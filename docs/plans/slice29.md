# Slice 29 — `R̂(look)`: THE SCHEDULE THAT LOOKS THROUGH ITS OWN RADOME (§11 Tier-A)

The SEVENTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
radome-slope compensation autopilot, 28 = the slope CURVE), and the deferral slice 28 named as its
own successor:

> *"**LOOK-ANGLE-SCHEDULED `R̂(look)` — SLICE 29.** The engineering answer to this slice, exactly as
> 27 was to 26. Its single-point version is already measured here (P7.5, P9.4: a scalar tuned to
> `R(look_op)` quiets the wire)."* — `docs/plans/slice28.md`, named deferrals

Slice 26 built the disease. Slice 27 built the cure and measured its limit (a scalar `R̂` cancels to
the accuracy of the belief). Slice 28 showed the glass has no single slope, so the belief must be a
CURVE. Slice 29 builds that curve into the compensator — **and finds that making the compensator a
FUNCTION OF THE LOOK ANGLE gives it a parasitic path of its own**, because the look angle it must
index on is the one the radome has already bent.

**Status: PLANNED. Gate 0 COMPLETE — 9 probes, three refutations, two advisor passes; raw findings
and the probe scripts live in `M:\claud_projects\temp\slice29\GATE0_FINDINGS.md`.**

---

## The one-paragraph statement of the lesson

A scheduled compensator has to be evaluated *somewhere*. The only look angle a guidance computer
possesses is the one it computes from its own measurement — and that measurement is exactly what the
radome bent. So the schedule lands at the **wrong point on its own curve**, by about `R̂'·(bend)`,
and the belief that actually reaches the loop is not the belief that was designed. The consequence is
not academic and it is measurable both ways: on this wire the compensator's index runs 2.4–2.7° below
truth, and a schedule whose curve is exact *as a model of the glass* can leave a critical residual,
while a schedule whose curve is badly wrong as a model can leave almost none. **Slice 26/27/28's
residual law does not need a new term — it needs to be read where the belief is actually evaluated.**
Slice 27's rate-domain corrector was immune to all of this, and the reason it was immune is the thing
nobody had to notice: a CONSTANT `R̂` has `R̂' ≡ 0`, so it cannot care where it is evaluated.

> **THE LESSON, IN ONE SENTENCE.** A scheduled compensator must be indexed on the look angle it
> *has*, which is the one the radome already bent — so what closes the loop is the residual measured
> at the COMPENSATOR'S OWN INDEX, the schedule's own slope `R̂' = dR̂/dlook` is the sensitivity that
> decides what that indexing error costs, and slice 27's rule "compensate with a signal that is not
> itself corrupted by what you are compensating" comes back in the RATE domain — the place slice 27
> concluded was safe — because **the immunity was never the domain, it was the constancy.**

⚠ **INHERITED LANGUAGE AND ITS PROHIBITIONS.** The instability is still slice 26's — a true
positive-feedback loop, a loop gain, a stability boundary, self-excitation from zero input. Slice
20's "degenerative spiral" language stays forbidden here; slice 26's stays forbidden elsewhere.
Slice 29 adds **no new instability and no new cap** — it adds a second GAIN to the existing loop,
exactly as slice 28 made that loop's gain a function of the flight condition.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⚠⚠ THE FIRST PLAN WAS REFUTED TWICE, AND THE REFUTATIONS ARE LOAD-BEARING (P1, P2, P3)

The obvious slice 29 is *"a scalar cannot cancel a curve; schedule it and it can."* **It is false on
this plant**, and the two measurements that killed it must be written down, because every future
reader will propose it again.

**P1 — the look angle does not move.** On a settled PN collision course `V_M·sin(L) = V_T·sin(aspect)`
with the LOS direction fixed ⇒ **the lead angle `L` is CONSTANT BY CONSTRUCTION**. Measured on a
STABLE arm (flat glass; a ringing arm's look angle swings *because* it rings — slice 28 §1's
discipline), slice 28's own wire gives `look_az` = 14.9/15.1/15.1/15.1/15.1° at the 5/25/50/75/95
percentiles: a **0.2° band**. ⇒ **a schedule evaluated there IS a scalar**, and slice 29 in the naive
form would be FALSE FIDELITY (the slice-15 `k_δ`-cancellation / slice-16 refusal class).

