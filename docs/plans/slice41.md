# Slice 41 — **A SECOND-ORDER FIN ACTUATOR: THE ACTUATOR INSIDE THE CONTROL LOOP** (§11 Tier-A)

**STATUS: GATE 0 PLANNED, NOTHING PROBED, NOTHING BUILT.** This file is the pre-probe record.
Every number below is a *prediction or a domain*, not a measurement — and §0.2 exists because the
inherited framing for this slice is one that must NOT be carried in.

The candidate is the deferral **slice 40 named as its own** (`docs/DEFERRALS.md`): *slice 15's fin is
first-order-with-a-rate-limit for exactly the reason slices 34–39's head was, and the bound slice 40
argues is not specific to a seeker head.*

---

## §0.0 THE BLOCKING CHECK — **PASSED** (run before anything else)

The slice only exists if the ringing wire actually flies fin channels rather than the lumped
`:a_ctrl` accel. Confirmed:

- `missile.jl:1211` — `alpha_6dof = has_af && get(w.fidelity, :airframe, :point_mass) === :six_dof`.
- `scenarios/slice40_resonance.yaml` / `slice40_heavy.yaml` (and the 26–38 radome arc) author
  `airframe: six_dof` + `autopilot: alpha` ⇒ `alpha_6dof == true` ⇒ the plant flies `(δp, δy)` and
  `:a_ctrl` is NOT persisted (`missile.jl:1433`).
- The seam is `missile.jl:1345–1346` — `c[:delta_cmd] = δp_cmd`, `c[:delta_yaw_cmd] = δy_cmd`, both
  written at the **END of phase-4 `decide!`**, consumed next tick by phase-1 `_integrate_6dof!`
  (`missile.jl:456`).

⇒ The insertion point is a two-line seam at the end of `decide!`. **Phase 1 is not touched.**

## §0.1 THE MODEL, AND THE SEAM DECISIONS DECLARED BEFORE THE PATCH

A new `:fin_servo` fidelity key (`FIN_SERVO_MODES`, defined ONCE in `airframe.jl` and REFERENCED by
`LIVE_FIDELITY_MODES` / `set_fidelity` — convention 7), three rungs:

* `:instant` — today. Gain exactly 1, phase exactly 0 at every frequency. **Bit-identical to the
  rung not existing.** This is what makes the three-rung ordering claim threshold-free.
* `:first_order` — `τ_a·δ̇ = δ_cmd − δ`. One number (`fin_tau_s`). ⚠⚠ **STEPPED BY THE EXACT
  EXPONENTIAL FORM, NOT EULER**: `δ′ = δ_cmd + (δ − δ_cmd)·exp(−dt/τ_a)`. Explicit Euler
  (`δ′ = δ + (δ_cmd − δ)·dt/τ_a`) is stable only for `τ_a ≥ dt/2 = 5e-4`, lands EXACTLY on `δ_cmd`
  at `τ_a = dt`, and oscillates and diverges below — and decision 3 ships NO rate limit, which is
  precisely what caps that blowup in slice 15's `fin_autopilot_step`. The exponential form is
  unconditionally stable, exact for a command held across the tick, and makes `τ_a → 0` a GENUINE
  limit to `δ_cmd`. This deletes an entire artifact class from the rung that carries P4.
* `:second_order` — `δ̈ = ω_a²(δ_cmd − δ) − 2ζ_a·ω_a·δ̇`, authored as `fin_omega_hz` / `fin_zeta`,
  stepped by SEMI-IMPLICIT EULER (slice 40's precedent — its bench and its "ratio 10.02 for a 10× dt"
  check are already written). Unstable around `ω_a·dt ≳ 2`, tighter at low `ζ_a` ⇒ P0 bounds it.

**Five decisions, written down before any probe, because a free choice inside a new actuator can
manufacture the claim** (slice 39 §0.1's discipline, slice 40 §0.1's form):

1. **PLACEMENT: END OF PHASE 4, OVERWRITING `:delta_cmd` / `:delta_yaw_cmd`** with the *achieved*
   deflection; the raw command is stashed under telemetry-only keys. Phase 1 stays TEXTUALLY
   unchanged ⇒ zero byte-identity risk on every ballistic/6-DOF slice, and the `τ_a→0` isolation is
   exact rather than one-tick-off. ⚠ Putting it in phase 1 inherits slice 37's ordering residual
   (`max|Δpos|` plateaus at 42.572 m against the shipped seam) — do not.
2. **PER-CHANNEL, INDEPENDENT STATE, IN ITS OWN COMP KEY.** `:fin_servo_state` carries
   `(δp, δ̇p, δy, δ̇y)`. It does NOT grow `AutopilotState` or slice-15's `FinState` — growing an
   existing NamedTuple perturbs every prior missile's fingerprint (slice-15 advisor #4).
3. **NO NEW RATE LIMIT. THE LESSON IS THE ORDER, NOT A LIMIT.** ⚠⚠ This is the explicit escape from
   the slice-20 kill (`δ_max` structurally SHADOWS `δ̇_max` inside this exact loop,
   `docs/plans/slice20.md`). Slice 41 ships actuator DYNAMICS and no new nonlinear cap; slice 20's
   kill is about which cap binds first and does not reach a resonance. **Do not re-import a
   rate-limit framing to give this slice a second knob.**
