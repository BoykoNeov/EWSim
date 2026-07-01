# geometry.jl — shared geometry / DOP primitives (HANDOFF §9, slice 5 gate 1).
#
# The §9 SHARED LIB that GPS-DOP and the seeker filter reuse later, so the
# signatures are deliberately MEASUREMENT-AGNOSTIC: `gdop`, `error_ellipse`,
# `eig2x2` consume a geometry/Jacobian matrix `H` or a covariance `C` and know
# nothing about angles. Only `bearing`/`wrap_angle` are angle-specific (DF needs
# them; GPS does not). When GPS (4 unknowns) lands, the CALL SITES are unchanged —
# only the inner 2×2 inverse generalises (the honest reading of "reuse"; advisor).
#
# Pure, no `w.rng`, dependency-free closed-form 2×2 (no LinearAlgebra — the `_range`
# house style). Everything is SI Float64.
#
# 2-D AZIMUTH-ONLY throughout (named approximation, HANDOFF §1): positions carry a
# z, but bearings/fix/covariance/ellipse all live in the x-y (plan) plane; z is
# ignored for the angle. A 3-D AOA ellipsoid is a future extension.
#
# Units / frames / SIGNS are the bug trifecta (HANDOFF §1): a bearing is an angle,
# so the `atan(Δy, Δx)` argument order and the residual WRAP are first-class here
# and pinned from day one (a flipped atan2 is exactly the LOS-rate-sign bug class).

# A large-but-finite anti-Inf/NaN ceiling for the DOP / covariance-axis readouts.
# A singular geometry (collinear sensors, emitter on the baseline) drives the 2×2
# inverse → ∞; `lin2db`-class +Inf/NaN would poison the JSON state frame (the
# recurring slice-1 `%g` / slice-2 null / slice-3 array watch-item). So the readouts
# clamp here to a value far above any real DOP (dimensionless ~1–100) or ellipse
# axis (metres, ~10–10⁴ for our scenarios) — it is an anti-poison guard, NOT a
# physical bound. The wire cap (gate 2/3) REUSES this constant so there is one
# ceiling and no drift (advisor).
const FINITE_CEIL = 1.0e9

"""
    bearing(from::Vec3, to::Vec3) -> θ   (radians, in [−π, π])

True azimuth from `from` to `to` in the x-y (plan) plane:

    θ = atan(Δy, Δx),   Δ = to − from

**2-D azimuth-only** (HANDOFF §1): the z components are ignored — this is the
planar bearing a DF sensor measures. The `atan(Δy, Δx)` argument order is the sign
convention, pinned and tested in all four quadrants (the §1 trifecta).
"""
bearing(from::Vec3, to::Vec3) = atan(to[2] - from[2], to[1] - from[1])

"""
    wrap_angle(θ) -> θ′   (radians, in [−π, π])

Wrap an angle (or an angular residual) into the principal interval via
`rem(θ, 2π, RoundNearest)`. Used for **every** angular residual `wrap(θ̂ − θ)`:
an unwrapped residual near ±π injects a ~2π error and yanks the fix (the §1 bug
class). The boundaries map to ±π; the magnitude of any wrapped residual is ≤ π.
"""
wrap_angle(θ::Real) = rem(float(θ), 2π, RoundNearest)

"""
    eig2x2(C) -> (λ₁ ≥ λ₂, angle)

Closed-form eigendecomposition of the **symmetric** 2×2 matrix
`C = [a b; b c]` (no LinearAlgebra):

    λ = (a+c)/2 ± √( ((a−c)/2)² + b² ),     angle = ½·atan(2b, a−c)

Returns the larger eigenvalue first and the principal-axis `angle` in (−π/2, π/2]
(an eigenvector orientation — it **wraps** at the ±90° boundary, tested). `C` is
read as `C[1,1]`, `C[1,2]`, `C[2,2]` (its symmetry is assumed, not enforced).
"""
function eig2x2(C)
    a = C[1, 1]; b = C[1, 2]; c = C[2, 2]
    m = (a + c) / 2
    d = sqrt(((a - c) / 2)^2 + b^2)
    λ1 = m + d
    λ2 = m - d
    ang = 0.5 * atan(2b, a - c)
    return (λ1, λ2, ang)
end

"""
    error_ellipse(C; nsigma = 1) -> (a, b, angle)

The `nsigma`-σ error ellipse of the 2×2 position covariance `C`: semi-axes
`a = nsigma·√λ₁ ≥ b = nsigma·√λ₂` and orientation `angle` (radians), from
[`eig2x2`](@ref). Because `C` carries the actual σθ (it is `(HᵀR⁻¹H)⁻¹`,
[`bearings_fix`](@ref)), the axes **scale linearly with σθ** — the live-slider
lesson. Under bad geometry `C` is large and the ellipse elongates **along the LOS**
(down-range), the GDOP lesson.

Named approximation (HANDOFF §1): this LINEARIZED (first-order / CRLB) ellipse is
exact only for small errors / benign geometry; under bad geometry the true fix
scatter is banana-shaped and the ellipse UNDER-predicts it (quantified offline,
gate-3 stretch). Axes are clamped to [`FINITE_CEIL`](@ref) so a singular `C` can
never ship Inf/NaN.
"""
function error_ellipse(C; nsigma::Real = 1.0)
    λ1, λ2, ang = eig2x2(C)
    a = nsigma * sqrt(max(λ1, 0.0))
    b = nsigma * sqrt(max(λ2, 0.0))
    return (_finite(a), _finite(b), ang)
