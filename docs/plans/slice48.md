# Slice 48 — THE SEEKER SEARCH PATTERN (what a missile does when the receiver opens and the target is not there)

**Status: ⭐⭐ GATE 0 — **THE SLICE LIVES**, and §4.3's re-block is **RETRACTED** (2026-08-25).
P0/P0b/P1/P2/P2b/P3/P4/P5 have run. §4.3c blamed the WIRE; **it was measuring the 30° MECHANICAL
STOP**, which was silently eating the sweep on 27–37 % of search ticks (§4.4). With the stop authored
at a perfectly ordinary 45°, a cell exists where the null **never acquires and misses by 1200 m** and
the sweep-rate slider walks it **monotonically to 0.19 m** (§4.5). ⚠ ONE OPEN QUESTION REMAINS and it
is about AUTHORING, not physics (§4.5c).** Suite green at 9333 tests (slice 47); no code shipped yet.

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

## §3 — GATE 3: THE SHOWCASE ⚠ **P0 HAS RUN — THE ARM IS CHOSEN (§4.1e); THE SLIDER RANGE STILL WAITS ON P1**

**The arm is `midcourse_err_gain = 50.0`** (§4.1e). ⚠ The slider's DOMAIN and its linearity still
wait on P1, because §4.1d item 1 makes P0's cliff a prediction rather than a measurement.

- **Scenario:** `scenarios/slice48_search.yaml` — slice 47's wire to the digit, with
  `midcourse_err_gain` **AUTHORED at 50.0** (§4.1e — ⚠ *not* 39.0; a 0.0505° deficit is not a search
  problem), the search anchor on, and the coverage authored.
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

## ⭐⭐⭐ §4.1 — GATE 0, PROBE **P0** (2026-08-25): **F0 DOES NOT FIRE, AND THE CLIFF IS NOT WHERE EITHER THIS PLAN OR SLICE 43 PUT IT**

`M:\claud_projects\temp\slice48\p0_budget.jl`, log beside it. Flown off
`scenarios/slice47_midcourse.yaml` **unmodified** except `midcourse_err_gain`, no core patch.
⭐ **THE ANCHOR HOLDS**: the cue-at-handover column reproduces slice 47's shipped ledger to four
decimals on every arm (9.7846 / 10.0505 / 10.3166 / 13.0441), so this probe is reading the same wire
the showcase will (convention 10).

### §4.1a — P0a AND P0b: THE DEFICIT IS SMALL AND THE BUDGET IS SHORTER THAN ESTIMATED

```
err m/s   lock?  t_hand s   t_cpa s  BUDGET s   cue@h °  DEFICIT°  r_hand m      CPA m
   38.0    lock    7.2560    9.0990    1.8430    9.7846   -0.2154    1436.2      2.542
   39.0   NEVER    7.2600    9.1330    1.8730   10.0505    0.0505    1436.4    316.549
   40.0   NEVER    7.2640    9.1350    1.8710   10.3166    0.3166    1436.6    324.870
   45.0   NEVER    7.2870    9.1450    1.8580   11.6723    1.6723    1436.2    366.633
   50.0   NEVER    7.3110    9.1540    1.8430   13.0441    3.0441    1436.2    408.654
```

⚠ **THE BUDGET IS 1.843–1.873 s, NOT THE ~2.2 s §0.6 ESTIMATED** — the estimate came from the
never-acquiring arm's *whole* flight, and the search's clock starts at handover, not at launch. The
plan's own arithmetic was 18 % optimistic about the only resource this slice spends. ⚠ **The handover
RANGE is 1436.2–1436.6 m on every arm** — the horizon is the target's RCS and the picture error does
not move it, which is what makes these arms comparable at all.

⭐ **AND THE ADVISOR's P0a WARNING IS CONFIRMED IN THE DIGITS: the 39 m/s arm's deficit is 0.0505°.**
A 240 °/s head crosses that in 0.2 ms. **It is not a search problem and must not be the showcase arm.**

### ⭐⭐⭐ §4.1b — P0c/P0d: **THE TARGET IS RUNNING AWAY FROM THE BELIEF, AND IT ACCELERATES**

The quantity a sweep must close is the cue-vs-truth separation, and it does not sit still. Arm
39.0 m/s, sampled from handover (full table for four arms in the log):

```
 t−t_h s    range m    |Δaz| °    |Δel| °    TOTAL ° growth °/s  ω_los °/s
  0.0000     1436.4    10.0661     0.0814    10.0665        —       6.7408
  0.3750     1164.9    13.1010     0.1348    13.1017     8.9360    10.2921
  0.7490      899.7    17.9371     0.2544    17.9389    14.5981    17.3730
  1.1240      645.5    26.7217     0.6290    26.7291    27.3080    34.1117
  1.4980      425.1    45.7340     3.4744    45.8658    62.2834    79.6757
```

