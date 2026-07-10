# EWSim — Engineering Handoff

A teaching-through-play simulator for electronic warfare / air defense, GPS, and
missile guidance. Hard physics where feasible, **explicit, switchable approximations**
where not. **Imaginary, generic devices** — real systems may be approximated from
public data only, to the fidelity a video game would.

This document pins down the architecture, the contracts that let independent slices
combine, and the first vertical slice. It is meant to be read by Claude Code as the
ground truth before any code is generated. Status: **design frozen, no code yet.**

---

## 0. The one-paragraph mental model

A single **headless Julia simulation server** holds the truth — physics, estimation,
RNG, scenario state. It steps a deterministic fixed-`dt` world and streams small state
frames over a localhost socket. **Godot is a thin client** for the spatial sandbox
(geometry, sliders, blips). **Pluto notebooks are thin clients** for the analytical
views (ROC curves, range-Doppler, GDOP ellipses). Heavy offline work (Monte Carlo,
big DSP) runs *inside the same server process* on extra threads / GPU and drops large
artifacts to a shared file. **Slices integrate inside the core, not inside Godot.**
The core gets richer as slices land; every client stays replaceable.

```
                       ┌─────────────────────────────────────┐
                       │     Julia simulation server          │
                       │  (one persistent process = "truth")  │
                       │                                      │
   localhost TCP  ◄────┤  • World state + fixed-dt tick loop   │
   (JSON frames)       │  • seeded RNG, deterministic replay   │
        ▲              │  • shared physics libs (rf, detection,│
        │              │    frames, estimation, geometry)      │
        │              │  • batch MC / DSP on threads + GPU ───┼──► shared/*.bin
        │              └─────────────────────────────────────┘        (big artifacts)
        │                          ▲
   ┌────┴───────┐         ┌────────┴────────┐
   │ Godot 4    │         │ Pluto notebooks │
   │ spatial    │         │ analytical      │
   │ sandbox    │         │ plots           │
   └────────────┘         └─────────────────┘
```

---

## 1. Design commitments (non-negotiable)

These are the decisions everything else depends on. Do not relitigate them inside a slice.

- **Core ≠ front-end.** Physics never lives in Godot scripts or in a notebook cell.
  It lives in the Julia core and is reachable headless. If you can't run it from
  `runtests.jl` with no GUI, it's in the wrong place.
- **Never simulate at carrier frequency.** Work at complex baseband / link-budget /
  correlator level. GPS models C/N₀ and correlator outputs, not 1.5 GHz samples.
  This is the approximation that makes RF feasible on a laptop. A sample-level "lab"
  is a separate, opt-in fidelity mode, not the default.
- **Phenomenological first, sample-level only where the DSP *is* the lesson.** Track
  SNR / J·S / Pd / positions / LOS-rate for breadth; synthesize I/Q only in the radar
  and GPS labs where seeing the signal is the point.