Only three things break the constancy, and only one is not pre-poisoned: a MANEUVERING target
(⚠ `_lateral_accel` is hard-coded to the x–z plane, so it sweeps ELEVATION — the probes patch it to
x–y to sweep the AZIMUTH lead the lesson lives in); MISSILE SPEED BLEED (⚠⚠ **POISONED** — `V` moves
`Q` and slice 26 measured `|R_crit| ∝ ρ`, so it would move the look angle AND the loop gain together,
slice 28 §2's confound class); or the launch transient (already excluded by slice 28 §7's
measurement, `rms r` 0.172 whole-approach vs 0.0138 in band).

**P2 — and opening the band does not license it.** The adversarial test (advisor): sweep `R̂` as a
scalar across its whole domain, take the MINIMUM `rms r`, compare to the exact schedule. A post-hoc
optimum is a strictly unfair advantage for the scalar — no engineer tunes `R̂` after flying the
engagement — which is exactly why beating it would mean the schedule wins structurally. It does not:

| wire (band) | best scalar | its `rms r` | exact schedule | ratio |
|---|---|---|---|---|
| frozen (0.2°) | −0.11 | 0.01154 | 0.01087 | **1.06×** |
| turn a_lat 40 +1 (10.0°) | −0.09 | 0.07355 | 0.07553 | **0.97×** |
| turn a_lat 40 −1 (14.2°) | −0.09 | 0.08217 | 0.07648 | **1.07×** |
| turn a_lat 80 +1 (16.8°) | −0.11 | 0.21691 | 0.15522 | 1.40× |

⭐ **THE REASON IS ARITHMETIC:** a CENTRED scalar leaves at most ± half the slope SPAN across the
visited band. At `A = −0.05` the glass's entire range is `|2A| = 0.10`, so that half-span is 0.05 —
just inside slice 28's measured onset residual (≈ 0.055). **The band being open is not enough; the
SLOPE SPAN across it must exceed twice the onset.**

