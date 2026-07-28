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

# --- the SLOPE CURVE (slice 28, §11 Tier-A — a deferral named by BOTH 26 and 27) -------------
#
# Slices 26 and 27 both assumed the glass has ONE error slope. It does not: a radome's boresight
# error slope is a CURVE in look angle, because the ray passes through different glass at
# different look angles. The consequence is not a bigger `R` — it is that **which part of the
# curve closes the loop is decided by the ENGAGEMENT, not by the radome**: a static target's
# collision course carries zero lead and settles the seeker onto boresight, while a crossing
# target holds a sustained lead angle and parks it on a steep part of the glass (`docs/plans/
# slice28.md` §1, MEASURED — on slices 23–27's static wire the look angle decays to 0.04–0.54°,
# which would make this whole family of kernels a DEAD KNOB there).

"""
    radome_slope_curve(slope0, ripple, k, look) -> R   (dimensionless, signed)

The radome's LOCAL error slope at look angle `look` (slice 28):

    R(look) = slope0 + ripple·(1 − cos(k·look))

`slope0` is the BORESIGHT slope, `ripple` the slope-ripple amplitude and `k` its spatial
frequency in rad⁻¹ (period `2π/k` in look angle). Bounded to `[slope0, slope0+2·ripple]`
BY CONSTRUCTION — which is the whole reason this form ships and a cubic `ε = R₀·look + C·look³`
does not: the cubic's slope is UNBOUNDED, so the amplitude that puts the off-axis slope past
critical also makes the bend diverge once the look angle grows, and the missile is simply lost
(measured: miss 2550–4158 m). That would be the small-angle model carrying the lesson exactly
where it is invalid — the objection slice 27 used to reject `R = −0.30`, recurring.

**`R(0) == slope0` EXACTLY, for every `ripple`** — the ripple term vanishes identically at
boresight. That is not a convenience: it is the MECHANISM of slice 28's central asymmetry.
Characterizing the radome at boresight — the natural thing to do — measures a number that is
*structurally* insensitive to the curve, and so is exactly right in the one place the loop is
never closed. Hence: **the scalar `R̂` that works is set by the ENGAGEMENT, not by the radome,
and characterizing at boresight is the DANGEROUS choice** (`docs/plans/slice28.md` §5).

⚠ `k` is a NON-KNOB (authored). The metric is NON-MONOTONE in it — quiet / rings / rings /
marginal / quiet / rings at `k` = 4 / 6 / 8.2 / 12 / 16 / 24 at held amplitude — because `k`
decides WHERE ON THE WIGGLE the operating look angle lands ([[ewsim-df-ellipse-sigma-monotonicity]],
4th occurrence). A caller must floor it positive; `radome_error_curve` divides by it.

⚠ ODD by construction (a SYMMETRIC radome). An asymmetric error curve, and a genuinely 2-D
`R(look_az, look_el)`, are named deferrals — this is ONE scalar curve applied per angle, which
is slice 26's own per-angle application generalized.
"""
radome_slope_curve(slope0::Real, ripple::Real, k::Real, look::Real) =
    slope0 + ripple * (1 - cos(k * look))

