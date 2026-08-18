# Slice 42 — **A SEARCH PATTERN: BUYING COVERAGE WITH TIME INSTEAD OF WITH GLASS** (§11 Tier-A)

**STATUS: GATE 0, PRE-PROBE. Written before any number for this slice exists.**
Everything below §0.2 is a *prediction, a domain, or a falsifier* — never a measurement. Where a probe
refutes a prediction the refutation is marked AT the prediction and recorded in §I; the prediction is
never quietly edited to match (slice 41's discipline, which is the only reason that kill was cheap).

The candidate is the one `docs/DEFERRALS.md` names as *"THE NEVER-ACQUIRED SIDE NEEDS A RE-CUE, NOT A
COAST"* — surfaced, named and explicitly **not taken** by slice 37's gate 0
(`docs/plans/slice37.md` §"What the probes surfaced that IS live").

---

## ⚠⚠ §0.0 THE ADMISSION TICKET — WHY THIS IS NOT THE MEMORY TRACK, WHICH IS DEAD

`docs/DEFERRALS.md` warns about re-importing a killed framing more loudly than about anything else,
and the killed framing sits one paragraph away from this candidate in the same file. So, first:

> **The memory track died because a break mid-flight is not an episode — it is the rest of the flight
> (6.0–7.9 s of it), and what makes it terminal is the ESTIMATOR's frozen rate destroying the guidance
> solution, not where the head points.** This slice is about the OTHER half of slice 36's basket: the
> arms that **never acquired at all** (`err ≤ −12`, `in_fov` false on tick 1, `:seek_init` never flips,
> every rate `0.0` — `docs/plans/slice37.md` §0.1). There is no track to remember there, nothing to
> coast on, and no estimator state to preserve. **A head that has never seen its target does not need
> a memory — it needs to be told, or it needs to look.** That is a different subsystem, and it is the
> one thing slice 37's five probes found that they did not spend.

⚠ **AND THE TWO HALVES ARE MEASURED TO BE DIFFERENT MECHANISMS, NOT ASSUMED TO BE** — slice 37 §0.1:
the never-acquired arms show NO line-of-sight reversal (+18.105° → +73.784°, monotone) while the
locked-then-lost arms run away to ≈ −92°. Two signatures, two failures.

## §0.1 THE CEILING AND ITS DOMAIN — WHAT IS ALREADY MEASURED, AND WHAT IT IS NOT

Slice 37's `:leak` arm (§0.3) fed the head the measured angles the seam writes unconditionally at
`missile.jl:2328-2330` — **angles that physically do not exist out of the window**. It is an ORACLE,
its provenance is LOGGED (the seam's unconditional `head_tgt` write, NOT the probe's own seeding: the
probe seeds the birth angle +6.105365° and by tick 1 the key already reads +18.106199°, tracking the
true body-frame LOS to a thousandth of a degree while `seek_init` is still false).

| `err` ° | shipped (no cue) | `:leak` (perfect cue) |
|---|---|---|
| −12 | 3620.675 m | **0.110 m** |
| −14 | 3620.675 m | **0.131 m** |
| −18 | 3620.675 m | **2350.299 m — STILL A MISS** |

⚠⚠ **THIS IS A CEILING, NOT A PAYOFF, AND NOTHING IN THIS SLICE MAY QUOTE IT AS A RESULT.** It is what
a *perfect, instantaneous, always-correct* cue reaches. The −18 row is the more useful one: **even a
perfect cue has a domain**, because a head born 18° off a 10° window cannot close before the geometry
runs away. The floor everything internal is stuck at is 3620.675 m.

The wire is `scenarios/slice36_handover.yaml` (seed 32, crossing target `vy = +200`, NO glass,
window 10°, servo 8 °/s, stop 30°, τ = 0.05, `n_pn = 8`), with `gimbal_handover_err_deg` as the axis —
the same wire all of slice 37's gate 0 flew, which is what licenses comparing to those numbers at all.

## §0.2 THE CANDIDATE MECHANISM, AND THE LESSON IT WOULD OWN IF IT SURVIVES

A head that is out of its window and has never locked currently **does nothing** (`missile.jl:2334`,
the NEVER-LOCKED branch: rates 0.0, `seek_init` stays false — a defined, finite, non-throwing state,
and the servo above it never slews because the slew gate requires the target already inside `fov_h`).
The candidate gives it a **SEARCH PATTERN**: while `!seek_init`, the head sweeps its gimbal over an
authored pattern at the servo's own rate limit until the detector window falls on the target.

⭐ **The lesson, if it survives:** a real seeker's window is narrow because a narrow window is what buys
sensitivity and resolution — so you cannot simply widen it, which is what slice 37 §0.2 measured as the
alternative rescue (min window that holds: 12.5° at `err = −12`, 15° at −14, 20° at −18). **A search
buys the COVERAGE of a wide window while keeping the DETECTOR of a narrow one, and it pays for it in
TIME — and here the target is running away at roughly the speed the head can search.** The exchange
rate between coverage and time, on a wire where that race is marginal, is the thing to measure.

⚠ **AND THAT IS EXACTLY WHY THE SLICE CAN DIE.** The servo's rate limit is 8 °/s; the body-frame LOS on
these arms travels +18.105° → +73.784° over the flight, an average of ≈ 7.4 °/s. **The head barely
outruns the thing it is chasing**, and it must do so while ALSO covering the sign it guessed wrong.

## ⚠⚠ §0.3 THE PRE-REGISTERED FALSIFIERS — FIXED IN WRITING BEFORE ANY MEASUREMENT EXISTS

Verdict language for every probe below. The wire's two attractors are ≈ 0.19 m (a hit) and
≈ 3620 m (a total miss), four orders of magnitude apart, so **rescued := miss ≤ 1.0 m** and
**not rescued := miss ≥ 100 m**; no cell is expected in between and any cell that IS gets quoted.

### F0 — THE TIME BUDGET (P0 kills the slice here or nowhere)

A search must sweep the coverage it needs at the rate it has. At `err = −12` that is 12° of angle at
8 °/s = **1.5 s** before the head can even be pointing the right way, and 1.75 s at −14 — and that is a
LOWER BOUND, because the LOS is moving away while the head sweeps.

> **F0 FIRES ⇒ THE SLICE IS DEAD AT P0.** If a cue that is otherwise PERFECT but DELAYED by
> Δt = 1.5 s fails to rescue `err = −12` (miss ≥ 100 m), then no autonomous search can win at the
> EASIEST never-acquired cell, the domain is empty, and there is nothing to build. The delay sweep is
> run at Δt ∈ {0, 0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0} s and the whole ladder is printed so a reader
> can redraw any line — slice 37's threshold-free discipline.

⚠ **ACQUISITION TIME IS READ OFF THE FLOWN ENTITY — the tick `:seek_init` flips — NEVER from the
authored Δt** (advisor). A cue delivered at Δt still needs the servo to slew through it, so the budget
that matters is when the lock actually happens, and the two differ by up to `off/rate` seconds.

⚠ **CONTAMINATION COLUMNS ON EVERY ARM, READ FIRST** (`CLAUDE.md`'s harness-traps rule, and slice 41's
own death by a clamp that bound 78 % of band ticks): `head_sat` (the servo rate limit — **expected to
bind by construction here**, since 8 °/s against a 7.4 °/s LOS is a near-saturated chase) and `aero`
(α_max ticks). A "search does not help" reading that sits behind a saturated servo is a statement
about the rate limit, not about searching.

### F2 — THE DIRECTION BLOCKER (runs SECOND, before any pattern is designed)

⚠⚠ **THE NEVER-ACQUIRED SET ON THIS WIRE IS ONE-SIDED, AND THAT MAKES A ONE-WAY SCAN A RIGGED TEST.**
The set is `err ≤ −12` — the head is born BELOW a RISING line of sight and is left behind. (The +side
births the head ABOVE, where the rising LOS sweeps INTO it, which is why `err = +2 … +12` all lock on
tick 1 and fail LATER, by the other mechanism.) So a scan authored to sweep UP wins using knowledge
the missile does not have, and **a test whose control also passes is not a test** (slice 41 §IV.8b).

> **F2 IS A SCOPING BLOCKER, NOT A RESULT.** Before any pattern is designed, find a MIRRORED cell — a
> never-acquired arm where the head is born on the OTHER side. The candidate is slice 36's own shipped
> control, the REVERSED CROSSING (`vy = −200`, where the body-frame LOS is nearly static, a 2.2° swing
> against this geometry's 33.2°, and the requirement is EXACTLY `|err|` at every servo rate — a tooth
> in `test_missile.jl`). If a mirrored never-acquired cell exists, the pattern must be **sign-blind by
> construction** and the slice has a real domain. **If it does not exist, that is written down and the
> slice is scoped to a SYMMETRIC two-way scan whose cost is the factor measured** — a one-way scan
> tuned to a one-sided wire does not ship.

### F1 — THE REPARAMETERIZATION GATE (the gate 39 and 41 both died at)

Slice 37 §0.2 already measured the alternative: widening the window rescues these cells at 12.5 / 15 /
20°. A scan of half-width `S` covers `fov/2 + S`. **If the verdict of every scan cell is predicted by
that single number, a search is a reparameterization of the window and the slice dies.**

> **F1 SURVIVAL CRITERION, FIXED NOW:** there must exist **a pair of scan cells with the SAME coverage
> `S` and DIFFERENT scan rate `ρ` whose verdicts are OPPOSITE** (one ≤ 1.0 m, one ≥ 100 m) — a 2-D
> surface `(S, ρ)` that a 1-D window cannot reproduce. **If the rescue set is a function of `S` alone
> across the whole `ρ` domain, F1 FIRES and the slice is dead.**
>
> ⚠ **THE CONTROL SHIPS IN THE SAME TABLE** (advisor): the shipped 10° window with no scan at all. If
> the scan arms, the widened-window arms and the control all land on the same attractor, nothing has
> been measured, and by slice 41 §IV.8b that is a DEGENERATE leg regardless of what the falsifier says
> by the letter.
>
> ⚠ **NON-MONOTONICITY IN `S` IS NOT THE DISCRIMINATOR AND MAY NOT BE USED AS ONE.** `k` (28), `ω_n`
> (40) and σ_seek (25) were each DISQUALIFIED by non-monotonicity in this project; an optimum in scan
> width would be suggestive at best, and the opposite-verdict pair above needs no curve shape at all.

## §0.4 PROBE ORDER (and the reason it is this order)

**P0 (time budget) → P2 (direction blocker) → P1 (degeneracy gate) → only then a kernel.**
P0 can kill the slice before a pattern exists; P2 can invalidate every pattern before one is designed;
P1 is the gate that killed 39 and 41 and it is answered before a key, a rung or a scenario is written.
No kernel, no comp key and no scenario is authored until all three are answered in this file.

## §0.5 OPEN AT PRE-PROBE TIME — stated so a later answer cannot be mistaken for a prediction

1. Does a mirrored never-acquired cell exist anywhere on this family (F2)? **UNKNOWN.**
2. Is the search's natural axis the coverage `S`, the rate `ρ`, or the PATTERN (one-way / symmetric /
   expanding)? **UNDECIDED** — it depends on F2's answer and on P0's ladder.