**P3 — and deepening the glass on a sweeping wire does not fix it either** (ratio only 1.2–1.6× even
where the best scalar's residual spans −0.06…+0.14, past the onset at the negative end). ⭐ **THE
REASON IS A REAL FINDING: the parasitic loop needs DWELL at a supercritical residual to build a limit
cycle.** A band the engagement SWEEPS THROUGH is visited briefly at every point, so no point gets the
dwell. ⇒ **the operating point must SIT STILL for the loop to ring.** Slice 28's frozen look angle
stops being an obstacle and becomes the ENABLING condition — which is why slice 29 keeps slice 28's
wire and does NOT add a maneuvering target.

⚠ P3's frozen-wire ratios of 6.3× / 30.8× are ARTEFACTS and must never be quoted: the scalar grid
truncated below `R₀+2A`, and a de-tuned arm's own look band moves, so the reported "best" was neither.

### 2. ⭐⭐ THE THIRD REFUTATION, WHICH IS A RESULT: THE CONSTRAINT IS ONE-SIDED (P4, P5, P6)

Rows = compensator, columns = engagement (crossing speed sets the sustained lead: vy 80/130/200/260
→ look 6.1°/9.8°/15.0°/19.1°). Glass `A = −0.10`; cells = `rms r`:

| compensator | vy 80 | vy 130 | vy 200 | vy 260 |
|---|---|---|---|---|
| `R̂ = −0.03` (boresight) | 0.753 RING | 1.022 RING | 1.093 RING | 1.048 RING |
| `R̂ = −0.13` | 0.013 | 0.013 | 0.904 RING | 0.687 RING |
| **`R̂ = −0.18`** | 0.020 | 0.017 | 0.012 | 0.012 |
| `R̂ = −0.23` (= `R₀+2A`) | 0.030 | 0.032 | 0.025 | 0.020 |

> ⭐⭐ **ONLY A NEGATIVE RESIDUAL RINGS; A POSITIVE ONE MERELY DE-TUNES** — slice 26's own finding,
> never before used as a design rule. So a SCALAR set at or below the most negative slope the glass
> reaches anywhere in the envelope is **UNCONDITIONALLY STABLE ACROSS THE WHOLE ENVELOPE**. ⇒ **GAIN
> SCHEDULING BUYS PERFORMANCE, NOT STABILITY**, and slice 27's "know your slope to within
> `0.38/(N·ρ)`" is a TWO-SIDED reading of a ONE-SIDED constraint. The design rule is **"know the most
> NEGATIVE slope your glass reaches over the envelope, and set `R̂` at or below it"** — a bound to be
> exceeded, not an estimate to be matched.

⚠ **AND THE PURCHASE IS NOT FREE, WHICH IS WHY A SCHEDULE IS STILL WORTH BUILDING** (P6). Over-
compensation DE-TUNES: `ω_ratio` (reported/true LOS-rate magnitude — the effective navigation ratio)
falls to 0.75/0.50/0.37/0.30/0.25 and the worst-case scalar's envelope MISS runs
0.20/1.08/4.15/14.14/**47.23 m** as the slope span goes 0.2/0.3/0.4/0.5/0.6. **The scalar has two
bounds — stability from below, accuracy from above — and they close on each other as the glass
worsens.** ⚠ This is the ENVELOPE claim, and it is NOT client-drivable (target velocity is not a comp
key): it stays a gate-0 finding and a named deferral, NOT a shipped proof (the slice-27/28 precedent).

### 3. ⭐⭐⭐ WHAT SLICE 29 ACTUALLY IS: THE SCHEDULE'S OWN SLOPE (P7A, P8, P9)

Build the schedule anyway — `R̂(look) = R̂₀ + Â·(1 − cos(k̂·look))`, the same functional form as the
glass — and something unplanned happens. With the level PERFECT (`Â = A`) and only the SHAPE varied,
at true glass `A = −0.15, k = 12, R₀ = −0.03`, vy = 200:

| `k̂` | `resid_op` = `R(look_op) − R̂(look_op)` | **`R̂'(op)`** | `rms r` (BENT index = shipped) | `rms r` (TRUTH index — counterfactual) |
|---|---|---|---|---|
| 6 | −0.151 | −0.90 | 0.988 RING | 0.932 RING |
| 8 | −0.060 | −0.97 | 0.894 RING | 0.731 RING |
| **9** | −0.038 | −0.90 | **0.829 RING** | **0.026 quiet** |
| **10** | **−0.016** | −0.69 | **0.637 RING** | **0.009 quiet** |
| 10.5 | −0.011 | −0.58 | 0.113 | 0.0095 |
| 11 | −0.005 | −0.42 | 0.0087 | 0.0102 |
| **12 (true)** | 0.000 | −0.02 | **0.0093** | 0.0117 |
| 14 | −0.014 | +0.91 | 0.0122 | 0.015 |
| 16 | −0.057 | +1.89 | 0.0157 | 0.026 |
| **17** | −0.087 | +2.32 | **0.0173 quiet** | **0.627 RING** |
| **19** | −0.157 | +2.85 | **0.0208 quiet** | **0.794 RING** |
| 20 | −0.183 | +2.92 | 0.447 RING | 0.800 RING |

⚠⚠ **THE `resid_op` COLUMN ABOVE IS A MEDIAN, AND ON A RINGING ARM IT IS CIRCULAR** (advisor,
blocking; P10). A ringing arm's look band is not the frozen 0.2° — the shipped `k̂ = 10` arm spans
**7.4–18.7°** against 14.5–15.0° for the quiet arms — so a median residual taken there describes the
ring, not its cause. Every residual claim below is instead evaluated at a common NON-RINGING
reference look angle (15°, from the quiet arms' band), with the compensator's MEASURED index error.

⭐ **AND THE ONSET WAS RE-MEASURED ON THIS WIRE RATHER THAN INHERITED** (slice 28's own rule: the
boundary constant is not geometry-free). A CONSTANT-`R̂` sweep — constant ⇒ `R̂' ≡ 0` ⇒ no index
sensitivity, so its residual is unambiguous — puts it at **≈ −0.056**: the least-compensating QUIET
arm (`R̂ = −0.27`) sustains −0.0556, and every arm with less compensation rings (0.572 / 0.764 /
0.876). Slice 28's ≈0.055 transfers — checked, not assumed.

⭐⭐⭐ **AND THEN THE LAW SURVIVES, READ AT THE COMPENSATOR'S OWN INDEX** (P10c). The index runs
2.4–2.7° below truth on every scheduled arm — that error IS the bend:

| `k̂` | residual at the TRUTH index | residual at the **BENT** index | measured outcome |
|---|---|---|---|
| **10** | −0.041 — sub-critical ⇒ predicts QUIET ✗ | **−0.067 — past −0.056 ⇒ RING ✓** | **0.637 RING** |
| 12 | 0.000 | −0.022 — sub-critical ✓ | 0.0093 quiet |
| **17** | −0.152 — past onset ⇒ predicts RING ✗ | **−0.001 — sub-critical ⇒ QUIET ✓** | **0.0173 quiet** |
| 19 | — | −0.046 — sub-critical ✓ | 0.0208 quiet |
| 20 | — | −0.064 — past onset ✓ | 0.447 RING |

> ⭐⭐⭐ **THE TRUTH-INDEXED RESIDUAL GETS TWO OF THREE WRONG; THE INDEX-SHIFTED ONE GETS EVERY ARM
> RIGHT.** That is the licensing fact, and it is stronger than "a second loop gain": slice 26/27/28's
> law is intact, and what slice 29 adds is that a SCHEDULE has an evaluation point at all, so the
> belief that reaches the loop is `R̂(look_bent)`, not `R̂(look_truth)`.

⚠ **`R̂'` IS THE SENSITIVITY, NOT A SUBSTITUTE FOR THE RESIDUAL.** `R̂'(look) = Â·k̂·sin(k̂·look)`
explains the SIZE and SIGN of the indexing error's cost, and the first-order form `δR̂ ≈ R̂'(op)·(index
error)` is quantitatively good away from `k̂ ≈ k` — but it FAILS at `k̂ = k`, where the operating point
sits at the curve's stationary point and the second-order term dominates (predicted −0.001 against an
actual −0.022). **Quote the index-shifted residual, which is exact; use `R̂'` to explain it.** This is
the copy-paste false-claim trap, caught twice in this slice's gate 0.

⭐⭐ **THE COUNTERFACTUAL IS DIAGNOSTIC IN BOTH DIRECTIONS**, which is what rules out a confound:
- `R̂'(op) < 0` **DESTABILISES**: `k̂` = 9/10 ring on sub-critical residuals, and freezing the index
  CURES them (0.829 → 0.026; 0.637 → 0.009, a **71×** split).
- `R̂'(op) > 0` **STABILISES**: `k̂` = 17/18/19 are quiet on residuals slice 26's law says must ring —
  and with a truth index they DO (0.017 → 0.627; 0.019 → 0.767; 0.021 → 0.794).

| | residual sub-critical | residual past onset |
|---|---|---|
| `R̂' < 0` | `k̂` = 9, 10 — **BENT rings, TRUTH quiet** | `k̂` = 6, 8 — both ring |
| `R̂' > 0` | `k̂` = 13, 14, 16 — both quiet | `k̂` = 17, 18, 19 — **BENT quiet, TRUTH rings** |

**A confound cannot produce a SIGN-REVERSING response to the same counterfactual** (slice 28 §2's
argument shape, one level up). ⭐ And the result is slice 27's own general rule recurring:
*"compensate with a signal that is not itself corrupted by what you are compensating"* — the rule
that killed slice 27's ANGLE-domain corrector, now live in the RATE domain. **Slice 27's immunity was
never the domain; it was the constancy** (`R̂' ≡ 0` for a scalar).

⚠ Note the two tables measure the SAME fact from two sides and must not be double-counted as two
findings: freezing the index removes the shift, so the truth-index column is simply the third column
of the table above evaluated with `δ = 0`. Quote ONE of them per claim, with its window.

⚠⚠ **THE COUNTERFACTUAL CANNOT SHIP AND MUST NOT BE FAKED.** A truth-indexed schedule requires the
guidance computer to read the true LOS, which slice 27 established would make the slice fake. So the
truth-index column is a **GATE-0 MEASUREMENT** (reproducible from `probe9_window.jl`), exactly as
slice 26 froze the geometry to measure a gain it could not identify in closed loop — NOT a shipped
tooth. What SHIPS as the proof is the pair the residual cannot explain (§7 phase 3), which needs no
unshipped path.

### 4. ⭐ THE ALIGNMENT WORRY, RAISED AND REFUTED (advisor; P8-B)

Slice 28 chose `k = 12` so the ripple PEAK lands on the ~15° operating lead. A peak is a STATIONARY
POINT, so a correctly-specified schedule on this wire sits exactly where `R̂' = 0` — the one place its
index error cannot hurt it, which would make the exact schedule's clean win an artefact. **Measured
and refuted:** a perfectly specified schedule (`k̂ = k`, `Â = A = −0.15`) is quiet at EVERY `k` from
6 to 20 — `rms r` 0.0101/0.0093/0.0090/0.0093/0.0104/0.0122/0.0167 at `k` = 6/8/10/12/14/16/20 —
even where `R̂'(op)` reaches +2.9. The win is structural.

### 5. THE METRIC, THE WINDOW, THE WIRE — ALL INHERITED FROM SLICE 28, DELIBERATELY

`rms r` (YAW) in the RANGE BAND `r ∈ [500, 3000] m`, for slice 28's measured reasons (the lead is in
azimuth so the ring is in yaw; a crossing wire's whole-approach `rms r` carries a legitimate
front-loaded baseline, 0.172 vs 0.0138 in band; arms with different ToF would otherwise compare
different parts of the engagement). ⚠ QUOTE THE WINDOW WITH EVERY NUMBER. ⚠ rms, NEVER the peak.
⚠ THE MISS IS NOT THE METRIC — every arm here hits (0.02–2.2 m).

⭐ **SLICE 29 KEEPS SLICE 28's GEOMETRY EXACTLY** — the same crossing target, the same launch, the
same window — because P1/P3 showed the frozen look angle is the ENABLING condition, not an obstacle.
Slice 28 broke the arc's shared static geometry for a measured reason; slice 29 has a measured reason
NOT to touch what 28 put there. ⚠ **The GLASS is not unchanged**: `A` goes −0.05 → −0.15 (AUTHORED,
not a knob). Slice 28's `A` floor of −0.10 was ITS knob's measured plateau; here `A` is the plant, and
−0.15 is what makes the `k̂` tolerance band wide enough to have an interior. Say "the geometry is
inherited, the glass is deepened" — not "the wire is unchanged". Validity is measured, not assumed:
`>30°` look = **0.0%** across every arm in P8/P9/P10, peak bend ≤ ~4°.

### 6. KNOBS: `Â` AND `k̂`; `R̂₀`, `A`, `k` AUTHORED

**KNOB 1 — `radome_ripple_k_est` (`k̂`), THE NEW ONE AND THE HEADLINE.** ⭐ **A LEGITIMATE KNOB, and
the contrast with slice 28's `k` is the point**: slice 28 DISQUALIFIED `k` for genuine oscillation
(quiet/rings/rings/marginal/QUIET/rings). Here the quiet window is a single CONNECTED band,
`k̂ ∈ [≈10.7, ≈19.5]` about a true `k = 12`, and **its ASYMMETRY IS THE LESSON**: over-estimate the
ripple frequency by 60% and stay quiet; under-estimate it by 15% and ring. Domain **`k̂ ∈ [6, 22]`**,
with BOTH endpoints measured as UNAMBIGUOUS rings (0.988 at 6, 0.787 at 22) — ⚠ the draft said 20,
where `rms r` is only 0.447, a MARGINAL edge; slice 26's post-commit rule is to measure the declared
endpoints rather than infer them from the interior, and here that moved the endpoint.

**KNOB 2 — `radome_ripple_est` (`Â`), the LEVEL half.** MONOTONE; ring onset between `Â = −0.13`
(0.357, marginal) and `−0.14` (0.0088); over-estimation safe and gentle (0.0093/0.0114/0.0161/0.0249/
0.0349 at −0.15/−0.17/−0.20/−0.25/−0.30) — §2's one-sidedness, now inside the schedule's own
amplitude. Domain **`Â ∈ [−0.30, 0]`**: the CEILING (0) is physical (the schedule collapses to slice
27's scalar `R̂₀`, and `radome_sched_slope` is then exactly 0 — the knob-vs-rung discriminator
MEASURED); the FLOOR is where over-estimation is still measured and gentle, and says so.

⚠ **CONVENTION 9 IS SATISFIED BY A MEASUREMENT, NOT BY COUNTING SLIDERS** (slice 28's shape): the two
knobs are the two halves of ONE object — the compensator's BELIEF about the curve, its LEVEL and its
SHAPE — and the core ships the quantity that decides (`radome_sched_slope`) as a number, so the
pairing is a reading rather than an argument.

**AUTHORED, NOT KNOBS:** `R̂₀ = −0.03` (the boresight belief, correct BY CONSTRUCTION since
`R(0) = R₀` for every `A` — slice 28's mechanism, inherited); `A = −0.15` and `k = 12` (the GLASS —
a knob on the plant would let a student move the thing the belief is being compared against);
`n_pn`, `rho`, `af_alpha_max`, `sigma_seek` DISQUALIFIED as in 26/27/28 and asserted ABSENT.

### 7. ⭐ THE SHOWCASE OPENS ON A DISEASE SLICE 28 COULD NOT HAVE STAGED

Author `Â = −0.15` (the level EXACTLY right) and `k̂ = 10` (the shape 17% low). Evaluated against the
glass at the reference look angle, that schedule is wrong by only **−0.041** — inside the −0.056
onset measured on this very wire — **and it rings at 0.637**, because where the compensator actually
evaluates it, 2.7° low, it is wrong by **−0.067**. Drag `k̂` to 12 and it goes quiet at 0.0093
(**68×**). Drag it to **17**, where the schedule is now wrong by −0.152 against the glass — **3.7×
the shipped arm's error and 2.7× past the onset** — and it **stays quiet**, because at its own index
it is wrong by only −0.001.

⭐⭐ **That is slice 28's headline one level up, and the numbers are the same shape.** Slice 28 opened
with the HARDWARE residual exactly 0.000 and it rang, because the ENGAGEMENT residual was not zero.
Slice 29 opens with a schedule that is a BETTER model of the glass than the one that works — and it
rings, because **a model is evaluated somewhere, and the somewhere is bent.**

---

## Gate plan

### Gate 1 — the pure kernels (`frames.jl`, beside slice 26/27/28's)

```julia
radome_schedule_slope(ripple_est, k_est, look) -> R̂'      # ripple_est·k_est·sin(k_est·look)
radome_compensation_scheduled(slope0_est, ripple_est, k_est, look_az, look_el, ω_body)
    -> (Δȧz, Δėl)
#   Δȧz = +R̂(look_az)·ω_z ,   Δėl = −R̂(look_el)·cos(look_az)·ω_y
#   with R̂(u) = radome_slope_curve(slope0_est, ripple_est, k_est, u)
```

⚠ **PER AXIS — slice 28's gate-2 hardening applied to the COMPENSATOR.** Slice 27's scalar law used
one `R̂` for both channels because there was only one. A schedule has two operating points on one
piece of glass (slice 28 §6's channel split), so the azimuth channel's gain is `R̂(look_az)` and the
elevation channel's is `R̂(look_el)`. An aggregate at `hypot(look_az, look_el)` is the gain of NEITHER.

Teeth (`test_frames.jl`):
- ⭐ **THE DERIVATIVE IDENTITY**: finite-difference `radome_slope_curve` in `look` and compare to
  `radome_schedule_slope`, tight `atol`, at several look angles. This pins the shipped telemetry to
  the kernel it CLAIMS to be the derivative of — the slice-28 integral-identity tooth's sibling, and
  what makes "the schedule's own slope is the second loop gain" a statement about shipped code.
- ⭐ **THE INDEX-SENSITIVITY SIGN TOOTH — the #1 SIGN TRAP's 11th occurrence.** Evaluate the scheduled
  compensation at a BENT look angle and at the TRUTH look angle on slice 26's FROZEN geometry; the
  difference must equal `R̂'·δlook·ω` to first order, and its SIGN must FLIP between a `k̂` below the
  true `k` and one above. ⚠ A test at ONE `k̂` passes for a constant-slope compensator and proves
  nothing (slice 28's two-look-angles rule, transposed to `k̂`).
- `ripple_est == 0` reduces to `radome_compensation` **bit-for-bit** (`==`), PAIRED with a
  does-schedule case (the slice-26/27/28 shape).
- `R̂(0) == slope0_est` exactly for every `ripple_est`; `radome_schedule_slope(·,·,0) == 0` exactly.
- the per-axis asymmetry: a pure yaw rate corrects `Δȧz` only, a pure pitch rate `Δėl` only, with
  the two channels' gains taken at DIFFERENT look angles (slice 27's tooth shape + slice 28's split).

### Gate 2 — the wired seam

`_observe_point3d!` (`missile.jl`): inside the existing `_comp_on` block, `_sched_on = haskey(c,
:radome_ripple_est)` chooses `radome_compensation_scheduled`, else `radome_compensation` **VERBATIM**
— the FOURTH nesting level of the slice-20/21/26/27/28 structural-byte-identity shape. Never the
scheduled kernel at zero amplitude (`x + 0.0` is not the identity at `x = −0.0`). ⚠ Rung-gated on the
LIVE `:airframe === :six_dof` via the inherited `_comp_on`, never on `haskey(:att_q)` — the
slice-21/23/26/27/28 latent-bug class, whose SIXTH occurrence this would be.

Loader (`scenario.jl`): `seeker.radome_ripple_est` and `seeker.radome_ripple_k_est`, validated finite
at LOAD; presence of `radome_ripple_est` is what mints the schedule.

⚠⚠ **WHICH LOOK ANGLE EACH KEY USES IS THE SLICE, SO IT IS SPECIFIED HERE AND NOT LEFT TO THE
IMPLEMENTER** (advisor). The seam already carries BOTH: `look_az` (TRUTH, off `û_tru` — where the
glass actually bends) and `look_az_c` (the compensator's own, off the BENT measurement — where the
belief is actually evaluated). The surrounding slice-28 code uses truth throughout, so the default
reading is wrong, and picking truth for both would **silently subtract the entire slice** (P10c: the
truth-indexed residual gets two of three arms wrong).

Telemetry (all scalars, `_finite*`, shipped only while the schedule is live):
- ⭐⭐ `radome_residual_az` — slice 28's key, whose FORMULA generalizes under a schedule to
  **`R(look_az) − R̂(look_az_c)`: the glass at the TRUTH angle, the belief at the COMPENSATOR'S OWN
  BENT INDEX.** This is the same QUANTITY (the engagement residual on the loop-closing axis) with
  `R̂` no longer constant, it is **the only version that predicts the outcome**, and a 26/27/28 wire
  is byte-identical BY GATING (no `radome_ripple_est` ⇒ the branch is dead; and for a constant `R̂`
  the two indices give the same number anyway, which is exactly why slice 27 never had to choose).
  ⚠ Stated explicitly rather than slipped in — a redefinition a prior verifier could read
  differently is the thing slice 28 refused.
- ⭐ `radome_sched_slope` — `R̂'(look_az_c)`, **at the BENT index too**: the SENSITIVITY that explains
  the size and sign of the indexing error, shipped as a NUMBER so the client never differentiates
  (convention 13, the `rho_air` precedent). ⚠ Label it a sensitivity, never "the loop gain" — §3's
  correction.
- `radome_slope_est_az` / `radome_slope_est_el` — the scheduled belief PER AXIS, each at ITS OWN
  channel's index (slice 28's `radome_slope_az`/`_el` sibling; the pair is the channel split on the
  compensator's side).

Determinism: draw count still exactly 2/tick; `Â = 0` bit-identical to `radome_ripple_est` absent;
slices 1–28 byte-identical, proven ON THE WIRE by re-running the 26/27/28 verifiers to the digit.
⚠ Class **4a**, FIFTH consecutive RNG-live slice — and since the ring/quiet gap here is 60×+, confirm
at gate 2 that the `k̂ = 10` ring survives a second seed (slice 26 measured self-excitation at
`σ_seek = 0`, but that is 26's measurement, not this one's).

### Gate 3 — scenario + the four proofs

`scenarios/slice29_radome_schedule.yaml`: slice 28's wire and crossing target UNCHANGED, glass
deepened to `A = −0.15` (`R₀ = −0.03`, `k = 12`), compensator `R̂₀ = −0.03`, `Â = −0.15`,
**`k̂ = 10`** — the showcase opens on the disease (the slice-25/26/27/28 shape).

`slice29_verify.gd`, FIVE drivable phases. ⚠ **Every residual assert is ONE-SIDED on the MOST
NEGATIVE value** (only a negative residual rings — §2) and is read from `radome_residual_az`, the
core's own index-shifted number; **none is a median taken on a ringing arm** (P10a: the shipped arm's
look band is 7.4–18.7°, not the quiet arms' 14.5–15.0°, so a median there describes the ring).

1. **RINGING** — the shipped wire: `rms r` ≈ 0.637 in band, WITH `radome_residual_az` reaching past
   the −0.056 onset that phase 2's arm never reaches. ⭐ The centrepiece.
2. **CURED** — `k̂ → 12`: quiet ≈ 0.0093, ratio ≈ 68×, `radome_sched_slope` → ≈ 0, and the residual
   stays sub-critical throughout.
3. ⭐⭐ **THE INVERSION** — `k̂ → 17`: STILL QUIET (≈ 0.0173) even though this schedule is a **worse
   model of the glass than the ringing one** — wrong by −0.152 against the true curve at the
   reference angle, 3.7× the shipped arm's −0.041 — because at its OWN index it is wrong by only
   −0.001. ⚠ The assert must compare LIKE WITH LIKE: `radome_residual_az` on both arms (both
   index-shifted), never one arm's index-shifted value against another's truth-indexed one.
   One drivable pair, the whole slice.
4. **LEVEL** — `Â → 0`: the schedule collapses to slice 27's scalar and rings hard (≈ 1.07), with
   `radome_sched_slope` exactly 0 — the knob-vs-rung discriminator and §2's one-sidedness in one arm.
5. **REPLAY** — held-seed bit-identical across a knob toggle.

`slice29_ui_test.gd` — an ELEVEN-way value guard (16/17/18/19/23/24/25/26/27/28/29) + the slice-28
HUD mirror; the button stays DROPPED (fifth slice in that family: 16, 26, 27, 28, 29), proven at BOTH
client sites. ⚠ NOT zero client code: one HUD line for `radome_sched_slope` beside the residual,
because the lesson is precisely that the residual is no longer the whole story — a student watching
only the residual sees phase 3 as a contradiction.

`Sandbox.tscn` headless smoke-load → `DONE`. TWO windowed shots at the same range: the shipped arm
RINGING with residual −0.016 and `R̂'` −0.69 displayed, and the `k̂ = 17` arm QUIET with residual
−0.087 and `R̂'` +2.32.

⚠ Verifier discipline inherited: assert one-sided; INTERPOLATE measured values into the pass text
(slice 25); `%g`/`%.2e` are NOT GDScript specifiers and an unknown one makes the whole `%` fail
silently on a GREEN run (slices 21, 25); a HIT samples COARSELY, so never compare two frame-sampled
CPAs (slice 27); both instruments must follow the RINGING channel — `omega_r` here, as in slice 28
(a peak-hold left on pitch meters the QUIET channel).

---

## Named deferrals (write them down; do not let them leak into this slice)

- **THE ENVELOPE / ONE-SIDEDNESS SLICE (§2)** — "gain scheduling buys performance, not stability;
  over-compensate deliberately to the envelope's worst-case slope, and pay for it in `ω_ratio`". Fully
  measured at gate 0 (P4/P5/P6) and NOT shipped, because it is a multi-engagement claim and target
  velocity is not a comp key. ⚠ Its enabling change is small and precedented — a presence-gated
  `cross_speed_mps` on `ConstantVelocity`, exactly slice 18's `alt_hold_m` — and it would ALSO retire
  the constraint that forced slice 28 to relocate two proofs. **The strongest single successor.**
- **ESTIMATING `R̂` IN FLIGHT** — still blocked by slice 26's P7A (the parasitic gain is not
  identifiable in closed loop), and slice 29 sharpens the obstacle: the estimator would have to
  identify a SHAPE from a signal whose index is bent.
- **AN IMPERFECT GYRO** (noise / bias / scale-factor) — open since slice 27, unchanged.
- **A 2-D SLOPE `R(look_az, look_el)`** and **AN ASYMMETRIC ERROR CURVE** — inherited from slice 28.
- **SEEKER FOV / GIMBAL LIMIT** — sharper again: this slice makes the schedule's INDEX a first-class
  quantity, and a gimbal limit truncates exactly that index.
- **THE OUT-OF-PLANE MANEUVERING TARGET** (slice 24 route (b)) — P1/P3 measured what it does here (it
  opens the look band but denies the loop its dwell), which is a finding it should inherit.

---

## Task checklist

- [x] Gate 0 — 10 probes; FOUR refutations (P1/P2/P3 killed the naive slice, P4/P5/P6 killed the
      envelope framing, P8 killed the residual-RANGE mechanism, P10 killed the residual-MEDIAN
      assert); three advisor passes — the adversarial best-scalar test that produced the refutations,
      the operating-point catch that produced §3, and the blocking catch that the centrepiece rested
      on two unmeasured numbers (the ringing arm's look band, and an onset inherited from a different
      configuration) and which reframed the mechanism from "a second loop gain" into "the same law,
      read at the compensator's own index". Raw findings in
      `M:\claud_projects\temp\slice29\GATE0_FINDINGS.md`.
- [ ] Gate 1 — `frames.jl` kernels + `test_frames.jl` teeth.
- [ ] Gate 2 — the `_observe_point3d!` seam + loader keys + telemetry; byte-identity on the wire;
      the second-seed check.
- [ ] Gate 3 — scenario + the four proofs; the 26/27/28 verifiers re-run to the digit.
- [ ] Docs — `docs/STATUS.md` as-built, `CLAUDE.md` status line, `HANDOFF.md` §11, memory.
