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
    ⭐⭐⭐ **AND MEASURE IT AT THE SLIDER'S EXTREMES, NEVER AT THE AUTHORED ARM** (slice 57): the
    tooth caught a real **403 px against a 400 px column** because no authored pair in this repo is
    wider than 12.5° while that slider's ceiling flies **63.2456°** — every earlier width tooth
    measured the shipped arm and would have passed green with the widest arm off the edge. ⚠ The fix
    is a SHORTER LINE: the columns are right-anchored, so a bigger window clips identically.
    ⚠⚠ **A LIVE SLIDER DRAG INVALIDATES A LATCH JUST AS A RESET DOES, AND IT REACHES NONE OF THESE
    FOUR PROOFS *UNLESS THE VERIFIER DRIVES ONE*** (slice 49; ⭐ slice 53 drove the first one): by
    default the verifier `reset`s between arms, the UI test presses the Reset BUTTON, the smoke-load
    touches no control, and a shot is one static frame. **The shape that closes it is two `step`
    commands with a `set_param` between them** — and it is REQUIRED whenever the latch lives in the
    CORE and ships as a wire key, because then a client-side disarm leaves a headless proof reading
    a stale value as a live measurement: green, and false (slice 53 §4.4). Every slice that latches
    or peak-holds needs a DRAG tooth as well as a RESET one — and only the instruments belonging to
    the thing the slider changes are cleared; the ones belonging to the RUN are kept (clearing those
    re-opens a closed window for one frame). `docs/LESSONS.md` has the split.
    ⚠ **Anything the verdict computes inside `_draw` has NO headless proof** — extract it to a pure
    helper the UI test can call (slice 31's aim-point comparison shipped wrong and only the SHOT
    caught it). ⭐⭐ **INCLUDING *WHICH BRANCH WINS*** (slice 50): when two view markers can be up at
    once, move the dispatch out of `_draw` into one pure function both `_draw` and the UI test read
    (`_spatial_hud_kind`, slice 53) rather than photographing the answer.
    ⚠⚠ **AND THE BLIND SPOT WORKS BOTH WAYS: A *FRAME-HANDLER* ACCUMULATOR HAS NO HEADLESS PROOF
    EITHER — AND NO WINDOWED SHOT CAN SEE IT** (slice 53). Slice 49's longest-closing-loss gauge is
    accumulated in `_on_state`, gated only on `_aspect_view` + an observer + `target_range_m` — all
    of which a slice-53 wire also has — so it ran silently for a whole pass, one `draw_string` from
    being printed under another slice's headline. **Gate at the accumulator's own site, and pair the
    tooth with a CONTROL** (the identical frames on a client without the new marker must still
    accumulate) or the tooth passes just as well on a broken accumulator and retires the older
    slice's proof instead of scoping it.
    ⚠ **THE WINDOWED SHOT'S FAILURE CLASSES NOW INCLUDE *VIEW EXTENTS*, NOT ONLY HUD TEXT** (slice
    53; the previous catches were all text — 31's aim-point, 46's clipping, 48's defaulted zero,
    49's `Pd 0.00`). Every wire 1–52 launches at the origin and flies OUTWARD, so `_world_to_screen`
    mapped `x = 0` to the left margin and needed no lower bound; a **crossing** pass is the first
    geometry that breaks it, and half the flight drew off-screen with every test green. A new
    geometry gets its extents LOOKED AT, and the fix is marker-gated with the default reproducing
    the old mapping bit for bit (`x − 0.0 === x`).

15. **Batches own their OWN seeded stream** (never `w.rng`) so a sweep can't desync the live trace
    — the *distribution* path (no byte-identity assert; the Threads/GPU seam). Determinism is CPU.