**THE SEPARATION GROWS 10.07° → 45.87° IN 1.5 s, AND ITS RATE GROWS 8.9 → 62.3 °/s DOING IT.** The
mechanism is not subtle and is not a modelling artifact: a **fixed lateral picture error subtends a
growing angle as the range closes** (283 m of cross-range error at 1436 m is 11°; the same 283 m at
425 m is 34°). ⇒ ⭐⭐⭐ **A SEARCH ON THIS WIRE IS NOT A COVERAGE PROBLEM, IT IS A RACE.** The head
must sweep faster than the target departs, and the departure rate is *rising*, so a search that has
not won early cannot win late. This is slice 43's U-shaped "best moment" arriving on a different wire
through a different mechanism — and slice 43's own floor mechanism (unswept-axis drift) is **NOT what
binds here**: |Δel| is 0.08–0.25° for the first second, an order of magnitude inside the window.

⭐ **⇒ P0d ANSWERS THE §0.8 SCOPE QUESTION: A SINGLE-AXIS AZIMUTH SWEEP IS VIABLE ON THIS WIRE.** The
elevation half of the separation only reaches 3.47° at t+1.5 s, by which point the azimuth half is
45.7° and the engagement is long over. A two-axis pattern would be modelling something this
engagement does not do. ⚠ Scope it honestly: that is a property of a nearly co-planar crossing
geometry, not of searching.

⚠ **THE LAST TWO ROWS OF EVERY TABLE ARE GARBAGE AND ARE NOT QUOTED** (163°, 265°, 95°, and a
NEGATIVE growth rate). Past ~1.7 s the missile has flown *past* the believed point and the bearing to
it reverses. It is outside every window this slice reads, but it would be a wrong number in a HUD.

### ⭐⭐ §4.1c — F0: **THE RATE AXIS SURVIVES, AND THE CLIFF IS ρ ≈ ω**

Slice 43's law as a hypothesis, with **ω taken as the separation's growth rate** (the §0.8 live
centre means that, not the raw LOS rate, is what the sweep is racing):

```
arm 50.0 m/s:  deficit 3.0441°   growth ω 11.16 °/s   budget 1.843 s   |Δel|@h 0.109°
     ρ °/s     travel °     t_lock s   fits budget?
    0.5–5.0     diverges        NEVER     no (ρ ≤ ω)
     10.0       diverges        NEVER     no (ρ ≤ ω)
     30.0         4.8783       0.2126            YES
    120.0         3.3770       0.0781            YES
    240.0         3.2122       0.0634            YES
```

**NEITHER F0(a) NOR F0(b) FIRES.** Below ~9–11 °/s nothing closes on any arm; above ~30 °/s
everything closes in under a quarter of the budget. ⇒ **there is a real, narrow, authorable band
(~5–30 °/s) with a sharp boundary in it**, and the slider's floor (ρ = 0) is still the genuine null.

⭐⭐ **AND THE PRE-REGISTERED KILL IS ANSWERED THE RIGHT WAY ROUND.** §0.1 feared the
locks/never-locks boundary would be **slice 47's deficit cliff relabelled** — a new component whose
only content is last slice's number. **It is not.** Across a 60× range of deficit (0.05 → 3.04°) the
0.05° arm fails for the *same reason* as the 3.04° arm: the target departs faster than a slow sweep
closes. **The failure MODE is shared**, which is the separation from slice 47 this slice needed and
did not have a right to expect.

⚠⚠ **WHAT THIS PARAGRAPH ORIGINALLY SAID IS RETRACTED, AND P0b REFUTED IT** (advisor caught the
reasoning, §4.2 measured it). It read *"the boundary is set by ω and barely by the deficit at all"*,
on the grounds that the cliff moved only 8.77 → 11.16 °/s over that 60× deficit range. **Two things
are wrong with that.** (1) ω and the deficit are **not independent variables here** — both are read
off the same authored knob, so a small spread in one beside a large spread in the other licenses
nothing. (2) **P0b flew the intersection properly and the cliff DOES move with the deficit**:
5–8 → 15–20 °/s as the deficit goes 0.067 → 3.063°. **Never quote the retracted sentence.**

### ⚠⚠ §4.1d — WHAT P0 DOES **NOT** ESTABLISH