- **Determinism on CPU; GPU for bulk statistics only.** Seeded replay must be
  bit-identical, so "truth" runs stay on deterministic CPU paths. GPU is for
  embarrassingly-parallel Monte Carlo where the *distribution* matters, not bit-equality
  (parallel reductions aren't reproducible). Be deliberate about which path a result took.
- **Approximations are first-class and switchable.** Every subsystem carries a
  `fidelity` knob (e.g. `free_space | two_ray`, `analytic | monte_carlo`,
  `point_mass | 6dof`). Dialing fidelity and watching what changes *is* the pedagogy.
  No hidden approximations.
- **Validate against closed form, as automated tests.** Every model ships with a test
  that checks it against an analytic truth (energy conservation, analytic-vs-MC Pd,
  zero miss for PN vs non-maneuvering target). These tests double as lessons.
- **Units, frames, signs.** Nearly every bug in this domain is one of these three.
  Canonical units policy + tested frame transforms from day one. LOS-rate sign errors
  are the #1 "my missile flies away" bug — expect them.

---

## 2. Technology choices

| Concern | Choice | Notes |
|---|---|---|
| Core language | **Julia** | Heavy numerics central; `DifferentialEquations.jl` is the best ODE stack for the missile side. |
| Small vectors | `StaticArrays` (`SVector{3}`) | Allocation-free 3-vectors/quaternions; big perf win in the tick loop. |
| ODE / integration | `OrdinaryDiffEq` (subset of `DifferentialEquations`) | For guidance/airframe; fixed-step custom RK is fine for slice 1. |
| Units | `Unitful` at boundaries; strip to SI internally | Validate at ingest, compute in raw SI Float64 in hot loops. |
| RNG | stdlib `Random.Xoshiro`, or `StableRNGs` | One owned, seeded stream in `World`. Cross-version stability matters for teaching. |
| Wire format | **length-prefixed JSON** (see §6) | Reversal of earlier msgpack default — see note below. |
| Transport | stdlib `Sockets` (TCP, localhost) | Sub-ms latency; fine for 60 Hz. |
| Big artifacts | stdlib `Mmap` / flat `.bin` in `shared/` | Godot reads `PackedByteArray`; notebooks `mmap`. |
| Analytical client | **Pluto.jl** | Reactive notebooks are ideal for "tweak a knob, watch the curve." |
| Batch parallel | stdlib `Threads`, then `CUDA.jl` for MC | GPU only on non-replay statistics. |
| Tests | stdlib `Test` | `runtests.jl` is the contract enforcer. |
| Spatial client | **Godot 4** (GDScript) | Pure client. No native Julia binding — and we never need one (IPC only). |

**Why JSON over msgpack (changed my earlier advice):** for a teaching tool the wire is
tiny (a few KB/frame even with hundreds of entities), and being able to *read the wire*
while debugging the protocol is worth more than compactness. Both Julia and Godot parse
JSON natively with zero dependencies. Switch to msgpack only if profiling ever shows the
serialize/parse step matters — it won't at these payload sizes.

**Julia "time to first call":** pay it once. The server pre-warms by running a throwaway
tick + a tiny batch before accepting connections (`warmup!` in §5). Never spawn a Julia
process per Monte Carlo batch — run batches inside the long-lived server.

---

## 3. The tick contract (the heart of the whole thing)

Every subsystem is a thing that participates in a **fixed per-tick pipeline of phases**.
Ordering is enforced by the loop, not self-reported by subsystems — that's what keeps
runs deterministic. Cross-subsystem coupling (a jammer raising a radar's noise floor;
a seeker reading a target's position) goes through the world's derived `env` blackboard
recomputed each tick, **never** by subsystems calling each other directly.

```julia
using StaticArrays, Random

const Vec3 = SVector{3, Float64}                 # inertial frame, SI, Float64

mutable struct Entity
    id::Symbol
    kind::Symbol                                  # :radar :target :jammer :missile :gps_sv :receiver ...
    pos::Vec3                                      # m, inertial
    vel::Vec3                                      # m/s
    att::SVector{4,Float64}                        # quaternion body<-inertial (identity = [1,0,0,0])
    comp::Dict{Symbol,Any}                         # typed component bag: RCS, emitter params, seeker, ...
end

mutable struct World
    t::Float64                                     # sim time, s
    entities::Dict{Symbol,Entity}
    env::Dict{Symbol,Any}                          # DERIVED per-tick blackboard (RF field, signal env). Cleared each tick.
    events::Vector{Dict{Symbol,Any}}               # detections / intercepts emitted this tick (sent, then cleared)
    rng::Xoshiro                                   # the single seeded stream of truth
    fidelity::Dict{Symbol,Symbol}                  # :propagation => :free_space, :detection => :analytic, ...
end

abstract type Subsystem end

# A subsystem implements any SUBSET of these phase methods. Defaults are no-ops.
integrate!(::Subsystem, ::World, dt::Float64) = nothing   # phase 1: advance kinematics / fuel / clocks
build_env!(::Subsystem, ::World)              = nothing   # phase 2: contribute to derived RF/signal field
observe!(::Subsystem, ::World)                = nothing   # phase 3: sensors read env+world -> measurements (seeded noise here)
decide!(::Subsystem, ::World)                 = nothing   # phase 4: estimators/guidance -> commands for next tick

function tick!(w::World, subs::Vector{<:Subsystem}, dt::Float64)
    for s in subs; integrate!(s, w, dt); end               # 1. kinematics
    empty!(w.env)
    for s in subs; build_env!(s, w);    end                # 2. derive environment (order-independent contributions)
    for s in subs; observe!(s, w);      end                # 3. sense
    for s in subs; decide!(s, w);       end                # 4. guide / estimate / act
    w.t += dt
    return w
end
```

**Time model.** Inner physics step `dt_physics` (e.g. 1 ms — guidance-loop rate) is
fixed and is the unit of determinism. The server emits a state frame to clients only
every `emit_every` steps (e.g. every 16 → ~60 Hz at 1 ms). Sub-systems that want a
slower internal cadence (a radar CPI, a seeker at 100 Hz) gate themselves on `w.t`
inside their phase method — they don't change `dt_physics`.

**Why this shape generalizes:** a radar is a subsystem with `build_env!` (its emission)
+ `observe!` (its detections). A jammer is `build_env!` only (raises noise in a band).
A missile is `integrate!` (airframe) + `observe!` (seeker) + `decide!` (guidance law).
A GPS receiver is `observe!` (pseudoranges) + `decide!` (trilateration). They never
know about each other — only about `w.env`. New slice = new subsystem type satisfying
this contract dropped into an existing world. **That is "atomize then combine" made cheap.**

---

## 4. The server (run modes + loop)

```julia
using Sockets

@enum RunMode PAUSED REALTIME FAST

mutable struct Server
    w::World
    subs::Vector{Subsystem}
    dt::Float64                 # dt_physics
    emit_every::Int
    mode::RunMode
    speed::Float64              # realtime multiplier
    step_budget::Int            # remaining steps for a step(n) command while PAUSED
end

function warmup!(srv::Server)
    # Pay Julia's first-call compilation once, before any client connects.
    snapshot = deepcopy(srv.w)
    tick!(snapshot, srv.subs, srv.dt)
    # also touch the batch path here once (tiny MC) so run_batch is warm too
end

function run_server!(srv::Server; port::Int = 8765)
    warmup!(srv)
    listener = listen(ip"127.0.0.1", port)
    @info "EWSim server listening" port
    sock = accept(listener)                      # single client for v1; multiplex later if needed
    step_count = 0
    last_wall = time()
    while isopen(sock)
        handle_commands!(sock, srv)              # non-blocking drain: may set mode/params/seed/budget, load scenario, run_batch

        n = steps_this_iteration(srv, last_wall) # REALTIME: pace to wall clock; FAST: a fixed chunk; PAUSED: min(step_budget, ...)
        last_wall = time()
        for _ in 1:n
            tick!(srv.w, srv.subs, srv.dt)
            step_count += 1
            if step_count % srv.emit_every == 0
                send_frame!(sock, state_frame(srv.w))
                empty!(srv.w.events)
            end
        end
        srv.mode == PAUSED && yield()            # don't spin
    end
end
```

Run modes: `PAUSED` (only advances on an explicit `step` budget), `REALTIME` (wall-clock
paced, `speed`× multiplier, the default play mode), `FAST` (as fast as possible — for
fast-forward and for driving long deterministic traces). Monte Carlo and heavy DSP are
**not** a run mode; they're a `run_batch` command handled out-of-band on worker threads
so the interactive loop never stalls (§6).

---

## 5. Wire protocol

Framing (both directions): **4-byte big-endian unsigned length** + that many bytes of
**UTF-8 JSON**. One JSON object per frame. That's the entire transport spec.

### Server → client (state stream)

```json
{
  "type": "state",
  "t": 12.34,
  "entities": [
    {"id": "radar1", "kind": "radar",  "pos": [0, 0, 10],     "att": [1,0,0,0]},
    {"id": "tgt1",   "kind": "target", "pos": [42000, 0, 3000]}
  ],
  "telemetry": { "radar1.snr_db": 13.2, "radar1.detected": true, "radar1.pd": 0.91 },
  "events": [
    {"kind": "detection", "by": "radar1", "of": "tgt1", "t": 12.34}
  ]
}
```

`telemetry` is a flat `string → number/bool` bag so any client can bind a slider/readout
to a key without schema changes. `events` are one-shot (sent on the frame they occur,
then cleared).

### Client → server (commands)

```json
{"type": "load_scenario", "path": "scenarios/slice1_roc.yaml"}
{"type": "set_param", "target": "radar1", "key": "pt_w", "value": 1500}
{"type": "set_seed",  "value": 42}
{"type": "run",  "mode": "realtime", "speed": 1.0}
{"type": "pause"}
{"type": "step", "n": 100}
{"type": "reset"}
{"type": "run_batch", "kind": "roc",
 "params": {"target": "radar1", "rcs_m2": 5.0, "trials": 100000,
            "pfa_grid": [1e-8, 1e-6, 1e-4], "snr_db_grid_start": 0, "snr_db_grid_stop": 20}}
```

`set_param` is the universal knob channel: it writes into an entity's `comp` bag, so any
slider the scenario declares (§7) works without protocol changes.

### Big artifacts (out-of-band)

`run_batch` runs on worker threads, writes a flat array to `shared/<name>.bin`, and
notifies the client when done:

```json
{"type": "artifact", "name": "roc_radar1", "path": "shared/roc_radar1.bin",
 "shape": [3, 64, 2], "dtype": "f64", "axes": ["pfa", "snr_db", "[pd_analytic, pd_mc]"]}
```

Godot reads it as `PackedByteArray`; a notebook `mmap`s it. The socket only ever carries
small JSON. This is the seam where "interactive" and "bulk" cleanly separate.

---

## 6. Scenario schema

Declarative YAML is the single source for save/replay, Monte Carlo inputs, test
fixtures, and the core↔client contract. One example (this *is* slice 1's scenario):

```yaml
name: slice1_roc
seed: 42
dt_physics: 1.0e-3
emit_every: 16
fidelity:
  propagation: free_space      # free_space | two_ray
  detection:   analytic        # analytic | monte_carlo

entities:
  - id: radar1
    kind: radar
    pos: [0, 0, 10]
    radar:
      pt_w:        1500
      gain_db:     35
      freq_hz:     9.4e9
      bandwidth_hz: 1.0e6
      noise_fig_db: 3
      losses_db:   4
      pfa:         1.0e-6
      swerling:    1
      n_pulses:    1

  - id: tgt1
    kind: target
    pos: [42000, 0, 3000]
    vel: [-250, 0, 0]
    target:
      rcs_m2: 5.0

knobs:                          # what clients expose as sliders (target+key must exist above)
  - {target: radar1, key: pt_w,   min: 100, max: 5000, label: "Tx power (W)"}
  - {target: tgt1,   key: rcs_m2, min: 0.1, max: 100,  label: "Target RCS (m²)", log: true}
```

`scenario.jl` turns this into `(World, Vector{Subsystem}, knobs)`. Adding a slice means
adding new `kind`s + their component blocks; the loader and protocol don't change.

---

## 7. Repo skeleton

```
ewsim/
  core/                          # Julia package — the headless engine (the "truth")
    Project.toml
    src/
      EWSim.jl                   # top module + exports
      world.jl                   # World, Entity, Vec3, time model
      subsystem.jl               # Subsystem abstract type, phase methods, tick!
      server.jl                  # socket server, run modes, command handling, warmup!
      protocol.jl                # JSON framing, encode/decode, state_frame
      scenario.jl                # YAML -> (World, subsystems, knobs)
      batch.jl                   # run_batch: threaded/GPU MC -> shared/*.bin
      rng.jl                     # seeded stream policy, reset
      # ---- shared physics libraries (grow across slices) ----
      units.jl                   # Unitful at boundaries, SI internally
      frames.jl                  # inertial/body/LOS transforms, quaternions   (missile + DF reuse)
      rf.jl                      # radar equation, link budget, J/S, baseband env
      detection.jl               # Pd/Pfa, Swerling 0–4, CFAR (CA/GO/SO/OS)
      estimation.jl              # least squares, EKF/UKF        (GPS + DF + seeker reuse)
      geometry.jl                # GDOP / error ellipse          (DF + GPS share this)
    test/
      runtests.jl
      test_radar_eq.jl           # free-space SNR vs hand calc; R^4 scaling
      test_detection.jl          # analytic Pd vs Monte Carlo within CI
      test_determinism.jl        # same seed -> bit-identical trace
      test_frames.jl
  clients/
    godot/                       # thin spatial client (Godot 4)
      project.godot
      net/SimClient.gd           # TCP, 4-byte length framing, JSON, reconnect
      scenes/Sandbox.tscn
    notebooks/                   # thin analytical clients (Pluto.jl)
      slice1_roc.jl              # ROC: analytic vs MC convergence
  scenarios/
    slice1_roc.yaml
  shared/                        # memmapped / large artifacts land here
  tools/
    run_server.jl                # julia --project tools/run_server.jl scenarios/slice1_roc.yaml
    run_batch.jl                 # headless MC entry point (no client)
  README.md
  HANDOFF.md                     # this file
```

---

## 8. Slice 1 — radar → detection → ROC (the architecture-proving slice)

**Thin in features, complete in architecture.** This slice's job is to exercise *every*
seam — scenario load, tick contract, server, protocol, RNG/seed, both client types, and
the analytic-vs-Monte-Carlo validation pattern — on the smallest possible physics.

**Physics.** One static radar, one target with an RCS (static or a simple constant-velocity
fly-by). `rf.jl` computes single-pulse SNR from the radar equation (free-space first;
`two_ray` behind the fidelity knob later). `detection.jl` maps SNR → Pd for a given Pfa
and Swerling case, **two ways**:
- *analytic* — closed-form / Marcum-Q (Swerling 0/1 to start),
- *monte_carlo* — draw noise (and target fluctuation), threshold, count.

**Outputs.**
- Live stream: `radar1.snr_db`, `radar1.pd`, `radar1.detected` per frame, plus a
  `detection` event when threshold is crossed — drives a Godot scene with a radar, a
  moving target, and detection blips.
- `run_batch kind=roc`: sweep Pfa × SNR, return both analytic and MC `Pd` to
  `shared/roc_radar1.bin` → the Pluto notebook plots both curves and shows them converge.
  **That convergence is the first lesson and the first regression test at once.**

**Validation tests (must pass before slice 2).**
- `test_radar_eq`: free-space SNR matches a hand calculation to floating tolerance;
  doubling range drops SNR by ~12 dB (R⁴).
- `test_detection`: analytic Pd is inside the Monte-Carlo 99% confidence interval across
  the SNR grid.
- `test_determinism`: same seed + same scenario ⇒ byte-identical state trace.

**Done = ** you can start the server on the YAML, connect Godot and watch blips, move a
slider and see Pd change live, hit "ROC" and get a converging two-curve plot in Pluto,
and `runtests.jl` is green. At that point every architectural decision in this document
is proven and slices 2+ are "add a subsystem."

---

## 9. Shared-library reuse map (why the suite is one project, not four)

The payoff of the core is that the same code teaches across domains. Build these once,
reuse deliberately:

- **`geometry.jl` (GDOP / error ellipse):** DF geolocation error ellipse **and** GPS
  dilution-of-precision are the *same math*. Cross-domain "aha."
- **`estimation.jl` (least squares + Kalman):** GPS trilateration (4th satellite = clock
  bias), DF emitter location, and seeker LOS-rate filtering all call it.
- **`rf.jl` (J/S, correlation peak):** RGPO range-gate pull-off in the EW jamming sandbox
  is mechanically identical to GPS spoofing (match the peak, then drag it) and to a
  missile seeker being walked off by a decoy. One model, three lessons.
- **`frames.jl`:** missile inertial/body/LOS transforms and DF bearing geometry share it.
- **`detection.jl` (CFAR):** the radar lab's CFAR sandbox and the seeker's
  target/decoy discrimination are the same thresholding problem.

When a slice needs one of these, extend the shared lib — don't fork a private copy.

---

## 10. Module roadmap (growth path)

Build one vertical feature slice at a time; each rides the contracts above. Order is a
suggestion, not a dependency chain after slice 1.

1. **Radar/detection** ✅ slice 1 above — also lays the core scaffolding.
2. **Propagation fidelity** — add `two_ray` (multipath lobing, R⁴→R⁸ at low grazing),
   4/3-Earth radar horizon. Pure extension of `rf.jl`; toggle via fidelity knob.
3. **CFAR sandbox** — range-power profile with clutter edge + two close targets;
   switch CA/GO/SO/OS-CFAR, watch masking and the clutter-edge false-alarm spike.
4. **Jamming / EP** — jammer subsystem (`build_env!` raises noise in a band). Teach the
   self-protection R² vs standoff geometry and the **burn-through crossover** on a slider.
   EP = modifiers to effective J/S (freq agility, PRF jitter, sidelobe blanking).
5. **DF / geolocation** — multi-sensor bearings → emitter location + error ellipse
   (`geometry.jl` + `estimation.jl`). The ellipse stretching with bad geometry is the
   showcase visual.
6. **Multi-emitter EW** — interleaved pulse trains → PRI-histogram deinterleaver.
   Generic parametric emitters only.
7. **GPS** — pseudorange = true range + separately-toggleable error terms (clock, iono,
   tropo, multipath, noise); trilateration (`estimation.jl`), DOP (`geometry.jl`), RAIM
   from residuals. Spoofing = RGPO from the EW module.
8. **Missile — ballistic** — build/validate the integrator + frames here (energy
   conservation with drag off). Everything later rides this.
9. **Missile — PID autopilot** — inner loop (commanded → achieved accel). Name the
   "PID-toward-target" stage honestly as a pursuit law.
10. **Missile — proportional navigation** — outer guidance loop; g-limit saturation
    modeled (this is *why* augmented PN matters); small-step/analytic endgame to avoid
    the LOS-rate→∞ blow-up as range→0.
11. **Seeker models** — RF/IR seekers feeding noisy LOS rate → `estimation.jl` filter.
12. **Countermeasures** — chaff (= RGPO), flares (IR decoys); seeker discrimination =
    the EW/CFAR sandbox. This stage *fuses the whole suite.*
13. **Cooperative guidance** — multiple interceptors sharing state. Capstone.

---

## 11. Future expansion directions (beyond the roadmap)

The roadmap (§10) is the *committed* growth path. This section is the *horizon* — places
the design deliberately leaves room to grow. They are sorted by **what they cost the
current architecture**, which is the useful question: the more of these land in Tier A,
the more the core≠front-end / phase-contract / declarative-scenario decisions were worth.

### Tier A — pure extensions (no contract changes)

These are new `Subsystem` types, new fidelity knobs, or new scenario `kind`s. The tick
loop, protocol, and scenario loader don't change. This is where most growth should live.

- **Community / plugin device library.** Subsystems shipped as separate Julia packages
  that implement the §3 phase interface; a scenario references them by `kind`. Generic
  archetypes ("a long-range surveillance radar," "a self-protection jammer") become
  shareable, swappable parts — the right way to model real systems "to a lesser degree
  from public data."
- **Higher fidelity behind existing knobs.** 6-DOF airframe + actuator/fin dynamics and
  angle-of-attack limits (`fidelity.airframe = point_mass | 6dof`); layered atmosphere,
  ducting, tropospheric scatter (`propagation`); land/sea clutter with Doppler spectra,
  which unlocks MTI/MTD lessons; DRFM-style *coherent* jamming as a fidelity step above
  noise jamming. Each is a swap, not a rewrite. **[OPENED — slice 15]** the actuator/fin
  half landed as the `:fin` autopilot rung (a rate-limited fin servo behind the existing
  `autopilot` knob — the g-onset-rate cap `|da_ach/dt| ≤ k_δ·δ̇_max`, a pure Tier-A swap, no
  contract change). The **6-DOF airframe + angle-of-attack half stays DEFERRED**; its trigger
  (a lesson needing the body to point off the velocity vector — α-limited maneuverability or a
  radome/body-rate parasitic loop) is recorded in `docs/plans/slice15.md`. The fin deflection
  state δ that 6-DOF's moment equation consumes is now banked.
- **Sibling domains that reuse the shared libs.** IR/EO seekers and IRST (add an IR
  environment channel to `env`, reuse `frames.jl`/`estimation.jl`); communications EW —
  jamming of frequency-hopping / spread-spectrum links — as a parallel to radar EW;
  multi-sensor track fusion (JPDA/MHT/track-to-track) growing inside `estimation.jl` once
  radar + DF + IR coexist in one scenario.

### Tier B — one new contract each (and exactly which seam moves)

Each of these needs a single, localized extension. The point of naming the seam is so a
future developer extends *that one place* rather than reworking the core.

- **Multi-client / red-team vs blue-team play.** The protocol gains client IDs and
  per-client command authority; the server loop generalizes from one `accept` to a client
  set. Headless determinism is what makes simultaneous fair play possible — one student
  jams while another defends, same truth for both.
- **Record / replay / timeline scrubbing.** Add a trace-log artifact and a "playback"
  subsystem that feeds recorded state instead of integrating. Because the core is
  deterministic, "replay this session with one knob changed" or "with a different seed" is
  exact, not approximate — a powerful teaching move.
- **Sample-level RF / I-Q streaming lab.** The big-artifact channel (§5) grows a
  *streaming* variant — a ring buffer in shared memory — so range-Doppler frames flow to a
  client without bloating the JSON state stream. This is the opt-in path to real pulse
  compression and SDR-style work.
- **RL / autonomous agents in the loop.** Add a step-synchronous, gym-style API (advance
  exactly N ticks → return observation → accept action) beside the wall-clock REALTIME
  mode. The deterministic headless core is already an ideal substrate for training agents
  to jam, evade, or allocate radar time — and those agents then become opponents in the
  sandbox.
- **Web / classroom deployment.** Swap raw TCP for WebSocket framing — the 4-byte-length +
  JSON logic is unchanged — and serve WGLMakie / Pluto in the browser. Removes the local
  install barrier for a class; transport changes, protocol logic doesn't.

### Tier C — new layers / capstone horizons

Bigger pieces that add structure above what exists today.

- **Decision / C2 layer.** A "commander" tier above sensors and effectors: weapon–target
  assignment, radar time-budget and resource management, engagement scheduling. Turns the
  suite from "how does one device work" into "how does a *system* allocate scarce
  attention."
- **Swarms & distributed estimation.** Past cooperative guidance: consensus filtering,
  distributed sensing, swarm tactics. Stresses the multi-agent + fusion stack and is the
  natural home for the most interesting emergent-behavior lessons.
- **Pedagogy as a first-class system.** A "lesson" layer over scenarios (objectives,
  guided narrative, the analytic-truth overlay turned into a teaching aid) plus a
  **headless autograder** that checks declarative success criteria — e.g. "tune the CFAR
  so Pd ≥ 0.9 at Pfa ≤ 1e-6," auto-verified by running the core with no GUI. The headless
  core + declarative scenarios make this nearly free, and for a *teaching* tool it is
  arguably the highest-leverage non-physics expansion of all.
- **Inverse / estimation-as-pedagogy problems.** Flip any forward model: "here is the
  observed ROC / the intercept geometry / the pseudorange residuals — infer the hidden
  parameters." Every model you build forward becomes a guided reverse exercise for free.

The throughline: nearly all of this is reachable *because* physics lives in a headless,
deterministic, declaratively-driven core rather than in the viewer. If a proposed feature
seems to require putting logic into Godot, that's the signal to re-examine it — the answer
is almost always a new subsystem or a new fidelity knob in the core instead.

---

## 12. Risks & watch-items

- **Scope is the dominant risk.** This is realistically several semester-sized sims.
  Go deep on one slice before going wide. Resist building two slices in parallel until
  slice 1's contracts are green.
- **Prove the IPC before building on it.** The Godot↔server socket + framing is the main
  integration risk; the trivial echo version should exist on day one of slice 1.
- **GPU non-determinism vs replay** — keep replay/"truth" on CPU; GPU only for aggregate
  statistics. Tag every result with which path produced it.
- **Julia TTFX** — always via the long-lived warmed server; never per-batch processes.
- **False precision** — a photoreal Godot scene implies accuracy the kinematic model
  lacks. Keep a visible "this is a <fidelity> approximation" badge in every view.
- **Units / frames / signs** — the bug trifecta. Tests for frame round-trips and LOS-rate
  sign from day one.

---

## 13. First actions for Claude Code (ordered)

1. Scaffold `core/` as a Julia package; add deps (`StaticArrays`, `Sockets`, `Random`,
   `YAML`, `JSON3`, `Test`; `Unitful`, `OrdinaryDiffEq`, `CUDA` can wait).
2. Implement `world.jl` + `subsystem.jl` (the §3 contract) with a no-op subsystem and a
   passing `test_determinism.jl` (tick a trivial world twice from one seed, assert equal).
3. Implement `protocol.jl` (4-byte length + JSON) and an **echo server** + a 30-line
   Godot `SimClient.gd` that connects and prints frames. **This de-risks the seam first.**
4. Implement `rf.jl` (free-space radar equation) + `detection.jl` (analytic + MC Pd) with
   `test_radar_eq` and `test_detection` green.
5. Implement `scenario.jl` + the `slice1_roc.yaml` loader; wire the radar/target
   subsystems into the live stream (`snr_db`, `pd`, `detected`, detection events).
6. Implement `batch.jl` `run_batch kind=roc` → `shared/roc_radar1.bin`; build the Pluto
   notebook that plots analytic vs MC and shows convergence.
7. Build the minimal Godot `Sandbox.tscn`: radar + moving target + blips + the two
   declared sliders. **Slice 1 complete; architecture proven.**

---

### One decision still open (answer before step 4)

**Swerling coverage for v1.** Start with Swerling 0 (non-fluctuating) + Swerling 1 only,
or do 0–4 up front? Recommendation: **0 and 1 for slice 1** (enough to show the
analytic-vs-MC convergence and a fluctuating case), add 2–4 in the CFAR slice. This keeps
slice 1 honestly thin. Flag if you'd rather have all five from the start.