end

"""
    gdop(H) -> Float64   (dimensionless)

Geometric Dilution of Precision from the geometry/Jacobian matrix `H` (an iterable
of 2-element rows — the `[∂θ/∂x, ∂θ/∂y]` rows for bearings, with the `1/R̂`
range-weighting already baked in):

    GDOP = √ trace( (HᵀH)⁻¹ )

evaluated at **UNIT measurement variance** (σ ≡ 1), so it is a pure-GEOMETRY scalar
with `σ_pos = GDOP·σθ`. Its units are those of `1/H`: for the AOA Jacobian here
(rows `~1/R̂`) GDOP is in **metres per radian** (position error per radian of bearing
error); for GPS's dimensionless unit-LOS rows the same function returns the classical
dimensionless DOP — the signature is measurement-agnostic, only the units follow `H`.
GDOP must **NOT** be the σθ-weighted
`√trace((HᵀR⁻¹H)⁻¹)` — that would make a σθ slider wrongly move GDOP (the
mean-vs-sum convention trap on a new surface, advisor #2). **GDOP is geometry only;
the ellipse ([`error_ellipse`](@ref)) carries σθ.** The far-sensor 1/R² down-
weighting still enters through `H`'s `1/R̂` rows (a distant sensor contributes less
Fisher info). Small for orthogonal crossings (the minimum), huge as the geometry
degenerates (collinear / emitter on the baseline) — clamped to [`FINITE_CEIL`](@ref),
never Inf. This is the **same DOP math GPS reuses** (HANDOFF §9).
"""
function gdop(H)
    m11 = 0.0; m12 = 0.0; m22 = 0.0      # M = HᵀH (2×2, symmetric PSD)
    for h in H
        h1 = h[1]; h2 = h[2]
        m11 += h1 * h1
        m12 += h1 * h2
        m22 += h2 * h2
    end
    det = m11 * m22 - m12 * m12
    det > 0 || return FINITE_CEIL        # singular (collinear) → huge but finite
    g = sqrt((m11 + m22) / det)          # trace((HᵀH)⁻¹) = (m11+m22)/det
    return _finite(g)
end

# Clamp a readout to the finite ceiling: a non-finite (Inf/NaN from a singular
# geometry) or an over-ceiling value becomes FINITE_CEIL, so the wire never carries
# Inf/NaN (advisor's output-clamp-over-ridge guidance).
_finite(x::Real) = isfinite(x) ? min(x, FINITE_CEIL) : FINITE_CEIL

# A SIGNED finite clamp for a coordinate readout that may be negative (a fix_x/fix_y, a GPS
# residual): a singular solve can blow to ±Inf/NaN → JSON poison, so map non-finite to
# FINITE_CEIL and clamp the magnitude to [−FINITE_CEIL, FINITE_CEIL]. The signed sibling of
# `_finite`, kept here in the shared lib so BOTH geolocation.jl (slice 5) and gps.jl (slice 7)
# draw from it (the §9 shared-lib layering, not a peer subsystem's private helper).
_finite_coord(x::Real) = isfinite(x) ? clamp(float(x), -FINITE_CEIL, FINITE_CEIL) : FINITE_CEIL

# ---------------------------------------------------------------------------------
# The N-dimensional shared solver (slice 7 §9 reuse — "extend, don't fork"). GPS
# (4 unknowns) needs the same normal-equation solve DF (2 unknowns) uses; rather
# than a second solver, the DF call sites in estimation.jl delegate to THIS generic
# routine at N=2, so DF geolocation and GPS trilateration call literally the same
# code (the §9 headline made real). Pure, no `w.rng`, no LinearAlgebra — a
# hand-rolled Cholesky (LLᵀ), ~plain loops over N (the `_range` house style).
# ---------------------------------------------------------------------------------

# Forward (L y = b) then back (Lᵀ x = y) substitution for a lower-triangular L.
function _chol_solve(L::AbstractMatrix{Float64}, b::AbstractVector{Float64})
    n = length(b)
    y = Vector{Float64}(undef, n)
    x = Vector{Float64}(undef, n)
    @inbounds for i in 1:n
        t = b[i]
        for k in 1:i-1; t -= L[i, k] * y[k]; end
        y[i] = t / L[i, i]
    end
    @inbounds for i in n:-1:1
        t = y[i]
        for k in i+1:n; t -= L[k, i] * x[k]; end
        x[i] = t / L[i, i]
    end
    return x
end