1. ⚠⚠ **THE CLIFF's LOCATION IS PREDICTED FROM A STATIC-ω LAW, AND ω IS NOT STATIC — SO THE LAW MAY
   HAVE NO FIXED POINT AT ALL** (advisor). ω is 8.77 °/s averaged over the first half-second and
   62 °/s by t+1.5 s, so **a sweep at 12 °/s does not lose the race at t = 0 — it wins briefly and
   then loses**, because ω crosses it a few hundred ms in. The real question is not a threshold but a
   **time-varying INTERSECTION**: is the target ever inside the window at a moment the head is
   pointed there? **§4.2 answers that properly and supersedes §4.1c's table.** No number in §4.1c
   may reach a scenario comment, a verifier or a HUD.
2. **The SWEEP DIRECTION is now load-bearing and unmeasured.** With the separation growing at
   ~10 °/s, a symmetric triangle that opens on the wrong side pays slice 43's `2S` in travel *while
   the target departs* — at S = 15° and ρ = 10 °/s that is 3 s against a 1.84 s budget. ⇒ **the
   coverage S and the sweep rate ρ are NOT independent here**, which §0.7's fallback axis assumed
   they were. P1 must sweep both.
3. **`ω` AS "THE SEPARATION's GROWTH RATE" IS A REASONED SUBSTITUTION, NOT A MEASUREMENT.** Slice 43's
   ω was a raw LOS rate against a fixed reference. The substitution follows from the live-belief
   centre (§0.8) and is *qualitatively* robust — a sweep must outrun the departure however the
   departure is booked — but the formula's exact form is P1's to confirm or replace.

### §4.1e — THE SHOWCASE ARM ⚠ **SUPERSEDED BY §4.2e — DO NOT READ THIS PARAGRAPH ALONE**

The arm is still **`midcourse_err_gain = 50.0`**, but ⚠⚠ **one of the three reasons written here was
BACKWARDS and is retracted**: *"the highest ω so the cliff sits furthest from zero"*. **A higher ω
makes the search HARDER, not better-instrumented** (advisor). The surviving reasons — the largest
deficit (3.0441°) so the travel is a real quantity rather than a rounding error; 25 % of the crossing
speed, which is **slice 47's own authored slider ceiling** and therefore already argued as
defensible; and an unambiguous 408.654 m null rather than a near miss — are joined in §4.2e by the
one that actually decides it. ⚠ **NOT 39.0** (§4.1a).

---

## ⭐⭐⭐ §4.2 — GATE 0, PROBE **P0b** (2026-08-25): **THE INTERSECTION, AND THE PRICE OF NOT KNOWING WHICH WAY TO LOOK**

`M:\claud_projects\temp\slice48\p0b_intersect.jl`, logs `p0b.log` / `p0b_fine.log`. Same flights,
no core patch. Instead of a static-ω threshold it integrates the head's offset forward and asks the
only question that matters: **`hypot(Δaz(t) + offset(t), Δel(t)) ≤ fov` for ANY t in the budget?**

Two patterns, because §4.1d item 2 made the direction load-bearing:

- **BEST** — the sweep opens **toward** the target. The luckiest a symmetric pattern can ever be,
  i.e. an **upper bound on what any search can do**.
- **TRI** — the shipped symmetric triangle opening on the **wrong** side first (+S, down to −S, …),
  i.e. slice 43's `2S` penalty paid *while the target departs*.

⚠ **THIS IS A KINEMATIC OVERLAY, NOT A FLOWN BRANCH.** No servo lag, no 240 °/s limit, no radome
bend, no seeker noise, and it grants the lock the instant the geometry allows one. **All of that
makes it OPTIMISTIC**, which is the safe direction for a falsifier and the wrong direction for a
number. **P1 must fly the real branch.**

### ⭐⭐ §4.2a — F0 DOES NOT FIRE UNDER **EITHER** PATTERN

**BEST case** — the cliff, in °/s, and **it moves with the deficit**:

```
   arm      deficit      cliff (last never → first LOCK)      lock time at first LOCK
  39.0      0.0665°            5 → 8                                 0.053 s
  40.0      0.3328°            8 → 10                                0.117 s
  45.0      1.6898°           12 → 15                                0.271 s
  50.0      3.0628°           15 → 20                                0.304 s
```

⭐ **COVERAGE IS IRRELEVANT IN THE BEST CASE** — every S column (5 / 10 / 15 / 25°) is identical to
the millisecond, because a sweep that opens the right way needs only a few degrees. The one exception
is the deepest arm at the narrowest coverage (50.0 at S = 5°, ρ = 20), which fails because **5° of
travel cannot reach a 3.06° deficit that is growing while you cross it.**

### ⭐⭐⭐ §4.2b — THE HEADLINE: **NOT KNOWING WHICH WAY TO LOOK COSTS 4–8× IN SWEEP RATE**

