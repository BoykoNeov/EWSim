# Slice 43 — **THE SEARCH-RATE WINDOW: WHAT A SEARCH PATTERN ACTUALLY COSTS** (§11 Tier-A)

**STATUS: GATE 0, PRE-PROBE. Written before any number for this slice exists.**
Everything below §0.2 is a *prediction, a domain, or a falsifier* — never a measurement. Where a probe
refutes a prediction the refutation is marked AT the prediction and recorded in the results section;
the prediction is never quietly edited to match (slices 41 and 42's discipline, and the only reason
both kills were cheap).

---

## ⚠⚠ §0.0 THE ADMISSION TICKET — WHY THIS IS NOT SLICE 42 RE-RUN

Slice 42 died at gate 1 and its **acquisition knife-edge is on the kill list**. Nothing here touches
it. What slice 42 left standing and carried to `docs/DEFERRALS.md` is exactly one thing:

> ⭐ **THE WRONG-GUESS FRONTIER** (`docs/plans/slice42.md` §V.4) — the minimum sweep rate ρ_min that
> rescues an arm is FLAT across a 6× range of coverage S when the sweep-direction guess is right, and
> RISES MONOTONICALLY with S when it is wrong.

**Two things are new, and neither existed when that deferral was written:**

1. ⚠⚠ **AN INSTRUMENT DEFECT IN THE TABLE ITSELF.** `p7b_frontier.jl`'s `arm()` never sets
   `:probe_search_drive`, so the patch fell through to its `:direct` branch — `head_clamp(cmd, …)`.
   **Every cell of §V.4 was flown by TELEPORTING the head to the search command: no `τ`, no
   `rate_max`, no `head_slew_full` at all.** The wire it claims to describe (`w37`) ships
   `gimbal_rate_dps = 8`. **So the ρ_min = 10, 11 and 14 °/s cells — the entire expensive half of the
   frontier, and the whole basis of the "wrong guess is expensive" sentence — are rates the shipped
   servo CANNOT PRODUCE.** This is the third instrument bug in this family (§V.4 already carries two)
   and it is the same species as the other two: *the probe drove the head, not the command.*
2. ⭐ **A PRICE THE DEFERRAL DID NOT NOTICE IT ALREADY HAD.** §V.6 blocked the slice because *"a
   wider window is FREE in this model"* — the coverage/glass trade cannot be motivated. True. But the
   frontier does not spend GLASS. **It spends SLEW RATE, and slew rate has been priced since slice 35
   and re-priced at slice 37** (`gimbal_rate_dps` is a shipped knob with a measured cost).

## ⚠⚠⚠ §0.1 WHAT THIS DOES **NOT** CLAIM — the overclaim this arc has made four times

Stated first, and in the negative, because §0.0 item 2 is one sentence away from the shape that
killed 39, 41 and both halves of 42:

> **THE SERVO CEILING PRICES THE *SEARCH*. IT DOES NOT PRICE THE *ALTERNATIVE*.**
> A designer holding this frontier can still just widen the window, and the window is still free.
> **The blocking precondition of §V.6 is NOT dissolved by this slice and must not be written as if it
> were.** What is on offer here is narrower and honest: *the law becomes clean and priced — the slice
> stays blocked.* A shippable search-pattern slice still needs `SEEKER RANGE / SNR ACQUISITION
> LIMITS` first, exactly as `docs/DEFERRALS.md` says.

⇒ **The deliverable of this gate is a LAW that is true and fully instrumented, not a slice.** If
gate 0 succeeds, the frontier's deferral in `docs/DEFERRALS.md` is rewritten with real numbers, a
real ceiling and its precondition intact. If gate 0 fails, the frontier joins the kill list and the
search-pattern family is closed for good — which is a cheaper and more useful outcome than a fifth
plausible sentence.

## §0.2 THE CANDIDATE LAW

