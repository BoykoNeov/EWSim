# Slice 46 — THE SEEKER'S DETECTION HORIZON (the first COMPONENT-FIDELITY slice)

**Status: IN PROGRESS (2026-08-18).**

**What this slice is:** the missile seeker stops being an angle-only sensor. It gets an RF link
budget, and therefore a RANGE beyond which it detects nothing at all. The window it looks through
implies its aperture, so the detector's window and its reach are ONE design variable pulling in
opposite directions: `R_acq · fov = constant`.

---

## §0 — GATE 0 IS SLICE 44's, CITED AND NOT RE-DERIVED

⚠⚠ **This slice runs NO gate 0 of its own, and that is a decision with a reason.** Slice 44's gate 0
(`docs/plans/slice44.md`, 2026-08-18, 12 probes, no code shipped) built this exact physics on the
flying wire and measured it EXACT:

| what slice 44 measured | number |
|---|---|
| the aperture identity `R_acq · fov` over a 4× fov range | constant to **0.0000 %** |
| `log R_acq` vs `log fov` | slope **−1.000000** |
| the closed-form `r_acq` against `snr_freespace` at the crossing | **+10.0000 dB**, i.e. exactly `snr_min` |
| the boundary the −28 dB figure hangs off, across `dt` ∈ {2e−3, 1e−3, 5e−4} | step-independent to **2 %** |

