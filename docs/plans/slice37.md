# Slice 37 — MEMORY TRACK / RE-ACQUISITION: **KILLED AT GATE 0** (§11 Tier-A)

**Status: DEAD, NOT DEFERRED. Killed at gate 0 on 2026-08-17 in five probes, no core change shipped.**
The slice-37 slot is FREE and its candidates are listed at the bottom.

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

* **THE HEAD'S OWN GYRO** (slice 34's, unspent) — a rate-stabilized head measures inertial LOS rate
  DIRECTLY, which is the classical reason gimbals exist and a different mechanism from anything in
  26–36.
* **A SECOND-ORDER SERVO (ω_a / ζ_a)** — slice 35's own named successor; slice 15's actuator is the
  precedent for what an inertia and a bandwidth add over a lag plus a rate limit.
* **A HANDOVER BASKET WITH A DISTRIBUTION** — slice 36's own first-named successor (a covariance and a
  Pk over the basket rather than a single arm). ⚠ Note §0.1 before scoping it: the basket's two sides
  fail by different mechanisms, so a Pk over it is a mixture of two failure modes, not one.
* **THE CAGE vs THE AIM AS ITS OWN A/B**, **THE ELEVATION HALF**, **A RECTANGULAR / PER-AXIS STOP**,
  **SEEKER RANGE / SNR ACQUISITION LIMITS** — all as slice 36 left them.
