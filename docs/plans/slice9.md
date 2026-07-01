# Slice 9 — Missile: the PID autopilot (inner loop) under a pursuit outer law

The **second slice of the missile-guidance arc** (HANDOFF **§10** item 9) and the first to
put a *closed control loop* on the airframe that slice 8 built. Slice 8 delivered a passive
`BallisticMissile` — forces (gravity + drag) → `integrate!` — plus the 3-D `frames.jl` LOS
kernel. Slice 9 adds the **inner autopilot loop**: a **PID controller** that turns a
*commanded* lateral acceleration into an *achieved* one through a first-order airframe/actuator
lag, driven by an **outer pursuit law** that points the commanded acceleration at the target.
It lights **phase 4 (`decide!`)** on the missile entity for the first time (the phase slice 5
lit for the DF geolocator) — *"a missile is `integrate!` (airframe) + `observe!` (seeker) +
`decide!` (guidance)"* (HANDOFF §3, line 164). Source of truth: HANDOFF §10 item 9 — *"Missile —
PID autopilot — inner loop (commanded → achieved accel). Name the 'PID-toward-target' stage
honestly as a pursuit law."* — and §10 item 10 (*"proportional navigation; g-limit saturation"*),
which **structurally fixes slice 9 as the inner loop**: the pursuit outer command is a
placeholder that slice 10 replaces with PN, and g-limit *saturation as a lesson* is slice 10, not
here.

**The lesson is the autopilot's tracking, shown as a number — not miss distance.** Miss distance
conflates the guidance law and the autopilot; the *inner-loop* lesson is the gap between
**commanded** and **achieved** lateral acceleration. Dial the `autopilot` fidelity:

- `:ideal` — the actuator is perfect, `a_achieved ≡ a_cmd` instantly. The pursuit intercept is
  clean.
