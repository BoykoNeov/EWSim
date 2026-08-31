# EWSim — cross-slice method lessons

Disciplines that transfer between slices. Each one was paid for by a gate that failed, a probe
that refuted its own premise, or a green run that shipped something wrong. **Not loaded into
context automatically** — read it when you are about to plan, probe, or verify a slice.

Provenance for every line is in `docs/plans/sliceN.md` (gate-0 probe records) and
`docs/STATUS.md` (gate-by-gate as-built). The *conclusions* of these lessons that are cheap
enough to always carry live in `CLAUDE.md` §Conventions and §Dead ends.

---

## Before you build: killing a slice for free

- **Fly the kill risk before the mechanism.** If one question would make the whole slice
  pointless, answer that question in the first probe, not the last. (Slice 40: *does the track
  break before the resonance rings?* — `out_band = 0.00 %` on every arm, and the slice lived.)
- **Run the arithmetic premise before the code.** Slice 37's P1 cost a calculator and could have
  killed the slice for free.
- **Compose your own equivalences before believing a rung is an architecture.** Slice 39 died
  here: an infinite-gain nulling loop is algebraically a reparameterization of the servo time
  constant. Ask *can an existing knob reach this state?* before writing a kernel.
- **Read the line the deferral describes before believing the deferral.** Slice 37's inherited
  wording was refuted by one line of shipped source (`missile.jl:1652`) before any probe ran.
- **When three slices bank the same cure, check which subsystem actually owns the failure
  before building it.** (The memory-track kill: the cure belonged to the estimator, not the head.)
- **When a slice REMOVES a key, re-derive every downstream behaviour that key was silently
  providing.** A client drop-branch inherited by count is not inherited at all.
- **⭐⭐ A NEW DYNAMIC ELEMENT IS ONLY DISTINGUISHABLE FROM A RETUNE BY A LOOP THAT SAMPLES IT AT MORE
  THAN ONE FREQUENCY.** Slice 41 died here. A pole differs from a gain ONLY in that its phase VARIES
  with frequency; the fin command on that wire was a single 1.6488 Hz line, so the loop sampled ONE
  point of a phase curve — and one point of a phase curve is a number, which is what a gain is. Slice
  38's *"`s` adds PHASE and scaling a slope cannot"* is TRUE and has teeth only where the loop is
  BROADBAND. **Before building any new dynamic element, measure the SPECTRUM of the signal it will sit
  on** — a detrended periodogram of the command it filters, ~40 lines and no dependency. A
  single-line spectrum predicts the reparameterization kill before a kernel is written.
- **⚠⚠ Pre-register the falsifier — and re-check its WORDING against what the probes have since
  learned.** Slice 41's P5 as originally worded (*can any `(k_α, k_q)` reproduce the arm?*) answers
  **yes** at the design point, because one of those gains is PART of the loop being measured (~98 % of
  its damping), so retuning it moves the boundary directly. That is the confounded-lever objection,
  not a reproduction of a pole. Re-worded over the whole THRESHOLD CURVE instead of a point, the same
  probe killed the slice honestly. **The pre-registration prevented a wrong death and then delivered
  the right one — both directions are the value.**

## While probing: what a probe is allowed to conclude

- **A probe's CONTROL row is worth more than its result rows.** Slice 40's ring-frequency claim
  died on its own control (0.80 Hz where every prior slice measures 1.7–2.1) and is recorded
  **UNTESTED**, not as refuted physics. A control that disagrees with the literature invalidates
  the instrument, not the hypothesis.
- **Having both ends of a causal chain is not having the chain.** Measuring the input gain and
  the output bracket does not link them; design a prediction only the proposed mechanism makes.
- **When a limit does not close, find the third object it closes against.** A budget that refuses
  to bind usually binds somewhere you have not instrumented.
- **When a probe reached its numbers by a different code path, prove the paths agree before
  quoting its tables** — don't discover it from a failing tooth.
- **A bracket at the edge of its own grid is truncated, not measured.** Extend the grid or quote
  it as a bound.
- **A number you invented must not decide a headline.** Either derive the threshold or print the
  whole ladder so a reader can redraw the line — and quote the sensitivity either way.
- **⭐⭐ AN rms MEASURED WHERE A CLAMP BINDS CANNOT MOVE, AND READS AS A KILL.** Slice 41's P2, run at
  its wire's AUTHORED design, read 0.4 % across the whole physically-honest band — because the α_max
  clamp bound **78 % of band ticks** there, so the metric was insensitive BY CONSTRUCTION. The same
  ladder one step inside the stability boundary read 1.27×–4.45×. **Carry a contamination column on
  EVERY arm (each clamp, counted IN BAND) and read it before the result column** — a wire authored to
  SHOW an instability is usually authored past the point where anything else can be measured on it.
- **⭐ To prove a clamp is not setting your metric, VARY THE CLAMP — don't argue.** Slice 41's suspect
  cell was bit-identical across a **20×** range of `delta_max`: invariance to the threshold of the
  thing suspected of setting it is the strongest non-contamination argument available, and it costs
  one extra run. (Its neighbour moved 0.396 → miss 846 m → no band at all over the same range — the
  clamp had been BOUNDING a divergence, which is the failure this check exists to catch.)
- **⚠ A CUMULATIVE counter cannot separate a band fire from the `r → 0` endgame spike** — difference
  it across band entry/exit. Slice 41's arms looked contaminated (36–83 fires) and were clean in band;
  the shipped CONTROL fires in the endgame too ([[ewsim-missile-verifier-sampling]]).
- **⚠⚠ A test whose CONTROL also passes is not a test.** Slice 41's pre-registered confirmation leg
  returned a PASS by the letter of its falsifier — and every arm sat within 0.9 % of the control as
  well, because on that wire nothing did anything. Recorded as DEGENERATE and counted as nothing.
  **Check the control against the falsifier before reading the arms.**
- **⚠ The dead-knob trap lives INSIDE probes too.** A slice-41 probe overrode `af_inertia` — a key
  nothing reads (it is `af_I`) — and returned an identical spectrum at three inertias, reading exactly
  like *"inertia does not move the ring"*. **Guard every override: `haskey(comp, key) || @warn`.**
- **One failure mode in a sweep can be two.** Slice 36's handover basket looked symmetric; its
  two sides fail by different mechanisms, so a single averaged metric over it is a mixture.
- **A PROBE HARNESS FAILS SILENTLY AND GREEN, EXACTLY LIKE THE PHYSICS TRAPS DO.** Slice 41's
  sweep script wrote all nine runs to ONE junk file and printed `ok` nine times: a backslashed
  `"...\$VAR"` inside a bash double-quoted Windows path does not expand. Pass Windows paths
  FORWARD-SLASHED, and never let a sweep report success from the exit code alone — have it print
  the output it produced (a line count, a size), so "no output" cannot read as "passed". Same tell
  as the `%g`-in-GDScript and `STEPS`/`emit_every` traps: a green run with nothing in it.
- **Derive a stability boundary before you walk it, then check its DIRECTION against a datum the
  repo already records.** Slice 41's plan predicted the semi-implicit rung was tighter at LOW
  damping; it is tighter at HIGH damping. What settled it was not the walk but an existing comment
  in `frames.jl` (decaying at 200 Hz, diverging at 300) that the wrong rule cannot explain and the
  right one can. **A bound is a curve over its parameters until proven otherwise, and a bound
  quoted as one number will be hard-coded by the gate that reads it.**
- **Do not carry a convergence tooth to an EXACT form.** A dt-ratio column that reads flat means
  "not solving this equation" only for an approximate stepper; for a closed-form update it is the
  correct answer, and copying the tooth over manufactures a bug report against working code.
- **Pin the integrator in the regime the claim lives in.** A lightly-damped claim is exactly
  where numerical damping can masquerade as physics — show first-order convergence and bound the
  discrete effective damping against a domain cell.

- **⭐⭐⭐ CHECK A CLAIMED *STEP* AGAINST THE *NULL* CELL BEFORE BELIEVING IT.** Slice 42's headline
  finding was *"the seeker locks at the rim and the lock is WORTHLESS"* — and the worthless-lock cell's
  miss was **byte-identical to the never-locked cell's** (305.112 m both). A cell whose verdict number
  equals the do-nothing cell's verdict number **is** the do-nothing case wearing a label. The null row
  was already in the table; nobody compared the two. **Put the do-nothing arm in the same table as the
  result arms, in the same column, and read them against each other first.**
- **⭐⭐ A REPORTED QUANTITY THAT EQUALS AN AUTHORED THRESHOLD TO FULL PRECISION IS THE THRESHOLD, NOT A
  MEASUREMENT.** `off@lock` reading `12.0000` against a `fov` of `12.00` looked like a four-decimal
  confirmation of a mechanism; it is an inclusive `off ≤ fov` gate echoing back its own constant with
  the head placed on the rim BY CONSTRUCTION. **When a measured column agrees with an authored number
  to the last digit, ask what would have to be true for it to disagree** — if nothing could, it is
  not data.
- **⭐⭐⭐ RE-FLY A NARROW THRESHOLD EFFECT AT HALF `dt`. IF IT HALVES, IT IS THE STEP.** Slice 42's
  acquisition "margin" is `ω_LOS · dt` — the distance the line of sight travels between two evaluations
  of a once-per-tick gate. Measured at `dt` = 2e−3 / 1e−3 / 5e−4 the band brackets halve each time and
  `ω·dt` lands inside all three; `hold_max` is exactly ONE TICK on every row. **A finding whose SIZE is
  set by the integrator's step cannot be a lesson about hardware** — and this is a much stronger kill
  than *"the effect is small"*, which only ever invites *"small on this wire"*. Two extra runs.
- **⚠⚠ BYTE-IDENTITY ACROSS A KNOB PROVES INVARIANCE, NOT A MECHANISM — AND THE TEMPTATION TO WRITE
  THE MECHANISM ANYWAY SURVIVES EVEN THE LESSON ABOVE.** Slice 42's kill record asserted *why* a 7.5×
  servo changed nothing (*"the command is still equal to the head's own angle"*) one paragraph after
  banking *"check the sentence against the table"* — and a five-tick trace showed the head's command
  was NOT stale (a real one existed on tick 1) while the conclusion held for a better reason: the
  command is written at the END of the tick, so the servo is idle for exactly one tick and both rates
  are equally idle. **Print the state, don't infer it — a tick-by-tick trace of the three or four
  numbers the branch reads is the cheapest probe in this repo and it is the one most often skipped.**
