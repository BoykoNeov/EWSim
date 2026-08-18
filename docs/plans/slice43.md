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

---

# ⭐⭐⭐ §II — PROBES **P2–P5** (2026-08-18): **THE LAW, AND IT IS NOT THE SENTENCE SLICE 42 LEFT**

**−SIDE ONLY.** The +side is excluded from every table below as stop-contaminated (§I.1, §I.3): its
`lag ≡ S` to three digits across seven rates, and its do-nothing cell sits on the stop 57 % of in-band
ticks. **The head is not flying the pattern there, so no number from it describes a search.**

## ⚠⚠ §II.0 P2a — **THE ADVISOR'S DISCRIMINATOR, AND READING (B) IS REFUTED**

Two readings of §I.3's monotone `t_lock` were equally consistent with everything measured: **(A)** the
pattern's amplitude collapses but the head still sweeps, or **(B)** the head barely moves and the LOS
simply walks into a nearly-stationary window, so the search does no searching at all. The
discriminator is a **dither** — a half-width too small to ever reach the target:

| half ° | ρ °/s | dir | miss (m) | t_lock | head excursion ° |
|---|---|---|---|---|---|
| 1 | 8 | ±1 | **305.112** | never | −0.73 … +0.74 |
| 2 | 8 | ±1 | **305.112** | never | −1.73 … +1.73 |
| 3 | 8 | +1 | 0.186 | 0.309 | 0.00 … **+2.07** |
| 3 | 32 | ±1 | **305.112** | never | −1.11 … +1.11 |
| 5 | 32 | ±1 | **305.112** | never | −1.92 … +1.92 |

> **READING (B) IS DEAD.** A dither that cannot travel ≈2.07° never rescues, at any rate, in either
> direction. **The head's travel is load-bearing.**

## ⭐⭐⭐ §II.1 **FINDING 1 — THE COST OF ACQUISITION IS THE OVERLAP DEFICIT, NOT THE ERROR**

The single most useful thing in this gate, and slice 42 never wrote it down. A head born `|err|` off
the line of sight behind a `±fov` window does not have to travel `|err|`. **It has to travel
`|err| − fov` — the amount by which the target is outside the window edge.** Right guess, ρ = 8:

| err ° | fov ° | **deficit °** | head travel at lock ° | ratio | t_lock s |
|---|---|---|---|---|---|
| −12 | 10 | 2 | 2.073 | 1.0365 | 0.309 |
| −14 | 10 | 4 | 4.144 | 1.0360 | 0.568 |
| −16 | 10 | 6 | 6.224 | 1.0373 | 0.828 |
| −18 | 10 | 8 | 8.304 | 1.0380 | 1.088 |
| −20 | 10 | 10 | 10.392 | 1.0392 | 1.349 |
| −18 | 15 | 3 | 3.104 | 1.0347 | 0.438 |
| −20 | 15 | 5 | 5.176 | 1.0352 | 0.697 |
| **−14** | **12** | **2** | **2.073** | 1.0365 | **0.309** |

⭐⭐ **THE LAST ROW IS A NATURAL EXPERIMENT AND IT IS EXACT.** `err −14 / fov 12` and `err −12 / fov 10`
are *different* errors behind *different* windows with the *same* deficit — and they return **the same
travel (2.073), the same lock time (0.309) and the same miss (0.186), to every digit printed.**
**The error and the window are not separately visible to the search. Only their difference is.**

⭐ **AND IT HAS A CLOSED FORM, GOOD TO THREE DIGITS ON ALL EIGHT CELLS:**

> ⚠⚠⚠ **SUPERSEDED BY §III — AND BY THIS FILE'S OWN RULE THE SENTENCE IS ANNOTATED, NOT DELETED.**
> **All eight cells are at ρ = 8**, so the 1.036 is one point of a curve, and the drift mechanism named
> for it below REQUIRES it to vary with ρ (it runs 1.031–1.357 over the rate axis). The corrected form
> is `travel = deficit / (1 − ω/ρ)` with ω the LOS rate, `t_lock = travel/ρ + τ`, **domain ρ ≤ rate_max**.
> ⚠ *"three digits, eight cells, two windows"* counted CELLS, not AXES.

> **`t_lock = 1.036 · deficit / ρ + τ`**   — *at ρ = 8 only; see §III.1*

with τ = 0.05 s the servo's own lag (`ρ·τ` — §I.0 — measured, not fitted) and **1.036 the price of the
LOS running away while the head travels.** Check: deficit 10 ⇒ 1.036·10/8 + 0.05 = 1.345 against a
measured 1.349.

## ⭐⭐⭐ §II.2 **FINDING 2 — THE RIGHT GUESS NEVER REACHES ITS COVERAGE.** That is why it looked free

Slice 42 §V.4 said *"guess right and the width is FREE — ρ_min is FLAT across a 6× range of coverage."*
The flatness reproduces exactly, and is now **stronger** (a 10× range, and the same digit not the same
bracket) — and the reason turns the sentence inside out. ρ = 8, lead clamped:

| S ° | 3 | 5 | 8 | 12 | 16 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|---|
| **t_lock, right guess** | 0.309 | 0.309 | 0.309 | 0.309 | 0.309 | 0.309 | 0.309 | 0.309 |

> ⭐⭐ **THE WIDTH IS NOT FREE — IT IS NEVER USED.** The head locks **2.07° into a pattern authored
> 3° to 30° wide.** Coverage does not appear in the answer because the search ends before coverage
> exists. ⇒ **quoting a search's coverage as its cost is a category error whenever the guess is
> right**, and a flat row is therefore evidence of *nothing* on its own — exactly as F5 pre-registered.

## ⭐⭐ §II.3 **FINDING 3 — THE WRONG GUESS PAYS `2S` IN TRAVEL, AND THE PRICE ACCELERATES**

Same grid, wrong guess. The static geometric prediction is `dt_lock/dS = 2/ρ = 0.250` s per degree
(out to the far edge and back again):