16. **The trap checklist — every entry below cost real hours.** Read the relevant half BEFORE
    writing a probe, a verifier tooth, a gate-3 proof or a HUD branch. This is the ONE list of
    trap NAMES; `docs/LESSONS.md` carries the long-form story behind each (grep the slice number),
    and §14 above carries the gate-3-specific teeth in full. ⚠ It deliberately does NOT live in
    `docs/PROHIBITIONS.md`: that file rules on CANDIDATES — a trap is a method discipline, not a
    component anyone proposed.

    **(a) HARNESS / PROBE traps.**
    - A verifier's `STEPS` MUST be a multiple of the scenario's `emit_every`, or the run hangs
      **silently** to `MAX_SECONDS` and reads exactly like a slow wire (slice 31; §14 has the
      arithmetic and the "measure before waiting" recipe).
    - `%g` and `%.2e` are NOT GDScript format specifiers, and ONE bad specifier kills the WHOLE `%`
      expression. ⚠ **Grep the whole file for specifiers**: a `print` is proved by its own output,
      but a `_fail` message's format string is proved by NOTHING until the test fails (slice 49,
      the THIRD occurrence; the class of the slice-1 `%g` bug at convention 6).
    - **Frame-sampling error is ASYMMETRIC** — a MISS samples faithfully, a HIT samples coarsely.
      Quote frame numbers and pin the ratio ([[ewsim-missile-verifier-sampling]]).
    - An rms measured where a CLAMP binds reads as a KILL of whatever you were measuring — it is
      the clamp's number, not the physics'.
    - A key that stops EMITTING makes `.get(k, 0.0)` print a **DEFAULTED ZERO as a PASSED TEST**.
      ⚠ WHICH default you pick is a CLAIM — pick the one that asserts the least (slice 49); ⚠⚠ and
      when the lesson's own NULL *is* that value, only **PRESENCE** separates the two (slice 50).
    - ⚠⚠ **A PEAK-HOLD cannot see a knob that FELL** (slice 52) — re-arm on the drag, at the instant
      the new setting OWNS the quantity, not at the next frame.
    - A probe's "has this arm drained yet?" predicate must be **ARM-SPECIFIC**, or the second shot
      photographs the first (slice 52).
    - ⚠⚠ **A SUITE COUNT IS ONLY EVIDENCE IF THAT RUN CONTAINED THE NEW TESTS** (slice 55): an
      illegal `@test` (a keyword riding a `&&` chain) aborts its FILE at parse time, the run
      continues, and the summary still prints a big green number. **Read `Pass / Error / Total`,
      never the Pass column** — and an UNCHANGED count beside new tests is the signature, not
      reassurance.
    - ⚠⚠ **`@test_throws ErrorException` IS A TAUTOLOGY when the fixture can fail for an unrelated
      reason** (slice 55: three loader-guard tests went green off a missing `mass_kg`, and the
      repair uncovered a SECOND guard behind it). Assert WHICH refusal fired — `occursin` on
      `sprint(showerror, err)`.
    - ⚠ **A GAUGE READ FROM A FRAME IS NOT THE GAUGE READ FROM A TICK** (slice 55): assert the
      dimensionless FRACTION in the client and pin the exact degrees in `core/test/`, where the
      sampling is exact. A verifier constant copied from a core test failed by 150 %.
    - ⚠ **A POST-INTERCEPT EPISODE IS A DIFFERENT ENGAGEMENT** — scope an engagement gauge to the
      slice's own latch, not to a tick count (slices 52 and 55, the seeker re-searching a target
      that is now behind the missile).
    - ⚠⚠ **A `set_param` COMMAND'S FIELD IS `target`, NOT `id`** (slice 40's first-run bug, re-walked
      in full by slice 57). The server reads `cmd[:target]`; a command carrying `id` is **silently
      ignored** — no error, no reply, and the arm simply reports the previous setting's answer, which
      reads as "the slider does nothing". ⚠ Only a **READ-BACK TRIPWIRE** catches it: assert the wire
      reports the value you just set before you believe any arm.
    - ⚠⚠ **A WINDOWED SHOT MUST WAIT FOR `EWSIM_SERVER_LISTENING` BEFORE LAUNCHING GODOT** (slice
      57): `SimClient` connects ONCE and does not retry, so a harness that starts both together races
      the server's startup and dies at stage 0 with a timeout that reads like a hung scene. Poll the
      server log for that line; a fixed sleep is a guess.
    - ⚠⚠ **Slice 53 RETRACTED "no gate-3 proof DRAGS a slider"** — its verifier does, and a drag
      tooth is MANDATORY once the latch lives on the WIRE (§14; retraction §7 of
      `docs/PROHIBITIONS.md`). ⚠⚠ **Slice 54 adds the harder half: something must deliberately
      SURVIVE the drag**, or the tooth only proves you can clear state.

    **(b) HUD / VIEW traps.**
    - A HUD budget is in **PIXELS** and belongs to the **VIEW**, not the family (slices 46, 49;
      §14 has the 430-vs-390 px numbers and the ≥12 px margin rule).
    - ⚠⚠ It is not just a WIDTH but **a CORNER THAT MAY ALREADY BE OCCUPIED**: slice 54's two
      right-anchored blocks collide at EVERY window size, and a width tooth passes anyway.
    - ⚠⚠ **A view marker must go in the chain its own wire actually REACHES** (slice 54: the first
      draft sat first in `_spatial_hud_kind()` and was DEAD CODE on a `:cfar` wire, reading as
      handled). It must also **separate wires that differ only by the SLIDER**, and be gated on the
      author's KEY, never on the slider's VALUE (slice 52).
    - ⚠ **Gate a windowed shot on the WIRE, never on a FRAME COUNT** (slice 54), and ⚠ a
      **CUMULATIVE** gauge read mid-pass is not the pass's answer.
    - ⚠ `get_theme_default_font()` does NOT exist on `Sandbox.gd` and calling it breaks EVERY
      dependent script; the file has exactly one `_font`.
    - ⚠ Anything the verdict computes inside `_draw` has **no headless proof** — including WHICH
      dispatch branch wins; and the blind spot works both ways, since a **frame-handler**
      accumulator has no proof either (§14, slices 31 / 50 / 53).
    - ⚠⚠ **A HUD LINE IS A SMALL STATE MACHINE AND ITS BRANCH ORDER IS A CLAIM** (slice 55, both
      defects the shot caught over a green verifier AND a green UI test): a **LATCH read as a live
      state** (`_detect_blind` tested before `acquired` ⇒ "waiting on the horizon" under a green
      "SAW IT AT ONCE"), and **two different NULLs collapsed onto one sentence** (no search
      authored vs a search never needed). ⚠ The UI test can PIN each once named — it cannot FIND
      them, because it chooses its own arguments.
    - ⚠⚠ **AN INHERITED BLOCK'S SENTINEL CAN INVERT THE VERDICT ON A NEW WIRE** (slice 55): slice
      48's `search_t_lock_s` is correctly −1.0 where no sweep ever ran, and 48's block renders that
      as "never found it" — over an intercept. Ask what the inheriting block SAYS about the value,
      not whether the key is right.
    - ⚠⚠ **A DERIVED READOUT MUST HAVE THE SAME SHAPE AS THE PREDICATE BESIDE IT** (slice 55): a
      2-norm margin under an ∞-norm window can carry the OPPOSITE SIGN to the validity lamp — the
      `√2·stop` hazard on the glass instead of the trunnion. ⚠ Ship the new predicate's own
      readout, and ship it PER AXIS: a worst-of is sign-honest and hides the lesson.
    - ⚠⚠ **A HUD STRING STATED AS FACT IS A CLAIM WITH A SHELF LIFE, AND A SLIDER IS WHAT EXPIRES
      IT** (slice 57, on slice 55's line): *"the el axis is idle"* was unconditional — true at 99.7 %
      idle on 55's one authored pair, FALSE at 9 % on 57's high wall — and its neighbour quoted two of
      55's constants as fact. ⇒ **the moment a slider can move what a sentence describes, that
      sentence must be COMPUTED FROM THE WIRE or deleted** (convention 13 one level up: the client may
      not recompute physics, and may not REMEMBER it either). ⚠ A threshold inside such a sentence is
      itself a claim — pick it against FLOWN ratios, not round numbers: 0.50 called slice 57's shipped
      arm idle, and **0.70** of the half-width is what four flown ratios support. ⚠ Note which slice
      shipped the defect: **55, whose own UI test existed to prevent it.**
