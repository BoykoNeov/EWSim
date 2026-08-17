# Slice 38 — **AN IMPERFECT HEAD GYRO: SLICE 37's MARGIN IS A GYRO SPEC** (§11 Tier-A)

**Status: SHIPPED AND COMPLETE (2026-08-17) — all four gates, suite 7496 → 7564, four proofs green.
The claim is real, both reparameterization gates are answered by measurement, and TWO PREDICTIONS
WERE REFUTED at gate 0 — one of them mine, one the advisor's, and both are load-bearing.** Raw
numbers and every table in `M:\claud_projects\temp\slice38g\`
(`lib38g.jl`, `p0_bench.jl`, `p1_blocking.jl`, `p2_collapse.jl`, `p3_ladders.jl`, `p4_grid.jl`,
`p5_dead.jl`, `g0_results.md`).

⚠ **P1–P5 NEEDED A CORE PATCH** (a `:probe_hg_*` block after the inertial-state mint in `missile.jl`'s
space-stabilized branch — slice 35/37's gate-0 precedent). It was applied for the runs and **REVERTED**:
`git diff --stat core/src/missile.jl` is empty and the suite is green at **7496** as of this file.

The candidate: the deferral slice 37 named FIRST —

> *"**AN IMPERFECT HEAD GYRO** (the stabilized arm has EXACTLY unity body-motion-rejection gain at
> every frequency — an IDEAL head-mounted rate gyro, and slice 31's scale factor and bias are the
> precedent for what an imperfect one adds; ⚠ scope it against slice 31's own trap first, since a
> gain error on the rejection path may collapse onto slice 26's boundary the way FRAMING A did)."*
> — `CLAUDE.md`, slice 37's own deferrals

---

## The one-paragraph statement of what was measured

Slice 37 showed that stabilizing the seeker head in space *removes* stability margin, because the
position servo's lag had been quietly low-passing the missile's own body motion out of the radome's
index. That whole result rests on a perfect gyro: the shipped stabilized head rejects body motion at
exactly unity gain at every frequency, because the model simply *stores the inertial angles*. Give
the gyro a scale-factor error and the rejection leaks — a fraction of the body motion comes back into
the index — and **slice 37's stability boundary walks continuously with gyro quality**, from its
shipped space bracket at a perfect gyro all the way to its shipped body bracket at a dead one. A 5 %
scale factor, an ordinary cheap-MEMS part, gives back a quarter of the margin the button costs.

> **THE RESULT, IN ONE SENTENCE.** The two architectures slice 37 shipped as a BUTTON are the two
> ends of ONE HARDWARE SPEC — and **a worse gyro is a more stable missile.**

---

## §0.1 THE MODEL, AND THE ARCHITECTURE FORK THAT WAS CHOSEN RATHER THAN FALLEN INTO

**FEED-FORWARD stabilization.** The head holds its pointing by feeding forward the negated gyro
reading `ω̃ = (1+s)·ω + b` (slice 31's shipped `gyro_reading`, `frames.jl:661`), so its inertial rate is

```
        ω − ω̃  =  −s·ω − b            ⇒  the pointing DRIFTS at −s·ω − b.