| S ° | 3 | 5 | 8 | 12 | 16 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|---|
| **t_lock, wrong guess** | 1.088 | 1.612 | 2.407 | 3.495 | 4.648 | 6.035 | **never** | **never** |
| **measured slope s/°** | — | 0.262 | 0.265 | 0.272 | 0.288 | **0.347** | — | — |

> ⭐⭐ **THE NAIVE TRAVEL-OVER-RATE LAW IS A LOWER BOUND, AND IT IS LOOSE EXACTLY WHERE THE DECISION IS
> HARD.** The measured price per degree of coverage starts 5 % above the geometric prediction and ends
> **39 % above it**, then diverges: at S = 25 and 30 the arm never locks at all at ρ = 8. **The excess
> is the target moving while you look the wrong way — the same 3.6 % term that appears in finding 1's
> constant, compounding over a search that is 20× longer.**

⚠ **THIS IS THE HONEST REPLACEMENT FOR SLICE 42 §V.4's ρ_min TABLE**, which was flown with the servo
bypassed and reported its own grid edge as a physical ceiling (§I.2).

## ⚠⚠ §II.4 **FINDING 4 — AN OPEN-LOOP PATTERN GENERATOR WINDS UP AGAINST THE RATE LIMIT** … and F7's own gate cuts it down

**The failure is real.** Slice 42's generator advances the command by `dir·ρ·dt` and reverses when
*the command* reaches the half-width — it never looks at the head. So once the head saturates at
`rate_max`, the command runs away and reverses while the head is still near the middle. At a fixed
authored S = 20, err −12, wrong guess:

| ρ °/s | 8 | 10 | 12 | 16 | 32 | 64 |
|---|---|---|---|---|---|---|
| **realized head excursion °, open loop** | −19.73 | −17.58 | −15.82 | −13.20 | −7.92 | **−4.39** |
| **miss, open loop** | 0.131 | 0.333 | 0.120 | 0.321 | 0.039 | **305.112** |
| **realized excursion °, lead = 1°** | −19.73 | −19.37 | −19.33 | −19.27 | −19.14 | **−19.03** |
| **miss, lead = 1°** | 0.131 | 0.319 | 0.006 | 0.329 | 0.108 | **0.287** |

> ⭐ **A SEARCH COMMANDED AT 64 °/s ON AN 8 °/s HEAD DOES NOT SWEEP FASTER AND IT DOES NOT MERELY
> SWEEP LESS — IT FAILS OUTRIGHT** (305.112 m, never locks) at a coverage that rescues comfortably
> when commanded at 8. **What saturates is not the rate. It is the AMPLITUDE.**
> **F7 PASSES:** one line of anti-windup — bound how far the command may lead the head — removes the
> collapse entirely (excursion flat −19.73 → −19.03 across an 8× rate range).

⚠ **CONTAMINATION GUARDS BOTH CLEAR.** F7's pre-registered crawl signature (t_lock ×50 at low ρ) does
not appear. And **below `rate_max` the clamp is provably inert** — ρ = 2, 4, 8 return identical digits
at every lead ∈ {∞, 8, 4, 2, 1}, which is what says the clamp acts only where it should.

### ⚠⚠⚠ §II.4a **AND THEN THE REPARAMETERIZATION GATE — RUN AGAINST MY OWN FINDING, AND IT BITES**

The gate slices 39 and 41 died at, applied here before the finding was written down rather than after.
**A designer could get this rescue far more cheaply: just refuse to author ρ above `rate_max`.** A =
lead 1° at the authored ρ; B = the open-loop generator at `min(ρ, 8)`:

| S ° | ρ = 8 | ρ = 16 | ρ = 32 | ρ = 64 |
|---|---|---|---|---|
| **A vs B, t_lock — S = 5** | +0.0 % | −12.5 % | −16.0 % | −18.4 % |
| **S = 10** | +0.0 % | −7.1 % | −9.0 % | −10.4 % |
| **S = 20** | +0.0 % | −5.2 % | −6.6 % | −7.5 % |
| **rescue verdict A vs B** | same | same | same | same (**all 16 cells**) |

> ⚠⚠ **THE LEAD CLAMP MOVES NO VERDICT. In all 16 cells A and B rescue or fail together** — including
> S = 30, where both fail at a byte-identical 305.112 m. It buys 5–18 % of lock time and not one miss.
> ⇒ **FINDING 4 IS A DESIGN CAUTION WITH A MEASURED SIZE, NOT AN ARCHITECTURE.** By this project's own
> standard it is not a slice, and it must never be written as one. **What ships is the caution:
> *authoring a sweep rate above the head's slew limit is not merely wasteful — it is a failure mode*,
> and the one-line cure is `ρ ← min(ρ, rate_max)` at authoring time.**

## §II.5 F4 AND F6 — BOTH ANSWERED, AND F6 IS THE ONE SLICE 42 DIED TO

**F6 — THE STEP.** Every headline cell re-flown at `dt` = 5e−4:

| cell | dt = 1e−3 | dt = 5e−4 | Δ |
|---|---|---|---|
| head travel at lock (deficit 6) | 6.2240 | 6.2240 | **0.0000** |
| t_lock, right guess, S = 20 | 0.3090 | 0.3095 | +0.0005 s (+0.16 %) |
| t_lock, wrong guess, S = 20 | 6.0350 | 6.0340 | −0.0010 s (−0.02 %) |

> ⭐ **HALVING THE INTEGRATION STEP MOVES NOTHING.** Slice 42's knife-edge halved when the step halved
> and died for it. **This does not.**

**F4 — THE RESCUE GATE.** 40 −side arms across S ∈ {5,10,20,30} × ρ ∈ {2,4,8,16,32} × both guesses:

> **30 rescues, largest 0.3398 m. 10 failures, smallest 305.1118 m. ZERO cells in between.** The
> verdict is perfectly bimodal — **the rescue gate could be set anywhere from 0.34 m to 305 m without
> changing a single cell.** F4's sampling worry does not apply to the −side.

