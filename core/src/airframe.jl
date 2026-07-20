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
    Cla::Float64    # lift-curve slope ∂C_L/∂α, 1/rad — slice 17: the α→lift→γ coupling. 0 ⇒
                    # decoupled = slice 16.
    K::Float64      # slice 20: the LUMPED induced-drag factor (C_Di = K·C_L², dimensionless).
                    # LAST field (the Cla precedent — slices 16–19 never read it). 0 ⇒ lift is
                    # DRAG-FREE = slices 17/19's named approximation, and `induced_drag_accel`
                    # returns EXACTLY zero.
end

# The 8-arg form — slices 16–19's construction sites (4 in missile.jl, 5 in the tests) keep
# compiling unchanged with K = 0 (no induced drag). The `Cla` precedent: a new LAST field with
# a zero default is additive by construction. NOTE this default is NOT what protects
# byte-identity in the live tick — `_integrate_coupled!` must not CALL the drag term at all
# unless the key is present (a `0.0*v` can mint `-0.0` and `a - (-0.0)` flips a bit the
# reinterpret determinism tests catch; advisor). This is a convenience, not the guard.
AirframeParams(S::Real, d::Real, I::Real, Cma::Real, Cmd::Real, Cmq::Real, rho::Real, Cla::Real) =
    AirframeParams(S, d, I, Cma, Cmd, Cmq, rho, Cla, 0.0)

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

# ─────────────────────────────────────────────────────────────────────────────
# SLICE 19 — the INNER α/g AUTOPILOT (`a_cmd → α_cmd → δ`) + the FLIGHT-CONDITION
# g-limit. Slice 17 coupled α→lift→γ but left δ an authored FIXED trim: the airframe
# curved, it did not AIM. Here the outer law's `a_cmd` is INVERTED THROUGH THE AERO
# into an angle-of-attack command and thence a fin deflection, so the missile flies
# its own PN command *through the airframe* rather than by fiat.
#
# THE LESSON — `a_max_aero = Q·S·C_Lα·α_max/m`. Slices 10/12 capped the missile with a
# NUMBER (`a_max`, authored by the engineer); slice 15 with a g-ONSET RATE (`k_δ·δ̇_max`).
# Here the cap is a PHYSICAL CONSEQUENCE: the airframe can only make the lift its dynamic
# pressure and its stall-limited α allow. Fly at low Q and it cannot pull, no matter what
# the guidance asks. `alpha_command`'s α_max clamp is not a safety hack bolted on beside
# the lesson — it IS `a_max_aero` expressed in code (the round-trip is pinned exactly in
# test_airframe.jl: a demand of exactly `a_max_aero` ⇒ `α_cmd == ±α_max`).
#
# THE SIGN CHAIN IS THE #1 TRAP, THIRD OCCURRENCE IN THIS ARC (slice 16 caught it on the
# moment sign, slice 17 on the lift direction). The chain is now LONGER —
# `a_perp → α_cmd → δ → M → α → lift → γ̇` — so an EVEN number of flips has more places to
# hide, and a magnitude-only test would pass. Every arrow is pinned INDIVIDUALLY in
# test_airframe.jl (gate-0 probe GOAL A), plus the mirror (demand < 0 flips all of them).
#
# NAMED APPROXIMATIONS (HANDOFF §1):
#   • PITCH PLANE ONLY ⇒ any OUT-OF-PLANE component of `a_cmd` is DISCARDED by the signed
#     projection. A pitch-plane α autopilot cannot make y-accel; this CONSTRAINS the
#     scenario to a planar engagement (a target maneuvering out of plane would be
#     unflyable BY CONSTRUCTION and would read as a bug). Bank-to-turn/3-D removes it.
#   • The α_max clamp bounds the COMMAND, not the ACHIEVED α. Lift uses the ACHIEVED α,
#     so a hot α-loop can overshoot the clamp transiently and the ceiling LEAKS (gate-0
#     FINDING 14: at k_α=100 the miss collapses 295→63 m). This is WHY `k_α`/`k_q` are
#     AUTHORED CONSTANTS AND NEVER KNOBS. A true stall would bound the ACHIEVED α — that
#     is the nonlinear `C_L(α)` deferral; the hard clamp is its honest stand-in.
#   • Constant ρ (shared with dynamics.jl) ⇒ **only SPEED moves Q — altitude does NOT**.
#     Say "low dynamic pressure (slow)", never "high altitude", until an exponential
#     atmosphere `ρ(z)` exists (the named deferral).
#   • The rate-limited fin is NOT in this loop (slice-15's `δ̇_max`): δ is commanded and
#     applied within the tick. Note also that slice-15's `FinState.δ` is a **Vec3** in the
#     accel frame while `pitch_moment` takes a **scalar** rad — different frames, NOT
#     literally composable. The halves join CONCEPTUALLY (a fin-commanded coupled
#     airframe is what slice 15 banked δ for); `FinState` is untouched here.
# ─────────────────────────────────────────────────────────────────────────────

