# airframe3d.jl — the 6-DOF SUBSTRATE + SKID-TO-TURN steering (HANDOFF §11 Tier-A, slice 23
# gate 1). Pure, RNG-free, no LinearAlgebra — the §9 house style. REUSES frames.jl's quaternion
# algebra (qmul/rotate/rotate_inv/qnormalize — already 3-D and tested); this file adds the
# rigid-body dynamics, the ⟂-v body aerodynamics, and the 2-plane STT command inversion.
#
# THE 3-D SUPERSET of the pitch-plane airframe.jl. Slices 16–22 built a complete PITCH-PLANE
# airframe: the missile makes its maneuver g from lift in ONE plane (x–z) and `alpha_command`
# (slice 19) PROJECTS the guidance command onto the in-plane direction and DISCARDS the
# out-of-plane component — a target maneuvering out of the x–z plane is UNFLYABLE BY
# CONSTRUCTION. Slice 23 cashes that named approximation: `att` becomes a genuine 3-D
# quaternion integrated from a body-rate vector ω = (p, q, r), the guidance command keeps its
# full 3-D direction, and a SKID-TO-TURN autopilot makes lift in BOTH body planes at once
# (angle of attack α → pitch lift, sideslip β → yaw lift), so the ⟂-v accel can point anywhere.
#
# ⭐ THE SIGN WIRING IS THE #1 SIGN TRAP'S FIFTH OCCURRENCE (16 = the moment sign, 17 = the lift
# direction, 19 = the a→α→δ→M→α→lift→γ̇ chain, 22 = the moment break; here the body↔inertial
# `rotate` direction and the per-axis ω sign). Pinned in test_airframe3d.jl by the P1a STRUCTURAL
# INVARIANT (an in-plane run keeps the out-of-plane states at the FP floor — gate-0 measured them
# at EXACTLY 0.0) and per-axis lift/moment-sign teeth. Two subtleties, both gate-0 findings:
#   • `att` maps body→inertial (`rotate(att,[1,0,0])` = the nose in inertial). Kinematics
#     q̇ = ½ q ⊗ [0, ω_body]. The ⟂-v body axes and signed incidence below reduce EXACTLY to
#     `lift_accel` in-plane (verified bit-for-bit; n̂_pitch = (−sinγ,0,cosγ) to 1e-16).
#   • ⚠ THE PITCH/YAW MOMENT SIGN IS *NOT* SYMMETRIC. Under `rotate`, physical NOSE-UP (α+,
#     +x→+z) is a −y body rotation, but physical NOSE-TOWARD-+y (β+, +x→+y) is a +z body
#     rotation. So the pitch aero moment maps to −y (NEGATED) and the yaw aero moment maps to +z
#     (NOT negated), and the physical incidence rates are α̇ = −ω_y, β̇ = +ω_z. Feeding +ω_y to the
#     pitch loop (the naïve "ω IS the rate") DIVERGES it (gate-0 C4: α → 3.11 rad tumble).
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden ones):
#   • DIAGONAL inertia (I_xx ≪ I_yy = I_zz). The ω×(I·ω) gyroscopic term IS included (correct
#     rigid-body form, cheap), but at STT's single-axis ω it is ≈0 (gate-0 P6: trajectory diff
#     on/off = EXACTLY 0.0). The roll-pitch-yaw inertial coupling that a non-diagonal I and a
#     large p produce — and the aero cross-derivatives (Clβ, Cnp, Clr, radome) that make a real
#     BANK-to-turn airframe DEPART — are DEFERRED (slice 24 / the departure lesson).
#   • SYMMETRIC CRUCIFORM: the yaw side-force slope C_Yβ defaults to C_Lα, and the yaw static/
#     control/damping derivatives reuse the pitch (Cma/Cmd/Cmq). A real airframe's differ.
#   • ROLL is held ≈0 by a pure damper — STT does not bank. The roll COMMAND (bank-to-turn) and
#     its finite bandwidth are slice 24's lesson.
#   • Lift is drag-free (⟂ v, speed-preserving) as in slice 17 — induced/separation drag on the
#     6-DOF path is a later composition (slices 20/22 in 3-D), not this slice.

