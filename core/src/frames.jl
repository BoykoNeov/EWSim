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

"""
    los_unit_from_angles(az, el) -> Vec3

The INVERSE of [`az_el`](@ref): the unit LOS direction rebuilt from an azimuth/elevation
PAIR, `û = (cos el·cos az, cos el·sin az, sin el)`. Round-trips with `az_el` to machine
precision for `|el| < π/2` (pinned in `test_frames.jl`).

Slice 25 (a seeker in the 6-DOF loop): a two-angle seeker MEASURES `(az, el)` — this is
how the measurement becomes a direction again. Its slice-11 predecessor measured the
SCALAR in-plane bearing `λ = atan(Δz, Δx)` and could only rebuild an x–z direction, which
is the whole foil (`docs/plans/slice25.md` §1).
"""
function los_unit_from_angles(az::Real, el::Real)
    ca, sa = cos(az), sin(az)
    ce, se = cos(el), sin(el)
    return Vec3(ce * ca, ce * sa, se)
end

"""
    los_rate_from_angles(az, el, az_dot, el_dot) -> Vec3   (rad/s)

The LOS angular-rate VECTOR reconstructed from an angle pair and its rates —
`ω = û × û̇`, with

    ∂û/∂az = (−cos el·sin az,  cos el·cos az, 0)
    ∂û/∂el = (−sin el·cos az, −sin el·sin az, cos el)
    û̇      = ȧz·∂û/∂az + ėl·∂û/∂el

**This is IDENTICALLY the quantity [`los_rate`](@ref) computes from truth kinematics.**
With `r = R·û`: `v = Ṙ·û + R·û̇`, so `r×v = R²·(û × û̇)` and `(r×v)/‖r‖² ≡ û × û̇` — the
radial component cancels because `û × û ≡ 0`. That identity makes truth an EXACT oracle
for a seeker's estimate rather than a calibrated one, and it is pinned that way in
`test_frames.jl` against an INDEPENDENT closed-form recompute of `(ȧz, ėl)` (convention 11).

**SIGN** is the #1 "missile flies away" bug (HANDOFF §1) and this is its 7th occurrence in
the project: the argument ORDER `û × û̇` is load-bearing — swapping it negates ω and PN
commands away from the intercept. Pinned by an in-plane invariant (`az ≡ 0` and `ȧz ≡ 0`
⇒ `ω_x = ω_z = 0`, motion confined to the x–z plane) PAIRED with a does-turn case, so the
test cannot pass by producing zero.

Note `ȧz` is ill-conditioned as `|el| → π/2` (the pole, where azimuth ceases to be
observable); ω itself stays finite and correct there because `∂û/∂az → 0`.
"""
function los_rate_from_angles(az::Real, el::Real, az_dot::Real, el_dot::Real)
    ca, sa = cos(az), sin(az)
    ce, se = cos(el), sin(el)
    û = Vec3(ce * ca, ce * sa, se)
    u̇ = Vec3(az_dot * (-ce * sa) + el_dot * (-se * ca),
             az_dot * ( ce * ca) + el_dot * (-se * sa),
             el_dot * ce)
    return _cross(û, u̇)
end

# --- the RADOME (slice 26, §11 Tier-A — the bank-to-turn / 3-D arc's named end point) ------
#
# The seeker does not look at the target directly: it looks THROUGH a radome, and a radome
# REFRACTS. Everything below is measurement geometry in the BODY frame, which is why it lives
# here beside `rotate_inv`/`az_el` and not in an aero lib — the radome is a property of the
# SENSOR's installation, not of the airframe.
#
# ⚠ THE PHYSICS IS THE FEEDBACK PATH, NOT THE FORMULA. Both kernels below are one-liners, and
# their triviality is the point: what makes slice 26 a slice is that `look` depends on the
# missile's own ATTITUDE, so a body rate moves the reported line of sight, which moves the
# guidance command, which moves the body rate. Past a critical loop gain (MEASURED at
# `N·|R|/ρ ≈ 0.38`, `docs/plans/slice26.md` §1) that loop is UNSTABLE and the missile shakes
# itself into a sustained limit cycle — with a NOISELESS seeker and a stationary target.