- **⚠ AND A DEAD BAND THAT DEPENDS ON A *SIGN* IS A COINCIDENCE, NOT A MECHANISM.** The same |offset|
  on the other side of the rim did not fail at all — there the LOS walked INTO the window and minted its
  own margin. **Fly the mirror-image arm before naming a boundary effect.**

- **⭐⭐ A GRID EDGE IS NOT A CEILING — AND THE SLICE THAT WROTE THE LESSON ABOVE BROKE IT IN THE SAME
  GATE.** Slice 42 §V.4 reported `none ≤ 16` for two cells and wrote the sentence *"past S ≈ 20° there
  is no rate that buys it back"*; its own legend read *"`--` = no rate in **1..16** deg/s rescues"*.
  Walked to 64, the answers are **18 and 22 °/s**. That is the *"a reported quantity that equals an
  authored threshold IS the threshold"* lesson, one section earlier in this same file, applied to a
  sweep's BOUND rather than to a gate's constant. **A `--` in a swept table must print the sweep's
  bound in the same cell, and any sentence built on one must say "not within the grid", never "not
  at any".**
- **⭐⭐⭐ A FLAT ROW IS EVIDENCE OF NOTHING UNTIL YOU KNOW WHERE THE MECHANISM STOPPED.** Slice 42 read a
  ρ_min row that was flat across a 6× range of coverage as *"coverage is FREE"*. Slice 43 measured what
  the head actually swept: it **locked 2.07° into a pattern authored 3–30° wide**, so coverage was
  never REACHED. *"Free"* and *"never used"* produce the identical flat row and license opposite
  designs — one says buy more, the other says you are measuring the wrong knob. **When a knob reads
  inert, instrument how far the mechanism got before it stopped, and check that against the knob.**
- **⭐⭐ DRIVE THE COMMAND, THEN PROVE THE ACTUATOR FOLLOWED IT — THREE BUGS IN ONE FAMILY ARE ALL THIS
  BUG.** (i) A sweep rebuilt from the head's own angle crawls at `dt/τ` of the commanded rate; (ii) a
  sweep that steps the HEAD never reverses once the stop binds; (iii) a sweep that steps a COMMAND and
  never checks the head silently **teleports** it — slice 42's whole frontier was flown through
  `head_clamp` with `τ`, `rate_max` and `head_slew_full` all bypassed, at rates the shipped servo
  cannot produce. **Every actuated probe carries two columns: the actuator's REALIZED excursion, and
  the command-minus-actuator lag.** The lag is the tell — it should read `ρ·τ` (0.049–0.245° here, and
  it did); when it instead reads *the authored half-width to three digits*, the actuator is on a stop
  and is not flying the pattern at all.
- **⭐⭐⭐ READ THE BRANCH AND ASK WHICH STATE IT WRITES — a causal sentence can be refuted before any probe
  runs.** Slice 43 wrote *"a slow one-axis search INFLATES its own deficit through the orthogonal channel
  while it works"*. Its own search branch is `head_clamp(cmd, head_el, stop)` — **`head_el` is never
  assigned**, and it is seeded once at birth, so the orthogonal drift is a pure function of time and is
  byte-identical whether a search runs or not (measured across four arms). **If the quantity in your causal
  clause is never written by the mechanism you are crediting, the clause is wrong on inspection.** ⭐ The
  correct sentence was a **DEADLINE, not a feedback** — and stating it that way turned a bracket into a
  DERIVATION: the exogenous curve plus the swept-axis form gave the floor to better than 1 % from the arm
  that never acquires. **Getting the mechanism right is not bookkeeping; it is what makes a number
  predictable.**
- **⭐⭐⭐ A HEDGE IS NOT A MEASUREMENT — AND DO NOT DRAW A MECHANISM FROM THE ARM THAT FAILED.** Slice 43
  correctly convicted its own earlier section of fitting a constant along one axis, and then, one section
  later, explained a sweep-rate floor with a line-of-sight table **measured on an arm that never locks,
  with no search running at all** — the endgame of a failed intercept, used to explain the failure. It
  carried the disclaimer *"quoted as MEASURED, not derived"* and that changed nothing: **the sentence
  still named a cause.** Two candidate mechanisms were then measured and BOTH refuted, and the real one
  was elsewhere entirely. ⇒ **If a claim names a mechanism, measure that mechanism on an arm that is not
  the failure itself — or name no mechanism at all.** ⚠ The tell was in the author's own arithmetic: a
  hand-check said the crossing should have happened seconds before the proposed cause could bite, and it
  was written off to a channel that was never printed. **When your own back-of-envelope disagrees with
  your explanation, print the channel you are blaming.**
- **⭐⭐ A ONE-AXIS CONTROL ACTION INSIDE A RADIAL GATE LOSES ITS MARGIN TO THE AXIS IT DOES NOT MOVE.**
  The seeker's window is a `hypot`, and a search that sweeps azimuth only closed azimuth to 9.75° inside
  a 10° window and **still never acquired**, held out by 2.49° of drift on elevation (25 % of the window
  radius). **Whenever an actuator moves in fewer dimensions than the gate measures, carry the orthogonal
  component as a column** — and note that this is the cheapest kind of arm to hand a per-axis-vs-radial
  design question, which had gone unanswered for nine slices for want of exactly one flying example.
- **⭐⭐⭐ COUNT THE AXES A CLAIM VARIES OVER, NOT THE CELLS — AND NAME THE AXIS THE CLAIM'S OWN MECHANISM
  SAYS MUST MATTER.** Slice 43 quoted a closed form as *"three digits, eight cells, two windows"*, which
  reads as three axes and was ONE: all eight cells sat at a single sweep rate. **The mechanism named for
  its constant was drift; drift is a function of travel time; travel time is a function of rate; and rate
  was never swept.** Swept, the "constant" ran 1.031–1.357 — and the corrected form was strictly better,
  because the drift term turned out to BE a directly measurable telemetry quantity instead of a fitted
  number. **Before quoting a fit, ask what its own explanation says should move it, and check that you
  moved it.** ⚠ Corollary: **state the DOMAIN.** The same form's `+τ` term is exact below the actuator's
  rate limit and decays above it, and neither the formula nor the finding that takes over above the limit
  said where the boundary was.
- **⚠⚠ AN OPEN-LOOP COMMAND GENERATOR WINDS UP AGAINST A RATE LIMIT, AND WHAT SATURATES IS THE
  AMPLITUDE, NOT THE RATE.** Commanding a 20° triangle at 64 °/s to an 8 °/s head does not sweep it
  faster or even merely less — the head realizes **4.4° of 20° and the arm fails outright** at a
  coverage that rescues comfortably when commanded at 8. ⚠ **But price the cure before naming it an
  architecture:** anti-windup (bound the command's lead over the actuator) and simply clamping the
  authored rate to `rate_max` gave the SAME rescue verdict in all 16 cells, 5–18 % apart in lock time.
  **A cure that moves no verdict is a caution.**

- ⭐⭐⭐ **A GATE IS NOT FINISHED WHILE A SUB-CLAIM ITS OWN PLAN ENUMERATED HAS NO ROW IN ANY TABLE**
  (slice 45, an advisor catch). That gate's PART II killed both halves of its slice on a table of
  byte-identical pairs; its plan's FIRST sub-claim named an arm that lived inside an earlier slice's
  probe patch, the probe run said *"skip it initially"*, and nothing came back to it. **The write-up
  did not notice because every arm it DID fly agreed.** One script overturned half the verdict.
  ⚠ **The guard is mechanical, not a matter of care: before writing a verdict, walk §0.2's
  sub-claims and point at the table that answers each one.** Agreement among the arms you flew is
  not evidence about the arm you did not.
- ⭐⭐ **A SHAPE (or any structural change) EARNS A RUNG ONLY IF IT CHANGES BEHAVIOUR — AND "IT IS
  CHEAPER" IS A CLAIM ABOUT A COST MODEL YOU MAY NOT HAVE** (slice 45). Two window shapes that give
  bit-identical verdicts at every value differ only in what you would have paid, and this simulator
  has no cost variable anywhere. ⚠ **The exception is the useful half:** where the two DISAGREE on
  a verdict, held cost becomes flyable — fix the budget, spend it each way, and read lock/no-lock.
  A cost claim you can fly is a lesson; one you can only assert is a slide.
- ⭐⭐ **THE REPARAMETERIZATION GATE DOES NOT ALWAYS NEED A GRID — ASK WHETHER THE SECOND KNOB IS
  INERT ABOVE A FLOOR** (slice 45, advisor). If knob B does nothing over its whole range above some
  threshold, the pair was ONE knob plus a floor before any tuning started, and the threshold is
  predictable from instrumentation: it is `max |the quantity B gates on|`. Predicted 0.3043° off a
  trace, flown flip at (0.30, 0.31]. **Cheaper than the grid it replaces, and anchored on a
  prediction, which makes it the sharp form of the test rather than a blind bracket.**
- ⭐⭐⭐ **A PROPERTY MEASURED IN ONE OPERATING MODE IS NOT A PROPERTY OF THE COMPONENT — AND WHEN A
  REGIME DISTINCTION OVERTURNS ONE CLAIM, WALK EVERY OTHER CLAIM IN THE DOCUMENT AND ASK WHICH
  REGIME IT WAS MEASURED IN** (slice 45, advisor, and the gate made this error TWICE). Its PART III
  established that a window's shape is invisible to a TRACKING head and decisive to a SEARCHING one
  — then in the same breath carried a TRACKING-arm inertness into a verdict about the STOP, whose
  elevation demand is 3–4× larger in the search regime. ⚠ It survived the re-run, which is luck, not
  method. **The check is mechanical and costs one table.**
- ⭐ **WHAT A LIMIT COSTS DEPENDS ON WHAT THE SUBSYSTEM IS DOING, NOT ONLY ON WHAT IT IS FLYING**
  (slice 45). A window's SHAPE is invisible to a TRACKING head (which holds the target near the
  middle, so the corners are never visited) and decisive for a SEARCHING one (which drives an axis
  to the rim by design, where the corners are). ⚠ Before concluding a geometric feature is inert,
  ask which OPERATING MODE would visit the part of the geometry that distinguishes it.

