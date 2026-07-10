# Slice 15 — actuator/fin dynamics: a rate-limited fin servo (the FIRST §11 Tier-A extension)

**OPENS THE TIER-A HORIZON.** HANDOFF §10 items 1–13 (the committed roadmap) are DONE. Slice 15 is the FIRST
HANDOFF **§11 Tier-A** extension — *"Higher fidelity behind existing knobs. **6-DOF airframe + actuator/fin
dynamics and angle-of-attack limits** (`fidelity.airframe = point_mass | 6dof`) … Each is a swap, not a
rewrite."* It takes the **actuator/fin-dynamics half** of that entry and DEFERS the **6-DOF airframe half**
(the trigger for 6-DOF is recorded below and in HANDOFF/STATUS). Source of truth: HANDOFF §11 Tier-A + §10 item 9
(the autopilot/plant cascade this extends) + §3 (the tick contract) + §1 (named approximations, the sign/units
trifecta).

## THE SCOPE (user-ratified 2026-07-10) — actuator rate saturation, NOT 6-DOF airframe

Three readings of "fin dynamics" were on the table; the user ratified **Option 1 — a rate-limited fin actuator
model** (now), with **Option 2 — full 6-DOF airframe** deferred (later). The plan is written around Option 1.

- **Option 1 (THIS slice):** a NEW `:autopilot` rung `:fin` (the 3rd, alongside `:ideal`/`:pid`). The PID
  controller is UNCHANGED; the **plant** becomes an explicit fin servo with a **rate limit** (δ̇_max) and a
  **deflection limit** (δ_max), mapped to lateral accel by a control-effectiveness gain `a = k_δ·δ`. The point-mass
  translational airframe is UNCHANGED (attitude stays kinematic velocity-aligned). **The NEW lesson (gate-0
  EMPIRICAL PIVOT — see below): the fin rate limit CAPS THE G-ONSET RATE** (`|da_ach/dt| ≤ k_δ·δ̇_max`), a genuinely
  new plant signature cleanly distinct from slice-9's steady-state gain undershoot, slice-10's magnitude g-limit,
  and slice-12's APN saturation — **YET the miss does NOT open** (point-mass PN is robust to actuator rate
  limiting; "a lack of effect IS the lesson," user-ratified 2026-07-10). The originally-planned "rate saturation
  opens the miss" did NOT materialize (12 probes) — the honest landing is the g-onset cap + the robustness that
  motivates 6-DOF.
