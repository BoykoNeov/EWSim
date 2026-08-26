# Slice 49 — ASPECT-DEPENDENT RCS (how visible you are depends on which way you are pointing)

**Status: GATE 0 — PLAN WRITTEN, NO PROBE RUN YET (2026-08-26).** Suite green at 16154 tests (slice
48); no code shipped. Picked from `docs/DEFERRALS.md` §"New candidates raised by slice 46" after the
search family (42/43/45/48) closed.

**What this slice is:** every target in this project reflects the same amount of radar energy from
every direction. `:rcs_m2` is one scalar on the target's comp, and *nothing anywhere reads the
target's heading*. A real airframe swings 20–40 dB between nose-on and broadside, which is the single
largest term in whether an air-defence radar sees it at all. This slice gives the target a SHAPE and
lets the echo fall out of it.

⚠ Slice 46 already named this gap in writing: `scenarios/slice46_horizon.yaml:128` — *"scalar RCS
with no aspect dependence (`rcs_m2` is the target's own key, shared with the radar path)"*.

---

## §0 — THE PREMISE, READ OFF THE SHIPPED CODE

Three facts located in the tree before any probe runs.

**1. THERE ARE EXACTLY TWO LIVE CONSUMERS OF `:rcs_m2`, AND THEY MUST STAY ONE NUMBER.**

| consumer | line | what it does |
|---|---|---|
| ground radar | `radar.jl:290` (`_target_snr`) | `rcs = tgt.comp[:rcs_m2]`, then `snr_freespace` / `snr_two_ray` / terrain-masked free space |
| missile seeker horizon | `missile.jl:2627` | `rcs_det = max(…get(tgt.comp, :rcs_m2, 1.0), 1e-12)`, then `detection_range` + `snr_freespace` |
| (batch coverage grid) | `batch.jl:307` | `_resolve_target_rcs` — a range×altitude GRID, no target and no heading |

⚠⚠ `missile.jl:2624` carries the standing warning in its own comment: minting a seeker-side RCS copy
*"would give one target two RCS numbers that can silently disagree (convention 7's exact failure)"*.
⇒ **both live consumers wire off ONE primitive or neither does.** Adding aspect to one is precisely
the failure that comment forbids.

**2. NOTHING READS ASPECT ANYWHERE.** `grep -rn 'aspect' core/src/*.jl` returns one hit, in
`slice20_induced_drag.yaml`'s comment about wing aspect RATIO — an unrelated word. The MODEL test
(the 2026-08-18 two-test rule) is therefore not at risk from a pre-existing half-wired key: this is a
clean gap, and wiring it correctly passes the model test by construction.

**3. THE GEOMETRY IS ALREADY CROSSING ON EVERY WIRE IN THE 26–48 ARC.** `slice48_search.yaml`'s
target flies `vel: [0, −200, 0]` while the missile closes from `[0,0,3000]` — so an aspect angle
EXISTS and MOVES on the shipped wire. Whether it moves *where the detection gate is deciding
something* is §0.2's kill risk, and it is the first thing this gate measures.

---

## §0.1 — THE CANDIDATE LESSON, THE GAUGE, AND THE TWO SHOWCASE ARMS

**CANDIDATE HEADLINE.** *A target's echo is a property of its SHAPE and its HEADING, not a number it
carries around. A long thin body seen nose-on returns thousands of times less than the same body seen
broadside — so a target can VANISH while it is still closing.*

**⚠⚠ THE GAUGE IS PRE-REGISTERED BEFORE ANY PROBE RUNS, AND IT IS NOT THE MISS.** `CLAUDE.md` and
`docs/DEFERRALS.md` §"Killed / not worth doing, from slice 46" both close this off: *"Any showcase
built on MISS for this component — DEAD, twice now"* (44 killed the component on it; 46 measured it
non-monotone along the ladder AND backwards across the button), and *"a late lock is paid in
MANOEUVRE AUTHORITY, never in MISS."* Anything that moves the ACQUISITION INSTANT is read on the
authority column. **A non-monotone miss curve is therefore NOT evidence of a kill in this slice, and
must not be quoted as one.**

**TWO SHOWCASE ARMS ARE PRE-REGISTERED, WITH P0 AS THE SELECTOR.** This is deliberate and it is slice
44's lesson applied in advance: *a detection gate can only price a design variable if the ENGAGEMENT
is launched where the gate is deciding something — a property of the WIRE, not of the physics.* If
the missile wire is flat, that is a WRONG-WIRE result, not a kill, and the showcase relocates while
the seeker wiring still ships.

