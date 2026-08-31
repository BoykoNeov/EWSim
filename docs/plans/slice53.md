# Slice 53 — **A TAIL LOBE**: does a target look the same going away as coming at you?

**STATUS: GATE 0 IN PROGRESS — P1 AND P2 HAVE RUN (2026-08-31); F1 AND F2 ARE DISCHARGED.**
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
(probes: `p1_aspect.jl`, `p2_wires.jl`, `p2b_w1_length.jl`, `p2c_substitution.jl`; raw output in the
matching `*_out.txt`). This section is the SUMMARY the repo carries.

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