## While testing: teeth that actually bite

- **Two wrong oracles can both look like a tolerance problem.** `acos` of a dot product is
  precision-limited; predicting a swept angle as `|Ω|·dt` is wrong *by construction*. Swapping
  one oracle and getting a bit-for-bit identical number is what exposes the other.
- **A tooth that passes can still be a tautology** — a flag and the comparison that sets it are
  the same fact twice. Downgrade its claim rather than trusting the pass.
- **Guard every band metric with `n_band > 0`**, and assert the emptiness as the positive fact
  it is. A quiet `rms = 0.00000` from zero samples reads exactly like a healthy arm.
- **The predictor and the predicted must not come from the same run** when the failure mode
  destroys the predictor. Fly the design twice.

## While shipping the client: what only a capture can catch

- **The stale-readout class** — a HUD branch reading keys a new wire does not have prints a
  fluent, entirely plausible verdict about the wrong subsystem. Its worst form is when nothing
  in it is stale and every number is true.
- **A live control that does nothing is the stale-readout class in a new form** — not a stale
  number but a dead one. Say so in the HUD.
- **A HUD's imperatives need the same freshness as its numbers.** Slice 40's shot caught a cure
  line advising the user to damp an arm that was already damped: every number true, the
  *instruction* stale.
- **There are TWO width budgets, not one.** A width tooth can pass at the body lines' ~55 chars
  while a headline drawn larger from a different origin overruns at ~30.
- **⭐⭐⭐ A SLICE INHERITS THE FAMILY'S MEASURED WIDTH BUDGET; IT DOES NOT DECLARE ITS OWN — AND THE
  BUDGET IS PIXELS, NOT CHARACTERS** (slice 46, one slice after the bullet above was written). Slice
  46's first three shots ran ALL five body lines AND all four headlines off the right edge, at 1152 px
  **and again at 1920 px**, while its own 100/96-CHARACTER tooth passed green. Three compounding
  failures, and each is the general lesson:
  - **A budget a slice picks for itself is not a budget.** The number has to come from the ORIGIN.
    Here that is `vp.x − 430`: 430 px of room, and the family had already measured what fits in it.
  - **A right-anchored origin does not get roomier with a bigger window — it MOVES.** So "it will be
    fine on a real monitor" is false: there is no window size at which an over-long line fits. Any
    reasoning of the form "the shot is just small" is the bug talking.
  - **`⇒ ° ← — | ⭐` are one `length()` each and many pixels each.** In HUD prose dense with them the
    char count under-reads real width by a per-line amount you cannot predict. ⇒ assert on
    `get_string_size(s, …, SIZE).x <= ROOM` at the SAME font and size `_draw` uses — then the tooth
    and the photograph can no longer disagree, which is the entire point of having both.
  ⚠ The mock the UI test builds never runs `_ready`, so `_font` is null there: assign it from the
  same source `_ready` does, or the tooth crashes rather than fails — and if you paper over that with
  a fallback font you are measuring a different typeface than the one in the picture.
- **⭐⭐ A DEFAULTED ZERO RENDERED AS A PASSED TEST** (slice 46, caught by a photograph and by nothing
  else). A rung that switches physics OFF usually stops EMITTING that physics' telemetry — so every
  `.get(key, 0.0)` in the client silently becomes a confident zero, and a line that formats it reads
  as a comparison that was made and came out favourably. Slice 46's HUD printed `RANGE sees` and
  `range 2846 m vs horizon 0 m ⇒ +0 m` **in its green "passed" colour** on the rung where no range
  test exists. ⇒ **pass the rung's state in as a PARAMETER and print `—`/`n/a`; never infer "the test
  passed" from numbers whose absence you defaulted away.** This is the stale-readout class in its
  purest form: not a stale number, a FABRICATED one. ⚠ It is worst in exactly the lines that exist to
  say WHICH limit ran out, because those are the lines a student reads to choose a cure.
- **Compressing a headline must not delete the slice's number.** When a headline is cut to its budget
  the figure it carried has to land in a body line, and a tooth has to assert it there — otherwise
  fixing the width quietly removes the one figure the slice exists to show.
- **Anything the verdict computes inside `_draw` has no headless proof.** Extract it to a pure
  helper the UI test can call.

- **A gate can only price a design variable if the design is on the wrong side of it to begin
  with.** Slice 44 built an exact detection-range gate and it moved nothing, because the
  engagement starts INSIDE the sensor's horizon (`R_acq/R_launch` = 1.255). Before building a
  limit, measure where the shipped wire sits relative to it — one line of arithmetic, and it
  is the whole slice.
- **Before composing a trade out of two times, check the two seconds are interchangeable.**
  Slice 44's V in acquisition TIME was real and priced nothing: a second spent unable to SEE cost
  nothing, a second spent with the servo unable to CATCH UP was unrecoverable. Same axis, same
  units, incommensurable.
- **⚠⚠ THE r → 0 ENDGAME SPIKE REACHES EVERY GUIDANCE QUANTITY, NOT JUST THE ONES ALREADY GATED**
  (slice 46, correcting slice 44 §VII.1). `[[ewsim-missile-verifier-sampling]]`'s range gate was
  written for miss / `a_cmd` / saturation; slice 44 read a NEW quantity — peak `a_cmd` as a fraction of
  `a_max` — and did not gate it, so its "the free cell flies at **100.00 %** of `a_max`" was measuring
  the degenerate geometry of the last fraction of a second. Gated at `r > 200 m` the same cell reads
  **10.45 %** against a free arm's **3.10 %**. ⇒ **when a slice introduces a new guidance-derived
  readout, apply the endgame gate to it before quoting it** — and note which way the correction cuts:
  the effect SURVIVED and became STRICTLY MONOTONE, so the spike was manufacturing the
  non-monotonicity, not the signal. An ungated endgame can invent an effect AND can hide the shape of
  a real one.
- **A flat headline metric can hide a budget being spent to the last percent.** The "free"
  arm of slice 44 flew at **100.00 %** of `a_max` while its miss stayed at 0.25 m; one cell
  further the demand FELL because the track was gone. Carry the authority/contamination column
  even when the headline looks flat — flatness is not slack. (Slice 41's kill inverted: there a
  clamp BOUND and hid a real effect.)
- **A threshold effect at a window EDGE is usually the actuator's, not the window's.** A lock at
  the rim hands the servo a full-window slew. Slice 44's narrow-window misses (362–439 m) all
  became hits at 0.10–0.22 m by tripling the head's slew rate alone, from identical lock instants.
  Re-fly any edge effect at a faster actuator before attributing it to the geometry.
- **Quote the VERDICT, never the metres, once a track is lost.** Post-loss trajectories diverge,
  so the miss samples a divergence rather than measuring one — slice 44's failure magnitudes
  walked 320 → 439 → 627 m across a 4× range of `dt` while every verdict held.
- **⭐⭐⭐ TWO AIMS ⇒ TWO TESTS ⇒ TWO VERDICTS — a gate-0 kill test measures the LESSON, not the
  COMPONENT** (2026-08-18 user reframe, after five consecutive gate-0 records shipped no code).
  *Reparameterizable*, *moves no verdict* and *false-fidelity knob* all answer **does dialing this
  move the authored scenario's headline metric** — a question about the SLICE. The separate
  question is **is the parameter READ by the physics each tick and does the response obey its own
  units/signs/frames** — a question about the MODEL, and the only one whose failure kills a
  component (a knob consumed once at load is a BUG). **Pass model / fail lesson ⇒ "dead as a
  lesson, ALIVE AS A MODEL": ship the hardware with tests and authorable keys, bury the lesson
  claim with its refutation.** ⚠ A reparameterization still must not ship as an ARCHITECTURE
  (slice 39), and new proposals face the unchanged model bar. ⚠⚠ Corollary, and the reason this
  went unnoticed for five slices: **four of the five failed the lesson test against the SAME
  authored engagement** — slice 45's own *"a property measured in one operating mode is not a
  property of the component"*, one level up. Detail: `docs/DEFERRALS.md` §"THE 2026-08-18
  RE-VERDICT".

---

## A quantity that only exists for one tick needs a LATCH, or no client can ever read it (slice 47)

â­â­â­ **A number formed inside one branch of one tick lives on NO later frame â€” and a client sees one
frame in `emit_every` anyway, so it cannot sample that tick even while it is happening.** Slice 47's
whole lesson is one angle at one instant: the pointing error at the moment the receiver first hears
the target. The wire shipped it as an instantaneous key, which is `0.0` the moment the head starts
TRACKING â€” honest (a tracking head has no cue) and useless. Two compounding reasons it is
unreadable, and the second is the one that surprises:

1. **It does not survive the transition.** Any frame after the event carries the post-event value.
2. **The 16-tick emit grid never lands on the event.** Even sampled *during* the blind phase, the
   last emitted frame is up to 15 ticks stale â€” **0.045Â° against a cliff that straddles its
   threshold by 0.05Â°**. The verifier's own log prints both numbers side by side.

â‡’ **LATCH IT INTO STATE AND EMIT THE LATCH AS ITS OWN NEVER-STALE KEY.** âš  And latch it on the
condition that DEFINES the event, not on the outcome: slice 47's cue stops when the RECEIVER OPENS,
not when a lock succeeds, so the latched value is defined on the arms that never acquire â€” which are
exactly the arms that carry the lesson. This is the same defect class as slice 47 gate 2's PIP
(a per-tick local read as telemetry, shipping `[0,0,0]` after handover), caught twice in one slice.

## Two flags that are ALMOST the same flag will be conflated, and the conflation shows up on the ONE arm that matters (slice 47)

âš âš  **`head_cued` and `midcourse_active` are gated on different conditions one line apart** â€” the
head's cue stops when the RECEIVER OPENS, the guidance arm stops when the TRACKER INITIALISES. On
every arm that works, the two flip within a tick of each other and either would do. On an arm that
hears the target and never acquires it, the first has stopped and the second has not â€” **and that is
the arm the slice exists to show**. A HUD line keyed off the wrong one announced a handover that had
not happened, over a missile still flying its stale belief to impact.