**Slice 44's own words: *"the physics is not what failed, what failed is the WIRE."*** What failed
its LESSON test is that this arc's authored engagement launches the missile at 6437 m **inside** its
own seeker's 8079 m horizon (ratio 1.255), so the gate is byte-identically inert there. Under the
2026-08-18 re-verdict (`docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT") that is **DEAD AS A LESSON,
ALIVE AS A MODEL** — pass the MODEL test, fail the LESSON test ⇒ **it ships as physics + tests +
authorable keys**, and the null result ships as documentation rather than as a reason not to build.

⭐ **AND THERE IS A DEPENDENCY REASON TO BUILD IT NOW, not just a re-verdict.** The search-pattern
family (42/43/45) has exactly ONE named unblocker left: **an engagement launched beyond the seeker's
horizon — a MIDCOURSE phase.** "Beyond the seeker's horizon" is not a property a scenario can author
until the horizon EXISTS as shipped physics. **46 is midcourse's precondition.**

## §0.1 — THE THREE THINGS THIS SLICE MUST NOT DO (pre-registered)

1. ⚠⚠ **THE VERIFIER MUST NOT READ MISS.** Slice 44 §VII.1 measured miss FLAT (0.2237 / 0.3491 /
   0.3267 / 0.2514 m) across the entire free interval while peak `a_cmd` after lock walked
   **19.10 % → 100.00 % of `a_max`**. *Miss hid both limits that end the interval.* The gate-3
   columns are **peak `a_cmd` after lock as % of `a_max`** and **hold %**. Reading miss is how this
   component gets killed a second time by its own showcase.
2. ⚠ **THE SERVO MUST BE ISOLATED OR CARRIED AS A CONTROL.** Slice 44 §VII.2: the narrow-window
   failures at fov 8.0/8.6/8.8 are **slice 35's slew rate**, not the window — at 30 °/s all three
   HIT from *identical* lock instants. A showcase that pairs a delayed lock with the shipped 8 °/s
   head ships a confounded lesson.
3. ⚠ **VERDICT, NEVER METRES, ON ANY ARM THAT LOST THE TRACK.** Slice 44 §VII.3: failure magnitudes
   walk 320 → 627 m across 4× `dt` while the verdict is step-independent. Assertions on broken arms
   are `hold% <` / never-locks booleans, never a metre tolerance.

## §0.2 — THE SEVEN CONSTANTS ARE THE WHOLE RISK, AND THEY BECOME KEYS

Slice 44's probe hard-codes `SK_PT_W`, `SK_FREQ_HZ`, `SK_TINT_S`, `SK_NF_DB`, `SK_LOSS_DB`, `SK_ETA`,
`SK_SNRMIN_DB` as `const`s because it was a probe. **Shipped as `const`s they would be seven knobs
read from nothing — the "consumed at load, never read" bug class that is this project's ONLY outright
kill** (`speed` 19, launch altitude 21, the handover bias key 36, `ζ` 40, `k_δ` 15, `(R̂,s)` 31).
⇒ every one of them is an AUTHORABLE SCENARIO KEY, and every one carries slice 19's **tripwire**: a
test asserting that dialing it MOVES `r_acq`. That tripwire suite is what makes "ALIVE AS A MODEL"
verifiable rather than asserted, and it is the highest-value thing gate 1 ships.

⚠ **`rcs_m2` IS THE TARGET's AND IS NOT MINTED HERE.** `scenario.jl` already loads
`comp[:rcs_m2]` on every `target:` entity (every scenario since slice 1 authors it). A seeker-side
copy would give one target two RCS numbers that can silently disagree — convention 7's exact failure.
The seeker READS the target entity's key.

---

## §1 — GATE 1: THE PURE PRIMITIVES (`rf.jl`)

Three functions, all cross-domain RF (convention 12 — pure, measurement-agnostic, no `w.rng`, no
entities). They are NOT seeker-specific: any antenna has an aperture, any receiver has a threshold.

* `aperture_gain(beamwidth_rad; eta)` — **the aperture identity** `G = η·4π/Ω`, `Ω = θ²`.
* `aperture_diameter(freq_hz, beamwidth_rad)` — the implied circular aperture, `θ ≈ 1.02 λ/D`.
* `detection_range(rp, rcs_m2; snr_min_db)` — the range at which `snr_freespace` crosses threshold.

⭐ **`detection_range` READS `snr_freespace` AT UNIT RANGE RATHER THAN RE-DERIVING THE EQUATION**, the
`burnthrough_range` posture exactly: `K = SNR·R⁴ = snr_freespace(rp, σ, 1.0)` ⇒ `R = (K/snr_min)^¼`.
Any slip in the link budget moves the horizon in lockstep instead of drifting from it — the project's
oracle-test style, and it is strictly better than slice 44's probe (which spelled out the closed form
and then had to check it against `snr_freespace` in P1).

**Teeth (`test_radar_eq.jl`):** the crossing is exact (`snr_db_freespace` at the returned range **==**
`snr_min_db`, an INDEPENDENT recompute, not a re-derivation); the `R·θ` invariance and the −1 log-log
slope slice 44 measured; the ¼-power scalings (16× power ⇒ 2× range; 16× RCS ⇒ 2× range); the aperture
identity against a hand-computed solid angle; domain guards.

## §2 — GATE 2: THE WIRE

**The rung.** `w.fidelity[:seeker_detect]` ∈ `(:none, :snr)`, default `:none`. **Convention 4 class
(c)** — physics-changing, NO RNG (the threshold is deterministic, no `Pd` draw), so the draw topology
is untouched and every existing replay is byte-identical. It is LIVE-TOGGLEABLE, which is the
showcase's button: flip the horizon on mid-flight and watch the track drop.

**The keys** (`seeker:` block, presence-gated on the anchor `detect_pt_w`, the `gimbal_tau_s`
posture): `detect_pt_w`, `detect_freq_hz`, `detect_tint_s`, `detect_nf_db`, `detect_loss_db`,
`detect_eta`, `detect_snr_min_db`. Refused without `two_angle: true` (the gate lives in
`_observe_point3d!` — the slice-32/34 "refused, not silently ignored" precedent), and refused without
a WINDOW (`gimbal_fov_deg` or `seeker_fov_deg`), because **the window is what implies the aperture**:
with no window there is no gain and the horizon is undefined.

**The seam.** ⚠ The gate is **AND-ed into the existing `in_fov` line, textually unbranched** — under
`:none` the conjunct is the literal `true`, and `x && true === x` for `Bool`, so 34/35/36's
byte-identity claim keeps the form it takes there. No `if` around the availability verdict.

⚠⚠ **A NAMED MODEL CAVEAT — THE GATE IS ON AVAILABILITY, NOT ON THE SLEW.** The head's slew gate
(`off_axis_angle(…) ≤ fov_h`) stays angle-only. Two reasons, and the second is the honest one:
(a) it is exactly what slice 44 MEASURED, so gate 2's validation can reproduce its table cell for
cell — and a seam that disagrees with the gate-0 record is a seam with an unexplained difference;
(b) a head pointed at a target it cannot yet detect is being **CUED**, not tracking, and that is
precisely the state a midcourse missile flies in. Modelling the cue (and its error, and the search
that follows a bad one) is the NEXT slice's component, not this one's. **Written down so it is not
mistaken for an oversight**, and probed in §2.x below rather than assumed harmless.

**Telemetry.** `m1.seeker_r_acq_m`, `m1.seeker_snr_db`, `m1.seeker_detect` (0/1). ⚠ The SNR readout
floors the range (convention 6): `snr_freespace` is R⁻⁴ and this endgame closes to ~0.2 m, so an
unfloored readout ships ±Inf to JSON at CPA.

## §3 — GATE 3: THE SHOWCASE

A scenario in which the horizon **BITES** — which per §0.1 means the columns are authority and hold,
not miss, and per §0.2 means it is reached by authoring the SEEKER and the TARGET rather than by
moving the launch (this wire's missile cannot fly a 20 km engagement — slice 44 §V: unpowered, zero
drag area at 3000 m, gravity drops it 3845 m into the ground over the ≥ 28 s it would take).

---

## §4 — THE LOG (what actually happened)

### §4.1 GATE 1 — LANDED. Three kernels, 40 new assertions, and one improvement on the probe.

`aperture_gain` / `aperture_diameter` / `detection_range` in `rf.jl`, exported, tested in
`test_radar_eq.jl` (10 → 50 assertions in that file).

⭐ **`detection_range` IS BETTER THAN THE PROBE'S CLOSED FORM AND THE DIFFERENCE IS STRUCTURAL.**
`lib44.jl` spelled the radar equation out a second time and then had to CHECK it against
`snr_freespace` in P1. The shipped one reads `K = SNR·R⁴` straight off `snr_freespace` at unit
range — the `burnthrough_range` posture — so there is no second copy of the equation to drift, and
the test that walks the returned range back through `snr_db_freespace` is an *independent* recompute
rather than the algebra restated.

**Pinned in the tests:** the crossing is exact at five thresholds (atol 1e−12) with a strict
inequality either side; 16× power ⇒ 2× range, 16× RCS ⇒ 2× range, 16× bandwidth ⇒ ½ range,
+6.02 dB gain ⇒ 2× range, +12.04 dB of loss ⇒ ½ range; **every field of the chain MOVES the horizon**
(the slice-19 tripwire, as `!=` assertions, so a refactor that stops threading one FAILS); the
half-angle trap (a window handed in unconverted is a 4× gain error) is pinned as a `/4`; λ at
16 GHz = 18.74 mm and a 2° beam needs 0.5476 m of dish, both external anchors; and `R_acq · fov`
constant with a log-log slope of −1 to 1e−12.

### §4.2 GATE 2 — LANDED, AND IT REPRODUCES SLICE 44's GATE-0 RECORD CELL FOR CELL

The rung (`:seeker_detect` ∈ `(:none, :snr)`, default `:none`), seven authorable keys, the
AND-ed conjunct in `_observe_point3d!`, five telemetry keys, and the loader's refusals — plus 73
assertions in `test_missile.jl`.

**THE VALIDATION THAT MATTERS** (`M:\claud_projects	emp\slice46\g2_seam.jl`, the shipped keys
and rung, no core patch): slice 44 §VII.1's authority table, flown through the shipped seam.

| `R_acq` | `t_lock` | miss | hold % | peak `a_cmd` | % of `a_max` | aero % |
|---|---|---|---|---|---|---|
| none | 0.0010 | 0.2237 | 99.99 | 573.0 | 19.10 | 0.00 |
| 4000 | 3.3670 | 0.3491 | 99.96 | 436.2 | 14.54 | 0.00 |
| 3000 | 4.7580 | 0.3267 | 99.98 | 1039.7 | 34.66 | 0.00 |
| **2000** | **6.1580** | **0.2514** | 99.96 | **3000.0** | **100.00** | 0.09 |
| 1500 | 6.8660 | 85.8355 | 31.20 | 627.3 | 20.91 | 20.32 |

**Every digit is slice 44's.** The probe SET the horizon; the shipped seam DERIVES it from the
window and the authored budget, and the two agree exactly — so gate 0's record is now a property of
what flies, not of a patch that was reverted.

**And the identity is on the wire, read from telemetry rather than from the kernels:**

| fov | `R_acq` (m, telemetry) | `R_acq · fov` | implied aperture (m) |
|---|---|---|---|
| 3° | 26929.7350 | 80789.2051 | 0.1825 |
| 6° | 13464.8675 | 80789.2051 | 0.0913 |
| 10° | 8078.9205 | 80789.2051 | 0.0548 |
| 12° | 6732.4338 | 80789.2051 | 0.0456 |

⭐ **80789.2051 m·deg to every digit over a 4× window range.** And the two numbers that decide this
arc: **8078.92 m of reach at the 10° window it flies, against a 6437 m launch** — the missile starts
inside its own seeker's horizon, so the gate is byte-identically inert here (`blind` = 0 ticks). At
12° the reach is 6732 m and it is *still* inert. **The null result is pinned as a test**, which is
what the 2026-08-18 re-verdict asks for: the regime where the hardware does not bite is shipped
documentation, not a reason to leave it unbuilt.

**The four null cells are byte-identical** (`===` on the miss and the lock instant): no rung + no
keys (every scenario 11–45), keys with the rung OFF, the rung ON with no keys, and the rung ON with
a horizon far beyond the engagement.
