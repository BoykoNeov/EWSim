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
