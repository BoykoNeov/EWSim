# Slice 1 — radar → detection → ROC

The architecture-proving slice: thin in physics, complete in architecture. It
exercises every seam (scenario load, tick contract, server, protocol, RNG/seed,
both client types, analytic-vs-MC validation) on the smallest possible physics.
Source of truth: `HANDOFF.md` §8 and §13.

**Done =** start the server on `slice1_roc.yaml`, connect Godot and watch blips,
move a slider and see `Pd` change live, hit "ROC" and get a converging two-curve
Pluto plot, and `runtests.jl` is green.

## Decisions taken
- Swerling **0 + 1** for slice 1 (2–4 deferred to the CFAR slice). — `HANDOFF.md` §13 open item.
- Wire JSON via **JSON3** (handoff §13). Manifest is committed (reproducible teaching repo).
- Julia invoked by full path through `tools/julia.ps1` — system PATH untouched.
- Godot 4.7 installed via winget (GDScript edition).

## Review gates (cadence: staged)
1. **Determinism green** — world + tick contract + `test_determinism.jl`.  ✅ DONE
2. **Physics green** — `rf.jl` + `detection.jl`, `test_radar_eq` + `test_detection` pass.
3. **ROC convergence** — `run_batch kind=roc` + Pluto plot shows analytic ≈ MC.

## Task checklist (handoff §13)
- [x] 1. Scaffold `core/` package; deps resolved; Manifest committed.
- [x] 2. `world.jl` + `subsystem.jl` (tick contract) + `test_determinism.jl` green.
- [ ] 3. `protocol.jl` (4-byte length + JSON) + **echo server** + ~30-line Godot
      `SimClient.gd` that connects and prints frames. **De-risks the seam first.**
- [ ] 4. `rf.jl` (free-space radar eq) + `detection.jl` (analytic + MC Pd);
      `test_radar_eq` (R⁴ scaling, hand-calc SNR) + `test_detection` (analytic Pd
      inside MC 99% CI) green.
- [ ] 5. `scenario.jl` + `slice1_roc.yaml` loader; wire radar/target subsystems
      into the live stream (`snr_db`, `pd`, `detected`, detection events).
- [ ] 6. `batch.jl` `run_batch kind=roc` → `shared/roc_radar1.bin`; Pluto notebook
      plots analytic vs MC convergence.
- [ ] 7. Minimal Godot `Sandbox.tscn`: radar + moving target + blips + 2 sliders.

## Context / landmarks
- Tick phases (fixed order, the unit of determinism): `integrate!` → `build_env!`
  → `observe!` → `decide!`. Seeded noise belongs in `observe!`/`integrate!`.
- `World.env` is a derived blackboard, cleared & rebuilt every tick — the only
  channel for cross-subsystem coupling.
- Time model: inner `dt_physics` fixed (1 ms); emit a frame every `emit_every`
  steps (~60 Hz). Slower subsystems gate themselves on `w.t`.
- Validation pattern to reuse everywhere: every model ships a test vs an analytic
  truth; the analytic-vs-MC convergence is simultaneously the first lesson and
  the first regression test.

## Watch-items (handoff §12)
- The Godot↔server socket + framing is the main integration risk — prove it in
  step 3, not late. Test partial reads / big-endian length parsing in GDScript.
- Julia TTFX: always via the long-lived warmed server; never a process per batch.
- Keep replay on CPU; GPU only for aggregate statistics, tagged by which path ran.
