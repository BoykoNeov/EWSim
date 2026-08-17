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

## §II.9 What gate 1 owes

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

