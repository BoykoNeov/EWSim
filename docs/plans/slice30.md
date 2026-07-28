# Slice 30 — THE ENVELOPE, AND THE ONE-SIDED CONSTRAINT (§11 Tier-A)

The EIGHTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
radome-slope compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator), and the
deferral slice 29 named as its own strongest successor:

> *"**THE ENVELOPE / ONE-SIDEDNESS SLICE (§2)** — 'gain scheduling buys performance, not stability;
> over-compensate deliberately to the envelope's worst-case slope, and pay for it in `ω_ratio`'.
> Fully measured at gate 0 (P4/P5/P6) and NOT shipped, because it is a multi-engagement claim and
> target velocity is not a comp key. ⚠ Its enabling change is small and precedented — a
> presence-gated `cross_speed_mps` on `ConstantVelocity`, exactly slice 18's `alt_hold_m` — and it
> would ALSO retire the constraint that forced slice 28 to relocate two proofs. **The strongest
> single successor.**"* — `docs/plans/slice29.md`, named deferrals

⭐ **THIS IS THE FIRST SLICE OF THE ARC WHOSE PHYSICS WAS ALREADY MEASURED BEFORE IT BEGAN.** Slice
29's gate 0 produced the result as a REFUTATION of its own first plan and then could not ship it,
because the claim ranges over ENGAGEMENTS and the engagement was not addressable. Slice 30's job is
therefore not to discover a mechanism — it is to make one **client-drivable**, and then to be honest
about the two things that only become visible once it is.

**Status: GATE 0 COMPLETE (2026-07-28) — 8 probes, one advisor-predicted trap that did not fire, one
predictor refutation that produced a second result. Raw findings and probe scripts in
`M:\claud_projects\temp\slice30\GATE0_FINDINGS.md` (P1–P4) and `GATE0_FINDINGS_P5-P8.md` (P5–P8).**

---

## The one-paragraph statement of the lesson

Slice 26 measured — and never used — the fact that the radome constraint is **ONE-SIDED**: only a
NEGATIVE residual closes the parasitic loop, while a positive one merely de-tunes the seeker. Read as
a design rule that is worth more than the whole scheduling apparatus slices 27–29 built. If only
negative residuals ring, then a plain SCALAR `R̂` set at or below the most negative slope the glass
reaches **anywhere in the envelope** is stable in **every** engagement — not because it is accurate
anywhere, but because it errs in the harmless direction everywhere. You do not need a schedule, you
do not need to know which engagement you will fly, and you do not need slice 29's index at all. What
you need is a BOUND. ⇒ **GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY**, and slice 27's "know your
slope to within `0.38/(N·ρ)`" is revealed as a TWO-SIDED reading of a ONE-SIDED constraint. But the
bound is not free: over-compensation cuts the effective navigation ratio, so the scalar has **two
bounds — stability from below, accuracy from above** — and they close on each other as the glass
worsens. That closing window is the classical fixed-gain-versus-gain-scheduling argument, made
quantitative on a measured plant.

> **THE LESSON, IN ONE SENTENCE.** Because only a negative residual rings, stability is
> UNCONDITIONALLY PURCHASABLE with a scalar aimed at the envelope's worst-case slope — so what a
> schedule actually buys is ACCURACY, and the engineering question stops being *"how well do I know
> my glass?"* and becomes *"how much navigation ratio am I willing to pay to stop caring?"*

⚠ **INHERITED LANGUAGE AND ITS PROHIBITIONS.** The instability is still slice 26's — a true
positive-feedback loop, a loop gain, a stability boundary, self-excitation from zero input. Slice
20's "degenerative spiral" language stays forbidden here; slice 26's stays forbidden elsewhere.
Slice 30 adds **no new instability, no new cap, no new gain and no new mechanism whatsoever**: it
adds an AXIS — the engagement — and the axis is what turns slice 26's sign observation into a design
rule.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⭐⭐ THE ADVISOR'S BLOCKING QUESTION, AND WHY IT DOES NOT FIRE: A STEP IS NOT A SWEEP (P1)

Slice 29's P3 measured that the parasitic loop needs **DWELL** at a supercritical residual to build a
limit cycle — a band the engagement SWEEPS THROUGH is visited briefly everywhere and does not ring.
The envelope claim is a MAX OVER N SEPARATE RUNS, so the natural worry is that a gate-3 verifier
driving the envelope with a LIVE `set_param` would measure quiet arms and read it as the compensator
working: **a green run with the lesson deleted.**