- `:pid` — a realistic first-order airframe lag (`τ·ȧ + a = u`) closed by a **PID** on the
  acceleration error. Under a **P-only** controller the achieved accel **undershoots by exactly
  `1/(1+Kp)`** of the command (steady-state error — the closed-form headline, the slice-9
  equivalent of slice-8's `½·g·dt·t`: 33.3 % at `Kp = 2`, 11.1 % at `Kp = 8`); adding **integral**
  drives that steady-state error to **zero**; **derivative** damps the ringing. Watch the
  commanded-vs-achieved readout close the gap as you tune `Kp`/`Ki`/`Kd`, and watch a badly-tuned
  loop **miss** the intercept the ideal autopilot hits.

**The second lesson is teed up for slice 10, as a visible readout:** pursuit is an honest
*tail-chaser*. Because it always points **at** the target (never **leads** it), the commanded
lateral accel **grows toward intercept** (the probe measured `|a_cmd|` climbing 21 → 214 m/s²
over a crossing engagement). That growing endgame demand — and the saturation it courts — is
exactly *why augmented proportional navigation matters* (slice 10). Slice 9 surfaces `|a_cmd|` so
the tail-chase is legible; it does **not** yet model saturation-as-lesson.

**Scope (one lesson per scenario — the slice-3 principle):** a single guided **interceptor**
(the slice-8 `BallisticMissile` airframe) pursuing a single **constant-velocity target** in a
**crossing engagement**, jamming/seeker-noise-free. Guidance reads **target truth**, not a noisy
seeker (that is slice 11). The autopilot/airframe is a **first-order lag** (not a full transfer
function). The switchable **fidelity is `autopilot ∈ (:ideal, :pid)`** (a *physics-changing*
knob — the slice-2/8 shape, **not** a slice-5/6/7 toggle-bit-identical rung; there is **no RNG**
in the missile arc). Explicitly **deferred**: **proportional navigation** and the **`:guidance`
fidelity** (pursuit vs PN — slice 10; the `:guidance` key is *reserved* now and left unused),
**g-limit saturation as the lesson** (slice 10 — slice 9 keeps a *generous* `a_max` clamp purely
as a crash-guard, tuned so it never binds), **noisy seekers / LOS-rate filtering** (slice 11),
**6-DOF / fin-actuator dynamics** (§11 Tier A — the lag is a lumped scalar model), **thrust /
boost** (the interceptor coasts, slice 8's passive body). 3 review gates (mirroring slices 5–8:
pure primitives → subsystem wired → scenario + client + verifiers).

**Done =** start the server on `slice9_pursuit.yaml`, connect Godot, watch (in the **existing
spatial / elevation view**, extended) the interceptor pursue a crossing target to a clean
intercept under `:ideal`; the readout shows `a_cmd`, `a_ach`, and the **tracking gap ≈ 0**. Cycle
the fidelity button to `:pid` and watch the **gap open** (the achieved accel lagging/undershooting
the command) and the pursuit **miss** or degrade; drag the **`Kp` slider** and watch the P-only
undershoot shrink toward `1/(1+Kp)`, the **`Ki` slider** drive the steady-state gap to zero, the
**`Kd` slider** damp the ringing; watch `|a_cmd|` **climb toward intercept** (the pursuit
tail-chase, the slice-10 tee-up). With `runtests.jl` green on the new closed-form `test_guidance.jl`
+ the wired `test_missile.jl` arms (the `1/(1+Kp)` steady-state pin, the ideal-passthrough, the
intercept, the not-a-dead-knob toggle) and slices 1–8 **byte-identical** (the guarded `:a_ctrl`
seam — **empirically confirmed green, see Decisions §0** — plus the pure `guidance.jl` touch no
radar/detection RNG path; the `_sample_z` golden + `test_determinism` untouched).

## The physics / math (named approximations — HANDOFF §1)

### 1. The outer pursuit law (`guidance.jl`, pure; RNG-free) — the *placeholder* guidance

Pure-pursuit commands a lateral acceleration that steers the velocity vector toward the
line-of-sight to the target:

    v̂    = v / ‖v‖                                  (heading)
    los  = los_unit(missile_pos, target_pos)        (frames.jl)
    perp = los − (los·v̂) v̂                          (LOS component ⟂ to heading)
    a_cmd = (K_guid · ‖v‖) · perp                    (m/s²; K_guid has units 1/s)

`a_cmd` is perpendicular to the heading (a pure turn, no speed change — the coast assumption).
`K_guid` is a turn-rate gain. **Named as a pursuit law, honestly (HANDOFF §10 item 9):** it points
*at* the target, does not *lead* it, and is the tail-chaser slice 10's PN replaces. The endgame
demand `|a_cmd|` **grows** as range closes (the probe: 21 → 214 m/s²) — the slice-10 motivation,
surfaced as telemetry. A **generous `a_max` clamp** caps `‖a_cmd‖` (crash-guard only — a live
`Kp`/`K_guid` slider must not blow up a tick; saturation-as-lesson is slice 10, and the scenario is
tuned so `a_max` **never binds** — the probe already reached ~22 g, so pick geometry/gains with
comfortable margin).

### 2. The inner PID autopilot (`guidance.jl`, pure; RNG-free) — the slice-9 *lesson*

The airframe/actuator that realizes the command is a **first-order lag** (a lumped scalar model —
named approximation, NOT a full transfer function; 6-DOF is §11 Tier A):

    τ · ȧ_ach = u − a_ach                            (plant: fin command u → achieved accel a_ach)

closed by a **PID** on the acceleration error `e = a_cmd − a_ach`:

    u = Kp·e + Ki·∫e dt + Kd·ė

**Closed-form headline (the `½·g·dt·t` of slice 9):** with **P-only** control (`Ki = Kd = 0`) the
loop settles to a steady-state **undershoot** `e_ss / a_cmd = 1/(1+Kp)` (33.3 % at `Kp = 2`,
11.1 % at `Kp = 8` — probe-confirmed exactly). **Integral action drives `e_ss → 0`** (probe:
`ss_err ≈ −0.00`); **derivative damps** the overshoot. `:ideal` bypasses the loop entirely
(`a_ach ≡ a_cmd`) — the perfect-actuator reference. The PID integrates at the **tick `dt`**
(1 ms); the one-tick `decide!→integrate!` delay is negligible there (see §4). PID **state**
(`∫e`, `e_prev`, `a_ach`) is per-missile and lives in the entity `comp`.

### 3. The seam into the airframe (`missile.jl`)

`BallisticMissile.integrate!` adds the autopilot's **control specific force** to the force field:

    accel = haskey(c, :a_ctrl) ? (v -> total_accel(v; …) + c[:a_ctrl]::Vec3)
                               : (v -> total_accel(v; …))          # slice-8 closure, UNCHANGED

The `haskey` guard makes a **ballistic** missile (no `:a_ctrl`) take the **exact** slice-8 code
path — byte-identity by construction, **not** by trusting `total_accel(v) + zero(Vec3)` to be
bit-safe (it is not: `-0.0 + 0.0 → +0.0` flips a bit the `reinterpret` determinism tests catch).
`:a_ctrl` is a **`Vec3`** (the SVector+SVector path stays bit-exact). The guidance subsystem writes
`:a_ctrl` in `decide!` (phase 4) → applied in the *next* tick's `integrate!` (phase 1). Impact /
energy / velocity-aligned-attitude logic is **reused verbatim** — the guided missile needs all of
it (the intercept, the `:impact` event, the energy readout).

### 4. Phase ordering & the one-tick delay

Per tick: `integrate!` (phase 1) runs first, then `build_env!` (2), `observe!` (3), `decide!` (4)
— so a command computed in `decide!` at tick *N* is applied by `integrate!` at tick *N+1* (the
subsystem.jl contract: *"decide! → commands for next tick"*). Consequences, all named: (a) **tick 1
is uncontrolled** — the guided missile's first step is pure ballistic (a *free* byte-identity
anchor); (b) the control lags the state by one `dt` = 1 ms (negligible at guidance rate). The
target's `decide!`-time truth is read; guidance is truth-fed (no seeker noise — slice 11).

