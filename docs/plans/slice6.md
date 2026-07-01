# Slice 6 — Multi-emitter EW (interleaved pulse trains → PRI-histogram deinterleaver)

The slice that lights **phase 2 + phase 3 + phase 4 of the tick contract in one pipeline** —
the phase-contract capstone. Slice 4 lit `build_env!` (phase 2, the jammer raising the noise
floor through `w.env`); slice 5 lit `decide!` (phase 4, the geolocator fusing bearings). Slice 6
runs **all three derived phases as one chain through `w.env`**: pulse emitters publish their
schedules (phase 2), an ESM receiver intercepts + measures the interleaved Time-of-Arrival stream
(phase 3 — the one seeded-draw site), and a deinterleaver recovers each emitter's PRI and groups
the pulses (phase 4). This is the §3 coupling exercised end-to-end across the
**build_env!→observe!→decide! seam**, the natural milestone after the two single-phase slices.
Source of truth: `HANDOFF.md` §10 (item 6 — "interleaved pulse trains → PRI-histogram
deinterleaver. Generic parametric emitters only"), §3 (the four-phase tick + `env` coupling), §1
(named approximations; **units** are first-class here — PRIs are µs–ms, sim time is SI seconds, a
µs/s mixup is exactly the trifecta bug), §12 (the fidelity badge).

The lesson is **deinterleaving the pulse-density "soup"**: a receiver that hears N radars at once
sees a single jumbled TOA stream, not N clean trains. The **difference histogram** (count of pulse-
pair time-differences vs lag) raises peaks at each emitter's PRI out of the chaos — that emergence
**is** the killer visual. The second lesson is the **deinterleaver fidelity**: the cumulative
difference histogram (**CDIF**) declares **phantom subharmonic PRIs** — a stable train at PRI=T
piles difference counts at 2T, 3T… as tall as the fundamental, so a naive method reports a radar
that isn't there; the sequential, subharmonic-checked histogram (**SDIF**, Milojević–Popović) rejects
the harmonic and recovers exactly the true emitters. The phantom-emitter trap is **structural, not
noise-driven** — it appears on *perfectly stable* emitters — so (like slices 2/4/5, unlike slice 3)
the core scenario is **fully deterministic** and there is **no draw-topology hazard**. Toggling
`deinterleaver` (`cdif ↔ sdif`, the §12 badge) and watching a phantom radar appear and vanish is the
EP-style named-switchable-approximation knob (the `pseudolinear→ml` / `free_space→two_ray` analog).

**De-risked empirically before this plan** (a throwaway 40-line probe, the slice-3/4/5 discipline
applied to the *lesson itself* — advisor): on 3 stable, well-separated PRIs `[1300, 1700, 2300] µs`,
CDIF declares **4** PRIs (the 3 fundamentals + a phantom at 2590 ≈ 2×1300) while SDIF declares **3**
(the subharmonic check rejects 2590). The 2-emitter case is sharper still (CDIF hallucinates 2T₁ and
3T₁ → 4, SDIF → 2). The probe also mapped the **failure boundaries** that pin the scenario design
(below): 5 µs TOA jitter muddies *both* algorithms (→ keep the showcase stable, jitter is a
degradation slider not the knob); 4+ dense emitters under-report with the simple flat-threshold
cumulative algorithm (the adaptive-threshold refinement that would fix it is deferred — §2);
near-integer PRI ratios (2.1 ≈ 2×1.0) break both. **3 stable well-separated non-harmonic emitters is
the sweet spot.**

**Scope (one lesson per scenario — the slice-3 principle):** **generic parametric emitters only**
(a PRI + phase + pulse-width, no real waveform — HANDOFF §10 item 6); **stable (constant) PRI**
core (jitter/missed-pulses optional degradation sliders); a **single ESM receiver** (multi-receiver
TDOA geolocation is a future slice); **no radar-detection / jamming / DF in the same scenario**.
Explicitly deferred: **staggered / dwell-switching / sliding PRI** (its own research rabbit hole),
**emitter-intrinsic PRI random-walk** (modeled here as receiver TOA-measurement noise — see the
approximation note), **Nelson's PRI-transform** rung (a named future third rung), **TDOA emitter
geolocation** (which *would* use the R/c offsets this slice can ignore). 3 review gates (mirroring
slice 5: pure primitives → subsystems wired → fidelity + scenario + client + verifier).

**Done =** start the server on a multi-emitter scenario, connect Godot, watch (in a **new ESM /
PRI view**) several radars' pulses arrive as one interleaved TOA raster, the difference histogram
raise peaks at the true PRIs, and the deinterleaver color each pulse by its recovered emitter;
toggle `deinterleaver` (`cdif → sdif`) and watch a **phantom emitter at 2×PRI appear (cdif) and
vanish (sdif)** — the detected-emitter count `n_pri` flipping 4→3 on the readout; drag the ESM's
`jitter_us` / `p_intercept` sliders and watch the histogram peaks blur / thin — with `runtests.jl`
green on the new closed-form deinterleave tests (the structural subharmonic trap pinned
deterministically) and slices 1–5 untouched and still **byte-identical** (no ESM subsystem touches
the radar/jammer/DF RNG path).

## The physics / math (named approximations — HANDOFF §1)

Pulse-train deinterleaving by PRI. Everything **SI seconds internally**, converted to **µs only at
the telemetry boundary** (the §1 units trifecta — a µs/s slip is this project's signature bug). The
whole slice is **deterministic given the drawn TOA stream** (the histogram + PRI extraction +
association are closed-form), so — like slices 2/4/5 — there is **no draw-topology hazard** (see
Decisions).

### 1. The pulse model + the interleaved TOA stream (`esm.jl` subsystems)
- A **`:pulse_emitter`** transmits a constant-PRI train: emit times `tₖ = phase + k·PRI` over the
  receiver's collection dwell. **Per-look dwell, regenerated each look** (Option B — no cross-tick
  TOA accumulation state; the determinism/replay simplicity of the CFAR-profile redraw, advisor).
  The emitter publishes its **params** (`pri`, `phase`, `pulse_width`, `pos`, **true id**) to
  `env[:emitters]` in **phase 2 `build_env!`** — cheap, RNG-free, order-independent (the jammer's
  `JamContribution`-into-`env` shape). It does **not** generate the pulses (that would be hundreds
  of TOAs every tick); the receiver does, on look-ticks only.
- The **`ESMReceiver`** (phase 3 `observe!`, the **one draw site**) reads every `env[:emitters]`
  record and, **on a look-tick**, generates the full interleaved TOA stream over `[t, t+T_dwell)`:
  for each emitter, the deterministic emit grid + a **TOA measurement jitter** `N(0, σ_toa)` per
  pulse, a **probability-of-intercept** drop `Bernoulli(1−p_intercept)` per pulse, and a static
  count of **spurious** (noise/clutter) TOAs uniformly over the dwell. Each kept pulse is stamped
  with its **true emitter id** (ground truth for the association score — the `err_m`-vs-truth analog
  from slice 5; spurious pulses carry a sentinel "no emitter"). The stream (sorted TOAs + truth ids)
  goes to `env[:toa_stream]`.
  - **Exact draw order — pin it (the determinism golden rides on this; the `sqrt(snr/2)` / noise-then-
    signal-order bug class — advisor).** Emitters in **sorted-id order** (the `env[:emitters]` append
    order); within an emitter, pulses in **emit order**; per candidate pulse draw **jitter (`randn`)
    THEN intercept (`rand`), both UNCONDITIONALLY** (so the `p_intercept` slider changes the keep/drop
    *decision*, never the draw *count* — the draw-count-invariant trick), keeping the jittered TOA iff
    the intercept draw is below `p_intercept`; **then** the static `n_spurious` **uniform (`rand`)**
    TOAs last. Total draw count is `2*n_candidate + n_spurious`, **fixed** regardless of the rung or
    any slider value. Gate 2's exact-draw reconstruction test (a fresh `Xoshiro`) replays exactly
    this sequence.
  - **Named approximation — jitter is receiver TOA-measurement noise, not emitter PRI instability.**
    Receiver TOA jitter (independent per pulse) and emitter-intrinsic PRI random-walk agree on the
    first-difference spread (√2·σ) but **diverge at higher lags**: emitter jitter random-walks, so
    the level-c difference spread grows ∝√c and degrades the higher-lag histogram peaks CDIF leans
    on; receiver jitter keeps every lag at √2·σ. So **true emitter PRI random-walk is the *harder*
    case** — modeling jitter receiver-side is the *easier*, named simplification (emitter-intrinsic
    PRI instability deferred). State it; don't claim to model PRI stability.
  - **Named approximation — geometry frozen over the dwell.** The emitter's range is evaluated once
    at look time; pulses within a dwell share that range. (And per the next note the range barely
    matters anyway.)
  - **Named approximation — R/c propagation delay is pedagogically inert and OMITTED.** A constant
    per-emitter TOA offset `R/c` cancels in *same-emitter* differences (the true-PRI peaks come from
    same-emitter pulse pairs; cross-emitter differences are histogram noise either way), so the PRI
    lesson is invariant to it. We drop R/c (the ESM subsystems then need **no** `_range`/radar
    dependency — see include-order). TDOA geolocation, which *does* exploit the offsets, is a future
    slice; name the omission there.
- **Draw-count invariance (the no-hazard proof obligation).** The candidate-pulse set per dwell is
  fixed by the (static) emitter params + dwell + spurious count, so the receiver draws a **fixed**
  number of randn (jitter) + rand (intercept) regardless of the `:deinterleaver` rung *or* the live
  slider *values* (a slider scales a draw or sets a keep-threshold; it never changes the draw
  *count* — the σθ-slider precedent). **`T_dwell` and the spurious count are therefore LOAD-TIME
  static** (changing them would change the draw count → the slice-3 `:cfar` desync hazard); only
  **`jitter_us` and `p_intercept` are live sliders** (advisor — corrects the first design sketch).

### 2. The difference histogram + PRI extraction (`deinterleave.jl`, pure / no RNG)
- **Difference histogram at level c:** for the sorted TOA stream `t₁…t_N`, the level-c differences
  are `{t_{i+c} − t_i : i = 1…N−c}`, binned at `bin_width` over `[0, T_dwell]`. Interleaving scatters
  an emitter's PRI across lags (with M roughly-equal emitters, same-emitter pulses sit ≈M apart in
  the merged stream), so the histogram is accumulated over levels `c = 1…C` (`C ≳ M·few`).
