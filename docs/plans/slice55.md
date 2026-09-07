# Slice 55 — THE WINDOW'S SHAPE, NOW THAT THE WINDOW COSTS SOMETHING

**A FAN BEAM: spend the aperture on the axis the search actually sweeps.**

Status: **PLAN + GATE 0 PRE-REGISTRATION.** No code shipped at the time of writing.
Scratch: `W:\temp\claude\slice55\`. Probe code is run through `& tools/julia.ps1`, never `julia -e`.

---

## §0 PROVENANCE — THIS IS NOT SLICE 45 PRODUCTIONIZED, AND SAYING SO IS THE FIRST FINDING

`docs/DEFERRALS.md` §"THE BUILD LIST" files **a rectangular / per-axis window and stop** (45) as
**TIER 1, `REGIME`, textbook**, and prices it as *"productionize `M:\claud_projects\temp\slice45`
— wire, test, author"*. ⚠⚠ **That price was written from the ledger rather than from the code, which
is exactly the shelf life slice 54 put a standing lesson on** (`docs/DEFERRALS.md` §"Slice 54 —
DISCHARGED, AND THE ENTRY'S OWN BLOCKER WAS STALE"). Re-read at HEAD on 2026-09-07, **three of the
entry's load-bearing sentences have expired**:

1. **Slice 45's own verdict was *"nothing ships, because the only arm where the shape matters lives
   inside a feature that has not been built."*** That feature is the SEARCH, and it **shipped —
   slice 48, with its width in slice 52** (`scenarios/slice48_search.yaml`). The precondition the
   45 record wrote as a blocker is a shipped wire with a shipped slider.
2. **Slice 45's §IV concluded *"a cost claim needs a cost model this simulator does not have."***
   It has one: **slice 46 shipped `R_acq · fov = constant`** — the detector window IS the beamwidth,
   the beamwidth implies the aperture, the aperture is the gain, the gain is the reach
   (`core/src/rf.jl` §"slice 46: THE APERTURE AND THE HORIZON"; the coupling is built at
   `core/src/missile.jl:2739–2745`). **The exact model slice 45 said was absent is now the thing
   every seeker on this arc flies through.**
3. **The build list's *"byte-identical to the disc on 8/9 TRACKING rows"* is STALE.** It was measured
   on 2026-08-18, before the window set the horizon. At HEAD with `seeker_detect: :snr`, a box
   `(10°, 1.9°)` and a disc `10°` have **different gains ⇒ different horizons ⇒ different flights,
   tracking or not.** The claim survives only in a corrected form (§0.4 P1).

⇒ **This is a new slice that slice 45's tables FEED, not a slice 45 revival.** The ruling in
`docs/PROHIBITIONS.md` §1 (*"DEAD AS A LESSON, ALIVE AS A MODEL, both halves"*) is untouched: what
died there was the 2026-08-18 HEADLINE, and this slice does not re-file it — it asks a question that
could not be asked before slice 46 existed.

⚠ **`M:\claud_projects\temp\slice45\patch45.py` IS NOT USED IN EITHER DIRECTION.** Its `apply`
anchor (`if off_axis_angle(head_az, head_el, look_az_b, look_el_b) ≤ fov_h` on one line) has **0
matches at HEAD** — the predicate has since been reformatted across two lines at
`core/src/missile.jl:2483` and `:2515` and composed with slice 47/48's cue and search bypasses. Worse,
its `revert` copies an **2026-08-18 snapshot of `missile.jl` over the live file**, which would erase
slices 52/53/54 and the 2026-09-06 ρ(z) fix. **Gate 0 flies against real gate-1 code behind a
key-presence anchor**, never a throwaway patch.

### §0.0 THE STOP HALF IS OUT OF SCOPE, DELIBERATELY

The build list bundles *"window **and stop**"* because slice 45 probed both. **This slice ships the
WINDOW only.**

* The stop half is **DEAD** on its own measurement and the number is not marginal: with the azimuth
  stop at 30°, the miss is **0.1912 m at every elevation stop from 0.04° to 30° — a 750× range** —
  even where the clamp binds **66.66 %** of in-band ticks. Box stop and disc stop give identical
  verdicts on every rung 30° → 8.2° and both fail at 8.1° with the same **3620.6755**.
* It carries a real trap for that zero lesson: `core/src/frames.jl` names it by name — *"a per-axis
  clamp would let the head sit at `√2·stop` while the readout compared against `stop`"* — measured
  **1.003×** at slice 45's gate 0.
* It is a **separate mechanism** (an azimuth ring and an elevation trunnion) from the detector's
  glass, and convention 9 says one lesson per scenario.

⇒ Recorded here so the build list's bundling is not read as scope. If the stop is ever built it is
its own slice, and it opens with that 750× null.

---

## §0.1 THE PRE-REGISTERED RULES — WRITTEN BEFORE ANY PROBE RUNS

⚠⚠ Slice 53's discipline: **declare the selection rule before the flights and publish the losers.**
Slice 54's: **a pre-registered rule earns authority the first time it REFUSES something.** Everything
in this section is fixed before a single probe is written.

### §0.1.1 THE CONTROL — and there are three candidates, only one of which the shipped code implies

`docs/PROHIBITIONS.md` §1: **"Never quote the box's rescue without its control."** Slice 45's own
pre-registered objection fired against it — *a disc **0.7 % wider** (10.07°) rescues the same cell* —
so at matched half-width the box's rescue is slice 42/43's *"a wider window is free."* Its rebuttal
was **held cost**, and it named three ways to spend a box `(a, b)`'s budget as a disc of radius `r`:

| control | `r` for `(10.00°, 1.90°)` | what defines it | is there a consumer? |
|---|---|---|---|
| **sum-matched** | `r = (a+b)/2` = **5.95** | a geometric analogy | **no** |
| **area-matched** | `r = 2√(ab/π)` = **4.92** | the window's solid angle as a plane figure | **no** |
| ⭐ **gain-matched** | `r = √(ab)` = **4.36** | `aperture_gain`'s own `Ω = θ_az·θ_el` — the link budget | **YES** |

> ⭐⭐⭐ **THE RULING CONTROL IS THE GAIN-MATCHED DISC, `r = √(ab)`, AND THE REASON IS THAT IT IS THE
> ONLY ONE WITH A CONSUMER.** `core/src/rf.jl`'s `aperture_gain` defines the budget as `G = η·4π/Ω`.
> Two windows cost the same iff they subtend the same `Ω`, and `Ω = θ_az·θ_el` ⇒ `r = √(ab)`. Sum-
> and area-matching are geometric analogies that nothing in the simulator reads.

⚠⚠ **AND IT IS THE HARDEST-TO-BEAT CONTROL OF THE THREE**, which is why declaring it in advance
matters: `√(ab) = 4.36 < 4.92 < 5.95`, so the gain-matched disc has the LEAST azimuth coverage and is
the arm most favourable to the box. **All three are flown and all three are published** — but the
verdict is read off the gain-matched row, and if the box beats only the other two the headline is
dead.

**THE BOX MUST BEAT TWO DIFFERENT DISCS FOR TWO DIFFERENT STATED REASONS, or there is no RIVAL:**

* **against the gain-matched disc `√(ab)`** — same reach, and the box has **more azimuth coverage**;
* **against the equal-azimuth disc `a`** — same azimuth coverage, and the box has **longer reach**
  (`R_acq` ratio `√(a/b)` = **2.29×** at `(10, 1.9)`).

If either comparison fails, **the fan beam is a free lunch wearing a rectangle** and the slice has no
headline.

### §0.1.2 THE FALSIFIER — slice 42's standing rule, applied to slice 45's brackets

Slice 45's central numbers are **threshold brackets**: the sweep-rate floor `ρ*` is `(1.01, 1.02]`
with a disc and `(0.92, 0.93]` with a box — **an 8.8 % gap**. `docs/PROHIBITIONS.md` §1 on the
acquisition knife-edge: *a finding whose SIZE is set by the integrator's step cannot be a lesson
about hardware — **re-fly a narrow threshold at half `dt`.***

> **PRE-REGISTERED FALSIFIER F1.** Re-fly the `ρ*` brackets at `dt` = 1e−3 **and** 5e−4. **If the
> disc/box gap narrows by more than 25 % when the step halves, the effect is an integration artifact
> and this slice's headline is DEAD**, whatever the 1e−3 table says. A gap that is *stable* under
> the halving is hardware; a gap that *halves* with the step is `ω·dt` again.

> **PRE-REGISTERED FALSIFIER F2 — THE FREE LUNCH.** On the shipped gate-3 wire the elevation slider
> must **REVERSE**: narrowing the unswept axis must eventually LOSE the target. **If the metric is
> monotone-better all the way to the floor of the slider's domain, the box is a free lunch, the
> trigger is not `CURVE`, and the slice ships as a NULL with its bound instead of as a lesson.**
> (Slice 48's shape, named at `docs/DEFERRALS.md` §"New candidates raised by slice 54": *a slider
> that is monotone-better upward is slice 48's shape and not a new lesson.*)

> **PRE-REGISTERED FALSIFIER F3 — THE SHAPE'S OWN BOUND.** The box is a **separable** approximation
> of a fan beam (§0.3). The alternative of the same class is the **ELLIPSE**,
> `hypot(Δaz/a, Δel/b) ≤ 1`. Slice 45's rescue cell has `Δaz = 9.7519°`, `Δel = 2.4934°`, so at
> `(10, 1.90)` the ellipse reads `hypot(0.97519, 1.3123) = 1.634 > 1` and **does not rescue** — by
> arithmetic, before flying. **This is predicted here, before the probe, and it must be flown and
> published**: if the ellipse also rescues, this plan's arithmetic is wrong and that is worth more
> than the headline. Either way **the claim is BOUNDED to separable windows in the shipped
> docstring**, not stated as a fact about fan beams in general.

> ⭐⭐⭐ **F3 FIRED IMMEDIATELY, AND WHAT IT REFUSED WAS THIS PLAN (P0c/P4, 2026-09-07).** The
> paragraph above quietly asserted that the BOX *does* hold that cell. It does not: the ∞-norm is
> `max(9.7519/10, 2.4934/1.90) = max(0.9752, **1.3123**) = 1.3123` — **OUTSIDE, by 31 %**. The plan
> read the azimuth term and stopped. ⚠⚠ **AND THE REPAIR IS NOT A CORRECTED NUMBER, IT IS A
> RETRACTED METHOD:** `Δaz = 9.7519°` / `Δel = 2.4934°` were measured on the DISC's flight at the
> DISC's best moment, and a window that changes SHAPE changes where the head goes, hence which
> geometry is ever offered to it. ⇒ **A WINDOW'S VERDICT IS A PROPERTY OF THE FLIGHT, NOT OF A CELL
> — no static evaluation of either norm can settle a shape comparison, and P2/P4 must FLY both.**
> ⭐ This is slice 45's own trap one level up (a verdict written from a table instead of from an arm)
> and slice 54's standing lesson in a third place. It is also the first thing a pre-registered rule
> refused in this slice — the authority slice 54 says such a rule only earns by refusing something.
> ⚠ The ellipse arithmetic (1.6350, OUTSIDE) was itself correct; it is simply not evidence.

### §0.1.3 THE GAUGE — and it is not the miss

⚠⚠ Slices 44, 45, 46, 47 all paid for this, and `docs/PROHIBITIONS.md` §2 carries it: **the gauge is
never the miss.** Slice 48's gauges are inherited unchanged:

* **`search_t_lock_s`** — seconds from sweep start to lock, `−1.0` while no lock has happened. The
  monotone one on slice 48's own slider.
* **lock / no-lock as a REGION**, not a cell (slice 48's floor is a region and asserts
  `max|Δpos| == 0` across it).
* **the horizon `R_acq`** and **the elevation margin** — both must be on the HUD or the trade is
  invisible and the curve reads as noise.

---

## §0.2 THE CLAIM, AND THE TRIGGER IT IS FILED UNDER

> **A ROUND WINDOW MAKES YOU BUY COVERAGE IN THE AXIS YOU ARE NOT SEARCHING. A FAN BEAM LETS YOU
> SPEND THE APERTURE WHERE THE SWEEP ACTUALLY GOES — AND THE MOMENT YOU NARROW IT TOO FAR, THE DRIFT
> ON THE UNSWEPT AXIS TAKES THE TARGET OUT THE SIDE.**

Two facts at HEAD make this askable, and neither existed when slice 45 ran:

* **`search_sweep` is SINGLE-AXIS** (`core/src/frames.jl:1085`, `slice48_search.yaml` §NAMED
  APPROXIMATIONS: *"a SINGLE-AXIS SYMMETRIC TRIANGLE SWEEP IN BODY AZIMUTH"*). The searching head
  drives azimuth to the rim **by design** and never commands elevation at all — slice 43/45 measured
  the elevation departure as **EXOGENOUS**, byte-identical at matched times across ρ = 0, 1, 1.5, 4.
* **The window sets the reach** (slice 46). So the elevation half-width is not free coverage — it is
  **gain the search is spending on an axis it does not sweep.**

⚠⚠ **`slice48_search.yaml`'s own knob list DISQUALIFIED the circular window for exactly the structure
this slice ships:** *"`gimbal_fov_deg` (⚠⚠ TWO-SIDED since slice 46 — it moves the window AND the
horizon in opposite directions, so the composite is non-monotone and the lesson would reverse)."*

> ⭐⭐⭐ **THAT DISQUALIFICATION IS THIS SLICE'S TRIGGER, NOT ITS OBSTACLE — AND IT IS LEGAL ONLY
> UNDER THE 2026-09-06 REFRAME.** `docs/PROHIBITIONS.md` §4 re-tags the whole non-monotonicity list
> as **TIER 2 — `CURVE`**: *a reversal says an OPTIMUM exists and names where.* The elevation slider
> is **non-monotone BY CONSTRUCTION** — narrow it and the reach grows while the unswept-axis coverage
> shrinks — and **the turning point IS the lesson.**
>
> ⚠⚠ **SHIPPED AS A SLIDER CLAIMING MONOTONE IMPROVEMENT, THIS SLICE DIES FOR `gimbal_fov_deg`'s
> REASON.** The headline is the turning point, never "narrower is better."

**Secondary trigger — `REGIME`, and it is the build list's own:** the shape is invisible to a
TRACKER (which holds both axes near zero, so the window's corners are never visited) and decisive for
a SEARCHER (which drives one axis to the rim, which is where the corners live). ⚠ At HEAD this is
provable only in its **corrected** form — see §0.4 P1. Convention 9: **the SHOWCASE carries the
CURVE**; the REGIME half ships as a tooth in `core/test/`, not as a second slider.

---

## §0.3 NAMED APPROXIMATIONS (HANDOFF §1)

* **The window is SEPARABLE** — `|Δaz| ≤ a && |Δel| ≤ b`, a box in angle space. This is the same
  CLASS of approximation the shipped disc already is: `off_axis_angle`'s own docstring says it is
  *"THE ANGLE-SPACE RADIUS, NOT THE EXACT CONE HALF-ANGLE."* A real fan beam's threshold contour is
  neither a box nor an ellipse. ⚠ The ELLIPSE is flown as F3 and the claim is bounded by its result.
* **The gain is `Ω = θ_az · θ_el`** — the standard separable-aperture solid angle, which is
  `aperture_gain`'s existing model with the two axes allowed to differ. At `θ_az = θ_el` it is the
  shipped expression **by construction** (§1.1), not merely equal to it.
* **No sidelobes, no taper difference between the axes**, and `detect_eta` stays one number for both
  axes. A real fan beam is illuminated differently along and across the fan.
* **Everything slice 48 named, unchanged** — one snapshot dead-reckoned at constant velocity, no
  datalink update, no INS drift, an authored deterministic picture error.
* ⚠ **The mechanical STOP stays CIRCULAR** (§0.0). A wire authoring a fan beam behind a circular stop
  is a deliberate, documented mismatch, not an oversight.

---

## §0.4 THE GATE-0 PROBES — what must be true before gate 1 is written

Probes live in `W:\temp\claude\slice55\`. Each names what would kill it.

**P0 — THE SEAM SURVEY (no measurement).** Enumerate every site that reads `gimbal_fov_deg` or
`fov_h` at HEAD: the two slew gates (`core/src/missile.jl:2483`, `:2515`), the availability verdict
(`:2568`), the horizon's `fov_det`/`bw_det` (`:2770` region), the margin readouts (`:3670`–`:3700`),
and the loader (`core/src/scenario.jl:823`, `:972`). ⚠⚠ **KILLS THE SLICE IF the two-axis form cannot
reach `bw_det`**: a box that keeps the 10°-disc horizon is strictly better at no cost, which is a
free lunch and not a trade.

**P1 — THE CORRECTED TRACKING IDENTITY (the REGIME half's tooth).** The build list's *"byte-identical
on 8/9 tracking rows"* cannot hold at HEAD. The provable statement is:

> **box `(a, b)` ≡ disc `√(ab)` on a tracking arm**, conditioned on `max|Δaz| ≤ √(ab)` **and**
> `max|Δel| ≤ b` over the arm.

Both conditions are **externally anchored** by measured errors, not asserted (convention 11). ⚠ If
the identity holds only because the tracking arm never approaches either limit, say so — that is the
mechanism, and it is the REGIME claim stated honestly.

**P2 — THE RESCUE, RE-FLOWN AT HEAD ON THE SHIPPED SEARCH WIRE.** Slice 45's rescue lived inside
slice 43's probe patch. Re-fly on `scenarios/slice48_search.yaml`'s wire with the shipped search:
disc `a`, box `(a, b)`, and **all three controls of §0.1.1**. Publish the full table.
⚠⚠ KILLS THE HEADLINE if the box fails either comparison in §0.1.1.

**P3 — F1, THE `dt` HALVING.** §0.1.2. KILLS THE HEADLINE on a >25 % gap narrowing.

**P4 — F3, THE ELLIPSE.** §0.1.2. Bounds the claim; does not kill it.

**P5 — THE LOSING ARM.** ⚠⚠ **REQUIRED, NOT OPTIONAL.** The box wins on slice 48's wire *because*
the elevation drift is small (**2.4934°** at the disc's best moment). Author a geometry with a large
unswept-axis drift and fly it: **the box must LOSE there.** Without this arm the slice ships a free
lunch, not a trade — and this arm is also what earns the `CURVE` reversal (F2). The dial is known and
measured, so make it bigger.

**P6 — THE SLIDER'S CURVE.** Sweep `gimbal_fov_el_deg` on the gate-3 wire and locate the turning
point. ⭐ Slice 54's technique applies if the argmax is noisy: **N shadow arms on ONE pass, paired,
drawing nothing.**

---

## §1 GATE 1 — PURE PRIMITIVES

### §1.1 `core/src/rf.jl` — the two-axis aperture

```
aperture_gain(bw_az_rad, bw_el_rad; eta = 0.6) -> Float64
```
`G = η·4π/(θ_az·θ_el)`. ⭐ **The shipped one-argument method is REDEFINED AS `aperture_gain(bw, bw)`
— defined from it, not merely equal to it** (the `boresight_angle` ⇐ `off_axis_angle` posture,
`core/src/frames.jl:1581`). That makes `aperture_gain(θ, θ) === aperture_gain(θ)` an **identity at
atol 0**, pinned in `core/test/test_radar_eq.jl`, rather than a tolerance.
⚠ Both arguments are **FULL** beamwidths; both throw `DomainError` on non-positive. Convention 12:
pure, measurement-agnostic, cross-domain — nothing seeker-specific here.

### §1.2 `core/src/frames.jl` — the anisotropic window

```
off_axis_ratio(ref_az, ref_el, az, el, a_rad, b_rad) -> Float64     # ≤ 1 ⟺ inside
```
Separable: `max(|wrap_angle(az−ref_az)|/a, |wrap_angle(el−ref_el)|/b)`.
⚠ **ONE KERNEL, and the trap `frames.jl` already names for `off_axis_angle` applies verbatim** — no
inline restatement at any consumer, or `test_frames.jl` proves a second implementation and nothing
about what flies.
⚠ At `a == b` this is `off_axis_angle`'s **∞-norm**, not its 2-norm — it is **not** a generalization
of the disc and must never be documented as one. **The disc is preserved by the CONSUMER's
key-presence anchor (§2.1), never by this kernel's algebra.**
⚠ `off_axis_angle`'s docstring at `core/src/frames.jl:790` currently says a rectangular window
*"remains a named deferral"* and that *"using this kernel on the glass would be that error."* That
paragraph is **amended, not deleted**: the circular kernel stays correct for a pencil beam, and the
amendment states which of the two a wire is choosing and why.

### §1.3 Tests
`core/test/test_frames.jl` (the kernel: wrap paired with a does-not-wrap case, symmetry, the ∞-norm
vs 2-norm separation stated as a tooth), `core/test/test_radar_eq.jl` (the atol-0 identity, the
`√(a/b)` reach ratio against an INDEPENDENT recompute — convention 11).

---

## §2 GATE 2 — THE WIRE

### §2.1 The anchor
`gimbal_fov_el_deg` is an **authored comp key whose PRESENCE gates every branch**, the
`seeker_search` / `_gim` posture. **Absent it, every site runs the shipped circular expression
verbatim** ⇒ slices 1–54 byte-identical **by construction**, not by measurement (convention 2).

### §2.2 The sites (all in `core/src/missile.jl`)
Two slew gates (`:2483`, `:2515`) · the availability verdict (`:2568`) · **the horizon's `bw_det`
(the P0 blocker)** — `Ω` from the two half-widths, so the reach is `√(a/b)` longer than the disc `a`
and **equal** to the disc `√(ab)` · the margin/telemetry block (`:3670`+), which gains
`gimbal_fov_el_deg`, the elevation margin, and `R_acq` beside them.

### §2.3 The loader (`core/src/scenario.jl`)
Validate-at-load (convention 5): `> 0`, finite, refused beside `seeker_fov_deg` (the existing
head/no-head exclusivity at `:972`). ⚠ The live slider clamps **at the consumer**. ⚠ Convention 6: no
`Inf`/`NaN` to JSON — the horizon floors finite on a degenerate the slider can reach in one drag.

### §2.4 Draw topology
Convention 4 class **(c)**: physics-changing, **no RNG**. The horizon is a hard threshold with no
`Pd` draw (`core/src/rf.jl` `detection_range`), so the per-look draw COUNT is untouched on every rung
and every slider (convention 3). `test_determinism.jl` unaffected; the **absolute golden** is the
check that matters (convention 2).

---

## §3 GATE 3 — THE SHOWCASE

`scenarios/slice55_fanbeam.yaml` on slice 48's wire, **with P5's losing arm authored into the
geometry** so the reversal is reachable inside the slider's domain.

* **ONE slider:** `gimbal_fov_el_deg` (convention 9). **Non-monotone by construction** — the label
  must say *watch the turning point*, never *narrower is better*. ⚠ Label ≤ ~110 characters (slice
  32's shots paid for this).
* **ONE button:** slice 46's `seeker_detect: none ↔ snr`, unchanged. Press it and the horizon goes
  away — **and with it the entire cost of a wide window**, which is the sharpest available statement
  of why the fan beam exists.
* **HUD:** `search_t_lock_s`, the elevation margin, and **`R_acq`** — the trade is invisible without
  the last one. ⚠ Convention 13: drawn from telemetry, never recomputed in GDScript.
* **FOUR proofs** (convention 14): `net/slice55_verify.gd`, `net/slice55_ui_test.gd`, a headless
  smoke-load, and a **windowed shot** — ⚠ anything inside `_draw` has no headless proof (slice 50).
* ⚠ The verifier **DRAGS the slider** (retracted rule, `docs/PROHIBITIONS.md` §6), and something must
  deliberately **SURVIVE** the drag (slice 54's harder half).

---

## §4 WHAT KILLS THIS SLICE

| # | finding | consequence |
|---|---|---|
| **K1** | the two-axis window cannot reach `bw_det` (P0) | **DEAD** — a free lunch, not a trade |
| **K2** | the box loses to the gain-matched disc `√(ab)` (P2) | **HEADLINE DEAD** — "a wider window is free" in a rectangle |
| **K3** | the `ρ*` gap narrows >25 % at half `dt` (P3/F1) | **HEADLINE DEAD** — an integrator artifact |
| **K4** | no reversal anywhere in the slider's domain (P6/F2) | **NOT A `CURVE`** — ships as a `NULL` with its bound |
| **K5** | no geometry where the box LOSES (P5) | **DEAD** — a free lunch, and the trade was never modelled |
| — | the ellipse does not rescue (P4/F3) | **NOT a kill** — bounds the claim to separable windows |

⚠ K4 and K5 downgrade the slice to *physics + tests + authorable keys* (the slice-51 `turn_start_s`
precedent, `docs/PROHIBITIONS.md` §6). They do **not** make it unshippable — that is the two-test
rule, and this plan is written so the downgrade is a documented outcome rather than a rescue.


---

# PART II — THE GATE-0 RECORD (2026-09-07)

**Gate 1 and the gate-2 seam were written FIRST, behind the key-presence anchor, and the suite is
GREEN AND UNCHANGED AT 20069** — so every number below is flown against real shipped code rather
than a throwaway patch (§0's ruling on `patch45.py`). Byte-identity for slices 1–54 is therefore a
CONSTRUCTION, not a measurement: with no `gimbal_fov_el_deg` authored, `_box` is the literal `false`
and every predicate takes the circular arm verbatim.

## §II.0 THE HARNESS IS ANCHORED ON A SHIPPED ORACLE (convention 10)

Before any new arm was believed, the probe reproduced slice 48's own published row on
`scenarios/slice48_search.yaml` at ρ = 36 °/s: **LOCK, `t_lock` 2.0400 s, CPA 677.27 m** — the
scenario file's table, to every digit. ⚠ Never a hand-recompute.

## §II.1 P0 — THE THREE THINGS THAT HAD TO BE TRUE BEFORE FLYING

**(a) THE APERTURE IDENTITY IS atol 0.** `aperture_gain(θ) === aperture_gain(θ, θ)` on the Float64
bits at θ = 1 / 2.5 / 10 / 20 / 45°, because `rf.jl` DEFINES the one-argument method from the
two-axis one instead of restating it.

**(b) THE REACH RATIO IS `√(a/b)`, AGAINST AN INDEPENDENT RECOMPUTE** (convention 11) — `R ∝ √G`,
the gain entering the link budget twice and `detection_range` inverting an `R⁻⁴` law:

| window | G (lin) | `R_acq` (m) | `√(a/b)` predicted | measured ratio |
|---|---|---|---|---|
| DISC 10.00° | 61.88 | 3038.16 | — | 1.0000 |
| BOX (10, 6.00) | 103.1 | 3922.25 | 1.2910 | **1.2910** |
| BOX (10, 2.50) | 247.5 | 6076.32 | 2.0000 | **2.0000** |
| BOX (10, 1.90) | 325.7 | 6970.02 | 2.2942 | **2.2942** |
| BOX (10, 1.00) | 618.8 | 9607.51 | 3.1623 | **3.1623** |

⭐⭐⭐ **AND THE RULING CONTROL IS AN IDENTITY, NOT AN APPROXIMATION.** For every row the
gain-matched disc `√(ab)` returns the SAME `G` and the SAME `R_acq` to all six printed digits (ratio
to the box **1.000000**). §0.1.1's pre-registered control is therefore the shipped link budget's own
definition — which is precisely why it, and not the sum- or area-matched disc, has a consumer.

**(c) THE ∞-NORM IS NOT THE 2-NORM**, so `b = a` does NOT recover the disc: equal on either axis,
**1.414214× apart on the diagonal**. Byte-identity is held by the anchor, never by algebra.

## §II.2 ⭐⭐⭐ F3 FIRED FIRST, AND WHAT IT REFUSED WAS THIS PLAN

See §0.1.2. The plan asserted the box holds slice 45's rescue cell; the ∞-norm reads **1.3123 —
OUTSIDE by 31 %**, because the plan read the azimuth term and stopped. ⚠⚠ The repair is a **retracted
METHOD, not a corrected number**: those departures were measured on the DISC's flight at the DISC's
best moment, and a window that changes shape changes where the head goes. **A window's verdict is a
property of the FLIGHT, not of a cell.**

## §II.3 ⚠⚠ P2 CONFOUNDED SHAPE WITH REACH — AND ITS NULL IS WHY THE REAL EXPERIMENT EXISTS

Sweeping `b` at fixed `a` = 10° moves `Ω`, hence the horizon, and on this wire the horizon decides
the engagement. Flown over ρ = 36 / 45 / 60 °/s and b = 6.0 … 0.6°, **all 27 box arms tied their
gain-matched control to every printed digit** — CPA, `R_acq`, `t_lock`, everything. ⇒ **the SHAPE was
invisible across that entire sweep, because only `Ω` differed and `Ω` was matched by construction.**

> ⭐⭐ **A SWEEP THAT MOVES THE COST CANNOT MEASURE THE SHAPE. HOLD `Ω`.** That is the correction P2
> forced on this slice's own experimental design, and it is the reason §II.4 exists.

## §II.4 ⭐⭐⭐ P2b — THE SHAPE ISOLATED: `a·b = 100 deg²`, SO `R_acq` IS THE SHIPPED 3038.2 m EXACTLY

Every arm below costs the SAME APERTURE as the shipped disc, and the gain-matched control IS the
disc-10 row by construction (`√(ab)` = 10). All differences are pure SHAPE.

**ρ = 0 °/s — NO SEARCH AT ALL, which is what slice 47 ships and what slice 48's slider floors to:**

| arm | lock? | `t_lock` | CPA | authority |
|---|---|---|---|---|
| DISC 10.00 (SHIPPED) | — | — | **1039.88 m** | 0.0 % |
| BOX (8.0, 12.500) | — | — | 1039.88 m | 0.0 % — **BIT-IDENTICAL** to the disc over 9600 ticks |
| BOX (6.0, 16.667) | — | — | 1039.88 m | 0.0 % — **BIT-IDENTICAL** |
| BOX (12.0, 8.333) | **LOCK** | 4.9360 s | **0.09 m** | 20.0 % |
| BOX (20.0, 5.000) … (150.0, 0.667) | **LOCK** | 4.9360 s | **0.09 m** | 20.0 % |

> ⭐⭐⭐ **A FAN BEAM ACQUIRES WITH NO SEARCH AT ALL WHERE THE DISC OF THE SAME APERTURE NEVER
> ACQUIRES.** The midcourse picture puts the target at −11.34° of body azimuth
> (`slice48_search.yaml` reason 2); a 10° disc cannot reach it and a 12°-wide fan beam can — **and it
> buys that azimuth with elevation it was never using.** 1039.88 m → 0.09 m at the same `G`, the same
> `R_acq`, the same everything else.
>
> ⭐⭐ **AND THE LOSING DIRECTION IS IN THE SAME TABLE, WHICH IS WHAT MAKES IT A TRADE AND NOT A
> CLAIM:** the TALL boxes (`a` < 10) are **BIT-IDENTICAL to the disc over 9600 ticks**. The same
> budget spent on the unswept axis buys **literally nothing** — `max|Δel|` on a locking arm is
> **0.0565°**.

**ρ = 36 °/s, with slice 48's search running:** the disc locks at 6.976 s, misses by **677.27 m** and
spends **71.2 %** of the airframe; BOX (12, 8.333) locks at **4.936 s**, hits at **0.09 m** and
spends **20.0 %**. ⭐⭐ **The fan beam buys what a faster servo would have bought** — and at
ρ = 240 °/s the disc finally reaches 0.31 m, so **the shape stops mattering once the sweep is fast
enough.** A REGIME boundary, measured.

### ⭐⭐⭐ AND THE SHARPEST STATEMENT IN THE SLICE IS NOT THE RESCUE — IT IS WHERE THE DISC LANDS

At ρ = 36 the TALL boxes are strictly WORSE than the disc: they never lock at all (`max|Δel|` 19.66°
while hunting) where the disc does. So across one aspect-ratio axis, at **one fixed aperture cost**:

    TALL (6° × 16.7°)  — never acquires, and at ρ = 0 it is BIT-IDENTICAL to the disc
    DISC (10°)          — acquires only with a search, 677.27 m, 71.2 % of the airframe
    WIDE (12° × 8.3°)   — acquires with NO SEARCH AT ALL, 0.09 m, 20.0 %

> ⭐⭐⭐ **THE SAME APERTURE, ARRANGED THREE WAYS, AND THE ROUND ONE IS NEITHER THE BEST NOR THE
> WORST.** That, and not the 1039.88 → 0.09 m rescue, is what this slice teaches — because a rescue
> can always be read as *buying coverage* (42/43's ban, which 46 upheld), and a MIDDLE cannot.
> **A circle is a point on the aspect-ratio axis, not the baseline the axis is measured from**, and
> the design question is where on that axis to sit, not how much window to buy.

⚠ The rescue number is the EVIDENCE for that sentence, never the headline. Quoted alone it invites
exactly the objection slice 45's own pre-registered control raised and §0.1.1 was written to answer.

## §II.5 ✅ F1 PASSES — THE BOUNDARY IS NOT AN INTEGRATOR ARTIFACT

The ρ = 0 acquisition boundary lies between **a = 11.0 (never locks)** and **a = 12.0 (locks at
4.9360 s)**. Re-flown at `dt` = 5e−4 it sits in the **same bracket**: the failing arms at 1039.94 m
against 1039.88, the locking arm at 4.9350 s against 4.9360. ⇒ slice 42's standing rule is
satisfied — **this is hardware, not `ω·dt`.**

## §II.6 ⚠⚠ F2 FIRED ON SLICE 48's GEOMETRY — AND P5b FOUND THE REVERSAL ELSEWHERE

On the shipped geometry, widening is **monotone-better out to a = 150° (b = 0.667°)**: every arm from
12° to 150° returns the identical 4.9360 s / 0.09 m / 20.0 %, because `max|Δel|` on a locking arm is
0.0565° and the elevation half-width never binds. ⇒ **no turning point there**, and per §0.1.2 that
is published rather than argued around.

**P5b gave the target a VERTICAL RATE, which is what loads the unswept axis.** ρ = 0 throughout, `Ω`
held, so this is still pure shape at constant cost:

| `vz` (m/s) | max\|Δaz\| | max\|Δel\| | DISC 10 | BOX (12, 8.33) | BOX (20, 5.0) | BOX (150, 0.667) |
|---|---|---|---|---|---|---|
| 0 | 11.35° | 0.06° | 1039.88 | **0.17** | **0.09** | **0.02** |
| 80 | 11.74° | 0.48° | 1073.73 | **0.03** | **0.03** | **0.07** |
| 120 | 12.04° | 0.74° | 1096.85 | *never locks* | **103.38** | 103.61 |
| 160 | 12.43° | 1.01° | 1124.94 | *never locks* | **280.66** | 280.80 |
| 220 | 13.23° | 1.41° | 1178.58 | *never locks* | **587.77** | **745.73** ⭐ |

⭐⭐⭐ **THE REVERSAL IS REAL AND IT ARRIVES EXACTLY WHERE THE ARITHMETIC SAYS IT MUST.** At
`vz` = 220 the unswept-axis error reaches **1.4086°**, and BOX (150, **0.667**) — the only arm whose
elevation half-width is BELOW that — locks **1.61 s later** (7.082 s against 5.473), misses by
**745.73 m** against 587.77, and spends **33 %** of the airframe against 17 %. Every arm with
`b` > 1.41° is unaffected. ⇒ **the turning point is not a tuning constant: it is where the elevation
half-width crosses the unswept-axis error.**

⚠⚠ **BUT THE REVERSAL IS ONE ARM DEEP ON THIS GEOMETRY, AND THAT IS NOT YET A SHOWCASE CURVE.** A
gate-3 slider needs the turning point INSIDE its domain with several arms either side of it, which
means authoring a wire whose unswept-axis error is larger — not quoting this table as if it already
were one. **That authoring is gate 3's first job, and it is the one thing gate 0 has NOT discharged.**

## §II.7 THE VERDICT AGAINST §4's KILL TABLE

| # | pre-registered kill | outcome |
|---|---|---|
| **K1** | the shape cannot reach `bw_det` | ❌ **does not fire** — it reaches it; `R_acq` moves as `√(a/b)`, measured |
| **K2** | the box loses to the gain-matched disc | ❌ **does not fire** at held `Ω` — 1039.88 m *never acquires* → 0.09 m *hit*. ⚠ It DID tie in P2, and that null is published in §II.3 as an experimental-design error, not a physics result |
| **K3** | the `dt` halving moves the boundary | ❌ **does not fire** — same bracket at 5e−4 |
| **K4** | no reversal anywhere | ⚠ **fires on slice 48's geometry** (§II.6) and is **discharged by P5b** at `vz` = 220 |
| **K5** | no geometry where the box loses | ❌ **does not fire** — two independent losing directions: TALL boxes are bit-identical to the disc (worthless), and `b` < max\|Δel\| is strictly worse |

⇒ **THE SLICE LIVES.** Trigger: **`RIVAL`** as the headline — *two windows of identical aperture
cost, one of which fails for a stated physical reason: a disc must buy elevation coverage it never
uses, and pays for it in the azimuth it desperately needs* — with **`CURVE`** available on a wire
gate 3 must still author, and a measured **`REGIME`** boundary at ρ = 240 °/s where the shape stops
mattering.

⚠⚠ **THIS IS NOT "A WIDER WINDOW IS FREE" (42/43, killed by 46).** `Ω` is held to the digit on every
comparison above, so every degree of azimuth is paid for in elevation. The claim is about **where you
SPEND a fixed aperture**, never about how much of it you have.

---

# PART III — THE GATE-1/2/3 LOG (2026-09-07)

⚠ **A LATER GATE LOG SUPERSEDES A PLAN §** (`CLAUDE.md`'s own rule). Where this part disagrees with
§3 above, this part is what shipped.

## §III.0 ⭐⭐⭐ THE SHOWCASE SLIDER PIVOTED, AND IT WAS FORCED RATHER THAN CHOSEN

§3 pre-registered **ONE slider, `gimbal_fov_el_deg`**, with the turning point inside its domain. That
slider **cannot exist**, and the reason is one line of the wire protocol: `set_param` carries a
single Float64 (`core/src/scenario.jl:1172`, `:1621`). Dragging the elevation half-width ALONE moves
the PRODUCT, hence the gain, hence the horizon — so the slider would teach **REACH** (slice 46's
lesson) while appearing to teach **SHAPE**, which is precisely the confusion §II.3 measured across 27
arms. Holding `Ω` needs BOTH keys moved on the same tick, and the wire has no such command.

⇒ **THE SHIPPED SLIDER IS SLICE 48's OWN `seeker_search_rate_dps`, INHERITED UNCHANGED SO THE A/B IS
EXACT, AND IT IS SHIPPED TO BE MEASURED AS INERT.** On slice 48's disc it is the whole lesson
(1039.88 m → 0.31 m over 0…240 °/s); here every position returns the same acquisition instant and a
**bit-identical trajectory**, because the target was never lost. The knob still reaches the physics
on every arm (`search_rate_dps` is read back off the wire, including after a mid-flight drag), so
this is a **measured NULL and not a dead knob**.

**TRIGGER AS SHIPPED: `RIVAL` (the headline) + `NULL` (the slider, with its bound).** The `CURVE` is
NOT shipped and is not claimed: §II.6's reversal is real, measured and one arm deep, and it needs its
own wire. It is filed as a candidate with its numbers, never quoted as if a slider existed.

## §III.1 ⚠⚠ THE GATE-1/2 TESTS AS WRITTEN HAD NEVER RUN — PART II's "GREEN AT 20069" WAS FALSE

`@test !disc.ever && disc.cpa ≈ 1039.88 rtol = 1e-4` is **not a legal `@test` call**: a keyword
argument cannot ride a `&&` chain. Julia raises `invalid test macro call` at PARSE time, which
aborted `test_search.jl` at its first slice-55 testset — **14853 passing, 1 error, and everything
after it in that file unrun.** PART II's line *"the suite is GREEN AND UNCHANGED AT 20069"* was
therefore written from a run that did not contain the tests it was claiming.

> ⭐⭐⭐ **A SUITE COUNT IS ONLY EVIDENCE IF THE RUN IT CAME FROM CONTAINED THE NEW TESTS.** The
> failure mode is silent in exactly the wrong direction: the error appears *inside* a testset banner,
> the run continues, and the summary line still prints a large green-looking number. ⇒ read the
> `Pass / Error / Total` triple, never the Pass column alone.

## §III.2 ⚠⚠ AND THE LOADER REFUSALS PASSED FOR THE WRONG REASON — TWO LAYERS DEEP

The three refusal tests were `@test_throws ErrorException load_scenario(y)` against a fixture that
was missing `mass_kg`. The loader threw — on `mass_kg` — and all three went green **with slice 55's
refusals deleted**. Repaired by asserting the refusal's own TEXT (`occursin`), which immediately
exposed a SECOND layer: the fixture also lacked `two_angle: true`, so the next throw was slice 34's
`gimbal_tau_s` guard. Only the third fixture in the chain actually reaches this slice's code.

> ⭐⭐ **`@test_throws ErrorException` IS A TAUTOLOGY WHENEVER THE FIXTURE CAN FAIL FOR AN UNRELATED
> REASON** — convention 11's rule, in the place it is easiest to violate. A loader guard's test must
> assert WHICH refusal fired.

## §III.3 WHAT GATE 3 ADDED TO THE **CORE**, AND WHY IT COULD NOT LIVE IN THE CLIENT

* ⭐⭐⭐ **`gimbal_t_acq_s` — THE ACQUISITION INSTANT, LATCHED.** `search_t_lock_s` measures seconds
  from the SWEEP's start and exists only where a sweep RAN. A fan beam wide enough to hold the cue
  error **never enters the search arm**, so on the shipped wire it holds its honest sentinel −1.0
  across a flight that acquires at **4.935 s** and hits at **0.085 m**. Slice 48's HUD reads that key
  and would print *"NOT SEARCHING: head frozen"* over an intercept — `docs/CONVENTIONS.md` §14's
  defaulted-value trap **with the sign flipped**. ⚠ Latched in the core because `gimbal_valid` beside
  it is LIVE and a client sees one frame in 16 ticks (slice 53's rule).
* ⭐⭐ **`gimbal_fov_az_margin_deg` / `gimbal_fov_el_margin_deg` — THE MARGIN, PER AXIS.** The shipped
  `gimbal_fov_margin_deg` is `fov_h − off_head`: a 2-norm RADIUS against the AZIMUTH half-width, which
  under a box compares two different windows and **can carry the opposite sign to `gimbal_valid`
  beside it** (2° off in azimuth and 9° in elevation reads +3.3° of margin behind a window that has
  already refused it). That is `frames.jl`'s `√2·stop` readout hazard one level over. The pair is
  built from the predicate's own numbers, so `gimbal_valid` ⇒ both ≥ 0, asserted on every flown tick.
  ⚠ Shipped SEPARATELY, never as a worst-of: the whole lesson is that the two are unequal.

Both are anchor-gated on `gimbal_fov_el_deg` ⇒ slices 34–54 ship neither and stay byte-identical.

## §III.4 THE FOUR PROOFS — AND THE SHOT CAUGHT TWO HUD DEFECTS NOTHING ELSE COULD

| proof | result |
|---|---|
| `net/slice55_verify.gd` (9 arms incl. a LIVE mid-blind DRAG) | **PASS** (exit 0) |
| `net/slice55_ui_test.gd` (9 teeth) | **PASS** (exit 0) |
| headless smoke-load (`Sandbox.tscn`) | **PASS** (exit 0) |
| windowed shot (1920×1080, tick 4944 = the acquiring frame) | **PASS**, after two attempts |

**⭐⭐⭐ DEFECT 1 — `_detect_blind` IS A LATCH, NOT A LIVE STATE.** The cure line tested it before
`acquired`, so the first shot rendered *"waiting on the horizon — the window is already turned"*
underneath a green **SAW IT AT ONCE: 4.93 s** and a locked seeker: two verdicts about the same
instant, this family's recurring HUD failure. The fix is an ORDERING (`acquired` first), not a new
input.

**⭐⭐⭐ DEFECT 2 — THE TWO NULLS ARE DIFFERENT NULLS.** Gating the search line on *"did the head ever
sweep"* collapses **a seeker with no search at all** onto **a seeker whose search was never needed**,
and printed slice 48's own *"search OFF — the head cannot look around"* over a wire that authors a
full 25° pattern and simply never had to use it. Split into the wire's authored CAPABILITY (the
coverage key's presence) and what the head actually DID.

⚠ Both were invisible to the verifier and the UI test alike, because both live in `_draw`'s dispatch.
⇒ convention 14's fourth proof earned its place again. The shot's five lines, at the acquiring frame:

    SAW IT AT ONCE: 4.93 s
    window 12.5° az x 8.0° el = 100 deg^2   reach 3038 m
    a 10.0° DISC costs the same and reaches no further
    margin az +2.85°   el +7.97° of 8.0° — the el axis is idle
    sweep 0°/s NEVER RAN — nothing was ever lost
    a 10° DISC of this cost cannot reach 11.3° of azimuth

## §III.5 TWO CORRECTIONS THE VERIFIER FORCED ON ITS OWN TEETH

1. ⚠⚠ **THE MARGIN PAIR IS ASSERTED AS FRACTIONS, NOT DEGREES.** The core's per-tick pair at the
   acquiring tick is **+1.1446° / +7.9797°**; the FIRST VALID FRAME a client sees is up to 15 ticks
   late and reads **+2.855° / +7.974°**, because the head keeps slewing onto the target. **The
   degrees are a joint property of the geometry and the emit grid; the FRACTIONS are the claim**
   (el above 98 % of its half-width still idle, az below 35 % of its own left). The per-tick degrees
   are pinned in `core/test/test_search.jl`, where the sampling is exact.
2. ⚠ **THE POST-INTERCEPT RE-SEARCH IS FENCED OFF.** From ~9.18 s the seeker has lost a target that
   is now behind it and the head starts hunting again — correctly. Both search gauges are read
   **before the acquisition only**; counting that episode would make *"the head never had to search"*
   false for a reason that has nothing to do with the window's shape. (Slice 52 met the same
   re-search and fenced it the same way.)

## §III.6 THE VERDICT

**THE SLICE SHIPS.** Against §4's kill table nothing fired that was not already discharged: the shape
reaches `bw_det` (K1), the box beats the gain-matched disc at held `Ω` (K2), the boundary survives the
`dt` halving (K3), and two independent losing directions exist (K5). **K4 fired on this geometry and
is published as a measured NULL with its bound** — which, under the 2026-09-06 reframe, is a legal
trigger rather than a downgrade.
