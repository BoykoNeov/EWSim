# estimation.jl — generic least-squares / Gauss-Newton scaffold + the bearings-only
# position fix (HANDOFF §9, slice 5 gate 1).
#
# Two layers, kept apart on purpose:
#   • A MEASUREMENT-AGNOSTIC scaffold — `linear_ls(A, b, W)` (the weighted 2×2
#     normal-equation solve) and `gauss_newton(p0, residual_fn, jacobian_fn, R;
#     iters)` (callback-based) — that GPS trilateration (slice 6) and the seeker
#     filter reuse with their OWN residual/Jacobian. The 2×2 inverse is closed-form
#     and dependency-free (the `_range` no-LinearAlgebra house style); GPS's 4
#     unknowns later swap only the inner inverse, not these signatures (advisor §9).
#   • `bearings_fix` — the ONE bearings-specific resident here (the staged gate needs
#     it at gate 1, before geolocation.jl exists; gate 2's `Geolocator` just calls it).
#     It builds the `[sin θ̂, −cos θ̂]` rows / the wrapped residual and calls the scaffold.
#
# Pure / no `w.rng` (the fix is closed-form for `:pseudolinear`, a fixed-iteration
# solve for `:ml`), so — like slices 2 and 4 — there is NO draw-topology hazard: the
# `:estimator` rung selects only post-processing, never a draw. 2-D azimuth-only.

# The estimator-fidelity rungs (slice 5). The SINGLE source of truth: `bearings_fix`
# validates against this, and gate-2's `LIVE_FIDELITY_MODES` will REFERENCE it (the
# `CFAR_MODES` one-list-no-drift lesson). Defined HERE (estimation.jl is included
# before radar.jl) so that reference needs no include-order gymnastics (advisor #5).
#   • :pseudolinear — closed-form, the BIASED baseline (noisy θ̂ sits in the regressor).
#   • :ml           — iterated Gauss-Newton seeded at pseudolinear, removes most bias.
const ESTIMATOR_MODES = (:pseudolinear, :ml)

# The seeker-fidelity rungs (slice 11) — the SINGLE source of truth for the `:seeker` key,
# defined HERE (estimation.jl precedes radar.jl) so gate-2's `LIVE_FIDELITY_MODES` REFERENCES
# it (the `ESTIMATOR_MODES`/`GUIDANCE_MODES` "mode-const-before-radar, one-list-no-drift"
# precedent) and `set_fidelity` picks it up with no server change.
#
# A GENUINELY NEW FIDELITY-CLASS COMBINATION — name it precisely, copy NEITHER template
# (advisor / gate-0 FINDINGS):
#   • DRAW-INVARIANT (class 4a, the slice-5 `:estimator` shape): BOTH rungs draw the SAME
#     one `randn(w.rng)` seeker sample every tick; the filter is pure post-processing → the
#     rung is INTRODUCIBLE via `set_fidelity` (UNLIKE `:cfar`, which flips draw topology), and
#     a `:raw↔:filtered` toggle never desyncs the RNG stream.
#   • YET TRAJECTORY-CHANGING (the slice-10 `:guidance` shape): the toggle selects WHICH `ω`
#     PN consumes (`:raw` → naïve finite-difference `λ̇`, `:filtered` → the α-β estimate), so it
#     MOVES the missile — NOT bit-identical (do NOT copy the slice-5 "toggle-bit-identical"
#     language), and NOT a dead knob.
# This is also the FIRST `w.rng` consumer in the missile arc: the slice-8/9/10 "RNG-is-vacuous"
# boilerplate INVERTS here — conventions 3 (unconditional draw) and 11 (own Xoshiro for MC)
# now APPLY. Byte-identity for slices 1–10 comes from the Seeker NOT EXISTING there, NOT from a
# draw-skipping `:truth` rung (there is none; "truth-fed PN" IS slice 10 — no Seeker).
#   • :raw      — the naïve foil: finite-difference consecutive noisy LOS angles
#     (`λ̇_raw = wrap(λ_meas − λ_prev)/dt`), amplifying the angle noise by `1/dt`.
#     PN's `N·Vc·λ̇_raw` then carries thousands of m/s² of noise → `a_max` pegs, the miss opens.
#   • :filtered — the α-β tracker (`alpha_beta_los_step`) estimates `λ̇` by predict–correct
#     WITHOUT differentiating → a smooth rate, PN leads to a tight intercept, saturation off.
#   • :scan     — slice-13 countermeasures: instead of ONE noisy truth bearing, the seeker forms
#     a NOISY angular-power PROFILE over a fixed `N_bins` grid (K lobes painted by
#     `paint_angular_profile!`, then the `2·N_p·N_bins` `randn` floor from `_draw_profile!`),
#     CFAR-DETECTS the peaks (`cfar_scan`, the slice-3 sandbox on the ANGLE axis), and resolves
#     the tracked bearing by `discrimination` (`:none` blend-all vs `:gated` α-β-gated). It is a
#     GENUINELY DIFFERENT CLASS from :raw/:filtered — a DRAW-TOPOLOGY FLIP (class 4b, the `:cfar`
#     shape): `1` randn/tick (:raw/:filtered) → `2·N_p·N_bins`/tick, so `set_fidelity` must REJECT
#     INTRODUCING or REMOVING it (gate 2, the cfar precedent) while `:raw↔:filtered` stay
#     introduce-safe — `SEEKER_MODES` gains MIXED introduce-safety. The measurement NOISE moved
#     into the profile floor (the `2·N_p·N_bins` draws), so `:scan` draws EXACTLY that (no +1
#     output `randn`) and the slice-11 `sigma_seek` slider goes INERT under it (documented, gate 2).
const SEEKER_MODES = (:raw, :filtered, :scan)