3. Is the second-cue variant (a datalink from the launching platform — the honest `:leak`) the same
   slice or a different one? **DEFERRED BY CONVENTION 9** — one lesson per scenario. It is named here
   so that a later slice does not present it as this one's finding.

---

# §I — GATE 0, PROBE **P0** (2026-08-18): THE TIME BUDGET, AND A CEILING THAT WAS NOT WHAT IT SAID

**The patch:** `core/src/missile.jl`'s body-arm slew gate and slew call, four out-of-window head
behaviours behind `:probe_cue_mode`, applied and reverted around the run (slice 35/37 precedent).
**VALIDATION FIRST:** the `:always` arm reproduces slice 37 §0.3's published `:leak` column to the
digit — **0.110 / 0.131 / 2350.299** at err = −12 / −14 / −18. Nothing below is readable without it.

## ⭐⭐ §I.1 THE CEILING SPLITS, AND A SEARCH OWNS NONE OF IT ALONE

Four arms, all at Δt = 0 (a PERFECT, INSTANT cue), on the never-acquired cells:

| err ° | CONTROL | `:mem_only` (slice 37 `:memory`) | cue **stops at lock** | cue + **honest memory** | `:always` (oracle) |
|---|---|---|---|---|---|
| −12 | 3620.675 | 3620.675 | **3620.675** | **0.110** | 0.110 |
| −14 | 3620.675 | 3620.675 | **3620.675** | **0.131** | 0.131 |
| −18 | 3620.675 | 3620.675 | **3620.675** | **2350.299** | 2350.299 |

