# Slice 50 — THE ASPECT-DEPENDENT ENGAGEMENT (the target gets a vote in when it is seen)

**Status: GATE 0 — PLAN WRITTEN, NO PROBE RUN YET (2026-08-26).** Suite green at 17280 tests (slice
49); no code shipped. Picked from `docs/DEFERRALS.md` §"New candidates raised by slice 49", the
⭐⭐⭐ entry: *"THE SEEKER SIDE OF THE SAME PHYSICS — an ASPECT-DEPENDENT ENGAGEMENT."*

**What this slice is:** slice 49 gave a target a SHAPE, and `_effective_rcs` is the ONE site where a
shape becomes a cross-section — so **the missile's seeker horizon is ALREADY aspect-dependent as of
slice 49** (`missile.jl:2661`), untested and unteaching. Every slice from 26 to 48 treats detection
as a property of the MISSILE'S DESIGN — the window, the aperture, the transmit power, the search
rate. This slice asks what happens when the horizon moves because **the target did something**.

---

## §0 — ⚠⚠ THE STRUCTURAL FACT THAT MAKES THIS GATE 0 UNUSUALLY LOAD-BEARING

**THERE IS NO CONSOLATION PRIZE IN THIS SLICE.** The 2026-08-18 two-test rule's escape hatch —
*"pass model / fail lesson ⇒ DEAD AS A LESSON, ALIVE AS A MODEL, it ships as physics + tests +
authorable keys"* — **is not available here, because the physics has already shipped.**
`_effective_rcs` is called by the seeker's detection horizon, `rcs_fineness` is loader-validated,
`aspect_angle`'s sign is pinned at 0/90/180°, and `target_aspect_deg` / `rcs_eff_m2` are already on
the wire. **The MODEL test was passed by slice 49.** What is left to decide is ONLY whether there is
a LESSON, and if there is not, **this slice ships nothing and must be abandoned rather than built for
tidiness.** ⇒ decide it fully at gate 0, before a kernel, a scenario or a Godot branch exists.

---

## §0.1 — THE PREMISE, READ OFF THE SHIPPED CODE (four facts, located before any probe)

**1. THE SEEKER'S GATE IS DETERMINISTIC AND SINGLE-THRESHOLD.** `missile.jl:2636` —
`_detectable = r_los_det ≤ r_acq_det`, and its own comment says *"DETERMINISTIC — a hard threshold,
NO `Pd` draw"*. ⚠⚠ This is the path slice 49 §8 discovered its P1 had probed by mistake while
believing it was the ground radar's — so **slice 49's central proof was measured on THIS gate and
banked for it**, which is exactly why §0.3 below treats "the seeker loses it while closing" as
ALREADY KNOWN rather than as this slice's finding.

**2. THE HORIZON HAS A CLEAN CLOSED FORM IN THE ASPECT, AND IT IS SIMPLER THAN THE RCS.** From
slice 49 §3's normalized ellipsoid `σ(θ) = rcs_m2 / (sin²θ + F²cos²θ)²` and `detection_range`'s
`R ∝ σ^(1/4)` (rf.jl:135, off the R⁻⁴ link budget), the fourth root and the square cancel exactly:

```
R_acq(θ) = R_broadside / sqrt(sin²θ + F²cos²θ)
```

⭐ **That cancellation is the single most useful fact in this plan** and it is the general form of
slice 49 §2's transferable lesson (*a fourth-root law does not make a component negligible if the
quantity under it is raised to the fourth power on the way in*). Near broadside, with `δ = 90° − θ`
in radians, `R_acq ≈ R_b / sqrt(1 + F²δ²)` — the horizon is governed by the product `F·δ`, i.e. by
**slenderness times degrees off broadside**, and by nothing else.