â­ **The plan had written the trap down** (Â§6.8 item 5, "two different gates, deliberately, and a
reader that conflates them reports the wrong instant") **and it was walked into anyway.** â‡’ when two
flags differ only on the failing arm, the test has to BE the failing arm â€” asserting the two strings
differ in that state, not merely that each state has a string.

⭐⭐⭐ **SLICE 50, VERBATIM THE SAME SHAPE, AND THE FIRST DEFECT NAMES *WHY* `_draw` IS UNREACHABLE.**
Verifier green, UI test green, smoke-load green — and the shot came back with **two headlines
overlapping**. **There are TWO dispatch chains in `Sandbox.gd`**, one selecting the top-of-screen
verdict LABEL and one selecting the HUD BLOCK, and only the second had been given the new slice's
branch. The file's own standing rule, written out in FIVE separate comments, is *"all dispatch chains
must agree"* — and it was still possible to edit one and not the other with every headless proof
passing, because **`--headless` never runs `_draw`, so a chain disagreement is INVISIBLE to the
verifier and the UI test alike.** ⇒ **after adding a view, grep for every dispatch on the view marker
and count the sites.** The second defect was the vocabulary bug (its own heading below), and a third,
smaller one: the disclaimer line printed a number the view already draws in its shared header — a
redundancy no assertion can judge, because both copies are correct.

## The windowed shot is not a formality: it caught two defects with three suites green (slice 47, and slice 50 is the SECOND occurrence — two defects again)

Convention 14's fourth proof, earning its place twice in one slice, with the verifier (13 arms), the
UI test (12 teeth) and the headless smoke-load all passing. **Both defects live in `_draw`, which
`--headless` never runs**, so no amount of extra assertions in the other three could have reached
them. One was the flag conflation above. The other was a **size budget in a different widget**: the
generic telemetry readout, which had room for ~54 keys and was handed ~72, clipped off the bottom of
the window and grew sideways into the HUD's column.

â­ **AND THE FIX DIRECTION WAS DETERMINED BY A CONSTRAINT, NOT A PREFERENCE.** A fourth column was
impossible â€” three at their natural width already reach the HUD's right-anchored origin, so growing
sideways collides by construction. The only free direction was DOWN, and shrinking the type bought
height and width at once. âš  **This is slice 46's finding one widget over**: there the lines were too
WIDE, here there were too MANY of them. A layout budget is not a per-line property; it is a property
of everything sharing the window.

### ⚠⚠ THIRD OCCURRENCE (slice 52, 2026-08-31) — **THREE DEFECTS, AND ALL THREE ARE ABOUT WHETHER THE PICTURE AGREES WITH ITSELF**

The verifier (17 arms), the UI test (11 teeth, including the band's geometry down to the pixel), the
smoke-load and the full 18632-test suite were all green, and the shot still changed three things:

1. **A FILLED BAND INSIDE A FILLED BAND IS NOT A COMPARISON.** The slice's whole picture is a
   commanded width containing a narrower flown one. At the showcase's opening width the head flies
   92 % of its command, so the outer band was a **two-pixel sliver** either side and the containment —
   the entire content — was invisible. An OUTLINE reads at every ratio, including the 27 % one at the
   slider's floor. ⭐ **A geometric claim needs a form that survives its own extreme case**, and the
   extreme case here is the one the design is *best* at.
2. **A ROUNDED HEADLINE CAN DISAGREE WITH THE CONTROL THE STUDENT IS HOLDING.** `%.0f` on the width
   printed *"SWEEPING 5°"* beside a slider reading **4.75** — at the cliff, which is exactly where a
   student stops to read it. ⚠ Not a truncation bug: every number was right. The defect is that the
   HUD and the widget disagreed, and no assertion in any suite compares them.
3. **THE SAME NUMBER TWICE UNDER TWO LABELS** — slice 50's own finding, arrived at independently and
   caught the same way. The block inherited 47/48's "range %.0f m — the MISS says nothing here" onto
   a view whose shared header already draws "range to target", so the shot came back with 2615 m
   printed twice. ⇒ the disclaimer names the **closing speed** instead, which is the other clock the
   sweep is racing and appears nowhere else on screen.

⚠ All three are invisible to a text-only proof by construction: two are about SPATIAL relations
between drawn things, and the third is about a number's relation to a widget outside the HUD.

## ⭐⭐⭐ A VIEW MARKER MUST SEPARATE WIRES THAT DIFFER ONLY BY THE **SLIDER**, AND ITS GATE MUST BE AN INSTRUMENT, NOT A FLAG (slice 52, 2026-08-31)

Every view marker from 35 to 50 separated wires that differed in PHYSICS — a rung, a comp key, a
target property — so the gate was always something the wire genuinely had that the others did not.
Slice 52's wire is slice 48's wire with a different slider: the same missile, the same anchor, the
same blind phase, the same numbers except three. It therefore authors `:seeker_search` and **raises
slice 48's marker**, and slice 48's HUD block is ALL TRUE on it — the sweep is real, the gap is real,
the lock time is real. What it cannot say is that the WIDTH is what is being dialled.

⚠⚠ **THIS IS THE ONE FORM OF THE INVISIBLE-SLICE FAILURE THAT ORDERING CANNOT FIX.** The family's
standing remedy since slice 35 is "check the newest marker FIRST in every dispatch chain". That works
when a newer marker EXISTS to check. Here there was nothing to raise it on.

⭐⭐⭐ **THE WAY OUT IS TO ASK WHAT THE NEW SLIDER'S LESSON NEEDS ON THE WIRE THAT THE OLD ONE DID
NOT, AND SHIP THAT.** Slice 52 needed the width the head ACTUALLY flew (its gate 2 had measured that
a head flies 0.27–0.95 of its command). That is a real instrument, read every searching tick, and
authoring it is what distinguishes the wire. ⇒ `seeker_search_realized` gates two telemetry keys AND
the marker.

⚠ **A MARKER KEY WITH NO PHYSICS BEHIND IT WOULD HAVE BEEN THE DEAD-KNOB CLASS** — a key consumed at
load and read by nothing, which the two-test rule calls the one outright kill. The test that
distinguishes the two: *does the physics read this key every tick?* If the honest answer is no, you
have written a view flag into a physics bag and should find the instrument instead.

⚠ **AND THE CARRIER SETS MUST BE EXTENDED, NEVER LOOSENED.** Three enumerated sets failed the moment
the new scenario landed (`search_view`, `midcourse_view`, and the `gimbal_rate_dps` list plus its
mirror exemption) — each one the assert doing its job. The NEW marker's set is what still carries the
separation, so it stays a single-file list.

## ⚠⚠ AN "ON EVERY ARM" CLAIM MUST NAME THE ARMS WHERE THE MECHANISM DOES NOT RUN — AND THE EXEMPTION IS USUALLY THE CLAIM (slice 52, 2026-08-31)

`slice52_verify.gd` asserted two things on every arm and both failed on the first run, neither
because the physics was wrong:

- *"the flown sweep is strictly inside the commanded one"* — true wherever a band is swept, and
  **undefined** on the horizon-OFF arms, which register exactly ONE searching frame: the tick the
  branch opens, where `search_sweep(0) === 0.0` by construction (the kernel's own tooth 1). Both
  peaks are a true 0.0 there. ⇒ gate the claim on **a band having been swept** (`told > 0`), not on a
  frame count.
- *"the head sweeps on every arm, because the rate is authored"* — and the mid-run PRESS arm never
  sweeps at all, because the horizon is removed BEFORE the handover so the receiver never opens onto
  empty sky. ⭐ That is not an exemption, it is *you only search because you were blind* — slice 48's
  own sentence — so it ships as `@test searching == 0` rather than as a skip.

⚠ The general shape: when a universal claim fails on an arm, ask whether that arm is **outside the
claim's domain** before weakening the claim. Twice here the arm outside the domain was carrying a
result worth asserting in its own right.

## ⚠ A "HAS THIS ARM DRAINED YET?" PREDICATE MUST BE ARM-SPECIFIC, OR THE SECOND SHOT PHOTOGRAPHS THE FIRST (slice 52, 2026-08-31)

A two-arm windowed-shot harness reset, dragged the slider, stepped N and waited for "the search keys
look live" before capturing. That predicate was **already satisfied by the previous arm's telemetry**,
which a Reset does not clear on the client, so the second shot re-photographed the first arm's frame
with the second arm's filename. ⚠ It printed plausible numbers and the PNG was not obviously wrong.

⇒ two fixes, and the second is the general one: (a) discriminate on a value that is unique to THIS
arm — the slider's own echo coming back off the wire — and (b) **one arm per process**, which has no
previous arm to be confused by. ⭐ The same class as the stale-instrument-across-reset bug this family
has now fixed seven times, moved into the measuring harness instead of the display.

## Retract a rule you inherited if the wire refuses it â€” and say what replaced it (slice 47)

âš âš  **A ban carried forward from a probe the plan itself flagged as CONFOUNDED did not survive contact
with the shipped wire.** Â§3.2 forbade an angle-margin gauge because an early sweep showed it
*improving* while the engagement was lost. Measured on the finished wire it does the opposite in
both samplings a HUD author would use. â­â­ **And the reason it does not invert was worth more than
the ban was: `margin + cue = fov` at the handover instant** â€” the two "rival" gauges are one
measurement counted from opposite ends, asserted to a tenth of a degree on four arms.

⚠⚠ **THE IDENTITY IS SERVO-CONTINGENT, NOT DEFINITIONAL** (advisor, added after the first write-up read as unconditional). `off_head` is BORESIGHT-vs-truth while the cue error is COMMAND-vs-truth, so the two coincide only while the head has **SETTLED** on its cue — true on this wire because the servo is authored at 240 °/s as slice 46's measured isolation, and the 0.12° residual in the verifier's 0.5° tolerance IS that lag. On slice 35's 8 °/s wire they would separate. ⭐ The general form is the transferable half: **two gauges that agree on the shipped wire may be agreeing THROUGH an isolation the wire authors** — write the isolation into the claim, or it gets quoted on a wire that does not have it, which is exactly how the ban it replaced went wrong (slice 45's rule: a property measured in one operating mode is not a property of the component).

â‡’ **the gauge stays off the display, but for REDUNDANCY and not for DECEPTION** â€” a distinction that
matters because the old reason was being quoted as a finding. âš  It took **two wrong assertions**, each
replaced only after a measurement, to arrive at the true one; a verifier that asserts a belief is
worth more than one that avoids the subject, precisely because it fails when the belief is wrong.

## An error a scenario AUTHORS must be read every tick, or the showcase's slider is dead in the hand (slice 47)

âš âš  **Folding an authored perturbation into a one-time snapshot is algebraically free and kills the
slider.** Gate 2 minted "truth plus the authored error" once, at launch â€” identical arithmetic to
adding the error at every read, and it made the error a key **consumed on the first blind tick**,
which is this project's own definition of a dead knob (slice 36's `_DEAD_KNOB_KEYS`: *"consumed once
â€¦ a slider on it is dead in the hand"*). Gate 3's entire showcase was a slider on that error.

â‡’ **snapshot the TRUTH; apply the authored error at every READ.** âš  And preserve the association
when you move it: `(p0 + e) + vÂ·Î”t` is byte-identical to the folded form, `p0 + (e + vÂ·Î”t)` is not â€”
the absolute golden would fail and read as a physics change.

â­ **The scalar that carries it needs two loader refusals, and both are CRASH guards.** `set_param`
carries one Float64, so a slider on a `Vec3` comp key overwrites the vector with a bare number and
the next type assertion throws INSIDE a tick â€” a dropped connection, not an error message
(convention 5). And a dimensionless multiplier only reads in honest SI if the vector it scales is
UNIT length, so the loader refuses the knob otherwise: **the label's units become true by
construction instead of by coincidence.**


## ⭐⭐⭐ When a head-pointing probe reports "never", LOG THE HEAD'S ACTUAL ANGLE AGAINST THE COMMANDED ONE **BEFORE** BELIEVING IT (slice 48 gate 0, and it is the FOURTH occurrence)

A clamp is **invisible in every downstream number.** `head_clamp` absorbs a commanded angle past the
mechanical stop silently and by design — the head simply sits at the stop — so a probe that drives
the head through `:head_tgt_*` and reads only the outcome sees a clean "never acquires" with no tell
at all. Slice 48's gate 0 wrote a whole section (§4.3c) blaming the WIRE, complete with algebra, for
a result that was **the 30° trunnion eating the sweep on 27–37 % of ticks** while the probe commanded
48–53°.

**THE TELLS, ALL VISIBLE IN THE FAILING TABLE ITSELF** (an advisor read them out of it before any new
measurement was taken):

- **A SMALLER demand failing where a LARGER one succeeds.** A 2.93° gap never acquired while a 4.04°
  gap did. Monotonicity broken in the *wrong direction* is a clamp, not a physics boundary.
- **A demand INSIDE the authored window that still does not produce a lock** (8.94° against a 10.0°
  window). *If the requirement is met and the outcome does not follow, something other than the
  requirement is refusing it.*
- **A lock followed by 0 % of `a_max` and a full-magnitude miss**, and **intermittent hold** (72–77 %)
  on the cells that do lock. Both are continuity signatures, not budget signatures.

⚠⚠ **THE ANGLE THE PROBE READS IS USUALLY NOT THE ANGLE THE STOP ACTS ON.**
`head_cue_err_handover_deg` is cue-vs-**truth**; the stop acts on the **body angle**. On a wire whose
truth LOS body angle swings +18° → −15° over the approach, a cue 13° off truth sits at 25–31° of body
angle — past a 30° stop — so the two readings disagree by the whole excursion. **Log the quantity the
CLAMP sees, not the quantity the lesson is about.**

⭐ **THE PRIOR THREE, so the pattern is not read as bad luck:** slice 43's `p7b_frontier.jl`
TELEPORTED the head in every cell (no τ, no `rate_max`, no `head_slew_full`) and its whole ρ_min
table had to be withdrawn; slice 45's box rescue needed a matched-half-width control before it meant
anything; slice 42's `off@lock == fov` column was the inclusive gate echoing its own authored
constant back. **Every one of them was an instrument reporting on a head it was not actually
driving.**

⇒ **THE CHEAP GUARD, and it is three lines:** count the ticks where `|head_az|` sits within a hair of
`gimbal_stop_deg`, and print it beside every verdict. A probe that reports `TICKS ON THE STOP: 28.3 %`
cannot publish a wire conclusion by accident.

⭐⭐ **AND THE CLAMP WAS ALSO A FINDING**, which is why this is not merely a hygiene note: **mechanical
travel is a HARD CEILING ON SEARCHABLE VOLUME** — a search can only look where the trunnion points,
and the cue itself already spends most of the travel. That is slice 45's elevation stop (*read,
clamping, working hardware*, binding 66–68 % of in-band ticks) arriving on the azimuth ring. **An
artifact that survives being understood is a component.**


---

## ⭐⭐⭐ A RANGE GATE IS NOT ENOUGH ON ITS OWN — THE POST-CPA RE-CROSSING COMES BACK THROUGH IT FROM THE FAR SIDE (slice 48, 2026-08-26)

**The trap.** Every guidance quantity in this arc is read under a range gate (`r > 200 m`) because the
`r → 0` endgame spikes all of them — that discipline is old and it is right. Slice 48's gate-0 and
gate-2 probes applied it and nothing else, and read a post-lock authority peak of **78.2 %** on the
arm that carries the lesson. The verifier, which ALSO gates on the first descending band, reads
**71.2 %** on the same arm of the same wire.

**Why.** The gate is on the range, and the range is not monotone. After CPA it climbs back **through
the same 200 m boundary from the outside**, into a region where the missile is turning around behind
the target and every guidance quantity is meaningless. A `r > 200` filter re-admits exactly that.

⇒ **THE PAIR IS THE DISCIPLINE, NOT EITHER HALF: gate on `r > R_min` **AND** on the first descending
band.** The closing-band gate alone lets the endgame spike in from the inside; the range gate alone
lets the post-CPA re-crossing in from the outside. Both, or the number is not the one you think.

⚠ **AND THE FAILURE IS SILENT AND PLAUSIBLE**, which is why it survived two gates: 78.2 % against
71.2 % is not an outlier, it is a slightly worse-looking version of the right answer, and it was
quoted in a plan log and a scenario header before the verifier caught it. This is the fourth slice in
the arc to be bitten by this family ([[ewsim-missile-verifier-sampling]] carries the others).

## ⭐⭐ A HARD-CODED SHRINK STEP GUARANTEES THE NEXT SLICE RE-OPENS THE DEFECT — SOLVE FOR THE FIT (slice 48)

**The trap.** Slice 47 found its telemetry readout running off the bottom of the window and fixed it
with a single step: `if rows * 19 > available: font = 11`. That was sized on ITS key count (24 rows ×
15 px = 360 against 388 px of room) and it fitted — exactly, and only, for that count. Slice 48 ships
**seven more keys**, 27 rows × 15 = 405 px, and the last row of every column printed straight through
the badge below the panel. The fix was re-opened by the next slice's arithmetic, on a widget that had
just been repaired.

⇒ **WHEN A LAYOUT MUST FIT, WRITE THE FIT, NOT A STEP.** A row is ~1.36× the font size at every size,
so `while fsize > floor and rows * fsize * 1.36 > available: fsize -= 1` cannot be re-opened by an
eighth key. ⚠ And the TOOTH must assert the fit (`rows × fsize × 1.36 ≤ available`), not the step
(`fsize == 11`) — a step-shaped assertion passes on the very wire where the layout overflows, which is
what slice 47's did.

⭐ **The general form, and it is bigger than layouts: a constant chosen to satisfy today's arithmetic
is a latent failure with a slice number on it.** The same shape as the range gate above — a threshold
that happens to be sufficient is not a rule, and the next wire is where the difference shows.

## ⚠ WHEN A PROBE AND THE SHIPPED SEAM DISAGREE ABOUT A FREEBIE, SUSPECT THE PROBE'S ORACLE (slice 48)

Slice 48's gate-0 probes forced the SWEEP DIRECTION by reading TRUTH (`dir = sign(cue_az − truth_az)`)
so that every cell paid the wrong-side cost — deliberately, and the plan said so. The SHIPPED kernel
cannot read truth: it always opens toward `+`. On the shipped wire that turned out to be **straight at
the target** (+12.94° of body azimuth), so every arm locked inside 0.27 s and the slider taught
nothing — the probe had been measuring a harder problem than the code could pose.

⇒ **A PROBE THAT USES TRUTH TO SET UP THE HARD CASE IS MEASURING A DIFFERENT WIRE.** Either the
scenario must AUTHOR the hard case (slice 48 flipped the belief-error direction so the sweep opens
away, and wrote the reason into the YAML), or the claim has to be restated as "on this geometry".
⚠ The tell is a gate-2 table that is uniformly EASIER than gate 0's — the direction of the surprise
matters, and this one was in the direction that flatters the component.

## ⭐⭐⭐ A GAUGE MUST CARRY ITS OWN WINDOW — AND IF THE WIRE CANNOT EXPRESS THE WINDOW, SHIP THE KEY THAT CAN (slice 49, 2026-08-26)

Slice 49's headline number is *the longest loss run **while closing***. The qualifier is not a
caption: the target flies a circle, passes CPA at ~7.8 km and opens again still nose-off, so it stays
invisible for the rest of the run. A clock that merely measures "how long has it been gone" therefore
**never stops**, and drifts above the ladder's own 36.50 s — printing a number that is not the
slice's, under the slice's label, on a display that looks entirely reasonable.

The radar had never shipped a RANGE. So the client *could not* have implemented the window at all,
and the two honest exits were (a) label the readout as the whole-flight number it actually is, or
(b) ship `target_range_m`. (b) was chosen because it also makes the HUD and the verifier read the
SAME quantity from the SAME place (convention 7) and turns "range given up" into a subtraction of two
wire values rather than a geometry recompute in GDScript (convention 13).

⇒ **Before writing a display instrument, state its window out loud and check the wire can express it.
A gauge whose window exists only in the prose is a gauge that will quietly outgrow its own label.**
The same reasoning already produced slice 47's post-handover authority peak (gated *after* the blind
phase, not whole-flight) and slice 48's range gate — this is the third occurrence, and the first
where closing the window required a NEW KEY rather than a filter.

