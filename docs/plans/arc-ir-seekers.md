# THE IR / HEAT-SEEKER ARC — **SCOPING ONLY** (§11 Tier-A "sibling domains")

**Status: SCOPING. No gate 0 spent, no probe run, no code, no slice number claimed.** This file
exists so the arc can be argued about before anything is built. Every ordering below is a
PROPOSAL; two of the entries are explicitly marked as needing their own gate-0 probe before they
may be given a position at all. ⚠ Nothing here has been measured — the only measured statements in
this document are the ones in §0, which describe what is ALREADY on the wire.

Written 2026-08-17 in answer to *"do we currently model heat seekers, different types, different
spectra, different guidance generations, different flares?"* The answer was **no to all five**, and
this is the scope of the "no".

⚠ **NOT a slice plan.** `docs/plans/` otherwise holds only `sliceN.md` (including kill records —
`slice39.md`). This is an ARC-level document: a spine of candidate slices, the seam each one moves,
and the traps this project has already learned to fear. A slice that leaves here gets its own
`sliceN.md` and its own gate 0, as always.

---

## §0 WHAT EXISTS TODAY — measured, not remembered

The seeker measures an **ANGLE**, and nothing else. There is no radiometry anywhere in the project.

| What a heat seeker needs | What the core has |
|---|---|
| Radiant intensity of a source | — nothing |
| A spectral band / detector response | — nothing |
| Atmospheric transmittance | — nothing (the RF path has propagation rungs; the seeker has none) |
| A detection threshold on signal strength | — nothing (the RADAR has one; the seeker does not) |
| Target signature vs aspect | — nothing (a target is a point with a position) |

⭐ **THE ONE MEASUREMENT THAT DEFINES THE GAP** (`core/src/missile.jl:2908`, `_scan_sources`): the
`:scan` seeker paints its angular profile from `(bearing, intensity)` per source, where `intensity`
is the **authored comp key straight through** — no `1/R²`, no `1/R⁴`, no attenuation, no aspect
term. Confirmed by reading the function. ⇒ **the shipped seeker is BAND-AGNOSTIC**: it commits to
neither RF nor IR, which is exactly why slice 13 could write *"chaff and a flare are the SAME
mechanic at this fidelity"* (`docs/plans/slice13.md:175-179`) and be right.

What the seeker DOES have — all of it geometry and signal processing, all of it reusable by an IR
seeker unchanged:

- `SEEKER_MODES = (:raw, :filtered, :scan)` — the tracker (`estimation.jl:62`)
- `DISCRIMINATION_MODES = (:none, :gated)` — blend-all vs α-β-predicted nearest-neighbour gate
  (`estimation.jl:79`) — **the seduction/rejection seam already exists**
- `SEEKER_AXES_MODES = (:pitch_plane, :az_el)` — dimensionality (`estimation.jl:109`)
- `SEEKER_HEAD_MODES = (:body_referenced, :space_stabilized)` — the gimbal servo's frame
  (`frames.jl:1063`), plus FOV, gimbal stop, slew rate, handover bias, gyro error (slices 32–38)
- a `:decoy` entity kind with ONE `comp[:intensity]` and no dynamics (`scenario.jl:173-188`)

And the named approximations on that decoy, verbatim from `scenario.jl:174-176` — **present from
t=0, born already-separated, constant velocity, constant intensity, no bloom / burn-out / timed
ejection.** ⇒ nothing that makes a flare specifically a flare is modelled.

**The arc is therefore mostly REUSE.** The genuinely new physics is exactly one thing, §1.

---

## §1 THE ONE NEW THING: A RADIOMETRIC SIGNAL MODEL

Everything in this arc rests on being able to answer *how much signal does this seeker get from
this source, right now?* — the IR analogue of `rf.jl`'s radar equation:

```
        S  =  J(aspect, band) · τ_atm(R, band) · A_aperture / R²      [W on the detector]
        SNR = S / NEP                                                  (detector noise-equivalent power)
```

Four inputs, all of which the project currently lacks: a source radiant intensity `J`, an
atmospheric transmittance `τ_atm`, an aperture, and a detector noise floor. Once they exist, every
later entry in this arc is a knob or a rung on top of them.

⭐⭐ **THIS PAYS AN ALREADY-NAMED DEBT.** §11 Tier-A and the slice 32/33/34 deferral list both carry
*"SEEKER RANGE / SNR ACQUISITION LIMITS — 32/33/34 model only the ANGLE half of 'can the seeker see
it'"*. §1 is the RANGE half. That is a strong argument for it going first regardless of the rest of
this arc: it closes a hole the radome/gimbal family named five slices ago.

### ⚠ THE DRAW-TOPOLOGY QUESTION, ANSWERED BY READING THE CODE (advisor catch — it changes the class)

