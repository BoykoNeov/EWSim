# Slice 24 — BANK-TO-TURN + ROLL-LAG: the steering law that must bank before it turns (§11 Tier-A)

**Status: GATE 0 COMPLETE (2026-07-21). Findings below — the plan HELD on the `:steering` rung,
route (a) static geometry, and the gyro-include decision; ONE design change forced (the BTT command
is REVERSIBLE-LIFT with NEAREST-REPRESENTATION bank, not a naive ±90° flip), and one framing
correction (route (a) is the COLD-START face, not a refutation of the maneuver foil — route (b) is a
named deferral). Ready for gate 1.** The SECOND slice of the bank-to-turn / 3-D arc, on the 6-DOF
substrate slice 23 built. Scoped as the STT-first arc's payoff:

- **Slice 23 (done) — 6-DOF substrate + SKID-TO-TURN.** STT makes lift in BOTH body planes at once
  (α pitch + β yaw), roll held ≈ 0, ⟂-v lift points anywhere with NO roll → the out-of-plane target
  intercepts (miss 0.23 vs the `:pitch_coupled` discard's 2002).
- **Slice 24 (this plan) — BANK-TO-TURN + roll-lag.** Swap the autopilot: a SINGLE lift plane (α
  only, β driven → 0), ROLL to orient that plane at the demanded lift, FINITE roll bandwidth τ_roll.
  **HEADLINE: against the SAME out-of-plane target, BTT MISSES where STT HIT — because it must bank
  ~90° to point its lift cross-range and the roll can't get there in time.** Roll time-constant τ_roll
  is the knob. Both laws map to real airframe classes (STT = most tactical SAMs; BTT = ramjet /
  lifting-body / X-wing), so neither is an artificial idealization.

---

## The one-paragraph statement of the lesson

A skid-to-turn airframe (slice 23) makes maneuver lift in TWO body planes at once, so its ⟂-v accel
can point ANYWHERE off the velocity with no roll — it turns the instant the guidance command asks. A
BANK-TO-TURN airframe makes lift in ONLY ONE body plane (angle of attack α on the body pitch axis;
sideslip β is actively driven to ≈ 0 — *coordinated flight*). To turn in an arbitrary direction it
must first ROLL the body so that its single lift plane contains the demanded lift, and roll has a
FINITE bandwidth (a roll time constant τ_roll). Put the target out of the launch plane — the same
static cross-range geometry slice 23 used — and the missile launches wings-level: to pull its lift
cross-range it must roll ~90°, and while it is rolling its lift still points the OLD way. With a slow
enough roll it is still pointing lift wrong for a large fraction of a short terminal flight, so it
misses where the instantly-repointing STT plant hit. τ_roll → 0 recovers STT (both hit); τ_roll large
saturates toward the pitch-plane DISCARD miss (≈ the cross-range offset).

> **THE LESSON, IN ONE SENTENCE.** Skid-to-turn points its lift anywhere instantly; bank-to-turn must
> ROLL to point its single lift plane first — and with finite roll bandwidth the time spent banking
> is time not turning, so against an out-of-plane target BTT misses where STT hit. You must bank
> before you turn.

---

## Read these FIRST — the design decisions settled at gate 0 (measured, not assumed)

### 1. ⭐ THE `:steering` RUNG — a SECOND `:six_dof`-requiring fidelity key; `:airframe` HELD

Slice 23 §2 RESERVED `:steering` for exactly this. The mode taxonomy:

    STEERING_MODES = (:skid_to_turn, :bank_to_turn)      # exactly what slice-23 §2 named

- **Slice 24's A/B IS the NEW `:steering` cycler, with `:airframe === :six_dof` HELD.** Both laws run
  on the 6-DOF plant; the ONLY variable is the steering law. Default `:bank_to_turn` (the showcase
  OPENS on the MISS, the slice-23 discipline); cycle to `:skid_to_turn` and it HITS. There are now
  TWO `:six_dof`-requiring keys (`:airframe:six_dof` + `:steering`), so `:steering` is THE ONE toggled
  fidelity of the showcase and `:airframe` is authored/held (the slice-21/22 two-view-claiming-keys
  precedent — convention 9, one lesson per button).
- **THE CROSS-FIDELITY DEPENDENCY — WRITTEN DOWN, NOT IMPLIED (the slice-19 shape, now steering-on-
  airframe):** `:steering` is INERT without `:airframe === :six_dof`. The scalar `:pitch_coupled`
  plant has no roll DOF and no yaw lift; STT/BTT are meaningless there. `:steering` reaches a branch
  ONLY on the 6-DOF path (the third-conjunct gate, the slice-21 `_atm_on` / slice-22 `_stall_on`
  precedent). A slice-1..23 scenario never sets `:steering` → it defaults to `:skid_to_turn` → the
  STT path is TEXTUALLY VERBATIM → byte-identical.
- Class **4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" VACUOUS;
  the 10th consecutive 4c after 14–23; live-settable, NO `set_fidelity` guard — the
  `:integrator`/`:autopilot`/`:airframe` precedent). `STEERING_MODES` referenced ONCE by
  `LIVE_FIDELITY_MODES` (convention 7, one-list-no-drift).

