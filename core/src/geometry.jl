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