"""
    _solve_normal(M, g) -> (x, Minv, singular)

Solve the `N×N` symmetric-PSD normal system `M·x = g` and return the solution `x`,
the inverse `Minv = M⁻¹` (the covariance / DOP matrix), and a `singular` flag — all
from ONE hand-rolled Cholesky factorization (no LinearAlgebra). This is the N-dim
generalization of estimation.jl's old closed-form 2×2 `_solve2x2`; the DF call sites
delegate here at N=2 and GPS at N=4 (§9 reuse).

**Regularization (the N-dim analog of `_solve2x2`'s relative det floor).** A pivot
that drops to/below a RELATIVE ridge `ridge = 1e-12·(tr(M)/N + 1)` marks the geometry
rank-deficient: `singular` is set and the pivot is floored to `ridge`, so a singular
constellation (< N independent rows, coplanar/clustered) yields a huge-but-FINITE
`Minv` (never NaN/Inf, never a throw) — the readouts clamp to [`FINITE_CEIL`](@ref) at
the consumer, or the caller keys off `singular` to ship `FINITE_CEIL` exactly. A
WELL-conditioned pivot is used verbatim (no ridge added), so the N=2 solve reproduces
the pre-refactor `_solve2x2` fix/cov to floating-point (the byte-safety obligation).
"""
function _solve_normal(M::AbstractMatrix{Float64}, g::AbstractVector{Float64})
    n = length(g)
    tr = 0.0
    @inbounds for i in 1:n; tr += M[i, i]; end
    ridge = 1e-12 * (tr / n + 1.0)
    L = zeros(Float64, n, n)
    singular = false
    @inbounds for j in 1:n
        s = M[j, j]
        for k in 1:j-1; s -= L[j, k]^2; end
        if s <= ridge                       # rank-deficient relative to the matrix scale
            singular = true
            s = ridge
        end
        Ljj = sqrt(s)
        L[j, j] = Ljj
        for i in j+1:n
            t = M[i, j]
            for k in 1:j-1; t -= L[i, k] * L[j, k]; end
            L[i, j] = t / Ljj
        end
    end
    x = _chol_solve(L, g)
    Minv = Matrix{Float64}(undef, n, n)
    e = zeros(Float64, n)
    @inbounds for c in 1:n
        fill!(e, 0.0); e[c] = 1.0
        col = _chol_solve(L, e)
        for i in 1:n; Minv[i, c] = col[i]; end
    end
    return x, Minv, singular
end

"""
    dop(H) -> (Q, singular)

The dilution-of-precision matrix `Q = (HᵀH)⁻¹` at **UNIT** measurement variance for a
geometry/Jacobian `H` (an iterable of N-element rows). This is the same `(HᵀH)⁻¹` math
`gdop` uses, generalized to N via the shared [`_solve_normal`](@ref) (§9 reuse) — GPS
calls it at N=4 with unit-LOS rows `[−û, 1]`. **σ enters NEVER inside Q** (pure
geometry) — the pseudorange σ multiplies the DOP at the readout (`σ_pos = DOP·σ`), the
slice-5 σ-invariance trap on a new surface (advisor). `singular` (a rank-deficient /
coplanar constellation) is passed through so [`dop_components`](@ref) can ship
`FINITE_CEIL` exactly.
"""
function dop(H)
    N = length(first(H))
    M = zeros(Float64, N, N)
    @inbounds for h in H
        for a in 1:N, c in a:N
            M[a, c] += h[a] * h[c]
        end
    end
    @inbounds for a in 1:N, c in 1:a-1; M[a, c] = M[c, a]; end   # symmetrize
    _, Q, singular = _solve_normal(M, zeros(Float64, N))
    return Q, singular
end

"""
    dop_components(Q; singular = false) -> (gdop, pdop, hdop, vdop, tdop)

Decompose a 4×4 GPS DOP matrix `Q = (HᵀH)⁻¹` (from [`dop`](@ref); local frame — 1,2
horizontal, 3 vertical, 4 receiver clock) into the classical dilution scalars:

    GDOP = √(Q₁₁+Q₂₂+Q₃₃+Q₄₄)   PDOP = √(Q₁₁+Q₂₂+Q₃₃)
    HDOP = √(Q₁₁+Q₂₂)           VDOP = √Q₃₃        TDOP = √Q₄₄

All clamped to [`FINITE_CEIL`](@ref); a `singular` constellation ships `FINITE_CEIL`
exactly (the `gdop` det-guard analog). **VDOP > HDOP is the TYPICAL upper-hemisphere
consequence** (all ranges arrive from above → one-sided vertical info) — a property of
the placement, verified per-layout, NOT a universal (named approximation, HANDOFF §1).
"""
function dop_components(Q; singular::Bool = false)
    singular && return (FINITE_CEIL, FINITE_CEIL, FINITE_CEIL, FINITE_CEIL, FINITE_CEIL)
    g = sqrt(max(Q[1,1] + Q[2,2] + Q[3,3] + Q[4,4], 0.0))
    p = sqrt(max(Q[1,1] + Q[2,2] + Q[3,3], 0.0))
    h = sqrt(max(Q[1,1] + Q[2,2], 0.0))
    v = sqrt(max(Q[3,3], 0.0))
    t = sqrt(max(Q[4,4], 0.0))
    return (_finite(g), _finite(p), _finite(h), _finite(v), _finite(t))
end
