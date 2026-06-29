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

# Solve the weighted 2×2 normal equations M·p = g and return (p, cov = M⁻¹), with a
# RELATIVE det floor (NOT an absolute one — det carries units and scales with sensor
# count and 1/R̂, so an absolute floor is scale-fragile; advisor). For a PSD M,
# det ∈ [0, m11·m22]; flooring it keeps a near-singular (collinear) solve huge-but-
# FINITE rather than NaN — the readouts then clamp to FINITE_CEIL at the consumer.
function _solve2x2(m11::Float64, m12::Float64, m22::Float64, g1::Float64, g2::Float64)
    det   = m11 * m22 - m12 * m12
    floor = 1e-12 * (m11 * m22 + 1.0)          # relative ridge; +1 guards a degenerate M≈0
    det < floor && (det = floor)
    i11 =  m22 / det; i12 = -m12 / det; i22 = m11 / det     # M⁻¹ (symmetric)
    p   = SVector(i11 * g1 + i12 * g2, i12 * g1 + i22 * g2)
    cov = SMatrix{2, 2, Float64}(i11, i12, i12, i22)
    return p, cov
end

"""
    linear_ls(A, b, W) -> (p::SVector{2}, cov::SMatrix{2,2})

Weighted linear least squares for a 2-parameter model: solve the normal equations
`(AᵀWA)·p = AᵀW·b` and return the estimate `p` and its covariance `cov = (AᵀWA)⁻¹`
(at unit residual variance — `W` already carries the measurement weighting). `A` is
an iterable of 2-element rows `Aᵢ`, `b` and `W` are vectors (`W` the DIAGONAL of the
weight matrix). The 2×2 normal matrix is accumulated by summation and inverted in
closed form (no LinearAlgebra). Generic / measurement-agnostic — `bearings_fix` and
(later) GPS build their own `A`/`W` and call this.
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

# Normal-equation pieces for A = H rows weighted by W = 1/R: returns the solve of
# (HᵀR⁻¹H)·Δ = HᵀR⁻¹·r and cov = (HᵀR⁻¹H)⁻¹. Shared by a GN step and the final cov.
function _normal_solve(H, r, R)
    m11 = 0.0; m12 = 0.0; m22 = 0.0; g1 = 0.0; g2 = 0.0
    @inbounds for i in eachindex(r)
        h1 = H[i][1]; h2 = H[i][2]; w = 1.0 / R[i]; ri = r[i]
        wh1 = w * h1; wh2 = w * h2
        m11 += wh1 * h1; m12 += wh1 * h2; m22 += wh2 * h2
        g1  += wh1 * ri; g2  += wh2 * ri
    end
    return _solve2x2(m11, m12, m22, g1, g2)
end

"""
    gauss_newton(p0, residual_fn, jacobian_fn, R; iters = 8) -> (p::SVector{2}, cov::SMatrix{2,2})

Fixed-iteration Gauss-Newton for a 2-parameter nonlinear least squares.
`residual_fn(p)` returns the residual vector `r` (already wrapped for angles),
`jacobian_fn(p)` returns the Jacobian `H` (iterable of 2-rows, `∂model/∂p`), and `R`
is the DIAGONAL vector of measurement variances. Each step solves
`Δ = (HᵀR⁻¹H)⁻¹ HᵀR⁻¹ r`, `p ← p + Δ`; the returned `cov = (HᵀR⁻¹H)⁻¹` at the final `p`.

**Fixed iteration COUNT, not until-convergence** (named approximation, HANDOFF §1):
"N-step Gauss-Newton" keeps a tick bounded and bit-reproducible — a `while !converged`
loop could spin under bad geometry and stall the tick non-deterministically.

**Divergence → seed fallback (advisor #6).** A fixed count bounds time, not the
result: a GN step under bad geometry can overshoot to a non-finite `p̂` or grow the
residual. So a step that yields a non-finite `p` OR a larger weighted residual norm is
REJECTED and the loop stops, keeping the last good `p` — and since callers seed `p0`
at the pseudolinear fix, the worst case is "no better than pseudolinear," never
NaN / never a spin.
"""
function gauss_newton(p0, residual_fn, jacobian_fn, R; iters::Integer = 8)
    p     = SVector{2, Float64}(p0[1], p0[2])
    rnorm = _wrss(residual_fn(p), R)
    for _ in 1:iters
        Δ, _  = _normal_solve(jacobian_fn(p), residual_fn(p), R)
        pnew  = p + Δ
        all(isfinite, pnew) || break                 # divergence → keep last good p
        rnew  = _wrss(residual_fn(pnew), R)
        rnew > rnorm && break                          # step grew the residual → reject
        p = pnew; rnorm = rnew
    end
    _, cov = _normal_solve(jacobian_fn(p), residual_fn(p), R)   # cov at the final fix
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
        return gauss_newton(ppl, resid, jac, Rdiag; iters = iters)
    end

    error("bearings_fix: unknown estimator :$estimator ($(join(ESTIMATOR_MODES, " | ")))")
end