⭐⭐⭐ **A CUE THAT STOPS WHEN THE SEARCH SUCCEEDS RESCUES NOTHING — AND CUE + COAST REPRODUCES THE
ORACLE EXACTLY, TO THE DIGIT, ON ALL THREE CELLS.** The two halves are each worth ZERO alone and the
whole difference together. ⇒ **the 0.110 m that `docs/DEFERRALS.md` offers this slice as its ceiling
is NOT an acquisition number**: an acquisition-only re-cue reaches none of it.

⭐ **AND THE MECHANISM IS ONE TICK.** `cue stops at lock` locks at exactly the same instant as the
oracle (t = 0.477 / 1.001 / 2.354 s) and then loses the window on the **very next tick** —
`hold_max = 0.001 s`, one millisecond — and never gets it back. With the honest coast covering that
single tick the same head then holds **continuously for 10.58 s** (`hold_max` 10.580, `in%` 95.6,
`nreacq` 1). **The entire 3.6 km hangs on one tick.**

⭐⭐ **WHY, AND IT IS AN ARCHITECTURE FINDING RATHER THAN A TUNING ONE.** Acquisition lands the target
on the **window EDGE** (`off@lock` = 9.997–9.999° against a 10.0° window, every arm), because the
servo's 8 °/s barely outruns the body-frame LOS's ≈ 7.4 °/s — the near-saturated chase the plan
predicted (`sat%` 6.5–32 at lock). And the shipped head **only slews when the target is already
inside the window** (`missile.jl:2086`). ⇒ **the slew gate is a latch that can be entered but never
re-entered: a head that acquires at the edge is one tick from losing its target for the rest of the
flight.** That is the same "a break is the rest of the flight" slice 37 measured, now visible at its
own birth.