## Decisions taken (advisor-reviewed 2026-07-01 — architecture endorsed; probe + seam pinned)

**0. The byte-identity seam is EMPIRICALLY CONFIRMED (not assumed).** The `haskey(c, :a_ctrl)`
guarded edit to `BallisticMissile.integrate!` (§3) was applied and the **full suite ran
1633/1633 green** — the `_sample_z` golden, the `reinterpret`-based `test_determinism`, and the
RK4-parabola-to-machine-eps tests all pass — then reverted (implementation belongs to gate 2). The
guard is the recommended seam: a ballistic missile is byte-identical *structurally*. (The advisor
flagged this as the one item that could invalidate the architecture; it is now pinned.)

**1. Cascade architecture — outer pursuit, inner autopilot — is roadmap-REQUIRED.** Slice 10 is the
outer loop (PN); slice 9 is unambiguously the inner loop with pursuit as a *stand-in* outer
command. **Build the seam so slice 10 swaps ONLY the `a_cmd` computation** (pursuit → PN) without
touching the inner loop: factor `pursuit_accel(...)` and `autopilot_step(...)` as **separate pure
functions** in `guidance.jl`. **Own `:autopilot` now; RESERVE `:guidance`** (pursuit-vs-PN) for
slice 10 (documented, unused — the "generic word namespaced by consumption" precedent).

