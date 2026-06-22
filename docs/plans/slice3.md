# Slice 3 — CFAR sandbox (+ pulse integration / full Swerling)

The first slice that adds a **new core object**: a *range-power profile* (a vector
of range cells), not just a point target's SNR. CFAR (Constant False-Alarm Rate)
sets the detection threshold **adaptively** from the noise/clutter estimate in the
cells *around* each cell-under-test — the slice-1/2 detector used a single fixed
`−ln(Pfa)` threshold. Dialing the CFAR variant (CA/GO/SO/OS) and watching the
threshold curve respond *is* the lesson. Source of truth: `HANDOFF.md` §10 (item 3),
§3 (`detection.jl` carries CFAR), §13 (Swerling 2–4 land here), §1 (named
approximations), §12 (the fidelity badge).

This slice is **bigger than slice 2** because the user pulled **pulse integration**
in (see Decisions): on top of CFAR it generalises the detector from single-pulse to
**N-pulse non-coherent integration** so the full Swerling 0–4 set becomes meaningful
(single-pulse SW1≡2 and SW3≡4 — only integration makes 2≠1 and 4≠3). Hence **4
steps**, not slice 2's 3. The advisor flagged integration as "its own slice"; the
scope call is the user's, recorded here, and the staging quarantines the interaction
(see the Gamma-cell note in step 3).

**Done =** start the server on the CFAR scenario, connect Godot, watch a range-power
profile with two close targets and a clutter band; toggle the `cfar` rung
`fixed → ca → go → so → os` live and watch the **threshold curve** redraw — the
clutter edge spikes false alarms under `fixed`, CFAR tracks the noise floor and holds
Pfa; one close target **masks** the other under CA but resolves under SO/OS — with
`runtests.jl` green on the new closed-form CFAR + integration tests (and slice-1/2
tests untouched and still byte-identical).

## The physics (named approximations — HANDOFF §1)

Two additions, both behind named knobs, both composing with the slice-2 `propagation`
ladder (a CFAR profile can be built over a `two_ray` SNR → lobing *and* an adaptive
threshold at once).

### 1. N-pulse non-coherent integration + Swerling 0–4 (`detection.jl`)
- **Integrated statistic:** `z = Σ_{i=1}^{N_p} |x_i|²` — the sum of `N_p` single-pulse
  square-law outputs (the slice-1 `_sample_z`). Noise-only each `|x_i|² ~ Exp(1)`, so
  `z ~ Gamma(N_p, 1)` (Erlang for integer `N_p`).
- **Threshold (no SpecialFunctions — keep the slice-1 stance):** `Pfa = P(z > T) =
  e^{−T}·Σ_{k=0}^{N_p−1} T^k/k!` (Erlang survival — a *finite* sum for integer `N_p`,
  same spirit as the existing Poisson-mixture `pd_swerling0`). The forward function is
  elementary; invert for `T(Pfa)` by a monotone **root-find** (bisection/Newton).
  `N_p = 1` collapses to `T = −ln(Pfa)`, recovering `detection_threshold` exactly.
- **Swerling under integration** (per-pulse linear SNR; total integrated SNR `= N_p·SNR`):
  - **SW0** non-fluctuating — non-central χ²(2N_p, λ=2N_p·SNR); the existing
    Poisson-mixture generalises (slice-1 `pd_swerling0` is the `N_p=1` case).
  - **SW1** slow Rayleigh (one RCS draw shared by all N_p pulses) — finite-sum form
    (Difranco–Rubin) for integer `N_p`.
  - **SW2** fast Rayleigh (independent RCS per pulse) → `z ~ Gamma(N_p, 1+SNR)`, so
    `Pd = e^{−T/(1+SNR)}·Σ_{k=0}^{N_p−1} (T/(1+SNR))^k/k!` — clean finite sum. `N_p=1`
    → `exp(−T/(1+SNR))`, exactly today's `pd_swerling1`. **This is where 2≠1.**
  - **SW3** slow 4-DOF (dominant + Rayleigh) — finite-sum form, integer `N_p`.
  - **SW4** fast 4-DOF per pulse — finite-sum form. **This is where 4≠3.**
  - Every Pd is computed **two ways** (analytic finite-sum + MC) — the slice-1
    analytic-vs-MC discipline, now across all five cases × `N_p`.

