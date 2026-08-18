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

⚠⚠ **THE CONSEQUENCE FOR THE SLIDER, WHICH IS THE WHOLE POINT OF GETTING THE SIGN RIGHT.** If P6
clears `ζ_a` as the slider on slice 40's shape (`[0.05, 1.0]`), the **BINDING CELL IS THE CEILING,
`ζ = 1.0`, at 131.8 Hz** — not the ~303 Hz a walk at the floor would have reported. A domain authored
off the floor goes unstable when the student drags the slider *up*, which is the worst possible place
to put an instability. **Validate-at-LOAD must bound `fin_omega_hz` against the ζ the wire can
reach, not against a single number.**

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

1. **The authored domain is bounded by a CURVE `f_a ≤ h_max(ζ_a)/(2πΔt)`, and the honest ceiling is
   the OVERSHOOT one: 117 Hz at ζ = 1.** No resonance may be claimed above it.
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

## §II.5 WHAT §II DECIDES

- **The placement is sound and the byte-identity risk is closed** — nine wires bit-exact across five
  distinct `:delta_cmd` paths, plus 7693/7693 including the absolute golden.
- **The seam needs no new key for `dt`** (`:dt_s`, already written in phase 1 and already read in
  phase 4).
- **Kill risks 1 (INERT) and 2 (REPARAMETERIZATION) are untouched by §I and §II and remain the two
  that can kill this slice.** P2 and P5 are next; P3, P4, P6, P7 follow them.
