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
- **Anything the verdict computes inside `_draw` has no headless proof.** Extract it to a pure
  helper the UI test can call.