> ⭐ **A SEARCH PATTERN LIVES INSIDE A RATE WINDOW, AND THE WRONG GUESS CLOSES IT.**
>
> * **A FLOOR, ρ_min(S, guess)** — set by the engagement's time budget: the head must sweep the whole
>   travel to the target before the intercept geometry runs out. Guess the direction right and the
>   travel is the birth offset alone, so **coverage does not enter and ρ_min is flat in S**. Guess
>   wrong and the travel is the offset PLUS twice the coverage, so **every extra degree of coverage
>   must be bought back in rate**.
> * **A CEILING, ρ_max** — and the claim is that it is **`gimbal_rate_dps`, the head's own servo**,
>   not a property of the search at all.
> * **THE LAW IS WHERE THEY MEET:** the maximum coverage a wrong guess can afford is
>   **S\* = the S at which ρ_min(S, wrong) crosses ρ_max**, and S\* must MOVE when the servo is
>   re-specified. A right guess never approaches the ceiling, which is the whole asymmetry.

**Why this is worth a gate even though the slice stays blocked (§0.1):** the search-pattern family
has been surfaced and dropped three times (37, 42 gate 0, 42 gate 1). Each time it was dropped for a
*different* reason, and none of the three reasons was measured against the servo the head actually
has. This gate ends that by pricing it once, in the shipped currency.

## ⚠⚠ §0.3 THE PRE-REGISTERED FALSIFIERS — FIXED IN WRITING BEFORE ANY MEASUREMENT EXISTS

Ordered by when they run. **F0 and F1 are the ones that can end it.**

### F0 — THE SERVO SMOKE (runs FIRST; the slice dies here or nowhere)

The entire §V.4 table was flown with the servo bypassed (§0.0). Before anything else, one cell that
`:direct` rescues comfortably is re-flown through `head_slew_full` at a rate FAR below the cap:
**err −12°, S = 10°, ρ = 2 °/s, `gimbal_rate_dps = 8`, `:probe_search_drive = :servo`.**

* **KILL:** if `:servo` fails to rescue (`miss > 1.0 m`) a cell that `:direct` rescues at the same ρ,
  then a real first-order servo cannot fly a search on this wire at all, **every number in §V.4 is
  an artifact of the bypass, and the frontier is dead.** The deferral is rewritten as a kill and the
  family is closed.
* ⚠ **PREDICTED (and this is a prediction, not a result):** it rescues. The command is its own
  integrator, so a τ = 0.05 s servo tracking a 2 °/s ramp lags by ρ·τ = 0.1° — immaterial against a
  10° window. **If the measured lag is anywhere near the window width, the prediction is wrong and
  the mechanism must be found before the run continues.**

### F1 — THE GRID EDGE (`docs/LESSONS.md`: a reported quantity that equals an authored constant IS that constant)

§V.4 reports **`none ≤ 16`** for S = 25 and 30 on the +side, and its own legend reads
*"`--` = no rate in 1..16 deg/s rescues"*. **The grid maximum was 16.** By this project's own lesson
— written down eight days ago by the slice that produced this very table — that cell is the grid edge
echoing itself, not a measurement of a ceiling.

* The ρ grid is extended to **64 °/s on `:direct`**.
* **WITHDRAWAL (pre-registered, not a kill):** if ρ_min becomes finite there, §V.4's sentence *"past
  S ≈ 20° on one side no rate buys it back"* **is withdrawn as an authored constant**, and the real
  ceiling claim must come from F2 or not at all.
* **KILL:** if ρ_min stays infinite at 64 °/s **with the servo bypassed**, there is a rate ceiling
  that is NOT the servo. The candidate law of §0.2 is then false as stated, and no sentence ships
  until that mechanism is named and measured.

### F2 — THE CEILING MUST MOVE WITH THE KNOB (the teeth — this is what makes it a law and not a table)

With `:servo` drive, `gimbal_rate_dps` is swept over slice 35's shipped domain **{4, 8, 16, 60}** and
S\* — the largest coverage a wrong guess still rescues — is read on each.

* **SURVIVAL:** S\*(wrong guess) rises **monotonically** with the rate limit across at least a 2×
  range of the knob, and S\*(right guess) does **not** (it is already ceiling-free).
* **KILL:** S\* flat in `gimbal_rate_dps` ⇒ the ceiling is not the servo, §0.2's central claim is
  false, and what remains is at most a re-measured §V.4 with no price on it.