- **ARM A — the missile wire (slice 48's geometry).** Aspect moves the seeker's horizon, hence the
  acquisition instant, hence the authority left at lock.
- **ARM B — the ground-radar wire (a new scenario, a crossing pass).** Aspect moves the detection
  state itself: the target is detected, LOST while still closing, and re-detected.

## §0.2 — ⚠⚠ THE PRE-REGISTERED KILL, AND IT IS THE SLICE-41 KILL IN NEW CLOTHES

**THE RISK, STATED BEFORE MEASURING IT.** Detection range goes as **σ^(1/4)** (`detection_range`,
rf.jl:135, off the R⁻⁴ link budget). So a **100× (20 dB)** reflectivity swing is only a **3.16×**
range swing, and a 40 dB swing only 10×. That fourth root is the whole hazard: if the target's aspect
is roughly CONSTANT over the ticks where the gate is deciding, then σ(θ) is a constant, and *a
constant σ is exactly what `rcs_m2` already is.* That is slice 41's death — **a new element is only
distinguishable from a retune by a wire that samples it at more than one operating point**
(`docs/LESSONS.md`, and slice 39 before it).

**THE ARITHMETIC, RUN BEFORE THE PROBE** (LESSONS: *"run the arithmetic premise before the code —
slice 37's P1 cost a calculator"*). On `slice48_search.yaml`, target→missile at launch is
`[−6000, −3000, −1200]`, |·| = 6814.7 m, and the target heading is `[0,−1,0]`:

- **aspect at launch = acos(3000/6814.7) = 63.9°**
- at ~t = 5 s (missile ~½ of the way down a closing LOS): **≈ 81°**
- at CPA: → 90°+

⇒ the engagement is flown **entirely in the broadside quarter, 64°→90°**, which is exactly where any
σ(θ) curve is FLATTEST. For a body-of-revolution ellipsoid the broadside-quarter σ ratio between 64°
and 81° is ~1.2×, i.e. **1.05× in range** — a few tens of metres of horizon, tens of milliseconds of
lock instant. Compare slice 48's own measured 60/65 °/s edge: **0.086 s**. ⭐ **The calculator says
ARM A is probably flat, and it says so before a kernel exists.**

**⚠ PRE-REGISTERED FALSIFIER FOR ARM A** (worded over a CURVE, not a point — slice 41's re-wording is
the reason this discipline exists): *ARM A DIES if a single constant `rcs_m2` reproduces the aspect
arm's authority-vs-slider curve to better than **3 %** across the slider's range.* Threshold fixed
here, in writing, before the measurement. Slice 41's precedent: falsifier 2.7–3.2 %, achieved
0.00–1.01 %.

**⚠ PRE-REGISTERED FALSIFIER FOR ARM B:** *ARM B DIES if the detection state is a MONOTONE function
of range* — i.e. if no constant σ can be beaten because the target never actually drops out. For a
constant-σ target, detection is monotone in range BY CONSTRUCTION (`r ≤ R_acq`, one threshold, one
range). Aspect is the only thing in this project that can break that monotonicity. **A drop-out at
DECREASING range is a state no constant σ can produce at any value**, which is why ARM B is the arm
that cannot be reparameterized away — and why the calculator above points at it.

---

## §0.3 — THE PRIMITIVE (gate 1), AND ITS NAMED APPROXIMATIONS

**PROPOSAL: the physical-optics ellipsoid, in `rf.jl`** — pure phenomenology, no RNG, no
LinearAlgebra, cross-domain (convention 12), and it is a textbook closed form rather than an invented
fudge:

```
σ(θ) = π a²b²c² / (a² sin²θ cos²φ + b² sin²θ sin²φ + c² cos²θ)²
```

For a body of revolution (radial semi-axis `r`, body semi-axis `L`) this collapses to two anchors a
test can check by hand, which is convention 11's EXTERNAL anchor:

- **nose-on (θ=0): σ = π r⁴ / L²** — 0.0079 m² for a 5 m × 0.5 m body
- **broadside (θ=90°): σ = π L²** — 78.5 m² for the same body
- ⇒ **~40 dB**, and the author sets it by choosing a SHAPE, not by choosing a number.

⭐ **Why this and not a three-lobe nose/broadside/tail interpolation:** the ellipsoid has no free
parameters to tune to taste — the RCS falls out of three lengths in metres, which is the teaching
point (*a long thin body is quiet nose-on BECAUSE it is long and thin*). A lobe interpolation would
let the author write any curve they like, which is a knob, not a model.

**NAMED APPROXIMATIONS, written down now so they are not discovered as bugs:**

1. **FORE/AFT SYMMETRY.** The ellipsoid gives σ(θ) ≡ σ(180°−θ): a fleeing target looks exactly like
   an approaching one. Real airframes have a distinct tail return (engine/exhaust). ⇒ a deferral,
   named here, not a defect.
2. **ASPECT COMES FROM THE TARGET'S VELOCITY DIRECTION, NOT ITS ATTITUDE.** Targets in this arc carry
   `vel` and no attitude quaternion. Nose = velocity direction. ⚠ Degenerate at `|vel| = 0` → clamp
   at the consumer (convention 5) and fall back to the scalar.
3. **⚠⚠ THE SIGN/FRAME TOOTH — the vector is TARGET→OBSERVER.** Nose-on means the observer is AHEAD
   of the target, so `cosθ = dot(unit(observer − target), unit(vel))`. Using observer→target silently
   swaps NOSE and TAIL — invisible under approximation 1's symmetry for a spheroid, and a wrong
   number the moment a tail lobe is ever added. **Pin 0° and 180° AND 90° against hand-computed
   anchors** (convention 11); this is the units/signs/frames trifecta and it gets an explicit test.
4. **THE COVERAGE GRID KEEPS THE SCALAR.** `batch.jl`'s `coverage_grid` is a range×altitude grid with
   no target entity and therefore no heading — aspect is UNDEFINED there. It keeps `rcs_m2`
   unchanged, said out loud here so a downstream test does not read as a regression.

## §0.4 — BYTE-IDENTITY (convention 2, the master check)

⚠⚠ **AN EARLY RETURN, NOT "THE FORMULA REDUCES TO THE SCALAR".** With the shape keys ABSENT, both
consumers must branch PAST the aspect math entirely and read `:rcs_m2` on the same line they read it
today — the shape `_det_on` and `ter === nothing` already use in this tree. An ellipsoid form that
*should* collapse to σ when the axes are equal will not be bit-exact, and byte-identity across 20+
slices of goldens is the master check.

✅ Checked before writing this plan: `grep -rn 'semi_ax|aspect|length_m|nose|broadside' scenarios/*.yaml`
hits nothing but prose comments — **no shipped scenario can silently activate the new path.**

---

## §1 — THE PROBES (gate 0), IN ORDER

| # | question | kills what |
|---|---|---|
| **P0** | On `slice48_search.yaml`, what is the aspect excursion over the PRE-LOCK ticks where the gate is deciding (`r_los` within [0.67, 1.5]× `r_acq`)? What lock-instant shift does the implied σ^(1/4) produce? | **ARM A**, and it is the selector between A and B. ⚠ Measure over the DECIDING ticks only — averaging over the whole 8.9 s flight will show a comfortable swing and mean nothing. |
| **P1** | On a ground-radar crossing pass: does an aspect target DROP OUT at decreasing range, and by how many ticks? | **ARM B.** If it never drops out, both arms are flat and the slice ships as component fidelity with a null result documented. |
| **P2** | The reparameterization test, on whichever arm P0/P1 selects: can one constant `rcs_m2` reproduce the arm's whole curve to <3 %? | The SLICE'S HEADLINE (not the component — the two-test rule). |
| **P3** | Byte-identity smoke: shape keys absent ⇒ every 26–48 golden unchanged. | The wiring, before it is written into a kernel. |

⚠ **P0 IS THE FIRST PROBE BECAUSE IT IS THE KILL RISK** (LESSONS: *"fly the kill risk before the
mechanism"*). No kernel is written until P0 and P1 have run.

---

## §2 — P0 HAS RUN (2026-08-26). ⚠⚠ IT REFUTES §0.2's OWN ARITHMETIC.

`M:\claud_projects\temp\slice49\p0_aspect.jl`, flown on `slice48_search.yaml` at three sweep rates.
The aspect angle is measured TARGET→OBSERVER against the target's velocity (§0.3 item 3's sign), and
the DECIDING window is `r_los ∈ [0.67, 1.5] × r_acq` and pre-lock, as pre-registered.

| ρ (°/s) | CPA (m) | t_lock (s) | aspect @ lock | DECIDING window | aspect over it | **EXCURSION** |
|---|---|---|---|---|---|---|
| 0 | 1039.880 | never | — | 10588 ticks, 2.958–18.000 s | 64.93 → 158.55° | 93.62° |
| 40 | 487.168 | 6.6410 | 85.82° | 3360 ticks, 2.958–6.317 s | 64.93 → 81.69° | **16.76°** |
| 240 | 0.311 | 5.2030 | 72.61° | 2245 ticks, 2.958–5.202 s | 64.93 → 72.61° | **7.68°** |

`r_acq` is **3038.2 m, flat**, against an `r_los` that walks 4557 → 2036 m. The gate is genuinely
deciding across the whole window (it is the *range* that crosses the horizon, not the horizon that
moves) — which is what makes this wire a fair place to ask the question.

**⚠⚠ THE PREDICTION IN §0.2 WAS WRONG, AND THE ERROR IS INSTRUCTIVE.** §0.2 estimated *"~1.2× in σ
over 64→81°, i.e. 1.05× in range"* by reasoning about a **sin² lobe**. The ellipsoid is not a sin²
lobe: its denominator is **squared**, so for a slender body the `L² cos²θ` term dominates until θ is
very close to broadside. Evaluated properly at fineness `F = L/r = 10`:

| θ | `(sin²θ + F² cos²θ)²` | σ relative to broadside |
|---|---|---|
| 65° | 349.0 | 1/349 |
| 72.6° | 9.853 → 97.08 | 1/97.08 |
| 82° | 8.512 | 1/8.512 |

⇒ over the ρ = 240 window (65 → 72.6°) σ moves **3.60×** ⇒ **1.38× in range**; over the ρ = 40 window
(65 → 82°) σ moves **41.00×** ⇒ **2.53× in range**. The horizon would move **3038 → 7688 m**.
**ARM A IS NOT FLAT.** ⭐ The transferable form: *a fourth-root law does not make a component
negligible if the quantity under it is raised to the fourth power on the way in* — the ellipsoid's
`^(1/4)` in range and `^2` in the denominator very nearly cancel, and the naive "σ^(1/4), so nothing
matters" reflex is the trap.

## §3 — THE PRIMITIVE IS REVISED (and it is better than §0.3's)

⚠ **§0.3's form as written cannot be authored onto this arc.** The raw ellipsoid fixes σ from the
axes alone: a 5 m × 0.5 m body gives σ_broadside = π L² = **78.5 m²**, which is **~4000×** the
0.020 m² `slice48_search.yaml` deliberately authors. Dropping it in would erase the blind phase that
slices 46/47/48 are built on. The arc's `rcs_m2` values are TUNING numbers for where the horizon
should sit, not physical measurements, and a model that overrides them is a model no existing
scenario can carry.

**REVISED: NORMALIZE THE ELLIPSOID TO BROADSIDE AND AUTHOR ITS SLENDERNESS.**

```
σ(θ) = rcs_m2 / (sin²θ + F² cos²θ)²        F = L/r, the FINENESS RATIO (dimensionless)
```

- `rcs_m2` keeps a meaning and gains a sharper one: **the broadside RCS** (θ = 90°), which is where
  every scenario in this arc already flies. Existing authored values keep their intent.
- **ONE new authorable number, `rcs_fineness`**, and it is physically named rather than fitted: how
  many times longer than wide the body is. `F = 1` is a sphere (aspect-independent); `F = 10` is
  **40 dB** nose-to-broadside, which is the right order for a real airframe.
- Nose-on σ = `rcs_m2 / F⁴` — a hand-checkable EXTERNAL anchor (convention 11), as are θ = 90° (σ ≡
  `rcs_m2`, exactly) and the F = 1 identity.
- ⚠ Byte-identity is still an EARLY RETURN on `rcs_fineness` absent (§0.4), NOT the `F = 1` identity —
  `(sin²θ + cos²θ)² = 1` is true in algebra and not in floating point.

## §4 — WHICH ARM, AND THE REMAINING KILL

P0 says ARM A is not flat, but **it does not say ARM A survives**, and the reason is §0.2's real
falsifier rather than its arithmetic. On the missile wire the aspect walks 65° → 90°, i.e. **σ only
ever RISES and the horizon only ever EXPANDS**, while the range only ever closes. Detection is a
single monotone crossing, and *a single monotone crossing can always be reproduced by some constant
σ that crosses at the same instant.* Whether ONE constant does it across the whole ρ slider is a
measurement (P2), not an assumption — but the shape of the wire is against it.

⭐⭐ **ARM B IS THE ARM THAT CANNOT BE REPARAMETERIZED, AND P0 SAYS WHY.** For a constant σ, detection
is a monotone function of RANGE alone, by construction (`r ≤ R_acq`: one threshold, one range). The
state no constant can produce at any value is **a drop-out at DECREASING range** — and aspect
produces it whenever the target turns its nose toward the observer while closing. That is not a
contrivance; it is the standard air-defence picture, and slice 12's `ManeuveringTarget` already
exists to fly it.

⇒ **P1 is now the load-bearing probe**: a ground radar, a target that turns from broadside onto an
inbound heading, and the question *does the radar lose it while it gets closer?*

---

## §5 — P1 HAS RUN. ⭐⭐⭐ ARM B LIVES, AND ITS FALSIFIER IS ANSWERED BY PROOF, NOT BY A THRESHOLD.

`M:\claud_projects\temp\slice49\p1_dropout.jl`. Slice 2's authored ground radar verbatim
(`RadarParams(50 kW, 35 dB, 9.4 GHz, 1 MHz, NF 3, L 4)`, `snr_min = 10 dB`) and the SHIPPED link
budget (`detection_range`, rf.jl). The target flies a **true broadside leg** at 30 km / 5 km alt,
then turns onto an inbound heading at 3 °/s — a rate-one turn, the standard air-defence picture.

⚠ **THE FIRST RUN'S GEOMETRY WAS WRONG AND ITS NULL MEANT NOTHING.** Heading was in the atan2
convention, so `hdg = 180` flew −x, not −y: the "broadside leg" was a 53° closing leg and the target
was never detected before it turned. **A probe that starts undetected cannot measure a drop-out.**
(LESSONS: a probe's control row is worth more than its result rows — here the CONTROL is what showed
the arms were being asked an empty question.)

| arm | drop-outs at DECREASING range | LOST at | REGAINED at | **blind stretch while closing** |
|---|---|---|---|---|
| **CONTROL, F = 1 (sphere)** | **0** — detected on **2401/2401** ticks, ZERO transitions | — | — | **none** |
| F = 3 (19 dB nose-on) | **1** | 30 335 m, t = 33.9 s | 16 527 m, t = 95.3 s | **13.8 km / 61.4 s** |
| F = 6 (31 dB) | **1** | 30 775 m, t = 28.4 s | 9 331 m, t = 126.8 s | **21.4 km / 98.4 s** |
| F = 10 (40 dB) | **1** | 30 852 m, t = 26.5 s | 6 881 m, t = 139.4 s | **24.0 km / 112.9 s** |

⚠ F = 10's extra transitions at t = 185/192 s are **post-CPA re-crossings at OPENING range** and are
excluded by the probe's own closing test — the hazard `docs/LESSONS.md` records from slice 48 (*"a
range gate is not enough on its own — the post-CPA re-crossing comes back through it from the far
side"*), handled here rather than discovered later.

**⭐⭐⭐ THE ARM-B FALSIFIER IS DISCHARGED BY A PROOF, WHICH IS STRONGER THAN THE 3 % THRESHOLD §0.2
PRE-REGISTERED.** For a constant σ, `R_acq` is a constant, so detection is `r ≤ const`; and `r` is
monotone decreasing until CPA. ⇒ **a constant-σ target can only ever be GAINED, never LOST, while
closing — at any value of σ whatsoever.** This is not a fit that came out below a threshold; it is a
state the constant-σ model cannot reach. The CONTROL row measures the same thing empirically: 2401
ticks, zero transitions. ⇒ **the slice-39/41 reparameterization kill does not apply to ARM B**, and
that is the strongest form of that answer this project has yet produced.

**⭐⭐ SECOND FINDING, NOT THE HEADLINE BUT WORTH AUTHORING: THE BROADSIDE PEAK IS A FLASH, NOT A
PLATEAU.** At F = 10, **6.9° past broadside** (96.89°) σ is already **0.680 m² against a 4.0 m²
peak — 7.7 dB down**. The slenderer the body, the narrower the flash. That is why the F = 10 arm
chatters across the threshold at t = 14.7/21.1/26.5 s: it is sitting ON the horizon while the flash
narrows under it. ⚠ For the showcase, start the leg comfortably INSIDE the broadside horizon so the
one drop-out that carries the lesson is unambiguous.

## §6 — THE VERDICT SO FAR, AND WHAT GATE 1 BUILDS

- **MODEL test:** passes by construction — `rcs_fineness` is read every tick by both consumers off
  one primitive (§0 fact 1), in its own units (dimensionless), with the sign pinned by §0.3 item 3.
- **LESSON test:** **PASSES on ARM B.** The blind stretch is **monotone in F** (13.8 → 21.4 → 24.0 km)
  and the null (F = 1) is a true null — a sphere never disappears.
- **THE SLIDER IS `rcs_fineness`**, floor F = 1 (sphere — bit-identical to a wire with no aspect
  model at all, once §0.4's early return is in), ceiling ~F = 12.
- **THE GAUGE IS THE BLIND STRETCH** (range and seconds lost while closing) — ⚠ NOT the miss (§0.1),
  and not a detection percentage, which mixes the outbound leg back in.

**HEADLINE, PROVISIONAL:** *⭐⭐⭐ A TARGET THAT TURNS ITS NOSE TOWARD THE RADAR DISAPPEARS WHILE IT IS
STILL CLOSING — and no single reflectivity number can make that happen, because a constant echo can
only ever be gained on an approach, never lost.*

⚠ **ARM A (the missile wire) is NOT killed and is NOT the showcase.** P0 measured it non-flat (§2),
but its aspect walks only toward broadside, so its detection is a single monotone crossing that some
constant σ reproduces. It ships as WIRING (both consumers, §0 fact 1) with its null documented — the
component-fidelity shape `docs/DEFERRALS.md` legalized on 2026-08-18.

## §7 — ⚠⚠ A BLOCKER FOUND IN THE TREE: THE SHIPPED TARGET CANNOT TURN HORIZONTALLY

`missile.jl:998` — `_lateral_accel(v, a_lat, sign)` returns `(a_lat·sign/s)·Vec3(−vz, 0, vx)`.
**The `y` component is structurally zero: `ManeuveringTarget` turns ONLY in the x–z (vertical)
plane**, and its own docstring says so (*"a coordinated g-turn in the x-z plane"*, slice 12's
augmented-PN foil). ⚠ `scenario.jl:157` additionally REFUSES `cross_speed_mps` alongside a
`maneuver:` block, for the slice-19 dead-knob reason.

**WHY THIS BLOCKS THE SHOWCASE, AND WHY NO GEOMETRY TRICK GETS AROUND IT.** First establish that the
manoeuvre is REQUIRED, not a convenience: for a target flying STRAIGHT past a radar, the aspect is
monotone 0° → 90° up to CPA and 90° → 180° after, while the range is monotone down then up. **σ
therefore rises exactly while the range falls and falls exactly while the range rises — the two
effects are aligned on both legs, so a straight-flying target can never drop out while closing at any
fineness.** The turn is the mechanism, not the staging.

The options, and what each costs:

1. **⭐ ADD AN AUTHORABLE TURN PLANE to `ManeuveringTarget`** — a `maneuver.turn_plane` key whose
   absence keeps `Vec3(−vz, 0, vx)` on the same line it is on today (byte-identical to slices 1–48 by
   early return, §0.4's shape) and whose `horizontal` value gives `Vec3(−vy, vx, 0)`. ~10 lines, one
   loader key, one test. ⚠ It is a change to shipped physics and needs its own byte-identity tooth,
   but the change is UNREACHABLE without the new key.
2. **Contort the geometry into the x–z plane** — e.g. a target at 30 km altitude diving onto the
   radar. It flies, and it is a wrong picture: no air target manoeuvres like that, and the slice's
   whole claim is that this is *the standard air-defence geometry*. ⚠ Rejected — a showcase that
   teaches a geometry no one flies is worse than no showcase.
3. **Author the turn as a scripted waypoint mover** — a new subsystem, which is a second lesson and
   convention 9's prohibition. Rejected.

⇒ **RECOMMENDATION: option 1.** It is enabling PLUMBING for this slice's lesson rather than a lesson
of its own, it is the smallest change that makes the real geometry authorable, and it removes a
restriction slice 12 named as an approximation rather than defended as physics. ⚠ It must be called
out in the gate-2 record as *this slice's one edit to shipped physics*, with the byte-identity tooth
naming slices 12/30 explicitly.

---

## §8 — ⚠⚠⚠ P1 PROBED THE WRONG CODE PATH. §5's PROOF DOES NOT APPLY TO THE GROUND RADAR.

**FOUND (advisor, 2026-08-26), and it invalidates §5's central claim as worded.** §5 argued *"for a
constant σ, detection is `r ≤ R_acq`, one threshold, one range, so a constant-σ target can only ever
be GAINED while closing."* **That is the MISSILE SEEKER's gate** (`missile.jl:2636`, whose own comment
says *"DETERMINISTIC — a hard threshold, NO `Pd` draw"*). **It is not the ground radar's.**

`radar.jl:543` — the shipped decision is

```julia
if is_look && detect_once(snr_eff, th, w.rng; swerling = sw, n_pulses = np)
```

⇒ **the ground radar's detection is a STOCHASTIC DRAW** against a `pfa`-derived threshold with
Swerling fluctuation, taken **per LOOK** at `revisit_s` (10 Hz on slice 2's block), not per tick.
`p1_dropout.jl` used `r ≤ detection_range(...)` — a hard threshold that path does not contain.

⚠⚠ **AND THE CONTROL ROW COULD NOT HAVE CAUGHT IT.** F = 1 scored 2401/2401 because the code path the
probe used has **no draw in it at all**, so the instrument was structurally incapable of flickering.
`docs/LESSONS.md` names this twice: *"a test whose control passes is not a test"*, and *"when a probe
reached its numbers by a different code path, prove the paths agree before quoting its tables."*
⇒ **§5's table is PROBE-ONLY and must not be quoted as a wire measurement.** Its shape is a
hypothesis; its numbers are not inherited (slice 48's §0.2 discipline, applied to my own probe).

**WHAT SURVIVES, AND WHAT THE CLAIM BECOMES.** A constant-σ target sitting at marginal SNR *does*
flicker on the real path — brief losses, at the horizon, from the draw. So "no constant can be lost
while closing" is **FALSE on the radar wire**. What replaces it is a **DEPTH-AND-DURATION** claim,
and it is still a claim no constant σ can meet: *a constant target's losses are threshold CHATTER —
short, and only where `r ≈ R_acq`; an aspect target's loss is SUSTAINED and DEEP INSIDE the horizon.*
⚠ That needs the constant-σ control **re-flown on the real path** to establish what chatter actually
looks like there. That is P1b, and it is now the load-bearing probe.

**⭐ THE PROOF IS NOT LOST — IT MOVED.** The seeker's gate IS deterministic, so *"no constant σ can be
lost while closing"* holds EXACTLY against a **missile seeker vs a turning target**. That is a live
alternative showcase, not a retreat. ⚠ It is NOT preferred, for a reason outside the physics: a
mid-flight detection break on the missile arc lands on slice 37's territory (*a break here is not an
episode but the rest of the flight*), whose cure is DEAD as a lesson, and this slice must not
re-import that framing. **The ground radar keeps the showcase; the seeker keeps the wiring.**

**⭐⭐ ONE CONVENTION-3 CLEARANCE, BANKED WHILE LOOKING (and it is the hazard that would have killed
the slice at gate 2).** Aspect changes `snr_eff`, and `snr_eff` feeds a `w.rng` draw — the exact shape
that flips a draw topology. It does **not** here: `radar.jl:532`'s own comment states *"the draw COUNT
(detect_once stays unconditional — same randn count regardless of SNR)"*. ⇒ **aspect-dependent σ is
draw-COUNT invariant on the radar path by construction** — convention 3 satisfied without a redesign.
⚠ Re-check this against the `:cfar` rung before gate 2 (`radar.jl:467`: `2·N_p·N_cells` vs `2·N_p`);
`:cfar` is class-(b) already and the count must stay invariant *within* each rung, not across them.

---

## §9 — ⭐⭐⭐ P1b: RE-FLOWN ON THE SHIPPED DETECTOR. THE CLAIM SURVIVES, AND IT IS STRONGER FOR HAVING A REAL CONTROL.

`M:\claud_projects\temp\slice49\p1b_wire.jl`. **The DETECTOR is the wire's** — `slice2_tworay.yaml`'s
radar entity, the real `RadarSensor` subsystem, the real `w.rng`, the real `detect_once` /
`pd_analytic` / Swerling-1 / `pfa = 1e-6`, the real 10 Hz `revisit_s` look cadence. **The KINEMATICS
are the probe's**, because §7's turn is not authorable yet; the target's phase-1 mover is removed
from the subsystem list so nothing double-integrates. ⚠ `propagation` forced to `:free_space` so
slice 2's 4/3-Earth horizon mask cannot be confused with an aspect drop-out — two mechanisms, one
readout. Broadside leg at 25 km / 5 km alt, 250 m/s, turning inbound at 3 °/s from t = 20 s.

**GAUGE: the LONGEST contiguous loss run that occurs while the range is CLOSING**, counted only after
the target has been detected at least once.

| arm | loss runs while closing | **LONGEST loss** | over a range of |
|---|---|---|---|
| **CONTROL, F = 1 (sphere, σ ≡ 4.0 m²)** | 41 | **0.20 s** | **0.0 km** |
| F = 3 (19 dB) | 133 | **5.60 s** | 1.4 km (20 890 → 19 533 m) |
| F = 6 (31 dB) | 53 | **64.10 s** | 13.9 km (25 732 → 11 880 m) |
| F = 10 (40 dB) | 42 | **85.30 s** | 17.9 km (25 963 → 8 056 m) |

⭐⭐⭐ **THE SEPARATION IS 427×, AND THE CONTROL IS NOW A REAL ONE.** The constant-σ target DOES get
lost while closing — 41 times — exactly as §8 predicted, and every one of those losses is **two ticks
of a 10 Hz look cadence or less**. That is Swerling-1 fading, not a horizon effect: at 25 km a 4 m²
target sits ~21 dB above this radar's threshold and still fades below it occasionally, because a
Swerling-1 echo is exponentially distributed. ⇒ **the chatter is CORRECT PHYSICS and it is bounded at
0.2 s**, while the aspect arms reach **85 s**. No draw-statistics explanation reaches that.

⇒ **THE ARM-B FALSIFIER IS DISCHARGED ON THE REAL PATH.** §5's proof-form is retired; what replaces
it is measured, with a control that could and did flicker: *a constant echo is lost for fractions of
a second; a turning slender target is lost for a minute and a half, seventeen kilometres deep inside
a horizon it was comfortably within.*

**⚠⚠ THE GAUGE IS THE LONGEST RUN — AND THE RUN COUNT IS NON-MONOTONE, WHICH WOULD HAVE DISQUALIFIED
IT** (the `k` (28) / `ω_n` (40) / `σ_seek` (25) precedent). The count goes **41 → 133 → 53 → 42**: at
F = 3 the target hovers AT the threshold and chatters constantly, while at F = 6/10 it drops out hard
and stays out, so *more slenderness gives fewer losses*. The DURATION is monotone (0.20 → 5.60 →
64.10 → 85.30 s) and so is the range depth (0.0 → 1.4 → 13.9 → 17.9 km). ⚠ A "detected %" gauge fails
the same way and additionally mixes the outbound leg back in. **Never quote the count.**

## §10 — GATE 0 IS CLOSED. THE SLICE LIVES.

| pre-registered probe (§1) | verdict |
|---|---|
| **P0** — does aspect swing where the gate decides? | **RAN.** Yes, but §0.2's own arithmetic was wrong in the optimistic direction (§2). ARM A non-flat, and NOT the showcase (§6). |
| **P1** — does a target drop out at decreasing range? | **RAN, WRONG PATH, RETIRED** (§8). Probe-only; not quotable. |
| **P1b** — the same on the shipped detector | **RAN. ARM B LIVES** (§9), 0.20 s control against 85.30 s. |
| **P2** — reparameterization | **ANSWERED BY P1b's CONTROL.** A constant `rcs_m2` at ANY value produces at most 0.20 s of loss on this wire; the model produces 85.30 s. There is no constant to retune to. |
| **P3** — byte-identity | **DEFERRED TO GATE 1** — it is an implementation tooth (§0.4's early return), not a question about the physics. |

- **MODEL test: PASSES** — `rcs_fineness` read every tick by both consumers off one primitive.
- **LESSON test: PASSES** — the gauge is monotone in the slider and the null is a true null.
- **SLIDER:** `rcs_fineness`, floor 1.0 (sphere), ceiling ~12.
- **GAUGE:** longest loss run while closing (seconds, and km of range). ⚠ NOT the count, NOT a
  detected-%, NOT the miss.

⭐⭐⭐ **HEADLINE:** *A TARGET THAT TURNS ITS NOSE TOWARD THE RADAR DISAPPEARS WHILE IT IS STILL
CLOSING — for a minute and a half, seventeen kilometres inside a horizon it was comfortably within —
and no single reflectivity number can imitate it: a steady echo of any size flickers for two tenths
of a second and no longer.*

**GATE 1 BUILDS:** `rcs_aspect` in `rf.jl` (§3's normalized ellipsoid, with the θ = 90° / nose-on /
F = 1 hand anchors), the aspect angle helper with §0.3 item 3's target→observer sign pinned at 0/90/
180°, and the `turn_plane` extension to `ManeuveringTarget` (§7 option 1) with its byte-identity
tooth and `scenario.jl:157`'s now-stale error message corrected in the same commit.

---

## §11 — GATE 1 SHIPPED (2026-08-26). Suite **17159** (was 16154, +1005).

Three pure kernels and their teeth. `core/test/test_rcs_aspect.jl`, registered in `runtests.jl`
after `test_search.jl`.

| what | where | anchors |
|---|---|---|
| `rcs_aspect(σ_broadside, F, θ)` | `rf.jl` | broadside EXACT at every F (`==`, atol 0); nose/tail `σ/F⁴` hand-computed; sphere aspect-independent; **and an INDEPENDENT oracle** — the raw ellipsoid `π a²b²c²/(…)²` from real semi-axes, agreeing to `rtol 1e-12` over 73 angles at two different shapes |
| `aspect_angle(tgt_pos, tgt_vel, obs_pos)` | `frames.jl` | 0 / π/2 / π on hand-built geometries, both abeam sides, out of plane, the 45° quarter, **and P0's own 63.8823° off `slice48_search.yaml`** |
| `_lateral_accel(v, a, sign, plane)` | `missile.jl` | ⭐ **the byte-identity tooth** |
| `TARGET_TURN_PLANES` | `dynamics.jl` | convention 7 — one list, `:vertical` first and pinned first |

**⭐ THE BYTE-IDENTITY TOOTH, AND IT IS THE ONE THAT WOULD HAVE KILLED THE SLICE AT GATE 2.** Over
three velocities × three accelerations × both signs, the default arm and the explicit `:vertical`
arm are asserted `==` — **atol 0, not a tolerance** — against the two-argument expression slices
12–48 flew, recomputed inline in the test. The `:horizontal` arm is checked to be the x–y sibling,
to be ⟂ to velocity **by an independent dot product** rather than by re-deriving the perpendicular,
to have magnitude `a`, and to never touch z (while `:vertical` never touches y). Both zero-guards
are pinned on both planes. ⇒ the full suite, `test_determinism.jl` and the ABSOLUTE golden included,
passes unchanged — slices 1–48 are untouched.

**⚠ MY HAND ARITHMETIC WAS WRONG A SECOND TIME, AND THE TEST CAUGHT IT.** §2 recorded the 65°→82°
σ ratio as **40.1×**; the true value is **41.00×** (the draft mis-squared cos 82°). §2's table and
the range figure are corrected (2.53×, horizon 3038 → 7688 m) and the test now pins 41.00 at
atol 0.05. ⭐ **The CLAIM never moved** — an order of magnitude over seventeen degrees, where the
sin²-lobe reasoning that produced the original kill prediction gives ~1.2×. ⭐⭐ **The transferable
part: this is the SECOND arithmetic slip in the same three-line calculation, and both times the slip
was in the same direction — toward the answer that would have killed the slice.** A number that
decides a headline gets a test, not a calculator.

**TWO DESIGN DECISIONS PINNED AS TESTS, so a later slice cannot quietly reverse them:**
- **A degenerate target reduces to the SCALAR model, not to a NaN.** No velocity ⇒ no nose ⇒
  `aspect_angle` returns π/2 ⇒ `rcs_aspect` returns the AUTHORED `rcs_m2`, exactly (`==`).
  Convention 6, and it means a stationary or coincident entity is quietly correct rather than
  quietly poisoned.
- **`F < 1` is LEGAL, not an error** — an oblate body, wider than long, brighter nose-on than
  broadside. Pinned with its inequality. Only `F ≤ 0` and `σ ≤ 0` throw, the `detection_range`
  posture (clamp at the CONSUMER, convention 5).

**GATE 2 WIRES:** `rcs_fineness` through the loader onto the target comp; the effective σ read off
`rcs_aspect(rcs_m2, F, aspect_angle(tgt.pos, tgt.vel, obs.pos))` at BOTH consumers off the one
primitive (`radar.jl:290` and `missile.jl:2627` — §0 fact 1, and the seeker-side-copy prohibition
that comment already carries); `maneuver.turn_plane` validated at load against `TARGET_TURN_PLANES`;
and ⚠ `scenario.jl:157`'s `cross_speed_mps` refusal message, whose stated reason (*"whose lateral
accel is in-plane by construction"*) the turn plane makes stale even though the guard itself still
stands. ⚠ Re-check convention 3's draw-count invariance on the `:cfar` rung (§8's clearance covers
the `:snr` path only).

---

## §12 — GATE 2 SHIPPED (2026-08-26). Suite **17214** (+55 over gate 1).

**ONE SITE.** `_effective_rcs(tgt::Entity, obs_pos::Vec3)` in `radar.jl` is the only place in the
project where a shape becomes a cross-section. `radar.jl`'s `_target_snr` and the seeker's detection
horizon (`missile.jl`) BOTH call it — because `missile.jl:2624`'s standing comment already says a
seeker-side RCS copy *"would give one target two RCS numbers that can silently disagree"*, and an
aspect model applied at one consumer and not the other is that failure one level up. It lives in
`radar.jl` rather than a §9 pure lib because it consumes an `Entity`; the physics it calls
(`rcs_aspect`, `aspect_angle`) is pure and lives in `rf.jl` / `frames.jl`.

| what | where |
|---|---|
| `rcs_fineness` on the `target:` block, validated finite and > 0 | `scenario.jl` |
| `maneuver.turn_plane`, validated against `TARGET_TURN_PLANES` | `scenario.jl` |
| `radar1.target_aspect_deg`, `radar1.rcs_eff_m2` (key-presence gated) | `radar.jl` |
| `m1.target_aspect_deg`, `m1.rcs_eff_m2` (key-presence gated) | `missile.jl` |

**⭐⭐ THE TOOTH THAT MATTERS: TWO OBSERVERS, ONE TARGET, TWO CROSS-SECTIONS.** Every equal-value
check also passes if aspect were a property stamped on the target once per tick — the slice-30
lesson one arc over (*only a DISAGREEING pair separates the orders*). So an observer abeam and an
observer dead ahead are read off the SAME comp bag at the SAME instant and must differ by **10⁴** at
F = 10. That is the tooth no single-observer test can supply, and it is why the seeker gets
`e.pos` and the radar gets `radar.pos` rather than either reading a stored number.

**BYTE-IDENTITY, THREE WAYS.** (a) With `:rcs_fineness` absent, `_effective_rcs` returns
`comp[:rcs_m2]` — asserted `===`, the authored object itself, at four geometries. (b) Through the
whole `ManeuveringTarget` mover, plane-absent ≡ `:vertical` over **20 000 ticks of pos AND vel,
`==` on the full trace**, paired against a `:horizontal` arm that differs. (c) The full suite,
`test_determinism.jl` and the ABSOLUTE golden included, unchanged.

⚠ **A FIRST DRAFT OF THE "PAIRED" ARM WAS VACUOUS AND THE SUITE CAUGHT IT.** It compared the aspect
value against the authored one at the fixture's default geometry — which is exactly ABEAM, where σ
legitimately EQUALS `rcs_m2` at every fineness. It read as *"the branch did not fire"*. ⭐ The
transferable form: **a not-equal tooth needs its geometry chosen as carefully as an equal one** — an
off-broadside observer is what makes it a test.

**THE STALE GUARD IS FIXED IN THE SAME COMMIT.** `scenario.jl`'s refusal of `cross_speed_mps`
alongside a `maneuver:` block used to justify itself with *"whose lateral accel is in-plane by
construction"* — which `turn_plane` makes false. The verdict is unchanged and the reason is
rewritten to the one that never depended on the plane (the pin lives in `ConstantVelocity`, which a
maneuver block replaces, so nothing would read the key). ⚠ A guard whose stated reason has rotted is
how a later slice re-imports a killed framing.

**TWO DEGENERATE POLICIES, PINNED:** a live `set_param` can write `rcs_fineness ≤ 0` straight to the
comp bag where the loader cannot see it, and `rcs_aspect` throws by design — so the CONSUMER floors
it and the tick survives (convention 5), shipping a huge-but-finite σ (convention 6). And the
telemetry keys are ABSENT on a scalar wire rather than present-and-zero, which is CLAUDE.md's
`.get(k, 0.0)` trap.

---

## §13 — GATE 3, CORE HALF (2026-08-26). Suite **17249** (+35). ⚠ The Godot half is still open.

`scenarios/slice49_aspect.yaml`, the `aspect_view` marker (`radar.jl` + `server.jl`), and the
gate-3 testset. **⚠ P1b's numbers did NOT survive to the ship, and that is the expected outcome, not
a problem.** P1b steered the heading toward the radar and STOPPED — a guidance law. The shipped
`ManeuveringTarget` applies a CONSTANT lateral accel, so the target flies a CIRCLE and keeps turning
THROUGH nose-on. The geometry was therefore re-measured on the shipped mover (P4) and then again
through `load_scenario` on the file that ships (P5), which is convention 10 in its plainest form.

**THE GEOMETRY, AND THE ONE CONSTRAINT THAT SETS IT.** On a circle of turn radius `R_t` entered
broadside at range `R0`, the closest approach to the radar is **`R0 − 2·R_t`**. So the turn radius
sets BOTH how fast the nose comes round AND how close the target ever gets — a lazier turn is a
target that never closes at all (it orbits at its start range, and there is no lesson). Shipped:
`R0` = 18 km, 300 m/s, `R_t` = 6 km (`a_lat` = 15 m/s², 1.53 g), CPA ≈ 7.8 km.

**THE LADDER, FLOWN THROUGH THE LOADER (90 s), longest loss run while CLOSING:**

| `rcs_fineness` | 1.0 (sphere) | 2.0 | 4.0 | 6.0 | **8.0 (authored)** | 10.0 | 12.0 |
|---|---|---|---|---|---|---|---|
| **loss (s)** | 0.20 | 0.20 | 1.30 | 5.30 | **36.50** | 40.20 | 46.60 |
| range given up | 0.0 km | 0.0 km | 0.4 km | 1.4 km | **8.3 km** | 9.1 km | 9.8 km |
| detected | 99.2 % | 96.0 % | 68.0 % | 40.7 % | **29.1 %** | 22.9 % | 18.1 % |

**Monotone in both columns.** ⭐ And the key REMOVED entirely reads **0.20 s / 99.2 %** — identical
to the sphere to the digit, which is the null being a real null. ⚠ Identical NUMBER, different CODE
PATH; that distinction is gate 2's `===` tooth and must not be collapsed.

⭐⭐ **THE SPHERE CONTROL IS THE TOOTH, AND SWERLING 1 IS WHAT MAKES IT ONE.** The control is lost
41 separate times — a 4 m² target ~21 dB above threshold still fades below it occasionally, because
a Swerling-1 echo is exponentially distributed. What it cannot do is STAY lost. ⚠⚠ **`swerling: 1`
in the scenario is LOAD-BEARING and must not be tidied to a non-fluctuating detector**: that would
hand the sphere a perfect 100 % and turn the slice's central comparison into a tautology — a test
whose control cannot fail.

**THE VIEW MARKER'S HOLE CHECK COMES BACK POSITIVE.** Without `aspect_view`, a slice-49 wire is a
slice-2 wire to the client: it would draw the two-ray propagation view and offer a
`free_space ↔ two_ray` button — **a lesson about MULTIPATH LOBING on a scenario whose target
vanishes for a completely different reason**, and the drop-out would read as a propagation null.
The marker carries `aspect_target` and `aspect_observer` because an aspect belongs to a
target–observer PAIR; a HUD reading "aspect 25°" with no subject is this family's ~13th stale
readout. ⚠ Gated on the COMP KEY, not a fidelity — there is deliberately no `aspect` rung, because
"no aspect at all" is reachable from the slider's own floor (a sphere), and a rung would duplicate a
slider position (slice 47/48's settled decision).

**⚠ STILL OPEN — THE FOUR PROOFS (convention 14).** `net/slice49_verify.gd`, `net/slice49_ui_test.gd`,
the headless smoke-load and the windowed shot, plus the client's aspect HUD branch. ⚠ `STEPS` must
be a multiple of `emit_every` = 16 (pinned as a test here so an edit to either breaks in the core
first), and anything computed inside `_draw` has NO headless proof.
