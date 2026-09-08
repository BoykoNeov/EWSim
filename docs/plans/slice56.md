# Slice 56 — THE WORST PLACE TO BE IS EXACTLY AT THE THRESHOLD

**The loss-count reversal in `rcs_fineness`: a middling body chatters, a slender one drops out and
stays out — and the peak of the chatter is a statable law, not a fitted number.**

Status: **PLAN + GATE 0 PRE-REGISTRATION.** No code shipped at the time of writing.
Scratch: `W:\temp\claude\slice56\`. Probe code is run through `& tools/julia.ps1`, never `julia -e`.

---

## §0 PROVENANCE — THIS SLICE LIFTS A BAN, AND SAYING SO IS THE FIRST THING IT OWES

### §0.1 The ban, quoted in full before it is touched

`docs/plans/slice49.md` §9 ends with:

> ⚠⚠ **THE GAUGE IS THE LONGEST RUN — AND THE RUN COUNT IS NON-MONOTONE, WHICH WOULD HAVE
> DISQUALIFIED IT** (the `k` (28) / `ω_n` (40) / `σ_seek` (25) precedent). The count goes
> **41 → 133 → 53 → 42**: at F = 3 the target hovers AT the threshold and chatters constantly, while
> at F = 6/10 it drops out hard and stays out, so *more slenderness gives fewer losses*. The DURATION
> is monotone (0.20 → 5.60 → 64.10 → 85.30 s) and so is the range depth (0.0 → 1.4 → 13.9 → 17.9 km).
> ⚠ A "detected %" gauge fails the same way and additionally mixes the outbound leg back in.
> **Never quote the count.**

`docs/DEFERRALS.md` (slice 49's candidate list) repeats it as **"⚠ A NON-MONOTONE-GAUGE NOTE, NOT A
CANDIDATE"**, adds the mechanism in one sentence — *"a middling body chatters at the threshold while
a slender one drops out and stays out"* — calls it *"a real and teachable effect — 'the worst place
to be is exactly at the threshold'"*, and then rules: *"it is NOT a slider axis, and any future slice
that reaches for it must supply its own monotone gauge."*

### §0.2 Why the ban is being lifted, and exactly how far

⚠⚠ **THE BAN IS NOT WRONG AND IS NOT BEING OVERTURNED. ITS SCOPE IS BEING READ CORRECTLY.** Both
sentences forbid ONE thing: the count as **slice 49's showcase SLIDER GAUGE**. Slice 49's headline was
*more slenderness ⇒ longer blind*, and against that headline a gauge that goes up and then down is a
gauge that contradicts the slide. That ruling stands for slice 49 and for any slice with a monotone
headline.

What changed is `CLAUDE.md`'s **2026-09-06 five-trigger reframe** (`docs/DEFERRALS.md` §"THE BUILD
LIST"): a lesson needs a TRIGGER and a CONTRAST, and **`CURVE` — the response REVERSES, and the
turning point IS the lesson — is one of the five.** Under a `CURVE` headline the reversal is not a
defect in the gauge; it is the object being taught. `docs/PROHIBITIONS.md` §4 already files the count
this way (*"TIER 2 — `CURVE`, seven ready-made lessons"*).

⇒ **The lift is narrow and it is stated as a rule, not a permission:**

- **STILL BANNED** — the loss COUNT as a monotone slider gauge, on slice 49's wire or any other. Slice
  49's own headline keeps the DURATION gauge and nothing here touches it.
- **LIFTED** — the loss COUNT as a `CURVE`'s object, on a wire built for a turning point, with the
  duration gauge published BESIDE it as the monotone companion. ⚠ The two gauges are two readouts of
  ONE lesson (*where you sit relative to the threshold decides, not how big you are*), which is
  convention 9 respected, not stretched.
- ⚠ **AND THE LIFT IS CONDITIONAL ON §3's KILL.** If the count's peak does not resolve, the ban is
  reinstated verbatim and this slice ships the NULL instead (§3.3). The ban's author gets the last
  word if the measurement agrees with them.

### §0.3 Two of slice 49's blockers are STALE at HEAD — checked in the code, not in the ledger

The standing lesson from slice 54 (`docs/DEFERRALS.md` §"Slice 54 — DISCHARGED, AND THE ENTRY'S OWN
BLOCKER WAS STALE") and again from slice 55 (three expired sentences in the slice-45 entry) is:
**re-read the CONSUMER before pricing a candidate on the ledger's account of what exists.** Done here
on 2026-09-08, and two sentences have expired:

1. **Slice 49 §9 flew its probe kinematics because *"§7's turn is not authorable yet"*, with the
   target's phase-1 mover removed from the subsystem list so nothing double-integrates.** ⚠⚠ **That
   is FALSE at HEAD.** Slice 51 shipped `maneuver.turn_start_s` (`core/src/missile.jl:1183–1218`,
   loaded at `core/src/scenario.jl:298–311`): a `ManeuveringTarget` flies STRAIGHT until an authored
   time and turns from the first step whose accumulated `w.t ≥ turn_start_s`. **The broadside-leg-
   then-turn-inbound geometry slice 49 had to fake in a probe is now an authorable scenario**, which
   is what makes this a showcase slice rather than another probe record.
2. **Slice 49 filed the count as *"NOT a slider axis"* partly because a curve would mean re-flying the
   pass once per arm.** ⚠⚠ **That cost is now ZERO** — see §2. Slice 54 shipped N shadow arms on ONE
   pass; §2 establishes that the same trick is available one layer UPSTREAM, at no extra RNG draws
   and bit-identically for the live arm.

⇒ **This is not slice 49 re-run.** It is a slice whose two preconditions shipped in 51 and 54, aimed
at the one measurement slice 49 wrote down and refused to use.

---

## §1 THE CLAIM, AND THE LAW IT STANDS OR FALLS ON

**THE CLAIM.** For a target whose echo depends on which way it is pointing, the number of times a
radar loses it is **not monotone in how slender it is**. It has an interior PEAK. A sphere is
essentially never lost (Swerling-1 fading only, bounded at a fraction of a second). A very slender
body drops below threshold and stays there — few, enormous losses. **The worst body is the middling
one, whose echo sits ON the threshold for a long stretch of the geometry and crosses it repeatedly.**

**THE LAW (this is the part that must be pre-registered, because a turning point that is only a
fitted number is a weaker object — slice 55 §II.6's standing objection).** The peak sits where the
target's MEDIAN echo, over the stretch of geometry the gauge scores, crosses the detector's own
threshold. It is not a tuning constant: it is a crossing of two quantities the simulator already
computes and can print side by side.

⇒ **PRE-REGISTERED PREDICTION, WRITTEN BEFORE THE FLIGHTS:** compute `F*`, the fineness at which the
median in-window SNR equals the detection threshold, from the geometry alone. **The measured
count-peak must land at `F*` within one sweep step.** If the peak lands somewhere else, the law is
refuted and the slice ships a fitted number with that refutation attached (§3.3, arm C).

---

## §2 THE MECHANISM: N SHADOW ARMS AT ZERO EXTRA DRAWS — VERIFIED IN THE CODE AT HEAD

**The reason this slice is cheap, and the reason it needs a gate-1 tooth before anything else.**

### §2.1 The separability, on both detector paths

The fineness enters the detector as a SCALE on an already-drawn standard normal. Read at HEAD:

- **POINT PATH** (`core/src/detection.jl:236–288`). Swerling-1, `n_pulses = 1`: the draw order is
  `(nI, nQ, sI, sQ)` — `nI = randn(rng)*_INV_SQRT2`, `nQ` likewise, then
  `_draw_signal` returns `(randn(rng)*sfluc, randn(rng)*sfluc)` with `sfluc = √(SNR/2)`. The file
  states it outright: *"The draw counts are fixed by (swerling) alone, so the RNG stream advances
  identically regardless of the SNR *value*."*
- **CFAR PATH** (`core/src/radar.jl:1232–1245`). `_draw_profile!` is *"the ONLY RNG call of a CFAR
  look"*: `2·N_p·N_cells` draws, `σ = sqrt(power[i]/2)`, and the fineness reaches `power[i]` through
  `_target_snr`'s additive bump BEFORE the draw (`radar.jl:1386–1389`).

⇒ **On both paths, changing `rcs_fineness` changes a MULTIPLIER, never a COUNT and never an ORDER.**

### §2.2 The bit-identity argument, stated precisely because it is the risk

`u = randn(rng); x = u * σ` performs **the same two operations in the same order** as
`x = randn(rng) * σ`. Writing the drawn value into a buffer before the multiply is not an algebraic
rearrangement — it is the identical arithmetic with a name attached. ⇒ the shadow-arm machinery draws
once into a unit buffer, and:

- the arm whose `σ` equals the live arm's `σ` reproduces the live sample **bit-for-bit**;
- every other arm costs **zero additional `randn` calls**;
- convention 3's draw topology (count invariant to rung, slider AND target) is untouched, and
  convention 15 is not engaged at all — there is no second stream to seed.

### §2.3 ⚠⚠ THE HAZARD, AND IT IS THE FIRST THING GATE 1 MUST PROVE

**`core/src/detection.jl` has been burned twice by exactly this class of refactor, and it says so in
its own comments:**

- lines 225–228: *"`sfluc = √(SNR/2)` … NB: √(SNR/2), not √SNR·√½ — **they differ in the last bit and
  the slice-1 golden pins the former**"*;
- lines 272–276: the `n_pulses == 1` branch exists *"solely so the floating-point operation order is
  byte-identical to slice 1 — the accumulator below is algebraically equal but **rounds the last bit
  differently, which would break golden replay** of an existing scenario."*

⇒ **RULES FOR THE EDIT, pre-registered:** the same `sfluc` expression, the same draw ORDER, the same
BRANCH structure, the buffer written and read in place. No "while I'm here" tidying of this file.

⇒ **GATE-1 TOOTH #1, PROVED BEFORE ANY OTHER GATE-1 WORK** (not last): the ABSOLUTE golden replays
byte-identically. Convention 2 — the absolute golden catches a draw-ORDER regression that
`test_determinism` structurally cannot. ⚠ If the golden moves by one bit, the mechanism is wrong and
gate 1 stops there.

---

## §3 GATE 0 — THE PRE-REGISTERED PROBES AND THE KILL

⚠⚠ **DECLARED BEFORE THE FLIGHTS, AND THE LOSERS GET PUBLISHED** (slice 53's rule; slice 54's rule
that a pre-registered rule earns its authority the first time it REFUSES something).

### §3.1 The probes

| probe | question | pass condition |
|---|---|---|
| **P0 — SEPARABILITY** | does a unit-buffer rewrite of the point-path draw reproduce the live sample bit-for-bit? | maxdiff **exactly 0.0** on a replayed pass, and the absolute golden unmoved. ⚠ Run FIRST; everything else is void without it. |
| **P0b — ⭐⭐⭐ ARM F IS A TARGET AUTHORED AT F (the sweep's ORACLE)** | does shadow arm `F₂` inside a sweep launched at `F₁` equal a REAL flight authored at `F₂`? | **bit-for-bit equality**, not approximate, on every probed arm. ⚠⚠ **P0 proves the rewrite is INERT; it does NOT prove the ARMS are CORRECT — two different claims, and only P0b tests the second.** Without it an 11-arm curve is 11 numbers whose only warrant is that the arithmetic LOOKS separable. |
| **P1 — THE DENSE SWEEP** | flown on ONE pass, `F ∈ {1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12}`: does the loss COUNT have an interior peak with **more than one arm on it**? | ≥ 3 arms strictly above both the F = 1 end and the F = 12 end, i.e. a peak that is at least 3 arms wide at the shoulders. |
| **P2 — THE LAW** | does the peak land at `F*`, the fineness where the median in-window SNR crosses the detection threshold? | measured argmax within **one sweep step** of `F*`, with `F*` computed from geometry BEFORE the sweep is read. |
| **P3 — THE COMPANION** | is the DURATION gauge still monotone over the dense sweep? | monotone non-decreasing across all 11 arms (slice 49 measured 4 points; 11 is a real test of it). |
| **P4 — REPARAMETERIZATION** | can a constant `rcs_m2` at any value reproduce the peak? | it must NOT. ⚠ Slice 49 §10's P2 already answers this for the DURATION gauge; it is re-asked for the COUNT because the count is a different object. |
| **P5 — SAMPLE-RATE INVARIANCE** | is the count a rule counted in LOOKS, not in ticks? | halve `dt` with the look cadence held: the count must not scale. ⚠ Slice 53's *"a rule counted in SAMPLES changes meaning when the sample rate does"* and slice 42's *"re-fly any narrow threshold at half `dt`"*. |

### §3.2 What each failure does — every branch ships something

| failure | consequence |
|---|---|
| **P0 fails** | ⛔ **HARD STOP, no workaround.** The mechanism is the slice; without bit-identity it is a golden break, and convention 2 is the master check. Record it and pick a different candidate. |
| **P0b fails** | ⛔ **HARD STOP.** A shadow arm that does not reproduce its own real flight means the sweep is measuring an ARTIFACT, and P1–P5 are void — they would be reading a curve of a thing that is not the slider. |
| **P1 fails (peak ≤ 2 arms wide)** | ⇒ **SHIP THE NULL WITH ITS BOUND.** The headline becomes the monotone DURATION gauge over 11 arms, with the count published as *the measured non-monotone companion, peak one arm wide, and here is how wide*. Slice 49's ban is REINSTATED VERBATIM in `docs/PROHIBITIONS.md`, cited to this measurement. **This is a shipping outcome, not a kill.** |
| **P2 fails (peak elsewhere)** | the CURVE still ships if P1 passed, but the turning point is a **fitted number**, and the plan says so in the scenario header. ⚠ The law's refutation is published beside it — slice 55's discipline for a bounded claim. |
| **P3 fails** | slice 49's duration headline is contradicted on a denser sweep ⇒ **that is a finding about slice 49 and it goes in the ledger**, and this slice's two-gauge framing collapses to one. |
| **P4 fails** | ⛔ **KILL.** A constant `rcs_m2` reproducing the peak means the aspect model is not what produces it. |
| **P5 fails** | ⛔ **KILL as a discretization artifact** — the slice-42 verdict, and it is the one verdict this project treats as fatal under both aims. |

### §3.2b ⭐ THE FORM P0b TAKES IS ALREADY WRITTEN — DO NOT INVENT ONE

`core/test/test_track.jl:1211` ships slice 54's version of exactly this tooth, headed **"ARM k IS A
TRACKER AUTHORED AT k (the sweep's oracle)"**, and its comment states the reason in one line: *"The
curve is only quotable if each of its points is the same thing the slider would give you at that
setting."* It flies solo at `k` for a handful of `k`, asserts equality against sweep arm `k`, asserts
the AUTHORED arm agrees with its own index, and then — the part most likely to be dropped —

> ⚠ **NOT A VACUOUS PASS: the arms must actually DIFFER from each other, or the identity above would
> hold for any constant.**

⇒ **P0b copies that shape, including the non-vacuity clause**, and adds the companion tooth beside it
(slice 54's *"THE SWEEP DRAWS NOTHING"*, `test_track.jl:1192`): the profile arrays with the sweep
PRESENT vs ABSENT must be equal, proving the arms cost no draws rather than merely claiming it.

### §3.3 The three arms this slice can ship as, named now

- **Arm A — THE CURVE** (P1 + P2 pass): *the worst body to be is the one sitting on the threshold, and
  here is where that is, computed not fitted.*
- **Arm B — THE CURVE, FITTED** (P1 passes, P2 fails): the same lesson with the turning point measured
  rather than predicted, and the failed prediction published.
- **Arm C — THE NULL** (P1 fails): the monotone duration gauge over a dense sweep, with the count's
  one-arm peak shipped as a bounded null and slice 49's ban reinstated.

⚠ **The obvious arm is A and the pre-registration exists so that A is not the assumed outcome.**

---

## §4 THE WIRE (sketch — gate 1/2 will pin it)

- **Geometry:** slice 49 §9's, now AUTHORED rather than probed — broadside leg at 25 km / 5 km alt,
  250 m/s, turning inbound at 3 °/s from `turn_start_s = 20.0` on a `ManeuveringTarget`.
- **Detector:** the shipped point path — `detect_once` / `pd_analytic` / Swerling-1 / `pfa = 1e-6`,
  10 Hz `revisit_s`.
- ⚠ **`propagation: :free_space` deliberately**, so slice 2's 4/3-Earth horizon mask cannot be
  confused with an aspect drop-out (slice 49 §9's own reason, and convention 9).
- **Gauges, both published:** longest contiguous loss run while CLOSING (seconds and km — slice 49's,
  monotone) and the loss RUN COUNT while closing (this slice's, the curve).
- **Slider:** `rcs_fineness`, with 11 shadow arms drawn as a curve and a marker on the live value —
  slice 54's shape exactly.

---

## §5 OPEN QUESTIONS FOR GATE 0 TO ANSWER, NOT TO ASSUME

1. ⚠⚠ **NOT AN OPEN QUESTION — DECIDED HERE, BEFORE P1, AND THE REASON IS THE DECISION.** The gauge's
   window needs a downrange FLOOR. Slice 53 established that a crossing pass does; slice 49 measured
   the same front-loading on this very geometry (rms 0.172 whole-approach vs 0.0138 in band). ⇒ **the
   floor is fixed in this plan, before the sweep is flown, and it is not revisited after reading the
   curve** — a window chosen after seeing the curve is a FITTED window, which is the identical defect
   P2 exists to avoid. Gate 0's first job is to write the number down here; changing it afterwards
   requires re-running every probe and saying so.
2. Is `F*` computable in closed form from `aspect_rcs` and the threshold, or only numerically? Either
   is fine; the plan must say which before P2 is read.
3. Does the 11-arm sweep need the CFAR path as well, or does the point path carry the lesson alone?
   ⚠ Default: point path only — convention 9, and the CFAR path brings the masker/false-alarm axis
   slice 54 already owns.

---

# ⛔ GATE 0 RAN, 2026-09-08 — **P4 REFUSED IT.** The record, and what survives.

Probes: `W:\temp\claude\slice56\p1_ladder.jl`, `W:\temp\claude\slice56\p2_law.jl`. Flown on the
SHIPPED `scenarios/slice49_aspect.yaml` (not a probe wire), 90 s, seed 49, 900 looks per arm.

## §6.1 The harness oracle passed FIRST, so every number below is comparable to slice 49's

`slice49_aspect.yaml`'s header publishes a seven-point ladder. This probe's gauge reproduced **all
seven columns with Δ = 0.0000 s** and the detected percentages to the published decimal. ⇒ the gauge
IS slice 49's gauge, and the new column beside it is measured on the same footing.

## §6.2 P1 — THE CURVE IS REAL, AND FAR STRONGER THAN THE FOUR-POINT RECORD SUGGESTED

| F | 1.0 | 1.5 | 2.0 | 2.5 | 3.0 | **4.0** | 5.0 | 6.0 | 8.0 | 10.0 | 12.0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **loss COUNT** | 6 | 14 | 29 | 54 | 78 | **96** | 83 | 57 | 36 | 26 | 21 |
| longest loss (s) | 0.20 | 0.20 | 0.20 | 0.30 | 0.60 | 1.30 | 2.80 | 5.30 | 36.50 | 40.20 | 46.60 |
| median in-window SNR (dB) | 30.87 | 26.15 | 24.12 | 21.57 | 19.13 | 14.87 | 11.34 | 8.36 | 3.56 | −0.23 | −3.35 |

**P1 PASSES** — a smooth 16× rise to an interior peak and a 4.6× fall, **eight arms strictly above
both ends** against a pre-registered bar of three. ⚠ The 41 → 133 → 53 → 42 in `docs/plans/slice49.md`
§9 was measured on a DIFFERENT (probe) wire; on the shipped wire the peak is not one arm deep.

**P3 PASSES** — the duration gauge is monotone non-decreasing on all eleven arms, so slice 49's
headline survives a sweep three times denser than the one that established it.

**P5 PASSES, exactly** — halving `dt` to 5.0e−4 with the look cadence held leaves the count
**identical** (54/54, 96/96, 57/57) and the longest loss identical. Not a discretization artifact;
the gauge is counted in LOOKS and behaves like it.

**P2 PASSES** — pre-registered before the sweep was read: Swerling 1 at `pfa = 1e−6` gives
`SNR* = ln(pfa)/ln(0.5) − 1 = 18.9316 = 12.7719 dB`. The median-SNR column crosses `SNR*` at
**F* = 4.5943**; the count's argmax is at **F = 4.0**, inside the pre-registered one-step window
[3.0, 5.0]. **The turning point is predicted, not fitted.**

## §6.3 ⛔ P4 FAILED — AND THE PRE-REGISTERED RULE IS HONOURED, NOT ARGUED WITH

**The question (written before the flights): can a CONSTANT `rcs_m2`, with the shape key absent
entirely, reproduce the peak? Pre-registered answer: it must NOT.**

| `rcs_m2` (no shape key) | 4.0 | 1.0 | 0.4 | 0.2 | **0.1** | 0.05 | 0.02 | 0.01 | 0.004 | 0.001 |
|---|---|---|---|---|---|---|---|---|---|---|
| **loss COUNT** | 6 | 28 | 56 | 81 | **112** | 98 | 80 | 66 | 35 | 4 |
| longest loss (s) | 0.20 | 0.20 | 0.50 | 0.80 | 1.10 | 3.40 | 10.10 | 7.80 | 5.10 | 4.80 |
| median SNR (dB) | 30.87 | 24.85 | 20.90 | 17.89 | **14.88** | 11.87 | 7.89 | 8.33 | 7.77 | 4.91 |

⇒ **A DIM SPHERE DOES NOT MERELY REPRODUCE THE PEAK — IT BEATS IT: 112 against 96.**

⚠⚠ **AND THE MATCHED PAIR IS THE PART THAT SETTLES IT, NOT THE HEIGHTS.** At `rcs_m2 = 0.1` the
median in-window SNR is **14.881 dB**; at `rcs_fineness = 4.0` it is **14.870 dB** — the same
picture to a hundredth of a dB — and the counts are 112 and 96. **The count is a function of where
the median echo sits relative to the threshold, and it does not care what put it there.** Shape is
one road; dimness is another; they land on the same curve.

⇒ **THE SHAPE HEADLINE IS DEAD FOR THIS GAUGE.** Slice 39's rule: a knob that another shipped knob
reparameterizes cannot carry the slice. The count curve is not a lesson about *which way a target is
pointing*; it is a lesson about *the detector's threshold*, and `rcs_fineness` is the more expensive
of two ways to demonstrate it.

⚠ **WHAT IS NOT KILLED, stated so nothing is over-read:**
- **Slice 49's DURATION headline is untouched and is re-confirmed here.** The dimmest constant
  (`rcs_m2 = 0.001`) reaches only **4.80 s** of longest loss where `rcs_fineness = 12` reaches
  **46.60 s** — a **9.7×** separation, on top of the ladder P1a reproduced exactly. A constant echo
  still cannot buy the long blind spot; only the shape can. ⇒ slice 49's own P2 stands.
- **`rcs_fineness` itself is untouched** — MODEL test unchanged, read every tick by both consumers.
- **The three PASSING probes stand as measurements** and are quotable: the count curve exists, it is
  `dt`-invariant, and its turning point is predicted by the threshold crossing.

## §6.4 ⭐ THE FINDING THIS BOUGHT, AND IT IS WORTH MORE THAN THE HEADLINE IT COST

**TWO GAUGES OVER THE SAME PICTURE ANSWER DIFFERENT QUESTIONS, AND ONLY ONE OF THEM CAN NAME A
CAUSE.** How OFTEN you lose a target tells you *that its echo is sitting on your threshold* and
cannot tell you *why*. How LONG you lose it for separates the reasons: a dim target is lost briefly
and often, a slender one is lost rarely and for a minute. ⇒ **the count is a symptom gauge and the
duration is a diagnostic one**, and a scenario that ships the count alone would let a viewer read a
cause that is not there.

⚠ This is a candidate, not a slice, and it is written here rather than promoted, because inventing a
new headline in the same breath as a kill is the failure this project keeps records about. It goes to
`docs/DEFERRALS.md` as a raised candidate with its evidence, and the next slice is picked from that
file on its merits.

## §6.5 VERDICT

**GATE 0 CLOSED. THE SLICE DOES NOT SHIP.** Four probes passed and the fifth refused it, which is
what the fifth was written for — slice 54's rule that *a pre-registered rule earns its authority the
first time it REFUSES something*, applied to a rule written two commits before the measurement
existed. P0/P0b (the shadow-arm mechanism) were **never run**: they are gate-1 implementation teeth
and there is nothing left to implement. ⚠ The separability argument in §2 is UNVERIFIED and must not
be quoted as measured — it was read out of the code, not flown.

⚠⚠ **AND THE BAN STANDS.** `docs/plans/slice49.md`'s *"Never quote the count"* is **reinstated
verbatim**, now with a second and stronger reason than the one it was written with: not only is the
count non-monotone, it is **not specific to the shape at all**. §0.2's conditional lift lapses.
