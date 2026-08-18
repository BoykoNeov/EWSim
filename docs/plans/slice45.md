# Slice 45 — **THE ENGAGEMENT IS ANISOTROPIC AND THE HARDWARE IS ROUND: A PER-AXIS WINDOW AND A PER-AXIS STOP** (§11 Tier-A)

**Status: GATE-0 SKELETON (2026-08-18). No code. Nothing measured yet.**
Everything below §0 is a PREDICTION with a falsifier attached, written before the first probe runs.

Inherited from: `docs/DEFERRALS.md` (**a RECTANGULAR / PER-AXIS FOV**, named by slice 34's gate 1,
sharpened by slice 43's gate 0 §IV.3), `core/src/frames.jl` (`off_axis_angle`'s and `head_clamp`'s
own docstrings, which each record that their circular shape rests on a **species argument**),
`docs/plans/slice34.md` §2.5 (**the stop and the window are ONE budget**), `docs/plans/slice43.md`
§IV.3/§V (the flying arm), `docs/plans/slice44.md` §VI/§VII (what a gate must do to be priceable).

---

## ⚠⚠ §0.0 THE ADMISSION TICKET — WHY THIS IS NOT SLICE 42/43/44 RE-RUN

Three consecutive gate-0s died on ONE sentence: **a wider detector window is FREE on this wire, so
nothing that makes the window bigger can be priced.** Slice 42 found it (a single 15° window rescues
every showcase cell with no search at all). Slice 43 sharpened it into an identity (**the cost of
acquiring is the overlap deficit `|err| − fov`**, so widening the glass by 2° and travelling 2°
further are THE SAME ACT). Slice 44 went and built the carrier that was supposed to make the window
cost something — `SEEKER RANGE / SNR ACQUISITION LIMITS` — and measured it INERT (`R_acq/R_launch` =
1.255; the gate is byte-identical to no gate).

> ⭐ **THIS SLICE DOES NOT MAKE THE WINDOW BIGGER. It changes the window's SHAPE at HELD COST, and
> the two shapes are NOT ORDERED**: a box admits the diagonal a disc rejects, and a disc of matched
> area admits the on-axis direction the box rejects. A trade between two unordered sets is priceable
> even when "more of it" is free — *provided the cost is actually held*, and holding the cost is the
> entire design of this gate.

> ⚠⚠ **AND SLICE 44's RULE DOES NOT REACH IT — BUT ONLY FOR ONE REASON, WHICH MUST BE STATED
> PLAINLY.** 44's law is *"a detection gate can only price a design variable if the engagement is
> launched OUTSIDE the sensor's horizon."* That is about the **RANGE** gate, which on this wire is
> inert. **The ANGLE gate is NOT inert on the same wire, and that has been measured three separate
> times:** slice 34's window cliff over `gimbal_fov_deg` ∈ [1, 8]°; slice 43's ρ = 1 arm held out at
> 10.0656° against a 10° window; slice 44's own §VII.2 rows at fov 8.0/8.6/8.8. **The angle window
> binds on the shipped wire. That is the whole admission ticket, and if it turns out to be false the
> slice dies immediately.**

---

## ⚠⚠⚠ §0.1 WHAT THIS DOES **NOT** CLAIM — stated first, in the negative

1. **NOT "a rectangle is better than a circle."** At matched half-width `a` the box strictly
   CONTAINS the disc (`box(a) ⊇ disc(a)`), so at matched half-width the box is simply MORE WINDOW —
   and more window is free here. **Any table that compares `box(a)` to `disc(a)` is measuring
   slice 42/43's finding again and proves nothing about shape.**
2. **NOT that slice 43's 0.066° arm carries the slice.** Slice 43 quoted that flip as NARROW itself
   and wrote down which half of its own finding was non-marginal (the 25 % of window radius spent on
   the unswept axis). One arm, at 0.066°, in ONE direction, is a hook — not a lesson.
