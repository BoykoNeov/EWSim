# Slice 7 — GPS (pseudoranges → trilateration → DOP + RAIM)

The **shared-library reuse milestone** — the slice that cashes in HANDOFF **§9** ("why the
suite is one project, not four"). Slices 5 and 6 lit the last two tick phases (`decide!`,
then all three derived phases in one pipeline); slice 7 lights **no new phase** — it reuses
the same `build_env!`→`observe!`→`decide!` shape a third time (satellites publish ephemeris →
a receiver measures pseudoranges → a solver trilaterates). Its novelty is **cross-domain code
reuse**: the *same* `geometry.jl` DOP math that drew a DF error ellipse now computes GPS
dilution-of-precision, and the *same* `estimation.jl` least-squares scaffold that fixed a DF
emitter now trilaterates a receiver — **generalized from 2 unknowns to 4** (x, y, z, and the
receiver clock bias, the classic "4th satellite pins the clock"). That the DF-geolocation
covariance code and the GPS-DOP code are *literally the same functions* is the §9 "aha" this
slice exists to demonstrate. Source of truth: `HANDOFF.md` §9 (the reuse map — GPS-DOP ≡ DF
ellipse, GPS trilateration ≡ DF fix, both call the shared libs), §10 (item 7 — "pseudorange =
true range + separately-toggleable error terms [clock, iono, tropo, multipath, noise];
trilateration, DOP, RAIM from residuals"), §3 (the four-phase tick + `env` coupling), §1
(named approximations; **units** are first-class — pseudoranges/positions are metres, the
clock bias is carried as `c·b` in **metres**, a seconds/metres slip is exactly the trifecta),
§12 (the fidelity badge).

The **first lesson is DOP**: identical measurement noise on every pseudorange yields a tight
fix when the satellites are spread across the sky and a smeared fix when they cluster — the
geometry, not the ranging accuracy, sets the position error (`σ_pos = DOP·σ_range`). Because
the satellites sit far *overhead* (all ranges arrive from above — one-sided vertical
information), a realistic upper-hemisphere spread typically shows **VDOP > HDOP** (a bonus
geometry lesson — but a *property of the placement*, not a guarantee; verify it on the actual
constellation in the gate-1 probe). The **second lesson is RAIM**
(Receiver Autonomous Integrity Monitoring): with more than the minimum four satellites the fix
is over-determined, so the least-squares *residuals* carry a consistency check — a single
faulty / spoofed satellite inflates the residual sum-of-squares above a threshold (**detect**,
raising an integrity flag), and dropping the largest-residual satellite and re-solving
(**exclude**) snaps the fix back toward truth. Toggling each error term on/off and watching the
error budget grow, sweeping the constellation to watch DOP breathe, and ramping a satellite's
injected bias until RAIM alarms — those are the interactive lessons.

**Scope (one lesson per scenario — the slice-3 principle), split across TWO scenarios (the
slice-4 selfscreen+standoff precedent):** a **DOP / error-budget** scene (`slice7_dop.yaml` —
a clean constellation, the five error toggles, a slow satellite drift that sweeps DOP
good→bad) and a **RAIM / fault** scene (`slice7_raim.yaml` — an over-determined constellation,
one faulted satellite, the `raim` rung + a fault-bias slider). **Flat-local fictional
satellites** (SI `Vec3`, the project's frozen flat-earth/inertial frame — NO ECEF/WGS84/orbit
propagation); **single receiver**; **azimuth+elevation sky geometry** but a full 3-D position
solve (x, y, z, clock). Explicitly deferred: real orbital mechanics / ephemeris, the
Klobuchar/Saastamoinen error models (simplified analytic forms here), multi-constellation /
carrier-phase / RTK, multi-fault RAIM (single-fault assumption), and **GPS spoofing as
RGPO-from-the-EW-module** (HANDOFF §9 notes RGPO ≡ GPS spoofing; the *cross-module* fusion is a
future slice — here a "fault" is a static/slider bias, not a live RGPO jammer). 3 review gates
(mirroring slices 5–6: pure primitives → subsystems wired → fidelity + scenarios + client +
verifiers).

**Done =** start the server on `slice7_dop.yaml`, connect Godot, watch (in a **new GPS / sky
view**) the satellites plotted on a sky plot, the receiver's fix sitting near truth with a live
HDOP/VDOP/PDOP/GDOP/TDOP readout, and the position error breathe as the constellation drifts
(DOP good→bad); toggle each of `iono / tropo / clock / multipath / noise` and watch that term's
contribution enter/leave the error budget; then `load_scenario slice7_raim.yaml`, ramp the
**fault-bias slider** on the spoofed satellite and watch its residual bar spike and the **RAIM
integrity flag raise** at the crossover (`raim = :detect`), then cycle `raim → :exclude` and
watch the bad satellite drop out and the **fix snap back toward truth** (`pos_err_m` collapsing
on the readout) — with `runtests.jl` green on the new closed-form GPS tests and slices 1–6
untouched and still **byte-identical** (the 2×2 estimation/geometry code is NOT modified — GPS
uses NEW N-dim siblings — and no GPS subsystem touches the radar/jammer/DF/ESM RNG path).

## The physics / math (named approximations — HANDOFF §1)

Pseudorange positioning. Everything **SI metres / seconds internally**; the receiver clock bias
is carried as **`c·b` in metres** (the standard GPS unknown-vector convention — it keeps the
4×4 normal matrix well-scaled) and converted to a time (ns/µs) only at the telemetry boundary
(the §1 units trifecta — a metres/seconds slip on the clock term is this slice's signature
bug). The whole slice is **deterministic given the drawn pseudoranges** (the fix, DOP, and RAIM
are closed-form / fixed-iteration), so — like slices 2/4/5/6, unlike slice 3 — there is **no
draw-topology hazard** (see Decisions).

### 1. The pseudorange model + the error budget (`gnss.jl`, pure / no RNG)
- **Flat-local fictional satellites (named approximation — HANDOFF §1).** A `:gps_satellite`
  is a far-away point source at a `Vec3` position in the sim's inertial SI frame (e.g.
  ~20 000 km "up" and spread in azimuth/elevation). **NO ECEF/WGS84, NO Keplerian orbit
  propagation** — a satellite is a slowly-moving point (`ConstantVelocity`, a small drift to
  sweep DOP). This is the whole project's flat-earth/inertial stance (HANDOFF §1 frozen
  decisions); real orbital mechanics is a future extension. Name it; don't imply orbit realism.
- **Pseudorange for satellite `j`** (receiver at `p_rx`, clock bias `b` seconds):

      ρⱼ = ‖pⱼ − p_rx‖  +  c·b  +  εⱼ^iono + εⱼ^tropo + εⱼ^clk + εⱼ^mp + εⱼ^noise

  The four **unknowns** solved for are `(x, y, z, c·b)`. Four satellites → an exact solve;
  **five or more → over-determined → RAIM** (the residuals become a consistency check).
