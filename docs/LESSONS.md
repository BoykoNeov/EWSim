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

