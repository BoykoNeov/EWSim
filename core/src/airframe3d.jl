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

# ─────────────────────────────────────────────────────────────────────────────
# SLICE 24 — BANK-TO-TURN + ROLL-LAG: the steering law that must bank before it turns.
#
# Slice 23's SKID-TO-TURN makes maneuver lift in TWO body planes at once (α → pitch lift, β → yaw
# side-force), so its ⟂-v accel points ANYWHERE off v̂ with no roll — it turns the instant the
# guidance command asks. BANK-TO-TURN makes lift in only ONE body plane (α on the body pitch axis;
# β is actively driven to ≈ 0 — COORDINATED FLIGHT) and must ROLL the body so that single lift plane
# contains the demanded lift. Roll has a FINITE bandwidth τ_roll, so the time spent banking is time
# not turning: against the SAME out-of-plane target STT hit, BTT MISSES (gate-0: STT 0.23 vs BTT
# τ_roll=1.0 → 372 m). τ_roll → 0 recovers STT; τ_roll large saturates toward the pitch-plane DISCARD
# miss (≈ the cross-range offset). This is the 3-D arc's payoff — "you must bank before you turn."
#
# THE `:steering` RUNG (slice-23 §2 reserved it): both laws run on the `:six_dof` plant, the ONLY
# variable is the steering law. `:steering` is INERT without `:airframe === :six_dof` (the scalar
# plant has no roll DOF) — the cross-fidelity dependency, written not implied (the slice-19 shape).
# Class 4c (10th consecutive — truth-fed PN, no seeker ⇒ draw-count invariance VACUOUS).
#
# NAMED APPROXIMATIONS (HANDOFF §1):
#   • ζ = 1 (CRITICALLY-DAMPED roll loop) is what makes τ_roll the SOLE lever — the roll-angle
#     dynamics are a clean 2nd-order in one time constant, so the miss is a clean function of τ_roll
#     alone. A real roll autopilot's damping ratio and actuator lag differ (a 2nd roll knob is
#     deferred). I_xx (roll inertia) MUST stay a NON-knob — it sits inside the roll-loop gain.
#   • The finite bandwidth lives in a MOMENT (M_x → ṗ → q̇ → bank), NOT a kinematic bank-angle lag —
#     the substrate-consistent choice (the roll autopilot produces a torque the 6-DOF integrates).
#   • The COLD-START face: the missile launches wings-level and the lesson is the ~90° roll it must
#     make to point lift cross-range. The SUSTAINED-TRACKING face (a maneuvering demand rotating
#     faster than the roll loop follows — an out-of-plane maneuvering target) is DEFERRED (slice-23
#     §5's route (b)). Both are real BTT physics; this slice ships the cold-start face.
#   • The ω×Iω gyroscopic term (airframe3d.jl `body_rate_deriv`) is INCLUDED and, at BTT's real roll
#     rates under coordinated flight, IMMATERIAL to the miss (gate-0 PROBE D2: ≤ 3% at lesson τ) —
#     because the RATES stay small in the slow-roll regime, NOT because the diagonal-I cross-
#     coefficients are small (they are ~0.9). The aero+inertial cross-coupling that CAUSES a real
#     BTT departure (non-diagonal I, sustained large p, Clβ/Cnp/Clr, radome) is the deferred lesson.

# The steering-law fidelity rung tuple — ONE list (convention 7); `LIVE_FIDELITY_MODES` (radar.jl)
# and the server's `set_fidelity` REFERENCE this, never re-list it. `:skid_to_turn` is slice 23's
# (and the default — a slice-1..23 scenario never sets `:steering`, so the STT path is byte-frozen).
const STEERING_MODES = (:skid_to_turn, :bank_to_turn)

# The ⟂-v BANK REFERENCE frame: û_ref = world-up projected ⟂ v (= n̂_pitch at zero bank, exactly
# (−sin γ, 0, cos γ) in the x–z plane), ŵ_ref = v̂ × û_ref (the right-hand horizontal ⟂-v axis). Bank
# angle φ is measured in this plane (φ = 0 ⇒ wings level, body up = world up). A near-vertical v (û
# degenerate) falls back to world-x projected ⟂ v — a live tick can't crash (convention 5).
function _bank_frame(vhat::Vec3)
    zref = Vec3(0.0, 0.0, 1.0)
    u = zref - _dot(zref, vhat) * vhat
    nu = _norm3(u)
    if nu < _AIRFRAME_DENOM_FLOOR
        xref = Vec3(1.0, 0.0, 0.0)
        u = xref - _dot(xref, vhat) * vhat
        nu = _norm3(u)
    end
    uref = nu > _AIRFRAME_DENOM_FLOOR ? u / nu : Vec3(0.0, 0.0, 1.0)
    wref = _cross(vhat, uref)
    return uref, wref
