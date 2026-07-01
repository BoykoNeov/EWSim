# guidance.jl — the missile guidance kernel: the outer pursuit law + the inner PID
# autopilot (HANDOFF §10 item 9, slice 9 gate 1). Pure, RNG-free, no LinearAlgebra — the
# §9 house style (the dynamics.jl / frames.jl analog).
#
# Slice 8 gave the airframe a passive integrator (forces → accel → vel → pos). Slice 9 puts
# the FIRST closed control loop on it: an outer PURSUIT law computes a commanded lateral
# acceleration that steers the velocity toward the target, and an inner PID AUTOPILOT realizes
# that command through a first-order airframe/actuator lag. Both are PURE functions here (the
# `Autopilot <: Subsystem` that calls them, writing `comp[:a_ctrl]` in `decide!`, lands in
# gate 2, missile.jl — after radar.jl). Included BEFORE radar.jl (so `AUTOPILOT_MODES` precedes
# `LIVE_FIDELITY_MODES` — the `INTEGRATOR_MODES`/`ESTIMATOR_MODES` "mode-const-before-radar,
# one-list-no-drift" precedent), but AFTER frames.jl (it reuses `los_unit`/`_norm3`/`_dot`).
#
# CASCADE ARCHITECTURE (roadmap-required — slice 10 is the outer loop, PN): pursuit is a
# STAND-IN outer command. `pursuit_accel` (outer) and `autopilot_step` (inner) are SEPARATE
# pure functions SO THAT slice 10 swaps ONLY `pursuit_accel → pn_accel` without touching the
# inner loop. Own `:autopilot` now; RESERVE `:guidance` (pursuit-vs-PN) for slice 10 (unused —
# the "generic word namespaced by consumption" precedent).
#
# DETERMINISM (the slice-8 discipline — do NOT copy the slice-5/6/7 template): there is NO RNG
# in the missile arc, so "RNG lockstep / draw-count-invariance" is VACUOUS. `:autopilot` is a
# PHYSICS-CHANGING fidelity (the slice-2 `propagation` shape): introduce-safe (absent an
# Autopilot nothing reads it) but a `:ideal↔:pid` toggle CHANGES the trajectory — the
# not-a-dead-knob property, the OPPOSITE of slices 5/6/7.
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden ones):
#   • pursuit reads TARGET TRUTH (no seeker / LOS-rate filtering — slice 11);
#   • the airframe/actuator is a FIRST-ORDER LUMPED-SCALAR lag (τ·ȧ = u − a), NOT a full
#     transfer function / 6-DOF fin model (§11 Tier A);
#   • the PID integrates at the TICK `dt` (fixed-step, matching the integrator);
#   • the `a_max` clamp is a CRASH-GUARD (a live gain slider can't blow up a tick), NOT the
#     lesson — g-limit-saturation-as-lesson is slice 10, and the scenario is tuned so it
#     never binds.

# The autopilot-fidelity rungs. The SINGLE source of truth (the INTEGRATOR_MODES precedent):
# gate-2's `LIVE_FIDELITY_MODES` (radar.jl) REFERENCES this, and `autopilot_step` dispatches
# on it — so a value the wire accepts can never reach a tick that throws. Defined HERE
# (guidance.jl precedes radar.jl) so that reference needs no include-order gymnastics.
#   • `:ideal` — the actuator is perfect, `a_ach ≡ a_cmd` instantly (the reference).
#   • `:pid`   — a realistic first-order lag closed by a PID on the accel error (the lesson:
#     P-only undershoots by exactly `1/(1+Kp)`, I drives the steady-state error to 0, D damps).
const AUTOPILOT_MODES = (:ideal, :pid)

# The inner-loop PID state, carried per-missile across ticks (in the entity `comp` in gate 2):
#   • `a_ach`  — the plant output (achieved control accel), the first-order-lag state;
#   • `e_int`  — the integral of the accel error `∫e dt` (the I term's memory);
#   • `e_prev` — the previous-step error (for the discrete derivative `ė ≈ (e−e_prev)/dt`).
# All Vec3 (the control accel is a 3-D vector). A NamedTuple keeps `autopilot_step` type-stable
# and pure (returns a fresh state, never mutates).
const AutopilotState = @NamedTuple{a_ach::Vec3, e_int::Vec3, e_prev::Vec3}

"""
    autopilot_init() -> AutopilotState

The zero PID state (`a_ach = e_int = e_prev = 0`): the launch/reset condition, before any
command has been applied. The `e_prev = 0` start gives the usual first-step derivative kick
(harmless — the `a_max` clamp guards the command, and the plant lag `τ` bounds the response).
"""
autopilot_init() = (a_ach = zero(Vec3), e_int = zero(Vec3), e_prev = zero(Vec3))