# The dynamic-pressure floor for the `a_cmd/Q` divide — THE crash-safety site of this
# slice (convention 5, the `_AIRFRAME_V_FLOOR` precedent). `Q = ½ρV² → 0` at launch/apex
# ⇒ `α_cmd = a_perp·m/(Q·S·C_Lα)` → Inf → NaN into `pos` → an invalid state frame; and a
# throw inside `decide!` lands in the session's IO/EOF-only catch and SILENTLY DROPS the
# connection. Floored, a V→0 tick simply pegs α_cmd at ±α_max (Q tiny ⇒ demand looks
# infinite ⇒ ask for everything) — honest, and it cannot crash.
const _AIRFRAME_Q_FLOOR = 1.0e-3

# The divisor floor for `Q·S·C_Lα` — `af_cla` is a LIVE slider whose slice-17 range reaches
# −5, so it can be dragged THROUGH ZERO while a tick is running. At C_Lα ≈ 0 the airframe
# has no lift authority at all: the honest answer is α_cmd = 0 with the ceiling SATURATED
# (a_max_aero = 0 — you cannot pull anything), not a divide-by-zero. Negative C_Lα is NOT
# degenerate and is NOT floored — see `alpha_command`.
const _AIRFRAME_DENOM_FLOOR = 1.0e-9

"""
    aero_accel_limit(V, mass, p::AirframeParams; alpha_max) -> a_max_aero

**THE HEADLINE READOUT of slice 19** — the flight-condition g-limit (m/s²):

    a_max_aero = Q·S·|C_Lα|·α_max / m,   Q = ½·ρ·V²

the largest lift-borne maneuver acceleration the airframe can make at airspeed `V` while
holding |α| ≤ `alpha_max`. This is the cap that DECIDES the engagement: plotted against
the outer law's demand, THE CROSSING IS THE VERDICT (the analog of slice-18's clearance
sign). Distinguish it from the caps already in the suite (the copy-paste false-claim trap,
convention 4): slice-10/12's `a_max` is an authored MAGNITUDE clamp, slice-15's `k_δ·δ̇_max`
is a g-ONSET RATE cap; this one is a FLIGHT CONDITION — what the air will give you *right
now*. With ρ constant (the named approximation), **only V moves it**.

`|C_Lα|` is deliberately the ABSOLUTE value while `alpha_command` divides by the SIGNED
`C_Lα`: the ceiling is a MAGNITUDE (a negative lift-curve slope still makes lift, it just
needs the opposite-signed α — `alpha_command` flips α_cmd to suit and the two stay
self-consistent; gate-0 FINDING 9). NO Q floor here (unlike `alpha_command`): this is a
pure product with no division — it is finite everywhere on its own, and the true ceiling
at V→0 genuinely IS zero. Flooring the readout would be a hidden approximation (§1); the
floor belongs only at the divide.

⚠ **SLICE 22 GENERALIZED THE `curve` ARM AND LEFT THIS ONE ALONE.** With an `AeroCurveParams`
the ceiling is the lift curve's INTERIOR PEAK, not its value at the clamp — see the `curve`
keyword below. `curve === nothing` (the default, and every slice-19/20/21 call site) takes the
line above TEXTUALLY VERBATIM.
"""
function aero_accel_limit(V::Float64, mass::Float64, p::AirframeParams; alpha_max::Float64,
                          curve::Union{Nothing,AeroCurveParams} = nothing)
    Q = 0.5 * p.rho * V^2
    # ⚠ BOTH OFF-STATES TAKE THE VERBATIM LINEAR LINE, AND THE SECOND ONE IS NOT OPTIONAL. A parked
    # knob (`α_stall > α_max` ⇒ the stall is unreachable) is mathematically the linear ceiling, but
    # computing it as `Q·S·cl_max/m` groups the multiply as `(Q·S)·(Cla·α_max)` where the line below
    # is `((Q·S)·Cla)·α_max` — a 1-ULP difference, which the parked-knob `===` tooth CAUGHT on the
    # wire (461.65182004425594 vs 461.651820044256). That is plan §4's multiply-grouping trap
    # appearing inside the very function that was supposed to be safe from it, and the third time
    # this project has caught the class. The knob-vs-rung argument rests on the parked state being
    # EXACTLY the linear path, so it must route through EXACTLY the linear expression.
    (curve === nothing || alpha_max < curve.alpha_stall) &&
        return Q * p.S * abs(p.Cla) * alpha_max / mass
    # ── SLICE 22 — THE CEILING IS THE CURVE'S OWN INTERIOR PEAK.
    #
    # Slices 19–21 extrapolated the LINEAR curve out to the clamp: `a_max_aero = Q·S·|C_Lα|·α_max/m`
    # assumes the airframe keeps trading α for lift all the way to α_max. It does not. Past
    # `α_stall` `C_L` FALLS, so the largest lift available over `|α| ≤ α_max` is attained INSIDE the
    # interval, at `α_stall`, and no amount of Q buys past it:
    #
    #     a_max_aero = Q·S·C_L_peak/m,   C_L_peak = max_{|α| ≤ α_max} |C_L(α)|
    #
    # ⭐ SUBSTITUTING `cl_peak = C_Lα·α_stall` GIVES THE SLICE'S HEADLINE, AN ALGEBRAIC IDENTITY:
    # the stall/linear ceiling ratio is IDENTICALLY `α_stall/α_max` — Q, S, C_Lα and m ALL CANCEL
    # (gate-0 F8, Δ ≤ 1.1e-16). That is slice 21's ρ-factor identity in a NEW LETTER, and it is why
    # the headline is pinned as a SAME-INPUTS FORMULA comparison and never as a run-vs-run (advisor,
    # plan §3): separation drag makes V diverge between two live arms, so a two-run comparison would
    # not actually be holding Q equal and would stop testing what it claims.
    #
    # CLOSED FORM, NOT A NUMERIC SEARCH (the anchor the tests pin). `C_L` rises to `α_stall` and
    # falls after, so the max over `|α| ≤ α_max` is attained at `α_stall` — reachable here by
    # construction, since the unreachable case already returned above.
    return Q * p.S * abs(cl_peak(p.Cla, curve)) / mass
