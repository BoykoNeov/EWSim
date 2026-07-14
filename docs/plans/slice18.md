# Slice 18 — terrain masking + the 3-D client view (§11 Tier-A)

**The FIRST terrain in the project, and the client's FIRST true 3-D view.** Through slice 17 the world is
ground-plane-flat: `:two_ray` models a flat reflecting plane and a smooth 4/3-Earth horizon, but nothing in the
suite can put a HILL between a radar and a target. Slice 18 adds an authored heightfield to the core, a third
`:propagation` rung `:terrain` (free-space link budget + terrain line-of-sight occlusion), and — on the client —
the first Node3D view: the heightmap mesh, the radar/target markers, and the LOS ray flipping green→red as the
target drops into terrain shadow. **Terrain masking is core EW doctrine** (low-altitude penetration, radar siting,
pop-up attacks) — the lesson writes itself.

**ORDERING NOTE (user-directed 2026-07-14).** `slice17.md`/HANDOFF §11 named slice 18 as *"the inner α/g autopilot
+ α-limited maneuverability."* The user directed terrain + 3-D representation next; that autopilot slice shifts to
**slice 19** with its trigger intact (the slice-15 δ→`Cmδ·δ` hook and the `a_max_aero` lesson are unchanged — only
the number moves). HANDOFF/STATUS get the same edit at gate-3 close.

Source of truth: HANDOFF §11 Tier-A "higher fidelity behind existing knobs" (`propagation` is the named seam),
§12 "false precision" (a 3-D scene NEEDS the fidelity badge), §1 (client draws core output, zero physics),
conventions 4a/5/6/7/9/10/13/14.

## The scope

- **Terrain = an authored ANALYTIC heightfield**: a base plane `h0` plus a sum of Gaussian hills
  `h(x,y) = h0 + Σᵢ Aᵢ·exp(−((x−cxᵢ)² + (y−cyᵢ)²) / (2σᵢ²))`. Closed-form, smooth, ZERO RNG (nothing to
  desync — simpler even than class 4a needs), trivially YAML-authorable, and every test anchor is exact.
  Seeded fractal/ridge noise is DEFERRED (named below) — the masking lesson doesn't need it.
