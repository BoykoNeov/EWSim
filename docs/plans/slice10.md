# Slice 10 — Missile: proportional navigation + g-limit saturation-as-lesson

The **third and final slice of the missile-guidance arc** (HANDOFF **§10** item 10) and the one the
whole arc was built toward. Slice 8 gave the airframe a passive force-integrator + the 3-D
`frames.jl` LOS kernel; slice 9 put the **inner** loop on it (a PID **autopilot** turning a
*commanded* lateral accel into an *achieved* one) under a **placeholder outer pursuit law** — an
honest *tail-chaser* that points **at** the target and never **leads** it, so its commanded accel
**grows toward intercept** (`|a_cmd|` climbed 21 → 214 m/s² in the slice-9 probe). Slice 10 replaces
that placeholder with the real **outer** law: **proportional navigation (PN)**, which drives the
**LOS rate to zero** (leads the target onto a collision triangle), and makes **g-limit saturation**
the teachable moment — *"this is why augmented PN matters"* (HANDOFF §10 item 10). Source of truth:
HANDOFF §10 item 10 — *"Missile — proportional navigation — outer guidance loop; g-limit saturation
modeled (this is why augmented PN matters); small-step/analytic endgame to avoid the LOS-rate→∞
blow-up as range→0."*

**The cascade seam was built FOR this slice and is already in place** (slice-9 Decisions §1, advisor-
required): `pursuit_accel` and `autopilot_step` are **separate pure functions** in `guidance.jl`
precisely so slice 10 swaps **only the outer command** (`pursuit_accel → pn_accel`) without touching
the inner PID; the `:guidance` fidelity key is **reserved and unused** (guidance.jl:17) waiting for
exactly this. `frames.jl` shipped **`los_rate`** (the ω vector `r×v/r²`) and **`range_rate`** fully
3-D and **sign-tested in slice 8** with a comment that names the purpose: *"the ω proportional
navigation multiplies by closing speed"* (frames.jl:193). So slice 10 is a **small, seam-clean**
slice: one new pure function, one reserved fidelity key filled in, a ~3-line branch in
`Autopilot.decide!`, and — the real design work — **two showcase scenarios that invert slice 9's
`a_max` discipline**.

## The two lessons (both shown as numbers)

