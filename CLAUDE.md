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

**Slices 1–18 COMPLETE & green — 2604 tests. The committed roadmap (HANDOFF §10 items 1–13) is DONE; slices 15–18
are into the §11 Tier-A horizon — slice 15 did the actuator/fin half of "6-DOF airframe + actuator/fin dynamics",
slice 16 the rotational half (pitch-plane θ,q), slice 17 the α→lift→γ TRANSLATION-COUPLING half (the real
path-changing `:airframe` toggle), slice 18 TERRAIN MASKING behind a third `:propagation` rung + the client's
FIRST true 3-D view (a user-directed insertion — the inner autopilot shifted to slice 19).** Full gate-by-gate
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

(The missile guidance arc — slices 8–12 — and its CAPSTONE slice 14 are COMPLETE; the countermeasures arc opened
with slice 13. HANDOFF §10 items 1–13 — the committed roadmap — are all DONE; slices 15–18 are into the §11 Tier-A
horizon — slice 15 the actuator/fin half, slice 16 the 6-DOF airframe's rotational half (pitch-plane θ,q), slice 17
the α→lift→γ TRANSLATION-COUPLING half (the real path-changing `:airframe` toggle), slice 18 terrain masking + the
3-D client view; what remains is slice 19 (the inner α/g autopilot + α-limited maneuverability, shifted from 18 by
the terrain insertion) then the rest of §11 Tier-A/B/C — most concretely land clutter [terrain banked the
heightfield] and the FULL 6-DOF airframe [bank-to-turn / 3-D].)

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
