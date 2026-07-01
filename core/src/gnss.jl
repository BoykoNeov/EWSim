# gnss.jl — GPS pseudorange positioning: the fix (trilateration), DOP, and RAIM
# (HANDOFF §9 REUSE milestone, slice 7 gate 1).
#
# This is the §9 SHARED-LIB payoff: the SAME `gauss_newton` scaffold that fixed a DF
# emitter (slice 5, N=2) trilaterates a GPS receiver here (N=4 — x, y, z, and the
# receiver clock bias c·b), and the SAME `(HᵀH)⁻¹` DOP math that drew a DF error
# ellipse computes GPS dilution-of-precision. gnss.jl adds only the GPS-SPECIFIC math
# (the pseudorange residual/Jacobian, the error-term models, the RAIM statistic +
# fault ID + exclude re-solve) and reuses the generalized geometry.jl/estimation.jl.
#
# Pure, no `w.rng`, dependency-free (base Julia + StaticArrays) — SI metres/seconds
# in/out. The whole slice is DETERMINISTIC given the drawn pseudoranges (the fix, DOP,
# RAIM are closed-form / fixed-iteration), so — like slices 2/4/5/6, unlike slice 3 —
# there is NO draw-topology hazard: the fidelity keys select only which error term /
# which post-processing enters, never a draw. The stochastic error terms (multipath,
# noise) take a PRE-DRAWN value (the draw lives in `observe!`, gate 2) so this file
# stays RNG-free.
#
# UNITS (the §1 trifecta on this surface): positions/pseudoranges/biases in METRES;
# the receiver clock unknown is carried as `c·b` in METRES (the standard GPS
# unknown-vector convention — keeps the 4×4 normal matrix well-scaled), converted to
# time (ns) only at the telemetry boundary (gate 2). A metres/seconds slip on the
# clock term (a factor of c ≈ 3e8) is this slice's signature bug — pinned by a
# round-trip test.

# The GPS fidelity mode constants — the SINGLE source of truth (the CFAR_MODES /
# ESTIMATOR_MODES / DEINTERLEAVER_MODES one-list-no-drift lesson). gate-2's
# `LIVE_FIDELITY_MODES` REFERENCES these, so gnss.jl precedes radar.jl in the include
# order. The five error terms each toggle independently; the RAIM rung has three states.
const GPS_TOGGLE = (:off, :on)                  # per-error-term toggle
const RAIM_MODES = (:off, :detect, :exclude)    # integrity-monitoring rung

# 3-vector Euclidean norm (no LinearAlgebra — the `_range` house style; gnss.jl is
# included before radar.jl so `_range` isn't in scope yet, and this is a hot inner call).
_norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

"""
    sat_az_el(sat::Vec3, rx::Vec3) -> (az, el)   (radians)

Azimuth and elevation of a satellite as seen from the receiver in the sim's flat-local
inertial frame (+z is "up"):

    el = atan(Δz, √(Δx²+Δy²)),   az = atan(Δy, Δx),   Δ = sat − rx

Used for the sky plot (gate 3) and the elevation-scaled error terms. Elevation is the
angle above the local horizontal; a low-elevation satellite (small `el`) sees more
atmosphere (larger iono/tropo obliquity) and worse multipath.
"""
function sat_az_el(sat::Vec3, rx::Vec3)
    d = sat - rx
    horiz = hypot(d[1], d[2])
    el = atan(d[3], horiz)
    az = atan(d[2], d[1])
    return az, el
end

# Elevation obliquity 1/sin(el): a low satellite's signal traverses a longer
# atmospheric slant path. Capped at el ≈ 2.87° (sin ≥ 0.05 → obliquity ≤ 20) so a
# near-horizon satellite can't blow the delay up unboundedly (the elevation mask drops
# these anyway; the cap is the "a live config can't crash a tick" guard).
_obliquity(el_rad) = 1.0 / max(sin(el_rad), 0.05)

"""
    iono_delay(el_rad, zenith_m) -> metres  (≥ 0, deterministic bias)

Ionospheric group delay: a positive range error (the signal is delayed), elevation-
scaled by the obliquity `zenith_m / sin(el)`. **Named approximation (HANDOFF §1): a
simple obliquity model, NOT Klobuchar.** Deterministic → toggling `iono` adds/removes
this bias with NO draw (the draw-topology invariant).
"""
iono_delay(el_rad, zenith_m) = zenith_m * _obliquity(el_rad)

"""
    tropo_delay(el_rad, zenith_m) -> metres  (≥ 0, deterministic bias)

Tropospheric delay: same elevation-scaled positive-bias shape as [`iono_delay`](@ref)
with its own zenith magnitude. **Named approximation: a simple mapping function, NOT
Saastamoinen.** Deterministic (no draw).
"""
tropo_delay(el_rad, zenith_m) = zenith_m * _obliquity(el_rad)