"""
    radome_error_curve(slope0, ripple, k, look_az, look_el) -> (ε_az, ε_el)   (radians)

The BORESIGHT ERROR of a radome whose slope follows [`radome_slope_curve`](@ref) — the EXACT
integral of that slope, applied per angle:

    ε(u) = slope0·u + ripple·u − (ripple/k)·sin(k·u)         ⇒   dε/du ≡ R(u)

**⭐ THAT IDENTITY IS THE POINT OF THE SLICE, AND IT IS A TOOTH, NOT A COMMENT** (`test_frames.jl`
finite-differences this against `radome_slope_curve`). Slice 26's parasitic loop is driven by
`dε/dt = (dε/dlook)·(dlook/dt)` — the LOCAL DERIVATIVE — while a radome is SPECIFIED by its
boresight ERROR `ε`. Under slice 26's linear model those are the same number, which is precisely
why 26 could not tell them apart. Here they separate, and the loop follows the DERIVATIVE:
a matched-secant A/B (same bend at the operating look angle, different slope there) rings on the
curve and stays quiet on the constant — measured. **A radome inside its boresight-error spec
everywhere can still ring.**

⚠ **`ripple == 0` IS NOT A SUBSTITUTE FOR [`radome_error`](@ref), AND THE SEAM MUST BRANCH.**
Algebraically the ripple terms vanish, but `x + 0.0` is not the identity at `x = −0.0` and float
addition is not associative, so the shipped no-ripple path is a KEY-ABSENT branch upstream that
calls `radome_error` VERBATIM (the slice-20/21/26/27 structural-byte-identity shape). The
reduction is pinned here bit-for-bit anyway, because that exactness is what makes `ripple` a KNOB
rather than a fidelity rung (atmosphere.jl's discriminator — measured, not argued).

⚠ SIGN: the parasitic gain inherits slice 26's convention unchanged, with `R` → `R(look)`. The
gate-1 tooth measures the frozen-geometry coefficient at **TWO different look angles** and
requires it to MOVE and to match `radome_slope_curve` at each — the #1 SIGN TRAP's 10th
occurrence. A test at ONE look angle passes for a constant-slope kernel and proves nothing.
"""
function radome_error_curve(slope0::Real, ripple::Real, k::Real, look_az::Real, look_el::Real)
    kk = max(Float64(k), 1.0e-6)          # convention 5: `ripple/k` at k = 0 is a real crash path
    f(u) = slope0 * u + ripple * u - (ripple / kk) * sin(kk * u)
    return (f(look_az), f(look_el))
end

"""
    radome_slope_worst(slope0, ripple) -> R_worst   (dimensionless, signed)

The MOST NEGATIVE local slope [`radome_slope_curve`](@ref) reaches ANYWHERE — the number slice 30's
design rule aims a scalar `R̂` at. Since `1 − cos(k·look) ∈ [0, 2]`, the curve's two extreme values
are `slope0` and `slope0 + 2·ripple`, so

    R_worst = min(slope0, slope0 + 2·ripple)

⭐⭐ **WHY THE WORST CASE IS A DESIGN RULE AT ALL: THE RADOME CONSTRAINT IS ONE-SIDED.** Only a
NEGATIVE residual `R − R̂` closes slice 26's parasitic loop; a positive one merely DE-TUNES the
reported LOS rate (slice 26, measured — `ω_app/ω_true → 0.593`, one knob with two failure modes).
So a scalar set at or below the most negative slope the glass reaches anywhere errs in the HARMLESS
direction at every look angle, in every engagement — it is not accurate anywhere and does not need
to be. ⇒ **GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY**, and slice 27's two-sided
"know your slope to within `0.38/(N·ρ)`" is a two-sided reading of a one-sided constraint.
Measured over an envelope of seven crossing speeds at five glass depths: the boresight scalar rings
5–6 of 7, this one rings **0 of 7 at every depth** (`docs/plans/slice30.md` §2).

⚠ **SUFFICIENT, NEVER TIGHT — say "a bound", never "the threshold".** The loop needs the residual to
reach the ONSET (≈ −0.055 on this wire), not merely to be negative, so the envelope actually goes
quiet ABOVE this value (at `R̂ ≈ −0.28` where the rule says −0.33): the rule carries ~0.05 of
built-in margin. It is a bound to be exceeded, not an estimate to be matched (§3).

⚠ AND IT IS A BOUND ON THE CURVE, NOT ON THE BAND THE ENGAGEMENT VISITS. The extremum needs
`k·look = π`, so for a small authored `k` the minimum sits outside the reachable look angles and the
bound is MORE conservative than the glass ever presents in flight. That extra conservatism is the
point — the rule's whole value is that it never has to know which engagement will be flown, which is
also why it survives the trap that catches a pre-flight rule sized from the nominal
collision-course look angle (§5: the band's CENTRE is not the band).

⚠ `min`, not the literal `slope0 + 2·ripple`, and the difference only shows up OUTSIDE slice 30's
`A ∈ [−0.20, 0]` knob domain (inside it the two agree exactly). A POSITIVE authored `ripple` is a
meaningful configuration in this codebase — positive slopes de-tune — and there `slope0 + 2·ripple`
is the most POSITIVE slope, i.e. the maximally de-tuned aim point: it would INVERT the rule this
function exists to serve. Both signs are pinned in `test_frames.jl`.

`ripple == 0` gives exactly `slope0` (the flat glass's only slope, and the boresight scalar's own
target), so the off-state is knob-reachable — the KNOB-not-rung discriminator, as everywhere in this
family.
"""
radome_slope_worst(slope0::Real, ripple::Real) =
    min(Float64(slope0), Float64(slope0) + 2.0 * Float64(ripple))