# The discrimination rungs (slice-13 countermeasures) — the peak-resolution selector for the
# `:scan` seeker, the SINGLE source of truth (gate-2's `LIVE_FIDELITY_MODES` REFERENCES it; the
# `SEEKER_MODES` one-list-no-drift, defined HERE so estimation.jl precedes radar.jl). A NESTED
# fidelity: DRAW-INVARIANT among its rungs (both build the SAME profile / SAME `2·N_p·N_bins`
# draws — they differ ONLY in post-detection peak SELECTION, zero extra draws → introduce-safe once
# `:scan` is on) YET TRAJECTORY-CHANGING (the toggle MOVES the missile — not a dead knob), and
# INERT unless `seeker=:scan` (no profile → no peaks → the key does nothing; the `:raim`-without-GPS
# coupling). NOT the free-standing class-4a of slice-11 `:seeker` — it is "draw-invariant within a
# 4b host" (the copy-paste false-claim trap, convention 4c).
#   • :none  — the intensity-weighted centroid of ALL detected peaks (`intensity_centroid`) → the
#     brighter/separating decoy lobe drags the blend OFF the target → the seeker is SEDUCED.
#   • :gated — the nearest-neighbor peak to the α-β PREDICTED bearing within a gate half-width
#     (`validation_gate`; coast on the prediction if none is in-gate) → the RGPO track-gate rejects
#     the separated decoy lobe → the seeker HOLDS the true target. CFAR alone cannot reject a
#     brighter decoy; this α-β predicted-LOS association is the discriminator (HANDOFF §9).
const DISCRIMINATION_MODES = (:none, :gated)