end

# ─────────────────────────────────────────────────────────────────────────────
# SLICE 22 — TRUE STALL: the NONLINEAR-AERO SIBLINGS. Each is the `_nl` twin of a linear
# function above, and **the linear original is left TEXTUALLY VERBATIM** rather than
# refactored to route through a shared helper (plan §4, the byte-identity trap): today
# `lift_accel` computes `((Q·S)·Cla)·α`, and `Q·S·_cl(α)` is `(Q·S)·(Cla·α)` — a DIFFERENT
# multiply grouping and a possible 1-ULP shift, in a project whose absolute `_sample_z`
# golden and determinism tests are bit-exact and which has already caught this class TWICE
# (`√(snr/2)` vs `√snr·√½`). The stall path branches AROUND the linear arm; it never
# rewrites it.
#
# ⚠ ONE `C_L`, TWO CONSUMERS — THE SHARPEST CHECK IN THE SLICE. `lift_accel_nl` (the turn)
# and `induced_drag_accel_nl` (slice 20's `K·C_L²` bill) MUST route through the SAME
# `lift_coefficient`. If they diverge the missile turns on one lift and is invoiced for
# another, and nothing else in the test set notices. Pinned in test_airframe.jl — a WIRING
# claim, which is why gate 1 explicitly deferred it to here.
#
# ⚠ THE AUTOPILOT'S INVERSION IS DELIBERATELY *NOT* HERE. `alpha_command` still inverts the
# LINEAR `C_L = C_Lα·α` and is UNCHANGED (plan §1). That is the design, not an omission: an
# autopilot carries an internal LINEAR model of its airframe, so a linear inversion that
# OVER-commands α as the real curve goes concave is slice-19's command-vs-achieved gap MADE
# PHYSICAL — and it sidesteps the MULTIVALUED past-peak inverse (two α give one C_L), which
# would author a genuine ambiguity surface into a first stall slice. A stall-aware autopilot
# is a NAMED DEFERRAL, not a thing this slice quietly did.
# ─────────────────────────────────────────────────────────────────────────────

"""
    lift_accel_nl(vel, theta, mass, p::AirframeParams, c::AeroCurveParams) -> Vec3

[`lift_accel`](@ref) on the NONLINEAR lift curve — identical in every respect except that
`C_L` comes from [`lift_coefficient`](@ref) instead of `C_Lα·α`:

    L = Q·S·C_L(α),   a_lift = (L/m)·(−sin γ, 0, cos γ)

so past `α_stall` **pulling HARDER turns you LESS**. That derivative sign change is what is
new in the suite: every prior cap in this project is a MAGNITUDE that saturates (pull harder,
get no more); this one REVERSES.

Same ⟂-v direction, same `_AIRFRAME_V_FLOOR` guard, same sign convention as the linear twin
(`C_Lα > 0`, `α > 0` ⇒ `γ̇ > 0`) — the curve changes the MAGNITUDE of lift, never its
direction. Below `α_stall` it agrees with `lift_accel` to the bit for a parked knob (F7).
"""
function lift_accel_nl(vel::Vec3, theta::Float64, mass::Float64, p::AirframeParams,
                       c::AeroCurveParams)
    V = _norm3(vel)
    V ≤ _AIRFRAME_V_FLOOR && return Vec3(0.0, 0.0, 0.0)
    γ = atan(vel[3], vel[1])
    α = theta - γ
    Q = 0.5 * p.rho * V^2
    L = Q * p.S * lift_coefficient(α, p.Cla, c)
    return (L / mass) * Vec3(-sin(γ), 0.0, cos(γ))
end

