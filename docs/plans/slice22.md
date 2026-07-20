# Slice 22 — NONLINEAR `C_L(α)` / TRUE STALL: the ceiling the airframe sets (§11 Tier-A)

**Status: GATE 0 COMPLETE (2026-07-19) — 11 findings, TWO USER DECISIONS TAKEN.
GATE 1 COMPLETE (2026-07-20, `aero_curve.jl`, suite 3182 → 4015).
GATE 2 COMPLETE (2026-07-20, the wiring, suite 4015 → 4174) — 8 findings, THREE of which
CHANGE WHAT GATE 3 CAN SHIP. Gate 3 pending.** The aero arc's nearest and most load-bearing
named deferral — carried explicitly by slices 19, 20 and 21, and the one that closes the LEAK
bounding two shipped knobs.

---

## ⭐ GATE 2 — WHAT THE WIRING SETTLED (2026-07-20)

Probe: `M:\claud_projects\temp\slice22_gate2\` (`probe.jl`, `probe2.jl`). Shipped in
`airframe.jl` (the `_nl` siblings), `missile.jl` (`_stall_on`/`_stall_params` + the leading stall
closure + the readouts), `scenario.jl` (load validation), `aero_curve.jl` (`moment_slope`).

**⭐⭐ G1 — THE WIRING *IS* THE GATE-0 PROBE, REPRODUCED TO THE DIGIT.** Parked/absent miss
**125.14**, stall (α_stall 0.20) **240.37**, ceilings **471.44 → 269.39**, `Cma_post` 8 → **243.67
(+1.4%)**, the ω_sp sentinel first firing at **t = 3.436** (F11 measured 3.435 — one tick). The
F7 parking off-state reproduces too: α_stall ∈ {0.25, 0.30, 0.35} ALL give **125.14 exactly**,
with α_pk **0.2412** (F7's 0.2408). Pinned as a tooth — the slice-21 "reproduce STATUS to the
digit" discipline applied to a probe, since the whole design rests on numbers measured outside
the engine.

**⚠⚠ G2 — `k_drop` IS LOAD-BEARING FOR THE DEPARTURE HALF, AND GATE 0 NEVER ISOLATED IT.** The
probe ran `k_drop = 0.7`; that is now the shipped default (a 1.0 default silently moved the miss
to 278.11, a 16% shift, with every structural test still passing). **At 0.7, F10's AUTHORITY
CLIFF DOES NOT APPEAR at the balanced angles:** across `Cma_post` 0 → 8 with α_stall 0.20 /
α_break 0.28 / α_sat 0.60, α_pk moves only **0.286 → 0.379** and the autopilot HOLDS throughout.
At `k_drop = 1.0` the same sweep gives **0.31 → 0.64 → 1.59 → 3.02** — the cliff. ⇒ **F10's table
is NOT a property of the two angles alone**, and gate 3's departure scenario must author
`k_drop` deliberately. Do not copy F10's numbers onto a 0.7 wire.

**⚠ G3 — P6's `defl_sat == 0` IS ARM-SPECIFIC, NOT A SLICE-WIDE INVARIANT.** It holds on the LIFT
arm at every α_stall tested, and on the departure arm at `k_drop` 0.7. It **BREAKS** on the
departure arm at `k_drop` 1.0: `defl_sat` goes 0 → 7 → 322 → 418 → 613 across `Cma_post`
4/6/8/12. So the configuration that produces the cliff is also the one where δ_max starts
binding — exactly slice-19 FINDING 2's shape. Gate 3 must assert `defl_sat` per arm and, if it
ships the cliff, either show δ_max non-binding at its chosen point or NAME the contamination.

**⚠ G4 — THE α_stall KNOB DOMAIN IS BOUNDED BY MONOTONICITY (the 3rd occurrence of that
pattern).** At `k_drop` 0.7 the miss rises 125.14 → 552.02 as α_stall falls 0.35 → 0.12, then
**FALLS to 544.54 at 0.10**. The [[ewsim-df-ellipse-sigma-monotonicity]] / slice-19-ρ pattern
recurring: past the turn the missile stops being able to pull at all and the lesson REVERSES.
**Ship `af_alpha_stall ∈ [0.15, 0.35]`** — margin above the measured 0.12 turn, top = α_max =
the in-scenario linear twin (Decision 1).

**⚠ G5 — SEPARATION DRAG IS NEARLY INERT ON THIS ENGAGEMENT, AND MUST NOT BE SOLD AS A LEVER
(P4, answered).** Sweeping `K_sep` 0 → 12 moves the miss only **278.11 → 280.60** (~0.9%); the
ceiling floor moves 262.1 → 256.0. It is monotone and clean across the whole range — there is no
domain to bound — but it is a PHYSICALITY term, not a lesson knob. That is consistent with plan
§2 (it is MANDATORY because a stalled missile that decelerated LESS would be the opposite of the
lesson), and it means **`K_sep` is NOT a second slider**. The teeth carry it instead: exactly 0
below the stall, EVEN in α, along −v̂, and moving OPPOSITE to induced drag past the peak.

**⚠ G6 — "TIME WITH ω_sp CEILED" IS NOT A MONOTONE DEPARTURE INDICATOR (a readout subtlety F11
could not see).** The sentinel fires whenever α crosses α_break — including when the autopilot
comfortably recovers (it fires at `Cma_post` = 2, α_pk 0.29). Worse, the ceiled COUNT *falls* as
the departure gets more violent (1007 → 365 ticks as `Cma_post` goes 2 → 12 at `k_drop` 1.0),
because α blows straight past α_sat into F9's deep-stall RESTORING region where ω_sp is real
again. **That is the deep-stall bound showing up in the readout, and it is honest** — but a gate-3
headline of "seconds with no short-period" would read BACKWARDS. Headline the α_pk / held-vs-lost
verdict; use the sentinel as the *tell that the break was reached*, not as a severity measure.

**G7 / G8 — TWO BUGS, BOTH CAUGHT BY THE SLICE'S OWN `===` TEETH, BOTH IN CODE WRITTEN TO AVOID
EXACTLY THEM.** (G7) `aero_accel_limit`'s new `curve` arm computed the PARKED ceiling as
`(Q·S)·(Cla·α_max)` where the linear line is `((Q·S)·Cla)·α_max` — **1 ULP** (461.65182004425594
vs 461.651820044256), plan §4's multiply-grouping trap appearing INSIDE the function that
generalizes the formula, and this project's THIRD catch of that class. Fixed by routing both
off-states (`curve === nothing` AND `α_max < α_stall`) through the verbatim linear expression.
(G8) `separation_drag_accel` fell through with `C_Dsep = 0.0` and returned `Vec3(-0.0,-0.0,-0.0)`
below the stall, not the exact zero it documented — the `-0.0` trap, caught on the first run by
its own tooth. Fixed with an early exact-zero return. **Neither was reachable by an `≈` test.**

### THE TWO STRUCTURAL DECISIONS TAKEN AT GATE 2

- **`_stall_on` = `haskey(:af_alpha_stall) && :airframe === :pitch_coupled`** — the third conjunct
  is DELIBERATE (advisor), and it is the answer to this plan's own gate-2 warning that *the moment
  break reaches FURTHER than ρ(z) did*. `pitch_moment` is live on the `:point_mass` rotational path
  (`_integrate_airframe!`); without the conjunct a `:point_mass` wire would integrate θ/q through a
  BREAKING moment while pos/vel flew a linear-aero fiat accel — half the missile in one aerodynamic
  model and half in another, slice 21's `_atm_on` latent bug exactly. **`_integrate_airframe!` is
  untouched by this slice.**
- **STALL × THE EXPONENTIAL ATMOSPHERE IS A LOAD ERROR, NOT A BRANCH-ORDER OUTCOME** (convention 9;
  advisor). The stall arm LEADS `_integrate_coupled!`'s chain so the four prior arms stay textually
  verbatim (4 closures, not 8) — but that is only sound because a missile carrying both
  `alpha_stall` and `scale_height_m` is REFUSED at load. Otherwise it would silently fly a
  constant-ρ stall with its ρ(z) vanishing without a word.

⚠ **THE GATE-2 SKETCH BELOW IS STALE WHERE IT SAYS `LIVE_FIDELITY_MODES` GAINS `aero_curve`** — it
contradicts its own Decision 1 (advisor). No rung shipped, and `test_aero_curve.jl` ASSERTS the
absence, so adding one later breaks a test on purpose.

---

## ⭐ GATE 0 — WHAT IT SETTLED, AND WHAT IT OVERTURNED

Probes: `M:\claud_projects\temp\slice22_probe\` (`probe.jl`, `p0`, `p0b`, `p1`, `p2`),
**full numbers in `FINDINGS.md` there.** Read that file before gate 1 — this is the summary.

**THE CORE 3-PIECE SLICE IS VALIDATED and its headline is EXACT:**

    ⭐ at FIXED Q the linear→stall ceiling ratio is IDENTICALLY α_stall/α_max
       (Q, S, C_Lα, m ALL CANCEL) — measured 471.44 → 269.39 = 0.571428571 vs
       0.571428571, Δ ≤ 1.1e-16. Slice 21's ρ-factor identity in a NEW LETTER.

Engagement consequence: miss **125.14 → 240.37 (1.92×)**, `aero_sat` 26.3%, `defl_sat == 0`.
⚠ On SLICE 19's geometry (target 6 km, `a_lat = 200`), NOT slice 20's — F1 found slice 20's
engagement inert (α_pk 0.085, all arms identical to the centimetre). `a_lat` is a narrow window:
at 400 both arms miss by >1300 m (the slice-21 REACH WALL recurring).

### ⚠ DECISION 1 (USER, 2026-07-19) — **KNOB, NOT RUNG. The plan's §"rung justification" is DEAD.**

The plan asserted *"linear is `α_stall → ∞`, a LIMIT POINT ⇒ RUNG"* and told gate 0 to verify it.
**It does not survive (F7).** The achieved α SELF-LIMITS to ~0.24 across the whole viable
geometry family (the linear arm's α_pk capped at 0.2408 even at `a_lat = 400` — past that is the
reach wall, not higher α). So α_stall parked anywhere ≥ ~0.25 is linear-in-effect **over all
reachable states**, not by coincidence of one scenario — measured: at α_stall = 0.25 the miss is
the linear miss to the printed digit.

**α_stall MOVES A CORNER and the corner can be parked out of reach — exactly slice 16's `af_cma`
(park it stable, nothing happens), and the OPPOSITE of slice 21's `H`, which cannot be parked
because altitude is the swept variable.** Also matches precedent: separation drag is a new
ADDITIVE term, and slice 20 already made a new additive term (`af_k_induced`) a knob.

⇒ **ONE knob `af_alpha_stall`, presence-gated (the slice-20 shape).** NO `:aero_curve` fidelity,
NO `AERO_CURVE_MODES`, NO `LIVE_FIDELITY_MODES` edit, NO `set_fidelity`, NO button — and so the
one-button rule's "4th occurrence" in `_setup_spatial_fid_btn` **does not arise**. Likely ZERO
new client code (slice 19's aero strip already plots the ceiling; it just starts lower —
slice 20's precedent exactly). **The top of the knob's own range IS the in-scenario linear
twin**; key ABSENCE stays the bit-exact prior-slices path.

⚠ **THE USER'S CLARIFICATION — "knob now, rung if it EARNS it."** The door stays open, but only
for the `Cm(α)` break: a slope SIGN FLIP is a distinct code path with **no parking escape**,
whereas a corner angle always has one. If the break never ships, slice 22 is a knob slice
permanently. **Do not reopen the rung question for the lift curve** — it was measured and lost.

⚠ And record the meta-point: **the discriminator is a CONVENTION, not a law.** A rung could be
shipped anyway for the crisp A/B — but it would have to be named a DELIBERATE DEVIATION. The
discriminator cannot be cited *in support* of a rung here, because it says the opposite.

### ⚠ DECISION 2 (USER, 2026-07-19) — **THE FOURTH PIECE IS REFRAMED: RELAXED STATIC STABILITY.**

Not "the airframe departs" (the framing the slice was grown for on 2026-07-19 morning), and not
dropped either. **What gate 0 actually found is a better lesson than the tumble**, and it is
what ships:

    ★ A STATICALLY UNSTABLE AIRFRAME IS PERFECTLY FLYABLE — UNTIL THE AUTOPILOT
      RUNS OUT OF AUTHORITY. The THRESHOLD is the lesson, not the tumble.

MEASURED (F10, at the balanced two angles α_stall 0.20 / α_break 0.28, α_sat 0.60) — a **SHARP
cliff between `Cma_post` 4 and 8**, with the controlled-collapse window UNCHANGED across it:

| Cma_post | α_pk | verdict | COLLAPSE | DEPART | dsat |
|---|---|---|---|---|---|
| 4.0 | 0.3103 | autopilot **HOLDS** | 0.877 s | 0.717 s | 0 |
| 8.0 | **2.7779** (159°) | autopilot **LOSES** | 0.877 s | 0.713 s | 0 |

This is real fly-by-wire physics (every modern fighter is statically unstable and flies fine),
it makes `Cma_post` the natural second slider — **the cliff is what you drag across** — and it
absorbs F5 (the "nominal, autopilot-held departure" that read as a disappointment is now HALF
THE LESSON, not a failure). It also keeps slice 16's callback intact and STRENGTHENS it: slice 16
authored the unstable case; here the airframe *flies into* it **and the autopilot fights back**.

⚠ **THE MISS IS NOT THE METRIC FOR THIS HALF, AND THAT IS FINAL (F4, re-confirmed at F10).**
Even at full tumble the miss moves **240.37 → 243.67 = +1.4%** — a missile that departs 0.7 s
before CPA keeps its momentum and lands in much the same place. Headline the THRESHOLD
(held-vs-lost) and the ω_sp sentinel; the miss corroborates at most. Any lesson line built on
the miss would actually be measuring the LIFT collapse and mis-attributing it.

### THE OTHER GATE-0 RESULTS THAT CHANGE THE BUILD

- **F3 ⭐ TWO ANGLES, NOT ONE — the plan's "RECOMMEND one angle" is REFUTED.** With
  `α_break == α_stall` the CONTROLLED lift-collapse window has **literally ZERO width** (0.000 s):
  the airframe goes unstable at the same α where lift peaks, so it departs before "pull harder,
  get less lift" is ever visible — and that regime is *what true-drop was chosen for*. Measured
  optimum **α_break = 0.28** (collapse 0.877 s, then departure 0.717 s). The window is bounded on
  BOTH sides: below ~0.22 the collapse vanishes, at ≥0.32 the break is never reached.
- **F9 — a FIFTH forced piece: the DEEP-STALL BOUND `α_sat`.** An unbounded divergent moment ran
  α to **470 rad** — a numerical artifact, not a tumble. `Cm(α)` needs a THIRD slope (restoring
  again above α_sat; physically the post-stall body acts as a flat plate), which bounds the
  divergence into a second high-α equilibrium = **deep-stall lock-in, a real named phenomenon**.
  It barely moves the miss ⇒ it is a PHYSICALITY/crash-safety fix, not a lesson lever. **Without
  it a real tumble and a bug are indistinguishable.**
- **F11 — slice 16's ω_sp NaN sentinel FIRES IN FLIGHT for 0.747 s**, first at t = 3.435. Built
  for an AUTHORED `Cmα ≥ 0`, never fired mid-run in the project's history. ⚠ NOT yet walked
  through `_finite`/`FINITE_CEIL` to the wire — **that stays a GATE-2 item** (convention 6).
- **F2 / P6 — settled GOOD:** `α_max > α_stall` (plan §3's inversion of slice 19) reaches stall
  by the COMMAND path **at the SHIPPED gains** (k_α 1.0, k_q 0.3), NOT via the FINDING-14 leak;
  and `defl_sat == 0` in the LOS-gated window in every non-blowup arm.

**Candidate curve shapes as measured (gate 1's spec):** `C_L` ODD, slope `Cla` below α_stall and
`−k_drop·Cla` above, `cl_peak = Cla·α_stall` closed-form. `C_Dsep` EVEN, `K_sep·max(0,|α|−α_stall)²`,
exactly 0 below. `Cm_α` ODD with THREE slopes: `Cma` / `Cma_post` / `Cma` (the F9 bound).

**Still unrun from the original probe list:** P4 (`K_sep` domain — every gate-0 run above had
`K_sep = 0`), P5 (the convention-9 separation from slice 20's induced spiral), P7 (the causation
counterfactual). ⚠ P7 needs re-scoping: with the reframe there are now TWO causal claims (the
lift ceiling, and the autopilot-authority threshold) and they need separating.

---

Slices 19–21 gave cap #4 (`a_max_aero`) three movers, and **all three moved `Q`**:

| slice | mover | mechanism |
|---|---|---|
| 19 | the ENGINEER | the `rho` knob — dialling a flight condition by hand |
| 20 | the MISSILE, by TURNING | induced drag bleeds V → Q falls |
| 21 | the MISSILE, by WHERE IT FLIES | `ρ(z) = ρ₀·exp(−z/H)` — climb → Q falls |

**Slice 22 moves the OTHER factor.** `a_max_aero = Q·S·C_Lα·α_max/m` has always assumed the lift
curve is a straight line out to `α_max` — that the airframe will keep trading α for lift forever.
It will not. Past `α_stall` the flow SEPARATES: **`C_L` peaks and then FALLS**, and the drag that
was negligible in attached flow RISES steeply. The ceiling is not `C_Lα·α_max`; it is the curve's
own INTERIOR PEAK, `C_L(α_stall)`, and no amount of Q buys past it.

> **THE LESSON, IN ONE SENTENCE.** Every prior cap in this project is a MAGNITUDE that saturates —
> pull harder, get no more. This one is a **DERIVATIVE THAT CHANGES SIGN**: past the peak, pulling
> HARDER turns you LESS *and* costs you MORE. That reversal is new in the suite, and it is why the
> user chose the true-drop curve over a saturating one (see "The curve-form decision" below).
>
> ⚠ **TWO REVERSALS, AND THE SECOND ONE COST A DESIGN DECISION — see §5.** A third advisor pass
> caught that a linear `pitch_moment` CANNOT depart, so "departure"/"pitch-up" was overclaimed
> (the slice-20 "positive feedback" / slice-21 "high altitude" class, 3rd occurrence). **The user
> chose to GROW THE SLICE**: `Cm(α)` now breaks too, so BOTH the control loop AND the attitude
> reverse, and the language is earned — **but ONLY under `:stall` on a scenario authoring the
> break.** Slice-16–21 wires keep a linear moment and cannot depart. No global find/replace.
>
> 🚫 **REFRAMED AT GATE 0 — DECISION 2.** The break SHIPS, but the lesson is **RELAXED STATIC
> STABILITY** (*an unstable airframe is flyable until the autopilot runs out of authority* — the
> measured `Cma_post` 4→8 cliff), NOT "it departs". And **the MISS is not the metric for that
> half** (+1.4% even at full tumble). "Departure"/"pitch-up" describe the far side of the cliff
> only. Also: no `:stall` rung exists any more — see Decision 1.

---

## Read these FIRST — the four things settled while planning

### 1. `alpha_command` IS NOT TOUCHED — and that is the design, not a shortcut

The lesson lives ENTIRELY on the **achieved** side. The inner autopilot inverts
`a_perp → α_cmd = a_perp·m/(Q_eff·S·C_Lα)` on the **LINEAR** `C_Lα`, and it KEEPS DOING SO.

This is right on three counts, not one:
- **It is realistic.** An autopilot carries an internal linear model of its airframe. A linear
  inversion that OVER-commands α as the real curve goes concave is precisely slice-19's
  command-vs-achieved gap MADE PHYSICAL — the same lesson, one layer deeper.
- **It sidesteps the MULTIVALUED INVERSE.** Past the peak two α give one `C_L`. Inverting the real
  curve would author a genuine ambiguity/crash surface into a first stall slice. Leaving the
  inversion linear means the ambiguity is never constructed. (⚠ It is therefore INHERITED BY
  WHOEVER LATER WANTS A STALL-AWARE AUTOPILOT — name it as a deferral, do not pretend it is gone.)
- **It shrinks the blast radius to the two functions that carry the physics.**

⚠ **`_AIRFRAME_DENOM_FLOOR`, `_AIRFRAME_Q_FLOOR`, the `C_Lα<0` self-consistency (slice-19 FINDING 9)
and the `sat` round-trip all live in `alpha_command` and are UNCHANGED.** Do not "helpfully" make
`sat` stall-aware — `sat` means *the α_max clamp bound*, and under this slice α_max is deliberately
NOT the binding limit (see #3). A new, separately-named flag reports stall.

### 2. THE DRAG IS ADDITIVE, NOT A CORRECTION — slice 20's term is CORRECT past stall

The tempting-but-wrong framing (caught at the advisor pass, and it would have oversized the slice):
*"`C_Di = K·C_L²` goes invalid past stall, so slice 20's headline term must be fixed."*

**It does not, and it must not be.** Induced drag genuinely DOES fall with lift² — slice 20's term
falling past the peak is CORRECT PHYSICS. What is missing is **SEPARATION DRAG**, which was
legitimately ≈0 in attached flow (which is why slices 17–21 never needed it) and rises steeply past
stall. So:

    total aero drag = induced (slice 20, VERBATIM, correctly FALLING past the peak)
                    + separation (NEW, gated, RISING — dominates past the peak)

`induced_drag_accel` is **not edited except for its shared `C_L`** (see #4). Byte-identity is
preserved the way slices 20/21 preserved it: a presence-gated branch, the else-arm textually
verbatim, and **never** a coefficient→0 that is trusted to vanish (the `-0.0` trap).

**AND IT IS NOT A SECOND LESSON.** Lift-collapse + drag-rise **IS** what stall is — one rung, one
phenomenon, one event: *pull past the peak → less lift AND more drag → you depart.* Convention 9 is
satisfied because there is one toggled fidelity, not two. A stalled missile that decelerated LESS
would not be an approximation, it would be the OPPOSITE of the lesson — which is exactly why the
separation term is **MANDATORY, NOT OPTIONAL**.

**Shape of the separation term** — it **KEYS ON α, NEVER ON `C_L`** (past stall `C_L` FALLS while
the drag must RISE; keying it on `C_L` would make the drag fall too, reproducing the very error):

    C_Dsep = K_sep · (max(0, |α| − α_stall))²        (lumped one-coefficient — the K / cd_area precedent)
    a_sep  = −(Q·S·C_Dsep / m)·v̂                     (ALONG −v̂, like induced — slows, never turns)

**EVEN in α**, mirroring `induced_drag_accel`'s even-in-α tooth. So the parity table — which ships
as a consistency tooth — is: **`C_L` ODD, both drag terms EVEN.** Up and down stall identically.

### 3. ⚠ THE LARGEST CONSEQUENCE OF THE TRUE-DROP CHOICE: `α_max > α_stall`, WHICH INVERTS SLICE 19

**This blocks the scenario, and it must not be written around.**

To reach post-stall the ACHIEVED α must exceed `α_stall`. There are exactly two routes:

- **Via the LEAK (`α_max ≤ α_stall`)** — the command never reaches stall, so departure could only
  happen through slice-19 FINDING 14's achieved-α overshoot above the clamp. **REJECTED.** It is
  gain-dependent, fragile, and **CIRCULAR**: closing that leak is a stated payoff of this very
  slice. A headline built on the leak evaporates the moment the leak closes.
- **Via the COMMAND (`α_max > α_stall`)** — ⭐ **THE DESIGN.** The autopilot COMMANDS INTO STALL.
  `α_max` becomes a soft high limit and **THE PHYSICS SETS THE WALL.**

**This INVERTS slice 19's relationship and the plan says so out loud.** In slice 19 `α_max` was the
BINDING clamp and `a_max_aero` was that clamp expressed as an accel. Here `α_max` is deliberately
NOT binding; the ceiling is the CURVE'S INTERIOR PEAK. Concretely:

    slice 19–21:  a_max_aero = Q·S·|C_Lα|·α_max / m           (linear extrapolation to the clamp)
    slice 22:     a_max_aero = Q·S·C_L_peak     / m,   C_L_peak = max_{|α| ≤ α_max} |C_L(α)|

⚠ **`aero_accel_limit` now computes an INTERIOR MAX, not a value at the clamp.** For the shipped
curve `C_L_peak = |C_L(α_stall)|` in closed form (do NOT ship a numeric search — a closed-form peak
is the anchor the tests pin). Presence-gate it: key absent ⇒ the slice-19/20/21 formula VERBATIM, so
those three slices stay byte-identical and this is a NEW RUNG'S number, not a regression in theirs.

⭐ **The headline tooth this makes possible, which slices 19–21 STRUCTURALLY COULD NOT WRITE:**
**hold `Q` EXACTLY constant across the rung flip and show the ceiling still drops.** Same ρ, same V,
same S, same mass, same α_max — only the curve changed. That is what proves slice 22 moved the
OTHER factor and is not "slice 21 again with a different letter."

⚠ **IT MUST BE A SAME-INPUTS FORMULA COMPARISON, NOT A LIVE RUN-VS-RUN** (advisor): feed IDENTICAL
`(V, ρ, α_max)` to `aero_accel_limit` under linear vs stall params. As a two-run comparison it
CONFOUNDS ITSELF — separation drag makes V diverge between the arms, so `Q` is not actually equal
and the tooth stops testing what it claims. (The slice-20 "matched on ΔV" discipline, inverted:
there the twin had to be matched empirically; here the whole point is that no run is needed.)

### 5. ⭐ THE `Cm(α)` BREAK — THE SLICE GREW HERE, BY USER DECISION (2026-07-19)

**How this section came to exist.** It originally said the OPPOSITE: that `pitch_moment` stays
linear, so there is no departure and no pitch-up, and that "departure"/"pitch-up" had to be scrubbed
from every lesson line (the third advisor pass caught the overclaim with those words already written
into this plan AND into the question the curve form was chosen from). **The user was shown that
finding and chose to GROW THE SLICE rather than soften the lesson.** The reasoning below is kept
because it is exactly what the moment break must now overturn — it is the specification.

**WHY A LINEAR MOMENT CANNOT DEPART** (the structural argument — every path closes the SAFE way):
- `Cmα < 0` held THROUGH stall ⇒ there is ALWAYS a restoring moment. The fin trims α to α_max and is
  **stable there**.
- As V bleeds, `Q` falls ⇒ ω_sp goes sluggish but stays REAL (no sign change).
- As V bleeds, `q̄ = q·d/(2V)` **RISES** ⇒ **MORE** pitch damping, not less.

⇒ Under a linear moment, attitude never departs no matter what lift and drag do. **Pitch-up is a
MOMENT-BREAK phenomenon**: it requires `Cm(α)` itself to break. So the slice takes a **FOURTH forced
piece**, on top of the three the true-drop curve already forced:

    Cm(α) = Cmα·α  BELOW the break, and LOSES ITS RESTORING SLOPE ABOVE it
            (∂Cm/∂α → 0 and then POSITIVE — the static margin is consumed)

⭐ **THE CALLBACK THAT MAKES THIS THE RIGHT CALL — SLICE 16'S TUMBLE, NOW SELF-INFLICTED.** Slice 16
taught the static-stability sign lesson with `af_cma` as an **AUTHORED** value: *`Cmα < 0`
weathervanes, `Cmα > 0` TUMBLES.* An engineer typed the unstable case. **Slice 22 makes the airframe
DRIVE ITSELF INTO THAT REGIME BY FLYING THERE** — the same tumble, now a CONSEQUENCE. This is the
same "who moves it" progression the ceiling got across 19/20/21, applied to STABILITY instead of
to the ceiling, and it is why the moment break is worth its cost.

⭐ **AND `short_period_freq`'s SENTINEL FINALLY FIRES IN FLIGHT.** Slice 16 built the NaN-guard
(`ω² < 0 ⇒ NaN`, `_finite`-clamped to `FINITE_CEIL`) for an authored `Cmα ≥ 0`, and **it has never
fired mid-run in the project's history.** Under a moment break it fires **DYNAMICALLY, at the
moment of departure** — ω_sp is the readout that says "there is no longer an oscillation to have."
That makes it a headline-grade telemetry channel, not a defensive branch. ⚠ Verify the whole
`_finite`/wire path actually survives a mid-run NaN (convention 6) — it has never been exercised
this way.

**BOTH REVERSALS NOW SHIP, AND THEY ARE ONE EVENT — name them in order:**
1. **The CONTROL-loop reversal** (present even without the moment break): too little g → command
   MORE α → past the peak get LESS lift → command MORE → peg at α_max with `C_L(α_max) < C_L_peak`.
2. **The ATTITUDE reversal** (what the break buys): past the break the airframe no longer returns.
   `trim_alpha` ceases to have a stable solution, ω_sp goes imaginary, and the missile departs.

⚠ **NOW "DEPARTURE" AND "PITCH-UP" ARE EARNED LANGUAGE — but only under the `:stall` rung on a
scenario that authors the break.** The `:linear` arm and every slice-16–21 wire still have a linear
moment and CANNOT depart; the slice-21 "high altitude" precedent governs exactly (the caveat lifts
where the physics lives, and nowhere else). **No global find/replace.**

**THE BLAST RADIUS THIS ADDS — `pitch_moment` IS THE FUNCTION SLICES 16–21 ALL BUILD ON:**
- Called from `airframe_step` (slice 16), `_integrate_airframe!` (the `:point_mass` rotational path)
  AND `_integrate_coupled!`'s closure. **Every call site must reach the linear arm TEXTUALLY
  VERBATIM when the break key is absent** — the #4 multiply-grouping trap applies to
  `Q * p.S * p.d * (p.Cma * alpha + ...)` with full force. Do NOT refactor the sum.
- `short_period_freq` and `trim_alpha` both read `p.Cma` and are **LOCAL LINEARIZATIONS** — under a
  break they are valid only BELOW it. Either evaluate them at the LOCAL slope `∂Cm/∂α|α` or document
  them as below-break-only. **Decide at gate 0; do not leave it implicit** (they are shipped
  readouts, and slice 21's `_atm_on` bug was exactly a readout disagreeing with the integrator).
- **Is `α_break` the SAME angle as `α_stall`?** Physically they are related but NOT identical (a
  real airframe's moment break and lift peak differ). **Gate-0 decision, and it is one-lesson-vs-
  knob-sprawl:** defaulting `α_break = α_stall` keeps ONE authored angle and ONE event
  (convention 9); a second parameter is more honest but doubles the knob surface and lets the two
  reversals separate in time. **RECOMMEND one angle, with the difference as a §1 named
  approximation** — but let P2/P3's measured timing decide.
  🚫 **SUPERSEDED — GATE 0 F3 REFUTED THE ONE-ANGLE RECOMMENDATION.** One angle gives the
  controlled lift-collapse window **ZERO width**, deleting the very regime true-drop was chosen
  for. **TWO ANGLES, α_break = 0.28** (measured optimum; window bounded on both sides). The
  measurement overruled exactly as this paragraph invited it to.

**Departure RECOVERY becomes a first-class question, not a footnote** (gate-0 P3, now upgraded):
recoverable vs terminal are DIFFERENT lessons and the headline must match whichever happens. With a
genuine break, terminal is the likely outcome — and if so, **the miss is no longer the metric**
(a tumbling missile's miss distance is arbitrary). Expect the headline to be a DEPARTURE-ONSET
quantity (the α or the time at which ∂Cm/∂α crosses zero, and the ω_sp sentinel firing), with the
miss corroborating at most. Slice 20's "lead with the pure-quantity metric" discipline.

### 4. THE BYTE-IDENTITY TRAP IS A MULTIPLY GROUPING — do NOT refactor the off-arm

`lift_accel` today computes `L = Q * p.S * p.Cla * α`, i.e. `((Q·S)·Cla)·α`. Routing the off-state
through a shared helper as `L = Q * p.S * _cl(α)` gives `(Q·S)·(Cla·α)` — **a different multiply
grouping, a possible 1-ULP shift**, and the absolute golden + determinism tests are bit-exact. This
project has already caught this class TWICE (`√(snr/2)` vs `√snr·√½`).

**Each off-arm stays TEXTUALLY VERBATIM; the stall path branches AROUND it.** Same for
`induced_drag_accel`'s `C_L = p.Cla * α`.

---

## The curve-form decision (settled by the user, recorded with its cost)

Two forms were costed. **SATURATING** (C_L → an asymptote, never drops) was the advisor's and my
recommendation: one lesson, monotone inverse, no separation term needed, smallest blast radius.
**TRUE-DROP** (C_L peaks, then falls) was **the user's decision**, and it is the better lesson —
the CONTROL-LOOP sign reversal is genuinely new in the suite and a saturating curve cannot produce
it at all.

⚠ **THE QUESTION IT WAS CHOSEN FROM OVERSOLD IT — AND THE USER CLOSED THE GAP BY GROWING THE
SLICE (RESOLVED 2026-07-19).** That question described true-drop as buying "the dramatic departure/
**pitch-up** failure mode," which a linear `pitch_moment` cannot deliver (§5). Offered the choice
between scrubbing the language and adding a `Cm(α)` break, **the user chose the break.** So the
slice is now FOUR forced pieces, not three:

    1. the stall curve          C_L peaks at α_stall, then FALLS
    2. separation drag          keyed on α, EVEN, rising past stall
    3. α_max > α_stall          the command reaches stall; the physics sets the wall
    4. the Cm(α) break          the moment loses its restoring slope ⇒ real departure

**Size it honestly at gate 2 and do not let it creep further.** Piece 4 is the one that touches a
function slices 16–21 all build on; the other three are additive in new code.

**Its true size, made visible here so gate 2 is not a surprise:** true-drop honestly done =
**stall curve + separation drag + the inverted clamp relationship (#3)**. Every one of those three
is FORCED by the choice, none is optional, and all three are additive and gated.

🚫 **SUPERSEDED BY GATE 0 — DECISION 1. The paragraph below is WRONG and is kept only to show
what was tested.** It predicted `α_stall → ∞` was a limit point ⇒ RUNG; F7 MEASURED the
off-state at a finite in-domain α_stall ≈ 0.25 ⇒ **KNOB**. The `⚠ VERIFY THIS AT GATE 0` note
below did its job — the verification FAILED. Do not re-derive; read Decision 1.

**The rung justification is UNCHANGED by the form choice** — apply slice 21's discriminator
(recorded in `atmosphere.jl`'s header, do not re-derive): *is the off-state (a) a distinct code path
and (b) NOT knob-reachable?* The linear curve is **`α_stall → ∞`** — a LIMIT POINT, not a slider
position. ⇒ **RUNG**, `fidelity.aero_curve = linear | stall`.

⚠ **VERIFY THIS AT GATE 0, DO NOT ASSUME IT.** If a FINITE `α_stall` parked above the operating
range is linear-in-effect, the off-state IS knob-reachable and this is a **KNOB** (the
`af_k_induced` shape), not a rung — and the rung justification evaporates. The `H ≈ 1.4e6` probe in
slice 21 is the template: show what finite `α_stall` would be needed for <1% deviation over the
achieved-α range, and show the scenario cannot reach it.

---

## Gate 0 — probes to run BEFORE writing any library code

The empirical-first discipline (convention 10). Each probe is throwaway; the NUMBERS come back and
the design may change (slices 19, 20 and 21 were all changed by their gate 0).

- **P1 — the rung/knob discriminator (#4 above).** What finite `α_stall` makes the stall curve
  indistinguishable from linear over the achieved α range? Confirm it is out of any sane slider
  domain. **If this fails, the slice is a KNOB and the plan is rewritten.**
- **P2 — does the missile actually reach post-stall α, via COMMAND?** With `α_max > α_stall`, sweep
  the engagement and measure the achieved-α histogram. Post-stall excursion must be reached by the
  COMMAND path with `k_α`/`k_q` at their SHIPPED authored values — **and must NOT depend on the
  FINDING-14 leak** (verify by checking it survives a gain reduction).
- **P3 — is the departure RECOVERABLE or TERMINAL?** Both are shippable lessons but they are
  DIFFERENT lessons and the headline must match the one that happens. With a genuine `Cm(α)` break
  TERMINAL is likely — and **if it is terminal the MISS IS NOT THE METRIC** (a tumbling missile's
  miss is arbitrary). Expect a DEPARTURE-ONSET headline instead (the α / the time at which
  `∂Cm/∂α` crosses zero; the `short_period_freq` sentinel firing) — slice 20's "lead with the
  pure-quantity metric" discipline.
- **P3b — `α_break` vs `α_stall`: ONE angle or TWO?** Measure whether the two reversals want to
  separate in time. RECOMMEND one authored angle (convention 9, one event) with the difference as a
  §1 approximation; let the measurement overrule that if the single angle makes either reversal
  invisible.
- **P3c — does the mid-run NaN survive the wire?** `short_period_freq`'s `ω² < 0 ⇒ NaN` sentinel has
  NEVER fired mid-run in this project (slice 16 built it for an AUTHORED `Cmα ≥ 0`). Walk the whole
  `_finite`/`FINITE_CEIL` path with a departure in progress — convention 6, and a genuinely
  untested branch.
- **P4 — `K_sep` domain, MEASURED like slice 20's K.** Find the range that is monotone and clean,
  then ship with a ≥2× margin (slice 20's discipline: at K≥0.8 `defl_sat` went 0→1289).
- **P5 — the CONVENTION-9 SEPARATION.** Hold `cd_area = 0` and keep `K` modest; confirm slice 20's
  induced spiral does NOT compete with the stall headline. They live at different α regimes but the
  scenario must be shown to keep them apart, not assumed to.
- **P6 — does `defl_sat` stay 0?** Slice 19's FINDING 2 (the δ_max cap silently contaminating a
  causation twin) recurs here: commanding α_max ABOVE α_stall means commanding LARGER α than any
  prior slice, and `δ_peak ≈ (|Cmα|/Cmδ + k_α)·α_max` scales with it. **A δ_max that binds would
  make this "slice 15's deflection cap in a stall costume."** Assert `defl_sat == 0`.
- **P7 — the CAUSATION COUNTERFACTUAL** (slice 19's "BINDING ≠ CAUSING" discipline). Relaxing
  `α_stall` ALONE must recover most of the miss. Identify what is NOT isolated: `α_stall` enters
  BOTH `C_L(α)` AND `C_Dsep` — so unlike slice 19's clean α_max it is **confounded by construction**
  and may need the two effects separated by a second probe (a stall curve with `K_sep = 0`).

---

## Gates 1–3 (sketch — to be firmed by gate 0's findings)

**Gate 1 — the pure lib.** New `aero_curve.jl` (included BEFORE `radar.jl` so `LIVE_FIDELITY_MODES`
can reference `AERO_CURVE_MODES` — convention 1). Contents: `lift_coefficient(α, p)` (ODD, peaks at
α_stall, falls after), `separation_drag_coefficient(α, p)` (EVEN, zero below α_stall),
`moment_coefficient(α, p)` (the `Cm(α)` break — ODD in α like the linear `Cmα·α` it replaces, losing
its restoring slope past α_break), the closed-form `cl_peak(p)`, and
`const AERO_CURVE_MODES = (:linear, :stall)` (defined ONCE — convention 7). Tests: the parity table
(C_L ODD, both drags EVEN, Cm ODD), the closed-form peak, the linear-limit agreement as
`α_stall → ∞`, the `C_L` consistency tooth (lift and its induced bill use the SAME `C_L` — else the
turn and the invoice disagree), **the break tooth (`∂Cm/∂α < 0` below, `> 0` above — pinned by SIGN,
not magnitude)**, and the sign chain (this arc's #1 trap, now on its FOURTH occurrence: 16 moment
sign, 17 lift direction, 19 the a→α→δ→M→α→lift→γ̇ chain — and note piece 4 puts this slice back on
the SAME function slice 16's trap was found in).

**Gate 2 — the wiring.** `lift_accel` and `induced_drag_accel` get presence-gated stall branches
sharing ONE `C_L(α)`; **`pitch_moment` gets the `Cm(α)` branch with its linear arm TEXTUALLY
VERBATIM** (⚠ the highest-risk edit in the slice — three call sites, and it is the function slices
16–21 all build on); the new `a_sep` term joins inside `_integrate_coupled!`'s closure (reading the
STAGE state — slice 17's stage-θ and slice 21's stage-z fixes are the precedent, and this term is
α-dependent so it has the same hazard); `aero_accel_limit` returns the interior peak under the rung;
`LIVE_FIDELITY_MODES` gains `aero_curve`. Class **4c** (physics-changing, NO RNG — truth-fed PN, no
seeker ⇒ "draw-count invariance" is VACUOUS; the 8th consecutive 4c; live-settable, NO
`set_fidelity` guard). ⚠ Check `:aero_curve` INERTNESS without `:pitch_coupled` — slice 21's `_atm_on`
third-conjunct bug is the direct precedent and it was a LATENT BUG FIX found at gate 3. ⚠ **AND NOTE
THE MOMENT BREAK REACHES FURTHER THAN ρ(z) DID**: `pitch_moment` is live on the `:point_mass`
rotational path too (`_integrate_airframe!`), so decide DELIBERATELY whether the break applies there
— slice 21's bug was precisely half the missile in one model and half in another.

**Gate 3 — the four proofs** (convention 14): `slice22_verify.gd`, `slice22_ui_test.gd`, the
`Sandbox.tscn` headless smoke-load, and a windowed shot aimed at the CLAIMED branch. The client
should REUSE slice 19's airframe view + aero strip (slices 20/21 both did); the button is the
`:aero_curve` cycler — ⚠ **`_setup_spatial_fid_btn` now has FOUR view-claiming keys to order**
(`:atmosphere` was checked first for slice 21); this is the one-button rule's **4th occurrence**.
⚠ Slice-21 gate-3's three PROOF bugs are live watch-items: `%.2e` is not a GDScript specifier (an
unknown one makes the WHOLE `%` fail SILENTLY), frame-sampling error is ASYMMETRIC (a miss samples
faithfully, a HIT samples coarsely), and magic-multiple teeth must be pinned against a MEASURED
value. See [[ewsim-missile-verifier-sampling]] for the LOS range-gate rule.

---

## Named deferrals (write them down; do not let them leak into this slice)

- **A STALL-AWARE AUTOPILOT** — inverting the real curve, with the multivalued past-peak inverse
  that implies (#1). This slice deliberately leaves the inversion linear.
- **Mach / compressibility** — the aero lib is deliberately Mach-free (`atmosphere.jl` §1), so
  `α_stall` and `C_Lα` do not vary with Mach here. A real interceptor's do.
- **Hysteresis** — real separation re-attaches at a LOWER α than it separates at. The shipped curve
  is single-valued in α, with no memory.
- **Roll/yaw departure** — the pitch-plane reduction still holds; a real departure goes
  OUT-OF-PLANE, and this slice's departs strictly in-plane. **This is now the sharpest remaining
  approximation in the slice** (piece 4 makes departure real, and the pitch-plane reduction is what
  keeps it flat). Dies only with bank-to-turn / 3-D.
- **DEPARTURE RECOVERY / a spin model** — if P3 finds the departure TERMINAL, this slice ships the
  onset and not the aftermath. Post-departure rotational behaviour (spin modes, recovery inputs) is
  a separate model and is NOT smuggled in.
- **ρ(z) on the ballistic path** (slice 21's deferral, unchanged) and the RF layered
  atmosphere / ducting entry — **do not conflate either with this slice**.
