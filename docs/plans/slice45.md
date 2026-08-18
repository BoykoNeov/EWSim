# Slice 45 — **THE ENGAGEMENT IS ANISOTROPIC AND THE HARDWARE IS ROUND: A PER-AXIS STOP, AND THE WINDOW HALF’S PRECONDITION** (§11 Tier-A)

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

### ⚠⚠⚠ §0.2.0 THE SPECIES IS DECIDED HERE, BEFORE ANY NUMBER EXISTS — AND IT SPLITS THE SLICE

An advisor catch on the first draft: *"equal solid angle is the right invariant for an imaging array
and meaningless for a dish, and nothing shipped in 26–44 commits to either."* A held-cost table whose
cost is undefined is not interpretable. So:

| half | the hardware | is a BOX purchasable? | the held-cost invariant |
|---|---|---|---|
| **the STOP** | a two-axis gimbal: an azimuth ring and an elevation trunnion, **two independent mechanisms** | **YES, and the box is the CORRECT model** — the disc is the artifact | mechanical travel per axis (see §0.5 P3) |
| **the WINDOW** | this family's seeker is **RF behind a RADOME** — slices 26–44 exist because of the glass — and slice 44 authored it as a **Ku-band dish** | **NO on this species**: a circular aperture makes a circular beam. A box window needs an IMAGING array, which nothing here has | solid angle (only meaningful once the species changes) |

> ⭐⭐ **SO THE SLICE'S PRIMARY CLAIM IS THE STOP, AND SLICE 43's ARM — WHICH IS A *WINDOW* ARM — IS
> THE HOOK THAT IS LEAST LIKELY TO SHIP.** That is the opposite of how the deferral reads and the
> opposite of how the first draft of this plan was written. It is written down here because the
> species argument was ALREADY in `frames.jl` for both kernels and only one of them survives it.
> ⚠ The window half is NOT killed — it is **conditional on a seeker species this project does not
> yet model**, which makes it a named deferral with a precondition (the shape of every kill in this
> family since 42), not a rung.

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

⚠⚠ **THE ORDER IS PART OF THE DESIGN (advisor).** P1 and P2 need no kernel, no rung and no grid —
only instrumentation on the shipped wire — and P2 is the probe most likely to decide the slice.
The grid probes come after, and the STOP half (P3s) runs **before** the window half (P3w), because
§0.2.0 leaves the stop the only one whose cost invariant is not contested.

**P1 — THE KNOB PROBE, AND IT IS THRESHOLD-FREE.** Instrument `|Δaz|` and `|Δel|` at the window
predicate and at the clamp across every arm this family flies: the 32/33/34 showcase grid, slice
43's search grid, slice 44's §VII.2 fov rows.
> ⚠⚠ **THE FIRST DRAFT OF THIS PROBE FAILED ITS OWN SLICE, AND THE ADVISOR CAUGHT IT.** It read
> *"if `|Δel|` never exceeds ~30 % of the half-width, the elevation knob is dead."* Slice 43's arm —
> the single arm this slice was chosen for — sits at **24.9 %** (2.4934 of 10), so the probe as
> written would have killed the slice on a constant **I invented**, and the only escapes would have
> been to kill it on that constant or to move it after seeing the data. **That is exactly slice 37's
> gate-0 catch** (a bare `rms r > 0.20` chosen by the author, load-bearing, appearing nowhere in
> 26–36). A threshold nobody else in the project uses is not a measurement.
> ⭐ **THE OPERATIONAL FORM, WHICH NEEDS NO CONSTANT:** *does there exist a value of `a_el` inside the
> declared domain that flips a verdict with `a_az` HELD?* On slice 43's arm, with `a_az` = 10, the box
> locks iff `a_el` ≥ **2.4934** — so elevation is LIVE by the operational test and dead by the
> percentage one. **FALSIFIER:** if no in-domain `a_el` flips any verdict at held `a_az`, the
> elevation half-width is the SEVENTH dead knob (`speed` 19, launch altitude 21, the handover bias
> key 36, `ζ` 40, `k_δ` 15, `(R̂, s)` 31) and that half is dead here.