"""
    mp_scale(el_rad) -> factor  (≥ 1)

Multipath elevation weight: the drawn multipath term is `mp_scale(el)·σ_mp·randn`,
worse at low elevation (ground reflections). STOCHASTIC — the `randn` is drawn in
`observe!` (gate 2) and passed in; this weight is the deterministic elevation shape.
"""
mp_scale(el_rad) = _obliquity(el_rad)

"""
    pseudorange(sat, rx, cb; clock_err, fault_bias, iono, tropo, mp, noise) -> metres

Assemble the measured pseudorange for one satellite (the §1 model, HANDOFF §10 item 7):

    ρ = ‖sat − rx‖ + c·b + clock_err + fault_bias + iono + tropo + mp + noise

`cb` is the receiver clock bias `c·b` in metres (a SOLVED unknown — never an error
term). `clock_err` is the SATELLITE clock error (a per-SV constant bias; distinct from
`cb` — a common confusion, named). `fault_bias` is the injected spoof/failure bias
(RAIM scene). The five error terms are passed ALREADY TOGGLED (0.0 when off) and the
stochastic `mp`/`noise` already drawn — this assembler is a pure sum, no RNG, no
knowledge of the fidelity. **Named approximation: instantaneous signal travel — the
range is evaluated once per look, no light-time iteration** (a constant per-SV offset a
real receiver corrects, inert for the DOP/RAIM lesson).
"""
function pseudorange(sat::Vec3, rx::Vec3, cb::Float64;
                     clock_err::Float64 = 0.0, fault_bias::Float64 = 0.0,
                     iono::Float64 = 0.0, tropo::Float64 = 0.0,
                     mp::Float64 = 0.0, noise::Float64 = 0.0)
    return _norm3(sat - rx) + cb + clock_err + fault_bias + iono + tropo + mp + noise
end

# The GPS residual/Jacobian for the iterated LS. residual rⱼ = ρⱼ − (‖pⱼ−p̂‖ + ĉb);
# Jacobian row Hⱼ = [−ûⱼ, 1] (ûⱼ = unit LOS receiver→satellite; the trailing 1 is
# ∂ρ/∂(c·b)) — the classical GPS geometry matrix, the DF `[sinθ,−cosθ]` row's 4-D cousin.
function _gps_residual(sat_positions, rho, p)
    pr = SVector(p[1], p[2], p[3])
    n = length(rho)
    r = Vector{Float64}(undef, n)
    @inbounds for j in 1:n
        r[j] = rho[j] - (_norm3(sat_positions[j] - pr) + p[4])
    end
    return r
end

function _gps_jacobian(sat_positions, p)
    pr = SVector(p[1], p[2], p[3])
    n = length(sat_positions)
    rows = Vector{SVector{4, Float64}}(undef, n)
    @inbounds for j in 1:n
        d = sat_positions[j] - pr
        rng = max(_norm3(d), 1e-9)
        u = d / rng
        rows[j] = SVector(-u[1], -u[2], -u[3], 1.0)
    end
    return rows
end

"""
    position_fix(sat_positions, rho; seed = zero(Vec3), cb0 = 0.0, iters = 10)
        -> (pos::SVector{3}, cb::Float64, Q::Matrix, singular::Bool)

Trilaterate the receiver position (x, y, z) and clock bias `c·b` (metres) from the
pseudoranges `rho` to satellites at `sat_positions`. **Reuses the SHARED
[`gauss_newton`](@ref) scaffold at N = 4** (§9) — the pseudorange measurement is
nonlinear in `p_rx`, so the fix is iterated LS with the GPS residual/Jacobian
([`_gps_residual`](@ref)/[`_gps_jacobian`](@ref)). Equal-σ pseudoranges (the DOP lesson
premise — identical ranging accuracy, the GEOMETRY sets the error), so unit weights;
the returned `Q = (HᵀH)⁻¹` at the fix is the UNIT-variance DOP matrix
([`dop_components`](@ref) decomposes it). `singular` (< 4 satellites / coplanar) is
passed through so the readouts clamp to `FINITE_CEIL`.

Seeded at a fixed guess (`seed`/`cb0`, the scene origin — draw-free, so the fix is
deterministic); the fixed iteration count + divergence→seed fallback are inherited
unchanged from `gauss_newton`.
"""
function position_fix(sat_positions, rho; seed = zero(Vec3), cb0::Real = 0.0, iters::Integer = 10)
    n = length(rho)
    if n < 1                                               # empty → degenerate, no throw
        return zero(Vec3), 0.0, FINITE_CEIL .* _eye4(), true
    end
    p0 = Float64[seed[1], seed[2], seed[3], cb0]
    R = ones(Float64, n)                                   # equal σ → unit weights
    resid(p) = _gps_residual(sat_positions, rho, p)
    jac(p)   = _gps_jacobian(sat_positions, p)
    p, _ = gauss_newton(p0, resid, jac, R; iters = iters)
    pos = SVector{3, Float64}(p[1], p[2], p[3])
    cb  = p[4]
    Q, singular = dop(_gps_jacobian(sat_positions, p))     # DOP from the geometry at the fix
    return pos, cb, Q, singular
