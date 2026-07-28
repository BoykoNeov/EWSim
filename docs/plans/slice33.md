# Slice 33 — THE RING IS AN FOV BUDGET ITEM: WHAT THE PARASITIC LOOP COSTS YOU IS THE ENVELOPE (§11 Tier-A)

The ELEVENTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro, 32 = the seeker's field of view), and the
successor slice 32 itself nominated:

> *"**THE GIMBAL ON THE RADOME WIRE** — measured here (§ the corollary), kept off the showcase by
> convention 9. **The strongest successor: it is the first mechanism in the arc that turns slice
> 26's ring into a LOCK LOSS.**"* — `docs/plans/slice32.md`, Deferred (NAMED)

**Status: GATE 0 COMPLETE (4 probes, 2026-07-28). The advisor's opening hypothesis was REFUTED by
probe 1 and the live claim was found in a DIFFERENT CURRENCY by probes 2–4 (§0 below). Probe
scripts in `M:\claud_projects\temp\slice33\`.**

⚠ **THE DEFERRAL'S NAME IS LOOSE AND THE PLAN DOES NOT INHERIT IT.** Its § points at slice 32's
FOV × radome corollary, not at head state. A REAL GIMBAL — a head with its own state, servo
bandwidth, rate limit and mechanical stop — is a **separate and bigger slice**, and `frames.jl`
(~line 691) says so in terms: it *"adds a dynamical state AND it rewrites 26–31's `look_az` (the
bend would key off the HEAD-vs-body angle rather than the LOS-vs-body angle)"*. This slice stays
**STRAPDOWN**. The gimbal is re-banked below, with the lesson it should carry.

---

## The one-paragraph statement of the lesson

Slice 32 asked what field of view a seeker needs and answered with the ENGAGEMENT: the collision
triangle's own lead angle, `V_m·sin λ = V_t·sin θ`, which on its wire is 18.13°. **That is the
QUIET-GLASS answer.** Slices 26–31 spent six slices on a missile that shakes itself — and every one
of them recorded, as a standing fact, that *the ringing arm still hits*: slice 26 wrote "**the MISS
is NOT the metric** — the ringing arm STILL HITS (2.18 m)", and 27–31 each inherited it, which is
why the whole family measures `rms q` / `rms r` instead. It is true here too, everywhere: across
three glass depths and the full R̂ ladder, **not one ringing arm misses by more than 3.53 m**. The
ring was benign *because the seeker had an infinite window*. Give it a real one and the same ring —
same glass, same R̂, same seed — misses by **one to four kilometres**, because the excursion the
limit cycle adds to the look angle is spent out of the very budget slice 32 measured. **The FOV a
seeker needs is the engagement's lead PLUS the parasitic loop's excursion**, and the second term is
continuous and monotone in the ring's amplitude: 18.14° → 20.62° → 22.12° → 23.92° → 25.01° as `R̂`
walks from slice 30's design rule to slice 28's boresight characterization.

> **THE LESSON, IN ONE SENTENCE.** A limit cycle you were told to measure in rad/s is spent in
> DEGREES OF FIELD OF VIEW — the ring costs you not accuracy but the ENVELOPE, and slice 30's
> scalar buys the whole envelope back.

⭐⭐ **THE PAYLOAD IS THAT SLICE 30's RULE IS AN ENVELOPE RULE, NOT ONLY A STABILITY RULE.** Slice 30
shipped `radome_slope_worst` as the aim point that makes a scalar compensator unconditionally
stable. Aim `R̂` there and the FOV requirement returns to **18.14°** — the radome-free engagement's
own 18.13°, to within the missile's aerodynamic incidence — and it does so at A = −0.10, −0.15 AND
−0.20, i.e. **depth-independently**. The glass gets worse, the requirement does not move.

---

## §0 — Gate 0 (4 probes, 2026-07-28)

⚠⚠ **THE ADVISOR'S OPENING HYPOTHESIS WAS REFUTED, AND THE REFUTATION IS LOAD-BEARING** — it is the
reason this slice does NOT claim to invert slice 32's closing sentence. The hypothesis was that the
band between slice 32's two measured endpoints (`R̂ = R₀`, rings, 72 % out; `R̂ = radome_slope_worst`,
0.00 % out) might contain a *marginally* stable design whose look excursion is nonetheless past the
window — the first regime where the FOV bound binds BEFORE the stability bound.

**PROBE 1 killed it in its own currency.** The stability onset and the FOV break arrive at the SAME
`R̂` bracket — quiet at −0.27 (rms r 0.031, 0.000 % out), ringing at −0.24 (rms r **0.70983**, 37.6 %
out) — which reproduces slice 30's measured boundary to the digit (its "last decisive ring
−0.24/0.709"). ⇒ **slice 32's "the FOV bound is NOT tighter than the stability bound on this glass"
STANDS, and this slice must not be written as overturning it.** What slice 33 changes is that the
FOV *requirement* becomes a CONTINUOUS function of the residual where slice 32 had a single number.

⚠⚠ **THE ISOLATION, BAKED IN FROM THE FIRST RUN (advisor, before any probe): `rms r` IS NOT A
STABILITY READ ON A WINDOWED ARM.** Slice 32 already warned that the metric inverts — losing the
measurement CUTS the parasitic feed, so `rms r` FALLS while the miss OPENS — so a low `rms r` on a
windowed arm is indistinguishable between "this design is stable" and "the seeker lost lock and
stopped driving the loop". **Every `R̂` is therefore flown TWICE**: a FREE arm (no `seeker_fov_deg`
key at all) supplies the stability read and the excursion, and a WINDOWED arm at the SAME `R̂`
supplies the envelope read. This is not a probe convenience; it is the shipped discipline (§ the
seam).

### P1 — the band between slice 32's endpoints (`p1_rhat_band.jl`)

Glass R₀ = −0.03, A = −0.15 (⇒ `radome_slope_worst` = −0.33), vy = 200, fov = 20°.

| R̂ | FREE: rms r | FREE: excursion | FREE: miss | WINDOWED fov 20: miss | out % | t_break |
|---|---|---|---|---|---|---|
| −0.33 | 0.05879 | 18.14° | 0.184 m | 0.184 m | 0.000 | — |
| −0.30 | 0.04716 | 18.14° | 0.030 m | 0.030 m | 0.000 | — |
| −0.27 | 0.03070 | 18.14° | 0.114 m | 0.114 m | 0.000 | — |
| −0.24 | 0.70983 | 20.62° | 1.450 m | **936.312 m** | 37.620 | 6.632 |
| −0.21 | 0.85201 | 21.49° | 1.157 m | 2007.964 m | 43.261 | 5.141 |
| −0.18 | 0.93194 | 22.12° | 0.920 m | 2567.950 m | 44.736 | 4.421 |
| −0.15 | 0.99779 | 22.83° | 1.722 m | 2870.788 m | 49.034 | 3.852 |
| −0.12 | 1.03165 | 23.34° | 1.163 m | 3193.596 m | 62.783 | 2.809 |
| −0.09 | 1.05848 | 23.92° | 1.819 m | 3468.112 m | 65.869 | 2.426 |
| −0.06 | 1.07490 | 24.50° | 0.754 m | 3640.996 m | 69.271 | 2.117 |
| −0.03 | 1.07211 | 25.01° | 2.070 m | 3759.992 m | 72.226 | 1.883 |

Reference (no glass at all): rms r 0.01589, excursion 18.13°, miss 0.191 m, 0.000 % out at fov 20.

⭐ **THE FREE-MISS COLUMN IS THE SLICE.** Every ringing arm HITS (0.75–2.07 m) — the arc's standing
fact since 26 — and the SAME arm with a 20° window misses by 0.9–3.8 km.

### P2 — the predicate (`p2_fov_budget.jl`)

The critical FOV (smallest window that HOLDS: 0.000 % out AND miss < 10 m) against the excursion
measured on the FREE arm. Verdicts were monotone in `fov` in every row — a clean step, no
re-entrant cells.

| R̂ | rms r | excursion | critical fov | ⌈excursion⌉ |
|---|---|---|---|---|
| −0.33 | 0.05879 | 18.14° | 19° | 19 |
| −0.24 | 0.70983 | 20.62° | 21° | 21 |
| −0.18 | 0.93194 | 22.12° | 23° | 23 |
| −0.09 | 1.05848 | 23.92° | 24° | 24 |
| −0.03 | 1.07211 | 25.01° | 26° | 26 |

⭐ **AND THE TWO SIDES COME FROM DIFFERENT CODE PATHS ON DIFFERENT RUNS**, which is what makes it a
MEASUREMENT and not a restatement (slice 32's `collision_lead_angle` vs `seeker_in_fov` precedent):
the excursion is `boresight_angle(att, û_tru)` accumulated on an arm with **no `seeker_fov_deg` key
at all**, while `held` is the shipped `seeker_in_fov` verdict inside `_observe_point3d!`.

### P3 — causation and robustness (`p3_causation.jl`)

**(a) The ring's AMPLITUDE is the budget item — not the value of `R̂`.** `af_alpha_max` is slice
26's own instrument for exactly this: it grows the limit cycle's amplitude while leaving its onset
where it was ("the ceiling BOUNDS the cycle, the radome decides whether there IS one"). At **FIXED**
R̂ = −0.18 and **FIXED** glass:

| α_max | rms r | excursion | free miss | critical fov |
|---|---|---|---|---|
| 0.20 | 0.67256 | 20.67° | 1.842 m | 21° |
| 0.30 | 0.93194 | 22.12° | 0.920 m | 23° |
| 0.45 | 1.16949 | 23.70° | 0.746 m | 24° |
| 0.60 | 1.31490 | 24.30° | 0.441 m | 25° |

⚠ **α_max IS A CAUSATION PROBE AND MUST NOT BECOME A SLIDER** — it is a confounded lever (slice 20
disqualified it for the induced-drag bill) and the shipped wire HOLDS it (advisor; § convention 9).

**(b) Robustness — three glass depths, and the cure is depth-independent.**

| A | R̂ | rms r | excursion | free miss | critical fov |
|---|---|---|---|---|---|
| −0.10 | **−0.230** (slice 30's rule) | 0.02550 | **18.14°** | 0.139 m | 19° |
| −0.10 | −0.120 | 0.94087 | 21.93° | 0.349 m | 22° |
| −0.10 | −0.030 | 1.09301 | 24.31° | 0.238 m | 25° |
| −0.15 | **−0.330** (slice 30's rule) | 0.05879 | **18.14°** | 0.184 m | 19° |
| −0.15 | −0.120 | 1.03165 | 23.34° | 1.163 m | 24° |
| −0.15 | −0.030 | 1.07211 | 25.01° | 2.070 m | 26° |
| −0.20 | **−0.430** (slice 30's rule) | 0.08903 | **18.14°** | 0.579 m | 19° |
| −0.20 | −0.120 | 1.04638 | 24.16° | 2.131 m | 25° |
| −0.20 | −0.030 | 1.08561 | 25.55° | 3.528 m | 26° |

⭐⭐ **THE THREE BOLD ROWS ARE THE PAYLOAD.** Slice 30's aim point returns the requirement to 18.14°
at every depth — the radome-free engagement's own number.

**16 of 16 cells** across three independent axes (the R̂ ladder, an α_max amplitude sweep at fixed
R̂, three glass depths) satisfy `critical fov == ⌈excursion⌉`.

### P4 — cliff, or a survivable band? (`p4_transition.jl`)

The integer grid resolves the transition only to ±1°. At 0.25°:

| R̂ = −0.18, excursion 22.124° | | | R̂ = −0.03, excursion 25.011° | | |
|---|---|---|---|---|---|
| fov | out % | miss | fov | out % | miss |
| 21.50 | 42.42 | 1609.457 m | 24.50 | 61.34 | 2642.941 m |
| 21.75 | 41.46 | 998.585 m | 24.75 | 59.11 | 1819.179 m |
| **22.00** | **3.21** | **31.899 m** | **25.00** | **0.10** | **2.002 m** |
| 22.25 | 0.00 | 0.920 m | 25.25 | 0.00 | 2.070 m |

⭐ **A SURVIVABLE BAND EXISTS AND IT IS NARROW — about 0.4° wide.** At R̂ = −0.03 a window
**0.011° BELOW** the excursion loses lock for 0.10 % of the approach and still HITS (2.002 m, within
0.07 m of the free arm's 2.070) — slice 32's re-acquisition evidence, reproduced. 0.12° below →
31.9 m. 0.37° below → 998 m. Then kilometres.

⭐⭐ **AND `t_break` IS THE DISCRIMINATOR — SLICE 32's OWN MECHANISM IN A NEW AXIS.** Every
held-or-survived cell breaks at **t ≈ 10.3–10.4 s** (near CPA); every lost cell breaks at
**t = 1.9–6.2 s**, while the lead is still building. Slice 32: *"A short loss is survivable; what is
terminal is a loss while the lead is still building."* Here the same sentence is reached by moving
the WINDOW instead of the crossing speed.

---

## §1 — Gate 1 (COMPLETE, 2026-07-28 — 6028 → 6062)

**ONE kernel, in `frames.jl` beside slice 32's three:**

```julia
seeker_fov_margin(att, los, fov) = max(Float64(fov), 0.0) - boresight_angle(att, los)
seeker_in_fov(att, los, fov)     = seeker_fov_margin(att, los, fov) ≥ 0.0     # ← REDEFINED
```

⭐ **THE REDEFINITION IS THE GATE, NOT THE ADDITION** (advisor, before any code). Shipping the
margin *beside* the predicate and wiring it at gate 2 would leave gate 1 with a kernel nothing
calls — which is precisely the arrangement **slice 32's own gate 1 rejected one layer up** ("the
gate-0 seam computed `hypot(fa,fe) ≤ fov` INLINE, so kernels shipped beside it would have had
`test_frames.jl` prove a SECOND implementation and nothing about what flies"). Defining the
predicate FROM the margin puts the shipped number on the flying path with **zero seam edits** —
`missile.jl:1670` still calls `seeker_in_fov` — and leaves exactly ONE comparison site and ONE
clamp site. The clamp-ownership claim RELOCATED from `seeker_in_fov`'s docstring rather than being
duplicated there.

⚠ **AND THAT MAKES THE OBVIOUS TEST VACUOUS.** `(margin ≥ 0) == seeker_in_fov(...)` is now `x == x`
(convention 11's tautology), so it is NOT shipped. The tooth is the subtraction form against **the
comparison form written longhand** — the expression slice 32 shipped, `boresight_angle ≤
max(fov,0)` — **swept at the boundary**, because that is the only place a subtraction could diverge
from a comparison: 600 seeded `(att, los)` × 10 near-boundary windows (`b`, `prevfloat(b)`,
`nextfloat(b)`, `b·(1∓1e−15)`, `b∓1e−12`, `0.5b`, `2b`, `−b`) = **6000 cells, 0 mismatches, no
tolerance anywhere**, landing 3000/3000 on the two sides. The underlying fact is about IEEE doubles
and not about the algebra — two distinct finite doubles never subtract to zero, and rounding to
nearest preserves sign — which is what licenses the refactor at all; it is PINNED by that sweep,
not asserted in a comment. `x − x` is EXACTLY `+0.0` (600/600) and one ULP tighter is STRICTLY
negative (600/600), so slice 32's `prevfloat` boundary tooth is inherited intact.

⚠⚠ **THE DIVERGENCE THE ADVISOR CAUGHT, AND IT FLIPS A VERDICT — NOT JUST A MAGNITUDE.** The wire
ships `seeker_fov_deg` **AUTHORED** (slice 32: a HUD showing 0° for a negative slider would hide
what the student is holding), while the margin must use the **CLAMPED** window or its sign stops
agreeing with the predicate — which is the entire reason it exists. ⇒ **the shipped keys do not
reconstruct this one on a negative slider**, and a client deriving `fov − look_angle` disagrees
with the core. It is not merely a magnitude gap (−20° vs −25° at `fov = −5°`, `b = 20°`): it flips
the verdict on **exactly the LOS the never-locked state is defined by** — an on-boresight target is
IN a `fov = −1` window (only that one is), where the subtraction says OUT. Written into the kernel
docstring and pinned with a PAIRED agree-at-positive-`fov` case.

Also new: `NaN` in the predicate's degenerate table (a claim about `max`, which PROPAGATES — a
`max` written the other way round would admit everything); strict monotonicity in `fov` above the
clamp and flatness below it (what makes "widen the seeker" a one-slider cure with a well-posed
**bracket**, seam discipline 2); the exact-degree PAIRED polarity case (20° LOS: +5° inside a 25°
window, −5° against a 15° one).

**BEHAVIOUR-PRESERVING, PROVEN ON THE WIRE — not by reading the diff.** The predicate is provably
the same boolean, but this project's discipline is to measure it:

* **§0's P1 table reproduces CELL FOR CELL** — all 11 R̂ rows in both arms, plus the reference
  (0.01589 / 18.13° / 0.191 m). Spot: −0.24 → free rms r 0.70983, excursion 20.62°, free miss
  1.450 m; windowed 936.312 m, 37.620 % out, `t_break` 6.632. −0.03 → 1.07211 / 25.01° / 2.070 m;
  3759.992 m, 72.226 %, 1.883.
* **Slice 32's four showcase arms reproduce to the digit** — 1140.63505 / 0.16777 / 0.06197 /
  0.16777 m, ToF 15.40 / 15.31 / 12.93 s (its own gate-1 commit's numbers), `look_max` 103.14 /
  29.02 / 23.86 / 29.02°.
  ⚠ **THAT CLAIM COVERS MISS / ToF / `look_max` AND NOT THE `out%` COLUMN, WHICH IS DEAD** (advisor):
  `slice32/g1_wire_check.jl` read `comp[:seek_in_fov]` — the key **slice 32's own gate 2 removed**,
  as its stale-readout catch — so it defaulted to `true` and printed `0.0 %` on all four arms where
  slice 32 measured 67.98 %. A column that reproduces because it counts nothing is not a
  reproduction ("a number that does not print is not a proof", slice 21). ⭐ **FIXED to read the
  shipped `seeker_valid` telemetry, and the column then reproduces slice 32's own gate-1 number
  EXACTLY: 69.6 % / 0.0 / 0.0 / 0.0** — so the claim now covers all four columns, but it did so only
  after the dead one was found. P1's `out%` reads that same key and reproduces independently
  (37.620 / 43.261 / 44.736 / 49.034 / 62.783 / 65.869 / 69.271 / 72.226).
* Full suite green, **6028 → 6062**.

⭐ **AND THE RUN CONFIRMED THE SEAM DISCIPLINE'S PREMISE AS A NUMBER**: the windowed arms'
`look_max` column reads **96.29 / 90.95 / 89.42 / 89.27 / 90.32 / 90.08 / 90.14 / 90.40°** across
every broken cell — the post-lock-loss runaway, ~90° regardless of a ring whose actual excursion
was 20.62–25.01°. **The predictor and the predicted must not come from the same run**, and that is
now measured rather than argued (docstring; enforced by the verifier's structure at gate 3).

**What gate 1 deliberately does NOT own** (advisor's checklist): no `ceil` / `critical_fov` helper
(seam item 2 — it would pin the 1° measuring grid); no excursion or running-peak accumulator (peak
-hold is DISPLAY state, settled at slice 27); no telemetry key (gate 2); no knob and no rung (both
sliders already ship); and no proof that `critical fov == excursion` — that needs a wire, exactly
as slice 32's gate 1 deferred `look == lead`. **Seam item 1 is a DOCSTRING deliverable at gate 1,
not a test**: a pure kernel cannot exercise a two-run discipline, and manufacturing a test for it
would be a fake tooth.

⚠ **THE CLAMP CHANGED OWNER, AND THIS CODEBASE REPEATS THAT FACT DELIBERATELY** (advisor). The
seam comment at `missile.jl:1652` and the test comment at `test_frames.jl:907` both named
`seeker_in_fov` as the single clamp site; after the redefinition it DELEGATES and does not clamp,
so both were REWORDED (the seam's "deliberately NOT clamping twice" stays true and unchanged — the
edit is a reword, not a behaviour note). ⚠ `docs/STATUS.md:4284` says it too, inside **slice 32's
dated as-built entry**, and is deliberately LEFT ALONE: it records what slice 32 shipped, and
rewriting a per-slice ledger entry to match a later slice would make the ledger stop being a
history. **Gate 3's STATUS entry must state the relocation** — this line is the carry-forward.

**Carried into gate 2:** ship `<sid>.seeker_fov_margin_deg` under `_fov_on` with **`_finite_coord`,
never `_finite`** (the margin goes hugely negative on the never-locked side, and `_finite` clamps
only the upper bound — the slice-29 `k̂` catch, which slice 32's own comment at `missile.jl:2111`
already names); decide whether the seam hoists one margin local or telemetry calls the kernel again
(three `boresight_angle` calls/tick is nothing at 27k ticks/s, and hoisting risks ambiguity about
which kernel flies); and the byte-identity re-run of the 26–32 verifiers.

---

## What ships

### The core

⭐ **ONE new number: `<sid>.seeker_fov_margin_deg` = `fov − boresight_angle`, SIGNED.** The precedent
is slice 18's `terrain_clearance_m` exactly: a signed margin whose **SIGN IS THE VERDICT**
(`margin ≥ 0 ⟺ seeker_valid`), shipped so the client never re-derives the test (convention 13 — the
client NEVER re-tests occlusion). It gives the HUD a needle that the ring visibly eats.

⚠ **NO running-peak key** (advisor): peak-hold is DISPLAY STATE, and slice 27 already settled that
a peak-hold is an instrument, not physics.

⚠ **No new rung, no new knob, no new instability, no new cap.** Both sliders already ship
(`radome_slope_est` from 27/28, `seeker_fov_deg` from 32); the physics of both halves already
ships. What is new is the COMPOSITION, the number that measures it, and the design rule it yields.
Slice 30's shape precisely — its only new core quantity was `radome_slope_worst`, and its payload
was a ring count over a swept engagement.

### The seam — three disciplines that must be WRITTEN, not discovered at gate 3

1. ⚠⚠ **THE PREDICTOR AND THE PREDICTED MUST NOT COME FROM THE SAME RUN.** The excursion that
   predicts a window is measured on an arm with **no window**. The windowed arm's own `look_max` is
   **~90° in every broken cell** — that is the post-lock-loss runaway (slice 32's signature), not a
   read of the ring. This is slice 32's `look_angle`-gating catch and slice 29's stale-readout class
   in a NEW quantity, and it belongs at the kernel and in the test, not only in a probe comment.
2. ⚠ **ASSERT THE INEQUALITY, NEVER `ceil`** (advisor). `critical == ⌈excursion⌉` 16/16 is an
   artifact of the 1° measuring grid; the physical claim is `held ⟺ fov > excursion`. The tooth is
   built backwards from the measurement as a BRACKETING PAIR — a window just below the excursion
   breaks, one just above holds — exactly as slice 32 built its `≤` boundary tooth with `prevfloat`.
   Writing the `ceil` identity would pin a test to the grid it was never about.
3. ⚠ **`rms r` is never read off a windowed arm** (§0's isolation).

### Convention 9 — why the two-mechanism wire is now permitted

Slice 32 kept this composition OFF its showcase because two mechanisms in one view is a confound.
**Here the composition IS the lesson**, which is the legitimate exemption — but it obliges the wire
to carry no THIRD thing:

- `af_alpha_max` is **HELD** on the shipped wire and stays a gate-0 causation probe (§P3a).
- The two live sliders are the two halves of ONE quantity, and convention 9 is satisfied **by
  MEASUREMENT, not by counting sliders** — the slice-27 precedent: the DIAGONAL is `fov` TRACKING
  the excursion, and moving both together leaves `held` UNCHANGED (P2's critical-fov column read as
  a path), so the pair is one axis, not two lessons.
  ⚠ **State the diagonal as tracking, NEVER as `fov = ⌈excursion(R̂)⌉`** (advisor) — seam item 2
  forbids asserting the `ceil` identity, and letting the `ceil` form carry the convention-9 argument
  puts the two statements in tension in one document and invites gate 3 to reach for exactly the
  identity it was told not to pin.

### The wire (proposed — gate 1 confirms)

Slice 32's geometry and glass: seed 32, vy = 200, R₀ = −0.03, A = −0.15, `fov` held while `R̂`
slides. Ladder at fov = 21°: HELD at R̂ = −0.33 (18.14°) and −0.24 (20.62°), LOST at −0.18 (22.12°),
−0.09, −0.03. Both cures are one slider each: **widen the window** (fov → 26 holds everything) or
**aim `R̂` at `radome_slope_worst`** (free, and depth-independent).

⚠⚠ **THE INTEGER LADDER STEPS STRAIGHT OVER THE SURVIVABLE BAND, AND THE TEST SET MUST NOT**
(advisor). Every cell above is either 0.000 % out or kilometres out, while P4's interesting regime
— 0.10 % out, still HITS, `t_break` ≈ 10.3 s — lives within ~0.4° of the excursion. **Slice 32 put
BOTH DIRECTIONS IN THE SAME TEST for exactly this reason**: the survivable arm is what proves the
coasting branch RE-ACQUIRES CLEANLY, and without it that branch is live-looking with no tooth (its
"⭐ AND THIS IS THE PROOF THE COASTING BRANCH RE-ACQUIRES CLEANLY"). ⇒ the sub-degree cell
**R̂ = −0.03, fov = 25.00 against a measured excursion of 25.011°** joins the test set.
⚠ **PIN IT AGAINST THE MEASURED EXCURSION, NEVER A HARDCODED 25.0** — the margin there is 0.011°,
below the measuring grid, so a literal becomes a magic number the next retune silently breaks
(the slice-21 magic-multiple tooth, now pinned against a measured quantity).

### The four proofs (convention 14)

`net/slice33_verify.gd`, `net/slice33_ui_test.gd`, a `Sandbox.tscn` headless smoke-load, a windowed
shot. ⚠⚠ **`STEPS` MUST BE A MULTIPLE OF `emit_every`** (slice 31 lost an hour to the silent hang;
slice 32 used 16000 = 16 × 1000). ⚠ Anything the verdict computes inside `_draw` has no headless
proof — the margin verdict goes in a pure helper the UI test calls. ⚠ ToF varies arm to arm; size
`STEPS` off the SLOWEST arm and assert every arm REACHED CPA. ⚠ Re-run the 26–32 verifiers ON THE
WIRE as the byte-identity check.

---

## Deferred (NAMED)

* ⭐ **A REAL GIMBAL — and it now has its lesson, banked at gate 0.** A head with its own state,
  servo bandwidth, rate limit and mechanical stop. **The lesson it should carry: the gimbal that
  saves your envelope PARKS YOU ON THE WORST GLASS.** A strapdown seeker's body chases the LOS, so
  the look angle stays near the lead; a gimbal deliberately holds the head at the FULL lead angle,
  which is exactly the steep part of the curve slice 28 showed closes the loop. So a gimbal buys the
  envelope back and hands the radome a worse operating point — the same trade in a new place. ⚠ It
  REWRITES 26–31's `look_az` (the bend would key off head-vs-body), which is the byte-identity
  surface of six slices, so it needs a presence-gated head state with the strapdown else-arm
  VERBATIM.
* **A RECTANGULAR / PER-AXIS FOV** — slice 32 ships ONE circular window; a two-axis gimbal really
  does have independent mechanical stops.
* **SEEKER RANGE / SNR ACQUISITION LIMITS** — the other half of "can the seeker see it".
* **THE HANDOVER BASKET as an authored quantity** — slice 32's P5 found the launch look angle is a
  live physical constraint its wire holds fixed.
* Everything 26–32 named and did not spend: estimating `R̂` in flight (blocked by 26's P7A, sharpened
  by 29); a 2-D slope `R(look_az, look_el)`; an asymmetric error curve; a SINGLE IMU; gyro NOISE
  (draw-topology, convention 3); per-axis scale factors and misalignment; the out-of-plane
  MANEUVERING target.
