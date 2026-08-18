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