# Solve the weighted 2×2 normal equations M·p = g and return (p, cov = M⁻¹), with a
# RELATIVE det floor (NOT an absolute one — det carries units and scales with sensor
# count and 1/R̂, so an absolute floor is scale-fragile; advisor). For a PSD M,
# det ∈ [0, m11·m22]; flooring it keeps a near-singular (collinear) solve huge-but-
# FINITE rather than NaN — the readouts then clamp to FINITE_CEIL at the consumer.
#
# **Kept 2×2-closed-form for the pseudolinear DF baseline (slice-7 fallback (a)).** The
# GPS generalization made `gauss_newton` N-dim (DF `:ml` and GPS both call it — the §9
# reuse that MATTERS), but the pseudolinear `linear_ls` normal matrix has a TINY leading
# pivot (the down-range/x information is the small one), which the natural-order N-dim
# Cholesky handles less stably than this direct-det cofactor on shallow-geometry noisy
# draws (a mean-shifting difference the slice-5 bias MC test catches). GPS never uses
# `linear_ls`, so keeping the stable 2×2 here costs nothing and the reuse story stays
# honest — the shared *scaffold* is `gauss_newton`/`_solve_normal`, not this baseline.
function _solve2x2(m11::Float64, m12::Float64, m22::Float64, g1::Float64, g2::Float64)
    det   = m11 * m22 - m12 * m12
    floor = 1e-12 * (m11 * m22 + 1.0)          # relative ridge; +1 guards a degenerate M≈0
    det < floor && (det = floor)
    i11 =  m22 / det; i12 = -m12 / det; i22 = m11 / det     # M⁻¹ (symmetric)
    p   = SVector(i11 * g1 + i12 * g2, i12 * g1 + i22 * g2)
    cov = SMatrix{2, 2, Float64}(i11, i12, i12, i22)
    return p, cov
end

# Assemble the weighted normal equations from measurement rows: the N×N symmetric
# `M = Σᵢ wᵢ·hᵢ·hᵢᵀ` and the RHS `g = Σᵢ wᵢ·hᵢ·bᵢ`. Generic over the row length `N`
# (used by `gauss_newton` at N=2 for DF and N=4 for GPS) feeding the ONE shared
# [`_solve_normal`](@ref) (§9 reuse). Streaming summation (no dense H), no LinearAlgebra.
function _normal_eqs(rows, rhs, w, N::Integer)
    M = zeros(Float64, N, N)
    g = zeros(Float64, N)
    @inbounds for i in eachindex(rhs)
        h = rows[i]; wi = w[i]; bi = rhs[i]
        for a in 1:N
            wha = wi * h[a]
            g[a] += wha * bi
            for c in a:N
                M[a, c] += wha * h[c]
            end
        end
    end
    @inbounds for a in 1:N, c in 1:a-1; M[a, c] = M[c, a]; end   # symmetrize
    return M, g
end

"""
    linear_ls(A, b, W) -> (p::SVector{2}, cov::SMatrix{2,2})

Weighted linear least squares for a 2-parameter model: solve the normal equations
`(AᵀWA)·p = AᵀW·b` and return the estimate `p` and its covariance `cov = (AᵀWA)⁻¹`
(at unit residual variance — `W` already carries the measurement weighting). `A` is
an iterable of 2-element rows `Aᵢ`, `b` and `W` are vectors (`W` the DIAGONAL of the
weight matrix). The 2×2 normal matrix is accumulated by summation and inverted in
closed form via [`_solve2x2`](@ref) (no LinearAlgebra). Generic / measurement-agnostic —
the DF pseudolinear baseline builds its own `A`/`W` and calls this.
"""
function linear_ls(A, b, W)
    m11 = 0.0; m12 = 0.0; m22 = 0.0; g1 = 0.0; g2 = 0.0
    @inbounds for i in eachindex(b)
        a1 = A[i][1]; a2 = A[i][2]; w = W[i]; bi = b[i]
        wa1 = w * a1; wa2 = w * a2
        m11 += wa1 * a1; m12 += wa1 * a2; m22 += wa2 * a2
        g1  += wa1 * bi; g2  += wa2 * bi
    end
    return _solve2x2(m11, m12, m22, g1, g2)
end

# Weighted residual sum of squares Σ rᵢ²/Rᵢ (R = diagonal measurement variances).
function _wrss(r, R)
    s = 0.0
    @inbounds for i in eachindex(r)
        s += r[i]^2 / R[i]
    end
    return s
end

