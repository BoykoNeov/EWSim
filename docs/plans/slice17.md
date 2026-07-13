# Slice 17 — the α→lift→γ coupling: rotation feeds translation (§11 Tier-A)

**The FIRST rotation→translation coupling in the project.** Slice 16 made `att` (θ, q) a DYNAMICAL output of the
aero pitching moment but kept it **ISOLATED** — rotation read the flight condition (V, γ) yet did NOT feed back
into (pos, vel), so the trajectory was byte-identical across any Cmα. Slice 17 closes that loop: the angle of
attack **α = θ − γ generates a body lift force ⟂ velocity that turns the flight path** (`α → lift → γ̇`). This is
the ROTATION analog of nothing prior — it is the *coupling* the whole slice-16 isolation was banked to enable,
and it is where the **real path-changing `:airframe` fidelity toggle** finally lands (slice 16 deliberately
refused it — a path-bit-identical toggle would have named a coupling it could not yet produce; the convention-4c
false-fidelity trap).

**SCOPE SPLIT (user-ratified 2026-07-13; advisor-backed).** HANDOFF §11 / `slice16.md` committed slice 17 as
*"the inner α/g autopilot + α→lift→γ coupling + angle-of-attack-limited maneuverability."* That bundles too much
into one entangled diff. **Split — exactly as slices 15/16 split the same Tier-A entry:**

- **Slice 17 (THIS plan) — the coupling, OPEN-LOOP.** α→lift→γ + the `:airframe = point_mass | pitch_coupled`
  toggle + the joint `[pos, vel, θ, q]` integrator. **No `decide!` change** — the fin δ is a FIXED authored trim.
  The diff touches ONLY the force model + integrator (dynamics.jl / airframe.jl / missile.jl `integrate!`). The
  lesson: **the airframe steers by α→lift** — a deflected fin pitches the nose, α builds, lift turns the flight
  path, and the trajectory bends into a circle (`:point_mass` flies ballistic, `:pitch_coupled` curves — the
  toggle is REAL). Clean closed-form anchor: the steady-turn radius.
