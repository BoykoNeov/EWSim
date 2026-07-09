# Slice 13 — countermeasures: a decoy that seduces a CFAR-scanning seeker + a discrimination gate (the suite-fusing slice)

HANDOFF **§10 item 12** — *"Countermeasures — chaff (= RGPO), flares (IR decoys); seeker discrimination = the
EW/CFAR sandbox. This stage **fuses the whole suite**."* The missile guidance arc (slices 8–12) is COMPLETE;
slice 13 opens the countermeasures arc by putting a **decoy** in front of the seeker and lifting **the slice-3
CFAR sandbox onto the seeker's angle axis**. The lesson is **seduction vs discrimination**: the seeker forms a
noisy **angular power profile**, CFAR-**detects** the peaks (target + decoy), and either blends them (an
amplitude-weighted centroid walks the seeker OFF the truth → a **miss**) or **discriminates** — a validation gate
on the α-β predicted LOS rejects the separated decoy and holds the intercept. Source of truth: HANDOFF §10 item 12
+ **§9** (the shared-library reuse map — *"RGPO range-gate pull-off in the EW jamming sandbox is mechanically
identical to GPS spoofing … and to a missile seeker being walked off by a decoy. One model, three lessons."*) +
§11 Tier A (the deferred horizon).

**SCOPE FORK (b) IS RATIFIED (user, 2026-07-02).** The plan is written around **(b) — a full continuous
angular-profile CFAR-scan seeker** (the slice-3 CFAR sandbox lifted into the angle axis), NOT the smaller
two-discrete-return option (a). This is the more literal reading of "seeker discrimination = the EW/CFAR sandbox,"
and it is materially bigger: a per-look angular power profile, a CFAR scan over angle bins, a peak
cluster-and-extract front-end, and a NEW `:scan` seeker rung — with the determinism consequences named below.

## RGPO is REALIZED here, NOT deferred — in the coordinate the seeker actually tracks (advisor)

Do NOT write "RGPO deferred" — that dodges the slice's billing. §9 states outright that a **seeker walked off by
a decoy IS the RGPO model** ("match the peak, then drag it"). The slice-11 seeker tracks the LOS **angle** (range
/`Vc` are truth by an explicit slice-11 scope decision), so slice 13 realizes the RGPO *match-then-drag* mechanic
**in angle**: the decoy is born near the target (a lobe co-located in the angular profile — matched), then
separates (its lobe drifts across the bins — dragged), pulling the extracted bearing. What is genuinely deferred
is the **range-gate** RGPO variant against a **tracking radar** — a *range* gate the seeker does not have, which
belongs in a future radar-tracking slice, NOT bolted onto an angle-only seeker (that would fight the slice-11
"Vc/range is truth" decision and add a range tracker this slice doesn't need). Name it that way (the deferred
piece is the *range-gate-against-a-radar*, not "RGPO").

## THE FUSION lives in the DISCRIMINATION half — CFAR *detects*, the α-β gate *discriminates* (advisor, load-bearing)

The seduction (`:none`) is the easy, correct half. The "**fuses the whole suite**" billing (§10 item 12) is
earned — or not — in the **discrimination** half, and the two reused libs do DIFFERENT jobs (do NOT conflate them
into a vague "gate"). Under (b) BOTH roles are non-trivial (the advisor's upside — the fusion is STRONGER than the
degenerate two-return threshold of (a), not just bigger):

- **CFAR (detection.jl) is the DETECTOR, not the discriminator — and under (b) it does a REAL job.** §9's "seeker
  discrimination = the same thresholding problem" is a **partial** analogy: `cfar_scan` runs the slice-3 CA/GO/SO/OS
  adaptive threshold over a NOISY angular profile and reports *which bins hold a return above the clutter floor* —
  a genuine peak-detection problem (two lobes in fast-Rayleigh noise), not the degenerate two-scalar threshold of
  (a). It tells you *a second return appeared in the beam*. It does **NOT** tell you *which* peak is the target: a
  **bright** flare/chaff lobe is a strong CFAR *detection*, not a rejection. **CFAR alone cannot reject a brighter
  decoy.**
- **The α-β predicted-LOS validation GATE (estimation.jl) is the discriminator — and that gate IS the RGPO
  track-gate** (the gate is precisely what RGPO captures and drags). It reuses slice-11's α-β filter *state* (the
  predicted bearing `λ_pred = λ_est + λ̇_est·dt`), NOT detection.jl.
- **So the fusion is HONEST when both fire in their own role:** detection.jl (`cfar_scan`) *detects* the peaks in
  the noisy angular profile (the decoy lobe crossed threshold); estimation.jl (α-β predicted gate) *discriminates
  which peak to keep*. Then:
  - **`:none`** → intensity-weighted **centroid of ALL detected peaks** → the seeker is **seduced** (blends the
    target and the brighter/separating decoy → the tracked bearing walks off).
  - **`:gated`** → keep only the peaks **inside the gate** around the α-β predicted track, centroid those → the
    decoy leaves the gate as its lobe separates → **rejected**, the seeker **holds**.

Under (b) this is a **full continuous angular profile** (N_bins cells, a beam-shaped lobe per return, a CFAR scan)
— the slice-3 range-power sandbox with the **axis relabeled range→angle** and the SAME pure `cfar_scan`
(detection.jl is NOT touched — its entry points are already generic power-vector + cell-index; see landmarks).

## THE DETERMINISM SHAPE — the RNG inflection RE-INVERTS to *APPLIES*, and the class is 4b (NOT slice-11's 4a)

The missile-arc RNG story has flip-flopped across the arc — **name this beat, copy neither neighbour verbatim:**

- Slices **8/9/10** — no RNG → "draw-count invariance is VACUOUS."
- Slice **11** — the Seeker is the FIRST `w.rng` consumer → conventions 3/11 **APPLY** ("1 draw/tick").
- Slice **12** — no seeker → no draw → the inflection **INVERTS BACK** ("vacuous" again).
- Slice **13** — the seeker is **BACK** (the decoy seduces a *seeker*) → `w.rng` draws again → the inflection
  **RE-INVERTS to APPLIES.** Conventions 3/11 apply again; slice-12's "no-RNG / vacuous" boilerplate is WRONG
  here (the convention-4c trap running the SAME direction as slice 11, opposite to slice 12).

**BUT the fidelity CLASS is 4b, NOT the slice-11 4a — this is the (b)-specific pivot; do NOT copy slice-11's clean
"introduce-safe class-4a" language (advisor — the copy-paste false-claim trap, convention 4c).** Two dimensions,
two classes:

- **The `:scan` seeker rung is CLASS 4b (draw-topology-flipping — the `:cfar` shape, introduce-REJECTED).** A
  genuine CFAR needs a NOISY per-bin floor to threshold against (a noise-free profile makes CFAR vacuous — which
  would defeat the whole reason (b) was chosen). So `:scan` builds the profile with `_draw_profile!` →
  **2·N_p·N_bins `randn`/tick** (radar.jl:491 draws 2·N_p per cell, cell-by-cell in index order), a **topology
  flip** from slice-11 `:filtered`'s **1/tick**. Exactly like slice-3 `:cfar` flipping point→profile draws:
  **`set_fidelity` must REJECT any switch that INTRODUCES or REMOVES `:scan`** (1 ↔ 2·N_p·N_bins desyncs replay).
  `SEEKER_MODES` therefore gains **MIXED introduce-safety**: `:raw↔:filtered` stays **bit-identical** to switch
  (both 1/tick — the slice-11 property, PRESERVED unchanged), but **any switch touching `:scan` is rejected** (the
  cfar-style guard, one dimension over).