"""
    gauss_newton(p0, residual_fn, jacobian_fn, R; iters = 8) -> (p::Vector, cov::Matrix)

Fixed-iteration Gauss-Newton for an **N-parameter** nonlinear least squares (N inferred
from `length(p0)` — 2 for the DF bearings fix, 4 for the GPS trilateration fix, the
§9 shared scaffold). `residual_fn(p)` returns the residual vector `r` (already wrapped
for angles), `jacobian_fn(p)` returns the Jacobian `H` (iterable of N-rows, `∂model/∂p`),
and `R` is the DIAGONAL vector of measurement variances. Each step solves
`Δ = (HᵀR⁻¹H)⁻¹ HᵀR⁻¹ r` via [`_solve_normal`](@ref), `p ← p + Δ`; the returned
`cov = (HᵀR⁻¹H)⁻¹` at the final `p`. Returns plain `Vector`/`Matrix` (dimension-generic);
the 2-D `bearings_fix` wraps them back to `SVector{2}`/`SMatrix{2,2}`.

**Fixed iteration COUNT, not until-convergence** (named approximation, HANDOFF §1):
"N-step Gauss-Newton" keeps a tick bounded and bit-reproducible — a `while !converged`
loop could spin under bad geometry and stall the tick non-deterministically.

**Divergence → seed fallback (advisor #6).** A fixed count bounds time, not the
result: a GN step under bad geometry can overshoot to a non-finite `p̂` or grow the
residual. So a step that yields a non-finite `p` OR a larger weighted residual norm is
REJECTED and the loop stops, keeping the last good `p` — and since callers seed `p0`
at a sensible guess (pseudolinear for DF, the scene origin for GPS), the worst case is
"no better than the seed," never NaN / never a spin.
"""
function gauss_newton(p0, residual_fn, jacobian_fn, R; iters::Integer = 8)
    N     = length(p0)
    p     = collect(Float64, p0)                       # mutable N-vector
    Winv  = [1.0 / Ri for Ri in R]                     # HᵀR⁻¹H weights (R constant across steps)
    rnorm = _wrss(residual_fn(p), R)
    for _ in 1:iters
        M, g  = _normal_eqs(jacobian_fn(p), residual_fn(p), Winv, N)
        Δ, _, _ = _solve_normal(M, g)
        pnew  = p .+ Δ
        all(isfinite, pnew) || break                   # divergence → keep last good p
        rnew  = _wrss(residual_fn(pnew), R)
        rnew > rnorm && break                          # step grew the residual → reject
        p = pnew; rnorm = rnew
    end
    M, g = _normal_eqs(jacobian_fn(p), residual_fn(p), Winv, N)
    _, cov, _ = _solve_normal(M, g)                    # cov at the final fix
    return p, cov
end