## ⭐⭐ §II.6 THE LAW, IN ONE PLACE

> **1. A search's cost is the OVERLAP DEFICIT `|err| − fov`, not the pointing error.** Error and
>    window are not separately visible; only their difference is (exact, two (err, fov) pairs).
> **2.** ⚠ **SUPERSEDED BY §III.5** — `travel = deficit/(1 − ω/ρ)`, `t_lock = travel/ρ + τ`, for `ρ ≤ rate_max`.
> **3. Guess the direction right and coverage is not free — it is NEVER REACHED.** Lock at 2.07° into
>    a pattern 3–30° wide, `t_lock` identical to the digit across a 10× range of coverage.
> **4. Guess wrong and coverage costs `2S` of travel — at a price that ACCELERATES**, 5 % over the
>    geometric bound at S = 5 and 39 % at S = 20, diverging to never-locks by S = 25. **The target is
>    moving while you look the wrong way, and that is the whole excess.**
> **5. The head, not the command, is what searches.** An open-loop generator commanded above the
>    head's slew limit converts excess rate into LOST COVERAGE and then into outright failure
>    (−19.73° → −4.39° of realized sweep, rescue → 305.112 m). ⚠ **Cure `ρ ← min(ρ, rate_max)`;
>    anti-windup is 5–18 % better and moves no verdict, so it is a caution, not an architecture.**

## ⚠⚠⚠ §II.7 WHAT THIS DOES **NOT** LICENSE — §0.1, restated now that the numbers exist

**The slice is still blocked, and nothing here changes that.** Findings 1–5 price the *search*. They
do not price the *alternative*: on this wire a wider window still rescues every showcase cell for
free (slice 42 §V.3), and finding 1 now says exactly why — **a wider `fov` reduces the deficit
one-for-one, and the deficit is the entire cost.** ⭐ Finding 1 makes the free-window objection
*sharper*, not weaker: widening the glass by 2° and travelling 2° further are **the same act**, and
only one of them costs time.

⇒ **A search-pattern slice STILL needs `SEEKER RANGE / SNR ACQUISITION LIMITS` first**, exactly as
`docs/DEFERRALS.md` says. **This gate ships a LAW to that deferral, not a slice.**

## §II.8 STANDING OF EVERY PRE-REGISTERED FALSIFIER

| | verdict |
|---|---|
| **F0** servo smoke | **PASSES** — a real rate-limited servo flies a search; lag ≡ `ρ·τ` measured |
| **F1** the grid edge | **FIRES** — slice 42's `none ≤ 16` is 18 and 22 °/s; its sentence WITHDRAWN |
| **F2** ceiling = the knob | **REFUTED, before its own probe ran** (§I.3) — withdrawn, not run |
| **F3** the +side is the stop | **CONFIRMED** — +side excluded from every table; not re-flown (advisor) |
| **F4** the rescue gate | **CLEARED** — the verdict is bimodal with a 0.34 m ↔ 305 m empty band |
| **F5** the collapse | **HOLDS as a LOWER BOUND, and the residue is the finding** (§II.3) |
| **F6** the step | **CLEARED** — 0.0000 / +0.16 % / −0.02 % at half `dt` |
| **F7** windup | **PASSES** — and §II.4a's own gate then cuts it to a caution |

## §II.9 WHAT SLICE 43 GATE 0 LEAVES BEHIND

**No code shipped. The suite stays at 7693.** `core/src/missile.jl` carried a probe patch during the
run and was reverted before the write-up (`git checkout`, verified clean).

**TO `docs/DEFERRALS.md`** — the frontier's entry is rewritten around findings 1–5 with its
precondition intact, and slice 42 §V.4's `--` cells are corrected to 18 and 22 °/s.
**TO `docs/LESSONS.md`** — three transferable disciplines:

1. ⭐ **A GRID EDGE IS NOT A CEILING.** Slice 42 wrote *"a reported quantity that equals an authored
   threshold is the threshold"* into LESSONS.md, and in the same gate reported its own ρ grid's
   maximum as a physical limit. **A `--` in a swept table must name the sweep's bound beside it.**
2. ⭐⭐ **A FLAT ROW IS EVIDENCE OF NOTHING UNTIL YOU KNOW THE MECHANISM STOPPED SHORT OF THE KNOB.**
   "Coverage is free" and "coverage is never reached" produce the identical flat row and mean
   opposite things. **Measure what the actuator actually did, not what it was told to do.**
3. ⭐⭐ **DRIVE THE COMMAND, THEN CHECK THE ACTUATOR FOLLOWED IT.** Three separate instrument bugs in
   this family are the same bug: the probe drove the *head* instead of the *command*, or drove the
   command and never checked the head. **Carry a realized-excursion column, and a command-vs-actuator
   lag column, on every actuated probe.**

---

# ⚠⚠⚠ §III — PROBES **P6–P8**: **§II.1's FORMULA WAS MEASURED ON ONE AXIS, AND THE CONSTANT IS NOT A CONSTANT**

**An advisor catch, and it is the same shape as the four failures this arc has catalogued: the probe
was right, the table was right, and the sentence on top was WIDER THAN THE MEASUREMENT.** §II.1 quoted
`t_lock = 1.036 · deficit / ρ + τ` as *"three digits, eight cells, two windows"* — which reads as three
axes and **was one**: every one of those eight cells is at ρ = 8. Worse, the mechanism §II.1 *named*
for the 1.036 (the LOS running away while the head travels) **predicts that the number must vary with
ρ** — halve the rate, double the travel time, double the drift. ⚠ **And §II.1's own ratio column was
already monotone (1.0347 → 1.0392). A slow function of travel time was rounded to a constant, and then
the constant was called a mechanism.**

## ⭐⭐⭐ §III.1 P6 — THE RATE AXIS. **THE MULTIPLIER IS NOT CONSTANT, AND IT MOVES AS DRIFT PREDICTS**