# --- the ⟂-v body axes + signed incidence -------------------------------------------
# n̂_pitch / n̂_yaw are the components of the body "up" / "right" axes perpendicular to v̂
# (Gram-Schmidt), i.e. the two orthogonal ⟂-v directions the cruciform lift acts along. In the
# pitch plane (roll = 0, β = 0) n̂_pitch = (−sin γ, 0, cos γ) EXACTLY, so `lift_accel_3d` reduces
# to `lift_accel` and `body_incidence`'s α equals θ − γ. Zero-length guards mirror frames.jl.
function body_perp_axes(q::Quat, vhat::Vec3)
    zu = rotate(q, Vec3(0.0, 0.0, 1.0))          # body "up"
    yw = rotate(q, Vec3(0.0, 1.0, 0.0))          # body "right" (+y)
    np = zu - _dot(zu, vhat) * vhat
    ny = yw - _dot(yw, vhat) * vhat
    nnp = _norm3(np); nny = _norm3(ny)
    np = nnp > _AIRFRAME_DENOM_FLOOR ? np / nnp : zero(Vec3)
    ny = nny > _AIRFRAME_DENOM_FLOOR ? ny / nny : zero(Vec3)
    return np, ny
end

"""
    body_incidence(q::Quat, vel::Vec3) -> (α, β)

The signed angle-of-attack `α` (pitch incidence) and sideslip `β` (yaw incidence), each the
angle of the nose off the velocity measured in the corresponding ⟂-v plane:

    α = atan(nose·n̂_pitch, nose·v̂),   β = atan(nose·n̂_yaw, nose·v̂)

In the pitch plane this gives `α = θ − γ` EXACTLY (the slice-16..22 scalar convention) and
`β = 0`. Zero-speed guard returns `(0, 0)` (apex / launch — a live tick can't crash, convention 5).
"""
function body_incidence(q::Quat, vel::Vec3)
    V = _norm3(vel)
    V < _AIRFRAME_V_FLOOR && return (0.0, 0.0)
    vhat = vel / V
    np, ny = body_perp_axes(q, vhat)
    nz = rotate(q, Vec3(1.0, 0.0, 0.0))          # nose
    α = atan(_dot(nz, np), _dot(nz, vhat))
    β = atan(_dot(nz, ny), _dot(nz, vhat))
    return α, β
end

"""
    lift_accel_3d(vel::Vec3, q::Quat, mass, p::AirframeParams; c_yaw = p.Cla) -> Vec3

The 2-plane body-lift specific force (m/s²) — the 3-D superset of [`lift_accel`](@ref):

    a_lift = (Q·S/m)·(C_Lα·α·n̂_pitch + C_Yβ·β·n̂_yaw),   Q = ½·ρ·V²

pitch lift on `n̂_pitch` (∝ α, slope `C_Lα = p.Cla`), yaw side-force on `n̂_yaw` (∝ β, slope
`c_yaw`, defaulting to `p.Cla` — a symmetric cruciform). Both act ⟂ v, so lift turns the path
WITHOUT changing speed; with the ⟂ axes above the resultant can point ANYWHERE off v̂ (the whole
point of STT). Reduces to `lift_accel` in the pitch plane (β = 0, roll = 0). `V ≤ _AIRFRAME_V_FLOOR`
returns zero (Q → 0 already kills it; the ÷0 guard — convention 5).
"""
function lift_accel_3d(vel::Vec3, q::Quat, mass::Float64, p::AirframeParams; c_yaw::Float64 = p.Cla)
    V = _norm3(vel)
    V ≤ _AIRFRAME_V_FLOOR && return zero(Vec3)
    vhat = vel / V
    np, ny = body_perp_axes(q, vhat)
    α, β = body_incidence(q, vel)
    Q = 0.5 * p.rho * V^2
    return (Q * p.S / mass) * (p.Cla * α * np + c_yaw * β * ny)
end

# --- 3-D rigid-body dynamics --------------------------------------------------------

"""
    attitude_kinematics(q::Quat, ω::Vec3) -> Quat

The quaternion rate `q̇ = ½ q ⊗ [0, ω_body]` — `att` maps body→inertial, `ω` is the body-frame
angular velocity `(p, q, r)`. A constant +ω_y rotates the nose +x→−z (gate-0 C1), so physical
nose-up is a −y rate; the moment mapping in [`stt_moments`](@ref) accounts for it.
"""
attitude_kinematics(q::Quat, ω::Vec3) = 0.5 * qmul(q, Quat(0.0, ω[1], ω[2], ω[3]))