"""
    bearings_fix(thetas, positions, sigmas; estimator = :pseudolinear, iters = 8)
        -> (pos::SVector{2}, cov::SMatrix{2,2})

Bearings-only (angle-of-arrival) position fix in the x-y plane. `thetas[i]` is the
MEASURED bearing from sensor `positions[i]` (a `Vec3`/2-vector, z ignored) with
1-σ accuracy `sigmas[i]` (radians). Returns the 2-D estimate and its linearized
covariance `(HᵀR⁻¹H)⁻¹` — the ellipse C for [`error_ellipse`](@ref).

`:pseudolinear` — each bearing is the line `sin θ̂ᵢ·(x−xᵢ) − cos θ̂ᵢ·(y−yᵢ) = 0`;
stack rows `Aᵢ = [sin θ̂ᵢ, −cos θ̂ᵢ]`, RHS `bᵢ = xᵢ sin θ̂ᵢ − yᵢ cos θ̂ᵢ`, and solve by
weighted [`linear_ls`](@ref). The closed-form BIASED baseline (named approximation,
HANDOFF §1): the noisy `θ̂` sits inside `A`, correlating the regressor with the error
— worst at long range / shallow crossings.

**Weighting (named two-pass; the watch-item that an inconsistent R̂ᵢ biases the fix):**
`Wᵢ = 1/(σᵢ²·R̂ᵢ²)` is the perpendicular-offset variance, but R̂ᵢ (sensor→emitter
range) is unknown a priori. So a first pass with σ-only weights `1/σᵢ²` gives a seed,
R̂ᵢ = ‖seed − sensorᵢ‖ is computed ONCE, and a single re-weighted solve follows (NOT
iterated to convergence — that drifts into IRLS and complicates determinism). The
SAME R̂ᵢ feeds the weights everywhere.

`:ml` — iterated [`gauss_newton`](@ref) SEEDED at the pseudolinear fix (so `:ml`
computes the pseudolinear solution first — deterministic, no extra draws, the rung
switch stays draw-free). Residual `rᵢ = wrap(θ̂ᵢ − atan(ŷ−yᵢ, x̂−xᵢ))`, Jacobian row
`Hᵢ = [−sin θᵢ(p)/R̂ᵢ, cos θᵢ(p)/R̂ᵢ]` (the model bearing at the current estimate; at
the fix it coincides with θ̂ᵢ to O(residual)). Removes most of the pseudolinear bias.
"""
function bearings_fix(thetas, positions, sigmas;
                      estimator::Symbol = :pseudolinear, iters::Integer = 8)
    n = length(thetas)
    x(i) = positions[i][1]
    y(i) = positions[i][2]

    # Pseudolinear lines: Aᵢ·p = bᵢ.
    A = [SVector(sin(thetas[i]), -cos(thetas[i])) for i in 1:n]
    b = [x(i) * sin(thetas[i]) - y(i) * cos(thetas[i]) for i in 1:n]

    # Pass 1 — σ-only seed weights to get R̂ᵢ.
    W0 = [1.0 / sigmas[i]^2 for i in 1:n]
    seed, _ = linear_ls(A, b, W0)
    Rhat = [max(hypot(seed[1] - x(i), seed[2] - y(i)), 1e-6) for i in 1:n]

    # Pass 2 — perpendicular-offset weights Wᵢ = 1/(σᵢ²R̂ᵢ²); covpl ≡ (HᵀR⁻¹H)⁻¹.
    W = [1.0 / (sigmas[i]^2 * Rhat[i]^2) for i in 1:n]
    ppl, covpl = linear_ls(A, b, W)

    estimator === :pseudolinear && return ppl, covpl

    if estimator === :ml
        Rdiag = [sigmas[i]^2 for i in 1:n]
        resid(p) = [wrap_angle(thetas[i] - atan(p[2] - y(i), p[1] - x(i))) for i in 1:n]
        function jac(p)
            rows = Vector{SVector{2, Float64}}(undef, n)
            @inbounds for i in 1:n
                dx = p[1] - x(i); dy = p[2] - y(i); R2 = dx * dx + dy * dy
                R2 = max(R2, 1e-12)
                rows[i] = SVector(-dy / R2, dx / R2)   # [−sinθ/R, cosθ/R]
            end
            return rows
        end
        p, cov = gauss_newton(ppl, resid, jac, Rdiag; iters = iters)
        return SVector{2, Float64}(p[1], p[2]),
               SMatrix{2, 2, Float64}(cov[1,1], cov[2,1], cov[1,2], cov[2,2])
    end

    error("bearings_fix: unknown estimator :$estimator ($(join(ESTIMATOR_MODES, " | ")))")
end

# A tiny dt floor for the rate-correction divide (`β/dt`). estimation.jl precedes frames.jl,
# so it can't borrow `_FRAME_EPS` — a local literal of the same 1e-12 magnitude. An EXACT no-op
# at the tick `dt = 1e-3` (so it never perturbs the probe-validated behaviour); it only guards a
# live `dt→0` from a divide-by-zero (the `autopilot_step` τ-floor precedent — clamp at consumer).
const _ALPHA_BETA_DT_FLOOR = 1e-12

