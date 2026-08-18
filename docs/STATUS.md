# EWSim — as-built status ledger (per-slice completion notes)

This is the detailed, gate-by-gate as-built record for every completed slice —
moved verbatim out of `CLAUDE.md` to keep the always-loaded design doc lean.
`CLAUDE.md` carries the short status + distilled conventions; reach here for
slice archaeology (exact numbers, test names, watch-items, advisor-catches).
Pre-implementation design plans live in `docs/plans/sliceN.md`.

---

## Slice 2 — propagation fidelity — two_ray lobing + horizon mask

Slice 2 (propagation fidelity — `two_ray`) — **COMPLETE. Steps 1–3 + coverage-diagram stretch
done & green** (420 tests).
Step 1: `rf.jl` two-ray physics behind the `propagation` knob. `two_ray_phase` (Δφ =
4π·h_r·h_t/(λ·R_g), flat-earth small-grazing path-diff), `two_ray_factor4` (F⁴ =
(1+ρ²+2ρ·cosΔφ)²; ρ=−1 → 16·sin⁴(Δφ/2), peak +12.04 dB, exact nulls; ρ=0 → 1 ≡ free space),
`snr_two_ray(rp, rcs, slant_m; h_r, h_t, ground_m, refl=-1.0)` = `snr_freespace(slant)`·F⁴
(link budget on **slant** range, multipath modulation on **ground** range+heights),
`snr_db_two_ray`, `horizon_range(h_r, h_t)` (4/3-Earth, √(2·4/3·R_e)·(√h_r+√h_t) ≈
4121.8·(√h_r+√h_t)). **rf.jl stays pure phenomenology — NO horizon gating here**; the
below-horizon policy (finite floor / `visible:false`, never −Inf/NaN) is step-2 radar.jl,
and radar.jl must call `snr_two_ray` (not re-apply F⁴). All three approximations named in
docstrings (HANDOFF §1). `test_propagation.jl` (20 closed-form tests, deterministic — no
MC bands): lobe peak ratio=16, null→0 (explicit `atol` — `≈0` rtol-only always passes
trivially/fails), small-grazing R⁻⁸ envelope (−24.08 dB/octave, double slant+ground),
ρ=0 ≡ free-space exactly, h→0 perpetual-null pin (NOT a throw — a fly-by may cross z=0
and must not crash the live sim), horizon coeff recomputed at full precision + additive in
√h, `ground_m>0` guard (the sole Inf/NaN input).
Step 2 (gate 2 — knob switches live): `radar.jl` `observe!` dispatches on
`get(w.fidelity,:propagation,:free_space)` via `_target_snr(prop, rp, radar, tgt) →
(snr, visible)`. two_ray decomposes geometry — link budget on **slant** `_range`,
multipath phase + 4/3-Earth horizon on **ground** `_ground_range` — masks a below-horizon
target to SNR 0 + `visible:false` (the below-horizon **policy** lives in radar.jl, NOT
rf.jl); clamps `h_r,h_t ≥ 0` (a fly-by below z=0 can't crash `horizon_range`'s sqrt) and
treats ground→0 (overhead, Δφ→∞) as visible free space. `_snr_db_wire` floors the
telemetry `snr_db` to `_SNR_DB_FLOOR=-120` so a **null** (F⁴=0, even above the horizon) or
a mask never ships `-Inf` to JSON (the watch-item, same class as slice-1's `%g`). New
telemetry key `"<id>.visible"`. **`detect_once` stays UNCONDITIONAL per look** — `_sample_z`
draws the same randn count regardless of SNR, so free_space/two_ray stay in RNG lockstep
and toggling fidelity changes only the detection booleans + telemetry, never the draw
sequence; gating the draw on snr/visible would desync replay. `PROPAGATION_MODES =
(:free_space,:two_ray)` in radar.jl is the **single source of truth** shared by the
dispatch's unknown-rung error AND the server's `set_fidelity` validation. `set_fidelity`
(`handle_command!`, server.jl) is a flagged §5 EXTENSION (mirrors `scenario_frame`):
`{type:set_fidelity,key:propagation,value:two_ray}` → writes `w.fidelity`, but VALIDATES
first (key===:propagation, value ∈ PROPAGATION_MODES) — a bad value reaching `observe!`
would throw inside `tick!`, and the session's IO/EOF-only catch would drop the connection.
Tests: `test_radar.jl` (6 contracts — default==free_space, two_ray==`snr_two_ray`
closed-form on a slant≠ground geom, below-horizon mask→floor+visible:false, null JSON
round-trip stays finite, **draw-stream parity across fidelities**, unknown-rung errors);
`test_determinism.jl` +mid-run toggle replays bit-identical; `test_server.jl` +`set_fidelity`
write/reject.
Step 3 (gate 3 — visible live): `scenarios/slice2_tworay.yaml` — a 100 m-altitude target
closing at 450 m/s from 70 km on a 30 m-mast 50 kW radar. The 4/3-Earth horizon is 63.8 km,
so the target opens BELOW it (dark, `visible:false`) for ~14 s, then crosses into LOS and
sweeps a dramatic lobe/null string (Pd 0↔~1; F⁴ −62 dB nulls → +12 dB peaks) as Δφ sweeps.
`propagation` is NOT a slider knob (it's a fidelity, toggled by the button) — knobs stay
`pt_w` (bracketed 1k–200k around the 50 kW default, NOT slice-1's 5k) + `rcs_m2`. Godot
`Sandbox.gd`: a `prop:` toggle button sends `set_fidelity`; the §12 badge + button label
re-render from a **local** fidelity copy, because the server applies `set_fidelity`/`reset`
silently (no new handshake — only `load_scenario` re-handshakes), so the client owns the
displayed state and resyncs to the scenario default on `reset` (which reloads the YAML →
two_ray). The target renders dark "(below horizon)" off the `<id>.visible` flag — NOT absence
of `:detection` events (the watch-item: a masked target still false-alarms at `pfa`, so "no
blip" ≠ "not visible"). `net/slice2_verify.gd` (headless, the `sandbox_verify.gd` analog)
drives the real server on this scenario: handshake fidelity is two_ray; the far target is
`visible:false` under two_ray but `visible:true` under free_space (the mask is the **model**,
not the geometry); step to T=28.0 s (target ~57 km, within horizon, mid-lobe) under two_ray,
then **`reset` (→ YAML two_ray) BEFORE `set_fidelity` free_space** (reset would clobber the
toggle — `_reload!` re-parses fidelity), replay to the SAME T — `t` bit-identical, SNR flips
**15.10 → 7.70 dB (Δ=7.40)**. Verifier mechanics: drain to the LAST frame of each `step`
burst (`t ≥ T−½dt`, not the first), `_inbox.clear()` before the replay, assert sign-agnostic
`|Δ|>2 dB` at a non-floored sample. Proven green end-to-end (`S2V OK`, exit 0) + `Sandbox.tscn`
smoke-loaded headless (no GDScript errors, server `DONE` ⇒ scene connected — catches parse
bugs the SimClient-only verifier can't). Because the verifier drives SimClient (not the
scene), the toggle BUTTON path (`_on_prop_pressed` + badge/button re-render + reset resync)
has its own headless test `net/sandbox_ui_test.gd` (`SUI OK`: mock client + fake handshake →
asserts the badge flips two_ray↔free_space, the `set_fidelity` frame ships, reset resyncs to
default). `_draw`'s below-horizon dark-target PIXEL branch isn't run headless (needs a
windowed look, like slice-1's dated visual check); the `visible` flag it reads IS wire-verified
by `slice2_verify.gd`. `test_scenario.jl` gains a slice2 loader assertion
(parses, two_ray default, no `propagation` knob, target starts beyond `horizon_range`) so a
malformed YAML fails as a clear test, not a confusing Godot-launch timeout.

Run the slice-2 showcase: `julia --project=core tools/server.jl scenarios/slice2_tworay.yaml`,
then launch Godot on `clients/godot` (toggle `prop:` to watch lobing/horizon appear & vanish).
Re-run the step-3 proof headless: start that server, then `godot --headless --path clients/godot
--script res://net/slice2_verify.gd` (exit 0 = pass; serves one client then exits). The toggle
UI test needs NO server: `godot --headless --path clients/godot --script res://net/sandbox_ui_test.gd`.

Coverage-diagram stretch (the slice's offline lesson, no client/server): `batch.jl`
`kind=:coverage` sweeps SNR (floored dB) over a ground-range × altitude grid two ways —
free_space + two_ray (with the 4/3-Earth horizon mask) — into `(n_range, n_alt, 2)`. Pure
`coverage_grid` (re-derives radar.jl's below-horizon policy for the clean grid; calls the same
rf.jl primitives + the SAME `_snr_db_wire` floor as the wire, so a null/mask reads
`_SNR_DB_FLOOR`, never `-Inf` in the artifact); `load_coverage` reader; `_run_coverage` is an
**additive** `elseif` so the ROC path stays byte-identical. NO RNG (closed form) → can't desync
a live trace. `test_batch.jl` pins both planes **cell-for-cell against the live `_target_snr`
oracle** (NOT a hand recompute — that would replicate any slant/ground decomposition slip; the
oracle is the actual sandbox path, so the diagram provably matches the sandbox AND a transpose
dies in the same loop) + descriptor↔file, Inf/NaN-free, below-horizon corner floors while
free_space stays finite (mask is the model not the geometry), `w.rng` untouched, rcs override.
Generate: `pwsh tools/julia.ps1 --project=core tools/run_coverage.jl` → `shared/coverage_radar1.bin`
(NOT committed — 3 MB sweep; `.gitignore` stages only the tiny ROC, so regen on a fresh clone).
View: Pluto `clients/notebooks/slice2_coverage.jl` (free_space vs two_ray heatmaps + analytic
horizon-curve overlay from the exported `horizon_range(0,1)` + an F⁴=two_ray−free_space panel).
**Grid default 10–80 km × 0–600 m / 400×480**: a 30 m X-band mast packs ~940 lobes over the
hemisphere, so high elevation angles (short range × high altitude) alias to moiré — this
low-elevation window keeps ~2–4 cells/lobe and centres the 100 m target in the lobing band.
Visually confirmed 2026-06-21 (headless PNG render of the notebook cells: clean lobe fan, dark
nulls, cyan horizon curve bounding the masked wedge; no headless *visual* test — same gap as
slice-1 `_draw`, numbers pinned, picture eyeballed).

## Slice 3 — CFAR sandbox + N-pulse integration

**Slice 3 — CFAR sandbox (+ pulse integration)** (HANDOFF §10 item 3) — **Steps 1–4 done & green (798
tests); wire + UI machine-verified AND the cfar range-power `_draw` now VISUALLY CONFIRMED
(2026-06-22). The "visible payoff" pixel path was the last open item; closed by a captured WINDOWED
render (the agent CAN render `_draw` from the tool shell — see [[ewsim-godot-headless]]): a throwaway
shot harness pointed `run/main_scene` at itself, instantiated `Sandbox.tscn` against the live slice3
server, and saved `get_viewport().get_texture().get_image()` to PNGs under three rungs. Confirmed:
`ca` forms threshold "towers" over the close pair → tgtA masked (the strong tgtB is the lone marker)
/ `os` FLATTENS that threshold over the pair (the unmasking signature) / `fixed` flat threshold →
clutter-band false-alarm storm (~40 markers); the threshold curve is the shipped core output,
axes/legend/badge render. (The per-look marker count is noisy — tgtA's statistical resolution under
so/os is proven by `slice3_verify.gd` (61/60 of 80 looks), NOT by a single frame; the frames prove the
threshold-SHAPE contrast.) (One cosmetic fix landed: the
dB y-axis labels moved to the RIGHT gutter — they collided with the left slider panel.) Pluto CFAR
diagram still deferred (stretch).** Planned in `docs/plans/slice3.md`
(4 staged steps: pulse integration + Swerling 0–4 → CFAR primitives → radar.jl profile/dispatch +
`:clutter` + per-key `set_fidelity` → Godot range-power view).
Step 1 (gate 1 — integration + Swerling 0–4 green): `detection.jl` generalised single-pulse →
**N-pulse non-coherent integration** (z = Σ|xᵢ|², noise-only `Gamma(N_p,1)`). `detection_threshold(
pfa, n_pulses=1)`: `N_p=1` → `−log(pfa)` **float-exact** (slice-1/2 byte-identity), else bisect the
monotone Erlang survival `Pfa(T)=e^{−T}Σ_{k<N_p}T^k/k!`. `pd_analytic(snr,pfa; swerling∈0:4,
n_pulses=1)` — five finite-sum forms (all first-principles-derived, advisor-verified, each reducing
to slice-1 at N_p=1 and →pfa as snr→0): SW0 Poisson-mixture `Σ poisson(k;N·snr)·poisscdf(N−1+k;T)`,
SW1 geometric weights (ρ=N·snr/(1+N·snr)), SW2 `ErlangSurv(T/(1+snr),N_p)`, SW3 NB-r2 weights
(μ=N·snr/(2+N·snr)), SW4 binomial-mixture-of-Erlangs (v=1+snr/2, from the per-pulse MGF partial
fraction). SW0/1/3 share one **saturation-aware** accumulator — once the inner `poisscdf`≈1 the
residual is the leftover weight mass, so it converges in ~T+O(√T) terms even as ρ,μ→1 at high N·SNR
(the slice-1 Poisson-sized cap would under-truncate that tail — advisor catch). The MC sampler
(`_sample_z`/`detect_once`/`pd_montecarlo`) integrates N_p square-law draws with the slow (one
shared amplitude: SW0/1/3) vs fast (fresh per pulse: SW2/4) pattern; 4-DOF amplitude
`|a|²=(snr/4)·χ²₄` (phase irrelevant under circular noise). **N_p=1 draws are byte-identical to
slice 1** — same draw order (noise then signal), same `sfluc=√(snr/2)` spelling (NOT `√snr·√½`,
1 ULP apart — the bug the golden caught), direct `(sI+nI)²+(sQ+nQ)²` for the single pulse (the
accumulator runs only for N_p>1). `test_detection.jl`: threshold round-trip, all 5 Swerling in the
MC Wilson band at N_p=8 (incl. a 15 dB saturation-exposer), SW2≠SW1 / SW4≠SW3 at N_p>1, N_p=1
collapses 2→1 & 4→3, an **absolute golden** pinning `_sample_z`'s N_p=1 bits (`test_determinism`
only compares run-to-run, so it can't catch a draw-order regression — advisor catch; it caught two
real 1-ULP desyncs), and the **Swerling fluctuation-loss ordering** as an external anchor for the
otherwise self-validated-only SW3/SW4 (SW0>SW3>SW1 at high Pd, reverses at low SNR — advisor catch).
`scenario.jl`: `n_pulses≥1` (was `==1`), stored in `comp[:n_pulses]`. `radar.jl` threads `n_pulses`
through `observe!` (default 1 via `get` ⇒ slice-1/2 byte-identical; a loaded `n_pulses` now fires).
Step 2 (gate 2 — CFAR primitives green): `detection.jl` CFAR adaptive thresholding (append-only —
no existing symbol changed, so slice-1/2 stay byte-identical). `cfar_alpha(variant, n_train, pfa;
n_pulses=1, k=⌈0.75N⌋)` → the multiplier α with `T = α·(noise estimate)` (**mean convention** — the
estimate is the MEAN of N training cells, pinned across alpha/threshold/MC, the advisor's
sum-vs-mean bug-magnet); `cfar_threshold(profile, cut; …)` (one CUT) + vectorised `cfar_scan(profile;
…) → (threshold, detections)` work in **LINEAR power** and are **PURE (no RNG)** — the profile DRAW
is step-3 radar.jl, so a scan can't desync a trace. `CFAR_VARIANTS=(:fixed,:ca,:go,:so,:os)` (step-3
`CFAR_MODES` will **reference** this, not re-list — advisor drift catch, the `PROPAGATION_MODES`
lesson). Closed forms via forward `_cfar_pfa` inverted by `_bisect_alpha` (same idiom as
`detection_threshold`, **no SpecialFunctions**): CA exponential `(1+α/N)^{−N}` (N_p=1, direct
`α=N(pfa^{−1/N}−1)`) **and gamma N_p>1 EXACT via the Beta tail** (CUT~Gamma(N_p,1), train
sum~Gamma(N·N_p,1), ratio crosses Beta(N_p,N·N_p) at `w=α/(N+α)`; `_beta_surv_int` = regularized
incomplete Beta as a finite binomial sum — **advisor: drop the heuristic-α, this is exact +
dependency-free**, collapses to the N_p=1 CA form). OS `∏_{i<k}(N−i)/(N−i+α)` (Rohling); SO
`2Σ_{j<M}C(M−1+j,j)(2+α/M)^{−(M+j)}` (M=N/2, from E[e^{−s·min}] of two Gamma(M,1) halves); GO
`2(1+α/M)^{−M}−Pfa_SO` (max+min identity). **GO/SO/OS are N_p=1 only** (no finite-sum inverse over
Gamma cells — N_p>1 rejected); the integrated path is **CA-only + MC-validated** (the plan's "N_p>1
by MC"). Edge cells shrink the training set & reuse the interior α (Pfa held only in the interior;
global-mean fallback when the window fully truncates — **never OOB**). Named approximations
(HANDOFF §1): 1-D range-only window, exact-α-for-exponential-cells, interior-only edge Pfa.
`test_cfar.jl` (174 tests): CA closed form + round-trip + the `N→∞→−ln(pfa)` monotone CFAR-loss
anchor; OS product vs independent recompute + `k=1` closed value; SO/GO round-trip + the `N=2/M=1`
hand value `2/(2+α)`; the **common-α** `Pfa_GO≤Pfa_CA≤Pfa_SO` ordering invariant (NOT per-variant
calibrated — would pass by construction, the slice-2 atol-not-rtol≈0 trap); **MC Pfa-maintenance**
(CA at N_p∈{1,5}, GO/SO/OS at N_p=1, fixed seeds → deterministic) drawing real Gamma cells through
the same estimator + asserting design Pfa in the Wilson 4σ band — **this is what validates the
SO/GO/Beta forward forms** (round-trips only prove self-inversion — advisor); the public
`cfar_threshold ≈ α·estimate` convention pin; edge cells finite+positive+no-OOB at the array ends
+ a sub-window profile; invalid-arg rejects (N_p>1 for GO/SO/OS, odd N for GO/SO halves, odd
`n_train`, bad variant).
Step 3 (gate 3 — knob switches live): `radar.jl` `observe!` dispatches on `haskey(w.fidelity,:cfar)`.
`_observe_point!` is the slice-1/2 body moved **verbatim** (a no-`:cfar` scenario stays byte-identical
— the slice-1 `_sample_z` golden + byte-identical frame-trace tests still green prove the move).
`_observe_cfar!` builds the slice's new core object — a range-power profile of `n_cells` cells
(`Δr=c/2B`). **Cell model** (named approximation): compute per-cell linear power DETERMINISTICALLY
first (noise floor 1 + `:clutter` band(s) `db2lin(cnr_db)` over `[R,R+extent]` on the slant axis +
each target's `_target_snr` ⇒ composes with `:propagation` lobing AND the below-horizon mask), THEN
draw each cell fast-Rayleigh `z_i=Σ_p|x_p|²`, `x_p~CN(0,power_i)` via `_draw_profile!` (**2·N_p
randn/cell, cell-by-cell — the ONE RNG call of a look**). Noise/clutter cells stay exponential at
N_p=1 (CA/OS closed forms hold in the homogeneous interior); the target folds into the variance
(SW2-like in the profile) while the scalar `pd` readout stays analytic Pd-at-design-`pfa` for the
configured `swerling` (plan's explicit definition — a reference readout, not the cell's CFAR Pd). The
**draw count is ALWAYS 2·N_p·N_cells, independent of rung AND target position** — that invariance is
why a mid-run rung toggle is bit-identical (`cfar_scan` is pure; the rung only swaps the rule).
`const CFAR_MODES = CFAR_VARIANTS` (references detection.jl, no re-list); `const LIVE_FIDELITY_MODES
= (propagation=…, cfar=…)` is the per-key truth the server's `set_fidelity` validates. **Advisor
catches:** (a) `n_train`/`n_guard` are LIVE sliders ⇒ `_observe_cfar!` **clamps at the consumer**
(`max(2,2*(raw÷2))` / `max(0,raw)`) so a slider to an odd N can't throw in `cfar_scan`→`tick!`→kill
the session (slice-2 watch-item: a live knob can't crash a tick); (b) NO early-return on an empty
target list — a clutter-only profile still draws + ships; (c) `n_cells≥1` + even `n_train` validated
**at LOAD** (`_validate_cfar`, the n_pulses pattern) so the handshake range-axis / first tick can't
`KeyError` inside the session's IO-only try. Telemetry: per-cell `profile_db`/`threshold_db`/
`detections` (floored via `_snr_db_wire`) **+ the slice-1/2 scalars kept** for the strongest target;
`:detection` events gain `:cell`/`:range`, a target hit also carries `:of`, a clutter/noise false
alarm carries NONE (the lesson surface). Static `range_axis_m`/`dr_m`/`n_cells` ship in
`scenario_frame` (`_cfar_axis_info`, handshake-once). `scenario.jl`: `:clutter` kind
(`comp[:extent_m,:cnr_db]`, no subsystem) + optional CFAR radar params read into comp. `server.jl`:
`set_fidelity` → per-key table + **rejects INTRODUCING `:cfar`** when absent (point→profile draw-flip
desyncs replay; changing `:propagation` stays safe). `protocol.jl`: `state_frame` docstring flags the
`string→number/bool`→`+array` telemetry widening. Tests (+62): `test_radar.jl` (well-formed+JSON
round-trip arrays; rung-selects-rule-not-draw [rng lockstep, detections differ]; **fixed lights the
clutter-band INTERIOR while ca holds it** — interior not edge, advisor catch — 41 vs 0; clutter-only
ships; a `_draw_profile!` **draw golden**; **event schema `:of`/`:cell`/`:range` with the right index
through the full observe path, clutter FA has no `:of`**; unknown rung errors); `test_determinism.jl`
(mid-run `cfar` toggle: same-seed identical + toggle-vs-no-toggle same rng end-state, different
detections — the sharp draw-count-invariance test); `test_server.jl` (per-key `set_fidelity` cfar
write/reject + reject-introducing + propagation still works; range-axis handshake; **live odd-`n_train`
set_param→tick survives the clamp**); `test_scenario.jl` (`:cfar`+`:clutter` loads; missing `n_cells`
/ odd `n_train` rejected at load).
Step 4 (gate 4 — visible live): `scenarios/slice3_cfar.yaml` — a STATIC range-power scene (everything
on +X, z=0, so slant=ground=cell axis; each look redraws the noise, the geometry holds) built to
expose all three lessons at once. Radar: 50 kW X-band, B=1 MHz → Δr=149.9 m, n_cells=300 (0–44.8 km),
pfa=1e-3, n_train=16/n_guard=2, default rung `:ca`. A 20 dB clutter band at 10–16 km (cells 68–108)
+ two close targets at ~25 km: tgtA (victim, 18.2 dB, cell 168) and tgtB (interferer, 31.6 dB, cell
173 — 5 cells away, inside tgtA's training window). `propagation` is deliberately ABSENT (defaults
free_space): two_ray nulls would inject zeros into arbitrary cells and muddy the lesson — **one
lesson per scenario** (two_ray-composition is already pinned by test_radar.jl; advisor catch). Knobs
are the LIVE CFAR sliders `n_train`/`n_guard`/`pfa` (cfar is a fidelity, toggled by the button, NOT a
slider). Tuned EMPIRICALLY first with a throwaway probe (advisor: the link-budget SNR decides the
masking; don't hand-derive) — the numbers are pinned into the verifier as comments.

Godot `Sandbox.gd` is now **adaptive**: the handshake's `range_axis_m` presence flips `_mode`
spatial→cfar (advisor: a separate scene would mis-open `godot --path` against a CFAR server; one
adaptive scene avoids the footgun). The two render paths share NO state and never interleave — the
slice-1/2 spatial view is untouched (its `_draw` → `_draw_spatial`; sandbox_ui_test + the spatial
smoke-load stay green). The cfar `_draw` plots range×power-dB: the drawn profile, the CFAR threshold
curve (**CORE output — drawn from the shipped `threshold_db`, α NEVER recomputed in GDScript**, the
central invariant), and a marker per detected cell. The shared fidelity button becomes the cfar rung
CYCLER (`fixed→ca→go→so→os→fixed`, `set_fidelity`) — the binary prop toggle's `_on_prop_pressed` is
swapped for `_on_cfar_pressed` (guarded disconnect so the headless UI test doesn't error); the §12
badge + button re-render from the local fidelity copy and resync on reset, exactly the slice-2
pattern. `_update_readout` now **skips Array telemetry** (the profile/threshold/detections arrays
render in `_draw`, not as text — the watch-item: it would have `float()`-crashed on the arrays).

`net/slice3_verify.gd` (headless, the slice2_verify analog) drives the real server on this scenario:
the handshake ships the static range axis (`range_axis_m` len n_cells, `dr_m`, `n_cells`) + `cfar:ca`
default; every state frame carries finite `profile_db`/`threshold_db`/`detections` arrays. The core
proof — **the rung selects the RULE, not the draw**: the profile draw is rung-invariant and happens
only on look ticks, so `reset` (held seed 3, t=0) **before** `set_fidelity` replays an IDENTICAL noise
sequence per rung — a clean controlled experiment. Measured over 80 looks/rung (deterministic, seed
3): all five rungs reach the SAME final t=4.0 (bit-identical replay); `fixed` lights the clutter band
(**2993 FA events**) vs `ca`/`go` (**31/7** — tracked, Pfa held); tgtA is **masked under ca (9
detections)** but **resolves under so/os (61/60)** while the interferer tgtB stays detected
everywhere (73–79). Drains ALL frames per burst accumulating one-shot `:detection` EVENTS (a target
hit carries `:of`, a clutter FA carries only `:cell`/`:range` — filtered by `of`/`range`); NOT the
per-frame detections array, which is republished between looks and would multi-count (advisor catch).
Proven green end-to-end (`S3V OK`, server `DONE`, exit 0). The toggle/slider UI path (which the
SimClient-driven verifier can't press) has its own headless `net/slice3_ui_test.gd` (`S3UI OK`: mock
client + fake cfar handshake → the rung cycler walks `fixed→ca→go→so→os` and wraps, badge/button
track it, the N_train slider sends `set_param`, reset resyncs to ca). `Sandbox.tscn` smoke-loaded
headless against BOTH a slice2 (spatial) AND the slice3 (cfar) server (no GDScript errors, server
`DONE` ⇒ the scene connected on each branch — catches CFAR-branch parse bugs the spatial verifiers
can't). `test_scenario.jl` gains a slice3 loader assertion (parses, `:cfar` default, clutter entity,
both targets on-grid + within `n_guard+n_train` cells of each other, clutter near-edge in the
interior, cfar not a knob). The cfar `_draw` PIXEL branch isn't run headless (Godot skips `_draw`
headless), so it was **visually confirmed 2026-06-22 via a captured windowed render** of `Sandbox.tscn`
against the live slice3 server (a throwaway shot harness: temporarily point `run/main_scene` at a
wrapper scene, instantiate `Sandbox.tscn`, let it connect+render realtime, then
`get_viewport().get_texture().get_image().save_png` under three rungs — `ca`/`os`/`fixed` — and Read
the PNGs). The three rungs render the lesson: `ca` threshold towers over the close pair → tgtA masked (tgtB the
lone marker), `os` threshold FLATTENS over the pair (the unmasking signature), `fixed` flat threshold
+ ~40 clutter-band false alarms. (Single-frame marker counts are noisy; tgtA's resolution under so/os
is the *statistical* claim, proven by `slice3_verify.gd` (61/60 of 80 looks) — the frames prove the
threshold-shape contrast.) Numbers were already wire-verified (`slice3_verify.gd`); the picture is now
eyeballed too — no
open step remains in slice 3. (The capture technique — the agent rendering `_draw` itself, not a human
— is saved in [[ewsim-godot-headless]].)

Run the slice-3 showcase: `julia --project=core tools/server.jl scenarios/slice3_cfar.yaml`, then
launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects CFAR and shows the range-power
view; cycle the `cfar:` button to watch the threshold curve track the clutter / resolve the masked
target). Re-run the step-4 proof headless: start that server, then `godot --headless --path
clients/godot --script res://net/slice3_verify.gd` (exit 0 = pass; serves one client then exits). The
toggle/slider UI test needs NO server: `godot --headless --path clients/godot --script
res://net/slice3_ui_test.gd`. **(stretch, deferred)** a Pluto CFAR diagram (Pd/Pfa vs SNR per
variant, or threshold-curve panels over the profile).

## Slice 4 — jamming / EP — J/S burn-through

**Slice 4 — jamming / EP** (HANDOFF §10 item 4) — **COMPLETE. Gates 1–4 done & green (923 tests);
wire + UI machine-verified AND the spatial jammer-marker `_draw` VISUALLY CONFIRMED (2026-06-23).**
Planned FULL in `docs/plans/slice4.md` (4 staged gates: `rf.jl` jamming
physics → `Jammer` `build_env!` subsystem + radar `SNR_eff=SNR/(1+JNR)` coupling + self-screening
burn-through → two-level antenna model + standoff + `ep` fidelity [none/freq_agility/sidelobe_blanking]
→ scenarios + Godot spatial-view extensions + verifier). The jammer will be the **first subsystem to
use `build_env!`** (phase 2) — the first real cross-subsystem coupling through `w.env` (HANDOFF §3).
No draw-topology hazard (deterministic SNR modulation, like slice 2 not slice 3); `:ep` is
introduce-safe (contrast slice-3's `:cfar` guard). DRFM/deceptive jamming, RGPO, PRF-jitter EP
deferred to §11.
Step 1 (gate 1 — jamming physics green): `rf.jl` gains the J/S primitives (append-only — no existing
symbol changed, so slices 1–3 stay byte-identical). `jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R_j;
gr_db=rp.gain_db)` — the one-way (beacon) JNR = `Pj·Gj·Gr·λ²·overlap / ((4π)²·R_j²·k·T0·B·F·L)`,
normalized to the SAME thermal denominator as `snr_freespace` (so `J/S = JNR/SNR` cancels k·T0·B·F·L
and λ²). One-way `(4π)²`/`R_j⁻²` + a SINGLE receive `Gr` (not the monostatic `G²`) is the burn-through
asymmetry: doubling jammer range costs it 6 dB, the two-way echo 12 dB. `overlap = min(1, B_r/B_j)`
is barrage dilution. `antenna_gain(rp, θ_rad; beamwidth_rad, sidelobe_db) → dB` is the two-level
receive pattern (mainlobe `gain_db` for `|θ|≤bw/2` inclusive, else `gain_db−sidelobe_db`) feeding
`gr_db` — the standoff-vs-self-screen enabler (deferred to gate 3, but the primitive lands now).
`burnthrough_range(rp, rcs, pj_w, gj_db, bj_hz; gr_db, js_margin=1.0)` is the self-screen `J/S=js_margin`
closed form via the ORACLE `K_s=snr_freespace(R=1)`, `K_j=jam_noise_ratio(R_j=1)`, `R_bt=√(js_margin·K_s/K_j)`
(a link-budget slip in either moves R_bt in lockstep). All four approximations named in docstrings
(one-way free-space J path, barrage `overlap`, two-level pattern, benign common-mode F/L: F/L cancel
in J/S so the crossover is invariant to them). `test_jamming.jl` (35 closed-form tests, deterministic
like two_ray — no MC band; runs after `test_propagation.jl`): the −6/−12 dB asymmetry SIDE BY SIDE,
J/S ∝ R² self-screen + ∝ R_t⁴ standoff, barrage −10 dB + overlap-saturates-at-1, two-level gain
(inclusive boundary, sign-symmetric, sidelobe JNR = −sidelobe_db), burnthrough round-trip (J/S=1 at
R_bt with atol, <1 inside / >1 outside, √-scaling on js_margin), F/L cancel in J/S, and the **corrected
B_r law** (J/S B_r-invariant for SPOT; with `B_j` held FIXED — barrage — JNR B_r-invariant + J/S ∝ B_r;
guards the inverted "B_r cancels in J/S" assertion that bit the plan), + guards.
Step 2 (gate 2 — self-screen burn-through live): `radar.jl` `Jammer <: Subsystem` — the **FIRST
`build_env!` subsystem** (phase 2 of the tick contract finally fires). It writes per-radar
contributions into `w.env[:jamming][radar] = Vector{JamContribution}`, where `const
JamContribution = @NamedTuple{jnr::Float64, in_beam::Bool, bj_hz::Float64}` — NOT a pre-summed
scalar, because gate-3 EP conditions on the per-contribution `in_beam`/`bj_hz` (a sum would erase
exactly what EP acts on). Gate 2 is mainlobe-only: `gr_db = rp.gain_db` (the `jam_noise_ratio`
default), `in_beam = true` placeholder (gate 3 fills it from `antenna_gain`). The §3 coupling done
right — through `env`, never a direct subsystem call; `env` is rebuilt fresh each tick so a stale
floor can't leak. `_observe_point!` reads it: `jnr_total = _radar_jnr(contribs)` (plain additive
sum — **the single seam where gate-3 EP plugs in**), then `SNR_eff = snr_th/(1+jnr_total)` per
target. Crucially `jnr_total = 0.0` absent a jammer ⇒ `snr_th/1.0 === snr_th` bit-for-bit, so the
detector sees an identical value and the **draw stream is untouched** — slices 1–3 byte-identical
(the `_sample_z` golden + `test_determinism` stayed green through the restructure, the real proof).
**No draw-topology hazard** (slice-2-shaped, not slice-3): `detect_once` stays unconditional, so
jammer on/off changes detection BOOLEANS, never the draw COUNT. Telemetry: `snr_db` now carries
`SNR_eff` (≡ thermal SNR when unjammed); `jnr_db` + `js_db` ship **ONLY when this radar sees a
jammer** (a no-jammer frame is unchanged — pinned). `js_db = _snr_db_wire(jnr) − _snr_db_wire(snr_th)`
— the dB DIFFERENCE equals `lin2db(JNR/S)` when both are above the floor (log identity) and stays
**wire-safe finite** if S→0 (a masked/no-target frame), where the quotient `lin2db(JNR/S)` would be
+Inf JSON-poison (the slice-2 null watch-item, here on J/S); >0 = jammed, <0 = burn-through. Guards
(a live config can't crash a tick): co-located `R_j = 0` skipped at the consumer (gate-4 range
slider can drive it), `bandwidth_hz > 0` validated at LOAD (a `DomainError` in `build_env!` →
`tick!` → the session's IO-only catch would silently drop the connection — not a live slider, so
reject at load). `scenario.jl`: `:jammer` kind (`comp[:pt_w, :gain_db, :bandwidth_hz]` +
`[ConstantVelocity, Jammer]` subs). `_observe_cfar!` LEFT UNTOUCHED — jammer+cfar is the documented
deferred composition (a jammer in a cfar scenario writes `env[:jamming]` harmlessly, ignored; do
NOT ship such a scenario). `test_jammer.jl` (6 testsets, +29): `build_env!` populates `env[:jamming]`
(record shape + JNR vs the rf.jl closed form); `SNR_eff == SNR/(1+JNR)` + jnr_db/js_db closed forms;
**self-screen burn-through** — `js_db` flips sign across `burnthrough_range` (+6 dB/octave R² law,
≈0 dB at R_bt), pinned deterministically NOT on the random boolean; **draw-stream invariance**
(jammer on/off → same `w.rng` end-state, different detections, unjammed detects more); **no-jammer
frame has NO jnr_db/js_db key**; the loader arm (comp + subs + bandwidth≤0 / missing-block rejects,
which the programmatic-world tests would otherwise never exercise). Mainlobe only (no antenna model /
EP yet).
Step 3 (gate 3 — two-level antenna/standoff + `ep` fidelity live): `radar.jl` `build_env!` now uses a
**two-level receive gain** — the radar boresights its NEAREST target (`_nearest_target`, ties by
sorted id; `nothing` → conservative mainlobe so a jammer-only scene can't throw), and the jammer's
`_boresight_angle` off that line (acos of the normalized dot, clamped to [−1,1], zero-vector guard)
picks `antenna_gain`'s mainlobe Gr (θ≈0 → self-screen, cancels in J/S) vs the sidelobe floor (off-axis
→ standoff, uncancelled & weaker, what sidelobe-blanking attacks). A self-screen jammer rides θ=0 →
mainlobe, so **gate-2 self-screen tests stay byte-identical**. `EP_MODES = (:none, :freq_agility,
:sidelobe_blanking)` joins `LIVE_FIDELITY_MODES` as `ep = EP_MODES`; **`set_fidelity :ep` needs NO
server change** (the per-key table from slice 3 validates it, and the `:cfar` introduce-guard doesn't
match `:ep` — so `:ep` is **introduce-safe**, the sharp slice-3 contrast). EP is applied in the
`_radar_jnr` **seam** via `_ep_factor(ep, c, comp)` — a NAMED, **CONDITIONED** modifier (never a flat
fudge): `:freq_agility` `JNR ×= min(1, B_j/B_agile)` (big benefit vs a SPOT jammer, **exact no-op vs
BARRAGE** `B_j ≥ B_agile`), `:sidelobe_blanking` `JNR ×= db2lin(−cancel_db)` iff `!in_beam` (**exact
no-op on a MAINLOBE** self-screen jammer — can't blank the mainlobe without blanking the target),
`:none` → 1.0 exactly (byte-identical to no EP). Antenna/EP config are RADAR comp keys read with
**defaults** (`:beamwidth_rad`=3°, `:sidelobe_db`=30, `:agile_bw_hz`=10 MHz, `:cancel_db`=30) so
toggling `:ep` onto ANY scenario can't `KeyError` a tick — the introduce-safe contract REQUIRES the
defaults (the "a live config can't crash a tick" watch-item). `_observe_point!` reads `ep` only when a
jammer is present (`contribs !== nothing`), so a no-jammer frame never consults it → slices 1-3 stay
byte-identical. Telemetry: `jnr_db`/`js_db` now reflect the EP-reduced JNR (the lesson is a visible
number). Tests (+28): `test_jammer.jl` (+2 testsets — standoff enters a sidelobe: `in_beam=false` +
exact sidelobe JNR = mainlobe·db2lin(−30); **2×2 EP conditioning** — matched reduces J/S by exactly
`cancel_db` / `10·log10(B_agile/B_j)`, mismatched is a **bit-exact `==` no-op** [not calibrated-to-pass,
the slice-2/3 trap], matched EP raises `snr_db`); `test_determinism.jl` (mid-run `:ep` **introduce AND
toggle** both bit-identical, `ta != tn` proves EP **flips detections** [a self-screen spot jammer tuned
to the burn-through knee — pj_w=1e-3 at 5 km — where freq_agility's +10 dB tips ~half the looks: not a
dead knob, the slice-3 cfar pattern], **jammer-free introduce → rng end-state unchanged** = the
sharpest introduce-safe form, closing the gap the goldens leave); `test_server.jl` (`set_fidelity :ep`
write/reject + introduce-allowed). **NO draw-topology hazard** — the `_sample_z` golden +
`test_determinism` stayed green through the `_radar_jnr` signature change.
Step 4 (gate 4 — visible live): two showcase scenarios, numbers TUNED EMPIRICALLY (throwaway probes —
the slice-3 lesson) and validated against the LIVE `build_env!→observe!` wire path, NOT a hand-recompute
(advisor: pin against the oracle). `scenarios/slice4_selfscreen.yaml` — σ=100 platform closing head-on
with a CO-LOCATED 8 W SPOT jammer on a 200 kW radar; **R_bt ≈ 25 km** (the gate-2-review's required
10–30 km band; default ~9 m R_bt fixed). Pd_unjammed ≈ 1 across the run so the jammer is the SOLE masker
(advisor: burn-through is clean only if range-limit isn't a confound) — which means light-up lands at
~0.22·R_bt, INSIDE R_bt: that's correct physics (at the J/S=1 crossover SNR_eff≈0 dB), so we keep
Pd_unj≈1 and let the EP toggle + jammer-power knob be the live levers rather than coincide light-up with
R_bt. `scenarios/slice4_standoff.yaml` — σ=10 fighter closing RADIALLY (fixed bearing → no
mainlobe↔sidelobe cliff) while a 10 kW BARRAGE (50 MHz) jammer holds station at `[28000, 0, 12000]`: the
offset is in ALTITUDE (z), NOT cross-range (y), so the elevation view renders it as a visibly elevated
~23° off-axis marker with an IDENTICAL 3-D boresight angle/sidelobe JNR (advisor: a y-offset collapses
onto the boresight line in the elevation view). JNR ≈ 33 dB sidelobe, masked across [25,40] km. The 2×2
EP lesson splits across the two scenarios: self-screen showcases **freq_agility** (spot, matched) with
sidelobe_blanking a mainlobe no-op; standoff showcases **sidelobe_blanking** (off-axis, matched) with
freq_agility a barrage no-op. `propagation` is OMITTED from both fidelity maps (advisor: one fidelity →
the shared client button is unambiguously the ep cycler; radar defaults propagation to free_space).
`scenario.jl`: `_radar_comp!` reads the OPTIONAL antenna/EP keys — `beamwidth_deg`
(→`comp[:beamwidth_rad]=deg2rad`), `sidelobe_db`, `agile_bw_hz`, `cancel_db` — when present (radar.jl
already defaults them, so slice-1/2/3 blocks omit them; introduce-safe). Godot `Sandbox.gd`: a
`_fid_kind` discriminator (decided at handshake: `cfar`|`ep`|`propagation`) drives the SHARED fidelity
button; a slice-4 (`ep`, no `range_axis_m`) handshake stays SPATIAL mode but `_setup_spatial_fid_btn`
wires the button to `_on_ep_pressed` (the none→freq_agility→sidelobe_blanking ring, guarded disconnect
like `_enter_cfar_mode`). `_draw_spatial` gains a `jammer` arm — a magenta diamond + a faint radar→jammer
line (mainlobe-on-target vs off-axis-sidelobe geometry); JNR/J-S readout is automatic (telemetry keys).
`net/slice4_verify.gd` drives the REAL server and covers BOTH scenarios on the wire (advisor: don't leave
the standoff lesson to smoke-load only): self-screen burn-through (js_db +1.55→−12.43 as the target
closes, SNR_eff rises), freq_agility +10 dB / sidelobe_blanking bit-identical no-op, **the jammer-power
knob** (`set_param jam1.pt_w` 8→80 W raises js_db +10 dB → crossover moves; the slice-1 sandbox_verify
"slider→core→telemetry IS the deliverable" precedent), then `load_scenario` to standoff:
sidelobe_blanking drops js_db 30 dB (=cancel_db) / freq_agility bit-identical barrage no-op — all numbers
matched the probe to the dB, no-ops bit-identical to 6 dp (`S4V OK`, exit 0). `net/slice4_ui_test.gd`
(mock client, no server): slice-4 handshake stays spatial + wires the ep cycler, the ring walks/wraps,
the jammer slider sends `set_param`, reset resyncs to none (`S4UI OK`). `Sandbox.tscn` smoke-loaded
headless against BOTH slice-4 servers (no GDScript errors, server `DONE` ⇒ scene connected on each).
`test_scenario.jl` +2 loader testsets (parse, ep default, propagation ABSENT, antenna/EP keys
`haskey`-asserted + deg→rad pinned — advisor: the keys EQUAL the defaults numerically so a silently
failed read would still pass every wire test; haskey is the discriminating check; jammer
co-located/elevated geometry, sidelobe angle > half-beamwidth, barrage ≥ agile band, R_bt in 10–30 km,
target beyond R_bt, ep not a knob). The spatial jammer-marker `_draw` PIXEL branch VISUALLY CONFIRMED
2026-06-23 via the windowed shot harness (the slice-3 technique, [[ewsim-godot-headless]]): the STANDOFF
scene renders the full lesson — `ep=none` target GREY (masked, js_db +9.2) with the elevated off-axis
magenta jammer + ~23° line; `ep=sidelobe_blanking` target GREEN + detection blips (jnr_db 33.4→3.4 =
−30 dB, detected:YES) — and the self-screen co-located jammer is legible (the magenta `jam1` label
distinguishes it from the `tgt1` circle it rides). **NO draw-topology hazard** held throughout (slices
1–3 byte-identical; `_sample_z` golden + test_determinism green). No open step remains in slice 4.

Run the slice-4 showcase: `julia --project=core tools/server.jl scenarios/slice4_selfscreen.yaml` (or
`scenarios/slice4_standoff.yaml`), then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses
the spatial view; cycle the `ep:` button to watch freq_agility burn through / sidelobe_blanking unmask;
drag the jammer-power slider to move the crossover). Re-run the gate-4 proof headless: start that server,
then `godot --headless --path clients/godot --script res://net/slice4_verify.gd` (exit 0 = pass; it
`load_scenario`s standoff itself, so launch it against the SELFSCREEN server). The UI test needs NO
server: `godot --headless --path clients/godot --script res://net/slice4_ui_test.gd`. **(stretch,
deferred)** a Pluto burn-through diagram (`clients/notebooks/slice4_burnthrough.jl`).

## Slice 5 — DF / geolocation — bearings-only fix + GDOP ellipse

**Slice 5 — DF / geolocation** (bearings-only emitter location + the GDOP error ellipse; HANDOFF §10
item 5) — **COMPLETE. Gates 1–3 done & green (1055 tests); wire + UI machine-verified AND the plan-view
`_draw_plan` VISUALLY CONFIRMED (2026-06-30).** Planned FULL in `docs/plans/slice5.md`
(3 staged gates: geometry/estimation primitives → `DFSensor`/`Geolocator` lighting **phase 4 of the
tick contract** [`decide!`, the natural milestone after slice 4 lit `build_env!`] → `estimator`
fidelity + scenario + Godot **plan/top-down (x-y)** view + verifier). The lesson is **GDOP**: bearings
crossing near 90° pin an emitter tightly, grazing crossings stretch the covariance into a long thin
**error ellipse** down-range; the second lesson is the **estimator fidelity** (the biased closed-form
`pseudolinear` fix vs the `ml` Gauss-Newton fix walking back toward truth). Scope: single emitter,
**2-D azimuth-only**, jamming-free (one lesson per scenario). NO draw-topology hazard (deterministic
given the drawn bearings, like slices 2/4 not slice 3); `:estimator` is introduce-safe.
Gate 1 (geometry + estimation primitives green — closed-form + analytic-vs-MC): two new HANDOFF §9
**SHARED LIBS** with deliberately **measurement-agnostic signatures** (GPS-DOP/seeker reuse the
*signature*, only the inner 2×2 inverse generalises to 4×4 later — advisor §9; eig2x2 stays 2×2-by-
name). Both pure / no `w.rng`, dependency-free closed-form 2×2 (no LinearAlgebra — the `_range` house
style). Included `detection.jl → geometry.jl → estimation.jl → radar.jl` (pure, depend only on
world/StaticArrays). `geometry.jl`: `bearing(from,to)=atan(Δy,Δx)` planar (z ignored), `wrap_angle=
rem(·,2π,RoundNearest)→[−π,π]` for every angular residual (the §1 sign/wrap trifecta, pinned in 4
quadrants), `eig2x2(C)` closed-form symmetric eigendecomp, `error_ellipse(C;nsigma)→(a,b,ang)` (axes
∝ σθ via C), `gdop(H)=√trace((HᵀH)⁻¹)` at **UNIT σ** (geometry-only, units m/rad for AOA, σθ-INVARIANT
— must NOT be the σθ-weighted form, advisor #2). **The discriminating seam (advisor):** gdop and the
ellipse consume *two different matrices* — gdop ← H with `1/R̂` rows at unit σ (range-weighted,
σ-unweighted); ellipse ← `C=(HᵀR⁻¹H)⁻¹`, `R=diag(σ²)` (range AND σ weighted); feed the σ-weighted one
to gdop and the σθ slider wrongly moves GDOP. Identity `AᵀWA≡HᵀR⁻¹H` ⇒ the pseudolinear `linear_ls`
cov **is** the ellipse C (no separate Fisher path). Singular geometry → readouts clamp to a NAMED
exported `FINITE_CEIL=1e9` (isfinite-guard, NOT an absolute det-floor which is scale-fragile —
advisor); the wire cap (gate 2/3) reuses it. `estimation.jl`: generic `linear_ls(A,b,W)→(p,cov)` (2×2
normal-eqs, relative det-ridge) + `gauss_newton(p0,resid_fn,jac_fn,R;iters)→(p,cov)` (callback-based,
**fixed iteration count** not until-convergence + **divergence→seed fallback** [non-finite or
residual-growing step rejected, keeps last good p] — advisor #6, two distinct guards from the det-
floor); `bearings_fix(thetas,positions,sigmas;estimator)` is the ONE bearings-specific resident (the
staged gate needs it at gate 1, before geolocation.jl), builds `[sinθ̂,−cosθ̂]` rows + the wrapped
residual + calls the scaffold. `:pseudolinear` = the BIASED baseline (noisy θ̂ in the regressor),
`:ml` = GN seeded at pseudolinear (draw-free rung switch). **Named two-pass weighting** (`Wᵢ=1/(σᵢ²R̂ᵢ²)`,
R̂ᵢ unknown a priori → σ-only seed pass → R̂ ONCE → one re-weight, same R̂ everywhere; not IRLS — the
inconsistent-R̂ gotcha). `ESTIMATOR_MODES=(:pseudolinear,:ml)` defined HERE (before radar.jl) so gate-2's
`LIVE_FIDELITY_MODES` can REFERENCE it with no include-order gymnastics (advisor #5; the CFAR_MODES
one-list-no-drift discipline). `test_geometry.jl`+`test_estimation.jl` (+44 tests): closed-form signs/
wrap/eig/ellipse (explicit `atol`); gdop monotonicity (orthogonal crossing = the minimum, wider
baseline lower), degenerate→huge-but-FINITE (parallel rows → `FINITE_CEIL`, near-collinear finite
naturally), ellipse elongates ALONG the LOS (advisor #3 — orientation pin), far sensors weigh less
(1/R²), and the **GDOP-σθ-INVARIANCE vs ellipse-σθ-SCALING** pin (advisor #2) with the exact
`√(a²+b²)=gdop·σ` decomposition; noise-free fix==truth exactly (both estimators) + 2-sensor 90°
crossing = the intersection; **pseudolinear bias as a MC MEAN offset with the KNOWN sign** (40 km/±10
km/1°: meanPL x=38735<40000 = range underestimated/pulled to sensors, ‖bias‖≈1265 m ≈ 34× the MC
stderr, `:ml` cuts it to ≈98 m — advisor #1, a mean-offset check not a covariance check, ML reduces
‖bias‖ as an external anchor); **CRLB≈ML MC scatter on GOOD geometry** (area ratio ≈1.008 — matched to
the ≈unbiased `:ml`, NOT the biased pseudolinear, a category error) **and the named UNDER-prediction on
BAD geometry** (linear ellipse area < MC scatter area, ≈304× — the honest approximation boundary). All
MC uses its OWN `Xoshiro` (the slice-1 batch precedent). The MC tests are NOT self-confirming (`Cmc`
uses only the point estimates; `cov_at`/`jac_rows` are test-local recomputes — independent of the cov
code under test, advisor-verified no pass-by-construction). Slices 1–4 **byte-identical** (the
`_sample_z` golden + `test_determinism` green through the include — no shared symbol touched; the plan
pin). Numbers tuned EMPIRICALLY first with a throwaway probe (the slice-3/4 rule).

Gate 2 (DF subsystems wired — phase 4 lit, green): `geolocation.jl` — the `DFSensor`/`Geolocator` pair,
the FIRST use of `decide!` (phase 4 of the tick contract). **Include order corrected (advisor):** the
plan's "geolocation BEFORE radar" rationale was STALE — it existed so `LIVE_FIDELITY_MODES` could see
`ESTIMATOR_MODES`, but gate 1 already moved that const into `estimation.jl`. So `geolocation.jl` is
included `… radar.jl → geolocation.jl → scenario.jl` (AFTER radar), letting it reuse `_range`
DIRECTLY instead of inlining distance; verified radar.jl has NO back-dep on geolocation (its only
cross-ref, `LIVE_FIDELITY_MODES → ESTIMATOR_MODES`, is satisfied by estimation.jl). `const
BearingRecord = @NamedTuple{theta::Float64, pos::Vec3, sigma::Float64}` (INTERNAL, like
`JamContribution`). `DFSensor.observe!` (phase 3): bearings the nearest `:emitter` (`_nearest_emitter`,
sorted-id tie, the `_nearest_target` mirror), draws ONE randn/look (`wrap_angle(θ_true + σ·randn)`),
appends to `w.env[:bearings]` + publishes `<id>.bearing_deg` (rad2deg — NOT radians under a `_deg`
key). `Geolocator.decide!` (phase 4): reads ALL `env[:bearings]`, fix+cov via `bearings_fix` dispatching
on `get(w.fidelity, :estimator, :pseudolinear)`, ellipse via `error_ellipse(cov)`, and — the advisor's
**second catch** — **GDOP from emitter TRUTH, not the noisy fix**: the gdop `H` rows `[−sinθ/R̂, cosθ/R̂]`
are built about the TRUE emitter so GDOP is σθ-invariant AND jitter-free (a fix-derived GDOP would
drift every tick and move when the σθ slider re-rolls the noise — failing the gate-3 wire asserts). So
the split is exact: **ellipse C ← bearings_fix (measured θ̂, scales ∝σθ); GDOP ← truth (σ-free)**.
Telemetry `<station>.fix_x/.fix_y/.err_m/.gdop/.ell_a/.ell_b/.ell_deg` all clamped finite (`_finite`
for the non-negative readouts, a signed `_finite_coord` for fix_x/fix_y, ceiling `FINITE_CEIL` — a
singular geometry ships huge-but-finite, never Inf/NaN, never throws the tick). `LIVE_FIDELITY_MODES`
(radar.jl) now **references** `ESTIMATOR_MODES` (`estimator = ESTIMATOR_MODES`) — so `set_fidelity
:estimator` validates with NO server change (introduce-safe, the `:cfar` guard doesn't match it), the
slice-4 `:ep` contract. **Scope note (advisor):** the core fidelity plumbing (the table entry + the
Geolocator's `:estimator` dispatch) landed in gate 2 — EARLIER than slice5.md's gate-3 text — per
CLAUDE.md's "Next: gate 2" guidance; it's introduce-safe with no draw hazard, and the Geolocator
actually consumes the key (no latent validate-but-ignore). `scenario.jl`: `:emitter` (≈target, CV
mover, no rcs), `:df_sensor` (`sigma_theta_deg`→`comp[:sigma_theta_rad]=deg2rad`, σθ>0 rejected at LOAD
— the jammer `bandwidth_hz` precedent; a live drag is clamped at the consumer `_SIGMA_THETA_FLOOR`),
`:df_station` (`Geolocator` + optional `geolocator: nsigma`); `_validate_geoloc` asserts ≥2 sensors +
exactly 1 emitter + ≥1 station at LOAD (triggered by DF-entity presence, so a non-DF scenario is
untouched). `test_geolocation.jl` (+43, the test_jammer analog): DFSensor record shape + EXACT-draw
reconstruction (off a fresh `Xoshiro`); Geolocator fix == `bearings_fix` (both rungs); FINITE telemetry
under a near-collinear geometry (no throw); the **GDOP+ellipse STRETCH** over range (deterministic,
truth-based); **GDOP σθ-INVARIANT (`==`) while the ellipse scales ∝σθ** (advisor #2 on the wire — the
ell-scaling leg uses TINY σ so the realized geometry is σ-free and `cov∝σ²` holds cleanly; a large-σ
single realization isn't monotone — the bug the first test run caught); the **draw-free rung switch**
(pseudolinear vs ml → SAME rng end-state, DIFFERENT fix, ml lowers mean err_m — the biased 40km/±10km/1°
geometry, not a dead knob); no-DF world writes no bearings/DF telemetry; loader arms + rejects.
`test_determinism.jl` +a DF scenario (same-seed bit-identical fix trace via `reinterpret`; rung switch
rng-lockstep but fix differs). Slices 1–4 **byte-identical** (geolocation adds NO code to the radar
path; the `_sample_z` golden + all prior testsets green through the include).

Gate 3 (estimator fidelity + scenario + Godot plan view + verifiers — **DONE & green, 1055 tests;
wire + UI machine-verified AND the plan-view `_draw_plan` VISUALLY CONFIRMED 2026-06-30**). The core
fidelity plumbing landed in gate 2, so gate 3 = the scenario + client + verifiers + server/scenario
test arms. **σθ unit blocker (advisor):** gate 2 stored `comp[:sigma_theta_rad]`, but a live
`set_param sigma_theta_deg` slider must write the SAME key the consumer reads (a knob addressing a
non-consumed key fails `_parse_knobs`/no-ops the ellipse). So DEGREES is now the comp key end-to-end —
`comp[:sigma_theta_deg]` (raw), `DFSensor.observe!` does `max(deg2rad(...), _SIGMA_THETA_FLOOR)` at the
consumer (floor stays in rad); the gate-1/2 fixtures + loader test migrated to `:sigma_theta_deg`.
`scenarios/slice5_geoloc.yaml` (seed 5): 3 sensors on a ±20 km y-baseline (dfs1/2/3) + a station at
centre; emitter starts abeam at (15 km, 5 km) and flies +x at 1 km/s (good→bad geometry); 3 σθ
sliders; default `:pseudolinear`. Tuned EMPIRICALLY (a throwaway probe) + oracle-pinned: GOOD t=8 s
(x=23 km, gdop≈37 k, a/b≈1.85) vs BAD t=40 s (x=55 km, gdop≈127 k, a/b≈3.63, **pseudolinear err≈53 km
COLLAPSING toward the sensors** vs **ml≈7 km** — a 7.77× cut). Godot `Sandbox.gd`: a NEW `"geoloc"`
render mode (top-down x-y PLAN view — the x-z elevation view can't show a 2-D crossing/ground ellipse),
discriminated at handshake (`_fidelity.has("estimator")` AND no `range_axis_m` → `_enter_geoloc_mode`,
the slice-3 `range_axis_m`→cfar pattern). `_draw_plan` plots sensor markers + measured bearing RAYS
(the LOPs), the emitter truth (orange X), the C2 station, the fix (green +), and the error ELLIPSE —
ALL from telemetry (`<station>.fix_x/.fix_y/.err_m/.gdop/.ell_a/.ell_b/.ell_deg`, `<id>.bearing_deg`),
computed in WORLD coords then mapped through an EQUAL-aspect `_world_to_plan` (one px/m scale so the
ellipse isn't distorted; screen +y = world +y UP so the **y-flip renders the ellipse rotation + ray
directions correctly — advisor #3, the silent-inversion risk**). The shared fidelity button becomes
the estimator cycler (`pseudolinear↔ml`, `_on_est_pressed`, guarded disconnect like cfar/ep); the
slice-1/2/4 spatial + slice-3 cfar paths are UNTOUCHED. `_update_readout` already skips arrays (the DF
telemetry is all scalars — no widening). **`warmup!` fix:** the ROC-batch warm resolves a radar (a DF
scenario has NONE → it crashed the server before listening), now guarded on radar presence — the
`tick!`+`state_frame` warm still covers the phase-4 `decide!`/`Geolocator`/`bearings_fix` compile;
`test_server.jl` pins the radar-free warm. `net/slice5_verify.gd` (drives the real server: gdop+ellipse
STRETCH good→bad [a/b 1.85→3.63, gdop 37 k→127 k]; `set_fidelity estimator` pseudolinear→ml cuts err_m
53302→6862 m = 7.77× with **bit-identical t=40.000000** under the held seed; the σθ SLIDER — `set_param
sigma_theta_deg` on ALL 3 sensors [the ellipse scales ∝σθ only when all sensors scale together] at the
GOOD sample with TINY σ (0.01°→0.02°, the clean-2× regime that sidesteps the
[[ewsim-df-ellipse-sigma-monotonicity]] flakiness) → ell_a 5.731→11.464 [2×] while gdop stays
**37464.2472 == 37464.2472** — advisor #2 on the wire, GDOP geometry-only, ellipse carries σθ). `S5V OK`,
exit 0. `net/slice5_ui_test.gd` (mock client, no server: handshake enters geoloc/plan mode + wires the
estimator cycler, the ring walks pseudolinear→ml and wraps, badge/button track, σθ slider sends
set_param, reset resyncs to pseudolinear — `S5UI OK`). `Sandbox.tscn` smoke-loaded headless against a
slice-5 server (server `DONE` ⇒ scene connected, no GDScript errors — catches geoloc-branch parse bugs
the SimClient verifier can't). Tests (+36 over gate 2's 1019): `test_scenario.jl` (slice-5 loader:
estimator default, NO radar/jammer/cfar/ep fidelity or entities, emitter CV/no-rcs flying +x, 3 sensors
on the x=0 baseline with σθ stored RAW in degrees [`haskey :sigma_theta_deg` not `_rad` — the
discriminating check], station+Geolocator nsigma, emitter opens abeam < baseline half-span, estimator
not a knob + σθ knobs address `:sigma_theta_deg`); `test_server.jl` (`set_fidelity :estimator`
write/reject + introduce-safe on a non-DF scenario [the `:ep` contract, NOT `:cfar`'s guard]; warmup
radar-free). `test_determinism.jl` slice-5 coverage was already complete in gate 2 (mid-run `:estimator`
toggle AND introduce-on-a-DF-world both bit-identical — untouched, only the fixture σθ key migrated;
the sharpest "introduce `:estimator` on a NON-DF world → rng end-state unchanged" sub-leg is
safe-by-construction [nothing reads `:estimator` without a `Geolocator`] and pinned at the COMMAND
level by `test_server.jl`'s introduce-safe arm, so it isn't separately re-asserted here — advisor). The `_draw_plan` PIXEL
branch (Godot skips `_draw` headless) was VISUALLY CONFIRMED via 3 windowed shots (the shot harness,
[[ewsim-godot-headless]] — throwaway static-emitter scenarios + a wrapper scene, reverted after): GOOD =
steep bearing crossings / fix sitting ON the emitter truth / round ellipse; BAD-pseudolinear = grazing
near-parallel LOPs / fix COLLAPSED to the sensor array (err 53 km) / stretched down-range ellipse;
BAD-ml = the fix WALKS BACK onto the emitter (err 3.6 km) — the estimator lesson as a picture; the
y-flip proven correct (the bearing rays converge on the emitter in all three). No open step remains in
slice 5's required gates.

Run the slice-5 showcase: `julia --project=core tools/server.jl scenarios/slice5_geoloc.yaml`, then
launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects DF and shows the top-down plan
view; cycle the `est:` button to watch the fix walk back toward truth; drag a σθ slider to scale the
ellipse; the emitter flies good→bad so the ellipse stretches over the run). Re-run the gate-3 proof
headless: start that server, then `godot --headless --path clients/godot --script
res://net/slice5_verify.gd` (exit 0 = pass; serves one client then exits). The UI test needs NO server:
`godot --headless --path clients/godot --script res://net/slice5_ui_test.gd`. **(stretch, deferred)**
offline `batch.jl` `kind=:geoloc_mc` + `clients/notebooks/slice5_gdop.jl` Pluto MC-vs-CRLB overlay.

## Slice 6 — multi-emitter EW — PRI-histogram deinterleaver

**Slice 6 — multi-emitter EW** (interleaved pulse trains → PRI-histogram deinterleaver; HANDOFF §10
item 6) — **COMPLETE. Gates 1–3 done & green (1238 tests); wire + UI machine-verified AND the
ESM raster/histogram `_draw_esm` VISUALLY CONFIRMED (2026-07-01).** The
phase-contract **capstone**: lights `build_env!` + `observe!` + `decide!` in ONE pipeline (emitters
publish params → ESM receiver intercepts/measures the interleaved TOA stream [the one draw site] →
deinterleaver recovers each PRI + groups pulses). Lesson: the **difference histogram** raising peaks
at the true PRIs out of pulse-density soup; fidelity knob `deinterleaver = (:cdif, :sdif)` — CDIF's
**phantom subharmonic** (a stable PRI=T train piles cumulative diff-counts at 2T, 3T → a radar that
isn't there) vs SDIF's **subharmonic check** rejecting it. **Structural, not noise-driven** (appears
on perfectly-stable emitters → deterministic core, no draw-topology hazard; introduce-safe like
`:estimator`/`:ep`). **De-risked with a throwaway probe BEFORE the plan** (advisor): on 3 stable
`[1300,1700,2300] µs` emitters, **CDIF declares 4 PRIs (phantom 2590≈2×1300), SDIF declares 3** —
`n_pri` flips 4→3, the not-a-dead-knob scalar. The two rungs **share one cumulative-histogram +
threshold + sequence-search pipeline; the subharmonic check is the SOLE differentiator** (the faithful
sequential/adaptive-threshold SDIF returned n=0 in the probe and is a named future refinement, with
Nelson's PRI-transform). Scope: **generic parametric emitters only**, stable PRI core (jitter/intercept
degradation sliders), single ESM, no radar/jam/DF in-scenario; defer staggered/sliding PRI, emitter PRI
random-walk (jitter modeled receiver-side), TDOA geolocation (R/c offset OMITTED — inert for PRI). New
`deinterleave.jl` (pure §9-style lib, defines `DEINTERLEAVER_MODES`, before radar.jl) + `esm.jl`
(`PulseEmitter`/`ESMReceiver`/`Deinterleaver`, after radar.jl like geolocation.jl); `:pulse_emitter`/
`:esm` kinds (NB `:emitter` is slice-5 DF — no collision); array telemetry `histogram`/`threshold` +
static `pri_axis_us` handshake (CFAR precedent); new Godot **ESM/PRI view** (TOA raster + difference
histogram, off the handshake `:deinterleaver` fidelity). **Units µs↔SI-seconds** is the §1 trifecta
here. Exact receiver draw order pinned (jitter `randn` THEN intercept `rand`, both unconditional,
spurious last; `2·n_candidate+n_spurious` fixed). `assoc_pct` direction (cdif<sdif) UNPROVEN — probe at
gate 1 before pinning; `n_pri` is the load-bearing flip. **Planned FULL in `docs/plans/slice6.md`** (3
staged gates: `deinterleave.jl` primitives + closed-form subharmonic-trap pin → the ESM 3-phase pipeline
wired → `deinterleaver` fidelity + scenario + Godot ESM view + verifier).

Gate 1 (deinterleave.jl primitives green): the pure §9 lib `deinterleave.jl` (dependency-free, base
Julia only, SI-seconds in/out — the µs↔s boundary lives at the loader/telemetry) included BEFORE
radar.jl + exported. `difference_histogram` (cumulative over C levels), `detect_pris` (the cdif/sdif
extractors — SHARED cumulative histogram + `thresh_frac·peak` threshold + sequence-search, sdif ALONE
adds the subharmonic check `_is_harmonic`), `associate` (two-sided support: a train member has partners
at ±τ, fundamental tie-break) + `assoc_pct` (majority-vote purity, `SPURIOUS_ID` never scores), centroid
PRI refinement. `DEINTERLEAVER_MODES=(:cdif,:sdif)` defined here (the one-list-no-drift source of truth
gate-2's `LIVE_FIDELITY_MODES` will reference). **Params PRINCIPLED-then-probed (advisor's overfit guard
— ONE shared param set for BOTH fixtures, never per-fixture):** bin 20 µs; C=15 levels; `thresh_frac=0.4`
on a WIDE plateau (cdif=4 holds ∀ thresh∈[0.30,0.62]·peak; max in-band spurious peak 15 vs min-kept count
32 — comfortable, not a knife-edge). **The SEARCH BAND is the binding, subtle constraint (advisor,
probe-confirmed):** `max_lag` must satisfy `2·min_PRI < max_lag < 2·(second-smallest PRI)` = (2600,3400) µs
here, so EXACTLY the one phantom (2×min=2600) is in-band and the next harmonic (2×1700=3400) is out.
`max_lag=3000` sits central (2700–3300 all give cdif=4); 2500→cdif=3 (**DEAD KNOB** — phantom excluded),
3500→cdif=5 (harmonic forest). It is **NOT "just above the max fundamental"** — that's a coincidence here
(2×1300≈2300) and FAILS for clustered sets (e.g. [2000,2300,2600]: "just above max"≈2700 excludes 2×2000=4000
→ dead; needs max_lag∈(4000,4600)). **Gate 3's scenario MUST honour this window.** **Sequence-search is
INERT on the stable showcase** (probe: `min_seq∈{0,10,30,50}` give the IDENTICAL PRI set — every periodic
lag recurs, so the threshold, not seq-search, does the discrimination); it stays in the pipeline (the real
algorithm) and earns its keep on spurious/jittered TOAs in **gate 2**, validated there not here. **Headline pinned
closed-form (a REAL over-detection, not pass-by-construction): 3-emitter [1300,1700,2300] µs → cdif=4
(the 3 fundamentals + phantom at 2×1300≈2600) / sdif=3 == n_true — the `n_pri` flip**, PRIs
centroid-refined to within ½-bin. **Deviation from slice6.md's sketch: the 2-emitter case is cdif=3 /
sdif=2 (NOT 4/2)** — 3×1300=3900 is outside the principled band that keeps the 3-emitter case clean
(per-fixture bands = overfit). The subharmonic check pinned in isolation (`_is_harmonic`: 2× with base
present → reject; the non-harmonic ratios 1.31/1.77 → keep — why those PRIs were chosen) + a lone train
showing cdif marks the phantom / sdif drops ONLY it. `assoc_pct` **finite + high (>0.8) interleaved,
==1.0 on a lone train**, direction cdif-vs-sdif NOT pinned (real coincidences on commensurate PRIs cap
it <1 — the honest boundary; extract-and-remove was WORSE at 0.84 — greedy chaining hops onto
coincident cross-emitter pulses). Units µs↔SI round-trip + degenerate guards (empty / single-pulse /
lone-emitter / bad-mode → no throw). `test_deinterleave.jl` (+46) wired into runtests after
detection/cfar; explicit `atol` throughout (never rtol-`≈0`). Slices 1–5 **byte-identical** (the new
lib touches no radar/detection path — the `_sample_z` golden + `test_determinism` green through the
include; nothing references the lib yet).

Gate 2 (the ESM pipeline wired — phases 2+3+4 lit, the phase-contract CAPSTONE; DONE & green, 1184 tests,
+83): new `esm.jl` (included AFTER radar.jl mirroring geolocation.jl; NO back-dep on radar symbols — R/c
omitted so `_range` isn't needed; reuses geometry.jl's `_finite` + deinterleave.jl's pure math) lights
`build_env!` + `observe!` + `decide!` in ONE chain through `w.env`. `PulseEmitter.build_env!` (phase 2)
publishes its constant-PRI params as an `EmitterParams` record into `env[:emitters]` (RNG-free, sorted-id
append order). `ESMReceiver.observe!` (phase 3 — **the ONE draw site**) reads `env[:emitters]` and on a
look-tick (`next_look_t`/`revisit_s` gate) generates the interleaved TOA stream into `env[:toa_stream]`
(a `ToaStream` record: sorted TOAs + parallel truth ids), republishing between looks (readout never
blanks). `Deinterleaver.decide!` (phase 4) reads the stream, runs `detect_pris`/`associate` dispatching
`get(w.fidelity, :deinterleaver, :cdif)`, and publishes telemetry. **Deviation from the plan sketch
(advisor-endorsed): the dwell is PHASE-REFERENCED `[0, T_dwell)`, NOT the literal `[t, t+T_dwell)`** —
matches gate-1's `gen_stream`, makes the candidate count a function of STATIC config only (per-look draw
count truly `w.t`-invariant + the exact-draw test `w.t`-independent), fits "geometry inert / emitters need
not move"; consequence stated: the stream is structurally identical every look, only the drawn noise
differs. **Exact §1 draw order pinned bit-for-bit** (the determinism-golden risk — `test_esm.jl`
reconstructs it MANUALLY off a fresh `Xoshiro`, independent of `_draw_toa_stream`): emitters sorted-id ->
k-ascending -> per candidate JITTER(`randn`) THEN INTERCEPT(`rand`) both UNCONDITIONAL -> `n_spurious`
uniform(`rand`) LAST; total `2*n_candidate + n_spurious`, fixed regardless of rung or slider value. The
phase-4 rung is PURE (no draw) -> **NO draw-topology hazard** anywhere -> `:deinterleaver` is introduce-safe
AND toggle-bit-identical (the `:ep`/`:estimator` contract, NOT slice-3's `:cfar` guard). `n_true` from the
`:pulse_emitter` ENTITY count (a `p_intercept`->0 slider can't lower it). Telemetry: fixed-length
`histogram`/`threshold` arrays (CORE output, `_finite`-clamped, RUNG-INDEPENDENT — the shared cumulative
pipeline; the rung changes only the PRI markers, a same-bars/different-markers visual) + `n_pri`/`n_true`/
`assoc_pct` scalars + display-only variable `pri_us`/`toa_us`/`assign` (never asserted on). `LIVE_FIDELITY_MODES`
REFERENCES `DEINTERLEAVER_MODES` (one-list-no-drift). `scenario.jl`: `:pulse_emitter` (pri/phase/pulse_width
µs->SI-seconds; **pri>0 rejected at LOAD** to avoid an infinite emit loop — NB distinct from slice-5 DF's
`:emitter`) + `:esm` (t_dwell/histogram params µs->s with gate-1's proven defaults; live `jitter_us`/
`p_intercept` sliders, both draw-count-invariant) kinds; `_validate_esm` (≥2 emitters, exactly 1 ESM, the
bounded-pulse `_ESM_MAX_PULSES=1000` guard) at LOAD, triggered by ESM-entity presence so non-ESM scenarios
are untouched. `test_esm.jl` (env-populated + record shape; the EXACT-draw golden; clean 144-pulse count +
truth-stamp; Deinterleaver reproduces the lib; **the headline cdif n_pri=4 / sdif n_pri=3 flip on the
WIRED stream**; histogram peaks at the true PRIs; the draw-free rung switch [rng lockstep, n_pri differs];
finite telemetry incl. a degenerate empty dwell [no throw]; no-ESM wire-surface byte-identity; loader arms
+ rejects). `test_determinism.jl` + a slice-6 scenario (same-seed bit-identical TOA-STREAM fingerprint via
`reinterpret` — sharper than n_pri, advisor; draw-free rung switch; mid-run `:deinterleaver` toggle AND
introduce bit-identical). Slices 1–5 **byte-identical** (esm.jl touches no radar/detection path; the
`_sample_z` golden + all prior testsets green through the include). Server handshake (`_esm_axis_info` +
`scenario_frame` merge + warmup), the scenario YAML, the Godot ESM view, and the verifier are all deferred
to gate 3.

Gate 3 (deinterleaver fidelity + scenario + Godot ESM view + verifiers — **DONE & green, 1238 tests (+54);
wire + UI machine-verified AND `_draw_esm` VISUALLY CONFIRMED 2026-07-01**). The core fidelity plumbing
landed in gate 2, so gate 3 = the handshake axis + scenario + client + verifiers + server/scenario test
arms. `_esm_axis_info(w)` (esm.jl, the `_cfar_axis_info` analog) ships the STATIC ESM axes once at handshake
— `pri_axis_us` (the difference-histogram bin CENTERS in µs, `(b−0.5)·bin`, len n_bins=150), `dwell_us`,
`bin_us`/`n_bins`, `esm` id — merged into `scenario_frame` (returns `nothing` for a non-ESM world, so
slices 1–5 handshakes are unchanged — the byte-identity guard). **`pri_axis_us` presence is the client's
ESM-view discriminator** (the `range_axis_m`→cfar precedent, advisor-endorsed over the plan's
`fidelity[:deinterleaver]` text — order-safe: the arms are mutually exclusive by the one-lesson rule).
`scenarios/slice6_deinterleave.yaml` (seed 6): the de-risked 3 emitters `[1300,1700,2300] µs` (phases
0/300/700, static) + one ESM (80 ms dwell, gate-1's proven params, `max_lag_us=3000` in the binding
`(2600,3400)` window so EXACTLY the one phantom is in-band), default `:cdif`, `jitter_us`/`p_intercept`
sliders; numbers PROBED against the live wire path first (n_pri cdif=4/sdif=3, assoc 0.9375, hist peaks at
1300/1707/2303/2600 µs, threshold 20.4). Godot `Sandbox.gd`: a NEW `"esm"` render mode (`_enter_esm_mode`
off the handshake `pri_axis_us`; `_fid_kind="esm"`, the shared fidelity button becomes the deinterleaver
cycler `cdif↔sdif` via `_on_deint_pressed`, guarded disconnect like cfar/ep/est). `_draw_esm` = two stacked
panels — a **TOA raster** (each intercepted pulse a tick colored by its assigned-emitter index) + the
**difference histogram** (bars over the τ-axis + the flat threshold line [CORE output, α never recomputed] +
green ▼ markers at the detected PRIs), ALL from telemetry. `_update_readout` already skips Array telemetry
(the histogram/threshold/toa/assign/pri arrays render in `_draw`, not as text — the slice-3 float()-crash
watch-item, re-confirmed for the esm keys). The slice-1/2/4 spatial + slice-3 cfar + slice-5 geoloc paths
are UNTOUCHED (their smoke-loads + UI tests stay green — re-run, all pass). `net/slice6_verify.gd` (drives
the real server: handshake ships `pri_axis_us`/`dwell_us` + cdif default + jitter/intercept knobs + no
range_axis; the histogram raises above-threshold peaks at the 3 true PRIs; **`set_fidelity deinterleaver`
cdif→sdif flips n_pri 4→3** with **bit-identical t=0.160000** under the held seed — AND the SHARPEST form
[advisor]: the `histogram`+`threshold` arrays are BIT-IDENTICAL across rungs, ONLY `pri_us` [4→3 markers]
changes = "same bars, same line, different markers"; `set_param jitter_us` blurs the peaks [max 51→16],
`set_param p_intercept` thins the stream [hist sum 687→125] — asserted on the FIXED histogram, never the
display-only toa/assign arrays). `assoc_pct` DIRECTION not asserted (probe: 0.9375==0.9375 across rungs, the
plan's "direction unproven" caveat — only finite+[0,1] checked). `S6V OK`, server `DONE`, exit 0.
`net/slice6_ui_test.gd` (mock client, no server: `pri_axis_us` handshake → esm mode + the deinterleaver
cycler; the ring walks cdif→sdif and wraps; badge/button track; jitter_us slider sends `set_param`; reset
resyncs to cdif — `S6UI OK`). `Sandbox.tscn` smoke-loaded headless against a slice-6 server (server `DONE` ⇒
scene connected on the esm branch, no GDScript errors — caught a GDScript `:=`-from-ternary inference bug in
`_draw_esm` the verifier can't). Tests (+54 over gate 2's 1184): `test_scenario.jl` (slice-6 loader:
deinterleaver default, NO radar/jammer/DF fidelity or entities, 3 pulse emitters with PRIs stored SI SECONDS
[`haskey :pri` not `:pri_us` — the µs→s discriminating check], the SEARCH-BAND `2·min < max_lag < 2·second`
pinned, one ESM, sliders address `jitter_us`/`p_intercept`, deinterleaver not a knob); `test_server.jl`
(`set_fidelity :deinterleaver` write/reject + introduce-safe on a non-ESM scenario [the `:ep`/`:estimator`
contract, NOT `:cfar`'s guard]; **warmup! tolerates an ESM scenario** [radar-free → ROC batch skipped, the
phase-2+3+4 + array-telemetry warm still runs, live World pristine]; `scenario_frame` ships the static PRI
axis with `len(pri_axis_us)==len(histogram)==150` — the handshake↔telemetry consistency an axis/binning
mismatch would break, advisor). `test_determinism.jl` slice-6 coverage was already complete in gate 2
(mid-run `:deinterleaver` toggle AND introduce both bit-identical, draw-free rung switch — untouched). The
`_draw_esm` PIXEL branch (Godot skips `_draw` headless) was VISUALLY CONFIRMED via 3 windowed shots (the
shot harness, [[ewsim-godot-headless]] — a throwaway ShotEsm wrapper pointed `run/main_scene` at itself,
instantiated `Sandbox.tscn` against the live server, `get_viewport().get_texture().get_image().save_png`,
reverted after): **cdif** = four ▼ markers (1300/1707/2303 + the phantom 2600) over four above-threshold
bars, n_pri=4; **sdif** = the SAME four bars + threshold but only THREE markers (the 2600 bar unmarked),
n_pri=3 — the phantom-vanishes lesson as a picture; **jitter σ=45 µs** = the histogram blurred into a noisy
forest (~21 spurious peaks, assoc 0.94→0.80) — TOA jitter muddying the algorithm. No open step remains in
slice 6's required gates.

Run the slice-6 showcase: `julia --project=core tools/server.jl scenarios/slice6_deinterleave.yaml`, then
launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects ESM and shows the raster/histogram
view; cycle the `deint:` button to watch the phantom PRI marker appear [cdif] and vanish [sdif]; drag the
TOA-jitter slider to blur the peaks, or P(intercept) to thin the stream). Re-run the gate-3 proof headless:
start that server, then `godot --headless --path clients/godot --script res://net/slice6_verify.gd` (exit 0
= pass; serves one client then exits). The UI test needs NO server: `godot --headless --path clients/godot
--script res://net/slice6_ui_test.gd`. **(stretch, deferred)** offline `batch.jl` `kind=:pri_mc`
(deinterleave success-rate vs jitter/emitter-density) + `clients/notebooks/slice6_pri.jl` Pluto diagram.

## Slice 7 — GPS — pseudoranges, trilateration, DOP + RAIM

**Slice 7 — GPS (pseudoranges → trilateration → DOP + RAIM)** (HANDOFF §9 REUSE milestone / §10 item 7)
— **COMPLETE. Gates 1–3 done & green (1492 tests); wire + UI machine-verified AND the GPS sky/residual
`_draw_gps` VISUALLY CONFIRMED (2026-07-01).** The slice that cashes in §9 ("why the suite is one project"):
lights NO new tick phase — it REUSES the `build_env!→observe!→decide!` shape a third time — its novelty
is CROSS-DOMAIN CODE REUSE (the same `geometry.jl`/`estimation.jl` that fixed a DF emitter now
trilaterate a GPS receiver, generalized 2→4: x,y,z + the receiver clock bias `c·b`). Lesson 1 = **DOP**
(identical σ on every pseudorange, but a spread constellation pins the fix and a clustered one smears it —
GEOMETRY sets the error, `σ_pos=DOP·σ`); lesson 2 = **RAIM** (over-determination → the LS residuals carry
a consistency check → a spoofed satellite inflates the residual RSS → detect/exclude). Scope: **flat-local
fictional satellites** (SI `Vec3`, NO ECEF/WGS84/orbits), single receiver, full 3-D solve; deferred: real
orbits/ephemeris, Klobuchar/Saastamoinen, carrier-phase/RTK, multi-fault RAIM, GPS-spoofing-as-live-RGPO.
NO draw-topology hazard (deterministic given the drawn pseudoranges, like slices 2/4/5/6). **Planned FULL
in `docs/plans/slice7.md`** (3 gates: pure primitives → GPS pipeline wired → fidelity + 2 scenarios +
Godot sky view + verifiers).

Gate 1 (pure primitives green — closed-form + MC): **the 2→4 generalization decision (advisor-run as the
a/b gate: implement (b), run the DF suite, let it decide).** `geometry.jl` gains the SHARED N-dim solver
`_solve_normal(M,g)→(x,Minv,singular)` (hand-rolled Cholesky LLᵀ, no LinearAlgebra — the `_range` house
style; relative-ridge pivot floor = the N-dim analog of `_solve2x2`'s det floor; a well-conditioned pivot
used VERBATIM so N=2 reproduces the cofactor to floating-point, a rank-deficient pivot floored + flagged)
+ generic `dop(H)→(Q,singular)` (`Q=(HᵀH)⁻¹` at UNIT variance — σ NEVER inside Q, the slice-5 σθ-trap on
the GPS surface) + `dop_components(Q;singular)→(gdop,pdop,hdop,vdop,tdop)` (a `singular` constellation
ships `FINITE_CEIL` EXACTLY — the `gdop` det-guard analog). `estimation.jl`: **`gauss_newton` generalized
to N-dim** (infers N from `p0`, assembles `HᵀR⁻¹H` via a generic `_normal_eqs`, solves via the shared
`_solve_normal`) — **so DF `:ml` (N=2) and GPS `position_fix` (N=4) call literally the same scaffold (the
§9 headline made real).** **`linear_ls`/`_solve2x2` KEPT 2×2-cofactor (advisor's fallback (a) for the
pseudolinear path ONLY):** the pseudolinear normal matrix has a TINY LEADING pivot (down-range/x info is
the small one), which natural-order Cholesky handles less stably on shallow-geometry noisy draws — the
slice-5 pseudolinear-bias MC test caught it (bias collapsed 1265→8.8 m via near-singular outliers). GPS
never uses `linear_ls`, so keeping the stable cofactor costs nothing and the reuse story stays honest —
the shared machinery is `gauss_newton`/`dop`, not the DF baseline. **Byte-identity (honest wording):** the
RNG draw stream + the `_sample_z` golden are UNTOUCHED (gnss.jl adds no code to the radar/detection path);
DF **pseudolinear** is byte-identical (cofactor unchanged); DF **`:ml`** now routes through the Cholesky
`_solve_normal` at N=2 (cofactor vs sqrt-Cholesky are equal to ULP, not bit-for-bit — `test_determinism`
compares run-A-vs-B on the same code so it stays green; the value tests are atol/inequality). New
`gnss.jl` (pure §9-style lib, defines `GPS_TOGGLE=(:off,:on)`/`RAIM_MODES=(:off,:detect,:exclude)` the
one-list source-of-truth `LIVE_FIDELITY_MODES` will reference — so gnss.jl precedes radar.jl in the
include order; reuses geometry/estimation, both already before radar): `pseudorange(sat,rx,cb;…)` =
`‖sat−rx‖ + c·b + clock_err + fault_bias + iono + tropo + mp + noise` (a PURE sum — the terms arrive
already-toggled + the stochastic mp/noise already-drawn, so gnss.jl stays RNG-free; the draw lives in
gate-2 `observe!`); `position_fix(sat_positions,rho;seed,cb0,iters)` CALLS the generalized `gauss_newton`
at N=4 (residual `rⱼ=ρⱼ−(‖pⱼ−p̂‖+ĉb)`, Jacobian row `Hⱼ=[−ûⱼ,1]` the classical GPS geometry matrix, the DF
`[sinθ,−cosθ]` cousin) + returns `(pos,cb,Q,singular)`; the five error-term models (`iono_delay`/
`tropo_delay` = deterministic elevation obliquity `zenith/sin(el)`, NOT Klobuchar/Saastamoinen; `mp_scale`
= the multipath elevation weight; clock_err = per-SV constant; all NAMED approximations) + `sat_az_el`
(sky geometry). **RAIM (the empirical-σ-multiple threshold — route (iii), the gate-1 probe DECISION):**
`raim_statistic = √(SSE/(n−4))` (σ-normalized → dimensionless, E≈1 under H0), `raim_suspect` (largest
normalized residual = the real single-fault ID), `raim_solve(…;mode,threshold)` (`:off` never flags /
`:detect` flags stat>T / `:exclude` drops the suspect + re-solves keeping ≥4 → snap-back). The χ²/Pfa
route was REJECTED: exclude drops n=6→5 (dof 2→1, odd → needs an erf-based χ² inverse the project has
avoided for 6 slices); the empirical threshold works at every DOF + matches the probe-tune discipline
(tune `k≈3–5` against the NOISY stat at gate 3 — the probe's noise-free stats are pure fault signal, ~1.0
H0 floor underneath — advisor). **VDOP>HDOP holds on the shipped upper-hemisphere layout** (a placement
property, pinned per-layout, NOT universal). `test_gnss.jl` (+70, wired after test_estimation): noise-free
fix==truth (exactly-4 AND over-determined); the **§9 reuse pin** (`_solve_normal` N=2 == `_solve2x2`);
**DOP decomposition vs an INDEPENDENT `_inv4` Gauss-Jordan recompute** (a different algorithm than the
Cholesky under test — the slice-2 oracle rule) + VDOP>HDOP + the decomposition identities; **σ-invariance**
(MC own Xoshiro: RMS_pos ∝ σ [ratio 2.000] while PDOP is a fixed number, RMS/σ≈PDOP); the **error budget —
all FIVE terms** (iono raises cb [clock absorbs the +delay, known sign] + grows pos err; per-SV clock_err
biases the fix; tropo obliquity sign+exactness; mp_scale worse-at-low-el; multipath+noise MC variance
∝ σ, own Xoshiro); **RAIM detect/ID/exclude/off** (fault ID picks the RIGHT satellite — the real step, not
tuned; exclude recovers truth <1e-4; `:off` never flags; **n=4 dof 0 is BLIND** — over-determination
required); **singular→FINITE_CEIL EXACTLY** (<4 sats AND a coplanar az=0 constellation, no throw); **units
ns round-trip** (the §1 metres-vs-seconds clock trifecta — `c·b` metres internal, ns at the boundary).
Slices 1–6 green through the include.

Gate 2 (the GPS pipeline wired — phases 2+3+4 lit, the §9 reuse in the tick loop; DONE & green, 1448
tests, +140): new `gps.jl` (included AFTER geolocation.jl, mirroring esm.jl/geolocation.jl; NO back-dep on
radar symbols — reuses geometry.jl's `_finite`/`FINITE_CEIL`, geolocation.jl's `_finite_coord`, gnss.jl's
pure math) lights `build_env!` + `observe!` + `decide!` in ONE chain through `w.env` a THIRD time (after
jammer→radar, DFSensor→Geolocator, emitter→ESM→deinterleaver — the §9 cross-domain reuse, not a phase
first). `GpsSatellite.build_env!` (phase 2) publishes an `EphemerisRecord`-shaped `SatEphemeris`
(`id`/`pos`/`clock_err`/`fault_bias`, SI metres) into `env[:gps_sats]` (RNG-free, sorted-id append).
`GpsReceiver.observe!` (phase 3 — **THE ONE DRAW SITE**) reads `env[:gps_sats]` and on a look-tick
(`next_look_t`/`revisit_s` gate) generates + measures the pseudorange vector into `env[:pseudoranges]` (a
`PseudorangeSet`: sat_ids + positions + measured ρ + a `visible` elevation-mask flag). `GpsSolver.decide!`
(phase 4) reads the set, filters to VISIBLE sats, runs `raim_solve` (dispatching `get(w.fidelity,:raim,
:off)` — internally `position_fix` at N=4 [the §9 shared `gauss_newton`] + `dop_components` + RAIM), and
publishes the fix/DOP/RAIM telemetry. **Exact §1 draw order pinned bit-for-bit** (`_draw_pseudoranges`,
reconstructed MANUALLY off a fresh `Xoshiro` in test_gps.jl, independent of the receiver): satellites
sorted-id → per satellite MULTIPATH(`randn`) THEN NOISE(`randn`), both UNCONDITIONAL → total `2·n_sats`,
FIXED regardless of any fidelity key AND slider value. The five error toggles gate the CONTRIBUTION (0.0
when off, no draw for the deterministic iono/tropo/clock); the elevation mask, RAIM exclusion, and any live
dropout are ALL POST-DRAW filters on which measurements enter the SOLVE — never gates on the DRAW. So
**NO draw-topology hazard** anywhere (the slice-2/4/5/6 shape) → all six keys (`iono/tropo/clock/multipath/
noise`=`GPS_TOGGLE`, `raim`=`RAIM_MODES`) are introduce-safe AND toggle-bit-identical (the `:ep`/
`:estimator`/`:deinterleaver` contract, NOT slice-3's `:cfar` guard). `LIVE_FIDELITY_MODES` (radar.jl)
REFERENCES `GPS_TOGGLE`/`RAIM_MODES` (one-list-no-drift); the six keys are **generic words namespaced BY
CONSUMPTION** — only a GpsSolver reads them (the `:estimator`-without-a-Geolocator precedent), so a non-GPS
scenario toggling one is a harmless no-op. **Deviation from the plan landmark (advisor-affirmed): the
receiver comp key is `raim_threshold` (an empirical σ-multiple), NOT the stale `pfa_raim`** — gate 1 chose
route (iii) [χ²/Pfa rejected: exclude→odd-DOF needs an erf], so the slider/solver share `raim_threshold`
(a `pfa_raim` would be a dead comp key `_parse_knobs` guards against). GPS DOP is FIX-geometry `Q` (the
gnss.jl convention; ≈ truth-geometry at 20 000 km range, σ-invariant by construction — unit weights). The
solver clamps EVERY scalar finite (`_finite`/`_finite_coord`, ceiling `FINITE_CEIL`) so a singular/under-
determined geometry (< 4 visible / coplanar / RAIM into < 4) ships huge-but-finite, never Inf/NaN, never a
throw (the "a live config can't crash a tick" watch-item). Telemetry: SCALARS `pos_err_m`/`fix_x`/`fix_y`/
`fix_z`/`clock_bias_ns` (c·b metres→ns, the §1 boundary)/`gdop`/`pdop`/`hdop`/`vdop`/`tdop`/`raim_stat`/
`raim_flag`/`n_sats_used`/`fault_sat` (the excluded satellite's CONFIGURED index)/`protection_level_m`
(crude `thr·σ·PDOP` proxy, named) + DISPLAY ARRAYS `sat_az_deg`/`sat_el_deg`/`sat_resid_m`/`sat_used`
(NEVER asserted). `scenario.jl`: `:gps_satellite` (`clock_err_m`/`fault_bias_m` — fault_bias_m the RAIM
slider key) + `:gps_receiver` (`sigma_range_m`/`sigma_mp_m`/`iono_zenith_m`/`tropo_zenith_m`/`clock_bias_m`/
`elevation_mask_deg`/`raim_threshold`) kinds + `_validate_gps` (≥ 4 satellites + exactly 1 receiver at
LOAD, GPS-presence-triggered so a non-GPS scenario is untouched; the RAIM ≥ 5 over-determination is the
scene's authoring responsibility); unknown-kind list updated. `test_gps.jl` (+109, the test_esm/
test_geolocation analog): env populated + record shape; the EXACT-draw golden; solver reproduces
`raim_solve`/`dop_components` on the realized ρ + VDOP>HDOP; the six-key fidelity plumbing (each error
toggle enters the pos_err budget, raim off/detect/exclude, n_sats_used drops under `:exclude`); **the
masked-AND-excluded index mapping** — `vis_idx≠1:n` pinned against an INDEPENDENT raim_solve+map (the
advisor bug: `sat_used[k]=res.used[k]` forgetting the vis→config map; the crude largest-residual RAIM ID
[a named approximation] is geometry-dependent so this test checks the SOLVER'S BOOKKEEPING, not ID
accuracy — correct-ID exclusion is pinned on the standard 6-sat layout in the six-key test); wire JSON
round-trip; **draw invariance across ALL SIX keys** (rng lockstep — toggling any key advances w.rng
identically); degenerate all-but-one-masked → FINITE_CEIL, no throw; no-GPS byte-identity (wire surface);
loader arms + rejects. `test_determinism.jl` + a slice-7 scenario (bit-identical PSEUDORANGE trace via
`reinterpret`; draw-free rung switch off↔exclude [n_sats_used 6↔5, not a dead knob]; toggle AND introduce
of each of the six keys → rng end-state bit-identical — **NB the ρ VALUES change with an error toggle [the
contribution enters], the DRAW COUNT does not, so the invariant pinned is the rng state, not the ρ
stream**). `test_server.jl` (six-key `set_fidelity` write/reject + introduce-safe on a non-GPS scenario;
warmup! tolerates a radar-free GPS scenario — the ROC batch is skipped, the tick!+state_frame warm covers
the phase-2+3+4 §9 pipeline + display-array round-trip). Slices 1–6 byte-identical (gps.jl adds no code to
the radar/detection path; the `_sample_z` golden + all prior testsets green through the include). Server
handshake (no `_gps_axis_info` — the satellites MOVE, so unlike CFAR's `range_axis_m` / ESM's `pri_axis_us`
there is no static axis; the gate-3 GPS-view discriminator is `raim ∈ fidelity`), the scenario YAMLs, the
Godot GPS/sky view, and the verifier are all deferred to gate 3.

Gate 3 (two scenarios + Godot GPS view + verifiers — **DONE & green, 1492 tests (+44); wire + UI
machine-verified AND `_draw_gps` VISUALLY CONFIRMED 2026-07-01**). The core fidelity plumbing + the
`test_server.jl` GPS arms (six-key `set_fidelity` write/reject + introduce-safe + GPS-free warmup) landed in
**gate 2**, so gate 3 = the scenarios + client + verifiers + loader tests — **NO `core/src/*.jl` change**, so
slices 1–6 are byte-identical *structurally* (the diff is `Sandbox.gd` + `test_scenario.jl` + four new files
only; the `_sample_z` golden untouched — stronger than "tests still pass"). `scenarios/slice7_dop.yaml` (6-sat
upper-hemisphere spread, DISTINCT per-SV clock errors, sv2+sv4 drift climbing to zenith → GDOP sweeps 3.05→4.57
over ~8 s; iono+tropo+noise default; **raim:off present = the GPS-view discriminator**, the range_axis_m→cfar /
estimator→geoloc precedent) + `scenarios/slice7_raim.yaml` (6 sats, sv3 faulted 100 m, raim:detect default so
the flag is up on connect, fault_bias_m slider). **Numbers PROBED against the LIVE
build_env!→observe!→decide! wire path** (the slice-3/4/5/6 rule) + reproduced through the loader. **The
advisor's error-budget trap baked in:** a common-mode range bias is absorbed by the receiver clock `c·b`, so
DISTINCT per-SV clock errors (the `clock` toggle moves pos_err 11.1→43.6) + elevation-DIFFERENTIAL iono/tropo
are what corrupt POSITION (a lot else lands in `clock_bias_ns`) — the verifier toggles `clock` (the biggest
lever; each of the five terms is unit-pinned in gate-2 `test_gps.jl`). Godot `Sandbox.gd`: a NEW `"gps"` render
mode (`_enter_gps_mode` off `raim ∈ fidelity`); `_draw_gps` = a polar SKY PLOT (zenith center / horizon edge,
satellites colored in-solve green / masked-excluded grey / faulted orange — the geometry→DOP visual) + a
per-satellite RESIDUAL bar chart (the spoofed sat's bar SPIKES — the RAIM signature), ALL telemetry; the
DOP/RAIM scalars render in the left readout (`_update_readout` skips the sat_* arrays — the slice-3/6
float()-crash watch-item, re-confirmed). The shared fidelity button becomes the raim cycler
(off→detect→exclude); the **NEW five-error-toggle button ROW** (`_gps_toggle_btns` — the one genuinely new
client-UI element, advisor: five toggles not a cycler) + the fault slider. A gps-specific left inset
(`GPS_PLOT_L`) clears the tall readout panel. The slice-1..6 views are UNTOUCHED (all their UI tests re-run
green). `net/slice7_verify.gd` (drives the real server over BOTH scenarios: DOP finite + decomposes
gdop²=pdop²+tdop² / pdop²=hdop²+vdop², **VDOP>HDOP** on the shipped layout, **sweeps 3.05→4.55 with the drift**;
the `clock` toggle moves pos_err [bit-identical t, draw-held]; then `load_scenario slice7_raim`: the fault
slider raises `raim_flag` at the crossover [20 m→flag 0, 120 m→flag 1, bit-identical t — the not-a-dead-knob];
`set_fidelity raim exclude` DROPS `n_sats_used` 6→5, `fault_sat`=3, and COLLAPSES `pos_err_m` 211.9→5.6 [the
snap-back] — all on the SCALARS, never the display arrays. `S7V OK`, exit 0). **Verifier mechanics:** step
counts are MULTIPLES of `emit_every` (16) so the LAST emit of a burst lands exactly on the target t (the
slice-2/6 drain contract — an off-multiple count leaves the last frame short and the drain times out; this bit
the first run). `net/slice7_ui_test.gd` (mock client, no server: handshake → gps mode + the raim cycler; the
ring walks off→detect→exclude and wraps; the five error toggles each send `set_fidelity` + flip via the
`.bind(term)` wiring; the fault slider sends `set_param`; reset resyncs the rung + toggles to defaults —
`S7UI OK`). `Sandbox.tscn` smoke-loaded headless against BOTH slice-7 servers (server `DONE` ⇒ scene connected
on the gps branch, no GDScript errors — catches gps-branch parse bugs the SimClient verifier can't).
`test_scenario.jl` +2 loader testsets (both loaders: GPS fidelity defaults, NO radar/jammer/DF/ESM fidelity or
entities, ≥4 sats [≥5 for RAIM], one receiver, DISTINCT per-SV clock errors [the `clock`-corrupts-position
premise], fault_bias stored SI METRES [`haskey :fault_bias_m` the discriminating unit check], error keys not
knobs, the fault slider addresses `:fault_bias_m`). The `_draw_gps` PIXEL branch (Godot skips `_draw` headless)
VISUALLY CONFIRMED via 3 windowed shots (the shot harness, [[ewsim-godot-headless]] — a throwaway ShotGps
wrapper pointed `run/main_scene` at itself, reverted after): **DOP** = a spread green constellation + the DOP
readout (VDOP>HDOP); **RAIM-detect** = raim_flag 1 + pos_err 209 + the sv3 residual tallest; **RAIM-exclude** =
sv3 ORANGE (excluded) + the isolated residual spike (max |r| = 101 m) + n_sats_used 5 + pos_err collapsed
209→5.9 — the RAIM lesson as a picture. **Showcase note:** the DOP drift is tuned for an ~8 s good→bad sweep;
a longer live run keeps clustering toward a near-singular constellation (readout → `FINITE_CEIL`) — reset to
replay. No open step remains in slice 7's required gates. **(stretch, deferred)** offline `batch.jl`
`kind=:dop_mc`/`:raim_roc` + `clients/notebooks/slice7_gps.jl` Pluto.

Run the slice-7 showcase: `julia --project=core tools/server.jl scenarios/slice7_dop.yaml` (or
`scenarios/slice7_raim.yaml`), then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects GPS
and shows the sky/residual view; toggle the five error terms to watch the error budget breathe, cycle the
`raim:` button to raise the integrity flag / snap the fix back, drag the fault-bias slider across the
detection threshold). Re-run the gate-3 proof headless: start that server, then `godot --headless --path
clients/godot --script res://net/slice7_verify.gd` (exit 0 = pass; it `load_scenario`s slice7_raim itself, so
launch it against the slice7_dop server). The UI test needs NO server: `godot --headless --path clients/godot
--script res://net/slice7_ui_test.gd`. All 1492 tests: `pwsh tools/test.ps1`.

## Slice 8 — ballistic missile — the force integrator + frames.jl

**Slice 8 — missile (ballistic): the airframe integrator + `frames.jl`** (HANDOFF §10 item 8, the first
slice of the missile-guidance arc) — **COMPLETE. Gates 1–3 done & green (1633 tests); wire + UI
machine-verified AND the missile spatial-view `_draw` VISUALLY CONFIRMED (2026-07-01).** Planned FULL in
`docs/plans/slice8.md` (3 gates: pure primitives → the `BallisticMissile` subsystem wired [phase 1, the
first FORCE-based integrator] → scenario + Godot spatial-view extension + verifiers). The slice pays down
two infra debts: the Newtonian ODE integrator (forces→accel→vel→pos) and the 3-D `frames.jl` shared lib
(slices 9–13 ride it). **Deterministic — NO RNG anywhere** (the trajectory is a closed-form ODE solve), so
unlike every prior slice there is no draw stream: the `integrator` fidelity is a **physics-changing** knob
(slice-2 `propagation` shape), NOT a slice-5/6/7 toggle-bit-identical rung — do NOT copy that language.

Gate 1 (pure primitives green — closed-form, SI, RNG-free, no LinearAlgebra): two NEW files, BOTH included
before `radar.jl` (the mode-const-before-radar rule). **`frames.jl`** — the §9 3-D quaternion/frame/LOS
kernel (the `geometry.jl`/`estimation.jl`/`gnss.jl` analog): `qmul`/`qconj`/`qinv`/`qnormalize`/
`quat_from_axis_angle`/`quat_from_two_vectors` (with the **antiparallel + zero-vector guards** an apex v→0
hits), `rotate`/`rotate_inv` (the inertial↔body pair), `los_unit`/`los_range`/`range_rate`/`los_rate`/
`az_el`. Reuses gnss.jl's module-level `_norm3` (precompile forbids re-defining it), adds `_dot`/`_cross`;
`los_range` is named (not bare `range`) to avoid shadowing `Base.range`. Built fully 3-D + tested 3-D now
(the slices-10–13 investment), scoped tight — **`geometry.jl` NOT refactored** (its 2-D `bearing`/`wrap_angle`
stay byte-identical; `frames.jl` is the 3-D superset, conceptually shared not code-merged — the slice-7
"keep the shipped 2×2 path" discipline), proven by the **azimuth == `bearing`** §9 pin. **`dynamics.jl`** —
the airframe force model + steppers (the plan's "small dynamics.jl" option, **resolving a plan
contradiction**: `INTEGRATOR_MODES` must precede radar.jl for `LIVE_FIDELITY_MODES` to reference it, but the
sketch put it in the after-radar `missile.jl`; the split — pure lib before radar, subsystem after — matches
the deinterleave→esm / gnss→gps convention exactly): `gravity_accel` (flat-earth constant `[0,0,−g]`,
g=9.80665), `drag_accel` (quadratic, constant ρ, drag off = `cd_area=0` → **EXACTLY zero**), `total_accel`
(= gravity + drag, a function of v only), pure `rk4_step`/`euler_step`/`integrator_step` (`(accel,p,v,dt)→
(p',v')` closures), and `INTEGRATOR_MODES=(:rk4,:euler)` the one-list source of truth. **ROADMAP DEVIATION
NAMED** (advisor #3): HANDOFF §10 sketches `airframe=point_mass|6dof`, but 6-DOF is deferred (§11 Tier A) and
a one-value fidelity is a dead button, so the slice-8 fidelity is the INTEGRATOR METHOD (RK4 exact vs Euler
bowing); airframe stays implicitly point_mass. All named approximations (flat-earth constant g, constant ρ,
point-mass, lumped Cd·A, passive body) in docstrings. `test_frames.jl` (43) + `test_missile.jl` (27), wired
into `runtests.jl` after `test_estimation.jl`, explicit `atol` throughout: **frames** — quaternion
round-trips (`rotate_inv(q,rotate(q,v))==v`), 90°-about-ẑ SIGN-checked (x̂→ŷ, ŷ→−x̂), `quat_from_two_vectors`
aligns a→b + both guards, the **LOS-rate SIGN** on a concrete left→right crossing (ω=+ẑ, value 0.05 — not
just magnitude, the #1 "missile flies away" bug), `range_rate` sign (negative=closing), the azimuth==`bearing`
§9 pin; **missile** — drag-off EXACTLY zero, **RK4 gravity-only == analytic parabola** (rtol 1e-11, the
headline — RK4 integrates the degree-2 solution exactly), **Euler position error EXACTLY `½·g·dt·t`** (the
error is analytically exact for constant accel, not just leading-order) + O(dt) at FIXED final time (holding
n fixed instead gives ÷4 and masks the order — the bug the first run caught), **convergence order ÷16 RK4 /
÷2 Euler** measured in a COARSE-dt STRONG-drag regime (on the pure parabola RK4 truncation is ZERO → only
roundoff remains, which won't halve — the subtle reason the convergence test can't use gravity-only), energy
(RK4 drag-off conserves to machine eps [4e-14], drag-on strictly DECREASES [Ė=−k‖v‖³<0]), degenerate guards
(straight-up v→0 apex, launch at z=0 integrates upward, huge dt — no throw/NaN). **Probe decisions** (a
throwaway harness, the slice-3..7 rule): Euler drift is dramatically visible (2.1 m z-lag at dt=0.01 over a
43 s flight); **`:semi_implicit` REJECTED** — two rungs suffice (Euler = the position-error lesson, RK4 = the
exact reference); Euler drag-off energy drifts UPWARD (~+0.05%, phase-dependent) → PROBED as a comment, NOT
asserted (the "don't assert what you haven't measured" discipline). Slices 1–7 **byte-identical** (frames/
dynamics add no code to the radar/detection path; the `_sample_z` golden + `test_determinism` [53] green
through the include).

Gate 2 (the `BallisticMissile` subsystem wired — phase 1, the FIRST force-based integrator in the tick loop;
**DONE & green, 1609 tests, +47**). New `missile.jl` (included after `gps.jl`, before `scenario.jl`; **NO
radar back-dep** — grep-confirmed, reuses only `dynamics.jl` [`total_accel`/`integrator_step`/
`INTEGRATOR_MODES`/`G_ACCEL`] + `frames.jl` [`quat_from_two_vectors`] + gnss's `_norm3` + geometry's
`_finite`/`_finite_coord`). `BallisticMissile.integrate!` (phase 1) dispatches `get(w.fidelity, :integrator,
:rk4)` → `integrator_step` under `total_accel`, does the `z≤0` impact clamp (within-`dt`, named approx) +
one-shot `:impact` event (pushed to `w.events` — NOT env, so `empty!(w.env)` can't wipe it) + `:impacted`
latch (frozen splash, subsequent ticks no-op), and sets a velocity-aligned `att` (`quat_from_two_vectors(
[1,0,0], v′)` — the FIRST live use of `frames.jl`, hitting its apex `v→0` zero-vector guard → identity).
**TELEMETRY-PHASE DEVIATION, NAMED (advisor): the plan sketch's "phase-1 writes into env[:telemetry]" is
WRONG — `tick!` calls `empty!(w.env)` immediately AFTER phase 1, wiping any phase-1 telemetry (and the radar
readout is actually phase-3 observe!, post-empty!). So the missile's energy/position readout is published
from `build_env!` (phase 2, post-empty!, reading the post-integrate state) — a DERIVED quantity, RNG-free,
own-keys → order-independent; observe!/decide! stay EMPTY for the guidance/seeker slices 9–11.** Telemetry
(all `_finite`/`_finite_coord`-clamped): `<id>.pos_x/.pos_z/.speed/.alt/.ke_j/.pe_j/.e_total_j/.de_frac/
.impacted`; `E₀` (the ΔE reference) lazily set on the first tick from the launch state (survives reset for
free). **`de_frac = −1` at impact** (KE=PE=0 at rest) is a discontinuity — the gate-3 verifier must sample ΔE
MID-FLIGHT, not post-impact. `LIVE_FIDELITY_MODES += integrator = INTEGRATOR_MODES` (references dynamics.jl's
const — one-list-no-drift). **`:integrator` is introduce-safe (NO `:cfar`-style guard — absent a `:missile`
nothing reads it) BUT PHYSICS-CHANGING, NOT toggle-bit-identical (advisor #1 — the one place the slice-5/6/7
template gives a FALSE claim): there is no RNG in slice 8, so "draw-count-invariance" is VACUOUS, and a
rk4↔euler toggle CHANGES the trajectory (the slice-2 `propagation` shape). Introduce-safe ≠ toggle-invariant
— the comment states the split.** `scenario.jl`: `:missile` kind (`missile:` block → `mass_kg`,
`speed`/`elevation_deg` [deg→rad → x-z-plane `vel`; stored RAW too so gate-3 launch knobs can address them],
`cd_area_m2` [drag off = 0], optional `rho`; positive-mass / non-negative cd_area/ρ rejected at LOAD) + the
entity gets `[BallisticMissile]` **NOT** `ConstantVelocity` (the double-integration guard — two phase-1
movers would advance `pos` twice) + `_validate_missile` (presence-triggered ≥1 missile) + unknown-kind list
updated. Tests: `test_missile.jl` wired half (+20: integrate! == the gate-1 stepper bit-exact [rk4 AND
euler]; rk4 WIRED == analytic parabola / euler bows by ½·g·dt·t / the two trajectories differ [live rung];
impact fires ONCE + freezes [z=0, v=0] + no-op after / a launch at z=0 with upward v RISES not insta-impacts;
energy telemetry == ½m‖v‖²+mgz every step + ΔE<1e-10 rk4 drag-off + ΔE<0 drag-on; finite telemetry +
att-never-NaN through the apex; loader gets BallisticMissile NOT ConstantVelocity + rejects missing mass /
negative cd_area); `test_determinism.jl` (+1 testset — the THREE claims pinned DISTINCTLY, no vacuous
rng-lockstep: (2) same-config replay bit-identical via `reinterpret`; (3) a mid-run rk4→euler toggle CHANGES
the flight [the not-a-dead-knob — the slice-5/6/7 OPPOSITE]; (1) introduce `:integrator` on a NON-missile
RandomWalker world → byte-identical + rng stream untouched); `test_server.jl` (+2: `set_fidelity integrator`
write/reject [bad rung rejected before landing] + introduce-safe on a plain radar scenario; `warmup!`
tolerates a radar-free missile scenario — the ROC batch is skipped, the phase-1 integrator + phase-2 energy
telemetry are warmed, the live World left pristine). Slices 1–7 **byte-identical** (missile.jl adds no code to
the radar/detection path; the `_sample_z` golden + all prior testsets green through the include).

Gate 3 (scenario + Godot spatial-view extension + verifiers — **DONE & green, 1633 tests (+24); wire + UI
machine-verified AND `_draw` VISUALLY CONFIRMED 2026-07-01**). NO `core/src/*.jl` change — the diff is
`Sandbox.gd` + `test_scenario.jl` + three new files, so slices 1–7 are byte-identical *structurally* (the
`_sample_z` golden untouched). `scenarios/slice8_ballistic.yaml` (seed 8): a single projectile launched from
the origin at 250 m/s / 45° in the x-z plane (mass 10 kg, cd_area 0 = DRAG OFF, ρ 1.225), `integrator: rk4`
default. Numbers PROBED against the live `integrate!→build_env!` wire path (the slice-3..7 rule) + pinned in
the verifier: drag-off rk4 T≈36.05 s, apex≈1593 m, range≈6373 m; `de_frac`@8s ≈ −5.5e-14 (rk4, machine eps)
vs ≈ +1.2e-5 (euler, ratio 2.2e8); cd=0.02 → `de_frac` −0.79 / range 1211 m. **The euler lesson rides the ΔE
READOUT, not the trajectory shape (advisor #1): the parabola bow is INHERENTLY sub-pixel (bowing/apex =
2·g·dt/v₀z, so any legible arc kills the relative bend, ~1 px here) — so `_update_readout` now routes float
scalars through the client's scientific `_fmt` (the Pfa-slider widget) so a tiny-but-nonzero `de_frac` reads
truthfully instead of rounding to "0.00" = a dead button (the rk4 shot CAPTURES `de_frac −3.7e-14`; the euler
figure ≈ +1.2e-5 is verifier/probe-derived — the shot harness was reverted before an euler capture, but `_fmt`
renders the same scientific form either way).** The prior slice-1..7 UI tests re-run green after this shared
`_update_readout` edit (no test asserts `_readout.text`; the change only widens tiny/near-integer formatting). **dt kept at 1e-3 / emit_every 16 (NOT
coarsened): RK4 is exact for the parabola at ANY dt, and at dt≥0.02 the sub-ms REALTIME `wall_dt` rounds to 0
steps/iter and playback stalls — so the standard slice-1..7 cadence is kept, `_fmt` alone carries euler.**
**LAUNCH GEOMETRY IS LOAD-TIME STATIC (gate-2 carry-over (a), VERIFIED at gate 3): `reset`→`_reload!`
reloads the YAML FILE (discarding any `set_param` to speed/elevation) and nothing re-derives `vel` mid-flight
(re-launching an airborne body is ill-defined), so ONLY `cd_area_m2` is a working live slider (the drag/
energy-bleed lever — well-defined mid-flight, the server reads it every step); launch speed/elevation are
edit-YAML-and-reconnect.** `integrator` is PHYSICS-CHANGING, NOT toggle-bit-identical (there is no RNG; a
rk4↔euler toggle CHANGES the trajectory — the slice-2 `propagation` shape, the OPPOSITE of slice-5/6/7).
Godot `Sandbox.gd`: **NO new render mode — the EXISTING spatial/elevation view EXTENDED** (the slice-4
"stay spatial" precedent). The handshake fidelity carrying `integrator` (and NO range_axis_m / pri_axis_us /
estimator / raim) is the discriminator: `_setup_spatial_fid_btn` sets `_fid_kind="missile"`, wires the shared
button to `_on_integrator_pressed` (the rk4↔euler ring, guarded disconnect like cfar/ep/est/deint/raim), and
seeds SMALL elevation-view extents (the radar defaults 45 km × 5 km only grow → a 6 km arc would render
cramped; advisor #2) that grow to fit. `_draw_spatial` gains a `_draw_missile` arm: a fading trajectory trail
(WORLD breadcrumbs mapped each draw so they survive the auto-expanding extents), a nose-oriented marker
(orientation off the last trail segment), and an orange impact BURST at the `<id>.impacted` ground crossing —
all telemetry / entity pos. The slice-1..7 render paths are UNTOUCHED (their six UI tests re-run green after the
shared `_update_readout`/`_fmt` edit — none asserts `_readout.text`).
`net/slice8_verify.gd` (drives the real server: handshake ships `integrator:rk4` + the cd_area slider + no
range/pri axis; PARABOLA — rk4 drag-off `de_frac`≈0 at a MID-FLIGHT t=8 s [carry-over (b): sample mid-flight,
`de_frac=−1` at rest]; EULER — reset + `set_fidelity integrator euler` → `de_frac` jumps orders above rk4 at a
bit-identical t [MAGNITUDE not sign — euler energy is phase-dependent]; DRAG — reset + `set_param cd_area_m2
0.02` → `de_frac` clearly negative + arc lower; IMPACT — step PAST T, accumulate the one-shot `:impact` events
across the drained burst [the slice-6/7 pattern] → exactly ONE + `impacted` latches + speed 0). `S8V OK`,
exit 0. `net/slice8_ui_test.gd` (mock client, no server: an `integrator` handshake STAYS spatial + wires the
integrator cycler; the ring walks rk4→euler and wraps; badge/button track; the cd_area slider sends set_param;
reset resyncs to rk4 — `S8UI OK`). `Sandbox.tscn` smoke-loaded headless against the slice-8 server (server
`DONE` ⇒ scene connected on the missile branch, no GDScript errors — caught a `%g`/`%e` format bug in the
verifier the smoke-load class always flags). `test_scenario.jl` +1 loader testset (integrator default rk4, NO
other fidelity/entities, exactly one `:missile` with `BallisticMissile` and **NOT** `ConstantVelocity` [the
double-integration discriminating check], launch state deg→rad pinned [`vel_x=vel_z=250·cos45°`, `vel_y=0`],
raw speed/elevation stored, cd_area the ONE knob, integrator/speed/elevation NOT knobs). The `_draw` missile
PIXEL branch (Godot skips `_draw` headless) VISUALLY CONFIRMED via 3 windowed shots (the shot harness,
[[ewsim-godot-headless]] — a throwaway ShotMissile wrapper pointed a positional scene arg at itself against the
live server, `get_viewport().get_texture().get_image().save_png`, reverted after): **rk4 mid-flight** = the
climbing arc + nose marker + energy readout (`de_frac −3.7e-14` via `_fmt`, `e_total 312500` constant);
**rk4 impact** = the full SYMMETRIC parabola + orange burst at range 6373 m (`impacted YES`, `de_frac −1`);
**drag** = a SHORTENED, ASYMMETRIC arc (steeper descent) impacting at 1247 m (~5× shorter) — the energy-
dissipation lesson as a picture. No open step remains in slice 8's required gates. **(stretch, deferred)**
`clients/notebooks/slice8_energy.jl` Pluto E(t) rk4-vs-euler overlay + an offline `batch.jl` `:dispersion`
Monte-Carlo launch-scatter (the first RNG in the missile arc).

Run the slice-8 showcase: `julia --project=core tools/server.jl scenarios/slice8_ballistic.yaml`, then launch
Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `integrator:` button to
watch the ΔE readout drift off zero under euler; drag the `cd_area` slider to bleed energy and shorten the arc;
the missile emits an `:impact` burst and freezes at z=0). Re-run the gate-3 proof headless: start that server,
then `godot --headless --path clients/godot --script res://net/slice8_verify.gd` (exit 0 = pass; serves one
client then exits). The UI test needs NO server: `godot --headless --path clients/godot --script
res://net/slice8_ui_test.gd`. All 1633 tests: `pwsh tools/test.ps1`.

## Slice 9 — the PID autopilot under a pursuit outer law

**Slice 9 — missile: the PID autopilot (inner loop) under a pursuit outer law** (HANDOFF §10 item 9, the
SECOND slice of the missile-guidance arc) — **COMPLETE. Gates 1–3 done & green (1723 tests); wire + UI
machine-verified AND the guided-missile spatial `_draw` VISUALLY CONFIRMED (2026-07-01).** The missile's
FIRST closed control loop + its FIRST `decide!` (phase 4 — the phase slice 5 lit for the DF Geolocator):
"a missile is `integrate!` (airframe) + `observe!` (seeker) + `decide!` (guidance)". A CASCADE — an OUTER
pursuit law (the honest tail-chaser stand-in slice 10 replaces with PN) commanding a lateral accel, closed
by an INNER PID autopilot through a first-order airframe lag. **The lesson is the tracking GAP (commanded
vs achieved accel), NOT miss distance** (miss conflates guidance + autopilot — advisor): dial `autopilot ∈
(:ideal, :pid)` and watch `track_gap` open/close. Fidelity is PHYSICS-CHANGING (the slice-2/8 shape — a
toggle CHANGES the trajectory), NOT a slice-5/6/7 toggle-bit-identical rung; there is NO RNG in the missile
arc. Deferred: proportional navigation + the `:guidance` fidelity (slice 10 — the key is RESERVED, unused),
g-limit-saturation-AS-LESSON (slice 10; slice 9 keeps a generous a_max crash-guard tuned to never bind),
noisy seekers (slice 11 — guidance reads TARGET TRUTH), 6-DOF (§11 Tier A — the lag is a lumped scalar).
Planned FULL in `docs/plans/slice9.md` (3 gates: pure primitives → the Autopilot wired → scenario + client
+ verifiers).

Gate 1 (primitives green — pure, closed-form, SI, RNG-free, no LinearAlgebra): new `guidance.jl` (the
dynamics.jl/frames.jl analog), included AFTER frames.jl (reuses `los_unit`/`_norm3`/`_dot`) but BEFORE
radar.jl (so `AUTOPILOT_MODES` precedes `LIVE_FIDELITY_MODES` — the mode-const-before-radar precedent). Two
SEPARATE pure functions SO slice 10 swaps ONLY the outer one: `pursuit_accel(m_pos, m_vel, t_pos; k_guid)`
→ a lateral accel ⟂ to heading steering `v` toward the LOS (a tail-chaser — `‖a_cmd‖` GROWS toward
intercept, the slice-10 tee-up); `autopilot_step(mode, a_cmd, state, dt; kp, ki, kd, tau)` → `(a_ach,
state′)` — `:ideal` bit-exact passthrough, `:pid` a first-order plant `τ·ȧ = u − a` closed by a PID on the
accel error `e = a_cmd − a_ach` (derivative-ON-ERROR, `τ→0` guarded). PID state is a Vec3 NamedTuple
`(a_ach, e_int, e_prev)` (pure — returns fresh state). `clamp_accel(a, a_max)` the crash-guard (zero-safe
AND non-finite-safe — the designated guard can't itself emit NaN, advisor). `AUTOPILOT_MODES=(:ideal,:pid)`
the one-list source of truth. `test_guidance.jl` (+26): **the `1/(1+Kp)` steady-state undershoot headline**
pinned `Kp=2→1/3`, `Kp=8→1/9` to atol (the Euler plant preserves the exact continuous fixed point
`a*=Kp/(1+Kp)·a_cmd` — confirmed 0.333333/0.111111); integral drives e_ss→0; **derivative damps the
integral-induced ringing** (the ordering anchor at Ki=40, real 27% overshoot 127→123 — at LOW Ki the naive
derivative-on-error first-step KICK would dominate, the honest boundary); `:ideal` bit-exact passthrough;
pursuit ⟂-to-v + LOS-side SIGN + the tail-chase growth; clamp + degenerate guards. Slices 1–8 byte-identical
(the `_sample_z` golden + `test_determinism` green through the include).

Gate 2 (the Autopilot wired — phase 4, the closed loop; +9 tests over gate 1's tally). `Autopilot <:
Subsystem` (missile.jl, after radar.jl — NO radar back-dep beyond the reused `_nearest_target`). It
implements `integrate!` ONLY to stash the tick `dt` into comp (`decide!` has no dt arg; the PID needs it),
NOT to move the entity — so a BALLISTIC slice-8 missile (no Autopilot) gets NO new comp key and stays
byte-identical. `decide!`: nearest `:target` (truth-fed) → `pursuit_accel` → `clamp_accel` → `autopilot_step`
(dispatch `get(w.fidelity,:autopilot,:ideal)`) → writes `comp[:a_ctrl]` (a Vec3, applied NEXT tick's
`integrate!`) + `comp[:ap_state]`. **Telemetry phase RESOLVED (the plan's open item): `decide!` runs AFTER
the single `empty!(w.env)` (phase 4 > phase 2), so unlike slice-8's energy readout it writes
`w.env[:telemetry]` DIRECTLY** — `<id>.a_cmd/.a_ach/.track_gap/.los_range/.range_rate`, all `_finite`-clamped.
**Threaded-clamp crash-guard (advisor): under `:pid` the achieved accel is clamped to a_max and the CLAMPED
value threaded BACK as the plant state, so a diverging discrete PID (ANY destabilizing gain — large Kp/Kd or
small τ, not just Kd — the P-only factor `|1−(1+Kp)dt/τ|`>1) is bounded over MANY ticks — no Inf→NaN in pos.**
`BallisticMissile.integrate!` gains the guarded `:a_ctrl` term (`haskey`, Vec3 — a ballistic missile takes
the EXACT slice-8 closure, byte-identity by construction, NOT `+ zero(Vec3)` which flips a −0.0 bit).
`LIVE_FIDELITY_MODES += autopilot = AUTOPILOT_MODES` (introduce-safe + physics-changing — the `:integrator`
shape, NOT slice-5/6/7 toggle-invariance). `scenario.jl`: a `guidance:` sub-block in the `:missile` block →
GUIDED (`[BallisticMissile, Autopilot]`, gains k_guid/kp/ki/kd/tau/a_max at knob-addressable comp keys,
tau/a_max>0 at LOAD); `_validate_missile` extended (a guided missile needs ≥1 `:target`). **NB `de_frac` is
now nonzero under guidance (the control specific force does work on the airframe — expected, NOT a slice-8
energy-conservation regression).** Tests (+35 total gate 2): `test_missile.jl` (decide! matches the pure
kernel; the WIRED loop intercepts under :ideal [track_gap==0]; :pid DIFFERS; P-only undershoot ORDERED in Kp
on the wire — the exact `1/(1+Kp)` stays the pure gate-1 pin, `a_cmd` RAMPS on the wire adding velocity-lag;
integral closes the gap; tick-1 ballistic anchor; diverging-gain-stays-finite; loader arms+rejects);
`test_determinism.jl` (the THREE claims — replay bit-identical [pos/vel/a_ctrl reinterpret]; mid-run
:ideal→:pid CHANGES the flight; introduce :autopilot on a BALLISTIC missile → byte-identical);
`test_server.jl` (set_fidelity :autopilot write/reject/introduce-safe; live gain sliders survive 500 ticks
[diverging gain → clamp, not throw]; warmup! tolerates a guided-missile scenario). Slices 1–8 byte-identical.

Gate 3 (scenario + Godot spatial-view extension + verifiers — DONE & green, 1723 tests; wire + UI
machine-verified AND `_draw` VISUALLY CONFIRMED 2026-07-01). `scenarios/slice9_pursuit.yaml`: an interceptor
CLIMBING from z=3000 at 10° pursuing a target DESCENDING through its path — **the engagement is PLANAR IN x-z
so the pursuit shows in the elevation view** (a y-crossing happens in the horizontal plane, INVISIBLE there —
advisor gate-2; the slice-4/8 "stay spatial, no new render mode" precedent). Default `:ideal` (clean
intercept t≈17.0, miss 4.98); DEFAULT gains P-ONLY (ki=kd=0) so the :ideal→:pid toggle opens a dramatic gap
the Ki slider closes. **a_max=1500 clears the ideal peak `|a_cmd|` (≈827 to closest-approach, ≈1094 at the
post-CPA whip) with ≥1.37× margin — PROVABLY never binds on the clean rung** (the miss-run's ~2e5 spike is the
badly-tuned regime; the pinned lesson is the MID-FLIGHT track_gap, a_max-free — advisor: the a_max/miss
tension resolved by NOT demoing the miss). Numbers PROBED against the live wire path + reproduced through the
loader. Godot `Sandbox.gd`: the EXISTING spatial view EXTENDED — `autopilot ∈ fidelity` (no axes) →
`_fid_kind="autopilot"`, the shared button wired to `_on_autopilot_pressed` (:ideal↔:pid ring); `_draw_spatial`
gains `_draw_guidance_los` (the missile→target LOS line + an intercept ring) on top of the reused
`_draw_missile` trail/marker; the a_cmd/a_ach/track_gap readout is all scalars (renders via `_update_readout`).
The slice-1..8 views UNTOUCHED (ALL their UI tests re-run green: sandbox/slice3/4/5/6/7/8). `net/
slice9_verify.gd` (drives the real server: :ideal track_gap 0 + intercept [min los 2.31] + |a_cmd| grows
12→1094; :pid opens the gap [6.50, ratio 0.374≈1/3, bit-identical t]; Kp=8→ratio 0.122≈1/9; Ki=40→gap 0.78 —
`S9V OK`, exit 0). `net/slice9_ui_test.gd` (mock client: handshake stays spatial + wires the autopilot cycler;
ring walks ideal→pid + wraps; kp slider → set_param; reset resyncs — `S9UI OK`). `Sandbox.tscn` smoke-loaded
headless against the slice-9 server (server DONE ⇒ scene connected, no GDScript errors). `test_scenario.jl`
+1 loader arm (autopilot default, NO other fidelity incl. the reserved `:guidance`, [BallisticMissile,
Autopilot] NOT ConstantVelocity, gains at consumed keys, 5 gain knobs, deg→rad launch). The `_draw` PIXEL
branch VISUALLY CONFIRMED via 2 windowed shots (the shot harness, [[ewsim-godot-headless]], reverted after):
**:ideal** = the climbing pursuit arc + nose marker + cyan LOS line to the target + readout `a_ach == a_cmd`
(77.26, track_gap 0); **:pid** = `a_ach 173 ≪ a_cmd 266` (the P-only undershoot as a picture). No open step
remains in slice 9's required gates. **(stretch, deferred)** `clients/notebooks/slice9_autopilot.jl` Pluto
(the commanded-vs-achieved step response) + an offline miss-distance-vs-τ/gain sweep.

Run the slice-9 showcase: `julia --project=core tools/server.jl scenarios/slice9_pursuit.yaml`, then launch
Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `autopilot:` button to
watch the track_gap readout open under :pid; drag Kp to shrink the undershoot, Ki to close it; the interceptor
pursues a descending target to a clean intercept). Re-run the gate-3 proof headless: start that server, then
`godot --headless --path clients/godot --script res://net/slice9_verify.gd` (exit 0 = pass). The UI test needs
NO server: `godot --headless --path clients/godot --script res://net/slice9_ui_test.gd`. All 1723 tests:
`pwsh tools/test.ps1`.

---

## Slice 10 — proportional navigation + g-limit saturation

**Slice 10 — missile: proportional navigation (outer loop) + g-limit saturation-as-lesson** (HANDOFF §10 item
10, the THIRD and FINAL slice of the missile-guidance arc) — **COMPLETE. Gates 1–3 done & green (1829 tests);
wire + UI machine-verified AND the guided-missile spatial `_draw` VISUALLY CONFIRMED (2026-07-02).** The
cascade seam built in slice 9 pays off: the OUTER law swaps `pursuit_accel → pn_accel` on the RESERVED
`:guidance` key, the INNER PID UNTOUCHED. **PN drives the LOS rotation rate λ̇ → 0** (leads the crossing target
onto a constant-bearing / decreasing-range collision triangle) — the tail-chaser slice 9 only approximated.
**Two lessons, two scenarios (the slice-4 split, one button-toggle each):** (1) PN beats pursuit — **MISS is now
an HONEST headline** (autopilot held :ideal lifts the slice-9 track_gap confound): pn intercepts cleanly while
pursuit tail-chases into a big miss, and |a_cmd| FALLS (pn, toward the ~2g gravity floor) vs CLIMBS (pursuit);
(2) g-limit saturation — the DELIBERATE INVERSION of slice 9's never-bind a_max: a hot geometry drives PN's
early demand ABOVE a_max → the clamp BINDS → the missile can't set the triangle → the miss OPENS, and the a_max
slider closes it. Fidelity `guidance ∈ (:pursuit, :pn)` is PHYSICS-CHANGING (the slice-2/8/9 shape, NO RNG —
NOT slice-5/6/7 toggle-invariance). Deferred (the tee-ups): augmented PN + a maneuvering target (slice 11 — the
~2g floor here is a literal in-scenario `N/(N-2)·g_perp` preview, gravity-as-unmodeled-target-accel); noisy
seekers / λ̇ filtering (slice 11 — PN reads TARGET TRUTH); 6-DOF (§11 Tier A). Planned FULL in
`docs/plans/slice10.md` (gate-0 probe + 3 gates). **Gate-0 advisor catches baked in:** the ~2g floor is NOT 0
(g-symmetric probe, mechanism TESTED); TWO independent sign sources in `pn_accel`; the magnitude identity
`N·Vc·‖ω‖` is structurally weak (pin the concrete vector); r_stop=0 default is the byte-identity lever.

Gate 1 (primitive green — pure, closed-form, SI, RNG-free, no LinearAlgebra): `guidance.jl` gains
`pn_accel(m_pos, m_vel, t_pos, t_vel; N=4.0) → Vec3` — TPN `a = N·Vc·(ω×û)` reusing `los_unit`/`los_rate`/
`range_rate`/`_cross` (all frames.jl, in scope). ⟂ LOS, zeroes on a collision course, zero-guarded (v→0 /
coincident / Vc=0 → 0). `GUIDANCE_MODES=(:pursuit,:pn)` the one-list source of truth (defined here, precedes
radar.jl). `pursuit_accel`/`autopilot_step` UNCHANGED (the seam). Both exported. `test_guidance.jl` PN arms:
the **collision-course-zero anchor** (pn≈0 vs pursuit=900 — the static Lesson-1 contrast, the sailor's-rule
EXTERNAL anchor); the **crossing** geometry — ⟂-LOS + the concrete-vector recompute `(0, N·vm·vy/D, 0)` (a
DIFFERENT expression than the cross-product path, catches the magnitude-preserving `û×ω` order flip) + the SIGN
on ±y crossings (BOTH sign sources — the `−range_rate` Vc-sign and the `ω×û` order); N-linearity; degenerate
guards + the endgame r→0 (finite-then-consumer-clamped). Slices 1–9 byte-identical (golden + determinism green
through the include).

Gate 2 (PN wired into the outer loop — the reserved `:guidance` key filled; +35 tests). `Autopilot.decide!`
(missile.jl): `guid = get(w.fidelity,:guidance,:pursuit)` (DEFAULT :pursuit → the byte-identical slice-9 path)
selects `pn_accel` vs `pursuit_accel`; a `_terminal_cutoff(a_dem, los_range, r_stop)` (§2 endgame coast-through
— **r_stop=0 default is an EXACT no-op**, `r<0` never fires, so slice-9 stays bit-identical) then `clamp_accel`
(the crash-guard that now BINDS on purpose in glimit). New telemetry (phase-4, post-empty!): `.a_demand`
(PRE-clamp — the saturation tell), `.saturated` (0/1), `.los_rate` (‖ω‖), `.closing_speed` (Vc); all
`_finite`-clamped; slice-9 keys kept. `LIVE_FIDELITY_MODES += guidance = GUIDANCE_MODES` (one-list-no-drift →
`set_fidelity`/loader/`_KNOWN_FIDELITY_KEYS` pick it up automatically, NO server change). `scenario.jl`: the
`guidance:` sub-block reads `n_pn`/`r_stop` at knob-addressable comp keys (n_pn>0, r_stop≥0 at LOAD). Tests:
`test_missile.jl` (decide! matches pn_accel; **PN miss ≪ pursuit** [0.03 vs 708 m at first-CPA — target
outruns missile so no re-convergence]; |a_cmd| falls-vs-climbs; :pursuit↔:pn DIFFER; **glimit saturation**
miss(a_max=300)=410 ≫ miss(1000)=0.7, sat real not artifact; loader arms+rejects bad n_pn/r_stop);
`test_determinism.jl` (the THREE claims + **the ADDITIVITY MASTER-CHECK: a verbatim slice-9 missile ≡
:guidance=:pursuit, bit-identical** — the "slices are additive" teeth); `test_server.jl` (set_fidelity
:guidance write/reject/introduce-safe; N/a_max/r_stop live sliders survive 500 ticks — huge N hits the clamp,
not a throw, including the deliberately-binding a_max). Slices 1–9 byte-identical.

Gate 3 (scenarios + Godot spatial-view extension + verifiers — DONE & green, 1829 tests; wire + UI
machine-verified AND `_draw` VISUALLY CONFIRMED 2026-07-02). `scenarios/slice10_pn.yaml` (Lesson 1: 12°
crossing, `v[-800,0,200]` target that OUTRUNS the missile, a_max=3000 generous — pn miss 0.03 ≪ pursuit 708,
a_cmd 213→46 vs 63→374) + `scenarios/slice10_glimit.yaml` (Lesson 2: 5° hot geometry, high fast-crossing
target, a_max=300 BINDS — miss 410 / sat_frac 0.84 / peak demand ~785; a_max↑ → miss 0.7). Numbers PROBED
against the live `load_scenario→decide!→integrate!→telemetry` path (loader/framesampled/bands probes) +
frame-sampled for the verifier. Godot `Sandbox.gd`: the EXISTING spatial view EXTENDED — **the `guidance`
discriminator branch is checked BEFORE `autopilot`** (advisor: slice-10 ships BOTH keys; autopilot held :ideal;
the ONE button must toggle `guidance` — convention 9), `_on_guidance_pressed` (:pursuit↔:pn ring),
`GUIDANCE_RUNGS`, button/badge; `_draw_spatial` missile-marker + `_draw_guidance_los` branches extended
(`guidance` fid_kind); the new a_demand/saturated/los_rate/closing_speed readout auto-renders (all scalars). The
slice-1..9 views UNTOUCHED (slice-8/9/sandbox UI tests re-run green). `net/slice10_verify.gd` (drives the real
server, **branches on the scenario name**: on `slice10_pn` — pn min-los 2.87 + a_cmd FALLS [first-descending
band 221→117] / set_fidelity pursuit degrades to 708 with a_cmd CLIMBING [53→94]; on `slice10_glimit` — default
a_max=300 SATURATES the early turn [los>2500-gated, avoiding the r→0 endgame spike — advisor] + miss 410, then
set_param a_max=1200 CLOSES the miss to 1.6 with no early saturation — `S10V OK`, exit 0 on BOTH).
`net/slice10_ui_test.gd` (mock client: handshake STAYS spatial + wires the GUIDANCE cycler NOT autopilot; ring
walks pursuit→pn + wraps; autopilot untouched; n_pn slider → set_param; reset resyncs to pn — `S10UI OK`).
`Sandbox.tscn` smoke-loaded headless against BOTH slice-10 servers (server DONE ⇒ scene connected, no GDScript
errors). `test_scenario.jl` +1 testset (both scenarios: guidance:pn default now PRESENT [the reserved key
FILLED], autopilot:ideal held, [BallisticMissile, Autopilot] NOT ConstantVelocity, n_pn/r_stop at consumed
keys, n_pn/a_max/r_stop knobs but guidance/autopilot NOT). The `_draw` PIXEL branch VISUALLY CONFIRMED via 3
windowed shots (the shot harness, [[ewsim-godot-headless]], reverted after): **pn** = the LOS line + missile
lead + readout a_cmd=a_demand=32.75 (on the floor, unsaturated); **pursuit** = a_cmd=270 (the climbing
tail-chase, ≫ pn at the same range); **glimit** = **a_cmd=300 PINNED at a_max while a_demand=821** (the g-limit
saturation as a picture, the clamp visibly binding). No open step remains in slice 10's required gates.
**(stretch, deferred)** `clients/notebooks/slice10_pn.jl` Pluto (the λ̇/|a_cmd| curves + a miss-vs-a_max
saturation sweep) + an offline `batch.jl` miss-vs-N/a_max grid.

Run the slice-10 showcase: `julia --project=core tools/server.jl scenarios/slice10_pn.yaml` (or
`slice10_glimit.yaml`), then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial
view; cycle the `guidance:` button to watch pn LEAD [constant-bearing LOS, |a_cmd| falling] vs pursuit
TAIL-CHASE [swinging LOS, |a_cmd| climbing]; on glimit drag the `a_max` slider up to close the saturated miss).
Re-run the gate-3 proof headless: start that server, then `godot --headless --path clients/godot --script
res://net/slice10_verify.gd` (exit 0 = pass; it branches on the scenario name). The UI test needs NO server:
`godot --headless --path clients/godot --script res://net/slice10_ui_test.gd`. All 1829 tests: `pwsh
tools/test.ps1`.

---

## Slice 11 — noisy seeker + LOS-rate filtering

**Slice 11 — missile: noisy seeker + LOS-rate filtering (the missile's FIRST `observe!`)** (HANDOFF §10 item
11, the FIRST slice of the seeker arc) — **COMPLETE. Gates 0–3 done & green (1921 tests); wire + UI
machine-verified AND the seeker spatial `_draw` VISUALLY CONFIRMED (2026-07-02).** Slice 10's PN read TARGET
TRUTH (`ω = r×v/‖r‖²` from truth pos/vel); slice 11 replaces that with a REAL seeker — the missile MEASURES
the LOS *angle* with white angular noise (`σ_seek`) and an **α-β tracker estimates the LOS *rate* λ̇ WITHOUT
differentiating**. **The lesson (the fidelity button, :filtered↔:raw):** the `:raw` naïve finite-difference
`λ̇=Δλ/dt` amplifies the angle noise by 1/dt → PN's `N·Vc·λ̇` pegs `a_max`, the missile flails and MISSES
WIDE; the `:filtered` α-β estimate is smooth → a TIGHT intercept ≈ the slice-10 truth-fed miss. **"A missile
is integrate! + observe! + decide!" (HANDOFF §3) is COMPLETE** — the phase-3 `observe!` missile.jl:11
anticipated is filled. **THE RNG INFLECTION: the seeker is the FIRST `w.rng` consumer in the missile arc**, so
the slice-8/9/10 "RNG-is-vacuous" boilerplate INVERTS here (conventions 3/11 now APPLY); byte-identity for
slices 1–10 comes from *the Seeker NOT EXISTING* (no draw), NOT a draw-skipping `:truth` rung (there is none —
`SEEKER_MODES=(:raw,:filtered)` only; "truth-fed PN" IS slice 10). **Scope RATIFIED-WITH-USER (2026-07-02):
seeker + filter ONLY; augmented PN + a maneuvering target → SLICE 12** (the RNG-free payoff of slice 10's ~2g
floor). Planned FULL in `docs/plans/slice11.md`. **The NEW fidelity-class combo (name both, copy neither
template): `:seeker` is DRAW-INVARIANT (class 4a — both rungs draw the SAME 1 randn/tick → `set_fidelity`
introduces it freely, UNLIKE `:cfar`) YET TRAJECTORY-CHANGING (a toggle moves the missile — the slice-10
shape).**

Gate 0 (probe + scope pin — DONE & advisor-confirmed, `M:\claud_projects\temp\slice11_probe\`): PINNED
**scalar in-plane α-β** (NOT vector — the engagement is planar x-z, ω∥±y, no atan2 singularity; the lesson IS
the scalar λ̇), **σ_seek=3 mrad / α=0.30 / β=0.05**, one scenario, headline = **MISS-RATIO** (saturation is
corroborating color). β U-shape confirmed BOTH arms (β→0 lags, β≥0.3 lets noise through → the miss climbs
again — the "smaller β smooths harder" trap). ⚠ deviation from the plan's σ=1 mrad guess: the scalar form
drops the out-of-plane noise channel, so the raw miss only EXPLODES at ~3 mrad (at 1 mrad the in-plane
sign-flip cancels → only ~4.6 m). LOCK 1: the truth path reproduces slice 10 with `pn_cmd==pn_accel` asserted.

Gate 1 (primitive green — pure, recursive, SI, RNG-free, no LinearAlgebra; +16 tests, 1845): `estimation.jl`
gains `SEEKER_MODES=(:raw,:filtered)` (the one-list source of truth, defined before radar.jl) + the scalar
`alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α, β)` (predict–correct: `λ_pred=λ_est+λ̇_est·dt`, innovation
`wrap_angle(λ_meas−λ_pred)`, correct with α and `β/dt` — the `β/dt` floored at `_ALPHA_BETA_DT_FLOOR=1e-12`,
exact no-op at dt=1e-3). `guidance.jl`: `pn_accel_from_omega(û, ω, Vc; N)=(N*Vc)*_cross(ω, û)` (the swappable
inner form — û FIRST, ω SECOND; NO `m_vel` param — TPN has no missile-vel term) + `pn_accel` becomes a thin
truth wrapper. **BYTE-IDENTITY proven two ways:** `pn_accel === (N*Vc)*_cross(ω,û)` slice-10-inline pin
(`test_guidance.jl`, bit-exact `===`) + full golden/`test_determinism` green. `test_estimation.jl` bands
MEASURED open-loop (NOT the probe's closed-loop numbers — advisor: the open-loop-variance-min (α,β) are NOT
the closed-loop-miss-min): convergence λ̇_est→ω_true ~1e-13; variance reduction filt <raw/8 (MC, own Xoshiro,
Wilson band); α/β scaling; dt→0/huge-meas/extreme-gain guards finite. **Fix logged:** the `pn_accel` docstring
must stay glued to its function (inserting the new block between them → a "cannot document" precompile error →
relocated `pn_accel_from_omega` AFTER `pn_accel`).

Gate 2 (the Seeker wired — the missile's FIRST `observe!`, the `:seeker` key filled; +45 tests, 1890). New
`Seeker <: Subsystem` (missile.jl): phase-1 `integrate!` captures its OWN `comp[:dt_s_seeker]` (self-contained,
advisor #4 — NOT a lean on the Autopilot's `:dt_s`); phase-3 `observe!` draws **ONE `randn(w.rng)`
UNCONDITIONALLY at the top** (before the tgt/impact gate — convention 3, a FIXED count), measures the noisy LOS
angle, updates BOTH the raw finite-diff memory AND the α-β state every tick (the rung selects only which ω is
written), reconstructs `ω=Vec3(0,−λ̇,0)` / `û=(cosλ,0,sinλ)` into `comp[:seeker_omega]`/`[:seeker_los]`, and
writes `lambda_dot_raw`/`lambda_dot_filt`/`lambda_dot_used`/`sigma_seek` telemetry. `Autopilot.decide!`: the
ω-source branch `guid===:pn && haskey(c,:seeker_omega)` → `pn_accel_from_omega(û_seek, ω_seek, TRUTH Vc)`
(rel_pos/rel_vel hoisted for the truth Vc); the truth `pn_accel` path UNTOUCHED (no Seeker ⇒ no `:seeker_omega`
⇒ slice-10 byte-identical). `LIVE_FIDELITY_MODES += seeker = SEEKER_MODES` (radar.jl, one-list-no-drift; class
4a — no `:cfar`-style guard). `scenario.jl`: a `seeker:` block reads `sigma_seek`/`alpha`/`beta` at
knob-addressable comp keys, LOAD-validated (σ≥0, 0<α<1, β>0), armed `[BallisticMissile, Seeker, Autopilot]`.
`export Seeker`. Numbers PROBED against the live decide!→integrate! path (convention 10). Test arms:
**test_missile** (the phase-3→4 seam `a_ctrl ≈ clamp(pn_accel_from_omega(û,ω,Vc))` [`atol=1e-9` — decide!
double-clamps vs a single-clamp oracle, a 1-ULP diff on a saturated tick], filtered≪raw, raw saturates,
trajectories differ, **1 randn/tick draw-count pin** via Xoshiro-advance, huge-σ no-crash, loader
arms+rejects); **test_determinism** (THE INFLECTION — the FIRST non-vacuous missile-arc RNG test: same-seed
bit-identical WITH the seeker drawing, 1-draw/tick, the NEW COMBO :raw↔:filtered draw-invariant AND
trajectory-changing, introduce-safe on a no-Seeker slice-10 missile); **test_server** (set_fidelity :seeker
write/reject/introduce-safe [4a], the σ/α/β live sliders survive a huge-σ tick). Slices 1–10 byte-identical.

Gate 3 (scenario + Godot spatial-view extension + verifiers — DONE & green, 1921 tests [+31]; wire + UI
machine-verified AND `_draw` VISUALLY CONFIRMED 2026-07-02). NO `core/src/*.jl` change beyond gates 1–2 — the
gate-3 diff is `Sandbox.gd` + `test_scenario.jl` + the scenario + two new `net/*.gd`, so slices 1–10 stay
byte-identical structurally. `scenarios/slice11_seeker.yaml` (seed 6, `seeker:filtered` default, guidance:pn +
autopilot:ideal HELD, the slice10_pn crossing so the seeker is the ONLY new variable). Numbers PROBED against
the live `load_scenario→observe!→decide!→integrate!→telemetry` wire (a 21-seed sweep): **seed 6 miss(:filtered)
≈ 0.39 m (frame-sampled ≈ 0.39, CPA on the emit grid) vs miss(:raw) ≈ 1391 m** (~3500×), saturation 0.01 vs
0.79, `var(λ̇_filt)≈0.10 ≪ var(λ̇_raw)≈22.7`. Bounds pinned CONSERVATIVE one-sided (filtered<30, raw>300 — NOT
the ratio; raw is a random walk, the filtered side floored by emit_every sampling — the
`ewsim-missile-verifier-sampling` memory). Godot `Sandbox.gd`: the EXISTING spatial view EXTENDED — **the
`seeker` discriminator branch is checked BEFORE `guidance` AND `autopilot`** (slice-11 ships ALL THREE keys;
guidance/autopilot held; the ONE button toggles `seeker` — convention 9; the exact slice-10 "guidance before
autopilot" precedent one lesson deeper), `_on_seeker_pressed` (:raw↔:filtered ring), `SEEKER_RUNGS`,
button/badge; `_draw_spatial` missile-marker + `_draw_guidance_los` branches extended (`seeker` fid_kind); the
new lambda_dot_raw/filt/used readout auto-renders (all scalars, no Array-crash). The slice-1..10 views
UNTOUCHED (slice-10 UI test re-run green — the seeker branch does NOT hijack slice-10, which has no `seeker`
key → falls through to guidance). `net/slice11_verify.gd` (drives the real server: FILTERED intercepts [frame-
sampled min-los 0.39 < 30] with λ̇_filt smoother than λ̇_raw [var 7.3 ≪ 959 over the FULL 6000-step run into
the r→0 endgame spike — vs the probe's 0.10/22.7 to-CPA; both hold with margin, and the shot's unsaturated
mid-flight `a_cmd=917` confirms the endgame inflation is not the lesson]; `set_fidelity seeker raw`
DEGRADES [min-los 1391 > 300, > 10× filtered] with early-turn saturation [los>2500-gated, the slice-10
first-descending/_past_early latch reused]; **REPLAY — the first NON-VACUOUS missile-arc same-seed identity:
two filtered runs' missile pos_x/pos_z sequences compared element-wise bit-for-bit** [on an RNG-AFFECTED value,
NOT the RNG-independent clock `t` — advisor #1] — `S11V OK`, exit 0). `net/slice11_ui_test.gd` (mock client:
handshake STAYS spatial + wires the SEEKER cycler NOT guidance/autopilot; ring walks raw→filtered + wraps;
guidance/autopilot untouched; σ_seek slider → set_param; reset resyncs to filtered — `S11UI OK`). Sandbox.tscn
full-lifecycle loaded (the windowed shot instantiated the real scene → connect → handshake → state → `_draw`,
exit 0 — a superset of the headless smoke-load). `test_scenario.jl` +1 testset (seeker:filtered default PRESENT
[the new key, not pre-reserved unlike :guidance], guidance:pn/autopilot:ideal held, [BallisticMissile, Seeker,
Autopilot] NOT ConstantVelocity, sigma_seek/alpha/beta at consumed keys + knobs, seed present, loader rejects
bad σ/α/β). The `_draw` PIXEL branch VISUALLY CONFIRMED via 2 windowed shots (the shot harness,
[[ewsim-godot-headless]], reverted+deleted after): **filtered** = a clean LOS line + smooth trail + readout
`a_cmd=a_demand=917` (unsaturated, below a_max=3000) + `lambda_dot_filt=−0.16`; **raw** = a WILD kinked trail +
`a_cmd=a_ach=3000` PINNED at a_max while `a_demand=25875` (8.6× over — the saturation flailing as a picture) +
`closing_speed=−1291` (diverged past the target). No open step remains in slice 11's required gates.
**(stretch, deferred)** `clients/notebooks/slice11_seeker.jl` Pluto (the λ̇_raw-vs-λ̇_filt variance + a
miss-vs-σ_seek/(α,β) sweep) + an offline `batch.jl` grid.

Run the slice-11 showcase: `julia --project=core tools/server.jl scenarios/slice11_seeker.yaml`, then launch
Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `seeker:` button to
watch :filtered LEAD [steady LOS, low a_cmd, saturated off] vs :raw FLAIL [jittering LOS/λ̇, a_cmd pegged at
a_max, wide miss]; drag σ_seek UP to watch the raw miss explode / the filtered miss hold). Re-run the gate-3
proof headless: start that server, then `godot --headless --path clients/godot --script
res://net/slice11_verify.gd` (exit 0 = pass). The UI test needs NO server: `godot --headless --path
clients/godot --script res://net/slice11_ui_test.gd`. All 1921 tests: `pwsh tools/test.ps1`.

---

## Slice 12 — augmented PN + a maneuvering target

**Slice 12 — missile: augmented PN + a maneuvering-target mover (the seeker arc's RNG-free payoff)** (HANDOFF
§10 item 10's deferred half — "g-limit saturation modeled, this is *why* augmented PN matters") — **COMPLETE.
Gates 0–3 done & green (2008 tests); wire + UI machine-verified AND the spatial `_draw` VISUALLY CONFIRMED
(2026-07-02).** Slice 10 gave PN against a CONSTANT-VELOCITY target (optimal, `a_cmd→0` at intercept); slice 11
gave a noisy seeker + α-β filter so PN reads a MEASURED LOS. Slice 12 lands the last structural piece: even a
PERFECT LOS estimate leaves plain PN LAGGING a MANEUVERING target by the target-accel term, and — under a
BINDING g-limit — PN's demand SATURATES and it MISSES. **Augmented PN (`:apn`)** adds a `(N/2)·a_T⊥` feedforward
on the target's TRUTH lateral acceleration → it anticipates the maneuver → low demand → tight intercept. **The
lesson (the 3-ring fidelity button, :pn↔:apn):** vs a maneuvering target under a binding `a_max=200`, `:pn`
saturates (pegs a_max most of the turn, `saturated` lit) and MISSES ≈167 m; `:apn` stays clear of a_max
(peak demand ≈36) and INTERCEPTS ≈0.85 m (restoring the CV baseline miss ≈0.9 m — both carry the same gravity
residual). **The g-limit is the BINDING constraint** — raise `a_max` to ≳350 and `:pn` RECOVERS too (proving
the miss was saturation, not a PN defect); `:apn` is flat across a_max. **DETERMINISM — THE RNG INFLECTION
INVERTS BACK:** slice 11's Seeker made the missile arc draw; slice 12 has NO seeker → NO `w.rng` draw, so the
framing RETURNS to the slice-8/9/10 shape ("draw-count invariance is VACUOUS" — do NOT copy slice-11's
"1 draw/tick" language; the convention-4c trap running the OPPOSITE direction). `:apn` is PHYSICS-CHANGING, NO
RNG (like `:pn`): introduce-safe, but a toggle CHANGES the trajectory. **Scope RATIFIED-WITH-USER (2026-07-02):
slice 11 was seeker+filter ONLY; APN + the maneuvering mover are slice 12** (needs a new mover; cleanly
separable). Planned FULL in `docs/plans/slice12.md`. **Deferred (named, convention 9):** gravity-compensated PN
(the residual `:apn` miss is the missile's OWN unmodeled gravity — a SECOND feedforward, not this slice);
estimated `a_T` (slice 12 reads TRUTH — "even a perfect seeker still lags"; fusing APN with the noisy seeker is
§11 Tier A); 6-DOF / jink-weave maneuver programs.

Gate 0 (probe + scope pin — DONE & advisor-confirmed twice, `M:\claud_projects\temp\slice12_probe\`): the KEY
EMPIRICAL FINDING (advisor #1) — under a GENEROUS `a_max` plain PN INTERCEPTS the maneuvering target anyway
(miss ≈0 for BOTH rungs; APN only lowers `a_cmd`), exactly slice-10's "the floor is an `a_cmd` effect, not a
miss" trap. So the MISS lesson REQUIRES a BINDING `a_max` — PN's high demand SATURATES → misses; APN's low
demand stays under → intercepts. **The linchpin (advisor's discriminating check): HANDOFF §10 item 10 verbatim
— "g-limit saturation modeled (this is *why* augmented PN matters)" — confirms the g-limited-MISS pivot is the
FACE-VALUE design intent, not a tidier reading.** PINNED: slice10_pn crossing + `a_lat=200` (~20 g) ⟂-v
**turn-sign=+1** (the CLEAN-first-CPA direction — the target curves AWAY after the first pass) + binding
`a_max=200`, N=4, r_stop=30, RNG-free. The FOUR advisor LOCKS all confirmed: (#1) headline = MISS-RATIO under a
binding g-limit (saturation is the corroborating mechanism — the advisor's "teach BOTH: the miss is the
consequence, the demand/saturation contrast is the mechanism, expose both"); (#2) RNG-free / slice-10
determinism shape; (#3) CLEAN FIRST CPA (`first_cpa==global_min` both arms); (#4) SIGN decisive — apn(+)=0.59 vs
apn(−)=646.7 vs pn=166.8 (a flipped feedforward is WORSE than plain PN — the silent failure). CV sanity:
apn==pn bit-identical at a_lat=0. RK4-mover speed drift −2.7e-12 over 8 s (a ⟂-v turn is speed-preserving).

Gate 1 (primitive green — pure, closed-form, SI, RNG-free, no LinearAlgebra; +12 tests, 1933): `guidance.jl`
gains **`GUIDANCE_MODES=(:pursuit,:pn,:apn)`** (add the third rung to the one-list source of truth —
`LIVE_FIDELITY_MODES` REFERENCES it, `set_fidelity`/`_validate_fidelity` pick it up automatically, NO server
change) + **`pn_accel_augmented(û,ω,Vc,a_T;N)=pn_accel_from_omega(û,ω,Vc;N)+(N/2)·(a_T−_dot(a_T,û)·û)`** —
REUSING `pn_accel_from_omega` TEXTUALLY for the base so the `:pn` arithmetic is untouched (byte-identity by
construction). `export pn_accel_augmented`. `test_guidance.jl` arms (explicit `atol`): `a_T=0`→reduces to PN
EXACTLY (`==`, the introduce-safe property); a DIRECT feedforward recompute (a DIFFERENT expression — catches a
`−`/transpose); `a_T∥û`→zero feedforward (the projection kills a radial maneuver); the feedforward ⟂ LOS; SIGN
(the feedforward ADDS along +a_T⊥, a flip flips it); N-linearity isolated on a collision course (base PN=0);
`:apn ∈ GUIDANCE_MODES`. Slices 1–11 byte-identical (golden + determinism green; no RNG added).

Gate 2 (the maneuvering mover + the `:apn` rung wired; +45 tests, 1978). New **`ManeuveringTarget <: Subsystem`**
(missile.jl — the accelerating sibling of `ConstantVelocity`): phase-1 `integrate!` solves
`integrator_step(:rk4, v->a_lat·perp(v), …)` (the SAME stepper the missile flies, but ALWAYS `:rk4`, NOT coupled
to the missile's `:integrator` — a cross-lesson leak guard) and writes `comp[:a_target]::Vec3` = the truth accel
THIS tick (post-step velocity) for the phase-4 `:apn` decide! to read (phase-1 write < phase-4 read; comp
survives `empty!`). GRAVITY-FREE / kinematic (feels only `a_T`, the ConstantVelocity lineage). Shared
`_lateral_accel(v,a_lat,sign)` = `a_lat·sign` along the in-plane (x-z) unit ⟂ v (v→0 guard → zero). `export
ManeuveringTarget`. `Autopilot.decide!`: the `guid===:apn` arm → `pn_accel_augmented(los_unit, los_rate,
−range_rate, get(tgt.comp,:a_target,zero(Vec3)); N)` — reads the EXACT `:pn` truth û/ω/Vc plus the feedforward;
the fetch+feedforward live INSIDE the `:apn` branch so `:pn`/`:pursuit`/the slice-11 seeker paths are TEXTUALLY
unchanged → slices 1–11 byte-identical. `scenario.jl`: a `maneuver:` sub-block under `:target` reads
`a_lat_mps2`/`turn_sign` at knob-addressable comp keys, LOAD-validated FINITE, and its PRESENCE swaps
`ConstantVelocity → ManeuveringTarget` (a plain target stays ConstantVelocity, byte-identical). Numbers PROBED
against the live decide!→integrate! path (`wire_probe.jl`, convention 10): pn miss 166.8/sat 0.63, apn 0.85/sat
0.00, pn(CV)==apn(CV)=0.919 bit-identical. Test arms: **test_missile** (ManeuveringTarget curves + writes
`comp[:a_target]` ⟂ v, |a|=a_lat; the `:apn` decide! matches `pn_accel_augmented`; miss(:apn)≪miss(:pn) under
the g-limit + the a_max slider recovers pn; `:pn↔:apn` differ; `:apn`-on-CV ≈ `:pn`; loader arms+rejects bad
a_lat); **test_determinism** (THE INVERSION — same-config bit-identical, **NO `w.rng` draw** [`rand(w.rng)==rand
(Xoshiro(0))` — the sharp inverse of slice-11's "1 draw/tick"], `:pn↔:apn` toggle changes it, additivity: a
`:pn`/ConstantVelocity world byte-identical); **test_server** (set_fidelity :guidance :apn write/reject/
introduce-safe + the 3-ring cycle on the wire; the live a_lat/N/a_max sliders survive a huge-a_lat tick).
Slices 1–11 byte-identical.

Gate 3 (scenario + Godot 3-ring extension + verifiers — DONE & green, 2008 tests [+30]; wire + UI
machine-verified AND `_draw` VISUALLY CONFIRMED 2026-07-02). NO `core/src/*.jl` change beyond gates 1–2 — the
gate-3 diff is `Sandbox.gd` (the guidance ring) + `test_scenario.jl` + the scenario + two new `net/*.gd`.
`scenarios/slice12_apn.yaml` (`guidance:apn` default, autopilot:ideal HELD, `[BallisticMissile, Autopilot]`
interceptor + a `[ManeuveringTarget]` curving target, the binding a_max=200, the slice10_pn base geometry so the
maneuver+APN are the ONLY new variables). Numbers PROBED on the EMIT GRID (`emit_probe.jl`, emit_every=16, the
verifier's frame sampling): apn frame-miss 6.61/sat 0.00, pn 166.9/sat 0.63, pursuit 261.7; pn recovers to 3.8
at a_max=350. Bounds pinned CONSERVATIVE one-sided (apn<30, pn>50, pn-recover<30 — NOT the ratio; the
`ewsim-missile-verifier-sampling` memory). Godot `Sandbox.gd`: the EXISTING spatial view EXTENDED — the
`guidance` cycler becomes a **3-RING** `GUIDANCE_RUNGS=["pursuit","pn","apn"]` (the generic `(i+1)%size`
`_on_guidance_pressed` handler auto-extends; tooltip + comment updated); the slice-1..11 views UNTOUCHED
(structurally the slice-10 guidance path, one rung wider). `net/slice12_verify.gd` (drives the real server, 4
phases): `:apn` INTERCEPTS the maneuvering target (frame-min 6.61 < 30) with NO approach saturation (demand 36);
**REPLAY — held-config bit-identical (two `:apn` runs' frame-min EQUAL, RNG-free determinism)**; `set_fidelity
guidance pn` DEGRADES it (166.9 > 50, sat lit while los>300, demand 11366 > a_max=200 — the saturation is real);
`set_param a_max 350` RECOVERS `:pn` (3.8 < 30, no saturation — the g-limit-is-the-constraint payoff). `S12V OK`,
exit 0. `net/slice12_ui_test.gd` (mock client: handshake STAYS spatial + wires the GUIDANCE cycler NOT
autopilot; the 3-ring walks pursuit→pn→apn + wraps; autopilot untouched; the a_lat slider → set_param to the
TARGET tgt1; reset resyncs to apn — `S12UI OK`). Sandbox.tscn smoke-loaded headless against the slice-12 server
(server `DONE` ⇒ scene connected, no GDScript errors). `test_scenario.jl` +1 testset (guidance:apn default
PRESENT [the reserved third rung, now real], autopilot:ideal held, `[BallisticMissile, Autopilot]` NOT Seeker,
`[ManeuveringTarget]` NOT ConstantVelocity, a_lat_mps2/turn_sign at consumed keys + the a_lat knob on tgt1,
a_max=200 binding, loader rejects a non-finite a_lat). The `_draw` PIXEL branch VISUALLY CONFIRMED via a windowed
shot (the shot harness, [[ewsim-godot-headless]], reverted+deleted after): the `:apn` mid-intercept renders the
missile leading the target on the LOS line with **`a_demand=3.72` — LOW, well under a_max=200 (no saturation, the
mechanism as a picture)**, the 4 sliders (a_lat on the target + N/a_max/r_stop), the "guidance: apn" button, and
the fidelity badge. No open step remains in slice 12's required gates. **(stretch, deferred)**
`clients/notebooks/slice12_apn.jl` Pluto (the miss-vs-a_lat / a_max sweep) + an offline `batch.jl` grid.

Run the slice-12 showcase: `julia --project=core tools/server.jl scenarios/slice12_apn.yaml`, then launch Godot
on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `guidance:` 3-ring button to
watch `:apn` LEAD the curving target [low a_demand, saturated off] vs `:pn` SATURATE + MISS [a_demand pegs
a_max, saturated lit, wide miss]; drag a_max UP to 350+ to watch `:pn` recover, or a_lat UP to make `:pn` lag
harder). Re-run the gate-3 proof headless: start that server, then `godot --headless --path clients/godot
--script res://net/slice12_verify.gd` (exit 0 = pass). The UI test needs NO server: `godot --headless --path
clients/godot --script res://net/slice12_ui_test.gd`. All 2008 tests: `pwsh tools/test.ps1`.

## Slice 13 — countermeasures — a decoy vs a CFAR-scanning seeker

**Slice 13 — countermeasures: a decoy that seduces a CFAR-scanning seeker + an α-β discrimination gate (the
suite-fusing slice)** (HANDOFF §10 item 12 — "chaff (= RGPO), flares (IR decoys); seeker discrimination = the
EW/CFAR sandbox … this stage *fuses the whole suite*") — **COMPLETE. Gates 0–3 done & green (2159 tests). Gate 0
(probe) + Gate 1 (primitives, +34) + Gate 2 (wired, +70) + Gate 3 (scenario/Godot/verifiers, +41).** Opens the
countermeasures arc: put a `:decoy` in front of the
slice-11 seeker and lift the slice-3 CFAR sandbox onto the LOS-ANGLE axis. The lesson is **seduction vs
discrimination** — the seeker forms a NOISY angular-power profile, CFAR-DETECTS the peaks (target + decoy), and
either blends them (`:none`, an intensity-weighted centroid walks the seeker OFF truth → miss) or DISCRIMINATES
(`:gated`, an α-β predicted-LOS gate rejects the separated decoy → holds). **The fusion is HONEST because the two
reused libs do DIFFERENT jobs:** detection.jl (`cfar_scan`, UNCHANGED) DETECTS the peaks in the noisy profile;
estimation.jl (the α-β predicted-LOS gate) DISCRIMINATES which peak to keep — CFAR alone cannot reject a brighter
decoy. **RGPO is REALIZED here in ANGLE** (the seeker walked off by a decoy IS the match-then-drag RGPO model,
HANDOFF §9); the deferred piece is the *range-gate-against-a-tracking-radar* variant, NOT "RGPO". **Scope fork (b)
RATIFIED (user, 2026-07-02):** a full continuous angular-profile CFAR-scan seeker (`:scan` rung), not the smaller
two-discrete-return option. **DETERMINISM — the RNG inflection RE-INVERTS to APPLIES** (a seeker draws again;
conventions 3/11 apply — do NOT carry slice-12's "no-RNG/vacuous" language), **and the class is 4b, NOT
slice-11's 4a:** `:scan` FLIPS the draw topology (`1` → `2·N_p·N_bins` randn/tick via `_draw_profile!` on the
fixed grid) → introduce-REJECTED like `:cfar`; `SEEKER_MODES` gains MIXED introduce-safety (`:raw↔:filtered`
safe, any switch touching `:scan` rejected); `discrimination` is draw-invariant AMONG its rungs, trajectory-
changing, and INERT without `:scan` (the `:raim`-without-GPS coupling) — "draw-invariant within a 4b host", NOT
free-standing 4a. Planned FULL in `docs/plans/slice13.md`. **Deferred (named, convention 9):** the range-gate
RGPO variant vs a tracking radar; the RF/IR seeker split + an IR env channel (§11 Tier A — chaff and flare are
the SAME mechanic at this fidelity, an angular lobe + an intensity scalar; the scenario picks ONE); decoy
dynamics (bloom/burn-out/timed-ejection/fall — slice-13 decoy is constant-velocity, constant-intensity, present
from t=0); the 2-D az×el profile + monopulse (slice 13 scans ONE in-plane angle, a 1-D window); multiple/salvo
decoys.

Gate 0 (probe + config pin — DONE & advisor-confirmed, `M:\claud_projects\temp\slice13_probe\` `probe*.jl` +
`FINDINGS.md`): pinned the angular grid/beam/CFAR config so the target + decoy lobes RESOLVE into two clean CFAR
peaks (separation ≳ a beamwidth AND clear of the guard+training span — the slice-3 masked-close-target lesson on
the angle axis, swept over the separation the engagement traverses so BOTH peaks survive CFAR throughout); the
headline; the intensity ratio + separation + near-co-location start (clean first CPA, `:gated` locks truth first
then the decoy lobe exits the gate); the sign/wrap; the `2·N_p·N_bins` draw-count invariance; miss-vs-true-target.
**Two FINDINGS overrides of the plan (both carried into gate 1):** `paint_angular_profile!` was PROMOTED into the
pure estimation.jl layer (kept OFF the byte-identity-critical radar.jl); and `validation_gate` is a
NEAREST-NEIGHBOR + halfwidth-reject → `nothing`-coast (NOT the plan-§3 keep-in-gate-then-centroid, which re-blends
the decoy and made `:gated` WORSE than `:none`).

Gate 1 (primitive green — pure, closed-form, SI, RNG-free, no LinearAlgebra [`wrap_angle` only]; +34 tests, 2042):
estimation.jl gains FOUR pure fns (all wrap-safe about a reference bearing — the ±π seam guard) + two mode tuples,
all exported: **`paint_angular_profile!(power, grid, sources; σ_beam, floor=1.0)`** — floor every cell then ADD a
Gaussian lobe `amp·exp(−½(Δλ/σ_beam)²)` per source (`Δλ=wrap_angle(grid−λ_s)`); the profile LENGTH is
decoy-count-INDEPENDENT (paint-the-fixed-grid, the determinism keystone — the noisy floor is added downstream by
`_draw_profile!`, so this stays RNG-free). **`intensity_centroid(peaks)`** — the intensity-weighted mean bearing
about the STRONGEST-weight peak (self-contained ref, the additivity anchor: a singleton returns its bearing
EXACTLY `===`; empty → `nothing`); serves double duty (within-cluster peak angle AND the `:none` cross-peak
blend). **`extract_peaks(grid, z, detections)`** — cluster CONTIGUOUS detection runs → per-run
`(intensity_centroid, Σz)`, grid order, no detections → empty. **`validation_gate(peaks, λ_pred, halfwidth)`** —
the RGPO track-gate: the NEAREST peak to the α-β predicted bearing IF within `halfwidth`, else `nothing` (coast).
**`SEEKER_MODES = (:raw, :filtered, :scan)`** (`:scan` appended — the 4b rung) + **`DISCRIMINATION_MODES =
(:none, :gated)`**, both the one-list source of truth defined in estimation.jl (precedes radar.jl); gate 2's
`LIVE_FIDELITY_MODES` will REFERENCE them (no re-list, the drift-catch). `alpha_beta_los_step` + `:raw`/`:filtered`
UNCHANGED (byte-identity anchor). `test_estimation.jl` arms (explicit `atol`, convention 11): the centroid
DIFFERENT-expression recompute (`Σwλ/Σw` off-seam); the singleton `===` additivity anchor; the ±π SEAM (target
near +π, decoy near −π → blend to ≈±π, not a jump to 0 — the slice-5 wrap trap); a symmetric-midpoint EXTERNAL
anchor; `extract_peaks` contiguous-run clustering → power-weighted centroids; the NN+halfwidth-reject gate
semantics (the FINDINGS override); `paint_angular_profile!` floor+additive-lobe superposition, wrap-safe painting,
and the fixed (decoy-count-independent) LENGTH; both mode tuples pinned. Slices 1–12 byte-identical (golden +
determinism green — no RNG added, estimation.jl stays pure). **GATE-2 forward-flags (advisor):** (a) the
grid-centering off-by-one MOVED (not vanished) — make `angular_grid(boresight, N_bins, bin_w)` a tiny TESTED
helper (or pin an observe!-path bin assertion), don't bury it in `observe!`; (b) keep the gate `halfwidth ≥ 0.045`
(the gate-0 `hw`) and validate it at LOAD — a tighter `hw` silently converts the gate's hold into a coast (couples
to the masking window). NEXT: gate 2 (the `:decoy` kind + the `:scan` profile/scan/gate `observe!` + the
`discrimination` rung + the `:scan`-introduce-reject `set_fidelity` guard + test_missile/determinism/server arms).

Gate 2 (WIRED — the `:decoy` kind + the `:scan` profile/scan/gate `observe!` + the `discrimination` rung + the 4b
introduce-reject guard; +70 tests, 2112; slices 1–12 byte-identical): **`angular_grid(boresight, N_bins, bin_w)`**
promoted into estimation.jl (the gate-1 forward-flag — the fixed bin-center grid `grid[i]=boresight+(i−(N+1)/2)·bin_w`,
NOT wrapped [small FOV, planar engagement — monotonic for `extract_peaks`]; length = N_bins boresight-independent, the
determinism grid), exported + TESTED (centering/ascending/uniform-spacing/known-bin round-trip — the off-by-one pin).
**scenario.jl:** a NEW **`kind === :decoy`** ([`ConstantVelocity`] mover + `comp[:intensity]` lobe amplitude, validated
≥0; born already-separated + parallel — the flare reading, present from t=0) that `_nearest_target` SKIPS (the
truth-path invariant — miss/CPA always vs the true `:target`); `:target` gains `comp[:intensity]` (default 1.0,
byte-identity for slices 1–12); the `seeker:` block gains the STATIC scan config (`n_bins`/`bin_width`/`sigma_beam`/
`floor`/`n_pulses`/`cfar_variant`/`cfar_n_train`/`cfar_n_guard`/`cfar_pfa`/`gate_halfwidth`, all LOAD-validated:
`n_bins≥1`, even `n_train≥2`, `bin_width`/`sigma_beam`/`floor`/`gate_halfwidth`>0, `pfa∈(0,1)`, AND the os/so/go×`n_pulses>1`
combo REJECTED — those CFAR closed forms are N_p=1 only, would throw inside `cfar_scan`→observe!). **missile.jl:**
`Seeker.observe!` split into a thin `rung`-dispatcher → **`_observe_point!`** (the slice-11 body VERBATIM, 1 randn —
byte-identity by construction; `:raw`/`:filtered` take it textually unchanged) + **`_observe_scan!`** (the new path):
tick-1 CUED-LOCK seed from the TRUTH LOS to `_nearest_target` (decoy-excluded → locks the target first, robust even
with the decoy at t=0) then FALL THROUGH to the draw (NOT an early return — every tick incl. tick 1 draws, so the count
is 1500×1280 not 1499×1280, advisor); center the grid on `λ_pred`, `paint_angular_profile!` all `:target`+`:decoy`
lobes (`_scan_sources`, sorted-id), `_draw_profile!` (the 2·N_p·N_bins topology flip, SAME N_p feeds `cfar_scan`),
`extract_peaks`, select (`:none`=`intensity_centroid` blend-all / `:gated`=`validation_gate` NN), COAST on `λ_pred` if
none (α-β innovation exactly 0), then the EXACT `alpha_beta_los_step`; PN consumes the α-β estimate (like `:filtered`);
scalar telemetry (`aim_error` [THE headline], `lambda_used`/`lambda_est`/`target_bearing`/`decoy_bearing`/`n_peaks`/
`gated` — no Array). **The `sigma_seek` slider goes INERT under `:scan`** (noise moved into the profile floor; the live
noise knob is now `pfa`/`intensity`) — named. **radar.jl:** `LIVE_FIDELITY_MODES += discrimination = DISCRIMINATION_MODES`
(the one-list reference; `:scan` already flowed via `SEEKER_MODES`). **server.jl `set_fidelity`:** the 4b guard —
reject a `:seeker` change that INTRODUCES *or* REMOVES `:scan` (`cur_scan != new_scan`; BOTH directions, unlike `:cfar`'s
introduce-only — `:scan→:filtered` is equally a 1280↔1 topology flip); `:raw↔:filtered` + `:none↔:gated` stay live.
Smoke (temp, seed 6, the FINDINGS operating point): `:none` aim(mid) 3.97° / miss 539 m vs `:gated` 0.056° / 0.06 m
(≈71× aim ratio — the lesson holds), draw count EXACTLY 1280/tick (2·10·64), decoy-count-independent. `test_missile`
arms: observe! paints/scans + n_peaks telemetry; `:none` seduced vs `:gated` holds (aim `< 0.5°` vs `> 2°`, ratio `>20×`;
miss `< 5 m` vs `> 100 m`); the `:none↔:gated` trajectories DIFFER; miss vs the true `:target` (`_nearest_target.id ===
:tgt1`); the 2·N_p·N_bins draw-count keystone (decoy present AND absent, both `:none`/`:gated`); the huge-intensity/
wide-gate live-slider guard; the loader arm + 6 rejects. `test_determinism`: same-config `:scan` replay bit-identical
WITH the 1280/tick draw; the `:none↔:gated` toggle CHANGES the trajectory with the RNG in LOCKSTEP (draw-invariant
within the 4b host — NOT "vacuous", the opposite of slice 12); the mixed topology (`:filtered` still exactly 1/tick).
`test_server`: `:discrimination` write/introduce-safe; `:scan` introduce AND remove REJECTED (both directions), while
`:raw↔:filtered` stays live; the live `intensity`/`gate_halfwidth` sliders survive the tick.
Gate 3 (gate 3 — visible live, 2159 tests, +47): `scenarios/slice13_decoy.yaml` — the slice-11 crossing (m1
climbs from z=3000 at 12°/700 m/s; the true target tgt1 `[6000,0,4200]` v`[-800,0,200]` OUTRUNS the missile so
the first CPA is the honest miss) PLUS a born-already-resolved `:decoy` dcy1 at `[5850,0,4793]` (Δ₀≈0.10 rad ≈
5.75° above the target bearing — ≈6·σ_beam, resolves into a SECOND CFAR peak), flying PARALLEL (v = tgt.vel → a
fixed linear offset), `intensity: 80` (2× the target's 40 — the brighter competing peak). `fidelity`:
`discrimination:none` DEFAULT (the button REVEALS the fix) + `seeker:scan`/`guidance:pn`/`autopilot:ideal` HELD
(convention 9 — the one button toggles discrimination). `a_max: 3000` GENEROUS — the headline is a POINTING miss
(aimpoint error), NOT saturation (the OPPOSITE of slice-12; the gate-0 pivot #1). knobs: the decoy `intensity`
(seduction lever) + `gate_halfwidth` (discrimination lever) + `n_pn`/`a_max`; `sigma_seek` is NOT exposed (INERT
under `:scan` — the dead-knob surprise). **RE-PROBED on the EMIT-GRID wire** (`emit_probe.jl`, convention 10, seed
6 — NOT the per-tick gate-2 smoke): loads through `load_scenario→tick!(w,subs,dt)` and samples `w.env[:telemetry]`
at every emit_every — `:none` aim(mid [0.4,1.4]s) **4.825°** / miss **597.6 m** (SEDUCED — the intensity-weighted
centroid of both peaks walks the aim toward the brighter decoy) vs `:gated` aim **0.054°** / miss **4.16 m** (HOLDS
— the NN-to-α-β-prediction gate rejects the decoy) — an **≈89× aim ratio**; draw EXACTLY 1280/tick. **The GATE-3
FORWARD-FLAG CLEARED:** the parallel decoy's subtended Δ grows only 5.75°→~7.3° over the midcourse vs the **9.17°
FOV half-width** (±0.16 rad), and `:none` misses by 598 m so R never collapses → the decoy stays inside ±FOV/2 for
t∈[0.02,4.4]s (through the whole aim window); no FOV walk-out, the lesson does NOT collapse. Godot `Sandbox.gd`:
the SPATIAL view EXTENDED (no new mode — the slice-8..12 precedent) — `DISCRIMINATION_RUNGS=(none,gated)`,
`_on_discrimination_pressed` (the none↔gated ring), the `discrimination` branch CHECKED FIRST in
`_setup_spatial_fid_btn` (BEFORE the held seeker/guidance/autopilot — a slice-13 scene ships all four keys; the
one button toggles the ONE lesson, convention 9), the "disc:" button label + full-four-key badge; the NEW VISUAL —
an orange ✦ decoy glyph + `_draw_discrimination_los` (the faint missile→decoy LOS + the seeker's TRACKED-aim ray
drawn from the `lambda_est` telemetry: under `:none` it walks toward the ✦ decoy, under `:gated` it holds on the
target). All readout SCALARS (no Array telemetry — the `float()`-crash watch-item; the profile/detections are NOT
shipped). Slice-1..12 views UNTOUCHED (the discriminator falls through — no `discrimination` key → the slice-11/12
paths unchanged). **THE FOUR PROOFS GREEN:** `net/slice13_verify.gd` (S13V OK, exit 0 — drives the real server:
`:none` aim 4.825°/miss 597.6 m SEDUCED, `:gated` aim 0.054°/miss 4.16 m HOLDS, the ≈89× ratio, the midcourse
FOV-containment guard, the **1280-draw/tick same-seed bit-identical pos_x/pos_z replay** [the slice-11 RNG-consumer
discipline — the `:scan` seeker DRAWS], the 4b guard `set_fidelity seeker raw` REJECTED with an error frame [removing
`:scan` = a topology flip], miss ALWAYS vs the true target); `net/slice13_ui_test.gd` (S13UI OK — the discrimination
cycler none↔gated, the held keys untouched, badge/button track, `intensity`→dcy1 `set_param`, reset resyncs to
none); the `Sandbox.tscn` headless smoke-load (server `WARMING→LISTENING→DONE` ⇒ the scene connected + handshaked,
NO GDScript errors); and the **windowed shot-harness** (`_draw` fires only windowed — [[ewsim-godot-headless]], the
slice-3/4 technique, Vulkan/RTX 5090): `:none` = the yellow aim ray walking to the ✦ decoy glyph (aim_error 0.13→
0.20 rad, seduced), `:gated` = the aim ray HELD on the grey target (aim_error 2.6e-4 rad ≈ 0.015°) — captured from
t=0 (the harness `reset`+`set_fidelity` BEFORE stepping, since switching `:none→:gated` mid-flight lets `:none` STEAL
the α-β track onto the decoy first — the RGPO-steal regime, a live gotcha the mid-flight capture surfaced).
`test_scenario.jl` slice-13 loader arm: the four-key fidelity (discrimination:none default + the three held), the
`:decoy`-kind truth-path invariant (`d.kind === :decoy !== :target`), the target+decoy `intensity` at consumed comp
keys, the scan grid/beam/CFAR/gate config at consumed keys, `intensity`/`gate_halfwidth` sliders (NOT sigma_seek —
dead under `:scan`), `a_max=3000` generous, the base geometry, and the LOAD rejects (negative decoy intensity / odd
n_train / N_bins<1 / an os variant at N_p>1). Slices 1–12 byte-identical (golden + determinism green through the
scenario/client/test edits — no `core/src` change beyond gate 2). **BYTE-IDENTITY ON THE NEW SCAN PATH — advisor
review close-out:** the RNG stream is pinned by the shared `_draw_profile!` `===` draw-order golden (test_radar.jl,
reused verbatim by `_observe_scan!`) + the 1280-draw keystone (its sole consumer); each deterministic link by its
estimation.jl unit golden (`angular_grid`/`paint_angular_profile!`/`extract_peaks`/`intensity_centroid`/
`validation_gate`, `===`/`atol=1e-12`); and — the gap the review closed — the `_observe_scan!` COMPOSITION (λ_pred
grid center, tick-1 cued-lock seed, disc→selection arg order, α-β wiring) by a NEW composition golden pinning
`seek_lambda_est` across the first 3 ticks per rung with `===` (probed off the live tick! path, convention 10; the two
rungs DIVERGE from tick 1 — `:none` walks the aimpoint off, `:gated` holds), so a silent refactor can't desync replay
while sailing under the loose lesson bounds. **Slice 13 COMPLETE — the countermeasures arc
opens; HANDOFF §10 item 12 ("fuses the whole suite") CLOSED.**
Run the slice-13 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice13_decoy.yaml`, then
launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `disc:` button to
watch the aim ray seduce toward the ✦ decoy under `:none` and snap back to the target under `:gated`; drag the decoy
`intensity` / `gate half-width` sliders). **RESET between rungs to see the clean `:gated` recovery** (the slice-2
"`reset` BEFORE `set_fidelity`" pattern): letting `:none` run first STEALS the α-β track onto the brighter decoy, so
a mid-flight `:none→:gated` toggle keeps tracking the decoy (the gate now centers on the stolen prediction — the
RGPO-steal regime). Press `reset` (→ t=0, the cued-lock re-seeds on the true target) THEN cycle to `:gated` so it
runs from launch — the honest live procedure, exactly what the verifier + shot-harness do. Re-run the gate-3 proof headless: start that server, then the console
Godot `--headless --path clients/godot --script res://net/slice13_verify.gd` (exit 0 = pass). The UI test needs NO
server: `… --script res://net/slice13_ui_test.gd`. **(stretch, deferred)** a Pluto miss-vs-intensity/separation
sweep + an offline `batch.jl` miss-vs-`I`/gate grid (own seeded stream — the distribution path).

---

## Slice 14 — cooperative salvo guidance (the capstone)

**Slice 14 — cooperative guidance: a salvo of interceptors sharing time-to-go for SIMULTANEOUS arrival (HANDOFF
§10 item 13 — "Cooperative guidance … Capstone")** — **COMPLETE. Gates 0–3 done & green (2259 tests). THE
COMMITTED ROADMAP IS CLOSED.** The missile guidance arc (slices 8–12) built the single-interceptor stack; slice
14 puts N=2 interceptors in ONE scenario and lets them SHARE STATE through the guidance law: each missile's
time-to-go `t_go ≈ R/V_c` is pooled over an IDEAL datalink into a team consensus `T_d = max_j t_go_j(0)`, and an
impact-time-control term shapes each trajectory so all N arrive together (Δτ → 0). **SCOPE FORK (C) — guidance-law
cooperation** (ratified 2026-07-10); (A) distributed/measurement-fusion estimation + (B) weapon–target assignment
are HANDOFF §11 Tier-C horizons, DEFERRED (NAMED). The RNG story INVERTS BACK to VACUOUS (the slice-12 shape):
truth-fed PN, NO seeker → NO `w.rng` consumer → class **4c** (physics-changing, no RNG — the `:integrator`/
`:autopilot`/`:apn` shape, NOT slice-13's draw-topology 4b). Do NOT carry slice-13's "2·N_p·N_bins draws / 4b"
language — that is the convention-4c copy-paste false-claim trap running the slice-13→14 direction.

Gate 0 (throwaway probe, `M:\claud_projects\temp\slice14_probe\`, advisor-confirmed): reused the REAL core
physics (`using EWSim`), hand-rolled the `time_to_go`/`salvo_consensus`/`impact_time_control_accel` candidates +
the 2-missile coordinator + the integrate!→build_env!→decide!(×2) loop. **Geometry F pinned:** a slow MOVING
target `[9000,0,4500]` v`[-500,0,0]` (a CV target dodges the ground-target gravity-droop miss — a stationary far
target makes plain PN miss ~940 m); near missile A `[3000,0,3000]` (natural t_go(0)≈5.0 s), far B `[0,0,3000]`
(≈7.3 s), both aimed at the target, speed 750; N=4, **K_it=0.45** (window [0.42,0.50]), a_max=3000 (generous —
does NOT bind), r_stop=30, `VC_FLOOR=50`. **The t_d FORK RESOLVED — FIXED absolute-time `T_d`** (advisor's
robustness default WINS empirically): the coordinator computes `T_d=max t_go(0)` ONCE and publishes the shared
REMAINING time `w.env[:salvo_t_d]=T_d−w.t`; each missile's `err=salvo_t_d−t_go`. Per-tick-max AND every
continuous-ratchet variant (probe8/9) were REJECTED — cooperative guidance induces the very stretch that
collapses each missile's V_c and INFLATES its `t_go=R/V_c`, so a live consensus SELF-POLLUTES and runs T_d away
(to ~99–105 s at R≈5000 m mid-course). **The one-shot launch exchange IS the state-sharing** (lands on advisor
#2's fallback with the mechanism pinned). Headline: Δτ(:solo)=2.34 s → Δτ(:salvo)=0.52 s (~4.5× collapse) with
BOTH hitting (<1 m); the near missile stretches (τ 5.04→6.87 s) via a ⟂-LOS-velocity WEAVE (detour ~2×) to meet
the far reference's natural 7.39 s. The metric SELF-JUSTIFIES (spread→0 IS the number) → **no defender model
needed** (deferred). The ITCG terminal blowup (V_c→0 mid-weave) is bounded two ways: `VC_FLOOR` in `time_to_go`
(the estimate) + `clamp_accel` at the consumer (the command). The solo degenerate moves to the LAW level
(`err==0` early-returns `pn_accel` bit-exact; a 1-missile salvo is loader-forbidden). `FINDINGS.md` pinned the
geometry + the RATIO + conservative one-sided bounds; advisor RE-CONSULTED after the numbers.

Gate 1 (primitive green — `core/src/guidance.jl`, pure/RNG-free/no-LinearAlgebra, +43 tests → 2174): NEW
`time_to_go(los_r, V_c) = los_r/max(V_c, VC_FLOOR)` (the receding/CPA guard → finite, convention 6),
`salvo_consensus(t_go_list) = maximum(...)` (the only reachable common time; singleton `===` itself — the
additivity anchor), `impact_time_control_accel(m,t,tgt,t_d; N, K_it)` = `pn_accel` base + a `(K_it·err·‖v‖)·v̂⊥`
⟂-LOS feedback that STRETCHES an EARLY missile (err>0). TWO GUARDS: (i) `err==0.0` early-returns `base` bit-exact
(NOT `base+zero(Vec3)` — the −0.0+0.0→+0.0 flip); (ii) the head-on floor `‖v⊥‖<1e-6` early-returns `base` (the
normalized-direction full-magnitude trap). `COOPERATION_MODES=(:solo,:salvo)` + `VC_FLOOR=50.0` added; `pn_accel`/
`GUIDANCE_MODES`/etc. UNCHANGED (byte-identity anchor). `test_guidance.jl` arms: `time_to_go=R/V_c` + the
receding→finite guard; `salvo_consensus=max` + singleton `===` + N-pin; the direct feedback recompute (a DIFFERENT
expression — the sign/transpose catch); the `err==0` command `===` `pn_accel` bit-exact no-op; an EARLY missile
gets a path-LENGTHENING command (`dot(fb, v⊥)>0` kinematic anchor). Slices 1–13 byte-identical (golden +
determinism green — guidance.jl stays pure).

Gate 2 (wired — `core/src/missile.jl` + `scenario.jl` + `radar.jl`, +48 tests → 2222): the NEW `:datalink` kind
(`scenario.jl`) → `[SalvoCoordinator]`, a NON-PHYSICAL entity (no mover) carrying ONLY the phase-2 `build_env!`.
`SalvoCoordinator.build_env!` gathers every `kind===:missile` interceptor's truth t_go (the esm/gps count-by-kind
precedent, never hard-coded ids), latches `T_d = salvo_consensus(...)` ONCE (the `haskey(c,:salvo_td)` lazy-latch),
and publishes `w.env[:salvo_t_d] = T_d − w.t` each tick as the SINGLE writer (survives `empty!(w.env)` — phase 2 →
live for phase-4 decide!). `Autopilot.decide!` gains the `:salvo` branch gated `coop===:salvo &&
haskey(w.env,:salvo_t_d)` → `impact_time_control_accel(...; K_it=k_it)`; every non-salvo arm is the slice-10/11/12
arithmetic TEXTUALLY UNCHANGED (byte-identity by construction — the `:salvo` fetch lives INSIDE its branch). NEW
per-missile telemetry `t_go`/`impact_time_err` (SHIPPED whenever a coordinator is present — under `:solo` the error
is SHOWN but not applied; the coordinator ships `salvo_t_d`/`T_d`); all SCALARS (no `float()`-crash). `k_it`
(`c[:k_it]`, default 0.45, LOAD-validated >0) is a KNOB-addressable live gain. `LIVE_FIDELITY_MODES += cooperation`
(radar.jl, one-list-no-drift); `set_fidelity` gains **NO new guard** — class 4c, `:solo↔:salvo` LIVE-SETTABLE (the
`:integrator`/`:autopilot` precedent, the CONTRAST to slice-13 `:scan`'s introduce-reject). `_validate_missile`:
a `:datalink` scenario needs ≥2 `:missile` interceptors (LOAD error). test_missile/test_determinism/test_server +
scenario arms; slices 1–13 byte-identical (SalvoCoordinator is SCENARIO-instantiated, never globally registered —
absent a `:datalink` nothing writes/reads the field).

Gate 3 (scenario + Godot spatial-view extension + verifiers — visible live, +37 tests → **2259**):
`scenarios/slice14_salvo.yaml` — geometry F (near mA elev `atan2(1500,6000)=14.036°`, far mB `atan2(1500,9000)=
9.462°` — the loader's speed/elevation construction reproduces the probe's `750·los_unit` aim exactly), the common
CV target tgt1, the `[SalvoCoordinator]` `link` `:datalink` node; `cooperation:solo` DEFAULT (the button REVEALS
the fix) + `guidance:pn`/`autopilot:ideal` HELD; `k_it`/`n_pn`/`a_max` sliders on mA. **RE-PROBED on the EMIT-GRID
wire** (`emit_probe.jl`, convention 10 — loads through `load_scenario→tick!` and samples `los_range` every
emit_every=16): **Δτ(:solo)=2.352 s → Δτ(:salvo)=0.528 s, RATIO 4.45×, both hit** (frame-sampled miss ≤8.67 m —
the CPA falls BETWEEN 16-tick frames, so the true <1 m intercept reads coarser; bounds set against the wire, NOT
the per-tick FINDINGS); RNG-free replay bit-identical. mB's CPA is IDENTICAL (7.392 s) in both modes — it IS the
reference; mA does all the stretching (5.040→6.864 s). Godot `Sandbox.gd`: the SPATIAL view EXTENDED (no new mode)
— `COOPERATION_RUNGS=(solo,salvo)`, `_on_cooperation_pressed`, the `cooperation` branch CHECKED FIRST in
`_setup_spatial_fid_btn` (BEFORE the held guidance/autopilot — convention 9), the "coop:" button + badge; the NEW
VISUAL — `_draw_salvo` renders N interceptors with PER-MISSILE colored trails (`_salvo_trails`, amber near / cyan
far) + nose markers + per-missile LOS to the common target + a `t_go`/range label each (the arrival-timing readout;
the coordinator's `salvo_t_d`/`T_d` + each missile's `impact_time_err` render as text). Slice-1..13 views UNTOUCHED
(the discriminator falls through — no `cooperation` key). **THE FOUR PROOFS GREEN:** `net/slice14_verify.gd` (S14V
OK, exit 0 — drives the real server: `:solo` Δτ=2.352 s SPREAD [mA CPA 5.04/mB 7.39], the per-missile CPA + a
pos-sequence checksum BIT-IDENTICAL on same-config replay [class-4c RNG-free determinism, NOT slice-13's
RNG-affected pos], `set_fidelity cooperation salvo` ACCEPTED LIVE → Δτ=0.528 s COLLAPSE with both hitting, the 4.45×
ratio, miss ALWAYS vs the true `:target`); `net/slice14_ui_test.gd` (S14UI OK — the cooperation cycler solo↔salvo,
the held keys untouched, badge/button track, `k_it`→mA `set_param`, reset resyncs to solo); the `Sandbox.tscn`
headless smoke-load (server `WARMING→LISTENING→DONE` ⇒ the scene connected + handshaked, NO GDScript errors); and
the **windowed shot-harness** (`_draw` fires only windowed — [[ewsim-godot-headless]], Vulkan/RTX 5090): `:solo` =
mA (amber) at the target r=1879 m/t_go=1.54 s while mB (cyan) lags at r=4781 m/t_go=3.87 s (the SPREAD), `:salvo` =
mA weaves a pronounced S-CURVE to delay (impact_time_err 2.30→0.57, closing_speed 1223→755 — the ⟂-LOS stretch
mechanism) so both converge. `test_scenario.jl` slice-14 loader arm: the three-key fidelity (cooperation:solo
default + the two held), the `:datalink`-kind truth-path invariant (`lk.kind===:datalink !==:target !==:missile`),
≥2 `:missile` + one common `:target` + one `[SalvoCoordinator]`, each missile `[BallisticMissile, Autopilot]`
(NO Seeker — RNG-free), the datalink has NO mover, `k_it` at a consumed comp key, asymmetric launch elevations,
the LOAD rejects (a 1-missile salvo / `k_it≤0`). Slices 1–13 byte-identical (golden + determinism green through
the scenario/client/test edits — no `core/src` change beyond gate 2). **Slice 14 COMPLETE — the missile guidance
arc's CAPSTONE; HANDOFF §10 item 13 CLOSED, the committed roadmap (items 1–13) is DONE.** DEFERRED (NAMED,
convention 9): consensus filtering / noisy-lossy-latent datalink (the Tier-C horizon); cooperative *estimation*
(A) + weapon–target assignment (B); the cooperative approach-ANGLE variant; an explicit point-defense/defender
model; N>2 / heterogeneous interceptors; decoys in the salvo.
Run the slice-14 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice14_salvo.yaml`, then
launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `coop:` button to
watch the two interceptors go from SPREAD [`:solo` — one reaches the target while the sibling is far] to TOGETHER
[`:salvo` — the near missile weaves a stretched S-curve to delay and both converge]; drag the `K_it` slider to walk
the tuning tension — too-cold → weak collapse, sweet spot → tight arrival, ≥0.55 → the near missile over-stretches
and misses). Re-run the gate-3 proof headless: start that server, then the console Godot `--headless --path
clients/godot --script res://net/slice14_verify.gd` (exit 0 = pass). The UI test needs NO server: `… --script
res://net/slice14_ui_test.gd`. **(stretch, deferred)** a Pluto Δτ-vs-geometry-asymmetry / stretch-vs-`t_d` sweep +
an offline `batch.jl` Δτ-vs-geometry grid (RNG-free here — the distribution path is trivial).

---

## Slice 15 — a RATE-LIMITED FIN SERVO

**Slice 15 — actuator/fin dynamics: a RATE-LIMITED FIN SERVO (HANDOFF §11 Tier-A, the FIRST horizon extension)** —
**COMPLETE. Gates 0–3 done & green (2347 tests).** The §10 committed roadmap (items 1–13) was DONE at slice 14;
slice 15 OPENS §11 Tier-A by taking the **actuator/fin half** of "6-DOF airframe + actuator/fin dynamics" and
DEFERRING the 6-DOF airframe half (trigger recorded in `docs/plans/slice15.md`). A THIRD `:autopilot` rung `:fin`
(`AUTOPILOT_MODES = (:ideal,:pid,:fin)`); a pure Tier-A swap behind the EXISTING `autopilot` knob — no contract
change.

THE CRUX (advisor, load-bearing — the convention-4c false-fidelity trap): a **linear** first-order fin servo
`τ_s·δ̇=δ_cmd−δ` with `a=k_δ·δ` collapses to `τ_s·ȧ=a_cmd−a` — the `:pid` plant relabeled (`k_δ` cancels). So the
**nonlinear limits (δ̇_max, δ_max) carry the ENTIRE fidelity**; a purely-linear fin model is NOT new physics.
PROVEN by the gate-1 `:pid`-equivalence anchor (δ̇/δ→∞ ⇒ `fin_autopilot_step` tracks the `:pid` plant to `atol`;
maxdiff ~3.8e-13). The degeneracy is a FEATURE, stated + tested.

Gate 1 (primitives, `core/src/guidance.jl` — pure, RNG-free, no LinearAlgebra): `fin_autopilot_step` (PID command
`u=kp·e+ki·e_int+kd·ė` → `δ_cmd=clamp_accel(u/k_δ,δ_max)` → `δ̇=clamp_accel((δ_cmd−δ)/τ_s, δ̇_max)` [THE RATE LIMIT]
→ `δ′=clamp_accel(δ+δ̇·dt,δ_max)` → `a_ach=k_δ·δ′`; returns `(a_ach, ap′, fin′, diag)` with `diag=(delta,
delta_rate, rate_sat, defl_sat)`), `fin_actuator_init`, `FinState=@NamedTuple{δ::Vec3}`. `AUTOPILOT_MODES += :fin`
(one-list-no-drift, before radar.jl). `autopilot_step`/`pursuit_accel`/`pn_accel` UNCHANGED (byte-identity anchor);
`clamp_accel` reused as the non-finite-safe magnitude clamp. `AutopilotState` STRUCTURALLY FROZEN — δ lives in its
OWN `:fin_state` (advisor #4: growing the NamedTuple perturbs every `:pid`/`:ideal` determinism fingerprint).
`test_guidance.jl` (+92): the `:pid` equivalence (the crux), the RATE-limit ramp (`‖δ‖=δ̇_max·t` under a step — an
external kinematic anchor), the deflection pin (`a=k_δ·δ_max` exact), the effectiveness map, the diag flags
(rate_sat/defl_sat light exactly when their clamp binds), zero/τ_s→0-safe.

Gate 2 (wired): the `:fin` branch in `Autopilot.decide!` (`missile.jl` — the `:ideal`/`:pid` arm TEXTUALLY
UNCHANGED, gated `mode===:fin`; `a_ach=clamp_accel(·,a_max)` crash-guard tuned NOT to bind; `:fin_state` threaded);
SCALAR fin telemetry `fin_defl`/`fin_rate`/`fin_rate_sat`/`fin_defl_sat`/`g_onset` (`g_onset=‖a_ctrl−a_prev‖/dt`,
the achieved-g build rate ≤ the cap by construction) shipped ONLY when `mode===:fin` → byte-identical wire for
`:ideal`/`:pid` (no Array → no `float()` client crash — convention 13). `scenario.jl` parses + LOAD-validates the
fin comp keys `k_delta`/`delta_max`/`delta_rate_max`/`tau_fin > 0` (the mass/`a_max`/`tau` precedent). Fidelity
plumbing FREE: `LIVE_FIDELITY_MODES.autopilot = AUTOPILOT_MODES` picks up `:fin` (NO re-list), and `set_fidelity`
needs NO guard — **class 4c** (physics-changing, NO RNG → no draw-topology to flip → introduce-safe, LIVE-settable;
the `:integrator`/`:autopilot`/`:apn`/`:cooperation` precedent, the CONTRAST to slice-13 `:scan`'s reject).
test_missile/test_determinism/test_server arms: the g-onset cap on the wire (peak ≤ `1.02·k_δ·δ̇_max`, `:ideal`
uncapped ≫ 2·cap), the isolation (`defl_sat==0 && saturated==0` in the guided window), `:ideal↔:pid↔:fin`
trajectories DIFFER (not-a-dead-knob, no RNG), replay bit-identical (pin `t`+pos, RNG-independent), `:fin`
introduce clean both directions, `set_fidelity :autopilot :fin` accepted live, a degenerate δ̇_max slider can't
crash a tick.

THE LESSON (gate-0 EMPIRICAL PIVOT, 12 probes — the slice-12/14 discipline realized): the fin rate limit **CAPS
THE G-ONSET RATE** `|da_ach/dt| ≤ k_δ·δ̇_max` (`a_ach=k_δ·δ`, δ slews ≤ δ̇_max ⇒ a jerk cap), cleanly DISTINCT from
slice-9's steady-state GAIN undershoot `1/(1+Kp)` and slice-10/12's MAGNITUDE cap `a_max`. THE ISOLATION (advisor
#2, ASSERTED): `k_δ·δ_max=2500 ≤ a_max=2600` and the maneuver tuned so `fin_defl_sat==0 && saturated==0` in the
guided window → the g-onset number is a CLEAN rate cap, NOT a slice-10 magnitude clamp in a fin costume (the three
numbers separable: rate cap 2000, g cap 2500, mag cap 2600). THE "LACK OF EFFECT" IS THE LESSON (user-ratified
2026-07-10): the MISS does NOT open — point-mass PN is robust to actuator rate limiting (the planned "saturation
opens the miss" did NOT materialize) — which is precisely WHY the DRAMATIC actuator failure modes (guidance-loop
limit cycle, α-limited maneuverability, the radome/body-rate parasitic loop) genuinely need the DEFERRED 6-DOF
airframe (empirically: PN+α-β+first-order actuator is unconditionally stable, no limit cycle even at N=55). Pin
the g-onset CAP RATIO, NEVER a miss ratio (misses are sub-meter and `:fin`'s is not worse than `:ideal`'s).

Gate 3 (scenario + Godot spatial-view extension + verifiers — +36 tests → **2347**): `scenarios/slice15_fin.yaml`
(`autopilot:fin` default + `guidance:pn` HELD; the slice-10/12 crossing geometry + a maneuvering target
[a_lat=160, turn_sign=+1]; the fin constants k_δ=5000/δ_max=0.5/δ̇_max=0.4/τ_fin=0.02; δ̇_max the lesson slider).
`Sandbox.gd`: a value-keyed discriminator branch (`autopilot=="fin"`, checked BEFORE `guidance` — the slice-13/14
"lesson key before the held keys" precedent, the FIRST value-keyed branch) routes the shared button to the
AUTOPILOT cycler as a **PER-SCENARIO 3-ring** `_autopilot_rungs = [ideal,pid,fin]` (slice-9 stays the 2-ring so
its UI test's 2-cycle assertion holds; the 3-ring SURVIVES reset). The generic readout auto-renders the fin
scalars (fin_defl/fin_rate/fin_rate_sat/g_onset/track_gap — no new mode, the slice-8..14 "stay spatial"
precedent). Numbers PROBED against the live `load_scenario→decide!→integrate!→telemetry` wire at the emit grid
(`temp/slice15_probe/emit_probe.jl`, RNG-free → EXACT): `:fin` δ̇=0.4 → g_onset caps at **2000** (=k_δ·δ̇_max),
rate_sat binds (11 emit frames), defl_sat/sat=0, miss 6.63; raise δ̇=2.0 → cap RISES to **10000** + binds LESS
(rate_sat 11→5) + miss UNCHANGED (6.71 — the lever, the "lack of effect"); `:ideal` ships NO fin keys
(byte-identical wire), miss 9.23. **Four proofs green:** `net/slice15_verify.gd` (`S15V OK`, exit 0 — the cap
binds isolated + rate_sat drops when δ̇_max raised + `:ideal` no-key + RNG-free bit-identical replay + live
`set_fidelity autopilot fin`); `net/slice15_ui_test.gd` (`S15UI OK` — the 3-ring walks ideal→pid→fin, wraps,
survives reset, δ̇_max slider → set_param m1, guidance untouched); `Sandbox.tscn` headless smoke-load
(`EWSIM_SERVER_DONE`, no parse errors); the windowed shot-harness capture (the curved fin-limited trail + the LOS
line + a_cmd 441 vs a_ach 330 lag mid-jink — "the fins can't keep up," all fin scalars rendered, no `float()`
crash). **Slice 15 COMPLETE — OPENS HANDOFF §11 Tier-A.** DEFERRED (NAMED, convention 9): the 6-DOF airframe /
angle-of-attack half (the trigger recorded — a lesson needing the body to point off the velocity vector: α-limited
maneuverability or a radome/body-rate parasitic loop; the fin state δ that 6-DOF's moment equation consumes is now
BANKED); a 2nd-order actuator (ω_a/ζ_a bandwidth/damping — Option 3, a different lesson); per-channel fin
allocation / hinge-moment / stall; the actuator feeding a MOMENT (→α→lift) = 6-DOF.
Run the slice-15 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice15_fin.yaml`, then
launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial view; cycle the `autopilot:` button
through ideal→pid→fin to watch the plant ladder; drag the δ̇_max slider — lower it and the fins lag harder [bigger
a_cmd–a_ach gap, g_onset capped], raise it toward 2.0 and `:fin` approaches `:ideal`, the miss unchanged). Re-run
the gate-3 proof headless: start that server, then the console Godot `--headless --path clients/godot --script
res://net/slice15_verify.gd` (exit 0 = pass). The UI test needs NO server: `… --script res://net/slice15_ui_test.gd`.
**(stretch, deferred)** a Pluto MISS-vs-δ̇_max / phase-lag-vs-τ_s sweep (the rate-limit lesson as a curve).

---

## Slice 16 — the 6-DOF airframe I — pitch-plane rotational dynamics

**Slice 16 — the 6-DOF airframe, FIRST HALF: pitch-plane ROTATIONAL DYNAMICS (HANDOFF §11 Tier-A)** — the
DEFERRED rotational half of the Tier-A "6-DOF airframe + actuator/fin dynamics" entry (slice 15 did the
actuator/fin half). The FIRST rotational state in the project: slices 8–15's missile was a POINT MASS whose
`att` was a KINEMATIC velocity-alignment (a named approximation); here `att` becomes a DYNAMICAL OUTPUT of the
aero pitching moment — the direct ROTATION analog of slice 8's ballistic force-integrator (which made `pos` a
force-integrated output). This opens the committed slice-16→17→… arc that recapitulates 8→9→10 FOR ROTATION,
frames/signs FIRST. **2409 tests, all green.**

THE LESSON (the af_cma slider — a live KNOB, NOT a fidelity button): `Cmα` is the STATIC STABILITY derivative
∂Cm/∂α. Drag it through 0 — Cmα<0 (STABLE) → the airframe WEATHERVANES: α oscillates about trim at the
short-period ω_sp=√(−Cmα·QSd/I), decaying under Cmq damping, the nose TRACKS the flight path. Cmα>0 (UNSTABLE)
→ it TUMBLES: |α| diverges, ω_sp is imaginary (the readout ships the FINITE_CEIL sentinel via `_finite`). The
#1 SIGN TRAP (a DOUBLE flip of both the α=θ−γ definition AND the moment sign oscillates at the SAME ω_sp), so
the moment SIGN is pinned DIRECTLY in `test_airframe.jl` (advisor tooth #1), not just the frequency.

THE ISOLATION (the slice-16 scope + the headline proof): rotation reads the live flight condition (V, γ) but
does NOT feed back into (pos, vel) — no α→lift→γ coupling this slice (that is slice 17). So the TRAJECTORY is
BYTE-IDENTICAL across any Cmα (verifier: posdiff = 0.0 across the Cmα-sign flip); only the ATTITUDE changes.
This is WHY there is NO `:airframe = point_mass | 6dof` fidelity: a toggle that leaves the path bit-identical
would name a coupling it cannot produce until slice 17 (the convention-4c FALSE-FIDELITY / dead-knob trap —
the slice-15 `k_δ`-cancellation precedent). **Option-P′ (advisor-reconciled):** the client recognizes the view
by a handshake `airframe_view` marker (the `range_axis_m`→cfar precedent), keeps the core PARAMS-PRESENCE
gated (`haskey(c, :af_cma)`), and DROPS the shared fidelity button (nothing to cycle — the Cmα slider is the
lesson lever). Class **4c** (physics-changing, NO RNG — truth-fed, no seeker → "draw-count invariance
VACUOUS", the 3rd consecutive 4c after slices 14/15; LIVE-SETTABLE, no `set_fidelity` guard — the
:integrator/:autopilot/:apn/:cooperation precedent).

GATES. **Gate 1** — `core/src/airframe.jl` (the rotation analog of `dynamics.jl`, pure/RNG-free/no-LinearAlgebra):
`AirframeParams` (S, d, I, Cma, Cmd, Cmq, ρ), `pitch_moment` (M = QSd·(Cmα·α + Cmδ·δ + Cmq·q̄), q̄=q·d/2V,
V-floor guard), `rk4_rot` (the generic (θ,q) stepper, structured so slice-17's joint [pos,vel,θ,q] step reuses
the closure shape), `airframe_step`, `short_period_freq` (NaN-guarded for Cmα≥0 — a live slider crossing 0
can't throw), `trim_alpha` (δ=0 → EXACTLY 0, no 0/0 NaN). `test_airframe.jl` (closed forms with the 3 advisor
teeth: moment sign BOTH Cmα signs; V/γ-frozen SHM RK4-exact to ~1e-15; damping log-decrement pins ζ, not just
ω_sp; divergence for Cmα>0). **Gate 2** — `BallisticMissile.integrate!` gains `_integrate_airframe!` gated on
`haskey(c, :af_cma)` (the `:a_ctrl`-guard precedent → slices 8–15 BYTE-IDENTICAL); phase-2 build_env! ships the
`pitch_theta/gamma/alpha/pitch_q/omega_sp/alpha_trim` telemetry; `scenario.jl` parses the `airframe:` block
(Cma NOT sign-guarded — crossing 0 IS the lesson). `test_missile.jl` airframe wiring (ISOLATION bit-identical
to a no-airframe twin, sign lesson, att-round-trip, live-Cmα crash-safe sweep). **Gate 3** —
`scenarios/slice16_airframe.yaml` (open-loop 40°/500 m/s ballistic climb, alpha0=0.15 kick, af_cma the sole
knob, NO fidelity); `_airframe_view_info` + `scenario_frame` merge (the handshake marker); the Godot airframe
view (button dropped; the missile marker draws the NOSE off θ vs a CYAN VELOCITY reference off γ — the gap IS
α, labeled). **Four proofs green:** `net/slice16_verify.gd` (`S16V OK` — STABLE max|α|=0.150 rad / ω_sp=2.40
real, REPLAY bit-identical 0.150115, UNSTABLE max|α|→1.0e6 / ω_sp=1e9 sentinel, **posdiff=0.0** the isolation);
`net/slice16_ui_test.gd` (`S16UI OK` — stays spatial, _fid_kind=airframe, button HIDDEN, af_cma slider →
set_param m1, reset keeps it hidden); `Sandbox.tscn` headless smoke-load (`EWSIM_SERVER_DONE`, no parse
errors); the windowed shot-harness capture (TWO contrasting shots — stable α=3.2° nose≈velocity/ω_sp=2.31 vs
mild-unstable α=23.8° nose visibly off velocity/ω_sp=1e9 sentinel). Numbers PROBED against the live
load_scenario→tick!→telemetry wire, PINNED as conservative frame-sampled bounds (emit_every=16).

**Slice 16 COMPLETE — the 6-DOF airframe's rotational primitive is VALIDATED & BANKED.** DEFERRED (NAMED,
convention 9): **slice 17 = the inner α/g autopilot + the α→lift→γ coupling** (the real path-changing
`:airframe` toggle — a stable Cmα LANDS then, once the coupling exists for it to name; the fin state δ from
slice 15 feeds the moment equation); then α-limited-maneuverability miss → bank-to-turn (the 3-D quaternion+ω
superset, the geometry.jl→frames.jl "2-D first" precedent) → radome/body-rate parasitic loop. **Slice-17
CLIENT NOTE:** the airframe branch is checked FIRST in `_setup_spatial_fid_btn`; when slice 17 adds an
`:airframe` fidelity alongside `af_cma`, `_airframe_view` will be true AND a fidelity present, so value-guard
the branch then (else it hides the button slice 17 wants).
Run the slice-16 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice16_airframe.yaml`,
then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial airframe view; drag the
Cmα slider through 0 to watch the nose go from weathervaning to tumbling — the nose/velocity gap is α). Re-run
the gate-3 proof headless: start that server, then the console Godot `--headless --path clients/godot --script
res://net/slice16_verify.gd` (exit 0 = pass). The UI test needs NO server: `… --script res://net/slice16_ui_test.gd`.

---

## Slice 17 — the 6-DOF airframe II — the alpha to lift to gamma coupling

**Slice 17 — the α→lift→γ COUPLING: rotation feeds translation (HANDOFF §11 Tier-A, the 6-DOF airframe's
SECOND half)** — the FIRST rotation→translation coupling in the project (2488 tests). Slice 16 made `att`
(θ, q) a DYNAMICAL output of the aero pitching moment but kept it ISOLATED — rotation read (V, γ) yet did
NOT feed back into (pos, vel), so the trajectory was BYTE-IDENTICAL across any Cmα (posdiff=0.0). Slice 17
CLOSES that loop: the angle of attack **α = θ−γ generates a body lift ⟂ velocity that TURNS the flight
path** (α→lift→γ̇) — the coupling the whole slice-16 isolation was BANKED to enable, and where the REAL
path-changing `:airframe = point_mass | pitch_coupled` fidelity finally lands (slice 16 refused it — a
path-bit-identical toggle would name a coupling it couldn't yet produce; the convention-4c false-fidelity
trap). SCOPE: pitch-plane ONLY, **OPEN-LOOP** (δ is a FIXED authored trim — no autopilot closes it; that is
slice 18), COUPLED (the joint `[pos, vel, θ, q]` state integrated in ONE RK4 step).

**Gate 1 — `airframe.jl` primitive (+20 arms).** `AirframeParams` gains `Cla` (lift-curve slope ∂C_L/∂α) as
its LAST field (byte-identity: slice-16 point_mass never reads it). `lift_accel(vel, θ, mass, p) = (Q·S·Cla·
α/m)·(−sinγ, 0, cosγ)` — body lift ⟂ v; the `(−sinγ,0,cosγ)` is v̂ rotated +90° in x–z, so +Cla gives γ̇>0
for α>0 (**the #1 SIGN TRAP**, pinned by BOTH `dot(a_lift,v̂)≈0` AND the γ̇ sign — a double flip survives a
magnitude-only test). `rk4_coupled(f, pos, vel, θ, q, dt)` — a FRESH generic 8-scalar joint RK4 (NOT a
composition of rk4_step+rk4_rot); it re-evaluates (V, γ) from the intermediate velocity WITHIN each stage =
the coupling, NOT operator-split. `const AIRFRAME_MODES = (:point_mass, :pitch_coupled)` before radar.jl
(one-list). Tests: steady-turn radius **R = 2m/(ρ·S·C_Lα·α) ≈ 5197 m** (isolation, Cmq=0, `atol=1e-2` — the
load-bearing closed-form anchor, SPEED-INDEPENDENT); lift sign; `rk4_coupled` constant-input exactness; the
**decoupled limit** `Cla=0` inertial ≡ `integrator_step ⊕ airframe_step` BIT-EXACT (`==`; the slice-16
1e-15 exactness does NOT transfer under gravity — the joint step re-evals V,γ mid-step).

**Gate 2 — wired (+32 arms).** `missile.jl`'s `_integrate_coupled!` branch, gated `haskey(:af_cma) &&
get(w.fidelity,:airframe,:point_mass)===:pitch_coupled` — the point-mass block wrapped VERBATIM in the
`else` (no code-share; the point-mass arithmetic stays bit-identical). Joint step; θ lazy-init from the
PRE-step launch γ (contrast the point-mass `_integrate_airframe!` POST-step seed); force = `total_accel` +
`lift_accel` (a_ctrl EXCLUDED — guidance→lift coupling is slice 18); impact clamp DUPLICATED; RK4-ONLY
(ignores the `:integrator` euler rung — the coupled short-period is stiff). **THE STAGE-θ FIX (advisor,
load-bearing):** the deriv closure reads the RK4 STAGE `TH`, NEVER the entry θ — the entry-θ bug is only
~0.019 m/8 s (measured), invisible to the R test (α≈const) and the decoupled test (Cla=0), so ONLY a
transient GOLDEN catches it (pos=(2187.823608281557, 3010.178483035902), θ=1.251491571778638, q=0.06393471,
atol 1e-6/1e-9). Lift telemetry `a_lift` / `turn_radius_m`=V²/a_lift gated on `:pitch_coupled` NOT af_cma
(else a slice-16 point_mass wire breaks). `LIVE_FIDELITY_MODES` gains `airframe = AIRFRAME_MODES` — the ONLY
plumbing edit (`_KNOWN_FIDELITY_KEYS`/`set_fidelity`/`_validate_fidelity` all derive; NO set_fidelity guard,
class 4c). Loader parses `airframe.cla`→`:af_cla`, validate FINITE not sign. Arms across test_missile (golden
stage-θ pin, non-dead toggle sep>500 m + ballistic twin, lift readout, att round-trip), test_determinism
(coupled A-vs-B bit-identical + pristine rng, :point_mass↔:pitch_coupled CHANGES it, introduce-safe both
dirs, check-G 25 s unstable→finite through build_env!→_finite), test_server (set_fidelity write/reject/
introduce + live af_cla/af_delta slider→tick).

**Gate 3 — scenario + Godot + the four proofs.** `scenarios/slice17_coupling.yaml`: ONE open-loop missile,
`fidelity: {airframe: pitch_coupled}`, `airframe: {…, delta: 0.15 (MANDATORY nonzero — the non-dead toggle),
cla: 20.0, …}`, gravity ON, drag OFF; the af_delta / af_cla turn levers as knobs. Live-wire probe (convention
10): coupled end (2187.8, 3010.2) vs ballistic (3064.2, 2257.3) → posdiff 1155 m end / 876 m frame-max;
δ→0 straightens to 91 m. CLIENT (`Sandbox.gd`): the `:airframe` cycler comes BACK, REUSING `_fid_kind =
"airframe"` (so the slice-16 curved-trail + nose/velocity/α drawing ALL carry over unchanged) with the drop
VALUE-GUARDED on `_fidelity.has("airframe")` — slice 17 (fidelity present) shows the point_mass↔pitch_coupled
cycler; slice 16 (no fidelity) still drops it. Four proofs GREEN: `slice17_verify.gd` (S17V OK — coupled
CURVES vs point_mass ballistic posdiff 876 m > 500 [the INVERSE of slice-16's 0.0], lift keys coupled-only,
held-seed replay posdiff 0.0, af_delta→0 straightens 69.5 m); `slice17_ui_test.gd` (S17UI OK — the cycler
shows + wraps + set_fidelity, the sliders set_param, AND a slice-16 handshake still DROPS the button — the
value-guard both ways); `Sandbox.tscn` smoke-load (server DONE); the windowed shot (the CURVED coupled trail
+ the nose leading the cyan v(γ) reference by the labeled α gap, button "airframe: pitch_coupled").

**Slice 17 COMPLETE — the α→lift coupling is REAL; the 6-DOF airframe's translation-coupling half is DONE.**
Class **4c** (physics-changing, NO RNG — truth-fed open-loop, no seeker → "draw-count invariance" VACUOUS;
the 4th consecutive 4c after 14/15/16; live-settable, NO set_fidelity guard). DEFERRED (NAMED, convention 9):
**slice 18 = the inner α/g autopilot + α-limited maneuverability** — invert PN's `a_cmd → α_cmd = a_cmd·m/
(Q·S·C_Lα) → δ` (the slice-15 fin state δ finally does work through the `Cmδ·δ` moment term; the `a_cmd/Q`
divide is a CRASH-SAFETY Q-floor site), then the flight-condition-dependent aero g-limit `a_max_aero = Q·S·
C_Lα·α_max/m` miss (less g at low speed / high altitude — distinct from slice-10's fixed kinematic a_max);
induced drag (`C_Di ∝ C_L²`); then bank-to-turn / 3-D (quaternion+ω) → radome/body-rate parasitic loop.
Run the slice-17 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice17_coupling.yaml`,
then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-uses the spatial airframe view; cycle the
`airframe` button point_mass↔pitch_coupled to watch the SAME missile fly ballistic vs curve; drag the δ/C_Lα
sliders to tighten the turn). Re-run the gate-3 proof headless: start that server, then the console Godot
`--headless --path clients/godot --script res://net/slice17_verify.gd` (exit 0 = pass). The UI test needs NO
server: `… --script res://net/slice17_ui_test.gd`.

---

**Client visual-polish pass (2026-07-14, post-slice-17)** — a cross-cutting DISPLAY-ONLY upgrade of
`Sandbox.gd` + `project.godot` (dark-navy `default_clear_color`); ZERO physics, ZERO core/scenario/wire
changes (git touches exactly those two files). Shared chrome: a one-palette set of display consts
(`COL_*`), the left UI panel in a styled `PanelContainer`, the scalar readout split across up to THREE
adaptive columns of ~18 rows (`_readout2`/`_readout3`, null-guarded — the salvo view ships ~46 keys and
one 18-px column ran off the window over the §12 badge; the headless UI-test harnesses build `_readout`
only and still pass), readout font 18→14. SPATIAL view: `_draw_spatial_backdrop()` (sky gradient +
ground fill + a labeled km grid off `_nice_step` — the first axis scale this view has had; mapped through
the same `_world_to_screen` as the markers so the auto-expanding extents stay honest), `_draw_trail()`
(age-faded polyline, oldest→transparent) for the missile + per-salvo trails, `_draw_missile_body()` (a
shared silhouette marker — hull + nose cone + tail fins — replacing the bare triangles everywhere,
including the salvo view). PLOT views (cfar/geoloc/esm/gps): filled `COL_PANEL_BG` panels behind every
plot rect + the GPS sky disc. AIRFRAME view (slice 16/17) DEEPENED: the α WEDGE (a translucent fan swept
v(γ)→nose(θ) — the angle of attack drawn AS an angle), arrowheads on the v/lift vectors, the slice-17
LIFT arrow (length off the core's `a_lift`, on the nose side of v = sign(α)), the STEADY-TURN ARC (the
core's `turn_radius_m` drawn as a dashed osculating circle through the missile — the R=2m/(ρSC_Lα·α)
anchor made visible; skipped when R→∞/CEIL), and an α-HISTORY STRIP CHART (bottom-right panel; samples
the core's `<id>.alpha` per state frame into `_alpha_hist`, display-clamped ±π so a tumble's
FINITE_CEIL can't wreck the autoscale; dashed cyan `alpha_trim` reference — the slice-16 weathervane
RINGING about trim vs the pegged tumble trace, as a time series; cleared on reset). Proofs: all 16
`*_ui_test.gd` GREEN post-change (TOTAL_FAILS=0); four windowed shots eyeballed via the throwaway
shot-harness recipe (slice 17: curved trail + wedge + lift arrow + turn arc + strip chart; slice 16:
textbook damped α ringing onto trim, button correctly dropped; slice 2: grid + below-horizon target;
slice 14: three-column readout fits, per-missile silhouettes + faded trails). Julia core untouched —
the 2488-test suite is out of scope of this change by construction.

---

## Slice 18 — TERRAIN MASKING + the 3-D client view

**Slice 18 — TERRAIN MASKING + the 3-D client view (HANDOFF §11 Tier-A "higher fidelity behind existing
knobs" — `propagation` is the named seam) — COMPLETE & green (2604 tests).** USER-DIRECTED INSERTION
(2026-07-14, "work on 3d representation and terrain"): the inner α/g autopilot slice17.md had slotted as
"slice 18" SHIFTS to **slice 19** with its trigger intact (HANDOFF §11 updated). The FIRST terrain in the
project and the client's FIRST true 3-D view. Plan: `docs/plans/slice18.md`.

Gate 1 (pure lib, 54 tests): `core/src/terrain.jl` — an authored ANALYTIC heightfield `h(x,y) = h0 +
Σ aᵢ·exp(−((x−cxᵢ)²+(y−cyᵢ)²)/(2σᵢ²))` (Gaussian hills: closed-form, smooth, ZERO RNG — nothing to
desync, simpler even than class 4a needs; seeded fractal terrain DEFERRED). `terrain_height`,
`terrain_clearance` (SIGNED min of ray_z − h over interior samples of the straight segment at
`los_step_m`; endpoints EXCLUDED — a mast on the ground must not self-block; the fixed fraction grid
`s = i/(n+1)` makes it bit-exact SYMMETRIC in (p1,p2) — an asymmetric walk would make "who shoots first"
physical), `terrain_los_clear` (= clearance > 0, the HARD shadow — knife-edge diffraction is the named
rung above), `terrain_grid` (the row-major n×n wire sample). Test teeth: hand-computed height literals
(e^(−1/2) at r=σ), LEVEL-ray clearance bit-exact `==`, a PEAK-SAMPLED hill where clearance == z−A exactly
(blocking sign-exact + monotone across A = z), bit-exact swap symmetry, endpoint exclusion, degenerate
p1==p2 + sub-step hops never throw, and the grid LAYOUT pinned against an ASYMMETRIC terrain (the
transpose canary — a mirrored client mesh is silent). WATCH-ITEM (caught by the first run): a TILTED
ray's minimum of (ray_z − gaussian) sits slightly OFF-peak (linear ray vs quadratic crest), so only the
LEVEL-ray anchor is exact — the tilted case is bracketed, not pinned.

Gate 2 (wiring, +39 tests): `PROPAGATION_MODES = (:free_space, :two_ray, :terrain)` (the ONE list —
`LIVE_FIDELITY_MODES`/`set_fidelity` picked it up with zero edits). `_target_snr` gains the `:terrain`
elseif: free-space link budget + the LOS mask → `(0.0, false)` when occluded (exactly the below-horizon
policy shape); **no terrain entity ⇒ bit-exact `:free_space`** (the slice-4 mismatched-EP no-op
precedent, tested `==` over 20 ticks — a live `set_fidelity propagation terrain` on ANY prior scenario
can neither crash a tick nor move a byte). Class **4a** (draw-invariant: detect_once draws
unconditionally, the mask gates only booleans — pinned by a 3-rung 50-tick RNG-lockstep test;
introduce-safe, live-settable, NO set_fidelity guard). Terrain is a NON-PHYSICAL `kind: terrain` entity
(the `:datalink` precedent — no hooks; `_nearest_target`/the radar sweep skip it): hills authored as a
YAML list, stored as FLAT SCALAR keys `hillK_a/x/y/s` + `:n_hills` (knob-addressable shape;
**LOAD-STATIC this slice** — the handshake grid ships once, a live hill slider would silently stale the
client mesh; hill-knob-with-grid-refresh DEFERRED), load-validated per convention 5 (σ>0, grid_n≥2,
ordered extents, hills complete per index, ≤1 terrain entity via `_validate_terrain`). `_terrain_info`
(the `_cfar_axis_info` shape) ships `terrain_grid`/`terrain_n`/`terrain_extent_m`/ids ONCE at handshake —
**`terrain_grid` presence is the client's 3-D-view discriminator**. Telemetry
`<radar>.terrain_clearance_m` (signed, `_finite_coord` — a signed readout keeps its sign) is gated on the
RUNG not entity presence (the slice-17 lift-keys precedent, tested both ways). NEW general lever:
`ConstantVelocity` gains an OPTIONAL presence-gated `alt_hold_m` comp (pins the mover's z each
integrate! — makes ALTITUDE knob-addressable; absent everywhere prior ⇒ byte-identical; the `:af_cma`
presence-gating precedent). CFAR path composes for free (`_target_snr` is shared; a shadowed target's
profile bump is 0); the clearance READOUT stays point-path-only (convention 9).

Gate 3 (scenario + the 3-D view + four proofs): `scenarios/slice18_terrain.yaml` (seed 18) — a 30 m mast
radar, a 3-hill ridge (crest A=250 @ x=6 km σ=900; asymmetric ±2.6 km flanks < 20 m on the y=0 LOS),
a 120 m penetrator inbound at 250 m/s from 14 km. Probe pins (live wire): DARK the whole approach →
POP-UP t=36.724 s x=4819 m (clearance −208.6 → +, SNR floor −120 → 50.7 dB), ZERO detections while
masked, first detection t=36.801 s; alt_hold_m→1000 collapses the shadow (min clearance +31.4 m, visible
every tick); free_space same seed detects from frame 1 (SNR 32.2 dB at spawn). THE LESSON: terrain
masking / the low-altitude pop-up — altitude buys detectability and vice versa; the SIGNED clearance's
sign IS the verdict. CLIENT (the first Node3D content): `_enter_terrain_mode` (discriminated on
`terrain_grid`, checked after range/pri axes) builds a `CanvasLayer(layer=−1)` → `SubViewportContainer`
→ `SubViewport(own_world_3d)` → heightmap `ArrayMesh` via SurfaceTool (two tris/cell, height-tinted
vertex colors green→brown→tan, generated normals, CULL_DISABLED), emissive radar(cyan)/target(orange)
sphere markers, the LOS ray as an ImmediateMesh LINE colored by the CORE's `visible` verdict
(green/red — the client NEVER re-tests occlusion), a fading trail strip, and an orbit/zoom camera
(`_unhandled_input`; `_update_t3d_cam` guards `is_inside_tree()` for the off-tree UI harness). Mapping
sim(x,y,z-up) → Godot(X=x, Y=z·2.5, Z=−y) — T3D_VEXAG=2.5 is DISPLAY-ONLY and labeled in the HUD (§12
honesty; applied to markers AND mesh so relative occlusion reads true). The shared button stays the
PROPAGATION cycler but upgrades to the FULL 3-ring via a PER-SCENARIO `_prop_rungs` (the
`_autopilot_rungs` precedent, SLICED from the one `PROP_RUNGS` const): slice 1/2 keep their historical
2-ring (no phantom `terrain` rung), `_on_prop_pressed` generalized flip→ring (behavior-identical on the
2-ring). The 2-D canvas draws only the HUD (LOS CLEAR/TERRAIN MASKED + the signed clearance + the
vert-exag note). FOUR PROOFS green: `slice18_verify.gd` (S18V OK — handshake grid/extents/ids/fidelity
+ starts masked at the exact wire floor with negative clearance + EXACTLY one masked→visible transition
with pop-up x in [4300,5300] (live 4816) + detections ONLY while visible + clearance SIGN matches the
verdict on every frame + every :terrain frame ships the key + 2500-frame held-seed replay BIT-IDENTICAL
through the masked draws + free_space: all-visible, 488 detections in the window terrain kept dark,
clearance key GONE + alt 1000: all-visible, min clearance +31.4); `slice18_ui_test.gd` (S18UI OK —
terrain mode + grid adoption + the 3-D layer builds OFF-TREE + 3-ring wraps
terrain→free_space→two_ray→terrain each press sending set_fidelity + alt slider set_param + a state
frame drives markers/LOS + reset resyncs & clears the trail + a PLAIN handshake keeps the 2-ring;
NB the plain path drives `_on_prop_pressed` directly — its connect lives in `_build_ui`, never run
off-tree); `Sandbox.tscn` smoke-load (server DONE, no GDScript errors); TWO windowed shots (masked: the
ridge massif + the RED LOS ray dying into the crest + "TERRAIN MASKED −205 m" + visible:no/snr −120;
clear after alt→1200 over the wire: the GREEN ray crossing above the ridge + "LOS CLEAR +32 m" +
detected:YES/pd 1/snr 34.7). `test_scenario.jl` +1 loader testset (23 tests: parses, :terrain default,
single-lesson fidelity, one terrain entity with the flat hill keys, `_terrain_info` ships the 65² grid,
the target STARTS masked, alt_hold_m knob declared, propagation not a knob).

**Slice 18 COMPLETE — terrain masks the LOS; the client renders it in 3-D.** Class **4a** (the FIRST
4a since slice 11 — breaks the 14/15/16/17 4c streak; draw-invariant, introduce-safe, live-settable).
Terrain BANKS the heightfield that land CLUTTER (§11 Tier-A) needs. DEFERRED (NAMED): knife-edge
diffraction (the graded-shadow rung above `:terrain`); terrain-composed multipath + land clutter;
seeded fractal terrain (own Xoshiro at LOAD, never `w.rng`); hill knobs with a handshake grid re-ship;
terrain occlusion at the DF/ESM/seeker LOS sites (mechanical — the same `terrain_los_clear` call);
**slice 19 = the inner α/g autopilot + α-limited maneuverability** (the shifted slice-18-as-was).
Run the slice-18 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice18_terrain.yaml`,
then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-enters the 3-D terrain view; drag to
orbit, wheel to zoom; drag the altitude slider through ~800 m to watch the LOS ray flip red↔green; cycle
`prop:` through free_space/two_ray/terrain). Re-run the gate-3 proof headless: start that server, then
the console Godot `--headless --path clients/godot --script res://net/slice18_verify.gd` (exit 0 =
pass). The UI test needs NO server: `… --script res://net/slice18_ui_test.gd`.

---

## Slice 19 — the inner alpha/g AUTOPILOT + the flight-condition ceiling

**Slice 19 — the inner α/g AUTOPILOT: the airframe flies its own command (HANDOFF §11 Tier-A, the 6-DOF
arc's closed inner loop)** — the slice that makes the coupled airframe STEER ITSELF, and the FIRST time an
AERODYNAMIC limit — not a kinematic number — decides whether the missile hits. Slice 17 gave the missile a
body lift that turns the flight path, but δ was a FIXED authored trim: the airframe curved, it did not AIM.
Slice 19 closes the inner loop — the PN command is inverted through the aero into an angle-of-attack command
and thence a fin deflection (**`a_cmd → α_cmd → δ`**) — so the missile flies its own guidance command
*through the airframe* rather than by fiat. **THE FIRST COUPLED AND GUIDED MISSILE** (slice 17 was open-loop,
no target). Gates 0–2 and their numbers are in `docs/plans/slice19.md`; this entry is gate 3.

**THE LESSON (the `:airframe` button, the ONE toggled fidelity):** the achievable maneuver accel IS the
FLIGHT-CONDITION lift ceiling `a_max_aero = Q·S·C_Lα·α_max/m` ≈ **269 m/s²**. The SAME PN law, the SAME
target: `:point_mass` applies `a_ctrl` by fiat and **HITS (0.276 m true / 3.84 frame-sampled)**;
`:pitch_coupled` must MAKE its g from lift, the demand exceeds the ceiling for **59%** of the approach
(`aero_sat` lit), the missile pulls everything the air will give and **MISSES by 295.168 m** — a **1069×**
spread (76.8× frame-sampled). **The cap is distinct from every cap already in the suite** (the copy-paste
false-claim trap): slice 10/12's `a_max` is an authored MAGNITUDE clamp, slice 15's `k_δ·δ̇_max` a JERK/onset
cap and `δ_max` a DEFLECTION cap — slice 19's is a **FLIGHT-CONDITION** cap: what the air will give you *right
now*. Class **4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" is VACUOUS;
live-settable, NO `set_fidelity` guard — the 5th 4c after 14/15/16/17, with slice 18's 4a interrupting).

**GATE-3 FINDING 15 (BLOCKING, advisor-confirmed) — the `speed` knob the plan named "THE demo lever" is DEAD
on the wire.** `comp[:speed]` is written at `scenario.jl:319` and consumed **ONCE at load** (line 322, to build
`e.vel`); **NOTHING in `core/src/` reads it per-tick** (`server.jl:227` is the unrelated *playback* speed), and
`_reload!` (`server.jl:70-74`) rebuilds from the YAML on `reset` — so the set_param-then-reset escape hatch
wipes it too. A live `set_param(speed)` writes a comp key **no consumer reads**. **Why it survived to gate 3:**
gate 0's V0 sweep re-authored `pick_world(V0=…)` **per run** (a fresh launch each time) and never touched the
wire; gate 2's `test_server` drags `speed` but asserts only *no crash / finite* — **which a dead knob passes**.
This is the **dead-knob face of the false-fidelity class** (slice-15 `k_δ`-cancellation, slice-16
false-fidelity, slice-19 finding 1 `a_ctrl`) — **4th occurrence in this arc, and the first caught at gate 3.**
**THE FIX: `rho` is the live Q lever** — `rho_af = get(c,:rho,1.225)` is fetched EVERY tick by BOTH `decide!`
(`missile.jl:607`) and `integrate!` (`:88` → `_integrate_coupled!` → `AirframeParams` → `lift_accel`/
`pitch_moment`), so declaring it in `knobs:` needed **zero new consumer code**. It is structurally BETTER than
speed ever was: Q ∝ ρ **exactly linear** (measured 21.991 @ ρ=0.1 → 549.776 @ 2.5 = 25.0× for 25× ρ);
**confounded identically** (ω_sp ∝ √ρ moves ceiling AND response speed together) so it stays the DEMO lever and
α_max stays the clean CAUSATION knob — the plan's split preserved; and **it cannot break the first-CPA
condition** (a working speed knob would have: at V0 > 825 the missile OUTRUNS the target ⇒ post-CPA
re-crossing, the [[ewsim-missile-verifier-sampling]] hazard — so the dead knob was hiding a second bug).
**The tripwire that would have caught it, now shipped:** the verifier and `test_server` assert
`set_param(rho)` **MOVES `a_max_aero`** — not merely that nothing threw.

**GATE-3 FINDING 16 (design-shaping) — the miss is NON-MONOTONE in ρ; below ρ≈0.5 the LESSON REVERSES.** The
authored sweep peaks at **ρ ≈ 0.50 (378.8 m)** and FALLS below it: at **ρ=0.1 the missile misses by 245.9 m —
LESS than the default's 295.2**. Honest but lesson-destroying: with almost no lift authority the missile stops
*trying*, flies ~ballistically, and passes CLOSER than turning hard in the wrong direction; a user dragging
there reads **"thinner air → smaller miss"**, the exact inverse. **This is the [[ewsim-df-ellipse-sigma-monotonicity]]
pattern recurring** (slice 5: the ellipse axes are monotone in σθ only at low GDOP). **Same discipline: the knob
is bounded to the MONOTONE region — ρ ∈ [0.6, 1.3], default 1.225 (THE PICK, untouched).** Physical (0.6 ≈ 7 km
ISA; 1.3 ≈ the densest real sea-level air), `defl_sat == 0` throughout, and stable throughout (`q_flips == 2`,
`q_peak ≈ 0.72`) — NB it dips to ω_sp = 6.80 at ρ=0.6, **below gate-0's proven-stable floor of 9.7** (which is
the PICK's OWN ω_sp), so this probe **empirically extends** it; at ρ=0.1 (ω_sp 2.77) the loop DOES start to go
(`q_flips` 2→6, `defl_sat` 0→1). ρ is **never** sold as a make-it-hit lever (it never hits; gate 0 found the
same of speed).

**ρ-AS-KNOB vs FINDING 3 ("high altitude" is FALSE here):** no conflict — it makes the constant-ρ approximation
**INTERACTIVE** ("the sim won't thin the air as you climb, so thin it yourself") instead of hidden. The
exponential atmosphere ρ(z)=ρ₀·exp(−z/H) stays DEFERRED (it touches the shared drag path). **Say "low dynamic
pressure (thin air)", never unqualified "high altitude"** — the phrasing is fixed in the scenario header,
`scenario.jl:462/496`, CLAUDE.md and HANDOFF §11.

**The shipped scenario reproduces THE PICK EXACTLY through `load_scenario → tick!`** (convention 10 — pinned
against the live wire, never a hand-recompute): miss **295.167860288** (Δ=1.6e-10 = the reference's own
rounding), `aero_sat` **2444/4130 = 59.2%**, `defl_sat` **0**, `a_max_aero` **269.3900**, α_peak **0.136882**,
δ_peak **0.266653**, point_mass **0.276114603**, ratio **1069.0×**, `a_max` 3000 ≡ 1e7 **bit-for-bit**, the
`:a_ctrl` tripwire holds (a pure-coupled run never grows the key). So the scenario inherits the whole
gate-0/1/2 evidence chain with no re-derivation.

**`scenarios/slice19_alpha_limit.yaml`** (seed 19, dt 1e-3, emit 16): **PLANAR** (every y=0 — the out-of-plane
discard is a §1 named approximation that CONSTRAINS the geometry, not a preference: a pitch-plane α autopilot
cannot make y-accel, so an out-of-plane maneuver would be unflyable by construction and would read as a bug —
`test_scenario` asserts every pos/vel y is 0). Fidelity `{airframe: pitch_coupled, guidance: pn, autopilot:
alpha}` — THREE keys, **ONE toggled** (convention 9). Knobs: **rho** (DEMO), **af_alpha_max** (CAUSATION),
**af_cla** (authority + the C_Lα-through-zero crash site). `k_alpha`/`k_q` are **deliberately NOT knobs** (the
α_max clamp bounds the COMMAND while lift uses the ACHIEVED α ⇒ a hot loop overshoots and **the ceiling LEAKS**:
gate 0 measured the miss collapsing 295 → 63 m at k_α=100).

**THE ISOLATION IS STRUCTURAL — `saturated == 0` FAILS and must NOT be copied from slice 15.** `a_max`=3000
clamps **560×** in the guided window and is **INERT** (proven bit-for-bit vs 1e7): it clamps `a_cmd` UPSTREAM of
the α inversion, and since `a_max_aero < a_max` the clamped demand STILL pegs `α_cmd` at ±α_max — **the tighter
clamp wins downstream**. Asserted instead: **max(`a_max_aero`) < `a_max`** (269 < 3000, an 11× margin) and
**`defl_sat == 0`** (δ_peak 0.2667 < δ_max 0.4, 33% margin, deterministic at launch). **BINDING ≠ CAUSING:** the
counterfactual is the only thing that licenses the causal claim — relaxing **α_max ALONE** (ρ/speed/geometry
held; α_max enters ONLY the α_cmd clamp, absent from `pitch_moment`/`lift_accel`/`short_period_freq`) recovers
**282 of 295 m = 95.4%**. Stated as a COUNTERFACTUAL, never a decomposition (gate 0 proved ceiling and dynamics
are NOT additive). The residual **~13 m** is **"the airframe + autopilot dynamic tracking cost"** — a §1 named
approximation of the `:pitch_coupled` plant, NOT "short-period lag" (unearned) and NOT a projection effect
(refuted at −0.081 m).

**THE PLOT/FLAG DECISION (the gate-2 finding, settled CONSCIOUSLY at gate 3):** `aero_sat` fires on `|a_perp|`
(the ⟂-v PROJECTION — the only component an airframe can make) while `a_demand` is the FULL-magnitude pre-clamp
demand, and `|a_perp| ≤ |a_cmd| ≤ |a_dem|` ⇒ the sets NEST, so a HUD plotting demand-vs-ceiling reads "breached"
EARLIER and MORE OFTEN than the flag lights (the along-v̂ component reaches 0.55·|a_cmd| — which is exactly why
the flag reads 59%, not more). **The call: keep the wire at 6 keys, accept the plot as ILLUSTRATIVE, and LABEL
it in the HUD** ("illustrative: flag keys off ⟂v projection") rather than ship `a_perp` as a 7th key. **The FLAG
is ground truth** — the verifier asserts `aero_sat`, NEVER a hand-rolled `a_demand > a_max_aero`.

**CLIENT** (`Sandbox.gd`, +1 draw fn / +3 vars — zero physics, convention 13): the airframe view carries over
from slice 17 **wholesale** — `_fid_kind = "airframe"` is REUSED (the curved trail, the nose/velocity/α overlay,
the cycler all unchanged), since the value-guard already keys on `_fidelity.has("airframe")`. NEW: the headline
**`_draw_aero_strip()`** — the cyan ceiling vs the orange demand on one axis with the breach band shaded RED and
the panel border LIGHTING on `aero_sat`. Autoscaled on the CEILING (×2.6), not the demand (the pre-clamp demand
spikes to ~1e4 in the endgame and would squash the ceiling to a flat line); the demand trace clamps to the panel
top. Gated on the `a_max_aero` key ⇒ slices 16/17 draw nothing new. Histories clear on reset.

**Four proofs green.** `slice19_verify.gd` (S19V OK, exit 0 — SIX phases): COUPLED miss(frame) **295.186**,
ceiling [261.94, 269.37], aero_sat **58.8%**, defl_sat 0; COUPLED_REPLAY **posdiff 0.0** + CPA bit-identical
(class-4c RNG-free); POINT_MASS **3.844** ⇒ ratio **76.8×**; RHO_LEVER ceiling 269.37 → **131.93 = 0.49×** with
aero_sat 58.8% → **82.4%** (the demo lever MOVES the physics — the dead-knob tripwire); ALPHA_CAUSE miss
**13.579** = **0.046×** the coupled default, **95.4% recovered**, defl_sat 0 throughout. `slice19_ui_test.gd`
(S19UI OK — the value-guard **THREE WAYS**: 16 drops the button / 19 shows the cycler / 18 stays 3-D; the
badge names `autopilot: alpha`; rho/af_alpha_max/af_cla → set_param; the headline samples core telemetry, is
empty on a slice-17 frame, and clears on reset). Smoke-load DONE (+ 16/17/18 re-smoke-loaded, and all NINE
prior UI tests re-run green after the `Sandbox.gd` edit). **THREE windowed shots.** The contrast pair at the SAME
tick 4130: coupled `los_range` **295.19**, `a_cmd` 282.43 vs `a_ach` **179.55** (track_gap 247.88 — the airframe
FAILING to deliver), α **−7.8°** with the lift vector drawn, demand above the ceiling with the red band filling;
point_mass `los_range` **3.84**, `a_cmd` 299.17 **== `a_ach`** (track_gap **0** — the plant delivers by fiat),
α ≈ 0. **A THIRD shot exists for a reason worth remembering (advisor catch):** BOTH of the pair captured
`aero_sat: 0` — the coupled one at CPA, where the ⟂-v projection dips back under the ceiling — so they both
landed on the **else-branch of the only conditional the slice added**, leaving the headline tell (the red border
+ the `AERO SAT` string) unrendered. That is precisely the branch the windowed-shot proof exists to catch, since
headless skips `_draw` entirely; the data path was already proven (S19V measured it binding 58.8%, S19UI latched
`_aero_sat_now`) but the PIXELS were not. A mid-approach capture at **tick 2500** closes it: border RED, **AERO
SAT** lit, `alpha_cmd` **−0.20** pegged exactly at −α_max, `a_cmd` **441.08** vs `a_max_aero` **262.93**
(track_gap 264.97). **The general lesson: a shot that lands on a conditional's else-branch proves nothing about
the branch you shipped the slice for.** **Shot-harness note:** the client auto-starts realtime on handshake (`_set_running(true)`), so the
harness must PAUSE → reset-via-the-button-handler → step a deterministic burst (the first attempt landed ~1.5 s
PAST CPA); and it must press the fidelity BUTTON rather than send a raw `set_fidelity`, or the physics changes
while the label/badge stay stale — the first point_mass shot came out labelled "pitch_coupled" while flying the
point-mass plant, a lying picture.

**Tests: 2823 → 2864 (+41); slices 1–18 byte-identical** (`test_determinism` + the `_sample_z` absolute golden
green). `test_scenario.jl`: the real yaml parses, THE PICK's params land at the consumed keys, the engagement is
PLANAR, the structural `a_max_aero < a_max` holds, the knobs are rho/af_alpha_max/af_cla with **`speed` asserted
ABSENT** (the slice-17 precedent at its own `k.key ∉ (:speed, :elevation_deg)` assert), the ρ range is bounded to
the monotone region, and `alpha_max ≤ 0` / `k_alpha ≤ 0` / `k_q < 0` are rejected. `test_server.jl`: the fixture's
dead `speed` knob **swapped for `rho`** (advisor-flagged — a no-crash drag of a dead knob is valid but enshrines
it as "tested"), plus the NEW not-a-dead-knob tripwire (ρ moves the ceiling, exactly linear) and `speed` asserted
rejected by `set_param` (it is not a declared knob — the guard that makes the dead knob unreachable).

**Slice 19 COMPLETE — the airframe flies its own command, and the air decides whether that is enough.** The
6-DOF Tier-A arc's inner loop is CLOSED (15 = fin, 16 = rotation, 17 = the α→lift coupling, **19 = the closed
inner loop**). DEFERRED (NAMED): the **exponential atmosphere** (makes "high altitude" a REAL lever — the honest
completion of this lesson); the **rate-limited fin INSIDE the coupled loop** (a SCALAR servo, NOT the Vec3
`FinState` — where slice-15's banked δ finally pays off in the **guidance limit cycle**, a real slice-20
candidate); **induced drag** (C_Di ∝ C_L² — it composes viciously: pulling g bleeds V → lowers Q → lowers
`a_max_aero` → a genuine feedback spiral); **nonlinear C_L(α) / true stall** (α_max here is a hard clamp on the
COMMAND — a true stall would bound the ACHIEVED α and close the ceiling-leak path); **bank-to-turn / 3-D**
(quaternion+ω — only there does the out-of-plane discard disappear), then the **radome/body-rate parasitic
loop**; a **seeker in the coupled loop** (flips the class back to 4a/RNG-live — conventions 3/11 re-apply).
Run the slice-19 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice19_alpha_limit.yaml`,
then launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects the airframe view). Watch the cyan
ceiling vs the orange demand: drag **ρ DOWN** to thin the air and the ceiling falls while the demand does not
(the miss opens); drag **α_max UP** and the miss collapses (the causation proof); cycle the `airframe:` button to
point_mass and the same PN law hits. Re-run the gate-3 proof headless: start that server, then the console Godot
`--headless --path clients/godot --script res://net/slice19_verify.gd` (exit 0 = pass). The UI test needs NO
server: `… --script res://net/slice19_ui_test.gd`.

---

## Slice 20 — INDUCED DRAG — the missile lowers its own ceiling

**Slice 20 — INDUCED DRAG: the missile lowers its own ceiling by maneuvering (HANDOFF §11 Tier-A)** — the
project's FIRST DEGENERATIVE SPIRAL, and the cash-in of an approximation slices 17/19 shipped EXPLICITLY:
*"lift is drag-free / speed-preserving (⟂ v)"*. Lift ⟂ v turns the flight path; **induced drag ∥ −v̂ sends the
invoice** — and the invoice is paid in the very currency that buys the turn. Plan + all 12 gate findings:
`docs/plans/slice20_induced_drag.md`. (The slice-20 SLOT was vacated: `docs/plans/slice20.md` holds the DEAD
rate-limited-fin candidate, killed at gate 0 because `δ_max` structurally SHADOWS `δ̇_max`.)

    pull α → pay K·C_L² in drag → V falls → Q = ½ρV² falls → a_max_aero = Q·S·C_Lα·α_max/m falls
           → the ceiling CATCHES the demand → you cannot pull → you miss

**SLICE 19 vs SLICE 20, in one line.** Slice 19: the maneuver ceiling is a FLIGHT CONDITION; it binds, and you
miss. Slice 20: the ceiling is a flight condition **YOU DEGRADE BY USING IT**. Slice 19 moved this same ceiling
with the ρ knob — an ENGINEER dialling a flight condition. Here the MISSILE moves it, by turning. This slice
adds **NO new cap** — it makes slice 19's cap #4 *self-lowering*. The novelty is the FEEDBACK, not a 5th cap.

**THE HEADLINE IS THE CEILING COLLAPSE RATIO, NOT `aero_sat`** (advisor, done-pass): the ceiling's own fall
WITHIN one run — **0.92× (FLAT) → 0.12× (an 8.4× collapse)** — is PURE CEILING and monotone-safe by
construction (more bill → more bleed → lower ceiling; it cannot reverse), so it is what actually evidences
"the missile lowers its own CEILING". `aero_sat 0/366 → 55.1%` is the stated CONSEQUENCE (it moves on the
ceiling AND the demand, so it is not a second measurement of the ceiling) — though a stark one: **at K=0 the
aero ceiling NEVER BINDS ONCE**, it is not a factor in the engagement at all. The miss CORROBORATES and does
NOT lead (it is non-monotone in K in general). Nothing that SETS the ceiling moved: ρ, S, C_Lα, α_max and mass
are held across every arm; the 0.92× residual at K=0 is GRAVITY on a climbing missile, not the turn.

**⚠ "DEGENERATIVE SPIRAL", NEVER "POSITIVE-FEEDBACK LOOP" (FINDING 12 — an advisor catch with the phrase
already in 8 shipped sites and heading into 4 docs).** The SPEED bleed is **SELF-LIMITING**: the bill
∝ Q·α² ∝ **V²**·α², so as V falls the bleed RATE falls. Measured live at K=0.3: `dV/dt` **PEAKS at −88.8 m/s²
(t≈4.0) then DECAYS to −35.8**; `a_induced` peaks at 81.9 and falls to 23.5; **V ASYMPTOTES at ≈213 and the
ceiling bottoms at ≈25 — neither reaches 0.** A positive-feedback loop AMPLIFIES; this decelerates itself, and
a physics-literate reader told "positive feedback" hears a speed runaway that never happens. The positive sign
lives on the **GUIDANCE/TRACKING ERROR**, and only **CONDITIONALLY**: below the ceiling PN converges normally
(*negative* feedback — that IS why PN works); once the demand crosses the FALLING ceiling the sign FLIPS and
the maneuvering that should shrink the error instead bleeds the speed that caps the maneuvering.

**⚠ THE CLAIM IS BOUNDED — the sharpest honesty constraint in this slice (gate-0 FINDING 5).** Matched on ΔV,
a PARASITIC `cd_area` reproduces this miss AND this ceiling almost exactly (**45.02 m / 173.2 vs 44.17 m /
176.3**): **"bleed → Q → ceiling → miss" is what ANY speed loss does** and is NOT evidence of induced drag.
Only the SOURCE of the bill is distinctive — so **the discriminator SHIPS AS A TOOTH, not as prose** (advisor:
*"without the straight-flight tooth, the slice's title is unearned by its tests"*). `test_missile.jl` "THE
DISCRIMINATOR" flies a straight coast: induced bills **< 1 m/s**, parasitic bills **> 50** (probed 0.06 vs
75–136), a **> 50×** separation — while the same K asked to TURN bills ~450 m/s. induced = a CLOSED LOOP
written BY THE MANEUVER (∝ α²); parasitic = an OPEN-LOOP TOLL that arrives whatever you do.

**AND NOT THIS (FINDING 7 — a prediction REFUTED by its own probe):** "a harder engagement costs more" is
**FALSE**. Holding K and hardening the target's maneuver, the *attributable* bill **FALLS** (194 → 117 m/s):
a jinking target SHORTENS time-of-flight and the α_max clamp caps α anyway. **The showcase target does not
maneuver at all**, deliberately — the missile pays for **its own turn onto the collision course**. Say "the
turn you must make to intercept bills you"; NEVER "dogfighting costs speed".

**Gate 1** — `airframe.jl` `induced_drag_accel(vel, θ, mass, p)`: `C_L = C_Lα·α`, `C_Di = K·C_L²`,
`a_ind = −(Q·S·C_Di/m)·v̂`. `lift_accel`'s **COMPANION AND ORTHOGONAL COMPLEMENT** — the same α and the same
`Q·S` build both, but lift acts on `n̂` and turns at constant speed while this acts on `−v̂` and slows without
turning. `AirframeParams` gains **`K` as the LAST field** (the slice-17 `Cla` precedent) + an 8-arg outer
constructor so slices 16–19's nine construction sites compile unchanged at K=0 — a CONVENIENCE, **not** the
byte-identity guard. Teeth (+40): K=0 ⇒ EXACTLY zero (`==`) and α=0 costs exactly zero even with K on (the
α²-SOURCE); DIRECTION ∥ −v̂ AND ⟂ n̂ on a CLIMBING missile (a leaked ⟂ component would be a second unnamed
lift; a sign flip a drag that ACCELERATES — neither survives a magnitude-only test); EVEN in α (`up == down`
bit-for-bit) contrasted against lift being ODD (the pair proves the square is really there); doubling α
QUADRUPLES the bill; the closed form by hand; ∝K linear and ∝Q ∝V² (the coupling that closes the loop);
C_Lα<0 flips the lift but NOT the bill (C_L² is even in C_Lα too). **⭐ THE SPIRAL in the primitives:** the
same 3 s constant-α turn is SPEED-FREE at K=0 (700.000 — the approximation, cashed) and costs 232.7 m/s at
K=0.3, the ceiling HALVES (0.4456×) with ρ/S/C_Lα/α_max/mass IDENTICAL, and `ceiling/ceiling ≡ (V/V)²` to
**~1e-16** — the tightest tooth here, and what makes the loop a LOOP. *Thresholds are MEASURED then loosened:
a first draft guessed them from the ENGAGEMENT's numbers and failed 3/6 — the physics was right, the guesses
were wrong (convention 11, live).*

**Gate 2** — `_integrate_coupled!` grows a **SECOND CLOSURE**, reachable only via `haskey(c, :af_k_induced)`;
the else-arm is slice 17/19 TEXTUALLY VERBATIM. **NOT** `+ induced_drag_accel(...)` trusting K=0→zero
(advisor): byte-identity is STRUCTURAL — the else-arm cannot differ from slice 19 because it IS slice 19 —
rather than a property of today's formula plus IEEE zero-sign reasoning (`-0.0 + 0.0 → +0.0`, the trap the
`:a_ctrl` guard right above it documents). The drag reads the **STAGE α** (`TH − γ`), the slice-17 stage-θ
catch applied identically. Loader: `airframe.k_induced` → `comp[:af_k_induced]`, **PRESENCE-gated on the KEY**
(the slice-18 `alt_hold_m` precedent), NOT on the airframe BLOCK — slices 16/17/19 all HAVE airframe blocks,
so block-gating would grow the key on every one and hand each a drag term (convention 2 dead). Unlike
`cma`/`cla` (finite-only — a negative lift slope is merely inverted and lesson-adjacent), **K's SIGN is
validated**: a negative K is a drag that ACCELERATES. `a_induced` telemetry is KEY-gated AND RUNG-gated
(inside the `:pitch_coupled` block — the slice-17 lift-keys precedent). **`LIVE_FIDELITY_MODES` untouched.**
+26 tests: key-absent replays `===` bit-identical and ships NO `a_induced` (the existing slice-19 golden pins
only `atol=1e-6` and would SAIL THROUGH a −0.0 flip, so byte-identity got its OWN `===` tooth); the K=0 arm is
a TRUE no-op, bit-exact vs key-absent (the `==` no-op precedent — which does NOT make the guard redundant, it
shows the arithmetic agrees TODAY); **NOT-A-DEAD-KNOB asserts MOVEMENT, not absence-of-throw** (slice 19's
gate 2 PASSED a dead `speed` knob — a no-crash check cannot tell). *The loader fixture initially threw for a
MISSING TARGET, so both `@test_throws` cases were passing for the wrong reason — the "a test that malforms its
own fixture proves nothing" trap, hit live.*

**Gate 3** — `scenarios/slice20_induced_drag.yaml`: slice-19's airframe/autopilot **VERBATIM** (α_max 0.2 rad
≈ 11.5°, physical — deliberately NOT inflated: FINDING 3 rejected unpegging via α_max because 0.8 rad = 46° is
absurd and blips defl_sat), a **NON-maneuvering** target at 9 km (|v| 825 > 700 ⇒ it OUTRUNS the missile ⇒ a
clean FIRST CPA), `cd_area_m2: 0` (**the isolation** — every m/s lost is provably bought with α),
`k_induced: 0.15` opening MID-RANGE so the slider reads both ways. **THE CLIENT NEEDED ZERO EDITS** — slice
19's airframe view carries it wholesale: `:airframe` in the fidelity routes to the existing cycler branch (as
slice 19's REFERENCE ARM, since slice 20's lesson is the SLIDER), the aero strip already plotted the core's
ceiling-vs-demand so the falling ceiling DRAWS ITSELF, and `a_induced` is a scalar so `_update_readout`
renders it with no whitelist edit. **The frame-sampled wire (S20V):**

| K | miss (frame) | ceiling start→min | aero_sat | a_ind | V_end | defl_sat |
|---|---|---|---|---|---|---|
| 0.15 (ships) | 103.139 | 269.4→129.6 (0.481×) | 12.7% | 48.7 | 485.5 | 0 |
| 0.00 (free) | **8.590** | 269.4→246.8 (**0.916× FLAT**) | **0/366** | 0.0 | 670.0 | 0 |
| 0.30 (max) | **714.116** | 269.4→**32.1** (**0.119×**) | **55.1%** | 86.0 | 241.7 | 0 |

replay posdiff **0.0**; **83.1×** end to end. **ONE knob** (`af_k_induced ∈ [0, 0.3]`) — α_max and ρ are
DISQUALIFIED and their absence is ASSERTED: both are CONFOUNDED with the new drag term (α_max now feeds the
bill through the ACHIEVED α — it can never be this slice's counterfactual, unlike slice 19 where it touched
only the clamp; ρ moves ceiling AND bill). **K enters ONLY the drag term** — which is what makes it the
causation lever.

**⭐ `ENDGAME_RANGE = 1000`, NOT slice-19's 300 — load-bearing, a gate-3 finding.** Slice 19's gate excludes
ITS terminal λ̇ spike only because slice 19 misses by **295 m — i.e. its CPA falls BELOW the gate, by luck of
the geometry**. Slice 20's KMAX arm misses by **714 m**, so its CPA sits ABOVE a 300 m gate: at CPA the LOS
rotates fastest ⇒ a_cmd spikes ⇒ α_cmd pegs ⇒ δ punches δ_max, and a 300 m gate COUNTS it (measured:
`defl_sat = 1` at t=8.016, r=714.1, δ=−0.4). **Copying slice 19's constant would have shipped a FALSE
isolation.** The gate must exceed the LARGEST CPA in the sweep; 1000 clears 714 by 286 m and costs ~10% of the
window. `defl_sat == 0` in EVERY arm under it — the isolation RE-ESTABLISHED, never copied.

**The knob range [0, 0.3] is MEASURED (FINDINGS 6 + 11).** The miss is NON-MONOTONE in K in general — at 6 km
against a maneuvering target it PEAKS at K≈0.3 and COLLAPSES to 33 m by K=0.8 (a bled-out missile stops trying
and flies ~ballistically into a close pass — the exact INVERSE of the lesson; the
[[ewsim-df-ellipse-sigma-monotonicity]] pattern, **4th occurrence**). THIS config does not reverse (a bled-out
missile vs a non-maneuvering target simply falls short) but CONTAMINATES from K ≥ 0.8: `defl_sat` 0 → **1289**,
CPA never closes, α_pk **0.582 OVERSHOOTS α_max** (slice-19's ceiling LEAK). Clean and monotone to **0.6** ⇒
the max sits at 0.3, a **2× margin**.

**Four proofs green.** S20V (the five phases above). S20UI (the value-guard FOUR ways — 16 drops / 17-19-20
show / 18 stays 3-D; **EXACTLY ONE** slider; the strip shows the ceiling FALLING; reset CLEARS the histories —
*a stale falling trace would read as a spiral that never happened*). Smoke-load → `EWSIM_SERVER_DONE`. **Shot**
(windowed, tick 6000): aimed at the branch being CLAIMED, not the climax — **cyan ceiling descending 269→138,
orange demand crossing at 301, red breach band, AERO SAT lit, `defl_sat: 0` visible in the readout**. Tick
picked by measuring the lit band (5504→7296) and staying clear of the r→0 endgame where the demand hits 12288
and would flatten the strip's y-scale. *A first verifier draft called `SimClient.stop()` (no such method)
inside `_teardown`, which runs AFTER `quit(0)` — so it threw, leaked 7 ObjectDB instances, and still exited 0.
An error that lands past the exit code is exactly the kind that survives.*

**Tests: 2864 → 2935 (+71); slices 1–19 byte-identical.** Proven on the LIVE WIRE, not just in-suite: the
16/17/19 verifiers reproduce this ledger's own numbers **to the digit** — S19V 295.186 / 3.844 / 76.8× / ρ
0.49× / 95.4% recovery, S17V posdiff 876.354 / end (2187.8, 3010.2), S16V max|α| 0.15011 / ω_sp 2.4022 /
posdiff 0.0 — and all 18 UI tests pass.

**Class 4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" is VACUOUS; do NOT
copy slice-11/13 draw language), live-settable, NO `set_fidelity` guard. The **6th consecutive 4c** (14/15/16/
17/19). **NO new fidelity rung, settled at the gate-0 advisor pass**: *a rung must name physics the knob cannot
express*, and a `:free` rung IS `K = 0` — the slider's own minimum. This is the **slice-16 `af_cma` precedent**
(a live knob that changes physics without being a fidelity button). Also: the spiral is CONTINUOUS (watching
the ceiling fall IS the lesson — a discrete flip throws the animation away), and a two-state button would HIDE
the FINDING-6 non-monotonicity a bounded slider respects.

**Slice 20 COMPLETE — the missile lowers its own ceiling, and only the turn is billed for it.** DEFERRED
(NAMED): the **exponential atmosphere** ρ(z) (makes "high altitude" a REAL lever; it touches the shared drag
path); **nonlinear C_L(α) / true stall** (α_max is still a hard clamp on the COMMAND — a true stall would bound
the ACHIEVED α and close the ceiling-leak path this slice's K≥0.8 contamination re-exposed); **zero-lift-drag
`C_D0` interaction** (`cd_area` exists but is held 0 for the isolation — a scenario with BOTH is the honest
composition); **bank-to-turn / 3-D** (quaternion+ω — only there does the out-of-plane discard disappear), then
the **radome/body-rate parasitic loop**; a **seeker in the coupled loop** (flips the class back to 4a/RNG-live).
The rate-limited fin inside the coupled loop is **DEAD**, not deferred (`docs/plans/slice20.md`).
Run the slice-20 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice20_induced_drag.yaml`,
then launch Godot on `clients/godot`. Watch the **cyan ceiling FALL** as the missile turns: drag **K to 0** and
it goes flat (the missile hits, and the ceiling never binds once); drag **K to 0.3** and it collapses 8.4× onto
the demand. Re-run the gate-3 proof headless: start that server, then the console Godot `--headless --path
clients/godot --script res://net/slice20_verify.gd` (exit 0 = pass). The UI test needs NO server:
`… --script res://net/slice20_ui_test.gd`.

---

## Slice 21 — THE EXPONENTIAL ATMOSPHERE

**Slice 21 — THE EXPONENTIAL ATMOSPHERE: the ceiling you lower by CLIMBING (HANDOFF §11 Tier-A)** — the
honest completion of slices 19/20's constant-ρ, and the last named deferral of the aero arc's opening trio.
Plan + the full gate-0 findings in `docs/plans/slice21.md`. **3182 tests green** (2935 → 3093 gate 1 → 3167
gate 2 → 3182 gate 3); slices 1–20 byte-identical.

Slices 19 and 20 shipped under standing orders to say *"low dynamic pressure (thin air)"* and NEVER
unqualified *"high altitude"* — because ρ was a number an ENGINEER TYPED, not a consequence of where the
missile flew, and only V could move `Q = ½ρV²`. Slice 21 makes ρ = ρ₀·exp(−z/H) and the phrase is EARNED:
**climb → ρ(z) falls → Q falls → `a_max_aero = Q·S·C_Lα·α_max/m` falls → you cannot pull → you miss.** ⚠ THE
CAVEAT LIFTS ONLY HERE: a slice-19/20 wire carries no `af_scale_height` and runs `:atmosphere = constant`, so
the OLD language still governs there. Do NOT do a global find/replace.

**THE CAP IS THE SAME ONE (#4) ALL THREE TIMES — 21 gives it a THIRD MOVER, not a new cap:**
  slice 19: the ceiling is a FLIGHT CONDITION, and it BINDS. **The ENGINEER moves it** (the `rho` knob).
  slice 20: you DEGRADE IT BY USING IT. **The MISSILE moves it, by TURNING** (the V bleed).
  slice 21: it is a property of **WHERE YOU FLY**. The missile moves it by CLIMBING — and the climb is not
            optional: it is the only way to a 14 km target at all.

**⭐ THE HEADLINE IS THE ρ-FACTOR, AND IT FACTORIZES EXACTLY — the thing slice 20 could never do.** Because
`a_max_aero = ½·ρ(z)·V²·S·|C_Lα|·α_max/m`, the within-run ceiling ratio is IDENTICALLY
`[ρ(z)/ρ(z₀)]·[V/V₀]²` — an ALGEBRAIC IDENTITY, not an empirical fit — so ALTITUDE and SPEED **separate with
no residual**. Measured ON THE WIRE at the ceiling-minimum frame, the residual is **EXACTLY 0.0**:
`ceiling 0.130605318 == rho 0.248319848 × V² 0.525956015`. Slice 20's V-only collapse was not decomposable.

**⭐⭐ AND THE SHARPEST SINGLE FACT — the twin's ρ-factor is EXACTLY 1.0** (`==`, never `≈`). The `:constant`
arm's ceiling ALSO falls on this climb — by ≈2× (0.524×) — but that is purely the V bleed, i.e. GRAVITY, and
its model books **100% of it to speed BY DEFINITION**, because it has no z in its ρ at all. ρ(z) reveals the
4× it could not see. **That is the whole slice in one number**, and it is exactly why `rho_air` is KEY-gated
and not RUNG-gated: the twin's half of the headline has to BE on the wire.

**GATE 1 — `atmosphere.jl`, the smallest pure lib in the project** (158 tests, `test_atmosphere.jl`).
`air_density(z; rho0, H) = rho0·exp(−max(z,0)/max(H,_ATM_H_FLOOR))` + `ATMOSPHERE_MODES = (:constant,
:exponential)`. Both guard sites are REAL crash paths, not ceremony (convention 5): z floored at 0 because an
RK4 stage legitimately probes z<0 (`exp(−z/H)` at a wild negative z mints Inf → NaN pos → an invalid frame),
and H floored at 1.0 because **H=0 with z=0 is `0/0` = NaN**. Teeth: the z=0 identity is BIT-EXACT (`==`) —
which is what lets ONE authored `rho` serve both rungs honestly; the e-folding `ρ(H)/ρ₀ ≡ e⁻¹` at four H (the
EXTERNAL anchor); strict monotonicity; and **the H→∞ limit APPROACHED-BUT-NEVER-REACHED** (`≈ 1.225 atol=1e-6`
AND `!= 1.225`) — that tooth was born from a FAILURE (a first draft asserted atol=1e-9 and failed on a
1.7e-8 residual; real physics, not a bug — the limit is never reached, and **that IS the slice's rung
argument**, so it now ships as the `!=`).

**★ WHY A RUNG AND NOT A KNOB — the general result, recorded in `atmosphere.jl`'s header because it outlives
the slice.** The plan originally said no-rung and gate 0 REVERSED it. The suite's real discriminator is **is
the off-state (a) a distinct code path and (b) NOT knob-reachable?**
  • KNOB (`af_cma` s16, `af_k_induced` s20): the off-state is an IN-DOMAIN SLIDER VALUE (`K=0` is the
    slider's own minimum, exact) — continuous, no separate path.
  • RUNG (`:airframe`, `:propagation`, `:atmosphere`): the off-state is a DISTINCT CODE PATH that NO knob
    value reaches. Constant ρ is `H = ∞` — a LIMIT POINT (within 1% at 13.6 km needs H ≈ 1.4e6).
So slice 20's "a `:free` rung IS K=0" reasoning DOES NOT TRANSFER. The tempting refusal — ":constant names no
physics ρ(z) lacks, only the ABSENCE of a gradient" — was **killed by the advisor**: it is word-for-word what
`:airframe = point_mass` and `:propagation = free_space` already are, so applied consistently it deletes two
shipped rungs and cannot be the test. The rung also IS the lesson: the punchline is the live side-by-side.

**GATE 2 — the rung wired, and THE STAGE-z FIX.** The whole slice hinges on an argument that was ALREADY
THERE: `_integrate_coupled!`'s joint closure has been `f(P, Vv, TH, Q)` since slice 17, and `P` — the RK4
STAGE POSITION — **was read by nothing**. The atmosphere is what finally reads it, at ZERO contract change.
Slice 17's stage-θ fix, exactly. Params are REBUILT PER STAGE with the stage ρ, which keeps
lift/induced/moment MEASUREMENT-AGNOSTIC and z-FREE (§12): the aero lib never learns about altitude, it just
gets a `p` whose rho is the stage value. The stage ρ also goes to `total_accel`, so the arm is
self-consistent — one air for all four terms. STRUCTURE (advisor): the else-arm is slices 17/19/20 TEXTUALLY
VERBATIM and now serves BOTH key-absent AND `:atmosphere === :constant`, so byte-identity is automatic and
the three-state wrinkle dissolves (never `exp(0)==1` — the `-0.0` trap). Loader: `scale_height_m`
PRESENCE-gated on the KEY (slices 16/17/19/20 ALL carry airframe blocks, so gating on the BLOCK would grow
the key on every one), H>0 validated at LOAD and floored at the CONSUMER (both sites required).
**THE STAGE-z GOLDEN is a HUNT with a MEASURED quarry, not insurance**: the entry-z variant sits
Δpos_z = 3.039e-3 m away at the pinned tick (atol 1e-6 ⇒ a ~3000× margin), and NOTHING else in the file can
see it (F9: it moves the miss 0.136 m on a 360 m lesson; ρ-factor/ceiling/twin/leak all survive it).

**GATE 3 — two core changes the verifier's design forced out, both found late and both real:**
• **`_atm_on` GAINED A THIRD CONJUNCT `:airframe === :pitch_coupled` — a LATENT BUG FIX, not plumbing.**
  ρ(z) reaches ONLY the coupled path (`_integrate_coupled!` is itself gated on `:pitch_coupled`), so under
  `:point_mass` the translation flies `total_accel`'s AUTHORED constant ρ whatever the rung says — but the
  readout sites called `_airframe_rho` unconditionally. The **decisive** case (advisor) is not the readouts:
  it is **slice-16's `_integrate_airframe!`, which actually INTEGRATES θ/q under `:point_mass`** — it would
  have advanced rotational state in ρ(z) while pos/vel flew ρ₀. **Half the missile in one atmosphere and half
  in another.** `atmosphere.jl`'s header already CLAIMED "ρ(z) reaches the COUPLED path only" — true of the
  integrator, false of the readout; now true of the GATE, the only place it can be true. `:atmosphere` is
  **INERT without `:pitch_coupled`** — the slice-14 (`:salvo` needs a `:datalink`) / slice-13
  (`discrimination` needs `:scan`) shape. Pinned `===` on the TRAJECTORY, and no tautology: the missile
  climbs to ~12.8 km where ρ(z)/ρ₀ ≈ 0.2, so a leak at ANY of the five sites moves θ/q far outside `===`.
  `atm_world`'s `airframe` kwarg was DEAD until this; it now has a purpose. ⚠ SIDE-EFFECT, DOCUMENTED IN
  PLACE (advisor — "future-you will wonder"): slice-19's `:point_mass` REFERENCE CEILING now reports the **ρ₀**
  ceiling under `:exponential`. Coherent (that plant flies constant-ρ `total_accel`, so ρ₀ IS its flight
  condition) and unreachable from this showcase; slices 16–20 carry no scale height and are unaffected.
• **NEW WIRE KEY `rho_air`** — the air the missile is actually flying in (kg/m³). KEY-gated on an authored
  `:af_scale_height` (the slice-20 `a_induced` / slice-15 fin-key precedent) ⇒ slices 16–20 byte-identical.
  **IT SHIPS UNDER BOTH RUNGS, AND THAT IS LOAD-BEARING** — the KEY is the gate, never the rung (the
  deliberate contrast with `a_lift`, a produced force that only exists when coupled). Under `:constant` it
  ships the flat ρ₀ **and that is precisely the lie the slice exposes**. Rung-gating would take the twin's
  ρ-factor==1.0 off the wire and leave the client to divide `2·q_dyn/V²` — physics in GDScript, which
  convention 13 forbids. The CORE computes; the client displays. (Also fixed in passing: `q_dyn`'s comment
  said "½ρV² — the flight condition (only V moves it)". Slice 21 makes that FALSE.)

**⚠ NOT ZERO CLIENT CODE — and the reason is the interesting part.** Slice 20 shipped none because its lesson
was a SLIDER and it let `:airframe` keep the button. Slice 21's lesson IS a button, and its scenario ALSO
ships `:airframe: pitch_coupled` (AUTHORED FIXED — the missile must stay coupled for a lift ceiling to EXIST).
**Two view-claiming fidelity keys in one handshake, a first for this arc.** `_setup_spatial_fid_btn` checks
`:atmosphere` **FIRST** so the ONE button toggles the LESSON's key and not the HELD one — the slice-13/14
rule, THIRD occurrence. Checking first (vs slotting between the two airframe branches) is also strictly safer:
an atmosphere scenario with no `:airframe` key would otherwise fall into the slice-16 DROP branch and lose its
button entirely. Everything else is REUSE, **proven not asserted**: the aero strip (s19), the α strip (s16/17)
and the nose-vs-velocity vectors are gated on `_airframe_view` and carry over untouched — only
`_draw_missile`'s `_fid_kind` gate needed the new kind, and `rho_air` renders through the no-whitelist scalar
path. New: `ATMOSPHERE_RUNGS`, `_on_atmosphere_pressed`, the `"atmosphere"` label arm, extents seeded 20×15 km.

**THE SHOWCASE — every part LOAD-BEARING, and it is NOT a slice-20 reskin (gate-0 F1–F3):**
• **A SLOW, DISTANT, HIGH TARGET (22 km / 14 km, −250 m/s).** "Just make it climb" is UNFLYABLE (F1): a
  700 m/s missile needs ~15 s to climb 6 km, in which a head-on 800 m/s target covers 12 km — "climbs a lot"
  and "closes fast" are MUTUALLY EXCLUSIVE, and every steep-climb geometry missed by KILOMETRES under BOTH
  arms (the REACH wall, not the ceiling). Launching high enough to shorten the climb made the TWIN saturate
  46.6% — that is SLICE 19's lesson, not this one.
• **THE TARGET JINKS, AND IT MUST (F2 — the finding that killed the first design).** Without a late demand the
  ρ(z) missile turns EARLY, LOW, in THICK air, arrives on a good collision course, and **by the time it is
  high and cannot maneuver it NO LONGER NEEDS TO** — measured: a ceiling of 16.5 m/s² (1.7 g) at 16 km and it
  still only missed by 29 m. PN NULLS LOS RATE, so terminal demand against a straight-flier → 0 BY
  CONSTRUCTION. **Late demand is STRUCTURAL.**
• **⚠ SLICE 20 FORBADE A MANEUVERING TARGET — DO NOT COPY THAT RULE (F3).** It existed to attribute the
  induced-drag BILL. **HERE K = 0: THERE IS NO BILL.** The jink is a DEMAND SOURCE, not the lesson — and the
  `:constant` twin flies the IDENTICAL geometry against the IDENTICAL jink and HITS, which controls for the
  target completely. Nor is this slice 12: the twin proves plain PN handles this jink comfortably at sea-level
  density — its ceiling never binds ONCE.
• **K = 0 AND cd_area = 0 — THE ISOLATION, and it is total.** Nothing bleeds speed but GRAVITY, and the twin
  carries the same gravity ⇒ the twin difference is PURE ALTITUDE. (Do NOT switch induced drag on to "compose
  20 and 21": gate-0 F10 measured the compose at +33% and found it CONFOUNDED — the two arms fly different
  trajectories, so a scenario number cannot isolate it. The compose ships as CLOSED FORM instead:
  **`a_ind ∝ 1/Q`** — the SAME turn bills MORE up high — vs an INDEPENDENT recompute `K·m·a_perp²/(Q·S)`, a
  tooth and a named observation, never the headline (convention 9 — slice 20 already teaches the bill).)
• **H = 8500 IS EARTH'S ACTUAL SCALE HEIGHT**, not a tuned number: this missile misses because of the
  atmosphere we live in.

**ONE KNOB `af_scale_height ∈ [6000, 25000]`** — H is not the density (that is ρ₀) but the RATE THE AIR THINS,
the one DOF no constant ρ has. **The range is MEASURED (F8) and the FLOOR binds**: H=25000 → 6.29 m; H=8500 →
360.74 m (ships here, and the slider reads BOTH ways from it); H=6000 → 1706.49 m (α_pk 0.194, still 3.0%
under the clamp); **H ≤ 3000 → THE CEILING LEAKS** (α_pk ≥ 0.2000 BREACHES α_max — slice-19 FINDING 14: the
clamp bounds the COMMAND, lift uses the ACHIEVED α). The floor sits at 2× that boundary (the slice-20 K
discipline). NOT KNOBS, deliberately: **ρ₀** (slice 19's lever telling slice 19's story; it scales the WHOLE
profile and **cannot produce a GRADIENT** — the precise difference this slice exists to show); **α_max**
(slice 19's causation lever, and it is the very clamp whose LEAK bounds H, so moving it moves the bound);
**K** (would confound the isolation); **launch/target ALTITUDE** — the obvious knob and a DEAD one (position
is consumed ONCE at load and `reset` reloads the YAML — slice-19's `speed` finding; **H is the live face of z**).
**⚠ THE MISS DOES NOT REVERSE IN H, and that prediction was explicitly REFUTED (F7):** slice 20's K reversed
(a bled-out missile stops trying and coasts into a close pass) because its penalty was SPEED. Thin air costs
ZERO speed here — only AUTHORITY — so the missile flies fast and STRAIGHT PAST and the miss is monotone across
the sweep. `[[ewsim-df-ellipse-sigma-monotonicity]]` does NOT apply. (Headline the ρ-factor anyway: it is
monotone BY CONSTRUCTION, which the miss only happens to be.)

**Class 4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" is VACUOUS; do NOT
copy slice-11/13 draw language). **The 7th consecutive 4c** (14/15/16/17/19/20). Live-settable, NO
`set_fidelity` guard (the `:integrator`/`:autopilot`/`:apn`/`:cooperation`/`:airframe` precedent; the CONTRAST
is slice-13's `:scan`, which flips draw topology and rejects introduction).

**FOUR PROOFS GREEN.** `net/slice21_verify.gd` (S21V OK — four phases: EXP / EXP_REPLAY / CONST / HMAX):
`:exponential` miss **360.768** frame-sampled, ceiling **239.3→31.3**, ρ **1.0884→0.2703** (ρ-factor **0.248**),
z_max **12846 m**, aero_sat **673/2626 (25.6%)**; the FACTORIZATION residual **EXACTLY 0.0**; replay posdiff
**0.0**; `:constant` miss **3.075** (**117×**), ceiling 269.3→141.2 (0.524×), ρ FLAT, **aero_sat 0/2628 — the
ceiling NEVER BINDS ONCE**, ρ-factor `== 1.0`; H=25000 miss **7.131**, ρ-factor **0.621**; `defl_sat == 0` in
EVERY arm and `a_max` INERT (3000 ≫ 269). `net/slice21_ui_test.gd` (S21UI OK — the value-guard is **FIVE-WAY**:
16 drops the button / 17-19-20 keep the airframe cycler / 18 stays 3-D / **21 takes the atm cycler DESPITE
`_fidelity.has("airframe")`**). `Sandbox.tscn` smoke-loaded headless against a slice-21 server (server `DONE` ⇒
scene connected, no GDScript errors) + slices 16/17/18/19/20 **re-smoked** (the new `elif` sits ABOVE every
airframe branch — "I only added a branch above it" is false by one `elif`). Plus the windowed shot.

**⚠ THREE GATE-3 BUGS, ALL IN THE PROOF RATHER THAN THE PHYSICS — worth remembering:**
1. **`%.2e` IS NOT A GDSCRIPT FORMAT SPECIFIER.** An unknown specifier makes the WHOLE `%` fail SILENTLY and
   return the literal — so the headline's own number printed as `"%.9f"` on the first GREEN run. Exit 0,
   number absent. **A number that does not print is not a proof.** (`%g` bit slice 1; this is that class.)
2. **THE PASS TEXT QUOTED PER-TICK TRUTH (1.95 m, 185×) WHILE THE FILE MEASURES FRAMES (3.075, 117×)** — a
   false claim in the proof's own output. The header now states the ASYMMETRY: **a MISS samples faithfully**
   (at CPA the radial rate is zero ⇒ EXP's 360.739 → 360.768, Δ 0.03) while **a HIT samples COARSELY**
   (~800 m/s closing × 16 ms ⇒ ~13 m between samples, so 1.949 → 3.075). Slice 20 hit this exactly (true
   1.27 → frame 8.59). Quote FRAME numbers in the verifier; per-tick belongs to `test_missile.jl`.
3. **A MAGIC-MULTIPLE TOOTH (advisor):** H_MAX's ρ-factor was pinned at `1.5 × EXP_RHOF_MAX` = 0.525, which
   the actual 0.621 cleared by only 18%. Now pinned against the EXP arm's **MEASURED** ρ-factor (0.621 vs
   0.248 = 2.5×) — bigger margin AND the honest statement: a deeper atmosphere thins LESS over the SAME climb,
   and neither number need be known in advance to say it.

**⚠ THE LOS GATE IS 1000 AND H=25000 IS THE KNOB ARM — both MEASURED, not copied
([[ewsim-missile-verifier-sampling]], THIRD RECURRENCE).** Gate 2 FAILED first at slice-19's 300: the twin
HITS, so it flies the r→0 endgame where PN's ω→∞ spikes a_cmd and the ceiling blipped 94 ticks; measured,
those blips lie ENTIRELY within r ∈ [1.9, 362.9] and at r>1000 the count is EXACTLY 0 — which matters because
`aero_sat == 0` is an ASSERTION, not a hope. And the gate must sit **ABOVE THE LARGEST CPA IN THE SWEEP**:
H=6000 misses by **1706 m** — a missile that never comes within 1000 m — so a 1000 m gate would exclude
NOTHING from it while excluding the endgame from every other arm. **H=25000 was chosen for that reason**
(largest CPA stays 360.8), and the severity direction is not lost: the CORE suite flies H=6000, where every
tick is available and no gate is needed.

**Convention 10 the hard way, twice.** The gate-2 inert-host tooth first GUESSED `rho_air < 0.6·ρ₀` and failed
at 0.878 — at 6 s this missile is only ~2.8 km up, where the air is still ~72% of sea level (the 4× collapse
is a **60-second** story, not a 6-second one). Re-pinned as `rho_air == air_density(z)` — the non-arbitrary
form, `==` with no tolerance to hide behind. And the probe was proven **BIT-FOR-BIT faithful** to the live path
(Δ = 0.000e+00 at 2k/10k/20k/30k ticks), which retroactively validates every gate-0 number.

**Slice 21 COMPLETE — constant ρ was lying to you at altitude, and the old model's own ceiling never told it.**
DEFERRED (NAMED): **ρ(z) on the point-mass/ballistic drag path** (`dynamics.jl`'s steppers take a `v -> a(v)`
closure with NO position in it; changing that to `(p,v) -> a` touches slice 8's `rk4_step`/`euler_step` — the
byte-identity surface of EVERY ballistic slice — for a path carrying no altitude lesson: it deserves its own
slice); a **LAYERED standard atmosphere** (troposphere lapse + stratosphere break — the lumped isothermal `H`
is to a real ρ(z) profile what `cd_area`'s lumped `Cd·A` is to a real drag polar); **Mach / temperature
effects** (the aero lib is deliberately Mach-free, so `C_Lα` does NOT vary with altitude here — a real
interceptor's does); **round-earth / geodetic z**; **nonlinear C_L(α) / true stall** (would bound the ACHIEVED
α and close the ceiling-leak path that BOUNDS this slice's H floor — now the single most-wanted neighbour);
**bank-to-turn / 3-D** (quaternion+ω — only there does the out-of-plane discard die), then the **radome/
body-rate parasitic loop**; a **seeker in the coupled loop** (flips the class back to 4a/RNG-live).
⚠ NOT this slice: §11's RF **"layered atmosphere / ducting / tropospheric scatter"** lives behind the
`propagation` knob and is a SEPARATE slice — nothing here touches the radar path.
Run the slice-21 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice21_atmosphere.yaml`,
then launch Godot on `clients/godot`. **Press the button**: `:constant` and the missile HITS (its cyan ceiling
never binds); `:exponential` and watch the ceiling FALL as it climbs until the orange demand crosses it — same
missile, same jink, 360 m miss. Drag **H to 25000** and a deep atmosphere forgives; drag it to **6000** and the
miss opens to 1.7 km. Re-run the gate-3 proof headless: start that server, then the console Godot `--headless
--path clients/godot --script res://net/slice21_verify.gd` (exit 0 = pass). The UI test needs NO server:
`… --script res://net/slice21_ui_test.gd`.

---

## Slice 22 — NONLINEAR C_L(alpha) / TRUE STALL

**Slice 22 — NONLINEAR `C_L(α)` / TRUE STALL: the ceiling the AIRFRAME sets (HANDOFF §11 Tier-A)** — the aero
arc's nearest and most load-bearing named deferral, carried explicitly by slices 19, 20 and 21, and the one
that closes the LEAK bounding two shipped knobs. Slices 19–21 gave cap #4 (`a_max_aero`) three movers and
**ALL THREE MOVED Q** — the ENGINEER (slice 19's `rho` knob), the MISSILE BY TURNING (slice 20's induced-drag
V bleed), the MISSILE BY WHERE IT FLIES (slice 21's ρ(z)). **Slice 22 moves the OTHER FACTOR.** Every one of
those slices assumed the lift curve is a STRAIGHT LINE out to `α_max` — that the airframe will keep trading α
for lift forever. It will not. Past `α_stall` the flow SEPARATES: **`C_L` PEAKS and then FALLS**, and the drag
that was negligible in attached flow RISES steeply. The ceiling is not `C_Lα·α_max`; it is the curve's own
INTERIOR PEAK, and **no amount of Q buys past it.**

> **THE LESSON, IN ONE SENTENCE.** Every prior cap in this project is a MAGNITUDE that SATURATES — pull
> harder, get no more. This one is a **DERIVATIVE THAT CHANGES SIGN**: past the peak, pulling HARDER turns
> you LESS *and* costs you MORE. That reversal is new in the suite, and it is why the user chose the
> true-drop curve over a saturating one (a saturating curve cannot produce the control-loop reversal at all).

⭐ **THE HEADLINE IS AN EXACT IDENTITY.** At fixed Q the linear→stall ceiling ratio is IDENTICALLY
`α_stall/α_max`, because Q, S, C_Lα and m ALL CANCEL: linear `a_max_aero = Q·S·C_Lα·α_max/m`, stall
`= Q·S·C_L_peak/m` with `C_L_peak = C_Lα·α_stall`. Measured 471.4352475793185 → 269.3915700453249, ratio
0.5714285714285715 vs 4/7 = 0.5714285714285715 — **|Δ| = 0.0, bit-for-bit.** Slice 21's ρ-factor identity in
a NEW LETTER (that one also landed at exactly 0.0; both are algebraic, not fitted). ⚠ **IT IS A SAME-INPUTS
FORMULA TOOTH, NOT A RUN-VS-RUN** — pinned in `test_aero_curve.jl` (coefficient ratio, atol 1e-15) and
`test_missile.jl` (`aero_accel_limit` linear-vs-stall on IDENTICAL inputs, atol 1e-12). As a two-run
comparison it would CONFOUND ITSELF: separation drag makes V (hence Q) diverge between the arms.

**KNOB, NOT RUNG — AND THE PLAN PREDICTED THE OPPOSITE (gate-0 F7, USER DECISION 1).** The plan asserted
*"linear is `α_stall → ∞`, a LIMIT POINT ⇒ RUNG"* and told gate 0 to VERIFY it. **The verification FAILED,
and that is the finding.** The achieved α SELF-LIMITS to ~0.24 across the whole viable geometry family (α_pk
capped at 0.2408 even at `a_lat = 400`; past that is the REACH WALL, not higher α), so α_stall parked at
≥ 0.25 is linear-in-effect **over every REACHABLE state** — at 0.25 the miss is the linear miss TO THE
PRINTED DIGIT. Slice 21's own discriminator (*is the off-state (a) a distinct code path and (b) NOT
knob-reachable?*) therefore returns **KNOB**: α_stall MOVES A CORNER, and a corner can be PARKED OUT OF REACH
— exactly slice 16's `af_cma`, and the OPPOSITE of slice 21's H, which cannot be parked because altitude is
the SWEPT variable. ⇒ NO `:aero_curve` fidelity, NO button, and the one-button rule's "4th occurrence" DOES
NOT ARISE. `test_aero_curve.jl` ASSERTS the absence, so adding one later breaks a test on purpose. ⚠ Record
the meta-point: **the discriminator is a CONVENTION, not a law** — a rung could be shipped anyway for the
crisp A/B, but it would be a DELIBERATE DEVIATION, and the discriminator could NOT be cited in support.

**Gate 1** — new pure lib `aero_curve.jl`: `lift_coefficient` (ODD, slope `Cla` below α_stall and
`−k_drop·Cla` above), `separation_drag_coefficient` (EVEN, `K_sep·max(0,|α|−α_stall)²`, EXACTLY 0 below),
`moment_coefficient` (ODD, THREE slopes `Cma`/`Cma_post`/`Cma` — the F9 deep-stall bound), the closed-form
`cl_peak`, `moment_slope`. Teeth: the parity table (**C_L ODD, both drags EVEN**), the closed-form peak, the
linear-limit agreement, the shared-`C_L` consistency tooth (lift and its induced bill use the SAME `C_L` —
else the turn and the invoice disagree), the break tooth pinned by SIGN not magnitude, and the sign chain
(this arc's #1 trap on its FOURTH occurrence). Suite 3182 → 4015.

**Gate 2** — the wiring. `lift_accel_nl`/`induced_drag_accel_nl`/`separation_drag_accel` siblings;
`_stall_on`/`_stall_params` + the leading stall closure in `_integrate_coupled!`; `aero_accel_limit` gains a
`curve` arm returning the INTERIOR PEAK; loader validation. Suite 4015 → 4180. **TEN findings**, five of
which changed what gate 3 could ship — the load-bearing ones: **G2** `k_drop` is NOT a free shape parameter
(a 1.0 default silently moved the miss 240.37 → 278.11, a 16% shift, with every structural test still
passing) and **at 0.7 the authority cliff is INVISIBLE**; **G5** separation drag is NEARLY INERT on this
engagement (0.9% over the whole `K_sep` range) so it is a PHYSICALITY term and **NOT a slider**; **G9** the
cliff needs `δ_max = 1.0` and relieving the cap DROPS α_pk at cma_post 8 from 2.93 to 1.22 — **part of gate
0's dramatic 2.7779 was slice-19 FINDING 2's contamination, so that number is NEVER quoted**; **G10** slice
19's `aero_sat ⟺ demand > a_max_aero` equivalence is BROKEN under stall BY DESIGN. **G7/G8 — two bugs, both
caught by the slice's own `===` teeth, both in code written to avoid exactly them**: a 1-ULP multiply-grouping
slip INSIDE the function that generalizes the formula (the project's THIRD catch of that class), and
`separation_drag_accel` returning `Vec3(-0.0,-0.0,-0.0)` instead of the exact zero it documented. **Neither
was reachable by an `≈` test.**

**Gate 3 — TWO SCENARIOS, AND THE SPLIT IS A MEASURED CONFIG CONFLICT, NOT A CONVENTION-9 PREFERENCE.** The
two halves need INCOMPATIBLE WIRES: the lift half needs `k_drop 0.7` / `δ_max 0.4`, the departure half needs
`k_drop 1.0` / `δ_max 1.0`, and at `k_drop 0.7` the cliff is invisible (G2). **Do not merge them.** ONE
verifier (`slice22_verify.gd`) detects which half from the declared knob and runs the matching phase set.

**HALF A — `slice22_stall.yaml`, knob `af_alpha_stall ∈ [0.15, 0.35]`.** α_max RAISED 0.2 → **0.35 > α_stall
0.20** — the plan-§3 inversion, and **it INVERTS SLICE 19**: to reach post-stall the ACHIEVED α must exceed
α_stall, and the route via the LEAK (slice-19 FINDING 14's overshoot) was REJECTED as gain-dependent,
fragile, and CIRCULAR (closing that leak is a stated payoff of this very slice). Via the COMMAND is the
design: **the autopilot COMMANDS INTO STALL, α_max becomes a soft high limit, and THE PHYSICS SETS THE
WALL.** The inner loop keeps inverting on the LINEAR `C_Lα` and that is deliberate on three counts — it is
REALISTIC (an autopilot carries an internal linear model of its airframe, so a linear inversion that
OVER-commands α as the real curve goes concave is **slice-19's command-vs-achieved gap MADE PHYSICAL**), it
SIDESTEPS the MULTIVALUED past-peak inverse (never constructed here; inherited by whoever wants a
stall-aware autopilot — a NAMED deferral), and it shrinks the blast radius. Wire (frame-sampled, seed 22,
LOS-gated r > 1000): stall **241.06** vs parked-linear **125.33** (**1.92×**), ceiling **269.37 vs 471.39**,
the identity residual **0.0 on the wire**, post_stall **56/215 = 26.0%**, `defl_sat` 0 in every arm, replay
posdiff **0.0**. Floor arm (0.15): miss 437.39, ceiling 202.02.

⭐⭐ **THE SHARPEST GATE-3 FINDING — `aero_sat` DOES NOT DISCRIMINATE AT ALL, AND THE PLAN'S "26.3%" IS NOT A
STALL CONSEQUENCE.** It fires **53/215 frames on the PARKED, LINEAR arm and 53/215 on the STALL arm — the
SAME COUNT** — because (G10) it keys off the **α_max CLAMP that BOTH arms share**, while the ceiling that
actually moved is the interior peak. So there is a real regime, **past the physics ceiling but with the
command not yet pegged**, where the demand exceeds `a_max_aero` and `aero_sat` stays 0. **`post_stall` is the
discriminator: EXACTLY 0 vs 56 frames.** That is why it is a SEPARATELY-NAMED flag rather than folded into
`aero_sat` (which would make the slice-19 flag lie about which cap is doing the work), and it is the entire
justification for the slice's ONE client edit.

**HALF B — `slice22_departure.yaml`, knob `af_cma_post ∈ [0, 10]` — RELAXED STATIC STABILITY.**

    ★ A STATICALLY UNSTABLE AIRFRAME IS PERFECTLY FLYABLE — UNTIL THE AUTOPILOT RUNS OUT
      OF AUTHORITY. **THE THRESHOLD IS THE LESSON, NOT THE TUMBLE.**

⚠ A REFRAME (gate-0 DECISION 2). The slice was GROWN for "the airframe DEPARTS" after an advisor pass caught
that a LINEAR `pitch_moment` structurally CANNOT depart (`Cmα < 0` held through stall ⇒ always a restoring
moment; as V bleeds ω_sp goes sluggish but stays REAL, and `q̄ = q·d/(2V)` RISES ⇒ MORE damping) — the
slice-20 "positive feedback" / slice-21 "high altitude" overclaim class, THIRD occurrence. The user chose to
GROW THE SLICE rather than soften the language; then gate 0 measured what the break actually does, and
**what it found is a better lesson than the tumble.**

⭐⭐ **AND IT IS A THREE-POINT CLAIM WHOSE LESSON IS THE MIDDLE — a gate-3 finding.** A two-point 0-vs-8 check
demonstrates "NEUTRAL vs LOST", a **WEAKER and DIFFERENT** claim than the ratified one, because at
`cma_post 0` the airframe is **NEUTRALLY stable past the break (slope 0), not unstable at all** — the ω_sp
sentinel never fires. It is the CONTROL. Measured on the wire (α at a FIXED RANGE of 500 m):

| cma_post | α@500m | ω_sp ceiled | miss | defl_sat | verdict |
|---|---|---|---|---|---|
| 0.0 | 0.3092 (17.7°) | **0 — SILENT** | 280.58 | 0 | NEUTRAL past the break — the CONTROL |
| 4.0 | 0.4340 (24.9°) | **60 frames** | 302.36 (**1.078×**) | 0 | ⭐ **UNSTABLE AND STILL FLYABLE** |
| 8.0 | 1.0081 (57.8°) | 33 frames | 371.93 | 0 | autopilot **LOSES** ← SHIPS |

**The lesson is `cma_post 4`: the sentinel FIRES (60 frames / 947 ticks — nearly a second with NO REAL
SHORT-PERIOD MODE, so the airframe is genuinely statically unstable) and THE AUTOPILOT HOLDS IT ANYWAY** (α
only 0.43, miss within 8% of baseline). **That is "statically unstable yet perfectly flyable"** — real
fly-by-wire physics; every modern fighter is statically unstable and flies fine, right up until the control
authority runs out. The verifier asserts **SILENT → FIRING-BUT-HELD → LOST** precisely so the middle cannot
be dropped.

⭐ **SLICE 16'S ω_sp SENTINEL FIRES IN FLIGHT — FIRST TIME IN PROJECT HISTORY**, and it is visible on the
shot as `omega_sp: 1000000000`. Slice 16 built the `ω² < 0 ⇒ NaN` guard (`_finite`-clamped to `FINITE_CEIL`)
for an AUTHORED `Cmα ≥ 0`; past the break the LOCAL slope is `cma_post > 0`, so it fires DYNAMICALLY at the
moment of departure. The whole `_finite`/wire path was walked with a departure in progress (convention 6,
gate-0 P3c): it reaches the wire as FINITE_CEIL, **never a NaN.** ⭐ **AND IT IS SLICE 16'S TUMBLE, NOW
SELF-INFLICTED**: slice 16 taught static stability with `af_cma` as an AUTHORED value — an engineer typed
the unstable case. Here the airframe **DRIVES ITSELF INTO THAT REGIME BY FLYING THERE.**

⚠ **THE MISS IS NOT THE METRIC FOR HALF B, AND THAT IS FINAL** (gate-0 F4/F10): even at full tumble the LIFT
file's miss moves **+1.4%** — a missile that departs 0.7 s before CPA keeps its momentum and lands in much
the same place. Any lesson line built on it would be measuring the LIFT collapse and mis-attributing it; it
corroborates the direction and nothing more. ⚠ **AND "TIME WITH ω_sp CEILED" IS NOT A SEVERITY MEASURE — IT
RUNS BACKWARDS** (G6, re-measured here): 60 frames at cma_post 4 vs 33 at 8 (per-tick 947 → 526 → 442),
because α blows straight PAST α_sat into the deep-stall RESTORING region where ω_sp is REAL again. Asserted
as a BOOLEAN only.

**TWO MORE GATE-3 FINDINGS, both about the measurement window:**
- ⚠ **`cma_post 12` BREAKS THE ISOLATION** (`defl_sat` 289). The edge is between **10.0 (exactly 0)** and
  **10.5 (65)**, and `defl_sat` is MONOTONE in cma_post, so the knob ships **[0, 10]** and the WHOLE declared
  domain is provably clean. ⚠ The margin is **~1.03×, NOT slice-20's 2×** — stated rather than hidden, and it
  cannot be widened by raising δ_max, which is ALREADY an unphysical 1.0 rad (57°) authored SPECIFICALLY so
  the deflection cap is provably not the story.
- ⚠ **α IS SAMPLED AT A FIXED RANGE (500 m), NOT AT CPA, AND THE LIFT FILE'S LOS GATE WOULD DELETE THIS
  LESSON.** The break is reached at **t = 3.12 s / r = 1474.7 m in EVERY arm** (identical to the metre); the
  divergence then develops between there and CPA, and α_pk lands within a few ms OF the CPA frame — exactly
  where PN's r→0 demand spike lives. At the lift file's gate of 1000 the arms have barely diverged (α@1000
  spans only 0.297 → 0.399 across the whole knob range). **The correct gate DIFFERS between the two halves**
  — measured, not assumed ([[ewsim-missile-verifier-sampling]]). A fixed-range sample at 500 m sits well past
  the break and well above the r→0 artifact, so it needs no common-mode argument at all.

**⚠ NOT ZERO CLIENT CODE (unlike slice 20), and the ONE edit is FORCED by G10**: `_draw_aero_strip`'s breach
indicator now keys on **`post_stall`, not `aero_sat`** (`_breach = _post_stall_now if _has_post_stall else
_aero_sat_now`), with a "POST-STALL" label and a stall-specific header/footer. **PRESENCE-GATED** — slices
19/20/21 ship no `post_stall` key, so `_has_post_stall` stays false and they are byte-identical. The shared
button is the AIRFRAME cycler by **slice-20's ESTABLISHED PRECEDENT** (that scenario also authors
`:airframe`), so `_setup_spatial_fid_btn` is UNCHANGED.

**Class 4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" is VACUOUS; the
**8th consecutive 4c**; live-settable, NO `set_fidelity` guard). **INERT without `:pitch_coupled`** —
`_stall_on`'s third conjunct is DELIBERATE and is this slice's answer to its own gate-2 warning that *the
moment break reaches FURTHER than ρ(z) did*: `pitch_moment` is ALSO live on the `:point_mass` rotational path
(`_integrate_airframe!`), so without the conjunct a `:point_mass` wire would integrate θ/q through a BREAKING
moment while pos/vel flew a linear-aero fiat accel — half the missile in one aerodynamic model and half in
another, slice 21's `_atm_on` latent bug exactly. **`_integrate_airframe!` is untouched by this slice.**
**STALL × THE EXPONENTIAL ATMOSPHERE IS A LOAD ERROR, NOT A BRANCH-ORDER OUTCOME** (convention 9): the stall
arm LEADS `_integrate_coupled!`'s chain so the four prior arms stay textually verbatim (4 closures, not 8) —
sound only because a missile carrying both `alpha_stall` and `scale_height_m` is REFUSED at load.

**Four proofs green.** `slice22_verify.gd` both halves (exit 0 each): Half A prints the identity residual
**0.0** on the wire and the 1.92× ratio; Half B prints the three-point progression with `defl_sat 0`
throughout and both replays bit-identical. `slice22_ui_test.gd` — FOUR teeth on the G10 edit (post_stall
lights where aero_sat is silent; the MIRROR case does NOT light, proving the indicator **SWITCHED rather
than gaining an `or`** — an `or` would light the panel for the linear twin and destroy the contrast; a wire
with no key falls back to aero_sat exactly as before, the additive claim PROVEN not asserted on SHARED draw
code) plus a **SIX-WAY** value-guard. **All seven prior `*_ui_test.gd` re-run green** (16/17/18/19/20/21) —
the shared-draw edit provably disturbed nothing. `Sandbox.tscn` headless smoke-load reaches
`EWSIM_SERVER_DONE` against BOTH servers. TWO windowed shots aimed at the CLAIMED branch: the stall wire with
**"POST-STALL"** lit (not "AERO SAT"), ceiling 262 flat under a demand of 796 through a red breach band,
`a_sep 0.84` live and `defl_sat 0`; and the departure caught mid-event — `omega_sp 1000000000` (the sentinel
ON THE WIRE), the nose cone **34.2° off** the cyan velocity vector, the trail CURLING BACK ON ITSELF, α
pinned at the −0.60 deep-stall bound, `a_sep 14.02`, and `defl_sat` STILL 0.

**Slice 22 COMPLETE — the ceiling is the airframe's own curve, and an unstable airframe flies fine until it
doesn't.** ⚠ A gate-3 note for whoever quotes these numbers: the gate-2 G1 teeth (miss 240.37 / 125.14) are
measured at **`k_sep = 0`** while the shipped file authors `k_sep 3.0`; through the loader at k_sep 0 it
reproduces **240.366 — the tooth, to the digit** — and at the shipped 3.0 it is **240.898**, so separation
drag is worth **+0.53 m (0.22%)** here. ⭐ And the PARKED arm is **125.143 at BOTH k_sep values, bit-for-bit**,
because separation drag is EXACTLY zero below the stall — gate-2 G8's `-0.0` fix corroborated on the wire.
DEFERRED (NAMED): **a STALL-AWARE AUTOPILOT** (inverting the real curve, with the multivalued past-peak
inverse that implies — this slice deliberately leaves the inversion linear); **HYSTERESIS** (real separation
re-attaches at a LOWER α than it separates at; the shipped curve is single-valued in α, with no memory);
**MACH / compressibility** (the aero lib is deliberately Mach-free, so `α_stall` and `C_Lα` do not vary with
Mach here — a real interceptor's do); **ROLL/YAW DEPARTURE** — ⚠ **the sharpest remaining approximation in
the slice**: a real departure goes OUT-OF-PLANE and this one departs strictly in-plane; it dies only with
bank-to-turn / 3-D; **DEPARTURE RECOVERY / a spin model** (this slice ships the ONSET, not the aftermath —
post-departure rotational behaviour is a separate model and is NOT smuggled in); **stall × ρ(z)** (refused at
load today); and slice 21's own **ρ(z) on the ballistic path**.
Run the slice-22 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice22_stall.yaml`
(or `scenarios/slice22_departure.yaml`), then launch Godot on `clients/godot`. **There is no button to press
— drag the slider.** On the stall file, drag **α_stall to 0.35** and the corner leaves every reachable α: the
missile flies the slice-19/20/21 lift curve and misses by 125 m; drag it down and the ceiling falls with it
EXACTLY proportionally until it misses by 437. On the departure file, drag **Cm_post to 0** and the autopilot
holds the airframe at 17.7° with the ω_sp sentinel silent; wind it to 4 and the sentinel FIRES while the
autopilot still holds; wind it to 8 and watch the nose come off the velocity vector for good. Re-run the
gate-3 proof headless: start either server, then the console Godot `--headless --path clients/godot --script
res://net/slice22_verify.gd` (exit 0 = pass; it auto-detects which half). The UI test needs NO server:
`… --script res://net/slice22_ui_test.gd`.

---

## Slice 23 — 6-DOF SUBSTRATE + SKID-TO-TURN

**Slice 23 — 6-DOF SUBSTRATE + SKID-TO-TURN: the out-of-plane engagement (HANDOFF §11 Tier-A)** — the FIRST
slice of the bank-to-turn / 3-D arc, and the slice that cashes **the sharpest approximation the whole aero arc
carried**: since slice 19, `alpha_command` PROJECTS the guidance command onto the in-plane direction
`n̂ = (−sinγ, 0, cosγ)` and **DISCARDS the out-of-plane component**, so a target off the x–z plane was
*unflyable BY CONSTRUCTION*. Slice 23 makes `att` a genuine 3-D quaternion integrated from a body-rate vector
`ω = (p, q, r)`, keeps the guidance command's FULL 3-D direction, and adds a SKID-TO-TURN autopilot that makes
lift in BOTH body planes at once (α → pitch lift, β → yaw side-force). **THE LESSON, IN ONE SENTENCE:** a
pitch-plane airframe can only pull g in the plane it is already in; skid-to-turn makes lift in two body planes
at once — and the out-of-plane target that was unflyable becomes a hit. Scoped STT-first as a **2-slice arc**
(slice 24 = BANK-TO-TURN + roll-lag, the same substrate, α-only lift + a roll autopilot). Class **4c** (9th
consecutive — truth-fed PN, no seeker ⇒ "draw-count invariance" VACUOUS; live-settable, NO set_fidelity guard).

Gate 0 (8 empirical probes, `temp/slice23_gate0/`) settled the design; findings in `docs/plans/slice23.md`.
Plan HELD on its live overturn candidates — **P4 → the RESULTANT clamp** (`hypot(α,β) ≤ α_max`: the total
maneuver-g ceiling is the SAME `a_max_aero` as the pitch plane, just REPOINTABLE in 3-D — "the discard dies" =
pointing the same authority out of plane, not getting MORE of it); **P6 → include the ω×Iω gyroscopic term**
(exactly 0.0 at STT's single-axis ω); **route → (a) static cross-range offset** (`:pitch_coupled` misses
EXACTLY Y with `max|pos_y| = 0.0`, STT hits). One mild refutation: **P1b** — the in-plane reduction is TIGHT
(~3e-12 m over 2 s), not loose. One new load-bearing finding: **the pitch/yaw moment sign is NOT symmetric** —
under `rotate`, physical nose-up (α+) is a −y body rotation but nose-toward-+y (β+) is a +z body rotation, so
the pitch aero moment is NEGATED onto −y and the yaw is NOT, with physical rates `α̇ = −ω_y`, `β̇ = +ω_z`
(feeding +ω_y to the pitch loop DIVERGES it — the #1 SIGN TRAP's FIFTH occurrence).

Gate 1 (`airframe3d.jl`, the frames.jl-reusing pure lib, +27 teeth): `body_perp_axes`/`body_incidence` (reduce
EXACTLY to `lift_accel` in-plane, bit-for-bit), `lift_accel_3d` (2-plane ⟂-v lift), `attitude_kinematics`,
`body_rate_deriv` (diagonal I + ω×Iω), `stt_moments` (the pitch/yaw sign asymmetry), `rk4_6dof`
(qnormalize-per-stage), `steering_command` (the 2-plane STT inversion + resultant clamp). `AIRFRAME_MODES` grows
`:six_dof` (one line; `:pitch_coupled` NOT renamed); `AirframeParams` UNTOUCHED (C_Yβ rides as a kwarg
defaulting to C_Lα — a symmetric cruciform).

Gate 2 (the wiring, +66 tests): **`_integrate_6dof!`** (the `_integrate_coupled!` sibling, a NEW `elseif` in
`integrate!` gated `haskey(:af_cma) && :airframe === :six_dof`; the `if`/`else` around it VERBATIM). Mints
PARALLEL comp keys `:att_q` (Quat) / `:omega_body` (Vec3), never `:pitch_theta`/`:pitch_q`. ONE joint
`f(pos,vel,q,ω)` closure reading the STAGE q/ω (the slice-17 stage-θ discipline), stepped by `rk4_6dof`; lift is
drag-free this slice (no induced/separation/ρ(z) arm — a named deferral). **The `:alpha` decide arm** gained an
`alpha_6dof` case: `steering_command` (2-plane, resultant clamp) → `alpha_autopilot_delta` per axis →
`(:delta_cmd, :delta_yaw_cmd)`; `:a_ctrl` NOT persisted (the FINDING-1 trap, 6-DOF); `defl_sat = defl_p ||
defl_y` (both fins). **`build_env!`** gained a SEPARATE 6-DOF readout block (`pos_y`, `alpha`, `beta`,
`omega_{p,q,r}`, the attitude quaternion as 4 SCALARS `att_q{w,x,y,z}` — convention 13, `a_lift`,
`turn_radius_m`). **Loader** (`scenario.jl`): `cy_beta`/`inertia_roll`/`inertia_yaw`/`c_roll` PRESENCE-gated per
key AND consumer-defaulted (`:airframe` is live-settable — a slice-19..22 scenario can be toggled to `:six_dof`
mid-run having authored none of them; convention 5's both halves).
⚠ **A gate-2 ADVISOR CATCH — the slice-21 `_atm_on` latent-bug class recurring**: the six_dof readout block was
first gated on `haskey(:att_q)`, but `:att_q` is never deleted, so after the 3-rung cycler leaves `:six_dof`
the stale block fired on a FROZEN attitude and OVERWROTE the fresh scalar readout. FIXED by rung-gating BOTH
rotational blocks on the LIVE `:airframe` (six_dof requires `=== :six_dof`, pitch requires `!== :six_dof`) —
byte-identity-safe (prior slices never reach `:six_dof`); a LIVE-CROSS-TOGGLE test pins both directions.
Gate-2 measured (live tick! path): **THE REDUCTION is tight AND shrinks with dt** (in-plane six_dof vs scalar
`_integrate_coupled!` = 4.46e-11 m at dt=2e-3 → 2.14e-12 at dt=1e-3, ~20.8× — legitimate scheme difference, not
a constant offset — the advisor's wiring-bug detector); **P1a on the wire** (an in-plane run keeps
pos_y/omega_p/omega_r/beta at EXACTLY 0.0); **THE LESSON** (Y=2000, ρ=0.3): `:pitch_coupled` miss 2002.37,
max|y|=0.0 (fully discarded) vs `:six_dof` 0.230, max|y|→2000.19 (it turned) — ~8700×; inert-without-params ≡
`:point_mass` byte-identical; live-toggle crash-safe; the `:a_ctrl` tripwire holds; 4c bit-identical replay.

Gate 3 (the FOUR proofs, convention 14): a NEW handshake discriminator `airframe_6dof` (`_airframe_view_info`
ships it when a missile carries an authored `:af_cy_beta` — key-gated, so slices 16–22 never ship it) upgrades
the client from the 2-D airframe overlay to a TRUE 3-D view. (1) **`slice23_verify.gd`** (S23V OK, exit 0) —
FIVE phases on the live server: `:pitch_coupled` misses ≈ Y (frame-sampled **2002.37**, `max|y| == 0.0` — the
discard, read from the state-frame ENTITY pos, full 3-D on every wire); held-seed replay BIT-IDENTICAL (posdiff
0.0); `:six_dof` INTERCEPTS (frame **5.01**; true 0.230 — sub-metre unreachable at emit_every 16, the
[[ewsim-missile-verifier-sampling]] asymmetry) and TURNS (`max|y| → 2720`), a **399.6×** separation; and the
CAUSATION lever — `set_param af_cy_beta → 0` KILLS the yaw authority and the STT plant DEGENERATES EXACTLY back
to the discard (miss 2002.37, `max|y| == 0.0`), so the out-of-plane authority did not merely correlate with the
hit, it CAUSED it. (2) **`slice23_ui_test.gd`** (S23UI OK) — the 3-D view routing + the 3-RING airframe cycler
(point_mass → pitch_coupled → six_dof, each press → set_fidelity) + the FIVE-way multi-view value-guard (16
drops the button / 17–19 keep the 2-RING cycler [six_dof is a DEAD rung there] / 18 stays terrain-3-D / 21
keeps the atmosphere cycler / 23 → airframe3d); all seven prior airframe/terrain UI tests (16–22) re-run GREEN.
(3) the `Sandbox.tscn` headless SMOKE-LOAD (server `DONE` ⇒ the scene connected + built the airframe3d view, no
parse error). (4) TWO contrasting WINDOWED shots — **`:six_dof`** the cyan trail CURVING out of the launch plane
toward the +Y target ("SKID-TO-TURN — turning in 3-D", cross-range +1024 m, β +3.3°, the full 6-DOF telemetry
panel) vs **`:pitch_coupled`** a STRAIGHT trail with the target off to the side ("PITCH-PLANE — out-of-plane
DISCARDED", cross-range **+0 m**); the two readout panels differ EXACTLY as designed (pitch_coupled ships
pitch_theta/omega_sp/alpha_trim; six_dof ships att_q/beta/omega_p·q·r/pos_y), corroborating the rung-gated
telemetry on the live wire with no stale keys. **The CLIENT 3-D view** reuses slice-18's terrain SubViewport
Node3D world (camera/env/markers/trail `_t3d_*` machinery) MINUS the heightfield ("duplicate, don't share"
keeps the byte-frozen terrain path untouched): a new `_mode = "airframe3d"` with `_enter_airframe3d_mode` /
`_build_airframe3d_scene` / `_airframe3d_on_state` / `_draw_airframe3d_hud`, a wireframe launch-plane floor for
depth, and the nose vector from `att_q` (Godot Quaternion (x,y,z,w) from the core's [w,x,y,z], the direction
axis-swapped but NOT scaled). The full suite is green; slices 1–22 byte-identical.
Run the slice-23 showcase: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice23_out_of_plane.yaml`,
then launch Godot on `clients/godot`. **Cycle the airframe button** point_mass → pitch_coupled → **six_dof** and
watch the trail go from a straight in-plane line (the discard) to a 3-D curve onto the cross-range target (the
hit); drag **C_Yβ to 0** and the STT plant loses its yaw authority and misses like the pitch plane. Re-run the
gate-3 proof headless: start the server, then the console Godot `--headless --path clients/godot --script
res://net/slice23_verify.gd` (exit 0 = pass). The UI test needs NO server: `… --script res://net/slice23_ui_test.gd`.
DEFERRED (NAMED): **BANK-TO-TURN + the roll-lag lesson = SLICE 24** (the same substrate, α-only lift + a
finite-bandwidth roll autopilot, the `:steering = (:skid_to_turn, :bank_to_turn)` rung — against the
out-of-plane maneuver, BTT misses where STT hit); **AERO + INERTIAL CROSS-COUPLING / DEPARTURE** (non-diagonal
I, Clβ/Cnp/Clr, the radome / body-rate parasitic loop — diagonal I + symmetric cruciform + coordinated flight
keep 23/24 clean); **ASYMMETRIC AERO** (C_Yβ ≠ C_Lα); an **OUT-OF-PLANE MANEUVERING TARGET** (slice 24's sharper
foil — this slice's target is static); a **SEEKER in the 6-DOF loop** (flips the class back to 4a / RNG-live);
induced/separation drag and ρ(z) on the 6-DOF path (a later composition).

---

## Slice 24 — BANK-TO-TURN + ROLL-LAG

**Slice 24 — BANK-TO-TURN + ROLL-LAG: the steering law that must bank before it turns (HANDOFF §11 Tier-A)**
— the SECOND slice of the bank-to-turn / 3-D arc, the payoff of the STT-first split, on slice 23's 6-DOF
substrate. Slice 23's SKID-TO-TURN makes maneuver lift in BOTH body planes at once (α pitch + β yaw), so its
⟂-v accel points ANYWHERE off v̂ with NO roll — it turns the instant the guidance command asks. BANK-TO-TURN
makes lift in only ONE body plane (α on the body pitch axis; β actively driven to ≈ 0 — COORDINATED flight)
and must ROLL the body so that single lift plane contains the demanded lift; roll has a FINITE bandwidth
τ_roll. Against the SAME static out-of-plane target STT hit, BTT MISSES. **THE LESSON, one sentence: skid-to-
turn points its lift anywhere instantly; bank-to-turn must ROLL to point its single lift plane first — and
with finite roll bandwidth the time spent banking is time not turning, so against an out-of-plane target BTT
misses where STT hit. You must bank before you turn.**

THE `:steering = (:skid_to_turn, :bank_to_turn)` rung (slice-23 §2 reserved it), on the HELD `:six_dof` plant
— the ONE toggled fidelity (`:airframe` authored six_dof, guidance :pn, autopilot :alpha; convention 9, the
slice-21/22 two-view-claiming-keys precedent). THE CROSS-FIDELITY DEPENDENCY (the slice-19 shape, now
steering-on-airframe): `:steering` is INERT without `:airframe === :six_dof` (the scalar plant has no roll
DOF). Class **4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance" VACUOUS; the
10th consecutive 4c after 14–23; live-settable, no set_fidelity guard). New pure lib additions in
`airframe3d.jl`: `STEERING_MODES`, `bank_angle` (the roll about v̂, shared by command + readout — the #1 SIGN
TRAP's 6th occurrence), `steering_bank_command` (REVERSIBLE-LIFT with NEAREST-REPRESENTATION bank — the gate-0
load-bearing law), `btt_roll_moment` (the ζ=1 bank autopilot moment, τ_roll the sole lever), `btt_moments`
(the `stt_moments` sibling — pitch/yaw DUPLICATED not shared, roll swapped to the autopilot). Wiring:
`_integrate_6dof!` gains a `:bank_to_turn` roll-moment branch (STT damper path TEXTUALLY VERBATIM), the
`:alpha` decide arm a BTT sub-branch (single-plane signed α + a `:phi_cmd` bank seam, β→0), `build_env!` the
gated `bank_deg`/`phi_cmd` readouts, `radar.jl` `steering = STEERING_MODES`, `scenario.jl` the `tau_roll`
loader. Client (`Sandbox.gd`): a slice-24 handshake reuses slice 23's 3-D airframe view but routes the shared
button to the STEERING cycler (value-guarded so a slice-23 wire keeps the airframe cycler — a within-airframe3d
SWITCH), the HUD labels the steering law + shows bank φ, a magenta lift-axis vector visualizes the bank.

⭐⭐ **THE GATE-3 MECHANISM CORRECTION (advisor, load-bearing — the shot's OWN telemetry refuted the plan's
one-liner).** The BTT miss is **NOT** the pure-kinematic "time spent banking is time not turning" — it is a
**DOWNSTREAM AERO-CEILING miss**, a chain: roll lag → cross-range lift throttled by sin(φ) while φ slews → the
missile falls behind → the catch-up demand OUTRUNS the SAME slice-19/23 ceiling → `aero_sat` binds → miss.
Measured over the approach: **`aero_sat` binds 93.2% of the bank_to_turn approach (8876/9525 frames) vs 0.2%
for skid_to_turn (14/9199); τ_roll→0.01 drops it back to 0.2% (19/9200)** — the saturation is the CONSEQUENCE
of the roll lag. ⚠ **THE SLICE-19/23 CONTRAST, precisely (the copy-paste false-claim trap):** the ceiling
`a_max_aero = Q·S·|C_Lα|·α_max/m` binds in 19/20/21/22/23 AND 24 — but under `:bank_to_turn` it binds BECAUSE
the roll lag leaves the missile behind (τ_roll→0 removes the lag AND the saturation), a DOWNSTREAM consequence
of the steering law; under 19/23 it binds from the FLIGHT CONDITION ITSELF, regardless of steering. Slice 24
adds no new cap — it adds a new UPSTREAM CAUSE (the roll lag) that drives the demand into the existing cap.

Gate 0 (8 probes, `temp/slice24_gate0/`, reusing the shipped kernels) forced ONE design change (the naive
"+lift/α≥0" bank churns 180° in-plane [PROBE F], and a hard ±90° flip chatters at the 90° singularity [PROBE
G] → the NEAREST-REPRESENTATION reversible-lift law) and one framing correction (route (a) static is the
COLD-START face — the missile launches wings-level and must roll ~90° to point cross-range lift; the SUSTAINED-
TRACKING face, an out-of-plane MANEUVERING target, is a NAMED DEFERRAL, not a refutation). The GYROSCOPIC ω×Iω
term goes LIVE under BTT (p≠0) but is IMMATERIAL to the miss (gate-0 PROBE D2: ≤3% at lesson τ, 1.3% at the
showcase — because the RATES stay small under coordinated flight in the slow-roll regime, NOT because the
diagonal-I cross-coefficients are small [~0.9]); INCLUDED for honesty. ζ=1 (critically-damped roll loop) is
the named approximation making τ_roll the sole lever; I_xx stays a NON-knob (roll-loop gain); the STT c_roll
damper goes INERT under BTT.

Live-wire goldens (frame-sampled, seed 24, LOS-gated): STT **0.230** (== slice 23's, byte-identical STT path)
vs BTT τ_roll=1.0 **371.79** (**1614×** per-tick / 74× frame-sampled — it TURNED, max|y|→2704, just LATE);
τ_roll→0.01 RECOVERS **0.133** (the causation — the roll LAG caused the miss); τ_roll=2.0 SATURATES **1535**
(toward the discard ≈ Y=2000, no reversal); in-plane Y=0 → max|y|=0.0 EXACTLY (the sign invariant). ⚠ The
recovery proof drives `af_tau_roll → 0.01`, BELOW the slider's declared min 0.1 — a headless causation probe
(the τ→0 limit), not an in-range value; a direct `set_param af_tau_roll = 0` stays FINITE (the `_FRAME_EPS`
consumer floor — convention 6, measured). Four proofs green (verifier: the miss split + af_tau_roll→0 causation
+ bit-identical replay; UI: the steering cycler + the slice-23 MIRROR [a SWITCH not an `or`] + a SIX-way
value-guard + prior UI tests re-run; smoke-load → `EWSIM_SERVER_DONE`; TWO shots: BTT bank φ=120° + aero_sat=1
[the shipped branch] vs STT omega_p≈0 + β=6.9° [the else] — both `_draw` branches proven). Full suite **4335**
(4276 + 25 airframe3d + 34 missile); slices 1–23 byte-identical, proven ON THE WIRE (slice23_verify re-run
reproduces SIX_DOF 5.011 / ratio 399.6× / CY_ZERO 2002.373 to the digit).

Run it live: `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice24_bank_to_turn.yaml`, then
launch Godot on `clients/godot`. **Cycle the steering button** bank_to_turn ↔ skid_to_turn and watch the SAME
target off the plane: bank_to_turn banks LATE (φ→~120°, aero_sat lit) and misses ~372 m, skid_to_turn turns
immediately and hits; drag **τ_roll toward 0.1** and the bank keeps up → the miss shrinks toward the STT hit.
Re-run the gate-3 proof headless: start the server, then the console Godot `--headless --path clients/godot
--script res://net/slice24_verify.gd` (exit 0 = pass). The UI test needs NO server: `… res://net/slice24_ui_test.gd`.
DEFERRED (NAMED): **SUSTAINED-TRACKING / route (b)** — an out-of-plane MANEUVERING target (the demand rotating
faster than the roll loop follows — a DISTINCT face from this slice's cold-start; its own careful mover build);
**AERO + INERTIAL CROSS-COUPLING / DEPARTURE** (non-diagonal I, sustained large p, Clβ/Cnp/Clr, the radome /
body-rate parasitic loop); **ζ ≠ 1 / a 2nd roll knob / a 2nd-order roll actuator**; ASYMMETRIC AERO; a SEEKER
in the 6-DOF loop (→ 4a/RNG-live — **DONE, slice 25**); induced/separation drag + ρ(z) on the 6-DOF path.

---

## Slice 25 — A SEEKER IN THE 6-DOF LOOP

**Slice 25 — A SEEKER IN THE 6-DOF LOOP: the seeker that cannot see out of the plane (HANDOFF §11 Tier-A)**
— the THIRD slice of the bank-to-turn / 3-D arc and its FIRST SENSOR slice. Slices 23 and 24 gave the missile
an airframe that can turn OUT of the x–z plane and a choice of how to point its lift — and both were
TRUTH-FED. Give it a REAL seeker and slice 11's sensor is waiting with the SAME approximation one layer up:
it measures a SCALAR in-plane bearing `λ = atan(Δz, Δx)` and reconstructs `ω = (0, −λ̇, 0)`, an LOS rate
STRUCTURALLY incapable of an out-of-plane component. This cashes a deferral slice 11 wrote into its OWN source
(`missile.jl`: *"Scalar avoids the vector form's tangent-injection / cross-innovation-sign / renormalize bug
surface"*) — the shape of 21 cashing constant-ρ and 22 cashing linear C_L. **THE LESSON, one sentence: slice 23
gave the missile an airframe that can turn out of the plane — but a seeker that only measures IN the plane
produces an LOS rate with no out-of-plane component, so the missile never asks it to: the same 2000 m miss,
from the SENSOR this time.**

⚠ **THE SIGNATURE IS IDENTICAL TO SLICE 23's FOIL AND THE MECHANISM IS NOT** (the copy-paste false-claim trap).
Slice 23's `:pitch_coupled` missed 2002 m with `max|y| = 0.0` because the AUTOPILOT threw the cross-range
command away. Slice 25's plant is `:six_dof` and FULLY CAPABLE of flying it — flip the button and it does, on
the same wire: **the command was never FORMED**, because the measurement had no such component in it.

⭐ **THE ISOLATION IS THE OTHER HALF OF THE CLAIM, AND IT FORCED A RETUNE OFF SLICE 24's WIRE (advisor).** The
arc has produced SIX ceiling misses (19/20/21/22/23/24); a seventh would be unattributable. At slice 24's
ρ = 0.3 the ceiling floor is ~95 m/s² and PN's `N·Vc·λ̇` on a noisy bearing peaks the demand at ~2530 ⇒
`aero_sat` **93.9%** and the arm that must HIT misses by 1268 m (gate-0 P3/P4). Retuned to ρ = 1.0 / σ = 0.3
mrad, **`aero_sat` is 0 in BOTH arms on the shipping wire** — a POINTING miss (the slice-13 framing), asserted
by the verifier as a number in both flight phases, never claimed in prose. ⚠ `a_demand` peaks 356 against a
314 ceiling in the foil arm WITHOUT `aero_sat` firing (the flag keys off the ⟂-v PROJECTION while `a_demand`
is full-magnitude — the sets NEST, slice 19), so the verifier asserts the **FLAG**, never a hand-rolled compare.

⭐⭐ **THE 2-DRAW LOCKSTEP IS WHAT MAKES THE BUTTON LEGAL.** A two-angle seeker draws **2** `randn`/tick against
slice 11's **1**, so a naive rung toggle would be a draw-topology FLIP mid-replay and `set_fidelity` would have
to REJECT the very switch the showcase exists to make (the `:cfar` 4b guard). **Both rungs therefore draw 2
UNCONDITIONALLY and `:pitch_plane` DISCARDS the azimuth sample** — gate the VALUE, never the draw (convention
3's template, applied to a FOIL). Measured 2.0 draws/tick on both rungs ⇒ class **4a WITHIN a 2-draw host**.
**Do NOT "optimize away" the unused draw** — a test pins it against `Xoshiro(seed)` advanced by 2N. The host
is the SCENARIO's `seeker: {two_angle: true}` marker, NOT the fidelity, which is exactly what makes introducing
`:seeker_axes` on a slice-11/13 wire INERT (P11: bit-identical trace incl. the next draw off `w.rng`) — the
guard against the slice-21 `_atm_on` / slice-23 `:att_q` latent-bug class, both of which an advisor caught at
gate 2 rather than by reasoning. **THE DISPATCH PRECEDENCE is explicit and one corner is a LOAD ERROR**
(`two_angle` × `seeker: scan` — the slice-13 profile is single-axis by construction; az×el CFAR is a named
deferral, refused rather than silently branch-ordered — the slice-21 precedent).

New `frames.jl` kernels beside `az_el` (which had sat unused since slice 8 — built for exactly this):
`los_unit_from_angles` and `los_rate_from_angles` (`ω = û × û̇`). **THE ORACLE IS AN IDENTITY, not a
calibration**: with `r = R·û`, `r×v = R²(û × û̇)` ⇒ `(r×v)/‖r‖² ≡ û × û̇`, so the seeker's ω IS the quantity
`los_rate` computes from truth — pinned via an INDEPENDENT closed-form recompute of `(ȧz, ėl)` (convention 11)
at the FP floor, with the **#1 SIGN TRAP's 7th occurrence** (the argument order `û × û̇`) pinned by the
in-plane invariant (`ω_x == ω_z == 0.0` EXACTLY) PAIRED with a does-turn case. ⚠ Measure the oracle EXCLUDING
the init ticks — the tick-1 error is 3.4e-2 (rates seeded 0) vs 8.9e-5 relative after, and round 1 nearly read
it as a sign error.

**THE 10-SLICE 4c STREAK (14–24) ENDS: class 4a, and the seed is load-bearing again for the first time since
13** — draw-invariant YET trajectory-changing (slice 11's combo), live-settable, no `set_fidelity` guard;
conventions 3/11 apply again and replay is SEEDED determinism, NOT the "RNG-free" claim slices 14–24 shipped.

Live-wire goldens (`scenarios/slice25_seeker_3d.yaml`, seed 25): `:pitch_plane` **2000.044** per-tick /
2000.071 frame with **max|y| = 0.0 EXACTLY** and reported **omega_oop = 0.0 EXACTLY** on every frame, vs
`:az_el` **0.008** per-tick / 9.555 frame (probe grid) — `aero_sat` **0/8647** and **0/7760**. ⚠ **The
verifier's own frame grid differs from the Julia probe's (the server's emit phase), and a HIT samples
COARSELY**: it measures 2000.044 / **1.373** / 1456×. Both are correct; the ASSERTS are ONE-SIDED bounds
(`< 30`, `> 30×`) and **the pass text INTERPOLATES what the run measured** rather than quoting a probe figure —
slice 21's gate-3 bug #2, avoided by construction. ⚠ This file also reproduced slice 21's OTHER gate-3 bug
verbatim: **`%g` is not a GDScript specifier**, and an unknown one makes the WHOLE `%` fail so the line prints
as its own format string ON A GREEN RUN. A number that does not print is not a proof.

ONE knob, `sigma_seek ∈ [5e-5, 3e-4]` rad. ⚠ **It is the REALISM lever, NOT the lesson lever** — the miss does
NOT degrade monotonically in σ (0.235/0.243/0.260/0.278 m at 0.05/0.1/0.2/0.3 mrad, then FALLING to 0.057 at
1.0 while `aero_sat` climbs to 25.4%: the noise EXCITES the loop, it does not steer it), and the domain is
bounded by where the ISOLATION survives, not by the physics. DISQUALIFIED and asserted ABSENT in the verifier
(the "a doc claim about a gate must live IN the gate" rule): **`rho`** (isolated domain only [1.0, 1.5] — a
1.5× span, and it moves the one thing this slice must hold), the α-β **`beta`** gain (breaks the isolation at
≥ 0.15 — the slice-11 U-shape), **`speed`** (the slice-19 DEAD-knob finding, 3rd occurrence). The PLANT is held
at skid-to-turn BY OMISSION (BTT binds `aero_sat` 93.2% of its approach — it cannot isolate a sensor), and the
TRACKER at `:filtered` (a 3-D `:raw` arm is slice 11's lesson in a new letter — convention 9).

CLIENT: the slice-23 3-D airframe view REUSED, with the shared button routed to the SEEKER-AXES cycler —
checked BEFORE `steering`/`airframe` ("check the NEW key first", 4th occurrence), so the within-airframe3d
discriminator is now THREE-WAY and both MIRROR cases are asserted (an if/elif SWITCH, not an `or`). The HUD
gains the headline readout `seeker ω out-of-plane: … ← BLIND` straight from the core's `omega_oop` (convention
13 — no client-side physics). Four proofs green (verifier `S25V OK`; UI test `S25UI OK` with a SEVEN-way
value-guard; smoke-load → `EWSIM_SERVER_DONE`; TWO windowed shots — "IN-PLANE SEEKER — BLIND out of plane" at
cross-range **+0 m** with ω_oop 0.00000 vs "AZ/EL SEEKER — LOS rate in 3-D" at **+983 m** with ω_oop 0.00929,
both `_draw` branches proven). Full suite **4399** (4335 + 28 frames + 36 missile); slices 1–24 byte-identical,
proven ON THE WIRE (the 23/24 verifiers re-run reproduce 2002.373 / 5.011 / 399.6× and 371.800 / 74.2× / 5.331
to the digit).

Run it live: `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice25_seeker_3d.yaml`, then
launch Godot on `clients/godot`. **Cycle the seeker button** pitch_plane ↔ az_el and watch the SAME airframe,
SAME PN law, SAME target: the in-plane seeker's trail stays dead flat (cross-range +0 m, ω_oop 0.00000) and
misses by ~2000 m; the az/el seeker curves out and intercepts. Re-run the gate-3 proof headless: start the
server, then the console Godot `--headless --path clients/godot --script res://net/slice25_verify.gd` (exit 0
= pass). The UI test needs NO server: `… res://net/slice25_ui_test.gd`.
DEFERRED (NAMED): **RADOME / body-rate parasitic loop** (the arc's named end point — an error slope perturbs a
TWO-ANGLE measurement as a function of look angle, and there was nothing for it to perturb before this slice);
a seeker **FOV / gimbal limit** (now expressible for the first time); **monopulse / az×el CFAR** (slice 13's
`:scan` lifted to two angular axes); a MEASURED range/closing speed (`Vc` stays truth here); the 3-D `:raw`
arm; **seeker noise × the BTT roll loop — DEAD, not deferred** (killed at gate 0: the ζ=1 τ_roll=1.0 roll loop
is a ~1000:1 low-pass — `std(Δφ_cmd)` 1.07 rad/tick vs `std(Δφ_ach)` 1.6e-5; the slice-20 dead-scalar-fin
precedent — do not re-propose it cold); the out-of-plane MANEUVERING target (composes with this slice).

---

## Slice 26 — THE RADOME / BODY-RATE PARASITIC LOOP

Slice 26 (§11 Tier-A, the bank-to-turn / 3-D arc's NAMED END POINT) — **THE RADOME / BODY-RATE
PARASITIC LOOP: the seeker that sees the missile's own nose — COMPLETE & green (4470 tests).**

Slice 25 wrote this slice down as a hard prerequisite in its own deferral list: *"an error slope
perturbs a TWO-ANGLE measurement as a function of look angle; there was nothing for it to perturb
before this slice."* It is ALSO the home of a lesson **slice 15 NAMED, slice 19 DEFERRED and slice 20
HUNTED AND KILLED**: the GUIDANCE LIMIT CYCLE. Slice 20's gate 0 proved no such cycle exists on the
ACTUATOR feedback path (`δ_max` structurally shadows `δ̇_max`, its FINDING 7). **It arrives here
through a wholly different feedback path: the SENSOR's.**

THE LESSON: the seeker does not look at the target directly — it looks through a RADOME, which
REFRACTS by an amount depending on WHERE IT IS LOOKING through it, `ε ≈ R·(look angle off the body
centerline)`. So when the missile's OWN BODY rotates, the look angle changes, the bend changes, and
**the line of sight the seeker reports MOVES — with the target perfectly still.** That closes a
feedback path `q → look → ε → apparent λ̇ → PN → a_cmd → α → q`, and past a critical loop gain the
loop is UNSTABLE: **the missile shakes itself into a sustained limit cycle, with a NOISELESS seeker
and a stationary target.**

⚠ **THE PROJECT'S FIRST TRUE POSITIVE-FEEDBACK INSTABILITY, AND THE PHRASE SLICE 20 FORBADE IS
EARNED HERE.** Slice 20 carries a standing warning ("say DEGENERATIVE SPIRAL, never positive
feedback") because its speed bleed is self-limiting and the positive sign sits only on the tracking
error past a crossing. Slice 26 is the opposite in every respect that matters: a **loop gain**, a
**stability boundary**, and **self-excitation from zero input**. Do not import slice 20's language
here, and do not import slice 26's anywhere else.

⭐⭐ **THE THRESHOLD FACTORIZES AS A LOOP GAIN — `N·|R_crit| ≈ 0.38`, constant to ±3% across a 2.67×
span of N** (0.390 / 0.380 / 0.400 / 0.390 / 0.400 at N = 3/4/5/6/8, i.e. R_crit = −0.130 / −0.095 /
−0.080 / −0.065 / −0.050), **and `|R_crit| ∝ ρ`** (0.100 / 0.095 / 0.097 / 0.095 at ρ = 0.6/1.0/1.5/
2.0). ⚠ It is a MEASURED stability boundary, NOT an algebraic identity — do not write it in slice
21's ρ-factor or slice 22's `α_stall/α_max` language. **The teaching payload is the design trade:** a
radome slope is not good or bad by itself; |R| = 0.1 is a POOR radome and |R| ≤ 0.03 a good one, but a
missile that wants a HIGHER navigation constant needs a BETTER radome to keep the same margin, and one
at LOWER dynamic pressure better still. **YOU CANNOT BUY N WITHOUT BUYING GLASS.**

⭐ **THE METRIC IS AN OSCILLATION, NOT A MISS — a NEW KIND of gate-3 proof for the suite** (slice 20's
plan sketched this shape for the cycle it never got to ship). rms body pitch rate over the approach:
**0.01245 → 0.88138 rad/s = 70.8×** between R = −0.09 and −0.10 (per-tick, mid-half window). ⚠ **The
MISS is NOT the metric and IS NOT MONOTONE ANYWHERE** (1.73 m at R = −0.15 sits BELOW 3.35 m at
−0.12): **the ringing arm STILL HITS (2.18 m)**, and the verifier pins that so a later slice cannot
"fix" the scenario by chasing a miss that was never the claim. ⚠ **`max|q|` is neither frame- nor
noise-robust** (peaks OVERLAP across the threshold) — **rms, never the peak.**
⚠ **READ THE WINDOW BEFORE THE NUMBER — TWO ARE IN USE AND BOTH ARE HONEST.** The docs quote rms over
the **MIDDLE HALF OF TICKS** (and that grid's ×16 decimation); the verifier computes rms over **FRAMES
that are CLOSING with r > 1000 m**, the same window its isolation counts use. That window includes the
early transient, so its baseline is higher and its ratio smaller: **70.8× (docs) vs 23.0× (verifier)**.
A reader who carries a docs number to the verifier's output will think something drifted. (The
slice-21/25 gate-3 bug class, pre-empted rather than repeated.)
⭐ **WITHIN a window, THE rms METRIC IS FRAME-ROBUST — REVERSING THE ARC'S USUAL SAMPLING CAVEAT**
([[ewsim-missile-verifier-sampling]]): a ~2 Hz ring sampled at 62.5 Hz reproduces the per-tick figure
to 3 digits ON THE SAME GRID (0.88372 frame vs 0.88138 tick; 0.01212 vs 0.01245 at R = 0) — **which is
exactly why the oscillation is the better headline than any miss in this arc.**

⭐ **THE ISOLATION IS MADE DIFFERENTLY FROM SLICE 25's, AND MUST NOT COPY IT.** `aero_sat == 0` is
IMPOSSIBLE here — an oscillation drives demand and demand hits the ceiling (60.8% at the showcase
point). Instead: **raise α_max 3× (0.3 → 0.9, ceiling 330 → 990) and THE ONSET DOES NOT MOVE** —
only the cycle's amplitude grows (max|q| 1.39 → 4.24). **The ceiling BOUNDS the limit cycle; the
radome decides whether there IS one.** The other caps are provably clear on the shipped arm:
`defl_sat` 1–2 ticks in ~9400 (0.02%, cap #3), ceiling 329.87 ≪ `a_max` 3000 (cap #1), no stall.

⭐ **STRUCTURAL, NOT NOISE AMPLIFICATION.** The tempting story ("a noisy seeker excites the airframe")
is REFUTED: at **σ_seek = 0** — a perfectly noiseless seeker — R = −0.10 still rings, a **106× rms
jump**. The loop excites ITSELF. ⚠ Related: at slice 25's σ = 3e-4 the seeker NOISE ALONE puts 7× the
σ=0 baseline of jitter on `q`, compressing the signature 106× → 13.8×, so the scenario re-authors
σ = 5e-5 (slice 25's own knob MINIMUM — an in-domain value) and **`sigma_seek` is DISQUALIFIED as a
knob here: on this wire it is a knob that DEGRADES the lesson beside it.**

⚠ **THE THRESHOLD IS THE GUIDANCE LOOP'S, NOT THE AIRFRAME'S — "more aero damping fixes it" is
REFUTED.** `Cmq` from −50 to −250 leaves the onset at EXACTLY −0.095 (the autopilot's `k_q` supplies
~98% of the damping — slice-20 FINDING 3 on this same airframe). The ring sits near **1.7–2.1 Hz**
(σ = 0 only, two independent estimators AGREEING; they disagree 2× at R = −0.095 near onset, so quote
the band where they agree) against the bare airframe's short-period 1.396 Hz. Never call this "the
airframe going unstable" — that is slice 22 half B, a different mechanism.

⭐ **THE MECHANISM IS FRAME-EXACT, AND MEASURING IT CAUGHT A SIGN ERROR IN THE PLAN'S OWN FIRST
DRAFT (the #1 SIGN TRAP's 8th occurrence).** On a FROZEN geometry (target, missile and true LOS all
held still, only the attitude rotating, so `d(look)/dt` is 100% body rate): **`ε̇_el =
+R·cos(look_az)·ω_y` and `ε̇_az = −R·ω_z`**, exact to 6 digits. The textbook writes `−R·θ̇`, and
transliterating that to `−R·q` HERE is the wrong sign: this project's convention is nose-up = a **−y**
body rotation (slice 23), so `θ̇ = −ω_y` while `q` names `ω[2] = ω_y`. **Nose-up (`q < 0`) with
`R < 0` ⇒ `ε̇_el > 0`: the LOS appears to rotate UP, which commands MORE nose-up.** The wrong sign
survived into a hand-written `@test ėe_up < 0` and was caught by the PAIRED coefficient assert on the
same value — which is the entire reason sign assertions are paired.
⚠ **AND IT CANNOT BE IDENTIFIED IN CLOSED LOOP — a general result worth keeping.** Fitting
`ε̇_el ≈ a·ėl_true + b·q` on the live wire returns **R² = 0.999 with `a/R` ranging 1.9…5.5**: the
regressors are COLLINEAR, because a missile that is tracking pitches at nearly the rate the LOS
rotates. **A parasitic gain cannot be measured on a tracking missile — freeze the geometry**, which
makes the isolation a pure-kernel tooth rather than an in-loop regression.

⚠ **THE SIGN IS ONE-SIDED AND THE OTHER SIGN IS A DIFFERENT FAILURE.** Positive R never rings out to
+0.6 — instead the seeker UNDER-reports the LOS rate (`ω_app/ω_true` 1.00 → 0.593), the EFFECTIVE
navigation ratio sags, and the miss opens from **sluggishness** (0.23 → 7.66 m). One knob, two
entirely different failure modes on its two signs — the `af_cma` shape, where 0 is the benign
interior point. The de-tuning face is a NAMED DEFERRAL (convention 9).
⚠ **`ω_app/ω_true` IS A DIAGNOSTIC, NOT THE MECHANISM (advisor)** — once the loop rings it is
dominated by the cycle's own body-rate feedthrough, i.e. THE SAME FACT AS `rms q` TOLD TWICE. It
ships as `omega_ratio`, labelled a consequence, and must never be quoted beside `rms q` as
independent evidence (the convention-4 false-claim trap).

GATE 1 — `frames.jl` gains `look_angles` (`az_el ∘ rotate_inv` — the LOS off the missile's own
boresight) and `radome_error` (`ε = R·look`, per angle). **Both one-liners ON PURPOSE: the physics is
the FEEDBACK PATH, not the formula.** Teeth: `R = 0 ⇒ (0.0, 0.0)` exactly, PAIRED with a does-perturb
case; the identity-attitude degenerate; linearity in both arguments; the frozen-geometry parasitic
gains as NUMBERS; the sign-flip mirror. GATE 2 — the perturbation lands on the MEASURED angles inside
`_observe_point3d!`, **after the two `randn` draws and before the trackers**, so the α-β filter
differentiates the bent angle and PRODUCES the parasitic rate itself (never hand-injected — advisor).
⭐ **BYTE-IDENTITY IS A BRANCH with the else-arm slice-25 VERBATIM, and the measurement is stronger
than expected: an authored `R = 0` is BIT-IDENTICAL to the key being absent** (`ε = 0·look` is exactly
±0.0 and `a + ±0.0 === a`). **That VERIFIES the knob-vs-rung discriminator rather than arguing it** —
R = 0 is not merely "an in-domain slider value", it is bit-identical to the radome not existing, which
is precisely why this is a KNOB like `af_cma`/`af_k_induced` and not a rung like `:atmosphere` (whose
off-state is `H = ∞`, a limit point no slider reaches). The branch still earns its keep: byte-identity
is BY CONSTRUCTION (the no-key arm never forms ε), not by a zero that happens to cancel.
⚠ **RUNG-GATED on the LIVE `:airframe === :six_dof`, NOT on `haskey(:att_q)`** — that key is minted by
`_integrate_6dof!` and NEVER deleted, so a key-gated radome would keep refracting through a FROZEN
attitude after a cross-toggle. **The slice-21 `_atm_on` / slice-23 stale-readout class, 3rd
occurrence**, pinned by a live cross-toggle test. `haskey(:att_q)` stays ONLY as a crash guard.
The loader key is PRESENCE-gated on `radome_slope` (the `alt_hold_m` precedent — every 11/13/25
scenario HAS a `seeker:` block, so block-gating would break them all) and validated **FINITE ONLY**:
the sign IS the lesson and every magnitude is crash-safe (gate-0 P5B ran |R| to 1e6 with all telemetry
finite), so a magnitude bound would be a fake constraint. The draw count stays EXACTLY 2/tick (slice
25's button legality rests on it). `LIVE_FIDELITY_MODES` UNTOUCHED — no new rung.
**Class 4a** (draw-invariant, RNG-live — the seed is load-bearing, conventions 3/11 apply; the 2nd
consecutive 4a after slice 25). Telemetry, key-gated: `radome_slope` / `radome_eps` / `radome_eps_az`
/ `look_angle` / `omega_ratio`.

CLIENT — ⚠ **THE BUTTON IS DROPPED, and the slice-20 precedent DELIBERATELY DOES NOT TRANSFER
(advisor).** The discriminator is not preference: *does the button's other position leave this slice's
lesson intact?* For slice 20 it did — `:point_mass` makes induced drag INERT, so nothing false is
displayed. Here the inherited cycler would be slice 25's `seeker_axes`, and its other position
(`:pitch_plane`) leaves the radome **LIVE AND REFRACTING** on a missile that ALSO misses by 2000 m for
a wholly unrelated reason: **two mechanisms compounding in one view, which is what convention 9 exists
to prevent**, and the "identical signature, different mechanism" trap slice 25 spent a section on. So
slice 26 ships a `radome_view` handshake marker and the client HIDES the button — **slice 16's
Option-P′, second use, and slice 16 is the right analogue anyway: a live knob spanning a stability
boundary with no button at all.** ⚠ **The drop needs BOTH sites**: `_enter_airframe3d_mode` hid it and
`_update_fid_btn`'s `"airframe"` case turned it straight back on (the scenario DOES carry an
`:airframe` fidelity, HELD at six_dof) — exactly the "defensive against a re-show" note slice 16 left
in that same branch, now load-bearing for a second slice. The 3-D airframe view + the new HUD headline
(`RADOME PARASITIC LOOP — RINGING` / `RADOME — refracting, loop STABLE`, plus the body rate, ε and the
look angle) are the only other client edits.

THE WIRE (seed 26, `scenarios/slice26_radome.yaml`, ρ = 1.0, N = 4, α_max = 0.3, σ = 5e-5, STT and
`seeker_axes: az_el` HELD): rms q **0.01245 (R = 0) → 0.88138 (R = −0.10) = 70.8×**, onset between
−0.090 and −0.095 (0.01398 → 0.61603), plateau past −0.10 (the α_max clamp bounds the cycle), miss
0.155 → 2.179 m (BOTH HIT), `defl_sat` 0.02%, ceiling 329.87, replay posdiff **0.0**.
⚠ **THE LOOK ANGLE STAYS SMALL AND THE PEAK MUST NOT BE QUOTED**: `ε = R·look` is a small-angle model,
and the look angle is **≤ 13° over the ENTIRE guided approach**, exceeding 30° on **6 of 9400 ticks,
first at r = 3.5 m** — the LOS sweeping past the nose in the last 5 ms. The telemetry PEAKS at 103.6°
(179.1° on the R = 0 arm at r = 0.5 m) and that is a CPA geometry artifact, not a regime the model is
asked to cover.
⭐ **THE DECLARED DOMAIN'S ENDPOINTS ARE MEASURED, NOT INFERRED FROM THE INTERIOR (advisor,
post-commit).** The first cut of the verifier proved the isolation at −0.10 / −0.09 / +0.06 — but a
student can drag the slider to its MINIMUM, −0.12, where `aero_sat` runs ~95%, and no gate covered
it. **A `DOMAIN_MIN` phase now does**: at −0.12 `defl_sat` is **0/499** (cleaner than the shipped
point's 2/9400 per-tick), the ceiling still 329.84, every telemetry scalar finite, the missile still
closes (3.992 m), and rms **0.83384** — i.e. the metric **PLATEAUS rather than grows** past onset,
which is the measured reason the domain stops where it does. **General rule: the endpoints of a
declared knob domain should be measured** — the [[ewsim-missile-verifier-sampling]] "the range gate
can dictate which arms you may ship" discipline applied to a knob range instead of a sweep.

KNOB — **ONE** (`radome_slope ∈ [−0.12, +0.06]`), bounded by the METRIC'S PLATEAU. **NOT knobs,
deliberately:** `n_pn` (live-read every tick, so NOT a dead knob — disqualified because it moves the
LOOP GAIN the lesson is ABOUT, so a student could cross the threshold with the radome untouched: the
confounded-lever rule), `rho` (same, plus slice 25's [1.0, 1.5] isolated domain), `af_alpha_max` (it
sets the cycle's AMPLITUDE, the thing the isolation holds fixed), `sigma_seek` (above). All five
disqualifications are asserted IN the verifier's handshake check and the UI test's knob check ("a doc
claim about a gate must live IN the gate").

FOUR PROOFS GREEN. `slice26_verify.gd` → **`S26V OK`** (RINGING rms_q **0.80408** / max|ε| 0.01243 rad
/ miss 5.210 / max|y| 2999.6 / aero_sat **268/496** / defl_sat **0** / ceil 329.84; REPLAY posdiff
**0.0** — a limit cycle replaying bit-for-bit is a stronger statement than a smooth trajectory doing
so; QUIET at −0.09 rms_q **0.03493** = **23.0×** with max|ε| still 0.00165 — *the glass refracts on
BOTH sides, the LOOP is what changed*; MIRROR at +0.06 rms_q **0.01357** = **59.2×**; DOMAIN_MIN at
−0.12 rms_q **0.83384** / defl_sat **0/499** / aero_sat 466/499 / ceil 329.84 / miss 3.992).
⭐ Two telemetry keys that shipped with NO tooth — `omega_ratio` and `radome_eps_az` — got one each
(advisor: *"a live wire key with no tooth is the kind that rots"*): the ratio is loosely pinned near
1 at R = 0 (0.919 — the α-β tracker lags truth, so it is NOT exactly 1) and ≥ 2× that when ringing,
with the co-moving `ω_truth → 0` divide asserted FINITE; `radome_eps_az` is EXACTLY 0.0 at R = 0 and
nonzero when ringing (it is nonzero only BECAUSE the target is off the x–z plane).
`slice26_ui_test.gd` → **`S26UI OK`** (six teeth incl. the SHARP slice-25 MIRROR — the same fidelity
WITHOUT the marker keeps its cycler, proving an if/elif SWITCH on the MARKER — and an EIGHT-way
value-guard where 16-vs-26 is asserted on BOTH mode and visibility so the two button-dropping branches
cannot collapse). `Sandbox.tscn` smoke-load → **`EWSIM_SERVER_DONE`**. TWO windowed shots at the SAME
range (~3.65 km): **"RADOME PARASITIC LOOP — RINGING"** (q **+1.168 rad/s**, ε −0.00255 rad at look
8.0°, a_cmd 361.85, aero_sat 1, omega_ratio 6.90, track_gap 342.21) vs **"RADOME — refracting, loop
STABLE"** (q **+0.019 rad/s**, ε −0.00102 rad at look 2.5°, a_cmd 39.97, aero_sat 0, omega_ratio 1,
track_gap 10.50). **The 23/24/25 verifiers re-run reproduce their STATUS numbers TO THE DIGIT**
(2002.373 / 5.011 / 399.6×; 371.800 / 5.011 / 74.2× / 5.331; 2000.044 / 1.373 / 1456.5× / 40.925 m).
⚠ **One gate-3 defect of the slice-21/25 class, in the PROOF not the physics: the HUD headline ran off
the right edge** (`"…the body rate fe|"` — it is drawn at `vp.x − 430` in 20 px, so ~38 characters is
the width). **A proof you cannot read is not a proof**, exactly as with `%g`.

Run: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice26_radome.yaml`, then the
console Godot `--headless --path clients/godot --script res://net/slice26_verify.gd` (exit 0 = pass).
The UI test needs NO server: `… res://net/slice26_ui_test.gd`.
⚠ **KNOWN-LATENT DISPLAY DEFECT, DOCUMENTED RATHER THAN BACKPORTED (found at slice 27's gate 3, and it
is LIVE, not historical): this slice's HUD headline keys off the INSTANTANEOUS `|q| > 0.5`, and a limit
cycle crosses zero TWICE PER CYCLE — so a RE-SHOOT of this scenario has roughly even odds of rendering
"RADOME — refracting, loop STABLE" on the RINGING arm.** The shipped shot caught q = +1.168 and is
correct; the capture instant is what saved it. **Slice 27 is the fix** — a display-only PEAK-HOLD on
|q| (an instrument, not physics), gated on the slice-27 telemetry key so THIS slice's label path stays
byte-identical. Deliberately NOT backported: it is a cosmetic path on a shipped slice whose artifact
is already correct. **Anyone re-shooting this scenario to compare against slice 27 must expect it.**
DEFERRED (NAMED): a **LOOK-ANGLE-DEPENDENT slope `R(look)`** (real radomes have a wiggly slope curve
and the design case is the worst LOCAL slope — this slice ships the constant-slope linear model as a
§1 named approximation); **the de-tuning face of positive R** (measured, real, a different lesson);
a **radome-slope COMPENSATION / stability-margin autopilot** (a rate-gyro feed-forward cancelling the
parasitic term — **DONE, slice 27**); a seeker **FOV / gimbal limit** (this
slice makes the look angle a first-class quantity, so it is now doubly expressible); monopulse / az×el
CFAR; a MEASURED `Vc`; the 3-D `:raw` arm; the out-of-plane MANEUVERING target (composes with this).

---

## Slice 27 — THE RADOME-SLOPE COMPENSATION AUTOPILOT

**Slice 27 — THE RADOME-SLOPE COMPENSATION AUTOPILOT: buying margin with a gyro (HANDOFF §11 Tier-A)**
— the FIFTH slice of the bank-to-turn / 3-D arc, and the one **slice 26 named as its own successor**
("a rate-gyro feed-forward that cancels the parasitic term — the natural slice 27, and it needs this
one"). **COMPLETE & green (4545 tests).**

Slice 26 built the disease. Slice 27 is the cure — **and the point of the slice is that the cure is
PARTIAL, in a way that is exactly quantifiable.** The missile already carries a rate gyro (the α/β
autopilot has fed on `:omega_body` since slice 23), so feed slice 26's measured coupling forward with
the slope the guidance computer BELIEVES it has, `R̂`, and subtract it. **THE LESSON, one sentence:
a rate-gyro feed-forward cancels the radome's parasitic term to the accuracy of the slope estimate it
is given, so what closes the loop is the RESIDUAL `R − R̂` and slice 26's boundary becomes
`N·|R − R̂|/ρ ≈ 0.38`: compensation buys MARGIN, NOT IMMUNITY, and the design requirement is not a
better radome but a BETTER-KNOWN one — here, to ±0.0475.**

⚠ **SLICE 26's LANGUAGE AND ITS PROHIBITIONS ARE INHERITED WHOLE.** The instability is still slice
26's — a true positive-feedback loop with a loop gain, a stability boundary and self-excitation from
zero input. Slice 20's "degenerative spiral" language is still forbidden here, and slice 26's is
still forbidden everywhere else. **Slice 27 adds NO new instability and NO new cap; it adds a SECOND
TERM INSIDE THE SAME LOOP GAIN.**

⭐⭐ **THE BOUNDARY SHIFTS ONE-FOR-ONE — ONE MEASUREMENT CARRIES BOTH THE HEADLINE AND THE ISOLATION,
AND A SECOND (THE MISS AT BASELINE) RULES OUT THE REMAINING READING.** ⚠ That phrasing is deliberate:
slice 25's isolation was ONE number (`aero_sat == 0`) and slice 26 had to warn "do not copy slice 25's
isolation" — this one is TWO numbers with different failure modes, and compressing it to "the same
measurement" would hand a later slice licence to ship one where the tests assert two. Sweeping the true
slope R down at fixed R̂ gives an onset whose RESIDUAL is CONSTANT — −0.095 / −0.095 / −0.095 / −0.095
/ −0.100 / −0.100 at R̂ = 0 / −0.05 / −0.10 / −0.15 / −0.20 / −0.30 (gate-0 P2A, at N = 4). An
**OFFSET**, across a 6× span. **That is not a stylistic preference for one statistic: the obvious
alternative story is DE-TUNING** — slice 26 measured that `ėl` and `q` are COLLINEAR in closed loop
(R² = 0.999), so subtracting `R̂·cos·ω_y` from `ėl` is numerically near-indistinguishable from SCALING
`ėl` DOWN, i.e. from lowering effective N, and a "compensator" that worked that way would quiet the
ring just as convincingly (advisor, and it was the sharpest risk in the slice). **A GAIN CANNOT
PRODUCE A CONSTANT OFFSET**, and the miss stays at baseline where de-tuning OPENS it (slice 26
measured that signature at 0.23 → 7.66 m). ⇒ cancellation, not de-tuning, from ONE measurement.

⭐ **SLICE 26's LAW SURVIVES THE SUBSTITUTION VERBATIM** (gate-0 P3A, measured with R̂ = −0.20 HELD, so
every point is a COMPENSATED missile): `N·|R − R̂|/ρ` = **0.390 / 0.400 / 0.400 / 0.390 / 0.400** at
N = 3/4/5/6/8 and **0.400 / 0.400 / 0.387 / 0.390** at ρ = 0.6/1.0/1.5/2.0, against slice 26's
uncompensated 0.390 / 0.380 / 0.400 / 0.390 / 0.400. **The same law, to the third digit.** ⚠ Say
"MEASURED boundary", NEVER "identity" — slice 26's rule, unchanged (contrast slice 21's ρ-factor and
slice 22's `α_stall/α_max`, which ARE algebraic identities). ⭐ The teaching payload is a REQUIREMENT
NUMBER: slice 26 sold the factorization as *"you cannot buy N without buying glass"*; slice 27 adds
the third currency — **or you can buy a gyro and KNOW your glass to within `0.38/(N·ρ)`.**

⚠⚠ **BUT IT IS NOT AN EQUIVALENT RADOME — the finding that keeps the slice honest (gate-0 P3B).** The
residual predicts the STABILITY BOUNDARY exactly; it does NOT make `(R, R̂)` the same missile as
`(R − R̂, 0)`. Over-compensating to a residual of +0.15 misses by **31.4 m** where a BARE radome at
+0.15 misses by **0.47**. **Why:** the look angle moves for TWO reasons — the BODY rotating, which the
gyro sees, and the LOS itself rotating, which it does not. The body-rate half cancels EXACTLY (hence
the exact boundary); the LOS-driven half survives. **A GYRO CAN ONLY CANCEL WHAT A GYRO CAN SEE.**

⭐ **THE ARCHITECTURE WAS CHOSEN BY MEASUREMENT, NOT ASSUMED (advisor).** Gate 0 built BOTH candidates:
the `:rate` gyro feed-forward (what ships) and an `:angle`-domain corrector that subtracts `R̂·look`
from the measured angle ahead of the tracker — superficially cleaner, since it removes the bend
itself. **The angle-domain arm FAILS**: its onset residual DRIFTS instead of holding (−0.095 → −0.005
as R̂ goes 0 → −0.30), and on the diagonal **with PERFECT knowledge `R̂ = R = −0.50` it RINGS anyway**
(rms 0.844, miss 131 m) where the rate arm stays quiet (0.014). **The reason is a general principle
worth more than the slice:** the angle-domain corrector needs the LOOK ANGLE and can only obtain it by
rotating the MEASURED LOS into the body frame — **a LOS it can only see through the very bend it is
removing**, so its error is second order in `R·R̂` and stops being small exactly when the glass gets
bad. The rate arm's correction signal is the GYRO, **outside the corrupted path**. ⇒ **compensate with
a signal that is not itself corrupted by what you are compensating.** ⚠ The advisor predicted the
OPPOSITE defect (the α-β filter lags the parasitic term inside `ėl_est` while the gyro path does not,
so `:rate` might under-cancel); that effect is REAL but SMALL (~17%) and swamped. `:angle` does NOT
ship (convention 9) — a gate-0 finding and a named deferral.

⚠⚠ **GATE-1 FINDING — THE TWO-TERM LAW DOES NOT CANCEL EVERYTHING, AND THE TESTSET FOUND IT.** The
cancellation tooth FAILED on first run: ELEVATION cancelled to 1e-16, AZIMUTH left **0.005984** against
a 2e-4 tolerance. The cause was in slice 26's own measured table, which this slice's plan had quoted
without noticing: for an OFF-BORESIGHT LOS a PITCH rate also moves AZIMUTH (`ε̇_az/R = −0.0598`) — a
CROSS-TERM the classic two-term feed-forward does not model. **It is a §1 named approximation OF THE
COMPENSATOR, not a defect in it**, and it does not touch the claim, for a reason worth stating:
**elevation is the channel that closes the pitch loop** (gain 0.9487 vs the cross-term's 0.0598,
~16× down) and the residual law was measured END TO END with this very law. The tooth now asserts the
honest thing — elevation cancels EXACTLY, azimuth cancels under pure yaw, and the pitch→azimuth
residual is PINNED at `R̂·k_cross·ω_y` against a cross-coefficient MEASURED from `radome_error` (never
a magic constant, convention 11). ⇒ **on the loop-closing axis compensation IS a slope offset; on the
other it is a slope offset plus a known second-order term.**

⚠ **THE SHOWCASE WIRE WAS CHOSEN ON MODEL VALIDITY, NOT TASTE — and the first candidate was rejected
by a measurement.** The crossing must land mid-slider, which needs `|R| ≈ 2·|R_crit| = 2·0.38/(N·ρ)`.
Reaching that by WORSENING THE GLASS to R = −0.30 was tried first and REJECTED at gate 0: it puts the
look-angle deciles at 12–25° with **528/9924 ticks past 30°** (5.3%), i.e. the linear small-angle model
`ε = R·look` carrying the lesson exactly where it is weakest. **Raising N instead (N = 8, R = −0.10,
ρ = 1.0)** keeps the glass REAL (slice 26: `|R| = 0.1` is POOR, ≤ 0.03 good) and the look-angle budget
at slice 26's own (**6/9421 ticks past 30°**, 0.06%). ⚠ **Be honest about the symmetry (advisor): N = 8
is the TOP of slice 26's own measured range**, so this wire sits at one extreme just as R = −0.30 sat
at the other — what separates them is a MEASUREMENT, not which extreme sounds realistic. ⭐ And it
instantiates slice 26's own payload: this is exactly the missile that design trade condemned.
⚠ `n_pn` STAYS AUTHORED, NEVER A KNOB — slice 26 disqualified it and the objection is STRONGER here:
with a compensator on the wire a student who crossed the boundary via N would credit the compensator.

⚠ **THE METRIC IS SLICE 26's, UNCHANGED — rms BODY RATE, never the peak, never the miss — and this
wire ENFORCES the discipline rather than tempting you away from it: THE UNCOMPENSATED ARM STILL HITS**
(per-tick 2.447 m vs 0.316 m). ⭐ The rms metric is FRAME-ROBUST here as in slice 26 (per-tick 0.81712
vs frame-sampled 0.81704, ratio 0.9999). ⚠ **THE ISOLATION IS SLICE 26's, RE-RUN ON THE COMPENSATED
BOUNDARY**: `aero_sat == 0` is IMPOSSIBLE (99.8% on the uncompensated arm — do NOT copy slice 25's),
so instead **raise α_max 3× and the CROSSING DOES NOT MOVE** (stays at R̂ = −0.055 while the amplitude
grows, rms 0.844 → 2.568, max|q| 1.42 → 4.34). Other caps clear on the shipped arms: `defl_sat`
0.01–0.02% (cap #3), ceiling 329.87 ≪ `a_max` 3000 (cap #1), max|α| 0.156 < α_max 0.3 (no clamp leak).

⭐ **TWO KNOBS, AND CONVENTION 9 IS SATISFIED BY A MEASUREMENT, NOT BY COUNTING SLIDERS** (advisor):
they are two halves of ONE quantity, and three gate-0 measurements say so. **(1) THE DIAGONAL** — move
both together and NOTHING HAPPENS (rms q 0.019 / 0.016 / 0.014 / 0.012 / 0.011 at R = R̂ = 0 / −0.05 /
−0.10 / −0.20 / −0.30, quiet out to −0.80): **the missile does not care about glass it KNOWS about.**
**(2) BOTH KNOBS CROSS AT THE SAME RESIDUAL** — dragging R̂ with R held at −0.10 crosses at R̂ = −0.055;
dragging R with R̂ held at −0.10 crosses at R = −0.145. Residual −0.045 both times, from opposite
directions. **(3) THE GRID is the whole slice in one picture**: stability is a DIAGONAL BAND in
(R, R̂), not a rectangle — **and slice 26 is this grid's `R̂ = 0` column.** ⚠ **THE DOMAINS, AND WHICH
ENDPOINT IS ACTUALLY MEASURED (advisor — slice 26's post-commit lesson was "measure the endpoints",
and half of these are NOT set by a measurement, which the plan says plainly rather than implying
otherwise):** R̂ ∈ [−0.15, 0.00] — the **FLOOR is UI FRAMING** (the crossing at −0.055 sits at ~37% of
travel; the metric is MEASURED FLAT from −0.06 to ≈ −0.30 and the de-tune face does not bite until
residual ≈ +0.3 — miss 2.9 m at R̂ = −0.40, 18.8 at −0.50, 214 at −0.80), while the **CEILING (0.00)
IS physical** (a POSITIVE R̂ compensates the WRONG WAY and is exactly a WORSE radome: R̂ = +0.10 against
R = −0.10 misses by 25.99 m, reproducing slice 26's BARE R = −0.20). R ∈ [−0.20, 0.00] — **the floor
IS measured**: one clear step past the crossing at −0.145, deep enough that the ring is unambiguous
(aero_sat 99.7%) while the look-angle budget holds (8/9400 past 30°), and it lands the residual at
−0.10, the same residual slice 26 shipped. ⚠ **Do NOT sell this as the `af_cma` two-failure-modes
shape**: within its domain this knob shows ONE, and the other is a measurement recorded outside it.

**KNOB, NOT RUNG, and the button stays DROPPED.** `R̂ = 0` is an in-domain slider value AND
**BIT-IDENTICAL to the compensator not existing** — MEASURED, not argued (`test_missile.jl`) ⇒ KNOB by
atmosphere.jl's discriminator, exactly as slice 26 concluded for R; `LIVE_FIDELITY_MODES` UNTOUCHED.
Slice 26's `radome_view` marker is INHERITED unchanged — **third slice in this family (16, 26, 27)
whose lesson is a slider with no button at all.** Class **4a** (2 randn/tick, compensator or not —
the feed-forward is arithmetic on state that already exists; THIRD consecutive RNG-live slice, the
seed load-bearing, draw-count identity ASSERTED not assumed). **RUNG-GATED on the LIVE `:airframe`**,
never on `haskey(:att_q)` (the slice-21 `_atm_on` / slice-23 stale-readout / slice-26 latent-bug
class, 4th occurrence); ⚠ and **NOT gated on the radome's own key** — compensating for glass you do
not have is a REAL configuration (residual = −R̂ ⇒ it de-tunes), not a no-op. New `frames.jl` kernel
`radome_compensation`; new loader key `seeker.radome_slope_est` (validated FINITE only — a WRONG-SIGN
estimate is legitimate and instructive, and bounding the key would bound the lesson); telemetry
`radome_slope_est` / **`radome_residual`** (⭐ the deciding quantity shipped as a NUMBER so the client
never subtracts — convention 13, the slice-21 `rho_air` precedent) / `radome_ff_el`.

⚠ **NOT zero client code (advisor): one HUD line, because a student who drags R̂ and watches the ring
die with R̂ nowhere on screen has been shown nothing** — slice 26 ate the "a proof you cannot read is
not a proof" defect once already. The HUD is a **SWITCH on `radome_residual`**, so a slice-26 wire is
untouched; keying off `radome_view` instead would print a residual of 0.000 on every slice-26 wire,
which is not cosmetic but WRONG (slice 26 has no compensator, so its residual IS its bare slope).

⭐⭐ **AND THE SHOT HARNESS CAUGHT A REAL DEFECT — convention 14's 4th proof earning its keep.** The
first slice-27 shot rendered **"RADOME COMPENSATED — loop STABLE" on the RINGING arm**, doubly wrong:
the verdict keyed off the INSTANTANEOUS `|q| > 0.5` and **a limit cycle crosses zero twice per cycle**,
so the capture landed mid-swing at q = −0.301 (peak 1.47); and the shipped wire OPENS with R̂ = 0, a
compensator that BELIEVES NOTHING, so "compensated" named a cure the arm did not have. Slice 26 has
the same structure and merely got lucky with its capture instant. FIXED with a **display-only
PEAK-HOLD** on |q| (an instrument, not physics — it computes no threshold from R, R̂ or N, since
|R_crit| moves with N and ρ and a client-side stability test would be physics in GDScript AND wrong
the moment a scenario changes N) plus a **three-state label**, both gated on the slice-27 key so slice
26's label path is byte-identical. ⚠ **A second methodological defect, caught by the VERIFIER itself:**
its first de-tune assert compared the two arms' FRAME-sampled CPAs and failed (3.305 ringing vs 5.269
cured). That comparison measures the frame grid, not the physics — at emit_every 16 and ~700 m/s the
grid is ~11 m wide and **a HIT samples COARSELY** ([[ewsim-missile-verifier-sampling]]). The assert is
now ONE-SIDED (the miss must not open into de-tune territory, 18.8 m being the measured signature);
the per-tick comparison lives in `test_missile.jl` where per-tick sampling is available.

Four proofs green. `slice27_verify.gd` → **`S27V OK`** (FIVE phases: **RINGING** rms 0.76836 with the
residual exactly −0.1000 and defl_sat 0/495, ceiling 329.84; **REPLAY** posdiff **0.0**; **CURED**
rms 0.01404 = **54.7×** with the residual exactly 0 and the feed-forward live (max 0.00439 rad/s);
⭐ **MARGIN** — R̂ HELD at −0.10 while the glass degrades to −0.20 puts the residual back at exactly
−0.1000 and **the loop RINGS AGAIN (0.81604)**: the boundary MOVED, it did not vanish; ⭐⭐ **DIAGONAL**
— R = R̂ = −0.15 (glass 1.5× worse than shipped, perfectly known, and the R̂ slider's declared FLOOR, so
this phase MEASURES a domain endpoint) is **QUIET at 0.01300** with the residual 0). `slice27_ui_test.gd`
→ **`S27UI OK`** (the slice-26 MIRROR asserted BOTH ways — 26 and 27 are indistinguishable by ROUTING,
so the HUD must be a SWITCH on the compensator's own key — plus TWO sliders both driving set_param with
NOTHING sending set_fidelity, the five disqualified levers asserted ABSENT, and a **NINE-WAY** value
guard where 16-vs-27 is asserted on BOTH mode and visibility so the three button-dropping branches
cannot collapse). `Sandbox.tscn` smoke-load → **`EWSIM_SERVER_DONE`**. TWO windowed shots at the SAME
range (~3.65 km): **"RADOME LOOP — RINGING, NO comp"** (residual −0.100 orange, a_cmd 587, track_gap
456, omega_ratio 4.60, aero_sat 1) vs **"RADOME COMPENSATED — loop STABLE"** (residual −0.000 green,
a_cmd 35.5, track_gap 19.5, omega_ratio 1.24, aero_sat 0, ff −1.4e-3). **Slices 1–26 byte-identical,
proven ON THE WIRE** — the 25/26 verifiers re-run reproduce their STATUS numbers TO THE DIGIT
(2000.044 / 1.373 / 1456.5× / 40.925 m; 0.80408 / 0.03493 / 23.0× / mirror 59.2× / posdiff 0.0).

Run: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice27_radome_comp.yaml`, then the
console Godot `--headless --path clients/godot --script res://net/slice27_verify.gd` (exit 0 = pass).
The UI test needs NO server: `… res://net/slice27_ui_test.gd`. Live: drag **R̂ DOWN** from 0 and the
ring dies between −0.05 and −0.055; then drag **R** down past −0.145 and it comes back.
DEFERRED (NAMED): **THE ANGLE-DOMAIN CORRECTOR** (built and measured at gate 0, not shipped — its
failure mode, a correction signal corrupted by what it corrects, is a general principle and could
carry its own slice on worse glass); **AN IMPERFECT GYRO** (noise, bias, scale-factor error — this
slice's gyro is PERFECT, a §1 approximation; a scale-factor error is exactly a multiplicative error on
R̂, i.e. it lands back on the residual, which makes it a cheap and well-motivated successor);
**ESTIMATING R̂ IN FLIGHT** (the adaptive answer — ⚠ slice 26's P7A is a REAL obstacle: the parasitic
gain is NOT identifiable in closed loop, so such a slice must first answer *what excites the
estimate?*); **a look-angle-dependent `R(look)`** (slice 26's, and it composes sharply: against a
wiggly real slope curve a CONSTANT R̂ is wrong almost everywhere, so the residual becomes a function of
the geometry); seeker FOV / gimbal limit; monopulse / az×el CFAR; a measured `Vc`; the 3-D `:raw` arm;
the out-of-plane MANEUVERING target.

---

## Slice 28 — R(look) — THE SLOPE CURVE AND THE BAND THE ENGAGEMENT VISITS

**Slice 28 — `R(look)`: THE SLOPE CURVE, AND THE BAND THE ENGAGEMENT VISITS (HANDOFF §11 Tier-A)** —
the SIXTH slice of the bank-to-turn / 3-D arc, and a deferral BOTH slice 26 and slice 27 named ("a
look-angle-dependent slope `R(look)` — it composes sharply: against a wiggly real slope curve a
CONSTANT `R̂` is wrong almost everywhere, so the residual becomes a function of the geometry").
**COMPLETE & green (5013 tests).**

Slice 26 built the disease (a constant error slope `R` closes a parasitic loop). Slice 27 built the
cure and measured its limit (a scalar `R̂` cancels to the accuracy of the belief; the residual `R − R̂`
sets the boundary). **BOTH ASSUMED THE GLASS HAS ONE SLOPE. It does not** — a radome's error slope is
a CURVE in look angle, because the ray passes through different glass at different look angles.
**THE LESSON, one sentence: the parasitic loop is closed by that curve's LOCAL DERIVATIVE at the look
angle the engagement actually holds, and which look angle that is belongs to the ENGAGEMENT rather
than to the radome — so slice 27's "know your slope" sharpens into "KNOW YOUR SLOPE CURVE OVER THE
LOOK-ANGLE BAND THE ENGAGEMENT VISITS", and characterizing at BORESIGHT is the natural AND DANGEROUS
choice.** ⚠ Slice 26's language and its prohibitions are INHERITED WHOLE (slice 20's "degenerative
spiral" stays forbidden here; slice 26's stays forbidden elsewhere). **Slice 28 adds NO new
instability and NO new cap: it makes the loop gain a FUNCTION OF THE FLIGHT CONDITION**, exactly as
slice 20 made the aero ceiling self-lowering without adding a cap.

⭐⭐ **THE WHOLE SLICE IS ONE PAIR OF NUMBERS THE CORE SHIPS, AND SLICE 27 COULD NOT HAVE WRITTEN IT
— it had only one of the two keys, because it had only one slope.** On the shipped wire the HARDWARE
residual `radome_residual` = `R₀ − R̂` is **EXACTLY 0.000** — the compensator's belief matches the glass
it was characterized against, perfectly — **and the missile RINGS**, because the ENGAGEMENT residual
`radome_residual_az` = `R(look_az) − R̂` runs **−0.100 to −0.052** across the measurement band. Drag R̂
to −0.13 and **the two numbers TRADE PLACES** (hardware **+0.100**, engagement **0.000**) and the body
goes quiet. That mirrored pair is the verifier's centrepiece, both HUD lines, and both shots.

⚠⚠ **THE WIRE CHANGES, AND THE MEASUREMENT IS THE REASON — the first slice of this arc to break the
shared STATIC `Y = 2000` geometry 23/24/25/26/27 all held.** Against a static target the collision
course carries ZERO LEAD, so the look angle decays to ~0 and the whole endgame sits at ONE point
(MEASURED on a STABLE arm — a ringing arm's look angle swings BECAUSE it is ringing — range-gated at
r > 500 m: |look| runs **0.04° → 0.54°** over the last half). `R(look)` would be a **DEAD KNOB** there.
A CROSSING target (`vel = [0, 200, 0]`) holds a SUSTAINED LEAD and the seeker looks ~15° off boresight
for the whole flight (median 14.8°, peak 22.4°). ⚠ The lead is almost entirely in AZIMUTH
(`look_el` within ±0.5°), which is load-bearing twice below.

⭐⭐ **THE ISOLATION IS A NON-MONOTONE RESPONSE TO A MONOTONE GEOMETRY CHANGE, and it defeats a REAL
confound (advisor, at gate 0).** "Static is quiet, crossing rings" changes the operating LOOK ANGLE
*and* the whole ENGAGEMENT, and the second one moves the loop ON ITS OWN: **with no curve anywhere**,
the constant-`R` onset is `|R_crit| ≈ 0.065` crossing against `≈ 0.05` static — a ~30% shift from
geometry alone. ⇒ **HOLD THE GLASS, SWEEP THE ENGAGEMENT.** With `k = 12` the ripple peaks at 15° and
returns to `R₀` at 30°, so a monotone crossing-speed sweep goes **QUIET → RING → QUIET** (`rms r`
0.016 / 1.042 / 0.011 at vy = 0 / 200 / 400) while the no-ripple CONTROL is **flat quiet at every
speed** (0.016 / 0.014 / 0.011, max/min < 2×). **A confound cannot produce a non-monotone response to
a monotone change.** ⚠ Past vy ≈ 400 the closing speed — and with it the PN loop gain — collapses and
even a ringing CONTROL goes quiet; that bound is measured, and arms above it are not ripple physics.

⭐ **WHAT LICENSES THE SLICE AT ALL: THE LOOP TRACKS THE DERIVATIVE, NOT THE BEND.** Under slice 26's
LINEAR model those are the same number, which is exactly why 26 could not tell them apart. The
matched triple, on the shipped kernel: RIPPLE **1.064 rings**, a CONSTANT slope matched to the
**SECANT** (−0.05) **0.016 quiet**, a CONSTANT matched to the **DERIVATIVE** (−0.10) **0.838 rings**.
Same bend at the operating point, opposite behaviour ⇒ **a radome INSIDE ITS BORESIGHT-ERROR SPEC
EVERYWHERE can still ring, because specs are written on `ε` and stability on `dε/dlook`.** ⚠ Measured
at `R₀ = 0` rather than on the shipped wire, DELIBERATELY: there the secant is ≈ −0.079, already past
`|R_crit| ≈ 0.065`, so BOTH linear arms would ring and the A/B would prove nothing — the trap that
spoiled two gate-0 runs.

⚠⚠ **TWO PROOFS THE PLAN LISTED FOR THE VERIFIER LIVE IN `test_missile.jl` INSTEAD, AND NEITHER WAS
DROPPED — NEITHER IS CLIENT-DRIVABLE** (advisor; the slice-27 precedent — its α_max isolation lives
there because α_max is deliberately not a knob): the target's VELOCITY is not a comp key, so the
geometry sweep cannot be reached by `set_param`, and `radome_slope` is not a slice-28 knob, so neither
can the matched-secant triple. Both are stated as relocations in the verifier's own header.

⚠ **THE METRIC IS `rms r` (YAW) — A DELIBERATE DEPARTURE FROM 26/27's `rms q`, not "the arc's metric,
continued".** The reason is measured: the lead is in AZIMUTH, so the ring is in yaw.
⭐ **AND THE PITCH CHANNEL BESIDE IT IS THE SECOND ISOLATION — THE CHANNEL SPLIT.** The two seeker
channels sit at DIFFERENT POINTS ON THE SAME GLASS: `R(look_az)` runs −0.130…−0.082 while
`R(look_el)` is pinned at `R₀` = −0.030, giving `rms r` **1.042** against `rms q` **0.101**. **A
CONSTANT SLOPE CANNOT PRODUCE THIS** — it gives both channels one gain and rings them together
(measured in the same triple: the matched-DERIVATIVE arm rings 0.838 yaw WITH 0.844 pitch). One
radome, two channels, two operating points.
⚠ **THE WINDOW IS A RANGE BAND `[500, 3000] m`, NOT A TICK FRACTION, and every number is quoted with
it.** Two defects it fixes, both of which would otherwise have entered as physics: on a crossing wire
`rms r` carries a LEGITIMATE front-loaded baseline (the turn onto the collision course — **0.172** over
the whole approach against **0.0138** in the band), and arms with different ToF would otherwise compare
DIFFERENT PARTS of the engagement. ⭐ The metric is FRAME-ROBUST (per-tick 1.04174 vs frame 1.04145).
⚠ rms, NEVER the peak. ⚠ **THE MISS IS NOT THE METRIC** — every arm still HITS (0.15–1.8 m per-tick).

⭐ **THE CURVE FORM IS A BOUNDED SLOPE RIPPLE, AND THE CUBIC WAS KILLED AT GATE 0.**
`R(look) = R₀ + A·(1 − cos(k·look))`, bounded to `[R₀, R₀+2A]`, with `ε` its EXACT integral (an
identity finite-differenced as a gate-1 tooth). A cubic `ε = R₀·look + C·look³` has an UNBOUNDED
slope: the amplitude that puts the off-axis slope past critical also makes the bend diverge (miss
2550 / 3531 / 4158 m at `C ≤ −0.2`, and the metric FALLS with |C|), with onset and breakdown too close
for a knob domain — the small-angle model carrying the lesson exactly where it is invalid, which is
the objection slice 27 used to REJECT `R = −0.30`. The bound is not merely respected but **REACHED**
on the wire: at the A floor the local slope measures **−0.23000** against `R₀ + 2A` = −0.230.

**TWO KNOBS, and convention 9 is satisfied by a MEASUREMENT: they are the two halves of ONE quantity**
— the engagement residual, which the core ships as `radome_residual_az`. **`radome_ripple` (A)** ∈
[−0.10, 0]: onset between −0.025 (0.0142, quiet) and −0.03 (0.821, rings), then a PLATEAU (1.002 /
1.042 / 1.085 / 1.093 at −0.04 / −0.05 / −0.08 / −0.10); the floor is where the plateau is established
with ~1.5× margin to the point where the miss starts growing (2.1 / 3.6 / 4.4 m at −0.15 / −0.20 /
−0.30) — a measured plateau, NOT a physical wall, and it is stated that way. ⭐ The model-validity
budget holds across the ENTIRE range: **0.0% of in-band frames past a 30° look angle** (the k = 8.2 /
vy = 300 wire blew it — 5.3% at A = −0.06, 17.1% at −0.10 — and would have bounded the domain).
**`radome_slope_est` (R̂)** ∈ [−0.15, 0] is slice 27's, inherited: the ring dies between −0.07 (0.564,
marginal) and −0.08 (0.0123, quiet), an engagement residual of ≈ −0.055, so the crossing sits at ~50%
of travel; the floor comfortably contains **R(15°) = −0.13**, the ENGAGEMENT-CORRECT characterization,
and beyond it the de-tune face is gentle (0.026 at −0.20, 0.042 at −0.25) ⇒ the floor is UI FRAMING and
says so. ⚠ **`radome_ripple_k` is AUTHORED and DISQUALIFIED BY NON-MONOTONICITY** (quiet / rings /
rings / marginal / **quiet** / rings at k = 4 / 6 / 8.2 / 12 / 16 / 24, because `k` decides WHERE ON
THE WIGGLE the operating look angle lands — [[ewsim-df-ellipse-sigma-monotonicity]], the 4th
occurrence after slices 19 and 22); it is also WHY `k = 12` was chosen — it is the value that puts a
quiet zone inside the valid speed band, which is what makes the isolation above possible at all.
`n_pn`, `rho`, `af_alpha_max`, `sigma_seek`, `speed` DISQUALIFIED as in 26/27 and asserted ABSENT in
both gates.

**KNOB, not rung** — `A = 0` is bit-identical to the ripple key not existing (MEASURED, not argued:
atmosphere.jl's discriminator, slice 26's `R = 0` precedent). ⚠ **TWO DISTINCT IDENTITIES HOLD HERE AND
THEY ARE NOT THE SAME CLAIM (advisor).** (1) **KEY ABSENT ⇒ the VERBATIM SEAM**: the seam branches on
key presence and the else-arm calls `radome_error` itself — never the curve kernel at amplitude 0,
because `x + 0.0` is not the identity at `x = −0.0` and float addition is not associative. That is what
keeps a slice-26/27 wire byte-identical, and it is pinned in `test_missile.jl`. (2) **THE SLIDER AT 0 ⇒
the KERNEL REDUCTION**: the shipped scenario AUTHORS the key, so dragging A to its top endpoint still
routes through `radome_error_curve(R, 0.0, k, ·)` — which is pinned bit-for-bit EQUAL to `radome_error`
in `test_frames.jl`. The verifier's FLAT phase exercises (2), not (1); both are tested, and conflating
them would let a later refactor drop one while the other kept passing. **The button stays DROPPED — the FOURTH slice in this family (16, 26, 27, 28) whose
lesson is sliders with no button at all.** Class **4a** (2 randn/tick, curve or not — arithmetic on
state that already exists; FOURTH consecutive RNG-live slice, the seed load-bearing, draw-count
identity ASSERTED not assumed). **RUNG-GATED on the LIVE `:airframe`**, never on `haskey(:att_q)` (the
slice-21 `_atm_on` / 23 / 26 / 27 latent-bug class, 5th occurrence). New `frames.jl` kernels
`radome_slope_curve` / `radome_error_curve`; new loader keys `seeker.radome_ripple` (presence mints
the key; authored WITHOUT `radome_slope` is a LOAD ERROR — a ripple is a variation OF a boresight
slope) and `seeker.radome_ripple_k` (validated finite and > 0 at load, floored positive at the
consumer — `ripple/k` at `k = 0` divides); telemetry `radome_ripple` / **`radome_slope_az`** /
**`radome_slope_el`** / **`radome_residual_az`**, all ADDED beside 26/27's keys, none redefined.
⚠ **PER AXIS, AND THAT IS NOT A DETAIL (advisor, the gate-2 hardening):** an earlier draft shipped ONE
key evaluated at the TOTAL off-boresight angle `hypot(look_az, look_el)` — a THIRD quantity that is
the gain of NEITHER channel, agreeing numerically only because this wire holds `look_el ≈ 0`, and it
would have reached the HUD and the shots as the wrong number.

⚠ **NOT zero client code: three HUD lines and TWO instrument switches.** A student who drags A while
the quantity that moved is invisible has been shown nothing (slice 27 ate that defect once). The HUD
is a **THREE-WAY SWITCH** checked most-specific first (28 → `radome_slope_az`; 27 → `radome_residual`;
26 → neither), so 26/27 render byte-identically; a careless `or` would print slice 27's single
"RESIDUAL R − R̂" on a slice-28 wire, and on this wire that number is EXACTLY 0.000 while the missile
rings — the one quantity a student must NOT read as the thing closing the loop. ⭐ **AND BOTH
INSTRUMENTS FOLLOW THE RINGING CHANNEL**: the rate line and slice 27's peak-hold verdict read
`omega_r` here and keep reading `omega_q` on 26/27 — a peak-hold left on pitch would meter the QUIET
channel and label a shaking missile STABLE. The UI test proves both switches by feeding a slice-27 and
a slice-28 wire the IDENTICAL rates (yaw 1.21, pitch 0.02) and asserting OPPOSITE verdicts.
⚠ **The first shot ran two of the new lines off the right edge** ("…← this closes t|" — the clipped
words being exactly which residual matters): at 15 px from `vp.x − 430` about 55 characters fit, and
the widths are now measured rather than guessed (slice 26 ate the same defect on its 20 px headline).

⚠ **A NAMED APPROXIMATION, STATED NOT SWEPT: slice 26/27's `N·|R − R̂|/ρ ≈ 0.38` IS NOT GEOMETRY-FREE.**
The constant-`R` onset measures `≈ 0.52` on this crossing wire, with no curve involved at all. What
transfers is the **FORM** of the law — a threshold on `N·|R(look) − R̂|/ρ` — not the number. That is a
finding, not an embarrassment, and it does NOT weaken the isolation above (whose controls hold the
geometry's contribution fixed by construction).

Four proofs green. `slice28_verify.gd` → **`S28V OK`** (FIVE phases: **RINGING** `rms r` **1.04145**
with `rms q` 0.10057, the hardware residual EXACTLY [0.000000, 0.000000], the engagement residual
[−0.100, −0.0517], `R(look_az)` [−0.130, −0.0817] against `R(look_el)` [−0.031, −0.030], look_max
22.4°, defl_sat **0/270**, ceiling 321.33; **REPLAY** posdiff **0.0**; **FLAT** A → 0 quiet at
**0.01445** (**72.1×**) with BOTH channel gains collapsed onto exactly −0.030 and the engagement
residual exactly 0; ⭐⭐ **CURED** R̂ → −0.13 quiet at **0.01290** (**80.7×**) with the hardware residual
exactly **+0.100**, the engagement residual [0.00012, 0.00104] and the glass UNCHANGED (`R(look_az)`
never flatter than −0.1290); ⭐ **DOMAIN** A → −0.10, the declared floor, rings at **1.09301** with the
local slope REACHING the exact bound **−0.23000** and the look budget still holding at 24.2°).
`slice28_ui_test.gd` → **`S28UI OK`** (the THREE-WAY HUD mirror asserted on all three wires, the
CHANNEL switch proven with identical telemetry, TWO sliders both driving set_param with NOTHING
sending set_fidelity, six disqualified levers asserted ABSENT, and a **TEN-WAY** value guard —
16 / 18 / 19 / 21 / 23 / 24 / 25 / 26 / 27 / 28 — with 16-vs-28 asserted on BOTH mode and visibility so
the four button-dropping branches cannot collapse). `Sandbox.tscn` smoke-load → **`EWSIM_SERVER_DONE`**.
TWO windowed shots at the SAME range (1444 m vs 1480 m, stepped to a RANGE rather than a tick count
because the two arms have different ToF): **"RADOME SLOPE CURVE — RINGING in YAW"** (yaw rate −0.799
← RINGING, R₀ −0.030 / R̂ −0.030 / hardware residual +0.000, yaw channel −0.096 vs pitch −0.030,
ENGAGEMENT RESIDUAL −0.066 in orange) vs **"SLOPE CURVE — R̂ matched, loop STABLE"** (yaw rate +0.002,
R̂ −0.130 / hardware residual +0.100, yaw channel −0.130 vs pitch −0.030, ENGAGEMENT RESIDUAL −0.000 in
green). **Slices 1–27 byte-identical, proven ON THE WIRE** — the 25/26/27 verifiers re-run reproduce
their STATUS numbers TO THE DIGIT, every phase re-read rather than just the headline (slice 26: 0.80408 /
max|ε| 0.01243 / QUIET 0.03493 = 23.0× / MIRROR 59.2× / posdiff 0.0; slice 27: RINGING 0.76836 / CURED
0.01404 = 54.7× / MARGIN 0.81604 / DIAGONAL 0.01300 / posdiff 0.0; slice 25: `omega_oop` exactly 0.0).

Run: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice28_radome_curve.yaml`, then the
console Godot `--headless --path clients/godot --script res://net/slice28_verify.gd` (exit 0 = pass).
The UI test needs NO server: `… res://net/slice28_ui_test.gd`. Live: the wire OPENS ON THE DISEASE —
drag **R̂ DOWN** from −0.03 and the ring dies between −0.07 and −0.08; or drag **A UP** to 0 and watch
the two channel gains collapse onto one number.
DEFERRED (NAMED): **LOOK-ANGLE-SCHEDULED `R̂(look)` — the engineering answer to this slice, exactly as
27 was to 26** (its single-point version is already measured here: a scalar tuned to `R(look_op)`
quiets the wire; ⚠ it inherits slice 26's P7A obstacle if the schedule is to be LEARNED rather than
authored); **a 2-D slope `R(look_az, look_el)`** (this slice applies ONE scalar curve per axis — real
glass varies over the aperture in two dimensions); **an ASYMMETRIC error curve** (`ε` here is ODD, a
symmetric radome; a manufacturing asymmetry makes the crossing DIRECTION matter); an IMPERFECT GYRO
and ESTIMATING `R̂` IN FLIGHT (both still open from slice 27, unchanged); **seeker FOV / gimbal limit**
(sharper here than ever — this slice makes the look angle the quantity the whole lesson turns on, and
a real seeker cannot hold 30° indefinitely); the out-of-plane MANEUVERING target (slice 24 route (b) —
it would sweep the look angle through the curve FASTER).

---

## Slice 29 — R-hat(look) — THE SCHEDULE THAT LOOKS THROUGH ITS OWN RADOME

**Slice 29 — `R̂(look)`: THE SCHEDULE THAT LOOKS THROUGH ITS OWN RADOME (HANDOFF §11 Tier-A)** — the
SEVENTH slice of the bank-to-turn / 3-D arc, and the deferral slice 28 named as its own successor
("LOOK-ANGLE-SCHEDULED `R̂(look)` — the engineering answer to this slice, exactly as 27 was to 26").
Slice 27 gave the missile a rate-gyro feed-forward with a SCALAR belief; slice 28 showed the glass has
no single slope, so the belief must be a CURVE. Making it one is three lines — and it raises a
question a scalar never had to answer: **EVALUATED WHERE?** The only look angle a guidance computer
owns is the one it computes from its own measurement, and that measurement is exactly what the radome
bent. **⇒ THE LESSON: what closes the loop is the residual measured at the COMPENSATOR'S OWN INDEX;
the schedule's own slope `R̂' = dR̂/dlook` is the SENSITIVITY that decides what that indexing error
costs; and slice 27's rule — "compensate with a signal that is not itself corrupted by what you are
compensating", the rule that killed its ANGLE-domain corrector — comes back in the RATE domain, the
place slice 27 concluded was safe, because THE IMMUNITY WAS NEVER THE DOMAIN, IT WAS THE CONSTANCY
(a scalar has `R̂' ≡ 0`).**

⭐⭐ **THE WHOLE SLICE IS TWO NUMBERS THE CORE SHIPS FROM THE SAME FRAMES, AND THEY DISAGREE.**
`radome_model_err_az = R(look_az) − R̂(look_az)` is the BENCH number — belief against glass at the
SAME look angle, what "how good is my schedule?" naturally means. `radome_residual_az` generalizes
slice 28's key to `R(look_az) − R̂(look_az_c)` — the belief where the compensator ACTUALLY EVALUATES
it. On the shipped arm (`k̂ = 10`) the bench number is **0.01394** and the loop residual **0.05210**
(3.7×) and it RINGS at rms `omega_r` 0.63631 in the [500,3000] m band. At `k̂ = 17` the schedule is a
**6.3× WORSE model of the glass** (bench 0.08795) and it stays QUIET (0.01723, 36.9× down), because
at its own index it is wrong by only 0.01200. **The bench ordering and the loop ordering are
REVERSED, and the ring follows the loop.** ⭐ And the cleanest single statement: at `k̂ = 12, Â = A`
the bench error is **EXACTLY 0.000000000** — the belief IS the glass — while the loop residual is
**still 0.02288**, because the belief is evaluated 2.49–2.59° off. *A perfect model evaluated at a
bent index is not a perfect compensator*, and a scalar could never show it.

⚠⚠ **FOUR GATE-0 REFUTATIONS, AND THEY ARE LOAD-BEARING — every future reader will re-propose the
naive slice.** (1) *"A scalar cannot cancel a curve"* is **FALSE here**: on a settled PN collision
course `V_M·sin L = V_T·sin(aspect)` with the LOS direction fixed, so **the lead angle is CONSTANT BY
CONSTRUCTION** and slice 28's wire holds `look_az` to a **0.2° band** (14.9→15.1 at the 5–95
percentiles, measured on a STABLE arm) — a schedule there is observationally a scalar, i.e. FALSE
FIDELITY (the slice-15 `k_δ` / slice-16 refusal class). (2) Opening the band with a maneuvering target
does not license it either: the **BEST POST-HOC SCALAR MATCHES the exact schedule** (1.06 / 0.97 /
1.07 / 1.40× at bands of 0.2 / 10.0 / 14.2 / 16.8°) — ⭐ **because the parasitic loop needs DWELL at a
supercritical residual, and a band the engagement SWEEPS THROUGH is visited briefly everywhere.**
⇒ **the frozen look angle is the ENABLING condition, not an obstacle**, and slice 29 keeps slice 28's
geometry untouched — the first slice of the arc with a measured reason NOT to move the wire. ⚠ Say
"the geometry is inherited, the GLASS is deepened" (`A` −0.05 → −0.15, AUTHORED — it is what gives
the `k̂` tolerance band an interior). (3) ⭐⭐ **THE ENVELOPE FRAMING IS ALSO REFUTED, AND THAT
REFUTATION IS ITSELF A RESULT: THE RADOME STABILITY CONSTRAINT IS ONE-SIDED.** Only a NEGATIVE
residual rings; a positive one merely DE-TUNES (slice 26's own finding, never before used as a design
rule). So a scalar set at or below the most negative slope the glass reaches ANYWHERE in the envelope
is **unconditionally stable across all of it** (measured across crossing speeds 80–260 → sustained
leads 6.1°/9.8°/15.0°/19.1°). ⇒ **GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY**, and slice 27's
"know your slope to within `0.38/(N·ρ)`" is a TWO-SIDED reading of a ONE-SIDED constraint — the rule
is *"know the most NEGATIVE slope your glass reaches over the envelope, and set `R̂` at or below it"*,
a bound to be exceeded rather than an estimate to be matched. ⚠ It is not free: the purchase DE-TUNES
(`ω_ratio` → 0.25, envelope miss 0.20 → 1.08 → 4.15 → 14.14 → **47.23 m** as the slope span goes
0.2→0.6), so the scalar has TWO bounds that close on each other. **That whole claim is
MULTI-ENGAGEMENT and NOT client-drivable** (target velocity is not a comp key — the slice-27/28
precedent), so it is NOT shipped and is the named strongest successor. (4) ⚠ The **residual-RANGE**
mechanism was killed too: evaluated at the OPERATING POINT rather than as a band range, `k̂ = 10` has
residual −0.016 (nearly exact) and RINGS while `k̂ = 16` has −0.057 (past onset) and is QUIET — the
copy-paste false-claim trap, caught before it was written down.

⚠⚠ **AND A FIFTH CATCH, IN THE CENTREPIECE ITSELF (advisor, blocking).** The draft asserted "the
residual stays inside ±0.055 while it rings" and BOTH halves were unmeasured. (a) **A ringing arm's
look band is not the frozen one** — the shipped arm spans **7.4–18.7°** against 14.5–15.0° for the
quiet arms, so any residual quoted as a median THERE describes the ring, not its cause (slice 28 §1's
own rule). (b) **The ≈0.055 onset was inherited from a different configuration** and had to be
re-measured on this wire: a CONSTANT-`R̂` sweep (constant ⇒ `R̂' ≡ 0` ⇒ no index sensitivity ⇒ its
residual is unambiguous) puts it at **≈ −0.056** (the least-compensating QUIET arm, `R̂ = −0.27`,
sustains −0.0556; every arm with less compensation rings). ⇒ **every residual claim that ships is
ONE-SIDED, and the ring/quiet VERDICT is always on `rms r`, never on a residual threshold.** What IS
legitimate on a ringing arm is comparing the bench and loop numbers **to each other**, because both
come from identical frames — and that is the shipped centrepiece. ⚠ The verifier's FIRST run failed
on exactly this at 1.6×: it used a MEAN OF ABSOLUTES, which a ringing arm inflates via its symmetric
excursions through zero; the MEDIAN of the signed series is the operating point and gives 3.7×.

⭐ **THE ALIGNMENT WORRY, RAISED AND REFUTED** (advisor): slice 28 chose `k = 12` so the ripple PEAK
lands on the ~15° lead, i.e. a correctly-specified schedule sits exactly where `R̂' = 0`. Measured and
killed: a perfect schedule is quiet at EVERY `k` from 6 to 20 (0.0101/0.0093/0.0090/0.0093/0.0104/
0.0122/0.0167) even where `R̂'(op)` reaches +2.9.

⚠ **THE TRUTH-INDEX COUNTERFACTUAL IS A GATE-0 MEASUREMENT AND MUST NOT SHIP** — it proves the
mechanism in BOTH directions (`k̂` = 9/10 ring on the bent index and go QUIET on a truth one, 0.829 →
0.026 and 0.637 → 0.009 = 71×; `k̂` = 17/18/19 are QUIET on the bent index and RING on a truth one,
0.017 → 0.627 / 0.019 → 0.767 / 0.021 → 0.794 — **the index error is STABILISING there**, so a
confound cannot produce a sign-reversing response). But a truth-indexed schedule requires the guidance
computer to read the true LOS, which slice 27 established would make the slice fake. It lives in
`M:\claud_projects\temp\slice29\probe9_window.jl`, the slice-26 frozen-geometry precedent.

**GATE 1** — `frames.jl` gains `radome_schedule_slope(ripple_est, k_est, look) = Â·k̂·sin(k̂·look)`
and `radome_compensation_scheduled(...)`, the latter **PER AXIS** (slice 28's gate-2 hardening applied
to the compensator: the azimuth channel's belief at `look_az`, the elevation channel's at `look_el`;
one value at `hypot(...)` is the belief of NEITHER and would agree numerically on exactly this wire).
Teeth: ⭐ **the DERIVATIVE IDENTITY** (finite-difference `radome_slope_curve`, compare to
`radome_schedule_slope` — the sibling of slice 28's integral identity, pinning the two kernels to each
other rather than restating either); ⭐ **the INDEX TOOTH — the #1 SIGN TRAP's 11th occurrence, and it
claimed a victim**: the sign of the index perturbation must FLIP between a `k̂` below the true `k` and
one above, and the first draft asserted BOTH backwards (the shift is in the BELIEF; the residual moves
the other way) — a test at ONE `k̂` passes for a constant-slope compensator and proves nothing; the
SECOND-ORDER pin (at `k̂ = k` the first-order sensitivity vanishes EXACTLY while the actual shift is
`½·R̂''·δ²`, which is why the shipped claim quotes the exact residual and uses `R̂'` only to explain
it); and `ripple_est == 0` reducing to `radome_compensation` **bit-for-bit**, paired with a
does-schedule case and with the control that a CONSTANT belief cannot be shifted by its index at all.

**GATE 2** — the seam branches inside the existing `_comp_on` block on `haskey(:radome_ripple_est)`,
the FOURTH nesting level of the structural byte-identity shape, else-arm VERBATIM. ⚠⚠ **WHICH LOOK
ANGLE EACH KEY USES IS THE SLICE, so it is written into the seam and not left to a reader**: the glass
bends at `look_az` (truth, off `û_tru`), the belief is evaluated at `look_az_c` (bent). Both were
already in scope and the surrounding slice-28 code uses truth throughout, so picking truth for both
would have silently deleted the finding. Telemetry: `radome_model_err_az` (a DIAGNOSTIC, labelled as
one — the slice-26 `omega_ratio` sense), `radome_sched_slope` (**a SENSITIVITY, never "the loop
gain"**), `radome_slope_est_az`/`_el` (per axis), `look_angle_est` beside slice 26's truth
`look_angle` (**the gap between them IS the bend**, pinned against a no-glass control). The `k̂`
tolerance band is measured CONNECTED and ASYMMETRIC — rings at 6/9/10, quiet 11–19, rings at 20/22 —
so unlike slice 28's GLASS `k` it **IS** a knob (do not copy 28's disqualification across; it was
measured on the other side of the comparison). The isolation is **slice 26's shape, not slice 25's**:
`defl_sat == 0` in-window everywhere, but `aero_sat == 0` is IMPOSSIBLE on a ringing arm and is not
asserted (584/4342 ringing vs 0/4360 cured). ⚠ Counting `defl_sat` over the WHOLE FLIGHT fails on
every arm and says nothing — the fin pegs in the launch transient regardless.

**GATE 3** — `scenarios/slice29_radome_schedule.yaml`: slice 28's geometry and crossing target
verbatim; glass `R₀ = −0.03, A = −0.15, k = 12`; belief `R̂₀ = −0.03, Â = −0.15` (level EXACT),
**`k̂ = 10`** (shape 17% low — the showcase OPENS ON THE DISEASE). TWO knobs, `radome_ripple_k_est ∈
[6, 22]` (⚠ the ceiling MOVED off 20, where `rms r` is only 0.447, a marginal edge — slice 26's
post-commit rule) and `radome_ripple_est ∈ [−0.30, 0]`. Four proofs green: **S29V** six phases —
RINGING 0.63631 / REPLAY posdiff **0.0** / CURED 0.00890 (**71.5×**, bench error exactly
0.000000000, loop residual still 0.02288) / INVERSION 0.01723 (**36.9×**, a 6.3× worse model) / LEVEL
`Â = 0` rings at 1.07220 with `radome_sched_slope` **EXACTLY 0** and the bench and loop numbers the
SAME NUMBER / DOMAIN `k̂ = 22` rings at 0.78773 inside the 30° budget (23.9° peak); **S29UI** the
ELEVEN-way value guard + ⭐⭐ **a FOUR-WAY HUD mirror (26/27/28/29 are all indistinguishable BY
ROUTING** — what separates them is a switch on each slice's own telemetry key) + the channel switch
proven on IDENTICAL telemetry; smoke-load `DONE`; TWO windowed shots at the same range (1442 vs
1478 m) — the ringing arm showing MODEL err **−0.049** against LOOP RESID **−0.084**, the quiet arm
MODEL err **−0.092** against LOOP RESID **−0.013**. Class **4a** (FIFTH consecutive RNG-live; draw
count ASSERTED via end-of-run RNG identity); KNOB not rung (`Â = 0` bit-identical to the key absent,
measured); the button stays DROPPED (16/26/27/28/29 — Option-P′'s fifth use). Slices 1–28
byte-identical, proven ON THE WIRE (the 27/28 verifiers re-run to the digit: 0.76836 / 54.7× / 3.305
and 1.04145 / 0.10057 / 80.7×). 5500 tests.

Run: `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice29_radome_schedule.yaml`,
then console Godot `--headless --path clients/godot --script res://net/slice29_verify.gd` (exit 0 =
pass). The UI test needs NO server: `… res://net/slice29_ui_test.gd`. Live: the wire OPENS ON THE
DISEASE — drag **k̂ UP** from 10 and the ring dies at ~11 and stays dead all the way to 19, even
though the schedule is getting STEADILY WORSE as a model of the glass; or drag **Â to 0** and watch
the schedule collapse to slice 27's scalar.
DEFERRED (NAMED): **THE ENVELOPE / ONE-SIDEDNESS SLICE** — "gain scheduling buys performance, not
stability; over-compensate deliberately to the envelope's worst-case slope and pay for it in
`ω_ratio`", fully measured at gate 0 and not shipped because it is multi-engagement. ⚠ **Its enabling
change is small and precedented — a presence-gated `cross_speed_mps` on `ConstantVelocity`, exactly
slice 18's `alt_hold_m` — and it would ALSO retire the constraint that forced slice 28 to relocate two
proofs. The strongest single successor.** Then: ESTIMATING `R̂` IN FLIGHT (⚠ slice 29 SHARPENS slice
26's P7A obstacle — the estimator would have to identify a SHAPE from a signal whose index is bent);
an IMPERFECT GYRO; a 2-D slope `R(look_az, look_el)`; an ASYMMETRIC error curve; **seeker FOV / gimbal
limit** (sharper again — this slice makes the compensator's INDEX first-class, and a gimbal limit
truncates exactly that index); the out-of-plane MANEUVERING target (⚠ it should inherit this slice's
finding about DWELL).

---

## Slice 30 — THE ENVELOPE, AND THE ONE-SIDED CONSTRAINT

**Slice 30 — THE ENVELOPE, AND THE ONE-SIDED CONSTRAINT (HANDOFF §11 Tier-A)** — the EIGHTH slice of
the bank-to-turn / 3-D arc, and the deferral slice 29 named as its own STRONGEST successor. Slice 26
measured — and never used — the fact that the radome constraint is **ONE-SIDED**: only a NEGATIVE
residual closes the parasitic loop, while a POSITIVE one merely de-tunes. Read as a design rule that
is worth more than the whole scheduling apparatus slices 27–29 built. **⇒ THE LESSON: because only a
negative residual rings, stability is UNCONDITIONALLY PURCHASABLE with a SCALAR aimed at the
envelope's worst-case slope — so what a SCHEDULE actually buys is ACCURACY, and the engineering
question stops being "how well do I know my glass?" and becomes "how much navigation ratio am I
willing to pay to stop caring?"** ⭐ **THIS IS THE FIRST SLICE OF THE ARC WHOSE PHYSICS WAS ALREADY
MEASURED BEFORE IT BEGAN** — slice 29's gate 0 produced the result as a REFUTATION of its own first
plan and then could not ship it, because the claim ranges over ENGAGEMENTS and the engagement was not
addressable. **⇒ SLICE 30 ADDS AN AXIS, NOT A MECHANISM: no new instability, no new cap, no new gain.
Slice 20's "degenerative spiral" language stays forbidden here; slice 26's stays forbidden
elsewhere.**

⭐⭐ **THE HEADLINE IS A RING COUNT OVER AN ENVELOPE, NOT A RATIO ON ONE ARM.** Slices 26–29 each flew
ONE engagement, so "the residual" could be spoken of as a number. Here the crossing speed is a SLIDER
(`cross_speed_mps`, the gate-1 `ConstantVelocity` seam — exactly slice 18's `alt_hold_m` in shape),
the ENVELOPE is the worst cell over vy ∈ {0, 80, 130, 200, 260, 320, 400}, and a compensator PASSES
stability iff it rings at ZERO of the seven. **The BORESIGHT-characterized scalar slice 28 shipped —
whose HARDWARE residual against R₀ is EXACTLY 0.000 — rings at 6/7. A scalar aimed at the glass's
worst-case slope (`radome_slope_worst` = `min(R₀, R₀+2A)` = −0.33, READ OFF THE WIRE) rings at 0/7**,
at every glass depth measured (a 3× range of slope span, gate 0). Measured margins on the shipped
wire: smallest RING **0.85462** (2.85× above the 0.30 verdict line), largest quiet under the
worst-case scalar **0.05853** (5.13× below it). ⚠ **A COUNT HAS NO TOLERANCE TO ABSORB NOISE** — gate
2 therefore re-ran all 14 arms at a second seed (6/7 vs 6/7, 0/7 vs 0/7; every cell moved < 0.2%),
and the two MARGINAL cells are teeth in `test_missile.jl`. ⭐ **THE ONE-SIDEDNESS AS A NUMBER**: on
the same glass at the same crossing speed the boresight scalar leaves a NEGATIVE engagement residual
(**−0.193**, rms `ω_r` 1.07180) and the worst-case scalar an over-compensated POSITIVE one (**+0.017**,
rms 0.05853).

⚠ **THE RULE IS SUFFICIENT, NEVER TIGHT, AND THE BRACKET IS MEASURED RATHER THAN ROUNDED.** The
envelope is ALREADY 0/7 at `R̂ = −0.28`, above the rule's −0.33, because the loop needs the residual
to reach the ONSET (≈ −0.055) and not merely to be negative; at `R̂ = −0.24` the envelope's
last-ringing cell (vy = 200) still rings decisively at **0.70899**. ⚠ The true boundary sits between
−0.26 (0.3168 — 1.06× the verdict line, MARGINAL) and −0.27 (0/7), and **a marginal cell is not
asserted** (slice 26's post-commit rule). **Never present −0.33 as a measured threshold.**

⭐⭐ **AND THE BOUND IS NOT FREE — THE SECOND HALF IS THE PRICE, AND THE SCALAR THEREFORE HAS TWO
BOUNDS: STABILITY FROM BELOW, ACCURACY FROM ABOVE.** They close on each other as the glass worsens —
the classical fixed-gain-versus-gain-scheduling argument, made quantitative on a measured plant.
Measured QUIET-TO-QUIET at the shipped engagement with `R̂` re-aimed at each glass's own wire-read aim
point: `ω_ratio` **0.7806 / 0.5647 / 0.4035** at A = −0.10 / −0.15 / −0.20 (**1.93×**), the aim point
itself moving −0.23 → −0.33 → −0.43. ⚠⚠ **THE PRICE IS ASSERTED ON `ω_ratio`, NOT ON THE MISS
(advisor, and it is a REAL defect avoided)**: gate 0's price column (0.213 / 1.075 / 4.150 m) came
from a Julia probe computing a PER-TICK CPA, while the verifier reads FRAMES on an ~11 m grid — the
exact defect slice 27's verifier ate ([[ewsim-missile-verifier-sampling]]: a HIT samples COARSELY).
⚠⚠ **AND `ω_ratio` IS A DE-TUNE MEASURE ONLY ON A QUIET ARM** (on a ringing one it reads 1.5–16 —
the cycle corrupting the reported LOS rate, slice 26: a DIAGNOSTIC, never the mechanism), so every
price arm asserts `rms r` QUIET *before* its `ω_ratio` is read; implemented naively the phase becomes
the ring-vs-quiet comparison the slice forbids and the file would state that rule and violate it.
⭐ **THE ONE PLACE A MISS CARRIES A CLAIM IS THE DOMAIN CORNER, AND IT IS FLOWN AT vy = 0 FOR THAT
REASON** — the de-tune miss is largest where the lead is smallest: at A = −0.20 the over-compensated
floor `R̂ = −0.55` misses by **21.680 m** against **4.242 m** at its own aim point (5.1×, a 17 m gap
that clears the frame grid), still QUIET, `ω_ratio` 0.2396 vs 0.3025. At vy = 200 the same pair is
10.0 vs 0.6 m — INSIDE the sampling error, and asserting it there would measure the emit rate.

⚠ **ToF VARIES ARM TO ARM — THE FIRST WIRE IN THIS ARC WHERE IT DOES** (9.4 s at vy = 0 to 18.3 s at
the domain corner), which is what makes slice 28's fixed RANGE BAND [500, 3000] m load-bearing here
rather than merely inherited, and why every arm asserts it REACHED CPA before its miss is quoted
(`STEPS = 20000`, sized off the slowest arm — an arm that runs out of steps still closing reports its
LAST RANGE as a "miss"). The metric, window and channel are slice 28/29's: **rms r (YAW)**, quoted
with its window, rms never the peak.

⚠ **THE NON-MONOTONE SWEEP SLICE 28 HAD TO RELOCATE IS *NOT* RESHIPPED, AND THAT IS THE HONEST
DELIVERABLE #2.** The constraint IS retired in principle (target velocity is a comp key now), but
slice 28's QUIET→RING→QUIET shape does not reproduce at A = −0.15: the deeper ripple keeps `R(look)`
supercritical across the whole band. The shape belongs to the (A, k) pair, not to the knob ⇒ slice
28's relocated phases STAY in `test_missile.jl`, and the scenario header says so and says why.
**Moving a proof to a slider buys presentation, not evidence.**

THREE KNOBS, and **convention 9 is satisfied by a MEASUREMENT, not by counting sliders**: they are
three terms of ONE quantity — the engagement residual `radome_residual_az` (vy sets the look angle the
engagement holds, A the glass's slope there, R̂ the belief). Over gate 0's full 245-arm grid, of the
**196** arms whose in-flight residual never went supercritical, **196 are quiet and NONE rings**.
⚠⚠ **QUOTE THE 196/196, NOT THE 47/47** — a ringing arm's look band swings BECAUSE it rings, so
"supercritical on a ringing arm" is corroboration and never proof (slice 29's P10a); the quiet
direction has no such circularity. Domains, every endpoint MEASURED: `cross_speed_mps ∈ [0, 400]`
(FLOOR = the DEAD POINT and it is dead exactly — residual **−0.000008**, look 0.63°, R(look) = R₀,
the whole slice has nothing to say there; CEILING = the model-validity budget, read at the SHALLOW
end of the A domain: 38.6% of in-band frames past a 30° look at vy = 450, 100% at 500), `radome_ripple
∈ [−0.20, 0]` (the FLOOR is the CORNER, measured: at −0.25 with R̂ at its top the budget blows to
0.6% — ⚠ at the UNDER-compensated corner, the opposite of what row-wise scans suggested), and
`radome_slope_est ∈ [−0.55, 0]` (contains R₀+2A = −0.43 for the deepest glass with margin, and puts
the de-tune face on show). Class **4a** (SIXTH consecutive RNG-live slice; a velocity pin adds no
draw, identity asserted); **KNOB not rung** on all three (A = 0 bit-identical to the ripple key
absent, slice 28 measured; `cross_speed_mps` equal to the authored `vel_y` bit-identical to the key
absent, gate 1 measured); the button stays DROPPED (16/26/27/28/29/30 — Option-P′'s SIXTH use).

**⚠ NOT ZERO CLIENT CODE, AND THE ONE REQUIRED LINE IS THE AIM POINT SHOWN LIVE BESIDE `R̂`** (advisor
— slice 28 ate exactly this defect once): the glass is a SLIDER, so dragging A MOVES THE RULE'S OWN
TARGET, and without that line a student who deepens the glass silently invalidates the R̂ they already
set. It ships as a NUMBER (`radome_slope_worst`) and is labelled "**or below**", never as a threshold.
⚠⚠ **THE HUD DISCRIMINATOR IS `cross_speed_mps`, NOT `radome_slope_worst`** — gate 2 measured the aim
point as ADDITIVE on every ripple-carrying wire, so slices 28 and 29 grow it too and switching on it
would print an ENGAGEMENT label on wires with no engagement knob. The slice-30 block is a SWITCH ahead
of 29's, and both UI mirrors deliberately CARRY the aim-point key so the wrong discriminator would be
caught. The headline label is THREE-state for the same reason the slice exists: ringing / "AIMED AT
R₀+2A — the SAFE side" / "**QUIET HERE — R̂ above the aim point**" — quiet HERE is not the same claim
as quiet EVERYWHERE.

Four proofs green: **S30V** (31 flights — ENVELOPE 6/7 → 0/7 with margins, TIGHT 0/7 at −0.28 plus
the still-ringing bracket at −0.24, PRICE quiet-to-quiet 1.93× with the aim point read off the wire
per glass depth, DOMAIN corner 21.680 vs 4.242 m, REPLAY posdiff **0.0**, the dead point's residual,
and per-arm isolation: `defl_sat` 0 in-band everywhere, ceiling ~321 ≪ a_max 3000, look ≤ 27° inside
the 30° budget — ⚠ `aero_sat` DOES fire on the ringing arms and is NOT asserted, slice 26's rule);
**S30UI** (the FIVE-WAY HUD mirror + the TWELVE-way value-guard + ⭐ the crossing-speed slider
targeting **tgt1**, the first knob in this arc on something other than the interceptor); the
`Sandbox.tscn` headless smoke-load (`EWSIM_SERVER_DONE`); and TWO windowed shots at the same range
(1441 m vs 1433 m): "ENVELOPE — RINGING at this crossing", yaw rate −1.309, R̂ −0.030 against "AIM AT
−0.330 or below", ENGAGEMENT RESIDUAL −0.299 orange, `ω_ratio` 30.20, `track_gap` 1825 — versus
"AIMED AT R₀+2A — the SAFE side", yaw +0.028, R̂ −0.330 = the aim, RESIDUAL **+0.011 green**,
`ω_ratio` 0.66, `track_gap` 14.4. Slices 1–29 byte-identical, proven ON THE WIRE (the 26/27/28/29
verifiers re-run to the digit: 0.80408 / 23.0× / 59.2×, 0.76836 / 54.7×, 1.04145 / 72.1× / 80.7×,
0.63631 with bench 0.01394 vs loop 0.05210). **5644 tests** (gate 1 +42, gate 2 +75, gate 3 +27).

Run: `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice30_envelope.yaml`, then
console Godot `--headless --path clients/godot --script res://net/slice30_verify.gd` (exit 0 = pass;
it flies 31 arms, so give it a few minutes). The UI test needs NO server: `… res://net/slice30_ui_test.gd`.
Live: the wire OPENS ON THE DISEASE — drag the **crossing speed** across its range and watch the ring
survive every setting except 0; then drag **R̂** down to the HUD's own `R₀+2A` and sweep the crossing
speed again — it is quiet everywhere. Then drag **A** deeper and watch the aim point MOVE OUT FROM
UNDER the R̂ you just set.
DEFERRED (NAMED): an IMPERFECT GYRO (noise / bias / scale-factor — a scale-factor error is
multiplicative on `R̂`, so it lands straight back on the residual; open since slice 27); ESTIMATING
`R̂` IN FLIGHT (still blocked by slice 26's P7A, sharpened by slice 29); a 2-D slope
`R(look_az, look_el)` and an ASYMMETRIC error curve (inherited from slice 28 — an asymmetric curve
would make the crossing DIRECTION matter, which composes directly with this slice's new axis);
**seeker FOV / gimbal limit** (sharper again: this slice's upper domain endpoint is set by the look
angle reaching 30°, which is exactly where a real gimbal would already have stopped); the out-of-plane
MANEUVERING target (slice 24 route (b), and now with a REASON to want it — it is the genuine sweep
that a STEP deliberately is not); the NON-MONOTONE SWEEP as a shipped proof (it needs its own glass,
not this one).

---

## Slice 31 — AN IMPERFECT GYRO — THE MARGIN IS A GYRO BUDGET

**Slice 31 — AN IMPERFECT GYRO: THE MARGIN IS A GYRO BUDGET (HANDOFF §11 Tier-A)** — the NINTH slice
of the bank-to-turn / 3-D arc, and the deferral slices 27, 28, 29 and 30 ALL named as a §1
approximation: their rate gyro is PERFECT. Every compensator 27–30 built multiplies a GYRO READING by
a believed slope and subtracts it; here the reading is `ω̃ = (1+s)·ω + b` (frames.jl `gyro_reading`),
and **the two error terms of ONE sensor land in TWO DIFFERENT CURRENCIES**. A SCALE FACTOR is
common-mode on the product `R̂·ω̃`, so the belief that reaches the loop is EXACTLY `R̂(1+s)` — back onto
slice 26/27's RESIDUAL, moving the STABILITY BOUNDARY, and ONE-SIDED like slice 26/30's constraint. A
BIAS never touches the belief: it injects a constant spurious LOS rate `R̂·b` — **the arc's FIRST
ADDITIVE entry**, where 26–30 are all multiplicative gain errors — which moves the AIM POINT, not the
boundary. **⇒ THE LESSON: slice 30's rule is SUFFICIENT, NEVER TIGHT, and that margin is not slack —
it is a GYRO BUDGET.** Aiming at the glass's worst-case slope tolerates a −21% scale-factor error; a
design "sharpened" to the onset measured on this very wire tolerates almost none and rings on a
realistic 5% one. What the conservatism purchases is INSENSITIVITY TO YOUR OWN SENSOR.

⚠⚠ **THE ADVISOR'S BLOCKING RISK FIRED BEFORE ANY CODE, AND THE SLICE WAS REBUILT AROUND IT.** A
common-mode scale factor is EXACTLY `R̂ → R̂(1+s)`, so the scale-factor half **adds no mechanism by
itself** — it walks a knob slice 27 shipped and slice 30 sweeps. That is this project's FALSE-FIDELITY
class (slice 15's `k_δ` cancellation, slice 16's refused toggle, slice 19's dead `speed` knob), 5th
occurrence in this arc. ⇒ it ships as a **TOOTH, not a headline**: `(R̂, s)` flies the SAME MISSILE as
`(R̂(1+s), perfect gyro)` — MEASURED on the wire at **max|Δpos| 7.76e−10 m** over the flight, with
identical rms r to five decimals. ⚠ Pinned as an `atol`, **NEVER** as bit-identity: `R̂·((1+s)·ω)` and
`(R̂·(1+s))·ω` differ in the last ULPs (gate 0 measured both — two of five wire pairs came out
bit-identical and three did not). What the equivalence CANNOT express is that the error is
MULTIPLICATIVE, so its absolute size is `|R̂|·|s|`, which is why slice 30's aim point becomes
`R_worst/(1+s)` (shipped live as `radome_aim_gyro`). **Slice 31 is therefore a DESIGN-RULE slice, not
a mechanism slice, and the scenario header says so out loud.**

⭐⭐ **THE SHIPPED WIRE OPENS ON THE DISEASE AND THE DESIGN THAT CATCHES IT LOOKS COMPETENT:**
`radome_slope_est = −0.27`, aimed just past the onset measured here with a PERFECT gyro (−0.260),
instead of at slice 30's conservative `radome_slope_worst` = R₀+2A = −0.33 — exactly the "estimate to
be matched" slice 30 warned against — plus `gyro_scale_err = −0.05`, a scale-factor error a cheap MEMS
rate gyro really has. The loop then sees **−0.2565** and rms r is **0.42395** in the [500,3000] m band:
RINGING. ⭐ **AND IT HAS TWO DIFFERENT CURES, ONE SLIDER EACH** — `s → 0` (BUY A BETTER GYRO, 0.03186,
**13.3×**) or `R̂ → radome_aim_gyro = −0.3474` (DESIGN MORE CONSERVATIVELY, 0.05903, **7.2×**) with the
gyro left exactly as it is. ⭐⭐ And cure B's effective belief lands on `radome_slope_worst` **EXACTLY**
(−0.33000 vs −0.33000, asserted): slice 30's rule is not replaced, it is RE-AIMED for the sensor.
The verdict follows the EFFECTIVE belief and nothing else — at a THIRD aim point (−0.30), `s = −0.145`
lands on −0.25650 and RINGS while `s = −0.070` lands on −0.27900 and stays quiet.

⭐⭐ **THE OTHER CURRENCY, AND THE HONEST NARROWING THAT MAKES IT PRECISE.** On slice 30's aim point a
bias NEVER rings across its whole domain, both signs (rms r 0.134 / 0.046 / 0.078 / 0.145 at
b = −0.08 / −0.02 / +0.02 / +0.08 rad/s) with `aero_sat` **0 on every arm**, while the miss moves 7500×
across the reachable range (0.23 → 1735 m) — the verdict never does. ⚠ **BUT "A BIAS NEVER RINGS" WAS
TOO STRONG, AND THE HONESTY CHECK FOUND IT (gate-0 P9/P10):** a bias STEERS the missile, which moves
the LOOK ANGLE, which on CURVED glass moves the ENGAGEMENT residual — **slice 28's mechanism arriving
through the SENSOR**. The curve's extremum sits at `k·look = π ⇒ look = 15°` and this engagement holds
~13.6°, so a NEGATIVE bias walks the seeker UP ONTO THE STEEPEST GLASS. On a MARGINAL design
(R̂ = −0.265, 0.005 past the onset) with a PERFECT gyro, **b = −0.02 RINGS it (0.35210, look 18.7°)
while b = +0.02 does not (0.05114, look 13.1°)** — and the SAME pair leaves −0.28 / −0.30 / −0.33
untouched. ⇒ the precise claim: **a bias has NO STABILITY VERDICT OF ITS OWN — it has no residual to
move — but it can flip a MARGINAL design in either direction.** ⭐⭐ **SO THE MARGIN IS MEASURED TWICE,
IN BOTH CURRENCIES, AND IT IS THE SAME MARGIN.**

⭐ **THE CLAIM ONLY THE BIAS CAN PRODUCE — TWO CURES FOR ONE DISEASE, AND ONLY ONE OF THEM IS FREE:
1.97×.** With the same b = +0.01, curing by DESIGNING DEEPER costs 0.014586 rad/s of true LOS azimuth
rate against cure A's 0.007413 — the injection is `R̂·b`, so the scalar that buys stability buys the
sensor's own bias with it. ⚠⚠ **MEASURED ON `los_azdot_true`, NEVER ON `gyro_inject_az`:** that key is
`R̂·b` and nothing else, so its ratio between two aim points is |R̂_B|/|R̂_A| = 1.29 **by arithmetic** —
and the verifier's FIRST DRAFT asserted exactly that tautology (convention 11's trap) and would have
passed while proving nothing. The new key is a TRUTH diagnostic in the `omega_ratio` sense, closed-form
(`d(atan2(dy,dx))/dt`), pinned against an INDEPENDENT recompute.

⚠⚠ **AND AT REALISTIC GYRO GRADES NEITHER TERM MATTERS — the slice-15 "the lack of effect IS the
lesson" shape (user-ratified), QUANTIFIED.** b = 2.1 °/hr moves rms r by 0.00001; s = −1% moves it by
−0.001; a tactical gyro is ~1–10 °/hr and 0.1–1%. **The compensator's own sensor is NOT the weak link
on slice 30's design** — the conservative aim point buys a budget ~200× looser than the hardware. That
is precisely WHY the pencil-sharpening comparison is the headline: at the TIGHTENED aim point a
realistic 3–5% error is already at the boundary. ⚠ **The knob domains are chosen for VISIBILITY, not
realism, and the scenario file says so.**

⚠ Class **4a** (7th consecutive RNG-live; 2 randn/tick UNCHANGED — both gyro terms are DETERMINISTIC
and add no draw, ASSERTED not assumed). **KNOBS, no rung** — `s = 0` and `b = 0` are in-domain slider
values BIT-IDENTICAL to the keys being absent (measured), so atmosphere.jl's discriminator returns
KNOB and the button stays DROPPED (slice-16 Option-P′, SEVENTH use: 16/26/27/28/29/30/31). THREE knobs
(`gyro_scale_err ∈ [−0.4,+0.4]`, `gyro_bias_z ∈ [−0.08,+0.08]` rad/s, `radome_slope_est ∈ [−0.55,0]`),
convention-9-legal because they are literally the three terms of the product the compensator
subtracts, `R̂·((1+s)·ω + b)` — and the discriminator is MEASURED twice (the equivalence, and the flip
sitting at the same effective belief across four aim points). ⚠ `cross_speed_mps` is DISQUALIFIED and
asserted absent: slice 30's envelope axis is a SECOND lesson. `gyro_bias_y` ships as a supported comp
key but NOT a knob (it drives the ELEVATION channel, ~10× smaller on a crossing wire). The loader
REFUSES a gyro key without `radome_slope_est` — the gyro reaches the compensator and nothing else, so
without one it is a DEAD KNOB (the slice-19 `speed` class; the slice-21/28/29 "refused, not
branch-ordered" precedent). ⚠ `s = −1` (the DEAD GYRO, bit-identical to slice 26's uncompensated
missile) is NOT refused — a legitimate degenerate, and `radome_aim_gyro` floors its denominator.

**TELEMETRY.** New, all gated on a gyro key: `gyro_scale_err`, `gyro_bias_z`, `radome_slope_est_eff`
(= `R̂(1+s)`, **the belief the LOOP sees** — the line the HUD exists for), `radome_aim_gyro`
(= `R_worst/(1+s)`), `radome_residual_az_eff`, `gyro_inject_az` and `los_azdot_true`. ⚠⚠ **Slice 27/28's
`radome_residual` / `radome_residual_az` KEEP THEIR MEANING (advisor)** — slice 28's headline IS that
the hardware residual reads exactly 0.000 while the missile rings, so folding the gyro into that key
would make its meaning depend on which keys happen to be present. The gyro-effective residual ships
ALONGSIDE, and the two DISAGREE by exactly `−R̂·s` (asserted).

⚠ **THE CLIENT IS NOT ZERO CODE, and the shot harness caught a real defect in it** (convention 14's
4th proof earning its keep): the three-state headline first compared the EFFECTIVE belief `R̂(1+s)`
against `radome_aim_gyro` = `R_worst/(1+s)` — **two quantities on opposite sides of the (1+s) factor**.
The HUD line tells the student where to put the SLIDER; the VERDICT is about what the LOOP sees. Mixing
them labelled a correctly-aimed missile "the gyro eats the margin". Nothing headless can catch it —
`_draw` never runs there. ⚠ A SECOND shot defect: `_range()` can read a STALE frame, so the harness
sailed past CPA and captured the target BEHIND the missile (range opening, look 158°); fixed with a
hard tick cap beside the range gate. The HUD is a **SIX-WAY SWITCH** (31/30/29/28/27/26) on each
slice's own telemetry key, and the slice-30 mirror in the UI test deliberately carries BOTH
`radome_slope_worst` and `cross_speed_mps` so a branch switched on either would be caught.

⚠⚠ **THE GATE-3 TRAP THAT COST THE MOST WAS ARITHMETIC, NOT PHYSICS: `STEPS` MUST BE A MULTIPLE OF
`emit_every`.** The server emits every 16th tick, so with `STEPS = 15000` the last frame it ever sends
is `t = 14.992` while the verifier waits for `t ≥ 15.000` — the run hangs SILENTLY, with no output, to
`MAX_SECONDS`, and reads exactly like a slow wire (Godot's stdout is also block-buffered into a file
or pipe, which hides per-arm progress and reinforces the wrong story). It was misdiagnosed twice
before measurement settled it: the CORE runs 27k ticks/s here (1.26× slice 30's; the slice-31 seam +
telemetry account for 1.44×), a MINIMAL client drains the same server at ~5000 ticks/s on BOTH wires
(5063 vs 4975), and the verifier itself reaches t = 14.40 in **2.89 s**. There was never a slowdown.
`STEPS = 12800 = 16 × 800`; slice 30's 20000 = 16 × 1250 lands exactly, which is why it never showed.

Four proofs green: **S31V OK** (17 arms — DISEASE / REPLAY / CURE A / CURE B / EQUIV / SAME-EFFECTIVE
×2 / BIAS ×4 / MARGINAL ×2 / PRICE ×4; replay posdiff **0.0**; `defl_sat` 0 and the look angle inside
the 30° budget on every arm; `aero_sat` asserted 0 on the QUIET bias/price arms only, since on a
ringing arm it is expected — slice 26); **S31UI OK** (the SIX-WAY mirror + a THIRTEEN-WAY value guard);
the headless `Sandbox.tscn` smoke-load (server `DONE`, zero script errors); and TWO windowed shots at
the same range with the SAME gyro in both — "GYRO — RINGING: loop sees R̂(1+s)" (yaw rate −0.591,
residual −0.062) against "AIMED PAST THE GYRO — the SAFE side" (+0.020, +0.027). **Slices 1–30
byte-identical, and 26/27/28/29/30's verifiers were ALL re-run against this core and PASS — proven ON
THE WIRE, not read off the diff.** (5798)
Run: `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice31_gyro.yaml`, then console
Godot `--headless --path clients/godot --script res://net/slice31_verify.gd` (exit 0 = pass; 17 arms,
give it a few minutes). The UI test needs NO server: `… res://net/slice31_ui_test.gd`. Live: the wire
OPENS ON THE DISEASE — drag **gyro s** to 0 and the ring dies (cure A), or put it back and drag **R̂**
down to the HUD's own `gyro AIM AT` number and it dies with the bad gyro still fitted (cure B). Then
add **bias** and watch the aim point move while the verdict does not.
DEFERRED (NAMED): a SINGLE IMU — and its mechanism is now MEASURED, not guessed: feeding the same
corrupted rate to the α/β autopilot moves the onset from `s ≤ −0.22` to `s ≤ −0.18` and DESTROYS the
exact `R̂(1+s)` equivalence, because `k_q` supplies ~98% of the plant damping (a DAMPING error, not a
residual one — two mechanisms at once, which convention 9 forbids); GYRO NOISE on DRAW-TOPOLOGY
grounds (convention 3 — an unconditional third `randn` desyncs every 25–30 replay; the slice-13
`:scan` 4b shape) ⚠ and slice 25's ~1000:1 roll-loop low-pass says probe before shipping, it may be
DEAD; PER-AXIS scale factors and gyro MISALIGNMENT (this one is COMMON-MODE, which is exactly why it
collapses onto one number); `gyro_bias_y` as a knob (it wants a geometry whose lead is in ELEVATION);
plus everything 26–30 named — ESTIMATING `R̂` IN FLIGHT (still blocked by slice 26's P7A), a 2-D slope
`R(look_az, look_el)`, an ASYMMETRIC error curve, **seeker FOV / gimbal limit** (sharper again: this
slice's bias domain is bounded by the look angle reaching 30°, exactly where a gimbal would have
stopped), the out-of-plane MANEUVERING target.

---

## Slice 32 — THE SEEKER'S FIELD OF VIEW

**Slice 32 — THE SEEKER'S FIELD OF VIEW: THE ENVELOPE IS SET BY WHAT THE SEEKER CAN SEE (HANDOFF §11
Tier-A)** — the TENTH slice of the bank-to-turn / 3-D arc, and a deferral every one of 26–31 named
and each one sharpened. Those six made the LOOK ANGLE the central quantity of the whole radome family
and then bounded every knob domain by it reaching 30° — declared five times as a §1 MODEL-VALIDITY
caveat. A real seeker makes the same angle a **PHYSICAL STOP**: past its field of view there is no
measurement at all. So the caveat and the hardware coincide, and the arc's **FIRST SENSOR-SIDE CAP**
lands — every previous cap in this project is airframe or actuator (10/12's authored magnitude clamp,
15's jerk and deflection caps, 19's flight-condition lift ceiling, 22's interior peak of the lift
curve).

⭐⭐ **AND WHAT IT CAPS IS THE ENGAGEMENT, NOT THE ACCURACY.** A crossing target must be LED; the lead
is a closed-form property of the collision triangle (`V_m·sin λ = V_t·sin θ`, `frames.jl`
`collision_lead_angle`, shipped live as `lead_angle_deg`); and the missile must hold that lead ALL THE
WAY IN. If the lead exceeds the window the seeker loses the target **while the lead is still
building**, the α-β tracker coasts on a rate that was right for a smaller lead, and the geometry runs
away monotonically.

> **THE LESSON, IN ONE SENTENCE.** The FOV a seeker needs is not a seeker number — it is the
> ENGAGEMENT's own lead angle, so a field of view does not cost you accuracy, it costs you the
> ENVELOPE: the set of targets you may engage at all.

⭐ **TWO CURES, ONE SLIDER EACH, AND THE ASYMMETRY IS THE PAYLOAD**: widen the seeker 25° → 30° and
the engagement is KEPT (free); slow the crossing 400 → 320 m/s and the engagement is DECLINED (not
free).

**THE SEAM** — `_observe_point3d!`, a branch AHEAD of the tracker update, rung-gated on the LIVE
`:airframe === :six_dof` (never `haskey(:att_q)` — the slice-21/23/26/27/29 latent-bug class, 6th
occurrence): `in_fov = seeker_in_fov(att, û_tru, deg2rad(fov))` with three tracker branches — NEVER
LOCKED, COASTING (the α-β predict step alone: the angle extrapolates and **the rate is FROZEN**, and
the rate is what PN consumes), and the existing in-window path VERBATIM. ⚠ The window quantity is the
TOTAL off-boresight angle `hypot(look_az, look_el)` — a CIRCULAR window, precisely the quantity the
radome comments correctly warn is the WRONG one for per-axis glass and the RIGHT one here. ⚠ Computed
from the **TRUTH LOS**: whether the target is inside the window is PHYSICS, not an estimate. ⚠ SCOPE:
a **STRAPDOWN** FOV, not a gimbal servo — there is no head state anywhere in this codebase, and a real
gimbal would add a dynamical state AND rewrite 26–31's `look_az` (the bend would key off head-vs-body
rather than LOS-vs-body). Named deferral, written at the seam.

⚠⚠ **THE SIGNATURE IS SLICE 23's AND SLICE 25's AND THE MECHANISM IS NEITHER** (the copy-paste
false-claim trap, 3rd occurrence in this arc): 23's autopilot THREW the out-of-plane command away and
25's seeker NEVER FORMED it, both leaving `max|y| = 0.0` EXACTLY. Here it **WAS formed and flown, and
the sensor stopped supplying it MID-FLIGHT** — the missile turns hard out of plane (`max|y| = 8125 m`)
and only then loses the target. ⭐ And `fov = 0` reaches the 23/25 signature by a **FOURTH route** (a
seeker that never locks reports no LOS rate, so PN commands nothing out of plane) — which is exactly
why **`max|y|` is the discriminating tooth and the ~2000 m miss is not.**

⚠ **THE METRIC IS THE MISS, AND THAT INVERTS 28–31's.** `rms r` must NOT be inherited: losing the
measurement CUTS the parasitic feed, so on a ringing wire a tight FOV would LOWER rms r while OPENING
the miss and the slice would be written backwards. Here the miss opens ~10⁴× and a big miss samples
FAITHFULLY ([[ewsim-missile-verifier-sampling]] cuts the right way for once — the HIT arms are the
coarse ones, so every hit assert is ONE-SIDED). ⚠ The miss MAGNITUDE is not an ordering inside the
broken region (2487 m at fov 20 against 1505 at fov 25 on the same crossing); the VERDICT is asserted
and the miss quoted.

⚠ **ISOLATION: `aero_sat` AND `defl_sat` ARE BOTH 0 in the r ∈ [500, 3000] m band in EVERY arm** ⇒ a
**POINTING** miss, not the arc's ceiling miss (19–24) — a missile with every bit of the authority it
needs and no idea where to point it. The whole-approach figure is ~6.5 % and it is ~6.5 % in the
REFERENCE arm too: a launch transient, the front-loaded baseline 28/31 measured in `rms r` arriving in
a different quantity.

**GATE 0 (5 probes)** settled the shape and KILLED two framings. ⭐ **P3b, the EXTERNAL ANCHOR
(convention 11): the critical FOV EQUALS the collision-triangle lead**, recomputed per tick by a
different algorithm — ratio 0.997–1.006 over vy ∈ [80, 400]. ⚠⚠ **P5 was the advisor's BLOCKING check
and it FIRED**: the 18.12° never-acquires floor is the scenario's authored LAUNCH ATTITUDE, not a
seeker property (it tracks the tick-1 look angle to 0.008° and moves with `elevation_deg`;
minimized-not-zeroed at 12° because the target's launch BEARING is ~18.4° in azimuth). ⭐ The
terminal-lead half is INVARIANT to the same change ⇒ **ONE binding constraint, the "max of two curves"
framing DROPPED**, and the domain floor set ABOVE the cliff so the slider measures the SEEKER. The
second killed framing: **slice 28's "know your slope curve over the BAND the engagement visits" does
NOT transfer** — this engagement holds a FROZEN lead (a 1° band over the whole approach), so the FOV
requirement is a SINGLE number against a SINGLE sustained angle. Importing 28's structure would be
this project's own false-fidelity reflex; the kinship is only that both quantities belong to the
ENGAGEMENT rather than to the hardware.

**GATE 1 (5798 → 5872)** — three kernels in `frames.jl`: `boresight_angle` (the CIRCULAR-window
total), `seeker_in_fov` (the predicate, and the SINGLE site of the `max(fov, 0)` clamp), and
`collision_lead_angle` (`λ = asin(‖v_t × û‖ / V_m)`). ⭐ **THE SEAM CALLS THE KERNEL** — the gate-0
seam computed `hypot(fa, fe) ≤ fov_rad` INLINE, and shipping kernels beside it would have proved a
SECOND implementation and nothing about what flies (convention 14's slice-31 lesson one layer down);
behaviour-preserving PROVEN ON THE WIRE, all four showcase arms reproducing gate 0 to the digit.
⚠⚠ **THE GATE-1 CORRECTION: "180° is the whole sphere" is FALSE** — the angle-space radius
`hypot(az, el)` has supremum `hypot(π, π/2) ≈ 201.246°`, so a `fov = π` window genuinely REJECTS a LOS
at `(az, el) = (180°, 20°)` (181.108°). The identity claim is therefore worded **"`seeker_fov_deg =
180` is bit-identical to the key being absent ON THIS WIRE"** — an empirical statement about the look
angles the engagement REACHES, which is exactly the reachable-set reasoning slice 22 used to refute
"the off-state is a limit point ⇒ RUNG". Also measured: the radius is **not** the exact cone half-angle
(`acos(u_body[1])`), overstating by at most **+0.364° at a true 30° cone**, peaking at a ~47° clock
angle — a §1 approximation, named and measured in both directions.

**GATE 2 (5872 → 5985, +113)** — the LOADER and the WIRE. ⚠⚠ **THE ADVISOR'S BLOCKING CATCH, AND IT
WOULD HAVE SHIPPED THE WRONG NUMBER**: the plan said to gate the `look_angle` telemetry on
`_rad_on || _fov_on`, but slice 26's `look_angle` is built from `look_az`/`look_el`, which are the
radome else-arm's **ZEROS** when no glass is authored — and slice 32's showcase has the radome keys
ABSENT BY DESIGN. That edit would have shipped **0.0** on the one wire the whole lesson runs on (the
slice-29 stale-readout class, 7th occurrence). It ships instead from `boresight_angle(att, û_tru)` at
its own site under `_fov_on`, which also makes every 26–31 wire byte-identical BY GATING. ⭐ **AND A
GATE-0 NUMBER WAS CORRECTED: "0.0 %" was a ROUNDING** — the quiet arms leave the window for ONE OR TWO
TICKS at r = 0.1–0.6 m as the LOS unit vector swings through a large angle in the last millisecond
before impact, which `%.1f` hid. Range-gated at **r > 200 m** the quiet arms are **EXACTLY 0.000 %**.
The loader is presence-gated on the key and validated **FINITE ONLY** (no positivity guard —
`seeker_in_fov` is the single clamp site and `fov = 0` is the DEFINED never-locked state, so a bound
would be a fake constraint), and ⚠⚠ **REFUSED WITHOUT `two_angle: true`** (the window is applied in
`_observe_point3d!`, so without that host the key is read by NOTHING — the slice-19 `speed` DEAD-knob
class). It is NOT refused without `:airframe = :six_dof`: that is a LIVE fidelity a student may toggle
mid-run, and 26/27 have the identical inert-without-it shape without refusing it.

**GATE 3 (5990 → 6028)** — `scenarios/slice32_fov.yaml` (seed 32, `STEPS = 16000 = 16 × 1000`, sized
off the slowest arm's 15.313 s). The shipped YAML **reproduces gate 2's programmatic world to the
digit**, which is itself the loader's proof. Frame-sampled, r > 200 m gate, closing leg only:

| arm | miss (m) | out-of-window % | max look° | lead° | max\|y\| | `aero_sat` |
|---|---|---|---|---|---|---|
| **OPEN — fov 25°, vy 400** | **1504.679** | **67.982** | 99.47 | 32.69 | **8125.0** | 0/442 |
| CURE A — fov 30° | 0.480 | 0.000 | 29.01 | 28.89 | 8124.5 | 0/409 |
| CURE B — vy 320 | 1.126 | 0.000 | 23.86 | 23.76 | 6137.5 | 0/332 |
| fov 180 / fov 40 | 0.480 (`===` cure A on the approach) | 0.000 | 29.01 | 28.89 | 8124.5 | 0/409 |
| `fov = 0` — NEVER LOCKED | 4786.388 | 100.000 | — | — | **0.0 EXACTLY** | (no band) |

Break at **t = 4.688 s / r = 4120.1 m**, with the lead still building. Ratios **3134× / 1336×**,
understated because the numerator samples faithfully and the denominator coarsely.

⚠⚠ **TWO GATE-3 CORRECTIONS, BOTH ABOUT *WHERE* A NUMBER IS MEASURED:**

1. **THE 180° IDENTITY IS ON THE CLOSING LEG, AND OVER THE WHOLE RUN IT IS FALSE BY 35.7 m** — the
   verifier's first run FAILED here. Past CPA the target is BEHIND the missile, the LOS swings through
   150–180°, and a 30 or 40 deg window correctly drops it while a 180 deg one does not; the arms
   separate *after* the engagement is over. That is gate 0's own post-CPA LOS flip (it saw 3.5e−9 m on
   a shorter tail). Restricted to the closing leg the identity is **EXACT (0.0 m)** across 30/40/180.
2. ⭐⭐ **A BROKEN ARM'S OWN LEAD IS INFLATED BY THE RUNAWAY IT IS IN — SLICE 29's P10a IN A NEW
   QUANTITY.** At the same 400 m/s crossing the broken arm's in-band median lead reads **32.69°**
   against **28.89°** on the arm that held: once the track breaks, the coasting missile's geometry runs
   away and the "lead the collision triangle demands" becomes a property of the runaway. Every demand
   in the envelope table is therefore read off the arm that **HELD** at that crossing speed, and the
   inflation is itself ASSERTED — a broken arm's lead would have made the predicate partly
   self-fulfilling.

⭐⭐ **THE ENVELOPE AS A PREDICATE — `held ⟺ lead < fov` over six cells, from BOTH directions**:
(20°, 260) lead 19.52 HELD · (20°, 320) lead 23.76 BROKEN · (25°, 320) HELD · (25°, 400) lead 28.89
BROKEN · (30°, 400) HELD · (20°, 400) BROKEN. ⚠ The two quantities come from **different code paths** —
`collision_lead_angle` against `seeker_in_fov`'s verdict on `boresight_angle` — so it is a measurement,
not a restatement. ⚠ And it is NOT the look-angle anchor: that INDEPENDENT recompute (an `acos` of the
LOS·v̂_t dot then `sin`) stays in `test_missile.jl`, or it becomes the self-calibrated round-trip this
project names as a trap.

**Class 4a** — draw-invariant YET trajectory-changing; the **EIGHTH consecutive RNG-live slice**
(25–32), so the seed is load-bearing, conventions 3/11 apply, and the draw-count identity is ASSERTED
(an out-of-window tick DRAWS `n_az`/`n_el` and DISCARDS them — slice 25's own lockstep: the foil
discards, it does not skip). **KNOB, not rung** (the 180° bit-identity, measured on the closing leg).
Knob domains MEASURED: `seeker_fov_deg ∈ [20, 40]` — the FLOOR stated with its reason (the 18.120°
cliff is the LAUNCH ATTITUDE), the CEILING **inert** (30/40/180 are the same flight, which is the
measured reason it stops at 40 rather than 180); `cross_speed_mps ∈ [0, 400]`, slice 30's, INHERITED.
DISQUALIFIED and asserted absent: `n_pn`/`rho` (the guidance loop the lesson is not about), every
`radome_*` (a SECOND mechanism), `sigma_seek` (degrades the lesson beside it), `elevation_deg` (TWICE:
the slice-19 DEAD-knob class AND gate 0's P5 artifact), `af_alpha_max` (the arc's ceiling, held at 0 %
here on purpose).

⚠ **THE CLIENT IS NOT ZERO CODE, and the gap was a MECHANISM the plan never named.** It asserted
"Button DROPPED" and nothing in the tree shipped one. A FOV wire holds `seeker_axes` at az_el, so the
dispatch falls through to slice 25's CYCLER — whose other position (`:pitch_plane`) leaves the WINDOW
LIVE on a missile that ALSO misses by 2000 m for a wholly unrelated reason (two mechanisms in one
view, which convention 9 exists to prevent). ⇒ a NEW core marker **`seeker_fov_view`**
(`_airframe_view_info`, presence-gated on `:seeker_fov_deg`, every 16–31 handshake byte-identical),
slice-16's Option-P′ for the **EIGHTH** time, and the UI test proves it **by mirror**: the same
handshake minus the marker takes the cycler with the button VISIBLE. ⚠ A SEPARATE marker rather than a
reuse of `radome_view` — the two select different HUD branches, and the radome cascade reads keys a FOV
wire does not have (it would print a confident 0.000). ⚠ The drop needs **BOTH sites** (mode entry AND
`_update_fid_btn`) — slice 26's finding, unchanged. ⭐ **`_fov_verdict_label` is a PURE HELPER**
(convention 14, slice 31's lesson), pinned in all THREE states — the middle one, *the lead has passed
the window but the tracker has not dropped yet*, is what a two-way label would hide. ⭐ **`_fov_lost`
is a LATCH where slice 27's peak-hold DECAYS**, and the difference is principled: a limit cycle crosses
zero twice per cycle so its verdict must FORGET, while a track break is a thing that HAPPENED and an
instantaneous `seeker_valid` blinks green when the runaway swings the LOS back through the window.
⚠ RANGE-GATED at r > 200 m so the endgame excursion cannot paint a healthy intercept as a lost track.

⚠⚠ **THE SHOT HARNESS CAUGHT THE WIDTH CLASS TWICE IN THIS ONE SLICE, AND THE SECOND DIAGNOSIS WAS
WRONG BEFORE THE ADVISOR CORRECTED IT.** (a) The HEADLINE was CLIPPED — "TRACK BROKEN — the lead
outgrew the FOV" (39 chars) ran off the right edge at 20 px from `vp.x − 430`, and the clipped word was
*FOV*; budget ~34, all three strings shortened. (b) Then the re-shot pair was **missing the y = 88
CROSS-RANGE line entirely** — this slice's own DISCRIMINATING TOOTH, the number that separates its
mechanism from 23's and 25's — with the y = 132 LEAD line surviving only as *"he requirement"*. That
was first written up as "the shared readout panel overlaps the HUD column, the layout is 26–31's",
which is **FALSE**: the occluders sit at y ≈ 83 and y ≈ 127, ABOVE the readout panel, and they are
**slice 32's OWN KNOB LABELS**, drawn full-width in the UI CanvasLayer which paints over the Node2D
`_draw`. At 172 and 157 characters they were the longest in the arc (slice 30's longest is ~137 and
stops short of the column). ⇒ the budget is **~110 characters** against `vp.x − 430`, both were
shortened to 76/68, and the pair re-shot. **THE GENERALIZATION: measure the KNOB-LABEL width against
`vp.x − 430`, not only the HUD strings** — slice 21's *a number that does not print is not a proof*, in
a third costume, and the reason convention 14's fourth proof exists at all.

⚠ **ONE BEHAVIOUR CHANGE TO SLICES 26–31, NAMED AND GIVEN A TOOTH** (advisor): `_radome_qpeak` was
never cleared on `reset`, so pressing Reset on a RINGING wire carried a stale RINGING verdict ~0.5 s
into the re-launch. That is exactly the defect slice 32's LATCH is built to avoid one slice later, so
the asymmetry is fixed rather than left; `slice32_ui_test.gd` drives `_on_reset_pressed()` on the
slice-26 mirror and asserts it (the sixteen prior UI tests are static-fixture and never call that
handler). ⚠ **AND THE VERIFIER FLIES TWO OUT-OF-DOMAIN VALUES** — `fov = 0` and `fov = 180`, through
`set_param`, which validates knob-ness and not range: the **SLICE-24 PRECEDENT**, now stated at the
constant. It matters most for `fov = 180`, which carries the knob-vs-rung IDENTITY at a value a student
cannot drag to; it stands as a KEY-ABSENT PROXY, and the domain CEILING claim rests on the reachable
`fov = 40` asserted bit-identical beside it.

**Four proofs green.** S32V (11 arms, replay posdiff **0.0**, `aero_sat`/`defl_sat` 0 in band in every
arm, the quiet arms inside the 30° budget at 29.01° peak while the broken ones deliberately are not —
that runaway IS the mechanism); S32UI (8 teeth: the marker mirror, the three-state verdict, the latch
in both directions, the two-ENTITY slider pair [a first for this arc — the WINDOW belongs to the
missile and the LEAD to the engagement], and a **FOURTEEN-way** value guard); the smoke-load
(`EWSIM_SERVER_DONE`); and TWO windowed shots at the same range (~2450 m) — "TRACK BROKEN — lead
outgrew FOV" / *cross-range +4496 m* / *look 45.6° vs FOV 25.0° ← OUTSIDE* / *ENGAGEMENT needs a lead
of 30.4°* / *seeker: COASTING*, against "IN THE WINDOW — FOV holds the lead" / *cross-range +4153 m* /
*look 28.5° vs FOV 30.0°* / *lead 28.9°* / *seeker: MEASURING*.

**Byte-identity PROVEN ON THE WIRE**: `slice30_verify.gd` and `slice31_verify.gd` re-run against live
servers (31 reproduces rms_r **0.42395**, cures **13.3×** / **7.2×**, `radome_aim_gyro` **−0.3474**,
replay 0.0); all **sixteen** prior UI tests (16–31) re-run green.

**Run it:** `& tools/julia.ps1 --project=core tools/server.jl scenarios/slice32_fov.yaml`, then
`godot --headless --path clients/godot --script res://net/slice32_verify.gd` (exit 0 = pass). The UI
test needs no server.

**Deferred (NAMED):** a REAL GIMBAL (a head with its own state, servo bandwidth, rate limit and
mechanical stop — it adds a dynamical state AND rewrites 26–31's `look_az`); a RECTANGULAR / PER-AXIS
FOV (this slice ships ONE circular window; the per-axis habit belongs to the glass, not to the window);
**THE GIMBAL ON THE RADOME WIRE** — measured here as the corollary, kept off the showcase by convention
9, and the strongest successor because it is the first mechanism in the arc that turns slice 26's ring
into a LOCK LOSS; THE HANDOVER BASKET as an authored quantity (P5 found the launch look angle is a live
physical constraint this wire holds fixed); SEEKER RANGE / SNR ACQUISITION LIMITS (the other half of
"can the seeker see it" — this slice models only the ANGLE); plus everything 26–31 named and did not
spend.

⭐ **THE COROLLARY THAT STAYS OFF THE WIRE** (`test_missile.jl`, the slice-28 precedent for relocating
a non-client-drivable claim, and it asserts THREE directions): **slice 26's parasitic loop can shake
the seeker out of its own window.** At `fov = 20` / `vy = 200` the radome-free missile hits (0.14 m)
while a RINGING one is out of the window 72 % of the approach and misses by **3774.59 m**. At `fov =
25` the same ringing arm loses lock for only **0.4 %**, in brief episodes, **and still hits (1.07 m)**
— a short loss is survivable; what is terminal is a loss while the lead is still building. ⚠⚠ **AND
THE THIRD DIRECTION IS WHAT MAKES THE SENTENCE TRUE** (advisor): the arm does not ring *because it has
a radome* — it rings because its compensator is the **BORESIGHT-characterized** one slice 30 exists to
condemn (hardware residual exactly 0.000). Aim `R̂` at `radome_slope_worst` = −0.33 — slice 30's rule —
and **the same glass flies the same 20° window** (0.00 % out, peak look 18.14° against the radome-free
18.13°, and a miss BIT-IDENTICAL to the same wire with no window at all). ⇒ write it as *"a
compensator that RINGS can shake the seeker out of its own window, and slice 30's design rule prevents
it"*, never as "the radome breaks the FOV" — and **the FOV bound is NOT tighter than the stability
bound on this glass.**

---

## Slice 33 — THE RING IS AN FOV BUDGET ITEM

**Slice 33 — THE RING IS AN FOV BUDGET ITEM: WHAT THE PARASITIC LOOP COSTS YOU IS THE ENVELOPE
(HANDOFF §11 Tier-A)** — the ELEVENTH slice of the bank-to-turn / 3-D arc, and the successor slice 32
itself nominated. ⚠ **THE DEFERRAL'S NAME IS LOOSE AND THE SLICE DID NOT INHERIT IT**: slice 32's §
points at its FOV × radome corollary, not at head state. A REAL GIMBAL is a separate and bigger slice
and `frames.jl` says so in terms. This slice stays **STRAPDOWN**.

Slices 26–31 each recorded, as a standing fact, that **THE RINGING ARM STILL HITS** — slice 26 wrote
it first ("the MISS is NOT the metric — the ringing arm STILL HITS (2.18 m)") and 27/28/29/30/31 each
inherited it, which is why the whole family measures `rms q` / `rms r` instead of a miss. It is true
on this wire too, everywhere: across three glass depths and the full `R̂` ladder, **not one ringing arm
misses by more than 3.53 m**. **The ring was benign BECAUSE THE SEEKER HAD AN INFINITE WINDOW.** Give
it a real one and the same ring — same glass, same `R̂`, same seed — misses by **kilometres**.

> **THE LESSON, IN ONE SENTENCE.** A limit cycle you were told to measure in rad/s is spent in
> DEGREES OF FIELD OF VIEW — the ring costs you not accuracy but the ENVELOPE, and slice 30's scalar
> buys the whole envelope back.

⇒ **THE FOV A SEEKER NEEDS IS THE ENGAGEMENT'S LEAD PLUS THE PARASITIC LOOP'S EXCURSION.** Slice 32
answered the question with the collision triangle alone (18.13° on this geometry); that is the
**QUIET-GLASS answer**. The second term is continuous and monotone in the ring's amplitude — 18.14° →
20.62° → 22.12° → 23.92° → 25.01° as `R̂` walks from slice 30's design rule to slice 28's boresight
characterization.

⭐⭐ **THE PAYLOAD IS THAT SLICE 30's RULE IS AN ENVELOPE RULE, NOT ONLY A STABILITY RULE.** Slice 30
shipped `radome_slope_worst` = min(R₀, R₀+2A) as the aim point that makes a SCALAR compensator
unconditionally stable. Aim `R̂` there and the FOV requirement returns to **18.14°** — the radome-free
engagement's own 18.13°, to within the missile's aerodynamic incidence — and it does so at
A = −0.10, −0.15 AND −0.20, i.e. **DEPTH-INDEPENDENTLY**. The glass gets 2× worse and the requirement
does not move.

⚠ **NO new rung, knob, instability, cap or draw.** Both halves already fly (26–31's glass, 32's
window) and both sliders already ship. What is new is the **COMPOSITION**, ONE telemetry number that
measures it, and the design rule it yields — **slice 30's shape precisely** (its only new core
quantity was `radome_slope_worst`, and its payload was a ring count over a swept engagement).

**GATE 0 (4 probes, 2026-07-28).** ⚠⚠ **THE ADVISOR'S OPENING HYPOTHESIS WAS REFUTED, AND THE
REFUTATION IS LOAD-BEARING** — it is why this slice does NOT claim to invert slice 32's closing
sentence. The hypothesis was that the band between slice 32's two endpoints might contain a
*marginally* stable design whose look excursion is nonetheless past the window — the first regime
where the FOV bound binds BEFORE the stability bound. **P1 killed it in its own currency**: the
stability onset and the FOV break arrive at the SAME `R̂` bracket (quiet at −0.27, rms r 0.031 / 0.000 %
out; ringing at −0.24, **0.70983** / 37.6 % out), reproducing slice 30's measured boundary to the digit.
⇒ **slice 32's "the FOV bound is NOT tighter than the stability bound on this glass" STANDS.** What
slice 33 changes is that the FOV *requirement* becomes a CONTINUOUS function of the residual where
slice 32 had a single number. P2 measured `critical fov == ⌈excursion⌉` in **16 of 16** cells across
three independent axes; P3 moved the ring's AMPLITUDE with `α_max` at FIXED `R̂` and FIXED glass and
the budget followed; P4 found a **SURVIVABLE BAND** below the excursion.

**GATE 1 (6028 → 6062)** — ONE kernel in `frames.jl`, shipped by **REDEFINING the predicate from it**:
`seeker_fov_margin(att, los, fov) = max(fov,0) − boresight_angle(att, los)` and
`seeker_in_fov(…) = seeker_fov_margin(…) ≥ 0`. ⭐ **THE REDEFINITION IS THE GATE, NOT THE ADDITION** —
shipping the margin *beside* the predicate would have left gate 1 with a kernel nothing calls, the
arrangement slice 32's own gate 1 rejected one layer up. ⚠ That makes the obvious test VACUOUS
(`(margin ≥ 0) == seeker_in_fov` is `x == x`), so the tooth is the subtraction form against the
COMPARISON form written longhand, **swept at the boundary**: 6000 cells, 0 mismatches, no tolerance.
⚠⚠ **THE DIVERGENCE THE ADVISOR CAUGHT FLIPS A VERDICT, NOT JUST A MAGNITUDE**: the wire ships
`seeker_fov_deg` AUTHORED while the margin uses the CLAMPED window, so the shipped keys do not
reconstruct this one on a negative slider — and an on-boresight target is IN a `fov = −1` window where
the subtraction says OUT. ⚠ **THE CLAMP CHANGED OWNER**: `seeker_in_fov` now DELEGATES and does not
clamp, so the seam comment at `missile.jl` and the test comment at `test_frames.jl` were both reworded.
`docs/STATUS.md`'s slice-32 entry still names `seeker_in_fov` as the clamp site and is deliberately
**LEFT ALONE** — it records what slice 32 shipped, and rewriting a per-slice ledger entry to match a
later slice would make the ledger stop being a history. **This paragraph is that carry-forward.**

**GATE 2 (6062 → 6169, +107)** — the readout (`<sid>.seeker_fov_margin_deg`, `_finite_coord` never
`_finite`), the wired lesson, and the loader composition. ⚠⚠ **FIVE ASSERTS FAILED AND THEY WERE
RIGHT TO — "HELD" IS NOT BIT-IDENTITY.** The first draft inherited slice 32's `cureA.miss === ref.miss`;
EVERY held arm leaves the window in the last metres (first out at **r = 0.18 / 1.0 / 1.98 / 2.81 /
8.55 m**, at look angles of 21–162°) because the LOS unit vector swings through a huge angle as r → 0,
perturbing the CPA by 5e−13…1.4e−7 m. Slice 32's `===` passed only by **luck of a wider window**. ⇒ a
`held(win, free)` helper puts the exact claim on the GATED quantities. ⚠⚠ **AND A COLUMN THAT WOULD
HAVE COUNTED NOTHING**: a badly broken arm's CPA is 3697 m so it NEVER ENTERS the r ∈ [500, 3000] band
— `sum/max(n,1)` would have printed a quiet **`rms r = 0.00000` from ZERO SAMPLES** on the arm missing
by 3.7 km. `arm` now yields `NaN`, and every test quoting a band number asserts `n_band > 0` first.

**GATE 3 (6169 → 6215)** — `scenarios/slice33_budget.yaml` (seed 32, `STEPS = 12800 = 16 × 800`, sized
off the slowest arm's 11.25 s, every arm asserting it REACHED CPA). **The FIRST scenario in the project
to author GLASS AND A WINDOW in one file**, and the shipped YAML reproduces gate 2's programmatic world
cell for cell. Frame-sampled, r > 200 m gate, closing leg only:

| `R̂` | FREE (fov 40): rms r | excursion° | miss (m) | THROUGH fov 21 | out % | `t_break` |
|---|---|---|---|---|---|---|
| −0.33 (slice 30's rule) | 0.05887 | 18.115 | 1.429 | **held** | 0.000 | — |
| −0.24 (the onset) | 0.70969 | 20.608 | 2.401 | **held** | 0.000 | — |
| −0.18 | 0.93167 | 22.113 | 3.628 | **2191.99 m** | 42.385 | 5.040 |
| −0.03 (boresight, SHIPPED) | 1.07151 | 24.995 | 3.896 | **3696.89 m** | 72.603 | 1.936 |

Break at **t = 1.936 s / r = 5247.0 m**, with the lead still building; the budget floor is **−69.84°**;
the headline ratio is **949×**. **CURE A** widens the seeker to 26° → 3.896 m; **CURE B** aims `R̂` at
the wire's own `radome_slope_worst` (read off telemetry, −0.3300, never recomputed) → 1.429 m, and the
requirement falls 24.995° → 18.115°. Replay **bit-identical (0.000000 m)**.

⚠⚠ **THE GATE-3 FINDING: THE EMIT GRID UNDER-READS THE EXCURSION BY MORE THAN THE SURVIVABLE BAND IS
WIDE, AND IT DECIDES WHAT THE VERIFIER MAY CLAIM.** A verifier reads FRAMES (every 16th tick), so the
peak look angle it sees is the largest SAMPLED one: **24.9946° against the 25.0108° the core flies — a
0.016° deficit**, where gate 2 measured the survivable band at ~0.011–0.05°. ⇒ **the finest cell in
that band is BELOW the verifier's resolution**: a window placed 0.011° under the FRAME excursion is
really ~0.027° under the true one and lands in the tens-of-metres regime (**20.6 m**) rather than the
**2.002 m** `test_missile.jl` measures PER TICK. So the sub-degree claim stays per-tick in the suite,
and the verifier makes the claim its own resolution supports — which is still the whole of **TWO
THRESHOLDS**, because `t_break` separates them cleanly: the survivable cell loses lock at **r = 707 m
(NEAR CPA)** and the 0.1° cell at **r = 3543 m, with the lead still building**. This is
[[ewsim-missile-verifier-sampling]] arriving in a NEW quantity — not the miss but the EXCURSION.

⚠⚠ **THE ISOLATION IS NOT SLICE 32's AND MUST NOT BE COPIED FROM IT — IT INVERTS.** Slice 32 could
assert `aero_sat == 0` in EVERY arm because its wire had NO GLASS. Here the FREE ringing arm saturates
**80.67 %** of its band **AND HITS at 3.896 m** (slice 26's ceiling BOUNDING the cycle) while the broken
arm saturates **0.00 %** and misses by kilometres. Saturation discriminates in neither direction; **THE
WINDOW does.** What IS invariant, and asserted on every arm, is **`defl_sat == 0`**.

⚠⚠ **AND THE PREDICTOR AND THE PREDICTED NEVER COME FROM THE SAME RUN — the verifier is STRUCTURED
that way, not commented.** On a windowed arm `rms r` FALLS **4.72×** (0.93167 → 0.19744) while the miss
OPENS **604×**, and the arm's own `look_max` reads **90.563°** — the post-lock-loss runaway — against
the ring's actual 22.113°. So every design is flown TWICE. ⚠ **The FREE read is itself a MEASUREMENT**:
a live wire always carries the key, so `fov = 40` stands in for "no window" and the verifier asserts
`out == 0.0` on every free arm — otherwise the excursion column would be the runaway.

⭐⭐ **THE CLIENT: A COMPOSITION HUD BRANCH, AND THE DEFECT IT PREVENTS IS ASSERTED AS A NUMBER.** This
wire is the FIRST to raise BOTH `seeker_fov_view` AND `radome_view` (slice 32's gate-3 testset asserts
`!haskey(info, :radome_view)` on ITS wire AS A FEATURE, and that still passes). ⚠ **The BUTTON outcome
is identical either way — both markers drop it at both sites, so slice 33 needs NO EDIT at either, the
OPPOSITE of slice 26's "the drop needs BOTH sites"** — **but the HUD BRANCH is not.** Without a
composition branch `_seeker_fov_view` wins and slice 32's `_fov_verdict_label` runs, comparing the
**LEAD** against the **WINDOW**: on this wire the lead is ~18.1° inside a 21° window, so it prints
**"IN THE WINDOW — FOV holds the lead" on the arm that misses by 3.7 km**, and after the latch "TRACK
BROKEN — lead outgrew FOV", naming the wrong cause confidently. **THE LEAD NEVER OUTGREW THE WINDOW;
THE RING DID.** `slice33_ui_test.gd` calls BOTH helpers with the SAME wire's numbers and asserts they
DISAGREE. ⇒ a branch on the CONJUNCTION, checked FIRST, a SWITCH ahead of both (32's helper left
VERBATIM and still correct on 32's glass-free wire), with a verdict riding the shipped **MARGIN** —
which is what earns that key its place under convention 13 — and drawing BOTH instruments.

⭐ **AND BOTH INSTRUMENTS MUST BE LIVE, which is the other thing a composition can silently break**
(the advisor's blocking concern). `_radome_qpeak` (the ring, slice 27) and `_fov_lost` (the track
break, slice 32) are two INDEPENDENT `if` blocks gated on their own telemetry keys — **not a chain** —
and the UI test proves it on ONE wire carrying both. A chained dispatch would freeze the peak-hold at
0 and print "loop STABLE" forever on a missile shaking itself out of its own window, with nothing
headless to catch it. The peak-hold is asserted to ride the **YAW** channel (slice 28's switch: this
wire's lead is in AZIMUTH, and a pitch meter reads 0.10 where yaw reads 1.31).

⚠ **`_budget_verdict_label` TAKES THE RANGE AS AN ARGUMENT, AND THAT IS GATE 2's FINDING IN THE
CLIENT.** Every held arm leaves the window in the last metres, so an ungated "breaking" state would
fire at the instant of a CLEAN INTERCEPT and paint the **CURE** arm a failure. The gate lives INSIDE
the pure helper so the UI test pins it — convention 14, slice 31's aim-point comparison shipped WRONG
with only a shot to catch it — and its mirror OUTSIDE the gate is asserted too, so the gate is proven
to be a RANGE gate and not a blanket suppression.

⚠ **THE SHOT HARNESS CAUGHT AN AIMING DEFECT, AND IT IS THIS SLICE'S OWN METRIC INVERSION.** A 4300 m
gate worked (the broken arm's CPA is 3696.9 m, so anything below that would never trigger — slice 32's
lesson, inherited) and **still captured the wrong thing**: by then the track had been broken ~1.8 s, so
the look angle read **56°** (the post-lock-loss RUNAWAY, not the ring) and the yaw rate had decayed to
0.205 rad/s, because the parasitic feed is CUT once the seeker stops measuring. Re-aimed at **5000 m**,
just past the t = 1.936 s break, the pair shows the MECHANISM: `look 30.1° vs FOV 21.0° / BUDGET LEFT
−9.1°` beside a `lead_angle_deg` of **15.32°** — the engagement's own demand, comfortably inside the
window, which is exactly the number that proves slice 32's verdict would have reported health. **AIM
AT THE MECHANISM, NOT ITS AFTERMATH.** THREE shots taken, one per verdict state (the third, on the FREE
arm, is the only one that can fire the `← RINGING` tag — for the same inversion reason).

**Knobs (2, both at the interceptor — unlike slice 30's and 32's two-entity pairs, because both halves
of this comparison belong to the missile):** `seeker_fov_deg ∈ [19, 40]` — floor = the QUIET-GLASS
requirement and clear of slice 32's P5 never-acquires cliff at ~18.12° (**the scenario's AUTHORED
LAUNCH ATTITUDE, not a seeker property**); ceiling = **the FREE READ itself**, measured, and
deliberately not 26 (though 26 measures free too) because 26 is CURE A's own value and one number must
not do both jobs. `radome_slope_est ∈ [−0.36, −0.03]` — floor reaches PAST slice 30's aim point so cure
B is reachable AND overshootable (the requirement then STOPS FALLING: 18.1379° at −0.36 against
18.1376° at −0.33, while `rms r` RISES 0.05879 → 0.06911 — the one-sided constraint, a positive
residual de-tunes); ceiling is the authored default, bounded by the **30° small-angle budget** 28/29/30/31
each declared, with the excursion already at 25.01° there. ⚠ **`cross_speed_mps` is DISQUALIFIED and
asserted absent** — slice 32's OWN axis, and a THIRD mechanism on a wire convention 9 already stretches
to two; `af_alpha_max` is HELD as the gate-0 causation probe. Convention 9 is satisfied **BY
MEASUREMENT** (the slice-27 DIAGONAL precedent): `fov` TRACKING the excursion leaves `held` unchanged,
4/4 cells. ⚠ **Stated as TRACKING, never as `fov = ⌈excursion(R̂)⌉`** — seam discipline 2 forbids
asserting the `ceil` identity (16/16 at gate 0 is an artifact of the 1° measuring grid; the physical
claim is the inequality, bracketed at ±0.1°).

Class **4a** (the NINTH consecutive RNG-live slice; no new branch and no new `randn`, so there is **no
fresh draw-count testset, deliberately** — slice 32's corollary already flew radome × FOV arms under
its asserted 2-draw lockstep). Button **DROPPED** (9th: 16, 26, 27, 28, 29, 30, 31, 32, 33).

**Four proofs green.** `slice33_verify.gd` (13 arms, 8 phases, exit 0); `slice33_ui_test.gd` (9 teeth,
FIFTEEN-way value-guard, exit 0); `Sandbox.tscn` headless smoke-load reaching `EWSIM_SERVER_DONE`;
three windowed shots. **Slices 1–32 byte-identical — gate 3 touched NO core file** — proven ON THE WIRE
anyway: `slice26/27/28/29/30/31/32_verify.gd` all re-run against live servers, exit 0, reproducing
STATUS to the digit, and all 31 prior UI tests re-run green.

Run it: `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice33_budget.yaml`, then
`godot --headless --path clients/godot --script res://net/slice33_verify.gd`. The UI test needs no
server.

**Deferred (NAMED):** ⭐ **A REAL GIMBAL — and gate 0 banked its lesson: THE GIMBAL THAT SAVES YOUR
ENVELOPE PARKS YOU ON THE WORST GLASS.** A strapdown seeker's body chases the LOS so the look angle
stays near the lead; a gimbal deliberately holds the head at the FULL lead angle, which is exactly the
steep part of the curve slice 28 showed closes the loop. So it buys the envelope back and hands the
radome a worse operating point — the same trade in a new place. ⚠ It REWRITES 26–31's `look_az`, the
byte-identity surface of six slices, so it needs a presence-gated head state with the strapdown
else-arm VERBATIM. Plus a RECTANGULAR / PER-AXIS FOV; SEEKER RANGE / SNR ACQUISITION LIMITS; THE
HANDOVER BASKET as an authored quantity; and everything 26–32 named and did not spend.

---

## Slice 34 — THE GIMBAL — the head points where the glass says

**Slice 34 — THE GIMBAL: THE HEAD POINTS WHERE THE GLASS SAYS THE TARGET IS (HANDOFF §11 Tier-A)** —
the TWELFTH slice of the bank-to-turn / 3-D arc, and the successor slices 32 AND 33 both nominated.
⚠ **BOTH HALVES OF THE BANKED DEFERRAL WERE REFUTED AT GATE 0** and the live claim was found in a
THIRD place — the slice-33 shape exactly, and the refutations are load-bearing.

Slices 26–33 built the parasitic loop on ONE geometric fact: the radome bends the ray by an amount set
by the LOOK ANGLE, and the look angle is the LOS measured off the missile's **own nose** — a quantity
the missile can only move by ROTATING, which is exactly why slice 26 is a BODY-RATE instability.
**A GIMBALLED SEEKER BREAKS THAT IDENTITY.** Its head has its own pointing angles, the ray passes
through the part of the dome the head is AIMED at, and — this is the whole slice — **the head is aimed
by the very measurement the dome just bent.** The index of the glass becomes a FIXED POINT of the
glass, so part of the bend's own variation is absorbed by the head's pointing instead of being handed
to guidance: slice 26's loop is partly RE-CLOSED THROUGH THE HEAD, where its sign is NEGATIVE.

> **THE LESSON, IN ONE SENTENCE.** A strapdown seeker's radome index is handed to it by the airframe;
> a gimballed seeker's is handed to it by its own last measurement — and an index that looks at itself
> is an index that fights back.

⭐⭐ **THE HEADLINE IS A COMPARISON BETWEEN TWO WIRES, AND THAT IS WHY THE SLICE SHIPS TWO SCENARIOS**
(slice 22's precedent). At R̂ = −0.18 on glass R₀ = −0.03 / A = −0.15, seed 32, the same crossing
target: the STRAPDOWN twin rings at `rms r` **0.93167** while the GIMBALLED wire sits at **0.01207** —
**77.2×** frame-sampled, **78.9×** per tick — and BOTH HIT (3.628 vs 4.299 m), the arc's standing fact
since slice 26. ⚠ A head is **not a fidelity**: `gimbal_tau_s` is AUTHORED and NO in-domain slider
value removes a head. τ → 0 does not — the head that ships tracks its own BENT, one-tick-delayed
measurement, so at τ = 0 it lands on the PREVIOUS tick's bent angle rather than this tick's
LOS-vs-body, and gate 2 measured it STILL QUIET (0.03394). ⭐⭐ **THAT IS ALSO THE ISOLATION: at zero
servo lag the margin is already there IN FULL ⇒ THE MARGIN IS BOUGHT BY THE INDEX, not by the servo.**

⭐ **THE ONSET WALKS TWO RUNGS OF THE SAME LADDER, FROM THE SAME SLIDER**, quoted BRACKET TO BRACKET
and never as one number (slice 30's "sufficient, never tight"): **(−0.27, −0.24] strapdown** against
**(−0.18, −0.16] gimballed**. The gap those two admit spans 0.06 to 0.11, so a single "≈0.08" would be
a number neither wire supports. ⭐ **AND `head_max` STEPS AT THE SAME PLACE** — flat at 17.190° (frame;
18.117° per tick) through every quiet arm and 20.616° at the first ringing one — a SECOND, INDEPENDENT
tell from a DIFFERENT quantity, which is what makes the bracket a MEASUREMENT and not a threshold read
off the metric that defined it.

⚠ **AND IT IS NOT FREE, IN THE ONE CURRENCY A GIMBAL HAS.** The margin is bought by the head's pointing
DECOUPLING from the true LOS, and the size of that decoupling is precisely the tracking error the
head's own detector must cover. **SLICE 33's SINGLE NUMBER SPLITS IN TWO**: a STOP (the head's TRAVEL
about the body, which reproduces slice 33's excursion — a RESTATEMENT, not a new claim) and a DETECTOR
WINDOW (about the head axis — NEW). Gate 2 measured that the two are ONE BUDGET: a clamped head cannot
reach the LOS, so its deficit is spent out of the detector's allowance
(`off_head ≈ (travel − stop) + free tracking error`). ⭐⭐ **SLICE 32's PREDICATE RETURNS IN THE NEW
CURRENCY — `held ⟺ tracking error < detector window`** — bracketed to 0.005° on the quiet arm and
CONSERVATIVE by ~1 % on the ringing one, with the two sides from DIFFERENT RUNS (the error off a FREE
arm, the verdict off a WINDOWED one). ⭐ **THE RING IS SPENT IN DETECTOR WINDOW, 3.7×** (1.598° →
5.916°), so through the shipped 4° window the SAME slider that quiets the loop also keeps the track.

⚠⚠ **THE TWO-RUN DISCIPLINE IS THE SHIPPED STRUCTURE, AND THE LIST IS THREE QUANTITIES — THE THIRD
FAILS QUIETLY.** A broken window FREEZES the index (no error signal, no slew — the head HOLDS), a
frozen index produces a CONSTANT bend, and a constant bend is QUIET at every R̂. So on a windowed arm
`rms r` FALLS and the tracking error RUNS AWAY to ~90° — both visibly wrong — but **`head_angle_deg`
FREEZES at the value it held when the track broke**, reading the QUIET arms' 17.190° against the ring's
actual 20.616°: a plausible number, in range, on the LOW side. A verifier reading the excursion off a
windowed run would report that the ring costs nothing.

⚠⚠ **GATE 3's FIRST FINDING WAS A BLOCKING CLIENT DEFECT NO EXISTING TEST WOULD HAVE CAUGHT** (advisor,
before any gate-3 code). Gate 2's loader refuses `seeker_fov_deg` beside a head — a gimballed seeker has
NO body-fixed window — so a gimbal wire raises `radome_view` (it HAS glass) and **NOT** `seeker_fov_view`:
both of the client's FOV branches fail their conjunction and slice 26/27/28's RADOME CASCADE takes it.
⚠ **That failure is the stale-readout class's WORST form, because NOTHING IN IT IS STALE** — a gimbal
wire carries `radome_slope`, `radome_residual*`, `radome_slope_worst` and `omega_q`/`omega_r`, so every
number that cascade reads is LIVE and PLAUSIBLE. It would print a fluent ring/quiet verdict about the
GLASS on a wire whose whole subject is the HEAD, and not one test would have failed. ⇒ a NEW handshake
marker **`gimbal_view`** (gated on `haskey(comp, :gimbal_tau_s)`) and a HUD branch checked FIRST, with
the no-marker MIRROR asserted in the UI test. ⚠ This made gate 3 a **CORE edit**, unlike slice 33's.
⚠ The BUTTON needs no edit at either site (`radome_view` already drops it) — slice 33's finding, 2nd
occurrence, and the OPPOSITE of slice 26's "the drop needs BOTH".

⚠ **THE DEFAULT WINDOW IS A FREE READ *ON THE APPROACH* AND NOT BIT-IDENTICAL — measured, not
inherited.** `max|Δpos|` against the key being absent runs 1.05e−3 / 2.09e−9 / **9.15e−11** / **0
EXACTLY** at 2.5 / 3.0 / 4.0 (the default) / 8.0° (the domain ceiling): the window IS reached in the
last metres as the LOS unit vector swings at r → 0 (slice 33's endgame finding, in the head's
currency). ⇒ the CEILING is the free read; the default's claim is **0.00 % out at r > 200 m**.

⚠⚠ **AND THE `held` TOLERANCE IS A FUNCTION OF THE WINDOW — the verifier's first run FAILED on it**
(4.319476 vs 4.298999 m at a flat 1e−6 inherited from slice 33). Everything a held arm pays it pays in
the ENDGAME, and how early the endgame swing reaches the window depends on how WIDE the window is: the
shipped 4° one moves the CPA by ~1e−10 m, the bracket's 2.05° one by **0.020 m**. Slice 33 could use
one flat number because its windows were 21–40°; a slice whose subject is a detector window a couple of
degrees wide cannot. The EXACT claim lives on the GATED quantities (tracking error and head travel, both
1e−6, r > 200 m).

⭐ **THE HANDOVER IS VISIBLE IN THE INDEX TRIPLE — the core testset's first draft FAILED on exactly one
tick.** `look_angle === head_angle_deg` (the glass used the HEAD's index) and `look_angle != look_body_deg`
(never the NOSE's) hold on every tick but the FIRST: a HANDED-OVER head initialises to the CLAMPED TRUTH
look angles, so on the tick it is born the two ARE the same number, by construction. Pinned as
`same_ticks == [1]`, which is strictly STRONGER — it also proves the handover happened where the
scenario says it does (§0.8 measured a CAGED head reading 18.117°, the strapdown requirement, instead).
⚠ **AND THE IDENTITY HALF IS NOT THE `x == x` SHAPE GATE 1 REFUSED, THOUGH IT IS STRUCTURALLY CLOSE**
(advisor): `look_angle === head_angle_deg` is the same expression over the same two locals at two
sites, so it is worth saying which regression it catches — it fires if the seam stops overwriting
`look_az, look_el` with the head's angles, or if the head block is ever moved BELOW the radome block
(seam discipline 2, whose whole point is that the other ordering leaves a one-tick lag that survives
τ → 0 and would fake a mechanism). The claim itself is carried by the paired INEQUALITY against
`look_body_deg`.

⭐⭐ **THE ISOLATION IS NEITHER SLICE 32's NOR SLICE 33's, AND IT IS THE CLEANEST OF THE THREE.** The
discriminating pair is the TWO WIRES at the SAME R̂: the strapdown twin saturates the slice-19 aero
ceiling **48.36 %** of its band while the gimballed wire touches it **0.00 %** ⇒ **the difference is the
INDEX, not authority** — the gimbal arm is not flying a better-behaved airframe, it simply is not
shaking. `defl_sat == 0` on every arm of both wires is what IS invariant (kept from slice 33; its
`aero_sat` reasoning is the part that does not transfer).

⭐ **POST-REVIEW (advisor): THE *OTHER* SLIDER'S FLOOR WAS FLOWN NOWHERE.** Both YAMLs declare
`radome_slope_est ∈ [−0.36, −0.03]` and the gimbal file cites slice 26's post-commit rule (ENDPOINTS
MEASURED, never inferred from the interior) while applying it only to the WINDOW knob — R̂'s CEILING is
flown on both wires, its FLOOR nowhere. ⚠ Not hygiene: past the aim point the residual goes POSITIVE and
DE-TUNES rather than rings, but a de-tuned loop LAGS, lag grows the LEAD, and the lead is what the
head's TRAVEL must cover (vs the stop) and what sets the TRACKING ERROR (vs the window). Measured, it
HOLDS on both wires — 0.00 % out, 0.433 / 0.185 m, `rms r` 0.06946 / 0.06911 (QUIET), head travel
18.117° of 30°, tracking error 1.508° of 4° (so the shipped window is INERT there too). ⭐⭐ **AND
MEASURING IT CORRECTED THE SCENARIO'S OWN STATED REASON**: the YAML said the overshoot shows the
requirement "STOPS FALLING"; it does not — the RING TURNS BACK UP (0.05917 → 0.06946 gimballed,
0.05879 → 0.06911 strapdown) and the MISS grows monotonically PER TICK (0.161 → 0.433 m, on to 5.669 m at
R̂ = −0.50 beyond the domain — ⚠ the ~11 m emit grid cannot resolve that ordering, both arms being
HITS, so the verifier asserts the RING and says so). A DE-TUNE THAT REVERSES, which is sharper than a plateau. ⚠ The DETECTOR
bill is not even monotone in R̂ (1.599 → 1.508 → 1.383° at −0.33/−0.36/−0.40, a MINIMUM past the aim
point), so the floor is where the REVERSAL is visible and both limits still have margin. Both wires now
fly a `DOMAIN_MIN` arm (PHASE DOMAIN) plus a core testset.

Class **4a** (the TENTH consecutive RNG-live slice — the head is a DETERMINISTIC SERVO on an existing
measurement, so NO new draw; draw count asserted both bounds at gate 2). **NO new rung, cap or
instability.** ONE live slider **`gimbal_fov_deg` ∈ [1, 8]°** on the head wire plus 27/28/33's
`radome_slope_est` (the two halves of ONE comparison — `window` vs `tracking error(R̂)`, slice 33's pair
in the new currency); the twin carries the SAME R̂ slider over the SAME domain, which is what makes
"walk it on both wires" one experiment. `gimbal_tau_s` AUTHORED — a **CONFOUNDED** lever, not a dead one
(the sag is monotone everywhere and AT THE LINE it crosses the verdict) — and `gimbal_stop_deg` AUTHORED
as a RESTATEMENT. Button **DROPPED** (10th: 16, 26, 27, 28, 29, 30, 31, 32, 33, 34).

**Four proofs green.** `slice34_verify.gd` (19 arms across BOTH wires through one `load_scenario`, 9
phases, exit 0); `slice34_ui_test.gd` (10 teeth, SEVENTEEN-way value-guard, exit 0);
`Sandbox.tscn` headless smoke-load on BOTH wires reaching `EWSIM_SERVER_DONE`; **three windowed shots,
one per verdict branch** — `quiet` ("SELF-INDEXED — the loop is quiet", head 12.7° vs nose 14.6°),
`broken` ("TRACK LOST — the head let go", head 16.9° vs nose **29.0°** — ⭐ the index pair diverging as
the frozen head is left behind by a runaway nose, the mechanism in one line), and `ringing`
("RINGING — the index is not enough", body yaw rate +0.717 rad/s ← RINGING). ⚠⚠ **TWO OF THE THREE WERE
AIMED WRONG FIRST**: 5000 m is the BROKEN arm's gate, but on a HOLDING arm that is t ≈ 2.4 s and the
lead has not built yet (the first quiet shot read head 2.99° / error 0.32° against the 17.19 / 1.95 the
verifier measures — it captured the engagement before the quantities the slice is about exist); and the
ringing shot aimed at R̂ = −0.16 read a peak-hold of 0.123, under the 0.5 the "← RINGING" tag needs, so
the HUD printed the QUIET verdict on the arm the shot exists to show ringing. **Aim at the STATE being
claimed, not at a shared range or the first rung that qualifies.**

**Slices 1–33 byte-identical**, proven ON THE WIRE rather than off the diff (gate 3 touched a core file,
so that is not a formality): `slice25/26/27/28/29/30/31/32/33_verify.gd` all re-run against live
servers, exit 0; all **34** UI tests re-run green.

Run it: `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice34_gimbal.yaml`, then
`godot --headless --path clients/godot --script res://net/slice34_verify.gd` (it switches to
`scenarios/slice34_strapdown.yaml` itself). The UI test needs no server.

**Deferred (NAMED):** **THE HANDOVER BASKET as an authored quantity** (§0.8 promoted it from slice 32's
deferral to a LIVE constraint: a caged head's window requirement IS the strapdown one until it acquires;
what ships is a HANDED-OVER head, stated as a §1 condition); **A RATE-LIMITED HEAD** (`gimbal_rate_max`
exists in the gate-0 probe and was NEVER EXERCISED — the natural home of a slew-rate-limited lock loss);
**MEMORY TRACK / RE-ACQUISITION** (the break is TERMINAL here — a real head coasts on its last inertial
rate; slice 32's α-β choice, one layer out) — ⚠⚠ **SINCE KILLED AT GATE 0, `docs/plans/slice37.md`
(2026-08-17): the coast is a head feature and what makes the break terminal is the ESTIMATOR's frozen
rate, so no head change reaches it**; **A RECTANGULAR / PER-AXIS STOP** (gate 1 wrote down that
its circular shape rests on a species argument, because no flying arm had ever bound it — gate 2's §2.5
bound it for the first time); **THE HEAD'S OWN GYRO** (a rate-stabilized head measures inertial LOS rate
directly — the classical reason gimbals exist, and a DIFFERENT mechanism from anything here)
— ⚠⚠ **TAKEN AS SLICE 37 AND THIS WORDING REFUTED AT ITS GATE 0** (2026-08-17, `docs/plans/slice37.md`
PART II): the shipped seeker ALREADY reports inertial LOS angles (`missile.jl:1652` is `az_el(û_tru)`,
not `look_angles(…)`), so what is body-referenced is the **SERVO** and the live claim is its REFERENCE
FRAME — and it INVERTS the classical argument, because the position servo's LAG was silently low-passing
body motion out of the glass's INDEX (three heads on one grid: strapdown (−0.265, −0.260], position-servoed
(−0.170, −0.165], rate-stabilized (−0.210, −0.205] ⇒ stabilizing gives back ≈40–45 % of what slice 34 bought
— ⚠ the onset line is the LARGEST SINGLE-STEP RATIO, threshold-free, and the sensitivity is quoted rather
than hidden (a bare `rms r > 0.20` was arbitrating the headline in the first draft),
while slice 35's two-sided knob goes INERT); plus
everything 26–33 named and did not spend.

---

## Slice 35 — A RATE-LIMITED HEAD

**Slice 35 — A RATE-LIMITED HEAD: THE BANDWIDTH THAT HOLDS THE TRACK IS THE BANDWIDTH THAT FEEDS THE
LOOP (HANDOFF §11 Tier-A)** — COMPLETE (2026-08-09), gates 0–3. The deferral slice 34
named SECOND. Slice 34's head was INFINITELY FAST: `head_slew` moved it a full first-order step every
tick with no bound on how far. A real gimbal has a servo with a maximum slew rate, and the moment it
does the head's motion stops being free — it becomes a RESOURCE spent against a demand, and **THE
DEMAND IS SET BY THE PARASITIC LOOP.**

**GATE 0 (5 probes)** — ⚠⚠ THE OPENING FRAMING WAS REFUTED BEFORE ANY CODE (advisor): "a finite slew
rate breaks lock in the endgame at `r ≈ V⊥/ω_max`" is a PURSUIT geometry and a DEAD KNOB on a
collision course (this arc has measured λ̇ ≈ 0 three times — slice 28's 0.2° band, slice 29's
refutation #1, slice 34's *constant* 17.190° head angle). ⚠⚠ AND THE ADVISOR'S OWN SHIP/NO-SHIP GATE
CAME BACK NEGATIVE: a WIDER WINDOW DOES rescue a rate-limited arm ⇒ the BREAK is slice 34's mechanism
and is NOT this slice's claim. ⭐⭐ The live claim was found in a THIRD place — **the arc's FIRST
TWO-SIDED KNOB**: slices 32/33/34 all end "widen it, it's free", and that cure does NOT transfer,
because bandwidth is what the loop FEEDS ON. Slow the head and the ring is attenuated (`rms r`
0.88465 → 0.38591, 2.29×) while the tracking error it must cover GROWS (5.916° → 12.828°, 2.17×).
⚠⚠ A SECOND advisor BLOCKING CHECK fired on the headline: at 2–3 °/s the limit binds on **100.00 %**
of band ticks — the head is an OPEN-LOOP RAMP, not a filtered servo, quiet for precisely slice 34's
FROZEN-HEAD reason — so **the 43× is UNQUOTABLE** and that end ships as THE REDUCTIO, which is what
sets the domain FLOOR.

**GATE 1 (6628 → 6680, + a post-review commit to 6685)** — `frames.jl` `head_slew` gains a defaulted
keyword `rate_max = Inf`, clamped **RADIALLY** and INNER to `head_clamp` (the stop keeps the last
word). ⚠⚠ FINDING 1: **the plan's own branch polarity was BACKWARDS and the gate-0 probe patch
carried the bug** — `cap = max(rate_max,0)·Δt`, so the DEFAULT `Inf` at `Δt = 0` gives `Inf·0.0 =
NaN`, and under `step ≤ cap` that falls into the LIMITING branch and regresses three of slice 34's
shipped `dt ≤ 0` degenerates to NaN. The shipped form guards the BINDING branch (`sat = dem > cap`),
which makes every non-finite cap inert for free — `head_clamp`'s own semantics, one kernel shape not
two. ⭐ FINDING 2: `τ = 0 ∧ dt = 0` PARTS COMPANY with slice 34 and it is the PHYSICAL answer — a
servo with a finite rate cannot teleport in zero time. ⚠ The return was SPLIT rather than widened
(`head_slew_full → (az, el, demand, rate_sat)`), because ~15 shipped asserts depend on the 2-tuple
idiom, and `demand` is a STEP IN RADIANS, not a rate (the division would manufacture a non-finite
from finite input at `Δt = 0`). ⚠ THREE test-integrity defects were caught AFTER the first green run
(advisor, slice 26's post-commit precedent): a bare `!isapprox` ordering tooth, a SEED-DEPENDENT hole
in the non-vacuity counter, and a four-band claim measured in a temp file rather than the suite.

**GATE 2 (6685 → 6874, + a post-review commit to 6892)** — the seam, the loader and the telemetry,
and FOUR edits total. `scenario.jl`
adds `gimbal_rate_dps` to the EXISTING `("gimbal_stop_deg", "gimbal_fov_deg")` validation loop rather
than growing a block of its own (refused without `gimbal_tau_s`, `isfinite`-validated, NO positivity
guard — `rate_max ≤ 0` is a degenerate the kernel OWNS). ⚠ Its name carries its UNIT where the other
two do not, deliberately: they are ANGLES; a RATE has a time in it. The seam swaps `head_slew` →
`head_slew_full` and ships `head_rate_dps` / `head_rate_sat` / `gimbal_rate_dps`.

⭐ THE SHIPPED KERNEL REPRODUCES EVERY GATE-0 NUMBER TO THE DIGIT (band demand p95 2.468 / 1.663 /
**0.600** / 32.155 / 48.536 / **60.831** at R̂ = −0.33 … −0.03), which retires gate 1's polarity worry
on the wire: the two forms differ only for NON-FINITE caps, and every flying tick has a finite one.
⭐⭐ AND THE PRE-LIMIT TOOTH IS SHARPER THAN PLANNED — the reason `head_slew_full` exists is that a
post-hoc difference of `:head_az` reads the CLIPPED motion, i.e. reports the CAP as the demand
(the answer as the question). At R̂ = −0.03 / 8 °/s: demand p95 **214.958 °/s** against an achieved
**8.000**, ~27×, and **on EVERY saturated tick the achieved step is EXACTLY the cap** (max AND min of
the whole saturated set 8.000000000 — the distribution, not one lucky tick, and `cap` rather than
`√2·cap`, which is gate 1's RADIAL species argument arriving on the wire). Where nothing binds the
two methods agree to 1e−9. ⚠ The HANDOVER tick and every HELD tick ship 0.0 — a zero is the ABSENCE
of a slew, not a quiet servo, and `head_rate_sat` therefore reads 0 on a BROKEN arm for the same
reason `rms r` falls there (the two-run discipline's FOURTH quantity, as the plan predicted).

⚠⚠ **GATE 2's FINDING — A RATE LIMIT MAKES THE ACQUISITION TURN THE BINDING REQUIREMENT, AND IT
SETTLES THE KNOB COUNT.** Gate 0 gated the acquisition confound away with the arc's [500, 3000] m
band; gate 2 found what that costs. At R̂ = −0.18 the LOOP's requirement barely moves under a rate
limit (`off_band` 1.956 → 2.022) while the whole-approach one TRIPLES (`off_max` 1.956 → 8.051) **out
at LAUNCH RANGE, r ≈ 5700 m**. ⚠⚠ And it is the MISSILE's turn, not the loop's — on a wire with NO
GLASS AT ALL `off_band` is a flat **0.031°** at every rate while `off_max` runs 2.112 → 7.223 →
12.346 at free / 15 / 8 °/s. ⇒ slice 32/34's predicate `held ⟺ requirement < window` is **FALSE** on
a rate-limited arm (a 2.20° window against a 1.986° requirement BROKE 97.4 % of the approach) and is
**NOT this slice's to re-ship** — there it is a statement about the HANDOVER BASKET, slice 34's FIRST
named deferral and a different slice. ⇒ **CONVENTION 9, MEASURED RATHER THAN ASSUMED** (the plan's own
instruction, and the expectation HOLDS): `gimbal_rate_dps` + `radome_slope_est` ship and
**`gimbal_fov_deg` goes AUTHORED AND WIDE** — not on argument but on a number, **19.279°**, the worst
whole-approach requirement over the R̂ domain at the servo domain's FLOOR. ⭐ And the two shipped knobs
are ONE AXIS: the rate knob's COST is charged by the ring, which R̂ sets — `off_band` FLAT across the
whole rate domain at slice 30's aim point (1.599 → 1.598) against 2.17× at the boresight
characterization. **SLICE 30's RULE PAYS A THIRD TIME** (33 = FOV, 34 = detector window, 35 = servo
bandwidth): aim R̂ at `radome_slope_worst` and fly the cheapest servo in the catalogue.

⚠ **TWO CONDITIONS EVERY GATE-2 NUMBER CARRIES.** (1) AN INFINITE DETECTOR WINDOW — a rate-limited
head LAGS, so slice 34's own 4°/8° window breaks it, the band EMPTIES and every column goes NaN; the
first draft of the probe ran at the inherited `fov = 8.0` and produced exactly that. (2) NO GLASS
**AND NO WINDOW** for the isolation — the window is the head's OTHER channel, so with both removed
`max|Δpos|` is **EXACTLY 0** at every rate from 60 down to 2 °/s (miss `===` 0.19116 by identity)
**while the head lags by 21.7°**, which is what makes the zero a measurement and not a dead knob.
⚠ THE BIT-IDENTITY CONTROL IS THE ABSENT KEY / `Inf`, NEVER `gimbal_rate_dps = 60` — now a POSITIVE
fact in the suite (`max|Δpos|` 0.652 / 0.041 / 0.165 m at R̂ = −0.33 / −0.18 / −0.03, against an EXACT
0.0 for the absent key and for `1e6`), because the peak demand is an identical 72.542 °/s on every
arm (the tick-2 handover transient) and gate 3 must not author the ceiling as a control.

⭐ **GATE-2 POST-REVIEW (advisor, 6874 → 6892)** — the `gimbal_rate_dps ≤ 0` degenerate the loader
DELIBERATELY permits was proven to LOAD and **never FLOWN**, which matters because at gate 3 the key
is a DECLARED KNOB and `set_param` writes one with no clamp and no revalidation. Flown, it is
**BIT-FOR-BIT slice 34's `τ = Inf` reductio** (`max|Δpos|` and `max|Δhead_az|` both EXACTLY 0 over
4000 ticks, head_az spread exactly 0): `cap = max(rate,0)·Δt = 0` ⇒ `sc = 0` ⇒ the head FREEZES at
its handover pointing, which is what an infinitely SLUGGISH servo does too — gate 1's third direction
onto the same identity, now on the wire. ⚠ What the three keys read there is pinned so gate 3's HUD
is not left inferring it: the cap ships its AUTHORED value (**a NEGATIVE one means FROZEN, never
FAST**), the flag is LIT on every tick past the handover, and the DEMAND keeps CLIMBING (>100 °/s)
because the LOS keeps moving while the head does not. ⚠ Also pinned: the tick-2 handover transient is
`===` IDENTICAL on every arm at **72.542 °/s** — §0.2's "the peak is an artefact, never quote it" as
the POSITIVE fact behind it, and the measured reason a 60 °/s ceiling is not a bit-identity control.
⚠ And the isolation's baseline is now pinned FINITE **before** its `===` loop, so an arm that never
reached CPA could not pass it vacuously on `Inf === Inf`.

**GATE 3 (6892 → 6876)** — ⚠ **THE FIRST GATE IN THIS ARC WHOSE SUITE COUNT FALLS, AND THE DIRECTION
IS ACCOUNTED FOR RATHER THAN LEFT TO READ AS LOST COVERAGE**: ~87 new asserts land and ~103 leave,
because gate 2's per-entity "no shipped wire carries `gimbal_rate_dps`" sweep collapses into ONE
`carriers == ["slice35_rate.yaml"]` assert — strictly stronger, since it pins the COUNT and the OWNER
and a second wire growing the key now fails. Ships ONE wire (`scenarios/slice35_rate.yaml`, unlike
slice 34's PAIR — the whole claim lives INSIDE one slider's domain, so the lesson is a DRAG), the
`gimbal_rate_view` marker, a new HUD branch + verdict helper + instrument, a gate-3 testset, and the
verifier/UI-test pair.

⚠⚠ **GATE 3's FIRST FINDING WAS BLOCKING AND FIRED BEFORE THE YAML WAS WRITTEN (advisor): THE AUTHORED
WINDOW'S NUMBER RESTED ON A COARSE GRID OF A QUANTITY THIS SLICE HAD ALREADY MEASURED TO BE
NON-MONOTONE IN BOTH SLIDERS.** Gate 2's 19.279° came from 7 R̂ × 5 rates; a student drags two
CONTINUOUS sliders, and the interior wrinkles (§0.4's −0.16 row, §2's 13.244-at-15 vs 12.828-at-8) are
exactly where a corner sweep says nothing. Re-measured on **184 cells** (R̂ ∈ [−0.36, −0.03] on a 0.015
step × rate ∈ {8, 10, 12, 15, 20, 25, 40, 60}, window REMOVED so the requirement is READ and never
CLIPPED): ⭐ the coarse answer SURVIVED — the surface is maximal at the CORNER (R̂ = −0.03, rate = 8)
at **19.279°**, the interior all well under it, worst head travel **24.602°** against a 30° stop. ⇒
`gimbal_fov_deg` is AUTHORED at **25.0** (clearing the domain max by 5.7°, 1.30×) and deliberately NOT
at 30.0, because the window and the stop are read against two DIFFERENT angles and equating them
invites the pairing slice 34's HUD exists to prevent. ⚠ The verifier does not trust the grid: it
asserts `out == 0` AND `off_max < window` on EVERY arm and **DERIVES "the corner IS the maximum" from
its own 12 arms** before cross-checking 19.279, which is labelled a MEASURED constant at both sites.

⚠⚠ **SECOND FINDING — THE MARKER-HOLE RE-CHECK THE PLAN DEMANDED CAME BACK *NEGATIVE*, AND THE
FAILURE IT PREVENTS IS AN *INVISIBLE SLICE*, NOT A WRONG NUMBER.** Slice 34's marker plugged a REAL
hole (a loader refusal re-routing its wire into the radome cascade, confidently wrong about the
SUBJECT). Here a slice-35 wire is a slice-34 wire PLUS one key: the loader refuses nothing extra,
`gimbal_view` is raised, and the branch it selects is still about the HEAD. ⇒ `gimbal_rate_view` is a
**BRANCH SELECTOR**, and that distinction is written into four files so the next slice does not learn
the wrong rule. What it selects is the half slice 34's HUD cannot say: that HUD pairs the tracking
error against the DETECTOR WINDOW, authored WIDE here and never binding, so it would report a
comfortable budget, name the INDEX and never mention the SERVO — **every number TRUE, the slice
invisible**. ⭐⭐ AND ON ONE STATE IT IS WORSE THAN SILENT: when a slow servo has BOUGHT the ring down,
slice 34's helper reads "SELF-INDEXED — the loop is quiet", **crediting the INDEX for a quiet the
BANDWIDTH paid for** — the exact inversion of the lesson, and the sharpest tooth in the UI test (the
two helpers are called on the SAME numbers and asserted to DISAGREE). ⚠ A handshake marker rather than
a telemetry value-guard, because `gimbal_rate_dps` ships FINITE_CEIL on a slice-34 wire and a guard
would be a magic-number compare against 1e9. ⚠ The BUTTON needs no edit at either site (slice 33's
finding, THIRD occurrence).

⚠ **THIRD FINDING — A VERIFIER TOOTH THAT PASSED 12/12 WAS A TAUTOLOGY** (advisor, post-green). It
counted frames where the shipped `head_rate_sat` disagreed with the shipped demand-vs-cap and claimed
that agreement LICENSED the HUD's three-number line. The kernel branches on `head_dem > max(rate,0)·Δt`
and the seam ships `rad2deg(head_dem)/Δt` beside the cap: **the same comparison rearranged, from the
same two floats** — convention 11's rtol-`≈0` trap in a new shape. The counter is KEPT with its claim
downgraded to what it is (a units-regression check on the seam), and the architectural reason the
client may not re-derive the predicate is argued at the HUD instead. ⭐ **THE TOOTH WITH CONTENT IS THE
ZERO**: a demand of EXACTLY 0.0 is the HANDOVER tick or a head HOLDING with no error signal, and it
carries a flag of 0.0 — so `head_rate_sat` reads FREE on a broken arm for precisely the reason `rms r`
reads QUIET there. The verifier now asserts ZERO such band frames on every arm, which is what makes
`sat_band` and `dem95` measurements of a SERVO. ⚠ One-sided, and the file says so.

**THE WIRE** — seed 32, the glass/head/geometry held to slice 34's digit, window 25.0 AUTHORED, R̂ =
−0.03 (OPENING ON THE DISEASE, slice 33's default; slice 34's departure does NOT transfer, since 34
opened quiet only to keep a stability verdict off a windowed arm), servo 40 °/s (INTERIOR, so the knob
drags BOTH ways). **S35V, 12 arms, 8 phases, green first run and reproducing gates 0/2 to the digit:**
OPEN rms r 0.86263 RINGING with `sat_band` 65.19 % and demand p95 **110.194 °/s against a 40 cap**,
miss 10.947; REPLAY max|Δpos| **0.000000**; ⭐⭐ TRADE 60→8 °/s gives rms r 0.88479 → 0.38556 (**2.29×,
MONOTONE across all five rungs**) while `off_band` grows 5.915 → 12.825 (**2.17×**), the interior dip
PINNED POSITIVELY; ⭐⭐ SPLIT `sat_band` **0.00 % vs 96.98 %** at one 8 °/s servo; ⭐ RULE at
`radome_slope_worst` the requirement moves **0.0019°** across the whole rate domain with the limit
binding 0.00 % at both ends; ⭐⭐ DEMAND **0.562 → 32.418 °/s = 57.7×** across slice 34's own bracket;
WINDOW corner 19.275° and `out = 0.00 %` on all 12; FLOOR R̂ = −0.36 quiet with the servo free.
**S35UI** 10 teeth + an 18-way guard, and all 20 prior UI tests re-run green. **Smoke-load** DONE.
**TWO SHOTS** at tick 9600, both aimed at the CLAIMED branch and verified against the client's own
instruments BEFORE the window opened: "SERVO PEGGED — and still RINGING" (demand 109.8 vs 40, duty
70 %, peak 1.257) vs "QUIET, BOUGHT WITH BANDWIDTH" (demand 31.9 vs 8, duty 91 %, peak 0.154).
⚠⚠ **SHOT B HAD TO BE RE-TAKEN** — the first harness sent a raw `set_param`, which moves the PHYSICS
while the slider handle and its label keep the OLD numbers: a capture showing a missile flying 8 °/s
under a slider reading 40, **a LYING PICTURE on a green run**, and slice 19's press-the-button lesson
recurring in a new widget. ⚠ The new client instrument is a THIRD SHAPE beside slice 27's peak-hold
and slice 32's latch — an **EMA DUTY**, earned because a rate limit binds on a FRACTION of ticks
(8.2 / 65.2 / 97.0 %), so an instantaneous read would flicker with the ring and a latch would go true
on every arm and stay; all three are INDEPENDENT `if` blocks and here all three keys ship on EVERY
frame (unlike slice 34's mutually-exclusive pair), so a chained dispatch would freeze one outright.

Class **4a** (the ELEVENTH consecutive RNG-live slice — a deterministic servo bound on an existing
measurement, 2 randn/tick, the seed load-bearing). **KNOB, not rung**; the button stays DROPPED (the
11th). Plan + full measured tables in `docs/plans/slice35.md` (§0, §1, §2, §3); probe scripts in
`M:\claud_projects\temp\slice35\`.

---

## Slice 36 — THE HANDOVER BASKET

**Slice 36 — THE HANDOVER BASKET: THE CHEAPEST PLACE TO HAND A SEEKER ITS TARGET IS NOT AT THE
TARGET** — **COMPLETE** (2026-08-10, 6876 → 6988 → 7057 → 7067 → **7222**), all four gates green. Slice 32's P5, promoted by slice 34 to a live constraint and sharpened by slice 35 into the
strongest remaining candidate of the gimbal family. Since slice 34 the head has been handed its
target PERFECTLY — tick 1 initialises it to the clamped truth look angles, on a path whose whole
thesis is that the head never sees truth. Slice 36 makes that handover an AUTHORED SIGNED ERROR
(`gimbal_handover_err_deg`), and ⭐⭐ **THE OPTIMUM IS NOT ZERO**: the body-frame LOS is not a fixed
target but travels **+18.11° → −15.15°** (a 33.2° excursion THROUGH ZERO) as the missile swings onto
the collision course, so the requirement is a **V** — left arm `|err|` EXACTLY (the tick-1 peak,
before the servo moves), right arm the CHASE COST — and the cheapest basket is biased toward where
the LOS is GOING. The argmin walks −2 → −4 → −8° as the servo slows 60 → 8 °/s. Full gate-0/1 detail
and every measured table in `docs/plans/slice36.md`; probes in `M:\claud_projects\temp\slice36\`.

**GATE 2 (6988 → 7057, +69) — the seam's two keys, the loader, and a THIRD key measured and
dropped.**

⭐⭐ **THE GO/NO-GO CAME BACK NEGATIVE, AND THAT IS THE GATE's FIRST FINDING** (advisor, blocking,
run BEFORE the key was written). The requirement is a MAX OVER THE APPROACH, so the core holds it as
a running maximum (`head_off_peak_deg`) — and the tempting justification was slice 33's gate-3
finding, THE EMIT GRID UNDER-READS THE EXCURSION. ⚠⚠ **It would have been a BORROWED CLAIM.** Slice
33 was entitled to say it because its under-read (0.016°) was WIDER than the band that decided its
verdict (0.011–0.05°); measured here on the cells where a verdict actually turns — err 0 / 12 °/s
reads 8.84016 per tick against 8.83704 per frame, a **0.00313° gap against a 1.1598° margin =
0.27 %** — and 0.10 % / 0.03 % at err −4 and −6. The frame grid also **agrees with the ticks on the
break verdict in every cell** (0/10579 vs 0/661 held; 7302/7919 vs 456/494 broken). ⇒ the key stands
on **CONVENTION 13** instead: a max over ticks is not a thing a client receiving one tick in sixteen
can form at all, whatever the sampling error happens to be. ⭐ And the MECHANISM for why it could
never have stood on slice 33's is slice 35's own knob — a RATE-LIMITED head cannot move more than
`rate·emit·dt` between frames (0.128° at the shipped 8 °/s and `emit_every: 16`), so **the servo
limit that CREATES the requirement also BOUNDS how much a frame grid can hide of it**; measured over
rate × emit ∈ {8, 25, 60} × {16, 64, 250} the gap never exceeds 3.6 % of that bound. *General: when
a later slice reaches for an earlier one's finding, re-run the comparison that ENTITLED the earlier
slice to it — the finding may be true and still not yours.*

⚠⚠ **AND A KEY WAS DRAFTED, MEASURED AND DROPPED — its whole value and its whole defect are the
same sentence.** A signed peak MARGIN (slice 33's `seeker_fov_margin_deg` shape) would go negative on
the first tick the window is breached and **never recover**, which reads as slice 32's client-side
LATCH derived and core-owned. But slice 34 measured that EVERY held arm leaves its window at
r = 0.18–8.55 m as the LOS swings past, and **a peak cannot forget**: reproduced here, the would-be
latch fires on 100 % of arms **including every hit** (the 0.191 m arms latch for their last tick).
⇒ the verdict stays with `gimbal_valid`, which is per-tick and RECOVERS when the geometry does, and
slice 32's latch stays the client's to hold over it. **TWO keys ship, not three.**

⚠⚠ **THE PEAK IS AN APPROACH QUANTITY, AND THIS IS THE ENDGAME SPIKE IN THE ONE TELEMETRY SHAPE FOR
WHICH IT IS IRREVERSIBLE.** `head_off_peak_deg` reads the clean requirement **BIT-IDENTICALLY from
r = 3000 m to r = 200 m** (8.84016 / 8.09069 / 2.11192 on the three cells) and then runs to
**179.4998° at CPA on every arm, hit or miss** — the target is simply behind the head by then. An
instantaneous key spikes there and recovers; a peak-hold cannot. ⇒ a reader takes it AT A RANGE,
never at the end ([[ewsim-missile-verifier-sampling]], new quantity), and **gate 3 inherits the
display decision** — a HUD that prints the raw key past CPA is a lying picture (slice 19's class).

⚠⚠ **THE TWO-RUN DISCIPLINE's FIFTH QUANTITY IS NOW SHIPPED, AND IT FAILS LARGE** — the opposite
direction to slice 34's. On a windowed/broken arm the head holds while the LOS leaves, so the peak is
the POST-BREAK RUNAWAY: 104.56 / 65.79 / 73.77° against free-window requirements of 12.35 / 10.00 /
18.00. Slice 34's `head_angle_deg` froze plausibly-but-TOO-SMALL; this one runs away. Every
requirement in the testset is read off a FREE-WINDOW arm and the file says so.

⭐⭐ **`_parse_knobs` GAINS THE FIRST BY-NAME REFUSAL, AND THE REASON IS AN ASYMMETRY WORTH THE
LINE.** `gimbal_handover_err_deg` is consumed exactly ONCE, at tick 1, and `:head_az` is rewritten
every tick after — a slider on it is dead in the hand (slice 19's `speed` class, the 5th in this
arc). ⚠ What is NEW is that the existing guard would NOT have caught it: `_parse_knobs` refuses a
knob whose comp key does not exist, which is how 19's `speed` and 21's launch altitude were caught —
**BY ACCIDENT, because neither is a comp key at all**. This one IS a comp key when authored, so the
declaration loads cleanly and ships a live slider onto a number nothing reads again. A constraint
stated in a policy is not enforceable where the policy cannot reach (slice 34 gate 2); this is where
it reaches. ⚠ ONE KEY BY NAME (`_DEAD_KNOB_KEYS`), deliberately not a registry, with the MIRROR
pinned — `gimbal_rate_dps` still declares cleanly on the same scenario.

**THE LOADER JOINS, IT DOES NOT REFUSE.** The key enters the EXISTING
`("gimbal_stop_deg", "gimbal_fov_deg", "gimbal_rate_dps")` validation loop (slice 35's precedent —
one source, no drift), inheriting presence-gating on `gimbal_tau_s` and the non-finite refusal. ⚠ The
loop's slice-attribution ternary needed a THIRD arm. ⚠⚠ The non-finite refusal is **not hygiene**
(gate 1's inherited item): `head_clamp` handles a NaN *stop* but not a NaN *az*, so `deg2rad(±Inf)`
would reach the kernel as a non-finite azimuth, make the radial projection `Inf/Inf` and poison the
head state permanently, inside `observe!` where the session's IO-only catch drops the connection.
⚠ **NO BOUND AGAINST THE STOP**, and the reason is decisive rather than stylistic: the key is an
OFFSET on the flying `look_az_b`, so "authored beyond its own stop" is **not a load-time-decidable
quantity** — and refusing it would delete the mechanism that bounds the basket from above. Slice 35's
post-review shape applies: a degenerate the loader PERMITS, proven to LOAD (`err = 400°`) and never
FLOWN.

⚠ **BOTH DOMAIN ENDPOINTS MEASURED, AND THEY ARE DIFFERENT KINDS OF BOUNDARY** (slice 26's
post-commit rule, applied to both ends rather than one). LOWER: at `err = −18.105365°` — the negative
of the perfect handover — the head is born at azimuth **EXACTLY 0.000000°**, pointing down its own
nose in that axis, which is where a CAGED head sits; `|head|` is then a pure elevation 0.655978°.
⚠ The key does NOT go inert there (at −20° the requirement is still exactly 20.000000°), so **the
lower bound is a MODELLING choice and the plan says so** rather than implying a mechanism it lacks.
UPPER: at `+11.9°` the birth angle SATURATES on the stop (`|head|` exactly 30.000000°) and the key
GOES INERT — the requirement agrees to **5e-4° over 11.9 → 20°**, a mechanism. ⇒ the signed domain is
**[−18.1 (the CAGED coincidence), +11.9 (the STOP)]**; the two shipped wires author 0 and −6.

⚠ **THE PEAK IS CUMULATIVE ACROSS A CROSS-TOGGLE, AND THAT IS THE DELIBERATE CHOICE** (the
latent-bug class this arc has caught seven times, in a new place): `:head_az` itself persists through
a toggle off `:six_dof` — the head FREEZES rather than un-existing, and on toggle-back the seam takes
the SLEW branch off the stored angles — so a peak that reset would be the ONLY piece of head state
that did, and would read LOWER than the tracking error the head has actually had. Nothing accrues
while `_gim` is false (the update sits inside the rung gate; measured **0/500 frames** ship the key
there, and the peak returns 8.090688 unchanged).

Convention 9 is settled by MEASUREMENT and not by counting sliders (slice 27's diagonal): gate 1's
own teeth already show the authored error and the servo are **ONE axis** — the servo MOVES the
argmin (−2 at 40 °/s, −8 at 8 °/s, a 1.54× saving) — and **slice 35 is the `err = 0` row of this
slice's grid**. ⭐ The blocking re-read gate 1 demanded was run and PASSED: Finding 3's elevation pin
(`hel1 === ref.hel1`, `hypot === 30.000000`) still holds against the new tick-1 telemetry.

**GATE 3 (7067 → 7222, +155) — TWO WIRES, THE WINDOW RE-AUTHORED ON A FINE GRID, AND THE FIRST MARKER
IN THIS FAMILY THAT HAD TO PLUG A *BUTTON* HOLE AS WELL AS A HUD ONE.**
`scenarios/slice36_handover.yaml` (err = 0, the FOIL) and `scenarios/slice36_biased.yaml` (err = −6,
the wire that HOLDS) differ in **exactly one comp key** — asserted by set difference over the whole
comp dict, not by a hand-listed tuple — with `gimbal_rate_dps` the ONE live slider on both and the
default at its FLOOR (8 °/s), because the showcase OPENS ON THE DISEASE: at that servo, behind the
same 10° window, on the same seed, the perfect handover MISSES BY 3290.079 m and the biased one HITS.

⚠⚠ **THE BUTTON DROP WAS NOT FREE, AND THE PLAN PREDICTED IT WOULD BE** (a COUNT with no mechanism —
the defect slice 32 caught in its own plan). `radome_view` is keyed on authored GLASS and **this is
the arc's first no-glass wire since slice 25** (§0.2's exact inertness and §0.6's isolation are why),
while `seeker_fov_view` is refused beside a head — so BOTH of the client's drop-branches fail, the
dispatch falls through to slice 25's `seeker_axes` cycler, and the button COMES BACK, whose other
position (`:pitch_plane`) would leave the handover live beside slice 25's unrelated 2000 m blind miss.
⇒ `gimbal_handover_view` does **slice 34's job AND slice 32's** — a BUTTON hole at both client sites
(slice 26's "the drop needs BOTH", 4th occurrence) *and* the HUD branch — and slice 35's "a branch
selector, not a hole plug" **does not transfer**. ⭐ The HUD half is a STALE-READOUT defect rather than
slice 35's invisible slice: `gimbal_rate_view` IS raised here, so slice 35's block would take the wire
and its own CURE line reads `radome_slope_est` / `radome_slope_worst`, printing **`R̂ +0.000   aim
point R₀+2A +0.000`** for keys that do not exist (the 9th occurrence of that class, on another slice's
payoff line), with `_radome_qpeak` frozen at 0.0 beside it. Proven BY MIRROR in both directions.

⚠⚠ **THE WINDOW'S CRITERION IS INVERTED FROM SLICE 35's**, which is the trap of this gate: slice 35
authored its window to CLEAR the worst requirement anywhere (one number, one direction), while this one
must SIT INSIDE the requirement's range on wire A and ABOVE it on wire B over the WHOLE domain — a
TWO-SIDED margin. Re-flown over **210 arms** (rate ∈ [8, 60] on a 0.5 °/s grid × 2 wires, free window)
because the requirement is NON-MONOTONE in both sliders: wire A runs **12.34604° at 8 °/s → 2.11192° at
42.5** with the ≥-window set **EXACTLY FIVE CELLS, CONTIGUOUS and anchored at the slow end** (the
assert a 7-column sweep cannot make) and the crossing a MEASURED bracket **10.0 (10.32507°) → 10.5
(9.89727°)**; wire B has **no crossing anywhere**, worst 8.09069° (a **1.909°**, 1.24× margin) and
**FLAT at 6.00000° over 100 of its 105 cells**. ⇒ `gimbal_fov_deg: 10.0`. ⭐ The 30° STOP never binds on
either wire (`head_max` 18.11891° flat / 14.995→15.197°, i.e. 11.9° and 14.8° of margin), so slice 34's
"the stop and the window are ONE budget" stays clean and the window is the only limit in play.

⭐⭐ **THE FLOOR IS SLICE 35's NUMBER FOR A DIFFERENT REASON, MEASURED RATHER THAN COPIED** (the
copy-paste false-claim trap, closed on a number). Slice 35's 8 °/s rested on the RING — 100 % band
saturation below it and the 0-vs-97 split at exactly 8 — and **neither survives the loss of the glass**
(band saturation at 5 °/s is 895/4341 = 20.6 % here, because there is no oscillation to chase). What
bounds it is **the biased wire's own claim**: at 6 °/s its requirement is 10.523° and the track is LOST
(t = 1.167 s, miss 2398.200 m), 7 °/s being the last holding cell. ⇒ *the bias buys MARGIN, NOT
IMMUNITY* (slice 27's phrase in a third currency), and "the slider stops mattering" is a statement
ABOUT THE DECLARED DOMAIN whose floor is the measurement that makes it true.

⭐⭐ **A THIRD KEY SHIPPED AT GATE 3, BECAUSE THE HUD COULD NOT OTHERWISE DRAW THE MECHANISM AT ALL.**
Every shipped angle on the head path is a `hypot` (`look_body_deg`, `head_angle_deg`, `head_off_deg`)
and §0.4's whole finding is that **a hypot cannot show a sign** — gate 0 inferred the LOS *settling*
18.1° → 15.2° from `head_max` and the story was WRONG. `look_body_az_deg` (SIGNED, `_finite_coord`,
recomputed from `att_q`/`û_tru` beside its neighbour) puts the 33.2° crossing excursion on the wire,
where until now it existed only in a probe. ⚠ It is NOT the peak-MARGIN key gate 2 measured and
dropped: no latch in it.

⚠⚠ **THE ENDGAME ARTIFACT NOW APPEARS IN THREE QUANTITIES WITH TWO DIFFERENT GATES, AND EVERY ONE OF
THEM COST A FAILING ASSERT.** (a) `head_off_peak_deg` runs to 179.4998° per tick at CPA on every arm,
hit or miss — gate 2's finding, and the reason the client **freezes its display** at r > 200 m
(`_handover_peak_hold`, a FOURTH instrument shape beside slice 27's peak-hold, slice 32's latch and
slice 35's EMA duty). (b) The core's first excursion tooth was ungated by RANGE and read **182.02°**
(the LOS at CPA is +164.29°). (c) The verifier's was ungated on the CLOSING LEG and read **359.778°**
on a HELD arm — the azimuth wrapping through ±180° once the target is behind the missile, which is
slice 32's gate-3 correction verbatim. ⇒ read on the closing leg AND inside r > 200 m.

⚠⚠ **EVERY EXCURSION FIGURE CARRIES ITS GRID, AND THE FIRST DRAFT DID NOT** (advisor, post-commit).
**PER TICK** (gate 0 / the core suite): `+18.105365° → −15.15°`, the 33.2° the lesson statement uses.
**PER FRAME** (the verifier and both shots at `emit_every = 16`): `+18.003° → −15.179° = 33.182°`,
because the earliest azimuth a client receives is 16 ms after the handover tick and lands 0.102° below
it. The verifier's frame constant was first named `AZ_BIRTH` with a 0.2° tolerance — wide enough to hide
that gap behind a label claiming the tick-1 value, which is slice 21/25's defect in a CONSTANT rather
than a print. Now `AZ_FIRST_FRAME` + `AZ_TICK1`, atol 0.01°.

⭐⭐ **AND THE MECHANISM IS THE TWO-RUN DISCIPLINE'S SIXTH QUANTITY, WHICH THE UPPER BOUND CAUGHT**:
gated both ways, the excursion is **33.182° on an arm that HELD and 110.473° (~3.3×) on the broken
one** (frame-sampled, both) — a lost track is a runaway geometry (slice 32's inflated-lead finding and slice 29's P10a, in a
new quantity), so every excursion number is read off a HELD arm and the broken arm asserts the RUNAWAY
as the positive fact. The list of quantities that lie on a broken arm is now `rms r` / `look_max` /
`head_angle_deg` / `head_rate_sat` / `head_off_peak_deg` / **the LOS excursion**.

⭐⭐ **THE BIASED WIRE REVISES GATE 2's OWN GO/NO-GO — THE SHARPEST NUMBER OF THE GATE.** Gate 2
measured the emit grid's under-read of the requirement at 0.03–0.27 % of the deciding margin and
concluded that slice 33's emit-grid finding was a BORROWED claim, so the key ships on convention 13.
⚠⚠ Those cells all have a SMOOTH MID-FLIGHT peak. Above the bracket on the biased wire the requirement
is the **TICK-1 PEAK — an initial condition, one tick wide** — and a client receiving one tick in
sixteen never sees it: the frame-sampled instantaneous max reads **5.753 / 5.298 / 4.998° against the
shipped 6.000** at 11 / 40 / 60 °/s (0.247–1.002° under, against 0.009° on the foil). ⇒ gate 2's
verdict was right about the cells it measured and does not generalize; the rule it wrote — *re-run the
comparison that entitled the earlier claim* — applied to itself.

⚠⚠ **TWO DEFECTS THE WINDOWED SHOT FOUND AND NO TEST WOULD HAVE.** (1) Shot A's first capture printed
`handover +0.0°   body LOS az −39.18°  (first frame +18.00°)` — three LIVE, TRUE numbers whose INVITED
ARITHMETIC is a 57° "excursion" that is the runaway, with a correct verdict line right above it (slice
33's defect exactly, in a new quantity) ⇒ a new pure helper `_handover_los_text` withdraws the pair and
says **RUNNING AWAY** once the latch is set. (2) The retake ran that clause off the right edge at 67
characters ("…RUNNING AWAY sin"), the **3rd occurrence** after slices 26 and 28, so both forms are now
length-asserted at the measured ~55-character budget. ⚠ And the verifier's pass text printed as a **RAW
FORMAT STRING on a green exit** — slice 21's `%.2e` and slice 25's `%g` in a THIRD form, an
argument-count mismatch rather than an unknown specifier.

**THE FOUR PROOFS.** `net/slice36_verify.gd` — ONE file, BOTH wires, auto-detected (slice 22's shape),
`STEPS = 12800 = 16 × 800`. Wire A: foil BROKEN 3290.079 m with its peak reading 107.378° (8.7× the
real 12.346°, the two-run discipline's FIFTH quantity failing LARGE); bracket BROKEN 10 → HELD 11 °/s;
requirement 9.515 → 8.840 → 2.112° above it; two held arms **bit-identical** (max|Δpos| = 0.0, same CPA
bits — the price of the cure is EXACTLY zero); `defl_sat` 0 and `aero_sat` 0 everywhere; the band EMPTY
on every broken arm (CPA 3.3 km) and 271 frames on every held one. Wire B: HELD in all cells, 8.091° at
the floor, FLAT 6.000° to the bit, plus the one-tick under-read. Replay bit-identical on both.
`net/slice36_ui_test.gd` — 11 teeth, NINETEEN-way guard. Sandbox smoke-load → `EWSIM_SERVER_DONE`.
TWO windowed shots at r ≈ 4.5 km: **A** "PERFECT HANDOVER — TRACK LOST" / `peak head err 54.0° —
POST-BREAK, NOT a requirement` / `LOS az −39.18° — RUNNING AWAY` / `head: HOLDING`; **B** "BIASED
HANDOVER — track HELD" / `requirement (peak) 8.09° vs window 10.0°` / `LOS az −12.49° from +18.00°` /
`demand 23.5°/s ← PEGGED` / `head: TRACKING`. ⭐ Shot B's servo is PEGGED on a HELD arm — the bias made
the requirement an initial condition, so a saturated servo costs it nothing. Class **4a** (the TWELFTH
consecutive RNG-live slice); button DROPPED (the 12th — and the FIRST that needed an edit to stay
dropped). Slices 1–35 byte-identical, proven ON THE WIRE (slice 34's and slice 35's verifiers re-run
green). Two loader/marker sweeps in `test_missile.jl` were TIGHTENED to enumerated carrier sets rather
than deleted, which is how slice 35's own "a second wire growing this key would fail here" paid off.

## Slice 37 — THE HEAD'S OWN GYRO — the servo's reference frame

**Slice 37 — THE HEAD'S OWN GYRO: A SPACE-STABILIZED SERVO GIVES BACK THE MARGIN THE POSITION
SERVO'S LAG WAS QUIETLY BUYING** — **COMPLETE** (2026-08-17, 7222 → 7323 → 7394 → 7396 → **7496**),
all four gates green. The deferral slice 34 named THIRD, and ⚠⚠ **ITS OWN WORDING WAS REFUTED BEFORE
ANY PROBE RAN**: "a rate-stabilized head measures inertial LOS rate DIRECTLY, the classical reason
gimbals exist" is ALREADY TRUE of the shipped model — `missile.jl:1652` is `az_el(û_tru)`, NOT
`look_angles(att, û_tru)`, so this seeker has reported INERTIAL angles since slice 25 and the α-β
tracker an INERTIAL rate. What is body-referenced is the **SERVO**, and the live claim is its
REFERENCE FRAME. ⭐⭐ **STABILIZING IT REMOVES MARGIN — THE CLASSICAL REASON GIMBALS EXIST INVERTS ON
THIS WIRE** — because the position servo's LAG was doing stability work nobody asked it for: it
LOW-PASSES the missile's own body motion out of the radome's INDEX, and slice 26's limit cycle lives
at 1.7–2.1 Hz, exactly where a τ = 0.05 s filter is worth 12–16 % of gain and ~30° of phase. Full
gate-by-gate detail in `docs/plans/slice37.md`; probes in `M:\claud_projects\temp\slice37g{,2,3}\`.
⚠ PART I of that plan is a DIFFERENT candidate — MEMORY TRACK / RE-ACQUISITION — **KILLED at gate 0**
(a break in this arc is not an episode but the rest of the flight; what makes it terminal is the
ESTIMATOR's frozen rate, not where the head points, so the cure 34/35/36 all banked was MIS-LOCATED).

**GATE 3 (7396 → 7496, +100) — the wire, the button that comes back, and a number that lied.**
⭐⭐ **THE DEMONSTRATION IS ONE BUTTON PRESS ON A DESIGN THAT WAS ALREADY GOOD**: at R̂ = −0.18 (slice
34's own shipped design) the body-referenced head is QUIET (`rms r` **0.01195**, intercept 2.084 m)
and one press — same glass, same believed slope, same seed, same servo, same handover — makes the same
missile RING at **1.00094**, **83.8× frame** (85.4× per tick), and it STILL HITS (2.689 m). ⭐ The
onset is found TWICE, once per servo frame, quoted BRACKET TO BRACKET: body **(−0.170, −0.165]** at
4.32×, space **(−0.210, −0.205]** at 9.09× — and the two are asserted DISJOINT FROM BOTH SIDES (across
the space bracket the body rung is still on its plateau; across the body bracket the space rung is
already ringing), which is what makes it ONE ladder walked twice rather than two readings of one
boundary. ⚠⚠ **THE ONSET RULE IS THE LARGEST SINGLE-STEP RATIO AND STAYS THRESHOLD-FREE** — gate 0's
advisor catch still doing work, and load-bearing here: the body rung reads 0.17284 at −0.165, an order
of magnitude above its own plateau AND BELOW the arc's 0.30 ring line, so a threshold would have
mis-bracketed it. The whole ladder is printed so a reader can redraw the line, and the ~40–45 % of
margin given back is quoted as a RANGE while the ORDER of the rungs is what is asserted.

⭐⭐ **THE SLIDER'S FLOOR IS SLICE 30's AIM POINT AND IT IS WHERE THE BUTTON GOES DEAD** — body 0.05901
against space 0.06030, **1.022×**, both quiet ⇒ aim R̂ at the glass's worst-case slope and THE
ARCHITECTURE DOES NOT MATTER. Slice 30's rule pays a **FOURTH** time (33 = FOV, 34 = detector window,
35 = servo bandwidth, 37 = the head's REFERENCE FRAME), and the proof is a control that visibly stops
working. ⚠ **THE CEILING'S OBVIOUS JUSTIFICATION WAS TESTED AND REFUTED**: the body rung saturates its
40 °/s limit on up to 64.6 % of band ticks past −0.14, so the limit might have been ATTENUATING its
ring (slice 35's mechanism leaking in) — re-flown with the limit REMOVED the body arm's `rms r` moves
by at most **1.04×** anywhere. The ceiling instead rests on the arm where BOTH rungs ring, the only
kind on which the demand comparison is legal at all: there the space head RINGS 1.70× HARDER AND ASKS
ITS SERVO FOR 3.15× LESS PEAK SLEW (17.650 vs 55.681 °/s, 0.00 % vs 17.5 % saturated) ⇒ **the
body-referenced servo's demand is almost all BODY MOTION, not target motion** — and ⚠ that does NOT
license "the stabilized head is the cheaper build": cheaper in SERVO BANDWIDTH, dearer in STABILITY
MARGIN, slice 35's one-knob-two-bounds shape moved onto the ARCHITECTURE.

⭐⭐ **THE CLIENT FINDING IS A BUTTON INVERSION, AND IT REVERSES TWELVE SLICES OF PRECEDENT.** Slices
26–36 each had no rung to cycle, so `radome_view` / `seeker_fov_view` / `gimbal_handover_view` all
HIDE the shared button and 32/33/34/35 rode one for free. `:seeker_head` IS a rung — the first on this
button since slice 25 — and this wire raises **three** of those drop markers, so a NEW
`gimbal_frame_view` exists to **UN-DROP** it, checked FIRST at both sites. ⚠ The rule is written at the
marker: it is NOT "a gimbal marker drops the button"; it is *the button shows what there is to cycle,
and these wires mostly have nothing*. ⚠ **GATED ON THE FIDELITY, not a comp key — the first in this
family** (the rung reuses slice 34's head verbatim) — and on the KEY, never value-guarded on
`:space_stabilized`, since the wire OPENS on `:body_referenced` and a value guard would hide the button
on exactly the arm the showcase starts from. ⭐ **THE MIRROR IS THE EXACT INVERSE OF SLICE 36's**:
there, stripping the marker made a button APPEAR that had to be dropped; here it makes it VANISH.
`_fid_kind` takes a NEW value `"seeker_head"` (free — slice 21's "which drawing gate needs this kind?"
re-checked, and **none did**), so the label needs its own `_update_fid_btn` arm or the `_:` default
prints `prop: ?` on a wire with no propagation rung.

⚠⚠ **THE HUD HALF IS AN INVITED SUBTRACTION — slice 36's gate-3 defect in a new quantity.**
`head_rate_dps` keeps its slice-35 name across this button and MEANS A DIFFERENT THING ON EACH SIDE OF
IT (BODY-frame demand, which includes tracking out the missile's own rotation, against INERTIAL-frame
demand with body motion already rejected). At the slider's ceiling the press makes it FALL 3.15× while
the ring RISES 1.70×, so slice 35's unlabelled line would invite exactly the "cheaper build"
conclusion the seam forbids ⇒ **the frame is printed INSIDE the same string as the number**, and the
UI test asserts the same demand renders DIFFERENTLY on the two rungs.

⭐⭐ **AND THE SHOT CAUGHT A NUMBER LYING — the finding only a capture could produce.** The first pair
of shots rendered the branch correctly and still could not be compared: `ring r −0.019 rad/s` on the
QUIET arm against `ring r +0.021 rad/s` on the one ringing **84× harder**, because a limit cycle
crosses zero twice per cycle and one frame catches it wherever it happens to be. Slices 26–36 all drew
the live rate beside a peak-hold TAG and that was fine — **nothing on those wires invited a
frame-to-frame comparison; here the whole demonstration IS two frames either side of one press.** ⇒
the decaying peak's **value** now sits beside the live rate (**0.02 against 1.08, ~54×**), with both
live values still on screen. ⚠ The same pair caught a **59-character** cure line against the measured
~55 budget (the right-edge overrun's 4th occurrence after 26/28/36), shortened to `← button goes dead`
— also the truer phrase. Both lines were extracted to pure helpers, which is the only reason they are
now pinned by width at all (convention 14).

⚠⚠ **A FRAME VERIFIER STRUCTURALLY CANNOT SEE THE PRESS, AND THE FRAME GRID MISREADS IT.** On the emit
grid the space→body press shows a **0.939°** step in `head_angle_deg` (~16× a normal frame) — which
reads exactly like the head being RE-BORN, the failure the seam's stamp exists to prevent. It is not:
per tick the head moves **0.0074°**, ~9× LESS than the tick before, and the frame figure is the SPACE
rung's own body-angle motion (0.0649 °/tick — a head held inertially is carried by the rotating body at
unity gain) accumulated over 16 ticks. ⇒ **the press is visible in the RATE, not the POSITION, and it
goes the other way**: the carry-along STOPS. [[ewsim-missile-verifier-sampling]] in a new quantity, so
`slice37_verify.gd` asserts NOTHING about a step across the press and the continuity tooth lives in
`test_missile.jl`, both directions, against gate 2's measured 2.696° counterfactual.

**THE FOUR PROOFS.** `net/slice37_verify.gd` — 19 arms, `out == 0` on every one (the precondition that
makes each `rms r` a stability read), `defl_sat` 0 everywhere, replay bit-identical **on BOTH rungs**
(a replay proven only on the body arm would leave the new branch unproven where it executes), and
⭐⭐ a MID-RUN PRESS arm — the one path gates 0–2 could not cover, since they toggled in Julia. ⚠⚠ It
needed a TWO-LEG arm because `_serve_session!` **drains every queued command before it steps at all**,
so `[step K, set_fidelity, step N−K]` sent back-to-back applies the toggle at tick 0 and silently
measures a from-launch arm. `net/slice37_ui_test.gd` — 11 teeth, 20-way value-guard, the inverse
mirror, and the button asserted to send `set_fidelity` (never `set_param`) with the LABEL moving with
it (slice 19's lying-picture lesson). Headless `Sandbox.tscn` smoke-load reached `EWSIM_SERVER_DONE` ⚠ **and, after the gate-3 review, with GODOT's OWN stdout captured and swept for `SCRIPT ERROR`/`Parse Error`/`GDScript backtrace` — the first run asserted only the SERVER's half, and that is the weaker half here: `Sandbox.gd` carries 271 of this slice's new lines and its HUD block runs ONLY from `_draw`, which never executes headless, so a defect there would connect, handshake and pass green. ⭐ The sweep is a real negative (the UI-test run in the same session printed `GDScript backtrace` lines through that same channel), and the SHIPPED bytes were re-loaded separately because the first run still carried the temporary port. ⚠ It still proves PARSE only — a runtime fault inside `_draw_frame_hud_lines` remains the two shots' to catch.**
TWO windowed shots, retaken after the ring-line fix. Class **4a**, the THIRTEENTH consecutive RNG-live
slice; the rung is live-settable with NO `set_fidelity` guard, MEASURED rather than assumed (a mid-run
press leaves the RNG state EQUAL to the never-pressed run's while the trajectories differ by 2.000 m).
⭐ Gate 2's own `@test isempty(carriers)` was written to be tightened here and was
(`== ["slice37_frame.yaml"]`); two slice-35 carrier enumerations fired as FAILING asserts and were
correct to — the second time that list has earned its keep. Slices 1–36 byte-identical.
⚠ **THE PROOFS FIRST RAN ON PORT 8770** — an unrelated `python` process (PID 40916) held 8765 and it
was not this project's to kill. The port is one integer constant, reverted immediately after those
runs. ✅ **THE 8765 RE-RUN IS DISCHARGED (2026-08-17, next session)**: that process had exited, and
BOTH server-driven proofs were re-run on the default port off the SHIPPED bytes — `slice37_verify.gd`
green (`S37V OK`, exit 0, all 19 arms, reproducing 0.01195 / 1.00094 / 83.8×, both brackets and the
1.022× dead button at the aim point TO THE DIGIT), and the `Sandbox.tscn` smoke-load green with BOTH
halves captured (`EWSIM_SERVER_DONE`; Godot stdout = the version banner and nothing else, stderr
EMPTY, zero `SCRIPT ERROR` / `Parse Error` / `GDScript backtrace`). Nothing differed but the integer.



## Slice 38 — AN IMPERFECT HEAD GYRO: SLICE 37's MARGIN IS A GYRO SPEC (2026-08-17)

**Status: SHIPPED AND COMPLETE, all four gates. Suite 7496 → 7564 (+68). Slices 1–37 byte-identical,
proven ON THE WIRE (slice 37's verifier re-run reproduces 0.01195 / 1.00094 / 83.8× and both onset
brackets to the digit).** Full plan and every gate-0 table in `docs/plans/slice38.md`; raw probe
output in `M:\claud_projects\temp\slice38g\`.

**THE LESSON.** Slice 37 showed that stabilizing the seeker head in space REMOVES stability margin,
because the position servo's LAG had been quietly low-passing the missile's own body motion out of the
radome's INDEX. That result rests entirely on a PERFECT gyro — the shipped stabilized head rejects body
motion at EXACTLY unity gain at every frequency, because the model simply STORES the inertial angles,
and slice 37 named that §1 approximation FIRST among its own deferrals. Give the gyro a scale-factor
error and the rejection LEAKS (`ω − ω̃ = −s·ω − b`, so the pointing DRIFTS), and slice 37's stability
boundary WALKS with gyro quality. ⇒ **THE TWO ARCHITECTURES SLICE 37 SHIPPED AS A BUTTON ARE THE TWO
ENDS OF ONE HARDWARE SPEC, AND A WORSE GYRO IS A MORE STABLE MISSILE.**

⭐⭐ **THE HEADLINE, ON SLICE 37's OWN 0.005 GRID UNDER ITS OWN THRESHOLD-FREE LARGEST-STEP RULE, EVERY
BRACKET INTERIOR:** s = 0 → **(−0.210, −0.205]**, which is slice 37's SPACE bracket EXACTLY; −0.02 →
(−0.205, −0.200]; −0.05 → (−0.200, −0.195]; −0.20 → (−0.185, −0.180]; −0.40 → (−0.175, −0.170]; a DEAD
gyro (s ≤ −0.80) → **(−0.170, −0.165]**, which is slice 37's BODY bracket EXACTLY. Its whole margin is
the 0.040 of R̂ (8 cells) between them ⇒ **−5 % of scale factor — an ordinary cheap-MEMS part — gives
back a QUARTER of it and −20 % gives back FIVE EIGHTHS.** ⭐ The domain FLOOR is a measurement: the walk
is INVISIBLE at 1 % and RESOLVES at 2 %, so the engineering claim rests on a mid-grade part.

⚠⚠ **TWO PREDICTIONS WERE REFUTED AT GATE 0 AND BOTH ARE LOAD-BEARING.** (1) The index gain is NOT
`|1+s|` and `s = −1` is NOT the frozen-index degenerate: it walks 1.00000 → 0.88608 with phase 0° →
−27.578° at 1.7 Hz, landing on the body rung's own 0.88405 / −27.561°. The error was conflating *the
drift cancelling body motion* with *the servo being off* — a head carried along by the body is STILL
SLEWED by its servo with lag τ, which IS the body-referenced rung. (2) The BIAS was to be the headline
and is the WEAK half: it needs ~10³× a bad real gyro to move anything (103 °/hr moves `rms r` by
0.00064), while the scale factor's claim rests on a real part. It ships as the SECOND CURRENCY — a
TWO-SIDED knob (43.2× in `rms r` while the tracking error moves the OTHER way, 2.70° → 0.96°) — and
⭐⭐ **SLICE 30's RULE PAYS A FIFTH TIME**: at the aim point the bias moves the tracking error 3.9× and
the ring moves **1.0×** (0.0598–0.0602 across the whole domain), the first time the rule buys off a
SENSOR error rather than a design choice.

**THREE GATES PASSED BY MEASUREMENT.** BLOCKING (bias vs the LEAD — does it collapse onto slice 32's
axis?): the lead holds at 14.59–14.68° across the whole bias sweep while `head_off` moves 2.84 → 1.31
and the verdict moves with it. THE `(s, R)` COLLAPSE: `s = −0.2` reads 0.29353 against 0.01453 for
glass scaled ×0.8 (**20.2×**) and 0.98063 for glass AND belief scaled (**3.3×** the other way) — `s`
adds PHASE, and scaling a slope cannot. ⚠⚠ THE RUNG BOUND HELD ONLY IN THE NARROW FORM AND THE PLAN
SAYS SO: the walk REACHES the body bracket at a dead gyro, so NO CLAIM MAY BE MADE IN THE RING METRIC;
what survives is 1.556 m of trajectory separation on the ringing arm (0.089 m quiet, against 40.29 m
for the honest pair), two distinct code paths, and a gyro reading ZERO physically BEING an unstabilized
head — a correct degenerate, not a false fidelity.

**GATE 1** — `frames.jl` gains `head_drift_inertial`, a COMPOSITION of slice 31's `gyro_reading` that
returns its input BIT-FOR-BIT at a zero residual (so an authored `s = 0` is byte-identical to the keys
being absent BY CONSTRUCTION). ⚠⚠ **TWO WRONG ORACLES, BOTH OF WHICH LOOKED LIKE TOLERANCE PROBLEMS**:
`acos` of the dot product is precision-limited to ~1.2e−04 rad on a 2e−4 rotation (it also hid the
linearity result at ~1e−8, which the chord formula reads as 1.7e−12), and predicting the swept angle as
`|Ω|·dt` is WRONG BY CONSTRUCTION (a vector rotated about an axis moves by `|Ω|·dt·sin ψ`) — that read
24 % on the widest cell, and swapping the first oracle left the number BIT-FOR-BIT UNCHANGED, which is
what exposed it. Against an independent Rodrigues recompute the kernel is exact to **3.554e−16**.

**GATE 2** — one call in the `elseif _stab` arm, three loader keys (`head_gyro_scale_err` /
`head_gyro_bias_y` / `_bias_z` — ⚠ NOT slice 31's `gyro_*`, which are the AUTOPILOT's gyro, a different
sensor on the same missile), three telemetry keys named by WHICH SENSOR. **THE ORDERING IS
DRIFT-THEN-CLAMP** and the seam says so: the head cannot drift THROUGH its own gimbal limit, pinned on a
wire where the stop binds on 5572 ticks with `over` at 1.78e−15. ⚠ **A GUESS BESIDE IT WAS WRITTEN AS AN
ASSERT AND REFUTED BY IT** — the draft claimed a perfect-gyro arm reaches that stop LESS often, "so the
binding is the drift's doing"; it is not (5582 against 5572, very slightly MORE), so the testset proves
the ORDERING INVARIANT and nothing about causation, and now says exactly that. **INERT ON THE BODY RUNG
BY PLACEMENT, NOT BY A GUARD** (`max|Δpos| == 0.0` with the keys authored at ringing values).

**GATE 3** — ONE wire (`scenarios/slice38_head_gyro.yaml`), ONE slider, and it OPENS ON THE STABILIZED
RUNG, the opposite of slice 37's choice and for the mirror reason: the slider's job is to make a
RINGING missile quiet by making its gyro WORSE, so the wire must open where the ring is. Verifier (14
arms, `out == 0.00 %` on every one): **0.63736 → 0.01967, 32.4×**, both hitting; the ladder MONOTONE
across all 9 cells (asserted CELL BY CELL — a first for this family after 19/20/22/28/35/36); the
transition a SINGLE 18.8× step across s ∈ (−0.030, −0.050] ⇒ **the gyro spec has a KNEE**; the ceiling
ringing HARDER than perfect (0.98525) — the half of the axis BEYOND slice 37's rung; and ⭐⭐ **the
slider BIT-IDENTICALLY INERT on the other side of the button** (`max|Δpos| = 0.000000000 m`, `rms r`
equal to nine digits). Replay bit-identical at BOTH ends. Class **4a**, the 14th consecutive RNG-live.

⭐⭐ **THE CLIENT: A MARKER WHOSE ONLY JOB IS THE HUD** (`gimbal_gyro_view`, the 8th of this family, the
second after slice 35 to be HUD-only, and the advisor predicted it before any client code). A
slice-38 wire raises FOUR earlier route markers and the BUTTON is already correct — correct for a
REASON, since `:seeker_head`'s two rungs are the two ENDS of this slider's axis. What is wrong without
it is the HUD: slice 37's block would take the wire and EVERY KEY IT READS IS LIVE HERE, so it would
print a fluent, entirely TRUE frame-comparison verdict — plus a cure line naming a slider this wire
does not have — above a lesson about the SENSOR. The stale-readout class's WORST form, its ~10th
occurrence. The mirror proves the branch is a SWITCH not an `or`: strip the marker and the BUTTON is
unchanged while only the HUD falls through. ⭐⭐ **AND THE STATE ONLY THIS BRANCH CAN NAME IS A DEAD
KNOB** — on the body-referenced rung the slider is inert, so the HUD says so rather than leaving a
student to drag a live control and watch nothing: **a live control that does nothing is the
stale-readout class in a NEW form, not a stale number but a dead one.**

⚠⚠ **THE SHOT CAUGHT A DEFECT THE UI TEST HAD JUST PASSED: TWO WIDTH BUDGETS, NOT ONE.** The first pair
of captures ran BOTH new headlines off the right edge (50 and 47 chars) while the width tooth PASSED,
because it pinned the ~55-character budget the BODY lines are drawn against at 15 px. The headline is
drawn LARGER and from a different origin, so its budget is ~30 — slice 37's longest is exactly 30, and
every label in this family had quietly obeyed that without anyone writing it down. ⇒ the right-edge
overrun's **5th occurrence** after 26/28/36/37 and **the FIRST in a headline**; the two budgets are now
pinned separately. Re-taken: **`PERFECT GYRO — RINGING`** (ring r −0.817, peak 1.12, leak 0 %) against
**`WORSE GYRO — loop QUIET`** (−0.014, peak 0.03, leak 5 %).

⚠ **FOUR CARRIER/MIRROR ASSERTS FIRED AND WERE RIGHT TO** — slices 35 and 37 each enumerate which wires
carry their keys and each mirrors "no other wire raises my marker"; a slice-38 wire legitimately
carries both, the THIRD time slice 35's list has earned its keep. Widened with the reason, not deleted.
Four proofs green (verifier, 10-tooth UI test, smoke-load with BOTH halves captured, TWO shots), and
slices 34/35/36/37's UI tests all re-run green.

**Deferred (NAMED):** a NULLING-LOOP head servo (the other classical architecture, where the scale
factor goes nearly inert and the bias carries everything — the natural A/B) — ⚠⚠ **SINCE KILLED AT
GATE 0 (2026-08-17, 9 probes in 4 files, nothing shipped, suite still 7564), `docs/plans/slice39.md`: a nulling
loop with INFINITE LOOP GAIN is not an architecture, it is a REPARAMETERIZATION OF THE SERVO TIME
CONSTANT — `nulling(τ, s, b) ≡ feed-forward(τ(1+s), 0, b/(1+s))` measured end to end at 5.8e−09 m of
trajectory over 12 000 ticks, across four cells including `s > 0`, with the bias twin re-flown ON THE
CLEAN TREE as a pure shipped arm. The prediction that the two currencies SWAP is refuted in the
strongest available form: NEITHER exists on that rung. What survives is a design sentence (on a
feed-forward head the scale factor is a STABILITY spec; on a nulling head a BANDWIDTH spec) and a live
successor, FINITE LOOP GAIN — whose own two gates are named in the plan**; GYRO NOISE (draw-topology
grounds, unchanged); PER-AXIS scale factors and head-gyro MISALIGNMENT (this one is COMMON-MODE, which
is exactly why it collapses onto one number); and slice 37's other two, a SECOND-ORDER head servo and
THE τ AXIS AS ITS OWN SLICE — both now sharper, because this slice shows the REJECTION path has its own
spec.

---

## Slice 39 — A NULLING-LOOP HEAD SERVO — KILLED AT GATE 0 (2026-08-17)

**Not a slice — a KILL RECORD. No code shipped; the suite stayed at 7564.** An infinite-gain
nulling loop is not an architecture, it is a reparameterization of the servo time constant
(`nulling(τ, s, b) ≡ feed-forward(τ(1+s), 0, b/(1+s))`, measured end to end at 5.8e−09 m of
trajectory over 12 000 ticks). Full record, all 9 probes: `docs/plans/slice39.md`. The live
successor it left behind (FINITE loop gain) is in `docs/DEFERRALS.md`.

## Slice 40 — A HEAVIER GIMBAL: THE SECOND-ORDER HEAD SERVO (2026-08-17)

**Status: SHIPPED AND COMPLETE, all four gates. Suite 7564 → 7693 (+129). Slices 1–39 byte-identical,
proven ON THE WIRE (the `:first_order` rung is `max|Δpos| = 0.000e+00` against the rung being absent,
over 12 000 ticks, with and without the new comp keys authored beside it).** Full plan and every
gate-0 table in `docs/plans/slice40.md`; raw probe output in `M:\claud_projects\temp\slice40g\`.

**THE LESSON.** Slices 34–39's head is a FIRST-ORDER LAG with a rate limit — one number, and a servo
that moves a fraction of its error every tick. A real gimbal has INERTIA, so its servo is
second-order (`θ̈ = ω_n²(θ_cmd − θ) − 2ζω_n θ̇`), and that is a new MECHANISM rather than a refinement,
because of what a lag cannot do. Slice 37 measured its whole margin in **GAIN** — the lag LOW-PASSES
body motion out of the radome's INDEX (0.882 at the ring's 1.7 Hz against a STRAPDOWN seeker's exactly
1.000) — and a first-order lag is **BOUNDED IN BOTH CURRENCIES: gain ≤ 1 and phase ≥ −90°, at every
frequency, for every τ.** It could only ever make the index quieter. A second-order servo leaves both
bounds.

⭐⭐ **THE HEADLINE IS A PAIR OF WIRES WHOSE INDEX GAINS DIFFER BY 32×, AND BOTH RING.** On slice 34's
own shipped design (R̂ = −0.18, which the first-order head flies QUIET at rms r 0.01181):

| servo | index gain @1.7 Hz | phase @1.7 Hz | `rms r` |
|---|---|---|---|
| **1st τ = 0.05 — THE SHIPPED HEAD** | 0.882 | −28.1° | **0.01181** (quiet) |
| 2nd ω_n = 2.0 Hz, ζ = 1.00 | 0.581 | −80.7° | 0.01212 (quiet) |
| 2nd ω_n = 2.0 Hz, ζ = 0.10 — **RESONANT** | **3.073** | −31.5° | **0.51659 (44×)** |
| 2nd ω_n = 0.5 Hz, ζ = 0.10 — **HEAVY** | **0.095** | −176.3° | **0.42414 (36×)** |

⇒ a servo **NINE TIMES QUIETER than the shipped lag rings THIRTY-SIX TIMES HARDER**. ⚠⚠ AND THE
CONVERSE IS MEASURED TOO, WHICH IS WHAT KEEPS THE CLAIM HONEST: phase past −90° does not by itself
ring (`0.5 Hz, ζ = 1.0` sits at −147° and reads 0.0184 — quiet). ⇒ the claim stops at **NEITHER
NUMBER, READ AT A FIXED FREQUENCY, ORDERS THE OUTCOME**, and no loop-crossover argument is made,
because the frequency the loop actually closes at is the ONE QUANTITY THIS GATE COULD NOT MEASURE
(§0.7 below).

⭐ **THE SENTENCE THE TWO WIRES EXIST TO SAY: INERTIA IS NOT THE ENEMY — UNDAMPED INERTIA IS.** The
SAME added inertia buys **+0.072 of R̂** of margin at ζ = 1.0 (onset (−0.100, −0.090] against the
shipped head's (−0.170, −0.165]) and rings at EVERY cell of that grid at ζ = 0.1. ⚠ QUOTED IN R̂ AND
NOT IN "CELLS": those two brackets were found on a **0.010** grid extended toward zero (on slice
37/38's own 0.005 grid those arms never ring inside it at all), and a "cell" means 0.005 everywhere
else in this family. **The damping decides the
SIGN of what the inertia does**, which is why ζ is the slider and ω_n is the wire.

⚠ **RUNG, NOT KNOB, AND THE GATE IS ANSWERED BY A BOUND** (slice 39's kill, pre-empted before any
kernel existed): analytically no τ reaches gain > 1 or phase < −90°, and IN FLIGHT the shipped knob's
own domain swept **800× over τ ∈ [0.001, 0.8] spans `rms r` 0.0104…0.0343 and NEVER RINGS** — 15×
below the quieter of the two second-order arms. ⚠ At large ζ the rung nearly collapses onto a lag of
`τ_eff = 2ζ/ω_n` (ratios 1.059 / 1.056 / 1.016 / 1.005 against the matched first-order arm — CLOSE,
never identical, always the same direction), which is where the button goes quiet, stated rather than
hidden.

⚠⚠ **THE DISCRETIZATION IS PART OF THE CLAIM AND IS PINNED, NOT ASSUMED** (advisor, before the
kernel): the claim lives in the lightly-damped regime, which is exactly where an integrator's own
numerical damping could masquerade as physics. Three oracles in `test_frames.jl` — the step response
against the CLOSED FORM converges at FIRST ORDER (**6.269e−03 → 6.259e−04 for a 10× dt, ratio
10.02**; a flat column would mean the recursion is not solving this equation), the discrete free
response's EFFECTIVE ζ is within **0.0003–0.011 OF ONE DOMAIN CELL**, and its damped frequency within
3e−04…2e−03 relative. ⚠ The recursion's own stability limit is measured too (decays at 200 Hz,
DIVERGES to NaN at 300 Hz on the shipped dt), and validate-at-LOAD bounds `gimbal_omega_hz` at 100 Hz
with a 3× margin — convention 5, on the integrator's number rather than on taste.

⚠⚠ **FOUR PREDICTIONS WERE REFUTED AND ALL FOUR ARE LOAD-BEARING.** (1) **THE KILL RISK, FLOWN
FIRST** (advisor's blocking question): as the gimbal gets heavier, does the TRACK BREAK before the
resonance rings? If so the headline would be slice 34's mechanism wearing a new name. Measured
`out_band = 0.00 %` on EVERY arm of every ladder — ω_n 0.5…30 Hz, ζ 0.05…3.0, with and without the
rate limit. (2) **THE RING'S OWN FREQUENCY IS NOT MEASURABLE ON THIS WIRE** — the sharpest available
claim (*the loop rings where the gimbal resonates*, which would have made the limit cycle's FREQUENCY
a design variable for the first time in the arc) had a CONTROL row in its probe, and **the control
failed**: a periodogram put the first-order head's ring at 0.80 Hz where slices 26–39 measure
1.7–2.1 Hz. Re-flown under slice 26 §P7B's own conditions (σ = 0, its PAIR of estimators) **the
oracle failed again and the two estimators disagree on the control itself** (0.91 vs 0.23 Hz) ⇒ NO
FREQUENCY CLAIM IS MADE, and the hypothesis is recorded as UNTESTED rather than as refuted physics.
(3) *"A well-damped second-order gimbal has more margin than the lag"* does not generalise as
written — at ζ = 1.0 the onset depends on ω_n (0 cells at 5 Hz, +3 at 2, then +0.045 and +0.072 of R̂
at 1 and 0.5 Hz — the last two on a coarser 0.010 grid, hence quoted in R̂ rather than in cells), and
what it became is better: MONOTONE IN THE INERTIA. ⭐ The 5 Hz row explains itself (`τ_eff` = 0.0637,
within 27 % of the shipped τ = 0.05 — the overdamped collapse arriving in flight). (4) **THE SEAM's
OWN PREDICTION, REFUTED AT GATE 2**: gate 1 wrote in three places that the resonance would be nearly
INERT on slice 37's space-stabilized rung (that head rejects body motion passively, so its index gain
is 1 whatever its servo order). **It is not inert** — at R̂ = −0.28, where that rung flies QUIET on
the first-order servo (0.04258), the same servo rings it to **0.26150, 6.1×**, with `out_band` 0.00 %
and the head 4.0° off and nowhere near its stop. ⚠ And the FIRST reading of it would have been wrong
TWICE: read at R̂ = −0.18 the same arm shows `rms r` FALLING while the miss opens 944× — slice 33/34's
METRIC INVERSION signature — on an arm whose head is ALSO pinned at its stop with `off_max` 68.6°.
⭐⭐ Why the prediction was wrong SHARPENS the mechanism: **body motion is only ONE of the two things
this servo is fed** — the other is slice 34's own fixed point (the head is aimed by the BENT
measurement), live on both frames. **A lag low-passes whatever it is fed; a resonance amplifies it.**
Corrected in `frames.jl`, `missile.jl` and the plan.

⚠⚠ **GATE 1 CAUGHT THE SEAM'S OWN DECISION BECOMING REACHABLE ON A CLAIMED ARM.** The kernel's stop
is INELASTIC (it zeroes the rate state), because a head winding up against a clamp produces an
oscillation that would FAKE this resonance exactly — and asserted PER ARM (advisor: not from the max
one happened to see), the heavy wire read `head_max = 30.000` EXACTLY at slice 37's stop. Opening it
moved the ring ~1 % (0.55230 → 0.54614), so the mechanism was never the clamp — but the arm was not
CLEAN. ⇒ **wire B authors a 50° stop**, and ⭐ the finding has its own payload: **THE RING IS SPENT IN
GIMBAL TRAVEL** (41.5° against the quiet arms' 18.117°) — slice 33's "the ring is an FOV budget item"
and slice 34's "spent in detector window" arriving in a THIRD currency.

⚠ **WIRE B ALSO AUTHORS ITS DETECTOR WINDOW WIDE, ON A NUMBER** (slice 35's precedent): a heavy
gimbal's tracking error is an order of magnitude larger than a resonant one's (22.482° vs 5.138° at
the same ζ), so slice 37's inherited 25° window BREAKS THE TRACK at ζ ≤ 0.05. At 35° every cell reads
`out_band` 0.00 % with ≥ 7.5° of margin — and **the wire flies BIT-IDENTICALLY at 45°**, which is what
PROVES it non-binding rather than merely observed to be.

⚠⚠ **AND `gimbal_rate_dps` IS AUTHORED WIDE (120 °/s) AS AN ISOLATION WITH A CROSS-REFERENCE, NOT AS
A CONFOUND REMOVAL** (advisor): at slice 37's 40 °/s the rate limit binds 20–53 % of band ticks on the
lightly damped arms AND **ATTENUATES the ring** (0.65648 against the free 0.79973 at ζ = 0.05) —
slice 35's own TWO-SIDED knob reappearing on a new architecture. ⇒ the honest sentence is that **the
shipped servo was partly HIDING this.** At 120 it binds 0.00 % on every arm of both wires, and the
verifier asserts that per arm.

**KNOB DOMAIN, BOTH ENDPOINTS MEASURED WITH THEIR REASONS** (slice 26's post-commit discipline), 16
cells: FLOOR **0.05** for TWO independent reasons — below it slice 35's rate limit comes back even at
120 °/s (`sat_band` 2.05 % at 0.03, 15.13 % at 0.01) AND the ladder stops being monotone there
(0.83533 / 0.84329 / 0.84872 at ζ = 0.01/0.02/0.03 against 0.79973 at 0.05); CEILING **1.00** because
the ring is on the quiet plateau (0.01212 against the control's own 0.01181) and past it the servo
COLLAPSES toward a lag ⇒ the button and the slider would be doing the same thing. ⭐ **THE ANALYTIC
EDGE ζ = 1/√2 IS INSIDE THE DOMAIN** — beyond it the closed-loop response has no peak above 1 at ANY
frequency — a landmark DERIVED before it was measured, and the shipped `head_index_gain` crosses 1.0
across it (1.11838 at ζ = 0.5, 0.81058 at 0.7071), which the verifier asserts as a CROSSING rather
than re-deriving the closed form.

**CLIENT.** The 9th handshake marker, `gimbal_servo_view`, and only the SECOND of this family whose
job is to **UN-DROP** the shared button (slice 37's was the first) — a slice-40 wire raises
`radome_view`, `gimbal_view` AND `gimbal_rate_view`, every one of which hides it, and here the PRESS
IS THE LESSON. ⚠⚠ Its HUD half is the stale-readout class's ~11th occurrence in its WORST form:
without the branch, slice 35's block draws a DEMAND-vs-CAP pair against a rate limit authored WIDE
here precisely so it never binds — every number TRUE, the verdict "servo FREE", and the INERTIA
ringing the missile never mentioned (slice 35's own invisible-slice failure mode, pointed back at
slice 35's own HUD). ⚠ Gated on the FIDELITY KEY and not its value (slice 37's choice), and the
scenarios deliberately DO NOT author `seeker_head` — raising slice 37's marker would point the shared
button at the servo's FRAME instead of its ORDER, which is convention 9 broken invisibly. ⭐⭐ THE
STATE ONLY THIS BRANCH CAN NAME IS A DEAD KNOB: on the first-order rung ζ is BIT-IDENTICALLY inert (a
lag has no ω_n and no ζ), so the mechanism line says so — slice 38's finding in a new key. ⭐⭐ AND THE
GAIN LINE IS A LABEL AND NEVER A VERDICT, because the other wire refuses that reading; it prints the
live number beside BOTH references (the lag's 0.88 and a strapdown seeker's 1.00) and the UI test
asserts no verdict word appears in it.

⚠⚠ **THE SHOT CAUGHT A DEFECT NO TEST HAD** (convention 14's fourth proof earning its keep): the cure
line read *"cure: damp it (ζ→1)"* on an arm ALREADY at ζ = 1.00 and already quiet, under a verdict
line correctly reading "DAMPED GIMBAL — loop QUIET" — every number true and the INSTRUCTION stale.
Made state-aware and pinned in all three states. ⚠ Its state-aware draft then landed EXACTLY on the
measured 55-character budget and was trimmed to 49 — this family's right-edge overrun has five
occurrences (26/28/36/37/38).

**Four proofs green.** `S40V OK` (16 arms: open 0.51706 RINGS / button 0.01207 QUIET = **42.8×** /
cure 0.01282 = 40.3× / ladder MONOTONE across all 9 cells / the gain crossing at the analytic edge /
the slider bit-identically inert on the lag rung / replay bit-identical at BOTH slider ends and on
BOTH rungs / a mid-run press quieting the ringing arm / every arm window-clear, rate-free,
stop-clear, `defl_sat` 0, CPA reached); a 10-tooth UI test; BOTH wires smoke-loaded to
`EWSIM_SERVER_DONE`; and THREE shots — `RESONANT GIMBAL — RINGING` (ring r +0.743, peak 0.84, index
gain 3.07) / `FIRST-ORDER LAG — bounded` (+0.015, gain 0.88, "ζ slider INERT") / `DAMPED GIMBAL —
loop QUIET` (−0.000, gain 0.58). ⚠ TWO verifier defects were caught by its own header's warnings: the
`set_param` field is `target` not `entity` (slice 19's NOT-A-DEAD-KNOB tripwire fired — the server
ignored every slider silently and the first arms passed because they happened to request the AUTHORED
value), and `%.3e` is not a GDScript specifier (slice 21's bug — three numbers printed as format
strings on a GREEN run). ⚠ FOUR carrier/mirror asserts fired and were right to — slice 35's
enumeration of which wires carry its servo key has now earned its keep a FOURTH time.

**Deferred (NAMED):** **THE τ AXIS AS ITS OWN SLICE** (slice 37's, unchanged and now sharper — this
slice shows the lag's bound is what its margin was made of); **FINITE LOOP GAIN** (slice 39's live
successor, untouched here); a RECTANGULAR / PER-AXIS stop and window; SEEKER RANGE / SNR ACQUISITION
LIMITS; GYRO NOISE (draw-topology grounds); PER-AXIS gyro scale factors and MISALIGNMENT. ⚠ And this
slice's own: **A FREQUENCY ESTIMATOR THAT WORKS ON THIS WIRE** — §0.7's refutation is not a dead end
but a prerequisite, and *the loop rings where the gimbal resonates* is a real hypothesis nobody can
test until it exists; **THE (ω_n, ζ) SURFACE AS A DESIGN CHART** (this slice ships two measured cells
of it and a monotone slider through each); and **A SECOND-ORDER FIN ACTUATOR** — slice 15's actuator
is first-order-with-a-rate-limit for exactly the reason slices 34–39's head was, and the bound argued
here is not specific to a seeker head.

---

**Client baked-fx pass (2026-07-14, post-slice-18)** — the SECOND cross-cutting DISPLAY-ONLY client
upgrade (the visual-polish-pass precedent): the first BAKED resources in the client — a new
`clients/godot/fx/` directory of five text-format resources shared by every view, current AND future,
plus the `Sandbox.gd` wiring (git touches exactly `fx/*` + `Sandbox.gd`; ZERO physics, ZERO
core/scenario/wire changes). The fx set: `backdrop.gdshader` (the instrument "sky" — vertical
palette gradient + a twinkling hashed starfield that fades toward the ground + haze + gentle
vignette; rides a full-rect ColorRect on CanvasLayer −2 behind EVERY view, so a future view inherits
it by existing), `glow.tres` (a baked radial-falloff GradientTexture2D — the one soft-halo sprite,
drawn via the new `_glow(p, r, col)` helper under radar/target/jammer/decoy markers, detection blips,
missile bodies + a faint tail glow, impact bursts, the geoloc emitter/fix, GPS satellites, ESM PRI
markers, and CFAR detections — every glow in the client is now the same falloff), `theme.tres` (the
one UI Theme: panel/button/slider/tooltip styleboxes + grabber icons + label colors; applied at the
`PanelContainer` root + badge, replacing the inline StyleBox — headless UI harnesses build bare
widgets and are untouched), `terrain.gdshader` (the 3-D surface: keeps the height-tinted VERTEX
COLORS as albedo — the data path unchanged — and adds slope-based rock shading, fwidth-antialiased
elevation CONTOURS with a stronger every-5th index line, and value-noise grain; spacing authored in
REAL metres — `T3D_CONTOUR_M=50` converted through T3D_SCALE·T3D_VEXAG so the exaggeration can't
silently re-scale it, and the HUD note now says "contours every 50 m" — §12 honesty), and
`terrain_env.tres` (the baked 3-D Environment: ProceduralSky night-blue matching the 2-D palette,
sky ambient, subtle depth fog, filmic tonemap, and a glow pass — the emissive markers bumped to 1.6×
so they bloom; the terrain scene also gains a warm shadow-casting key light + a faint cool fill).
SPATIAL backdrop change: `_draw_spatial_backdrop` no longer paints an opaque sky polygon — the
shader layer owns the sky; the ground strip/grid/labels still draw in-canvas off the live
`_world_to_screen`. CFAR gains a translucent area fill under the profile polyline — drawn as
PER-SEGMENT convex quads, NOT one polygon: a 512-point noisy trace routinely fails the renderer's
ear-clipping triangulation ("Invalid polygon data", caught live on the first windowed shot); each
quad is convex so it always draws (vertex alpha fades curve→baseline; same per-cell data, zero
recompute). Proofs: all 17 `*_ui_test.gd` GREEN post-change (FAILS: 0 — these load the script, so
they also prove the five fx resources parse headless); four windowed shots against live servers
eyeballed via the throwaway shot-harness recipe (slice 18: contour-ringed hills + slope shading +
procedural-sky horizon + themed panel + "TERRAIN MASKED −201 m" intact; slice 2: starfield sky +
glowing radar + honest dark-red below-horizon target; slice 3: area-filled clutter block + glowing
detections + ZERO polygon errors after the quad fix; slice 14: twin salvo arcs + glowing missile
silhouettes). Julia core untouched — the 2604-test suite is out of scope by construction.

---

**Client baked-props pass (2026-07-14, post-slice-18)** — the THIRD cross-cutting DISPLAY-ONLY client
upgrade (the baked-fx-pass precedent): `fx/props3d.gd`, a baked 3-D PROP & EFFECT library for the
Node3D views (the slice-18 terrain view today; land-clutter/6-DOF views inherit it), plus the
`Sandbox.gd` wiring (git touches exactly `fx/props3d.gd` + `Sandbox.gd`; ZERO physics, ZERO
core/scenario/wire changes). `decorate()` runs a DETERMINISTIC scatter — RNG seeded from the CORE's
handshake height grid (same scenario → same layout, nothing to desync: pure display) — that surveys a
22×22 site lattice (height/slope/LOS-corridor distance) and sites: MILITARY (two SAM batteries in
earth-berm revetments with canted launch tubes + engagement panel, a hilltop search-radar site with a
SPINNING antenna head + blinking beacon, a 5-tank column road-marching to the SAM site, a truck convoy
with lit headlights), CIVILIAN (a city of lit-window towers — nearest-filtered emission texture — with
a night-glow pool + aviation beacon, two villages + water tower, a farm with silo/barn + a
vertex-colored field patchwork, an oil refinery — tank farm, distillation columns, pipe rack — with a
BURNING flare stack, a sawtooth factory with smoking chimneys, an airstrip with quonset hangar +
tower, a 4-turbine wind farm with TURNING rotors, a comms mast with microwave drums), LINES
(terrain-hugging road ribbons, a power line with sagging catenary wires between pylons, an elevated
pipeline with supports + pump station), and EFFECTS (GPU-particle fire/smoke reusing the baked
`glow.tres` as the billboard sprite; a live-fire RANGE — sited FARTHEST from the LOS corridor — with
craters, charred hulks, and a PERIODIC one-shot explosion: fireball + flash + lingering smoke; a
burning tank wreck beside the village road). Honesty rails: every prop grounds by bilinear-sampling
the SAME handshake grid (placement only — the client still never re-tests occlusion); NOTHING TALL
sites inside the radar↔target keep-out corridor (10% of span around the first-frame LOS), so the
decoration can never visually contradict the core's `visible` verdict; the HUD line now reads "props
decorative/not-to-scale (display only)" (§12). Wiring: props build LAZILY on the FIRST state frame
(the corridor endpoints are only known then), animate from `_process` (spin/blink/boom timers — the
decorate() contract via node meta), and reset with the scene rebuild. Two hard-won catches: the
StandardMaterial3D emission operator DEFAULTS TO ADD, so a warm base `emission` color washes the whole
tower face cream — keep emission BLACK and put the warm tint in the texture's lit pixels only (caught
on the second windowed shot: towers rendered as glowing lightboxes); and prop scale wants
`k≈span·scale/70` clamped [0.8, 2.6] — true-scale props are invisible at a 16-km map. Proofs: all 17
`*_ui_test.gd` GREEN post-change (the slice-18 UI test drives a state frame through `_on_state`, so it
exercises decorate() headless — the 2-ObjectDB-leak warning predates the pass, verified on HEAD);
`slice18_verify.gd` GREEN against a live server (the 2500-frame held-seed replay stays bit-identical
WITH the props building mid-run — display-only proven, not assumed); four windowed shots eyeballed
(wide: roads/city/glow + "TERRAIN MASKED −203 m" intact; refinery close-up: flare fire + smoke +
pylon wires + trucks; city close-up: dark towers with blocky lit windows post-fix; range close-up:
explosion fireball + smoke dome + craters + hulks + turbine rotors on the ridge). Julia core
untouched — the 2604-test suite is out of scope by construction.

**Baked-props follow-up (2026-07-14, same day)** — four refinements, same rails (git touches exactly
`fx/props3d.gd` + `Sandbox.gd`; display-only): (1) HOUSE WINDOW TEXTURES — the city-tower treatment
scaled to cottages: `_house_win_mat` reuses the SAME nearest-filtered lit-window emission texs over
the wall albedo at coarser UV tiling (1.3/1.5) and gentler energy (1.1 — a village glows, it doesn't
blaze); replaces the old single lit-window box. (2) ROAD TRAFFIC — `_traffic` puts looping two-way
cars on every road ribbon (one per direction, offset ±0.22·road_w off the centreline = right-hand
traffic), each following a `Curve3D` baked onto the SAME handshake heightfield; the cars contract
joins spin/blink/boom in the decorate() meta contract (meta `path`/`speed`/`off`; the caller advances
`off`, wraps at `get_baked_length()`, yaws the +X nose at a point sampled 0.4 u ahead — skipping the
yaw at the wrap point keeps the car from snapping). Cars are `_car` props: paint-variant body, glass
cabin, warm headlights + red taillights. (3) SEASONAL FIELD PALETTES — the farm patchwork picks
spring/summer/autumn/winter off the GRID HASH (`absi(gh>>4)%4`), NOT an rng draw, so the scatter
sequence — and every previously-eyeballed layout — is untouched; same scenario always farms the same
time of year. (4) FAR-ZOOM SHADOW TUNING — the sun's `directional_shadow_max_distance` now TRACKS the
orbit zoom (`clamp(cam_dist·1.8, 100, 1200)` in `_update_t3d_cam`, replacing the fixed 500: ~3×
crisper close-in) with `shadow_opacity` easing to 0.45 at max zoom-out (sub-pixel prop shadows only
shimmer), blend-split + `shadow_blur 1.6` at build; and ground-hugging strips/wires (ribbons, field
patches, catenary wires, pipeline) plus all particle puffs get `cast_shadow OFF` — at far zoom they
smear into shadow acne / dark blobs. GDScript catch: `:=` cannot infer through an untyped loop
variable (`for lane in [1.0,-1.0]` → Variant products) — type the loop var or the target. Proofs:
all 17 UI tests GREEN; `slice18_verify.gd` GREEN vs a live server (2500-frame held-seed replay
bit-identical with cars/windows/season/shadow changes building mid-run); four windowed shots
eyeballed (far: framing + shadows intact; mid/close: window-lit houses, a car with taillights on the
village road — position moved between two captures 3 s apart, confirming the loop animates).

**Battle board (2026-07-14, post-slice-18)** — the FOURTH display-only client piece, and the first
STANDALONE one: `scenes/BattleBoard.tscn` + `scenes/BattleBoard.gd`, a 2-D top-down BATTLE /
COORDINATOR overview screen — the client-side FACE of the future HANDOFF §11 Tier-C "Decision / C2
layer". PURE THEATRE, ZERO PHYSICS, ZERO WIRE: the scene never connects to the Julia core; every
speed/range/Pk is readability-exaggerated choreography and the HUD SAYS SO on-screen (the §12
display-honesty rule — "DISPLAY-ONLY THEATRE … not core truth (the Tier-C C2 layer will own this)").
When the C2 slice lands in the core, this board becomes a thin view of it. The board: a 48×32 km
map (deterministic Gaussian-hill terrain tint, seeded `RNG_SEED=20260714` — same board every
launch; 8-km grid; a dashed FLOT divider), 12 BLUE assets west (HQ/C2, EW radar + coverage ring,
SAM battery, 2 tank platoons, artillery, 2×F-16 CAP, 2×F-16 strike, AEW&C, AH-64) vs 8 RED east
(CP — the objective, 2 SA batteries with THREAT RINGS, EW radar, a patrolling armor company,
artillery, a MiG-29 CAP, an airfield). All unit glyphs are programmatic `_draw` "assets"
(NATO-flavored: blue rect / red diamond frames + type marks; heading-oriented aircraft silhouettes
with velocity leaders; spinning helo rotor; hp pips; wreck ✕), riding the shared `res://fx` chrome
(backdrop shader, glow, theme). THE COORDINATOR LOOP: left-click / drag-box selects blue;
right-click ground = MOVE (waypoint flag + dashed path, formation offsets); right-click a red unit
= ENGAGE (gated by weapon domain — unarmed/wrong-domain refuse with a log line); homing shot
streaks + boom effects; a roster (live status per unit), a selected-unit card, and a timestamped
event log; Pause / ×1–×8 time compression / Reset. RED AUTO-DEFENSE makes the rings real: every
armed red unit engages blue inside its ring (the MiG chases; statics shoot), so the coordinator's
actual job is SEAD sequencing — aircraft ARC at 90% launch range instead of overflying (standoff
10 km vs the 13-km SA ring = a survivable but honest exchange; the scripted demo trades the strike
pair + helo for one SA battery). Blue's ONLY autonomy is the SAM battery self-defending its ring —
every other blue trigger pull is an order. Proofs: `net/battleboard_ui_test.gd` headless GREEN
(off-tree instance, no _ready — the slice-16 mock pattern: 12+8 spawn, MOVE closes on the waypoint,
ENGAGE fires/kills inside the ring then goes idle, unarmed/wrong-domain refuse, red SAM
auto-engages blue air in its ring, reset restores the board); `BattleBoard.tscn` headless
smoke-load exit 0; three windowed shots eyeballed (start board with rings/rosters; mid-fight SAM
duel with streaks + a fresh wreck; late board with R-SAM2's ring GONE and the trade tallied in the
roster). Julia core untouched — the 2604-test suite out of scope by construction. Run:
`godot --path clients/godot res://scenes/BattleBoard.tscn` (no server needed). Deferred (NAMED):
core-owned C2 truth (weapon–target assignment / engagement scheduling — the Tier-C slice this
screen fronts); terrain-aware movement; EW/sensor-coverage effects on detection (needs the core);
waypoint queues; save/load of a battle plan.

---

## Slice 41 — A SECOND-ORDER FIN ACTUATOR — KILLED AT GATE 0 (2026-08-18)

**Not a slice — a KILL RECORD. No code shipped; the suite stayed at 7693.** Full record, all probes:
`docs/plans/slice41.md`; raw probe output and the reverted prototype in `M:\claud_projects\temp\slice41\`.

**WHAT DIED, AND ON WHAT.** Put a first/second-order actuator on the FIN (slice 15's fin is
first-order-with-a-rate-limit for the reason slices 34–40's head was). The pre-registered falsifier —
written one commit before the measurement existed — was *"if a fitted `(k_α, k_q)` reproduces the
arm's rms at the design point AND tracks its `R_crit` across the ladder to within the 2.7–3.2 % the
whole effect spans, the actuator is a reparameterization."* **It tracks to 0.00–1.01 %, at three
crossing levels, on two independent gain axes.** Slice 39's death in a new letter.

⭐⭐ **THE REASON, AND IT IS WORTH MORE THAN THE SLICE WAS.** A pole differs from a gain ONLY in that
its phase VARIES with frequency. The probe measured this loop's fin command to be a **single line at
1.6488 Hz** carrying over half its energy, with the airframe filtering the rest out of the body rate.
⇒ **a loop that visits one frequency samples one point of a phase curve, and one point of a phase
curve is a number — which is what a gain is.** Slice 38's *"`s` adds PHASE and scaling a slope
cannot"* is TRUE but has teeth only where the loop is BROADBAND. On a single-mode limit cycle it has
none.

**WHAT WAS REAL BEFORE IT DIED (P2 survived, §III).** The actuator does eat radome margin and the
inherited sign was WRONG: a lag on slices 34–40's feed-forward path was *"silently doing stability
work"*; inside the MAIN control loop the same component **destabilizes**. At `R = −0.09` the ring goes
1.27× / 1.58× / 1.93× / 4.45× at 60 / 40 / 30 / 20 Hz (monotone, unclamped), and `R_crit` walks
−0.0926 → −0.0901 from an ideal actuator to a 20 Hz one — *a cheaper actuator needs a better radome*,
2.7–3.2 % however the line is drawn. ⚠ **AND IT IS A MARGIN EFFECT: at `R = −0.085` a 20 Hz actuator
is FREE to seven figures.** None of this saves the slice — every one of those numbers is reproduced
by a gain retune.

**THREE TRAPS THIS GATE WALKED INTO AND OUT OF, ALL NOW IN `docs/LESSONS.md`:**
1. **The clamped plateau.** Run at the wire's authored design, P2 read 0.4 % and would have fired the
   INERT kill — because the α_max clamp binds **78 % of band ticks** there, so the rms is insensitive
   BY CONSTRUCTION. The lesson only exists one step inside the boundary.
2. **The point fit that kills the wrong slice.** P5 as originally worded (*can any `(k_α, k_q)`
   reproduce the arm?*) answers **yes** at the design point — `k_α = 1.01` matches the 60 Hz arm to
   0.9 %. Run that way, slice 41 dies at §IV.1 for a reason that is `k_q` being *part of the radome
   loop* (~98 % of its damping), not a reproduction of a pole. **The pre-registration saved it from a
   wrong death and then delivered the right one.**
3. **A degenerate confirmation.** The pre-registered second leg (apply the fitted pair to
   `slice40_resonance`) returns a PASS by the letter — and every arm is within 0.9 % of the CONTROL
   too. **A test whose control also passes is not a test.** Recorded as run, not counted.

**THE SUCCESSOR IT LEAVES BEHIND** (`docs/DEFERRALS.md`): a slice whose lesson IS the frequency
dependence. Halving `af_I` moves this ring 1.6488 → 2.7503 Hz while leaving the onset put (slice 26's
own *"the threshold is the guidance loop's, not the airframe's"*), and there the pair that matched to
2.6 % **over-shoots by 27 %** — the sign a phase lag predicts. ⚠ CONFOUNDED by the plant change, so it
is a measured hook and NOT a claim.

## Slice 42 — A SEARCH PATTERN, THEN AN ACQUISITION MARGIN — KILLED AT GATE 1 (2026-08-18)

**Not a slice — a KILL RECORD. No code shipped; the suite stayed at 7693.** Full record, all ten
probes: `docs/plans/slice42.md`; raw probe output in `M:\claud_projects\temp\slice42\`. Nothing under
`core/` was touched at any point (the one gate-0 probe patch was reverted in `78c98da`).

**WHAT WAS PROPOSED, AND WHAT IT BECAME.** The slice opened as *"buy coverage with TIME instead of
with GLASS"* — a seeker that SWEEPS to find a target it never acquired, against a wider detector
window. Gate 0 measured that honestly and **demoted it**: §V.3 found that on the geometry that would
ship, **a single 15° window rescues every showcase cell, and nothing in this model charges for the
window**, so the trade cannot be motivated from inside the simulator. What survived gate 0 in its
place was a second finding — the **acquisition knife-edge** — and §V.6 made the scoping call onto it.
**Gate 1 killed that too, and the frontier the slice walked away from turns out to have been the
stronger of the two all along.**

⚠⚠ **THE KNIFE-EDGE WAS THE NULL CASE WEARING A LABEL, AND ITS OWN GATE-0 TABLE SAID SO.** §V.2 read
the window ladder as *"when the window exactly equals the birth offset the seeker LOCKS — and the lock
is WORTHLESS"*: at `fov 12.00` the head locks, `off@lock` reads 12.0000, the lock survives one tick,
and the arm misses by 305.112 m. **But 305.112 m is the `fov 11.95` NEVER-LOCKS cell's miss, to the
digit.** A lock that moves no number in the verdict column is not a lock that is worth nothing — it is
the do-nothing case relabelled. And `off@lock == fov` to four decimals was never a measurement: the
gate fires on `off ≤ fov` with the head at the rim BY CONSTRUCTION, so the column echoes its own
authored constant.

⭐⭐⭐ **AND THE KILL IS STRUCTURAL, NOT A MAGNITUDE ARGUMENT: THE DEAD BAND IS `ω_LOS · dt` — ONE
INTEGRATION STEP.** Gate 1 walked the BIRTH OFFSET (not the window) on `slice36_handover`'s shipped
wire, shipped 10° window, and re-flew the rim at three integration steps:

| `dt` s | ω_LOS °/s | **ω·dt** ° | last **DYING** err ° | first **HOLDING** err ° | `hold_max` |
|---|---|---|---|---|---|
| 2e−3 | +3.6300 | **0.00726** | −9.9940 | −9.9900 | 0.0020 s |
| 1e−3 | +3.6290 | **0.00363** | −9.9980 | −9.9960 | 0.0010 s |
| 5e−4 | +3.6285 | **0.00181** | −9.9990 | −9.9980 | 0.0005 s |

**The load-bearing result is the HALVING — the band halves when the step halves.** (`ω·dt` inside its
bracket at all three steps is corroboration, quoted as that: ⚠ the `dt = 1e-3` bracket is two grid
points wide and clears by 0.00037°. P11's telemetry supplies the containment properly.) **`hold_max` is
EXACTLY ONE TICK on every row.** The "acquisition margin" is the distance the line of
sight travels between two evaluations of a once-per-tick gate. At the shipped `dt = 1e-3` it is
0.0036° against a 10° window — **0.036 %**. ⇒ **A FINDING WHOSE SIZE IS SET BY THE INTEGRATOR'S STEP
CANNOT BE A LESSON ABOUT HARDWARE** (now `docs/LESSONS.md`).

**THE RESCUE HYPOTHESIS WAS TESTED AND REFUTED TOO (P8, §VI.1).** The one non-degenerate reading —
*the required margin is set by the RACE between the LOS rate and the servo rate* — predicts the dead
band shrinks as the servo speeds up. It does not move at all: `err −10` misses by **3620.675 m at both
8 and 60 °/s, the same digits**, holding one tick on both. ⭐⭐ **WHY, MEASURED (P11, §VI.1a — the first
draft of this paragraph asserted it instead): THE SERVO IS ONE TICK LATE.** A real head command exists
on tick 1 but is written at the END of that tick, so the tick-1 slew runs against the handover's own
seeded command and moves the head ZERO — **both rates are equally idle on that tick**. The `off`
telemetry then steps 10.000000 → **10.003629**, which is `ω_LOS·dt` to six decimals from an
independent measurement, the gate shuts at tick 2, and — since a shut gate forbids slewing — `head_az`
is CONSTANT TO 7 DECIMALS for the rest of the flight at both rates. ⇒ *the margin a lock needs is one
tick of LOS motion, because the servo is one tick late* — and being late by one tick is not something
a faster servo fixes. ⚠ And **the same |err| on the OTHER SIGN does not die**:
`err +10` at 60 °/s holds (0.206 m, `off@lock` 9.9364 at tick 2), because there the LOS walks INTO the
window and mints its own margin. Exact equality AND a direction of travel is a coincidence, not a
mechanism.

⚠ **THE INSTRUMENT PASSED ITS HONESTY CHECK THIS TIME, WHICH IS WHY THE KILL STANDS.** Gate 0 had two
instrument bugs (§II.3's 1/50-rate crawl, §V.0's search parked on the gimbal stop). The gate-1 probe
reproduces the shipping wire's own published numbers: at 8 °/s, `err 0 → 3290.078 m` and
`err −6 → 0.191 m` — `slice36_handover`'s and `slice36_biased`'s headline numbers to the digit — and
the holding basket `err ∈ [−9, −4]` is slice 36's own basket.

**WHAT SURVIVES, AND IT IS DEFERRED, NOT DEAD** (`docs/DEFERRALS.md`): ⭐ **the WRONG-GUESS FRONTIER**
(§V.4) — the minimum sweep rate that rescues, against coverage, is FLAT across a 6× range of coverage
when the search guesses the right direction and rises monotonically on every wrong-guess arm (past
S ≈ 20° on the + side no rate buys it back). Clean 2-D law, passes the reparameterization gate, `sat%`
6–19 / `aero%` ≈ 0 on every quoted cell. ⚠ **It must NOT be planned until the DETECTOR WINDOW COSTS
SOMETHING** — until then a wider window dominates it for free.

**THE METHOD LESSONS** (all now in `docs/LESSONS.md`): check a claimed STEP against the NULL cell
before believing it; a reported quantity that equals an authored threshold to full precision is the
threshold, not a measurement; re-fly a narrow threshold effect at half `dt`. ⚠ **And the pattern this
arc has now repeated four times** (39, 41, the search half of 42, its acquisition half): *the probe was
right, the table was right, and the SENTENCE on top of the table was wrong* — every one caught by a
criterion written down BEFORE the measurement existed.

## Slice 43 — THE SEARCH LAW: THE OVERLAP DEFICIT — GATE-0 LAW RECORD (2026-08-18)

**Not a slice — a GATE-0 LAW RECORD. No code shipped; the suite stayed at 7693 (re-run green after
revert).** Full record, probes P0–P5: `docs/plans/slice43.md`; raw probe output in
`M:\claud_projects\temp\slice43\`. `core/src/missile.jl` carried the slice-42 probe patch plus a
one-line anti-windup extension during the run and was reverted with `git checkout` before write-up.

**WHY IT WAS RE-OPENED.** Slice 42 left exactly one surviving finding — the wrong-guess frontier — and
deferred it. Two things made it worth one more gate. ⚠⚠ **First, the table was flown on a THIRD
instrument bug in this family:** `p7b_frontier.jl`'s `arm()` never set `:probe_search_drive`, so every
cell fell through the probe patch's `:direct` branch and **TELEPORTED the head to the search command —
no `τ`, no `rate_max`, no `head_slew_full`.** The wire ships `gimbal_rate_dps = 8`, so its ρ_min = 10,
11 and 14 °/s cells — the entire expensive half of the frontier — are rates the shipped servo cannot
produce. Second, the frontier does not spend GLASS; it spends SLEW RATE, which has been priced since
slice 35. That second thought produced a candidate law (*"the search's rate ceiling IS the servo"*)
which **the probes refuted before its own falsifier ran** — recorded in `slice43.md` §I.3, not smoothed.

⭐ **F0 — A REAL SERVO FLIES A SEARCH FINE, and its lag is `ρ·τ` to three digits** (0.049 / 0.098 /
0.196 / 0.245° at ρ = 1 / 2 / 4 / 5 against τ = 0.05). So most of slice 42's numbers survive the
bypass — but not its sentences.

⚠⚠ **F1 FIRES — `none ≤ 16` WAS THE 1..16 GRID'S OWN EDGE.** Walked to 64 °/s the four `--` cells read
**18, 22, 18, 22 °/s**, so §V.4's *"past S ≈ 20° no rate buys it back"* is WITHDRAWN. This is the lesson
slice 42 itself banked (*a reported quantity that equals an authored threshold IS the threshold*),
applied to a sweep's BOUND instead of a gate's constant.

⚠⚠ **F3 CONFIRMED — THE +SIDE IS THE 30° STOP AND IS EXCLUDED FROM EVERY TABLE.** Its command-minus-head
lag reads the authored half-width to three digits across seven rates (14.990–14.996 at S = 15;
24.977 at S = 25; 29.979 at S = 30), and its DO-NOTHING arm sits on the stop 56.5 % of in-band ticks.
The head is not flying the pattern there. ⚠ The two signs are also not the same failure: the − arms
never lock and miss an identical 305.112 m at both errors; the + arms DO lock, late, and still miss.

**THE FIVE FINDINGS (−side, real servo, lead-clamped where noted):**
1. ⭐⭐⭐ **THE COST OF ACQUISITION IS THE OVERLAP DEFICIT `|err| − fov`, NOT THE POINTING ERROR.** Head
   travel at lock over eight cells: 2.073 / 4.144 / 6.224 / 8.304 / 10.392° at deficits 2/4/6/8/10, and
   3.104 / 5.176° at deficits 3/5 behind a 15° window — ratio 1.035–1.039 throughout. **The natural
   experiment: `err −14 / fov 12` and `err −12 / fov 10` return travel 2.073°, t_lock 0.309 s and miss
   0.186 m — identical to every digit printed.** Error and window are not separately visible.
2. ⭐⭐ **`travel = deficit / (1 − ω/ρ)` and `t_lock = travel/ρ + τ`, FOR `ρ ≤ rate_max`** — where ω is
   the LINE-OF-SIGHT RATE. ⚠ The first form of this (`1.036·deficit/ρ + τ`) was measured at ρ = 8 ONLY and
   is superseded (`slice43.md` §III, an advisor catch): the multiplier runs **1.031–1.357** over the rate
   axis, rising as the sweep slows, exactly as the drift mechanism named for it requires. ⭐ ω extracted
   from the multiplier matches `m1.look_body_az_deg`'s measured derivative to **5.6–13 % on 15 cells**
   (four deficits, four rates, two windows), one-sided because the telemetry averages while the binding
   drift accrues at the end. ⭐ The `+τ` term is **exact — residual 0.0000 s on all 12 unsaturated cells**,
   because a `ρ·τ` lag traversed at ρ °/s costs τ seconds whatever ρ is; **above `rate_max` it decays**
   (+0.023 / +0.016 / +0.007 s at ρ = 12 / 16 / 32), which is where finding 5 takes over.
2b. ⭐⭐⭐ **THERE IS A FLOOR ON SWEEP RATE (1.0–1.5 °/s), AND IT IS THE AXIS THE SEARCH DOES NOT SWEEP.**
   Two candidate mechanisms were proposed and BOTH measured and refuted (`slice43.md` §III.4 then §IV, a
   second advisor catch): it is not a race against the LOS rate, and it is not a missing reversal (at
   ρ = 1 the arm fails at EVERY coverage 2–20°, identical digits). ⭐⭐ **What it IS: at ρ = 1 the head closed
   the SWEPT axis to 9.7519° — INSIDE a 10° window — and still never acquired, because 2.4934° of drift on
   the UNSWEPT axis made the RADIAL off-axis angle 10.0656°.** It misses by 0.066°, identically at S = 5,
   8 and 20. ⭐⭐ **AND IT IS A DEADLINE, NOT A FEEDBACK** (a third advisor catch): the search branch
   never assigns `head_el`, so the unswept drift is EXOGENOUS — measured BYTE-IDENTICAL at matched times
   across ρ = 0, 1, 1.5, 4 (0.4093 / 0.9827 / 1.6591 / 2.4991 / 3.6243° at t = 1–5). **It spends the
   window's radius on a schedule the search does not control; the sweep rate only decides whether the
   SWEPT axis closes first.** 25 % of the radius is what the unswept axis COSTS, not something the
   search CAUSED. ⭐⭐⭐ **AND THE FLOOR IS THEREFORE DERIVED, FROM THE NO-SEARCH ARM ALONE:** with
   `Δaz(t,ρ) = Δaz₀(t) − ρ(t−τ)` (verified to 0.001°) and the radial gate,
   `ρ* = min_t [Δaz₀(t) − √(fov² − Δel(t)²)] / (t − τ)` = **1.0174 °/s at t = 4.00 s** — flown, ρ = 1.01
   NEVER locks and ρ = 1.02 locks at t = 3.809 s, so **the prediction lies inside a sub-1 % bracket and
   calls the acquisition TIME too.** ⭐ The required-rate curve is **U-shaped** (2.399 / 1.017 / 2.019 °/s
   at t = 1 / 4 / 7): too early the swept axis has not closed, too late the unswept one has eaten the
   budget — **a search has a best moment.** ⚠ *"and one that misses it cannot recover by continuing"* is
   **DERIVED, NOT FLOWN** — the U's left arm and minimum are confirmed, its right arm is a property of the
   derived curve, and by construction no flown arm can acquire on it (a higher rate always locks earlier).
   ⭐⭐⭐ **AND THE DERIVATION HOLDS ON GEOMETRIES IT WAS NOT TUNED ON — 4/4 to the grid's 0.01 °/s:**
   ρ* = 1.0174 / 1.8817 / 2.6259 / 1.2193 °/s predicted at deficits 2 / 6 / 10 / 3 (the last behind a 15°
   window), each landing exactly on the first LOCKING rung with the rung below it failing; and the predicted
   times 4.03 / 5.16 / 5.65 / 4.59 s match measured locks of 3.961 / 5.104 / 5.597 / 4.529 s — **within 0.07 s
   on all four, across a 5× range of deficit and two window sizes.** ⚠ The ρ ladder is anchored on the
   prediction (`ρ*−0.05 : 0.01 : ρ*+0.06`), so the test is the SHARP one — locks at ρ*, fails at ρ*−0.01 —
   not a blind bracket, and must not be quoted as one. ⚠ F6 applied here too: off-axis reads 10.0647 / 10.0656 / 10.0661 at
   `dt` = 2e−3 / 1e−3 / 5e−4 — **it does not halve, it does not move.** ⭐⭐ **AND IT LANDS ON SLICE 34's
   RECTANGULAR / PER-AXIS FOV DEFERRAL WITH THE ARM THAT DEFERRAL WAS MISSING:** a per-axis window of the
   same 10° half-width would LOCK this arm (9.75 < 10 AND 2.49 < 10) while the shipped radial `hypot`
   gate holds it out — **the first flying arm in this family where the window's SHAPE, not its size,
   decides acquisition** (⚠ precisely: slice 34 gate 2 §2.5 bound the STOP; this binds the WINDOW). ⚠ The shape verdict rests on 0.066° and is quoted as narrow; the non-marginal
   claim is the 25 % of window radius. ⚠ The LOS rate DOES rise 318× across the flight (0.271 → 86.05 °/s,
   t = 1 → 9 s) and that is correctly measured — it is why a LATE acquisition is worthless, and it is NOT
   why the ρ = 1 arm fails.
3. ⭐⭐ **GUESS RIGHT AND COVERAGE IS NOT FREE — IT IS NEVER REACHED.** `t_lock` = **0.309 s, the same
   digit**, at S = 3, 5, 8, 12, 16, 20, 25, 30 (a 10× range): the head locks 2.07° into a pattern
   authored 3–30° wide. Slice 42's *"the width is FREE"* is a flat row misread.
4. ⭐⭐ **GUESS WRONG AND COVERAGE COSTS `2S` OF TRAVEL AT AN ACCELERATING PRICE.** `t_lock` 1.088 /
   1.612 / 2.407 / 3.495 / 4.648 / 6.035 s at S = 3→20, then **never-locks at S = 25 and 30**. Measured
   d`t_lock`/dS = 0.262 → 0.347 s/° against the geometric bound `2/ρ` = 0.250 — **5 % over, then 39 %
   over.** The naive travel-over-rate law is a LOWER bound, loose exactly where the decision is hard.
5. ⚠ **THE HEAD, NOT THE COMMAND, IS WHAT SEARCHES — an open-loop generator WINDS UP against the rate
   limit and what saturates is the AMPLITUDE.** At an authored S = 20, realized head excursion falls
   −19.73 / −17.58 / −15.82 / −13.20 / −7.92 / **−4.39°** as ρ goes 8 → 64, and **at ρ = 64 the arm FAILS
   OUTRIGHT (305.112 m, never locks)** at a coverage that rescues comfortably at ρ = 8. A one-line
   anti-windup lead clamp removes it (excursion flat −19.73 → −19.03), and below `rate_max` the clamp is
   **provably inert** (identical digits at ρ = 2, 4, 8 for every lead ∈ {∞, 8, 4, 2, 1}).

⚠⚠⚠ **AND THE REPARAMETERIZATION GATE WAS RUN AGAINST FINDING 5 BEFORE IT WAS WRITTEN DOWN — it bites.**
Anti-windup at the authored ρ versus the open-loop generator at `min(ρ, 8)`: **the same rescue verdict
in ALL 16 CELLS** (including S = 30, where both fail at a byte-identical 305.112 m), 5–18 % apart in lock
time only. ⇒ **finding 5 ships as a design CAUTION with a measured size, not an architecture**, and its
cure is the cheaper `ρ ← min(ρ, rate_max)` at authoring time.

⭐ **F6 CLEARED — THE RULE SLICE 42 DIED TO DOES NOT BITE HERE.** At `dt` = 5e−4 the headline cells move
by **0.0000°** (head travel at lock), **+0.0005 s / +0.16 %** and **−0.0010 s / −0.02 %** (t_lock).
**F4 CLEARED — the verdict is BIMODAL:** 40 −side arms give 30 rescues (largest 0.3398 m) and 10 failures
(smallest 305.1118 m) with **nothing in between**, so the 1 m gate could sit anywhere in a 0.34–305 m band.

⚠⚠ **THE SLICE STAYS BLOCKED, AND FINDING 1 SHARPENS THE BLOCK RATHER THAN LIFTING IT.** A wider `fov`
reduces the deficit ONE-FOR-ONE and the deficit is the entire cost ⇒ **widening the glass by 2° and
travelling 2° further are the SAME ACT, and only one of them costs time.** A search-pattern slice still
needs `SEEKER RANGE / SNR ACQUISITION LIMITS` first. **This gate ships a LAW to that deferral.**

**THE METHOD LESSONS** (all now in `docs/LESSONS.md`): a grid edge is not a ceiling — print the sweep's
bound beside any `--`; a FLAT ROW is evidence of nothing until you know where the mechanism stopped
(*free* and *never reached* look identical and license opposite designs); **drive the COMMAND, then
prove the ACTUATOR followed it** — three instrument bugs in this family are all that one bug, and the
tell is a command-minus-actuator lag that reads the authored half-width instead of `ρ·τ`.

## Slice 1 — radar to detection to ROC (the first slice; block sits at EOF)

Slice 1 (radar → detection → ROC) — **COMPLETE. Steps 1–7 done & green** (227 tests): world +
tick contract + determinism; wire protocol + Godot↔Julia socket seam proven
(`tools/echo_server.jl` + `clients/godot/net/seam_test.gd`, exit 0); `rf.jl`
(free-space radar eq) + `detection.jl` (analytic + MC Pd, Swerling 0/1) with
`test_radar_eq` + `test_detection`. SNR is dimensionless with noise normalised to
1, so `snr_freespace` feeds `pd_analytic`/`pd_montecarlo` directly. Step 5:
`scenario.jl` (`load_scenario` → `Scenario` struct) + `scenarios/slice1_roc.yaml`,
plus the concrete subsystems in `radar.jl` (`ConstantVelocity` mover, `RadarSensor`).
Live readout (`snr_db`/`pd`) is per-tick into `w.env[:telemetry]`; the detection
draw + `:detection` event are gated to `revisit_s` (the per-scan blip), with the last
verdict persisted in radar `comp`. `detect_once` is the shared single-look sampler
(`pd_montecarlo` loops it). `test_scenario.jl` covers loader, live-telemetry-vs-closed-
form, the static-geometry Bernoulli check, and byte-identical replay through the loader.
Step 6 (gate 3, ROC convergence): `batch.jl` — `run_batch kind=roc` sweeps Pfa × SNR,
computes analytic + MC Pd, and writes `shared/roc_radar1.bin` (flat `(n_pfa,n_snr,2)`
Float64, col-major) + a `roc_radar1.meta.json` sidecar (the headless twin of the §5
socket artifact descriptor — one descriptor, three uses). `load_roc` is the tested
reader the Pluto notebook (`clients/notebooks/slice1_roc.jl`) reuses; `tools/run_batch.jl`
is the headless generator. The batch owns its **own** seeded stream (never `w.rng`), so a
sweep never desyncs the live trace — and per HANDOFF §1/§12 it's the *distribution* path
(no byte-identity assert; the cell loop is the Threads/GPU seam). `test_batch.jl`: analytic
plane == independent recompute (catches a transpose), MC in the analytic Pd's Wilson 4σ
band, descriptor↔file agree, `w.rng` untouched by a batch.
Step 6b (deferred prereq for 7): `server.jl` — the interactive socket run loop (HANDOFF §4).
`Server` wraps a `Scenario`; a `@async` reader task ONLY parses+enqueues commands onto a
Channel, while the MAIN loop owns **all** World mutation (commands + `tick!`) — single-mutator,
so no locks and determinism survives. `handle_command!` covers the 8 §5 commands;
`set_seed`/`reset` compose (the held seed survives reset → clean replay); the `run_batch`
adapter maps the §5 `snr_db_grid_start/stop` wire spelling to the internal `snr_db_start/stop`
kwargs (drop it and the bounds silently default) and runs **inline** (slice-1 single-writer
stance; the Threads/@spawn seam is later). `steps_this_iteration` paces PAUSED/REALTIME/FAST
with a catch-up cap. `warmup!` pays TTFX on a deepcopy + a tempdir batch, never touching the
live World or real `shared/`. A connect-time `scenario_frame` (a flagged §5 extension) ships
the knob list (incl. each knob's live `value` so a slider opens at the truth, not at `min`)
**and** the World's `fidelity` map (so the §12 badge reflects actual fidelity, not a hardcoded
label), so the client builds sliders + badge from the handshake. `tools/server.jl` is the headless
entrypoint (`EWSIM_SERVER_*` stdout markers; `julia tools/server.jl [scenario] [port]`).
`test_server.jl` (51 tests): command dispatch, seed/reset composition, the grid-rename
mapping, warmup isolation, pacing, and a **real-loopback** test proving handshake + emit +
one-shot event clear (on a provable-detection fixture, not the 42 km scenario where Pd is
unknown) + clean EOF teardown. Also smoke-proven end-to-end via `run_server!` on a real port.
Step 7 (slice 1 complete): the Godot spatial sandbox. `clients/godot/net/SimClient.gd` is the
ONE protocol impl (4-byte BE length + JSON, §5 framing; mirrors `seam_test.gd`) — IO is driven
by `poll()` so it runs both in a live scene (`_process`) and headless (caller polls). Both the
scene and the verifier reference it via `preload`, **not** `class_name` (the global class cache
isn't built on a headless/fresh-clone load, so a bare `SimClient` type reference fails to resolve
there — a real bug the scene smoke-load below caught). `scenes/
Sandbox.gd` (+ a trivial `Sandbox.tscn`, all UI built in code) is a **pure client, zero physics**:
on the `scenario` handshake it builds sliders from the knob list (log knobs → `exp_edit`, opened
at the handshake `value`) and the §12 fidelity badge, auto-runs realtime, and renders `state`
frames in a 2-D elevation view (screen-x downrange, screen-y altitude — the two coords that move
in slice 1) — radar marker, target (green when detected), and a fading ring blip per `detection`
event; the per-tick SNR/Pd readout stays prominent (at the 42 km cold start Pd≈0, so no blip
fires for ~a minute — the readout is what shows the view is live). Slider drag → `set_param`.
`net/sandbox_verify.gd` is the headless step-7 proof (the `seam_test.gd` analog): drives the REAL
`tools/server.jl` through `SimClient` and asserts the §8 done-criterion as machine checks —
handshake carries both knobs + values + fidelity, state entities sorted `[radar1, tgt1]` with
SNR/Pd telemetry, **`set_param` rcs_m2 0.1→100 makes `radar1.pd` rise ~0→0.35** (the slider→
core→telemetry loop, which IS the deliverable), realtime advances `t`, clean disconnect. Proven
green end-to-end (server `WARMING→LISTENING→DONE`, verifier `SBV OK`, real exit 0 via the
`_console.exe` build). The verifier exercises only the protocol layer, so `Sandbox.tscn` is ALSO
smoke-loaded headless against a live server (`--quit-after`; assert no `SCRIPT ERROR`/`Parse
Error`/`GDScript backtrace` and that the server reaches `DONE`, i.e. the scene actually connected)
— that's what caught the `class_name` resolution bug and a `%g` (unsupported in GDScript) format
bug. `_draw` (the actual pixel rendering) isn't hit headless, but it has now been **visually
confirmed in a windowed run** (2026-06-21): live SNR/Pd readout, the §12 fidelity badge, the
elevation view (radar triangle + target marker), and the slider→Pd loop all render correctly.

Re-run the seam check: start `pwsh tools/julia.ps1 tools/echo_server.jl`, then
`godot --headless --path clients/godot --script res://net/seam_test.gd`.
Run the real server: `pwsh tools/julia.ps1 --project=core tools/server.jl` (port 8765).
It serves **one** client then exits (HANDOFF "single client v1") — restart it per session.
Watch the sandbox live: start the server, then launch Godot on `clients/godot` (main scene is
`Sandbox.tscn`) — or `godot --path clients/godot`. Re-run the step-7 proof headless: start the
server, then `godot --headless --path clients/godot --script res://net/sandbox_verify.gd`
(exit 0 = pass; it connects as the one client, so the server exits after).
Next: **slice 2 — propagation fidelity** (`two_ray` behind the `propagation` knob; HANDOFF §10).
**Planned** in `docs/plans/slice2.md` (3 staged steps: `rf.jl` two-ray physics + closed-form
`test_propagation.jl` → `radar.jl` propagation dispatch + `set_fidelity` command → Godot fidelity
toggle, Pluto coverage diagram a stretch). The seam is pre-built: `radar.jl` already guards on the
`:propagation` knob and the server handshake already ships `world.fidelity` (the §12 badge).

## Slice 44 — CAN THE SEEKER SEE IT: RANGE / SNR ACQUISITION LIMITS — GATE-0 KILL RECORD (2026-08-18)

**Not a slice — a GATE-0 KILL RECORD. No code shipped; the suite stayed at 7693 (re-run green on a
`git status`-clean tree after revert).** Full record, probes P1/P0a/P7/P0b/P10/P11/P12:
`docs/plans/slice44.md`; raw probe output in `M:\claud_projects\temp\slice44\`. `core/src/missile.jl`
carried a one-line `:probe_r_acq` conjunct twice during the run and was restored from a pre-patch copy
both times (`git status --short` empty, `git diff --stat` empty).

**WHY IT WAS OPENED.** `docs/DEFERRALS.md` named `SEEKER RANGE / SNR ACQUISITION LIMITS` as **the
precondition that would unblock the search-pattern family** — slices 42 and 43 both ended blocked on
*"a wider window is FREE in this model"*, and slice 43's finding 1 sharpened it to *"widening the glass
by 2° and travelling 2° further are THE SAME ACT."* The candidate law was that one aperture serves
both window and reach (`G ∝ θ⁻²` ⇒ `SNR ∝ θ⁻⁴` ⇒ `R_acq ∝ 1/fov`), so widening buys angle and spends
range, giving a V in acquisition time with an interior optimum.

⭐ **THE APERTURE IDENTITY IS EXACT ON THE FLYING WIRE** — `R_acq · fov` constant to **0.0000 %** over a
4× fov range, log-log slope **−1.000000**, and `r_acq` verified against `snr_freespace` (SNR at `R_acq`
= +10.0000 dB at fov 3/6/12) rather than hand-recomputed. **The physics is not what failed.**

⚠⚠⚠ **P1 FIRED AT THE SHIPPED CONFIGURATION AND EVERYTHING AFTER IT IS AN AUTOPSY.** A Ku-band seeker
authored from a real class *before any flight* (200 W, 16 GHz, 10 ms coherent integration, NF 4 dB,
L 5 dB, η 0.6, 10 dB threshold, against the scenario's own `rcs_m2 = 1.0`) gives `R_acq` = **8079 m at
the shipped 10° window against a 6437 m launch range — a ratio of 1.255.** **The missile is launched
INSIDE its own seeker's horizon**, and the gate is not weak but *exactly inert*: `t_lock` 0.0010 s and
miss 0.2237 m, byte-identical to no gate at all.

⭐⭐ **THE COMPOSED V IS REAL AND PRICES NOTHING.** One never-locking flight carries both curves (the
pre-lock trajectory is fov-independent — PN has no rate to act on — so `head_off_deg(t)` and
`los_range(t)` give `t_angle(fov)` and `t_range(fov)` for every fov at once; slice 43 §V.2's method).
The V is INTERIOR at every budget from −12 to +6 dB with the left arm binding on ANGLE and the right on
RANGE, and `fov*` moves ≈1° per 6 dB. **Flown, miss does not follow it:** fov 8.0 angle-limited locks at
t 5.442 / r 2510 and misses by **361.97 m**, while fov 20 range-limited locks at t 5.777 / r 2271 and
**hits at 0.058 m** — the same lock time, the same lock range, opposite verdicts.

⭐⭐⭐ **ISOLATED, THE RANGE GATE IS FREE ACROSS THE WHOLE PLAUSIBLE DOMAIN.** Holding the window wide and
sweeping `R_acq` alone: miss 0.2237 / 0.3491 / 0.3267 / **0.2514** at `R_acq` = none / 4000 / 3000 /
**2000 m** — a lock at **6.158 s of an 8.9 s flight** is indistinguishable from a lock on tick 1. With
the coupling on, sweeping fov at each budget, **a hit remains available down to −26 dB** and the gate
first costs something at **−28 dB** (`R_acq/R_launch` = 0.250) — **a 0.0025 m² target instead of 1.0 m²,
or 1/400 of the transmit power, or 1/400 of the integration time.** Restricting fov to the family's own
1–12° domain does not move that boundary.

**⚠⚠ THE THREE PRE-REGISTERED CHECKS (P12) — TWO OF THEM REFUTED THE FIRST WRITE-UP'S SENTENCES:**
1. ⭐⭐ **THE AUTHORITY COLUMN (P7, unrun on the deciding tables).** *"A delayed acquisition costs
   nothing"* is **too wide**. Peak `a_cmd` after lock runs 573 → 436 → 1040 → **3000.0** at `R_acq` =
   none / 4000 / 3000 / **2000**, against `a_max` = 3000 — **the last free cell spends exactly 100.00 %
   of the airframe's authority** where the no-gate arm spends 19.10 %. ⭐ **The delay is not free; it is
   paid in manoeuvre authority, and MISS cannot show that until the authority runs out.** Past it the
   failure is *not* an authority failure — at `R_acq` 1500 the demand falls back to 20.91 % precisely
   because the track is gone (hold 31.20 %). **Two different limits end the free interval within 500 m
   of each other and miss alone showed neither.** (Slice 41's kill inverted: there a clamp BOUND and
   hid a real effect; here a limit is spent to the last percent under a flat headline metric.)
2. ⚠⚠⚠ **THE NARROW-WINDOW FAILURE IS THE SERVO'S, NOT THE WINDOW'S — and the first write-up's
   *"a late lock with WRONG POINTING is fatal"* is REFUTED.** At fov 8.0 / 8.6 / 8.8 the shipped 8 °/s
   head misses by 361.97 / 438.89 / 402.17 m holding the track 1.24 / 0.71 / 0.63 % of the time; at
   **30 °/s the same arms hit at 0.2209 / 0.1931 / 0.1036 m with hold ≥ 99.97 %, from IDENTICAL lock
   instants** (5.4420 / 4.1470 / 3.6980). ⭐⭐ **A lock at the window's edge hands the servo a
   full-window slew, and at 8 °/s it cannot close 8.6° before the LOS runs away** — slice 35's axis
   alone, not 32/34's. ⚠ 30 and 60 °/s are byte-identical on every row, so this is a THRESHOLD
   somewhere in (8, 30] and is NOT bracketed.
3. ⭐ **HALF `dt` (P6).** The free/broken boundary the −28 dB figure hangs off is **step-independent**
   (the broken cell reproduces to 2 % and its hold % to 0.2 points across 2e−3 / 1e−3 / 5e−4). ⚠ But
   **failure MAGNITUDES walk hard with `dt`** (320 → 439 → 627 m on the servo arm) ⇒ **quote the
   VERDICT, never the metres, on any arm that has lost the track.**

⚠ **AN INHERITED CLAIM CONTRADICTED IN PASSING, FLAGGED NOT BURIED:** slice 43 recorded this wire's
verdict as **BIMODAL** (*"largest rescue 0.3398 m, smallest failure 305.1118 m, nothing between"*).
Two cells here land inside that gap — **7.7996 m at hold 55.04 %** and **85.84 m at hold 31.20 %**.
**There is a PARTIAL-RESCUE mode** (acquire, hold part of the endgame, lose it) that slice 43's grid
could not produce. Recorded so a later slice does not meet it as a surprise.

> ⭐⭐⭐ **THE VERDICT, AND IT IS THE OPPOSITE OF WHAT THE DEFERRAL PROMISED.** `SEEKER RANGE / SNR
> ACQUISITION LIMITS` **does not unblock the search-pattern family**. A wider window still costs
> nothing at any plausible budget, and where it finally does, the cost belongs to slices already
> shipped. ⭐⭐ **THE REASON IS THE TRANSFERABLE RULE: A DETECTION GATE CAN ONLY PRICE A DESIGN
> VARIABLE IF THE ENGAGEMENT IS LAUNCHED OUTSIDE THE SENSOR'S HORIZON** — and that is a property of
> the WIRE, not of the seeker. Slices 26–43 fly a 6.4 km / 8.9 s TERMINAL engagement chosen for the
> radome loop. ⇒ **The precondition is RENAMED: what a search-pattern slice needs is an engagement
> launched beyond the seeker's horizon — a MIDCOURSE phase — and that is its own slice**, because
> this wire's missile is unpowered with zero drag area at 3000 m, so a 20 km engagement takes ≥28 s
> over which gravity alone drops it **3845 m, into the ground.**