"""
    induced_drag_accel_nl(vel, theta, mass, p::AirframeParams, c::AeroCurveParams) -> Vec3

[`induced_drag_accel`](@ref) on the NONLINEAR lift curve — the SAME `C_Di = K·C_L²` polar,
with `C_L` from the SAME [`lift_coefficient`](@ref) `lift_accel_nl` turns on (the consistency
tooth).

⚠ **SLICE 20'S TERM IS CORRECT PAST STALL AND IS NOT "FIXED" HERE** (plan §2 — the framing
that would have oversized this slice). Induced drag genuinely DOES fall with lift², so this
term FALLING as `C_L` collapses is right physics, not a bug. What was missing is
[`separation_drag_accel`](@ref), which was legitimately ≈0 in attached flow (hence slices
17–21 never needed it) and RISES steeply past the stall. The two are ADDITIVE and move
OPPOSITE ways past the peak — that is how you tell them apart, and it is a tooth.
"""
function induced_drag_accel_nl(vel::Vec3, theta::Float64, mass::Float64, p::AirframeParams,
                               c::AeroCurveParams)
    V = _norm3(vel)
    V ≤ _AIRFRAME_V_FLOOR && return Vec3(0.0, 0.0, 0.0)
    γ = atan(vel[3], vel[1])
    α = theta - γ
    C_L = lift_coefficient(α, p.Cla, c)
    Q = 0.5 * p.rho * V^2
    D = Q * p.S * p.K * C_L^2
    return -(D / (mass * V)) * vel
end

"""
    separation_drag_accel(vel, theta, mass, p::AirframeParams, c::AeroCurveParams) -> Vec3

**The post-stall bill** — the separation-drag specific force (m/s²):

    C_Dsep = K_sep·max(0, |α| − α_stall)²        (EVEN in α, EXACTLY 0 below the stall)
    a_sep  = −(Q·S·C_Dsep/m)·v̂                   (ALONG −v̂ — slows, never turns)

A NEW ADDITIVE term, not a correction to an old one. Below `α_stall` it returns EXACTLY
`Vec3(0,0,0)` — not "small" — which is what lets a parked knob leave slices 17–21's drag bill
untouched to the bit.

**IT IS MANDATORY, NOT OPTIONAL, AND IT IS NOT A SECOND LESSON** (plan §2). Lift-collapse +
drag-rise **IS** what stall is: one phenomenon, one event — *pull past the peak → less lift AND
more drag*. Convention 9 is satisfied because there is one toggled thing, not two. A stalled
missile that decelerated LESS would be the OPPOSITE of the lesson.

Direction: `−v̂`, like induced drag, so the ⟂/∥ decomposition of the whole aero stays clean —
lift is the ONLY term that turns the path. Same `_AIRFRAME_V_FLOOR` ÷V guard.
"""
function separation_drag_accel(vel::Vec3, theta::Float64, mass::Float64, p::AirframeParams,
                               c::AeroCurveParams)
    V = _norm3(vel)
    V ≤ _AIRFRAME_V_FLOOR && return Vec3(0.0, 0.0, 0.0)
    γ = atan(vel[3], vel[1])
    α = theta - γ
    # ⚠ THE BELOW-STALL ARM RETURNS THE EXACT ZERO VECTOR, AND THE EARLY RETURN IS WHY IT CAN.
    # Falling through with `C_Dsep = 0.0` gives `-(0.0/(m·V))·vel` = `Vec3(-0.0,-0.0,-0.0)`, NOT
    # `Vec3(0,0,0)` — the `-0.0` trap this project documents at the slice-20 induced-drag gate,
    # caught here by its own `===` tooth on the first run. It is harmless in the sum (`a + (-0.0)`
    # is `a`), but a term that claims to contribute EXACTLY nothing below the stall must actually
    # do so, or the parked-knob byte-identity argument rests on a value that is not what it says.
    C_Dsep = separation_drag_coefficient(α, c)
    C_Dsep == 0.0 && return Vec3(0.0, 0.0, 0.0)
    Q = 0.5 * p.rho * V^2
    D = Q * p.S * C_Dsep
    return -(D / (mass * V)) * vel
end

