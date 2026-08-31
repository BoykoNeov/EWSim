# EWSim — the deferral ledger (what to build next, and what is already DEAD)

**Read this BEFORE planning a new slice.** It is the backlog *and* the kill list: several
entries below are candidates that were probed and REFUTED, with the refutation written down.
Re-importing a framing this file marks as killed is how a slice gets burned (slice 39 was
exactly that failure, and the check that killed it was already written down).

Companion files: `docs/SLICES.md` (what each shipped slice's lesson was), `docs/STATUS.md`
(gate-by-gate as-built detail, grep `## Slice N`), `docs/plans/sliceN.md` (per-slice plans and
gate-0 probe records — including the kill records for slice 37's memory-track probe and slice
39's nulling loop), `HANDOFF.md` (frozen architecture).

A short, always-loaded summary of the hardest kills lives in `CLAUDE.md` under
**"Dead ends — do not rebuild"**. That list is deliberately lossy; this file is the detail.

---

## ⭐⭐⭐ THE 2026-08-18 RE-VERDICT — TWO AIMS, TWO TESTS, TWO VERDICTS

**Written after the user's reframe: EWSim is a teaching instrument AND a simulator** — different
scenarios, different models, different subcomponents, different imperfections. **Slices 41–45 were
all killed at gate 0 by tests that measure LESSON value only** (*reparameterizable*, *moves no
verdict*, *false-fidelity knob*), and the word DEAD was applied to the COMPONENT. That was wrong,
and this section is the correction. The criterion now lives in `CLAUDE.md` as well.

- **MODEL test** — is the parameter READ by the physics every tick, and does the response obey its
  own units / signs / frames? **Failing this is the ONLY outright kill** (a knob consumed once at
  load and never read again is a BUG, not a feature — `speed` 19, launch altitude 21, the handover
  bias key 36, `ζ` on the lag rung 40, `k_δ` 15, `(R̂,s)` 31 all fail here and STAY dead).
- **LESSON test** — does dialing it move the authored scenario's headline metric? Failing this kills
  **the slice's HEADLINE**, not the hardware.

⇒ **PASS model / FAIL lesson ⇒ "DEAD AS A LESSON, ALIVE AS A MODEL": it ships as physics + tests +
authorable keys, and the refuted lesson claim stays buried in its plan file with its refutation
intact.** ⚠ This does NOT lower the bar for new proposals (read by the physics, correct in its own
units, or no ship), and a reparameterization still must not ship as an **ARCHITECTURE** — slice 39's
discipline survives untouched. What dies is the inference *"it did not move the miss on this one
scenario, therefore the component does not exist."*

⚠⚠ **AND THE STRUCTURAL POINT UNDER ALL FIVE: FOUR OF THEM FAILED THE LESSON TEST AGAINST THE SAME
SCENARIO** — the 6.4 km / 8.9 s terminal shot slices 26–45 all fly, chosen at slice 26 for the radome
loop. A component measured inert on ONE authored engagement has been measured on one engagement.
(Slice 45's own PART IV lesson — *a property measured in one operating mode is not a property of the
component* — is this same error one level down, and it was written the day before this reframe.)

### The five re-verdicts

| slice | candidate | MODEL test | LESSON test | RE-VERDICT |
|---|---|---|---|---|
| 41 | second-order fin actuator | **PASS** — kernel clean, seam bit-exact across five `:delta_cmd` writers, physics real (a lag inside the MAIN loop DEstabilizes: 1.27–4.45× ring growth at 60→20 Hz, `R_crit` walks −0.0926 → −0.0901) | FAIL — two `(k_α,k_q)` retunes reproduce the whole curve to 0.00–1.01 % | **DEAD AS A LESSON, ALIVE AS A MODEL.** ⚠ Scope the equivalence honestly: it was MEASURED on a loop whose fin command is a single 1.6488 Hz line, and whether it survives a BROADBAND loop is UNPROVEN — the one available probe (halving `af_I` moves the ring to 2.7503 Hz and the matched gain pair over-shoots 27–47 %) is CONFOUNDED, because `af_I` moves the plant as well as the frequency. Ships as authorable actuator hardware; must NOT ship as "the fin architecture". |
| 42 | acquisition knife-edge | **FAIL** — the effect's width is `ω_LOS·dt`, ONE integration step, and HALVES when `dt` halves | FAIL — the "worthless lock" cell's miss is BYTE-IDENTICAL to the never-locks cell | **DEAD UNDER BOTH AIMS — the only genuine kill of the five.** There is no component here, only a discretization artifact. Nothing to author, nothing to ship. |
| 43 | seeker search pattern | **N/A** — never a physics kill; it shipped a LAW (`travel = deficit/(1−ω/ρ)`, `ρ* = min_t […]`, confirmed 4/4 on untuned geometries) | ~~BLOCKED~~ **UNBLOCKED by slice 47 (2026-08-25)** | **NOT A KILL AT ALL — was BLOCKED, law banked, and 47 supplied both missing halves (a midcourse to search FROM, and a slider that authors the deficit).** ⚠ The block is a property of the ENGAGEMENT, not of searching: a search costs time, and time is worthless when you were launched already able to see. |
| 44 | seeker detection range / SNR | **PASS, EXACTLY** — `R_acq·fov` constant to 0.0000 %, log-log slope −1.000000, `r_acq` vs `snr_freespace` at +10.0000 dB; the plan says it outright: *"the physics is not what failed, what failed is the WIRE"* | FAIL — an 8079 m seeker against a 6437 m launch ⇒ the gate is byte-identical to no gate | **DEAD AS THE UNBLOCKER, ALIVE AS A MODEL — and arguably the biggest miss of the five.** A seeker with a detection horizon is not optional equipment for a simulator meant to carry different seekers against different targets at different ranges. `lib44.jl` is written and measured correct. ⚠ Its two survivors stand regardless (a late lock is paid in MANOEUVRE AUTHORITY and miss cannot show it; the narrow-window failures of 32/34 are the SERVO's). |
| 45 | rectangular / per-axis window and stop | **PASS, BOTH HALVES** — the elevation stop BINDS 66–68 % of in-band ticks (read, clamping, working hardware); the box changes ACQUISITION on a searching head (disc never locks 305.11 m, box hits 0.24/0.23/0.15) | FAIL (stop) / CONDITIONAL (window) — miss 0.1912 m at every el stop over a 750× range; box ≡ disc byte-identically on 8/9 TRACKING rows | **BOTH HALVES DEAD AS A LESSON, BOTH ALIVE AS A MODEL.** ⚠ "The 7th false-fidelity knob" is a MISNOMER and must not be quoted: the other six were never READ; this one is read and binds two-thirds of the ticks. An azimuth ring and an elevation trunnion are independent mechanisms with independent authorable travel — that is hardware variety, which is the simulator's whole point. |

### The OLDER kills, swept under the same two tests (2026-08-18)

The reframe applies backwards, not only to 41–45. Every kill on the list was re-read and sorted by
the MODEL test. ⚠ Nothing below is a new measurement — this is a re-classification of records that
already exist, and each row names where its evidence lives.

**A. ALIVE AS A MODEL — killed for LESSON reasons, the hardware is real and (mostly) already written:**

| candidate | why it was killed | why it survives the MODEL test |
|---|---|---|
| **The ANGLE-DOMAIN radome corrector** (slice 27 gate 0, `docs/plans/slice27.md` §146–158) | It fails: the onset residual DRIFTS (−0.095 → −0.005 as `R̂` 0 → −0.30) and at PERFECT knowledge `R̂ = R = −0.50` it RINGS (rms 0.844, miss 131 m) where the rate arm is quiet (0.014). | ⭐ **It was BUILT and it fails PHYSICALLY, for a stated reason** (it needs the look angle and can only see it through the bend it is removing; the error is second order in `R·R̂`). That is a legitimate authorable **inferior design**, and a simulator that only carries designs that work cannot show why the shipped one is shipped. Ships as an alternative compensator rung, NOT as the default. ⚠ The general rule it taught (*compensate with a signal not itself corrupted by what you are compensating*) is unaffected either way. |
| **MEMORY TRACK / a COASTING head** (slice 37 gate 0, 5 probes, `docs/plans/slice37.md`) | Mis-located: a break in this arc is not an episode but the rest of the flight (`coast_max` 6.0–7.9 s, `nreacq` 0 on every arm), so the cure belongs to the ESTIMATOR's frozen rate, not the head. | ⭐ Real seekers coast, and the HONEST coast was built (the head follows the tracker's coasted inertial estimate through the current attitude) — it rescued ONE boundary cell of fifteen. **Rescuing one cell is a small effect, not a non-existent one.** Ships as head behaviour; ⚠ its LESSON claim stays dead, and the estimator-side slice remains the real cure. |
| **A SCALAR RATE-LIMITED FIN inside the coupled loop** (slice 20 gate 0, 4 probes) | `δ_max` structurally SHADOWS `δ̇_max` — the fin only needs to move fast when the command does, which needs high `k_α` or low damping, and both peg DEFLECTION first. | ⚠ The rate limit is SHIPPED already (slice 15's `fin_autopilot_step`, `δ̇_max` with `rate_sat` telemetry) — what died was making it the *lesson of the coupled loop*. **Shadowed at the tunings tried is not absent**, and the shadowing is itself a fact worth authoring. Low priority: nothing new to build. |
| **GYRO NOISE** | Deferred on DRAW-TOPOLOGY grounds — an unconditional third `randn` desyncs every 25–31 replay. | ⚠ A **plumbing** constraint, not a physics verdict, and the pattern that solves it already exists (slice 13's `:scan` 4b shape). ⚠ Slice 25's ~1000:1 roll-loop low-pass says probe first — it may still be inert, but inert-and-modelled is the point of this reframe. |
| **LAUNCH ALTITUDE** (slice 21, listed as a false-fidelity knob) | The knob's comp key did not exist — caught the same way as 19's `speed`. | ⭐⭐ **THIS ONE IS A MODEL GAP WEARING A DEAD-KNOB LABEL.** `_integrate_6dof!` (`missile.jl:479`) passes a CONSTANT `rho` to `total_accel`, and its own comment says the stage position `P` is *"threaded for the `rk4_6dof` contract and reserved for a future ρ(z) on this path"*. So on the path the ENTIRE 26–45 arc flies, altitude changes nothing — while `_integrate_coupled!` DOES call `air_density(P[3])`. Altitude cannot be a knob until that seam is closed, and the seam is already threaded. ⚠ Distinct from the point-mass/ballistic path gap (which touches slice 8's `rk4_step` byte-identity surface) — the 6-DOF one does not. |

**B. CORRECTLY DEAD — they fail the MODEL test, and the reframe does not touch them:**

- **The ACQUISITION KNIFE-EDGE** (42) — the effect's width IS the integration step (`ω_LOS·dt`, halves when
  `dt` halves, 0.0036° at the shipped step) and the cell's miss is byte-identical to the never-locks cell.
  **No component exists to author.** The only genuine kill of 41–45.
- **`speed`** (19) — a live `set_param` wrote a comp key **no consumer reads**. A plumbing BUG, and it was
  FIXED (`rho` became the live lever, with a tripwire asserting the knob MOVES `a_max_aero`).
- **`k_δ`** (15) — cancels EXACTLY in the algebra (`τ_s·δ̇ = δ_cmd − δ` with `a = k_δ·δ` collapses to the
  `:pid` plant relabelled, maxdiff ~3.8e−13). Not an independent parameter — there is nothing to author.
- **`ζ` on the LAG rung** (40) — a first-order lag HAS no damping parameter; the slider is inert because the
  model genuinely lacks the term. A rung-scoping matter, correctly handled.
- **The NULLING-LOOP head servo** (39) — an algebraic IDENTITY with the shipped feed-forward under
  transformed parameters (`nulling(τ,s,b) ≡ feed-forward(τ(1+s), 0, b/(1+s))`, 5.8e−09 m over 12000 ticks).
  A reparameterization, not a component. ⚠ FINITE loop gain remains unproven and un-killed.
- **A CUBIC radome curve** — unbounded slope, the bend DIVERGES, no valid domain. An unphysical model.

**C. NEVER A COMPONENT KILL — a different class, and nothing to resurrect:**

- **The NON-MONOTONICITY disqualifications** — `k` (28), `ω_n` (40), `σ_seek` (25), and the miss-vs-`K` /
  miss-vs-`α_stall` reversals (20, 22). ⭐ **Every one of these is SHIPPED PHYSICS.** What was rejected is
  their use as the SHOWCASE SLIDER (*a domain that reverses the lesson is not a domain*) — a statement about
  teaching, which the reframe leaves standing. The components are alive and always were.
- **The SEARCH PATTERN** (42/43/45) — blocked, never killed, and its law is banked.
- **The `SEEKER NOISE × BTT ROLL LOOP` coupling** — the noise itself is shipped (25); what was killed is a
  CLAIM about a coupling (~1000:1 low-pass, std 1.07 vs 1.6e−5), not a part.

⭐⭐ **THE PATTERN ACROSS BOTH SWEEPS: the genuine kills are ALGEBRAIC OR NUMERICAL** (a cancellation, an
identity, a discretization artifact, a divergence, an unread key) — **and every kill that was PHYSICAL was
really a statement about the authored scenario.** That is the cheapest available test of whether a kill is
about the model or about the wire, and it is worth applying to the NEXT one before writing it down.

### What this changes about what to build

⭐ **Three of the five have PROBE CODE THAT ALREADY WORKS**, in `M:\claud_projects\temp\slice41`,
`…\slice44` (`lib44.jl` + patched `missile.jl`), `…\slice45` (patches + eight probes). Their cost is
**productionization** — wire, test, author, document — **not re-derivation.** ⚠ Verify each against
the current HEAD before reuse; they were written against the tree as it stood on 2026-08-18.

⭐⭐ **A NEW SLICE SHAPE THIS REFRAME MAKES LEGAL: A COMPONENT-FIDELITY SLICE.** Ship the hardware
(detection horizon, actuator inertia, per-axis travel) with tests and authorable keys, and let the
LESSON be *"here is the hardware, here is the regime where it bites, and here is the measured regime
where it does not"* — the null result becomes part of the shipped documentation rather than a reason
not to ship. ⚠ Convention 9 (**one lesson per scenario**) still governs the SHOWCASE; it does not
govern what the core is allowed to model.

---

The NEXT named candidates:
⚠⚠ **RE-VERDICT 2026-08-18 — see §"THE 2026-08-18 RE-VERDICT" at the top of this file: DEAD AS A LESSON, ALIVE AS A MODEL. The refutation below stands as written and is load-bearing; what changed is that it kills the SLICE'S HEADLINE, not the component.**
**(⚠⚠⚠ "A SECOND-ORDER FIN ACTUATOR" IS NO LONGER ON THIS LIST — IT IS **DEAD**, KILLED AT GATE 0 ON
2026-08-18 (`docs/plans/slice41.md`), and it is the deferral SLICE 40 NAMED AS ITS OWN. **Do not
rebuild it as written.** Give slice 15's fin an INERTIA the way slice 40 gave the gimbal one, and the
kernel is clean, the seam is clean (nine wires bit-exact across five distinct `:delta_cmd` writers)
and the PHYSICS IS REAL — the inherited sign even inverts, which is the headline the plan hoped for:
a lag on the head's feed-forward path was *"silently doing stability work"*, but the same component
inside the MAIN control loop **eats phase margin and destabilizes** (at one step inside slice 26's
boundary the ring goes 1.27× / 1.58× / 1.93× / 4.45× at 60 / 40 / 30 / 20 Hz, monotone and unclamped,
and `R_crit` walks −0.0926 → −0.0901: *a cheaper actuator needs a better radome*).
**IT DIES ON REPARAMETERIZATION ANYWAY**: two independent single-axis `(k_α, k_q)` retunes each
reproduce the actuator's ENTIRE threshold curve to **0.00–1.01 %**, against a falsifier of 2.7–3.2 %
fixed in writing one commit before the measurement existed. ⭐⭐ **AND THE REASON IS THE PART TO CARRY
FORWARD: a pole differs from a gain ONLY in that its phase VARIES with frequency, and that loop's fin
command is a single 1.6488 Hz line — one point of a phase curve is a number, which is what a gain is.**
Slice 38's *"`s` adds PHASE and scaling a slope cannot"* is TRUE and has teeth only where the loop is
BROADBAND. ⚠ Before proposing ANY new dynamic element on this family, run the spectrum probe first
(`p2_spectrum.jl`): a single-line spectrum predicts this kill before a kernel is written.)**

**⭐ THE ONE LIVE SUCCESSOR SLICE 41 LEAVES — *A SLICE WHOSE LESSON IS THE FREQUENCY DEPENDENCE
ITSELF*.** §IV.4's explanation makes a falsifiable prediction, and §IV.8d has a measured hook for it:
halving `af_I` moves that ring **1.6488 → 2.7503 Hz** while leaving the onset essentially put (slice
26's own *"the threshold is the guidance loop's, not the airframe's"*), and there the gain pair that
matched the actuator to 2.6 % **over-shoots it by 27 %** (47 % on the other axis) — the sign a phase
lag predicts and a gain does not. ⚠⚠ **IT IS CONFOUNDED AND IT IS NOT A CLAIM**: changing `af_I`
changes the PLANT, not only the ring frequency, so *"the pair no longer matches"* has two live
explanations. What this candidate needs before it is worth a slice is **a way to move the ring
WITHOUT moving the plant** — and it starts its own gate 0 from zero, with a fresh falsifier. ⚠ Its
first probe is NOT a kernel: it is the two-frequency separation, on the shipped wire, with the plant
held. If that cannot be built, the candidate dies with it.

**⚠ AND ONE ROUTE IS ALREADY CLOSED FOR IT: `slice40_resonance` IS NOT THE SECOND WIRE.** Its design
is COMPENSATED (`R̂ = −0.18` against a worst slope of −0.33), so there is no parasitic margin for an
actuator to eat and its ring is the gimbal servo's own resonance. Measured: the actuator moves it
**0.992×** and the gain pairs 1.009× / 1.006× — every arm within 0.9 % of the CONTROL. A test whose
control passes is not a test.
**(⚠ "THE GIMBAL" IS NO LONGER ON THIS LIST — SLICE 34 SHIPPED IT, and ⚠⚠ BOTH HALVES OF THE LESSON SLICE 33's
GATE 0 BANKED FOR IT WERE REFUTED at slice 34's own gate 0: "the gimbal that saves your envelope PARKS YOU ON THE
WORST GLASS" rests on a contrast that does not exist — the head parks nowhere the body was not already looking,
because a missile points its nose along its velocity plus incidence, so a strapdown seeker's look angle IS the
full lead; and "it REWRITES 26–31's `look_az`" collapses at zero servo lag, which makes it a TOOTH and not a
headline. The live claim was in a THIRD place — the head is aimed by the BENT measurement, so the index of the
glass is a FIXED POINT of the glass. Do not re-import the banked framing.)**
**(⚠⚠ "THE HANDOVER BASKET" IS NO LONGER ON THIS LIST — SLICE 36 SHIPPED IT, and its own named successors are
below. ⚠ Do not re-import slice 34's §0.8 framing for it: the CAGED-head degeneracy it banked was measured at
slice 36's gate 0 to be a SEPARATE mechanism from the aimed one — shrinking `gimbal_stop_deg` reaches the same
rescue, but it CAGES the head (`head_max === stop` exactly) and its birth angle SATURATES, so the V's right arm is
unreachable by it and their verdicts part in BOTH directions over a band of crossings. That separation ships as a
tooth in `test_missile.jl`, and "THE CAGE vs THE AIM AS ITS OWN A/B" is now a named deferral of its own.)**
**SLICE 36's OWN DEFERRALS, in the order it named them: A HANDOVER BASKET WITH A DISTRIBUTION (it authors ONE
signed error; a real handover has a COVARIANCE and the design question is a Pk over the basket rather than a single
arm — the natural successor ⚠ but scope it against slice 37's §0.1 FIRST: the basket's two sides fail by DIFFERENT
mechanisms, so a Pk over it is a mixture of two failure modes, not one); ⚠⚠ **MEMORY TRACK / RE-ACQUISITION IS
DEAD, NOT DEFERRED — KILLED AT GATE 0 (2026-08-17, 5 probes, `docs/plans/slice37.md`), AND SLICE 36's SHARPENED
PREDICTION IS REFUTED**: the TOO-MUCH-BIAS side of the basket NEVER ACQUIRES (born outside the window, `seek_init`
never flips, every rate 0.0), so a coast has NOTHING TO REMEMBER on exactly the half it was predicted to rescue;
an HONEST coast (the head follows the α-β tracker's coasted INERTIAL estimate through the CURRENT attitude)
rescues ONE boundary cell of fifteen and moves NO verdict, because ⭐⭐ A BREAK IN THIS ARC IS NOT AN EPISODE, IT
IS THE REST OF THE FLIGHT (`coast_max` 6.0–7.9 s, `nreacq` 0 on every arm of every wire at both servo rates) ⇒ what
makes a break terminal is the ESTIMATOR's FROZEN RATE destroying the guidance solution, NOT where the head points,
so the cure 34/35/36 all banked was MIS-LOCATED and no head feature can reach it. ⭐ What IS live is a DIFFERENT
subsystem: THE NEVER-ACQUIRED SIDE NEEDS A RE-CUE, NOT A COAST (a probe arm that cheats by feeding the head the
measurement it cannot have goes 3620.675 → 0.110 m, and its provenance is LOGGED — the seam's unconditional
`head_tgt` write, not the probe's seeding) ⇒ a SEARCH PATTERN / SECOND CUE slice owns that number, with its
ceiling and its floor both already measured. ⚠⚠ **THAT CEILING IS NOT AN ACQUISITION NUMBER — MEASURED AT SLICE
42's GATE 0 (2026-08-18, `docs/plans/slice42.md` §I.1) AND THE SENTENCE ABOVE MUST NOT BE QUOTED WITHOUT THIS
ONE.** A cue that STOPS at the first lock (what a search can actually do) reaches NONE of the 0.110 m: it locks
at the same instant as the oracle and misses the full 3620.675 m. The oracle's rescue is a PERMANENT feed that
also covers everything after the lock. ⚠⚠⚠ **AND THE "ACQUISITION KNIFE-EDGE" GATE 0 FOUND IN ITS PLACE IS **DEAD**, KILLED AT
GATE 1 (2026-08-18, `docs/plans/slice42.md` §VI) — DO NOT REBUILD IT.** The claim was that with the window
EXACTLY equal to the birth offset the seeker locks, the lock survives ONE TICK, and the arm misses as if it had
never locked, so *acquisition needs MARGIN, not coverage*. **It is the NULL CASE RELABELLED, and its own gate-0
table said so: the "worthless lock" cell's miss is BYTE-IDENTICAL to the never-locks cell's**, so the lock moves
no number any verdict depends on — and the `off@lock == fov` column is the inclusive `off ≤ fov` gate echoing
back its own authored constant, not a measurement. ⭐⭐⭐ **THE DEAD BAND IS `ω_LOS · dt` — ONE INTEGRATION
STEP:** re-flown at `dt` = 2e−3 / 1e−3 / 5e−4 the band HALVES when the step halves, `ω·dt` lands inside its
bracket at all three, and `hold_max` is exactly one tick on every row — 0.0036° against a 10° window at the
shipped step, i.e. 0.036 %. ⚠ The one non-degenerate rescue (*the required margin is set by the RACE between
the LOS rate and the servo*) is REFUTED in the same probe: `err −10` misses by 3620.675 m at BOTH 8 and 60 °/s,
the same digits, and the same |err| on the OTHER SIGN holds fine (the LOS walks INTO the window there and mints
its own margin). ⇒ the transferable rule, in `docs/LESSONS.md`: **a finding whose SIZE is set by the
integrator's step cannot be a lesson about hardware — re-fly a narrow threshold effect at half `dt`.** ⚠ Also measured there and load-bearing for the search half: on the geometry that
would ship a single 15° window rescues every showcase cell with NO search, so *"buy coverage with time instead
of glass"* is not demonstrable while a wider window is FREE in this model — a search-pattern slice must first
make the window COST something (detector sensitivity / resolution). ⭐⭐⭐ **WHAT A SEARCH OWNS IS NOW MEASURED AND WRITTEN DOWN — SLICE 43's GATE 0**
(2026-08-18, `docs/plans/slice43.md`, no code shipped, suite unchanged at 7693). ⚠⚠ **AND IT SUPERSEDES SLICE 42
§V.4's ρ_min TABLE ENTIRELY, WHICH WAS FLOWN ON A THIRD INSTRUMENT BUG:** `p7b_frontier.jl` never set
`:probe_search_drive`, so every cell TELEPORTED the head to the search command — no `τ`, no `rate_max`, no
`head_slew_full` — at rates the shipped 8 °/s servo cannot produce. ⚠ Its `none ≤ 16` cells were **the 1..16
grid's own edge**: walked to 64 they are **18 and 22 °/s**, so *"past S ≈ 20° no rate buys it back"* is WITHDRAWN.
⚠ Its +side rows are STOP CONTAMINATION and are withdrawn too (command-minus-head lag ≡ the authored half-width
to three digits across seven rates; the do-nothing arm sits on the 30° stop 57 % of in-band ticks). **THE FIVE
FINDINGS THAT REPLACE IT, all −side, all on the real servo:**
**(1) THE COST OF ACQUISITION IS THE OVERLAP DEFICIT `|err| − fov`, NOT THE POINTING ERROR** — err −14 behind a
12° window and err −12 behind a 10° window return the SAME travel (2.073°), the SAME lock time (0.309 s) and the
SAME miss (0.186 m) to every digit; the error and the window are not separately visible, only their difference is.
**(2) `travel = deficit/(1 − ω/ρ)`, `t_lock = travel/ρ + τ`, DOMAIN `ρ ≤ rate_max`** — ω is the LOS RATE, matched
against measured `look_body_az_deg` telemetry to 5.6–13 % on 15 cells; the `+τ` is EXACT (0.0000 s on 12 cells)
because a `ρ·τ` lag traversed at ρ costs τ seconds whatever ρ is, and it DECAYS above `rate_max`. ⚠ An earlier
form of this (`1.036·deficit/ρ`) was measured at ρ = 8 ONLY and is superseded — the multiplier runs 1.031–1.357
over the rate axis. **(2b) ⭐⭐⭐ A FLOOR ON SWEEP RATE (1.0–1.5 °/s), AND IT IS THE AXIS THE SEARCH DOES NOT SWEEP.** Two mechanisms
were proposed and BOTH measured and refuted (an LOS-rate race; a missing reversal — at ρ = 1 the arm fails at
EVERY coverage 2–20°, identical digits). **At ρ = 1 the head closed the SWEPT axis to 9.7519° — INSIDE a 10°
window — and still never acquired, held out by 2.4934° of drift on the UNSWEPT axis making the RADIAL off-axis
angle 10.0656°.** ⭐⭐ **A DEADLINE, NOT A FEEDBACK:** the search branch never assigns `head_el`, so the unswept drift is
EXOGENOUS — byte-identical at matched times across ρ = 0, 1, 1.5, 4. It spends the window's radius on a
schedule the search does not control; the rate only decides whether the SWEPT axis closes first (25 % of the
radius is what it COSTS, not what the search CAUSED). ⭐⭐⭐ **SO THE FLOOR DERIVES, from the NO-SEARCH arm
alone:** `Δaz(t,ρ) = Δaz₀(t) − ρ(t−τ)` (0.001°) plus the radial gate give
`ρ* = min_t [Δaz₀(t) − √(fov² − Δel(t)²)]/(t−τ)` = **1.0174 °/s at t = 4.00 s** — flown, 1.01 NEVER locks and
1.02 locks at t = 3.809 s. ⭐ The required-rate curve is **U-shaped** (2.399 / 1.017 / 2.019 at t = 1 / 4 / 7):
**a search has a BEST MOMENT** (⚠ *"and cannot recover by continuing"* is DERIVED, not flown — the U's right arm
is a property of the curve and no flown arm can acquire on it). ⭐⭐⭐ **CONFIRMED 4/4 ON GEOMETRIES IT WAS NOT
TUNED ON, to the grid's 0.01 °/s:** ρ* = 1.0174 / 1.8817 / 2.6259 / 1.2193 at deficits 2 / 6 / 10 / 3 (last behind
a 15° window), each the first LOCKING rung with the one below failing, and the predicted times within 0.07 s of
the measured locks. ⚠ The ladder is anchored on the prediction, so it is the SHARP test (locks at ρ*, fails at
ρ*−0.01), not a blind bracket.
⭐⭐ **AND THIS GIVES THE BLOCKED DEFERRAL A SECOND, CHEAPER ROUTE TO BEING MOTIVATABLE:** the window's SHAPE, not
just its sensitivity. A per-axis gate of the same half-width LOCKS the arm the radial gate rejects ⇒ **the
RECTANGULAR / PER-AXIS FOV deferral would unblock a search-pattern slice just as `SEEKER RANGE / SNR ACQUISITION
LIMITS` would, and it is the cheaper of the two.** ⚠⚠⚠ **HALF OF THAT SENTENCE IS NOW REFUTED — SLICE 44's GATE 0
MEASURED `SEEKER RANGE / SNR ACQUISITION LIMITS` AND IT DOES **NOT** UNBLOCK ANYTHING** (2026-08-18,
`docs/plans/slice44.md`; see the rewritten entry below). ⚠⚠⚠ **AND THE PER-AXIS HALF IS NOW REFUTED TOO — SLICE 45's GATE 0 (2026-08-18, `docs/plans/slice45.md`, no code, suite unchanged at 7693). DO NOT QUOTE THE SENTENCE ABOVE.** A per-axis window does NOT unblock a search-pattern slice, and the reason is exact: the blocker is *a wider window is FREE, so widen the glass instead of searching*, and a box does **not** make a wider window cost anything — it makes **SEARCHING CHEAPER** (sweep-rate floor ρ* (1.01, 1.02] → (0.92, 0.93], 8.8 % less), which is the WRONG DIRECTION to relieve that objection. ⭐⭐⭐ **⇒ THE SEARCH-PATTERN SLICE HAS NO NAMED UNBLOCKER LEFT ON THIS WIRE EXCEPT SLICE 44's MIDCOURSE-RANGE ENGAGEMENT.** ⚠ Does not
move with `dt` (10.0647 / 10.0656 / 10.0661 at 2e−3 / 1e−3 / 5e−4). ⚠ The LOS rate DOES rise 318× across the
flight (0.271 → 86.05 °/s) — that is why a LATE acquisition is worthless, not why this arm fails. **(3) GUESS RIGHT AND COVERAGE IS NOT FREE — IT IS NEVER REACHED:** the head locks
**2.07° into a pattern authored 3–30° wide**, which is why ρ_min looked flat. **(4) GUESS WRONG AND COVERAGE COSTS
`2S` OF TRAVEL AT AN ACCELERATING PRICE** — measured 0.262 → 0.347 s per degree against a geometric bound of
`2/ρ` = 0.250 (5 % → 39 % over), diverging to never-locks by S = 25 at ρ = 8: **the target moves while you look
the wrong way, and that excess IS the finding.** **(5) THE HEAD, NOT THE COMMAND, IS WHAT SEARCHES** — an
open-loop generator commanded above `rate_max` converts excess rate into LOST COVERAGE and then into outright
failure (realized sweep −19.73° → −4.39° as ρ goes 8 → 64, and at 64 the arm never locks). ⚠ **Cure it with
`ρ ← min(ρ, rate_max)` at authoring time: anti-windup is 5–18 % better in lock time and moves NO rescue verdict in
16 cells, so it is a CAUTION, not an architecture** (slice 43 ran that reparameterization gate against its own
finding before writing it down). ⭐ Cleared: half `dt` moves the headline cells by 0.0000 / +0.16 % / −0.02 %, and
the rescue verdict is BIMODAL (largest rescue 0.3398 m, smallest failure 305.1118 m, nothing between — the gate
could sit anywhere in that band).
⚠⚠⚠ **AND THE PRECONDITION IS UNCHANGED AND IS NOW SHARPER, NOT WEAKER: finding (1) says a wider `fov` reduces
the deficit ONE-FOR-ONE, and the deficit is the ENTIRE cost — so widening the glass by 2° and travelling 2°
further are THE SAME ACT, and only one of them costs time.** A search-pattern SLICE still must not be planned
until the detector window COSTS something. ⚠⚠ **RE-VERDICT 2026-08-18 — see §"THE 2026-08-18 RE-VERDICT" at the top of this file: DEAD AS A LESSON, ALIVE AS A MODEL. The refutation below stands as written and is load-bearing; what changed is that it kills the SLICE'S HEADLINE, not the component.**
⚠⚠⚠ **THE CARRIER THIS LINE NAMED — `SEEKER RANGE / SNR ACQUISITION
LIMITS` — WAS BUILT AND MEASURED AT SLICE 44's GATE 0 AND IT IS NOT THE CARRIER** (2026-08-18,
`docs/plans/slice44.md`, no code shipped, suite unchanged at 7693). The aperture identity is EXACT on the flying
wire (`R_acq · fov` constant to **0.0000 %** over a 4× fov range, log-log slope **−1.000000**, `r_acq` checked
against `snr_freespace` at +10.0000 dB) — **the physics is not what failed.** ⚠⚠ What failed is the WIRE:
a Ku-band seeker authored from a real class BEFORE any flight (200 W, 16 GHz, 10 ms integration, NF 4, L 5,
η 0.6, 10 dB threshold, `rcs_m2 = 1.0`) reaches **8079 m at the shipped 10° window against a 6437 m launch
range — ratio 1.255**, so **the missile is launched INSIDE its own seeker's horizon** and the gate is *exactly
inert* (`t_lock` 0.0010 s, miss 0.2237 m, byte-identical to no gate). Isolated, a delayed lock is FREE:
miss 0.2237 / 0.3491 / 0.3267 / **0.2514** at `R_acq` = none / 4000 / 3000 / **2000 m**, i.e. **a lock at
6.158 s of an 8.9 s flight is indistinguishable from a lock on tick 1**; with the coupling on, a hit stays
available to **−26 dB** and the gate first costs something at **−28 dB** (`R_acq/R_launch` = 0.250 — a
**0.0025 m²** target, or 1/400 of the power, or 1/400 of the integration time), and restricting fov to the
family's 1–12° domain does not move it. ⭐⭐⭐ **THE RULE: A DETECTION GATE CAN ONLY PRICE A DESIGN VARIABLE IF THE
ENGAGEMENT IS LAUNCHED OUTSIDE THE SENSOR'S HORIZON — a property of the WIRE, not of the seeker** (26–43 fly a
6.4 km / 8.9 s TERMINAL engagement, chosen for the radome loop). ⇒ **THE PRECONDITION IS RENAMED: what a
search-pattern slice needs is AN ENGAGEMENT LAUNCHED BEYOND THE SEEKER'S HORIZON — A MIDCOURSE PHASE — and that
is its own slice, not a scenario edit**, because this wire's missile is unpowered with zero drag area at 3000 m,
so a 20 km engagement takes ≥ 28 s over which gravity alone drops it **3845 m, into the ground.**
⭐⭐ **TWO MEASURED THINGS SURVIVE AND ARE WORTH MORE THAN THE LAW WAS.** (a) **A LATE LOCK IS PAID FOR IN
MANOEUVRE AUTHORITY, AND MISS CANNOT SHOW IT:** peak `a_cmd` after lock runs 573 → 436 → 1040 → **3000.0**
against `a_max` = 3000 as `R_acq` falls none → 4000 → 3000 → **2000** — **the last FREE cell spends exactly
100.00 %** where the no-gate arm spends 19.10 %, and past it the demand FALLS BACK to 20.91 % because the track
is gone. **Two limits end the free interval within 500 m of each other and the headline metric showed neither.**
(b) ⚠⚠ **THE NARROW-WINDOW FAILURE IS THE SERVO'S, NOT THE WINDOW'S:** at fov 8.0/8.6/8.8 the shipped 8 °/s head
misses 361.97/438.89/402.17 m holding 1.24/0.71/0.63 % of ticks, and at **30 °/s the same arms hit at
0.2209/0.1931/0.1036 m with hold ≥ 99.97 % from IDENTICAL lock instants** ⇒ **a lock at the window's EDGE hands
the servo a FULL-WINDOW SLEW** (slice 35's axis alone; ⚠ 30 and 60 °/s are byte-identical, so it is a THRESHOLD
in (8, 30] and is NOT bracketed). ⚠ And a **PARTIAL-RESCUE MODE** exists that slice 43's grid could not produce
— 7.7996 m at hold 55.04 %, 85.84 m at hold 31.20 % — both inside the gap slice 43 recorded as EMPTY
(*"largest rescue 0.3398 m, smallest failure 305.1118 m, nothing between"*). ⭐ P6 cleared the boundary the
−28 dB figure hangs off (step-independent to 2 % across 2e−3/1e−3/5e−4) ⚠ but failure MAGNITUDES walk hard with
`dt` (320 → 439 → 627 m) ⇒ **quote the VERDICT, never the metres, once a track is lost.**
**Slice 43's gate 0 ships a LAW to this deferral, not a slice; slice 44's gate 0 ships a KILL to its
PRECONDITION and a rename.**
⚠ THREE INSTRUMENT BUGS in this family are all ONE bug — a sweep command rebuilt from the head's own position
crawls at 1/50 rate; a sweep that steps the HEAD never reverses once the gimbal STOP binds; a sweep that steps a
COMMAND and never checks the head silently teleports it. **A search probe must be checked where the CLAMPS bind,
and must carry the actuator's REALIZED excursion and the command-minus-actuator lag as columns.** ⚠ Reviving the memory track needs a TRACKER that maintains a usable
rate through a gap, not a head change — a larger slice, of which a coast is the corollary; THE CAGE vs THE AIM AS ITS OWN A/B (§0.8, built and measured, shipped only as a tooth — including a
mechanism neither slice has named: the WRONG-WAY CHASE, where a head born BELOW the LOS slews UP toward +18.1°
before the LOS reverses, and at 8 °/s that climb is unaffordable); THE ELEVATION HALF (the error is authored in
AZIMUTH because that is where the lead and the excursion are — slice 28's channel split — and §0.5 predicts NO
optimum shift there, which is a tooth rather than a slice).**
**SLICE 34's OWN REMAINING DEFERRALS: ⚠⚠ MEMORY TRACK / RE-ACQUISITION IS OFF THIS LIST — KILLED AT GATE 0, see
above and `docs/plans/slice37.md` (34/35/36 all recorded the break as TERMINAL and all three assumed a coasting
head was the cure; it is not, and the mis-location is the result). **⚠⚠ THE HEAD'S OWN GYRO IS NO LONGER A DEFERRAL —
IT IS SLICE 37, **SHIPPED AND COMPLETE** (2026-08-17, all four gates, `docs/plans/slice37.md` PART II —
⚠ the notes below are the GATE-0 record and are kept because the refutations in them are load-bearing;
the as-built numbers are in the slice-37 paragraph above and in `docs/STATUS.md`), AND ITS OWN WORDING WAS
REFUTED THERE.** "A rate-stabilized head measures inertial LOS rate DIRECTLY" is ALREADY TRUE of the shipped model —
`missile.jl:1652` is `az_el(û_tru)`, NOT `look_angles(…)`, so the seeker already reports INERTIAL angles and the α-β
tracker an INERTIAL rate. What is body-referenced is the **SERVO**, and the live claim is its REFERENCE FRAME:
stabilize the head inertially and body motion is REJECTED rather than tracked out, so the servo demand collapses
(⭐ 8.19× at the boresight design and 0.86× when quiet — an inertial servo buys NOTHING on a design that does not
ring) and ⭐⭐ SLICE 35's TWO-SIDED KNOB GOES INERT (ring FLAT 1.01× and window FLAT across the whole 60→8 °/s domain,
against 2.29× and 2.17× shipped) — ⭐⭐ **BUT IT GIVES BACK ≈40–45 % OF THE MARGIN SLICE 34's GIMBAL BOUGHT, because the
position servo's LAG WAS SILENTLY DOING STABILITY WORK: it LOW-PASSES body motion out of the glass's INDEX** (measured
on a frozen-geometry bench against `1/√(1+(2πfτ)²)` to 3–4 digits, and EXACTLY unity gain at every frequency for the
stabilized head, with the ring living at 1.7–2.1 Hz where that filter is worth 12–16 % of gain and ~30° of phase).
THREE HEADS, ONE WIRE, ONE 0.005 GRID: strapdown (−0.265, −0.260], position-servoed (−0.170, −0.165],
rate-stabilized (−0.210, −0.205] — and TWO OF THE THREE NEED NO PATCH AT ALL, which is what makes the third credible.
⚠⚠ THE ONSET LINE IS THRESHOLD-FREE BY CONSTRUCTION (advisor): the first draft bracketed on a bare `rms r > 0.20`
THAT I CHOSE and that appears nowhere in 26–36 — and it was load-bearing, since the shipped head reads 0.17308 at
R̂ = −0.165, 13% below it and an order of magnitude above its own 0.01172 plateau. The rule is now the LARGEST
SINGLE-STEP RATIO, the whole ladder is printed so a reader can redraw the line, and the SENSITIVITY IS QUOTED —
≈42% under the largest-step rule and 45% under the discarded one, so the fraction is **≈40–45%** while THE ORDER of
the three rungs and the SIGN of the effect are threshold-FREE. ⚠ The MIDDLE OF THE CAUSAL CHAIN IS NOT YET MEASURED:
gate 0 has the index gain and the bracket but not the link between them, and gate 1 closes it with a prediction only
this mechanism makes (the bracket must walk with τ on the SHIPPED head and NOT walk on the stabilized one).
⇒ **THE CLASSICAL REASON GIMBALS EXIST INVERTS ON THIS WIRE.** ⚠ The reparameterization gate is answered by a BOUND,
not a tolerance (a 25× faster servo at a 50× smaller τ stops at 4.796° and cannot reach the stabilized head's 3.861°)
⇒ RUNG, not knob. ⚠ The τ→0 isolation FAILS against the shipped seam (`max|Δpos|` plateaus at 42.572 m) and holds
EXACTLY (0.000e+00) against a FRESH-ATTITUDE head — the residual is ONE TICK OF ATTITUDE, a property of the seam's
ORDERING and not of the servo, so no "collapse" may be claimed. ⚠⚠ FRAMING A — a strapdown reconstruction with a
CORRUPTED gyro — WAS KILLED BEFORE IT WAS PROBED: `s·ω_body` on the measured LOS rate is `−R·ω_body` to first order,
so the loop cannot tell a body-motion-isolation gain error from a radome slope error and the claim collapses onto
slice 26's boundary (slice 31's shape, convention 4's copy-paste trap). ⭐ SLICE 30's RULE PAYS A FOURTH TIME (33 =
FOV, 34 = detector window, 35 = servo bandwidth, 37 = the head's REFERENCE FRAME): at `radome_slope_worst` both heads
are quiet, flat and cheap ⇒ the ARCHITECTURE DOES NOT MATTER THERE.
**SLICE 37's OWN DEFERRALS, in the order it named them: ⚠⚠ "AN IMPERFECT HEAD GYRO" IS NO LONGER ONE —
IT IS SLICE 38, SHIPPED AND COMPLETE (2026-08-17, all four gates, `docs/plans/slice38.md`), AND ITS OWN
SCOPING WARNING WAS THE RIGHT ONE TO GIVE BUT LANDED ON THE WRONG HALF**: the gain error on the
rejection path does NOT collapse onto slice 26's boundary (measured — 20.2× against an equivalent
radome, because `s` adds PHASE and scaling a slope cannot), and what DID need the slice-31 trap
treatment was the BIAS, which turned out to need ~10³× a bad real gyro.
⚠⚠ **ITS OWN FIRST-NAMED SUCCESSOR — A NULLING-LOOP HEAD SERVO — IS NOW DEAD, NOT DEFERRED: KILLED AT
GATE 0 (2026-08-17, 9 probes in 4 files, `docs/plans/slice39.md`), AND SLICE 38's PREDICTION IS REFUTED IN THE
STRONGEST AVAILABLE FORM.** It predicted the two gyro currencies would SWAP (bias carrying the slice,
scale factor inert). ⭐⭐ **NEITHER CURRENCY EXISTS ON THAT RUNG: a nulling loop with INFINITE LOOP GAIN
is not an ARCHITECTURE, it is a REPARAMETERIZATION OF THE SERVO TIME CONSTANT** —
`nulling(τ, s, b) ≡ feed-forward(τ(1+s), 0, b/(1+s))`, measured END TO END at **5.8e−09 m** of
trajectory over 12 000 ticks across four cells INCLUDING `s > 0`, with the bias twin re-flown ON THE
CLEAN TREE (no patch — a pure shipped slice-38 arm) landing on 0.97634 / 2.12049° / 1.2097 to the
quoted digit. The false-fidelity class (15's `k_δ`, 19's dead `speed`, 31's `(R̂, s)`) caught EARLIER
THAN EVER BEFORE — before any kernel, key, rung, scenario or client code existed. ⚠ The onset table
is NOT flat and that is the second half of the kill: it gives back 0 cells at a real −5 % part (against
feed-forward's 2) but walks to 5 cells at a dead gyro, and the walk is PROVABLY `τ_eff = τ(1+s)`, not
a gyro effect. ⚠⚠ The ONE regime that does not collapse (`|1+s| → 0`, where the demand diverges and the
gimbal saturates) is ENTIRELY the consequence of the probe's own cap-after-division ordering and IS NOT
EARNED — do not quote it. ⭐ What survives is a design sentence — *on a feed-forward head the gyro's
scale factor is a STABILITY spec; on a nulling head it is a BANDWIDTH spec, and a bandwidth spec is one
you already own* — and a LIVE SUCCESSOR, **FINITE LOOP GAIN** (this model rejects body motion perfectly
at EVERY frequency, which is exactly why it collapsed onto a first-order lag; a real loop's rejection
falls off above its own bandwidth, and slice 26's limit cycle lives at 1.7–2.1 Hz, exactly there).
⚠⚠ TWO THINGS MUST BE PROBED BEFORE THAT GETS A PLAN: does a finite-K loop's rejection curve actually
DIFFER from a first-order lag's at the ring frequency (**the identical trap in a new letter** — slice
37's frozen-geometry bench answers it), and are `K` and `τ` SEPARABLE AT ALL (if not, it is slice 37's
τ axis again, which is already a named deferral in its own right).
⚠⚠ **"A SECOND-ORDER HEAD SERVO" IS NO LONGER ON THIS LIST — IT IS SLICE 40, SHIPPED AND COMPLETE**
(2026-08-17, all four gates, `docs/plans/slice40.md`), and its own successors are named there. The
inherited framing was RIGHT that the first-order lag is doing stability work and that an inertia
would change how much — and INCOMPLETE in the way that made the slice: what the lag's margin was made
of is its BOUND (gain ≤ 1 AND phase ≥ −90° at every frequency, for every τ), and a second-order servo
leaves both, in EITHER direction depending on its damping. Then: **THE τ AXIS AS ITS OWN
SLICE** (⚠ gate 1 measured BOTH terms moving with τ — the honest range over τ ∈ [0.005, 0.2] is 0 % to
79 %, and at τ ≤ 0.005 the two rungs' brackets COINCIDE — so "≈40–45 %" is quoted AT THE SHIPPED τ = 0.05
and a slice that made τ the slider would be measuring how much lag is worth buying, which is a different
question from which frame to close in).
⚠ "A RATE-LIMITED HEAD" IS NO LONGER ON THIS LIST — SLICE 35 SHIPPED IT, and its OWN named successor, **A
SECOND-ORDER SERVO (ω_a/ζ_a)**, IS SLICE 40 AND IS ALSO SPENT (see above). ⚠ Slice 15's actuator was named there as
the precedent, and slice 40 turns that round into a NEW deferral: **A SECOND-ORDER FIN ACTUATOR** — slice 15's fin
is first-order-with-a-rate-limit for exactly the reason slices 34–39's head was, and the bound slice 40 argues (a
first-order lag cannot exceed gain 1 or lag more than 90°, so it can only ever damp) is not specific to a seeker
head.** ⚠⚠ **RE-VERDICT 2026-08-18 — see §"THE 2026-08-18 RE-VERDICT" at the top of this file: DEAD AS A LESSON, ALIVE AS A MODEL. The refutation below stands as written and is load-bearing; what changed is that it kills the SLICE'S HEADLINE, not the component.**
Also: **a RECTANGULAR / PER-AXIS FOV — ⚠⚠⚠ **MEASURED AT SLICE 45's GATE 0 (2026-08-18,
`docs/plans/slice45.md`), AND THE VERDICT IS SPLIT: THE STOP HALF IS *DEAD*, THE WINDOW HALF IS *ALIVE BUT
RE-AIMED*.** ⚠⚠ **THE STOP HALF IS DEAD AND IT WAS THE HALF THE PLAN PROMOTED.** §0.2.0 argued from the hardware's
species that the mechanical stop is a box under BOTH readings (an azimuth ring and an elevation trunnion are
independent mechanisms) while the RF dish's beam is genuinely round — the argument is sound and **it picked the
wrong half**: with the azimuth stop held at 30° the miss is **0.1912 m at EVERY elevation stop from 0.04° to 30°**
(a **750×** range) even where the clamp binds **66.66 %** of in-band ticks, and box-vs-disc at matched half-width
is verdict-identical on every rung 30 → 8.2° (both failing at 8.1° with the same 3620.6755). **The SEVENTH
false-fidelity knob** (`speed` 19, launch altitude 21, the handover bias key 36, `ζ` 40, `k_δ` 15, `(R̂,s)` 31).
⚠ The `√2·stop` readout hazard `frames.jl` names is real and measures **1.003×** here.
⭐⭐⭐ **THE WINDOW HALF IS ALIVE, AND WHAT IT NEEDS IS NOT A GEOMETRY BUT A *SEARCHING HEAD*.** On every
TRACKING arm the shape is INERT — box ≡ disc **byte-identically** on eight of nine rows (fov 1–10°, every row this
family has quoted) — because the window is lost on the AZIMUTH axis at every half-width (`off@brk` = fov to four
decimals, elevation contributing ~0.003°, an order of magnitude under one tick of LOS motion; slice 42's `ω·dt`
argument again). ⚠⚠ **SLICE 45's PART II CONCLUDED FROM THAT THAT BOTH HALVES WERE DEAD AND IT WAS WRONG — an
advisor catch: its own §0.2 sub-claim (a) named slice 43's ρ = 1 SEARCH arm and PART II never flew it.** Flown
(controls reproduce slice 43's record exactly): at ρ = 0.95 / 1.00 / 1.01 the DISC **never locks (305.11 m)** and
the BOX **locks and hits at 0.2409 / 0.2285 / 0.1473 m**; the NULL cell (ρ = 0) is identical on both gates.
⭐⭐⭐ **THE RULE, STRUCTURAL RATHER THAN A PROPERTY OF THIS GEOMETRY: A TRACKING HEAD SITS NEAR ZERO ERROR ON
BOTH AXES SO A WINDOW'S CORNERS ARE NEVER VISITED; A SEARCHING HEAD DRIVES ONE AXIS TO THE RIM BY DESIGN, WHICH
IS EXACTLY WHERE THE CORNERS LIVE.** ⚠ The pre-registered objection fires and must be quoted with it: a disc
**0.7 % wider** (10.07°) rescues the same cell, so at matched half-width the box's rescue is 42/43's *"a wider
window is free"*. ⭐⭐ **WHERE IT SURVIVES IS HELD COST, AND THERE IT IS A FLOWN VERDICT RATHER THAN AN ACCOUNTING
SENTENCE:** the rescuing box is (10.00, **1.90**), the cheapest rescuing disc is 10.07 — spend the BOX's OWN budget
as a disc (r = 5.95 by sum-of-travel, 4.92 by area) and the arm **NEVER ACQUIRES**. ⇒ **NOTHING SHIPS, FOR A NEW
REASON: the only arm where the shape matters lives inside an UNSHIPPED feature, so this belongs INSIDE the
search-pattern slice rather than before it.** ⚠ And see the line above — it does NOT unblock that slice.
⭐ Also measured and worth carrying: the stop's demand ratio is **27.3 : 1** (18.1237° az against 0.6643° el), and
on a TRACKING arm the window's elevation half-width is a **FLOOR at `max |Δel|`** — predicted **0.3043** off a trace
before flying, flown flip at **(0.30, 0.31]**, byte-identical over the 32× range above it.
⚠⚠ **THE SUPERSEDED FRAMING, kept so it is not re-imported: — ⭐⭐ **SLICE 43's GATE 0 SUPPLIES THE FLYING ARM THIS DEFERRAL WAS MISSING:** on the
ρ = 1 search arm a per-axis window of the same 10° half-width would LOCK (Δaz = 9.75 < 10 AND Δel = 2.49 < 10)
while the shipped RADIAL `hypot` gate holds it out at 10.0656° — **the first arm in this family where the
window's SHAPE, not its size, decides acquisition** (⚠ precisely: 34 gate 2 §2.5 bound the STOP; this binds the WINDOW) (⚠ the verdict flip rests on 0.066° and is quoted as narrow,
though it is step-independent and 100× the per-tick LOS motion; the non-marginal number is the 25 % of window
radius spent on the unswept axis). — and slice 34 SHARPENS it (it ships one circular
window AND one circular stop, and gate 1 wrote down that the circular shape rests on a SPECIES argument because no
flying arm had ever bound the stop; gate 2's §2.5 bound it for the first time); ⚠⚠ **SEEKER RANGE / SNR ACQUISITION LIMITS IS NO LONGER ON THIS
LIST AS AN UNBLOCKER — MEASURED AND KILLED AT SLICE 44's GATE 0** (2026-08-18, `docs/plans/slice44.md`); what
replaces it is **AN ENGAGEMENT LAUNCHED BEYOND THE SEEKER'S HORIZON (a MIDCOURSE phase)**, see the rewritten
block above. ⚠ The RF half itself (32/33/34 model only the ANGLE half of "can the seeker see it") remains
un-modelled and could still ship as physics — but it must NOT be planned as the thing that motivates a
search, and on a terminal wire it is a DEAD KNOB by measurement;**
a SINGLE IMU (slice 31 corrupts the COMPENSATOR's gyro only; feeding the same reading to the α/β autopilot was
MEASURED at its gate 0 and moves the onset by a DIFFERENT mechanism — plant DAMPING, `k_q` supplying ~98% of it —
which is why it is a separate slice and not a footnote); GYRO NOISE (⚠ deferred on DRAW-TOPOLOGY grounds, not
overlooked: an unconditional third `randn` desyncs every 25–31 replay, so it needs the slice-13 `:scan` 4b shape,
and slice 25's ~1000:1 roll-loop low-pass says probe first — it may be DEAD); per-axis scale factors and gyro
MISALIGNMENT (slice 31's is COMMON-MODE, which is exactly why it collapses onto one number); ESTIMATING R̂ IN FLIGHT (⚠ slice 26's P7A is a
REAL obstacle — the parasitic gain is NOT identifiable in closed loop, so such a slice must first answer *what
excites the estimate?* — and ⚠ slice 29 SHARPENS it: the estimator would have to identify a SHAPE from a signal
whose own index is bent); the ANGLE-DOMAIN corrector as its own A/B on worse glass (built and measured at slice
27's gate 0, not shipped); a 2-D slope `R(look_az, look_el)` or an ASYMMETRIC error curve (slice 28 ships ONE
ODD scalar curve PER AXIS — a symmetric radome, and a manufacturing asymmetry would make the crossing DIRECTION
matter); SUSTAINED-TRACKING / route (b) — an out-of-plane MANEUVERING
target (the demand rotating faster than the roll loop follows, a DISTINCT face from slice 24's cold-start); and
the AERO + INERTIAL CROSS-COUPLING / DEPARTURE that makes a real BTT airframe go OUT-OF-PLANE during a hard roll
(non-diagonal I, Clβ/Cnp/Clr; diagonal I + symmetric cruciform + coordinated flight keep 23/24 clean).
What else remains of §11 Tier-A/B/C: land clutter [terrain banked the heightfield]; monopulse / az×el CFAR.
(⚠ "a seeker FOV / gimbal limit" is FULLY SPENT — slice 32 shipped the FOV half and slice 34 the GIMBAL SERVO; what
remains are slice 34's own four deferrals, named above.) ⚠ Slice 21 did NOT finish the
atmosphere: ρ(z) reaches the COUPLED airframe path ONLY. The point-mass/ballistic drag path keeps a constant ρ
because `dynamics.jl`'s steppers take a `v -> a(v)` closure with NO position in it, and changing that contract to
`(p,v) -> a` touches slice 8's `rk4_step`/`euler_step` — the byte-identity surface of EVERY ballistic slice — for a
path carrying no altitude lesson. A named deferral, and its own slice. Nor is it §11's RF "layered atmosphere /
ducting" entry, which lives behind the `propagation` knob and touches the radar path — do not conflate them.)


---

## ⭐ SLICE 46 DISCHARGED SLICE 44's RE-VERDICT — the first "ALIVE AS A MODEL" actually shipped (2026-08-18)

Slice 46 took the row marked *"arguably the biggest miss of the five"* in the table above and shipped
it: three pure kernels, seven authorable `detect_*` keys, a `:seeker_detect` rung, five telemetry
readouts, a scenario, a HUD branch, a 10-arm verifier and a 9-tooth UI test. 7693 → 7808 tests.
**This is what the re-verdict is FOR** — the physics slice 44 measured EXACT was never the problem;
only its use as slice 44's headline was. Full as-built: `docs/STATUS.md` §Slice 46.

**Both of slice 44's survivors were confirmed on the shipped wire, and one of them was CORRECTED:**

- ⭐⭐ **"A late lock is paid in MANOEUVRE AUTHORITY and MISS cannot show it" — CONFIRMED, and it is
  now a shipped slider.** Down the RCS ladder peak `a_cmd` runs **2.5 → 3.0 → 7.4 → 100.0 → 100.0 %**
  of `a_max` (monotone, 40× span) while the miss is **NON-MONOTONE** (4.541 → 4.786 → 1.381 → 0.987)
  and moves the WRONG WAY across the button (0.9874 gated vs 4.5411 free). The cell in the deepest
  trouble is one that HITS.
- ⚠⚠ **BUT SLICE 44 §VII.1's "the last FREE cell flies at 100.00 % of `a_max`" IS WRONG AS QUOTED —
  it is an r → 0 ENDGAME read.** Gated at `r > 200 m` that cell spends **10.45 %** against the free
  arm's **3.10 %**. ⇒ **do not quote the 100.00 % figure**; quote the gated pair, or the ladder above.
  The effect SURVIVES and becomes STRICTLY MONOTONE once gated — the spike was manufacturing the
  disorder, not the physics. (New method lesson, `docs/LESSONS.md`: the endgame gate belongs on EVERY
  new guidance-derived readout, not only on the three it was written for.)
- ⭐ **"The narrow-window failures of 32/34 are THE SERVO's" — CONFIRMED AGAIN, from a new direction.**
  Slice 46's wire binds the rate limit for **205 frames** at the shipped 30 °/s, all inside a
  1948–2094 m window: the ACQUISITION SLEW at the lock instant. Authored wide at 240 °/s it vanishes,
  and 60/120/240 °/s give identical misses, locks and authority to four decimals — so the isolation
  is free and the effect is unambiguously the actuator's.

**⭐⭐ THE APERTURE IDENTITY is the slice's own new law, and it inverts a rule five slices taught.**
The window IS the beamwidth ⇒ `G = η·4π/θ²` ⇒ `R_acq ∝ √G` ⇒ **`R_acq · fov = constant`** (measured
80789.2051 m·deg off the wire; log-log slope −1 to 1e−12). Slices 32–36 taught *"a wider window is
free"*; with a link budget it is **exactly not** — reach shortens in exact proportion. And `R·σ^(−¼)`
is constant to ten digits, so 16× the RCS buys only 2× the range: **the obvious lever is the weak
one.**

### ⚠ WHAT THIS DOES AND DOES NOT DO FOR THE BLOCKED SEARCH SLICE (42/43/45)

**It supplies the precondition and does NOT by itself unblock the search.** The search family is
blocked on *"an engagement launched OUTSIDE the seeker's horizon"* — slice 44's law. Slice 46 makes
that sentence AUTHORABLE (the seven keys, the rung, the target's `rcs_m2`), and its own NULL cell
still reproduces the block exactly: at `rcs_m2 = 1.0` the horizon is **8078.9 m** against a
**6436.7 m** launch, ratio **1.255** — inside, as it always was. What remains is a **MIDCOURSE
ENGAGEMENT**: a wire whose launch range exceeds the horizon at a sensible RCS. On this scenario that
is now a one-line authoring change (the ladder's lower rungs already do it — at `rcs_m2 = 0.001` the
seeker is blind for 434 frames and locks 6.96 s in), but a *scenario* is not the same as a
*midcourse guidance phase*, which is what a search actually needs to be searching FROM.

⇒ **The search slice's remaining unblocker is unchanged in kind and much cheaper in cost:** author a
launch outside the horizon on top of slice 46's keys, and give the missile something to fly on while
it is blind. The horizon itself is no longer the missing piece.

### New candidates raised by slice 46

- **A MIDCOURSE PHASE (inertial / datalink), THEN the search pattern.** Now the top of the backlog,
  and **slice 47's gate 0 is written and RUN** (`docs/plans/slice47.md`, 2026-08-19).
  ⚠⚠ **CORRECTION, MEASURED (slice 47 P0), AND IT STANDS WHATEVER BECOMES OF SLICE 47:** this entry
  used to read *"it is flying pure PN off a target it cannot see."* **That is wrong. It is flying
  NOTHING.** On the shipped wire `|a_cmd|` is **EXACTLY 0.0 for 6955 consecutive blind ticks** and the
  missile still arrives at 2.998 m — because the Seeker writes `:seeker_omega` unconditionally
  (`missile.jl:2629`) while the never-locked init zeroes every estimate, so PN reads a zero LOS rate,
  **and because the scenario authors the target into the missile's ballistic plane.** ⭐ A second
  freebie measured alongside it (P2): the head is **CUED OFF TRUTH for free** through the whole blind
  phase — 0.30° off a 10° window after 25° of body-frame travel. ⇒ the gap is not "bad guidance while
  blind", it is **no guidance, a free perfect cue, and a launch heading that is already the answer.**
  ⚠ Note the midcourse and the search are the same slice's two halves, and slice 43's law
  (`travel = deficit/(1−ω/ρ)`, the U-shaped best moment) is already banked for the second half.
  ⚠ **Slice 47's own headline proposal — a three-way "squeeze" in which widening the window to survive
  a bad handover shortens the horizon enough to make the error worse — was REFUTED AT GATE 0**
  (`t_lock` saturates against the CPA, so the angle margin improves monotonically). What replaced it:
  ⭐⭐ **a wider window does buy handover tolerance and is never the right way to buy it, because the
  reach it sells is what the airframe was going to spend on the intercept** — over a 6→25° sweep with
  a PERFECT picture the authority goes 8.55 % → PINNED, hold 100 → 6.90 %, CPA 2.6 → 271.9 m while the
  angle margin *improves*. ⇒ **`gimbal_fov_margin_deg` is not the gauge either** (§0.5 rule 1, one
  level up). ⚠ And a method catch worth carrying: **a probe that perturbs the TRUTH to emulate a wrong
  BELIEF is clean only for quantities read at a single instant** — anything integrated over the
  approach is measuring a different engagement (slice 47 P6's error arm, not quotable).
  ⭐⭐ **GATE 0 IS NOW CLOSED AND THE DESIGN FORK IS DECIDED (user, 2026-08-19 — *"we are attempting to
  be closer to reality"*): THE SEEKER HEAD IS CUED ON THE MISSILE'S BELIEF, NOT ON TRUTH.** That makes
  the cue and the guidance ONE component with ONE authored quality figure (convention 9: one lesson —
  *how good does the launch-time picture have to be?*). ⚠ **And P2's freebie has a sharper statement
  than "the head sees truth": the slew is gated on the ANGULAR window alone** (`missile.jl:2103/2129`,
  `off_axis_angle(… look_az_b …)` off `û_tru` at `:1879`) **while slice 46's `_detectable` (`:2413`)
  gates only the MEASUREMENT ⇒ the head slews on an error signal for which there is no detection —
  it tracks an echo the receiver cannot hear.** The fix is a MODE (cued while undetectable, tracking
  once detectable) and it is byte-safe **by construction**: with `detect_pt_w` absent `_detectable ≡
  true`, so the cue arm is UNREACHABLE on any slice 11–45 wire.
- ⚠ **A LAUNCH AZIMUTH — A RESERVED SEAM, NOT A BUG, AND NOT SLICE 47's WORK (slice 47 P7,
  2026-08-19).** `scenario.jl:350` builds `e.vel` with an explicit `0.0` cross-range component and
  `missile.jl:439` mints `:att_q` from `atan(e.vel[3], e.vel[1])` — **pitch only, `e.vel[2]` unread.**
  That is **CONSISTENT today** precisely because the loader forces `vel[2] = 0` (nose along velocity,
  `α = β = 0` at launch, the correct initial condition), and it becomes a **wrong number the moment a
  launch-azimuth key is authored.** ⇒ file it beside the launch-altitude(21) MODEL GAP, with the
  tripwire that **whoever adds `azimuth_deg` to `scenario.jl` must fix `:att_q` in the same commit.**
  ⭐ **The seam does NOT block an azimuth-steering midcourse, which was the reason to look**: P7
  measured the missile leaving its launch plane cleanly — cross-range linear in the command, sideslip
  TRIMMING rather than ramping (2.25° flat over 5 s), `defl_sat` 0 on every arm, resultant incidence
  never near `α_max` — **and slice 46's own top ladder row already flies it**, locking at tick 1 and
  hitting a `y = +2000` target at 2.38 m with `max|β| = 0.83°`. The in-plane birth is an INITIAL
  CONDITION, not a constraint; `steering_command` resolves a full 3-D demand onto two body axes with
  no projection-and-discard (slice 23, "the discard dies").
- **RCS as a per-aspect quantity.** `rcs_m2` is a scalar on the target's comp. A real RCS swings
  10–20 dB with aspect angle, and against a CROSSING target (which every wire in this arc uses) that
  is a large, continuously-varying effect on the horizon. ⚠ Check the MODEL test first: does anything
  read aspect today? Cheap to wire, and it makes the horizon breathe.
- **A `detect` rung above `:snr` — integration / range gating / a false-alarm floor.** The rung tuple
  is `(:none, :snr)`; the obvious third is a CFAR-style threshold with a false-alarm rate, which the
  radar side already has (`detection.jl`). ⚠ Class-(b) hazard: it would flip the draw topology.
- **A NOISE floor on `snr_db` and a probabilistic lock.** Today the gate is deterministic
  (`r ≤ R_acq`), which is why the wire stays byte-identical. A `P_d` draw would make acquisition
  stochastic — genuinely more realistic, and directly at odds with convention 3 (the per-look draw
  COUNT must be rung-invariant). ⚠ Plan the draw topology BEFORE proposing this, not after.

### Killed / not worth doing, from slice 46's own measurements

- **Any showcase built on MISS for this component — DEAD, twice now.** Slice 44 killed the component
  on it; slice 46 measured it non-monotone along the ladder AND backwards across the button. ⚠ This
  is NOT a component kill (see the two-test rule) — it kills MISS AS THE GAUGE for anything that
  moves the ACQUISITION INSTANT. Reach for the authority column instead.
- **A self-declared HUD width budget — DEAD as a practice.** See `docs/LESSONS.md`; slice 46's tooth
  passed green at 100/96 chars while every line ran off the edge at two window sizes. Budgets are
  inherited from the family and asserted in PIXELS.

---

## â­â­â­ SLICE 47 SHIPPED â€” THE MIDCOURSE PHASE, AND THE SEARCH FAMILY'S BLOCK IS **GONE** (2026-08-25)

**Slice 47 is COMPLETE (3 gates, suite 9333).** Detail: `docs/STATUS.md` Â§Slice 47, `docs/SLICES.md`,
`docs/plans/slice47.md` Â§7. This section records only what it changes for the BACKLOG.

### THE BLOCK ON 42/43/45 IS DISCHARGED

Slice 46 supplied the precondition (an engagement launched OUTSIDE the seeker's horizon, authorable
by shrinking the target) and explicitly did **not** unblock the search, because *"a scenario is not
the same as a midcourse guidance phase, which is what a search actually needs to be searching FROM."*
**Slice 47 is that phase, and it ships.** A blind missile now flies a real law â€” a lead-pursuit to
the predicted intercept point of a believed target â€” for 7132 ticks of a 7256-tick engagement, with a
head CUED on that belief, an authored and live-settable error in the picture, and a HUD that shows
what the error costs.

â‡’ **THE SEEKER SEARCH PATTERN (42/43/45) IS NO LONGER BLOCKED.** Every precondition it was waiting on
is now shipped and authorable: an engagement outside the horizon (46), something to fly on while
blind (47), and â€” new from 47 â€” **a measured, tunable way to arrive at handover with a KNOWN pointing
error**, which is precisely the "overlap deficit" a search pattern exists to close. Slice 43's law
(`travel = deficit/(1âˆ’Ï‰/Ï)`, the sweep floor, `t_lock`, the U-shaped best moment) is banked and was
never refuted. â­ **The cost of acquiring is the OVERLAP DEFICIT `|err| âˆ’ fov`, and slice 47 authors
`|err|` on a slider whose cliff sits at the window.** A search slice can now be authored to start
exactly where 47's showcase ends: the arm at 39 m/s that hands over 0.05Â° outside the window and
never acquires is a missile with something specific to search FOR.

âš  **What a search slice must NOT re-litigate:** that a wider window is free (46 killed it â€” the
window IS the beamwidth, so `R_acq Â· fov` is constant), and that the miss is the gauge (44/45/46/47).

### â­â­ A NEW LAW THE SEARCH SLICE MUST BUILD ON â€” THE DEFICIT IS SET BY *TWO* THINGS

**THE HANDOVER ERROR IS THE PICTURE ERROR TIMES THE TIME SPENT BLIND** (slice 47 Â§7.2, found by a
verifier assertion FAILING). Belief and truth start together and separate at a rate the belief error
sets, so the angle at handover is set as much by **when** the receiver opens as by **how wrong** the
picture is: the identical slider value gives **1.3881Â° at a 3.2 s handover and 9.7846Â° at 7.264 s**.

â‡’ **a midcourse error budget cannot be specified in metres per second alone â€” it has to be specified
against a handover RANGE**, and a search slice's deficit therefore has TWO authorable axes rather
than one. âš  This also means slice 47's tidy 0.503â€“0.522 Â°/% line is a property of *that* engagement's
blind duration and must not be carried to a wire with a different horizon.

### âš âš  A BAN THIS LEDGER HELPED CARRY IS **RETRACTED**

`gimbal_fov_margin_deg` was recorded above (slice 46's "New candidates" entry, from slice 47 gate-0
P6b) as disqualified because *"the angle margin improves monotonically"* over the interval where the
engagement is lost. **MEASURED ON THE SHIPPED WIRE, IT DOES NOT.** It separates the ends of the
slider cleanly in both samplings a HUD author would use â€” 9.9932Â° â†’ âˆ’2.9281Â° at handover, 9.5682Â° â†’
1.6764Â° post-lock â€” and P6b's inversion was measured on the sweep that entry ITSELF flags as
confounded ("a probe that perturbs the TRUTH to emulate a wrong BELIEF is clean only for quantities
read at a single instant").

â­â­ **The replacement is stronger than the ban was: at the handover instant `margin + cue = fov`**,
asserted to a tenth of a degree on four arms, because a CUED head's pointing error against the truth
LOS *is* the cue error. The two "rival" gauges are ONE measurement counted from opposite ends. â‡’ the
margin stays off the HUD for **REDUNDANCY** (convention 9: one lesson, one gauge) and **NOT for
deception**. **Do not quote the old reason.**

⚠⚠ **THE IDENTITY IS SERVO-CONTINGENT, NOT DEFINITIONAL** (advisor, added after the first write-up read as unconditional). `off_head` is BORESIGHT-vs-truth while the cue error is COMMAND-vs-truth, so the two coincide only while the head has **SETTLED** on its cue — true on this wire because the servo is authored at 240 °/s as slice 46's measured isolation, and the 0.12° residual in the verifier's 0.5° tolerance IS that lag. On slice 35's 8 °/s wire they would separate. ⭐ The general form is the transferable half: **two gauges that agree on the shipped wire may be agreeing THROUGH an isolation the wire authors** — write the isolation into the claim, or it gets quoted on a wire that does not have it, which is exactly how the ban it replaced went wrong (slice 45's rule: a property measured in one operating mode is not a property of the component).

### New candidates raised by slice 47

- â­â­ **THE SEEKER SEARCH PATTERN (42/43/45) â€” UNBLOCKED by 47 and **SHIPPED BY SLICE 48** — see the slice-48
  section at the foot of this file. This bullet is kept for the history.** Its law is
  banked, its precondition ships, and slice 47's slider hands it a tunable overlap deficit. Author it
  on slice 47's wire with the picture error just past the cliff.
- **A MID-FLIGHT DATALINK UPDATE.** Slice 47's belief is ONE snapshot for the whole blind phase
  (named approximation). A real midcourse gets refreshed, and the lesson would be **how often**: the
  handover error is the picture error times the time since the last update, so update RATE and
  picture QUALITY trade against each other on one axis that Â§7.2 already measured the slope of.
  âš  Check the model test first â€” the update must be READ every tick, not consumed at load.
- **INS DRIFT.** Slice 47's missile knows its OWN state perfectly, which is half of what a real
  midcourse error budget is made of. A drifting own-state estimate corrupts the cue in a way an
  authored target-picture error cannot emulate (it moves the head's frame, not the point it aims at).
  âš  Would need its own model test â€” and note slice 31's warning about compensating with a signal that
  is itself corrupted by what you are compensating.
- **A MANOEUVRING TARGET UNDER MIDCOURSE.** Slice 47's dead-reckon assumes constant velocity, which
  is exactly the assumption a manoeuvre breaks. Slice 12's `ManeuveringTarget` already exists. âš  The
  risk is that this is slice 47's lesson again in different clothes (a wrong picture is a wrong
  picture) â€” it needs a gate-0 probe showing the failure MODE differs, not just the magnitude.
- âš  **NOT a candidate: a `midcourse` FIDELITY RUNG.** Gate 3 considered one to make "no midcourse at
  all" reachable from the client and rejected it â€” the anchor is deliberately an authored key (gate
  2's decision, argued at length), the third arm is a claim about the WIRE rather than a slider
  position, and it is pinned as a test. Adding a rung would reopen a settled decision for no gain.


---

# ⭐⭐⭐ SLICE 48 SHIPPED — THE SEARCH FAMILY IS CLOSED (2026-08-26)

**The 42/43/45 entry above is SUPERSEDED: the seeker search pattern is no longer a deferral, a block
or a kill. It is SHIPPED** — `search_sweep` (frames.jl), one branch in the cue block, three authored
keys, seven telemetry keys, a `search_view` marker, `scenarios/slice48_search.yaml`, and four proofs.
Full detail: `docs/STATUS.md` §Slice 48. Slice 43's banked law was never refuted and is still the
right way to think about the mechanism; what shipped is the SIMULATION of it, and the law's numbers
stayed un-quoted exactly as the plan required (they were measured on an 8 °/s servo over a ~7 s
window; this wire is 240 °/s over ~2 s).

**WHAT THE SLICE ESTABLISHED, beyond its own headline:**

- ⭐⭐⭐ **ACQUISITION IS NOT A LATCH.** A lock taken with less window margin than ONE TICK of LOS
  drift does not survive the next tick — the head freezes before it has ever slewed — so a search that
  ends at first contact can be consumed by a glimpse and leave the missile flying straight with a
  "found it" key on the wire. Measured: 4 of 44 cells, ~1183 m misses, 0 % of `a_max`, 0.005° of
  margin, invisible on every gauge. The rule is `margin@lock > ω_LOS·dt`.
- ⭐⭐ **THE DIRECTION A SYMMETRIC SWEEP OPENS INTO IS A PROPERTY OF THE SCENARIO, NOT OF THE KERNEL.**
  The shipped pattern has no truth to read and always opens toward +azimuth; on slice 47's authored
  error direction that happens to be straight at the target (+12.94°), which hands every arm a freebie
  and flattens the slider. The showcase flips the error so the wrong half is paid for in full.
- ⭐⭐ **A SEARCH SPENDS THE ENGAGEMENT, NOT THE HEAD.** Between 36 and 60 °/s the missile acquires
  every time, flies at up to 100 % of `a_max`, and still misses by 677 → 32 m. The edge at 60/65 °/s
  is **0.086 s** of earlier lock and nothing about the search looks different across it.

## New candidates raised by slice 48

- ⭐⭐ **A ONE-TICK MEASUREMENT MEMORY IN THE TRACKER'S SLEW GATE.** The gap slice 48 made visible and
  deliberately routed around rather than fixing: the gate re-evaluates `off_axis_angle(head, TRUTH
  NOW) ≤ fov` every tick, so a head that has just been handed a fresh, valid measurement can be
  refused the slew that would consume it — the gate closes against a truth that has moved, before the
  head has moved at all. A one-tick memory ("slew to a stored target the detector produced last
  tick") closes it. ⚠⚠ THIS IS A CHANGE TO SLICES 34–47's SHIPPED PHYSICS and would need its own
  byte-identity story; it is NOT slice 37's coasting head (that is a head moving on a REMEMBERED RATE
  and stays dead). ⚠ Its own gate 0 must first show the state is reachable on a wire where it
  MATTERS — on slice 48's wire the search routes around it, which is why this is a candidate and not
  a bug fix.
- **THE SEARCH COVERAGE (half-amplitude S) AS THE AXIS.** Slice 48 authors it at 25° and §0.7 kept it
  in reserve. Slice 43 measured that a wrong-side guess pays `2S` in travel and *"the price
  accelerates"*: too wide a coverage is a search that arrives too late, which is slice 48's lesson on
  a knob whose domain is not squeezed by a 240 °/s servo. ⚠ Its own gate 0 must settle whether the
  coverage is measured against the LIVE sweep centre (which walks away from the target while the
  search runs) or a frozen one — slice 48 ships the live centre and never varied S.
- **A SECOND SWEEP AXIS (raster / spiral / palmer).** Slice 48's pattern is single-axis in body
  azimuth, named as an approximation. A real seeker searches a SOLID ANGLE. ⚠ The obvious risk is
  that it is slice 48's lesson with a bigger constant in front — the honest gate-0 question is
  whether the ELEVATION axis is where the target actually goes on any wire this project flies, and
  slice 43's own gate 0 warned that an unswept axis drifts out on a schedule the search does not
  control. Slice 48 measured the deficit as pure azimuth on its wire, so this needs a geometry where
  it is not.
- ⚠ **NOT a candidate: a `search` FIDELITY RUNG.** Gate 2 considered one and rejected it for slice
  47's reason — "no search at all" is reachable from the SLIDER's own floor (ρ = 0, pinned
  bit-identical to a wire with no anchor), so a rung would duplicate a slider position, and the
  anchor is deliberately a key an author writes.
- ⚠ **NOT a candidate: making the sweep direction authorable.** It would be a knob whose only effect
  is to hand the missile information it cannot have, and the symmetric pattern already bounds the
  cost of the wrong guess at `2S` of travel.

## New candidates raised by slice 49

⚠ Read the two-test rule at the top of this file before proposing to kill any of these.

**⭐⭐ A TAIL LOBE (fore/aft asymmetry).** `rcs_aspect` is fore/aft SYMMETRIC by construction —
σ(θ) ≡ σ(π−θ), so a fleeing target looks exactly like an approaching one, and slice 49's HUD has to
say "tail-on" rather than "nose-on" past 150° because the model genuinely cannot tell them apart.
Real airframes have a distinct tail return (engine face, exhaust). ⚠ Named as an approximation in the
docstring, so this is a DEFERRAL and not a defect. **The gate-0 question is whether it can carry a
LESSON**: it needs a scenario where the same target is engaged from both ends, which slice 49's
single-radar circle is not. Candidate wire: the two-observer geometry gate 2 already tests.

**⭐ A TARGET ATTITUDE.** `aspect_angle` takes the nose to be the VELOCITY direction — zero sideslip,
zero angle of attack on the target (named approximation). A target that carried its own attitude
quaternion would use it, and the difference is exactly the sideslip a hard-turning aircraft flies at.
⚠ Two-sided: it would make the aspect depend on the turn rate as well as the heading, which is a
second mechanism inside slice 49's one-lesson scenario (convention 9). Probably belongs to whichever
slice gives targets a 6-DOF airframe, not to a slice of its own.

**⭐⭐⭐ THE SEEKER SIDE OF THE SAME PHYSICS — an ASPECT-DEPENDENT ENGAGEMENT.** `_effective_rcs` is
the ONE site and `missile.jl`'s seeker horizon already calls it, so a missile's detection range
against a manoeuvring target is ALREADY aspect-dependent as of slice 49, untested as a lesson. Slice
46 proved a detection gate can only price a design variable if the engagement is launched OUTSIDE the
sensor's horizon; the new question is what happens when the horizon MOVES because the target turned.
⚠⚠ Read slice 44's verdict first (a detection gate needs the right wire) and 46's discharge of it.

**⚠ AN RCS FLUCTUATION MODEL TIED TO THE SHAPE.** Swerling 1 is currently a scenario-level detector
choice, independent of the target's geometry; physically the fluctuation statistics and the aspect
curve are the same phenomenon at two timescales. ⚠⚠ **PRE-REGISTERED KILL:** slice 49's own control
arm depends on `swerling: 1` being authorable INDEPENDENTLY of the shape — that is what makes a sphere
a control that can fail. A model that couples them would remove the slice's own control. Propose it
only with a replacement control.

**⚠ A NON-MONOTONE-GAUGE NOTE, NOT A CANDIDATE.** The LOSS COUNT is measured non-monotone in fineness
(41 → 133 → 53 → 42) because a middling body chatters at the threshold while a slender one drops out
and stays out. It is a real and teachable effect — "the worst place to be is exactly at the
threshold" — but it is NOT a slider axis, and any future slice that reaches for it must supply its own
monotone gauge. Same class as `k` (28), `ω_n` (40) and `σ_seek` (25).

**⚠ CLOSED BY SLICE 49, so nobody re-proposes them:** the elevation view's own picture for a
horizontal-plane engagement (the target's cross-range is not on that axis at all — the HUD carries the
lesson instead, and the plan says so); and the blip pile-up under a `step` (a harness artifact of
aging on WALL time while firing on SIM events — pre-existing for every spatial slice, and NOT to be
"fixed" in the client for a shot harness's sake).

## ⭐⭐⭐ SLICE 50 DISCHARGED SLICE 49's OWN TOP CANDIDATE — "THE SEEKER SIDE OF THE SAME PHYSICS" IS **SHIPPED** (2026-08-26)

Slice 49 raised **"⭐⭐⭐ THE SEEKER SIDE OF THE SAME PHYSICS — an ASPECT-DEPENDENT ENGAGEMENT"** and
noted that `_effective_rcs` is the ONE site, that `missile.jl`'s seeker horizon already calls it, and
that a missile's detection range was therefore ALREADY aspect-dependent as of 49, **untested as a
lesson**. The candidate asked *"what happens when the horizon MOVES because the target turned?"*

**It is now answered and shipped** (`scenarios/slice50_defensive.yaml`, `docs/STATUS.md` §Slice 50).
⭐ The candidate's own framing was right on the cost: 49's physics needed **ONE new telemetry key** to
carry a lesson, and everything else was the showcase. ⚠ Its caution — *"read slice 44's verdict first
(a detection gate needs the right wire) and 46's discharge of it"* — was also right, and 46's rule
came back in a stronger form: see the existence condition below.

### ⚠⚠ WHAT SLICE 50 ADDS TO 44/46's RULE ABOUT WHERE AN ENGAGEMENT MUST BE LAUNCHED

44/46: *a detection gate can only price a design variable if the engagement is launched OUTSIDE the
sensor's horizon.* Slice 50's gate is a horizon that MOVES, and the condition it derived is
`F·ω > 4·V_c·R_b/r₀²` — **with `r₀²` in the DENOMINATOR.** ⇒ **launching DEEPER inside the horizon
makes the drop-out HARDER**, because the retreating horizon has further to fall before it passes
through a range that is already small. Same direction as 44/46's rule and for a different reason: not
"you must start outside it" but "you must start near its EDGE." A slice that wants a moving-horizon
loss and launches comfortably inside will get nothing and will not know why.

### ⭐⭐ AND THE MISS BAN IS RE-EARNED, NOT INHERITED

Above `F` = 10 the CPA **reverses direction four times** across the slider. 44/46/48 each banned the
miss on this arc; slice 50 measured its own reversal rather than quoting theirs. ⇒ **the ban now has
four independent measurements behind it and should be treated as a property of the ARC, not of any one
scenario.**

## New candidates raised by slice 50

⚠ Read the two-test rule at the top of this file before proposing to kill any of these.

**⚠⚠ THE TAIL LOBE (slice 49's candidate) NOW HAS HIGHER STAKES — IT WOULD BREAK A SHIPPED TOOTH.**
49 deferred fore/aft asymmetry as missing physics. Slice 50's `slice50_ui_test.gd` tooth 9b asserts
the aspect vocabulary is fore/aft symmetric **as an IDENTITY** (`word(θ) == word(180 − θ)`), which is
correct *because* `rcs_aspect` is symmetric by construction. ⇒ a tail lobe is no longer an additive
change: it retires that identity, and whichever slice ships it must say what replaces the tooth. ⭐
That is the tooth doing its job — it pins the approximation in place so the day it is removed is a
visible day.

**⭐⭐ A MIDCOURSE HANDOVER INTO A TURNING TARGET.** Slice 50 deliberately authors **no `midcourse` and
no `seeker_search`** so that the ONLY thing that can take the lock away is the target. Slice 47's law
(the handover error is the PICTURE error × the TIME SPENT BLIND) and slice 48's search both assume the
horizon stands still while the head hunts. A target that turns during the blind phase moves the horizon
underneath the search. ⚠ The gate-0 question is whether that is a NEW lesson or 47/48's arithmetic with
one more term — and convention 9 is against stacking three mechanisms in one scenario, so it likely
needs 47's or 48's scenario with the shape added, not a fourth one.

**⭐ RE-ACQUISITION AS A LESSON IN ITS OWN RIGHT.** Both live arms **get the lock back** (the target's
turn carries it past nose-on and the echo recovers), and slice 50 asserts that it happens but does
NOT price it. What the second lock is worth — how much of the owed heading can still be paid, against
`t_go` at the moment it returns — is a gauge nobody has measured. ⚠ Beware slice 48's finding that
**acquisition is not a latch**: a lock re-gained too late is consumed and buys nothing, so this
candidate must price the RECOVERY, not merely count it.

**⚠ A TARGET THAT TURNS TO DEFEAT rather than one that happens to be turning.** `maneuver` is an
authored constant here — the target turns because the scenario says so, not because it saw a missile.
A target that pointed its nose at the THREAT would make the aspect a closed loop through the
engagement geometry. ⚠⚠ **PRE-REGISTERED HAZARD:** slice 50's whole byte-identity argument (the shape
reaches the SEEING and nothing about the FLYING) dies the moment the target's motion depends on the
shape, and that identity is what makes the slider's comparison a clean frame-for-frame one. Propose it
only with a replacement for that argument.

**⚠ A NOTE, NOT A CANDIDATE — `rcs_m2` CHANGES MEANING WHEN A FINENESS IS PRESENT.** With a shape
authored, `rcs_m2` is the **BROADSIDE PEAK**, not a mean or a typical value, so a target authored at
1.0 m² is dimmer than 1.0 m² almost everywhere. Both shipped scenarios document it in place. ⚠ Any
future scenario that reuses an RCS number lifted from a slice-1..48 wire and adds a fineness has
silently made that target dimmer. Not a defect; a footgun with two occurrences and no third one yet.

**⚠ CLOSED BY SLICE 50, so nobody re-proposes them:** the max-of-ratio gauge (`R_acq`-retreat ÷
closing rate — killed at gate 0 by its own pre-registered predictive test, see `docs/LESSONS.md`); the
loss RANGE as this slice's gauge (it carries identical information and a ground radar can say it, so
it fails the substitution test); and slice 48's rim-margin conjunct on this wire (an ANGULAR rule
applied to a RANGE-gate loss — a no-op that would have looked like a safeguard).

---

# ⭐⭐⭐ SLICE 51 ANSWERED SLICE 50's OWN ⭐ CANDIDATE — "RE-ACQUISITION AS A LESSON" IS **DEAD AS A LESSON** (2026-08-31)

Slice 50 raised **"⭐ RE-ACQUISITION AS A LESSON IN ITS OWN RIGHT"** — both live arms get the lock
back, the slice asserts that it happens and does NOT price it, and *"what the second lock is worth ...
is a gauge nobody has measured."*

**It is measured, and it cannot be a slice.** Nine probes, no core change, full record in
`docs/plans/slice51.md`. ⚠ **A LESSON KILL, NOT A MODEL KILL** — nothing was proposed to ship,
nothing shipped is refuted, and no key is removed.

**THE KILL, in one line:** a mechanism, an axis and a counterfactual were all found, and then the
quantity the slice exists to measure turned out **not to reproduce under a halved integration step**
— on the SHIPPED slice-50 wire with nothing emulated, at `rcs_fineness` = 9.0, halving `dt` **flips
whether the track ever comes back** (resumes at 1e-3, NEVER at 5e-4; CPA 33 m → 685 m), while every
at-loss quantity reproduces to 0.08 %.

### ⭐⭐⭐ WHAT THIS ADDS TO 44/46/48/50's MISS BAN — **IT WAS NEVER A BAN ON A GAUGE**

Four slices banned the miss on this arc and all four gave the same reason: a blind coast is an
open-loop integration, chaotic in its initial condition. **The miss was simply the first quantity
anyone tried to read there.** The reason applies verbatim to the return time, the head angle at the
return, the recovered share of the heading debt, and to the yes/no of whether the track resumes. ⇒
**a slice on this arc may read a number AT the loss and may not read one AFTER the blind phase.**

### ⭐⭐⭐ AND A SENTENCE SLICE 50 SHIPS IS SHARPENED (not refuted)

Slice 50's table says *"lock given back — yes"* on both live arms. That is the RANGE lamp
(`seeker_detect`, `missile.jl:3737`), and slice 50 says so itself. **The TRACK is a different flag**
(`gimbal_valid`, the `in_fov` conjunction): on `F` = 9.25 / 9.75 / 10.0 the echo returns and the
tracker never resumes, and those flights are **bit-identical** (`max|Δpos| = 0.000e+00`) to arms whose
horizon was collapsed at the loss and never allowed back. ⇒ **A LOCK IS GIVEN BACK BY THE HEAD, NOT
BY THE ECHO.** ⚠ Slice 50's shipped tests are unaffected — it pins at-loss quantities only.

## New candidates raised by slice 51

⚠ Read the two-test rule at the top of this file before proposing to kill any of these.

**⚠⚠ A ONE-TICK MEASUREMENT MEMORY / A RE-CUE ON THE RETURNING ECHO — NOW WITH A MEASURED MOTIVE,
AND STILL BLOCKED BY THE SAME REGION.** Slice 48 raised the slew-gate memory as a candidate and
required its gate 0 to *"show the state is reachable on a wire where it MATTERS."* Slice 51 shows a
wire where it plainly matters: the echo comes back, the head is 15–24° off, and the missile throws
it away. ⚠⚠ **But the improvement would have to be measured after a blind coast, which §V has just
ruled unreadable** — so the candidate needs a wire whose blind phase is SHORT and whose gauge is
read at a bounded time after the return, or it inherits this kill. ⚠ It is still a change to slices
34–50's shipped physics with its own byte-identity story.

**⚠ THE TURN ONSET KEY (`maneuver.turn_start_s`) — UN-BUILT, AND THE SEAM IS CLEAN.** Slice 50 named
it *"the most interesting axis in the slice"* and ruled it not-authorable. Slice 51 emulated it (write
`:a_lat_mps2` per tick; `ManeuveringTarget` reads it with a default every tick, `missile.jl:1092`) and
confirms: **eight** shipped scenarios author a `maneuver:` block (12, 15, 19, 21, 22×2, 49, 50),
none would grow the key, absent ⇒ turn from `t` = 0 ⇒ every slice 12–50 wire byte-identical
(**checked by name, LESSONS §752** — ⚠ the file-level grep first said TEN, matching two comments that
say the opposite)). ⚠ It is a
one-commit key whenever a slice needs it — but slice 51 is NOT that slice, and a key with no lesson
behind it is not worth a commit.

**⚠⚠ CLOSED BY SLICE 51, so nobody re-proposes them:**

- **`gimbal_fov_deg` as a slider on slice 50's wire** — slice 46 shipped the coupling (the window IS
  the beamwidth), so widening it shortens the horizon: at `fov` = 6–8° the missile never detects the
  target at all and at 16–20° it starts blind and acquires later. ⇒ the knob does not move slice
  50's engagement, **it turns it into slice 46's** — two SCENARIOS on one knob, not two mechanisms.
- **`rcs_fineness` as the axis for anything measured after the loss** — the recovered share reverses
  three times across 7.5–10.0 (0.960, 0.976, 0.974, 0.524, 0.597, 0.215, 0.610, 0.000, 0.371, 0.000,
  0.000). Same class as `k` (28), `ω_n` (40), `σ_seek` (25), the loss count (49).
- **The head's angle at the return, as a GAUGE** — `head_off > fov ⇔ no track` **is the definition
  of `in_fov`**, i.e. slice 42's `off@lock == fov` column: the inclusive gate echoing back its own
  authored constant. ⚠ It is a fine EXPLANATORY variable and would be a fine telemetry key; it can
  never be what a slider is scored on.
