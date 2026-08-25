# Slice 48 — THE SEEKER SEARCH PATTERN (what a missile does when the receiver opens and the target is not there)

**Status: PLANNED (2026-08-25). GATE 0 NOT YET RUN. ⚠⚠ §3 IS BLOCKED ON PROBE P0 — the showcase arm
cannot be chosen until P0's four numbers exist.** Suite green at 9333 tests (slice 47).

**What this slice is:** slice 47 leaves a missile whose receiver opens onto empty sky. The head is
pointed where the launch-time picture said the target would be; the target is 0.05° further out than
the detector window is wide; and the head **does nothing at all** for the remaining seconds of the
engagement. This slice gives it the one thing it can still do — **look around** — and asks the only
question a search pattern can be asked: *how fast do you have to sweep, and is there still time?*

⭐ **The family (42/43/45) was BLOCKED, never killed, and slice 47 discharged the block**
(`docs/DEFERRALS.md` §"SLICE 47 SHIPPED"). Slice 43's gate 0 banked a LAW and shipped no code; this
slice is the first attempt to build on it. ⚠⚠ **The law's SHAPE is inherited as a HYPOTHESIS. Its
NUMBERS are not inherited at all** — see §0.2.

---

## §0 — THE PREMISE, READ OFF THE SHIPPED CODE

Three facts, located in the tree before any probe runs. They are what makes this slice a component
and not a scenario.

**1. THE SERVO IS GATED ON THE WINDOW, AND THAT GATE IS CORRECT.** `missile.jl:2292` (space-stabilized
rung) and `:2322` (body rung) both read

```julia
if get(c, :head_cued, false) ||
   off_axis_angle(head_az, head_el, look_az_b, look_el_b) ≤ fov_h
```

⇒ a head whose target sits outside its detector window **does not slew**, because a tracker cannot
slew on an error signal its detector never produced. That is not a bug and this slice must not
"fix" it. It is the reason the 39 m/s arm of slice 47 misses by 316 m: the head holds, in the
direction the midcourse last cued it, for the whole endgame.

**2. THE MEASUREMENT EXISTS ANYWAY, AND IT IS NOT REACHABLE.** `az_m` / `el_m` (`missile.jl:2471`)
are formed from truth every tick regardless of the window and regardless of `_detectable`. The
else-branch of the cue block (`:2718`) writes `head_tgt` from them **unconditionally**. On a wire
where the window gate holds the servo still, that write is inert — the stored target is never
consumed. ⚠ **It is not inert once a search branch bypasses the window gate**, and that is the single
sharpest hazard in this slice: a searching head that consumes `head_tgt` written off `az_m` is a head
being handed the truth it is supposedly hunting for. `docs/DEFERRALS.md` already logs this seam as
*"the seam's unconditional `head_tgt` write"*, discovered when slice 42's oracle probe went
3620.675 → 0.110 m. **The search branch must WRITE `head_tgt` itself, never fall through to that
line.**

**3. THE ONE STATE THAT HAS NO BRANCH.** After slice 47 the cue block (`missile.jl:2671`) is a
two-way decision:

| while… | the head is… | its slew target is… |
|---|---|---|
| not detectable, never locked, `:midcourse` authored | **CUED** (open-loop, window bypassed) | the belief LOS |
| detectable, or locked | **TRACKING** (window-gated) | the measurement |

