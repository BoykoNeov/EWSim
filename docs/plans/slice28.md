# Slice 28 — `R(look)`: THE SLOPE CURVE, AND THE BAND THE ENGAGEMENT VISITS (§11 Tier-A)

The SIXTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
radome-slope compensation autopilot) and a deferral BOTH 26 and 27 named:

> *"A LOOK-ANGLE-DEPENDENT SLOPE `R(look)` — slice 26's deferral, unchanged, and it composes sharply
> with this one: against a wiggly real slope curve a CONSTANT `R̂` is wrong almost everywhere, so the
> residual becomes a function of the geometry."* — `docs/plans/slice27.md`, named deferrals

Slice 26 built the disease (a constant error slope `R` closes a parasitic loop). Slice 27 built the
cure and measured its limit (a scalar `R̂` cancels to the accuracy of the belief; the residual
`R − R̂` sets the boundary). **Both assumed the glass has ONE slope. It does not** — a radome's error
slope is a curve in look angle. Slice 28 makes it one, and the consequence is that the residual
stops being a property of the hardware and becomes a property of **the engagement**.

**Status: GATE 0 COMPLETE (10 probes run 2026-07-27, `M:\claud_projects\temp\slice28\`; raw
findings in `GATE0_FINDINGS.md` beside the probe scripts).**

---

## The one-paragraph statement of the lesson

A radome's boresight-error slope is not a number, it is a curve `R(look)`: the ray passes through
different glass at different look angles, and the slope wiggles. The parasitic loop of slice 26 is
driven by the **local derivative of the boresight error at the look angle you are actually flying**
— so which part of that curve closes your loop is decided not by the radome but by the
**geometry of the engagement**. Against a static target the collision course carries zero lead and
the seeker settles onto boresight, where the curve is flat by construction; against a crossing
target it holds a sustained lead angle and parks on a steep part of the glass. Slice 27's
compensator, characterized at boresight — the natural place to characterize it — is then exactly
right where it is never used and wrong where it matters, and the missile rings.

> **THE LESSON, IN ONE SENTENCE.** The radome's error slope is a CURVE, the parasitic loop is closed
> by its LOCAL DERIVATIVE at the look angle the engagement actually holds, and that look angle is
> set by the target's crossing geometry — so slice 27's requirement "know your slope" sharpens into
> **"know your slope curve over the look-angle band the engagement visits"**, and characterizing at
> boresight is the natural and DANGEROUS choice.

⚠ **INHERITED LANGUAGE AND ITS PROHIBITIONS.** The instability is still slice 26's — a true
positive-feedback loop with a loop gain, a stability boundary and self-excitation from zero input.
Slice 20's "degenerative spiral" language stays forbidden here; slice 26's stays forbidden
elsewhere. Slice 28 adds **no new instability and no new cap**: it makes the loop gain a function of
the flight condition, exactly as slice 20 made the aero ceiling self-lowering without adding a cap.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⚠⚠ THE BLOCKING QUESTION: THE LOOK ANGLE MUST SWEEP — AND SLICE 27's WIRE KILLS IT (P1, P1b)

`R(look)` is only a slice if the engagement VISITS a meaningful band of look angle. If it does not,
`R'` over the traversed band is a constant and slice 28 collapses onto slice 27's residual axis —
the trap that killed slice 20's rate-limited fin in four probes.

⚠ **MEASURE IT ON A STABLE ARM.** A ringing arm's look angle swings *because* it is ringing;
using it is circular. Range-gate at `r > 500 m` too — at CPA the LOS sweeps through the missile and
`look_az` flips to ~180°, a geometric artifact, not an operating point.

| geometry | \|look\| at 5%…95% of flight | last-half band (10–90%) |
|---|---|---|
| STATIC Y=2000 — **slice 27's own wire** | 10.2 → 5.0 → 0.8 → **0.01** → 0.55 | **0.04° → 0.54°** |
| STATIC Y=6000 | 35.7 → 13.8 → 2.2 → **0.06** → 0.52 | 0.06° → 0.60° |
| CROSSING vel = (0,+300,0) | 0.8 → 16.8 → 21.1 → **22.4** | 21.9° → 22.4° |
| CROSSING+closing (−200,+300,0) | 3.3 → 23.6 → 29.5 → **31.8** | 30.7° → 31.8° |

⭐ **THE FINDING, AND IT IS PHYSICS NOT TUNING.** Against a STATIC target the collision course has
**zero lead**, so the look angle decays to ~0 and the entire endgame sits at ONE point — `R(look)`
would be a DEAD KNOB on slices 23–27's wire. A CROSSING target holds a **sustained lead angle** and
the seeker looks 15–30° off boresight for the whole flight.

⇒ **THE WIRE CHANGES, AND THAT IS THE FIX — NOT THE MODEL.** Slice 28 is the first slice of this arc
to break the shared static `Y = 2000` geometry that 23/24/25/26/27 held so they would read side by
side. **Say so plainly and give this measurement as the reason** (the slice-25 precedent: "THE
ISOLATION forced a retune off slice 24's wire"). ⚠ The lead is almost entirely in AZIMUTH
(`look_el` stays within ±0.5°) — which is load-bearing twice below (§3, §6).

### 2. ⭐⭐ THE ISOLATION: NON-MONOTONE IN THE GEOMETRY, WITH BOTH CONTROLS FLAT (P6, P7, P9)

⚠ **THE CONFOUND, AND IT WAS REAL (advisor).** "Static is quiet, crossing rings" changes TWO things
at once: the operating LOOK ANGLE (the mechanism claimed) and the WHOLE ENGAGEMENT (ToF, closing
geometry, LOS-rate history, a sustained yaw maneuver). And the second one moves the loop ON ITS OWN:
**with no curve anywhere**, the constant-`R` onset is `|R_crit| ≈ 0.065` on the crossing wire vs
`≈ 0.05` on the static one (P2) — a ~30% shift from geometry alone.

⇒ **HOLD THE GLASS, SWEEP THE ENGAGEMENT.** Crossing speed moves the sustained lead angle
monotonically while keeping the engagement qualitatively the same. With `k = 12` the slope ripple
peaks at look = 15° and returns to `R₀` at 30°, so a monotone speed sweep traverses **loud → quiet
inside the valid band**. `rms r` in the window, `A = −0.05`, `R₀ = R̂ = −0.03`:

| vy | 0 | 50 | 100 | 150 | 200 | 250 | 300 | 350 | 400 |
|---|---|---|---|---|---|---|---|---|---|
| **RIPPLE** | 0.0166 | 0.0157 | 0.411 | **0.994** | **1.042** | **0.983** | 0.086 | 0.0113 | 0.0109 |
| CONTROL (a) `A = 0` | 0.0166 | 0.0160 | 0.0155 | 0.0146 | 0.0140 | 0.0131 | 0.0123 | 0.0117 | 0.0112 |
| CONTROL (b) const −0.13 | 0.850 | 0.816 | 0.833 | 0.826 | 0.835 | 0.841 | 0.845 | 0.831 | 0.776 |

⭐⭐ **QUIET → RING → QUIET against a MONOTONE geometry change**, with control (a) flat quiet at
every speed and control (b) flat ringing at every speed, and `>30°` = **0.0%** throughout.
**A confound cannot produce a non-monotone response to a monotone geometry change.** This is the
isolation the slice rests on; it is stronger than control (a) alone, which only shows that the
engagement change by itself never rings.

⚠ **THE SWEEP'S VALID BAND IS BOUNDED, AND THE BOUND IS MEASURED.** Past vy ≈ 400 the closing speed
— and with it the PN loop gain — collapses, and even CONTROL (b) goes quiet (0.776 at 400, 0.047 at
450 in the `k = 8.2` run). Do not sweep past 400 and do not read the quiet arms above it as ripple
physics.

⚠ **DO NOT SUBSTITUTE THE `k` SWEEP FOR THIS.** `k` is also non-monotone (§5) but it is an AUTHORED
parameter, and non-monotonicity in a parameter you chose reads as "you tuned it". Non-monotonicity
in the GEOMETRY, at fixed glass, is the one a skeptic cannot answer.

### 3. ⭐ THE DISCRIMINATOR THAT LICENSES THE SLICE: THE LOOP TRACKS THE DERIVATIVE (P3, P8.6)

A slope curve is more than a re-parameterization of slice 26's constant only if the loop is driven
by the LOCAL DERIVATIVE `dε/dlook` rather than by the BEND `ε` itself. **Under slice 26's linear
model those are the same number** — which is exactly why 26 could not tell them apart.

**The matched-secant A/B**, on the SHIPPED kernel (`k = 12`, `R₀ = 0`, `A = −0.05`, `R̂ = 0`,
vy = 200; derivative `R(L) = −0.10`, secant `ε(L)/L = −0.05`):

| arm | `rms r` (window) | verdict |
|---|---|---|
| RIPPLE | **1.064** | RINGS |
| LIN matched-**SECANT** (−0.05) | 0.0156 | quiet |
| LIN matched-**DERIVATIVE** (−0.10) | 0.845 | RINGS |

⭐ Same bend at the operating point; opposite behaviour. **A radome inside its boresight-ERROR spec
everywhere can still ring, because the loop feels the SLOPE.** That is the licensing fact and it is
also the teaching payload's other half — specs are written on `ε`, stability is written on `dε/dlook`.

⚠ **SIZE THE A/B SO THE SECANT LANDS INSIDE CRITICAL.** Two gate-0 runs of this comparison were
SPOILED because the secant was itself past `|R_crit| ≈ 0.065` and both arms rang (P5.4 at −0.0801,
P4.4 at −0.075). The tooth must assert quiet-vs-ring, so the secant must be *demonstrably* safe.

### 4. ⭐ THE CURVE FORM: A BOUNDED SLOPE RIPPLE — AND THE CUBIC IS KILLED (P4, P5)

⚠⚠ **THE CUBIC `ε = R₀·look + C·look³` IS DEAD, killed at gate 0.** Its SLOPE is unbounded, so the
amplitude that puts the off-axis slope past critical also makes the bend diverge once the look angle
grows: at `C ≤ −0.2` the miss explodes (2550 / 3531 / 4158 m — the missile never intercepts) and the
metric *falls* with `|C|`. Onset (`C ≈ −0.15`) and breakdown (`C ≈ −0.2`) are too close for a knob
domain to fit between them, and the small-angle model would be carrying the lesson exactly where it
is invalid — **the objection slice 27 used to REJECT `R = −0.30`**, recurring.

⇒ **PARAMETRIZE THE SLOPE, NOT THE BEND, AND MAKE IT BOUNDED:**

```
R(look) = R₀ + A·(1 − cos(k·look))                       BOUNDED to [R₀, R₀+2A]
ε(look) = R₀·look + A·look − (A/k)·sin(k·look)           its exact integral; ODD; linear growth
```

- `R(0) = R₀` **exactly**, for every `A` — so "characterized at boresight" is unambiguous, and this
  is also the MECHANISM of §5's asymmetry.
- `dε/dlook ≡ R(look)` is an **exact identity**, which is a gate-1 tooth rather than a comment
  (finite-difference the shipped bend, compare to the shipped slope function).
- The slope can be driven far past critical while the BEND stays small — the physical point a cubic
  cannot express. Measured bends stay ≤ 5° across the whole shipped domain.
- ODD in `look`, i.e. a symmetric radome. A radome with an asymmetric error curve is a named
  deferral, not an oversight.

### 5. ⭐⭐ THE PAYLOAD, AND ⚠⚠ THE FIRST VERSION OF IT WAS REFUTED AT GATE 0 (P9.2, P10)

The plan's first payload was **"you cannot cancel a function with a scalar"** — a scalar `R̂` right
for one engagement must be wrong for the other. **It is FALSE on this wire, measured.** At
`A = −0.10` (`R(0) = −0.03`, `R(15°) = −0.23`):

| `R̂` | STATIC | CROSSING |
|---|---|---|
| **`R(0) = −0.03`** (boresight-correct) | quiet 0.0166, miss 0.150 | **RINGS 1.093**, miss 0.187 |
| **`R(15°) = −0.23`** (crossing-correct) | quiet 0.0218, **miss 0.172** | quiet 0.0254, miss 0.115 |

The off-diagonal cell does **not** bite: a crossing-tuned scalar leaves a **+0.20** residual at
boresight and the static engagement is fine.

⭐ **THE MECHANISM OF THE ASYMMETRY — state it, do not report it as an anomaly.** At `look ≈ 0` the
ripple term `A·(1 − cos(k·look))` vanishes **identically**, so `R(0) = R₀` for every `A`: **the
boresight engagement is STRUCTURALLY insensitive to the curve.** And the compensator's spurious
feed-forward `−R̂·cos(look_az)·ω_y` needs body rate to act on, which a benign static intercept does
not supply. (Slice 27's de-tune threshold, +0.15 → 31.4 m, was measured on ITS wire and does not
transfer: here over-compensation only starts costing at `R̂ = −0.50`, residual +0.46 → miss 5.8 m.)

⭐ **THE REFRAME IS THE BETTER SLICE, because it is asymmetric and ACTIONABLE:**

> The payload is NOT "no scalar works". It is **"the scalar that works is set by the ENGAGEMENT, not
> by the radome"** — and the actionable half is that **characterizing at BORESIGHT is the dangerous
> choice** (exactly right where the curve is flat, wrong where the loop is closed), while
> characterizing at the operating look angle is safe in BOTH.

⚠ **AND THE SCOPE OF "SAFE IN BOTH" IS MEASURED, NOT HEDGED (P10).** It survived every margin
removal tried: `n_pn` = 8/12/16 and static `Y` = 2000/4000/6000 all keep the crossing-tuned scalar's
static miss at 0.15–0.40 m with no ring. ⭐ It broke only in the OTHER direction: at `n_pn = 20` the
**boresight-tuned** arm rings even the STATIC engagement (`rms r` 0.789), because the launch
transient itself swings the look angle to ~10° where the glass is steep — **"static" means the look
angle SETTLES at zero, not that it is always zero.** Off-wire, named, not shipped as the lesson.

### 6. ⭐ THE SECOND ISOLATION: THE CHANNEL SPLIT (P2, P3)

With the lead in AZIMUTH and `look_el ≈ 0` (§1), the two seeker channels sit at **different points on
the same glass**: yaw at `R(look_az) ≈ −0.09`, pitch at `R(0) = R₀ = −0.03`. Measured (P3 A1):
`rms r` **0.808** with `rms q` only **0.106**.

⭐ **A CONSTANT SLOPE CANNOT PRODUCE THIS**, and that is what makes it evidence rather than an
observation: P2's constant-`R` arms ring BOTH channels together (`q` 0.783 / `r` 0.713 at
`R = −0.07`) because both channels share one slope. One radome, two channels, two operating points.

### 7. ⚠ THE METRIC IS `rms r` IN A RANGE BAND — A DELIBERATE DEPARTURE FROM 26/27 (P4, P7)

Slices 26/27 used `rms q` (pitch). **This slice uses `rms r` (yaw) as the headline**, with `rms q`
reported beside it as the §6 channel-split evidence. The reason is measured, not stylistic: the
lead is in azimuth, so the ring is in yaw. Write it as an explicit departure with its reason (the
slice-25 precedent), never as "the arc's metric, continued".

⚠ **THE WINDOW IS A RANGE BAND `[500, 3000] m`, NOT A TICK FRACTION.** Two defects it fixes, both of
which would otherwise have entered the plan as physics:
- On a crossing wire `rms r` carries a LEGITIMATE baseline — the missile turning onto the collision
  course, which is front-loaded. Over the whole approach that baseline is **0.172**; in the band it
  is **0.0138**. A settled constant-velocity intercept is a straight line.
- Arms with different ToF would otherwise compare **different parts of the engagement**. A fixed
  range band is identical across arms.

⚠ **QUOTE THE WINDOW WITH EVERY NUMBER** (slice 26's two-windows-two-ratios rule).
⚠ **rms, NEVER the peak** (slice 26: peaks overlap across the threshold).
⚠ **THE MISS IS NOT THE METRIC** — the ringing arms still HIT (0.19–1.7 m), exactly as in 26/27.

### 8. KNOBS: `A` AND `R̂`; `R₀` AND `k` AUTHORED (P5.3, P9.3, P9.4)

**KNOB 1 — `radome_ripple` (`A`), the new one.** Onset between `A = −0.025` (0.0137, quiet) and
`A = −0.03` (0.801, rings) at the shipped wire; rises and PLATEAUS (1.042 / 1.093 / 1.072 / 1.085 at
−0.05 / −0.10 / −0.15 / −0.20). ⭐ `>30°` = **0.0% across the entire range** — unlike the `k = 8.2`
/ vy = 300 wire, where the model-validity budget blew (5.3% at `A = −0.06`, 17.1% at −0.10) and
would have bounded the domain. The MISS starts growing past `A ≈ −0.15` (2.1 / 3.6 / 4.4 m at
−0.15 / −0.20 / −0.30) ⇒ **declare `A ∈ [−0.10, 0]`**, a measured plateau with ~1.5× margin to the
miss growth, and SAY that rather than implying the endpoint is physical.

**KNOB 2 — `radome_slope_est` (`R̂`), slice 27's, inherited.** At the shipped `A` the ring dies as
`R̂` is dragged toward `R(look_op)`; at `A = −0.10` the crossing is between −0.10 (0.993, rings) and
−0.17 (0.171, quieting), quiet by −0.25. ⚠ Its FLOOR is UI framing, not physics — de-tuning does
not bite until `R̂ = −0.50` (residual +0.46, miss 5.8 m), well outside. Its CEILING (0.00) is
physical, as in slice 27.

**AUTHORED, NOT KNOBS:**
- **`R₀` = −0.03** (the boresight slope) — a GOOD radome on slice 26's scale, deliberately: the
  lesson is that good glass at boresight is not good glass everywhere.
- **`k` = 12** (a 30° ripple period) — ⚠ **DISQUALIFIED as a knob by NON-MONOTONICITY**: at held
  `A = −0.05` the metric goes quiet / rings / rings / marginal / **quiet** / rings at
  `k` = 4 / 6 / 8.2 / 12 / 16 / 24, because `k` decides WHERE ON THE WIGGLE the operating look angle
  lands. That is the [[ewsim-df-ellipse-sigma-monotonicity]] rule (slices 19, 22) applying for the
  4th time. It is also *why* `k = 12` was chosen — it is the value that puts a quiet zone inside the
  valid speed band, which is what makes §2's isolation possible.

⚠ `n_pn` STAYS AUTHORED (slices 26/27 both disqualified it: it moves the loop gain the lesson is
about — the confounded-lever rule). `rho`, `af_alpha_max`, `sigma_seek` DISQUALIFIED as in 26/27 and
asserted ABSENT in the gate.

### 9. KNOB vs RUNG, AND THE BUTTON STAYS DROPPED

`A = 0` must be **bit-identical to the ripple not existing** — measured, not argued (slice 26's
`R = 0` precedent, atmosphere.jl's discriminator). That makes it a KNOB. ⚠ The identity is
STRUCTURAL: `A = 0` (or the key absent) routes to `radome_error` **VERBATIM**, never to the ripple
kernel evaluated at zero amplitude — `x + 0.0` is not the identity at `x = −0.0`, and float
non-associativity applies (the slice-20/21/26/27 shape).

The button stays DROPPED — slice 26's `radome_view` marker inherited unchanged; fourth slice in this
family (16, 26, 27, 28) whose lesson is sliders with no button. ⚠ NOT zero client code: one HUD line
for the LOCAL slope `R(look)` and the look angle, because a student who drags `A` while the quantity
that moved is invisible has not been shown anything (slice 27 ate that defect once).

### 10. CLASS 4a, AND THE BOUNDARY CONSTANT IS GEOMETRY-DEPENDENT

Class **4a** — draw-invariant (2 `randn`/tick, ripple or not: the curve is arithmetic on state that
already exists) yet trajectory-changing. FOURTH consecutive RNG-live slice (25, 26, 27, 28); the
seed is load-bearing and conventions 3/11 apply. Draw-count identity ASSERTED, not assumed.

⚠ **A NAMED APPROXIMATION, STATED NOT SWEPT: slice 26/27's `N·|R − R̂|/ρ ≈ 0.38` IS NOT
GEOMETRY-FREE.** P2 measured the constant-`R` onset at `|R_crit| ≈ 0.065` on the crossing wire
(⇒ ≈ 0.52) against ≈ 0.05 static (⇒ ≈ 0.40), **with no curve involved at all**. So 0.38 was measured
on ONE geometry. What transfers is the **form** of the law — a threshold on `N·|R(look) − R̂|/ρ` —
not the number. Say that plainly; it is a finding, not an embarrassment, and it does NOT weaken §2
(whose controls hold the geometry's contribution fixed by construction).

---

## Gate plan

### Gate 1 — the pure kernels

`frames.jl` gains TWO functions beside `radome_error` / `radome_compensation`:

```julia
radome_slope_curve(slope0, ripple, k, look) -> R          # R₀ + A·(1 − cos(k·look))
radome_error_curve(slope0, ripple, k, look_az, look_el) -> (ε_az, ε_el)
#   ε(u) = slope0*u + ripple*u − (ripple/k)*sin(k*u), applied per angle
```

`k` is clamped at a positive floor at the consumer (convention 5: a live knob can never throw, and
`ripple/k` at `k = 0` is a real crash path — the slice-21 `H` floor precedent).

Teeth (`test_frames.jl`, beside slice 26/27's):

- ⭐ **THE INTEGRAL IDENTITY**: finite-difference `radome_error_curve` in `look` and compare to
  `radome_slope_curve` at several look angles, tight `atol`. This pins the two kernels TO EACH OTHER
  rather than restating either formula, and it is what makes "the loop feels the derivative" a
  statement about the shipped code.
- ⭐ **THE SIGN TOOTH — the #1 SIGN TRAP's 10th occurrence — MEASURED AT TWO DIFFERENT LOOK ANGLES.**
  On slice 26's FROZEN geometry, the parasitic coefficient must MOVE with look angle and match
  `radome_slope_curve` at each. ⚠ A test at ONE look angle passes for a constant-slope kernel too
  and would prove nothing.
- `ripple == 0` reduces to `radome_error` **bit-for-bit** (`==`, not `≈`) at several look angles,
  PAIRED with a does-curve case (the slice-26 shape).
- `R(0) == slope0` **exactly**, for several ripple amplitudes — §5's mechanism, as a tooth.
- ODDNESS: `ε(−u) == −ε(u)` bit-for-bit; boundedness `R ∈ [R₀, R₀+2A]` over a look sweep.

### Gate 2 — the wired seam

`_observe_point3d!` (`missile.jl`): the `_rad_on` branch chooses the CURVE kernel when
`haskey(c, :radome_ripple)`, else `radome_error` VERBATIM (§9). ⚠ Rung-gated on the LIVE
`:airframe === :six_dof`, never on `haskey(:att_q)` — the slice-21/23/26/27 latent-bug class, whose
FIFTH occurrence this would be.

Loader (`scenario.jl`): `seeker.radome_ripple` and `seeker.radome_ripple_k`, validated finite and
`k > 0` at LOAD. Presence of `radome_ripple` is what mints the key.

Telemetry (all scalars, `_finite*`, shipped only while live):
- `radome_slope_local` — ⭐ `R(look)` this tick, THE quantity the lesson is about.
- `radome_residual_local` — `R(look) − R̂`, what actually closes the loop.
- ⚠ `radome_residual` KEEPS ITS SLICE-27 MEANING (`R₀ − R̂`) so a slice-27 wire stays byte-identical;
  the new key is ADDED beside it, never redefined.

Determinism: draw count still exactly 2/tick; `A = 0` bit-identical to the key absent; slices 1–27
byte-identical, proven ON THE WIRE by re-running the 25/26/27 verifiers to the digit.

### Gate 3 — scenario + the four proofs

`scenarios/slice28_radome_curve.yaml`: slices 23–27's missile with `n_pn` authored, `R₀ = −0.03`,
`k = 12`, `A = −0.05` (⚠ **the showcase opens on the disease** — the slice-25/26/27 shape), `R̂ = R₀
= −0.03` (boresight-characterized, the natural and wrong choice), and **a CROSSING target,
`vel = [0, 200, 0]`** with §1's measurement quoted as the reason.

The four proofs (convention 14):
- `slice28_verify.gd` — phases: the RIPPLE-vs-`A=0` split on `rms r` in the range band; ⭐⭐ the
  NON-MONOTONE crossing-speed sweep with both controls (§2); the matched-secant/derivative triple
  (§3); the CHANNEL SPLIT (§6); `A = 0` bit-identical replay.
- `slice28_ui_test.gd` — a TEN-way value guard (16/17/18/19/23/24/25/26/27/28) + the slice-27 HUD
  mirror; the button stays dropped, proven at BOTH client sites.
- `Sandbox.tscn` headless smoke-load → `DONE`.
- TWO windowed shots at the same range: the boresight-characterized arm RINGING with `R(look)`
  displayed far from `R̂`, and the same glass quiet once `R̂` is dragged to `R(look_op)`.

⚠ Verifier discipline inherited: assert one-sided; INTERPOLATE measured values into the pass text
(slice 25); `%g`/`%.2e` are NOT GDScript specifiers and an unknown one makes the whole `%` fail
silently on a GREEN run (slices 21, 25); a HIT samples COARSELY, so never compare two frame-sampled
CPAs (slice 27).

---

## Named deferrals (write them down; do not let them leak into this slice)

- **LOOK-ANGLE-SCHEDULED `R̂(look)` — SLICE 29.** The engineering answer to this slice, exactly as 27
  was to 26. Its single-point version is already measured here (P7.5, P9.4: a scalar tuned to
  `R(look_op)` quiets the wire). ⚠ It inherits slice 26's P7A obstacle if the schedule is to be
  learned rather than authored.
- **A 2-D SLOPE `R(look_az, look_el)`** — this slice applies ONE scalar curve per axis. Real glass
  varies over the aperture in two dimensions.
- **AN ASYMMETRIC ERROR CURVE** — `ε` here is ODD (a symmetric radome). A manufacturing asymmetry
  breaks that and makes the crossing DIRECTION matter.
- **AN IMPERFECT GYRO** (noise / bias / scale-factor) — still open from slice 27, unchanged.
- **ESTIMATING `R̂` IN FLIGHT** — still blocked by slice 26's P7A, unchanged.
- **SEEKER FOV / GIMBAL LIMIT** — sharper here than ever: this slice makes the look angle the
  quantity the whole lesson turns on, and a real seeker cannot hold 30° indefinitely.
- **THE OUT-OF-PLANE MANEUVERING TARGET** (slice 24 route (b)) — this slice's crossing target is
  constant-velocity; a MANEUVERING one would sweep the look angle through the curve *faster*.

---

## Task checklist

- [x] Gate 0 — the look-angle-band hunt; 10 probes; FINDINGS above; two advisor passes (the
      confound catch that forced §2, and the payload refutation that produced §5's reframe).
- [ ] Gate 1 — `frames.jl` `radome_slope_curve` / `radome_error_curve` + `test_frames.jl` teeth.
- [ ] Gate 2 — the `_observe_point3d!` seam + loader keys + telemetry; byte-identity on the wire.
- [ ] Gate 3 — scenario + the four proofs; the 25/26/27 verifiers re-run to the digit.
- [ ] Docs — `docs/STATUS.md` as-built, `CLAUDE.md` status line, `HANDOFF.md` §11, memory.
