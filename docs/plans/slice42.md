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

---

# §II — PROBE **P2** (2026-08-18): THE BLIND SEARCH ON THE SHIPPED (RECEDING) WIRE

No oracle in any arm. The head sweeps azimuth at rate ρ in direction d, reversing at half-width S
about its BIRTH angle, and stops for good on the first lock. Grid: d ∈ {+1, −1} × S ∈ {5, 10, 20, 30}°
× ρ ∈ {2, 4, 8} °/s, on err ∈ {−12, −14, −18}. `d = +1` is the lucky guess here (the target is above
the birth angle); a missile with a two-sided handover error cannot know which it has.

| err ° | CONTROL | d **+1**, ρ 2 / 4 | d **+1**, ρ **8** | d **−1**, ANY S, ρ 2 / 4 / 8 |
|---|---|---|---|---|
| −12 | 3620.675 | 3620.675 | **0.007** | 3620.675 — every one of 12 cells |
| −14 | 3620.675 | 3620.675 | **0.240** | 3620.675 — every one of 12 cells |
| −18 | 3620.675 | 3620.675 | 2348.358 (still a miss) | 3620.675 — every one of 12 cells |

⭐ **THE LUCKY GUESS AT THE FULL SERVO RATE RESCUES, AND IT BEATS THE PERFECT CUE** — 0.007 m against
the oracle's 0.110 m at err = −12 (§I.1), from a head that knows nothing. Below the rate limit
(ρ = 2, 4) nothing is ever rescued: the sweep is slower than the LOS's own ≈7.4 °/s and never closes.

⭐⭐ **AND THE WRONG GUESS IS FATAL — 24 of 24 cells, at every width and every rate.** `sweep_s` reads
7.358 s on every one of them: the head sweeps for the WHOLE FLIGHT and never finds the target,
because on a receding LOS the ground given up going the wrong way is never recovered.

⚠ **THE COVERAGE KNOB IS COMPLETELY INERT HERE** — S = 5, 10, 20, 30 give BIT-IDENTICAL results in
every one of the 24 cells. It is the slice-19 dead-knob class, in the instrument: at ρ = 8 the target
is caught before the first reversal, and at ρ < 8 the reversal cannot help because the target is gone.
**On this wire a search has exactly one design question and it is not the one §0.2 predicted.**

## ⚠⚠ §II.1 THE COMPLEMENTARITY CLAIM OF §I.1 IS **REFUTED FOR A SEARCH** (P2b, the control)

§I.1 read the cue and the coast as complements. That reading is **correct for a CUE and false for a
SEARCH**, and the control says so bit-exactly — the same arms flown with the honest memory coast ON
and OFF:

| wire | err ° | arm | coast **OFF** | coast **ON** |
|---|---|---|---|---|
| receding | −12 | d+1 S20 ρ8 | **0.007** | **0.007** — identical |
| receding | −14 | d+1 S20 ρ8 | **0.240** | **0.240** — identical |
| static | −12/−14, +12/+14 | every arm, ρ 2/4/8 | rescues | **bit-identical** |

⇒ **once a SEARCH is running, the memory coast is worth exactly zero on both geometries.** The 3.6 km
the coast was worth in §I.1 was a patch for the CUE's own failure mode, not a property of acquisition.
The prediction is left standing above and refuted here, per this file's opening rule.

## ⭐⭐⭐ §II.2 WHY A BLIND SEARCH BEATS A PERFECT CUE — **THE APPROACH, NOT THE INFORMATION**

The two arrive at the target differently, and that is the whole mechanism:

* **A CUE is a servo command ONTO the target.** As the head closes, the error shrinks, the commanded
  rate shrinks with it, and the head **decelerates onto the rim of its own window** — `off@lock`
  9.997–9.999° against a 10.0° window on every cued arm (§I.1). One tick of relative motion then puts
  the target back outside, and the shipped slew gate cannot be re-entered ⇒ `hold_max` = 0.001 s.
* **A SEARCH is a constant-rate sweep.** It does not know the target is there, so it does not slow
  down: it **overshoots THROUGH** the target and deposits it well inside the window ⇒ `hold_max`
  10.2–10.6 s, `in%` 90–97, with no coast anywhere.

> **THE RESULT, IN ONE SENTENCE. A blind search outperforms a perfect cue — not because it knows more,
> but because of HOW it arrives: knowing where the target is makes a servo stop ON it, and stopping on
> it means stopping at the edge of the window. The information was never the binding constraint. The
> approach was.**

## ⚠⚠ §II.3 THE INSTRUMENT CHECK THAT NEARLY SHIPPED A BUG AS A CLAIM (P4)

The first form of the probe wrote the head angle DIRECTLY, bypassing `gimbal_tau_s` and the rate cap —
so the headline above rested on an unfair servo. Re-flown with the sweep as a COMMAND the shipped
servo chases through `head_slew_full`:

| wire | err ° | ρ | `:direct` | `:servo` |
|---|---|---|---|---|
| receding | −12 | 8 | 0.007 (lock 0.475) | **0.064** (lock 0.574) |
| receding | −14 | 8 | 0.240 (lock 1.000) | **0.010** (lock 1.110) |
| static | −12 | 4 | 0.036 (lock 0.535) | **0.061** (lock 0.588) |
| static | −14 | 8 | 0.030 (lock 0.517) | **0.045** (lock 0.568) |

⇒ **every verdict agrees; the servo costs ≈0.05 s of acquisition time and nothing else.** The
advantage is not an instrument artifact.

⚠⚠ **AND THE FIRST RUN OF THIS CHECK WAS WRONG IN A WAY THAT READ EXACTLY LIKE PHYSICS.** It rebuilt
the sweep command from the head's OWN position each tick, making the commanded step one tick wide, so
a τ = 0.05 servo closed dt/τ of it and the sweep crawled at **1/50** the authored rate — and the table
came back with `:servo` rescuing NOTHING on any wire, which reads precisely like *"a real servo cannot
fly a search."* **The command must be its own integrator.** Recorded because the wrong version was
plausible, self-consistent, and one commit from being written down as a finding.

---

# §III — PROBE **P3**: THE REVERSED CROSSING, WHERE THE TARGET DOES NOT RUN AWAY

Slice 36's own shipped control geometry (`vy = −200`, the body-frame LOS nearly static — a 2.2° swing
against the shipped wire's 33.2°). This is F2's named candidate and it answers F2's blocker.

## §III.1 F2's BLOCKER — **ANSWERED: THE FAILING SET IS TWO-SIDED HERE**

| err ° | −18 … −11 | −10 | −8 … +10 | +11 | +12 … +18 |
|---|---|---|---|---|---|
| verdict | **never locks**, 305.112 | locks, 305.112 | 0.224 (hit) | 0.124 | locks LATE (t ≈ 4.8 s), 423–483 |

The head is born BELOW the LOS on the left arm and ABOVE it on the right, and both arms fail. ⇒ **a
single authored sweep direction cannot serve both**, which is what makes a blind, reversing search a
real design here rather than a rigged one. (The wire's attractors are ≈0.22 m and ≈305–483 m, so §0.3's
verdict language holds with room to spare.)

## ⭐⭐ §III.2 **F1's SURVIVAL CRITERION IS MET — BOTH AXES ARE LIVE, WITH OPPOSITE VERDICTS**

Wrong-guess arms (d = −1 at err = −14 / −12, d = +1 at err = +12), coast off; controls 305.112 / 423.494:

| cell | ρ 2 | ρ 4 | ρ 8 |
|---|---|---|---|
| err −14, d−1, **S = 5** | MISS 305.112 | MISS 305.112 | **0.315** |
| err −14, d−1, **S = 20** | MISS 305.112 | MISS 305.112 | **0.100** |
| err −14, d−1, **S = 30** | MISS 305.112 | MISS 305.112 | **MISS 305.112** |
| err −12, d−1, **S = 5** | MISS 305.112 | **0.349** | **0.109** |
| err −12, d−1, **S = 10** | MISS 305.112 | MISS 305.112 | **0.194** |
| err +12, d+1, **S = 20** | **0.286** | **MISS 405.638** | **0.141** |

> **SAME COVERAGE, DIFFERENT RATE, OPPOSITE VERDICTS** — S = 5 at err = −12: ρ = 2 misses, ρ = 4
> rescues. **SAME RATE, DIFFERENT COVERAGE, OPPOSITE VERDICTS** — ρ = 8 at err = −14: S = 20 rescues
> (0.100 m), S = 30 misses (305.112 m). **F1 PASSES on both axes**, on a wire whose CONTROL genuinely
> misses, which is the degeneracy check slice 41 §IV.8b failed.

⭐ **AND THE S = 20 → S = 30 FLIP IS THE MECHANISM IN ONE CELL:** a search that sweeps too WIDE the
wrong way spends its budget looking where the target is not, and arrives too late. Coverage is not
free — it is bought with the only currency a search has.

⚠ **ρ IS NOT MONOTONE ON THE WRONG-GUESS ARMS** (err +12, d+1: rescue at ρ 2, MISS at ρ 4, rescue at
ρ 8), and `docs/DEFERRALS.md` disqualifies knobs on exactly that (`k` 28, `ω_n` 40, σ_seek 25). Here it
is a real coincidence — whether the sweep happens to be pointing the right way when the LOS crosses it
— **but it is a hazard for any slider built on ρ and it is written down before a scenario exists.**

