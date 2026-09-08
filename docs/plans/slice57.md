# Slice 57 — A FIXED APERTURE, A TWO-AXIS UNCERTAINTY, AND THE BAND WHERE A DESIGN EXISTS

**Status: PLAN ONLY — gate 0 has not run.** Nothing below is a measurement. Every number quoted from
an earlier slice carries its cite; every number this slice will produce is written as a PREDICTION
with a falsifier attached, per slice 53's rule (*declare the selection rule before the flights and
publish the losers*) and slice 54's (*a pre-registered rule earns authority the first time it
REFUSES something*).

---

## §0 PROVENANCE — THIS IS THE ONE THING SLICE 55 NAMED AND COULD NOT SHIP

`docs/PROHIBITIONS.md` §2, on the fan-beam window: *"✅ SHIPPED by 55, at HELD APERTURE. ⚠ NOT
discharged: the aspect-ratio CURVE (its turning point is measured but ONE ARM DEEP), the ELLIPSE, and
the STOP half."* This slice takes the first of those three.

Slice 55 shipped a **RIVAL**: three windows of identical solid angle `Ω = θ_az·θ_el = 100 deg²`, of
which the tall one is bit-identical to the disc over 9600 ticks and the wide one locks. Its own
pre-registered falsifier **F2 FIRED** — on the shipped geometry widening is monotone-better all the
way out to `(150°, 0.667°)`, every arm returning the identical 4.9360 s / 0.09 m / 20.0 %, because
`max|Δel|` on a locking arm is **0.0565°** and the elevation half-width never binds
(`docs/plans/slice55.md` §II.6). P5b discharged it only by giving the target a vertical rate: at
`vz` = 220 m/s the unswept-axis error reaches **1.4086°** and the single arm below it —
`(150°, 0.667°)` — locks 1.61 s later and misses by 745.73 m against 587.77.

⚠⚠ **ONE ARM IS NOT A DOMAIN, AND SLICE 55 SAID SO IN WRITING:** *"the reversal is ONE ARM DEEP on
this geometry, and that is not yet a showcase curve… That authoring is gate 3's first job, and it is
the one thing gate 0 has NOT discharged."* This slice is that authoring, promoted to its own wire.

## §0.0 NOVELTY AGAINST SLICE 52 — STATED FIRST, AS 55 STATED ITS PROVENANCE AGAINST 45

The nearest shipped lesson is **52**: *SIZE THE SWEEP TO THE UNCERTAINTY ⇒ a faster sweep needs a
WIDER one.* The distinction, and it must survive gate 0 or this slice is 52 in different clothes:

| | slice 52 | slice 57 (proposed) |
|---|---|---|
| what is sized | the SEARCH SWEEP's angular coverage | the DETECTOR WINDOW's two half-widths |
| axes | ONE (body azimuth — `search_sweep` is single-axis, `core/src/frames.jl:1085`) | TWO, and they are COUPLED |
| the budget | none — coverage is free, it costs only TIME | **`Ω` is fixed**, so every degree of azimuth is paid for in elevation at the going rate |
| the shape of the answer | *more coverage, up to the deficit* | *a BAND, with a wall at each end and a different failure at each wall* |

⭐ **The new object is the TRADE, not the sizing.** 52 asks how much you need; 57 asks where you spend
a budget you cannot enlarge. ⚠ If gate 0 finds that the elevation wall never binds on any authorable
geometry, this collapses into 52 and dies there.

---

## §0.1 THE PRE-REGISTERED RULES — FIXED BEFORE ANY PROBE IS WRITTEN

### §0.1.1 ⭐⭐⭐ THE TRIGGER IS A **BRANCH**, DECLARED IN ADVANCE — NOT CHOSEN AFTER THE PROBES

Slice 55's F2 already rules on this and the ruling binds here: *"if the metric is monotone-better all
the way to the floor of the slider's domain, the box is a free lunch, the trigger is not `CURVE`, and
the slice ships as a NULL with its bound instead of as a lesson."* And `docs/LESSONS.md`:880 carries
the older, harder objection — `k` (28), `ω_n` (40), `σ_seek` (25) and 20/22's miss were **all
disqualified for failing RESOLUTION over their own domain.** A flat interior IS that defect.