### 2. CFAR adaptive thresholding (`detection.jl`)
- **Range-power profile:** a vector of `N_cells` range cells. Cell width is the radar
  **range resolution** `Δr = c/(2·B)` (from the matched-filter bandwidth — physically
  honest, not an arbitrary count, HANDOFF §1). Each cell = integrated noise (`Gamma(N_p,1)`)
  + **clutter** (elevated mean over a band, with a hard **edge**) + injected target
  signal (the cell whose range matches a target gets `_target_snr`'s power).
- **The CFAR window:** for each cell-under-test (CUT), `N` training cells split
  `N/2` per side, skipping `G` **guard** cells adjacent to the CUT (so a spread target
  doesn't poison its own estimate). Noise estimate → threshold `= α · estimate`:
  - **CA** (cell-averaging) — `estimate = mean(all N)`. Best in homogeneous noise;
    a strong neighbour raises it → **masks** a weak target; a clutter edge → **Pfa spike**.
  - **GO** (greatest-of) — `max(mean_lead, mean_lag)`. Tames the clutter-edge spike,
    worse at masking.
  - **SO** (smallest-of) — `min(mean_lead, mean_lag)`. Resolves closely-spaced targets,
    worse at edges.
  - **OS** (ordered-statistic) — sort the N training cells, take the k-th (`k≈0.75N`),
    `threshold = α·X_(k)`. Robust to both, costs detection loss.
- **`fixed`** rung — the slice-1/2 rule (`α = −ln(Pfa)`, no adaptation) **applied to the
  profile**, NOT a fall-back to the legacy point detector (see the determinism note in
  Decisions). It is the "before CFAR" baseline: it spikes at the clutter edge.
- **Approximations, named:** clutter = **elevated-mean exponential** (Rayleigh amplitude
  → cells stay exponential at `N_p=1`, so the CA/OS closed forms hold in the homogeneous
  interior and the *edge* is exactly where they break — that's the lesson). Weibull /
  K-distributed clutter deferred. CFAR window is one-dimensional in range (no Doppler).

## Decisions taken
- **`cfar` is a fidelity** (one knob, rungs `(:fixed, :ca, :go, :so, :os)`), toggled by
  the slice-2 `set_fidelity` command; the §12 badge shows the rung. The two-axis
  `detector`+`variant` alternative makes `variant` meaningless when off — rejected.
  **`N_train`/`N_guard`/design-`pfa` are sliders** (`set_param` on radar `comp`), not
  rungs — "widen the window, watch the CFAR loss change" wants the existing slider seam.
- **CFAR composes with `propagation`.** The target-cell power comes from the existing
  `_target_snr(prop, …)` (radar.jl), so a CFAR profile built over `two_ray` shows lobing
  **and** adaptive thresholding together — no forked SNR path.
- **Determinism — the load-bearing decision (advisor catch).** A profile look draws
  `~2·N_p·N_cells` randn; the legacy `detect_once` draws `~2·N_p` per target. So:
  - **Slice-1/2 scenarios** (no `:cfar` key) → the legacy point path, **byte-identical**,
    existing tests and `test_determinism` untouched.
  - **Within a CFAR scenario the profile is ALWAYS built and drawn**; the rung selects
    only the *thresholding rule*. Every live-toggleable rung (`fixed/ca/go/so/os`) shares
    the **identical** profile draw — including `fixed` (fixed-threshold-on-profile, NOT
    the legacy detector). So a mid-run `cfar` toggle is **bit-identical** (the slice-2
    mid-run-toggle property, preserved). This unifies the code path *and* sharpens the
    lesson: same profile, same draws, swap the rule, watch the edge.
  - **The same invariant at the command layer.** `set_fidelity` may change the *value*
    of a fidelity key already present in the scenario, but must NOT *introduce* a key that
    changes the draw topology — adding `:cfar` to a scenario that started without it would
    flip legacy-point-path → profile-path (different draw count) and desync a mid-run
    replay. So `set_fidelity :cfar …` is **rejected unless `haskey(w.fidelity, :cfar)`**
    (changing `:propagation`'s value stays safe; adding `:cfar` does not). The rung
    watch-item, generalised to the wire.
- **Pulse integration is IN** (user override of the advisor's "own slice"). It expands
  the slice to 4 steps. Quarantined: the integration closed forms are tested at the
  point-detector level (no CFAR); the CFAR closed forms are tested at `N_p=1` (clean
  exponential cells); the **combined** integration+CFAR path is validated by **MC
  Pfa-maintenance**, since CA/OS over `Gamma(N_p)` cells has only a messier closed form.
- **No SpecialFunctions.** Erlang-survival finite sums + a root-find threshold inverse
  keep detection.jl dependency-free (it was proud of "no Bessel, no SpecialFunctions").
- **Clutter = a new `:clutter` entity kind** (`pos` = near edge, `comp[:extent_m, :cnr_db]`),
  consistent with the loader's kind-dispatch. First cut: elevated-mean exponential.
- **The inert `:detection` fidelity key** (`analytic`/`monte_carlo`, declared in YAML,
  never dispatched) **stays inert** — out of scope, acknowledged.
- **Wire: telemetry may now carry ARRAY values** — a flagged extension (the `state_frame`
  docstring currently promises `string→number/bool`; arrays don't bother JSON3 but they
  change the documented contract, so flag it like slice-2 flagged `set_fidelity`). The
  **threshold curve is CORE output** computed in detection.jl and shipped — **never**
  recomputed in GDScript (the project's central invariant: physics in the core, the
  client renders arrays it's handed).
- **CFAR coexists with the slice-1/2 telemetry + event schema (don't break consumers).**
  - **Scalars stay.** Keep emitting `<id>.snr_db/.pd/.detected/.visible` for the strongest
    target (the readout and existing verifiers depend on them) *alongside* the new arrays.
    `.pd` under an *adaptive* threshold isn't cleanly defined — **define it explicitly** as
    Pd-at-design-`pfa` for the strongest target (the analytic Pd at the slider's `pfa`,
    consistent with what the threshold is calibrated to), so the readout stays meaningful.
  - **The static range axis ships ONCE in the handshake**, not per frame: `range_axis_m`
    (or `Δr`/`range_start`/`N_cells`) goes in `scenario_frame` (core-computed, so not a
    physics-in-client violation) — it can't change frame-to-frame. Only
    `profile_db`/`threshold_db`/`detections` are per-frame state.
  - **Events carry a cell, not just a target.** A flagged *clutter/noise* cell is a false
    alarm with **no `:of`** — today's `:detection` event has `:by`/`:of`. Extend it with a
    `:cell`/`:range` field; a target-cell hit also carries `:of`, a false alarm carries
    only `:cell`. The clutter-edge spike *is* false alarms, so this is the lesson surface
    and must be explicit, not implicit.

## Review gates (cadence: staged)
1. **Pulse integration + Swerling 0–4 green** — `detection.jl` integrator + threshold
   inverse + 5 Swerling Pd (analytic finite-sum) with `test_detection` extended:
   threshold round-trip (`Pfa→T→Pfa`, and `N_p=1` == `−ln(Pfa)`), every Swerling's
   analytic Pd inside the MC Wilson band, **SW2≠SW1 and SW4≠SW3 at `N_p>1`** (the whole
   point), `N_p=1` recovers slice-1 exactly. Slice-1 tests stay green untouched.
2. **CFAR physics green** — CA/GO/SO/OS over a profile + `α` scaling + `test_cfar.jl`:
   CA `α = N·(Pfa^(−1/N)−1)` (and `N→∞` → `−ln(Pfa)`, the CFAR-loss anchor), OS
   `Pfa = ∏_{i=0}^{k−1}(N−i)/(N−i+α)` (closed form, re-derived), GO/SO + the combined
   path by **MC Pfa-maintenance** (design Pfa held in the homogeneous interior). Plus a
   **GO/SO ordering invariant** at a **common α** (NOT per-variant-calibrated):
   `Pfa_GO ≤ Pfa_CA ≤ Pfa_SO` — catches a swapped GO/SO cheaply. (At common α
   deliberately: per-variant-calibrated Pfa is equal *by construction* and would pass for
   the wrong reason — same trap as slice-2's "explicit atol, not rtol≈0".) All closed
   forms at `N_p=1`; `N_p>1` by MC.
3. **Knob switches live** — `radar.jl` builds the profile + dispatches on the `:cfar`
   rung (composing with `:propagation`); `:clutter` entity loads; `set_fidelity`
   generalised to a per-key mode table (`:propagation`→`PROPAGATION_MODES`,
   `:cfar`→`CFAR_MODES`); profile/threshold arrays ship as telemetry (finite, no
   Inf/NaN). Integration tests: rung switches the detections for the **same** profile
   draw, **mid-run toggle replays bit-identical**, slice-1/2 scenarios unchanged.
4. **Visible live** — `slice3_cfar.yaml` (two close targets + clutter edge), Godot
   range-power view (range × power-dB, the threshold curve overlaid, detections marked)
   + `cfar` rung toggle + `N_train`/`N_guard`/`pfa` sliders + the §12 badge; headless
   verifier asserts the toggle loop (rung flips detections at fixed `t`/draws; the
   clutter-edge spike under `fixed` vanishes under GO/OS; masking under CA resolves
   under SO/OS). **(stretch)** Pluto CFAR diagram (Pd/Pfa vs SNR per variant, or
   threshold-curve panels over the profile).

## Task checklist
- [x] 1. `detection.jl`: N-pulse non-coherent integrator. **DONE & green (546 tests).**
      `detection_threshold(pfa, n_pulses=1)` — `N_p=1` returns `−log(pfa)` float-exact;
      `N_p>1` bisects the strictly-decreasing Erlang survival `Pfa(T)=e^{−T}Σ_{k<N}T^k/k!`.
      Analytic `pd_analytic(snr, pfa; swerling∈0:4, n_pulses=1)` — five finite/rapidly-
      truncating forms, all derived from first principles + advisor-checked: **SW0**
      `Σ_k poisson(k;N·snr)·poisscdf(N−1+k;T)`; **SW1** geometric weights
      `Σ_k(1−ρ)ρ^k·poisscdf(N−1+k;T)`, ρ=N·snr/(1+N·snr); **SW2** `ErlangSurv(T/(1+snr),N)`;
      **SW3** NB-r2 weights `Σ_k(1−μ)²(k+1)μ^k·poisscdf(N−1+k;T)`, μ=N·snr/(2+N·snr); **SW4**
      binomial-mixture-of-Erlangs `Σ_j C(N,j)(s/v)^j(1/v)^{N−j}ErlangSurv(T/v,N+j)`,
      v=1+snr/2 (from the per-pulse MGF partial fraction). SW0/1/3 share one
      **saturation-aware** accumulator (once the inner `poisscdf` ≈1, the residual sum is
      the leftover weight mass — converges in ~T+O(√T) terms regardless of ρ,μ→1, so the
      slice-1 Poisson-sized cap can't under-truncate the long high-N·SNR tail — advisor
      catch). `n_pulses=1` routes SW0/1 to the exact slice-1 `pd_swerling0/1`; SW1≡SW2,
      SW3≡SW4 for a single pulse. `_draw_signal`/`_sample_z`/`detect_once`/`pd_montecarlo`
      generalised to integrate `N_p` square-law draws with the slow (one shared amplitude:
      SW0/1/3) vs fast (fresh per pulse: SW2/4) pattern; 4-DOF amplitude `|a|²=(snr/4)·χ²₄`
      (phase irrelevant under circular noise). **N_p=1 draws are byte-identical to slice 1**
      — same order (noise then signal), same `sfluc=√(snr/2)` spelling (NOT `√snr·√½`, 1 ULP
      apart), direct `(sI+nI)²+(sQ+nQ)²` for the single pulse (the accumulator is only used
      for `N_p>1`, where no golden exists). `test_detection.jl` extended: threshold
      round-trip (`Pfa→T→Pfa`, `N_p=1`==`−log(pfa)` exact), all 5 Swerling inside the MC
      Wilson band at `N_p=8` (incl. a 15 dB point that exposes a mis-sized truncation cap),
      SW2≠SW1 / SW4≠SW3 at `N_p>1`, `N_p=1` collapses 2→1 & 4→3, an **absolute golden**
      pinning `_sample_z`'s N_p=1 bits (captured from slice-2; `test_determinism` only
      compares run-to-run so it can't catch a draw-order regression — advisor catch; it
      caught two real 1-ULP desyncs: the accumulator op-order and `sfluc=√(snr/2)` vs
      `√snr·√½`), and the **Swerling fluctuation-loss ordering** as an EXTERNAL anchor for
      SW3/SW4 (steadier wins at high Pd: SW0>SW3>SW1; reverses at low SNR: SW1>SW3>SW0, and
      likewise SW2>SW4>SW0) — `≈MC` only proves the derivation matches the sampler's own
      model, so the ordering brackets the new 4-DOF case between the slice-1-anchored SW0/SW1
      (advisor catch; the model checks out as the textbook `4g·e^{−2g}` Swerling-3 pdf).
      `scenario.jl`: `n_pulses≥1` (was `==1`), stored in `comp[:n_pulses]`. `radar.jl`
      threads `n_pulses` through `observe!`'s threshold/`pd_analytic`/`detect_once` (default
      1 via `get` ⇒ slice-1/2 scenarios byte-identical; makes a loaded `n_pulses` actually
      fire). `test_scenario.jl` rejection test flipped (n_pulses=3 loads & stores; <1 rejected).
- [x] 2. `detection.jl`: CFAR primitives. **DONE & green (720 tests).** `cfar_alpha(variant,
      n_train, pfa; n_pulses=1, k=⌈0.75N⌋)` → the threshold multiplier α with `T=α·(noise
      estimate)`, mean-convention; `cfar_threshold(profile, cut; …)` (single CUT) and the
      vectorised `cfar_scan(profile; …) -> (threshold, detections)` (LINEAR power, PURE — no
      RNG, so it can't desync a trace; the profile DRAW is step 3 / radar.jl). Variant set
      `CFAR_VARIANTS=(:fixed,:ca,:go,:so,:os)` (step-3 `CFAR_MODES` will **reference** this,
      not re-list — advisor catch on drift, the slice-2 `PROPAGATION_MODES` lesson).
      **Closed forms (forward `_cfar_pfa`, inverted by `_bisect_alpha` — same idiom as
      `detection_threshold`, no SpecialFunctions):** CA exponential `(1+α/N)^{−N}` (N_p=1,
      direct `α=N(pfa^{−1/N}−1)`) AND **gamma N_p>1 exact via the Beta tail** — CUT~Gamma(N_p,1),
      training sum~Gamma(N·N_p,1), ratio crosses Beta(N_p,N·N_p) at `w=α/(N+α)`; `_beta_surv_int`
      is the regularized incomplete Beta as a finite binomial sum `Σ_{j<N_p} C(M,j)w^j(1−w)^{M−j}`
      (advisor: drop my heuristic-α, this is exact and dependency-free, collapses to the N_p=1
      CA form). OS `∏_{i<k}(N−i)/(N−i+α)` (Rohling); SO `2Σ_{j<M}C(M−1+j,j)(2+α/M)^{−(M+j)}`
      (M=N/2, from E[e^{−s·min}] over two Gamma(M,1) halves); GO `2(1+α/M)^{−M}−Pfa_SO`
      (max+min identity). **GO/SO/OS are N_p=1 only** (no finite-sum inverse over Gamma cells —
      reject N_p>1); the integrated path is **CA-only + MC-validated** (the plan's "N_p>1 by MC").
      Edge cells shrink the training set & reuse the interior α (Pfa held only in the interior;
      global-mean fallback if the window fully truncates — never OOB). `test_cfar.jl` (174 tests):
      CA closed form + round-trip + the `N→∞→−ln(pfa)` monotone CFAR-loss anchor; OS product form
      vs independent recompute + `k=1` closed value; SO/GO round-trip + the `N=2/M=1` hand value
      `2/(2+α)`; the **common-α** `Pfa_GO≤Pfa_CA≤Pfa_SO` ordering invariant (NOT per-variant
      calibrated — would pass by construction; the slice-2 atol-not-rtol≈0 trap); **MC
      Pfa-maintenance** (CA at N_p∈{1,5}, GO/SO/OS at N_p=1) drawing real Gamma cells through the
      same estimator + asserting design Pfa in the Wilson 4σ band — this is what validates the
      SO/GO/Beta *forward* forms (round-trips only prove self-inversion; advisor); the public
      `cfar_threshold ≈ α·estimate` convention pin; edge cells finite+positive+no-OOB at the
      array ends + a sub-window-length profile; invalid-arg rejections (N_p>1 for GO/SO/OS, odd N
      for GO/SO halves, odd `n_train`, bad variant). Slice-1/2 byte-identical (append-only — no
      existing `detection.jl` symbol changed; `test_determinism` green).
- [x] 3. `radar.jl`: range-power profile build + `:cfar` dispatch. **DONE & green (782 tests).**
      `observe!` now dispatches on `haskey(w.fidelity,:cfar)`: `_observe_point!` is the slice-1/2
      body moved **verbatim** (a no-`:cfar` scenario stays byte-identical — the slice-1 `_sample_z`
      golden + the byte-identical frame-trace test still green prove it); `_observe_cfar!` builds
      the new core object — a range-power profile of `n_cells` cells, `Δr=c/2B`. **Cell model (named
      approximation):** compute the per-cell linear power DETERMINISTICALLY first (noise floor 1 +
      `:clutter` band(s) `db2lin(cnr_db)` over `[R, R+extent]` on the slant axis + each target's
      `_target_snr` — so the profile composes with `:propagation` lobing AND the below-horizon
      mask), THEN draw each cell as a fast-Rayleigh square-law `z_i=Σ_p|x_p|²`, `x_p~CN(0,power_i)`,
      via `_draw_profile!` (**2·N_p randn/cell, cell-by-cell** — the ONE RNG call of a look). Noise/
      clutter cells stay exponential at N_p=1 (CA/OS closed forms hold in the homogeneous interior);
      the target folds into the variance (SW2-like in the profile) while the scalar `pd` readout
      stays the analytic Pd-at-design-`pfa` for the configured `swerling` (the plan's explicit
      definition — a reference readout, not the cell's CFAR detection prob). The **draw count is
      always 2·N_p·N_cells, independent of rung AND target position** — that invariance is what keeps
      a mid-run rung toggle bit-identical (`cfar_scan` is pure; the rung only swaps the rule).
      `const CFAR_MODES = CFAR_VARIANTS` (references detection.jl, no re-list — the `PROPAGATION_MODES`
      drift lesson); `const LIVE_FIDELITY_MODES = (propagation=…, cfar=…)` is the per-key source of
      truth the server's `set_fidelity` validates against. **Advisor catches baked in:** (a) `n_train`/
      `n_guard` are LIVE sliders, so `_observe_cfar!` **clamps at the consumer** (`n_train=max(2,2*(raw÷2))`,
      `n_guard=max(0,raw)`) — a slider dragged to an odd N can't throw in `cfar_scan`→`tick!`→kill the
      session (the slice-2 watch-item generalised: a live knob can't crash a tick); (b) NO early-return
      on an empty target list — a clutter-only profile still draws + ships (a core sandbox view);
      (c) `n_cells≥1` + even `n_train` validated **at LOAD** (`_validate_cfar`, the n_pulses pattern) so
      the handshake range-axis / first tick can't `KeyError` inside the session's IO-only try.
      Telemetry: per-cell `profile_db`/`threshold_db`/`detections` (floored via `_snr_db_wire` — a null
      cell never ships `-Inf`) **+ the slice-1/2 scalars kept** for the strongest target; `:detection`
      events gain `:cell`/`:range`, a target hit also carries `:of`, a clutter/noise false alarm carries
      NONE (the lesson surface, explicit). Static `range_axis_m`/`dr_m`/`n_cells` ship in
      `scenario_frame` (`_cfar_axis_info`, handshake-once). `scenario.jl`: `:clutter` kind
      (`comp[:extent_m,:cnr_db]`, no subsystem) + optional `n_cells`/`range_start_m`/`n_train`/`n_guard`
      read into the radar comp (absent for slice-1/2 radars, keeping their bag clean). `server.jl`:
      `set_fidelity` → per-key table + **rejects INTRODUCING `:cfar`** when absent (point→profile
      draw-topology flip would desync replay; changing `:propagation`'s value stays safe).
      `protocol.jl`: `state_frame` docstring flags the `string→number/bool`→`+array` widening (a named
      extension, like slice-2's `set_fidelity`). Tests (+62): `test_radar.jl` (well-formed+JSON
      round-trip arrays, rung-selects-rule-not-draw [rng lockstep, detections differ], **fixed lights
      the clutter-band INTERIOR while ca holds it** — the interior not the edge, advisor catch — 41 vs 0,
      clutter-only ships, a `_draw_profile!` **draw golden**, **event schema: `:of`/`:cell`/`:range` with
      the right index through the full observe path; clutter FA has no `:of`**, unknown rung errors);
      `test_determinism.jl` (mid-run `cfar` toggle: two same-seed runs identical + toggle-vs-no-toggle
      same rng end-state but different detections — the sharp draw-count-invariance test);
      `test_server.jl` (per-key `set_fidelity` cfar write/reject + reject-introducing-`:cfar` +
      propagation still works, range-axis handshake, **live odd-`n_train` set_param→tick survives the
      clamp**); `test_scenario.jl` (`:cfar`+`:clutter` loads, missing `n_cells` / odd `n_train` rejected
      at load). Slice-1/2 byte-identical (720 prior tests green untouched).
- [x] 4. `scenarios/slice3_cfar.yaml` + the Godot range-power view. **DONE & green (798 tests).**
      STATIC scene (all on +X, z=0 → slant=ground=cell axis; each look redraws the noise, the
      geometry holds): 50 kW X-band, B=1 MHz → Δr=149.9 m, n_cells=300 (0–44.8 km), pfa=1e-3,
      n_train=16/n_guard=2, default `:ca`. A 20 dB clutter band at 10–16 km (cells 68–108) + two
      close targets at ~25 km — tgtA (victim, 18.2 dB, cell 168) & tgtB (interferer, 31.6 dB, cell
      173, 5 cells away → inside tgtA's training window). `propagation` deliberately ABSENT (defaults
      free_space) — two_ray nulls would muddy the lesson (one lesson per scenario; advisor). Knobs =
      the LIVE sliders `n_train`/`n_guard`/`pfa` (cfar is a fidelity, toggled by the button). Tuned
      EMPIRICALLY with a throwaway probe first (advisor: link-budget SNR decides masking; don't
      hand-derive), numbers pinned into the verifier. Godot `Sandbox.gd` is now ADAPTIVE: handshake
      `range_axis_m` presence flips `_mode` spatial→cfar (advisor: one scene avoids `godot --path`
      mis-opening against a CFAR server); the two render paths share NO state (spatial `_draw` →
      `_draw_spatial`, untouched). cfar `_draw` plots range×power-dB + the threshold curve (**from the
      shipped `threshold_db`; α NEVER recomputed in GDScript**) + a marker per detected cell; the
      shared fidelity button becomes the rung cycler (`fixed→ca→go→so→os`, guarded disconnect of
      `_on_prop_pressed`); `_update_readout` skips Array telemetry (would have crashed on the arrays).
      `net/slice3_verify.gd`: handshake axis + finite arrays; the rung selects the RULE not the draw —
      `reset` (seed 3, t=0) BEFORE `set_fidelity` replays an IDENTICAL noise sequence per rung (the
      draw is rung-invariant, only on look ticks). Over 80 looks/rung (deterministic): all five reach
      the SAME final t=4.0 (bit-identical); `fixed` lights the clutter band (**2993 FA**) vs `ca`/`go`
      (**31/7**); tgtA **masked under ca (9)** resolves under **so/os (61/60)**, tgtB never masked
      (73–79). Drains ALL frames accumulating one-shot `:detection` EVENTS (target hit→`:of`, clutter
      FA→`:cell`/`:range` only), NOT the republished per-frame array (would multi-count; advisor).
      `S3V OK`, server `DONE`, exit 0. Toggle/slider UI path: `net/slice3_ui_test.gd` (`S3UI OK`: mock
      client + fake cfar handshake → rung cycler walks+wraps, badge/button track, N_train slider sends
      `set_param`, reset resyncs). `Sandbox.tscn` smoke-loaded headless against BOTH a slice2 (spatial)
      AND the slice3 (cfar) server (no GDScript errors, server `DONE` ⇒ scene connected on each
      branch). `test_scenario.jl` slice3 loader assertion (parses, `:cfar` default, clutter entity,
      targets on-grid + within `n_guard+n_train` cells, clutter near-edge in interior, cfar not a
      knob). The cfar `_draw` pixel branch isn't run headless (windowed look, same gap as slice-1/2;
      numbers wire-verified). **(stretch, DEFERRED)** `clients/notebooks/slice3_cfar.jl` (CFAR diagram).

## Context / landmarks
- **The seam is partly pre-built.** `set_fidelity` (`server.jl:145`) already exists from
  slice 2 — generalise its single `:propagation` check to a per-key table. The §12 badge
  (`scenario_frame`, `server.jl:90`) already ships `world.fidelity`. `state_frame`
  (`protocol.jl:67`) is generic over telemetry values — arrays flow without a builder
  change. `_snr_db_wire`/`_SNR_DB_FLOOR` (radar.jl:85) already floor Inf/NaN — reuse for
  the profile dB.
- **`_target_snr(prop, rp, radar, tgt)`** (radar.jl:99) is the composition point: call it
  per target to get the cell power, so `:cfar` rides on top of `:propagation` unchanged.
- **Frame convention:** `pos = [downrange/x, y, altitude/z]`; range = 3-D slant (already
  `_range`). A target's range cell index = `round((R − R_start)/Δr)`.
- **Validation shape:** integration closed forms tested at the point level; CFAR closed
  forms at `N_p=1`; the combined path by MC Pfa-maintenance (the analytic-vs-MC pattern).

## Watch-items (gotchas to bake in)
- **Draw-stream desync (the slice-3 determinism trap).** Do NOT let any live `cfar` rung
  fall back to the legacy point detector — it draws a different randn count and a mid-run
  toggle would desync replay (`test_determinism` mid-run-toggle fails). Profile always
  drawn within a CFAR scenario; rung changes only the thresholding rule. The same trap at
  the **command layer**: `set_fidelity` must reject *introducing* `:cfar` on a scenario
  that started without it (it would flip legacy-point ↔ profile draw topology). Pin both
  with tests.
- **`-Inf`/`NaN` on the wire.** A null/clutter-free/masked cell → `lin2db(0) = -Inf`.
  Floor every profile + threshold dB through `_snr_db_wire` (the slice-1 `%g` / slice-2
  null watch-item, now over a whole array). Test an all-empty cell explicitly.
- **CFAR window edges.** The first/last `N/2+G` cells have a truncated window — clamp /
  shrink the window or mark them invalid; never index out of bounds. Test the array ends.
- **Gamma-cell ≠ exponential-cell.** The CA `(1+α/N)^(−N)` / OS product closed forms are
  for `N_p=1` (exponential) cells. Do NOT assert them at `N_p>1` (Gamma cells) — use MC
  Pfa-maintenance there. Keep the closed-form tests on their clean turf.
- **Telemetry array contract.** Flag the `string→number/bool`→`+array` widening in the
  `state_frame` docstring (a named extension, like slice-2's `set_fidelity`). Keep
  `N_cells` modest (~300 at `Δr=c/2B`, B=1 MHz → 150 m); localhost bandwidth is fine.
- **Threshold curve is core output.** The CFAR threshold per cell is shipped from
  detection.jl — never recomputed in GDScript. The client renders the array it's handed
  (HANDOFF §1: physics in the core, the client is a thin renderer).
- **`swerling`/`n_pulses` are not live sliders.** They change the per-look draw count, so
  a mid-run `set_param` on them would desync (true since slice 1). Keep them out of the
  `knobs` list; the live toggle is `cfar` (rule only, draw-count-invariant).
- **Name every approximation** in the docstrings (non-coherent integration, elevated-mean
  exponential clutter, 1-D range-only CFAR window). HANDOFF §1: no hidden approximations.
