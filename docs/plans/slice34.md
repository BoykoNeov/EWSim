# Slice 34 — THE GIMBAL: THE HEAD POINTS WHERE THE GLASS SAYS THE TARGET IS (§11 Tier-A)

The TWELFTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro, 32 = the seeker's field of view, 33 = the ring as
an FOV budget item), and the successor slices 32 AND 33 both nominated:

> *"⭐ **A REAL GIMBAL — and it now has its lesson, banked at gate 0.** … **The lesson it should
> carry: the gimbal that saves your envelope PARKS YOU ON THE WORST GLASS.** … ⚠ It REWRITES 26–31's
> `look_az` (the bend would key off head-vs-body), which is the byte-identity surface of six slices,
> so it needs a presence-gated head state with the strapdown else-arm VERBATIM."*
> — `docs/plans/slice33.md`, Deferred (NAMED)

**Status: GATE 0 COMPLETE (2026-08-09, 9 probes). Gates 1–3 PENDING. ⚠⚠ BOTH HALVES OF THE BANKED
DEFERRAL WERE REFUTED AT GATE 0 (§0.1, §0.2) and the live claim was found in a THIRD place (§0.4) —
the slice-33 shape exactly, and the refutations are load-bearing. Probe scripts in
`M:\claud_projects\temp\slice34\`.**

---

## The one-paragraph statement of the lesson

Slices 26–31 built the parasitic loop on one geometric fact: the radome bends the ray by an amount
set by the LOOK ANGLE, and the look angle is the LOS measured off the missile's own nose. That is a
quantity the missile can only move by ROTATING — which is exactly why the loop closes through the
body and why slice 26 is a body-rate instability. **A gimballed seeker breaks that identity.** Its
head has its own pointing angles, the ray passes through the part of the dome the head is AIMED at,
and — this is the whole slice — **the head is aimed by the very measurement the dome just bent.**
The index of the glass becomes a FIXED POINT of the glass: the head points where the bent
measurement says the target is, so part of the bend's own variation is absorbed by the head's
pointing instead of being handed to guidance. Slice 26's loop is partly re-closed through the HEAD,
where its sign is NEGATIVE. On the shipped glass and R̂ ladder the onset walks from `(−0.27, −0.24]`
strapdown to `(−0.18, −0.16]` gimballed — ⚠ **quoted BRACKET TO BRACKET, never as one number**
(slice 30's "sufficient, never tight" discipline: the gap those two brackets admit spans 0.06 to
0.11, so a single "≈0.08" would be asserted at gate 2 and fail) — and at `R̂ = −0.18` the SAME
glass, SAME residual, SAME seed gives **rms r 0.93194 (RINGS) strapdown vs 0.01181 (QUIET)
gimballed, 78.9×**.

> **THE LESSON, IN ONE SENTENCE.** A strapdown seeker's radome index is handed to it by the
> airframe; a gimballed seeker's is handed to it by its own last measurement — and an index that
> looks at itself is an index that fights back.

⚠ **AND IT IS NOT FREE, IN THE ONE CURRENCY A GIMBAL HAS.** The margin is bought by the head's
pointing DECOUPLING from the true LOS, and the size of that decoupling is precisely the tracking
error the head's own detector window must cover. Slice 33's single number splits in two: a STOP
(the head's travel about the body, which reproduces slice 33's excursion — **a restatement, not a
new claim**) and a DETECTOR WINDOW (about the head axis — new, and where the margin is paid for).

---

## §0 — Gate 0 (9 probes, 2026-08-09)

⚠ **METHOD.** `GimbalSeeker` is a probe-local COPY of `missile.jl::_observe_point3d!` with a head
state inserted; the core was NOT touched. Because a hand-copy can differ from the shipped seam in
ways that masquerade as physics, **P0 validates the copy before anything is claimed from it**
(convention 10, one layer stricter than usual). All arms: glass `R₀ = −0.03, A = −0.15, k = 12`
(⇒ `radome_slope_worst = −0.33`), `vy = 200`, seed 32, `dt = 1e-3`, 22 000 ticks — slice 33's wire
verbatim, so every strapdown column is checkable against `docs/plans/slice33.md`.

### ⚠⚠ §0.1 — REFUTATION 1: THE BANKED LESSON IS FALSE, AND ONE COLUMN KILLS IT (`p0_collapse.jl`)

The banked lesson was *"the gimbal that saves your envelope PARKS YOU ON THE WORST GLASS"* — a
strapdown seeker's body chases the LOS so the look angle stays near the lead, while a gimbal
deliberately HOLDS the head at the full lead, out on slice 28's steep glass. **It rests on a
contrast that does not exist.** With the head degenerate (τ → 0), the probe measures

| arm | `look_body_max` | `head_max` |
|---|---|---|
| strapdown, R̂ = −0.03 | 24.984° | — |
| gimbal τ→0, R̂ = −0.03 | 24.984° | **24.984°** |
| strapdown, R̂ = −0.33 | 18.138° | — |
| gimbal τ→0, R̂ = −0.33 | 18.138° | **18.138°** |

**The head parks nowhere the body was not already looking.** A strapdown seeker's look angle IS the
full lead — that is what slice 32 measured and named (`held ⟺ lead < fov`) and what slice 33 spent
its excursion budget on. The banked framing imagined a strapdown seeker whose nose tracks the LOS;
it does not, and cannot, because a missile points its nose along its velocity plus incidence.

### ⚠⚠ §0.2 — REFUTATION 2: THE `look_az` REWRITE COLLAPSES (the advisor's blocking check)

The deferral's stated reason for being a big slice is that it *"rewrites 26–31's `look_az` (the bend
would key off head-vs-body)"*. Measured, on RINGING glass so the bend is live and large:

**`max|Δpos| = 0` over 9 000 ticks — EXACTLY, at both R̂ = −0.03 and R̂ = −0.33.**

At zero servo lag the head angle IS the LOS-vs-body angle, so the glass sees the same index and the
bend is unchanged. This is the FALSE-FIDELITY class — slice 15's `k_δ` cancellation, slice 19's dead
`speed`, slice 31's `R̂(1+s)` reparameterization — and it means **"the bend keys off head-vs-body"
ships as a TOOTH, never as the headline.** ⭐ It doubles as the copy's validation: `GimbalSeeker`
degenerate is bit-identical to the shipped `Seeker`, so every later probe rides on a verified copy.

### §0.3 — Is the servo lag material at all? (`p1_tau.jl`, `p2_onset.jl`, `p3_split.jl`)

The failure mode to rule out next is slice 25's: seeker noise × the BTT roll loop was a ~1000:1
low-pass and shipped **DEAD, not deferred**. With a head slewing toward the TRUE LOS (`:truth`):

| τ (s) | RINGING (R̂ = −0.03) `off_max` | rms r | QUIET (R̂ = −0.33) `off_max` | rms r |
|---|---|---|---|---|
| 0.000 | 0.0000° | 1.07211 | 0.0000° | 0.05879 |
| 0.020 | 1.8285° | 0.97277 | 0.4176° | 0.05893 |
| 0.050 | 3.7680° | 0.86863 | 0.8551° | 0.05919 |
| 0.200 | 7.6777° | 0.64831 | 2.1164° | 0.06089 |
| 0.400 | 9.5767° | 0.54579 | 3.2032° | 0.06209 |

Not dead: the lag both quiets the loop and costs detector error, and the RING inflates the error
~4× over the quiet arm at matched τ. **P2 then ran slice 27's discriminator** (an OFFSET moves the
onset; a GAIN scales the whole ladder) and found the onset walking −0.27 → −0.21 as τ goes 0 → 0.2,
with the quiet rows barely moving (−0.33: 0.05879 → 0.06089) — a boundary shift, not a de-tune.
**P3 measured the price:** at R̂ = −0.24 the critical detector window grows 0.25° → 5.0° as τ goes
0 → 0.2, while `rms r` falls 0.70983 → 0.04306 and the head travel requirement RETURNS to 18.118°.

⚠ **`head_max` IS NON-MONOTONE IN τ** (20.62 → 22.29 → 23.42 → 18.12 → 18.12): a partially
suppressed ring makes the head chase MORE before the ring dies. **This is the 5th occurrence of the
non-monotone-knob pattern in this arc** (slice 19's ρ, 20's K, 22's α_stall, 28's k) and any knob
domain chosen across that peak would reverse the lesson.

### ⚠⚠ §0.4 — THE FORK, AND WHERE THE CLAIM ACTUALLY LIVES (`p4_bent.jl`, `p5_bent_onset.jl`)

§0.3's head slews toward the TRUTH LOS. **A real head cannot: it slews on its own detector's error
signal, which is the BENT, NOISY measurement — and slice 27 already made that a rule** ("compensate
with a signal that is not itself corrupted by what you are compensating"). The honest head
(`:bent`) tracks the previous tick's MEASURED LOS-in-body. Two checks, then the fork:

* **(A) It does not reverse the direction.** `:bent` is never worse than `:truth`; at R̂ = −0.24 it
  is far quieter (0.02609 vs 0.40798 at τ = 0.02), at R̂ = −0.03 the two agree within 2%.
* **(B) No delay-driven re-destabilization** out to τ = 3.2 s (a lag normally buys phase, not
  margin). `rms r` stays ≈0.04 while `off_max` grows to 13.7°.

**But the fork is real, and it decides the slice's shape:** under `:bent`, τ does NOT move the onset
anywhere in `[0.02, 0.2]` — only the amplitude sags. The full ladder:

| R̂ | strapdown | `:bent` τ=0.02 | τ=0.05 | τ=0.10 | τ=0.20 | **τ=1e9 (frozen)** |
|---|---|---|---|---|---|---|
| −0.33 | 0.05879 | 0.06037 | 0.05917 | 0.05905 | 0.05930 | 0.07895 |
| −0.27 | 0.03070 | 0.03832 | 0.03701 | 0.03691 | 0.03763 | 0.05927 |
| −0.24 | **0.70983** | 0.02609 | 0.02497 | 0.02459 | 0.02545 | 0.05017 |
| −0.18 | 0.93194 | 0.01166 | 0.01181 | 0.01162 | 0.01042 | 0.03368 |
| −0.12 | 1.03165 | **0.83567** | 0.70207 | 0.57877 | 0.42355 | 0.02101 |
| −0.03 | 1.07211 | 0.99009 | 0.88465 | 0.79182 | 0.66688 | **0.01472** |

⇒ **τ is an AUTHORED §1 PARAMETER, NOT A SLIDER** (the slice-19 dead-knob discipline applied
BEFORE the knob exists rather than after it ships). The single live slider is the detector window.

⭐⭐ **AND THE FROZEN ARM PINS THE MECHANISM RATHER THAN INFERRING IT FROM A TREND** (slice 21's
ρ-factor standard). A head frozen in the BODY frame produces a CONSTANT bend — there is nothing for
`dε/dt` to differentiate — and it is quiet at **every** R̂ including −0.03 (0.01472, a 72.8× drop
from the strapdown arm). ⚠ **It is a REDUCTIO, not a design:** its detector error runs to **33.08°**
(P6C), i.e. it has stopped being a gimbal and become a staring seeker whose window is the whole
lead. **That is what makes the trade STRUCTURAL and not incidental — the motion that holds the
track is the motion that feeds the loop.**

### ⭐⭐ §0.5 — THE ISOLATION: WHAT ACTUALLY BUYS THE MARGIN (`p7_isolation.jl`)

Under `:bent` the onset moves a full two rungs of the ladder while τ does nothing across a 10× span.
So the margin is NOT the servo lag, and two candidates remain — one of which would be a probe
artifact:

* **(i) the SELF-REFERENTIAL INDEX** — the head points where the bent measurement says the target
  is, so the bend indexes on a quantity the bend itself moved. Real physics.
* **(ii) the ONE-TICK SAMPLING DELAY** that `:bent` necessarily carries. **A 1 ms delay worth 0.08
  of radome residual would be an implementation artifact of the probe**, and shipping it as physics
  would be the false-fidelity class for the THIRD time in one gate.

**The isolation arm `:delay` carries (ii) without (i)** — the same one-tick sampling delay applied
to the TRUTH LOS:

| R̂ | strapdown | `:truth` | **`:delay`** | `:bent` |
|---|---|---|---|---|
| −0.24 | 0.70983 | 0.40798 | **0.40752** | 0.02609 |
| −0.18 | 0.93194 | 0.69538 | **0.69399** | 0.01166 |
| −0.03 | 1.07211 | 0.97277 | **0.97186** | 0.99009 |

(τ = 0.02; the pattern holds at 0.05 and 0.20.) **`:delay` reproduces `:truth` to three decimals at
every R̂ — the sampling delay contributes NOTHING — while `:bent` departs from both.** ⇒ the margin
is bought by the INDEX, and the slice has a mechanism rather than a coincidence.

### §0.6 — The bracket, at the arc's own resolution (`p6_bracket.jl`)

The shift IS the payload, so it is quoted as a MEASURED bracket, never interpolated. `:bent`,
τ = 0.05:

| R̂ | rms r | `off_max` | `head_max` | miss |
|---|---|---|---|---|
| −0.19 | 0.01215 | 1.926° | 18.117° | 0.170 m |
| −0.18 | 0.01181 | 1.956° | 18.117° | 0.187 m |
| −0.17 | 0.03934 | 3.762° | 18.117° | 3.631 m |
| −0.16 | **0.35338** | 5.237° | **20.619°** | 5.695 m |
| −0.12 | 0.70207 | 5.587° | 22.026° | 6.500 m |

⇒ onset bracket **(−0.18, −0.16]**, with −0.17 MARGINAL and not asserted; strapdown's own bracket on
this glass is **(−0.27, −0.24]** (slice 30's "last decisive ring −0.24/0.709", reproduced to the
digit). ⭐ **AND `head_max` STEPS AT THE SAME PLACE** — 18.117° through the quiet arms, 20.619° at
the first ringing one — a SECOND, INDEPENDENT tell from a different quantity, which is what makes
the bracket a measurement rather than a threshold read off the metric that defined it.

⚠ **THE MISS IS NOT THE METRIC** — every arm in every table above HITS (0.05–7.5 m). That is the
arc's standing fact since slice 26 and it is unchanged here; the verdict is always `rms r`.

### ⭐⭐ §0.7 — IS THE DETECTOR WINDOW A LIVE KNOB? (`p8_window.jl`, an advisor BLOCKING check)

⚠ Every `:bent` number in §0.4–§0.6 was measured at `fov = 1e6`. **Gate 0 had NO `:bent` arm where a
finite window BINDS**, and the plan proposes exactly that as the slice's one live slider — so it
was flown before §1 was written. `:bent`, τ = 0.05, stop 30°:

| R̂ | free `off_max` | 1.0° | 1.5° | 2.0° | 4.0° | 6.0° | critical |
|---|---|---|---|---|---|---|---|
| −0.18 (quiet) | 1.9556° | 1028.8 m | 728.2 m | **0.185 m HOLD** | HOLD | HOLD | **2.0°** |
| −0.16 (ringing) | 5.2368° | 1254.8 m | 1186.5 m | 568.9 m | 269.2 m | **5.695 m HOLD** | **6.0°** |

⭐⭐ **SLICE 32's PREDICATE RETURNS IN THE NEW CURRENCY: `held ⟺ tracking error < detector window`,**
and `⌈off_max⌉` calls the critical window exactly in both rows (2 and 6). ⚠ As in slice 32, the two
sides come from DIFFERENT CODE PATHS on DIFFERENT RUNS — the error off a FREE arm, the verdict off a
WINDOWED one — which is what makes it a measurement rather than a restatement. ⭐ **AND THE RING IS
SPENT IN DETECTOR WINDOW, 3× (2° → 6°)** — slice 33's payload, in the quantity a gimbal actually has.

⚠⚠ **THE METRIC INVERSION ARRIVES THROUGH A NEW DOOR, AND IT IS MEASURED, NOT FEARED.** The head
HOLDS when it loses its error signal, so a broken window FREEZES the index — and §0.4's frozen arm is
quiet at every R̂. Confirmed: at R̂ = −0.16, `rms r` **FALLS 0.35338 → 0.08491** while the miss OPENS
to 1254.8 m, with `off_max` running to **89.9°** (slice 33's post-lock-loss runaway signature).
⇒ **SLICE 33's TWO-RUN DISCIPLINE IS MANDATORY HERE, NOT INHERITED AS A COURTESY**: the predictor
(`off_max`, `rms r`) comes off the FREE arm, the predicted (miss, % out) off the WINDOWED one, and no
stability verdict may ever be read on a windowed arm.

### ⚠⚠ §0.8 — THE HANDOVER IS LOAD-BEARING (same probe; slice 32's P5 vindicated)

The head initialises to the truth look angles on tick 1 — a TRUTH read on a path whose whole thesis
is that the head never sees truth. Expected immaterial (one tick, then the servo converges).
**It is not.** Against a head that starts CAGED at boresight:

| R̂ | init | rms r | `off_max` | miss |
|---|---|---|---|---|
| −0.18 | handover | 0.01181 | **1.9556°** | 0.187 m |
| −0.18 | boresight | 0.01305 | **18.1172°** | 0.172 m |
| −0.16 | handover | 0.35338 | 5.2368° | 5.695 m |
| −0.16 | boresight | **0.26719** | 18.1172° | 1.883 m |

**A caged head must slew the WHOLE LEAD, so during acquisition its window requirement degenerates to
the strapdown one** (18.12° — slice 32's own number) and `off_max` over the full flight stops
measuring the tracking error at all. ⚠ **AND THE RING VERDICT IS TOUCHED**: at R̂ = −0.16 the caged
arm's 0.26719 sits on the wrong side of the 0.30 line the bracket was read against. ⇒ **the §0.6
bracket is quoted FOR THE HANDOVER INIT**, which is what ships, and gate 1 must either window
`off_max` past the acquisition transient or author the handover as a stated §1 condition. This is
precisely the deferral slice 32's P5 named ("the handover basket as an authored quantity") arriving
as a live constraint rather than a nicety.

---

## What ships (gates 1–3, PLANNED)

### The core

* `frames.jl` — the head kernels, beside `look_angles`/`boresight_angle` (measurement geometry in
  the body frame, which is exactly what a head angle is):
  * `head_slew(head_az, head_el, tgt_az, tgt_el, τ, dt, stop) -> (az, el)` — the first-order servo
    with the mechanical STOP. ⚠ `τ ≤ dt` must LAND EXACTLY by ASSIGNMENT, not by arithmetic
    (`head + (tgt − head)` is not `tgt` in IEEE doubles, and §0.2's bit-identity claim is the
    slice's own false-fidelity control — the tooth must be able to pass).
  * the detector's off-head-axis angle — the quantity the head's window is compared against. ⚠
    **CIRCULAR, like `boresight_angle` and unlike the per-axis glass**, for the same reason: a
    detector window is one window about one axis. ⚠⚠ **DO NOT SHIP A SECOND ANGLE-MAGNITUDE HELPER
    BESIDE `boresight_angle` WITHOUT FIRST TRYING TO REDEFINE ONE FROM THE OTHER** (advisor; slice
    33's gate 1 got its cleanest result exactly that way, and `boresight_angle`'s own docstring
    warns about a parallel implementation). It is `hypot` of two wrapped differences, which is
    `boresight_angle`'s shape with the head as the reference axis rather than the nose — gate 1
    decides whether that is one kernel generalized or two, and must say which and why.
* Comp keys `:head_az` / `:head_el`, PARALLEL to `:att_q` / `:omega_body` (the slice-23 precedent),
  minted by the seam and never deleted.

### The seam — three disciplines that must be WRITTEN, not discovered at gate 3

1. **PRESENCE-GATED on `:gimbal_tau_s` AND rung-gated on the LIVE `:airframe === :six_dof`**, never
   on `haskey(:head_az)` — that is the slice-21 `_atm_on` / 23 / 26 / 27 / 32 latent-bug class,
   whose SEVENTH occurrence this would be. The else-arm is slice 33 VERBATIM.
2. **THE HEAD SLEWS BEFORE THE BEND IS TAKEN.** The other ordering leaves a one-tick lag that
   SURVIVES τ → 0 and would fake a mechanism — and §0.5 measured that a one-tick lag is worth
   nothing, so a slice resting on one would be resting on noise.
3. **THE SERVO TRACKS THE BENT MEASUREMENT (`:bent`), AND THAT IS THE SLICE.** Tracking truth is
   both less realistic and a different physics (§0.4/§0.5); slice 27's rule names why. The
   `:truth` variant does NOT ship — it was measured and is recorded here.

### Telemetry (all scalars, `_finite*`, shipped ONLY under the gimbal gate — the never-stale rule)

`head_angle_deg` (travel, vs the STOP) · `head_off_deg` (the detector error, vs the WINDOW) ·
`gimbal_valid` · and slice 26's `look_angle` continues to ship the index the glass ACTUALLY used,
which under a head is the head's own angle. ⚠ **`seeker_fov_deg` / `seeker_fov_margin_deg` KEEP
THEIR SLICE-32/33 MEANING** (LOS-vs-body) and the head quantities ship ALONGSIDE — slice 28's
`radome_residual*` precedent. Redefining them would silently rewrite two slices' asserts.

### Convention 9 and the knob count

ONE live slider: **`gimbal_fov_deg`** (the detector window) — **and §0.7 measured that it BINDS
rather than assuming it** (critical 2.0° quiet / 6.0° ringing, with a sharp cliff either side, so
the domain has real range). `gimbal_tau_s` and `gimbal_stop_deg` are AUTHORED — τ because §0.4
measured it does not move the onset over any realistic band (the dead-knob discipline applied before
the knob exists), the stop because it reproduces slice 33's excursion and is therefore a
RESTATEMENT. Domain to be MEASURED at gate 1; the non-monotone `head_max` peak of §0.3 and the
acquisition transient of §0.8 are the two constraints to bracket against.

### Class and the button

**4a** (RNG-live, draw-invariant — no new draw; the head is a deterministic servo on an existing
measurement), the 10th consecutive. ⚠ **The button is expected DROPPED (10th)** but needs a
MECHANISM, not an assertion — slice 32's finding. This wire raises `radome_view` AND a new gimbal
marker, so the composition branch of slice 33's HUD is the starting point and the verdict helpers
must be re-examined: **slice 33's HUD compares LEAD vs WINDOW, and under a head the window the lead
is compared against is the STOP, while the DETECTOR window is compared against the tracking error.
A HUD that keeps slice 33's single comparison will print a verdict on the wrong pair.**

### The wire (proposed — gate 1 confirms)

Slice 33's wire held: glass R₀ = −0.03, A = −0.15, vy = 200, seed 32. **`R̂ = −0.18`** is the
showcase residual — strapdown 0.93194 (RINGS) vs gimballed 0.01181 (QUIET), **78.9×**, same glass,
same residual, same seed. ⚠ `STEPS` must be a MULTIPLE of `emit_every` (convention 14; slice 31 lost
an hour to the silent hang).

### The four proofs (convention 14)

`net/slice34_verify.gd`, `net/slice34_ui_test.gd`, a `Sandbox.tscn` headless smoke-load, a windowed
shot. ⚠ Re-run the 26–33 verifiers ON THE WIRE as the byte-identity check — this slice touches the
index six slices are built on, so reading the diff is not enough.

---

## Deferred (NAMED)

* **THE HANDOVER BASKET as an authored quantity** — §0.8 promoted this from slice 32's named
  deferral to a LIVE constraint on this slice: a caged head's window requirement IS the strapdown
  one until it acquires. What ships here is a HANDED-OVER head, stated as a §1 condition; making the
  handover itself addressable is the successor.
* **A RATE-LIMITED HEAD.** `gimbal_rate_max` is implemented in the probe and was NEVER EXERCISED —
  every result above has it absent. A real head has one, and it is the natural home of a
  slew-rate-limited lock loss.
* **MEMORY TRACK / RE-ACQUISITION.** Once the target leaves the detector window the probe's head
  HOLDS — no error signal, no slew — so the break is TERMINAL. A real head coasts on its last
  inertial rate. This is the same choice slice 32 made for the α-β tracker, now one layer out.
* **A RECTANGULAR / PER-AXIS STOP** — a two-axis gimbal really does have independent mechanical
  stops (slice 32's deferral, sharper here: this slice ships one circular window AND one circular
  stop).
* **THE HEAD'S OWN GYRO** — a rate-stabilized head measures inertial LOS rate directly, which is
  the classical reason gimbals exist and a DIFFERENT mechanism from anything here.
* Everything 26–33 named and did not spend: seeker range / SNR acquisition limits; the handover
  basket as an authored quantity; estimating `R̂` in flight (blocked by 26's P7A, sharpened by 29);
  a 2-D slope `R(look_az, look_el)`; an asymmetric error curve; a SINGLE IMU; gyro NOISE
  (draw-topology, convention 3); per-axis scale factors and misalignment; the out-of-plane
  MANEUVERING target; aero + inertial cross-coupling / departure.