- **Slice 18 (DEFERRED, NAMED) — the inner α/g autopilot + α-limited maneuverability.** `decide!`/guidance only:
  invert the PN command `a_cmd → α_cmd → δ` (the slice-15 δ state finally does work through the `Cmδ·δ` moment
  term), then the **flight-condition-dependent aero g-limit** miss (`a = Q·S·C_Lα·α_max/m`, Q = ½ρV² → less g at
  low speed / high altitude — distinct from slice-10's fixed kinematic `a_max`). The trigger recorded in
  slice15.md/slice16.md is fulfilled THERE.

Source of truth: HANDOFF §11 Tier-A (lines 487–506) + §10 item 8 (the force-integrator this couples into) + §3
(the tick contract) + §1 (named approximations, the sign/units/frames trifecta). Slice 16's `airframe.jl`
primitives + `_integrate_airframe!` are the direct base.

## The scope — the coupling, isolated and OPEN-LOOP

The direct analog of slice 8 (validate the integrator before closing a loop on it): slice 17 validates the
COUPLED airframe under a fixed fin, slice 18 closes the α/g autopilot on it.

- **Pitch plane ONLY** (scalar θ, q — the slice-16 reduction unchanged; 3-D quaternion+ω waits for bank-to-turn).
- **OPEN-LOOP** — δ is a FIXED authored trim (no autopilot closes it; that is slice 18). A nonzero δ is MANDATORY
  (see the toggle-non-dead constraint below).
- **COUPLED** — rotation now feeds translation via the lift force. `total_accel` becomes α-aware; the missile
  integrates the JOINT `[pos, vel, θ, q]` state in ONE RK4 step (the coupled short-period is stiff — do NOT
  operator-split it).

The dynamics (the NEW term is the lift; gravity + drag + the pitching moment are slice-8/16 verbatim):

    α      = θ − γ,   γ = atan(v_z, v_x),   V = ‖v‖,   Q = ½ρV²
    L      = Q·S·C_Lα·α                              (body normal / lift force, N — LINEAR lift-curve slope C_Lα)
    a_lift = (L/m)·(−sinγ, 0, cosγ)                  (⟂ v in the x-z plane; the +90°-rotated v̂ — THE SIGN)
    a      = gravity_accel() + drag_accel(v) + a_lift        (translation — a_lift is the slice-17 addition)
    q̈      = pitch_moment(α, δ, q, V, p) / I         (rotation — slice-16 airframe.jl, UNCHANGED)
    (ṗ, v̇, θ̇, q̇) = (v, a, q, q̈)                      (the joint first-order system)

**THE #1 SIGN TRAP (frames/signs FIRST — the slice-16 discipline extended).** The lift sign × the ⟂-direction ×
the `α = θ−γ` definition interact. Pinned DIRECTLY (a magnitude-only anchor passes under a double-flip — the
exact trap slice 16 caught on the moment sign): **a steady α > 0 must make γ INCREASE** (the flight path chases
the nose; α self-reduces as γ catches up). The `(−sinγ, 0, cosγ)` perp with `+C_Lα·α` (C_Lα > 0) gives lift
toward +perp → γ̇ > 0 for α > 0. Pin `dot(a_lift, v̂) ≈ 0` (lift ⟂ velocity, no speed change from lift) AND the
γ̇ sign, not just the turn magnitude.

## THE LESSON — the airframe steers by α→lift (the toggle becomes real)

Slice 16's lesson was the Cmα static-stability SIGN (weathervane vs tumble) in the ATTITUDE, path frozen. Slice
17's lesson is the COUPLING itself, now visible in the PATH: deflect the fin (fixed δ ≠ 0) → the `Cmδ·δ` moment
pitches the nose to a trim α → lift ⟂ velocity → the flight path bends into a **steady circular turn**. Drag the
δ slider (or C_Lα) and watch the turn tighten. Flip the `:airframe` button `:point_mass ↔ :pitch_coupled` and
watch the SAME missile fly ballistic (point-mass: δ inert, att kinematic) vs curve (coupled: δ → α → lift). **The
curved-path-from-a-fixed-fin IS the lesson AND is what makes the toggle non-dead** (the slice-15 "the limit must
actually bind" discipline, here "the coupling must actually bend the path").

**Closed-form anchor — the STEADY-TURN RADIUS (advisor, load-bearing — use this, NOT a short-period frequency):**

    a_lift = Q·S·C_Lα·α / m   set equal to the centripetal V·γ̇  ⇒
    γ̇ = ρ·V·S·C_Lα·α / (2m)          and          R = V/γ̇ = 2m / (ρ·S·C_Lα·α)

**R is SPEED-INDEPENDENT** (lift and required centripetal both scale with V²) — an exact equilibrium, recall-free,
the clean pin. Validate lift **in ISOLATION first (gravity OFF, drag OFF)** so the ONLY ⟂ force is lift and the
path is a PURE circle (the slice-8 "drag off → clean parabola" discipline); THEN add gravity for the showcase
scenario.

**Two subtleties (advisor — will bite if unflagged):**
- **The slice-16 1e-15 EXACTNESS DOES NOT TRANSFER.** Slice 16's "RK4-exact to machine-eps vs closed form" held
  because the isolated system was LINEAR CONSTANT-COEFFICIENT (γ frozen within a step). COUPLED, γ evolves → not
  constant-coefficient → the transient short-period frequency is only APPROXIMATE. Do NOT hand-recall a coupled
  ω_sp (it picks up a lift/Z_α term). Pin the EXACT steady-turn equilibrium (R) instead; verify any transient
  short-period in the gate-0 probe against a FINE-dt reference, never against a recalled formula.
- **Steady-turn α ≠ slice-16 `trim_alpha`.** In a steady turn q = γ̇ ≠ 0 (the nose rotates WITH the turning flight
  path), so the moment balance carries a `Cmq·q̄` term and α is offset from `−(Cmδ/Cmα)·δ`. For the CLEANEST R
  anchor, set **Cmq = 0 in the anchor case** → `α_trim = −(Cmδ/Cmα)·δ` exactly and R is clean. Confirm both the
  Cmq=0 (clean) and Cmq≠0 (offset) cases in the gate-0 probe.

## The advisor-reconciled design decisions

- **`AIRFRAME_MODES = (:point_mass, :pitch_coupled)`** — the real toggle, defined in `airframe.jl` (before
  radar.jl so `LIVE_FIDELITY_MODES` REFERENCES it — the one-list-no-drift / mode-const-before-radar precedent).
  **NAMING HONESTY (advisor):** NOT `:sixdof` (over-claims — this is pitch-plane α→lift ONLY; full 6-DOF /
  bank-to-turn / 3-D is still deferred). `:pitch_coupled` carries a named-approximation line. Default
  **`:point_mass`** → `get(w.fidelity, :airframe, :point_mass)`.
- **Gating (advisor-confirmed correct):** rotation still runs on `haskey(c, :af_cma)` (slice-16, UNCHANGED); the
  COUPLING (lift + joint step) runs iff `haskey(c, :af_cma) && get(w.fidelity, :airframe, :point_mass) ===
  :pitch_coupled`. So:
  - a **slice-8..15** scenario (no `:af_cma`) → point-mass force + velocity-aligned att → **byte-identical**;
  - a **slice-16** scenario (`:af_cma` present, no `:airframe` fidelity → defaults `:point_mass`) → ISOLATED
    rotation, NO coupling → **byte-identical to slice 16** (the pos-invariance slice 16's verifier asserts);
  - a **slice-17** scenario (`:af_cma` + `:airframe: pitch_coupled`) → the coupled path.
- **The toggle MUST be non-dead (the slice-16 trap returns — advisor).** With δ = 0 and no α-kick, `:pitch_coupled`
  ≈ `:point_mass` (α ≈ 0 → lift ≈ 0 → ballistic) → the toggle is bit-identical AGAIN → the exact convention-4c
  false-fidelity trap. **The scenario MUST author a nonzero trim δ** so a sustained α_trim bends the path clearly
  ≠ ballistic. That is the lesson and what makes the toggle real.
- **Class 4c** (physics-changing, NO RNG — truth-fed, OPEN-LOOP, no seeker → "draw-count invariance VACUOUS"; the
  4th consecutive 4c after slices 14/15/16). Live-settable, **NO `set_fidelity` guard** (the
  `:integrator`/`:autopilot`/`:apn`/`:cooperation` precedent; CONTRAST slice-13 `:scan`'s introduce-reject). A
  `:point_mass↔:pitch_coupled` toggle CHANGES the trajectory (not a dead knob) with no RNG.
- **The JOINT integrator is NEW code — VERIFY, do not trust the forward-promise (advisor).** Slice 16's `rk4_rot`
  is a 2-state `(θ, q)` stepper and its comment ("shaped so slice-17's joint step reuses the closure") is a design
  INTENTION written before slice 17. Check how much actually composes vs a fresh 8-scalar `[pos, vel, θ, q]` RK4.
  Integrate the full state JOINTLY in one step (the stiff short-period must not be operator-split from
  translation). Likely shape: a new `airframe.jl` `rk4_coupled(deriv, pos, vel, θ, q, dt)` where `deriv` returns
  `(a_translational, q̈)` from `(pos, vel, θ, q)` — the closure captures params/δ/ρ; the `:point_mass` path keeps
  the slice-8 `integrator_step` VERBATIM (byte-identity).
- **Crash-safety (convention 5):** V→0 (launch/apex) — the lift `Q·S·C_Lα·α` → 0 there (Q→0), so no divide; the
  `(−sinγ, 0, cosγ)` perp is well-defined for any v (γ = atan(v_z, v_x), a v→0 apex rides the same guard the
  slice-16 γ read uses). No new floor needed for the OPEN-LOOP coupling — the `a_cmd/Q → α_cmd` divide that DOES
  need a Q-floor is slice 18 (recorded there). The wire `_finite`-clamps the lift readout.

## The three gates (planned)

0. **Gate-0 probe (throwaway, `M:\claud_projects\temp\slice17_probe\`).** Reuse the REAL core physics (`using
   EWSim`: `total_accel`/`drag_accel`/`gravity_accel`/`integrator_step`/`pitch_moment`/`airframe_step`/`short_period_freq`/
   `_norm3`/`los_*`), hand-roll only the `lift_accel` candidate + the joint `rk4_coupled` + the `integrate!` loop.
   **Confirm + pin:** (i) the STEADY-TURN RADIUS `R = 2m/(ρ·S·C_Lα·α)` (gravity/drag OFF → pure circle; Cmq = 0
   → clean α_trim) to `atol`; (ii) the LIFT SIGN directly (α>0 ⇒ γ̇>0; `dot(a_lift, v̂) ≈ 0`); (iii) the coupled
   transient short-period vs a FINE-dt reference (NOT a recalled formula) — and whether it can go unstable in the
   showcase regime; (iv) byte-identity of a slice-8/16 scenario (point_mass path bit-identical); (v) NO RNG; (vi)
   the joint-integrator composition (does `rk4_rot` reuse, or a fresh 8-scalar RK4). Write `FINDINGS.md`, pin the
   geometry / δ / C_Lα / S / I / Cmα / Cmq / launch condition + the R value + conservative verifier bounds. **RE-
   CONSULT THE ADVISOR after the numbers** (the coupled-stability regime is the one thing un-settleable from the
   plan). Forward-flag gate-1/2/3 seams.

1. **`airframe.jl` primitive green** (pure, RNG-free, no LinearAlgebra — the §9 house style). Add: `lift_accel(alpha,
   V, gamma, p::AirframeParams)` (the ⟂-v lift specific force; `C_Lα` a NEW `AirframeParams` field, see below);
   `rk4_coupled` (the joint `[pos, vel, θ, q]` stepper); `AIRFRAME_MODES = (:point_mass, :pitch_coupled)` (one-list
   source of truth). `pitch_moment`/`rk4_rot`/`airframe_step`/`short_period_freq`/`trim_alpha` **UNCHANGED**
   (byte-identity anchor). `AirframeParams` gains `Cla::Float64` (lift-curve slope ∂C_L/∂α, 1/rad) — a STRUCT
   change; confirm every slice-16 `AirframeParams(...)` call site (missile.jl:161, :209) updates in lockstep (or
   add `Cla` LAST with the slice-16 constructors passing a default). `test_airframe.jl` (+ coupling arms, explicit
   `atol`): the **steady-turn radius** (isolated lift, gravity/drag off, Cmq=0 → R exact); the **lift SIGN**
   (α>0⇒γ̇>0, lift⟂v); the **joint stepper** reproduces the slice-16 rotation when lift=0 (C_Lα=0 → `rk4_coupled`
   ≡ `airframe_step` on (θ,q) AND `integrator_step` on (pos,vel) — the decoupled limit); **zero-safe** (V→0 ⇒
   lift→0, no NaN). Slices 1–16 byte-identical through the include.

2. **Wired — the coupled `integrate!` path + the `:airframe` rung + loader.** `missile.jl`: `_integrate_airframe!`
   (or a new `_integrate_coupled!`) gains the coupled branch — when `:airframe === :pitch_coupled`, step the JOINT
   state through `rk4_coupled` (lift in the force); else the slice-16 ISOLATED path (rotation only) or the
   slice-8..15 point-mass path, both TEXTUALLY UNCHANGED (byte-identity — the `mode === :fin`/`haskey(:af_cma)`
   gating precedent). New lift telemetry from `build_env!` (scalars: `a_lift`, `gamma_dot` or turn radius). `radar.jl`:
   `LIVE_FIDELITY_MODES` picks up `:airframe` via `AIRFRAME_MODES` — **this is a NEW fidelity KEY** (unlike slice
   15's `:fin` which was a new RUNG of an existing key), so add the `airframe = AIRFRAME_MODES` entry to the
   `LIVE_FIDELITY_MODES` NamedTuple (radar.jl:164) and confirm `_KNOWN_FIDELITY_KEYS` (scenario.jl:508) + `set_fidelity`
   (server.jl) pick it up with NO further edit. `scenario.jl`: parse `airframe.cla` → `comp[:af_cla]` (LOAD-validate
   finite; C_Lα > 0 for a normal lifting body — but crossing/negative is a lesson-adjacent knob, so validate FINITE
   not sign, mirroring `cma`); the `airframe:` block is otherwise slice-16 verbatim. `set_fidelity`: **NO new guard**
   (class 4c — the `:integrator`/`:autopilot` live-settable precedent).
   - `test_missile.jl` (+ coupling arms): a `:pitch_coupled` missile with a fixed δ ≠ 0 CURVES (its path ≠ the
     `:point_mass` twin's ballistic arc — the toggle is not-a-dead-knob, pinned on the POS sequence); the steady
     turn radius on the realized 1-missile world matches R (loose `atol` — gravity on); `:point_mass` byte-identical
     to slice 8/16; the lift readout is finite; **att round-trips** (nose off θ, the slice-16 check).
   - `test_determinism.jl` (the SLICE-14/15/16 shape — NOT slice-11/13's RNG shape): same-seed bit-identical with
     **NO RNG on the missile path** (pin `t` AND a per-missile pos sequence); a slice-1..16 scenario **byte-identical**
     (`:airframe` unset → `:point_mass` → the slice-16 isolated / slice-8 point-mass arithmetic verbatim);
     `:point_mass↔:pitch_coupled` toggle CHANGES the trajectory with no RNG (class 4c — "draw-count invariance
     VACUOUS"); introduce CLEAN both directions (no topology guard — the class-4c live-safety).
   - `test_server.jl`: `set_fidelity :airframe :pitch_coupled` write/**introduce-safe both directions** (class 4c);
     the `af_cla`/`af_delta` live `set_param`→tick survives (no throw — "a live slider can't crash a tick"). Slices
     1–16 byte-identical.

3. **Scenario + Godot view + verifiers.** `scenarios/slice17_coupling.yaml`: ONE open-loop missile
   `[BallisticMissile]` with `airframe:` (nonzero `delta` — MANDATORY for the non-dead toggle — plus `cla`, and
   Cmq per the gate-0 pick) + `fidelity: {airframe: pitch_coupled}`; the δ and C_Lα (or Cmα) as knobs; gravity ON
   (a showcase climbing turn), drag OFF (one lesson). **Numbers probed against the live `load_scenario→integrate!→
   telemetry` wire** + pinned (convention 10).
   - Godot: the airframe view (slice-16 base) gains the `:airframe` fidelity BUTTON BACK — **value-guard the
     `_setup_spatial_fid_btn` airframe branch** (the slice-16 CLIENT NOTE: the branch is checked FIRST and drops
     the button on `_airframe_view`; now that an `:airframe` fidelity EXISTS alongside `af_cma`, gate the drop on
     the fidelity being ABSENT so slice 17 gets its `:point_mass↔:pitch_coupled` cycler while slice 16 still drops
     it). The NEW VISUAL: the curved (coupled) vs straight (point_mass) trail; the nose off θ, the velocity ref off
     γ, the gap = α (slice-16 visual, now with a BENDING path). All readout scalars (no Array — the `float()`-crash
     watch-item).
   - `net/slice17_verify.gd` (drives the real server): `:pitch_coupled` with a fixed δ CURVES (turn radius ≈ R,
     the coupled path ≠ ballistic) while `:point_mass` flies the slice-16 ballistic arc (posdiff > 0 — the toggle
     is REAL, the INVERSE of slice-16's posdiff=0.0 assertion); `set_param af_delta 0 → path straightens` (the
     lever); `t`/per-missile `pos` bit-identical under the held seed+config (RNG-free replay); `set_fidelity airframe
     pitch_coupled` ACCEPTED live (class-4c). `S17V OK`, exit 0. Step counts multiples of `emit_every`.
   - `net/slice17_ui_test.gd` (mock client, no server): the airframe view now SHOWS the `:airframe` cycler
     (`:point_mass↔:pitch_coupled`, wraps); the δ/C_Lα slider sends `set_param`; reset resyncs; **a slice-16-style
     handshake (af_cma, no `:airframe` fidelity) still DROPS the button** (the value-guard both ways). `S17UI OK`.
   - `Sandbox.tscn` smoke-loaded headless against the slice-17 server (server `DONE` ⇒ scene connected, no GDScript
     errors); the slice-16 airframe scenario re-smoke-loaded (button still dropped).
   - `test_scenario.jl` + slice-17 loader testset (parses; `airframe: pitch_coupled` present; `af_cla`/`af_delta`
     at consumed keys + knobs; loader rejects non-finite `cla`).
   - The **coupled-vs-ballistic `_draw` PIXEL branch** confirmed via the windowed shot harness
     ([[ewsim-godot-headless]]): the curving coupled trail (nose leading, α gap, path bending) vs the straight
     point-mass arc.

## Deferred (NAMED) — slice 18 and beyond

- **Slice 18 (NEXT) — the inner α/g autopilot + α-limited maneuverability.** `decide!`/guidance only: invert PN's
  `a_cmd → α_cmd = a_cmd·m/(Q·S·C_Lα) → δ` (the slice-15 fin state δ feeds the `Cmδ·δ` moment term — the two
  Tier-A halves join). **The `a_cmd/Q` divide is a CRASH-SAFETY site (advisor):** Q = ½ρV² → 0 as V→0 → floor Q /
  clamp α_cmd (convention 5). The headline: the **flight-condition-dependent aero g-limit** `a_max_aero = Q·S·C_Lα·
  α_max/m` — at low Q (slow / high-altitude) the missile can't pull enough g → misses a maneuvering target the
  `:point_mass` (fixed `a_max`) catches. Distinct from slice-10's kinematic clamp.
- **Induced drag** (lift costs speed: `C_Di ∝ C_L²`) — a named-deferred approximation; slice 17's lift is
  drag-free (⟂-v, speed-preserving) exactly as the ManeuveringTarget turn is.
- **Bank-to-turn / 3-D** (the quaternion+ω superset; the geometry→frames "2-D first" precedent); the radome/
  body-rate parasitic loop (needs body rates + a body-mounted seeker); per-channel fin allocation / hinge-moment /
  stall; a 2nd-order actuator (ω_a/ζ_a).

## Watch-items (gotchas to bake in)

- **THE LIFT SIGN IS THE #1 TRAP (advisor, load-bearing).** α>0 ⇒ γ̇>0 (flight path chases the nose). Pin
  DIRECTLY (`dot(a_lift, v̂)≈0` AND the γ̇ sign), not a magnitude-only turn check — a double-flip (α-definition ×
  perp-direction) passes the magnitude test (the slice-16 moment-sign trap, recurring).
- **THE 1e-15 EXACTNESS DOES NOT TRANSFER (advisor).** Coupled → γ evolves → not constant-coefficient → the
  transient short-period is APPROXIMATE. Anchor on the EXACT steady-turn radius R; verify any transient vs a
  fine-dt reference, NEVER a recalled coupled ω_sp formula.
- **STEADY-TURN α ≠ `trim_alpha` (advisor).** A steady turn has q = γ̇ ≠ 0 (a Cmq·q̄ term). Set Cmq = 0 in the R
  anchor case for a clean `α_trim = −(Cmδ/Cmα)·δ`; confirm the Cmq≠0 offset separately (don't pin R against
  slice-16's `trim_alpha` and lose time on the mismatch).
- **THE TOGGLE MUST BE NON-DEAD (the slice-16 trap returns — advisor).** δ = 0 ⇒ `:pitch_coupled` ≈ `:point_mass`
  bit-identical ⇒ false-fidelity trap. The scenario MUST author a nonzero trim δ (curved path ≠ ballistic). The
  slice-15 "the limit must actually bind" discipline.
- **THE JOINT INTEGRATOR IS NEW CODE — VERIFY (advisor).** Don't trust slice-16's "reuses the closure" forward-
  promise; check composition vs a fresh 8-scalar RK4. Integrate JOINTLY in one step (do NOT operator-split the
  stiff short-period from translation). Anchor the decoupled limit (C_Lα=0 ⇒ joint step ≡ slice-16 isolated).
- **NAMING HONESTY (advisor).** `:pitch_coupled`, NOT `:sixdof` — pitch-plane α→lift ONLY; 3-D / bank-to-turn
  deferred. Carry a named-approximation line (the §1 "no hidden approximations" discipline).
- **CLASS 4c, NOT slice-13's 4b.** Physics-changing, NO RNG (truth-fed open-loop, no seeker) → no draw-topology
  → introduce-SAFE, live-settable, NO set_fidelity guard (the `:integrator`/`:autopilot`/`:apn`/`:cooperation`
  precedent). "Draw-count invariance" is VACUOUS — the 4th consecutive 4c. Do NOT copy slice-11/13 draw language.
- **`AirframeParams` STRUCT CHANGE (byte-identity hazard).** Adding `Cla` touches every constructor call
  (missile.jl:161, :209; test_airframe.jl). Update ALL in lockstep — a missed call site is a MethodError, not a
  silent bug, but confirm the slice-16 `airframe`-scenario determinism fingerprints are bit-for-bit unchanged
  (the `:point_mass`/isolated path takes the same numbers → same bytes).
- **`:airframe` IS A NEW FIDELITY KEY, not a rung** (contrast slice-15's `:fin`). Add it to `LIVE_FIDELITY_MODES`
  (radar.jl:164) as a new NamedTuple entry; `_KNOWN_FIDELITY_KEYS`/`set_fidelity`/`_validate_fidelity` pick it up
  via that single source (one-list-no-drift — verify nothing re-lists it).
- **CLIENT: BUTTON BACK, value-guarded (the slice-16 note).** `_setup_spatial_fid_btn` checks the airframe branch
  FIRST and drops the button on `_airframe_view`; gate that drop on the `:airframe` fidelity being ABSENT so slice
  17 gets its cycler and slice 16 still drops it. Re-run every slice-1..16 smoke-load + UI test.
- **Verifier drain multiples** of `emit_every`; the replay assertion pins `t` AND a per-missile pos sequence on an
  RNG-INDEPENDENT value (NO seeker — the slice-14/15/16 discipline). First-CPA/miss stamp not needed (open-loop,
  no target) — pin the TURN RADIUS / posdiff instead ([[ewsim-missile-verifier-sampling]] for the sampling floor).

## Context / landmarks

- **The primitives slice 17 extends:** `core/src/airframe.jl` — `AirframeParams`(:46, gains `Cla`), `pitch_moment`(:76,
  UNCHANGED), `rk4_rot`(:95, the 2-state stepper the joint `rk4_coupled` generalizes), `airframe_step`(:115),
  `short_period_freq`(:129, the transient is now only approximate — don't over-pin), `trim_alpha`(:150, ≠ the
  steady-turn α). NEW: `lift_accel`, `rk4_coupled`, `AIRFRAME_MODES`.
- **The force model slice 17 couples into:** `core/src/dynamics.jl` — `total_accel`(:75, gains the α-dependent lift
  term OR the lift is added at the missile.jl call site so `total_accel` stays v-only — gate-0 picks; the advisor's
  "α-aware force" can live either place, but the JOINT step must see it). `integrator_step`(:125, the `:point_mass`
  path keeps it VERBATIM). `gravity_accel`/`drag_accel` UNCHANGED.
- **The integrate! slice 17 extends:** `Autopilot`-free `BallisticMissile.integrate!` (missile.jl:84) +
  `_integrate_airframe!`(:154, the slice-16 isolated rotation) — slice 17 adds the coupled branch gated on
  `:airframe === :pitch_coupled`. The `_airframe_view_info`(:238) handshake marker is REUSED (the client value-
  guards on the `:airframe` fidelity now existing alongside it).
- **The class-4c precedent (physics-changing, no RNG, live-settable, NO introduce-reject):** `:integrator`(slice 8),
  `:autopilot`(slice 9/15), `:apn`(slice 12), `:cooperation`(slice 14). CONTRAST slice-13 `:scan` (4b, rejected).
- **Fidelity plumbing precedent:** slice-15 added `:fin` to `AUTOPILOT_MODES` (a new RUNG); slice 17 adds a new KEY
  `:airframe` → `LIVE_FIDELITY_MODES`(radar.jl:164) → `_KNOWN_FIDELITY_KEYS`(scenario.jl:508) + `set_fidelity`
  (server.jl:183) + `_validate_fidelity`(scenario.jl:512), one-list-no-drift.
- **HANDOFF** §11 Tier-A (lines 487–506 — the entry this slice's coupling half completes; slice 15 = actuator/fin,
  slice 16 = rotation, slice 17 = α→lift coupling, slice 18 = α/g autopilot + α-limit), §10 item 8 (the force-
  integrator), §3 (the tick contract), §1 (named approximations; the sign/units/frames trifecta).
- **Memory:** [[ewsim-fin-dynamics-direction]] (the 6-DOF arc tracker — update on completion),
  [[ewsim-missile-verifier-sampling]], [[ewsim-godot-headless]], [[ewsim-realtime-dt-floor]].

## Task checklist
- [x] **0. Probe + config pin** — DONE (`M:\claud_projects\temp\slice17_probe\`: `probe.jl` + `FINDINGS.md`;
      advisor re-consulted, 3 follow-ups folded in). CONFIRMED: R=5196.9 m EXACT at equilibrium (0.0 err); lift
      SIGN correct (α>0⇒γ̇>0, dot⟂v≤4e-15); decoupled limit byte-exact (inertial); dt=1e-3 converged; NO RNG;
      composition = FRESH 8-scalar `rk4_coupled` (re-evals V,γ in-step = the coupling; `airframe_step` kept
      VERBATIM for `:point_mass`). Non-dead toggle SHOWN (coupled vs ballistic twin = 1155 m separation @ 8 s).
      Long unstable knob-drag (Cma=+0.5, 25 s) stays FINITE ⇒ no consumer clamp, wire-clamp suffices. Config
      pinned: Cla=20, δ=0.15 (α_trim=0.05), Cmq=−150 (overdamped — lighten at gate 3 if the ring is wanted;
      goal iii-b short-period-vs-fine-dt then re-run). Gate-1/2/3 seams flagged in FINDINGS.md.
- [x] **1. Primitive** — DONE (2429 tests, +20 gate-1 arms, byte-identity green). `airframe.jl`: `AirframeParams`
      gained `Cla` as the LAST field (docstring: slice-16 point_mass never reads it); `lift_accel(vel,θ,mass,p)` =
      `(Q·S·Cla·α/m)·(−sinγ,0,cosγ)`, reusing `_AIRFRAME_V_FLOOR` (advisor #4), V≤floor→zero; `rk4_coupled(f,pos,vel,
      θ,q,dt)` = a FRESH generic 8-scalar joint RK4 (probe expressions VERBATIM — advisor #2, so the decoupled `==`
      survives; re-evals V,γ mid-step = the coupling, not operator-split); `const AIRFRAME_MODES=(:point_mass,
      :pitch_coupled)` before radar.jl (one-list, for gate-2 `LIVE_FIDELITY_MODES`). Exported lift_accel/rk4_coupled/
      AIRFRAME_MODES. Call sites in lockstep: missile.jl:161/:209 (`get(c,:af_cla,0.0)`), test_airframe.jl:27/162/164,
      test_missile.jl:1554 (`get(c,:af_cla,0.0)`). `test_airframe.jl` arms: lift SIGN (#1 trap — ⟂-dot AND γ̇-sign AND
      magnitude, level+climbing, α<0 flips, α=0/V≤floor→0), `rk4_coupled` constant-(force,q̈) exact (joint analog of
      the rk4_rot pin), decoupled limit `Cla=0` inertial ≡ `integrator_step ⊕ airframe_step` BIT-EXACT (`==`, advisor
      #2/#3), steady-turn R=2m/(ρSC_Lα·α)≈5197 m at tight `atol=1e-2` (finite-diff γ̇, NOT ==) + ⟂-lift preserves speed.
      Byte-identity CONFIRMED by the full suite (test_determinism + test_detection golden green), not just reasoned.
- [x] **2. Wired** — DONE (2461 tests, +32 gate-2 arms, slices 1–16 byte-identical). `missile.jl`: the coupled
      `_integrate_coupled!` branch, gated `haskey(:af_cma) && get(w.fidelity,:airframe,:point_mass)===:pitch_coupled`
      — the point-mass block wrapped VERBATIM in the `else` (advisor: no code-share; point-mass arithmetic
      bit-identical). JOINT [pos,vel,θ,q] `rk4_coupled` step; θ lazy-init from the PRE-step launch γ (contrast the
      point-mass `_integrate_airframe!` POST-step seed); force = `total_accel` + `lift_accel` (a_ctrl EXCLUDED —
      slice-18 guidance coupling, commented); impact clamp DUPLICATED (kept separate for byte-identity); RK4-ONLY
      (ignores `:integrator` euler — named). **THE STAGE-θ FIX (advisor, load-bearing):** the deriv closure reads
      the RK4 STAGE `TH`, NEVER the entry θ — pinned by a transient GOLDEN in test_missile (`total_accel+lift_accel+
      rk4_coupled`, 8 s: pos=(2187.823608281557, 3010.178483035902), θ=1.251491571778638, q=0.06393471230113383;
      atol 1e-6/1e-9). The entry-θ bug is only ~0.019 m/8 s (measured) — invisible to R (α≈const) & the decoupled
      test (Cla=0), so ONLY this golden catches it. Lift telemetry (`a_lift`, `turn_radius_m`=V²/a_lift) gated on
      `:pitch_coupled` NOT af_cma (advisor: else a slice-16 `:point_mass` wire breaks). Loader: `airframe.cla`→
      `:af_cla`, validate FINITE not sign. `LIVE_FIDELITY_MODES` gains `airframe = AIRFRAME_MODES` (the ONLY plumbing
      edit — `_KNOWN_FIDELITY_KEYS`/`set_fidelity`/`_validate_fidelity` all derive; NO set_fidelity guard, class 4c).
      Arms: test_missile (golden, non-dead toggle sep>500 m + ballistic-twin, lift readout Q·S·Cla·α/m, att
      round-trip, loader cla parse/reject); test_determinism (coupled A-vs-B bit-identical + pristine rng, :point_mass↔
      :pitch_coupled CHANGES it, introduce-safe both dirs, check-G 25 s unstable→finite through build_env!→_finite);
      test_server (set_fidelity :airframe write/reject/introduce + live af_cla/af_delta slider→tick survives).
- [x] **3. Scenario + Godot + verifiers** — DONE (2488 tests). `scenarios/slice17_coupling.yaml` (δ=0.15 MANDATORY,
      Cla=20, `fidelity:{airframe:pitch_coupled}`, grav on/drag off, af_delta+af_cla knobs). `Sandbox.gd`: the
      `:airframe` cycler BACK, REUSING `_fid_kind="airframe"` (curved-trail + nose/vel/α drawing carry over
      unchanged — the advisor site-audit showed the α drawing is `_airframe_view`-gated + line-1133 readout keys on
      `_fid_kind=="airframe"`, so reuse is lowest-risk) with the drop VALUE-GUARDED on `_fidelity.has("airframe")`
      (`AIRFRAME_RUNGS`, `_on_airframe_pressed`, `_update_fid_btn` show/hide branch). Live-wire probe (convention 10,
      `temp/slice17_probe/scenprobe.jl`): coupled (2187.8,3010.2) vs ballistic (3064.2,2257.3) → posdiff 1155 m end /
      876 m frame-max; δ→0 straightens to 91 m (12.7×). FOUR PROOFS GREEN: `slice17_verify.gd` (S17V OK — coupled
      CURVES/replay 0.0/point_mass ballistic posdiff 876>500/δ→0 straightens 69.5), `slice17_ui_test.gd` (S17UI OK —
      cycler shows+wraps+set_fidelity, sliders set_param, slice-16 handshake STILL drops = value-guard both ways),
      `Sandbox.tscn` smoke-load (SERVER_DONE), windowed shot (the CURVED coupled trail + nose leading cyan v(γ) by the
      labeled α gap, button "airframe: pitch_coupled"). `test_scenario.jl` loader arm (parses the real yaml, af_cla/
      af_delta consumed+knobs, rejects non-finite cla). STATUS.md + CLAUDE.md + [[ewsim-fin-dynamics-direction]]
      updated. **Slice 17 COMPLETE.**
