# Slice 11 — Missile: noisy seeker + LOS-rate filtering (the first missile `observe!`)

The **first slice of the seeker arc** (HANDOFF **§10 item 11** — *"Seeker models — RF/IR seekers feeding
noisy LOS rate → `estimation.jl` filter"*). Slice 10 closed the missile-guidance arc with proportional
navigation reading **target truth** (`pn_accel` computes `ω = r×v/‖r‖²` from the target's true pos/vel —
guidance.jl:126 says so explicitly: *"Reads target truth (ω from truth pos/vel — no seeker, slice 11)"*).
Slice 11 replaces that truth-feed with a **real seeker**: the missile *measures* the line-of-sight with
**angular noise**, and PN's `ω` must be **estimated from that noisy measurement** rather than known. The
lesson is that **naïvely differentiating a noisy LOS angle is catastrophic** (PN multiplies `λ̇` by the
large closing speed `Vc`, so tiny angle noise → wild acceleration commands → the missile jitters, the
`a_max` clamp pegs, the miss opens) and a **filter** (an α-β tracker — the `estimation.jl` filter HANDOFF
§10.11 names) **recovers** the intercept. Source of truth: HANDOFF §10 item 11.

**Scope RATIFIED WITH THE USER (2026-07-02): slice 11 = seeker + LOS-rate filter ONLY.** CLAUDE.md's
prior roadmap note bundled three features (noisy seeker + filter **+ augmented PN against a maneuvering
target**). The user approved **splitting**: **augmented PN + the maneuvering target move to slice 12**
(the RNG-free extension of slice 10's ~2g gravity floor, and what roadmap item 12/countermeasures builds
on). Rationale (advisor-endorsed): HANDOFF §10 item 11 is *literally* only "seeker models → estimation.jl
filter"; the seeker introduces the **first RNG into the missile arc** (a determinism-discipline inflection
worth isolating); APN needs a new maneuvering *mover* and is cleanly separable. This slice lights the
**missile's first phase-3 `observe!`** — missile.jl's own comment anticipated it: *"observe!/decide! stay
EMPTY here — guidance / seekers are slices 9–11"* (missile.jl:11). **"A missile is `integrate!` +
`observe!` + `decide!`" (HANDOFF §3) is COMPLETE after this slice.**

## The lesson (shown as numbers)

**Noisy λ̇ blows PN up; an α-β filter recovers it.** Against the SAME crossing engagement slice 10 used
(PN, `autopilot = :ideal`, a constant-velocity target — no maneuver, so this is *purely* the seeker
lesson, not APN):

- **Raw (unfiltered) seeker → the miss explodes.** The seeker measures the LOS direction with 1-σ angular
  noise `σ_seek`. Recovering `λ̇` by finite-differencing consecutive noisy angles amplifies the noise by
  `1/dt` (at `dt = 1e-3`, `σ_seek = 1 mrad → ω`-noise ~1 rad/s **per sample**). PN's command
  `N·Vc·(ω×û)` then carries `N·Vc·(σ/dt)` of pure noise — e.g. `4·800·1 ≈ 3200 m/s²` — so the **`a_demand`
  pegs at `a_max` almost every tick, `saturated` stays lit** (the slice-10 saturation telemetry, reused),
  the command direction is nearly random, and the missile **misses by a wide margin**.
- **Filtered seeker → the miss collapses back.** An **α-β tracker** on the LOS direction estimates `ω`
  *directly* (predict–correct, no differentiation): it predicts the LOS rotating at the current `ω_est`,
  corrects toward the noisy measurement with small gains `(α, β)`, and outputs a **smooth `ω_est`**. PN
  fed the filtered `ω_est` **leads the target to a tight intercept**, `saturated` **off**, the miss back
  near the slice-10 truth-fed miss.

**The headline numbers:** `miss(:raw) ≫ miss(:filtered) ≈ miss(truth, slice-10)`, plus the
**saturation fraction** (lit for `:raw`, off for `:filtered`) and the **`λ̇` readout** (jittering raw vs
smooth filtered — the α-β variance-reduction, visible as a curve and a number). Miss is measured **at CPA
from TRUTH positions** (the seeker noise corrupts the *guidance*, never the truth CPA measurement — the
slice-10 CPA-miss discipline, unchanged).

**The tee-up for slice 12 (augmented PN + maneuvering target), named honestly:** even a *perfect* filter
leaves plain PN lagging a **maneuvering** target by the `N/2·a_T` target-acceleration term (the slice-10
~2g gravity floor was a literal in-scenario preview of exactly this). Slice 11 models the **seeker/filter**
(HANDOFF §10.11) and **names APN + the maneuvering target as slice 12** — the same structural tee-up
slice 9 gave slice 10 and slice 10 gave this one.

## Scope (one lesson per scenario — the slice-3/4 principle)

A single guided **interceptor** (`[BallisticMissile, Seeker, Autopilot]` — the slice-8 airframe + the
**new phase-3 `Seeker`** + the slice-9/10 `Autopilot`) against a single **constant-velocity crossing
target**, under **`guidance = :pn`** and **`autopilot = :ideal`** (both held, so the miss isolates the
**seeker/filter** — the slice-10 isolation discipline, one knob further in). The switchable **fidelity is
`seeker ∈ (:raw, :filtered)`**. Explicitly **deferred**:

