# Slice 4 — jamming / EP (noise jamming + the burn-through crossover)

The slice that finally lights up **phase 2 of the tick contract**. Slices 1–3 only
ever used `observe!` (and `integrate!`); `build_env!` has been a no-op default since
`subsystem.jl` was written. A **jammer is a `build_env!`-only subsystem** (HANDOFF
§3: "a jammer is `build_env!` only — raises noise in a band"): it writes an elevated
noise floor into the world's derived `env` blackboard, and the radar's `observe!`
reads it back. This is the **first real cross-subsystem coupling through `env`** — the
exact mechanism §3 was designed around ("a jammer raising a radar's noise floor … goes
through the world's derived `env` blackboard, **never** by subsystems calling each
other directly"). Source of truth: `HANDOFF.md` §10 (item 4), §3 (the `build_env!`
phase + `env` coupling), §6 (`rf.jl` carries J/S), §1 (named approximations), §12 (the
fidelity badge), §11 (DRFM / deceptive jamming explicitly deferred).

The lesson is the **burn-through crossover**: a target echo is **two-way** (R⁻⁴), an
active jammer's power at the radar is **one-way** (R⁻²). So as the engagement closes,
the signal grows *faster* than the jamming — at some **burn-through range** the radar
"sees through" the jammer and re-detects. Dragging jammer power / range and watching
that crossover move *is* the lesson (HANDOFF §1). **EP** (electronic protection) is the
radar fighting back: each EP technique is a **named, conditioned modifier to effective
J/S**, and toggling it (the §12 fidelity badge) is the second lesson.

**Scope: FULL** (user's call, recorded here like slice-3's pulse-integration override).
Both geometries — **self-screening** (jammer on the target, in the mainlobe) **and
standoff** (jammer off-axis, in a sidelobe) — which pulls in a **two-level antenna
receive-gain model**. That model is what makes **sidelobe-blanking EP physically real**
(it attacks the sidelobe term); without standoff there is no sidelobe to blank. Hence
**4 gates**, not slice-2's 3: gate 2 is self-screening (mainlobe, no antenna model),
gate 3 adds the antenna model + standoff + the EP fidelity.

**Done =** start the server on a jamming scenario, connect Godot, watch a target that is
**masked** by the jammer at long range cross its **burn-through range** and light up as
it closes; drag jammer power and watch the crossover move; toggle the `ep` fidelity
(`none → freq_agility → sidelobe_blanking`) and watch the effective J/S drop **only in
the matching condition** (agility vs a spot jammer, blanking vs a standoff/sidelobe
jammer) — with `runtests.jl` green on the new closed-form jamming tests (and slices 1–3
untouched and still **byte-identical** — no-jammer scenarios never read `env[:jamming]`).

## The physics (named approximations — HANDOFF §1)

Noise jamming only (barrage / spot). Coherent / DRFM / deceptive jamming (RGPO, PRF-jitter
counters) is a **future slice** (§11) and explicitly out of scope here.

### 1. The effective SNR under jamming (`radar.jl`)
- Slice-1's `snr_freespace` is already `S/N` with thermal noise **normalized to 1** (the
  radar-eq denominator is `k·T0·B·F·L`). Jamming raises the interference floor to `N + J`,
  so the detector sees `SNR_eff = S/(N+J) = (S/N)/(1 + JNR)` where `JNR = J/N` is the
  jammer-to-thermal-noise ratio at the radar. **The detection draw is unchanged** — it
  draws the same `randn` count regardless of the SNR fed to it (the slice-1 invariant),
  so jamming changes detection *booleans*, never the *draw count*.