It does not happen. Stepping the crossing speed from the quiet cell to the ringing one rings at
essentially the from-t0 value at every switch time tested (0.90410 / 0.90534 / 0.90301 / 0.90489 /
0.90654 / 0.90458 at t_switch 0…5 s), and so does a dragged RAMP (0.904 / 0.906 / 0.906 / 0.893 over
1 / 2 / 4 / 8 s). **A step to a new CONSTANT crossing speed gives a new FROZEN lead — dwell at the new
operating point for the rest of the flight — so P3's requirement is SATISFIED, not violated.**

⭐ **THE ESTABLISHMENT TIME, MEASURED:** on the from-t0 arm the loop sits at 0.14–0.15 while the lead
is still building (`|look_az|` 0.8–7.6°) and goes 0.40 → 0.90 in the ONE 0.5 s slab where `|look_az|`
crosses ~12°. **~0.5 s to establish, against a 4+ s measurement band.** ⇒ the envelope is drivable
live, and the verifier may use either shape.

⚠ **P3 IS INTACT AND MUST NOT BE WRITTEN UP AS REFUTED.** The ramps above all END inside the
supercritical band and therefore dwell. A genuine P3 sweep keeps moving through and past it. What
P1 establishes is narrower and worth stating exactly: **a sweep that stops is a step.**

### 2. ⭐⭐ THE RESULT, AND IT HOLDS AT EVERY GLASS DEPTH MEASURED (P3)

Envelope = the worst cell over vy ∈ {0, 80, 130, 200, 260, 320, 400}. A compensator PASSES stability
iff it rings at ZERO of the seven.

| span \|2A\| | worst-case scalar `R̂ = R₀+2A` | rings | max envelope MISS | min `ω_ratio` | >30° |
|---|---|---|---|---|---|
| 0.20 | -0.230 | **0/7** | 0.213 m | 0.605 | 0.0% |
| 0.30 | -0.330 | **0/7** | 1.075 m | 0.407 | 0.0% |
| 0.40 | -0.430 | **0/7** | 4.150 m | 0.307 | 0.0% |
| 0.50 | -0.530 | **0/7** | 15.976 m | 0.252 | 0.0% |
| 0.60 | -0.630 | **0/7** | 48.290 m | 0.220 | 0.0% |

(the BORESIGHT compensator on the same envelopes rings 5/7, 6/7, 6/7, 6/7, 6/7.)

⭐⭐ **THE GUARANTEE IS ROBUST** — quiet at every speed at every depth, across a 3× range of slope
span. ⭐⭐ **AND THE PRICE OF THE IDENTICAL GUARANTEE GROWS 227×** (0.213 → 48.290 m) over the same 3×.
The stability bound is pinned at `R₀+2A` by definition, the accuracy bound near a fixed residual by
the de-tune physics, and they converge.

### 3. ⭐ THE `R₀+2A` RULE IS **SUFFICIENT, NEVER TIGHT** (P4b)

At the shipped glass the envelope actually goes quiet at `R̂ ≈ -0.28`, not at the rule's -0.33,
because the loop needs the residual to reach the ONSET (≈ -0.055, slice 29 P10b) and not merely to
be negative. **The rule carries ~0.05 of built-in margin: a BOUND TO BE EXCEEDED, not an estimate to
be matched.** Say "sufficient". Never say "tight", and never present -0.33 as a measured threshold.

### 4. ⭐⭐ CONVENTION 9 IS SATISFIED BY A MEASUREMENT, NOT BY COUNTING SLIDERS (P6/P7/P8)

