# Slice 8 — Missile (ballistic): the airframe integrator + `frames.jl`

The **first slice of the missile-guidance arc** (HANDOFF **§10** items 8–13) and the slice
that pays down two long-deferred infrastructure debts at once: it builds and validates the
**Newtonian ODE integrator** (forces → acceleration → velocity → position) and the
**`frames.jl`** shared library (inertial/body/LOS transforms + quaternion algebra) that
slices 9–13 all ride on. Slices 1–7 lit phases 2/3/4 of the tick contract repeatedly but
only ever used phase 1 (`integrate!`) for *trivial kinematics* — `ConstantVelocity`'s
`pos += vel·dt` (`radar.jl:30`). Slice 8 is the **first FORCE-BASED integrator**: a
`BallisticMissile` under gravity (and optional drag) whose `integrate!` solves the airframe
ODE. Its novelty is not a new phase (phase 1 already runs) — it is **real dynamics** where
every prior slice had passive movers, plus the **first `frames.jl`** (built + tested here so
the PID autopilot, proportional-navigation, and seeker slices ride validated frame/LOS code
from day one). Source of truth: `HANDOFF.md` §10 (item 8 — *"Missile — ballistic — build/
validate the integrator + frames here (energy conservation with drag off). Everything later
rides this."*), §9 (the reuse map — *"frames.jl: missile inertial/body/LOS transforms and DF
bearing geometry share it"*; the `estimation.jl` LOS-rate filter and RGPO seeker walk-off ride
later), §3 (the four-phase tick + `env` coupling — the missile is `integrate!`-only here,
`observe!`/`decide!` are slices 9–11), §1 (named approximations; **units/frames/signs are the
bug trifecta** — *"LOS-rate sign errors are the #1 'my missile flies away' bug"* — so
`frames.jl` ships with sign-pinned tests from day one; the integrator's **energy-conservation**
test is the closed-form validation §1 mandates), §11 Tier A (the 6-DOF airframe is a *deferred*
fidelity — see the roadmap deviation below), §12 (the fidelity badge).

The **first lesson is the integrator itself**: dial the integration method and watch the
trajectory's fidelity change. A **4th-order Runge-Kutta** step reproduces constant-gravity
projectile motion **exactly** (RK4 integrates the degree-2 analytic solution to machine
epsilon — a striking clean pin), while **explicit Euler** accumulates an O(dt) position error
(`≈ ½·g·dt·t`) that bows the parabola — *the* "validate your integrator before you trust your
missile" lesson made interactive (HANDOFF §1: *"dialing fidelity and watching what changes IS
the pedagogy"*). The **second lesson is energy accounting**: with **drag off**, total
mechanical energy `E = ½m‖v‖² + m·g·z` is conserved (RK4 → machine eps; the §1-mandated
closed-form validation test); with **drag on**, `E` decreases **monotonically** (dissipation
`Ė = −k‖v‖³ < 0`) and the trajectory shortens — a drag / ballistic-coefficient slider bleeds
energy live. `frames.jl` earns its keep in tests now (quaternion round-trips, the sign-pinned
LOS rate) and — optionally — in the *live* tick (velocity-aligned attitude gives the missile a
nose direction and exercises the zero-vector guard at apex).

