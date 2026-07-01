# frames.jl — the shared frame / LOS library (HANDOFF §9, slice 8 gate 1).
#
# A NEW §9 SHARED LIB (the geometry.jl / estimation.jl / gnss.jl analog): pure, no
# `w.rng`, closed-form, dependency-free base Julia + `StaticArrays`, **no LinearAlgebra**
# (the `_range` / `_solve_normal` house style — `dot`/`cross`/`norm` are hand-rolled).
# Everything is SI Float64, inertial frame.
#
# Built **fully 3-D and tested 3-D now** (the slices 10–13 investment: the PID autopilot,
# proportional-navigation, and seeker slices all ride this), even though slice 8's ballistic
# scenario is planar. Scoped to exactly what the guidance/seeker slices need — quaternion
# algebra, the inertial↔body frame pair, and the sign-critical LOS kernel — and NOT
# gold-plated (advisor). `geometry.jl` is left byte-identical: its 2-D `bearing`/`wrap_angle`
# are the planar DF special case, `frames.jl` is the 3-D superset — conceptually shared, NOT
# code-merged (the slice-7 "keep the shipped 2×2 path, don't churn" discipline). The
# azimuth == `bearing` pin (below) is the §9 reuse-faithfulness proof.
#
# Units / frames / SIGNS are the bug trifecta (HANDOFF §1). Here SIGNS are the co-headline:
# a flipped LOS-rate sign is the #1 "my missile flies away" bug, so `los_rate`/`range_rate`
# ship with tests that pin the SIGN on a concrete crossing geometry, not just the magnitude.

# --- hand-rolled vector math (no LinearAlgebra — the house style) ----------------
# `_norm3` already lives in gnss.jl (included before frames.jl, identical math) — reuse
# the module-level helper rather than redefine it (precompile forbids overwriting). `_dot`
# and `_cross` are new here.

_dot(a, b)   = a[1]*b[1] + a[2]*b[2] + a[3]*b[3]
_cross(a, b) = Vec3(a[2]*b[3] - a[3]*b[2],
                    a[3]*b[1] - a[1]*b[3],
                    a[1]*b[2] - a[2]*b[1])

# A tiny magnitude below which a vector is treated as zero (zero-range / apex v→0 guards).
const _FRAME_EPS = 1e-12

# --- quaternion algebra (Quat = SVector{4}, [w,x,y,z], body<-inertial, id [1,0,0,0]) ---

"""
    qmul(a, b) -> Quat

Hamilton product `a ⊗ b` of two quaternions (`[w,x,y,z]` layout). Composition of the
rotations `a` then `b` in the usual quaternion sense; NOT commutative.
"""
function qmul(a::Quat, b::Quat)
    aw, ax, ay, az = a[1], a[2], a[3], a[4]
    bw, bx, by, bz = b[1], b[2], b[3], b[4]
    return Quat(aw*bw - ax*bx - ay*by - az*bz,
                aw*bx + ax*bw + ay*bz - az*by,
                aw*by - ax*bz + ay*bw + az*bx,
                aw*bz + ax*by - ay*bx + az*bw)
end

"""
    qconj(q) -> Quat

Quaternion conjugate `[w, −x, −y, −z]`. For a UNIT quaternion this is the inverse
rotation (see [`qinv`](@ref)).
"""
qconj(q::Quat) = Quat(q[1], -q[2], -q[3], -q[4])

"""
    qnormalize(q) -> Quat

Normalize `q` to unit length. A (near-)zero quaternion falls back to the identity
`[1,0,0,0]` rather than producing NaN (the guard an accumulated-drift `att` could hit).
"""
function qnormalize(q::Quat)
    n = sqrt(q[1]^2 + q[2]^2 + q[3]^2 + q[4]^2)
    n < _FRAME_EPS && return Quat(1, 0, 0, 0)
    return q / n
end

"""
    qinv(q) -> Quat

Inverse rotation quaternion `q⁻¹ = q* / ‖q‖²`. For a unit quaternion this equals the
conjugate [`qconj`](@ref); the general form is kept so a slightly non-unit `att` still
inverts correctly.
"""
function qinv(q::Quat)
    n2 = q[1]^2 + q[2]^2 + q[3]^2 + q[4]^2
    n2 < _FRAME_EPS && return Quat(1, 0, 0, 0)
    return qconj(q) / n2
end

"""
    quat_from_axis_angle(axis::Vec3, θ) -> Quat

Unit quaternion for a rotation of `θ` radians about `axis` (right-hand rule):
`[cos(θ/2), sin(θ/2)·â]`. A zero-length `axis` yields the identity (no rotation).
"""
function quat_from_axis_angle(axis::Vec3, θ::Real)
    n = _norm3(axis)
    n < _FRAME_EPS && return Quat(1, 0, 0, 0)
    â = axis / n
    s = sin(θ / 2)
    return Quat(cos(θ / 2), s*â[1], s*â[2], s*â[3])
end