Slice 30 ships **THREE** knobs. They are legal iff they are three terms of ONE quantity — the
engagement residual the core has shipped as `radome_residual_az` since slice 28 (vy sets the look
angle the engagement holds, A sets the glass's slope there, R̂ sets the belief). The discriminating
test is the one slice 28 used on its own two: reach the same residual from different directions and
check the VERDICT agrees.

Over the full reachable grid (245 arms), with `%super` = the fraction of in-band ticks whose
in-flight residual sits below the onset:

| `%super` | arms | RING | quiet |
|---|---|---|---|
| == 0 | 196 | **0** | 196 |
| (0, 5] | 1 | 0 | 1 |
| (5, 25] | 2 | 1 | 1 |
| (25, 60] | 9 | 9 | 0 |
| (60, 100] | 37 | 37 | 0 |

**No ring anywhere on the grid occurred without the residual first going supercritical** ⇒ no slider
acts outside the engagement residual.

⚠⚠ **QUOTE THE 196/196, NOT THE 47/47 — THE ASYMMETRY IS WHAT MAKES THIS LEGAL UNDER SLICE 29's
P10(a).** A RINGING arm's look band swings BECAUSE it rings, so "`%super` > 0 on a ringing arm" is
CORROBORATION and never proof: the ring may be feeding its own band. "`%super` == 0 on a QUIET arm"
has no such circularity, and it is the direction convention 9 actually needs.

⭐ The only two exceptions are QUIET arms at `%super` 3.92 and 9.28 — brief supercritical excursions
that never got the DWELL. **P1's finding and slice 29's P3, arriving independently out of a grid
that was not built to test them.**

### 5. ⭐⭐ A REFUTATION THAT PRODUCED A SECOND RESULT: THE BAND'S CENTRE IS NOT THE BAND (P6/P7)

Convention 9's first test predicted RING from a PRE-FLIGHT residual — the glass evaluated at the
nominal collision-course look angle (taken off the FLAT-GLASS arm, one band per crossing speed). It
agreed on 237/245 = 96.7%, and **the 8 failures did not cluster at the boundary**: several ring hard
(rms 0.80–0.94) at a clearly POSITIVE design residual, up to +0.110. Taken at face value that is a
slider changing the verdict without moving the residual — a second lesson, and a knob to drop.

Diagnosing them (P7) showed it is a PREDICTOR flaw: every ringing mismatch spent real in-band time
below the onset (`%super` 17.4–100), with actual median residuals all negative. **And the mechanism
is a result worth shipping.** With k = 12 the ripple's minimum is at look = 15° and it RETURNS to R₀
at 30°. The nominal band CENTRE runs 19.7 / 24.0 / **29.2°** at vy 260 / 320 / 400 — at vy = 400,
`1 − cos(k·look_ref) = 0.016`, so the nominal look angle sits on the flat RETURNING branch and
predicts almost no ripple at all. The arm actually SWEEPS 8–26°, straight through the minimum.

> ⭐⭐ **A PRE-FLIGHT RULE SIZED FROM THE NOMINAL COLLISION-COURSE LOOK ANGLE UNDER-COMPENSATES,
> BECAUSE THE ENGAGEMENT VISITS A BAND AND THE BAND'S CENTRE IS NOT THE BAND.** This is slice 28's
> "know your slope curve over the band the engagement visits" with the emphasis moved onto **BAND** —
> and it is a SECOND, INDEPENDENT ARGUMENT FOR THE WORST-CASE-SLOPE RULE, which never needs the band
> at all. That is precisely why it is robust.

⚠ Probe 5B's first attempt used the WORST-CASE SCALAR as the quiet reference and was wrong: that arm
is de-tuned by construction and its look band COLLAPSES with glass depth (13.92° at A = -0.10 down to
2.90° at A = -0.25, same vy). Use the FLAT-GLASS arm — it is the only reference independent of both
radome knobs.

### 6. ⚠ `ω_ratio` IS A DE-TUNE MEASURE **ONLY ON A QUIET ARM** (P4c)

On the ringing arms it reads 1.51–16.0 — that is the limit cycle corrupting the reported LOS rate,
not a de-tune (slice 26: `omega_ratio` is a DIAGNOSTIC, not the mechanism). **The price must be
quoted as the drop ACROSS QUIET ARMS** (0.4992 at R̂ = -0.28 down to 0.2266 at -0.60), or against the
flat-glass control — **never as "1.58 → 0.41"**, which silently compares a ringing number to a quiet
one.

### 7. ⚠ THE NON-MONOTONE SWEEP IS **NOT** SHIPPED AS A PROOF, AND THAT IS THE HONEST DELIVERABLE #2

Slice 29 promised this slice would "retire the constraint that forced slice 28 to relocate two
proofs". The constraint IS retired in principle — target velocity becomes a comp key, so slice 28's
QUIET→RING→QUIET sweep becomes a slider. But **it does not reproduce at the shipped glass**: at
A = -0.15 the sweep rings 80 → 450 with no quiet upper end, because the deeper ripple keeps `R(look)`
supercritical across the whole band. The shape is a property of the (A, k) pair, not of the knob.

⇒ Slice 28's relocated phases **stay in `test_missile.jl`**, where they are already proven, and the
scenario header says so and says why. The non-monotone remains reachable by dragging A to -0.10.
Moving a proof to a slider buys presentation, not evidence.

### 8. THE SHIPPED WIRE, AND WHY IT IS NOT A = -0.10 (P4a)

`A = -0.15`, `R₀ = -0.03`, `k = 12`, so the glass's most negative slope anywhere is `R₀+2A = -0.33`.

| vy | BORESIGHT `R̂ = -0.03` | WORST-CASE `R̂ = -0.33` | FLAT control `A = 0` |
|---|---|---|---|
| 0 | 0.01649 quiet | 0.03640 quiet | 0.01641 quiet |
| 40 | 0.01571 quiet | 0.04589 quiet | 0.01593 quiet |
| 80 | **0.85295 RING** | 0.05280 quiet | 0.01561 quiet |
| 130 | **1.01447 RING** | 0.05821 quiet | 0.01496 quiet |
| 170 | **1.08561 RING** | 0.05966 quiet | 0.01433 quiet |
| 200 | **1.07247 RING** | 0.05879 quiet | 0.01386 quiet |
| 240 | **1.05930 RING** | 0.05475 quiet | 0.01309 quiet |
| 280 | **1.04926 RING** | 0.04688 quiet | 0.01235 quiet |
| 320 | **0.98837 RING** | 0.03862 quiet | 0.01188 quiet |
| 360 | **0.96030 RING** | 0.03347 quiet | 0.01131 quiet |
| 400 | **0.97927 RING** | 0.02970 quiet | 0.01081 quiet |

`>30°` is **0.0% in every cell.**

⭐ **THE HEADLINE IS THE RING COUNT — 6/7 → 0/7 — NOT A RATIO.** It is the envelope claim in the
envelope's own units, and it is what "unconditionally stable across the whole envelope" means. The
per-cell collapse (max rms r 1.0725 → 0.0588, 18.2×) rides beside it as CORROBORATION only: an rms
ratio invites the reader to treat one cell as the result, which is exactly the aggregation slice 26's
two-windows-two-ratios rule warns about.

⚠ A = -0.10 was rejected as the shipped glass **even though it ships the non-monotone for free**,
because its price is 0.213 m — a price a student cannot see. The slice's own headline is the two
bounds; take the price half.

### 9. THE KNOB DOMAINS, EVERY ENDPOINT MEASURED (slice 26's post-commit rule)

| knob | domain | the endpoint, measured |
|---|---|---|
| `cross_speed_mps` (NEW) | **[0, 400]** | FLOOR = the DEAD point, and it is dead exactly: look 0.04°, `R(look) = R₀`, residual **-0.0000**. CEILING = the model-validity budget, which blows at 450 (**38.6%** of in-band frames past a 30° look) and 500 (100%) — read at the SHALLOW end of the A domain, because at A = -0.15 the same 450 is still 0.0% and a domain chosen on deep glass alone would be wrong. Slice 28's other reason corroborates: Vc collapses 688 → 362 → 241. |
| `radome_ripple` A | **[-0.20, 0]** | THE CORNER, measured not inferred: at A = -0.25 with the R̂ slider at its TOP the budget blows to 0.6%. ⚠ The blown cell is at the **UNDER**-compensated corner, the opposite of what row-wise scans suggested. CEILING 0.00 is bit-identical to the key being absent (slice 28, measured). |
| `radome_slope_est` R̂ | **[-0.55, 0]** | FLOOR contains `R₀+2A = -0.43` for the DEEPEST glass with margin and puts the de-tune face on show (miss 21.6 m at the corner). CEILING 0.00 is physical, as in slice 27/28: a POSITIVE R̂ compensates the WRONG WAY and is exactly a worse radome. |

⚠ **EVERY OTHER CANDIDATE STAYS DISQUALIFIED AND THE VERIFIER ASSERTS THEIR ABSENCE** (inherited from
26/27/28): `n_pn` and `rho` move the LOOP GAIN the lesson is about; `radome_ripple_k` is non-monotone;
`af_alpha_max` sets the cycle's amplitude; `sigma_seek` compresses the contrast; `speed` is the
slice-19 DEAD knob.

### 10. CLASS, BYTE-IDENTITY AND THE KNOB-vs-RUNG DISCRIMINATOR

Class **4a** — draw-invariant yet trajectory-changing; a target-velocity knob adds no draws, so the
2 randn/tick are untouched. **FIFTH consecutive RNG-live slice** (25, 26, 27, 28, 29, 30): the seed is
load-bearing and conventions 3/11 apply. Draw-count identity is **ASSERTED, not assumed**.

**KNOB, not rung**, and MEASURED (slice 26's rule, whose whole point is that this is not argued): a
pinned `cross_speed_mps = 200` on a target authored `vel: [0, 200, 0]` gives

```
no key: rms r = 1.072466902, miss = 2.004235
vy=200: rms r = 1.072466902, miss = 2.004235
max |posdiff| over the common prefix = 0        <- BIT-IDENTICAL
```

Slices 1–29 stay byte-identical by PRESENCE gating.

---

## Gate 1 — the core seam — **COMPLETE (2026-07-28), 5500 → 5542 tests**

⭐⭐ **THE ORDERING TOOTH WAS PROVEN BY DELIBERATE INVERSION, NOT BY INSPECTION** (advisor: "the
single highest-value five minutes in this gate"). With the pin moved to the WRONG side of the `pos`
update and the suite re-run, **exactly 6 asserts go red** — both `⭐⭐ THE ORDERING` teeth
(`test_radar.jl`: the full-trace `==`, and `ymax` reading **0.2 vs 0.0**), both disagreeing pairs on
the real missile wire (`test_missile.jl`), and — as corroboration — the two `pos[2] ≈ n·v·dt` atol
checks in the "holds every tick" / "composes with `alt_hold_m`" teeth.

⚠⚠ **AND THE EQUAL-VALUE TEETH PASSED UNDER THE BUG — MEASURED, NOT PREDICTED**: `BYTE-IDENTITY`
went 3/3 and `THE KNOB-vs-RUNG DISCRIMINATOR` 2/2 with the seam wrong. That is the plan's own §gate-1
warning turned into evidence: a gate built only from equal-value comparisons ships the ordering bug
GREEN, and gate 0's P4d (`cross_speed_mps = 200` vs an authored `vel: [0,200,0]`) is exactly such a
comparison.

⭐ **THREE TEST FILES, NOT THE TWO THE DRAFT NAMED** (advisor): mover mechanics → `test_radar.jl`
(`ConstantVelocity` lives in `radar.jl`); loader / LOAD ERROR / knob declaration → `test_scenario.jl`
beside the `alt_hold_m` tooth, which is the established precedent; draw-count identity → the new
`test_missile.jl` slice-30 testset on slice 29's own wire.

⚠ **THE MANEUVER GUARD READS THE YAML BLOCK, NOT THE COMP BAG** (advisor): `haskey(comp,
:cross_speed_mps)` would work today only because the parse happens to sit above the fork — a later
reorder would silently disarm it. `haskey(tb, "cross_speed_mps")` is the slice-28/29 loader shape.

⚠ **VALIDATED FINITE ONLY — no positivity guard, no consumer clamp.** The SIGN is meaningful (a
negative crossing flies the mirror engagement) and every magnitude is crash-safe: the `alt_hold_m` /
slice-28 `radome_ripple` posture, not a second guard site invented for this key.



`ConstantVelocity.integrate!` (`core/src/radar.jl`) gains ONE presence-gated key, pinned EVERY tick
(slice 29's probes did a one-shot `t.vel = ...`; for a constant the difference is nil — P2a measured
the pinned form reproducing slice 29's P4/P5 matrix to the digit — but the pinned form is the one
that composes with a live slider):

```julia
haskey(e.comp, :cross_speed_mps) &&
    (e.vel = Vec3(e.vel[1], Float64(e.comp[:cross_speed_mps]), e.vel[3]))
e.pos = e.pos + e.vel * dt
```

⚠⚠ **THE PIN GOES BEFORE THE INTEGRATE LINE, AND THIS IS NOT WHERE `alt_hold_m` PUTS IT** (advisor,
load-bearing — the plan's own first draft had it after, copying `alt_hold_m` literally, and that is
a BUG). `alt_hold_m` pins a **position**: the pin is idempotent AND is itself the observable, so
after the update is correct. `cross_speed_mps` pins a **velocity that the `pos` update on the same
tick has already consumed** — pinned after, the first step of every run advances on the AUTHORED
`vel_y` and the knob is dead for one tick.

⚠ **AND GATE 0's OWN BIT-IDENTITY TEST CANNOT SEE THAT BUG.** P4d compared `cross_speed_mps = 200`
against a target authored `vel: [0, 200, 0]` — the two AGREE, so an ordering error is invisible.
P4d is the BYTE-IDENTITY check, not the CORRECTNESS check. The discriminating tooth is a
**DISAGREEING pair** (gate 1, below). ⚠ The probes escaped the bug only because they set `tgt.vel`
BEFORE `tick!` — i.e. gate 0 measured the correct order while the plan's first draft wrote the wrong
one, which is exactly the kind of gap that reaches a verifier green.

⚠ It must compose with `alt_hold_m` (one pins `pos.z`, the other `vel.y` — disjoint) and must NOT
collide with the `a_lat_mps2` / `turn_sign` → `ManeuveringTarget` fork, whose `_lateral_accel` is
hard-coded to the x–z plane. A `cross_speed_mps` on a maneuvering target is a **LOAD ERROR**, refused
rather than silently branch-ordered (the slice-21 precedent).

Loader (`core/src/scenario.jl`): the key lands beside `alt_hold_m`, validated finite at LOAD
(convention 5), and declared a knob.

**Teeth** (`test_radar.jl` / `test_missile.jl`):

- **BYTE-IDENTITY** — the presence gate is bit-identical when the key is absent (slices 1–29).
- **THE KNOB-vs-RUNG DISCRIMINATOR** — `cross_speed_mps` EQUAL to the authored `vel_y` is
  bit-identical to no key (P4d, `posdiff == 0` exactly).
- ⭐⭐ **THE CORRECTNESS TOOTH — A DISAGREEING PAIR, WHICH IS THE ONLY ONE THAT CATCHES THE ORDERING
  BUG.** Authored `vel: [0, 200, 0]` with `cross_speed_mps: 0` must be bit-identical to a target
  authored `vel: [0, 0, 0]` with NO key — in particular `max|pos_y| == 0.0` EXACTLY. Pinned after
  the integrate line it is ~0.2 m, not 0.0, and every equal-value test still passes.
- the pin holds against an authored non-zero `vel_y` over many ticks (not just the first);
- it composes with `alt_hold_m` (disjoint coordinates: one pins `pos.z`, the other `vel.y`);
- a maneuvering target carrying it is a LOAD ERROR;
- draw-count identity across the knob (class 4a, asserted).

## Gate 2 — telemetry and the wire — **COMPLETE (2026-07-28), 5542 → 5608 tests**

No new physics ⇒ no new telemetry is strictly required: `radome_residual_az`, `omega_ratio` and the
look angle have all shipped since 28. What the LESSON needs is the number the design rule TARGETS —
`R₀ + 2A`, the glass's most negative slope anywhere — which the core must ship rather than let the
client compute (convention 13: physics never in GDScript). Plus the crossing speed itself, so the HUD
can label the engagement being flown. Raw findings in
`M:\claud_projects\temp\slice30\GATE2_FINDINGS.md` (probes 9 and 10).

**TWO KEYS, and a new one-line kernel.** `frames.jl` gains `radome_slope_worst(slope0, ripple)`
beside the curve it bounds; `missile.jl` ships `<m>.radome_slope_worst` (inside the `_ripple_on`
block, beside slice 28's `radome_slope_az`/`_el`) and `<m>.cross_speed_mps`.

### 1. ⚠⚠ IT IS A `min`, NOT THE LITERAL `R₀ + 2A` (advisor) — and the wire exercises both branches

`radome_slope_worst = min(slope0, slope0 + 2·ripple)`. Over the declared `A ∈ [-0.20, 0]` knob domain
the two forms are IDENTICAL, so the prose above is implemented rather than contradicted. The
difference is outside it: the loader validates `radome_ripple` FINITE ONLY, and a POSITIVE amplitude
is a meaningful configuration in this codebase (slice 26: positive slopes DE-TUNE rather than ring) —
there the literal `R₀+2A` is the most POSITIVE slope, i.e. the maximally de-tuned aim point, which
**inverts the one-sided rule the key exists to serve**. `min` keeps §3's "sufficient, never tight"
property in BOTH signs. MEASURED on the wire, not just in the kernel test: at `A = +0.15` the shipped
key is `-0.03`, not `+0.27`.

⚠ **AND IT IS A BOUND ON THE CURVE, NOT ON THE BAND** — stated in the docstring because a reader will
otherwise take it for "the slope the engagement sees at worst". The extremum needs `k·look = π`, so
for a small authored `k` the minimum sits OUTSIDE the reachable look angles and the bound is even more
conservative than the glass ever presents in flight. That extra conservatism is the whole value: the
rule never has to know which engagement will be flown, which is also why it survives the trap of §5
(a pre-flight rule sized from the nominal collision-course look angle under-compensates).

### 2. THE SITE: `cross_speed_mps` SHIPS FROM PHASE-4 `decide!`, NOT FROM THE SEEKER (advisor)

The question is which block already owns ENGAGEMENT geometry — that is the one carrying `los_range` /
`closing_speed` / `range_rate` / `los_rate`. A target's crossing speed is not a SENSOR quantity, and
siting it in the seeker's readout would needlessly couple it to the `:seeker_axes` host. It ships the
**KNOB VALUE** (`tgt.comp[:cross_speed_mps]`), never `tgt.vel[2]` — which would grow a key on every
prior wire and would report the authored velocity of a target carrying no pin at all.

⚠ Published ABOVE the no-target/impacted early return, so both arms ship it exactly once. Unlike the
never-stale ZEROS below it, this key does NOT go stale post-impact: the target keeps crossing at the
speed the knob says. Both new keys take `_finite_coord` — both are SIGN-meaningful (a negative
crossing flies the mirror engagement), and `_finite` clamps only from above, which is the exact trap
slice 29 caught on `k̂`.

### 3. ⚠⚠ "BYTE-IDENTITY ON THE WIRE" IS NOT LITERALLY TRUE, AND THE PRECISE CLAIM IS THIS (advisor)

Slices 28 and 29 both AUTHOR `radome_ripple`, so `_ripple_on` is true there and their wires **GROW**
`radome_slope_worst`. That is the right gate — the worst-case slope is a property of the GLASS, and
coupling it to the target's knob would be wrong — but the claim must be stated as: **trajectory and
RNG bit-identical, telemetry ADDITIVE on ripple-carrying wires.** A `cross_speed_mps`-free target
grows nothing; a no-ripple (26/27) or no-radome (25) wire grows nothing. All four gates are teeth.

### 4. ⭐ THE DISCRIMINATING PAIR: A PROPERTY OF THE GLASS, NOT OF THE ENGAGEMENT

The reason this is a second key and not a relabelling of `radome_slope_az`: the crossing speed moves
WHERE the seeker looks, so `radome_slope_az` (the slope THERE) moves with it — and the worst case over
the whole curve cannot. Pinned as a pair on one wire (`cross = 0` vs `300`: `_worst` bit-identical,
`_az` different). That split IS the one-sidedness argument — the rule needs no knowledge of the
engagement, which is exactly why it holds across an envelope.

### 5. ⭐ THE SECOND SEED — LOAD-BEARING, BECAUSE THE HEADLINE IS A COUNT (advisor)

A ratio has tolerance to absorb noise; a RING COUNT does not — one cell flipping changes the published
number. All 14 envelope arms were re-run at seed 4242 beside the scenario's own 28:

**6/7 vs 6/7 (boresight), 0/7 vs 0/7 (worst-case).** Every cell moves **< 0.2%** with the seed, against
a ~14.5× gap between the two arms. Margins to the 0.30 verdict line: the largest QUIET arm sits
**5.10× below** it, the smallest RING arm **2.84× above**. The two MARGINAL cells (vy = 200 under the
worst-case scalar, vy = 80 under boresight) are TEETH in `test_missile.jl`; the other twelve stay
probe territory, `log`-style, so nothing is silently sampled.

### 6. ⭐ THE SHIPPED SEAM REPRODUCES GATE 0's EMULATION TO THE DIGIT

All twelve cells of §8's table come back identical off the real `comp[:cross_speed_mps]` pin (gate 0
set `tgt.vel` once per tick before `tick!`; gate 1 pins inside `integrate!`, before the `pos` update).
P2a asserted the agreement; this measures it, and it is the evidence that §2/§3/§8's tables transfer
to the shipped code unchanged.

### 7. THE GATE-3 DEPENDENCY, CHECKED HERE RATHER THAN DISCOVERED THERE (advisor)

`set_param` on a **target** entity works: `handle_command!` needs only the entity to exist plus a
declared `Knob` matching `(target, key)`, gate 1's `test_scenario.jl` tooth already asserts
`cross_speed_mps` lands in `scn.knobs` for a target, and slice 18's `alt_hold_m` is driven exactly
that way from `slice18_ui_test.gd`. ⇒ P1's licence to drive the envelope with a LIVE slider stands,
and the verifier does not need a different approach.

**Teeth** (`test_frames.jl` / `test_missile.jl`): the kernel against a DENSE SWEEP of
`radome_slope_curve` over a full ripple period (convention 11 — an independent recompute as the
oracle, in six (R₀, A, k) combinations spanning both signs), `A = 0 ⇒ exactly R₀` bit-exact,
monotone-in-depth over the shipped domain, the `min` branch PAIRED with a does-differ case; and on the
wire: the four gating cases, the glass-vs-engagement pair, the signed/clamped live-slider guards, the
post-impact never-stale case, and the two second-seed marginal cells with their margins.

⚠ The `R₀+2A` teeth are pinned against the EXPRESSION, never the decimal `-0.33` — the Float64 sum is
`-0.32999999999999996`, so a literal would assert float formatting instead of the identity (caught by
the first run of the new frames testset).

## Gate 3 — scenario, client, four proofs

`scenarios/slice30_envelope.yaml` — slice 28's wire with `A = -0.15` and the three knobs above. Opens
on the DISEASE (boresight `R̂ = -0.03`, vy = 200, ringing), the slice-25/26/27/28/29 shape.

⚠ **THE ONE CLIENT EDIT THE LESSON REQUIRES** (advisor; slice 28 ate exactly this defect once): the
HUD must show **`R₀ + 2A` LIVE beside `R̂`**. Dragging A moves the rule's own target, so without it a
student who deepens the glass silently invalidates the R̂ they already set. Everything else reuses
slice 26/28's radome HUD, and the button stays DROPPED (16/26/27/28/29/30 — the SIXTH slice in that
family whose lesson is sliders with no button at all).

**FOUR PROOFS, per convention 14** — `slice30_verify.gd`, `slice30_ui_test.gd`, the `Sandbox.tscn`
headless smoke-load, and the windowed shot harness. ⚠ The list below is the FIRST proof's internal
PHASES, not the four — do not let the heading and the content contradict each other (slice 21 lost a
headline to exactly that class of proof-not-physics defect).

`slice30_verify.gd` phases:

1. **ENVELOPE / BORESIGHT** — sweep `cross_speed_mps` across the domain; assert the ring count is 6/7.
2. **⭐ ENVELOPE / WORST-CASE SCALAR** — same sweep at `R̂ = R₀+2A`; assert 0/7 and quote both counts.
   ⇒ the headline, in the envelope's own units.
3. **⭐⭐ THE PRICE** — `ω_ratio` and the miss, asserted to grow as A deepens.
   ⚠⚠ **QUIET-TO-QUIET, AND R̂ MUST BE MOVED TO THE WORST-CASE SCALAR *FOR EACH A*** (it is
   `R₀+2A`, so it MOVES with A). At the boresight compensator most arms RING, and §6 forbids reading
   `ω_ratio` off a ringing arm — implemented naively this phase becomes a ring-vs-quiet comparison
   and the slice states §6 and violates it in the same file.
4. **SUFFICIENT-NOT-TIGHT** — the envelope goes quiet at R̂ ≈ -0.28, above the rule's -0.33 (§3).
5. **REPLAY** — held-seed bit-identical across a knob change (posdiff 0.0).
6. **DOMAIN ENDPOINTS** — the dead point at vy = 0 (residual -0.0000) and the validity budget at the
   ceiling (slice 26's post-commit rule: measure the endpoints).

⚠ The verifier may drive the envelope with live `set_param` (P1 licenses it) — but it MUST allow the
~0.5 s establishment time and window on the range band, never on raw ticks.

---

## Named deferrals (write them down; do not let them leak into this slice)

- **AN IMPERFECT GYRO** (noise / bias / scale-factor) — open since slice 27, unchanged. A
  scale-factor error is a multiplicative error on `R̂`, so it lands back on the residual.
- **ESTIMATING `R̂` IN FLIGHT** — still blocked by slice 26's P7A (not identifiable in closed loop),
  sharpened by slice 29 (the estimator would have to identify a SHAPE from a bent index).
- **A 2-D SLOPE `R(look_az, look_el)`** and **AN ASYMMETRIC ERROR CURVE** — inherited from slice 28.
  An asymmetric curve would make the crossing DIRECTION matter, which composes directly with this
  slice's new axis.
- **SEEKER FOV / GIMBAL LIMIT** — sharper again: this slice's upper domain endpoint is set by the
  look angle reaching 30°, which is exactly where a real gimbal would already have stopped.
- **THE OUT-OF-PLANE MANEUVERING TARGET** (slice 24 route (b)) — and now with a REASON to want it:
  it is the genuine P3 sweep that P1 deliberately did not test (§1).
- **THE NON-MONOTONE SWEEP AS A SHIPPED PROOF** — §7; needs its own glass, not this one.

---

## Task checklist

- [x] Gate 0 — 8 probes. One advisor-predicted trap measured and did not fire (P1, the dwell
      question); one predictor refutation that produced a second result (P6/P7, the band's centre is
      not the band); the corner of the two-knob rectangle measured rather than inferred (P5); and
      convention 9 settled by measurement (P8, 196/196). Two advisor passes — the false-fidelity
      check that opened gate 0, and the design review that set the glass, the headline, the corner
      and the HUD requirement.
- [x] Gate 1 — the `ConstantVelocity` seam + loader key + teeth. **5500 → 5542 (+42), full suite
      green.** The ordering tooth PROVEN by deliberate inversion (6 red, and the equal-value teeth
      green under the bug); the maneuver × crossing-speed corner refused at LOAD; teeth split across
      `test_radar.jl` / `test_scenario.jl` / `test_missile.jl`.
- [x] Gate 2 — the `R₀+2A` telemetry (`frames.jl radome_slope_worst` + two wire keys); the
      byte-identity claim STATED PRECISELY (trajectory/RNG identical, telemetry ADDITIVE on
      ripple-carrying wires — 28/29 DO grow a key); the second-seed check over all 14 envelope arms
      (**6/7 vs 6/7, 0/7 vs 0/7** — the ring count is seed-invariant, cells move < 0.2%). **5542 →
      5608 (+66), full suite green.** Three advisor calls landed: the `min` instead of the literal
      `R₀+2A`, the phase-4 `decide!` site for `cross_speed_mps`, and the target-scoped `set_param`
      check that gate 3's whole approach depends on.
- [ ] Gate 3 — scenario + the four proofs; the 26/27/28/29 verifiers re-run to the digit.
- [ ] Docs — `docs/STATUS.md` as-built, `CLAUDE.md` status line, `HANDOFF.md` §11, memory.
