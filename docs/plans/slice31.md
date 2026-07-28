# Slice 31 — AN IMPERFECT GYRO: THE COMPENSATOR AMPLIFIES ITS OWN SENSOR (§11 Tier-A)

The NINTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
radome-slope compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the
ENVELOPE and the one-sided constraint), and a deferral slices 27–30 all named:

> *"**AN IMPERFECT GYRO** (noise, bias, scale-factor error — this slice's gyro is PERFECT, a §1
> approximation; a scale-factor error is exactly a multiplicative error on `R̂`, i.e. it lands back
> on the residual, which makes it a cheap and well-motivated successor)."* — `docs/STATUS.md`,
> slice 27 named deferrals; repeated in slice 30's scenario header as a §1 approximation.

**Status: SLICE 31 COMPLETE (2026-07-28) — gate 0 (10 probes), gates 1 & 2 GREEN (5798 tests, 5644 →
+154), gate 3's FOUR PROOFS all green (verifier `S31V OK`, UI test `S31UI OK`, headless smoke-load,
two windowed shots). Slices 26/27/28/29/30 verifiers ALL re-run against this core and PASS — byte
identity proven ON THE WIRE, not read off the diff.**

⚠⚠ **THE GATE-3 TRAP THAT COST THE MOST, AND IT WAS ARITHMETIC, NOT PHYSICS: `STEPS` MUST BE A
MULTIPLE OF `emit_every`.** The server emits every 16th tick, so with `STEPS = 15000` the last frame
it ever sends is `t = 14.992` while `_drain_scan` waits for `t ≥ 15.000` — the run then hangs
SILENTLY, with no output at all, until `MAX_SECONDS`. It reads exactly like a slow wire, and it was
misdiagnosed twice as one (Godot's stdout is also block-buffered into a file or pipe, which hides
per-arm progress and reinforces the wrong story). What finally settled it was measurement, in this
order: the CORE runs 27k ticks/s on this wire (1.26× slice 30's, and the slice-31 seam + telemetry
account for 1.44× of that — worth knowing, and small); a MINIMAL client drains the same server at
~5000 ticks/s on BOTH wires (5063 vs 4975, so the emit path is not it); and the verifier itself
reaches `t = 14.40` in **2.89 s**. There was never a slowdown. `STEPS = 12800 = 16 × 800` — slice
30's 20000 = 16 × 1250 lands exactly, which is why it never showed this.

**Original gate-0 status: 7 probes. The advisor's reparameterization risk FIRED (the
equivalence is exact on the wire) and the slice was rebuilt around it as a DESIGN-RULE slice; the
headline is an EXCHANGE RATE confirmed at four aim points, and an honest negative result at realistic
gyro grades. Raw findings and probe scripts in `M:\claud_projects\temp\slice31\GATE0_FINDINGS.md`.**

---

## The one-paragraph statement of the lesson

Every compensator slices 27–30 built is a feed-forward path: it multiplies a RATE GYRO READING by a
believed slope and subtracts the product from the seeker's LOS rate. All four slices assumed that
reading is TRUTH. It is not, and the two ways it fails land in two different currencies that this
arc has never had to separate. A **SCALE-FACTOR** error is common-mode on the multiplication, so the
belief that actually reaches the loop is `R̂·(1+s)` — it lands exactly back on slice 26/27's residual
`R − R̂(1+s)`, moves the stability boundary, and inherits the ONE-SIDEDNESS slice 30 built its design
rule on (`s < 0` under-reads and walks the effective belief toward the ringing side; `s > 0` merely
de-tunes). A **BIAS** does not touch the belief at all: it injects a CONSTANT spurious LOS rate
`R̂·b` into the guidance loop — the arc's first ADDITIVE injection, where 26–30 are all multiplicative
gain errors — so it does not move the boundary, it moves the AIM POINT, and it is TWO-SIDED with no
safe direction. ⭐ And both terms are scaled by `|R̂|`, which is the quantity slice 30's design rule
DELIBERATELY MAXIMIZES: buying unconditional stability by aiming `R̂` at the glass's worst-case slope
multiplies the gyro's own errors by exactly the factor it bought the stability with.

> **THE LESSON, IN ONE SENTENCE.** A feed-forward compensator is an AMPLIFIER for the sensor that
> drives it, with gain `|R̂|` — so slice 30's "stability is unconditionally purchasable with a
> scalar" is purchased a SECOND time, in gyro quality, and the deeper you compensate the more of it
> you must buy.