"""
    body_rate_deriv(ω::Vec3, M_body::Vec3, Idiag::Vec3) -> Vec3

Euler's rigid-body equation `ω̇ = I⁻¹·(M_body − ω×(I·ω))` for a DIAGONAL inertia
`Idiag = (I_xx, I_yy, I_zz)`. The ω×(I·ω) gyroscopic term is the correct rigid-body form and is
kept (cheap); at STT's single-axis ω it is ≈0 (gate-0 P6). The roll–pitch–yaw coupling a large
`p` / non-diagonal `I` produce is slice 24's / the departure lesson (named §deferral).
"""
function body_rate_deriv(ω::Vec3, M_body::Vec3, Idiag::Vec3)
    Iω  = Vec3(Idiag[1]*ω[1], Idiag[2]*ω[2], Idiag[3]*ω[3])
    rhs = M_body - _cross(ω, Iω)
    return Vec3(rhs[1]/Idiag[1], rhs[2]/Idiag[2], rhs[3]/Idiag[3])
end

# Physical incidence rates — what the aero Cmq damping AND the autopilot's −k_q·rate term must
# oppose. α̇ = −ω_y (nose-up), β̇ = +ω_z (nose-+y). Passing the raw +ω_y to the pitch loop diverges
# it (gate-0 C4). NAMED helpers so the sign lives in exactly one place (convention 7).
pitch_rate_phys(ω::Vec3) = -ω[2]
yaw_rate_phys(ω::Vec3)   =  ω[3]

"""
    stt_moments(q, vel, ω, δp, δy, p::AirframeParams; c_roll) -> Vec3

The body-axis aerodynamic moment `M_body = (M_x, M_y, M_z)` (N·m) for the skid-to-turn airframe,
reusing [`pitch_moment`](@ref)'s three-term form per channel (symmetric cruciform):

    M_pitch_phys = Q·S·d·(Cmα·α + Cmδ·δp + Cmq·q̄_phys),   q̄_phys = α̇·d/(2V),  α̇ = −ω_y
    M_yaw_phys   = Q·S·d·(Cmα·β + Cmδ·δy + Cmq·r̄_phys),   r̄_phys = β̇·d/(2V),  β̇ = +ω_z
    M_body       = (−c_roll·p,  −M_pitch_phys,  +M_yaw_phys)

⚠ THE ±: physical nose-up is a −y body rotation but nose-+y is a +z rotation (gate-0 C1/C5), so
the PITCH aero moment is negated onto −y and the YAW aero moment maps to +z UN-negated — the
frame is NOT sign-symmetric between the two channels. Roll is a pure damper `−c_roll·p` (STT holds
`p ≈ 0`). The `_AIRFRAME_V_FLOOR` q̄/r̄ guard is `pitch_moment`'s (a live tick at apex can't crash).
"""
function stt_moments(q::Quat, vel::Vec3, ω::Vec3, δp::Float64, δy::Float64,
                     p::AirframeParams; c_roll::Float64)
    V = _norm3(vel)
    α, β = body_incidence(q, vel)
    Q  = 0.5 * p.rho * V^2
    qbp = V > _AIRFRAME_V_FLOOR ? pitch_rate_phys(ω) * p.d / (2.0 * V) : 0.0
    rbp = V > _AIRFRAME_V_FLOOR ? yaw_rate_phys(ω)   * p.d / (2.0 * V) : 0.0
    M_pitch_phys = Q * p.S * p.d * (p.Cma * α + p.Cmd * δp + p.Cmq * qbp)
    M_yaw_phys   = Q * p.S * p.d * (p.Cma * β + p.Cmd * δy + p.Cmq * rbp)
    return Vec3(-c_roll * ω[1], -M_pitch_phys, M_yaw_phys)
end