### 2. The jammer-to-noise ratio `JNR` (`rf.jl` — the new J/S primitive, HANDOFF §6)
- **One-way (beacon) link budget**, normalized to the *same* thermal denominator as
  `snr_freespace`:

      JNR = Pj · Gj · Gr · λ² · overlap / ( (4π)² · R_j² · k·T0·B·F·L )

  - `Pj` jammer transmit power (W), `Gj` jammer antenna gain toward the radar (one-way),
    `Gr` the **radar's receive gain in the direction of the jammer** (see §3 below — this
    term is the whole self-screen-vs-standoff distinction), `R_j` jammer→radar range.
  - **`overlap = min(1, B_r/B_j)`** — barrage dilution: a wideband jammer spreads `Pj`
    over `B_j`, the matched filter only collects the `B_r/B_j` fraction in its passband
    (≈1 for a spot jammer matched to the radar; ≪1 for broadband barrage).
  - **One-way `R_j⁻²`** vs the echo's two-way `R_j⁻⁴` is the burn-through asymmetry:
    doubling jammer range costs the jammer **6 dB**, the signal **12 dB**.
- **`J/S = JNR / (S/N)`** is invariant to **`F` and `L`** (common-mode in `J/N` and
  `S/N` — the benign approximation). The thermal `k·T0·B_r·F·L` cancels between `JNR` and
  `SNR`, so the **only** residual bandwidth term in `J/S` is `overlap`: **J/S is
  `B_r`-invariant for a SPOT jammer** (`overlap = 1`) but **`∝ B_r` for BARRAGE**
  (`overlap = B_r/B_j` re-introduces it). Dually, **`JNR` (= J/N) is `B_r`-invariant for
  barrage** (`J` and `N` both scale with `B_r`) — and `JNR` is what feeds `SNR_eff`. So:
  - **Self-screening** (`R_j = R_target`, mainlobe `Gr = G`): `J/S ∝ R²` — halve the
    range, J/S drops 6 dB → the signal catches up → **burn-through ∝ R²**.
  - **Standoff** (`R_j` fixed, target closes at `R_t`): J constant, `S/N ∝ R_t⁻⁴`, so
    `J/S ∝ R_t⁴` — a *steeper* crossover (the standoff signature).
- **`burnthrough_range`** helper — the self-screening closed form where `J/S = 1`
  (`S = J`): `R_bt = √(K_s/K_j)` with `K_s = (S/N)·R⁴`, `K_j = JNR·R²`. Configurable J/S
  margin for "burn-through at a usable Pd" rather than exactly `S = J`.

### 3. Two-level antenna receive-gain model (`rf.jl` — the standoff enabler, NAMED approx)
- The radar beam points at its **primary target** (boresight = radar→target direction).
  `Gr` toward an emitter at angle `θ` off boresight is a **two-level pattern** (named
  approximation): **mainlobe** `G` for `θ ≤ beamwidth/2`, a flat **sidelobe floor**
  `G − sidelobe_db` (e.g. 30 dB down) outside. (Real patterns roll off as a sinc/Taylor
  taper — deferred; two-level captures the *in-beam vs sidelobe* lesson, which is all EP
  needs.)
- **Self-screening:** jammer co-located with the target → `θ ≈ 0` → mainlobe `Gr = G`,
  which **cancels** against the echo's receive gain in `J/S` (no antenna model needed —
  this is why gate 2 is clean). **Standoff:** jammer off-axis → sidelobe `Gr` (uncancelled,
  much smaller) — physically *why* standoff jamming is weaker, and **exactly what
  sidelobe-blanking EP attacks**.
- **Boresight rule** (deterministic): the radar points at the **nearest** `:target`
  (ties by sorted id). Single primary target in slice-4 scenarios; named so it can't
  drift. Guard: no target present → treat the jammer as in-mainlobe (conservative).

### 4. EP = named, **conditioned** modifiers to effective J/S (`radar.jl`, the `ep` fidelity)
Each rung is a multiplier on the per-jammer `JNR` contribution, **conditioned on a
jammer property** so it is a real lesson, never a flat fudge factor (advisor: a flat
scalar is a fake knob):
- **`none`** — full jamming (the baseline; the scenario default, badge "EP: none").
- **`freq_agility`** — the radar hops over an agile band `B_agile`; a narrow (spot)
  jammer only overlaps a fraction → `JNR ×= min(1, B_j/B_agile)`. **Big benefit vs a
  spot jammer, no-op vs barrage** (`B_j ≥ B_agile` → ×1). Needs the radar's `agile_bw_hz`.