**2. Fidelity `autopilot ∈ (:ideal, :pid)` — physics-changing, NOT toggle-invariant.** There is NO
RNG in the missile arc, so "RNG lockstep / draw-count-invariance" is **vacuous** (the slice-8
advisor #1 catch — do NOT copy the slice-5/6/7 template's false claim). Three distinct claims:
(1) **introduce-safe** — absent an `Autopilot` subsystem nothing reads `:autopilot`, so introducing
it on any slice-1..8 scenario is a no-op → byte-identical; (2) **same-config replay is
bit-identical** (deterministic, trivially — no RNG to desync); (3) a mid-run `:ideal↔:pid` toggle
**CHANGES the trajectory** (the not-a-dead-knob property — the *opposite* of slices 5/6/7). The
probe confirms (3) strongly: at `K_guid = 3`, `:ideal` miss 4.7 m vs `:pid`(P-only) miss 228 m.

**3. The subsystem: a new `Autopilot <: Subsystem` lighting `decide!`, in `missile.jl`.** It reads
the missile + its **nearest `:target`** (`_nearest_target` — reuse radar.jl's, or mirror it),
computes `pursuit_accel` (outer), runs `autopilot_step` (inner PID, dispatching `get(w.fidelity,
:autopilot, :ideal)`), and writes `comp[:a_ctrl]::Vec3` for the next `integrate!`. `BallisticMissile`
is **modified** (the guarded `:a_ctrl` term) and **reused** (impact/energy/att) — the advisor's
recommended "modify+reuse" over a duplicating `GuidedMissile`. The loader gives a *guided* missile
`[BallisticMissile, Autopilot]` (phase-1 mover + phase-4 guidance); a *ballistic* slice-8 missile
stays `[BallisticMissile]` only. (Naming alt: the subsystem could be `Guidance`; `Autopilot` names
the slice's headline. Pick at gate 2 — the pure inner-loop fn is `autopilot_step` either way.)

**4. The lesson is the tracking gap, NOT miss distance (advisor).** Surface `a_cmd` (‖command‖),
`a_ach` (‖achieved‖), and **`track_gap = ‖a_cmd − a_ach‖`** in telemetry — the `1/(1+Kp)`
undershoot is *directly* visible there, uncontaminated by guidance geometry. Miss distance is a
gate-3 verifier *outcome* check, not the live readout headline. `|a_cmd|`-growing-toward-intercept
is the slice-10 tee-up readout.

**5. `a_max` is a GUARD, not a lesson — tune the scenario so it NEVER binds.** Keep the clamp so a
huge `Kp`/`Kd`/`K_guid` slider can't blow up a tick, but the probe already demanded ~214 m/s²
(~22 g) *and climbing* at `a_max = 300`, so pick geometry/gains where **peak demand stays well
under** the clamp (target/generous margin) — otherwise the clamp becomes a confound and silently
imports slice-10's saturation lesson. Probe the scenario at gate 3 (the slice-3..8 rule) and pin the
peak `|a_cmd|` as a comment.

**6. Stay in the spatial view (no new render mode).** Extend `_draw_spatial` (the slice-8
precedent) with the target marker, the LOS line, the intercept/impact marker, and the
`a_cmd`/`a_ach`/`track_gap` readout. The missile handshake is discriminated off `autopilot ∈
fidelity` (the `integrator`→missile precedent) but stays *spatial* — the discriminator only wires
the fidelity button to the autopilot cycler + builds the gain sliders.

**7. PID-gain sliders are inert under `:ideal` (documented, fine).** In `:ideal` the loop is
bypassed, so `Kp`/`Ki`/`Kd` have no effect — this is correct (the ideal actuator has no gains) and
called out in the UI/readout, not a bug.

**8. Named approximations (house rule — no hidden ones):** pursuit reads **target truth** (no
seeker — slice 11); **first-order lumped-scalar airframe lag** (no 6-DOF/fin dynamics — §11 Tier A);
**one-tick `decide!→integrate!` delay** (negligible at `dt = 1 ms`); the **`a_max` clamp is a
crash-guard** (saturation-as-lesson is slice 10); PID integrates at the tick `dt` (fixed-step,
matching the integrator).

## Review gates (cadence: staged, mirroring slices 5–8)

1. **Primitives green (pure, closed-form, SI, RNG-free, no `LinearAlgebra`).** A new pure
   `guidance.jl` — the outer pursuit law + the inner PID autopilot + the clamp, all pure functions,
   before any subsystem wiring. Included in `EWSim.jl` **before `radar.jl`** (so `AUTOPILOT_MODES`
   precedes `LIVE_FIDELITY_MODES` — the `INTEGRATOR_MODES`/`ESTIMATOR_MODES`
   "mode-const-before-radar, one-list-no-drift" precedent); reuses `frames.jl` (`los_unit`) +
   `world.jl` (`Vec3`), depends on nothing else; exported.
   - **Functions:** `pursuit_accel(m_pos, m_vel, t_pos; k_guid)` → `Vec3` (§1); `autopilot_step(mode,
     a_cmd, state, dt; kp, ki, kd, tau)` → `(a_ach, state′)` where `state = (a_ach, e_int, e_prev)`
     (§2 — `:ideal` returns `(a_cmd, state)` verbatim; `:pid` runs the one-step PID + first-order
     plant); `clamp_accel(a, a_max)` → `Vec3` (magnitude clamp, zero-safe). `AUTOPILOT_MODES =
     (:ideal, :pid)` the source-of-truth const lives here.
   - `test_guidance.jl` — closed-form, slice-2 style (**explicit `atol`**, never rtol-`≈0`), wired
     into `runtests.jl` after `test_frames.jl`/`test_missile.jl`:
     - **the headline `1/(1+Kp)` steady-state undershoot** — drive `autopilot_step` with a *constant*
       `a_cmd` to settle, assert `‖a_cmd − a_ach‖ / ‖a_cmd‖ → 1/(1+Kp)` under P-only (pin `Kp = 2 →
       1/3`, `Kp = 8 → 1/9` — the probe values, closed-form, NOT calibrated-to-pass); **integral
       drives it to ~0** (assert `< atol` with `Ki > 0`); **derivative reduces overshoot** (peak with
       `Kd > 0` < peak without — the ordering anchor, like slice-1's Swerling-loss ordering);
     - **`:ideal` is exact passthrough** (`a_ach == a_cmd` bit-exact, state unchanged — the perfect
       reference);
     - **pursuit geometry** — `pursuit_accel` is ⟂ to velocity (`a_cmd · v̂ == 0` to `atol`), points
       toward the LOS side (sign-checked on a concrete left/right crossing — the frames.jl LOS-sign
       discipline), and `‖a_cmd‖` **grows as range closes** on a fixed closing geometry (the
       tail-chase pin, the slice-10 tee-up as a test);
     - **`clamp_accel`** caps the magnitude, preserves direction, and is zero-safe (no NaN at
       `a = 0`);
     - **degenerate guards** — `v → 0` (apex/launch), coincident missile/target (zero LOS), huge
       gains → no throw / no NaN.
     - **Numbers probed with a throwaway harness first** (DONE — see the slice-9 probe: the
       `1/(1+Kp)` law, the ideal-vs-PID miss split, the tail-chase `|a_cmd|` growth, and dt=1e-3
       closed-loop stability are all confirmed). **Byte-identity**: `guidance.jl` touches no
       radar/detection symbol → slices 1–8 green through the include; `_sample_z` golden +
       `test_determinism` untouched. Pin it.
2. **The autopilot wired (phase 4 — the first `decide!` on the missile; the closed loop live).**
   `Autopilot <: Subsystem` in `missile.jl` (after `radar.jl`; **verify no back-dep on radar
   symbols** beyond the shared `_nearest_target` helper — factor it if needed). `decide!(a::Autopilot,
   w)` reads the missile + nearest `:target`, computes `pursuit_accel`, runs `autopilot_step`
   (dispatch on `get(w.fidelity, :autopilot, :ideal)`), clamps to `a_max`, writes `comp[:a_ctrl]`
   (Vec3) + the PID state back to `comp`. `BallisticMissile.integrate!` gains the **guarded `:a_ctrl`
   term** (§3 — gate-0-confirmed byte-identical). `LIVE_FIDELITY_MODES` (radar.jl) gains `autopilot =
   AUTOPILOT_MODES` (referencing the gate-1 const — one-list-no-drift; introduce-safe, no draw
   hazard, the subsystem actually consumes the key — the slice-8 `:integrator` precedent).
   `scenario.jl`: a *guided* `:missile` block reads `k_guid`/`kp`/`ki`/`kd`/`tau`/`a_max` (defaults at
   the consumer so a bare block / live slider can't `KeyError` a tick) and a `target:` reference (or
   the loader auto-targets the single `:target`); the guided missile gets `[BallisticMissile,
   Autopilot]` (**NOT** a second phase-1 mover); `_validate_missile` extended (a guided missile needs
   ≥1 `:target`); a *ballistic* slice-8 missile block is unchanged (`[BallisticMissile]` only).
   Telemetry (from `decide!` via `env[:telemetry]`, or `build_env!` — resolve the phase like slice 8:
   `decide!` runs post-`empty!`, so it *may* write telemetry directly; confirm against the tick
   order): `<id>.a_cmd`/`.a_ach`/`.track_gap`/`.los_range`/`.range_rate` — all `_finite`-clamped;
   the slice-8 energy keys kept.
   - `test_missile.jl` (+ the wired autopilot arms): `decide!` writes `comp[:a_ctrl]` matching
     `autopilot_step` on a realized state; **the wired closed loop INTERCEPTS** the crossing target
     under `:ideal` (miss < a few m — the probe geometry); the **`:pid` trajectory DIFFERS** from
     `:ideal` (the not-a-dead-knob — assert the two runs diverge); **P-only undershoot on the WIRE**
     (the `track_gap` telemetry settles to `1/(1+Kp)·|a_cmd|` — the closed-form on the live path);
     **integral closes the gap** (higher `Ki` → smaller settled `track_gap`); tick-1 is ballistic
     (the free byte-identity anchor); loader arms + rejects (a guided missile with no `:target`).
   - `test_determinism.jl` + a slice-9 scenario: **same-config replay bit-identical** trajectory +
     `a_ctrl` trace (`reinterpret` fingerprint — the slice-6/7/8 sharper-than-a-scalar pin);
     **introduce `:autopilot` on a NON-missile (or ballistic) world → byte-identical** (claim 1); **a
     mid-run `:ideal↔:pid` toggle CHANGES the trajectory** (claim 3 — assert the runs differ, each
     internally deterministic; the explicit *opposite* of slice-5/6/7). **No RNG** → no vacuous
     rng-lockstep assertion (the slice-8 discipline).
   - `test_server.jl`: `set_fidelity :autopilot` write/reject (the per-key table validates it — no
     server change; introduce-safe, the `:integrator`/`:ep` contract, NOT `:cfar`'s guard); the
     `Kp`/`Ki`/`Kd`/`tau`/`k_guid` **live sliders** `set_param`→tick survive (the "a live slider
     can't crash a tick" watch-item — a huge gain hits the `a_max` guard, not a throw); `warmup!`
     tolerates a radar-free guided-missile scenario (ROC batch skipped; the phase-1+4 loop warmed).
     Slices 1–8 byte-identical.
3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice9_pursuit.yaml` — a
   single interceptor pursuing a single crossing `:target`, `:ideal` autopilot default (so the
   connect-state is the clean intercept — the lesson is what the toggle/sliders REVEAL),
   `Kp`/`Ki`/`Kd`/`tau`/`k_guid` sliders, `autopilot` the fidelity button. **Numbers probed against
   the LIVE `decide!→integrate!→telemetry` wire path** (the slice-3..8 rule) + reproduced through the
   loader; **tune so `a_max` never binds** (peak `|a_cmd|` well under the clamp — pin it as a
   comment); pin the probed intercept miss / settled `track_gap` under each rung.
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode) — the target marker
     (crossing), the missile marker + trajectory trail (slice-8), a LOS line missile→target, the
     intercept/impact marker, and the **`a_cmd`/`a_ach`/`track_gap` readout** (the lesson number);
     the shared fidelity button wired to `_on_autopilot_pressed` (the `:ideal↔:pid` ring, guarded
     disconnect like cfar/ep/est/deint/raim/integrator); the gain sliders. `_update_readout` renders
     the accel scalars (all scalars — no Array telemetry; re-confirm no `float()`-crash). The
     slice-1..8 views UNTOUCHED (re-run every smoke-load + UI test — all pass).
   - `net/slice9_verify.gd` (drives the real server): under `:ideal` the `track_gap ≈ 0` and the
     interceptor closes (`los_range → small`); `set_fidelity autopilot :pid` **opens the gap** (the
     settled `track_gap` jumps to `≈ 1/(1+Kp)·|a_cmd|`, `t` bit-identical under the held config); the
     **`Kp` slider** shrinks the P-only gap, the **`Ki` slider** drives it toward 0 (the closed-form
     on the wire — the not-a-dead-knob levers); `|a_cmd|` **grows toward intercept** (the tail-chase
     readout). Assertions on the SCALARS. `S9V OK`, exit 0. **Verifier mechanics**: step counts are
     MULTIPLES of `emit_every` so the last emit lands on the target `t` (the slice-2/6/7/8 drain
     contract).
   - `net/slice9_ui_test.gd` (mock client, no server: a missile/autopilot handshake wires the
     `autopilot` cycler; the ring walks `:ideal→:pid` and wraps; badge/button track; the gain sliders
     send `set_param`; reset resyncs the rung + sliders — `S9UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-9 server (server `DONE` ⇒ scene connected
     on the missile branch, no GDScript errors — catches parse bugs the SimClient verifier can't).
   - `test_scenario.jl` + a slice-9 loader testset (parses; `:ideal` autopilot default; NO
     radar/jammer/DF/ESM/GPS fidelity; the guided `:missile` gets `[BallisticMissile, Autopilot]` and
     **NOT** `ConstantVelocity` [the double-integration guard], with a `:target` present; the gains
     stored at the right comp keys [the slider→consumed-key discipline — the slice-5 σθ-key lesson];
     `autopilot` not a knob, the gains ARE knobs; `:guidance` fidelity ABSENT [reserved for slice 10]).
   - The **`_draw` missile PIXEL branch** (Godot skips `_draw` headless) **visually confirmed** via
     the windowed shot harness (the slice-3..8 technique, [[ewsim-godot-headless]]): `:ideal` = the
     clean pursuit-to-intercept + `track_gap ≈ 0` readout; `:pid`(P-only, low Kp) = the visible gap +
     degraded/curved endgame; the LOS line + intercept marker. **(stretch, deferred)**
     `clients/notebooks/slice9_autopilot.jl` Pluto — the commanded-vs-achieved accel step response
     (the `1/(1+Kp)` undershoot and the I/D effects as *curves*), and/or an offline `batch.jl`
     miss-distance-vs-`τ`/gain sweep.

## Task checklist
- [ ] **0. Probe + architecture pin (DONE).** Standalone closed-loop probe (`M:\claud_projects\temp\
      slice9_probe\probe.jl`) confirmed: dt=1e-3 pursuit intercept is stable; `autopilot` ideal-vs-PID
      is a strong not-a-dead-knob (miss 4.7 vs 228 m); the `1/(1+Kp)` steady-state law + I-drives-to-0;
      the tail-chase `|a_cmd|` growth (21→214). The **guarded `:a_ctrl` seam ran 1633/1633 green** then
      reverted. Advisor-endorsed (cascade required by slice 10; lesson = tracking gap; `a_max` a guard).
- [ ] **1. Primitives** — `guidance.jl` (`pursuit_accel` / `autopilot_step` / `clamp_accel` /
      `AUTOPILOT_MODES`) + `test_guidance.jl` (the `1/(1+Kp)` headline, ideal passthrough, pursuit
      geometry + tail-chase, guards). Byte-identity slices 1–8. GATE 1.
- [ ] **2. Autopilot wired** — `Autopilot <: Subsystem` (`decide!`) + the guarded `BallisticMissile`
      `:a_ctrl` seam + `LIVE_FIDELITY_MODES += autopilot` + loader (guided missile + target) +
      telemetry + `test_missile.jl`/`test_determinism.jl`/`test_server.jl` arms. Byte-identity slices
      1–8. GATE 2.
- [ ] **3. Scenario + Godot + verifiers** — `slice9_pursuit.yaml` (a_max never binds) + `_draw_spatial`
      extension + fidelity/slider UI + `slice9_verify.gd` + `slice9_ui_test.gd` + smoke-load +
      `test_scenario.jl` arm + visual confirm. GATE 3 → slice COMPLETE.

## Context / landmarks
- **Slice-8 airframe** (`core/src/missile.jl`, `dynamics.jl`): `BallisticMissile.integrate!`
  (`missile.jl:81`) is the seam to modify (§3); `total_accel`/`integrator_step` (`dynamics.jl`) are
  reused unchanged; energy/impact/att logic reused verbatim.
- **`frames.jl`** (`core/src/frames.jl`): `los_unit`/`los_range`/`range_rate`/`los_rate` — the pursuit
  law + telemetry ride these (built + sign-tested in slice 8 for exactly this).
- **Fidelity plumbing precedent**: slice-8 `:integrator` (`LIVE_FIDELITY_MODES`, radar.jl;
  `set_fidelity` per-key table, server.jl) — `:autopilot` mirrors it (introduce-safe, physics-changing).
- **Phase-4 precedent**: slice-5 `Geolocator.decide!` (`geolocation.jl`) — the DF pair lit phase 4;
  the Autopilot is the missile's first `decide!`.
- **`_nearest_target`** (radar.jl) — reuse for the missile's target lock (single target in slice 9).
- **Scenario loader** (`scenario.jl`): the `:missile` arm (slice 8) extends to the guided case;
  `:target` is the slice-1 kind.
- **HANDOFF** §10 item 9 (this slice), item 10 (slice 10 — the constraint), §3 (the four-phase tick),
  §9 (frames reuse), §1 (named approximations; **LOS-sign trifecta**), §12 (fidelity badge).

## Watch-items (gotchas to bake in)
- **Don't copy the slice-5/6/7 "toggle-bit-identical" language** — `:autopilot` is *physics-changing*
  (no RNG; a toggle changes the trajectory). Use the slice-8 three-claims framing (introduce-safe /
  replay-bit-identical / not-a-dead-knob). (Advisor, slice-8 #1.)
- **Byte-identity via the `haskey` guard, NOT `+ zero(Vec3)`** (`-0.0 + 0.0 → +0.0` flips a bit).
  Confirmed green in gate 0; keep the guard.
- **`:a_ctrl` is a `Vec3`** (SVector) — a plain `Vector` breaks the bit-exact add.
- **The lesson is `track_gap`, not miss distance** (miss conflates guidance + autopilot). Telemetry
  headline = commanded-vs-achieved accel. (Advisor.)
- **`a_max` must NOT bind in the scenario** — the probe hit ~22 g *and climbing*; leave margin or the
  clamp silently imports slice-10's saturation lesson. Probe + pin peak `|a_cmd|`. (Advisor.)
- **PID-gain sliders are inert under `:ideal`** — document it (not a bug).
- **Reserve `:guidance` for slice 10** (pursuit vs PN) — own only `:autopilot` now; factor
  `pursuit_accel` / `autopilot_step` separately so slice 10 swaps only the outer fn.
- **One-tick `decide!→integrate!` delay** — tick 1 is ballistic (a *free* byte-identity anchor); the
  1 ms control lag is negligible but named.
- **Telemetry phase** — confirm whether `decide!` (post-`empty!`) may write `env[:telemetry]` directly
  or (like slice-8's energy) it belongs in `build_env!`; resolve against the actual tick order, don't
  assume the plan sketch.
- **Verifier drain multiples** of `emit_every` (the slice-2/6/7/8 timeout trap).
- **Stay spatial** — extend `_draw_spatial`, no new render mode (the slice-8 precedent).