- **The five error terms — separately toggleable (the fidelity knobs, HANDOFF §10 item 7).**
  Two families, chosen so the lesson separates **bias** (shifts the fix systematically —
  DOP-independent, RAIM-relevant) from **variance** (inflates the scatter — DOP-amplified):
  - **`iono` (ionospheric delay) — DETERMINISTIC bias.** A positive range error (signal
    delayed), **elevation-scaled** by an obliquity factor (low-elevation satellites see more
    atmosphere → larger delay). Named approximation: a simple `zenith_delay / sin(el)`-style
    obliquity model, **NOT Klobuchar**.
  - **`tropo` (tropospheric delay) — DETERMINISTIC bias.** Same shape (elevation-scaled
    positive delay), a simple mapping function, **NOT Saastamoinen**.
  - **`clock` (satellite clock error) — DETERMINISTIC bias.** A per-satellite constant offset
    (the SV clock error not captured by the broadcast correction). NB this is the *satellite*
    clock; the *receiver* clock bias `b` is a solved unknown, never an error term (name the
    distinction — a common confusion).
  - **`multipath` — STOCHASTIC, elevation-weighted.** `εⱼ^mp = mp_factor(elⱼ)·σ_mp·randn`
    (worse at low elevation). A drawn term (see the draw-order pin).
  - **`noise` (receiver thermal / measurement noise) — STOCHASTIC.** `εⱼ^noise = σ_noise·randn`.
    A drawn term.
  - **Draw discipline (the §1 draw-topology invariant, on a new surface).** The two stochastic
    terms are **always drawn, every configured satellite, every epoch — the contribution is
    gated by the toggle, never the draw.** `iono/tropo/clock` are deterministic, so toggling
    them adds/removes a computed bias with no draw at all. So all five toggles (and the RAIM
    rung, and the fault slider) change only the *value* fed to the solver, never the *number*
    of `randn` — the draw-count-invariant trick that makes every fidelity key introduce-safe
    and toggle-bit-identical (see Decisions).
- **Named approximation — geometry frozen over the epoch, R/c signal-travel modeled as instant.**
  The satellite range is evaluated once per look; there is no light-time iteration (a constant
  per-satellite offset that a real receiver corrects and that is inert for the DOP/RAIM lesson).

### 2. Trilateration (the fix) — reuse `estimation.jl`, generalized 2→4 (`gnss.jl`)
- The measurement `ρⱼ = ‖pⱼ − p_rx‖ + c·b + εⱼ` is **nonlinear** in `p_rx`, so the fix is an
  **iterated least-squares** (Gauss-Newton) — the SAME `gauss_newton` scaffold slice 5's `:ml`
  DF fix used, called at **N = 4** with a GPS residual/Jacobian:
  - **residual** `rⱼ = ρⱼ − (‖pⱼ − p̂_rx‖ + c·b̂)`;
  - **Jacobian row** `Hⱼ = [−ûⱼ, 1]` where `ûⱼ = (pⱼ − p̂_rx)/‖pⱼ − p̂_rx‖` is the unit
    line-of-sight from the receiver to satellite `j` (three components) and the trailing `1` is
    `∂ρ/∂(c·b)`. This `[−û, 1]` is the classical GPS geometry matrix — the DF `[sinθ, −cosθ]`
    row's 4-D cousin.
  - Seeded at a fixed initial guess (scene origin / receiver's nominal position — draw-free, so
    the fix is deterministic). Fixed iteration count + divergence→seed fallback are **inherited
    unchanged** from `gauss_newton` (the named approximation already documented there).