The shipped symmetric triangle, opening on the wrong side (fine grid, S = 10°):

```
   arm      deficit    BEST cliff    WRONG-SIDE cliff    ratio
  39.0      0.0665°       5 → 8          30 → 35          ~4.4×
  40.0      0.3328°       8 → 10         35 → 40          ~4.0×
  45.0      1.6898°      12 → 15         40 → 45          ~3.0×
  50.0      3.0628°      15 → 20         50 → 55          ~2.8×
```

**A search that opens away from the target needs three to four times the sweep rate to survive** —
and the multiple is *largest where the deficit is smallest*, because a small deficit is closed
almost instantly if you guess right and is otherwise a full `2S` excursion away. ⇒ ⭐⭐⭐ **THE
DOMINANT COST OF SEARCHING IS NOT COVERING THE GAP, IT IS NOT KNOWING WHICH SIDE THE GAP IS ON.**
That is slice 43's Finding 3 (`2S`, "and the price accelerates") confirmed on a wire it was not
measured on, in a currency slice 43 did not have: **the price is paid in RATE, because the clock is
the binding resource.**

### ⭐⭐⭐ §4.2c — COVERAGE IS A **V**, AND ITS TWO SIDES ARE DIFFERENT MECHANISMS

The wrong-side cliff against coverage (°/s required, fine grid):

```
   arm       S = 5°    S = 10°    S = 15°    S = 25°
  39.0         30         35         45         60
  40.0         30         40         45         60
  45.0         45         45         50         70
  50.0         80         55         55         70
```

- **THE CEILING (every arm): a WIDER search is a WORSE search.** Each extra degree of coverage is an
  extra degree that might have to be *wasted* on the wrong side, and it is paid out of a 1.84 s
  clock. Monotone, clean, and **the mirror image of slice 46's finding** — there a wider window sold
  reach, here a wider sweep sells time.
- **THE FLOOR (the deepest arm only): a search too NARROW cannot reach.** At 50.0 m/s, S = 5° needs
  **80 °/s** where S = 10° needs **55** — because 5° of travel does not reach a 3.06° deficit that is
  *growing while you cross it*, so the head sweeps back and forth inside the gap.
- ⇒ ⭐⭐ **COVERAGE IS A V WHOSE FLOOR ARM ONLY APPEARS ONCE THE DEFICIT IS LARGE**, and the two arms
  are different physics. **This is the same SHAPE as slice 36's handover basket** (its left arm the
  error itself, its right arm the chase cost) arriving in a second place in this arc — which is worth
  more than either number.

### §4.2d — WHAT P0b DOES **NOT** ESTABLISH

1. **It is kinematic** (see the warning above). Every cliff here will move when the servo, the bend
   and the noise are in the loop. **P1.**
2. **"THE WRONG SIDE" IS DETERMINISTIC ON THIS WIRE AND WOULD NOT BE ON A REAL ONE.** The picture
   error is authored as a single direction (`[0, −1, 0]`), so the target is always on the same side
   of the belief. ⚠ **A shipped pattern must therefore not be allowed to be accidentally right** —
   §4.2e names the fork.
3. **The BEST-case column is not achievable by any honest search** and exists only as the bound. It
   must never appear on a HUD as though a missile could reach it.

### ⭐ §4.2e — THE ARM, RE-DERIVED — AND ONE **DESIGN FORK** THIS PLAN CANNOT SETTLE BY MEASUREMENT

**THE ARM STAYS `midcourse_err_gain = 50.0`, on the reason §4.1e did not have:** with the shipped
wrong-side pattern at S = 10°, its cliff sits at **50 → 55 °/s**, which places a slider domain of
**0 → 120 °/s** with the cliff near the middle and a **2× clearance** below the head's authored
240 °/s servo limit — so slice 35's rate limit stays out of this lesson, which is exactly the
isolation slice 46 measured and slice 47 kept. ⚠ The narrower arms' cliffs (30–45 °/s) sit low enough
that a slider would spend most of its travel in the "locks" region.

⚠⚠ **THE FORK — WHICH WAY DOES THE PATTERN OPEN?** Three options, and it is a MODELLING decision, not
a measurement:

- **(a) AUTHORED DIRECTION, opening the WRONG way on the showcase.** Honest about the missile's
  ignorance, and puts §4.2b's headline on the slider. ⚠ But it authors the missile's bad luck, which
  a reader can fairly call rigged.
- **(b) AUTHORED DIRECTION, opening the RIGHT way.** Reads as a much better search than any real one
  and hides the slice's best finding. **Rejected** unless (a) proves unauthorable.
