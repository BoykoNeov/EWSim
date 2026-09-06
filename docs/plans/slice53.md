# Slice 53 — **A TAIL LOBE**: does a target look the same going away as coming at you?

**STATUS: GATE 0 IN PROGRESS — P1–P6 HAVE RUN (P1/P2/P3 2026-08-31, P4–P6b 2026-09-06). ⭐ F1, F2,
F4 AND F5 ARE DISCHARGED, and F3's THREE filters — monotonicity, the bar, and *not sayable without
the asymmetry* — are ALL discharged. ⚠ **F3 IS NOT CLOSED — its ENDPOINT JUSTIFICATION is still
P7's, and P7 IS THE ONLY PROBE LEFT.**
⚠⚠ **TWO THINGS EVERY LATER PROBE AND GATE 1 MUST CARRY:** (1) `load_scenario` **silently DROPS**
`rcs_tail_gain` — **INJECT it, never AUTHOR it**, until gate 1 teaches the loader (§2.13a, which
also CORRECTS P5 §4's stated cause); (2) the headline **metres are a joint property of the tail lobe
and the TRACKER** (`revisit_s` + the give-up rule) — the SIGN is physics, the SIZE is not, so every
number is quoted with its `revisit_s` and `N`\* or it is not a measurement (§2.14).
⚠ P3 FIXED TWO THINGS P4–P7 MUST USE VERBATIM: the run-length rule `N`\* = 3 and MIRRORED edges
(§2.8). The ceiling is 50 and **P4b confirms it stands** — ⚠⚠ **P4 §E's "RETRACTED" verdict on
§2.8's bar IS NOT ISSUED; do not quote P4 §E** (§2.11). **§2.3's and §2.6's ladder magnitudes are
superseded by §2.8, and §2.5 item 3's +2924 m by §2.10 — do not quote them.**
⚠ Everything below the falsifier list was written as a PREDICTION before any probe ran (slice 41's
discipline — `docs/LESSONS.md:13`, *"pre-register the falsifier"*) and is **left unedited on
purpose** so the predictions can be scored. **§2 at the foot of this file records what was
MEASURED, including where the predictions were wrong.** Probes and their full write-ups live in
`M:\claud_projects\temp\slice53\`. No core change is authorised by this document; §0 states what a
core change would be IF gate 0 lives.

The candidate, in `M:\claud_projects\EW\docs\DEFERRALS.md` §"New candidates raised by slice 49":

> **⭐⭐ A TAIL LOBE (fore/aft asymmetry).** `rcs_aspect` is fore/aft SYMMETRIC by construction —
> σ(θ) ≡ σ(π−θ), so a fleeing target looks exactly like an approaching one, and slice 49's HUD has
> to say "tail-on" rather than "nose-on" past 150° because the model genuinely cannot tell them
> apart. Real airframes have a distinct tail return (engine face, exhaust). ⚠ Named as an
> approximation in the docstring, so this is a DEFERRAL and not a defect. **The gate-0 question is
> whether it can carry a LESSON**: it needs a scenario where the same target is engaged from both
> ends, which slice 49's single-radar circle is not. Candidate wire: the two-observer geometry gate
> 2 already tests.

…and its raised stakes, in §"New candidates raised by slice 50":

> **⚠⚠ THE TAIL LOBE (slice 49's candidate) NOW HAS HIGHER STAKES — IT WOULD BREAK A SHIPPED
> TOOTH.** […] a tail lobe is no longer an additive change: it retires that identity, and whichever
> slice ships it must say what replaces the tooth.

**THE PROPOSED LESSON, in one sentence.** *Which way a target points does not just change how
bright it is — it changes it ASYMMETRICALLY, so the same target on the same pass at the same range
is held far longer running away than coming in, and no single cross-section number can say that.*

⚠ That is deliberately the SHAPE of slice 49's headline one level up: 49 proved *only a shape makes
a closing target harder to see*; this claims *only an ASYMMETRIC shape makes the two ends of a pass
different*. If the probes cannot separate the two claims, this is 49 with a sign flip and it dies
here.

---

## §0 THE MODEL TEST — ⚠ THERE IS NO MODEL YET, WHICH MAKES THIS SLICE A DIFFERENT SHAPE FROM 52

Slice 52's §0 could settle the MODEL half by INSPECTION because the key already existed and was
already read every tick. **Nothing here exists.** This slice proposes a new kernel, so the two-test
rule's model half is a THING TO BUILD AND CHECK, and it is held to the bar the 2026-08-18
re-verdict states for new proposals: *read by the physics every tick, correct in its own units, or
no ship.*

### §0.1 The proposed kernel — ONE key, and the design constraint is what it must NOT disturb

    σ(θ) = σ_b · [ 1 + (G − 1)·max(0, −cos θ)² ] / (sin²θ + F²·cos²θ)²

added to `rcs_aspect` (`core/src/rf.jl:222`), with `G` = `rcs_tail_gain`, dimensionless, authored
beside `rcs_fineness` in the `target:` block.

**Every term of that bracket is chosen by what it must leave alone**, and each is a checkable claim
rather than a preference:

- **`max(0, −cos θ)` is zero on the whole FORWARD hemisphere** (θ < π/2) ⇒ nose-on and every
  approaching aspect is EXACTLY the shipped number. Slices 49 and 50's mechanism — the nose-on
  collapse as the target turns toward the observer — is untouched, bit for bit.
- **The weight is zero AT broadside** ⇒ `rcs_aspect(σ, F, π/2) = σ` still holds at every `G`, so
  `rcs_m2` keeps the sharper meaning slice 49 gave it (the BROADSIDE peak) and slice 50's
  "every arm of the slider starts on the same cross-section" argument survives verbatim.
- **Squared, not linear** ⇒ the derivative is continuous at broadside; no kink for a detector to
  trip over. ⚠ It also makes the lobe HEMISPHERE-WIDE (half-power ~45° off the tail) rather than a
  narrow nozzle spike. **That is a named approximation and must be written into the docstring**, in
  the same posture as the fore/aft symmetry it replaces — a real exhaust return is narrower.
- **`G = 1` collapses the bracket to `1 + 0.0·x` = exactly `1.0`**, and `σ·1.0 == σ` in IEEE
  arithmetic ⇒ the LESSON null is exact, not approximate. ⚠⚠ It is still **NOT** the WIRE null:
  the byte-identity path stays the KEY BEING ABSENT (slice 49's rule, and the same floating-point
  reason — `sin²+cos²` is not always 1.0).
- **Tail-on reads `G·σ_b/F⁴`** ⇒ `G` has a one-sentence physical meaning a student can hold: *the
  tail is G times brighter than the nose.* At `F` = 8 and `G` = 100 the tail is 20 dB above the
  nose and still 16 dB below broadside — an ordinary airframe, not a special effect.

⚠ **`G < 1` is LEGAL and is a QUIET tail** (the posture `F < 1` already has: an oblate body is
legal and means something). Domain: `G > 0`, `DomainError` outside — `rcs_aspect`'s existing
posture, clamped at the CONSUMER (convention 5) because a live slider must never throw inside a
tick.

### §0.2 Why multiplicative and not additive — settled before probing, because it is arithmetic

A physically tempting alternative is a separate scatterer: `σ = σ_body(θ) + σ_tail·h(θ)`. **It is
refused, and not on taste.** `σ_body` is at its MINIMUM at the tail (`σ_b/F⁴`, four orders down at
F = 10), so an additive term scaled off `σ_b` swamps the entire curve for any `σ_tail` big enough
to matter, and one scaled off `σ_b/F⁴` is the multiplicative form wearing a second key. The
multiplicative form gives one dimensionless key with a physical sentence; the additive form gives
two keys, one of which has to be re-authored every time `F` moves.

### §0.3 The presence gate, and what "a sphere with a tail" means — ⚠ DECIDED HERE, NOT LATER

`_effective_rcs` (`core/src/radar.jl:343`) early-returns on `rcs_fineness` being absent. **The tail
gain is gated on the SAME key, and is read INSIDE that branch.** Consequences, all deliberate:

- A wire with no shape at all is untouched — the slices 1–52 line, `===` on the authored object.
- `rcs_tail_gain` authored WITHOUT `rcs_fineness` is **refused at load** (`scenario.jl`), not
  silently ignored. ⚠ This is the `speed` (19) / handover-bias (36) failure mode, and the whole
  point of the MODEL test: a key nothing reads is a bug, so the loader must make it unauthorable.
- **A sphere with a tail lobe is incoherent and the model says so out loud:** at `F` = 1 the body
  curve is flat, and `G` then tilts a sphere, which is not a body of revolution any more. The
  docstring names it; **the showcase avoids it by authoring `rcs_fineness: 8.0` FIXED** — the
  arc's own value (49 and 50 both author 8), not a knob, so the shape is held still while the
  ASYMMETRY is dialled (convention 9: one mechanism on the wire). ⚠ It is NOT refused at load —
  `F` = 1 with `G` = 100 is a legal call and returns a finite number, because a kernel that throws
  on a live slider's floor is convention 5's exact prohibition.

**THE SLIDER'S DOMAIN, pre-registered as a PROCEDURE rather than a number** (`docs/LESSONS.md`: *a
number you invented must not decide a headline*):

- **FLOOR = 1.0, fixed and non-negotiable** — the exact symmetric null, and the same "the floor is
  the lesson's null, not the wire's" posture slice 49 and 50 both ship.
- **CEILING = decided by P7's ladder**, measured over `G` ∈ {1, 2, 5, 10, 20, 50, 100} and quoted
  in full so a reader can redraw the line. It is the last cell that is still MONOTONE in the gauge
  **and** still a physically ordinary airframe — at `F` = 8 the tail sits `G/4096` of broadside, so
  `G` = 100 is a tail 20 dB above the nose and still 16 dB below broadside.
- ⚠ **THE AXIS IS IN dB AND THE SLIDER IS LINEAR** — the opposite of slice 49's situation, where
  the payoff concentrated at the TOP and linear was right. Here `G` = 1 → 10 is 10 dB and
  10 → 100 is another 10, so a linear 1–100 drag spends 90 % of its travel on the second half of
  the effect. **If P7's ladder confirms that, the ceiling comes DOWN rather than the axis going
  log** (the knob protocol carries min/max, not a curve).

### §0.4 The seam, and the ONE site

`_effective_rcs` is the ONE site where a shape becomes a cross-section (slice 49's decision) and
both the ground radar and the missile seeker already route through it. ⇒ **a tail lobe reaches the
seeker for free, and that is a hazard, not a bonus**: F1 below exists because "for free" means
"unmeasured on two shipped wires."

---

## §0.5 THE PRE-REGISTERED FALSIFIERS — fixed in writing BEFORE any probe runs

⚠ Ordered by LETHALITY, not convenience (`docs/LESSONS.md:13` — *fly the kill risk before the
mechanism*). Each is copied into its probe file's header. **F1 and F2 are the slice; F3–F6 are
hygiene.**

### ⚠⚠ F1 — WHICH SHIPPED WIRES EVER VISIT THE REAR HEMISPHERE **WHILE DETECTABLE**

The bracket is identically 1.0 for θ < π/2, so the knob can only bite where the observer is BEHIND
the target. ⚠⚠ **THE ARITHMETIC FIRST** (`docs/LESSONS.md:13` — *run the arithmetic premise before
the code*), and it PREDICTS A SPLIT rather than the flat "inert everywhere" a first draft of this
section asserted:

- **Slice 50 — forward hemisphere throughout.** 30 m/s² at 300 m/s is 0.1 rad/s ≈ 5.7 °/s over a
  ~6–8 s flight ⇒ **~40° of heading change**, from 90° aspect toward ~50°. The bracket never
  leaves 1.0. **Prediction: byte-identical at every `G`.**
- **Slice 49 — ⚠ PREDICTED TO REACH IT.** 15 m/s² at 300 m/s is 0.05 rad/s ≈ 2.86 °/s over 90 s ⇒
  **~258° of heading change**, so the orbit carries the nose through 0° and out the far side. The
  bracket is LIVE for part of that run.

⇒ **the question F1 actually asks is not "is it inert" but "are the rear-hemisphere ticks ones
where the target is DETECTABLE at all"** — at `F` = 8, tail-on σ is `σ_b/4096`, which may be dim
enough that a live bracket changes nothing that any gauge can see.

- **The probe:** replay both shipped wires unmodified, log `aspect_angle` every tick, print
  min/max, the fraction of ALL ticks with θ > 90°, and — the column that decides it — the fraction
  of **DETECTED** ticks with θ > 90°.
- **OUTCOME A (predicted for 50, and for 49's detected ticks): no detectable rear-hemisphere time
  ⇒ the slice must author a NEW geometry.** ⭐ That is a finding, not a failure: it says in one
  measurement that this candidate cannot be "slice 49 with one more key", which is the shape four
  of the five 41–45 kills took.
- **OUTCOME B: a shipped wire spends DETECTED ticks behind the target** ⇒ the slice may be cheaper
  than expected, **and** slice 49/50's byte-identity stories must be re-checked before anything
  ships. ⚠ The presence gate contains the risk either way — neither shipped scenario authors a
  `rcs_tail_gain`, so both stay byte-identical regardless — but an "inert" claim in the write-up
  would be false, and this arc kills slices for exactly that (`docs/LESSONS.md`: *an "on every arm"
  claim must name the arms where the mechanism does not run*).

### ⚠⚠ F2 — THE REPARAMETERIZATION KILL: **ONE ASPECT IS ONE NUMBER, AND ONE NUMBER IS A GAIN**

This is slice 41's kill in aspect-space and it is the one that ends the slice. `G` multiplies the
cross-section by a factor fixed by θ. **On any engagement that sits at essentially ONE rear aspect
— a stern chase is exactly this — `G` is indistinguishable from a larger `rcs_m2`:** both scale σ
by a constant over the whole flight, so the ladder in `G` is reproduced by a ladder in `rcs_m2`
with no lobe present at all. Slice 39's rule then applies: a reparameterization must not ship as an
architecture.

- **The probe:** for each candidate wire, print the aspect HISTOGRAM over the detected ticks. Then
  fit — is there a single scalar `s` such that `rcs_m2 → s·rcs_m2` reproduces the whole gauge
  ladder in `G` to within the gauge's own noise?
- **The slice lives ONLY on a wire whose aspect SWEEPS the rear hemisphere while the target is
  detectable**, because only then does the lobe change the SHAPE of the echo-vs-time curve rather
  than its level. ⚠⚠ **A stern chase is therefore predicted DEAD as this slice's wire** — it is
  the obvious "engaged from both ends" geometry and it is the one that reparameterizes.
- ⚠ The two-observer test named in the ledger (`core/test/test_rcs_aspect.jl:239`) is **NOT** a
  wire: it is a static two-point σ comparison in a bare world with no movers and truth written by
  the caller. It proves the seam; it cannot carry a slider, a gauge or a headline. **The ledger's
  suggested wire does not exist, and gate 0's hardest question is building one.**

### ⚠⚠ F3 — THE GAUGE MUST BE UN-BANNED, MONOTONE, AND NOT SAYABLE WITHOUT THE ASYMMETRY

Three filters, all of which have killed something on this arc:

- **The MISS is banned four times** (44, 46, 48, and 50 re-earned it). Not available, and not to be
  re-litigated.
- **49's gauge is the longest loss run while closing; 50's is `ω_LOS·t_go` at the loss.** A gauge
  that is either of those in new units fails slice 50's own SUBSTITUTION TEST (*if a ground radar
  with a scalar RCS can say it, it is not this slice's*).
- **Monotone over the whole authored slider domain**, or it joins `k` (28), `ω_n` (40), `σ_seek`
  (25) and the loss COUNT (49).

**The proposed gauge, pre-registered so it can be refuted:** on a single straight pass, the
DIFFERENCE between the range at which the track is finally lost on the OUTBOUND leg and the range
at which it is first gained on the INBOUND leg — *"how much further you can follow it home than you
could ever see it coming."*

⭐ **THE THEOREM, and it is about the ECHO:** with `G` = 1 the model gives σ(θ) ≡ σ(π−θ), so at
equal range the two legs present the IDENTICAL cross-section and the pass is symmetric in echo.
**No scalar `rcs_m2` and no `rcs_fineness` can produce an asymmetry** — the substitution test is
passed by construction.

⚠⚠ **AND THE THEOREM DOES NOT REACH THE GAUGE, WHICH IS THE TRAP.** The gauge is a range
difference read through a **Swerling-1 detector**: identical σ on the two legs still means
DIFFERENT random draws, so the measured difference at `G` = 1 will be some non-zero fading noise,
not zero. Slice 49's own control is the precedent and it is the favourable one — its sphere arm
flickered **41 separate times** and the slice earned its headline as a **183× separation against a
control that could and did fail**, never as "the control was silent."

⇒ **PRE-REGISTERED, so a non-zero reading at high `G` is attributable:** P3 must first fly the
`G` = 1 wire across **N ≥ 8 seeds** and quote the noise floor in metres (mean and max |asymmetry|).
The `G` ladder must clear **max-null × 3** at its authored ceiling, or the gauge is measuring the
detector and the slice dies. ⚠ This is a DIFFERENT null from F4's: F4's is exact because it is the
same arithmetic path; F3's is stochastic because a detector sits between the physics and the
number. Slice 49 kept the LESSON null and the WIRE null apart for the same reason one level over —
do not let F4's exactness be quoted for F3.

### ⚠ F4 — THE NULL MUST BE MEASURED, NOT DEFINED (slice 50's rule, applied to a NEW kernel)

`G` = 1 must be BYTE-IDENTICAL to the key being absent over a whole flight (`max|Δpos|` = 0.000e+00
and identical telemetry), and the key-absent path must still `===` the authored object. ⚠⚠ Both
must be shown; slice 49's own note is that these are two different things reached by different
code, and a new kernel is exactly where they drift apart.

### ⚠ F5 — THE THRESHOLD (IF ANY) MUST SURVIVE A HALVED STEP

Slice 42 died because its band was one integration step wide; slice 51 died because a boundary
FLIPPED at `dt/2`. Any cliff quoted here is re-flown at `dt` = 5e-4 and the movement printed. ⚠ A
detection-threshold crossing under Swerling-1 fading is a STOCHASTIC boundary — the re-fly must
compare the same seeded stream, and a gauge that moves with `dt` at fixed seed is dead.

### ⚠ F6 — THE RETIRED TOOTH, ANSWERED BEFORE PROBING (the ledger's own instruction)

`clients/godot/net/slice50_ui_test.gd` tooth 9b asserts `_s50_word(d) == _s50_word(180 − d)` **as
an identity**, correct because `rcs_aspect` is symmetric by construction.

**⭐ THE ANSWER IS THAT NOTHING REPLACES IT — IT IS RE-SCOPED, AND SLICE 50's WIRE KEEPS IT
UNCHANGED.** `scenarios/slice50_defensive.yaml` authors no `rcs_tail_gain`, so on that wire the
model still genuinely cannot tell nose from tail and the vocabulary still must not pretend
otherwise. The tooth's comment gains ONE clause naming the condition it was always relying on
(*"on a wire with no tail gain"*), and slice 53 ships the MIRROR tooth on its own wire: with a tail
gain authored, the word at θ and at 180 − θ must DIFFER, and the tail word must be reachable only
where the lobe is. ⚠ **A vocabulary is a gauge and must be scored like one** (slice 50) — the new
words are held to the same bar: resolution over the slider's own domain, and no word that claims a
brightness the frame does not have.

---

## §0.6 THE CANDIDATE WIRES — what gate 0 has to build, and what it predicts about each

⚠ None of these exists. Listed with the prediction F2 makes about each, so the probe order is
decided in advance:

| wire | aspect over the flight | F2 prediction |
|---|---|---|
| **W1 — a straight fly-past of a ground radar** (49's radar block, a non-manoeuvring target) | sweeps 0° → 180° monotonically, through broadside at closest approach | ⭐ **SURVIVES** — the rear hemisphere is swept while detectable, so the lobe changes the SHAPE of the echo-vs-time curve; and the inbound leg is a built-in control flown by the same target on the same pass |
| **W2 — a stern-chase missile engagement** | pinned near 180° for the whole flight | ⚠⚠ **DIES** — one aspect is one number; `G` reparameterizes `rcs_m2` |
| **W3 — two observers, one target** (the ledger's suggestion) | two aspects, one instant | ⚠ not a wire at all — it is `test_rcs_aspect.jl`'s static seam test; no slider, no gauge, no headline |

⇒ **W1 is the wire to build**, and it is deliberately the SIMPLEST geometry in the whole arc: one
radar, one target, straight and level, no manoeuvre, no missile. Convention 9 is satisfied by
construction — there is exactly one mechanism on the wire, and the inbound leg is the control for
the outbound one.

⚠ **W1 has its own pre-registered hazard:** slice 49's wire needs a TURN because *a straight-flying
target's σ rises exactly while its range falls* — the two effects are aligned on both legs, which
is why 49 could not use a fly-past. **That alignment is what this slice measures against**, not an
obstacle to it: the symmetric model makes the two legs identical at equal range, and the lobe is
the only thing that can break the tie. But it means the DETECTION on both legs is dominated by
range, so the gauge must be read at RANGE, never at TIME.

---

## §0.7 WHAT WOULD SHIP IF GATE 0 LIVES (scope, stated up front so it cannot grow)

- `core/src/rf.jl` — the bracket inside `rcs_aspect`, plus a docstring that names the
  hemisphere-wide lobe as an approximation and RETRACTS the fore/aft symmetry paragraph in place.
- `core/src/radar.jl` — `rcs_tail_gain` read inside the existing presence branch of
  `_effective_rcs`. **No new call site.**
- `core/src/scenario.jl` — load-time validation, including the refusal of a tail gain with no
  fineness.
- `core/test/test_rcs_aspect.jl` — the null (both kinds), the domain, the broadside identity at
  every `G`, the forward-hemisphere byte-identity, and an EXTERNAL hand-checkable anchor at θ = π.
- `scenarios/slice53_*.yaml` + the four gate-3 proofs, and the re-scoped tooth 9b clause.

⚠ **NOT in scope:** a target attitude quaternion (49's other candidate — the nose is still the
velocity vector), a narrow nozzle lobe with its own width key, and any change to the seeker.

---

## §1 GATE 0 PROBE ORDER (to run next)

1. **P1 (F1)** — aspect over the two shipped wires. Cheapest, and it decides whether a new
   geometry is needed at all.
2. **P2 (F2)** — build W1 and W2 as probe scenarios; print the aspect histogram over detected
   ticks for each. **Kill W2 here if it pins.**
3. **P3 (F3)** — ⚠ the `G` = 1 NOISE FLOOR across N ≥ 8 seeds FIRST, then the gauge ladder in `G`
   on W1 with the inbound leg as the control. A ladder quoted without its floor is unattributable.
4. **P4 (F3/F2)** — the substitution test: sweep `rcs_m2` and `rcs_fineness` and show neither
   reproduces a non-zero asymmetry.
5. **P5 (F4)** — the two nulls, byte-identity.
6. **P6 (F5)** — halved step at the cells that decide the headline.
7. **P7 (F3)** — monotonicity over the intended slider domain, both endpoints justified.

⚠ **If P1 confirms inertness and P3/P4 find no un-banned monotone gauge, this is a GATE-0 KILL
RECORD and not a slice** — written up with both tests shown (`docs/LESSONS.md`: *a kill record must
show BOTH tests*), with the kernel's MODEL verdict stated separately from the LESSON one. Do not
reach for a fourth geometry to rescue it.

---

## §2 GATE 0 — WHAT HAS ACTUALLY BEEN MEASURED (append-only; §0/§1 above stay as written)

Full write-ups, with every raw number and the probe sources, are in
`M:\claud_projects\temp\slice53\p1_findings.md` and `M:\claud_projects\temp\slice53\p2_findings.md`
(probes: `p1_aspect.jl`, `p2_wires.jl`, `p2b_w1_length.jl`, `p2c_substitution.jl`, `p2d_flicker.jl`,
`p3_floor.jl`, `p3b_perseed.jl`, `p4_subst.jl`, `p4b_paired.jl`, `p5_nulls.jl`, `p6_halfstep.jl`, `p6a_keycheck.jl`, `p6b_teeth.jl`, `p6c_fliploc.jl`; raw output in the matching
`*_out.txt`). This section is the SUMMARY the repo carries.

### §2.1 P1 (F1) — DISCHARGED, and the plan's own hedge was refuted

The split §F1 predicted is real — the bracket is inert on `slice50_defensive` and LIVE on
`slice49_aspect` — but F1's expectation that 49's rear-hemisphere looks would be *too dim to matter*
is measured FALSE: **91 of 271 rear looks are already DETECTED**, and the 130–150° band flips at
`G` ≈ 10. ⚠ Consequences that bind later gates: an "inert on both shipped wires" claim would be
FALSE and must name slice 49 as the arm where the mechanism runs; 49's byte-identity holds by the
PRESENCE GATE, not by the geometry; and **slice 53 must not author `rcs_tail_gain` onto
`slice49_aspect.yaml`** — it would rewrite a shipped, quoted ladder.

### §2.2 ⭐⭐⭐ A THEOREM THAT PRUNES THE CANDIDATE SET (found while building P2)

`aspect_angle` is the angle between the target's velocity and the target→observer direction, so for
a **stationary** observer `ṙ = −‖v‖·cos θ` EXACTLY ⇒ **θ > 90° ⇔ the target is OPENING.** On any
ground-radar wire the rear hemisphere and the receding leg are the SAME TICKS: a tail lobe can only
ever brighten a target that is moving away, and a "rear hemisphere while closing" ground geometry
**does not exist**. Only a moving observer can be behind a target and still closing. ⇒ the candidate
set is CLOSED rather than sampled, and the slice's sentence is not a nicely-phrased gauge but the
only statement this kernel can make: *how much further you can follow it home than you could ever
see it coming.*

### §2.3 P2 (F2) — DISCHARGED ON W1; W2 DEAD; a THIRD wire the plan did not list is LIVE

⚠ The proposed kernel does not exist in the repo. It was patched onto `_effective_rcs` inside the
probe process, with the presence branch untouched, and **verified BIT-IDENTICAL to the shipped
kernel over 30 000 ticks of `slice49_aspect` with no tail gain authored.** ⚠ That is the patch being
honest — it is NOT F4/P5, which is a whole-flight `max|Δpos|` against the key being ABSENT.

- **W1 — the straight fly-past — LIVES, on a measured ladder.** 160 s, aspect 18.33° → 171.43°,
  range 15802 → 4970 → 33343 m. Gauge (first gain inbound, last loss outbound, read AT RANGE),
  seeds 53/149/250, mean asymmetry: `G` = 1 **−511.7 m** (the floor; max |asym| 1349.3 m ⇒ F3's bar
  is 4047.8 m), 2 → −46.2, 5 → +2745.5, 10 → **+4705.2**, 20 → +7222.0, 50 → +15755.5,
  100 → **+19684.2 m**. **Monotone in the mean AND on every individual seed**, clearing the bar from
  `G` = 10. ⚠ Three seeds is a RANKING read; P3 still owes the N ≥ 8 floor.
  ⚠⚠ **THESE MAGNITUDES ARE SUPERSEDED — SEE §2.6.** The outbound loss here is a single Swerling
  crossing, and it is measured to be a FLICKER: the final detection is routinely 80–181 looks after
  the previous one. The effect is real and stays monotone under a run-length rule, but every number
  in this bullet overstates it by ~1.7×. Quote §2.6's table, not this one. The INBOUND
  bit-identity below is unaffected and stands.
  ⭐⭐⭐ **THE STRUCTURAL FACT:** the INBOUND gain range is **bit-identical at every `G` from 1 to
  100** (10570.9 / 11265.0 / 9811.6 m) — the forward hemisphere is untouched by construction, so the
  whole ladder is ONE LEG MOVING WHILE THE OTHER IS NAILED DOWN. That is a shape change in the
  strictest available sense, and it is what F2 asks for.
- **W2 — the stern chase — DEAD, and slightly worse than F2 predicted.** Aspect over all pre-CPA
  ticks 108.62°–180.00° (median 175.63°) — it pins, as predicted. ⚠⚠ But over DETECTED ticks it is
  108.62°–132.20°, and only 1402 of 18 841 ticks are detected at all: **the seeker sees nothing for
  the first 92 % of the chase**, so the only ticks where the aspect moves are the r → 0 ENDGAME this
  arc bans quoting (44 §VII.1). 86 % of what `G` does on that span is a constant multiplier.
  ⚠ A MODEL statement worth keeping for the docstring: under the shipped symmetric model **a
  stern-chase seeker is blind for the whole chase**, because tail-on and nose-on are the same number.
- **W3 — a target that turns and RUNS under a missile (slice 50's wire with `turn_sign: +1`) — LIVE
  PHYSICS, REFUSED AS THE WIRE, NOT KILLED.** At `G` = 1 the lock is lost at t = 0.975 s and the
  missile coasts eight seconds blind; at `G` = 100 it holds to r = 0.2 m. Refused on three counts:
  (1) ⚠⚠ its natural gauge is the MISS, banned four times and **re-earned a fifth time here** —
  2668.8 → **2753.6** → 0.2 m is NOT monotone, and the `G` = 10 arm holds the lock all the way to
  closest approach and still misses by MORE than the arm that went blind at t = 0.975 s; (2) its only
  other gauge is slice 50's `ω_LOS·t_go`, which is this plan's own pre-registered "49 with a sign
  flip" kill; (3) the aspect barely sweeps — 7.89° over detected ticks at `G` = 1.
  ⇒ **If W1 fails P3, W3 is where to look next, and it would need a gauge invented rather than
  borrowed.**
- **F2's SECOND HALF — the scalar fit — HAS NO SOLUTION.** `rcs_m2` swept 4 → 64 and `rcs_fineness`
  swept 2 → 12 on W1 with **no tail gain present**: every uncensored arm stays inside the fading
  floor. They move the inbound and outbound ranges TOGETHER (`rcs_m2` 4 → 64 moves the inbound gain
  10.6 → 15.7 km and the outbound loss 10.0 → 18.4 km), which is what a brighter target does. **No
  scalar `s` can reproduce a ladder in which one of the two ranges does not move at all.**

### §2.4 ⚠⚠ A GAUGE DEFECT FOUND AND FIXED MID-PROBE — **EVERY EDGE NEEDS A CENSORING FLAG**

The gauge can be clamped at BOTH ends of the flight and the first probe guarded only one. The
outbound edge (a track still held when the run stops) was caught and cost a re-fly at 160 s. The
INBOUND edge is **slice 49's rule from the other side — *a probe that starts DETECTED cannot measure
a gain*** — and it nearly produced a false refutation of this slice's central theorem:
`rcs_fineness = 2.0` reported **+16 177 m of asymmetry with no tail gain present**, which was
entirely the wire's opening range being reported as a "gain". With the flag added, all three seeds of
that arm are censored and the arm has NO measurement. ⇒ a censoring flag must exist for every edge a
gauge can be clamped against, not for the one that bit last time.

### §2.5 WHAT P3 INHERITS, AND THREE THINGS IT MUST DECIDE RATHER THAN ASSUME

⚠⚠ **READ §2.6 FIRST — it adds a FOURTH thing (the loss rule `N`) and re-derives the numbers items
1 and 2 below are reasoning from.** The signed floor and the ceiling argument both move with the
rule, so treat the two items as questions that survive rather than as figures that do.

1. ⚠ **The `G` = 1 floor's MEAN is −511.7 m, not zero.** On three seeds that is inside the scatter
   (−1349 → +417). If N ≥ 8 confirms a NEGATIVE bias it is an asymmetry in the MEASUREMENT — the
   last-look-before-loss and the first-look-after-gain are not symmetric samplers while the range is
   changing — and it must be named, not left as a signed floor under a signed ladder.
2. ⚠ **The ceiling is not decided, and §0.3's worry about a linear 1–100 axis is CONFIRMED REAL:**
   the gauge moves 2745 → 4705 → 7222 m over `G` = 5 → 20 and then jumps to 15 756 m by `G` = 50, so
   the interesting travel is the bottom third of a 1–100 slider. **A ceiling of 20 is the candidate
   to beat**, and P7 must justify whatever it picks against this table.
3. ⚠ **P4's control arms need the same care as its slider.** The bright arms (`rcs_m2` = 64,
   `rcs_fineness` = 4) already sit at +2924 m — three quarters of the bar — because a brighter
   target's detection window grows toward the wire's ends and the censoring starts to bite. The `G`
   ladder is immune by construction (its inbound edge never moves); the CONTROLS are not.

### §2.6 ⚠⚠ A **THIRD** CENSORING EDGE — THE OUTBOUND LOSS WAS A FLICKER SAMPLER, AND §2.3's LADDER
### MAGNITUDES ARE SUPERSEDED BY THE TABLE BELOW (probe `p2d_flicker.jl`, `p2d_out.txt`)

§2.4 found two edges of the flight. There is a third, and it is not an edge of the flight but of the
DETECTOR: `p2b`'s outbound loss is `findlast(detected)`, and under Swerling-1 that is *the last look
that happened to draw above threshold*, not the range where the target became reliably invisible.

**MEASURED, and it is not marginal.** The last five detections on each arm, with the gap in looks to
the previous detection:

| arm | final detection | SNR there | gap to the previous detection |
|---|---|---|---|
| `G` = 50, seed 149 | 27571.9 m | **+0.47 dB** | **181 looks — 18 seconds** |
| `G` = 100, seed 250 | 31060.5 m | +1.38 dB | 117 looks |
| `G` = 100, seed 53 | 32067.8 m | +0.82 dB | 100 looks |
| `G` = 50, seed 53 | 26039.0 m | +1.48 dB | 81 looks |
| `G` = 1, seed 250 | 10228.9 m | +2.86 dB | 36 looks |

⇒ **the headline "+19684 m at `G` = 100" in §2.3 was set by single lucky fades**, and the identical
27571.9 m at `G` = 50 and `G` = 100 on seed 149 — flagged there only as "monotone holds" — was the
tell. ⚠ This is CLAUDE.md's own slice-49/50 line arriving from a new direction: **a gauge must carry
its own window.** A single threshold crossing is not a loss; a track is given up after a RUN.

**THE RULE, and the ladder under it.** Walking outbound, the track is given up at the first detection
whose NEXT detection is more than `N` looks away (or absent) — slice 49's "longest loss run" logic
applied to the edge rather than the interior. The same rule mirrored gives the inbound gain. Mean
asymmetry over seeds 53/149/250, in metres:

| `G` | N = 1 | N = 3 | N = 5 | N = 10 |
|---|---|---|---|---|
| 1 | −3037.7 | −1820.5 | −1279.9 | −659.2 |
| 2 | −3037.7 | −1722.3 | −978.0 | −397.8 |
| 5 | −2937.8 | −1537.3 | −191.8 | +1261.6 |
| 10 | −2937.8 | −583.2 | +1136.5 | +2259.4 |
| 20 | −2676.7 | +329.5 | +3106.0 | +5606.2 |
| 50 | −2242.2 | +4858.0 | +6332.9 | +8312.1 |
| 100 | −128.0 | +5445.2 | +8914.9 | +11543.9 |

⚠ `N` = 1 is the STRICTEST rule (give up at the first detection with any gap after it); the raw
`findlast` of §2.3 is `N` = ∞. Larger `N` is more permissive and declares the loss later.

**WHAT SURVIVES AND WHAT DOES NOT:**

- ✅ **The effect is real and the ladder is MONOTONE under every rule tested**, `N` = 1 through 10.
  The mechanism is not an artefact of the sampler.
- ❌ **The MAGNITUDES in §2.3 are not quotable.** The raw read overstates by roughly 1.7× against
  `N` = 10 (+19684 vs +11544 m at `G` = 100) and the floor moves with the rule too (−511.7 raw,
  −659.2 at `N` = 10, −1279.9 at `N` = 5). **A ladder and its floor must be read under the SAME
  rule**, which is why the table above is the one to carry forward.
- ✅ **The structural fact of §2.3 is UNAFFECTED and remains the strongest thing P2 measured.** The
  inbound leg's SNR values and Swerling draws are bit-identical at every `G`, so *any* rule applied
  to that leg returns the same range. The lobe still moves one leg while the other is nailed down.
- ⚠ **`N` is now a decision P3 must make and justify**, not a number to inherit. The effect's SIZE
  and the floor both scale with it, and picking `N` after seeing the ladder is exactly the thing this
  project's own discipline forbids. Anchor it on something outside this gauge — slice 49's control
  flickered for at most 0.20 s, i.e. **two looks**, which argues for a small `N` (3–5), not 10.

### §2.7 CORRECTION TO §2.3's REFUSAL OF W3

§2.3 refused W3 on three counts. **Count (3) — "the aspect barely sweeps, 7.89° over detected ticks"
— is not an independent reason and must not be read as one.** The detected span is narrow *because*
the lock is lost a second into the flight, which is the very mechanism the lobe would remove; it is
downstream of the wire's behaviour at `G` = 1, not evidence against the wire. **W3 is refused on
counts (1) and (2) alone** — the miss is banned and measured non-monotone here, and its only other
gauge is slice 50's, which this plan pre-registered as the "49 with a sign flip" kill. That is
sufficient, and W3 stays LIVE as the fallback if W1 fails P3.

### §2.8 P3 (F3) — **DISCHARGED. THE NEGATIVE FLOOR WAS THE GAUGE'S OWN DEFINITION, AND THE CEILING
### IS 50** (probe `p3_floor.jl`, `p3_out.txt`; full write-up `p3_findings.md`)

8 seeds (P2's 53/149/250, extended by the stated rule "the first five positive integers"), 200 s,
`revisit_s` = 0.1. **Two decisions were fixed in the probe header BEFORE the run**, because §2.6's
own rule against picking `N` after seeing the ladder applies to every choice the gauge makes:

- **`N`\* = 3**, anchored outside this gauge: slice 49's CONTROL was dark for at most 0.20 s on the
  *identical* `revisit_s` = 0.1 (`docs/STATUS.md`, and the key REMOVED reads the same 0.20 s) ⇒
  0.20 s = 2 missed looks = a gap of 3 ⇒ tolerate gap ≤ 3, give up on gap > 3.
- **The two edges are the SAME FUNCTION**: `gain(inbound, N) := edge(reverse(inbound), N)`.

### ⭐⭐⭐ §2.5 ITEM 1 IS DISSOLVED, NOT CONFIRMED — **A DIFFERENCE OF TWO EDGES IS ONLY A MEASUREMENT IF THE TWO EDGES ARE THE SAME MEASUREMENT**

`p2d`'s pair was never a mirror pair: the outbound rule took the first detection **followed by** a
gap > `N` (the end of the first sustained run), while the inbound rule took the first detection that
**has a successor** within `N` — which accepts an **isolated early pair**. The inbound rule was
strictly the more permissive one ⇒ the gain was declared at longer range ⇒ the difference was biased
**negative by a near-constant offset**. That is the sign *and* the shape §2.5 item 1 flagged
(−3037.7 / −3037.7 / −2937.8 m at `N` = 1 for `G` = 1/2/5 — a fixed offset is a rule bias; Swerling
noise does not do that). The `G` = 1 floor, 8/8 uncensored, metres:

| rule | MIRRORED mean | MIRRORED max\|·\| | `p2d` mean | `p2d` max\|·\| |
|---|---|---|---|---|
| `N` = 1 | −112.0 | 572.2 | −2658.1 | 3478.6 |
| **`N` = 3** ⭐ | **+39.8** | **968.4** | −1595.9 | 2609.0 |
| `N` = 5 | −14.5 | 911.5 | −1140.0 | 1800.8 |
| `N` = 10 | −92.3 | 1151.4 | −594.3 | 1593.1 |

⇒ **the mirrored floor straddles zero at every rule** while the old one is negative by 0.6–2.7 km at
every rule. At `N`\* = 3: mean +39.8 m, sd 609.9, se 215.6, **mean/se = +0.18** — not distinguishable
from zero. **There is no measurement asymmetry to name; §2.5 item 1 is CLOSED.**

### THE LADDER, AND F3's BAR (max\|null\| = 968.4 m ⇒ **BAR = 2905.2 m**)

| `G` | 1 | 2 | 5 | 10 | 20 | **50** | 100 |
|---|---|---|---|---|---|---|---|
| mean (m) | +39.8 | +189.1 | +777.2 | +1465.0 | +2699.0 | **+5531.3** | +6818.5 |
| min over 8 seeds | −657.6 | −657.6 | −531.8 | +371.0 | +1480.6 | +3865.5 | +5192.3 |
| vs BAR | null | 0.07× | 0.27× | 0.50× | **0.93× fail** | **1.90× PASS** | 2.35× PASS |

**MONOTONE at `N` = 1, 3, 5 and 10 AND under both edge definitions — eight monotone ladders out of
eight**, 8/8 uncensored in every cell — and §2.9 confirms it holds on **every individual seed**,
not just the ensemble mean. **F3's MONOTONICITY filter is discharged.** ⚠ F3's filters are named,
never numbered, from here on: the *un-banned* and *monotone* filters are discharged; the
*not-sayable-without-the-asymmetry* filter is P4's substitution test and is OPEN.

### ⚠⚠ THE §0.3 / §2.5-ITEM-2 COLLISION, AND ITS ANSWER — **THE CEILING IS 50**

§2.5 named `G` = 20 "the candidate to beat" and §0.3 pre-registered that the ceiling should come
DOWN rather than the axis going log. **F3's bar is not cleared until `G` = 50; 20 reaches 0.93× and
misses.** ⇒ **20 is beaten and the ceiling is 50.**

⚠⚠ **THE DERIVATION MATTERS AS MUCH AS THE NUMBER, AND F3's BAR IS NOT THE SELECTION RULE.**
§0.3's criterion is *"the last cell that is still MONOTONE in the gauge **and** still a physically
ordinary airframe"* — every cell measured is monotone and §0.1 calls `G` = 100 an ordinary airframe
outright, so §0.3's own rule taken literally returns **100**. F3's bar is a NECESSARY CONDITION at
whatever ceiling is authored, never a way of picking one. The chain P7 inherits is therefore:

1. §0.3's literal criterion ⇒ **100**.
2. §0.3's OWN dB caveat fires, and it is now MEASURED rather than feared: on a 1–100 linear drag the
   top half buys 19 % of the effect ⇒ **the ceiling comes down** (§0.3's stated response).
3. F3's bar FLOORS how far it may come down: below 50 the ladder no longer clears 3 × max-null at
   8 seeds ⇒ **50**, and at 50 the drag is close to the diagonal (39 % of travel, 48 % of effect).

Same number, sourced correctly — and each step is a thing P7 can audit or overturn on its own.

⭐ **AND §0.3's LINEAR-AXIS WORRY IS RE-MEASURED IN THE GAUGE'S OWN UNITS, WHERE IT LARGELY
VANISHES.** §0.3 reasoned in dB; the gauge is in metres. Fraction of the slider's travel vs fraction
of the gauge's range:

| `G` | 5 | 10 | 20 | 50 | 100 |
|---|---|---|---|---|---|
| 1–50 slider: travel / effect | 8 % / 13 % | 18 % / 26 % | 39 % / 48 % | **100 % / 100 %** | — |
| 1–100 slider: travel / effect | 4 % / 11 % | 9 % / 21 % | 19 % / 39 % | 49 % / 81 % | 100 % / 100 % |

⇒ on 1–50 the gauge is close to the diagonal (39 % of the drag buys 48 % of the effect); on 1–100
the top half of the drag buys 19 %. **The ceiling F3's bar forces is also the ceiling that makes the
linear axis honest**, and §0.3's log-curve fallback is not needed. **THE AXIS STAYS LINEAR.**

⚠ A POST-HOC observation, recorded WITH its provenance and NOT substituted for the bar: the null
spread (−657.6 … +968.4) and the `G` = 20 spread (+1480.6 … +3959.7) are **completely disjoint from
`G` = 20 upward**, overlapping at `G` = 10. Defensible — and exactly the statistic this project
forbids choosing after seeing the numbers. It does not move the ceiling.

### ⚠ A DEFECT IN F3's OWN BAR, FOUND BY RUNNING IT — **A THRESHOLD MUST CARRY ITS OWN SAMPLE SIZE**

F3 wrote the bar as `3 × max|null|` and fixed only `N ≥ 8`. **A maximum does not stabilise** — adding
seeds can only raise it, so the bar RISES as the evidence improves and a slice passing at 8 seeds can
fail at 16 with no physics changing. Measured here: max\|null\| swings 572.2 → 1151.4 m across the
four rules on the same 8 seeds, driven by which single seed was worst. ⇒ **always quote the bar with
its seed count**; `G` = 50 clears at 1.90× and has room for the bar to grow, `G` = 20 at 0.93× would
have been decided by one unlucky seed. This is the arc's "a gauge must carry its own window" arriving
one level up.

### THE STRUCTURAL CONTROL HOLDS EXACTLY ON 8 SEEDS, AND A PROPERTY NOBODY ASKED FOR

- **§2.3's strongest fact re-checked over 56 flights:** the inbound gain range is identical at every
  `G` on all 8 seeds (7078.0983 / 6805.9246 / 6243.9596 / 6785.4645 / 7207.3690 / 7250.9401 /
  7630.3031 / 5899.9563 m). The lobe moves one leg while the other is nailed down.
- ⭐ **The run-length rule makes the gauge INDEPENDENT OF FLIGHT LENGTH.** Truncating the same traces
  from 200 s to 160 s reproduces every cell to the last printed digit, 8/8 uncensored at both. The
  raw `findlast` of §2.3 crawled outward with the flight; this does not. P2's shorter-flight table
  stays comparable, and the insensitivity is independent evidence the rule is right.

### WHAT P4–P7 INHERIT

1. **`N`\* = 3 and the mirrored edges are FIXED** — P4–P7 use them verbatim.
2. **The ceiling is 50.** P7's job is now to justify or refute 50 against the bar *at its own seed
   count*, not to pick a number. The floor stays 1.0 (§0.3, non-negotiable).
3. ⚠⚠ **DO NOT CARRY §2.3's OR §2.6's MAGNITUDES INTO P4.** §2.5 item 3's control arms (`rcs_m2` =
   64, `rcs_fineness` = 4, quoted at +2924 m) must be **re-measured under `N`\* = 3 with mirrored
   edges** before being quoted against anything.
4. **P6 (F5) has a specific target:** `G` = 50 carries the headline and `G` = 20 vs 50 is where the
   ceiling rests — both re-fly at `dt` = 5e-4 on the same seeded stream.
5. ❌ F4 (P5, the two nulls) and F2's substitution half (P4) are untouched. §2.2's theorem is about
   σ and **does not reach a number read through a Swerling detector** — the same trap F3
   pre-registered, and P3 has now shown it was worth pre-registering twice.

### §2.9 P3b — **THE LADDER PER SEED. THE SLIDER THE USER DRAGS IS ONE FLIGHT, AND P3 HAD NO
### EVIDENCE ABOUT ONE FLIGHT** (probe `p3b_perseed.jl`, `p3b_out.txt`)

⚠⚠ **WHAT §2.8 DID NOT MEASURE.** Every "monotone" in §2.8 is a statement about the ENSEMBLE MEAN
over 8 seeds. A showcase slider is dragged on ONE seeded flight, and this arc has killed five
sliders on exactly that distinction — `k` (28), `ω_n` (40), `σ_seek` (25), the loss COUNT (49) and
miss-vs-`rcs_fineness` (50). The scatter said the worry was live, not theoretical: at `G` = 5 the
mean is +777.2 m over a −531.8 … +2410.5 m spread, and §2.8's `min` column repeats −657.6 m at
`G` = 1 **and** `G` = 2, i.e. some seed's edge had not moved at all between those cells.

**THE BRANCH WAS PRE-REGISTERED IN THE PROBE HEADER BEFORE THE RUN** (all-monotone ⇒ the ceiling of
50 stands and a one-flight slider is legal; any reversal ⇒ the gauge is an ENSEMBLE gauge, the
showcase becomes a seeded batch under convention 15, **and a monotone seed must not be selected**).
A FLAT cell was declared in advance to be *not* a reversal — the edge is quantised to look indices,
so two adjacent `G` values can legitimately declare the loss at the identical look.

### THE RESULT — **ZERO REVERSALS ON 8 OF 8 SEEDS** (metres, `N`\* = 3, mirrored edges)

| seed | `G`=1 | 2 | 5 | 10 | 20 | 50 | 100 | rev | flat |
|---|---|---|---|---|---|---|---|---|---|
| 53 | −531.8 | −531.8 | −531.8 | +1720.6 | +1819.9 | +6244.0 | +6244.0 | **0** | 3 |
| 149 | +315.7 | +315.7 | +870.7 | +1480.6 | +1480.6 | +6044.4 | +7411.4 | **0** | 2 |
| 250 | +583.1 | +877.6 | +877.6 | +877.6 | +3516.5 | +8114.0 | +8508.7 | **0** | 2 |
| 1 | +444.3 | +665.0 | +665.0 | +2615.9 | +3417.2 | +3865.5 | +5843.9 | **0** | 1 |
| 2 | −441.7 | −255.7 | +446.4 | +446.4 | +2270.5 | +5256.7 | +6170.4 | **0** | 1 |
| 3 | −361.9 | −361.9 | +1131.9 | +1796.9 | +2716.8 | +4095.7 | +6154.7 | **0** | 1 |
| 4 | −657.6 | −657.6 | +347.5 | +371.0 | +3959.7 | +4449.7 | +5192.3 | **0** | 1 |
| 5 | +968.4 | +1461.6 | +2410.5 | +2410.5 | +2410.5 | +6180.1 | +9022.3 | **0** | 2 |

**Total reversals: 0. Largest reversal: 0.0 m.** ⇒ **the pre-registered all-monotone branch fires**:
the ceiling of 50 stands as §2.8 wrote it, and the gate-3 showcase MAY be a single flight with a
live slider. ⭐ This is a much stronger statement than §2.8's — the mechanism survives the filter
that killed five sliders on this arc, **on every individual trajectory**, not on an average.

### ⚠⚠ THE ONE THING GATE 3 MUST DESIGN AROUND — **THE SLIDER HAS DEAD ZONES, AND THEY ARE NOT
### ONLY AT THE BOTTOM**

13 of the 48 intervals are FLAT. Counted per interval across the 8 seeds:

| interval | 1→2 | 2→5 | 5→10 | 10→20 | **20→50** | 50→100 |
|---|---|---|---|---|---|---|
| seeds flat | 4 | 3 | 3 | 2 | **0** | 1 |

⚠ **The ONLY interval clean on all eight seeds is `G` = 20 → 50.** Flats are commonest at the bottom
(seed 53 does not move at all from `G` = 1 to 5) but they reach 10 → 20 on two seeds — which straddles
the region §2.8 reasons about — and even 50 → 100 on seed 53 (+6244.0 twice). **This is a stronger
constraint than "the first inch of the drag is dead", not a weaker one.**

The cause is the edge's quantisation to a look index, not a physics failure: two adjacent `G` values
can legitimately declare the loss at the identical look. But on a LIVE slider it means **a user
dragging one flight can see nothing move over a whole interval, anywhere below `G` = 20 and
occasionally above it.**

⇒ gate 3 must not let a flat stretch read as "the knob is dead" (49's `.get(k, 0.0)` family of
traps one level up: here the number is REAL and simply has not changed yet). Either the view shows
the batch, or the authored default sits inside 20 → 50, or the readout says *how many looks* the edge
moved rather than only metres. **Decided at gate 3, recorded here.**

### HOW BIG A BATCH, IF ONE IS EVER WANTED (estimated from n = 8, quoted as such)

| `G` | 1 | 2 | 5 | 10 | 20 | 50 | 100 |
|---|---|---|---|---|---|---|---|
| sd (m) | 609.9 | 762.9 | 830.9 | 842.9 | 870.0 | 1411.3 | 1354.9 |
| se at n = 8 (m) | 215.6 | 269.7 | 293.8 | 298.0 | 307.6 | 499.0 | 479.0 |
| seeds for the BATCH MEAN's se ≤ mean/3 | 2112 | 147 | 11 | 3 | 2 | 2 | 2 |

⚠⚠ **THE LAST ROW IS FLOORED AT 2 AND MEANS ONLY WHAT IT SAYS.** The raw `(3·sd/mean)²` returns 1
at `G` ≥ 20, which is the formula running below its own domain — **a single flight has no standard
error at all.** The row is about how many seeds a BATCH MEAN needs, nothing else. In particular it
is NOT a licence to quote a headline from one flight: one flight at `G` = 20 is a single draw from a
distribution with sd 870 m, and the table above shows that draw ranging +1480.6 … +3959.7 m across
the eight seeds. **What licenses a one-flight showcase is the PER-SEED MONOTONICITY above — zero
reversals on 8 of 8 — and nothing in this table.**

⭐ The genuine finding here is that **the scatter does not grow with the effect**: sd goes 610 → 870 m
from `G` = 1 to 20 while the mean goes +40 → +2699 m. The lobe moves the mean without widening the
distribution, which is why the per-seed ladders come out clean.

### ⚠ ONE ADDITION TO WHAT P4 MUST RUN (advisor, after P3b)

§2.8 point 3 already requires §2.5 item 3's control arms (`rcs_m2` = 64, `rcs_fineness` = 4) to be
**re-measured under `N`\* = 3 with mirrored edges** before being quoted. Add to that: **run the
controls through the SAME per-seed reversal check P3b just ran**, on the same 8 seeds and the same
rule, in the same probe. F2's substitution test needs the controls to FAIL to reproduce the
asymmetry — and *a control that produces a non-monotone or seed-dependent asymmetry is a different
and WEAKER refutation than one that produces none.* The distinction has to be measured, not assumed.

---

### §2.10 P4 (F2/F3) — **THE SUBSTITUTION TEST. BRANCH (S) FIRED: NEITHER SHIPPED KNOB PRODUCES
### AN ASYMMETRY AT ALL** (probe `p4_subst.jl`, `p4_out.txt`)

P4 pre-registered its verdict branches in its own file header, before the run: **(S)** every
control arm indistinguishable from zero ⇒ strong refutation; **(D)** a control reproduces the
ladder ⇒ the slice dies; **(W)** a control produces a non-monotone or seed-dependent asymmetry ⇒
weak refutation (the distinction §2.9's closing note demanded). It flew TWO wires, each its own
stream, nothing compared across them: **wire A** = P3/P3b's wire verbatim (x0 = −15 km, 200 s),
**wire B** = a wide wire (x0 = −60 km, 420 s) sized so even the brightest arm opens undetected.

**The correctness tooth first.** P4's null arm reproduced P3's `G` = 1 cell to the printed digit —
mean +39.8 m, max |·| 968.4 m, 8/8 uncensored. The gauge in this probe **is** P3's gauge.

**⭐ BRANCH (S) FIRED ON BOTH WIRES.** No control arm clears even 3 standard errors of its own
seeds, let alone the bar:

| wire | knob swept | means in knob order (m) | largest \|mean\|/se |
|---|---|---|---|
| A | `rcs_m2` 4 → 64 (F = 8) | +40 → −184 → −212 → −110 → +615 | 1.56 |
| A | `rcs_fineness` 2 → 12 (σ = 4) | +1278 → +638 → +40 → −128 | 2.87 |
| B | `rcs_m2` 4 → 1024 (F = 8) | +191 → +127 → −50 → −777 → −786 | 1.35 |
| B | `rcs_fineness` 2 → 12 (σ = 4) | −548 → −50 → +191 → +115 | 0.85 |

⇒ **F2's substitution half is DISCHARGED, and F3's third filter — *not sayable without the
asymmetry* — with it.** Per-seed reversal counts were printed for completeness and are **NOT a
finding**: a reversal count on a flat-noise arm is uninformative by construction, which P4's header
said before the run.

**⚠ §2.5 ITEM 3's WARNING IS NOW DEAD, AND ITS NUMBER WITH IT.** The old **+2924 m** control-arm
figure was an artefact of the raw-`findlast`, unmirrored rule. Re-measured under `N`\* = 3 with
mirrored edges, `rcs_m2` = 64 gives **+615.3 m** (\|m\|/se 1.44) and `rcs_fineness` = 4 gives
**+637.7 m** (1.59). **Do not quote +2924 m again.**

**⭐ THE MECHANISM-LEVEL REFUTATION — a brightness knob moves BOTH edges, the tail gain moves ONE**
(wire B, means over 8 seeds):

| arm | gain-in (m) | loss-out (m) | asymmetry (m) |
|---|---|---|---|
| `rcs_m2` = 4 (null) | 6681.8 | 6872.9 | +191.2 |
| `rcs_m2` = 64 | 10065.7 | 10015.7 | −50.0 |
| `rcs_m2` = 1024 | 16877.4 | 16091.6 | −785.8 |
| **`G` = 20** | **6681.8** | **10015.7** | **+3334.0** |
| **`G` = 50** | **6681.8** | **11565.4** | **+4883.6** |

⚠ **Read the `gain-in` column.** Brightness drags the inbound edge outward *with* the loss edge;
the tail gain leaves it exactly where the null put it. This is §2.3's structural control holding on
a second, independent wire — and it is the mechanism P4b then turns into an estimator (§2.11).

### ⭐⭐ §2.10a THE TWO SHIPPED KNOBS COLLAPSE TOWARD **ONE** KNOB AT THE POLES — ⚠ **AN EXACT
### IDENTITY AT cos²θ = 1, AN APPROXIMATION AT THE ANGLES THE EDGES ACTUALLY SIT AT**

Found empirically in P4's sizing run, then derived: `rcs_aspect` reads σ / (sin²θ + F² cos²θ)², so
at nose-on and tail-on (cos²θ = 1) it is **exactly σ / F⁴**. `rcs_m2` = 64 / `rcs_fineness` = 8 and
`rcs_m2` = 4 / `rcs_fineness` = 4 both give 0.015625 there; 1024/8 and 4/2 both give 0.25.

**⚠⚠ BUT THE IDENTITY IS EXACT ONLY AT THE POLE, AND THIS GAUGE'S EDGES ARE NEAR IT, NOT AT IT.**
With the target at 5 km and the radar at 30 m, the outbound edge at ~10 km sits ~30° off tail-on
(cos²θ ≈ 0.75) and at ~16.6 km still ~17° off (cos²θ ≈ 0.92). The residual grows with how far apart
the two `F` values are, and **P4's own arms measure it**:

| σ/F pair | ratio of `F` | gain-in (m) | loss-out (m) | verdict |
|---|---|---|---|---|
| 64/8 vs 4/4 | 2 | 10065.7 vs 10065.7 | 10015.7 vs 10015.7 | **bit-identical in every column** |
| 1024/8 vs 4/2 | 4 | **16877.4 vs 16639.3** | 16091.6 vs 16091.6 | ⚠ **238.1 m apart INBOUND** |

238.1 m *is* the whole difference between those two arms' means (−785.8 vs −547.7), and §2.10's own
off-axis print names the cause: at 30° they read 0.44 vs 0.379, **14 % apart**.

⇒ F2's words — *one aspect is one number, and one number is a gain* — hold **in the limit**, and
§2.2's theorem arrives from the parameter side. ⚠ **The rule a later probe may use is the narrow
one:** σ/F⁴ is an exact identity at nose-on and tail-on; at the angles this gauge's edges sit at the
two keys are interchangeable only when the `F` values are **close** — measured, 64/8 ≡ 4/4 exactly,
while 1024/8 vs 4/2 differ by 238 m. **Never substitute across a large `F` ratio and call it a null.**

⚠ None of this touches branch (S): that verdict rests on the control means being indistinguishable
from zero on their own seeds, not on the degeneracy.

### §2.11 P4b — **THE PAIRED TEST. F3's BAR STANDS AS §2.8 WROTE IT; P4 §E's RETRACTION IS NOT
### ISSUED** (probe `p4b_paired.jl`, `p4b_out.txt`)

**⚠⚠ P4 §E MUST NOT BE QUOTED.** P4's branch (R) asked whether F3's bar was measured at the range
the headline is read at, built a floor from the two control arms *bracketing* `G` = 50's outbound
edge (FLOOR_R = 3049.6 m ⇒ BAR_R = 9148.7 m), scored `G` = 50 at **0.53× — FAIL**, and wrote that
§2.8's 1.90× PASS was "RETRACTED, not reinterpreted". **That retraction is hereby NOT issued.** The
bracketing construction is the **wrong estimator**, and it is wrong for a reason this file can state
mechanically rather than by preference:

> A control arm's asymmetry contains **two** stochastic edges at two different ranges. `G` = 50's
> asymmetry contains only **one**, because its inbound edge is bit-identical to the null's. Pricing
> the second against the first charges the tail gain for a variance term its own gauge does not
> contain.

⚠ **This is a supersession on a stated mechanism, not a number discarded for being unwelcome.** The
concern was named in-session *before* wire B's bracketing numbers existed, and P4b's §0 **checks the
mechanism rather than assuming it**: max \|in_G − in_1\| over 8 seeds is **0.000000e+00** on both
wires at both `G` = 20 and `G` = 50. Bit-identical. The cancellation is exact.

**⭐⭐⭐ THE PAIRED TEST. Δ(`G`, seed) = out_G(seed) − out_1(seed), whose null is EXACTLY zero by
construction** — no floor to build, no bar to clear, no null arm to fly. The test is P3b's own
filter: positive on 8 of 8?

| wire | `G` | mean Δ (m) | sd (m) | se (m) | mean/se | seeds positive |
|---|---|---|---|---|---|---|
| A | 20 | **+2659.1** | 1068.7 | 377.8 | 7.04 | **8/8** |
| A | 50 | **+5491.4** | 1281.1 | 452.9 | 12.12 | **8/8** |
| B | 20 | **+3142.8** | 1023.3 | 361.8 | 8.69 | **8/8** |
| B | 50 | **+4692.4** | 1309.3 | 462.9 | 10.14 | **8/8** |

**BOTH FLOORS, REPORTED TOGETHER** (the ledger carries both so the supersession is auditable):

| | wire A | wire B |
|---|---|---|
| (i) F3's bar as WRITTEN, same-wire null | 3 × 968.4 = 2905.2 m ⇒ `G` = 50 at **1.90× PASS** | 3 × 1044.6 = 3133.7 m ⇒ `G` = 50 at **1.56× PASS** |
| (ii) P4 §E's bracketing-arm floor | — | **SUPERSEDED** (mechanism above) |
| (iii) ⭐ the paired test, no floor needed | +5491.4 m, se 452.9, 8/8 | +4692.4 m, se 462.9, 8/8 |

⇒ **F3 IS FULLY DISCHARGED. The ceiling of 50 stands as §2.8 and §2.9 wrote it, and P7 inherits no
correction from P4 §E.**

### ⭐⭐ THE SCATTER IS A PROPERTY OF THE **RANGE**, NOT OF THE ARM

P4 reported one sd per arm, conflating two edges sitting at two different ranges. P4b measures each
edge separately. Sorted by the range the edge sits at, per-edge sd climbs monotonically — ~175 m at
5.8 km, ~430–560 m at 6.7–6.9 km, ~750 m at 10 km, ~1100–1360 m at 11.8–12.6 km, ~1200–2400 m at
16–16.9 km — **regardless of which knob put the edge there**. On every control arm (whose two edges
sit at matched range) `arm sd ÷ √2` tracks each edge's own sd, so the two edges are independent and
equally noisy at matched range. P4's pre-registered prediction for `G` = 50 (~1257 m) against the
measured 1215 m was right for the right reason.

⇒ ⚠ **A NOISE FLOOR ON THIS GAUGE MUST BE QUOTED WITH THE RANGE ITS EDGES SIT AT** — a general
statement that outlives P4 §E's specific error, and the real content of branch (R).

### ⚠ THE MONOTONE DRIFT IS AN OPEN ITEM, NOT A FINDING — AND IT CANNOT TOUCH Δ

Two of P4's four control sweeps drift monotonically negative with brightness (wire A's `F` sweep,
wire B's σ sweep). No arm clears 3 se, so **branch (S) is not reopened** — that verdict was
pre-registered. P4b §3 asks a different question with a diagnostic that needs no threshold model:
**the SNR at the look each edge is declared on**. Two mirrored samplers on a geometrically symmetric
pass should declare at the same signal level. Measured, `out − in` spans only **−1.5 … +1.4 dB** and
**its sign is not consistent** — the same arms flip sign between wires (`F` = 12: +1.35 dB on A,
−1.17 dB on B). ⇒ **the drift is not a sampler bias**; it is the detector's own R⁻⁴ geometry.

⚠⚠ And in any case: **a bias on the INBOUND edge cannot touch Δ**, because Δ cancels the inbound
edge exactly, per seed. Recorded as an open observation for P7, **not** as a finding.

### WHAT P5–P7 INHERIT FROM P4/P4b

1. **F1 and F2 are DISCHARGED, and so are all THREE of F3's filters.** ⚠ **F3 itself is NOT closed:
   its ENDPOINT JUSTIFICATION is P7's job.** Remaining: **F4** (P5, the two nulls, byte-identity),
   **F5** (P6, halved step), **F3's endpoints** (P7).
2. **P7's ceiling work starts from 50 UNCHANGED.** P4 §E's demand that "the ceiling must rise" is
   withdrawn with §E itself.
3. ⚠ **P7 may substitute `rcs_m2` for `rcs_fineness` only across a SMALL `F` ratio** — the σ/F⁴
   identity is exact at the poles but the gauge's edges sit ~17–30° off them (§2.10a).
4. ⚠ **P6 halves the step at `G` = 50 AND at the `G` = 20 vs 50 comparison**, since 20 → 50 is the
   only interval clean on all eight seeds (§2.9) and is therefore what a gate-3 default sits inside.

---

### §2.12 P5 (F4) — **ALL THREE NULLS ARE EXACT. THE KERNEL NEEDS NO EXTRA BRANCH** (probe
### `p5_nulls.jl`, `p5_out.txt`)

**⚠ F4 NAMES TWO NULLS; THERE ARE THREE.** P5's header pre-registered them before the run:

| | what it compares | why it exists |
|---|---|---|
| **N1** the LESSON null | `rcs_tail_gain: 1.0` authored **vs** the key ABSENT, both with a fineness | F4 as written |
| **N2** the WIRE null | the patched core on a slices-1–48 wire (no `rcs_fineness`) must return the **authored object** — `===`, not `==` | F4 as written |
| **N3** the BASELINE null | the patched core, key absent, **vs the UNPATCHED core** | ⭐ **not in F4.** N1 and N2 can both pass while the kernel still perturbs a shipped wire, because N1 compares two *patched* runs to each other |

N3 was captured **before the patch was applied at all**, which is the only ordering that makes it a
baseline rather than a second opinion.

**⭐ BRANCH (A) FIRED — the pre-registered strongest outcome.** All 24 rows printed exact in all
three columns: `max|Δpos|` = **0.000000000e+00**, telemetry fields differing by `===` = **0**, and
post-flight RNG stream position = **0** differences.

**⚠⚠ BUT DO NOT QUOTE "24 OF 24" — ONLY N3's 8 ROWS ARE EVIDENCE.** Under the shape that actually
ships (the unconditional multiply), **N1 and N2 cannot fail**, and P5's own §4 finding is what
proves it:

- **N1 is structurally guaranteed.** `load_scenario` normalises the authored value to Float64, so
  `rcs_tail_gain: 1.0` gives `G` = 1.0 — and the key being *absent* gives `G` = 1.0 too, from
  `get(…, 1.0)`'s default. Identical `G` ⇒ identical arithmetic for the whole rest of the function.
  ⚠ N1 **would** have had content under branch (B), where absent SKIPS the multiply and `1.0`
  performs it: **N1 is the test that discriminates (A) from (B), and once (A) is chosen it becomes a
  tautology.** That is what it was for; it is not independent evidence of exactness.
- **N2 is the same one line earlier** — both sides execute the textually identical
  `haskey(tgt.comp, :rcs_fineness) || return tgt.comp[:rcs_m2]` and nothing else runs. It confirms
  the edit did not disturb that line. A check on the probe's own patch text, not a measurement.

⇒ ⭐ **N3 ALONE CARRIES F4** — the only pair where genuinely different code executes (no multiply vs
multiply-by-1.0), **exact on 8 of 8 seeds in all three columns**. Together with §1's 40 376-point
grid and its 684/2884 control, that is a sound discharge.

⚠ **The RNG column is not decoration.** Convention 3's hazard is a draw-COUNT regression, and an
identical trajectory does not prove an identical draw count. P5 draws 8 numbers from `w.rng` *after*
the flight and compares them; equal draws mean the stream sat at the same position.

⚠ **WHAT "IDENTICAL TELEMETRY" ACTUALLY COVERS HERE**, stated narrowly because F4's phrase is wider
than the comparison: the full per-tick position trace (200 000 ticks), **five named** telemetry
fields at every look, and the post-flight RNG stream position. It does **not** cover a key that
stopped emitting — `telget` defaults to `NaN`, and in Julia `NaN === NaN` is **true**, so a vanished
key reads as identical. (`CLAUDE.md`'s documented `.get(k, 0.0)` trap, with `NaN` as the default.)
That gap cannot reach this result — the patch changes a returned float and provably cannot alter the
key set, and N3's position trace and RNG check are independent of telemetry entirely — but a later
probe reusing `bitcmp` must know it is there.

⇒ **F4 IS DISCHARGED, and the kernel ships as an UNCONDITIONAL MULTIPLY** — no early return on
`rcs_tail_gain` being absent. §0.4's seam gains no branch.

### ⭐⭐ WHY THE MULTIPLY IS EXACT WHERE `F` = 1 WAS NOT — MEASURED, WITH ITS OWN CONTROL

`_effective_rcs`'s docstring already forbids routing a scalar wire through `rcs_aspect` with
`F` = 1, because `sin²θ + cos²θ` is 1 in algebra and **not always 1.0 in floating point**. The
obvious worry is that `1 + (G−1)·u` at `G` = 1 is the same kind of trap. It is not, and P5 measured
rather than asserted it:

| test | combinations | NOT bit-identical |
|---|---|---|
| `rcs_aspect(σ,F,θ) · (1 + (1−1)·u)` **vs** `rcs_aspect(σ,F,θ)` | 40 376 | **0** |
| ⚠ the CONTROL — `σ / (sin²θ + 1²cos²θ)²` **vs** `σ` | 2 884 | **684** |

⇒ ⭐ **The control reproduces the docstring's trap at a 24 % failure rate, so §1's clean pass is
ATTRIBUTABLE and not the artefact of a weak test.** The arithmetic reason is narrow and worth
keeping: `(1.0−1.0)·u` is `+0.0` for every finite `u ≥ 0`, `1.0 + 0.0` is `1.0`, and `x · 1.0 === x`
for every finite `x`. **A multiply by an exactly-representable 1.0 is the identity; a trigonometric
sum is not.** ⚠ This licenses the multiply *only* at `G` = 1 — it says nothing about any other
value, and nothing about an additive kernel (which §0.2 already rejected on other grounds).

### ⚠⚠ A TOOTH OF P5's OWN THAT TURNED OUT **VACUOUS** — RECORDED AS FAILED, NOT AS PASSED

P5 built a type tooth for N2: author `rcs_m2: 4` as an **integer**, on the theory that the early
return hands back the `Int` itself, so any conversion would flip the type and `===` would catch it.
It printed a pass. **It is not a pass — it is a tautology** (convention 11's exact ban):

> `_effective_rcs` on an authored `rcs_m2: 4` returned **4.0 (Float64)**.

`load_scenario` **normalises the authored value to Float64 at load**, so `tgt.comp[:rcs_m2]` is
already a Float64 before `_effective_rcs` ever sees it. The tooth never presented a non-Float64
value and therefore could not have failed. ⇒ ⚠ **`===` on this path can never catch a conversion**,
because on a Float64 it is bit-equality and nothing more. What actually protects the scalar wire is
N3 — the unpatched-vs-patched comparison — and the fact that the early-return LINE is untouched.
**Do not quote P5's type tooth as evidence of anything.**

### ⚠⚠ A REQUIREMENT ON GATE 1 THAT F4 DOES NOT ASK FOR — **`rcs_tail_gain` WITHOUT
### `rcs_fineness` IS A DEAD KNOB**

Asked in P5's header **before** it was measured, so the answer could not be chosen after seeing it.
Measured: `rcs_tail_gain: 50` authored on a scalar wire, against no key at all, gives `max|Δpos|`
0.000e+00, 0 telemetry differences, 0 RNG differences. **`G` = 50 changes literally nothing.**

**⚠⚠ P5 ATTRIBUTED THAT TO THE WRONG CAUSE, AND §2.13a CORRECTS IT.** P5 wrote *"the early return on
`rcs_fineness` fires first, so the tail gain is read by nothing"*. **That is not what happened.**
P6a proved `load_scenario` **silently DROPS an unknown `target:` key** — `rcs_tail_gain` never
reaches `entity.comp` at all, so the early return never got the chance to shadow it. **P5 §4
measured the LOADER, not the seam.** The correct statement, and the properly-asked measurement, are
in §2.13a; the CONCLUSION survives but the obligation on gate 1 is **larger** than P5 said.

### WHAT P6/P7 INHERIT FROM P5

1. **F4 is DISCHARGED.** Remaining: **F5** (P6, the halved step) and **F3's endpoints** (P7).
2. **The shipped shape is the unconditional multiply** — P6 and P7 must patch *that* shape, which
   is what every probe from P3 onward has already been flying.
3. ⚠ **P6 and P7 may not use `===` on a Float64 as a conversion tooth** (the vacuous-tooth note
   above); a byte-identity claim needs the unpatched-vs-patched comparison N3 uses.
4. ⚠⚠ **THE LESSON P5 KEEPS TEACHING ITSELF: a comparison whose two arms execute the SAME code is
   not a measurement.** It caught P5 three times — the type tooth (the loader normalises), N1 (the
   `get` default equals the authored null), and N2 (one shared early-return line). **Before quoting
   any null as evidence, name the line that differs between its two arms.** If none does, it is a
   check on the probe, not on the physics.

---

### §2.13 P6 (F5) — **THE PROBE FIRED ITS OWN "NO TEETH" BRANCH. F5 AS WRITTEN IS UNANSWERABLE ON
### THIS GAUGE** (probe `p6_halfstep.jl`, `p6_out.txt`)

P6 pre-registered four branches, including **(T)**: *zero detection flips ⇒ the run is a TAUTOLOGY,
it does NOT discharge F5.* That branch fired, and §2.12's closing rule is why it existed at all —
*a comparison whose two arms execute the same code is not a measurement; name the line that differs.*

Halving `dt` from 1e-3 to 5e-4 moved the range at a matched look by at most **0.413 m** and the SNR
by at most **0.00629 dB**, and flipped **0 detection bits in 48 000 looks**. Every edge was therefore
identical by construction. **P6's numbers are a re-print, not a re-measurement.**

⭐ **THE DIAGNOSIS, AND IT IS THE USEFUL PART.** The radar looks on `revisit_s`, **not** on `dt`, and
the edge is quantised to a LOOK INDEX. Halving `dt` does not add looks, does not add RNG draws, and
does not change which draw lands on which look. ⇒ **this gauge is not `dt`-quantised at all**, so
F5's knob is the wrong one. P3b had already measured the real quantum from the other side: 13 of 48
ladder intervals are FLAT because two adjacent `G` values declare the loss on the identical look.

### ⚠⚠ §2.13a P6a — **`load_scenario` SILENTLY DROPS AN UNKNOWN `target:` KEY** (probe
### `p6a_keycheck.jl`, `p6a_out.txt`) — AND IT CORRECTS P5 §4

P6's first run printed **identical edges for `G` = 1, 20 and 50**, which is impossible if the key is
read. Cause: P6 **authored** `rcs_tail_gain` in the YAML; P3/P3b/P4/P4b all **injected** it into
`entity.comp` after load. Measured directly — authored `rcs_tail_gain: 50` with or without a
fineness, the entity's component keys come back as `intensity, rcs_fineness, rcs_m2`:
**`haskey(:rcs_tail_gain)` is `false` every time.**

**⚠ NOTHING IN P3–P4b IS AFFECTED — THEY INJECTED.** P6's re-run with injection reproduces P3 §2.8's
ladder means **to the printed digit** (`G` = 1 → +39.8, `G` = 20 → +2699.0, `G` = 50 → +5531.3), which
is the tooth that makes this a probe-harness fact rather than a contamination of the ledger.

**⚠⚠ BUT IT CORRECTS P5 §4's CAUSE.** P5 authored the key in YAML too, saw zero bits change, and
blamed the `rcs_fineness` early return. The key never reached the entity, so the early return never
shadowed anything. **P5 §4 measured the loader.** Asked properly — inject, do not author, and read
`σ_eff` at a tail-on observer:

| wire | `G` absent | `G` = 50 injected | verdict |
|---|---|---|---|
| WITH `rcs_fineness` | 0.000976562 | **0.0488281** | LIVE — read, and exactly 50× |
| NO `rcs_fineness` (scalar) | 4 | 4 | ⚠ **DEAD — the early return does shadow it** |

⇒ **P5 §4's CONCLUSION SURVIVES; ITS CAUSE WAS WRONG; AND THE GATE-1 OBLIGATION IS BIGGER.** There
are now **TWO** defects stacked, and P5 could only see the outer one:

1. ⭐ **The loader must LEARN the key.** A key that is authored, accepted silently and then thrown
   away is worse than one shadowed downstream — there is no consumer to clamp at (convention 5)
   because there is no value anywhere.
2. **And then reject `rcs_tail_gain` without `rcs_fineness` at LOAD**, which is the obligation P5
   stated. Fixing only (1) turns a silently-ignored key into a silently-shadowed one.

⚠ **A HARNESS TRAP FOR EVERY LATER PROBE AND FOR GATE 1's OWN TESTS:** *authoring a not-yet-shipped
key in a scenario YAML flies a NULL, silently.* Inject until gate 1 teaches the loader. This is the
`.get(k, 0.0)` family one level up — the wire accepts the key and the run looks legitimate.

### §2.14 P6b (F5, redesigned) — **THE EFFECT IS NOT AN ARTEFACT OF THE GRID, BUT ITS SIZE IS NOT A
### PROPERTY OF THE TARGET** (probe `p6b_teeth.jl`, `p6b_out.txt`)

Two arms, **two bars, deliberately not in one table**, both pre-registered:

- **ARM 1 — COARSENED `dt`, PAIRED.** `revisit_s` untouched ⇒ look times, look count and the RNG
  draw sequence are all preserved, so the same draws land on a perturbed geometry. That is F5's
  "same seeded stream" exactly. ⚠ Its stated limit, written before the run: coarsening `dt` changes
  the **integrator's own error**, not only the sample instants, so a PASS here is strong evidence
  while a FAIL would be ambiguous and could not kill anything alone.
- **ARM 2 — HALVED `revisit_s`, DISTRIBUTIONAL.** ⚠⚠ The look count changes ⇒ the draw sequence
  changes ⇒ **this is a different realisation and CANNOT be a paired comparison.** Saying so is the
  point: weaker per seed, stronger in what it tests.

**⭐ ARM 1 — (P1), A CLEAN PASS *WITH TEETH*.**

| `dt` | det. flips | max \|ΔR\| | max \|ΔSNR\| | Δ shift vs 1e-3, `G` = 20 / 50 |
|---|---|---|---|---|
| 1e-3 | (baseline) | — | — | — |
| 2e-3 | **1** | 0.89 m | 0.0039 dB | +0.4 / +0.8 m |
| 4e-3 | **1** | 2.09 m | 0.0252 dB | −0.3 / −0.4 m |
| 1e-2 | **7** | 5.67 m | 0.0755 dB | −1.5 / −1.3 m |

8-of-8 positivity survives at every step, with the paired mean moving **at most 1.5 m against a
standard error of 378–453 m — 0.00 se.**

**⚠⚠ BUT P6c SHOWS THIS PASS IS WEAKER THAN THE TABLE LOOKS** (probe `p6c_fliploc.jl`,
`p6c_out.txt`). The flip counts invite a claim the flips do not support: **1 flip** at `dt` = 2e-3
and **1** at 4e-3, across 24 flights and 48 000 looks, is barely distinguishable from P6's zero. So
P6c asked, against pre-registered branches, **where the flips sit** — a bit flipped in the middle of
a solidly-detected run changes no edge at all. Distance in looks from each flip to that flight's own
declared edge, with the rule reading `N`\* = 3:

| `dt` | flips | **within `N`\* = 3 of a declared edge** | nearest flip |
|---|---|---|---|
| 2e-3 | 1 | **0** | 120 looks |
| 4e-3 | 1 | **0** | 120 looks |
| 1e-2 | 7 | **0** | 51 looks |

⇒ ⚠ **BRANCH (b): every flip landed far from both edges, so not one of them reached the
edge-declaration logic.** The declared edge **look index never changed** in any flight; what moved
was the *range recorded at that unchanged look*, by **0.7–4.0 m**, which is simply the slightly
different trajectory. **So ARM 1 demonstrates that the range READOUT is insensitive to `dt` — it
does NOT demonstrate that the edge-declaration RULE absorbs a perturbed detection sequence**, because
the sequence was never perturbed anywhere the rule looks. Do not write "a tenfold coarsening does not
move this gauge": the supportable claim is that **at every step tested, the edge look index was
identical and the recorded range moved by single metres.**

⇒ **F5's substantive discharge rests on ARM 2. ARM 1 is corroboration, and weak corroboration at
that** — its own honest reading is P6's branch (T) in a milder form.

**⚠ ARM 2 — 8-OF-8 SURVIVES EVERYWHERE, SO THE LETHAL BRANCH (W) DID NOT FIRE — BUT THE MAGNITUDE
MOVES BY UP TO 5.8 se, WHICH IS THIS ARM'S OWN "STATED SENSITIVITY, NOT A CLEAN PASS".**

| `revisit_s` | `N`\* | `G` | mean Δ (m) | shift vs base | shift/se | 8/8? |
|---|---|---|---|---|---|---|
| 0.100 | 3 | 20 | +2659.1 | — | — | ⭐ 8/8 |
| 0.100 | 3 | 50 | +5491.4 | — | — | ⭐ 8/8 |
| 0.050 | 3 | 20 | +2809.3 | +150.2 | 0.40 | ⭐ 8/8 |
| 0.050 | 3 | 50 | **+3955.8** | **−1535.7** | 3.39 | ⭐ 8/8 |
| 0.050 | 6 | 20 | **+4850.3** | **+2191.1** | 5.80 | ⭐ 8/8 |
| 0.050 | 6 | 50 | **+7076.5** | +1585.1 | 3.50 | ⭐ 8/8 |

⇒ **F5's LETHAL QUESTION IS ANSWERED: the asymmetry is NOT an artefact of the look quantum.**

⚠⚠ **AND THE ARGUMENT FOR THAT IS NOT THE OBVIOUS ONE.** The tempting reading — *refining the grid
makes the effect LARGER, which is the opposite of what an artefact does* — **is wrong and must not be
written.** At matched blindness time a finer grid gives more re-detection chances inside the same
window, so the track is held further out: that is **a tracker gaining sensitivity**, and a genuine
look-grid artefact would produce the very same sign. The growth direction is a red herring.

**What actually rules the artefact out is the SIGN's invariance:** 8-of-8 positivity survives at
**every** configuration — including the stricter one (`revisit_s` = 0.05, `N`\* = 3) where the
magnitude *fell* by 3.4 se. **The effect changes SIZE under every reparameterisation of the tracker
and never changes SIGN.** An artefact of the quantum would not survive halving the quantum on all
eight seeds in both directions of magnitude change.

### ⭐⭐⭐ WHAT ARM 2 ACTUALLY FOUND — **THE METRES ARE A PROPERTY OF THE TRACKER, NOT OF THE TARGET**

The `N`\* = 3 confound this probe raised itself is what makes the table readable, and it had to be
run both ways or the two causes would be inseparable: **`N`\* is counted in LOOKS, so refining the
grid silently TIGHTENS the rule in time** (3 looks = 0.3 s at `revisit_s` = 0.1, but only 0.15 s at
0.05). Read the two rows for `G` = 50 against each other:

- **same LOOKS (`N`\* = 3), i.e. a stricter give-up time** ⇒ the track is abandoned sooner ⇒ Δ **falls**
  to +3955.8.
- **same TIME (`N`\* = 6)** ⇒ twice as many chances to re-detect inside the same 0.3 s of blindness ⇒
  the track is held further out ⇒ Δ **rises** to +7076.5.

⇒ ⭐⭐⭐ **THE SIGN AND THE 8-OF-8 MONOTONICITY ARE PHYSICS; THE METRES ARE A JOINT PROPERTY OF THE
TAIL LOBE AND THE TRACKER'S OWN PARAMETERS** (`revisit_s` and the give-up rule). A faster-revisiting
radar follows a tail-lobed target substantially further home at matched blindness tolerance —
**+2191 m at `G` = 20, on the same physics.** That is a real and teachable statement, and it is the
same family as slice 52's *a faster sweep needs a WIDER one*.

⚠⚠ **THE CONSEQUENCE FOR GATE 3, AND IT IS BINDING:** the headline metres **must never be presented
as a property of the target.** Any quoted figure carries its `revisit_s` and its `N`\* or it is not
a measurement — the same discipline as *a gauge must carry its own window* (slice 49) and *a
threshold must carry its own sample size* (§2.8). The **direction** is what the lesson teaches.

### WHAT P7 INHERITS FROM P6/P6a/P6b

1. **F5 IS DISCHARGED, BY ARM 2 — NOT BY ARM 1.** ⚠ ARM 1's flips all landed 51+ looks from any
   edge (P6c), so it shows the range readout is `dt`-insensitive and nothing stronger. ARM 2 answers
   the lethal question: the effect is not a grid artefact, because its SIGN survives every retuning
   of the tracker while its SIZE does not. ⚠ **ARM 2's magnitude sensitivity is a STATED SENSITIVITY
   that travels with the headline**, not a clean pass, per its own pre-registered bar.
   Remaining: **F3's endpoints (P7)**.
2. ⚠⚠ **INJECT `rcs_tail_gain`, NEVER AUTHOR IT**, until gate 1 teaches the loader (§2.13a).
3. ⚠ **P7 must quote `revisit_s` = 0.1 and `N`\* = 3 beside every number it reports**, since the
   ceiling of 50 was measured under exactly that pair and Arm 2 shows the pair matters.
4. ⭐ **The `N`\*-in-looks-vs-seconds confound is a general trap**, not a slice-53 detail: a rule
   counted in samples silently changes meaning when the sample rate changes. It belongs in
   `docs/LESSONS.md` when this slice completes.

---

### 2.15 — P7 (F3): THE TWO ENDPOINTS OF THE SLIDER — **CEILING 50, LINEAR, DEFAULT 20**

Probe `M:\claud_projects\temp\slice53\p7_endpoints.jl`, raw `…\p7_out.txt`, full write-up
`M:\claud_projects\temp\slice53\p7_findings.md`. **103 cells × 8 seeds = 824 flights, all at
`revisit_s` = 0.1 and `N`\* = 3**, mirrored edges, wire A (x0 = −15 km, 200 s), σ = 4 m², F = 8,
seeds (53, 149, 250, 1, 2, 3, 4, 5). `rcs_tail_gain` INJECTED (§2.13a), never authored.

**§0 — the paired construction is exact at EVERY cell, not just P4b's two.** `max |in_G − in_1|`
over all 824 flights = **0.000000e+00**; **0 of 824** edges censored. Δ = out_G − out_1 is an exact
paired gauge across the whole domain.

**§1 — ⭐⭐ THE MONOTONICITY IS STRUCTURAL, AND THE ONE HOLE IN THE ARGUMENT IS EMPIRICALLY EMPTY.**
The structural claim (identical draws ⇒ multiplier 1 inbound / ≥1 outbound ⇒ raising `G` only ADDS
detections ⇒ adding a detection splits a gap and never grows one ⇒ the `N`\* edge cannot fall) has
one leak, pre-registered before the run: **Swerling-1 adds signal to noise in QUADRATURE, so `z` is
an upward parabola and a detection CAN be lost when `G` rises** — but only from a look whose
crossing at the lower `G` was noise-driven, a `pfa`-scale event. Counted: inbound looks differing
from the null **0**; outbound vs null **200 191 added, 0 DROPPED** over **1 187 208** look
comparisons; adjacent-cell drops **0**; expected at `pfa` = 1e-6, ~1.19. ⇒ the superset holds
exactly and **no fine-grid reversal hunt is needed** — none of the arc's non-monotonicity
disqualifications (28, 40, 25, 20, 22, 49, 50) can attach to this knob.

**§2 — ⭐⭐⭐ THE STAIRCASE. §2.9 measured 7 CELLS; THE USER DRAGS A CONTINUUM.** Grid `G` = 1(1)100.

| domain | mean steps/drag | mean dead run | **worst-seed dead run** | top decile moves |
|---|---|---|---|---|
| 1 → 20 | 3.4 | 56.9 % | **90.0 %** (seed 5) | 1 of 8 |
| 1 → 50 | 6.0 | 40.0 % | **52.0 %** (seeds 1, 5) | 2 of 8 |
| 1 → 100 | 7.0 | 42.9 % | 58.0 % (seed 1) | **0 of 8** |

⇒ **§2.5's "ceiling of 20 is the candidate to beat" IS BEATEN — and beaten on the staircase, not on
total effect.** On seed 5 a 1→20 drag is dead over **90 %** of its travel; on seed 250, 85 %. A
ceiling of 100 is condemned the other way: **its top decile is dead on 8 of 8 seeds**, and its last
50 cells buy one extra step and 19 % more effect. ⭐⭐ **A LADDER'S CELLS CANNOT PRICE A SLIDER —
ONLY THE STRETCHES BETWEEN THEM CAN.**

**§3 — ⚠⚠ THE PRE-REGISTERED FALSIFIER FIRED: THE EDGE IS *NOT* ONE LEVEL CROSSING PUSHED OUTWARD.**
Declared-edge SNR rises **+2.71 dB ± 0.84** from `G` = 1 (13.65 dB, sd 1.10, n = 8) to `G` = 10
(16.36 dB), against a null-arm per-seed spread of 1.10 dB — then plateaus and wobbles
(16.31 → 15.06 → 16.15), i.e. not even a monotone trend. **Mechanism, and it is not a defect:** the
edge is declared by a RUN rule (give up after `N`\* = 3 consecutive misses), and a run of 3 misses
accumulates where the signal falls SLOWLY. The multiplier `1 + (G−1)·max(0,−cosθ)²` is ≈1 just
after CPA (θ ≈ 90°) and → `G` only as θ → 180°, so it reshapes the SNR-vs-range curve and changes
the **local slope** where the edge lands, not merely the level.

⇒ ⭐⭐⭐ **A RUN-RULE EDGE IS DECLARED AT A LEVEL THAT DEPENDS ON HOW FAST THE SIGNAL IS FALLING
THERE.** ⚠ **Gate 1 and gate 3 must NOT write "the tail gain buys range at a fixed detection
threshold" as an identity** in a docstring or a HUD — it is approximately, not exactly, true. It is
also why P7 refused to pre-register an `R_ref·(G^(1/4) − 1)` closed form as an external anchor (the
measured Δ(50)/Δ(20) = **2.07** vs the law's 1.49 already refutes it; pre-registering a refuted law
would have manufactured a FAIL needing retraction on a stated mechanism — P4 §E's exact shape).
2.71 dB out of a ~30 dB swing changes no sign and no ordering: **a stated CAVEAT, not a kill.**

**§4 — THE FLOOR IS A LESSON CHOICE, NOT A MODEL LIMIT** (a MODEL test under the two-test rule).
`G` < 1 = a target whose tail is DIMMER than its nose: Δ = **−403.6 m** at 0.25 (7 of 8 seeds
negative), −199.1 at 0.50, −128.9 at 0.75, +0.0 at 1.00. **Correctly signed and continuous through
1**; the kernel special-cases nothing. ⇒ **the floor of 1.0 is the NULL THE USER RETURNS TO, chosen
for the lesson.** ⚠ **Gate 1's docstring must SAY that**, and the load-time validator must accept
any `G` > 0 (clamping only at ≤ 0, where the multiplier would go negative at θ = π) even though the
shipped slider starts at 1.

**§5 — ⭐⭐⭐ THE CEILING: 50, LINEAR, WITH AN AUTHORED DEFAULT OF 20.**

| ceiling | Δ(C) m | half-effect at `G` | % of travel | worst dead run | tail/nose | tail/broadside |
|---|---|---|---|---|---|---|
| 20 | 2659.1 | 9.6 | 45.3 % | **90.0 %** | +13.0 dB | −23.1 dB |
| **50** | **5491.4** | **20.2** | **39.2 %** | **52.0 %** | **+17.0 dB** | **−19.1 dB** |
| 100 | 6778.6 | 24.2 | 23.5 % | 58.0 % | +20.0 dB | −16.1 dB |

(The dB columns need no simulation: the multiplier is exactly `G` at θ = π ⇒ tail/nose = `G`,
tail/broadside = `G`/F⁴ at the arc's authored F = 8, which 49 and 50 both author.)

**Against 20:** §2.9's ONLY all-seed-clean interval is `G` = 20 → 50, and a ceiling of 20 ends at
the bottom of it — the one drag guaranteed to move every seed would not be on the slider at all.
**Against 100:** top decile dead on 8 of 8; doubles the slider for 19 % more effect; +20 dB is the
outer edge of ordinary. **For 50:** contains the clean interval, best on every staircase measure,
and +17 dB tail-vs-nose / −19 dB tail-vs-broadside are ordinary for a real airframe.

⇒ **SHIP: floor 1.0, ceiling 50.0, LINEAR, authored default `G` = 20.** That default gives gate 3
two drags that provably move on all 8 seeds: **20 → 50** (the only all-seed-clean interval) and
**20 → 1** (back to the null). All 8 seeds are non-zero at `G` = 20 and all 8 move again on 20 → 50.

**⚠⚠ CORRECTION TO §0.3 — A LOG AXIS *IS* AVAILABLE ON THE SHIPPED WIRE, AND IS REFUSED ON
MEASUREMENT.** §0.3 pre-registered *"the knob protocol carries min/max, not a curve"* and therefore
concluded that a badly-spent linear drag would force **the ceiling down rather than the axis to
log**. **That premise is FALSE:** `Knob` carries `log::Bool` (`core/src/scenario.jl:20-29`), the
scenario handshake ships it (`core/src/server.jl:94-97`), seven shipped scenarios author
`log: true`, and the client honours it. The ceiling was a genuine three-way choice (50 linear /
100 log / 20 linear). The log axis loses on its own number: the half-effect of a 1→50 domain sits
at `G` = 20.2, which is **39.2 % of a LINEAR drag** but `ln 20.2 / ln 50` = **76.8 % of a LOG one**.
This knob's payoff is concentrated at the **BOTTOM** (Δ reaches 48 % of its 1→50 total by `G` = 20),
and a log axis stretches the bottom — turning a near-balanced 39 % into a badly top-heavy 77 %.

⇒ ⭐⭐⭐ **SLICE 49 REFUSED A LOG AXIS BECAUSE ITS PAYOFF WAS CONCENTRATED AT THE TOP; SLICE 53
REFUSES ONE FOR THE EXACT OPPOSITE REASON.** The shipped rule is not "linear by default" — it is
**put the half-effect near the middle of the drag**, and which axis does that is a MEASUREMENT.
⚠ **The gate-3 verifier tooth must state THIS reason (the 39 % vs 77 % pair) — it must NOT copy
49's or 52's wording**, which would assert a mechanism this slice does not have.

**⇒ F3 IS DISCHARGED. ALL PRE-REGISTERED FALSIFIERS ARE NOW ANSWERED — GATE 0 IS COMPLETE.**

---

### 2.15a — P7a: THE THREE THINGS §2.15 CLAIMED WITHOUT EARNING (56 flights)

Probe `M:\claud_projects\temp\slice53\p7a_mechanism.jl`, raw `…\p7a_out.txt`. 7 cells × 8 seeds,
same wire and same `revisit_s` = 0.1 / `N`\* = 3. Written because §2.15 starred a mechanism it had
not discriminated, fell back from a criterion that selected nothing without saying so, and leaned
on a censoring flag with slice 52's shape.

**§A — ⭐⭐ `snr_db` IS THE DETERMINISTIC LINK-BUDGET MEAN, NOT A REALISED DRAW.** The trajectory is
identical across seeds (`yaml_for` varies only `seed:`), so a seed-invariant `snr_db` at fixed
(`G`, look index) settles it: **max |snr_db(seed) − snr_db(53)| = 0.000000e+00 over 1500 looks at
all 7 cells.** ⇒ **the rival mechanism is dead.** The recorded quantity carries no per-draw noise,
so it cannot be shifted by selection *on itself*; the only free choice left is WHICH LOOK gets
declared, and where the first 3-run lands on a deterministic Pd curve is set by that curve's SHAPE.

**§B — THE SLOPE FALLS 2.9× ACROSS THE DOMAIN, AND IT IS THE ASPECT TERM DYING.** |dSNR/dlook| over
the 10 looks ending at the declared edge: **0.1109 → 0.0974 → 0.0787 → 0.0676 → 0.0570 → 0.0430 →
0.0387** dB/look for `G` = 1…100 (sd ≤ 0.011, n = 8) — monotone, exactly the predicted direction.
**External anchor, pure geometry, no simulation** (convention 11): a `1/R⁴` fall alone gives
`17.3718·v·(h/R)/R` dB per 0.1 s look at the measured edge range, with `h = √(R² − 4970²)`:

| `G` | edge R (m) | range-only slope | observed slope | **ASPECT share** |
|---|---|---|---|---|
| 1 | 6902.6 | 0.0524 | 0.1109 | **52.8 %** |
| 2 | 7051.9 | 0.0524 | 0.0974 | 46.2 % |
| 5 | 7640.0 | 0.0518 | 0.0787 | 34.2 % |
| 10 | 8327.7 | 0.0502 | 0.0676 | 25.7 % |
| 20 | 9561.7 | 0.0466 | 0.0570 | 18.3 % |
| 50 | 12394.0 | 0.0385 | 0.0430 | 10.4 % |
| 100 | 13681.2 | 0.0355 | 0.0387 | **8.3 %** |

The range-only column is nearly CONSTANT (0.052 → 0.036) while the total falls by 2.9× ⇒ **almost
all of the flattening is the aspect term dying away** as the multiplier `→ G` cancels the `1/F⁴`
nose/tail collapse. At `G` = 100 the edge sits where the fall is 92 % pure range.

⚠ **BUT THE MECHANISM IS ONLY HALF-CONFIRMED, AND §2.15 MUST BE READ WITH THIS.** A slower fall
should declare the edge at a HIGHER SNR, and it does over the first decade (slope −39 %, SNR
+2.71 dB, `G` = 1 → 10). Over the second (slope −43 %, `G` = 10 → 100) the same argument predicts
another ≈ +2.7 dB and the readout gives **≈ 0** (16.36 → 16.31 → 15.06 → 16.15, SE 0.4–0.8 dB).
⇒ **the slope is the only channel available (§A) and moves as predicted (§B), but it does not
quantitatively account for the plateau above `G` ≈ 10. That is OPEN and P7a did not close it.**

⇒ **⭐⭐ DOWNGRADED FROM §2.15's ⭐⭐⭐, AND RESTATED AS WHAT WAS ACTUALLY EARNED: A RUN-RULE EDGE IS
NOT A LEVEL — BEFORE QUOTING A THRESHOLD SNR, MEASURE HOW FAST THE SIGNAL IS FALLING WHERE THE RULE
FIRES.** The operational consequences in §2.15 §3 stand unchanged (do not write "buys range at a
fixed detection threshold" as an identity; do not pre-register the `G^(1/4)` closed form). ⚠ **This
is what may go into `docs/LESSONS.md` — NOT the stronger causal claim §2.15 printed.**

**§C — THE CENSORING FLAG IS CLEAN, BY A MARGIN OF THREE ORDERS OF MAGNITUDE.** P7's `edge` flags
censored only when the last detection IS the final element, so a flight ending in 1–2 trailing
misses would read UNCENSORED though truncated (slice 52's arm-specific trap). Measured gap from the
declared edge to the end of the outbound leg: **minimum 1030 looks** anywhere in the sweep (1324 at
`G` = 1, 1030 at `G` = 100), against `N`\* = 3. **0 flights with a gap < 3, at every cell.**
⇒ no flight was truncated by the 200 s window, and **§2.15 §5's "the last 50 cells buy 19 %" is
look-quantisation, not a window artefact** — the `G` = 90 / `G` = 100 tie is real.

**⇒ THREE CORRECTIONS THAT TRAVEL WITH §2.15's VERDICT (the verdict itself is unchanged):**

1. ⚠⚠ **"MONOTONE BY CONSTRUCTION" IS TOO STRONG — §2.15 §1 OVERSTATED ITS OWN CAVEAT.** 0 drops
   against ~1.19 expected is **P(0) = 0.30**: fully consistent with the quadrature leak existing and
   being rare, not with it being absent. **Correct wording: monotone across all 824 flights, with a
   `pfa`-scale exception rate consistent with ~1 per 10⁶ outbound looks.** The leak is real physics
   (Swerling-1 adds signal to noise in quadrature); a zero count does not repeal it.
2. ⚠⚠ **THE PRE-REGISTERED CEILING RULE SELECTED NOTHING, AND §2.15 DID NOT SAY SO.** "Does not
   spend its top decile of travel dead" is failed by ALL THREE candidates (20: 1/8 seeds move,
   50: 2/8, 100: 0/8). The verdict fell back to RELATIVE RANKING on that criterion. **Declared
   here, explicitly.** ⚠ This project killed five slices in a row and then ruled the CRITERION at
   fault (2026-08-18); undeclared criterion drift is that exact failure mode and must be recorded,
   not smoothed over.
3. **LEAD THE CASE AGAINST 20 ON THE CLEAN INTERVAL, NOT ON THE DEAD-RUN PERCENTAGE.** Two
   confounds sit under the percentage: dead-run "% of travel" is domain-normalised while the grid
   is 1 unit of `G` — coarse exactly where the payoff concentrates (`G` < 10 is 47 % of a 1→20
   widget but 9 % of a 1→100 one), so under-resolution inflates the dead-run % and deflates the
   step count of the very domain it condemned; and §2.9's "only all-seed-clean interval" compared
   unequal widths (1/3/5/10/30/50), so a wider interval moves more seeds mechanically. **Neither
   is needed:** P7's fine grid gives the direct statement — **20 → 50 moves 8 of 8 seeds** — and the
   case against a ceiling of 20 is simply that **it puts no all-seed-clean drag on the slider at
   all.** The staircase table stays as SUPPORTING evidence, not as the lead argument.

**⚠ SCOPE LIMIT THAT TRAVELS WITH THE CEILING (the P6 Arm 2 discipline).** Every endpoint number is
**wire A only** (x0 = −15 km, 200 s, σ = 4 m², F = 8, `revisit_s` = 0.1, `N`\* = 3). P6 Arm 2 already
showed the METRES are a joint property of the tail lobe and the tracker. **The ceiling of 50 is
justified on this wire and is quoted with it** — not re-flown on others, and not claimed beyond them.
