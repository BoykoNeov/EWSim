# airframe.jl — pitch-plane ROTATIONAL dynamics: the aero pitching moment + a rotational
# integrator (HANDOFF §11 Tier A — the 6-DOF airframe, slice 16 gate 1). Pure, RNG-free,
# no LinearAlgebra — the §9 house style.
#
# The ROTATION analog of dynamics.jl. dynamics.jl integrates TRANSLATIONAL force
# `(ṗ, v̇) = (v, a(v))`; here we integrate the pitch-plane ATTITUDE `(θ̇, q̇) = (q, M/I)`,
# where M is the aerodynamic pitching moment. This is the FIRST rotational state in the
# project — slices 8–15's missile was a point mass whose `att` was a KINEMATIC
# velocity-alignment (a named approximation, missile.jl), never a dynamical quantity.
# Here `att` finally becomes an integrated OUTPUT (gate 2), the way BallisticMissile made
# `pos` a force-integrated output in slice 8.
#
# SCOPE (slice 16, advisor-scoped): pitch plane ONLY (scalar θ, q — the minimal honest
# representation of 1-D rotation; quaternion+ω waits for bank-to-turn/3-D). OPEN-LOOP — no
# guidance closes δ (that is slice 17's inner α/g autopilot). And ISOLATED — rotation does
# NOT feed back into translation (no α→lift→γ coupling); the per-step flight environment
# (V, γ) is READ from the live translation and passed in, but the path is unchanged. The
# α→lift coupling + the `:airframe = point_mass | 6dof` path toggle land slice 17. Framed
# honestly (the slice-15 "lack of effect is the lesson" precedent): slice 16 VALIDATES and
# BANKS the rotational primitive; the trajectory stays byte-identical, the ATTITUDE comes
# alive — Cmα<0 restores/oscillates vs Cmα>0 diverges/tumbles, visible in `att`.
#
# THE #1 SIGN TRAP (frames/signs FIRST — the load-bearing discipline): `Cmα` is the static
# stability derivative ∂Cm/∂α. `Cmα < 0` is STATICALLY STABLE — a nose-up perturbation
# (α>0) makes a nose-DOWN restoring moment (M<0) → oscillation about trim. `Cmα > 0`
# DIVERGES — the airframe tumbles. A DOUBLE sign flip (of both the α = θ−γ definition AND
# the moment sign) oscillates at the SAME ω_sp and passes a frequency-only test, so the
# moment-SIGN is pinned directly in test_airframe.jl (advisor tooth #1), not just ω_sp.
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden ones):
#   • pitch plane only — roll/yaw frozen (a 2-D reduction of the 6-DOF entry; the 3-D
#     superset lands with bank-to-turn, the geometry.jl→frames.jl "2-D first" precedent);
#   • LINEAR aero moment in (α, δ, q̄) — no stall / nonlinear Cm(α) (α-limited maneuver is a
#     later lesson); constant air density ρ (the dynamics.jl approximation, shared);
#   • ISOLATED rotation — no α→lift→γ coupling this slice (slice 17); Q and γ are frozen
#     WITHIN a step (read from translation, constant over the dt), so the closed-form
#     anchors (ω_sp, trim) hold exactly.

# AirframeParams — the immutable authored aero coefficients + reference geometry (the
# "constants of the airframe"), the RadarParams precedent. Validated at LOAD (convention 5:
# S>0, d>0, I>0, ρ>0 — a live tick reads these, so a zero I would divide-by-zero the moment
# equation). The per-tick flight ENVIRONMENT (V, γ) is NOT here — it comes from the live
# translation and is passed to `pitch_moment`/`airframe_step` separately (the slice-16
# isolation: the airframe's constants are fixed; what changes tick-to-tick is the flight
# condition, which rotation does not feed back into).
struct AirframeParams
    S::Float64      # aerodynamic reference area, m²
    d::Float64      # reference length (diameter), m — also the q̄ nondim length
    I::Float64      # pitch moment of inertia, kg·m²
    Cma::Float64    # static stability derivative ∂Cm/∂α, 1/rad — <0 STABLE, >0 DIVERGES (#1 trap)
    Cmd::Float64    # control (fin) effectiveness ∂Cm/∂δ, 1/rad
    Cmq::Float64    # pitch damping derivative ∂Cm/∂q̄, 1/rad — <0 DAMPS (q̄ = q·d/2V)
    rho::Float64    # air density, kg/m³ — constant (named approximation, shared with dynamics.jl)
    Cla::Float64    # lift-curve slope ∂C_L/∂α, 1/rad — slice 17: the α→lift→γ coupling. LAST field
                    # (byte-identity: slice-16 point_mass never reads it). 0 ⇒ decoupled = slice 16.
