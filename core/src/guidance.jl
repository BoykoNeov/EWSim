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

# The cooperation-fidelity (SALVO) rungs — the SINGLE source of truth for the `:cooperation`
# key (the GUIDANCE_MODES precedent, defined HERE so radar.jl's `LIVE_FIDELITY_MODES` can
# REFERENCE it at gate 2 — one-list-no-drift). Slice 14, the capstone: N interceptors share
# their time-to-go over an IDEAL datalink to arrive SIMULTANEOUSLY (HANDOFF §10 item 13).
# PHYSICS-CHANGING, NO RNG — class 4c (the `:integrator`/`:autopilot`/`:apn` shape, NOT
# slice-13's draw-topology 4b): a `:solo↔:salvo` toggle CHANGES the trajectory (the faster
# missile stretches its path) but the scenario is truth-fed PN with NO seeker — the cooperation
# lesson is isolated exactly as slice 12 isolated APN, so there is NO `w.rng` consumer.
# Therefore "draw-count invariance" is VACUOUS here (do NOT copy slice-13's draw language) and
# there is NO draw-topology to flip → `:cooperation` is introduce-SAFE, live-settable, and
# `set_fidelity` needs NO new guard (unlike slice-13 `:scan` / slice-3 `:cfar`).
#   • `:solo`  — no cooperation: each interceptor flies plain PN to its own natural t_go, so a
#     salvo launched from different ranges impacts SPREAD OUT in time (the reference).
#   • `:salvo` — impact-time-control cooperation: each missile drives its t_go toward the team
#     consensus `t_d = max_j t_go_j(0)` (the SLOWEST sets the pace — the only time all can reach,
#     since a missile can stretch but not shorten). The faster missiles S-curve to delay, the
#     slowest flies ~straight, and all N arrive TOGETHER (Δτ → 0) while every missile still hits.
# Defined at gate 1; `:salvo` NOT YET REFERENCED by a consumer (the `SalvoCoordinator` build_env!
# + decide! read it at gate 2) — so adding the rung leaves every slice-1..13 path byte-identical.
const COOPERATION_MODES = (:solo, :salvo)

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

# The convention-#6 numerical-safety floor on the closing speed inside `time_to_go` — a NAMED
# const like `_FRAME_EPS`, NOT a convention-#5 live slider clamp (gate-0 FINDINGS, advisor). The
# `t_go = R/V_c` estimate blows up as `V_c → 0`, which HAPPENS mid-course when a stretching salvo
# missile turns ⟂ to the LOS and its own closing speed collapses (even goes negative). Flooring
# `V_c` at 50 m/s keeps `t_go` (and hence the impact-time-error feedback) FINITE (no Inf/NaN to
# the wire — convention 6) without distorting normal operation: in-scenario closing is
# ~1000–1250 m/s, so the floor (≤ 300 in the gate-0 sweep, outcome-invariant) NEVER binds during
# clean closing.
const VC_FLOOR = 50.0

"""
    time_to_go(los_r::Real, closing_speed::Real) -> Float64

The zeroth-order **time-to-go** estimate `t_go ≈ R / V_c` (§1, slice 14) — how long until the
missile reaches the target at the current closing rate. `los_r` is the LOS range `R`
(`los_range`, frames.jl); `closing_speed` is the POSITIVE closing rate `V_c = −range_rate`
(frames.jl's sign is "negative = closing"). **Named approximation:** the zeroth-order estimate
(constant closing speed); the PN-curvature correction `t_go·(1 + λ̇²/(2(2N−1)))` is a fidelity
choice the gate-0 probe found UNNECESSARY (the zeroth-order estimate does not under-delay on the
pinned geometry — so it is deliberately NOT added; the speed-based `R/‖v‖` was REJECTED, it
over-estimates when the target closes fast).

**The `V_c → 0` guard (convention 6 — no Inf/NaN to the wire).** As a salvo missile STRETCHES
(turns ⟂ to the LOS to delay), its closing speed collapses toward and past zero, so a bare
`R/V_c` would blow up (→ Inf) or flip sign mid-course. `time_to_go` FLOORS the divisor at
[`VC_FLOOR`](@ref) (`R / max(V_c, VC_FLOOR)`): a receding / at-CPA missile gets a
large-but-FINITE `t_go = R/VC_FLOOR`, never `Inf`/`NaN`. `VC_FLOOR ≪` normal closing (~1000 m/s)
→ the floor NEVER binds during clean closing, so it distorts nothing (the gate-0 floor sweep is
outcome-invariant).
"""
time_to_go(los_r::Real, closing_speed::Real) = los_r / max(closing_speed, VC_FLOOR)

"""
    salvo_consensus(t_go_list) -> Float64

The shared-state reduction (§1, slice 14): the team's **desired impact time-to-go**
`t_d = maximum(t_go_list)` — the SLOWEST missile's time-to-go. This is the ONLY common arrival
time all interceptors can ACHIEVE: a missile can STRETCH its path to delay, but cannot SHORTEN
below its own minimum-time trajectory, so the consensus must be the maximum (never the mean or
min — those are unreachable by the laggard). Pure reduction over the team's published `t_go`
(the coordinator's `build_env!` calls this ONCE at launch over `kind === :missile`, gate 2 —
the fixed-at-launch consensus the gate-0 probe pinned as robust; a per-tick recompute
self-pollutes, since the very stretch it induces collapses each missile's `V_c` and inflates its
`t_go`, running the consensus away — probe8/9).

**The solo degenerate — the additivity bridge.** One element → itself, `===` bit-exact
(`maximum((x,)) === x`): a lone missile's consensus is its own `t_go` → the impact-time error is
identically zero → the `:salvo` command reduces to plain PN (see the early return in
[`impact_time_control_accel`](@ref)). The cooperation only bites with N ≥ 2 at different ranges.
"""
salvo_consensus(t_go_list) = maximum(t_go_list)