"""
    alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α = 0.3, β = 0.05) -> (λ_est′, λ̇_est′)

One predict–correct step of an **α-β tracker** on a SCALAR line-of-sight ANGLE `λ` (radians,
in the engagement plane) and its rate `λ̇` (rad/s) — the recursive seeker LOS-rate filter
HANDOFF §10.11 names. **A NEW primitive, not a `gauss_newton`/`bearings_fix` reuse:** those
batch neighbours are least-squares over a fixed measurement set; a seeker filter is RECURSIVE
(predict–correct across ticks). Estimating the rate this way is the whole slice-11 lesson —
it produces `λ̇` WITHOUT differentiating the noisy angle (the `:raw` finite-difference foil
amplifies noise by `1/dt`; this does not).

    λ_pred = λ_est + λ̇_est·dt                     (predict: the LOS keeps rotating at λ̇_est)
    r      = wrap(λ_meas − λ_pred)                 (wrapped innovation — the ±π branch guard)
    λ_est′ = λ_pred + α·r                          (correct the angle)
    λ̇_est′ = λ̇_est + (β/dt)·r                      (correct the rate — the divide dt is floored)

**SCALAR in-plane, NOT the vector-on-direction form** (gate-0 FINDINGS decision 3): the slice-11
engagement is planar in x-z, so `ω ∥ ±y` and `λ = atan(Δz, Δx)` is well-conditioned (the LOS
never approaches vertical → no atan2 singularity). Scalar avoids the vector form's tangent-
injection / cross-innovation-sign / renormalize bug surface. The Seeker (gate 2) reconstructs
`ω = Vec3(0, −λ̇_est, 0)` for PN from this scalar rate.

`α ∈ (0,1)` (angle gain) and `β > 0` (rate gain) trade tracking lag vs noise rejection — larger
`β` tracks faster / smooths less. **The gains are tuned for CLOSED-LOOP miss (a U-shape in β —
gate 0 / gate 2), NOT open-loop variance** (over-smoothing trades noise for lag near CPA); this
primitive is only the recursive step. RNG-free and dependency-free (`wrap_angle` only, the §12
house style — no LinearAlgebra); the noise is injected in the Seeker BEFORE this is called, so
the filter is deterministic post-processing. `dt→0` is floored (no divide-by-zero → no NaN); a
huge `λ_meas` is bounded by `wrap_angle` → the step never throws / never NaNs (the caller
validates `α`/`β` at load — gate 2 — this stays a safe pure primitive).
"""
function alpha_beta_los_step(λ_est::Real, λ̇_est::Real, λ_meas::Real, dt::Real;
                             α::Real = 0.3, β::Real = 0.05)
    dt_c   = max(Float64(dt), _ALPHA_BETA_DT_FLOOR)   # floor ONLY the β/dt divide (predict is divide-free)
    λ_pred = λ_est + λ̇_est * dt
    r      = wrap_angle(λ_meas - λ_pred)              # wrapped innovation (±π branch)
    λ_est′ = λ_pred + α * r
    λ̇_est′ = λ̇_est + (β / dt_c) * r
    return λ_est′, λ̇_est′
end

# =====================================================================================
# Slice-13 countermeasures — the seeker angular-profile processing primitives (gate 1).
#
# The slice-3 CFAR RANGE sandbox lifted onto the LOS-ANGLE axis: paint a beam-shaped lobe
# per return over a FIXED angular grid, add the noisy floor (`_draw_profile!`, radar.jl,
# UNCHANGED), CFAR-detect the peaks (`cfar_scan`, detection.jl, UNCHANGED — its power-vector
# + cell-index signature is already generic), then resolve the tracked bearing by the
# `discrimination` rung. These FOUR functions are the PURE, RNG-free, dependency-free
# (`wrap_angle` only, the §12 house style — no LinearAlgebra) processing layer; the noise is
# injected UPSTREAM by `_draw_profile!`, so they carry NO draw-topology hazard themselves.
#
# THE ±π SEAM is the trap: bearings are `atan(Δz, Δx) ∈ [−π, π]`, and a naïve weighted mean
# bugs at the branch cut — so every centroid/gate/innovation averages WRAPPED deltas about a
# REFERENCE bearing (the §1 wrap trifecta, the slice-5 `wrap_angle` precedent).
# =====================================================================================