# --- the SCHEDULED COMPENSATOR (slice 29, §11 Tier-A — the answer slice 28 named) ---------------
#
# Slice 27 gave the missile a rate-gyro feed-forward with a SCALAR belief `R̂`. Slice 28 showed the
# glass has no single slope, so the belief must be a CURVE. Making it one is three lines — and it
# introduces a question a scalar never had to answer: **evaluated WHERE?** The only look angle a
# guidance computer owns is the one it computes from its own measurement, and that measurement is
# what the radome bent. So the schedule lands at the wrong point on its own curve, and the belief
# that reaches the loop is `R̂(look_bent)` rather than `R̂(look_truth)`.
#
# ⭐ SLICE 26/27/28's RESIDUAL LAW SURVIVES — READ AT THE COMPENSATOR'S OWN INDEX. Measured
# (`docs/plans/slice29.md` §3, gate-0 P10c): at a common reference look angle the TRUTH-indexed
# residual gets two of three arms WRONG (it predicts quiet for the arm that rings and ringing for
# the arm that stays quiet) while the INDEX-SHIFTED residual gets every arm right. Slice 29 adds no
# new gain to the loop; it adds the fact that a SCHEDULE HAS AN EVALUATION POINT AT ALL.

"""
    radome_schedule_slope(ripple_est, k_est, look) -> R̂'   (per radian)

The SCHEDULE'S OWN SLOPE `dR̂/dlook` at look angle `look` — the exact derivative of the belief
[`radome_slope_curve`](@ref)`(·, ripple_est, k_est, ·)` builds:

    R̂'(look) = ripple_est · k_est · sin(k_est · look)

⭐ **THIS IS A SENSITIVITY, NOT A LOOP GAIN — say it that way** (the slice's own gate-0 correction,
made twice). A scheduled compensator is evaluated at an index that is wrong by the bend, so the
belief it applies is off by roughly `R̂'·(index error)`; this function is the coefficient in that
statement, and it is what makes a schedule's stability depend on the SHAPE of its curve and not only
on how close its VALUE is. ⚠ The first-order form is quantitatively good AWAY from `k_est ≈ k`, and
FAILS at `k_est = k` on a wire whose operating look angle sits at the curve's own extremum, where
`R̂' = 0` and the second-order term carries it (measured: −0.001 predicted against −0.022 actual).
**Quote the index-shifted residual, which is exact; use this to explain its size and sign.**

⭐ **SLICE 27's SCALAR COMPENSATOR HAD `R̂' ≡ 0`, WHICH IS WHY IT NEVER HAD TO CHOOSE AN INDEX** —
and why slice 27 concluded the RATE domain was safe while its ANGLE-domain corrector was not. The
immunity was never the domain; it was the constancy. That is the general result slice 29 carries:
*a corrector built from a signal the disease corrupts inherits the disease — including when the
corruption enters through the corrector's own argument rather than its output.*

`radome_schedule_slope(·, ·, 0) == 0` exactly, and `ripple_est == 0` gives exactly zero at every
look angle — the knob-reachable off-state that makes `Â` a KNOB rather than a fidelity rung
(atmosphere.jl's discriminator).
"""
radome_schedule_slope(ripple_est::Real, k_est::Real, look::Real) =
    ripple_est * k_est * sin(k_est * look)

