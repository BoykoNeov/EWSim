# Slice 12 — Missile: augmented PN + a maneuvering-target mover (the seeker arc's RNG-free payoff)

The deferred half of HANDOFF **§10 item 10/11** (the missile arc's tee-up, named across three slices). Slice 10
gave proportional navigation against a **constant-velocity** target: PN is *optimal* there (`a_cmd → 0` at
intercept, miss ≈ 0), and the only residual was the ~2g **`a_cmd` floor** (gravity acting as an unmodeled
*relative* acceleration — the CV target is gravity-free, the missile carries `−g`). Slice 11 gave a noisy seeker
+ α-β LOS-rate filter so PN reads a *measured* LOS. Slice 12 lands the **third structural tee-up**: even a
**perfect** LOS estimate leaves plain PN **lagging a *maneuvering* target** by the target-acceleration term, and
**augmented PN** (APN) — the `(N/2)·a_T⊥` feedforward — closes that lag. Source of truth: HANDOFF §10 items 10–11
(the "g-limit saturation modeled — this is *why* augmented PN matters" note) + §11 Tier A (the deferred horizon).

**Scope RATIFIED WITH THE USER (2026-07-02):** slice 11 was seeker + filter **ONLY**; **augmented PN + the
maneuvering-target mover are slice 12** (needs a new mover; cleanly separable). This slice is **RNG-free** — the
"even a *perfect* seeker" framing means the guidance reads **truth** (truth `ω` *and* truth target-accel `a_T`),
so there is **no `w.rng` draw**. That is the single sharpest framing trap in this slice (watch-item 1 below).

## THE DETERMINISM SHAPE — REVERT TO SLICE 10; do NOT carry slice 11's RNG-inflection framing (advisor #2)

**Slice 11 was the RNG inflection** ("the seeker is the first `w.rng` consumer in the missile arc; conventions
3/11 now APPLY"). **Slice 12 INVERTS that back.** It has **no seeker → no `w.rng` draw**, so the determinism
story is the **slice-10 shape**: `:apn` and the `ManeuveringTarget` mover are **physics-changing, no RNG,
introduce-safe**; "RNG lockstep / draw-count invariance" is **VACUOUS** again (convention 4c). This is the
**convention-4c copy-paste trap running the OPPOSITE direction from slice 11** — every file I just read for
slice 11 asserts "RNG now applies"; that language is WRONG here. The three claims (the slice-10/8 template, NOT
the slice-11 one):

1. **Introduce-safe / additivity.** Absent a `:apn` selection AND absent a `maneuver:` block, nothing new runs:
   a slice-1..11 scenario is **byte-identical**. `:apn` is a *new* `GUIDANCE_MODES` rung (default stays
   `:pursuit`), so slice-9/10/11 scenarios that select `:pursuit`/`:pn` are untouched; a plain `:target` with no
   `maneuver:` block still arms `ConstantVelocity` (the exact slice-1..11 mover).
2. **Same-config replay is bit-identical** — deterministic, TRIVIALLY (no RNG to desync).
3. **A `:pn↔:apn` toggle CHANGES the trajectory** (the not-a-dead-knob property — the OPPOSITE of slices 5/6/7)
   **but there is no RNG stream to keep in lockstep** — so do NOT write "draw-count invariant" (vacuous). It is
   the slice-10 `:guidance` shape exactly: physics-changing, no RNG.

## The lesson (shown as numbers — the LANDING IS EMPIRICAL, advisor #1)

**Plain PN lags a maneuvering target; APN's `(N/2)·a_T⊥` feedforward closes the lag.** Against a target that
**maneuvers** (a lateral / turning acceleration `a_T`, unlike the slice-10 CV crossing):

- **Plain PN (`:pn`) lags.** TPN `a = N·Vc·(ω×û)` nulls the LOS rate for a *non-accelerating* target; a
  maneuvering target keeps regenerating LOS rate faster than PN removes it, so PN chases a moving collision
  triangle and **opens a miss** (and/or drives `a_cmd` up — the split between "miss opens" vs "`a_cmd` climbs"
  is the **gate-0 probe's** call, see the CAUTION below).
- **Augmented PN (`:apn`) closes it.** APN adds a feedforward proportional to the target's acceleration
  **perpendicular to the LOS**: `a = N·Vc·(ω×û) + (N/2)·(a_T − (a_T·û)û)`. Fed the **truth** `a_T` (the perfect
  estimate — RNG-free), the feedforward cancels the maneuver-induced lag and the missile **intercepts tightly**.

**⚠ CAUTION — do NOT pin the landing from theory (advisor #1).** Slice 10's "~2g floor" was an **`a_cmd`** floor;
its PN **miss** against the CV target was **~0** (0.03 m at the sampling floor). "Gravity as unmodeled accel"
manifested as a nonzero terminal *`a_cmd`*, **not a miss**. So it is an **empirical gate-0 question** whether plain
PN against *this* maneuvering target (a) opens a real **miss** that APN collapses, or (b) merely raises the
terminal **`a_cmd`** (with both intercepting). The probe MUST report `miss(:pn)` vs `miss(:apn)` **and**
`a_cmd(:pn)` vs `a_cmd(:apn)` and **pick the headline from the data** (miss-ratio if the miss opens; `a_cmd` /
saturation contrast if it doesn't — the slice-11 "pick the regime from the probe" discipline). **Pin the RATIO,
not absolutes** (the [[ewsim-missile-verifier-sampling]] frame-sampling floor). Design the maneuver magnitude so
the lesson is UNAMBIGUOUS (a maneuver hard enough that `:pn` visibly fails on the chosen headline).

**✅ GATE-0 RESOLUTION (the probe settled the CAUTION; advisor re-read + HANDOFF linchpin confirmed).** Under a
**generous** `a_max`, plain PN INTERCEPTS the maneuvering target anyway (miss ≈ 0 for both; APN only lowers
`a_cmd`) — exactly the slice-10 "the floor is an `a_cmd` effect, not a miss" trap. So the **miss lesson requires a
BINDING `a_max`**: PN's high demand against the maneuver **saturates → misses**; APN's low demand stays under the
limit → intercepts. This is **HANDOFF §10 item 10 verbatim** — *"g-limit saturation modeled (this is why
augmented PN matters)"* — the face-value design intent, not a tidier reading. **PINNED SCENARIO:** slice10_pn
crossing + `a_lat = 200 m/s²` (⟂-v, turn-sign **+1** — the clean direction) + **binding `a_max = 200`**, N=4,
r_stop=30, RNG-free. **HEADLINE:** `:pn` miss=166.8/sat=0.62 vs `:apn` miss=0.59/sat=0.00 (**~281× ratio**; pin the
ratio). **The miss is the headline (consequence); the demand/saturation contrast is the mechanism (advisor's
"teach BOTH" — B contains A) — expose BOTH in telemetry + the verifier.** `:apn` **restores the maneuvering-target
miss to the CV baseline** (apn 0.59 ≈ pn(CV) 0.49 — both carry the same gravity residual; a stronger statement
than "gravity residual"). **Lesson WINDOW `a_max ∈ ~[100, 350]`** (default 200 centered; slider → 350+ = "PN
recovers", the payoff) — document it so a learner's nudge can't silently erase the lesson. SIGN decisive:
apn(+)=0.59 vs apn(−)=646.7 vs pn=166.8. Full record: `M:\claud_projects\temp\slice12_probe\FINDINGS.md`.

**Gravity handling — lean gravity-free target; name gravity-comp PN as DEFERRED (advisor #1, convention 9).** The
`ManeuveringTarget` is **kinematic and gravity-free** (the ConstantVelocity lineage — it feels only its commanded
`a_T`, not `−g`). The missile still carries gravity, so a **small residual `a_cmd`/miss floor may remain even
under `:apn`** (the slice-10 ~2g floor persists — APN feeds forward the *target* accel, not the missile's own
gravity). That is HONEST and expected; the probe reports it. **Do NOT fold a second (gravity-compensation)
feedforward into this slice** — gravity-compensated PN is a named, DEFERRED extension (one lesson per scenario,
convention 9). If APN doesn't get satisfyingly close because gravity dominates, fix it by making the **maneuver
dominate gravity** in the scenario (a hard turn), NOT by adding a second feedforward.

## Scope (one lesson per scenario — the slice-3/4/9/10 principle)

A single guided **interceptor** (`[BallisticMissile, Autopilot]` — NO Seeker, RNG-free) against a single
**maneuvering target** (`[ManeuveringTarget]` — the new phase-1 mover), under **`autopilot = :ideal`** (held, so
the miss/`a_cmd` isolates the **guidance law**, the slice-10 isolation discipline). The switchable **fidelity is
`guidance ∈ (:pursuit, :pn, :apn)`** — `:apn` is the NEW third rung; the lesson is the **`:pn ↔ :apn`** compare
(`:pursuit` rides along in the ring as the slice-9/10 foil). Explicitly **deferred**:

- **Gravity-compensated PN** (feeding forward the missile's own `−g` / the full *relative* accel) — a second
  feedforward; named, DEFERRED (§ gravity handling above; convention 9).
- **Estimated `a_T`** (an α-β-γ tracker / estimating target accel from the seeker) — slice 12 reads **truth**
  `a_T` (the perfect estimate; "even a perfect seeker still lags"). Fusing APN with the slice-11 noisy seeker (a
  noisy `a_T` estimate) is a later fidelity step (§11 Tier A) — slice-12 scenarios carry **no Seeker**.
- **6-DOF / fin-actuator dynamics** (§11 Tier A); **IR/RF seeker discrimination / countermeasures** (roadmap
  item 12); **thrust/boost** (coasting body). Maneuver type limited to ONE clean form (probe-pinned below).

**One scenario** (one lesson; the button cycles the 3-ring, the lesson is `:pn↔:apn`; the maneuver is fixed in
the scenario, not a live toggle). 3 review gates + a gate-0 probe (mirroring slices 5–11).

## The physics / math (named approximations — HANDOFF §1)

### 1. The `ManeuveringTarget` mover (a NEW phase-1 subsystem — the maneuvering foil)

The slice-1..11 `:target` gets `ConstantVelocity` (`pos += vel·dt`, RNG-free, no accel). Slice 12 adds a
**`ManeuveringTarget <: Subsystem`** (phase-1 `integrate!`) that applies a **lateral acceleration** so the target
curves — the thing plain PN can't lead. **Maneuver form (probe-pinned; lean a constant-magnitude lateral accel ⟂
velocity — a coordinated, speed-preserving g-turn IN THE x-z PLANE):**

    a_T = a_lat · perp(v)          (perp = the in-plane unit ⟂ to v, turn-sign · rotate(v̂, ±90° in x-z))
    (p′, v′) = integrator_step(:rk4, w -> a_T(w), p, v, dt)      (advisor efficiency note — REUSE dynamics.jl)

- **Reuse `integrator_step(:rk4, accel, p, v, dt)`** with the closure `accel(v) = a_lat·perp(v)` (advisor), NOT a
  bespoke stepper — but keep it **self-contained** (the target's step is ALWAYS `:rk4`; do NOT couple the target
  to the missile's `:integrator` fidelity — that would make the target's path move when the *missile*'s
  integrator toggles, a cross-lesson leak). The probe confirms the arc is exact enough that target-integration
  error does not confound the miss (a constant-⟂-v turn is a circle; RK4 is very accurate but NOT exact for it —
  unlike constant-g, which it integrates exactly).
- **The mover writes `comp[:a_target]::Vec3`** — the **truth** target accel THIS tick — into the target entity's
  comp, so the missile's phase-4 `decide!` can read it for APN (a cross-entity truth read, like reading
  `tgt.pos`/`tgt.vel`; comp survives `empty!(w.env)` — advisor #f confirmed). Default (no maneuver) = not
  written, so `decide!` reads `get(tgt.comp, :a_target, zero(Vec3))` → APN's feedforward vanishes on a CV target.
- **Named approximations:** the maneuver is a **constant** lateral accel (no jink/weave program — a later
  fidelity step); the target is **gravity-free / kinematic** (feels only `a_T`, not `−g` — the ConstantVelocity
  lineage; § gravity handling); planar in **x-z** (the elevation view's plane, no cross-range — the slice-10
  precedent). Config guards: `a_lat_mps2` finite (a huge live value just curves harder, no crash).
- **CLEAN-FIRST-CPA (advisor #3 — the verifier's sharp edge, HARDER than 10/11).** A *turning* target can curve
  **back** and create a **second CPA**, and the r→0 endgame spike still applies ([[ewsim-missile-verifier-
  sampling]]). Pick the **turn direction + magnitude + launch geometry so the first CPA is clean** (the target
  curves/​outruns *away* after the first pass, no re-convergence). This is a **gate-0 probe deliverable**, not a
  gate-3 surprise — the probe pins the min-`los_range` sampling window (first-descending band, endgame-gated) and
  the conservative one-sided bounds.

### 2. The APN law (`pn_accel_augmented`, guidance.jl — reuses `pn_accel_from_omega`)

**Augmented true proportional navigation:** the TPN command plus a feedforward proportional to the target's
acceleration **perpendicular to the LOS**:

    a_apn = pn_accel_from_omega(û, ω, Vc; N) + (N/2)·a_T⊥        a_T⊥ = a_T − (a_T·û)·û      (⟂-LOS component)

- **`pn_accel_augmented(û, ω, Vc, a_T; N = 4.0) -> Vec3`** — a NEW pure function in guidance.jl, **reusing
  `pn_accel_from_omega(û,ω,Vc;N)` for the base term** so the `:pn` arithmetic is textually untouched. The
  feedforward `(N/2)·(a_T − _dot(a_T,û)·û)` uses `_dot`/`_norm3` (frames.jl house style, no LinearAlgebra).
- **SIGN is the trifecta (advisor #4 — a flipped feedforward makes `:apn` WORSE than `:pn`, the silent
  failure).** Pin it **TWO independent ways**: (a) **closed-loop** — `miss(:apn) < miss(:pn)` on the live wire
  (gate 2 / the probe); (b) a **direct-recompute** of the `(N/2)·a_T⊥` term in `test_guidance.jl` (a DIFFERENT
  expression than the impl — the slice-10 two-source sign-pin precedent). The `a_T⊥` projection sign is direct
  (the actual target accel projected ⟂ LOS); the `+N/2` coefficient and the `+` (not `−`) are the two levers.
- **Byte-identity (slices 1–11).** Keep the `a_T` **fetch INSIDE the `:apn` branch** of `decide!` (default
  `zero(Vec3)`) so the `:pn`/`:pursuit` code path is **textually unchanged** → byte-identical BY CONSTRUCTION.
  `:apn`-on-a-CV-target `≈ :pn` is a nice sanity check but use **`≈`** (the `x + zero(Vec3)` `−0.0 + 0.0 → +0.0`
  bit trap — missile.jl:104) and it carries **NO** byte-identity burden (no prior scenario selects `:apn`).

### 3. Fidelity: `guidance ∈ (:pursuit, :pn, :apn)` — the third rung (physics-changing, no RNG)

`GUIDANCE_MODES = (:pursuit, :pn, :apn)` — **add `:apn`** to the existing tuple (guidance.jl, the one-list source
of truth; `LIVE_FIDELITY_MODES` in radar.jl REFERENCES it, `set_fidelity`/`_KNOWN_FIDELITY_KEYS` pick it up
automatically — NO server change, the slice-10 precedent). `:apn` is **physics-changing, NO RNG** (the
slice-2/8/9/10 shape): introduce-safe (default `:pursuit`; slice-9/10/11 scenarios select their own rung → byte-
identical) but a `:pn↔:apn` toggle CHANGES the trajectory (not-a-dead-knob). `Autopilot.decide!` gets a **third
branch**: `guid === :apn` → `pn_accel_augmented(truth û, truth ω, truth Vc, truth a_T; N)`. **`:apn` reads
TRUTH** (no seeker branch — slice-12 scenarios have no Seeker; the slice-11 `haskey(c,:seeker_omega)` branch
stays `:pn`-gated and untouched). `:guidance`/`:autopilot` stay orthogonal; slice-12 scenarios pin
`:autopilot = :ideal` so the ONE button toggles the ONE guidance lesson (convention 9).

## Decisions to take at gate 0 (surface to advisor BEFORE gates 1–3 — advisor #1 is un-settleable from here)

1. **The HEADLINE — miss-ratio vs `a_cmd`/saturation contrast (advisor #1).** Report `miss(:pn)`/`miss(:apn)`
   AND `a_cmd(:pn)`/`a_cmd(:apn)`/saturation; **pick the headline from the data**. Pin the RATIO.
2. **Maneuver form + magnitude** — lean constant-⟂-v g-turn; the probe picks `a_lat` so `:pn` UNAMBIGUOUSLY fails
   on the chosen headline while `:apn` closes it, AND the first CPA is clean (advisor #3).
3. **Gravity-free kinematic target** — confirm; report the residual `:apn` floor (gravity persists); gravity-comp
   PN stays DEFERRED (advisor #1).
4. **Clean-first-CPA geometry** — pin the min-`los_range` sampling window (first-descending, endgame-gated) and
   conservative one-sided bounds (`:pn`-lower / `:apn`-upper), NOT the ratio for the verifier (advisor #3).
5. **`integrator_step(:rk4, ...)` reuse for the mover** — confirm the arc is exact enough (target-integration
   error ≪ the guidance lag); self-contained (not coupled to `:integrator`).
6. **The sign is right** — `miss(:apn) < miss(:pn)` closed-loop AND the direct-recompute agrees (advisor #4).
7. **One scenario, `N`/`a_lat` values** — pinned by the probe against the live wire (convention 10).

## Review gates (cadence: staged, mirroring slices 5–11)

0. **Gate-0 probe (throwaway, `M:\claud_projects\temp\slice12_probe\`).** Reuse the REAL core physics
   (`using EWSim`: `total_accel`/`integrator_step`/`los_unit`/`los_rate`/`range_rate`/`clamp_accel`/`pn_accel`/
   `pn_accel_from_omega`), hand-roll only the maneuvering target (the `a_lat·perp(v)` closure), the APN
   feedforward, and the decide!→integrate! loop (autopilot `:ideal`; `:pn` vs `:apn`). **Confirm + pin numbers:**
   (i) plain PN against the maneuvering target — measure BOTH `miss` and `a_cmd`/saturation, **decide the
   headline** (advisor #1); (ii) APN closes it (the chosen headline collapses; report the residual `:apn` floor);
   (iii) the maneuver `a_lat` + launch geometry give a **CLEAN FIRST CPA** (advisor #3 — no curve-back second
   CPA, endgame spike excluded); (iv) **the SIGN** — `miss(:apn) < miss(:pn)` AND a direct `(N/2)·a_T⊥`
   recompute (advisor #4); (v) the RK4-mover arc is exact enough (advisor efficiency note). Write `FINDINGS.md`,
   pin `a_lat`/`N`/geometry and the `:pn`≫`:apn` **RATIO** + conservative one-sided verifier bounds.
   **RE-CONSULT THE ADVISOR after the numbers land** (advisor #1 — the landing is the one thing un-settleable
   from the plan). Forward-flag any gate-1/2/3 seams the hand-rolled probe papers over.

1. **Primitive green (pure, closed-form, SI, RNG-free, no LinearAlgebra).** guidance.jl:
   **`pn_accel_augmented(û, ω, Vc, a_T; N)`** = `pn_accel_from_omega(û,ω,Vc;N) + (N/2)·(a_T − _dot(a_T,û)·û)`,
   pure, `_dot`/`_norm3` only, guarded (`û→0` → the `pn_accel_from_omega` base handles it; `a_T=0` → exact base).
   **`GUIDANCE_MODES = (:pursuit, :pn, :apn)`** (add the rung; one-list-no-drift). `pursuit_accel`/`pn_accel`/
   `pn_accel_from_omega`/`autopilot_step` **UNCHANGED** (byte-identity anchor). Export `pn_accel_augmented`.
   `test_guidance.jl` (+ APN arms, explicit `atol`): **the feedforward direct-recompute** (a DIFFERENT expression
   than the impl — catches a transpose / a `−` sign flip); **`a_T⊥` really ⟂ LOS** (`_dot(a_apn − a_pn, û)/‖…‖`
   ≈ 0 up to the base term's ⟂-ness); **`a_T ∥ û` → zero feedforward** (a radial maneuver adds nothing — the
   projection kills it); **`a_T = 0` → `a_apn == pn_accel_from_omega`** (`===` bit-exact, the base is untouched);
   **N-linearity of the feedforward** (`N/2` scales). Slices 1–11 byte-identical through the include (golden +
   determinism green; no RNG added).

2. **Wired — the maneuvering mover + the `:apn` rung.** New **`ManeuveringTarget <: Subsystem`** (missile.jl or a
   new mover home) with a **phase-1 `integrate!`**: `integrator_step(:rk4, v->a_lat·perp(v), pos, vel, dt)`,
   writes `comp[:a_target]` (truth accel this tick) + optional target telemetry (the `a_lat` magnitude). RNG-free.
   `Autopilot.decide!`: the **§3 `:apn` branch** (`guid === :apn` → `pn_accel_augmented` with truth ω/û/Vc +
   `get(tgt.comp, :a_target, zero(Vec3))`) — the `:pn`/`:pursuit` paths and the slice-11 seeker branch
   **UNCHANGED**. `LIVE_FIDELITY_MODES` picks up `:apn` via `GUIDANCE_MODES` (no edit). `scenario.jl`: a
   `maneuver:` sub-block under `:target` reads `a_lat_mps2` (+ turn sign) at a **knob-addressable comp key**,
   validated at **LOAD**; its PRESENCE swaps `ConstantVelocity → ManeuveringTarget` (a plain target — no
   `maneuver:` — stays `ConstantVelocity`, byte-identical).
   - `test_missile.jl` (+ APN/maneuver arms): `ManeuveringTarget.integrate!` curves the target + writes
     `comp[:a_target]` matching `a_lat·perp(v)`; the `:apn` decide! branch matches `pn_accel_augmented` on a
     realized state; **`miss(:apn) ≪ miss(:pn)` on the wire** (autopilot `:ideal`, the Lesson pin — or the
     `a_cmd` contrast per the probe's headline); **`:pn↔:apn` trajectories DIFFER** (not-a-dead-knob); the
     maneuvering target's path CURVES (vs ConstantVelocity's straight line); loader arms+rejects bad `a_lat`.
   - `test_determinism.jl` (the SLICE-10 shape — NOT slice-11's; watch-item 1): same-seed bit-identical
     (trivial, no RNG); **a slice-1..11 scenario is byte-identical** (no `:apn`, no `maneuver:` block →
     `ConstantVelocity` + no feedforward — the additivity master-check); **`:pn↔:apn` toggle CHANGES the
     trajectory** (physics-changing, no RNG — do NOT write "draw-count invariant"); a **slice-10 `:pn` scenario
     replays BIT-IDENTICAL** after the guidance.jl/missile.jl/scenario.jl edits (the truth-path anchor).
   - `test_server.jl`: `set_fidelity :guidance :apn` write/**introduce-safe** (physics-changing, no RNG — like
     `:pn`); the `a_lat`/`N`/`a_max` live sliders `set_param`→tick survive (a huge `a_lat`/`N` curves/​commands
     harder, does NOT throw — the "a live slider can't crash a tick" watch-item). Slices 1–11 byte-identical.

3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice12_apn.yaml` (`guidance:apn` default,
   `autopilot:ideal` held, `[BallisticMissile, Autopilot]` interceptor + a `[ManeuveringTarget]` curving target,
   the clean-first-CPA geometry from gate 0). **Numbers probed against the live
   `load_scenario→decide!→integrate!→telemetry` wire** + pinned (the probe's headline + conservative one-sided
   bounds).
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode — the slice-8/9/10/11 precedent).
     The **guidance cycler becomes a 3-RING** (`GUIDANCE_RUNGS = [:pursuit, :pn, :apn]`; `_on_guidance_pressed`
     walks/wraps the ring — the slice-10 2-ring extended); the `a_lat`/`N` sliders; the target's **CURVED trail**
     is the new visual (the maneuvering path vs the slice-10 straight crossing). The visual tell: under `:pn` the
     missile **trails the curving target** (lag → miss / high `a_cmd`); under `:apn` it **leads the curve** to a
     tight intercept. All readout scalars (re-confirm no Array telemetry / `float()`-crash). Slice-1..11 views
     UNTOUCHED (re-run every smoke-load + UI test — the guidance cycler stays a superset).
   - `net/slice12_verify.gd` (drives the real server): `:apn` **intercepts** the maneuvering target (small
     min-`los_range` / low `a_cmd` per the headline); `set_fidelity guidance :pn` **degrades** it (large
     min-range / high `a_cmd`); **`t`/`pos` bit-identical under the held seed+config** (replay — trivial without
     RNG, but pin it on a pos sequence, the slice-10/11 discipline). Assertions on SCALARS/sequences. `S12V OK`,
     exit 0. Step counts **multiples of `emit_every`** (the drain contract).
   - `net/slice12_ui_test.gd` (mock client, no server): the handshake wires the **3-ring guidance** cycler; the
     ring walks `:pursuit→:pn→:apn` and wraps; badge/button track; the `a_lat`/`N` sliders send `set_param`;
     reset resyncs (`S12UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-12 server (server `DONE` ⇒ scene connected, no
     GDScript errors).
   - `test_scenario.jl` + slice-12 loader testset (parses; `:apn` default now PRESENT [the reserved-rung-becomes-
     real move]; `:autopilot = :ideal` held; the target gets `[ManeuveringTarget]` NOT `ConstantVelocity`;
     `a_lat_mps2` at a consumed comp key and IS a knob; loader rejects a bad `a_lat`).
   - The **`_draw` maneuvering PIXEL branch** visually confirmed via the windowed shot harness
     ([[ewsim-godot-headless]]): `:pn` = the missile lagging the curving target (miss / high `a_cmd`); `:apn` =
     the lead onto the curve + tight intercept. **(stretch, deferred)** `clients/notebooks/slice12_apn.jl` Pluto
     (the miss-vs-`a_lat` sweep — the maneuver-lag lesson as a curve); an offline `batch.jl` miss-vs-`N`/`a_lat`
     grid (own seeded stream — the distribution path, though RNG-free here).

## Task checklist
- [ ] **0. Probe + scope pin** (`M:\claud_projects\temp\slice12_probe\`: `probe.jl` + `FINDINGS.md`). Pin the
      headline (advisor #1), `a_lat`/`N`/geometry, the clean-first-CPA window (advisor #3), the sign (advisor #4).
      **RE-CONSULT ADVISOR after the numbers.** Forward-flag gate-1/2/3 seams.
- [ ] **1. Primitive** — `pn_accel_augmented` + `:apn` rung in guidance.jl; `test_guidance.jl` arms; slices 1–11
      byte-identical.
- [ ] **2. Wired** — `ManeuveringTarget` mover + the `:apn` decide! branch + the `maneuver:` loader block;
      test_missile/test_determinism/test_server arms; slices 1–11 byte-identical.
- [ ] **3. Scenario + Godot + verifiers** — `slice12_apn.yaml`, the 3-ring cycler + curved-target view, the four
      proofs, `test_scenario.jl` arm. Update STATUS.md + CLAUDE.md. Commit + push (end-of-batch ritual).

## Context / landmarks
- **The truth PN slice 12 augments:** `pn_accel`/`pn_accel_from_omega` (guidance.jl:135/160) — `:apn` adds the
  `(N/2)·a_T⊥` term to `pn_accel_from_omega`'s output. The `:apn` word is NOT yet a `GUIDANCE_MODES` rung — this
  slice adds it (the third rung; slice 10 added `:pn` next to `:pursuit`).
- **The decide! seam:** `Autopilot.decide!` (missile.jl:255) already branches `guid === :pn && haskey(:seeker_omega)`
  / `guid === :pn` / else pursuit; slice 12 adds a `guid === :apn` arm reading truth ω + `tgt.comp[:a_target]`.
- **The mover to clone:** `ConstantVelocity` (radar.jl:26) — the phase-1 `pos += vel·dt` mover; `ManeuveringTarget`
  is its accelerating sibling, reusing `integrator_step(:rk4, ...)` (dynamics.jl) with an `a_lat·perp(v)` closure.
- **`frames.jl` LOS kernel (reused):** `los_unit`, `los_rate`, `range_rate`, `_cross`, `_dot`, `_norm3` — the APN
  feedforward's `a_T − (a_T·û)û` projection uses `_dot`.
- **Fidelity plumbing precedent:** slice-10 `:guidance` (`GUIDANCE_MODES` → `LIVE_FIDELITY_MODES` → `set_fidelity`
  → `_KNOWN_FIDELITY_KEYS`) — `:apn` is the third rung, physics-changing/no-RNG (like `:pn`, introducible).
- **The mover-arming precedent:** the `:missile` block's conditional `push!(subs, Seeker)/Autopilot` (scenario.jl:285/305)
  — the `maneuver:` block conditionally swaps `ConstantVelocity → ManeuveringTarget` the same way.
- **HANDOFF** §10 items 10–11 (this slice's tee-up; "g-limit saturation modeled — why augmented PN matters"),
  §3 (the tick contract — phase-1 mover + phase-4 decide!), §1 (named approximations; the LOS/feedforward-sign
  trifecta), §11 Tier A (estimated `a_T` / 6-DOF / seeker fusion — the deferred horizon).

## Watch-items (gotchas to bake in)
- **THE FRAMING INVERSION — do NOT carry slice-11's RNG-inflection language (advisor #2).** Slice 12 has NO
  seeker → NO `w.rng` draw → the slice-11 "first w.rng consumer / conventions 3+11 apply" boilerplate is WRONG
  here. Revert to the slice-10 shape: physics-changing, NO RNG, "draw-count invariance is VACUOUS." The
  convention-4c trap running the OPPOSITE direction from slice 11.
- **The landing is EMPIRICAL, not theoretical (advisor #1).** Slice 10's ~2g "floor" was an `a_cmd` floor with a
  ~0 miss. Do NOT assume plain PN opens a big MISS against the maneuvering target — the probe measures BOTH miss
  and `a_cmd`/saturation and picks the headline. Pin the RATIO.
- **CPA against a CURVING target is the sharp edge (advisor #3).** A turning target can curve back → a second
  CPA; the r→0 endgame spike still applies ([[ewsim-missile-verifier-sampling]]). Design the geometry for a CLEAN
  FIRST CPA (curve away, no re-convergence); pin conservative one-sided bounds, NOT the ratio, for the verifier.
- **Sign-pin APN two ways (advisor #4).** A flipped `(N/2)·a_T⊥` makes `:apn` WORSE than `:pn` (the silent
  failure). Closed-loop `miss(:apn) < miss(:pn)` AND a direct-recompute in `test_guidance.jl`.
- **Keep the `:pn`/`:pursuit` path byte-identical.** The `a_T` fetch + feedforward live INSIDE the `:apn` branch
  (default `zero(Vec3)`) so the `:pn` arithmetic is textually untouched → slices 1–11 replay bit-identical. Pin a
  slice-10 `:pn` scenario. `:apn`-on-CV `≈ :pn` uses `≈` (the `+zero(Vec3)` ±0 trap), no byte-identity burden.
- **The mover is gravity-free / self-contained.** `ManeuveringTarget` feels ONLY `a_T` (not `−g` — the CV
  lineage), always steps `:rk4` (NOT coupled to the missile's `:integrator`). A residual `:apn` floor from the
  missile's own gravity is HONEST; gravity-comp PN is DEFERRED (convention 9).
- **`a_lat` / `N` are knobs; validate at LOAD** (finite `a_lat`); a live huge value just curves/​commands harder,
  the `clamp_accel`/mass-floor "a live slider can't crash a tick" discipline — no throw.
- **Stay spatial** — extend `_draw_spatial`, no new render mode (slice-8/9/10/11 precedent); the CURVED target
  trail + missile lead (apn) vs lag (pn) IS the visual. The guidance cycler becomes a 3-RING (not a new button).
- **Verifier drain multiples** of `emit_every`; the replay assertion pins a pos sequence (trivial without RNG,
  but keep the discipline).
