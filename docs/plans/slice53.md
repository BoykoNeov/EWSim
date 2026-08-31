# Slice 53 — **A TAIL LOBE**: does a target look the same going away as coming at you?

**STATUS: GATE 0 IN PROGRESS — P1, P2 AND P3 HAVE RUN (2026-08-31); F1 AND F2 ARE DISCHARGED, AND
F3's MONOTONICITY AND BAR FILTERS WITH THEM. ⚠ F3's THIRD FILTER — *not sayable without the
asymmetry* — IS P4's SUBSTITUTION TEST AND IS STILL OPEN.**
⚠ P3 FIXED TWO THINGS P4–P7 MUST USE VERBATIM: the run-length rule `N`\* = 3 and MIRRORED edges
(§2.8). The ceiling is 50. **§2.3's and §2.6's ladder magnitudes are superseded by §2.8 — do not
quote them.**
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

### ⚠ THE ONE THING GATE 3 MUST DESIGN AROUND — **THE BOTTOM OF THE SLIDER HAS DEAD ZONES**

Every seed has 1–3 FLAT cells and they are concentrated at low `G`: seed 53 does not move at all
from `G` = 1 to `G` = 5, seed 250 sits at +877.6 m across `G` = 2 → 10, seed 5 sits at +2410.5 m
across `G` = 5 → 20. That is the edge's quantisation to a look index, not a physics failure — but on
a LIVE slider it means **a user dragging one flight from 1 to 2 can see nothing move at all.**

⇒ gate 3 must not let the first inch of the drag read as "the knob is dead" (49's `.get(k, 0.0)`
family of traps, one level up: here the number is REAL and simply has not changed yet). Either the
view shows the batch, or the authored default sits where the ladder is already moving, or the
readout says *how many looks* the edge moved rather than only metres. **Decided at gate 3, recorded
here.**

### HOW BIG A BATCH, IF ONE IS EVER WANTED (estimated from n = 8, quoted as such)

| `G` | 1 | 2 | 5 | 10 | 20 | 50 | 100 |
|---|---|---|---|---|---|---|---|
| sd (m) | 609.9 | 762.9 | 830.9 | 842.9 | 870.0 | 1411.3 | 1354.9 |
| se at n = 8 (m) | 215.6 | 269.7 | 293.8 | 298.0 | 307.6 | 499.0 | 479.0 |
| seeds for se ≤ mean/3 | 2112 | 147 | 11 | 3 | **1** | **1** | **1** |

⭐ **The scatter is essentially FLAT in `G`** (sd 610 → 870 m from `G` = 1 to 20 while the mean goes
+40 → +2699 m) — the lobe moves the mean without widening the distribution, which is why one flight
suffices from `G` = 20 up and why the per-seed ladders are clean. ⚠ The `n` column is an estimate
from 8 seeds and is not a licence to quote a headline from one flight at low `G`.
