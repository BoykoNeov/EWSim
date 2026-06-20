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

## Current status

Slice 1 (radar → detection → ROC). **Steps 1–2 done & green**: world, tick
contract, determinism test. Next: protocol + echo server + Godot `SimClient.gd`
(step 3 — de-risk the socket seam). See `docs/plans/slice1.md`.