"""
    pitch_moment_nl(alpha, delta, q, V, p::AirframeParams, c::AeroCurveParams) -> M

[`pitch_moment`](@ref) with the `Cmα·α` static term replaced by the THREE-SLOPE
[`moment_coefficient`](@ref) — **relaxed static stability**. The control (`Cmδ·δ`) and damping
(`Cmq·q̄`) terms and the `_AIRFRAME_V_FLOOR` q̄ guard are unchanged.

⚠ **THIS IS THE HIGHEST-RISK EDIT IN THE SLICE AND IT IS WHY IT IS A SEPARATE FUNCTION.**
`pitch_moment` is the function slices 16–21 ALL build on, live at THREE call sites
(`airframe_step`, `_integrate_airframe!`, `_integrate_coupled!`'s closure). Its sum is NOT
refactored — the linear arm above is byte-for-byte what it always was, and the plan's #4
multiply-grouping trap applies to `Q*p.S*p.d*(p.Cma*alpha + ...)` with full force.

⚠ **AND THIS PUTS THE ARC'S #1 SIGN TRAP BACK INSIDE THE EXACT FUNCTION SLICE 16 FOUND IT IN**
(4th occurrence: 16 = the moment sign, 17 = the lift direction, 19 = the a→α→δ→M→α→lift→γ̇
chain). The break is therefore pinned BY SIGN — `∂Cm/∂α < 0` below `α_break`, `> 0` above —
never by magnitude: getting it backwards would make an unstable airframe SELF-RIGHT, deleting
the second lesson entirely while passing any magnitude-based check.

THE LESSON THIS CARRIES IS **NOT** "IT TUMBLES" (gate-0 Decision 2, and the miss is NOT its
metric — +1.4% even at full tumble): a statically unstable airframe is PERFECTLY FLYABLE until
the autopilot runs out of authority. The THRESHOLD is the lesson — a sharp cliff between
`Cma_post` 4 (holds) and 8 (loses) — which is real fly-by-wire physics.
"""
function pitch_moment_nl(alpha::Float64, delta::Float64, q::Float64, V::Float64,
                         p::AirframeParams, c::AeroCurveParams)
    Q = 0.5 * p.rho * V^2
    qbar = V > _AIRFRAME_V_FLOOR ? q * p.d / (2.0 * V) : 0.0
    return Q * p.S * p.d * (moment_coefficient(alpha, p.Cma, c) + p.Cmd * delta + p.Cmq * qbar)
end

"""
    short_period_freq_nl(V, alpha, p::AirframeParams, c::AeroCurveParams) -> ω_sp

[`short_period_freq`](@ref) evaluated at the **LOCAL** static-stability slope
[`moment_slope`](@ref)`(α, Cmα, c)` instead of the constant `p.Cma`.

⭐ **THIS IS WHAT MAKES SLICE 16'S NaN SENTINEL FIRE IN FLIGHT — the second lesson's HEADLINE
TELEMETRY, not a defensive branch.** Slice 16 built the `ω² < 0 ⇒ NaN` guard for an AUTHORED
`Cmα ≥ 0` and it has never fired mid-run in the project's history. Past `α_break` the local
slope is `Cma_post > 0`, so `ω²` goes negative and ω_sp becomes NaN **dynamically, at the moment
of departure**: the readout that says *there is no longer an oscillation to have*. Gate 0 F11
measured it firing for 0.747 s starting at t = 3.435.

⚠ Using the CONSTANT `p.Cma` here would report a healthy real ω_sp for a departed airframe —
a readout describing a different missile than the one on screen, which is precisely slice 21's
`_atm_on` bug class. The NaN is `_finite`-clamped to `FINITE_CEIL` at the wire (convention 6);
that path is walked with a departure in progress at gate 3 (P3c), since it has never been
exercised this way.
"""
function short_period_freq_nl(V::Float64, alpha::Float64, p::AirframeParams, c::AeroCurveParams)
    Q = 0.5 * p.rho * V^2
    ω² = -moment_slope(alpha, p.Cma, c) * Q * p.S * p.d / p.I
    return ω² < 0.0 ? NaN : sqrt(ω²)
end

"""
    trim_alpha_nl(delta, alpha, p::AirframeParams, c::AeroCurveParams) -> α_trim

[`trim_alpha`](@ref) at the **LOCAL** slope, the [`short_period_freq_nl`](@ref) treatment
applied to the other shipped linearization (both take their slope from the ONE
[`moment_slope`](@ref), so the two readouts cannot drift from each other or from the
integrator).

`α_trim = −(Cmδ/∂Cm∂α|α)·δ`. Past `α_break` the local slope is POSITIVE, so the reported trim
FLIPS SIGN — the honest reading: the balance point that used to attract now REPELS. `δ = 0`
returns EXACTLY `0.0` (the linear twin's degenerate, unchanged), and a local slope crossing 0
gives `±Inf`, `_finite`-clampable.

⚠ A LOCAL LINEARIZATION IS ALL THIS IS. The three-slope `Cm` can have a SECOND balance point
above `α_sat` (deep-stall lock-in — F9's high-α equilibrium); this readout does not search for
it. Naming that is cheaper than pretending a single closed-form trim still describes the whole
curve.
"""
function trim_alpha_nl(delta::Float64, alpha::Float64, p::AirframeParams, c::AeroCurveParams)
    delta == 0.0 && return 0.0
    return -(p.Cmd / moment_slope(alpha, p.Cma, c)) * delta
end

