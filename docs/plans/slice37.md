# Slice 37 — PART I: MEMORY TRACK / RE-ACQUISITION, **KILLED AT GATE 0** · PART II: **THE HEAD'S OWN GYRO**, the slice that took the slot (§11 Tier-A)

**ONE NUMBERED PLAN FILE HOLDS BOTH — the `docs/plans/slice20.md` precedent** (a candidate killed in
its own gate 0, and the slice that then filled the slot, in one file so the kill cannot be re-proposed
without meeting it). **PART II begins at "THE HEAD'S OWN GYRO" below.**

**Part I status: DEAD, NOT DEFERRED. Killed at gate 0 on 2026-08-17 in five probes, no core change shipped.**

The candidate: the deferral slice 34 named third, slice 35 carried forward unchanged, and slice 36
SHARPENED into a falsifiable prediction —

> *"**MEMORY TRACK / RE-ACQUISITION** — unchanged from slice 34/35, and every break measured here is
> still TERMINAL. ⚠ SHARPENED: a memory track is exactly what would rescue the *too-much-bias* side
> of §0.6's basket, so it would make the basket ONE-SIDED. That is a real prediction and a real
> slice."*
> — `docs/plans/slice36.md`, Deferred (NAMED)

**The prediction is REFUTED, the premise underneath it is refuted, and the replacement subject is not
a memory track.** This is the slice-20 shape — a named deferral killed by measurement rather than
shipped (`δ_max` structurally SHADOWS `δ̇_max`, `docs/plans/slice20.md`) — and it is worth the file
for the same reason: the next person to reach for this will otherwise reach for it again.