The obvious fear is that adding radiometry adds an RNG draw and therefore lands in the class-4b
introduce-rejected box with `:cfar` (convention 4b). **It does not have to.** Measured:

- `_observe_point3d!` (`missile.jl:1677-1678`) draws **exactly 2 `randn` unconditionally, at the
  top, before any gate**, then scales them by `σ = comp[:sigma_seek]`.
- `detect_once` (`detection.jl:300-306`) likewise **samples unconditionally** and gates only the
  BOOLEAN (`_sample_z(...) > th`).

⇒ two draw-invariant routes exist, and the arc should take one of them:

1. **σ from SNR** — radiometry sets the angle noise on the draw ALREADY being taken. Zero new
   draws. Lock range emerges as "σ blows up until the track is lost". **Class 4a, introduce-safe,
   live-togglable — the button the showcase wants.**
2. **An acquisition test written like `detect_once`** — draw unconditionally, gate the boolean.
   Also class 4a.

⚠ The 4b hazard is real ONLY if the draw COUNT varies with rung, slider or geometry (convention 3).
Write it either of the two ways above and it does not. **Do not file this arc as 4b by assumption.**

### ⚠ WHICH SEAM MOVES — and it is smaller than §11 currently says

HANDOFF §11 Tier-A files IR behind *"add an IR environment channel to `env`"*. **That overstates the
cost of the entry slice.** `w.env` (phase-2 `build_env!`) is what you need when MORE THAN ONE
consumer reads the same field — that is why jamming lives there (slice 4). A single seeker can read
a target's signature comp keys DIRECTLY, exactly as `_scan_sources` reads `:intensity` today.

⇒ **the `env` channel is required at IRST / multiple seekers (§2 G), not at §1.** §1 is comp keys +
a pure lib + a fidelity rung — a pure Tier-A swap, no contract change.

---

## §2 THE PROPOSED SPINE

Each entry: the lesson, the seam, what it reuses, the metric, and the risk. **The metric matters as
much as the lesson in this project** — see §4's warning about boolean outcomes.

### A. THE RADIOMETRIC LINK BUDGET AND THE LOCK RANGE — §1 made into a slice

- **Lesson:** *the range at which a seeker can see a target is a BAND decision and an ATMOSPHERE
  decision, not an aperture decision.* The same target, same aperture, same detector gives very
  different lock ranges in different bands because the atmosphere is transparent in some places and
  opaque in others.
- **Seam:** new pure lib (`radiometry.jl`); comp keys on `:target`; one fidelity rung on the seeker.
- **Reuses:** the whole seeker (angles, tracker, FOV, gimbal), `rf.jl`'s link-budget house style.
- **Metric:** LOCK RANGE (continuous, monotone in the knob) — good.
- **Risk:** low. This is the arc's foundation and the one entry that is nearly certain to survive
  its own gate 0.

### B. ASPECT DEPENDENCE — THE TAIL-CHASE CONSTRAINT

- **Lesson:** ⭐⭐ *an early heat seeker is a REAR-HEMISPHERE weapon, and that is a GEOMETRY
  constraint, not a sensor constraint.* Hot metal in the tailpipe is visible from behind; from the
  beam or the front you see far less of it. Make `J` a function of aspect and the launch ENVELOPE
  collapses to a cone behind the target.
- **Seam:** one more term in `radiometry.jl` + comp keys. Nothing else moves.
- **Reuses:** ⭐ the collision-triangle machinery slice 32 already ships (`lead_angle_deg`,
  `collision_lead_angle`) — **this is slice 32's "a field of view costs you not ACCURACY but the
  ENVELOPE" in a second currency**, and the two compose into one envelope statement.
- **Metric:** the envelope itself — the set of aspects from which a shot holds. Continuous, and the
  project already knows how to assert an envelope as a predicate (slice 32/36).
- **Risk:** low. Cheap after A, and probably the largest teaching payoff per unit of work in the
  whole arc.

### C. TWO-COLOUR / SPECTRAL DISCRIMINATION

- **Lesson:** ⭐⭐ *one band cannot tell a flare from a target NO MATTER HOW BRIGHT the flare is;
  two bands can, because a flare burns far hotter than a jet exhaust and therefore has a different
  RATIO between bands. And the counter is a flare engineered to match the ratio* — which is where
  the spectrally-matched flare enters as a second decoy type.
- **Seam:** a second band in `radiometry.jl`; a discrimination rung beside the existing
  `DISCRIMINATION_MODES`; a `temperature` comp key on the decoy.
- **Reuses:** the `:none`/`:gated` seduction seam wholesale.
- **Metric:** ⚠ needs care — "did it break lock" is a BOOLEAN (see §4). Prefer separation angle at
  break, or the ratio margin between target and flare.
