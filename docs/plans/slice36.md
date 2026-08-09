# Slice 36 — THE HANDOVER BASKET: THE CHEAPEST PLACE TO HAND A SEEKER ITS TARGET IS NOT AT THE TARGET (§11 Tier-A)

The FOURTEENTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro, 32 = the seeker's field of view, 33 = the ring as
an FOV budget item, 34 = the gimbal, 35 = a rate-limited head), and the deferral slice 32 named as
its P5, slice 34 PROMOTED to a live constraint, and slice 35 SHARPENED into the strongest remaining
candidate of the family:

> *"**THE HANDOVER BASKET as an authored quantity** — slice 34's first deferral, and §0.4 SHARPENS
> it: the acquisition transient is the largest slew demand in the whole engagement (~40 °/s against
> the ring's ~60) and it is entirely a property of how the head is handed over. A caged head would
> make it larger still. This slice gates it away with the band; that slice would make it the
> subject."*
> — `docs/plans/slice35.md`, Deferred (NAMED)

**Status: GATE 0 COMPLETE (2026-08-10, 5 probes). Gates 1–3 NOT STARTED.**
⚠⚠ **THE BANKED FRAMING WAS REFUTED AND SO WAS ITS REPLACEMENT, AND BOTH REFUTATIONS ARE
LOAD-BEARING.** (1) The advisor's opening hypothesis — *a badly handed-over head RINGS LESS, because
it indexes shallower glass* — is measured with the OPPOSITE sign and non-monotone at the loud arm
(§0.3); slice 34's contrary number sits AT THE ONSET BRACKET, the one place in this arc where `rms r`
is knife-edge, and no reconciliation probe is owed. (2) The advisor's own ordering then forced the
discriminating probe FIRST, and it came back saying **slice 35's [500, 3000] m band gate removes this
slice's entire subject** (§0.1) — acquisition is over by r ≈ 4900 m — so no band metric may carry the
claim. (3) And the mechanism's first story was wrong too: the body-frame LOS was inferred from
`head_max` to settle 18.1° → 15.2°, and `head_max` is a `hypot` that cannot show a sign. Logged
directly it **crosses through zero to −15.15°, a 33.2° EXCURSION** (§0.4). The live claim is in a
FOURTH place, and it is better than any of the three: **the requirement has an OPTIMUM, and the
optimum is not zero.**
Probe scripts and the full measured tables in `M:\claud_projects\temp\slice36\`
(`g0_results.md`, `lib36.jl`, `p1_band.jl`, `p2_where.jl`, `p2b_break.jl`, `p3_swap.jl`,
`p4_optimum.jl`, `p5_wire.jl`).

⭐ **ZERO CORE PATCH AT GATE 0, AND THAT IS A PROPERTY OF THE SEAM RATHER THAN A TRICK.**
`_observe_point3d!` mints `:head_az` **only when the key is absent** (`missile.jl:1722`), so
pre-seeding the comp dict skips the shipped truth handover and the head is born wherever the probe
authors it. Unlike slice 35's gate 0 there is no uncommitted kernel patch to apply and revert, and
every number below is therefore a statement about what already flies. ⚠ The seed is `head_clamp`ed
exactly as the handover is (slice 34 gate 1 Finding 2 — the servo contracts toward the target ONLY
FROM INSIDE the disc, and the handover is the one place a head can be born outside it).

---

## The one-paragraph statement of the lesson

Since slice 34 the head has been handed its target **perfectly**: tick 1 initialises it to the
clamped truth look angles, a truth read on a path whose whole thesis is that the head never sees
truth. Slice 34 measured that this is load-bearing rather than a nicety, and wrote it down as a
stated §1 condition; slice 35 found that a rate limit makes the resulting acquisition turn the
LARGEST slew demand in the engagement, and gated it away with a range band and a deliberately wide
window. Slice 36 makes the handover itself an authored quantity — the head is born `err` degrees off
the true line of sight — and the question that was gated away turns out to have an answer nobody in
the arc predicted. **The window a seeker needs is not `|err|`.** The body-frame LOS is not a fixed
target: over the approach it travels **+18.11° → −15.15°**, a 33.2° excursion, as the missile swings
its nose onto the collision course. A head handed over ON the LOS must chase that entire journey, and
a rate-limited servo falls **12.35°** behind doing it; a head handed over 8° along the journey never
falls further behind than the 8° it started with. So the requirement is a **V** — its left arm the
handover error itself (the tick-1 peak, before the servo has done anything), its right arm the chase
cost — and the cheapest basket sits at the **kink**, which is not at zero and which the servo moves.

> **THE LESSON, IN ONE SENTENCE.** The cheapest place to hand a seeker its target is not at the
> target — it is part-way to where the target is *going*, and how far depends on how fast a servo
> you bought.

⭐⭐ **AND THE SHOWCASE IS A BASKET THAT EXCLUDES THE PERFECT HANDOVER.** At an 8 °/s servo behind a
10° detector window, a head handed over *exactly right* loses its track at t = 0.434 s and misses by
**3290 m**, while the same head handed over **8° WRONG** holds all the way in and hits at **0.191 m**
— and so does 4° and 6° wrong, while 10° wrong breaks again the other way. Too little bias breaks
the track and too much bias breaks it. The set of handover errors that work is a genuine *basket*,
and **zero is outside it**.

⚠ **THIS IS NOT SLICE 33's SECOND TERM AND IT IS NOT A RADOME CLAIM.** The break is GLASS-FREE:
err −18 / window 15 misses by **3620.131 m WITH the glass and 3620.675 m WITHOUT it** — 0.5 m apart
on a 3.6 km miss (§0.6). The budget slices 32 and 33 built now has a third term, and it is the
largest of the three:

    window ≥ the ENGAGEMENT's lead (32) + the LOOP's excursion (33) + THE HANDOVER BASKET (36)

⚠ **NO NEW CAP, NO NEW RUNG, NO NEW INSTABILITY, NO NEW DRAW.** What is new is one comp key, an
authored quantity where there was a truth read, and the finding that its optimum is not zero.

---

## §0 — Gate 0 (5 probes, 2026-08-10)

Every probe flies the SHIPPED `EWSim.Seeker` off the real comp keys. The wire is
`scenarios/slice35_rate.yaml` to the digit (seed 32, crossing target vy = 200, τ = 0.05, stop 30°),
with the glass, the window and the servo rate as parameters.

### ⚠⚠ §0.1 — THE DISCRIMINATING PROBE, RUN FIRST: SLICE 35's BAND GATE REMOVES THE SUBJECT

The advisor's ordering, and it decided what the slice IS. `r_acq0.5` — the range at which the
tracking error first falls below 0.5° — is **4937–6437 m in all 28 arms**. Slice 35's [500, 3000] m
band begins *after* acquisition is over. `off_band` at the loud arm is 7.496 (err 0) against
7.40–7.52 across ±18°, and on a NO-GLASS wire it is a bit-identical **0.0308 for every error**.

⇒ **NO BAND METRIC MAY CARRY THIS CLAIM.** The headline is whole-approach and the metric is the MISS
(slice 32's shape, not slice 33/35's). ⚠ This is the inverse of the usual caution: 26–35 all had to
gate the launch transient AWAY to see their loop; here the launch transient IS the subject, and the
band that protected them deletes it.

### ⭐ §0.2 — AND THE ISOLATION FELL OUT OF THE SAME PROBE, STRONGER THAN EXPECTED

On a NO-GLASS wire with a free window, a handover error is **EXACTLY INERT** on the trajectory:
miss **0.191**, rms r **0.01589**, `off_band` **0.0308**, identical across every error at every rate
(30 cells, §0.5's Table A). ⇒ the basket reaches the trajectory through the **WINDOW** or through the
**INDEX** and through nothing else — slice 35's isolation shape in a new quantity, and it is what
licenses dropping the glass (§0.6).

### ⚠⚠ §0.3 — REFUTATION 1: THE OPENING HYPOTHESIS, MEASURED WITH THE OPPOSITE SIGN

Slice 34 §0.8 recorded a CAGED head (err ≈ −18°) as QUIETER — rms r 0.26719 against the handover's
0.35338 at R̂ = −0.16 — which suggests *a badly handed-over head indexes the glass at a smaller look
angle, so on ripple glass with A < 0 it sees a shallower slope and rings less* (slice 28's mechanism
running in the handover's favour). **It does not reproduce.** At rate 40 / window 25:

| R̂ | err −18° | err 0 | err +18° |
|---|---|---|---|
| −0.33 | 0.07254 | 0.05890 | **0.04943** |
| −0.18 | 0.01465 | 0.01172 | **0.01070** |
| −0.03 (loud) | 0.87359 | 0.86288 | 0.88826 |

The sign is the OTHER WAY at both quiet arms (1.47× and 1.37×) and NON-MONOTONE at the loud one.
⚠ Slice 34's number was measured AT THE ONSET BRACKET, the one place in this arc where `rms r` is
knife-edge — which is exactly why slice 34 quoted a bracket and not a number. **Written as
measured-and-refuted; no reconciliation probe is owed** (advisor, second call, correcting its own
first). Nothing in this slice is built on the ring.

### ⭐⭐ §0.4 — REFUTATION 2: THE MECHANISM'S FIRST STORY WAS WRONG, AND MEASURING IT PROPERLY IS THE SLICE

The signed asymmetry in §0.5's Table A was first attributed to the body-frame LOS *settling* from the
handover angle 18.1° down to a sustained lead ~15.2°. That was inferred from `head_max` — **a `hypot`,
which cannot show a sign** (the #1 SIGN TRAP's 10th occurrence, in a diagnostic rather than a kernel).
Logged directly on the err = 0 / no-glass arm, `look_az_b` runs

| t (s) | 0.001 | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| vy = **+200** | **+18.11** | −1.93 | −8.67 | −12.12 | −13.85 | −14.67 | −15.00 | −15.12 | **−15.15** |
| vy = **−200** | +18.10 | +16.55 | +16.12 | +15.93 | +15.90 | +15.94 | +16.00 | +16.12 | — |

It **CROSSES THROUGH ZERO — a 33.2° excursion**, not a 3° settle. And against the reversed crossing
the same quantity is nearly STATIC (a 2.2° swing). ⇒ the quantity that sets the requirement is **the
body-frame LOS EXCURSION**, and the crossing sign sets it.

**THE PREDICTION AND WHAT IT ACTUALLY DID.** The advisor's test was that reversing the crossing must
SWAP the good and bad sides. It does not — **the asymmetry VANISHES**, which is stronger. `off_max`
ratio (8 °/s ÷ 40 °/s), free window, no glass:

| err_az | −18 | −10 | −5 | 0 | +5 | +11 |
|---|---|---|---|---|---|---|
| vy = **+200** | 1.00 | 1.00 | **1.76** | **5.68** | **3.18** | **2.03** |
| vy = **−200** | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

⇒ **THE RATE-DEPENDENCE OF THE BASKET REQUIREMENT IS CREATED ENTIRELY BY THE ENGAGEMENT'S OWN LOS
EXCURSION.** Against a crossing that leaves the LOS still in the body frame, a handover error costs
EXACTLY ITSELF at every servo rate and the servo is irrelevant. ⚠ That control arm is what makes this
a statement about the ENGAGEMENT rather than about handover errors, and it must ship as a tooth.

### ⭐⭐ §0.5 — WHERE THE LIVE CLAIM IS: THE OPTIMUM IS NOT ZERO, AND THE SERVO MOVES IT

`off_max` (deg), NO GLASS, FREE window, 16 × 5 cells per crossing (`p4_optimum.jl`). vy = +200:

| err_az | 60 °/s | 40 | 25 | 15 | 8 |
|---|---|---|---|---|---|
| −18 … −8 | exactly \|err\| | \|err\| | \|err\| | \|err\| | \|err\| |
| −6 | 6.0000 | 6.0000 | 6.0000 | 6.0000 | 8.0907 |
| −4 | 4.0000 | 4.0000 | 4.0000 | 5.0995 | 9.4999 |
| −2 | 2.0000 | 2.0000 | 3.4277 | 6.2143 | 10.9707 |
| **0** | 2.1119 | 2.1728 | 4.0746 | 7.2228 | **12.3460** |
| +12 | 11.8875 | 12.2936 | 15.1840 | 18.7483 | 24.0790 |
| **ARGMIN** | **−2** | **−2** | **−2** | **−4** | **−8** |
| **MIN** | 2.0000 | 2.0000 | 3.4277 | 5.0995 | **8.0000** |
| **SAVING vs err = 0** | 1.06× | 1.09× | 1.19× | 1.42× | **1.54×** |

CONTROL, vy = −200: ARGMIN **+0.0 at every rate**, MIN **0.2028 at every rate**, SAVING **1.00× at
every rate**, requirement exactly `|err|` in all 80 cells.

⭐ **THE SHAPE IS A V AND BOTH ARMS ARE EXPLAINABLE FROM FIRST PRINCIPLES**: the left arm is `|err|`
EXACTLY — the tick-1 peak, before the servo has done anything — and the right arm is the CHASE COST,
the servo falling behind a receding LOS. The requirement is their **max**, the optimum is the
**KINK**, and a slower servo pushes the kink further along the LOS's journey. ⚠ The two arms come
from DIFFERENT mechanisms (an initial condition and a bandwidth), which is why the minimum is a
genuine trade and not a fitted curve.

⚠ **THE POSITIVE DOMAIN IS BOUNDED BY THE 30° STOP, NOT BY TASTE.** The perfect handover is +18.105°,
so **+11.9° is where a head is born ON the stop**: `off_max` saturates at 11.8902 for any larger
authored error and `head_max` reads 29.113 at +11. The signed domain is physically asymmetric —
**[−18.1 (CAGED), +11.9 (STOP)]** — and the two endpoints are the arc's own two degenerates.

### ⭐⭐ §0.6 — THE SHOWCASE CELL, AND WHY THE WIRE HAS NO GLASS

NO GLASS, servo 8 °/s, vy = +200, window **10.0°** (`p5_wire.jl`):

| err_az | 0 | −2 | −4 | −6 | −8 | −10 | −12 | −18 |
|---|---|---|---|---|---|---|---|---|
| %out | 94.6 | 92.3 | **0.0** | **0.0** | **0.0** | 100.0 | 100.0 | 100.0 |
| miss (m) | 3290.1 | 2965.5 | **0.191** | **0.191** | **0.191** | 3620.7 | 3620.7 | 3620.7 |
| `aero_sat` / `defl_sat` | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |

**TOO LITTLE BIAS BREAKS THE TRACK AND TOO MUCH BIAS BREAKS IT, AND ZERO IS OUTSIDE THE BASKET THAT
HOLDS.** `aero_sat` and `defl_sat` are **0.0 on every row** ⇒ slice 32's POINTING-miss isolation,
clean on BOTH sides of the basket — full authority, no idea where to point it.

⚠⚠ **THE LOUD-GLASS TWIN DOES NOT REPRODUCE IT CLEANLY** — `aero_sat` runs 27–48 % on the broken rows
and there are two anomalous ~140 m partial rows at −8/−10 — so on a glass wire the isolation would
discriminate in NEITHER direction (slice 33's inversion). Combined with §0.2's exact inertness and
convention 9, **THE WIRE IS NO GLASS: the first since slice 25, and the first of this arc.** The
break itself is glass-INDIFFERENT and that is the tooth that proves the drop is legitimate rather
than convenient: err −18 / window 15 misses **3620.131 m with the glass and 3620.675 m without**.

### ⚠ §0.7 — THE PREDICATE RETURNS, IN A THIRD CURRENCY

`held ⟺ requirement < window` holds in EVERY cell of both break tables (`p2b_break.jl`, 48 arms,
requirement read on a FREE-window arm and the verdict on the WINDOWED one):

| err | rate | requirement | window 25 | 15 | 8 |
|---|---|---|---|---|---|
| 0 | 40 | 2.17 | held | held | held |
| 0 | 8 | 12.35 | held | held | **BROKE** 3154.6 m |
| −18 | 40 | 18.00 | held | **BROKE** 3620.7 | **BROKE** |
| +5 | 8 | 17.19 | held | **BROKE** 3420.2 | **BROKE** |
| +11 | 40 | 11.41 | held | held | **BROKE** 3201.8 |
| +11 | 8 | 23.19 | held (23.19 < 25) | **BROKE** | **BROKE** |

Slice 32 measured `held ⟺ lead < fov`; slice 34 re-measured it as `tracking error < detector window`;
slice 35 wrote that on a rate-limited arm it is *"a statement about the HANDOVER BASKET, which is
slice 34's FIRST named deferral and a different slice."* **This is that slice, and the statement is
measured.**

---

## What ships (gates 1–3, PLANNED)

### The core (gate 1)

ONE new comp key, `gimbal_handover_err_deg` (SIGNED, degrees at the wire boundary — the
`gimbal_stop_deg` / `gimbal_fov_deg` / `gimbal_rate_dps` posture; the seam converts once). The
handover branch at `missile.jl:1735` gains the offset, and **the offset is applied INSIDE
`head_clamp`** — never after it, or a head can be born outside its own stop.

⚠⚠ **THE BIT-IDENTITY CONTROL IS THE ABSENT KEY, NEVER `= 0.0`** (slice 35's blocking pin, verbatim,
and it was measurably right there). Structure it as a separate branch gated on `haskey`, with the
else-arm slice 34/35's line TEXTUALLY UNCHANGED — never `head_clamp(look_az_b + err, …)` trusting
`err = 0` to be inert, because `-0.0 + 0.0` is `+0.0` (the trap 20/21/26 all name). **MEASURE that
`= 0.0` is or is not bit-identical to absent; do not assert it.**

⚠ Whether the error needs its own KERNEL is gate 1's to decide and to say why. The candidate is that
it does not — it is an argument to an existing clamp — in which case gate 1 is a SEAM edit and
`frames.jl` is untouched, which would make every prior slice bit-identical BY CONSTRUCTION (slice
35's gate-1 shape inverted).

### The seam + loader (gate 2)

* Telemetry: the SIGNED authored error, and the REQUIREMENT as a running maximum
  (`head_off_peak_deg`) — ⚠ slice 27's peak-hold shape, because the requirement is a *max over the
  approach* and an instantaneous readout cannot show it. The margin against the window is slice 33's
  SIGNED `seeker_fov_margin_deg` shape: **the sign is the verdict.**
* Loader: validate the error against the STOP (a head authored beyond its own stop is silently
  clamped today — a degenerate the loader would permit; slice 35's post-review commit shape is to
  prove it LOADS and is never FLOWN, or to refuse it).
* ⚠ `radome_slope_est` **cannot be knob 2** — it is DEAD on a no-glass wire (the slice-19 dead-knob
  class). The knobs are `gimbal_handover_err_deg` and slice 35's `gimbal_rate_dps`; the verifier must
  assert the GLASS keys ABSENT the way slice 35 asserted its disqualified ones.
* Convention 9 by MEASUREMENT, not by counting sliders (slice 27's diagonal): §0.5's table already
  shows the two knobs are ONE axis — the servo *moves the optimum of the basket* — and slice 35 is
  the `err = 0` row of that same grid.

### The wire (gate 3)

`scenarios/slice36_handover.yaml`: slice 35's wire **MINUS THE GLASS**, servo authored at 8 °/s,
window authored ~10°, `gimbal_handover_err_deg` and `gimbal_rate_dps` the two sliders.

⚠⚠ **THE WINDOW'S NUMBER MUST BE RE-AUTHORED ON THIS SLICE'S OWN FINE GRID** (the advisor's blocking
point, and slice 35's own gate-3 finding): the requirement is NON-MONOTONE in both sliders, so a
corner sweep is not evidence about the interior. And ⚠ **the window and the stop are within ~2° of
binding at the same corner** (+11 / 8 °/s: requirement 23.19 against a 25° window, `head_max` 29.11
against a 30° stop) — slice 34's gate 2 already found the two are ONE budget, so either the window
carries measured margin over the whole domain or the positive domain is bounded below the stop and
**the plan says the stop is what bounds it.**

⚠⚠ **THE TWO-RUN DISCIPLINE GAINS A FIFTH QUANTITY, AND IT FAILS IN THE OPPOSITE DIRECTION TO SLICE
34's.** On a never-acquired arm `off_max` reads **65–120°** — the post-break runaway, LARGER than any
real requirement — where slice 34's `head_angle_deg` froze plausibly-but-TOO-SMALL. A reader of the
break table will take those numbers for requirements; the verifier must read every requirement off a
FREE-window arm and say so in the file.

⚠ **MARKER RE-CHECK (slice 35's INVISIBLE-SLICE class, and it must be RUN, not inherited).** A
slice-36 wire is a slice-35 wire minus the glass plus one key, so `gimbal_rate_view` routes it and
the SUBJECT is right — but slice 35's HUD meters the servo's duty against **the loop's** demand, and
there is no loop here at all. Expect a branch selector, not a hole plug, and expect the branch to be
checked BEFORE slice 35's.

### The four proofs (convention 14)

`net/slice36_verify.gd` (⚠ `STEPS` a MULTIPLE of `emit_every` — slice 31's silent hang), a
`slice36_ui_test.gd` with an ELEVENTH-way value guard, the Sandbox smoke-load, and TWO windowed shots
— the broken perfect handover beside the held biased one, at the same range.

---

## Deferred (NAMED)

* **A HANDOVER BASKET WITH A DISTRIBUTION** — this slice authors ONE signed error. A real handover
  has a covariance, and the design question is a Pk over the basket rather than a single arm.
* **MEMORY TRACK / RE-ACQUISITION** — unchanged from slice 34/35, and every break measured here is
  still TERMINAL. ⚠ SHARPENED: a memory track is exactly what would rescue the *too-much-bias* side
  of §0.6's basket, so it would make the basket ONE-SIDED. That is a real prediction and a real slice.
* **A SECOND-ORDER SERVO (ω_a/ζ_a)** — slice 35's own named successor, unspent.
* **THE ELEVATION HALF** — the error here is authored in AZIMUTH because that is where the lead and
  the excursion are (slice 28's channel split). An elevation basket is orthogonal to the excursion and
  §0.5 predicts it has NO optimum shift; measuring that is a tooth, not a slice.
* **A RECTANGULAR / PER-AXIS STOP**, **THE HEAD'S OWN GYRO** — slice 34's, unchanged and unspent.
* Everything 26–33 named and did not spend.
