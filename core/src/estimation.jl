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
const SEEKER_MODES = (:raw, :filtered)

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