## §III.3 THE CONTRAST THAT MAKES THE PAIR

| | receding LOS (`vy = +200`) | static LOS (`vy = −200`) |
|---|---|---|
| wrong guess | **fatal — 24/24 cells lost** | **survivable** — rescued at 8 of 12 cells |
| coverage S | **DEAD** (bit-identical over 5→30°) | **LIVE**, and non-monotone (S 20 rescues, S 30 does not) |
| rate ρ | one bracket: ≥ the LOS rate or nothing | **LIVE** across 2 / 4 / 8 |
| contamination | `sat%` 29–75, `aero%` up to 31 | `sat%` 9–21, `aero%` ≤ 4.8 — **clean** |

> **THE SECOND SENTENCE. A search pattern is a race against the target's own motion. Against a line of
> sight that is running away, the only thing that matters is whether you guessed the direction — width
> and rate buy nothing and a wrong guess is unrecoverable. Against one that stays put, a wrong guess is
> survivable, and only THEN does a search have a design: sweep fast enough, but not so WIDE that the
> budget goes on looking where the target isn't.**

---

# §IV — GATE 0 STANDING (2026-08-18): **ALIVE**, and what it must answer next

* **F0** fired by the letter and its interpretation did not survive its own measurement (§I.3): what it
  priced was a STANDING delay, and a search does not stand still. Superseded by §II/§III, which measure
  the search directly. **The F0 number is kept, its verdict is withdrawn, and both are visible.**
* **F2** — ANSWERED (§III.1). A two-sided failing set exists on the reversed crossing, so a sign-blind
  reversing search is testable rather than rigged.
* **F1** — **PASSES** (§III.2), on both axes, with a control that misses.

⚠ **WHAT IS NOT YET ANSWERED, AND MUST BE BEFORE A KERNEL:**
1. **Which wire ships, and can one scenario carry this?** The lesson is a PAIR (receding vs static) and
   convention 9 says one lesson per scenario — slice 36's own answer was two files differing by one
   number, and that precedent fits exactly.
2. **Is the search a reparameterization of a WIDER WINDOW on the static wire specifically?** §III.2
   answers it structurally (a window has no rate and no direction) but the window ladder has not been
   re-flown on THIS geometry with the search off, and it must be, cell for cell.
3. **The ρ non-monotonicity (§III.2)** — a slider hazard, not yet a disqualification, and it decides
   whether ρ or S is the live knob.
4. **The −18 cells and every arm above `sat%` ≈ 50 are NOT quotable** — they are statements about the
   rate limit and the α ceiling. The shipping domain must be drawn inside the clean region.

---

# ⚠⚠ §V — THE FIXED-INSTRUMENT RE-MEASUREMENT (P5–P7): WHAT SURVIVES §II/§III AND WHAT DOES NOT

Three checks were run before any kernel. **Two of them refuted claims made above, and one of them
refuted the instrument the claims were measured with.** The refutations are recorded here and the
original claims are left standing where they were written, per this file's opening rule.

## ⚠⚠⚠ §V.0 THE INSTRUMENT BUG THAT INVALIDATES EVERY **+SIDE** ROW OF §III

§II/§III's grids were flown with the FIRST form of the search, which stepped the **head angle** itself
(`head_az + d·ρ·dt`) rather than an independent COMMAND. **Where the gimbal STOP binds, the head stops
advancing, so the step stops advancing, so the REVERSAL NEVER TRIGGERS** — the search silently parks on
the stop for the whole flight. The static wire's `err ≥ +12` cells are born ON the 30° stop (slice 36's
own domain note: `+11.9` births the head on the stop), so **every +side row of §III is instrument, not
physics, and is withdrawn.**

⚠ **WHAT SAYS THE −SIDE TRANSFERS** (rather than being assumed to): the −side never touches the stop,
and the fixed instrument reproduces §III's −side cells **to the digit** — `err −14, d−1, ρ8, S20` =
0.100 m and `err −12, d−1, ρ8, S20` = 0.129 m, both unchanged. That agreement is the licence to keep
the −side and only the −side.

⚠ **AND THIS IS THE SECOND INSTRUMENT BUG IN THIS GATE** (§II.3 was the first, the 1/50-rate crawl).
Both were plausible, self-consistent, and produced tables that read exactly like physics. **A search
probe has to be checked where the CLAMPS bind — the stop and the rate limit — because that is where a
kinematic shortcut stops being equivalent to the thing it stands in for.**

## ⚠⚠ §V.1 §II.2's HEADLINE IS **REFUTED**: THE CUE AND THE SEARCH ARRIVE THE SAME WAY

The discriminating test — the same oracle cue in two approach shapes, same target, same trajectory,
one variable (`:servo` = `err/τ` capped, which decelerates; `:const` = pure constant rate, no τ):

