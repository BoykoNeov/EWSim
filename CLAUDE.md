# EWSim — working notes for Claude Code

Teaching-through-play simulator for EW / air defense / GPS / missile guidance.
A headless Julia **core holds the truth**; Godot and Pluto are thin, replaceable
clients. **`HANDOFF.md` is the ground-truth design** — read it before changing
architecture, and don't relitigate its frozen decisions inside a slice.

## How to run things (Windows)

Julia 1.11.9 is installed portably and is **not on PATH**. Always go through the
wrappers so the path lives in exactly one place:

- Run tests:  `pwsh tools/test.ps1`
- Any Julia:  `pwsh tools/julia.ps1 <args>`   (e.g. `pwsh tools/julia.ps1 tools/setup.jl`)
- Godot 4.7:  `& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"`

PowerShell 5.1 mangles double quotes passed to `julia -e`. **Put Julia code in a
`.jl` file and run the file** rather than fighting inline `-e`.

## Where things live

- `core/src/` — the engine. `world.jl` (World/Entity/Vec3), `subsystem.jl` (the
  tick contract), then physics libs (`rf.jl`, `detection.jl`, ...) as slices land.
- `core/test/runtests.jl` — the contract enforcer. New model ⇒ new test here.
- `clients/godot/`, `clients/notebooks/` — thin clients. **No physics here.**
- `scenarios/*.yaml` — declarative source of truth for runs, tests, MC inputs.
- `docs/plans/` — staged plans / context / task checklists.
- `docs/STATUS.md` — the as-built ledger (detailed per-slice completion notes).

## Invariants that catch the real bugs

- **Physics lives in the core, never in a Godot script or a notebook cell.** If
  it can't run headless from `runtests.jl`, it's in the wrong place.
- **Units / frames / signs are the bug trifecta.** SI Float64 internally,
  inertial frame, quaternion body<-inertial = `[1,0,0,0]`. Test frame round-trips
  and LOS-rate signs from day one.
- **Determinism is on CPU.** Same seed + same scenario ⇒ bit-identical trace
  (enforced by `test_determinism.jl`). GPU is for bulk statistics only, never replay.
- **Approximations are switchable and named.** Every subsystem carries a
  `fidelity` knob; dialing it and watching what changes *is* the lesson. No hidden
  approximations, never simulate at carrier frequency (work at baseband / link budget).

## Tick contract (the phase map, HANDOFF §3)

Every subsystem hook runs in a fixed order each `tick!`: **phase 1** `integrate!` (movers/
airframe) → `empty!(w.env)` → **phase 2** `build_env!` (cross-subsystem fields, e.g. jamming) →
**phase 3** `observe!` (sensors) → **phase 4** `decide!` (estimators/guidance). The `empty!`
after phase 1 is a recurring gotcha (see conventions). "A missile is `integrate!` + `observe!`
+ `decide!`."

## Current status

**Slices 1–23 COMPLETE & green — 4276 tests. The committed roadmap (HANDOFF §10 items 1–13) is DONE; slices 15–23
are into the §11 Tier-A horizon — slice 15 did the actuator/fin half of "6-DOF airframe + actuator/fin dynamics",
slice 16 the rotational half (pitch-plane θ,q), slice 17 the α→lift→γ TRANSLATION-COUPLING half (the real
path-changing `:airframe` toggle), slice 18 TERRAIN MASKING behind a third `:propagation` rung + the client's
FIRST true 3-D view (a user-directed insertion — the inner autopilot shifted to slice 19), slice 19 the CLOSED
INNER LOOP (`a_cmd→α_cmd→δ`) + the flight-condition g-limit, slice 20 INDUCED DRAG — the missile LOWERS ITS OWN
CEILING by maneuvering — slice 21 the EXPONENTIAL ATMOSPHERE: the ceiling you lower by CLIMBING (ρ(z) at
last, so "high altitude" is EARNED language and not a caveat), slice 22 NONLINEAR C_L(α) / TRUE STALL —
the ceiling the AIRFRAME itself sets, which moves the ONE factor of `a_max_aero` that 19/20/21 all left
alone — and slice 23 the 6-DOF SUBSTRATE + SKID-TO-TURN: the OUT-OF-PLANE ENGAGEMENT, where the pitch plane's
out-of-plane DISCARD (unflyable BY CONSTRUCTION since slice 19) finally intercepts — `att` becomes a genuine 3-D
quaternion and STT makes lift in TWO body planes at once, the FIRST slice of the bank-to-turn / 3-D arc.** Full gate-by-gate
as-built detail (exact numbers, test names, watch-items, advisor-catches, per-slice run commands)
lives in **`docs/STATUS.md`**; pre-implementation plans in `docs/plans/sliceN.md`.

- **Slice 1** — radar → detection → ROC. Free-space radar eq, analytic+MC Pd (Swerling 0/1),
  the wire protocol + Godot socket seam, the server run-loop, the `batch.jl`/ROC path. (227)
- **Slice 2** — propagation fidelity: `two_ray` lobing + 4/3-Earth horizon mask behind
  `:propagation`; coverage-diagram stretch. (420)
- **Slice 3** — CFAR sandbox + N-pulse integration (Swerling 0–4): CA/GO/SO/OS adaptive
  threshold, the masked-close-target lesson; `:cfar` (the one draw-topology flip). (798)
- **Slice 4** — jamming / EP: J/S burn-through, standoff vs self-screen, `:ep`
  none/freq_agility/sidelobe_blanking. First `build_env!`. (923)
- **Slice 5** — DF / geolocation: bearings-only fix, GDOP error ellipse, `:estimator`
  pseudolinear vs ml. First `decide!` (Godot plan/top-down view). (1055)
- **Slice 6** — multi-emitter EW: PRI-histogram deinterleaver, CDIF phantom vs SDIF subharmonic
  check, `:deinterleaver`. The phase-contract capstone (build_env!+observe!+decide!). (1238)
- **Slice 7** — GPS: pseudoranges → trilateration → DOP + RAIM (`:raim` off/detect/exclude).
  The §9 cross-domain-reuse milestone (same `gauss_newton` fixes DF N=2 and GPS N=4). (1492)
- **Slice 8** — ballistic missile: the force-integrator + `frames.jl`; `:integrator` rk4 vs
  euler (physics-changing, not toggle-invariant). First phase-1 force-based mover. (1633)
- **Slice 9** — PID autopilot under a pursuit outer law; `:autopilot` ideal vs pid, the
  commanded-vs-achieved track-gap lesson. First missile `decide!`. (1723)
- **Slice 10** — proportional navigation (outer loop) + g-limit saturation-as-lesson; `:guidance`
  pursuit vs pn (the reserved key filled, physics-changing). MISS is the honest headline (pn ≪
  pursuit); the a_max clamp BINDS on purpose (the slice-9 inversion). Closes the missile arc. (1829)
- **Slice 11** — noisy seeker + LOS-rate filtering; `:seeker` raw vs filtered — the naïve finite-diff
  `λ̇=Δλ/dt` amplifies angle noise → PN pegs a_max & misses wide, the α-β tracker recovers a smooth λ̇
  → tight intercept. The missile's **first phase-3 `observe!`** ("integrate!+observe!+decide!" COMPLETE)
  and the **first `w.rng` consumer in the missile arc** (the RNG inflection — conventions 3/11 now apply;
  byte-identity from *no Seeker* on prior slices). NEW fidelity-class combo: draw-invariant (4a,
  introducible) AND trajectory-changing. (1921)