"""
    radome_compensation_scheduled(slope0_est, ripple_est, k_est, look_az, look_el, ω_body)
        -> (Δȧz, Δėl)   (rad/s)

[`radome_compensation`](@ref) with the scalar belief replaced by the SCHEDULE
[`radome_slope_curve`](@ref)`(slope0_est, ripple_est, k_est, ·)` — slice 29, the engineering answer
slice 28 named for itself. Slice 27's signs are inherited UNCHANGED:

    Δȧz = +R̂(look_az)·ω_z ,      Δėl = −R̂(look_el)·cos(look_az)·ω_y

⚠ **PER AXIS, AND THAT IS NOT A DETAIL — slice 28's gate-2 hardening applied to the COMPENSATOR.**
Slice 27 used one `R̂` for both channels because there was only one. A curve has a different value at
each channel's look angle, so the azimuth channel's belief is `R̂(look_az)` and the elevation
channel's is `R̂(look_el)`; a single value taken at `hypot(look_az, look_el)` is the belief of
NEITHER, and on a crossing wire (where `look_el ≈ 0`) it would agree numerically while being wrong
in principle — exactly the defect slice 28 caught on the plant side.

⚠⚠ **THE CALLER MUST PASS THE COMPENSATOR'S OWN LOOK ANGLES, NOT THE TRUTH ONES, AND THE DIFFERENCE
IS THE SLICE.** The radome bends the real ray at the TRUE look angle — that is the physics. This
function is the guidance computer, which has only its INS attitude, its gyro and its BENT
measurement, so `look_az`/`look_el` here are recomputed from the measured angles (`missile.jl`
`_observe_point3d!` passes `look_az_c`). Feeding it the truth look angles would make the slice fake
AND would silently delete its finding: measured at a common reference angle, a schedule that is a
BETTER model of the glass (wrong by −0.041 against a −0.056 onset) RINGS, while one that is a far
worse model (−0.152) stays QUIET, because at their own indices the errors are −0.067 and −0.001.
[`radome_schedule_slope`](@ref) is the sensitivity that sizes that shift.

**`ripple_est == 0` reduces to [`radome_compensation`](@ref) bit-for-bit** at every look angle — the
knob-vs-rung discriminator, pinned in `test_frames.jl` and PAIRED with a does-schedule case. ⚠ The
SEAM still branches upstream rather than calling this at zero amplitude: `x + 0.0` is not the
identity at `x = −0.0` and float addition is not associative, so a slice-27/28 wire is bit-for-bit
unchanged BY CONSTRUCTION (the slice-20/21/26/27/28 structural-byte-identity shape).

⚠ Everything slice 27's law does NOT cancel is inherited unchanged: the LOS-driven half of the bend
(a gyro can only cancel what a gyro can see), and the PITCH→AZIMUTH cross-term the two-term law does
not model. A PERFECT gyro remains a §1 named approximation.
"""

function radome_compensation_scheduled(slope0_est::Real, ripple_est::Real, k_est::Real,
                                       look_az::Real, look_el::Real, ω_body::Vec3)
    R̂_az = radome_slope_curve(slope0_est, ripple_est, k_est, look_az)
    R̂_el = radome_slope_curve(slope0_est, ripple_est, k_est, look_el)
    return (R̂_az * ω_body[3], -R̂_el * cos(look_az) * ω_body[2])
end

# --- AN IMPERFECT GYRO (slice 31, §11 Tier-A — the PERFECT-gyro approximation 27-30 all named) ----
#
# Every compensator slices 27-30 built multiplies a RATE GYRO READING by a believed slope and
# subtracts the product from the seeker's LOS rate. All four assumed that reading is TRUTH. It is
# not - and the two ways it fails land in two DIFFERENT CURRENCIES this arc has never had to
# separate: a SCALE FACTOR lands on the RESIDUAL (the stability boundary) and is ONE-SIDED, while a
# BIAS lands on the AIM POINT (an additive injection, the arc's first) and is TWO-SIDED.

