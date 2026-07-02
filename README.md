# EWSim

**A teaching-through-play simulator for electronic warfare, air defense, GPS, and missile guidance.**

Hard physics where it's feasible on a laptop, and **explicit, switchable approximations**
where it isn't. Every subsystem carries a *fidelity* knob — flipping it and watching what
changes *is* the lesson. All devices are imaginary and generic (real systems approximated
only from public data, to the fidelity a video game would).

> Status: 9 vertical slices complete (radar → propagation → CFAR → jamming/EP → DF geolocation
> → multi-emitter deinterleaving → GPS/RAIM → ballistic missile → guided missile), 1731 tests
> green. See [the slice map](#whats-implemented) below.

---

## The mental model

A single **headless Julia server holds the truth** — physics, estimation, RNG, scenario
state. It steps a deterministic fixed-`dt` world and streams small JSON state frames over a
localhost TCP socket. Clients are thin and replaceable: **Godot** renders the spatial/analytic
sandbox (geometry, sliders, live readouts), **Pluto notebooks** render offline analytical
views (ROC curves, coverage diagrams). Heavy Monte-Carlo / DSP runs *inside the same server
process* and drops large artifacts to `shared/`. **Slices integrate inside the core, never
inside a client.**

```
                       ┌─────────────────────────────────────┐
                       │      Julia simulation server         │
                       │   (one persistent process = truth)   │
   localhost TCP  ◄────┤  • World state + fixed-dt tick loop   │
   (JSON frames)       │  • seeded RNG, deterministic replay   │
        ▲              │  • shared physics libs (rf, detection,│
        │              │    frames, estimation, geometry, …)   │
        │              │  • batch MC / DSP  ───────────────────┼──► shared/*.bin
        │              └─────────────────────────────────────┘
   ┌────┴───────┐         ┌─────────────────┐
   │  Godot 4   │         │ Pluto notebooks │
   │  spatial   │         │  analytical     │
   │  sandbox   │         │  plots          │
   └────────────┘         └─────────────────┘
```

The design commitments (core ≠ front-end, never simulate at carrier frequency, determinism on
CPU, named/switchable approximations) are pinned in **[HANDOFF.md](HANDOFF.md)** — the
ground-truth architecture doc. Working notes and per-slice status live in
**[CLAUDE.md](CLAUDE.md)**; staged plans in [`docs/plans/`](docs/plans).

---

## Quickstart (Windows)

Julia 1.11 is used portably and is **not on PATH** — everything goes through the wrappers in
`tools/`, so the interpreter path lives in exactly one place.

```powershell
# Run the full test suite (the contract enforcer — 1731 tests)
pwsh tools/test.ps1

# Start the simulation server on a showcase scenario (serves ONE client, then exits)
pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice1_roc.yaml

# Launch the Godot sandbox against a running server (main scene = Sandbox.tscn)
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe" --path clients/godot
```

Any other Julia command goes through `pwsh tools/julia.ps1 <args>`. The Julia **core** itself
is plain cross-platform Julia (`core/`); only the wrapper scripts are Windows-specific.

The Godot client is **adaptive**: it inspects the server's handshake and switches its view
(elevation / range-power / plan / ESM raster / GPS sky) to match the scenario — one scene
covers every slice. The shared fidelity button and sliders are built from the handshake, so
dragging a slider or cycling the fidelity knob round-trips through the core and back to the
readout.

---

## What's implemented

Each slice adds physics to the core and a live lesson you can toggle. Run a slice's server
(`tools/server.jl scenarios/<file>.yaml`) then attach Godot.

| Slice | Topic | Scenario | The lesson (toggle to see it) |
|------:|-------|----------|-------------------------------|
| 1 | Radar → detection → ROC | `slice1_roc.yaml` | SNR / Pd; drag RCS, watch detection probability rise |
| 2 | Propagation fidelity | `slice2_tworay.yaml` | `free_space` ↔ `two_ray`: multipath lobing + the 4/3-Earth horizon appear |
| 3 | CFAR + pulse integration | `slice3_cfar.yaml` | `fixed`/`ca`/`go`/`so`/`os`: adaptive threshold masks/unmasks a close target |
| 4 | Jamming / EP | `slice4_selfscreen.yaml`, `slice4_standoff.yaml` | burn-through; `freq_agility` / `sidelobe_blanking` cut the jammer's J/S |
| 5 | DF / geolocation | `slice5_geoloc.yaml` | GDOP error ellipse; `pseudolinear` ↔ `ml` fix walks back to truth |
| 6 | Multi-emitter EW | `slice6_deinterleave.yaml` | PRI difference histogram; `cdif` phantom PRI vs `sdif` rejecting it |
| 7 | GPS (trilateration) | `slice7_dop.yaml`, `slice7_raim.yaml` | DOP from geometry; RAIM detects/excludes a spoofed satellite |
| 8 | Missile (ballistic) | `slice8_ballistic.yaml` | Newtonian integrator; `rk4` ↔ `euler` energy drift; drag bleeds the arc |
| 9 | Missile (guided) | `slice9_pursuit.yaml` | PID autopilot under a pursuit law; `ideal` ↔ `pid` opens the tracking gap |

Each slice ships headless verifiers (`clients/godot/net/sliceN_verify.gd`) that drive the real
server and machine-check the lesson, plus UI tests that exercise the client without a server.

---

## Repository layout

```
core/           the engine — the truth
  src/          world.jl, subsystem.jl (tick contract), then physics libs:
                rf, detection, frames, geometry, estimation, gnss, dynamics,
                guidance, radar, deinterleave, esm, geolocation, gps, missile …
  test/         runtests.jl — the contract enforcer (new model ⇒ new test here)
clients/
  godot/        the spatial sandbox (thin client, ZERO physics)
  notebooks/    Pluto analytical views (thin client)
scenarios/      declarative YAML — the source of truth for runs, tests, sweeps
tools/          julia.ps1 / test.ps1 wrappers, server.jl, batch generators
docs/plans/     staged per-slice plans
docs/STATUS.md  as-built ledger — detailed per-slice completion notes
shared/         batch artifacts (mostly .gitignored — regenerated on demand)
HANDOFF.md      frozen architecture + contracts (read before changing architecture)
CLAUDE.md       working notes — how-to-run, invariants, short status, conventions
```

---

## Invariants (what keeps slices composable)

- **Physics lives in the core, never in a Godot script or a notebook cell.** If it can't run
  headless from `runtests.jl`, it's in the wrong place.
- **Determinism is on the CPU.** Same seed + same scenario ⇒ bit-identical trace (enforced by
  `test_determinism.jl`). Toggling fidelity mid-run must not desync a replay.
- **Units / frames / signs are the bug trifecta.** SI Float64 internally, inertial frame,
  quaternion body←inertial. Frame round-trips and LOS-rate signs are tested from day one.
- **Approximations are switchable and named.** No hidden approximations; never simulate at
  carrier frequency (work at baseband / link budget).

---

## License

See [LICENSE](LICENSE) and [NOTICE](NOTICE).