4. **THE EXISTING `δ_max` IS A MECHANICAL STOP ON THE ACHIEVED DEFLECTION, AND IT IS INELASTIC.**
   The rung can overshoot its command, so the achieved δ is clamped and **the clamp zeroes the rate
   state** — letting δ̇ wind up against a stop produces a clamp-driven oscillation that would fake a
   resonance exactly (slice 40 §0.1 decision 2 caught that arm for real). See P7: the shipped arms
   must never touch it anyway.
5. **THE ROLL CHANNEL IS UNTOUCHED.** `φ_cmd` already carries `τ_roll` (slice 24). The actuator sees
   `δp`/`δy` only, so no channel gets two lags stacked. Structural, not a promise.
6. **INITIALIZATION AND RUNG RE-ENTRY, STATED BEFORE THE PATCH.** `(δp, δ̇p, δy, δ̇y)` are ZERO at
   launch, and **the rate state is ZEROED ON ENTERING THE RUNG, NOT CARRIED** across a live fidelity
   toggle (slice 40 shouts this at `missile.jl:1870` — a carried rate makes a mid-flight toggle a
   transient injector, which fakes exactly the effect this slice claims). ⚠ Tick 1 still flies
   `af_delta` because `integrate!` precedes the first `decide!` (`missile.jl:1343`) — the scenarios
   author `af_delta: 0` so tick 1 injects no transient, and that stays true here.