* ⚠ **AND THE DEAD-KNOB CHECK APPLIES** (`CLAUDE.md`, false-fidelity): if S\* moves for the first
  step of the knob and then saturates, quote the domain over which it moves and do not extrapolate.

### F3 — THE CLAMP, WHICH MAY BE THE WHOLE +/− ASYMMETRY (advisor)

§V.4's two signs disagree sharply (wrong-guess ρ_min 4→11 on the − side, 4→14-then-nothing on the
+ side). ⚠ **The +side arms are born ON the 30° stop** — slice 36's domain note, and `p7b_frontier`'s
own header says the +side is where a previous instrument bug lived. **If the sweep cannot achieve S
degrees of coverage there because the stop truncates it, then S is not coverage and the asymmetry is
the clamp.**

* Every cell carries a **`stop%` column** (fraction of search ticks with the head on the stop) and
  **it is read before any other column** (`CLAUDE.md`: carry a contamination column IN BAND and read
  it first — the discipline slice 41 paid for).
* The +side is re-flown at **`stop` = 45° and 60°**. **If S\*(+) moves with the stop, the
  two-sidedness of §V.4 is instrument, is withdrawn, and only the −side survives.**

### F4 — THE RESCUE GATE MAY BE SAMPLING (advisor)

`arm()` calls an arm rescued at **`miss ≤ 1.0 m`**, and CPA is read as `r_prev` with no
interpolation. At 700 m/s and dt = 1e-3 the CPA grid is ~0.7 m, so the gate is **about one tick of
travel wide** — and `docs/LESSONS.md` already carries *frame-sampling error is asymmetric*.

* The ρ_min bracket is re-read at gates **1 / 2 / 5 m**.
* **WITHDRAWAL:** if ρ_min shifts by more than one grid step between gates, the frontier's boundary
  is CPA sampling and every ρ_min in this file must be quoted as a bracket, not a number.

### F5 — THE COLLAPSE (the reparameterization gate — ⚠ explicitly **NOT** a kill criterion)

Test whether every cell satisfies **ρ_min · T_avail ≈ (birth offset) + (0 or 2S)**, i.e. whether the
whole surface is travel-over-time.

* ⚠⚠ **A MEASURED SURFACE MATCHING A DERIVATION IS CONVENTION 11's EXTERNAL ANCHOR — IT IS THE
  OPPOSITE OF A KILL.** Slices 39 and 41 died because a new *dynamic element* was reproducible by
  retuning an existing *scalar*: no new degree of freedom. A closed form that PREDICTS a surface is
  what this project asks its findings to have. **This is written down here so that a future session
  does not kill a good result by pattern-matching on the word "reparameterization".**
* **BUT IT DOES DECIDE THE HEADLINE:** if the collapse is clean, the frontier's *shape* is arithmetic
  and the headline must be the **ceiling crossing** (F2), which is not.
* ⚠ **PREDICTED:** the right-guess rows being flat in S is *implied* by the collapse (S does not enter
  the travel when you sweep toward the target), so flatness is not evidence for anything on its own.
  ⭐ **The non-trivial residue is that the right guess reads ρ_min = 2 on the − side and 1 on the
  + side.** Static travel cannot produce that — **the LOS is MOVING**, so the real variable is closure
  against a moving line of sight, not distance over time. If the collapse holds everywhere EXCEPT
  that asymmetry, the asymmetry is the finding.

### F6 — THE STEP (`docs/LESSONS.md`, the rule slice 42 died to)

Whatever S\* survives F2 is **re-flown at `dt` = 5e-4**. **If S\* moves with the step, it is the
integrator and not the hardware, and it dies exactly as the knife-edge did.**

## §0.4 PROBE ORDER (and the reason it is this order)

Cheapest kill first, teeth last, so that a dead slice costs one run and not ten.

| # | Probe | Answers |
|---|---|---|
| P0 | one `:servo` cell vs the same `:direct` cell | **F0** — is there anything here at all |
| P1 | ρ grid to 64, `:direct`, full (dir × S) | **F1** — turn `none` into a number, and reproduce §V.4 |
| P2 | full grid re-flown `:servo`, with `stop%` | **F3 first pass**, and the honest frontier |
| P3 | `gimbal_rate_dps` ∈ {4, 8, 16, 60} → S\* | **F2** — the teeth |
| P4 | +side at stop 45 / 60 | **F3** — is the asymmetry the clamp |
| P5 | rescue gate 1 / 2 / 5 m on the ρ_min brackets | **F4** |
| P6 | ρ_min · T_avail vs travel, all cells | **F5** — the derivation, and the residue |
| P7 | S\* at dt = 5e-4 | **F6** |