end

"""
    bank_angle(q::Quat, vel::Vec3) -> φ

The airframe BANK angle `φ` (roll about the velocity vector, rad, in [−π, π]): the body "up" axis
projected ⟂ v (`n̂_pitch`) measured against the [`_bank_frame`](@ref) reference (`φ = atan(n̂_pitch·ŵ,
n̂_pitch·û)`). `φ = 0` is WINGS LEVEL (body up = world up); a bank-to-turn missile rolls to `|φ| ≈ 90°`
to point its single lift plane cross-range. SHARED by [`steering_bank_command`](@ref) (the roll
COMMAND) and the client bank readout, so the sign lives in exactly one place (convention 7 — the #1
SIGN TRAP's 6th occurrence, pinned by the in-plane invariant: an in-plane engagement keeps `φ ≡ 0`).
Zero-speed guard returns `0.0` (apex / launch — a live tick can't crash, convention 5).
"""
function bank_angle(q::Quat, vel::Vec3)
    V = _norm3(vel)
    V < _AIRFRAME_V_FLOOR && return 0.0
    vhat = vel / V
    uref, wref = _bank_frame(vhat)
    np, _ = body_perp_axes(q, vhat)
    return atan(_dot(np, wref), _dot(np, uref))
end

"""
    steering_bank_command(a_cmd::Vec3, vel::Vec3, q::Quat, mass, p::AirframeParams;
                          alpha_max, q_floor = _AIRFRAME_Q_FLOOR) -> (φ_cmd, α_cmd, sat)

The BANK-TO-TURN command inversion — the single-lift-plane counterpart of [`steering_command`](@ref)
(which resolves the demand onto TWO body planes). The guidance command `a_cmd` (a full 3-D Vec3) is
projected onto the plane ⟂ v; the demanded lift direction `L̂` fixes the BANK, and its magnitude `L`
the (signed) angle of attack:

    a_perp = a_cmd − (a_cmd·v̂)·v̂,   L = ‖a_perp‖,   L̂ = a_perp/L
    φ_L    = atan(L̂·ŵ_ref, L̂·û_ref)                         (bank to align +n̂_pitch with L̂, α>0)
    α_cmd  = clamp(sgn·L·m/(Q_eff·S·C_Lα), ±alpha_max),  Q_eff = max(½ρV², q_floor)

⭐ REVERSIBLE LIFT + NEAREST-REPRESENTATION bank (gate-0 PROBE F/G — the load-bearing law): the same
physical ⟂-v lift is `(bank φ_L, α > 0)` OR `(bank φ_L ± π, α < 0)`. Pick whichever bank is the
SHORTER roll from the CURRENT bank `bank_angle(q, vel)`, so an IN-PLANE "pull down" command flips α's
sign (no 180° roll) and a ~90° cross-range bank COMMITS by continuity (no chatter at the ±90° reversal
singularity). `sat` is set when the demand exceeds the aero ceiling `a_max_aero = Q·S·|C_Lα|·α_max/m`
(the SAME single-axis ceiling as slices 19/23 — β ≈ 0 ⇒ the resultant IS |α|; BTT gets no more or less
authority than STT, it just can't POINT it without rolling). Degenerates mirror `steering_command`:
`V → 0` pegs Q at the floor; a ~0 lift slope drops α to 0. The #1 SIGN TRAP's 6th occurrence — the
bank/α sign pair pinned by the in-plane structural invariant.
"""
function steering_bank_command(a_cmd::Vec3, vel::Vec3, q::Quat, mass::Float64, p::AirframeParams;
                               alpha_max::Float64, q_floor::Float64 = _AIRFRAME_Q_FLOOR)
    V = _norm3(vel)
    vhat = V > _AIRFRAME_V_FLOOR ? vel / V : Vec3(1.0, 0.0, 0.0)
    a_perp = a_cmd - _dot(a_cmd, vhat) * vhat
    L = _norm3(a_perp)
    uref, wref = _bank_frame(vhat)
    L̂ = L > _AIRFRAME_DENOM_FLOOR ? a_perp / L : uref
    φ_L = atan(_dot(L̂, wref), _dot(L̂, uref))              # bank to align +n̂_pitch with L̂ (α > 0)
    # NEAREST-REPRESENTATION: choose (φ_L, +1) vs (wrap(φ_L+π), −1) by the shorter roll from φ_now.
    φ_now = bank_angle(q, vel)
    φ_alt = wrap_angle(φ_L + π)
    dL = abs(wrap_angle(φ_L  - φ_now))
    dA = abs(wrap_angle(φ_alt - φ_now))
    φ_cmd, sgn = dL <= dA ? (φ_L, 1.0) : (φ_alt, -1.0)
    Q   = max(0.5 * p.rho * V^2, q_floor)
    den = Q * p.S * p.Cla
    α_raw = abs(den) < _AIRFRAME_DENOM_FLOOR ? 0.0 : sgn * L * mass / den   # signed single-plane α
    sat = abs(α_raw) > alpha_max
    return (φ_cmd, clamp(α_raw, -alpha_max, alpha_max), sat)