- **Risk:** ⚠⚠ **THE FALSE-FIDELITY TRAP IS LOADED HERE.** If the two bands' signatures are
  proportional for every source, the second band is a REPARAMETERIZATION of the first and the rung
  is DEAD — precisely the class this project has killed five times (slice 15 `k_δ`, 19 `speed`, 31
  `(R̂, s)`, 39 the nulling loop, and the slice-16 refusal). **The ratio must genuinely differ
  between target and flare, and gate 0 must MEASURE that before the rung is written**, not assume
  it from the physics story.

### D. THE TRACKER GENERATIONS — reticle / conical scan / rosette / imaging

- **Lesson:** ⭐⭐ *a spinning-reticle seeker measures its pointing error as an AMPLITUDE MODULATION
  — and that is EXACTLY why it can be broken by a modulated light source.* The tracker's own
  encoding scheme IS its vulnerability. An imaging seeker resolves the flare as a separate OBJECT
  and rejects it on shape and kinematics rather than on colour.
- **Seam:** ⚠⚠ **BIGGER THAN B/C/E.** This is the one entry where the seeker stops emitting an
  angle and starts emitting a demodulated error signal — an internal contract move, not a knob.
- **Risk:** ⚠⚠ **NO ORDERING POSITION ASSIGNED. Needs its own gate-0 probe first.** Given this
  project's record (slice 39 killed before any code existed), the honest shape is to probe whether
  the reticle's modulation actually produces a DIFFERENT failure mode from the existing tracker
  rungs, rather than a costlier spelling of them.

### E. FLARE DYNAMICS — bloom, burn-out, ejection, separation rate

- **Lesson:** ⭐ *the reason a flare works is TIMING AND SEPARATION RATE, not brightness.* A flare
  that blooms too slowly, or does not separate fast enough, never breaks the lock — and the counter
  is a seeker that gates on KINEMATICS, which is the `:gated` mechanic that already ships.
- **Seam:** the decoy entity's named approximations, lifted one at a time
  (`scenario.jl:174-176`). ⚠ Slice 13 already flagged the trap: giving the decoy a ballistic mover
  couples it to the missile's `:integrator` rung — a cross-lesson leak (`slice13.md:180-183`).
- **Metric:** ⭐⭐ **this is where the arc GETS its continuous metric** — time-to-break, separation
  angle at break. Cheap, because the decoy entity already exists.
- **Risk:** low.

### F. IRCM / DIRCM — a modulated jamming source

- **Lesson:** the reticle seeker of D is broken by a lamp; an imaging seeker forces you to a laser
  and a track. The IR analogue of the existing noise jammer.
- **Seam:** phase-2 `build_env!` only — structurally the slice-4 `Jammer` shape (`scenario.jl:198`).
- **Risk:** ⚠⚠ **NO ORDERING POSITION. Depends entirely on D, and inherits D's probe.**

### G. IRST — passive IR as a SENSOR rather than a seeker

- **Lesson:** ⭐ passive detection gives you a BEARING and no range — which is the bearings-only
  problem slice 5 already solved. Two IRST sensors triangulate.
- **Seam:** ⭐⭐ this is where the **`env` IR channel finally earns itself** (more than one consumer).
- **Reuses:** ⭐⭐ `estimation.jl`'s `gauss_newton` and the GDOP/error-ellipse machinery UNCHANGED —
  the §9 cross-domain-reuse story ("the same `gauss_newton` fixes a DF emitter and a GPS receiver")
  gaining a THIRD domain for free. That is a strong argument for G on its own merits.

---

## §3 ORDERING — and the one contested decision

**Proposed: A → B → E → C → (D, F, G as their own decisions).**

A is unarguably first (everything needs radiometry). B is cheap and pays the most per unit of work.

⚠ **THE CONTESTED ONE IS E-BEFORE-C, and the argument is worth making explicitly rather than
picking silently:**

- **For E first (the recommendation):** C's entire payload is *rejecting a flare*, and today's
  flare is present-from-t=0, constant-velocity, constant-intensity. **Rejecting THAT is a weak
  demonstration.** E makes the flare a real object first and hands the arc the continuous metric it
  otherwise lacks. Then C rejects something worth rejecting.
- **Against (for C first):** the GENERATIONAL story is what was actually asked about, and C is its
  headline — one band cannot, two bands can. Putting E first delays the arc's most quotable result.

Both are defensible. **Recorded as a decision, not resolved.**

⚠ **FLARE TYPES SPAN TWO ENTRIES, NOT ONE.** A spectrally-matched flare is defeated by COLOUR (C);
a kinematic flare is defeated by GATING (E, connecting back to the shipped `:gated` mechanic). Do
not file "flare types" in a single slice.

