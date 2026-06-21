# Slice 2 — propagation fidelity (`two_ray`)

A **pure extension** slice: no new architecture, no contract rewrites. It adds
the second rung of the `propagation` fidelity ladder behind the knob slice 1
already stubbed, and makes "dial the knob, watch the physics change" the lesson.
Source of truth: `HANDOFF.md` §10 (item 2), §1 (named approximations), §12.

The seam is already there: `radar.jl` errors today on any `:propagation` but
`:free_space` (the stub), and the server's `scenario` handshake already ships
`world.fidelity` to clients (the §12 badge). Slice 2 fills the stub.

**Done =** start the server on the two-ray scenario, connect Godot, toggle
`propagation` free_space↔two_ray live and watch the coverage change — Pd
oscillates as the target sweeps the interference lobes, and a target beyond the
4/3-Earth horizon goes dark — with `runtests.jl` green on the new closed-form
propagation tests (and slice-1 tests untouched).

## The physics (named approximations — HANDOFF §1)

Flat-earth two-ray multipath + curved-earth (4/3) horizon — the conventional
engineering hybrid, both behind the one `propagation` knob.

- **Pattern-propagation factor** (perfect reflection, ρ = −1, horizontal pol at
  grazing): one-way power `F² = 4·sin²(Δφ/2)`, phase difference
  `Δφ = 4π·h_r·h_t / (λ·R_g)` (`h_*` = antenna heights above the reflecting
  plane, `R_g` = ground range). Monostatic (two-way): `SNR_two_ray = SNR_fs · F⁴`.
- **4/3-Earth radar horizon:** `d_horizon ≈ √(2·k·R_e)·(√h_r + √h_t)` with
  `k = 4/3`, `R_e = 6.371e6 m` → `≈ 4122·(√h_r + √h_t)` m. Beyond it the target
  is masked (no LOS).
- `free_space` = no ground at all (infinite LOS, no multipath); `two_ray` = ground
  present → both lobing **and** horizon masking. Dialing between them *is* the lesson.

## Decisions taken
- **Horizon bundles into `two_ray`** (not a separate knob). HANDOFF §10 item 2
  lists "two_ray (multipath lobing…), 4/3-Earth radar horizon" as one item toggled
  by one knob. free_space ignores the ground entirely; two_ray introduces it.
- **ρ = −1 perfect reflection** is the slice-2 default (textbook flat-earth
  result). Reflection coefficient stays a constant for now — a future sub-knob,
  not slice 2.
- **Live fidelity toggle = a new `set_fidelity` command**
  (`{"type":"set_fidelity","key":"propagation","value":"two_ray"}` → writes
  `w.fidelity`). One `if/elseif` branch in `handle_command!`; mirrors the
  `scenario_frame` extension precedent. **Flagged honestly:** §11 Tier A says
  "protocol doesn't change for new fidelity knobs" — that holds for YAML+reload;
  *live* toggling needs this one command. A deliberate, flagged extension (like
  `scenario_frame`), not an accident. Determinism is unaffected — it's a live
  mutation exactly like `set_param`, covered by the fixed-command-sequence replay
  property.
- **Detection unchanged (Swerling 0 + 1).** two_ray only changes the SNR fed to
  `detection.jl`; the detector, the ROC path, and `test_detection`/`test_batch`
  don't move.
- **Pluto coverage diagram = stretch goal, not the core proof.** The lobing
  already shows live in the existing Godot elevation view (screen-x downrange,
  screen-y altitude) as the target sweeps lobes — slice 1 *needed* Pluto only
  because ROC (analytic-vs-MC) is intrinsically a plot. If built, its regression
  test is a **closed-form recompute** (deterministic), not an MC convergence band.

## Review gates (cadence: staged)
1. **Propagation physics green** — `snr_two_ray` + horizon helper + `test_propagation.jl`
   (lobe peak = +12.04 dB, null → 0, low-grazing doubling = −24.08 dB R⁸,
   ρ=0 recovers free-space exactly, below-horizon masked). Slice-1 physics tests
   stay green untouched.
