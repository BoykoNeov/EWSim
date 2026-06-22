# EWSim — working notes for Claude Code

Teaching-through-play simulator for EW / air defense / GPS / missile guidance.
A headless Julia **core holds the truth**; Godot and Pluto are thin, replaceable
clients. **`HANDOFF.md` is the ground-truth design** — read it before changing
architecture, and don't relitigate its frozen decisions inside a slice.

## How to run things (Windows)

Julia 1.11.9 is installed portably and is **not on PATH**. Always go through the
wrappers so the path lives in exactly one place:

- Run tests:  `pwsh tools/test.ps1`
- Any Julia:  `pwsh tools/julia.ps1 <args>`   (e.g. `pwsh tools/julia.ps1 tools/setup.jl`)
- Godot 4.7:  `& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"`

PowerShell 5.1 mangles double quotes passed to `julia -e`. **Put Julia code in a
`.jl` file and run the file** rather than fighting inline `-e`.

## Where things live

- `core/src/` — the engine. `world.jl` (World/Entity/Vec3), `subsystem.jl` (the
  tick contract), then physics libs (`rf.jl`, `detection.jl`, ...) as slices land.
- `core/test/runtests.jl` — the contract enforcer. New model ⇒ new test here.
- `clients/godot/`, `clients/notebooks/` — thin clients. **No physics here.**
- `scenarios/*.yaml` — declarative source of truth for runs, tests, MC inputs.
- `docs/plans/` — staged plans / context / task checklists.

## Invariants that catch the real bugs

- **Physics lives in the core, never in a Godot script or a notebook cell.** If
  it can't run headless from `runtests.jl`, it's in the wrong place.
- **Units / frames / signs are the bug trifecta.** SI Float64 internally,
  inertial frame, quaternion body<-inertial = `[1,0,0,0]`. Test frame round-trips
  and LOS-rate signs from day one.
- **Determinism is on CPU.** Same seed + same scenario ⇒ bit-identical trace
  (enforced by `test_determinism.jl`). GPU is for bulk statistics only, never replay.
- **Approximations are switchable and named.** Every subsystem carries a
  `fidelity` knob; dialing it and watching what changes *is* the lesson. No hidden
  approximations, never simulate at carrier frequency (work at baseband / link budget).

## Current status

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
`ca` masks tgtA (1 marker, threshold "towers" over the close pair) / `os` resolves both (flatter
threshold, 2 markers) / `fixed` flat threshold → clutter-band false-alarm storm (40 markers); the
threshold curve is the shipped core output, axes/legend/badge render. (One cosmetic fix landed: the
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
the PNGs). The three rungs render the lesson exactly: `ca` 1 marker + threshold towers (tgtA masked),
`os` 2 markers + flatter threshold (both resolve), `fixed` flat threshold + ~40 clutter-band false
alarms. Numbers were already wire-verified (`slice3_verify.gd`); the picture is now eyeballed too — no
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

**Next: slice 4 — see HANDOFF §10 for the next showcase (item 4).**

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
