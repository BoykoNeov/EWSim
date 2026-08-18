# Slice 41 — **A SECOND-ORDER FIN ACTUATOR: THE ACTUATOR INSIDE THE CONTROL LOOP** (§11 Tier-A)

**STATUS: P0 AND P1a/P1b RUN (2026-08-18) — see §I and §II. THE SLICE IS NOT YET CLEARED:
P2 (INERT) and P5 (REPARAMETERIZATION), the two risks that can still kill it, are UNRUN.**

**§0–§0.6 below are the PRE-PROBE record and are left exactly as written**: every number in them
is a *prediction or a domain*, not a measurement, and §0.2 exists because the inherited framing for
this slice is one that must NOT be carried in. Where a probe refuted a prediction, the refutation is
marked at the prediction and recorded in §I/§II — the prediction is never quietly edited to match.

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
  ⚠⚠ **THE SECOND HALF OF THAT SENTENCE IS REFUTED BY P0 — see §I.1.** The bound is a CURVE and it
  is tighter at HIGH `ζ_a`, not low. Left standing here because it was the prediction.

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

---

# §I — P0: THE BENCH (2026-08-18)

A frozen bench, slice 37's precedent: both candidate kernels re-declared inside a throwaway probe so
the measurement is of the LAW, not of a wiring. Every cell below is at the shipped `dt = 1e-3`.

## ⭐⭐ §I.1 THE STABILITY BOUND IS A **CURVE**, AND §0.1's OWN PREDICTION WAS BACKWARDS