- **Shared candidate pipeline (BOTH rungs).** Sum the level-1…C difference histograms into one
  **cumulative** histogram; take every local-peak bin over a fixed detection threshold that passes
  the **sequence-search** test → a candidate-PRI list. The cumulative histogram, the threshold, and
  the sequence search are **identical for both rungs** — the **only** difference is the acceptance
  rule below. This is the de-risked algorithm (advisor: align the plan to what the probe proved):
  isolating one teaching variable also keeps the display coherent (same bars, same threshold line,
  only the markers move).
- **`:cdif` (the BIASED baseline / named approximation) — accept EVERY candidate.** **The structural
  flaw:** a stable train at PRI=T piles cumulative counts at 2T, 3T… nearly as tall as T (lag-2 gives
  ≈N−2 counts at 2T, etc.), and a 2T-spaced subsequence *does* exist, so the sequence search at 2T
  succeeds — CDIF declares a **phantom emitter at the subharmonic**. This is the *named* approximation
  the slice teaches.
- **`:sdif` (the higher-fidelity rung) — accept candidates that pass the SUBHARMONIC CHECK.** Before
  accepting a candidate τ, reject it if a sub-multiple (τ/2, τ/3, …) is also a candidate — the
  fundamental, not its harmonic, is the real PRI. This **single added rule** removes the phantom (the
  de-risk probe's exact result: cdif=4 → sdif=3 on `[1300,1700,2300]`). The subharmonic check is
  **SDIF's historically-real contribution over CDIF** (Milojević–Popović) — name it as such in the
  docstring; it is not a strawman fudge. **(The faithful sequential-per-level / adaptive-exponential-
  threshold `x·(N−c)·exp(−τ/κN)` / extract-and-remove SDIF is deliberately NOT used** — it adds
  untested threshold tuning [`x`, `κ`] + bug-prone sequential code, and it breaks the shared-cumulative
  display. It returned `n=0` in the first probe attempt and was scrapped for the post-filter version
  that produced the clean 4→3. It is a **named future refinement**, alongside Nelson's PRI-transform.)
- **Shared, NOT rung-dependent — the association too.** The **sequence-search association** that
  follows PRI detection is **identical for both rungs**; the rung changes only *which PRIs are found*,
  and association (each pulse → its nearest detected-PRI sequence, scored against truth) follows. Say
  so explicitly so the per-pulse-assignment story stays clean.
- **The detection threshold is core output**, shipped on the wire (the CFAR `threshold_db`
  precedent — the client never recomputes physics, HANDOFF §1). **PRI estimates refined by bin
  centroid** (not the (b−0.5)·bin_width bin-center the probe used — that left a ½-bin ≈10 µs offset).

### 3. The association score + the "lesson as a number" (`deinterleave.jl`)
- **`associate(stream, pris) → assignment`**: each pulse → the detected-PRI sequence it best fits
  (sequence search), or "unassigned." **`assoc_pct`** = fraction of *true* (non-spurious) pulses
  assigned to the correct emitter (scored against the truth ids the receiver stamped). A phantom
  subharmonic *may* steal pulses from its fundamental, lowering CDIF's `assoc_pct` — **but only if
  association doesn't tie-break toward the higher-support fundamental** (a PRI=T pulse fits both the
  T and 2T sequences). The *direction* (cdif < sdif) is **unproven** (the de-risk probe never
  implemented association — advisor) and must be probed before it is pinned; **`n_pri` is the
  de-risked headline scalar**, not `assoc_pct`'s sign.
- **`n_pri`** = count of detected PRIs — the **central scalar** the verifier pins to **flip**
  between rungs (cdif > n_true, sdif == n_true on the stable showcase) — the not-a-dead-knob proof
  (the slice-5 `err_m` precedent). `n_true` (the truth emitter count) ships alongside for reference.

## Decisions taken (advisor-reviewed 2026-06-30 — design endorsed, lesson de-risked, constraints folded)
- **Entity/subsystem model — three subsystems across three phases (the capstone).** A
  **`:pulse_emitter`** entity carries `ConstantVelocity` + **`PulseEmitter`** (phase-2 `build_env!`
  → publishes its params to `env[:emitters]`; RNG-free). A single **`:esm`** entity (the intercept +
  fusion platform — co-located, as a real ESM is) carries `ConstantVelocity` + **`ESMReceiver`**
  (phase-3 `observe!` → generates + measures the interleaved TOA stream into `env[:toa_stream]`; the
  ONE draw site) + **`Deinterleaver`** (phase-4 `decide!` → reads the stream, runs the histogram /
  PRI extraction / association per the `:deinterleaver` fidelity, publishes telemetry). The §3
  coupling done right — emitters→receiver and receiver→deinterleaver both **through `env`**, never a
  direct call — and it lights **build_env! + observe! + decide! in one tick** (the intro celebrates
  it as the phase-contract capstone). The receiver/deinterleaver are separate subsystems (not one
  doing both phases) so the `env[:toa_stream]` handoff is independently testable (the DFSensor→
  Geolocator pattern, here co-located on one entity).
- **`env[:emitters]` is a VECTOR of param records** (`const EmitterParams = @NamedTuple{id::Symbol,
  pri::Float64, phase::Float64, pulse_width::Float64, pos::Vec3}`), appended in sorted-emitter-id
  order (the `PulseEmitter` subs run in sorted-id order, so the receiver's draw order across
  emitters is deterministic — the §1 bug class made free). `env[:toa_stream]` is a record carrying
  the sorted `Vector{Float64}` TOAs + the parallel `Vector{Symbol}` truth ids (INTERNAL, like
  `BearingRecord`/`JamContribution`). The deinterleaver re-sorts defensively before the solve.
- **Fidelity = `deinterleaver => (:cdif, :sdif)`**, joining `LIVE_FIDELITY_MODES`. Both rungs
  consume the **same drawn TOA stream** (the rung selects only the phase-4 post-processing), so it is
  **introduce-safe AND toggle-bit-identical** (the slice-4 `:ep` / slice-5 `:estimator` contract,
  NOT slice-3's `:cfar` guard — there is **no draw-topology hazard anywhere in this slice**:
  generation + all draws live in `observe!`, independent of the rung). `set_fidelity :deinterleaver`
  needs **no server change** (the per-key table from slice 3 validates it; the `:cfar` introduce-guard
  at `server.jl:172` doesn't match `:deinterleaver`). The source-of-truth `DEINTERLEAVER_MODES =
  (:cdif, :sdif)` lives in `deinterleave.jl` and is **referenced** by `LIVE_FIDELITY_MODES` (the
  `CFAR_MODES`/`ESTIMATOR_MODES` one-list-no-drift lesson) — so `deinterleave.jl` must precede the
  `LIVE_FIDELITY_MODES` definition (see Context/landmarks).
- **`deinterleave.jl` is a new HANDOFF §9-style SHARED PHYSICS LIB** (the detection.jl/CFAR analog —
  pure, no RNG, closed-form, dependency-free). It is **genuinely new** (HANDOFF §9 doesn't list a
  deinterleaver among the reuse map; the PRI-histogram math isn't the GDOP/LS/Kalman/CFAR family).
  Keep it free of subsystem/world types — it takes plain `Vector{Float64}` TOAs and returns plain
  PRI/assignment data — so a future PRI-transform rung or a comms-EW hop-deinterleaver reuses it.
- **The pulse generation lives in `observe!`, on LOOK-TICKS ONLY** (the receiver's `revisit_s`
  cadence — the `next_look_t` gate the radar already uses, `radar.jl`). Between looks the last
  realization is republished as telemetry (the slice-1/2/3 "readout never blanks" pattern). This
  keeps generation off non-look ticks (hundreds of TOAs/tick otherwise) and makes the draw cadence
  explicit + deterministic.
- **Per-dwell pulse count is BOUNDED (~≤ 500).** `T_dwell / min_PRI` can blow up (100 ms / 10 µs =
  10 000 TOAs/frame → a fat wire frame + a slow histogram). The scenario picks `T_dwell` + PRIs to
  keep it sane (the de-risk probe ran 80 ms × ~1.5 ms PRIs → ~150 pulses); the loader can warn /
  the receiver can cap + name the decimation if a future scenario pushes it. Pin the bound.
- **Telemetry: a FIXED-length histogram + threshold (assert on these) + variable-length TOA/PRI
  arrays (display only, NEVER assert — advisor).** `<esm>.histogram` (the cumulative difference-count
  curve, `n_bins` Float64) + `<esm>.threshold` (the detection threshold curve, `n_bins`) are the
  fixed-length core objects (the CFAR `profile_db`/`threshold_db` precedent — the slice-3 array-
  telemetry widening already documented in `protocol.jl:64`). The **displayed histogram bars AND the
  threshold curve are rung-INDEPENDENT (the shared cumulative pipeline); the rung changes ONLY the
  detected-PRI markers** (cdif marks the phantom 2T peak, sdif doesn't) — a crisp same-bars/same-line/
  different-markers visual. Variable-length `<esm>.pri_us` (detected PRIs), `<esm>.toa_us` + `<esm>.assign`
  (the raster: TOAs + assigned-emitter index) are display-only (JSON3 serializes variable arrays
  fine + deterministic given seed, but the verifier/determinism tests assert on the **scalars**
  `n_pri`/`assoc_pct`/`n_true` and the **fixed** histogram, never the variable arrays). The static
  `pri_axis_us` (bin centers) + `dwell_us` ship **once at handshake** (`_esm_axis_info`, the
  `range_axis_m` analog — they can't change frame-to-frame).
- **Live sliders are `jitter_us` + `p_intercept` (draw-count-safe); the fidelity button is the
  `deinterleaver` cycler.** `T_dwell` / spurious count / `n_bins` / `bin_width` / `C` levels /
  thresholds are LOAD-TIME static (draw-count or axis-defining). Emitters need not move (geometry is
  inert) — the interactive levers are measurement quality (sliders) + the algorithm (button), not
  emitter motion (the contrast to slice 5, where motion swept the GDOP lesson).
- **The Godot client gains a NEW ESM / PRI render mode** — neither the x-z elevation view (slices
  1/2/4) nor the x-y plan view (slice 5) nor the range-power view (slice 3) shows a TOA raster +
  difference histogram. Discriminated at the **handshake** off `fidelity[:deinterleaver]` (the
  slice-3 `range_axis_m`→cfar / slice-5 `estimator`→geoloc pattern; extend the `_fid_kind`
  discriminator → add `esm`). Two stacked panels: the **TOA raster** (time axis, each pulse a tick
  colored by its assigned emitter index — interleaved chaos resolving into clean rows) and the
  **difference histogram** (τ-axis in µs, bars + the threshold curve + green markers at accepted
  PRIs — the phantom appears/vanishes on the toggle). The shared fidelity button becomes the
  **deinterleaver cycler** (`cdif ↔ sdif`, `set_fidelity`, the guarded-disconnect pattern). The
  slice-1/2/4 spatial, slice-3 cfar, and slice-5 geoloc paths are untouched (their smoke-loads + UI
  tests stay green).
- **No-ESM scenarios stay byte-identical.** Absent any `:pulse_emitter`/`:esm`, `env[:emitters]` /
  `env[:toa_stream]` are never written, no ESM subsystem runs, and the radar/jammer/DF RNG path is
  untouched. Slices 1–5 (and `test_determinism`, the `_sample_z` golden) stay byte-identical — pin
  it. A slice-6 scenario has **no radar/jammer/DF**, so the paths never interact (multi-domain fusion
  is a future slice).

## Review gates (cadence: staged, mirroring slice 5)
1. **`deinterleave.jl` primitives green (closed-form + the structural subharmonic-trap pin).** The
   pure lib — `difference_histogram`, the `cdif`/`sdif` PRI extractors, `associate`, all pure / no
   `w.rng`, dependency-free, SI seconds in / out. `DEINTERLEAVER_MODES = (:cdif, :sdif)` defined
   here. `test_deinterleave.jl` (closed-form, slice-2 style — **explicit `atol`**, never rtol-`≈0`):
   - a **deterministic stable 3-emitter fixture** (`[1300,1700,2300] µs`, the de-risked numbers):
     `cdif` returns the 3 fundamentals **+ a phantom at 2×1300** (the structural trap — pinned as a
     real over-detection, the slice-2/3/4/5 "don't-pass-by-construction" rule), `sdif` returns
     **exactly** the 3 fundamentals (the subharmonic check removes the phantom). The **`n_pri` flip**
     (cdif=4, sdif=3=n_true) is the headline assertion;
   - PRI estimates within ½-bin of truth (centroid refinement — pin the offset is gone);
   - the **2-emitter sharper case** (cdif hallucinates 2T₁ **and** 3T₁ → 4, sdif → 2);
   - the subharmonic check in isolation (a candidate at 2T with its fundamental present → rejected;
     a true fundamental with no sub-multiple → kept);
   - `associate` correctness on the noise-free stream (every true pulse → its emitter; `assoc_pct`
     = 1.0 with no spurious). **`n_pri` is the load-bearing flip** (cdif=4 vs sdif=3, de-risked); do
     **NOT** pin `assoc_pct`'s *direction* (cdif vs sdif) — it depends on association tie-breaking
     (advisor), so until a probe confirms it, assert `assoc_pct` is computed + finite, not its sign;
   - units (a PRI authored/printed in µs round-trips through SI-seconds internals) + degenerate
     guards (empty stream, single pulse, one emitter → no throw, sensible empties).
   Wire into `runtests.jl` after the detection/cfar tests. Slices 1–5 green untouched.
2. **The ESM pipeline wired (phases 2+3+4 lit, no fidelity toggle yet).** `PulseEmitter <: Subsystem`
   (phase-2 `build_env!` → `env[:emitters]`); `ESMReceiver <: Subsystem` (phase-3 `observe!` →
   `env[:toa_stream]`, the one draw site, on look-ticks); `Deinterleaver <: Subsystem` (phase-4
   `decide!` → histogram/PRI/assoc telemetry); `:pulse_emitter`/`:esm` kinds + `_validate_esm` in
   `scenario.jl`. `EmitterParams` named-tuple. Telemetry clamped finite (reuse geometry.jl's
   `_finite`; the histogram/threshold floored like the CFAR arrays). Tests (`test_esm.jl`, the
   `test_jammer.jl`/`test_geolocation.jl` analog): `PulseEmitter` populates `env[:emitters]` (record
   shape + params); `ESMReceiver` populates `env[:toa_stream]` with the **exact** drawn TOAs
   reconstructed off a fresh `Xoshiro` (the slice-5 exact-draw pin, per the §1 draw order) + truth ids stamped + bounded
   count; `Deinterleaver` `n_pri`/`assoc_pct` match `deinterleave.jl` on the realized stream;
   telemetry keys present + **finite** (incl. a degenerate single-emitter / empty-dwell case → no
   throw); **draw-stream invariance** (the stream is drawn once/look on look-ticks; a no-ESM scenario
   byte-identical to slices 1–5 — golden + `test_determinism` green); the **histogram raises peaks at
   the true PRIs** over a realized stream (deterministic). The fidelity plumbing
   (`LIVE_FIDELITY_MODES[:deinterleaver]` + the `Deinterleaver` dispatching `get(w.fidelity,
   :deinterleaver, :cdif)`) lands here (the slice-5 gate-2 precedent — introduce-safe, no draw
   hazard, and the Deinterleaver actually consumes the key). `test_determinism.jl` + a slice-6
   scenario bit-identical (replay + rung toggle).
3. **`deinterleaver` fidelity + scenario + Godot ESM view + verifier.** `set_fidelity :deinterleaver`
   works with **no server change** (introduce-safe, the `:ep`/`:estimator` contract).
   `scenarios/slice6_deinterleave.yaml` (3 stable well-separated non-harmonic emitters — the de-risked
   `[1300,1700,2300] µs` — + one ESM; `jitter_us`/`p_intercept` sliders; default `:cdif` so the
   phantom is visible on connect and **toggling to `:sdif` removes it**; numbers tuned **empirically**
   with a throwaway probe + validated against the **live wire path**, the slice-3/4/5 rule). The Godot
   ESM view (TOA raster colored by assigned emitter + difference histogram + threshold curve + PRI
   markers; the `deinterleaver` badge + cycler button + the two sliders); `net/slice6_verify.gd`
   (drives the real server: the histogram peaks sit at the true PRIs; **`set_fidelity :deinterleaver`
   cdif→sdif flips `n_pri` 4→3** (the load-bearing assertion; `assoc_pct`'s direction only if the gate-1
   probe confirms it) with `t` **bit-identical** under a held seed —
   the not-a-dead-knob deliverable; `set_param jitter_us` blurs the histogram / `p_intercept` thins
   it, slider→core→telemetry); `net/slice6_ui_test.gd` (the deinterleaver cycler + the two sliders +
   badge, mock client, no server); `Sandbox.tscn` smoke-loaded headless against a slice-6 server;
   `test_determinism.jl` (mid-run `:deinterleaver` **toggle AND introduce** both bit-identical,
   `n_pri` differs between rungs proving it is not a dead knob; no-ESM-introduce → rng end-state
   unchanged — but see the slice-5 note: the introduce-safe-on-a-non-ESM-world leg is safe-by-
   construction [nothing reads `:deinterleaver` without a `Deinterleaver`] and is pinned at the
   command level by `test_server.jl`); `test_server.jl` (`set_fidelity :deinterleaver` write/reject +
   introduce-allowed on a non-ESM scenario; warmup ESM-free); `test_scenario.jl` slice-6 loader
   assertions (parse, deinterleaver default, **no radar/jammer/DF**, ≥2 `:pulse_emitter` with
   stable PRIs stored in SI seconds [the slice-4 "keys equal defaults so `haskey` is the discriminating
   check" rule — assert the µs→s conversion], one `:esm`, sliders address `jitter_us`/`p_intercept`,
   deinterleaver not a knob). The ESM-view `_draw` pixel branch **visually confirmed** via the windowed
   shot harness (the slice-3/4/5 technique, [[ewsim-godot-headless]]): the phantom-emitter marker
   appearing under `cdif` and vanishing under `sdif`, the raster resolving from chaos to clean rows.
   **(stretch, deferred)** an offline `batch.jl` `kind = :pri_mc` (deinterleave success-rate vs
   jitter/emitter-density, an analytic-vs-MC-style sweep) + `clients/notebooks/slice6_pri.jl` Pluto
   diagram — **not** a live rung.

## Task checklist
> **Gate 1 DONE & green (1101 tests, +46) — 2026-07-01.** Params PRINCIPLED-then-probed (advisor's
> overfit guard, ONE shared set for both fixtures): bin 20 µs, C=15 levels, `thresh_frac=0.4` on a
> WIDE plateau (cdif=4 holds for thresh ∈ [0.30, 0.62]·peak; max in-band spurious peak 15 vs min-kept
> count 32 — NOT a knife-edge). **The SEARCH BAND is the binding constraint (advisor, probe-confirmed):**
> `max_lag` must satisfy **`2·min_PRI < max_lag < 2·(second-smallest PRI)`** = (2600,3400) µs here, so
> EXACTLY the one phantom (2×min=2600) is in-band and the next harmonic (2×1700=3400) is out.
> `max_lag=3000` sits central (2700–3300→cdif=4); 2500→cdif=3 (DEAD KNOB), 3500→cdif=5 (forest). It is
> **NOT "just above the max fundamental"** (a coincidence here since 2×1300≈2300; FAILS for a clustered
> set like [2000,2300,2600] where "just above max"≈2700 excludes 2×2000=4000 → dead — needs (4000,4600)).
> **Gate 3's scenario MUST honour this window.** **Headline pinned: 3-emitter [1300,1700,2300] µs →
> cdif=4 (3 fundamentals + phantom at 2×1300≈2600 µs) / sdif=3 — the `n_pri` flip.** PRIs centroid-refined
> to within a bin (observed <½-bin; largest 7 µs on the bin-edge 1700 µs PRI). **Deviation from the
> sketch below:** the **2-emitter** case is **cdif=3 / sdif=2** (NOT 4/2) — 3×1300=3900 falls outside the
> band that keeps the 3-emitter case clean (per-fixture bands would be overfit — advisor); still the
> phantom lesson. **Sequence-search is INERT on this stable stream** (probe: `min_seq∈{0,10,30,50}` →
> identical PRIs; the threshold does the discrimination — every periodic lag recurs); it stays in the
> pipeline and is validated on spurious/jittered TOAs in gate 2, not here. `associate` is **two-sided
> support** (a train member has partners at ±τ, fundamental tie-break) — `assoc_pct` is **finite + high
> (>0.8) interleaved, ==1.0 on a lone train**, direction (cdif vs sdif) NOT pinned (real coincidences on
> commensurate PRIs cap it <1 — the honest boundary; extract-and-remove was WORSE, 0.84). Slices 1–5
> byte-identical (the new lib touches no radar/detection path). **Next: gate 2.**
- [x] 1. **`deinterleave.jl` primitives (pure, SI-seconds, dependency-free).** `difference_histogram`,
      `cdif`/`sdif` PRI extraction (cumulative-vs-sequential + the adaptive threshold + the subharmonic
      check), `associate` + `assoc_pct`, centroid PRI refinement; `DEINTERLEAVER_MODES = (:cdif,
      :sdif)`. Export. `test_deinterleave.jl` per gate 1 (the structural subharmonic-trap pin: cdif=4
      vs sdif=3 on `[1300,1700,2300]`; the 2-emitter sharper case; subharmonic-check in isolation;
      association; units; degenerate guards). Wire into `runtests.jl` after the detection tests.
      Slices 1–5 green untouched.
- [x] 2. **The ESM pipeline wired (phases 2+3+4 lit) — DONE & green (1184 tests, +83), 2026-07-01.**
      `PulseEmitter`/`ESMReceiver`/`Deinterleaver` in a new `esm.jl` (included after `radar.jl`, mirroring
      `geolocation.jl`; NO back-dep on radar symbols — R/c omitted so `_range` isn't needed; reuses
      geometry.jl's `_finite` + deinterleave.jl's pure math). `EmitterParams` + `ToaStream` named-tuples;
      `env[:emitters]` (phase 2) → `env[:toa_stream]` (phase 3, the ONE draw site on look-ticks) →
      telemetry (phase 4); truth-id stamping; bounded pulse count (`_ESM_MAX_PULSES=1000`). **Deviation
      from the sketch (advisor-endorsed): the dwell window is PHASE-REFERENCED `[0, T_dwell)`, NOT the
      literal `[t, t+T_dwell)`** — it matches gate-1's `gen_stream`, makes the candidate count a function
      of STATIC config only (so the per-look draw count is truly `w.t`-invariant and the exact-draw test is
      `w.t`-independent), and fits "geometry inert / emitters need not move." Consequence stated: the stream
      is structurally identical every look, only the drawn noise differs (a deliberately static scene).
      **Exact §1 draw order pinned bit-for-bit** (the determinism-golden risk surface — `test_esm.jl`
      reconstructs it MANUALLY off a fresh `Xoshiro`, independent of `_draw_toa_stream`): emitters
      sorted-id → within an emitter k-ascending → per candidate JITTER(`randn`) THEN INTERCEPT(`rand`) both
      UNCONDITIONAL → `n_spurious` uniform(`rand`) LAST; total `2·n_candidate + n_spurious`, fixed. The
      Deinterleaver's phase-4 rung (`get(w.fidelity, :deinterleaver, :cdif)`) is PURE (no draw) — NO
      draw-topology hazard, so `:deinterleaver` is introduce-safe AND toggle-bit-identical (the
      `:ep`/`:estimator` contract). `n_true` from the `:pulse_emitter` ENTITY count (not distinct-in-stream
      — a `p_intercept`→0 slider can't lower it). Telemetry: fixed-length `histogram`/`threshold` arrays
      (CORE output, `_finite`-clamped, RUNG-INDEPENDENT — the shared cumulative pipeline; the rung changes
      only the PRI markers) + `n_pri`/`n_true`/`assoc_pct` scalars + display-only variable `pri_us`/`toa_us`/
      `assign`. `:pulse_emitter` (pri/phase/pulse_width µs→SI-seconds; pri>0 rejected at LOAD to avoid an
      infinite emit loop) + `:esm` (t_dwell/params µs→s, gate-1's proven defaults; live `jitter_us`/
      `p_intercept` sliders) kinds in `_build_entity`; `_validate_esm` (≥2 emitters, 1 ESM, bounded-pulse
      guard) at LOAD. `LIVE_FIDELITY_MODES` REFERENCES `DEINTERLEAVER_MODES` (the one-list-no-drift lesson;
      introduce-safe, no `:cfar`-style guard). `test_esm.jl` (env-populated + record shape; the EXACT-draw
      golden; clean-stream 144-pulse count + truth-stamp; Deinterleaver reproduces `detect_pris`/`assoc_pct`;
      **the headline cdif n_pri=4 / sdif n_pri=3 flip on the WIRED stream**; histogram peaks at the true
      PRIs; the draw-free rung switch [rng lockstep, n_pri differs]; finite telemetry incl. a degenerate
      empty dwell [no throw]; no-ESM byte-identity of the wire surface; loader arms + rejects). `test_determinism.jl`
      + a slice-6 scenario: same-seed bit-identical TOA-STREAM trace (the RNG fingerprint, sharper than
      n_pri — advisor), draw-free rung switch, mid-run `:deinterleaver` toggle AND introduce bit-identical.
      Slices 1–5 byte-identical (esm.jl touches no radar/detection path; the `_sample_z` golden +
      test_determinism green through the include). **Server handshake (`_esm_axis_info`), scenario YAML,
      Godot ESM view, verifier all deferred to gate 3.** **Next: gate 3.**
- [ ] 3. **`deinterleaver` fidelity + scenario + Godot ESM view + verifier.** `scenarios/
      slice6_deinterleave.yaml` (the de-risked 3-emitter numbers, default `:cdif`, jitter/intercept
      sliders). Godot `Sandbox.gd` new `"esm"` mode (`_fid_kind → esm` off the handshake; `_draw_esm`
      raster + histogram, all from telemetry; the deinterleaver cycler). `net/slice6_verify.gd` (real
      server: histogram peaks at PRIs; cdif→sdif flips n_pri 4→3 + raises assoc_pct, bit-identical t;
      jitter/intercept sliders move the histogram). `net/slice6_ui_test.gd` (mock client). `Sandbox.tscn`
      smoke-loaded headless against a slice-6 server. Tests: `test_scenario.jl` (slice-6 loader),
      `test_server.jl` (`set_fidelity :deinterleaver` + warmup ESM-free), `test_determinism.jl`
      (toggle+introduce). `_draw_esm` visually confirmed via the shot harness (phantom appears/vanishes).
      **(stretch, deferred)** `kind = :pri_mc` batch + `slice6_pri.jl` Pluto.

## Context / landmarks
- **The phase contract is fully exercised here.** `build_env!` (phase 2, `subsystem.jl:13`),
  `observe!` (phase 3, `:15`), `decide!` (phase 4, `:17`) run in that fixed order in `tick!`
  (`subsystem.jl:28–32`), so `PulseEmitter`(2)→`ESMReceiver`(3)→`Deinterleaver`(4) is guaranteed
  visible in-order the same tick (the correctness-by-construction the jammer→radar and DFSensor→
  Geolocator couplings got). `env` is cleared + rebuilt each tick (`subsystem.jl:29`), so a stale
  stream can't leak.
- **The `env` coupling templates are `Jammer`** (`radar.jl` `build_env!` → `observe!` read — the
  per-radar Dict of `JamContribution`) **and `DFSensor`→`Geolocator`** (`geolocation.jl` — the
  `BearingRecord` vector + the observe!→decide! seam). Copy their shape: `const EmitterParams =
  @NamedTuple{…}`, a `get!`-into-`env` append in `PulseEmitter.build_env!`, a collect-read in
  `ESMReceiver.observe!`; `env[:toa_stream]` written by the receiver, read by `Deinterleaver.decide!`.
- **The array-telemetry + static-axis template is the CFAR radar** (`radar.jl` `_observe_cfar!` ships
  `profile_db`/`threshold_db`/`detections` arrays floored through `_snr_db_wire`; `_cfar_axis_info`
  ships the static `range_axis_m` once at handshake, merged into `scenario_frame` at `server.jl:105`).
  Mirror it: `histogram`/`threshold` arrays + `_esm_axis_info` → `pri_axis_us`/`dwell_us`. The
  protocol's `string → number/bool/array` widening is already documented (`protocol.jl:64`).
- **The fidelity table** is `LIVE_FIDELITY_MODES` (`radar.jl:106`), validated by `set_fidelity`
  (`server.jl:160`). Add `deinterleaver = DEINTERLEAVER_MODES`. **Include order (advisor — resolve at
  gate 2, a hard compile failure otherwise):** current order is `… detection → geometry → estimation
  → radar → geolocation → scenario → batch → server` (`EWSim.jl:16–27`). Slot `deinterleave.jl`
  (pure, defines `DEINTERLEAVER_MODES`, depends only on base Julia) **before `radar.jl`** (so
  `LIVE_FIDELITY_MODES` can reference it, the `ESTIMATOR_MODES`-in-estimation.jl move) and `esm.jl`
  (the subsystems, depends on world/subsystem/deinterleave) **after `radar.jl`** mirroring
  `geolocation.jl`. **Verify at gate 2 the ESM subsystems have NO back-dep on radar symbols** (R/c
  omitted → no `_range`); if one surfaces, the slice-5 fallback applies (move `LIVE_FIDELITY_MODES`
  to a tiny post-include registry). `:deinterleaver` carries **no** introduce-guard (the `:cfar`
  guard at `server.jl:172` doesn't match it — introduce-safe, the `:ep`/`:estimator` contract).
- **The loader** `_build_entity` (`scenario.jl:91`) is the `kind`-dispatch — add `:pulse_emitter`
  (a `pulse_emitter:` block → `pri`/`phase`/`pulse_width` in **µs authored**, stored **SI seconds**
  — the `beamwidth_deg`→`beamwidth_rad` µs/s mirror; + `ConstantVelocity` + `PulseEmitter`) and
  `:esm` (an `esm:` block → `t_dwell_us`, `jitter_us`, `p_intercept`, spurious/bins/levels;
  + `ConstantVelocity` + `ESMReceiver` + `Deinterleaver`). Update the unknown-kind error list
  (`scenario.jl:163`). `_validate_esm` (≈ `_validate_geoloc`, `scenario.jl:261`) asserts ≥2
  `:pulse_emitter` + exactly 1 `:esm` at LOAD (a clear load error, triggered by ESM-entity presence
  so a non-ESM scenario is untouched). **NB the `:emitter` kind is already taken by slice-5 DF** —
  slice-6 pulse radars are `:pulse_emitter` (no collision).
- **The look-tick gate** is the radar's `next_look_t`/`revisit_s` (`radar.jl` `_observe_cfar!`:
  `is_look = w.t + 1e-12 ≥ get(radar.comp, :next_look_t, 0.0)`). Reuse it in `ESMReceiver.observe!`
  so the TOA stream is regenerated on the ESM's revisit cadence + republished between looks.
- **Telemetry → wire** is generic (`protocol.jl:73` `state_frame` reads `env[:telemetry]`). The DF
  readouts use geometry.jl's `_finite`/`FINITE_CEIL` (`geolocation.jl:44`); reuse `_finite` for the
  ESM scalars (`n_pri` etc. are bounded counts/fractions, but clamp defensively); the histogram/
  threshold arrays floor like the CFAR arrays.
- **No-LinearAlgebra house style** holds — the histogram + sequence search + centroid are all plain
  array loops; no `LinearAlgebra`/`inv` needed (there's no matrix solve in this slice).
- **Units (the §1 trifecta, FIRST-CLASS here):** PRIs/jitter/dwell authored + displayed in **µs**,
  stored + computed in **SI seconds**. Convert at the loader (in) and the telemetry boundary (out)
  only — the `beamwidth_deg↔rad` / `sigma_theta_deg↔rad` precedent. A µs/s slip is this project's
  signature bug; pin a units round-trip in `test_deinterleave.jl` and the loader test.

## Watch-items (gotchas to bake in)
- **The phantom subharmonic is the LESSON — pin it deterministically, never let it be noise.** The
  cdif=4/sdif=3 contrast must hold on the **stable** fixture with **no RNG** (the de-risk probe
  proved it's structural). Assert it closed-form in `test_deinterleave.jl`; the live verifier asserts
  the **`n_pri` flip** on the realized (seeded) stream. Do NOT tune the rungs to pass by construction
  (the slice-2 atol-not-rtol≈0 / slice-3/4/5 don't-self-calibrate rule) — the SDIF subharmonic check
  is a real algorithm step, not a fudge that happens to drop one bin.
- **Units: µs vs SI seconds (the §1 bug trifecta).** Store seconds, display µs, convert only at the
  boundaries. A PRI of 1300 µs is 1.3e-3 s — mixing them by 10⁶ is the signature bug. Pin a round-trip.
- **No draw-topology hazard — but PROVE it** (the slice-4/5 pattern, the contrast to slice-3's `:cfar`
  guard *is* a lesson): the receiver draws a fixed count (jitter + intercept per fixed candidate set +
  static spurious) independent of the `:deinterleaver` rung — in the **exact order §1 pins** (jitter
  then intercept, both unconditional, spurious last). Pin (a) no-ESM byte-identity vs the
  slice-1 golden; (b) `n_pri` differs between rungs while the `w.rng` end-state is identical; (c)
  mid-run `:deinterleaver` toggle **and** introduce both bit-identical. **Keep `T_dwell` + spurious
  count LOAD-TIME static** — making them live sliders would change the draw count and desync replay
  (the `:cfar` hazard); only `jitter_us`/`p_intercept` are live (draw-count-invariant).
- **Bound the per-dwell pulse count (~≤ 500).** `T_dwell / min_PRI` can explode the histogram +
  the wire frame. Pick dwell/PRIs to stay bounded (the probe's 80 ms × ~1.5 ms ≈ 150 pulses); if a
  scenario pushes it, cap + **name the decimation** (no silent truncation — HANDOFF §1). The loader
  can warn.
- **Degenerate streams must NOT throw a tick** (the "a live config can't crash a tick" watch-item, on
  a new surface). An empty dwell (all pulses dropped by a `p_intercept`→0 slider), a single pulse, or
  a lone emitter → the histogram/extractor return sensible empties + clamped-finite telemetry, never
  an OOB/throw. A live `p_intercept` slider can drive the empty case, so guard at the consumer; the
  loader rejects a malformed AUTHORED config. Test the empty + single-pulse cases.
- **The displayed histogram bars AND the threshold curve are rung-independent (the shared cumulative
  pipeline); the rung changes ONLY the PRI markers.** Don't recompute the threshold in GDScript — it is
  core output, shipped (the CFAR `threshold_db` invariant, HANDOFF §1). The phantom appears as a *marked*
  peak under cdif and an *unmarked* peak under sdif — same bars, same threshold line, different markers.
- **Variable-length TOA/PRI telemetry: display only, NEVER assert on it.** The verifier +
  determinism tests assert on the **scalars** (`n_pri`/`assoc_pct`/`n_true`) + the **fixed-length
  histogram**, not the per-pulse `toa_us`/`assign` arrays (deterministic but unwieldy). And
  `_update_readout` must **skip Array telemetry** (the slice-3 watch-item: it would `float()`-crash
  on the arrays — already handled for cfar, re-confirm for the esm keys).
- **Jitter is receiver-side, named — emitter PRI random-walk is the harder, deferred case.** Don't
  present receiver TOA jitter as modeling emitter PRI instability (they diverge at higher lags, which
  is exactly where CDIF works). Name the approximation (HANDOFF §1: no hidden approximations).
- **Deferred to future slices, explicitly NOT here:** staggered / dwell-switching / sliding PRI
  (its own research problem), emitter-intrinsic PRI random-walk, Nelson's PRI-transform rung, TDOA
  multi-receiver emitter geolocation (which *would* use the R/c offsets this slice drops), ESM +
  radar/jammer/DF fusion in one scenario, the live MC success-rate rung (offline only). Listing them
  keeps the slice-6 boundary honest.