**Scope (one lesson per scenario — the slice-3 principle; ONE showcase scenario suffices
here, contrast slice-4/7's two):** a single **ballistic projectile** launched in the **x-z
plane** (downrange × altitude — no cross-range, so it renders in the *existing* slice-1
elevation view) under **flat-earth constant gravity** (`g = 9.80665 m/s²`, `[0,0,−g]`) with
**optional quadratic drag** (constant air density, point-mass — no atmosphere layering, no
attitude dynamics). The switchable **fidelity is the integrator method** `∈ (:rk4, :euler)`
(a possible `:semi_implicit` third rung is a gate-1 probe decision — see Decisions).
`frames.jl` is built **fully 3-D** and tested 3-D (the investment for slices 10–13), even
though this scenario is planar. Explicitly deferred: the **6-DOF airframe** (`fidelity.airframe
= point_mass | 6dof`, HANDOFF §11 Tier A — fin/actuator dynamics, angle-of-attack limits),
**thrust / boost / staging / variable mass** (a passive ballistic body here — a rocket motor is
a later refinement), **layered atmosphere / ducting** (constant `ρ`), **any guidance or seeker**
(no `observe!`/`decide!` — slices 9–11), **round-earth / Coriolis** (the project's frozen
flat-earth stance, §1), and the **live Monte-Carlo dispersion rung** (offline only, a stretch).
3 review gates (mirroring slices 5–7: pure primitives → subsystem wired → scenario + client +
verifiers).

**Done =** start the server on `slice8_ballistic.yaml`, connect Godot, watch (in the
**existing spatial / elevation view**, extended) the missile fly a clean parabola with a fading
trajectory trail and a live **energy readout** (`KE` / `PE` / `E_total` / the conservation
error `ΔE`); drag off + `:rk4` → the parabola is analytic and `ΔE ≈ 0`; cycle the fidelity
button to `:euler` and watch the parabola **bow** and `ΔE` drift off zero (the integrator
lesson); drag the **ballistic-coefficient / drag slider** and watch the range shorten and `E`
bleed (the energy-dissipation lesson); the missile emits an **`:impact` event** and freezes when
it crosses `z = 0` — with `runtests.jl` green on the new closed-form `test_frames.jl` +
`test_missile.jl` (the parabola / convergence-order / energy-conservation / LOS-sign pins) and
slices 1–7 **byte-identical** (`frames.jl`/`missile.jl` add no code to the radar/detection RNG
path; `geometry.jl` is NOT refactored — `frames.jl` is a fresh 3-D sibling; the `_sample_z`
golden + `test_determinism` untouched).

## The physics / math (named approximations — HANDOFF §1)

Point-mass Newtonian dynamics, flat-earth. Everything **SI internally** (metres, m/s, m/s²,
seconds, kg, joules); the launch geometry is authored in convenient units at the loader
(speed m/s, elevation **degrees** → radians — the `sigma_theta_deg`/`beamwidth_deg` boundary
precedent) and stripped to SI. The whole slice is **deterministic — there is NO RNG anywhere**
(the trajectory is a closed-form ODE solve), so unlike every prior slice there is no draw
stream to reason about; the determinism story is *trivial* (same config → bit-identical) and
the fidelity is a *physics-changing* knob (slice-2 `propagation` shape, NOT slice-5/6/7's
RNG-lockstep toggles — see Decisions, and do NOT copy the "toggle-bit-identical" language).

### 1. The airframe ODE + the force model (`missile.jl`, pure force fns; RNG-free)
- **State** = the entity's `(pos, vel)` (SI `Vec3`, inertial frame). The ODE is
  `ṗ = v`, `v̇ = a(p, v)` with the total specific force

      a(v) = g_vec + a_drag(v),   g_vec = [0, 0, −g]   (g = 9.80665 m/s², constant)

- **Gravity — flat-earth constant `g` (named approximation).** A uniform downward field; no
  round-earth / inverse-square / Coriolis (the project's frozen flat-earth/inertial stance,
  HANDOFF §1). Independent of position — so gravity-only motion is *exactly* the degree-2
  parabola `p(t) = p₀ + v₀·t + ½·g_vec·t²`, the closed form the RK4 test pins against.
- **Quadratic aerodynamic drag — constant air density, point-mass (named approximation).**

      a_drag(v) = −(ρ·Cd·A / (2·m))·‖v‖·v  =  −(1/(2·β))·ρ·‖v‖·v

  opposing velocity, magnitude ∝ ‖v‖² (quadratic / Newtonian drag regime). The lumped
  **ballistic coefficient** `β = m/(Cd·A)` (kg/m²) is the natural single knob (larger β →
  less drag → longer range); the drag term is `0` exactly when `Cd·A = 0` (drag off → the
  clean parabola + energy conservation). **Constant `ρ`** (no altitude/atmosphere layering —
  that is HANDOFF §11 Tier A `propagation`-family fidelity); named, not implied.
- **The integrator (the fidelity — pure stepping functions).** One fixed step of size `dt`
  (= `dt_physics`, the guidance-loop rate, HANDOFF §3) advancing `(p, v)`:
  - **`:rk4`** — classical 4-stage Runge-Kutta on the first-order system `(ṗ, v̇) = (v, a(v))`.
    **RK4 is EXACT for constant-gravity projectile motion** (it integrates the degree-2
    polynomial solution with zero truncation error) → gravity-only `:rk4` reproduces the
    analytic parabola to **machine epsilon**. With drag it is the accurate reference (O(dt⁴)
    local error). The default.
  - **`:euler`** — explicit forward Euler (`p += v·dt; v += a·dt`). O(dt) global error; the
    gravity-only position error is **`≈ ½·g·dt·t`** (derived closed-form — pinned in gate 1),
    which bows the parabola visibly at a coarse `dt`. The lesson rung.
  - **`:semi_implicit`** (symplectic Euler, `v += a·dt; p += v_new·dt`) — a possible **third
    rung** (conserves a *nearby* energy → a richer "why symplectic integrators matter" lesson).
    **Gate-1 probe decision** (Decisions); two rungs suffice for the slice.
  - All three are **pure `(p, v, dt) → (p', v')` functions** taking the force closure — no
    world mutation, no RNG — so they are unit-tested closed-form before any subsystem wiring.
- **Ground impact (named terminal condition).** When the step would cross `z = 0` (descending
  through the ground), clamp `z = 0`, zero the velocity, mark `comp[:impacted] = true` (so
  subsequent `integrate!` calls no-op — the frozen splash), and emit an **`:impact` event**
  ONCE (the `w.events` channel — the detection-event precedent). A sub-step impact time is
  *not* root-found (a named approximation — the clamp is within one `dt`, sub-mm at guidance
  rates); name it. The impact must never throw (a straight-up shot that never leaves `z≥0`
  until it falls back is fine; a launch already at `z=0` integrates upward on step 1).

### 2. `frames.jl` — the shared frame / LOS library (HANDOFF §9, pure / RNG-free / no LinearAlgebra)
Built **fully 3-D** and tested 3-D now (the slices 10–13 investment), scoped to exactly what
the guidance/seeker slices need — **do not gold-plate** (advisor). Hand-rolled quaternion +
vector math on `StaticArrays` (the `_range`/`_solve_normal` no-`LinearAlgebra` house style):
- **Quaternion algebra** (the `Quat = SVector{4}` already in `world.jl`, `[w,x,y,z]`,
  `body<-inertial`, identity `[1,0,0,0]`): `qmul(a,b)` (Hamilton product), `qconj(q)` /
  `qinv(q)` (unit-quaternion inverse = conjugate), `qnormalize(q)`, `quat_from_axis_angle(axis,
  θ)`, and **`quat_from_two_vectors(a, b)`** (the minimal rotation aligning `a`→`b` — the
  velocity→attitude builder, with the **antiparallel + zero-vector guards** an apex `v→0` hits).
- **Frame transforms**: `rotate(q, v)` (apply `q` to a `Vec3`) and `rotate_inv(q, v)` — the
  inertial↔body pair. Round-trip `rotate_inv(q, rotate(q, v)) == v` is the day-one §1 test.
- **LOS geometry** (the sign-critical guidance kernel — the #1 "missile flies away" bug class):
  `los_unit(from, to)` (unit line-of-sight, zero-range guard), `range(from, to)`,
  `range_rate(rel_pos, rel_vel)` (closing speed `= (r·v)/‖r‖`, sign convention pinned:
  **negative = closing**), and the **LOS rate vector** `los_rate(rel_pos, rel_vel) = (r × v)/‖r‖²`
  (the ω that PN multiplies by closing velocity — its **SIGN** is pinned against a concrete
  left-to-right crossing geometry, NOT just `‖ω‖`). `az_el(los)` (azimuth = `atan(y, x)`,
  elevation = `atan(z, ‖xy‖)`) for the seeker / sky readouts.
- **§9 reuse-faithfulness pin (advisor — the slice-7 `N=2 == _solve2x2` move):** `frames.jl`'s
  planar azimuth `atan(Δy, Δx)` **equals `geometry.jl`'s `bearing`** on a shared `z=0` example.
  This honors HANDOFF §9 (*"frames.jl and DF bearing geometry share it"*) **without refactoring
  shipped DF code** — `geometry.jl`'s 2-D `bearing`/`wrap_angle` stay byte-identical (the
  slice-7 "keep `linear_ls` 2×2, don't churn shipped code" discipline); `frames.jl` is the 3-D
  superset, conceptually-shared-not-code-merged, and the pin proves the two agree.

### 3. Energy (the "lesson as a number" — the closed-form validation, HANDOFF §1)
- **Total mechanical energy** `E = ½·m·‖v‖² + m·g·z` (KE + flat-earth PE). Published as
  telemetry (`ke_j`, `pe_j`, `e_total_j`) plus the **conservation error** `ΔE = (E − E₀)/E₀`
  (fractional, the load-bearing scalar the verifier pins).
- **Drag off + `:rk4` → `ΔE ≈ 0`** to machine eps over the whole flight (the §1 closed-form
  validation test — necessary, and here nearly exact). **Drag on → `Ė = −(ρ·Cd·A/2)·‖v‖³ < 0`
  → `E` monotonically decreases** (a second clean, sign-guaranteed test). **Euler's *energy*
  drift is phase-dependent** (position lags, velocity is exact for gravity-only) so it is **NOT
  a clean monotonic gain/loss** — the crisp Euler lesson is the **position** error (§1 above),
  not energy; **probe the Euler energy direction, do not assert it** (the slice-2..7
  don't-assert-what-you-haven't-measured discipline).

## Decisions taken (advisor-reviewed 2026-07-01 — architecture endorsed, six sharpenings folded in)
- **The fidelity is the INTEGRATOR method, a roadmap deviation NAMED (advisor #3).** HANDOFF §10
  item 8 sketches `fidelity.airframe = point_mass | 6dof`, but **6-DOF is deferred** (§11 Tier A)
  and a one-value fidelity is a dead button. So the switchable slice-8 fidelity is
  `integrator ∈ (:rk4, :euler)` — the "build/validate the integrator" lesson made interactive
  (RK4 exact vs Euler bowing). The airframe stays **implicitly `point_mass`**; when 6-DOF lands
  it adds the `airframe` fidelity alongside. Flag this deviation explicitly in the docstrings
  (the slice-7 "deviation from the plan sketch, named" discipline).
- **`integrator` is a PHYSICS-CHANGING fidelity (slice-2 `propagation` shape), NOT toggle-bit-
  identical (advisor #1 — the one place copying the slice-5/6/7 template gives a FALSE claim).**
  There is **no RNG in slice 8**, so "RNG lockstep" / "draw-count-invariance" is *vacuous*, not
  a property to prove. State the determinism story as **three distinct claims**, never conflated:
  1. **introduce-safe** — absent a `:missile` entity nothing reads `integrator`, so introducing
     it mid-run on any slice-1..7 scenario is a no-op → slices 1–7 **byte-identical** (the
     include adds no code to the radar/detection path; `_sample_z` golden untouched).
  2. **same-config replay is bit-identical** — deterministic, *trivially* (no RNG to desync).
  3. **a mid-run `integrator` toggle CHANGES the trajectory** (the not-a-dead-knob property) —
     the **opposite** of slices 5/6/7's toggle invariance; say so explicitly. (Introducing on a
     *missile* scenario likewise changes the physics going forward — that is correct and the
     point.) The determinism test therefore pins (1) + (2); the toggle test pins (3).
- **Primary gate-1 test = the CLOSED-FORM PARABOLA, not energy conservation (advisor #2 — energy
  is necessary but not sufficient, and near-trivial for RK4).** The gate-1 matrix:
  - **RK4 gravity-only `== analytic parabola`** `p₀+v₀t+½g_vec·t²` to **machine eps** (the
    striking exact pin);
  - **Euler gravity-only position error `≈ ½·g·dt·t`** — pin magnitude AND that it is O(dt);
  - **convergence-order test** (halve `dt` → RK4 error ÷≈16, Euler error ÷≈2) — proves RK4 is
    genuinely 4th-order and not a mislabeled RK2 (a "don't self-calibrate — external anchor"
    check, the slice-2/3/4/5/6 rule);
  - **energy**: RK4 drag-off conserves to machine eps; **drag-on `E` monotonically decreases**
    (sign-guaranteed dissipation); **Euler energy direction PROBED, not asserted** (phase-
    dependent).
- **`frames.jl` built 3-D + tested 3-D now, scoped tight, DF code NOT refactored (advisor #5).**
  The frame/LOS lib is the slices-10–13 investment; build the full 3-D quaternion/LOS kernel and
  test it closed-form (round-trips, known rotations, the **sign-pinned** LOS rate), but **do not
  gold-plate** — ship exactly `rotate`/`rotate_inv`, `quat_from_two_vectors`, `los_unit`/`range`/
  `range_rate`/`los_rate`/`az_el`, and the quaternion algebra they need. **`geometry.jl` is left
  byte-identical** (its 2-D `bearing`/`wrap_angle` are the planar DF special case; `frames.jl` is
  the 3-D superset — conceptually shared, not code-merged, the slice-7 "keep the shipped 2×2
  path" discipline). The **azimuth == `bearing`** pin (math §2) is the §9 reuse proof.
- **Velocity-aligned attitude — OPTIONAL, exercises `frames.jl` in the LIVE tick (advisor #6).**
  A point-mass ballistic `att` is not dynamically coupled, but setting `att` kinematically each
  step to point body-x along `v` (via `quat_from_two_vectors([1,0,0], v̂)`) exercises `frames.jl`
  in the *live* tick (not just tests), gives Godot a nose direction, and naturally hits the
  **zero-vector guard** at apex (`v→0` on a straight-up shot). **If cheap, do it**; otherwise
  `att = identity` and `frames.jl` stays test-only until the PID slice (10). Decide at gate 2.
- **New `:missile` kind + `BallisticMissile` subsystem (`integrate!` ONLY).** The entity carries
  `ConstantVelocity`? **No** — a force-integrated body must NOT also be moved by the passive
  `ConstantVelocity` mover (double-integration). `BallisticMissile` **is** the phase-1 mover
  (it owns `pos`/`vel` advancement); the loader gives a `:missile` entity `[BallisticMissile]`,
  not `[ConstantVelocity, BallisticMissile]`. `comp`: `:mass_kg`, `:cd_area_m2` (the lumped
  `Cd·A`, so drag off = `0`) or `:ballistic_coeff` (pick one at gate 1 — `Cd·A` is the more
  primitive; `β = m/(Cd·A)` derived), `:rho` (air density, default `1.225`), plus the launch
  state in `pos`/`vel`. Antenna/EP-style **defaults at the consumer** so a bare `:missile`
  block can't `KeyError` a tick (the "a live config can't crash a tick" watch-item).
- **Live sliders + the fidelity button.** Slider knobs: **launch speed**, **launch elevation
  (deg)**, and the **drag / ballistic-coefficient** (the energy-bleed lever). The `integrator`
  method is the **fidelity button** (cycler `:rk4 ↔ :euler`, +`:semi_implicit` if the third rung
  lands), NOT a slider. `g`, `ρ`, `mass` are LOAD-TIME static (or `ρ`/`mass` sliders if a probe
  shows they teach — default static). **NB re-launching:** changing launch speed/angle mid-flight
  is ill-defined (the missile is already flying); the sliders take effect on **`reset`** (which
  reloads the YAML → re-launches) — document it, the slice-2 "reset reloads the scenario"
  precedent. (A live in-flight slider that teaches — the drag coefficient — changes the *force*,
  which IS well-defined mid-flight; launch geometry is not.)
- **Reuse the EXISTING spatial / elevation view — NO new render mode (advisor-endorsed shape,
  the slice-4 "stay spatial" precedent).** A ballistic parabola is downrange × altitude — exactly
  the slice-1 `_draw_spatial` axes. Extend it with a **missile marker** (a nose-oriented triangle
  if velocity-aligned attitude lands, else a dot), a **fading trajectory trail** (breadcrumbs),
  an **impact marker** at `z=0`, and the **energy readout** (`KE`/`PE`/`E_total`/`ΔE`). The
  fidelity button becomes the `integrator` cycler. Contrast slices 3/5/6/7 (each needed a *new*
  view); slice 8 does not. The `integrator` badge reads from the local fidelity copy + resyncs on
  reset (the slice-2 pattern). The energy time-series *plot* (Euler-vs-RK4 `E(t)`) is the **Pluto
  stretch**, not the live view.
- **No-missile scenarios stay byte-identical.** Absent a `:missile`, no `BallisticMissile` runs,
  `integrator` is unread, and `frames.jl`/`missile.jl` add nothing to the radar/jammer/DF/ESM/GPS
  paths. Slices 1–7 (and `test_determinism`, the `_sample_z` golden) stay byte-identical — pin
  it. A slice-8 scenario has **no radar/jammer/DF/ESM/GPS** (missile + sensors fuse in the
  countermeasures slice, §10 item 12 — a future slice).

## Review gates (cadence: staged, mirroring slices 5–7)
1. **Primitives green (pure, closed-form, SI, RNG-free, no `LinearAlgebra`).** `frames.jl` (the
   3-D quaternion/frame/LOS kernel) + the `missile.jl` force model + the integrator stepping
   functions, all pure — before any subsystem wiring.
   - **`frames.jl`** — `qmul`/`qconj`/`qinv`/`qnormalize`/`quat_from_axis_angle`/
     `quat_from_two_vectors`, `rotate`/`rotate_inv`, `los_unit`/`range`/`range_rate`/`los_rate`/
     `az_el`. Included in `EWSim.jl` **before `radar.jl`** (a pure §9 lib the later subsystems
     reuse; alongside `geometry.jl`/`estimation.jl`); exported.
   - **`missile.jl` force + steppers** — `gravity_accel()`, `drag_accel(v; rho, cd_area, mass)`,
     `total_accel(v; …)`, and pure `rk4_step`/`euler_step`(/`semi_implicit_step`?) taking the
     force closure + `(p, v, dt)`. (The `BallisticMissile` *subsystem* is gate 2; gate 1 is the
     math.) The `INTEGRATOR_MODES = (:rk4, :euler[, :semi_implicit])` source-of-truth const lives
     here (the `ESTIMATOR_MODES`/`GPS_TOGGLE` "mode-const-before-radar, one-list-no-drift"
     precedent, so `LIVE_FIDELITY_MODES` can reference it).
   - `test_frames.jl` + `test_missile.jl` — closed-form, slice-2 style (**explicit `atol`**,
     never rtol-`≈0`), wired into `runtests.jl` after `test_geometry.jl`/`test_estimation.jl`:
     - **frames**: quaternion round-trip (`rotate_inv(q, rotate(q,v)) == v`; `qmul(q, qinv(q)) ==
       identity`); known rotations (90° about ẑ sends x̂→ŷ, sign-checked); `quat_from_two_vectors`
       aligns `a`→`b` (+ the **antiparallel** and **zero-vector** guards); **the LOS-rate SIGN**
       pinned on a concrete crossing geometry (target passing left→right at a known range/closing
       → `los_rate` of a KNOWN sign, not just magnitude — the #1 "missile flies away" bug);
       `range_rate` sign (negative = closing); **`az_el`/azimuth == `geometry.jl` `bearing`** on a
       shared `z=0` example (the §9 reuse-faithfulness pin).
     - **missile**: **RK4 gravity-only == analytic parabola to machine eps** (the headline);
       **Euler position error `≈ ½·g·dt·t`** (magnitude + O(dt)); **convergence order** (halve dt
       → RK4 ÷≈16, Euler ÷≈2 — the external anchor that RK4 is 4th-order); **energy conservation**
       (RK4 drag-off `ΔE ≈ 0` machine eps; **drag-on `E` strictly decreasing**); the drag term is
       `0` exactly at `cd_area = 0` (drag off ≡ free ballistic); Euler energy direction **PROBED
       and recorded as a comment**, not asserted; degenerate guards (straight-up shot `v→0` at
       apex, launch at `z=0`, huge `dt` → no throw / no NaN).
     - **Byte-identity**: `frames.jl`/`missile.jl` touch no radar/detection symbol → slices 1–7
       green through the include, `_sample_z` golden + `test_determinism` untouched. Pin it.
     - **Numbers probed with a throwaway harness first** (the slice-3..7 rule): confirm the Euler
       drift is *visible* at the scenario's `dt`/flight-time (else the readout, not the parabola,
       carries the live lesson), and **decide `:semi_implicit`** (probe whether its energy
       behavior teaches enough to earn a third rung; two rungs suffice).
2. **The missile wired (phase 1 — the first force-based integrator in the tick loop).**
   `BallisticMissile <: Subsystem` in a new `missile.jl` (the subsystem half; the force fns may
   live in `missile.jl` or a `dynamics.jl` split — one file is fine), included **after `radar.jl`**
   (mirroring `geolocation.jl`/`esm.jl`/`gps.jl`; **verify no back-dep on radar symbols** — it
   reuses `frames.jl` + `world.jl` only). `integrate!(m::BallisticMissile, w, dt)` dispatches on
   `get(w.fidelity, :integrator, :rk4)`, steps `(pos, vel)` via the gate-1 stepper under
   `total_accel`, handles the `z=0` **impact clamp + one-shot `:impact` event**, and (optionally)
   sets velocity-aligned `att`. `LIVE_FIDELITY_MODES` (radar.jl) gains `integrator =
   INTEGRATOR_MODES` (referencing the gate-1 const — one-list-no-drift; the fidelity plumbing
   lands here, the slice-5/6/7 gate-2 precedent — introduce-safe, no draw hazard, the subsystem
   actually consumes the key). `:missile` kind + `_build_entity` arm + `_validate_missile` (≥1
   `:missile`, positive `mass`/`ρ`, non-negative `cd_area`, GPS-style at LOAD; triggered by
   missile-entity presence so non-missile scenarios are untouched) in `scenario.jl`; unknown-kind
   list updated. Telemetry (phase-1 writes into `env[:telemetry]` like the radar readout):
   `<id>.pos_x/.pos_z/.speed/.alt/.ke_j/.pe_j/.e_total_j/.de_frac/.impacted` — all `_finite`-
   clamped (reuse `geometry.jl`'s `_finite`). **No static handshake axis** (the missile moves,
   like GPS's satellites — the client discriminates the missile view off the **`integrator ∈
   fidelity`** handshake key, the `range_axis_m`→cfar / `raim`→gps precedent — though slice 8
   stays in the *spatial* view, so the discriminator only wires the integrator button, it does
   NOT switch render mode).
   - `test_missile.jl` (+ the wired half): `BallisticMissile.integrate!` advances `(pos,vel)`
     matching the gate-1 stepper on a realized step; the `:rk4` wired trajectory == the analytic
     parabola (drag off); the **`:euler` wired trajectory differs** (the fidelity is live — the
     not-a-dead-knob); the **impact event** fires exactly once at `z=0` + freezes the entity;
     energy telemetry matches `½m‖v‖²+mgz`; finite telemetry incl. a degenerate straight-up /
     already-impacted case (no throw); loader arms + rejects (missing `mass`, negative `cd_area`).
   - `test_determinism.jl` + a slice-8 scenario: **same-config replay bit-identical** trajectory
     trace (`reinterpret` fingerprint of the `pos`/`vel` stream — the slice-6/7 sharper-than-a-
     scalar pin); **introduce `:integrator` on a NON-missile world → byte-identical** (claim 1);
     **a mid-run `:integrator` toggle CHANGES the trajectory** (claim 3 — the explicit *opposite*
     of the slice-5/6/7 toggle-invariance; assert the two runs *differ* after the toggle, both
     internally deterministic). NB **no RNG** → there is no "rng end-state" to compare (claim 2 is
     the bit-identical replay itself); do not write a vacuous rng-lockstep assertion.
   - `test_server.jl`: `set_fidelity :integrator` write/reject (validated by the per-key table,
     no server change — introduce-safe, the `:ep`/`:estimator`/`:deinterleaver` contract, NOT
     `:cfar`'s guard); `warmup!` tolerates a **radar-free missile scenario** (the ROC batch is
     skipped — the slice-5 `warmup!` radar-guard already covers this; the `tick!`+`state_frame`
     warm exercises the phase-1 integrator + energy telemetry). Slices 1–7 byte-identical.
3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice8_ballistic.yaml` — a
   single projectile launched in the x-z plane (a probe-tuned speed/elevation giving a legible
   multi-second arc that fits the view), **drag off** + **`:rk4`** default (so the connect-state is
   the clean conserved parabola — the lesson is what the toggles/sliders REVEAL), the launch-speed
   / elevation / drag sliders, `integrator` the fidelity button. **Numbers probed against the LIVE
   `integrate!`→telemetry wire path** (the slice-3..7 rule) + reproduced through the loader; pin the
   probed values (apex, range, flight time, `ΔE` under each rung) as comments.
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode) — a `:missile`-kind
     marker + fading trajectory trail + impact marker + the energy readout; the shared fidelity
     button wired to `_on_integrator_pressed` (the `:rk4↔:euler` ring, guarded disconnect like
     cfar/ep/est/deint/raim). `_update_readout` renders the energy scalars (all scalars — no Array
     telemetry, so no `float()`-crash risk, but re-confirm). The slice-1..7 views UNTOUCHED (re-run
     every smoke-load + UI test — all pass).
   - `net/slice8_verify.gd` (drives the real server): the `:rk4` trajectory tracks the analytic
     parabola + `ΔE ≈ 0` (drag off); `set_fidelity integrator :euler` **bows the trajectory** (the
     apex/range/`ΔE` shift measurably — the fidelity-as-a-number, `t` bit-identical under the held
     config); the **drag slider** (`set_param` on `cd_area`/`ballistic_coeff`) **bleeds energy**
     (`ΔE` goes negative, range shortens — the not-a-dead-knob energy lever); the **`:impact`
     event** fires once and `impacted` latches. All assertions on the SCALARS. `S8V OK`, exit 0.
     **Verifier mechanics**: step counts are MULTIPLES of `emit_every` so the last emit lands on
     the target `t` (the slice-2/6/7 drain contract — an off-multiple count times out).
   - `net/slice8_ui_test.gd` (mock client, no server: a missile handshake wires the `integrator`
     cycler; the ring walks `:rk4→:euler` and wraps; badge/button track; the drag/launch sliders
     send `set_param`; reset resyncs the rung + sliders to defaults — `S8UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-8 server (server `DONE` ⇒ scene
     connected on the missile branch, no GDScript errors — catches missile-branch parse bugs the
     SimClient verifier can't).
   - `test_scenario.jl` + a slice-8 loader testset (parses; `:rk4` integrator default; NO
     radar/jammer/DF/ESM/GPS fidelity or entities; exactly the `:missile` entity with `BallisticMissile`
     and **NOT** `ConstantVelocity` [the double-integration guard — the discriminating check];
     launch state stored SI [speed m/s, elevation **deg→rad** converted — `haskey`/value pin, the
     slice-4/6/7 "keys equal defaults so haskey is the discriminating check" rule]; drag/launch
     knobs address the right comp keys; `integrator` not a knob).
   - The **`_draw` missile PIXEL branch** (Godot skips `_draw` headless) **visually confirmed** via
     the windowed shot harness (the slice-3..7 technique, [[ewsim-godot-headless]]): the `:rk4`
     clean parabola + trail + energy readout; the `:euler` bowed parabola (or, if the drift is
     sub-pixel at this `dt`, the `ΔE` readout carries it — probe at gate 3); the impact marker at
     `z=0`. **(stretch, deferred)** `clients/notebooks/slice8_energy.jl` Pluto — `E(t)` for
     `:euler` vs `:rk4` (drag off) + the trajectory overlay, the integrator lesson as a *curve*;
     and/or an offline `batch.jl` `kind = :dispersion` (a Monte-Carlo launch-scatter — the FIRST
     use of RNG in the missile arc, a natural bridge to slice-9's noisy autopilot). NOT a live rung.

## Task checklist
- [x] 1. **Primitives (pure, SI, RNG-free, no LinearAlgebra).** DONE & green (1562 tests, +70).
      Split into `frames.jl` (3-D quaternion/frame/LOS kernel — `qmul`/`qconj`/`qinv`/`qnormalize`/
      `quat_from_axis_angle`/`quat_from_two_vectors` + antiparallel & zero-vector guards, `rotate`/
      `rotate_inv`, `los_unit`/`los_range`/`range_rate`/`los_rate`/`az_el`; reuses gnss.jl's
      module-level `_norm3`, adds `_dot`/`_cross`) + `dynamics.jl` (`gravity_accel`/`drag_accel`/
      `total_accel`, pure `rk4_step`/`euler_step`/`integrator_step`, `INTEGRATOR_MODES=(:rk4,:euler)`),
      BOTH included before `radar.jl` (the mode-const-before-radar rule; `LIVE_FIDELITY_MODES` will
      reference `INTEGRATOR_MODES` in gate 2). **Resolved a plan contradiction (INTEGRATOR_MODES must
      precede radar.jl, but the sketch put it in the after-radar missile.jl): used the sanctioned
      `dynamics.jl` split — pure lib before radar, subsystem `missile.jl` after (gate 2), matching the
      deinterleave→esm / gnss→gps convention exactly.** `los_range` (not bare `range`) avoids shadowing
      `Base.range` (named deviation). `test_frames.jl` (43: round-trips, 90° rotations sign-checked,
      quat_from_two_vectors + both guards, **LOS-rate SIGN** on a left→right crossing (+ẑ, value 0.05),
      range_rate sign (neg=closing), azimuth==`bearing` §9 pin) + `test_missile.jl` (27: drag-off EXACTLY
      zero, **RK4==analytic parabola rtol 1e-11**, **Euler position error EXACTLY ½·g·dt·t** — analytically
      exact for constant accel, not just leading-order — + O(dt) at fixed T, **convergence ÷16 RK4 / ÷2
      Euler** in a coarse-dt strong-drag regime (pure-parabola RK4 truncation is ZERO → only roundoff,
      which won't halve — the subtle bit), energy RK4 drag-off machine-eps + drag-on strictly decreasing,
      degenerate guards). **Probe decisions:** Euler drift is dramatically visible (2.1 m z-lag at dt=0.01
      over a 43 s flight); **`:semi_implicit` REJECTED** — two rungs suffice (Euler = the position-error
      lesson, RK4 = the exact reference); Euler drag-off energy drifts UPWARD (~+0.05%, phase-dependent)
      → probed as a comment, NOT asserted. Slices 1–7 byte-identical (frames/dynamics touch no
      radar/detection path; `_sample_z` golden + `test_determinism` green through the include).
- [x] 2. **The missile wired (phase 1 — first force-based integrator).** DONE & green (1609 tests,
      +47). `BallisticMissile` in `missile.jl` (included after `gps.jl`, before `scenario.jl`; **no
      radar back-dep** — reuses only `dynamics.jl`/`frames.jl`/gnss's `_norm3`/geometry's
      `_finite`/`_finite_coord`, grep-confirmed). `integrate!` (phase 1) dispatches
      `get(w.fidelity, :integrator, :rk4)` → `integrator_step` under `total_accel`, does the `z≤0`
      impact clamp (within-`dt`, named approx) + one-shot `:impact` event (pushed to `w.events`, NOT
      env — so not wiped by `empty!(w.env)`) + `:impacted` latch (frozen splash), and sets a
      velocity-aligned `att` (`quat_from_two_vectors([1,0,0], v′)` — exercises `frames.jl` live +
      its apex `v→0` zero-vector guard → identity). **TELEMETRY-PHASE DEVIATION (advisor-confirmed):
      the plan's "phase-1 writes into env[:telemetry]" is WRONG — `tick!` calls `empty!(w.env)`
      immediately after phase 1, wiping it (and the radar readout is actually phase-3 observe!). So
      the energy/position readout is published from `build_env!` (phase 2, post-empty!, reading the
      post-integrate state) — a DERIVED quantity, RNG-free, own-keys → order-independent; NOT a
      sensing/guidance phase (observe!/decide! stay EMPTY for slices 9–11).** Telemetry (all
      `_finite`/`_finite_coord`-clamped): `<id>.pos_x/.pos_z/.speed/.alt/.ke_j/.pe_j/.e_total_j/
      .de_frac/.impacted`; `E₀` (the ΔE reference) lazily set on the first tick from the launch
      state (survives reset for free). `LIVE_FIDELITY_MODES += integrator = INTEGRATOR_MODES`
      (referencing dynamics.jl's const — one-list-no-drift; introduce-safe, NO `:cfar`-style guard,
      but **physics-changing NOT toggle-bit-identical** — the comment states the split explicitly).
      `:missile` kind + `_validate_missile` in `scenario.jl` (the entity gets `[BallisticMissile]`,
      **NOT** `ConstantVelocity` — the double-integration guard; `missile:` block → `mass_kg`,
      `speed`/`elevation_deg` [deg→rad, x-z-plane `vel`; stored RAW too so gate-3 launch knobs can
      address them], `cd_area_m2` [drag off = 0], optional `rho`; positive-mass / non-negative
      cd_area/ρ rejected at LOAD). `test_missile.jl` wired half (+20: integrate! == gate-1 stepper
      bit-exact; rk4 WIRED == analytic parabola / euler bows by ½·g·dt·t / trajectories differ;
      impact fires ONCE + freezes + no-op after / launch-at-z=0-rises-not-insta-impacts; energy
      telemetry == ½m‖v‖²+mgz every step + ΔE<1e-10 rk4 drag-off + ΔE<0 drag-on; finite telemetry +
      att-never-NaN through apex; loader gets BallisticMissile NOT ConstantVelocity + rejects missing
      mass / negative cd_area). `test_determinism.jl` (+1 testset: (2) same-config replay
      bit-identical via `reinterpret`; (3) mid-run rk4→euler toggle CHANGES the flight — the
      not-a-dead-knob, slice-5/6/7 opposite; (1) introduce `:integrator` on a NON-missile
      RandomWalker world → byte-identical + rng untouched. **NB advisor #1: no RNG in slice 8, so no
      vacuous rng-lockstep assertion — the three claims are pinned distinctly**). `test_server.jl`
      (+2: `set_fidelity integrator` write/reject [bad rung rejected] + introduce-safe on a plain
      radar scenario; `warmup!` tolerates a radar-free missile scenario — ROC batch skipped, phase-1
      integrator + phase-2 telemetry warmed, live World pristine). Slices 1–7 **byte-identical** (the
      `_sample_z` golden + all prior testsets green through the include). Gate 3 (scenario + Godot
      spatial-view extension + verifiers) is next.
- [ ] 3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice8_ballistic.yaml`
      (probe-tuned, drag-off + `:rk4` default, launch/drag sliders). **GATE-2 CARRY-OVER FLAGS
      (advisor):** (a) **launch speed/elevation sliders are NOT achievable via reset** — `_reload!`
      reloads from the YAML FILE, discarding any live `set_param` to `comp[:speed]`/
      `comp[:elevation_deg]`, and nothing re-derives `vel` mid-flight, so only **`cd_area`** is a
      working live lever. The raw keys ARE stored (a knob can address them), but decide at gate 3:
      make launch geometry load-time-static (document "edit YAML + reconnect") OR add a genuine
      re-launch mechanism — do NOT declare launch sliders "working" per the plan's stale wording;
      VERIFY the reset behavior yourself. (b) **No t=0 telemetry frame** — the first `build_env!`
      runs after the first `integrate!`, so the verifier must sample ΔE/energy after **≥1 step** (and
      MID-FLIGHT, not post-impact where `de_frac = −1`). `Sandbox.gd` spatial view
      EXTENDED (missile marker + trail + impact + energy readout; the shared button → integrator
      cycler; NO new render mode). `net/slice8_verify.gd` (rk4 parabola + ΔE≈0; euler bows it;
      drag slider bleeds E; impact event once — S8V OK). `net/slice8_ui_test.gd` (integrator ring
      walks/wraps, sliders send set_param, reset resyncs — S8UI OK). `Sandbox.tscn` smoke-loaded
      headless vs the slice-8 server. `test_scenario.jl` loader testset (integrator default, no
      other fidelity/entities, `:missile` NOT `ConstantVelocity`, deg→rad launch pin). `_draw`
      missile branch VISUALLY CONFIRMED via the shot harness. **(stretch)** `slice8_energy.jl`
      Pluto E(t) overlay + `:dispersion` MC batch.

## Context / landmarks
- **This lights NO new phase — phase 1 (`integrate!`) already runs** (`subsystem.jl:28`,
  `ConstantVelocity.integrate!` at `radar.jl:30`). Slice 8's novelty is the **first FORCE-BASED**
  integrator (a Newtonian ODE, forces→accel) and the **first `frames.jl`** — not a phase first.
  The plan's intro celebrates the real-dynamics + shared-lib investment, not a contract change.
- **The subsystem template** is any `integrate!`-only mover — `ConstantVelocity` (`radar.jl:16–34`)
  is the minimal shape (config struct + `w.entities`/`comp` state + `integrate!`). Copy it, swap
  the trivial `pos += vel·dt` for the force-integrated step + telemetry + impact handling. The
  **later `observe!`/`decide!` half is slices 9–11** — do NOT add them here.
- **`frames.jl` is a NEW HANDOFF §9 shared lib** (the `geometry.jl`/`estimation.jl`/`gnss.jl`
  analog — pure, no RNG, closed-form, dependency-free base Julia + `StaticArrays`, **no
  `LinearAlgebra`**). It slots alongside `geometry.jl` (pure, before `radar.jl`). `Quat =
  SVector{4,Float64}` + `att` (`body<-inertial`, identity `[1,0,0,0]`) already exist in
  `world.jl:22,29` — build the algebra on them, don't redefine.
- **Include order** is `… detection → geometry → estimation → deinterleave → gnss → radar →
  geolocation → esm → gps → scenario → batch → server` (`EWSim.jl`). Slot **`frames.jl` before
  `radar.jl`** (pure, defines `INTEGRATOR_MODES` that `LIVE_FIDELITY_MODES` references; the force
  fns can sit in `frames.jl` or a small `dynamics.jl` — or fold into `missile.jl` if the pure fns
  and the subsystem cohabit cleanly) and **`missile.jl` after `radar.jl`** (the subsystem,
  mirroring `geolocation.jl`/`esm.jl`/`gps.jl`). **Verify at gate 2 the missile has no back-dep on
  radar symbols.**
- **The fidelity table** is `LIVE_FIDELITY_MODES` (`radar.jl`), validated by `set_fidelity`
  (`server.jl:160`). Add `integrator = INTEGRATOR_MODES`. **No introduce-guard** — the `:cfar`
  guard (`server.jl:177`) doesn't match it (introduce-safe, the `:ep`/`:estimator`/`:deinterleaver`
  contract). **But UNLIKE those, a toggle CHANGES the trajectory** (physics-changing, slice-2
  `propagation` shape) — introduce-safe ≠ toggle-invariant here; keep the two ideas separate.
- **The loader** `_build_entity` (`scenario.jl`) is the `kind`-dispatch — add `:missile` (a
  `missile:` block → `pos`, launch `speed`/`elevation_deg` → `vel = speed·[cos,0,sin]` in the x-z
  plane, `mass_kg`, `cd_area_m2` [drag off = 0], optional `rho`; + `[BallisticMissile]`, **NOT**
  `ConstantVelocity`). Update the unknown-kind error list. `_validate_missile` (≈ `_validate_gps`)
  at LOAD, missile-presence-triggered.
- **Telemetry → wire** is generic (`protocol.jl` `state_frame` reads `env[:telemetry]`). The
  missile scalars serialize like the radar readout; reuse `geometry.jl`'s `_finite`. All scalars
  (no display arrays this slice), so no `_update_readout` Array-skip needed — but re-confirm.
- **The spatial view is `_draw_spatial`** (slice-1, downrange×altitude) — extend it for the
  missile (marker/trail/impact/energy), the slice-4 "stay spatial, add an arm" precedent. The
  `_fid_kind` discriminator gains a `missile`/`integrator` case that wires the button WITHOUT
  switching render mode (the missile view IS the spatial view).
- **Units (the §1 trifecta):** positions/velocities SI (m, m/s), energy in **joules**, launch
  **elevation authored in degrees → radians** at the loader (the `sigma_theta_deg` precedent),
  `g`/`ρ` SI constants. **Frames/signs are the co-headline trifecta here** — `frames.jl` ships
  sign-pinned LOS/round-trip tests from day one (HANDOFF §1: LOS-rate sign = the #1 missile bug).

## Watch-items (gotchas to bake in)
- **`integrator` is PHYSICS-CHANGING, not toggle-invariant — do NOT copy the slice-5/6/7 "toggle-
  bit-identical" language (advisor #1, the template-copy hazard).** There is no RNG in slice 8, so
  "draw-count-invariance"/"rng lockstep" is vacuous. The three separate claims: (1) introduce-safe
  (no-op absent a missile → slices 1–7 byte-identical); (2) same-config replay bit-identical
  (deterministic, no RNG to desync); (3) a mid-run toggle CHANGES the trajectory (not-a-dead-knob —
  the *opposite* of the last three slices). Pin all three distinctly; never assert a vacuous
  rng-lockstep.
- **No double integration.** A `:missile` gets `BallisticMissile` (which owns `pos`/`vel`
  advancement) and **NOT** `ConstantVelocity` — two phase-1 movers on one entity would advance
  `pos` twice. Pin it in the loader test (the missile's subsystem list excludes `ConstantVelocity`).
- **RK4 exactness is the pin, not just conservation (advisor #2).** RK4 reproduces the constant-g
  parabola to machine eps (it integrates the degree-2 solution exactly) — assert `== analytic` to
  ~1e-9, not merely `ΔE small`. Energy conservation is necessary-not-sufficient. The convergence-
  order test (÷16 / ÷2 on halving dt) is the external anchor that RK4 isn't a mislabeled RK2.
- **Euler's ENERGY drift is phase-dependent — probe, don't assert (advisor #2).** For gravity-only,
  Euler's velocity is exact but position lags, so energy is not cleanly monotonic. The crisp Euler
  lesson is the **position** error (`≈½g·dt·t`, O(dt)); pin THAT. Record the probed Euler-energy
  direction as a comment, not a test assertion.
- **LOS-rate SIGN, not magnitude (advisor #5, the #1 bug class).** `test_frames.jl` must pin the
  *sign* of `los_rate` on a concrete left-to-right crossing (a magnitude-only test misses exactly
  the "missile flies away" bug HANDOFF §1 warns about). Same for `range_rate` (negative = closing).
- **`quat_from_two_vectors` guards.** The antiparallel case (rotation axis undefined — pick any
  perpendicular) and the zero-vector case (`v→0` at apex on a straight-up shot) must not throw / NaN.
  The velocity-aligned-attitude option hits the zero-vector guard live — test it.
- **Ground impact must never throw and fires ONCE.** The `z=0` clamp + `:impact` event + `impacted`
  latch: a descending step clamps to `z=0`, freezes, emits one event; subsequent ticks no-op. A
  launch at `z=0` integrates upward on step 1 (don't insta-impact); a straight-up shot impacts on
  the way back down. Pin the once-only + no-throw.
- **Don't refactor `geometry.jl` (advisor #5, the slice-7 discipline).** `frames.jl` is the 3-D
  superset; `geometry.jl`'s 2-D `bearing`/`wrap_angle` stay byte-identical (shipped DF code). Prove
  agreement with the azimuth==`bearing` pin, don't code-merge — keeps slices 5–7 byte-identical.
- **Launch-geometry sliders take effect on RESET, not mid-flight.** Changing launch speed/angle
  while the missile is airborne is ill-defined; those sliders reload via `reset` (the slice-2
  "reset reloads the YAML" precedent). The **drag** slider IS well-defined mid-flight (it changes
  the force) — that one is the live in-flight lever. Document the distinction.
- **A live config can't crash a tick.** Missile `comp` keys read with **defaults at the consumer**
  (`:rho`=1.225, `:cd_area`=0, etc.) so toggling `:integrator` onto any scenario or a bare
  `:missile` block can't `KeyError`. The loader rejects a malformed AUTHORED missile (missing mass,
  negative `cd_area`/`rho`) at LOAD.
- **Roadmap deviation NAMED (advisor #3).** §10 sketches `airframe = point_mass | 6dof`; slice 8
  ships `integrator = (:rk4, :euler)` instead (6dof deferred, §11 Tier A; a one-value fidelity is a
  dead button). State it in the docstrings — the slice-7 "deviation from the sketch, flagged" rule.
- **Named approximations, stated (no hidden ones — HANDOFF §1):** flat-earth constant `g` (no
  round-earth/Coriolis/inverse-square), constant air density `ρ` (no atmosphere layering),
  point-mass (no attitude dynamics — `att` is kinematic-only, if set), quadratic drag lumped into a
  ballistic coefficient, within-`dt` impact clamp (no sub-step root-find), passive body (no
  thrust/staging/variable mass). Name each in the docstrings.
- **Deferred to future slices, explicitly NOT here:** the 6-DOF airframe (§11 Tier A), thrust /
  boost / staging / variable mass, layered atmosphere, ANY guidance or seeker (`observe!`/`decide!`
  — slices 9–11), round-earth / Coriolis, sensor↔missile fusion (§10 item 12), and the live MC
  dispersion rung (offline stretch only). Listing them keeps the slice-8 boundary honest.