"""
    angular_grid(boresight, N_bins, bin_w) -> Vector{Float64}

The FIXED angular bin-center grid for the `:scan` seeker — `N_bins` cells of width `bin_w`
(rad) centered on `boresight`: `grid[i] = boresight + (i − (N_bins+1)/2)·bin_w`, i ∈ 1:N_bins,
ascending. For even `N_bins` the boresight falls BETWEEN the two central bins (bin `N/2` at
`−bin_w/2`, bin `N/2+1` at `+bin_w/2`); for odd `N_bins` the center bin sits EXACTLY on the
boresight. Length is `N_bins` REGARDLESS of `boresight` — the determinism grid: `_draw_profile!`
draws `2·N_p·N_bins` `randn` independent of geometry (convention 3, the draw-count keystone).

**A TINY TESTED helper on purpose (gate-1 forward-flag):** the ±π-wrap is handled by the painted
delta (`paint_angular_profile!`) and the centroid/gate references, but the bin CENTERING
`(i−(N_bins+1)/2)·bin_w` is its own off-by-one trap — a half-bin shift misaligns the whole
profile vs boresight and only the coarse closed-loop numbers might catch it. Pinned by a closed-
form round-trip so it can't hide in `observe!`.

**NOT wrapped to [−π,π]:** the seeker FOV is a small window (span `N_bins·bin_w`, ±0.16 rad in the
slice-13 config) about the LOS, which stays clear of the ±π seam in the planar x-z engagement (the
slice-11 "λ never vertical" well-conditioning). Keeping the grid MONOTONIC ascending is what
`extract_peaks`' contiguous-run clustering needs; the seam guard lives in the wrapped deltas, not
here. Pure / dependency-free.
"""
function angular_grid(boresight::Real, N_bins::Integer, bin_w::Real)
    c   = (N_bins + 1) / 2                          # the fractional center index (N/2+½ for even N)
    b   = Float64(boresight); bw = Float64(bin_w)
    return [b + (i - c) * bw for i in 1:N_bins]
end

"""
    paint_angular_profile!(power, grid, sources; σ_beam, floor = 1.0) -> power

Paint the DETERMINISTIC linear-power angular profile for the `:scan` seeker. Start every
cell at the homogeneous `floor` (the noise level the CFAR α calibrates against — the
slice-3 convention), then ADD a beam-shaped Gaussian lobe `amp·exp(−½(Δλ/σ_beam)²)` for
each `(λ_source, amp)` in `sources`, with `Δλ = wrap_angle(grid[i] − λ_source)` (the ±π
seam guard). `grid` is the fixed vector of bin-center bearings (rad); `power` is written in
place (`length(power) == length(grid)`).

**The determinism keystone (convention 3): K returns paint K lobes onto the SAME fixed
grid.** The profile LENGTH — and hence the downstream `_draw_profile!` draw count
(`2·N_p·N_bins`) — is INDEPENDENT of how many sources there are: paint-then-draw-the-fixed-
grid, NEVER draw-per-return (a per-return draw would desync replay the instant a decoy
blooms). The Gaussian lobe is a named approximation (no sidelobes at this fidelity;
sinc/boxcar are alternatives). Pure / RNG-free — the noisy floor is added afterward by
`_draw_profile!` in the Seeker (gate 2).
"""
function paint_angular_profile!(power, grid, sources; σ_beam::Real, floor::Real = 1.0)
    fill!(power, floor)
    @inbounds for (λs, amp) in sources
        for i in eachindex(grid)
            d = wrap_angle(grid[i] - λs)
            power[i] += amp * exp(-0.5 * (d / σ_beam)^2)
        end
    end
    return power
end

