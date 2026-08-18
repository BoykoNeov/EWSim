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

The NEXT named candidates:
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
also covers everything after the lock. ⭐ And gate 0 then found something sharper than the candidate it was
probing: **THE ACQUISITION KNIFE-EDGE** — with the window EXACTLY equal to the birth offset the seeker locks,
`off@lock` == fov to four decimals, the lock survives ONE TICK and the arm misses as if it had never locked;
**0.05° more window turns the same lock into 8.854 s of track and a 0.224 m hit**, flat to the digit on both
sides. The mechanism is `missile.jl:2086` — the slew gate can be ENTERED but never RE-ENTERED ⇒ **ACQUISITION
NEEDS MARGIN, NOT COVERAGE.** ⚠ Also measured there and load-bearing for the search half: on the geometry that
would ship a single 15° window rescues every showcase cell with NO search, so *"buy coverage with time instead
of glass"* is not demonstrable while a wider window is FREE in this model — a search-pattern slice must first
make the window COST something (detector sensitivity / resolution). ⭐ What a search DOES own, measured on the
fixed instrument: **THE WRONG-GUESS FRONTIER** — the minimum sweep rate is FLAT across a 6× range of coverage
when the direction guess is right and RISES MONOTONICALLY with coverage when it is wrong (4/5/7/8/10/11 °/s over
S = 5→30°, and past S ≈ 20° on one side no rate buys it back). ⚠ TWO INSTRUMENT BUGS in that gate produced
tables that read exactly like physics (a sweep command rebuilt from the head's own position crawls at 1/50 rate;
a sweep that steps the HEAD rather than a COMMAND never reverses once the gimbal STOP binds) — **a search probe
must be checked where the CLAMPS bind.** ⚠ Reviving the memory track needs a TRACKER that maintains a usable
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
head.** Also: **a RECTANGULAR / PER-AXIS FOV — and slice 34 SHARPENS it (it ships one circular
window AND one circular stop, and gate 1 wrote down that the circular shape rests on a SPECIES argument because no
flying arm had ever bound the stop; gate 2's §2.5 bound it for the first time); SEEKER RANGE / SNR ACQUISITION
LIMITS (32/33/34 model only the ANGLE half of "can the seeker see it");**
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