⚠ **THE REPARAMETERIZATION TRAP IS THIS SLICE'S CENTRAL RISK, AND IT IS NAMED HERE BEFORE GATE 1**
(advisor, before any code): a common-mode scale factor is EXACTLY `R̂ → R̂(1+s)`, so the scale-factor
half ON ITS OWN adds **no new mechanism** — it walks a knob slice 27 shipped and slice 30 sweeps
across a domain that already exists. That is this project's own named trap (slice 15's `k_δ`
cancellation, slice 16's refusal of a path-bit-identical toggle, slice 20's "a rung must name physics
the knob can't express", slice 19's dead `speed` knob — the FALSE-FIDELITY class, 5th occurrence in
this arc). ⇒ **the exact equivalence is not a defect to be hidden, it is a TOOTH to be measured**,
and the slice's claim must be the thing the equivalence CANNOT express: that the error is
MULTIPLICATIVE, so its absolute size is `|R̂|·|s|` and slice 30's aim point must become
`R_worst/(1+s)`. Write this as a DESIGN-RULE slice, not a mechanism slice.

⚠ **INHERITED LANGUAGE AND ITS PROHIBITIONS.** The instability remains slice 26's — a true
positive-feedback loop, a loop gain, a stability boundary, self-excitation from zero input. Slice
20's "degenerative spiral" language stays forbidden here; slice 26's stays forbidden elsewhere.
Slice 31 adds NO new instability, NO new cap, NO new plant and NO new loop gain: it adds an ERROR
SOURCE on an existing signal path, and one of its two terms is a genuinely new KIND of entry
(additive, not multiplicative).

---

## Gate 0 — the probes (what must be MEASURED before the design is fixed)

| # | question | why it is load-bearing |
|---|---|---|
| P1 | Is `R̂_eff = R̂(1+s)` exact on the WIRE (not just algebraically)? To what tolerance? | The reparameterization trap. If exact ⇒ the scale-factor half is a tooth, never a headline. ⚠ `atol`, NEVER bit-identity: `R̂*((1+s)*ω) ≠ (R̂*(1+s))*ω` by float association (advisor). |
| P2 | Does `s = −1` (a DEAD gyro) reproduce slice 26's UNCOMPENSATED ring exactly? | A free degenerate tooth: the compensator's output vanishes ⇒ residual `R − 0`. |
| P3 | The SIDEDNESS split: does `s < 0` move the onset toward ringing and `s > 0` de-tune, on a wire where the perfect-gyro arm is QUIET? | The one-sided inheritance — the claim that ties slice 31 to slice 30's design rule. |
| P4 | ⭐ THE DISCRIMINATING MEASUREMENT: on a QUIET arm at fixed `b`, does the injected error scale as `\|R̂\|` (~11× from −0.03 to −0.33)? | Decides which half leads. Yes ⇒ the bias half carries the slice. No ⇒ lead with aim-point inflation, demote bias. |
| P5 | The PRODUCT LAW: is the steady-state true LOS-rate error ≈ `\|R̂·b\|`, linear in BOTH factors, reached from two directions? | ⚠ The metric must NOT be a frame-sampled CPA (slice 27's verifier ate exactly that defect; slice 30 §"the miss is not the metric"). A per-tick product law is also slice 30's convention-9 discriminator reused. |
| P6 | Which gyro AXIS does the bias have to be on? (`b_y` → `Δėl`, `b_z` → `Δȧz`.) | The crossing wire's loop-closing channel is AZIMUTH (rms r), so `b_z` is the candidate; measure, don't assume. Decides whether the shipped key is one scalar or two. |
| P7 | The SINGLE-IMU alternative, MEASURED not asserted: what happens if the SAME corrupted reading feeds the autopilot's `k_q` rate damping? | Slice 26: `k_q` supplies ~98% of the damping ⇒ corrupting it moves the ONSET by a different mechanism and destroys the exact `R̂(1+s)` equivalence. One probe, then a §1 named approximation whose mechanism is DAMPING, not RESIDUAL. |
| P8 | Knob domains, and the corner: `s`, `b`, `R̂` — where does each stop being monotone / blow the 30° validity budget / leak a cap? | Slice 30's discipline: domains MEASURED, endpoints measured rather than inferred from the interior (slice 26's post-commit correction). |
| P9 | Does gyro NOISE need to ship at all? | ⚠ Deferred on DRAW-TOPOLOGY grounds (convention 3): an unconditional 3rd draw breaks 25–30's wires bit-for-bit, and a host-marker gate is the slice-13 `:scan` 4b shape. Slice 25 also measured a ~1000:1 low-pass on the roll loop, so it may be DEAD anyway. State the reason; probe before ever shipping it. |

