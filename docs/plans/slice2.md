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
- [ ] 1. `rf.jl`: propagation-factor helper (`Δφ`, `F⁴`), `snr_two_ray(rp, rcs,
      slant_m; h_r, h_t, ground_m, refl=-1.0)`, `horizon_range(h_r, h_t)` (4/3-Earth).
      Name every approximation in the docstrings (flat-earth small-grazing phase,
      ρ=−1, 4/3-Earth). `test_propagation.jl` green (the 5 closed-form checks);
      added to `runtests.jl`.
- [ ] 2. `radar.jl`: replace the `:free_space`-only guard with a dispatch on
      `get(w.fidelity, :propagation, :free_space)`; extract `h_r`/`h_t` (`pos[3]`)
      and ground range; apply the horizon gate (below horizon → finite SNR floor
      **or** a `visible:false` telemetry flag — **never** `-Inf`/`NaN`). Add
      `set_fidelity` to `handle_command!` (`server.jl`); the `scenario` handshake
      already ships `world.fidelity`. Tests: knob switches model, horizon masks,
      default unchanged, no Inf/NaN on the wire.
- [ ] 3. `scenarios/slice2_tworay.yaml`: geometry that sweeps several lobes and
      crosses the horizon (e.g. a climbing or descending fly-by) — note the
      existing `slice1_roc.yaml` already lobes under two_ray, so this is for a
      *striking* lesson, not correctness. Godot: a fidelity toggle button sending
      `set_fidelity`, the §12 badge re-rendering, lobing visible as Pd oscillates,
      target going dark past the horizon. Headless verifier asserts the toggle
      loop (free_space→two_ray flips the telemetry SNR for the same `t`).
      **(stretch)** `batch.jl` coverage-diagram kind (SNR over range×altitude grid)
      → `shared/*.bin` + Pluto `slice2_coverage.jl`; closed-form regression test.

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