- **(c) A DIRECTION RULE THE MISSILE COULD ACTUALLY HAVE** — e.g. sweep first toward the side the
  target's own believed motion is carrying it. ⭐ This is the physically honest one and it may be
  *systematically right on a closing crossing engagement*, which would make the wrong-side cost a
  pinned TEST rather than the showcase. ⚠ It is also a second component and would need its own
  model test.

**Recommendation: (a) for the showcase with (c) measured as a probe**, so the slice ships the
honest cost and knows what a smarter rule would have bought.

⭐ **DECIDED (user, 2026-08-25): (a) — THE SHOWCASE OPENS THE WRONG WAY, AND (c) IS PROBED BESIDE
IT.** The slider therefore teaches §4.2b's headline (the cost of not knowing which side), and what a
smarter opening rule would have bought is a measured number rather than an untested assertion.
⚠ **THE AUTHORING OBLIGATION THAT COMES WITH (a):** the scenario must say IN ITS HEADER that the
opening direction is authored against the missile, and why — a reader who discovers that for
themselves will (rightly) call the showcase rigged. The honest framing is that a real missile's
opening guess is a COIN FLIP, and this wire authors the losing half so the cost is visible; the
winning half is `p1`'s BEST column and is pinned as a test.

---

## ⚠⚠⚠ §4.3 — GATE 0, PROBES **P1 / P2 / P2b** (2026-08-25): **THE SEARCH WORKS. THE WIRE CANNOT PRICE IT.**

`p1_fly.jl`, `p1b_arm.jl`, `p2_wire.jl`, `p2b_cov.jl`, logs beside them.

⭐ **P1 FLIES THE REAL BRANCH WITH NO CORE PATCH, AND THAT IS NOT A SHORTCUT — IT IS THE SEAM GATE 2
WOULD USE.** `observe!` slews the head near its TOP off `:head_tgt_*` / `:head_cued` and writes those
keys near its BOTTOM (the one-tick seam, discipline 2). ⇒ overwriting them after `tick!` returns is
consumed by the NEXT tick's slew. Everything downstream is the shipped article: the 240 °/s limit,
the 30° stop, τ = 0.05, the radome bend, `σ_seek`, the window gate, the tracker's `seek_init`, PN,
the airframe. **It also enforces §0 fact 2's discipline from outside** — the core writes `head_tgt`
from TRUTH every tick and this probe overwrites it afterwards.

### §4.3a — THE SEARCH ACQUIRES, AND P0b's OVERLAY WAS ~2× OPTIMISTIC

Arm 50.0 m/s, S = 10°, wrong-way opening:

```
   ρ °/s  acquires   t_lock s   search s      CPA m   auth pk%   hold %
     0–80    NEVER          —          —    408.654       0.00     0.00
    100.0     lock     7.6260     0.3150    183.662     100.00    72.27
    120.0     lock     7.5770     0.2660    168.840     100.00    77.47
```

P0b put this cliff at 50 → 55 °/s; **flown it is 80 → 100 °/s.** The overlay was optimistic by
construction (no servo lag, no bend, no noise, lock granted the instant geometry allowed) and it was
optimistic by about a factor of two. ⭐ **The direction of the error is the useful part: a kinematic
overlay is a LOWER BOUND ON THE RATE, never an estimate of it.**

### ⚠⚠⚠ §4.3b — **AND THE MISSILE STILL MISSES BY 51–408 m ON EVERY ARM**

The arm re-derived on flown data (S = 10°, wrong-way opening; each cell `t_search / CPA / peak
authority`):

```
  gain |    ρ = 0   |     ρ = 50      |     ρ = 70      |    ρ = 100      |    ρ = 160
  39.0 | NEVER 317m | 0.552s 158.1m   | 0.380s 315.7m 0%| 0.268s  79.7m   | 0.175s  51.1m
  40.0 | NEVER 325m | 0.562s 323.8m 0%| 0.386s 121.8m   | 0.272s  88.7m   | 0.177s  59.4m
  42.0 | NEVER 342m | 0.585s 191.0m   | 0.398s 141.6m   | 0.280s 107.3m   | 0.182s  77.1m
  45.0 | NEVER 367m | NEVER           | 0.417s 171.7m   | 0.291s 135.1m   | 0.189s 103.6m
  50.0 | NEVER 409m | NEVER           | NEVER           | 0.315s 183.7m   | NEVER
```