- **The 2→4 generalization (the crux decision — advisor-reconciled to option (b)).** `estimation.jl`
  and `geometry.jl` are today **hardcoded 2×2** (`_solve2x2` cofactor, `SVector{2}`,
  `SMatrix{2,2}`). GPS needs a **4×4** solve. The decision: **GENERALIZE the inner solve to N
  unknowns and have the existing 2×2 call sites delegate to it at N=2** — the honest reading of
  §9 reuse (and exactly what geometry.jl's own docstring already promises: *"the CALL SITES are
  unchanged — only the inner 2×2 inverse generalises"*). This makes the slice's §9 headline
  **literally true** (DF geolocation and GPS DOP call the SAME solver) rather than a family
  resemblance. It is byte-safe: the DF value tests are all **atol-guarded or inequalities**
  (`test_geometry.jl:33–139`, `test_estimation.jl:77–106` — grep-confirmed, no absolute-literal
  golden), and `test_determinism.jl:234/246/253` compare run-A-vs-B (`reinterpret`, both runs on
  the new code), so a ULP-scale reformulation breaks nothing. **The call-site logic is
  untouched** — `linear_ls`/`gauss_newton`/`bearings_fix` keep their signatures, the two-pass
  weighting, the relative det-ridge, and the divergence→seed fallback; only the innermost
  `_solve2x2` is replaced by a generic `_solve_normal` over N. The inner solve is a **hand-rolled
  Cholesky / LDLᵀ** (the normal matrix `HᵀR⁻¹H` is symmetric PSD), generic over N, ~15 lines of
  plain loops, with the relative ridge folded in as PSD regularization — **NOT** StaticArrays'
  `inv` (out of the `_range` no-LinearAlgebra house style) and **NOT** the O(N!) cofactor
  extended. Cholesky yields both the solve (the fix) and the inverse (the covariance → DOP) in
  one factorization. **Gate-1 obligation:** re-run the slice-5/6 value + determinism tests after
  the generalization to confirm the tolerances survive; **fallback (a)** — if any tolerance
  surprises, add pure N-dim *siblings* and leave the 2×2 code untouched instead (zero-risk, at
  the cost of a duplicated inner solve and a softened "same file, generalized" headline).

### 3. DOP — reuse `geometry.jl`, decomposed (`geometry.jl` extension)
- **`Q = (HᵀH)⁻¹`** at **unit measurement variance** (geometry only — the classical,
  dimensionless DOP, since `û` is dimensionless and the clock column is `1`). This is the SAME
  `gdop` math (`√trace((HᵀH)⁻¹)`), extended to 4×4 and **decomposed** by pulling specific
  diagonals of `Q` (in the receiver's local frame, x-y horizontal, z vertical, the 4th
  time/clock):
  - **GDOP** `= √(Q₁₁+Q₂₂+Q₃₃+Q₄₄)` (the existing `gdop` at N=4),
  - **PDOP** `= √(Q₁₁+Q₂₂+Q₃₃)` (position),
  - **HDOP** `= √(Q₁₁+Q₂₂)` (horizontal),
  - **VDOP** `= √Q₃₃` (vertical — typically the worst for an overhead spread, verify per-layout),
  - **TDOP** `= √Q₄₄` (time/clock).
  This is an **extension of the shared lib in the §9 "extend, don't fork" spirit** — a generic
  N-dim `dop(H) → Q` plus a GPS-facing `dop_components(Q)`; `gdop` stays measurement-agnostic
  (advisor). **DOP must NOT be σ-weighted** (the slice-5 lesson: the σθ-invariance trap — DOP is
  pure geometry; the pseudorange σ enters `σ_pos = DOP·σ_range` at the readout, not inside `Q`).
- **The lesson:** identical `σ_range` on every satellite, but the fix error scales with DOP —
  clustered satellites (small crossing angles) → huge DOP → smeared fix; spread satellites →
  DOP ≈ 1–2 → tight fix. The DOP sweeps as the constellation drifts (the interactive lever).

### 4. RAIM — from the residuals (`gnss.jl`, the second lesson)
- **Over-determination is the whole trick.** With `n ≥ 5` satellites the LS fit leaves `n − 4`
  degrees of freedom in the residual vector `r`; a self-consistent constellation drives `r → 0`,
  a **faulty satellite** (a biased/spoofed pseudorange) cannot be absorbed by the 4 unknowns
  and leaks into `r`.
- **`raim = :detect` (fault detection).** Test statistic on the residual sum-of-squares,
  `raim_stat = √(SSE / (n − 4))` (the range-residual RSS test — a **named approximation** of the
  parity-space method, single-fault assumption), compared to a threshold `T` set from a configured
  false-alarm rate. `raim_stat > T` → the **integrity flag** raises. A **protection level**
  (HPL/VPL ≈ slope_max·T) ships as a readout (named approximate — the max-slope bound).
  - **Threshold route — a gate-1 DECISION, not committed here (advisor — the no-SpecialFunctions
    house style).** The textbook `T = σ_range·√(χ²_{1−Pfa}(n−4))` needs a χ² inverse-CDF =
    incomplete-gamma, which the project has avoided for six slices. The χ² CDF is a clean finite
    sum only for **even** integer DOF (integer-shape Erlang — the exact idiom `detection_threshold`
    already bisects); `n=6` → DOF 2 (clean), but **exclude-and-retest drops to `n=5` → DOF 1
    (odd → needs erf)** — the retest is the snag, not the initial detect. Pick a route in the
    gate-1 probe, all three teaching-equivalent: (i) **reuse the CFAR Erlang-bisection**
    (`detection_threshold`) and keep **DOF even by construction** (constellation sized so detect
    and retest both land on even DOF); (ii) a **tiny hardcoded χ² table** for the few DOF in play;
    (iii) an **empirical σ-multiple threshold** authored per-scenario (the slice-3/4/5/6
    probe-tuning discipline) — dropping the χ²/Pfa formulation entirely. Do **not** pin the χ²
    quantile in the plan; the gate-1 probe chooses.
- **`raim = :exclude` (fault detection AND exclusion).** On alarm, identify the suspect by the
  **largest normalized residual** `|rⱼ|/σ` (a named simplification of the max-slope /
  parity-vector fault ID — single-fault), **drop that satellite and re-solve** with `n − 1`.
  The fix snaps back toward truth; the flag clears if the retest passes. **Re-solving is
  post-draw** (a filter on which measurements enter the phase-4 solve) — it changes NO draw
  (the invariant).
- **`raim = :off`** — no integrity check (the flag never raises even under a fault; the naïve
  baseline that trusts a spoofed satellite — the lesson's "before" state).
- **Fault injection is DETERMINISTIC.** A `:gps_satellite` carries a `fault_bias_m` (a static
  bias added to its pseudorange — a spoof / SV failure). The RAIM scenario sets it; a live
  `fault_bias_m` slider ramps it from below to above the detection threshold (the not-a-dead-
  knob crossover — the slice-4 burn-through / jammer-power precedent). No draw (the bias is a
  constant), so the fault slider is draw-count-safe.

### 5. The "lesson as a number" (the scalars the verifier pins)
- **DOP scene:** `hdop`/`vdop`/`pdop`/`gdop`/`tdop` (the decomposition, sweeping with the
  drift; **VDOP > HDOP** pinned), and `pos_err_m = ‖fix − truth‖` tracking `PDOP·σ_range` — each
  error toggle's contribution to `pos_err_m` is the error-budget lesson.
- **RAIM scene:** `raim_flag` (0/1 — the load-bearing scalar that **raises** as the fault slider
  crosses the threshold), `raim_stat` (the residual RSS), `n_sats_used` (drops by 1 under
  `:exclude`), `fault_sat` (which satellite was excluded), and `pos_err_m` (**collapses** when
  `:exclude` removes the biased satellite — the snap-back, the slice-5 `err_m` precedent).

## Decisions taken (advisor-reviewed 2026-07-01 — architecture endorsed, RAIM depth chosen by the user)
- **The 2→4 generalization: GENERALIZE the inner solve, 2×2 call sites delegate at N=2
  (advisor-reconciled option (b)).** See math §2. The innermost `_solve2x2` is replaced by a
  generic `_solve_normal` (plain-loop Cholesky over `N`); `linear_ls`/`gauss_newton`/`bearings_fix`
  keep their signatures + two-pass/ridge/fallback logic and call it at N=2, so DF geolocation and
  GPS DOP share the SAME solver (the §9 headline made literal + geometry.jl's docstring honored).
  Byte-safe (the DF value tests are atol/inequality, grep-confirmed; determinism is run-A-vs-B).
  Geometry likewise gains a generic `dop(H) → Q` + `dop_components(Q)`; `gdop` stays a
  measurement-agnostic call into it. **Gate-1 obligation:** re-run slice-5/6 value + determinism
  tests; **fallback (a)** if a tolerance surprises — pure N-dim siblings, 2×2 untouched, softened
  headline. Pin at gate 1 that the N=2 solve reproduces the pre-refactor DF fix (atol) and slices
  5–6 stay green.
- **Flat-local fictional satellites (advisor — the only frame consistent with HANDOFF).** SI
  `Vec3`, no ECEF/WGS84/orbits. Satellites as far point sources; VDOP > HDOP is the *typical*
  consequence of a one-sided upper-hemisphere spread (a property of the placement, confirmed in
  the gate-1 probe — not a universal). Named in the docstrings.
- **Fidelity = FIVE per-error-term toggle keys + the RAIM rung.** `iono`, `tropo`, `clock`,
  `multipath`, `noise` each `∈ (:off, :on)`; `raim ∈ (:off, :detect, :exclude)`. This fits the
  existing `LIVE_FIDELITY_MODES` (one symbol per key) + `set_fidelity` (per-key validation,
  `server.jl:166`) with **zero server change** — verified key-generic (the only hardcoded case
  is the `:cfar` introduce-guard at `server.jl:177`, which matches none of these). Every GPS key
  is **introduce-safe AND toggle-bit-identical** (the `:ep`/`:estimator`/`:deinterleaver`
  contract — no draw-topology hazard anywhere in the slice). The source-of-truth mode constants
  `GPS_TOGGLE = (:off, :on)` and `RAIM_MODES = (:off, :detect, :exclude)` live in `gnss.jl` and
  are **referenced** by `LIVE_FIDELITY_MODES` (the one-list-no-drift lesson — so `gnss.jl`
  precedes the `LIVE_FIDELITY_MODES` definition; see landmarks). **Namespace note:** the keys are
  generic words (`noise`, `clock`) but are namespaced **by consumption** — only a `GpsSolver`
  reads them (exactly as `:estimator` is inert without a `Geolocator`), so a non-GPS scenario
  toggling one is a harmless no-op. GPS does **NOT** reuse the `:estimator` rung — its estimator
  is a fixed iterated-LS; the *fidelity* is the error terms + RAIM (say so — keep the reuse
  story honest: GPS reuses the *scaffold*, not the DF *rung*).
- **Entity/subsystem model — three subsystems across three phases (the slice-6 shape, reused).**
  A **`:gps_satellite`** entity carries `ConstantVelocity` + **`GpsSatellite`** (phase-2
  `build_env!` → publishes its ephemeris [`id`, `pos`, `clock_err`, `fault_bias`] to
  `env[:gps_sats]`; RNG-free, sorted-id append order — the `EmitterParams`/`JamContribution`
  shape). A single **`:gps_receiver`** entity carries `ConstantVelocity` (usually static) +
  **`GpsReceiver`** (phase-3 `observe!` → reads `env[:gps_sats]`, generates + measures the
  pseudorange vector into `env[:pseudoranges]`; the ONE draw site, on look-ticks) +
  **`GpsSolver`** (phase-4 `decide!` → reads the pseudoranges, trilaterates + DOP + RAIM per the
  fidelity, publishes telemetry). The §3 coupling done right — satellites→receiver and
  receiver→solver both **through `env`**, never a direct call — the DFSensor→Geolocator /
  ESMReceiver→Deinterleaver pattern, here with the receiver+solver co-located on one entity for
  an independently-testable `env[:pseudoranges]` handoff.
- **`env[:gps_sats]` is a VECTOR of ephemeris records** (`const SatEphemeris = @NamedTuple{
  id::Symbol, pos::Vec3, clock_err::Float64, fault_bias::Float64}`), appended in sorted-satellite-id
  order (so the receiver's draw order across satellites is deterministic — the §1 bug class made
  free). `env[:pseudoranges]` is a record carrying the parallel `Vector{Symbol}` sat ids +
  `Vector{Float64}` measured ρ + the `Vec3` satellite positions the solver needs (INTERNAL, like
  `BearingRecord`/`ToaStream`). The solver re-reads `env[:gps_sats]` for the geometry.
- **`gnss.jl` is a new HANDOFF §9-style SHARED math lib** (the `deinterleave.jl` analog — pure,
  no RNG, closed-form, dependency-free base Julia + StaticArrays). It holds the GPS-specific math
  (pseudorange residual/Jacobian builder, `position_fix`, `dop_components`, the RAIM statistic +
  fault ID + exclude re-solve) and **reuses the generalized `estimation.jl`/`geometry.jl`
  scaffolds**. `gps.jl` holds the SUBSYSTEMS (the `esm.jl`/`geolocation.jl` analog), included
  after `radar.jl`.
- **The pseudorange draw lives in `observe!`, on LOOK-TICKS ONLY** (the receiver's `revisit_s`
  cadence — the `next_look_t` gate the radar/ESM already use). Between looks the last
  realization is republished (the "readout never blanks" pattern).
- **Telemetry: scalars (assert on these) + variable-length per-satellite display arrays (NEVER
  assert — the slice-6 rule).** Scalars: `pos_err_m`, `fix_x`/`fix_y`/`fix_z` (signed
  `_finite_coord`), `clock_bias_ns` (the solved `c·b` converted to time at the boundary),
  `hdop`/`vdop`/`pdop`/`gdop`/`tdop`, `raim_stat`, `raim_flag`, `n_sats_used`, `fault_sat`,
  `protection_level_m` — all `_finite`-clamped (reuse geometry.jl's `_finite`/`FINITE_CEIL`).
  Display-only variable arrays: `sat_az_deg`/`sat_el_deg` (the sky plot), `sat_resid_m` (the RAIM
  residual bars), `sat_used` (bool per satellite — in-solve / elevation-masked / RAIM-excluded).
  The satellites move, so **there is no static handshake axis** (unlike CFAR's `range_axis_m` /
  ESM's `pri_axis_us`); the **GPS-view discriminator is `raim ∈ fidelity`** at handshake (raim is
  GPS-unique — the `range_axis_m`→cfar / `estimator`→geoloc precedent).
- **Live sliders + the fidelity buttons.** DOP scene: the five error toggles + (no fault). RAIM
  scene: the `fault_bias_m` slider on the spoofed satellite + the `raim` cycler. `σ_range`,
  `σ_mp`, satellite count, `Pfa`, the elevation mask are LOAD-TIME static (draw-count / geometry
  defining). Satellite **motion** (the DOP sweep) is scenario-authored drift, not a slider — the
  interactive levers are the error budget (toggles), the fault (slider), and the algorithm
  (RAIM cycler); the constellation drifts on its own (the slice-5 emitter-motion precedent for
  making the geometry lesson visible).
- **The Godot client gains a NEW GPS / sky render mode** — none of the existing views (x-z
  elevation, x-y plan, range-power, ESM raster) shows a sky plot + a satellite-residual bar
  chart. Discriminated at the handshake off `raim ∈ fidelity` (extend the `_fid_kind`
  discriminator → add `gps`). Panels: a **sky plot** (polar az/el — zenith center, the geometry→
  DOP visual; satellites colored used/masked/excluded/faulted), a **residual bar chart** (per-
  satellite `sat_resid_m` — the faulted bar spikes, the RAIM visual), and a **DOP + error
  readout**. The shared fidelity button becomes the `raim` cycler (`off→detect→exclude`); the
  **five error toggles are a new button ROW** (the UI departure — advisor: 5 toggles, not one
  cycler — the one genuinely new client-UI element this slice adds) + the fault slider. The
  slice-1..6 views are UNTOUCHED (their smoke-loads + UI tests stay green).
- **No-GPS scenarios stay byte-identical.** Absent any `:gps_satellite`/`:gps_receiver`,
  `env[:gps_sats]`/`env[:pseudoranges]` are never written, no GPS subsystem runs, and the
  radar/jammer/DF/ESM RNG path is untouched. Slices 1–6 (and `test_determinism`, the `_sample_z`
  golden) stay byte-identical — pin it. A slice-7 scenario has **no radar/jammer/DF/ESM** (GPS +
  EW fusion — RGPO spoofing — is a future slice).

## Review gates (cadence: staged, mirroring slices 5–6)
1. **Primitives green (pure, closed-form).** The generalized scaffolds + the GPS math lib, all
   pure / no `w.rng`, dependency-free (base Julia + StaticArrays), SI metres/seconds in/out.
   - **`estimation.jl` / `geometry.jl` N-dim siblings** — a hand-rolled generic Cholesky solve +
     inverse; `gauss_newton_n` (or a generic normal-solve the GPS fix calls); a generic `dop(H)`
     + `dop_components(Q) → (gdop,pdop,hdop,vdop,tdop)`. **The 2×2 code is NOT touched.**
   - **`gnss.jl`** — the pseudorange residual/Jacobian builder (`[−û, 1]` rows), `position_fix(
     sat_positions, pseudoranges; seed, iters)`, the error-term models (deterministic iono/tropo/
     clock as pure functions of geometry; the stochastic mp/noise taking a pre-drawn value),
     `raim_statistic`, `raim_exclude` (fault ID + re-solve), `GPS_TOGGLE`/`RAIM_MODES`.
   - `test_gnss.jl` (+ N-dim additions to `test_estimation.jl`/`test_geometry.jl`) — closed-form,
     slice-2 style (**explicit `atol`**, never rtol-`≈0`):
     - **noise-free fix == truth exactly** (4 satellites, all errors off → `pos_err_m ≈ 0`,
       clock bias recovered); the reuse pin — **the N=2 Cholesky sub-case matches `_solve2x2`** on
       a shared 2-unknown example (the generalization is faithful, not a fork);
     - **DOP decomposition vs an independent recompute** (a known geometry; `VDOP > HDOP` **on the
       actual probe layout** — the bonus lesson, pinned only after the gate-1 probe confirms it for
       that placement, NOT asserted as universal; DOP σ-invariant — the slice-5 trap pinned
       on the new surface: scaling `σ_range` moves `pos_err` but NOT the DOPs);
     - the **error budget** — each deterministic term shifts the fix by a known bias (iono/tropo
       elevation-scaling sign + magnitude pinned; sat-clock bias pinned), each stochastic term
       inflates a known variance (MC mean/scatter, its OWN `Xoshiro` — the slice-5 precedent);
     - **RAIM** — an injected `fault_bias` spikes `raim_stat` above threshold (detect); the fault
       ID picks the **right** satellite; `raim_exclude` drops it and **recovers truth** (
       `pos_err_m` collapses); `raim=:off` never flags; the single-fault / largest-residual method
       pinned as the real algorithm step, NOT tuned to pass by construction (the slice-2/3/4/5/6
       don't-self-calibrate rule);
     - **singular geometry** (< 4 satellites, or coplanar/clustered → the 4×4 normal matrix
       singular) → `FINITE_CEIL`, **no throw** (the Cholesky falls back like `_solve2x2`'s det
       floor);
     - **units** (a clock bias authored/printed in ns round-trips through the `c·b`-metres
       internal + a pseudorange in metres) + degenerate guards (empty sat list, exactly-4 exact
       solve → no throw).
     Wire into `runtests.jl` after the estimation/geometry tests. Slices 1–6 green untouched.
2. **The GPS pipeline wired (phases 2+3+4 lit, the §9 reuse in the tick loop).** `GpsSatellite`/
   `GpsReceiver`/`GpsSolver` in a new `gps.jl` (included after `radar.jl`, mirroring
   `geolocation.jl`/`esm.jl`; **verify NO back-dep on radar symbols** — it reuses
   geometry.jl's `_finite` + gnss.jl's pure math; if a `_range` dep surfaces, it's already a
   shared helper). `SatEphemeris`/`PseudorangeSet` records; `env[:gps_sats]` (phase 2) →
   `env[:pseudoranges]` (phase 3, the ONE draw site on look-ticks) → telemetry (phase 4).
   `:gps_satellite`/`:gps_receiver` kinds + `_validate_gps` in `scenario.jl`. Telemetry clamped
   finite. `LIVE_FIDELITY_MODES` gains the six keys (referencing `GPS_TOGGLE`/`RAIM_MODES`) — the
   fidelity plumbing lands here (the slice-5/6 gate-2 precedent — introduce-safe, no draw hazard,
   the `GpsSolver` actually consumes each key).
   - **Exact §1 draw order pinned bit-for-bit** (`test_gps.jl` reconstructs it MANUALLY off a
     fresh `Xoshiro`, independent of the receiver code): satellites in **sorted-id order**
     (`env[:gps_sats]` append order); per satellite draw **MULTIPATH (`randn`) THEN NOISE
     (`randn`)**, both **UNCONDITIONAL** (the toggle gates the contribution, not the draw); total
     `2·n_sats`, **fixed** regardless of any toggle / the RAIM rung / the fault slider.
   - `test_gps.jl` (the `test_esm.jl`/`test_geolocation.jl` analog): `GpsSatellite` populates
     `env[:gps_sats]` (record shape + params); `GpsReceiver` populates `env[:pseudoranges]` with
     the **exact** drawn pseudoranges reconstructed off a fresh `Xoshiro` + a bounded count;
     `GpsSolver` `pos_err_m`/DOPs/`raim_*` match `gnss.jl` on the realized pseudoranges; the
     six-key fidelity plumbing (each error toggle changes the budget; the `raim` rung changes
     detect/exclude/off — `n_sats_used` drops under `:exclude`); **draw-stream invariance**
     (toggling ANY key → same `w.rng` end-state, different fix/flag; a no-GPS scenario
     byte-identical to slices 1–6 — the golden + `test_determinism` green); finite telemetry incl.
     a degenerate single-satellite / all-masked case → no throw; loader arms + rejects.
   - `test_determinism.jl` + a slice-7 scenario: same-seed bit-identical **pseudorange trace**
     (the RNG fingerprint via `reinterpret`, sharper than `pos_err_m` — the slice-6 advisor
     lesson); draw-free rung switch; mid-run toggle AND introduce of each GPS key bit-identical.
3. **Fidelity + two scenarios + Godot GPS view + verifiers.** `set_fidelity` on the six keys
   works with **no server change** (introduce-safe, the `:ep`/`:estimator` contract).
   - `scenarios/slice7_dop.yaml` (a clean spread constellation ~6–8 satellites + one receiver;
     the five error toggles; a slow satellite drift sweeping DOP good→bad; default a *realistic*
     subset on [e.g. `iono`+`tropo`+`noise`] so the fix has a visible error and toggling teaches
     each contribution; no fault). `scenarios/slice7_raim.yaml` (an over-determined constellation
     ~6 satellites, one carrying a `fault_bias`; default `raim = :detect` so the flag is visible
     on connect; a `fault_bias_m` slider that ramps across the detection threshold; cycling to
     `:exclude` drops the bad satellite and snaps the fix back). **Numbers tuned EMPIRICALLY with
     throwaway probes + validated against the LIVE wire path** (the slice-3/4/5/6 rule — the
     DOP/error-budget magnitudes and the fault-detection crossover are geometry/σ-dependent; don't
     hand-derive — probe, then pin as comments). **Honour the DOP-visibility drift** (a static
     scene shows one DOP number).
   - The Godot GPS view (sky plot colored by satellite status + residual bars + DOP/error readout;
     the `raim` badge + cycler + the five-toggle button row + the fault slider). `_update_readout`
     must **skip Array telemetry** (the slice-3/6 `float()`-crash watch-item — re-confirm for the
     `sat_*` keys). The slice-1..6 paths untouched (re-run their smoke-loads + UI tests, all pass).
   - `net/slice7_verify.gd` (drives the real server, covers **both** scenarios — advisor: don't
     leave the RAIM lesson to smoke-load only): DOP scene — the DOPs are finite + decompose
     (`hdop²+vdop²+tdop² ≈ pdop²+tdop²`... i.e. `gdop² = pdop²+tdop²`, `pdop² = hdop²+vdop²`; the
     decomposition identity is a clean wire pin), `VDOP > HDOP` on the shipped constellation, the
     DOP sweeps with the drift, and
     each `set_fidelity` error toggle changes `pos_err_m` (the error-budget-as-a-number, each
     term's contribution); then `load_scenario slice7_raim.yaml` — the `fault_bias_m` slider ramps
     `raim_stat` across the threshold so `raim_flag` **raises at the crossover** (the not-a-dead-
     knob deliverable, `t` **bit-identical** under a held seed), and `set_fidelity raim :exclude`
     **drops `n_sats_used` by 1 and collapses `pos_err_m`** (the snap-back) while `:detect` only
     flags — all assertions on the SCALARS, never the display arrays. `S7V OK`, exit 0.
   - `net/slice7_ui_test.gd` (mock client, no server: the `raim` cycler walks off→detect→exclude
     and wraps; the five error toggles each send `set_fidelity`; the fault slider sends
     `set_param`; badge/buttons track; reset resyncs to defaults — `S7UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against BOTH slice-7 servers (server `DONE` ⇒ scene
     connected on the gps branch — catches gps-branch parse bugs the SimClient verifier can't).
   - Tests: `test_scenario.jl` (both loaders — GPS fidelity defaults, NO radar/jammer/DF/ESM
     fidelity or entities, ≥4 satellites [≥5 for the RAIM scene], one receiver, the `fault_bias`
     stored SI metres [the slice-4/6 "keys equal defaults so `haskey` is the discriminating check"
     rule — assert the unit conversion], error keys not knobs, the fault/error sliders address the
     right comp keys); `test_server.jl` (the six `set_fidelity` GPS keys write/reject +
     introduce-safe on a non-GPS scenario [the `:ep`/`:estimator` contract, NOT `:cfar`'s guard];
     warmup GPS-free — `warmup!` already guards on radar presence [the slice-5 fix], a GPS
     scenario has NO radar → the ROC batch is skipped, so pin the radar-free warm covers the
     phase-2+3+4 GPS path).
   - The `_draw_gps` PIXEL branch (Godot skips `_draw` headless) **visually confirmed** via the
     windowed shot harness (the slice-3/4/5/6 technique, [[ewsim-godot-headless]]): the sky plot
     geometry (spread vs clustered → the DOP contrast), the faulted-satellite residual spike + the
     raised RAIM flag under `:detect`, and the excluded satellite + snapped-back fix under
     `:exclude`. **(stretch, deferred)** an offline `batch.jl` `kind = :dop_mc` (position-error vs
     DOP / satellite count) or `:raim_roc` (detection probability vs fault size) +
     `clients/notebooks/slice7_gps.jl` Pluto diagram — **not** a live rung.

## Task checklist
- [x] 1. **Primitives (pure, SI, dependency-free).** DONE & green (1308 tests, +70). **The 2→4
      decision resolved as a HYBRID (advisor's a/b gate — implement (b), run the DF suite):**
      `gauss_newton` GENERALIZED to N-dim (DF `:ml` N=2 and GPS `position_fix` N=4 call the same
      scaffold — option (b), the §9 headline made real) + new shared `_solve_normal` (hand-rolled
      Cholesky) / `dop` / `dop_components` in geometry.jl; but `linear_ls`/`_solve2x2` KEPT 2×2-cofactor
      (fallback (a) for the pseudolinear path ONLY — the tiny-leading-pivot near-singular instability
      the slice-5 bias MC caught; GPS never uses `linear_ls`, so the reuse story stays honest). `gnss.jl`
      (pseudorange sum + residual/Jacobian `[−û,1]`, `position_fix` calling `gauss_newton` at N=4, the
      five error-term models [iono/tropo obliquity NOT Klobuchar/Saastamoinen; clock per-SV; mp/noise
      pre-drawn], `raim_statistic`/`raim_suspect`/`raim_solve` with the **empirical σ-multiple threshold
      — route (iii)**, χ²/Pfa rejected because exclude→odd-DOF needs erf; `GPS_TOGGLE`/`RAIM_MODES`).
      Exported. `test_gnss.jl` (noise-free fix==truth + N=2==`_solve2x2` reuse pin; DOP vs an independent
      `_inv4` recompute + VDOP>HDOP-on-the-probed-layout + σ-invariance; error budget ALL FIVE terms;
      RAIM detect/ID/exclude/off + n=4-blind; singular→FINITE_CEIL EXACTLY [<4 sats + coplanar]; units ns
      round-trip; degenerate guards). Wired into `runtests.jl` after test_estimation. Byte-identity: RNG
      stream + `_sample_z` golden untouched; DF pseudolinear byte-identical; DF `:ml` re-routed through the
      shared Cholesky at N=2 (ULP-equal, determinism intact). Slices 1–6 green.
- [x] 2. **The GPS pipeline wired (phases 2+3+4 lit).** DONE & green (1448 tests, +140).
      `GpsSatellite`/`GpsReceiver`/`GpsSolver` in a new `gps.jl` (included AFTER geolocation.jl;
      no radar back-dep — reuses geometry.jl's `_finite`/`FINITE_CEIL`, geolocation.jl's
      `_finite_coord`, gnss.jl's pure math). `SatEphemeris`/`PseudorangeSet` records; the §3
      coupling `env[:gps_sats]` (phase 2) → `env[:pseudoranges]` (phase 3, THE ONE DRAW SITE on
      look-ticks) → telemetry (phase 4). **Exact §1 draw order** `_draw_pseudoranges`: satellites
      sorted-id, per satellite MULTIPATH(randn) THEN NOISE(randn) both UNCONDITIONAL → `2·n_sats`
      fixed regardless of any key/slider (the five error toggles gate the CONTRIBUTION, the
      elevation mask / RAIM exclusion are POST-DRAW filters — no draw-topology hazard, every key
      introduce-safe + toggle-bit-identical). `:gps_satellite` (`clock_err_m`/`fault_bias_m`, SI
      metres — fault_bias_m the RAIM slider key) + `:gps_receiver` (`sigma_range_m`/`sigma_mp_m`/
      `iono_zenith_m`/`tropo_zenith_m`/`clock_bias_m`/`elevation_mask_deg`/`raim_threshold`) kinds
      + `_validate_gps` (≥4 sats + exactly 1 receiver at LOAD, GPS-presence-triggered) in
      `scenario.jl`; unknown-kind list updated. **`raim_threshold` (not the plan landmark's stale
      `pfa_raim`)** — gate-1 chose the empirical σ-multiple (route iii), so the comp key the
      slider/solver share is `raim_threshold`. `LIVE_FIDELITY_MODES` (radar.jl) gains the six keys
      referencing `GPS_TOGGLE`/`RAIM_MODES` (one-list-no-drift; namespaced-by-consumption — only a
      GpsSolver reads them). GPS DOP is FIX-geometry `Q` (gnss.jl convention, ≈ truth at 20 000 km
      range, σ-invariant). Solver clamps every scalar finite (`_finite`/`_finite_coord`) — a
      singular/under-determined geometry (< 4 visible, coplanar, RAIM into < 4) ships `FINITE_CEIL`,
      never a throw. `test_gps.jl` (+109: env populated + record shape; the EXACT-draw golden
      reconstructed off a fresh Xoshiro; solver reproduces `raim_solve`/`dop_components` +
      VDOP>HDOP; the six-key fidelity plumbing [each error toggle enters the budget, raim
      off/detect/exclude, n_sats_used drops]; **masked-AND-excluded index mapping** — `vis_idx≠1:n`
      pinned against an independent raim_solve, the advisor bug [`sat_used[k]=res.used[k]` forgetting
      the map]; wire JSON round-trip; **draw invariance across ALL SIX keys** [rng lockstep];
      degenerate all-but-one-masked → FINITE_CEIL no throw; no-GPS byte-identity; loader arms +
      rejects). `test_determinism.jl` + a slice-7 scenario (bit-identical PSEUDORANGE trace via
      `reinterpret`; draw-free rung switch off↔exclude [n_sats_used 6↔5]; toggle AND introduce of
      each of the six keys → rng end-state bit-identical [ρ VALUES change with an error toggle, the
      DRAW COUNT does not — the invariant is the rng state]). `test_server.jl` (six-key
      `set_fidelity` write/reject + introduce-safe on a non-GPS scenario [the `:ep`/`:estimator`
      contract]; warmup! tolerates a radar-free GPS scenario). Slices 1–6 byte-identical (gps.jl
      adds no code to the radar/detection path; the `_sample_z` golden + all prior testsets green).
      **Next: gate 3** — `set_fidelity` on the six keys (no server change); `slice7_dop.yaml` +
      `slice7_raim.yaml` probed against the live wire; the Godot GPS/sky view (sky plot + residual
      bars + DOP readout + five-toggle row + raim cycler + fault slider); `net/slice7_verify.gd` +
      `net/slice7_ui_test.gd`; `test_scenario.jl` both loaders; `_draw_gps` visually confirmed.
- [ ] 3. **Fidelity + two scenarios + Godot GPS view + verifiers.** `set_fidelity` on the six keys
      (no server change). `slice7_dop.yaml` (spread constellation + drift + error toggles) +
      `slice7_raim.yaml` (over-determined + faulted satellite + `raim` rung + fault slider),
      numbers probed against the live wire. The Godot GPS view (sky plot + residual bars + DOP
      readout + the five-toggle row + `raim` cycler + fault slider). `net/slice7_verify.gd` (both
      scenarios: DOP finite/decompose/VDOP>HDOP/sweeps; error toggles change `pos_err_m`; the
      fault slider raises `raim_flag` at the crossover; `:exclude` drops `n_sats_used` + collapses
      `pos_err_m`, bit-identical `t`). `net/slice7_ui_test.gd` (the toggle row + `raim` cycler +
      fault slider + reset resync). `Sandbox.tscn` smoke-loaded against both servers.
      `test_scenario.jl` (both loaders); `test_server.jl` (six-key write/reject + introduce-safe +
      GPS-free warmup). `_draw_gps` visually confirmed via the shot harness. **(stretch, deferred)**
      `batch.jl` `kind = :dop_mc`/`:raim_roc` + `slice7_gps.jl` Pluto.

## Context / landmarks
- **This lights NO new phase — it is the §9 REUSE milestone.** `build_env!`(2)→`observe!`(3)→
  `decide!`(4) already run in order (`subsystem.jl:28–32`); `GpsSatellite`(2)→`GpsReceiver`(3)→
  `GpsSolver`(4) inherits the same correctness-by-construction the jammer→radar / DFSensor→
  Geolocator / emitter→ESM couplings got. The novelty is that `geometry.jl`/`estimation.jl` now
  serve a SECOND domain (the §9 promise) — the plan's intro celebrates the cross-domain reuse,
  not a phase first.
- **The `env` coupling + subsystem templates are `esm.jl`** (`PulseEmitter.build_env!` →
  `ESMReceiver.observe!` → `Deinterleaver.decide!`, the `EmitterParams`/`ToaStream` records) **and
  `geolocation.jl`** (`DFSensor`→`Geolocator`, `BearingRecord`). Copy their shape: `const
  SatEphemeris = @NamedTuple{…}`, a `get!`-into-`env` append in `GpsSatellite.build_env!`, a
  collect-read + draw in `GpsReceiver.observe!`, `env[:pseudoranges]` read by `GpsSolver.decide!`.
- **The shared-lib reuse targets** are `estimation.jl` (`linear_ls`/`gauss_newton`/`_solve2x2` —
  the 2×2 scaffold + the `bearings_fix` resident) and `geometry.jl` (`gdop`/`error_ellipse`/
  `eig2x2`/`FINITE_CEIL`/`_finite`). **Generalize the innermost `_solve2x2`→`_solve_normal`
  (N-dim Cholesky) and delegate the 2×2 call sites to it** (option (b) — the §9 reuse made
  literal; re-run slice-5/6 tests, fallback to pure siblings if a tolerance surprises).
  `ESTIMATOR_MODES` (estimation.jl:25) is
  the "mode-const-before-radar" precedent — put `GPS_TOGGLE`/`RAIM_MODES` in `gnss.jl` the same way.
- **The include order** is `… detection → geometry → estimation → deinterleave → radar →
  geolocation → esm → scenario → batch → server` (`EWSim.jl`). Slot **`gnss.jl` before `radar.jl`**
  (pure, defines the mode consts `LIVE_FIDELITY_MODES` references; depends on the generalized
  geometry/estimation, both already before radar) and **`gps.jl` after `radar.jl`** (the
  subsystems, mirroring `geolocation.jl`/`esm.jl`). **Verify at gate 2 the GPS subsystems have no
  back-dep on radar symbols**; if one surfaces, the slice-5 fallback (a tiny post-include
  fidelity registry) applies.
- **The fidelity table** is `LIVE_FIDELITY_MODES` (`radar.jl`), validated by `set_fidelity`
  (`server.jl:160`). Add `iono`/`tropo`/`clock`/`multipath`/`noise` = `GPS_TOGGLE`, `raim` =
  `RAIM_MODES`. **No introduce-guard** — the `:cfar` guard (`server.jl:177`) doesn't match them
  (introduce-safe, the `:ep`/`:estimator`/`:deinterleaver` contract).
- **The loader** `_build_entity` (`scenario.jl`) is the `kind`-dispatch — add `:gps_satellite`
  (a `gps_satellite:` block → `pos`/`velocity`, `clock_err_m`, optional `fault_bias_m`, all SI
  metres; + `ConstantVelocity` + `GpsSatellite`) and `:gps_receiver` (a `gps_receiver:` block →
  `sigma_range_m`, `sigma_mp_m`, `pfa_raim`, `elevation_mask_deg`, `revisit_s`; + `ConstantVelocity`
  + `GpsReceiver` + `GpsSolver`). Update the unknown-kind error list. `_validate_gps` (≈
  `_validate_esm`/`_validate_geoloc`) asserts ≥4 `:gps_satellite` (≥5 for a RAIM scene) + exactly
  1 `:gps_receiver` at LOAD, triggered by GPS-entity presence so a non-GPS scenario is untouched.
- **The look-tick gate** is the radar/ESM `next_look_t`/`revisit_s` — reuse it in
  `GpsReceiver.observe!` so the pseudorange draw is on the receiver's revisit cadence + republished
  between looks.
- **Telemetry → wire** is generic (`protocol.jl` `state_frame` reads `env[:telemetry]`). Reuse
  geometry.jl's `_finite`/`FINITE_CEIL` for the scalars; the display arrays serialize like the
  slice-5/6 variable arrays (JSON3 handles them). The `string→number/bool/array` widening is
  already documented (`protocol.jl:64`).
- **No-LinearAlgebra house style** holds — the Cholesky solve + the DOP diagonals + the RAIM RSS
  are all plain array loops over StaticArrays; no `LinearAlgebra`/`inv`.
- **Units (the §1 trifecta):** positions/pseudoranges/biases in **metres**, the clock unknown as
  **`c·b` metres** internally, displayed as **ns** (clock) — convert only at the loader (in) and
  telemetry (out). Elevation/azimuth in **radians** internally, **degrees** on the wire (the
  `sigma_theta_deg`/`beamwidth_deg` precedent). A metres/seconds slip on the clock term is this
  slice's signature bug; pin a round-trip.

## Watch-items (gotchas to bake in)
- **Draw-count-invariance on SATELLITE SELECTION (the signature hazard, new surface).** Draw
  multipath + noise for **every CONFIGURED satellite, every epoch, unconditionally** (in the exact
  §1 order — multipath then noise). The **elevation mask, live satellite dropout, and RAIM
  exclusion are ALL post-draw filters on which measurements enter the SOLVE — never gates on the
  DRAW.** Gate the draw on visibility/exclusion and a mid-run mask/exclude/toggle desyncs replay
  (the slice-3 `:cfar` trap). Configured satellite count is LOAD-TIME static. Pin (a) no-GPS
  byte-identity vs the slice-1 golden; (b) any key toggle → `w.rng` end-state identical, fix/flag
  differ; (c) mid-run toggle AND introduce of each of the six keys bit-identical.
- **Generalize the inner solve; keep the call-site LOGIC untouched (option (b)).** Only the
  innermost `_solve2x2` becomes a generic Cholesky `_solve_normal`; `linear_ls`/`gauss_newton`/
  `bearings_fix`'s signatures, two-pass weighting, det-ridge, and divergence fallback are
  unchanged. Byte-safe (DF value tests atol/inequality; determinism run-A-vs-B) — but **re-run
  slice-5/6 value + determinism tests at gate 1 to confirm the tolerances survive the ULP shift**;
  if any surprises, fall back to pure siblings with the 2×2 code untouched (option (a)). Pin at
  gate 1 that the N=2 solve reproduces the pre-refactor DF fix (atol) AND slices 5–6 green.
- **Units: metres vs seconds on the CLOCK term (the §1 trifecta).** The receiver clock bias is
  carried as `c·b` in METRES in the unknown vector; a seconds/metres mix is a factor of `c ≈ 3e8`
  — the signature bug on this surface. Convert to ns only at the telemetry boundary. Pin a
  round-trip.
- **Singular / under-determined geometry must NOT throw a tick** (the "a live config can't crash a
  tick" watch-item). Fewer than 4 usable satellites (a live dropout / an aggressive elevation mask
  / RAIM excluding into < 4), or a clustered/coplanar constellation → the 4×4 normal matrix is
  singular → the Cholesky falls to `FINITE_CEIL` (the `_solve2x2` det-floor analog), never NaN /
  never a throw. A live fault slider + `:exclude` can drive `n_used` down; guard at the consumer;
  the loader rejects a malformed AUTHORED constellation (< 4 satellites). Test the degenerate cases.
- **RAIM needs OVER-determination — pin the DOF.** `:detect`/`:exclude` are meaningful only at
  `n ≥ 5` (`n − 4 ≥ 1` residual DOF); at exactly 4 the residuals are ≈0 and RAIM cannot see a
  fault (name it — the RAIM scenario ships ≥ 5, and `:exclude` re-solving must not drop below 4).
- **The fault is DETERMINISTIC — the fault slider is draw-count-safe.** The injected `fault_bias`
  is a constant added to a pseudorange (no draw); ramping it via `set_param` changes the residual,
  never the RNG. `raim` detect/exclude is post-draw. So the whole RAIM lesson is introduce-safe +
  bit-identical under a held seed (the slice-4 burn-through-slider precedent).
- **The five error keys are GENERIC WORDS namespaced by consumption.** Only a `GpsSolver` reads
  `iono`/`noise`/`clock`/etc.; a non-GPS scenario toggling one is a harmless no-op (the
  `:estimator`-without-a-`Geolocator` precedent). Don't add a special guard; do document that a
  bare `noise`/`clock` fidelity means the GPS error term (a future slice wanting the word must
  disambiguate).
- **Don't σ-weight the DOP (the slice-5 trap).** DOP is `(HᵀH)⁻¹` at UNIT variance — pure
  geometry; the pseudorange σ enters `σ_pos = DOP·σ_range` at the readout. σ-weighting `Q` would
  make a `σ_range` change wrongly move DOP. Pin DOP σ-invariance at gate 1.
- **Display arrays: NEVER assert; skip in `_update_readout`.** The verifier/determinism tests
  assert on the SCALARS (`pos_err_m`/DOPs/`raim_flag`/`n_sats_used`) + never the `sat_az_deg`/
  `sat_resid_m`/`sat_used` arrays. `_update_readout` must skip Array telemetry (the slice-3/6
  `float()`-crash watch-item, re-confirmed for the `sat_*` keys).
- **Named approximations, stated (no hidden ones — HANDOFF §1):** flat-local satellites (no
  ECEF/orbits), simplified analytic iono/tropo (not Klobuchar/Saastamoinen), stochastic
  elevation-weighted multipath, RAIM residual-RSS detection + largest-residual single-fault ID
  (not parity-space/max-slope), instantaneous signal travel (no light-time iteration), linearized
  DOP/covariance (reused). Name each in the docstrings.
- **Deferred to future slices, explicitly NOT here:** real orbital mechanics / broadcast
  ephemeris, ECEF/WGS84, Klobuchar/Saastamoinen, carrier-phase / RTK / multi-constellation,
  multi-fault RAIM, **GPS spoofing as live RGPO from the EW jammer module** (HANDOFF §9's
  RGPO≡spoofing cross-domain fusion — a future slice; here a "fault" is a static/slider bias), the
  live MC DOP/RAIM success-rate rung (offline only). Listing them keeps the slice-7 boundary honest.