end

# A speed floor for the q̄ = q·d/(2V) nondimensionalization: at V→0 (launch/apex) the pitch
# damping term is undefined (÷V). Below this, drop the damping contribution to 0 rather than
# blow up (the drag_accel `speed < _FRAME_EPS → 0` precedent; a live tick can't crash).
const _AIRFRAME_V_FLOOR = 1.0e-6

"""
    pitch_moment(alpha, delta, q, V, p::AirframeParams) -> M

The aerodynamic pitching moment (N·m) in the pitch plane:

    q̄ = q·d / (2V)                              (nondimensional pitch rate)
    M  = Q·S·d·(Cmα·α + Cmδ·δ + Cmq·q̄),   Q = ½·ρ·V²   (dynamic pressure)

`α` is the angle of attack (rad, = θ − γ), `δ` the fin deflection (rad, OPEN — no autopilot
this slice), `q` the pitch rate (rad/s), `V` the airspeed (m/s). The three terms are the
static-stability restoring moment (`Cmα·α`), the control moment (`Cmδ·δ`), and the pitch
damping (`Cmq·q̄`). With `Cmα < 0` the α-term is RESTORING (M opposes α). At V ≤ floor the q̄
term is dropped (the ÷V guard) — Q also → 0 there, so the whole moment → 0 (no torque at
rest, physically correct).
"""
function pitch_moment(alpha::Float64, delta::Float64, q::Float64, V::Float64, p::AirframeParams)
    Q = 0.5 * p.rho * V^2
    qbar = V > _AIRFRAME_V_FLOOR ? q * p.d / (2.0 * V) : 0.0
    return Q * p.S * p.d * (p.Cma * alpha + p.Cmd * delta + p.Cmq * qbar)
end

"""
    rk4_rot(qddot, theta, q, dt) -> (θ′, q′)

One classical 4-stage Runge-Kutta step of the rotational system `(θ̇, q̇) = (q, q̈(θ, q))`,
where `qddot` is a closure `(θ, q) -> q̈` (the angular acceleration `M/I`). The generic
stepper (the `rk4_step` sibling) — the caller captures V, γ, δ, and the params INSIDE the
closure, so this stays a pure `(θ, q, dt)` advance. Structured to take the full rotational
state so slice 17's JOINT step over `[pos, vel, θ, q]` reuses the same closure shape (the
coupled airframe integrated in ONE stepper, not two operator-split ones — advisor).

RK4 is EXACT to machine epsilon for the linear short-period ODE (constant coefficients when
V, γ are frozen within the step), so the SHM/trim/damping closed forms pin to ~1e-15.
"""
function rk4_rot(qddot, theta::Float64, q::Float64, dt::Float64)
    # y = (θ, q); dy/dt = (q, q̈(θ, q)).
    k1t = q;                k1q = qddot(theta, q)
    k2t = q + (dt/2)*k1q;   k2q = qddot(theta + (dt/2)*k1t, q + (dt/2)*k1q)
    k3t = q + (dt/2)*k2q;   k3q = qddot(theta + (dt/2)*k2t, q + (dt/2)*k2q)
    k4t = q + dt*k3q;       k4q = qddot(theta + dt*k3t,     q + dt*k3q)
    θ′ = theta + (dt/6)*(k1t + 2*k2t + 2*k3t + k4t)
    q′ = q + (dt/6)*(k1q + 2*k2q + 2*k3q + k4q)
    return θ′, q′
end