The state this slice owns is **detectable, not locked, and the target is outside the window** — which
today falls into row 2, where the window gate then refuses to slew. It is a real, reachable, flown
state (slice 47's three broken arms live in it for ~2 s each) and nothing is modelled in it.

## §0.1 — THE CANDIDATE LESSON, AND THE PRE-REGISTERED KILL

**CANDIDATE HEADLINE.** *A search converts a pointing error you cannot fix into TIME — and the time
is bounded by the engagement, not by the head. Below a sweep rate the target is never found; above
it, what you paid is not the miss but the manoeuvre authority you had left when you found it.*

**THE SLIDER:** `seeker_search_rate_dps`, the commanded sweep rate ρ. Its floor (ρ = 0) is a
**genuine null** — it is exactly what ships today, a held head that never acquires — which is a
property slice 47's slider did not have and is worth having.

⚠⚠ **PRE-REGISTERED KILL, WRITTEN BEFORE ANY MEASUREMENT EXISTS.** *If the authorable rate range
either always locks or never locks, the rate slider is DEAD and the axis must change.* The specific
way this slice fails is that the locks/never-locks boundary turns out to live in the **deficit**
(how far outside the window the target is) rather than in the **rate** — in which case the headline
is **slice 47's cliff in new clothes**, dressed as a new component. That is precisely the trap
slices 44 and 45 fell into, and naming it here is what stops a later measurement being read as a
discovery. The two named replacement axes, in order of preference, are in §0.7.

## §0.2 — WHAT IS CITED, AND WHAT IS EXPLICITLY **NOT** CARRIED ACROSS

**CITED, NOT RE-PROBED:**

- **The window is FIXED HARDWARE** (slice 46). `R_acq · fov` is constant — the detector window IS the
  beamwidth — so widening the glass sells range. ⚠ **This slice does not re-open that**, does not
  measure it, and does not argue about it. `gimbal_fov_deg` is authored at 10.0° and is not a knob.
- **The MISS IS NOT THE GAUGE** (44, 45, 46, 47). Across slice 47's whole surviving domain the miss
  wanders 0.135 → 2.542 m up and down by 20× while the authority walks 4.27 → 27.97 % monotonically.
  The gauge here is **acquires-or-not, `t_lock`, and post-lock manoeuvre authority gated at r > 200 m**.
- **The handover error is the picture error × the time spent blind** (slice 47 §7.2). This slice
  authors the picture error as a constant and inherits the handover geometry it produces.

⚠⚠ **NOT CARRIED ACROSS — SLICE 43's NUMBERS.** Slice 43 measured `travel = deficit/(1 − ω/ρ)`,
`t_lock = travel/ρ + τ`, a sweep-rate floor `ρ* = 1.0174 °/s`, and a U-shaped required-rate curve
(2.399 / 1.017 / 2.019 °/s at t = 1 / 4 / 7 s). **Every one of those numbers was measured on a
DIFFERENT WIRE**: an 8 °/s servo, a ~7 s window to work in, and a geometry with no midcourse in
front of it. This wire is **240 °/s** (slice 46's measured isolation) with roughly **2 s** between
handover and CPA. ⇒ **the law's SHAPE is a hypothesis P0/P1 must re-measure; its NUMBERS are quoted
nowhere in this slice.** In particular `ρ* ≈ 1.0174 °/s` must not appear in a scenario comment, a
verifier tooth, or a HUD.

⚠ Slice 43's floor mechanism — *the unswept axis drifts out on a schedule the search does not
control* — is likewise a hypothesis here, not a finding. It was measured over ~7 s; over ~2 s it may
be negligible. **P0d settles it, and if it is live an azimuth-only sweep fails for a reason that is
not the rate**, which would be a wrong lesson wearing a right number.

## §0.3 — THE SEAM (the exact lines this slice touches)

- `core/src/missile.jl:2671` — the cue block. One new branch, and one new key written beside
  `:head_cued`.
- `core/src/missile.jl:2292` / `:2322` — the two slew predicates. One new disjunct each.
- `core/src/frames.jl` — one new pure kernel (§1). No existing kernel is modified.
- `core/src/scenario.jl` — three authored keys, their refusals, and one entry in the knob whitelist.
- Telemetry (`missile.jl:3275` neighbourhood) — the search keys, minted **only under the anchor**.

**BYTE-IDENTITY IS STRUCTURAL, NOT MEASURED.** Every new branch is gated on `haskey(c, :seeker_search)`,
an authored anchor absent from every slice 1–47 scenario, so the new disjuncts short-circuit on the
literal `false` and every prior replay is bit-for-bit unchanged **by construction** (slice 47's own
shape, §0.3). The absolute golden still runs as the master check (convention 2).

## §0.4 — REUSE, DON'T REBUILD

| need | use | never |
|---|---|---|
| "is the target available?" | **`in_fov`** as computed at `missile.jl:2611` (`in_fov && _detectable`) | a fresh `off_axis_angle(...) > fov_h` — a SECOND implementation of the availability verdict, the trap this file names for `off_axis_angle` in three places, and it can disagree with the branch it claims to report at the boundary tick |
| body angles → inertial pair | `az_el(rotate(att, los_unit_from_angles(az, el)))` — the line already at `:2205` | a hand-rolled quaternion product |
| rate limiting the sweep | the existing servo (`head_slew_full` / `head_slew_inertial`), which already owns `rate_max`, τ and the stop | a second rate limit inside the pattern generator |
| the mechanical stop | `head_clamp` / `head_clamp_inertial`, via the servo | clamping the pattern's output |
| the mode flag | a NEW `:head_searching` | ⚠⚠ **overloading `:head_cued`** — it is shipped telemetry, slice 47's HUD reads it, `slice47_verify.gd` asserts on it, and slice 47's gate-3 defect #1 was exactly a flag conflation. Overloading it also corrupts `head_cue_err_handover_deg`'s latch semantics |

## §0.5 — PRE-REGISTERED: THE SIX THINGS THIS SLICE MUST NOT DO

1. **Must not re-litigate that a wider window is free.** Slice 46 killed it. `gimbal_fov_deg` is
   authored, is not a knob, and is not compared against anything but the deficit.
2. **Must not use the miss as the gauge**, in the HUD, the verifier, or the scenario header.
3. **Must not quote slice 43's numbers** (§0.2). Shape yes, digits no.
4. **Must not overload `:head_cued`** (§0.4).
5. **Must not re-derive the window verdict** (§0.4).
6. **Must not bake the sweep at search onset.** The offset is recomputed every tick from `w.t` (or
   integrated per tick). A rate consumed once on the first search tick is `_DEAD_KNOB_KEYS`'s own
   definition of a dead knob — the slice-36 trap slice 47's gate 3 had to undo (`docs/STATUS.md`
   §Slice 47 gate 3 item 1).

## §0.6 — THE PROBES, WITH THEIR FALSIFIERS WRITTEN DOWN FIRST

Probe code under `M:\claud_projects\temp\slice48\`. Flown off `scenarios/slice47_midcourse.yaml`
**unmodified** wherever possible (convention 10: probe empirically, then pin against the live wire).

### ⚠⚠ P0 — **BLOCKING. §3 CANNOT BE WRITTEN UNTIL THIS RUNS.**

Four numbers, on each of slice 47's broken arms (`midcourse_err_gain` = 39 / 40 / 45 / 50) and on
the last surviving arm (38, as the control):

- **P0a — THE DEFICIT.** `head_cue_err_handover_deg − gimbal_fov_deg` at the handover tick. ⚠ At
  39 m/s this is **0.05°**, which a 240 °/s head sweeps in under one tick — *that arm has no rate
  slider on it at all*. At 50 m/s it is ~3.04°. The showcase arm is the one whose deficit makes
  `travel/ρ` a meaningful fraction of the time budget.
- **P0b — THE BUDGET.** Wall time from the handover tick to CPA, per arm. Estimated ~2.2 s from
  slice 47's ledger (handover 7.13 s, ~9.33 s to CPA on the broken arms); **estimated is not
  measured.** This is the entire time a search has.
- **P0c — THE LOS RATE ω AT AND AFTER HANDOVER**, in °/s, off `look_body_az_deg` telemetry. Slice 43's
  law diverges as ρ → ω. At r ≈ 1436 m closing at ~650 m/s on a crossing geometry ω is **not small
  and is rising**, and it — not slice 43's floor — is the likely binding constraint on this wire.
- **P0d — THE UNSWEPT AXIS.** Elevation separation |Δel| between cue and truth over the
  post-handover window, and the belief-vs-truth angle's growth rate over the same window. Slice 43's
  ρ = 1 arm closed the swept axis to 9.7519° inside a 10° window and **still never acquired**, held
  out by 2.4934° of drift on the axis it was not sweeping.

**F0 — THE PRE-REGISTERED FALSIFIER.** The rate axis is DEAD if either holds over the authorable
domain of ρ:

- (a) at the **lowest** authorable ρ, predicted `travel/ρ + τ` is under ~5 % of P0b's budget on every
  candidate arm ⇒ everything locks, the slider is a no-op; or
- (b) at the **highest** realisable ρ (bounded above by the authored `gimbal_rate_dps` = 240 °/s and
  below by nothing), predicted `travel` never closes within P0b ⇒ nothing locks.

If (a) or (b) fires, **stop and change the axis** (§0.7) rather than authoring around it.

### P1 — THE LAW's SHAPE ON THIS WIRE

Fly the branch as a scratch patch and measure `travel` and `t_lock` against deficit and ρ. **Falsifier
F1:** if `travel` is not monotone in the deficit and not monotone-decreasing in ρ over the domain,
slice 43's law does not describe this wire and the slice's HUD cannot claim it does.

### P2 — THE SEAM SMOKE (runs before P1 is believed)

Assert the search branch never consumes `head_tgt` written from `az_m`/`el_m` (§0 fact 2), by flying
an arm with the truth-write **poisoned** (a deliberate large offset). **Falsifier F2:** if the lock
instant moves at all, the branch is reading truth and every P1 number is worthless.

### P3 — THE NULL AND THE STEP

ρ = 0 must be **byte-identical** to the shipped slice-47 arm at the same picture error. And per the
rule slice 42 died to (`docs/LESSONS.md`): **re-fly the acquisition threshold at half `dt`.** If the
locks/never-locks boundary halves with `dt`, it is an integration artifact and not a rate floor.

### P4 — THE REPARAMETERIZATION GATE (slice 39/41's rule)

Can a retune of an existing knob reproduce the whole ρ curve? The candidates are `gimbal_rate_dps`
and the coverage. If ρ is indistinguishable from a servo-rate retune it must not ship as an
architecture — it ships as an authorable pattern with a measurement behind it.

## §0.7 — THE TWO-TEST VERDICT, DECLARED IN ADVANCE (the 2026-08-18 rule)

**MODEL TEST** — is `seeker_search_rate_dps` **read by the physics every tick**, and correct in its
own units, signs and frame? Specifically: the offset is recomputed from `w.t` every tick (§0.5 item
6); the commanded rate is realisable and is rate-limited by the shipped servo rather than by a second
limiter; the pattern is defined in the **body** frame, which is the frame `gimbal_fov_deg` is
measured in. **Failing this is the only outright kill** — a knob consumed at load or at search onset
is a BUG.

**LESSON TEST** — does dialing ρ move the headline (acquires / `t_lock` / post-lock authority) on the
authored scenario? **Failing this kills the SLICE'S HEADLINE, not the hardware**: a searching head
that is read every tick and physically correct ships as physics + tests + authorable keys under
"DEAD AS A LESSON, ALIVE AS A MODEL".

**THE TWO NAMED REPLACEMENT AXES**, if F0 fires, in order of preference:

1. **THE SEARCH COVERAGE** (half-amplitude S). Slice 43 measured that a wrong-side guess pays `2S`
   in travel and *"the price accelerates"* — a coverage that is too wide is a search that arrives too
   late, which is the same lesson on a knob whose domain is not squeezed by a 240 °/s servo.
2. **THE HANDOVER RANGE** (via `rcs_m2`, slice 46's own slider). ⚠ **This is the tension §0 owes the
   reader**: the deficit and the time available to close it are set by the *same* number. A later
   handover buys a bigger deficit and less time; an earlier one buys time and shrinks the deficit
   toward zero. Whether a sweet spot exists is a real question with a U-shape behind it — but it
   moves the horizon, the blind duration and the handover range at once, which is why it is second.

⚠ **THE FALLBACK INHERITS A §0.8 DECISION, AND P0d SETTLES IT** (advisor). The live-belief sweep
centre means the deficit GROWS while the search runs — so a FIXED coverage S may never bracket a
target that is walking away from the centre, however wide S is, which would kill fallback axis 1
before it is tried. **Whether the coverage axis is measured against the live centre or a frozen one
is therefore NOT decided in §0.8** — it is decided by P0d's growth-rate number, which is already
being collected.

## §0.8 — SCOPE, AND THE NAMED APPROXIMATIONS

- **The pattern is a single-axis symmetric triangle sweep in body azimuth.** Not a raster, not a
  spiral, not a palmer scan. ⚠ Chosen SYMMETRIC (start at the cue centre, sweep +S, reverse to −S,
  reverse) **specifically so that no arm gets the freebie of guessing the right side** — a missile
  that knew which way to look would not need to search. The cost of the wrong half is bounded and
  authored, not lucky.
- **The sweep centre is the LIVE belief direction, not a frozen pointing.** A real missile keeps its
  midcourse picture and scans around it. ⭐ This has a consequence the slice should be honest about:
  the belief and the truth keep separating after handover, so **the deficit GROWS while you are
  searching** — which is the mechanism behind a deadline, and is the honest form of slice 43's
  U-shaped best moment. ⚠ The rejected alternative (freeze the head's pointing at handover and sweep
  about that) is rejected because it discards information the missile demonstrably has.
- **No detection logic changes.** The lock is still `in_fov`, still slice 46's link budget, still
  slice 25's noise. A search moves the head; it does not make the detector better.
- **`_stab` (space-stabilized) rung:** the pattern is DEFINED in body azimuth and the inertial pair
  is derived from it through `att_q` at the same seam the cue block already uses, so both rungs are
  fed. Any claim this slice makes about sweep geometry is a claim about the **body** frame and says
  so.
- **Everything slice 47 named, unchanged:** one snapshot dead-reckoned at constant velocity, no
  datalink update, no INS drift, a non-manoeuvring target, an authored and deterministic picture error.

---

## §1 — GATE 1: THE PURE PRIMITIVE

**One kernel, in `core/src/frames.jl`**, beside `head_clamp` / `head_slew_full` (convention 12: pure,
measurement-agnostic, no `w.rng`, no world).

```julia
search_sweep(t_since_start::Real, rate::Real, coverage::Real) -> offset_rad
```

A symmetric triangle wave: `offset(0) = 0`, rising at `+rate` to `+coverage`, reversing to
`−coverage`, reversing again — period `4·coverage/rate`.

**THE TEETH** (`core/test/test_search.jl`, an EXTERNAL anchor or an INDEPENDENT recompute per
convention 11 — never a tautology):

1. `offset(0) == 0.0` exactly, and the first step is positive for `rate > 0`.
2. `|offset| ≤ coverage` for all t, to `atol` 0 (a bound, not a fit).
3. `|d offset/dt| == rate` almost everywhere — checked as an independent finite difference at
   sample points away from the turns, explicit `atol`.
4. Period is `4·coverage/rate`: `offset(t + T) == offset(t)` bit-for-bit at sampled t.
5. Odd symmetry over the half period, and continuity across each reversal.
6. **DEGENERATES, clamped at the consumer (convention 5 — a live knob can never crash a tick):**
   `rate ≤ 0` ⇒ 0.0 (the null); `coverage ≤ 0` ⇒ 0.0; NaN/Inf inputs ⇒ finite output (convention 6).
   A slider can reach each of these in one drag.
7. **No RNG, no allocation, no LinearAlgebra** (convention 12).

⚠ **WHAT GATE 1 DOES *NOT* SHIP: a predictor.** Slice 43's `travel = deficit/(1 − ω/ρ)` and
`t_lock = travel/ρ + τ` are **verifier and probe arithmetic**, not physics. Shipping a `search_travel`
kernel into the core would be a second implementation of the thing the simulation is supposed to
produce, and a verifier that compared the two would be checking the model against itself.

---

## §2 — GATE 2: THE WIRE

### §2.1 The keys

In the missile's `seeker:` block:

| key | role |
|---|---|
| `seeker_search: true` | **THE ANCHOR.** Its presence gates every new branch and every new telemetry key. |
| `seeker_search_rate_dps` | ρ — **the slider**, °/s at the YAML boundary, radians inside. |
| `seeker_search_coverage_deg` | S — half-amplitude, AUTHORED (§0.7 keeps it in reserve as the fallback axis). |

**LOADER REFUSALS** (`scenario.jl`, and each is a crash guard or a dead-knob guard, never tidiness):

- The two search keys are **refused without the anchor** — an authored key nothing reads is the
  dead-knob class this project keeps catching after the fact.
- The anchor is **refused without a gimballed head** (`gimbal_fov_deg` / the head keys). A strapdown
  seeker has no head to sweep; the pattern would have nowhere to go and the branch would be a lie.
- ⚠ `seeker_search_rate_dps` as a **live knob** is refused unless the anchor is authored (same
  reason), and is clamped at the consumer to `[0, ∞)`.

### §2.2 The branch

In the cue block (`missile.jl:2671`), between the cue arm and the tracking arm:

```
_cue    = haskey(c, :midcourse) && !_detectable && !get(c, :seek_init, false)
_search = haskey(c, :seeker_search) && _detectable && !in_fov && !get(c, :seek_init, false)
```

⚠ **`!in_fov`, NOT a fresh angle test** (§0.4). `in_fov` at `:2611` already IS the availability
verdict — angle AND range, `in_fov && _detectable` — so it can never disagree with the branch that
reports it at the boundary tick.

⚠⚠ **`_detectable` IS IN THE CONJUNCT EXPLICITLY, AND IT IS NOT REDUNDANT WITH `!in_fov`** (advisor).
`in_fov` folds TWO failures into one verdict — outside the window, and out of range — and here that
conflation cuts the wrong way: on a wire with the anchor and a horizon but **no midcourse** (which
§2.1's refusals deliberately permit), `!in_fov` is true from tick 1 for the RANGE reason alone, and a
search would start before the receiver has opened at all. That is a head hunting for an echo that does
not exist yet — the very thing this branch exists to avoid.

⚠ **AND `_detectable` IS WHY `!_cue` IS NOT NEEDED**, rather than branch order being trusted to do
it: the cue requires `!_detectable`, so the two arms are mutually exclusive **by predicate**. The
search starts when the receiver opens, which is exactly where the cue stops — one instant, two
branches, no gap and no overlap.

On the search arm:

1. Recompute the sweep centre from the **live** belief (`_midcourse_belief!`, §0.8) — or, with no
   midcourse authored, from the head's current pointing.
2. `off = search_sweep(w.t − c[:search_t0], ρ, S)` where `:search_t0` is stamped on the first search
   tick. ⚠ **`w.t` every tick** (§0.5 item 6) — `:search_t0` is an instant, not a baked rate.
3. `head_tgt_az = centre_az_b + off`, `head_tgt_el = centre_el_b`. **Written here, in this branch**
   — never falling through to `:2718`'s truth-derived write (§0 fact 2, the hazard).
4. Derive the inertial pair the way `:2205` does:
   `az_el(rotate(att, los_unit_from_angles(head_tgt_az, head_tgt_el)))`.
5. `c[:head_searching] = _search`, minted **only under the anchor**.

### §2.3 The slew predicates

`missile.jl:2292` and `:2322` each become a three-way or:

```julia
if get(c, :head_cued, false) || get(c, :head_searching, false) ||
   off_axis_angle(head_az, head_el, look_az_b, look_el_b) ≤ fov_h
```

Same argument as slice 47's cue, verbatim in meaning: **a searching head is executing an open-loop
COMMAND and needs no error signal.** The gate exists to stop a *tracker* slewing on an error its
detector never had; it is not a licence.

⚠ **The one-tick seam is inherited, not reinvented.** `:head_searching` is decided at the END of tick
k's `observe!` and consumed by tick k+1's slew — the same seam `:head_tgt_*` and `:head_cued` already
live under (discipline 2). Recomputing availability up at the slew would be a second implementation
of the gate.

### §2.4 Telemetry (minted only under the anchor)

`head_searching`, `search_offset_deg` (the commanded offset, signed, body frame),
`search_deficit_deg` (cue-to-truth angle **minus** `gimbal_fov_deg` — the quantity slice 43 named as
the real currency of acquisition), `search_elapsed_s`, and a **latched** `search_t_lock_s`.

⚠⚠ **THE LATCH IS NOT OPTIONAL, and slice 47 paid to learn why.** The client sees one frame in
`emit_every` = 16 ticks; a quantity that is live only during the search is unsamplable at the instant
that matters. Slice 47's verifier log is the proof — a latched 9.7846° against a 16-tick-sampled peak
of 9.7401°, a 0.045° gap against a cliff that straddles the window by 0.05°. Anything gate 3 asserts
in degrees or seconds gets its own never-stale latched key.

### §2.5 The core tests

`core/test/test_search.jl` extends into the wire: the null (ρ = 0 byte-identical to slice 47),
the anchor-absent byte-identity, the seam smoke (P2 as a permanent test, not just a probe), the
`w.t`-recompute pin (the rate CHANGED mid-search must change the next tick's offset — the model test,
§0.7, made permanent), and the loader refusals.

---

## §3 — GATE 3: THE SHOWCASE ⚠⚠ **BLOCKED ON P0**

**The arm cannot be chosen until P0 exists** (§0.6). What is decided now is everything that does not
depend on it.

- **Scenario:** `scenarios/slice48_search.yaml` — slice 47's wire to the digit, with
  `midcourse_err_gain` **AUTHORED** at whatever P0a shows to be the arm with a workable deficit
  (⚠ *not* 39.0 unless P0 says otherwise — a 0.05° deficit is not a search problem), the search
  anchor on, and the coverage authored.
- **ONE LIVE KNOB:** `m1.seeker_search_rate_dps`. Slice 47's picture-error slider is **retired to an
  authored key here** — convention 9, one lesson, one gauge. Its range and its linearity are P0/P1's
  to set; a log slider is legitimate only if the axis turns out not to be straight.
- **The button:** slice 46's `seeker_detect: none ↔ snr`, unchanged, still the sharpest A/B — press it
  and the horizon goes away, the missile locks on tick 1, and there is nothing to search for.
- **The gauge:** acquires-or-not, `t_lock`, and post-lock manoeuvre authority **gated at r > 200 m**
  (⚠ the gate is mandatory — `docs/DEFERRALS.md` records slice 44's "100.00 % of `a_max`" as an
  r → 0 endgame read). **Never the miss** (§0.5 item 2).
- **The HUD:** searching-or-not, the deficit in degrees against the window, the sweep offset, elapsed
  search time, and the authority. ⚠ `gimbal_fov_margin_deg` stays **off** the HUD for REDUNDANCY —
  slice 47 measured that `margin + cue = fov` at handover, so it is the same measurement counted from
  the other end. ⚠⚠ **Never quote the retracted reason** ("it improves while the engagement is
  lost"); and note that identity is **servo-contingent** (it holds while the head has SETTLED, true
  at 240 °/s, false on slice 35's 8 °/s wire).
- **THE FOUR PROOFS** (convention 14): `net/slice48_verify.gd`, `net/slice48_ui_test.gd`, a headless
  smoke-load, and **windowed shots**. ⚠ `STEPS` must be a multiple of `emit_every` = 16 or the
  verifier hangs SILENTLY. ⚠ Anything computed inside `_draw` has no headless proof — slice 47's two
  worst defects both lived there, and both were caught by the shot and by nothing else.
- ⚠ **The HUD width and height budget is INHERITED and is asserted in PIXELS, not characters.** Slice
  47 already had to shrink the telemetry type: three columns of 18 hold ~54 keys against ~72 shipped,
  and the columns reach the HUD's origin at `vp.x − 430`, so **a fourth column cannot be the answer.**
  This slice adds ~5 more keys on top of that.

---

## §4 — THE LOG (what actually happened)

*Empty. Gate 0 has not run.*