Deficit fixed, right guess, lead clamped. `multiplier` = head travel at lock ÷ deficit:

| ρ °/s | 2 | 4 | 6 | 8 | 12 (sat) | 16 (sat) | 32 (sat) |
|---|---|---|---|---|---|---|---|
| **multiplier, deficit 2** | 1.177 | 1.076 | 1.050 | 1.036 | 1.033 | 1.033 | 1.031 |
| **multiplier, deficit 6** | **1.357** | 1.087 | 1.051 | 1.037 | 1.035 | 1.035 | 1.034 |
| **multiplier, deficit 10** | never | 1.109 | 1.058 | 1.039 | 1.039 | 1.038 | 1.038 |

> ⚠ **1.036 IS THE VALUE AT ρ = 8 AND NOWHERE ELSE.** Over the measured domain the multiplier runs
> **1.031 to 1.357**, and it rises monotonically as the sweep slows — which is the drift mechanism
> behaving exactly as it should, and which §II.1's single-axis table could not have seen.

⭐ **THE CLOSED FORM THAT PRODUCES IT.** If the LOS moves at ω while the head travels, the head must
cover the deficit *plus* whatever the target added during the trip: `travel = deficit + ω·travel/ρ`, so

> **`travel = deficit / (1 − ω/ρ)`**  and  **`t_lock = travel/ρ + τ`   (domain: ρ ≤ rate_max)**

## ⭐⭐ §III.2 P7 — **THE DRIFT TERM IS THE LOS RATE, ANCHORED AGAINST TELEMETRY AND NOT FITTED**

Convention 11 asks for an EXTERNAL anchor. ω extracted from the multiplier, `ω_fit = ρ(1 − 1/m)`,
against `ω_tel` = d(`m1.look_body_az_deg`)/dt measured directly over the same window — 15 cells, four
deficits (2, 3, 6, 10), four rates, two windows:

| | ρ = 2 | ρ = 4 | ρ = 6 | ρ = 8 |
|---|---|---|---|---|
| **deficit 2** — ω_fit / ω_tel | 0.301 / 0.278 | 0.283 / 0.258 | 0.286 / 0.253 | 0.281 / 0.251 |
| **deficit 6** | 0.526 / 0.436 | 0.321 / 0.294 | 0.291 / 0.274 | 0.288 / 0.265 |
| **deficit 10** | never | 0.394 / 0.346 | 0.328 / 0.299 | 0.302 / 0.282 |
| **deficit 3, fov 15** | 0.322 / 0.300 | 0.283 / 0.266 | 0.275 / 0.258 | 0.268 / 0.254 |

> ⭐ **THE FITTED DRIFT PARAMETER IS THE MEASURED LINE-OF-SIGHT RATE, to within 5.6–13 % on 15 cells**
> (one outlier at 20.8 %: deficit 6 at ρ = 2, the longest travel). ⚠ **AND THE RESIDUAL HAS ONE SIGN
> AND A NAMED REASON** — `ω_fit > ω_tel` on every single cell, because `ω_tel` averages the LOS rate
> across the whole search window while the drift that actually binds accrues at the END of it, where
> the rate is highest (§III.4). **It is a biased anchor in a known direction, not a scatter.**

## ⭐⭐ §III.3 P6 — **THE `+τ` TERM IS EXACT BELOW THE RATE LIMIT AND DECAYS ABOVE IT**

This half is **not** circular: the prediction uses the *measured* travel, so the residual tests only
the `+τ` claim. Across three deficits × four unsaturated rates:

> **RESIDUAL = 0.0000 s ON EVERY UNSATURATED ROW** (12 cells; the largest is −0.0001).

⭐ **AND THE IDENTITY BEHIND IT IS WHY IT IS RATE-INDEPENDENT:** below the limit the servo carries a
steady lag of `ρ·τ` degrees (measured directly in §I.0), and `ρ·τ` degrees traversed at `ρ` °/s costs
**exactly τ seconds regardless of ρ.**

⚠⚠ **AND ABOVE `rate_max` IT DOES NOT APPLY — the domain clause §II.1 was missing.** With the command
saturating the servo from tick 1 there is no steady lag to pay, and the residual against a τ-free
prediction is **+0.0228 / +0.0157 / +0.0073 s at ρ = 12 / 16 / 32** — decaying toward zero, against
0.0500 s below the limit. ⇒ **findings 2 and 5 meet exactly at ρ = `rate_max`, and both are now stated
as bounded there.**

## ⚠⚠ §III.4 P7b/P8 — **THERE IS A HARD FLOOR ON SWEEP RATE, AND IT IS NOT THE `ρ → ω` SINGULARITY**

> ⚠⚠⚠ **THE FLOOR STANDS; THE MECHANISM BELOW IS REFUTED BY §IV — annotated, not deleted.** The LOS
> blow-up table is drawn from an arm that never locks with NO search running, i.e. from the failure it
> is used to explain. The real mechanism is the UNSWEPT AXIS (§IV.2).

Deficit 2, right guess, ρ walked down:

| ρ °/s | 2.0 | 1.5 | 1.0 | 0.75 | 0.5 | 0.4 | 0.3 |
|---|---|---|---|---|---|---|---|
| **t_lock s** | 1.227 | 1.753 | **never** | **never** | **never** | **never** | **never** |

⚠ **The naive form does NOT predict this floor.** At ρ = 1 it asks for 2.96° of travel and 8.87° were
available — every failing arm swept for the same **8.867 s**, i.e. it ran out of FLIGHT, not of
coverage. ⭐ **The reason is that ω is not a constant either — it is the endgame blow-up**, measured
directly on a never-locking arm with no search at all:

| t s | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| **d(LOS)/dt °/s** | 0.271 | 0.344 | 0.455 | 0.633 | 0.948 | 1.582 | 3.190 | 9.676 | **86.05** |