"""
    alpha_command(a_cmd::Vec3, vel::Vec3, mass, p::AirframeParams; alpha_max, q_floor)
        -> (α_cmd, sat::Bool)

**The inversion of the aero — this ONE function holds the crash-safety AND the lesson.**
The outer guidance law's acceleration command (a Vec3, already `clamp_accel`-ed at `a_max`)
becomes the signed angle-of-attack command the inner loop flies:

    γ  = atan(v_z, v_x),   n̂ = (−sin γ, 0, cos γ)     (the lift direction — `lift_accel`'s ⟂)
    a_perp = dot(a_cmd, n̂)                            (SIGNED; OUT-OF-PLANE DISCARDED — §1)
    Q_eff  = max(½ρV², q_floor)                       (← the crash-safety floor)
    α_cmd  = clamp(a_perp·m / (Q_eff·S·C_Lα), ±α_max) (← the clamp IS `a_max_aero`)

`sat` is set when the RAW inversion exceeded ±α_max — the telemetry tell that the aero
ceiling is BINDING, and exactly equivalent to `|a_perp| > aero_accel_limit(V, …)` (the two
names agree BY CONSTRUCTION, not by calibration — pinned by the round-trip test).

The projection onto `n̂` is what makes this the INVERSE of `lift_accel`: lift can only act
⟂ v, so the along-v̂ component of `a_cmd` is unproducible by an airframe (measured at up to
0.55·|a_cmd| in the engagement — and gate-0 FINDING 3 refuted it as a miss contributor at
−0.081 m: the projection marginally HELPS).

Degenerates (a live knob can never crash a tick — convention 5):
  • `V → 0` (launch/apex): the `q_floor` keeps the divide finite; α_cmd pegs at ±α_max.
  • `C_Lα ≈ 0`: no lift authority ⇒ returns `(0.0, true)` — the ceiling is zero and you are
    saturated against it. Honest, and no divide.
  • `C_Lα < 0` (the slider's range reaches −5): NOT degenerate and NOT floored — the divide
    by a SIGNED `C_Lα` flips α_cmd's sign, and `lift ∝ C_Lα·α` then puts the lift back on
    +n̂ exactly as commanded. The inversion is self-consistent through zero (FINDING 9).
"""
function alpha_command(a_cmd::Vec3, vel::Vec3, mass::Float64, p::AirframeParams;
                       alpha_max::Float64, q_floor::Float64 = _AIRFRAME_Q_FLOOR)
    V = _norm3(vel)
    γ = atan(vel[3], vel[1])
    n̂ = Vec3(-sin(γ), 0.0, cos(γ))
    a_perp = a_cmd[1]*n̂[1] + a_cmd[2]*n̂[2] + a_cmd[3]*n̂[3]   # the out-of-plane discard (§1)
    Q = max(0.5 * p.rho * V^2, q_floor)
    den = Q * p.S * p.Cla
    abs(den) < _AIRFRAME_DENOM_FLOOR && return (0.0, true)    # no lift possible ⇒ ceiling 0
    α_raw = a_perp * mass / den
    return (clamp(α_raw, -alpha_max, alpha_max), abs(α_raw) > alpha_max)
end

"""
    alpha_autopilot_delta(alpha_cmd, alpha, q, p::AirframeParams; k_alpha, k_q, delta_max)
        -> (δ_cmd, defl_sat::Bool)

The inner α-loop: the fin deflection (rad) that flies the achieved α to `alpha_cmd`. The
FEEDFORWARD + FEEDBACK law (`:ff_fb`), the gate-0 pick:

    δ_ff = −(Cmα/Cmδ)·α_cmd                     (the EXACT inverse of `trim_alpha`)
    δ    = clamp(δ_ff + k_α·(α_cmd − α) − k_q·q,  ±δ_max)

The feedforward is slice-17's `trim_alpha` run BACKWARDS — the δ that statically balances
`Cmδ·δ` against `Cmα·α_cmd` (net pitching moment zero AT the commanded α). The feedback
corrects the transient and the `−k_q·q` term is the standard inner RATE loop (it damps the
short-period ring the feedforward alone would leave).

**Why both halves (gate-0 FINDING 4, measured on three airframes):** feedforward ALONE
(`:static`) has no α error but RINGS at +68…+96% overshoot (only aero damping opposes it);
feedback ALONE (`:fb`) is damped but UNDERSHOOTS, settling at the closed-form ratio
`α_ss/α_cmd = Cmδ·k_α/(Cmδ·k_α − Cmα)` — **the slice-9 `1/(1+Kp)` undershoot recurring, one
loop deeper** (gate 0 measured it at 5/6 = −16.67% with its probe gains; at the SHIPPED
Cmδ=3, k_α=1 the same form gives 3/4 = −25%, pinned in test_airframe.jl). Together: no
steady-state error, ~0% overshoot, and stable across ω_sp ∈ [9.7, 68.7] rad/s.

**`k_alpha`/`k_q` are AUTHORED CONSTANTS and MUST NEVER BE KNOBS** (gate-0 FINDING 14): the
α_max clamp bounds the COMMAND while lift uses the ACHIEVED α, so a hot loop overshoots the
clamp and leaks lift ABOVE `a_max_aero` — an exposed gain slider is a live path to eroding
the lesson (at k_α=100 the miss collapses 295→63 m and the fin goes bang-bang).

`defl_sat` reports the δ_max clamp binding — the tell for slice-15's DEFLECTION cap, which
is a FOURTH cap in this plant and an IMPLICIT α ceiling at ≈`(Cmδ/|Cmα|)·δ_max` (gate-0
FINDING 2: it silently contaminated the first causation twin). The showcase pins
`defl_sat == 0` so δ_max is PROVABLY not binding while α_max is — structural, not luck:
δ_peak is deterministic at launch (α = 0, α_cmd pegged) at `(|Cmα|/Cmδ + k_α)·α_max`.
`Cmδ ≈ 0` (no fin authority) drops the feedforward rather than dividing by zero.
"""
function alpha_autopilot_delta(alpha_cmd::Float64, alpha::Float64, q::Float64,
                               p::AirframeParams; k_alpha::Float64, k_q::Float64,
                               delta_max::Float64)
    # The trim inversion — `trim_alpha(δ) = −(Cmδ/Cmα)·δ` solved for δ. At Cmδ ≈ 0 the fin
    # has no authority, so no feedforward exists: drop it (the ÷0 guard) rather than blow up.
    δ_ff = abs(p.Cmd) < _AIRFRAME_DENOM_FLOOR ? 0.0 : -(p.Cma / p.Cmd) * alpha_cmd
    δ_raw = δ_ff + k_alpha * (alpha_cmd - alpha) - k_q * q
    return (clamp(δ_raw, -delta_max, delta_max), abs(δ_raw) > delta_max)