"""
    gyro_reading(ω_true, scale_err, bias) -> Vec3   (rad/s)

What the RATE GYRO REPORTS, given the body rate the missile actually has (slice 31):

    ω̃ = (1 + scale_err)·ω_true + bias

`scale_err` is the dimensionless SCALE-FACTOR error (`s`; +0.05 = the gyro reads 5% high on every
axis) and `bias` the per-axis rate offset in rad/s. Slices 27–30 all fed
[`radome_compensation`](@ref) the TRUE body rate — a PERFECT gyro, named as a §1 approximation in
every one of them. This is that approximation cashed.

⭐⭐ **THE TWO TERMS LAND IN DIFFERENT CURRENCIES, AND THAT IS THE SLICE.** The feed-forward is
`R̂·ω̃`, so:

  * a SCALE-FACTOR error is common-mode on the product ⇒ the belief that reaches the loop is
    **`R̂·(1+s)`**, exactly. It lands back on slice 26/27's residual (`R − R̂(1+s)`), MOVES THE
    STABILITY BOUNDARY, and inherits slice 26/30's ONE-SIDEDNESS: with `R̂ < 0`, a gyro that
    UNDER-reads (`s < 0`) walks the effective belief toward the ringing side while `s > 0` merely
    de-tunes.
  * a BIAS never touches the belief. It injects a CONSTANT spurious LOS rate `R̂·b` into guidance —
    the arc's FIRST ADDITIVE entry, where 26–30 are all multiplicative gain errors — so it does not
    move the boundary, it moves the AIM POINT, and it is TWO-SIDED: there is no safe direction.

⚠ **THE SCALE FACTOR'S EQUIVALENCE IS EXACT, AND SAYING SO IS THE POINT.** `R̂(1+s)` is a value
`radome_slope_est` can already take, so the scale-factor half ADDS NO MECHANISM on its own — it is
this project's FALSE-FIDELITY trap (slice 15's `k_δ` cancellation, slice 16's refused toggle, slice
19's dead `speed` knob) and it is shipped as a TOOTH, never as a headline. What the equivalence
cannot express is what the slice claims: the error is MULTIPLICATIVE, so its ABSOLUTE size is
`|R̂|·|s|`, and slice 30's design rule "aim `R̂` at `radome_slope_worst`" therefore has to become
`R_worst/(1+s)`. **A feed-forward compensator is an amplifier for its own sensor, with gain `|R̂|`**
— and slice 30 buys unconditional stability precisely by making that gain as large as the glass
demands.

⚠ Pinned to a tight `atol`, NEVER bit-for-bit: `R̂·((1+s)·ω)` and `(R̂·(1+s))·ω` differ in the last
ULP by float non-associativity. An "exact reparameterization" claim in this codebase means the
PHYSICS is the same, not that the bits are.

`scale_err == 0` with a zero `bias` returns `ω_true` componentwise unchanged — but the shipped
no-gyro-error path is a KEY-ABSENT branch upstream that passes `:omega_body` VERBATIM, never this
function at zero (the `-0.0` trap and float non-associativity, the slice-20/21/26/27/28/29
structural-byte-identity shape). That exactness is still pinned here, because it is what makes both
terms KNOBS rather than fidelity rungs (atmosphere.jl's discriminator).

⚠ `scale_err == −1` is the DEAD GYRO: the reading collapses to the bias alone, the feed-forward
vanishes with it, and the missile is slice 26's UNCOMPENSATED missile — a degenerate that is a free
tooth, not an edge case to guard.

⚠ GYRO NOISE IS A NAMED DEFERRAL, ON DRAW-TOPOLOGY GROUNDS (convention 3), not an oversight: a
per-tick random rate error is an unconditional THIRD `randn` on a path that has drawn exactly two
since slice 25, so introducing it desyncs every 25–30 replay — the slice-13 `:scan` 4b shape, which
would need a host marker and an introduce-rejecting `set_fidelity`. Deterministic errors do not.
"""
gyro_reading(ω_true::Vec3, scale_err::Real, bias::Vec3) =
    Vec3((1.0 + scale_err) * ω_true[1] + bias[1],
         (1.0 + scale_err) * ω_true[2] + bias[2],
         (1.0 + scale_err) * ω_true[3] + bias[3])