- **`sidelobe_blanking`** — cancels/attenuates a jammer arriving through a **sidelobe**:
  `JNR ×= db2lin(−cancel_db)` **iff the jammer is out of the mainlobe**; **no-op on a
  mainlobe (self-screen) jammer** (you cannot blank the mainlobe without blanking the
  target). Needs the antenna model from §3.
- **`PRF_jitter` is deliberately NOT a rung** — it counters range-gate pull-off /
  deceptive jamming, a **no-op against noise jamming**; adding it here would be a knob
  that does nothing. It belongs to the future DRFM/deceptive slice (§11).

## Decisions taken
- **The jammer is an ENTITY + a `build_env!`-only subsystem** (`kind = :jammer`), not a
  fidelity. It carries `comp[:pt_w, :gain_db, :bandwidth_hz]` and a `ConstantVelocity`
  mover (so it can close / hold station). Its `build_env!` writes per-radar JNR
  contributions into `w.env[:jamming]`; the radar's `observe!` reads them. Faithful to
  §3/§10's "jammer = `build_env!` raises the noise floor."
- **`env[:jamming][radar_id]` is a VECTOR of per-jammer contributions**, each a
  `(jnr, in_beam::Bool, bj_hz)` record — NOT a pre-summed scalar. The radar needs the
  per-contribution `in_beam` (for `sidelobe_blanking`) and `bj_hz` (for `freq_agility`)
  to apply EP **conditionally**; a pre-summed JNR would erase exactly the structure EP
  acts on. Multiple jammers' contributions are additive and order-independent (the §3
  `build_env!` contract). The jammer bakes in the **geometry + antenna gain** (physics —
  the noise floor genuinely depends on `Gr`); the radar applies **EP** (its own
  countermeasure) — clean separation of who-owns-what.
- **`ep` is the toggleable §12 fidelity** (rungs `(:none, :freq_agility,
  :sidelobe_blanking)`), joining `LIVE_FIDELITY_MODES` (radar.jl) alongside
  `:propagation`/`:cfar`. The fidelity badge shows the rung; toggling it is the EP lesson.
- **`:ep` is INTRODUCE-safe** — a sharp contrast to slice-3's `:cfar` guard. EP only
  scales a deterministic scalar; it changes **no RNG draw count**. So `set_fidelity` may
  both *change* and *introduce* `:ep` mid-run, and a mid-run toggle replays bit-identical.
  **There is no draw-topology hazard anywhere in this slice** (the jammer's `build_env!`
  has no RNG; the detection draw is unchanged) — note this explicitly, it's why slice 4 is
  "slice-2-shaped" (deterministic SNR modulation) and not "slice-3-shaped."
- **No-jammer scenarios stay byte-identical.** Absent a `:jammer`, `env[:jamming]` is
  never written, the radar reads `JNR = 0`, `SNR_eff = SNR`. Slices 1–3 (and
  `test_determinism`, the `_sample_z` golden) are untouched — pin it.
- **Composition with `propagation`:** the **signal** `S` flows through the existing
  `_target_snr(prop, …)` (radar.jl) unchanged, so a jammed two_ray scenario lobes the
  signal correctly. The **jammer-path** `JNR` is one-way **free-space** (no multipath
  lobing on the J path) — named and deferred. Slice-4 scenarios use `free_space`
  propagation (one lesson per scenario — the slice-3 principle); the code composes, the
  scenarios don't mix lessons.
- **Composition with `:cfar` is DEFERRED** (and the two are not combined in any slice-4
  scenario). A jammer would raise the CFAR profile's noise floor (`1 → 1 + JNR`), which
  CFAR would then adapt to — a natural future composition, but slice 4 wires + tests only
  the **point** path (`_observe_point!`). Flagged as a watch-item so it is a conscious
  gap, not a silent wrong result (a `:cfar` + `:jammer` scenario is out of scope; do not
  ship one without wiring `_observe_cfar!` to read `env[:jamming]`).
