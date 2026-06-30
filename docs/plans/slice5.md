# Slice 5 — DF / geolocation (bearings-only emitter location + the GDOP error ellipse)

The slice that finally lights up **phase 4 of the tick contract**. Slices 1–3 used only
`observe!`/`integrate!`; slice 4 lit `build_env!` (phase 2). `decide!` (phase 4 —
"estimators/guidance → commands acted on next tick", `subsystem.jl:17`) has been a no-op
default since the contract was written. A **geolocator is a `decide!` subsystem**: the DF
sensors *sense* (phase 3 — each draws a noisy bearing to the emitter), and the fusion node
*estimates* (phase 4 — crosses the bearings into a position fix). The two are coupled
**through `w.env`** (sensors write `env[:bearings]`, the geolocator reads it back), the exact
§3 mechanism slice 4 proved across the build_env!→observe! seam — here reused across the
**observe!→decide! seam**. Source of truth: `HANDOFF.md` §10 (item 5), §3 (the four-phase
tick + `env` coupling), §9 (`geometry.jl` GDOP/ellipse + `estimation.jl` least-squares are
the **shared libs** GPS/seeker slices will reuse — build them right once), §1 (named
approximations; units/frames/**signs** are the bug trifecta — bearings are an angle, so sign
+ wrap are first-class here), §12 (the fidelity badge).

The lesson is the **geometric dilution of precision (GDOP)**: crossing two or more bearing
lines-of-position (LOPs) locates an emitter, but *how well* depends entirely on the **crossing
geometry**. Bearings that cross near 90° pin the emitter tightly; bearings that graze
(sensors nearly collinear with the emitter, or a long thin baseline) pin it only *across* the
LOPs, not *along* them — the position covariance stretches into a long thin **error ellipse**
pointed down-range. Watching that ellipse stretch and rotate as the emitter flies through
good→bad geometry **is** the lesson (HANDOFF §9: this is the *same math* as GPS DOP — a
deliberate cross-domain "aha" the shared `geometry.jl` sets up). The second lesson is the
**estimator fidelity**: the closed-form **pseudolinear** least-squares fix is *biased* (it
puts the noisy measured bearing inside the regressor matrix), worst at long range / poor
geometry; the iterated **maximum-likelihood** (Gauss-Newton) fix removes most of that bias.
Toggling `estimator` (the §12 badge) and watching the fix walk back toward truth is the EP-style
"named, switchable approximation" knob.

**Scope:** a single emitter (named scope, like slice-3's single radar — multi-emitter
deinterleaving is slice 6, §10 item 6); **2-D azimuth-only** DF in the x-y (plan) plane; **noise
jamming-free** (one lesson per scenario — the slice-3 principle). 3 review gates (geometry +
estimation primitives fold into one closed-form gate; the slice has fewer moving parts than
slice 4's antenna/EP).

**Done =** start the server on a geolocation scenario, connect Godot, watch (in a **new plan /
top-down view**) the emitter fly while three DF sensors throw bearing rays at it, a position fix
tracks it, and the **error ellipse stretches** as the emitter crosses into poor geometry; drag a
sensor's bearing accuracy (`sigma_theta_deg`) and watch the whole ellipse scale; toggle the
`estimator` fidelity (`pseudolinear ↔ ml`) and watch the fix **walk back toward truth** (most
visibly at the worst geometry) — with `runtests.jl` green on the new closed-form geometry tests
and the analytic-CRLB-vs-MC estimation tests (and slices 1–4 untouched and still
**byte-identical** — no DF subsystem touches the radar/jammer RNG path).

## The physics / math (named approximations — HANDOFF §1)

Bearings-only (angle-of-arrival) geolocation. **2-D azimuth-only** throughout: sensors and the
emitter live in the x-y plane (z carried but **ignored** for the bearing — a named planar
simplification; a 3-D AOA ellipsoid is a future extension). Independent Gaussian bearing noise
per sensor. The whole slice is **deterministic given the drawn bearings** (the fix + covariance
are closed-form / a fixed-iteration solve), so — like slices 2 and 4 and unlike slice 3 — there
is **no draw-topology hazard** (see Decisions).

### 1. The bearing measurement (`geometry.jl` + the `DFSensor`)
- True azimuth from sensor `s` to emitter `e`: **`θ = atan(Δy, Δx)`** in (−π, π] (the
  `bearing(from, to)` primitive). Sign convention pinned and tested from day one (the §1
  trifecta — a flipped `atan2` arg order is exactly the LOS-rate-sign class of bug).
- Measurement: **`θ̂ = wrap(θ + n)`, `n ~ N(0, σθ)`** — one `randn` draw per sensor per look.
  `σθ` (`comp[:sigma_theta_rad]`, authored `sigma_theta_deg`) is **per-sensor** and **fixed**
  (named approximation: bearing accuracy is independent of range/SNR — a real DF sensor's σθ
  grows as the emitter's SNR drops with range; a future emitter-power/SNR coupling is deferred).
- `wrap_angle(θ) → (−π, π]` is used for **every** angular residual (the bug class: an unwrapped
  residual near ±π injects a ~2π error and yanks the fix).

### 2. The position fix (`estimation.jl`)
Two estimators sharing the **same drawn bearings** (the fidelity rung selects only the
post-processing — no extra draws):
- **`:pseudolinear`** (closed-form, the **biased** baseline / named approximation). Each bearing
  is a line `sin θ̂ᵢ·(x − xᵢ) − cos θ̂ᵢ·(y − yᵢ) = 0`; stack rows `Aᵢ = [sin θ̂ᵢ, −cos θ̂ᵢ]`,
  RHS `bᵢ = xᵢ sin θ̂ᵢ − yᵢ cos θ̂ᵢ`, weights `Wᵢ = 1/(σᵢ² R̂ᵢ²)` (perpendicular-offset variance;
  `R̂ᵢ` = sensor→seed range), solve the 2×2 normal equations `(AᵀWA) p̂ = AᵀW b` by a
  **closed-form 2×2 inverse** (dependency-free, the `_range`-avoids-LinearAlgebra style). The
  **bias** is structural: `θ̂` (noisy) sits inside `A`, correlating the regressor with the error
  — worst at long range / shallow crossings. This is the *named* approximation the slice teaches.
- **`:ml`** (iterated Gauss-Newton, the higher-fidelity rung). Seed at the pseudolinear fix, then
  a few fixed iterations on the nonlinear LS: residual `rᵢ = wrap(θ̂ᵢ − atan(ŷ−yᵢ, x̂−xᵢ))`,
  Jacobian row `Hᵢ = [−sin θ̂ᵢ/R̂ᵢ, cos θ̂ᵢ/R̂ᵢ]`, update `Δp = (Hᵀ R⁻¹ H)⁻¹ Hᵀ R⁻¹ r`,
  `R = diag(σᵢ²)`. **Fixed iteration count** (no while-until-converged — keeps it deterministic
  and un-stallable inside a tick; named: "N-step Gauss-Newton, not to convergence"). Removes most
  of the pseudolinear bias. **Divergence fallback (advisor #6):** a fixed iteration *count* bounds
  the time but not the *result* — a GN step under bad geometry can overshoot to NaN or walk the fix
  *away* from the data. So guard the step (singular-`HᵀR⁻¹H` det floor, reject a step that produces
  a non-finite `p̂` or grows the residual norm) and **fall back to the pseudolinear seed** on
  divergence — never return NaN / never spin. Because `:ml` is *seeded* by the pseudolinear fix, the
  `:ml` path computes the pseudolinear solution first — deterministic, **no new draws** (the rung
  switch is still draw-free).

### 3. The error ellipse + GDOP (`geometry.jl`)
- **Linearized (CRLB / first-order) position covariance:** `C = (Hᵀ R⁻¹ H)⁻¹` evaluated at the
  estimate (`H`, `R = diag(σᵢ²)` as above) — a 2×2 symmetric matrix that **carries the actual σθ**,
  **the live ellipse**. Named approximation: exact only for small errors / benign geometry; under
  bad geometry the *true* fix scatter is non-elliptical (banana-shaped) and the linear ellipse
  **under-predicts** it — quantified by the offline MC stretch (gate 3, below), the slice-1
  analytic-vs-MC convergence reprised in 2-D.
- **`eig2x2(C) → (λ₁ ≥ λ₂, angle)`** — closed-form symmetric 2×2 eigendecomposition (no
  LinearAlgebra): `λ = (a+c)/2 ± √(((a−c)/2)² + b²)`, principal angle `½·atan(2b, a−c)`.
  **`error_ellipse(C; nsigma=1) → (a, b, ang)`** = `(nsigma·√λ₁, nsigma·√λ₂, angle)`. Because `C`
  carries σθ, the ellipse axes **scale with σθ** (the live-slider lesson). The principal `angle`
  is an eigenvector `atan2` → it **wraps** (test it), and under bad geometry it aligns with the LOS
  (the ellipse elongates *down-range*, not across — advisor #3).
- **`gdop(H) = √trace((Hᵀ H)⁻¹)`** — computed at **UNIT measurement variance** (σθ ≡ 1), so it is a
  pure-geometry, dimensionless scalar with `σ_pos = gdop·σθ` (the **same** DOP math GPS will reuse,
  HANDOFF §9). The range-weighting (far sensors weigh less) is already baked into `H`'s `1/R̂ᵢ`
  rows; GDOP must **NOT** be the σθ-weighted `√trace((HᵀR⁻¹H)⁻¹)` — that would make a σθ slider
  wrongly move GDOP (the CFAR mean-vs-sum convention trap on a new surface — advisor #2). **GDOP is
  geometry only; the ellipse carries σθ.** Small for orthogonal crossings, →∞ (capped finite) as the
  geometry degenerates (collinear / emitter on the baseline extension). `gdop` is the scalar readout
  of "how good is this geometry right now," **invariant to the σθ slider** (pin this).

## Decisions taken (advisor-reviewed 2026-06-29 — both flagged decisions confirmed, 6 catches folded in)
- **Entity/subsystem model — Model A, the phase-4 decomposition (lights `decide!`).** DF sensors
  are `:df_sensor` **entities**, each carrying a **`DFSensor`** subsystem (phase-3 `observe!`):
  it reads the (single) emitter's truth `pos`, computes the true bearing, draws one noisy bearing,
  and appends a record to **`w.env[:bearings]`** + publishes `<id>.bearing_deg` telemetry. A
  `:df_station` **entity** (the C2 / fusion node) carries a **`Geolocator`** subsystem (phase-4
  `decide!`): it reads **all** of `env[:bearings]`, runs the fix (per the `:estimator` fidelity)
  + the linearized covariance/ellipse + GDOP, and publishes the fix/ellipse telemetry. This is
  the §3 coupling done right — through `env`, across the **observe!→decide! seam** — and it
  **lights phase 4 for the first time** (the natural milestone after slice 4 lit phase 2; the
  intro celebrates it exactly as slice 4 celebrated `build_env!`). *(Alternative Model B — one
  `Geolocator.observe!` reads sensor entity positions directly and does everything in phase 3,
  sensors passive like `:clutter` — is simpler but does not light `decide!` and folds sense+
  estimate into one phase. Flagged for the advisor; the lean is A.)*
- **`env[:bearings]` is a VECTOR/Dict of per-sensor records**, each
  `@NamedTuple{theta::Float64, pos::Vec3, sigma::Float64}` (NOT a pre-solved fix) — the geolocator
  needs each sensor's position + σ to build `A`/`H`/`W`. Records are appended in **sorted sensor-id
  order** (the DFSensor subs run in the scenario's sorted-id order, so the RNG draw order across
  sensors is deterministic — the §1 bug class made free). The geolocator sorts again before the
  solve so the fix is order-independent.
- **Fidelity = `estimator => (:pseudolinear, :ml)`**, joining `LIVE_FIDELITY_MODES`. Both rungs
  consume the **same drawn bearings** → the rung changes only deterministic post-processing, so
  it is **introduce-safe AND toggle-bit-identical** (the slice-4 `:ep` contract, NOT slice-3's
  `:cfar` guard — there is **no draw-topology hazard anywhere in this slice**: each sensor draws
  exactly one `randn` per look regardless of rung). `set_fidelity :estimator` needs **no server
  change** (the per-key table from slice 3 validates it; the `:cfar` introduce-guard doesn't match
  `:estimator`). The source-of-truth `ESTIMATOR_MODES = (:pseudolinear, :ml)` lives in the new
  geolocation subsystem file and is **referenced** by `LIVE_FIDELITY_MODES` (the `CFAR_MODES`
  lesson — one list, no drift) — which means the geolocation include must precede the
  `LIVE_FIDELITY_MODES` definition (see Context/landmarks).
- **`geometry.jl` / `estimation.jl` are HANDOFF §9 SHARED LIBS — keep the signatures
  measurement-agnostic NOW, or rewrite them in slice 6 (advisor #4, cheap-now/expensive-later).**
  - `geometry.jl` takes a **Jacobian / geometry matrix**, not bearings: `gdop(H)`, `error_ellipse(C)`,
    `eig2x2(C)` all consume an `H`/`C` and know nothing about angles — so GPS pseudorange DOP reuses
    them verbatim. (`bearing`/`wrap_angle` are the only angle-specific helpers; they can live here or
    move to `geolocation.jl` — they are not what GPS reuses.)
  - `estimation.jl` is a **generic LS + Gauss-Newton scaffold**: a `linear_ls(A, b, W) → (p, cov)`
    (the 2×2 closed-form normal-equation solve) and a `gauss_newton(p0, residual_fn, jacobian_fn, R;
    iters) → (p, cov)` that take **callbacks** — NOT bearings-hardcoded. The bearings-specific
    `A`/`H` construction (the `[sin θ̂, −cos θ̂]` rows, the `wrap`-ed residual) lives in
    `geolocation.jl` (or a thin `bearings_fix` wrapper) and *calls* the scaffold. GPS trilateration
    (slice 6) and the seeker filter then reuse the same `gauss_newton` with their own residual/Jacobian.
    Designing this seam now costs a few extra function boundaries; retrofitting it after bearings is
    baked in is a rewrite.
- **MC-scatter-vs-linearized-ellipse is OFFLINE (`batch.jl` + a Pluto stretch), NOT a live rung.**
  An MC covariance would re-draw the bearings `N_mc` times per fix — a draw-topology hazard that
  would make the rung introduce-unsafe and complicate determinism. The **distribution path belongs
  offline** (its own seeded stream, never `w.rng` — the slice-1 ROC / slice-2 coverage precedent):
  `kind = :geoloc_mc` sweeps the emitter over a grid (or fixes one geometry and re-samples) and
  emits the empirical fix scatter + its sample covariance, to overlay against the analytic CRLB
  ellipse. The **live** path ships only the single deterministic fix + the linearized ellipse.
- **2-D azimuth-only** (planar x-y). Sensors/emitter may carry a z (for a future 3-D view) but the
  bearing, fix, covariance, and ellipse are all 2-D. Named in every docstring.
- **The Godot client gains a NEW plan / top-down (x-y) render mode** — the elevation view (x-z) of
  slices 1/2/4 can't show a 2-D crossing geometry or a ground-plane ellipse. Discriminated at the
  **handshake** off `fidelity[:estimator]` (reusing slice-4's `_fid_kind`: `cfar` | `ep` |
  `propagation` → add `geoloc`), exactly as slice-3's `range_axis_m` flipped to the range-power
  view. The plan view renders: each `:df_sensor` marker + its bearing ray, the `:emitter` truth
  marker, the `:df_station` C2 marker, the **fix point**, and the **error ellipse** (from
  telemetry). The shared fidelity button becomes the **estimator cycler** (`pseudolinear ↔ ml`,
  `set_fidelity`), the slice-3/4 guarded-disconnect pattern. The slice-1/2/4 spatial path and the
  slice-3 cfar path are untouched (their smoke-loads + UI tests stay green).
- **Telemetry exposes the fix/ellipse as SCALARS** (the slice-4 stance — no new array telemetry):
  `<station>.fix_x` / `.fix_y` (the estimate, m), `<station>.err_m` (‖fix − truth‖, the bias/
  accuracy readout — the lesson as a *number*), `<station>.gdop`, and the ellipse
  `<station>.ell_a` / `.ell_b` / `.ell_deg` (semi-axes m + orientation deg). Per-sensor
  `<id>.bearing_deg`. The emitter truth + sensor + station positions ride the normal entity list
  (`_entity_json` already ships `pos` + `kind`), so the client draws *them* from entities and only
  the derived fix/ellipse come from telemetry. **All ellipse/gdop values floored/capped finite**
  (singular geometry → `lin2db`-class Inf/NaN poison; see Watch-items).
- **GDOP sweep is driven by EMITTER MOTION, not a slider** (knobs address `comp` only, never `pos`
  — `scenario.jl`'s `Knob`/`set_param` contract is left unchanged). The emitter flies a path that
  sweeps good→bad geometry (the continuous, automatic killer visual). The **live sliders** are the
  sensors' `sigma_theta_deg` (bearing accuracy → ellipse *size*, the interactive lesson). *(A
  future enhancement could let a knob address `pos` for true drag-the-geometry; out of scope here
  to keep the contract frozen.)*
- **No-DF scenarios stay byte-identical.** Absent any `:df_sensor`/`:df_station`, `env[:bearings]`
  is never written, no DF subsystem runs, and the radar/jammer RNG path is untouched. Slices 1–4
  (and `test_determinism`, the `_sample_z` golden) stay byte-identical — pin it. A DF scenario has
  **no radar**, so the two paths never interact in slice 5 (DF + radar fusion is a future slice).
- **Single emitter** (named scope). The `DFSensor` bearings the *nearest* (sorted-id tie-break)
  `:emitter`, mirroring the radar's `_nearest_target` rule; with one emitter this is unambiguous.
  Multi-emitter (which bearing belongs to which emitter — the association/deinterleave problem) is
  §10 item 6, explicitly deferred.

## Review gates (cadence: staged)
1. **Geometry + estimation primitives green (closed-form + analytic-vs-MC)** — `geometry.jl`
   (`bearing`, `wrap_angle`, `eig2x2`, `error_ellipse`, `gdop`) + `estimation.jl` (`bearings_fix`
   with `:pseudolinear`/`:ml`, returning `(pos, cov)`), both **pure / no `w.rng`**. Tests:
   - `test_geometry.jl` (closed-form, slice-2 style — **explicit `atol`**, never rtol-`≈0`):
     `bearing` signs in all four quadrants + the wrap round-trip (the §1 sign/trifecta anchor);
     `eig2x2` vs a hand-diagonalized matrix (incl. a non-axis-aligned cov → a rotated ellipse
     angle, and `ell_deg` **wrap** at the ±90° boundary); `error_ellipse` axes = `nsigma·√λ` on a
     diagonal cov; `gdop` monotonicity — orthogonal crossing is the **minimum**, collinear sensors /
     emitter on the baseline extension → **huge but finite** (the singular guard) with the ellipse
     **elongated ALONG the LOS** (`ell_deg` points down-range, not across — advisor #3, an
     orientation pin not just a magnitude pin), and a wider baseline lowers gdop; the **far-sensor
     1/R² weighting** (a distant sensor contributes less Fisher info — moving one sensor out widens
     the ellipse, advisor #3); and the **GDOP-is-geometry-only** invariant — `gdop` computed at unit
     σ is **unchanged** when σθ scales, while `error_ellipse` axes scale **linearly** with σθ
     (advisor #2, the σθ-slider-must-not-move-GDOP pin, the closed-form half of it).
   - `test_estimation.jl` (closed-form **+** an MC band, the slice-1 detection pattern):
     noise-free bearings → fix == truth **exactly** for *both* estimators (`atol`); a 2-sensor 90°
     crossing → the geometric intersection; the **pseudolinear bias** as an **external anchor**
     (MC **mean** of the pseudolinear fix is biased away from truth by a known sign at long range —
     check the **mean offset**, not just the covariance: a biased estimator can have right-shaped
     scatter around the wrong centre, advisor #1 — and **`:ml` strictly reduces ‖bias‖**, NOT a
     self-calibrated check, the slice-2/3/4 "don't-pass-by-construction" rule); the **CRLB-vs-MC**
     covariance match tested against the **`:ml`** (≈unbiased) estimator within a Wilson-style band
     for **good** geometry (analytic ellipse ≈ ML MC scatter cov — CRLB bounds the *unbiased*
     estimator, so matching it to the *biased* pseudolinear scatter would be a category error,
     advisor #1) **and** the named **under-prediction** for **bad** geometry (linear ellipse area <
     MC scatter area — pinned as a real effect, the honest approximation boundary). Slices 1–4
     physics tests stay green untouched.
2. **Live fix + linearized ellipse (the DF subsystems wired, no fidelity toggle yet)** —
   `DFSensor <: Subsystem` (phase-3 `observe!` → `env[:bearings]`); `Geolocator <: Subsystem`
   (phase-4 `decide!` → fix/ellipse/gdop telemetry); `:df_sensor`/`:df_station`/`:emitter` kinds in
   `scenario.jl`. Tests (`test_geolocation.jl`, the `test_jammer.jl` analog): `DFSensor` populates
   `env[:bearings]` (record shape + bearing vs the `geometry.jl` closed form — the **first phase-4
   contribution** check is the `Geolocator` reading it); `Geolocator` fix matches `bearings_fix`
   on the realized bearings; telemetry keys present + **finite** (incl. a near-collinear geometry
   → ellipse floored/capped, no Inf/NaN, **no tick throw**); **draw-stream invariance** (the fix
   is drawn once/look, sorted-sensor order; a no-DF scenario byte-identical to slices 1–4 — golden
   + `test_determinism` green); the **GDOP/ellipse stretch** over a closing trace (ellipse `a/b`
   ratio grows as the emitter crosses into bad geometry — deterministic, not the random fix).
3. **`estimator` fidelity + the bias lesson + visible live** — `ESTIMATOR_MODES` joins
   `LIVE_FIDELITY_MODES`; `set_fidelity :estimator` works with **no server change** (introduce-
   safe, the `:ep` contract). `scenarios/slice5_geoloc.yaml` (3 sensors on a baseline + an emitter
   flying through good→bad geometry; `sigma_theta_deg` sliders; numbers tuned **empirically** with
   a throwaway probe + validated against the **live wire path**, the slice-3/4 rule). The Godot
   plan view (sensor markers + bearing rays, emitter truth, fix, **error ellipse**, gdop/err_m
   readout, the `estimator` badge + cycler button + σθ sliders); `net/slice5_verify.gd` (drives the
   real server: the ellipse `a/b` stretches as the emitter closes into bad geometry; `set_param`
   on a sensor's `sigma_theta_deg` scales the ellipse `ell_a`/`ell_b` **while `gdop` stays fixed**
   (advisor #2 on the wire — GDOP is geometry, the slider is σθ) — the slider→core→telemetry
   deliverable; **`set_fidelity :estimator` pseudolinear→ml reduces `err_m`** at the worst-geometry
   sample, and `t` is bit-identical under a held seed); `net/slice5_ui_test.gd` (the estimator cycler + σθ
   slider + badge, mock client, no server); `Sandbox.tscn` smoke-loaded headless against a slice-5
   server; `test_determinism.jl` (mid-run `:estimator` **toggle AND introduce** both bit-identical,
   `fix` differs between rungs proving it is not a dead knob; no-DF-introduce → rng end-state
   unchanged); `test_server.jl` (`set_fidelity :estimator` write/reject + introduce-allowed);
   `test_scenario.jl` slice-5 loader assertions (parse, estimator default, **no radar/jammer**,
   sensor σθ deg→rad pinned via `haskey` — the slice-4 "keys equal defaults so haskey is the
   discriminating check" rule, sensor/emitter geometry on the plan, station present). The plan-view
   `_draw` pixel branch **visually confirmed** via the windowed shot harness (the slice-3/4
   technique, [[ewsim-godot-headless]]): the ellipse stretching + the fix walking toward truth on
   the estimator toggle.
   **(stretch, deferred)** the offline `batch.jl` `kind = :geoloc_mc` + `clients/notebooks/
   slice5_gdop.jl` — the MC-scatter-vs-CRLB-ellipse overlay (the analytic-vs-MC convergence in
   2-D), a closed-form/MC regression test in `test_batch.jl`, **not** a live rung.

## Task checklist
- [ ] 1. **Geometry + estimation primitives (measurement-agnostic, §9 shared-lib signatures).**
      `geometry.jl` (`bearing`, `wrap_angle`, `eig2x2`, `error_ellipse(C)`, `gdop(H)` at **unit σ** —
      all pure, dependency-free closed-form 2×2, `gdop`/`error_ellipse`/`eig2x2` consume an `H`/`C`
      matrix, NOT angles) + `estimation.jl` (the generic scaffold: `linear_ls(A, b, W) → (p, cov)` +
      `gauss_newton(p0, residual_fn, jacobian_fn, R; iters) → (p, cov)` with callbacks + the
      divergence→seed fallback + the singular-det floor; the bearings-specific `A`/`H` rows + the
      `:pseudolinear`/`:ml` `bearings_fix` wrapper call the scaffold). Export both. `test_geometry.jl`
      + `test_estimation.jl` per gate 1 (closed-form signs/wrap/eig/ellipse + gdop monotonicity &
      **σθ-invariance** & ellipse-along-LOS orientation & 1/R² far-sensor weighting; the external
      pseudolinear-**mean-bias** anchor + **ML**-CRLB-vs-MC good-geometry match + bad-geometry
      under-prediction). Wire both into `runtests.jl` after the rf/detection tests. Slices 1–4 green
      untouched.
- [x] 2. **DF subsystems wired (phase 4 lit).** ✅ DONE & green (1015 tests). `DFSensor`/`Geolocator`
      in a new `geolocation.jl`. **Include order corrected (advisor):** the "before radar" rationale
      was stale (gate 1 already moved `ESTIMATOR_MODES` into `estimation.jl`), so the include is
      `… radar.jl → geolocation.jl → scenario.jl` (AFTER radar) — letting it reuse `_range` directly;
      radar.jl confirmed to have NO back-dep on geolocation. `BearingRecord` named-tuple (internal,
      like `JamContribution`); the geolocator's `decide!` → fix/ellipse/gdop telemetry (floored finite,
      `_finite`/`_finite_coord`). **GDOP from emitter TRUTH, not the noisy fix (advisor):** keeps GDOP
      σθ-invariant + jitter-free; ellipse C stays from `bearings_fix` (measured θ̂, σ-scaled).
      `:df_sensor`/`:df_station`/`:emitter` kinds in `_build_entity` (sensor `sigma_theta_deg`>0 at
      LOAD; emitter = `ConstantVelocity`; station = `Geolocator` + optional `geolocator: nsigma`);
      `_validate_geoloc` (≥2 sensors + 1 emitter + station). `LIVE_FIDELITY_MODES` now references
      `ESTIMATOR_MODES` + the Geolocator dispatches `get(w.fidelity, :estimator, :pseudolinear)` — the
      core fidelity plumbing landed early (gate 2), introduce-safe, the Geolocator consumes the key.
      `test_geolocation.jl` (+43: env populated/exact-draw, fix matches `bearings_fix`, finite telemetry
      incl. near-singular, GDOP/ellipse stretch, GDOP-σθ-invariance vs ellipse-σθ-scaling, draw-free rung
      switch, no-DF byte-identity, loader arms). `test_determinism.jl` + a DF scenario bit-identical.
- [x] 3. **`estimator` fidelity + scenario + Godot plan view + verifier.** ✅ DONE & green (1055
      tests; wire + UI machine-verified AND the plan-view `_draw_plan` VISUALLY CONFIRMED 2026-06-30).
      The core fidelity plumbing landed in gate 2 (`LIVE_FIDELITY_MODES[:estimator]` + the Geolocator
      dispatch), so gate 3 was the SCENARIO + client + verifiers + the server/scenario test arms.
      **σθ unit blocker (advisor):** the gate-2 loader stored `comp[:sigma_theta_rad]` but a live
      `set_param sigma_theta_deg` slider must write the SAME key the consumer reads — so degrees is
      now the comp key end-to-end (`comp[:sigma_theta_deg]`, `DFSensor.observe!` converts to rad at
      the consumer; the floor stays in rad). `scenarios/slice5_geoloc.yaml` — 3 sensors on a ±20 km
      y-baseline + a station at centre; the emitter starts abeam (good geometry) and flies +x into
      bad geometry; 3 σθ sliders; default `:pseudolinear`. Tuned EMPIRICALLY (a throwaway probe,
      seed 5): GOOD t=8 s (x=23 km, gdop≈37 k, a/b≈1.85), BAD t=40 s (x=55 km, gdop≈127 k, a/b≈3.6,
      pseudolinear err≈53 km collapsing toward the sensors vs ml≈7 km). Godot `Sandbox.gd` — a NEW
      `"geoloc"` render mode (top-down x-y PLAN view, `_fid_kind → geoloc` off the handshake
      `fidelity.estimator`, NO range_axis_m): `_draw_plan` renders sensor markers + measured bearing
      RAYS (the LOPs), the emitter truth, the C2 station, the fix, and the error ELLIPSE — all from
      telemetry, computed in WORLD coords then mapped through an EQUAL-aspect `_world_to_plan` so the
      ellipse is un-distorted AND the y-flip (screen +y = world +y, UP) renders the ellipse rotation
      / ray directions correctly (advisor #3). The shared fidelity button becomes the estimator
      cycler (`pseudolinear↔ml`, guarded disconnect like cfar/ep). `net/slice5_verify.gd` (real
      server: gdop+ellipse stretch good→bad; `set_fidelity estimator` pseudolinear→ml cuts err_m
      7.77× with bit-identical t; `set_param sigma_theta_deg` on ALL 3 sensors at the GOOD sample
      scales ell_a ∝σθ [tiny σ 0.01°→0.02° for clean 2×, sidestepping the
      [[ewsim-df-ellipse-sigma-monotonicity]] flakiness] while gdop stays BIT-IDENTICAL — advisor #2
      on the wire). `net/slice5_ui_test.gd` (mock client: plan mode + estimator cycler walks/wraps,
      σθ slider sends set_param, reset resyncs). `Sandbox.tscn` smoke-loaded headless against a
      slice-5 server (DONE ⇒ connected, no GDScript errors). **`warmup!` fix:** the ROC-batch warm
      resolves a radar — a DF scenario has none, so it's now guarded on radar presence (the tick! +
      state_frame warm still covers the phase-4 decide! path); `test_server.jl` pins it. Tests added:
      `test_scenario.jl` (slice-5 loader: estimator default, no radar/jammer/cfar/ep, emitter CV/no-rcs
      flying +x, 3 sensors on x=0 baseline with σθ stored RAW in degrees, station+Geolocator, σθ knobs);
      `test_server.jl` (`set_fidelity :estimator` write/reject + introduce-safe; warmup radar-free).
      `_draw_plan` confirmed via 3 windowed shots (good = steep crossings/fix-on-truth/round ellipse;
      bad-pseudolinear = grazing LOPs/fix collapsed to the sensors/stretched ellipse; bad-ml = fix
      walks back to the emitter) — the shot harness ([[ewsim-godot-headless]]).
      **(stretch, deferred)** `kind = :geoloc_mc` batch + `slice5_gdop.jl` Pluto + `test_batch.jl` MC-vs-CRLB.

## Context / landmarks
- **Phase 4 is the seam.** `decide!` (`subsystem.jl:17`) is a no-op default, invoked in phase 4 of
  `tick!` (`subsystem.jl:32`) **after** `observe!` (phase 3) — so a `DFSensor.observe!` writing
  `env[:bearings]` is guaranteed visible to a `Geolocator.decide!` *the same tick*, no ordering
  hazard (the same correctness-by-construction the jammer→radar coupling got from phase-2-before-3).
  `env` is cleared + rebuilt each tick (`tick!`, `subsystem.jl:29`), so a stale fix can't leak.
- **The `env` coupling template is `Jammer`** (`radar.jl:218` `build_env!` → `radar.jl:337`
  `observe!` read). Copy its shape: a `const BearingRecord = @NamedTuple{...}`, a `get!`-into-`env`
  append in the producer, an additive/collect read in the consumer. The jammer's per-radar Dict
  (`env[:jamming][rid]`) maps to a per-station (or flat) `env[:bearings]` here.
- **The fidelity table** is `LIVE_FIDELITY_MODES` (`radar.jl:102`), the per-key source of truth the
  server's `set_fidelity` validates (`server.jl:160`). Add `estimator = ESTIMATOR_MODES`. **Include
  order (advisor #5 — resolve BEFORE writing code; it is a hard `using EWSim` compile failure
  otherwise):** the current order is `world → subsystem → protocol → rf → detection → radar →
  scenario → batch → server` (`EWSim.jl:16-24`). Slot the new files as:
  `… detection.jl → geometry.jl → estimation.jl → geolocation.jl → radar.jl → …`. Rationale:
  `geometry.jl`/`estimation.jl` (gate 1) are pure and depend only on `world.jl` + `StaticArrays`;
  `geolocation.jl` (gate 2, defining `ESTIMATOR_MODES` + `DFSensor`/`Geolocator`) depends on
  `subsystem.jl` + `world.jl` + `geometry.jl` + `estimation.jl` but **NOT** `radar.jl` (verify: the
  DF subsystems need world/subsystem/geometry/estimation, never a radar symbol). With
  `geolocation.jl` *before* `radar.jl`, `LIVE_FIDELITY_MODES` can reference `ESTIMATOR_MODES` and
  stays put. **Fallback only if a back-dep on `radar.jl` surfaces:** move `LIVE_FIDELITY_MODES` to a
  tiny post-include registry after both files. Decide (and confirm no back-dep) at gate 2.
  `:estimator` carries **no** introduce-guard (the `:cfar` guard at `server.jl:172` does not match
  it — introduce-safe).
- **The loader** `_build_entity` (`scenario.jl:91`) is the `kind`-dispatch — add `:emitter`
  (≈ `:target`: `ConstantVelocity`, minimal comp), `:df_sensor` (a sensor block + a `DFSensor`
  subsystem — like `:radar` owning `RadarSensor`), `:df_station` (a `Geolocator` subsystem; closest
  template is the jammer arm which owns a subsystem, `scenario.jl:114`). `sigma_theta_deg`→
  `comp[:sigma_theta_rad] = deg2rad(...)` mirrors `beamwidth_deg` (`scenario.jl:83`). Update the
  unknown-kind error list (`scenario.jl:133`). A `_validate_geoloc` (≈ `_validate_cfar`,
  `scenario.jl:208`) can assert "a geoloc scenario has ≥2 sensors + exactly one emitter + a station"
  at LOAD (a clear load error, not a tick `KeyError`).
- **The handshake static channel** is `scenario_frame` + `_cfar_axis_info` (`server.jl:90`,
  `radar.jl:466`). Sensor positions are static but already ride the entity list, so **no new
  handshake field is needed** — the client discriminates the plan view off `fidelity[:estimator]`
  in the handshake's `fidelity` map (already shipped, `server.jl:100`).
- **Telemetry → wire** is generic (`protocol.jl:73` `state_frame` reads `env[:telemetry]`); the
  floor helper is `_snr_db_wire`/`_SNR_DB_FLOOR` (`radar.jl:109`) — but the DF readouts are metres/
  degrees, not dB, so add a small **finite-clamp** helper (cap + NaN/Inf guard) rather than reuse
  the dB floor. Fix/ellipse are plain scalars (number telemetry — no array widening needed).
- **No-LinearAlgebra house style:** `_range` (`radar.jl:69`) does Euclidean distance via
  `StaticArrays` + `sum` to avoid a `LinearAlgebra` dep. The 2×2 normal-equation solve, the 2×2
  inverse, and `eig2x2` are all closed-form — keep the same dependency-free style (do **not** pull
  in `LinearAlgebra`/`inv`).
- **Frame convention** (`world.jl:7`): `pos = [x, y, z]`, SI, inertial. DF works the **x-y** plane;
  the existing spatial view is **x-z** (elevation) — hence the new plan (x-y) view.

## Watch-items (gotchas to bake in)
- **Singular / ill-conditioned geometry → Inf/NaN on the wire.** Collinear sensors, or the emitter
  on the baseline, make `AᵀWA` / `HᵀR⁻¹H` singular → the 2×2 inverse blows up → `fix`/`gdop`/ellipse
  go Inf/NaN → JSON poison (the recurring slice-1 `%g` / slice-2 null / slice-3 array watch-item).
  Guard at the **consumer**: floor the determinant (a ridge/`max(det, ε)`), **cap** the covariance
  + ellipse axes + gdop to a large-but-finite ceiling, and clamp before telemetry. A **live σθ
  slider** (→0 or huge) and the emitter crossing the baseline can both drive this, so it must
  **never throw a tick** (the slice-2/3/4 "a live config can't crash a tick"). Test a near-collinear
  geometry explicitly.
- **Angle sign + wrap (the §1 bug trifecta).** `atan(Δy, Δx)` argument order, and **every** residual
  `wrap(θ̂ − θ)` to (−π, π]. An unwrapped residual near ±π injects ~2π and yanks the fix; a flipped
  atan2 is the LOS-rate-sign bug. Pin sign round-trips in all four quadrants + a wrap-boundary case
  from day one (HANDOFF §1).
- **No draw-topology hazard — but PROVE it** (the slice-4 pattern, the contrast to slice-3's `:cfar`
  guard *is* a lesson): each sensor draws exactly one `randn`/look independent of the `:estimator`
  rung. Pin (a) no-DF byte-identity vs the slice-1 golden; (b) the fix differs between rungs while
  the `w.rng` end-state is identical; (c) mid-run `:estimator` toggle **and** introduce both
  bit-identical.
- **Fixed-iteration ML, never until-convergence — AND a divergence fallback (advisor #6).** A
  `while !converged` loop inside `decide!` could spin (bad geometry → slow/no convergence) and stall
  the tick non-deterministically. Use a fixed iteration count (named) so a tick is bounded and
  bit-reproducible. But the count bounds *time*, not the *result*: a GN step under bad geometry can
  overshoot to NaN or walk the fix away from the data. So guard each step (singular-`HᵀR⁻¹H` det
  floor; reject a step that yields a non-finite `p̂` or grows the residual norm) and **fall back to
  the pseudolinear seed** on divergence — `:ml` *seeds* from pseudolinear, so the worst case is "no
  better than pseudolinear," never NaN/spin. The singular-det floor alone (next item) covers the
  2×2 inverse, **not** GN divergence — they are two distinct guards.
- **The linearized ellipse is an approximation** — name it; it under-predicts the true scatter under
  bad geometry. The offline MC stretch (gate-3 stretch) quantifies *where*; do **not** silently
  present the linear ellipse as ground truth (HANDOFF §1: no hidden approximations).
- **2-D azimuth-only** — named; z is carried but ignored for the bearing/fix/ellipse. A scenario
  giving sensors/emitter altitude has it projected to the x-y plane for DF. Say so.
- **Weights `W` need a range estimate** the pseudolinear fix doesn't have a priori. Seed `R̂ᵢ` from
  an unweighted first pass (or the sensor→origin range), then optionally one re-weight — name the
  choice; an inconsistent `R̂ᵢ` biases the weighting (a subtle, real DF gotcha).
- **Deferred to future slices, explicitly NOT here:** multi-emitter association / PRI-histogram
  deinterleaving (§10 item 6), range/SNR-dependent σθ (a seeker/emitter-power coupling), 3-D AOA
  ellipsoids, DF + radar/jammer fusion in one scenario, the live MC-covariance rung (offline only).
  Listing them keeps the slice-5 boundary honest.
