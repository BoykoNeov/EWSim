# Slice 35 — A RATE-LIMITED HEAD: THE BANDWIDTH THAT HOLDS THE TRACK IS THE BANDWIDTH THAT FEEDS THE LOOP (§11 Tier-A)

The THIRTEENTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro, 32 = the seeker's field of view, 33 = the ring as
an FOV budget item, 34 = the gimbal), and the deferral slice 34 named SECOND:

> *"**A RATE-LIMITED HEAD.** `gimbal_rate_max` is implemented in the probe and was NEVER EXERCISED —
> every result above has it absent. A real head has one, and it is the natural home of a
> slew-rate-limited lock loss."*
> — `docs/plans/slice34.md`, Deferred (NAMED)

**Status: GATE 2 COMPLETE (2026-08-09) — the seam + the loader + the telemetry, suite 6685 → 6874
green, + a post-review commit to 6892 (advisor: the `rate ≤ 0` degenerate the loader PERMITS was
proven to LOAD and never FLOWN — it is BIT-FOR-BIT slice 34's `τ = Inf` reductio, and at gate 3 the
key is a declared knob a client can reach live). See §2 for its ONE FINDING (a rate limit makes the ACQUISITION TURN the binding requirement,
which SETTLES the knob count) and for the two conditions every gate-2 number carries. GATE 1 COMPLETE
(2026-08-09) — the kernel + 52 teeth, and `missile.jl` was UNTOUCHED there, so every prior slice was
bit-identical BY CONSTRUCTION; §1's two findings both changed what gate 2 wrote. GATE 0 COMPLETE
(2026-08-09, 5 probes).
⚠⚠ THE OPENING FRAMING WAS REFUTED BEFORE ANY CODE (§0.1, advisor) — "a finite slew rate breaks
lock in the endgame at `r ≈ V⊥/ω_max`" is a PURSUIT geometry and a DEAD KNOB on a collision course.
⚠⚠ AND THE ADVISOR'S OWN SHIP/NO-SHIP GATE CAME BACK NEGATIVE (§0.3) — a wider window DOES rescue a
rate-limited arm, so the BREAK is slice 34's mechanism and is NOT this slice's claim. The live
claim was found in a THIRD place (§0.5), the slice-33/34 shape exactly.
⚠⚠ AND A SECOND ADVISOR BLOCKING CHECK FIRED ON THE HEADLINE ITSELF (§0.6) — the quiet end of the
new knob is slice 34's FROZEN-HEAD REDUCTIO reached continuously, so its 43× is UNQUOTABLE.
Probe scripts and the full measured tables in `M:\claud_projects\temp\slice35\`
(`g0_results.md`, and the uncommitted kernel patch as `g0_probe_patch.diff`).**

---

## The one-paragraph statement of the lesson

Slice 34 gave the seeker a head, and the head bought a stability margin by pointing where its own
bent measurement said the target was. That head was **infinitely fast**: `head_slew` moved it a full
first-order step every tick with no bound on how far. A real gimbal has a servo with a maximum slew
rate, and the moment it does, the head's motion stops being free — it becomes a resource, spent
against a demand. **The demand is set by the parasitic loop.** On a settled collision course the
LOS barely moves in the body frame (slice 28 held `look_az` to a 0.2° band; slice 34's head angle is
a *constant* 17.190°), so a quiet design asks its servo for essentially nothing — 0.600 °/s in the
engagement band. Let the loop ring and the same head must chase its own oscillation: **60.831 °/s,
53.6× more, across slice 34's own onset bracket.** So a rate limit that is *free* on a good design
is *binding* on a ringing one, and what it costs is charged to the account slice 34 opened — the
detector window: at the same 8 °/s servo the shipped design saturates its rate limit on **0.00 %**
of the band and the boresight-characterized one on **97.14 %**, paying 13.2° of tracking error where
the good design pays 1.98°.

> **THE LESSON, IN ONE SENTENCE.** A gimbal's slew rate is free until the loop rings — and then it
> is the most expensive thing on the missile, because the motion that holds the track is the same
> motion that feeds the loop.

⭐⭐ **AND THIS IS THE ARC'S FIRST TWO-SIDED KNOB.** Slices 32, 33 and 34 all end the same way:
*widen it — it is free* (a wider FOV, a wider detector window, costing nothing but glass). **That
cure does not transfer.** Servo bandwidth is not a window; it is what the parasitic loop feeds on.
Slow the head and the ring is attenuated (`rms r` 0.88465 → 0.38591, **2.29×**) while the tracking
error it must cover grows (5.916° → 12.828°, 2.17×) — one knob, two bounds, pulling in opposite
directions. ⚠ And the far end of that knob is **not** a better filter: past ~5 °/s the limit binds
on 100.00 % of ticks and the head stops being a servo at all (§0.6).

---

## §0 — Gate 0 (5 probes, 2026-08-09)

All probes fly the **SHIPPED** `EWSim.Seeker` off the real comp keys — unlike slice 34's gate 0,
nothing is duplicated, because the gimbal shipped. The wire is `scenarios/slice34_gimbal.yaml` to
the digit (seed 32, crossing target vy = 200, glass R₀ = −0.03 / A = −0.15 / k = 12, τ = 0.05,
stop 30°). The rate limit itself is an **uncommitted** patch to `head_slew` + the seam
(`g0_probe_patch.diff`, applied and reverted per probe run); what ships is gate 1's business.

### ⚠⚠ §0.1 — REFUTATION 1: THE ENDGAME FRAMING IS A DEAD KNOB (advisor, before any code)

The natural opening claim is that the LOS rate `λ̇ = V⊥/r` grows without bound as range closes, so a
finite slew rate breaks lock at a range with a closed form, `r_break ≈ V⊥/ω_max` (≈ 1145 m at 200
m/s against 10 °/s — a comfortable domain). **It is a PURSUIT geometry.** On a settled collision
course the perpendicular component of relative velocity is zero *by construction*, so λ̇ ≈ 0 and
stays ≈ 0 as `r` closes. This arc has already measured that three times: slice 28 holds `look_az`
to a **0.2° band**, slice 29's gate-0 refutation #1 turns on exactly it ("the lead angle is CONSTANT
BY CONSTRUCTION on a settled collision course"), and slice 34's `head_angle_deg` is a **constant
17.190°** on the quiet arm, not a sweep. ⇒ on any wire this family flies, an endgame rate limit is
the **slice-19 DEAD-KNOB class**, and slice 33 already located the terminal LOS swing at
r = 0.18–8.55 m — ~10 ms before impact, far too late to move a miss. **Do not write it.**

### ⭐⭐ §0.2 — P1: WHERE THE DEMAND ACTUALLY LIVES, AND IT STEPS AT SLICE 34's OWN BRACKET

Demanded head rate (deg/s, a finite difference on the head's own `:head_az`/`:head_el` — i.e. what
the head ACTUALLY DID with no limit, which is exactly what a limit would clip), free window:

| R̂ | rms r | rate p50 | rate p95 | **band p95** | head | off | miss |
|---|---|---|---|---|---|---|---|
| −0.33 | 0.05917 | 2.529 | 3.668 | 2.468 | 18.117 | 1.599 | 0.161 |
| −0.24 | 0.02497 | 2.383 | 3.711 | 1.663 | 18.117 | 1.831 | 0.050 |
| −0.18 | 0.01181 | 0.784 | 4.319 | **0.600** | 18.117 | 1.956 | 0.187 |
| −0.16 | 0.35338 | 4.404 | 33.883 | **32.155** | 20.619 | 5.237 | 5.695 |
| −0.12 | 0.70207 | 19.067 | 47.796 | 48.536 | 22.026 | 5.587 | 6.500 |
| −0.03 | 0.88465 | 28.922 | 60.450 | **60.831** | 23.601 | 5.916 | 5.246 |

⇒ the band demand **STEPS 0.600 → 32.155 °/s across slice 34's own onset bracket (−0.18, −0.16] —
53.6×** — and the whole quiet ladder sits under 2.5 °/s. A limit anywhere in ~8–40 °/s is therefore
inert quiet and binding ringing **by construction**, which is a knob domain that writes itself.

⚠ **THE PEAK IS AN ARTEFACT AND MUST NEVER BE QUOTED**: `rate_max` is an identical **72.542** on
every arm, because it is the tick-2 HANDOVER transient, before the arms have diverged. Slice 25's
"exclude the init ticks" rule, in a new quantity — use percentiles and the band, never the peak.

### ⚠⚠ §0.3 — REFUTATION 2: THE ADVISOR'S OWN SHIP GATE CAME BACK NEGATIVE (`p2_decide.jl`)

Slice 33 already shipped "the ring breaks the FOV" and slice 34 "the ring is spent in detector
window". The check that decides whether slice 35 is a different slice: **widen `gimbal_fov_deg` and
the rate-limited arm must still break.** R̂ = −0.03, binding limits:

| rate | fov 4 | fov 8 | fov 20 | fov 60 | fov 1e6 |
|---|---|---|---|---|---|
| 10 °/s | break, 3914 m | break, 3952 m | HOLD 7.920 | HOLD 7.920 | HOLD 7.920 |
| 5 °/s | break, 3688 m | break, 3770 m | break, 3530 m | HOLD 0.898 | HOLD 0.898 |

**A wider window DOES rescue it.** ⇒ THE BREAK MECHANISM IS SLICE 34's (`tracking error > detector
window`) AND IS NOT THIS SLICE'S CLAIM — writing slice 35 as a new failure mode would be the
copy-paste false-claim trap. What is new is the **REQUIREMENT** (the window needed grows 5.9° free
→ 16.3° at 10 °/s → 23.4° at 5) and the **TRADE** (§0.5). The novelty is relocated, not defended.

### ⚠⚠ §0.4 — THE ACQUISITION CONFOUND, AND THE GATE THAT REMOVES IT (`p3_ushape.jl`, `p4_band.jl`)

With **no glass at all** — nothing to ring — `off_max` still runs 2.112° free → 10.325° at 10 °/s →
24.330° at 2 °/s, and `t@off` is EARLY every time (0.12 → 3.28 s). That is the missile's **initial
turn onto the collision course**, and its demand (~40 °/s) is the SAME ORDER as the ring's (~60).
⇒ **no number may be attributed to the loop until the launch transient is gated away** (convention
9). THE GATE IS THE ARC'S OWN [500, 3000] m band — the launch turn happens at r ≈ 6000 m, so the
band excludes it BY CONSTRUCTION rather than by a tuned `t₀`.

`off_band` (deg), free window — the requirement with the launch turn removed:

| arm | free | 40 | 30 | 25 | 20 | 15 | 10 |
|---|---|---|---|---|---|---|---|
| NO GLASS | 0.031 | 0.031 | 0.031 | 0.031 | 0.031 | 0.031 | 0.031 |
| RULE R̂ = −0.33 | 1.599 | 1.603 | 1.603 | 1.602 | 1.602 | 1.601 | 1.600 |
| DESIGN −0.18 | 1.956 | 1.959 | 1.978 | 1.986 | 1.988 | 1.986 | 1.981 |
| RING −0.16 | 5.167 | 5.156 | 5.126 | 4.945 | 4.691 | 4.349 | 5.018 |
| LOUDEST −0.03 | 5.916 | 7.496 | 8.531 | 9.524 | 11.003 | **13.244** | 13.228 |

⭐ At 15 °/s the loudest design's requirement grows **+7.328°** (5.916 → 13.244, 2.24×) and the
shipped design's grows **+0.030°** (1.956 → 1.986) — the SAME servo, the SAME window, ~240×
difference in what the identical rate limit COSTS.

⭐ **SLICE 30's RULE PAYS A THIRD TIME** (33 = FOV, 34 = detector window, 35 = servo bandwidth): at
R̂ = `radome_slope_worst` = −0.33 the requirement is **FLAT across the whole rate domain**
(1.599 → 1.591) ⇒ aim the compensator at the glass's worst-case slope and you may fly the cheapest
servo in the catalogue.

⚠ **THE R̂ = −0.16 ROW IS NON-MONOTONE** (5.167 → 4.349 → 5.018, and `p3` shows the same dip at
10–12 °/s): the ring-suppression benefit briefly outruns the lag cost there. **Nothing may be built
on it** — name it as measured non-monotonicity and keep the domain off it (the ~5th occurrence of
that pattern in this arc, after slices 19/20/22/28).

⚠ **AND `off_band` IS NOT U-SHAPED**: `p3` swept it to 2 °/s on every arm and it is monotone in the
rate. ⇒ there is **no interior optimum**; the two bounds live in two DIFFERENT quantities, which is
slice 30's two-bound shape (stability from one side, accuracy from the other), not a new one.

### ⭐⭐ §0.5 — WHERE THE LIVE CLAIM IS: THE FIRST TWO-SIDED KNOB (`p2_decide.jl` §P2c)

`rms r` against the rate limit at an **infinite window** — so it CANNOT be slice 34's
frozen-index-from-lock-loss artefact, since the head never loses its error signal:

| R̂ | free | 60 | 40 | 25 | 15 | 10 | 5 | 3 | 2 |
|---|---|---|---|---|---|---|---|---|---|
| −0.16 | 0.3534 | 0.3534 | 0.3542 | 0.3313 | 0.2506 | 0.1821 | 0.1401 | 0.0273 | 0.0143 |
| −0.03 | 0.8847 | 0.8847 | 0.8629 | 0.7049 | 0.5583 | 0.4696 | 0.2844 | 0.0269 | 0.0205 |

**A rate limit QUIETS THE RING while BREAKING THE TRACK.** That is `head_slew`'s own docstring line
made quantitative — *"the motion that holds the track is the motion that feeds the loop"* — and it
is slice 34's `τ = Inf` FROZEN-HEAD REDUCTIO reached **continuously** instead of by fiat.

⇒ ONE KNOB, TWO BOUNDS, PULLING IN OPPOSITE DIRECTIONS. Every cure since slice 32 ends "widen it,
it's free"; **that cure does not transfer**, because bandwidth is what the loop feeds on. This is
the slice's payload, and §0.4's requirement curve is how the LOWER bound is priced.

### ⚠⚠ §0.6 — P5: THE QUIET END IS THE REDUCTIO (advisor BLOCKING CHECK, and it FIRED)

Two different claims produce §0.5's single column and they had to be separated before any ratio
could be quoted: **(a)** the limit ATTENUATED the parasitic feed — the head still closes its own
loop, a LOW-PASS, a mechanism; or **(b)** the servo can no longer follow ANYTHING — an OPEN-LOOP
RAMP whose output is `∫ rate_max`, whose bend is therefore nearly constant, and which is quiet for
precisely slice 34's frozen-head reason. THE DISCRIMINATOR: what fraction of band ticks does the
limit actually BIND? (⚠ the STOP cannot confound it — head travel ≤ 24.6° against a 30° stop on
every arm, so `head_clamp` never binds and only the rate limit can hold the step at its cap.)

| rate | −0.03 sat% | rms r | off_band | −0.16 sat% | −0.18 sat% |
|---|---|---|---|---|---|
| 60 | 8.64 | 0.88469 | 5.915 | 0.00 | **0.00** |
| 40 | 64.61 | 0.86288 | 7.496 | 4.02 | **0.00** |
| 25 | 91.27 | 0.70495 | 9.524 | 16.54 | **0.00** |
| 15 | 96.65 | 0.55832 | 13.244 | 31.07 | **0.00** |
| 8 | 97.14 | 0.38591 | 12.828 | 78.43 | **0.00** |
| 5 | 97.42 | 0.28440 | 9.839 | 93.00 | 87.94 |
| 3 | **100.00** | 0.02690 | 17.140 | **100.00** | **100.00** |
| 2 | **100.00** | 0.02047 | 23.717 | **100.00** | **100.00** |

⚠⚠ **THE 43× IS UNQUOTABLE.** At 2–3 °/s the limit binds on **100.00 %** of band ticks on every arm:
the head is an open-loop ramp, not a filtered servo, and quoting a ring ratio against it would be
slice 26's `omega_ratio` diagnostic trap in a new place. **That end ships as THE REDUCTIO, named,
and it is what sets the DOMAIN FLOOR.** ⭐ The defensible trade is the partially-saturated region:
`rms r` 0.88465 → 0.38591 (**2.29×**) bought with `off_band` 5.916 → 12.828 (2.17×).

⭐⭐ **AND P5 SHIPS A BETTER DISCRIMINATOR THAN `off_band`.** At the SAME 8 °/s servo the shipped
design saturates **0.00 %** of the band and the loudest **97.14 %** — and `sat_band` is EXACTLY 0.00
on the shipped design all the way down to 8 °/s. A 0-vs-97 split, and it is the SERVO's own side of
§0.2's 0.600-vs-60.831 demand: two quantities, two code paths, one claim.

### ⭐ §0.7 — THE ISOLATION, MEASURED AND STRONGER THAN EXPECTED (`p3_ushape.jl` §P3b)

On the **no-glass** wire the MISS is **0.191 m at every rate from free to 2 °/s** and `rms r` is
identical to five decimals (0.01589) — while `off_max` runs to 24.33°. ⇒ **THE RATE LIMIT REACHES
THE TRAJECTORY ONLY THROUGH THE GLASS.** Slice 34's "exactly two channels" (the radome INDEX and
the detector WINDOW) re-measured for the new knob, as a column rather than an inference. ⚠ And
`head_max` FREEZES at 18.117° on every rate-broken arm — slice 34's THIRD two-run quantity, the
dangerous one (plausible, in range, too small), reconfirmed here in a new failure mode.

---

## §1 — Gate 1 (2026-08-09) — THE KERNEL, AND TWO FINDINGS

`frames.jl` `head_slew` gains the defaulted keyword `rate_max = Inf`; the radial clamp on the step
is INNER to `head_clamp` (the stop keeps the last word); 52 teeth in `test_frames.jl`.

### ⚠⚠ FINDING 1 — THE PLAN'S OWN BRANCH POLARITY IS BACKWARDS, AND THE GATE-0 PROBE PATCH CARRIES
### THE BUG (advisor, before any code)

"What ships" below writes the inert branch as `step ≤ cap || …`, and `g0_probe_patch.diff`
implements exactly that. **It regresses three of slice 34's shipped degenerates to NaN.**
`cap = max(rate_max, 0)·Δt`, so the DEFAULT `rate_max = Inf` at `Δt = 0` gives `cap = Inf·0.0 =
NaN`; `step ≤ NaN` is FALSE, so the LIMITING branch runs and `sc = NaN/step` propagates. The three:
`test_frames.jl`'s `dt = 0`, `dt < 0`, and `τ = 0 ∧ dt = 0` rows, all of which demand `===`.

⇒ **the shipped form guards the BINDING branch** (`sat = dem > cap`), which makes every non-finite
cap inert for free and is `head_clamp`'s own `m > s || return (a, e)` semantics — ONE kernel shape,
not two. A NaN `rate_max` therefore degenerates to NO limit with no special case. ⚠ The NaN-cap rows
are now in the degenerate table explicitly, so a later cleanup of the `Inf·0` NaN cannot silently
reintroduce it.

### ⭐ FINDING 2 — `τ = 0 ∧ dt = 0` PARTS COMPANY WITH SLICE 34, AND IT IS THE PHYSICAL ANSWER

The one row where a finite limit is STRICTLY STRONGER than the unlimited head: `cap = rate·Δt` is
ZERO at `Δt ≤ 0`, so the exact-landing ASSIGNMENT is unreachable and the head FREEZES where slice
34's servo lands on the target — **a servo with a finite rate cannot teleport in zero time.** It
freezes to the SAME BITS as the `τ = Inf` head, so the `rate_max ≤ 0` ≡ `τ = Inf` identity arrives
from a THIRD direction; slice 34's row is untouched under the default (cap NaN ⇒ no limit) and is
asserted as such beside it. ⚠ The first draft of the tooth asserted slice 34's answer and FAILED —
the kernel was right and the test was wrong.

### ⚠⚠ THE BIT-IDENTITY CONTROL IS THE ABSENT KEY / `Inf`, NEVER `gimbal_rate_dps = 60` (advisor,
### blocking — and it constrains GATE 3, not gate 1)

The domain CEILING is measurably NOT inert: §0.2's peak demand is an identical **72.542 °/s** on
every arm (the tick-2 HANDOVER transient, and at `τ → 0` the step is the full error EVERY tick,
which is exactly where a cap bites), and §0.6's rate-60 row already reads `sat_band` 8.64 % with
`rms r` 0.88469 against the free 0.88465. An arm authored at 60 expecting `max|Δpos| = 0` would land
as a NEAR-MISS and read like a rounding residual in the new branch. Pinned as arithmetic in
`test_frames.jl` so gate 3 cannot author it.

### What gate 1 PROVED (and what it deliberately did not)

* **BIT-IDENTITY, three ways, 4 000 randomized cells each `===`**: the absent kwarg, `rate_max =
  Inf`, and a NON-BINDING FINITE rate all take the OLD CODE PATH — with the non-vacuity counter
  beside it (a limit BELOW the demand moved the answer in **4 000 / 4 000** cells).
* **The kernel half of the τ → 0 collapse**: with a non-binding limit PRESENT, the `τ ≤ dt` exact
  landing is still `=== (tgt_az, tgt_el)`. ⚠ **The WIRE half is gate 2/3's** — `missile.jl` is
  untouched here, so no flying arm can yet carry a `rate_max` at all.
* **Contraction survives the limit** — `n_grew == 0` over **16 000 cells across FOUR BANDS spanning
  `10^0.5 … 10^5` rad/s**, so it is not a property of one band. ⚠ **All four FLY IN THE SUITE**, not
  in a gate-1 probe: the first draft measured three of them in a temp file and quoted them here,
  which is precisely what slice 30 had to attribute ("gate 0 measured the same 0/7 across FIVE glass
  depths; the shipped verifier flies ONE"). ⚠ The COUNTER band is chosen and the reason is measured:
  a tighter one starves the STOP counter (1570 rate-bound vs only 156 stop-bound at `10^(0.5…3)`),
  and it is the **83 cells where BOTH bind** that pin the ORDERING in a sweep rather than in one
  constructed case.
* ⚠ **THREE TEST-INTEGRITY DEFECTS WERE CAUGHT AFTER THE FIRST GREEN RUN** (advisor, post-commit —
  slice 26's post-commit precedent). (a) The reverse-ORDERING tooth was a bare `!isapprox`, which
  passes whenever the two orders merely DIFFER and would survive a refactor making the shipped
  order wrong-but-different ⇒ BOTH orders are now pinned positively (`(25.000°, 10.000°)` shipped
  vs `(20.628°, 8.994°)` reversed, 4.4° apart). (b) The non-vacuity counter had a SEED-DEPENDENT
  hole: at a zero demand the half-demand limit is `cap = 0.0`, `0.0 > 0.0` is FALSE, the branch is
  inert, and the counter would fire on a cell where nothing is wrong — seed 3538 draws none, a
  reseed would ⇒ guarded on `dem > 0` with the live-cell count asserted beside it. (c) The
  four-band claim above.
* **RADIAL, not per-axis**, EXHIBITED differing on the diagonal (`√2·cap`) — `head_clamp`'s own
  tooth in the new quantity, and the same species argument. The direction of the demanded step is
  preserved EXACTLY while only its magnitude moves: the limit spends bandwidth, it does not re-aim.
* **The ORDERING is a measurement, not a comment** — the rate limit is radial about the HEAD and
  the stop radial about the ORIGIN, so the two orders are NOT the same map; the reverse order is
  exhibited giving a different head, which is what makes the pin meaningful.

### ⚠ THE RETURN SHAPE WAS SETTLED AT GATE 1 BECAUSE IT FIXES THE SIGNATURE (advisor)

Gate 2 must ship the pre-clamp DEMAND and the saturation FLAG, and the plan forbids reconstructing
them from a post-hoc difference of `:head_az`. The alternative — the seam re-forming
`wrap_angle(tgt − head)·gain/dt` and the `step > cap` comparison — is a SECOND IMPLEMENTATION of the
kernel, the trap `missile.jl` names for `off_axis_angle`, and here it is worse than cosmetic: a flag
built from a re-derived predicate can DISAGREE with the branch it claims to report, at the boundary
tick where the disagreement is least visible. ⚠ Widening `head_slew`'s return is OUT (~15 shipped
asserts and the seam depend on the `=== (t_az, t_el)` 2-tuple idiom), so the kernel is SPLIT:
**`head_slew_full` → `(az, el, demand, rate_sat)`** is the implementation and `head_slew` is its
first two elements, pinned over 2 000 cells. `demand` is a STEP in RADIANS, not a rate — `step/Δt`
at `Δt = 0` would manufacture a non-finite from finite input, so the division and the degrees belong
to the seam, where this family's unit conversions already live. ⚠ ONE caller today, and gate 2's
telemetry is the named second — `head_clamp`'s own story at slice 34's gate 1.

---

## §2 — Gate 2 (2026-08-09) — THE SEAM, THE LOADER, THE TELEMETRY, AND ONE FINDING

**Status: GATE 2 COMPLETE. Suite 6685 → 6874 (+189). Four edits and nothing else:**

* `scenario.jl` — `gimbal_rate_dps` joins the EXISTING `for hk in ("gimbal_stop_deg",
  "gimbal_fov_deg")` loop rather than growing a block of its own (one source, no drift). ⚠ Its name
  carries its UNIT where the other two do not, deliberately: they are ANGLES, where "deg" is the
  whole story, while a RATE has a time in it and `gimbal_rate_deg` would read as an angle. The seam's
  conversion is still a plain `deg2rad` — deg→rad is a pure scale factor and the seconds are
  untouched — and that is written down in both files, because a `deg2rad` on a per-second quantity
  reads like a units bug to the next reader.
* `missile.jl` seam — `head_slew` → `head_slew_full` with `rate_max = deg2rad(get(c,
  :gimbal_rate_dps, Inf))`. ⚠ **THE ZERO INITIALISER OF `head_dem`/`head_sat` IS LOAD-BEARING ON TWO
  PATHS**: the HANDOVER tick calls `head_clamp` and never slews, and a tick with the target outside
  the detector window HOLDS — both ship 0, so a zero is the ABSENCE of a slew and not a quiet servo.
* `missile.jl` telemetry — `head_rate_dps` (the demand, `rad2deg(dem)/dt`), `head_rate_sat` (the
  kernel's own branch predicate as a FLAG) and `gimbal_rate_dps` (the cap, so demand and cap are read
  in the same units off the same wire). ⚠ The `dt ≤ 0` degenerate is the SEAM's: it ships `0.0`
  rather than an `Inf` the `_finite` ceiling would then disguise as a real 1e9 °/s.
* `test_missile.jl` — the gate-2 testset, eight blocks.

### ⭐ WHAT THE WIRE CONFIRMED (and it confirmed gate 0 EXACTLY)

The shipped kernel reproduces every gate-0 number **to the digit**, which retires the worry gate 1's
Finding 1 opened — the probe patch's backwards polarity differs from the shipped `sat = dem > cap`
only for NON-FINITE caps, and every flying tick has a finite one. Band demand p95 off the SHIPPED
key: 2.468 / 1.663 / **0.600** / 32.155 / 48.536 / **60.831** at R̂ = −0.33 / −0.24 / −0.18 / −0.16 /
−0.12 / −0.03, identical to §0.2's finite-difference column.

⭐⭐ **AND THE PRE-LIMIT TOOTH IS SHARPER THAN THE PLAN EXPECTED.** The reason `head_slew_full` exists
is that a post-hoc difference of `:head_az` reads the CLIPPED motion — it would report the CAP as the
demand, i.e. report the answer as the question. Measured at R̂ = −0.03 / 8 °/s: demand p95
**214.958 °/s** against an achieved **8.000**, ~27×, and **on EVERY saturated tick the achieved step
is EXACTLY the cap** (max and min of the whole saturated set both 8.000000000, so it is the
distribution and not one lucky tick — and `cap`, not `√2·cap`, which is gate 1's RADIAL species
argument arriving on the wire). Where nothing binds the two methods agree to 1e−9, which is what
makes the disagreement a measurement rather than a units bug.

### ⚠⚠ FINDING — A RATE LIMIT MAKES THE **ACQUISITION TURN** THE BINDING REQUIREMENT, AND IT
### SETTLES THE KNOB COUNT

Gate 0 §0.4 named the acquisition confound and gated it away with the [500, 3000] m band. Gate 2
found what that gating COSTS: the band is what makes a tracking-error number attributable to the
LOOP, and it is therefore blind to the requirement that actually breaks the track.

| R̂ = −0.18 | `off_band` | `off_max` | r @ max |
|---|---|---|---|
| free | 1.956 | 1.956 | 533 m |
| 25 °/s | 1.986 | 4.023 | 6219 m |
| 15 °/s | 1.986 | **5.497** | **6062 m** |
| 8 °/s | 2.022 | **8.051** | **5662 m** |

The loop's requirement barely moves (1.956 → 2.022) while the whole-approach one triples, **out at
LAUNCH RANGE**. ⚠⚠ **AND IT IS THE MISSILE'S TURN, NOT THE LOOP'S** — the discriminator is a wire
with NO GLASS AT ALL, where `off_band` is a flat **0.031°** at every rate while `off_max` runs
2.112 → 7.223 → **12.346** at free / 15 / 8 °/s. Nothing is ringing; the body is simply rotating
faster than the servo can follow.

⇒ this is why `g2_knobs.jl` §C found slice 32/34's predicate **FALSE** on rate-limited arms (at
R̂ = −0.18 / 15 °/s a 2.20° window — comfortably above the 1.986° band requirement — BROKE 97.4 % of
the approach). **THE PREDICATE IS NOT THIS SLICE'S TO RE-SHIP**: on a rate-limited arm it is a
statement about the HANDOVER BASKET, which is slice 34's FIRST named deferral and a different slice.

⇒ **CONVENTION 9, MEASURED RATHER THAN ASSUMED (the plan's own instruction), AND THE EXPECTATION
HOLDS**: `gimbal_rate_dps` + `radome_slope_est` ship as the two knobs and **`gimbal_fov_deg` goes
AUTHORED AND WIDE** — not on §0.3's argument alone but on a number. A LIVE window would make this
wire's break an ACQUISITION break, i.e. §0.4's confound promoted to the headline and slice 34's own
lesson re-run as a third mechanism. **The window must clear 19.279°** — the worst whole-approach
requirement over the R̂ domain at the servo domain's FLOOR (8 °/s), measured across
R̂ ∈ {−0.36 … −0.03} and asserted in the suite.

⭐ **AND THE TWO SHIPPED KNOBS ARE ONE AXIS, WHICH IS WHAT CONVENTION 9 ACTUALLY ASKS** — the
`(rate, R̂)` grid, `off_band` on a free window:

| R̂ \ rate | free | 40 | 25 | 15 | 10 | 8 |
|---|---|---|---|---|---|---|
| −0.33 | 1.599 | 1.603 | 1.602 | 1.601 | 1.600 | 1.598 |
| −0.24 | 1.831 | 1.837 | 1.840 | 1.839 | 1.837 | 1.836 |
| −0.18 | 1.956 | 1.959 | 1.986 | 1.986 | 1.981 | 2.022 |
| −0.16 | 5.167 | 5.156 | 4.945 | 4.349 | 5.018 | 4.414 |
| −0.03 | 5.916 | 7.496 | 9.524 | 13.244 | 13.228 | 12.828 |

The rate knob's COST is charged by the ring, and the ring is what R̂ sets: FLAT across the whole rate
domain at slice 30's aim point, 2.17× at the boresight characterization. ⭐ **SLICE 30's RULE PAYS A
THIRD TIME** (33 = FOV, 34 = detector window, 35 = servo bandwidth) — aim R̂ at `radome_slope_worst`
and you may fly the cheapest servo in the catalogue. ⚠ The −0.16 row's NON-MONOTONICITY (§0.4)
reproduces exactly and nothing is built on it.

### ⚠ THE TWO CONDITIONS EVERY GATE-2 NUMBER CARRIES

1. **AN INFINITE DETECTOR WINDOW.** A rate-limited head LAGS, so slice 34's own 4°/8° window breaks
   it, the band EMPTIES and every column goes NaN. The first draft of the gate-2 probe ran at the
   inherited `fov = 8.0` and produced exactly that — `sat_band` NaN with `out` 60–97 %. Measured on a
   windowed arm the whole two-sided-knob block would report slice 34's frozen-index artefact instead
   of the servo. ⚠ This is the two-run discipline meeting its FOURTH quantity, as the plan predicted.
2. **NO GLASS *AND* NO WINDOW for the isolation.** The window is the head's OTHER channel to the
   trajectory, so leaving it at 8° measures channel 2. With both removed the isolation is
   **EXACTLY 0** at every rate from 60 down to 2 °/s (`max|Δpos| == 0`, miss `===` 0.19116 by
   identity) **while the head lags by 21.7°** — which is what makes the zero a measurement and not a
   dead knob. Slice 34's "exactly two channels", re-measured for the new knob as a column.

### The blocking pin that is now a POSITIVE fact

`rate = 60` is measurably NOT inert and the suite says so as a `>` rather than leaving it unsaid:
`max|Δpos|` 0.652 / 0.041 / 0.165 m at R̂ = −0.33 / −0.18 / −0.03, against an EXACT 0.0 for the
absent key and for `1e6`. Gate 3 cannot author the ceiling as a control.

Probe scripts: `M:\claud_projects\temp\slice35\` (`g2_seam.jl`, `g2_knobs.jl`, `g2_acq.jl`).

---

## What ships (gates 1–3, PLANNED)

### The core (gate 1)

* `frames.jl` `head_slew` gains a **defaulted keyword** `rate_max = Inf` (⚠ **ONE CALLER — do not
  split a kernel until it has two**; `head_clamp` earned its split by having two, and slice 34's
  docstring says so). The step is clamped **RADIALLY**, never per-axis — the same species argument
  as the circular stop and the circular window, since it must match the telemetry that reads it.
* ⚠⚠ **INERT BY BRANCH** (`step ≤ cap || …`, `head_clamp`'s own pattern), because slice 34's
  τ → 0 ⇒ `max|Δpos| = 0` strapdown collapse is a **BIT-IDENTITY control** carrying a refutation,
  and a rounding residual on that path would turn it into a near-miss. **Both must be proven**: an
  absent/`Inf` rate is bit-identical to slice 34, AND the τ → 0 collapse still holds with a
  NON-BINDING rate limit present.
* The degenerate table extends slice 34's: `rate_max ≤ 0` freezes the head (which by
  `off_axis_angle`'s identity is slice 34's `τ = Inf` reductio — pin that the two agree); a NaN
  `rate_max` degenerates to NO limit (convention 6: never manufacture a non-finite from finite
  input); the ordering rate-limit-then-`head_clamp` is pinned (the stop is the outer authority).

### The seam + loader (gate 2)

* Comp key **`gimbal_rate_dps`** — ⚠ a rate needs its unit visible, unlike the angle-valued
  `gimbal_stop_deg` / `gimbal_fov_deg`; deg/s at the YAML boundary, rad/s inside, converted ONCE.
* **INERT WITHOUT `gimbal_tau_s`, AND REFUSED RATHER THAN IGNORED** — the slice-31/34 posture
  already in `scenario.jl` for `gimbal_stop_deg`/`gimbal_fov_deg`; a rate limit on a strapdown
  seeker names a component that is not there.
* Telemetry: the **saturation flag** (§0.6's discriminator — the `aero_sat`/`defl_sat` shape, a
  FLAG the verifier reads and never a hand-rolled compare) and the **demanded rate**, both under
  the gimbal gate only (the never-stale rule). ⚠ The demand must be the pre-clamp step, so it is a
  seam quantity, not a post-hoc difference of `:head_az`.

### Convention 9 and the knob count (to be MEASURED at gate 2, not assumed)

Three live candidates — `gimbal_rate_dps`, `radome_slope_est`, `gimbal_fov_deg` — and convention 9
admits two only if the DIAGONAL shows they are one axis (slice 27's precedent, slice 34's practice).
**Expectation to be tested: rate + R̂ ship, and `gimbal_fov_deg` goes AUTHORED**, because after §0.3
the window is the *account* both bounds are charged to rather than an independent lesson.

### The domain (both endpoints already MEASURED, per slice 26's post-commit rule)

`gimbal_rate_dps ∈ [8, 60]`. **FLOOR 8**: below it the no-glass acquisition transient itself breaks
(§0.4: `off_band` 0.031 → 4.582 between 10 and 5 °/s) and the servo runs to 100 % saturation
(§0.6) — the floor is where the knob stops being a servo, and it is measured, not chosen.
⭐ **GATE 2 SHARPENED THAT JUSTIFICATION AND IT IS NOW THE SLICE'S OWN DISCRIMINATOR**: 8 °/s is
exactly where `sat_band` is **0.00 % on the shipped design and 97.14 % on the boresight-characterized
one** — one servo, two designs, a 0-vs-97 split. The floor is where the knob is simultaneously free
for a good design and binding for a bad one, which is a stronger reason than "it stops being a servo".
**CEILING 60**: the loudest arm's own band demand is 60.831 °/s (§0.2), so at 60 the limit is
already ~inert **ON THE METRIC** (`rms r` 0.88469 vs the free 0.88465).
⚠⚠ **"INERT ON THE METRIC" IS NOT "BIT-IDENTICAL", AND GATE 3 MUST NOT CONFLATE THEM** (gate 2, and
the suite now says so as a `>`): at 60 °/s the TRAJECTORY moves — `max|Δpos|` 0.652 / 0.041 / 0.165 m
at R̂ = −0.33 / −0.18 / −0.03 — because the cap clips the tick-2 HANDOVER transient, an identical
72.542 °/s on every arm. ⇒ **the free read for a BIT-IDENTITY control is the ABSENT KEY (or `Inf`),
never the domain ceiling.** The ceiling is the top of a knob's useful range; it is not a control.

### Class, the button, and the wire

**Class 4a** (the ELEVENTH consecutive RNG-live slice — a deterministic servo bound on an existing
measurement, 2 randn/tick, the seed load-bearing, conventions 3/11 apply). **KNOB, not rung** — to
be proven the way slice 34 proved its window: an absent key bit-identical to `Inf`. **Button
DROPPED** (the 11th), and slice 34's `gimbal_view` marker already exists and already routes this
wire, so unlike slice 34 this needs no new marker — ⚠ *to be re-checked at gate 3 against the
marker-hole class, which is exactly what slice 34's §3.0 was.*

### The four proofs (convention 14)

Unchanged in shape. ⚠ `STEPS` a multiple of `emit_every`. ⚠ **The two-run discipline now covers
FOUR quantities** — `rms r`, `head_off_deg`, `head_angle_deg` (slice 34's three) **plus
`sat_band`**, which reads 0 on a broken arm for the same reason `rms r` falls: a frozen head does
not saturate. ⚠ Check the discriminating quantity per-tick vs frame before trusting frames (slice
33's excursion was under-read by 0.016°).

---

## Deferred (NAMED)

* **THE HANDOVER BASKET as an authored quantity** — slice 34's first deferral, and §0.4 SHARPENS it:
  the acquisition transient is the largest slew demand in the whole engagement (~40 °/s against the
  ring's ~60) and it is entirely a property of how the head is handed over. A caged head would make
  it larger still. This slice gates it away with the band; that slice would make it the subject.
* **MEMORY TRACK / RE-ACQUISITION** — unchanged from slice 34, and every break measured here is
  still TERMINAL.
* **A SECOND-ORDER SERVO (ω_a/ζ_a)** — the head here is first-order-with-a-rate-limit; a real gimbal
  has an inertia and a bandwidth, and slice 15's actuator is the precedent for what that adds.
* **A RECTANGULAR / PER-AXIS STOP**, **THE HEAD'S OWN GYRO** — slice 34's, unchanged and unspent.
* Everything 26–33 named and did not spend.