- **`discrimination ∈ (:none, :gated)` is draw-invariant AMONG its rungs, trajectory-changing, and NESTED in the
  4b `:scan` context.** Both rungs build the SAME profile (same 2·N_p·N_bins draws, same order) and differ ONLY in
  post-detection peak extraction (blend-all vs gate-then-blend) → a `:none↔:gated` toggle is **draw-count
  invariant** and **introduce-safe** (unlike `:scan` itself), **YET TRAJECTORY-CHANGING** (the toggle MOVES the
  missile — not a dead knob). It is **INERT unless `seeker=:scan`** (no `:scan` → no angular profile → no peaks to
  discriminate → the key does nothing), the exact **`:raim`-inert-without-GPS coupling** (name it that way). This
  is NOT free-standing class 4a — it is "draw-invariant within a 4b host"; writing "class 4a like slice-11
  `:seeker`" is the false claim.

The three additivity claims (the byte-identity master check — slices 1–12):

1. **Introduce-safe / additivity — via the mode, NOT a live toggle.** Absent a `:scan` seeker AND absent a
   `:decoy`, nothing new runs: a slice-1..12 scenario is **byte-identical**. Slices 1–12 use `:raw`/`:filtered`
   (or no seeker) → **1-or-0 draws/tick, UNCHANGED** — `:scan`'s 2·N_p·N_bins topology is reached ONLY by a
   scenario that DECLARES `seeker=:scan` at LOAD (the cfar precedent: topology is per-scenario-config, fixed at
   load, not live-introducible). A slice-11 `:filtered` scenario replays **bit-identical** after the
   estimation.jl/missile.jl/radar.jl edits.
2. **Same-config replay is bit-identical** — deterministic; `:scan`'s 2·N_p·N_bins draws are in lockstep on both
   discrimination rungs (same profile, same order).
3. **A `:none↔:gated` toggle CHANGES the trajectory** (the not-a-dead-knob property) with the RNG in **lockstep**
   (both rungs draw the same 2·N_p·N_bins — the difference is post-detection extraction, ZERO draws) — the
   slice-11 `:raw↔:filtered` *value-changes-not-draws* shape, one level up. **Draw-count invariance is NOT vacuous
   here** (there is an RNG stream); it is the sharp property to PROVE for the `discrimination` dimension
   (convention 3) — the opposite of slice 12.

**THE SHARPEST DRAW TRAP (convention 3, advisor).** The per-tick draw count must be invariant to the
`discrimination` rung, to the number of decoys, AND to the separation state. **The FIXED angular grid is what
guarantees it:** `_draw_profile!` draws `2·N_p·N_bins` regardless of how many lobes are painted (K returns paint
K lobes onto the SAME fixed `power` vector, THEN one 2·N_p-per-cell noise pass) — so the count is
decoy-count-independent BY CONSTRUCTION. A per-return or per-detection draw would make the count depend on decoy
presence → desync replay the instant a decoy blooms. **Paint-then-draw-the-fixed-grid, never draw-per-return.**
Inherit `_draw_profile!`'s EXACT count/order (2·N_p per cell, cell-by-cell) — do not re-roll it (the one-list
discipline for the draw itself; radar.jl:491 is the source of truth).

## The decoy is a NEW `kind` `:decoy` — NEVER `:target` (advisor — the truth-path hijack)

`_nearest_target` (radar.jl:221, `kind === :target`) is consumed by the **radar**, the **jammer boresight**, AND
the **autopilot's truth path** (`Autopilot.decide!` `_nearest_target`, missile.jl:275) + the **CPA/miss
telemetry**. A `:target`-kind decoy that sits *closer* would hijack ALL of them — the miss would be measured
against the **decoy**, and the slice-9/10/12 truth-fed fallback would silently break. So the decoy is a **new
`kind` `:decoy`**: the **Seeker's `observe!`** paints `:target` + `:decoy` lobes into its angular profile (it is
the ONLY consumer that sees decoys), while `_nearest_target` — and therefore the miss/CPA readouts and every prior
slice — still returns the **true target**. **THE INVARIANT (the lesson made visible):** the seeker is *seduced*,
but **miss/CPA is ALWAYS computed vs the true `:target` entity** — the number that opens under `:none` is the
honest miss against the thing the missile was supposed to hit. State this in the verifier + a test.

## The lesson (shown as numbers — the LANDING IS EMPIRICAL, the slice-12 discipline)

**A decoy seduces the undiscriminated CFAR-scanning seeker; the α-β gate rejects it.** Against a decoy whose lobe
is born near the target's and **separates** across the angular bins (a competing peak + intensity):