### 2. ⭐ THE BTT COMMAND — REVERSIBLE LIFT with NEAREST-REPRESENTATION bank (gate-0 forced)

The plan's first sketch (a naive "bank to point +lift, α ≥ 0") is WRONG — gate-0 PROBE F/G killed it
in two ways, both the #1 SIGN TRAP's 6th occurrence:
- An IN-PLANE "pull down" command (demanded lift along −û_ref) asked for a **180° roll** instead of
  negative α → roll churn, out-of-plane drift (maxy → 387 m on an in-plane target).
- A hard ±90° bank LIMIT with an α-sign flip fixed that but made a PURE cross-range target (which
  needs ~90° bank) chatter at the ±90° reversal singularity → the missile never commits → misses ≈Y.

The correct law (standard robust BTT): lift along the demanded direction `L̂` can be made with **(bank
φ_L, α > 0) OR (bank φ_L ± π, α < 0)** — the SAME physical lift. Pick whichever bank is the SHORTER
roll from the CURRENT bank (nearest-representation), so an in-plane down-command flips α (no roll) and
a ~90° cross-range bank commits by continuity (no chatter). This needs the CURRENT attitude as input
(available in the decide arm — it already reads `:att_q`):

    steering_bank_command(a_cmd::Vec3, vel::Vec3, q::Quat, mass, p; alpha_max, q_floor) → (φ_cmd, α_cmd, L)
      a_perp = a_cmd − (a_cmd·v̂)·v̂;  L = |a_perp|;  L̂ = a_perp/L
      û_ref = normalize(ẑ − (ẑ·v̂)v̂)  (world-up ⟂ v = n̂_pitch at zero bank),  ŵ_ref = v̂ × û_ref
      φ_L = atan(L̂·ŵ_ref, L̂·û_ref)                            (bank to align +n̂_pitch with L̂)
      φ_now = current bank (n̂_pitch measured against û_ref/ŵ_ref)
      pick (φ_L, +1) vs (wrap(φ_L+π), −1) by MIN |wrap(φ_cand − φ_now)|
      α_cmd = clamp(sgn·L·m/(Q_eff·S·C_Lα), ±alpha_max)         (single-plane SIGNED magnitude, β≈0)

