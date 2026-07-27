# Slice 26 — THE RADOME / BODY-RATE PARASITIC LOOP: the seeker that sees the missile's own nose (§11 Tier-A)

The FOURTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop) and **the arc's named end point**. Slice 25
wrote it down as a hard prerequisite in its own deferral list: *"an error slope perturbs a TWO-ANGLE
measurement as a function of look angle; there was nothing for it to perturb before this slice."*

It is also the home of a lesson **slice 15 named, slice 19 deferred and slice 20 hunted and KILLED**:
the GUIDANCE LIMIT CYCLE. Slice 20's gate 0 proved no such cycle exists on the *actuator* feedback
path (`δ_max` structurally shadows `δ̇_max`, FINDING 7). It arrives here through a **different feedback
path entirely** — the SENSOR's — and gate 0 produced it in four probes.

**Status: GATE 0 COMPLETE (6 probes run 2026-07-27, `M:\claud_projects\temp\slice26_gate0\`).**

---

## The one-paragraph statement of the lesson

The seeker does not look at the target directly — it looks through a **radome**, and a radome
REFRACTS. The bend depends on where the seeker is looking through it: `ε ≈ R · (look angle off the
body centerline)`, with `R` the *radome error slope*. So when the missile's **own body** rotates, the
look angle changes, the bend changes, and **the line of sight the seeker reports MOVES — with the
target perfectly still.** That is a feedback path from the airframe's attitude back into the guidance
loop: `q → look angle → ε → apparent λ̇ → PN → a_cmd → α → q`. Below a critical loop gain it is a
harmless perturbation; **above it the loop is UNSTABLE and the missile shakes itself into a sustained
limit cycle — with a NOISELESS seeker and a stationary target.**

> **THE LESSON, IN ONE SENTENCE.** A piece of glass in front of the seeker closes a feedback loop
> from the missile's own body rate back into the LOS rate it measures, and past a critical loop gain
> `N·|R|` the missile shakes itself: at R = −0.09 the body is quiet (rms q = 0.013 rad/s), at
> R = −0.10 it oscillates at ±1.4 rad/s **68× harder**, self-excited, with no noise in the loop.

⚠ **THIS IS THE PROJECT'S FIRST TRUE POSITIVE-FEEDBACK INSTABILITY, and the phrase slice 20 FORBADE
is EARNED here.** Slice 20 carries a standing warning — *"say DEGENERATIVE SPIRAL, never positive
feedback"* — because its speed bleed is self-limiting (`∝V²α²`, V asymptotes, nothing reaches zero)
and the positive sign sits only on the tracking error past a crossing. Slice 26 is the opposite in
every respect that matters: there is a **loop gain**, a **stability boundary** measured at
`N·|R_crit| ≈ 0.38`, and **self-excitation from zero input** (σ_seek = 0 reproduces the cycle). Do
not import slice 20's language, and do not let a later slice import slice 26's.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⭐⭐ THE HEADLINE IS THE OSCILLATION, AND THE THRESHOLD FACTORIZES AS A LOOP GAIN

`N·|R_crit|` is CONSTANT to ±3% across a 2.67× span of the navigation constant (P4B, P5C):

| N | 3 | 4 | 5 | 6 | 8 |
|---|---|---|---|---|---|
| first ringing R | −0.130 | −0.095 | −0.080 | −0.065 | −0.050 |
| **N·\|R_crit\|** | **0.390** | **0.380** | **0.400** | **0.390** | **0.400** |

and `|R_crit| ∝ ρ` equally cleanly (P4C: 0.060 / 0.095 / 0.145 / 0.190 at ρ = 0.6 / 1.0 / 1.5 / 2.0
⇒ `|R_crit|/ρ` = 0.100 / 0.095 / 0.097 / 0.095). Together: **the boundary is a LOOP GAIN
`N·|R|/ρ ≈ 0.38`** — the slice-21 ρ-factor / slice-22 `α_stall/α_max` shape in a new letter, except
this one is MEASURED rather than algebraic (it is a stability boundary, not an identity — say so).

**The teaching payload of that factorization is the design trade, and it is what makes the slice
worth building:** a radome slope is not good or bad by itself. `|R| = 0.1` is a poor radome and
`|R| ≤ 0.03` a good one — but a missile that wants a HIGHER navigation constant (a snappier
intercept) needs a BETTER radome to keep the same margin, and one flying at LOWER dynamic pressure
needs a better one still. **You cannot buy N without buying glass.**

### 2. ⭐ THE ISOLATION — the ceiling BOUNDS the cycle, it does NOT CAUSE it (the advisor's warning, tested)

The arc has produced six ceiling misses (19–24) and slice 25 spent its whole gate 0 buying
`aero_sat == 0`. **Slice 26 CANNOT and MUST NOT make that claim**: an oscillation drives demand, and
demand hits the ceiling — `aero_sat` runs 61% at the showcase point. The isolation is therefore made
a DIFFERENT way, and it is a stronger one:

**Raise α_max from 0.3 to 0.9 (the ceiling from 330 to 990 m/s², so it cannot bind at the old
amplitude) and the ONSET DOES NOT MOVE — it stays between R = −0.09 and −0.10 (P3B).** Only the
cycle's amplitude grows (max|q| 1.39 → 4.24, max|α| 0.138 → 0.502). ⇒ **the ceiling sets the
AMPLITUDE the limit cycle settles at; the radome sets whether there IS one.** That is the claim gate 3
must assert as a number, and it replaces slice 25's `aero_sat == 0`.

⚠ Do NOT copy slice 25's isolation sentence, and do NOT copy slice 22's `post_stall` discriminator
hunt either — **`aero_sat` here is not a failed discriminator, it is a CONSEQUENCE that is expected
to fire.** The three other caps stay provably clear ON THE SHIPPED ARM, as numbers (P7C, σ = 5e-5,
α_max = 0.3): **`defl_sat` binds 1/9423 ticks at R = 0 and 2/9400 at R = −0.10** (0.01–0.02% — cap #3
clear); the ceiling maxes at **329.87 ≪ `a_max` 3000** (cap #1 never binds); no stall (α peaks 0.139,
and this scenario ships no `aero_curve` at all). ⚠ **Those are the SHIPPED numbers — the α_max = 0.9
ISOLATION probe of §2 leaks `defl_sat` 5–8%, which is fine there and must not be quoted as the
shipping figure.**

### 3. ⭐ IT IS STRUCTURAL, NOT NOISE AMPLIFICATION — σ_seek = 0 REPRODUCES IT (P2A)

The tempting story ("a noisy seeker excites the airframe") is REFUTED, and refuting it is what makes
this a *loop* rather than a *filter* lesson. At **σ_seek = 0** — a perfectly noiseless seeker — R = 0
gives a smooth monotone body-rate drift of ~0.02 rad/s and R = −0.10 gives a sustained ±1.4 rad/s
oscillation, a **106× rms jump**. The loop excites ITSELF. (The slice-25 P2 discipline: *"the collapse
is STRUCTURAL, not noise-driven — which is why σ = 0 reproduces it."*)

⚠ Related, and it drives the scenario tuning: at slice 25's shipped σ = 0.3 mrad the **seeker noise
alone** puts 0.059 rad/s of jitter on `q` — 7× the σ=0 baseline — compressing the signature from 106×
to 13.8×. **Ship σ = 5e-5** (slice 25's own knob MINIMUM, an in-domain value, so this is a re-authoring
and not a new regime): contrast **68.5×**, and say in the header WHY.

⚠ **AND THAT DISQUALIFIES `sigma_seek` AS A KNOB HERE (advisor).** Slice 25 shipped it as its one
slider over `[5e-5, 3e-4]`. On THIS scenario dragging it to the top compresses the headline from 68×
to 14× — **a knob that degrades the lesson it sits next to.** Slice 26 therefore authors σ as a
CONSTANT and ships `radome_slope` as its ONE knob (§7). The measured σ-vs-contrast ladder (P6B: 106.6×
/ 96.2× / 68.5× / 41.0× / 21.3× / 13.8× at σ = 0 / 2e-5 / 5e-5 / 1e-4 / 2e-4 / 3e-4) goes in the
scenario header, so the disqualification reads as a measurement rather than an omission.

### 4. ⭐ THE MECHANISM, FRAME-EXACT — and the naive algebra had the SIGN WRONG (the #1 SIGN TRAP's 8th)

**Only NEGATIVE R destabilizes.** Positive R never rings out to +0.6 (P4E) — instead the seeker
UNDER-reports the LOS rate (`ω_app/ω_true` falls 1.00 → 0.593), the EFFECTIVE navigation ratio sags,
and the miss opens from **sluggishness** (0.23 → 7.66 m). One knob, two entirely different failure
modes on its two signs — the `af_cma` shape (slice 16), where 0 is the benign interior point.

**THE PARASITIC GAIN, MEASURED ON A FROZEN GEOMETRY (P8B — missile, target and LOS all held still,
ONLY the attitude rotating, so `d(look)/dt` is 100% body rate):**

| body rate ω | ε̇_az / R | ε̇_el / R |
|---|---|---|
| (0, −1, 0) — nose UP | −0.0598 | **−0.948693** |
| (0, +1, 0) | +0.0602 | +0.948674 |
| (0, 0, +1) | **−1.000000** | 0.000000 |

`0.948693 = cos(look_az)` EXACTLY, so

    ε̇_el = +R·cos(look_az)·ω_y ,   ε̇_az = −R·ω_z      (+ roll cross-terms for an off-boresight LOS)

⚠ **The textbook form is `−R·θ̇`, and writing it as `−R·q` in THIS project is the WRONG SIGN.** The
convention here is *nose-up = a −y body rotation* (slice 23's fifth sign-trap occurrence), i.e.
`θ̇ = −ω_y`, and `q` is the telemetry name for `ω[2] = ω_y`. The parasitic term is therefore `+R·q`,
and the first draft of this plan carried `−R·q` — caught ONLY because the coefficient was MEASURED
rather than cited (advisor). **Nose-up (`q < 0`) with `R < 0` gives `ε̇_el > 0`: the LOS appears to
rotate UP, which commands MORE nose-up.** That is the loop.

⚠ **AND IT CANNOT BE IDENTIFIED IN CLOSED LOOP — a general result worth keeping (P7A).** Fitting
`ε̇_el ≈ a·ėl_true + b·q` on the live wire returns **R² = 0.999 with `a/R` ranging 1.9…5.5**: the two
regressors are COLLINEAR, because a missile that is tracking pitches at very nearly the rate the LOS
rotates. A perfect fit with unidentifiable coefficients is exactly the self-calibrated round-trip
convention 11 warns about. **The isolation must FREEZE THE GEOMETRY, which makes it a pure-kernel
tooth (gate 1), never an in-loop regression.**

Gate-1 teeth: `R = 0 ⇒ ε ≡ 0` bit-exactly, PAIRED with the P8B frozen-geometry gains above (a
does-perturb case with a MEASURED sign — the slice-24 in-plane-invariant-paired-with-does-roll shape).

### 5. THE THRESHOLD IS THE GUIDANCE LOOP'S, NOT THE AIRFRAME'S — "more damping fixes it" is REFUTED

`Cmq` from −50 to −250 leaves the onset at **exactly −0.095** (P4D); only at −400 does it move one
step to −0.100. The aero damping is nearly irrelevant because the autopilot's `k_q` rate feedback
supplies ~98% of the total damping (slice-20 FINDING 3, measured on this same airframe).

The ring sits **near the airframe's short-period mode but is not it**: measured at σ = 0 ONLY, by two
independent estimators (mean-removed zero-crossing rate and above-half-peak local-maximum count,
P7B), they AGREE at **1.69/1.69, 1.80/1.69, 1.98/2.08 Hz** for R = −0.15/−0.12/−0.20 against the bare
airframe's `ω_sp = 8.773 rad/s = 1.396 Hz`. ⚠ They DISAGREE by 2× at R = −0.095 (2.56 vs 1.28 — the
zero-crossing estimator counting a harmonic near onset), so **quote the band where they agree and
never a single-estimator figure**. ⇒ Describe it as a **guidance-loop instability near the
short-period frequency**, never as "the airframe going unstable" (slice 22 half B's lesson, a
different mechanism entirely).

### 6. ⭐ KNOB, NOT RUNG — by the project's own discriminator, and the consequences are client-side

`atmosphere.jl`'s discriminator: *is the off-state (a) a distinct code path and (b) NOT
knob-reachable?* **`R = 0` is an in-domain slider value** ⇒ KNOB, exactly like `af_cma` (slice 16) and
`af_k_induced` (slice 20), and `af_cma` is the closest analogue since it too spans a stability
boundary through zero. ⇒ `LIVE_FIDELITY_MODES` is UNTOUCHED and this is a **slice-20-shaped slice**:
the lesson is a SLIDER, and crossing the threshold live is the whole demo.

⭐ **SETTLED AT GATE 0 (advisor, and it moves gate-2 scope): THE BUTTON IS DROPPED — the slice-16
handshake-marker precedent, NOT the slice-20 inherited-cycler one.** The discriminator is not
preference, it is: *does the button's other position leave this slice's lesson intact?*

- For slice 20 it did, in the only sense that matters — `:point_mass` makes induced drag **INERT**, so
  the other position displays nothing false.
- For slice 26 it does NOT. The scenario is a two-angle host, so slice 25's guard would route the
  button to the `seeker_axes` cycler; and cycling to `:pitch_plane` leaves the radome **LIVE AND
  REFRACTING** (ε is applied to `λ` as well — it is one physical bend of one measurement) on a missile
  that ALSO misses by 2000 m for a completely unrelated reason. **Two mechanisms compounding in one
  view is precisely what convention 9 exists to prevent**, and it is the "identical signature,
  different mechanism" trap slice 25 spent a whole section on.

⇒ **The slice-20 precedent does not transfer.** Slice 26 ships a handshake marker that makes the
client recognize the view and DROP the shared button (nothing to cycle) — word-for-word slice 16's
Option-P′, and slice 16 is the right analogue anyway: *a live knob spanning a stability boundary,
with no button at all.* Gate 2 emits the marker; gate 3's `_setup_spatial_fid_btn` checks it FIRST
(the one-button rule's 4th occurrence after 13/14/21), the value-guard grows to **EIGHT ways**, and
every prior UI test is re-run.

### 7. THE KNOB DOMAIN — bounded by the metric's PLATEAU, and the MISS is not monotone anywhere

Measured at σ = 5e-5 (P6D), `rms q` relative to the R = 0 baseline:

| R | +0.05 | 0.00 | −0.05 | −0.08 | −0.09 | **−0.095** | **−0.10** | −0.12 | −0.15 | −0.20 | −0.30 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ×base | 1.0 | 1.0 | 1.0 | 1.0 | 1.1 | **50.2** | **68.5** | 65.8 | 64.0 | 64.4 | 63.6 |
| miss (m) | 0.31 | 0.19 | 0.07 | 0.12 | 0.24 | 1.42 | 2.17 | 3.35 | **1.73** | 28.4 | 255.8 |
| aero_sat | 0.2% | 0.0% | 0.0% | 0.1% | 0.6% | 34.1% | 60.9% | 94.6% | 99.5% | 99.6% | 99.2% |

**The metric SATURATES past onset** (the α_max clamp bounds the cycle — §2), so past −0.10 it is a
plateau, not growth. ⇒ domain **`[−0.12, +0.06]`**, which straddles the threshold with the plateau
just entered and no reversal. ⚠ **THE MISS IS NOT THE METRIC AND IS NOT MONOTONE ANYWHERE** (1.73 at
−0.15 is BELOW 3.35 at −0.12) — the 4th occurrence of [[ewsim-df-ellipse-sigma-monotonicity]] in this
project, and here it disqualifies the miss rather than bounding a domain.

**NOT knobs, deliberately:** `n_pn` — it is live-read every tick (`missile.jl:921`, so NOT a dead
knob) and it moves the boundary cleanly, which makes it *tempting*; it is disqualified because it
moves the loop gain the lesson is ABOUT, so a student could cross the threshold with the radome
untouched and conclude the slope did it (the confounded-lever rule, slice 19/20). It ships as a
MEASURED table in this file instead. `rho` — same objection, plus slice 25's finding that its
isolated domain is only [1.0, 1.5]. `af_alpha_max` — it sets the cycle's amplitude, i.e. the thing
§2's isolation must hold fixed. **`sigma_seek` — DISQUALIFIED AND IT WAS SLICE 25's OWN KNOB** (§3):
on this scenario its top compresses the headline 68× → 14×, so it is a knob that degrades the lesson
beside it. Authored constant here, with the measured ladder in the header.

### 8. THE FRAME-SAMPLED METRIC SURVIVES — and that is a REVERSAL of the usual caveat

[[ewsim-missile-verifier-sampling]] warns that a HIT samples coarsely (the CPA moves metres between
frames). **An rms body rate does not have that problem**: a ~2 Hz ring sampled at 62.5 Hz
(`emit_every = 16`) reproduces the per-tick figure to 3 digits — 0.88342 (frame) vs 0.88122 (tick) at
R = −0.10, and 0.01295 vs 0.01286 at R = 0 (P6C). ⇒ **the verifier can assert the headline directly**
rather than pinning conservative one-sided bounds around a sampling artifact, which is exactly why the
oscillation is a better headline than the miss. ⚠ `max|q|` is NOT frame-robust (0.207 vs 0.353 at
R = 0) — **use rms, never the peak**, and this is doubly true under noise (P5D: peaks overlap across
the threshold, rms does not).

---

## Gate 0 — FINDINGS (run 2026-07-27; probes in `M:\claud_projects\temp\slice26_gate0\`)

- **P1A — THE PROBE IS VALIDATED.** `ProbeSeeker` at R = 0 reproduces the SHIPPED `Seeker`
  **bit-identically** (max |Δ| = 0.0 over 8 series, same 9423 ticks, same miss 0.007748174). The
  slice-20 FINDING-1 discipline: validate the scaffolding before believing a sweep row.
- **P1B/P2 — THE EFFECT IS REAL AND SIGNED** (§4), and **STRUCTURAL** (§3, σ = 0 reproduces it).
- **P3 — THE ONSET, AND THE ISOLATION** (§2): the bifurcation sits between −0.09 and −0.10 and is
  INVARIANT to a 3× ceiling raise (α_max 0.3 → 0.9). Shipped-arm cap numbers in P7C.
- **P4A — the knife edge at 0.001 resolution:** rms q = 0.0084 / 0.0089 / 0.0134 / 0.0616 / 0.381 /
  0.632 at R = −0.090 / −0.091 / −0.092 / −0.093 / −0.094 / −0.095. The transition is sharp but not
  a cliff — it develops over ~0.005 in R, then plateaus.
- **P4B / P5C — THE LOOP-GAIN IDENTITY** (§1).
- **P4C — `|R_crit| ∝ ρ`** (§1). **P4D — `Cmq` does not move it** (§5). **P4E — the sign** (§4).
- **P5B — CRASH-SAFETY (convention 5/6):** R = ±1, ±10, ±1e6 all complete with every telemetry scalar
  finite. A live slider cannot kill the tick.
- **P6A — SEED-ROBUST:** 13.8× / 14.6× / 15.0× / 13.9× at seeds 25/26/27/99 (σ = 0.3 mrad). The ring
  is not one lucky realization. ⚠ **P5A was a PROBE BUG** — its seeded helper never set
  `seeker_axes = :az_el`, so all eight cells ran the BLIND arm (miss 2000.044 in every row gave it
  away). The slice-25 P8b lesson recurring: **a sweep whose rows all read the same is a probe bug
  until proven otherwise.**
- **P6B — the σ choice** (§3). **P6C — frame-robustness** (§8). **P6D — the knob domain** (§7).
- **P7A — ⚠ THE IN-LOOP REGRESSION IS NOT IDENTIFIABLE** (§4): R² = 0.999 with `a/R` = 1.9…5.5,
  because `ėl_true` and `q` are collinear in closed loop. The finding is methodological and general:
  **a parasitic gain cannot be measured on a tracking missile — freeze the geometry.**
- **P7B — the ring frequency, σ = 0, two estimators** (§5). **P7C — the SHIPPED arm's cap numbers** (§2).
- **P8 — ⭐ THE FROZEN-GEOMETRY PARASITIC GAIN** (§4): `ε̇_el = +R·cos(look_az)·ω_y`,
  `ε̇_az = −R·ω_z`, exact to 6 digits, **and it caught a SIGN ERROR in this plan's own first draft**
  (`−R·q`, the textbook form transliterated without converting `θ̇ = −ω_y`). The 8th occurrence of the
  #1 sign trap, and the first one caught by an advisor-mandated measurement rather than by a test.

### Numbers the showcase would ship (σ = 5e-5, seed 25, ρ = 1.0, N = 4, α_max = 0.3)

| arm | **rms q (rad/s)** | max\|q\| | miss (m) | aero_sat | defl_sat | *(ω_app/ω_true)* |
|---|---|---|---|---|---|---|
| `radome_slope = 0` (or absent) | **0.01286** | 0.050 | 0.187 | **0.03%** | 1/9423 | *1.018* |
| `radome_slope = −0.10` | **0.88122** | 1.387 | 2.166 | 60.95% | 2/9400 | *7.135* |
| ratio | **68.5×** | 27.7× | — | — | — | *7.0×* |

⚠ **`ω_app/ω_true` IS PARENTHESISED ON PURPOSE — it is a CONSEQUENCE of the ring, not the mechanism,
and it must never be quoted beside `rms q` as an independent line of evidence (advisor).** P4E shows
the STATIC effect of R on the reported LOS rate is small and smooth: 0.593 at R = **+0.6**, 1.084 at
R = −0.05. The 7.135 is the limit cycle ALREADY RUNNING and its own body-rate feedthrough dominating
the reported ω — **the same fact as `rms q`, told twice** (the convention-4 false-claim trap). The
independent mechanism number is `ε` and its frozen-geometry gain (§4). ⚠ Likewise **`max|q|` is
parenthetical**: it is neither frame-robust (§8) nor noise-robust (P5D). **`rms q` is THE metric.**

---

## Gates 1–3 (sketch — firmed by the findings above)

**Gate 1 — the pure lib.** The look-angle + boresight-error kernels. `frames.jl` is the natural home
(it already owns `rotate_inv` / `az_el` / `los_unit_from_angles`, and this is measurement geometry,
not aerodynamics): a `look_angles(att_q, û_los)` returning the body-frame (az, el) pair, and
`radome_error(R, look_az, look_el)` — trivial, and its triviality is the point: **the physics is the
FEEDBACK PATH, not the formula.** Teeth: `R = 0 ⇒ ε ≡ 0` bit-exactly PAIRED with **the P8B
frozen-geometry gains as a NUMBER** (`ε̇_el/R = −cos(look_az)` under `ω = (0,−1,0)`; `ε̇_az/R = −1`
under `ω = (0,0,1)`) — the does-perturb half, with the sign MEASURED not cited; the identity-attitude
degenerate (`att = [1,0,0,0]` ⇒ look ≡ the inertial angles); a round-trip against `rotate`/`az_el`;
the ±π az seam.

**Gate 2 — the wired subsystem.** The perturbation goes on the MEASURED angles inside
`_observe_point3d!`, **after** the two `randn` draws and **before** the trackers — the α-β filter
differentiates the perturbed angle and PRODUCES the `−R·q` term itself; **do NOT hand-inject a rate
term** (advisor). A SECOND gated closure keyed on `haskey(c, :radome_slope)` with the else-arm slice-25
**VERBATIM** — never `+ ε` trusting `R = 0 → 0.0` (the `-0.0` trap, slice 20's structural byte-identity
shape). **The draw count stays EXACTLY 2/tick** — slice 25's button legality rests on it, so pin it as
a tooth. Gate additionally on the LIVE `:airframe === :six_dof` rung, NOT on `haskey(:att_q)` (the
slice-21 `_atm_on` / slice-23 stale-readout latent-bug class, whose **third** occurrence this would
be — an `:att_q` that is never deleted would leave a cross-toggled wire refracting through a frozen
attitude). Loader: presence-gated `seeker.radome_slope` → `comp[:radome_slope]`, validated finite.
`LIVE_FIDELITY_MODES` UNTOUCHED (§6). New telemetry, KEY-gated so slices 11/13/25 are byte-identical:
`radome_eps` (the injected boresight error, rad — **the mechanism**), `look_angle` (deg off
boresight), and `omega_ratio` (‖ω_reported‖/‖ω_truth‖) shipped as a **DIAGNOSTIC, labelled as a
consequence** (§ showcase table). Core-side per convention 13 — the client computes none of it. Plus
**the handshake marker that drops the shared button** (§6, settled at gate 0 — this is the scope the
deferral would have cost). **Class 4a** (draw-invariant, RNG-live — the seed is load-bearing,
conventions 3/11 apply, the second consecutive 4a after slice 25).

**Gate 3 — the four proofs.** `scenarios/slice26_radome.yaml` (slice 25's geometry and plant, σ
re-authored to 5e-5 with the reason in the header, `radome_slope` defaulting to the RINGING value so
the showcase opens on the drama — the slice-25 "opens on the miss" shape). The verifier asserts **the
oscillation as a number** (rms q over frames, the R=0 vs R=−0.10 ratio) — a NEW KIND of gate-3 proof
for the suite, which slice 20's plan sketched and never got to ship — **plus the α_max-invariance of
the onset** (§2, the isolation IS the claim) and a held-seed bit-identical replay. The UI test asserts
the button is **DROPPED** on a radome wire while slices 23/24/25 keep THEIRS (the EIGHT-way
value-guard, §6), plus the smoke-load and a windowed shot (the tell is the NOSE, not the trail:
max|α| 0.139 rad = 8.0° oscillating near 2 Hz while the path barely weaves — a ±330 m/s² lateral at
2 Hz is only ~2 m of displacement). ⚠ **Re-run the 23, 24 AND 25 verifiers** — the seeker code moves.

---

## Named deferrals (write them down; do not let them leak into this slice)

- **A LOOK-ANGLE-DEPENDENT slope `R(look)`** — real radomes have a wiggly slope curve and the design
  case is the WORST local slope, not a constant. This slice ships the constant-slope linear model as
  a §1 named approximation.
- **The de-tuning face of positive R** — measured (§4, `ω_app/ω_true → 0.593`, miss → 7.66 m at
  R = +0.6) and REAL, but it is a different lesson (a reduced effective N, the slice-9 "commanded vs
  achieved" family) and convention 9 keeps it out of this scenario.
- **A radome-slope COMPENSATION / stability-margin autopilot** — the engineering answer (a rate-gyro
  feed-forward that cancels the parasitic term). It is the natural slice 27 and it needs this one.
- **Seeker FOV / gimbal limit** (slice 25's deferral, unchanged) — a look-angle CONSTRAINT is now
  doubly expressible: this slice makes the look angle a first-class quantity.
- **The 3-D `:raw` arm, monopulse / az×el CFAR, a measured `Vc`** — slice 25's list, unchanged.
- **The out-of-plane MANEUVERING target** (slice 24 route (b)) — composes with this slice rather than
  competing.

---

## Task checklist

- [x] Gate 0 — the parasitic-loop hunt; FINDINGS above; advisor pass before gate 1.
- [ ] Gate 1 — `frames.jl` look-angle/boresight kernels + `test_frames.jl` teeth; `tools/test.ps1` green.
- [ ] Gate 2 — the `_observe_point3d!` seam + loader key + telemetry; byte-identity assert for 11/13/25.
- [ ] Gate 3 — scenario + the four proofs; re-run the 23/24/25 verifiers.
- [ ] Docs — `docs/STATUS.md` as-built, `CLAUDE.md` status line, `HANDOFF.md` §11, memory.