- **`:none` (no discrimination) is seduced.** The intensity-weighted centroid of the {target, decoy} detected
  peaks tracks a bearing *between* them, weighted toward the brighter/stronger lobe; as the decoy lobe separates
  the centroid walks OFF the target, PN guides toward the blend → a **miss** (and/or an inflated tracked-bearing
  error — the split is the **gate-0 probe's** call, exactly the slice-12 "miss vs a_cmd" empirical fork).
- **`:gated` (discrimination on) holds.** CFAR-detect the peaks; keep only those inside the validation gate
  centered on the α-β **predicted** bearing; the decoy peak leaves the gate as its lobe separates → excluded → the
  seeker tracks the true target → **tight intercept** (≈ the slice-11 no-decoy miss under `:scan`).

**⚠ CAUTION — do NOT pin the landing from theory (the slice-12 lesson VERBATIM).** Slice 12's probe found plain
PN **intercepts anyway** under a generous `a_max` (the miss lesson needed a *binding* constraint). Analogously,
whether `:none` opens a **real miss** depends on the **intensity ratio**, the **separation rate**, the **CFAR
detectability** (both lobes must cross threshold), and the **timing** (bloom-near-then-drift). The probe MUST
report `miss(:none)` vs `miss(:gated)` **AND** the tracked-bearing error (λ_used − λ_truth) for both, and **pick
the headline from the data** (miss-ratio if the miss opens; bearing-error contrast if the missile intercepts
anyway under a generous `a_max` — then, as in slice 12, consider a **binding `a_max`** so the seduced high-λ̇
demand SATURATES → misses). **Pin the RATIO, not absolutes** (the [[ewsim-missile-verifier-sampling]]
frame-sampling floor). Design the intensity ratio + separation + beam/grid so the lesson is UNAMBIGUOUS (`:none`
visibly fails on the chosen headline; `:gated` recovers the `:scan` no-decoy baseline).

**The gate can ALSO fail (name the failure regime — advisor).** `:gated` works BECAUSE the seeker locks the true
target FIRST (the decoy lobe is born near-co-located) and the decoy lobe then LEAVES the gate. If the decoy lobe
starts already separated, or is bright enough to pull the *predicted* track before it exits the gate, or the gate
is too wide, `:gated` can still be seduced. The probe pins the **near-co-location + separation-velocity** geometry
(the seeker locks truth first) AND the gate half-width so `:gated` is robust across the run — and reports the
window, so a learner's slider nudge can't silently erase the lesson (the slice-12 `a_max ∈ [100,350]` window
discipline).

## Scope — one lesson per scenario (fork (b) RATIFIED)

A single guided **interceptor** (`[BallisticMissile, Seeker, Autopilot]` — the slice-11 stack, now RNG-drawing at
2·N_p·N_bins under `:scan`) against a single **true target** (`[ConstantVelocity]`) **plus one `:decoy`**
(`[ConstantVelocity]`, the new `kind`). Held: **`seeker = :scan`** (the NEW angular-profile-CFAR path — the gate
reuses its α-β predicted state) and **`autopilot = :ideal`, `guidance = :pn`** (so the miss isolates the
**discrimination** lesson, the slice-10/11/12 isolation discipline). The switchable **fidelity is
`discrimination ∈ (:none, :gated)`** — the NEW key; the lesson is the `:none↔:gated` compare. **Deferred, NAMED
(convention 9):**

- **The range-gate RGPO variant against a tracking radar** (a *range* gate the angle seeker lacks — a future
  radar-tracking slice; § "RGPO is realized here" above), NOT this slice.
- **RF-vs-IR seeker split / an IR environment channel in `env`** (§11 Tier A — "add an IR environment channel to
  `env`, reuse `frames.jl`/`estimation.jl`"). Slice 13 models ONE **generic** decoy: an angular lobe + a relative
  **intensity** scalar. **Chaff (RF, intensity = RCS ratio, seduces an RF seeker) and a flare (IR, intensity =
  radiant-intensity ratio, seduces an IR seeker) are the SAME mechanic at this fidelity** — the domain is flavour
  (which seeker, which intensity units); per convention 9 the scenario picks ONE (chaff shown; flare is a label).
- **Decoy dynamics** — bloom expansion, burn-out intensity decay, timed ejection, a gravity/drag flare-fall
  (a `[BallisticMissile]`-style mover would couple the decoy to the missile's `:integrator` — a cross-lesson leak,
  the slice-12 `ManeuveringTarget`-is-always-`:rk4` precedent). Slice 13 decoy = **constant-velocity, constant
  intensity, present from t=0** (named approximations).
- **2-D angular profile (az×el) / monopulse amplitude-comparison / true beam sidelobes** — slice 13 scans ONE
  angle (the in-plane LOS `λ = atan(Δz,Δx)`, the slice-11 scalar), a **1-D** angular profile (the slice-3
  1-D-range-window reused as a 1-D-angle window). A 2-D sky profile + monopulse is a later fidelity.
- **Multiple simultaneous decoys / salvo** (the machinery paints N lobes; the scenario ships ONE — one lesson).

**One scenario** (one lesson; the button toggles `:none↔:gated`; the decoy geometry is fixed in the scenario).
3 review gates + a gate-0 probe (mirroring slices 5–12).

## The physics / math (named approximations — HANDOFF §1)

### 1. The `:decoy` entity + the intensity field (the lobe amplitude)

A new **`kind` `:decoy`** entity, moved by the existing **`ConstantVelocity`** (radar.jl) — passive, no new mover.
Both the `:target` and the `:decoy` carry a **`comp[:intensity]`** scalar (dimensionless relative brightness — the
RCS ratio for chaff, the radiant-intensity ratio for a flare; the **lobe amplitude** in the angular profile and
the centroid weight). Named approximations: **constant** intensity (no bloom/burn-out/aspect dependence),
**constant velocity** (no fall/deceleration), **present from t=0** (no timed ejection). Geometry (probe-pinned):
the decoy is born **near-co-located** in angle with the target and carries a **separation velocity** so the lobe
pull develops OVER the engagement (born already-separated → the seeker never locks truth first → `:gated` can't
work; the § "gate can fail" note). Config guard: `intensity ≥ 0` at LOAD (a live huge value just paints a taller
lobe, no crash).

### 2. The angular-profile front-end (the slice-3 CFAR sandbox, axis relabeled range→angle)

A **fixed** angular grid of **N_bins** cells spanning a field of view **FOV** about the seeker's boresight (bin
resolution `dλ = FOV/N_bins`) — load-fixed, geometry-independent (the determinism grid). Each return (target +
each decoy) paints a **beam-shaped lobe** `intensity · beam(λ_bin − λ_return)` into a deterministic linear-power
`power` vector over the floor (floor = 1.0, the homogeneous noise the CFAR α calibrates against — the slice-3
convention). Then:

    _draw_profile!(z, power, w.rng, n_pulses)               # radar.jl:491 REUSED — 2·N_p·N_bins randn, cell-by-cell
    threshold, detections = cfar_scan(z; variant, n_train, n_guard, pfa, n_pulses)   # detection.jl REUSED, PURE
    peaks = extract_peaks(z, detections, axis)             # cluster contiguous detections → (λ_peak, strength) list

- **`beam(Δλ)`** — a load-fixed **Gaussian** lobe `exp(−½(Δλ/σ_beam)²)` (named approximation; sinc/boxcar are
  alternatives, Gaussian is the house default — no sidelobes at this fidelity). `σ_beam` (the seeker beamwidth) is
  a load-fixed scenario parameter; the decoy separation must exceed ~a beamwidth for the lobes to resolve into two
  CFAR peaks (a probe-pinned geometry — the "gate can fail" note has teeth here: sub-beamwidth separation = one
  merged blob = no discrimination possible).
- **THE TRAINING-WINDOW MASKING CONSTRAINT (advisor — the slice-3 masked-close-target lesson, on the angle axis).**
  Resolving two lobes (separation ≳ beamwidth) is NECESSARY but NOT sufficient for CFAR to detect BOTH: a second
  strong lobe sitting in the other cell's **training band** (`_cfar_estimate`, detection.jl:494 — the estimate is
  built from `[cut−guard−half, cut−guard−1] ∪ [cut+guard+1, cut+guard+half]`) INFLATES the noise estimate → raises
  that cell's threshold → **MASKS the weaker peak** (the exact slice-3 close-target masking, CLAUDE.md slice-3
  line). This has a LESSON consequence, not just a physics one: a **masked decoy** → `:none` isn't seduced (only
  the target detected); a **masked target** → `:gated` has nothing to hold — **either way both modes track the
  target and the lesson COLLAPSES to "both intercept."** So the separation is a **WINDOW**: bounded BELOW by the
  beamwidth (resolve) and complicated in the middle by mutual training-window masking. **The decoy separates OVER
  the engagement**, so the geometry must keep the relevant peaks detected across the WHOLE separation sweep the run
  traverses — separation must clear the **guard+training span**, not merely the beamwidth. The gate-0 probe pins
  this (sweep the separation the engagement actually reaches; confirm both peaks survive CFAR at every step).
