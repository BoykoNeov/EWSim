# Slice 16 — the 6-DOF airframe, FIRST HALF: pitch-plane rotational dynamics (§11 Tier-A)

**The DEFERRED rotational half of Tier-A's "6-DOF airframe + actuator/fin dynamics"** (slice 15 did the
actuator/fin half). This opens the committed **slice 16 → 17 → …** arc that recapitulates the ballistic→
autopilot→PN arc (slices 8→9→10) **for ROTATION**, one validated slice at a time, **frames/signs FIRST**.
Source of truth: HANDOFF §11 Tier-A + §10 item 8 (the force-integrator this mirrors) + §3 (the tick contract)
+ §1 (named approximations, the sign/units/frames trifecta). **COMPLETE — 2409 tests, four proofs green.**

## The scope (advisor-scoped) — pitch-plane rotational INTEGRATOR, isolated, open-loop

Slice 16 is the direct ROTATION analog of slice 8's ballistic force-integrator: slice 8 made `pos` a
force-integrated output; slice 16 makes `att` a **moment-integrated output**. It is deliberately narrow:

- **Pitch plane ONLY** (scalar θ, q — the minimal honest 1-D rotation; the 3-D quaternion+ω superset waits for
  bank-to-turn, the geometry.jl→frames.jl "2-D first" precedent).