⚠ **KNOBS HELD AT SLICE 30's AUTHORED VALUES.** `cross_speed_mps` and `radome_ripple` stay AUTHORED
on this wire: slice 31's claim is PER-ENGAGEMENT, and stacking slice 30's envelope axis on top of it
violates convention 9 (advisor). The three candidate knobs are `s`, `b`, `R̂`, and they are legal iff
they are three terms of ONE quantity — measured by P4/P5, never by counting sliders.

## The seam (provisional — gate 1/2, revised by what gate 0 measures)

`frames.jl`, beside the radome family (body-frame MEASUREMENT error, and no new mode tuple ⇒ no
convention-1 ordering question):

    gyro_reading(ω_true, scale_err, bias) -> Vec3        # (1+s)·ω + b

`missile.jl` `_observe_point3d!` — a FIFTH nesting level inside `_comp_on`. ⚠ Keys absent ⇒ call
`radome_compensation` / `radome_compensation_scheduled` with the TRUTH `ω` VERBATIM, never
`gyro_reading(ω, 0, 0)` trusting the zeros (the `-0.0` trap + float non-associativity — the
slice-20/21/26/27/28/29 structural-byte-identity shape). At this depth a mis-nested else-arm is the
real risk ⇒ the check is a WIRE-LEVEL re-run of the 26/27/28/29/30 verifiers, not a reading of the
diff.

---

# GATE 0 — WHAT WAS MEASURED (the design, settled)

Full tables in `GATE0_FINDINGS.md`. Metric/window/channel INHERITED from 28/29/30 with their reasons:
**rms r (YAW), range band r ∈ [500, 3000] m, ring threshold 0.30.** ⚠ Quote the window with every
number. ⚠ rms, never the peak. ⚠ The miss is NOT the metric.

### 1. ⚠ THE ADVISOR'S RISK FIRED: THE REPARAMETERIZATION IS EXACT (P1)

`(R̂, s)` and `(R̂(1+s), perfect gyro)` fly the SAME FLIGHT — max|Δpos| 8e−12 … 2e−11 over five pairs,
and **BIT-identical in two of the five**. ⇒ the scale-factor half adds NO MECHANISM by itself and
ships as a TOOTH. ⚠ **`atol`, NEVER a byte claim** — three of five pairs differ in the last ULPs by
float non-associativity, so "exact" here means the PHYSICS, not the bits. Slice 31 is therefore a
**DESIGN-RULE slice**: what the equivalence cannot express is that the error is MULTIPLICATIVE.

### 2. ⭐⭐ THE HEADLINE — THE EXCHANGE RATE: SLICE 30's MARGIN **IS** A GYRO BUDGET (P6/P7)

⚠⚠ **STATE THIS IN THREE PARTS, AND DO NOT CALL IT A CONFIRMED PREDICTIVE LAW (advisor).** Given §1,
the boundary sitting at a fixed `R̂(1+s)` is FORCED — it is ALGEBRA, and the four-aim-point table below
is a consistency check on the harness, not independent evidence (the only way it could fail is if §1
were false; the ±0.008 drift in the effective belief is the `s` grid, not physics). This project
polices identity-vs-measurement in both directions — slices 21/22 call identities identities, 26/27
forbid calling a measured boundary one. So:

* **ALGEBRA:** the boundary depends on `R̂(1+s)` ALONE. Nothing is measured here.
* **MEASURED, ONE NUMBER:** `R̂_onset ≈ −0.260` on this wire, with a PERFECT gyro (rings at −0.2600,
  quiet at −0.2650) — the same quantity slice 30 measured as its rule's margin, re-measured here
  because slice 30's discipline is that an onset is re-measured on the wire that quotes it.
* **THE EMPIRICAL PAYLOAD:** the MARGIN RATIO `R̂_onset / R_worst = 0.260/0.330 = 0.79` ⇒ slice 30's
  conservative aim point tolerates a scale-factor error down to **−21%**. That is a property of slice
  30's rule ON THIS GLASS, and it is what the pencil-sharpening table actually demonstrates.