- **Augmented PN (`N/2·a_T` feedforward) + a maneuvering-target mover → SLICE 12** (the user-ratified
  split; the slice-10 ~2g floor's real payoff).
- **Noisy `Vc` / range-rate** — only the **angular LOS rate** is noisy (the PN driver and *the* lesson);
  the seeker's closing speed `Vc` is treated as **known (truth)** so the scenario carries **one** lesson
  (named approximation §1 below). RF-seeker Doppler `Vc` noise is a later fidelity step.
- **6-DOF / fin-actuator dynamics** (§11 Tier A — the airframe lag stays the slice-9 lumped scalar);
  **IR vs RF seeker discrimination / countermeasures** (roadmap item 12); **thrust/boost** (coasting body).

**One scenario** (one lesson; the fidelity button toggles `:raw↔:filtered`, the `σ_seek` slider drives
the noise magnitude). 3 review gates + a gate-0 probe (mirroring slices 5–10).

## The RNG inflection — the sharpest new discipline in this slice

**Slice 11 is where "no RNG in the missile arc" STOPS being true.** Slices 8/9/10 all state (correctly,
for themselves) that *"RNG lockstep / draw-count-invariance is VACUOUS — there is no RNG in the missile
arc."* **The seeker is the first `w.rng` consumer in the missile arc**, so that boilerplate **inverts
here** — and it is the single most likely thing to get wrong, because every surrounding file asserts the
reverse (the convention-4c trap running *backwards*). The seeker obeys the RNG disciplines the radar/GPS
paths do:

- **Convention 3 (draw-topology).** `Seeker.observe!` draws its angle-noise sample **UNCONDITIONALLY every
  tick** — a **fixed** draw count, invariant to the `:seeker` rung, the `σ_seek` slider, target
  position/geometry, and even post-impact (the `detect_once`/`_draw_pseudoranges` precedent). **Never gate
  the draw** on rung or geometry — gate only the *value* PN consumes. The `:raw`↔`:filtered` rungs are
  **draw-count-identical** (both draw; the filter is pure post-processing) — the slice-5 `:estimator`
  (`:pseudolinear`↔`:ml`) **draw-invariant-rung** shape (fidelity class **4a**), NOT the `:cfar` draw-
  topology flip (4b).
- **The three claims, re-derived (NOT copied from slice 8/9/10):**
  1. **Introduce-safe / additivity** — a slice-1..10 scenario has **no `Seeker` subsystem**, so it makes
     **no draw** → byte-identical. Byte-identity comes from *the Seeker not existing*, **NOT** from a
     `:truth` rung that skips the draw (that would be a 4b draw-topology flip `set_fidelity` must reject —
     the advisor's explicit warning). So there is **no `:truth` rung**; "truth-fed PN" IS slice 10 (no
     Seeker).
  2. **Same-config replay is bit-identical WITH the seeker drawing** — now a **non-vacuous** check (the
     first in the missile arc): same seed + same scenario ⇒ the RNG stream and trajectory reproduce
     bit-for-bit.
  3. **A mid-run `:raw↔:filtered` toggle CHANGES the trajectory but does NOT desync the RNG** (draw-count
     invariant → replay-safe, yet not-a-dead-knob). **This is a genuinely NEW fidelity-class combination:
     draw-invariant (like slice 5) AND trajectory-changing (like slice 10) at once** — name it precisely,
     don't force it into an existing template.
- **Convention 11.** Any MC/statistical test uses **its own `Xoshiro`** (never `w.rng`) in a **Wilson/4σ
  band**; the determinism/byte-identity tests use `w.rng` and assert bit-equality.
- **Scenario seed — plumbing CONFIRMED (advisor #5).** A slice-11 scenario is the **first missile
  scenario that consumes `w.rng`**, so it must carry a **seed**. The loader already threads it:
  `scenario.jl:372` reads `seed = Int(get(data, "seed", 0))` and line 376 does `World(seed = seed, …)` —
  so a slice-11 YAML just adds a `seed:` field, **no new plumbing**. Pin a fixed seed for the verifier's
  (now non-vacuous) replay assertion.

## The physics / math (named approximations — HANDOFF §1)

### 1. The seeker measurement model (`Seeker.observe!`, phase 3 — the missile's first sensor)

The seeker measures the **line-of-sight direction** `û = los_unit(m_pos, t_pos)` with **angular noise**
(the honest RF/IR seeker: it senses *where the target is*, an angle — NOT the rate directly; the "you
can't just differentiate it" lesson lives in that choice — advisor gate-0 decision, lean **angle-in /
rate-out**):

    û_true = los_unit(m_pos, t_pos)                        (frames.jl — truth direction)
    (t̂₁, t̂₂) = two unit vectors ⟂ û_true                   (the LOS tangent plane)
    û_meas = normalize( û_true + σ_seek·(n₁·t̂₁ + n₂·t̂₂) )   (n₁,n₂ ~ randn(w.rng) — TWO draws, ⟂ noise)

Noise is injected **in the tangent plane** (perpendicular to the LOS — angular, not radial), the
physically correct place. **`Vc` (closing speed) is truth** (`−range_rate` from truth rel-vel) — only the
**angle** is noisy (§ scope: one lesson). Named approximations: seeker is a **perfect gimbal** (no
boresight/FOV limit, no glint/scintillation beyond white angular noise, no range/Doppler channel);
angular noise is **white Gaussian, `σ_seek` constant** (no range-dependent SNR — a later fidelity step).

### 2. The α-β LOS-rate filter (the `estimation.jl` filter — a NEW recursive primitive)

**estimation.jl reuse is CONCEPTUAL, not code (advisor):** `gauss_newton`/`linear_ls` are **batch** least-
squares; a seeker LOS-rate filter is **recursive** (predict–correct across ticks). So slice 11 adds a
**new pure primitive** — an **α-β tracker on the LOS unit direction** (state = estimated direction +
estimated rate), the textbook seeker filter, RNG-free (the noise is added in the Seeker *before* the
filter is called; the filter is deterministic post-processing):

    Scalar in-plane form (the LIKELY pick — advisor #2; the scenarios are planar, ω ∥ ±y, the lesson IS
    the scalar λ̇ magnitude):
      State: (λ_est, λ̇_est)   (LOS angle + rate in the engagement plane; per-missile in comp)
      Predict:  λ_pred = λ_est + λ̇_est·dt
      Residual: r = wrap( λ_meas − λ_pred )          (λ_meas = the noisy in-plane LOS angle)
      Correct:  λ_est′  = λ_pred + α·r ;  λ̇_est′ = λ̇_est + (β/dt)·r
    Vector-on-direction form (the 3-D alternative — MUST be justified by the probe, NOT the default):
      State (û_est, ω_est); predict û_pred = normalize(û_est + (ω_est×û_est)·dt); innovation δ = û_pred×û_meas;
      correct û_est′ = normalize(û_pred + α·(û_meas−û_pred)), ω_est′ = ω_est + (β/dt)·δ.

`α ∈ (0,1)` (position gain) and `β > 0` (rate gain) trade tracking lag vs noise rejection. **CRITICAL
(advisor #1): tune (α,β) for closed-loop MISS, and expect a U-shape — "smaller β smooths harder" is a
TRAP.** The filter sits *inside* the guidance loop, so over-smoothing trades noise for **lag**, and lag
near CPA (where true ω changes fastest) commands the wrong turn → the miss climbs again. So `miss(β)` is
**U-shaped**: the probe finds the minimum, it does NOT push β→0. The primitive is
**`alpha_beta_los_step(state, meas, dt; α, β)`** → `state′`, pure and dependency-free (`_cross`/`_norm3` or
`wrap_angle` — the §12 house style, no LinearAlgebra). Lives in **`estimation.jl`** (the §9 estimation
home; the `bearings_fix`/`gauss_newton` neighbours). The **raw (`:raw`) path** for the contrast is the
**naïve finite-difference** `λ̇_raw = wrap(λ_meas − λ_prev)/dt` (consecutive noisy angles — the noise-
amplifying path the filter fixes); both paths store the previous measurement, so both are draw-count-
identical and stateful.

**Gate-0 decisions to pin (probe FIRST — the slice-3..10 rule):** (a) **angle-in/rate-out vs rate-in** —
lean angle-in (above); (b) **α-β vs a first-order low-pass EMA on `λ̇_raw`** — lean α-β (the HANDOFF
"filter", predict–correct, estimates rate without differentiating), EMA the fallback if α-β is finicky at
`dt = 1e-3`; (c) **scalar in-plane α-β vs vector-on-direction** — lean the **SCALAR in-plane** form
(advisor #2: the lesson is the scalar λ̇, the scenarios are planar; the vector form's tangent-injection /
cross-innovation-sign / renormalize surface is bug-prone — the probe must JUSTIFY vector if it picks it,
not default to it); (d) **`σ_seek`, `α`, `β` tuned for closed-loop MISS (sweep miss, not variance —
advisor #1), U-shape expected**; (e) **the NOISE REGIME (advisor #3 — it picks the headline):** at high σ
raw pegs `a_max` constantly → a random walk (headline = **miss-ratio**, saturation-always-on is color); at
moderate σ saturation is intermittent (headline = **saturation-fraction**). Back-of-envelope (σ=1 mrad,
dt=1e-3): finite-diff ω-noise ~1.4 rad/s ≫ ω_true ~0.13 rad/s (~10×) → likely the **constant-saturation /
miss-ratio** regime. **Confirm and COMMIT to one** before building the verifier's tell; (f) **`û`/plane
source for the reconstructed `ω`** — filtered estimate (consistent) vs truth; (g) **one vs two scenarios**
— lean one (one lesson).

### 3. The `pn_accel` ω-source refactor (the swappable-estimate seam — advisor)

`pn_accel` currently computes `ω`/`Vc` from **target truth** (guidance.jl:135). Slice 11 makes the **ω
source swappable** so PN reads either truth (slice 10) or the seeker/filter estimate (slice 11), keeping
the **truth path bit-identical** (slice-10 scenarios must not move). The clean seam mirrors the
`haskey(c, :a_ctrl)` guard in `integrate!`:

- Add **`pn_accel_from_omega(û, ω, Vc; N)`** — the pure inner form that takes `ω`/`û`/`Vc` **already
  computed** and returns `N·Vc·(ω×û)`. (**No `m_vel` param** — TPN `N·Vc·(ω×û)` has no missile-velocity
  term; a dead param would be building rot into the seam — advisor #6.) `pn_accel(m_pos,m_vel,t_pos,t_vel;N)`
  becomes a thin wrapper that computes truth `ω`/`û`/`Vc` and calls it — **the slice-10 truth path is
  byte-identical by construction** (same arithmetic, same order; pin it). (`m_vel` stays in the truth
  wrapper's signature only because `v = t_vel − m_vel` feeds `ω`/`Vc` there.)
- `Autopilot.decide!`: if the **Seeker wrote an estimate this tick** (`haskey(c, :seeker_omega)`), call
  `pn_accel_from_omega` with the seeker's `ω_est`/`û_est` (and **truth `Vc`** — § scope); **else** the
  slice-10 truth `pn_accel` (byte-identical). The `Seeker.observe!` (phase 3) writes `comp[:seeker_omega]`,
  `comp[:seeker_los]` **before** `decide!` (phase 4) reads them — the tick contract's phase order does the
  hand-off (no one-tick delay for the estimate; the seeker senses THIS tick's truth + noise).
- **The Seeker's `dt` (advisor #4 — a gate-2 seam the probe papers over).** `observe!(s, w)` has **no `dt`
  argument** (cf. `RadarSensor.observe!`), but the α-β predict step needs it. Do NOT lean implicitly on
  `Autopilot.integrate!`'s `comp[:dt_s]` stash (an undocumented cross-subsystem coupling + an ordering
  assumption that the Autopilot is armed alongside the Seeker). Give the **`Seeker` its OWN phase-1 `dt`
  capture** (`integrate!(s,w,dt)` writes `comp[:dt_s_seeker]` — self-contained, the safer choice; the
  `Autopilot.integrate!` dt-capture precedent, missile.jl:184). The hand-rolled probe loop has `dt` in
  scope so it won't surface this — flag it for gate 2.

### 4. Fidelity: `seeker ∈ (:raw, :filtered)` — draw-invariant AND trajectory-changing (the new combo)

`SEEKER_MODES = (:raw, :filtered)` is the **single source of truth** (defined in **estimation.jl**, which
precedes radar.jl — the `ESTIMATOR_MODES`/`GUIDANCE_MODES` "mode-const-before-radar, one-list-no-drift"
precedent; referenced by `LIVE_FIDELITY_MODES` and picked up by `set_fidelity`/`_KNOWN_FIDELITY_KEYS`
automatically, no server change). The Seeker **always draws** and **always updates the filter state**; the
rung selects **which `ω` it writes** to `comp[:seeker_omega]` (`:filtered` → `ω_est`; `:raw` → `ω_raw`).
Both rungs are **draw-count-identical** (class 4a, slice-5 shape → `set_fidelity` may introduce it freely,
UNLIKE `:cfar`) yet a toggle **changes the trajectory** (physics-changing in VALUE — the slice-10 shape).
**Name this NEW combination explicitly** (draw-invariant *and* not-a-dead-knob); do NOT copy the slice-5
"toggle-bit-identical" language (a toggle here is NOT bit-identical — it changes guidance) NOR the slice-8/
9/10 "RNG-is-vacuous" language (there IS RNG now). `:seeker`, `:guidance`, `:autopilot` are **orthogonal**;
slice-11 scenarios pin `:guidance = :pn`, `:autopilot = :ideal` so the **one** button toggles **one**
lesson (convention 9).

## Decisions to take at gate 0/2 (surface to advisor before implementing)

1. **Angle-in/rate-out** (seeker measures noisy LOS *angle*, filter produces rate) vs rate-in (measures
   noisy `λ̇` directly). Lean angle-in (the "can't differentiate noise" lesson). **Probe confirms.**
2. **α-β tracker** vs first-order low-pass EMA on `ω_raw`. Lean α-β (the HANDOFF "filter"). **Probe.**
3. **Vector α-β on `û`** vs scalar-in-plane. Lean vector (3-D honest, no singularity). **Probe.**
4. **Only the angle is noisy; `Vc` is truth** — isolates the λ̇ lesson (one scenario, one lesson). Confirm.
5. **The `pn_accel` refactor keeps the truth path byte-identical** — `pn_accel_from_omega` + thin wrapper;
   pin a slice-10 scenario replaying bit-identical after the guidance.jl edit.
6. **The seeker estimate is same-tick** (phase-3 observe! → phase-4 decide!), NOT one-tick-delayed like
   `:a_ctrl` — the seeker senses this tick's truth, decide! consumes it this tick. Confirm the phase order.
7. **`σ_seek`, `α`, `β` values + one scenario** — pinned by the probe against the live wire.

## Review gates (cadence: staged, mirroring slices 5–10)

0. **Gate-0 probe (throwaway, `M:\claud_projects\temp\slice11_probe\`).** Reuse the REAL core physics
   (`using EWSim`: `total_accel`/`integrator_step`/`los_unit`/`los_rate`/`range_rate`/`clamp_accel`/
   `pn_accel`), hand-roll only the seeker (noise + tangent-plane injection), the α-β filter, and the
   decide!→integrate! loop (autopilot `:ideal`, `:pn`). **Confirm + pin numbers:** (i) raw noisy `λ̇`
   OPENS the miss (peg-at-`a_max`, `saturated`); (ii) the α-β filter CLOSES it (miss ≈ truth-fed); (iii)
   stable at `dt = 1e-3`; (iv) **SWEEP `(α,β)` vs closed-loop MISS (advisor #1) — confirm the U-shape and
   pick the minimum, do NOT push β→0**; (v) **pin the NOISE REGIME (advisor #3) — commit to
   constant-saturation/miss-ratio OR intermittent/saturation-fraction**; (vi) **decide scalar-in-plane vs
   vector α-β (advisor #2) — take scalar unless the probe justifies vector**. **Advisor-confirm the seven
   decisions.** Write `FINDINGS.md`, pin σ/α/β and the miss(:raw) ≫ miss(:filtered) **RATIO** (not
   absolutes — the slice-10 tick-sampling-floor caution).

1. **Primitive green (pure, closed-form/recursive, SI, RNG-free, no LinearAlgebra).** Extend
   `estimation.jl`: **`alpha_beta_los_step(û_est, ω_est, û_meas, dt; α, β)` → `(Vec3, Vec3)`** (§2), pure,
   `_cross`/`_norm3` only, guarded (`û→0`/`dt→0` → safe). **`SEEKER_MODES = (:raw, :filtered)`** the
   source-of-truth const, defined here (estimation.jl precedes radar.jl). Guidance.jl:
   **`pn_accel_from_omega`** + the `pn_accel` wrapper (§3), `pursuit_accel`/`autopilot_step`/the truth
   `pn_accel` result **UNCHANGED** (byte-identity anchor). `test_estimation.jl` (+ α-β arms, explicit
   `atol`, never rtol-`≈0`): **rate convergence** — on a CLEAN constant-`ω` LOS ramp (no noise) the filter's
   `ω_est → ω_true` (external anchor: the known ramp rate, not a self-calibrated round-trip); **variance
   reduction** — on a noisy ramp `Var(ω_est) ≪ Var(ω_raw)` (MC with its OWN `Xoshiro`, Wilson band — the
   convention-11 teeth). **These open-loop tests are NECESSARY-NOT-SUFFICIENT (advisor #1):** the (α,β)
   that minimize open-loop variance are NOT the ones that minimize closed-loop miss (over-smoothing → lag
   → miss climbs); the CLOSED-LOOP miss test lives at gate 2 / the probe, which SWEEPS (α,β) vs miss.
   **α/β scaling** (larger β → faster tracking/less smoothing — the gain does what it
   says); **degenerate guards** (`û→0`, `dt→0`, huge noise → no throw/NaN); **`pn_accel_from_omega`
   recompute** (a DIFFERENT expression than the impl — catches a transpose). `test_guidance.jl`:
   **truth-`pn_accel` byte-identical** to slice 10 (the wrapper preserves the arithmetic — pin it). Slices
   1–10 byte-identical through the include (golden + determinism green; estimation.jl adds no RNG path).

2. **Seeker wired — the missile's first `observe!` (the `:seeker` key filled).** New **`Seeker <:
   Subsystem`** (missile.jl or seeker.jl) with a **phase-1 `dt` capture** (`comp[:dt_s_seeker]` —
   self-contained, advisor #4, NOT a lean on the Autopilot's `:dt_s`; the missile.jl:184 precedent) and
   **phase-3 `observe!`**: reads truth `û`, **draws the angle-noise sample(s) `randn(w.rng)`
   UNCONDITIONALLY** (convention 3; a FIXED count — 1 scalar-in-plane / 2 vector), injects noise, updates
   the α-β state
   (always), and writes `comp[:seeker_omega]`/`comp[:seeker_los]` + seeker telemetry (`λ̇_raw`, `λ̇_filt`,
   `σ_seek`). `Autopilot.decide!`: the **§3 ω-source branch** (`haskey(c,:seeker_omega)` → seeker estimate
   else truth) — the **inner PID + truth path UNCHANGED**. `LIVE_FIDELITY_MODES += seeker = SEEKER_MODES`
   (one-list-no-drift). `scenario.jl`: a `seeker:` sub-block reads `sigma_seek`/`alpha`/`beta` at
   **knob-addressable comp keys**, validated at **LOAD** (`sigma_seek ≥ 0`, `0 < alpha < 1`, `beta > 0`);
   the guided `:missile` arms `[BallisticMissile, Seeker, Autopilot]`; the scenario carries a **seed**.
   - `test_missile.jl` (+ seeker arms): `Seeker.observe!` writes `comp[:seeker_omega]` matching the filter
     on a realized state; **filtered miss ≪ raw miss on the wire** (autopilot `:ideal`, the Lesson pin);
     **`:raw↔:filtered` trajectories DIFFER** (not-a-dead-knob); **`:raw` saturates** (`saturated ≈ 1`
     midcourse) while `:filtered` does not; the seeker draws a FIXED count per tick (1 scalar / 2 vector —
     the probe pins which; the draw-count-invariance pin).
   - `test_determinism.jl` (**THE INFLECTION — the first non-vacuous missile-arc RNG test**): same-seed
     bit-identical **with the seeker drawing** (claim 2); **introduce the Seeker on nothing / a slice-1..10
     scenario has no Seeker → byte-identical** (claim 1, the additivity master-check — byte-identity from
     *no Seeker*, NOT a draw-skipping `:truth` rung); **`:raw↔:filtered` toggle CHANGES the trajectory yet
     is draw-count-invariant** (claim 3 — the new combo: replay-safe AND not-a-dead-knob); a **slice-10
     scenario replays BIT-IDENTICAL after the guidance.jl/missile.jl edits** (the truth-path anchor).
   - `test_server.jl`: `set_fidelity :seeker` write/reject/**introduce-safe** (class 4a — introducible,
     UNLIKE `:cfar`); the **`sigma_seek`/`alpha`/`beta` live sliders** `set_param`→tick survive (a huge
     `σ_seek` pegs `a_max`, does not throw — the "a live slider can't crash a tick" watch-item). Slices
     1–10 byte-identical.

3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice11_seeker.yaml` (`:pn`,
   `:autopilot = :ideal`, `[BallisticMissile, Seeker, Autopilot]`, `:filtered` default, a fixed seed, a
   crossing target — filtered clean, raw misses). **Numbers probed against the live
   `load_scenario→observe!→decide!→integrate!→telemetry` wire** + pinned (`miss(:raw)`, `miss(:filtered)`,
   the saturation fraction, `Var(λ̇)`).
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode — the slice-8/9/10 precedent).
     The **seeker fidelity button** cycles `:raw↔:filtered` (`_on_seeker_pressed`, guarded like the
     guidance cycler; the `seeker` discriminator checked alongside `guidance`/`autopilot`); the `σ_seek`
     slider; the new `λ̇_raw`/`λ̇_filt`/`saturated` readout (all scalars — re-confirm no Array telemetry /
     `float()`-crash). The visual tell: the **LOS/`ω` readout JITTERS under `:raw`** (saturation lit,
     wild `a_cmd`) vs **STEADY under `:filtered`** (the α-β smoothing as a picture). Slice-1..10 views
     UNTOUCHED (re-run every smoke-load + UI test).
   - `net/slice11_verify.gd` (drives the real server): `:filtered` **intercepts** (small min-`los_range`,
     `saturated` low, `λ̇_filt` smooth); `set_fidelity seeker :raw` **degrades** it (large min-range,
     `saturated` high, `λ̇_raw` jittering); **`t` bit-identical under the held seed+config** (the replay
     assertion — now non-vacuous). Assertions on SCALARS. `S11V OK`, exit 0. Step counts **multiples of
     `emit_every`** (the drain contract).
   - `net/slice11_ui_test.gd` (mock client, no server): the seeker handshake wires the **`seeker`** cycler;
     the ring walks `:raw→:filtered` and wraps; badge/button track; the `σ_seek`/`α`/`β` sliders send
     `set_param`; reset resyncs (`S11UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-11 server (server `DONE` ⇒ scene connected, no
     GDScript errors).
   - `test_scenario.jl` + slice-11 loader testset (parses; `:seeker = :filtered` default now PRESENT [the
     reserved-word-becomes-real move]; `:guidance = :pn` / `:autopilot = :ideal` held; the guided `:missile`
     gets `[BallisticMissile, Seeker, Autopilot]` and NOT `ConstantVelocity`; `sigma_seek`/`alpha`/`beta`
     at consumed comp keys and ARE knobs; the scenario carries a seed; loader rejects bad
     `sigma_seek`/`alpha`/`beta`).
   - The **`_draw` seeker PIXEL branch** visually confirmed via the windowed shot harness
     ([[ewsim-godot-headless]]): `:raw` = the jittering LOS/`a_cmd` + `saturated` lit + wide miss;
     `:filtered` = the steady LOS + tight intercept + `saturated` off. **(stretch, deferred)**
     `clients/notebooks/slice11_seeker.jl` Pluto — the `λ̇_raw` vs `λ̇_filt` variance + a miss-vs-`σ_seek`
     sweep (the seeker lesson as a curve); an offline `batch.jl` miss-vs-`σ_seek`/`(α,β)` grid (own seeded
     stream — the distribution path).

## Task checklist
- [x] **0. Probe + scope pin — DONE & advisor-confirmed** (`M:\claud_projects\temp\slice11_probe\`:
      `probe.jl` + `FINDINGS.md`). PINNED: **scalar in-plane α-β** (NOT vector — planar x-z, ω∥±y, no
      atan2 singularity; gate-1 signature `alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α, β) →
      (λ_est′, λ̇_est′)`), **σ_seek = 3 mrad, α = 0.30, β = 0.05**, one scenario. Headline =
      **MISS-RATIO** (raw median 774 m vs filtered 0.34 m ≈ truth 0.026 m; ~2251× per-tick) with
      saturation (raw 0.83 vs filtered 0.01) as the corroborating "raw is broken" tell. LOCK 1: the
      truth path reproduces slice-10 (0.026 m) with `pn_cmd == pn_accel` asserted every tick. β
      U-shape confirmed BOTH arms (β→0 lag, β≥0.3 noise-through → 800 m+); draw count = **1** (scalar).
      **⚠ Deviation from plan's σ=1 mrad guess:** scalar drops the out-of-plane noise channel, so the
      raw miss only explodes at ~3 mrad (at 1 mrad it saturates but the in-plane sign-flip cancels →
      only 4.6 m). Forward-flags in FINDINGS: gate-1 byte-identity is UNTESTED (probe used `≈`, keep
      exact grouping `(N*Vc)*_cross(ω,û)` + call order); gate-2 Seeker needs its OWN `dt` capture
      (`comp[:dt_s_seeker]`); gate-3 verifier is 1-seed vs 30-seed median + `emit_every` floors the
      filtered side → read `slice10_verify.gd`, pin conservative raw-lower/filtered-upper bounds, not
      the ratio.
- [x] **1. Primitive — DONE & green (1845 tests, +16 arms).** `SEEKER_MODES = (:raw,:filtered)` +
      scalar `alpha_beta_los_step(λ_est,λ̇_est,λ_meas,dt;α,β)` (predict–correct, `wrap_angle` only,
      `β/dt` floored at `_ALPHA_BETA_DT_FLOOR=1e-12` — exact no-op at dt=1e-3, no û guard) in
      estimation.jl; `pn_accel_from_omega(û,ω,Vc;N)=(N*Vc)*_cross(ω,û)` + thin `pn_accel` wrapper in
      guidance.jl. **Byte-identity proven** two ways: `pn_accel === (N*Vc)*_cross(ω,û)` slice-10-inline
      pin (`test_guidance.jl`, bit-exact `===` not `≈`) + full golden/`test_determinism` suite green.
      Test bands MEASURED open-loop (not the probe's closed-loop numbers — advisor): convergence
      λ̇_est→ω_true ~1e-13 (atol 1e-6); variance reduction std(raw)==σ√2/dt anchor, filt <raw/8 (~11.8×);
      α/β scaling larger-β-faster (open-loop, NOT a miss claim); dt→0/huge-meas/extreme-gain guards
      finite. Exports added. **Fix logged:** the `pn_accel` docstring must stay glued to its function —
      inserting the new block between them made the docstring precede a string literal → "cannot
      document" precompile error (relocated `pn_accel_from_omega` AFTER `pn_accel`).
- [x] **2. Wired — DONE & green (1890 tests, +45 arms).** `Seeker <: Subsystem` in missile.jl:
      phase-1 `integrate!` captures `comp[:dt_s_seeker]` (self-contained, advisor #4); phase-3
      `observe!` draws ONE `randn(w.rng)` UNCONDITIONALLY at the top (before the tgt/impact gate —
      convention 3), measures the noisy LOS angle, updates BOTH the raw finite-diff memory AND the
      α-β state every tick (rung selects only which ω is written), reconstructs `ω=Vec3(0,−λ̇,0)` /
      `û=(cosλ,0,sinλ)` into `comp[:seeker_omega]`/`[:seeker_los]`, and writes λ̇_raw/λ̇_filt/λ̇_used/
      σ telemetry. `Autopilot.decide!`: the ω-source branch `guid===:pn && haskey(c,:seeker_omega)`
      → `pn_accel_from_omega(û_seek, ω_seek, TRUTH Vc)` (û FIRST, ω SECOND — arg order is the silent
      sign trap; rel_pos/rel_vel hoisted above for truth Vc); the truth `pn_accel` path UNTOUCHED
      (no Seeker ⇒ no `:seeker_omega` ⇒ slice-10 byte-identical). `LIVE_FIDELITY_MODES += seeker =
      SEEKER_MODES` (radar.jl, one-list-no-drift; class 4a so `set_fidelity` introduces it freely,
      no `:cfar`-style guard). scenario.jl: a `seeker:` block reads `sigma_seek`/`alpha`/`beta` at
      knob-addressable comp keys, LOAD-validated (σ≥0, 0<α<1, β>0), armed `[BallisticMissile, Seeker,
      Autopilot]`; seed plumbing already existed. `export Seeker`. **Numbers PROBED against the live
      decide!→integrate! path** (`slice11_gate2_measure.jl`, convention 10): σ=3mrad/α=0.30/β=0.05 →
      filtered miss ~0.9m (sat 0.01) vs raw ~713m (sat 0.80), ratio ~793× @ seed 0. Test arms:
      **test_missile** — the phase-3→4 seam (`a_ctrl == clamp(pn_accel_from_omega(û,ω,Vc))`, ‖Δ‖=0),
      filtered≪raw, raw saturates, trajectories differ, **1 randn/tick draw-count pin** (Xoshiro-
      advance), huge-σ no-crash, loader arms+rejects. **test_determinism** (THE INFLECTION — first
      non-vacuous missile-arc RNG test): same-seed bit-identical WITH the seeker drawing, 1-draw/tick,
      the NEW COMBO (:raw↔:filtered draw-invariant AND trajectory-changing), introduce-safe on a
      no-Seeker slice-10 missile. **test_server** — set_fidelity :seeker write/reject/introduce-safe
      (4a), the σ/α/β live sliders survive a huge-σ tick. Fix logged: the `a_ctrl` seam pin uses
      `≈ atol=1e-9` (not `==`) — decide! double-clamps (a_cmd then a_ctrl) vs the single-clamp oracle,
      a 1-ULP difference on a saturated tick; tick-100 is non-saturated so it matches, but atol is the
      honest form. Deviation from probe seed: gate-2 pins seed 0 (filtered 0.90m/raw 713m), not the
      probe's seed-11 30-seed median (0.34m/774m) — same regime, single-seed for a deterministic test.
- [x] **3. Scenario + Godot + verifiers — DONE & green (1921 tests, +31 arms).** `scenarios/slice11_seeker.yaml`
      (seed 6, `seeker:filtered` default, guidance:pn + autopilot:ideal HELD, the slice10_pn crossing —
      the seeker is the ONLY new variable). Numbers PROBED against the live `load_scenario→observe!→decide!→
      integrate!→telemetry` wire (21-seed sweep): seed 6 miss(:filtered) ≈ 0.39 m (frame-sampled ≈ 0.39, CPA
      on the emit grid) vs miss(:raw) ≈ 1391 m (~3500×), sat 0.01 vs 0.79, var(λ̇_filt)≈0.10 ≪ var(λ̇_raw)≈22.7;
      bounds pinned CONSERVATIVE one-sided (filtered<30, raw>300 — NOT the ratio; the memory's frame-sampling
      floor). `Sandbox.gd`: the `seeker` discriminator branch checked BEFORE `guidance`/`autopilot` (all three
      keys ship; the one button toggles seeker — convention 9), `_on_seeker_pressed` (:raw↔:filtered ring),
      `SEEKER_RUNGS`, `_draw` missile+LOS branches extended, the λ̇ readout auto-renders (scalars). Slice-1..10
      views UNTOUCHED (slice-10 UI test re-run green — the seeker branch does NOT hijack slice-10). Four proofs:
      `net/slice11_verify.gd` (filtered intercepts / set_fidelity raw degrades+saturates / **the first
      non-vacuous missile-arc same-seed replay — pos_x/pos_z sequences element-wise bit-identical, on an
      RNG-affected value NOT the clock `t`** — advisor; `S11V OK`, exit 0); `net/slice11_ui_test.gd` (seeker
      cycler wired, NOT guidance/autopilot; σ_seek slider; reset resync — `S11UI OK`); Sandbox.tscn
      full-lifecycle windowed load (connect→handshake→state→`_draw`, exit 0 — a superset of the headless
      smoke-load); `test_scenario.jl` +1 testset (seeker:filtered default present, held keys, [BallisticMissile,
      Seeker, Autopilot], consumed keys + knobs, seed, rejects bad σ/α/β). The `_draw` PIXEL branch VISUALLY
      CONFIRMED via 2 windowed shots (reverted+deleted): filtered = clean LOS + a_cmd=a_demand=917 (unsaturated);
      raw = wild kinked trail + a_cmd=3000 PINNED at a_max while a_demand=25875 (the saturation as a picture) +
      closing_speed −1291 (diverged). STATUS.md + CLAUDE.md updated. **SLICE 11 COMPLETE.**

## Context / landmarks
- **The truth-feed slice 11 replaces:** `pn_accel` computes `ω` from truth (guidance.jl:135); its docstring
  names the seeker as slice 11 (guidance.jl:126). The `:seeker` word is not yet reserved — this slice
  introduces it (unlike `:guidance`, which slice 9 pre-reserved).
- **The missile's empty `observe!`:** missile.jl:11 — *"observe!/decide! stay EMPTY here — guidance /
  seekers are slices 9–11"*. Slice 11 fills `observe!` (phase 3).
- **`frames.jl` LOS kernel (reused):** `los_unit`, `los_rate` (`r×v/r²`), `range_rate` ("negative =
  closing"), `_cross`, `_norm3` — everything the seeker + α-β need, dependency-free.
- **`estimation.jl` (the filter's home):** `gauss_newton`/`linear_ls`/`bearings_fix` (batch) + the new
  recursive `alpha_beta_los_step`; `ESTIMATOR_MODES` the mode-const precedent.
- **Fidelity plumbing precedent:** slice-10 `:guidance` (`GUIDANCE_MODES` in guidance.jl →
  `LIVE_FIDELITY_MODES` in radar.jl → `set_fidelity` per-key table → `_KNOWN_FIDELITY_KEYS` in scenario.jl)
  — `:seeker` mirrors it, but as a **draw-invariant (class 4a) RNG rung**, so it is introducible via
  `set_fidelity` (UNLIKE `:cfar`).
- **RNG draw precedents (the discipline slice 11 imports into the missile arc):** `detect_once` (radar.jl)
  and `_draw_pseudoranges` (gps.jl:117 — draws multipath THEN noise, BOTH unconditional) — the
  "draw-unconditionally, gate-the-value" template. `test_determinism.jl`'s `RandomWalker` fixture is the
  same-seed-bit-identical anchor.
- **HANDOFF** §10 item 11 (this slice), §3 (the tick contract — phase-3 observe! finally lit for the
  missile), §9 (estimation.jl reuse — CONCEPTUAL here, not code), §1 (named approximations; the LOS-sign
  trifecta extended to the estimate), §12 (fidelity badge). §11 Tier A (IR/RF seeker discrimination, 6-DOF
  — the deferred horizon).

## Watch-items (gotchas to bake in)
- **THE RNG INFLECTION — do NOT copy the slice-8/9/10 "RNG is vacuous" boilerplate.** The seeker is the
  first `w.rng` consumer in the missile arc; convention 3 (unconditional draw) and convention 11 (own
  Xoshiro for MC) now APPLY. Every surrounding missile file says the reverse — the convention-4c trap
  BACKWARDS.
- **Byte-identity comes from NO SEEKER, not a `:truth` rung.** A `:truth` rung that skips the draw is a
  4b draw-topology flip (`set_fidelity` must reject introducing it). There is **no `:truth` rung** — the
  Seeker always draws; "truth-fed PN" IS slice 10 (no Seeker). `SEEKER_MODES = (:raw, :filtered)` only.
- **Keep the truth `pn_accel` byte-identical.** The `pn_accel_from_omega` refactor must reproduce slice
  10's arithmetic EXACTLY (same order, `N·Vc·(ω×û)`) so slice-10 scenarios replay bit-identical. Pin it.
- **The `:seeker` rung is a NEW fidelity-class combo:** draw-invariant (4a — introducible, no desync) AND
  trajectory-changing (physics — a toggle moves the missile). Name both; copy NEITHER the slice-5
  "toggle-bit-identical" NOR the slice-10 "no-RNG" language wholesale.
- **PN amplifies angle noise by `Vc/dt`.** `a_cmd = N·Vc·(ω×û)` with `ω_raw = Δangle/dt` → `N·Vc·σ/dt` of
  noise (thousands of m/s² at `dt=1e-3`). Expect `:raw` to peg `a_max` — REUSE the slice-10 `saturated`
  telemetry as the "raw is broken" tell (a happy synergy, not a new readout).
- **Miss at CPA from TRUTH positions.** The seeker noise corrupts the guidance, never the CPA measurement
  (the slice-10 discipline). Measure min `los_range` over the run from truth, sampled on `emit_every`
  multiples.
- **`σ_seek`/`α`/`β` are knobs; validate at LOAD** (`σ ≥ 0`, `0 < α < 1`, `β > 0`) AND floor at the
  consumer (a live `α→0`/`α→1` or `dt→0` can't NaN the filter — the `autopilot_step` `τ`-floor precedent).
- **Stay spatial** — extend `_draw_spatial`, no new render mode (slice-8/9/10 precedent); the LOS/`a_cmd`
  JITTER (raw) vs STEADY (filtered) IS the visual.
- **Verifier drain multiples** of `emit_every`; the replay assertion needs the **held seed** (the first
  non-vacuous missile-arc replay).
- **`:seeker` word is NEW** (not pre-reserved like `:guidance`) — the slice-10 `test_scenario` did not
  assert it absent, so there is no prior assertion to flip; just add the slice-11 arm.