end

# ─────────────────────────────────────────────────────────────────────────────
# SLICE 20 — INDUCED DRAG: **the missile lowers its own ceiling by maneuvering.**
#
# Slices 17/19 shipped an EXPLICIT §1 approximation: *"lift is drag-free / speed-preserving
# (⟂ v)"*. This cashes it. Lift ⟂ v turns the flight path; induced drag ∥ −v̂ SENDS THE
# INVOICE — and the invoice is paid in the very currency that buys the turn:
#
#     pull α → pay K·C_L² in drag → V falls → Q = ½ρV² falls → a_max_aero = Q·S·C_Lα·α_max/m
#            falls → the ceiling CATCHES the demand → you cannot pull → you miss
#
# THE FIRST DEGENERATIVE SPIRAL IN THE PROJECT. Slice 19's ceiling was a flight condition that
# BINDS; slice 20's is a flight condition YOU DEGRADE BY USING IT. The tell (gate-0 FINDING 9):
# the ceiling COLLAPSES 8.4× ACROSS ONE RUN (269 → 32 at K = 0.3) where it is FLAT at K = 0
# (269 → 247, and that 8% is GRAVITY) — with the geometry, the target, α_max, ρ and mass ALL
# HELD. Nobody lowered the ceiling; the missile lowered it, by turning. `aero_sat` climbing
# 0.0% → 55% is the CONSEQUENCE of that collapse, not a second measurement of it (it moves on
# the ceiling AND the demand; the collapse ratio is pure ceiling — advisor).
#
# ⚠ SAY IT PRECISELY: **DEGENERATIVE, NOT "POSITIVE FEEDBACK"** (advisor, gate-3 FINDING 12).
# The SPEED bleed is SELF-LIMITING, not runaway: the bill ∝ Q·α² ∝ V²·α², so as V falls the
# bleed RATE falls. Measured at K = 0.3: `dV/dt` PEAKS at −88.8 m/s² (t ≈ 4.0) and DECAYS to
# −35.8 by CPA; `a_induced` peaks at 81.9 and falls to 23.5; V ASYMPTOTES at ≈213 m/s and the
# ceiling bottoms at ≈25 — NEITHER REACHES ZERO. A positive-feedback loop AMPLIFIES; this
# physical quantity DECELERATES ITSELF, and a physics-literate reader told "positive feedback"
# will hear a speed runaway that never happens. The positive sign lives on the GUIDANCE/
# TRACKING ERROR, and only CONDITIONALLY: below the ceiling PN converges normally (negative
# feedback — that IS why PN works); once the demand crosses the FALLING ceiling the sign FLIPS,
# and the maneuvering that should shrink the error instead bleeds the speed that caps the
# maneuvering. Name the variable, or call it a degenerative (vicious) spiral.
#
# ⚠ THE CLAIM IS BOUNDED — READ THIS BEFORE WRITING ANY LESSON LINE (gate-0 FINDING 5, the
# convention-4 copy-paste false-claim trap): **"bleed → Q → ceiling → miss" is what ANY speed
# loss does.** Matched on ΔV, a PARASITIC `cd_area` reproduces the induced miss and ceiling
# almost exactly (45.02 m / 173.2 vs 44.17 m / 176.3). The spiral's DOWNSTREAM is NOT evidence
# of induced drag. What IS distinctive is the SOURCE of the bill:
#   • induced  = a CLOSED LOOP — written BY THE MANEUVER (∝ α²), self-inflicted. A straight
#     fly-out is billed **0.06 m/s** (gate-0 FINDING 4).
#   • parasitic = an OPEN-LOOP TOLL — set by `cd_area`, arriving whatever you do. The same
#     straight fly-out is billed **75–136 m/s**.
# That contrast is the ONLY thing that earns this slice its title, so it ships as a VERIFIER
# TOOTH (advisor), not as prose.
#
# AND NOT THIS (gate-0 FINDING 7, a prediction REFUTED by its own probe): "a harder engagement
# costs more" is **FALSE** — holding K fixed and hardening the target's maneuver, the
# attributable bill FALLS (194 → 117 m/s), because a harder-maneuvering target SHORTENS
# time-of-flight and the α_max clamp caps α anyway. The showcase target does NOT maneuver at
# all: the missile pays for **its own turn onto the collision course**. Say "the turn you must
# make to intercept bills you", NEVER "dogfighting costs speed".
#
# NAMED APPROXIMATIONS (§1):
#   • `K` is LUMPED (the `cd_area` = "lumped Cd·A" precedent), NOT decomposed as 1/(π·e·AR).
#     This airframe's C_Lα = 20/rad is AUTHORED high (slice 17/19's choice), so C_L reaches ≈3
#     at α = 0.15 and the K that produces a visible spiral is correspondingly large. **Do NOT
#     quote an implied aspect ratio** — C_Lα is not derived from geometry here, so K =
#     1/(π·e·AR) would be false precision.
#   • The polar is QUADRATIC and the lift curve LINEAR (no stall / no C_L roll-off — the
#     nonlinear C_L(α) deferral), and ρ is CONSTANT (shared with dynamics.jl) ⇒ only V moves Q.
#   • ZERO-LIFT drag (`C_D0`, i.e. `cd_area`) is a SEPARATE, already-shipped term and the
#     showcase holds it at 0 — so every m/s the showcase loses is provably bought with α.
# ─────────────────────────────────────────────────────────────────────────────

