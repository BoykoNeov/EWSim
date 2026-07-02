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

# The guidance-fidelity (OUTER-law) rungs — the SINGLE source of truth for the `:guidance`
# key (the AUTOPILOT_MODES precedent, defined HERE so radar.jl's `LIVE_FIDELITY_MODES` can
# REFERENCE it — one-list-no-drift). PHYSICS-CHANGING, NO RNG (the slice-2/8/9 shape, NOT the
# slice-5/6/7 toggle-invariant rungs): introduce-safe (absent a consumer nothing reads it, and
# `get(w.fidelity, :guidance, :pursuit)` defaults to the slice-9 law → byte-identical), but a
# `:pursuit↔:pn` toggle CHANGES the trajectory (not-a-dead-knob — the OPPOSITE of slices 5/6/7,
# so "RNG lockstep / draw-count-invariance" is VACUOUS here; convention 4c).
#   • `:pursuit` — the slice-9 tail-chaser: points AT the target, does not lead (the reference).
#   • `:pn`      — proportional navigation: leads the target by nulling the LOS rotation rate
#     (the collision-triangle law; `|a_cmd|` falls toward a small floor vs pursuit's climb).
#   • `:apn`     — AUGMENTED PN (slice 12): TPN plus a `(N/2)·a_T⊥` feedforward on the TARGET's
#     acceleration ⟂ LOS. Against a MANEUVERING target plain PN lags by the target-accel term and,
#     under a binding g-limit, SATURATES → misses; APN anticipates the maneuver → low demand → no
#     saturation → intercept (HANDOFF §10 item 10 — "g-limit saturation modeled — this is why
#     augmented PN matters"). Reads TRUTH `a_T` (the "even a perfect seeker still lags" framing —
#     RNG-free, no estimated target accel; that fusion is §11 Tier A). Same physics-changing/no-RNG
#     shape as `:pn` — introduce-safe (a CV target has `a_T = 0` → feedforward vanishes → ≈ `:pn`).
# Defined at gate 1; `:apn` NOT YET REFERENCED by a consumer (decide! reads it at gate 2) — so
# adding the rung leaves every slice-1..11 path byte-identical.
const GUIDANCE_MODES = (:pursuit, :pn, :apn)

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
    pn_accel(m_pos::Vec3, m_vel::Vec3, t_pos::Vec3, t_vel::Vec3; N = 4.0) -> Vec3

