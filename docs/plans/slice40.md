# Slice 40 — **A HEAVIER GIMBAL: THE SECOND-ORDER HEAD SERVO** (§11 Tier-A)

**Status: GATE 0 COMPLETE — the slice is LIVE.** 6 probes in 6 files (2026-08-17). Raw numbers in
`M:\claud_projects\temp\slice40g\` (`p0_bench.jl`, `lib40g.jl`, `p1_ordering.jl`, `p2_ladders.jl`,
`p3_frequency.jl`, `p4_freq2.jl`, `p5_sliders.jl`, `p6_twowires.jl`). The gate-0 patch in
`missile.jl` (grep `SLICE 40 GATE-0 PROBE PATCH`) is a PROBE and **must be reverted before any
commit** — gate 1 replaces it with a kernel in `frames.jl`.

The candidate is the deferral slices **35, 37 and 38** each named and none spent:

> *"**A SECOND-ORDER SERVO (ω_a/ζ_a)** — the head here is first-order-with-a-rate-limit; a real
> gimbal has an inertia and a bandwidth, and slice 15's actuator is the precedent for what that
> adds."* — `docs/plans/slice35.md`; sharpened by 38: *"this slice shows the REJECTION path has its
> own spec, so τ and ω_a would both change how much that spec is worth."*

---

## The one-paragraph statement of what was measured

> ⭐⭐ **THE RESULT, IN ONE SENTENCE.** Slice 37 measured its whole margin in **GAIN** — the
> first-order servo's lag LOW-PASSES body motion out of the radome's index (0.884 at the ring's
> 1.7 Hz against a strapdown seeker's 1.000), and that filtering is worth ≈40–45 % of slice 34's
> stability margin. Give the gimbal an INERTIA and that reading stops being the answer: on slice
> 34's own shipped design, **a second-order servo with an index gain of 0.095 — NINE TIMES QUIETER
> than the shipped lag — rings 36× harder than it**, because its phase has run to −176°. A
> first-order lag cannot show this, because it has ONE number: its gain and its phase are locked
> together by the same τ, and its phase can never pass −90°. **⇒ NEITHER NUMBER, READ AT A FIXED
> FREQUENCY, ORDERS THE OUTCOME — AND ONLY AN ARCHITECTURE WITH TWO NUMBERS CAN SHOW THAT.**
>
> ⚠⚠ **THAT SENTENCE IS DELIBERATELY WEAKER THAN "IT WAS THE GAIN AND THE PHASE" AND THE WEAKENING
> IS A MEASUREMENT, NOT CAUTION** (advisor): this file's own `2nd 0.5 Hz ζ = 1.0` arm sits at −147°,
> far outside the lag's phase bound, and is QUIET. A two-variable rule read at 1.7 Hz fails on that
> row exactly as the one-variable rule fails on the row above it. §0.7 says why the honest statement
> stops here: the frequency the loop actually closes at is the one quantity this gate could not
> measure.

The two failure modes sit on **opposite sides of the resonance** and are unreachable by any τ:

| servo | index gain @1.7 Hz | phase @1.7 Hz | `rms r` at R̂ = −0.18 |
|---|---|---|---|
| **1st τ = 0.05 — THE SHIPPED HEAD** | 0.882 | −28.1° | **0.01181** (quiet) |
| 2nd ω_n = 2.0 Hz, ζ = 1.00 (well damped) | 0.581 | −80.7° | 0.01212 (quiet) |
| 2nd ω_n = 2.0 Hz, ζ = 0.10 — **RESONANT** | **3.073** | −31.5° | **0.51659 (44×)** |
| 2nd ω_n = 0.5 Hz, ζ = 0.30 (heavy) | 0.093 | −169.1° | 0.07874 (6.7×) |
| 2nd ω_n = 0.5 Hz, ζ = 0.10 — **HEAVY + light** | **0.095** | −176.3° | **0.42414 (36×)** |

⭐ **THE TWO RINGING ARMS' GAINS DIFFER BY 32×, ONE ABOVE THE SHIPPED LAG AND ONE FAR BELOW IT.**
Gain does not order the outcome. What they share is that each is out of a bound the first-order lag
cannot leave.

---

## §0.1 THE MODEL, AND THE THREE SEAM DECISIONS DECLARED BEFORE THE PATCH

Slices 34–39's head is a first-order lag with a rate limit (`head_slew_full`). A real gimbal has
inertia, so its servo is second-order:

```
        θ̈  =  ω_n²·(θ_cmd − θ)  −  2ζ·ω_n·θ̇        ⇒  H(s) = ω_n² / (s² + 2ζω_n s + ω_n²)