7. **THE NEW TELEMETRY KEYS ARE GATED ON THE RUNG'S PRESENCE** — `if haskey(c, :fin_tau_s) ||
   haskey(c, :fin_omega_hz) || haskey(c, :fin_zeta)`, slice 40's `missile.jl:2939` pattern.
   Unconditional new keys change the wire payload for EVERY prior slice's verifier.

## §0.2 ⚠⚠ THE INHERITED FRAMING THAT MUST NOT BE CARRIED IN (advisor, pre-probe)

The deferral was written as *"the bound slice 40 argues is not specific to a seeker head"* — a
first-order lag has gain ≤ 1 and phase ≥ −90° at every frequency, so it can only damp. **The BOUND
transfers; THE SIGN OF THE EFFECT DOES NOT, AND WRITING THAT IT DOES IS THE GATE-1 REFUTATION
WAITING TO HAPPEN.**

On slices 34–40 the lag sat on the *index / feed-forward* path, low-passing a CORRUPTING measurement
out of the glass — which is why it was "silently doing stability work." **The fin actuator sits
inside the MAIN CONTROL FEEDBACK LOOP** (α autopilot → δ → M → α → autopilot), where added phase lag
*eats phase margin* and DESTABILIZES. Same component, same bound, opposite sign, **because of where
it sits in the loop.**

⇒ Gate 0 predicts NOTHING about the direction and measures it (P4). **If the sign inverts, that
inversion is the headline of the slice**, and it is a stronger one than the deferral asked for.

## §0.3 ⚠ WHICH MODE THE ACTUATOR ACTUALLY COLLIDES WITH — the inert risk, named first

A real fin actuator runs **20–60 Hz**. The radome limit cycle lives at **1.7–2.1 Hz**. At that
separation the actuator's gain at the ring is ≈1 and the rung reads **INERT** — the same flat outcome
that killed `ζ` on slice 40's first-order rung (a dead knob, convention-4 false fidelity).

But the airframe's own short period is `ω_sp ∈ [9.7, 68.7] rad/s` ≈ **1.5–11 Hz**
(`airframe.jl:624`), which **overlaps a realistic actuator**. ⇒ **The axis is `ω_a/ω_sp`, not `ω_a`
against the ring**, and slice 16's existing `ω_sp` sentinel is pre-built tooling for the departure
end of it. P2 and P3 measure both and let the numbers pick the mechanism.

## §0.4 THE GATE-0 PROBE LIST

| # | Probe | What it decides |
|---|---|---|
| **P0** | **THE BENCH.** Open-loop step + frequency response of both rungs against the closed-form second-order response, on a frozen bench (slice 37's precedent). Walk `ω_a` up until semi-implicit Euler at `dt = 1e-3` starts manufacturing oscillation. | **BOUNDS THE AUTHORED DOMAIN.** A stiff actuator at a 1 ms step fakes a resonance — the same class as slice 40's stop-driven artifact. No resonance may be claimed above this bound. |
| **P1a** | **THE ISOLATION PROBE — the kill risk, flown FIRST.** `:instant` must be **BIT-EXACT** against the shipped tree over a full flight. | The byte-identity proof, and it holds **BY CONSTRUCTION** (the rung returns the command untouched) — INDEPENDENT of any `τ_a`. If it is not exact, the placement is wrong. |
| **P1b** | **THE CONVERGENCE RESULT — a DOMAIN result, belonging to P0, NOT an isolation proof.** How closely `τ_a → 0` / large `ω_a` approach `:instant` inside the stable domain. | ⚠⚠ **DO NOT WORD THIS AS AN ISOLATION PROOF.** A failure here is a DISCRETIZATION failure, not a placement failure, and conflating them costs a pointless seam re-audit. The exponential first-order form (§0.1) makes `τ_a → 0` a genuine limit; `ω_a → ∞` is OUTSIDE the domain P0 exists to find and is not claimed. |
| **P2** | **THE INERT LADDER.** Sweep `ω_a` from 60 Hz down on the shipped slice-40/26 wire; read the limit-cycle rms *and* the miss. Print the WHOLE ladder. | Whether the effect exists at a physically honest actuator, or only at an absurd one. A flat ladder down to 5 Hz is a KILL. |
| **P3** | **THE SHORT-PERIOD COLLISION.** ⚠ **MEASURE `ω_sp` ON THE SHIPPED WIRE FIRST, THEN choose the ratios** — `ω_a/ω_sp ∈ {10, 5, 2, 1, 0.5}` is only physically honest if `ω_sp` lands at the HIGH end of `[9.7, 68.7] rad/s`; at `ω_sp ≈ 10` the 0.5 ratio is a 0.8 Hz actuator, which is absurd territory and is exactly what P2 exists to reject. Read overshoot, the `ω_sp` sentinel, departure. | The candidate mechanism (§0.3), and which ratios a claim may be shipped from. |
| **P4** | **THE DIRECTION PROBE.** Does `:first_order` DAMP or DESTABILIZE relative to `:instant`, at the same design? | §0.2's open question. The potential headline. |
| **P5** | **THE REPARAMETERIZATION GATE — ANSWERED BY A BOUND, NOT A TOLERANCE** (slice 39's kill, pre-empted). Can ANY `(k_α, k_q)` on `:instant` reproduce a `:first_order` arm? | The argument is **order/phase, not gain** — an added actuator pole is unreachable by retuning two gains on the existing plant (slice 38's *"`s` adds PHASE and scaling a slope cannot"*, verbatim). Must be stated as a bound over the whole `(k_α, k_q)` space, not a fitted tolerance. |
| **P6** | **MONOTONICITY OF WHATEVER SHIPS AS THE SLIDER.** Full ladder across the full range. | Slice 40 disqualified `ω_n` on the gimbal for non-monotonicity; that does not carry over, but it must be SHOWN, not assumed. `ζ_a` is the expected slider (slice 40's shipped choice). |
| **P7** | **THE SLICE-20 SHADOW TOOTH.** Assert `defl_sat == 0` on EVERY claimed arm of BOTH new rungs. | A lagging actuator transiently demands a LARGER deflection and could newly peg `δ_max` — which resurrects slice 20's shadowing and contaminates the claim. |

### ⚠⚠ THE VERDICT RULE, FIXED BEFORE ANY NUMBER EXISTS

P2 and P4 both read "the limit-cycle rms", and **what counts as DAMPED vs DESTABILIZED is fixed
here, in advance.** Slice 37's onset line was a threshold chosen *post hoc* and it turned out to be
load-bearing (the shipped head read 13 % below it); the rule that replaced it is the one adopted
here:

- the verdict is the **LARGEST SINGLE-STEP RATIO** along the ladder — no absolute rms threshold is
  chosen by me, at any point;
- **the WHOLE ladder is printed** in the plan and in `docs/STATUS.md`, so a reader can redraw the
  line themselves;
- if any claim's magnitude moves under a different defensible rule, **the sensitivity is quoted**
  (slice 37's "≈40–45 %" form), and only the ORDER of the rungs and the SIGN of the effect may be
  stated threshold-free.

## §0.5 THE NAMED KILL RISKS, IN THE ORDER THEY WOULD FIRE

1. **INERT** (P2) — a realistic actuator is 10–30× above the ring, reads flat, and the rung is a dead
   knob. *Mitigation: §0.3's `ω_a/ω_sp` axis is a different and live collision. If BOTH are flat, the
   slice dies at gate 0 and this file becomes a kill record.*
2. **REPARAMETERIZATION** (P5) — the actuator pole is absorbed by the existing gains. *This is how
   slice 39 died. Answered by a bound.*
3. **EULER ARTIFACT** (P0) — the "resonance" is the discretization. *Bounded before it is claimed.*
4. **SHADOWED BY `δ_max`** (P7) — slice 20's kill, in a new letter.
5. **THE INHERITED SIGN** (§0.2) — asserting "a lag can only damp, here too." *Predict nothing.*

## §0.6 WHAT WOULD SHIP (subject to the gates)

Gate 1: `FIN_SERVO_MODES` + the actuator kernel in `airframe.jl`, pure and closed-form-tested against
the analytic second-order response, with the discretization bound pinned. Gate 2: the `:fin_servo`
key wired at the phase-4 seam, both channels, with the `:instant` bit-identity test. Gate 3: one
scenario on the shipped radome wire with the rung on the fidelity button and `ζ_a` (or whatever P6
clears) on the slider, plus the four gate-3 proofs — verifier, UI test, headless scene smoke-load,
shot capture. ⚠ `STEPS` must be a multiple of the scenario's `emit_every`.