end

# 4×4 identity for the degenerate empty-satellite fallback (never a throw).
_eye4() = Float64[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]

"""
    raim_statistic(sat_positions, rho, pos, cb, sigma) -> stat

The RAIM test statistic on the range residuals: `stat = √(SSE/(n−4))` where
`SSE = Σⱼ (rⱼ/σ)²` (σ-normalized → DIMENSIONLESS, E[stat] ≈ 1 under H0). **Named
approximation of the parity-space method (single-fault, residual-RSS).** RAIM needs
OVER-determination — at `n ≤ 4` the residuals are ≈ 0 (no redundancy) and the statistic
is 0 (RAIM cannot see a fault; the scene must ship ≥ 5).
"""
function raim_statistic(sat_positions, rho, pos, cb, sigma)
    n = length(rho)
    dof = n - 4
    dof <= 0 && return 0.0
    sse = 0.0
    @inbounds for j in 1:n
        r = rho[j] - (_norm3(sat_positions[j] - pos) + cb)
        sse += (r / sigma)^2
    end
    return sqrt(sse / dof)
end

# Fault ID: the LARGEST NORMALIZED residual |rⱼ|/σ (named simplification of the
# max-slope / parity-vector single-fault ID). Returns the satellite index (0 if empty).
function raim_suspect(sat_positions, rho, pos, cb, sigma)
    n = length(rho)
    imax = 0; rmax = -1.0
    @inbounds for j in 1:n
        r = abs(rho[j] - (_norm3(sat_positions[j] - pos) + cb)) / sigma
        if r > rmax
            rmax = r; imax = j
        end
    end
    return imax
end

"""
    raim_solve(sat_positions, rho, sigma; mode, threshold, seed, cb0, iters)
        -> NamedTuple (pos, cb, Q, singular, flag, stat, used, fault_sat)

The full RAIM-aware fix. `mode ∈ RAIM_MODES`:
  • `:off`     — plain fix; the flag NEVER raises (the naïve baseline that trusts a
                 spoofed satellite — the lesson's "before" state).
  • `:detect`  — fix + [`raim_statistic`](@ref); `flag = stat > threshold` (fault
                 DETECTION only; raises the integrity flag).
  • `:exclude` — on alarm, identify the suspect by [`raim_suspect`](@ref), DROP it and
                 RE-SOLVE with n−1 (single-fault exclusion) — IFF that keeps ≥ 4
                 satellites; the fix snaps back toward truth and the flag is re-evaluated
                 on the retest. Re-solving is POST-DRAW (a filter on which measurements
                 enter the solve — it changes NO draw, the invariant).

`threshold` is an empirical σ-multiple on the dimensionless statistic (route (iii),
gate-1 probe decision — the χ²/Pfa route needs an erf-based inverse for the odd DOF
that exclusion produces; the empirical threshold works at every DOF and matches the
six-slice no-SpecialFunctions + probe-tune discipline). `used` is a Bool per satellite
(entered the final solve); `fault_sat` is the excluded index (0 if none).
"""
function raim_solve(sat_positions, rho, sigma;
                    mode::Symbol = :off, threshold::Real = 5.0,
                    seed = zero(Vec3), cb0::Real = 0.0, iters::Integer = 10)
    mode in RAIM_MODES || error("raim_solve: unknown mode :$mode ($(join(RAIM_MODES, " | ")))")
    n = length(rho)
    used = trues(n)
    fault_sat = 0
    pos, cb, Q, singular = position_fix(sat_positions, rho; seed = seed, cb0 = cb0, iters = iters)
    stat = raim_statistic(sat_positions, rho, pos, cb, sigma)

    mode === :off && return (; pos, cb, Q, singular, flag = false, stat, used, fault_sat)

    flag = stat > threshold
    mode === :detect && return (; pos, cb, Q, singular, flag, stat, used, fault_sat)

    # :exclude — drop the suspect and re-solve, keeping ≥ 4 satellites.
    if flag && (n - 1) >= 4
        sus = raim_suspect(sat_positions, rho, pos, cb, sigma)
        keep = [j for j in 1:n if j != sus]
        pos, cb, Q, singular = position_fix(sat_positions[keep], rho[keep];
                                            seed = seed, cb0 = cb0, iters = iters)
        stat = raim_statistic(sat_positions[keep], rho[keep], pos, cb, sigma)
        fault_sat = sus
        used[sus] = false
        flag = stat > threshold                          # residual flag after exclusion
    end
    return (; pos, cb, Q, singular, flag, stat, used, fault_sat)
end