**Lesson 1 — PN beats pursuit (leads vs tail-chases).** Pure-pursuit points *at* the target; PN
turns to null the **line-of-sight rotation rate** `λ̇`, which puts the missile on a **constant-bearing,
decreasing-range** collision triangle. Two visible consequences against a **crossing** target:
- **Miss distance collapses.** PN intercepts a crossing target with a far smaller miss than pursuit
  (pursuit's tail-chase bleeds energy turning in the endgame). **Miss distance is now an HONEST
  headline** — the slice-9 constraint ("miss conflates guidance + autopilot, use `track_gap`
  instead") is **lifted** because slice 10 runs `autopilot = :ideal`, so miss isolates the
  *guidance law* with no PID contamination. (The arc's readout progression: slice 8 = energy, slice
  9 = `track_gap`, slice 10 = **miss distance**, each honest once its confound is pinned out.)
- **The commanded accel does NOT grow toward intercept.** For a non-maneuvering target on a
  collision course PN drives `λ̇ → 0`, so `|a_cmd|` **falls toward a small bounded floor** as the
  triangle is established — the **opposite** of the slice-9 pursuit tail-chase (21 → 214). **Gate-0
  correction (advisor #1, mechanism TESTED not asserted):** the floor is `~2g ≈ 18–20 m/s²`, NOT 0.
  The g-symmetric probe (rerun with gravity removed) confirms it — g-off, `|a_cmd|` collapses to ~0
  (textbook); g-on it floors at ~2g. The floor is the **`N/(N-2)·g_perp` PN-lag signature** (N=4 →
  ×2): the gravity-free CV target vs the gravity-carrying missile makes gravity act as an *unmodeled
  target acceleration*, and plain PN lags it by exactly the augmented-PN term — a **literal
  in-scenario preview of the slice-11 APN tee-up**, not a bug. Probed: PN `|a_cmd|` falls ×0.21–0.27
  (20→70 % of the intercept) toward the ~2g floor while pursuit climbs ×1.9–4.4. Surface both `a_cmd`
  profiles side-by-side (the fidelity toggle) and the climbing-vs-falling-toward-a-floor demand **is**
  the lesson, as a curve and a number.

**Lesson 2 — g-limit saturation (this INVERTS slice 9's `a_max` discipline).** Slice 9's headline
watch-item was *"`a_max` must NOT bind — tune the scenario so it never binds"* (a pure crash-guard;
a binding clamp would *"silently import slice-10's saturation lesson"*). **Slice 10 is where that
lesson arrives:** `a_max` **binds on purpose** and that is the point. With a large initial
heading-error / high-crossing geometry, PN's peak lateral demand **exceeds the airframe g-limit** →
the `clamp_accel` guard **binds** → the missile **cannot turn hard enough** → the miss **grows**.
Drag the **`a_max` slider up** and watch the miss shrink as the airframe out-muscles the demand;
drag it **down** and watch saturation open the miss. The headline numbers: **miss(a_max)** and the
**saturation fraction** (share of guided ticks where the pre-clamp demand `a_demand > a_max`).

**The tee-up for slice 11+ (augmented PN), shown honestly:** plain PN is optimal against a
*non-maneuvering* target; against a **maneuvering** target (or in the deep endgame as `r→0` and `λ̇`
spikes) its demand saturates and it misses — which is **why augmented PN matters** (APN adds a
`N/2·a_T` target-acceleration feedforward). Slice 10 **models the saturation** (the HANDOFF verb)
and **names APN + the maneuvering target as the next-slice motivation** — the exact structural
parallel to how slice 9 named PN as *its* tee-up. Slice 10 implements **PN, not APN**, and uses a
**constant-velocity target** (saturation is forced by geometry, not target accel), so the slice
stays one-lesson-per-scenario and adds no new mover.

## Scope (one lesson per scenario — the slice-3/4 principle)

A single guided **interceptor** (the slice-8 `BallisticMissile` airframe + slice-9 `Autopilot`)
against a single **constant-velocity target** in a **crossing engagement**, jamming/seeker-noise-
free (guidance reads **target truth** — noisy seekers are slice 11). The switchable **fidelity is
`guidance ∈ (:pursuit, :pn)`** (a *physics-changing* knob — the slice-2/8/9 shape, **not** a
slice-5/6/7 toggle-bit-identical rung; **no RNG** in the missile arc). `autopilot` is held at
`:ideal` in the slice-10 scenarios so the guidance-law lesson is uncontaminated by the PID (the
slice-9 lesson is isolated the same way, in reverse). Two scenarios (the slice-4 split, so the
shared client fidelity button toggles exactly **one** lesson):
- **`slice10_pn.yaml`** — Lesson 1. A crossing target where **PN cleanly intercepts** and **pursuit
  degrades/misses**; `a_max` **generous** (never binds — Lesson 2 is held out). Headline: miss
  distance (pursuit ≫ PN) + the `|a_cmd|` climbs-vs-vanishes contrast.
- **`slice10_glimit.yaml`** — Lesson 2. A hotter geometry (large heading error / faster crossing)
  under **`:pn`**, `a_max` **tuned so the peak demand exceeds it** → saturation → a visible miss the
  **`a_max` slider** closes. Headline: miss(a_max) + saturation fraction.

Explicitly **deferred** (the tee-ups): **augmented PN** (the `N/2·a_T` feedforward) and a
**maneuvering-target** model (slice 11+); **noisy seekers / LOS-rate filtering** (slice 11 — PN here
reads truth-fed ω); **6-DOF / fin-actuator dynamics** (§11 Tier A — the airframe lag stays the
slice-9 lumped scalar); **thrust / boost** (the interceptor coasts, slice 8's passive body). The
subsystem is **NOT renamed** — `Autopilot` still owns `decide!`; slice 10 only changes **which outer
`a_cmd` function it calls**, exactly as the cascade seam intended. 3 review gates (mirroring slices
5–9: pure primitive → subsystem wired → scenarios + client + verifiers).

**Done =** start the server on `slice10_pn.yaml`, connect Godot, watch (in the **existing spatial /
elevation view**) the interceptor under `:pn` **lead** the crossing target to a tight intercept, its
`|a_cmd|` **falling toward a small ~2g floor** (gate-0 tested: ~18–20 m/s², not 0 — the `N/(N-2)`
PN-lag against gravity-as-unmodeled-target-accel) midcourse and the LOS line **holding a constant bearing**
(the collision triangle). Cycle the fidelity button to `:pursuit` and watch it **tail-chase** — the
LOS bearing **swinging**, `|a_cmd|` **climbing**, a **larger miss**. Then load `slice10_glimit.yaml`,
watch `:pn` **saturate** (the `a_demand` readout **pinned at `a_max`**, the `saturated` flag lit, a
visible miss); drag the **`a_max` slider up** and watch the miss close. With `runtests.jl` green on
the extended `test_guidance.jl` (the PN closed-form arms) + `test_missile.jl` (the wired-PN arms) and
slices 1–9 **byte-identical** (the `guidance = GUIDANCE_MODES` default `:pursuit` keeps every
slice-9 trajectory bit-for-bit; guidance.jl/missile.jl touch no radar/detection RNG path; the
`_sample_z` golden + `test_determinism` untouched).

## The physics / math (named approximations — HANDOFF §1)

### 1. The PN outer law (`pn_accel`, `guidance.jl`, pure; RNG-free) — the sibling of `pursuit_accel`

**True proportional navigation (TPN):** command a lateral acceleration proportional to the LOS
rotation rate `ω` and the closing speed `Vc`, perpendicular to the LOS:

    r   = t_pos − m_pos                              (relative position, target − missile)
    v   = t_vel − m_vel                              (relative velocity)
    û   = los_unit(m_pos, t_pos)                     (frames.jl)
    ω   = los_rate(r, v)   =  (r × v) / ‖r‖²         (frames.jl — the SLICE-8 kernel, sign-tested)
    Vc  = −range_rate(r, v)                          (closing speed; POSITIVE when closing — the
                                                      frames.jl sign is "negative = closing")
    a_cmd = N · Vc · (ω × û)                          (m/s², ⟂ to LOS; N ≈ 3–5, dimensionless)

Because `ω = r×v/‖r‖²` is perpendicular to `r̂ = û` (a cross product with `r`), `ω × û` has magnitude
`‖ω‖` and lies **perpendicular to the LOS** — the accel that rotates the velocity to **null `λ̇`**.
The **defining PN property, the test anchor:** on a **constant-bearing, decreasing-range**
(collision-course) geometry `ω = 0 → a_cmd = 0` (the sailor's rule — steady bearing means collision;
no correction needed). On a **crossing** geometry `ω ≠ 0` and the command turns the missile to lead.
`N` is the **navigation constant** (a new gain; 3–5 typical). **SIGN is the trifecta** (HANDOFF §1):
`los_rate`'s sign is already pinned in `test_frames.jl`; `pn_accel` must be pinned to turn the
missile **toward the lead** (reduce `λ̇`) on a concrete left→right crossing — a flipped sign is the
#1 "my missile flies away" bug. Guards (no NaN, HANDOFF §1): `v→0` / coincident / zero-range all fall
out of the frames.jl zero-guards → zero command.

**Named as PN, honestly.** It **leads** the target (nulls `λ̇`) — the collision-triangle law pursuit
only approximated. Against a **non-maneuvering** target it is optimal (`a_cmd → 0` at intercept);
against a **maneuvering** target it lags by a target-accel term (→ augmented PN, slice 11+). It reads
**target truth** (ω from truth positions/velocities, no seeker — slice 11). The **`a_max` clamp now
BINDS on purpose** in `slice10_glimit.yaml` — g-limit-saturation is the lesson, the deliberate
inversion of slice 9's crash-guard-only clamp.

### 2. The endgame `r→0` guard (HANDOFF §10 item 10 — "avoid the LOS-rate→∞ blow-up as range→0")

`ω = r×v/‖r‖²` **blows up as `r→0`** whenever there is any residual miss (a non-exact collision
course) — the named numerical hazard. The `frames.jl` zero-range guard (`_FRAME_EPS = 1e-12`) is FAR
too small to catch this (at `r ≈ 1 m` the demand is already enormous). Three layers, all named:
- **Terminal cutoff (guidance-level):** below a small **`r_stop`** range (author-set, ~a few missile
  body-lengths) the outer law **freezes / zeroes the command** and the missile **coasts through** the
  endgame — the "small-step/analytic endgame" HANDOFF calls for, implemented as a coast-through cutoff
  (the interceptor's fins can't act faster than the tick anyway). CPA/impact detection (slice-8
  `:impacted`) ends the engagement.
- **The `a_max` clamp** bounds any command the cutoff doesn't catch (the crash-guard role it keeps
  even in the glimit scenario — a diverged demand can't blow up a tick).
- **`_finite` on telemetry** — the pre-clamp `a_demand` readout near `r→0` can be huge; `_finite`
  clamps it to `FINITE_CEIL = 1e9` (no `±Inf`/NaN to JSON — the slice-1 `%g` bug class).

The **miss distance** is measured at **CPA** (closest point of approach — the min `los_range` over
the run), not at a fixed `t`, so the endgame cutoff doesn't corrupt it.

### 3. The seam into `Autopilot.decide!` (`missile.jl`) — a ~3-line branch, inner loop UNTOUCHED

`decide!` currently computes `a_cmd = clamp_accel(pursuit_accel(...), a_max)` (missile.jl:225). Slice
10 selects the outer law on the reserved key and passes the same clamped `a_cmd` into the **unchanged**
inner PID:

    outer  = get(w.fidelity, :guidance, :pursuit)                       # DEFAULT :pursuit (slice-9)
    a_dem  = outer === :pn ? pn_accel(e.pos, e.vel, tgt.pos, tgt.vel; N = n_pn)
                           : pursuit_accel(e.pos, e.vel, tgt.pos; k_guid = k_guid)
    a_dem  = _terminal_cutoff(a_dem, los_range(e.pos, tgt.pos), r_stop)  # §2 endgame guard
    a_cmd  = clamp_accel(a_dem, a_max)                                   # §1 (BINDS in glimit)
    # ... autopilot_step(...) UNCHANGED — the inner loop never sees which outer law fed it.

The default `:pursuit` is the **byte-identity anchor**: every slice-9 scenario (which sets no
`:guidance`) takes the **exact slice-9 code path** → bit-for-bit identical. `pn_accel` reads the
**target velocity** (`tgt.vel`) — `pursuit_accel` did not; the loader/`decide!` already have `tgt`
(the nearest `:target`), so no new plumbing. New telemetry (published from `decide!`, phase 4,
post-`empty!` — the slice-9 resolution): `<id>.a_demand` (**pre-clamp** magnitude, so saturation is
visible), `<id>.a_cmd` (post-clamp, existing), `<id>.los_rate` (`‖ω‖`), `<id>.closing_speed`
(`Vc`), `<id>.saturated` (0/1 — `a_demand > a_max`) — all `_finite`-clamped; the slice-9 keys kept.

### 4. Fidelity: `guidance ∈ (:pursuit, :pn)` — physics-changing, the three-claims framing (NOT toggle-invariant)

Copy the slice-8/9 discipline, **not** the slice-5/6/7 template. **No RNG in the missile arc**, so
"RNG lockstep / draw-count-invariance" is **vacuous** (the false-claim trap — convention 4c). Three
distinct, honest claims: (1) **introduce-safe** — absent any consumer nothing reads `:guidance`, and
`get(w.fidelity, :guidance, :pursuit)` defaults to the slice-9 law, so introducing the key on any
slice-1..9 scenario is a **no-op → byte-identical**; (2) **same-config replay is bit-identical**
(deterministic, trivially — no RNG to desync); (3) a mid-run `:pursuit↔:pn` toggle **CHANGES the
trajectory** (the not-a-dead-knob property — the *opposite* of slices 5/6/7). `GUIDANCE_MODES =
(:pursuit, :pn)` is the **single source of truth** (defined in `guidance.jl`, referenced by
`LIVE_FIDELITY_MODES` — one-list-no-drift), and `:guidance` becomes a valid `set_fidelity` key
automatically (the per-key table reads `LIVE_FIDELITY_MODES`; `_KNOWN_FIDELITY_KEYS =
keys(LIVE_FIDELITY_MODES)` in scenario.jl picks it up — no server change). `:autopilot` and
`:guidance` are **orthogonal** knobs (inner vs outer); slice-10 scenarios pin `:autopilot = :ideal`
so only **one** toggles.

## Decisions to take at gate 2/3 (surface to advisor before implementing)

**1. PN vector form.** TPN `a = N·Vc·(ω × û)` (above) reuses `los_rate` + `range_rate` directly and
zeroes on a collision course — the cleanest form and the best test anchor. Alternative "pure PN"
references missile speed (`N·Vm·ω×v̂`); pick TPN unless the probe shows a reason. **N** is a new live
slider/knob (`:n_pn`, default ~4).

**2. Saturation without a maneuvering target — CONFIRM the geometry actually saturates PN.** PN
against a *non-maneuvering* target on an interceptable course drives `a_cmd → 0` (no endgame
saturation). Saturation must be forced by a **large initial heading error / fast crossing** (the
missile pulls hard **early**, or `λ̇` spikes near a **residual-miss endgame**). **Probe first** (the
slice-3..9 rule): confirm `slice10_glimit.yaml`'s peak `a_demand` genuinely exceeds a chosen `a_max`
under `:pn`, and that raising `a_max` genuinely shrinks the miss — otherwise the "saturation" is an
artifact, not the lesson. Pin the peak `a_demand` per rung as a comment.

**3. Two scenarios vs one.** Proposed: **two** (slice-4 precedent), so each fidelity-button toggle is
one clean lesson. If the probe shows one geometry can carry both legibly, collapse — but default to
two.

**4. Endgame cutoff vs analytic endgame.** HANDOFF offers "small-step **OR** analytic endgame."
Proposed: the simple **coast-through terminal cutoff** (`r_stop`) + CPA-based miss — no sub-stepping
(the fixed `dt=1e-3` matches the integrator; a sub-step endgame is gold-plating this slice doesn't
need). Revisit only if the probe shows the cutoff visibly corrupts the miss.

**5. Miss measured at CPA, not fixed-`t`.** The endgame cutoff + the crossing geometry mean a
fixed-`t` sample can miss the closest approach. Track **min `los_range`** over the run (the verifier
+ telemetry) as the miss.

**6. `autopilot = :ideal` in slice-10 scenarios.** Isolate the guidance-law lesson (miss = the law,
not the PID). The PID stays fully available (orthogonal knob) but is not the slice-10 story.

## Review gates (cadence: staged, mirroring slices 5–9)

1. **Primitive green (pure, closed-form, SI, RNG-free, no `LinearAlgebra`).** Extend `guidance.jl`:
   - **`pn_accel(m_pos, m_vel, t_pos, t_vel; N = 4.0)` → `Vec3`** (§1) — reuses `los_unit` /
     `los_rate` / `range_rate` / `_cross` / `_norm3` (all already in frames.jl, included before
     guidance.jl). Zero-guarded (v→0 / coincident / zero-range → zero). **`GUIDANCE_MODES =
     (:pursuit, :pn)`** the source-of-truth const, defined here (guidance.jl precedes radar.jl — the
     `AUTOPILOT_MODES` precedent). Optionally a small `_terminal_cutoff(a, r, r_stop)` helper (§2) —
     or inline it in `decide!` at gate 2 (decide at gate 2). `pursuit_accel`/`autopilot_step`
     **UNCHANGED** (the seam pays off — the inner loop is untouched).
   - `test_guidance.jl` (+ PN arms, explicit `atol`, never rtol-`≈0`, closed-form):
     - **the defining PN anchor** — on a **constant-bearing decreasing-range** collision geometry
       `pn_accel ≈ 0` (assert `< atol` — the sailor's-rule external anchor, not a self-calibrated
       round-trip);
     - **crossing geometry** — `pn_accel` is ⟂ to the LOS (`a_cmd · û == 0` to `atol`), magnitude
       `== N·Vc·‖ω‖` (independent recompute — a *different* expression than the impl, catches a
       transpose), and turns toward the **lead** (SIGN pinned on a concrete left→right crossing — the
       frames.jl LOS-sign discipline extended to PN);
     - **PN vs pursuit contrast** — on a fixed crossing, `pn_accel` magnitude **falls** as the
       geometry approaches collision while `pursuit_accel` **grows** (the Lesson-1 tee-up as a test —
       the slice-9 tail-chase pin, now with its PN foil);
     - **`N` scaling** — `pn_accel` magnitude is linear in `N` (the gain does what it says);
     - **degenerate guards** — `v→0`, coincident, zero closing speed (tail-chase `Vc=0`), huge `N`
       → no throw / no NaN; and the **endgame `r→0`** demand is finite-after-cutoff/clamp (pin it).
     - **Numbers probed with a throwaway harness FIRST** (the slice-3..9 rule — a standalone PN-vs-
       pursuit closed-loop probe in `M:\claud_projects\temp\slice10_probe\`): confirm PN intercepts
       the crossing target with a small miss and pursuit misses larger; confirm the `slice10_glimit`
       geometry saturates PN (peak `a_demand > a_max`) and that raising `a_max` shrinks the miss;
       confirm the `r→0` endgame is stable under the cutoff at `dt=1e-3`. **Byte-identity**:
       `guidance.jl` touches no radar/detection symbol → slices 1–9 green through the include;
       `_sample_z` golden + `test_determinism` untouched. Pin it.
2. **PN wired into the outer loop (the reserved `:guidance` key filled in).** `Autopilot.decide!`
   (missile.jl) gains the **§3 branch** (`get(w.fidelity, :guidance, :pursuit)` → `pn_accel` vs
   `pursuit_accel`) + the terminal cutoff + the new telemetry (`a_demand`/`los_rate`/`closing_speed`/
   `saturated`); the **inner PID path is UNCHANGED**. `LIVE_FIDELITY_MODES` (radar.jl) gains
   `guidance = GUIDANCE_MODES` (referencing the gate-1 const — one-list-no-drift; introduce-safe,
   default `:pursuit`, physics-changing — the `:autopilot` shape, NOT `:cfar`'s guard).
   `scenario.jl`: the `guidance:` sub-block reads **`n`** (PN gain) + **`r_stop`** (endgame cutoff)
   alongside the slice-9 gains (defaults at the consumer so a bare block / live slider can't
   `KeyError` a tick; `n>0`, `r_stop≥0` validated at LOAD). The guided-missile arming is unchanged
   (`[BallisticMissile, Autopilot]`).
   - `test_missile.jl` (+ PN arms): `decide!` under `:pn` writes `comp[:a_ctrl]` matching `pn_accel`
     on a realized state; **the wired PN loop INTERCEPTS** the crossing target with a **smaller miss
     than `:pursuit`** (the Lesson-1 pin, autopilot `:ideal`); **the `:pursuit↔:pn` trajectories
     DIFFER** (the not-a-dead-knob — assert divergence); **`a_demand` saturation on the wire** (in a
     hot-geometry testset the settled `a_demand > a_max` and `saturated == 1`, and a **larger `a_max`
     → smaller miss** — the Lesson-2 pin on the live path); **`|a_cmd|` falls toward CPA under `:pn`**
     vs **grows under `:pursuit`** (the contrast, on the wire); tick-1 ballistic anchor kept; loader
     arms + rejects (bad `n`/`r_stop`).
   - `test_determinism.jl` (+ the THREE claims for `:guidance`): **same-config replay bit-identical**
     (pos/vel/`a_ctrl` `reinterpret` fingerprint); **introduce `:guidance` on a slice-1..9 world →
     byte-identical** (default `:pursuit` — claim 1, the additivity master-check); **mid-run
     `:pursuit→:pn` toggle CHANGES the trajectory** (claim 3 — the explicit *opposite* of
     slice-5/6/7). **No RNG** → no vacuous rng-lockstep assertion. **Critically: an existing slice-9
     scenario replays BIT-IDENTICAL after the missile.jl edit** (the default-`:pursuit` path is the
     unchanged slice-9 code — the "slices are additive" teeth).
   - `test_server.jl`: `set_fidelity :guidance` write/reject/introduce-safe (the per-key table
     validates it — no server change; the `:autopilot`/`:integrator` contract, NOT `:cfar`'s guard);
     the **`n`/`r_stop`/`a_max` live sliders** `set_param`→tick survive (a huge `N` hits the `a_max`
     guard, not a throw — the "a live slider can't crash a tick" watch-item, now including the
     **deliberately-binding** `a_max`). Slices 1–9 byte-identical.
3. **Scenarios + Godot spatial-view extension + verifiers.** `scenarios/slice10_pn.yaml` (Lesson 1:
   `:pn` default, generous `a_max`, crossing target — PN clean, pursuit degrades) and
   `scenarios/slice10_glimit.yaml` (Lesson 2: `:pn`, hot geometry, `a_max` **tuned to bind**).
   **Numbers probed against the live `decide!→integrate!→telemetry` wire path** (the slice-3..9 rule)
   + reproduced through the loader; **pin the peak `a_demand` per rung + the miss(a_max) sweep** as
   comments. `slice10_pn`: pin miss(`:pn`) ≪ miss(`:pursuit`); `slice10_glimit`: pin
   miss(low `a_max`) ≫ miss(high `a_max`) and the saturation fraction.
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode — the slice-8/9
     precedent) — the LOS line (already drawn slice-9) now the **constant-bearing tell** (holds fixed
     under `:pn`, swings under `:pursuit`), the target marker + crossing, the intercept/CPA marker,
     and the **`a_demand`/`a_cmd`/`saturated` readout** (the lesson numbers — all scalars, no Array
     telemetry, re-confirm no `float()`-crash). The fidelity button cycles `:pursuit↔:pn`
     (`_on_guidance_pressed`, guarded disconnect like the slice-9 autopilot cycler); the `n`/`a_max`
     sliders. **`:autopilot` stays fixed** (scenario sets `:ideal`; the button toggles `:guidance`).
     The slice-1..9 views UNTOUCHED (re-run every smoke-load + UI test).
   - `net/slice10_verify.gd` (drives the real server): on `slice10_pn`, `:pn` **intercepts** (min
     `los_range` small) with `|a_cmd|` **falling** toward CPA; `set_fidelity guidance :pursuit`
     **degrades** it (larger min-range, `|a_cmd|` **climbing**), `t` bit-identical under the held
     config; on `slice10_glimit`, `:pn` **saturates** (`saturated == 1`, `a_demand` pinned near
     `a_max`) and the **`a_max` slider** shrinks the miss (the not-a-dead-knob lever, the Lesson-2
     closed-form on the wire). Assertions on the SCALARS. `S10V OK`, exit 0. **Step counts are
     MULTIPLES of `emit_every`** (the slice-2/6/7/8/9 drain contract).
   - `net/slice10_ui_test.gd` (mock client, no server): a missile/guidance handshake wires the
     **`guidance`** cycler; the ring walks `:pursuit→:pn` and wraps; badge/button track; the `n`/
     `a_max` sliders send `set_param`; reset resyncs the rung + sliders (`S10UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against BOTH slice-10 servers (server `DONE` ⇒ scene
     connected on the missile branch, no GDScript errors — catches parse bugs).
   - `test_scenario.jl` + slice-10 loader testsets (both scenarios parse; `:pn` default; `:autopilot`
     `:ideal`; the guided `:missile` gets `[BallisticMissile, Autopilot]` and **NOT**
     `ConstantVelocity`; `n`/`r_stop` at the consumed comp keys [the slider→consumed-key discipline];
     `n`/`a_max` ARE knobs, `guidance` is NOT a knob; `:guidance` fidelity now **PRESENT** [the
     reserved key, filled]).
   - The **`_draw` missile PIXEL branch** (Godot skips `_draw` headless) **visually confirmed** via
     the windowed shot harness ([[ewsim-godot-headless]]): `:pn` = the constant-bearing LOS line +
     tight intercept + `a_cmd` **falling**; `:pursuit` = the swinging LOS + tail-chase +
     `a_cmd` **climbing**; the glimit shot = `a_demand` pinned at `a_max` + the `saturated` readout +
     the visible miss. **(stretch, deferred)** `clients/notebooks/slice10_pn.jl` Pluto — the
     PN-vs-pursuit `λ̇`/`|a_cmd|` curves + a **miss-vs-`a_max`** saturation sweep (the g-limit lesson
     as a curve); and/or an offline `batch.jl` miss-vs-`N`/`a_max` grid.

## Task checklist
- [x] **0. Probe + scope pin — DONE.** Standalone PN-vs-pursuit closed-loop probe
      (`M:\claud_projects\temp\slice10_probe\` — `probe.jl`/`probe2.jl`/`probe3.jl` + `FINDINGS.md`;
      reuses the REAL core physics via `using EWSim`, hand-rolls only `pn_accel` + the
      decide!→integrate! loop). All four confirmed + all six scope decisions advisor-confirmed. See
      **Gate-0 probe results (pinned)** below. **The one plan-wording fix the probe forced: Lesson 1's
      `|a_cmd|` does NOT go to 0 — it falls to a ~2g floor (gravity-as-unmodeled-target-accel, the
      `N/(N-2)` PN-lag signature; mechanism TESTED via the g-symmetric `probe4.jl`, advisor #1).**
- [x] **1. Primitive — DONE (1748 green).** `pn_accel(m_pos,m_vel,t_pos,t_vel;N=4)` + `GUIDANCE_MODES
      =(:pursuit,:pn)` in guidance.jl (`pursuit_accel`/`autopilot_step` UNCHANGED — the seam); exported.
      `test_guidance.jl` PN arms: collision-course-zero anchor (PN=0 vs pursuit=900 — the static
      Lesson-1 contrast), crossing ⟂-LOS + concrete-vector recompute `(0,N·vm·vy/D,0)` + SIGN on ±y
      crossing (BOTH sign sources — Vc-sign & cross-order), `N`-linearity, degenerate guards + endgame
      r→0 finite-then-clamped. Byte-identity slices 1–9 (golden + determinism green through the include).
      **Advisor gate-1 catches baked in:** two independent sign sources; magnitude identity is
      structurally weak (pin the concrete vector, not `N·Vc·‖ω‖`); r_stop cutoff is gate-2 not gate-1.
- [x] **2. Wired — DONE (1783 green).** The `:guidance` branch (default `:pursuit`) + `_terminal_cutoff`
      (r_stop, **default 0 = exact no-op → slice-9 byte-identical**) + new telemetry
      (`a_demand`/`saturated`/`los_rate`/`closing_speed`) in `Autopilot.decide!` (inner PID UNTOUCHED);
      `LIVE_FIDELITY_MODES += guidance = GUIDANCE_MODES` (one-list-no-drift → `set_fidelity`/loader
      pick it up, no server change); `scenario.jl` reads `n_pn`/`r_stop` (validated at LOAD: n_pn>0,
      r_stop≥0). `test_missile.jl` (decide!-matches-pn_accel; PN miss≪pursuit [0.03 vs 708 m]; a_cmd
      falls-vs-climbs; paths differ; **glimit saturation** miss(a_max=300)=410 ≫ miss(1000)=0.7;
      loader arms+rejects). `test_determinism.jl` (3 claims + **additivity master-check**: a verbatim
      slice-9 missile ≡ `:guidance=:pursuit`, bit-identical). `test_server.jl` (set_fidelity write/
      reject/introduce-safe; N/a_max/r_stop live sliders survive — huge N hits the clamp, not a throw).
      **Key decisions:** comp/YAML/knob key = `n_pn` (consistent, not bare `:n`); r_stop default 0 is
      the byte-identity lever; Lesson-1 geometry = the v[-800,0,200] crossing (pursuit ≫ PN honestly).
- [x] **3. Scenarios + Godot + verifiers — DONE (1829 green + all Godot proofs pass).**
      `slice10_pn.yaml` (12° crossing, a_max 3000 generous — pn miss 0.03 ≪ pursuit 708) +
      `slice10_glimit.yaml` (5° hot geometry, a_max 300 BINDS — miss 410 sat 0.84; a_max↑ → 0.7).
      Numbers PROBED against the live `load_scenario→decide!→integrate!` path (gate3_loader/framesampled/
      bands) + frame-sampled for the verifier. Godot: `guidance` discriminator branch checked BEFORE
      `autopilot` (advisor A — slice-10 ships BOTH; the one button toggles guidance), `_on_guidance_pressed`
      cycler, GUIDANCE_RUNGS, button/badge/readout (new telemetry auto-renders); `_draw` missile+LOS
      branches extended (`guidance` fid_kind). Proofs: `net/slice10_verify.gd` (branches on scenario name;
      S10V OK on BOTH — first-descending-band a_cmd fall/climb + los>2500-gated early saturation, advisor
      C), `net/slice10_ui_test.gd` (S10UI OK — button cycles guidance NOT autopilot), Sandbox.tscn
      smoke-load on both (SERVER_DONE, no GDScript errors), `test_scenario.jl` arms, and the windowed
      shot-harness visual confirmation (pn a_cmd=33 floor / pursuit a_cmd=270 climb / glimit a_cmd=300
      pinned at a_max while a_demand=821 — saturation visible). Slice-8/9 UI tests re-run green.

## Gate-0 probe results (pinned — rough, re-pin at gate 3 vs the live wire)

Probe reused the real `total_accel`/`integrator_step`(:rk4)/`los_rate`/`range_rate`/`clamp_accel`/
`pursuit_accel`; hand-rolled only `pn_accel` (TPN `a=N·Vc·(ω×û)`, N=4) + the decide!→integrate! loop
(autopilot `:ideal`, one-tick delay, gravity-free CV target, gravity-on missile). Full detail:
`M:\claud_projects\temp\slice10_probe\FINDINGS.md`.

- **PN sign CORRECT** — intercepts every crossing (miss 0.0–0.5 m); no "flies away". (Still pin the
  sign in `test_guidance.jl` on a concrete L→R crossing.)
- **Lesson 1 (PN beats pursuit) — robust.** e.g. missile [0,0,3000]@700 m/s/12°, tgt [6000,0,4200]
  v[-600,0,120] → **pursuit ~378 m, PN ~0.1 m**; harder v[-800,0,200] → pursuit **708 m**, PN 0.0 m.
  The signature holds: pursuit `|a_cmd|` **climbs ×1.9–4.4** (tail-chase), PN `|a_cmd|` **falls
  ×0.21–0.27**. **Gravity floor — mechanism TESTED (advisor #1): PN `|a_cmd|` floors at ~2g ≈
  18–20 m/s², NOT 0.** The g-symmetric probe (`probe4.jl`, gravity removed) is the discriminator:
  g-off → `|a_cmd|` collapses to ~0 (textbook), g-on → floors at ~2g. It is the **`N/(N-2)·g_perp`
  PN-lag signature** (N=4 → ×2) — the gravity-free CV target makes gravity an *unmodeled target
  acceleration* PN lags by the APN term (a bonus slice-11 tee-up). Contrast still large (~2g floor ≪
  pursuit's hundreds). `slice10_pn` pick: a mid crossing, a_max generous (3000, never binds). **Pin
  the RATIO / "pursuit ≫ PN", not PN's absolute miss** — 0.0–0.5 m is at the tick-sampling floor
  (~0.9 m/tick at these closing speeds; advisor gate-3 note).
- **Lesson 2 (g-limit saturation) — clean, monotone, EARLY-turn.** Geometry: missile [0,0,3000]@
  800 m/s/**5°** (large heading error to a high fast-crossing target), tgt [4000,0,6500] v[-700,0,-150].
  **Unsaturated peak PN demand ≈ 785 m/s² (~80 g).** miss(a_max): 60→2730 m, 250→1385 m, **500→0.5 m**,
  ≥1000→0.4 m — monotone, sharp knee at the demand peak; saturation is the **establish-the-triangle
  early turn** (advisor #2, `sat_early` = all early ticks for a_max ≤ 500), not the endgame spike.
  Mechanism real, not artifact. `slice10_glimit` pick: a_max ~300–400 m/s² (~30–40 g) for a legible
  connect-state miss the slider closes; knee is sharp → tune exact a_max vs the live wire at gate 3;
  pin the unsaturated peak (~785) as a comment.
- **Endgame r→0 — hazard REAL, 3-layer guard validated.** Raw pre-clamp `|a_demand|` = **2.02×10⁶
  m/s² at r=0.125 m** (`_FRAME_EPS=1e-12` guard useless — HANDOFF §10.10 confirmed). `r_stop`
  coast-through: **miss identical (0.54 m) across r_stop ∈ {0,5,15,30,60,120}** (no CPA corruption,
  Decision 4); r_stop tames the pre-cutoff spike (5→5502, 15→1587, **30→26**, 60/120→21). **Pin
  r_stop ≈ 30–50 m.** `clamp_accel` holds applied accel at exactly a_max (3000) even at 2e6 raw
  demand — **no NaN/Inf ever**; `_finite` < FINITE_CEIL=1e9. Bonus: without the cutoff the missile
  diverges post-CPA (range→31 km) — extra justification for the coast-through.
- **Scope (advisor-confirmed):** PN-not-APN · CV target · two scenarios · TPN `a=N·Vc·(ω×û)` ·
  CPA-miss · coast-through `r_stop`. **N default 4.** All at dt=1e-3 (the realtime floor).

## Context / landmarks
- **The cascade seam (built for this):** `guidance.jl` — `pursuit_accel` / `autopilot_step` are
  separate pure fns (guidance.jl:14–18, the slice-9 Decisions §1 factoring); `:guidance` reserved
  (guidance.jl:17). Add `pn_accel` as `pursuit_accel`'s sibling; the inner loop is untouched.
- **`frames.jl` PN kernel (built + sign-tested in slice 8 FOR this):** `los_rate` (`r×v/r²`, the ω;
  frames.jl:197), `range_rate` (closing speed; frames.jl:183, "negative = closing"), `los_unit`,
  `_cross`, `_norm3` — everything PN needs, dependency-free.
- **`Autopilot.decide!`** (missile.jl:196) — the ~3-line seam to modify (§3: the outer-law branch);
  the a_cmd clamp (missile.jl:225) is where the g-limit binds; telemetry publish (missile.jl:246–250)
  extends with `a_demand`/`saturated`.
- **Fidelity plumbing precedent:** slice-9 `:autopilot` (`AUTOPILOT_MODES` in guidance.jl →
  `LIVE_FIDELITY_MODES` in radar.jl:126 → `set_fidelity` per-key table in server.jl:173 → scenario.jl
  `_KNOWN_FIDELITY_KEYS`:325) — `:guidance` mirrors it exactly (introduce-safe, physics-changing).
- **Scenario loader** (`scenario.jl`) — the guided `:missile`/`guidance:` sub-block (slice 9) extends
  with `n`/`r_stop`.
- **HANDOFF** §10 item 10 (this slice — PN + g-limit + the r→0 endgame), item 9 (slice 9 — the inner
  loop this rides on), §1 (named approximations; **LOS-sign trifecta**), §9 (frames reuse), §12
  (fidelity badge). §11 Tier A (6-DOF, APN — the deferred horizon).

## Watch-items (gotchas to bake in)
- **Default `:guidance = :pursuit` is the byte-identity anchor.** Every slice-9 scenario sets no
  `:guidance`; `get(w.fidelity, :guidance, :pursuit)` MUST default to the slice-9 law so slice-9
  trajectories stay bit-for-bit identical (the "slices are additive" master-check). Pin a slice-9
  scenario replaying bit-identical after the missile.jl edit.
- **Slice 10 INVERTS slice 9's `a_max` discipline.** Slice 9: "a_max must NEVER bind" (crash-guard).
  Slice 10 `glimit`: a_max **binds on purpose** (the lesson). Keep the clamp as a crash-guard in
  `slice10_pn` (generous, never binds — Lesson 1 held clean) but **make it bind** in `slice10_glimit`
  (Lesson 2). Document the inversion prominently so nobody "fixes" the binding clamp.
- **PN SIGN is the trifecta.** `pn_accel` must turn the missile toward the LEAD (reduce `λ̇`), not away
  ("missile flies away"). Pin the sign on a concrete left→right crossing (extend the frames.jl
  `los_rate` sign discipline). Publish `los_rate`/`closing_speed` telemetry so a sign flip is visible.
- **The endgame `r→0` blow-up is REAL and NAMED** (HANDOFF §10.10). `ω = r×v/r²` diverges as `r→0`
  with any residual miss; the `_FRAME_EPS = 1e-12` frames guard is far too small. Add a guidance-level
  **terminal cutoff (`r_stop`)** + keep the `a_max` clamp + `_finite` the pre-clamp `a_demand`
  telemetry. Measure **miss at CPA** (min `los_range`), not fixed-`t`.
- **Confirm the glimit geometry actually saturates PN** (Decision 2) — PN against a non-maneuvering
  target on a good course does NOT saturate (`a_cmd→0`). Force it with heading-error/crossing, PROBE
  the peak `a_demand > a_max`, and confirm raising `a_max` shrinks the miss — else the "saturation" is
  an artifact, not a lesson.
- **Don't copy the slice-5/6/7 "toggle-bit-identical" language** — `:guidance` is *physics-changing*
  (no RNG; a toggle changes the trajectory). Use the slice-8/9 three-claims framing (introduce-safe /
  replay-bit-identical / not-a-dead-knob). (Convention 4c; advisor slice-8 #1.)
- **`:autopilot` and `:guidance` are ORTHOGONAL** (inner vs outer). Slice-10 scenarios pin
  `:autopilot = :ideal` so the client's ONE fidelity button toggles ONE lesson (convention 9). Two
  scenarios, one toggled fidelity each.
- **PN, not APN; constant-velocity target.** Implement plain PN; the maneuvering-target/APN case is
  the TEE-UP (slice 11+), the exact parallel to slice 9 teeing up slice 10. HANDOFF says saturation
  "modeled … why augmented PN matters" — motivation, not an in-slice APN implementation.
- **`a_demand` (pre-clamp) is the new saturation readout** — publish it distinct from `a_cmd`
  (post-clamp) so the clamp binding is visible; `_finite`-clamp both (no Inf/NaN to JSON).
- **Verifier drain multiples** of `emit_every` (the slice-2/6/7/8/9 timeout trap).
- **Stay spatial** — extend `_draw_spatial`, no new render mode (the slice-8/9 precedent); the LOS
  line's constant-bearing-vs-swing IS the PN-vs-pursuit visual.
- **Reserved key now filled** — `:guidance` moves from "reserved, absent" (slice-9 `test_scenario`
  asserted ABSENT) to present; update that slice-9 loader assertion (it becomes a slice-10 arm).