The OUTER **proportional-navigation** guidance law (§1, slice 10) — the sibling of
[`pursuit_accel`](@ref) the cascade seam was built to swap in. True proportional navigation
(TPN): command a lateral acceleration proportional to the LOS rotation rate `ω` and the
closing speed `Vc`, perpendicular to the LOS:

    r   = t_pos − m_pos                              (relative position, target − missile)
    v   = t_vel − m_vel                              (relative velocity)
    û   = los_unit(m_pos, t_pos)                     (r̂; frames.jl)
    ω   = los_rate(r, v)  = (r × v) / ‖r‖²           (frames.jl — the sign-tested slice-8 kernel)
    Vc  = −range_rate(r, v)                          (closing speed; POSITIVE when closing —
                                                      frames.jl's sign is "negative = closing")
    a_cmd = N · Vc · (ω × û)                          (m/s², ⟂ LOS; N ≈ 3–5, dimensionless)

`ω = r×v/‖r‖²` is ⟂ to `r̂ = û` (a cross product with `r`), so `ω × û` has magnitude `‖ω‖` and
lies **perpendicular to the LOS** — the accel that rotates the velocity to **null `λ̇`**.

**The defining PN property (the test anchor):** on a **constant-bearing, decreasing-range**
(collision-course) geometry `ω = 0 → a_cmd = 0` (the sailor's rule — steady bearing means
collision, no correction). On a **crossing** geometry `ω ≠ 0` and the command turns the missile
to **lead** (unlike pursuit, which points AT the target). Against a NON-maneuvering target PN is
optimal (`a_cmd → 0` at intercept); against a maneuvering target it lags by a target-accel term
(→ augmented PN, slice 11). Reads **target truth** (ω from truth pos/vel — no seeker, slice 11).

**SIGN is the trifecta (HANDOFF §1) — TWO independent sources, both pinned in `test_guidance.jl`:**
the `Vc = −range_rate` term (a `+` flips the whole command) and the cross-product ORDER `ω × û`
(a swap to `û × ω` flips sign but PRESERVES magnitude — the silent one). Zero-guards fall out of
frames.jl (`v→0` / coincident / zero-range → zero ω or zero Vc → zero command; no NaN). The
endgame `r→0` blow-up (`ω → ∞`) is bounded at the CONSUMER (the `r_stop` terminal cutoff +
`a_max` clamp in `decide!`, gate 2), NOT here — `pn_accel` alone stays huge-but-FINITE.
"""
function pn_accel(m_pos::Vec3, m_vel::Vec3, t_pos::Vec3, t_vel::Vec3; N::Real = 4.0)
    r  = t_pos - m_pos                               # relative position (target − missile)
    v  = t_vel - m_vel                               # relative velocity
    û  = los_unit(m_pos, t_pos)                       # r̂ (zero-range guard inside → zero vector)
    ω  = los_rate(r, v)                              # LOS angular rate (zero-range guard inside)
    Vc = -range_rate(r, v)                           # closing speed (POSITIVE when closing)
    return pn_accel_from_omega(û, ω, Vc; N = N)       # ⟂ LOS, N·Vc·‖ω‖ — byte-identical to slice 10
end

"""
    pn_accel_from_omega(û::Vec3, ω::Vec3, Vc::Real; N = 4.0) -> Vec3

The INNER TPN command form (slice 11): `a_cmd = N · Vc · (ω × û)`, taking `û`/`ω`/`Vc`
**already computed** — the swappable-estimate seam PN reads either from **truth** (the
[`pn_accel`](@ref) wrapper, slice 10) or from the **seeker/filter estimate** (the `Autopilot`
`decide!` branch, slice 11), keeping ONE arithmetic path. **No `m_vel` param** — TPN
`N·Vc·(ω×û)` has no missile-velocity term (a dead param would build rotation into the seam —
advisor #6). The cross-product ORDER `ω × û` (not `û × ω`) is the silent sign source; the
`Vc = −range_rate` sign is the other (both pinned in `test_guidance.jl`).

**Byte-identity anchor (the slice-10 truth path must NOT move):** this reproduces the exact
slice-10 inline arithmetic `(N * Vc) * _cross(ω, û)` — same operands, same grouping, same order
(the [`pn_accel`](@ref) wrapper computes `û`/`ω`/`Vc` in the slice-10 order and delegates here),
so a slice-10 `:pn` scenario replays bit-identical (no `√(snr/2)`-style reassociation — conv. 2).
"""
function pn_accel_from_omega(û::Vec3, ω::Vec3, Vc::Real; N::Real = 4.0)
    return (N * Vc) * _cross(ω, û)
end

"""
    pn_accel_augmented(û::Vec3, ω::Vec3, Vc::Real, a_T::Vec3; N = 4.0) -> Vec3

The OUTER **augmented proportional-navigation** command (§1, slice 12) — TPN plus a feedforward
proportional to the TARGET's acceleration **perpendicular to the LOS**:

    a_T⊥  = a_T − (a_T·û) û                           (target accel ⟂ LOS — the component PN must
                                                       counter; the ∥-LOS part changes range, not λ̇)
    a_apn = pn_accel_from_omega(û, ω, Vc; N) + (N/2)·a_T⊥      (m/s², ⟂ LOS)

**Why the feedforward (the lesson).** Plain TPN `N·Vc·(ω×û)` nulls the LOS rate for a
NON-accelerating target (optimal, `a_cmd→0` at intercept). A **maneuvering** target keeps
regenerating LOS rate faster than PN removes it, so PN reacts a step behind and — **under a
binding g-limit** — its demand SATURATES and it MISSES (HANDOFF §10 item 10: "g-limit saturation
modeled — this is why augmented PN matters"). The `(N/2)·a_T⊥` term FEEDS FORWARD the maneuver so
the missile turns WITH the target instead of chasing it: low demand, no saturation, tight
intercept. The `N/2` coefficient is the standard APN result (constant-target-accel, the optimal-
control / linearized-kinematics derivation).

**Reads the TRUTH `a_T`** ("even a *perfect* seeker still lags" — RNG-free; estimating `a_T` from
a noisy seeker is a later fidelity step, §11 Tier A). On a **constant-velocity** target `a_T = 0`
→ `a_T⊥ = 0` → the feedforward vanishes and `a_apn` reduces to `pn_accel_from_omega` exactly (the
introduce-safe / `:apn`-on-CV ≈ `:pn` property; the `+ zero(Vec3)` gives `+0.0` not bit-`===`, so
tests use `≈` — the `−0.0 + 0.0 → +0.0` trap).

**Byte-identity anchor:** the base term is `pn_accel_from_omega(û,ω,Vc;N)` TEXTUALLY (not a
re-inlined `(N*Vc)*_cross(...)`), so the `:pn` arithmetic is untouched and any `:pn`/`:pursuit`
path replays bit-identical (the feedforward lives only in this new function + the gate-2 `:apn`
branch). **SIGN is the trifecta (HANDOFF §1):** a flipped `(N/2)·a_T⊥` (a `−` for the `+`, or a
sign-flipped projection) makes `:apn` WORSE than `:pn` — the SILENT failure. Pinned two ways in
`test_guidance.jl`: a direct `a_T⊥` recompute (a DIFFERENT expression) AND closed-loop
`miss(:apn) < miss(:pn)` (gate 2 / the probe). Uses `_dot` only (frames.jl house style, no
LinearAlgebra); zero-safe (`a_T = 0` → base; `û` from a coincident geometry → the base's guards).
"""
function pn_accel_augmented(û::Vec3, ω::Vec3, Vc::Real, a_T::Vec3; N::Real = 4.0)
    a_T⊥ = a_T - _dot(a_T, û) * û                    # target accel ⟂ LOS (projection removes the ∥ part)
    return pn_accel_from_omega(û, ω, Vc; N = N) + (N / 2) * a_T⊥
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
    _terminal_cutoff(a::Vec3, r::Real, r_stop::Real) -> Vec3

The §2 endgame guard (HANDOFF §10 item 10 — "avoid the LOS-rate→∞ blow-up as range→0"). PN's
`ω = r×v/‖r‖²` blows up as `r→0` with any residual miss (`_FRAME_EPS = 1e-12` is FAR too small
to catch it — the probe saw 2×10⁶ m/s² at r ≈ 0.1 m). Below a small **`r_stop`** range the outer
law FREEZES (zero command) and the missile COASTS THROUGH the endgame (the interceptor's fins
can't act faster than the tick anyway); CPA/impact detection ends the engagement. The probe pins
CPA-miss IDENTICAL across `r_stop ∈ {0,5,…,120}` (no corruption; Decision 4).

**`r_stop = 0` is an EXACT no-op** (`r = los_range ≥ 0`, so `r < 0` never fires → returns `a`
unchanged): the default, so a slice-9 `:pursuit` scenario that authors no `r_stop` takes the
byte-identical slice-9 path. Slice-10 `:pn` scenarios author `r_stop ≈ 30–50 m`.
"""
_terminal_cutoff(a::Vec3, r::Real, r_stop::Real) = r < r_stop ? zero(Vec3) : a

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
