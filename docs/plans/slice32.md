# Slice 32 — THE SEEKER'S FIELD OF VIEW: THE ENVELOPE IS SET BY WHAT THE SEEKER CAN SEE (§11 Tier-A)

The TENTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro), and a deferral that has been named in every one
of them and got sharper each time:

> *"**seeker FOV / gimbal limit** (sharper every slice — this one's bias domain is bounded by the
> look angle reaching 30°, exactly where a gimbal would already have stopped)."* — `docs/plans/
> slice31.md`, Deferred (NAMED); repeated at 26, 28, 29 and named in `CLAUDE.md` as *"now the
> sharpest of these"*.

**Status: GATE 0 COMPLETE (5 probes, 2026-07-28). The advisor's blocking check FIRED and removed
half the planned framing (§4 below). Raw findings and probe scripts in
`M:\claud_projects\temp\slice32\GATE0_FINDINGS.md`. GATE 1 COMPLETE (2026-07-28, 5798 → 5872).
Gates 2–3 NOT STARTED.**

---

## The one-paragraph statement of the lesson

Slices 26–31 made the LOOK ANGLE the central quantity of the whole radome family, and then each of
them bounded its knob domains by that angle reaching 30° — declared every time as a §1
MODEL-VALIDITY caveat, a place where the small-angle linear bend stops being trustworthy. A real
seeker makes the same angle a **PHYSICAL STOP**: it has a field of view, and past it there is no
measurement at all. So the caveat and the hardware coincide, and the arc's first **SENSOR-SIDE CAP**
lands — every previous cap in this project is airframe or actuator (slices 10/12's authored
magnitude clamp, 15's jerk and deflection caps, 19's flight-condition lift ceiling, 22's interior
peak of the lift curve). What the FOV caps is not a force or a rate: it is the **ENGAGEMENT**. A
crossing target must be led, the lead angle is a closed-form property of the collision triangle
(`V_m·sin λ = V_t·sin θ`), and the missile must hold that lead all the way in. If the lead exceeds
the window, the seeker loses the target **while the lead is still building**, the α-β tracker coasts
on a rate that was right for a smaller lead, and the geometry runs away monotonically — a 1141 m
miss out of a missile with 0.0 % of its approach saturated, i.e. with every bit of the authority it
needs and no idea where to point it.

> **THE LESSON, IN ONE SENTENCE.** The FOV a seeker needs is not a seeker number — it is the
> ENGAGEMENT's own lead angle, so a field of view does not cost you accuracy, it costs you the
> ENVELOPE: the set of targets you may engage at all.

⚠ **SCOPE: A STRAPDOWN FOV, NOT A GIMBAL SERVO** (advisor, before any code). There is no head state
anywhere in this codebase — today's seeker is strapdown with an infinite window, and `look_angles`
measures the LOS off the BODY boresight. This slice ships the **track-break**: `|look| > fov ⇒ no
measurement ⇒ the tracker coasts`. A REAL gimbal (a head with its own state, servo bandwidth, rate
limit and mechanical stop) is a different slice and a bigger one: it adds a dynamical state AND it
rewrites 26–31's `look_az`, because the bend would key off the HEAD-vs-body angle rather than the
LOS-vs-body angle. *If a servo state appears in `_observe_point3d!`, the slice has been left.*

⚠ **INHERITED LANGUAGE AND ITS PROHIBITIONS.** Slice 32 adds NO new instability, NO new loop gain
and NO new plant. Slice 26's positive-feedback / limit-cycle language stays with 26–31; slice 20's
"degenerative spiral" stays forbidden. What is new is a **hard sensor limit** and, through it, an
**engagement envelope**.

⚠⚠ **THE SIGNATURE IS SLICE 23's AND SLICE 25's, AND THE MECHANISM IS NEITHER** (the copy-paste
false-claim trap, 3rd occurrence in this arc — write the distinction, never inherit the sentence):

| slice | the miss | the mechanism |
|---|---|---|
| 23 | ≈ 2000 m, `max\|y\| = 0.0` | the autopilot **THREW the out-of-plane command AWAY** (it projected onto the pitch plane) |
| 25 | ≈ 2000 m, `max\|y\| = 0.0` | the command was **NEVER FORMED** — a scalar in-plane seeker cannot represent it |
| **32** | **1141 m, `max\|y\| ≠ 0`** | it **WAS formed and flown, and then the sensor STOPPED SUPPLYING IT MID-FLIGHT** — the missile turns, holds the lead, and loses the target at r = 4072 m |

---

## Gate 0 — the probes (all COMPLETE; full tables in `GATE0_FINDINGS.md`)

| # | question | what it settled |
|---|---|---|
| P1 | ⭐ **BLOCKING (advisor): what look angle does this engagement family actually REACH?** | 0.32° at vy = 0 → **28.84° at vy = 400** (band medians), and the lead is **FROZEN** through the approach (27.93° at r = 3000 → 29.02° at r = 50). ⇒ a FOV stop is pass/fail on the ENGAGEMENT, not a transient dropout. The max reachable over slice 30's whole envelope is ~29° — **exactly the 30° budget 28/29/30/31 each declared**. |
| P2 | Does a lost measurement actually COST anything? (A frozen-lead collision course is exactly where coasting is nearly right — if the miss does not open, the slice must be written around whatever it IS.) | **REFUTED, by ~10⁴×.** fov 25 / vy 400 → **1140.64 m** vs 0.168 m; fov 20 kills vy 320 AND 400. A **30° FOV flies slice 30's ENTIRE envelope; 25° kills its top cell.** |
| P3 | The MECHANISM, and the EXTERNAL ANCHOR (convention 11). | Break at t = 4.80 s / r = 4072 m **while the lead is still building**; the missile keeps turning on the last rate it saw (`a_cmd` ≈ 60–70 all the way in) and the look angle diverges 25° → 32° → 51° → 70°. ⭐ **The critical FOV EQUALS the collision-triangle lead** `V_m·sin λ = V_t·sin θ`, recomputed per tick by a different algorithm: ratio **0.997–1.006** over vy ∈ [80, 400]. |
| P4 | KNOB or RUNG, and the domains. | **`fov = 180°` is BIT-IDENTICAL to the key being absent** (max\|Δpos\| = 0.000e+00 at every vy) ⇒ **KNOB**, button stays DROPPED (8th consecutive). ⚠ 45/60/90 differ by 3.5e−9 m at vy = 400 — the **post-CPA LOS flip**, not the approach; quote 180° for the identity claim. |
| P5 | ⚠⚠ **THE ADVISOR'S BLOCKING CHECK: is the 18.12° never-lock floor a SEEKER property or the scenario's launch attitude?** | **THE LAUNCH ATTITUDE — it FIRED.** The floor tracks the tick-1 look angle to **0.008°** and moves with `elevation_deg` (21.34 / 18.86 / 18.12 / 19.30 / 22.11 at 0 / 6 / 12 / 18 / 24°), minimized not zeroed at 12° because the target's launch BEARING is ~18.4° in azimuth and no pitch attitude removes it. ⭐ **The terminal-lead half is INVARIANT to the same change** (vy = 400: 28.95 / 28.79 / 28.73). ⇒ ONE binding constraint, the "max of two curves" framing DROPPED, domain floor 20°. |

### The two framings gate 0 KILLED

1. **"The envelope is the max of two curves — the handover angle and the terminal lead."** P4b's flat
   18.12° column looked like a second binding constraint. P5 showed it is the authored launch
   attitude (§P5), and that the lead-bound half is invariant to it. **The launch cliff is demoted to
   a MEASURED reason for where the domain stops** (slice 26's post-commit shape).
2. **"Know your slope curve over the BAND the engagement visits" (the slice-28 callback).** Slice
   28's sentence describes a curve sampled ACROSS a band; this engagement holds a **FROZEN** lead —
   a 1° band over the entire approach — so the FOV requirement is a SINGLE number against a SINGLE
   sustained angle. Importing 28's structure is this project's own false-fidelity reflex. **The
   kinship is only that both quantities belong to the ENGAGEMENT rather than to the hardware.**

---

## Gate 1 — COMPLETE (the kernels and their teeth, 5798 → 5872)

Three kernels in `frames.jl`, exported, beside `look_angles`:

| kernel | what it is |
|---|---|
| `boresight_angle(att, los)` | the TOTAL off-boresight angle `hypot(look_angles(...)...)` — the CIRCULAR-window quantity, i.e. the one the radome comments correctly warn is the WRONG one for the per-axis glass |
| `seeker_in_fov(att, los, fov)` | the predicate, `≤ max(fov, 0)` — **the single site of the negative-`fov` clamp** (convention 5) |
| `collision_lead_angle(V_m, v_t, û)` | the ENGAGEMENT side: `λ = asin(‖v_t × û‖ / V_m)`, the P3b external anchor |

⭐ **THE SEAM NOW CALLS THE KERNEL — that is the load-bearing half of this gate** (advisor, before
any code). The gate-0 seam computed `hypot(fa, fe) ≤ fov_rad` INLINE; had gate 1 shipped kernels
beside it, `test_frames.jl` would have proved a SECOND implementation and nothing about what flies.
That is convention 14's slice-31 lesson ("anything the verdict computes inside `_draw` has no
headless proof — extract it to a pure helper") one layer down. ⚠ The clamp moved WITH it, to exactly
one site: `missile.jl` converts degrees → radians and hands the result in, deliberately not clamping
twice. **Behaviour-preserving, PROVEN on the wire, not by reading the diff** — all four P4c showcase
arms reproduce gate 0 to the digit (1140.635 / 0.16777 / 0.06197 / 0.16777 m, out-of-window 69.6 %,
look_max 103.14 / 29.02 / 23.86°, ToF 15.40 / 15.31 / 12.93 s; `M:\claud_projects\temp\slice32\
g1_wire_check.jl`).

⚠ **`collision_lead_angle` has NO src caller yet** — normal at gate 1 (slice 25 shipped
`los_unit_from_angles` at gate 1 and wired it at gate 2), but **gate 2 must DECIDE**: ship it as
`<sid>.lead_angle_deg` telemetry (the client could then draw the lead the engagement DEMANDS beside
the window it HAS) or drop it. It may not reach gate 3 as a core function whose only caller is a
test. ⚠ And if it ships, **the verifier may NOT use that telemetry as the anchor for the look-angle
claim** — the P3b anchor has to stay an independent recompute, or it becomes the self-calibrated
round-trip this project names as a trap.

### ⚠⚠ THE GATE-1 CORRECTION: "180° IS THE WHOLE SPHERE" IS FALSE

The angle-space radius `hypot(az, el)` is **not bounded by π**. Its supremum is
`hypot(π, π/2) ≈ 201.246°`, approached at the anti-boresight: a LOS at `(az, el) = (180°, 20°)`
reads **181.108°**, and a `fov = π` window **REJECTS** it. So P4a's measured identity must be worded
**"`seeker_fov_deg = 180` is bit-identical to the key being absent ON THIS WIRE"** — an empirical
statement about the look angles the engagement REACHES, never "180° admits everything". The
knob-vs-rung argument is undamaged and in fact rests on exactly that reachable-set reasoning (slice
22's refutation of "the off-state is a limit point ⇒ RUNG"). The domain ceiling is 40°, so nothing
operational changes. Both facts are pinned in `test_frames.jl`.

### The other measured facts gate 1 added

* **The radius is NOT the exact cone half-angle** `acos(u_body[1])` — a §1 approximation, now
  MEASURED in both directions: EXACT on either axis plane, and OVERSTATING off them by at most
  **+0.364° at a true 30° cone** (peaking at a ~47° clock angle). Both windows are defensible; what
  matters is that the shipped one is named, and it is the one every gate-0 number was measured with.
* **The circular-vs-rectangular tooth**: at `(0.8f, 0.8f)` the radius is `1.131·f` (OUT) while
  `max(|az|,|el|)` is `0.8·f` (IN) — the two windows DISAGREE and the assert says which ships,
  PAIRED with `(0.6f, 0.6f)` where they agree.
* **The `≤` boundary is pinned without a tolerance**, built backwards from the kernel
  (`prevfloat(boresight_angle(...))` rejects) — no float LOS lands bit-exactly on `deg2rad(25)`.
* **The `asin` saturation is a SENTINEL meaning "no FOV suffices", NEVER "you need 90°"** — pinned
  flat at exactly π/2 from the limit outward, so gate 3 cannot quote it as a requirement number.
* **`collision_lead_angle` really is a collision lead, not an arcsine**: flying the missile at that
  lead in the `(û, v_t)` plane cancels the relative velocity's ⟂-LOS component to ≤1e−9 over a
  400-case seeded sweep — checked with the projection subtraction the kernel deliberately avoids.
* **Rotation invariance** of `boresight_angle` under a common rotation of attitude and LOS (400
  cases, its own `Xoshiro`) — the transpose / frame-error catch, and the stochastic half of
  convention 1, which has nothing else random here. ⚠ It is NOT roll-invariance: the radius
  genuinely varies with the clock angle, and that variation IS the approximation measured above.

⚠ **What gate 1 deliberately does NOT prove**: that the look angle EQUALS the collision lead. The
two differ by aerodynamic incidence (−0.06…+0.03° against a ~29° lead, gate-0 §5) — that is a
statement about a flying missile and it needs a wire, so it is gate 3's.

### Gate-1 post-review (advisor)

* **The one-shot-lead misuse is now IN the docstring**, in the same register as the saturation
  sentinel: a lead computed from the LAUNCH geometry instead of the live one is **32.90° against the
  28.84° the engagement holds — 14 % strict** (gate-0 §5), because the LOS rotates as the target
  crosses. Evaluating this kernel once is the natural misuse for a HUD or a pass text, and the
  0.997–1.006 agreement with the look angle is a PER-TICK agreement resting on nothing else.
* **`fov_rad` is deliberately UNASSIGNED on the non-FOV path.** A first draft set it to `Inf` in the
  else-arm, which silently supplies a plausible value where an unassigned local throws and the suite
  catches it — and gate 2 ships `<sid>.seeker_fov_deg` telemetry. **Gate-2 telemetry reads
  `c[:seeker_fov_deg]` under `_fov_on`, never this local.**
* **The P4d radome × FOV corollary was re-measured under the kernel seam** — the one branch
  combination the showcase check does not exercise (radome LIVE + FOV LIVE). All six arms reproduce
  gate 0 exactly, headline included: **3774.59302 m at fov 20 + ringing glass, 72.0 % out of window**,
  against 0.14117 m radome-free at the same fov, and the re-acquisition arm at 1.06672 m / 0.4 %
  (`M:\claud_projects\temp\slice32\g1_wire_check_radome.jl`).

### Still open, carried into gate 2 (advisor)

* ⚠⚠ **GATE 2's OPENING MOVE — NOTHING IN THIS SLICE HAS EVER GONE THROUGH THE LOADER.** Every
  gate-0 probe and both gate-1 wire checks inject `m.comp[:seeker_fov_deg] = fov` PROGRAMMATICALLY;
  `scenarios/slice32_fov.yaml` will not. Verify the YAML→comp path admits the key, and decide
  whether `scenario.jl` needs a validate-at-LOAD entry (convention 5), BEFORE building on top of it
  — the whole evidence base rests on a path the shipped scenario does not use.

* `look_angle` telemetry must become `_rad_on || _fov_on`-gated — **never unconditional**, which
  would add a key to slice 25's wire.
* The `_prev`-tracks-the-prediction line (§ the seam, below) still needs either a tooth on a `:raw`
  arm or an explicit defensive-and-unexercised marker. Gate 0 §8 already supplies the re-acquisition
  evidence.
* The draw-count assertion (convention 3) is gate 2/3, not gate 1.

---

## The seam (gates 1 & 2)

`missile.jl` `_observe_point3d!`, a new branch AHEAD of the tracker update — the experimental version
is already in the tree and the full suite is **green at 5798** with it (the key-absent path is
textually the existing one, so slices 1–31 are byte-identical by construction, not by a cancelling
zero — the slice-20/21/26/27/28/29/31 structural shape).

    _fov_on = haskey(c, :seeker_fov_deg) && haskey(c, :att_q) &&
              get(w.fidelity, :airframe, :point_mass) === :six_dof
    in_fov  = !_fov_on || seeker_in_fov(c[:att_q], û_tru, deg2rad(c[:seeker_fov_deg]))

(gate 1 replaced the inline `hypot(...) ≤ deg2rad(max(fov,0))` with the shipped kernel, and moved
the clamp inside it — see the gate-1 section above; the wire numbers are unchanged to the digit)

with three tracker branches: **NEVER LOCKED** (out of the window before the first measurement — a
defined, finite, non-throwing state; `seek_init` stays false so the first in-window tick initializes
normally), **COASTING** (the α-β predict step alone: the angle extrapolates, the **rate is FROZEN**,
and the rate is what PN consumes), and the existing in-window path VERBATIM.

* ⚠ **The FOV quantity is the TOTAL off-boresight angle `hypot(look_az, look_el)`** — a CIRCULAR
  window. That is precisely the quantity the radome comments correctly warn is the WRONG one for the
  per-axis glass (`ε_az = f(look_az)` separately), and the RIGHT one here. A rectangular / per-axis
  FOV is a named deferral, and the reason is written at the branch.
* ⚠ **Computed from the TRUTH LOS**: whether the target is inside the window is PHYSICS, not an
  estimate. (Contrast the compensator two blocks below, which must use the BENT measurement.)
* ⚠ **Rung-gated on the LIVE `:airframe === :six_dof`**, never on `haskey(:att_q)` alone — the
  slice-21 `_atm_on` / 23 / 26 / 27 latent-bug class, whose FIFTH occurrence this would be.
* ⚠ **Convention 3 — gate the VALUE, never the DRAW.** The two `randn` at the top of
  `_observe_point3d!` stay unconditional; an out-of-window tick draws `n_az`/`n_el` and discards
  them. That is slice 25's own lockstep (the foil DISCARDS, it does not SKIP), and it is what keeps
  25–31 bit-identical. **ASSERT the draw count, do not assume it.**
* ⚠ Convention 5/6: `max(fov, 0.0)` at the consumer (a live slider cannot go negative); `fov = 0` is
  the never-locked state, not a throw.
* ⚠ **The `_prev`-tracks-the-prediction line is DEAD CODE on a `:filtered` wire** (advisor): while
  coasting, `seek_*_prev` is set to the predicted angle so the `:raw` foil differences a sane pair on
  re-acquisition instead of one spanning the whole gap. **Either give it a tooth on a `:raw` arm
  (re-acquire, assert the raw rate is finite and O(true rate)) or mark it defensive-and-unexercised
  in the comment. Do not leave a live-looking branch with no proof.**

New telemetry, per slice 22's `post_stall` discipline — **do not let the miss carry the mechanism
claim alone, and do not expect an existing flag to discriminate**:

* `<sid>.seeker_valid` — 1/0, the discriminator.
* `<sid>.look_angle` — already shipped, but RADOME-gated today; it must ship on a FOV wire too.
* `<sid>.seeker_fov_deg` — the window itself, so the client can draw the limit beside the angle.

---

## Gate 3 — the wire, the metric, the proofs

**Scenario `scenarios/slice32_fov.yaml`** — slice 30's geometry and plant, with the **RADOME KEYS
ABSENT** (convention 9 and the advisor: 26–31's wire RINGS by construction, and a ringing arm's look
angle swings BECAUSE it rings, so the look angle measured on it is the LOOP's and not the
ENGAGEMENT's; deleting them puts the missile on the slice-25 clean path). Opens on the disease:
`seeker_fov_deg = 25`, `cross_speed_mps = 400`.

**TWO KNOBS, AND CONVENTION 9 IS SATISFIED BY A MEASUREMENT** (never by counting sliders): they are
two terms of ONE comparison, `fov` vs `lead(vy)`, and the verdict flips exactly where the difference
crosses zero — reached from both directions, agreeing to **0.01–0.03°** (P4b).

| arm | miss (m) | out-of-window % | max look° | `aero_sat` % |
|---|---|---|---|---|
| **OPEN — fov 25°, vy 400** | **1140.64** | **69.6** | 103.14 | 0.0 |
| CURE A — widen the seeker → 30° | 0.17 | 0.0 | 29.02 | 0.0 |
| CURE B — slow the crossing → 320 | 0.06 | 0.0 | 23.86 | 0.0 |
| reference — no FOV at all, vy 400 | 0.17 | 0.0 | 29.02 | 0.0 |

**6710× and 19011×** — the slice-31 two-cures-one-slider-each shape. ⚠ **AND THE ASYMMETRY IS THE
PAYLOAD: cure A is free, cure B is not.** Widening the seeker keeps the engagement; slowing the
crossing means DECLINING it.

**THE METRIC IS THE MISS** (advisor, and it inverts 28–31's): `rms r` must NOT be inherited here,
because losing the measurement **cuts the parasitic feed** — on a ringing wire the FOV would LOWER
rms r while OPENING the miss, and the slice would be written backwards. Here the miss opens ~10⁴×,
and a big miss samples faithfully ([[ewsim-missile-verifier-sampling]] cuts the right way).

* ⚠ **ASSERT the VERDICT and the out-of-window fraction; QUOTE the miss at named cells.** The miss
  MAGNITUDE is **NOT monotone in `fov` inside the broken region** (vy = 320: 1374 → 1693 → 1325 →
  866) — a ballistic-scatter number. The verdict is monotone and sharp to 0.02°. (4th occurrence of
  the non-monotone-knob pattern, [[ewsim-df-ellipse-sigma-monotonicity]].)
* ⚠ **ISOLATION: `aero_sat` is 0.0 % in EVERY arm, broken or not** ⇒ a POINTING miss, not the arc's
  ceiling miss. Assert the FLAG as a number; never hand-roll the compare (the sets nest).
* ⚠ Every look-angle number is **range-gated (r > 200 m)** or band-restricted: the ungated max reads
  151–180°, which is the post-CPA LOS flip.

**Knob domains, MEASURED** (slice 26's post-commit discipline — endpoints measured, never inferred):

* `seeker_fov_deg ∈ [20, 40]`. The FLOOR is stated with its reason: below **18.120°** the seeker
  never acquires on this wire, but **that cliff is the scenario's authored launch attitude, not a
  seeker property** (P5) — so the domain starts above it and the slider measures the SEEKER. The
  CEILING is inert across the whole crossing-speed axis (every cell hits from 30° up).
* `cross_speed_mps ∈ [0, 400]` — slice 30's, INHERITED unchanged.
* DISQUALIFIED and asserted absent: `n_pn` / `rho` (they move the guidance loop the lesson is not
  about); `radome_*` (a second mechanism, §below); `sigma_seek` (degrades the lesson beside it);
  `elevation_deg` (the slice-19 DEAD-knob class — consumed once at load — **and** P5's artifact);
  `af_alpha_max` (the arc's ceiling, held at 0.0 % here on purpose).

**Class 4a** — draw-invariant (the two `randn` stay unconditional) YET trajectory-changing. **EIGHTH
consecutive RNG-live slice** (25–32): the seed is load-bearing, conventions 3/11 apply, and the
draw-count identity is ASSERTED. **KNOB, not rung** (the 180° bit-identity, measured). **Button
DROPPED** — the 8th consecutive slice whose lesson is sliders with no button at all (16, 26, 27, 28,
29, 30, 31, 32).

### The corollary that stays OFF the wire

**⭐ SLICE 26's PARASITIC LOOP CAN SHAKE THE SEEKER OUT OF ITS OWN WINDOW.** At the same `fov = 20`
and the same `vy = 200`, the radome-free missile hits (0.14 m) while the RINGING one is out of the
window 72 % of the approach and misses by **3774.59 m** — the ring inflates the look-angle excursion
from 18.13° to 25.05°. **⚠ A SECOND MECHANISM ⇒ convention 9 keeps it off the showcase wire**; it
ships as a `test_missile.jl` phase (the slice-28 precedent for relocating a non-client-drivable
claim), and **that one test must assert BOTH directions**, because it is also the re-acquisition
evidence: at `fov = 25` the same ringing arm loses lock for **0.4 %** of the approach, in brief
episodes, **and still hits (1.07 m)**. A short loss is survivable; what is terminal is a loss while
the lead is still building.

### The four proofs (convention 14)

`net/slice32_verify.gd`, `net/slice32_ui_test.gd`, a `Sandbox.tscn` headless smoke-load, and a
windowed shot. ⚠⚠ **`STEPS` MUST BE A MULTIPLE OF `emit_every`** (16 on this wire — slice 31 lost an
hour to a silent hang). ⚠ **Anything the verdict computes inside `_draw` has no headless proof** —
the FOV verdict goes in a pure helper the UI test calls (slice 31's aim-point comparison shipped
wrong and only the SHOT caught it). ⚠ Re-run the 26–31 verifiers **on the wire** as the byte-identity
check, not a reading of the diff. ⚠ ToF varies arm to arm (12.9–15.4 s) — size `STEPS` off the
SLOWEST arm and assert every arm REACHED CPA (slice 30's discipline).

---

## Deferred (NAMED)

* **A REAL GIMBAL** — a head with its own state, servo bandwidth, rate limit and mechanical stop.
  It adds a dynamical state AND rewrites 26–31's `look_az` (the bend would key off head-vs-body, not
  LOS-vs-body). The reason it is not folded in here is written at the seam.
* **A RECTANGULAR / PER-AXIS FOV** — this slice ships ONE circular window; the per-axis habit belongs
  to the glass, not to the window.
* **THE GIMBAL ON THE RADOME WIRE** — measured here (§ the corollary), kept off the showcase by
  convention 9. The strongest successor: it is the first mechanism in the arc that turns slice 26's
  ring into a LOCK LOSS.
* **THE HANDOVER BASKET as an authored quantity** — P5 found the launch look angle is a live physical
  constraint that this wire holds fixed; making it addressable is a scenario-design slice.
* **SEEKER RANGE / SNR ACQUISITION LIMITS** — the other half of "can the seeker see it": this slice
  models only the ANGLE.
* Everything 26–31 named and did not spend: estimating `R̂` in flight (blocked by 26's P7A, sharpened
  by 29); a 2-D slope `R(look_az, look_el)`; an asymmetric error curve; a SINGLE IMU; gyro NOISE
  (draw-topology, convention 3); per-axis scale factors and misalignment; the out-of-plane
  MANEUVERING target.
