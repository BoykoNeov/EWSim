# Slice 23 — 6-DOF SUBSTRATE + SKID-TO-TURN: the out-of-plane engagement (§11 Tier-A)

**Status: GATE 0 COMPLETE (2026-07-20) — findings below; plan HELD on P4/P6/route, one mild
refutation (P1b). Ready for gate 1.** The FIRST slice of the
bank-to-turn / 3-D arc — the 3-D quaternion+ω superset where "the pitch-plane out-of-plane
discard finally dies" (HANDOFF §11, and the sharpest remaining approximation named at the close of
slice 22). Scoped STT-first as a **2-slice arc** (user decision, 2026-07-20, advisor-recommended):

- **Slice 23 (this plan) — 6-DOF substrate + SKID-TO-TURN.** Real quaternion+ω attitude
  (moment → ω̇, diagonal inertia), genuinely 3-D guidance (the discard dies), an STT autopilot:
  cruciform 2-plane lift (α pitch + β yaw), roll held ≈ 0, ⟂-v lift points anywhere with no roll.
  **HEADLINE: the out-of-plane engagement — unflyable-BY-CONSTRUCTION since slice 19 — now
  intercepts.** Front-loads the hard substrate.
- **Slice 24 (deferred, its own plan) — BANK-TO-TURN + roll-lag.** Same substrate, swap the
  autopilot: single lift plane (α only, β ≈ 0), roll to orient, finite roll bandwidth. **HEADLINE:
  against the out-of-plane maneuver, BTT misses where STT hit — "you must bank before you turn."**
  Roll time-constant is the knob.

Both map to real airframe classes (STT = most tactical SAMs; BTT = ramjet / lifting-body), so
neither is an artificial idealization. As-built detail will land in `docs/STATUS.md` per gate.

---

## The one-paragraph statement of the lesson

Slices 16–22 built a complete pitch-plane airframe — the missile makes its maneuver g from **lift
in ONE plane (the x-z plane)** and can only pull ⟂ v *within that plane*. `alpha_command` (slice
19) makes this explicit: it PROJECTS the guidance command onto the in-plane direction
`n̂ = (−sin γ, 0, cos γ)` and **DISCARDS the out-of-plane component** (slice 19 §1, in code at
`airframe.jl:589`). A target maneuvering out of the x-z plane is therefore *unflyable by
construction* — a stated approximation the whole arc has carried. Slice 23 cashes it: `att`
becomes a genuine 3-D quaternion integrated from a body-rate vector `ω = (p, q, r)`, the guidance
command keeps its full 3-D direction, and a **skid-to-turn** autopilot makes lift in BOTH body
planes at once (angle of attack α → pitch lift, sideslip β → yaw lift), so the ⟂-v accel can point
anywhere. Put the target OUT of the x-z plane and the contrast is the headline: the old
`:pitch_coupled` plant misses it WIDE (the discard), the new `:six_dof` STT plant TURNS to it and
intercepts.

> **THE LESSON, IN ONE SENTENCE.** A pitch-plane airframe can only pull g in the plane it is
> already in; a real interceptor turns in 3-D. Skid-to-turn does it by making lift in two body
> planes at once — and the out-of-plane target that was unflyable by construction becomes a hit.

---

## Read these FIRST — the design decisions settled while planning (subject to gate 0)

### 1. ⭐ THE PARALLEL 3-D BRANCH IS FORCED, NOT A PREFERENCE (advisor, load-bearing)

The scalar `(θ, q)` path (`comp[:pitch_theta]`/`[:pitch_q]`, read by FOUR sites:
`_integrate_coupled!`, `_integrate_airframe!`, `build_env!`, the `:alpha` arm of `decide!`)
**CANNOT be refactored into a quaternion representation.** `qmul`/`qnormalize`/`rotate` (frames.jl)
carry a `sqrt` and a different multiply grouping, and will NEVER bit-reproduce the scalar
`rk4_coupled` step. This project catches 1-ULP desyncs against absolute goldens (`√(snr/2)` vs
`√snr·√½`, twice). So:

- Slices 16–22 must keep hitting the **verbatim scalar code**. `:six_dof` is a NEW rung reaching a NEW
  branch `_integrate_6dof!`, gated so it is unreachable without BOTH `:af_cma` present AND
  `:airframe === :six_dof` (the `_integrate_coupled!` gate shape). `_integrate_coupled!` /
  `_integrate_airframe!` / the `:alpha`+`:pitch_coupled` arm stay **TEXTUALLY VERBATIM**.