**P2 — THE COLLAPSE PROBE: DOES THE BOX HAVE AN INTERIOR OPTIMUM AT ALL?** (Advisor; this was P8 in
the first draft and it is promoted because it is arithmetic on P1's own traces.) The quantity is
**max `|Δel|` over the ACQUISITION INTERVAL, sampled only where `|Δaz|` is within a half-width or two
of the gate** — ⚠ read over the whole flight instead and you are reading elevation at times the arm
was never close, which is a different number and answers nothing.
> ⭐⭐ **THE PREDICTION THIS PROBE TESTS:** if that max is bounded well below the half-widths in play,
> then a box with `a_el` above it behaves **exactly as a scalar azimuth gate**, the disc behaves as a
> scalar azimuth gate minus a small elevation bite, and held-cost reshaping is a MONOTONE trade with a
> **BOUNDARY optimum at `a_el` = max|Δel|** — no interior optimum, two knobs collapsing to **one knob
> plus a floor**.
> **FALSIFIER, AND IT IS THE CHEAPEST KILL IN THE PLAN:** a boundary optimum IS the collapse. If P2
> shows one, the box is one knob wearing two names and P3/P4's grid need never be flown. ⚠ This is
> slice 41's kill in this family's letter, and 41's rule is verbatim: **run the equivalence probe
> BEFORE a kernel is written.**

**P3s — THE STOP HALF, AT HELD COST, AND IT RUNS FIRST OF THE GRID PROBES.** `gimbal_stop_deg` is an
authored knob sitting at 30.0° on the shipped wire with a MEANINGFUL domain, and slice 34 §2.5 already
flew binding stops on it (critical stops (10, 11] / (14, 16] / (16, 18] at windows 8 / 4 / 2°).
> ⚠ **THE FIRST DRAFT DEFERRED THIS HALF ON A TECHNICALITY AND THE ADVISOR CAUGHT THAT TOO.** It read
> *"if no arm the slice would ship binds the stop, authoring one is a WIRE change."* **It is not.**
> §0.1 item 4 forbids changing the ENGAGEMENT GEOMETRY to make a gate bite (slice 44's lesson);
> sweeping an authored knob inside its own declared domain is what every slice in this arc does.
> ⭐ **THE COST INVARIANT, PRE-REGISTERED AS A ROBUSTNESS REQUIREMENT RATHER THAN A CHOICE.**
> Two defensible readings exist for a two-axis gimbal: **SUM** `a_az + a_el` (two independent
> mechanisms, each costing its own travel) and **PRODUCT** `a_az · a_el` (the swept solid angle).
> **The finding must survive BOTH.** If the verdict flips between them, what has been measured is the
> cost model and not the physics — say so and ship nothing. ⚠ This is deliberately NOT the
> equal-solid-angle rule of the window half: a stop's cost is mechanical travel, not aperture.
> **FALSIFIER:** if a single circular stop reproduces the best box stop's verdict column under BOTH
> invariants, the stop half is dead (§0.6's bound is where that is adjudicated).

**P3w — THE WINDOW HALF, AND IT IS CONDITIONAL ON §0.2.0.** Same held-cost comparison at **equal solid
angle** — square of half-width `a` covers `4a²`, disc of radius `r` covers `πr²` ⇒ **`r = 2a/√π =
1.1284·a`** — run ONLY as the measurement of *what an imaging seeker would buy*, and reported as
such. **It cannot ship as a rung on an RF dish**, and any sentence that forgets that is a false claim
about the hardware rather than a tight one about the geometry.

**P4 — THE ASPECT-RATIO PROBE, IF AND ONLY IF P2 FOUND AN INTERIOR OPTIMUM.** Holding cost, sweep
`a_az : a_el` from 1:1 out toward the engagement's own anisotropy.
> **PRE-REGISTERED PREDICTION** (slice 43's derivation discipline — write the number before flying):
> the optimum should track the ratio of `|Δaz|` to `|Δel|` **at the moments the limit binds** — NOT the
> ratio of the leads, because the window sees the tracking error and the stop sees the travel demand,
> and neither of those is the lead. Derive it off an UNLIMITED arm, predict, then fly. Slice 43's ρ\*
> is the template: a ladder anchored on a prediction is a SHARP test, a blind bracket is not.
> **FALSIFIER:** flown optimum more than one grid step off the predicted one ⇒ the mechanism named is
> not the mechanism operating. Name none (slice 43 §IV.4, the sixth instance in this arc).

**P5 — CONTAMINATION COLUMNS ON EVERY TABLE, READ FIRST.** `a_max` %, stop-bound %, `hold %` in band,
aero %, `t_lock`. Slice 41's kill (an rms measured where a clamp bound read 0.4 % against a real
1.27–4.45× effect) and slice 44's §VII.1 (the "free" arm free right up to **100.00 %** of `a_max`)
are the precedents, and they fail in OPPOSITE directions.
> ⚠⚠ **AND ONE COLUMN IS SPECIFIC TO THIS SLICE: `hypot(head_az, head_el)` AGAINST THE PER-AXIS
> STOP.** §0.4 item 1 is not only a readout hazard — it is the contamination column. A box-clamped
> head may sit at up to `√2·stop` by the shipped readout's own arithmetic, so every excursion number
> in 34–44 changes meaning on a box arm and must be carried in BOTH forms on every table.

**P6 — HALF `dt`, ON ANY VERDICT FLIP.** Re-fly at 2e−3 / 1e−3 / 5e−4. Slice 42's rule: *a finding
whose SIZE is set by the integrator's step cannot be a lesson about hardware.* ⚠ Slice 43 already
cleared its 0.066° arm this way (10.0647 / 10.0656 / 10.0661); a NEW flip gets its own re-fly.
⚠ Slice 44's corollary: **quote the VERDICT, never the metres, on any arm that has lost the track**
(failure magnitudes walked 320 → 627 m across the same `dt` range).

## ⚠⚠ §0.6 THE REPARAMETERIZATION GATE — stated as a BOUND, with its number fixed NOW

Slice 37's precedent (a bound, not a tolerance) and slice 41's (the falsifier fixed in writing one
commit before the measurement existed).

> **THE GATE:** sweep the circular half-width on a fine grid across the whole cost budget and ask
> whether SOME disc reproduces the best box's entire verdict column.
> **THE NUMBER, FIXED HERE, BEFORE ANY MEASUREMENT EXISTS:** if a single circular radius reproduces
> every box arm's **verdict** and its `t_lock` to within **3 %** across the declared domain, the
> slice is **DEAD ON REPARAMETERIZATION** and gets a kill record, not a rung.
> ⚠ **AND THE HONEST VERSION OF THE GATE IS TWO-SIDED.** A box that survives must beat the disc
> **somewhere** and lose to it **somewhere else**. A shape that only ever wins is a size.
> ⚠⚠ **P2 CAN REACH THIS VERDICT WITHOUT THE GRID, AND THAT IS THE POINT OF PROMOTING IT.** A
> BOUNDARY optimum at `a_el` = max|Δel| *is* the reparameterization — one knob plus a floor — and it
> is readable off instrumentation. **If P2 finds it, §0.6 is already answered and the grid is not
> flown.** The 3 % bound above exists for the case where P2 finds an INTERIOR optimum and the grid
> therefore has something to adjudicate.

---

## ⚠⚠⚠ §0.7 THE BIGGEST RISKS — both are >50 % and both are written down first

> **RISK 1 — THE 42/43/44 BLOCKER IN A NEW LETTER, AND IT IS THE LIKELIER KILL.** `box(a) ⊇ disc(a)`
> is a theorem, not a measurement. Held cost is the ONLY thing standing between this slice and the
> exact sentence that killed the previous three. If P3s shows no crossing under BOTH cost invariants, this slice
> dies where 42, 43 and 44 died, and the *fourth* consecutive kill in this family is itself the
> finding: **the angle budget on this wire is one-dimensional, and no amount of reshaping a
> one-dimensional budget is a design variable.**

> **RISK 2 — THE ELEVATION KNOB IS DEAD ON THIS GEOMETRY.** Slice 28 split the channels and the lead
> is AZIMUTH; slice 36's own deferral (**THE ELEVATION HALF**) predicted no optimum shift there and
> called it *"a tooth rather than a slice."* If P1 says elevation never loads, the correct outcome is
> to name an elevation-loaded engagement as its own slice and STOP — not to author one here.

> ⚠ **RISK 3 — THE SEEKER'S SPECIES DECIDES WHICH HALF IS EVEN BUILDABLE. RESOLVED IN §0.2.0, AND
> THE RESOLUTION COSTS THIS SLICE ITS BEST HOOK.** For an imaging seeker the array is a box and the
> DISC is the modelling artifact (you paid for corner pixels and threw them away). For the Ku dish
> slice 44 authored — an RF seeker behind a RADOME, which is the whole reason slices 26–44 exist —
> the beam is round and the BOX is unpurchasable. **The stop is a box under both readings.** ⇒ the
> STOP is the half that can ship here, and slice 43's window arm — the thing that got this slice
> picked — is the half that cannot. **The plan must not read as though the window half were the safe
> one just because slice 43 handed it an arm.**

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
  further than its elevation trunnion) — the natural successor if P3s carries.
* **MONOPULSE / az×el CFAR** (§11 Tier-A) — the other place in the project where a two-axis sensor's
  axes are genuinely independent. Related, not this.
* **THE 3-D REACH OF THE SHAPE**: `seeker_in_fov`'s body-fixed window (slices 32/33) has the same
  species question and is a SEPARATE consumer. This plan touches the HEAD's window and the STOP; the
  body-fixed window is deliberately left alone (32/33's asserts hang off `boresight_angle`).

---

## §0.9 WHAT SHIPS IF IT CARRIES (so the scope is fixed before the numbers arrive)

A shape rung (`:radial` | `:per_axis`) on the **stop** (§0.2.0), disc-by-default; its own per-axis
readouts beside — never replacing — `head_angle_deg` / `gimbal_fov_margin_deg`; ONE scenario carrying
ONE lesson (convention 9); teeth in `test_frames.jl` (the paired wrap case, the box/disc containment,
the held-cost identity under BOTH invariants) and `test_missile.jl` (the verdict flip, both
directions); and gate 3's four proofs. **If P1/P2/P3s kill it, what ships is a kill record and the
renamed precondition — the same product slices 41, 42 and 44 delivered.**

> ⚠⚠ **THE RUNG'S FIDELITY CLASS IS (c) — PHYSICS-CHANGING, NO RNG** (convention 4, and the advisor
> flagged the drift risk before gate 1 exists). A shape toggle CHANGES THE TRAJECTORY, exactly like
> `:integrator` and `:autopilot`. **Byte-identity when the key is ABSENT is the true claim and the
> one gate 1 may make.** "Toggling the rung is bit-identical" is the class-(a) sentence and would be
> a FALSE CLAIM here — the copy-paste trap convention 4 names by name, caught previously by advisor
> and pre-empted here in writing.