2. **Knob switches live** — `radar.jl` dispatches on `:propagation`; `set_fidelity`
   command lands; integration test shows two_ray ≠ free_space SNR for the same
   geometry, below-horizon masking, **and the default stays free_space**. No
   Inf/NaN reaches the wire.
3. **Visible live** — Godot fidelity toggle (free_space/two_ray) + badge update +
   lobing/horizon visibly changing. **(stretch)** Pluto coverage diagram (SNR/Pd
   over a range×altitude grid) showing the lobe structure.

## Task checklist
- [x] 1. `rf.jl`: propagation-factor helper (`Δφ`, `F⁴`), `snr_two_ray(rp, rcs,
      slant_m; h_r, h_t, ground_m, refl=-1.0)`, `horizon_range(h_r, h_t)` (4/3-Earth).
      Name every approximation in the docstrings (flat-earth small-grazing phase,
      ρ=−1, 4/3-Earth). `test_propagation.jl` green (the 5 closed-form checks);
      added to `runtests.jl`. **DONE** — `two_ray_phase`/`two_ray_factor4`/`snr_two_ray`/
      `snr_db_two_ray`/`horizon_range` in `rf.jl` (rf.jl stays pure: NO horizon gating —
      that's step-2 radar.jl policy; radar.jl calls `snr_two_ray` and must NOT re-apply F⁴).
      20 closed-form tests green (247 total): lobe peak ratio=16 (+12.04 dB), null→0
      (explicit `atol`), small-grazing R⁻⁸ (−24.08 dB/octave), ρ=0 ≡ free-space exactly,
      h→0 perpetual-null pin (not a throw — a fly-by may cross z=0), 4/3-Earth horizon
      (coeff recomputed at full precision ≈4121.8, additive in √h), `ground_m>0` guard.
- [x] 2. `radar.jl`: replace the `:free_space`-only guard with a dispatch on
      `get(w.fidelity, :propagation, :free_space)`; extract `h_r`/`h_t` (`pos[3]`)
      and ground range; apply the horizon gate (below horizon → finite SNR floor
      **or** a `visible:false` telemetry flag — **never** `-Inf`/`NaN`). Add
      `set_fidelity` to `handle_command!` (`server.jl`); the `scenario` handshake
      already ships `world.fidelity`. Tests: knob switches model, horizon masks,
      default unchanged, no Inf/NaN on the wire. **DONE** (272 tests) — `_target_snr`
      in `radar.jl` dispatches on `PROPAGATION_MODES` (the single source of truth shared
      with the server validation); two_ray decomposes slant (link budget) vs ground
      (phase + 4/3-Earth horizon), masks below-horizon to SNR 0 with `visible:false`,
      clamps heights ≥0 and guards ground→0 (overhead → free space). `_snr_db_wire`
      floors the telemetry `snr_db` to `_SNR_DB_FLOOR=-120` so a **null** (F⁴=0, even
      above the horizon) / mask never ships `-Inf`. **`detect_once` stays UNCONDITIONAL
      per look** (same randn count under either rung → RNG lockstep across fidelities;
      gating it would desync replay). `set_fidelity` (`server.jl`) validates BEFORE
      writing `w.fidelity` (a bad value would otherwise throw inside `tick!`, which the
      session's IO/EOF-only catch turns into a dropped connection). New `test_radar.jl`
      (6 contracts: default==free_space, two_ray==closed-form on a slant≠ground geom,
      below-horizon mask, null JSON round-trip, **draw-stream parity across fidelities**,
      unknown-rung error). `test_determinism.jl` gains a **mid-run toggle replays
      bit-identical** case; `test_server.jl` gains the `set_fidelity` write/reject test.
- [x] 3. `scenarios/slice2_tworay.yaml`: geometry that sweeps several lobes and
      crosses the horizon (e.g. a climbing or descending fly-by) — note the
      existing `slice1_roc.yaml` already lobes under two_ray, so this is for a
      *striking* lesson, not correctness. Godot: a fidelity toggle button sending
      `set_fidelity`, the §12 badge re-rendering, lobing visible as Pd oscillates,
      target going dark past the horizon. Headless verifier asserts the toggle
      loop (free_space→two_ray flips the telemetry SNR for the same `t`).
      **DONE** (279 tests) — `slice2_tworay.yaml`: a 100 m-altitude target closing at
      450 m/s from 70 km on a 30 m mast radar (50 kW). The 4/3-Earth horizon is 63.8 km, so
      the target starts BELOW it (dark, `visible:false`) for ~14 s, then crosses into LOS and
      sweeps a dramatic string of lobes/nulls (Pd 0↔~1; F⁴ from −62 dB deep nulls to +12 dB
      peaks) as Δφ sweeps. `propagation` is NOT a knob (it's a fidelity, toggled by the
      button) — knobs stay pt_w (bracketed 1k–200k around the 50 kW default) + rcs. Godot
      `Sandbox.gd`: a `prop:` toggle button sends `set_fidelity`; the §12 badge + button
      re-render from a **local** fidelity copy (the server applies set_fidelity / reset
      silently — no new handshake — so the client owns the displayed state and resyncs to
      the scenario default on reset); the target renders dark "(below horizon)" off the
      `<id>.visible` flag, NOT absence of `:detection` events (the watch-item — a masked
      target still false-alarms at pfa). `net/slice2_verify.gd` (headless, the
      `sandbox_verify.gd` analog) drives the real server: handshake fidelity is two_ray; the
      far target is `visible:false` under two_ray but `visible:true` under free_space (the
      mask is the model, not the geometry); step to T=28.0 s under two_ray, then **reset
      (→YAML two_ray) BEFORE set_fidelity free_space** (reset would clobber the toggle),
      replay to the SAME T — `t` bit-identical, SNR flips 15.10→7.70 dB (**Δ=7.40 dB**, drain
      to the LAST frame of the step burst, `_inbox.clear()` before the replay). Proven green
      end-to-end (`S2V OK`, exit 0) + `Sandbox.tscn` smoke-loaded headless (no GDScript
      errors, server `DONE`). The verifier drives SimClient directly, so the toggle BUTTON
      path (`_on_prop_pressed`, the badge/button re-render, the reset resync) is covered by a
      separate headless UI test `net/sandbox_ui_test.gd` (`SUI OK` — builds the toggle-path
      nodes + a mock client, feeds a fake handshake, asserts the badge flips two_ray→free_space,
      the `set_fidelity` frame is sent, and reset resyncs to the default). `_draw`'s
      below-horizon pixel branch isn't run headless (needs a windowed look like slice-1's), but
      the `visible` flag it keys off is wire-verified by `slice2_verify.gd`. `test_scenario.jl` gains a loader assertion (parses, two_ray
      default, no `propagation` knob, target starts beyond `horizon_range`) so a malformed
      YAML fails as a clear test, not a confusing Godot-launch timeout.
      **(stretch — DONE, 420 tests)** `batch.jl` `kind=:coverage`: pure `coverage_grid`
      sweeps SNR (floored dB) over a ground-range × altitude grid two ways — free_space and
      two_ray (with the 4/3-Earth horizon mask) — as an `(n_range, n_alt, 2)` array;
      `load_coverage` reader + `_resolve_target_rcs` (rcs defaults to the sole target).
      Additive `elseif kind === :coverage` branch (`_run_coverage` helper) so the ROC path
      stays byte-for-byte the slice-1 code. dB-floored via the SAME `_snr_db_wire` as the wire
      (a null/mask reads `_SNR_DB_FLOOR`, never `-Inf` — the watch-item carried into the
      artifact). No RNG at all (closed form), so a coverage run can't desync a live trace.
      `tools/run_coverage.jl` (headless twin of `run_batch.jl`) → `shared/coverage_radar1.bin`
      (NOT committed — 3 MB sweep, `.gitignore` stages only the tiny ROC; the notebook says
      generate-first). `clients/notebooks/slice2_coverage.jl`: free_space vs two_ray SNR-dB
      heatmaps + the analytic horizon curve overlay (coeff recovered from the exported
      `horizon_range(0,1)` — no internal constants) + an F⁴ = two_ray−free_space difference
      panel. **Test = the live `_target_snr` as oracle** (NOT a hand recompute, which would
      replicate any slant/ground decomposition slip): the all-cells loop proves both planes
      match the sandbox path AND catches a transpose in one shot; plus descriptor↔file agree,
      artifact Inf/NaN-free, below-horizon corner floors while free_space stays finite (mask
      is the model not the geometry), grid non-degenerate, `w.rng` untouched, rcs override +
      ambiguous-multi-target error. **The test grid MUST include a `0 < h_t < ~162 m` row**
      (the 100 m row, masked beyond ~63.8 km): at `h_t=0` the perpetual two-ray null floors a
      cell *regardless* of the horizon mask, so an all-high-altitude grid would pass even with
      the mask deleted — a masked-but-NOT-null cell is what actually guards the policy (proven
      by disabling the mask → exactly 3 assertions fail; advisor catch).
      **Grid default = 10–80 km × 0–600 m** (400×480): a 30 m X-band mast packs ~940 lobes
      over the hemisphere, so short-range/high-altitude aliases into moiré — this low-elevation
      window keeps ~2–4 cells/lobe and centres the scenario's 100 m target in the lobing band.
      Visually confirmed (2026-06-21, headless PNG render of the notebook cells): clean lobe
      fan, dark nulls, cyan horizon curve bounding the masked wedge (no headless *visual* test,
      same gap as slice-1 `_draw` — the numbers are pinned, the picture is eyeballed).

## Context / landmarks
- **The seam is pre-built.** `radar.jl:73-74` is the guard to replace;
  `scenario_frame` (`server.jl:90`) already ships `world.fidelity` (the badge).
  `handle_command!` (`server.jl:134`) is a clean `if/elseif` chain — `set_fidelity`
  is one branch.
- **Frame convention:** `pos = [downrange/x, y, altitude/z]`. Height above the
  reflecting plane = `pos[3]`; ground range = horizontal distance; slant range =
  full 3-D distance (what `snr_freespace` already uses).
- **two_ray only changes the SNR fed to detection** — `detection.jl` and the ROC
  path are untouched. The whole slice is `rf.jl` + a dispatch in `radar.jl` + one
  wire command + clients.
- **Validation shape differs from slice 1:** two_ray is deterministic, so its
  tests are closed-form (lobe peak / null / R⁸ envelope), not analytic-vs-MC bands.

## Watch-items (gotchas to bake in)
- **`-Inf` on the wire.** Below-horizon → SNR=0 → `lin2db(0) = -Inf` → invalid
  JSON (same failure class as the slice-1 `%g` bug). Gate to a finite SNR floor or
  carry a `visible:false` flag; never let Inf/NaN hit JSON3. Test this explicitly.
- **`h→0` degeneracy.** two_ray collapses (`F→0` at all ranges) when either
  antenna sits on the reflecting plane. Slice-1 geometry (radar z=10) is fine;
  guard/note `h_r,h_t > 0` and pin the behavior with a test.
- **Default must stay `free_space`.** `get(w.fidelity,:propagation,:free_space)`
  already does this — confirm `test_radar_eq`/`test_scenario` stay green untouched.
- **Name every approximation** in the docstrings (flat-earth small-grazing phase,
  ρ=−1, 4/3-Earth). HANDOFF §1: no hidden approximations — this is the slice whose
  whole point is the named knob.
- **Step 3 Godot: "target dark past horizon" keys off the `visible` telemetry flag,
  NOT absence of `:detection` events.** A masked (below-horizon, SNR=0) target still
  false-alarms at rate `pfa`, so it can occasionally blip a detection even below the
  horizon — "no recent blip" ≠ "not visible". Step 2 added `"<id>.visible"` for exactly
  this; the client must read it.