Probe scripts and the full measured tables in `M:\claud_projects\temp\slice37\` (`lib37.jl`,
`p1_break.jl`, `p2_reparam.jl`, `p3_coast.jl`, `p4_ring.jl`, `p5_slow_ring.jl`, `g0_results.md`).

⚠ **P3/P4/P5 NEEDED A KERNEL PATCH** (a `:probe_coast` `elseif` after the shipped slew in
`missile.jl`'s head block — slice 35's gate-0 precedent). It was applied for the runs and REVERTED:
`git diff --stat core/src/missile.jl` is empty and the suite is green at **7222** as of this file.

---

## The one-paragraph statement of what was measured

Since slice 34 a break has been **terminal**: once the target leaves the detector window the head
holds, no error signal, no slew. Three slices wrote that down as the natural home of a memory track —
a real head coasts on its last inertial rate — and slice 36 predicted which half of its basket the
coast would buy back. Build the coast honestly (the head follows the α-β tracker's own COASTED
INERTIAL estimate, projected through the CURRENT attitude — nothing unavailable to the missile) and
it rescues **one boundary cell out of fifteen** and moves no verdict anywhere else. The reason is one
column: on every wire in this arc, **a break is not an episode — it is the rest of the flight**, 6.0
to 7.9 seconds of it. Long before a coasting head could point anywhere useful, the tracker's FROZEN
rate has stopped resembling the truth and the guidance solution is already lost.

> **THE RESULT, IN ONE SENTENCE.** A memory track is not a head feature in this architecture: what
> makes a break terminal is the ESTIMATOR's frozen rate ruining the guidance solution, not where the
> head is pointing — so the cure three slices banked was **mis-located**, and pointing the head
> better cannot reach it.

---

## §0 — Gate 0 (5 probes, 2026-08-17)

The wire is `scenarios/slice36_handover.yaml` to the digit (seed 32, crossing target vy = 200, NO
glass, window 10°, servo 8 °/s, stop 30°, τ = 0.05, n_pn = 8), with the handover error, the window,
the servo and the glass as parameters. Every probe flies the SHIPPED `EWSim.Seeker` off the real comp
keys.

### ⚠⚠ §0.1 — THE ADVISOR'S BLOCKING QUESTION, RUN FIRST: THE BASKET'S TWO SIDES BREAK DIFFERENTLY

Perfect handover: az **+18.10537°**, el −0.65598°.

| err ° | ever locked | break t_lost | off@lost | azdot@lost °/s | LOS az birth → final | out % | miss m |
|---|---|---|---|---|---|---|---|
| −18 … −12 | **NO** | — | — | — | +18.105 → **+73.784** | 100.0 | 3620.675 |
| −10 | yes (tick 1) | 0.002 | 10.004 | **+0.0000** | +18.105 → +73.784 | 100.0 | 3620.675 |
| −8 / −6 / −4 | yes | (CPA only) | — | — | +18.105 → −15.307 | 0.0 | **0.191** |
| −2 | yes | 0.662 | 10.004 | +3.0054 | +18.105 → −93.361 | 92.3 | 2965.542 |
| **0** | yes | **0.434** | 10.007 | +3.4438 | +18.105 → −92.470 | 94.6 | 3290.078 |
| +2 … +12 | yes | 0.018–0.512 | ~10.0 | +3.6 … +4.4 | +18.105 → ≈ −92 | 96.5–99.8 | 3344–3566 |

⭐⭐ **THE TOO-MUCH-BIAS SIDE NEVER ACQUIRES.** At err ≤ −12 the head is born ≥ 12° off a 10° window,
`in_fov` is false on tick 1, `:seek_init` never flips, and the arm lands in `missile.jl:2026`'s
NEVER-LOCKED branch where every rate is `0.0`. The too-little-bias side (err ≥ −2) locks on tick 1
and loses the window during the acquisition turn. ⇒ **the two halves of slice 36's basket are two
different failures**, and a memory track has NOTHING TO COAST ON on exactly the half slice 36
predicted it would rescue.

⚠ err = −10 is the boundary cell and belongs to neither: it locks on tick 1 and loses the window on
tick 2 with a frozen rate of EXACTLY +0.0000 °/s — a lock that has no rate yet.

⚠ **THE FRAMES DIFFER, AND THE SIGN IS THE TELL** (the #1 sign trap's 11th occurrence, avoided). At
the break the tracker's frozen rate is **+3.44 °/s** while the body-frame LOS is travelling the OTHER
way (+18.105 → −15.307). These are different quantities — the estimator coasts in INERTIAL angles,
the head points in BODY angles — which is why slice 34's own wording (*"coasts on its last inertial
rate"*) is the correct formulation and a body-frame coast would have been wrong and plausible.

⚠ The never-acquired arms show NO LOS reversal at all (+18.105 → +73.784, monotone); the
locked-then-lost arms run away to ≈ −92°. Two mechanisms, two signatures.

### §0.2 — THE REPARAMETERIZATION GATE, RUN BEFORE ANY KEY WAS WRITTEN

Slice 36 ran this as its §0.8 for `gimbal_stop_deg`; slice 31's version was a blocking advisor catch.
Two-run discipline: `req` is `off_max` on a FREE window, the verdict a SEPARATE flight behind 10°.

| err ° | req ° (free) | w10 verdict | miss m | min window that holds |
|---|---|---|---|---|
| −18 / −14 / −12 | 18.000 / 14.000 / 12.000 | never locked | 3620.675 | 20.0 / 15.0 / 12.5 |
| −10 | 10.00000 | lost | 3620.675 | 11.0 |
| −8 / −6 / −4 | **8.00000** / 8.09069 / 9.49992 | HELD | 0.191 | 10.0 |
| −2 | 10.97074 | lost | 2965.542 | 11.0 |
| 0 | **12.34604** | lost | 3290.078 | 12.5 |
| +2 … +12 | 14.194 → 24.079 | lost | 3344–3421 | 15 → 25 |

⇒ slice 36's **V** reproduced on this slice's own run (left arm `|err|` EXACTLY to five decimals,
kink at −8, right arm the chase cost), which is what licenses using this wire at all. ⭐ And the
gate's own answer: widening the window rescues cells in order of `req`, and that order **INTERLEAVES
the two mechanisms** — −12 (never-acquired) sits between −2 and 0 (lost-track). The window is BLIND
to which mechanism broke the arm, so a coast that rescues only one of them is not a
reparameterization of the window. The gate PASSES; it is not what kills the slice.

### ⭐⭐ §0.3 — THE DECIDING PROBE: THE HONEST COAST RESCUES ONE CELL OF FIFTEEN

Three arms per cell. `:none` = SHIPPED (the head freezes). `:memory` = the head coasts toward the α-β
tracker's COASTED INERTIAL estimate projected through the CURRENT attitude — the honest memory track.
`:leak` = the head coasts toward `head_tgt`, i.e. the MEASURED angles the seam writes unconditionally
at `missile.jl:2017-2022` and which PHYSICALLY DO NOT EXIST out of the window.

| err ° | shipped out % / miss | `:memory` out % / nreacq / coast_max s / miss | `:leak` miss |
|---|---|---|---|
| −18 | 100.0 / 3620.675 | 100.0 / 0 / 7.358 / **3620.675** | 2350.299 |
| −14 | 100.0 / 3620.675 | 100.0 / 0 / 7.358 / **3620.675** | **0.131** |
| −12 | 100.0 / 3620.675 | 100.0 / 0 / 7.358 / **3620.675** | **0.110** |
| −10 | 100.0 / 3620.675 | **0.0 / 0 / 0.001 / 0.191** | 0.191 |
| −8 / −6 / −4 | 0.0 / 0.191 | 0.0 / 0.191 (unchanged) | 0.191 |
| −2 | 92.3 / 2965.542 | 92.3 / 0 / 7.923 / 2951.237 | 2951.237 |
| **0** | 94.6 / 3290.078 | 94.7 / 0 / 7.732 / **3194.488** | 3194.488 |
| +2 … +12 | 96.5–99.8 / 3344–3421 | unchanged to ≤ 11 m | ≈ unchanged |

⭐⭐ **ONE CELL OF FIFTEEN** — err = −10, the boundary cell, rescued by coasting for **1 ms**.
Everywhere else the coast is inert: the showcase (err = 0) moves 3290.078 → 3194.488, a 3 % change on
a 3.3 km miss, and **no verdict moves on any cell**.

⭐⭐ **AND THE REASON IS THE `coast_max` COLUMN: 7.3–7.9 s.** The break is not an episode, it is the
rest of the flight. By the time a coasting head could point anywhere useful, the tracker's FROZEN rate
has long stopped resembling the truth, so the head chases a stale prediction and never re-acquires —
`nreacq` = **0** on every lost-track cell. **A coast only pays if the break is BRIEF, and on this wire
no break is.**

⭐⭐ **THE TRUTH LEAK IS TOTAL, AND IT LANDS EXACTLY WHERE THE INFORMATION ISN'T.** `:leak` rescues the
NEVER-ACQUIRED side — 3620.675 → 0.110 / 0.131 at err = −12 / −14 — i.e. precisely the cells where the
tracker never had a measurement to coast on. That is not a memory track by any definition; it is the
head being TOLD where the target is. ⇒ **the gap between `:leak` and `:memory` IS the measurement**
(slice 27's rule — *compensate with a signal not itself corrupted by what you are compensating* — in a
new place), and it is the whole result on one side and exactly zero on the other. No shippable memory
track can reach any of `:leak`'s rescues.

⚠ **AND `:leak`'s PROVENANCE IS THE SEAM, NOT THE PROBE'S SEEDING** (advisor — the number a re-cue
slice would be built on has to rest on a log). The probe seeds `head_tgt_az` to the birth angle
+6.105365°; by **tick 1** it already reads **+18.106199°**, tracking the true body-frame LOS
(+18.105365°) to a thousandth of a degree, while `seek_init` is still false and the head crawls
+6.105 → +6.145° at exactly 8 °/s. The unconditional write is what flies.

⚠ `:leak` at err = −18 is 2350 m and still a miss: even handed the measurement, a head born 18° off a
10° window cannot close before the geometry runs away. The leak is not omnipotent — it is just
information the missile does not have.

### ⚠⚠ §0.4 — THE LAST DOOR: IS THERE A **BRIEF** BREAK ANYWHERE IN THE ARC?

If a coast only pays on brief breaks, its natural home is a RINGING gimballed wire — slice 32's own
corollary recorded that a ringing compensator can shake the seeker out of its window. Slice 35's glass
(R₀ = −0.03, A = −0.15, R̂ = −0.03 — the boresight-characterized compensator, which rings), SHIPPED
truth handover, window swept down.

⚠ **THE FIRST RUN OF THIS PROBE WAS RUN AT THE WRONG SERVO AND ITS NEGATIVE WOULD NOT HAVE HELD**
(advisor): at 40 °/s slice 35 had already measured the requirement to be ~2°, so `out % = 0.0` at
every window down to 12° proves nothing. Re-flown at **8 °/s**, where slice 35 measured ~19.3°:

| fov ° | shipped out % / nreacq / coast_max s / off_max ° / miss | `:memory` miss |
|---|---|---|
| 25 / 22 / 20 | 0.0 / 0 / ~0.01 / **19.279** / 3.191 | 3.191 (identical) |
| 19 | 84.4 / **0** / 6.440 / 100.628 / 3482.530 | 3352.392 |
| 18 | 86.4 / **0** / 6.570 / 101.855 / 3499.589 | **3650.796** |
| 16 | 88.3 / **0** / 6.202 / 102.784 / 3754.671 | 3751.295 |
| 14 | 90.8 / **0** / 6.052 / 103.580 / 3855.630 | 3855.633 |
| 12 | 93.4 / **0** / 6.195 / 104.941 / 3865.404 | 3865.411 |

⭐⭐ **THERE IS NO EPISODIC REGIME. THE WINDOW EITHER HOLDS OUTRIGHT OR BREAKS TERMINALLY**, with
nothing in between: `nreacq` is **0 on every arm at every window**, and `coast_max` steps from ~0.01 s
(the r ≤ 200 m endgame) straight to 6.0–6.7 s. The transition sits between a 20° window (0.0 % out,
3.191 m) and a 19° one (84.4 % out, 3482 m) — one degree. ⚠ And the coast is not merely inert here,
it is mildly HARMFUL at fov 18 (3499.589 → 3650.796): a head chasing a stale estimate points worse
than a head that stopped.

⚠ The `off_max` column is the TWO-RUN DISCIPLINE again — 19.279° on a held arm against 100–105° on a
broken one, which is the post-break runaway and not a requirement (slice 33's finding, 7th occurrence).

⚠ The quiet control (slice 30's design rule, R̂ = −0.33) is flat at `out % = 0.0`, miss 0.234,
rms r 0.05890 across every window from 25 down to 12 — as it must be, and it confirms the breaks above
belong to the ring.

---

## Why the candidate is DEAD rather than deferred

Three measurements, each sufficient on its own:

1. **The prediction is refuted.** The half of slice 36's basket a coast was predicted to rescue is the
   half that NEVER ACQUIRES, where there is no track to remember (§0.1, §0.3).
2. **The mechanism is mis-located.** What makes a break terminal is the ESTIMATOR's frozen rate
   destroying the guidance solution over 6–8 seconds, not where the head points. A head feature cannot
   reach it: the honest coast moves one cell of fifteen and no verdict (§0.3).
3. **There is no wire in the arc with a brief break to ride through.** Breaks are binary here — hold,
   or lose it for the rest of the flight — on both the handover wire and the ringing wire, at both
   servo rates (§0.4).

⚠ **WHAT WOULD REVIVE IT, STATED SO IT IS NOT RE-DISCOVERED BY ACCIDENT.** A memory track needs an
episodic break, and this architecture has none because nothing here recovers a guidance solution once
the rate freezes. The enabling change is therefore NOT on the head at all — it is a tracker that
maintains a usable rate through a gap (a target-state estimator with its own dynamics, rather than an
α-β filter running predict-only). That is a different and larger slice, and a coast would be its
corollary rather than its subject.

⚠ **DO NOT RE-IMPORT SLICE 36's FRAMING FOR IT.** "The basket becomes one-sided" is measured false at
§0.1 and the file that predicted it should be read with this one.

---

## ⭐ What the probes surfaced that IS live (named, not taken)

**THE NEVER-ACQUIRED SIDE NEEDS A RE-CUE, NOT A COAST.** `:leak`'s 3620.675 → 0.110 m at err = −12
says the information is worth kilometres, that it arrives from OUTSIDE the seeker, and that the
missile does not have it. A slice that gives the head a search pattern, or a second cue from the
launching platform, would own that number — and §0.3 has already measured both its ceiling (`:leak`)
and the floor everything internal is stuck at (`:memory`). ⚠ It is a genuinely different subsystem
from anything in 26–36, and ⚠ `:leak` at err = −18 (2350 m, still a miss) says even a perfect re-cue
has a domain.

---

## The slice-37 slot: candidates, untouched by any of this

* ⚠⚠ **THE HEAD'S OWN GYRO — TAKEN. It is PART II of this file**, and its gate 0 REFUTED the wording
  above ("measures inertial LOS rate DIRECTLY"): the shipped seeker already does. See §II.0.
* **A SECOND-ORDER SERVO (ω_a / ζ_a)** — slice 35's own named successor; slice 15's actuator is the
  precedent for what an inertia and a bandwidth add over a lag plus a rate limit.
* **A HANDOVER BASKET WITH A DISTRIBUTION** — slice 36's own first-named successor (a covariance and a
  Pk over the basket rather than a single arm). ⚠ Note §0.1 before scoping it: the basket's two sides
  fail by different mechanisms, so a Pk over it is a mixture of two failure modes, not one.
* **THE CAGE vs THE AIM AS ITS OWN A/B**, **THE ELEVATION HALF**, **A RECTANGULAR / PER-AXIS STOP**,
  **SEEKER RANGE / SNR ACQUISITION LIMITS** — all as slice 36 left them.

---
---

# PART II — SLICE 37 AS SHIPPED: **THE HEAD'S OWN GYRO**

## A RATE-STABILIZED HEAD: THE SERVO LAG WAS DOING STABILITY WORK

**Status: gate 0 COMPLETE (2026-08-17, six probes). The claim is real, the reparameterization gate is
answered by a BOUND, and the lesson INVERTS the deferral's own framing.** Raw numbers:
`M:\claud_projects\temp\slice37g\g0_results.md`. Probe patch applied for P2–P5 and **REVERTED** before
P6; `git diff --stat` empty; suite green.

Wire: `scenarios/slice35_rate.yaml` to the digit (seed 32, vy 200, glass R₀ = −0.03 / A = −0.15 /
k = 12, window 25°, stop 30°, τ = 0.05, n_pn = 8, σ 5e-5). Band `r ∈ [500, 3000] m` (28/33/34/35's).
Metric `rms r` — slice 28's YAW channel, because the lead is in azimuth.

---

## §II.0 THE FRAMING CORRECTION, BEFORE ANY PROBE (advisor) — the deferral's own wording is WRONG

`docs/plans/slice34.md:931` named this slice as *"a rate-stabilized head measures inertial LOS rate
DIRECTLY, which is the classical reason gimbals exist"*. **`missile.jl:1652` is `az_el(û_tru)`, NOT
`look_angles(att, û_tru)`.** The seeker already reports **INERTIAL** LOS angles, the α-β tracker
already produces an **INERTIAL** LOS rate, and PN is frame-consistent — the shipped model is an
implicitly, perfectly body-motion-isolated seeker. ⇒ **THE HEADLINE THE DEFERRAL PROMISED IS ALREADY
TRUE AND CANNOT BE SHIPPED.** What is body-referenced is the **SERVO**: `head_tgt = look_angles(att,
…)` and `head_slew_full` rate-limits the step in **BODY** coordinates.

⚠⚠ **FRAMING A WAS KILLED BEFORE IT WAS PROBED — IT IS SLICE 31's TRAP.** "Strapdown reconstruction
with a corrupted gyro" adds `s·ω_body` to the measured LOS rate; the radome adds `−R·ω_body` to first
order. **The loop cannot distinguish a body-motion-isolation gain error from a radome slope error**,
so the stability claim collapses onto slice 26's boundary and what survives is slice 31's shipped
shape with a bigger gain — a second design-rule slice of the same shape, i.e. convention 4's
copy-paste false-claim trap. It does not ship, and it is written down here so it is not re-proposed.

⇒ **THE SLICE IS THE SERVO'S REFERENCE FRAME.** Head state becomes an INERTIAL pointing direction,
the rate limit bounds the **INERTIAL** step, the body-relative angle is DERIVED (and is what the stop
and the glass see), and body motion is **REJECTED PASSIVELY** instead of tracked out.

---

## §II.1 THE PREMISE, ARITHMETICALLY (P1, no patch) — HOLDS, and the asymmetry is the interesting half

`dem` = slice 35's `head_rate_dps`; `wl` = ‖measured inertial LOS rate‖, what a stabilized head must
slew at. **dem/wl is the saving an inertially-referenced servo would buy:**

| arm (40 °/s) | rms r | dem_rms | wb_rms | wl_rms | **dem/wl** |
|---|---|---|---|---|---|
| R̂ = −0.18 (slice 34's design) | 0.01172 | 0.303 | 0.979 | 0.354 | **0.86** |
| R̂ = −0.16 (one rung up) | 0.35421 | 15.801 | 20.323 | 2.070 | **7.63** |
| R̂ = −0.03 (boresight) | 0.86288 | 70.561 | 49.699 | 8.618 | **8.19** |
| R̂ = −0.33 (slice 30's rule) | 0.05890 | 1.604 | 3.558 | 0.855 | **1.88** |

⇒ an inertial servo buys **essentially nothing on a quiet design (0.86×) and 8.19× on a ringing one**.
Slice 35's demand really is the missile's own rotation. ⚠ Had these columns not co-scaled the slice
was dead for the price of a calculator — which is why this probe ran first.

---

## §II.2 THE FRAME TOOTH (P2, bench) — the #1 SIGN TRAP's 12th occurrence guarded before flight

⚠ **THIS SLICE IS *ABOUT* A FRAME CHANGE and the sign trap has fired 11 times**, so the invariants are
measured on a bench before anything flies.

**P2a — freeze the geometry, spin the body.** Inertial LOS fixed, body rotating at ω, τ = 0.05 s. The
SHIPPED head chases a target that moves IN ITS OWN FRAME and settles to a steady-state pointing error
**≈ τ·ω** (0.135679° vs 0.143239° at ω = 0.05; 0.541664° vs 0.572958° at ω = 0.20; 1.421764° vs
1.432394° at ω = 0.50); the STABILIZED head's error is **0.000000000° at every ω**.
⚠ **THE PROBE ALSO RAN ω ≥ 0.8 AND THOSE ROWS ARE DELIBERATELY NOT REPRODUCED HERE**: at 40 °/s the
RATE LIMIT breaks the small-error regime and they read 74.7°/95.4° against a τ·ω column of 2.3°/3.4°,
which is the rate limit and not the lag law. A later reader seeing them beside that column would
mis-read the tooth, so they stay in `g0_results.md` and out of the plan.

**P2b — at zero body rate the two frames are the same frame:** `max|STAB(expressed in body) − SHIP|`
over 3000 ticks = **1.110e−16 rad**. ⇒ the heads are distinguishable ONLY by body rotation.

---

## §II.3 ⭐⭐ THE REPARAMETERIZATION GATE, ANSWERED BY A BOUND (P3b) — the result that licenses the slice

Convention 4 and `atmosphere.jl`'s discriminator ask whether the off-state is knob-reachable. Target
cell R̂ = −0.03; **the STABILIZED head at 8 °/s reaches `off_band` 3.861** (dem 29.261).

| τ (s) | rate | rms r | off_band | dem_rms |
|---|---|---|---|---|
| 0.050 | 8 | 0.38591 | 12.828 | 143.07 |
| 0.050 | 200 | 0.88465 | 5.916 | 38.12 |
| 0.010 | 200 | 1.01252 | 4.979 | 45.61 |
| 0.001 | 200 | 1.06497 | **4.796** | 48.50 |

⇒ **A 25× FASTER SERVO WITH A 50× SMALLER TIME CONSTANT STOPS AT 4.796 AND CANNOT REACH 3.861.**
The gate is answered by a **BOUND, not a tolerance window** — ⚠ the first draft used a 15 %
"REACHES IT" column, which invites *where did 15 % come from?*; the bound needs no threshold at all.
**⇒ RUNG, NOT KNOB.** The absent key must be bit-identical BY CONSTRUCTION (a branch whose else-arm
is slice 34/35's line TEXTUALLY UNCHANGED), never a `ω_ref = 0` trusted to cancel — the `-0.0` trap
20/21/26/27/28/35/36 all name.

---

## §II.4 ⚠⚠ THE ISOLATION FAILS IN τ, AND WHERE IT ACTUALLY LIVES (P4a / P5b — the advisor's blocking catch)

The first draft read *"convergence ⇒ the difference IS the frame"*. **The plain reading of that table
is that the two curves CROSS**: shipped `rms r` RISES 0.01172 → 0.06051 as τ falls while stabilized
FALLS 1.00097 → 0.01704, the order SWAPS near τ = 0.005, and Δ is NON-MONOTONE (minimum at 0.005,
growing after). Slice 34's isolation was `max|Δpos| = 0.0 EXACTLY`. Re-measured in that quantity:

| τ (s) | 0.05 | 0.01 | 0.001 | 1e−4 | 1e−5 | 1e−6 |
|---|---|---|---|---|---|---|
| `max abs Δpos` (m) | 64.235 | 32.613 | **42.572** | **42.572** | **42.572** | **42.572** |

⇒ **THE TWO HEADS DO NOT COLLAPSE IN ANY LIMIT OF τ.** ⭐ **P5b LOCATES THE RESIDUAL AND THE
ISOLATION EXISTS — AGAINST A DIFFERENT HEAD.** The shipped seam expresses its servo target in the
attitude **OF THE TICK IT WAS MEASURED** (`head_tgt = look_angles(att(k), …)`, consumed at k+1), while
the stabilized target is attitude-FREE and is consumed against att(k+1). A bench head that
re-expresses the target in the CURRENT attitude ("FRESH"):

| τ (s) | 0.05 | 0.01 | 0.001 | 1e−5 | 1e−7 |
|---|---|---|---|---|---|
| abs(STAB − FRESH) (rad) | 2.568e−02 | 5.589e−03 | **0.000e+00** | **0.000e+00** | **0.000e+00** |
| abs(STAB − SHIP) (rad) | 2.621e−02 | 6.210e−03 | 6.259e−04 | 6.259e−04 | 6.259e−04 |

⇒ at τ → 0 the stabilized head is **BIT-IDENTICAL** to a body-referenced head whose target is
re-expressed in the current attitude, and **the residual against the SHIPPED head is EXACTLY ONE TICK
OF ATTITUDE** — a property of the seam's ORDERING, not of the servo, and not removable by τ.
⚠ **THE PLAN MUST NOT CLAIM A COLLAPSE THE DATA DOES NOT SHOW**; the honest statement is *"the frame
difference has a τ → 0 limit only against a fresh-attitude head; against the shipped seam there is an
irreducible one-tick term."*

---

## §II.5 ⭐⭐ THE MECHANISM, MEASURED AGAINST CLOSED FORM (P4b) — NOT inferred from `rms r`

⚠ *"The servo lag was doing stability work"* is a claim about **THE INDEX** (the head's BODY-frame
angle — the part of the dome the ray passes through), so it is measured there. Geometry FROZEN, body
oscillating sinusoidally, τ = 0.05 s:

| f (Hz) | SHIP gain | **STAB gain** | `1/sqrt(1+(2πfτ)^2)` |
|---|---|---|---|
| 0.25 | 0.9970 | **1.0000** | 0.9969 |
| 1.00 | 0.9547 | **1.0000** | 0.9540 |
| 1.70 | 0.8838 | **1.0000** | 0.8821 |
| 2.10 | 0.8370 | **1.0000** | 0.8347 |
| 4.00 | 0.6263 | **1.0000** | 0.6227 |

⇒ **THE SHIPPED SERVO IS A LOW-PASS FILTER ON THE PARASITIC PATH**, matching the first-order law to
3–4 digits at EVERY frequency, and the stabilized head's index tracks body motion at **UNITY GAIN,
EXACTLY, AT EVERY FREQUENCY**. ⭐ The ring lives at **1.7–2.1 Hz** (slice 26), where that filter is
worth 12–16 % of gain and ~30° of phase — **which is what a design one rung inside the bracket has
been living on since slice 34, unnamed.**

---

## §II.6 ⭐⭐ THE LADDER: THREE HEADS, ONE WIRE, ONE 0.005 GRID (P4c / P5a / P6)

⚠⚠ **THE ONSET LINE IS NOT ALLOWED TO BE A BARE NUMBER I CHOSE** (advisor). The first draft bracketed
on `rms r > 0.20`, which appears NOWHERE in 26–36 and was doing real work: the shipped head reads
**0.17308** at R̂ = −0.165 — 13 % below that line and already an ORDER OF MAGNITUDE above its 0.01172
plateau — so moving the line to 0.15 moves the bracket one cell and the headline fraction with it.
That is exactly the *where did 15 % come from?* objection §II.3 raises against itself. ⇒ **the rule
here is THRESHOLD-FREE: the bracket is the cell with the LARGEST SINGLE-STEP RATIO in `rms r`**, and
the full ladder is printed so a reader can redraw the line and see what moves.

| head | `rms r` across the transition | **bracket (largest-step rule)** | patch? |
|---|---|---|---|
| **STRAPDOWN** (no head) | 0.03070 → 0.07250 → **0.32320** (2.4×, **4.5×**) | **(−0.265, −0.260]** | no — SHIPPED path |
| **GIMBAL, position-servoed** | 0.03992 → **0.17308** → 0.35421 (**4.3×**, 2.1×) | **(−0.170, −0.165]** | no — SHIPPED path |
| **GIMBAL, RATE-STABILIZED** | 0.01981 → 0.04536 → **0.41625** (2.3×, **9.2×**) | **(−0.210, −0.205]** | yes |

⚠ **AND THE SENSITIVITY IS STATED, NOT HIDDEN.** Under the discarded `> 0.20` line the middle rung
becomes (−0.165, −0.160] and the headline fraction reads 45 %; under the largest-step rule and under
`> 0.15` it reads **42 %**. ⇒ quote **≈40–45 %**, and note that **the ORDER of the three rungs and the
SIGN of the effect are threshold-FREE** — no line anywhere in the printed range reorders them.

⚠ **TWO OF THE THREE RUNGS NEED NO PATCH AT ALL, which is what makes the third credible**, and both
shipped rungs REPRODUCE slice 34's own brackets ((−0.27, −0.24] and (−0.18, −0.16], measured on slice
34's wires) — a validation, stated rather than assumed. ⚠ **A LADDER QUOTED ACROSS TWO GRIDS IS NOT A
LADDER** (the advisor's catch, applied to my own first fix): slice 34's numbers are NOT borrowed, they
are re-flown here — [[ewsim-fin-dynamics-direction]]'s *re-run the comparison that entitled an earlier
slice to its finding before borrowing it*, slice 36 gate 2.

⭐⭐ **THE HEADLINE ARITHMETIC**, on bracket MIDPOINTS. Slice 34's gimbal bought 0.2625 → 0.1675 =
**0.095** of margin. Rate-stabilizing **GIVES BACK 0.040 — ≈42 % of it** (45 % under the discarded
threshold; ⇒ quote **≈40–45 %**) — and lands BETWEEN the strapdown and the position-servoed gimbal.
**THE CLASSICAL REASON GIMBALS EXIST INVERTS ON THIS WIRE.**

⚠ **AND THE MIDDLE OF THE CAUSAL CHAIN IS NOT YET MEASURED** (advisor). §II.5 has the INDEX gain
(closed form, 3–4 digits, unity exactly) and §II.6 has the BRACKET; the step from *"the filter is
worth 12–16 % of gain and ~30° of phase"* to *"that is what moves the bracket 0.040"* is an
INFERENCE, and the plan says so rather than writing one causal chain. **GATE 1 CLOSES IT:** sweep τ
on BOTH heads and check the bracket walks with τ on the shipped head in the direction the filter
predicts, and **does NOT walk on the stabilized one** (whose index gain is τ-independent at unity).
That is a prediction the mechanism makes and the alternatives do not.

> ⚠⚠ **THE SECOND HALF OF THAT PREDICTION IS WRONG AND GATE 1 (§II.11) REPLACED IT WITH SOMETHING
> STRONGER.** The stabilized bracket walks MORE (0.055 against 0.030) and **in the OPPOSITE
> DIRECTION**, so the right statement is about the GAP: it closes monotonely as τ → 0 (0.095 →
> 0.010, 9.5×), because the frame stops mattering exactly where the filter stops existing. ⭐ AND
> **THE 0.040 ABOVE IS A τ = 0.05 STATEMENT** — one point on that curve — so *"≈40–45 % of what the
> gimbal bought"* is true AT THE SHIPPED TIME CONSTANT and must be written with it.

---

## §II.7 ⭐⭐ THE TRADE (P5c) — SLICE 35's TWO-SIDED KNOB DISSOLVES, and that is the payload

**R̂ = −0.03, slice 28's boresight characterization (the disease):**

| servo | SHIP rms r | SHIP off | SHIP dem | STAB rms r | STAB off | STAB dem |
|---|---|---|---|---|---|---|
| 60 °/s | 0.88469 | 5.915 | 38.33 | 1.09405 | 4.583 | 13.10 |
| 25 °/s | 0.70495 | 9.524 | 128.65 | 1.09409 | 4.584 | 13.10 |
| 8 °/s | 0.38591 | 12.828 | 143.07 | 1.10480 | 3.861 | 29.26 |

⭐⭐ The shipped head walks **0.885 → 0.386 in ring (2.29×) while its window requirement GROWS 5.915 →
12.828 (2.17×)** — slice 35's trade, reproduced to its own published shape. The stabilized head is
**FLAT IN BOTH**: ring 1.094 → 1.105 (**1.01×**), window 4.583 → 3.861. ⇒ **THE SERVO KNOB GOES
INERT. Slice 35's knob had NO FREE DIRECTION; this head has NO DIRECTION AT ALL** — you are stuck
with the ring you have, and the window is cheap and constant.

**R̂ = −0.33, slice 30's aim point `radome_slope_worst` (the cure):** both heads quiet (0.05775 vs
0.05897 at 8 °/s), both flat, both cheap (off 1.598 vs 1.561; dem 1.57 vs 2.01).
⭐ **SLICE 30's RULE PAYS A FOURTH TIME** (33 = FOV, 34 = detector window, 35 = servo bandwidth,
**37 = the head's REFERENCE FRAME**): at the aim point the ARCHITECTURE DOES NOT MATTER.

---

## §II.8 ISOLATION FROM THE CAGE, AND THE 30° CAVEAT (P4d)

`head_max` (body-relative travel) against the 30° stop, worst anywhere in the ladder: **23.614°
(shipped) / 23.332° (stabilized)** at R̂ = −0.03. ⇒ **THE STOP NEVER BINDS — NO CAGE** (slice 36's
gate 0 established caging as a SEPARATE mechanism with its own verdict, so a cage here would be an
attribution error), and the small-angle bend keeps its headroom. ⚠ Counter-intuitively the stabilized
head's travel is **NOT** systematically larger: on the ringing arms the shipped head rings less but
LAGS more, and the two effects trade. **Do not assume the stabilized head swings further — measure it.**

---

## §II.9 What gate 1 owed

* **RUNG** `:seeker_head = (:body_referenced, :rate_stabilized)` (name TBD at gate 1) on the HELD
  `:airframe: six_dof` + `gimbal_tau_s` host — INERT without a head, refused without `two_angle`.
  ⚠⚠ **GATE IT ON THE LIVE `:airframe`, NEVER ON `haskey(:head_i_az)`** — this is the seam whose
  latent-bug class has fired SEVEN times on exactly this question (21's `_atm_on`, 23, 26, 27, 29, 32,
  34). The new inertial state is minted and never deleted, so a key-gated rung would keep an
  inertially-referenced head slewing against a FROZEN attitude after a cross-toggle off `:six_dof`,
  and — worse than the earlier occurrences — a frozen attitude makes the body↔inertial conversion the
  identity, so the two rungs would silently BECOME each other rather than visibly break. The loader
  must also refuse the rung without `gimbal_tau_s` (there is no head to stabilize), the slice-21
  "refused rather than silently branch-ordered" precedent.
* **Class 4a**, 12th consecutive RNG-live: NO new `randn`; the draw count is identical on both rungs.
  ⚠ Gyro NOISE stays determinism-blocked (an unconditional third draw desyncs 25–31 — the slice-13
  `:scan` 4b shape); it is NOT this slice.
* ⚠ **Implementation note carried from the probe:** clamp the stop by a body round-trip **only when
  `head_clamp` actually clamps**. The probe round-tripped every in-window tick (a no-op to ~1e−16),
  which is fine for a probe and wrong for a shipped seam.
* **Two-run discipline** — every arm quoted in this gate has `out% = 0.00`. A windowed arm's `rms r`,
  `head_angle_deg`, `head_rate_sat` and (slice 36) the LOS excursion all read plausibly wrong.
* ⚠ The MISS is NOT the metric (every arm hits; the stabilized head often misses LESS while ringing
  MORE — 9.979 → 3.838 at R̂ = −0.03/40 °/s — because its window requirement is smaller).

---
---

# GATE 1 AS BUILT (2026-08-17) — the pure kernels, and the causal chain closed

**Status: gate 1 COMPLETE and green. Suite 7222 → 7323 (+101 asserts, all in `test_frames.jl`); every
prior assert unmoved, so slices 1–36 are byte-identical.** Raw measurements:
`M:\claud_projects\temp\slice37g1\g1_results.md` (`g1a_tau_shipped.jl`, `g1b_tau_both.jl`,
`g1c_frozen.jl`). Probe patch re-applied for G1b/G1c calling **the shipped gate-1 kernels**, and
**REVERTED** — `git diff --stat` shows no `missile.jl`.

## §II.10 What shipped: TWO kernels, and why it is two and not one

`frames.jl` gains a slice-37 section and three names, exported:

* **`SEEKER_HEAD_MODES = (:body_referenced, :space_stabilized)`** — the rung's tuple, defined ONCE
  here and referenced by `LIVE_FIDELITY_MODES` at gate 2 (convention 7). ⚠ **NAMED
  `:space_stabilized`, NOT `:rate_stabilized`** (§II.9 left the name open): the classical term names
  the loop's SENSOR, and §II.0 measured that this project's seeker has reported an INERTIAL LOS RATE
  since slice 25 — so `:rate_stabilized` would assert the one thing already true. What moves is
  WHERE THE POINTING IS HELD. `:rate_stabilized ∉ SEEKER_HEAD_MODES` is asserted, so the refutation
  cannot be quietly undone by a later rename.
* **`head_clamp_inertial(az, el, att, stop) -> (az_i, el_i, az_b, el_b)`** — the airframe's BODY
  stop applied to a head whose pointing is held in SPACE. Returns BOTH pairs, because the stop, the
  glass's index and the detector window are all body-relative while the servo state is not: ONE
  conversion site, or `test_frames.jl` proves a second implementation of it and nothing about what
  flies.
* **`head_slew_inertial(head_az, head_el, tgt_az, tgt_el, att, τ, dt, stop; rate_max)`
  `-> (az_i, el_i, az_b, el_b, demand, rate_sat)`** — one tick of the space-stabilized servo:
  `head_slew_full(…, Inf)` in the INERTIAL frame, then `head_clamp_inertial`.

⭐ **IT IS TWO KERNELS FOR `head_clamp`'s OWN REASON — THE SECOND CALLER.** Slice 34 split
`head_clamp` out because the seam's HANDOVER must clamp the same way the servo does, and a
space-stabilized handover has exactly that need in the new frame. Gate 2 calls `head_clamp_inertial`
directly at handover, as slice 34's seam calls `head_clamp`.

⭐ **AND IT IS `head_slew_full` INSIDE, NOT A SECOND SERVO.** The first-order gain, the exact-landing
assignment, the radial `step > cap` limit and every convention-5/6 degenerate are the SAME CODE, so
the two rungs differ ONLY in the frame their angles live in and in where the stop is taken — which is
what makes §II.11's ladder a measurement of the FRAME rather than of two different servos. Pinned:
`demand` and `rate_sat` are `head_slew_full`'s own values on every attitude and every stop, and at
the identity attitude with a free stop the inertial pair is `===` `head_slew`'s.

⚠⚠ **THE ROUND TRIP IS CONDITIONAL, AND IT IS A CORRECTNESS REQUIREMENT RATHER THAN A SAVING**
(§II.9's implementation note, which the gate-0 probe got wrong by round-tripping every tick). The
body↔inertial round trip is exact in exact arithmetic and NOT in doubles, so an unconditional one
would inject a slow RANDOM WALK into the one piece of state whose whole thesis is that it does not
move with the body. ⭐ **The binding test is `head_clamp`'s OWN DOCUMENTED CONTRACT** — *"returns its
input UNCHANGED (bit-for-bit) when the stop does not bind"* — consumed as `===`, never a second
`hypot(az_b, el_b) > max(stop, 0)`: that restatement is a SECOND IMPLEMENTATION of the clamp's
predicate (the trap `head_slew_full` names for its own `rate_sat`), and it would also have to restate
the NaN-stop and `stop ≤ 0` degenerates instead of inheriting them.

⚠ **THE BODY PAIR PAYS ONE ROUND TRIP EVEN AT THE IDENTITY ATTITUDE (~1e−16), AND THAT IS PINNED AS A
BOUND RATHER THAN LEFT AS A SURPRISE.** It is RECOMPUTED from the inertial state every tick and never
integrated, so nothing accumulates — the asymmetry between the two returned pairs (inertial EXACT,
body approximate) is deliberate and asserted in both directions.

## ⭐⭐ §II.11 THE CAUSAL CHAIN, CLOSED — AND §II.6's PREDICTION WAS HALF WRONG

Both heads, one 0.005 grid, 25 cells each, **rate limit REMOVED** (the isolation: at a finite rate a
τ sweep confounds the servo low-pass with rate saturation, because at τ → 0 the step is the full error
every tick — `frames.jl:907-911`). `out% = 0.00` and `sat% = 0.00` on all 250 arms.

| τ (s) | body-referenced | step | space-stabilized | step | **gap** |
|---|---|---|---|---|---|
| 0.200 | (−0.145, −0.140] | 1.82× | (−0.240, −0.235] | 5.21× | **0.0950** |
| 0.100 | (−0.165, −0.160] | 2.52× | (−0.230, −0.225] | 6.93× | 0.0650 |
| 0.050 | (−0.170, −0.165] | 4.42× | (−0.210, −0.205] | 9.22× | **0.0400** |
| 0.020 | (−0.175, −0.170] | 6.72× | (−0.190, −0.185] | 9.91× | 0.0150 |
| 0.010 | (−0.175, −0.170] | 11.23× | (−0.185, −0.180] | 12.26× | **0.0100** |

⚠ **THE BRACKET RULE IS §II.6's, UNCHANGED AND THRESHOLD-FREE** (the largest single-step ratio), and
⭐ **τ = 0.05 REPRODUCES BOTH OF §II.6's BRACKETS WITH THE RATE LIMIT REMOVED** — so the isolation
does not move the numbers it isolates, and the two measurements are the same measurement.

⭐⭐ **THE GAP *IS* THE FILTER: IT CLOSES MONOTONELY AS τ → 0, 0.095 → 0.010, A 9.5× COLLAPSE.** The
frame stops mattering exactly where the filter stops existing. That is §II.5's index gain measured
through to the bracket instead of inferred, and it is the prediction §II.6 asked gate 1 for.

⭐⭐ **ONE KNOB, TWO SIGNS — AND THAT IS THE PART NO CONFOUND CAN PRODUCE.** More lag HELPS the
body-referenced head (its lag low-passes body motion out of the glass's index) and HURTS the
stabilized one (whose index gain is unity at every τ, so the lag only slows its tracking of the bent
measurement and weakens slice 34's fixed-point cancellation). Both heads carry the fixed-point
weakening; only one carries the filter — which is why subtracting them isolates it. Slice 28's rule
(*a confound cannot produce a non-monotone response to a monotone change*) in a new quantity: here it
is opposite SIGNS from one knob.

⚠⚠ **SO §II.6's WORDING — "does NOT walk on the stabilized one" — IS REFUTED, AND THE ADVISOR'S
PRE-MEASUREMENT WARNING IS WHY IT WAS NOT ASSERTED THAT WAY.** The stabilized head's INDEX gain is
τ-independent at unity, but its POINTING still tracks the bent measurement through the same `dt/τ`
gain, so slice 34's fixed-point path survives with a τ in it. Demanding "flat" would have made a real
0.055 walk read as a bug in the new branch.

> ⚠⚠ **THE FIRST DRAFT OF THIS SECTION CLAIMED A FLOOR AND THERE ISN'T ONE — SEE §II.15.** It read
> *"the gap does not reach zero (0.010 at τ = 0.01), and that floor was independently located"* off
> the BOTTOM CELL of the τ range flown, and attributed it to §II.4's one-tick term by comparing a
> SLOPE (6.259e−4 rad) to an ANGLE (0.010 in R̂). Extended to τ = 0.001 the gap is **EXACTLY 0.0000
> for every τ ≤ 0.005** — all three heads on one bracket. The collapse is TOTAL, which is a stronger
> result than the floor was, and the attribution was an inference dressed as a measurement.

⚠ **THE CO-VANISHING IS AN ORDERING, NOT AN IDENTITY** (slice 26's rule, not slice 21/22's): the
first-order attenuation `1 − 1/√(1+(2πfτ)²)` at the ring's 1.9 Hz runs 0.614 / 0.358 / 0.141 / 0.027
/ 0.007 across the same τ grid against a gap-above-floor of 0.085 / 0.055 / 0.030 / 0.005 / 0.000 —
monotone together and NOT proportional. Do not write it as an exact factorization.

## ⭐ §II.12 THE FROZEN HEAD IN BOTH FRAMES — the mechanism PINNED, not trended

Slice 34 §0.4 did not infer its mechanism from a trend: it FROZE the head (τ = 1e9) and measured that
a head frozen IN THE BODY makes a CONSTANT bend — nothing for `dε/dt` to differentiate — so it is
quiet at every R̂. A head frozen IN SPACE has a body-relative index that KEEPS MOVING at unity gain,
so the same degenerate must land on the OPPOSITE side. ⚠ Window FREE on both arms (a frozen head's
tracking error runs to ~33°; at the wire's 25° window both would break and read quiet for slice 33's
reason — the two-run discipline applied BEFORE the measurement).

| R̂ = −0.03, τ = 1e9 | `rms r` | `off_max` ° | `head_max` ° |
|---|---|---|---|
| body-referenced (frozen in BODY ⇒ frozen INDEX) | **0.01472** | 33.079 | 18.117 |
| **space-stabilized (frozen in SPACE ⇒ index still moves)** | **0.52112** | 11.951 | 28.002 |
| strapdown control | 1.07211 | — | — |

⭐⭐ **35.4× AT THE BORESIGHT DESIGN — and the frozen body arm reproduces slice 34's OWN 0.01472 and
1.07211 TO FIVE DECIMALS**, which validates this whole harness against a shipped number rather than
against itself.

⚠ The contrast appears ONLY at −0.03: at −0.12 / −0.18 / −0.33 both freezes are quiet, because a
frozen-in-space head is its own plant with its own bracket somewhere in (−0.12, −0.03).

⚠⚠ **TWO HONEST CAVEATS ON THESE REDUCTIO ARMS.** (1) The frozen SPACE head is a **BETTER** tracker,
not a worse one — `off_max` 11.95° against 33.08° — because holding a direction in space keeps it near
the LOS while holding one in the body does not. Slice 34's *"it has stopped being a gimbal and become
a staring seeker whose window is the whole lead"* does NOT transfer to this frame. (2) **`head_max`
reaches 30.000° at R̂ = −0.33 — THE 30° STOP BINDS, the first arm anywhere in slices 34–37 to do so.**
§II.8's *"the stop never binds"* is a statement about the LADDER arms and does not extend here.

## §II.13 A STALE PROOF CORRECTED IN TWO SHIPPED FILES (and it is not this slice's finding)

`frames.jl:856-859` and `EWSim.jl`'s slice-34 block both carried slice 34's **gate-0** reason for τ
being AUTHORED: *"τ does not move the stability onset anywhere in `[0.02, 0.2]`; only the amplitude
sags."* ⚠ **Slice 34's OWN GATE 2 (§2.3) had already overturned that** — *"its ladder skipped −0.17
and −0.16, which is exactly where the bracket is… τ is a CONFOUNDED LEVER"* — and the correction never
reached the docstrings. Both now carry the confounded-lever reading and gate 1's own ladder. **The
conclusion is unchanged (τ stays authored) and the corrected reason is STRONGER**: a lever that moves
the verdict on every arm without moving the mechanism is a worse slider than a dead one.
⇒ [[ewsim-fin-dynamics-direction]]'s *re-run the comparison that entitled an earlier slice to its
finding before borrowing it* — pointed at a docstring rather than at a claim, and the reason to run
G1a FIRST was that it could have refuted this slice's title for the price of one sweep.

## §II.14 WHAT GATE 2 OWES (§II.9's list, updated by what gate 1 measured)

* The **rung** `:seeker_head` (`SEEKER_HEAD_MODES`) on the HELD `:airframe: six_dof` + `gimbal_tau_s`
  host. ⚠⚠ **GATE IT ON THE LIVE `:airframe`, NEVER ON `haskey(:head_i_az)`** — the latent-bug class
  that has fired SEVEN times on exactly this question (21's `_atm_on`, 23, 26, 27, 29, 32, 34), and
  here it is WORSE than the earlier occurrences: a frozen attitude makes the body↔inertial conversion
  the IDENTITY, so the two rungs would silently BECOME each other rather than visibly break. Refuse
  the rung without `gimbal_tau_s` at load (there is no head to stabilize) — slice 21's "refused rather
  than silently branch-ordered".
* The **HANDOVER** calls `head_clamp_inertial(az_tru, el_tru, att, stop)`, and the **servo target** is
  the measured INERTIAL angles `(az_m, el_m)` — no attitude at all, which is §II.4's residual's whole
  origin. ⚠ Bit-identity for `:body_referenced` must be BY CONSTRUCTION (a branch whose else-arm is
  slice 34/35's lines TEXTUALLY UNCHANGED), never a `ω_ref = 0` trusted to cancel.
* ⚠ **THE `HOLD` BRANCH IS PHYSICS AND NOT HOUSEKEEPING, and the probe already had to decide it.**
  When the target leaves the detector window a body-referenced head HOLDS ITS BODY ANGLE; a
  space-stabilized head holds its INERTIAL angle, so its body angle KEEPS MOVING (and its stop can
  still bind). No arm quoted at gate 0 or gate 1 reaches that branch (`out% = 0.00` everywhere), so
  gate 2 must either exercise it or say it is unexercised — slice 34's gate-2 advisor catch on
  `fov_rad` is the precedent for what an unreached branch costs.
* **Class 4a**, 12th consecutive RNG-live: NO new `randn`, draw count identical on both rungs.
  ⚠ Gyro NOISE stays determinism-blocked (an unconditional third draw desyncs 25–31 — the slice-13
  `:scan` 4b shape); it is NOT this slice.
* **Telemetry**: the head's body pair already ships (`head_angle_deg`, `head_off_deg`), and
  `head_rate_dps` / `head_rate_sat` keep their slice-35 meaning IN THE SERVO'S OWN FRAME — which is
  the point of the rung and must be SAID, not assumed, because the same key name now measures a
  different frame's demand on each rung.
* **Two-run discipline** — every arm quoted must have `out% = 0.00`. A windowed arm's `rms r`,
  `head_angle_deg`, `head_rate_sat` and (slice 36) the LOS excursion all read plausibly wrong.
* ⚠ The MISS is NOT the metric (see above) — and gate 1 adds a second reason not to reach for it: on
  the frozen reductio arms the two heads' misses are 0.160 and 0.169 m while `rms r` parts by 35.4×.

---

## ⚠⚠ §II.15 GATE-1 POST-REVIEW (advisor) — THREE CATCHES, AND ONE OF THEM KILLED A CLAIM

The first pass of §II.10–§II.14 was committed and then reviewed. Three findings, re-flown as **G1d**
(`g1d_extended.jl`): ONE grid of 29 cells (−0.140 … −0.280), **FOUR** heads, τ over **eight** values
from 0.200 down to 0.001, `rate_max = Inf`, 696 arms + 29 strapdown. `out% = sat% = 0.00` on every
one.

### ⭐⭐ CATCH 1 (the one that killed a claim) — THERE IS NO FLOOR, AND THE COLLAPSE IS TOTAL

The gap was quoted as bottoming at 0.010 — **which was the last cell of the τ range I chose to fly**,
while §II.3 had already run the shipped head to τ = 0.001. Extended:

| τ (s) | body mid | stab mid | fresh mid | **gap (stab − body)** | gap (stab − fresh) |
|---|---|---|---|---|---|
| 0.200 | −0.1425 | −0.2375 | −0.1425 | **0.0950** | 0.0950 |
| 0.100 | −0.1625 | −0.2275 | −0.1625 | 0.0650 | 0.0650 |
| 0.050 | −0.1675 | −0.2075 | −0.1675 | **0.0400** | 0.0400 |
| 0.020 | −0.1725 | −0.1875 | −0.1725 | 0.0150 | 0.0150 |
| 0.010 | −0.1725 | −0.1825 | −0.1775 | 0.0100 | 0.0050 |
| 0.005 | −0.1775 | −0.1775 | −0.1775 | **0.0000** | 0.0000 |
| 0.002 | −0.1775 | −0.1775 | −0.1775 | **0.0000** | 0.0000 |
| 0.001 | −0.1775 | −0.1775 | −0.1775 | **0.0000** | 0.0000 |

⇒ **THE GAP GOES TO EXACTLY ZERO AND STAYS THERE: all three heads land on the SAME bracket
(−0.180, −0.175] for every τ ≤ 0.005.** The frame stops mattering ENTIRELY where the filter stops
existing — a *complete* collapse, which is a stronger statement than the floor I wrote and had less
evidence for. ⚠ **AND THE ATTRIBUTION WAS AN INFERENCE DRESSED AS A MEASUREMENT** — comparing §II.4's
6.259e−4 **rad** slope residual to a 0.010 **dimensionless** R̂ gap and calling both being nonzero
"the same floor". Exactly the defect the advisor had already made this plan strip out of §II.6's
causal chain, reappearing in the sentence meant to close it.

⭐ **AND THE DISCRIMINATOR THAT SETTLED IT IS §II.4's OWN FRESH-ATTITUDE HEAD, FLOWN RATHER THAN
CITED**: a body-referenced head whose target is re-expressed in the CURRENT attitude, so it differs
from the shipped seam by EXACTLY one tick of attitude and from the stabilized head by ONLY the frame
the lag is applied in. Its bracket matches the shipped head's at every τ but one (τ = 0.010, one
cell) ⇒ **the one-tick attitude term is worth ≤ 0.005 of residual anywhere and 0.000 in the limit** —
slice 34's §0.5 finding (*a one-tick delay is worth nothing*) reproduced in a new quantity.

⭐⭐ **THE TWO QUANTITIES ANSWER τ → 0 DIFFERENTLY, AND THAT IS THE THING TO CARRY FORWARD:** in
POSITION the heads never collapse against the shipped seam (`max|Δpos|` plateaus at 42.572 m, §II.4);
in STABILITY they collapse completely. **A 42 m trajectory difference that is worth nothing to the
loop.** Both shipped files now say so.

⚠ **AND THE HEADLINE FRACTION IS A τ = 0.05 STATEMENT TWICE OVER**, because BOTH terms move with τ.
On one grid: strapdown −0.2625 throughout, so the gimbal buys 0.1200 / 0.1000 / **0.0950** / 0.0900 /
0.0900 / 0.0850 at τ = 0.2 … 0.005, and stabilizing gives back **79.2 % / 65.0 % / 42.1 % / 16.7 % /
11.1 % / 0.0 %** of it. ⇒ *"≈40–45 % of what the gimbal bought"* is true AT τ = 0.05 and the honest
range is **0 % to 79 %**.

### CATCH 2 — `head_max` WAS NEVER RECORDED, SO "NO CAGE" WAS UNESTABLISHED FOR THE LADDER

§II.8's *"the stop never binds — no cage"* rested on gate 0's P4d, measured at ONE τ over a different
R̂ region — while G1b flew τ up to 0.2, and G1c gave direct evidence the space head travels FURTHER as
the servo slows (28.0–30.0° frozen, and it **hit** the 30° stop at R̂ = −0.33). A clamping cell would
not be a reference-frame measurement at all: slice 36's gate 0 established caging as a SEPARATE
mechanism with its own verdict. Worst `head_max` over each 29-cell ladder, against the 30° stop:

| τ (s) | 0.200 | 0.100 | 0.050 | 0.020 | 0.010 | 0.005 | 0.002 | 0.001 |
|---|---|---|---|---|---|---|---|---|
| body | 19.858 | **21.691** | 21.558 | 21.019 | 20.701 | 20.471 | 20.343 | 20.247 |
| stab | 21.108 | 20.335 | 19.803 | 19.944 | 20.003 | 20.109 | 20.166 | 20.166 |
| fresh | 19.744 | 21.675 | 21.509 | 20.942 | 20.621 | 20.384 | 20.245 | 20.166 |

⇒ **THE WORST CELL ANYWHERE IN 696 ARMS IS 21.691°, AND IT IS THE BODY-REFERENCED HEAD.** No cage
anywhere on the ladder, with ~8° of headroom. ⭐ And §II.8's *"do not assume the stabilized head
swings further — measure it"* is vindicated a second time: on the LADDER it is the SMALLER of the two
at six of eight time constants.

### CATCH 3 — THE 0.095 ARITHMETIC HAD SPLICED TWO GRIDS, WHICH IS §II.6's OWN PROHIBITION

G1b's grid stopped at −0.260 and therefore could NOT produce the strapdown bracket (−0.265, −0.260];
that number was still gate 0's P6, flown at rate 40. §II.6's own rule is *"A LADDER QUOTED ACROSS TWO
GRIDS IS NOT A LADDER"* — written about slice 34's numbers and then violated on this slice's own.
G1d's grid reaches −0.280 and re-flies the strapdown arm on it: **(−0.265, −0.260], mid −0.2625,
step 4.46×**, reproducing P6 exactly. ⇒ the three-rung ladder and every fraction above are now ONE
grid, one band, one metric, one rate.


---
---

# GATE 2 AS BUILT (2026-08-17) — the rung wired, and a finding that inverts a servo intuition

**Status: gate 2 COMPLETE and green. Suite 7323 → 7396 (+73 asserts, all in `test_missile.jl`); every
prior assert unmoved, so slices 1–36 are byte-identical.** Raw measurements:
`M:\claud_projects\temp\slice37g2\` (`lib37g2.jl`, `g2a_ladder.jl`, `g2b_seam.jl`, `g2c_hold.jl`,
`g2d_pins.jl`, `g2e_sat.jl`). **NO PATCH ANYWHERE** — every arm here flies the shipped seam, which is
itself the gate's first result.

## ⭐⭐ §II.16 THE BLOCKING CHECK, RUN BEFORE ANY TOOTH (advisor): DOES THE SHIPPED RUNG REPRODUCE GATE 1?

Gate 0 and gate 1 both flew a PATCHED kernel behind a `:probe_head` comp key. The wiring is only
proven if the shipped rung reproduces gate 1's published ladder with that patch reverted — and it
could have refuted the wiring for the price of one sweep, which is why it ran first (§II.13's own
reason for running G1a first, applied to this gate).

| τ (s) | body-referenced | space-stabilized | gap | G1d's gap |
|---|---|---|---|---|
| 0.050 | (−0.170, −0.165] step 4.42× | (−0.210, −0.205] step 9.22× | **0.0400** | 0.0400 |
| 0.010 | (−0.175, −0.170] step 11.23× | (−0.185, −0.180] step 12.26× | 0.0100 | 0.0100 |
| 0.005 | (−0.180, −0.175] | (−0.180, −0.175] | **0.0000** | 0.0000 |
| 0.002 | (−0.180, −0.175] | (−0.180, −0.175] | **0.0000** | 0.0000 |

⇒ **EVERY BRACKET, EVERY STEP RATIO AND EVERY `head_max` COLUMN REPRODUCES G1d CELL FOR CELL**
(21.558 / 19.803 at τ = 0.05, 20.343 / 20.166 at 0.002 — the same four digits). The patched probe and
the shipped seam are the same physics, and gate 1's whole ladder now rests on flying code.

⭐ **AND THE LADDER SURVIVES THE SHIPPED RATE LIMIT.** Gate 1 removed it for the isolation (at a
finite rate a τ sweep confounds the servo low-pass with rate saturation). Re-flown at slice 35's
40 °/s: body **(−0.170, −0.165]** step 4.34×, space **(−0.210, −0.205]** step 9.18× — the same two
brackets. ⇒ the isolation does not move the number it isolates, and the four cells that ARE those
brackets ship as teeth (0.03992 → 0.17308 and 0.04536 → 0.41625, with the body head QUIET at
0.01392 / 0.01495 across the space head's own bracket).

## §II.17 WHAT SHIPPED AT THE SEAM — six decisions, and the two that were advisor-corrected

* **The rung gate is `_stab = _gim && fidelity[:seeker_head] === :space_stabilized`** — the live
  `:airframe` through `_gim`, NEVER `haskey(c, :head_i_az)`. Pinned by a cross-toggle arm: while
  `:airframe` is off `:six_dof` the head's pointing, its stamp AND its inertial state are unchanged
  on all 999 ticks, on BOTH rungs, and the two rungs are still 13 m apart after the round trip.
* **The handover calls `head_clamp_inertial(az_tru, el_tru, att, stop)`** — `head_clamp_inertial`'s
  SECOND CALLER, which is the reason gate 1 split it out (slice 34 split `head_clamp` for exactly
  this need). ⭐ MEASURED: the head is born on the truth LOS on both rungs — tracking error `0.0`
  EXACTLY (body) and 3.3e−15° (space, one frame round trip), body pairs agreeing to ~6e−17 rad ⇒
  **the rungs are not two births, they are ONE birth held in two frames.**
* ⚠⚠ **`gimbal_handover_err_deg` IS REFUSED BESIDE `:space_stabilized` AT LOAD (advisor), AND IT IS
  THE FALSE-CLAIM CLASS RATHER THAN HYGIENE.** Slice 36's basket, its V and its sign convention are
  all stated in the BODY frame ("ALONG the body-frame LOS excursion"); an INERTIAL-azimuth offset is
  a different physical birth, so shipping it would be a measured slice's name on an unmeasured
  quantity. ⚠ The load refusal is COMPLETE COVER even though the rung is live-settable — the
  handover is consumed once, at tick 1, so no mid-run toggle can reach that branch.
* **The servo target is stored in BOTH frames, unconditionally under `_gim`**: the body pair
  (slice 34's line, TEXTUALLY UNBRANCHED — which is the form its byte-identity claim takes) and the
  inertial pair, which is FREE (it IS the measurement, no attitude in it at all — §II.4's residual's
  whole origin). ⚠ The alternative — each rung storing only its own frame — makes the first tick
  after a toggle-back consume a target stale by however long the other rung ran, a wrong NUMBER
  rather than a bookkeeping cost. Measured: the two differ by 0.264° at tick 1, so this is two
  quantities and not one told twice.
* ⭐ **THE INERTIAL STATE IS MINTED AT THE RUNG BOUNDARY AND ONLY THERE, AND THE CURRENCY TEST IS A
  STAMP, NOT `haskey`** (advisor: *derive at the toggle, not every tick* — the first design kept the
  inertial pair live on both rungs every tick, which adds a write to the body rung's path and is
  exactly how "byte-identical BY CONSTRUCTION" quietly becomes "by measurement"). `:head_i_az` is
  minted and never deleted, so after a body stint it is PRESENT and STALE; `:head_frame` records
  which frame the pointing was last held in — provenance, not a second copy of the state.
  ⚠ THE COUNTERFACTUAL IS MEASURED, which is what gives the tooth content: on a
  body→space→body→space script the stale key is **2.696°** from the fresh mint while the head's own
  body angle steps **0.0039°** across that tick — a **~700×** discriminator, so a `haskey` mint would
  be a visible jump and not a rounding difference.
* **Telemetry: no new key, and one comment that had to be written into the seam** (§II.14's item).
  `head_rate_dps` keeps its slice-35 name and now measures the demand IN THE SERVO'S OWN FRAME,
  which CHANGES WITH THE RUNG — so a client comparing it across a button press is comparing two
  frames' demands. Said at the telemetry line, because the key name does not change and nothing on
  the wire would otherwise say so.

## ⭐⭐ §II.18 GATE 2's OWN FINDING — THE HEAD THAT RINGS HARDER DEMANDS LESS

The sharp pair at slice 34's own design (R̂ = −0.18, body **0.01172** quiet against space **1.00097**
ringing, 85×, both HITTING at 0.16 / 0.34 m) cannot support a DEMAND claim, because one arm rings and
the other does not — and the space arm's demand is the LARGER there (11.6 against 0.30 °/s), which is
the reading a careless gate would have shipped backwards. At a MATCHED ring state it inverts:

| R̂ (both rungs ringing) | `rms r` body / space | `dem_max` body / space | `sat_band` body / space |
|---|---|---|---|
| −0.140 | 0.644 / **1.093** | 63.1 / **18.4** °/s | **17.44 %** / **0.00 %** |
| −0.150 | 0.557 / 1.085 | 59.6 / 18.3 | 10.48 % / 0.00 % |
| −0.160 | 0.354 / 1.065 | 54.9 / 17.9 | 4.02 % / 0.00 % |

⭐ **THE SPACE-STABILIZED HEAD RINGS 1.7× HARDER AND ASKS ITS SERVO FOR 3.4× LESS PEAK SLEW**, never
touching slice 35's 40 °/s limit on any cell where the body-referenced head saturates on up to 17.4 %
of band ticks. ⇒ **THE BODY-REFERENCED SERVO'S DEMAND IS ALMOST ALL BODY MOTION, NOT TARGET MOTION** —
gate 0 §II.1's `dem/wl` = 8.19× seen at the seam, on the flying wire, with the rate limit live.
⚠ AND IT DOES NOT LICENSE *"the stabilized head is the cheaper build"*: it is cheaper in SERVO
BANDWIDTH and dearer in STABILITY MARGIN (the brackets), which is slice 35's one-knob-two-bounds
shape moved onto the ARCHITECTURE.

## ⭐⭐ §II.19 THE HOLD BRANCH, FLOWN — the branch NO arm at gate 0 or gate 1 reached

§II.14 required gate 2 to either exercise it or say it is unexercised (slice 34's gate-2 advisor
catch on `fov_rad` is what an unreached branch costs), and every one of the ~950 arms behind gates 0
and 1 ran `out % = 0.00`. It is PHYSICS: a body-referenced head with no error signal holds its BODY
angle and its index FREEZES (slice 34 §0.4 — a constant bend is quiet at every R̂); a space-stabilized
one holds its INERTIAL angle, so the body angle the glass, the stop and the detector all read KEEPS
MOVING at unity gain while the missile rotates under it.

⚠ **THE WINDOW HAD TO GO TO 1° TO REACH IT** — far below any shipped wire, because the tracking error
on this cell only reaches 3.4°. These arms are a BRANCH EXERCISE and NOT a stability read; their
`rms r` is meaningless by the two-run discipline and is not quoted.

| fov | rung | held ticks | head_angle MOTION while held | span |
|---|---|---|---|---|
| 3° | body | **0** (never breaks) | — | — |
| 3° | space | 4530 | 13.83° | 13.93° |
| 1° | body | 5229 | **0.00000° EXACTLY** | 0.0000° |
| 1° | space | 5916 | **46.80°** | 28.34° |

⭐ **AND THE STOP CAN BIND WHILE THE HEAD IS HOLDING — in a way only one rung can produce.** With a
12° stop and a 2° window both arms break at the same tick and stay broken for the same 7366 ticks,
and BOTH are against the stop — but the body head is FROZEN there (bound on **100 %** of held ticks,
having been clamped before the break) while the space head is being continuously re-clamped as the
body rotates under it and is bound on **59 %**: it wanders in and out of its own stop while holding.
⚠ **ATTRIBUTION, PRECISELY (advisor's post-review wording):** these arms **ARE** caged by slice 36's
own definition — a head at `head_max == stop` is exactly that — and the claim read off them is about
**what the clamp does in each frame**, never a stability or envelope verdict, which is what slice
36's separate-mechanism finding forbids. What keeps the BRACKET cells clean of it is a different
fact: no arm on any LADDER here reaches the stop at all (worst 21.7° against 30°).

## §II.20 THE OTHER TEETH, IN ONE LIST

* **BYTE-IDENTITY, three ways**: the ABSENT fidelity vs `:body_referenced` authored BY NAME
  (`max|Δpos| === 0.0`, `head_az ===`), and the STRAPDOWN twin (no `gimbal_tau_s`) bit-identical
  across BOTH rungs — the programmatic path the loader's refusal cannot see.
* **Class 4a, 12th consecutive**: the RNG state after 4000 ticks is EQUAL on both rungs, PAIRED with
  the does-differ case (36.6 m apart by then) — a lockstep assert alone passes on a rung that does
  nothing.
* **The loader**: the rung LOADS with a head, is REFUSED without one FOR EITHER RUNG (authoring the
  default by name is exactly as dead — the slice-19 `speed` class one level up from a knob), is
  REFUSED beside the handover basket WITH THE MIRROR (the same basket loads under
  `:body_referenced`, so the refusal is about the COMBINATION), and an unknown rung is refused for
  free by `_validate_fidelity` because `SEEKER_HEAD_MODES` is REFERENCED and never re-listed
  (convention 7). `LIVE_FIDELITY_MODES.seeker_head === SEEKER_HEAD_MODES` is asserted directly.
* **The carrier set is EMPTY at gate 2** — no shipped YAML authors the rung, so slices 1–36 are
  byte-identical BY GATING; gate 3 tightens that to an enumerated set rather than deleting it
  (slice 35/36's shape).
* ⚠ **A TOLERANCE BUG CAUGHT BY A FAILING ASSERT, and it is worth its line**: the birth tooth first
  compared a DEGREE readout (`head_off_deg`, 3.3e−15) against a RADIAN-sized bound (1e−15) and
  FAILED on a correct seam. The last-bit claim belongs on the radian pair; the degree readout gets a
  degree tolerance.

## §II.21 WHAT GATE 3 OWES

* **THE WIRE.** Slice 35's `slice35_rate.yaml` geometry with **R̂ = −0.18** — slice 34's own shipped
  design, where the body-referenced head is QUIET and the space-stabilized one RINGS at 85×. ONE
  toggled fidelity (convention 9): `:seeker_head` is the BUTTON, and the R̂ slider is the domain over
  which the two brackets are walked. ⚠ The domain must be chosen so BOTH brackets are inside it
  (−0.140 … −0.280 is the measured ladder) and the verifier must READ `out == 0` on every stability
  arm it quotes.
* **THE CLIENT.** ⚠⚠ THE MARKER-HOLE RE-CHECK IS OWED (slices 34/35/36 each paid for a version of
  it): a slice-37 wire is a slice-35 wire PLUS one fidelity, so `gimbal_view` routes it and the
  SUBJECT is right — but slice 35's HUD names the SERVO's demand against its rate cap, and on the
  space-stabilized rung that demand is in a DIFFERENT FRAME and never saturates (§II.18). The failure
  mode to check for is slice 35's own: a comfortable-looking budget that credits the wrong thing.
* **THE BUTTON.** `:seeker_head` is a genuine 2-rung cycler on a wire that ALSO raises `radome_view`
  and `gimbal_view` — the one-button rule again, and the branch order must be settled before the HUD
  is written.
* ⚠ **THE MISS IS NOT THE METRIC** (every arm here hits, and the RINGING arm often misses LESS), and
  ⚠ **`head_rate_dps` MAY NOT BE COMPARED ACROSS THE BUTTON** without saying which frame each reading
  is in — §II.18 is the reason, and the seam comment is where it is said.

## ⚠⚠ §II.22 GATE-2 POST-REVIEW (advisor) — THREE CATCHES, AND ONE WAS A LIVE SEAM DEFECT

### ⭐⭐ CATCH 1 (the real one) — THE SLEW GATE WAS READING A ONE-TICK-STALE ATTITUDE

The space-stabilized branch gated its slew on the STORED body pair `c[:head_az]`, which tick k−1's
`observe!` wrote as this pointing expressed in **att(k−1)**. But `integrate!` is PHASE 1 and
`observe!` is PHASE 3, so `:att_q` in that block is already **att(k)** — and on THIS rung the head's
body angle moves with attitude even when the servo does nothing. ⇒ *"the error the detector HAD
before this tick's slew"* was being measured against the WRONG ATTITUDE, and discipline 3's two
evaluations differed by attitude TIMING as well as by the slew, which is not what discipline 3 says
they differ by. (The body rung has no such gap: a body-referenced head's stored pair is still
current, which is exactly why the defect is new here.)

⚠⚠ **AND §II.16's REPRODUCTION — THIS GATE'S STRONGEST CHECK — STRUCTURALLY COULD NOT SEE IT.** Gate
1's probe patched the same hunk and made the same choice, so cell-for-cell agreement proves
`seam == probe`, never that either is right. **A reproduction check is blind on exactly the question
the two implementations share** — and here that question was frame timing, which is this slice's
whole subject.

**THE FIX IS AN ORDERING, AND IT SIMPLIFIED THE BRANCH:** the body carries the head, and the STOP is
taken, BEFORE the detector is read — `head_clamp_inertial` moved from the `else` arm to above the
gate, and the `else` arm is gone, because *a head outside its window simply does not slew* is the
only thing it ever meant. Physically this is also the right order: the body rotating under a
space-stabilized head can drag it into its own mechanical stop with no slew involved.

⭐ **THE RE-FLIGHT IS THE INTERESTING PART — THE FIX IS BIT-INERT ON EVERY ARM THE LADDER QUOTES AND
MATERIAL EXACTLY WHERE THE BRANCH IS EXERCISED**, which is why the probe and the seam agreed in the
first place:

| re-flown | before | after |
|---|---|---|
| the 4 bracket cells + the sharp pair + the matched-ring cells | — | **unchanged to 5 decimals** (`out = 0.00` on all: the gate never fires and the stop never binds) |
| hold arm, fov 3°, space | 4711 held ticks / 13.93° / miss 789.5 m | **4530 / 13.83° / miss 953.5 m** |
| hold arm, fov 2°, space | 4503 held ticks / 26.72° / miss 145.0 m | **3001 / 17.74° / miss 1911.1 m** |
| hold arm, fov 1°, space | 5916 / 46.803° | 5916 / **46.801°** |
| the 12° / 8° / 5° stop arms | — | identical |

⇒ every number §II.16–§II.18 rests on is untouched, and the branch §II.19 flew moved by up to 13×
in miss. ⚠ **THIS IS THE THIRD PLACE ATTITUDE TIMING ENTERS THE HEAD** — §II.4 names the other two
(the target expressed in `att(k)` and consumed at k+1; the servo state's own frame) — and it was
undocumented until this review.

### CATCH 2 — A `sat == 0.0` ASSERT SITTING ON THE ONE VALUE A BROKEN ARM PRODUCES

§II.18's two CORROBORATING cells asserted `sat == 0.0` for the space rung without asserting
`out == 0.0` beside it. `head_rate_sat` reads 0 on a windowed arm for the reason the seam comment
gives (a held head is asked for nothing, so nothing saturates) ⇒ that was the one place in the
testset where the two-run discipline was asserted **in the direction that hides its own failure**.
Both cells now carry the window gate. (The primary cell at R̂ = −0.140 always did.)

### CATCH 3 — "NOT SLICE 36's CAGE" WAS THE WRONG SENTENCE

A head at `head_max == stop` **is** caged by slice 36's own definition, so §II.19's attribution
could not stand as written. The correct statement has two halves and they are about different arms:
the claim read off the 12°-stop arms is about **what the clamp does in each frame** and never a
stability or envelope verdict (which is what slice 36's separate-mechanism finding forbids); and
what keeps the BRACKET cells clean is the separate fact that no ladder arm reaches the stop at all.
⚠ In this project the attribution sentence is the thing a later slice quotes, so it is fixed in the
plan AND at the tooth.

---

# GATE 3 AS BUILT (2026-08-17) — the wire, the button that comes back, and a number that lied

**Status: gate 3 COMPLETE and green. Suite 7396 → 7496 (+100, all in `test_missile.jl`); slices 1–36
byte-identical.** Four proofs green: `slice37_verify.gd` (19 arms), `slice37_ui_test.gd` (11 teeth,
20-way value-guard), the `Sandbox.tscn` headless smoke-load (`EWSIM_SERVER_DONE`), and TWO windowed
shots. Probes in `M:\claud_projects\temp\slice37g3\`.

⚠ **THE PROOFS WERE RUN ON PORT 8770, NOT 8765** — an unrelated `python` process (PID 40916) held the
default port and it is not this project's to kill. The port is ONE integer constant, reverted in both
files after the runs; the re-run on 8765 is owed whenever that process exits. Nothing else differed.

## §II.23 THE WIRE — `scenarios/slice37_frame.yaml`

`slice35_rate.yaml` **KEY FOR KEY**, with ONE number changed and one fidelity authored, and the test
asserts that against the shipped slice-35 file rather than against literals so the two cannot drift
apart. The one number is `radome_slope_est` = **−0.18**, slice 34's own shipped design, not 26–35's
boresight default: the demonstration is a BUTTON, so the wire must open where the button DOES
something, and at the boresight BOTH rungs ring and the press moves `rms r` by 1.27× — a true number
and a dead demonstration.

⭐⭐ **ONE KNOB AND ONE BUTTON, WHICH IS WHAT CONVENTION 9 ASKS ON A WIRE WHOSE LESSON IS A RUNG.**
`:seeker_head` is the button; R̂ is the slider, and its job is to walk the SAME stability boundary
TWICE so the press is a mechanism and not a cell. The wire OPENS on `:body_referenced` — authored BY
NAME so the file states which rung it opens on — so the FIRST press is the one that breaks it.

**BOTH DOMAIN ENDPOINTS MEASURED (slice 26's post-commit rule), and they are different kinds of
boundary:**

* **FLOOR −0.33 = slice 30's aim point `radome_slope_worst` EXACTLY, and it is the floor because THAT
  IS WHERE THE BUTTON GOES DEAD** — body 0.05901 against space 0.06030, **1.022×**, both quiet.
  ⭐⭐ The rule pays a FOURTH time (33 = FOV, 34 = detector window, 35 = servo bandwidth, 37 = the
  head's REFERENCE FRAME) and the proof is a control that visibly stops working. ⚠ Deliberately NOT
  below it (slice 35's floor was −0.36, reachable and overshootable): the one-sided constraint is
  slice 30's shipped lesson and a wire about the ARCHITECTURE has no room for it.
* **CEILING −0.14 = the arm where BOTH rungs ring**, which is the ONLY kind of arm on which the DEMAND
  comparison is legal at all. ⚠⚠ **AND THE OBVIOUS JUSTIFICATION WAS TESTED AND REFUTED.** The body
  rung saturates its 40 °/s limit on up to 64.6 % of band ticks past the ceiling, so the limit might
  have been ATTENUATING its ring (slice 35's mechanism leaking into this slice's ratio). Re-flown with
  the limit REMOVED, the body arm's `rms r` moves by **at most 1.04×** anywhere — it is not. ⚠ There
  is also NO WALL past −0.14: at −0.03 the window still never binds and `head_max` is 23.614° against
  the 30° stop. What actually stops the domain is that past it the only column still moving is the
  BODY rung's SATURATION (17.5 → 64.6 %), which is slice 35's axis on a wire whose servo is authored,
  while the ring gap the slider exists to teach has settled into its tail (1.698× at −0.14 against
  1.268× at −0.03). **A refuted hypothesis and a measured replacement, not an argument.**

⚠ The servo stays AUTHORED at slice 35's 40 °/s and its disqualification is a MEASUREMENT: §II.18's
demand inversion is this slice's own finding, and putting the servo live beside this button would put
slice 35's TWO-SIDED KNOB — a third mechanism — on a wire whose subject is the reference frame.

## ⭐⭐ §II.24 THE CLIENT — THE FIRST MARKER IN THIS FAMILY WHOSE JOB IS TO **UN-DROP** THE BUTTON

**THE MARKER-HOLE RE-CHECK CAME BACK POSITIVE ON BOTH HALVES, AND THE BUTTON HALF INVERTS TWELVE
SLICES OF PRECEDENT.** Slices 26–36 each had no rung to cycle — the lesson was a slider every time —
so `radome_view`, `seeker_fov_view` and `gimbal_handover_view` all HIDE the shared button, and
32/33/34/35 rode one of them for free. `:seeker_head` IS a rung, the first on this button since slice
25, and **this wire raises `radome_view`, `gimbal_view` AND `gimbal_rate_view`** — three separate
drops. Without a marker of its own, the one slice in twelve that has something to cycle would ship
with no control at all.

⇒ `gimbal_frame_view`, checked FIRST at both client sites, and the rule written down at the marker:
**it is NOT "a gimbal marker drops the button"; it is *the button shows what there is to cycle, and
these wires mostly have nothing*.** A later slice reading only 26–36 would learn the wrong one.

⚠ **GATED ON THE FIDELITY, NOT A COMP KEY — the first marker in this family that is**, because the
rung reuses slice 34's head verbatim and there is no slice-37 comp key to gate on. ⚠ And gated on the
KEY, never value-guarded on `:space_stabilized`: the wire OPENS on `:body_referenced`, so a value
guard would hide the button on exactly the arm the showcase starts from — the one direction that is
fatal. Both rungs raise it, asserted.

**THE SECOND SITE IS LOAD-BEARING IN THE OPPOSITE DIRECTION FROM SLICE 36's.** `_fid_kind` takes a NEW
value `"seeker_head"` (free — the 3-D view keys off `_mode`, and slice 21's "only `_draw_missile`'s
gate needed this kind added" was re-checked: **none did**, exactly as for slice 24's `steering` and
slice 25's `seeker_axes`), so the label lives in its own `_update_fid_btn` arm. Without that arm the
`_:` default would print `prop: ?` on a wire with no propagation rung.

⭐ **THE MIRROR IS THE EXACT INVERSE OF SLICE 36's**: there, stripping the marker made a button APPEAR
that had to be dropped; here it makes the button VANISH. Same mechanism, opposite sign, both asserted.

**THE HUD HALF IS AN INVITED SUBTRACTION** — slice 36's own gate-3 defect in a new quantity.
`gimbal_rate_view` is raised, so without the new branch slice 35's servo block takes the wire and
pairs `head_rate_dps` against the rate cap **WITHOUT NAMING ITS FRAME**. That key means BODY-frame
demand on one rung and INERTIAL-frame demand on the other, and at the slider's ceiling the press makes
it FALL 3.15× while the ring RISES 1.70×. Every number true; the invited arithmetic — *press it, watch
the demand drop, conclude the stabilized head is the cheaper build* — is exactly what the seam forbids.
⇒ **the frame is printed INSIDE the same string as the number**, and the UI test asserts the SAME
demand renders DIFFERENTLY on the two rungs.

## ⭐⭐ §II.25 THE SHOT'S OWN FINDING — THE RING NUMBER LIED ACROSS THE PRESS

The first pair of captures rendered the branch correctly and **still could not be compared**:

| | headline | ring line |
|---|---|---|
| shot A (body, quiet) | BODY-REFERENCED — loop STABLE | `ring r −0.019 rad/s   head lag 1.91°` |
| shot B (space, ringing 84×) | SPACE-STABILIZED — RINGING | `ring r +0.021 rad/s  RINGING  head lag 1.50°` |

**−0.019 against +0.021 on two arms 84× apart.** A limit cycle crosses zero twice per cycle, so one
frame catches it wherever it happens to be — slices 26–36 all drew the live rate beside a peak-hold
tag and that was fine, **because nothing on those wires invited a frame-to-frame comparison. Here the
whole demonstration IS two frames either side of one button press.** Two live, TRUE numbers whose
comparison says the architecture did not matter: the exact inverse of the claim.

⇒ the DECAYING PEAK's **value** is now drawn beside the live rate (`_frame_ring_text`, extracted for
convention 14 — inside `_draw` it had no headless proof, which is how it shipped wrong for one
capture). Re-shot: **peak 0.02 against 1.08, ~54×**, with both live values still on the line so
nothing hides behind the instrument. ⚠ An INSTRUMENT, not physics — a peak-hold of a shipped key,
exactly slice 27's.

⚠ **AND THE SAME PAIR CAUGHT A RIGHT-EDGE OVERRUN, the 4th after 26/28/36**: the cure line shipped at
**59 characters** against the measured ~55-character budget, clearing the edge by ~10 px at 1600 px
and cut at any narrower window. Shortened to `← button goes dead`, which is also the truer phrase — at
the aim point the two rungs read 0.05901 and 0.06030, so what visibly stops working is the CONTROL.
Both lines are now pinned by width in the UI test, which is only possible because they are pure
helpers.

## §II.26 THE VERIFIER — 19 ARMS, AND THE ONSET RULE STAYS THRESHOLD-FREE

⭐ **THE LADDER IS WALKED TWICE, five rungs per servo frame on gate 2's own 0.005 grid, and the
brackets are established by the LARGEST SINGLE-STEP RATIO** — never by comparing an `rms r` to a line.
That is gate 0's advisor catch still doing work: **the body rung reads 0.17284 at R̂ = −0.165, an order
of magnitude above its own 0.012 plateau AND BELOW the arc's 0.30 ring line**, so a threshold would
have mis-bracketed it. The whole ladder is printed so a reader can redraw the line.

    BODY   −0.210:0.01518  −0.205:0.01418  −0.180:0.01195  −0.175:0.01364  −0.170:0.03999  −0.165:0.17284   → 4.32× at (−0.170, −0.165]
    SPACE  −0.210:0.04578  −0.205:0.41602  −0.180:1.00094  −0.175:1.02118  −0.170:1.04757  −0.165:1.05386   → 9.09× at (−0.210, −0.205]

⭐⭐ **AND THE TWO BRACKETS ARE ASSERTED DISJOINT FROM BOTH SIDES**, which is what makes this ONE ladder
walked twice rather than two readings of one boundary: across the SPACE bracket the body rung is still
on its plateau (0.01518 / 0.01418), and across the BODY bracket the space rung is ALREADY ringing
(1.04757 / 1.05386). Either half alone is consistent with a single shifted curve.

⚠ The RING line is used ONLY where the two sides differ by two orders of magnitude (the showcase, the
aim point). The ~40–45 % of margin given back is quoted as a RANGE; what is asserted is the ORDER of
the rungs, which is threshold-free.

**Headline pair:** at R̂ = −0.18, body **0.01195** / miss 2.084 m against space **1.00094** / miss
2.689 m — **83.8× frame** (85.4× per tick), both hitting, `out == 0` on all 19 arms.

⭐⭐ **THE MID-RUN PRESS ARM — the one path gates 0–2 could not cover**, because they toggled in Julia
and gate 3 is the first time the command a button sends reaches the rung boundary at an arbitrary tick
(gate 2's CATCH-1 territory). ⚠⚠ **IT NEEDED A TWO-LEG ARM AND THE REASON IS A SERVER FACT:
`_serve_session!` DRAINS EVERY QUEUED COMMAND BEFORE IT STEPS AT ALL**, so `[step K, set_fidelity,
step N−K]` sent back-to-back applies the toggle at tick 0 and silently measures a from-launch arm. The
first leg must be FLOWN before the press is sent. Pressed at tick 6400 the arm finishes at rms r
0.88320 against 1.00094 from launch (11.8 %), hits, and `out` stays 0.

## ⚠⚠ §II.27 A FRAME VERIFIER STRUCTURALLY CANNOT SEE THE PRESS, AND THE FRAME GRID MISREADS IT

On the emit grid the **space→body** press shows a **0.939°** step in `head_angle_deg` — ~16× a normal
frame — which reads exactly like the head being RE-BORN, the failure the seam's stamp exists to
prevent. **It is not.** Per tick the head moves **0.0074°** at the press, ~9× LESS than the tick
before. The frame figure is the SPACE rung's own body-angle motion (0.0649 °/tick — a head held
inertially is carried along by the rotating body at unity gain) accumulated over 16 ticks, ending at
the press.

⇒ **THE PRESS IS VISIBLE IN THE RATE, NOT THE POSITION, AND IT GOES THE OTHER WAY**: the carry-along
STOPS, which is the rung's own mechanism in a single tick. [[ewsim-missile-verifier-sampling]] in a
new quantity. **`slice37_verify.gd` therefore asserts NOTHING about a step across the press**, and the
continuity tooth lives in `test_missile.jl` where it can be read per tick — both directions, against
gate 2's measured 2.696° counterfactual rather than a chosen epsilon.

⚠ **AND THE TRAP IS ON THE *RETURN* PRESS, NOT THE SHOWCASE ONE — say which, because a reader would
otherwise assume the worse case sits on the press the slice actually demonstrates.** The shipped
showcase presses **body→space**, where the step is 1.06× a normal tick, i.e. continuous in the
ordinary sense and nothing to misread. The 0.939° frame step is on **space→body** — the press a
student makes when they press twice, or when they cycle back to compare. Both directions are pinned
in the core tooth; only the second one can be misread, and only from a frame.

## §II.28 THE CORE EDITS, AND THE ASSERT GATE 2 LEFT FOR THIS GATE

* **`_airframe_view_info` gains `gimbal_frame_view`** — the only core change of substance.
* ⭐ **GATE 2's OWN `@test isempty(carriers)` WAS WRITTEN TO BE TIGHTENED HERE, and it was** — now
  `carriers == ["slice37_frame.yaml"]`. The `isempty` form would have gone on passing forever while
  quietly ceasing to say anything the moment a wire was added.
* ⚠ **TWO SLICE-35 CARRIER LISTS FIRED AS FAILING ASSERTS AND WERE CORRECT TO** (the second time that
  list has earned its keep — slice 36 was the first): a slice-37 wire is slice 35's with one number
  changed, so it carries `gimbal_rate_dps` and raises `gimbal_rate_view`. Both enumerations widened.
* New testset: the wire against slice 35's file key-for-key, the fidelity, the marker + its mirror +
  its both-rungs property, convention 9, and the per-tick press continuity.


## ⚠⚠ §II.29 GATE-3 POST-REVIEW (advisor) — THE SMOKE-LOAD PROVED HALF OF WHAT IT CLAIMED

**THE BLOCKING CATCH.** The smoke-load captured the SERVER's log and asserted `EWSIM_SERVER_DONE` — the
scene connected and handshaked — but **never captured GODOT's stdout**, so the other half of the
convention's own assertion (*no `SCRIPT ERROR` / `Parse Error` / `GDScript backtrace`*) was simply
unmade. ⚠⚠ **AND THAT HALF IS THE ONE THIS GATE NEEDED**, because `Sandbox.gd` carries 271 of this
slice's new lines and its new HUD block is called **only from `_draw`, which never runs headless**: a
defect there would let the scene connect and handshake exactly as it did, `DONE` would appear, and the
smoke-load would pass green over a broken HUD.

⚠ A second, smaller gap in the same proof: the run was made while `Sandbox.gd` still carried the
temporary `PORT := 8770`, so **the shipped bytes had never been loaded at all**.

**RE-RUN, BOTH HALVES:**

* Against a live server with Godot's stdout AND stderr captured: **CLEAN** — the version banner and
  nothing else, empty stderr, `EWSIM_SERVER_DONE` reached. ⭐ And the capture channel is proven live
  rather than assumed: the UI-test run earlier in the same session printed `GDScript backtrace` lines
  through it, so an empty sweep is a negative result and not a silent one.
* The SHIPPED file (`PORT := 8765`) re-loaded through `slice37_ui_test.gd`, which `preload`s
  `Sandbox.gd` and calls every new helper: **clean, exit 0**.

⚠ **WHAT THE SMOKE-LOAD STILL DOES NOT PROVE, STATED PLAINLY**: GDScript parse errors are whole-file
and compile-time, so this covers them — but a RUNTIME fault inside `_draw_frame_hud_lines` would still
be invisible headless. **The two windowed shots are that function's only proof**, and both were retaken
AFTER the `_frame_ring_text` / `_frame_cure_text` extractions (shot A reads `(peak 0.02)` and
`← button goes dead`, which is how the retake is identifiable).

## §II.30 TWO TEXT CORRECTIONS FROM THE SAME REVIEW

* **THE MID-RUN ARM'S 25 % ENVELOPE WAS A NUMBER I CHOSE** — gate 0's own catch, in this file's one
  remaining tolerance. It is now bounded by a MEASUREMENT and the assert says so: presses at ticks
  2000 / 4000 / 6000 / 6400 give band `rms r` 1.01231 / 1.02777 / 0.95534 / 0.88320 against the
  from-launch 1.00094 — a spread of 0.883–1.028. ⚠ And the reason it is not tighter is now stated
  rather than implied: the first `PRESS_AT` ticks fly the OTHER rung, so exact agreement would be the
  surprising result.
* **§II.27's TRAP IS ON THE *RETURN* PRESS AND DID NOT SAY SO.** The shipped showcase presses
  body→space, where the step is 1.06× a normal tick; the 0.939° frame step is space→body — the press a
  student makes when they press twice or cycle back to compare. Both directions are pinned in the core
  tooth; only the second can be misread, and only from a frame.

## §II.31 WHAT REMAINS OWED

* ⚠ **Re-run `slice37_verify.gd` and the smoke-load on port 8765** once PID 40916 releases it. The
  constant is already reverted; the 8770 runs are otherwise identical.