- NEW comp keys: `:att_q` (a `Quat`) + `:omega_body` (a `Vec3` body-rate) — PARALLEL to
  `:pitch_theta`/`:pitch_q`, never replacing them. A slice-16–22 scenario never sets
  `:airframe === :six_dof`, never grows these keys → byte-identical by construction.
- **The reduction proof (roll = yaw = 0 ⇒ 6-DOF reproduces the pitch plane) is a GOLDEN with
  `atol`, NOT `==`** (advisor — the goldens impose this, it is not a choice): quaternion-RK4 and
  scalar-θ-RK4 are DIFFERENT SCHEMES for the same ODE, so they diverge FAR ABOVE ULP (different
  truncation + `qnormalize` projection) — the atol comes from a dt-convergence study, not a ULP
  budget (P1b). The TIGHT ~1e-15 check is the separate out-of-plane structural invariant (P1a). Same
  loose status as the decoupled-limit tests (`rk4_coupled` with `C_Lα = 0` reproducing
  `airframe_step`). The byte-identity claim is ONLY about slices 16–22 (which never reach the
  branch), never about 6-DOF-vs-scalar.

### 2. ⭐ THE MODE TAXONOMY — `:airframe` GAINS `:six_dof`; `:steering` IS SLICE 24's

`:airframe` today is `(:point_mass, :pitch_coupled)`. Slice 23 adds a THIRD rung:

    AIRFRAME_MODES = (:point_mass, :pitch_coupled, :six_dof)      # exactly what HANDOFF §11 names

- **Slice 23's A/B IS THE EXISTING `:airframe` CYCLER** — no new fidelity key. Against an
  out-of-plane target, `:pitch_coupled` (the discard) misses WIDE and `:six_dof` STT intercepts. The
  client already cycles `:airframe`; the button gains one rung. (Convention 9: ONE toggled fidelity.)
- **STT is the ONLY steering law in slice 23.** There is NO `:steering` fidelity yet, because there
  is nothing to A/B it against — the KNOB-vs-RUNG discriminator and slice 16's precedent (refuse a
  toggle you cannot contrast). Slice 24 introduces `:steering = (:skid_to_turn, :bank_to_turn)` as
  ITS lesson-rung, both on the `:six_dof` plant. Writing `:steering` now would be the false-fidelity
  trap (a rung naming a distinction the slice cannot show).
- ⚠ **The `:six_dof` rung is DELIBERATELY DISTINCT from `:pitch_coupled`, not a rename** — advisor's
  "you can't rename `:pitch_coupled`". Both remain, both are byte-frozen for their own scenarios.

Class **4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" is
VACUOUS; the 9th consecutive 4c after 14–22; live-settable, NO `set_fidelity` guard — the
`:integrator`/`:autopilot`/`:apn`/`:cooperation`/`:airframe` precedent). Referencing
`AIRFRAME_MODES` from `LIVE_FIDELITY_MODES` is already wired (radar.jl:219) — the tuple just grows.

### 3. THE DISCARD'S CODE HOME — a NEW `steering_command`, NOT a retrofit of `alpha_command`

"The discard dies" is precisely the removal of `alpha_command`'s projection-and-throw-away
(`a_perp = dot(a_cmd, n̂)`, scalar, `airframe.jl:589`). But `alpha_command` is the byte-frozen
scalar path slices 19–22 use — **do NOT retrofit it.** Write a NEW 3-D command in the parallel
path:

    steering_command(a_cmd::Vec3, vel::Vec3, att::Quat, mass, p; alpha_max, beta_max, q_floor)
        → (α_cmd, β_cmd, sat)

The STT generalization (verified viable while planning — same scalar inversion, twice):
1. Project `a_cmd` onto the plane ⟂ v: `a_perp3 = a_cmd − (a_cmd·v̂)·v̂` (the along-v̂ component is
   unproducible by any airframe — the SAME truth `alpha_command` used, now kept as a 3-D vector
   instead of collapsed to a scalar).