⚠⚠ **So the trigger is not asserted here. It is a rule with two arms, and P3 decides which fires:**

> **R1 — THE INTERIOR RESOLVES.** If `search_t_lock_s` varies across the feasible band with a
> measurable interior optimum separated from both walls by ≥ 3 arms and by more than the
> `dt`-halving noise floor, the trigger is **`CURVE`** and the headline is the turning point.
>
> **R1′ — THE INTERIOR IS FLAT.** If arms inside the band are bit-identical (which is slice 55's
> shipped result with ONE loaded axis), the trigger is **`REGIME`**, the headline is **the two WALLS
> and the law that locates them**, and the flat interior ships as a **NULL with its bound** —
> *inside the band the shape is free, and here is how wide the band is.* ⚠ Under R1′ the plan must
> name `docs/LESSONS.md`:880 in the scenario header and say why the EDGES carry a lesson the
> INTERIOR does not: a wall is a failure with a stated cause, and resolution is a property a gauge
> needs in order to RANK arms — not in order to LOCATE a boundary.

⭐⭐ **BOTH ARMS ARE SHIPPABLE. Filing the wrong one is not.** Under neither arm may the slice be
sold as *"narrower is better"* or *"wider is better"* — that is `gimbal_fov_deg`'s disqualification
(48) and slice 46's ban on *a wider window is free*, and it would be earned here too.

### §0.1.2 THE CONTROL — THE VARYING-RADIUS DISC, FLOWN AND PUBLISHED

Slice 55's ruling control was the **gain-matched disc `r = √(ab)`** — the only one with a consumer
(`rf.jl`'s `aperture_gain`, `G = η·4π/Ω`). That control is inherited unchanged for every single-arm
comparison.

⚠⚠ **AND THIS SLICE ADDS A SECOND CONTROL THAT 55 DID NOT NEED: THE DISC WITH A VARYING RADIUS,
SWEPT OVER THE SAME NUMBER OF ARMS.** It will also produce a two-sided response — small `r` cannot
reach the pointing error, large `r` collapses the horizon (slice 46: `R_acq · fov` = constant). ⭐ It
is the **dull rival**, and it is what makes *held `Ω`* load-bearing rather than asserted:

* the disc sweep moves the gauge **because the REACH moves** — `R_acq` changes across its arms;
* the aspect sweep moves the gauge **with `R_acq` identical to nine digits** (`Ω` held by
  construction, §2.1).

⇒ **Two two-sided curves, one mechanism each, and the mechanisms are distinguishable on the wire.**
This is slice 56's SPECIFICITY toll paid in advance (`docs/PROHIBITIONS.md` §4: *drive the gauge's
mediating quantity to the same value with the dullest other knob available and re-measure*).

### §0.1.3 ⭐⭐⭐ THE CENTRAL PREDICTION — THE PRODUCT INEQUALITY

Let `A = max|Δaz|` and `E = max|Δel|` be the pointing errors the head is offered during the blind
phase, and let the window be the box `(a, b)` with `a·b = Ω` held. Write the aspect ratio `r = a/b`,
so `a = √(Ω·r)` and `b = √(Ω/r)`. The window covers the error iff `a ≥ A` **and** `b ≥ E`, i.e.

> **`A²/Ω ≤ r ≤ Ω/E²`  —  a band, non-empty iff  `A·E ≤ Ω`.**

⭐⭐⭐ **NOTHING IN THIS REPO STATES THIS AND IT IS THE SLICE.** It says three things at once: a fixed
aperture can cover a two-axis uncertainty **only if the PRODUCT of the two errors fits inside it**;
when it can, the shape is **not free but pinned inside a band**; and the two walls are at **different
places for different reasons** — the low wall is *not enough azimuth*, the high wall is *not enough
elevation*.