```

⚠ **THE ALTERNATIVE IS NAMED, NOT OVERLOOKED (advisor):** a NULLING loop on a head-mounted gyro drives
`ω̃_head → 0` and has steady state `−b/(1+s)` — **scale factor nearly INERT, bias-only**. Feed-forward
is chosen deliberately because it is the architecture that makes gyro error a GAIN ON THE REJECTION
PATH, which is the quantity slice 37 measured its margin out of. The nulling loop is a §1 approximation
of this slice and a candidate successor, not an oversight.

⚠ **THE SIGN IS PINNED ON A BENCH (the #1 sign trap's 11th occurrence in this arc)** — an inverted sign
still produces a plausible sweep. P0c: with the servo absent and the body turning at a known rate, a
gyro that reads NOTHING (`s = −1`) freezes the head's **BODY** angle at **0.0000000°** while its
inertial angle sweeps the full body rotation. ⚠ And the probe's FIRST DRAFT printed the oracle
`−s·ω_y·t` beside a bench whose true body rate is negative, so it read as a sign error in the PHYSICS
when the defect was in the ORACLE. The derivation now sits beside the column.

---

## §0.2 ⚠⚠ TWO REFUTATIONS BEFORE ANY WIRE EXISTED, BOTH LOAD-BEARING

**1. THE INDEX GAIN IS NOT `|1+s|`, AND `s = −1` IS NOT THE FROZEN-INDEX DEGENERATE.** Both the
opening plan and the advisor's first reading expected a flat, phase-free rejection gain of `|1+s|`,
hence gain 0 at a dead gyro — *"the knob spans BEYOND the rung pair"*. **P0b measures the opposite:**

| `s` | index gain @1.7 Hz | phase @1.7 Hz |
|---|---|---|
| +0.30 | 1.07168 | **+6.596°** (LEAD) |
| 0.00 (slice 37's space rung) | 1.00000 | 0.000° |
| −0.20 | 0.96054 | −4.899° |
| −1.00 (dead) | 0.88608 | −27.578° |
| **slice 37's BODY rung** | **0.88405** | **−27.561°** |

The error was conflating *the drift cancelling body motion* with *the servo being off*: a head carried
along by the body is **still slewed by its servo toward the target with lag τ**, which is exactly the
body-referenced rung. ⇒ the knob **INTERPOLATES BETWEEN SLICE 37's TWO ARCHITECTURES**, and extends
past the space rung only on the `s > 0` side (an OVER-reading gyro, which over-rejects and leads).

**2. THE BIAS WAS TO BE THE HEADLINE AND IT IS THE WEAK HALF.** The advisor's call — bias headline,
scale factor a tooth — rested on the scale factor being a slice-31 repeat (*"at realistic grades
neither term matters"*). Measured, it is the reverse: **−5 % of scale factor is a real part and moves
the boundary two cells**, while the bias needs ~10³× a bad real gyro to move anything.

---

## §0.3 ⭐⭐ THE HEADLINE — THE ONSET WALKS WITH THE GYRO (P4)

Slice 37 found its onset TWICE, once per architecture. The SAME boundary walks CONTINUOUSLY with the
gyro, on slice 37's own 0.005 grid, under its own **threshold-free largest-single-step rule**:

| `s` | onset bracket in R̂ | cells of slice 37's margin given back |
|---|---|---|
| 0.00 (perfect — **slice 37's space bracket EXACTLY**) | (−0.210, −0.205] | 0 / 8 |
| −0.01 (1 %) | (−0.210, −0.205] — **unchanged, sub-grid** | 0 / 8 |
| −0.02 (2 %) | (−0.205, −0.200] | 1 / 8 |
| −0.05 (5 %, a real cheap-MEMS part) | (−0.200, −0.195] | **2 / 8** |
| −0.10 | (−0.195, −0.190] | 3 / 8 |
| −0.20 | (−0.185, −0.180] | **5 / 8** |
| −0.30 | (−0.180, −0.175] | 6 / 8 |
| −0.40 | (−0.175, −0.170] | 7 / 8 |
| −0.80 / −1.00 (dead) | (−0.170, −0.165] | 8 / 8 |
| **slice 37's BODY rung** | **(−0.170, −0.165]** | — |

⭐ **THE `s = 0` ROW REPRODUCES SLICE 37's SHIPPED SPACE BRACKET AND THE BODY ROW ITS SHIPPED BODY
BRACKET, BOTH EXACTLY** — which is what makes this a measurement of the gyro rather than a re-grid of
slice 37.

⚠⚠ **THE FIRST RUN OF THIS TABLE WAS TRUNCATED AND ITS STRONGEST SENTENCE WAS AN ARTIFACT** (advisor,
blocking). The grid ENDED at −0.180, which is exactly where the `s = −0.20` bracket landed, and
*"−20 % gives back essentially all of the margin"* rested on that edge. Re-flown to −0.150, past slice
37's own body bracket, every onset is INTERIOR and the true figure is **five eighths, not all**.
A bracket pinned against the edge of its own grid is not measured, it is truncated.

⭐ **THE DOMAIN FLOOR IS A MEASUREMENT, NOT A CHOICE:** the walk is INVISIBLE at 1 % and RESOLVES at
2 %, so the engineering claim rests on a mid-grade MEMS part. (At 1 % the bracket is unchanged while
the cells inside it move — 0.0454 → 0.0242 at R̂ = −0.210 — which is the honest reading of *"sub-grid"*
rather than *"no effect"*.)

⚠ **THE STEP-RATIO COLUMN IS NOT THE QUANTITY.** It is non-monotone across these rows (9.18 → 11.13 →
5.58 → 23.16 → 16.19 → 19.18 → 21.02 → 28.96) and NOTHING is built on it. The BRACKET is the quantity —
slice 37's own rule, for slice 37's own reason.

---

## §0.4 ⭐ THE SECOND CURRENCY — THE BIAS IS A TWO-SIDED KNOB (P1b, P3c)

At the marginal design R̂ = −0.205 a bias spans **43.2×** in `rms r` (0.0185 → 0.7984 over
b ∈ [−0.4, +0.4] rad/s), MONOTONE — and the head's tracking error moves **the other way the whole
time** (2.70° → 0.96°).

> ⇒ **THE DRIFT DIRECTION THAT HELPS THE HEAD KEEP UP IS THE ONE THAT DE-STABILIZES THE LOOP.**
> Slice 35's one-knob-two-bounds shape, in a new pair of currencies.

⚠ **AND ITS DOMAIN IS CHOSEN FOR VISIBILITY, NOT REALISM — STATED, NOT BURIED** (slice 31's posture
verbatim). On the most favourable design, a bias of 103 °/hr (a bad MEMS part) moves `rms r` by
**0.00064**; the visible domain starts around 10⁴ °/hr, ~10³× a bad real gyro. ⚠ The SCALE FACTOR is
**not** in this position and the two must never be quoted in one breath.

---

## §0.5 ⭐⭐ SLICE 30's RULE PAYS A FIFTH TIME, IN ITS STRONGEST FORM YET (P3c)

At the aim point `radome_slope_worst` = R₀ + 2A = **−0.33**, the bias moves the head's tracking error
by **3.9×** (2.06° → 0.53°) and **the ring does not move at all**: `rms r` spans **1.0×**
(0.0598–0.0602) across the entire bias domain.

33 = FOV · 34 = detector window · 35 = servo bandwidth · 37 = the reference frame · **38 = immunity to
your own head gyro** — and this is the first time the rule buys off a **SENSOR ERROR** rather than a
design choice. The proof is again a control that visibly stops working.

---

## §0.6 THE THREE GATES THAT HAD TO BE PASSED

* **BLOCKING — the bias vs the LEAD (does it collapse onto slice 32's axis?): PASSED.** Both a bias
  and a faster crossing move the index along the slope curve. Across the whole bias sweep at fixed
  crossing speed, `lead_angle_deg` is **constant at 14.59–14.68°** while `head_off_deg` moves 2.84° →
  1.31° and the verdict moves with it; the contrast column (moving the lead itself, vy 100 → 320)
  moves the lead **7.41° → 21.54°**. Two mechanisms, measured side by side.
* **THE `(s, R)` COLLAPSE — PASSED DECISIVELY.** `s = −0.2` reads 0.29353; the same missile with the
  glass scaled ×0.8 reads 0.01453 (**20.2×** apart) and with glass AND belief scaled ×0.8 reads
  0.98063 (**3.3×** apart the other way). Neither reading of *"an equivalent radome"* reproduces a
  gyro error — and the bench says why: `s` adds **PHASE** (−4.9° at −0.2, 1.7 Hz), and scaling a slope
  cannot produce phase.
* **THE RUNG BOUND — HELD, BUT ONLY IN THE NARROW FORM.** ⚠⚠ **The walk REACHES the body rung's
  bracket at `s ≤ −0.80`**, and the whole `s = −1` row sits within 1–3 % of the body row cell for
  cell. ⇒ **NO CLAIM MAY BE MADE IN THE RING METRIC.** What survives: the two are different missiles
  by **1.556 m** of trajectory on the ringing arm (0.089 m on a quiet one — the right direction for a
  body-motion mechanism, against **40.29 m** for the honest architecture pair); they are different
  CODE PATHS; and a gyro that reads ZERO *physically is* an unstabilized head, which is a correct
  degenerate rather than a false fidelity. **This sentence belongs in the scenario header too** — it
  is what stops a reader concluding slice 37's rung was false fidelity all along.

---

## §0.7 WHAT MUST BE STATED RATHER THAN BURIED

* **`out_band` is 0.00 % on every arm quoted anywhere in this gate** — the two-run discipline's
  precondition, without which no `rms r` here is a stability read at all.
* **Byte-identity is MEASURED, not argued:** authored `s = b = 0` against the keys being ABSENT gives
  `max|Δpos|` = **0.000000e+00** (slice 26's precedent). The shipped else-arm must be slice 37
  **verbatim**, never `+ 0.0` trusting the zero.
* ⚠ **A PROBE DEFECT WORTH THE RECORD:** P3a applied the largest-single-step rule to a ladder ordered
  DESCENDING and reported 1.03× where its own table showed a 10.3× collapse. **The rule is
  DIRECTION-SENSITIVE** — gate 1 must order the ladder ascending or take `max(r, 1/r)`.

---

# GATES 1 AND 2 — AS BUILT (2026-08-17)

**Gate 1 COMPLETE (suite 7496 → 7516).** `frames.jl` gains `head_drift_inertial`, a COMPOSITION of
slice 31's `gyro_reading` that returns its input BIT-FOR-BIT at a zero residual — so an authored
`s = 0` is byte-identical to the keys being absent BY CONSTRUCTION. Four teeth: the sign (the body
angle frozen to 8.5e−14 over 5000 ticks at a dead gyro, paired with the perfect-gyro `===`); the
drift as a Rodrigues rotation against an INDEPENDENT recompute (3.554e−16 over 108 cells); linearity
in `s` (1.7e−12) paired with the bias as a different currency; and the degenerates.

⚠⚠ **TWO WRONG ORACLES, BOTH OF WHICH LOOKED LIKE TOLERANCE PROBLEMS**, and both are recorded in the
test because either would have shipped as a loose `atol`: `acos` of the dot product is
precision-limited to ~1.2e−04 rad on a 2e−4 rotation (and hid the linearity result at ~1e−8, which
the chord formula reads as 1.7e−12); and predicting the swept angle as `|Ω|·dt` is **wrong by
construction**, since a vector rotated about an axis moves by `|Ω|·dt·sin(ψ)`. That read 24 % on the
widest cell — and swapping the first oracle for the chord formula left the number BIT-FOR-BIT
UNCHANGED, which is what exposed it as a formula error rather than a precision one.

**Gate 2 COMPLETE (suite 7516 → 7553).** The seam is one call in `missile.jl`'s `elseif _stab` arm
plus three loader keys and three telemetry keys.

* ⭐ **THE SHIPPED SEAM REPRODUCES GATE 0's CELLS with the probe patch reverted** — 0.63754 / 0.01963
  / 0.89855 / 0.01981 against gate 0's 0.6375 / 0.0196 / 0.8985 / 0.0198. ⚠ A reproduction check is
  blind to whether BOTH are right (slice 37 §II.4's finding); what it establishes is that the seam
  IS the probe.
* ⭐ **SLICE 37 IS BYTE-IDENTICAL ON THE WIRE**, re-run after the seam edit: 0.01195 / 1.00094 =
  83.8×, both brackets unchanged (4.32× and 9.09×), the aim point still 1.022×.
* **THE ORDERING IS DRIFT-THEN-CLAMP** and it is stated in the seam: a drift that pushes the head
  into its mechanical stop is clamped in the SAME tick, so the head cannot drift THROUGH its own
  gimbal limit. Pinned on a wire where the stop actually binds (5572 ticks at a 12° stop; `over`
  1.78e−15, floating point only). ⚠ **A GUESS BESIDE IT WAS WRITTEN AS AN ASSERT AND REFUTED BY IT:**
  the draft claimed a perfect-gyro arm reaches that stop LESS often, *"so the binding is the drift's
  doing"*. It is not — 5582 ticks perfect against 5572 drifted, very slightly MORE. ⇒ the testset
  proves the ORDERING INVARIANT and nothing about causation, and it says so.
* **INERT ON THE BODY RUNG BY PLACEMENT, NOT BY A GUARD** (advisor): `max|Δpos| == 0.0` with the keys
  authored at values that visibly ring the space rung — the other-rung twin of the key-absent tooth,
  and what makes the keys introduce-safe on slices 34–36's wires.
* **THE HANDOVER TICK IS NOT DRIFTED** — tick 1 takes the `!haskey(:head_az)` branch, so the head is
  BORN in the same place whatever its gyro is and the arms part only from tick 2.
* **TELEMETRY NAMED BY WHICH SENSOR** (advisor): `head_gyro_scale_err` / `head_gyro_bias_z` /
  `head_gyro_leak`, shipped only when a key is authored, ALONGSIDE slice 27/28's `radome_residual*`
  and never folded into them. ⚠ `head_gyro_leak` is `|s|` — the SENSOR's own property — and is
  explicitly **not** the index gain (which runs 1.000 → 0.886 because the servo also acts).
* **THE LOADER refuses the keys without `gimbal_tau_s`** (dead without a head) but **accepts them
  beside EITHER rung** — the distinction from slice 36's by-name refusal is that a handover error is
  consumed once at tick 1 while these are consumed every tick, and `:seeker_head` is live-settable.

---

# GATE 3 — AS BUILT (2026-08-17): the wire, the marker whose only job is the HUD, and a headline that
# ran off the edge

**Status: gate 3 COMPLETE and green. Suite 7553 → 7564.** Four proofs green: `slice38_verify.gd`
(14 arms), `slice38_ui_test.gd` (10 teeth), the `Sandbox.tscn` headless smoke-load with BOTH halves
captured, and TWO windowed shots.

## The wire — `scenarios/slice38_head_gyro.yaml`

`slice37_frame.yaml` KEY FOR KEY with ONE number changed and ONE key added. ⚠ **IT OPENS ON THE
STABILIZED RUNG, WHICH IS THE OPPOSITE OF SLICE 37's CHOICE AND FOR THE MIRROR REASON:** slice 37
opened on the GOOD design so the first press would break it; here the slider's job is to make a
RINGING missile quiet by making its gyro WORSE, so the wire must open where the ring is. The one
number is `radome_slope_est` = **−0.20**, chosen BY MEASUREMENT as the design at which the slider
decides the verdict (at a perfect gyro it rings 0.6375; at −5 % it is quiet 0.0196). Slice 37's own
−0.18 would have put both ends of the slider on the ringing side.

**The verifier's numbers** (frame-sampled, 14 arms, `out == 0.00 %` on every one):

* **THE SHOWCASE** — `rms r` **0.63736** at a perfect gyro against **0.01967** at −5 %, **32.4×**,
  both hitting (1.236 / 2.418 m), with the believed slope bit-identical between them.
* **THE LADDER IS MONOTONE ACROSS THE WHOLE DOMAIN** — 0.98525 → 0.01440 over 9 cells, asserted CELL
  BY CELL rather than end to end (an end-to-end check passes over any interior reversal). ⚠ A first
  for this family after the wrinkles at 19/20/22/28/35/36.
* **THE TRANSITION IS A SINGLE STEP** across s ∈ (−0.030, −0.050] at **18.8×** ⇒ the gyro spec has a
  KNEE rather than a proportional cost.
* **THE CEILING RINGS HARDER THAN PERFECT** (0.98525 against 0.63736) — the half of this axis lying
  BEYOND slice 37's stabilized rung rather than between its two.
* ⭐⭐ **THE SLIDER IS BIT-IDENTICALLY INERT ON THE OTHER SIDE OF THE BUTTON** — `max|Δpos| =
  0.000000000 m` across its whole range on the body-referenced rung, with `rms r` equal to nine
  digits (0.01340) and the same miss to three (3.971 m).
* **REPLAY** bit-identical at BOTH ends of the slider (class 4a, the 14th consecutive RNG-live slice).

## ⭐⭐ The client: a marker whose only job is the HUD (the advisor predicted it before any code)

`gimbal_gyro_view`, raised on the COMP KEY — the OPPOSITE choice from slice 37's fidelity gate, and
for the same reason it made its own: what distinguishes THIS wire is the imperfect sensor, and the
RUNG is shared. It is checked FIRST at **all three** client sites (button, headline, HUD body).

⚠ **THE BUTTON NEEDED NO DECISION AT ALL, AND THAT IS NEW.** A slice-38 wire raises FOUR earlier
route markers, and `gimbal_frame_view` already keeps the button — correctly, because `:seeker_head`'s
two rungs are the two ENDS of this slice's slider axis. What was wrong without the new marker is the
HUD: slice 37's block would take the wire, and EVERY KEY IT READS IS LIVE HERE, so it would print a
fluent and entirely TRUE frame-comparison verdict — plus a cure line naming a slider this wire does
not have — above a lesson about the SENSOR. The stale-readout class's WORST form (slice 34's), where
nothing is stale, and its ~10th occurrence. **The mirror proves the branch is a SWITCH, not an `or`:**
strip the marker and the BUTTON is unchanged while only the HUD falls through.

⭐⭐ **AND THE STATE ONLY THIS BRANCH CAN NAME IS A DEAD KNOB.** On the body-referenced rung the slider
is inert, so the mechanism line reads *"BODY-REFERENCED: no gyro to corrupt — slider INERT"* rather
than leaving a student to drag a live control and watch nothing happen. **A live control that does
nothing is the stale-readout class in a NEW form — not a stale number but a dead one.**

## ⚠⚠ THE SHOT CAUGHT A DEFECT THE UI TEST HAD JUST PASSED: TWO WIDTH BUDGETS, NOT ONE

The first pair of captures ran BOTH new headlines off the right edge — *"PERFECT-ish GYRO — RINGING:
the index sees the body"* (50 chars) and *"GYRO LEAK — the ring is bought by a WORSE sensor"* (47) —
**while the width tooth passed**, because it pinned the ~55-character budget the BODY lines are drawn
against at 15 px. THE HEADLINE IS DRAWN LARGER AND FROM A DIFFERENT ORIGIN, so its budget is ~30:
slice 37's longest is "SPACE-STABILIZED — loop STABLE" at exactly 30, and every label in this family
had quietly obeyed that without anyone writing it down. ⇒ the right-edge overrun's **5th occurrence**
after 26/28/36/37 and **THE FIRST IN A HEADLINE**; the UI test now pins the two budgets SEPARATELY.
Re-taken, the shots read **`PERFECT GYRO — RINGING`** (ring r −0.817, peak 1.12, `s +0.000`, leak
0 %) against **`WORSE GYRO — loop QUIET`** (−0.014, peak 0.03, `s −0.050`, leak 5 %).

## ⚠ Four carrier/mirror asserts fired, and they were right to

Slices 35 and 37 each enumerate which shipped wires carry their keys, and each has a mirror asserting
no OTHER wire raises their marker. A slice-38 wire legitimately carries both (`gimbal_rate_dps` and
`seeker_head`), so all four fired — the **third** time slice 35's list has earned its keep. They are
widened with the reason, not deleted: the claim being pinned is still that slices 1–34 stay
byte-identical BY GATING.

⚠ **SLICE 37 IS BYTE-IDENTICAL ON THE WIRE**, re-verified after the seam edit: `S37V OK`, 0.01195 /
1.00094 = 83.8×, both onset brackets and the 1.022× dead button unchanged. All four prior UI tests
(34/35/36/37) re-run and green.

---

# THE PLAN — GATE 3 (as written before the work; kept for the record)

## Gate 1 — the kernel and its teeth (DONE, above)

* **`frames.jl`:** the drift is `gyro_reading` (slice 31's, unchanged) plus one small kernel that
  advances an inertial pointing by a body-rate residual — `head_drift_inertial(az, el, ω_b, s, b, att,
  dt)`. ⚠ It must be a KERNEL and not an inline block, for the reason `head_slew_full` already
  documents: a predicate or a rotation re-derived beside the branch it reports can disagree with it.
* ⚠ **NO SECOND SERVO.** The slew stays `head_slew_inertial` bit-for-bit — the two rungs must keep
  differing only in the frame, or the walk in §0.3 stops being a measurement of the gyro.
* **Teeth:** the sign (P0c's frozen-body-angle row, `0.0000000°` at `s = −1`); the index gain and its
  PHASE against the `1/√(1+(2πfτ)²)` column (P0a/P0b — the same bench in one file); `s = 0` and `b = 0`
  bit-identical to the keys being absent; the drift's own degenerates (convention 6: a zero-norm axis
  is skipped, `dt ≤ 0`, non-finite `s`).

## Gate 2 — the seam

* **Keys `head_gyro_scale_err` / `head_gyro_bias_y` / `head_gyro_bias_z`** — ⚠ **NOT** slice 31's
  `gyro_scale_err` / `gyro_bias_*`, which are the AUTOPILOT's gyro and a different sensor on the same
  missile. The names must not collide (advisor).
* ⚠ **THE FOURTH ATTITUDE-TIMING SITE** (slice 37's gate-2 fix named three). The drift reads
  `:omega_body`, which in phase 3 is PHASE 1's output — the rate belonging to `att(k)`, the same
  attitude the carry uses. **Pin which tick's rate it is**, because gate 1's probe and the seam can
  agree cell-for-cell while both are wrong (slice 37 §II.4's own finding).
* ⚠ **INERT ON THE BODY RUNG BY CONSTRUCTION** — a body-referenced head has no stabilization gyro to
  corrupt. That is itself a tooth, and it must be measured rather than assumed.
* **Gated on the LIVE `:seeker_head`**, never on `haskey`, for the reason slice 21/23/26/27/29/32/37
  each paid for.

## Gate 3 — the wire, the client, the four proofs

* **ONE wire**, `scenarios/slice38_head_gyro.yaml` = `slice37_frame.yaml` KEY FOR KEY with the rung
  authored at `:space_stabilized` (the good design, so the slider is what breaks it) and the gyro key
  added. Convention 9: **ONE slider** — the scale factor — with R̂ AUTHORED at the design whose
  bracket the walk is quoted against. ⚠ The bias ships as the second currency in the tests and the
  HUD, not as a second slider on the same wire.
* ⚠⚠ **THE CLIENT MARKER TRAP, PREDICTABLE NOW (advisor, before any code).** `gimbal_frame_view` is
  gated on the KEY `seeker_head`, not its value — deliberately, so slice 37's button shows on
  `:body_referenced`. A slice-38 wire therefore **inherits slice 37's button AND its HUD**, which
  would print a frame-comparison verdict on a wire whose subject is the GYRO. This family's ~10th
  occurrence of that class ⇒ a new **`gimbal_gyro_view`** marker, **checked FIRST**.
* ⚠ **NO NEW `randn`.** Gyro NOISE stays deferred on draw-topology grounds (already named in
  `CLAUDE.md`): an unconditional third draw desyncs every 25–37 replay. Class **4a**, the 14th
  consecutive RNG-live slice.
* The four proofs as always (verifier / UI test / smoke-load with BOTH halves captured / two windowed
  shots), and **`out == 0` asserted on every arm the verifier quotes**.

---

## Named deferrals

* **A NULLING-LOOP HEAD SERVO** (§0.1) — the other classical architecture, where the scale factor goes
  nearly inert and the bias carries everything. The natural A/B against this slice.
* **GYRO NOISE** — draw-topology, as above; and slice 25's ~1000:1 roll-loop low-pass says probe first,
  it may be DEAD.
* **PER-AXIS SCALE FACTORS AND HEAD-GYRO MISALIGNMENT** — this one is COMMON-MODE, which is exactly
  why it collapses onto one number (slice 31's own shape).
* **A SECOND-ORDER HEAD SERVO (ω_a/ζ_a)** and **THE τ AXIS AS ITS OWN SLICE** — slice 37's other two
  deferrals, untouched here and now sharper: this slice shows the REJECTION path has its own spec, so
  τ and ω_a would both change how much that spec is worth.