3. **NOT a claim about the exact cone.** `off_axis_angle` is the ANGLE-SPACE radius, not the true
   cone half-angle (frames.jl's §1 approximation, gap 0.0004–0.139° over the plausible domain). A
   "rectangle in angle space" is likewise not a rectangle on the sphere. Both approximations are
   INHERITED here and neither is the lesson; if a verdict ever turns on that gap, the slice stops.
4. **NOT a wire change.** If the shape only matters on an engagement this family does not fly, the
   answer is to NAME that engagement as its own slice — slice 44's lesson about what you may and may
   not do to make a gate bite — not to quietly author elevation into the showcase.
5. **NOT a re-litigation of `boresight_angle`.** Slice 34 DEFINED `boresight_angle` as
   `off_axis_angle` at `ref = (0, 0)`, and slices 32/33's asserts hang off it. Nothing here may
   redefine it.

---

## ⭐ §0.2 THE CANDIDATE LAW

> ⭐⭐ **THE ENGAGEMENT IS ANISOTROPIC AND THE HARDWARE IS ROUND.**
> On slice 28's crossing geometry the lead lives almost entirely in AZIMUTH — the head reaches
> 18–23° of azimuth while its elevation stays at `|el| ≤ 0.84°` (frames.jl, measured). The detector
> window is a disc and the mechanical stop is a disc. **So the elevation half of both budgets is
> bought and never spent, and the azimuth half is the only one that ever binds.** Under a HELD COST,
> reshaping either disc into a box aligned with the engagement's own anisotropy should buy azimuth
> envelope with elevation nobody was using.

Three sub-claims, each independently killable:

* **(a) THE WINDOW'S SHAPE DECIDES ACQUISITION ON AT LEAST ONE FLYING ARM.** Slice 43 §IV.3, already
  measured: Δaz = 9.7519 and Δel = 2.4934 both inside a 10° half-width, while the radial gate holds
  the arm out at 10.0656°. ⚠ Margin 0.066°; step-independent (10.0647 / 10.0656 / 10.0661).
* **(b) THE STOP IS THE HALF WHERE THE PHYSICS IS UNAMBIGUOUS.** A two-axis gimbal has independent
  mechanical stops — an azimuth ring and an elevation trunnion — and the box is the CORRECT model,
  not an alternative one. (Symmetrically: for the dish seeker slice 44 authored, the RF beam really
  is round, so the WINDOW's disc may be right and the STOP's disc wrong. **The two halves have
  different burdens of proof and this plan keeps them apart.**)
* **(c) THE TWO BUDGETS ARE COUPLED, SO RESHAPING ONE MOVES THE OTHER.** Slice 34 §2.5:
  `off_head ≈ (head travel requirement − stop) + free tracking error` — *a clamped head cannot reach
  the LOS, so its deficit is spent out of the DETECTOR budget.* A per-axis stop therefore shifts the
  window's load PER AXIS, which is a mechanism neither the window half nor the stop half owns alone.

---

## §0.3 THE PHYSICS, AND WHERE IT LIVES

| quantity | kernel | site | current shape | why it is that shape |
|---|---|---|---|---|
| detector window | `off_axis_angle(ref_az, ref_el, az, el)` | `frames.jl:767` | `hypot` disc | *"a detector window is ONE window about ONE axis"* — a **species argument**, written down as one |
| mechanical stop | `head_clamp(az, el, stop)` | `frames.jl` | radial projection onto a disc | must match the `head_angle_deg = hypot(...)` readout — also a **species argument** |
| body-fixed window (32/33) | `seeker_in_fov` / `seeker_fov_margin` | `frames.jl` | disc about boresight | slice 32's, and `boresight_angle` is DEFINED from `off_axis_angle` |

Flying consumers: `missile.jl:2060`, `:2086` (the head's window predicate), `:2139` (`off_head`),
`:2302` (`in_fov = off_head ≤ fov_h`), plus `head_slew` / `head_slew_full` / the handover
initialisation, all of which end in `head_clamp`.

⚠ **CONVENTION 2 IS THE BINDING CONSTRAINT ON ANY IMPLEMENTATION.** Slices are additive and must be
bit-for-bit identical. So the circular kernels are **not edited** — a per-axis variant is added
beside them behind a shape rung whose absence leaves the disc path byte-for-byte untouched. Any
design that "generalises" `off_axis_angle` and recovers the disc as a special case is the wrong
design, however clean it reads: it puts every prior slice's asserts downstream of new arithmetic.

---

## §0.4 THE SEAM — three disciplines, each already written down by an earlier slice

1. ⚠⚠ **A PER-AXIS STOP MAKES `head_angle_deg` LIE.** `frames.jl` names this hazard by name: *"a
   PER-AXIS clamp would let the head sit at `√2·stop` while the readout compared against `stop`."*
   And it records that slice 34's own gate-0 probe **did exactly that and nobody noticed**, because
   no arm of that slice bound the stop in either form. A per-axis stop must ship its own readout, or
   the HUD and every excursion column in 34–44 silently change meaning.
2. ⚠⚠ **THE CLAMP'S CONTRACTION ARGUMENT IS ABOUT A DISC AND MAY NOT BE INHERITED.** `head_clamp`
   has exactly ONE site (with `head_slew` and the handover init both ending in it) *because slice
   34's gate 1 measured that the servo is a contraction toward the target **only from inside the
   disc***. On a BOX that argument must be re-established, not assumed — and the handover init is
   where a violation would be handed to tick 1 with nothing downstream able to detect it.
3. ⚠ **THE WRAP IS LOAD-BEARING AND SURVIVES THE RESHAPE.** `off_axis_angle` wraps each axis before
   combining (a head at −179° and a LOS at +179° must read 2°). A per-axis predicate needs the same
   wrap on each axis SEPARATELY, and its tooth must be PAIRED with a does-not-wrap case — a wrap
   test that only exercises the wrapping branch cannot catch a wrap applied where it does not belong.

---

## ⭐⭐ §0.5 THE PROBES, PRE-REGISTERED WITH THEIR FALSIFIERS

**P1 — THE DEAD-KNOB PROBE, AND IT RUNS FIRST.** Instrument `|Δaz|` and `|Δel|` at the window
predicate across every arm this family flies: the 32/33/34 showcase grid, slice 43's search grid,
slice 44's §VII.2 fov rows.
> **FALSIFIER (pre-registered):** if `|Δel|` never exceeds ~30 % of the window half-width on any arm
> that decides a verdict, then an elevation half-width is a **DEAD KNOB** — the false-fidelity class
> this project has now caught six times (`speed` 19, launch altitude 21, the handover bias key 36,
> `ζ` 40, `k_δ` 15, `(R̂, s)` 31) — and the "rectangle" is a scalar reparameterization of the disc
> along azimuth alone. **`fov_el` must move at least one verdict at a value where `fov_az` is held,
> or the window half of this slice is dead here.**

**P2 — THE BOTH-DIRECTIONS PROBE.** Slice 43 supplies one arm where the box ACCEPTS and the disc
REJECTS. Find the other direction: an arm where the BOX rejects and a matched disc ACCEPTS.
> **FALSIFIER:** if no such arm exists anywhere in the declared domain, then on this wire the box is
> merely MORE PERMISSIVE than the disc — which it is by construction — and slice 42/43's "a wider
> window is free" kills the slice outright, in the same letter it killed the previous three.

**P3 — THE HELD-COST PROBE (the one that makes it a trade at all).** Fix the cost as **equal solid
angle** — a focal-plane array's pixel count at fixed resolution, or an aperture. Square of
half-width `a` covers `4a²`; disc of radius `r` covers `πr²` ⇒ **`r = 2a/√π = 1.1284·a`**. Fly
`box(a)` against `disc(1.1284a)` over the acquisition grid.
> **FALSIFIER:** if the matched-area disc wins or ties on EVERY arm, the shape buys nothing at held
> cost and the slice is a widening in disguise.
> ⚠ **THE COST DEFINITION IS ITSELF A CLAIM AND MUST BE DEFENDED, NOT ASSUMED.** Equal area is right
> for an imaging array; for the Ku dish slice 44 authored, the aperture sets a ROUND beam and a box
> is not purchasable at any price. **State which seeker the slice is about, in the plan, before the
> numbers exist.**

**P4 — THE ASPECT-RATIO PROBE (where the lesson would live).** Holding area, sweep the aspect ratio
`a_az : a_el` from 1:1 out toward the engagement's own anisotropy.
> **PRE-REGISTERED PREDICTION (slice 43's derivation discipline — write the number before flying):**
> the optimal aspect ratio should track the ratio of `|Δaz|` to `|Δel|` **at the moments the window
> binds** — NOT the ratio of the leads (the window sees the tracking error, not the lead). Derive
> that ratio off a NO-WINDOW arm, predict the optimum, then fly it. Slice 43's ρ\* is the template:
> a prediction the ladder is anchored on is a SHARP test; a blind bracket is not.
> **FALSIFIER:** if the flown optimum sits more than one grid step off the predicted one, the
> mechanism named is not the mechanism operating — say so and name none (slice 43's §IV.4 lesson,
> the sixth in this arc).

**P5 — THE STOP HALF, RUN SEPARATELY.** Repeat P3/P4 on `head_clamp` with the window held circular.
> **FALSIFIER:** slice 34's grid ran the stop at 30° or 1e6° against a head travel of at most 23.4°,
> so **the stop has never bound on a shipped arm** — only §2.5's deliberately-bound probe did. If no
> arm the slice would ship binds the stop, the stop half has NO FLYING ARM, and authoring one is a
> WIRE change (§0.1 item 4). Defer it; do not smuggle it.

**P6 — CONTAMINATION COLUMNS ON EVERY TABLE, READ FIRST.** `a_max` %, stop-bound %, `hold %` in
band, aero %, `t_lock`. Slice 41's kill (an rms measured where a clamp bound read as 0.4 % against a
real 1.27–4.45× effect) and slice 44's §VII.1 (the "free" arm free right up to **100.00 %** of
`a_max`) are the two precedents, and they fail in OPPOSITE directions.

**P7 — HALF `dt`, ON ANY VERDICT FLIP.** Re-fly at 2e−3 / 1e−3 / 5e−4. Slice 42's rule: *a finding
whose SIZE is set by the integrator's step cannot be a lesson about hardware.* ⚠ Slice 43 already
cleared its 0.066° arm this way; a NEW flip gets its own re-fly. ⚠ And slice 44's corollary: **quote
the VERDICT, never the metres, on any arm that has lost the track** (failure magnitudes walked
320 → 627 m across the same `dt` range).

**P8 — COMPOSE THE EQUIVALENCES BEFORE BELIEVING IT IS AN ARCHITECTURE.** Two half-widths is two
knobs only if both are free. If the flown optimum aspect is a CONSTANT of the geometry rather than a
design freedom, the box is one knob wearing two names.
> ⚠ **THIS IS SLICE 41's KILL IN THIS FAMILY'S LETTER,** and 41's rule applies verbatim: run the
> equivalence probe BEFORE a kernel is written.

---

## ⚠⚠ §0.6 THE REPARAMETERIZATION GATE — stated as a BOUND, with its number fixed NOW

Slice 37's precedent (a bound, not a tolerance) and slice 41's (the falsifier fixed in writing one
commit before the measurement existed).

> **THE GATE:** sweep the circular half-width on a fine grid across the whole cost budget and ask
> whether SOME disc reproduces the best box's entire verdict column.
> **THE NUMBER, FIXED HERE, BEFORE ANY MEASUREMENT EXISTS:** if a single circular radius reproduces
> every box arm's **verdict** and its `t_lock` to within **3 %** across the declared domain, the
> slice is **DEAD ON REPARAMETERIZATION** and gets a kill record, not a rung.
> ⚠ **AND THE HONEST VERSION OF THE GATE IS TWO-SIDED.** A box that survives must beat the disc
> **somewhere** and lose to it **somewhere else** (P2). A shape that only ever wins is a size.

---

## ⚠⚠⚠ §0.7 THE BIGGEST RISKS — both are >50 % and both are written down first

> **RISK 1 — THE 42/43/44 BLOCKER IN A NEW LETTER, AND IT IS THE LIKELIER KILL.** `box(a) ⊇ disc(a)`
> is a theorem, not a measurement. Held cost is the ONLY thing standing between this slice and the
> exact sentence that killed the previous three. If P3 shows no crossing at matched area, this slice
> dies where 42, 43 and 44 died, and the *fourth* consecutive kill in this family is itself the
> finding: **the angle budget on this wire is one-dimensional, and no amount of reshaping a
> one-dimensional budget is a design variable.**

> **RISK 2 — THE ELEVATION KNOB IS DEAD ON THIS GEOMETRY.** Slice 28 split the channels and the lead
> is AZIMUTH; slice 36's own deferral (**THE ELEVATION HALF**) predicted no optimum shift there and
> called it *"a tooth rather than a slice."* If P1 says elevation never loads, the correct outcome is
> to name an elevation-loaded engagement as its own slice and STOP — not to author one here.

> ⚠ **RISK 3 — THE SEEKER'S SPECIES DECIDES WHICH HALF IS EVEN BUILDABLE, AND I HAVE NOT PICKED
> ONE.** For an imaging seeker the array is a box and the DISC is the modelling artifact (you paid
> for corner pixels and threw them away). For the Ku dish slice 44 authored, the beam is round and
> the BOX is unpurchasable. **The stop is a box under both readings.** ⇒ if only one half survives
> its probes, it is likelier to be the STOP, and the plan must not be written as though the window
> half were the safe one just because slice 43 handed it an arm.

> ⚠ **RISK 4 — FOUR STRAIGHT SLICES HAVE SHIPPED NO CODE** (41, 42, 44 kills; 43 a law record). That
> is a reason to pick probes that can KILL EARLY AND CHEAPLY — P1 and P2 need no kernel and no rung,
> only instrumentation on the shipped wire — and it is **not** a reason to lower the bar for what
> counts as a lesson. A slice that ships a rung nobody can justify is worse than a fifth kill record.

---

## §0.8 DEFERRALS NAMED IN ADVANCE (so they cannot be smuggled in as rungs)

* **AN ELEVATION-LOADED ENGAGEMENT** (a climbing/diving target, or the handover error authored in
  elevation — slice 36's `THE ELEVATION HALF`). Its own slice, per §0.1 item 4.
* **THE EXACT CONE ANGLE** vs the angle-space radius, and its box analogue on the sphere. Inherited
  approximation; becomes live only if a window much wider than 10° ever ships.
* **PER-AXIS STOPS WITH DIFFERENT SPECIES ON EACH AXIS** (a real gimbal's azimuth ring travels much
  further than its elevation trunnion) — the natural successor if P5 carries.
* **MONOPULSE / az×el CFAR** (§11 Tier-A) — the other place in the project where a two-axis sensor's
  axes are genuinely independent. Related, not this.
* **THE 3-D REACH OF THE SHAPE**: `seeker_in_fov`'s body-fixed window (slices 32/33) has the same
  species question and is a SEPARATE consumer. This plan touches the HEAD's window and the STOP; the
  body-fixed window is deliberately left alone (32/33's asserts hang off `boresight_angle`).

---

## §0.9 WHAT SHIPS IF IT CARRIES (so the scope is fixed before the numbers arrive)

A shape rung (`:radial` | `:per_axis`) on the seeker, disc-by-default and byte-identical when absent;
its own per-axis readouts beside — never replacing — `head_angle_deg` / `gimbal_fov_margin_deg`; ONE
scenario carrying ONE lesson (convention 9); teeth in `test_frames.jl` (the paired wrap case, the
box/disc containment, the matched-area identity) and `test_missile.jl` (the verdict flip, both
directions); and gate 3's four proofs. **If P1/P2/P3 kill it, what ships is a kill record and the
renamed precondition — the same product slices 41, 42 and 44 delivered.**