"""
    induced_drag_accel(vel, theta, mass, p::AirframeParams) -> Vec3

**The bill for the lift** — the induced-drag specific force (m/s², a per-mass acceleration):

    α     = θ − γ,   γ = atan(v_z, v_x)          (angle of attack, flight-path angle)
    C_L   = C_Lα·α                                (the SAME linear lift curve `lift_accel` uses)
    C_Di  = K·C_L²                                (the induced-drag polar — quadratic in lift)
    a_ind = −(Q·S·C_Di / m)·v̂,   Q = ½·ρ·V²       (ALONG −v̂ — pure deceleration)

`induced_drag_accel` is `lift_accel`'s COMPANION AND ITS ORTHOGONAL COMPLEMENT: the same α and
the same `Q·S` build both, but lift acts on `n̂ = (−sin γ, 0, cos γ)` and turns the path at
constant speed, while this acts on `−v̂` and slows the missile without turning it. The two are
⟂ BY CONSTRUCTION — pinned in test_airframe.jl by `dot(a_ind, n̂) == 0` AND `dot(a_ind, v̂) < 0`
(the #1 sign trap: a drag that leaked a ⟂ component would silently become a second, unnamed
lift, and a magnitude-only test would never see it).

**The bill is EVEN in α** (`C_L²`): turning UP costs exactly what turning DOWN costs, and
`α = 0` costs EXACTLY ZERO — a straight-flying missile pays NOTHING. That is the whole
difference from `drag_accel`'s parasitic `cd_area`, which bills a straight flight anyway, and
it is what makes this term a FEEDBACK rather than a toll (see the section header, FINDING 4/5).

`mass` is the MISSILE's (passed, like V/γ — not an airframe constant), mirroring `lift_accel`.
Degenerates (a live knob can never crash a tick — convention 5):
  • `K = 0` ⇒ returns EXACTLY `Vec3(0,0,0)` (the `==` tooth) — lift is drag-free again, i.e.
    slices 17/19's approximation restored. NOTE: the live tick must still GATE THE CALL on key
    presence rather than lean on this (`0.0*v` can mint `-0.0`; see the AirframeParams note).
  • `V ≤ _AIRFRAME_V_FLOOR` (launch/apex): returns zero — Q → 0 kills it anyway, and this is
    the ÷V guard for the `v̂ = v/V` normalization (the `lift_accel` / `pitch_moment` precedent).
  • `K < 0` is NOT floored and is NOT degenerate: it would be a drag that ACCELERATES, which is
    unphysical, so the LOADER rejects it (convention 5's validate-at-LOAD) and the knob's floor
    is 0 — no consumer branch is spent on it.
"""
function induced_drag_accel(vel::Vec3, theta::Float64, mass::Float64, p::AirframeParams)
    V = _norm3(vel)
    V ≤ _AIRFRAME_V_FLOOR && return Vec3(0.0, 0.0, 0.0)
    γ = atan(vel[3], vel[1])
    α = theta - γ
    C_L = p.Cla * α
    Q = 0.5 * p.rho * V^2
    D = Q * p.S * p.K * C_L^2           # the induced drag FORCE (N) — even in α, ≥ 0 for K ≥ 0
    return -(D / (mass * V)) * vel      # ALONG −v̂ (v̂ = vel/V) — slows, never turns
end
