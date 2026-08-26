# EWSim - conventions and hard-won disciplines (the DETAIL)

**Split out of `CLAUDE.md` on 2026-08-18**, when that file was cut back to being a reference/router.
`CLAUDE.md` keeps a ONE-LINE hook per convention so a session knows the trap exists; this file holds
the teeth - the function names, the rungs, the measured numbers. **Grep this file, do not paraphrase
the hooks.**

Companions: `docs/LESSONS.md` (cross-slice METHOD disciplines - probing, gates, verifier teeth),
`docs/DEFERRALS.md` (the backlog and the kill list), `docs/STATUS.md` (per-slice as-built),
`HANDOFF.md` (frozen architecture).

---

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
    ⚠⚠ **A HUD's WIDTH BUDGET IS A PROPERTY OF THE *VIEW*, NOT OF THE FAMILY** (slice 49). The
    right-anchored block at `vp.x − 430` has 430 px in the 3-D airframe view, whose right edge is
    empty — and only **390** in the SPATIAL view, which prints ALTITUDE TICK LABELS at `vp.x − 34`
    (`_draw_spatial_backdrop`, "alt (km)" at `vp.x − 52`). Both origins are right-anchored, so **no
    window size rescues an over-wide line**. Assert in PIXELS against the budget *this view* leaves,
    require a MARGIN (≥12 px — slice 49's first run passed at exactly 390.0 of 390), and have the
    tooth NAME the widest line so a pass on the limit is distinguishable from a fail.
    ⚠⚠ **A LIVE SLIDER DRAG INVALIDATES A LATCH JUST AS A RESET DOES, AND IT REACHES NONE OF THESE
    FOUR PROOFS** (slice 49): the verifier `reset`s between arms, the UI test presses the Reset
    BUTTON, the smoke-load touches no control, and a shot is one static frame. Every slice that
    latches or peak-holds needs a DRAG tooth as well as a RESET one — and only the instruments
    belonging to the thing the slider changes are cleared; the ones belonging to the RUN are kept
    (clearing those re-opens a closed window for one frame). `docs/LESSONS.md` has the split.
    ⚠ **Anything the verdict computes inside `_draw` has NO headless proof** — extract it to a pure
    helper the UI test can call (slice 31's aim-point comparison shipped wrong and only the SHOT
    caught it).

15. **Batches own their OWN seeded stream** (never `w.rng`) so a sweep can't desync the live trace
    — the *distribution* path (no byte-identity assert; the Threads/GPU seam). Determinism is CPU.