end

"""
    btt_roll_moment(φ, φ_cmd, p_roll, I_xx, τ_roll) -> M_x

The ROLL autopilot moment (N·m) for bank-to-turn: a critically-damped (ζ = 1) 2nd-order bank-angle
controller whose ONLY lever is `τ_roll` (the roll time constant, s), with natural frequency
`ω_n = 1/τ_roll`:

    M_x = I_xx·( ω_n²·wrap(φ_cmd − φ) − 2·ω_n·p_roll )

giving `φ̈ ≈ ω_n²·(φ_cmd − φ) − 2·ω_n·φ̇` (a settling time ~4–5·τ_roll). This REPLACES slice 23's pure
roll damper `−c_roll·p` (STT holds `p ≈ 0`; here the autopilot COMMANDS the bank). `I_xx` sits in the
gain, so it MUST stay a NON-knob (else it confounds τ_roll — the slice-19 FINDING-14 discipline); ζ = 1
is the named approximation making τ_roll the sole lever (§header). The bank error is `wrap_angle`d to
the ±π branch so the shorter roll direction is always taken.
"""
function btt_roll_moment(φ::Float64, φ_cmd::Float64, p_roll::Float64, I_xx::Float64, τ_roll::Float64)
    ωn = 1.0 / τ_roll
    return I_xx * (ωn^2 * wrap_angle(φ_cmd - φ) - 2.0 * ωn * p_roll)
end

"""
    btt_moments(q, vel, ω, δp, δy, φ_cmd, p::AirframeParams; I_xx, τ_roll) -> Vec3

The body-axis aerodynamic + control moment `M_body = (M_x, M_y, M_z)` (N·m) for the BANK-TO-TURN
airframe — the [`stt_moments`](@ref) sibling with an IDENTICAL pitch/yaw aero (the arithmetic is
DUPLICATED, not shared, so `stt_moments` stays byte-frozen — "duplicate, don't share") and the ROLL
channel swapped from the pure damper to the [`btt_roll_moment`](@ref) autopilot:

    M_pitch_phys = Q·S·d·(Cmα·α + Cmδ·δp + Cmq·q̄_phys),   q̄_phys = α̇·d/(2V),  α̇ = −ω_y
    M_yaw_phys   = Q·S·d·(Cmα·β + Cmδ·δy + Cmq·r̄_phys),   r̄_phys = β̇·d/(2V),  β̇ = +ω_z
    M_body       = ( btt_roll_moment(φ, φ_cmd, p, I_xx, τ_roll),  −M_pitch_phys,  +M_yaw_phys )

⚠ THE SAME ± ASYMMETRY as `stt_moments`: physical nose-up is a −y body rotation but nose-+y is a +z
rotation, so the pitch aero moment is negated onto −y and the yaw maps to +z un-negated (the gate-0
sign finding). Roll is now the autopilot (bank COMMAND), not the STT damper. The `_AIRFRAME_V_FLOOR`
q̄/r̄ guard is `stt_moments`' (a live tick at apex can't crash).
"""
function btt_moments(q::Quat, vel::Vec3, ω::Vec3, δp::Float64, δy::Float64, φ_cmd::Float64,
                     p::AirframeParams; I_xx::Float64, τ_roll::Float64)
    V = _norm3(vel)
    α, β = body_incidence(q, vel)
    Q  = 0.5 * p.rho * V^2
    qbp = V > _AIRFRAME_V_FLOOR ? pitch_rate_phys(ω) * p.d / (2.0 * V) : 0.0
    rbp = V > _AIRFRAME_V_FLOOR ? yaw_rate_phys(ω)   * p.d / (2.0 * V) : 0.0
    M_pitch_phys = Q * p.S * p.d * (p.Cma * α + p.Cmd * δp + p.Cmq * qbp)
    M_yaw_phys   = Q * p.S * p.d * (p.Cma * β + p.Cmd * δy + p.Cmq * rbp)
    M_x = btt_roll_moment(bank_angle(q, vel), φ_cmd, ω[1], I_xx, τ_roll)
    return Vec3(M_x, -M_pitch_phys, M_yaw_phys)
end