## ⭐⭐⭐ A LIVE SLIDER DRAG INVALIDATES A DISPLAY INSTRUMENT JUST AS A RESET DOES — AND IT REACHES NONE OF THE FOUR PROOFS (slice 49, 2026-08-26)

Every stale-instrument fix in this family hangs off `_on_reset_pressed` — 26's ring, 35's duty, 36's
two, 46's two, 47's three, 48's one, 49's six. **All seven were fixing the wrong doorway alone.** The
DRAG is the showcase's primary interaction and it is invisible to convention 14's whole battery:

- the **verifier** sends a `reset` between arms (so it never drags),
- the **UI test** presses the Reset BUTTON (so it tests the other doorway),
- the **smoke-load** never touches a control,
- the **windowed shot** is one static frame.

Slice 49's case: open at the authored fineness with the target lost and the gauge running, drag down
to a sphere. The target reappears and the HUD reads `BACK — it was gone 26.9 s` over `longest closing
loss 26.99 s / 5.84 km` — **the needle's number displayed under a sphere**, i.e. the exact comparison
the slice exists to show, shown backwards. Found by advisor review *after* all four proofs were green.

⚠⚠ **AND THE FIX HAS A SPLIT IN IT; CLEARING EVERYTHING IS ALSO WRONG.** Sort the instruments by what
they belong to:

- **What belongs to the thing the slider changes** — clear it. The measurement was made on a
  different object. (Here: the loss gauge and the live run behind it.)
- **What belongs to the RUN** — keep it. The trajectory did not restart. (Here: the closing/opening
  window. Clearing it re-seeds the previous range with nothing to compare against, so the turn is
  re-detected one frame later — one frame of "STILL CLOSING" painted over a target that is already
  opening.)

`_on_reset_pressed` clears both groups, correctly, because a reset restarts the run as well.

⇒ **Add a drag tooth to every slice that latches or peak-holds anything, and assert BOTH halves of
the split.** Then confirm it bites by removing the fix and watching it fail (convention 11).

⭐⭐⭐ **SLICE 50 SHARPENS THE SPLIT INTO A RULE ABOUT *WHAT KIND OF THING* IS LATCHED: A LATCHED
DURATION MAY RESTART MID-FLIGHT; A LATCHED INSTANT MAY NOT.** Slice 49's instrument is a STOPWATCH —
how long the target was gone — and a drag correctly CLEARS it and lets it run again, because a
duration's meaning is local to the stretch of run it accumulates. Slice 50's instrument is a MOMENT:
the instant the picture went away and how much heading was still owed at it. **An instant's meaning is
the whole history that led to it, and a live knob rewrites that history**, so restarting the
measurement would silently attribute one shape's flight to another. ⇒ slice 50's drag **DISARMS** the
latch for the rest of the flight, shows `SHAPE CHANGED — Reset to measure` and **no number at all**,
and only Reset re-arms it. ⚠ A verdict-WORD distinction would have been a display patch over a
semantic collision — the number itself would still be mislabelled. ⚠ The LIVE lines (detect lamp,
horizon, range, aspect) are untouched either way, which is what keeps the drag a teaching instrument
rather than a switch that blanks the screen.

## ⚠⚠ GREP THE WHOLE FILE FOR FORMAT SPECIFIERS — A `print` IS PROVED BY ITS OWN OUTPUT, A `_fail` MESSAGE IS PROVED BY NOTHING (slice 49, and the THIRD occurrence)

GDScript's `%` supports a small set of specifiers; an unknown one makes the **whole** format fail
SILENTLY and print the format string itself. Slice 21 shipped it, slice 25 reproduced it verbatim, and
slice 49 committed it **twice in one file**:

1. On a live `print` (`S49V_REPLAY max|Δpos| = %.12f m, max|Δsigma| = %.12e m²`) — caught only by
   **reading the output of a run that exited 0**. Nothing failed; the line simply printed itself.
2. Inside the sphere-null **`_fail` message**, a branch nothing had ever executed. No test reaches it,
   no green run prints it, and it would have produced gibberish on the one day it mattered — when the
   model's own null broke. Found by sweeping the file with a regex for any specifier outside
   `f`/`d`/`s`/`%`.

⇒ **The mechanical check is the only reliable one:** `re.findall(r'%[-+ 0-9.#]*[a-zA-Z]', src)` and
read every hit, including the ones in strings you have never seen printed. ⚠ And note the second-order
trap this exposes: a near-zero residual has no printable fixed-point form — `%.3f` of 1e-16 is
`"0.000"`, which **reads as a PASS inside a FAILURE message**. Slice 49 ships a hand-rolled `_sci()`
(the `Sandbox.gd:_fmt` construction) for exactly that. Same family: `%%` is an escape for the `%`
OPERATOR, so a plain literal with no operator applied prints the doubled sign (slice 48 hit this, and
so did 49).

## ⚠ AN EXACT IDENTITY BELONGS WHERE IT CAN BE STATED EXACTLY — A FRAME-SAMPLED CLIENT CANNOT SEE `t = 0` (slice 49)

`slice49_verify.gd`'s first draft asserted that the effective RCS on the opening frame IS the authored
broadside value, exactly. It failed at 3.999867 against 4.0 — **correctly**. The first frame a client
ever receives is `emit_every` (= 16) ticks AFTER launch, by which time the target's nose has come
~0.09° off broadside and the model has legitimately moved σ.

The identity is real and is worth pinning — it is what lets `rcs_m2` keep its authored meaning under a
normalized aspect model. It is pinned **in the core**, where `test_rcs_aspect.jl` can evaluate θ = π/2
directly, to 1e-12.

⇒ **When a client-side tooth wants an exact identity, ask what the client can actually observe.** Two
substitutes are usually available and both are better than a loosened tolerance:
- **a near-equality with a MEASURED tolerance and the cause named in the comment** (here: 0.1 %,
  because 16 ticks is ~0.09°, not because 1e-6 "felt tight"), and