- **`cfar_scan` / `cfar_threshold` / `_cfar_estimate` are REUSED UNCHANGED** (detection.jl — they already take a
  bare `AbstractVector{<:Real}` power vector + cell indices; ZERO radar/Swerling coupling — the "1-D range-only
  window" approximation becomes a "1-D angle window," same code, relabeled axis). **detection.jl is NOT edited**
  (the byte-identity-critical path stays untouched; the "fuses the suite" reuse is HONEST — the slice-3 lib does a
  real job on the angle axis). The scenario carries the CFAR config (`variant`/`pfa`/`n_train`/`n_guard`,
  `n_pulses=1` natural for a single-look seeker) — load-fixed, reusing the slice-3 knob names.

### 3. The seeker-processing primitives (estimation.jl — pure, RNG-free, no LinearAlgebra)

FOUR NEW pure functions (gate-1), tested closed-form, all **wrap-safe** (bearings are `atan(Δz,Δx) ∈ [−π,π]`; a
naïve weighted mean bugs at the ±π seam — average the WRAPPED deltas about a reference, the strongest cell's
bearing — the §1 wrap trifecta, the slice-5 `wrap_angle` precedent):

    bearing_to_bin(λ, grid) -> Int      # and its inverse bin_to_bearing(i, grid) -> λ
        # the bearing↔bin mapping (FOV, N_bins, boresight) — PURE + TESTED (advisor: the ±π-wrap AND off-by-one
        # bin arithmetic hide in the painting half; do NOT bury this in observe!). Closed-form round-trip test.

    extract_peaks(power, detections, axis) -> Vector{(λ_peak, strength)}
        # cluster CONTIGUOUS runs of detections==true; each cluster → intensity_centroid of its cells' bearings
        # (weighted by power), strength = Σ power over the cluster. NO detection anywhere → empty (see fallback).

    intensity_centroid(bearings, intensities) -> λ_c
        # λ_ref = bearing of the strongest weight; λ_c = wrap_angle(λ_ref + Σ Iᵢ·wrap_angle(λᵢ−λ_ref) / Σ Iᵢ)
        # ONE bearing → returns it EXACTLY. Used BOTH within a cluster (peak angle) AND across peaks (:none blend).

    validation_gate(bearings, intensities, λ_pred, halfwidth) -> (kept_bearings, kept_intensities)
        # keep peak i iff |wrap_angle(λᵢ − λ_pred)| ≤ halfwidth; the RGPO track-gate about the α-β prediction.
        # Empty gate (all peaks left) → fall back to the FULL peak set (never track nothing — the "can't crash" guard).

- **`DISCRIMINATION_MODES = (:none, :gated)`** in estimation.jl; **`:scan` appended to `SEEKER_MODES`**
  (`= (:raw, :filtered, :scan)`) — both the one-list source of truth defined **before radar.jl**;
  `LIVE_FIDELITY_MODES` REFERENCES them — no re-list, the drift-catch.
- **`extract_peaks` uses `intensity_centroid`** for each cluster's angle (the within-cluster extractor) — the
  primitive serves double duty (within-cluster peak angle AND cross-peak `:none` blend). Wrap-safe throughout.
- **The gate center is the α-β PREDICTION** `λ_pred = λ_est + λ̇_est·dt` — reusing the slice-11 filter STATE
  (`c[:seek_lambda_est]`, `c[:seek_lambdadot_est]`), the RGPO track-gate made concrete. Reuse `alpha_beta_los_step`
  and its `wrap_angle` innovation UNCHANGED.

### 4. The Seeker `observe!` extension (missile.jl — the profile/scan/gate seam)

`Seeker.observe!` (missile.jl:433) today draws **1 `randn`** (line 438, unconditional) then reads `_nearest_target`
for a lone truth bearing (`:raw`/`:filtered`). Slice 13 adds the **`:scan` branch** (dispatch on
`get(w.fidelity, :seeker, :filtered)`):

    if seeker === :scan
        power = _paint_angular_profile(w, e, {target}∪{decoys}, grid)   # deterministic lobes over the floor
        _draw_profile!(z, power, w.rng, n_pulses)                       # THE 2·N_p·N_bins draws (topology flip)
        _, detections = cfar_scan(z; variant, n_train, n_guard, pfa, n_pulses)
        peaks = extract_peaks(z, detections, axis)                      # (λ_peak, strength) list
        cand_b, cand_i = (peak bearings, peak strengths)
        λ_meas = discrimination === :gated ?
                     intensity_centroid(validation_gate(cand_b, cand_i, λ_pred, halfwidth)...) :
                     intensity_centroid(cand_b, cand_i)                 # blend ALL peaks (:none) — NO extra draw
    else   # :raw / :filtered — the slice-11 path, VERBATIM (1 randn, _nearest_target) — byte-identical
        n = randn(w.rng); tgt = _nearest_target(w, e); λ_meas = λ_tru + σ·n
    end

then the EXACT slice-11 α-β / raw update on `λ_meas` (`alpha_beta_los_step`; the α-β state feeds `λ_pred` for the
gate) and the slice-11 telemetry PLUS new keys (`decoy_bearing`, `target_bearing`, `lambda_used`, `n_peaks`,
`gated` flag — all SCALARS/small ints, no Array → no `float()`-crash). **THE NOISE MODEL MOVED (name it):** under
`:scan` the measurement noise enters via the **profile's fast-Rayleigh floor** (the 2·N_p·N_bins draws), NOT an
added `σ·randn` output draw — the resolved centroid already carries noise from the noisy profile. So `:scan` draws
**exactly 2·N_p·N_bins** (no +1); `:raw`/`:filtered` keep their **1**. **DEAD-KNOB SURPRISE — name it (advisor):**
because the noise moved into the profile floor, the slice-11 **`sigma_seek` slider goes INERT under `:scan`** (it
scaled the removed output draw) — the live noise knob is now the **profile SNR / `pfa`** (lobe amplitude over the
floor). A learner arriving from slice 11 must be told `sigma_seek` does nothing here (badge/readout note + the
STATUS line), NOT left to discover a silently-dead slider. **FIRST-TICK `λ_pred` BOOTSTRAP (advisor):** the α-β
state is empty at t=0 so the gate's predicted bearing is undefined on tick 1 — the **empty-gate→full-set
fallback** (§3) covers it (an undefined/degenerate `λ_pred` gates nothing out → the full peak set → the `:none`
blend on tick 1, harmless with the near-co-located start), but state it explicitly (the α-β warm-up is where
`:gated` could spuriously reject early — do NOT lean on the catch-all). **BYTE-IDENTITY (slices 1–12):** the
`:scan` branch is UNREACHABLE without `seeker=:scan` in the scenario; `:raw`/`:filtered` take the slice-11 line
**textually unchanged** (the 1-randn `λ_tru + σ·n`) → slices 1–12 byte-identical BY CONSTRUCTION. Keep the whole
profile/scan block **INSIDE the `:scan` branch** so the `:raw`/`:filtered` arithmetic is bit-untouched (the
slice-12 `a_T`-fetch-inside-the-branch precedent; the `+0.0` bit trap — use the slice-11 spelling verbatim in the
non-`:scan` arm).

### 5. Fidelity plumbing — `:scan` (4b) + `discrimination` (nested draw-invariant)

`SEEKER_MODES += :scan` and `LIVE_FIDELITY_MODES += discrimination = DISCRIMINATION_MODES` (radar.jl,
one-list-no-drift; `_validate_fidelity` picks up the new tuple automatically). **`set_fidelity` gains ONE guard
(the cfar precedent, mirrored):** **reject a `seeker` change that introduces OR removes `:scan`** (1 ↔
2·N_p·N_bins draw-topology flip — the byte-identity killer); `:raw↔:filtered` and `:none↔:gated` stay live-safe.
Class map: `:scan` = **4b** (topology-flip, introduce-rejected — like `:cfar`); `discrimination` = draw-invariant
among its rungs + trajectory-changing + **inert unless `seeker=:scan`** (the `:raim`-without-GPS coupling; NOT
free-standing 4a). Orthogonal held keys: slice-13 scenarios pin `seeker=:scan`, `guidance=:pn`, `autopilot=:ideal`
so the ONE button toggles the ONE discrimination lesson (convention 9).

## Decisions to take at gate 0 (surface to the advisor before gates 1–3)

1. **The HEADLINE — miss-ratio vs bearing-error/saturation contrast** (the slice-12 empirical fork). Report
   `miss(:none)`/`miss(:gated)` AND the tracked-bearing error for both; pick from the data; pin the RATIO. If the
   missile intercepts anyway under a generous `a_max`, consider a **binding `a_max`** (the slice-12 pivot).
2. **The angular grid + beam + CFAR config + the SEPARATION WINDOW** — `N_bins`, `FOV`, `σ_beam`,
   `variant`/`pfa`/`n_train`/`n_guard` (`n_pulses=1`) so the target and decoy lobes RESOLVE into two CFAR peaks
   (separation ≳ a beamwidth) AND neither lobe MASKS the other via its training window (separation must clear the
   **guard+training span** — the slice-3 masked-close-target lesson, advisor). Since the decoy separates OVER the
   run, the probe SWEEPS the separation the engagement actually traverses and confirms BOTH peaks survive CFAR at
   every step (a masked peak collapses the lesson to "both intercept"). Pin `:none` seeing two peaks (seducible)
   AND a clean two-lobe detection (no spurious noise-peak flood — a Pfa/CFAR-loss tradeoff).
3. **Intensity ratio + separation geometry + timing** — the probe picks `I_decoy/I_target`, the separation
   velocity, and the near-co-location start so `:none` UNAMBIGUOUSLY fails on the chosen headline AND `:gated` is
   robust (locks truth first, decoy lobe exits the gate) AND the first CPA is CLEAN (advisor — a seduced
   trajectory can re-cross; [[ewsim-missile-verifier-sampling]]).
4. **The gate half-width** — wide enough to hold the true-target peak through the run, narrow enough to reject the
   separated decoy peak; report the robust window (a learner's nudge can't erase the lesson — the slice-12
   discipline).
5. **The draw count is EXACTLY 2·N_p·N_bins** on both discrimination rungs and independent of decoy count /
   separation / spurious-peak count (convention 3 — the determinism keystone; paint-then-draw-the-fixed-grid, NOT
   per-return/per-detection). `:raw`/`:filtered` still exactly 1.
6. **The gate/centroid/peak-cluster SIGN + wrap are right** — `miss(:gated) < miss(:none)` closed-loop AND a
   direct `intensity_centroid`/`validation_gate`/`extract_peaks` recompute (a DIFFERENT expression) in
   `test_estimation.jl` (the slice-10/12 two-source sign-pin; the ±π wrap seam is the trap).
7. **Miss/CPA is measured vs the true `:target`, never the `:decoy`** — confirm `_nearest_target` still returns
   the target (the decoy is `kind === :decoy`); the verifier asserts the number is the honest truth-miss.
8. **`:scan` introduce/remove is REJECTED, `:raw↔:filtered`/`:none↔:gated` are live** — the mixed-introduce-safety
   guard (advisor #5, the cfar precedent); confirm `set_fidelity` rejects `seeker→:scan` and back.
9. **One scenario, grid/`I`/separation/`a_max`/gate values** — pinned by the probe against the live wire
   (convention 10).

## Review gates (cadence: staged, mirroring slices 5–12)

0. **Gate-0 probe (throwaway, `M:\claud_projects\temp\slice13_probe\`).** Reuse the REAL core physics
   (`using EWSim`: `total_accel`/`integrator_step`/`los_unit`/`los_rate`/`range_rate`/`pn_accel_from_omega`/
   `clamp_accel`/`alpha_beta_los_step`/`wrap_angle`/`_draw_profile!`/`cfar_scan`), hand-roll only the angular-lobe
   painting, the `extract_peaks`/`intensity_centroid`/`validation_gate` candidates, and the
   observe!→decide!→integrate! loop (`seeker=:scan`, `guidance=:pn`, `autopilot=:ideal`; `:none` vs `:gated`).
   **Confirm + pin numbers:** (i) the grid/beam/CFAR config resolves TWO clean peaks (target + decoy) with no
   noise-peak flood (advisor #2); (ii) `:none` seduced — measure BOTH `miss` and tracked-bearing error, **decide
   the headline** (advisor #1; escalate to a binding `a_max` if PN intercepts anyway — the slice-12 pivot); (iii)
   `:gated` holds (the chosen headline collapses to ≈ the `:scan` no-decoy baseline; report any residual); (iv) the
   intensity ratio + separation + near-co-location start give a **CLEAN FIRST CPA** (advisor — no seduced
   re-cross, endgame spike excluded) AND `:gated` is robust (locks truth first, decoy exits the gate — the gate
   half-width window); (v) **the draw count is EXACTLY 2·N_p·N_bins** on both rungs, decoy/peak-count-independent
   (convention 3); (vi) the SIGN/wrap — `miss(:gated) < miss(:none)` AND a direct centroid/gate/peak recompute
   (advisor #6); (vii) miss vs the **true target** (advisor — `_nearest_target` untouched). Write `FINDINGS.md`,
   pin the grid/geometry/intensities/gate + the `:none`≫`:gated` **RATIO** + conservative one-sided verifier
   bounds. **RE-CONSULT THE ADVISOR after the numbers land** (the landing is the one thing un-settleable from the
   plan — advisor #1). Forward-flag any gate-1/2/3 seams the hand-rolled probe papers over.

1. **Primitive green (pure, closed-form, SI, RNG-free, no LinearAlgebra).** estimation.jl:
   **`intensity_centroid(bearings, intensities)`** (wrap-safe about the strongest weight; ONE bearing → itself
   `===` — the additivity anchor) + **`validation_gate(bearings, intensities, λ_pred, halfwidth)`**
   (keep-within-`halfwidth`, empty→full fallback) + **`extract_peaks(power, detections, axis)`** (contiguous-run
   clustering → per-cluster `intensity_centroid`). **`DISCRIMINATION_MODES = (:none, :gated)`** + **`:scan` into
   `SEEKER_MODES`** (add the tuples; one-list-no-drift). `alpha_beta_los_step`/the existing `SEEKER_MODES` members
   `:raw`/`:filtered` **UNCHANGED** (byte-identity anchor). Export the three fns + `DISCRIMINATION_MODES`.
   `test_estimation.jl` (+ CM arms, explicit `atol`): **the centroid direct-recompute** (a DIFFERENT expression —
   catches a transpose / a wrap slip); **singleton → bearing exactly** (`===`, the additivity property); **two
   bearings → the intensity-weighted mean** (pin the fraction); **the ±π WRAP seam** (a target near +π, a decoy
   near −π → the centroid does NOT jump to 0 — the slice-5 wrap trap, explicit `atol`); **`validation_gate` keeps
   in-gate / drops out-of-gate / empty→full**; **`extract_peaks`: two separated detection runs → two peaks; one
   run → one peak; no detections → empty; a peak's angle = the cluster's power-weighted centroid** (pin against a
   direct recompute); **a symmetric two-return centroid sits at the midpoint** (an external anchor, not a
   self-calibrated round-trip — convention 11). Slices 1–12 byte-identical through the include (golden +
   determinism green; no RNG added — estimation.jl stays pure).

2. **Wired — the `:decoy` mover + the `:scan` profile/scan/gate `observe!` + the `discrimination` rung.**
   `scenario.jl`: a **`:decoy` kind** (`comp[:intensity]` + `[ConstantVelocity]`, LOAD-validated `intensity ≥ 0`)
   + an `:intensity` key on the `:target` + the angular-grid/beam/CFAR config on the seeker (LOAD-validated:
   `N_bins ≥ 1`, even `n_train`, `FOV`/`σ_beam` > 0). `Seeker.observe!`: the NEW `:scan` branch — paint the
   angular profile, `_draw_profile!` (the 2·N_p·N_bins draws), `cfar_scan`, `extract_peaks`, dispatch `:none`
   blend vs `:gated` gate-then-blend on the α-β **predicted** bearing, then the EXACT slice-11 α-β update; the
   **non-`:scan` arm is the slice-11 arithmetic verbatim** (byte-identity by construction). `SEEKER_MODES += :scan`
   / `LIVE_FIDELITY_MODES += discrimination` (radar.jl). `set_fidelity`: **reject introducing/removing `:scan`**
   (the 4b guard). RNG: 2·N_p·N_bins/tick under `:scan`, both discrimination rungs, decoy-count-independent.
   - `test_missile.jl` (+ CM/decoy arms): `:scan` `observe!` paints N lobes + scans + writes the new telemetry;
     **`:none` centroid is pulled toward the decoy** while **`:gated` tracks the true-target bearing** (pin against
     `extract_peaks`/`intensity_centroid`/`validation_gate` on a realized profile); **`miss(:gated) ≪ miss(:none)`
     on the wire** (`seeker=:scan`/`guidance=:pn`/`autopilot=:ideal`, the Lesson pin — or the
     bearing-error/saturation contrast per the probe's headline); **`:none↔:gated` trajectories DIFFER**
     (not-a-dead-knob); **miss is vs the true `:target`, not the `:decoy`** (`_nearest_target` untouched — the
     truth-path invariant); the **2·N_p·N_bins draw-count pin** (Xoshiro-advance, decoy present AND absent — same
     count) AND **`:raw`/`:filtered` still exactly 1** (the mixed-topology pin); loader arms + rejects a negative
     `intensity` / odd `n_train` / `N_bins < 1`.
   - `test_determinism.jl` (the SLICE-11 shape ONE LEVEL UP — NOT slice-12's; watch-item): same-seed bit-identical
     WITH the `:scan` seeker drawing (2·N_p·N_bins/tick); **a slice-1..12 scenario is byte-identical** (no
     `:decoy`, `seeker=:raw`/`:filtered` → the slice-11 lone-target path + slice-11 1-draw — the additivity
     master-check); **`:none↔:gated` toggle CHANGES the trajectory** with the RNG in lockstep (draw-invariant
     among discrimination rungs AND trajectory-changing — do NOT write "no-RNG/vacuous"); a **slice-11
     `:filtered` scenario replays BIT-IDENTICAL** after the estimation.jl/missile.jl/radar.jl edits (the
     RNG-consumer + mode-anchor); **`:scan` introduce/remove REJECTED** (the 4b guard — `set_fidelity seeker :scan`
     on a non-scan missile is refused; the sharpest form), while **`:none↔:gated` and `:raw↔:filtered` introduce
     CLEAN** (the mixed-safety proof).
   - `test_server.jl`: `set_fidelity :discrimination :gated` write/**introduce-safe** (draw-invariant); **`set_
     fidelity :seeker :scan` REJECTED** when introducing/removing (the topology-flip guard, like `:cfar`); the
     `intensity`/gate-halfwidth live sliders `set_param`→tick survive (a huge `intensity`/wide gate does NOT throw
     — "a live slider can't crash a tick"). Slices 1–12 byte-identical.

3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice13_decoy.yaml`
   (`discrimination:none` default — so the button reveals the fix; `seeker:scan`/`guidance:pn`/`autopilot:ideal`
   HELD; the grid/beam/CFAR config + `[BallisticMissile, Seeker, Autopilot]` interceptor + a `[ConstantVelocity]`
   true target + a `[ConstantVelocity]` `:decoy`, the clean-first-CPA + robust-gate geometry from gate 0).
   **Numbers probed against the live `load_scenario→observe!→decide!→integrate!→telemetry` wire** + pinned (the
   probe's headline + conservative one-sided bounds).
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode — the slice-8..12 precedent). The
     `discrimination` discriminator branch is checked **before** `seeker`/`guidance`/`autopilot` (slice-13 ships
     ALL keys; the others held; the ONE button toggles `discrimination` — convention 9, the slice-11 "seeker
     before guidance/autopilot" precedent one lesson deeper); `_on_discrimination_pressed` (`:none↔:gated` ring),
     `DISCRIMINATION_RUNGS`, button/badge. The **NEW VISUAL: the `:decoy` marker** (a distinct glyph — e.g. an
     orange ✦ vs the target circle) + the seeker's tracked-LOS line: under `:none` the LOS line walks toward the
     decoy (the missile leads the BLEND → miss); under `:gated` the LOS line stays on the target (intercept). All
     readout scalars (re-confirm no Array telemetry / `float()`-crash — `n_peaks` is an int, the profile/detections
     are NOT shipped as telemetry). Slice-1..12 views UNTOUCHED (re-run every smoke-load + UI test — the
     discriminator branch does NOT hijack slice-11/12, which have no `discrimination` key → fall through).
   - `net/slice13_verify.gd` (drives the real server): `:gated` **intercepts** the decoyed target (small
     min-`los_range` vs the true target per the headline); `set_fidelity discrimination none` **degrades** it
     (large min-range / seduced-bearing / saturation per the headline); **`t`/`pos` bit-identical under the held
     seed+config** (replay — the `:scan` seeker DRAWS, so pin a missile pos_x/pos_z sequence element-wise, the
     slice-11 RNG-consumer discipline — NOT the RNG-independent `t`); **`set_fidelity seeker scan` is REJECTED**
     mid-run (the 4b guard on the wire). Assertions on SCALARS/sequences vs the TRUE target. `S13V OK`, exit 0.
     Step counts **multiples of `emit_every`** (the drain contract).
   - `net/slice13_ui_test.gd` (mock client, no server): the handshake wires the **discrimination** cycler (NOT
     seeker/guidance/autopilot); the ring walks `:none↔:gated` and wraps; badge/button track; the `intensity`/gate
     sliders send `set_param`; reset resyncs to `:none` (`S13UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-13 server (server `DONE` ⇒ scene connected, no
     GDScript errors).
   - `test_scenario.jl` + slice-13 loader testset (parses; `discrimination:none` default PRESENT [the new key];
     `seeker:scan`/`guidance:pn`/`autopilot:ideal` held; the grid/beam/CFAR config present + validated; the
     `:decoy` entity present with `[ConstantVelocity]` + `intensity`; the target `[BallisticMissile...]` / the
     true target `[ConstantVelocity]`; `intensity` at a consumed comp key + a knob; loader rejects a negative
     `intensity` / odd `n_train` / `N_bins < 1`; the decoy is `kind === :decoy` NOT `:target` — the truth-path
     invariant).
   - The **`_draw` decoy/seduced-LOS PIXEL branch** visually confirmed via the windowed shot harness
     ([[ewsim-godot-headless]]): `:none` = the LOS line + missile walking toward the decoy glyph (miss); `:gated` =
     the LOS line held on the target + tight intercept. **(stretch, deferred)** `clients/notebooks/slice13_decoy.jl`
     Pluto (miss-vs-intensity-ratio / miss-vs-separation sweep — the seduction lesson as a curve); an offline
     `batch.jl` miss-vs-`I`/gate grid (own seeded stream — the distribution path).

## Task checklist
- [x] **0. Probe + config pin DONE** (`M:\claud_projects\temp\slice13_probe\`: `probe*.jl` + `FINDINGS.md`, advisor-confirmed). Pin the
      grid/beam/CFAR config (#2), the headline (#1), intensity/separation/gate geometry (#3/#4), the
      clean-first-CPA + robust-gate window, the sign/wrap (#6), the draw-count invariance (#5), miss-vs-true-target
      (#7), the `:scan` introduce-reject (#8). **RE-CONSULT ADVISOR after the numbers.** Forward-flag gate-1/2/3
      seams.
- [x] **1. Primitive DONE (2042 tests, +34)** — FOUR pure fns in estimation.jl:
      **`paint_angular_profile!`** (promoted into gate-1 per the FINDINGS forward-flag — the pure lobe
      painter over the fixed grid, kept OFF the byte-identity-critical radar.jl), **`intensity_centroid`**
      (internal strongest-weight ref → the bit-exact `===` singleton anchor; drops the FINDINGS `(peaks,ref)`
      param — no call-site needs it, all three uses are ref-invariant), **`extract_peaks`** (contiguous-run
      clustering → per-cluster `intensity_centroid`), **`validation_gate`** (NN + halfwidth-reject → `nothing`
      coast — the gate-0 FINDINGS override of the plan-§3 keep-list-then-centroid, which made `:gated` worse).
      `DISCRIMINATION_MODES = (:none, :gated)` + `:scan`→`SEEKER_MODES = (:raw,:filtered,:scan)`; all exported.
      `test_estimation.jl` arms (centroid direct-recompute, ±π seam, symmetric midpoint anchor, NN+reject gate,
      additivity/decoy-count-independent length). Slices 1–12 byte-identical (golden + determinism green).
      **Advisor-confirmed design; the one catch (the `SEEKER_MODES==(:raw,:filtered)` assertion) handled.**
      LIVE_FIDELITY_MODES `discrimination` entry + the `:scan` introduce-reject guard are GATE 2 (wiring).
- [ ] **2. Wired** — the `:decoy` kind + the `:scan` profile/scan/gate `observe!` + the `discrimination` rung +
      the `:scan`-introduce-reject guard; test_missile/test_determinism/test_server arms; slices 1–12 byte-identical.
      **GATE-1 FORWARD-FLAGS (advisor, carry into gate 2):**
      - **The bin↔bearing / grid-construction off-by-one did NOT vanish — it MOVED.** Plan §3 wanted
        `bearing_to_bin`/`bin_to_bearing` TESTED so the ±π-wrap + off-by-one bin arithmetic couldn't hide in
        `observe!`; the FINDINGS rightly dropped them (grid-as-vector + wrapped-in-paint deltas), but the trap
        relocated to the grid CENTERING `grid[i] = boresight + (i−(N_bins+1)/2)·bin_w`. Make it a TINY TESTED
        helper (`angular_grid(boresight, N_bins, bin_w)`) OR pin an `observe!`-path assertion that a known target
        bearing lands in the expected bin — a half-bin shift misaligns the whole profile vs boresight and only the
        coarse closed-loop numbers would (maybe) catch it. **Do NOT bury it unabstracted in `observe!`.**
      - **Keep the gate halfwidth ≥ 0.045 (the gate-0 `hw`).** `validation_gate`'s coast path (→`nothing`→hold
        `λ_pred`) is newly reachable (the probe's `gate_nn` never coasted); it is inert in gate-0 geometry ONLY
        because the target peak sits within `hw` of the prediction. A tighter `hw` silently converts "hold" into
        "coast", and it COUPLES to the masking window (a masked TARGET peak also triggers the coast → `:gated`
        dead-reckons). Validate `hw` at LOAD and pin the robust window.
- [ ] **3. Scenario + Godot + verifiers** — `slice13_decoy.yaml`, the discrimination cycler + decoy/seduced-LOS
      view, the four proofs, `test_scenario.jl` arm. Update STATUS.md + CLAUDE.md. Commit + push (end-of-batch
      ritual).

## Context / landmarks
- **The seeker slice 13 extends:** `Seeker.observe!` (missile.jl:433) — today draws 1 `randn` (line 438) then
  reads `_nearest_target` for a lone truth bearing (`:raw`/`:filtered`); slice 13 adds the `:scan` branch (paint
  profile → `_draw_profile!` → `cfar_scan` → `extract_peaks` → centroid/gate), the 2·N_p·N_bins draws.
- **The α-β filter STATE the gate reuses:** `c[:seek_lambda_est]`/`c[:seek_lambdadot_est]` (missile.jl:468–471) →
  the gate center `λ_pred = λ_est + λ̇_est·dt`; `alpha_beta_los_step` (estimation.jl:277) UNCHANGED.
- **The CFAR sandbox (reused UNCHANGED, generic):** `cfar_scan`/`cfar_threshold`/`_cfar_estimate`
  (detection.jl:563/537/494) — take a bare `AbstractVector{<:Real}` power vector + cell indices, ZERO
  radar/Swerling coupling ("1-D range window" → "1-D angle window"). **detection.jl is NOT edited.** `CFAR_VARIANTS`
  (detection.jl:367) is the mode source of truth.
- **The profile draw (reused UNCHANGED):** `_draw_profile!` (radar.jl:491) — draws **2·N_p `randn` per cell,
  cell-by-cell in index order**; the FIXED cell count = decoy-count-independent draws (the determinism grid). The
  seeker calls it directly (same module) — inherit the exact count/order, do not re-roll.
- **The truth-path guard:** `_nearest_target` (radar.jl:221, `kind === :target`) — consumed by radar/jammer/the
  autopilot (missile.jl:275) + CPA telemetry; the decoy MUST be `kind === :decoy` so it never hijacks these.
- **The mover to reuse:** `ConstantVelocity` (radar.jl:26) — the passive `pos += vel·dt` mover for the decoy (NOT
  a `[BallisticMissile]` fall — that couples to `:integrator`, the slice-12 self-contained-mover precedent).
- **The wrap kernel (reused):** `wrap_angle` (geometry.jl) — the ±π seam guard in `intensity_centroid`/the gate
  innovation/the peak-cluster centroid (the slice-5 sign/wrap trifecta).
- **The 4b introduce-reject precedent:** slice-3 `:cfar` (`set_fidelity` rejects INTRODUCING it — the point→profile
  topology flip). `:scan` is the SAME shape (1 ↔ 2·N_p·N_bins); `SEEKER_MODES` gains mixed introduce-safety.
- **Fidelity plumbing precedent:** slice-11 `:seeker` (`SEEKER_MODES` → `LIVE_FIDELITY_MODES` → `set_fidelity` →
  `_validate_fidelity`) — `:scan` extends the SAME tuple; `discrimination` is a new key the SAME way (but nested).
- **The kind-arming precedent:** the `:target`/`:jammer`/`:clutter` kinds (scenario.jl) — `:decoy` is a new kind
  the SAME way; the `:scan` seeker is its only consumer.
- **HANDOFF** §10 item 12 (this slice — "fuses the whole suite"), §9 (the reuse map — RGPO = the seeker walked off
  by a decoy; CFAR = the discrimination thresholding), §3 (the tick contract — phase-3 observe! + phase-4 decide!),
  §1 (named approximations; the bearing wrap/sign trifecta), §11 Tier A (RF/IR seeker split + IR env channel — the
  deferred horizon).

## Watch-items (gotchas to bake in)
- **THE FRAMING RE-INVERSION — do NOT carry slice-12's "no-RNG/vacuous" language.** Slice 13 has a seeker → `w.rng`
  DRAWS → the inflection RE-INVERTS to APPLIES (conventions 3/11). The convention-4c trap running the SAME
  direction as slice 11.
- **THE CLASS IS 4b, NOT slice-11's 4a (the (b) pivot).** `:scan` FLIPS the draw topology (1 → 2·N_p·N_bins) →
  introduce-REJECTED like `:cfar`. `SEEKER_MODES` = MIXED introduce-safety (`:raw↔:filtered` safe; any switch
  touching `:scan` rejected). `discrimination` is draw-invariant AMONG its rungs but NESTED in the 4b `:scan` host
  and INERT without it (the `:raim`-without-GPS coupling) — NOT free-standing 4a. Writing "4a like slice-11
  `:seeker`" is the false claim.
- **THE DRAW-COUNT KEYSTONE (convention 3).** 2·N_p·N_bins `randn`/tick under `:scan` from `_draw_profile!` on the
  FIXED grid — invariant to the discrimination rung, decoy count, separation, AND spurious-peak count
  (paint-then-draw-the-fixed-grid, NEVER per-return/per-detection). A per-return draw would desync replay. Pin the
  count with a decoy present AND absent; pin `:raw`/`:filtered` still at 1.
- **THE FUSION IS THE DISCRIMINATION HALF (advisor) — and STRONGER under (b).** CFAR *detects* (peaks in a noisy
  profile — a REAL job now), the α-β gate *discriminates* (which peak to keep) — CFAR alone can't reject a brighter
  decoy. Say both roles explicitly; the "fuses the whole suite" claim rests on the α-β gate being the RGPO
  track-gate AND CFAR doing genuine peak detection.
- **detection.jl IS NOT EDITED.** `cfar_scan`/`cfar_threshold`/`_cfar_estimate` are already generic (power vector +
  cell indices) — reuse them on the angle axis. Touching detection.jl would risk the byte-identity-critical radar
  path; the reuse is pure BY the generic signature.
- **THE DECOY IS `kind === :decoy`, NEVER `:target` (advisor).** Else `_nearest_target` hijacks the radar/jammer/
  autopilot truth path + the miss readout. Invariant: the seeker is seduced, but **miss/CPA is ALWAYS vs the true
  target** — assert it.
- **THE LANDING IS EMPIRICAL (the slice-12 lesson).** Do NOT assume `:none` opens a big MISS — the probe measures
  miss AND bearing error and picks the headline; escalate to a binding `a_max` if PN intercepts anyway (the
  slice-12 pivot). Pin the RATIO.
- **THE LOBES MUST RESOLVE — AND NOT MASK (advisor, the slice-3 lesson on the angle axis).** Decoy separation ≳ a
  beamwidth (`σ_beam`) so CFAR sees TWO peaks, not one merged blob — AND separation must clear the CFAR
  **guard+training span** so neither lobe sits in the other's training window and MASKS it (`_cfar_estimate`,
  detection.jl:494). A masked decoy → `:none` isn't seduced; a masked target → `:gated` holds nothing — **either
  collapses the lesson to "both intercept."** It is a separation WINDOW (below: resolve; middle: mutual masking);
  the decoy separates over the run, so the probe sweeps the traversed separation and confirms both peaks survive
  CFAR throughout.
- **THE ±π WRAP SEAM.** `intensity_centroid`/`extract_peaks` cluster about a reference bearing (not a naïve mean);
  the gate innovation wraps. A target/decoy straddling ±π is the trap — test it explicitly (the slice-5 `wrap_angle`
  discipline).
- **THE GATE CAN FAIL — pin the window.** Near-co-location start (locks truth first) + a separation velocity + a
  gate half-width that holds the target peak and rejects the separated decoy peak; report the robust window (a
  slider nudge can't erase the lesson — the slice-12 `a_max` window).
- **Keep the non-`:scan` path byte-identical.** The whole profile/scan/gate block lives INSIDE the `:scan` branch;
  `:raw`/`:filtered` take the slice-11 `n = randn; λ_meas = λ_tru + σ·n` verbatim (the `+0.0`/spelling bit trap —
  slices 1–12 replay bit-identical; pin a slice-11 `:filtered` seeker scenario).
- **`intensity`/gate/grid are config; validate at LOAD** (`intensity ≥ 0`, even `n_train`, `N_bins ≥ 1`,
  `FOV`/`σ_beam` > 0); a live huge `intensity`/wide gate just paints/widens harder — no throw (the "a live slider
  can't crash a tick" discipline). But `seeker→:scan` introduce/remove is REJECTED (the 4b topology guard — a
  config-load choice, not a live slider).
- **Stay spatial** — extend `_draw_spatial`, no new render mode (slice-8..12 precedent); the decoy glyph + the
  seduced-vs-held LOS line IS the visual. The discrimination cycler is a new button state, not a new view. The
  angular profile/detections are NOT shipped as telemetry (scalars only — the `float()`-crash watch-item).
- **Verifier drain multiples** of `emit_every`; the replay assertion pins a missile pos sequence on an
  RNG-AFFECTED value (the `:scan` seeker draws — the slice-11 discipline, NOT the RNG-independent `t`).