"""
    impact_time_control_accel(m_pos, m_vel, t_pos, t_vel, t_d; N = 4.0, K_it = 0.45) -> Vec3

The OUTER **impact-time-control** guidance command (§1, slice 14 — the salvo law) — the
[`pn_accel`](@ref) base PLUS a feedback term that shapes the flight time so the missile arrives
at the team's shared desired time-to-go `t_d`. The classic ITCG family (Jeon–Lee–Tahk 2006: PN
plus a bias on the impact-time error):

    base = pn_accel(m_pos, m_vel, t_pos, t_vel; N)               (the slice-10 PN command, REUSED)
    V_c  = −range_rate(t_pos − m_pos, t_vel − m_vel)             (closing speed, POSITIVE closing)
    t_go = time_to_go(los_range(m_pos, t_pos), V_c)              (this missile's own time-to-go)
    err  = t_d − t_go                                            (>0 ⇒ EARLY ⇒ must STRETCH / delay)
    v⊥   = m_vel − (m_vel·û) û                                    (the missile velocity ⟂ to the LOS)
    a    = base + (K_it · err · ‖m_vel‖) · (v⊥/‖v⊥‖)             (m/s²)

`t_d` is the shared **desired REMAINING time-to-go** (gate 2: the coordinator publishes
`w.env[:salvo_t_d] = T_d − w.t`, the fixed launch consensus minus elapsed time), and `err =
t_d − t_go` is this missile's impact-time error: **positive ⇒ the missile has LESS time-to-go
than the team wants ⇒ it is EARLY ⇒ it must LENGTHEN its path to delay.**

**THE SIGN IS THE TRIFECTA TRAP (HANDOFF §1).** The feedback pushes along `+v⊥` (the velocity's
⟂-LOS component) when EARLY: GROWING the heading error curves the missile OFF the direct line →
a LONGER arc → a LATER arrival (the intended delay). A `−` would make an early missile take a
SHORTCUT — arriving even earlier, the silent failure. Pinned two ways in `test_guidance.jl`: a
direct feedback recompute (a DIFFERENT expression) AND the kinematic `dot(feedback, v⊥) > 0` for
an early missile; and closed-loop `Δτ(:salvo) < Δτ(:solo)` at gate 2.

**TWO GUARDS (advisor):**
  (i) **`err == 0.0` early-returns `base` bit-exact** (NOT `base + zero(Vec3)`, whose −0.0+0.0→+0.0
    would flip a sign bit): a missile exactly on-time takes the plain-PN command `===`. This is the
    convention-11 bit-exact no-op and the LAW-LEVEL solo degenerate anchor (gate-0 FINDINGS moved
    it here from the scenario level — a 1-missile salvo is loader-forbidden anyway; additivity for
    slices 1–13 is guaranteed by GATING, never by this equivalence).
  (ii) **the feedback is BOUNDED, two ways.** The `t_go` blow-up as `V_c → 0` (the stretching
    missile's own closing collapse) is floored inside [`time_to_go`](@ref) (`VC_FLOOR`), so `err`
    stays finite; and a near-head-on tick (`‖v⊥‖ < 1e-6`, no ⟂ handle) early-returns `base`. The
    head-on floor is DELIBERATELY larger than `_FRAME_EPS`: because the feedback DIRECTION is
    normalized (`v⊥/‖v⊥‖`), its MAGNITUDE `K_it·err·‖v‖` is INDEPENDENT of `‖v⊥‖`, so a
    tiny-but-nonzero `‖v⊥‖` would inject a FULL-magnitude feedback along a numerically
    ill-conditioned direction — the `1e-6` floor suppresses feedback exactly when the ⟂-direction
    is unreliable. The residual PN `ω → ∞` endgame blow-up is bounded at the CONSUMER
    (`_terminal_cutoff` + `clamp_accel` in `decide!`, gate 2), as for `pn_accel`.

`K_it` (units 1/s²) is the impact-time-error gain — the gate-0 nominal 0.45 (window [0.42, 0.50]):
too cold → weak collapse; the sweet spot → tight simultaneous arrival; too hot (≥ 0.55) → the near
missile OVER-stretches and MISSES (the "salvo can fail" upper edge — the slice-12 pin-the-window
discipline). Reuses `pn_accel`/`los_unit`/`los_range`/`range_rate` (frames.jl house style, no
LinearAlgebra); zero-safe via the two guards.
"""
function impact_time_control_accel(m_pos::Vec3, m_vel::Vec3, t_pos::Vec3, t_vel::Vec3, t_d::Real;
                                   N::Real = 4.0, K_it::Real = 0.45)
    base = pn_accel(m_pos, m_vel, t_pos, t_vel; N = N)           # the slice-10 PN command (REUSED)
    Vc   = -range_rate(t_pos - m_pos, t_vel - m_vel)            # closing speed (POSITIVE when closing)
    tgo  = time_to_go(los_range(m_pos, t_pos), Vc)             # this missile's own time-to-go
    err  = t_d - tgo                                           # impact-time error (>0 ⇒ EARLY ⇒ stretch)
    err == 0.0 && return base                                  # BIT-EXACT no-op (conv. 11) — NOT base + 0
    û    = los_unit(m_pos, t_pos)                              # r̂ (zero-range guard inside → zero vector)
    v⊥   = m_vel - _dot(m_vel, û) * û                          # missile velocity ⟂ to the LOS
    n    = _norm3(v⊥)
    n < 1e-6 && return base                                    # near head-on: no ⟂ handle this tick (see docstring)
    return base + (K_it * err * _norm3(m_vel)) * (v⊥ / n)
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