> ⭐⭐ **A SEARCH IS RACING A TARGET THAT ACCELERATES AWAY FROM IT.** The LOS rate rises by **318× over
> nine seconds**, so a sweep that is merely *slow* does not acquire *late* — **it never converges at
> all**, and the floor sits at 1.0–1.5 °/s against an early LOS rate of 0.25 °/s, i.e. **≈5× the rate
> it would have to beat at t = 0.**

⚠⚠ **STATED AS MEASURED, NOT DERIVED.** A 1-D reading of the table above does not reproduce the exact
floor — the acquisition gate is the **2-D off-axis angle** and the elevation channel drifts too. **The
floor's value is quoted; its direction and its cause are measured; its exact position is NOT derived
here**, and no sentence in this file may imply otherwise.

## ⭐⭐ §III.5 THE CORRECTED LAW — replacing §II.6 items 1–2

> **1. THE COST OF ACQUIRING IS THE OVERLAP DEFICIT `|err| − fov`, NOT THE POINTING ERROR.**
>    Unchanged and exact (`err −14 / fov 12` ≡ `err −12 / fov 10` to every digit).
> **2. `travel = deficit / (1 − ω/ρ)`, and `t_lock = travel/ρ + τ`, FOR `ρ ≤ rate_max`** — where ω is
>    the line-of-sight rate, anchored against telemetry to 5.6–13 % on 15 cells with a one-sided,
>    explained residual. The `+τ` is exact (0.0000 s on 12 cells) because a `ρ·τ` lag traversed at ρ
>    costs τ seconds whatever ρ is. **Above `rate_max` the τ term decays (0.023 → 0.007 s) and finding
>    5 takes over.**
> **3.** ⚠ **SUPERSEDED BY §IV.4** — the floor (1.0–1.5 °/s) stands, but it is the UNSWEPT AXIS eating
>    the window, not the LOS rate and not a missing reversal (both measured, both refuted).
> **4–6.** §II.6 items 3, 4, 5 (never-reached coverage; the accelerating wrong-guess price; open-loop
>    windup) stand unchanged — none of them rests on the multiplier being constant.

⚠ **THE METHOD LESSON, and it is the fifth instance of the same failure in this arc:** *"three digits,
eight cells, two windows"* counted **cells**, not **AXES**. Eight cells that all share one value of a
variable measure a curve at a point. ⭐ **Count the axes a claim varies over, and name the one the
claim's own mechanism says must matter** — here the mechanism named drift, drift is a function of
time, time is a function of rate, and rate was never swept.

---

# ⭐⭐⭐ §IV — PROBES **P9/P10**: **§III.4's MECHANISM IS REFUTED, AND WHAT REPLACES IT IS THE BEST THING IN THE GATE**

**A second advisor catch, and it is the same circularity §III just criticised in §II.1.** §III.4
explained the sweep-rate floor with an LOS blow-up **measured on an arm that never locks and misses
305.112 m with no search running at all** — i.e. the endgame of a *failed* intercept, used to explain
the failure. ⚠ **And my own arithmetic had already flagged it:** the head-versus-LOS crossing works out
near t ≈ 3.7 s at ρ = 1, long before any blow-up, and I wrote the discrepancy off to "the elevation
channel" **without measuring it**. §III.4's own hedge (*"quoted as measured, not derived"*) was not
enough, because the sentence still named a cause.

## §IV.1 P9a — THE DISCRIMINATOR: **IT IS NOT THE MISSING REVERSAL EITHER**

The competing reading was that at ρ = 1 with S = 20 the head simply never reverses inside the flight,
so the pattern gets no second pass. Walk the coverage down, ρ fixed:

| ρ °/s \ S ° | 2 | 3 | 5 | 8 | 12 | 20 |
|---|---|---|---|---|---|---|
| **1.0** | never | never | **never** | **never** | never | never |
| **1.5** | never | **1.753** | 1.753 | 1.753 | 1.753 | 1.753 |
| **2.0** | never | **1.227** | 1.227 | 1.227 | 1.227 | 1.227 |

> **Coverage plays no part in the floor.** At ρ = 1 the arm fails at *every* coverage, and at ρ ≥ 1.5
> it succeeds at every coverage that exceeds the travel — the same digit throughout, which is
> finding 3 (§II.2) again. **Both candidate mechanisms are dead. The floor is something else.**

## ⭐⭐⭐ §IV.2 P9b/P10 — **A ONE-DIMENSIONAL SEARCH LOSES ITS MARGIN TO THE AXIS IT DOES NOT SWEEP**

> ⚠⚠ **THE NUMBERS STAND; ONE CAUSAL CLAUSE BELOW IS REFUTED BY §V — annotated, not deleted.** *"a slow
> one-axis search INFLATES its own deficit through the orthogonal channel while it works"* is false as
> causation: the search branch never assigns `head_el`, so the unswept drift is EXOGENOUS (measured
> byte-identical across arms, §V.1). It is a **DEADLINE**, not a feedback — and §V.2 then DERIVES the floor.

Closest angular approach on each arm, with the off-axis angle split into the swept channel and the
unswept one. The window is **10.0°**, and the shipped gate is `off_axis_angle ≤ fov` — **RADIAL**:

| ρ °/s | S ° | t s | **off-axis °** | **Δaz (swept)** | **Δel (UNSWEPT)** | locks? |
|---|---|---|---|---|---|---|
| **1.0** | 20 | 3.994 | **10.0656** | **9.7519** | **2.4934** | **no** |
| **1.0** | 8 | 3.994 | **10.0656** | **9.7519** | **2.4934** | **no** |
| **1.0** | 5 | 3.994 | **10.0656** | **9.7519** | **2.4934** | **no** |
| 1.5 | 20 | 5.885 | 0.0002 | 0.0001 | −0.0000 | YES |
| 2.0 | 20 | 4.417 | 0.0001 | 0.0001 | −0.0000 | YES |
| 4.0 | 20 | 6.920 | 0.0001 | 0.0000 | −0.0001 | YES |
| 8.0 | 20 | 6.920 | 0.0001 | −0.0000 | −0.0001 | YES |