⚠⚠ **AND IT REOPENS SLICE 37 §0.4 WITHOUT CONTRADICTING IT.** That probe looked for an EPISODIC break
and found none — *"the window either holds outright or breaks terminally"*. That is TRUE on the
shipped wire and it is true **because these arms never acquire at all**. Once anything gets the head
to the window edge, the very next tick is a 1-ms break, and slice 37's own honest coast is worth the
whole engagement there. **The memory track is not resurrected by this** — it is worth nothing on its
own here (`:mem_only` = 3620.675, unchanged), exactly as slice 37 measured. What is new is that it is
worth everything *downstream of an acquisition that does not yet exist*.

## ⚠⚠ §I.2 THE TIME BUDGET — **F0 FIRES BY THE LETTER**

Delay sweep in the only mode that rescues anything (`:cue_mem`), Δt = when the cue starts:

| err ° | Δt 0 | 0.10 | 0.25 | 0.50 | 0.75 | 1.00 → 4.00 |
|---|---|---|---|---|---|---|
| −12 | **0.007–0.110** | **0.019** | **0.007** | 2443.001 | 2407.566 | 3620.675 (never locks) |
| −14 | **0.131** | **0.249** | 2443.001 | 2407.566 | 3620.675 | 3620.675 |
| −18 | 2350.299 | 2244.921 | 3620.675 | 3620.675 | 3620.675 | 3620.675 |

> **F0 AS PRE-REGISTERED FIRES.** The falsifier required Δt = 1.5 s to rescue err = −12 (the time a
> 12° sweep costs at 8 °/s). The measured budget is **between 0.25 and 0.50 s** — **6× short** — and
> at −14 it is between 0.10 and 0.25 s against a 1.75 s sweep, **~10× short**. At −18 no delay
> rescues anything, and Δt = 0 is a 2.35 km miss regardless.

⚠ **CONTAMINATION, READ BEFORE THE VERDICT** (and it does not overturn it): `sat%` is 33–43 % on the
rescued arms at −12/−14 and **99.8 % at −18** with `aero%` 29.2, so **the −18 row is a statement
about the rate limit and the α ceiling, not about cueing** and is not quoted as a search result. The
−12/−14 rows are clean enough to read (`aero%` ≤ 3.6).

## ⚠⚠⚠ §I.3 WHAT F0 ACTUALLY MEASURED — STATED BEFORE ANY RE-SCOPE IS PROPOSED

**The falsifier fired, and the measurement ALSO showed the falsifier models the wrong thing.** Both
halves are recorded, in this order, because the second half is exactly the move by which a dead slice
gets dishonestly rescued and it must be visible as a claim rather than smuggled in as a correction:

A delayed oracle **stands still** for Δt and then goes straight at the target. **A search does not
stand still — it sweeps.** And a one-way search sweeping in the CORRECT direction at the servo's rate
limit is not the Δt = 1.5 s arm at all: it is **the Δt = 0 arm**, because both slew azimuth up at
8 °/s. So what §I.2 prices is not "the sweep a search needs" — it is **the cost of guessing the
direction WRONG**, and by that reading the budget is even tighter than the table says, since a
wrong-way sweep must also travel back over the ground it lost.

⇒ **F0's number stands and F0's INTERPRETATION does not.** The honest restatement of what P0 leaves:

> On this wire a search that knows which way to look is free, and a search that must guess is
> bankrupt within a quarter of a second. **The slice's lesson, if it has one, is the cost of not
> knowing which way to look** — which makes §0.3's F2 (the DIRECTION BLOCKER) not a scoping question
> but the whole slice.

⚠ **AND F2 IS THEREFORE PROMOTED TO THE DECIDING PROBE, WITH THE ORACLE REMOVED ENTIRELY.** No arm of
the next probe may contain a cue: the head sweeps blind, at an authored rate, in an authored
direction, reversing at an authored half-width, and the honest coast runs after lock. If a blind
symmetric search cannot rescue a single cell that a wide window does not already rescue, the slice
dies at P2 and P1 is never reached.