- **Telemetry exposes the jamming as SCALARS** (advisor): new `<id>.jnr_db` (total
  jammer-to-noise at the radar, floored via `_snr_db_wire`) and `<id>.js_db` (J/S in dB),
  so burn-through reads as a **visible number**, not inferred from Pd. The existing
  `<id>.snr_db` now carries `SNR_eff` (post-jamming) for jammed scenarios — fine, since
  no-jammer scenarios are unchanged; note the redefinition in the docstring. No new array
  telemetry (unlike slice 3); the spatial view is reused.
- **The Godot spatial view is REUSED** (no new render mode — unlike slice-3's range-power
  view). The slice-1 elevation view already shows downrange × altitude; slice 4 adds a
  jammer marker, a JNR/J-S readout, the masked↔detected target transition across
  burn-through, the `ep` badge, and the EP-cycler button + jammer sliders. `_mode` stays
  `spatial` (no `range_axis_m` in the handshake).
- **F/L treatment is a NAMED approximation, and benign.** `JNR` uses the same `k·T0·B·F·L`
  denominator as the radar eq for a consistent normalization. Strictly, the receiver
  noise figure `F` should not amplify *external* jamming — but `F` and `L` are common-mode
  in `J/N` and `S/N`, so **`J/S` (and therefore the burn-through crossover) is invariant
  to the choice**. Say so in the docstring (HANDOFF §1: no hidden approximations).