## §0.5 OPEN AT PRE-PROBE TIME — stated so a later answer cannot be mistaken for a prediction

1. **What sets T_avail?** §V.4 never wrote down the time budget its ρ_min is dividing. It is probably
   the ~6.5 s to the point where the intercept is no longer recoverable (slice 42 §I.2's F0 measured
   a budget on the RECEDING wire; this is the STATIC wire and the number does not transfer).
2. **Does the search's own sweep spend the servo the guidance loop needs?** The head is one servo. A
   search at 8 °/s on a wire whose cap is 8 °/s leaves nothing for tracking at the moment of lock —
   **which would make ρ_max strictly LESS than `gimbal_rate_dps`,** and that gap would itself be the
   finding. Not predicted either way; measured at P3.
3. Whether a reversal costs anything beyond its travel (the command reverses instantly; the servo
   cannot). At ρ near the cap this should bite, and at ρ far below it should not.

---

# §I — GATE 0, PROBES **P0/P1** (2026-08-18): **F0 PASSES, F1 FIRES, AND MY OWN CEILING CLAIM IS IN TROUBLE**

## §I.0 P0 — **F0 PASSES, AND ITS PREDICTION IS NOW MEASURED RATHER THAN ASSUMED**

Same cell, two drives, `gimbal_rate_dps = 8`:

| err ° | S ° | dir | ρ °/s | miss `:direct` | miss `:servo` | lag ° | stop% | sat% | t_lock s |
|---|---|---|---|---|---|---|---|---|---|
| −12 | 10 | +1 (right) | 2 | 0.184 | **0.146** | 0.098 | 0.0 | 11.2 | 1.227 |
| −12 | 10 | +1 | 4 | 0.036 | **0.061** | 0.196 | 0.0 | 11.5 | 0.588 |
| −12 | 10 | −1 (WRONG) | 5 | 0.105 | **0.309** | 0.245 | 0.0 | 5.1 | 5.180 |
| −14 | 10 | +1 | 2 | 0.089 | **0.172** | 0.098 | 0.0 | 10.1 | 2.506 |
| +12 | 10 | −1 (right) | 1 | 0.057 | **0.099** | 0.049 | 0.0 | 17.5 | 1.525 |
| +12 | 10 | +1 (WRONG) | 8 | 0.288 | **0.327** | **9.997** | **29.1** | 18.4 | 2.679 |

> ⭐ **A REAL FIRST-ORDER RATE-LIMITED SERVO FLIES A SEARCH FINE. F0 does not fire.** Every cell the
> bypass rescued, the servo rescues.

⭐ **AND THE LAG IS EXACTLY `ρ·τ`, TO THREE DIGITS, ON EVERY UNSATURATED ROW** — 0.049 / 0.098 /
0.196 / 0.245° at ρ = 1 / 2 / 4 / 5 against τ = 0.05. That is the closed form the falsifier
*predicted*, now measured on the shipped kernel. It is immaterial against a 10° window, which is why
§V.4's numbers mostly survive the bypass — **but "mostly" is not "all", and the last row is why.**

⚠⚠ **THE LAST ROW TRIPS F0's OWN ESCAPE CLAUSE** (*"if the measured lag is anywhere near the window
width, the prediction is wrong and the mechanism must be found before the run continues"*): at ρ = 8,
the lag is **9.997° — a full window** — and the head is on the stop 29 % of in-band ticks. `ρ·τ` would
be 0.4°. **The 25× excess is not the servo's lag, it is the CLAMP**: the command is unclamped and the
head is not, so while the head is parked on the stop the command runs away from it without bound.

## ⚠⚠ §I.1 THE NULL CELLS — AND **THE TWO SIGNS ARE NOT THE SAME FAILURE**

Read first, per `docs/LESSONS.md`:

| err ° | no-search miss (m) | ever locks? | stop% |
|---|---|---|---|
| −12 | 305.112 | **no** | 0.0 |
| −14 | 305.112 | **no** | 0.0 |
| +12 | 423.494 | **YES** | **56.5** |
| +14 | 483.430 | **YES** | **56.6** |

⭐⭐ **THE MINUS SIDE IS AN ACQUISITION FAILURE AND THE PLUS SIDE IS NOT.** The − arms never lock and
both miss the *same* 305.112 m (the signature of a null that does not depend on the error at all).
The + arms **do** lock, and still miss — and they spend **57 % of their in-band ticks pinned on the
30° stop with no search running at all.**

⇒ ⚠ **F3 IS ALREADY LIVE BEFORE ITS OWN PROBE.** Slice 42 §III.1's *"the failing set is two-sided
here"* is true only in the sense that both signs miss. **They miss for different reasons**, and the
+ side's reason is visible in the do-nothing cell.

## ⭐⭐ §I.2 P1a — **F1 FIRES: `none ≤ 16` WAS THE GRID EDGE, AND IT IS NOW A NUMBER**

The four cells slice 42 §V.4 reported as `--`, walked to 64 °/s on the same `:direct` instrument:

| err ° | dir | S ° | **ρ_min** | miss (m) | stop% | lag ° |
|---|---|---|---|---|---|---|
| +12 | +1 | 25 | **18** | 0.246 | 32.3 | 24.977 |
| +12 | +1 | 30 | **22** | 0.315 | 31.8 | 29.979 |
| +14 | +1 | 25 | **18** | 0.246 | 32.3 | 24.978 |
| +14 | +1 | 30 | **22** | 0.315 | 31.8 | 29.980 |

> ⚠⚠ **SLICE 42 §V.4's SENTENCE — *"past S ≈ 20° on the +side there is no rate that buys it back"* —
> IS WITHDRAWN. There is: 18 °/s and 22 °/s.** The `--` was the top of an authored 1…16 grid echoing
> itself back, which is **the exact lesson slice 42 itself wrote into `docs/LESSONS.md` eight days
> earlier** and then did not apply to its own surviving table.

⚠ Note also `lag ≈ S` **to the digit** (24.977 at S = 25, 29.979 at S = 30) — the head is a full
half-width behind its command. That is not a servo lag, it is the head sitting on the stop while the
command sweeps the whole pattern without it. **These rows describe a command, not a head.**

## ⚠⚠⚠ §I.3 P1b — **§0.2's CEILING CLAIM IS REFUTED: COMMANDING ABOVE `rate_max` STILL HELPS**

The candidate law said ρ_max = `gimbal_rate_dps`, so on `:servo` the digits should stop changing at
ρ = 8. They do not:

| err | dir | S | ρ °/s | miss `:servo` | miss `:direct` | lag ° | stop% | t_lock s |
|---|---|---|---|---|---|---|---|---|
| −12 | −1 (wrong) | 20 | 4 | 305.112 | 305.112 | 0.196 | 0.0 | — |
| −12 | −1 | 20 | 6 | 305.112 | 305.112 | 0.294 | 0.0 | — |
| −12 | −1 | 20 | **8** | **0.131** | 0.129 | 0.392 | 0.0 | **6.035** |
| −12 | −1 | 20 | 10 | 0.333 | 0.185 | 6.094 | 0.0 | **5.174** |
| −12 | −1 | 20 | 12 | 0.120 | 0.037 | 10.532 | 0.0 | **4.604** |
| −12 | −1 | 20 | 16 | 0.321 | 0.332 | 16.715 | 0.0 | **3.821** |
| −12 | −1 | 20 | 32 | 0.039 | 0.059 | 20.990 | 0.0 | **2.353** |

> ⚠⚠ **`t_lock` FALLS MONOTONICALLY FROM 6.035 s TO 2.353 s AS THE COMMANDED RATE GOES FROM 1× TO 4×
> THE SERVO'S OWN LIMIT.** A head that cannot slew faster than 8 °/s nonetheless acquires **2.6×
> sooner** when told to sweep at 32. **⇒ F2's central claim — that the search's rate ceiling IS the
> servo knob — is false as stated in §0.2, and it is withdrawn here rather than at F2's own probe.**