"""
    rk4_6dof(f, pos, vel, q, ω, dt) -> (pos′, vel′, q′, ω′)

One classical 4-stage RK4 step of the joint state `[pos, vel, q, ω]`, where
`f(pos, vel, q, ω) -> (ṗ, v̇, q̇, ω̇)`. The `rk4_coupled` sibling for 6-DOF — a FRESH stepper (the
coupling is the mid-stage re-evaluation of the flight condition inside `f`, not operator-splitting;
the slice-17 precedent). The quaternion is RE-NORMALIZED each stage and at the end (`qnormalize`,
the accumulated-drift guard — frames.jl's identity fallback keeps a degenerate normalize NaN-free).
"""
function rk4_6dof(f, pos::Vec3, vel::Vec3, q::Quat, ω::Vec3, dt::Float64)
    p1, v1, q1, w1 = f(pos,          vel,          q,                      ω)
    p2, v2, q2, w2 = f(pos+dt/2*p1,  vel+dt/2*v1,  qnormalize(q+dt/2*q1),  ω+dt/2*w1)
    p3, v3, q3, w3 = f(pos+dt/2*p2,  vel+dt/2*v2,  qnormalize(q+dt/2*q2),  ω+dt/2*w2)
    p4, v4, q4, w4 = f(pos+dt*p3,    vel+dt*v3,    qnormalize(q+dt*q3),    ω+dt*w3)
    pos′ = pos + dt/6*(p1 + 2*p2 + 2*p3 + p4)
    vel′ = vel + dt/6*(v1 + 2*v2 + 2*v3 + v4)
    q′   = qnormalize(q + dt/6*(q1 + 2*q2 + 2*q3 + q4))
    ω′   = ω + dt/6*(w1 + 2*w2 + 2*w3 + w4)
    return pos′, vel′, q′, ω′
end

"""
    steering_command(a_cmd::Vec3, vel::Vec3, q::Quat, mass, p::AirframeParams;
                     alpha_max, c_yaw = p.Cla, q_floor = _AIRFRAME_Q_FLOOR) -> (α_cmd, β_cmd, sat)

The 2-plane STT inversion — the 3-D generalization of [`alpha_command`](@ref) that **does NOT
discard the out-of-plane component**. The guidance command (a Vec3, already `clamp_accel`-ed) is
projected onto the plane ⟂ v, resolved onto the two body ⟂-v axes, and each is inverted through
the aero:

    a_perp3 = a_cmd − (a_cmd·v̂)·v̂                       (the along-v̂ part is unproducible — kept 3-D)
    a_pitch = a_perp3·n̂_pitch,   a_yaw = a_perp3·n̂_yaw
    Q_eff   = max(½ρV², q_floor)                          (the crash-safety floor)
    α_raw   = a_pitch·m/(Q_eff·S·C_Lα),  β_raw = a_yaw·m/(Q_eff·S·c_yaw)

⭐ THE CEILING IS A **RESULTANT** CLAMP `hypot(α_raw, β_raw) ≤ α_max` (gate-0 P4): the total
maneuver-g ceiling is the SAME `a_max_aero = Q·S·|C_Lα|·α_max/m` as the pitch plane — STT
REPOINTS that authority in 3-D, it does not get MORE of it (total incidence `√(α²+β²)` is what
drives stall). `sat` is set when the raw resultant exceeds `α_max` (the aero-ceiling-binding
tell; scaling both axes preserves the per-axis sign self-consistency, so a negative `C_Lα`/`c_yaw`
stays honest — the slice-19 FINDING 9 shape). Degenerates mirror `alpha_command`: `V→0` pegs at
the floor; a ~0 slope on either axis drops that axis to 0 (no lift authority, no divide).
"""
function steering_command(a_cmd::Vec3, vel::Vec3, q::Quat, mass::Float64, p::AirframeParams;
                          alpha_max::Float64, c_yaw::Float64 = p.Cla,
                          q_floor::Float64 = _AIRFRAME_Q_FLOOR)
    V = _norm3(vel)
    vhat = V > _AIRFRAME_V_FLOOR ? vel / V : Vec3(1.0, 0.0, 0.0)
    a_perp = a_cmd - _dot(a_cmd, vhat) * vhat
    np, ny = body_perp_axes(q, vhat)
    Q   = max(0.5 * p.rho * V^2, q_floor)
    denp = Q * p.S * p.Cla
    deny = Q * p.S * c_yaw
    α_raw = abs(denp) < _AIRFRAME_DENOM_FLOOR ? 0.0 : _dot(a_perp, np) * mass / denp
    β_raw = abs(deny) < _AIRFRAME_DENOM_FLOOR ? 0.0 : _dot(a_perp, ny) * mass / deny
    mag = sqrt(α_raw^2 + β_raw^2)
    if mag > alpha_max
        s = alpha_max / mag
        return (α_raw * s, β_raw * s, true)
    end
    return (α_raw, β_raw, false)
end