"""
    look_angles(att::Quat, los::Vec3) -> (look_az, look_el)   (radians)

The LOOK ANGLES of a line-of-sight direction off the missile's own boresight: `los` rotated
into the BODY frame (`rotate_inv`, since `att` maps body→inertial) and read out with
[`az_el`](@ref). Zero when the nose points straight at the target.

Slice 26 (the radome parasitic loop) is the first consumer, and slice 25's two-angle seeker
was its hard prerequisite: an error slope perturbs a measurement AS A FUNCTION OF LOOK ANGLE,
and before slice 25 there was no two-angle measurement for it to perturb. A seeker FOV /
gimbal limit is the other thing this quantity makes expressible (a named deferral).

The identity attitude returns `az_el(los)` unchanged — the degenerate pinned in
`test_frames.jl`.
"""
look_angles(att::Quat, los::Vec3) = az_el(rotate_inv(att, los))

"""
    radome_error(slope, look_az, look_el) -> (ε_az, ε_el)   (radians)

The BORESIGHT ERROR a radome of error slope `slope` (dimensionless, signed) adds to a
measurement taken at look angles `(look_az, look_el)`: the standard LINEAR model
`ε = R · (look angle)`, applied per angle. A §1 named approximation — a real radome's slope
VARIES with look angle and the design case is the worst LOCAL slope (a named deferral).

**`slope == 0` returns exactly `(0.0, 0.0)`** — the shipped no-radome path is a KEY-ABSENT
branch upstream of this (never `+ ε` trusting the zero, the `-0.0` trap), and this exactness
is pinned bit-for-bit and PAIRED with a does-perturb case.

**SIGN — the #1 "missile flies away" bug (HANDOFF §1), 8th occurrence, and the one place a
transliterated textbook formula gets it WRONG.** On a FROZEN geometry (target, missile and
true LOS all held still, only the attitude rotating) the parasitic gain measures EXACTLY

    ε̇_el = +R·cos(look_az)·ω_y ,    ε̇_az = −R·ω_z

(`docs/plans/slice26.md` §4, gate-0 P8B, pinned in `test_frames.jl`). The textbook writes this
as `−R·θ̇`, and transliterating that to `−R·q` in THIS project is the wrong sign: the
convention here is nose-up = a **−y** body rotation (slice 23), so `θ̇ = −ω_y` while `q` is the
telemetry name for `ω[2] = ω_y`. Hence: **nose-up (`q < 0`) with `R < 0` ⇒ `ε̇_el > 0` ⇒ the
LOS appears to rotate UP ⇒ the loop commands MORE nose-up.** Only NEGATIVE slopes destabilize;
positive ones DE-TUNE (the seeker under-reports the LOS rate, the effective navigation ratio
sags, and the miss opens from sluggishness — measured, and a named deferral).

⚠ This gain is NOT identifiable on a tracking missile: in closed loop `ėl` and `q` are
collinear (a missile that is tracking pitches at nearly the rate the LOS rotates), so an
in-loop regression fits with R² = 0.999 and meaningless coefficients (gate-0 P7A). **Freeze
the geometry** — that is what the test does.
"""
radome_error(slope::Real, look_az::Real, look_el::Real) =
    (slope * look_az, slope * look_el)