2. Resolve `a_perp3` onto the two BODY ⟂-v axes — the body pitch axis (→ α, lift via `C_Lα`) and
   the body yaw axis (→ β, side-force via `C_Yβ`). With roll ≈ 0 these are well-defined and
   `rotate`/`rotate_inv` (frames.jl) map between body and inertial.
3. Invert each independently: `α_cmd = a_pitch·m/(Q·S·C_Lα)`, `β_cmd = a_yaw·m/(Q·S·C_Yβ)` — the
   `alpha_command` scalar inversion run on two orthogonal axes. Same `_AIRFRAME_Q_FLOOR`,
   `_AIRFRAME_DENOM_FLOOR`, and `C_Lα<0` self-consistency (slice-19 FINDING 9) carry over per axis.
4. `sat` per axis where the raw inversion exceeds `±α_max` / `±β_max` (the aero ceiling binding —
   the slice-19 tell, now 2-plane). ⭐ **GATE-0 QUESTION: is `a_max_aero` still the single-axis
   `Q·S·|C_Lα|·α_max/m`, or the 2-plane resultant?** A cruciform airframe pulling α AND β at once
   has a resultant ceiling that is NOT simply the pitch-axis one. Measure it; do not assume it.

⚠ `C_Yβ` (yaw side-force slope) is a NEW aero coefficient. Default it to `C_Lα` (a symmetric
cruciform airframe — pitch and yaw are interchangeable), a §1 named approximation; a real airframe's
differ. This is the ONLY new authored aero constant slice 23 adds.

### 4. THE 3-D RIGID-BODY DYNAMICS — diagonal inertia, and NAME the ω×Iω deferral