**3. THE TELEMETRY THIS SLICE NEEDS ALREADY EXISTS.** `missile.jl:3695–3709` ships
`seeker_detect` (0/1), `target_aspect_deg` (⚠ from the MISSILE's seat — a different number from the
ground radar's on the same target at the same instant) and `rcs_eff_m2`, all key-presence gated on
`:rcs_fineness`. ⇒ every probe below reads the SHIPPED wire, never a hand-recompute (convention 10).

**4. A TURNING TARGET IS AUTHORABLE, BUT NOT ALONGSIDE `cross_speed_mps`.** Slice 49 shipped
`TARGET_TURN_PLANES` and `turn_plane: horizontal` (`missile.jl:1007`). ⚠ `scenario.jl:157` REFUSES
`cross_speed_mps` in the same target block as `maneuver:` — and **`slice48_search.yaml:214` authors
exactly that key** (`cross_speed_mps: -200.0`). ⇒ a turning version of the missile wire is a NEW
scenario that drops the crossing-speed hold, not an edit to slice 48's. Said out loud here because
"the showcase is slice 48's wire plus a `maneuver:` block" is a load ERROR, not a plan.

---

## §0.2 — ⚠⚠⚠ THE PRE-REGISTERED KILL, AND IT IS NOT A REPARAMETERIZATION KILL

Every slice since 39 has pre-registered *"can one constant reproduce the curve?"* as the kill. **That
is the WRONG kill for this slice, and pre-registering it would let a dead slice pass.** The right one:

> **⚠⚠ THIS SLICE DIES IF ITS SURVIVING SENTENCE IS SLICE 49's SENTENCE WITH "RADAR" REPLACED BY
> "SEEKER".** 49's ⭐⭐⭐ headline is *a constant echo can be gained while closing and never lost*.
> §0.1 fact 1 says that proof was MEASURED ON THIS GATE. So "the seeker loses a closing target when
> it turns nose-on" is **not a finding of slice 50 — it is slice 49's finding, on a consumer 49 had
> already wired.** A gate-0 probe that ends there has measured a redux.

⇒ **THE SURVIVING CLAIM MUST BE AN ENGAGEMENT STATEMENT A GROUND RADAR CANNOT MAKE.** A ground radar
has no intercept: no guided time, no manoeuvre authority, no CPA, no endgame. Anything this slice
ships must be about **what the moving horizon COSTS a guided engagement, and WHEN.**

**THE SECONDARY KILL, and it is the one that usually fires** (39/41's ground): *a LATE LOCK is
reproducible by a constant.* If the headline reduces to "a slender target locks later, so less guided
time," then a smaller constant `rcs_m2` — one whose fixed horizon crosses the closing range at the
same instant — reproduces the whole engagement, and the aspect model is a retune. ⚠ **This is why the
denial arm cannot stand on the lock INSTANT alone.** The discriminator has to be a state a fixed
horizon cannot reach, and there is exactly one such state on a deterministic single-threshold gate:
**the horizon RETREATING faster than the range closes.**

---

## §0.3 — THE ARITHMETIC, RUN BEFORE THE PROBE (the `docs/LESSONS.md` discipline)

**THE QUESTION THE CALCULATOR HAS TO ANSWER FIRST:** is a horizon that retreats faster than the
missile closes reachable with a turn a real aircraft can fly, on a wire this project flies? If not,
the slice has no showcase and §0 says it has nothing else either.

Differentiate §0.1 fact 2 along a turn at heading rate `ω` (which moves `δ` one-for-one):

```
|dR_acq/dt| = R_b · F²·δ·ω / (1 + F²δ²)^(3/2)
```

The detection state can only be LOST while closing when `|dR_acq/dt| > V_c` (the closing speed).
Evaluate at the moment the horizon crosses the range — i.e. where `R_acq = r`, so
`(1 + F²δ²) = (R_b/r)²`:

| quantity | value used | source |
|---|---|---|
| `F` (fineness) | 8 | slice 49's authored showcase value |
| `R_b` (broadside horizon) | 12 000 m | to be authored; slice 48's wire has 3038 m at `rcs_m2 = 0.020` and R ∝ σ^(1/4), so ~4× wants ~250× the RCS — **a 5 m² broadside target, which is an ORDINARY aircraft** |
| `r` at the crossing | 4 000 m | mid-endgame on this arc |
| ⇒ `F·δ` | `sqrt(9 − 1)` = 2.83 | from `(1+F²δ²) = 3²` |
| ⇒ `δ` | 0.354 rad = **20.3° off broadside** | |
| ⇒ `|dR_acq/dt|` | **≈ 10 070 · ω** m/s (ω in rad/s) | the formula above at `u = 9` |
| `V_c` (closing speed) | ~800 m/s | the 26–48 arc's endgame |
| ⇒ **ω required** | **> 0.079 rad/s = 4.6 °/s** | |
| ⇒ `a_lat` at 200 m/s | **> 15.9 m/s² ≈ 1.6 g** | `a = ω·v` |
| ⇒ `a_lat` at 300 m/s | **> 23.8 m/s² ≈ 2.4 g** | slice 49's showcase authors 15.0 m/s² at 300 m/s |

⭐⭐ **THE CALCULATOR SAYS YES, AND BY A WIDE MARGIN: A TWO-G DEFENSIVE TURN MAKES THE SEEKER'S
HORIZON RETREAT FASTER THAN THE MISSILE CLOSES.** That is a gentle, entirely ordinary manoeuvre —
not a 9 g break — and the margin means the effect is not living on a knife-edge (⚠ slice 42's kill:
*re-fly any narrow threshold at half `dt`*; a factor-of-several margin is what keeps this off that
ground).

**⚠ AND THE CALCULATOR ALSO SAYS THE SHOWCASE CANNOT BE SLICE 48's WIRE.** Two independent reasons:

1. **The pre-lock deciding window is 2.2–3.4 s** (slice 49 P0, measured). At 4.6 °/s a target builds
   only 10–16° of heading inside it, from an aspect that starts at 64.93° — i.e. **`δ` starts at
   25°, already 25.4 dB down**, and moves the wrong way (49 P0: the aspect walks 65° → 90°, so σ
   RISES and the horizon EXPANDS). Slice 48's geometry is aligned AGAINST this slice's mechanism, in
   the same way slice 49 §7 showed a straight-flying target is aligned against its own.
2. **`rcs_m2` becomes the BROADSIDE value** (slice 49 §3). Authoring `rcs_fineness: 8` onto slice
   48's `rcs_m2: 0.020` at a 65° aspect dims it ~180× → the horizon collapses from 3038 m to ~740 m
   and the missile never sees the target at all. **An existing scenario cannot be given a shape
   without re-authoring its RCS**, which is the same finding slice 49 §3 recorded for the ground
   radar, one consumer over.

⇒ **THE SHOWCASE IS A NEW ENGAGEMENT, and the geometry is prescribed by the arithmetic rather than
inherited:** the target starts NEAR BROADSIDE to the missile (bright, long horizon, comfortably
inside it — slice 49 §5's *"start the leg inside the broadside horizon so the one drop-out is
unambiguous"*), and turns its nose toward the missile during the flight.

⚠⚠ **AND THE WIRE IS SETTLED HERE RATHER THAN LEFT IN TWO STATES (§3 correction 2): THE MISSILE IS
LAUNCHED *INSIDE* THE BROADSIDE HORIZON, AND SLICE 47's MIDCOURSE IS *NOT* A PRECONDITION.** An
earlier draft of this section invoked slice 46's law (*a detection gate can only price a design
variable if the engagement is launched OUTSIDE the sensor's horizon*) and concluded a midcourse phase
was required. **That law does not bind arm B.** 46's premise is that a gate which never closes on
anything prices nothing — but arm B's gate closes MID-FLIGHT, in the direction no constant horizon
can (§0.2), so it is deciding something from the first tick to the last. ⇒ the wire is: **lock early
and comfortably (inside a ~12 km broadside horizon), turn, and let the horizon retreat back through a
~4 km range.** ⭐ This also keeps the engagement at slice 48's scale (6.4 km / 8.9 s) instead of
roughly doubling it, so no claim is made on airframe energy that this arc has not already flown.

---

## §0.4 — THE TWO CANDIDATE HEADLINES, PRE-REGISTERED, WITH P0 AS THE SELECTOR

Slice 49's arm-A/arm-B shape, reused because it worked: name both before measuring, let the probe
choose, and record the loser's refutation.

**ARM A — DENIAL (the missile never gets a usable lock).** The turn shrinks the horizon below the
range for the whole endgame; the missile arrives having flown the intercept on a midcourse belief.
⚠ **Arm A carries §0.2's secondary kill on its back** — a late-or-never lock is exactly what a
smaller constant `rcs_m2` produces — so arm A can only ship if P2 shows a constant CANNOT match the
curve. Prior: it probably can.

**ARM B — THE RETREATING HORIZON (the lock is taken and then broken while the range falls).** The
missile acquires on the broadside flash, the target turns, `R_acq` retreats faster than `V_c` closes
(§0.3), and the seeker's availability verdict flips back to false at DECREASING range. **No constant
horizon can do this at any value** — the same structural proof slice 49 banked, but here the thing
being proved is about an INTERCEPT: the missile spends its endgame on a frozen estimate.
⚠⚠ **ARM B'S OWN HAZARD, NAMED NOW (advisor):** what the missile DOES while blind is the tracker's
coast behaviour, and slice 37 is DEAD AS A LESSON there (*a break in this arc is not an episode but
the rest of the flight; the cure is the ESTIMATOR's frozen rate, not the head*). ⇒ **this slice must
not propose a cure and must not make the coast its subject.** It measures the COST and names the
cure as another slice's, or it re-imports 37's killed framing.

**⭐ THE SENTENCE ARM B IS ALLOWED TO SHIP (and the test of whether it earned it): it must survive
the §0.2 substitution test — swap "seeker" for "radar" and it must become FALSE or EMPTY.** Draft:
*a defensive turn can take back a lock the missile already had, and the later it comes the less of
the intercept is left to fly on what the missile last knew.* A ground radar cannot say "intercept",
"left to fly" or "last knew". ⚠ If the measured version of that sentence loses those words, the
slice dies at gate 0.

---

## §0.5 — ⚠⚠ THE CONFOUND, AND THE CONTROL THAT ANSWERS IT (slice 41's `af_I` failure, avoided)

**A TURN MOVES THE TRAJECTORY AS WELL AS THE ASPECT.** Closing speed, the intercept triangle, the
CPA and the LOS rate all change when the target manoeuvres — so an arm flown against a straight
target is measuring TWO things. This is slice 41's confound verbatim (*"halving `af_I` is CONFOUNDED,
because `af_I` moves the plant as well as the frequency"*), and it is the single easiest way for this
gate to produce a number that means nothing.

⇒ **EVERY PROBE ROW AND EVERY SHOWCASE ARM HAS THE SAME CONTROL: `rcs_fineness: 1.0` (a sphere)
FLYING THE BYTE-IDENTICAL MANOEUVRE.** Same `a_lat_mps2`, same `turn_plane`, same start, same
everything — only the shape differs. Then any difference is ASPECT and cannot be geometry.
⚠ The control is `F = 1`, **not** the key absent: slice 49's loader comment is explicit that
`sin²θ + cos²θ` is 1 in algebra and not always 1.0 in floating point, so the absent key is the
WIRE's null (byte-identity) and `F = 1` is the LESSON's null (a sphere). Both get used, for different
questions.

---

## §0.6 — THE GAUGE, PRE-REGISTERED BEFORE ANY PROBE RUNS

Everything that is already banned or already spent, and why:

| candidate gauge | verdict |
|---|---|
| **MISS / CPA** | ⚠⚠ **BANNED, THREE TIMES NOW** — 44 killed a component on it, 46 measured it non-monotone along the ladder AND backwards across the button, 48 measured a 100 %-authority acquisition that still missed. Not a gauge on this arc. |
| **manoeuvre authority (`a_cmd/a_max`)** | ⚠ 46/47's gauge, but slice 48 measured it **NON-MONOTONE in its slider** (it saturates, then falls). Report it; do not make it the axis. |
| **longest loss run while closing** | ⚠ **SPENT — this is slice 49's shipped gauge.** Using it here is the §0.2 redux wearing a number. |
| **GUIDED TIME BEFORE CPA** (seconds with `seeker_detect == 1`, pre-CPA) | ⚠⚠ **DEMOTED TO A READOUT — IT FAILS §0.2's OWN SUBSTITUTION TEST, see §3 correction 1.** It and 49's loss run are two functions of the SAME 0/1 trace over the same closing window (the longest run of zeros vs the count of ones); neither reads the guidance loop, the airframe or the intercept. *"The seconds the radar had the target before closest approach"* is a sentence a ground radar can say. |
| ⭐⭐ **‖ω_LOS‖ AT THE FINAL VALID MEASUREMENT** (deg/s — `los_rate`, `missile.jl:1707`, sampled on the last tick the gate is closed before CPA) | **PRE-REGISTERED PRIMARY.** *How far from a collision course was the missile when the picture went stale?* Under PN the loop drives ω toward zero while it can see; a nonzero ω at the last look is a heading error the missile **can no longer learn about**. ⚠ A radar has no collision course to correct — this is the quantity that passes the substitution test. |
| **`t_go` AT THAT SAME INSTANT** (s — `missile.jl:1718`) and the product **‖ω_LOS‖·t_go** (rad) | **PRE-REGISTERED SECONDARY.** How much flying was left, and the angle the missile still OWED and went blind holding. |
| **RANGE AT FINAL LOCK** (m) | **READOUT.** Names *where* the engagement went blind, which is how the HUD will have to say it. |

⚠ **AND THE 48 HAZARD THIS SLICE WILL MANUFACTURE: RIM-MARGIN LOCKS.** Slice 48 measured that a lock
taken with less window margin than ONE TICK of LOS drift is consumed and buys nothing
(`margin@lock > ω_LOS·dt`, 4 of 44 cells, ~1183 m misses, invisible on every gauge). A retreating
horizon manufactures exactly that state — a lock taken as the horizon sweeps back through the range.
⇒ **the gauge's tick test is `seeker_detect == 1` AND the window margin rule, decided here rather
than discovered when a cell reads 0.005° and passes.**

---

## §0.7 — SLIDER

**PRE-REGISTERED: `rcs_fineness`, floor 1.0 (sphere), ceiling ~12 — the same slider slice 49 shipped,
on a different consumer.** ⚠ Named as a repeat deliberately: **the slider may repeat, the GAUGE may
not** (§0.6), because the gauge is what carries the lesson and the §0.2 substitution test is applied
to the SENTENCE, not to the knob.

Everything else is disqualified, and each for a reason already on the record:

- **`a_lat_mps2` (how hard the target turns)** — ⚠ TWO-SIDED, and worse here than in slice 49: the
  turn rate sets how fast the nose comes round AND the whole intercept triangle (§0.5). Non-monotone
  by construction.
- **The TURN ONSET TIME (when the target breaks)** — ⭐ the most interesting axis in the slice
  (*how late can you turn and still deny the shot?*) and **NOT AUTHORABLE TODAY**: `ManeuveringTarget`
  turns from t = 0. It would be a new key on shipped physics with its own byte-identity tooth. ⚠ Do
  not smuggle it in: if P0/P1 say the lesson needs it, that is a decision to record at gate 0 with
  the §7-of-slice-49 shape (option 1: an absent key reaching the existing line by early return), and
  if they do not, it stays a deferral.
- **`detect_pt_w` / the seeker window** — ⚠ this is 46's axis, and pairing it with the target's shape
  is a two-mechanism scenario (convention 9).

---

## §1 — THE PROBES (gate 0), IN ORDER. ⚠ NO KERNEL IS WRITTEN UNTIL P0 AND P1 HAVE RUN.

| # | question | kills what |
|---|---|---|
| **P0** | On a purpose-built wire (§0.3's geometry, slice 47's midcourse so the launch is outside the horizon): does `R_acq` retreat faster than `V_c` closes, and does the seeker's `seeker_detect` flip 1 → 0 at DECREASING range? Sweep `F ∈ {1, 3, 6, 8, 10}` with the §0.5 control. | **ARM B**, and it is the selector. ⚠ Read `seeker_detect` off the SHIPPED wire, never a recompute (convention 10). |
| **P1** | Is **‖ω_LOS‖ at the final valid measurement** monotone in `F`, and does it separate from the `F = 1` control flying the identical manoeuvre? Report `t_go` and the product alongside. | **THE GAUGE.** A non-monotone gauge is not a domain (28/40/25 precedent). ⚠ THE EXPECTED SIGN, PRE-REGISTERED: slenderer ⇒ the horizon retreats sooner ⇒ **less time for PN to null ω before the loss** ⇒ ω at the last look RISES with `F`. A curve that falls with `F` is a wrong-sign result and must be understood, not quoted. ⚠ If NO intercept-only quantity is monotone, the honest fallback is guided-time WITH §3's admission written into the ledger — weaker, but not a false positive. |
| **P2** | ⚠⚠ **THE LOAD-BEARING ONE FOR ARM A:** can ONE constant `rcs_m2` reproduce the guided-time-vs-`F` curve to better than **3 %**? (Threshold fixed here, before measuring — slice 41's precedent: falsifier 2.7–3.2 %, achieved 0.00–1.01 %.) | **ARM A's headline.** ⚠ For ARM B this is answered by PROOF instead (a fixed horizon cannot retreat), which is the stronger form — but only if P0 shows the retreat actually happens. |
| **P3** | The §0.2 SUBSTITUTION TEST, applied to whatever sentence survives P0–P2: swap "seeker" for "radar" — does it become false or empty? | **THE WHOLE SLICE.** ⚠ This is a prose test, not a number, and it is the one this plan exists to force. |

⚠ **P0 IS FIRST BECAUSE IT IS THE KILL RISK** (`docs/LESSONS.md`: *fly the kill risk before the
mechanism*). ⚠ Probes live in `M:\claud_projects\temp\slice50\`, flown through `tools/julia.ps1`.

**WHAT GATE 1 WOULD BUILD IF THE GATE CLOSES:** ⭐ almost nothing in the core — the primitive
(`rcs_aspect`), the aspect helper, the seam (`_effective_rcs`) and the telemetry all shipped with
slice 49. The expected shape of this slice is **a scenario, a gauge, a view and four proofs**, plus
whichever ONE physics edit P0/P1 prove the lesson needs (§0.7's turn-onset key is the only candidate
on the table, and it is not yet justified). ⚠ That is a slice shape this project has not built
before, and it is worth saying out loud: **if gate 0 closes, the cheap part is the code and the whole
cost is the showcase.**

---

## §2 — WHAT THIS PLAN DELIBERATELY DOES NOT PROPOSE

- **A CURE for the blind endgame.** Slice 37's memory track is DEAD AS A LESSON and the estimator's
  frozen rate is another slice's subject (§0.4).
- **A TAIL LOBE.** `rcs_aspect` is fore/aft symmetric by construction, so a fleeing target looks like
  an approaching one — a NAMED approximation and a separate ⭐⭐ deferral, and pulling it in here
  would be a second mechanism (convention 9).
- **A TARGET ATTITUDE.** Aspect is taken off the velocity direction; a hard-turning target really
  flies at sideslip. ⚠ It belongs to whichever slice gives targets a 6-DOF airframe, and note it
  would make aspect depend on the TURN RATE — which is §0.5's confound with a second head.
- **AN RCS FLUCTUATION MODEL TIED TO THE SHAPE.** ⚠⚠ Slice 49 PRE-REGISTERED a kill on this: its own
  control arm depends on the Swerling choice being authorable independently of the shape.
- **A `Pd` DRAW ON THE SEEKER GATE.** ⚠ Slice 46 flagged it as a class-(b) draw-topology hazard
  (convention 3), and it would destroy the one property this slice's proof rests on (§0.2): a
  deterministic single threshold.

---

## §3 — TWO CORRECTIONS MADE BEFORE ANY PROBE FLEW (2026-08-26, advisor)

Both were caught against the plan as first written, and both would have produced a gate-0 result that
looked clean and meant nothing. Recorded rather than silently edited, because the second one is a
design decision and the first is a method lesson worth carrying.

**⚠⚠ CORRECTION 1 — THE SUBSTITUTION TEST APPLIES TO THE GAUGE, NOT ONLY TO THE SENTENCE.** §0.2
invents a test (*swap "seeker" for "radar"; the claim must become false or empty*) and then §0.6
pre-registered a gauge that FAILS it. **Guided time before CPA and slice 49's longest-loss-run are
two functions of the same 0/1 detection trace over the same closing window** — the count of ones and
the longest run of zeros. Neither reads the guidance loop, the airframe or the intercept, and *"the
seconds the radar had the target before closest approach"* is a sentence a ground radar says without
difficulty. ⇒ **P1 would have measured slice 49's trace re-denominated and closed gate 0 on a false
positive** — the one failure §0 says this slice cannot afford, since there is no model to fall back
on. ⭐ **The transferable form: a test you invent for the CLAIM must be run against the MEASUREMENT
too, or the claim is new and the evidence is not.**

⚠ **AND THE SQUEEZE THAT MAKES THIS HARD, NAMED SO IT IS NOT REDISCOVERED MID-PROBE:** miss is banned
(§0.6), and most genuinely intercept-only quantities — cross-range error accumulated after the loss,
error at CPA — **are the miss under another name**. The escape is to read a guidance-loop STATE at
the instant of final loss rather than an OUTCOME after it, which is why the gauge is now ‖ω_LOS‖ (and
`t_go`) at the last valid measurement: both are already on the shipped wire (`missile.jl:1707/1718`),
both are states of the loop, and neither is a function of what happens afterwards.

**⚠⚠ CORRECTION 2 — 46's LAW DOES NOT BIND ARM B, AND THE WIRE IS NOW SETTLED.** §0.3 originally
concluded that slice 47's midcourse was *"not optional staging, it is the precondition"*, on 46's law
that a detection gate can only price a design variable if the engagement launches outside the
horizon. **Arm B does not need the launch outside the horizon — it needs the gate to CLOSE
MID-FLIGHT, which is a different requirement**, and one a launch INSIDE the horizon satisfies just as
well (46's premise is a gate that never decides anything; arm B's decides continuously). Keeping the
midcourse would have meant launching beyond a 12 km broadside horizon — roughly DOUBLE slice 48's
6.4 km / 8.9 s engagement — and an airframe-energy claim this arc has never flown. ⇒ §0.3 now states
the launch is INSIDE the horizon and the midcourse is dropped. ⭐ The general form:
**a law is a statement about a PREMISE, and a slice that inherits the law without re-checking the
premise inherits a constraint it does not have.**

⚠ **UNCHANGED BY BOTH CORRECTIONS**, and re-affirmed: the closed form
`R_acq = R_b/sqrt(sin²θ + F²cos²θ)`, the 2 g margin it implies, slice 48's wire being ruled out
twice over, the `F = 1`-flying-the-byte-identical-manoeuvre control (valid precisely because
`ManeuveringTarget` does not react to the missile, so both arms fly the same trajectory), and §0.6's
rim-margin tick test.

---

## §4 — P0 HAS RUN (2026-08-26). ⭐⭐⭐ **THE SEEKER LOSES A TARGET IT ALREADY HAD, WHILE THE RANGE IS STILL FALLING.** ARM B LIVES.

**Probes:** `M:\claud_projects\temp\slice50\` — `p0a_gate.jl` (+ `p0a_gate_lib.jl`), `p0a2_cell.jl`,
`slice50_probe.yaml`, `p0b_wire.jl` (+ `p0b_lib.jl`), `p0c_dense.jl`. Gate 0 ships nothing, so the
wire is a temp YAML, not `scenarios/`.

### §4.1 — ⚠⚠ FIRST: §0.3's ARITHMETIC IS WRONG, AND ITS OWN CELL SHOWS **NO LOSS ON ANY ARM**

§0.3 checks that the horizon retreats faster than the missile closes **at an assumed crossing**
(`r = R_acq = 4000 m`). **It never checks that the crossing HAPPENS BEFORE CPA.** Those are different
conditions and the second binds much harder. With `R_acq ≈ R_b/(F·ω·t)` and `r ≈ r₀ − V_c·t`:

```
a crossing exists only if      F·ω  >  4·V_c·R_b / r₀²
```

At §0.3's own numbers (`R_b` = 12 000 m, `r₀` = 6100 m, `V_c` ≈ 800 m/s, `F` = 8) that is
**ω > 0.13 rad/s ≈ 7.4 °/s ≈ 3.9 g** — not the **4.6 °/s / 1.6 g** §0.3 advertises, and not the
"wide margin" it claims. Measured (`p0a_gate.jl`, 96 cells, kinematic stand-in):

| `rcs_m2` | `R_b` | `r₀` | a_lat 15 | 30 | 45 | 60 | (all at F = 8) |
|---|---|---|---|---|---|---|---|
| **5.0 (§0.3's own)** | 12 081 m | 6100 m | **no loss** | **no loss** | LOSS | LOSS | |
| **1.0 (this wire)** | 8 079 m | 6100 m | no loss | **LOSS** | LOSS | LOSS | |

⇒ **the wire drafted straight off §0.3 would have flown and shown nothing, on the one probe §0 says
this slice cannot afford to get wrong.**

⭐⭐ **AND THE LEVER RUNS BACKWARDS TO THE PLAN: `r₀²` IS IN THE DENOMINATOR, SO LAUNCHING DEEPER
INSIDE THE HORIZON MAKES THE CROSSING HARDER, NOT EASIER.** §3 correction 2 was qualitatively right
(arm B needs the gate to close mid-flight, not a launch outside the horizon) but it dropped the
QUANTITATIVE half with it. The design variable is the **ratio `R_b/r₀`**, and §0.3's 2.0 is too big.
The fix is a **smaller broadside horizon** (`rcs_m2: 1.0` — as ordinary an aircraft as 5 m²), **not a
harder turn**: a harder turn pushes on §0.5's confound. ⭐ **THE TRANSFERABLE FORM: a design
condition evaluated AT a crossing has not shown the crossing EXISTS.**

### §4.2 — THE WIRE (`slice50_probe.yaml`)

Slice 48's plant and seven-key seeker budget, with the search and the midcourse both REMOVED (arm B's
missile has the lock at launch; §3 correction 2 drops the midcourse), plus: `rcs_m2: 1.0`
(⇒ `R_b` = 8079 m), target at `[6000, 0, 4200]` with `vel [0, −300, 0]` against a missile at
`[0, 0, 3000]` — **exact 90.00° aspect at t = 0**, measured 89.997° off the wire — and
`maneuver: {a_lat_mps2: 30.0, turn_sign: −1.0, turn_plane: horizontal}` (3.06 g, 5.73 °/s). Launch
range 6118 m, INSIDE the 8079 m broadside horizon. `cross_speed_mps` is refused beside a `maneuver:`
block (scenario.jl:170), so the crossing is authored in `vel:` — §0.1 fact 4, confirmed at load.

### §4.3 — ⭐⭐⭐ THE RESULT, READ OFF THE SHIPPED WIRE (`p0c_dense.jl`, dt = 1e-3)

`m1.seeker_detect`, `m1.seeker_r_acq_m`, `m1.closing_speed`, `m1.los_rate`, `m1.target_aspect_deg`
straight off the telemetry — **the headline is ONE SHIPPED KEY DIFFERENCED AGAINST ANOTHER**, zero
recompute (convention 10). `ratio` = `|dR_acq/dt| / V_c` at the loss instant.

| `F` | blind s | LOST at t / r / aspect | `dR_acq/dt` | `V_c` | **ratio** | re-GAIN t / r | ‖ω‖ | `t_go` | CPA m | det@CPA |
|---|---|---|---|---|---|---|---|---|---|---|
| 1.0 – 7.0 | **0.000** | — | — | — | — | — | — | — | 0.40 | YES |
| 7.5 | 0.377 | 4.122 / 3204.6 / 71.86° | −788.4 | 727.1 | **1.08** | 4.500 / 2928 | 0.0054 | 3.99 | 0.21 | YES |
| 8.0 | 2.096 | 3.276 / 3812.8 / 76.39° | −1112.8 | 711.7 | **1.56** | 5.373 / 2281 | 0.0312 | 3.05 | 0.39 | YES |
| 9.0 | 3.646 | 2.635 / 4266.5 / 79.64° | −1449.5 | 704.4 | **2.06** | 6.282 / 1621 | 0.1033 | 2.21 | 33.46 | YES |
| 10.0 | 5.023 | 2.257 / 4532.2 / 81.47° | −1709.8 | 702.2 | **2.44** | 7.281 / 995 | 0.4064 | 1.62 | 570.56 | YES |
| 11.0 | 6.382 | 1.989 / 4720.3 / 82.71° | −1937.3 | 701.5 | **2.76** | **never** | — | — | 1032.88 | **no** |
| 12.0 | 6.588 | 1.785 / 4863.4 / 83.63° | −2144.1 | 701.5 | **3.06** | **never** | — | — | 1038.57 | **no** |

⭐⭐⭐ **THE HORIZON RETREATS AT UP TO 2144 m/s WHILE THE MISSILE CLOSES AT 702 m/s — THREE TIMES
FASTER — AND THE FIRST LOSING ARM SITS AT A RATIO OF 1.08.** The threshold is not fitted: **the loss
happens exactly where the retreat rate crosses the closing speed**, which is the structural statement
no constant `rcs_m2` can reach at any value (a fixed horizon has `dR_acq/dt = 0`).

⭐⭐ **AND THE ARM-B TRACE IS THE ONE §0.4 PRE-REGISTERED**: lock at launch on the broadside flash →
lost while CLOSING, at 3.2–4.9 km → blind for 0.4–6.6 s → (mostly) re-gained. **A 3 g turn takes back
a lock the missile already had.**

### §4.4 — ⚠⚠ THE ADVISOR'S SECOND CORRECTION, CONFIRMED: **A RE-GAIN BEFORE CPA IS STRUCTURAL**, AND IT RE-SITES §0.6's PRIMARY GAUGE

`r → 0` while `R_acq` flattens, so **`det@CPA` is YES on every one of P0a's 96 kinematic cells and on
every wire arm out to F = 10.** ⇒ **§0.6's pre-registered primary — ‖ω_LOS‖ at the FINAL valid
measurement before CPA — is sampled in the POST-RE-GAIN stretch, where it carries no aspect
information at all.** It has to be re-sited, and P0 was built to make P1 able to (it emits EVERY
transition, not just the first). The candidate the physics hands over: **‖ω_LOS‖ and `t_go` AT
RE-ACQUISITION** — the heading error the missile discovers it has, and how little flying is left to
remove it. Both are monotone in `F` (0.0054 → 0.4064 rad/s; 3.99 → 1.62 s) and neither is the miss.
⚠ **NOT COMMITTED TO HERE — see §4.5, which finds it dt-unstable.**

### §4.5 — ⚠⚠⚠ SLICE 42's RE-FLY AT HALF `dt` — AND IT SPLITS THE MEASUREMENTS IN TWO

Re-flown at `dt = 5e-4`. **The threshold does NOT move: it sits between F = 7.0 and F = 7.5 at both
`dt`, and every quantity read AT THE LOSS INSTANT agrees to 3–4 digits** (F = 8: t 3.276 → 3.278,
r 3812.8 → 3811.3, aspect 76.39 → 76.38, ratio 1.56 → 1.56). **This is not a discretization artifact.**

⚠⚠ **BUT EVERYTHING READ AFTER THE BLIND RUN MOVES — ‖ω_LOS‖ at re-acquisition BY 3.1×, AND THE CPA ON THE SAME ROW BY 20×:**

| `F` | ‖ω‖ at re-gain, dt = 1e-3 → 5e-4 | CPA, dt = 1e-3 → 5e-4 |
|---|---|---|
| 8.0 | 0.0312 → **0.0862** | 0.39 → 0.69 m |
| 9.0 | 0.1033 → **0.3170** | **33.46 → 684.91 m** |
| 10.0 | 0.4064 → 0.3836 | 570.56 → 554.63 m |
| 11.0 | — | 1032.88 → **1197.65 m** |

⇒ ⭐⭐⭐ **A GAUGE READ AT THE MOMENT THE PICTURE IS LOST IS `dt`-STABLE; A GAUGE READ AFTER THE
COAST IS NOT.** The blind run is an open-loop integration of a frozen estimate, so anything sampled
downstream of it inherits the coast's divergence — which is **the miss ban's mechanism, in this
slice's units**, and it disqualifies §4.4's re-acquisition candidate as a headline gauge unless P1
can pin it. ⚠ **P1's gauge must be read at or before the LOSS, not at the re-gain.**

### §4.6 — §0.5's CONTROL IS NOW A MEASUREMENT, NOT AN ASSERTION

At exact broadside `rcs_aspect(σ, F, π/2) = σ` for every `F`, and `ManeuveringTarget` never reads the
missile — so every arm must fly the SAME missile until its own first loss. Measured over the prefix:

```
F=3  vs F=1, 8211 ticks:  max|Δpos| = 0.000e+00 m   BIT-IDENTICAL
F=6  vs F=1, 8211 ticks:  max|Δpos| = 0.000e+00 m   BIT-IDENTICAL
F=8  vs F=1, 3275 ticks:  max|Δpos| = 0.000e+00 m   BIT-IDENTICAL
F=10 vs F=1, 2256 ticks:  max|Δpos| = 0.000e+00 m   BIT-IDENTICAL
ABSENT KEY vs F=1:        max|Δpos| = 0.000e+00 m
```

⇒ any difference between arms is **ASPECT and cannot be geometry** (§0.5's confound, closed by
measurement rather than argument), and the draw topology is untouched (convention 3).
⚠ The absent-key arm coming out bit-identical to `F = 1` is **not** a refutation of slice 49's
`sin²+cos²` note: the gate is a threshold with kilometres of margin here, so a last-bit difference in
`rcs_eff_m2` cannot change the verdict and therefore cannot change the trajectory. The absent key
remains the WIRE's null and `F = 1` the LESSON's null.

### §4.7 — ⚠ TWO PLAN ERRORS FOUND IN THE TREE, RECORDED RATHER THAN SILENTLY FIXED

1. **⚠⚠ `t_go` IS NOT ON THIS WIRE.** §0.6 pre-registers it as a secondary gauge citing
   `missile.jl:1718` — but that line is inside `if haskey(w.env, :salvo_t_d)`, a **salvo-coordinator
   gate**. There is no coordinator in a slice 46–50 wire, so the key is absent. P0 derives it as
   `r / closing_speed` from two unconditional keys. ⚠ Whether to ship `t_go` unconditionally is a
   **gate-1 decision**, not a P0 blocker — and it is a real candidate, since it is free.
2. **The kinematic stand-in and the flown wire disagree on WHERE the threshold sits.** `p0a2_cell.jl`
   predicted a loss at F = 6 (2.14 s blind); the real PN missile through a 6-DOF airframe closes
   differently and F = 6 never loses. ⇒ **the pre-flight gate is a CELL PICKER and nothing more** —
   quoting its blind durations as results would be quoting a point-mass.

### §4.8 — THE STATE OF THE GATE

- **P0: PASSED, and arm B is selected — SCOPED TO F ≤ 10** (⚠ §4.9/§4.10 correct this paragraph as
  first written, which claimed arm A was refuted outright). Over F = 7.5–10 every arm acquires at
  launch, is LOST WHILE CLOSING, and re-acquires before CPA: **the surviving claim is about a lock
  that is TAKEN BACK, which a fixed horizon cannot do at any value**, and P2 is answered by proof
  there — the stronger form, exactly as slice 49 §5 was. ⚠⚠ **At F ≥ 11 the missile never re-acquires
  and that IS arm A, where §0.2's secondary kill does come due.**
- **STILL OPEN: P1 (the gauge) and P3 (the substitution test).** §4.5 has already disqualified the
  obvious candidate; §0.6's pre-registered primary is disqualified by §4.4. **The slice does not have
  a gauge yet, and §0 says that is the whole remaining question.**

### §4.9 — ⚠⚠⚠ THE TOP OF THE SLIDER IS A **DIFFERENT MECHANISM**, AND IT IS NOT A PLATEAU (advisor; `p0d_armA.jl`)

§4.8 as first written said arm A (denial — never a usable lock) is refuted. **It is not: F = 11 and
F = 12 ARE arm A.** They go blind, NEVER re-acquire, fly the rest of the engagement on a frozen
estimate and miss by ~1030–1040 m. §4.8's "every arm out to F = 10 re-acquires" is true and does not
generalise. The pre-registered slider (§0.7: floor 1.0, ceiling ~12) therefore spans **three
regions**, which is slice 48's own shape and has to be NAMED as three rather than described as arm B
with a tail:

| region | what happens |
|---|---|
| **F ≤ 7.0** | ⭐ **A TRUE NULL** — never loses the lock at all. CPA 0.40 m, and `max\|Δpos\| == 0` across every arm in it (§4.6). Exactly what ships without this slice. |
| **F = 7.5 – 10** | ⭐⭐⭐ **ARM B** — the lock is TAKEN BACK while closing, and then GIVEN BACK. |
| **F ≥ 11** | **ARM A** — taken back and never given back; blind through CPA. |

**AND THE TOP REGION IS NOT A BIT-IDENTICAL PLATEAU** — this is where it differs from slice 48's
floor, and the difference matters:

| `F` | 10 | 11 | 12 | 14 | 16 | 20 | 30 |
|---|---|---|---|---|---|---|---|
| re-acquires? | YES | **no** | **no** | **YES** | **no** | **no** | **no** |
| CPA m | 570.56 | 1032.88 | 1038.57 | **618.21** | 1670.86 | 1505.30 | 1814.44 |
| `max\|Δpos\|` vs F = 11 | — | 0.0 | 17.8 m | 342.7 m | 454.7 m | 469.5 m | 706.5 m |

⚠⚠ **RE-ACQUISITION IS NON-MONOTONE ABOVE F = 11 (F = 14 re-acquires while 12 and 16 do not) AND SO
IS THE MISS (1033 → 1039 → 618 → 1671 → 1505 → 1814).** That is not a lesson, it is a divergence
being sampled — the coast is an open-loop integration of a frozen estimate, and where it happens to
put the missile at CPA is chaotic in the initial condition. ⇒ **§0.6's miss ban applies to the top of
this slider with full force, and the slider's TEACHABLE domain is F ≤ ~10.**

⭐⭐⭐ **AND THE SAME TABLE CARRIES THE OPPOSITE FINDING, WHICH IS THE USEFUL ONE: THE LOSS INSTANT
IS PERFECTLY MONOTONE ALL THE WAY OUT.** t 2.257 → 1.989 → 1.785 → 1.490 → 1.283 → 1.007 → 0.657 s
and r 4532 → 4720 → 4863 → 5070 → 5216 → 5410 → 5657 m, without a single reversal, over a domain on
which the miss reverses four times. **Everything upstream of the blind run is orderly; everything
downstream of it is noise.**

### §4.10 — ⚠ THREE CORRECTIONS TO §4.4–§4.8 (advisor)

1. **⚠ §4.5's "moves by 3×" UNDERSTATES IT, AND THE BIGGER NUMBER IS THE POINT.** Both are real and
   they are different quantities: ‖ω_LOS‖ at re-acquisition moves **3.1×** (F = 9: 0.1033 → 0.3170),
   while the **CPA on that same row moves 20×** (33.46 → 684.91 m). The 20× is the damning one and is
   the miss ban's mechanism stated in this slice's units.
2. **⚠⚠ §4.8's "arm A is refuted" IS RETRACTED, SCOPED TO F ≤ 10.** §0.2's secondary kill (*a
   late-or-never lock is reproducible by a smaller constant `rcs_m2`*) **does come due at F ≥ 11**,
   because a never-re-acquiring engagement is exactly what a constant horizon produces. ⇒ **P2 is
   answered by proof ONLY for the retreat itself** (a fixed horizon has `dR_acq/dt = 0`, so it cannot
   take a lock back mid-flight at any value). The surviving claim is scoped to the arm-B region, or
   P2 must be run as a constant-`rcs_m2` comparison against the top of the slider.
3. **⚠ THE RE-ACQUISITION GAUGE (§4.4) IS RETIRED, NOT DEFERRED.** It was the advisor's own
   suggestion and §4.5 measured it `dt`-unstable; it does not go forward into P1 as a live candidate.

### §4.11 — ⭐⭐ THE GAUGE P1 SHOULD TEST FIRST, AND IT IS ALREADY IN §4.3's TABLE

Everything §4.4 and §4.5 disqualified was read AFTER the picture was lost. The one quantity in the
data that is read **at** the loss — and therefore survives both — is **the RETREAT RATIO
`|dR_acq/dt| / V_c` at the instant the lock is taken back**:

- **monotone** over the whole domain: **1.08 → 1.56 → 2.06 → 2.44 → 2.76 → 3.06** (F = 7.5 → 12), no
  reversal, unlike authority (48), the loss count (49), `k` (28), `ω_n` (40) or `σ_seek` (25);
- **`dt`-stable to 3 digits** (F = 8: 1.56 → 1.56 at half `dt`) — §4.5's own bar;
- **both terms are SHIPPED WIRE KEYS** (`seeker_r_acq_m`, `closing_speed`), so it is a difference of
  telemetry, not a recompute (convention 10);
- **it is a state of the engagement geometry, not a function of the 0/1 detection trace** — which is
  §3 correction 1's exact bar, the one that disqualified guided-time and slice 49's loss run;
- **and it passes §0.2's substitution test in a way the plan did not anticipate.** Swap "seeker" for
  "radar": *a ground radar has no `V_c` that means anything* — it is not on a collision course, so
  there is nothing for the retreat rate to be measured against. The ratio is only defined for a
  sensor that is CLOSING ON WHAT IT IS LOOKING AT.

⚠ **NOT PRE-REGISTERED AS THE PRIMARY HERE** — a gauge chosen after seeing the data is a gauge fitted
to it, and P1 has to test it against the §0.6 bar properly, including whether it is a LESSON gauge or
only a diagnostic. Recorded now because §0.6's own primary and §4.4's replacement are both dead, and
P1 should not start from nothing.

---

## §5 — P1 PRE-REGISTERED (2026-08-26, advisor). ⚠ WRITTEN BEFORE THE PROBE RAN.

§4.11 nominated the retreat ratio `|dR_acq/dt| / V_c` **at the loss instant**. That version has a
defect §4.11 did not name: **it is UNDEFINED on F ≤ 7**, the region that ships today (§4.9's true
null). A gauge with no value on the null cannot be a slider's axis. P1 therefore tests the
**generalised** form.

### §5.1 — THE CANDIDATE, RESTATED AS A SERIES

`ratio(t) = |dR_acq/dt| / V_c`, evaluated **every tick over the closing phase**, and the gauge is its
**MAXIMUM**. Defined on every arm including the sphere (where `R_acq` is constant, so it is 0).

⭐⭐ **AND THAT TURNS A DESCRIPTION INTO A PREDICTION.** The at-the-loss version can only be read on
arms that already lost; the max can be read on arms that did not, and then asked whether it crossed
1.0 exactly where the losing starts. **That is the whole of P1.**

### §5.2 — ⚠⚠ THE `dt` TRAP THAT IS SPECIFIC TO A MAX, AND THE ESTIMATOR THAT AVOIDS IT

§4.5's re-fly showed at-the-loss quantities are `dt`-stable. **A MAX IS A DIFFERENT ESTIMATOR AND
DOES NOT INHERIT THAT.** Halving `dt` doubles the sample count, and *a max over a noisier series is
biased upward by construction* — so a naive per-tick difference would manufacture a `dt`-dependent
number and could retire the best candidate in the slice for a reason that is the probe's, not the
physics'.

⇒ **`dR_acq/dt` IS TAKEN OVER A FIXED 10 ms CENTRED WINDOW, NOT PER TICK** (±5 ticks at `dt` = 1e-3,
±10 at 5e-4). The estimator is fixed in TIME, so halving `dt` leaves it unchanged. ⭐ **THE
TRANSFERABLE FORM: when a gauge is an EXTREMUM of a differenced series, the differencing window is
part of the gauge and must be pinned in SECONDS, not in ticks.**

### §5.3 — WHAT ELSE THE TABLE MUST CARRY (and why each earns its column)

| column | why it is there |
|---|---|
| ⭐ **max `ratio`** | the candidate (§5.1). Reported over the pre-loss prefix AND over the whole closing phase, because everything after the loss is a blind coast whose geometry is contaminated (§4.5). |
| **‖ω_LOS‖ AT THE LOSS INSTANT** | ⚠⚠ **§0.6's PRE-REGISTERED PRIMARY, RE-SITED.** §4.4 disqualified it *at the final valid measurement* (sampled post-re-gain, carries no aspect information) and never tested it at the LOSS — which is §4.5's `dt`-stable side. **A gauge picked after seeing the data is fitted to it; the defence is reporting the pre-registered one correctly sited, not replacing it silently.** |
| **min `R_acq / r`** | ⚠ **THE TAUTOLOGICAL ALTERNATIVE, ON THE RECORD ON PURPOSE.** Defined everywhere and crosses 1.0 at the loss BY CONSTRUCTION. It loses to the retreat ratio on exactly ONE bar — §0.2's substitution test, since a ground radar has `R_acq/r` and no `V_c` worth measuring against. Omitting it would leave a reader asking why the obvious gauge was not used. |
| **F = 6.5 and 7.0** | ⭐ **THE REAL CONTROL.** §0.5's control is `F = 1`, where max-ratio is identically 0 — a trivially large separation that proves nothing. 6.5/7.0 are the SAME mechanism, sub-threshold. |

### §5.4 — ⚠⚠ A CORRECTION TO §4.3 BEFORE IT IS QUOTED AS A RULE

§4.3 says *"the loss happens exactly where the retreat rate crosses the closing speed."* **That is
false as written and §4.3's own table refutes it** — F = 12 loses at ratio 3.06, F = 7.5 at 1.08. The
loss is a **LEVEL crossing** (`r` rises above `R_acq`), not a rate crossing.

⭐⭐⭐ **WHAT IS TRUE IS ABOUT THE THRESHOLD IN `F`, AND IT IS THE BETTER FACT: THE ONSET IS A
TANGENCY.** At the marginal arm the two curves just touch — so their derivatives match there and the
ratio → 1. That is why F = 7.5 reads **1.08 with only 0.377 s blind**, and why the number is not
fitted. ⚠ Quote the tangency, never the "every loss happens at ratio 1" form.

### §5.5 — ⚠⚠⚠ THE VERDICT RULE, FIXED HERE, BEFORE THE OUTPUT IS READ

| # | test | bar |
|---|---|---|
| 1 | **MONOTONE** in `F` over 1 – 12 | no reversal (28/40/25/48/49 precedent) |
| 2 | **`dt`-STABLE** | moves **< 1 %** at half `dt` — §4.5's own bar, and §5.2's estimator is what makes it a fair test |
| 3 | ⭐ **PREDICTIVE** | the `F` at which max-ratio first crosses **1.0** lands in **(7.0, 7.5]** — the same interval as the observed first loss |

- **ALL THREE ⇒ HEADLINE GAUGE.**
- **1 and 2 but NOT 3 ⇒ DIAGNOSTIC ONLY**, and the ledger says so in those words; the fallback is
  §1's named one — guided time WITH §3 correction 1's admission written in.
- **FAILS 1 or 2 ⇒ DEAD**, and the slice has no gauge, which by §0 is the whole remaining question.


---

## §6 — P1 HAS RUN (2026-08-26). ⚠⚠⚠ **THE RETREAT RATIO IS MONOTONE, `dt`-STABLE — AND IT DOES NOT PREDICT THE LOSS.**

**Probe:** `M:\claud_projects\temp\slice50\p1_gauge.jl`, on P0's wire, 12 arms × 2 `dt`.

### §6.1 — THE TABLE (`dt` = 1e-3; the half-`dt` re-fly agrees to the digits shown)

| `F` | lost? | ⭐ **max ratio** (pre-loss) | max ratio (whole flight) | **min `R_acq/r`** (pre-loss) | min `R_acq/r` (whole) | ‖ω_LOS‖ AT LOSS | aspect at loss |
|---|---|---|---|---|---|---|---|
| 1.0 | no | **0.0000** | 0.0000 | 1.3212 | 1.3212 | — | — |
| 3.0 | no | **1.0975** | 1.0975 | 1.3212 | 1.3212 | — | — |
| 5.0 | no | **1.7841** | 1.7841 | 1.3212 | 1.3212 | — | — |
| 6.0 | no | **2.0792** | 2.0792 | 1.2028 | 1.2028 | — | — |
| 6.5 | no | **2.2189** | 2.2189 | 1.1273 | 1.1273 | — | — |
| 7.0 | no | **2.3544** | 2.3544 | 1.0594 | 1.0594 | — | — |
| **7.5** | **yes** | **2.4861** | 2.4861 | **1.0000** | 0.9982 | 0.00468 | 71.86° |
| 8.0 | yes | **2.6148** | 2.6148 | 1.0000 | 0.9440 | 0.00778 | 76.39° |
| 9.0 | yes | **2.8635** | 2.8635 | 0.9999 | 0.8463 | 0.01218 | 79.64° |
| 10.0 | yes | **3.1028** | **123.32** | 0.9998 | 0.7511 | 0.01560 | 81.47° |
| 11.0 | yes | **3.3346** | **80.29** | 0.9999 | 0.5994 | 0.01847 | 82.71° |
| 12.0 | yes | **3.5601** | **67.42** | 1.0000 | 0.5476 | 0.02094 | 83.63° |

### §6.2 — SCORED AGAINST §5.5, WHICH WAS FIXED BEFORE THIS RAN

| # | test | result |
|---|---|---|
| 1 | monotone in `F` over 1–12 | ✅ **PASS** — no reversal, 0.00 → 3.56, and *strictly* increasing on every step |
| 2 | `dt`-stable, < 1 % at half `dt` | ✅ **PASS** — worst **0.064 %**. §5.2's fixed-window estimator did its job |
| 3 | ⭐ the 1.0 crossing lands in (7.0, 7.5] | ❌ ⚠⚠⚠ **FAIL — IT CROSSES IN (1.0, 3.0], FIVE SLIDER STEPS EARLY** |

⇒ **BY §5.5's OWN PRE-REGISTERED RULE THE RETREAT RATIO IS A DIAGNOSTIC, NOT A HEADLINE GAUGE.**
Recorded as a fail rather than argued around: the rule was written down first precisely so this
reading could not be renegotiated after the fact.

### §6.3 — ⭐⭐⭐ **AND THE FAILURE IS THE MOST TRANSFERABLE THING IN THE SLICE: A RATE CANNOT PREDICT A LEVEL CROSSING WITHOUT THE HEADROOM.**

§5.4 already retracted "the loss happens where the retreat rate crosses the closing speed." **§6.1
shows how badly:** at `F = 3` the target's visibility horizon is retreating **1.10× faster than the
missile is closing** — and the missile never loses the lock, not for one tick. At `F = 5` it retreats
**1.78× faster** and still never loses it. The lock survives because the horizon **started 32 %
above the range** (`min R_acq/r` = 1.3212 = `R_b/r₀` = 8079 / 6115, the launch condition itself).

⇒ **the retreat ratio measures HOW HARD THE TARGET IS PUSHING; the margin measures WHETHER IT
WORKED.** They are different questions and only the second one has a threshold in it. ⭐ **The
transferable form, for `docs/LESSONS.md`: a RATE gauge and a LEVEL event are not interchangeable —
a rate can exceed its comparator for the whole flight and never produce the event, and the missing
term is the HEADROOM the level started with.**

### §6.4 — ⚠ WHAT §6.1's OTHER TWO COLUMNS SAY (both fail, and each for its own reason)

- **`min R_acq/r`, the tautological alternative (§5.3).** Pre-loss it is **flat at both ends and
  resolves only over `F` = 6 – 7.5**: below 6 the minimum sits **at t = 0** (identical 1.3212 on
  three arms with completely different aspect histories — it is reading the LAUNCH, not the
  encounter), and at/above 7.5 it is pinned at 1.0000 **by construction**, because the pre-loss
  prefix ends at the level crossing. ⚠ A gauge with resolution over one and a half slider steps is
  §0.7's "switch, not a slider."
- **The same quantity over the WHOLE flight** does keep falling (0.998 → 0.548, monotone) —
  ⚠⚠ **and it is `dt`-UNSTABLE exactly as §4.5 predicts**: F = 9 moves 3.1 %, F = 11 **7.3 %**,
  F = 12 **14.7 %**. It is sampled downstream of the blind coast. **FAILS §5.5 test 2.**
- **‖ω_LOS‖ AT THE LOSS — §0.6's pre-registered primary, correctly re-sited (§5.3).** ⭐ On the
  domain where it exists it is **monotone (0.00468 → 0.02094) and `dt`-stable to ≤ 0.4 %** — so
  §4.4's disqualification was of the SITING, not of the quantity. ⚠ But it is **undefined on
  `F` ≤ 7**, which is §5.1's original objection to the at-the-loss form, unchanged.
- ⭐⭐ **AND THE WHOLE-FLIGHT max ratio CONFIRMS §4.5 A THIRD TIME**: it explodes to **123 / 80 / 67**
  on exactly the arms with long blind runs, and those values move by **21 % / 31 % / 22 %** at half
  `dt`. Everything downstream of the coast is divergence being sampled. **The pre-loss prefix is not
  a convenience, it is the measurement.**

### §6.5 — THE STATE OF THE GATE AFTER P1

- **P0 PASSED** (arm B, scoped to `F` ≤ 10). **P1 RAN AND ITS CANDIDATE FAILED TEST 3.**
- **Every gauge proposed so far is now measured**: §0.6's primary (mis-sited → re-sited → monotone
  but undefined on the null), §4.4's re-acquisition version (`dt`-unstable, retired §4.10), §4.11's
  at-the-loss ratio (undefined on the null), §5.1's max-ratio (diagnostic, not predictive), the
  tautological margin (flat at both ends, or `dt`-unstable). **§5.5's named fallback — guided time
  WITH §3 correction 1's admission — is now the live option, and it is the weak one.**
- ⚠ **STILL OPEN: the gauge, P2, P3.** §0 says the gauge IS the remaining question.