⚠ **AND THE +SIDE ROWS OF THE SAME PROBE ARE CONTAMINATION, NOT PHYSICS** (err +12, dir +1, S = 15):
`lag` reads **14.990 / 14.995 / 14.996 / 14.996 / 14.985 / 14.989 / 14.974** across ρ = 4 → 32 — i.e.
**pinned at the half-width S = 15 to three digits, at every rate** — with stop% 53.2 → 10.9. The head
is on the stop and the command is sweeping without it. `miss` there runs 258.959 / 414.581 / 324.076
before rescuing at ρ = 10, which is not a bracket and must not be read as one.

## §I.4 WHERE THIS LEAVES THE GATE — **the law is not the one §0.2 named**

**Standing:** F0 does not fire (there is something here). **F1 fires** (§V.4's `--` withdrawn).
**F2's claim is refuted early** (the servo limit is not the ceiling). **F3 is confirmed on the +side
before its own probe** (lag ≡ S, stop% up to 57 % *with no search running*).

⭐ **THE MECHANISM P1b IMPLIES, STATED AS A PREDICTION SO THE NEXT PROBE CAN KILL IT:** the command
is an unclamped, unlimited integrator; the head is clamped and rate-limited. So when ρ_cmd exceeds
`rate_max`, **what collapses is not the head's rate — it is the pattern's AMPLITUDE.** The command's
half-period is `S/ρ_cmd`, and in that time a saturated head covers only `rate_max · S/ρ_cmd`. ⇒

> **PREDICTED: the head's realized excursion is `A = S · min(1, rate_max/ρ_cmd)`,**
> so past the servo limit **asking for more rate SPENDS coverage, one for one** — and slice 42's
> (S, ρ) grid is in COMMANDED coordinates that the head never flies.

⚠ **THIS IS A PREDICTION AND NOTHING ELSE. It is not yet measured, and the alternative reading — that
a fast dither near the birth angle simply waits for the LOS to walk into it, so the "search" is doing
no searching at all — is equally consistent with every number above.** P2 measures the head's actual
excursion and separates them.

## ⚠⚠ §I.5 **F7 — PRE-REGISTERED BEFORE P2/P3 RUN.** Is the amplitude collapse PHYSICS or MY OWN GENERATOR?

Written before the dither ladder or the lead ladder exists, because §I.4's prediction has an obvious
alternative that would make it an artifact and I want the criterion fixed first.

Slice 42's search command is an **OPEN-LOOP integrator**: it advances by `dir·ρ·dt` every tick and
reverses when *the command* reaches the half-width. It never looks at the head. So when the head
saturates at `rate_max`, the command runs away and reverses while the head is still out near the
middle of the pattern — **and that is integrator WINDUP, a property of the generator I wrote, not of
the seeker.**

> **THE FIX IS ONE LINE AND IT HAS A NAME: bound how far the command may lead the head
> (`:probe_search_lead`). That is anti-windup, applied to a search pattern.**

* **PREDICTED:** with a finite lead, **commanding ρ above `rate_max` becomes INERT** — t_lock and
  miss stop changing at ρ = `gimbal_rate_dps`, and the realized excursion stops collapsing.
* **IF THAT HOLDS:** §I.4's amplitude collapse is **real but is a property of the OPEN-LOOP
  generator**, the honest law is a statement about *search-pattern architecture* rather than about
  seeker hardware, and — ⭐ — **§0.2's ceiling claim is restored CONDITIONALLY**: the servo is the
  ceiling *if and only if your pattern generator knows about the head.*
* **IF IT DOES NOT HOLD** (ρ > rate_max still moves the numbers with the lead clamped in), then the
  collapse is not windup, my mechanism is wrong, and nothing about amplitude ships until the real
  one is found.
* ⚠ **CONTAMINATION GUARD:** the lead clamp is a second feedback path from `head_az` into the
  command, which is the shape of the slice-42 instrument bug that *"crawls at 1/50 rate"*. **The
  crawl signature is `t_lock` blowing up by ~50× at small ρ.** If any lead-clamped row shows it, the
  clamp is mis-built and every row from it is void.