"""
    airframe_step(theta, q, dt; gamma, V, delta, p::AirframeParams) -> (θ′, q′)

Advance the pitch-plane attitude `(θ, q)` by one `dt` step under the aero moment, with the
flight condition `(V, γ)` FROZEN over the step (the slice-16 isolation — read from the live
translation, not fed back). The angle of attack is `α = θ − γ`; the angular acceleration is
`q̈ = pitch_moment(α, δ, q, V, p) / I`. Convenience wiring of `pitch_moment` into `rk4_rot`
(the `total_accel` + `integrator_step` pairing, for rotation).
"""
function airframe_step(theta::Float64, q::Float64, dt::Float64;
                       gamma::Float64, V::Float64, delta::Float64, p::AirframeParams)
    qddot = (th, qq) -> pitch_moment(th - gamma, delta, qq, V, p) / p.I
    return rk4_rot(qddot, theta, q, dt)
end

"""
    short_period_freq(V, p::AirframeParams) -> ω_sp

The undamped short-period natural frequency `ω_sp = √(−Cmα·Q·S·d / I)` (rad/s) at airspeed
`V` — REAL when `Cmα < 0` (stable oscillation), and `NaN` (via `√` of a negative) when
`Cmα > 0` (divergent — no oscillation frequency exists). The closed-form anchor the SHM test
pins the integrator against. Q = ½ρV².
"""
function short_period_freq(V::Float64, p::AirframeParams)
    Q = 0.5 * p.rho * V^2
    ω² = -p.Cma * Q * p.S * p.d / p.I
    # Cmα ≥ 0 (neutral/unstable) → no real oscillation frequency. Return NaN rather than let
    # `sqrt` THROW a DomainError (a live Cmα slider crossing zero must not crash a tick —
    # convention 5); a NaN is `_finite`-clampable at the wire.
    return ω² < 0.0 ? NaN : sqrt(ω²)
end

"""
    trim_alpha(delta, p::AirframeParams) -> α_trim

The trim angle of attack `α_trim = −(Cmδ/Cmα)·δ` (rad) — the α at which the control moment
`Cmδ·δ` balances the static moment `Cmα·α` (net pitching moment zero). The CENTER the
undamped short-period oscillation swings about (advisor tooth #3). Independent of V (both
terms scale with Q·S·d). With `δ = 0` (no control input) the trim is EXACTLY `0` for any
Cmα — returned directly, so a live Cmα slider crossing `0` at δ = 0 does NOT hit the `0/0`
NaN (the common case; the readout stays 0, not a spurious `_finite` ceiling spike). With
`δ ≠ 0` and `Cmα → 0` (neutral) no finite trim exists → `±Inf` (a `_finite`-clampable
degenerate, never consumed live without a stable Cmα).
"""
trim_alpha(delta::Float64, p::AirframeParams) = delta == 0.0 ? 0.0 : -(p.Cmd / p.Cma) * delta

# ─────────────────────────────────────────────────────────────────────────────
# SLICE 17 — the α→lift→γ COUPLING (open-loop). The rotation slice 16 BANKED now
# feeds translation: the angle of attack α = θ−γ generates a body lift ⟂ to the
# velocity that TURNS the flight path (α→lift→γ̇). This is the FIRST rotation→
# translation coupling — the reason slice 16 was deliberately ISOLATED (posdiff=0)
# and this slice is not (the `:point_mass ↔ :pitch_coupled` toggle bends the path).
# Still OPEN-LOOP: δ is authored/fixed, no autopilot closes it (slice 18).
# ─────────────────────────────────────────────────────────────────────────────