> ⭐⭐⭐ **THE ρ = 1 HEAD CLOSED THE SWEPT AXIS TO 9.7519° — INSIDE A 10° WINDOW — AND STILL NEVER
> ACQUIRED**, because **2.4934° of drift on the axis the search never touches** made the radial
> off-axis angle 10.0656°. It misses by **0.066°**, and it misses identically at S = 5, 8 and 20.
>
> **THE SWEEP-RATE FLOOR IS NOT A RACE AGAINST THE LINE-OF-SIGHT RATE. IT IS THE SEARCH TAKING LONG
> ENOUGH FOR THE UNSWEPT AXIS TO EAT THE WINDOW.**

⭐ **AND THIS IS FINDING 1 AGAIN, WHICH IS WHAT SAYS IT IS THE RIGHT MECHANISM AND NOT A THIRD STORY:**
the deficit is a **radial** quantity. **A slow one-axis search does not merely take longer to close its
own axis — it inflates its own deficit through the orthogonal channel while it works.** The robust
number is not the 0.066° shortfall (which is narrow, and is quoted as narrow): it is that **2.4934° of
a 10° window radius — 25 % of it — is consumed by an axis the search never moves.**

⚠ **F6 APPLIED TO THIS FINDING TOO, because a 0.066° margin is exactly the shape slice 42 died to:**

| dt | 2e−3 | 1e−3 | 5e−4 |
|---|---|---|---|
| **off-axis °** | 10.0647 | 10.0656 | 10.0661 |
| **Δel °** | 2.4934 | 2.4934 | 2.4929 |

> ⭐ **IT DOES NOT HALVE — IT DOES NOT MOVE AT ALL** (4 digits stable over a 4× range of step). Slice
> 42's knife-edge halved when the step halved; this is not that.

## ⭐⭐ §IV.3 **AND IT LANDS ON AN EXISTING DEFERRAL WITH THE ARM THAT DEFERRAL WAS MISSING**

`docs/DEFERRALS.md` carries **a RECTANGULAR / PER-AXIS FOV** from slice 34, whose gate 1 recorded that
the circular window *"rests on a SPECIES argument because no flying arm had ever bound"* the shape.

> ⭐⭐ **HERE IS ONE. A per-axis window of the same 10° half-width would LOCK this arm** — Δaz = 9.75 < 10
> **and** Δel = 2.49 < 10, both inside — while the shipped radial `hypot` gate holds it out at 10.0656.
> **This is the first flying arm in the family where the WINDOW'S SHAPE, not its size, decides
> acquisition.**

⚠ Quoted with its margin: the *verdict* flip rests on 0.066°, which is narrow (though step-independent
and 100× the per-tick LOS motion). **The non-marginal claim is the 25 % of window radius spent on the
unswept axis; the rectangular-vs-circular verdict flip is the narrow one.**

## ⭐ §IV.4 THE CORRECTED FLOOR — replacing §III.5 item 3

> **3.** ⚠ **SUPERSEDED BY §V.3** — the axis reading is right, the CAUSAL clause is not, and the floor is
>    now DERIVED (ρ* = 1.0174 °/s against a flown bracket of (1.01, 1.02]). Original text follows.
>    **THERE IS A FLOOR ON SWEEP RATE (1.0–1.5 °/s here), AND IT IS NEITHER A RACE AGAINST THE LOS RATE
>    NOR A MISSING REVERSAL — both were measured and both are refuted.** ⭐⭐ **A one-dimensional search
>    inside a two-dimensional window loses its margin to the axis it does not sweep:** at ρ = 1 the
>    swept axis closed to 9.75° inside a 10° window and the arm still failed, held out by 2.49° of
>    drift on the unswept axis (25 % of the window radius). **Sweep slowly enough and the orthogonal
>    channel eats the window before the swept one closes.**

⚠ **AND §III.4's LOS-RATE TABLE IS NOT DELETED, BUT ITS ROLE IS DEMOTED:** the 318× rise (0.271 → 86.05
°/s over t = 1 → 9 s) is real and correctly measured, and it is why a *late* acquisition is worthless.
**It is not why the ρ = 1 arm fails.**

⚠⚠ **THE METHOD LESSON, and it is the SIXTH instance in this arc:** §III correctly convicted §II.1 of
fitting a constant along one axis — **and then explained a floor with a table drawn from the very arm
that failed.** *A hedge is not a measurement.* Writing *"quoted as measured, not derived"* under a
sentence that still names a cause does not make the cause measured. **If a claim names a mechanism,
either measure that mechanism on an arm that is not the failure itself, or name no mechanism at all.**

---

# ⭐⭐⭐ §V — PROBES **P11/P12**: **THE UNSWEPT AXIS IS EXOGENOUS — IT IS A DEADLINE, NOT A FEEDBACK — AND THE FLOOR DERIVES**

**A third advisor catch, and this one was readable from the patch rather than needing a probe.** The
search branch is `head_az, head_el = head_clamp(_s_cmd, head_el, stop_h)` — **elevation passes
through untouched**, and `head_el` is seeded once at birth. So `Δel(t)` cannot depend on ρ, on S, or
on whether a search runs at all. ⚠ **§IV.2's sentence — *"a slow one-axis search INFLATES its own
deficit through the orthogonal channel while it works"* — is therefore FALSE AS CAUSATION**, and it is
the third instance of the pattern §IV.4 had just banked into `docs/LESSONS.md`.

## ⭐⭐ §V.1 P11 — **MEASURED, NOT INFERRED FROM THE CODE: THE COLUMN IS BYTE-IDENTICAL**

`Δaz` and `Δel` at matched times, four arms:

| t s | **Δel, no search** | **Δel, ρ = 1** | **Δel, ρ = 1.5** | **Δel, ρ = 4** | Δaz no search | Δaz ρ = 1 |
|---|---|---|---|---|---|---|
| 1 | **0.4093** | **0.4093** | **0.4093** | 0.3812 | 12.270 | 11.319 |
| 2 | **0.9827** | **0.9827** | 0.6459 † | 0.0229 † | 12.614 | 10.663 |
| 3 | **1.6591** | **1.6591** | −0.0104 † | −0.0101 † | 13.068 | 10.117 |
| 4 | **2.4991** | **2.4991** | −0.0156 † | −0.0154 † | 13.701 | 9.750 |
| 5 | **3.6243** | **3.6243** | −0.0212 † | −0.0211 † | 14.649 | 9.698 |

† = that arm has already LOCKED, after which the tracker drives elevation to zero. **On every tick
before lock the columns agree to the last digit printed.**

> ⭐⭐ **THE UNSWEPT AXIS IS EXOGENOUS. It spends the window's radius on a schedule the search does not
> control, and the sweep rate only decides whether the SWEPT axis closes before that budget is gone.**
> **A DEADLINE, NOT A FEEDBACK** — same numbers, same floor, same rectangular-window consequence, and
> a different mechanism sentence.

⭐ **AND THE SWEPT CHANNEL HAS ITS OWN EXACT FORM, verified on the same five samples:**
`Δaz(t, ρ) = Δaz₀(t) − ρ·(t − τ)` — check at ρ = 1: 12.270 − 1·0.95 = 11.320 against a measured
11.319, and so on down the column to 0.001°. **The `τ` is §III.3's servo lag, appearing here a second
time and in a different quantity.**

## ⭐⭐⭐ §V.2 P12 — **THE FLOOR IS NOW DERIVED, AND IT WAS DERIVED FROM AN ARM THAT NEVER LOCKS**

Put the two together against the **radial** gate. The arm acquires iff, at some instant inside the
flight, azimuth has fallen inside the budget the unswept axis leaves it:

> **`|Δaz₀(t) − ρ·(t − τ)| ≤ √(fov² − Δel(t)²)`**
> ⇒ **`ρ_req(t) = [Δaz₀(t) − √(fov² − Δel(t)²)] / (t − τ)`**, and the floor is **`min over t`**.

Both curves come from the **no-search arm alone** — the one that never acquires anything:

| t s | 1.0 | 2.0 | 3.0 | 3.5 | **4.0** | 4.5 | 5.0 | 6.0 | 7.0 |
|---|---|---|---|---|---|---|---|---|---|
| Δel ° (budget eaten) | 0.409 | 0.983 | 1.659 | 2.053 | 2.499 | 3.014 | 3.624 | 5.319 | 8.425 |
| azimuth budget ° | 9.992 | 9.952 | 9.861 | 9.787 | 9.683 | 9.535 | 9.320 | 8.468 | 5.387 |
| **ρ required °/s** | 2.399 | 1.365 | 1.087 | 1.035 | **1.017** | 1.031 | 1.077 | 1.305 | 2.019 |

> ⭐⭐ **THE REQUIRED RATE IS U-SHAPED IN TIME — THERE IS A WINDOW OF OPPORTUNITY.** Too early and the
> swept axis has not closed yet; too late and the unswept axis has eaten the budget. **The floor is
> the bottom of that U: ρ\* = 1.0174 °/s, at t = 4.00 s.**

**AND THEN IT WAS FLOWN — a prediction, not a fit:**

| ρ °/s | 0.95 | 1.00 | **1.01** | **1.02** | 1.03 | 1.05 | 1.10 | 1.25 | 1.50 |
|---|---|---|---|---|---|---|---|---|---|
| **t_lock s** | never | never | **never** | **3.809** | 3.570 | 3.307 | 2.915 | 2.289 | 1.753 |
| miss (m) | 305.112 | 305.112 | 305.112 | 0.295 | 0.087 | 0.284 | 0.167 | 0.006 | 0.276 |

> ⭐⭐⭐ **THE MEASURED FLOOR IS THE BRACKET (1.01, 1.02], AND THE DERIVED VALUE 1.0174 LIES INSIDE IT —
> BETTER THAN 1 %.** And the derivation predicts the acquisition TIME as well: it says the opportunity
> is at t = 4.00 s and the first surviving arm locks at **t = 3.809 s**.
>
> ⇒ **§III.4's *"quoted as MEASURED, not derived"* and §IV.4's declining to attempt it are both
> discharged. The floor is derived, and it is derived from the failing arm's own two curves.**

## ⭐⭐ §V.3 THE CORRECTED FLOOR — replacing §IV.4, which replaced §III.5 item 3

> **3. THERE IS A FLOOR ON SWEEP RATE, AND IT IS THE **DEADLINE** SET BY THE AXIS THE SEARCH DOES NOT
>    SWEEP.** The unswept channel's drift is **exogenous** — byte-identical whether a search runs or
>    not — and it eats the *radial* window's radius on its own schedule. The sweep rate only decides
>    whether the swept axis closes first. ⚠ **NOT** a race against the LOS rate (§III.4, refuted),
>    **NOT** a missing reversal (§IV.1, refuted), and **NOT** the search inflating its own deficit
>    (§IV.2, refuted here — the code cannot do it and the measurement says it does not).
>    ⭐ **`ρ* = min over t of [Δaz₀(t) − √(fov² − Δel(t)²)] / (t − τ)` = 1.0174 °/s, against a flown
>    bracket of (1.01, 1.02].** The curve is U-shaped: **a search has a best moment, and one that
>    misses it cannot recover by continuing.**

⚠ **THE 25 % FIGURE SURVIVES AND ITS SENTENCE CHANGES.** At the opportunity the unswept axis holds
2.4991° of a 10° radius — a quarter of it — spent on a channel the search never moves. **That is what
it COSTS; it is not something the search CAUSED.**

⚠ **PRECISION ON THE SLICE-34 CITATION** (§IV.3): slice 34's gate 2 §2.5 *did* bind the **stop** for
the first time. **This arm binds the WINDOW**, which is the other half of the same species argument
and is what the rectangular/per-axis deferral is actually about. The claim is *"first flying arm where
the window's SHAPE decides acquisition"* — not *"first time anything in the family was bound"*.