"""
    quat_from_two_vectors(a::Vec3, b::Vec3) -> Quat

The MINIMAL rotation quaternion taking direction `a` onto direction `b`, i.e.
`rotate(quat_from_two_vectors(a,b), a) ∥ b` (see [`rotate`](@ref)). Used to build a
velocity-aligned attitude (`quat_from_two_vectors([1,0,0], v̂)`).

Two guards the ballistic missile actually hits (HANDOFF §1 — must not throw / NaN):
  • **zero-vector** — either input (near-)zero (`v→0` at the apex of a straight-up shot)
    → identity;
  • **antiparallel** — `a ≈ −b` (rotation axis undefined) → a π rotation about ANY axis
    perpendicular to `a` (picked deterministically).
Otherwise the half-way construction `q = normalize([1 + â·b̂, â × b̂])`.
"""
function quat_from_two_vectors(a::Vec3, b::Vec3)
    na = _norm3(a); nb = _norm3(b)
    (na < _FRAME_EPS || nb < _FRAME_EPS) && return Quat(1, 0, 0, 0)   # zero-vector guard
    â = a / na; b̂ = b / nb
    d = _dot(â, b̂)
    if d >= 1.0 - _FRAME_EPS                     # already aligned
        return Quat(1, 0, 0, 0)
    elseif d <= -1.0 + _FRAME_EPS                # antiparallel: π about any ⟂ axis
        # pick the world axis least parallel to â, project it perpendicular, normalize.
        ref = abs(â[1]) < 0.9 ? Vec3(1, 0, 0) : Vec3(0, 1, 0)
        axis = _cross(â, ref)
        return quat_from_axis_angle(axis, π)
    end
    c = _cross(â, b̂)
    return qnormalize(Quat(1.0 + d, c[1], c[2], c[3]))
end

"""
    rotate(q, v::Vec3) -> Vec3

Apply the rotation represented by quaternion `q` to vector `v`: `v' = q ⊗ [0,v] ⊗ q*`
(active rotation). A unit `q` preserves length. The inertial↔body pair is
[`rotate`](@ref) / [`rotate_inv`](@ref); their round-trip is the day-one §1 test.
"""
function rotate(q::Quat, v::Vec3)
    p = qmul(qmul(q, Quat(0, v[1], v[2], v[3])), qconj(q))
    return Vec3(p[2], p[3], p[4])
end

"""
    rotate_inv(q, v::Vec3) -> Vec3

Apply the INVERSE rotation of `q` to `v` (`v' = q* ⊗ [0,v] ⊗ q`). Satisfies
`rotate_inv(q, rotate(q, v)) == v` for unit `q`.
"""
function rotate_inv(q::Quat, v::Vec3)
    qi = qconj(q)
    p = qmul(qmul(qi, Quat(0, v[1], v[2], v[3])), q)
    return Vec3(p[2], p[3], p[4])
end

# --- LOS geometry (the sign-critical guidance kernel) ----------------------------

"""
    los_unit(from::Vec3, to::Vec3) -> Vec3

Unit line-of-sight vector from `from` to `to`. Zero-range guard: coincident points
return the zero vector (never NaN).
"""
function los_unit(from::Vec3, to::Vec3)
    d = to - from
    n = _norm3(d)
    n < _FRAME_EPS && return zero(Vec3)
    return d / n
end

"""
    los_range(from::Vec3, to::Vec3) -> Float64

Euclidean range `‖to − from‖` (metres). Named `los_range` (not bare `range`) to avoid
shadowing `Base.range`; it is the 3-D sibling of radar.jl's internal `_range`.
"""
los_range(from::Vec3, to::Vec3) = _norm3(to - from)

"""
    range_rate(rel_pos::Vec3, rel_vel::Vec3) -> Float64   (m/s)

Range rate `d‖r‖/dt = (r·v)/‖r‖` for relative position `r = rel_pos` and relative
velocity `v = rel_vel` (both target − missile). **SIGN CONVENTION (pinned): negative =
CLOSING** (range decreasing), positive = opening. Zero-range guard returns 0.
"""
function range_rate(rel_pos::Vec3, rel_vel::Vec3)
    n = _norm3(rel_pos)
    n < _FRAME_EPS && return 0.0
    return _dot(rel_pos, rel_vel) / n
end

"""
    los_rate(rel_pos::Vec3, rel_vel::Vec3) -> Vec3   (rad/s)

The line-of-sight ANGULAR RATE vector `ω = (r × v) / ‖r‖²` — the ω proportional
navigation multiplies by closing speed. Its **SIGN** (not just `‖ω‖`) is the #1
"missile flies away" bug (HANDOFF §1) and is pinned against a concrete left→right
crossing in `test_frames.jl`. Zero-range guard returns the zero vector.
"""
function los_rate(rel_pos::Vec3, rel_vel::Vec3)
    r2 = _dot(rel_pos, rel_pos)
    r2 < _FRAME_EPS && return zero(Vec3)
    return _cross(rel_pos, rel_vel) / r2
end

"""
    az_el(los::Vec3) -> (az, el)   (radians)

Azimuth / elevation of a line-of-sight vector: `az = atan(y, x)` (in the x-y plane,
in [−π,π]), `el = atan(z, ‖(x,y)‖)` (above the x-y plane, in [−π/2,π/2]). The azimuth
uses the SAME `atan(Δy, Δx)` convention as `geometry.jl`'s [`bearing`](@ref) — pinned
equal on a shared z=0 example (the §9 reuse-faithfulness proof).
"""
az_el(los::Vec3) = (atan(los[2], los[1]), atan(los[3], hypot(los[1], los[2])))