## Review gates (cadence: staged)
1. **Jamming physics green** — `rf.jl`: `jam_noise_ratio` (one-way JNR, `overlap`,
   thermal-normalized) + the two-level `antenna_gain` + `burnthrough_range`, with
   `test_jamming.jl`: JNR ∝ `R_j⁻²` (−6 dB/octave, vs the signal's −12); `J/S ∝ R²`
   self-screen and `J/S ∝ R_t⁴` standoff; barrage dilution (`B_j = 10·B_r` → overlap
   −10 dB); spot (`B_j = B_r`) → overlap 1; two-level gain (in-beam = mainlobe, out =
   sidelobe floor, the boundary exact at `θ = beamwidth/2`); `burnthrough_range` closed
   form (`J/S = 1` at `R_bt`, `<1` inside, `>1` outside) **with explicit `atol`** (the
   slice-2 rtol≈0 trap); `F`/`L` cancel in `J/S` (vary them, J/S unchanged — the
   benign-approximation claim); the **correct** `B_r` behavior (J/S `B_r`-invariant for a
   spot jammer, `∝ B_r` for barrage; JNR `B_r`-invariant for barrage — guards against the
   *inverted* "B_r cancels in J/S" assertion, which fails for barrage). All deterministic
   closed-form (slice-2-style, no MC band).
   Slices 1–3 physics tests stay green untouched.
2. **Self-screening burn-through live (mainlobe, no antenna model, no EP)** —
   `Jammer <: Subsystem` with `build_env!` → `env[:jamming]`; `_observe_point!` reads it
   → `SNR_eff = SNR/(1+ΣJNR)`; `:jammer` kind in `scenario.jl`; `jnr_db`/`js_db`
   telemetry. Tests (`test_radar.jl`/`test_jammer.jl`): `build_env!` populates
   `env[:jamming]` (the FIRST phase-2 contribution); a present jammer drops `SNR_eff`;
   **self-screening burn-through** (far → `SNR_eff < thr` masked, close → detected) over a
   closing trace; **no-jammer scenario byte-identical** (slice-1/2/3 + golden green); the
   detection **draw count is jammer-invariant** (jammer on/off → same `randn` stream).
3. **Standoff + antenna model + EP fidelity** — the two-level `Gr` (boresight at the
   nearest target) so a standoff jammer enters a **sidelobe**; the `ep` fidelity joins
   `LIVE_FIDELITY_MODES`; `set_fidelity` generalises (already per-key from slice 3 — just
   add the `:ep` rungs; **no introduce-guard** for `:ep`); EP applied **conditionally** in
   `_observe_point!`. Tests: standoff JNR uses the **sidelobe** gain (≪ mainlobe);
   `sidelobe_blanking` raises `SNR_eff` for a **standoff** jammer but is a **no-op on a
   self-screen (mainlobe)** jammer; `freq_agility` raises `SNR_eff` for a **spot** jammer
   but **no-op on barrage**; the **common-condition** EP ordering (a matched EP strictly
   reduces J/S, a mismatched EP leaves it unchanged — NOT calibrated to pass by
   construction, the slice-2/3 trap); **mid-run `ep` toggle replays bit-identical** AND
   **`:ep` may be introduced mid-run** (the slice-3 `:cfar`-guard contrast — pin both);
   `set_fidelity :ep` write/reject in `test_server.jl`.
4. **Visible live** — `scenarios/slice4_selfscreen.yaml` (jammer on the target, closing
   through burn-through — the slider lesson) and `scenarios/slice4_standoff.yaml`
   (off-axis standoff jammer + a closing target — the sidelobe/EP lesson); the Godot
   spatial view extended (jammer marker, JNR/J-S readout, masked↔detected transition,
   `ep` badge + EP-cycler button + jammer-power/range sliders); a headless
   `net/slice4_verify.gd` asserting the burn-through crossover (SNR_eff/J-S flips across a
   range, `t` bit-identical under a held seed) **and** the EP toggles (matched EP raises
   SNR_eff, mismatched is a no-op); a `net/slice4_ui_test.gd` (the EP cycler + sliders +
   badge, mock client, no server); `Sandbox.tscn` smoke-loaded headless against a slice-4
   server; `test_scenario.jl` slice-4 loader assertions. The `_draw` pixel branch
   visually confirmed via the windowed shot harness (see [[ewsim-godot-headless]]).
   **(stretch)** a Pluto burn-through diagram (detection range vs jammer power, or J/S vs
   range for self-screen vs standoff — a closed-form recompute regression test, not MC).

## Task checklist
- [x] 1. **DONE & green (833 tests).** `rf.jl`: `jam_noise_ratio(rp, pj_w, gj_db, bj_hz,
      R_j; gr_db = rp.gain_db)` (one-way JNR, `(4π)²`/`R_j⁻²`, single receive `Gr`, SAME
      thermal denominator as `snr_freespace`, `overlap = min(1, B_r/B_j)` inside) +
      `antenna_gain(rp, θ_rad; beamwidth_rad, sidelobe_db) → dB` (two-level mainlobe/sidelobe,
      inclusive `|θ| ≤ bw/2` step, feeds `gr_db`) + `burnthrough_range(rp, rcs, pj_w, gj_db,
      bj_hz; gr_db, js_margin = 1.0)` (self-screen `J/S = js_margin` closed form via the
      ORACLE `K_s = snr_freespace(R=1)`, `K_j = jam_noise_ratio(R_j=1)`, `R_bt =
      √(js_margin·K_s/K_j)` — a link-budget slip moves R_bt in lockstep). All four
      approximations named in docstrings (one-way free-space J path, barrage `overlap`,
      two-level pattern, benign common-mode F/L). `test_jamming.jl` (35 closed-form tests,
      in `runtests.jl` after `test_propagation.jl`): the −6 dB(JNR)/−12 dB(signal)
      asymmetry SIDE BY SIDE (the burn-through lesson), J/S ∝ R² self-screen + ∝ R_t⁴
      standoff, barrage dilution (−10 dB) + overlap saturating at 1 for a narrow jammer,
      two-level gain (inclusive boundary, sign-symmetric, sidelobe = −sidelobe_db JNR),
      burnthrough round-trip (J/S=1 at R_bt, <1 inside / >1 outside, atol; `js_margin` √-scaling),
      F/L cancel in J/S (vary, unchanged), and the **corrected B_r law** (J/S B_r-invariant
      for SPOT; with `B_j` held FIXED — barrage — JNR B_r-invariant + J/S ∝ B_r; guards the
      inverted "B_r cancels in J/S" assertion), + guards (R_j/B_j/js_margin > 0).
- [x] 2. **DONE & green (862 tests).** `Jammer <: Subsystem` (`radar.jl`) — the FIRST
      `build_env!` subsystem: writes `env[:jamming][radar] = Vector{JamContribution}` where
      `const JamContribution = @NamedTuple{jnr::Float64, in_beam::Bool, bj_hz::Float64}` (NOT
      pre-summed — the per-contribution structure is what gate-3 EP conditions on; gate 2 sets
      `in_beam = true` / mainlobe `gr_db = rp.gain_db`, no antenna model yet). `_observe_point!`
      reads it via `_radar_jnr(contribs)` (plain additive sum — the gate-3 EP seam), applies
      `SNR_eff = snr_th/(1+ΣJNR)` per target (jnr_total = 0.0 absent a jammer ⇒ `snr/1.0 ===
      snr`, slices 1-3 byte-identical), tracks `best_snr_eff` (→ snr_db, pd) AND `best_snr_th`
      (→ js_db). Telemetry: `snr_db` now carries `SNR_eff`; `jnr_db` + `js_db` ship **ONLY when
      jamming is present** (a no-jammer frame is unchanged — pinned). `js_db = _snr_db_wire(jnr)
      − _snr_db_wire(snr_th)` (the dB DIFFERENCE = `lin2db(JNR/S)` above-floor, wire-safe finite
      if S→0 where the quotient would be +Inf JSON-poison; >0 = jammed, <0 = burn-through).
      Co-located `R_j = 0` guarded at the consumer (skip), `bandwidth_hz > 0` validated at LOAD
      (a tick-throw would kill the session — not a live slider). `scenario.jl`: `:jammer` kind
      (`comp[:pt_w, :gain_db, :bandwidth_hz]` + `[ConstantVelocity, Jammer]` subs). `_observe_cfar!`
      LEFT UNTOUCHED (jammer+cfar deferred; a jammer in a cfar scenario writes env harmlessly,
      ignored). `test_jammer.jl` (6 testsets): build_env! populates `env[:jamming]` (record shape
      + JNR vs rf.jl); SNR_eff == `SNR/(1+JNR)` closed form + jnr_db/js_db; **self-screen
      burn-through** (js_db flips sign across `burnthrough_range`, +6 dB/octave R² law, ≈0 at
      R_bt — deterministic, not the random boolean); **draw-stream invariance** (jammer on/off →
      same rng end-state, different detections, unjammed detects more); **no-jammer frame has NO
      jnr_db/js_db key**; loader arm (comp + subs + bandwidth≤0 / missing-block rejects). Mainlobe
      only (no antenna model / EP yet). **NO draw-topology hazard proven** — the byte-identity
      goldens (`_sample_z`, test_determinism) stayed green through the `_observe_point!` restructure.
- [x] 3. **DONE & green (890 tests).** Two-level `Gr` in `build_env!`: the radar boresights its
      NEAREST target (`_nearest_target`, ties by sorted id; `nothing` → conservative mainlobe so a
      jammer-only scene can't throw), and the jammer's `_boresight_angle` off that line (acos of
      the normalized dot, clamped, zero-vector guard) picks `antenna_gain`'s mainlobe Gr (θ≈0 →
      self-screen, cancels in J/S) vs the sidelobe floor (off-axis → standoff, uncancelled). A
      self-screen jammer rides θ=0 → mainlobe, so **gate-2 tests stay byte-identical**. `EP_MODES =
      (:none,:freq_agility,:sidelobe_blanking)` joins `LIVE_FIDELITY_MODES` as `ep = EP_MODES` — and
      `set_fidelity :ep` works with **NO server change** (the per-key table from slice 3 validates
      it; the `:cfar` introduce-guard doesn't match `:ep`, so it is **introduce-safe**). EP applied
      in the `_radar_jnr` seam via `_ep_factor(ep, c, comp)` — a NAMED, **CONDITIONED** modifier
      (never a flat fudge): `:freq_agility` `JNR ×= min(1, B_j/B_agile)` (big vs SPOT, exact no-op
      vs BARRAGE `B_j ≥ B_agile`), `:sidelobe_blanking` `JNR ×= db2lin(−cancel_db)` iff `!in_beam`
      (exact no-op on a MAINLOBE self-screen jammer), `:none` → 1.0 exactly. Antenna/EP config are
      RADAR comp keys read with **defaults** (`:beamwidth_rad :sidelobe_db :agile_bw_hz :cancel_db`)
      so toggling `:ep` onto ANY scenario can't `KeyError` a tick (the "a live config can't crash a
      tick" watch-item — the introduce-safe contract needs the defaults). `_observe_point!` reads
      `ep` only when a jammer is present, so a no-jammer frame never consults it (byte-identical).
      Tests: `test_jammer.jl` (standoff enters a sidelobe — `in_beam=false` + exact sidelobe JNR =
      mainlobe·db2lin(−30); **2×2 EP conditioning** — matched reduces J/S by exactly cancel_db /
      10·log10(B_agile/B_j), mismatched is a **bit-exact `==` no-op**, NOT calibrated-to-pass; matched
      EP raises snr_db); `test_determinism.jl` (mid-run `:ep` **introduce AND toggle** both
      bit-identical, `ta != tn` proves EP **flips detections** not a dead knob — self-screen spot
      jammer at the burn-through knee where freq_agility's +10 dB tips ~half the looks; **jammer-free
      introduce → rng end-state unchanged**, the sharpest introduce-safe form); `test_server.jl`
      (`set_fidelity :ep` write/reject + introduce-allowed, the `:cfar`-guard contrast). **NO
      draw-topology hazard** — the byte-identity goldens stayed green through the restructure.
- [ ] 4. `scenarios/slice4_selfscreen.yaml` + `scenarios/slice4_standoff.yaml`; Godot
      **— SCENARIO TUNING (advisor, gate-2 review):** `burnthrough_range` scales with the link
      budget, and it is SMALL for modest numbers — the gate-2 fixture (`pt_w=1000, pj_w=100,
      gj=10, rcs=1`) gives **R_bt ≈ 9 m**, i.e. a 100 W self-screen jammer buries that radar by
      ~+60 dB at 9 km and burns through only at absurd close range. The gate-2 burn-through TEST
      is still valid (it pins the scale-invariant J/S∝R² sign-flip + 6 dB/octave, true at any R),
      but those default numbers are useless for a watch-it-close scenario. Tune `pj_w`/`pt_w`/RCS
      (empirically, with a throwaway probe — the slice-3 lesson) so **R_bt lands in a realistic
      closing band (~10–30 km)**, or the on-screen burn-through never fires.
      spatial-view extensions (jammer marker, JNR/J-S readout, EP cycler + badge, jammer
      sliders); `net/slice4_verify.gd` + `net/slice4_ui_test.gd`; `Sandbox.tscn` headless
      smoke-load against a slice-4 server; `test_scenario.jl` slice-4 assertions; windowed
      visual confirm of `_draw`. **(stretch)** `clients/notebooks/slice4_burnthrough.jl`.

## Context / landmarks
- **The seam is pre-built (mostly).** `build_env!` is a no-op default (`subsystem.jl:13`)
  invoked in phase 2 of `tick!` (`subsystem.jl:30`) **before** `observe!` (phase 3) — so
  the jammer→radar `env` coupling is correct by construction (no ordering hazard). `env`
  is cleared and rebuilt every tick (`world.jl` / `tick!`), so a stale floor can't leak.
- **The radar SNR seam:** `_target_snr` (`radar.jl:115`) returns `(snr_lin, visible)` —
  leave it returning the **thermal** `S/N`; apply `1/(1+JNR)` in `_observe_point!`
  (`radar.jl:162`) after the call, where the env read lives. `_snr_db_wire` /
  `_SNR_DB_FLOOR` (`radar.jl:101`) floor the dB telemetry — reuse for `jnr_db`/`js_db`.
- **The fidelity table:** `LIVE_FIDELITY_MODES` (`radar.jl:94`) is the per-key source of
  truth the server's `set_fidelity` validates (`server.jl:160`); add `ep = EP_MODES`.
  `set_fidelity` is already a per-key table (slice 3) — `:ep` is just a new entry with
  **no** introduce-guard (the `:cfar` guard at `server.jl:172` does NOT apply).
- **The loader:** `_build_entity` (`scenario.jl:80`) is the `kind`-dispatch — add a
  `:jammer` arm next to `:clutter`; `:clutter` (`scenario.jl:94`) is the closest template
  (a passive entity feeding the radar), but the jammer DOES own a subsystem (its
  `build_env!`), unlike clutter.
- **Frame convention:** `pos = [downrange/x, y, altitude/z]`; slant `R_j = _range(jammer,
  radar)`; the boresight angle is `acos(...)` of the (target−radar)·(jammer−radar)
  directions.
- **Validation shape:** the jamming physics is **deterministic**, so gate-1 tests are
  **closed-form** (the slice-2 pattern), not analytic-vs-MC bands. The only RNG is the
  unchanged detection draw.

## Watch-items (gotchas to bake in)
- **`-Inf`/`NaN` on the wire.** `JNR = 0` (no jammer) → `lin2db(0) = -Inf`; `J/S` with
  `S → 0` likewise. Floor `jnr_db`/`js_db` through `_snr_db_wire` (the slice-1 `%g` /
  slice-2 null watch-item). Test a no-jammer frame and a deep-null frame explicitly.
- **The `in_beam` / `bj_hz` structure MUST survive to the radar.** If `build_env!`
  pre-sums JNR into a scalar, EP loses the per-contribution condition it acts on (a
  sidelobe-blank would wrongly hit a mainlobe jammer). Ship the vector of contributions.
- **EP must be CONDITIONED, never a flat scalar** (advisor). `sidelobe_blanking` no-ops a
  mainlobe jammer; `freq_agility` no-ops barrage. Pin the no-op-in-the-wrong-condition
  case — a flat multiplier would pass a "does EP reduce J/S?" test for the wrong reason
  (the slice-2/3 "calibrated-to-pass" trap).
- **No draw-topology hazard — but PROVE it.** Unlike slice 3, jamming/EP change no draw
  count. Pin: (a) no-jammer byte-identity vs the slice-1 golden; (b) jammer-on vs
  jammer-off same `randn` end-state, different detections; (c) mid-run `ep` toggle AND
  mid-run `ep` *introduce* both bit-identical. This is the slice's determinism story —
  the *contrast* to slice-3's `:cfar` guard is itself a lesson, so test it, don't assume.
- **The two-level pattern has a hard step at `θ = beamwidth/2`.** In the standoff
  scenario, boresight tracks the closing target; if the target has cross-range motion the
  jammer can walk across the mainlobe↔sidelobe boundary mid-run → a JNR **cliff** that
  muddies the lesson. Tune the standoff geometry for **radial** target closure (fixed
  bearing → the jammer sits solidly in the sidelobe throughout). A conscious gate-4 tuning
  constraint, not a surprise.
- **Boresight needs a target.** A jammer-only scenario has no boresight — guard it
  (jammer treated in-mainlobe, conservative) so `acos`/the nearest-target lookup can't
  throw inside `build_env!` → `tick!` → kill the session (the slice-2/3 "a live config
  can't crash a tick" watch-item). Live jammer sliders (`pt_w`, etc.) likewise can't crash.
- **`:cfar` + `:jammer` is OUT OF SCOPE.** `_observe_cfar!` does NOT read `env[:jamming]`
  in slice 4. Do not ship a scenario combining them without wiring it (it would silently
  ignore the jammer in the profile — a hidden wrong result). Flagged here as a conscious
  gap, deferred composition.
- **Name every approximation** in the docstrings (one-way free-space J path, barrage
  `overlap = min(1,B_r/B_j)`, two-level antenna pattern, benign common-mode F/L,
  nearest-target boresight). HANDOFF §1: no hidden approximations — this slice's whole
  point is that the burn-through geometry and the EP modifiers are *named, switchable* knobs.
- **Deferred to a future slice (§11), explicitly NOT here:** DRFM / coherent / deceptive
  jamming, range-gate pull-off (RGPO), PRF-jitter EP, jammer-path two_ray lobing, the
  CFAR+jamming composition. Listing them keeps the slice-4 boundary honest.
