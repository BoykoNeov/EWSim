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
1b. **Seam proven** — Godot↔Julia socket round-trip, big-endian framing.  ✅ DONE
2. **Physics green** — `rf.jl` + `detection.jl`, `test_radar_eq` + `test_detection` pass.  ✅ DONE
3. **ROC convergence** — `run_batch kind=roc` + Pluto plot shows analytic ≈ MC.  ✅ DONE
   **Numbers**: `test_batch.jl` puts MC in the analytic Pd's Wilson 4σ band; real
   `shared/roc_radar1.bin` is `[3,64,2]` with max |analytic−MC| = 0.0034 (Swerling 1,
   100k trials). **Plot**: `clients/notebooks/slice1_roc.jl` opened in Pluto — the
   analytic lines and MC scatter overlap, convergence confirmed.

## Task checklist (handoff §13)
- [x] 1. Scaffold `core/` package; deps resolved; Manifest committed.
- [x] 2. `world.jl` + `subsystem.jl` (tick contract) + `test_determinism.jl` green.
- [x] 3. `protocol.jl` (4-byte big-endian length + JSON) + `tools/echo_server.jl`
      + headless Godot `net/seam_test.gd`. Round-trip verified, exit 0. Tests:
      `test_protocol.jl` (byte-exact header, multi-frame, real-TCP loopback).
      Reusable `SimClient.gd` Node deferred to step 7 (Sandbox scene).
- [x] 4. `rf.jl` (free-space radar eq) + `detection.jl` (analytic + MC Pd);
      `test_radar_eq` (R⁴ scaling, hand-calc SNR) + `test_detection` (analytic Pd
      within MC sampling-error band) green. SNR convention: noise normalised to 1,
      so the radar eq's `Pr/N` is the linear SNR detection consumes directly.
      Marcum-Q via Poisson-mixture (no SpecialFunctions dep). Swerling 0 + 1 only.
- [x] 5. `scenario.jl` (`load_scenario` → `Scenario`) + `scenarios/slice1_roc.yaml`;
      concrete subsystems in `radar.jl` (`ConstantVelocity`, `RadarSensor`). Live
      `snr_db`/`pd` per tick into `w.env[:telemetry]`; detection draw + `:detection`
      event gated to `revisit_s`, last verdict persisted in radar `comp`; shared
      `detect_once` single-look sampler. `test_scenario.jl` green (loader + telemetry-
      vs-closed-form + static-geometry Bernoulli + byte-identical replay). **Scope
      decision:** the socket run loop (`server.jl`: run modes, command handling,
      `warmup!`, event-clearing post-emit) is *not* in step 5 — it lands just before
      step 7's Godot scene. Until then the caller owns `empty!(w.events)` between emits.
- [x] 6. `batch.jl` `run_batch kind=roc` → `shared/roc_radar1.bin` (+ `.meta.json`
      sidecar, the headless twin of the §5 socket descriptor) and `load_roc` reader;
      Pluto `clients/notebooks/slice1_roc.jl` plots analytic vs MC convergence;
      `tools/run_batch.jl` headless generator. `test_batch.jl` green: analytic plane ==
      independent closed-form recompute (no transpose), MC plane in the analytic Pd's
      Wilson 4σ band (convergence-as-regression), descriptor↔file shape/size agree, and
      a batch leaves `w.rng` untouched (own seeded stream — a sweep never desyncs the
      live trace). The batch is the *distribution* path (HANDOFF §1/§12): no byte-identity
      assert, and the cell loop is the seam where Threads/GPU drop in later. The Pluto
      notebook was opened and renders: analytic lines + MC scatter overlap (its data path
      reuses the tested `load_roc`, so only the `plot(...)` itself was unproven headlessly).
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