- **Occlusion = sampled-profile LOS**: walk the straight radar→target segment at a fixed step, blocked iff the
  terrain height reaches the ray height at any interior sample. Flat-earth WITHIN the terrain patch (the same
  approximation class as `:two_ray`'s flat multipath plane — named, §1). Diffraction/knife-edge is DEFERRED —
  `:terrain` is a hard shadow (binary mask), exactly like the existing horizon mask.
- **`:terrain` = free_space link budget + the LOS mask.** Deliberately NOT composed with two_ray lobing —
  convention 9 (one lesson per scenario): lobing nulls would muddy "the hill did it". Terrain+multipath (and
  clutter, which terrain later unlocks) are DEFERRED.
- **The 3-D view is DISPLAY-ONLY** (convention 13): the client renders the handshake height grid and the
  per-frame `visible` verdict; it never recomputes a height or an intersection.

## THE LESSON — terrain shadow: altitude buys detectability (and vice versa)

A ground radar on one flank, a ridge of authored hills mid-field, a target flying a LOW pass behind the ridge.
Under `:free_space` the radar tracks it wall-to-wall; flip the button to `:terrain` and detection CUTS OUT in the
terrain shadow — the LOS ray goes red, `visible:false`, the blip dies — then REACQUIRES as the target clears the
ridge. Drag the target-altitude knob UP and the shadow window SHRINKS to nothing (altitude buys detectability —
the defender's view); drag it DOWN and the target hides the whole pass (terrain masking — the penetrator's view).
The numeric readout is the signed **LOS clearance** `min over the ray of (ray_z − terrain_h)`: positive = clear
by that many metres, negative = buried. One number, sign IS the verdict.

## Fidelity class — 4a (draw-invariant RNG rung), introduce-safe

`detect_once` draws UNCONDITIONALLY (convention 3); `:terrain` gates only the `(snr, visible)` pair —
`(0.0, false)` when occluded, exactly the below-horizon policy `:two_ray` already ships. So the rung is
class **4a**: RNG in lockstep across all three rungs, live-settable, NO `set_fidelity` guard, byte-identical
replay across a held-seed toggle (the slice-2 shape — the verifier pins it).

**The no-terrain-entity clamp (convention 5).** `set_fidelity propagation terrain` is now reachable LIVE on ANY
scenario, including slice 1 with no terrain entity. A throw inside `observe!` kills the session — so the consumer
clamps: **no terrain entity ⇒ `:terrain` behaves as bit-exact `:free_space`** (the slice-4 mismatched-EP no-op
precedent; tested with `==`, not "calibrated to pass").

## Gate 1 — `core/src/terrain.jl` (pure lib) + tests

Pure, dependency-free, no `w.rng`, no LinearAlgebra (the §9 house style). Included **before `radar.jl`**
(convention 1) so `PROPAGATION_MODES`' consumers can reference its constants if needed.

- `TerrainParams` — `h0`, hills as parallel vectors `(a, cx, cy, sigma)`, LOS sample step `los_step_m`.
- `terrain_height(t, x, y) -> Float64` — the closed form above.
- `terrain_clearance(t, p1, p2) -> Float64` — signed min of `(ray_z − h)` over interior samples of the straight
  segment (endpoints EXCLUDED — a mast sitting on the ground must not self-block; step from `los_step_m`,
  clamped ≥ 1 sample). Finite by construction (no Inf/NaN — convention 6).
- `terrain_los_clear(t, p1, p2) -> Bool` — `terrain_clearance(...) > 0`.
- `terrain_grid(t, xmin, xmax, ymin, ymax, n) -> Vector{Float64}` — the row-major n×n wire sample (handshake).

Test teeth (convention 11 — explicit atol, external anchors, no self-calibration):
- **Exact heights**: hill peak = `h0 + A` at the center; at `r = σ` the falloff is exactly `A·e^(−1/2)`;
  two-hill superposition = sum (closed form vs closed form is legal here because the IMPLEMENTATION path is the
  grid/clearance code, not a re-typed formula — pin a hand-computed literal, not a call-the-same-function).
- **Flat-terrain clearance is exact**: no hills, `h0 = 0`, endpoints at `z₁, z₂` ⇒ clearance `== min(z₁, z₂)`
  up to the sample step (atol pinned to the step geometry).
- **Single mid-hill blocking is monotone + sign-exact**: hill height `A` under a level ray at `z`: blocked iff
  `A > z` (scan A across the threshold; clearance crosses 0 within one step's tolerance).
- **Symmetry**: `clear(p1,p2) == clear(p2,p1)` (bit-exact — the sampler must walk the same set).
- **Grid pinning**: `terrain_grid` cell (i,j) `==` `terrain_height` at that cell's coordinates (a transpose /
  row-major slip is THE classic bug here — pin an ASYMMETRIC terrain).

## Gate 2 — the `:terrain` rung + handshake + loader

- `PROPAGATION_MODES = (:free_space, :two_ray, :terrain)` — the ONE list (convention 7); `LIVE_FIDELITY_MODES`
  and `set_fidelity` pick it up with ZERO further edits.
- `_target_snr` gains the `:terrain` elseif: look up the terrain entity (`kind === :terrain`, ≤1 enforced at
  load), no entity ⇒ free-space verbatim (the clamp above); else `terrain_los_clear(radar_pos, tgt_pos)` ⇒
  clear: `(snr_freespace, true)`; occluded: `(0.0, false)`. Prior rungs TEXTUALLY UNCHANGED.
- Telemetry (phase 3, the radar's `observe!`): `<id>.terrain_clearance_m` (`_finite`-clamped), shipped ONLY
  under the `:terrain` rung with a terrain entity present (the slice-17 lift-keys precedent — key-presence
  gated on the RUNG, so a non-terrain wire is byte-identical).
- Terrain entity: `kind: terrain`, comps `h0`, `hill1_a/hill1_x/hill1_y/hill1_s`, `hill2_*`, … (flat scalar
  keys so the knob machinery applies unchanged), `xmin/xmax/ymin/ymax`, `grid_n`, `los_step_m`. Non-physical
  (no hooks — the `:datalink` precedent): terrain never ticks; it is read by the radar's `observe!` and the
  handshake.
- Load-time validation (convention 5): `σᵢ > 0`, `grid_n ≥ 2`, `xmax > xmin`, `ymax > ymin`, `los_step_m > 0`,
  at most ONE terrain entity, hills keys complete per index (a `hill2_a` without `hill2_s` is an authoring
  error at LOAD, not a tick throw).
- **Terrain is LOAD-STATIC** — hills are NOT live knobs this slice. The handshake grid ships once (the
  `range_axis_m` handshake-once contract); a live hill slider would silently stale the client mesh. The live
  lever is the TARGET-ALTITUDE knob + the fidelity button. Hill-knob-with-grid-refresh is DEFERRED (named).
- `_terrain_info(w)` (the `_cfar_axis_info` shape): `nothing` without a terrain entity; else ships
  `terrain` (id), `terrain_n`, `terrain_extent_m = [xmin, xmax, ymin, ymax]`, `terrain_grid` (row-major
  n² heights), `radar` + `target` ids. **`terrain_grid` presence is the client's 3-D-view discriminator.**
- Tests: draw-lockstep across all three rungs (the slice-2 propagation test pattern — same draw count, same
  stream position); the no-terrain-entity `==` no-op; occluded ⇒ `visible == false` && snr floored on the wire
  (`_SNR_DB_FLOOR`); handshake block pinned against the gate-1 grid; loader rejections (each bad input).
- Byte-identity: slices 1–17 untouched (new elseif + new include + additive handshake merge); `test_determinism`
  + the `_sample_z` absolute golden stay green; any existing PROPAGATION_MODES pin updated to the 3-tuple.

## Gate 3 — scenario + the Node3D view + four proofs (convention 14)

- `scenarios/slice18_terrain.yaml` (seed 18): ground radar (mast height ~30 m) at one flank; a 2–3-hill ridge
  mid-field (asymmetric — the grid-transpose canary); target on a low straight pass behind the ridge,
  altitude a DECLARED KNOB; `fidelity: propagation: terrain` (the ONE toggled fidelity — convention 9).
  Numbers tuned by probe FIRST, then pinned against the live emit-grid wire (convention 10): the masked window
  (N consecutive `visible:false` frames) exists at the low default, vanishes above a pinned altitude.
- **The 3-D view** (in the adaptive `Sandbox.gd`, discriminated on `terrain_grid`): a runtime-built
  `SubViewportContainer`/`SubViewport`/`Node3D` — an `ArrayMesh` heightmap from the handshake grid
  (height-tinted vertices; sim x→Godot x, sim y→Godot −z, z→y), a radar mast marker, the target marker +
  fading trail, the LOS segment colored by `<radar>.visible` (green/red), the clearance + fidelity badge HUD
  (§12: "this is a :terrain approximation"). Orbit/zoom camera on mouse drag/wheel. The existing knob sliders +
  fidelity button carry over UNCHANGED (the button cycles the 3 propagation rungs).
  **Watch-item**: `_setup_spatial_fid_btn`'s airframe branch is checked FIRST (the slice-16→17 value-guard) —
  the terrain view must branch BEFORE the spatial fallback but must NOT touch the airframe path.
- Four proofs: `slice18_verify.gd` (masked window exists under `:terrain` & absent under `:free_space` on the
  SAME held seed; detections zero inside the window; clearance sign flips with the altitude knob via
  `set_param`; held-seed replay across the rung toggle BIT-IDENTICAL — the 4a claim as a test);
  `slice18_ui_test.gd` (mock handshake with `terrain_grid` → 3-D view branch, button cycles
  free_space→two_ray→terrain and wraps, altitude slider → `set_param`); the headless `Sandbox.tscn` smoke-load;
  the windowed shot (the ridge mesh + the red LOS ray in shadow + the badge).

## Deferred (NAMED)

- Seeded fractal/ridge terrain (own `Xoshiro`, built once at LOAD — the batch-stream discipline, never `w.rng`).
- Knife-edge diffraction (a graded shadow behind the crest — the natural fidelity rung ABOVE `:terrain`).
- Terrain-composed multipath (`two_ray` off a sloped facet) and terrain-driven land CLUTTER (the §11 Tier-A
  clutter entry — terrain is its prerequisite and this slice banks the heightfield it needs).
- Hill knobs with a handshake-refresh (grid re-ship on `set_param`).
- Terrain occlusion for the DF/ESM sensors and the SEEKER (the same `terrain_los_clear` call at their LOS
  sites — mechanical once this slice lands the lib).
- **Slice 19 = the inner α/g autopilot** (the shifted slice-18-as-was — trigger intact from slice15/16/17 plans).
