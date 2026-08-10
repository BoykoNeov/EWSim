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

**Status: GATE 0 COMPLETE (2026-08-10, 8 probes — 5, then 3 more on the advisor's pre-gate-1 review).
GATE 1 COMPLETE (2026-08-10, 6876 → 6980 → 6988 post-review — see §1).
GATE 2 COMPLETE (2026-08-10, 6988 → 7057, +69 — see §2). Gate 3 NOT STARTED.**
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
⚠⚠ **AND THE PRE-GATE-1 REVIEW FOUND A FOURTH THING, WHICH CHANGED THE SCENARIO COUNT**: the new key
is STRUCTURALLY A DEAD KNOB (§0.9) — it is consumed once at tick 1 and never read again, so slice
19's NOT-A-DEAD-KNOB TRIPWIRE would FAIL on it. It is authored, not slid, and the slice ships **TWO
SCENARIOS** with slice 35's `gimbal_rate_dps` as the ONE live slider (slice 34's precedent exactly).
Probe scripts and the full measured tables in `M:\claud_projects\temp\slice36\`
(`g0_results.md`, `lib36.jl`, `p1_band.jl`, `p2_where.jl`, `p2b_break.jl`, `p3_swap.jl`,
`p4_optimum.jl`, `p5_wire.jl`, `p6_advisor.jl`, `p7_discriminator.jl`, `p8_trap.jl`).

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

⭐⭐ **AND THE BIAS BUYS SOMETHING SLICE 35 SAID COULD NOT BE BOUGHT.** Slice 35 shipped the arc's
first TWO-SIDED knob: servo bandwidth is not a window, so *"widen it — it's free"* stopped working
and there was no free direction to run in. On the err = 0 wire that is exactly what the requirement
does — it walks **2.112 → 12.346°** as the servo slows 60 → 8 °/s (5.8×), crossing a 10° window
between 12 and 10 °/s. On the err = −6 wire it reads **6.000 / 6.000 / 6.000 / 6.000 / 6.000 / 6.412
/ 8.091** over the same sweep: **held everywhere, and FLAT.** ⇒ **A CORRECTLY BIASED HANDOVER MAKES
THE SERVO RATE STOP MATTERING** — the left arm of the V is `|err|` exactly, an initial condition no
bandwidth touches, so biasing onto it moves the design off the two-sided knob altogether. That is
the free direction slice 35 could not find, and it is not on slice 35's axis. (§0.9)

⭐ **AND IT IS FREE IN ACCURACY, BIT-EXACTLY.** Every arm across the whole domain — −18° to +11°,
both servo rates, free window, *and* the windowed holding rows — returns the identical 64 bits
`miss = 0.19116048719212922` and the identical CPA position to 17 digits. Not "the same to three
decimals": `===`. The price of the bias is EXACTLY ZERO and the only thing a handover error can
change is whether the track is held at all — slice 32's asymmetry with the cost column at 0. (§0.2)

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

### ⭐⭐ §0.2 — AND THE ISOLATION FELL OUT OF THE SAME PROBE, STRONGER THAN EXPECTED — THEN STRONGER AGAIN

On a NO-GLASS wire with a free window, a handover error is **EXACTLY INERT** on the trajectory:
miss **0.191**, rms r **0.01589**, `off_band` **0.0308**, identical across every error at every rate
(30 cells, §0.5's Table A). ⇒ the basket reaches the trajectory through the **WINDOW** or through the
**INDEX** and through nothing else — slice 35's isolation shape in a new quantity, and it is what
licenses dropping the glass (§0.6).

⚠ **"IDENTICAL" AT THREE DECIMALS IS PRINTED AGREEMENT, NOT A MEASUREMENT** (advisor, pre-gate-1).
With no glass there is no bend, so the prediction is stronger than inertness-to-eye: the miss should
be **BIT-IDENTICAL**. Re-measured with `===` on the scalar AND on the full 3-D CPA position
(`p6_advisor.jl`), across err ∈ {0, −2, −4, −6, −8, −10, −18, +5, +11} × rate ∈ {40, 8}:

| quantity | value | across |
|---|---|---|
| `miss` | `0.19116048719212922` | **all 18 cells `===`** |
| `pos_cpa` | `(5999.8334218207992, 4185.714198674571, 4199.9621559124289)` | **all 18 cells `===`** |
| the WINDOWED holding rows (err −4/−6/−8, window 10°, 8 °/s) vs the free-window baseline | same bits | **`===`** |

⇒ **THE PRICE OF THE BIAS IS EXACTLY ZERO.** ⚠ Note what the third row rules out: it is not merely
that a *held* track flies the same, it is that a track held from a **10° window with an 8° bias**
flies bit-for-bit the same trajectory as one with an infinite window and no bias. Had any row
differed, there would be a head-angle→trajectory path unaccounted for; there is not.

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
HOLDS.** ⇒ slice 32's POINTING-miss isolation, clean on BOTH sides of the basket — full authority,
no idea where to point it.

⚠⚠ **THAT LAST ROW IS A `%5.1f` PRINT, NOT A MEASUREMENT, AND GATE 1 RE-READ IT AS COUNTS** (§1
Finding 4 — the class the advisor already caught once at §0.2, recurring in a second column). The
number behind a printed `0.0` runs up to 0.047 %. Read as counts over `r > 200` the picture is
STRONGER, not weaker: `defl_sat` is **EXACTLY 0** on every arm, and `aero_sat` fires on **exactly ONE
tick out of 7358–10579**, at **r = 6383 m — the same range on every arm that reaches it, independent
of the handover error**. It is the launch transient, and inside the arc's [500, 3000] m band both are
exactly zero. Quote the counts, never the percentages.

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

### ⚠⚠ §0.8 — THE REPARAMETERIZATION GATE, RUN BEFORE THE KEY IS WRITTEN: `gimbal_stop_deg` REACHES THE SAME RESCUE

The advisor's blocking check, and the arc's standing false-fidelity gate (15's `k_δ`, 19's dead
`speed`, 31's scale factor). The perfect handover is **+18.105°**, and the shipped handover is
`head_clamp`ed — so **authoring a 10° STOP already births the head at exactly 10.000°**, which is the
showcase's winning birth angle. Measured on the showcase cell (`p6_advisor.jl` §B):

| arm | birth° | %out | miss | `off_max` | `head_max` |
|---|---|---|---|---|---|
| stop 30, err **0** (the foil) | 18.117 | 94.6 | 3290.078 | 107.378 | 18.119 |
| stop 30, err **−8.105** (the ship) | 10.021 | **0.0** | **0.191** | 8.105 | **15.173** |
| **stop 10, err 0** (the alternative) | 10.000 | **0.0** | **0.191** | 8.132 | **10.000** |

**IT RESCUES IT.** Same verdict, same miss. So the objection is real and must be answered with a
measurement rather than with prose — slice 20's matched-ΔV shape exactly, where a parasitic drag
reproduced the miss and only the α²-SOURCE made it *induced*.

⭐ **ANSWER 1 — IT IS NOT ONE PARAMETER WEARING TWO NAMES, AND THE TELL IS IN THE TABLE.** Sweeping
each parameter over the SAME birth angles at a free window (`p7_discriminator.jl` §B):

| | route 1: `err` at stop 30 | route 2: `stop` at err 0 |
|---|---|---|
| birth 18.117° | `off_max` 12.3460 | `off_max` 12.3460 **at stop 30 AND stop 20 — bit-identical** |
| birth ~12° | 8.0907 (err −6) | **7.2684** (stop 12) |
| birth 10° | 8.1050 | 8.1321 |
| birth 4° | 14.0000 | 14.1321 |
| `head_max` | **15.173 — the LOS's own far excursion** | **`=== stop` on every row: PINNED** |

Two facts kill the equivalence. **(a) The stop's birth angle SATURATES at 18.117** — clamping only
ever moves a birth angle TOWARD zero, so *the entire right arm of the V is unreachable by the stop*,
and a positive handover error is a real thing a real handover does. **(b) `head_max === stop`
exactly on every stop row**: the stop does not *aim* the head, it **CAGES** it for the whole flight,
where the aimed head runs free out to the LOS's own 15.173°. They also reach different minima (7.27
vs 8.09) — two mechanisms overlapping on part of one arm, not one mechanism twice.

⭐⭐ **ANSWER 2 — AND THEIR VERDICTS PART IN BOTH DIRECTIONS.** Matched birth angle, window 10°,
servo 8 °/s, swept over the crossing (`p8_trap.jl`):

| birth | vy | AIMED (stop 30) | CAGED (stop = birth) |
|---|---|---|---|
| 10° | 260 | HELD 0.068 (`head_max` 19.591) | HELD 0.068 (10.000) |
| 10° | **275** | **HELD 0.214** (`head_max` 20.681) | **BROKEN 383.164** (10.000) |
| 10° | **285** | **HELD 0.166** (21.400) | **BROKEN 482.589** (10.000) |
| 10° | **295** | **HELD 0.116** (22.103) | **BROKEN 483.956** (10.000) |
| 10° | 305 | BROKEN | BROKEN |
| 12° | **260** | **BROKEN 3235.815** | **HELD 0.068** |
| 12° | **275** | **BROKEN 3125.306** | **HELD 0.214** |
| 12° | 285+ | BROKEN | BROKEN |

**THE CAP THAT AIMS YOU IS THE CAP THAT TRAPS YOU** — at a 10° birth the caged head is pinned at
exactly 10.000° while the LOS walks off it (the aimed head follows to 20.7–22.1°), so it breaks over
a whole band of crossings the aimed one survives. ⭐ And the 12° rows **REVERSE it**, which is the
better half of the finding: a cage also blocks the **WRONG-WAY CHASE**. A head born *below* the LOS
slews *upward* toward +18.1° for the first moments — the LOS has not turned around yet — and at
8 °/s that climb is unaffordable; the caged head cannot make it and is better placed when the LOS
comes down. ⇒ **NEITHER ROUTE DOMINATES**, which is a stronger separation than a one-directional one.
⚠ It also sharpens §0.5's right arm: part of the "chase cost" is chasing the LOS in the direction it
is about to stop going.

⚠ **THIS SHIPS AS A TOOTH IN `test_missile.jl`, NOT ON THE WIRE** — neither route is client-drivable
as a contrast (the stop is authored, and putting two of them on one scenario breaks convention 9).
Slice 28's precedent, and the relocation goes in the verifier header.

### ⚠⚠ §0.9 — THE KEY IS A DEAD KNOB, AND THAT SETS THE SCENARIO COUNT

`_observe_point3d!` mints the head **only when `:head_az` is absent**, and writes `c[:head_az]`
unconditionally at the end of every tick. So `gimbal_handover_err_deg` is **consumed exactly once, at
tick 1, and never read again** — dragging a slider on it mid-flight does nothing. This is slice 19's
`comp[:speed]` and slice 21's launch altitude verbatim, the **5th occurrence in this arc**, and it is
caught BEFORE the key is written rather than at gate 3. ⚠ Sharper: **slice 19's NOT-A-DEAD-KNOB
TRIPWIRE (verifier + `test_server` assert the knob MOVES a number) would FAIL on it.**

⇒ **THE PRECEDENT IS SLICE 34's, AND THE SLICE SHIPS TWO SCENARIOS** — `gimbal_tau_s` is authored
there for the same class of reason (no in-domain slider removes a head). Here: an **err = 0** wire
that breaks and an **err = −6** wire that holds, with slice 35's `gimbal_rate_dps` as the ONE live
slider. Convention 9 is satisfied by one live knob plus one authored contrast, not by counting
sliders.

⭐⭐ **AND THE SLIDER EARNS ITS PLACE — IT DOES SOMETHING DIFFERENT ON EACH WIRE** (`p7_discriminator.jl`
§C; window 10°, stop 30, vy 200, no glass):

| `gimbal_rate_dps` | 60 | 40 | 25 | 15 | 12 | 10 | 8 |
|---|---|---|---|---|---|---|---|
| **err = 0** `off_max` | 2.112 | 2.173 | 4.075 | 7.223 | 8.840 | 104.562 | 107.378 |
| **err = 0** verdict | HELD | HELD | HELD | HELD | HELD | **BROKEN 3338.3 m** | **BROKEN 3290.1 m** |
| **err = −6** `off_max` | 6.000 | 6.000 | 6.000 | 6.000 | 6.000 | 6.412 | 8.091 |
| **err = −6** verdict | HELD | HELD | HELD | HELD | HELD | **HELD 0.191** | **HELD 0.191** |

A crisp HELD→BROKEN transition inside the declared domain on ONE wire and none on the other, and the
`off_max` row on the biased wire is **flat at 6.000 over five of seven rates** — the left arm of the
V is an initial condition, and no bandwidth touches it. ⚠ The requirement's non-monotonicity means
the transition's location is a MEASURED bracket (between 12 and 10 °/s), never interpolated.

---

## §1 — Gate 1 (2026-08-10): the seam, and the decision NOT to write a kernel — 6876 → 6980

⭐ **THE DECISION, AND ITS REASON. NO KERNEL: `frames.jl` IS FUNCTIONALLY UNTOUCHED.** The offset is
an ARGUMENT to an existing clamp. `head_clamp` already owns the stop, the CAGED (`stop ≤ 0`)
degenerate, the NaN-stop degenerate and the sign of the returned zeros, so a `head_handover` wrapper
would have exactly ONE call site and would be a SECOND place for stop policy to drift — the trap
`missile.jl` already names for `off_axis_angle` and `head_slew`. ⇒ **every prior slice is
bit-identical BY CONSTRUCTION rather than by a measurement** (slice 35's gate-1 shape inverted): with
the key absent the seam runs slice 34/35's own line TEXTUALLY UNCHANGED, and the 34/35 testsets
re-running green IS that proof. The whole gate is ONE `haskey` branch in `_observe_point3d!` plus a
prose correction in `frames.jl` (Finding 3).

⭐⭐ **THE GO/NO-GO, RUN BEFORE ANY TEETH (the advisor's blocking item), AND IT LANDED `===`.** Gate 0
flew every table by PRE-SEEDING `:head_az`, which makes tick 1 take the **slew** branch (a no-op
toward itself); what ships takes the **handover** branch. The two agree only because `stop = 30° >
18.105°` makes `head_clamp` INERT on the reference, collapsing the probe's double clamp into the
shipped single one — a narrow condition, and if it had failed nothing in §0.2/0.5/0.6/0.8 would have
been quotable. Measured over err ∈ {0, −2, −4, −6, −8, −10, −18, +5, +11} at the showcase cell
(`g1_equiv.jl`): the two routes are **`===` on the miss in ALL NINE CELLS**, and §0.6 reproduces to
the digit (3290.078 / 2965.542 / 0.191 / 3620.675). ⇒ **EVERY GATE-0 TABLE TRANSFERS**, and §0.4's
and §0.5's numbers were then re-flown on the shipped branch and reproduce exactly (`g1_measure.jl`:
the V's 2.1119 / 2.1728 / 12.3460 / 8.0907 / 9.4999 / 10.9707, the control's 1.00 / 1.00 / 1.76 /
5.68 / 3.18 / 2.03 and its 0.2028 floor).
⚠ **ONE PORTING TRAP, NOT TAKEN** (advisor): the probe's `c0[:head_tgt_az] = haz` is an ARTIFACT of
pre-seeding — it existed only to make the pre-seeded tick-1 slew a no-op. Shipped mints `:head_tgt_*`
at the END of tick 1 from the measurement, and an init would have silently rewritten tick 2's chase.

**FINDING 1 — `err = 0.0` IS bit-identical to the key being absent, AND IT WAS MEASURED WHERE IT
COULD FAIL.** The plan required this measured, not asserted. ⚠ On the crossing wire `look_az_b ≈
+0.316 rad`, so `+ 0.0` is trivially inert and that arm **carries no information** (advisor); the
hazard needs a SIGNED-ZERO azimuth, i.e. the IN-PLANE (Y = 0, no crossing) geometry — slice 23's own
wire, which `hand_world` reaches with a `ypos` argument because `cross_speed_mps` re-pins `vel.y`
every tick. Both geometries come back `max|Δpos| = 0` over 3 000 ticks and `===` on the miss and on
the birth angle's bits. ⭐ **AND THE REASON IS THE PART WORTH KEEPING**: `az_el` hands back `+0.0` on
that arm, not `−0.0`, so `x + 0.0` never meets the value that breaks it. The `haskey` branch
therefore stays for the STRUCTURAL reason (slice 35's blocking pin, verbatim) and NOT because a
flying arm needs it — and the value that WOULD break it is pinned at the kernel beside the arm, so
the branch is evidenced rather than folklore: `head_clamp(-0.0, …)[1] === -0.0` while
`head_clamp(-0.0 + 0.0, …)[1] === +0.0`.

**FINDING 2 — THE TICK-1 SIGNATURE IS `|err|` TO 3.6e−15°, WHICH IS AN `atol` AND NOT AN `===`.**
The handover branch runs on exactly one tick, and the tracking error it leaves is the pin that fixes
AXIS, UNITS and SIGN at once. ⚠ The deg→rad→deg round trip is not the identity — measured worst
|Δ| = 3.553e−15° over the domain (exact at −18/−10/−8, 1.8e−15 at −12) — so the tooth is `atol =
1e-12`, carrying ~280× margin. The elevation is asserted `===` UNCHANGED, which is what says the key
went in on the axis where the lead and the excursion are (slice 28's channel split) and is the tooth
the DEFERRED elevation half would have to break.

⭐ **FINDING 3 — THE OFFSET GOES INSIDE THE CLAMP, AND SLICE 36 IS THE FIRST FLOWN ARM IN THE PROJECT
TO BIND THE STOP.** `head_clamp`'s docstring rested circular-vs-per-axis on a SPECIES argument, whose
stated condition was that *no arm had ever bound the stop in either form* (slice 34 gate 1). A head
born past `+11.9°` binds it, and the two forms PART on a flown arm: this kernel scales BOTH axes
radially, so `head_el` MOVES (−0.65598° → −0.65353° → −0.61283° as the error grows to +11.9/+12/+14)
and `hypot` lands EXACTLY on 30.000000°, where the per-axis alternative would leave `head_el` alone
and sit at **30.0072° — outside a 30° stop while the readout compared against 30**. ⇒ the docstring's
species argument is RETIRED and replaced with the measurement; the elevation is the tell, and it is
also what proves the offset did not go in AFTER the clamp.

⚠⚠ **FINDING 4 — §0.6's ISOLATION COLUMN IS A `%5.1f` PRINT, NOT A MEASUREMENT** (and it took a
FAILING tooth to notice, which is the point of writing the tooth as `== 0`). The first draft asserted
`aero_sat == 0.0` and `defl_sat == 0.0` as PERCENTAGES and failed at 0.0125 % / 0.047 % / 0.0095 %.
Re-read as COUNTS the claim is STRONGER: `defl_sat` is **EXACTLY 0** on every arm, and `aero_sat`
fires on **exactly ONE tick**, at **r = 6383 m on every arm that reaches it, INDEPENDENT of the
handover error** — the launch transient, not the basket — with both exactly 0 inside [500, 3000] m.
⚠ AND A SECOND DEFECT WAS HIDING UNDER IT: the first counters sat OUTSIDE the `r > 200` gate and so
read the r → 0 ENDGAME SPIKE (5 `aero_sat` + 1 `defl_sat` tick at r = 0.19 m on a HITTING arm) —
[[ewsim-missile-verifier-sampling]]'s own warning, applied to `off_max` in this file since slice 32
but not, until now, to the saturation counters.

⚠⚠ **AND A THIRD, CAUGHT POST-GREEN (advisor — slice 26's post-commit precedent, and it BLOCKED):
three of those asserts were VACUOUS.** `n_sat_band == 0` was asserted on the BROKEN arms, whose CPA
is 3.3–3.6 km — **so they never enter [500, 3000] at all** and the counter is zero FROM ZERO SAMPLES.
That is precisely the class slice 33 paid five failing asserts to catch (a quiet `rms r = 0.00000`
from an empty band on the 3.7 km arm), reappearing in a slice that cites it. Measured: `n_band` is
**4341** on the held arm, **866** at err −2 (it breaks late enough to dip below 3 km) and **0** at
err 0 / −10 / −18. ⇒ the band claim is now made ONLY on the held arm, and the broken arms' emptiness
is asserted as the POSITIVE fact it is — *it is why §0.1's "no band metric may carry this claim" is
true*. ⭐ The independence half was upgraded in the same pass, from prose to a measurement: the one
saturating tick lands at **`r_sat_lo === 6383.1955244633746` — BIT-IDENTICAL across err 0 / −2 / −4 /
−6 / −8** (spread exactly 0), which is what makes "the launch transient, not the basket" a fact.
**6980 → 6988.**

**FINDING 5 — THE GLASS TWIN IS `R̂ = −0.03`, NOT −0.18.** §0.6's glass-indifference number was flown
on lib36's LOUD default. Re-measured on the shipped branch: no glass **3620.6755**, `R̂ = −0.03`
**3620.1305** (§0.6's 3620.131 to the digit, **0.545 m apart on a 3.6 km miss**), `R̂ = −0.18`
3619.0219. The tooth pins the first two and the 1 m bound; getting this wrong reads as a 1.65 m gap
and would have understated the drop's own justification.

**AND A COST FINDING THAT SHAPED THE TESTSET.** `off_max` peaks during ACQUISITION (§0.1: the
tracking error is under 0.5° by r ≈ 4937–6437 m), so a REQUIREMENT arm need not fly to CPA —
measured identical at n = 4000 / 6000 / 9000 / full in every cell used, and the testset runs
requirement arms at n = 5000 and only MISS arms to CPA (19.6 s for 104 asserts). ⚠ Every requirement
is read off a **FREE-WINDOW** arm and the testset says so: on a never-acquired arm `off_max` is the
POST-BREAK RUNAWAY at 65–120°, the two-run discipline's FIFTH quantity, failing in the opposite
direction to slice 34's.

⚠ **§0.8 IS RELOCATED AND LANDED, NOT REBUILT** (advisor: "without building a new grid"). The
cage-vs-aim separation ships as a tooth in `test_missile.jl` with four cells rather than the gate-0
sweep: `head_max === stop` on the caged route against the aimed head's free 15.17° run; the birth
angle SATURATING (stop 30 and stop 20 bit-identical on a free-window arm, so the V's right arm is
unreachable by the stop); and the two cells where the verdicts part in OPPOSITE directions (birth 10°
/ vy 275: AIMED holds, CAGED breaks — birth 12° / vy 260: the reverse, the WRONG-WAY CHASE).

**WHAT GATE 2 INHERITS.** Three items were found here and belong there: ⚠⚠ `head_clamp` handles a
NaN *stop* but not a NaN *az*, so a non-finite authored error would poison the head state permanently
— **the loader must refuse NaN AND ±Inf** (advisor; `deg2rad(Inf)` reaches the kernel as a non-finite
`az` and `hypot(Inf, el)` makes the radial projection `Inf/Inf`); the domain's upper end is where the
key GOES INERT, which §1's saturation tooth now gives a mechanism for (`off1` at +14 and +20 agree to
0.02°); and ⚠ **Finding 3's elevation pin reads `ref.hel1` off a SEPARATE 1-tick arm** — correct
today, but if gate 2's telemetry changes tick 1 in any way that pin must be RE-READ, not inherited.

---

## §2 — Gate 2 (2026-08-10): the seam's two keys, the loader, and a third key DROPPED — 6988 → 7057

⭐⭐ **THE GO/NO-GO RAN FIRST AND CAME BACK NEGATIVE** (the advisor's blocking item, before the key
was written). The requirement is a MAX OVER THE APPROACH so the core holds it, and the tempting
justification was slice 33's gate-3 finding — THE EMIT GRID UNDER-READS THE EXCURSION BY MORE THAN
THE SURVIVABLE BAND IS WIDE. ⚠⚠ **It would have been a BORROWED CLAIM, and the check is the rule:**
slice 33 was entitled to say it because its 0.016° under-read was WIDER than the 0.011–0.05° band
that decided its verdict. Measured here on the cells where a verdict actually turns (`g2_grid.jl`;
free window, no glass, the 10° window the wires will author):

| cell | per-tick | per-frame | GAP° | margin to 10° | gap / margin |
|---|---|---|---|---|---|
| err 0 / 12 °/s (§0.9's HELD) | 8.84016 | 8.83704 | **0.00313** | 1.1598 | **0.27 %** |
| err −4 / 8 °/s | 9.49992 | 9.49942 | 0.00050 | 0.5001 | 0.10 % |
| err −6 / 8 °/s (§0.9's HELD) | 8.09069 | 8.09019 | 0.00050 | 1.9093 | 0.03 % |
| err 0 / 15 °/s | 7.22281 | 7.22240 | 0.00041 | 2.7772 | 0.015 % |

and the frame grid **agrees with the ticks on the BREAK verdict in every cell** (0/10579 vs 0/661
held; 7302/7919 vs 456/494 at err 0 / 10 °/s). ⇒ **THE KEY STANDS ON CONVENTION 13 INSTEAD** — a max
over ticks is not a thing a client receiving one tick in sixteen can form at all, whatever the
sampling error happens to be. ⭐ And the MECHANISM for why it could never have stood on slice 33's is
**slice 35's own knob**: a RATE-LIMITED head cannot move more than `rate·emit·dt` between frames
(0.128° at 8 °/s and `emit_every: 16`), so the servo limit that CREATES the requirement also BOUNDS
how much a frame grid can hide of it. Over rate × emit ∈ {8, 25, 60} × {16, 64, 250} the gap never
exceeds **3.6 %** of that bound (largest absolute 0.547° at 60 °/s × 250).
> **GENERAL.** *When a later slice reaches for an earlier slice's finding, re-run the comparison
> that ENTITLED the earlier slice to it. The finding may be perfectly true and still not yours.*

⚠⚠ **A THIRD KEY WAS DRAFTED, MEASURED AND DROPPED, AND ITS WHOLE VALUE IS ITS WHOLE DEFECT.** A
signed peak MARGIN (`gimbal_fov_peak_margin_deg`, slice 33's `seeker_fov_margin_deg` shape) would go
negative on the first tick the window is breached and **never recover** — slice 32's client-side
LATCH, derived and core-owned, which is how it was written. But slice 34 measured that EVERY held arm
leaves its window at r = 0.18–8.55 m as the LOS swings past, and **a peak cannot forget**: reproduced
in `g2_measure.jl` §B, the would-be latch fires on **100 % of arms, including every hit** (the
0.191 m arms latch for their last tick; the broken arms for their last 7302–7358). A latch that is
true of every arm is not a verdict. ⇒ the verdict stays with `gimbal_valid` — per tick, and it
RECOVERS when the geometry does — and slice 32's latch stays the client's to hold over it.
**TWO keys ship, not three**, and the drop is a measurement rather than a preference (the tooth
recomputes the dropped key so a later slice cannot re-propose it from the plan alone).

**FINDING 1 — THE PEAK IS AN APPROACH QUANTITY, AND THIS IS THE ENDGAME SPIKE IN THE ONE TELEMETRY
SHAPE FOR WHICH IT IS IRREVERSIBLE.** `head_off_peak_deg` reads the clean requirement **BIT-
IDENTICALLY from r = 3000 m through r = 1000 m to r = 200 m** — 8.84016 / 8.09069 / 9.49992 / 2.11192
on the four cells measured, `===` at all three ranges — and then runs to **179.4998° at CPA on every
arm, hit or miss**, because the target is behind the head by then. An instantaneous key spikes there
and recovers. ⇒ a reader takes it AT A RANGE and never at the end, and **gate 3 inherits the display
decision**: a HUD that prints the raw key past CPA is slice 19's lying picture in a new widget.

**FINDING 2 — THE TWO-RUN DISCIPLINE's FIFTH QUANTITY IS NOW SHIPPED AND IT FAILS LARGE.** On a
windowed arm the head holds with no error signal while the LOS leaves, so the peak is the POST-BREAK
RUNAWAY — **104.56 / 65.79 / 73.77°** against free-window requirements of **12.346 / 10.000 /
18.000** at err 0 / −10 / −18 (8 °/s). Slice 34's `head_angle_deg` froze plausibly-but-TOO-SMALL;
this one runs away, so a reader of a break table will take these for requirements. They are not.

⭐⭐ **FINDING 3 — `_parse_knobs` GAINS THE FIRST BY-NAME REFUSAL IN THE PROJECT, AND THE REASON IS AN
ASYMMETRY.** §0.9 established the key is structurally a dead knob; gate 2 makes that ENFORCEABLE.
⚠ The existing guard would NOT have caught it: `_parse_knobs` refuses a knob whose comp key does not
exist, which is how 19's `speed` and 21's launch altitude were caught — **BY ACCIDENT, because
neither is a comp key at all**. `gimbal_handover_err_deg` IS a comp key when authored, so the
declaration loads cleanly and ships a live slider onto a number nothing reads again. *A constraint
stated in a policy is not enforceable where the policy cannot reach* (slice 34 gate 2) — this is
where it reaches. ⚠ ONE KEY BY NAME (`_DEAD_KNOB_KEYS`), deliberately **not a registry**: a registry
invites entries argued rather than measured, and every other dead knob is already caught by the
existence check below it. The MIRROR is pinned — `gimbal_rate_dps` still declares cleanly on the same
scenario, so this is a refusal and not a blanket ban.

**FINDING 4 — THE LOADER JOINS, IT DOES NOT REFUSE.** The key enters the EXISTING three-key gimbal
validation loop (slice 35's precedent — one source, no drift), inheriting presence-gating on
`gimbal_tau_s` and the non-finite refusal. ⚠ The loop's slice-attribution ternary needed a THIRD arm
or it would credit slice 34. ⚠⚠ The non-finite refusal is **not hygiene** (gate 1's inherited item):
`head_clamp` handles a NaN *stop* but not a NaN *az*, so `deg2rad(±Inf)` reaches the kernel as a
non-finite azimuth, makes the radial projection `Inf/Inf` and poisons the head state permanently —
inside `observe!`, where the session's IO-only catch drops the connection. ⚠ **NO BOUND AGAINST THE
STOP**, and the reason is decisive rather than stylistic: the key is an OFFSET on the flying
`look_az_b`, so *"authored beyond its own stop"* is **not a load-time-decidable quantity** — the
loader cannot know the geometry that puts the boundary at +11.9° here and elsewhere on another wire —
and refusing it would delete the mechanism that bounds the basket from above. Slice 35's post-review
shape: a degenerate the loader PERMITS, proven to LOAD (`err = 400°`) and never FLOWN.

**FINDING 5 — BOTH DOMAIN ENDPOINTS MEASURED, AND THEY ARE DIFFERENT KINDS OF BOUNDARY** (slice 26's
post-commit rule, applied to both ends rather than one — slice 34's gate-3 post-review found it had
been applied to neither). `g2_measure.jl` §D, free window, 8 °/s:

| err° | birth az° | \|head\|° | requirement° |
|---|---|---|---|
| −20.000 | −1.894635 | 2.004981 | 20.000000 |
| **−18.105365** | **0.000000** | **0.655978** | 18.105365 |
| −12.000 | 6.105365 | 6.140504 | 12.000000 |
| 0.000 | 18.105365 | 18.117245 | 12.346038 |
| **+11.900** | 29.992833 | **30.000000** | 24.078964 |
| +20.000 | 29.995556 | **30.000000** | 24.079428 |

LOWER: at the NEGATIVE OF THE PERFECT HANDOVER the head is born at azimuth **exactly 0.000000°** —
pointing down its own nose in that axis, which is where a CAGED head sits, so the endpoint is a
coincidence with the arc's other degenerate. ⚠ **The key does NOT go inert there** (at −20° the
requirement is still exactly 20.000000° and the V's left arm continues), so the lower bound is a
**MODELLING choice** and this plan says so rather than implying a mechanism it does not have. UPPER:
the birth angle SATURATES on the stop and the key GOES INERT — the requirement agrees to **5e-4° over
a 1.7× span of authored error**, which is a mechanism. ⇒ **[−18.1 (the CAGED coincidence), +11.9 (the
STOP)]**, two different kinds of bound; the wires author 0 and −6, well inside.

**FINDING 6 — THE PEAK IS CUMULATIVE ACROSS A CROSS-TOGGLE, DELIBERATELY.** The latent-bug class this
arc has caught seven times, arriving in a new place: state that outlives its rung gate. `:head_az`
itself persists through a toggle off `:six_dof` — the head FREEZES rather than un-existing, and on
toggle-back the seam takes the SLEW branch off the stored angles — so a peak that RESET there would
be the only piece of head state that did, and would read LOWER than the tracking error the head has
actually had. Nothing accrues while `_gim` is false because the update sits inside the rung gate:
measured **0/500 frames** ship the key while off-rung, and the peak returns 8.090688 unchanged.

**CONVENTION 9, BY MEASUREMENT.** Gate 1's own teeth already carry it: the authored error and the
servo are ONE axis, because **the servo MOVES the argmin** (−2 at 40 °/s, −8 at 8 °/s, a 1.54×
saving), and slice 35 is the `err = 0` ROW of this slice's grid. No new tooth was owed.

⭐ **AND THE BLOCKING RE-READ WAS RUN, NOT INHERITED** (§1's "WHAT GATE 2 INHERITS"): Finding 3's
elevation pin reads `ref.hel1` off a separate 1-tick arm, and gate 2 changes tick 1's telemetry. The
whole slice-36 gate-1 ladder was re-run against the shipped seam and is green — `hel1 === ref.hel1`
and `hypot === 30.000000` still hold.

**WHAT GATE 3 INHERITS.** ⚠⚠ The peak's ENDGAME (179.4998° at CPA on every arm) is a DISPLAY problem
the HUD must own — freeze or annotate it past CPA, and never print it raw. ⚠ The scenario sweep at
the end of the loader testset asserts **no shipped wire carries the key**; gate 3 authors two and
must TIGHTEN that to the pair rather than delete it (slice 35's shape). ⚠ The verifier reads every
requirement off a FREE-WINDOW arm and every peak AT A RANGE. ⚠ The GLASS keys must be asserted ABSENT
the way slice 35 asserted its disqualified ones (`radome_slope*` is a dead knob on a no-glass wire) —
that bullet is unspent, and it is a gate-3 artifact because it is a claim about the shipped YAML.

⚠⚠ **AND THE DECLARED DOMAIN IS NOT THE BASKET — DO NOT LET THE HUD OR THE PROSE PRESENT ONE AS THE
OTHER** (advisor). `[−18.1, +11.9]` is the range over which the KEY IS MEANINGFUL; the set of
handover errors that HOLD THE TRACK on the shipped wire is far smaller — roughly **[−8, −4] at
8 °/s behind a 10° window** (§0.6), because at +11.9 the requirement is 24.079° against that same
10°. The slice's headline is that **zero is outside the basket**, and a picture that draws the domain
as the basket would make the headline unreadable in the one place it is supposed to be visible.

**⚠ MEASURED-AND-NOT-DONE.** The `fov_h`-vs-authored-`gimbal_fov_deg` divergence (slice 33's, live on
a negative window) was checked and is MOOT here: with the peak margin dropped, nothing new subtracts
the two, and the per-tick `gimbal_fov_margin_deg` already owns that divergence.

---

## What ships (gates 1–3, PLANNED)

### The core (gate 1) — ✅ DONE, see §1

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
35's gate-1 shape inverted). ⇒ **ANSWERED: NO KERNEL** (§1). The only `frames.jl` edit is PROSE —
`head_clamp`'s species argument, retired by Finding 3.

⚠ **AND THE `= 0.0` MEASUREMENT CAME BACK IDENTICAL, INCLUDING ON THE IN-PLANE SIGNED-ZERO ARM** (§1
Finding 1). The branch stays anyway, for the structural reason and not for a flying one, with the
value that would break it pinned at the kernel.

### The seam + loader (gate 2) — ✅ DONE, see §2

* Telemetry: the SIGNED authored error, and the REQUIREMENT as a running maximum
  (`head_off_peak_deg`) — ⚠ slice 27's peak-hold shape, because the requirement is a *max over the
  approach* and an instantaneous readout cannot show it. The margin against the window is slice 33's
  SIGNED `seeker_fov_margin_deg` shape: **the sign is the verdict.**
  ⇒ **PARTLY ANSWERED, PARTLY REFUTED (§2).** The two keys ship; the third — the signed peak MARGIN
  — was written, MEASURED and DROPPED, because a latch that fires on every arm (the endgame breaches
  any window and a peak cannot forget) is not a verdict. ⚠ And the *reason* for the peak key is
  CONVENTION 13, **not** slice 33's emit grid, which was the go/no-go and came back at 0.27 % of the
  deciding margin.
* Loader: validate the error against the STOP (a head authored beyond its own stop is silently
  clamped today — a degenerate the loader would permit; slice 35's post-review commit shape is to
  prove it LOADS and is never FLOWN, or to refuse it).
  ⇒ **ANSWERED: PROVEN TO LOAD, NEVER FLOWN (§2 Finding 4)** — and refusing it is not merely
  unnecessary but *not possible*, because the key is an OFFSET on the flying `look_az_b` and "beyond
  its own stop" is not a load-time-decidable quantity. The loader validates FINITENESS only, in the
  existing three-key loop.
* ⭐⭐ **AND THE POLICY GOT AN ENFORCER THE PLAN DID NOT ANTICIPATE (§2 Finding 3):** `_parse_knobs`
  refuses `gimbal_handover_err_deg` BY NAME. The bullet below says the key "must NOT be declared
  live-settable" — that was a policy, and the existing knob guard would not have caught a violation,
  because it only refuses knobs whose comp key does not exist and this one's does.
* ⚠⚠ **THERE IS EXACTLY ONE LIVE KNOB, `gimbal_rate_dps`** (§0.9). `gimbal_handover_err_deg` is
  AUTHORED — structurally a dead knob, and slice 19's tripwire would fail on it — so it must NOT be
  declared live-settable and the verifier must NOT run a set-param sweep on it. `radome_slope_est`
  is also dead here (no glass), and the verifier asserts the GLASS keys ABSENT the way slice 35
  asserted its disqualified ones.
* Convention 9 by MEASUREMENT, not by counting sliders (slice 27's diagonal): §0.5's table already
  shows the authored error and the servo are ONE axis — the servo *moves the optimum of the basket* —
  and slice 35 is the `err = 0` row of that same grid.
* ⚠ **THE DOMAIN'S UPPER END IS WHERE THE KEY GOES INERT** (slice 26's post-commit endpoint lesson).
  `off_max` saturates at 11.8902 for any authored error past ~+11.9° because the head is then born ON
  the stop — so the plan states **the stop bounds the basket from above** rather than presenting
  [−18.1, +11.9] as a plain range, and gate 2 MEASURES the endpoint rather than inferring it. Slice
  34 gate 2 already found the stop and the window are one budget.

### The wire (gate 3)

**TWO SCENARIOS** (§0.9, slice 34's precedent — and slice 22's before it): both are slice 35's wire
**MINUS THE GLASS** with the window authored ~10° and `gimbal_rate_dps` the ONE live slider,
differing only in the authored `gimbal_handover_err_deg` —

* `scenarios/slice36_handover.yaml` — **err = 0**, the perfect handover: HELD down to 12 °/s, BROKEN
  at 10 and below, missing ~3.3 km. *The slider decides whether you keep the track.*
* `scenarios/slice36_biased.yaml` — **err = −6**, the biased handover: HELD at every rate in the
  domain with `off_max` flat at 6.000 over five of seven rates. *The slider stops mattering.*

⚠ ONE verifier auto-detects which (slice 22's shape), and the pair IS the A/B — there is no rung to
toggle and no button to press, which is consistent with the button having been DROPPED for eleven
consecutive slices.

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

⚠ **MARKER RE-CHECK (slice 35's INVISIBLE-SLICE class, and it must be RUN, not inherited).** There
are **TWO live-and-wrong candidates, not one**: a slice-36 wire is a slice-35 wire minus the glass
plus one key, so `gimbal_rate_view` routes it and meters the servo's duty against **the loop's**
demand — and there is no loop here at all — while `gimbal_view` would meter the tracking error
against the detector window, closer to right and still never naming the basket or its tick-1 peak.
Both are FLUENT and FULLY LIVE (nothing stale) on a track that has missed by 3.3 km — slice 34's
worst form. Expect a `gimbal_handover_view` branch checked FIRST, expect the check to come back
POSITIVE this time, and **run it anyway**.

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
* **THE CAGE vs THE AIM AS ITS OWN A/B** — §0.8 measured a real, two-directional split between
  biasing the birth angle and shrinking the stop, including a mechanism neither slice has named
  (the WRONG-WAY CHASE: a head born below the LOS slews *up* toward +18° before the LOS reverses).
  Built and measured here, shipped only as a tooth — slice 27's angle-domain-corrector precedent.
* **THE ELEVATION HALF** — the error here is authored in AZIMUTH because that is where the lead and
  the excursion are (slice 28's channel split). An elevation basket is orthogonal to the excursion and
  §0.5 predicts it has NO optimum shift; measuring that is a tooth, not a slice.
* **A RECTANGULAR / PER-AXIS STOP**, **THE HEAD'S OWN GYRO** — slice 34's, unchanged and unspent.
* Everything 26–33 named and did not spend.