> **PRE-REGISTERED FALSIFIER F2 — THE INFEASIBLE GEOMETRY.** Two wires are authored: one with
> `A·E` just **below** `Ω` (a narrow band must exist) and one just **above** (**no arm may lock at
> any aspect ratio**). **If any arm locks on the infeasible wire, the inequality is wrong and that
> is worth more than the headline** — it would mean the two errors are not simultaneous, which is
> itself a finding and must be published as one.

⚠⚠ **AND THE INEQUALITY'S INPUTS ARE NOT INPUTS — SLICE 55's F3 RETRACTION APPLIES HERE VERBATIM.**
*"A WINDOW'S VERDICT IS A PROPERTY OF THE FLIGHT, NOT OF A CELL — a window that changes SHAPE changes
where the head goes, hence which geometry is ever offered to it."* So `A` and `E` are measured on a
**NULL arm** (an effectively unbounded window, where the head is never gated) and the law is tested by
asking whether those two numbers **predict the walls of the flown sweep**. They are a prediction,
never a substitute for flying the arms. ⚠ If they do not predict the walls, the physics is not wrong —
the *static reading of it* is, and that discrepancy is the honest finding.

### §0.1.4 THE OTHER FALSIFIERS

> **F1 — `dt`.** Both walls are threshold brackets. Slice 42's standing rule
> (`docs/PROHIBITIONS.md` §1): re-fly every narrow threshold at `dt` = 1e−3 **and** 5e−4. **If either
> wall moves by more than one arm when the step halves, that wall is `ω·dt` and the slice is DEAD.**

> **F3 — THE DULL RIVAL WINS.** If the varying-radius disc (§0.1.2) produces a band that is *wider*
> than the aspect sweep's, or reaches a *better* gauge value at its optimum, then spending the
> aperture differently is worth less than buying more of it and **the headline is 46's, not this
> slice's.**

> **F4 — THE LIVE KNOB IS NOT THE AUTHORED WIRE.** The aspect knob (§2.1) recomputes `(a, b)` every
> tick from a stored `Ω`. **Dragging it to the value an arm authors must reproduce that arm
> BIT-IDENTICALLY** (convention 2). If it does not, the knob is a second implementation of the
> window and it does not ship.

### §0.1.5 THE GAUGE — AND IT IS NOT THE MISS

`docs/PROHIBITIONS.md` §2, paid for by 44/45/46/47: **the gauge is never the miss.** Inherited from
48/55 unchanged:

* **`search_t_lock_s`** — seconds from receiver-open to lock, `−1.0` while no lock has happened.
* **lock / no-lock as a REGION**, asserted with `max|Δpos| == 0` across it (48's floor posture).
* **the two MARGINS on the HUD** — `a − |Δaz|` and `b − |Δel|` in degrees, because under R1′ the
  walls ARE the lesson and a wall is invisible without the margin that closes at it.
* **`seeker_r_acq_m`** — printed on every arm specifically to be seen NOT MOVING (that is the whole
  meaning of held `Ω`), and to be seen MOVING on the dull-rival control.

---

## §0.2 THE CLAIM, AND WHAT IT IS FILED UNDER

> **A FIXED APERTURE CAN COVER A TWO-AXIS UNCERTAINTY ONLY IF THE TWO ERRORS MULTIPLY TO LESS THAN
> ITS SOLID ANGLE — AND WHEN THEY DO, THE SHAPE IS NOT FREE: IT IS PINNED INSIDE A BAND WHOSE LOW
> WALL IS TOO LITTLE AZIMUTH AND WHOSE HIGH WALL IS TOO LITTLE ELEVATION.**

**Trigger:** `CURVE` under R1, `REGIME` + a bounded `NULL` under R1′ (§0.1.1). ⚠ Not `SLIDER`: this
slice may not claim a monotone improvement in either direction, and says so in advance.

## §0.3 NAMED APPROXIMATIONS (HANDOFF §1)

Everything slice 55 named, unchanged — a SEPARABLE (box) window with `Ω = θ_az·θ_el`, no taper
difference between the axes, no sidelobes, one `detect_eta` for both axes, a single-axis symmetric
triangle sweep in body azimuth, one snapshot dead-reckoned at constant velocity, no datalink update,
no INS drift — **plus this slice's own:**

* **The picture error is authored, deterministic and now THREE-DIMENSIONAL.** Slice 55 authored
  `midcourse_vel_err_mps: [0, 1, 0]`; this slice tilts that unit direction out of the horizontal so
  that the same `midcourse_err_gain` loads BOTH axes. ✅ **The consumer is verified to read all three
  components** — `core/src/missile.jl:1324` adds the whole `Vec3` into `belief_v`. ⚠ The loader
  requires the authored vector to be UNIT length whenever the gain is a live knob
  (`core/src/scenario.jl:1641`), so the tilt is written in the DIRECTION and the size stays on the
  gain.
* **The mechanical stop stays CIRCULAR**, as 55 documented — the per-axis stop is a separate,
  still-open candidate that opens with its own 750× null (`docs/PROHIBITIONS.md` §1).

---

## §0.4 THE GATE-0 PROBES — WHAT MUST BE TRUE BEFORE GATE 1 IS WRITTEN

Probes live in `W:\temp\claude\slice57`. Convention 10: **probe empirically, then pin against the
live wire oracle** — never against a hand-recompute.

| # | probe | what it must show | what it kills if it fails |
|---|---|---|---|
| **P0** | **The NULL arm.** Fly slice 55's wire with an effectively unbounded window and record `A = max\|Δaz\|`, `E = max\|Δel\|` over the blind phase, as functions of the authored tilt and gain. | A tilt/gain pair exists with `A·E` comfortably below `Ω = 100 deg²` **and** with several authorable aspect arms on each side of both walls. | If no such geometry exists the band is not showable and the slice dies here, collapsing into §0.0's slice-52 objection. |
| **P1** | **Draw topology** (convention 3). Count the per-look RNG draws across three aspect arms and the disc. | INVARIANT to the window shape and to the aspect knob. | A shape-dependent draw count means the live knob cannot ship; author-only, and the showcase loses its slider. |
| **P2** | **`Ω` really is held.** Sweep aspect across the full domain and read `seeker_r_acq_m`. | Identical to nine digits on every arm; and MOVING on the dull-rival disc sweep. | If `R_acq` moves, this is slice 46 again wearing a rectangle (55 §II.3's 27 wasted arms, exactly). |
| **P3** | ⭐ **THE TRIGGER BRANCH.** Sweep aspect on the feasible wire and read `search_t_lock_s` on every arm. | Decides **R1 vs R1′** by §0.1.1's stated criterion, before any headline is written. | Nothing — this probe cannot kill, only route. **It must be run before §0.2's trigger line is edited.** |
| **P4** | **The two walls, predicted.** Compare the flown walls against `A²/Ω` and `Ω/E²` from P0. | The predicted and flown walls agree to within one arm. | Disagreement does not kill; it retracts the STATIC reading and the honest finding is published in its place (§0.1.3). |
| **P5** | **F2 — the infeasible wire.** `A·E` just above `Ω`. | NO arm locks, at any aspect ratio. | An arm that locks refutes the inequality — publish, and re-derive. |
| **P6** | **F1 — `dt`.** Re-fly both walls at 5e−4. | Both walls stable to within one arm. | Either wall moving ⇒ integration artifact ⇒ DEAD (42's rule). |
| **P7** | **F3 — the dull rival.** The varying-radius disc sweep, same arm count, published beside the aspect sweep. | The aspect band is not beaten by simply resizing the disc. | If it is beaten, the headline is 46's and this slice has none. |

⚠ **P0, P1 and P2 gate everything else** — they are geometry and plumbing, and each can end the slice
for a stated reason before a line of `core/` is touched.

---

## §1 GATE 1 — PURE PRIMITIVES (small; most of this slice already exists at HEAD)

⭐ **Almost no new physics, and that is the point.** The two-axis window kernel, the two-axis
`aperture_gain` and both authoring keys shipped in slice 55. Gate 1 adds ONE pure function:

`core/src/rf.jl` — `fov_from_aspect(omega_rad2, aspect) -> (a_rad, b_rad)`, with
`a = √(Ω·r)`, `b = √(Ω/r)`. Tests (convention 11 — explicit `atol`, an EXTERNAL anchor, an
INDEPENDENT recompute):

* `a·b == Ω` in the round-trip direction, over a decade-wide `r` sweep;
* `aspect == 1` ⇒ `a == b == √Ω`, and `aperture_gain(a, b) === aperture_gain(√Ω)` at `atol` 0
  (`rf.jl:123` already guarantees that identity BY CONSTRUCTION);
* the ratio is recovered: `a/b == r`;
* degenerates throw `DomainError` (non-positive `Ω` or `r`), matching `aperture_gain`'s posture.

## §2 GATE 2 — THE WIRE

### §2.1 The live knob, and why it is legal

`docs/DEFERRALS.md` §"New candidates raised by slice 55" names the obstacle exactly: *"`set_param`
carries a single Float64, so no drag can hold `a·b` constant. Options are a wire-protocol change or a
DERIVED authoring pair… ⚠⚠ Slice 39's rule applies: a reparameterization must not ship as an
ARCHITECTURE. It ships only if it carries the curve above."*

⇒ **This slice is the "only if".** The derived pair ships, minimally:

* the loader stores `Ω = a·b` once, at load, from the authored `gimbal_fov_deg` / `gimbal_fov_el_deg`
  (no new authoring key, and no YAML change for any existing scenario);
* a new comp key `:gimbal_fov_aspect` (dimensionless, so no unit suffix — slice 35's naming rule)
  is **absent by default**, and its ABSENCE is the bit-identity anchor: slices 1–56 take the shipped
  path verbatim, byte-identical BY CONSTRUCTION rather than by measurement (convention 2, and
  `missile.jl:2288`'s `_box` posture exactly);
* when present, the consumer recomputes `(a, b)` from `(Ω, aspect)` each tick, **clamped at the
  consumer** (convention 5 — `off_axis_ratio` throws a `DomainError` on a non-positive half-width and
  a throw inside `observe!` silently drops the client's connection);
* validate-at-LOAD for the authored side, clamp-at-CONSUMER for the live side (convention 5).

### §2.2 Draw topology

No new RNG draw, and P1 must confirm the per-look draw COUNT is invariant to the aspect knob before
this is written (convention 3: **gate the detection, never the draw**).

### §2.3 Telemetry

`seeker_r_acq_m` already ships. Add the two MARGINS in degrees (§0.1.5) — computed in the CORE, never
in GDScript (convention 13, and slice 53's rule that a gauge counted against a rate cannot live in
the client).

## §3 GATE 3 — THE SHOWCASE

`scenarios/slice57_aspect.yaml` — slice 55's wire with the picture error tilted (§0.3), ONE live
knob (`gimbal_fov_aspect`), and a header that states the band, both walls, and — under R1′ — names
`docs/LESSONS.md`:880 and says why the edges carry the lesson.

Four proofs (convention 14): `net/slice57_verify.gd`, `net/slice57_ui_test.gd`, a headless
smoke-load, and a windowed shot. ⚠ Anything inside `_draw` has NO headless proof (50).

## §4 WHAT KILLS THIS SLICE

1. **P0 finds no geometry** with arms either side of both walls ⇒ it is slice 52 again (§0.0).
2. **F1** — either wall moves with `dt` ⇒ integration artifact ⇒ DEAD (42).
3. **F2** — an arm locks on the infeasible wire ⇒ the inequality is wrong; publish and re-derive.
4. **F3** — the varying-radius disc beats the aspect band ⇒ the lesson is 46's.
5. **F4** — the live knob is not bit-identical to the authored arm ⇒ no slider ships.
6. ⚠ **And the standing one:** if the slice can only be stated as *"narrower is better"* or *"wider
   is better"*, it has re-imported `gimbal_fov_deg`'s disqualification and 46's ban, and it is dead
   whatever the arms say.
