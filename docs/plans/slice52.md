# Slice 52 — **HOW WIDE SHOULD A SEEKER SEARCH?** (slice 48's reserve axis, `seeker_search_coverage_deg`)

**STATUS: GATE 0 PASSED + GATE 1 BUILT & GREEN, 2026-08-31. THE SLICE LIVES; GATES 2–3 NOT YET BUILT.** Seven probes in
`M:\claud_projects\temp\slice52\`. **No core change was made and none is needed** — the key already
exists, is read every tick and is already on the wire; what is missing is a showcase. Verdict table
in §IX.

The candidate, in `M:\claud_projects\EW\docs\DEFERRALS.md` §"New candidates raised by slice 48":

> **THE SEARCH COVERAGE (half-amplitude S) AS THE AXIS.** Slice 48 authors it at 25° and §0.7 kept
> it in reserve. Slice 43 measured that a wrong-side guess pays `2S` in travel and *"the price
> accelerates"*: too wide a coverage is a search that arrives too late, which is slice 48's lesson on
> a knob whose domain is not squeezed by a 240 °/s servo. ⚠ Its own gate 0 must settle whether the
> coverage is measured against the LIVE sweep centre (which walks away from the target while the
> search runs) or a frozen one — slice 48 ships the live centre and never varied S.

**THE PROPOSED LESSON, in one sentence.** *A sweep must be sized to the uncertainty you actually
have: too narrow never reaches the target at all, and every degree wider than necessary is paid
TWICE, in travel you spend before you ever look at the right place.*

⚠ That is a claim about a **two-sided** knob, which is what would make it different from slice 48's
one-sided one (faster is always better up to the servo's own limit). If it turns out one-sided, this
is 48's lesson with a different label and the slice dies here.

---

## §0 THE MODEL TEST — SETTLED BY INSPECTION, NOT BY A PROBE

The two-test rule's MODEL half (`docs/DEFERRALS.md`, the 2026-08-18 re-verdict) asks whether the
parameter is READ by the physics every tick and correct in its own units. It is, and this is an
inspection result rather than a measurement:

- `core/src/missile.jl:2954` calls `search_sweep(t_srch, ρ_srch, deg2rad(get(c,
  :seeker_search_coverage_deg, 0.0)))` — a `get` off the comp bag on **every searching tick**, with
  no accumulator and no value baked at search onset (`search_sweep` recomputes its phase from
  `t_since_start`, `core/src/frames.jl:1078`). A live drag therefore moves the very next offset.
- Units: authored DEGREES at the boundary, converted once at the call site, radians inside — the
  `gimbal_*_deg` posture (slice 35's rule). Emitted back as `search_coverage_deg`
  (`core/src/missile.jl:3585`).
- Degenerates are owned by the kernel (`S ≤ 0 ⇒ 0.0`, non-finite ⇒ `0.0`), so convention 5 is
  already satisfied for a slider.

⇒ **MODEL: PASS, on inspection.** The whole probe budget goes to the LESSON test. ⚠ This is NOT a
finding — it is the reason there is nothing to build at gate 0 but a scenario.

---

## §0.5 THE PRE-REGISTERED FALSIFIERS — fixed in writing BEFORE any probe ran

Written here first, then copied into each probe file's own header (slice 41's discipline, and slice
51 §0's form). ⚠ Ordered by lethality, not by convenience — *fly the kill risk before the mechanism*
(`docs/LESSONS.md:13`).

- **F1 — THE CLIFF MUST SURVIVE A HALVED STEP.** The headline is *a sweep too narrow never finds the
  target*, i.e. a THRESHOLD `S*`. Slice 42 died because its threshold was one integration step wide
  (`ω_LOS·dt`, halving with `dt`), and slice 51 died because a boundary FLIPPED at `dt/2`. ⇒ re-fly
  the cells bracketing `S*` at `dt = 5e-4` and quote the movement. **If `S*` moves by more than one
  ladder step, the slider's floor is a discretization artifact and the slice is dead.** *(P2 — probe
  TWO, on the advisor's instruction, not probe six.)*
- **F2 — REACH vs DEADLINE: the only thing a RATE cannot imitate.** ⚠⚠ **This replaces the
  exchangeability test this plan was first going to pre-register** (*"can a `ρ` retune reproduce an
  `S` arm's curve?"*), which is slice 41's confounded-lever trap in new clothes: both knobs enter
  `t_lock ≈ (2S + d)/ρ`, so a `ρ` retune reproduces any single `S` arm's lock time **by
  construction**, and answering "yes" would kill the slice for a reason that is arithmetic rather
  than physics (`docs/LESSONS.md:45`, *re-check the falsifier's WORDING*). The honest discriminator
  is the FAILURE MODE at the floor:
  - a **rate** floor is a **DEADLINE** — the head would cover the gap given enough flight, and the
    engagement ends first;
  - a **coverage** floor is a **REACH** — the target sits outside the swept band and is never
    covered **at any duration**.

  ⇒ Fly both floors with the engagement EXTENDED. **If a sub-threshold `S` eventually acquires, the
  two knobs fail the same way and this is slice 48 relabelled.** *(P3.)*
- **F3 — THE TRUNNION MUST NOT BE THE SLIDER.** The cue sits at 25–31° of BODY angle on this
  geometry and `gimbal_stop_deg` is 45.0, so `cue + S` crosses the mechanical stop inside the
  interesting domain. Slice 48's own gate 0 read a clamped head (commanded 48°, head at 29.998°) as
  *"the search does not work"* (`docs/LESSONS.md:436`, the FOURTH occurrence). ⇒ carry a
  CONTAMINATION column — clamped ticks as a percentage of searching ticks — and read it **before**
  the result column (slice 41's rule), then VARY the stop to prove non-contamination rather than
  argue it. **The slider's usable ceiling is whatever `S` first makes the stop bind.** *(P4, run
  early.)*
- **F4 — THE GAUGE, AND THE REGION IT MAY BE READ IN.** The gauge is `search_t_lock_s` (48 measured
  it monotone in `ρ` over the whole domain) plus authority as 48's THREE-REGION verdict
  (never / pinned / cheap), **never the miss** — banned on this arc by 44, 46, 48 and re-earned by
  50. ⚠ And slice 51's correction applies: *a slice may read a number AT the loss and may not SCORE
  one on the far side of a blind phase.* This wire's blind phase is MIDCOURSE-GUIDED rather than an
  open-loop coast, so post-lock authority should be legal here — **but that must be MEASURED, not
  assumed**: slice 46 P0 found `|a_cmd|` exactly 0.0 for 6955 consecutive blind ticks on the
  pre-47 wire. ⇒ P0 prints `midcourse_active` and `a_cmd` through the blind phase, and the clearance
  is stated explicitly or the gauge changes. *(P0.)*
- **F5 — THE NULL MUST BE IN THE SAME TABLE.** Slice 42's headline died because nobody compared its
  result cell against the do-nothing cell in the same column (`docs/LESSONS.md`). Every ladder here
  carries the `S = 0` row (the kernel's own degenerate — a head that does not sweep) and slice 48's
  authored `S = 25` row, in the same columns as the arms. **A row whose numbers equal the null row's
  IS the null row wearing a label.**
- **F6 — MONOTONICITY, AND WHAT IT IS ALLOWED TO MEAN.** `k` (28), `ω_n` (40), `σ_seek` (25), the
  loss count (49) and miss-vs-`rcs_fineness` (50) were all disqualified as SLIDERS for reversing.
  ⚠ This axis is expected to be non-monotone BY DESIGN (a floor region, then an optimum, then a
  ramp) — that is the lesson, not a defect. The discipline it inherits: the gauge above the cliff
  must not CHATTER, and **the OPTIMUM'S LOCATION is a boundary and may not be the headline** (F1's
  reason, one level up).

---

## §I — P0: THE WIRE. **F4 IS CLEAR — THE MISSILE IS STEERING WHILE BLIND.**

`p0_wire.jl`, at slice 48's authored `S` = 25.0, over slice 48's own slider positions.

**The instrument first.** The probe reproduces slice 48's shipped table to every printed digit —
`t_lock` 2.0400 / 1.0230 / 0.9370 / 0.5030 / 0.2670 at ρ = 36 / 60 / 65 / 120 / 240, CPA
677.27 / 32.09 / 0.48 / 0.27 / 0.31, and the null 1039.88 at ρ = 0. ⭐ That is the harness
validating itself against a shipped ledger before any new number is read off it.

**F4, the legality question, ANSWERED AND CLEAR.** Through the whole blind phase (937–2040 ticks
depending on ρ): `midcourse_active` = **100.0 %** of ticks and `|a_cmd|` peaks at **15.243 m/s²**,
identical on every arm. ⇒ this wire's blind phase is a **guided midcourse, not an open-loop coast**,
so slice 51's ban (*may not SCORE a number on the far side of a blind phase*) does **not** reach it,
and post-lock authority is a legal gauge here. ⚠ Stated as a measurement because slice 46's P0
measured the opposite on the pre-47 wire (`|a_cmd|` exactly 0.0 for 6955 consecutive blind ticks).

## §II — P1: THE LADDER. THE AXIS IS REAL, AND ITS SHAPE IS TWO-SIDED

`p1_ladder.jl`, `S` ∈ [0, 45] at two authored rates. Every row carries the contamination column
(F3) to its left and the null row above it (F5).

**At ρ = 60 °/s the coverage spans the entire three-region verdict on its own:**

| `S` ° | clamp % | `t_lock` s | max \|a\|/a_max | mean | sat % | CPA m |
|---|---|---|---|---|---|---|
| 0 (NULL) | 0.00 | **NEVER** | — | — | — | 1039.88 |
| 2 | 0.00 | **NEVER** | — | — | — | 1039.88 ← **== NULL** |
| 4 | 0.00 | **NEVER** | — | — | — | 1039.88 ← **== NULL** |
| 6 | 0.00 | 0.2990 | 0.2316 | 0.0808 | 0.0 | 0.07 |
| 10 | 0.00 | 0.4490 | 0.2484 | 0.0982 | 0.0 | 0.03 |
| 16 | 0.00 | 0.6760 | 0.2820 | 0.1404 | 0.0 | 0.07 |
| 20 | 0.00 | 0.8290 | 0.3050 | 0.1916 | 0.0 | 0.42 |
| 25 (slice 48's) | 2.43 | 1.0230 | 1.0000 | 0.3902 | 0.2 | 32.09 |
| 30 | 18.97 | 1.2220 | 1.0000 | 0.5829 | 17.4 | 171.73 |
| 35 | 0.88 | 1.4260 | 1.0000 | 0.6484 | 18.6 | 309.79 |
| 40 | 4.37 | 1.6380 | 0.9290 | 0.6348 | 0.0 | 446.05 |
| 45 | 10.72 | 1.8590 | 0.7815 | 0.5918 | 0.0 | 578.10 |

- ⭐⭐ **`t_lock` IS EXACTLY LINEAR IN `S`, AT SLOPE `2/ρ`.** 0.2990 → 1.8590 s over `S` = 6 → 45 is
  **0.04000 s/° = 2/60** to four digits, and the ρ = 240 ladder gives 0.00886 against `2/240` =
  0.00833. ⇒ **slice 43's banked `2S` wrong-half travel law, measured on the shipped kernel for the
  first time** — 43 measured it on an 8 °/s servo over a ~7 s window, this is 60–240 °/s over ~2 s.
- ⭐ **The direction of the cost is OPPOSITE to slice 48's knob.** 48's rate is monotone BETTER
  upward (buy a faster servo). Coverage is monotone WORSE upward, and its best value sits
  **immediately above a cliff** where the missile gets nothing at all.
- ⚠ **At ρ = 240 the whole ladder is benign** — `t_lock` 0.113 → 0.441, every cell hits, authority
  0.213 → 0.247. The coverage only costs anything when the servo is not fast enough to absorb it.

## §III — P1b: **THE FLOOR IS NOT WHAT THE PLAN SAID IT WAS**, and an instrument bug caught by it

The plan predicted the floor as a REACH failure read off `search_deficit_deg`. P1 reported the
deficit at search onset as **1.3423°** and a ±2° sweep still never locking — a deficit of 1.34°
apparently inside a band of 2° that never closes. `docs/LESSONS.md:436` (*when a head-pointing probe
reports "never", LOG THE HEAD'S ACTUAL ANGLE BEFORE BELIEVING IT* — the FOURTH occurrence) says dump
the series, so `p1b_series.jl` did.

- ⚠⚠ **THE INSTRUMENT WAS WRONG, NOT THE PHYSICS: `gimbal_fov_deg` IS THE WINDOW'S RADIUS, NOT ITS
  FULL CONE** (`missile.jl:2178`, `fov_h = deg2rad(gimbal_fov_deg)`). The probe was thresholding at
  5°. The lock at `S` = 6 happens at `head_off` = **9.9759°** against a window of **10.0**, and the
  `S` = 4 arm's closest approach over the whole flight is **10.4856°** — it misses the rim by half a
  degree. Both numbers are nonsense against a 5° threshold and exact against a 10° one.
- ⭐⭐ **THE REAL MECHANISM IS A RACE, NOT A STATIC GEOMETRY.** The deficit **GROWS** while the search
  runs — 1.3423° at onset to 8.155° one second later, ~6.8 °/s — because the sweep centre is the
  LIVE belief and the belief is a dead-reckoned snapshot walking away from the truth. The sweep opens
  the WRONG way first (slice 48's authored geometry), so the head reaches its negative extreme at
  `3S/ρ`, and it locks iff `S` ≥ deficit(`3S/ρ`). Measured: `S` = 6 at ρ = 60 locks at 0.2990 s
  against a predicted `3S/ρ` = **0.300 s**.

## §IV — P2: **F2 DOES NOT FIRE — AND IT DOES NOT DISCRIMINATE EITHER**

F2 asked whether a sub-threshold COVERAGE ever acquires when the engagement is lengthened (a
DEADLINE) or never does at any duration (a REACH). The duration lever is the closing speed.

| arm | `vscale` | min `head_off` ° | window | verdict |
|---|---|---|---|---|
| `S` = 4, ρ = 60 | 1.00 / 0.75 / 0.50 | 10.4856 / 14.2362 / 21.8198 | 10.0 | NEVER / NEVER / NEVER |
| `S` = 2, ρ = 60 | 1.00 / 0.75 / 0.50 | 11.3554 / 15.1073 / 22.7080 | 10.0 | NEVER / NEVER / NEVER |
| `S` = 25, ρ = 20 | 1.00 / 0.75 / 0.50 | 11.3554 / 15.1073 / 22.7080 | 10.0 | NEVER / NEVER / NEVER |
| `S` = 25, ρ = 30 | 1.00 / 0.75 / 0.50 | 11.3554 / 14.1004 / 16.5100 | 10.0 | NEVER / NEVER / NEVER |

- **F2 does not fire**: no sub-threshold coverage row turns COVERED. But **the rate floor does not
  turn COVERED either**, so the probe as designed cannot tell the two failures apart. ⭐ On this wire
  **both floors are REACH failures against a moving band** — §III's race, lost by the coverage in one
  case and by the rate in the other.
- ⚠⚠ **AND THE LEVER IS CONFOUNDED — slice 41's objection, in a new place.** Slowing the closure
  does not buy search time at a fixed deficit; it lengthens the BLIND PHASE, and the handover error
  is the picture error × the time spent blind (slice 47's law), so the deficit the search must cover
  grows with the very lever meant to relieve it. Every `min head_off` column above gets **worse**,
  monotonically, as more time is given. A duration probe on this wire measures a different
  engagement, not a longer one.
- ⚠ One instrument defect fixed mid-probe and worth recording: the first run printed `min head_off`
  = **0.0000** and a verdict of **COVERED** for arms that never searched at all — `head_off_deg` is
  0.0 on ticks where the gimbal block never ran. **The defaulted-zero trap reading as a PASS**
  (CLAUDE.md §harness traps, slice 49's occurrence). Such an arm now prints NO SEARCH.

### ⚠⚠ F2 IS RETIRED, AND THIS IS WHAT REPLACED IT

`docs/LESSONS.md:400` — *retract a rule you inherited if the wire refuses it, and say what replaced
it.* F2 is retired as **unanswerable on this wire**, not as failed. What replaces it is a comparison
P1 already contains, needing no new probe:

⭐⭐⭐ **THE COVERAGE'S COST IS CONTINGENT ON THE RATE, AND ITS SIGN IS OPPOSITE.** At ρ = 240 °/s the
whole coverage ladder is benign — every cell hits, authority 0.213 → 0.247. At ρ = 60 the SAME
ladder spans never → hit → pinned-and-miss, CPA 0.07 → 578 m. If the two knobs were exchangeable the
ladder would carry the same verdict structure at every ρ, merely shifted; it does not. **They
COMPOSE, they do not SUBSTITUTE.** And the directions differ: the rate is monotone BETTER upward
(*buy the fastest servo you can afford*), the coverage monotone WORSE upward (*do not sweep wider
than your handover error requires*). Slice 48's knob cannot produce the second instruction, because
it has no expensive end.

⭐ **AND THE ONE-LINE MECHANISM, which is why both floors collapse into one failure:** the deficit
grows monotonically while the search runs, so **later excursions are strictly worse than earlier
ones** — it is FIRST-EXCURSION-OR-NEVER. The head reaches its first negative extreme at `3S/ρ`
(measured: `S` = 6, ρ = 60 locks at 0.2990 s against a predicted 0.300), and if the band does not
cover the target there, no later sweep will.

## §V — P3: **F1 DOES NOT FIRE.** THE CLIFF IS STEP-INVARIANT

`p3_cliff.jl`, ρ = 60, `S` refined to 0.25° across 3.50–7.50, every cell flown at BOTH `dt` = 1e-3
and `dt` = 5e-4.

| `S` ° | `t_lock` @1e-3 | `t_lock` @5e-4 | ratio | min `head_off` @1e-3 | @5e-4 |
|---|---|---|---|---|---|
| 3.50–4.75 | **NEVER** | **NEVER** | — | 10.7677 → 10.0303 | 10.7688 → 10.0330 |
| **5.00** | **0.2660** | **0.2655** | 0.99812 | 0.0026 | 0.0034 |
| 5.50 | 0.2810 | 0.2800 | 0.99644 | 0.0022 | 0.0028 |
| 6.00 | 0.2990 | 0.2985 | 0.99833 | 0.0010 | 0.0009 |
| 7.50 | 0.3560 | 0.3550 | 0.99719 | 0.0001 | 0.0003 |

- ⭐⭐⭐ **`S*` = 5.00° AT BOTH STEP SIZES. MOVEMENT: 0.00°, ZERO refined steps.** No cell flips
  LOCK ↔ NEVER between the columns, and every lock time agrees within 0.4 %. **This is where slices
  42 and 51 died and this axis does not.** ⚠ The distinction from 42 is structural rather than
  lucky: 42's band was `ω_LOS·dt` — a width made OF the step — while `S*` is set by an angular race
  between the sweep and the growing deficit, and neither term contains `dt`.
- ⭐⭐ **THE APPROACH TO THE CLIFF IS CONTINUOUS AND READABLE.** `min head_off` walks 10.7677 →
  10.0303 across `S` = 3.50 → 4.75 against a 10.0° window — the floor is not a flat dead zone but a
  region that says HOW CLOSE the head came. ⚠ With a limit: below `S` ≈ 3 the column is pinned at
  11.3554 (the sweep never brings the head nearer than where it started), so the instrument covers
  the upper part of the floor, not all of it.

## §VI — P4: **F3 DOES NOT FIRE.** THE TRUNNION IS NOT IN THE MEASUREMENT

`p4_stop.jl`. Slice 41's rule — *to prove a clamp is not setting your metric, VARY THE CLAMP, don't
argue.* The same ladder at `gimbal_stop_deg` = 45 (slice 48's authored hardware), 60 and 90:

| `S` ° | `t_lock` @stop 45 | @60 | @90 | clamp % (45 / 60 / 90) | spread |
|---|---|---|---|---|---|
| 25 | 1.0230 | 1.0230 | 1.0230 | 2.43 / 0.00 / 0.00 | **0.0000 s** |
| 30 | 1.2220 | 1.2220 | 1.2220 | 18.97 / 14.87 / 3.72 | **0.0000 s** |
| 35 | 1.4260 | 1.4260 | 1.4260 | 0.88 / 16.22 / 0.00 | **0.0000 s** |
| 45 | 1.8590 | 1.8590 | 1.8590 | 10.72 / 0.09 / 0.00 | **0.0000 s** |

- ⭐⭐⭐ **THE GAUGE IS INVARIANT TO A 2× CHANGE IN THE MECHANICAL TRAVEL, ON EVERY ROW, INCLUDING THE
  ROW WHERE THE STOP BINDS 19 % OF SEARCHING TICKS.** Spread 0.0000 s throughout.
- ⭐⭐ **AND THE REASON IS WORTH KEEPING: A POSITIONAL SWEEP CANNOT BE DELAYED BY A STOP.**
  `search_sweep` returns a phase computed from `t_since_start` with no accumulator, so a clamped head
  does not fall behind its own schedule — it resumes the commanded angle the instant the command
  comes back inside the travel, and the servo (240 °/s against a 60 °/s sweep) has the margin to do
  it. The stop removes travel the head was wasting on the wrong half anyway. ⚠ This is honest only
  while the servo is faster than the sweep; on slice 35's 8 °/s head it would not be.

## §VII — P5: **F5 HOLDS — THE FLOOR IS BIT-IDENTICAL TO THE NULL, AND STILL NOT EMPTY**

`p5_null.jl`, position compared tick-by-tick against the `S` = 0 arm over 8926 ticks:

| `S` ° | 0 | 1 | 2 | 3 | 3.5 | 4 | 4.5 | 4.75 | 5.00 |
|---|---|---|---|---|---|---|---|---|---|
| max abs Δpos, m | 0.000e+00 | 0.000e+00 | 0.000e+00 | 0.000e+00 | 0.000e+00 | 0.000e+00 | 0.000e+00 | 0.000e+00 | 1.065e+03 |
| sweep reached ± | 0.00 | 1.00 | 2.00 | 3.00 | 3.50 | 4.00 | 4.50 | 4.74 | 5.00 |
| min `head_off` ° | 11.3554 | 11.3554 | 11.3554 | 11.0245 | 10.7677 | 10.4856 | 10.1853 | 10.0303 | 0.0026 |

⭐ **Every floor cell is BIT-IDENTICAL to the null while the head is demonstrably sweeping** — the
`sweep reached` row exists precisely so a zero difference cannot be misread as a head that did
nothing. Slice 48's own finding, re-measured on a different knob: nothing the head does reaches the
guidance until something is LOCKED.

## ⭐⭐⭐ §VIII — P6: THE POSITIVE CLAIM. **THE RIGHT COVERAGE IS SET BY THE PICTURE ERROR**

`p6_match.jl`. `midcourse_err_gain` is slice 47's authored picture quality, read every tick
(`missile.jl:1226`). `S*` is the narrowest coverage that still acquires, bracketed to 0.25°.

| `midcourse_err_gain` | deficit @onset ° | **`S*` °** | `t_lock` @`S*` | `t_lock` @25° | CPA @`S*` | CPA @25° |
|---|---|---|---|---|---|---|
| 60 / 100 / 120 | — | **no search needed** | — | — | — | 0.01 / 0.22 / 0.16 |
| **140** (slice 48's) | 1.3423 | **5.00** | 0.2660 | 1.0230 | 0.29 | 32.09 |
| 160 | 2.9641 | **8.00** | 0.4150 | 1.0750 | 0.12 | 200.84 |
| 180 | 4.6069 | **11.25** | 0.5850 | 1.1290 | 1.32 | 374.67 |
| 200 | 6.2697 | **15.75** | 0.8050 | 1.1850 | 254.00 | 552.87 |
| 220 | 7.9725 | **22.25** | 1.1320 | 1.2450 | 650.49 | 740.62 |

- ⭐⭐⭐ **`S*` IS NOT A CONSTANT. IT TRACKS THE HANDOVER UNCERTAINTY, MONOTONICALLY AND STEEPLY**
  — 5.00 → 22.25° while the inherited deficit goes 1.34 → 7.97°, i.e. **`S*` runs 2.4–3.7 × the
  deficit MEASURED AT ρ = 60 °/s** — ⚠ that spread is this rate's outcome, NOT a coefficient and
  NOT a law, and it must not be quoted as one (`docs/LESSONS.md`: a bound quoted as one number will
  be hard-coded by the gate that reads it). The multiplier is the race: the sweep must cover not the deficit it inherits but the
  deficit it will face after `3S/ρ` seconds of travel. ⇒ *how wide should the sweep be?* has an
  answer only the ENGAGEMENT can give. **A sweep RATE carries no such rule** — faster is better at
  every picture error — which is the separation from slice 48 that F2 failed to produce.
- ⭐⭐ **THE PRICE OF NOT MATCHING, in the legal currency:** at a picture error of 160 the matched
  8° sweep locks in 0.4150 s and slice 48's authored 25° sweep in 1.0750 s — **2.6× later on the
  same engagement**, for coverage that was looking somewhere the target provably was not.
- ⭐⭐ **A THIRD REGION AT THE BOTTOM, AND IT IS SLICE 47's OWN RESULT:** below a picture error of
  ~130 the handover lands INSIDE the window, the missile locks the instant the receiver opens, and
  no sweep is needed at all. **A search costs time, and time is worthless when you were launched
  already able to see** (`docs/DEFERRALS.md`, the 43 block's own wording) — here measured as the
  bottom of a slider's domain rather than as a block.
- ⚠ **MATCHING BUYS A LOCK, NOT AN INTERCEPT.** At err_gain 200 and 220 even the matched sweep
  arrives too late to convert (CPA 254 / 650 m). The rule is *size the sweep to the uncertainty*,
  never *a matched sweep saves the shot*.
- ⚠ **AN INSTRUMENT DEFECT THIS PROBE CAUGHT, AND IT IS A NEW SHAPE OF AN OLD TRAP.** Its first run
  printed `deficit@onset` = 104.3° and `head_off@onset` = 178.3° for err_gain = 60, `t_lock` NEVER,
  **beside a CPA of 0.01 m**. All three numbers were correct and none was about the search: with a
  good enough picture the missile never searches during the engagement, so the only search episode on
  the wire is a POST-INTERCEPT one against a target now astern. A reader would have read "never
  acquired" next to a 1 cm hit. ⇒ **an episode-scoped gauge must assert the episode it thinks it is
  in, not merely find one.**

---

## §IX — THE GATE-0 VERDICT: **THE SLICE LIVES.**

| test | result |
|---|---|
| **MODEL** (two-test rule) | **PASS by inspection** — read every tick, correct units, degenerates owned by the kernel (§0) |
| **F1** cliff at `dt/2` | **PASS** — `S*` = 5.00° at both step sizes, zero movement, no flips (§V) |
| **F2** reach vs deadline | **RETIRED, unanswerable** — replaced by the composition result (§IV) |
| **F3** trunnion | **PASS** — `t_lock` invariant across a 2× stop, spread 0.0000 s (§VI) |
| **F4** gauge legality | **PASS** — the blind phase is midcourse-guided, 100 % of ticks, a_cmd ≤ 15.243 (§I) |
| **F5** the null | **PASS** — the floor is bit-identical to `S` = 0 over 8926 ticks (§VII) |
| **F6** chatter | **PASS** — `t_lock` strictly monotone in `S` on every ladder, no reversal |
| **LESSON** (two-test rule) | **PASS** — `S*` tracks the picture error 5.00 → 22.25° (§VIII) |

**THE LESSON, as gate 0 leaves it:** *A search pattern must be SIZED to the handover uncertainty, not
maximised. Too narrow and the sweep never reaches a target whose angle is running away from it; every
degree wider is paid TWICE in travel across a half of the sky the target is not in; and the right
width is not a number in the seeker's datasheet — it is set by how good the picture was when the
missile went blind.*

**WHAT GATES 1–3 WOULD BUILD.** No core change: the key ships, is read every tick and is already
emitted. What is missing is a SHOWCASE — `scenarios/slice52_*.yaml` (slice 48's geometry, ρ AUTHORED
at 60 °/s, `seeker_search_coverage_deg` as THE slider over roughly 0–45°), a view that draws the
swept band against the inherited deficit, and slice 48's four proofs. ⚠ Convention 9: the picture
error stays an authored FIXTURE, exactly as slice 48 retired slice 47's slider to a constant.

---

## §X — GATE 1 (2026-08-31): **THE COVERAGE AXIS IS NOW A LAW IN THE REPO, NOT A NUMBER IN THIS FILE**

`core/test/test_search.jl`, a new top-level section between slice 48's gate-1 and gate-2 blocks.
**224 teeth, suite 18175 → 18399, PASS 18399 / 18399 in 7m28s.** ⚠ NO CORE FILE WAS TOUCHED — this
gate is pure enforcement of what §§I–VIII measured, which is the whole reason it could be written
before a scenario exists.

**WHY A GATE 1 AT ALL, GIVEN §IX's "no core change".** Because gate 0's results lived in exactly two
places, and neither is the repo: this document, and probes under `M:\claud_projects\temp\slice52\`.
The ritual's *new model ⇒ new test* is not satisfied by a measurement that only a plan remembers.
⭐ Slice 48 shipped `search_sweep` and varied only its RATE; every claim slice 52 makes is about the
OTHER argument, and the file had no tooth on it beyond `|offset| ≤ S` and the period.

### THE FIVE TEETH, AND WHAT EACH ONE STOPS

1. **THE FIRST NEGATIVE EXTREME IS AT `3S/ρ`, AND NOTHING EARLIER REACHES IT.** §IV's
   FIRST-EXCURSION-OR-NEVER is a claim about *when* the band first covers the wrong side, and it was
   resting on a single flown coincidence (`S` = 6, ρ = 60 locking at 0.2990 s against a predicted
   0.300). It is now an identity, exact on binary-exact `(ρ, S)`.
2. **THE SCALE LAW — `t` enters only through `ρt/S`**, i.e. the wave is `S ·` the unit triangle.
   ⭐⭐ This is the STRUCTURAL reason §II's `t_lock` came out linear at slope `2/ρ`; pinning it here
   makes the flown 0.04000 s/° a CONSEQUENCE rather than a fit, which is the form
   `docs/LESSONS.md` asks a measured coefficient to be shipped in.
3. **THE `2S` WRONG-HALF LAW — first cover of a target at `−a` costs `(2S + a)/ρ`**, with `2/ρ` as
   its derivative in `S` at fixed `a`. Slice 43 banked this on an 8 °/s servo over ~7 s; gate 0 read
   it off the shipped kernel at 60–240 °/s; it is now arithmetic that cannot drift.
4. **THE MODEL TEST's KERNEL HALF.** ⚠⚠ §0 recorded MODEL as **"PASS by inspection"** — a
   code-reading, and the two-test rule's model half is its ONLY outright kill. It is a tooth now.
5. **`S ≤ 0` PINNED ACROSS THE PHASE**, not at one time. §6 pinned it at a single `t`, which was
   enough while the coverage was an authored constant; it is this slice's dragged knob, so its floor
   is reached MID-SWEEP from an arbitrary phase.

⚠ **ONE CLAIM DELIBERATELY NOT WRITTEN AS A TEST.** The REACH half — *`S < a` and `−a` is never
reached at any `t`* — is slice 48's tooth 2 (`|offset| ≤ S`) restated in this slice's currency.
Convention 11 bans a tautology dressed as a tooth, so it is a comment deriving it, not an `@test`.

### ⭐⭐ THE ONE REAL FINDING: **A COVERAGE CHANGE IS INVISIBLE UNTIL THE FIRST REVERSAL**

Tooth 4 FAILED on its first run, and the reason is a property of the wave this plan had not written
down anywhere: **on the opening leg the offset is `ρt` and `S` does not enter the arithmetic at
all.** Read at `t` = 0.3 s, a 25.0° sweep and a 25.5° sweep both return exactly **18.0**, and the
tooth built to prove the knob is LIVE reads it as a DEAD KNOB — the slice-36 class, arrived at from
the opposite direction.

⇒ the tooth is read at `t` = 0.5 s, past the first turn for both (`S/ρ` = 0.4167 s at the wider
one), **and the opening leg's equality is pinned as a tooth in its own right** so the property is
RECORDED rather than stepped around. ⭐ This is §1's mechanism turning up in a place the plan did not
expect it: *the coverage is not something the sweep HAS, it is something the sweep does not reach
until it has run for `S/ρ`.* ⚠ It is also a live warning for gate 2 and for the verifier — **any
`S`-comparison sampled inside the first `S/ρ` of a search compares two identical numbers**, and on
this wire at ρ = 60 that is the first 0.42 s of every arm.

The second failure was ordinary: the slope sub-check inherited none of the outer loop's `S < a`
guard, so at a deficit of 8° it compared "first cover" times for a 5° sweep that never covers.

### ⚠ TWO THINGS GATE 1 SETTLES **FOR** GATES 2–3, BOTH AGAINST §IX

- **`@test carriers == ["slice48_search.yaml"]`** (`test_search.jl`, the enumerated-carrier set)
  FAILS the moment any `scenarios/slice52_*.yaml` authoring `:seeker_search` lands, because that key
  is what raises `search_view`. Expected, and it is the test doing precisely its job; gate 3 extends
  the list rather than loosening the check.
- ⚠⚠ **§IX's "a view that draws the swept band" AND "no core change" CANNOT BOTH BE TRUE.**
  `_draw_search_hud_lines` (`clients/godot/scenes/Sandbox.gd:3275`) is **FIVE `draw_string` LINES AND
  NO GEOMETRY** — there is nothing in the client that draws a band today. And a slice-52 wire is
  slice 48's wire with a different slider, so there is **no new comp key for a new view marker to
  switch on**, which is the mechanism every marker in this family since slice 38 has used. ⇒ gate 3
  must either (a) ship a new key the marker can gate on, or (b) share `search_view` and switch the
  block on something already distinguishing — and (b) needs a candidate that is not the slider
  itself, since a HUD that changed shape mid-drag is convention 5's hazard in the VIEW.
  **§IX is corrected to that extent: the "no core change" verdict is a GATE-0 finding about the
  PHYSICS, and it does not reach the client.**