The α ceiling is the SAME `a_max_aero = Q·S·|C_Lα|·α_max/m` as slices 19/23 (β ≈ 0 ⇒ the resultant
IS |α|); BTT does not get more or less authority than STT — it just can't POINT it without rolling.
The α_cmd → δ_pitch inversion is the shipped `alpha_autopilot_delta` (slice 19); the yaw channel runs
`alpha_autopilot_delta(β_cmd = 0, β_ach, r_phys)` → δ_yaw, ACTIVELY driving β → 0 (coordinated flight;
gate-0 PROBE E: residual β_pk ~0.04–0.06 vs STT's COMMANDED 0.27). ⚠ **BTT is NOT "STT minus β_cmd"**
(advisor): rolling at α kinematically bleeds α into β, so the yaw loop must DRIVE β to 0, not merely
stop commanding it. Use `_AIRFRAME_Q_FLOOR` (not the probe's 100.0).

### 3. THE FINITE ROLL BANDWIDTH — a roll autopilot MOMENT, ζ = 1 the sole-lever approximation

The roll bandwidth lives in a MOMENT (M_x → ṗ → q̇ → bank), NOT a kinematic bank-angle lag — the
substrate-consistent choice (advisor). A critically-damped 2nd-order bank-angle controller:

    M_x = I_xx·( (1/τ_roll²)·wrap(φ_cmd − φ) − (2/τ_roll)·p )    (ζ = 1, ω_n = 1/τ_roll)

- ⚠ **ζ = 1 (critically damped) is the NAMED APPROXIMATION that makes τ_roll the SOLE lever**
  (§1 — a reviewer will ask why ζ isn't a second knob; it is FIXED so the miss is a clean function of
  one time constant). `I_xx` (roll inertia) MUST stay a NON-knob — it sits inside the roll-loop gain,
  so dialling it would confound τ_roll (the slice-19 FINDING-14 / slice-20 "disqualify the confounded
  knob" discipline).
- ⚠ **The STT roll damper `−c_roll·p` (slice 23) goes INERT under BTT** — the roll autopilot's
  `−(2/τ_roll)·p` term IS the damping. `c_roll` is read only on the `:skid_to_turn` path (byte-frozen).
- The roll autopilot reads φ_cmd (from decide, the `:delta_cmd` seam's sibling) and the STAGE bank/roll
  rate (the slice-17 stage-θ / slice-21 stage-z discipline). φ_cmd is a NEW comp key `:phi_cmd`.

### 4. THE GYROSCOPIC ω×Iω TERM — INCLUDE (measured immaterial at BTT's real roll rates)

The load-bearing gate-0 question (advisor #1): BTT ROLLS (p ≠ 0 by construction), so the ω×Iω term
that slice-23 P6 measured at EXACTLY 0.0 (p ≈ 0) goes LIVE. With diagonal I (I_yy = I_zz), the pitch
axis gets ≈(I_zz−I_xx)·r·p/I_yy and yaw ≈ −p·q — first-order in the rates, and the cross-coefficients
are NOT small (~0.9). **Gate-0 PROBE D2 measured it on the clean static engagement:** on the
lesson-carrying misses (τ_roll ≥ 0.6) the term shifts the CPA by ≤ 3.1% (1.3% at the showcase τ = 1.0),
though the gyroscopic MOMENT peaks ~155 N·m during fast roll (p_pk up to 11). ⇒ **INCLUDE it** (correct
rigid-body form, cheap, already in `body_rate_deriv`) — the "roll lag" story is NOT confounded by
inertial-coupling departure. ⚠ **ATTRIBUTE IT RIGHT (advisor):** it is immaterial because the RATES
stay small under COORDINATED flight in the slow-roll (miss) regime — NOT because the diagonal-I
cross-coefficients are small (they are ~0.9). At fast roll the term is large but the flight is too
short to matter and BTT hits there anyway. The AERO + INERTIAL CROSS-COUPLING that MATTERS (non-diagonal
I, large sustained p, Clβ/Cnp/Clr, the radome/body-rate parasitic loop) stays the DEFERRED departure
lesson (slice 23 §4).

### 5. THE SHOWCASE GEOMETRY — route (a) static cross-range (the COLD-START face)

Reuse slice 23's exact geometry: a STATIC aero-free target at cross-range +Y = 2000, ρ = 0.3, the
6-DOF interceptor launched wings-level in the x–z plane. ⚠ **This is the COLD-START face of "bank
before you turn," NOT a refutation of the maneuver foil (advisor):** the missile launches wings-level
and must roll ~90° to point lift cross-range; with finite bandwidth it is still pointing lift the OLD
way for a large fraction of a short flight (gate-0 maxy: BTT reaches 2400–2818 of STT's 2924 — it DOES
turn, just LATE). It is CLEAN and confound-free (no target motion, reuses the slice-23 client view),
and DISTINCT from the SUSTAINED-TRACKING face (a maneuvering demand rotating faster than the roll loop
follows) — slice-23 §5's route (b), now a NAMED DEFERRAL, not "the prediction was wrong." Both are
real BTT physics. ⚠ The cold-start miss scales with flight-time / τ_roll (roll settling ~4–5·τ_roll
against a ~9 s flight) — fine for a FIXED showcase, but **the lesson lives in the geometry**: do NOT
add a range/speed knob that lengthens the flight and evaporates it (the slice-19 dead-`speed`-knob /
slice-21 dead-launch-altitude discipline — position/speed are load-only, `reset` reloads the YAML).

### 6. TELEMETRY & READOUTS — additive, gated on `:bank_to_turn`, `_finite`-clamped

New BTT readouts (RUNG-gated on `:steering === :bank_to_turn` so slices 16–23 wires are byte-identical,
the slice-23 six_dof-block precedent — RUNG-gated NOT key-gated, the `_atm_on` latent-bug class):
`bank_deg` (the achieved bank φ, the client's roll indicator), `phi_cmd`, `delta_yaw` (already shipped),
and the roll rate `omega_p` (already in the six_dof block). All SCALARS (convention 13, no Array), all
`_finite`-clamped (convention 6). The bank angle rides the shipped quaternion — no new NaN path.

---

## Gate 0 — FINDINGS (run 2026-07-21; probes in `M:\claud_projects\temp\slice24_gate0\`)

Throwaway probes (`btt_kernels.jl` + `probes{,2,3}.jl`) — a self-contained closed-loop STT/BTT 6-DOF
simulator REUSING the shipped kernels (frames.jl quaternion, airframe3d.jl `body_perp_axes`/
`body_incidence`/`lift_accel_3d`/`rk4_6dof`/`attitude_kinematics`, guidance `pn_accel`/`clamp_accel`,
airframe.jl `alpha_autopilot_delta`) so the probe exercises the code that informs gate 1. Nothing
touched a source file. **All findings below; the plan HELD on route (a)/`:steering`/gyro-include, with
the BTT-command law CHANGED (nearest-representation) and the framing CORRECTED (cold-start, not
refutation).**

### ⭐ THE BTT COMMAND LAW — nearest-representation reversible lift (the design change)
The naive law churns (PROBE F) or chatters at 90° (PROBE G); the nearest-representation law (§2) fixes
BOTH. After the fix: in-plane invariant EXACT (§below), knob monotone and saturating (§below), showcase
decisive (§below). This is the load-bearing gate-1 spec.

### PROBE F — the BANK-ANGLE SIGN structural invariant: GREEN AT THE FP FLOOR (#1 SIGN TRAP's 6th)
IN-PLANE target (Y = 0): BTT keeps `max|p| = max|pos_y| = max|β| = EXACTLY 0.0` and hits 0.242 (= STT
0.242) at every τ_roll. The bank/α sign pair is wired right — nothing leaks out of plane, no spurious
roll. ⚠ **PAIR IT WITH THE COMPLEMENT (advisor):** a law that NEVER rolls also passes this, so gate 1
also pins the DOES-ROLL tooth — out-of-plane target ⇒ BTT genuinely rolls (maxy grows, p ≠ 0,
bank → ~90°, α carries the demand). Both teeth in `test_airframe3d.jl`.

### PROBE G / H — the KNOB DOMAIN and the SHOWCASE A/B (monotone, saturating, decisive)
τ_roll sweep (static Y = 2000, ρ = 0.3): 0.05→0.064 (≈ STT), 0.1→0.256, 0.3→0.60, 0.6→33.6, 0.8→60.9,
1.0→**371.8**, 1.5→1530, 2.0→1535, 4.0→1985 — MONOTONE-increasing and SATURATING toward ≈Y = 2000 (the
pitch-plane DISCARD limit: at large τ the missile can't roll → never turns → misses ≈Y), NO reversal.
⚠ A tiny dip at 0.2→0.3 (0.834→0.604, both sub-meter HITS — FP/sampling noise): **pin monotonicity
only ABOVE the sub-meter hitting region** (advisor — else a tooth fails on a green run). SHOWCASE:
**STT 0.23 vs BTT τ_roll = 1.0 → 371.8 m (1614×)**, and BTT still visibly TURNS (maxy 2818 of 2924).
τ_roll = 1.0 is the LOAD-BEARING showcase default (a 1-s roll time constant — exaggerated for teaching,
the slice-20 K / slice-21 H precedent). Knob domain `af_tau_roll ∈ [0.1, 2.0]` (the monotone region).
⚠ Frame-sampling ASYMMETRY: BTT-372 samples faithfully, STT-0.23 coarsely ([[ewsim-missile-verifier-sampling]])
— LOS-gate ABOVE the largest CPA and quote frame numbers.

### PROBE B — τ_roll → 0 RECOVERS STT (the causation license)
BTT τ_roll = 0.005 (≈ instant roll) → CPA 0.11 ≈ STT 0.23 (both HIT). The single-plane lift pointed
instantly via bank produces the same ⟂-v vector as STT's two-plane resultant. This is the causation
proof (the slice-19 α_max-recovery / slice-23 reduction-golden analog): the MISS is caused by the roll
LAG, because removing the lag removes the miss. (p_pk = 118 at τ = 0.005 — instant roll means huge
transient roll rates, but it works.)

### PROBE D2 — the GYROSCOPIC ω×Iω term: IMMATERIAL, INCLUDE (§4). Measured, not assumed.

### PROBE E — β REGULATED → 0 under BTT (coordinated flight, NOT "STT minus β")
BTT β_pk ~0.04–0.06 at the showcase τ (vs STT's COMMANDED β_pk = 0.27). The yaw loop
(`alpha_autopilot_delta(0, β, r)`) actively drives the kinematic α→β roll-bleed back to 0. The residual
is a regulated disturbance, uncommanded — the "single lift plane" story holds.

### NET — what changed / what to carry into gate 1
- **Confirmed (plan held):** the `:steering` rung (§1), route (a) static geometry (§5), INCLUDE ω×Iω
  (§4), ζ = 1 sole-lever roll loop (§3), C_Yβ = C_Lα symmetric default (unused-ish — β ≈ 0).
- **Changed (gate-0 forced):** the BTT command is NEAREST-REPRESENTATION reversible lift (§2), not a
  naive ±90° flip. Needs the current attitude.
- **Corrected (framing):** route (a) is the COLD-START face; route (b) (sustained-tracking, an
  out-of-plane MANEUVERING target) is a NAMED DEFERRAL, not a refutation (§5).
- **New for gate 1:** the DOES-ROLL complement tooth (PROBE F pairing); pin monotonicity above the
  sub-meter region; use `_AIRFRAME_Q_FLOOR`.

---

## Gates 1–3 (sketch — firmed by the gate-0 findings above)

**Gate 1 — the pure lib.** Extend `airframe3d.jl` (the 6-DOF home) with:
- `steering_bank_command` (§2) — the nearest-representation reversible-lift BTT inversion. Reuses
  `body_perp_axes` for the ⟂-v frame; a NEW `bank_angle(q, vel)` helper (n̂_pitch vs the û_ref/ŵ_ref
  reference frame) that the command AND the readout share (convention 7, sign in one place).
- `btt_roll_moment(φ, φ_cmd, p, I_xx, τ_roll)` (§3) — the ζ = 1 bank-angle autopilot moment; and a
  `btt_moments` sibling of `stt_moments` (pitch/yaw identical, roll = the autopilot not the damper).
- `STEERING_MODES = (:skid_to_turn, :bank_to_turn)` (grow the ONE tuple — convention 7).
- **Tests (teeth, convention 11):** the in-plane invariant (PROBE F — p/pos_y/β at the FP floor) AND
  the DOES-ROLL complement (out-of-plane ⇒ rolls, bank → ~90°); τ_roll → 0 recovers the STT resultant
  DIRECTION (the command produces the same ⟂-v lift vector as `steering_command` when bank is free);
  the nearest-representation SELECTION (an in-plane down-command flips α, does NOT roll 180°; a ~90°
  bank commits, no chatter); the roll-moment sign (a +Δφ error drives p the right way); β_cmd = 0.

**Gate 2 — the wiring.** `_integrate_6dof!` gains a `:steering === :bank_to_turn` branch choosing
`btt_moments` (roll autopilot) over `stt_moments` (damper) — the `:skid_to_turn` arm TEXTUALLY VERBATIM
(slice 23 byte-frozen); the `:alpha` decide arm's `:six_dof` case gains a BTT sub-branch calling
`steering_bank_command` → (α_cmd → δ_pitch, β_cmd = 0 → δ_yaw, φ_cmd) written to comp; `build_env!`
gains the gated `bank_deg`/`phi_cmd` readouts (§6). `radar.jl` `LIVE_FIDELITY_MODES` grows
`steering = STEERING_MODES`. `scenario.jl` loads/validates `steering:` and `tau_roll` (τ_roll > 0,
finite — convention 5). Class **4c**. ⚠ **INERTNESS:** `:steering` inert without `:airframe:six_dof`
(§1 third-conjunct); the STT/`:skid_to_turn` path and every slice-16..23 wire byte-identical; the roll
autopilot MUST NOT reach the `:point_mass`/`:pitch_coupled`/STT paths (the slice-22/23 "the moment
reaches further" warning). Tests +N in `test_missile.jl` incl. the byte-identity + cross-toggle.

**Gate 3 — the four proofs** (convention 14): `slice24_verify.gd` (the STT-hits / BTT-misses split
against the SAME static out-of-plane target + the τ_roll → 0 RECOVERY causation lever [instant roll
recovers the STT hit] + held-seed bit-identical replay across the `:skid_to_turn ↔ :bank_to_turn`
toggle); `slice24_ui_test.gd` (the NEW `:steering` cycler, value-guard vs the slice-23 airframe cycler
/ slice-18 terrain view / slice-16 2-D view — the multi-view discriminator, newest key first; all
prior UI tests re-run); the `Sandbox.tscn` headless smoke-load; a windowed shot aimed at the CLAIMED
branch (BTT ROLLING then lagging — the banked airframe still pointing lift the old way while STT flies
the intercept). ⚠ Watch-items: `%.2e` is not a GDScript specifier (slice-21/22 silent-`%` failure);
frame-sampling ASYMMETRY (BTT misses faithfully, STT hits coarsely); magic-multiple teeth pin against
MEASURED values (τ_roll = 1.0 → 372 m). REUSE slice 23's 3-D SubViewport airframe view (the bank is a
NEW thing to draw — the nose rolled about the velocity).

---

## Named deferrals (write them down; do not let them leak into this slice)

- **SUSTAINED-TRACKING / route (b) — the out-of-plane MANEUVERING target** (slice-23 §5's foil). The
  cold-start face (this slice) shows the launch-transient roll lag; the sustained face shows a demand
  ROTATING faster than the roll loop follows. Real BTT physics, DISTINCT, and a cleaner story only
  once a maneuvering out-of-plane mover exists (generalize `ManeuveringTarget` to a tilted turn plane
  — gate-0 confirmed a naive version breaks target reachability; its own careful build). Its own slice.
- **AERO + INERTIAL CROSS-COUPLING / DEPARTURE** (slice-23 §4, unchanged) — non-diagonal I, large
  sustained p, Clβ/Cnp/Clr, the radome / body-rate parasitic loop. Gate-0 confirmed the DIAGONAL-I
  ω×Iω term is immaterial here (coordinated flight, small rates in the miss regime); the departure it
  can cause under a hard sustained roll with cross-derivatives is the later lesson.
- **ζ ≠ 1 / a 2nd roll knob, a 2nd-order roll ACTUATOR, per-fin roll allocation** — the roll loop is
  critically damped with τ_roll the sole lever (§3). A real roll autopilot's damping ratio and
  actuator lag differ.
- **ASYMMETRIC AERO** (C_Yβ ≠ C_Lα), **a SEEKER in the 6-DOF loop** (flips to 4a/RNG-live),
  **induced/separation drag + ρ(z) on the 6-DOF path** — slice-23 deferrals, unchanged.