- **Option 2 (DEFERRED, NAMED — the other half of the Tier-A entry):** full 6-DOF rotational dynamics (moment of
  inertia, aero moments Cmα/Cmδ, angle-of-attack α, fin→moment→α→body-lift fed back into the force;
  `fidelity.airframe = point_mass | 6dof`). **THE TRIGGER to build it (recorded so it is not lost):** 6-DOF earns
  its cost the moment a lesson requires the **body to point somewhere other than along the velocity vector** —
  most concretely (a) **angle-of-attack-limited maneuverability** (the *aerodynamic* g-limit α_max→C_Lmax→a_max,
  of which slice-15's δ_max is one physical origin) or (b) the **seeker/body radome parasitic loop** (a
  body-mounted seeker sees LOS through attitude). Practically: after this slice (which introduces the fin
  deflection state δ that 6-DOF's moment equation consumes) and once ≥2–3 attitude-dependent lessons queue so the
  rotational integrator's cost (and its frames/signs bug surface) amortizes. Until a scenario NEEDS α ≠ 0, stay
  point-mass + this slice's actuator model.

## THE CRUX — the LIMITS are the entire content of `:fin`, or it is a dead knob (advisor, load-bearing)

Work the algebra: a **linear** first-order fin servo `τ_s·δ̇ = δ_cmd − δ` with a linear control-effectiveness map
`a = k_δ·δ` collapses to `τ_s·ȧ = a_cmd − a` — **mathematically the `:pid` plant relabeled** (k_δ cancels). That is
precisely the **convention-4c false-fidelity trap**: a purely-linear fin model is NOT new physics, it is `:pid`
with a renamed time constant. **The ONLY new physics is the nonlinearities: the fin RATE limit (δ̇_max) and the
deflection limit (δ_max).** Therefore:

- **The RATE limit IS the lesson.** The scenario MUST make δ̇_max bind, or `:fin` is a dead knob (the slice-12
  "the g-limit must actually bind" discipline, here for the rate limit).
- **The degeneracy is a FEATURE, stated honestly and TESTED:** `:fin` with δ̇_max, δ_max → ∞ reproduces the `:pid`
  plant to float tolerance (gate-1 anchor #1). This both proves the algebra and documents that the limits carry
  the fidelity.
- **A purely-LINEAR refinement would have to be SECOND-order** (ω_a, ζ_a — the bandwidth/damping lesson) to be
  non-degenerate; that was Option 3, NOT chosen. Option 1's saturation is the more vivid teaching increment,
  which is exactly why it needs the limits.

## THE PLANT (guidance.jl — pure, RNG-free, no LinearAlgebra — the §9 house style)

The PID controller is REUSED UNCHANGED (`:fin` is same-controller + nonlinear-plant). The new plant, per tick
(all Vec3, in-plane x-z; magnitude clamps preserve direction — the `clamp_accel` house style):

    u      = Kp·e + Ki·e_int + Kd·ė            # the SAME PID command (accel domain), e = a_cmd − a_ach
    δ_cmd  = _clamp_mag(u / k_δ, δ_max)         # desired fin deflection, DEFLECTION-command limited (rad)
    δ̇_des  = (δ_cmd − δ) / τ_s                  # first-order fin servo (δ = the carried plant state)
    δ̇      = _clamp_mag(δ̇_des, δ̇_max)           # ← the RATE LIMIT (δ̇_max, rad/s) — THE LESSON
    δ′     = _clamp_mag(δ + δ̇·dt, δ_max)        # integrate + DEFLECTION-position limit (δ_max, rad)
    a_ach  = k_δ · δ′                           # control-effectiveness map (m/s² per rad)

- **`k_δ`** (control effectiveness, m/s²·rad⁻¹), **`δ_max`** (deflection limit, rad), **`δ̇_max`** (rate limit,
  rad/s), **`τ_s`** (fin servo time constant, s). New comp keys `:k_delta`/`:delta_max`/`:delta_rate_max`/
  `:tau_fin`; the PID gains `kp`/`ki`/`kd` are REUSED (same controller). `τ_fin` defaults to the `:pid` `τ` default
  (0.3) so the δ̇/δ→∞ equivalence to `:pid` is exact-by-default.
- **δ_max is the PHYSICAL ORIGIN of the abstract `a_max`.** Set `k_δ·δ_max ≤ a_max` in the scenario so the
  `clamp_accel(·, a_max)` crash-guard NEVER binds → the effective g-cap is `k_δ·δ_max` and the isolated lesson is
  the RATE limit (advisor #2 — the deflection/g-limit must NOT bind while the rate limit does).
- **State discipline (advisor #4):** the fin deflection δ lives in its OWN comp key `:fin_state`
  (`FinState = @NamedTuple{δ::Vec3}`), NOT as new fields on `AutopilotState` — growing that NamedTuple would
  perturb every `:pid`/`:ideal` missile's determinism fingerprint. The PID memory (`a_ach`/`e_int`/`e_prev`)
  stays in `AutopilotState`, STRUCTURALLY UNCHANGED. First-order servo → δ suffices (a 2nd-order servo would also
  carry δ̇ — Option 3, deferred).
- **Zero/degenerate-safe (convention 5/6):** `a_cmd = 0 → δ→0 → a_ach = 0` (no NaN); a live `τ_s→0` slider is
  floored (`max(τ_s, _FRAME_EPS)` — the `autopilot_step` τ precedent); `_clamp_mag` is `clamp_accel`'s
  non-finite-safe magnitude clamp reused/renamed (an Inf/NaN component → zero, never NaN to JSON).

**The pure kernel** — a NEW function so `:ideal`/`:pid` in `autopilot_step` stay TEXTUALLY frozen (byte-identity;
the PID arithmetic is DUPLICATED into it deliberately — reusing `:pid`'s branch would entangle the frozen bytes):

    fin_autopilot_step(a_cmd, ap::AutopilotState, fin::FinState, dt;
                       kp, ki, kd, tau_s, k_delta, delta_max, delta_rate_max)
        -> (a_ach::Vec3, ap′::AutopilotState, fin′::FinState, diag::NamedTuple)

`diag = (delta, delta_rate, rate_sat::Bool, defl_sat::Bool)` feeds the telemetry (the saturation tells). Returns
BOTH states (the caller threads `ap′`→`:ap_state`, `fin′`→`:fin_state`). `autopilot_step` (`:ideal`/`:pid`) is
UNCHANGED — the `:fin` branch never routes through it.

## THE DETERMINISM SHAPE — class 4c, "draw-count invariance VACUOUS" (the slice-14 shape, NOT slice-13's 4b)

The missile-arc RNG story has flip-flopped every slice; slice 15 is the SECOND consecutive 4c (after slice 14) —
**name it, copy neither RNG-consuming neighbour (convention 4c, the copy-paste false-claim trap):**

- Slice **11** — Seeker is the first `w.rng` consumer → conventions 3/11 APPLY.
- Slice **13** — the seeker is back (decoy seduces a seeker) → `2·N_p·N_bins` draws, class **4b** (draw-topology
  flip, introduce-REJECTED).
- Slices **12 / 14** — no seeker (truth-fed APN / salvo PN) → the inflection INVERTS to VACUOUS, class **4c**.
- Slice **15** — actuator dynamics on a TRUTH-FED PN missile (NO seeker in the scenario — the fin lesson is
  isolated exactly as slice 12 isolated APN and slice 14 isolated cooperation). The plant is DETERMINISTIC
  (a rate/deflection-limited servo) → **NO `w.rng` consumer** → the inflection **STAYS VACUOUS** (class 4c).
  **Do NOT carry slice-11/13's "1 draw/tick / 2·N_p·N_bins / conventions 3/11 apply / 4b" language — that is the
  false claim here.**

**The fidelity CLASS is 4c — physics-changing, no RNG** (the `:integrator`/`:autopilot`/`:apn`/`:cooperation`
shape). An `:ideal↔:pid↔:fin` toggle **CHANGES the trajectory** (moves the missile — not a dead knob) with **no
RNG stream at all**, so:

- **"Draw-count invariance" is VACUOUS** (there is no RNG to keep in lockstep) — write it that way, NOT slice-13's
  "the sharp property to prove."
- **No draw-topology to flip → NO introduce-reject guard** (unlike slice-13 `:scan` / slice-3 `:cfar`). `:fin`
  joins `AUTOPILOT_MODES`, which `set_fidelity` already treats as **live-settable** (`:ideal↔:pid` is already a
  live toggle); adding `:fin` makes `:ideal↔:pid↔:fin` all live — the `:integrator`/`:autopilot` precedent, NO
  server change beyond the one-list tuple.
- Additivity is via **the rung not existing** on prior slices: `get(w.fidelity, :autopilot, :ideal)` never returns
  `:fin` for a slice-1..14 scenario, and `autopilot_step`'s `:ideal`/`:pid` arithmetic is TEXTUALLY UNCHANGED →
  slices 1–14 **byte-identical** (the class-4c additivity — like introducing `:apn` left slices 1–11 identical).

The additivity claims (the byte-identity master check — slices 1–14):

1. **Introduce-safe / additivity — via the rung, NOT a live draw.** Absent an `:autopilot: fin` config nothing
   reads `:k_delta`/`:fin_state`: a slice-1..14 scenario is **byte-identical** (no RNG added anywhere; guidance.jl
   gains only a pure function; the `:ideal`/`:pid` branches are frozen). A slice-9/10/12 single-PID scenario
   replays **bit-identical** after the guidance.jl / missile.jl / radar.jl edits.
2. **Same-config replay is bit-identical** — deterministic and **RNG-free** on the missile path (the slice-14
   shape): the verifier pins `t` AND a per-missile `pos` sequence, both RNG-independent (NO seeker draw here;
   [[ewsim-missile-verifier-sampling]]).
3. **An `:ideal↔:pid↔:fin` toggle CHANGES the trajectory** (the not-a-dead-knob property) — the fin lag/rate
   saturation reshapes the path — with **no RNG** (class 4c; the slice-9 `:ideal↔:pid` shape, now with a third
   rung).

## The lesson (shown as numbers — the LANDING WAS EMPIRICAL; gate-0 PICKED the g-onset cap over the miss)

**THE HEADLINE (gate-0-confirmed, 12 probes) — TWO parts, both honest:**

1. **PRIMARY (measurable / monotone / provable): the fin rate limit CAPS THE G-ONSET RATE.** `a_ach = k_δ·δ` and δ
   slews ≤ δ̇_max ⇒ **`|da_ach/dt| ≤ k_δ·δ̇_max` BY CONSTRUCTION** — the achieved lateral-g cannot BUILD faster than
   `k_δ·δ̇_max` (a jerk / g-onset-rate cap). `:ideal` is UNCAPPED (a_ach follows a_cmd's steps instantly — huge
   onset); `:pid` caps the onset too but via the τ-lag exponential rise (a DIFFERENT mechanism); `:fin` HARD-CAPS
   it at the slew slope. The slider `δ̇_max` IS the lever: raising it raises the cap (steepens the a_ach ramp) until
   the cap exceeds the command's own onset. This is cleanly DISTINCT from slice-9 (steady-state GAIN undershoot
   `1/(1+Kp)`) and slice-10 (MAGNITUDE cap `a_max`): slice-15 caps the RATE-OF-CHANGE of the achievable g.
   Measured (probe10, k_δ=5000, τ_s=0.02, mid-course jink): `:fin` peak g-onset ≈ k_δ·δ̇_max (ratio 0.98 at
   δ̇=0.5 — the cap BINDS), vs `:ideal` peak g-onset ≈ 25073 (≫ cap). `rate_sat` lights only during the maneuver
   (~1% of ticks — honest, not the τ_s≈dt constant-lit artifact).

2. **SECONDARY (the "lack of effect" that IS the lesson — user-ratified): the miss does NOT open.** Across the whole
   δ̇_max slider the miss stays sub-meter (~0.29 m; PN robust) — the point-mass interceptor homes fine despite the
   capped g-onset. **This is the deliberate teaching point, not a disappointment:** finite actuator bandwidth is
   ACCEPTABLE for a point-mass homing loop (the required deflections are a small fraction of a radian and PN's
   terminal gain absorbs the residual lag), which is precisely WHY the DRAMATIC actuator failure modes — guidance-
   loop limit cycle, angle-of-attack-limited maneuverability, the radome/body-rate parasitic loop — genuinely need
   the deferred 6-DOF airframe (empirically confirmed: PN+α-β+first-order actuator is unconditionally stable, no
   limit cycle even at N=55 — probes 11–12). The slice HONESTLY reports the small miss as corroboration/context.

**THE ISOLATION (advisor #2, promoted to an ASSERTION — the g-onset number must be CLEAN).** The cap number is
`k_δ·δ̇_max` EXACTLY only if δ never reaches δ_max and a_max never binds — else the "cap" is partly a slice-10
magnitude clamp in a fin costume. `k_δ·δ_max = 2500 ≤ a_max = 2600` and the jink is tuned so **`defl_sat == 0` and
`amax_bind == false` throughout the guided window (r > r_stop)** — pin BOTH as explicit assertions (if either
lights, lower A_jink / raise δ_max so δ_cmd < δ_max while δ̇ still saturates during the transient).

**DROPPED (advisor #3):** the "low-g-cap secondary miss" (FINDINGS open-question #3 — forcing a small miss by
accepting mild a_max contamination). It contradicts "lack of effect IS the lesson" AND violates the isolation
above. ONE clean lesson: the cap is observable, the miss is unaffected, the contrast motivates 6-DOF.

**Why the ManeuveringTarget jink (advisor-confirmed).** A `ManeuveringTarget` (slice-12, reused) mid-course upward
jink gives a clean mid-flight a_cmd STEP to watch a_ach RAMP behind at the capped slope (that ramp IS the Godot
visual) — whereas a launch-heading-error transient is contaminated by the `e_prev=0` derivative kick + initial
settling, and "PN is robust even against a maneuver" is the stronger claim. Probe-pinned; A_jink=140 at
los_range < 1500 m.

**The lesson can ALSO fail (name the failure regime — the slice-12/14 discipline).** If δ̇_max is set so loose it
never binds, `:fin` ≈ `:pid` and the cap is vacuous (the discriminator collapses); if δ_max or a_max bind, the
"g-onset cap" is a MAGNITUDE (slice-10) clamp wearing a fin costume (the isolation assertion above catches this).
The probe pins a δ̇_max where the RATE limit binds while δ_max/a_max do NOT, and reports the robust δ̇_max window (a
learner's slider nudge can't silently erase or mis-attribute the cap — the slice-12 window discipline).

## The truth-path / plant invariants (advisor-style guards)

- **`:fin` is a PLANT change only — the outer law and the truth path are UNTOUCHED.** `:fin` replaces the inner
  autopilot plant; `guidance`/the seeker/`_nearest_target` are unchanged. Miss/CPA is still per-missile vs the true
  `:target` (the slice-10..14 truth-path invariant).
- **`AutopilotState` is STRUCTURALLY FROZEN.** δ lives in `:fin_state`. Growing the NamedTuple is the byte-identity
  hazard — do NOT (advisor #4). Confirm the `:ideal`/`:pid` determinism fingerprints are bit-for-bit unchanged
  (golden + determinism green).
- **`k_δ·δ_max ≤ a_max` (the g-cap isolation).** The `clamp_accel(·, a_max)` crash-guard stays (a huge gain slider
  can't blow up a tick) but is tuned NOT to bind, so δ_max is the effective g-limit and the RATE limit is the
  isolated lesson.
- **The plant is DETERMINISTIC — NO `w.rng`.** `:fin` adds no draw (class 4c). The slice-15 scenario carries no
  seeker (truth-fed PN), so the whole run is RNG-free — the slice-14 replay discipline (pin `t` + pos, not an RNG
  value).

## Scope — one lesson per scenario

**ONE guided interceptor** `[BallisticMissile, Autopilot]` (the slice-9/10 force-integrated stack) against a
**single crossing target** `[ConstantVelocity]` (regime a/b) — or a `[ManeuveringTarget]` only if the probe
escalates to regime (c). Held: **`guidance = :pn`** (the law under test; `:apn` only for regime c),
**`autopilot = :fin`** (the plant under test), **NO seeker** (truth-fed — the fin lesson isolated exactly as slice
12/14 isolated their lessons). The switchable **lesson is the `δ̇_max` slider** (the fin rate limit); the fidelity
**button** cycles `:ideal↔:pid↔:fin` as a secondary view (`:ideal` = perfect, `:pid` = lumped lag, `:fin` = the
rate-limited servo — the three-rung plant-fidelity ladder, the `:pursuit→:pn→:apn` precedent). **Deferred, NAMED
(convention 9):**

- **6-DOF airframe / angle-of-attack / rotational dynamics** (Option 2 — the other half of the Tier-A entry; the
  trigger recorded above).
- **Second-order actuator** (ω_a, ζ_a bandwidth/damping — Option 3, the LINEAR refinement; a different lesson).
- **Per-channel (pitch/yaw) fin allocation, fin aero nonlinearity, hinge-moment/stall** — the fin is a single
  magnitude-limited Vec3 deflection (the planar `clamp_accel` abstraction), not a resolved fin set.
- **The actuator feeding a MOMENT (→ α → lift)** rather than accel directly — that IS Option 2 (6-DOF); slice 15
  maps δ→accel directly (named approximation: skips the airframe's α/short-period rotational response).

**One scenario** (one lesson; the slider is δ̇_max; the button toggles the plant ladder). 3 review gates + a
gate-0 probe (mirroring slices 5–14).

## The physics / math (named approximations — HANDOFF §1)

### 1. The fin-servo kernel (guidance.jl — pure, RNG-free, no LinearAlgebra)

NEW in `core/src/guidance.jl` (the §9 pure lib that holds `pursuit_accel`/`pn_accel`/`autopilot_step`), tested
closed-form. The exact δ̇_max/δ_max/k_δ/τ_s constants are PROBE-PINNED (gate 0); the plan fixes the structure:

    _clamp_mag(v::Vec3, vmax) -> Vec3          # magnitude clamp, direction-preserving, non-finite-safe
        # = clamp_accel generalized (or clamp_accel reused directly — it already IS this). Reuse, don't fork.

    fin_actuator_init() -> FinState            # FinState = @NamedTuple{δ::Vec3}; δ = 0 (launch/reset)

    fin_autopilot_step(a_cmd, ap::AutopilotState, fin::FinState, dt;
                       kp=2.0, ki=0.0, kd=0.0, tau_s=0.3, k_delta, delta_max, delta_rate_max)
        -> (a_ach, ap′, fin′, diag)
        # PID command u (DUPLICATED from :pid, so :pid's bytes stay frozen) → δ_cmd = clamp(u/k_δ, δ_max)
        # → δ̇ = clamp((δ_cmd−δ)/τ_s, δ̇_max)  [THE RATE LIMIT]  → δ′ = clamp(δ + δ̇·dt, δ_max) → a_ach = k_δ·δ′.
        # diag = (delta=‖δ′‖, delta_rate=‖δ̇‖, rate_sat = ‖δ̇_des‖ > δ̇_max, defl_sat = ‖δ′‖ ≥ δ_max·(1−ε)).
        # τ_s floored (max(τ_s,_FRAME_EPS)); a_cmd=0 → δ→0 → a_ach=0 (zero-safe). ap′ carries the PID
        # memory (a_ach=k_δ·δ′ for continuity, e_int, e_prev); fin′ carries δ′.

- **`AUTOPILOT_MODES = (:ideal, :pid, :fin)`** — ADD `:fin` (the one-list source of truth, guidance.jl, before
  radar.jl so `LIVE_FIDELITY_MODES` references it — the drift-catch). `autopilot_step`/`pursuit_accel`/`pn_accel`/
  everything else **UNCHANGED** (byte-identity anchor). Export `fin_autopilot_step`/`fin_actuator_init`/`FinState`
  (+ `AUTOPILOT_MODES` already exported).
- **The equivalence anchor (the crux, tested):** `fin_autopilot_step` with `δ̇_max, δ_max = Inf` (or huge) tracks
  the `:pid` plant `autopilot_step(:pid, …; tau=tau_s)` output to `atol` over N steps — proving the linear servo
  IS the `:pid` lag and that the limits carry the fidelity.

### 2. The `Autopilot.decide!` extension (missile.jl — the `:fin` plant branch)

`Autopilot.decide!` (missile.jl:270) today runs `autopilot_step(mode, a_cmd, state, dt; …)` for `mode ∈
{:ideal,:pid}` (missile.jl:373–385). Slice 15 dispatches `:fin` to the new kernel:

    state = get(c, :ap_state, autopilot_init())::AutopilotState
    if mode === :fin
        fin = get(c, :fin_state, fin_actuator_init())::FinState
        a_ach, state′, fin′, diag = fin_autopilot_step(a_cmd, state, fin, dt;
                                        kp=kp, ki=ki, kd=kd, tau_s=tau_fin,
                                        k_delta=k_delta, delta_max=delta_max, delta_rate_max=delta_rate_max)
        a_ach  = clamp_accel(a_ach, a_max)                 # crash-guard (tuned NOT to bind: k_δ·δ_max ≤ a_max)
        state′ = (a_ach = a_ach, e_int = state′.e_int, e_prev = state′.e_prev)
        c[:fin_state] = fin′
        a_ctrl = a_ach
    else
        a_ach, state′ = autopilot_step(mode, a_cmd, state, dt; kp=kp, ki=ki, kd=kd, tau=tau)  # UNCHANGED
        if mode === :pid ... end                            # UNCHANGED (textually frozen)
        a_ctrl = mode === :pid ? a_ach : clamp_accel(a_ach, a_max)                             # UNCHANGED
    end
    c[:ap_state] = state′
    c[:a_ctrl]   = a_ctrl

**BYTE-IDENTITY (slices 1–14):** the `:fin` branch is gated on `mode === :fin` — unreachable for a slice-1..14
scenario (`get(w.fidelity,:autopilot,:ideal)` never returns `:fin`), and the `else` arm is the slice-9/10/12
arithmetic **textually unchanged** → slices 1–14 byte-identical BY CONSTRUCTION (the slice-12 `+0.0`/spelling bit
trap — do NOT reformat the `:ideal`/`:pid` arithmetic). New comp reads (`:k_delta`/`:delta_max`/`:delta_rate_max`/
`:tau_fin`) with DEFAULTS at the consumer (a live slider / bare block can't `KeyError` — convention 5). New fin
telemetry keys (`fin_defl`, `fin_rate`, `fin_rate_sat`, `fin_defl_sat`) — all SCALARS (no Array → no `float()`
client crash); shipped WHENEVER `mode === :fin` (a `:ideal`/`:pid` scenario ships none → byte-identical wire).

### 3. Fidelity plumbing — `:fin` (class 4c, live-settable, no introduce-reject)

`AUTOPILOT_MODES` gains `:fin`; `LIVE_FIDELITY_MODES` (radar.jl:169) already REFERENCES `AUTOPILOT_MODES`, so the
new rung propagates to `set_fidelity` (server.jl) AND the scenario loader validation (`scenario.jl` — `_KNOWN_
FIDELITY_KEYS` / `_validate_fidelity`) with **NO edit** beyond the one tuple (one-list-no-drift; verify nothing
re-lists the autopilot rungs). **`set_fidelity` gains NO new guard** (unlike slice-13 `:scan` / slice-3 `:cfar`):
`:fin` is class 4c (physics-changing, no RNG → no draw-topology to flip → introduce-safe like `:integrator`/
`:autopilot`), so `:ideal↔:pid↔:fin` is **live-settable**. Loader VALIDATES the fin params AT LOAD (the ballistic
mass/`a_max`/`tau` precedent — immutable authored inputs): `k_delta > 0`, `delta_max > 0`, `delta_rate_max > 0`,
`tau_fin > 0` (only when a missile block authors them / `autopilot: fin`).

## Decisions to take at gate 0 (surface to the advisor before gates 1–3)

1. **The REGIME + HEADLINE — terminal (a) vs mid-course (b) vs weaving (c) rate saturation.** Report MISS(δ̇_max),
   the rate-saturation fraction, and whether `a_max`/`δ_max` bind. Pick the regime where the RATE limit binds while
   the MAGNITUDE limits do NOT (the isolation — advisor #2). Pin the RATIO (tight vs generous δ̇_max miss).
2. **The `r_stop` collision (regime a) — advisor #3.** Verify the fin rate saturates BEFORE `r_stop` freezes the
   outer law (its docstring: "the fins can't act faster than the tick anyway"). Tune `r_stop` down / to 0 for this
   scenario, or confirm the saturation window opens outside the cutoff radius. If terminal (a) cannot be isolated
   from `r_stop`, fall to mid-course (b) — which avoids the collision entirely.
3. **The fin constants — δ̇_max, δ_max, k_δ, τ_s + the geometry.** δ̇_max tight enough to bind (open the miss), loose
   enough that the missile still meaningfully guides; `k_δ·δ_max ≤ a_max` (the g-cap isolation); τ_s realistic.
   The geometry (crossing angle / launch heading error) that drives the LOS-rate / turn demand into the rate limit.
   Report the robust δ̇_max window.
4. **The equivalence anchor** — `fin_autopilot_step` with δ̇/δ→∞ reproduces the `:pid` plant to `atol` (the crux
   proof — the limits carry the fidelity).
5. **The rate-limit kinematic anchor** — a step command with a tight δ̇_max ramps δ at EXACTLY δ̇_max
   (‖δ(t)‖ = δ̇_max·t until it reaches δ_cmd) — an EXTERNAL kinematic check (a rate-limited integrator ramps at the
   limit), not a self-calibrated round-trip. And the deflection anchor: a large sustained command pins δ at δ_max,
   a_ach = k_δ·δ_max exactly.
6. **Byte-identity** — a slice-9/10/12 single-PID/PN scenario replays bit-identical after the guidance.jl/missile.jl/
   radar.jl edits (RNG-free — pin `t` AND a pos sequence, the slice-14 shape); `AutopilotState` structurally frozen
   (`:ideal`/`:pid` fingerprints unchanged).
7. **NO RNG** — the run is bit-identical replay with `t`/pos RNG-independent (the class-4c "vacuous" property, the
   slice-14 shape — state it, do NOT claim slice-11/13 draws).
8. **One scenario, geometry/δ̇_max/δ_max/k_δ/a_max values** — pinned by the probe against the live wire (convention
   10). **RE-CONSULT THE ADVISOR after the numbers land** (the landing/regime is the one thing un-settleable from
   the plan — advisor #1: which regime isolates cleanly; does `a_max`/`δ_max`/`r_stop` stay out of the way).

## Review gates (cadence: staged, mirroring slices 5–14)

0. **Gate-0 probe (throwaway, `M:\claud_projects\temp\slice15_probe\`).** Reuse the REAL core physics (`using
   EWSim`: `total_accel`/`integrator_step`/`pn_accel`/`pursuit_accel`/`autopilot_step`/`clamp_accel`/
   `_terminal_cutoff`/`los_*`/`range_rate`), hand-roll only the `fin_autopilot_step` candidate + the
   integrate!→decide! loop (`guidance=:pn`, `autopilot=:fin` vs `:pid`/`:ideal`, no seeker). **Confirm + pin:**
   (i) the equivalence anchor (δ̇/δ→∞ ⇒ `:fin` ≈ `:pid` — the crux, #4); (ii) the rate/deflection kinematic anchors
   (#5); (iii) the geometry drives the demand into δ̇_max and MISS(δ̇_max) opens as δ̇_max shrinks (#1/#3) with
   `a_max`/`δ_max` NOT binding (the isolation) and — regime (a) — the saturation before `r_stop`; (iv) the
   regime pick (a/b/c) from the data; (v) byte-identity of a slice-9/10/12 scenario (#6); (vi) NO RNG (#7). Write
   `FINDINGS.md`, pin the geometry/δ̇_max/δ_max/k_δ/τ_s/a_max + the MISS(tight)/MISS(loose) **RATIO** + conservative
   one-sided verifier bounds + the rate-sat fraction. **RE-CONSULT THE ADVISOR after the numbers.** Forward-flag
   any gate-1/2/3 seams.

1. **Primitive green (pure, closed-form, SI, RNG-free, no LinearAlgebra).** guidance.jl: `fin_autopilot_step`
   (PID command → rate/deflection-limited fin servo → k_δ·δ; the diag flags), `fin_actuator_init`, `FinState`,
   `_clamp_mag` (reuse `clamp_accel`). **`AUTOPILOT_MODES += :fin`** (one-list-no-drift). `autopilot_step`/
   `pursuit_accel`/`pn_accel`/all existing members **UNCHANGED** (byte-identity anchor). Export the new symbols.
   `test_guidance.jl` (+ fin arms, explicit `atol`): **the `:pid` EQUIVALENCE** (δ̇/δ→∞ ⇒ fin ≈ pid plant — the
   crux); **the RATE-limit ramp** (‖δ‖ = δ̇_max·t under a step, until δ_cmd — the external kinematic anchor);
   **the DEFLECTION limit** (large command ⇒ δ = δ_max, a_ach = k_δ·δ_max exact); **a_ach = k_δ·δ** (the
   effectiveness map); **zero-safe** (a_cmd=0 ⇒ a_ach=0, τ_s→0 floored — no NaN); **the diag flags** (rate_sat /
   defl_sat light exactly when the respective clamp binds). Slices 1–14 byte-identical through the include (golden
   + determinism green; NO RNG added — guidance.jl stays pure; `AutopilotState` structurally unchanged).

2. **Wired — the `:fin` `decide!` branch + the `:fin` rung + loader validation.** `missile.jl`: the `:fin`
   dispatch in `Autopilot.decide!` (the new branch; the `:ideal`/`:pid` arm textually unchanged) + `:fin_state`
   threading + the fin telemetry keys (scalars). `scenario.jl`: the fin comp keys (`k_delta`/`delta_max`/
   `delta_rate_max`/`tau_fin`) parsed into the missile `comp` + LOAD-validated (`> 0` each, when authored).
   `radar.jl`: `LIVE_FIDELITY_MODES` picks up `:fin` via `AUTOPILOT_MODES` (NO re-list). `set_fidelity`: **NO new
   guard** — `:ideal↔:pid↔:fin` live-settable (class 4c; the `:integrator`/`:autopilot` precedent).
   - `test_missile.jl` (+ fin arms): a `:fin` missile's `a_ach` LAGS `a_cmd` under a tight δ̇_max (the rate lag on
     a realized 1-missile world), and `rate_sat` lights during the jink; **the `:fin` peak G-ONSET ≤ 1.02·k_δ·δ̇_max
     while `:ideal`'s ≫ that** (the Lesson pin on the wire — the cap, NOT a miss) while **`a_max`/`δ_max` do NOT
     bind** (the isolation — assert `defl_sat == 0` AND `amax_bind == false` throughout the guided window r >
     r_stop, and δ < δ_max); **the `:fin` MISS stays small (< ~3 m, comparable to `:ideal`/`:pid` — PN robust)**,
     reported as corroboration NOT a lesson; **`:ideal↔:pid↔:fin` TRAJECTORIES (pos sequence) + peak g-onset DIFFER**
     (not-a-dead-knob — pinned on trajectory + the cap, NEVER on miss, since misses are sub-meter and `:fin`'s is
     LOWER than `:ideal`'s); **miss is vs the true `:target`** (the truth-path invariant); loader arms + rejects
     `k_delta ≤ 0` / `delta_max ≤ 0` / `delta_rate_max ≤ 0` / `tau_fin ≤ 0`.
   - `test_determinism.jl` (the SLICE-14 shape — NOT slice-11/13's RNG shape; watch-item): same-seed bit-identical
     with **NO RNG on the missile path** (pin `t` AND a per-missile pos sequence, RNG-independent); **a slice-1..14
     scenario is byte-identical** (`autopilot` unset/`:ideal`/`:pid` → the frozen arithmetic + no draw — the
     additivity master-check); **`:ideal↔:pid↔:fin` toggle CHANGES the trajectory** with **no RNG** (class 4c —
     write "draw-count invariance VACUOUS", do NOT claim slice-13 draws); **`:fin` introduce is CLEAN both
     directions** (no topology guard — the class-4c live-safety, unlike slice-13 `:scan`); `AutopilotState`
     structurally unchanged (`:ideal`/`:pid` fingerprints bit-for-bit).
   - `test_server.jl`: `set_fidelity :autopilot :fin` write/**introduce-safe both directions** (class 4c, no
     guard — the `:integrator`/`:autopilot` precedent, CONTRAST slice-13 `:scan`'s reject); the `delta_rate_max`
     live slider `set_param`→tick survives (a tiny/huge δ̇_max does NOT throw — "a live slider can't crash a tick").
     Slices 1–14 byte-identical.

3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice15_fin.yaml` (`autopilot:fin` HELD or
   `:pid` default so the button reveals the rate-limit degradation — gate-0 picks; `guidance:pn`/no-seeker HELD;
   the crossing/heading geometry + fin constants from gate 0; δ̇_max the lesson slider; `k_δ·δ_max ≤ a_max`).
   **Numbers probed against the live `load_scenario→integrate!→decide!→telemetry` wire** + pinned.
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode — the slice-8..14 precedent). The
     autopilot cycler gains the `:fin` rung (`:ideal↔:pid↔:fin`); **the NEW VISUAL: the fin deflection δ + the
     a_cmd-vs-a_ach lag** (a fin-deflection readout / bar and the tracking gap — "the fins can't keep up"; the
     rate-sat flag lit). All readout scalars (re-confirm no Array telemetry / `float()`-crash). Slice-1..14 views
     UNTOUCHED (re-run every smoke-load + UI test — the `:fin` rung falls through for scenarios without it).
   The autopilot cycler cycles `:ideal↔:pid↔:fin`; the δ̇_max slider is the lesson lever.
   - `net/slice15_verify.gd` (drives the real server): under the binding δ̇_max the `:fin` **peak g-onset ≤
     1.02·k_δ·δ̇_max (the cap BINDS) + the rate-sat fraction > 0 + `defl_sat==0`/`amax_bind==false` (isolation)**,
     while `:ideal`'s peak g-onset ≫ the cap; `set_param delta_rate_max <large>` **RAISES the cap (steepens the
     a_ach ramp toward `:ideal`)** — the lesson lever — with the **miss unchanged and small** (the "lack of effect"
     reported honestly, NOT a closing-miss); **`t`/per-missile `pos` bit-identical under the held seed+config**
     (RNG-free replay — the slice-14 discipline); **`set_fidelity autopilot fin` is ACCEPTED live** (the class-4c
     contrast to slice-13's `:scan` reject). `S15V OK`, exit 0. Step counts multiples of `emit_every`.
   - `net/slice15_ui_test.gd` (mock client, no server): the handshake wires the **autopilot** cycler through the
     3-rung ring (`:ideal↔:pid↔:fin`, wraps); badge/button track; the `delta_rate_max` slider sends `set_param`;
     reset resyncs (`S15UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-15 server (server `DONE` ⇒ scene connected, no
     GDScript errors).
   - `test_scenario.jl` + slice-15 loader testset (parses; `autopilot:fin` [or the held default] present;
     `guidance:pn`/no-seeker held; the fin comp keys at consumed keys + δ̇_max a knob; loader rejects each fin param
     ≤ 0).
   - The **`_draw` fin-deflection / rate-sat PIXEL branch** visually confirmed via the windowed shot harness
     ([[ewsim-godot-headless]]): the fins pinned at the rate limit while the commanded turn outruns them (the lag),
     vs a fast fin tracking. **(stretch, deferred)** `clients/notebooks/slice15_fin.jl` Pluto (MISS-vs-δ̇_max /
     phase-lag-vs-τ_s sweep — the rate-limit lesson as a curve).

## Task checklist
- [ ] **0. Probe + config pin** (`M:\claud_projects\temp\slice15_probe\`: `probe*.jl` + `FINDINGS.md`). Pin the
      regime (a/b/c) + headline (#1), the `r_stop` collision (#2), the fin constants + geometry (#3), the
      equivalence + kinematic anchors (#4/#5), byte-identity (#6), no-RNG (#7). **RE-CONSULT ADVISOR after the
      numbers.** Forward-flag gate-1/2/3 seams.
- [ ] **1. Primitive** — `fin_autopilot_step`/`fin_actuator_init`/`FinState`/`_clamp_mag` in guidance.jl +
      `AUTOPILOT_MODES += :fin`; `test_guidance.jl` arms (`:pid` equivalence, rate ramp, deflection pin,
      effectiveness map, zero-safe, diag flags). Slices 1–14 byte-identical (golden + determinism).
- [ ] **2. Wired** — the `:fin` `decide!` branch + `:fin_state` + fin telemetry; loader parse+validate of the fin
      params; `LIVE_FIDELITY_MODES` picks up `:fin` (NO re-list, NO set_fidelity guard — class 4c live).
      test_missile/test_determinism/test_server arms; slices 1–14 byte-identical.
- [ ] **3. Scenario + Godot + verifiers** — `scenarios/slice15_fin.yaml`; Sandbox.gd `:fin` cycler rung +
      fin-deflection/lag visual; the four proofs (verify/ui/smoke/shot); `test_scenario.jl` loader arm.
      **Re-probe on the emit-grid wire** (convention 10). STATUS.md + CLAUDE.md + HANDOFF (Tier-A opened) updated.
      **Slice 15 COMPLETE.**

## Context / landmarks
- **The guidance lib slice 15 extends:** `core/src/guidance.jl` — `AUTOPILOT_MODES`(:42), `autopilot_step`(:406,
  the `:ideal`/`:pid` plant — the `:pid` first-order lag `τ·ȧ=u−a` is what `:fin` generalizes with rate/deflection
  limits), `clamp_accel`(:358, reused as `_clamp_mag`), `AutopilotState`(:92, STRUCTURALLY FROZEN). The new
  `fin_autopilot_step`/`fin_actuator_init`/`FinState` go HERE (before radar.jl, the one-list precedent).
  `autopilot_step` is UNCHANGED (the `:fin` branch never routes through it).
- **The Autopilot slice 15 extends:** `Autopilot.decide!` (missile.jl:270) — the INNER-plant dispatch
  (`autopilot_step(mode,…)`, missile.jl:373–385); slice 15 adds the `:fin` branch (gated `mode === :fin`) → the new
  kernel + `:fin_state`. The `:ideal`/`:pid` arm stays textually unchanged (byte-identity).
- **The class-4c precedent (physics-changing, no RNG, live-settable, NO introduce-reject):** `:integrator`
  (slice 8), `:autopilot` `:ideal↔:pid` (slice 9), the `:apn` rung (slice 12), `:cooperation` (slice 14). CONTRAST
  slice-13 `:scan` (4b, introduce-rejected) — `:fin` is 4c, so `set_fidelity` needs NO new guard.
- **Fidelity plumbing precedent:** the `:apn` rung added to `GUIDANCE_MODES` (slice 12) — `:fin` is added to
  `AUTOPILOT_MODES` the SAME way (`*_MODES` → `LIVE_FIDELITY_MODES`(radar.jl:169) → `set_fidelity`(server.jl) +
  `_validate_fidelity`(scenario.jl:461), one-list-no-drift, NO re-list).
- **The load-validation precedent (the fin params):** the missile block validates `mass>0`/`a_max>0`/`tau>0`
  (scenario.jl / the ballistic loader) — the fin params `k_delta`/`delta_max`/`delta_rate_max`/`tau_fin` validate
  `> 0` the SAME way (immutable authored inputs; live sliders clamp-at-consumer).
- **The g-limit-as-lesson contrast:** `slice10_glimit.yaml` — `a_max` BINDS on purpose (MAGNITUDE saturation).
  Slice 15 is the DISTINCT failure: the RATE limit binds while `a_max`/`δ_max` do NOT (the isolation — do not
  re-import slice 10). The `_terminal_cutoff`/`r_stop` collision (advisor #3) is the slice-10..14 endgame guard.
- **The verifier sampling discipline:** [[ewsim-missile-verifier-sampling]] (first-CPA, exclude re-cross, the
  frame-sampling floor); [[ewsim-realtime-dt-floor]] (dt=1e-3/emit_every=16 cadence); [[ewsim-godot-headless]]
  (the windowed shot harness for the `_draw` proof).
- **HANDOFF** §11 Tier-A lines 483–491 (the Tier-A entry this OPENS — "6-DOF airframe + actuator/fin dynamics";
  slice 15 takes the actuator half, 6-DOF the deferred half), §10 item 9 (the autopilot/plant cascade), §3 (the
  tick contract — phase-4 decide!), §1 (named approximations; the sign/units trifecta).

## Watch-items (gotchas to bake in)
- **THE LIMITS ARE THE CONTENT (advisor, load-bearing).** A linear fin servo collapses to the `:pid` plant
  relabeled (k_δ cancels) — the convention-4c false-fidelity trap. δ̇_max/δ_max are the ONLY new physics; the
  scenario MUST make δ̇_max BIND or `:fin` is a dead knob. TEST the `:pid` equivalence (the degeneracy is a feature,
  proven).
- **ISOLATE THE RATE LIMIT — `a_max`/`δ_max` must NOT bind (advisor #2).** Set `k_δ·δ_max ≤ a_max` and tune δ̇_max
  as the sole binding constraint; assert `saturated == 0` and δ < δ_max in the scenario. Else the miss is a
  slice-10 MAGNITUDE miss wearing a fin costume.
- **THE `r_stop` COLLISION (regime a — advisor #3).** `_terminal_cutoff` freezes the outer law near r→0 ("the fins
  can't act faster than the tick anyway") — the exact rate-limit regime. Verify the saturation bites BEFORE
  `r_stop` engages (tune `r_stop` down / to 0), or fall to mid-course regime (b) which avoids it.
- **CLASS 4c, NOT slice-13's 4b.** Physics-changing, NO RNG → no draw-topology to flip → **introduce-SAFE,
  live-settable, NO set_fidelity guard** (the `:integrator`/`:autopilot`/`:apn`/`:cooperation` precedent). "Draw-
  count invariance" is **VACUOUS** — do NOT copy slice-11/13's "1 draw/tick / 2·N_p·N_bins / the sharp property to
  prove" language. The SECOND consecutive 4c (after slice 14).
- **`AutopilotState` STRUCTURALLY FROZEN (advisor #4).** δ lives in `:fin_state`, NOT new NamedTuple fields —
  growing it perturbs every `:pid`/`:ideal` fingerprint. Confirm golden + determinism bit-for-bit.
- **KEEP THE `:ideal`/`:pid` ARM BYTE-IDENTICAL.** The `:fin` branch is gated on `mode === :fin`; the `else` arm is
  the slice-9/10/12 arithmetic verbatim (the `+0.0`/spelling bit trap; the PID arithmetic is DUPLICATED into
  `fin_autopilot_step` rather than shared, so `:pid`'s bytes stay frozen — pin a slice-10 single-PN scenario,
  RNG-free).
- **NAME THE APPROXIMATION (advisor #5).** Slice 15 models the ACTUATOR (command→deflection through rate/position
  limits) and maps δ→lateral-accel DIRECTLY — SKIPPING the airframe's α/short-period rotational response. The
  lesson is "actuator rate saturation," NOT airframe dynamics; 6-DOF (the α/moment half) stays DEFERRED (the
  trigger recorded). δ_max is the PHYSICAL ORIGIN of the abstract `a_max`.
- **THE LANDING WAS EMPIRICAL — and it PIVOTED (the slice-12/14 lesson, realized).** The planned "rate limit opens
  the miss" did NOT materialize (12 probes; PN robust). Gate-0 picked the **g-onset cap** (`|da_ach/dt| ≤ k_δ·δ̇_max`,
  measurable/monotone/provable) as the primary, with the small miss reported as the honest "lack of effect" that
  motivates 6-DOF. Advisor RE-CONSULTED after the numbers (green light). Pin the cap RATIO (`:fin` onset/cap ≈ 1
  vs `:ideal` ≫ 1), NEVER a miss ratio — the misses are sub-meter and `:fin`'s is LOWER than `:ideal`'s.
- **Fin params are config; validate at LOAD** (`k_delta`/`delta_max`/`delta_rate_max`/`tau_fin > 0`); a live tiny/
  huge δ̇_max just slews slower/faster — no throw (the "a live slider can't crash a tick" discipline). `τ_s→0`
  floored; `_clamp_mag` non-finite-safe (no Inf/NaN to JSON — convention 6).
- **Stay spatial** — extend `_draw_spatial`, no new render mode (slice-8..14 precedent); the fin-deflection readout
  + the a_cmd-vs-a_ach lag + the rate-sat flag IS the visual. The autopilot cycler gains a 3rd ring state, not a
  new view. No Array telemetry (scalars only — the `float()`-crash watch-item).
- **Verifier drain multiples** of `emit_every`; the replay assertion pins `t` AND a per-missile pos sequence on an
  **RNG-INDEPENDENT** value (NO seeker draw — the slice-14 discipline, NOT slice-11/13's RNG-affected pos).
  First-CPA/miss stamp (exclude re-cross; [[ewsim-missile-verifier-sampling]]).
