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
- `docs/plans/` — staged plans / context / task checklists (incl. gate-0 kill records).
- `docs/STATUS.md` — the as-built ledger (detailed per-slice notes; grep `## Slice N`).
- `docs/SLICES.md` — the digest: one paragraph per slice, what its lesson was.
- `docs/DEFERRALS.md` — the backlog **and the kill list**. Read before planning a slice.
- `docs/LESSONS.md` — cross-slice method disciplines (probing, teeth, client proofs).

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


## Where the project is (2026-08-18)

**Slices 1–40 COMPLETE & green — 7693 tests.** (Slices 39, **41 and 42** are KILL RECORDS and **43 is a
GATE-0 LAW RECORD** — none shipped code, so the count is unchanged.)
HANDOFF §10 items 1–13 — the committed roadmap — are DONE; slices 15–40 are into the §11
Tier-A horizon.

The live arc is the **missile seeker/radome family (slices 26–40)**: a seeker looks through a
radome whose bend depends on the look angle, so the missile's own body motion feeds back into
the line-of-sight it reports and past a loop gain it shakes itself into a limit cycle. Slices
27–31 built the gyro feed-forward cure and priced it (belief accuracy, the slope *curve*, the
engagement envelope, gyro error); 32–33 turned it into a field-of-view budget; 34–38 put the
seeker on a **gimbal** and worked through its index, its servo bandwidth, its handover, its
reference frame and its gyro; 40 gave that gimbal **inertia** (a second-order servo).

**The rule that keeps paying** (slices 33, 34, 35, 37, 38): *aim `R̂` at the glass's worst-case
slope* (`radome_slope_worst`) and the cost — of FOV, of detector window, of servo bandwidth, of
which frame the servo closes in — mostly goes away.

## Read on demand — DO NOT preload these

Triggered by what you are about to do, not by topic. Reference them as paths; **never** as
`@`-imports (those get inlined into context eagerly and recursively, which is the whole problem
this split exists to fix).

| Before you… | Read |
|---|---|
| plan slice 43 / pick the next slice | `docs/DEFERRALS.md` — the backlog **and the kill list** |
| change architecture, frames, the wire protocol, the tick contract | `HANDOFF.md` |
| quote slice N's numbers, test names, or gate detail | `docs/STATUS.md` — grep `## Slice N` |
| recall what slice N's *lesson* was | `docs/SLICES.md` |
| write a gate-0 probe, a verifier tooth, or a HUD branch | `docs/LESSONS.md` — cross-slice method disciplines |
| re-run slice N's showcase / verifier | `docs/STATUS.md` §Slice N has the exact commands |

**When a slice completes**, the doc ritual writes to FIVE places, in this order: the full
as-built block into `docs/STATUS.md` (under a `## Slice N — TITLE (date)` heading), a paragraph
into `docs/SLICES.md`, the new/killed candidates into `docs/DEFERRALS.md`, any transferable
method lesson into `docs/LESSONS.md`, and **only** the state line + any new dead end into
`CLAUDE.md`. Keep `CLAUDE.md` under ~20 KB — it is loaded on every single turn.

## Dead ends — do not rebuild

Kept inline because the expensive failure is not "I didn't read a file", it is **rebuilding
something already killed**. One line each; the reasoning is in `docs/DEFERRALS.md` and
`docs/plans/sliceN.md`.

- **A nulling-loop head servo** (slice 39) — DEAD. Infinite loop gain is a reparameterization of
  the servo time constant, not an architecture (5.8e−09 m over 12000 ticks). What survives is
  *finite* loop gain, and even that must first prove its rejection curve differs from a lag's.
- **Memory track / re-acquisition** — DEAD. A break in this arc is not an episode, it is the rest
  of the flight; the cure belongs to the ESTIMATOR (frozen rate), not the head. Three slices
  banked it and all three mis-located it.
- **A scalar rate-limited fin inside the coupled loop** (the slice-20 candidate) — DEAD.
  `δ_max` structurally SHADOWS `δ̇_max`.
- **A second-order FIN actuator** (slice 41, the deferral slice 40 named as its own) — DEAD, on
  REPARAMETERIZATION. Two single-axis `(k_α, k_q)` retunes each reproduce its whole threshold curve to
  0.00–1.01 %. ⭐⭐ **The reason is the rule to carry: a pole differs from a gain ONLY in that its phase
  VARIES with frequency, and that loop's fin command is a single 1.6488 Hz line — one point of a phase
  curve is a number, which is what a gain is.** Slice 38's *"`s` adds PHASE and scaling a slope
  cannot"* has teeth only where the loop is BROADBAND. ⇒ **before proposing any new dynamic element
  here, measure the SPECTRUM of the signal it will sit on.** (The physics was real — inside the main
  control loop a lag DEstabilizes, the opposite of its sign on 34–40's feed-forward path — and it did
  not matter.)