```

⚠⚠ **THE PROBE PATCH'S THREE FREE DECISIONS, STATED BECAUSE SLICE 39 §0.1's LESSON IS THAT A FREE
DECISION INSIDE A PATCH CAN MANUFACTURE THE CLAIM** (advisor, before any code):

1. **THE RATE LIMIT BINDS THE RATE STATE, RADIALLY — not the step.** With an inertia the drive's
   maximum rate is a property of the MECHANISM; a step cap would leave the unspent rate in the state
   to be delivered next tick, which is a cap that is not a cap. `head_dem` keeps slice 35's units (a
   STEP, radians) so the seam's telemetry is unchanged.
2. **THE STOP ZEROES THE RATE STATE.** A mechanical stop is inelastic. Letting θ̇ wind up against it
   produces a clamp-driven oscillation that would FAKE the resonance exactly. ⚠ On every claimed arm
   the stop is provably clear (`head_max` 18.1–22.9° against a 30° stop), so this never binds.
3. **THE HANDOVER'S RATE INITIAL CONDITION IS ZERO** — a gimbal at rest. This makes the acquisition
   turn slower than first-order's, and slice 35's gate 2 found that turn to be the binding window
   requirement, so `off_max` is watched on every arm (1.96° first-order against 3.4–4.9° second-order;
   both far inside the 25° window).

---

## §0.2 P0 — THE BENCH: **THE BOUND**, WHICH IS WHAT MAKES THIS A RUNG

Slice 37/38's frozen-geometry bench (`index_bench`), unchanged, with the servo as the new axis:
geometry frozen, body oscillating at `f`, and the measured quantity is the head's BODY-frame azimuth
— **the part of the dome the ray actually goes through**. NO CORE PATCH; both heads are built from
shipped kernels.

**P0a — the first-order head is BOUNDED IN BOTH CURRENCIES**, and the bench reproduces
`1/√(1+(2πfτ)²)` and `−atan(2πfτ)` to 3–4 digits over an 40× span of τ:

| τ | f | gain | pred | phase | pred |
|---|---|---|---|---|---|
| 0.005 | 1.7 | 0.99886 | 0.99858 | −2.45° | −3.06° |
| 0.05 | 1.7 | 0.88405 | 0.88208 | −27.56° | −28.11° |
| 0.20 | 2.1 | 0.35513 | 0.35435 | −68.82° | −69.25° |

⇒ **gain ≤ 1 and phase ≥ −90°, at every frequency, for every τ.** A strapdown seeker's index gain is
EXACTLY 1, which is why slice 34's gimbal could only ever buy margin.

**P0b — the second-order head exceeds both**, matching `1/√((1−r²)² + (2ζr)²)` and
`−atan2(2ζr, 1−r²)` to 3–4 digits (ω_n = 2 Hz, ζ = 0.3): gain 1.71848 at 1.7 Hz against the
predicted 1.72233, phase −98.1° at 2.1 Hz against −99.2° — **past the first-order bound in both**.

**P0c — the grid the domain comes off.** `gain > 1` at the ring's 1.7/2.1 Hz for every
ω_n ≥ 1.5 Hz with **ζ < 1/√2**, and never for ζ ≥ 1/√2. ⭐ **ζ = 1/√2 ≈ 0.7071 IS AN ANALYTIC EDGE**
— beyond it the closed-loop response has no peak above 1 at ANY frequency — so the domain is
DERIVED first and MEASURED second, the shape this arc prefers.

**P0d — the overdamped corner is where the rung goes nearly dead**, and it is stated rather than
hidden: at ζ ≥ 3 the second-order gain tracks a lag of `τ_eff ≈ 2ζ/ω_n` to ~1.6 % (0.19573 against
0.19261) while the PHASE still parts (−85.97° against −78.59°). ⇒ the claim lives in the LOW-ζ
region, and the high-ζ region is the button going quiet — slice 30's aim point, in a new axis.

---

## §0.3 ⚠⚠ P1 — THE ORDERING PROBE: THE KILL RISK, FLOWN FIRST, AND **REFUTED**

The advisor's blocking question, before any ladder: **as the gimbal gets heavier, which failure
arrives first — the resonant ring, or the track breaking out of the detector window?** A heavy
gimbal that cannot follow the LOS blows `off_max` through the window, and then this is slice 33/34's
METRIC INVERSION (a frozen index is quiet at every R̂, so `rms r` FALLS while the miss opens) and the
headline would be slice 34's mechanism wearing a new name.

**Measured: `out_band = 0.00 %` on EVERY arm of every ladder in this gate** — ω_n from 0.5 to 30 Hz,
ζ from 0.05 to 3.0, with and without the rate limit. The window never breaks. ⇒ the resonance is
REACHABLE, and every number in this file is a legal stability read.

⭐ **AND THE LICENSING ISOLATION IS A GATE-0 ARM, NOT A GATE-2 AFTERTHOUGHT** (advisor): the ring
must survive with slice 35's rate limit ABSENT and the stop well clear, or the oscillation is a rate
limit or a clamp windup rather than an inertia (slice 39 §0.5: a corner owned by the patch's own free
decision is NOT a result).

| arm | rms r | out% | sat% | head° | miss |
|---|---|---|---|---|---|
| 1st, shipped limits | 0.01172 | 0.00 | 0.00 | 18.117 | 0.162 |
| 1st, NO rate limit | 0.01181 | 0.00 | 0.00 | 18.117 | 0.187 |
| 2nd 2 Hz ζ=0.3, shipped | 0.10918 | 0.00 | 0.00 | 21.933 | 11.725 |
| 2nd 2 Hz ζ=0.3, NO rate limit | 0.09830 | 0.00 | 0.00 | 22.316 | 12.356 |
| 2nd 2 Hz ζ=0.3, NO limit, 90° stop | 0.09830 | 0.00 | 0.00 | 22.316 | 12.356 |

⇒ the ring is the INERTIA. ⚠ The last two rows are IDENTICAL to five decimals, which is the stop
proving it never bound.

---

## §0.4 P2 — THE ONSET LADDERS: THE MARGIN MOVES IN **BOTH** DIRECTIONS

Slice 37/38's currency: the R̂ ONSET BRACKET on their own 0.005 grid, under their THRESHOLD-FREE
largest-single-step rule, one cell wider at each end than the bracket (slice 38's own gate-0 lesson:
*a bracket pinned against the edge of its grid is truncated, not measured*). ⚠ Every ladder flown
with the rate limit ABSENT, the control included — its own rms r moves 0.01172 → 0.01181, i.e. not
at all — so the ladders are comparable BY CONSTRUCTION.

| servo | onset bracket | cells vs the shipped head |
|---|---|---|
| 2nd 2.0 Hz ζ=1.0 | (−0.155, −0.150] | **+3 — MORE margin than the lag** |
| **1st τ = 0.05 (CONTROL)** | **(−0.170, −0.165]** | 0 — slice 37's own body bracket EXACTLY |
| 2nd 30 Hz ζ=0.3 (≈ strapdown) | (−0.180, −0.175] | −2 |
| 2nd 2.0 Hz ζ=0.3 | (−0.185, −0.180] | −3 |
| 2nd 0.75 Hz ζ=0.3 | (−0.185, −0.180] | −3 |
| 2nd 1.0 Hz ζ=0.3 | (−0.190, −0.185] | −4 |
| 2nd 2.0 Hz ζ=0.1 | (−0.200, −0.195] | −6 |
| 2nd 1.0 Hz ζ=0.1 | **rings at every cell** | ≤ −13, off the grid — **TRUNCATED, NOT MEASURED** |

⭐ **THE CONTROL ROW REPRODUCES SLICE 37's SHIPPED BODY-REFERENCED BRACKET EXACTLY**, which is what
entitles this harness to speak about the other rows at all (slice 38's own discipline).

⚠ **THE LAST ROW IS QUOTED AS A BOUND, NOT A BRACKET** — its ladder rises smoothly from 0.15051 at
the grid's own edge, so the rule finds a 1.28× "largest step" that means nothing. Slice 38's lesson,
obeyed rather than restated.

---

## §0.5 ⭐⭐ P5/P6 — THE HEADLINE: **THE GAIN DOES NOT ORDER THE OUTCOME**

The ladders above are ordered by index gain read at 1.7 Hz — **until they are not.** The row that
breaks it is the one that makes the slice:

```
   2nd ω_n = 0.5 Hz, ζ = 0.1:   index gain @1.7 Hz = 0.0945   (the shipped lag's is 0.882)
                                 phase              = −176.3°  (the lag can never pass −90°)
                                 rms r              = 0.42414  (the lag reads 0.01181)
```

**A TENTH OF THE GAIN AND THIRTY-SIX TIMES THE RING.** Slice 37's mechanism — *the lag low-passes
body motion out of the index, and that is where the margin comes from* — is TRUE and INCOMPLETE, and
this is the first architecture in the arc that can show the difference.

⚠ **AND THE CONVERSE IS ALSO MEASURED, WHICH IS WHAT KEEPS THE CLAIM HONEST**: phase past −90° does
NOT by itself ring. `2nd 0.5 Hz ζ = 1.0` sits at −147.2° and reads 0.01840 — quiet. ⇒ the claim is
**neither number alone orders the outcome**, not "phase is the real currency". Writing it the second
way would be this arc's copy-paste false-claim trap in a new letter.

---

## §0.6 P6c — THE REPARAMETERIZATION GATE, **ANSWERED BY A BOUND** (slice 39's kill, pre-empted)

Slice 39 died because an "architecture" turned out to be a relabelled `gimbal_tau_s`. The same
question, asked here BEFORE any kernel exists, and answered two ways:

* **ANALYTICALLY** — a first-order lag's index gain is `1/√(1+(2πfτ)²) ≤ 1` and its phase
  `−atan(2πfτ) ≥ −90°` at every frequency and every τ. Both ringing arms are outside those bounds
  (gain 3.07; phase −176°). No τ exists.
* **IN FLIGHT** — the shipped knob's OWN domain, swept 800× over τ ∈ [0.001, 0.8] on the showcase
  design: `rms r` spans **0.01042 … 0.03428 and never rings**, against the second-order arms' 0.424
  and 0.517. The loudest first-order arm is **15× below** the quieter of the two.

⇒ **RUNG, NOT KNOB**, and the gate is answered the way slice 37 §II.3 answered its own — with a
bound rather than a tolerance.

---

## §0.7 ⚠⚠ WHAT WAS REFUTED: **THE RING FREQUENCY IS NOT MEASURABLE ON THIS WIRE**

P3 hypothesised the sharpest available claim — *the loop rings where the gimbal resonates*, which
would have made the limit cycle's FREQUENCY a design variable for the first time in the arc — and
put a CONTROL row in the probe to guard it. **The control failed.** A periodogram of the band's
`ω_r` put the first-order head's ring at **0.80 Hz** where slices 26–39 measure **1.7–2.1 Hz**.

P4 re-flew it under slice 26 §P7B's own conditions (σ = 0, and its PAIR of independent estimators —
mean-removed zero-crossing rate and above-half-peak local-maximum count). **The oracle failed
again**, and worse: the two estimators DISAGREE on the control itself (0.91 vs 0.23 Hz).

⇒ **NO FREQUENCY CLAIM IS MADE.** The band is ~3.5 s and the oscillation is growing inside it, so
neither estimator has the stationarity it needs; slice 26's own rule (*quote only the band where they
agree*) forbids it. The hypothesis is recorded as UNTESTED, not as refuted physics, and a slice that
wants it must first earn a frequency estimator on this wire.

⚠ This is also why §0.5 is written as *"neither number alone orders the outcome"* rather than as a
loop-crossover argument: the crossover frequency is exactly what could not be measured.

---

## §1.1 ⚠⚠ THE DISCRETIZATION PIN — THE CHECK THAT SEPARATES A RESONANCE FROM AN EULER ARTIFACT

The claim lives in the LIGHTLY-DAMPED regime, which is exactly where an integrator's own numerical
damping is most likely to masquerade as physics (advisor, before any kernel was written). Three
oracles, none of them the recursion restated:

* **THE STEP RESPONSE against the CLOSED FORM** `θ(t) = 1 − e^(−ζωt)(cos ω_d t + (ζ/√(1−ζ²)) sin ω_d t)`:
  max error **6.269e−03 → 6.259e−04** as dt falls 10×, a ratio of **10.02** — first order, exactly as
  semi-implicit Euler must be. ⭐ The ratio is the point (slice 23's wiring-bug detector): a FLAT
  column would mean the recursion is not solving the equation it claims to.
  ⚠ The oracle itself is undefined at ζ = 1 (`√(1−ζ²)` is 0/0) and returns NaN — an ORACLE defect,
  not a stepper one; the critically-damped and overdamped closed forms are separate branches and the
  testset must carry all three.
* **THE EFFECTIVE DAMPING of the discrete free response**, by log decrement, against the AUTHORED ζ:
  the error is **1.5e−05 … 5.7e−04 at the shipped cells, i.e. 0.0003–0.011 OF ONE DOMAIN CELL**
  (the ζ grid is 0.05 apart). ⇒ the stepper adds no damping the physics did not author, in the
  currency that matters.
* **THE DAMPED FREQUENCY** of that same response: within **3e−04 … 2e−03** relative.

⚠ **AND THE RECURSION'S STABILITY LIMIT IS MEASURED, BECAUSE VALIDATE-AT-LOAD MUST RESPECT IT**
(convention 5 — a live knob can never crash a tick): it decays to ω_n = 200 Hz (`ω_n·dt = 1.26`) and
**DIVERGES to NaN at 300 Hz** (`1.885`). The shipped wires sit at `ω_n·dt` = 0.0126 and 0.0031.

---

## §1.2 ⚠⚠ TWO BLOCKING FINDINGS FROM THE MARGIN RE-CHECK, AND WHAT THEY CHANGED

**FINDING 1 — WIRE B's HEAD REACHED ITS MECHANICAL STOP, AND THE ARC's OWN RULE CAUGHT IT.** The
gate quoted `head_max` 22.9° against a 30° stop from the arms it happened to look at; asserted PER
ARM (advisor), the ω_n = 0.5 Hz wire reads **`head_max = 30.000` EXACTLY at ζ ≤ 0.15** — §0.1's
DECISION 2 (an inelastic stop zeroes the rate state) reachable on a claimed arm.

Resolved by measurement rather than by argument — opening the stop 30 → 45 → 90°:

| ζ | rms r @30 | @45 | @90 | head° @30 | @45 | @90 |
|---|---|---|---|---|---|---|
| 0.05 | 0.55230 | 0.54614 | 0.54614 | 30.000 | 41.498 | 41.498 |
| 0.10 | 0.42414 | 0.41555 | 0.41555 | 30.000 | 33.433 | 33.433 |
| 0.30 | 0.07874 | 0.07874 | 0.07874 | 18.117 | 18.117 | 18.117 |

⇒ the clamp was worth **~1 %** of the ring and the mechanism is the inertia — but the arm was not
CLEAN, so **wire B authors a 50° stop** and every quoted arm asserts `head_max` strictly inside it.
⭐ **AND THE FINDING HAS ITS OWN PAYLOAD: THE RING IS SPENT IN GIMBAL TRAVEL** — 41.5° at ζ = 0.05
against the quiet arms' 18.117° — which is slice 33's *"the ring is an FOV budget item"* and slice
34's *"the ring is spent in detector window"* arriving in a THIRD currency, the mechanical stop.

**FINDING 2 — "A WELL-DAMPED SECOND-ORDER GIMBAL HAS MORE MARGIN THAN THE SHIPPED HEAD" DOES NOT
GENERALISE AS WRITTEN, AND WHAT IT BECAME IS BETTER.** At ζ = 1.0 the onset depends on ω_n, and once
the grid is extended toward zero (a ladder that never rises has no bracket — slice 38's truncation
lesson mirrored) it is **MONOTONE IN THE INERTIA**:

| servo (ζ = 1.0) | onset bracket | cells vs the shipped head |
|---|---|---|
| 2nd 5.0 Hz | (−0.170, −0.165] | **0 — the CONTROL's own bracket** |
| 2nd 2.0 Hz | (−0.155, −0.150] | +3 |
| 2nd 1.0 Hz | (−0.130, −0.120] | **+0.045 of R̂** |
| 2nd 0.5 Hz | (−0.100, −0.090] | **+0.072 of R̂** |

⚠ **THE LAST TWO ROWS ARE QUOTED IN R̂, NOT IN "CELLS", AND THE REASON IS THE GRID** (advisor): they
were found on a **0.010** grid extended toward zero, because on slice 37/38's own 0.005 grid these
arms never ring at all inside it. Everywhere else in this family a "cell" means 0.005, so quoting
them that way would silently double the resolution they were measured at. The first three rows ARE
on the 0.005 grid and keep their cell counts.

⭐⭐ **⇒ THE SLICE'S CLEANEST SENTENCE: INERTIA IS NOT THE ENEMY — UNDAMPED INERTIA IS.** The SAME
added inertia buys +0.072 of R̂ of margin at ζ = 1.0 (⚠ in R̂, not "cells" — §1.2) and rings at
  every cell of the grid at ζ = 0.1.
**The damping decides the SIGN of what the inertia does**, which is why ζ is the slider and ω_n is
the wire.

⭐ **AND THE 5 Hz ROW EXPLAINS ITSELF, WHICH IS A CHECK RATHER THAN AN EXCUSE**: `τ_eff = 2ζ/ω_n =
0.0637`, within 27 % of the shipped τ = 0.05 — P0d's overdamped collapse, arriving in flight.

**P9d — THAT COLLAPSE, PINNED FROM BOTH SIDES.** Each second-order arm at large ζ against the
FIRST-ORDER arm at its own `τ_eff`: ratios **1.059 / 1.056 / 1.016 / 1.005**. ⚠ CLOSE AND NEVER
IDENTICAL, and always in the same direction (the second-order arm is louder — the residual phase).
⇒ the rung is not a reparameterization (slice 39), and the overdamped corner is where the button
goes quiet, stated rather than hidden.

---

## §2 GATE 2 — THE WIRED RUNG, AND THE PREDICTION IT REFUTED

The rung is `:head_servo = (:first_order, :second_order)` on the HELD `:seeker_head`, its keys are
`gimbal_omega_hz` / `gimbal_zeta` (validated at load — the ω_n ceiling is the INTEGRATOR's stability
limit with a 3× margin, §1.1, not taste), the rate state is `:head_rate_az` / `:head_rate_el`, and
`:head_servo_frame` stamps which ORDER last held it.

**§2.1 THE SHIPPED PATH REPRODUCES GATE 0 TO FIVE DECIMALS** on all six arms (0.01181 / 0.01212 /
0.51659 / 0.79973 / 0.07874 / 0.41555), which is what says no seam decision moved between the probe
patch and the ship — slice 39 §0.1's lesson, discharged rather than promised.

**§2.2 THE BIT-IDENTITY CONTROL IS THE ABSENT RUNG** (slices 35/36's blocking pin): `max|Δpos| =
0.000e+00` over 12 000 ticks both for `:first_order` against the rung absent, AND for `:first_order`
with ω_n/ζ authored beside it. ⇒ the keys are inert without the rung and the rung is inert without
the keys, BY CONSTRUCTION.

**§2.3 ⚠⚠ THE SEAM's OWN PREDICTION WAS REFUTED, AND IT IS THE THIRD REFUTED PREDICTION OF THIS
SLICE.** Gate 1 wrote — in `frames.jl`, in `missile.jl` and in this plan — that the resonance would
be nearly INERT on slice 37's space-stabilized rung, because such a head rejects body motion
passively and its index gain is 1 whatever its servo order. It is not inert:

| arm | rms r | miss | out% | off_max° | head° |
|---|---|---|---|---|---|
| SPACE, 1st order, R̂ = −0.28 | 0.04258 | 0.216 | 0.00 | 2.041 | — |
| **SPACE, 2nd 2 Hz ζ=0.10, R̂ = −0.28** | **0.26150 (6.1×)** | 0.535 | 0.00 | 4.007 | clear |
| BODY, 1st order, R̂ = −0.18 | 0.01181 | 0.187 | 0.00 | 1.956 | 18.117 |
| **BODY, 2nd 2 Hz ζ=0.10, R̂ = −0.18** | **0.51659 (44×)** | 4.914 | 0.00 | 3.647 | 22.878 |

⚠ **AND THE FIRST READING OF IT WOULD HAVE BEEN WRONG TWICE OVER.** Read at R̂ = −0.18 the space arm
shows `rms r` FALLING 1.00097 → 0.86014 while the miss opens 0.312 → 294.590 m — which is exactly
slice 33/34's METRIC INVERSION signature, so it is unreadable until `out_band` is known; and that
arm ALSO has its head pinned at the 30° stop with `off_max` 68.6°, i.e. a track broken OUTSIDE the
measurement band. The readable comparison is at R̂ = −0.28, where the space rung starts QUIET (it is
already ringing at −0.18 — slice 37's whole result — which makes −0.18 the worst possible place to
ask whether a servo changes anything).

⭐⭐ **WHY THE PREDICTION WAS WRONG, AND IT SHARPENS THE MECHANISM RATHER THAN DENTING IT: BODY
MOTION IS ONLY ONE OF THE TWO THINGS THIS SERVO IS FED.** The other is slice 34's own fixed point —
the head is aimed by the BENT measurement — and that loop is live on both frames. **A lag low-passes
whatever it is fed; a resonance amplifies it.** ⇒ the shipped wires use the body-referenced rung
because the effect is LARGER there (44× against 6.1×, each rung read at a design its own first-order
servo flies quiet), NEVER because the other rung is untouched. Corrected in all three places.

**§2.4 THE MID-RUN TOGGLE STARTS FROM REST**, and the stamp is what makes it so: running
second-order the rate state reads 0.091993 rad/s; 500 ticks of `:first_order` later it reads
0.000000 with the stamp at `:first_order`; one tick back on `:second_order` reads 0.000587 — a fresh
tick from rest, not the 0.091993 it left. ⚠ A first-order head HAS no rate state, so resuming one
would be a velocity the head never had.

---

## §0.8 WHAT SHIPS (the gate-1/2/3 scope, subject to the gates)

* **A RUNG, `:head_servo = (:first_order, :second_order)`**, on the HELD `:seeker_head =
  :body_referenced` rung — slice 24's shape (a rung on a held plant). ⚠ **THE CLAIM LIVES ON THE
  BODY-REFERENCED HEAD BY MECHANISM, NOT BY CHOICE**: a space-stabilized head rejects body motion
  passively (slice 37), so its index gain is 1 whatever its servo order. The resonance reaches the
  glass only through a servo that TRACKS OUT body motion.
* **TWO WIRES, ONE SLIDER EACH — ζ, THE DAMPING RATIO** (precedent: 22, 34, 36). Wire A holds
  ω_n = 2.0 Hz (a resonance INSIDE the loop's band — the GAIN failure), stop 30°; wire B holds
  ω_n = 0.5 Hz (a HEAVY gimbal below it — the PHASE failure, at a tenth of the gain), **stop 50°**
  (§1.2 Finding 1: its own ring needs 41.5° of travel). The CONTRAST BETWEEN THE WIRES IS THE
  PAYLOAD.
* ⚠⚠ **ω_n IS AUTHORED AND DISQUALIFIED AS A SLIDER BY MEASUREMENT** (slice 28's `k`, 4th
  occurrence): P5b's ω_n ladder is NON-MONOTONE in both directions at both dampings — at ζ = 0.3 it
  runs 0.079 → 0.107 (1 Hz) → 0.098 (2 Hz) → 0.019 (10 Hz) → 0.031 (30 Hz), because the resonant
  peak is a COINCIDENCE effect that must fall off on BOTH sides. The non-monotonicity is the lesson
  and the disqualification at once.
* **ζ IS MONOTONE ON BOTH WIRES AND IS THE SLIDER**: wire A 0.79973 → 0.01105 across ζ ∈ [0.05, 1.5]
  (72×), wire B 0.55230 → 0.01840 (30×), each flattening into the same ~0.011–0.02 quiet plateau the
  first-order head already sits on.
* ⚠ **`gimbal_rate_dps` IS AUTHORED WIDE (120 °/s) AND THE REASON IS MEASURED**: at the shipped
  40 °/s the rate limit binds 20–53 % of band ticks at ζ ≤ 0.1 — and it ATTENUATES the ring (0.65648
  against the free 0.79973 at ζ = 0.05), which is slice 35's own two-sided finding reproduced. At
  120 °/s `sat_band` is **0.00 % on every arm of both wires**, so slice 35's knob is provably not in
  the answer.
* **THE SHOWCASE IS ONE BUTTON PRESS ON A DESIGN THAT WAS ALREADY GOOD** (slice 37's shape): at
  R̂ = −0.18 — slice 34's own shipped design — the first-order head is QUIET at 0.01181 and the
  second-order head at ζ = 0.1 RINGS at 0.51659, **44×**, and still hits (4.9 m).

### Named risks carried into gate 1

* ⚠ **THE KERNEL MUST BE ONE KERNEL.** `head_slew_inertial` is `head_slew_full` with the frame
  changed, deliberately (slice 37's ⭐). The second-order servo must be the same shape — one law,
  one radial rate limit, one stop site — or `test_frames.jl` proves a second implementation and
  nothing about what flies.
* ⚠ **THE RATE STATE IS NEW PERSISTENT HEAD STATE** and it must be rung-gated exactly as
  `:head_i_az` is (the latent-bug class this arc has caught EIGHT times: 21's `_atm_on`, 23, 26, 27,
  29, 32, 34, 37).
* ⚠ **THE BIT-IDENTITY CONTROL IS THE ABSENT RUNG**, never an authored ω_n = ∞ (slices 35/36's
  blocking pin).
* ⚠ **GATE 3 WILL HAVE A MARKER HOLE** (advisor): a slice-40 wire raises slice 35's
  `gimbal_rate_view`, whose HUD pairs the tracking error against a detector window that never binds
  here — and slice 37's `gimbal_frame_view` too. Plan a new branch rather than discovering it in the
  shot.