The attitude kinematics and the body-rate dynamics:

    q̇   = ½ · q ⊗ [0, ω_body]                          (quaternion kinematics — frames.jl qmul)
    ω̇   = I⁻¹ · (M_body − ω × (I·ω))                   (Euler's rigid-body equation)

- **`I` is DIAGONAL** `(I_xx, I_yy, I_zz)` — roll inertia `I_xx ≪ I_yy = I_zz` (roll is fast; a
  slender missile). `I_yy` reuses the scalar path's `:af_I` (pitch inertia); `I_xx`, and `I_zz = I_yy`
  by symmetry, are new (or defaulted from `I_yy`). The pitch channel's moment reuses `pitch_moment`'s
  physics (`Cmα·α + Cmδ·δ_pitch + Cmq·q̄`); the yaw channel is its mirror (`Cnβ·β + Cnδ·δ_yaw + Cnr·r̄`,
  with the yaw coefficients defaulting to the pitch ones by symmetry). Roll channel: a roll damper
  holds `p ≈ 0` for STT (roll-command is slice 24's).
- ⚠ **The full `ω × (I·ω)` gyroscopic term IS included (it is the correct rigid-body form and it is
  cheap), but the LESSON does not ride on it** — for STT with `p ≈ 0` and coordinated flight it is
  ≈ 0 by construction. **GATE-0 DECISION: include the term for honesty, or defer to keep 23/24
  minimal?** Either way, NAME the deferral explicitly:
  > **DEFERRED — AERO + INERTIAL CROSS-COUPLING (the real BTT departure hazard).** The roll-pitch-yaw
  > inertial coupling that a non-diagonal `I` and a large `p` produce, and the aero cross-derivatives
  > (`Clβ` dihedral, `Cnp`, `Clr`, radome-induced parasitic terms) that make a real bank-to-turn
  > airframe DEPART during a hard roll, are NOT modeled. Diagonal `I`, symmetric cruciform aero, and
  > coordinated flight keep 23/24 clean. This is a later lesson — sibling to the radome / body-rate
  > parasitic loop named in HANDOFF §11.

### 5. THE OUT-OF-PLANE TARGET — the scenario that makes the discard visible

The lesson needs a target the pitch plane CANNOT reach. The existing `ManeuveringTarget` turns
**in the x-z plane** (`_lateral_accel` uses `(vx,vz) → (−vz,vx)`, `missile.jl:604` — planar by
construction). Slice 23 needs an out-of-plane component. Two routes (gate-0 decision):

- **(a) A cross-range target position / velocity** — put the target off the x-z plane (`pos_y ≠ 0`
  and/or `vel_y ≠ 0`) so the LOS to it has an out-of-plane component from t=0. Simplest; the
  `:pitch_coupled` plant discards the y-command and flies straight past in x-z. NO new mover.
- **(b) An out-of-plane MANEUVER** — generalize `ManeuveringTarget` (or a new mover) to turn in a
  tilted plane. More dramatic (the target actively jinks out of plane) but a bigger build.

⭐ **RECOMMEND (a) for slice 23** (a static out-of-plane geometry is enough to kill the pitch-plane
plant), with (b) as slice 24's sharper foil if the roll-lag needs an active out-of-plane maneuver
to bite. Let gate 0's measured miss decide. ⚠ Whatever the target does, it stays **aerodynamically
free** (no ceiling, no bleed — `missile.jl:589`'s named approximation): the lesson is the MISSILE's
steering, not a target-aero contest.

### 6. TELEMETRY & READOUTS — additive, gated, `_finite`-clamped

New `:six_dof` readouts (KEY/RUNG-gated so slices 16–22 wires are byte-identical, the slice-17
lift-key / slice-20 `a_induced` precedent):
- `att_q` components (or roll/pitch/yaw Euler angles derived from it — the client's 3-D nose/lift
  drawing), `omega_body = (p, q, r)`.
- `beta` (sideslip — the NEW angle this slice makes non-zero), `beta_cmd`, `delta_yaw`.
- The 2-plane aero ceiling / `aero_sat` per axis (or resultant — see #3's gate-0 question).
- All SCALARS (no Array → no client `float()` crash, convention 13), all `_finite`-clamped
  (convention 6). The `att_q` NaN path (a degenerate normalize) rides `qnormalize`'s identity
  fallback (frames.jl:67) — no `±Inf` to JSON.

---

## Gate 0 — probes to run BEFORE writing any library code

The empirical-first discipline (convention 10). Throwaway probes in
`M:\claud_projects\temp\slice23_gate0\` (global temp policy). The numbers come back and the design
may change (slices 19/20/21/22 were ALL changed by their gate 0).

- **P1 — the reduction SPLITS INTO TWO PROBES, and the ULP yardstick is WRONG for the physics-match
  half (advisor, load-bearing).** `_integrate_6dof!` (quaternion-RK4) and `_integrate_coupled!`
  (scalar-θ-RK4) are TWO DIFFERENT integration SCHEMES for the SAME ODE — different O(dt⁵) local
  truncation PLUS a per-step `qnormalize` projection — so their in-plane trajectories diverge FAR
  ABOVE ULP over an engagement. Testing the physics-match against a ULP atol would send gate 0
  chasing a "bug" that is just legitimate scheme difference. Split it:
    - **P1a — the STRUCTURAL INVARIANT (the real sign/frame-bug detector, and it IS tight ~1e-15).**
      In a perfectly in-plane setup (v_y = 0, target in-plane, roll = 0), the OUT-OF-PLANE states
      **`(p, r, β)` must stay ≈ 0 to ~1e-15** — because ω = (0, q, 0) ⇒ ω×Iω = 0 and the quaternion
      stays `[cos(θ/2), 0, sin(θ/2), 0]`. A frame/sign error LEAKS motion out of plane and this
      catches it sharply. ⭐ THIS is the check that earns "the #1 SIGN TRAP's FIFTH occurrence" (16
      moment, 17 lift, 19 the chain, 22 the moment break; here the body↔inertial `rotate` direction
      and the ω sign) — NOT the physics-match. Pin it BEFORE any out-of-plane run.
    - **P1b — the PHYSICS-MATCH reduction (the "same lesson" check, inherently LOOSE).** In-plane
      trajectory vs `_integrate_coupled!` to an atol set by a **dt-CONVERGENCE STUDY** (halve dt →
      does the divergence shrink at the expected order?), NOT by ULP. This validates the reduction
      CLAIM; it is not a bug detector. The atol is a MEASURED number from the convergence study, not
      a guessed magic multiple.
- **P2 — the out-of-plane MISS SPLIT is real and CLEAN — the miss should BE the cross-range offset.**
  The headline: `:pitch_coupled` misses the out-of-plane target WIDE, `:six_dof` STT intercepts.
  ⭐ Make the `:pitch_coupled` miss CLEAN by construction (advisor): the missile stays at y = 0 (it
  discards every y-command) and the target sits at y = Y, so the minimum approach is ≥ Y and the
  headline miss ≈ Y (a well-defined first-CPA in x-z), NOT a muddied 3-D CPA. Choose Y large enough
  to be decisive. ⚠ [[ewsim-missile-verifier-sampling]]: frame-sampling is ASYMMETRIC (the MISS
  samples faithfully, the HIT samples coarsely — quote frame numbers, pin the ratio); the LOS
  range-gate must sit ABOVE the largest CPA in the sweep; keep the x-z first-CPA clean.
- **P3 — does STT actually hold β usefully, and is `C_Yβ = C_Lα` (symmetric) the right default?**
  Measure the achieved (α, β) histogram through the engagement. Both should stay within their
  clamps by the COMMAND path (not a leak — slice-19 FINDING 14's shape, per axis).
- **P4 — the 2-plane ceiling: single-axis or resultant?** (#3's gate-0 question.) Measure whether
  `a_max_aero` for a cruciform pulling α AND β at once is the pitch-axis value or the 2-plane
  resultant. This decides what `aero_sat` keys off and what the client's aero strip plots.
- **P5 — roll stays ≈ 0 under STT.** Confirm the roll damper holds `p ≈ 0` (STT does not bank).
  If a residual roll builds, the ω×Iω coupling (#4) is biting and the "STT holds roll" claim needs
  the damper tuned or the term named. This is the seam slice 24's BTT roll-command opens.
- **P6 — the ω×Iω term: include or defer?** (#4's gate-0 decision.) Measure the trajectory with and
  without the gyroscopic term at STT's `p ≈ 0`. If it moves nothing (expected), decide whether to
  ship it for honesty or defer it to keep the branch minimal — and NAME the choice either way.
- **P7 — does `:six_dof` stay INERT without a target / degrade safely?** The `:six_dof` plant on a
  missile with no target, at V → 0 (launch/apex), and through the `qnormalize` identity fallback —
  a live rung can never crash a tick (convention 5). Walk the degenerate paths.
- **P8 — is `:six_dof` INERT without airframe params, like `:pitch_coupled`?** `_integrate_6dof!` must
  be unreachable without `:af_cma` (the params-presence gate). Confirm a bare `:missile` under
  `:airframe === :six_dof` falls to the point-mass path (byte-identical), never a `KeyError`.

---

## Gate 0 — FINDINGS (run 2026-07-20; probes in `M:\claud_projects\temp\slice23_gate0\`)

Throwaway probes (`kernels.jl` + `p1a.jl` + `p1b_p2.jl` + `p3_p8.jl` + `p2b_sweep.jl`) that REUSE
the shipped frames.jl algebra (`qmul`/`rotate`/`rotate_inv`/`qnormalize`) so P1a tests the code
that will ship. Nothing touched a source file. **All 8 probes green; the plan HELD on its live
overturn candidates (P4, P6, route), with one mild refutation (P1b).**

### ⭐ THE SIGN WIRING — the load-bearing gate-1 spec (the #1 SIGN TRAP's FIFTH occurrence)
`att` maps body→inertial (`rotate(att,[1,0,0])` = nose in inertial). Kinematics
`q̇ = ½ q ⊗ [0, ω_body]`. The ⟂-v body axes and signed incidence (which reduce EXACTLY to
`lift_accel` in-plane — verified `|Δ|=0` bit-for-bit, `n̂_pitch=(−sinγ,0,cosγ)` to 1e-16):

    n̂_pitch = normalize(zup(q) − (zup·v̂)v̂),   n̂_yaw = normalize(ywing(q) − (ywing·v̂)v̂)
    α = atan(nose·n̂_pitch, nose·v̂)   (= θ−γ in-plane),   β = atan(nose·n̂_yaw, nose·v̂)
    a_lift = (Q·S/m)(Cla·α·n̂_pitch + Cyb·β·n̂_yaw)          (⟂ v; bit-matches lift_accel in-plane)

⚠ **THE PITCH/YAW MOMENT SIGN IS NOT SYMMETRIC — a concrete new finding, and the divergence trap.**
Under `rotate`, physical NOSE-UP (α+, +x→+z) is a **−y** body rotation, but physical NOSE-TOWARD-+y
(β+, +x→+y) is a **+z** body rotation. So the aero moments map as:

    M_body = (−c_roll·p,  −M_pitch_phys,  +M_yaw_phys)         # pitch NEGATED, yaw NOT
    M_*_phys = Q·S·d·(C·incidence + Cmd·δ + Cmq·rate_phys)
    physical incidence rates:  α̇ = −ω_y  (pitch),   β̇ = +ω_z  (yaw)

The physical rate (−ω_y / +ω_z) is what BOTH the `Cmq` damping AND the autopilot's `−k_q·rate` term
must consume. Passing `+ω_y` to the pitch loop (the naïve "ω is the rate") DIVERGES it (caught at C4,
α→3.11 tumble). The autopilot itself is the shipped `alpha_autopilot_delta`, called once per axis.
Roll is a pure damper holding `p≈0`; the roll COMMAND is slice 24's.

### P1a — STRUCTURAL INVARIANT: GREEN AT THE FP FLOOR (better than the plan's ~1e-15)
In-plane run (6 s): `max|p| = max|r| = max|β| = max|q_x| = max|q_z| = EXACTLY 0.0`. The #1-sign-trap
gate is green — nothing leaks out of plane. Pinned BEFORE any out-of-plane run (advisor).

### P1b — THE REDUCTION IS TIGHTER THAN THE PLAN PREDICTED (mild refutation of "inherently LOOSE")
6-DOF-quaternion vs scalar-θ `rk4_coupled` in-plane trajectory diff = **3.9e-11 m** at dt=2e-3 →
**0.0** at dt=2.5e-4, O(dt⁴) ratio 14.0 until it hits the FP-noise floor. The pure-pitch quaternion-RK4
and scalar-θ-RK4 are structurally near-identical (`qnormalize` contributes ~1e-11 over 2 s). ⇒ **the
reduction golden atol can be TIGHT (~1e-9 m), NOT a loose engineering tolerance.** The advisor's "far
above ULP" caution holds for the general case; the specific in-plane pitch reduction is nearly exact.
(Keep P1a — the FP-floor structural check — as the separate sharp sign/frame detector; P1b is the
"same trajectory" confirmation, and it turned out sharp too.)

### P2 / P2b — THE MISS SPLIT IS CLEAN, DECISIVE, AND ROBUST (route (a) confirmed)
Target static cross-range `+Y`, aero-free. **Plant A (:pitch_coupled) CPA = EXACTLY Y** (300.00 /
600.03), **max|pos_y| = 0.0 EXACTLY** (the y-command is fully discarded; the missile never leaves x-z
→ licenses "miss = Y"). **Plant B (STT) intercepts to <3 m.** Robust across Y∈[300,3000], ρ∈[0.3,1.225]:
A always misses ≈Y, B always hits.
- ⚠ At sea level the engagement is EASY (α_pk=0.025 from gravity alone, β_pk≈0.005) — the STT plant
  barely works. **For a VISIBLE lesson pick a low authored ρ** (a constant flight condition, NOT slice
  21's `:atmosphere` rung — the ONE toggled fidelity stays `:airframe`): at ρ=0.3, Y=2000, β_pk=0.122
  (≈0.41·α_max) and B still hits — the shot shows B yawing hard while A flies straight past. (Route (b),
  an out-of-plane MANEUVERING target, is NOT needed for slice 23; it is slice 24's sharper foil.)

### P4 — 2-PLANE CEILING = the RESULTANT CLAMP (confirms advisor; decides what `aero_sat` keys off)
Demand at 45° in the ⟂-v plane vs the single-axis ceiling (840 m/s²): at 1.4× over-drive, per-axis
clamps give `|inc|=√2·α_max`, lift `√2×` ceiling; the resultant clamp gives `|inc|=α_max`, lift =
single-axis (REPOINTED). ⇒ **Use `hypot(α,β) ≤ α_max`.** Total maneuver-g ceiling is UNCHANGED from the
pitch plane, just repointable in 3-D — the clean lesson ("the discard dies" = POINTING the same
authority out of plane, not getting MORE of it). `a_max_aero` keeps the single-axis formula
`Q·S·|Cla|·α_max/m`; `aero_sat` keys off `hypot(α_cmd, β_cmd) > α_max`. Per-axis is physically wrong
(total incidence `√(α²+β²)` is what drives stall).

### P5 — ROLL≈0 under STT (both vacuous & non-vacuous)
`p0=0 → max|p|=4.4e-18` (vacuous by construction — no roll source; scaffolding banked for slice 24).
`p0=0.5 → p_end=1.1e-19` (the damper pulls it back). STT does not bank — the seam slice 24's roll
command opens. Report the vacuous case as "vacuous by construction," NOT "tested and holds" (4c discipline).

### P6 — ω×Iω: INCLUDE (the plan left it open; decided)
Trajectory diff gyro-on vs gyro-off = **EXACTLY 0.0** at STT's single-axis ω. Ship the term for honesty
(cheap, correct rigid-body form). The inertial cross-coupling that MATTERS (large `p`, non-diagonal `I`)
is slice 24's — NAMED as the AERO+INERTIAL CROSS-COUPLING deferral (§4).

### P7 — DEGENERATE PATHS SAFE (convention 5)
V→0 aero/moment/steering all finite; `qnormalize(0)→[1,0,0,0]`; 5 s free-flight stays finite, q unit to 0.0.

### P8 — INERT WITHOUT PARAMS (gate-2 structural, confirmed by design)
`_integrate_6dof!` mirrors `_integrate_coupled!`'s gate (`haskey(:af_cma) && :airframe===:six_dof`). A
bare `:missile` under `:six_dof` falls to the point-mass path, mints no `:att_q`/`:omega_body` keys →
byte-identical. Enforced at gate 2.

### NET — what changed / what to carry into gate 1
- **Confirmed (plan held):** P4→resultant clamp, P6→include ω×Iω, route→(a) static offset. `C_Yβ = C_Lα`
  (symmetric cruciform) is a fine default.
- **Refuted (mild):** P1b — the in-plane reduction is TIGHT (~1e-11 m), not loose. Tighten the golden.
- **New for gate 1:** the pitch/yaw moment-negation ASYMMETRY (the frame is not sign-symmetric — pitch
  moment negated, yaw not; physical rates α̇=−ω_y, β̇=+ω_z). This is the load-bearing sign spec above.
- **Scenario:** author a low ρ (or large Y) so the STT yaw authority is VISIBLY exercised in the shot.

---

## Gates 1–3 (sketch — firmed by gate 0's findings above)

**Gate 1 — the pure lib.** Extend `airframe.jl` (or a new `airframe3d.jl` if the surface warrants —
gate-0 decision) with the 3-D primitives, REUSING frames.jl's quaternion algebra (`qmul`,
`qnormalize`, `rotate`, `rotate_inv` — all already 3-D and tested):
- `attitude_kinematics(q, ω) → q̇ = ½ q ⊗ [0,ω]` and the body-rate dynamics
  `body_rate_deriv(ω, M_body, I) → ω̇ = I⁻¹(M_body − ω×(I·ω))` (diagonal `I`).
- `rk4_6dof(f, pos, vel, q, ω, dt)` — the joint `[pos, vel, q, ω]` stepper, the `rk4_coupled`
  sibling (a FRESH stepper, not a composition; the coupling is the mid-stage re-eval — advisor's
  slice-17 precedent). ⚠ Re-NORMALIZE `q` each step (drift guard — `qnormalize`).
- `steering_command` (#3) — the 2-plane STT inversion. `stt_moments` — the pitch/yaw/roll moments
  from (α, β, p, δ_pitch, δ_yaw), reusing `pitch_moment`'s form per channel.
- `AIRFRAME_MODES = (:point_mass, :pitch_coupled, :six_dof)` (grow the ONE tuple — convention 7).
- **Tests (teeth, not tautologies — convention 11):** the reduction golden (roll=yaw=0 ⇒ scalar
  path, `atol`); the #1 SIGN TRAP pinned per axis (a +β makes yaw lift toward +y ⇒ γ_yaẇ sign;
  `dot(a_lift_pitch, v̂) ≈ 0` AND `dot(a_lift_yaw, v̂) ≈ 0`; the ω sign on a concrete out-of-plane
  crossing); the quaternion round-trip (`rotate_inv(q, rotate(q, v)) == v`); the ω×Iω term ≈ 0 at
  p=0; and the STT inversion round-trip (`steering_command` of exactly the 2-plane `a_max_aero`
  resultant ⇒ clamps at `±α_max`/`±β_max`).

**Gate 2 — the wiring.** `_integrate_6dof!` in missile.jl (the `_integrate_coupled!` sibling), gated
`haskey(:af_cma) && :airframe === :six_dof`, with `_integrate_coupled!`/`_integrate_airframe!`/the
`:alpha`+`:pitch_coupled` arm TEXTUALLY VERBATIM; the `:alpha` arm of `decide!` gains a `:six_dof`
branch calling `steering_command` → `(δ_pitch, δ_yaw)` written to comp for next tick (the
`:delta_cmd` seam, now 2-channel); `build_env!` gains the gated 3-D readouts (#6); the loader
(scenario.jl) validates the new airframe keys (`I_roll`, `cy_beta`, out-of-plane target geometry) —
convention 5 validate-at-load. Class **4c**. ⚠ **INERTNESS CHECK**: `:six_dof` must be inert without
airframe params (P8), and the new readouts absent on every slice-16–22 wire (byte-identity, the
slice-21/22 `_atm_on`/`_stall_on` third-conjunct precedent — the gate where slice 21 found a LATENT
BUG). ⚠ **DO NOT let the 3-D moment reach the `:point_mass`/`:pitch_coupled` paths** — the exact
slice-22 warning ("the moment break reaches further than ρ(z) did"): keep `_integrate_6dof!` the
sole consumer of the 3-D dynamics.

**Gate 3 — the four proofs** (convention 14): `slice23_verify.gd` (the out-of-plane miss split +
held-seed bit-identical replay across the `:pitch_coupled ↔ :six_dof` toggle + the reduction golden on
the wire), `slice23_ui_test.gd` (the `:airframe` cycler now 3-rung; value-guard the 3-D view vs the
2-D airframe view vs slice-18's terrain 3-D view — the multi-view discriminator), the `Sandbox.tscn`
headless smoke-load, and a windowed shot aimed at the CLAIMED branch (the 3-D trail curving OUT of
the x-z plane toward the out-of-plane target, the nose/lift vectors in 3-D). ⚠ **THE CLIENT NEEDS A
3-D VIEW** — but slice 18 already built one (the terrain SubViewport Node3D world,
[[ewsim-godot-material-gotchas]]); REUSE its 3-D scaffolding rather than the 2-D side-on airframe
view. Gate-0 should confirm the airframe 3-D view can borrow slice 18's camera/mesh machinery.
⚠ Slice-21/22 gate-3 PROOF bugs are live watch-items: `%.2e` is not a GDScript specifier (silent
`%` failure); frame-sampling is ASYMMETRIC; magic-multiple teeth pin against MEASURED values.

---

## Named deferrals (write them down; do not let them leak into this slice)

- **BANK-TO-TURN + the roll-lag lesson = SLICE 24** — the same substrate, α-only lift + a roll
  autopilot with finite bandwidth, and the `:steering = (:skid_to_turn, :bank_to_turn)` rung. This
  slice ships the substrate and STT; the roll-lag miss is 24's headline. (The whole reason for the
  STT-first split.)
- **AERO + INERTIAL CROSS-COUPLING / DEPARTURE** (#4) — non-diagonal `I`, `Clβ`/`Cnp`/`Clr` aero
  cross-derivatives, the radome / body-rate parasitic loop. The real BTT departure hazard; diagonal
  `I` + symmetric cruciform + coordinated flight keep 23/24 clean. Its own later lesson.
- **ASYMMETRIC AERO** — `C_Yβ ≠ C_Lα`, different pitch/yaw stability. Slice 23 defaults them equal
  (symmetric cruciform, #3). A real airframe's differ.
- **A SEEKER IN THE 6-DOF LOOP** — flips the class back to 4a / RNG-live (slice 11's seeker against
  a 3-D airframe). All of 14–23 are 4c (no RNG). Deferred.
- **AERODYNAMICALLY-CONSTRAINED TARGET** (missile.jl:596's deferral, unchanged) — giving the target
  its own ceiling / energy bleed so a defensive out-of-plane turn COSTS it. Its own slice; an
  aero-free target is what isolates the MISSILE's steering as the lesson here.
- **ρ(z) on the ballistic path** and the RF layered-atmosphere / ducting entry (slice 21's
  deferrals, unchanged) — do not conflate with this slice.
