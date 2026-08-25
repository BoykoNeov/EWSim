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

## The windowed shot is not a formality: it caught two defects with three suites green (slice 47)

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

## Retract a rule you inherited if the wire refuses it â€” and say what replaced it (slice 47)

âš âš  **A ban carried forward from a probe the plan itself flagged as CONFOUNDED did not survive contact
with the shipped wire.** Â§3.2 forbade an angle-margin gauge because an early sweep showed it
*improving* while the engagement was lost. Measured on the finished wire it does the opposite in
both samplings a HUD author would use. â­â­ **And the reason it does not invert was worth more than
the ban was: `margin + cue = fov` at the handover instant** â€” the two "rival" gauges are one
measurement counted from opposite ends, asserted to a tenth of a degree on four arms.

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