- **Slice 12** — augmented PN (`(N/2)·a_T⊥` feedforward on the target's truth accel) + a `ManeuveringTarget`
  phase-1 mover; `:guidance` gains a THIRD rung `:apn` (the 3-ring pursuit→pn→apn). Vs a maneuvering target
  under a BINDING `a_max`, plain `:pn` SATURATES → misses (~167 m); `:apn` anticipates → low demand → tight
  intercept (~0.85 m, the CV baseline). The g-limit IS the constraint (raise a_max → pn recovers). **The RNG
  inflection INVERTS BACK** — no seeker → no `w.rng` draw → the slice-10 shape ("draw-count invariance VACUOUS"
  again). Reads TRUTH `a_T` ("even a perfect seeker still lags"); gravity-comp PN + estimated `a_T` DEFERRED.
  Closes HANDOFF §10 item 10. (2008)

- **Slice 13 (roadmap item 12) — countermeasures COMPLETE**: a `:decoy` seduces the slice-11 seeker; the
  slice-3 CFAR sandbox lifts onto the LOS-ANGLE axis (`:scan` rung); seduction (`:none` intensity-blend of ALL
  CFAR peaks) vs discrimination (`:gated` α-β predicted-LOS **nearest-neighbour** gate = the RGPO track-gate in
  angle). The FUSION lives in the discrimination half: `cfar_scan` DETECTS the peaks in the noisy angular profile
  (a real job — two lobes in fast-Rayleigh noise), the α-β predicted gate DISCRIMINATES which peak to keep (CFAR
  alone can't reject a BRIGHTER decoy). The HEADLINE is AIMPOINT error `|λ_est−λ_target|` (clean by construction;
  miss corroborates) under a GENEROUS `a_max` (a POINTING miss, ≠ slice-12's saturation miss). RNG inflection
  RE-INVERTS to APPLIES (a seeker draws again, conventions 3/11); `:scan` is class 4b (draw-topology flip
  `1`→`2·N_p·N_bins`, introduce/remove-rejected like `:cfar`), `discrimination` draw-invariant-within-the-4b-host
  + inert without `:scan`. The `:decoy` kind is NEVER `:target` (`_nearest_target` skips it → miss/CPA ALWAYS vs
  the true target — the seeker is seduced but the miss is honest). `Seeker.observe!` split into `_observe_point!`
  (slice-11 VERBATIM, 1 draw) / `_observe_scan!` (2·N_p·N_bins, tick-1 truth-cued lock, paint→`_draw_profile!`→
  `cfar_scan`→`extract_peaks`→`:none` blend / `:gated` NN gate). Emit-grid wire (seed 6): `:none` aim 4.83°/miss
  598 m vs `:gated` aim 0.054°/miss 4.16 m (~89×), draw EXACTLY 1280/tick; the born-resolved parallel decoy stays
  inside ±FOV/2 across the aim window. Four proofs green (verifier + UI + smoke-load + windowed shot: `:none` aim
  ray walks to the ✦ decoy, `:gated` holds on the target). Closes HANDOFF §10 item 12 — "fuses the whole suite".
  Deferred (NAMED): the range-gate RGPO variant vs a tracking radar; RF/IR seeker split; decoy dynamics
  (bloom/burn-out/ejection); 2-D az×el/monopulse; salvo. (2159)

- **Slice 14 (roadmap item 13) — cooperative salvo guidance COMPLETE (THE CAPSTONE)**: N=2 interceptors SHARE
  their time-to-go over an IDEAL datalink so they arrive SIMULTANEOUSLY. A `[SalvoCoordinator]` `:datalink` node
  (a NEW non-physical kind, phase-2 `build_env!`, SINGLE writer) pools every `kind===:missile` interceptor's truth
  `t_go≈R/V_c` into the team consensus `T_d=max_j t_go_j(0)` — FIXED-AT-LAUNCH (the robustness default; a per-tick
  or ratcheted consensus SELF-POLLUTES: the stretch it induces collapses V_c and inflates `t_go=R/V_c`, running T_d
  to ~99–105 s — probe8/9), republished as the shared REMAINING time `w.env[:salvo_t_d]=T_d−w.t`. The NEW
  `:cooperation` fidelity (`(:solo,:salvo)`): `:solo` = plain PN to each missile's natural `t_go` → SPREAD arrivals;
  `:salvo` = `impact_time_control_accel` (PN base + a `(K_it·err·‖v‖)·v̂⊥` ⟂-LOS feedback, `err=salvo_t_d−t_go>0 ⇒
  EARLY ⇒ STRETCH`) drives every missile's `t_go→T_d` → the near missile WEAVES a stretched S-curve to delay while
  the far reference flies ~straight → both arrive TOGETHER (Δτ collapses **2.35→0.53 s, ~4.5×** on the emit-grid
  wire) while each still HITS (cooperation reshapes TIMING, not accuracy). `a_max=3000` GENEROUS — the residual Δτ
  is a CONTROL-AUTHORITY/gain artifact, NOT a g-limit (the OPPOSITE of slice-12; do NOT import saturation language).
  The RNG inflection INVERTS BACK to VACUOUS (truth-fed PN, NO seeker → NO `w.rng` consumer) — class **4c**
  (physics-changing, no RNG; `:cooperation` LIVE-SETTABLE, NO `set_fidelity` guard — the `:integrator`/`:autopilot`/
  `:apn` precedent, the CONTRAST to slice-13 `:scan`'s introduce-reject). The FIRST multi-interceptor scenario +
  the FIRST `:datalink` kind. The solo degenerate is a LAW-level `err==0` bit-exact `pn_accel` early-return (a
  1-missile salvo is loader-forbidden); additivity for slices 1–13 is BY GATING (`:salvo` unreachable without the
  mode AND the coordinator). The metric SELF-JUSTIFIES → no defender model (deferred). Closes HANDOFF §10 item 13.
  Deferred (NAMED): consensus filtering / noisy-latent-lossy datalink (Tier-C); cooperative estimation (A) + WTA
  (B); the approach-ANGLE variant; a point-defense model; N>2 / heterogeneous; decoys in the salvo. (2259)

- **Slice 15 (§11 Tier-A, FIRST horizon extension) — a RATE-LIMITED FIN SERVO COMPLETE**: the actuator/fin half of
  the Tier-A "6-DOF airframe + actuator/fin dynamics" entry (6-DOF DEFERRED). A THIRD `:autopilot` rung `:fin`
  (`(:ideal,:pid,:fin)`): the SAME PID feeds a fin-deflection command `δ_cmd=clamp(u/k_δ,δ_max)`; the fin slews
  through a first-order servo whose rate is HARD-CAPPED at `δ̇_max` (rad/s); `a_ach=k_δ·δ`. THE CRUX (advisor,
  load-bearing): a LINEAR fin servo collapses to the `:pid` plant relabeled (`k_δ` cancels — the convention-4c
  false-fidelity trap), so the NONLINEAR limits (δ̇_max, δ_max) carry the ENTIRE fidelity — PROVEN by the
  `:pid`-equivalence-at-δ̇/δ→∞ test. THE LESSON (gate-0 EMPIRICAL PIVOT, 12 probes): the fin rate limit CAPS THE
  G-ONSET RATE `|da_ach/dt| ≤ k_δ·δ̇_max` (telemetry `g_onset`, ≤ the cap EVERYWHERE by construction) — a jerk cap
  cleanly DISTINCT from slice-9's steady-state gain undershoot `1/(1+Kp)`, slice-10/12's MAGNITUDE cap `a_max`. The
  ISOLATION (advisor #2, ASSERTED): `k_δ·δ_max=2500 ≤ a_max=2600` and the maneuver tuned so `fin_defl_sat==0 &&
  saturated==0` in the guided window → the cap is a CLEAN rate cap, not a slice-10 magnitude clamp in a fin costume
  (the three numbers separable: rate cap 2000, g cap 2500, mag cap 2600). THE "LACK OF EFFECT" IS THE LESSON
  (user-ratified): the MISS does NOT open — point-mass PN is robust to actuator rate limiting (the planned
  "saturation opens the miss" did NOT materialize) — which is precisely WHY the DRAMATIC failure modes (guidance
  limit cycle, α-limited maneuverability, radome/body-rate parasitic loop) genuinely need the DEFERRED 6-DOF (the
  fin state δ that 6-DOF's moment equation consumes is now BANKED). Class **4c** (physics-changing, NO RNG —
  truth-fed PN, no seeker; "draw-count invariance VACUOUS", the 2nd consecutive 4c after slice 14; LIVE-SETTABLE,
  NO `set_fidelity` guard — the `:integrator`/`:autopilot`/`:apn`/`:cooperation` precedent, CONTRAST slice-13
  `:scan`). `AutopilotState` STRUCTURALLY FROZEN (δ in its own `:fin_state` — advisor #4); the `:ideal`/`:pid` arm
  TEXTUALLY UNCHANGED (slices 1–14 byte-identical). Emit-grid wire (seed 15): `:fin` δ̇=0.4 → g_onset caps at 2000
  (=k_δ·δ̇_max), rate_sat binds, defl_sat/sat=0, miss 6.6; raise δ̇=2.0 → cap RISES to 10000 + binds LESS (rate_sat
  7→1) + miss UNCHANGED (the lever, the "lack of effect"); `:ideal` ships NO fin keys (byte-identical wire), miss
  9.2. Four proofs green (verifier + UI 3-ring ideal→pid→fin + smoke-load + windowed shot: the curved fin-limited
  trail + a_cmd 441 vs a_ach 330 lag). The client routes the shared button to a PER-SCENARIO autopilot 3-ring on
  `autopilot==:fin` (slice-9 stays a 2-ring). OPENS HANDOFF §11 Tier-A. Deferred (NAMED): the 6-DOF airframe /
  angle-of-attack half (trigger recorded); a 2nd-order actuator (ω_a/ζ_a); per-channel fin allocation / hinge-
  moment / stall; the actuator feeding a MOMENT (→α→lift) = 6-DOF. (2347)

- **Slice 16 (§11 Tier-A, the 6-DOF airframe's FIRST HALF) — pitch-plane ROTATIONAL DYNAMICS COMPLETE**: the
  DEFERRED rotational half of Tier-A's "6-DOF airframe + actuator/fin dynamics" (slice 15 did the fin half). The
  FIRST rotational state in the project — `att`, a KINEMATIC velocity-alignment through slices 8–15, becomes a
  DYNAMICAL OUTPUT of the aero pitching moment (the ROTATION analog of slice 8's ballistic force-integrator that
  made `pos` force-integrated). New pure lib `airframe.jl` (`AirframeParams`, `pitch_moment` M=QSd·(Cmα·α+Cmδ·δ+
  Cmq·q̄), `rk4_rot` the generic (θ,q) stepper — shaped so slice-17's joint [pos,vel,θ,q] step reuses the closure,
  `short_period_freq` NaN-guarded, `trim_alpha` δ=0→0). THE LESSON (the af_cma slider, a live KNOB not a fidelity
  button): Cmα<0 WEATHERVANES (α oscillates about trim at ω_sp=√(−Cmα·QSd/I), damped by Cmq, nose tracks γ) vs
  Cmα>0 TUMBLES (|α| diverges, ω_sp imaginary → FINITE_CEIL sentinel). #1 SIGN TRAP → the moment SIGN pinned
  DIRECTLY (advisor tooth #1), V/γ-frozen SHM RK4-exact ~1e-15, damping log-decrement pins ζ. THE ISOLATION (the
  headline proof): rotation reads (V,γ) but does NOT feed (pos,vel) — no α→lift this slice (slice 17) → the
  TRAJECTORY is BYTE-IDENTICAL across the Cmα flip (verifier posdiff=**0.0**). This is WHY there is NO `:airframe`
  fidelity toggle — a path-bit-identical toggle would name a coupling it can't produce yet (the convention-4c
  FALSE-FIDELITY trap, the slice-15 k_δ-cancellation precedent). **Option-P′** (advisor-reconciled): a handshake
  `airframe_view` marker (the range_axis_m→cfar precedent) makes the client recognize the view + DROP the shared
  button (nothing to cycle), core stays PARAMS-PRESENCE gated (`haskey(c,:af_cma)`, slices 8–15 byte-identical).
  Class **4c** (physics-changing, NO RNG — truth-fed, no seeker → "draw-count invariance VACUOUS", the 3rd
  consecutive 4c after 14/15; LIVE-SETTABLE, no `set_fidelity` guard). The Godot marker draws the NOSE off θ vs a
  CYAN VELOCITY reference off γ — the gap IS α, labeled. Four proofs green (verifier: STABLE max|α|=0.150/ω_sp=2.40
  real, REPLAY bit-identical, UNSTABLE max|α|→1e6/ω_sp=1e9 sentinel, posdiff=0.0; UI: button HIDDEN + af_cma
  slider→set_param; smoke-load DONE; TWO contrasting shots — stable α=3.2° nose≈v vs mild-unstable α=23.8° nose
  off v/ω_sp sentinel). Deferred (NAMED): **slice 17 = the inner α/g autopilot + α→lift→γ coupling** (the real
  path-changing `:airframe` toggle lands THEN — a stable Cmα gains a coupling to name; the fin state δ from slice
  15 feeds the moment equation); then α-limited-maneuverability miss → bank-to-turn (3-D quaternion+ω, the
  geometry→frames "2-D first" precedent) → radome/body-rate parasitic loop. SLICE-17 CLIENT NOTE: the airframe
  branch is checked FIRST in `_setup_spatial_fid_btn` — value-guard it when slice 17 adds an `:airframe` fidelity
  alongside `af_cma` (else it hides the button slice 17 wants). (2409)

- **Slice 17 (§11 Tier-A, the 6-DOF airframe's SECOND HALF) — the α→lift→γ COUPLING COMPLETE**: the FIRST
  rotation→translation coupling in the project. Slice 16 made `att` a dynamical output but ISOLATED it (posdiff=0);
  slice 17 CLOSES the loop — **α = θ−γ generates a body lift ⟂ v that TURNS the flight path** (α→lift→γ̇), and the
  REAL path-changing `:airframe = point_mass | pitch_coupled` toggle finally lands (slice 16 refused it — the
  convention-4c false-fidelity trap). OPEN-LOOP (δ a FIXED authored trim — the inner α/g autopilot is slice 18).
  New `airframe.jl`: `lift_accel` (`(Q·S·Cla·α/m)·(−sinγ,0,cosγ)`; +Cla ⇒ γ̇>0 for α>0 = the #1 SIGN TRAP, pinned
  by `dot⟂v` AND γ̇-sign), `rk4_coupled` (a FRESH 8-scalar joint `[pos,vel,θ,q]` RK4 — re-evals V,γ mid-stage = the
  coupling, NOT operator-split), `AIRFRAME_MODES`; `AirframeParams` gains `Cla`. The LESSON & anchor: the
  STEADY-TURN RADIUS `R = 2m/(ρSC_Lα·α) ≈ 5197 m` (SPEED-INDEPENDENT). `missile.jl` `_integrate_coupled!` gates on
  `haskey(:af_cma) && :airframe===:pitch_coupled` (point-mass block wrapped VERBATIM in the else — byte-identity).
  **THE STAGE-θ FIX (advisor, load-bearing):** the deriv closure reads the RK4 STAGE θ (`TH`), NEVER the entry θ —
  the entry-θ bug is only ~0.019 m/8 s, invisible to the R & decoupled tests, so ONLY a transient GOLDEN catches
  it. Lift telemetry (a_lift/turn_radius_m) gated on `:pitch_coupled` NOT af_cma (else a slice-16 wire breaks).
  `LIVE_FIDELITY_MODES` gains `airframe = AIRFRAME_MODES` (the ONLY plumbing edit; NO set_fidelity guard). Class
  **4c** (physics-changing, NO RNG — "draw-count invariance VACUOUS", the 4th consecutive; live-settable). CLIENT:
  the `:airframe` cycler comes BACK, REUSING `_fid_kind="airframe"` (the curved-trail + nose/velocity/α drawing all
  carry over) with the drop VALUE-GUARDED on `_fidelity.has("airframe")` (slice 17 shows it, slice 16 still drops).
  Scenario `slice17_coupling.yaml` (δ=0.15 MANDATORY nonzero — the non-dead toggle; Cla=20; grav on, drag off): the
  live wire gives coupled (2187.8,3010.2) vs ballistic (3064.2,2257.3) → posdiff 1155 m; δ→0 straightens to 91 m.
  Four proofs green (verifier S17V OK: coupled CURVES vs point_mass ballistic posdiff 876 m [the INVERSE of
  slice-16's 0.0], lift keys coupled-only, replay bit-identical, δ→0 straightens; UI: cycler shows+wraps+set_fidelity,
  sliders set_param, slice-16 handshake STILL drops the button = value-guard both ways; smoke-load DONE; windowed
  shot: the CURVED coupled trail + nose leading the cyan v(γ) by the labeled α gap, button "airframe: pitch_coupled").
  Deferred (NAMED): **slice 18 = the inner α/g autopilot** (invert PN `a_cmd→α_cmd=a_cmd·m/(Q·S·C_Lα)→δ`, the
  slice-15 δ feeding `Cmδ·δ`; the `a_cmd/Q` divide = a crash-safety Q-floor) + the flight-condition aero g-limit
  `a_max_aero=Q·S·C_Lα·α_max/m` miss (distinct from slice-10's fixed a_max); induced drag; then bank-to-turn / 3-D
  (quaternion+ω) → radome/body-rate parasitic loop. (2488)

- **Slice 18 (§11 Tier-A "higher fidelity behind existing knobs" — `propagation` is the named seam) — TERRAIN
  MASKING + the 3-D client view COMPLETE**: the FIRST terrain in the project and the client's FIRST true 3-D view
  (a USER-DIRECTED insertion 2026-07-14 — the inner α/g autopilot slice17.md slotted as "18" SHIFTS to slice 19,
  trigger intact). New pure lib `terrain.jl`: an authored ANALYTIC Gaussian-hill heightfield (`h0 + Σ aᵢ·exp(…)`,
  ZERO RNG — nothing to desync), `terrain_clearance` (SIGNED min ray_z−h over interior samples, endpoints EXCLUDED
  [a mast can't self-block], fixed `s=i/(n+1)` grid ⇒ bit-exact (p1,p2) SYMMETRY), `terrain_los_clear` (the HARD
  shadow — knife-edge diffraction is the named rung above), `terrain_grid` (the row-major wire sample; layout
  pinned vs an ASYMMETRIC terrain — the transpose canary). `PROPAGATION_MODES` gains **:terrain** (free-space link
  budget + the LOS mask → `(0.0,false)` occluded — the below-horizon-policy shape; **no terrain entity ⇒ bit-exact
  :free_space**, the mismatched-EP `==` no-op precedent). Class **4a** (draw-invariant — detect_once draws
  unconditionally, the mask gates booleans; 3-rung RNG-lockstep pinned; introduce-safe, live-settable, NO guard —
  the FIRST 4a since slice 11, breaking the 14–17 4c streak). Terrain = a NON-PHYSICAL `kind: terrain` entity (the
  `:datalink` precedent; hills → FLAT `hillK_*` comp keys, ≤1 entity enforced, **LOAD-STATIC** — the handshake grid
  ships ONCE so hills are NOT live knobs [named deferral]); `_terrain_info` ships grid/extents/ids at handshake —
  **`terrain_grid` presence is the client's 3-D-view discriminator**. `<radar>.terrain_clearance_m` (signed,
  `_finite_coord`) is RUNG-gated (the slice-17 lift-keys precedent). NEW general lever: `ConstantVelocity` gains a
  presence-gated `alt_hold_m` comp (altitude becomes knob-addressable; absent prior ⇒ byte-identical). THE LESSON
  (probe, live wire, seed 18): the 120-m penetrator is DARK the whole approach behind the 250-m ridge → POP-UP at
  t=36.72 s / x=4819 m (clearance −208.6→+, SNR floor→50.7 dB, ZERO detections while masked); alt→1000 COLLAPSES
  the shadow (min clearance +31.4 m); free_space same seed tracks from frame 1 — altitude buys detectability, the
  clearance SIGN is the verdict. CLIENT: `_enter_terrain_mode` builds a CanvasLayer(−1)/SubViewport Node3D world —
  the heightmap ArrayMesh (height-tinted vertex colors), emissive markers, the LOS ray colored by the CORE's
  `visible` verdict (client NEVER re-tests occlusion), fading trail, orbit/zoom camera; sim(x,y,z-up)→Godot(x,
  z·2.5,−y) with T3D_VEXAG=2.5 DISPLAY-ONLY + HUD-labeled (§12). The shared button = the propagation cycler
  upgraded to the FULL 3-ring via PER-SCENARIO `_prop_rungs` (the `_autopilot_rungs` precedent, sliced from ONE
  `PROP_RUNGS` const — slices 1/2 keep the 2-ring, no phantom rung). Four proofs green (S18V: masked start at the
  exact floor + EXACTLY one transition @ x 4816 + detections only-visible + clearance-sign≡verdict + 2500-frame
  replay BIT-IDENTICAL through the masked draws + free_space contrast + alt collapse; S18UI: mode/grid/3-ring
  wraps/set_param/off-tree 3-D build + the plain-handshake 2-ring guard; smoke-load DONE; TWO shots: red ray dying
  into the crest "TERRAIN MASKED −205 m" vs green ray over it "LOS CLEAR +32 m" detected:YES). Banks the
  heightfield land CLUTTER needs. Deferred (NAMED): knife-edge diffraction; terrain multipath/clutter; fractal
  terrain; hill-knob grid re-ship; DF/ESM/seeker terrain occlusion. (2604)

- **Slice 19 (§11 Tier-A, the 6-DOF arc's CLOSED INNER LOOP) — the inner α/g AUTOPILOT COMPLETE**: the missile
  finally flies its own PN command *through the airframe* instead of by fiat. Slice 17's fin δ was a FIXED
  authored trim (the airframe curved, it did not AIM); slice 19 inverts the guidance command through the aero —
  **`a_cmd → α_cmd = a_perp·m/(Q_eff·S·C_Lα) → δ`** (`alpha_command` + `alpha_autopilot_delta`, the `:ff_fb`
  feedforward-trim-inversion + rate-damped feedback law) — on the **FIRST COUPLED AND GUIDED missile** in the
  project (slice 17 was open-loop, no target). THE LESSON: the achievable maneuver accel IS the FLIGHT-CONDITION
  lift ceiling **`a_max_aero = Q·S·C_Lα·α_max/m` ≈ 269**; the SAME PN law on `:point_mass` applies `a_ctrl` by
  fiat and **HITS (0.276 m)** while `:pitch_coupled` must MAKE its g from lift, the demand exceeds the ceiling
  **59%** of the approach, and it **MISSES by 295.168 m (1069×)**. The cap is DISTINCT from every prior one (the
  copy-paste false-claim trap): 10/12's `a_max` = an authored MAGNITUDE clamp, 15's `k_δ·δ̇_max` = a JERK cap and
  `δ_max` = a DEFLECTION cap — 19's is a **FLIGHT-CONDITION** cap (what the air gives you *right now*). **The
  ISOLATION is STRUCTURAL — `saturated == 0` FAILS and must NOT be copied from slice 15**: `a_max` clamps 560×
  INERTLY (3000 ≡ 1e7 bit-for-bit) because it clamps `a_cmd` UPSTREAM of the α inversion and the tighter clamp
  wins downstream ⇒ assert `max(a_max_aero) < a_max` (269 ≪ 3000) + `defl_sat == 0` (the FOURTH cap). **BINDING
  ≠ CAUSING** — the counterfactual licenses the claim: relaxing **α_max ALONE** (it enters ONLY the α_cmd clamp,
  absent from `pitch_moment`/`lift_accel`/`short_period_freq`) recovers **282 of 295 m = 95.4%**; the ~13 m
  residual is "the airframe + autopilot DYNAMIC TRACKING COST" (a §1 named approximation — NOT "short-period
  lag", NOT a projection effect). `:a_ctrl` STAYS OUT of the coupled force (adding it rebuilds the point-mass
  plant in an airframe costume and deletes the lesson — the 3rd occurrence of that trap); the `:alpha` rung's
  behaviour DEPENDS on `:airframe` (a_ctrl under `:point_mass`, δ under `:pitch_coupled`) — **the FIRST
  cross-fidelity dependency in the suite, written down, not implied**.
  **GATE-3 FINDING (blocking): the planned `speed` demo knob is DEAD** — `comp[:speed]` is consumed ONCE at load
  to build `e.vel` and read by NOTHING per-tick, and `reset` reloads the YAML; gate 0 swept it by re-authoring
  per run and gate 2's no-crash drag PASSES on a dead knob (**the dead-knob face of the false-fidelity class —
  4th in this arc, first caught at gate 3**). **`rho` is the live Q lever** (fetched every tick by BOTH
  integrate! and decide! ⇒ zero new consumer code; Q ∝ ρ exactly linear; confounded like speed [ω_sp ∝ √ρ] ⇒ DEMO
  only, α_max stays the causation knob; and unlike speed it can't break the first-CPA condition — a working
  speed knob at V0 > 825 would outrun the target). Knob **ρ ∈ [0.6, 1.3]** — bounded to the MONOTONE region: the
  miss PEAKS at ρ≈0.5 and FALLS below it (at ρ=0.1 it misses by LESS than the default — the missile stops trying
  and flies ballistically), which would REVERSE the lesson (the [[ewsim-df-ellipse-sigma-monotonicity]] pattern
  recurring). ρ-as-knob makes the constant-ρ approximation INTERACTIVE — **say "low dynamic pressure (thin air)",
  NEVER unqualified "high altitude"** (ρ is not derived from z; the exponential atmosphere is DEFERRED). The
  NOT-A-DEAD-KNOB TRIPWIRE now ships (verifier + `test_server` assert ρ MOVES `a_max_aero`, not merely that
  nothing threw). Class **4c** (physics-changing, NO RNG — truth-fed, no seeker ⇒ "draw-count invariance
  VACUOUS"; live-settable, NO guard — the 5th 4c after 14/15/16/17). CLIENT: the slice-17 airframe view REUSED
  wholesale (`_fid_kind="airframe"`) + the NEW headline `_draw_aero_strip` (cyan ceiling vs orange demand, breach
  band red, border lights on `aero_sat`) — **the plot is ILLUSTRATIVE and says so**: `aero_sat` keys off the ⟂-v
  PROJECTION while `a_demand` is full-magnitude, so the sets nest (the verifier asserts the FLAG, never a
  hand-rolled compare). Four proofs green (S19V: 295.186 vs 3.844 = 76.8× frame-sampled, replay posdiff 0.0, the
  ρ lever drops the ceiling 0.49× live, the α_max sweep recovers 95.4%; S19UI: the value-guard THREE ways — 16
  drops / 19 shows / 18 stays 3-D; smoke-load + 16/17/18 re-smoked + all 9 prior UI tests green; TWO shots at tick
  4130: coupled los 295.19 / a_cmd 282 vs a_ach 180 / α −7.8° vs point_mass los 3.84 / track_gap 0). Deferred
  (NAMED at the time — **since RESOLVED, see slice 20**): the exponential atmosphere (makes "high altitude"
  REAL); a SCALAR rate-limited fin inside the coupled loop (slice-15's banked δ → the guidance limit cycle) —
  **that candidate is now DEAD, killed at gate 0: `δ_max` SHADOWS `δ̇_max`, `docs/plans/slice20.md`**; induced
  drag (C_Di ∝ C_L² — the g-bleeds-V-lowers-Q spiral) — **DONE, slice 20**; nonlinear C_L(α)/true stall;
  bank-to-turn / 3-D (the out-of-plane discard dies only there) → the radome/body-rate parasitic loop (now the
  empirically-motivated home of the limit cycle); a seeker in the coupled loop (flips back to 4a/RNG-live). (2864)

- **Slice 20 (§11 Tier-A) — INDUCED DRAG: THE MISSILE LOWERS ITS OWN CEILING BY MANEUVERING**: the project's
  FIRST DEGENERATIVE SPIRAL, cashing an approximation slices 17/19 shipped EXPLICITLY ("lift is drag-free /
  speed-preserving ⟂ v"). Lift ⟂ v turns the path; **induced drag ∥ −v̂ SENDS THE INVOICE** — `C_Di = K·C_L²`,
  `a_ind = −(Q·S·K·C_L²/m)·v̂` (`induced_drag_accel`, `lift_accel`'s ORTHOGONAL COMPLEMENT: same α, same Q·S;
  one turns at constant speed, one slows without turning) — and the invoice is paid in the very currency that
  buys the turn: **pull α → bleed V → Q falls → `a_max_aero` falls → the ceiling CATCHES the demand → you can't
  pull → you miss.** Slice 19: the ceiling is a flight condition that BINDS. Slice 20: it is a flight condition
  **YOU DEGRADE BY USING IT** — slice 19 moved it with the ρ knob (an ENGINEER dialling a flight condition);
  here the MISSILE moves it, by turning. **NO new cap — it makes cap #4 SELF-LOWERING; the novelty is the
  FEEDBACK.** **THE HEADLINE IS THE CEILING COLLAPSE RATIO** (0.92× FLAT → **0.12×**, an 8.4× fall WITHIN one
  run) — pure ceiling and monotone-safe BY CONSTRUCTION, so it is what evidences "lowers its own CEILING";
  `aero_sat 0/366 → 55.1%` is the CONSEQUENCE (it moves on ceiling AND demand), though a stark one: **at K=0
  the ceiling NEVER BINDS ONCE.** ρ/S/C_Lα/α_max/mass ALL HELD; only K changed. Wire (frame-sampled, seed 20,
  LOS-gated at **r > 1000 — NOT slice-19's 300**): K=0 miss 8.59 (HIT) / K=0.15 103.14 / K=0.3 **714.12** (83×);
  `defl_sat` 0 in every arm; replay posdiff 0.0. **⚠ THE CLAIM IS BOUNDED (the sharpest constraint here):
  "bleed→ceiling→miss" is what ANY speed loss does — matched on ΔV a parasitic `cd_area` reproduces it (45.02 m
  /173.2 vs 44.17/176.3) — so ONLY the α²-SOURCE makes it *induced*, and that ships as a TOOTH, not prose**
  (straight coast: induced <1 m/s vs parasitic >50, a >50× split — `test_missile.jl` "THE DISCRIMINATOR").
  **⚠ "DEGENERATIVE SPIRAL", NEVER "positive feedback"**: the speed bleed is SELF-LIMITING (bill ∝ V²α² ⇒ dV/dt
  PEAKS at −88.8 then DECAYS to −35.8; V asymptotes ≈213, ceiling ≈25 — neither reaches 0). The positive sign is
  on the TRACKING ERROR and only CONDITIONALLY (below the ceiling PN converges — *negative* feedback, which is
  WHY PN works; past the crossing the sign flips). **⚠ NOT "a harder engagement costs more" — REFUTED** (the
  attributable bill FALLS 194→117 as the target jinks: shorter ToF + the α clamp). The target does NOT maneuver:
  **the missile pays for its own turn onto the collision course.** Byte-identity is STRUCTURAL — a SECOND
  closure gated on `haskey(:af_k_induced)`, the else-arm slice 17/19 VERBATIM (never `+ a_ind` trusting
  K=0→zero: the `-0.0` trap); loader PRESENCE-gated on the KEY not the BLOCK (16/17/19 all have airframe
  blocks); K's SIGN validated (a negative K ACCELERATES). **NO new rung** (a rung must name physics the knob
  can't express; `:free` IS K=0 — the slice-16 `af_cma` precedent); **ONE knob** `af_k_induced ∈ [0, 0.3]`
  (MEASURED: monotone+clean to 0.6; at K≥0.8 `defl_sat` 0→1289 and α_pk overshoots α_max = slice-19's LEAK ⇒ a
  2× margin) — **α_max/ρ DISQUALIFIED and asserted ABSENT** (α_max now feeds the bill through the ACHIEVED α ⇒
  no longer isolated, unlike slice 19 where it touched only the clamp; ρ moves ceiling AND bill). Class **4c**
  (6th consecutive; no RNG ⇒ draw-invariance VACUOUS). **ZERO new client code** — slice 19's airframe view
  carries it (the aero strip already plotted the ceiling; it just starts FALLING). Four proofs green (S20V;
  S20UI 4-way value-guard + exactly ONE slider; smoke; shot at tick 6000 aimed at the CLAIMED branch — cyan
  ceiling 269→138, demand crossing at 301, AERO SAT lit). Slices 1–19 byte-identical, proven ON THE WIRE (the
  16/17/19 verifiers reproduce STATUS to the digit). (2935)

- **Slice 21 (§11 Tier-A) — THE EXPONENTIAL ATMOSPHERE: THE CEILING YOU LOWER BY CLIMBING**: the honest completion
  of 19/20's constant-ρ, and the aero arc's last opening deferral. Slices 19/20 were under STANDING ORDERS to say
  "low dynamic pressure (thin air)" and NEVER unqualified "high altitude" — ρ was a number an ENGINEER TYPED, not a
  consequence of where the missile flew, and only V could move `Q = ½ρV²`. Here `ρ = ρ₀·exp(−z/H)` and the phrase is
  EARNED: **climb → ρ(z) falls → Q falls → `a_max_aero` falls → you cannot pull → you miss** (⚠ THE CAVEAT LIFTS
  ONLY HERE — a 19/20 wire has no `af_scale_height` and runs `:constant`; no global find/replace). **NO new cap —
  the SAME cap #4, a THIRD MOVER**: 19 the ENGINEER moved it (the ρ knob), 20 the MISSILE moved it by TURNING (V
  bleed), 21 by **WHERE IT FLIES** — and the climb is not optional, it is the only way to a 14 km target.
  **⭐ THE HEADLINE IS THE ρ-FACTOR, AND IT FACTORIZES EXACTLY** — what slice 20 could never do: since
  `a_max_aero = ½ρ(z)V²·S·|C_Lα|·α_max/m`, the within-run ceiling ratio is IDENTICALLY `[ρ(z)/ρ(z₀)]·[V/V₀]²`, an
  ALGEBRAIC identity — so ALTITUDE and SPEED separate with **NO residual** (measured ON THE WIRE at the
  ceiling-min frame: residual **EXACTLY 0.0**). **⭐⭐ THE SHARPEST FACT: the twin's ρ-factor is EXACTLY 1.0** (`==`).
  The `:constant` arm's ceiling ALSO falls (0.524×) — but that is GRAVITY bleeding V, and its model books **100% of
  it to speed BY DEFINITION**, because it has no z in its ρ at all. **That is the whole slice in one number**, and
  it is WHY `rho_air` is KEY-gated not RUNG-gated (the twin's half of the headline must BE on the wire; rung-gating
  would leave the client dividing `2·q_dyn/V²` — physics in GDScript, convention 13). New pure lib `atmosphere.jl`
  (the project's SMALLEST — one function + one mode tuple; z floored at 0 and H at 1.0, BOTH real crash paths: an
  RK4 stage probes z<0 → Inf → NaN pos, and H=0 with z=0 is `0/0`). **★ THE KNOB-vs-RUNG DISCRIMINATOR (the general
  result, in atmosphere.jl's header because it outlives the slice)**: *is the off-state (a) a distinct code path and
  (b) NOT knob-reachable?* KNOB (`af_cma`, `af_k_induced`) = an IN-DOMAIN slider value; RUNG (`:airframe`,
  `:propagation`, `:atmosphere`) = a distinct path no knob reaches. Constant ρ is `H = ∞`, a LIMIT POINT — so slice
  20's "a `:free` rung IS K=0" does NOT transfer. The tempting refusal (":constant names no physics ρ(z) lacks")
  was ADVISOR-KILLED: it is word-for-word `point_mass`/`free_space`, so it would delete two shipped rungs.
  **THE STAGE-z FIX**: the slice hinges on an argument ALREADY THERE — `_integrate_coupled!`'s closure has been
  `f(P,Vv,TH,Q)` since slice 17 and `P` (the RK4 STAGE POSITION) **was read by nothing**; ρ(z) finally reads it at
  ZERO contract change (slice 17's stage-θ fix exactly; params REBUILT PER STAGE keep the aero lib z-FREE — it
  never learns about altitude, it just gets a `p` whose rho is the stage value). Byte-identity STRUCTURAL: the
  else-arm is 17/19/20 VERBATIM and serves BOTH key-absent AND `:constant` (never `exp(0)==1` — the `-0.0` trap).
  **`:atmosphere` is INERT without `:pitch_coupled`** (`_atm_on`'s third conjunct — a gate-3 LATENT BUG FIX: ρ(z)
  reaches the coupled path only, and slice-16's `_integrate_airframe!` would otherwise have INTEGRATED θ/q in ρ(z)
  while pos/vel flew ρ₀ = half the missile in each atmosphere; the slice-13/14 inert-without-its-host shape).
  ⚠ **NOT zero client code** (unlike slice 20): the lesson IS a button and the scenario ALSO ships `:airframe:
  pitch_coupled` HELD — **two view-claiming fidelity keys, a first** — so `_setup_spatial_fid_btn` checks
  `:atmosphere` FIRST (the slice-13/14 one-button rule, 3rd occurrence); everything else REUSES slice 19's airframe
  view. Class **4c** (7th consecutive; no RNG ⇒ draw-invariance VACUOUS; live-settable, no guard). ONE knob
  `af_scale_height ∈ [6000,25000]` (MEASURED: H≤3000 LEAKS α_max — slice-19 FINDING 14; ρ₀/α_max/K DISQUALIFIED and
  asserted ABSENT; **launch altitude is a DEAD knob** — position is load-only, `reset` reloads the YAML: **H is the
  live face of z**). ⚠ **The miss does NOT reverse in H — that prediction was REFUTED**: slice 20's K reversed
  because its penalty was SPEED; thin air costs ZERO speed, only AUTHORITY. Wire (frame-sampled, seed 21, LOS-gated
  r>1000): `:exponential` miss **360.8** / ceiling 239→31 / ρ-factor **0.248** / aero_sat 25.6% vs `:constant` miss
  **3.1** (**117×**; per-tick 1.95/185×) / **aero_sat 0/2628 — NEVER BINDS ONCE**; H=25000 → 7.1; `defl_sat` 0 in
  every arm; replay posdiff 0.0. Four proofs green (S21V; S21UI with a **FIVE-WAY** value-guard; smoke + 16–20
  re-smoked; shot at the CROSSING — ceiling 81.7 vs demand 83.4, AERO SAT lit). **⚠ Three gate-3 bugs, all in the
  PROOF not the physics**: `%.2e` is NOT a GDScript specifier (an unknown one makes the WHOLE `%` fail SILENTLY →
  the headline printed as `"%.9f"` on a GREEN run — *a number that does not print is not a proof*); the pass text
  QUOTED PER-TICK truth while the file measures FRAMES (**a miss samples faithfully — radial rate is 0 at CPA — but
  a HIT samples COARSELY**: ~13 m between samples); and a MAGIC-MULTIPLE tooth (now pinned against the EXP arm's
  MEASURED ρ-factor). (3182)

- **Slice 22 (§11 Tier-A) — NONLINEAR `C_L(α)` / TRUE STALL: THE CEILING THE AIRFRAME SETS**: slices 19/20/21 gave
  cap #4 three movers and **ALL THREE MOVED Q** (the engineer's ρ knob; the missile's own turn via V; where it
  flies via ρ(z)). **Slice 22 moves the OTHER FACTOR** — all three assumed the lift curve is a STRAIGHT LINE out
  to α_max. Past α_stall the flow SEPARATES: **C_L PEAKS and FALLS**, and the ceiling is the curve's own INTERIOR
  PEAK — no amount of Q buys past it. **THE REVERSAL IS NEW IN THE SUITE**: every prior cap is a MAGNITUDE that
  SATURATES; this one is a **DERIVATIVE THAT CHANGES SIGN** — past the peak, pulling HARDER turns you LESS *and*
  costs you MORE (which is why the user chose true-drop over a saturating curve; a saturating one cannot produce
  the control-loop reversal at all). ⭐ **THE HEADLINE IS AN EXACT IDENTITY**: at fixed Q the linear→stall ceiling
  ratio is IDENTICALLY `α_stall/α_max` (Q, S, C_Lα, m ALL CANCEL) — 471.435… → 269.391…, ratio ≡ 4/7 with **|Δ| =
  0.0 bit-for-bit**, slice 21's ρ-factor identity in a new letter. ⚠ **A SAME-INPUTS FORMULA TOOTH, NEVER a
  run-vs-run** (separation drag makes V, hence Q, diverge between arms). **KNOB, NOT RUNG — and the plan predicted
  the OPPOSITE**: it asserted linear was `α_stall → ∞` (a limit point ⇒ rung) and gate 0 **REFUTED** it — the
  achieved α SELF-LIMITS to ~0.24 over every reachable state, so a finite α_stall ≥ 0.25 is linear-in-effect and
  **the knob's own TOP is the in-scenario linear twin**; `test_aero_curve.jl` ASSERTS the fidelity's absence.
  ⚠ **α_max 0.35 > α_stall 0.20 INVERTS SLICE 19**: reaching stall via the FINDING-14 LEAK was REJECTED as
  gain-dependent and CIRCULAR (closing that leak is this slice's own payoff), so the autopilot **COMMANDS INTO
  STALL** and THE PHYSICS SETS THE WALL. The inner loop keeps inverting on the LINEAR C_Lα deliberately — it is
  REALISTIC (an autopilot carries a linear model of its airframe ⇒ **slice-19's command-vs-achieved gap MADE
  PHYSICAL**) and it SIDESTEPS the multivalued past-peak inverse (a named deferral, not a solved problem).
  Separation drag is **MANDATORY, not a lever** (measured 0.9% over its whole range — a PHYSICALITY term; the
  teeth carry it: exactly 0 below stall, EVEN in α, along −v̂, moving OPPOSITE to induced drag past the peak) and
  **slice 20's induced term is NOT "fixed"** — `C_Di = K·C_L²` falling past the peak is CORRECT physics.
  **⭐⭐ THE SHARPEST GATE-3 FINDING: `aero_sat` DOES NOT DISCRIMINATE AT ALL** — it fires **53/215 frames on the
  PARKED LINEAR arm and 53/215 on the STALL arm, the SAME COUNT**, because it keys off the **α_max CLAMP both arms
  SHARE** while the ceiling that moved is the interior peak. So there is a real regime **past the physics ceiling
  with the command not yet pegged** where it stays 0. **`post_stall` is the discriminator: EXACTLY 0 vs 56.**
  ⇒ the ONE client edit (**NOT zero, unlike slice 20**): the aero strip's breach indicator keys on `post_stall`,
  presence-gated so 19/20/21 are byte-identical; the button stays the AIRFRAME cycler by slice-20's PRECEDENT.
  **TWO SCENARIOS, and the split is a MEASURED CONFIG CONFLICT** (the lift half needs k_drop 0.7 / δ_max 0.4, the
  departure half k_drop 1.0 / δ_max 1.0, and at 0.7 the cliff is INVISIBLE) — one verifier auto-detects which.
  **HALF B = RELAXED STATIC STABILITY**: *a statically unstable airframe is perfectly flyable — UNTIL THE
  AUTOPILOT RUNS OUT OF AUTHORITY; the THRESHOLD is the lesson, not the tumble.* ⭐⭐ **A THREE-POINT CLAIM WHOSE
  LESSON IS THE MIDDLE** — 0-vs-8 would show "neutral vs lost", a WEAKER and DIFFERENT claim, because cma_post 0 is
  **NEUTRAL past the break, not unstable at all** (sentinel SILENT). The lesson is **cma_post 4: the ω_sp sentinel
  FIRES (60 frames / 947 ticks — genuinely no short-period mode) and the autopilot HOLDS IT ANYWAY** (α@500 0.434,
  miss 1.078× baseline); only at 8 does it LOSE it (α@500 1.008 = 57.8°). ⭐ **SLICE 16's ω_sp SENTINEL FIRES IN
  FLIGHT — FIRST TIME IN PROJECT HISTORY** (built for an AUTHORED Cmα ≥ 0; reaches the wire as FINITE_CEIL, never
  a NaN), and it is **SLICE 16's TUMBLE NOW SELF-INFLICTED** — an engineer typed the unstable case there; here the
  airframe FLIES ITSELF INTO IT. ⚠ **THE MISS IS NOT THE METRIC for half B** (+1.4% even at full tumble — a
  missile that departs 0.7 s before CPA keeps its momentum) ⚠ and **"time with ω_sp ceiled" RUNS BACKWARDS**
  (60 frames at cma_post 4 vs 33 at 8 — α blows past α_sat into the deep-stall RESTORING region), so it is a
  BOOLEAN tell, never a severity measure. ⚠ **α IS SAMPLED AT FIXED RANGE (500 m), NOT AT CPA** — the break is
  reached at t=3.12/r=1475 in EVERY arm, α_pk lands ON the CPA frame, and **the lift file's LOS gate of 1000 would
  DELETE this lesson** (α@1000 spans only 0.297→0.399): the correct gate DIFFERS between the halves. Knob domains
  MEASURED: `af_alpha_stall ∈ [0.15,0.35]` (the miss TURNS at ≈0.12 and REVERSES — the 3rd occurrence of that
  pattern) and `af_cma_post ∈ [0,10]` (defl_sat exactly 0 through 10, monotone, first binds 65 at 10.5 — a ~1.03×
  margin, NOT slice-20's 2×, stated rather than hidden). ⚠ **NEVER quote gate-0's 2.7779 departure α** — it was
  measured with δ_max 0.4 BINDING, which AMPLIFIED the divergence (relieving it drops α_pk 3.02 → 1.22); the clean
  progression is 0.64 → 0.97 → 1.22. Class **4c** (8th consecutive; no RNG ⇒ draw-invariance VACUOUS);
  **INERT without `:pitch_coupled`** (the third conjunct is deliberate — `pitch_moment` is live on the point-mass
  rotational path, so without it half the missile would fly a breaking moment and half a linear-aero fiat accel);
  **stall × ρ(z) is a LOAD ERROR**, refused rather than silently branch-ordered. Four proofs green (verifier both
  halves; UI test with FOUR teeth on the G10 edit incl. the MIRROR case proving a SWITCH not an `or`, + a SIX-WAY
  value-guard, + all seven prior UI tests re-run; smoke-load both servers; TWO shots — "POST-STALL" lit on the
  stall wire, and the departure with `omega_sp 1000000000`, the nose 34.2° off velocity, and the trail CURLING
  BACK ON ITSELF). Deferred (NAMED): a STALL-AWARE AUTOPILOT (the multivalued inverse); HYSTERESIS; Mach;
  **ROLL/YAW DEPARTURE — the sharpest remaining approximation** (this one departs strictly IN-PLANE; dies only
  with bank-to-turn / 3-D); DEPARTURE RECOVERY / a spin model (the ONSET ships, not the aftermath). (4180)

- **Slice 23 (§11 Tier-A, the FIRST slice of the bank-to-turn / 3-D arc) — 6-DOF SUBSTRATE + SKID-TO-TURN: THE
  OUT-OF-PLANE ENGAGEMENT**: cashes the sharpest approximation the whole aero arc carried. Since slice 19,
  `alpha_command` PROJECTS the guidance command onto the in-plane direction `n̂ = (−sinγ, 0, cosγ)` and **DISCARDS
  the out-of-plane component** — a target off the x–z plane was *unflyable BY CONSTRUCTION*. Slice 23 makes `att` a
  GENUINE 3-D quaternion integrated from a body-rate vector `ω = (p, q, r)` (NEW comp keys `:att_q`/`:omega_body`,
  PARALLEL to `:pitch_theta`/`:pitch_q`), keeps the guidance command's FULL 3-D direction, and adds a SKID-TO-TURN
  autopilot that makes lift in BOTH body planes at once (α → pitch lift, β → yaw side-force). **THE LESSON: a
  pitch-plane airframe can only pull g in the plane it is already in; STT makes lift in two body planes at once —
  and the out-of-plane target that was unflyable becomes a hit.** New pure lib `airframe3d.jl` (reuses frames.jl's
  quaternion algebra). Gate-0 (8 probes) HELD the plan: **P4 → the RESULTANT clamp `hypot(α,β) ≤ α_max`** (the
  total maneuver-g ceiling is the SAME `a_max_aero` as the pitch plane — STT REPOINTS the authority in 3-D, it does
  not get MORE); include the ω×Iω term; a static cross-range target (the discard's miss ≈ Y is clean). One new
  load-bearing finding: **the pitch/yaw MOMENT SIGN is NOT symmetric** (physical nose-up is a −y body rotation but
  nose-toward-+y is a +z, so the pitch moment is NEGATED onto −y and the yaw is not, `α̇ = −ω_y`, `β̇ = +ω_z` — the
  #1 SIGN TRAP's 5th occurrence). `:airframe` gains a THIRD rung `:six_dof` (the A/B: `:pitch_coupled` discards and
  misses, `:six_dof` STT intercepts). Wire (Y=2000 cross-range, ρ=0.3, static aero-free target): `:pitch_coupled`
  miss **2002.37 m** with `max|pos_y| = 0.0 EXACTLY` (fully discarded — never leaves x–z) vs `:six_dof` **0.230 m**
  with `max|y| → 2720` (it TURNED); ~8700× (frame-sampled 399.6×). The CAUSATION lever `af_cy_beta → 0` kills the
  yaw authority and DEGENERATES the STT plant EXACTLY back to the discard. The reduction golden must SHRINK with dt
  (the advisor's wiring-bug detector — 4.46e-11 → 2.14e-12, ~20.8×, not `==`). ⚠ A gate-2 ADVISOR CATCH — the
  slice-21 `_atm_on` latent-bug class recurring: the `build_env!` six_dof readout block was first key-gated on
  `haskey(:att_q)`, which is never deleted, so a cross-toggle off `:six_dof` fired the stale block on a FROZEN
  attitude; FIXED by rung-gating BOTH rotational blocks on the LIVE `:airframe`. CLIENT: a NEW handshake
  discriminator `airframe_6dof` (a missile carrying authored `:af_cy_beta`) upgrades to a TRUE 3-D view REUSING
  slice-18's terrain SubViewport machinery (`_mode = "airframe3d"`) MINUS the heightfield; the `:airframe` cycler
  is now 3-RING via a PER-SCENARIO `_airframe_rungs` (slice 17/19 stay 2-ring — six_dof is a dead rung there). Class
  **4c** (9th consecutive — truth-fed PN, no seeker ⇒ "draw-count invariance" VACUOUS; live-settable, no
  set_fidelity guard). Four proofs green (verifier: the discard/hit miss split + af_cy_beta→0 causation + replay
  bit-identical; UI: the 3-D routing + 3-ring cycler + FIVE-way multi-view value-guard + all seven prior UI tests
  re-run; smoke-load; TWO contrasting shots — the six_dof trail CURVING out of the plane vs the pitch_coupled
  STRAIGHT trail, "cross-range +1024 m" vs "+0 m"). Slices 1–22 byte-identical. Deferred (NAMED): **slice 24 =
  BANK-TO-TURN + roll-lag** (the same substrate, α-only lift + a finite-bandwidth roll autopilot, the `:steering`
  rung); aero+inertial cross-coupling / departure; a SEEKER in the 6-DOF loop; an out-of-plane MANEUVERING target;
  induced/separation drag + ρ(z) on the 6-DOF path. (4276)


(The missile guidance arc — slices 8–12 — and its CAPSTONE slice 14 are COMPLETE; the countermeasures arc opened
with slice 13. HANDOFF §10 items 1–13 — the committed roadmap — are all DONE; slices 15–23 are into the §11 Tier-A
horizon — slice 15 the actuator/fin half, slice 16 the 6-DOF airframe's rotational half (pitch-plane θ,q), slice 17
the α→lift→γ TRANSLATION-COUPLING half (the real path-changing `:airframe` toggle), slice 18 terrain masking + the
3-D client view, slice 19 the CLOSED INNER LOOP (`a_cmd→α_cmd→δ`) + the flight-condition g-limit — which COMPLETES
the Tier-A "6-DOF airframe + actuator/fin dynamics" entry in the pitch plane (15 = fin, 16 = rotation, 17 = the
α→lift coupling, 19 = the closed loop) — slice 20 INDUCED DRAG, which makes that closed loop's ceiling
SELF-LOWERING (the aero arc's first feedback, and the first slice whose lesson is a KNOB with no button at all),
slice 21 the EXPONENTIAL ATMOSPHERE, which gives that same ceiling a THIRD mover — WHERE THE MISSILE FLIES —
and CLOSES 19+20's constant-ρ approximation ("high altitude" is now earned language, not a standing caveat), and
slice 22 NONLINEAR C_L(α) / TRUE STALL, which finally moves the OTHER FACTOR: 19/20/21 all moved Q, while all three
assumed the lift curve runs straight out to α_max. It does not — past α_stall C_L PEAKS AND FALLS, so the ceiling
is the curve's own INTERIOR PEAK, and the cap stops being a MAGNITUDE THAT SATURATES and becomes a DERIVATIVE THAT
CHANGES SIGN. Slice 22 also closes the ceiling-LEAK path that BOUNDED slice 21's H floor, and its second half
(RELAXED STATIC STABILITY) makes slice 16's authored tumble SELF-INFLICTED — the airframe flies itself unstable,
and slice 16's ω_sp sentinel fires in flight for the first time in the project's history.
**The slice-20 slot was CONTESTED**: the planned SCALAR rate-limited fin inside the coupled loop [the guidance
limit cycle] is **DEAD, not deferred** — gate 0 killed it in 4 probes (`δ_max` structurally SHADOWS `δ̇_max`: the
fin only needs to move fast when the command does, which requires high k_α or low damping, and BOTH peg deflection
first — see `docs/plans/slice20.md`, a worthwhile general result). **The FULL 6-DOF airframe is now UNDERWAY:
slice 23 OPENED the bank-to-turn / 3-D arc with the 6-DOF substrate + SKID-TO-TURN — the pitch-plane out-of-plane
discard finally dies (the out-of-plane target, unflyable BY CONSTRUCTION since slice 19, now intercepts). Scoped
STT-first as a 2-slice arc: slice 24 = BANK-TO-TURN + roll-lag (the same substrate, α-only lift + a
finite-bandwidth roll autopilot, the `:steering = (:skid_to_turn, :bank_to_turn)` rung — against the out-of-plane
maneuver, BTT misses where STT hit) is the NEXT named candidate.** Slice 23's departure note: it departs strictly
IN-PLANE and its target is STATIC; the AERO + INERTIAL CROSS-COUPLING / DEPARTURE that makes a real BTT airframe
go OUT-OF-PLANE during a hard roll (non-diagonal I, Clβ/Cnp/Clr, the radome/body-rate parasitic loop) is a later
lesson (diagonal I + symmetric cruciform + coordinated flight keep 23/24 clean). What else remains of §11
Tier-A/B/C: land clutter [terrain banked the heightfield], the radome slice (needs a SEEKER in the 6-DOF loop →
class flips back to 4a/RNG-live). ⚠ Slice 21 did NOT finish the
atmosphere: ρ(z) reaches the COUPLED airframe path ONLY. The point-mass/ballistic drag path keeps a constant ρ
because `dynamics.jl`'s steppers take a `v -> a(v)` closure with NO position in it, and changing that contract to
`(p,v) -> a` touches slice 8's `rk4_step`/`euler_step` — the byte-identity surface of EVERY ballistic slice — for a
path carrying no altitude lesson. A named deferral, and its own slice. Nor is it §11's RF "layered atmosphere /
ducting" entry, which lives behind the `propagation` knob and touches the radar path — do not conflate them.)

## Conventions / hard-won disciplines

The patterns that recur across every slice. Each names its teeth — grep the file, don't
paraphrase away the specifics.

1. **A slice = 3 gates.** Pure primitives (a `*.jl` lib, closed-form + MC tests) → wired
   subsystem (the tick contract) → scenario + Godot view + verifier. A new mode-const lib is
   included **before `radar.jl`** so `LIVE_FIDELITY_MODES` can reference it.

2. **Byte-identity is the master check — slices are additive.** A new slice must leave every
   prior slice bit-for-bit identical. Never touch a shared symbol on the radar/detection path.
   Proven by the `_sample_z` N_p=1 **absolute golden** (`test_detection.jl`) + `test_determinism.jl`.
   `test_determinism` only compares run-A-vs-B, so it CANNOT catch a draw-ORDER regression — the
   absolute golden does (it caught two real 1-ULP desyncs, e.g. `√(snr/2)` vs `√snr·√½`).

3. **Draw-topology hazard — the sharpest determinism trap.** The per-look RNG draw *count* must
   be invariant to fidelity rung, slider value, AND target position/SNR. Gate the
   detection/telemetry on snr/visible — **never the draw**. `detect_once`/`_draw_profile!`/
   `_draw_toa_stream`/`_draw_pseudoranges` draw unconditionally; gating a draw desyncs replay.

4. **Three fidelity classes — don't conflate them (the copy-paste false-claim trap):**
   - **(a) draw-invariant RNG rungs** — a toggle keeps the RNG in lockstep and changes only
     detection booleans / telemetry values; introduce-safe (namespaced by consumption — nothing
     reads the key without its subsystem). `:propagation`, `:ep`, `:estimator`, `:deinterleaver`,
     the GPS error toggles, `:raim`.
   - **(b) draw-topology-flipping** — `:cfar` alone: *introducing* it flips point→profile draws →
     replay desync, so `set_fidelity` **rejects introducing** it (switching among cfar rungs is
     bit-identical).
   - **(c) physics-changing, no RNG** — `:integrator`, `:autopilot`: a toggle CHANGES the
     trajectory. "draw-count invariance" is *vacuous* here — do NOT copy the toggle-bit-identical
     language; it's a false claim (advisor catch).

5. **A live knob can never crash a tick.** A throw inside `build_env!`/`observe!`/`decide!`/`tick!`
   lands in the session's IO/EOF-only catch and silently drops the connection. Two guard sites:
   **validate-at-LOAD** for immutable authored inputs (bandwidth>0, σθ>0, pri>0, mass>0,
   cd_area≥0, tau/a_max>0, even `n_train`, `n_cells≥1`, ≥2 sensors, ≥4 sats, fidelity rungs);
   **clamp-at-CONSUMER** for live sliders (odd `n_train`→`max(2,2*(raw÷2))`, σθ floor, `R_j=0`
   skip). Only declared **knobs** are live-settable.

6. **No Inf/NaN to JSON.** `_snr_db_wire` floors dB to `_SNR_DB_FLOOR=-120`; `_finite`/
   `_finite_coord` clamp readouts to the exported `FINITE_CEIL=1e9`. A null (F⁴=0), a mask, S→0,
   a singular geometry ships huge-but-finite — never `±Inf`/NaN. The class of the slice-1 `%g` bug.

7. **One-list-no-drift for mode tuples.** `PROPAGATION_MODES`/`CFAR_VARIANTS`/`ESTIMATOR_MODES`/…
   are defined ONCE in the pure lib and **referenced** by `LIVE_FIDELITY_MODES` and the server's
   `set_fidelity` validation — never re-listed (the drift-catch).

8. **Telemetry-phase gotcha.** `tick!` calls `empty!(w.env)` immediately after phase-1
   `integrate!`, wiping any phase-1 telemetry. So a force-integrator publishes its readout from
   **phase-2 `build_env!`** (post-`empty!`); a `decide!` subsystem is **phase 4** (post-`empty!`,
   writes `w.env[:telemetry]` directly); the radar readout is **phase-3 `observe!`**.

9. **One lesson per scenario.** Don't stack fidelities that muddy a lesson (slice-3 CFAR OMITS
   `:propagation` so two_ray nulls can't inject zeros; slice-4 splits the 2×2 EP lesson across two
   scenarios). The shared client fidelity button is unambiguous only with one toggled fidelity.

10. **Probe empirically, THEN pin against the live wire oracle.** Tune showcase numbers with a
    throwaway probe (link-budget SNR / masking / crossover / DOP resist hand-derivation), then pin
    tests against the ACTUAL `_target_snr` / `build_env!→observe!→decide!` path — NOT a
    hand-recompute (which replicates any decomposition slip). The coverage grid is pinned
    cell-for-cell vs the live oracle.

11. **Test teeth, not tautologies.** Explicit `atol` (rtol-`≈0` always passes); MC in a Wilson 4σ
    band using its OWN `Xoshiro` (never `w.rng`); an EXTERNAL anchor (Swerling loss ordering,
    `1/(1+Kp)` undershoot, common-α `Pfa_GO≤Pfa_CA≤Pfa_SO`) not a self-calibrated round-trip; a
    mismatched-EP no-op is a bit-exact `==` (not "calibrated to pass"); an INDEPENDENT recompute
    (a *different* algorithm) as the oracle catches a transpose.

12. **§9 shared libs are pure, measurement-agnostic, and cross-domain.** `geometry.jl`/
    `estimation.jl`/`frames.jl`/`gnss.jl` have no `w.rng` and are dependency-free closed-form (no
    LinearAlgebra — the `_range` house style). The same `gauss_newton` fixes a DF emitter (N=2)
    and a GPS receiver (N=4); the pseudolinear path keeps the stable 2×2 cofactor. `frames.jl` is
    the 3-D superset of `geometry.jl`'s 2-D (conceptually shared, NOT code-merged).

13. **The Godot client is pure — zero physics.** One protocol impl (`SimClient.gd`, referenced by
    `preload` not `class_name`). One adaptive `Sandbox.tscn` picks its view from the handshake
    (`range_axis_m`→cfar, `pri_axis_us`→esm, `estimator`+no-axis→geoloc plan, `raim`→gps sky,
    `integrator`/`autopilot`→spatial). CORE outputs (threshold curve, error ellipse, histogram)
    are DRAWN from telemetry — α/cov NEVER recomputed in GDScript. `_update_readout` skips Array
    telemetry (the `float()`-crash watch-item).

14. **Every gate-3 ships four proofs:** a headless `sliceN_verify.gd` (drives the real server,
    asserts the lesson as a number + held-seed bit-identical replay across a rung toggle); a
    `sliceN_ui_test.gd` (mock client, no server — the button/slider path); a `Sandbox.tscn`
    headless smoke-load (server `DONE` ⇒ scene connected, catches parse bugs); and a windowed
    **shot-harness** capture to eyeball `_draw` (Godot skips `_draw` headless). See
    [[ewsim-godot-headless]].

15. **Batches own their OWN seeded stream** (never `w.rng`) so a sweep can't desync the live trace
    — the *distribution* path (no byte-identity assert; the Threads/GPU seam). Determinism is CPU.

## Running a showcase (the per-slice pattern)

Each slice `N` ships `scenarios/sliceN_*.yaml`, a `net/sliceN_verify.gd`, and a
`net/sliceN_ui_test.gd`. Exact names + the lesson to look for are in `docs/STATUS.md`.

- **Live:** `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/sliceN_*.yaml`, then
  launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects the view). Cycle the
  fidelity button / drag the sliders to drive the lesson. The server serves **one** client then
  exits — restart per session.
- **Headless proof:** start that server, then `godot --headless --path clients/godot --script
  res://net/sliceN_verify.gd` (exit 0 = pass). The UI test needs no server:
  `… --script res://net/sliceN_ui_test.gd`.
- **All tests:** `pwsh tools/test.ps1`. (On this machine, see [[ewsim-godot-headless]] for the
  `_console.exe` / non-`pwsh` invocation caveats.)