- **OPEN-LOOP** — no guidance closes the fin δ (that is slice 17's inner α/g autopilot).
- **ISOLATED** — rotation reads the live flight condition (V, γ) but does NOT feed back into (pos, vel); no
  α→lift→γ coupling this slice. **The trajectory is BYTE-IDENTICAL across any Cmα** — only the attitude changes.

The dynamics: `M = QSd·(Cmα·α + Cmδ·δ + Cmq·q̄)`, `I·q̇ = M`, `θ̇ = q`, with `α = θ − γ`, `q̄ = q·d/(2V)`,
`Q = ½ρV²`. Closed-form anchors (V, γ frozen within a step): torque-free → q const; SHM ω_sp = √(−Cmα·QSd/I);
trim α_trim = −(Cmδ/Cmα)·δ; damping ζ = −Cmq·QSd·d/(4VIω_sp), log-decrement 2πζ/√(1−ζ²).

## THE LESSON — the static-stability SIGN (`Cmα`), the #1 trap

`Cmα` is the static stability derivative ∂Cm/∂α. **Cmα < 0 STABLE** (a nose-up perturbation makes a nose-DOWN
restoring moment → weathervanes / oscillates about trim, decaying under Cmq); **Cmα > 0 UNSTABLE** (the moment
reinforces the perturbation → tumbles, |α| diverges, no real ω_sp). The `af_cma` slider crossing 0 IS the
interactive lesson. A DOUBLE sign flip (of both the `α = θ−γ` definition AND the moment sign) oscillates at the
SAME ω_sp and passes a frequency-only test, so the moment SIGN is pinned DIRECTLY (advisor tooth #1), the
V/γ-frozen SHM is RK4-exact to ~1e-15 (tooth #2), and the damping test pins ζ via the log-decrement, not just
ω_sp (tooth #3 — a q̄ factor-of-2 slip leaves the frequency right but the damping wrong).

## The advisor-reconciled design decisions

- **NO `:airframe = point_mass | 6dof` fidelity (Option-P′).** The original instinct was to add the toggle. But
  slice 16 is ISOLATED → the path is bit-identical across it → a `:sixdof` rung would name a coupling it cannot
  produce until slice 17's α→lift. That is precisely the **convention-4c false-fidelity / dead-knob trap** (the
  slice-15 `k_δ`-cancellation precedent). Resolution: gate the rotational integrator on airframe
  **PARAMS-PRESENCE** (`haskey(c, :af_cma)` — the `:a_ctrl`-guard precedent, slices 8–15 byte-identical), and
  ship a handshake **`airframe_view`** marker (`_airframe_view_info`, the `range_axis_m`→cfar view-hint
  precedent) so the CLIENT recognizes the view and **drops the shared fidelity button** (nothing to cycle — the
  Cmα slider is the lesson lever). No core false-fidelity, no wrong-button fallthrough.
- **Class 4c** (physics-changing, NO RNG — truth-fed, no seeker → "draw-count invariance is VACUOUS"; the 3rd
  consecutive 4c after slices 14/15). Live-settable, no `set_fidelity` guard.
- **Structural freeze** (advisor): the rotational state (θ, q) lives in the comp bag (`:pitch_theta`,
  `:pitch_q`), NOT new Entity fields; `att` (already present) becomes the integrated output. The stepper
  `rk4_rot` takes the full (θ, q) state and an angular-accel closure, shaped so slice-17's JOINT [pos, vel, θ, q]
  step reuses the closure (the coupled airframe in ONE stepper, not two operator-split ones).
- **Crash-safety** (convention 5): `short_period_freq` returns NaN (not a DomainError throw) for Cmα ≥ 0;
  `trim_alpha` returns EXACTLY 0 at δ = 0 (no 0/0 NaN when a live slider crosses 0); the wire `_finite`-clamps
  NaN → FINITE_CEIL. Proven by a live-Cmα crash-safe sweep test.

## The three gates (as executed)

1. **`airframe.jl`** (pure, RNG-free, no LinearAlgebra) — `AirframeParams`, `pitch_moment`, `rk4_rot`,
   `airframe_step`, `short_period_freq`, `trim_alpha`; `test_airframe.jl` (the closed forms with the 3 teeth).
2. **`BallisticMissile.integrate!`** gains `_integrate_airframe!` (gated on `:af_cma`); phase-2 build_env! ships
   `pitch_theta/gamma/alpha/pitch_q/omega_sp/alpha_trim`; `scenario.jl` parses the `airframe:` block (Cma NOT
   sign-guarded — crossing 0 is the lesson). `test_missile.jl` (isolation bit-identical vs a no-airframe twin,
   sign lesson, att round-trip, crash-safe sweep).
3. **`scenarios/slice16_airframe.yaml`** (open-loop 40°/500 m/s climb, alpha0=0.15 kick, af_cma the sole knob,
   NO fidelity) + `_airframe_view_info` handshake merge + the Godot airframe view (button dropped; nose off θ vs
   a cyan velocity reference off γ, the gap labeled α). **Four proofs:** `slice16_verify.gd` (STABLE
   max|α|=0.150/ω_sp=2.40 real, REPLAY bit-identical, UNSTABLE max|α|→1e6/ω_sp=1e9 sentinel, **posdiff=0.0**);
   `slice16_ui_test.gd` (button HIDDEN, af_cma slider→set_param, reset keeps hidden); Sandbox smoke-load DONE;
   two contrasting windowed shots (stable α=3.2° nose≈v vs mild-unstable α=23.8° nose off v / ω_sp sentinel).

## Deferred (NAMED) — the slice-17 trigger and beyond

- **Slice 17 (NEXT) — the inner α/g autopilot + the α→lift→γ coupling.** This is where the real path-changing
  `:airframe` fidelity toggle LANDS: once α→lift exists, a stable Cmα gains a coupling for the toggle to name
  (the false-fidelity trap dissolves). The fin state δ banked by slice 15 feeds slice-17's moment equation. The
  headline lesson: **angle-of-attack-limited maneuverability** (the aerodynamic g-limit α_max → C_Lmax → a_max,
  distinct from slice-10's kinematic `a_max` clamp) — "even with the fins hard over, the airframe can only pull
  what α can generate."
- **Then:** bank-to-turn (the 3-D quaternion+ω superset), the radome/body-rate parasitic loop (needs body rates
  + a seeker), per-channel fin allocation / hinge-moment / stall, a 2nd-order actuator (ω_a/ζ_a).
- **CLIENT NOTE for slice 17:** the airframe branch is checked FIRST in `_setup_spatial_fid_btn`. When slice 17
  adds an `:airframe` fidelity alongside `af_cma`, `_airframe_view` will be true AND a fidelity present — so
  value-guard the branch then (else it hides the button slice 17 wants).
