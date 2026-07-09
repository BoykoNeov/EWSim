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

**Slices 1–13 COMPLETE & green — 2159 tests.** Full gate-by-gate
as-built detail (exact numbers, test names, watch-items, advisor-catches, per-slice run commands) lives in
**`docs/STATUS.md`**; pre-implementation plans in `docs/plans/sliceN.md`.

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

(The missile guidance arc — slices 8–12 — is COMPLETE. The countermeasures arc opens with slice 13.)

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