The conversion `s_min(R̂) = R̂_onset/R̂ − 1` is then arithmetic on those two numbers. Checked at FOUR
aim points spanning 1.67× in R̂ (4/4 inside the measured bracket, effective belief −0.2585 … −0.2614):

| aim R̂ | predicted s_min | measured bracket |
|---|---|---|
| −0.27 | −0.0370 | −0.0398 / −0.0318 |
| −0.30 | −0.1333 | −0.1370 / −0.1290 |
| −0.33 (slice 30's rule) | −0.2121 | −0.2165 / −0.2085 |
| −0.45 | −0.4222 | −0.4287 / −0.4207 |

⭐⭐ **THE PENCIL-SHARPENING PENALTY.** The same gyro on two designs: at `s = −0.05` slice 30's
conservative `R̂ = R_worst = −0.33` is QUIET (0.053) while a "tightened" `R̂ = −0.27` — aimed just past
the measured onset, which slice 30 explicitly warned against ("a bound to be exceeded, not an estimate
to be matched") — **RINGS (0.402)**. ⇒ the only difference between a stable and an unstable missile is
0.06 of deliberate conservatism, and slice 30's margin is revealed as a purchased quantity.

### 3. ⭐⭐ THE OTHER CURRENCY: A BIAS HAS NO RESIDUAL TO MOVE — AND THE MARGIN BUYS IMMUNITY TO IT TOO

Over the whole reachable range of `b_z`, BOTH signs, at slice 30's aim point, the miss moves **7500×**
(0.23 → 1735 m) and the stability verdict NEVER moves. ⇒ **the two error terms of one sensor land in
different currencies** — the scale factor on the RESIDUAL (a boundary), the bias on the AIM POINT (an
additive injection, the arc's first). ⚠ The `b_z` domain is set by the 30° small-angle budget,
measured: it blows at −0.14 / +0.18 (72% / 78% of in-band frames past 30°).

⚠⚠ **BUT "A BIAS NEVER RINGS" WAS TOO STRONG, AND THE HONESTY CHECK (P9/P10) FOUND IT.** A bias steers
the missile, which moves the LOOK ANGLE, which on CURVED glass moves the ENGAGEMENT residual — slice
28's mechanism arriving through the SENSOR. The curve's extremum sits at `k·look = π ⇒ look = 15°` and
this engagement holds ~13.6°, just below it, so a NEGATIVE bias walks the seeker UP ONTO THE STEEPEST
GLASS. Measured across `b_z` at five aim points:

| aim R̂ | margin past onset | verdict across the whole bias domain, both signs |
|---|---|---|
| −0.265 | 0.005 | **RINGS at b = −0.010 (0.302) and −0.020 (0.354)** — look walks to 14.5°/15.3° |
| −0.270 | 0.010 | quiet everywhere (max 0.103) |
| −0.280 | 0.020 | quiet everywhere (max 0.076) |
| −0.300 | 0.040 | quiet everywhere (max 0.085) |
| −0.330 (slice 30's rule) | 0.070 | quiet everywhere (max 0.101) |

⇒ the precise statement: **a bias has no stability verdict of its own — it has no residual to move —
but it can flip a MARGINAL design in either direction by moving the band the engagement visits, and it
cannot touch a design carrying slice 30's margin.** ⭐⭐ **SO THE MARGIN IS MEASURED TWICE, IN BOTH
CURRENCIES, AND IT IS THE SAME MARGIN:** the conservative aim point is what makes the missile
insensitive to its own sensor. That is the slice's unifying sentence.

### 4. FINDING 6 — the amplification is real, SUPER-linear, and clean ONLY on flat glass

At held `b`, the steady-state true-LOS-rate error grows **34× over an 18× range of |R̂|** on FLAT glass
(monotone; super-linear by 1.86× because over-compensation de-tunes, lowering the effective navigation
ratio, which amplifies a steady measurement bias further). ⚠ On the shipped CURVED glass it holds only
END TO END (1.94× against 1.96×) and is NON-MONOTONE in between, because the bias moves the look angle
and hence `R(look)` — slice 28/30's engagement coupling confounding it. ⭐ **THE COMPOSITION:** the
design rule for a gyro spec, `R̂ = R_worst/(1+s)`, deepens the aim point, which amplifies the SAME
gyro's bias (+67% at `s = −0.40`, every arm quiet). **Tolerance to one term is paid for in sensitivity
to the other.**

### 5. FINDING 7 — the SINGLE-IMU alternative, MEASURED, and its mechanism NAMED

Feeding the same corrupted rate to the α/β autopilot's damping too (temporary hook, reverted) moves
the onset (rings at `s ≤ −0.18` against −0.22) and **destroys the exact equivalence** (1.22369 against
the twin's 0.88472). ⇒ the §1 approximation states its MECHANISM: a single IMU adds a **PLANT-DAMPING**
error (slice 26: `k_q` supplies ~98% of the damping), not a residual one — two mechanisms at once,
which convention 9 forbids inside one lesson. NOT asserted; measured.

### 6. ⚠⚠ FINDING 8 — AT REALISTIC GYRO GRADES NEITHER TERM MATTERS, AND THAT IS THE POINT

`b = 2.1 °/hr` moves rms r by 0.00001; `s = −1%` moves it by −0.001. A tactical gyro is ~1–10 °/hr and
0.1–1%. ⇒ **the compensator's own sensor is not the weak link on slice 30's design**, and the reason is
QUANTIFIED: the conservative aim point buys a −21% budget, ~200× looser than the hardware. The
slice-15 "the lack of effect IS the lesson" shape (user-ratified). ⚠ It is also exactly why §2 is the
headline: **at the tightened aim point a REALISTIC 3–5% error is already at the boundary.**
⚠ The knob domains are chosen for VISIBILITY, not realism, and the scenario SAYS SO.

---

# THE SHIPPED DESIGN (gates 1–3)

**Class 4a** (7th consecutive RNG-live; 2 randn/tick UNCHANGED — deterministic gyro errors add no
draw; draw-count identity ASSERTED). **KNOBS, not rungs** — `s = 0` / `b = 0` are in-domain slider
values and the key-absent path is byte-identical (measured: 5644/5644 unchanged with the seam in).

**THE WIRE OPENS ON THE DISEASE, AND THE DESIGN THAT CATCHES IT LOOKS COMPETENT:** `R̂ = −0.27` (a
"tightened" aim point just past the measured onset) with `s = −0.05` (a realistic cheap-MEMS
scale-factor error) ⇒ **rms r 0.402, RINGING**. ⭐ TWO DIFFERENT CURES, one slider each: `s → 0` (buy a
better gyro, **13.0×** → 0.031) or `R̂ → R_worst = −0.33` (design more conservatively, **7.6×** →
0.053). ToF 11.1–11.3 s across the four arms; `aero_sat` 0.0% on every QUIET arm (1.5% on the ringing
one — slice 26: `aero_sat == 0` is impossible while ringing), so no aim-point claim is confounded by
slice 19's ceiling.

⚠⚠ **AND THE SCENARIO HEADER MUST SAY THIS OUT LOUD (advisor):** by §1 the opening disease is
BIT-FOR-BIT a slice-30 wire at `R̂ = −0.2565` with no gyro at all (measured: max|Δpos| 6.4e−11, rms r
0.40208 both) — so **the scale-factor half is a REINTERPRETATION of a shipped knob**, and cure A is
indistinguishable from dragging `R̂`. That is not hidden; it is the slice's own §1 finding. What the
bias adds is a state no existing knob on this wire reaches, and the wire ships the claim that needs it:

⭐ **TWO CURES FOR ONE DISEASE, AND ONLY ONE OF THEM IS FREE.** With the same gyro bias present, cure B
(design deeper) costs **1.68–1.75×** the aim-point error of cure A (buy a better gyro) — measured at
b = ±0.005/±0.010/+0.020, both signs, every arm quiet and `aero_sat` 0. Cure A fixes both currencies;
cure B trades stability for accuracy, because the deeper aim point amplifies the same bias.

**THREE KNOBS**, legal by convention 9 because they are the three terms of ONE product —
`R̂·((1+s)·ω + b)` — with the discriminator MEASURED TWICE (§1 and §2): `gyro_scale_err ∈ [−0.40,
+0.40]`, `gyro_bias_z ∈ [−0.08, +0.08]` rad/s, `radome_slope_est ∈ [−0.55, 0]` (slice 30's, inherited).
`cross_speed_mps` and `radome_ripple` revert to AUTHORED — slice 31's claim is PER-ENGAGEMENT.
`gyro_bias_y` ships as a supported comp key but NOT a knob (P6: it drives ELEVATION, Δazdot 14× smaller
on a crossing wire) — the channel split is a test, exactly like slice 28's per-axis curve.

**TELEMETRY.** New keys, gated on the gyro keys' presence: `gyro_scale_err`, `gyro_bias_z`,
`radome_slope_est_eff = R̂(1+s)` (**the belief the LOOP sees, shipped as a NUMBER** — convention 13, the
client never evaluates physics), and `radome_residual_az_eff` (the engagement residual read against
that effective belief). ⚠⚠ **`radome_residual` and `radome_residual_az` KEEP SLICE 27/28's MEANING
UNCHANGED (advisor).** Slice 28's headline IS that the hardware residual reads exactly 0.000 while the
missile rings; folding the gyro into that key would make its meaning depend on which keys are present.
Ship the gyro-effective residual ALONGSIDE and label both — two numbers from the same frames that
disagree is 28's and 29's own shape, it teaches better, and it leaves the 28/29/30 verifiers
structurally untouched instead of relying on equal values. ⚠ If the HUD shows the design-rule aim point
`R_worst/(1+s)`, `(1+s)` needs the conventions 5/6 floor — `s = −1` is reachable by a live slider.

**FOUR PROOFS (convention 14).** Verifier phases: RINGING (the shipped wire) → CURE A (`s → 0`) → CURE
B (`R̂ → R_worst`) → ⭐⭐ THE EXCHANGE RATE at two aim points (assert the EFFECTIVE BELIEF bracket, not
`s`) → ⭐ THE EQUIVALENCE tooth (`atol`, never bits) → THE BIAS never rings across its domain while the
aim point moves → bit-identical replay. Plus a UI test, a smoke-load, and two shots. ⚠ Byte-identity is
proven ON THE WIRE by re-running the 26/27/28/29/30 verifiers, not by reading the diff.

**§1 NAMED APPROXIMATIONS.** A SINGLE IMU is a deferral whose mechanism is DAMPING (§5, measured); gyro
NOISE is deferred on DRAW-TOPOLOGY grounds (convention 3) — not overlooked; a common-mode scale factor
across all three axes (per-axis scale factors and misalignment are a named deferral); everything slices
26–30 named is inherited unchanged.

---

# GATE 3 — WHAT THE WIRE MEASURED (the shipped numbers)

`S31V OK`, 17 arms, metric rms r (YAW) in the range band r ∈ [500, 3000] m, every arm reaching CPA
with `defl_sat` 0 and the look angle inside the 30° budget.

| arm | R̂ | s | b | LOOP SEES | rms r | verdict |
|---|---|---|---|---|---|---|
| **DISEASE** (shipped) | −0.2700 | −0.05 | 0 | **−0.25650** | **0.42395** | **RING** |
| CURE A (buy a better gyro) | −0.2700 | 0 | 0 | −0.27000 | 0.03186 | quiet (**13.3×**) |
| CURE B (design deeper) | −0.3474 | −0.05 | 0 | **−0.33000** | 0.05903 | quiet (**7.2×**) |
| EQUIV (the twin) | −0.2565 | 0 | 0 | −0.25650 | 0.42395 | RING |
| third aim −0.30 | −0.3000 | −0.145 | 0 | −0.25650 | 0.42395 | RING |
| third aim −0.30 | −0.3000 | −0.070 | 0 | −0.27900 | 0.03693 | quiet |

* ⭐⭐ **CURE B's effective belief lands on `radome_slope_worst` EXACTLY** (−0.33000 against −0.33000):
  slice 30's rule is not replaced, it is RE-AIMED, and the identity is asserted on the wire.
* ⭐ **THE REPARAMETERIZATION, ON THE WIRE:** DISEASE and EQUIV are the same flight to
  **max|Δpos| = 7.76e−10 m**, and their rms r agree to five decimals. Asserted as an `atol`.
* ⭐⭐ **THE BIAS NEVER RINGS** at slice 30's aim point across its whole domain, both signs (rms r
  0.13379 / 0.04631 / 0.07835 / 0.14453 at b = −0.08 / −0.02 / +0.02 / +0.08), with `aero_sat` **0 on
  every one** so no aim-point claim is confounded by slice 19's ceiling. The injection flips sign
  with b (+0.0264 → −0.0264 rad/s).
* ⚠ **AND THE NARROWED CLAIM IS ASSERTED:** on a MARGINAL design (R̂ = −0.265, 0.005 past the onset)
  with a PERFECT gyro, **b = −0.02 RINGS it (0.35210, look 18.7°) while b = +0.02 does not (0.05114,
  look 13.1°)** — the bias walks the seeker up onto the curve's steepest glass. The SAME pair leaves
  the conservative design untouched. ⇒ the margin is measured twice, in both currencies.
* ⭐ **THE PRICE — the one claim only the bias can produce: 1.97×.** With the same b = +0.01, curing
  by designing deeper costs 0.014586 rad/s of true LOS azimuth rate against cure A's 0.007413.
  ⚠ Measured on `los_azdot_true`, NEVER on `gyro_inject_az`: that key is `R̂·b` and nothing else, so
  its ratio between two aim points is |R̂_B|/|R̂_A| = 1.29 BY ARITHMETIC. **The first draft of the
  verifier asserted exactly that tautology** (convention 11's trap) and would have "passed" while
  proving nothing.
* REPLAY posdiff **0.0** — class 4a, and a deterministic gyro error adds no draw.

## The client, and the defect the shot harness caught (convention 14's 4th proof earning its keep)

The HUD's three-state headline first compared the EFFECTIVE belief `R̂(1+s)` against
`radome_aim_gyro` = `R_worst/(1+s)` — **two quantities on opposite sides of the (1+s) factor**. The
line below tells the student where to put the SLIDER (`R̂ ≤ R_worst/(1+s)`); the VERDICT is about what
the LOOP ends up seeing (`R̂(1+s) ≤ R_worst`). Mixing them labelled a correctly-aimed missile *"the
gyro eats the margin"*. Nothing headless can catch this — `_draw` never runs there — so the shot was
the only evidence. ⚠ A SECOND shot defect: `_range()` can read a STALE frame if the step chunk has
not drained, so the harness sailed past CPA and captured a frame with the target BEHIND the missile
(range opening, look angle 158°); fixed with a hard tick cap beside the range gate.

The shipped pair, at the same range and with the SAME gyro in both:

* **RING** (1396 m): *"GYRO — RINGING: loop sees R̂(1+s)"*, body yaw rate −0.591 rad/s, `R̂ −0.270
  ×(1−0.05) → LOOP SEES −0.257`, `gyro AIM AT −0.347 or below`, ENGAGEMENT RESIDUAL **−0.062** (eff).
* **QUIET** (1441 m): *"AIMED PAST THE GYRO — the SAFE side"*, body yaw rate +0.020 rad/s, `R̂ −0.360
  ×(1−0.05) → LOOP SEES −0.342`, same aim line, ENGAGEMENT RESIDUAL **+0.027** (eff).

## Deferred (NAMED)

* **A SINGLE IMU** — the mechanism is DAMPING, not residual, and it was MEASURED (gate-0 P7): feeding
  the same corrupted rate to the α/β autopilot moves the onset from `s ≤ −0.22` to `s ≤ −0.18` and
  DESTROYS the exact `R̂(1+s)` equivalence, because `k_q` supplies ~98% of the plant damping. Two
  mechanisms at once, which convention 9 forbids inside one lesson.
* **GYRO NOISE** — on DRAW-TOPOLOGY grounds (convention 3): an unconditional third `randn` desyncs
  every 25–30 replay; a host-marker gate is the slice-13 `:scan` 4b shape. ⚠ And slice 25 measured a
  ~1000:1 low-pass on the roll loop, so probe before ever shipping it — it may be DEAD.
* **PER-AXIS SCALE FACTORS AND GYRO MISALIGNMENT** — this slice's scale factor is COMMON-MODE, which
  is exactly why it collapses onto one number; a misalignment term would not.
* **`gyro_bias_y` AS A KNOB** — it ships as a supported comp key and is tested, but on a crossing wire
  it drives the ELEVATION channel (~10× smaller). It becomes interesting on a geometry whose lead is
  in elevation, which this arc has never flown.
* Everything 26–30 named and did not spend: ESTIMATING `R̂` IN FLIGHT (still blocked by slice 26's
  P7A, sharpened by 29); a 2-D slope `R(look_az, look_el)`; an ASYMMETRIC error curve; **seeker FOV /
  gimbal limit** (sharper every slice — this one's bias domain is bounded by the look angle reaching
  30°, exactly where a gimbal would already have stopped); the out-of-plane MANEUVERING target.