| wire | err ° | arm | miss m | `off@lock` ° | `hold_max` s | `in%` |
|---|---|---|---|---|---|---|
| receding | −12 | cue `:servo` | 0.110 | **9.991** | **10.580** | 95.6 |
| receding | −12 | cue `:const` | 0.110 | **9.991** | **10.580** | 95.6 |
| receding | −12 | **SEARCH** | 0.007 | **9.991** | **10.581** | 95.6 |
| static | −14 | cue `:servo` / `:const` | 0.001 | 9.990 | 8.337 | 94.0 |
| static | −14 | **SEARCH** | 0.030 | 9.989 | 8.339 | 94.0 |

⇒ **all three acquire at the SAME rim and hold for the SAME duration.** There is no approach-shape
effect. **"A blind search beats a perfect cue" is withdrawn**, and so is §II.2's mechanism sentence.
The 0.007-vs-0.110 gap that suggested it is a 16× ratio **between two hits a tenth of a metre apart**,
which carries no mechanism (advisor's catch, and the reason the verdict column here is `hold_max`).

⚠ **AND §I.1's `a cue that stops at lock rescues nothing` (hold_max 0.001 s) IS AN ARTIFACT OF THE SAME
CLASS.** P0b opened the existing slew gate; P5 moved the head *before* the gate and let the normal slew
run too — **one extra servo step on the acquisition tick**, and that one step is the whole difference
between 3620.675 m and 0.110 m. Which leads to the finding that replaces it:

## ⭐⭐⭐ §V.2 WHAT IS ACTUALLY THERE: **THE ACQUISITION KNIFE-EDGE — A LOCK AT THE RIM IS WORTH NOTHING**

> ⚠⚠⚠ **REFUTED AT GATE 1 — SEE §VI.** The measurements below are correct; the SENTENCE on top of
> them is not. The `fov 12.00` cell misses by 305.112 m, which is the `fov 11.95` NEVER-LOCKS cell's
> miss to the digit — so the "worthless lock" is the NULL CASE RELABELLED. The dead band is
> `ω_LOS·dt`, ONE INTEGRATION STEP, and halving `dt` halves it (§VI.3).

The window walked in 0.05° steps across the bracket, static wire, no search, no cue, no coast:

| err ° | fov 11.95 | **fov 12.00** | **fov 12.05** | fov 12.10 … 25.0 |
|---|---|---|---|---|
| −12 | never locks, 305.112 | **locks — `off@lock` 12.0000, `hold_max` 0.001 s, MISS 305.112** | **0.224 m, `hold_max` 8.854 s, `in%` 100** | 0.224, flat to the digit |

| err ° | fov 13.95 | **fov 14.00** | **fov 14.05** | fov 14.10 … 25.0 |
|---|---|---|---|---|
| −14 | never locks, 305.112 | **locks — `off@lock` 14.0000, `hold_max` 0.001 s, MISS 305.112** | **0.224 m, `hold_max` 8.854 s, `in%` 100** | 0.224, flat to the digit |

> ⭐⭐ **WHEN THE WINDOW EXACTLY EQUALS THE BIRTH OFFSET, THE SEEKER LOCKS — AND THE LOCK IS WORTHLESS.**
> `off@lock` is the window, to four decimals; the lock survives ONE TICK; the arm misses by the full
> 305.112 m of a head that never locked at all. **Fifty millidegrees of extra window turns that same
> lock into 8.854 s of continuous track and a 0.224 m hit.** Both sides of the step are FLAT to the
> digit over their whole range, so the finding is threshold-free: it is a step, not a slope.

⭐ **THE MECHANISM IS THE SHIPPED SLEW GATE (`missile.jl:2086`), AND IT IS AN ARCHITECTURE PROPERTY:**
the head only slews when the target is ALREADY inside the window, so **the gate can be entered but
never re-entered.** A lock with no margin is one tick of relative motion from being lost for the rest
of the flight — which is slice 37's *"a break is not an episode, it is the rest of the flight"*, now
located at the moment of BIRTH rather than at a break.

⇒ **ACQUISITION NEEDS MARGIN, NOT COVERAGE** — and margin is exactly what slice 33 built
`seeker_fov_margin` to talk about, on a wire where nothing was ever acquired at the rim.

## §V.3 THE WINDOW LADDER ON THE GEOMETRY THAT WOULD SHIP — the reader's first question, answered

Slice 37 §0.2's 12.5 / 15 / 20° are from the RECEDING wire and do not transfer. On the static wire,
with no search at all: **err −12 needs 12.05°, err −14 needs 14.05°, err +12 needs 11°, err +14 needs
12°** ⇒ **a single 15° window rescues all four showcase cells.**

⚠⚠ **SO THE SLICE'S ORIGINAL VALUE PROPOSITION (§0.2, *"buy coverage with time instead of with
glass"*) IS NOT DEMONSTRABLE ON THIS MODEL, AND THAT MUST BE SAID PLAINLY: in this simulator a wider
window is FREE.** A search buys the same rescue behind a 10° window at a cost in TIME (`t_lock` 0.15–
6.5 s against instant) — the exchange rate is now measured — but nothing in the model charges for the
window, so the trade cannot be *motivated* from inside it. That is a named approximation of the
detector, not a finding, and any slice built here must carry it as one.

## ⭐⭐ §V.4 WHAT DOES SURVIVE, AND IT IS A CLEAN TWO-PARAMETER LAW — **THE WRONG-GUESS FRONTIER**

Full (dir × S × ρ) grid re-flown on the fixed instrument, static wire, coast OFF. The table is the
MINIMUM sweep rate ρ_min (°/s) that rescues, against coverage S (°):

| err ° | dir | S 5 | S 10 | S 15 | S 20 | S 25 | S 30 |
|---|---|---|---|---|---|---|---|
| −12 | **+1 (right)** | 2 | 2 | 2 | 2 | 2 | 2 |
| −14 | **+1 (right)** | 2 | 2 | 2 | 2 | 2 | 2 |
| +12 | **−1 (right)** | 1 | 1 | 1 | 1 | 1 | 1 |
| +14 | **−1 (right)** | 1 | 1 | 1 | 1 | 1 | 1 |
| −12 | **−1 (WRONG)** | 4 | **5** | **7** | **8** | **10** | **11** |
| −14 | **−1 (WRONG)** | 6 | **5** | **7** | **8** | **10** | **11** |
| +12 | **+1 (WRONG)** | 4 | **8** | **10** | **14** | **none ≤ 16** | **none ≤ 16** |
| +14 | **+1 (WRONG)** | 4 | **8** | **10** | **14** | **none ≤ 16** | **none ≤ 16** |

> ⭐⭐ **GUESS RIGHT AND THE WIDTH IS FREE — ρ_min IS FLAT ACROSS A 6× RANGE OF COVERAGE, ON ALL FOUR
> ARMS. GUESS WRONG AND EVERY EXTRA DEGREE OF COVERAGE MUST BE PAID FOR IN SWEEP RATE**, monotonically,
> on all four wrong-guess arms — and past S ≈ 20° on the +side there is no rate that buys it back.

⇒ **F1's survival criterion is met on the FIXED instrument and not only on the broken one:** the rescue
set is a genuine 2-D surface in (S, ρ) whose shape depends on a third binary variable (the guess), and
a window has neither a rate nor a direction. **The `S = 20 → S = 30` flip quoted in §III.2 survives**
(ρ8: S20 rescues 0.100 m, S30 does not) — it is one cell of this frontier.

⚠ **AND THE ρ NON-MONOTONICITY OF §III.2 IS WITHDRAWN WITH THE +SIDE ROWS THAT PRODUCED IT.** On the
fixed instrument the fine grid (1 → 16 °/s, 1 °/s steps) is a clean **BRACKET on every arm** — rescue
above ρ_min, miss below, no comb. **ρ is NOT disqualified**, which is what slice 40's `ω_n` was.
⚠ One wrinkle kept rather than smoothed: `err −14, d−1` reads ρ_min = 6 at S = 5 and 5 at S = 10, a
single non-monotone step at the smallest coverage. It is one cell and it is quoted, not averaged away.

⚠ **CONTAMINATION on the surviving grid: `sat%` 6–19, `aero%` 0.0 on every quoted cell but one
(4.8 %).** Clean — unlike the receding wire (`sat%` 29–75, `aero%` to 31), which is the second reason
the static wire is the one that would ship.

## §V.5 GATE 0 STANDING AFTER THE RE-MEASUREMENT

> ⚠⚠ **SUPERSEDED BY §VI.** Finding 1 (the knife-edge) is DEAD. Finding 2 (the wrong-guess frontier)
> and finding 3 (the two-sided failing set) stand.

**The slice is ALIVE but its headline is not the one §II proposed.** What is measured and survives:

1. ⭐ **The acquisition knife-edge** (§V.2) — a lock exactly at the rim is worth exactly nothing, and
   0.05° of margin is worth 305 m. Threshold-free, flat on both sides, and it explains this whole
   family. **This is the strongest result in the gate and it is not about searching at all.**
2. ⭐ **The wrong-guess frontier** (§V.4) — coverage is free when the guess is right and must be bought
   with rate when it is wrong. A clean 2-D law with a binary third variable.
3. The two-sided failing set on the static wire (§III.1) — unaffected by the instrument bug, since it
   involves no search.

**WITHDRAWN:** §II.2's *"a blind search beats a perfect cue"*; §I.1's *"a cue that stops at lock
rescues nothing"*; every +side row of §III; §III.2's ρ non-monotonicity.

⚠ **THE OPEN QUESTION IS NOW A SCOPING ONE, AND IT IS THE HONEST ONE:** finding 1 is an *acquisition
margin* lesson and finding 2 is a *search pattern* lesson, and **convention 9 says they are two
slices, not one.** Finding 1 is cheaper, sharper, threshold-free, and it is a property of code that
already ships; finding 2 needs a new subsystem and lands on a model where the alternative (a wider
window) is free. That choice is not made in this file yet.

## ⭐⭐ §V.6 THE SCOPING CALL — **MADE HERE, NOT LEFT OPEN** (2026-08-18)

> ⚠⚠⚠ **VOID — SEE §VI.4.** This call picked the knife-edge over the frontier because the knife-edge
> was "threshold-free" and "the strongest result in the gate". It was NEITHER. The frontier was the
> stronger of the two all along — and the deferral written below is unaffected and still correct.

§V.5 left the choice between the two findings open. It is answered now, so that a future session
inherits a decision rather than re-deriving one:

> **SLICE 42 IS THE ACQUISITION-MARGIN LESSON (§V.2). THE SEARCH-PATTERN FRONTIER (§V.4) BECOMES ITS
> NAMED DEFERRAL.**

The reasons, in the order that decided it:

1. **The knife-edge is threshold-free and contamination-free.** It is a STEP — flat to the digit on
   both sides over the whole ladder — not a slope with a line drawn on it. Slice 37's §II.0 had to
   quote a sensitivity because its onset rested on a bracket the author chose; this one does not.
2. **It needs no new subsystem and no new knob.** The mechanism is `missile.jl:2086`, code that has
   shipped since slice 34: the slew gate can be ENTERED but never RE-ENTERED. Slice 33 already built
   the vocabulary for the fix (`seeker_fov_margin`) on a wire where nothing was ever acquired at the
   rim, so the lesson lands on existing structure rather than beside it.
3. **The search half lands on a free alternative** (§V.3): a single 15° window rescues every showcase
   cell on the geometry that would ship, and nothing in this model charges for the window. A slice
   whose lesson is *"buy coverage with time"* cannot be motivated from inside a model where the thing
   it is buying instead of is free.

⚠ **AND THE DEFERRAL IS NAMED WITH ITS OWN PRECONDITION, so it is not re-attempted blind:**

> **A SEARCH PATTERN / THE WRONG-GUESS FRONTIER** — the (S, ρ) law of §V.4 is real, monotone, and
> passes the reparameterization gate on the fixed instrument. ⚠ **It must NOT be planned until the
> DETECTOR WINDOW COSTS SOMETHING** (sensitivity, resolution, or acquisition range — the `SEEKER RANGE
> / SNR ACQUISITION LIMITS` deferral is the natural carrier). Until then a wider window dominates it
> for free and the slice has a law but no design question. ⚠ And whoever takes it inherits two
> instrument hazards measured here: a sweep command rebuilt from the head's own position crawls at
> 1/50 rate, and a sweep that steps the HEAD rather than a COMMAND never reverses once the gimbal stop
> binds — **check a search probe where the CLAMPS bind.**

## ⚠⚠ §V.7 WHAT SLICE 42 STILL HAS TO PROVE — the knife-edge is a PROBE result, not a shipped one

Stated explicitly so §V.2 is never quoted as more than it is:

**The knife-edge was measured on an AUTHORED `fov` ladder inside a probe.** It shows that a lock with
zero margin is worth nothing and that 0.05° is worth 305 m — on a wire whose window was walked by hand.
**It has NOT yet been shown to move a verdict on an unmodified shipping scenario**, and no kernel, comp
key, rung or scenario exists for it. That is gate-1 work and it is the first thing gate 1 must do:
find the shipping wire where the margin is the binding term, and show the step there without authoring
the window to sit on it. ⚠ If the step only exists when the window is placed on the birth offset by
hand, the finding is a curiosity about a measure-zero coincidence and the slice dies at gate 1 — that
is the falsifier to pre-register before writing any code.

---

# ⚠⚠⚠ §VI — GATE 1 (2026-08-18): **THE PRE-REGISTERED FALSIFIER FIRES. SLICE 42 IS DEAD.**

§V.7 pre-registered the kill in writing: *"if the step only exists when the window is placed on the
birth offset by hand, the finding is a curiosity about a measure-zero coincidence and the slice dies
at gate 1."* **It does — and it is worse than measure-zero in the loose sense: the dead band is
EXACTLY ONE INTEGRATION STEP WIDE, and halving `dt` halves it.**

## ⚠⚠ §VI.0 THE TELL WAS ALREADY IN §V.2's OWN TABLE, AND IT WAS NOT READ

Before any new measurement, the advisor's catch, which needs no probe at all:

| `fov` | verdict |
|---|---|
| 11.95 | never locks — **305.112 m** |
| **12.00** | locks, `off@lock` 12.0000, hold 1 tick — **305.112 m** |
| 12.05 | 0.224 m |

⇒ **THE "WORTHLESS LOCK" CELL'S MISS IS BYTE-IDENTICAL TO THE NEVER-LOCKED CELL'S.** A lock that
changes no number in the verdict column is not a lock that is *worth nothing* — it is the **null case
wearing a different label**. And `off@lock` reading `12.0000` to four decimals is not a measurement:
the gate fires on `off ≤ fov` and the head sits at the rim BY CONSTRUCTION, so that column is the
authored threshold echoed back. ⭐ **RULE: WHEN A "STEP" CELL'S VERDICT NUMBER EQUALS THE DO-NOTHING
CELL'S, CHECK IT AGAINST THE NULL BEFORE CALLING IT A STEP.**

## §VI.1 PROBE **P8** — THE RACE SWEEP: WALK THE BIRTH OFFSET, NOT THE WINDOW

The right instrument for the one surviving hypothesis (*the required margin is set by the race
between the LOS rate and the servo rate*). Shipped `slice36_handover` geometry to the digit, shipped
10° window, servo at **both ends of the shipped slider** (8 and 60 °/s), `err_az` walked ±10° in 1°
steps. `M:\claud_projects\temp\slice42\p8_race.jl`. Coarse first, on purpose — a fine sweep run
before a gap is visible only resolves an artifact more precisely.

| err ° | miss m @ 8 °/s | `hold_max` s | miss m @ 60 °/s | `hold_max` s |
|---|---|---|---|---|
| **−10** | **3620.675** | **0.001** | **3620.675** | **0.001** |
| −9 … −4 | 0.191 | 10.929 | 0.191 | 10.929 |
| −3 | 3125.932 | 0.924 | 0.191 | 10.929 |
| 0 | 3290.078 | 0.433 | 0.191 | 10.929 |
| +9 | 3548.614 | 0.043 | 0.191 | 10.929 |
| **+10** | 3398.255 | 0.016 | **0.206** | **10.928** |

⭐ **THREE THINGS, AND THE FIRST TWO KILL THE RACE HYPOTHESIS OUTRIGHT:**

1. **A 7.5× SERVO BUYS NOTHING AT THE RIM.** `err −10` misses by **3620.675 m at both 8 and 60 °/s —
   the same digits** — and holds for exactly one tick on both. If the rim failure were a race, the
   ceiling servo would win it. The trajectory is identical because the head never moves: the gate
   opens for one tick on a command still equal to the head's own angle, and shuts before the servo
   has anything to chase.
2. **THE SAME |err| ON THE OTHER SIGN DOES NOT DIE.** `err +10` at 60 °/s HOLDS (0.206 m, `off@lock`
   **9.9364**, at tick **2**) — there the LOS walks INTO the window and mints its own margin. A
   "finding" that needs exact equality *and* a particular direction of LOS travel is a coincidence,
   not a mechanism.
3. At 60 °/s the failing set over the whole 21-cell sweep is **exactly one cell: {−10}**.

⚠ **INSTRUMENT-HONESTY CHECK, AND IT PASSES:** at 8 °/s this probe returns `err 0 → 3290.078 m` and
`err −6 → 0.191 m`, which are `slice36_handover`'s and `slice36_biased`'s SHIPPED numbers to the
digit (both files' headers quote them). The holding basket `err ∈ [−9, −4]` is slice 36's own basket.
**The instrument reproduces the shipping wire exactly — unlike §II/§III, this kill is not an
instrument failure.**

## ⚠⚠ §VI.2 PROBE **P9** — THE BAND IS ONE CELL WIDE AT §V.2's OWN RESOLUTION

`p9_rim.jl`, the rim walked in **0.05° steps** — the SAME step §V.2's ladder used, so the two tables
are directly comparable:

| err ° | miss @ 8 °/s | miss @ 60 °/s |
|---|---|---|
| **−10.000** | **3620.675** | **3620.675** |
| −9.950 … −9.500 | 0.191, flat | 0.191, flat |
| +9.500 … +9.950 (sign control) | — | 0.191, flat |

> ⇒ **FIFTY MILLIDEGREES INSIDE THE RIM THE TRACK HOLDS COMPLETELY, AT BOTH ENDS OF THE SHIPPED
> SLIDER.** The dead band at §V.2's own resolution is the **bit-equality cell and nothing else**.

## ⭐⭐⭐ §VI.3 PROBE **P10** — THE BAND'S WIDTH IS `ω_LOS · dt`. IT IS THE INTEGRATION STEP.

`p10_dt.jl`. Same wire, same window, same servo; only the step changes. The LOS body-azimuth rate at
birth is measured on each step (~3.63 °/s, essentially step-invariant) and `ω·dt` is the prediction
written down BEFORE the run:

| `dt` s | ω_LOS °/s | **ω·dt** ° | last **DYING** err ° | first **HOLDING** err ° | `hold_max` |
|---|---|---|---|---|---|
| 2e−3 | +3.6300 | **0.00726** | −9.9940 | −9.9900 | 0.0020 s |
| 1e−3 | +3.6290 | **0.00363** | −9.9980 | −9.9960 | 0.0010 s |
| 5e−4 | +3.6285 | **0.00181** | −9.9990 | −9.9980 | 0.0005 s |

> ⭐⭐⭐ **THE BAND HALVES WHEN THE STEP HALVES, AND `ω·dt` FALLS INSIDE ITS MEASURED BRACKET AT ALL
> THREE STEPS.** `hold_max` is EXACTLY ONE TICK on every row. The "acquisition margin" is the distance
> the line of sight travels between two evaluations of a once-per-tick gate — **a discretization
> artifact, not a property of a seeker.** At the shipped `dt = 1e-3` it is 0.0036° against a 10°
> window: **0.036 %.**

⭐ **AND THAT IS THE STRONGEST FORM THIS KILL COULD TAKE.** A magnitude argument (*"the band is
small"*) invites the reply *"small on this wire"*. A scaling argument does not: **a finding whose SIZE
is set by the integrator's step cannot be a lesson about hardware.** ⇒ the new discipline, carried to
`docs/LESSONS.md`: **before shipping a narrow threshold effect, RE-FLY IT AT HALF `dt` — if it halves,
it IS the step.**

## §VI.4 WHAT §V.2 SHOULD HAVE SAID

Not deleted — annotated, per this file's opening rule. §V.2's measurements are all correct. Its
*sentence* is not:

* **Written:** *"When the window exactly equals the birth offset, the seeker locks — and the lock is
  worthless. Acquisition needs margin, not coverage."*
* **True:** *"The slew gate is inclusive (`off ≤ fov`), so at bit-exact equality it mints a lock that
  survives exactly one tick and moves no verdict number. Any margin at all — down to one tick of LOS
  motion, 0.0036° here — is fully sufficient, at every servo rate on the shipped slider."*

⚠ **AND §V.6's SCOPING CALL IS THEREBY VOID.** It chose the acquisition-margin lesson over the
search-pattern frontier because the knife-edge was *"threshold-free and contamination-free"* and *"the
strongest result in the gate."* It was neither — it was the null case. **The frontier (§V.4) was the
stronger of the two all along**, and it stays deferred for the reason §V.6 gave it, which §VI does not
touch: in this model a wider window is free.

## §VI.5 WHAT SLICE 42 LEAVES BEHIND

**No code shipped. The suite stays at 7693.** Nothing under `core/` was touched in this gate — the
probes author the birth offset by pre-seeding `:head_az`, which is exactly how the shipped
`gimbal_handover_err_deg` is consumed, so every number above is the shipping mechanism.

**SURVIVING, AND CARRIED TO `docs/DEFERRALS.md`:**
1. ⭐ **THE WRONG-GUESS FRONTIER (§V.4)** — untouched by §VI (it involves no rim and no equality).
   Deferred with its precondition intact: **not until the detector window COSTS something.**
2. The two-sided failing set on the static wire (§III.1).

**DEAD, AND ON THE KILL LIST:**
* **The acquisition knife-edge / "a lock at the rim is worth nothing"** — the null case relabelled;
  band width = `ω_LOS·dt`.
* **"the required margin is set by the servo-vs-LOS race"** — refuted by P8: 8 °/s and 60 °/s return
  the same digits at the rim.

**THE THREE METHOD LESSONS (all to `docs/LESSONS.md`):**
1. **Check the step against the NULL.** A cell whose verdict equals the do-nothing cell's verdict IS
   the do-nothing cell.
2. **A reported quantity that equals an authored threshold to full precision is the threshold, not a
   measurement.** `off@lock == fov` to four decimals was the gate echoing its own constant.
3. **RE-FLY A NARROW THRESHOLD EFFECT AT HALF `dt`.** If it halves, it is the step.

⚠ **AND THE PATTERN THIS ARC HAS NOW REPEATED FOUR TIMES** (39, 41, the search half of 42, and now
its acquisition half): **the probe was right, the table was right, and the SENTENCE on top of the
table was wrong.** All four were caught by a criterion written down BEFORE the measurement existed.
Pre-registration is the only thing that has ever killed a slice in this project on time.