**NO CELL RECOVERS THE ENGAGEMENT.** The best result anywhere is 51.1 m, against slice 47's
surviving arms which arrive at 0.1–2.5 m. ⚠ **AND THE AUTHORITY GAUGE IS PINNED AT 100 % OF `a_max`
ON EVERY LOCKING CELL** — which is `CLAUDE.md`'s own named harness trap (*an rms measured where a
CLAMP binds cannot move and reads as a KILL*). **Slice 46/47's gauge cannot grade this slider at
all.** ⚠ Two cells lock and then report 0 % authority with a ~320 m miss (39.0/ρ 70, 40.0/ρ 50), and
the bottom-right cell **fails at ρ = 160 where ρ = 100 and 120 succeed** — the pattern has PHASE
LUCK, and a non-monotone showcase slider is disqualified by this project's own rule.

### ⚠⚠⚠ §4.3c — **RETRACTED IN FULL BY §4.4. DO NOT QUOTE THIS SECTION.** ~~P2/P2b: the pointing error and the intercept error are the same quantity~~

> **This section's conclusion is WRONG and its cause is diagnosed in §4.4: every "never acquires"
> cell below was a head PINNED ON ITS 30° MECHANICAL STOP, not a wire that cannot price a search.**
> The measurements are reproduced unchanged because the retraction is only legible beside them, and
> because §4.4's tell — *a SMALLER gap failing where a LARGER one succeeds* — is visible in this very
> table to anyone who reads it after the fact. **Its algebra is wrong too** (advisor): recoverability
> is set by the ACCELERATION needed, `≈ v·gap·v_close / r_hand`, which FALLS as the handover range
> rises at fixed gap — so the two quantities are locked together only if `r_hand` is held fixed,
> which every cell here did except one.

#### ~~The retracted claim, kept for the record~~

The hypothesis P2 tested was slice 44's rule one level up — *a search can only price a sweep rate if
the engagement is still WINNABLE when the receiver opens* — with the target's RCS (slice 46's own
slider) as the knob that buys time. **Every reachable cell falls into one of two states, and there is
nothing in between:**

```
rcs 0.005 gain  50 : r_hand 2148 m  cue@h  7.51°  NULL ALREADY LOCKS (0.32 m) — no deficit
rcs 0.020 gain  90 : r_hand 3038 m  cue@h  7.93°  NULL ALREADY LOCKS (0.30 m) — no deficit
rcs 0.080 gain 140 : r_hand 4296 m  cue@h  5.97°  NULL ALREADY LOCKS (0.35 m) — no deficit
rcs 0.005 gain  90 : cue@h 14.04°  NULL 753.0 m  | best search: 69.6 m  (S=15, ρ=240)
rcs 0.005 gain 140 : cue@h 23.50°  NULL 1200.2 m | never acquires at ANY (S, ρ) tried
rcs 0.020 gain 200 : cue@h 20.01°  NULL 1757.1 m | never acquires at ANY (S, ρ) tried
```

⭐⭐⭐ **AND THE REASON IS STRUCTURAL, NOT A FAILURE TO FIND THE RIGHT CELL. On this wire the angular
gap the search must close and the lateral error the missile must fly out are THE SAME NUMBER DIVIDED
BY THE RANGE.** Both are `picture error × time spent blind`; the search sees it as an angle and the
airframe sees it as metres. ⇒ **no knob can make one large and the other small.** Raising the picture
error raises both; opening the receiver earlier (bigger RCS) lowers both. The two states above are
the two ends of one axis with no habitable middle:

- **a deficit small enough to be recoverable is small enough that there is no deficit** (the null
  locks unaided, and there is nothing to search for — slice 42's original blocker, returned); and
- **a deficit large enough to need a search comes with a lateral error large enough to lose the
  shot** (753 → 1757 m nulls, best-case searches at 69–250 m).

⇒ ⚠⚠⚠ **A SEARCH PATTERN CANNOT BE PRICED WHERE THE ONLY SOURCE OF POINTING ERROR IS THE
MIDCOURSE's OWN PICTURE ERROR.** It needs a deficit source **ORTHOGONAL to the intercept solution** —
a pointing error that costs TIME and nothing else.

### ⚠⚠ §4.3d — **RETRACTED AS A CONCLUSION BY §4.4** (it survives only as a candidate for a LATER slice)

**INS DRIFT** (`docs/DEFERRALS.md`, "New candidates raised by slice 47"). If the missile's estimate
of **its own attitude** is wrong, the head is commanded to the wrong **body** angles while the
**inertial** intercept solution stays exactly as good as the datalink made it. ⭐ **That is a pointing
error whose entire cost is the time taken to find the target again — which is precisely what a search
pattern exists to spend, and precisely what this wire cannot produce.** DEFERRALS already flags it as
needing its own model test and warns (via slice 31) about compensating with a signal corrupted by
what you are compensating.

⚠ **THE SHAPE OF THIS RESULT IS SLICE 44's, VERBATIM.** Slice 44: *"the physics is not what failed,
what failed is the WIRE"*, and its rule — *a detection gate can only price a design variable if the
engagement is launched OUTSIDE the sensor's horizon* — is this one's parent. **The generalisation
worth carrying: a component that spends a RESOURCE can only be priced on a wire where that resource
is the thing in short supply.** A search spends TIME; slice 47's wire is short of ANGLE-INDEPENDENT
MANOEUVRE, and time is not what it lacks.

### §4.3e — WHAT SURVIVES, AND WHAT IS NOT CLAIMED

**SURVIVES, and is banked whatever happens to the slice:**
- The one-tick-seam technique (§4.3's opening) — a search branch is flyable end-to-end with **no core
  patch**, which makes gate 2 a transcription rather than an experiment.
- §4.2b's headline (**opening the wrong way costs 3–4× in sweep rate**) and §4.2c's coverage **V**,
  both measured, neither refuted — they are properties of searching, not of this wire.
- §4.3a's rule: **a kinematic overlay bounds the rate from below and must never be quoted as an
  estimate** (measured 2× here).
- §4.1b's mechanism: the target's angular departure from a stale belief **accelerates** as the range
  closes, so a search wins early or not at all.

**NOT CLAIMED:**
- That a search pattern is dead. **It is not** — it acquires, it obeys a legible law, and every
  finding above is about the WIRE.
- That INS drift will work. It is a **named hypothesis** with a gate-0 of its own to run.
- Any miss figure in §4.3b/§4.3c as an accuracy claim. Once the missile is saturated for the whole
  endgame these are divergence magnitudes (DEFERRALS: *quote the VERDICT, never the metres*).

---

## ⭐⭐⭐ §4.4 — GATE 0, PROBE **P3** (2026-08-25): **§4.3 WAS MEASURING THE MECHANICAL STOP**

`p3_stop.jl`, log `p3.log`. ⚠⚠ **Raised by the advisor from §4.3's OWN TABLES, before any new
measurement:** a **smaller** gap was failing where a **larger** one succeeded (2.93° never acquires,
4.04° does), and one cell had a cue error of **8.94° — INSIDE the 10° window — and still never
locked.** *A cue error inside the window that does not produce a lock means something other than the
gap is refusing it.*

**IT WAS THE STOP, AND THE DIAGNOSTIC IS NOT SUBTLE.** `head_cue_err_handover_deg` is cue-vs-**truth**,
not the cue's **body angle**; the truth LOS body angle on this wire runs +18° → −15° over the
approach, so a cue 13° off truth sits at 25–31° of body angle — **on or past `gimbal_stop_deg = 30`.**
Logging the commanded body azimuth against the head's actual one:

```
rcs 0.020 gain 140.0  cue@h 12.93°  NEVER LOCKS   TICKS ON THE STOP: 28.3 %
    t−t_h   COMMANDED°  HEAD ACTUAL°   cue centre°   stop°
    0.000       26.192        26.195        26.192    30.0
    0.300       48.214        29.998        26.214    30.0   <-- ON THE STOP
    0.400       30.221        29.998        26.221    30.0   <-- ON THE STOP
    0.700       44.242        29.997        26.242    30.0   <-- ON THE STOP
```

**The probe commanded 48° and 53°; the head sat at 29.998°.** `head_clamp` absorbed the sweep
silently, exactly as designed — a head cannot travel past its own trunnion. **27–37 % of every search
tick, on all three failing cells.** ⇒ this also explains §4.3b's two anomalies (a lock followed by
**0 % authority** and a ~320 m miss) and the 72–77 % intermittent hold: **that is a stop signature,
not a manoeuvre-budget one.**

⚠⚠ **THIS IS THE FOURTH TIME THIS PROBE FAMILY HAS BEEN BITTEN BY AN INSTRUMENT THAT DID NOT DRIVE
THE HEAD IT THOUGHT IT WAS DRIVING** (slice 43's `p7b_frontier.jl` TELEPORTED the head in every cell;
slice 45's box; slice 42's `off ≤ fov` echo). ⭐ **The transferable form, and it is stronger than the
finding: when a head-pointing probe reports "never", LOG THE HEAD'S ACTUAL ANGLE AGAINST THE
COMMANDED ONE BEFORE BELIEVING THE VERDICT.** A clamp is invisible in every downstream number.

⭐⭐ **AND THE STOP IS A REAL FINDING IN ITS OWN RIGHT, NOT JUST AN ARTIFACT: THE MECHANICAL TRAVEL IS
A HARD CEILING ON SEARCHABLE VOLUME.** A search can only look where the trunnion can point, and the
cue itself already spends most of the travel. That is slice 45's elevation stop (*"read, clamping,
working hardware"*, binding 66–68 % of in-band ticks) arriving on the azimuth ring with teeth.

## ⭐⭐⭐ §4.5 — GATE 0, PROBES **P4 / P5**: **THE HABITABLE CELL EXISTS, AND THE SLIDER IS MONOTONE**

`p4_control.jl` / `p5_fine.jl`, logs beside them. With `gimbal_stop_deg` authored at **45°** — an
utterly ordinary seeker trunnion, and an AUTHORED hardware parameter rather than a knob — §4.3c's
"two states with nothing between them" dissolves.

### ⭐⭐⭐ §4.5a — THE SHOWCASE CELL

`rcs_m2 = 0.020`, picture error **140 m/s**, stop 45°, S = 25°, wrong-way opening.
Handover at **3038 m**, cue error **12.93°** against the 10° window ⇒ a **2.93° deficit**:

```
   ρ °/s   acquires   t_search s        CPA m   auth pk%
       0      NEVER            —      1200.17        0.0     <- what ships today
      20      NEVER            —      1200.17        0.0
      40       lock       1.7350      1186.21        0.0     <- ⭐ A LOCK THAT ARRIVES TOO LATE
      60       lock       1.0530       233.57      100.0
      80       lock       0.7740        78.35      100.0
     100       lock       0.6180         2.86      100.0
     120       lock       0.5170         0.54      100.0
     150       lock       0.4190         0.39      100.0
     180       lock       0.3550         0.19      100.0
     210       lock       0.3090         0.20      100.0
     240       lock       0.2750         0.37      100.0
```

**MONOTONE FROM A 1200 m NULL TO 0.19 m**, with a knee at ρ ≈ 100 °/s, and — ⭐⭐ **the best cell in
the table is ρ = 40: THE SEARCH FINDS THE TARGET AND IT CHANGES NOTHING.** It locks 1.735 s after
handover, spends **0 %** of `a_max`, and misses by 1186.21 m against a null of 1200.17 m. **A lock
that arrives too late is indistinguishable from no lock** — which is this slice's version of slice
42's "worthless lock", except that here it is NOT a relabelled null (it differs by 14 m and by a real
`t_lock`) and it sits inside a slider that also contains a 0.19 m arm. **This is the arm the showcase
should open on.**