"""
    intensity_centroid(peaks) -> λ_c::Float64   (or `nothing` if `peaks` is empty)

Intensity-weighted mean bearing of `peaks` (an iterable of `(λ, weight)` tuples), computed
WRAP-SAFELY about the strongest-weight bearing `λ_ref`:

    λ_c = wrap_angle(λ_ref + Σ wᵢ·wrap_angle(λᵢ − λ_ref) / Σ wᵢ)

Averaging WRAPPED deltas about a reference (not a naïve mean) is the ±π seam guard — a
target near +π and a decoy near −π blend to the true midpoint, NOT a jump to 0 (the slice-5
wrap trap). Choosing `λ_ref` = the strongest peak's OWN bearing makes it self-contained (no
external reference) and gives the **additivity anchor**: a SINGLE peak returns its bearing
EXACTLY (`wrap(λ−λ)=0` → `wrap(λ)=λ`, bit-exact for an already-wrapped `λ ∈ [−π, π]`).
Used BOTH within a cluster (`extract_peaks`, the peak angle) AND across peaks (the `:none`
blend). Pure / wrap-safe (`wrap_angle` only).
"""
function intensity_centroid(peaks)
    isempty(peaks) && return nothing
    λ_ref = 0.0; w_ref = -Inf                          # the strongest-weight bearing = the wrap reference
    for (λ, w) in peaks
        w > w_ref && (w_ref = w; λ_ref = λ)
    end
    num = 0.0; den = 0.0
    for (λ, w) in peaks
        num += w * wrap_angle(λ - λ_ref); den += w
    end
    den == 0.0 && return λ_ref                         # degenerate all-zero weights → the reference bearing
    return wrap_angle(λ_ref + num / den)
end

"""
    extract_peaks(grid, z, detections) -> Vector{Tuple{Float64, Float64}}

Cluster CONTIGUOUS runs of `detections[i] == true` in the scanned profile `z` into peaks.
Each contiguous run `[i, j−1]` becomes one `(λ_peak, strength)`: `λ_peak` is the
`intensity_centroid` of the run's bin bearings `grid[k]` weighted by their scanned power
`z[k]` (a power-weighted, wrap-safe centroid → sub-bin angular resolution), and `strength =
Σ z[k]` over the run (the peak's total power, the centroid weight for the `:none` blend and
the association strength). Peaks are returned in grid (ascending-bin) order; NO detections
→ an EMPTY vector (the Seeker then coasts on the α-β prediction — never tracks nothing).
`grid`, `z`, `detections` share the fixed grid length. Pure.
"""
function extract_peaks(grid, z, detections)
    peaks = Tuple{Float64, Float64}[]
    n = length(grid)
    i = 1
    @inbounds while i <= n
        if detections[i]
            j = i
            while j <= n && detections[j]; j += 1; end       # [i, j−1] is one contiguous run
            cluster  = [(grid[k], z[k]) for k in i:j-1]
            strength = 0.0
            for k in i:j-1; strength += z[k]; end
            push!(peaks, (intensity_centroid(cluster), strength))
            i = j
        else
            i += 1
        end
    end
    return peaks
end

"""
    validation_gate(peaks, λ_pred, halfwidth) -> λ::Float64   (or `nothing`)

The RGPO track-GATE / nearest-neighbor association — the discriminator (`:gated`). Returns
the bearing of the peak NEAREST the α-β predicted bearing `λ_pred`, but only if it lies
within `halfwidth` of the prediction (`|wrap_angle(λ − λ_pred)| ≤ halfwidth`); otherwise
`nothing` (COAST — the caller holds `λ_pred`, NEVER tracks a peak outside the gate). Empty
`peaks` → `nothing`.

This is what rejects a SEPARATED decoy: once the decoy lobe leaves the gate about the
target-locked prediction, the nearest IN-gate peak is the target's and the brighter decoy is
ignored. CFAR alone cannot reject a brighter decoy (a bright decoy is a strong DETECTION, not
a rejection) — the α-β predicted-LOS ASSOCIATION is the discriminator (HANDOFF §9: the seeker
walked off by a decoy IS the RGPO model; the gate is precisely what RGPO captures and drags).
Nearest-neighbor + a hard `halfwidth` reject (NOT keep-all-in-gate-then-centroid, which
re-blends the decoy and makes `:gated` worse than `:none` — gate-0 FINDINGS). Pure / wrap-safe.
"""
function validation_gate(peaks, λ_pred::Real, halfwidth::Real)
    best_λ = 0.0; best_d = Inf
    for (λ, _) in peaks
        d = abs(wrap_angle(λ - λ_pred))
        d < best_d && (best_d = d; best_λ = λ)
    end
    return best_d <= halfwidth ? best_λ : nothing
end