"""
    radome_compensation(slope_est, look_az, ω_body) -> (Δȧz, Δėl)   (rad/s)

The RATE-GYRO FEED-FORWARD that cancels [`radome_error`](@ref)'s parasitic term (slice 27, §11
Tier-A — the engineering answer to slice 26, which named it as its own successor). Returns the
CORRECTIONS to ADD to the seeker's measured LOS angle rates, given the slope the guidance
computer BELIEVES its radome has (`slope_est` = `R̂`) and the body-frame rate gyro reading.

    Δȧz = +R̂·ω_z ,      Δėl = −R̂·cos(look_az)·ω_y

**⚠ THE SIGNS ARE THE WHOLE FUNCTION, and they are the #1 SIGN TRAP's 9th occurrence.** They are
the NEGATION of the parasitic gain `radome_error` produces (`ε̇_el = +R·cos(look_az)·ω_y`,
`ε̇_az = −R·ω_z`), because compensation SUBTRACTS what the radome ADDED. The first draft of slice
27's plan carried BOTH flipped (advisor) — which DOUBLES the parasitic term at `R̂ = R` while
still producing a plausible-looking sweep: the ring goes quiet at `R̂ = −R`, and the slice gets
written up backwards. ⇒ the gate-1 tooth is not this formula restated, it is the CANCELLATION
measured against the shipped `radome_error` on the frozen geometry, PAIRED with an axis-asymmetry
case (a pure yaw rate must correct `Δȧz` ONLY, a pure pitch rate `Δėl` ONLY — a compensator that
put the cosine on both axes, or neither, still cancels at `look_az ≈ 0` and would pass a single
small-angle test).

**WHAT IT CANCELS, AND WHAT IT CANNOT (slice 27 gate-0 P3B — the finding that keeps the slice
honest).** The look angle moves for TWO reasons: the BODY rotating, which the gyro sees, and the
LOS itself rotating, which it does not. This cancels the body-rate half EXACTLY, which is why the
STABILITY BOUNDARY lands exactly on the residual `R − R̂` (measured: slice 26's loop gain
`N·|R|/ρ ≈ 0.38` returns verbatim with `R` → `R − R̂`, constant to ±3% across N ∈ {3…8} and
ρ ∈ {0.6…2.0}). The LOS-driven half survives, so a compensated missile is **NOT** the same missile
as one with a better radome — over-compensation de-tunes rather than helping (`R = −0.30`,
`R̂ = −0.45` misses by 31.4 m where a bare `R = +0.15` misses by 0.47). **A gyro can only cancel
what a gyro can see** — say "the residual sets the STABILITY BOUNDARY", never "the residual is an
equivalent radome".

**⚠ AND WHAT THE TWO-TERM LAW LEAVES BEHIND (gate-1 finding — the testset failed on it first).**
For an OFF-BORESIGHT LOS a PITCH rate also moves AZIMUTH (slice 26's own frozen-geometry table:
`ε̇_az/R = −0.0598` at `ω = (0,−1,0)`), a CROSS-TERM this law does not model — so the AZIMUTH
channel keeps a residual under pitch while the ELEVATION channel cancels exactly. That is a §1
named approximation of the CLASSIC compensator, not a defect in it, and it does not touch the
slice's claim: elevation is the channel that closes the pitch loop (gain 0.9487 against the
cross-term's 0.0598, ~16× down), and the residual law was measured END TO END with this very
law. ⇒ **on the loop-closing axis compensation IS a slope offset; on the other axis it is a slope
offset plus a known second-order term** — pinned in `test_frames.jl` against the cross-coefficient
MEASURED from `radome_error`, never a magic constant.

`slope_est == 0` returns exact zeros — the shipped no-compensator path is a KEY-ABSENT branch
upstream of this (never `+ Δ` trusting the zero: the `-0.0` trap), and that exactness is what
makes "no compensation" KNOB-REACHABLE and therefore a knob rather than a fidelity rung
(atmosphere.jl's discriminator; measured bit-identical at gate 0, not argued).

⚠ A PERFECT gyro is a §1 named approximation (slice 11's "Vc stays truth" precedent). ⚠ And
`look_az` here is the compensator's OWN estimate, formed from the BENT measurement — a guidance
computer has no truth LOS. Feeding it the true look angle would make the slice fake.
"""
radome_compensation(slope_est::Real, look_az::Real, ω_body::Vec3) =
    (slope_est * ω_body[3], -slope_est * cos(look_az) * ω_body[2])