### §4.5b — THE SECOND CELL, KEPT AS THE CONTROL

`rcs 0.005`, error 90 m/s (45 % of the crossing speed), same stop: null **753.0 m**, and the slider
walks **468.8 → 343.3 → 272.2 → 226.4 → 180.3 → 149.6 → 128.0 → 111.7 m** over ρ = 60 → 240.
**Perfectly monotone and it NEVER recovers the shot.** ⇒ **the two cells together are the lesson**:
whether a search can save an engagement is a property of the **wire**, and the slider looks
qualitatively identical from inside either one. ⭐ That is slice 44's rule stated from the other
side, and it is a better control than any synthetic null.

### ⚠⚠ §4.5c — THE ONE OPEN QUESTION, AND IT IS ABOUT AUTHORING, NOT PHYSICS

**140 m/s of velocity error against a 200 m/s crossing target is 70 %.** Slice 47 argued 25 % as the
defensible ceiling for a *datalink quality* story, and 70 % is not a datalink quality story — it is
"the target did something else". Three ways out, none yet measured:

1. **Author it as a POSITION error instead** (`midcourse_pos_err_m`, deliberately omitted by slice 47
   as "one axis at a time"). The geometry needs ~697 m of lateral offset at handover, which is a
   large but arguable handoff error from a long-range ground radar. ⚠ Needs its own gate-0 — a
   position error and a velocity error do NOT subtend the same angle history.
2. **Reframe the scenario as a MANOEUVRING TARGET** — the honest physical story for a 70 %
   discrepancy, and a named deferral (`docs/DEFERRALS.md`, slice 47's candidates). ⚠ DEFERRALS warns
   this risks being slice 47's lesson in different clothes and wants a probe showing the failure MODE
   differs.
3. **Ship the 70 % and label it honestly** as a target that changed course, not as datalink noise.

⚠ **AND THE STOP CHANGE MUST BE AUTHORED WITH ITS REASON IN THE HEADER** (§4.4): 45° is ordinary
hardware, but a reader who finds the showcase quietly using different hardware from slice 47 will —
rightly — ask what else moved. The reason is one sentence: **a search needs somewhere to look, and a
30° trunnion is a search that cannot leave its cue.**