---

## §4 THE TRAPS THIS ARC WALKS INTO

1. ⚠⚠ **THE FALSE-FIDELITY CLASS, LOADED AT C** (and latent at D). Five kills on record. Any new
   rung must be shown to be a distinct CODE PATH that no in-domain knob value reaches (the
   knob-vs-rung discriminator, `atmosphere.jl`'s header). **Compose your own equivalences before
   believing a rung** — slice 39's lesson, and C is exactly the shape that hides one.
2. ⚠⚠ **THE METRIC PROBLEM IS SPECIFIC TO THIS ARC.** The natural outcome here is *"did it break
   lock"* — a BOOLEAN. The radome family only worked because it found continuous metrics (rms body
   rate, lock margin in degrees). **Every entry above must name a continuous metric before it gets
   a plan**; E is listed early partly because it manufactures one.
3. ⚠ **DRAW TOPOLOGY** — answered in §1, but it must be re-checked per slice, not inherited.
   Convention 3: gate the VALUE, never the draw.
4. ⚠ **CONVENTION 9 TENSION.** This arc naturally wants target signature + flare + atmosphere +
   seeker all live at once. Each slice isolates ONE. Expect the two-scenario pattern (slices 22,
   34, 36) to be needed more than usual here.
5. ⚠ **BYTE-IDENTITY.** Every entry must leave slices 1–38 bit-for-bit identical. The seeker path
   is shared with the whole radome/gimbal family (26–38) — the most heavily-asserted code in the
   project. Presence-gate on a NEW key; never widen a shared symbol.

---

## §5 WHERE THIS SITS AGAINST THE AGREED SEQUENCE — ⚠ A USER DECISION, NOT MINE

HANDOFF §11 carries an **AGREED SEQUENCE (user, 2026-07-20)**: (1) slice 22 [done], (2) SCENARIO
SCALE, (3) ACTOR FIDELITY. An IR arc is a new LESSON arc and therefore competes with items 2 and 3
— **except that it does not compete cleanly, and the split is worth stating plainly:**

- ⭐ **§1/A/B are ACTOR FIDELITY.** A target that has an infrared signature is an aircraft that can
  be SEEN PASSIVELY — an actor upgrade under the dual aim's own grading (FOIL-grade vs
  ACTOR-grade), not merely a lesson. These parts SERVE the agreed sequence.
- ⚠ **C/D/E/F are lesson slices** and DO jump the queue ahead of scenario scale.
- ⭐ **G (IRST) is a sensor an actor needs** and leans back toward actor fidelity again.

⇒ the arc is not one queue position. **Whether to take the actor-grade half early and defer the
lesson half is the user's call**, and it is the reason this file exists rather than a slice plan.

---

## §6 DATA HONESTY — a hard constraint, not a style note

Real infrared signatures, flare compositions, and seeker performance figures are classified and/or
export-controlled. **Nothing in this arc may claim to model a specific real missile, seeker or
aircraft.** This is not a new rule — it is two existing ones:

- §11 Tier-A already scopes device modelling as *"generic archetypes … to a lesser degree from
  public data"*.
- §12 already carries the **FALSE PRECISION** watch-item (*"a photoreal Godot scene implies accuracy
  the kinematic model lacks — keep a visible fidelity badge in every view"*).

⇒ **generations are named as MECHANISM STEPS, never as model designations**: uncooled rear-aspect →
cooled all-aspect → two-colour rejection → imaging. Every number authored, every scenario labelled
illustrative. A scenario file named after a real weapon would be a §12 violation.

---

## §7 WHAT MUST BE PROBED BEFORE ANY OF THIS GETS A SLICE NUMBER

In order, cheapest first:

1. **Does a σ-from-SNR seeker produce a LOCK RANGE that is monotone and clean over a usable knob
   domain?** (§1 route 1.) If yes, A is a class-4a slice with a live button. If no, route 2.
2. **Do target and flare band-ratios separate enough to carry C** — measured, not assumed? If they
   collapse, C is a false fidelity and dies before it is written (§4.1).
3. **Does a reticle tracker fail DIFFERENTLY from the shipped trackers**, or is it a costlier
   spelling of them? D and F both hang on this answer.
4. **Does aspect-dependent `J` actually collapse the envelope** on the geometry the arc flies, or
   does the existing FOV/lead constraint (slice 32) bind first and hide it?

⚠ Probe 4 is the one most likely to surprise: this arc's B entry and slice 32's FOV entry both cap
the ENVELOPE, and if the older one binds first, B measures nothing. That is the same shape as slice
33's opening hypothesis — **and slice 33's was REFUTED at gate 0.**