- **a ONE-SIDED anchor that IS exact** (here: no frame may ever be BRIGHTER than the broadside value,
  because broadside is the peak of a prolate body's curve — true on every frame, at every fineness).

⚠ Same root cause as the frame-sampling asymmetry in [[ewsim-missile-verifier-sampling]]: the client
sees a grid, not the continuum, and a tooth written as though it sees the continuum is measuring the
emit cadence.

## ⚠ THE DEFAULT VALUE OF A MISSING TELEMETRY KEY IS A CLAIM — PICK THE ONE THAT ASSERTS THE LEAST (slice 49)

`docs/CONVENTIONS.md` §14's standing warning is that `.get(k, 0.0)` prints a defaulted zero as a
passed test. Slice 49 adds the sharper half: **which** default you pick is itself an assertion, and on
an aspect HUD the conventional 0.0 is the loudest possible one — an aspect of 0° means **NOSE-ON**,
the single state the whole lesson is about. A frame carrying no evidence would have asserted the
slice's own conclusion.

The shipped default is **90° (broadside)**, the state that claims nothing: it is where the curve peaks,
where σ_eff equals the authored value at every fineness, and where the model is a no-op. Likewise
`detected` defaults to TRUE (no evidence of a loss is not a loss) and `rcs_loss_db`'s absence is
tested for rather than defaulted, since 0 dB would read as "a target at its BRIGHTEST".

⇒ **For every `.get(k, default)` in a readout, ask what the default SAYS if the key never arrives. If
the answer is the thing you are trying to demonstrate, the default is wrong.**

⚠⚠ **AND SLICE 50 FOUND THE CASE WHERE NO CHOICE OF DEFAULT CAN SAVE YOU: THE LESSON'S OWN NULL AND
THE DEAD INSTRUMENT ARE THE SAME NUMBER.** Its gauge reads `0.000°` when the target is round and the
lock is never lost — which is the lesson's null, a real and meaningful measurement — and a missing
`seeker_tgo_s` read through `.get(k, 0.0)` also reads `0.000°`. **No value assertion anywhere can
separate them**, and unlike slice 49's aspect there is no "quiet" default available: the quiet value
*is* the null.

⇒ **When a lesson's null collides with a dead instrument's default, PRESENCE is the only
discriminator — track it independently of value, and make the HUD say WHICH of the two it is
holding.** Slice 50 prints *"no heading error owed — the shape is round"* against *"gauge unavailable
— `seeker_tgo_s` not on the wire"*, asserted in both directions (`slice50_ui_test.gd` tooth 9).

## ⭐⭐⭐ A RATE CANNOT PREDICT A LEVEL CROSSING WITHOUT THE HEADROOM (slice 50 gate 0, 2026-08-26)

Slice 50 pre-registered a gauge and it failed, in the most instructive way available. The mechanism
was real: a manoeuvring target's detection horizon **retreats**, and on the losing arms it retreats up
to **three times faster than the missile closes**. So the obvious gauge was the ratio of those two
rates, and it looked perfect — strictly monotone across the whole slider, `dt`-stable to 0.064 %.

**It crossed 1.0 five slider steps before anything was ever lost.** At a fineness of 3 the horizon
retreats **1.10× faster than the missile closes and the lock never breaks, not for one tick**; at 5 it
retreats 1.78× faster and still never breaks. The lock survives because the horizon **started 32 %
above the range**, and a rate has to spend that headroom before it can produce the event.

⇒ **A RATE gauge and a LEVEL event are not interchangeable.** A rate can exceed its comparator for an
entire flight and never produce the crossing; the missing term is the headroom the level started with.
The rate says *how hard the target is pushing*, a margin says *whether it worked*, and only the second
has a threshold in it.

⚠ **AND THE PRACTICAL RULE THAT FALLS OUT: pre-register the PREDICTIVE test, not just monotonicity and
`dt`-stability.** Slice 50's §5.5 fixed all three before the probe ran — *monotone*, *< 1 % at half
`dt`*, *and the 1.0 crossing lands in the same interval as the first observed loss*. The first two
passed and would have shipped a gauge that describes the mechanism without predicting the event. **The
third test is the one that earned its place, and it is the one easiest to leave out.**

## ⭐⭐ WHEN A MODEL TOUCHES ONLY THE DETECTION AND NOT THE DYNAMICS, EVERY AT-EVENT GAUGE IS THE EVENT TIME IN OTHER UNITS (slice 50 gate 0, 2026-08-26)

Slice 50's aspect model changes **when the target can be seen** and nothing else — it is not in the
airframe, the guidance or the mover. Consequence, measured rather than argued: **every arm of the
slider flies a bit-identical engagement (`max|Δpos|` = `0.000e+00` m) until its own first loss.**

⇒ the sphere's LOS rate at arm *F*'s loss tick **equals arm *F*'s own, to machine precision, on every
arm.** So ‖ω_LOS‖, the range, the closing speed, the time-to-go and every product of them, **read at
the loss**, are functions of the **LOSS INSTANT ALONE**. They carry identical information.

⇒ ⭐⭐ **THE CHOICE AMONG AT-EVENT GAUGES IS A CHOICE OF UNITS, NOT OF INFORMATION** — so it cannot be
made on monotonicity or stability (they all inherit the event time's) and must be made on **what
sentence each one lets you say**. Slice 50 chose `ω_LOS · t_go` ("the heading error the missile went
blind holding") over the loss RANGE, which is the simpler quantity and carries exactly the same
information — because a ground radar can say *"the range at which I lost it"* perfectly well, and the
slice's whole job was to say something a ground radar cannot.

⚠⚠ **RECORD THE IDENTITY IN THE LEDGER.** A reader who discovers later that the gauge is a
reparameterization of a simpler quantity, and finds it unrecorded, will read it as a gauge dressed up.
⚠ This is NOT slice 39's reparameterization kill — that rule forbids a reparameterization shipping as
an **ARCHITECTURE**. Using one to convert a domain-generic quantity into a domain-specific one, with
no new machinery built, is what a reparameterization is *for*.

⭐ **THE TEST, and it is cheap:** take the NULL arm's series, look up its value at each live arm's
event tick, and difference. Zero ⇒ your gauge is the event time wearing units.

## ⭐⭐⭐ A VOCABULARY IS A GAUGE AND MUST BE SCORED LIKE ONE (slice 50, 2026-08-26)

Every numeric gauge on this arc is scored for **resolution over its own slider's domain** — slice 28's
`k`, 40's `ω_n`, 25's `σ_seek` and 20/22's miss were all disqualified for failing exactly that, and
slice 50's gate 0 threw out its own pre-registered gauge partly on the same ground. **The WORDS printed
beside those numbers have never once been scored.**

Slice 50's HUD prints a plain-English word for the target's aspect, and `_s50_word` inherited slice
49's bands, which are ABSOLUTE (70–110° → "broadside"). **This wire never leaves that one band:**
launch is 90° and every loss on every arm is between 71.9° and 81.5°. The vocabulary was therefore
CONSTANT across the entire teachable domain — zero resolution, the identical objection that killed the
numeric candidates.

⚠⚠ **AND IT WAS WRONG, NOT MERELY USELESS — WHICH IS THE PART TO CARRY.** The constant word was
"broadside", i.e. *at its brightest*, and it was printed on the one frame that carries the lesson: the
echo ~18 dB down and the line directly beneath it reporting that the horizon had collapsed inside the
range. **Every number on screen was correct and the sentence they added up to was the reverse of the
slice's own conclusion.**

⇒ **Band a HUD's vocabulary on the quantity that MOVES on this wire, not on the one the previous
slice's wire moved.** Slice 50 re-banded on the DEPARTURE from broadside, `|90 − θ|`, which is what the
horizon actually follows (`R_acq = R_broadside / sqrt(1 + F²δ²)`).

⚠ **The "keep it consistent with the previous slice" argument is usually not available on inspection.**
`_s50_word` was ALREADY a separate function from `_asp_word`; only the numbers had been copied. The
fork existed and re-calibrating created no drift with anything.

⭐ **THE TOOTH, and no proof in this family had ever carried one** (`slice50_ui_test.gd`, tooth 9b):
the word must CHANGE between two reachable states, must RESOLVE across the slider's extremes, must
never read the word for the GOOD state at a value where the lesson says the state is bad, must still be
reachable where it IS true, and must respect whatever symmetry the underlying model has as an IDENTITY.

## ⭐⭐⭐ "BYTE-IDENTICAL BY CONSTRUCTION" IS A CLAIM ABOUT WHICH SHIPPED WIRES SATISFY THE GATE — CHECK THEM BY NAME (slice 50, 2026-08-26)

Convention 2 makes byte-identity the master check, so every new telemetry key gets placed behind a
presence gate and justified with some form of *"a key added there is byte-identical on every prior wire
by construction."* Slice 50's plan wrote exactly that sentence at gate 0 about the `_det_on` block —
**and it was false.** `_det_on` is TRUE on slices **46, 47 and 48's** wires, all three of which author
`detect_pt_w` and run the `:snr` rung, and `test_missile.jl` pins `length(a.keys0) == 5`. All three
would have grown the key and the suite would have gone red.

⭐ **THE PLAN GOT THE PRINCIPLE RIGHT AND MIS-APPLIED IT ONE LINE LATER.** It correctly retracted *"just
emit it always"* on the grounds that a presence-gated key is gated for a reason — and then proposed a
home whose gate it had not checked against the wires that actually satisfy it.

⇒ **THE PHRASE IS NOT A PROOF; IT IS THE THING THAT NEEDS ONE.** Grep the gate's condition across
`scenarios/` and name the wires that satisfy it. Slice 50's key ships behind a conjunction (an `:snr`
seeker **AND** a shaped target) whose two sets are **DISJOINT across every shipped scenario** — that is
a checkable statement, and it is what "by construction" was pretending to be.

⚠⚠ **AND VERIFYING THE FORMULA IS NOT VERIFYING THE SITE.** Slice 50 verified that its new key's
*expression* reduced to the probe's, and never checked that a **phase-3** write agrees with the
**phase-4** quantity the probe had actually read. Nothing moves between `observe!` and `decide!` —
*should* being the word that precedes a pinned number nobody measured. Measured: `max|Δ| = 0.000e+00`
over every tick of every arm, and only then did the gate-0 table stand on the shipped key. **A tick has
phases; two keys that "obviously" agree are two measurements until one is differenced against the
other.**

⚠ **SAME FAMILY, THIRD FORM: a rule inherited from another slice must be re-checked against the
QUANTITY it constrains, not the situation it was written for.** Slice 50 §0.6 required slice 48's
rim-margin conjunct on its tick test. 48's rule is about the ANGULAR window; this loss is a RANGE-gate
loss, and `missile.jl` ships the two verdicts as separate lamps on purpose. The conjunct would have
been a no-op that looked like a safeguard. Record the N/A rather than dropping it silently.

## ⭐⭐ `emit_every` IS PART OF ANY GAUGE LATCHED AT A TRANSITION — PIN THE **EMITTED** NUMBERS (slice 50, 2026-08-26)

Gate-0 probes run in Julia at `dt` and see every tick. **The client never sees that grid.** With
`emit_every: 16` the 1 → 0 transition a HUD can latch on lands up to one emission interval after the
true event, so a gauge read AT that transition is systematically offset:

| `F` | per-tick (the probe) | **emitted (what ships)** |
|---|---|---|
| 7.5 | 1.183° | 1.179° |
| 8.0 | 2.389° | **2.380°** |
| 10.0 | 5.771° | **5.702°** |

The shift is DETERMINISTIC, not noise, so it pins perfectly well — but it must be pinned **from frames a
client is actually handed**, or the verifier and the probe disagree by an amount nobody can explain.

⇒ **This is slice 47's "the differencing window is part of the estimator" in a second currency: when a
gauge is latched at a TRANSITION, the EMISSION INTERVAL is part of the estimator.**

⚠ **AND IT RE-SITES THE BYTE-IDENTITY TOOTH BY ONE FRAME.** The "this arm is bit-identical to the null
until it loses the lock" tooth must be measured at the last frame the arm still HELD the lock (`k − 1`),
not at the frame it lost it on. At the loss FRAME the arm has already coasted a few milliseconds
(7.4e-8 m at `F` = 8, 2.0e-5 m at `F` = 10) — that divergence is the coast, measured correctly, and a
tooth sited one frame later reads it as a failure of the identity.

## ⭐⭐ A NULL ARM AND A SUB-THRESHOLD ARM ARE DIFFERENT CONTROLS, AND A SLIDER NEEDS BOTH (slice 50, 2026-08-26)

The obvious control for a mechanism is the arm with the mechanism switched OFF — slice 50's sphere,
slice 49's sphere, slice 48's frozen head. **It proves the mechanism exists and nothing about where it
bites.**

Slice 50 ships a second control: `F` = 7, whose echo is **452.4× dimmer than the sphere's at the
IDENTICAL geometry** (the two flights are bit-identical over all 500 frames) and whose lock is **still
never lost**. That is what turns the result from *"more shape → worse"* into *"there is a THRESHOLD,
and here is a target three orders of magnitude dimmer sitting below it."*

⇒ **When a lesson claims a threshold, put an arm just under it.** A separation measured only against
the null is a separation from zero, and it cannot distinguish a threshold from a slope. ⚠ It is also
the arm that catches a mis-sited gate: a sub-threshold arm that DOES trip is a much sharper failure
signal than a null arm that does not.

## ⭐⭐⭐ HALF A PAIR IS NOT A MARKER — AN OPTIONAL FIELD IN A VIEW MARKER IS A LATENT STALE-READOUT BUG (slice 50, 2026-08-26)

A relational readout names a PAIR: an aspect angle belongs to a target **and** an observer, and the
same aircraft is side-on to one radar and head-on to another at the same instant. Slice 49 raised its
marker on **ANY shaped target** and merely omitted the observer key when no radar was present — which
looked like harmless defensive code for a whole slice, because **no slice-1..49 wire could reach it.**

Slice 50's wire is the first with a shaped target and no radar. The block would have rendered:

> `HOLDING IT: 90° broadside` / `echo 0 m² — 0.0 dB below broadside` / `range 0.0 km  Pd 0.00  SEEN`

over a target turning nose-on at 3 g and seconds from being lost. **Six defaulted numbers, no failing
test, and the two loudest of them ("broadside", "SEEN") asserting the exact opposite of the lesson.**

⇒ **The fix belongs in the CORE, not the client: a marker that names a pair must REQUIRE both halves
and return `nothing` without one.** A client cannot defend itself here — every value it read was a
legal default of the right type.

⚠ **This is the same defect as the vocabulary lesson above, in DEFAULTED form rather than COMPUTED
form, and both shipped in the same slice.** ⇒ when a HUD block is keyed off a marker, the question is
not only *"are the numbers right?"* but *"is this block entitled to draw at all on this wire?"*

## ⭐⭐⭐ A BAN ON A GAUGE CAN BE A BAN ON A REGION OF THE FLIGHT — CHECK WHICH ONE YOU INHERITED (slice 51 gate 0, 2026-08-31)

Slices 44, 46, 48 and 50 each banned the MISS as a gauge on the missile-seeker arc, and all four gave
the same reason: **a blind coast is an open-loop integration, chaotic in its initial condition.**
Every later slice read that as *"do not use the miss."*

Slice 51 tried to price a RE-ACQUISITION — a different quantity, in a different currency (authority
and owed heading, never the miss), with a proper counterfactual arm — and the same reason killed it.
Measured on the SHIPPED slice-50 wire with nothing emulated, full `dt` against half `dt`:

| measured | `t_loss` | `r_loss` | `t_back` | head angle at the return | does the track resume? |
|---|---|---|---|---|---|
| drift at half `dt` | **0.06 %** | **0.04 %** | **11 %** | **179–2742 %** | ⚠⚠ **FLIPS** at `F` = 9.0 |

At `rcs_fineness` = 9.0 — *inside a shipped slider's own domain* — the tracker comes back at one step
size and never comes back at the other, and the CPA goes 33 m → 685 m.

⇒ **The ban was never about the miss. It is about WHERE IN THE FLIGHT a number is read.** Everything
at the loss reproduces. The miss was simply the first quantity anyone tried to read on the wrong
side of it.

⚠ **AND SAY THAT PRECISELY — THE FIRST DRAFT OF THIS LESSON OVERSTATED IT.** It read *"nothing after
the blind phase reproduces,"* which slice 51's own probe P9 contradicts: once the guidance loop is
CLOSED again the flight RE-CONVERGES, and arms that resume early agree across step sizes. What does
not reproduce is the **BOUNDARY** — which side of *"does the track come back at all"* a marginal
setting falls on — plus everything measured while the loop is still open. The distinction matters
because it is not a counsel of despair: a slice may read a number after a blind phase if it stays
well clear of that boundary and says how far clear. ⚠⚠ What a slice may NOT do is SCORE the boundary,
and the boundary is precisely what a re-acquisition lesson would have to score — which is why 51 dies
and a future slice need not. **An over-broad ban retires work that was never in danger**, which is
the same failure the 2026-08-18 two-test re-verdict was written to stop.

⚠ **The practical rule:** when you inherit a ban, ask whether it names a QUANTITY or a REGION. A
quantity ban is discharged by choosing a better quantity — which is exactly what slice 51 did, three
times, before discovering the ban was not that kind. **A region ban is discharged only by moving the
measurement, or by not making it.**

⭐ And the cheap test that would have found it first: re-fly at half `dt` and diff the QUALITATIVE
verdicts, not only the numbers. A percentage on a near-zero quantity is noise; a boolean that flips
is the whole finding.

## ⭐⭐ TWO FLAGS THAT ARE ALMOST THE SAME FLAG — THE **THIRD** OCCURRENCE, AND THIS TIME IT IS A LESSON'S OWN SENTENCE (slice 51, 2026-08-31)

Slice 47 recorded that two nearly-identical flags get conflated and that the conflation shows up on
the one arm that matters. Slice 50 kept them apart correctly IN THE CODE — `seeker_detect` is the
RANGE verdict alone, `gimbal_valid` is the `in_fov` conjunction, and its STATUS block says so — and
then wrote its PROSE against the range lamp: *"lock given back — yes"* on both live arms.

Slice 51 measured what the sentence covers. On `rcs_fineness` = 9.25 / 9.75 / 10.0 the echo returns
before CPA and the tracker **never resumes**, because the head has drifted 15–24° off a 10° window
while it had no measurement to slew on. Those flights are **bit-identical** (`max|Δpos|` =
`0.000e+00`) to arms whose horizon was collapsed at the loss and never allowed to return.

⇒ **A LOCK IS GIVEN BACK BY THE HEAD, NOT BY THE ECHO.** ⚠ No shipped test is wrong — slice 50 pins
at-loss quantities only — but a reader of the ledger would have carried the wrong picture.

⚠⚠ **AND THE OBVIOUS GAUGE FOR IT IS A TAUTOLOGY, WHICH IS THE PART THAT NEARLY SHIPPED.** *"The
recovery is worthless when the head angle at the return exceeds the window"* is `head_off > fov`,
which **is the definition of `in_fov`** — slice 42's `off@lock == fov` column, the inclusive gate
echoing back its own authored constant. A quantity can be the right EXPLANATION and still be a
forbidden GAUGE. ⇒ before scoring a slider on a threshold, ask whether the threshold is a
MEASUREMENT or the gate's own definition read back.

## ⭐⭐⭐ A KILL RECORD MUST SHOW **BOTH** TESTS — WRITING THE RULE DOWN IS NOT APPLYING IT (slice 51, 2026-08-31)

The 2026-08-18 re-verdict exists because slices 41–45 killed COMPONENTS for failing a LESSON test.
It is in `CLAUDE.md`, loaded every turn, with its own ⭐⭐⭐ heading. **Slice 51's kill record still
applied only the lesson half** — it ran three gauges, four counterfactual arms and a half-`dt` re-fly,
concluded "killed", and wrote *"no component was proposed"* as if that closed it. It took the user
saying **"we are developing also a simulator"** to get the second test run at all. Given it, the same
probe data yielded an authorable key worth shipping and a model gap worth naming.

⚠ **The failure mode is specific and it is not forgetfulness.** A gate-0 probe campaign is BUILT
around the lesson question — every falsifier, every arm, every table column is aimed at "does dialling
it move a headline?". By the time the verdict is written, the lesson test is the only test in the
author's head, and "no component was proposed" reads as a fact about the slice rather than what it
is: **a fact about the QUESTION the author chose to ask.** A rule is not applied by being loaded.

⇒ **THE PROCEDURE, and it is cheap:** a kill record does not close until it answers, in writing and
as a separate section, **"what would this ship if the lesson question had never been asked?"** Sources
to check, in order:

1. **What did the probe have to EMULATE from outside the core?** Slice 51 faked a turn onset by
   writing `:a_lat_mps2` per tick. **A quantity a probe must fake is a quantity the simulator is
   missing** — this is the single highest-yield question, and the answer is usually already sitting
   in the probe's own §I.
2. **What behaviour did the probe EXPLAIN that no comment in the core admits to?** Slice 51 found the
   seeker throws away an echo returning off-boresight. That was never a decision; it was the absence
   of a branch, and an absence cannot be found by grep. **Name it at the site, even if you do not fix it.**
3. **Which of the dead gauges would be a fine TELEMETRY KEY or explanatory variable?** Failing as a
   score is not failing as an output.

⚠ **And the verdict WORD is part of the record.** "DEAD" and "DEAD AS A LESSON, ALIVE AS A MODEL" are
read by future slices as permission or prohibition; `CLAUDE.md` §"Dead ends" tells readers to read the
verdict word first. Writing the bare word after running one of the two tests **mislabels the shelf**.

## ⭐⭐⭐ AN EPISODE-SCOPED GAUGE MUST ASSERT WHICH EPISODE IT IS IN, NOT MERELY FIND ONE (slice 52 gate 0, 2026-08-31)

A probe measuring "the search" scoped every column to *the first search episode on the wire*: find
the first tick where `head_searching` is set, read the deficit and the head-off angle there, and
report the latched lock time. On a wire where the picture error was small it printed

    err_gain 60 | deficit@onset 104.3°  head_off@onset 178.3°  t_lock NEVER  ...  CPA 0.01 m

**Every number is correct and not one of them is about the search.** With a good enough handover the
missile locks the instant the receiver opens and never searches during the engagement at all — so
the only search episode on that wire is a POST-INTERCEPT one, against a target now 180° astern. A
reader would have read *"never acquired"* beside a **1 cm hit**.

⚠ **THIS IS NOT THE DEFAULTED-ZERO TRAP** (slice 49, and this same probe hit that one too — an arm
that never searched reported `min head_off` = 0.0000 and a verdict of COVERED, off a key that simply
stops being written). That trap is a MISSING value read as a real one. This is the opposite: a
present, correct value **from the wrong occurrence of the thing you are scoping to.** No default is
involved and no key is absent, so every guard written for the first trap passes.

⇒ **THE PROCEDURE:** a gauge scoped to "the episode" must classify the run before it reads a column,
and the classification must be a stated REGIME, printed on the row:

- *did the event this gauge exists to measure happen at all, or did the run skip it?* (here: the lock
  PRECEDED the first search — `k_lock < k_search` — so there was no search to measure);
- *is the episode I found the FIRST one, or a later recurrence?* (slice 48: acquisition is not a
  latch, so a search RESUMES after a lost track — the same probe's deficit column reached 170° on a
  late re-search and had to be re-scoped to search-onset → first-lock);
- and the row prints the regime word (`no search needed`), never a number in a column whose meaning
  depends on a regime the row does not name.

⭐ The tell that something is wrong is almost always **a headline gauge disagreeing with a crude
orientation number in the same row** — NEVER beside 0.01 m. Keep one such column (CPA here, printed
for orientation and banned as a gauge) precisely so the contradiction is visible on the row.

### ⚠⚠ THIRD OCCURRENCE, AND IT HAD ALREADY POISONED A PRINTED COLUMN (slice 52 gate 2, 2026-08-31)

The first two occurrences were about a ROW (a regime the row did not name). The third was about a
COLUMN inside a row that was otherwise correct. Gate 0's F3 contamination column — *the share of
searching ticks the head spends on its mechanical stop* — read **2.43 % at `S` = 25 and 18.97 % at
`S` = 30**, and was used to pick which cell to prove the trunnion invariance on. Flown again with
the window cut at the FIRST LOCK, both cells clamp on **exactly zero** ticks: every one of those
percentages is from the POST-LOCK re-search, an episode the metric beside it (`t_lock`) was never
read on. The gauge and its contamination column were scoped to different episodes **in the same
table**, and nothing in the table said so.

⇒ **A GUARD COLUMN INHERITS THE GAUGE'S WINDOW, OR IT GUARDS NOTHING.** Cut every column — the
contamination ones especially — at the same two ticks the headline is read between, and say in the
header which two they are. ⚠ The failure is silent in the safe direction: it reported contamination
that was not there, so the verdict (F3 passes) survived. The next one may not.

⭐ AND IT MOVED THE PROOF: with the window right, the stop binds before the lock on exactly ONE cell
of the whole ladder (`S` = 45 at a 45° stop, 102 ticks pinned at 45.000°), which is the only cell on
which "vary the clamp and watch `t_lock` not move" means anything.