"""
    lift_accel(vel, theta, mass, p::AirframeParams) -> Vec3

The body-lift specific force (m/s², a per-mass acceleration) in the pitch plane:

    α = θ − γ,   γ = atan(v_z, v_x)                 (angle of attack, flight-path angle)
    L = Q·S·C_Lα·α,   Q = ½·ρ·V²                    (lift force, linear in α)
    a_lift = (L / m)·(−sin γ, 0, cos γ)             (⟂ velocity, in the x–z plane)

The direction `(−sin γ, 0, cos γ)` is `v̂` rotated +90° in the x–z plane, so with
`C_Lα > 0` a positive α (nose above the velocity) lifts the nose UP → `γ̇ > 0` (the
#1 sign trap, pinned in test_airframe.jl by BOTH `dot(a_lift, v̂) ≈ 0` AND the γ̇
sign — a double flip survives a magnitude-only test). Lift is ⟂ v, so it turns the
path WITHOUT changing speed (the steady-turn radius `R = 2m/(ρ·S·C_Lα·α)` anchor).
`mass` is the MISSILE's (passed, like V/γ — it is not an airframe constant). At
`V ≤ _AIRFRAME_V_FLOOR` returns zero (Q→0 already kills it; the ÷0 guard mirrors
`pitch_moment`'s q̄ floor — a live tick at launch/apex can't crash, convention 5).
"""
function lift_accel(vel::Vec3, theta::Float64, mass::Float64, p::AirframeParams)
    V = _norm3(vel)
    V ≤ _AIRFRAME_V_FLOOR && return Vec3(0.0, 0.0, 0.0)
    γ = atan(vel[3], vel[1])
    α = theta - γ
    Q = 0.5 * p.rho * V^2
    L = Q * p.S * p.Cla * α
    return (L / mass) * Vec3(-sin(γ), 0.0, cos(γ))
end

"""
    rk4_coupled(f, pos, vel, theta, q, dt) -> (pos′, vel′, theta′, q′)

One classical 4-stage RK4 step of the JOINT 8-scalar state `[pos, vel, θ, q]`, where
`f(pos, vel, θ, q) -> (ṗ, v̇, θ̇, q̈)` is the coupled derivative (ṗ = vel, v̇ = the
force accel INCLUDING lift, θ̇ = q, q̈ = M/I). The coupled sibling of `rk4_rot` /
`rk4_step` — but a FRESH stepper, not a composition of the two: `f` re-evaluates the
flight condition (V, γ) from the INTERMEDIATE velocity at every stage, so the moment
and the lift see each other WITHIN the step. That mid-step re-evaluation IS the α→lift
coupling — NOT operator-splitting the rotation from the translation (advisor, gate 0).

The decoupled limit is exact: with `C_Lα = 0` and zero translational accel, the vel
stages are all `vel` (V, γ frozen) → the (θ,q) sub-step reproduces `airframe_step` and
the (pos,vel) sub-step reproduces `integrator_step(:rk4)` BIT-FOR-BIT (test_airframe.jl
pins this with `==`). The stage arithmetic is kept unrefactored for that byte-identity.
"""
function rk4_coupled(f, pos::Vec3, vel::Vec3, theta::Float64, q::Float64, dt::Float64)
    a1p, a1v, a1θ, a1q = f(pos,               vel,               theta,               q)
    a2p, a2v, a2θ, a2q = f(pos + dt/2*a1p, vel + dt/2*a1v, theta + dt/2*a1θ, q + dt/2*a1q)
    a3p, a3v, a3θ, a3q = f(pos + dt/2*a2p, vel + dt/2*a2v, theta + dt/2*a2θ, q + dt/2*a2q)
    a4p, a4v, a4θ, a4q = f(pos + dt*a3p,   vel + dt*a3v,   theta + dt*a3θ,   q + dt*a3q)
    pos′   = pos   + dt/6*(a1p + 2*a2p + 2*a3p + a4p)
    vel′   = vel   + dt/6*(a1v + 2*a2v + 2*a3v + a4v)
    theta′ = theta + dt/6*(a1θ + 2*a2θ + 2*a3θ + a4θ)
    q′     = q     + dt/6*(a1q + 2*a2q + 2*a3q + a4q)
    return pos′, vel′, theta′, q′
end

# The `:airframe` fidelity rungs (slice 17) — `:point_mass` (slice 8–16: rotation
# ISOLATED, `att` velocity-aligned or slice-16 free-flying but not fed back) vs
# `:pitch_coupled` (α→lift→γ turns the path). Defined here (before radar.jl) so
# `LIVE_FIDELITY_MODES` and the server's `set_fidelity` reference this ONE list (the
# one-list-no-drift discipline, convention 7). Class 4c: physics-changing, NO RNG.
const AIRFRAME_MODES = (:point_mass, :pitch_coupled)
