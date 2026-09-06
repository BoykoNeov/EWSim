# Slice 54 — **THE GIVE-UP RULE**: how long should a radar keep looking before it lets go?

**STATUS: GATE 0 PRE-REGISTRATION, 2026-09-06. NO PROBE HAS RUN. NO CORE CHANGE IS AUTHORISED BY
THIS DOCUMENT.** Everything below the falsifier list was written as a PREDICTION before any probe
(slice 41's discipline — `docs/LESSONS.md:13`). It is to be left unedited so the predictions can be
scored; §2 at the foot records what was MEASURED, including where the predictions were wrong. Probes
and their write-ups live in `M:\claud_projects\temp\slice54\`.

The candidate, in `M:\claud_projects\EW\docs\DEFERRALS.md` §"New candidates raised by slice 53":

> **⭐⭐ A TRACKER WHOSE GIVE-UP RULE IS THE SLIDER.** §2.14 Arm 2 measured that `revisit_s` and `N`\*
> move the metres by **+2191 m at `G` = 20** on identical physics — the same size as the tail lobe's
> own effect — and slice 53 had to hold them fixed and ship them beside every number for exactly
> that reason. That is a lesson in its own right (*how long should a radar keep looking before it
> gives up?*) and the hardware to run it is already shipped (`track_run_step`, `_track_look!`,
> `track_drop_looks`). ⚠⚠ **It is TWO-SIDED and that is the whole interest**: a patient tracker
> follows a fading target further home, and also holds a track on nothing. The gate-0 question is
> what prices the second half — this arc has no false-track model, so a slider that is
> monotone-better upward is slice 48's shape and not a new lesson. ⇒ **needs a cost for patience
> before it can be proposed**, and the honest candidate is a false-alarm track, which is new physics
> rather than a new scenario.

## ⭐⭐⭐ THE CANDIDATE'S OWN BLOCKER IS **STALE**, AND THAT IS THIS PLAN'S FIRST FINDING

**"This arc has no false-track model" is FALSE as written.** `_observe_cfar!` (`core/src/radar.jl`,
slice 3) already draws a noise-and-clutter range-power profile every look and thresholds it, and it
already pushes **one `:detection` event per detected cell carrying `:cell` and `:range`** — with
`:of` present ONLY when that cell holds a real target (`radar.jl` §4 of `_observe_cfar!`). A
threshold crossing in a noise or clutter cell **is** a false alarm, it **has a range**, and its rate
is authorable two ways that already ship (`pfa`, and a `clutter` entity's `cnr_db`/`extent_m`).

⇒ **The physics is not missing. A TRACKER THAT CAN CONSUME IT is.** The shipped give-up tracker
(`_track_look!`) is wired into the POINT detector only, takes `any_detect` over the strongest target,
and is handed the TRUE target's range — it can neither see a false alarm nor be fooled by one. The
loader refuses the key on a `:cfar` wire for exactly that reason, in a comment that names the defect
it is preventing (`core/src/scenario.jl` `_validate_cfar`):

> ⚠ SLICE 53 gate 2 — THE TRACKER IS WIRED IN THE POINT PATH ONLY. […] a `:cfar` scenario would
> carry an authored `track_drop_looks` that NOTHING READS — the `speed` (19) / handover-bias (36)
> dead-knob shape […] Refused at LOAD.

**This slice's core change, if gate 0 lives, is to LIFT THAT REFUSAL WITH A REASON**: a give-up
tracker over the CFAR picture, gated in RANGE rather than by target identity. That is new WIRING and
a new gauge, not new physics — which is a materially cheaper slice than the ledger entry assumes,
and the ledger must be corrected either way, pass or fail.

⚠ The DEFERRALS entry is not otherwise wrong: the two-sidedness still has to be MEASURED, and it is
what §2 exists to answer.

---

## §0 THE MODEL TEST — SPLIT, BECAUSE HALF OF IT ALREADY PASSES BY INSPECTION

The 2026-08-18 two-test rule (`docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT") asks two questions.
Here the MODEL half splits cleanly in two, and only the second part is at risk:

1. **`track_drop_looks` as a read-every-look parameter — PASSES BY INSPECTION, ALREADY SHIPPED.**
   `_track_look!` reads it from `radar.comp` on every look and passes it to `track_run_step`, whose
   semantics are pinned in `core/test/test_track.jl`. It is a COUNT OF LOOKS, correct in its own
   units, and the loader already refuses `< 1` and refuses it without a positive `revisit_s`. There
   is no question to answer here and gate 0 must not spend a probe on it.
2. **The CFAR-side tracker — DOES NOT EXIST, and is what a core change would build.** Two pieces:
   a RANGE GATE (which detected cells count as "this track's detection") and the handling of a
   detection whose range is NOT the target's. Neither is written. §1 states what it would be.

⇒ Unlike slice 53, this slice is **not** proposing a new physical kernel. Under the two-test rule the
worst outcome available to it is therefore unusually well defined: if the LESSON fails, what ships is
the wiring plus its tests plus the lifted loader refusal — the "dead as a lesson, alive as a model"
shape, with the ledger's stale blocker corrected as the standing result.

---

## §1 WHAT A CORE CHANGE WOULD BE (stated so gate 0 can be scored against it, NOT authorised)

- **A range-gated give-up tracker on the CFAR path.** `_track_look!` gains a sibling (or a branch)
  that is handed the look's DETECTED CELLS and their ranges instead of a single boolean, and decides
  `detected` for the track by asking *is any detected cell within the gate of where I expect the
  track to be?* `track_run_step` itself is untouched — it is pure and already correct.
- **The track carries its own range**, updated from the ACCEPTED cell, not from truth. ⚠⚠ This is
  the whole point: today `_track_look!` is handed `_range(best_pos, radar.pos)` — the true strongest
  target's range — so a track held on nothing would stamp the REAL target's range and be silently
  right. A track that can be WRONG about where it is, is the thing being built.
- **Lifting `_validate_cfar`'s refusal**, replacing it with whatever narrower guard the new wiring
  actually needs.
- **No new RNG.** The tracker reads `detections` AFTER `_draw_profile!` and draws nothing —
  `_track_look!`'s existing posture (`radar.jl`, "It reads `any_detect` AFTER the draw and draws
  nothing itself — convention 3's draw topology is untouched").

⚠ **NAMED APPROXIMATIONS THIS WOULD SHIP WITH** (§1 trifecta discipline): one track per radar (the
family's posture); the gate is a fixed range window, not a Kalman-style covariance gate; a track
accepts the NEAREST admissible cell rather than the strongest; and the leg/CPA latch inherited from
`_track_look!` still assumes ONE closest approach.

---

## §2 THE FALSIFIERS — PRE-REGISTERED, TO BE ANSWERED BEFORE ANY CORE EDIT

**F1 — TWO-SIDEDNESS. Is the curve two-sided at all?** Sweep `track_drop_looks` on a fly-past wire
with clutter and read the gauge. ⚠ **KILL IF** the gauge is monotone in patience across the whole
domain on every clutter arm: that is slice 48's shape (monotone-better upward), a knob with a right
answer at its endpoint is not a design lesson, and the honest verdict is DEAD AS A LESSON.

**F2 — ⭐⭐⭐ THE DISCRIMINATOR. Does the OPTIMUM MOVE?** Build the full (patience × `cnr_db`) table
over **at least three** clutter levels and locate the best patience cell on each arm. ⚠⚠ **KILL IF**
the optimum sits at the same `track_drop_looks` on every arm. This is slice 52's separation restated
in a new currency — *the right coverage is not a constant, it is set by the handover picture error*
becomes *the right patience is not a constant, it is set by how dirty the picture is* — and without
it this slice has a constant, not a lesson. **Two arms is not a trend; three or more.**

**F3 — THE GAUGE MUST BE ABLE TO BE WRONG, NOT MERELY LONG.** `docs/LESSONS.md:851`: *when a model
touches only the detection and not the dynamics, every at-event gauge is the event time in other
units.* A false-alarm model touches only the detection, so "seconds of false track" ≈ patience ×
false-alarm rate — the slider in other units, and that is this slice's most likely death. ⚠ **The
gauge must therefore be a POSITION ERROR, not a DURATION**: the track's range against the target's
truth range. A long track is not a failure; a track in the wrong place is. **KILL IF** the only
separating gauge found is a duration.

**F4 — THE GATE WIDTH IS A CONFOUND AND MUST BE FIXED BY A RULE.** A gate wide enough to admit noise
cells makes patience expensive at every clutter level; a narrow one makes it free. It may NOT be a
second live slider (convention 9) and it may NOT be tuned per arm — tuning it per arm tunes the
answer. ⚠ **Fix it before flying by a stated rule** (candidate: the cells spanned by one revisit of
closing motion, `|ṙ|·revisit_s / Δr`, rounded up) and quote it beside every number, exactly as slice
53 quotes `revisit_s` and `N`\*.

**F5 — THE MOVER MAY NOT BE A SECOND SLIDER.** `cnr_db` is what SETS the right patience, so it is the
ANSWER to the slice's question and cannot also be an input to it — the ledger's own ruling on
`midcourse_err_gain` (`docs/DEFERRALS.md` §"New candidates raised by slice 52"), convention 9. It is
AUTHORED per arm and quoted in the ladder. ⚠ **KILL the slice's headline** if the effect can only be
shown with two live knobs.

**F6 — DRAW TOPOLOGY AND BYTE-IDENTITY.** `_draw_profile!` is the ONLY RNG of a CFAR look and draws
`2·N_p·N_cells` regardless of rung or geometry. ⚠ **The draw count must be provably invariant to
`track_drop_looks`**, and the shipped wire that must stay byte-identical is named individually:
**`scenarios/slice3_cfar.yaml`** (the only `:cfar` scenario in the tree), plus every point-path wire,
which is untouched by construction. `docs/LESSONS.md:932` — a byte-identity claim names its wires.

**F7 — THE SLIDER IS STEPPED, AND FLAT STRETCHES ARE GUARANTEED.** `set_param` coerces to
`Int(round(v))` (`core/src/server.jl` `_coerce_like`) because the key is stored as an `Int`, so a
domain of 1–8 is ~8 discrete positions. That is not a defect, but it means the readout MUST carry a
disambiguator so a flat stretch reads as *the edge has not moved* rather than *nothing is being read*
— slice 53 shipped the loss LOOK INDEX for exactly this and it is needed here from the start.

**F8 — THE SEED RULE IS DECLARED BEFORE THE FLIGHTS AND THE LOSERS ARE PUBLISHED.**
`docs/LESSONS.md:1314`; slice 53's obvious name-matching seed lost. The rule is to be written into
§2 BEFORE the ladder is flown, and every seed tried is to be reported, winners and losers.

---

## §3 THE WIRE (proposed, to be settled by gate 0)

⚠ **`scenarios/slice3_cfar.yaml` IS NOT THE WIRE and must not be retrofitted.** Its targets are
STATIC at fixed range with `revisit_s` 0.05 and two targets five cells apart — there is no fading
end for a give-up rule to be measured at, and the second target is slice 3's masking lesson.

The candidate wire is **slice 53's fly-past under the CFAR detector**: one radar, one target, straight
and level, plus a `clutter` entity whose `cnr_db` is the AUTHORED mover. The pass has a real end (the
target fades out at long range) and a real beginning, so patience has something to be patient about.

⚠ Gate 0 must check that a fly-past is compatible with the CFAR cell grid at all: `Δr = c/2B` is
149.9 m at 1 MHz, and `n_cells`/`range_start_m` must span the pass. If the target leaves the grid the
detector stops seeing it for a reason that is not fading, which would be a different lesson.

---

## §4 PREDICTIONS, TO BE SCORED (written before any probe)

1. **F1 lives.** Patience will help on the clean-noise arm and hurt on the heavy-clutter arm.
2. **F2 lives, but weakly.** The optimum will move by only one or two cells across the clutter
   ladder, because the slider is stepped and its useful domain is small. ⚠ This is the prediction
   most likely to kill the slice.
3. **F3 is the real risk.** The first gauge tried will probably be a duration and will have to be
   replaced by a range error.
4. **The gate width (F4) will turn out to matter more than the clutter level**, and keeping it fixed
   by rule will be the hardest part of an honest ladder.

---

## §2 — WHAT WAS MEASURED

Probes live in `M:\claud_projects\temp\slice54\`. No core change has been made.

### §2.1 P1 — a fly-past under the CFAR detector RUNS, and false alarms are plentiful

`M:\claud_projects\temp\slice54\p1_feasibility.jl`. Slice 53's fly-past geometry (radar at
`[0,0,30]`, target `[-15000,0,5000]` at 300 m/s) under `cfar: ca`, σ = 4 m², `pfa` 1e-3, 340 cells
of Δr = 149.9 m (grid to 51 km), 200 s = 2000 looks, seed 54.

| `cnr_db` | target hit % | false alarms / look | looks with ≥1 FA |
|---|---|---|---|
| 0 | 90.2 | 0.365 | 29.4 % |
| 10 | 80.8 | 0.503 | 38.5 % |
| 20 | 60.5 | 0.589 | 43.5 % |

⭐ **Both things the slice needs exist on this wire**: threshold crossings in cells that are not the
target's fire at ~1e-3 per cell per look (the design `pfa`, as it should), and the target is on the
grid for the whole pass (0 off-grid looks).

⚠⚠ **BUT THE PASS HAS NO END.** Hit rate vs range at σ = 4 was 100 % / 100 % / 100 % / 95 % / 93 % /
84 % / 73 % / **77 % / 65 % / 67 %** over 0–50 km in 5 km bands — it does not decay, it wanders. A
give-up rule needs a fade to be measured at, and at 4 m² there isn't one inside 50 km. **P1's
geometry is therefore NOT the wire**, and this is the first prediction §4 got wrong (it assumed the
fade came for free).

⭐ **What P1 did find is a second mechanism worth naming**: the clutter band (12–32 km slant) does
not merely raise the false-alarm rate, it **masks** — at `cnr_db` = 20 the hit rate inside the band
collapses to 1–5 % and recovers to 77 % beyond it. That is a HOLE in the middle of a pass, not a
fade at the end, and it is a different (also interesting) lesson. It is not the one being probed
here; see §3's note on convention 9.

### §2.2 P2 — the fade is real but FURTHER OUT, and `cnr_db` is the WRONG mover

`M:\claud_projects\temp\slice54\p2_fade.jl`.

**P2a — where the target fades** (no clutter, `pfa` 1e-3, grid to 150 km, 450 s), hit rate %:

| σ (m²) | 0–20k | 20–40k | 40–60k | 60–80k | 80–100k | 100–120k |
|---|---|---|---|---|---|---|
| 4.00 | 99.7 | 84.6 | 41.4 | 8.7 | 1.2 | 0.4 |
| 1.00 | 98.5 | 60.6 | 10.9 | 0.6 | 0.0 | 0.0 |
| 0.25 | 93.2 | 25.7 | 1.2 | 0.0 | 0.0 | 0.0 |

⇒ **σ = 1 m² puts the fade inside a 300 s pass** (98 % → 61 % → 11 % → 0.6 %), which is the wire P3
and P4 use. σ = 4 needs 450 s and σ = 0.25 fades before the track is ever established.

**P2b — ⭐⭐⭐ WHICH AUTHORED KNOB IS THE "DIRTY PICTURE" MOVER**, σ = 4, 340 cells, 200 s:

| arm | target hit % | FA / look | FA / cell / look |
|---|---|---|---|
| `pfa` 1e-4, no clutter | 88.0 | 0.034 | 1.00e-04 |
| `pfa` 1e-3, no clutter | 91.8 | 0.349 | 1.03e-03 |
| `pfa` 1e-2, no clutter | 94.8 | 3.346 | 9.84e-03 |
| `pfa` 1e-3, clutter 30–50 km `cnr` 10 | 75.7 | 0.503 | 1.48e-03 |
| `pfa` 1e-3, clutter 30–50 km `cnr` 20 | 71.1 | 0.567 | 1.67e-03 |
| `pfa` 1e-3, clutter 30–50 km `cnr` 30 | 70.8 | 0.579 | 1.70e-03 |

⭐⭐⭐ **`cnr_db` IS NOT THE MOVER THE PLAN ASSUMED, AND THE REASON IS THE DETECTOR ITSELF.** A
CA-CFAR threshold is estimated from the training cells *beside* the cell under test, so a broad
clutter band raises the threshold with it: 10 → 30 dB of clutter moves the false-alarm density by
**1.48 → 1.70 e-3 (+15 %)** while it destroys 5 points of target detection. **Clutter under CFAR is a
MASKER, not a false-alarm source** — only its EDGES spike. ⚠ This retires §3's proposed mover and
§4's prediction 4 with it.

⭐⭐⭐ **`pfa` IS THE MOVER**: 1e-4 → 1e-2 moves the false-alarm density by a factor **98** (1.00e-4 →
9.84e-3 per cell per look) while moving the target's own detection by 7 points. It is authored, not a
slider on this wire (F5 satisfied), and it is the physically honest statement of *how dirty a picture
are you willing to accept* — which is the same design question the give-up rule asks, put to the
detector instead of to the tracker.

### §2.3 P3 — the curve IS two-sided (F1 LIVES), on one seed

`M:\claud_projects\temp\slice54\p3_table.jl`. The offline range-gated give-up tracker (§1's proposed
model, run offline over the CFAR picture: α-β range filter α = 0.5 / β = 0.1, **gate fixed at ±2
range cells on every arm** per F4, dead track re-opens on the strongest detected cell), σ = 1 m²,
534 cells to 80 km, 300 s = 3000 looks, seed 54. Gauge is **NET = looks tracking the TARGET (within
one cell of truth) − looks tracking SOMETHING ELSE** — scored on POSITION, never on duration (F3).

| `pfa` | NET at n_drop 1 | peak NET | at n_drop | NET at 16 |
|---|---|---|---|---|
| 1e-5 | 1389 | **1651** | 5 | 1575 |
| 1e-4 | 1397 | **1539** | 3 | 1310 |
| 1e-3 | 1199 | 1246 | 12 | 1093 |
| 1e-2 | 1018 | 1430 | 11 | 1361 |

⭐ **F1 LIVES on the clean arms.** At `pfa` 1e-5 the gauge rises 1389 → 1651 and falls back to 1575;
at 1e-4 it rises 1397 → 1539 and falls to 1310. **An interior optimum exists** — patience is bought
and then paid for, which is exactly the two-sidedness the DEFERRALS entry demanded and the thing a
false-alarm-free wire cannot show.

⚠⚠ **F2 IS NOT YET ANSWERED, AND THE TWO DIRTY ARMS ARE CHATTER, NOT A CURVE.** The optimum reads
5 → 3 → 12 → 11, which is not a trend; the 1e-3 column alone runs 1199, 1200, 1168, 1129, 1201, 1144,
1103, 1184, 1117, 1159, 1238, 1246, 1014, 971, 1154, 1093 — **an argmax over a bouncing column is not
a measurement** (the slice-53 discipline of scoring a ladder, applied to a single seed). The clean
arms' movement 5 → 3 is in the right DIRECTION (a dirtier picture buys less patience) but one seed
cannot separate it from noise. **P4 re-flies the ladder over six declared seeds to answer F2.**

### §2.4 P4 — ⭐⭐⭐ THE OPTIMUM MOVES. **F2 LIVES**, over six declared seeds

`M:\claud_projects\temp\slice54\p4_seeds.jl`; raw output `M:\claud_projects\temp\slice54\p4_out.txt`.
Same tracker, same wire, same gauge as P3. **⚠ THE SEED RULE WAS DECLARED IN THE PROBE BEFORE ANY
FLIGHT** (`docs/LESSONS.md:1314`): the six consecutive integers **101…106**, chosen for being
arbitrary and contiguous, no seed selected on its result. **All six are reported; none was dropped.**
The headline is the MEAN curve; the per-seed argmax spread is printed beside it as the noise floor
the arm-to-arm movement has to clear.

| `pfa` | best `n_drop` (mean curve) | per-seed argmax | mean NET at 1 | at the peak | at 16 |
|---|---|---|---|---|---|
| 1e-6 | 16 (**plateau from ~7**) | 7, 10, 15, 9, 16, 13 | 1321 | 1637 | 1637 |
| 1e-5 | **7** | 7, 9, 8, 7, 16, 6 | 1379 | 1678 | 1631 |
| 1e-4 | **4** | **3, 4, 3, 4, 4, 4** | 1395 | 1567 | 1372 |
| 1e-3 | 2 (**curve flat**) | 2, 9, 14, 4, 14, 16 | 1176 | 1181 | 1175 |

⭐⭐⭐ **THE OPTIMUM MOVES 16 → 7 → 4 → 2 AS THE PICTURE DIRTIES, MONOTONICALLY, ACROSS FOUR ARMS.**
That is slice 52's separation in a new currency and it is the whole slice: *the right patience is
not a constant — it is set by how dirty your picture is.* ⚠ The movement clears the seed noise by a
wide margin where it is best determined: the `pfa` = 1e-4 arm's per-seed argmax spans **3…4**, i.e.
six seeds agree to within one cell, against a 16 → 4 movement.

⭐⭐ **AND THE TWO END ARMS ARE NOT FAILURES — THEY ARE THE TWO LIMITS OF THE LESSON**, and each is a
sentence worth teaching:

* **`pfa` = 1e-6 — PATIENCE IS FREE.** The curve rises to ~1616 by `n_drop` = 6 and is then FLAT to
  16 (1615…1637, inside its own sd of 25–64). With almost nothing crossing the threshold there is
  nothing to be seduced by, so holding on costs nothing. ⚠⚠ **The argmax of 16 is a PLATEAU
  ARTEFACT and must not be quoted as "the best patience is 16"** — the honest reading is *≥ 6, and
  the curve cannot tell you more*. The per-seed spread (7…16) says the same thing.
* **`pfa` = 1e-3 — PATIENCE BUYS NOTHING.** NET is 1176 at `n_drop` = 1, 1181 at 2 and 1175 at 16 —
  the whole column is flat inside its own scatter, and the per-seed argmax (2, 9, 14, 4, 14, 16) is
  pure chatter. The gauge is not broken; **the answer is that at this false-alarm density a track
  that is coasting is more likely to be captured than to be right**, so the floor is the best you can
  do. ⚠ Do not quote "2" as a measured optimum.

⇒ **THE WELL-DETERMINED INTERIOR OF THE LADDER IS `pfa` 1e-5 → 1e-4, WHERE THE OPTIMUM IS 7 → 4**,
and that is where a showcase must live. §4's prediction 2 ("the optimum will move by only one or two
cells… this is the prediction most likely to kill the slice") is **WRONG, and in the slice's favour**:
it moves by a factor of about four across the ladder, and by 7 → 4 across the two arms where both
ends are tightly determined.

⭐ §4's prediction 3 (F3, "the first gauge tried will probably be a duration and will have to be
replaced by a range error") is **also wrong** — the position-scored NET was the first gauge tried and
it separates. F3 is satisfied by construction: `bad` counts looks where a track is ALIVE AND IN THE
WRONG PLACE, which no duration can express.

### §2.5 P5 — F4 AND `dt`. ⚠⚠ **THE GATE THE PROBES FLEW IS NOT THE GATE F4 DECLARED**

`M:\claud_projects\temp\slice54\p5_robust.jl`; raw output `M:\claud_projects\temp\slice54\p5_out.txt`.
Same six declared seeds 101…106, same flights as P4 (the gate sweep RE-USES each flight — the CFAR
picture does not depend on the tracker — so it costs no extra flights).

#### §2.5.1 ⚠⚠ THE DISCREPANCY, AND THE RULING

**F4 pre-registered the gate rule as `|ṙ|·revisit_s / Δr`, rounded up. That arithmetic yields ±1
cell. Every probe P3–P6 flew ±2.**

    |ṙ|·revisit_s / Δr  =  300 m/s · 0.1 s / 149.90 m  =  0.2001 cells  →  ceil = 1

⇒ **THE RULE STANDS AND THE PROBES ARE RE-READ AT ±1.** Shipping ±2 while citing a rule that
computes ±1 is the failure the previous commit is named after (*"the claim the verifier and its own
docs disagreed about"*). The rule was declared before the flights precisely so it could not be
chosen after them, and it is not to be retro-fitted to the number that happened to be flown.

⭐ **AND THE DECLARED GATE IS THE BETTER MEASUREMENT ANYWAY** — which is a result, not a
convenience. At ±1 the ladder is **6 → 5 → 3 → 2**, monotone across ALL FOUR arms, with no plateau
artefact at the clean end: P4's `pfa` = 1e-6 argmax of 16 was a flat-top artefact whose honest
reading was *"≥ 6, and the curve cannot tell you more"*, and the declared gate reads exactly **6**.

#### §2.5.2 F4 — THE FULL SWEEP, INCLUDING THE CELL THAT LOSES

| `pfa` | ±1 best `n_drop` (spread) | ±2 (spread) | ±4 (spread) |
|---|---|---|---|
| 1e-6 | **6** (5–13) | 16 (7–16) | 16 (7–16) |
| 1e-5 | **5** (5–16) | 7 (6–16) | 8 (7–16) |
| 1e-4 | **3** (3–5) | 4 (3–4) | 4 (3–4) |
| 1e-3 | **2** (1–14) | 2 (2–16) | **16** (4–16) |

⚠⚠ **THE LOSING CELL IS PUBLISHED: gate ±4 at `pfa` = 1e-3 reads 16 against 2 at both other gates.**
Read literally that is a direction flip and F4's pre-registered kill says a ladder whose direction
flips with the gate is a property of the gate. **It does not kill the slice, and the reason must be
made rather than assumed**: that arm was ALREADY declared flat inside its own scatter by P4 before
this sweep was flown (NET 1176 / 1181 / 1175 at `n_drop` 1 / 2 / 16), and its per-seed spread here is
4–16 on six seeds — an argmax over a flat column, which §2.3 already ruled is not a measurement. The
flip is the same non-result reported twice, not a contradiction of a determined one.

⇒ **THE HEADLINE IS SCOPED TO THE INTERIOR AND MUST BE WORDED THAT WAY.** *"The ladder survives every
gate"* is FALSE. What is true: **`pfa` 1e-5 → 1e-4 moves the best patience at EVERY gate width
(5 → 3, 7 → 4, 8 → 4)**, and those are the two arms where both ends are determined.

#### §2.5.3 ⭐⭐⭐ THE GATE MOVES *WHERE THE ARGMAX SITS ON A FLAT TOP*, NOT HOW WELL YOU CAN DO

Peak NET at `pfa` = 1e-4 is **1537 / 1566 / 1566** across ±1 / ±2 / ±4 — a 1.9 % spread against a
gate width that quadrupled. The gate is therefore NOT a competing lesson (F4's real worry); it barely
touches the achievable score. What it moves is which cell of a nearly flat top wins the argmax.

⚠⚠ **⇒ THE SHOWCASE MUST QUOTE THE CURVE, NOT THE ARGMAX.** A gauge that reports "best = 4" is
reporting a coin-flip between neighbouring cells of a plateau; the teaching object is the SHAPE —
rises, peaks, falls — and the shipped readout has to show enough of it for the shape to be visible.
This is slice 53's *"the SIGN is physics, the SIZE is not"* one instrument over.

#### §2.5.4 `dt` — THE OPTIMUM IS INVARIANT TO HALVING THE PHYSICS STEP

| `pfa` | `dt` = 1e-3 | `dt` = 5e-4 |
|---|---|---|
| 1e-5 | 9 (7–9), peak NET 1677 | 9 (7–9), peak NET 1677 |
| 1e-4 | 4 (3–4), peak NET 1581 | 4 (3–4), peak NET 1581 |

Identical argmax, identical spread, identical peak NET — as predicted, because the rule is counted in
LOOKS and the look cadence (`revisit_s` = 0.1 s) is 100× the step. ⚠ This is a THREE-SEED
mean-curve argmax comparison and P4 measured the per-seed argmax spread as 6…16 on the 1e-5 arm, so
**a match at this resolution could be luck** — slices 42 and 51 both died on a threshold that moved
when `dt` halved, and neither would have been caught by a coincidence of two argmaxes. P6a re-asks
it PAIRED and structurally.

### §2.6 P6a — ⭐⭐⭐ `dt`-INVARIANCE IS **STRUCTURAL**, NOT AN ARGMAX COINCIDENCE

`M:\claud_projects\temp\slice54\p6_paired.jl`; raw output `M:\claud_projects\temp\slice54\p6_out.txt`.
`pfa` = 1e-4 (the arm P4 determined most tightly), six declared seeds, PAIRED per seed.

| seed | looks @ `dt` / `dt`/2 | detected cells @ `dt` / `dt`/2 | every look's cell SET identical? | argmax @ `dt` / `dt`/2 | max‖ΔNET‖ over `n_drop` 1…16 |
|---|---|---|---|---|---|
| 101 | 3000 / 3000 | 1663 / 1663 | **YES** | 3 / 3 | **0.0** |
| 102 | 3000 / 3000 | 1627 / 1627 | **YES** | 4 / 4 | **0.0** |
| 103 | 3000 / 3000 | 1639 / 1639 | **YES** | 3 / 3 | **0.0** |
| 104 | 3000 / 3000 | 1631 / 1631 | **YES** | 4 / 4 | **0.0** |
| 105 | 3000 / 3000 | 1616 / 1616 | **YES** | 4 / 4 | **0.0** |
| 106 | 3000 / 3000 | 1663 / 1663 | **YES** | 4 / 4 | **0.0** |

⭐⭐⭐ **THE PICTURE ITSELF IS IDENTICAL AT BOTH STEPS — SAME LOOK COUNT, SAME DETECTED-CELL SET ON
EVERY ONE OF 3000 LOOKS, ON ALL SIX SEEDS — SO THE WHOLE NET CURVE IS IDENTICAL TO 0.0, NOT MERELY
ITS ARGMAX.** This is the structural answer P5b could not give and it is qualitatively stronger than
one: P5b compared two argmaxes over three seeds, and P4 had measured the per-seed argmax spread as
6…16 on one arm, so a MATCH there could have been luck and a MISS could have been sampling.

⚠⚠ **AND IT IS A NON-OBVIOUS PASS, WHICH IS WHY IT HAD TO BE ASKED.** Slices 42 and 51 both died on a
threshold that moved when `dt` halved, and neither would have been caught by two argmaxes agreeing.
The reason it passes here is checkable and is a rule worth keeping: **every draw of a CFAR look is
made once per LOOK, and the look boundary is a `revisit_s` clock that lands on the same wall time
regardless of the step** — so halving `dt` inserts only extra non-look ticks, which draw nothing.
⇒ **A rule counted in LOOKS is `dt`-invariant when the look cadence is; the slice-53 hazard is a rule
counted in FRAMES.** The residual `dt`-sensitivity is the target's own position drift within a look
(≤ 0.2 cells here), which does not reach the cell quantisation.

### §2.7 P6b / P7 — THE GAUGE'S OWN FREE PARAMETER, AND THE ONE THAT MUST BE ASKED AT ±1

P6b swept the correctness band (what counts as "on the target": 1 vs 2 range cells) **at the
superseded ±2 gate**, and the four-arm ladder does NOT stay monotone at a 2-cell band:

| `pfa` | band 1 cell: best `n_drop` (spread) | band 2 cells: best `n_drop` (spread) |
|---|---|---|
| 1e-6 | 16 (7–16) | 11 (10–16) |
| 1e-5 | 7 (6–16) | 11 (9–12) |
| 1e-4 | 4 (3–4) | 5 (4–11) |
| 1e-3 | 2 (2–16) | **16** (4–16) |

⇒ ladder direction: **16 → 7 → 4 → 2** at one cell, **11 → 11 → 5 → 16** at two.

⭐ **P6's own pre-registered PREDICTION — that a more forgiving band should move the optimum RIGHT —
is CONFIRMED on both determined arms** (7 → 11 and 4 → 5): looks previously scored as *tracking
something else* become *tracking the target*, and a seduced track is exactly what makes patience
expensive, so forgiving it buys more patience. The mechanism is understood, not a surprise.

⚠⚠ **BUT THE FOUR-ARM LADDER IS NOT MONOTONE AT THE 2-CELL BAND, AND P6's HEADER PRE-REGISTERED THAT
AS A KILL.** Two things must happen before that can be ruled on, and the ruling may NOT be made from
this table:

1. **THE QUESTION IS AT THE WRONG GATE.** §2.5.1 ruled the shipped gate to ±1. P7
   (`M:\claud_projects\temp\slice54\p7_band.jl`) re-asks the band as a CROSS PRODUCT — gate {1,2} ×
   band {1,2} over ONE flight set per arm, so no cell can differ by sampling.
2. **⚠⚠ THE EXCLUSION OF THE TWO END ARMS IS NOW BEING INVOKED FOR THE SECOND TIME AND THAT MUST BE
   CHECKABLE, NOT CONVENIENT.** Both non-monotone entries above are end arms: `pfa` = 1e-3 (16, per-
   seed spread 4–16) and `pfa` = 1e-6 (11, spread 10–16). The defence is that **§2.4 declared both
   arms non-measurements BEFORE P5, P6 or P7 were flown** — 1e-6 as a PLATEAU whose honest reading is
   *"≥ 6, the curve cannot tell you more"*, 1e-3 as FLAT INSIDE ITS OWN SCATTER (NET 1176/1181/1175 at
   `n_drop` 1/2/16) — so it is a pre-registered exclusion and not a post-hoc rescue. ⚠ **If a third
   result has to be rescued the same way, the exclusion has become the finding and the slice should
   be re-scoped to the two arms it can actually measure**, rather than claiming a four-arm ladder.

### §2.8 P7 — ⭐⭐⭐ **THE OPTIMUM MOVES IN EVERY CELL OF THE CROSS PRODUCT. F2 LIVES, AND NO END ARM HAD TO BE EXCLUDED TO SAY SO**

`M:\claud_projects\temp\slice54\p7_band.jl`; raw output `M:\claud_projects\temp\slice54\p7_out.txt`.
Gate {±1, ±2} × correctness band {1, 2 cells}, six declared seeds, **ONE flight set per arm scored
four ways** — so no cell can differ from another by sampling.

| `pfa` | gate ±1 band 1 (**SHIPPED**) | gate ±1 band 2 | gate ±2 band 1 | gate ±2 band 2 |
|---|---|---|---|---|
| 1e-6 | **6** (5–13) | 9 (9–11) | 16 (7–16) | 11 (10–16) |
| 1e-5 | **5** (5–16) | 9 (9–16) | 7 (6–16) | 11 (9–12) |
| 1e-4 | **3** (3–5) | 5 (3–11) | 4 (3–4) | 5 (4–11) |
| 1e-3 | **2** (1–14) | 9 (3–14) | 2 (2–16) | 16 (4–16) |

**THE DETERMINED INTERIOR, `pfa` 1e-5 → 1e-4, IN ALL FOUR CELLS:**

| gate | band | interior movement |
|---|---|---|
| ±1 | 1 cell | **5 → 3** |
| ±1 | 2 cells | **9 → 5** |
| ±2 | 1 cell | **7 → 4** |
| ±2 | 2 cells | **11 → 5** |

⭐⭐⭐ **THE OPTIMUM MOVES DOWN IN EVERY CELL, BY A FACTOR OF 1.7–2.2, UNDER EVERY COMBINATION OF THE
TWO FREE PARAMETERS.** F2 is answered and the answer is robust: *a dirtier picture buys less
patience* is a property of the physics, not of the tracker's gate or of the gauge's band.

⭐⭐ **AND §2.7's STOPPING RULE WAS NOT TRIGGERED — NOTHING HAD TO BE RESCUED.** The shipped cell
(gate ±1, band 1) is monotone across ALL FOUR arms **6 → 5 → 3 → 2 with no arm excluded at all**;
the end-arm exclusion is needed only to read the band-2 robustness cells, which are checks and not
the shipped configuration. The claim therefore rests on a direct measurement, not on a defence.

#### §2.8.1 ⭐⭐⭐ THE SHIPPED CELL'S CURVE IS TWO-SIDED ON EVERY ARM — AND ITS **FALL** IS THE LESSON

Mean NET over six seeds, gate ±1, band 1 cell, `n_drop` = 1…16:

| `pfa` | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | … | 16 | peak → 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1e-6 | 1305 | 1454 | 1532 | 1566 | 1573 | **1580** | 1576 | 1547 | … | 1493 | −5.5 % |
| 1e-5 | 1362 | 1520 | 1594 | 1626 | **1637** | 1619 | 1624 | 1620 | … | 1501 | −8.3 % |
| 1e-4 | 1377 | 1498 | **1537** | 1537 | 1521 | 1492 | 1462 | 1433 | … | 1264 | −17.8 % |
| 1e-3 | 1153 | **1161** | 1143 | 1100 | 1082 | 1043 | 1065 | 1009 | … | 1030 | −11.3 % |

⭐⭐⭐ **EVERY ARM RISES AND THEN FALLS — F1 IS ANSWERED ON ALL FOUR, NOT JUST THE CLEAN ONES** (P3
could only show it on two), **and the PEAK MARCHES LEFT while the PENALTY FOR OVERSHOOTING IT GROWS**:
holding on to 16 costs 5.5 % of the score on the cleanest picture and 17.8 % on the `pfa` = 1e-4 one.
⇒ *Patience is nearly free when there is nothing to be seduced by, and it gets expensive exactly as
fast as the picture gets dirty.* **That is the slice, in one table.**

#### §2.8.2 ⚠⚠ THE NUMBER OF LOOKS IS A **JOINT PROPERTY** OF THE TRACKER'S GATE AND THE GAUGE'S BAND

The interior optimum reads 5, 9, 7 or 11 at `pfa` = 1e-5 depending purely on two constants that are
NOT physics — the gate width and what counts as "on the target". The band alone moves it 5 → 9.

⇒ **THE DIRECTION IS PHYSICS; THE COUNT IS NOT. Quote the gate and the band beside every `n_drop`
or it is not a measurement.** This is slice 53's *"the METRES are a joint property of the lobe and the
tracker — quote `revisit_s` and `N`\* or it is not a measurement"* restated one instrument over, and
it lands on this slice for the same structural reason: the gauge is read through a tracker whose own
constants set the scale. ⭐ It also re-confirms §2.5.3 — **the showcase must ship the CURVE, whose
shape is invariant, not the ARGMAX, which is not.**

---

## §3 — GATE 0 VERDICT (2026-09-06): ⭐⭐⭐ **LIVE. PROCEED TO GATE 1.**

| falsifier | verdict | where |
|---|---|---|
| **F1** two-sidedness | ✅ **LIVES** — every arm rises then falls, on the shipped cell | §2.8.1 |
| **F2** the optimum MOVES | ✅ **LIVES** — 6 → 5 → 3 → 2 with no arm excluded; interior moves in all 4 robustness cells | §2.8 |
| **F3** gauge can be WRONG, not merely long | ✅ **SATISFIED BY CONSTRUCTION** — NET is scored on POSITION (`bad` = alive AND in the wrong place) | §2.3, §2.4 |
| **F4** gate width fixed by a stated rule | ✅ **RULED ±1** = the pre-registered `\|ṙ\|·revisit_s/Δr`; the ladder is *better* there; losing cell published | §2.5 |
| **F5** the mover may not be a second slider | ✅ **SATISFIED** — the mover is `pfa`, AUTHORED per arm; `cnr_db` was retired as a mover by measurement | §2.2 |
| **F6** draw topology / byte-identity | ⏳ **GATE 2's JOB** — the tracker reads `detections` AFTER the draw and draws nothing; to be PROVEN, incl. the ABSOLUTE golden | §1 |
| **F7** stepped slider needs a disambiguator | ⏳ **GATE 3's JOB** — carried forward | — |
| **F8** seed rule declared before the flights | ✅ **HONOURED** — 101…106 declared in the probe; all six reported, none dropped | §2.4 |
| *(unregistered)* **`dt`-invariance** | ✅ **STRUCTURAL** — picture bit-identical at `dt`/2, `max‖ΔNET‖ = 0.0` | §2.6 |

**PREDICTIONS SCORED** (§4, written before any probe): **1 RIGHT** (F1 lives). **2 WRONG, in the
slice's favour** (the optimum moves by a factor ~2, not "one or two cells"). **3 WRONG** (the
position-scored gauge was the FIRST tried and separated; no duration was ever needed). **4 WRONG
TWICE OVER** — the gate width does NOT matter more than the dirtiness (peak NET moves 1.9 % across a
4× gate, §2.5.3), and `cnr_db` was not the dirtiness mover at all (§2.2). ⚠ Two further §-level
assumptions were also wrong: §3's proposed wire had NO FADE (§2.1) and §3's proposed mover was
retired by the detector's own physics (§2.2).

**WHAT SHIPS, PER §0:** the CFAR-side range-gated give-up tracker + its tests + the lifted
`_validate_cfar` refusal, and — pass or fail on the headline — the correction of the DEFERRALS
entry's stale *"this arc has no false-track model"* blocker (see the plan's first finding).

### §3.1 THE SPECIFICATION, CORRECTED — ⚠ **§1 IS AMBIGUOUS AND P7's TRACKER IS THE SPEC**

§1 is left unedited (it is pre-registration). It is corrected here, because gate 1 must build the
tracker that produced §2.8's table and not the one §1 loosely describes.

1. ⚠⚠ **§1 says a track "accepts the NEAREST admissible cell". THAT IS ONLY THE *ALIVE* RULE.**
   The probes use TWO association rules and both are load-bearing:
   * **alive** → the **NEAREST** detected cell whose range is within the gate of the prediction;
   * **dead → re-open** on the **STRONGEST** detected cell in the whole profile, **ungated**
     (`findmax(u.pow)`, p7_band.jl:105).

   The re-open rule is what sets **how fast a track is seduced after a drop**, which is the exact
   mechanism the lesson prices — a dead track grabs the loudest thing in the picture, and on a dirty
   picture that is often not the target. Porting only the "nearest" rule would build a tracker that
   does not reproduce §2.8's curve. **Both ship; both are named approximations.**
2. ⚠ **§1's "the leg/CPA latch inherited from `_track_look!`" is NOT honoured — it is dropped.**
   Slice 53's gain/loss edges and one-CPA latch are ITS gauge and they assume a TRUTH range this
   tracker is deliberately no longer handed. The CFAR tracker is therefore a **SIBLING** of
   `_track_look!` sharing only the pure `track_run_step`, not a branch of it.
3. ⭐⭐ **THE GATE AND THE FILTER ARE BOTH EXPRESSED IN `revisit_s`, WHICH NO LOADER FIXES** — so a
   wire with a different revisit silently gets a different tracker unless the gate is COMPUTED from
   the wire. §2.8.2 is what makes this load-bearing. ⇒ the gate is `ceil(|ṙ|·revisit_s/Δr)` evaluated
   per look from the TRACK's OWN estimated range rate (never truth), floored at 1 cell; α and β are
   named module constants pinned by a test that fails if they are edited. ⚠ On this wire
   |ṙ| ≤ 300 m/s ⇒ the rule yields **1 cell everywhere**, reproducing the probes exactly.