§0.1 predicted *"unstable around `ω_a·dt ≳ 2`, tighter at low `ζ_a`"*. **Both halves are wrong.**
Nondimensionalising the semi-implicit recursion in `h = ω_a·Δt`, the amplification matrix on
(error, rate·Δt) is

    x'      = (1 − h²)·x + (1 − 2ζh)·(vΔt)
    (v'Δt)  =   −h² ·x + (1 − 2ζh)·(vΔt)          det = 1 − 2ζh      trace = 2 − 2ζh − h²

which is **dimensionless in `h` and `ζ` alone** — `Δt` only sets the Hz at which a given `h` is
reached, so the boundary is a property of the pair and not of the actuator. Jury's conditions
(`|det| < 1`, `|trace| < 1 + det`) give

    h_max = min( 1/ζ , 2(√(1+ζ²) − ζ) )

and the second term binds **everywhere** — `1/ζ` is never the constraint at any `ζ` on the grid. It
**FALLS monotonically as ζ RISES.**

| ζ_a | h_jury | h at ρ = 1 | h flown | f_a ceiling, Hz @ dt = 1e-3 |
|---|---|---|---|---|
| 0.02 | 1.96040 | 1.96040 | 1.96040 | 312.0 |
| 0.05 | 1.90250 | 1.90250 | 1.90250 | 302.8 |
| 0.10 | 1.80998 | 1.80998 | 1.80997 | 288.1 |
| 0.20 | 1.63961 | 1.63961 | 1.63960 | 261.0 |
| 0.30 | 1.48806 | 1.48806 | 1.48806 | 236.8 |
| 0.50 | 1.23607 | 1.23607 | 1.23607 | 196.7 |
| 0.7071 | 1.03528 | 1.03528 | 1.03529 | 164.8 |
| **1.00** | **0.82843** | 0.82843 | 0.82844 | **131.8** |
| 1.50 | 0.60555 | 0.60555 | 0.60557 | 96.4 |
| 2.00 | 0.47214 | 0.47214 | 0.47215 | 75.1 |
| 3.00 | 0.32456 | 0.32456 | 0.32457 | 51.7 |

**THREE INDEPENDENT ORACLES AGREE TO FIVE DECIMALS** (convention 11): the closed-form Jury
prediction, the numerically-computed spectral radius of the 2×2, and a *flown* free response
bisected for the onset of a non-decaying envelope.

⭐ **AND ITS CONTROL ROW IS THE SHIPPED GIMBAL'S OWN DATUM.** `frames.jl` records slice 40's servo
*decaying at 200 Hz and DIVERGING at 300 Hz*. A plain `h < 2` rule cannot explain a divergence at
`h = 1.885`; this curve can, and only at slice 40's own `ζ = 0.1`:

| f | ζ | h | ρ | verdict |
|---|---|---|---|---|
| 200 Hz | 0.10 | 1.2566 | 0.86526 | decays |
| 300 Hz | 0.10 | 1.8850 | **1.52024** | **DIVERGES** — matches the shipped comment |
| 200 Hz | 0.05 | 1.2566 | 0.93506 | decays |
| 300 Hz | 0.05 | 1.8850 | 0.90084 | decays — i.e. the shipped datum pins ζ ≈ 0.1, not ζ ≤ 0.05 |

⚠⚠ **THE CONSEQUENCE, AND IT IS A LOAD-TIME CONSTRAINT ON THE PAIR — IT DOES NOT WAIT FOR P6.**
Whatever a wire authors as `fin_omega_hz`, the loader must reject it against **the worst `ζ_a` that
wire can REACH**: the slider's ceiling if `ζ_a` is live, the authored value if it is not.
**`fin_omega_hz` alone is not a validatable quantity.** Concretely, on slice 40's slider shape
(`ζ ∈ [0.05, 1.0]`) the binding cell is the CEILING, `ζ = 1.0` — 131.8 Hz, not the ~303 Hz a walk at
the floor would have reported. A domain authored off the floor goes unstable when the student drags
the slider *up*, which is the worst possible place to put an instability.

## §I.2 THE TIGHTER BOUND: WHERE THE STEPPER MANUFACTURES AN OSCILLATION

Divergence is not the first thing that goes wrong, and it is not the artifact P0 exists to bound. An
authored `ζ_a ≥ 1` has NO overshoot in continuous time; the discrete recursion acquires one **well
below** the stability boundary — that overshoot IS "a stiff actuator at a 1 ms step fakes a
resonance", in its own currency.

| ζ_a | h at first overshoot | f_a, Hz | h at instability | f_a, Hz |
|---|---|---|---|---|
| 1.00 | 0.73595 | **117.1** | 0.82843 | 131.8 |
| 1.20 | 0.65820 | 104.8 | 0.72410 | 115.2 |
| 1.50 | 0.56432 | 89.8 | 0.60555 | 96.4 |
| 2.00 | 0.45132 | 71.8 | 0.47214 | 75.1 |
| 3.00 | 0.31748 | 50.5 | 0.32456 | 51.7 |

⇒ **THE HONEST CEILING IS 117 Hz, NOT 132.**

## §I.3 THE DISCRETE RESPONSE'S OWN ζ — AND ITS ERROR IS IN THE SAFE DIRECTION

By log decrement on the kernel's own free response — an INDEPENDENT recompute the recursion never
forms (convention 11). ⚠ The first run of this bench read NaN at five of nine cells and it was an
**instrument** defect, not a stepper one: a fixed 10 s window underflows the late peaks to `0.0` at
high `ω` and `log(x/0) = Inf`. The window is now a TIME-CONSTANT COUNT. (Slice 40's gate 0 was bitten
by the sibling of this, an oracle that returned NaN at `ζ = 1`.)

| f_a | ζ_a | h | ζ_eff | ζ_eff/ζ | f_d meas | f_d exact | f_d err |
|---|---|---|---|---|---|---|---|
| 2 | 0.10 | 0.0126 | 0.100062 | 1.0006 | 1.9913 | 1.9900 | 0.07 % |
| 10 | 0.10 | 0.0628 | 0.100302 | 1.0030 | 9.9819 | 9.9499 | 0.32 % |
| 30 | 0.10 | 0.1885 | 0.100778 | 1.0078 | 30.2198 | 29.8496 | 1.24 % |
| 60 | 0.10 | 0.3770 | 0.101498 | 1.0150 | 61.4525 | 59.6992 | 2.94 % |
| 100 | 0.10 | 0.6283 | 0.101926 | 1.0193 | 104.3478 | 99.4987 | 4.87 % |
| 150 | 0.10 | 0.9425 | 0.100573 | 1.0057 | 164.3836 | 149.2481 | **10.14 %** |
| 200 | 0.10 | 1.2566 | 0.100419 | 1.0042 | 237.2881 | 198.9975 | **19.24 %** |
| 30 | 0.50 | 0.1885 | 0.525438 | 1.0509 | 27.027 | 25.9808 | 4.03 % |
| 60 | 0.50 | 0.3770 | 0.556037 | 1.1121 | 56.338 | 51.9615 | 8.42 % |

⚠ **THE TWO `ζ = 0.5` ROWS ARE THE LARGEST ERRORS QUOTED AND THEY RUN ON THE FEWEST PEAKS** (5, the
estimator's minimum — a lightly-damped response gives 32), so they are exactly the cells LESSONS
warns are *"a bracket at the edge of its own grid"*. **Checked rather than assumed:** widening the
window to 40 / 80 / 160 time constants takes the peak count to 11 / 22 / 45 and moves `ζ_eff` from
0.525438 to 0.525461 (30 Hz) and 0.556037 to 0.555986 (60 Hz) — stable in the sixth figure. ⇒ they
are MEASURED, not truncated.

⭐ **THE SIGN OF THE ERROR IS THE REASSURING PART: `ζ_eff > ζ` IN EVERY CELL.** Semi-implicit Euler
here ADDS damping; it cannot manufacture a ring by *removing* it. What it does distort, and badly, is
the FREQUENCY — 10 % high at 150 Hz and 19 % at 200 Hz. ⇒ **the ceiling in §I.2 is the binding one,
and above ~60 Hz any claim must be quoted as "the servo the discrete recursion actually flew", not as
the authored one.** At a physically honest 20–60 Hz actuator the damping error is 1.5–11 % of the
authored value and the frequency error 1–8 %.

## §I.4 THE RUNGS AGAINST THEIR CLOSED FORMS

**Second order** — vs `H(s) = ω²/(s² + 2ζωs + ω²)`, **all three branches of the oracle carried from
line one** (`ζ < 1` / `= 1` / `> 1`; `√(1−ζ²)` is 0/0 at 1 and imaginary past it). The RATIO is the
tooth — a flat column would mean the recursion is not solving this equation.

| f_a | ζ_a | h | err @1e-3 | err @1e-4 | ratio |
|---|---|---|---|---|---|
| 2 | 0.05 | 0.0126 | 6.269e−03 | 6.259e−04 | 10.02 |
| 2 | 0.30 | 0.0126 | 5.716e−03 | 5.707e−04 | 10.02 |
| 2 | 1.00 | 0.0126 | 3.919e−03 | 3.911e−04 | 10.02 |
| 2 | 3.00 | 0.0126 | 1.851e−03 | 1.848e−04 | 10.02 |
| 0.5 | 0.10 | 0.0031 | 1.549e−03 | 1.548e−04 | 10.00 |
| 10 | 0.30 | 0.0628 | 2.880e−02 | 2.855e−03 | 10.09 |
| 30 | 0.70 | 0.1885 | 7.100e−02 | 6.900e−03 | 10.29 |
| 60 | 1.00 | 0.3770 | 1.249e−01 | 1.181e−02 | 10.58 |

FIRST ORDER at the low-h cells, matching slice 40's own 10.02, and degrading gracefully as `h` grows.

**First order (the exact exponential)** — ⚠⚠ **THE dt-RATIO TOOTH DOES NOT APPLY HERE AND COPYING IT
OVER WOULD MANUFACTURE A BUG REPORT AGAINST A CORRECT KERNEL.** `δ′ = δ_cmd + (δ−δ_cmd)·exp(−dt/τ)` is
*exact* for a command held across the tick, so its error is accumulated rounding
(**1e−16 … 6e−15** over 5 s across `τ ∈ [1e−6, 0.5]`) and its dt column is FLAT BY CONSTRUCTION.

**And the limit is genuine, not asymptotic.** One tick from `δ = 0` toward `δ_cmd = 1`:

| τ_a | achieved | abs(1 − δ) | explicit Euler would give |
|---|---|---|---|
| 1e−2 | 0.0951625819640405 | 9.048e−01 | 0.1 |
| 1e−3 | 0.6321205588285577 | 3.679e−01 | 1.0 |
| 5e−4 | 0.8646647167633873 | 1.353e−01 | 2.0 |
| 1e−4 | 0.9999546000702375 | 4.540e−05 | 10.0 |
| **1e−6** | **1.0** | **0.0** | 1000.0 |
| 1e−12 | 1.0 | 0.0 | 1e9 |
| **0.0** | **1.0** | **0.0** | NaN |

⇒ `τ_a → 0` reaches `δ_cmd` **exactly**, and `τ_a = 0` is a clean degenerate rather than a division.

**The price of the form §0.1 refused**, measured (200 ticks of a held command, worst abs(δ)):

| τ_a | dt/τ | exponential | explicit Euler |
|---|---|---|---|
| 1e−3 | 1.0 | 1.0 | 1.0 |
| 7e−4 | 1.4286 | 1.0 | 1.42857 |
| 5e−4 | 2.0 | 1.0 | 2.0 |
| 4e−4 | 2.5 | 1.0 | **1.65e+35** |
| 3e−4 | 3.3333 | 1.0 | **3.94e+73** |

⇒ §0.1's arithmetic is confirmed to the digit: explicit Euler is stable only for `τ_a ≥ dt/2`, lands
exactly on the command at `τ_a = dt`, and blows up below — and with decision 3 shipping no rate limit
there is nothing to cap it. **The exponential form deletes that artifact class from the rung that
carries P4.**

## ⭐ §I.5 GAIN **AND PHASE** — THE NUMBER P2 IS OWED

§0.3 fears the rung reads INERT because a 20–60 Hz actuator has gain ≈ 1 at the 1.7–2.1 Hz ring. That
is true and it is **not the same as inert**, because §0.2's whole argument is about PHASE eating
margin, not gain. So P0 hands P2 both. Measured off the recursion by correlation, with the continuous
closed form beside it.

**AT 2 Hz (the radome limit cycle):**

| rung | gain meas | gain exact | phase meas | phase exact |
|---|---|---|---|---|
| 2nd, 60 Hz, ζ 0.7 | 0.99973 | 1.00002 | −1.95° | −2.68° |
| 2nd, 30 Hz, ζ 0.7 | 0.99950 | 1.00008 | **−4.63°** | −5.36° |
| 2nd, 20 Hz, ζ 0.7 | 0.99928 | 1.00015 | −7.32° | −8.05° |
| 2nd, 30 Hz, ζ 0.1 | 1.00429 | 1.00437 | −0.05° | −0.77° |
| 1st, τ = 1/(2π·30) | 0.99779 | 0.99779 | −3.47° | −3.81° |
| 1st, τ = 0.05 | 0.84674 | 0.84673 | −31.78° | −32.14° |

**AT 11 Hz (the TOP of the airframe short-period band, `ω_sp` = 68.7 rad/s — §0.3's live collision):**

| rung | gain meas | gain exact | phase meas | phase exact |
|---|---|---|---|---|
| 2nd, 60 Hz, ζ 0.7 | 0.99089 | 1.00011 | −10.74° | −14.87° |
| 2nd, 30 Hz, ζ 0.7 | 0.97803 | 0.99371 | **−26.17°** | −30.67° |
| 2nd, 20 Hz, ζ 0.7 | 0.94556 | 0.96252 | −42.80° | −47.83° |
| **2nd, 30 Hz, ζ 0.1** | **1.14723** | **1.15120** | −0.82° | −4.84° |
| 1st, τ = 1/(2π·30) | 0.93822 | 0.93888 | −18.19° | −20.14° |

⭐⭐ **TWO THINGS P2 MUST NOT ASSUME AWAY.** (1) A 30 Hz actuator contributes **−4.6° at the ring** —
small, but "gain ≈ 1" is not the same statement as "phase ≈ 0", and whether 4.6° matters on a
marginally-stable parasitic loop is a QUANTITATIVE question, not a foregone one. (2) At the top of the
short-period band the same physically-honest actuator is at **−26°**, and a lightly-damped one has
**gain 1.15 — above 1, at 30 Hz, i.e. at a completely realistic actuator.** §0.2's bound is left
there, inside the band §0.3 named as the live collision. **The `ω_a/ω_sp` axis is not a consolation
axis; it is where the numbers are.**

⚠ **§0.2's FIRST-ORDER BOUND HOLDS, AND ITS APPARENT VIOLATION IS THE INSTRUMENT.** Over
`τ ∈ [1e−3, 1] × f ∈ [0.1, 200] Hz` the measured gain peaks at **1.000525**, at `τ = 1e−3, f = 2.374 Hz`
where the analytic value is 0.9998888 — and the correlator's own worst error over that grid is
**0.0407**, i.e. **the excursion is 80× smaller than the instrument**. Measured phase never leaves
(−87.53°, −0.02°]. The bound transfers; §0.2's point was only ever that the SIGN does not.

⚠ **THE MEASURED-vs-CLOSED-FORM PHASE GAP IS NOT NOISE — IT IS THE HALF TICK, AND IT IS NAMED SO P2
CARRIES THE RIGHT NUMBER.** The seam samples the command at the END of the tick, so the discrete rung
LEADS the continuous one by `ω·dt/2`:

| f | τ | gap | ω·dt/2 | residual |
|---|---|---|---|---|
| 2 Hz | 0.005 | +0.348° | 0.360° | −0.012° |
| 5 Hz | 0.020 | +0.893° | 0.900° | −0.008° |
| 11 Hz | 0.020 | +1.993° | 1.980° | +0.013° |
| 20 Hz | 0.020 | +3.570° | 3.600° | −0.030° |

⇒ a named, quantified sampling effect (residual ≤ 0.12° over the whole grid), not correlator noise.

## §I.6 WHAT P0 DECIDES

1. **THE AUTHORED DOMAIN IS BOUNDED BY A CURVE, NOT A NUMBER:** `f_a ≤ h_over(ζ_a)/(2πΔt)`, using the
   OVERSHOOT boundary of §I.2 rather than the looser stability one. **117 Hz is the value of that
   curve AT `ζ_a = 1.0`, not the bound** — the curve reads 104.8 Hz at ζ = 1.2 and 50.5 Hz at ζ = 3.
   ⚠ Gate 2 must implement the curve; hard-coding 117 reintroduces the single number this probe
   exists to replace. No resonance may be claimed above it.
2. **KILL RISK 3 (EULER ARTIFACT) DOES NOT BIND FOR A PHYSICALLY HONEST ACTUATOR.** A 20–60 Hz fin
   sits at `h ∈ [0.126, 0.377]`, a factor 2–6 inside the boundary at *every* ζ, with `ζ_eff` erring
   1.5–11 % **in the damping direction**. ⇒ **attention belongs on P2 (INERT) and P5 (REPARAM).**
3. **The exponential first-order form is confirmed and priced**, and its `τ_a → 0` limit is EXACT.
4. **P2 is owed a phase budget, not only a gain ladder** — −4.6° at the ring, −26° at the top of the
   short period, and gain 1.15 there at `ζ_a = 0.1`, all at a realistic 30 Hz actuator.

---

# §II — P1a / P1b: THE ISOLATION PROBE AND THE LIMIT (2026-08-18)

A minimal PROTOTYPE patch was applied to the tree, flown, tested and **reverted** (the tree is clean;
the diff is kept at `M:\claud_projects\temp\slice41\prototype_seam.patch` for gate 1). It is the
kernel plus the phase-4 seam and nothing else: 56 inserted lines, 0 deleted.

⭐ **ONE SEAM FINDING FELL OUT OF WRITING IT, AND IT CHANGES NOTHING BUT IS WORTH KNOWING BEFORE
GATE 2: phase 4 IS HANDED NO `dt`.** `decide!(s, w)` takes only the world. The actuator reads the
Autopilot's OWN phase-1 capture `c[:dt_s]` (`missile.jl:1019` writes it, `missile.jl:1117` already
reads it back in phase 4) ⇒ **the seam mints no new key for a timestep**, and slice 25's sibling
`:dt_s_seeker` shows the same pattern on the seeker.

## §II.1 P1a — `:instant` IS BIT-EXACT AGAINST THE SHIPPED TREE ON NINE WIRES

12800 ticks each (slice 40's own verifier length). The instrument folds FOUR fingerprints per tick:
the full state (pos/vel/att + every numeric comp value), the comp **KEY SET** plus the telemetry
**KEY SET**, the telemetry values the wire actually ships, and a fingerprint of the RNG stream
position taken off a *copy* so the probe never perturbs the stream it measures.

⚠ **THE KEY-SET FINGERPRINT IS THERE BECAUSE A FLOAT TRACE PASSES CLEANLY WHILE THE WIRE PAYLOAD
CHANGED** — which is exactly what decision 7 exists to prevent (advisor).

| path | wires | result |
|---|---|---|
| 6-DOF `:alpha` — **the insertion point** (`missile.jl:1345–46`) | `slice40_resonance`, `slice40_heavy`, `slice37_frame`, `slice26_radome` | **BIT-EXACT** |
| scalar `:pitch_coupled` `:alpha` — a DIFFERENT `:delta_cmd` writer (`:1277`) | `slice19_alpha_limit`, `slice22_stall` | **BIT-EXACT** |
| slice-15 `:fin` autopilot — a THIRD `:delta_cmd` producer | `slice15_fin` | **BIT-EXACT** |
| open loop, `af_delta`, no `:delta_cmd` at all | `slice17_coupling` | **BIT-EXACT** |
| `:point_mass` / `:ideal` — the guard's false branch | `slice9_pursuit` | **BIT-EXACT** |

**AND THE FULL SUITE PASSES ON THE PATCHED TREE: 7693/7693, 3m58s.** This is the check that
matters and it is not optional: convention 2 names the `_sample_z` N_p=1 **absolute golden** plus
`test_determinism.jl` as the master byte-identity pair, and warns that `test_determinism` compares
run-A-vs-B and therefore CANNOT catch a draw-ORDER regression. A hand-rolled trace comparison is in
that same weaker class; only the golden closes it. (advisor)

## §II.2 ⚠ THE CONTROL ROW — THE INSTRUMENT CAN SEE A CHANGE

A trace comparison that cannot detect a difference proves nothing (*"a tooth that passes can still be
a tautology"*, `docs/LESSONS.md`). Every `:first_order` arm in §II.3 MOVES the fingerprint, so the
nine BIT-EXACT rows above are a measurement and not a blind instrument.

## §II.3 P1b — THE LIMIT, AS A **DOMAIN** RESULT (NOT AN ISOLATION PROOF)

⚠⚠ A failure here would be a DISCRETIZATION failure, not a placement failure. Worded accordingly.

`max|Δpos|` is against the same tree's `:instant` arm, over 12800 ticks, sampled every 16:

| τ_a | slice40_resonance | slice26_radome |
|---|---|---|
| **1e−6** | **0.000000e+00** | **0.000000e+00** |
| 1e−4 | 6.498083e−05 | 3.981702e−02 |
| 1e−3 | 8.518931e−01 | 4.560085e+02 |
| 5e−3 | 3.857462e+00 | 2.267797e+03 |
| 2e−2 | 1.498344e+01 | 2.252643e+03 |

⭐ **AT `τ_a = 1e−6` THE FLIGHT IS BIT-IDENTICAL TO `:instant`, NOT MERELY CLOSE** — and the
fingerprints localise *what* differs with no ambiguity at all: over all 12800 ticks the telemetry
fingerprint differs on **0** ticks and the RNG fingerprint on **0** ticks; only the state and key-set
fingerprints move, and the key diff is exactly `fin_servo_state` (plus the probe's own injected
`fin_tau_s`). ⇒ **the wire payload is untouched and the physics is untouched; the limit adds one
private comp key.** That is the strongest form this result comes in.

⚠ **AND IT IS PRECISELY LIMITED.** Under `:instant` achieved == commanded, so decision 1's overwrite
is a literal no-op and P1a alone would pass **whether or not the end of phase 4 is the right seam**
(advisor). What the `τ_a → 0` arm adds is that the seam introduces **no EXTRA tick of delay**: had the
achieved deflection been written somewhere consumed a tick later, the limit could not have landed on
`:instant` bit-for-bit. It does NOT independently confirm the one-tick delay that was already there —
`exp(−dt/τ) = 0` annihilates the carried state, so that arm cannot see it.

## ⚠ §II.4 A SIGNPOST FOR P2 — EXPLICITLY NOT A CLAIM

The `τ_a` ladder is **NOT FLAT**, and on `slice26_radome` it is violently not flat (456 m at
`τ_a = 1e−3`, a ≈160 Hz actuator). That is *suggestive* against kill risk 1 (INERT) — and it is
**not evidence of the lesson**, for two reasons this file records before P2 can be tempted by it:

1. **`max|Δpos|` IS A DIVERGENCE METRIC ON A MARGINALLY-STABLE WIRE, NOT A LESSON METRIC.** Two arms
   of a ringing loop separate exponentially; the number measures sensitivity, not stability, and it
   ORDERS NOTHING. The lesson metrics are the limit-cycle rms and the miss (P2's own).
2. **THE VERDICT RULE IN §0.4 STANDS UNCHANGED** — largest single-step ratio, whole ladder printed,
   sensitivity quoted. Nothing here licenses a threshold.

## ⭐⭐ §II.5 THE SECOND CLAMP SITE, COUNTED — P7 HAS A HEAD START AND A PROBLEM

Decision 4 gives the actuator a SECOND clamp site (the inelastic `δ_max` stop on the *achieved*
deflection). It writes no telemetry, and `alpha_diag.defl_sat` still reports only the PRE-actuator
`defl_p || defl_y` — so it could fire invisibly and make the §II.3 ladder a measurement of
clamp-driven behaviour rather than of actuator dynamics (advisor; and slice 40's gate 1 caught
exactly that arm for real). Counted, on the same two wires, 12800 ticks:

| arm | new-clamp fires (pitch / yaw) | pre-actuator `defl_sat` ticks |
|---|---|---|
| **slice40_resonance** | | |
| `:instant` (control) | 0 / 0 | 6 |
| first order, τ 1e−6 … 1e−3 | **0 / 0** | 6 |
| first order, τ 5e−3 | **0 / 0** | 14 |
| first order, τ 2e−2 | **0 / 0** | 104 |
| second order, 30 Hz, ζ 0.7 | 0 / 1 | 26 |
| second order, 30 Hz, ζ 0.1 | **1051 / 942** | 351 |
| second order, 5 Hz, ζ 0.7 | **32 / 33** | **12233** |
| **slice26_radome** | | |
| `:instant` (control) | 0 / 0 | 2 |
| first order, τ 1e−6 … 2e−2 | **0 / 0** | 1–2 |
| second order, 30 Hz, ζ 0.7 | 0 / 0 | 3 |
| second order, 30 Hz, ζ 0.1 | **179 / 158** | 2 |
| second order, 5 Hz, ζ 0.7 | 0 / 0 | 170 |

**THREE RESULTS, AND THEY POINT DIFFERENT WAYS.**

1. ⭐ **§II.4's SIGNPOST IS NOT CONTAMINATED.** The entire first-order ladder fires the new clamp
   **zero** times on both wires, at every `τ_a`. The ladder measures actuator dynamics.
2. ⚠⚠ **BUT THE SECOND-ORDER RUNG DOES HIT IT, AT PHYSICALLY HONEST SETTINGS.** A 30 Hz, `ζ_a = 0.1`
   actuator — squarely inside §0.3's realistic band — pegs the stop on ~8 % of ticks on
   `slice40_resonance`. ⇒ **P7 is a live constraint on the second-order rung, not an end-of-slice
   assertion.** Any second-order arm must author `delta_max` wide enough that this reads 0, and
   MEASURE that it does, before its rms means anything. Decision 4 called this correctly.
3. ⚠⚠ **P7's TOOTH AS WRITTEN WOULD FAIL ON ITS OWN CONTROL, AND THE REASON IS THE ENDGAME.**
   §0.4 P7 says *assert `defl_sat == 0` on EVERY claimed arm* — but the SHIPPED baseline is not 0:
   `slice40_resonance` at `:instant` saturates on 6 ticks and `slice26_radome` on 2. Located in
   time, they are a single contiguous burst at the very end of the flight (**ticks 11061–11066 of
   12800**, and 9399–9400 of 12800) — the `r → 0` endgame spike that
   [[ewsim-missile-verifier-sampling]] already requires every miss/saturation scan to exclude. ⇒
   **P7 must inherit the arc's existing endgame exclusion rather than assert a flat zero**, and the
   quantity it asserts is *saturation before the endgame*, on both clamp sites.
   ⚠ The distinction has teeth: the `30 Hz, ζ 0.1` arm starts saturating at **tick 104**, not at the
   endgame — so the exclusion separates a contaminated arm from a clean one instead of hiding it.

⚠ And one arm is already disqualified by this table alone: **second order at 5 Hz, `ζ_a = 0.7` runs
the PRE-actuator limit on 12233 of 12800 ticks** on `slice40_resonance`. That arm is saturated, not
lagging, and nothing may be read off it — which is §0.3's *"absurd territory"* arriving as a number.

## §II.6 WHAT §II DECIDES

- **The placement is sound and the byte-identity risk is closed** — nine wires bit-exact across five
  distinct `:delta_cmd` paths, plus 7693/7693 including the absolute golden.
- **The seam needs no new key for `dt`** (`:dt_s`, already written in phase 1 and already read in
  phase 4).
- **P7 IS PROMOTED FROM AN END-OF-SLICE ASSERTION TO A PRECONDITION ON THE SECOND-ORDER RUNG**
  (§II.5): the new clamp fires on ~8 % of ticks at a realistic 30 Hz / ζ 0.1 actuator, and P7's
  `defl_sat == 0` must be re-worded to exclude the `r → 0` endgame or it fails on its own control.
- **Kill risks 1 (INERT) and 2 (REPARAMETERIZATION) are untouched by §I and §II and remain the two
  that can kill this slice.** P2 and P5 are next; P3, P4, P6, P7 follow them.

---

# §III — P2: THE INERT LADDER (2026-08-18)

**Run on the prototype-patched tree (`prototype_seam.patch` re-applied, plus two probe-only clamp
counters). Instrument: `p2_ladder.jl`, which reads slice 40's verifier metric to the digit — rms of
`omega_r` over the FIRST-DESCENDING band `500 ≤ r ≤ 3000` — and carries the contamination columns
without which an rms means nothing (advisor).**

⚠⚠ **THE WIRE IS `slice26_radome`, LED DELIBERATELY** (advisor). `slice40_resonance`'s ring **IS** a
second-order servo at 2.0 Hz / ζ = 0.1; putting a second second-order resonator in the same loop makes
attribution impossible — you cannot say which one moved. Slice 26 has no gimbal at all, so its ring is
purely the radome loop.

## ⭐⭐ §III.0 P2a — WHERE THE FIN COMMAND HAS ITS ENERGY (the blocking pre-probe, advisor)

Run BEFORE the ladder and on the **SHIPPED TREE** — `:instant` *is* the tree, so no patch is involved
and this is a property of the wire, not of the prototype. Detrended periodogram (mean + linear
removed: the turn is a ramp and its DC would swamp every band being compared) of `δ_cmd` /
`δ_yaw_cmd` over the same band. Probe: `p2_spectrum.jl`.

| wire / channel | dominant line | its share | >3 Hz | >20 Hz | >60 Hz |
|---|---|---|---|---|---|
| **slice26** pitch | **1.6488 Hz** | 0.551 | 0.187 | 0.111 | 0.074 |
| **slice26** yaw | **1.6488 Hz** | 0.499 | 0.264 | 0.136 | 0.084 |
| slice40 pitch | 58.81 Hz | **0.016** | 0.998 | 0.990 | **0.703** |
| slice40 yaw | 0.90131 Hz | 0.260 | 0.509 | 0.429 | 0.294 |

⭐ **SLICE 26's FIN COMMAND IS A LINE AT 1.65 Hz** — the radome ring itself (the wire's header records
1.7–2.1 Hz), carrying over half the energy, with ~81 % of the total below 3 Hz. The remainder is a
broadband floor and it is the seeker's own white noise: it never reaches the body rate, because the
airframe (short period 1.4 Hz) is already a far harder low-pass than any actuator could be.

⚠⚠ **AND SLICE 40's PITCH CHANNEL HAS NO LINE AT ALL** — its largest single bin is 1.6 % and 70 % of
its energy sits above 60 Hz. That channel is noise, not a lesson, and it is the second independent
reason (beside the stacked resonators) that slice 40 is the WRONG wire to lead P2 with.

⇒ At 1.65 Hz a 20–60 Hz actuator has gain 1.0002 and phase −2.7° … −8° (§I.5). **So the actuator
cannot act by attenuating the command; if it acts at all, it acts by PHASE.** That is §0.2's
mechanism, and it makes the ladder a test of exactly one thing.

## ⭐⭐ §III.1 THE PLAN'S OWN P2, RUN AS WRITTEN — AND IT READS A FALSE KILL

At the **authored** design `R = −0.10` the wire is already ringing:

| arm | rms_r | miss | clamp | defl_band | **aero (of 3639 band ticks)** |
|---|---|---|---|---|---|
| `:instant` (control) | 0.808626 | 2.179 | 0/0 | 0 | **2850 (78 %)** |
| 2nd, 30 Hz, ζ 0.7 | 0.811669 | 2.346 | 0/0 | 0 | 2712 |
| 2nd, 20 Hz, ζ 0.7 | 0.814515 | 2.284 | 0/0 | 0 | 2515 |

**0.4 % across the whole physically-honest band. Read as written, P2 fires the INERT kill.**

⚠⚠ **IT IS NOT A KILL, IT IS THE WRONG MEASURING POINT, AND THE CONTAMINATION COLUMN SAYS SO IN
NUMBERS** (advisor, pre-registered): **78 % of band ticks have the α_max clamp binding.** Slice 26's
own header says it in words — *"past onset the α_max clamp BOUNDS the cycle, so it is a PLATEAU, not
growth"* — and its own R ladder shows it (68.5× at −0.10 against 65.8 / 64.0 / 64.4 / 63.6 at
−0.12 … −0.30). **A clamped amplitude cannot move, so at the authored design the rms is insensitive
BY CONSTRUCTION.** Anything measured there measures the clamp.

⇒ **THE ACTUATOR EATS MARGIN, SO IT MUST BE MEASURED WHERE THERE IS MARGIN LEFT TO EAT** — i.e. on
the QUIET side of slice 26's own onset (`R_crit = −0.095`), not past it.

## ⭐⭐⭐ §III.2 THE LADDER AT `R = −0.09` — ONE STEP INSIDE THE STABILITY BOUNDARY

Same seed, same wire, same everything; `radome_slope` moved from the authored −0.10 to −0.09, which
slice 26 itself measured as **QUIET** (its own ladder: 1.1× the R = 0 baseline). `aero = 0` on the
control and on every arm down to 20 Hz ⇒ **these rms values are unclamped and free to move in both
directions.**

| ω_a (ζ_a = 0.7) | rms_r | vs `:instant` | step ratio | miss | clamp | defl_band | aero |
|---|---|---|---|---|---|---|---|
| `:instant` | 0.0234857 | 1.00× | — | 0.280 | 0/0 | 0 | 0 |
| 60 Hz | 0.0298658 | 1.27× | 1.27 | 0.420 | 0/1 | 0 | 0 |
| 40 Hz | 0.0369971 | 1.58× | 1.24 | 0.590 | 0/0 | 0 | 0 |
| 30 Hz | 0.0452563 | 1.93× | 1.22 | 0.958 | 0/0 | 0 | 0 |
| 20 Hz | 0.104459 | 4.45× | 2.31 | 0.508 | 0/0 | 0 | 0 |
| **15 Hz** | **0.613926** | **26.1×** | **⭐ 5.88** | 0.861 | 0/0 | 0 | 906 |
| 10 Hz | 0.754769 | 32.1× | 1.23 | 0.970 | 0/0 | 0 | 1370 |

⭐ **MONOTONE ACROSS THE WHOLE BAND, AND THE LARGEST SINGLE STEP IS 20 → 15 Hz AT 5.88×** — §0.4's
verdict rule applied unchanged, with no threshold chosen by me, and the ladder printed whole so a
reader can redraw the line. Past that step the `aero` column turns on (906, then 1370 ticks), i.e.
**the arm has entered the same clamped plateau §III.1 was stuck on** — so 26× and 32× are plateau
magnitudes and only the 60 → 20 Hz rows are free reads.

⚠ **THE 15 AND 10 Hz ARMS ARE BELOW A PHYSICALLY HONEST ACTUATOR** (§0.3: a real fin runs 20–60 Hz).
What ships is **the 20–60 Hz range, which is unclamped, monotone, and already 1.27× … 4.45×** — the
eruption below it is where the ladder is going, not what the slice is sold on.

## §III.3 THE ORDER IS THE LESSON — FIRST ORDER IS MILDER AT THE SAME CORNER

Matched by corner frequency, `τ_a = 1/(2π f)`, same wire and same `R = −0.09`:

| corner | first order (`τ_a`) | second order (ζ_a = 0.7) | ratio 2nd/1st |
|---|---|---|---|
| 30 Hz | 0.0368852 (τ = 5.305e−3) | 0.0452563 | **1.23×** |
| 20 Hz | 0.0405609 (τ = 7.958e−3) | 0.104459 | **2.58×** |

⭐ **AT THE SAME CORNER FREQUENCY THE SECOND-ORDER ACTUATOR COSTS MORE MARGIN THAN THE FIRST-ORDER
ONE, AND THE GAP WIDENS AS THE ACTUATOR SLOWS.** That is the slice's own title arriving as a number.

⚠ **AND THE MECHANISM IS CHECKED AGAINST §I.5's OWN MEASURED PHASE, NOT AGAINST A TEXTBOOK FIGURE**
(advisor). The comparison does NOT happen at the corner — it happens at the 1.65 Hz line (§III.0), far
below both corners, and §I.5 measured exactly those two cells there: **−4.63°** for 30 Hz / ζ 0.7
against **−3.47°** for `τ = 1/(2π·30)`. That is a **1.33× phase ratio against a 1.23× rms ratio** — the
two agree to 8 %, on numbers taken from two different probes on two different days. Quoting “90° vs
45° at the corner” would have been a textbook sentence about a place the loop never visits.

## ⚠⚠ §III.4 P4 IS ANSWERED, AND THE INHERITED SIGN WAS WRONG

§0.2 forbade predicting the direction. **Measured: the actuator DESTABILIZES.** Every rung, every
corner frequency, monotone, on an unclamped read. The lag that was *"silently doing stability work"*
on slices 34–40's feed-forward path does the opposite inside the main control loop — **same
component, same bound, opposite sign, because of where it sits in the loop.** §0.2's refusal to
inherit the sign was the right call, and the inversion is the headline it predicted it might be.

## ⚠⚠ §III.5 `ζ_a` IS NON-MONOTONE **AND** CONTAMINATED — IT IS NOT THE SLIDER

Slice 40 shipped `ζ` as its slider and §0.4 P6 expected it here. **It does not survive**, on the same
`R = −0.09` wire:

| arm | rms_r | vs ζ_a = 0.7 | clamp (pitch/yaw) |
|---|---|---|---|
| 30 Hz, ζ_a 0.7 | 0.0452563 | — | 0/0 |
| **30 Hz, ζ_a 0.1** | **0.39614** | **8.75× WORSE** | **115/242** |
| 20 Hz, ζ_a 0.7 | 0.104459 | — | 0/0 |
| **20 Hz, ζ_a 0.1** | **0.0418136** | **2.50× BETTER** | **36/75** |

**THE SIGN OF `ζ_a` APPEARS TO FLIP BETWEEN 30 Hz AND 20 Hz** — which would be the fifth occurrence of
the disqualifying class (`k` at 28, `ω_n` at 40, σ_seek at 25, the miss reversals at 20/22). ⚠⚠ **IT MAY
NOT BE CLAIMED AS ONE YET**, for the reason the next paragraph gives — see §III.6 item 4. And every lightly-damped cell
fires **the actuator's own new inelastic stop**, so neither number is a clean read at all: §II.5
predicted exactly this, and P7 is the reason it was counted. ⇒ **`ζ_a` is not the slider, and the two
ζ_a = 0.1 cells above must be re-run at a widened `delta_max` — WITH the `:instant` control re-run at
the same widened value** (advisor) — before either is quoted.

## §III.6 WHAT §III DECIDES SO FAR

1. **KILL RISK 1 (INERT) DOES NOT FIRE — but it very nearly did, for a reason that was a measurement
   artifact.** The plan's own P2, at the authored design, reads 0.4 %; the same ladder one step inside
   the boundary reads **1.27× … 4.45× over 60 → 20 Hz** and **5.88× at the next step down**.
2. **THE MECHANISM IS PHASE, AND IT IS MEASURED, NOT ASSUMED** (§III.0: the command is a 1.65 Hz line,
   where a 20–60 Hz actuator's gain is 1.0002).
3. **THE SLICE'S AXIS IS THE ACTUATOR'S CORNER FREQUENCY AGAINST THE LOOP'S OWN MARGIN, NOT AGAINST
   THE RING.** §0.3 named `ω_a/ω_sp`; the numbers say the live comparison is `ω_a` against the
   *parasitic* loop's margin, which is a third thing again.
4. **`ζ_a` IS UNRESOLVED AS THE SLIDER, NOT YET DISQUALIFIED** — ⚠ the correction is the advisor's and
   it matters: **both** ζ_a = 0.1 cells fire the actuator's own new clamp, so they are exactly the
   reads §III.5 itself labels unusable, and *a contaminated cell cannot disqualify anything.* The
   sign flip is a SIGNAL TO GO AND MEASURE, not a verdict. It is resolved only by re-running those
   cells at a widened `delta_max` **with the `:instant` control re-run at the same widened value**.
   `ω_a` — or the radome slope at a fixed `ω_a` — is the other candidate, and P6 covers both.
5. **STILL UNRUN AND STILL ABLE TO KILL: P5 (REPARAMETERIZATION).** A destabilizing pole is harder to
   fake with `(k_α, k_q)` than a damping one, but slice 39 died here and it is answered by a bound,
   not a tolerance.

⚠ **§III.6 IS SUPERSEDED IN TWO PLACES BY §§III.7–III.10, WHICH WERE RUN AFTER IT.** Item 1's ratios
are now known to be a **margin** effect that vanishes off the shoulder (§III.7); item 4's `ζ_a` is now
**disqualified on clean evidence** (§III.8), not merely unresolved. Items 2, 3 and 5 stand.


## ⭐⭐⭐ §III.7 THE SHOULDER CONTROL — THE ACTUATOR'S COST IS A **MARGIN** COST, AND IT VANISHES

⚠ **THE OBJECTION THIS ANSWERS, STATED FIRST** (advisor, and it BLOCKED the width of §III.2's claim):
every ratio in §III.2 is against a *single* `:instant` number at a *single* `R`, and that number
(0.0234857) is already **1.33× slice 26's own `R = −0.08` quiet read** (0.0175738). So `R = −0.09` is
not flat baseline — it is on the **rising shoulder** of the onset. Nothing in §III.2 could yet
distinguish *"a 30 Hz actuator costs 1.9×"* from *"`R = −0.09` is simply where anything costs 1.9×."*

Same seed, same wire, same band, same rungs; only `radome_slope` moves. `aero = 0` and `clamp = 0/0`
on **all nine** cells — every read below is unclamped.

| R | `:instant` | 30 Hz, ζ 0.7 | **ratio** | 20 Hz, ζ 0.7 | **ratio** |
|---|---|---|---|---|---|
| **−0.085** | 0.0174387 | 0.0173123 | **0.99×** | 0.0174495 | **1.00×** |
| **−0.088** | 0.0183264 | 0.0218027 | **1.19×** | 0.0304101 | **1.66×** |
| **−0.090** | 0.0234857 | 0.0452563 | **1.93×** | 0.104459 | **4.45×** |

⭐⭐ **THE RATIO COLLAPSES TO 1.00× AWAY FROM THE BOUNDARY AND GROWS AS THE BOUNDARY IS APPROACHED.**
At `R = −0.085` a 20 Hz actuator — half the honest band, and the arm that costs 4.45× three cells
later — is **free to four significant figures**. That is the alternative explanation refuted by
measurement rather than by argument: the effect tracks the LOOP'S MARGIN, not the measuring point.

⭐ **AND IT IS THE BETTER SENTENCE, NOT A NARROWER ONE.** The honest claim is not *"an actuator costs
you 1.9×"*; it is **an actuator's phase lag is FREE while you have margin and RUINOUS when you do
not** — which is the same shape as the arc's own `N·|R|` result (*you cannot buy N without buying
glass*) and reads in the same currency. It also predicts §III.1: at `R = −0.10` the loop has no margin
left to lose, so there is nothing for the actuator to take, which is a second and independent reason
the authored design reads 0.4 % — beside the α_max clamp.

⚠ **AND IT SETS THE DOMAIN A SHIPPED WIRE MAY BE AUTHORED IN.** A scenario authored at `R = −0.085`
would hand the student a dead button; one authored at `R = −0.10` would hand them a dead button for a
different reason. The live window is narrow and it is now measured, not guessed.


## ⭐⭐ §III.8 `ζ_a` RESOLVED — CLEAN AT 20 Hz, AND AT 30 Hz IT DOES NOT RING, IT **DESTROYS THE FLIGHT**

§III.5 could not claim anything because both lightly-damped cells fired the actuator's own new stop.
Resolved two ways at once. **(1)** The instrument now counts that clamp **IN BAND** (`clampBAND`),
differenced across band entry/exit — the cumulative counter cannot tell a band fire from the `r → 0`
endgame spike, and §II.5 result 3 is exactly that the endgame fires on the *shipped control* too.
**(2)** Each cell is re-flown at `delta_max` = 0.5 (authored) / 2.0 / 10.0, **with the `:instant`
control re-flown at each** (advisor).

| arm | δ_max | rms_r | miss | **clampBAND** | clampALL | aero |
|---|---|---|---|---|---|---|
| `:instant` | 0.5 / 2.0 / 10.0 | 0.0234857 (all three) | 0.280 | 0/0 | 0/0 | 0 |
| **20 Hz, ζ_a 0.1** | 0.5 | **0.0418136** | 0.353 | **0/0** | 36/75 | 0 |
| **20 Hz, ζ_a 0.1** | 2.0 | **0.0418136** | 0.353 | **0/0** | 83/104 | 0 |
| **20 Hz, ζ_a 0.1** | 10.0 | **0.0418136** | 0.353 | **0/0** | 72/83 | 0 |
| 30 Hz, ζ_a 0.1 | 0.5 | 0.39614 | 1.024 | **0/62** | 115/242 | 0 |
| 30 Hz, ζ_a 0.1 | 2.0 | 1.37674 | **846.4** | **145/144** | 355/352 | 2741 |
| **30 Hz, ζ_a 0.1** | 10.0 | **NaN — band empty** | **3552.6** | 0/0 | 169/183 | 0 |

⭐⭐ **THE 20 Hz CELL IS BIT-IDENTICAL ACROSS A 20× RANGE OF THE STOP** — 0.0418136 at δ_max 0.5, 2.0
and 10.0, with `clampBAND = 0/0` at all three. That is the strongest available proof of
non-contamination: **the metric is invariant to the threshold of the thing suspected of setting it.**
The cumulative counter's 36–83 fires are all in the `r → 0` endgame, which is what `clampBAND` was
built to separate and what §II.5 predicted.

⚠⚠ **AND THE 30 Hz CELL IS NOT "8.75× WORSE" — IT IS A LOST MISSILE.** As the stop is opened the
same arm goes 0.396 → 1.377 (miss **846 m**) → **the band never happens at all** (miss **3553 m**).
⇒ **at δ_max = 0.5 the mechanical stop was BOUNDING a divergence**, exactly as slice 26's own α_max
clamp bounds its limit cycle. The instrument reports `NaN`, not a beautifully quiet `0.00000` computed
from zero samples — slice 33's gate-2 finding, carried into this probe by design.

⇒ **`ζ_a` IS DISQUALIFIED AS THE SLIDER, NOW ON EVIDENCE.** At 20 Hz light damping is **2.5×
BETTER** than ζ_a = 0.7 (0.0418 vs 0.1045, both uncontaminated); at 30 Hz it loses the missile. The
sixth entry in the non-monotone class, and the most violent one in the project.

⭐ **AND THE MECHANISM IS ALREADY IN §I.5's TABLE, WHICH IS WHY THE FLIP IS NOT A SURPRISE ONCE
READ.** A lightly-damped second-order lag contributes almost **no phase** at low frequency
(§I.5: 30 Hz / ζ 0.1 is **−0.05°** at the 2 Hz ring, against **−4.63°** for ζ 0.7) — so on the
radome loop it is the *gentler* actuator, which is the 20 Hz result. But it carries a resonant peak
of `Q = 1/(2ζ_a) = 5` at its own frequency, and the α autopilot's rate feedback `k_q` is a direct
fast path from body rate to deflection. **Where that peak lands, a second and much faster loop closes
through it.** Two effects of one parameter, opposite in sign, in different frequency bands — which is
what a non-monotone knob always turns out to be.

⚠⚠ **THE TWO HALVES OF THAT SENTENCE DO NOT HAVE THE SAME STANDING, AND §0.2's OWN DISCIPLINE SAYS
SO** (advisor). The phase half is **MEASURED** (§I.5's table, taken before any of this was flown). The
`k_q` fast-path half was **INFERRED** — a hypothesis wearing a measurement's clothes. It is put to a
probe in §III.12 rather than left standing.

⚠ **AND `ζ_a = 0.1` IS AT THE EDGE OF HONEST FOR A FIN ACTUATOR ANYWAY** (real fin servos run
ζ ≈ 0.5–0.7). The divergence is real, but it is not a design a wire should be authored at, and the
shipped domain must exclude it rather than showcase it.

## ⭐⭐⭐ §III.9 THE THRESHOLD LADDER — THE ACTUATOR MOVES `R_crit`, IN THE ARC'S OWN CURRENCY

The measurement §III.7 pointed at. Slice 26's whole architecture is a **threshold** (`N·|R| ≈ 0.39`,
*you cannot buy N without buying glass*). If the actuator eats margin, it must move that threshold —
and unlike an rms at a fixed design, a threshold cannot be trapped on the clamped plateau.

Nine values of `R` × four arms, same seed / band / metric throughout. `*` marks a cell where the α_max
clamp binds in band, i.e. the plateau. **The whole grid is printed** (§0.4).

| R | `:instant` | 60 Hz | 30 Hz | 20 Hz |
|---|---|---|---|---|
| −0.0850 | 0.017439 | — | 0.017312 | 0.017449 |
| −0.0880 | 0.018326 | — | 0.021803 | 0.030410 |
| −0.0890 | 0.019713 | 0.022008 | 0.029819 | 0.047452 |
| −0.0900 | 0.023486 | 0.029866 | 0.045256 | 0.104460 |
| −0.0910 | 0.033742 | 0.045206 | 0.075717 | **0.595540\*** |
| −0.0920 | 0.048279 | 0.063109 | **0.588630\*** | 0.800370\* |
| −0.0930 | 0.206520 | **0.588670\*** | 0.798570\* | 0.788830\* |
| −0.0940 | 0.678990\* | 0.799620\* | 0.789920\* | 0.762500\* |
| −0.0950 | 0.822860\* | — | 0.762170\* | 0.754640\* |

**Largest single-step ratio per column** — §0.4's verdict rule, applied unchanged, no threshold chosen
by me:

| arm | largest step | between |
|---|---|---|
| `:instant` | 4.28× | −0.092 → −0.093 |
| 60 Hz | 9.33× | −0.092 → −0.093 |
| 30 Hz | 7.77× | **−0.091 → −0.092** |
| 20 Hz | 5.70× | **−0.090 → −0.091** |

⭐⭐ **THE ONSET WALKS TOWARD ZERO AS THE ACTUATOR SLOWS. A CHEAPER ACTUATOR NEEDS A BETTER RADOME.**

⚠ **AND THE MAGNITUDE IS QUOTED WITH ITS SENSITIVITY, BECAUSE THE CROSSING LEVEL IS A CHOICE**
(§0.4's rule). Log-interpolated crossing of three very different levels — the geometric mid-point
between floor and plateau, one well below it, one well above:

| crossing level | `:instant` | 60 Hz | 30 Hz | 20 Hz | shift `:instant`→20 Hz |
|---|---|---|---|---|---|
| 0.050 | −0.09202 | −0.09130 | −0.09019 | −0.08907 | 0.00296 (**3.2 %**) |
| 0.118 | −0.09261 | −0.09228 | −0.09122 | −0.09007 | 0.00254 (**2.7 %**) |
| 0.300 | −0.09331 | −0.09270 | −0.09167 | −0.09061 | 0.00271 (**2.9 %**) |

⭐ **MONOTONE IN `ω_a` AT EVERY LEVEL, AND THE SHIFT IS 2.7–3.2 % HOWEVER THE LINE IS DRAWN.** The
claim survives its own sensitivity analysis with the ordering intact and the magnitude stable in the
first two figures.

In the arc's own currency, at the mid-level, with `N = n_pn = 4`:

| arm | `R_crit` | `N·|R_crit|` |
|---|---|---|
| `:instant` | −0.09261 | 0.3705 |
| 60 Hz | −0.09228 | 0.3691 |
| 30 Hz | −0.09122 | 0.3649 |
| 20 Hz | −0.09007 | 0.3603 |

⭐ **CROSS-CHECK AGAINST A NUMBER NOBODY MEASURED FOR THIS SLICE:** the control column puts the
shipped wire's own onset at **−0.0926**, and `slice26_radome.yaml`'s header — written fifteen slices
ago on a coarser grid — records it as *between −0.09 and −0.095*. The two agree, and the control
column was not tuned to make them.

## ⭐⭐ §III.10 THE PAIR OF NUMBERS IS THE LESSON, AND NEITHER ALONE IS HONEST

The threshold moves only **~3 %**. At a fixed design the same actuator changes the ring by up to
**4.45×**. Both are true and they are the same fact seen twice: **the boundary is a cliff, so a
3 % move of the cliff is the difference between quiet and ringing for anything parked near it.**

⇒ The sentence the slice can carry: *an actuator's phase lag is free while you have margin and
ruinous when you do not* — and the shipped wire must be authored in the narrow window where that is
visible (§III.7: dead at −0.085, dead at −0.10, live between).


## §III.11 THE 60 Hz COLUMN COMPLETED — AND AN APPARENT COINCIDENCE THAT IS NOT ONE

⚠ **THE 60 Hz LADDER WAS TWO CELLS SHORTER THAN THE CONTROL'S**, so its 9.33× step ratio was computed
over a different ladder from `:instant`'s 4.28× (advisor). Filled: `R = −0.085` → 0.0174495,
`R = −0.088` → 0.0191260. **Every column now spans the same nine slopes, and nothing in §III.9 moves**
— the step-ratio cells, the three crossing levels and the ordering are all unchanged.

⚠ **AND A SIX-FIGURE COINCIDENCE WAS CHASED RATHER THAN QUOTED.** At `R = −0.085` the 60 Hz and 20 Hz
cells printed *the same six figures* (0.0174495), which for two different actuators is either luck or
a probe reading the same thing twice. Re-run at twelve:

| arm @ R = −0.085 | rms_r (12 sig. figs.) |
|---|---|
| `:instant` | 0.0174387438258 |
| 60 Hz, ζ 0.7 | 0.0174494566785 |
| 20 Hz, ζ 0.7 | 0.0174494**824393** |

⭐ **They part at the EIGHTH figure — luck, not a bug — and the check turns the §III.7 claim UP, not
down: off the shoulder a 20 Hz and a 60 Hz actuator are indistinguishable from each other to seven
figures, and both sit 0.06 % from an ideal one.** "Free" is not a rounding.

## ⭐⭐ §III.12 THE `k_q` FAST PATH — THE INFERRED HALF OF §III.8, PUT TO A PROBE

§III.8 explained the ζ_a = 0.1 divergence by the actuator's `Q = 1/(2ζ_a) = 5` resonant peak closing a
second loop through the α autopilot's body-rate feedback `k_q`. **That half was inferred.** Probe:
hold the diverging arm (30 Hz, ζ_a 0.1, `R = −0.09`, `delta_max = 10` so the stop cannot bound
anything) and walk `k_q` down from its authored 0.3.

| `k_q` | rms_r | miss | **actuator's own clamp (all)** | band | aero |
|---|---|---|---|---|---|
| **0.30 (authored)** | **NaN — band empty** | **3552.6** | **169 / 183** | 0 | 0 |
| 0.15 | 1.45385 | 6.776 | **0 / 0** | 3706 | 3579 |
| 0.05 | 3.21072 | 269.3 | **0 / 0** | 4030 | 3973 |
| 0.00 | 1.55694 | **0.278** | **0 / 0** | 3708 | 2734 |

⭐ **THE FAST-PATH CLAIM IS SUPPORTED, AND THE TELL IS THE CLAMP COLUMN, NOT THE rms.** At the
authored `k_q` the actuator drives itself into its own stop 169/183 times and the missile is lost by
3.5 km; **at `k_q` ≤ 0.15 the actuator stops hitting its stop entirely** and the flight is recovered
(6.8 m, and 0.28 m at `k_q` = 0). ⇒ what turns a lightly-damped actuator from *ringing* into *lost*
is the rate-feedback path, exactly as §III.8 guessed.

⚠⚠ **BUT IT IS SUPPORT, NOT AN ISOLATION, AND THE FILE SAYS SO RATHER THAN ROUNDING IT UP.** `k_q` is
not a spare parameter here: `slice26_radome.yaml`'s own header records that **`k_q` supplies ~98 % of
the loop's damping** (slice-20 FINDING 3, same airframe). So lowering it necessarily changes the
radome loop too — which is visible in the same table, where the **rms stays enormous and is
NON-MONOTONE in `k_q`** (1.45 → 3.21 → 1.56). Two things move when one number does. ⇒ **the sentence
that may be written is *the divergence travels with the `k_q` path*, not *the divergence is caused by
the `k_q` path alone*.**

## ⭐⭐ §III.13 P5 PRE-REGISTERED — THE DESIGN POINT, AND WHY A POINT FIT WOULD ANSWER THE WRONG QUESTION

Written before any gain is swept, because P5 is the risk that killed slice 39 and a free choice made
after the fact would manufacture its own answer.

**1. THE DESIGN POINT IS `R = −0.09`, FIXED HERE.** §III.7 made the old wording ambiguous: at
`R = −0.085` there is nothing to reproduce (every actuator is free to seven figures, §III.11), and at
the authored `R = −0.10` everything is on the clamped plateau (§III.1). **The shoulder is the only
place P5 is a real question**, and `R = −0.09` is slice 26's own published quiet cell — not a value
chosen after seeing a result.

**2. ⚠⚠ A POINT FIT WOULD ANSWER *YES* FOR A REASON THAT HAS NOTHING TO DO WITH AN ACTUATOR POLE**
(advisor, and this is the finding of §III.13). `k_q` is body-rate feedback — it is **part of the
radome loop itself**, supplying ~98 % of its damping (§III.12). So retuning `(k_α, k_q)` **moves
`R_crit` directly**, and "can some gain pair reproduce the arm's rms at `R = −0.09`?" will almost
certainly answer yes — by moving the effective margin, which is precisely the confounded-lever
objection that disqualifies `n_pn` and `rho` as knobs on slice 26's own wire.

**3. ⇒ THE BOUND IS STATED OVER THE `R_crit` **CURVE**, NOT OVER A POINT.** The question P5 must ask
is: *can any `(k_α, k_q)` on `:instant` reproduce BOTH the arm's rms at `R = −0.09` AND its whole
threshold ladder?* — because **a gain retune SHIFTS the threshold curve; an added actuator pole TILTS
it.** A pole changes how the loop's phase varies WITH frequency, and the ladder samples exactly that.

⭐ This is slice 38's *"`s` adds PHASE and scaling a slope cannot"* in the form this slice's own data
can carry, and the instrument for it already exists: fit the gain pair to the arm at `R = −0.09`,
then re-run the four-column ladder of §III.9 at that pair and compare **curves**.

**4. THE FALSIFIER, NAMED IN ADVANCE.** If a fitted `(k_α, k_q)` reproduces the arm's rms at
`R = −0.09` *and* tracks its `R_crit` across the ladder to within the 2.7–3.2 % the whole effect
spans, **the actuator is a reparameterization and slice 41 dies here** — the same death as slice 39,
and this file becomes the kill record.