"""
    pursuit_accel(m_pos::Vec3, m_vel::Vec3, t_pos::Vec3; k_guid = 3.0) -> Vec3

The OUTER pure-pursuit guidance law (§1): command a lateral acceleration that steers the
missile's velocity toward the line-of-sight to the target.

    v̂    = v / ‖v‖                                  (heading)
    los  = los_unit(m_pos, t_pos)                   (frames.jl)
    perp = los − (los·v̂) v̂                          (LOS component ⟂ to heading)
    a_cmd = (k_guid · ‖v‖) · perp                    (m/s²)

`a_cmd` is PERPENDICULAR to the heading (a pure turn, no speed change — the coast assumption),
so `a_cmd · v̂ = 0`. `k_guid` (units 1/s) is a turn-rate gain. **Named as a pursuit law,
honestly (HANDOFF §10 item 9):** it points AT the target, does NOT LEAD it — the tail-chaser
slice 10's proportional navigation replaces. The endgame demand `‖a_cmd‖` GROWS as range
closes (the tail-chase, surfaced as telemetry, the slice-10 tee-up). Zero-speed (`v→0`, apex/
launch) or zero-range (coincident) → zero command (no NaN).
"""
function pursuit_accel(m_pos::Vec3, m_vel::Vec3, t_pos::Vec3; k_guid::Real = 3.0)
    spd = _norm3(m_vel)
    spd < _FRAME_EPS && return zero(Vec3)
    v̂ = m_vel / spd
    los = los_unit(m_pos, t_pos)                    # zero-range guard inside → zero vector
    perp = los - _dot(los, v̂) * v̂                    # LOS ⟂ to heading
    return (k_guid * spd) * perp
end

"""
    clamp_accel(a::Vec3, a_max::Real) -> Vec3

Magnitude clamp: if `‖a‖ > a_max` scale `a` down to `a_max` (preserving direction), else
return `a` unchanged. Zero-safe (`a = 0` → `0`, no NaN) AND **non-finite-safe** (`a` with an
`Inf`/`NaN` component → `0`): as the DESIGNATED crash-guard primitive it must never itself emit
NaN, even if a caller threads a diverged `Inf` accel (a badly-tuned discrete PID CAN diverge —
gate 2 — and `Inf·(a_max/Inf) = NaN` would otherwise leak into `pos` → invalid state-frame
JSON). This is the CRASH-GUARD (§1 named approximation): a huge `k_guid`/`Kp` slider can't blow
up a tick — but the scenario is tuned so it NEVER binds (g-limit-saturation-as-lesson is slice
10, so a binding clamp would silently import that lesson).
"""
function clamp_accel(a::Vec3, a_max::Real)
    mag = _norm3(a)
    isfinite(mag) || return zero(Vec3)              # a diverged Inf/NaN accel → safe zero
    (mag <= a_max || mag < _FRAME_EPS) && return a
    return a * (a_max / mag)
end

"""
    autopilot_step(mode::Symbol, a_cmd::Vec3, state::AutopilotState, dt::Float64;
                   kp = 1.0, ki = 0.0, kd = 0.0, tau = 0.3) -> (a_ach::Vec3, state′::AutopilotState)

One step of the INNER autopilot loop (§2), dispatching on `mode ∈ AUTOPILOT_MODES`:

  • `:ideal` — the perfect actuator: `a_ach ≡ a_cmd` instantly, state RETURNED UNCHANGED
    (bit-exact passthrough — the reference the PID is measured against).
  • `:pid`   — a first-order airframe/actuator plant `τ·ȧ_ach = u − a_ach` (fin command `u`
    → achieved accel) closed by a PID on the accel error `e = a_cmd − a_ach`:

        e      = a_cmd − a_ach                        (a_ach = state.a_ach, last plant output)
        e_int′ = e_int + e·dt                         (integral memory)
        ė      = (e − e_prev) / dt                     (discrete derivative)
        u      = Kp·e + Ki·e_int′ + Kd·ė               (fin command)
        a_ach′ = a_ach + ((u − a_ach)/τ)·dt            (one forward-Euler plant step)

    **Closed-form headline (the `½·g·dt·t` of slice 9):** under P-only (`Ki = Kd = 0`) the
    loop settles to a steady-state undershoot `‖a_cmd − a_ach‖ / ‖a_cmd‖ = 1/(1+Kp)` (33.3 % at
    `Kp = 2`, 11.1 % at `Kp = 8`). Integral action drives that error to 0; derivative damps the
    overshoot.

`state` is per-missile; the caller threads `state′` back for the next tick. Reuses the tick
`dt` (fixed-step, matching the integrator — §1 named approximation).
"""
function autopilot_step(mode::Symbol, a_cmd::Vec3, state::AutopilotState, dt::Float64;
                        kp::Real = 1.0, ki::Real = 0.0, kd::Real = 0.0, tau::Real = 0.3)
    if mode === :ideal
        # Perfect actuator: pass the command through, state untouched (the PID is dormant).
        return a_cmd, state
    elseif mode === :pid
        a_ach  = state.a_ach
        e      = a_cmd - a_ach
        e_int  = state.e_int + e * dt
        ė      = (e - state.e_prev) / dt
        u      = kp * e + ki * e_int + kd * ė
        τ      = max(Float64(tau), _FRAME_EPS)          # a live τ→0 slider can't divide-by-zero
        a_ach′ = a_ach + ((u - a_ach) / τ) * dt
        return a_ach′, (a_ach = a_ach′, e_int = e_int, e_prev = e)
    end
    error("autopilot_step: unknown autopilot :$mode ($(join(AUTOPILOT_MODES, " | ")))")
end
