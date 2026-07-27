# Slice 25 — A SEEKER IN THE 6-DOF LOOP: the seeker that cannot see out of the plane (§11 Tier-A)

The THIRD slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag), and the arc's first **sensor** slice. It cashes a deferral slice 11 wrote
down in its own source — `missile.jl:1363`: *"Scalar avoids the vector form's tangent-injection /
cross-innovation-sign / renormalize bug surface"* — the same shape as slice 21 cashing constant-ρ and
slice 22 cashing linear `C_L(α)`.

**Status: GATE 0 COMPLETE (probes run 2026-07-27, `M:\claud_projects\temp\slice25_gate0\`).**

---

## The one-paragraph statement of the lesson

Since slice 19 the guidance command's out-of-plane component was DISCARDED by the autopilot, and
slice 23 killed that discard — `att` became a real quaternion, skid-to-turn made lift in two body
planes, and the out-of-plane target finally intercepted. But every one of those missiles was
**truth-fed**: PN read the target's true position and velocity. Give it a REAL seeker and slice 11's
sensor is waiting with the SAME approximation one layer up — it measures a SCALAR in-plane bearing
`λ = atan(Δz, Δx)` and reconstructs `ω = (0, −λ̇, 0)`, an LOS rate that is **structurally incapable of
having an out-of-plane component**. The 6-DOF airframe that slice 23 taught to turn out of plane is
never told to. **A two-angle (az/el) seeker measures the LOS direction in 3-D and reconstructs the
LOS-rate VECTOR `ω = û × û̇`; the in-plane seeker on the same wire flies straight down the x–z plane
and misses by the full cross-range offset.**

> **THE LESSON, IN ONE SENTENCE.** Slice 23 gave the missile an airframe that can turn out of the
> plane — but a seeker that only measures IN the plane produces an LOS rate with no out-of-plane
> component, so the missile never asks it to: the same 2000 m miss, from the SENSOR this time.

⚠ **The signature is IDENTICAL to slice 23's foil and the mechanism is NOT** — that is the whole
point, and it is also the copy-paste false-claim trap (see §4). Slice 23's `:pitch_coupled` missed
2002.37 with `max|y| = 0.0` because the AUTOPILOT threw the cross-range command away. Slice 25's
in-plane seeker misses 2000.04 with `max|y| = 0.0` on a plant that is FULLY CAPABLE of flying it —
the command was never FORMED, because the measurement had no such component to form it from.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⭐ THE RUNG — a new `:seeker_axes = (:pitch_plane, :az_el)`, INERT without its host block

`SEEKER_MODES = (:raw, :filtered, :scan)` stays UNTOUCHED — `:raw`/`:filtered` name the *tracker*
(finite-difference vs α-β) and `:scan` names the *profile* topology; NONE of them name the
measurement's DIMENSIONALITY, which is what moves here. Adding a 4th rung would force the button to
cycle through `:scan` (meaningless in this scenario) and would conflate two independent axes.

The **host** is the scenario's `seeker:` block: a missile authoring the two-angle seeker (a
`sigma_az`/`axes` key — gate 1 picks the spelling) runs the 2-draw path; a slice-11/13 missile runs
the untouched 1-draw / profile paths. `:seeker_axes` then selects only WHICH tracker consumes the
measurement. **On a slice-11 wire the key is INERT** (nothing reads it — the slice-13/14/21/24
inert-without-its-host shape), so `set_fidelity` needs **NO guard**: introducing it live cannot flip
a draw count that is gated on comp presence, not on the rung.

⚠ **That last sentence is the ONE claim gate 0 could not test against shipping code, and it is the
shape of this arc's two latent bugs** (slice 21's `_atm_on` firing a key-gated block on a frozen
state; slice 23's `build_env!` readout key-gated on `:att_q`, which is never deleted, firing stale
across a cross-toggle — BOTH caught by an advisor at gate 2, neither by reasoning at gate 0). It is
pinned NOW as **P11** (probe 4): on a slice-11 wire, `:seeker_axes` introduced live at t = 1.5 s
leaves the remaining trace **bit-identical (max |Δ| = 0.0 over 84 sampled state scalars)** and the
**next draw off `w.rng` identical** (stream in lockstep). Vacuous today — nothing reads the key —
which is exactly the point: **it becomes a `test_missile.jl` tooth at gate 2 so it FAILS LOUDLY if
the `:seeker_axes` read lands OUTSIDE the comp-presence gate.**

### 1b. ⭐ THE DISPATCH PRECEDENCE — decided explicitly, and one combination is a LOAD ERROR

`observe!` today is a two-way `rung === :scan ? _observe_scan! : _observe_point!`. A third path makes
two conditions simultaneously satisfiable, and **silent branch order is how a scenario runs and
teaches the wrong thing** (the slice-21 "stall × ρ(z) is a LOAD ERROR, refused rather than silently
branch-ordered" precedent). The decision, to be written in the source, not implied:

| scenario | `:seeker` | outcome |
|---|---|---|
| no 2-angle host | `:raw` / `:filtered` / `:scan` | UNCHANGED — slices 11/13 byte-identical |
| 2-angle host | `:filtered` | `_observe_point3d!`, α-β tracker — **the showcase** |
| 2-angle host | `:raw` | `_observe_point3d!`, finite-difference rates — reachable and DEFINED (§6 keeps it off the button, it is not a dead combination) |
| 2-angle host | `:scan` | **LOAD ERROR** — the slice-13 angular profile is IN-PLANE by construction (one λ axis); az×el CFAR is a named deferral, not a silent branch |

So `:seeker` (tracker) and `:seeker_axes` (dimensionality) are ORTHOGONAL on the host, with the one
meaningless corner refused at LOAD rather than ordered around.

### 2. ⭐⭐ THE 2-DRAW LOCKSTEP — the foil DRAWS the azimuth sample and DISCARDS it (convention 3)

The trap that would have killed the showcase: a two-angle seeker draws **2** `randn`/tick against
slice 11's **1**, so a naive `:filtered ↔ 3-D` rung toggle is a **draw-topology flip mid-replay** —
`set_fidelity` would have to REJECT the very switch the button exists to make (the `:cfar` 4b guard).

**Both rungs therefore draw 2 randn UNCONDITIONALLY, and `:pitch_plane` uses only `n_el`.** Gate the
VALUE, never the draw — `detect_once` / `_draw_pseudoranges` / `_draw_profile!`, the convention-3
template, now applied to a *foil* rather than to a geometry gate. **MEASURED (P9): 26000 draws over
13000 ticks on BOTH rungs, exactly 2.0/tick ⇒ the button is live-toggleable, class 4a within a
2-draw host.** Do NOT "optimize away" the unused draw — it IS the mechanism that makes the toggle legal.

⚠ **AND SAY SO IN THE SCENARIO HEADER: the foil is slice 11's TRACKER in a 2-draw host, NOT slice
11's seeker.** Because it consumes the RNG differently, `slice25 :pitch_plane` will NOT reproduce
`slice11 :filtered`'s realization on the same geometry — someone WILL compare them and find they
disagree. Written down, that reads as design; unwritten, it reads as drift.

### 3. THE LOS-RATE RECONSTRUCTION — `ω = û × û̇`, and it is the #1 SIGN TRAP's 7th occurrence

With `r = R·û`: `v = Ṙ·û + R·û̇` ⇒ `r×v = R²·(û × û̇)` ⇒ `r×v/R² ≡ û × û̇`. So the two-angle seeker's
ω is the SAME quantity `los_rate(rel_pos, rel_vel)` computes from truth — which makes truth an
EXACT ORACLE, not a calibrated one (convention 11's external anchor). With
`û = (cos el·cos az, cos el·sin az, sin el)`:

    ∂û/∂az = (−cos el·sin az,  cos el·cos az, 0)
    ∂û/∂el = (−sin el·cos az, −sin el·sin az, cos el)
    û̇ = ȧz·∂û/∂az + ėl·∂û/∂el ,   ω = û × û̇

**MEASURED (P1b): at σ = 0 with raw rates, `|ω_probe − ω_truth|` is 8.9e-5 RELATIVE after the init
ticks.** ⚠ The tick-1 error is 3.4e-2 — the α-β/finite-diff init seeds rates at 0 (slice 11's
`seek_init` shape). **Measure the oracle EXCLUDING the init transient or the tooth reads as a sign
error** (round 1 nearly did).

### 4. ⭐ THE ISOLATION — a POINTING miss, and it needed a RETUNE of slice 24's wire (advisor)

The arc has produced SIX ceiling misses (19/20/21/22/23/24). If slice 25's miss arrives with
`aero_sat` lit, it is unattributable — the ceiling absorbs the command error and the sensor lesson
is a claim, not a measurement. **Slice 24's wire is UNUSABLE as-is**: at ρ = 0.3 the ceiling floor is
~95 m/s², and PN's `N·Vc·λ̇` on a noisy bearing peaks `a_demand` at 2533 ⇒ `aero_sat` **93.9%** and a
miss of 1268 m in the arm that is supposed to HIT (P3/P4).

**The retune: ρ 0.3 → 1.0 and σ_seek 3 → 0.3 mrad.** Then (P9, the shipping A/B):

| arm | miss | max\|y\| | aero_sat |
|---|---|---|---|
| `:az_el` | **0.278 m** | 2621.6 | **0/7761 (0.0%)** |
| `:pitch_plane` | **2000.044 m** | **0.0 EXACTLY** | **0/8647 (0.0%)** |

**7182×, and `aero_sat` is 0 in BOTH arms** — the ceiling never binds, so the miss is a POINTING miss
(the slice-13 framing), NOT the seventh ceiling miss. This is the claim gate 3 must assert as a
NUMBER, not prose.

⚠ **THOSE ARE PER-TICK TRUTH NUMBERS AND THE 0.278 WILL NOT SURVIVE `emit_every = 16`.**
Frame-sampling error is ASYMMETRIC — a MISS samples faithfully (radial rate → 0 at CPA) but a HIT
samples COARSELY ([[ewsim-missile-verifier-sampling]]; slice 21's gate-3 bug #2 was exactly this:
pass text quoting per-tick truth while the file measured frames). Gate 3 must MEASURE the
frame-sampled ratio and quote **both, labelled** — the slice-24 form ("74× frame / 1614× per-tick"). ⚠ Slice 24's ρ = 0.3 was chosen so BTT's roll lag could visibly cost the
intercept; slice 25 needs the OPPOSITE (authority to spare). Same geometry, different flight
condition — say so in the scenario header rather than letting a reader assume the wires match.

### 5. THE PLANT IS HELD AT SKID-TO-TURN — `:steering` omitted, not authored (advisor)

`:bank_to_turn` binds `aero_sat` **93.2%** of its approach (slice 24's own measurement) vs **0.2%**
for STT. Layering seeker noise on a plant that is saturated 93% of the time makes §4's isolation
impossible. The showcase omits `steering:` entirely (the loader default IS `:skid_to_turn`), so
`:seeker_axes` is the ONE toggled fidelity (convention 9) and the button is unambiguous.

### 6. THE FILTER IS HELD TOO — `:seeker: filtered` both arms (convention 9)

A 3-D `:raw` arm re-runs slice 11's lesson in a new letter (at σ = 0.3 mrad and dt = 1e-3 the
finite-difference noise is σ/dt = 0.3 rad/s ⇒ `N·Vc·λ̇` ≈ 840 m/s² against a 317 ceiling — it
saturates and misses). That is a REAL effect and a DIFFERENT lesson; hold `:filtered` on both arms so
the ONLY variable is the measurement's dimensionality. Named deferral, not a refutation.

### 7. KNOBS — σ_seek is BOUNDED BY THE ISOLATION, not by the physics

**MEASURED (P10), the 3-D arm at ρ = 1.0:**

| σ (mrad) | 0.05 | 0.1 | 0.2 | 0.3 | 0.5 | 0.7 | 1.0 |
|---|---|---|---|---|---|---|---|
| miss | 0.235 | 0.243 | 0.260 | 0.278 | 0.127 | 0.103 | 0.057 |
| aero_sat | 0.0% | 0.0% | 0.0% | **0.0%** | 0.7% | 7.3% | 25.4% |

⚠ **σ_seek is NOT a lesson lever and must not be sold as one** — the miss does not degrade
monotonically in σ (it FALLS at 0.5–1.0 mrad while saturation climbs; the noise is exciting the loop,
not steering it). It is the REALISM knob, and its domain `[0.05, 0.3] mrad` is set by **where §4's
isolation survives**, exactly as slice 19's ρ domain was set by monotonicity rather than by physics
([[ewsim-df-ellipse-sigma-monotonicity]], 4th occurrence).

**NOT knobs, deliberately — and the list is the point, not an apology:** the α-β `β` gain — P8b
measures `β ≥ 0.15` breaking the isolation (19.6% at σ = 0.3, 80.5% at β = 0.4), the slice-11 U-shape
recurring, so it is an AUTHORED constant here; the target's cross-range `Y` (position is load-only —
the slice-21 DEAD-KNOB finding, 3rd occurrence); `k_alpha`/`k_q` (slice-19 FINDING 14); and **`rho`,
whose ISOLATED domain is only [1.0, 1.5]** — a 1.5× span (at ρ = 0.6 it is already 1.6% saturated at
σ = 0.3), which is narrower than a slider labelled "air density" implies, and it moves nothing the
lesson needs beyond the ceiling it must NOT touch. **Ship `sigma_seek` alone** (plus `af_alpha_max`
only if gate 1 finds it clean) and state the disqualifications in the scenario header — a knob whose
range is one-third of what its label suggests teaches a wrong intuition about the physics.

---

## Gate 0 — FINDINGS (run 2026-07-27; probes in `M:\claud_projects\temp\slice25_gate0\`)

- **P1b — the ω oracle: GREEN at 8.9e-5 relative** (§3). The reconstruction is the truth quantity;
  truth is an exact oracle. ⚠ Exclude the init ticks.
- **P2 — THE FOIL IS REAL, and it is not my reconstruction of it.** Slice 11's actual `Seeker`, on
  the slice-24 geometry, STT plant: **miss 2000.03, `max|y| = 0.0` EXACTLY**, at σ = 0 AND at
  σ = 3 mrad (2002.85). The truth-fed baseline on the same wire hits at 0.23 with `max|y| → 3393`.
  The collapse is STRUCTURAL, not noise-driven — which is why σ = 0 reproduces it.
- **P3/P4 — the retune was FORCED, not preferred** (§4). Slice 24's ρ = 0.3 gives `aero_sat` 93.9%
  and a 1268 m miss in the arm that must hit.
- **P6 — the tuning sweep** (ρ × σ, 16 cells): ρ ≥ 1.0 with σ ≤ 0.3 mrad is the isolated region.
- **P7 — the foil survives the retune** at every ρ tried (2000.035 / 2000.044 / 2000.055 at
  ρ = 0.6/1.0/1.5, `max|y| = 0.0` throughout). The foil cannot be tuned away — it is geometry.
- **P9 — the 2-draw lockstep VERIFIED** (§2): 2.0 draws/tick on both rungs; the headline A/B above.
- **P10 — the σ domain** (§7).
- **P8b — the α-β gains** (§7). ⚠ Round 2's β sweep was a PROBE BUG (the gains were never plumbed
  into the probe seeker and every row read identically) — re-run plumbed before it was believed.
- **P11 — the INERTNESS invariant** (§1, advisor item 1): `:seeker_axes` introduced live on a
  slice-11 wire leaves the trace bit-identical (max |Δ| = 0.0) and the RNG stream in lockstep.
  Vacuous today BY DESIGN; it ships as a gate-2 tooth against the latent-bug class that has now bitten
  this arc twice.

### ⭐ CANDIDATE (2) IS DEAD — "seeker noise × the BTT roll loop" (killed at gate 0, with numbers)

The framing I opened with — under `:bank_to_turn` the bank command is the `atan2` ARGUMENT of a noisy
accel vector, so LOS noise should become roll-command CHATTER — is **refuted by the bandwidth
separation the advisor predicted**. The ζ = 1 roll loop at τ_roll = 1.0 s is a ~1 rad/s corner
against noise that is white at dt = 1e-3: a ~1000:1 low-pass. **MEASURED (P5), BTT at τ = 1.0:**

| σ | std(Δφ_cmd) | std(Δφ_ach) |
|---|---|---|
| 0 | 0.084 | 5.5e-2 |
| 3 mrad | **1.070** | **1.6e-5** |
| 30 mrad | 1.002 | 1.7e-5 |

The command chatters by a full radian per tick and **the achieved bank angle does not move** — the
roll loop rejects it wholesale. Two further reasons it could not have been the headline anyway:
σ_seek = 0 is an in-domain slider value ⇒ **KNOB, not rung** (the `atmosphere.jl` discriminator), so
it cannot be the toggled fidelity convention 9 wants; and slice 24's gate 0 already engineered out
the 90°-singularity chatter (the nearest-representation law) — this would re-open a mitigated failure
mode. **Do not re-propose it cold** — the slice-20 dead-scalar-fin precedent: the general result
(a low-bandwidth actuator loop is a noise REJECTER, so "noise excites the actuator" needs the
bandwidths compared BEFORE the slice) is worth more than the slice would have been.

---

## Gates 1–3 (sketch — firmed by the gate-0 findings above)

**Gate 1 — the pure lib.** The two-angle kernels beside the existing seeker maths: the az/el
measurement pair, the per-angle α-β update (REUSING `alpha_beta_los_step` — no new tracker), and
`los_rate_from_angles` (the `ω = û × û̇` reconstruction of §3). Teeth: the truth oracle vs
`los_rate` (init excluded); the in-plane DEGENERATE case (`az ≡ 0 ⇒ ω_x = ω_z = 0` — the sign
invariant PAIRED with a does-turn case, the slice-24 shape); wrap behaviour at the ±π az seam;
`SEEKER_AXES_MODES` defined ONCE (convention 7).

**Gate 2 — the wired subsystem.** A `_observe_point3d!` **sibling** dispatched from `observe!`, with
`_observe_point!` left TEXTUALLY UNCHANGED and `n = randn(w.rng)` still its literal first statement
(the slice-13 `_observe_scan!` precedent — no value-branch inside the point path). `:seeker_axes` in
`LIVE_FIDELITY_MODES`; the §1b precedence table in the source and the `:scan` × host corner refused
at LOAD; **P11 promoted to a `test_missile.jl` tooth** (the inertness invariant, §1). ⚠ **The seed goes LIVE again — the first RNG-consuming missile slice since
13**, so `test_determinism` and the `_sample_z` absolute golden are back in force, conventions 3/11
APPLY, and the class flips **4c → 4a** after a 10-slice 4c streak (14–24).

**Gate 3 — the four proofs.** `scenarios/slice25_*.yaml` (slice 24's geometry, ρ = 1.0, STT held,
`:filtered` held); `slice25_verify.gd` asserting the A/B as numbers **plus `aero_sat == 0` in BOTH
arms** (§4 — the isolation IS the claim) and a held-seed bit-identical replay across the toggle;
`slice25_ui_test.gd` (the seeker-axes cycler + the slice-23/24 MIRROR value-guard — the airframe3d
view must keep ITS button on those wires); the Sandbox smoke-load; a windowed shot. ⚠ Re-run the
**23 and 24 verifiers** — the seeker CODE changes even though those scenarios carry no Seeker.

---

## Gate 3 — THE WIRE (measured on `scenarios/slice25_seeker_3d.yaml`, seed 25, via load_scenario→tick!)

| arm | miss (per-tick) | miss (frame @16) | max\|y\| | omega_oop max | aero_sat |
|---|---|---|---|---|---|
| `:pitch_plane` (default) | **2000.044** | 2000.071 | **0.0 EXACTLY** | **0.0 EXACTLY** | **0/8647** |
| `:az_el` | **0.008** | 9.555 | 2839.3 | 336.4 | **0/7760** |

**Ratio: 209.3× FRAME-SAMPLED / 258131× per-tick.** ⚠ **Quote the frame-sampled ratio and
"sub-metre per-tick" — NEVER the 258131×.** The per-tick figure is a lucky near-zero CPA on this
seed; the verifier sees FRAMES, and a hit samples coarsely. Pin CONSERVATIVE ONE-SIDED BOUNDS
(`:az_el` frame miss < 30, `:pitch_plane` > 1500), the slice-11 discipline — never the ratio.

**THE ISOLATION HOLDS ON THE SHIPPING WIRE: `aero_sat` is 0 in BOTH arms** (0/8647 and 0/7760) — a
POINTING miss, not the arc's seventh ceiling miss. ⚠ Note `a_demand` peaks at 356.1 against a 314.2
ceiling in the foil arm WITHOUT `aero_sat` firing: the flag keys off the ⟂-v PROJECTION while
`a_demand` is full-magnitude, so the sets NEST (slice-19's documented behaviour). **The verifier must
assert the FLAG, never a hand-rolled `demand > ceiling` compare.**

Replay is bit-identical on both rungs; the knob holds the isolation across its whole declared domain
(0/7761 saturated frames at 5e-5, 1e-4, 2e-4, 3e-4 rad); a σ pegged to 5 rad keeps every telemetry
value finite (convention 5/6).

---

## Named deferrals (write them down; do not let them leak into this slice)

- **The 3-D `:raw` arm** — slice 11's tracker lesson in az/el (§6). Real, measured to saturate at the
  showcase tuning, and a DIFFERENT lesson: convention 9 keeps it out.
- **Seeker noise × the BTT roll loop** — DEAD as a headline, with the bandwidth argument and the
  numbers recorded above. Revisit only if a roll loop is shown NOT to reject it.
- **RADOME / body-rate parasitic loop** — the arc's named end point, and slice 25 is its hard
  prerequisite: an error slope perturbs a TWO-ANGLE measurement as a function of look angle; there
  was nothing for it to perturb before this slice.
- **A seeker FOV / gimbal limit** — the two-angle measurement makes a look-angle constraint
  expressible for the first time (slice 13's ±FOV/2 was an in-plane window).
- **Monopulse / az×el CFAR** — slice 13's `:scan` profile lifted to two angular axes (its own named
  deferral, now with a 3-D host to land on).
- **Range/closing-speed measurement** — `Vc` stays TRUTH here, exactly as in slice 11 (§ scope: only
  the ANGLES are noisy). A measured `Ṙ` is its own slice.
- **The out-of-plane MANEUVERING target** (slice 24's route (b)) — unchanged, and it composes with
  this slice rather than competing: a moving out-of-plane target is what makes az-rate tracking hard.
