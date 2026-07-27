# Slice 27 — THE RADOME-SLOPE COMPENSATION AUTOPILOT: buying margin with a gyro (§11 Tier-A)

The FIFTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop) and the
one slice 26 named as its own successor:

> *"A radome-slope COMPENSATION / stability-margin autopilot — the engineering answer (a rate-gyro
> feed-forward that cancels the parasitic term). It is the natural slice 27 and it needs this one."*
> — `docs/plans/slice26.md`, named deferrals

Slice 26 built the disease: the seeker looks through glass that bends the LOS by `ε = R·(look
angle)`, so the missile's own body rate moves the LOS it reports, and past a loop gain
`N·|R|/ρ ≈ 0.38` the missile shakes itself into a sustained limit cycle. **Slice 27 is the cure —
and the point of the slice is that the cure is PARTIAL, in a way that is exactly quantifiable.**

**Status: GATE 0 COMPLETE (6 probes run 2026-07-27, `M:\claud_projects\temp\slice27_gate0\`).**

---

## The one-paragraph statement of the lesson

The missile already carries a rate gyro — the α/β autopilot has been feeding on `:omega_body` since
slice 23. So subtract the parasitic term back out: the seeker reports a LOS rate, the gyro says how
fast the body is rotating, and slice 26 measured the coupling exactly (`ε̇_el = +R·cos(look_az)·ω_y`,
`ε̇_az = −R·ω_z`). Feed that forward with the slope you BELIEVE your radome has, `R̂`, and the
parasitic path is cancelled — **to the accuracy of your belief.** What is left driving the loop is
the **residual** `R − R̂`, and slice 26's stability boundary comes back unchanged with `R` replaced
by that residual. So compensation does not delete the loop; **it moves the boundary, one-for-one**,
and the design question stops being *"how good is my radome?"* and becomes *"how well do I KNOW my
radome?"* — with a number attached.

> **THE LESSON, IN ONE SENTENCE.** A rate-gyro feed-forward cancels the radome's parasitic term to
> the accuracy of the slope estimate it is given, so what closes the loop is the RESIDUAL `R − R̂`
> and slice 26's boundary becomes `N·|R − R̂|/ρ ≈ 0.38`: compensation buys MARGIN, not immunity, and
> the design requirement is not a better radome but a better-KNOWN one — here, known to ±0.0475.

⚠ **THIS SLICE INHERITS SLICE 26's LANGUAGE, INCLUDING ITS PROHIBITIONS.** The instability is still
slice 26's — a true positive-feedback loop with a loop gain, a stability boundary and
self-excitation from zero input. Slice 20's "degenerative spiral" language is still forbidden here,
and slice 26's is still forbidden everywhere else. Slice 27 adds NO new instability; it adds a
**second term inside the same loop gain**.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⭐⭐ THE BOUNDARY IS ON THE RESIDUAL, AND IT SHIFTS ONE-FOR-ONE (P2A, P3A)

At fixed `R̂`, sweeping the true slope `R` down until the body rate erupts gives an onset whose
**residual is constant**:

| R̂ | 0.000 | −0.050 | −0.100 | −0.150 | −0.200 | −0.300 |
|---|---|---|---|---|---|---|
| onset R | −0.095 | −0.145 | −0.195 | −0.245 | −0.300 | −0.400 |
| **onset residual `R − R̂`** | **−0.095** | **−0.095** | **−0.095** | **−0.095** | **−0.100** | **−0.100** |

An **OFFSET**, across a 6× span of `R̂`. And slice 26's loop gain survives the substitution
verbatim — measured at `R̂ = −0.20` held, so every one of these is a COMPENSATED missile:

| N | 3 | 4 | 5 | 6 | 8 |
|---|---|---|---|---|---|
| onset R | −0.330 | −0.300 | −0.280 | −0.265 | −0.250 |
| residual | −0.130 | −0.100 | −0.080 | −0.065 | −0.050 |
| **N·\|residual\|/ρ** | **0.390** | **0.400** | **0.400** | **0.390** | **0.400** |

| ρ | 0.6 | 1.0 | 1.5 | 2.0 |
|---|---|---|---|---|
| **N·\|residual\|/ρ** | **0.400** | **0.400** | **0.387** | **0.390** |

Slice 26's uncompensated figures were 0.390 / 0.380 / 0.400 / 0.390 / 0.400 and 0.400 / 0.380 /
0.388 / 0.380. **The same law, to the third digit, with `R` → `R − R̂`.** ⚠ Say "MEASURED boundary",
never "identity" — this is slice 26's rule, unchanged (contrast slice 21's ρ-factor and slice 22's
`α_stall/α_max`, which ARE algebraic identities).

**⭐ THE TEACHING PAYLOAD IS A REQUIREMENT NUMBER.** Slice 26 sold the factorization as a design
trade — *"you cannot buy N without buying glass."* Slice 27 adds the third currency: **or you can
buy a gyro and know your glass to within `0.38/(N·ρ)`.** On the shipped wire (N = 8, ρ = 1) that is
**±0.0475** — so a −0.10 radome with a manufacturing spread worse than about ±0.05 rings anyway,
compensator or not. That is a specification an engineer can actually write down.

### 2. ⭐⭐ THE ISOLATION, AND IT IS THE SAME MEASUREMENT AS THE HEADLINE (advisor)

**The sharpest risk in this slice is that the compensator quiets the ring by DE-TUNING rather than
by cancelling.** Slice 26 measured (P7A) that in closed loop `ėl` and `q` are COLLINEAR — R² = 0.999
— because a tracking missile pitches at very nearly the rate the LOS rotates. Subtracting
`R̂·cos(look_az)·ω_y` from `ėl` is therefore numerically near-indistinguishable from SCALING `ėl`
DOWN, i.e. from lowering the effective navigation constant. **A "compensator" that works by
de-tuning is not a compensator, and it would quiet the ring just as convincingly.**

Two discriminators, both measured:

- **THE ONE-FOR-ONE SHIFT IS ITSELF THE ISOLATION.** A de-tuner's onset would move with `R̂` as a
  GAIN; §1's table shows it moving as an OFFSET, with the residual pinned at −0.095 across a 6×
  span. A gain cannot do that.
- **THE MISS STAYS AT BASELINE.** Slice 26 measured de-tuning's signature — sluggishness opens the
  miss (0.23 → 7.66 m at R = +0.6). On the diagonal `R̂ = R` the miss stays at the no-radome
  baseline all the way to R = −0.30 (0.316 / 0.304 / 0.108 m at R = −0.10 / −0.20 / −0.30 against a
  0.024 m baseline at R = 0). Ring down **and** miss at baseline ⇒ cancellation, not de-tuning.

⚠ **AND SLICE 26's OWN ISOLATION IS RE-RUN AND STILL HOLDS (P4A, P5C).** `aero_sat == 0` remains
impossible (an oscillation drives demand into the ceiling — 99.8% on the uncompensated arm), so the
isolation is slice 26's: **raise α_max 3× (0.3 → 0.9) and the CROSSING DOES NOT MOVE** — it stays at
`R̂ = −0.055` while the amplitude grows (rms q 0.844 → 2.568, max|q| 1.42 → 4.34). The ceiling bounds
the cycle; the RESIDUAL decides whether there is one. The other caps are clear on the shipped arms:
`defl_sat` 0.01–0.02% (cap #3), ceiling 329.87 ≪ `a_max` 3000 (cap #1), max|α| 0.156 < α_max 0.3
(no clamp leak, and this wire ships no `aero_curve` at all).

### 3. ⚠⚠ THE EQUIVALENCE IS PARTIAL — AND THIS IS THE FINDING THAT KEEPS THE SLICE HONEST (P3B)

The tempting sentence — *"compensation is equivalent to a better radome"* — is **REFUTED as
written.** The residual predicts the STABILITY BOUNDARY exactly; it does **not** make `(R, R̂)` the
same missile as `(R − R̂, 0)`:

| R | R̂ | residual | compensated rms | bare rms | compensated miss | bare miss |
|---|---|---|---|---|---|---|
| −0.30 | −0.20 | −0.100 | 0.779 | 0.884 | 3.480 | 2.130 |
| −0.40 | −0.30 | −0.100 | 0.605 | 0.884 | 0.521 | 2.130 |
| −0.30 | −0.45 | +0.150 | 0.0092 | 0.0074 | **31.418** | **0.470** |
| −0.20 | −0.30 | +0.100 | 0.0105 | 0.0078 | **2.397** | **0.188** |

**Why, physically, and it is worth writing down:** the radome's error moves with the LOOK angle, and
the look angle moves for TWO reasons — the body rotating (which the gyro sees) and the LOS itself
rotating (which it does not). The feed-forward cancels the body-rate half **exactly**, which is why
the stability boundary lands exactly on `R − R̂`; the LOS-driven half survives, so the seeker still
mis-reports the LOS rate and the missile is not restored to a clean-radome missile. **A gyro can
only cancel what a gyro can see.**

⇒ Write the claim as: *the residual sets the STABILITY BOUNDARY*, never *the residual is an
equivalent radome*. The over-compensated rows above are the proof and they must be quoted with it.

### 4. ⭐ THE ARCHITECTURE MATTERS, AND THE CLASSIC ONE WINS FOR A MEASURABLE REASON (P2A, P2B, P5D)

Gate 0 built BOTH candidate compensators rather than assuming the named one (advisor):

- **`:rate` — the rate-gyro FEED-FORWARD**, on the tracker's output rate. What slice 26's deferral
  literally names, and what ships.
- **`:angle` — an ANGLE-DOMAIN corrector**, subtracting `R̂·look_est` from the measured angle ahead
  of the tracker. Superficially the cleaner idea: it removes the bend itself.

The angle-domain arm **fails**, and the failure is instructive. Its onset residual DRIFTS instead of
holding — −0.095 / −0.090 / −0.080 / −0.065 / −0.045 / −0.005 as `R̂` goes 0 → −0.30 — and on the
diagonal, **with PERFECT knowledge `R̂ = R = −0.50`, it RINGS anyway** (rms 0.844, miss 131 m) where
the rate arm stays quiet (rms 0.014).

**The reason is a general principle worth more than the slice:** the angle-domain corrector needs
the LOOK ANGLE, and it can only obtain that by rotating the MEASURED LOS into the body frame — a LOS
it can only see **through the very bend it is trying to remove**. Its correction is therefore
self-referential, and the error is second order in `R·R̂`, which stops being small exactly when the
glass gets bad. The rate arm's correction signal is the GYRO, which is **outside the corrupted
path**. ⇒ **Compensate with a signal that is not itself corrupted by what you are compensating.**

⚠ The advisor predicted the opposite defect (the α-β filter lags the parasitic term inside `ėl_est`
while the gyro path does not, so `:rate` might under-cancel). That effect is REAL but SMALL —
matched-knowledge rms 0.0097 vs the angle arm's 0.0082 at R = R̂ = −0.10, ~17% — and it is swamped
by the angle arm's self-reference defect. Measured, not argued.

⇒ **`:angle` does NOT ship** (convention 9 — one lesson per scenario; on the shipped wire the A/B is
weak anyway, rms 0.0135 vs 0.0208 at matched knowledge). It is recorded here as a gate-0 finding and
a named deferral.

### 5. ⭐ THE SHOWCASE WIRE IS SLICE 26's DESIGN TRADE, INSTANTIATED (P5)

The first candidate wire was slice 26's own (N = 4) with the glass made worse until the crossing
landed mid-slider: **R = −0.30. It was rejected, and MODEL VALIDITY is what rejected it** — not
taste, and not realism alone. P4C measured the price: look-angle deciles of 12–25° with **528/9924
ticks past 30°** (5.3%), i.e. the small-angle model `ε = R·look` asked to carry the lesson in the
band where it is weakest. (Slice 26's header does also call `|R| = 0.1` POOR and `|R| ≤ 0.03` good,
so −0.30 is 3× worse than "poor" — but that argument alone would not settle it, because the shipped
wire reaches the same loop gain from the OTHER extreme.)

**The shipped wire instead raises N and keeps the glass real: N = 8, R = −0.10, ρ = 1.0.** That is
precisely the missile slice 26's trade condemned — a snappy interceptor with a poor-but-real radome,
`N·|R|/ρ = 0.80`, twice the boundary.

⚠ **BE HONEST ABOUT THE SYMMETRY (advisor): N = 8 is the TOP of slice 26's own measured range**
(its table sweeps N ∈ {3…8}), so this wire sits at one extreme just as R = −0.30 sat at the other.
What separates them is not which extreme is "realistic" but which one keeps the model honest — and
that is a measurement: **6/9421 ticks past 30° here against 528/9924 there.**

⚠ **AND `n_pn` STAYS AUTHORED, NOT KNOB-EXPOSED.** Slice 26 disqualified it as a knob for a reason
that is *stronger* here, not weaker: N moves the loop gain the lesson is about, so a student could
cross the boundary with both slopes untouched and conclude the compensator did it (the
confounded-lever rule). Authoring it at 8 is a choice of operating point; exposing it would be a
second lever on the same quantity.

Measured:

| | R̂ = 0 (uncompensated) | R̂ = −0.10 (matched) |
|---|---|---|
| rms body pitch rate | **0.84405** | **0.01353** |
| max\|q\| | 1.435 | 0.081 |
| miss | 2.447 m | 0.316 m |
| aero_sat | 99.8% | 0.1% |
| look angle > 30° | 6/9421 ticks | 2/9369 |

**Contrast 62.4×**, and the look-angle budget is now slice 26's own (6 ticks vs its 6/9400). The
predicted crossing `R̂ = R + 0.38/N = −0.0525` lands at a **measured −0.055**.

⭐ **AND THE SHOT WILL DISCRIMINATE — CHECKED AT GATE 0, NOT DISCOVERED AT GATE 3 (advisor, P7).**
Because the uncompensated arm still HITS, the two shots cannot lean on the trajectory, so the
discrimination was measured in advance at a matched range (r ≈ 3650 m): **q = −1.074 vs +0.017
rad/s**, and — the thing the 3-D view actually DRAWS — the nose-off-velocity gap α **wags 11.86°
peak-to-peak over a ±0.25 s window versus 0.07°**, i.e. a visibly shaking nose at ~2 Hz against a
dead-still one. Even the path shows it: 40.08 m of deviation from its own chord versus 8.44 m.

⚠ **THE METRIC IS THE OSCILLATION, NOT THE MISS — slice 26's discipline, and this wire enforces it
rather than tempting you away from it.** The uncompensated arm still HITS (2.447 m). rms body rate,
never the peak (peaks overlap across the threshold), never the miss (not monotone anywhere). ⭐ And
the rms metric is FRAME-ROBUST here as it was in slice 26 — per-tick 0.81712 vs frame-sampled
0.81704 (ratio 0.9999) on the ringing arm — which is exactly why it beats any miss.

### 6. ⭐ TWO KNOBS, AND THE SECOND ONE IS WHAT MAKES THEM ONE LESSON (P6A, P6B, P6D)

Slice 26 shipped ONE knob. Slice 27 ships **two — `radome_slope` (R, the glass) and
`radome_slope_est` (R̂, the belief) — and convention 9 is satisfied not by counting sliders but by
the measurement that they are two halves of ONE quantity.** Three measurements say so:

- **THE DIAGONAL (P6A).** Move both together and NOTHING HAPPENS: rms q 0.019 / 0.016 / 0.014 /
  0.012 / 0.011 at R = R̂ = 0 / −0.05 / −0.10 / −0.20 / −0.30, quiet all the way to −0.80. **The
  missile does not care about glass it KNOWS about.**
- **BOTH KNOBS CROSS AT THE SAME RESIDUAL (P6D).** Dragging R̂ with R held at −0.10 crosses at
  **R̂ = −0.055** (residual −0.045); dragging R with R̂ held at −0.10 crosses at **R = −0.145**
  (residual −0.045). Same number, from opposite directions.
- **⭐ THE GRID (P6B) IS THE WHOLE SLICE IN ONE PICTURE** — stability is a DIAGONAL BAND in
  (R, R̂), not a rectangle, and **slice 26 is this grid's `R̂ = 0` column.**

The second knob also carries the half of the lesson the first cannot: **a compensated missile
meeting a radome it was not designed for.** R̂ held at −0.10, glass degraded to −0.145 → it rings
again. Margin, not immunity.

### 7. ⚠ COMPENSATION IS NOT FREE — BUT THE COST IS OUTSIDE THE SHIPPED DOMAIN, AND THAT IS STATED

Over-compensating pushes the residual POSITIVE, into slice 26's deferred de-tuning face (the seeker
under-reports, the effective navigation ratio sags, the miss opens from sluggishness). Measured on
the shipped wire (P6C), R = −0.10 held:

| R̂ | −0.10 | −0.20 | −0.30 | −0.40 | −0.50 | −0.60 | −0.80 |
|---|---|---|---|---|---|---|---|
| residual | 0.000 | +0.100 | +0.200 | +0.300 | +0.400 | +0.500 | +0.700 |
| miss (m) | 0.316 | 0.333 | 0.619 | 2.918 | **18.843** | **64.142** | **214.208** |

⚠ **It does not bite inside a sane knob domain** — at the domain floor R̂ = −0.15 the miss is
0.236 m. So unlike slice 16's `af_cma` and slice 26's own `radome_slope`, **this knob does NOT show
two failure modes on its two sides within its domain**; it shows one, and the other is recorded here
as a measurement with the domain stopping well short of it. Do not sell the `af_cma` shape here.

⚠⚠ **AND THEREFORE SAY WHAT ACTUALLY SETS EACH DOMAIN — slice 26's post-commit lesson was exactly
"measure the endpoints, don't infer them", and half of these endpoints are NOT set by a measurement
(advisor).** Stating that plainly is the honest move:

- **`radome_slope_est` R̂ ∈ [−0.15, 0.00] — the floor is UI FRAMING, not physics.** The crossing at
  −0.055 sits at 37% of travel, and the metric is MEASURED FLAT from −0.06 out to about −0.30 (rms
  0.0154 → 0.0119) with the de-tune face not biting until residual ≈ +0.3. −0.15, −0.20 and −0.30
  would all be defensible; the physics does not choose between them and the plan does not pretend it
  does. The CEILING (0.00) *is* physical: a positive R̂ compensates the wrong way and is a strictly
  worse radome (P1C measured it — R̂ = +0.10 against R = −0.10 misses by 25.99 m, matching slice
  26's bare R = −0.20).
- **`radome_slope` R ∈ [−0.20, 0.00] — the floor IS measured.** It is one clear step past the
  crossing at −0.145, deep enough that the ring is unambiguous (aero 99.7%, rms 0.820) while the
  look-angle budget still holds (8/9400 ticks past 30°). It also lands the residual at −0.10, the
  same residual slice 26 shipped as its own showcase — the two slices read side by side.

### 8. KNOB vs RUNG, and the button stays DROPPED

`atmosphere.jl`'s discriminator: *is the off-state (a) a distinct code path and (b) NOT
knob-reachable?* **`R̂ = 0` is an in-domain slider value AND bit-identical to the compensator not
existing** — measured, not argued (P1B: both candidate architectures at `R̂ = 0` are bit-for-bit the
shipped slice-26 seeker, `max|Δq| = 0.000e+00`, identical RNG state). ⇒ **KNOB**, exactly as slice 26
concluded for `R`, and `LIVE_FIDELITY_MODES` is UNTOUCHED.

⇒ **The button stays dropped** — slice 26's `radome_view` marker is inherited unchanged, and slice
27 adds no rung to cycle. Third slice in this family (16, 26, 27) with a slider lesson and no button.

⚠ **BUT NOT ZERO CLIENT CODE (advisor).** A student drags `R̂`, the ring dies, and `R̂` is nowhere on
screen — slice 26 already ate the *"a proof you cannot read is not a proof"* defect once at gate 3
(its HUD headline ran off the right edge). Slice 27's ONE client edit: the HUD's slope line gains
the ESTIMATE and the RESIDUAL — the quantity that actually decides — presence-gated on
`radome_slope_est` so a slice-26 wire is byte-identical. ⚠ **~38 characters at 20 px is the width
at `vp.x − 430`** (slice 26 measured it); the 15 px lines below it are wider but not unlimited.

### 9. WHERE THE CODE LIVES — PHASE 3, AND THE REASON IS WRITTEN DOWN NOT DEFAULTED (advisor)

The compensator is a GUIDANCE-computer function (it is the autopilot's answer to a sensor defect),
but it lands in `_observe_point3d!` — **phase 3, `observe!`** — and that is deliberate:

- the LOS-rate vector `ω` is ASSEMBLED there, from the α-β angle rates, by `los_rate_from_angles`;
  a phase-4 correction would have to re-assemble `ω` from angles the autopilot does not own;
- the correction is defined ON the angle rates (`ε̇_az`, `ε̇_el`), which exist only there;
- phase 1 < phase 3, so `:omega_body` is THIS tick's post-integrate gyro reading — the same state
  `build_env!` ships and `decide!` consumes (slice 23's discipline).

⚠ **AND THE COMPENSATOR NEVER READS TRUTH (advisor).** `_observe_point3d!` computes the radome's
look angle from `û_tru` — legitimate for the PHYSICS (the glass bends the real ray) but fake in the
CORRECTION. Its legal inputs are exactly three: `c[:att_q]` (own INS attitude), `c[:omega_body]`
(the gyro) and the MEASURED LOS. The look angle it uses is therefore computed off the BENT
measurement, so its own error is second order in the bend. A PERFECT gyro is a §1 named
approximation (slice 11's "Vc stays truth" precedent).

### 10. CLASS 4a, AND THE DRAW COUNT IS ASSERTED NOT ASSUMED (P6E)

The compensator adds NO `randn` — it is arithmetic on state that already exists. Third consecutive
RNG-live slice (25, 26, 27); the seed is load-bearing and conventions 3/11 apply. **Measured**: at a
fixed 5 s horizon the RNG state is bit-identical across `R̂ = 0` and `R̂ = −0.10`, and a same-seed
replay reproduces `max|Δpos| = 0.000e+00`.

---

## Gate plan

### Gate 1 — the pure kernel

`frames.jl` gains ONE function beside `radome_error`:

```julia
radome_compensation(slope_est, look_az, ω_body) -> (Δȧz, Δėl)
#   Δȧz = +slope_est * ω_body[3]
#   Δėl = -slope_est * cos(look_az) * ω_body[2]
```

⚠ **THE SIGNS ARE THE WHOLE FUNCTION AND THEY ARE THE #1 SIGN TRAP's 9th OCCURRENCE.** They are the
NEGATION of slice 26's parasitic gain, because compensation SUBTRACTS what the radome ADDED. The
first draft of this slice's plan had BOTH flipped (advisor), which doubles the parasitic term at
`R̂ = R` while still producing a plausible sweep — dragging `R̂` to the OPPOSITE sign quiets the ring,
and the slice gets written up backwards.

Teeth (`test_frames.jl`, beside slice 26's):

- `slope_est == 0` returns exactly `(0.0, -0.0)`-class zeros, PAIRED with a does-correct case (the
  slice-26 shape).
- ⭐ **THE CANCELLATION TOOTH, on the SAME FROZEN GEOMETRY slice 26 used**: `radome_compensation(R,
  look_az, ω) .+ eps_dot(R, ω)` ≈ 0 to the finite-difference tolerance, for pitch AND yaw rates.
  This is the tooth that would have caught the double sign flip — it PAIRS the new kernel against
  the shipped one instead of asserting it in isolation.
- Linearity in `slope_est` and in `ω`; a zero body rate corrects NOTHING at any slope (the parasitic
  path is a BODY-RATE path).
- ⭐ **THE AXIS-ASYMMETRY TOOTH (advisor) — the one the cancellation test alone would MISS.** Slice
  26's parasitic gain carries a `cos(look_az)` on the PITCH axis and NONE on the yaw axis. A
  compensator that applied the cosine to both axes, or to neither, still cancels at look_az ≈ 0 and
  would PASS a single frozen-geometry test taken at a small look angle — and this wire's deciles
  START at 14°, where `cos` is 0.97. So assert the axes SEPARATELY: a pure yaw rate `(0,0,ω_z)`
  corrects `Δȧz` ONLY, a pure pitch rate `(0,ω_y,0)` corrects `Δėl` ONLY, and the cosine is pinned
  at a look angle large enough to distinguish it from 1.
- ⚠ **NEVER an in-loop identification** — slice 26's P7A stands: `ėl` and `q` are collinear in
  closed loop (R² = 0.999, meaningless coefficients). Freeze the geometry.

**⚠⚠ GATE-1 FINDING — THE TWO-TERM LAW DOES NOT CANCEL EVERYTHING, AND THE TESTSET FOUND IT.** The
cancellation tooth FAILED on first run: the ELEVATION axis cancelled to 1e-16 but the AZIMUTH axis
left **0.005984** against a 2e-4 tolerance. The cause is in slice 26's own measured table, which
this plan quoted without noticing: for an OFF-BORESIGHT LOS a PITCH rate also moves AZIMUTH
(`ε̇_az/R = −0.0598` at `ω = (0,−1,0)`) — a CROSS-TERM the classic two-term feed-forward does not
model. **It is a §1 named approximation of the compensator, not a defect in it**, and it does not
touch the slice's claim, for a reason that is itself worth stating: **elevation is the channel that
closes the pitch loop** (gain 0.9487 vs the cross-term's 0.0598, ~16× down), and the residual law
was measured END TO END with this very law and held to ±3%. ⇒ the tooth now asserts the honest
thing — elevation cancels EXACTLY, azimuth cancels under pure yaw, and the pitch→azimuth residual
is PINNED at `R̂·k_cross·ω_y` against a cross-coefficient MEASURED from `radome_error` (never a
magic constant, convention 11). **On the loop-closing axis compensation is a slope offset; on the
other it is a slope offset plus a known second-order term.**

⚠ This is the SECOND time gate 0's headline survived a detail it had not modelled (the first: the
angle-domain arm's self-reference). Both were found by pairing the new kernel against the SHIPPED
one rather than asserting it in isolation.

### Gate 2 — the wired seam

- `_observe_point3d!` gains a compensation branch, structurally byte-identical (a BRANCH with the
  else-arm slice-26 VERBATIM — never `+ Δ` trusting `R̂ = 0 ⇒ Δ = 0.0`: the `-0.0` trap and float
  non-associativity, the slice-20/21/26 discipline).
- Gate: `haskey(c, :radome_slope_est) && haskey(c, :att_q) && get(w.fidelity, :airframe, :point_mass) === :six_dof`.
  ⚠ **RUNG-GATED ON THE LIVE `:airframe`, never on `haskey(:att_q)` alone** — the slice-21 `_atm_on`
  / slice-23 stale-readout / slice-26 latent-bug class, whose FOURTH occurrence this would be.
  `haskey(:att_q)` stays only as a crash guard (convention 5).
- Loader: `seeker.radome_slope_est`, validated finite, beside `radome_slope` (`scenario.jl:371`).
  ⚠ Authored under `seeker:` because that is the code site; §9 records why the physical home is the
  guidance computer.
- Telemetry (never-stale, gated on the same condition, all scalars, `_finite_coord`):
  `radome_slope_est` and ⭐ `radome_residual` = `R − R̂` — **THE quantity that decides**, shipped as a
  number so the client never subtracts (convention 13).

### Gate 3 — scenario + four proofs

- `scenarios/slice27_radome_comp.yaml` — seed 27, N = 8, R = −0.10, R̂ = 0 (⚠ **the showcase OPENS
  ON THE DISEASE**, the slice-25/26 shape: the body is already ringing when the client connects, and
  dragging R̂ down through −0.055 quiets it). Two knobs per §6.
- `net/slice27_verify.gd` — the lesson as a number (rms q ringing vs compensated, the crossing, the
  diagonal), the α_max isolation, bit-identical replay. ⚠ Assert the FLAG `aero_sat`, never a
  hand-rolled compare (the sets nest — slice 19/26).
- `net/slice27_ui_test.gd` — the HUD line + a value-guard including the slice-26 MIRROR (a radome
  wire WITHOUT `radome_slope_est` must render slice 26's line, proving a SWITCH not an `or`).
- `Sandbox.tscn` headless smoke-load; TWO windowed shots at the SAME range (ringing vs compensated).
- ⚠ `%g`/`%.2e` are NOT GDScript specifiers — an unknown one makes the WHOLE `%` fail silently on a
  GREEN run (slices 21 and 25 both shipped this bug). And the pass text must INTERPOLATE what the
  run measured, never quote a probe's number.

---

## Named deferrals (write them down; do not let them leak into this slice)

- **THE ANGLE-DOMAIN CORRECTOR** — built and measured at gate 0 (§4), not shipped. Its failure mode
  (a correction signal that is itself corrupted by what it corrects) is a general principle and
  could carry its own slice as a two-rung A/B on worse glass.
- **AN IMPERFECT GYRO** — noise, bias, scale-factor error. This slice's gyro is PERFECT (§9, a §1
  approximation). A biased gyro injects a constant false LOS rate; a scale-factor error is exactly
  a multiplicative error on `R̂`, i.e. it lands back on the residual — which makes it a cheap and
  well-motivated successor.
- **ESTIMATING `R̂` IN FLIGHT** — the adaptive/self-tuning answer. ⚠ Slice 26's P7A is the standing
  obstacle and it is a REAL one: the parasitic gain is NOT identifiable in closed loop (`ėl` and `q`
  collinear, R² = 0.999). Any such slice must first answer *what excites the estimate?*
- **A LOOK-ANGLE-DEPENDENT SLOPE `R(look)`** — slice 26's deferral, unchanged, and it composes
  sharply with this one: against a wiggly real slope curve a CONSTANT `R̂` is wrong almost
  everywhere, so the residual becomes a function of the geometry.
- **SEEKER FOV / GIMBAL LIMIT**; **monopulse / az×el CFAR**; **a measured `Vc`**; **the 3-D `:raw`
  arm**; **the out-of-plane MANEUVERING target** — slices 25/26's lists, unchanged.

---

## Task checklist

- [x] Gate 0 — the compensation hunt; FINDINGS above; advisor pass before gate 1.
- [x] Gate 1 — `frames.jl` `radome_compensation` + `test_frames.jl` teeth (4503 tests). ⚠ The
      cancellation tooth FAILED first and produced the cross-term finding above.
- [x] Gate 2 — the `_observe_point3d!` seam + loader key + telemetry (4545 tests).
- [x] Gate 3 — scenario + the four proofs; the 25/26 verifiers re-run to the digit. ⚠ TWO
      methodological defects caught by the proofs themselves: the verifier's first de-tune assert
      compared two FRAME-sampled CPAs (measuring the ~11 m grid, not the physics), and the first
      shot mislabelled the ringing arm because a limit cycle crosses zero twice per cycle.
- [x] Docs — `docs/STATUS.md` as-built, `CLAUDE.md` status line, `HANDOFF.md` §11, memory.
