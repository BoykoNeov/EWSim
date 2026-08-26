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
unambiguous"*), and turns its nose toward the missile during the flight. ⚠ 46's law still binds: the
engagement must be launched OUTSIDE the sensor's horizon or the gate is deciding nothing — which
means slice 47's midcourse phase is not optional staging here, it is the precondition.

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
| ⭐ **GUIDED TIME BEFORE CPA** (seconds with `seeker_detect == 1` and a valid measurement, pre-CPA) | **PRE-REGISTERED PRIMARY.** It is an ENGAGEMENT quantity a ground radar cannot have (§0.2's test), it is what arm B's sentence is actually about, and it should fall monotonically as the body gets slenderer. ⚠ P1 must MEASURE that monotonicity, not assume it — `k`(28), `ω_n`(40), `σ_seek`(25) and 49's own loss COUNT are the precedents. |
| **RANGE AT FINAL LOCK** (the last time the gate closes before CPA) | **PRE-REGISTERED SECONDARY / READOUT.** Names *where* the engagement went blind, in metres, which is how the HUD will have to say it. |

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
| **P1** | Is GUIDED TIME BEFORE CPA monotone in `F`, and does it separate from the `F = 1` control flying the identical manoeuvre? | **THE GAUGE.** A non-monotone gauge is not a domain (28/40/25 precedent) — and this slice has no fallback gauge left (§0.6). |
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