- **A SEEKER SEARCH PATTERN** (42 gate 0; **re-measured and LAWED at slice 43 gate 0**) — DEFERRED, not dead,
  **blocked on its precondition**: a wider window is FREE here, and slice 43 makes that objection SHARPER —
  ⭐⭐ **the cost of acquiring is the OVERLAP DEFICIT `|err| − fov`, not the pointing error** (err −14/fov 12
  ≡ err −12/fov 10 to every digit), so widening glass and travelling further are THE SAME ACT. Law:
  `travel = deficit/(1−ω/ρ)`, `t_lock = travel/ρ + τ` **for ρ ≤ rate_max** (ω = LOS rate, anchored to telemetry;
  ⚠ a ρ-only form was an advisor catch — count AXES, not cells). ⭐⭐ **Sweep floor 1.0–1.5 °/s = THE AXIS
  THE SEARCH DOES NOT SWEEP** (an LOS-rate race and a missing reversal were both measured and REFUTED): at
  ρ = 1 the swept axis closed to 9.75° INSIDE a 10° window and still failed, held out by 2.49° of UNSWEPT-axis
  drift on the RADIAL gate — 25 % of the window radius; ⭐ **first flying arm where a PER-AXIS FOV would flip
  the verdict** (slice 34's deferral). Guess right and coverage is **never REACHED** (lock 2.07° into a
  3–30° pattern — 42's "free" was a flat row misread); guess wrong it costs `2S` at an **accelerating** price
  (5→39 % over `2/ρ`, never-locks by S = 25). ⚠ 42 §V.4's ρ_min table is VOID (servo bypassed; `none ≤ 16`
  was its own grid edge — 18 and 22 °/s; +side rows are stop contamination). ⚠ **An open-loop sweep WINDS UP
  against `rate_max` — what saturates is the AMPLITUDE** (20° commanded at 64 °/s → 4.4° swept, arm FAILS);
  cure `ρ ← min(ρ, rate_max)`, and anti-windup is a CAUTION not an architecture (moves no verdict in 16 cells).
- **AN "ACQUISITION KNIFE-EDGE" / "a lock at the rim is worth nothing"** (slice 42, gate 1) — DEAD. ⭐⭐ **The
  band is `ω_LOS · dt` — ONE INTEGRATION STEP: halve `dt` and it halves** (0.0036° against a 10° window).
  The gate-0 table already said so — the "worthless lock" cell's miss was BYTE-IDENTICAL to the never-locks
  cell's, i.e. the null case relabelled, and `off@lock == fov` to four decimals was the inclusive `off ≤ fov`
  gate echoing its own constant. The servo-vs-LOS *race* reading is refuted too (same digits at 8 and
  60 °/s — **the head's command is written at the END of the tick, so the servo is idle for exactly one
  tick, and being one tick late is not something a faster servo fixes**), and the mirror-image sign does
  not fail at all. ⇒ **before shipping a narrow threshold effect,
  RE-FLY IT AT HALF `dt`; and read a claimed STEP against the NULL cell first.**
- **Seeker noise × the BTT roll loop** — DEAD. A ~1000:1 low-pass (std 1.07 vs 1.6e−5).
- **A cubic radome curve** — killed at gate 0: unbounded slope, the bend diverges, no domain.
- **An angle-domain radome corrector** — built and measured, does NOT ship: it needs the look
  angle and can only see it *through* the bend it is removing. General rule: **compensate with a
  signal that is not itself corrupted by what you are compensating.**
- **False-fidelity / dead knobs** — a knob consumed once at load is not a knob: `speed` (slice 19),
  launch altitude (21), the handover bias key (36), `ζ` on the lag rung (40), `k_δ` (15), `(R̂,s)`
  (31). **Compose your own equivalences before believing a rung is an architecture.**
- **Disqualified by non-monotonicity** — `k` (28), `ω_n` (40), σ_seek (25), and the miss-vs-K /
  miss-vs-α_stall reversals (20, 22). A domain that reverses the lesson is not a domain.
- **Harness traps that cost real hours** — a verifier's `STEPS` MUST be a multiple of the
  scenario's `emit_every` (else it hangs silently); `%g` / `%.2e` are not GDScript specifiers and
  a bad one makes the WHOLE `%` fail silently on a green run; frame-sampling error is asymmetric
  (a miss samples faithfully, a HIT samples coarsely); an rms measured where a clamp binds cannot move
  and reads as a KILL (slice 41: α_max bound 78 % of band ticks at the authored design, so a real
  1.27–4.45× effect read 0.4 %) — carry a contamination column IN BAND on every arm and read it first.

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
    ⚠⚠ **A VERIFIER'S `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every`** (slice 31; slice 30
    escaped it only by accident, 20000 = 16×1250). The server emits every `emit_every`th tick, so
    `STEPS = 15000` at `emit_every = 16` makes the LAST frame `t = 14.992` while the drain loop waits
    for `t ≥ STEPS·dt` = 15.000 — which never arrives. The run hangs **silently, with no output at
    all**, to `MAX_SECONDS`, and reads exactly like a slow wire. ⚠ Compounding it: Godot's stdout is
    BLOCK-BUFFERED into a file or a pipe, so per-arm progress is invisible until ~4 KB accumulates.
    **When a verifier looks slow, MEASURE before waiting** — timing the core alone (`tick!` in a
    loop, no server) and a minimal-client frame-rate probe separates physics from emit path from
    client in two cheap runs.
    ⚠ **Anything the verdict computes inside `_draw` has NO headless proof** — extract it to a pure
    helper the UI test can call (slice 31's aim-point comparison shipped wrong and only the SHOT
    caught it).

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
