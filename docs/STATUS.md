# EWSim — as-built status ledger (per-slice completion notes)

This is the detailed, gate-by-gate as-built record for every completed slice —
moved verbatim out of `CLAUDE.md` to keep the always-loaded design doc lean.
`CLAUDE.md` carries the short status + distilled conventions; reach here for
slice archaeology (exact numbers, test names, watch-items, advisor-catches).
Pre-implementation design plans live in `docs/plans/sliceN.md`.

---

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