⚠⚠ **THE METHOD LESSON, and it is the THIRD correction in this one gate:** all three had the same
shape — *the measurement was right and the causal clause on top of it was wider than the measurement*.
§II.1 fitted along one axis; §III.4 drew a mechanism from the failing arm; §IV.2 attributed to the
search an effect the search's own code cannot produce. ⭐ **The cheapest guard is the one that caught
the third: READ THE BRANCH AND ASK WHICH STATE IT WRITES. If the quantity in your causal sentence is
never assigned by the mechanism you are crediting, the sentence is wrong before any probe runs.**

---

# ⭐⭐⭐ §VI — PROBE **P13**: **THE DERIVATION HOLDS ON GEOMETRIES IT WAS NOT TUNED ON**

§V.2 derived and flew ρ\* on **one** cell. The form is general — both curves come off any no-search
arm — but one confirmation is a worked example, not a law. Derived on three further geometries and
flown on each:

| err ° | fov ° | **deficit °** | **ρ\* PREDICTED** | flown bracket | **t\* PREDICTED** | **t_lock MEASURED** |
|---|---|---|---|---|---|---|
| −12 | 10 | 2 | **1.0174** | (1.0074, **1.0174**] | 4.03 | **3.961** |
| −16 | 10 | 6 | **1.8817** | (1.8717, **1.8817**] | 5.16 | **5.104** |
| −20 | 10 | 10 | **2.6259** | (2.6159, **2.6259**] | 5.65 | **5.597** |
| −18 | 15 | 3 | **1.2193** | (1.2093, **1.2193**] | 4.59 | **4.529** |

> ⭐⭐⭐ **FOUR FOR FOUR, AND EACH TO THE RESOLUTION OF THE TEST GRID.** Across a **5× range of deficit**
> and **two window sizes**, every predicted floor lands inside its flown bracket — and the bracket is
> **one grid step (0.01 °/s) wide.** ⭐ **The derivation also calls the ACQUISITION TIME**, predicted
> 4.03 / 5.16 / 5.65 / 4.59 s against measured 3.961 / 5.104 / 5.597 / 4.529 — within 0.07 s on all four.

⚠ **STATED PRECISELY, BECAUSE THE GRID IS ANCHORED ON THE PREDICTION:** the ρ ladder runs
`ρ*−0.05 : 0.01 : ρ*+0.06`, so ρ\* is itself a grid point and the test is the sharp one — **does the arm
lock at exactly ρ\*, and fail at ρ\*−0.01?** It does, on all four. That is a stronger test than a wide
bracket, not a weaker one, but it is not a blind bracket and must not be quoted as one.

## ⚠ §VI.1 ONE CLAIM MARKED **DERIVED, NOT FLOWN**

> *"A search that misses the moment cannot recover by continuing"* (§V.2/§V.3) **rests on the rising
> right arm of the ρ_req curve, which is derived, not flown.** What IS flown: the ρ\*−0.01 arm searches
> for the entire engagement — well past the optimum — and never locks; and the ρ\* arm locks inside the
> derived window (3.961 s against a predicted 4.03). ⚠ **No flown arm has acquired ON the right arm of
> the U**, and by construction none can, since a higher rate always locks earlier. **The U's left arm
> and its minimum are confirmed; its right arm is a property of the derived curve.**

## ⭐⭐ §VI.2 THE LAW AS IT NOW STANDS — the final form

> **1. THE COST OF ACQUIRING IS THE OVERLAP DEFICIT `|err| − fov`, NOT THE POINTING ERROR.**
>    Exact: `err −14 / fov 12` ≡ `err −12 / fov 10` to every digit printed.
> **2. `travel = deficit/(1 − ω/ρ)`, `t_lock = travel/ρ + τ`, FOR `ρ ≤ rate_max`.** ω is the LOS rate
>    (anchored against telemetry, 15 cells); `+τ` is exact because a `ρ·τ` lag traversed at ρ costs τ
>    seconds whatever ρ is. Above `rate_max` the τ term decays and finding 5 takes over.
> **3. GUESS THE DIRECTION RIGHT AND COVERAGE IS NEVER REACHED** — not free, never *used*: lock at
>    2.07° into a pattern authored 3–30° wide, same digit across a 10× range.
> **4. GUESS WRONG AND COVERAGE COSTS `2S` OF TRAVEL AT AN ACCELERATING PRICE** — 5 % over the
>    geometric bound at S = 5, 39 % at S = 20, never-locks by S = 25.
> **5. THE HEAD, NOT THE COMMAND, IS WHAT SEARCHES.** An open-loop generator commanded above
>    `rate_max` converts excess rate into LOST COVERAGE and then outright failure. ⚠ A caution, not an
>    architecture — `ρ ← min(ρ, rate_max)` gives the same verdict in all 16 cells.
> **6. ⭐⭐⭐ THE FLOOR IS A DEADLINE SET BY THE AXIS THE SEARCH DOES NOT SWEEP, AND IT IS DERIVABLE:**
>    **`ρ* = min over t of [Δaz₀(t) − √(fov² − Δel(t)²)] / (t − τ)`** — computed from the arm that never
>    acquires, confirmed 4/4 to 0.01 °/s across a 5× range of deficit and two windows, and it predicts
>    the acquisition time to 0.07 s as well. **A search has a best moment.**

⚠⚠ **AND THE SLICE IS STILL BLOCKED (§0.1, §II.7).** Finding 1 makes the free-window objection
sharper, not weaker. ⭐ **What finding 6 adds to the blocked deferral is a second reason the window
matters that has nothing to do with sensitivity: the window's SHAPE.** A per-axis gate of the same
half-width locks the arm the radial gate rejects — so `SEEKER RANGE / SNR ACQUISITION LIMITS` is no
longer the *only* precondition that would make a search-pattern slice motivatable; the
**RECTANGULAR / PER-AXIS FOV** deferral would do it too, and it is the cheaper of the two.
