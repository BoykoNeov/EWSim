# Slice 39 — **A NULLING-LOOP HEAD SERVO: KILLED AT GATE 0** (§11 Tier-A)

**Status: DEAD, NOT DEFERRED — killed in 9 probes across 4 files (2026-08-17), with a general result worth more than
the slice would have been.** No core change survives: the gate-0 patch was applied for the runs and
**REVERTED** (`git diff` empty, suite green at **7564**, the slice-38 count unchanged). Raw numbers in
`M:\claud_projects\temp\slice39g\` (`lib39g.jl`, `p0_degen.jl`, `p1_table.jl`, `p2_collapse.jl`,
`p3_twin.jl`).

The candidate was slice 38's own FIRST named successor:

> *"**A NULLING-LOOP HEAD SERVO** (§0.1), AND IT IS A FALSIFIABLE PREDICTION RATHER THAN A DESCRIPTION.
> … A nulling loop drives `ω̃_head → 0` and has steady state `−b/(1+s)` ⇒ **THE TWO CURRENCIES SHOULD
> SWAP**: the bias becomes the term that carries the slice and the scale factor should go nearly
> INERT. That is a prediction this arc can be wrong about, which is what makes it worth flying."*
> — `docs/plans/slice38.md`, Named deferrals

It was worth flying. It is wrong, and it is wrong in a more interesting way than "the currencies do
not swap".

---

## The one-paragraph statement of what was measured

> ⭐⭐ **THE RESULT, IN ONE SENTENCE.** A nulling loop with infinite loop gain **is not an
> architecture — it is a reparameterization of the servo time constant.** Every nulling arm, at every
> gyro error in the domain, is a SHIPPED slice-37/38 arm with `gimbal_tau_s` and the bias re-typed:
> `nulling(τ, s, b) ≡ feed-forward(τ·(1+s), 0, b/(1+s))`, measured at **5.8e−09 m** of trajectory over
> 12 000 ticks. **What would make it an architecture is FINITE LOOP GAIN**, which this model does not
> have — and that, not the nulling loop, is the live successor.

⇒ the false-fidelity class (slice 15's `k_δ`, 19's dead `speed`, 31's `(R̂, s)`), caught **before any
kernel, key, rung, scenario or client code existed** — the earliest this project has ever caught one,
and the fourth consecutive slice whose gate 0 refuted its own opening prediction.

---

## §0.1 THE MODEL, AND WHY THE FORK LOOKED REAL

Slice 38 ships **FEED-FORWARD** stabilization: the head holds its pointing by feeding forward the
negated gyro reading `ω̃ = (1+s)·ω + b`, so what is left in the pointing is

```
        ω − ω̃  =  −s·ω − b          ⇒  a fraction of the missile's OWN BODY MOTION, back into the index.
```

That `ω_body` term is the whole of slice 38: it is why a scale factor is a **stability** spec there,
and why slice 37's onset bracket walks eight cells from a perfect gyro to a dead one.

A **NULLING** loop closes on the gyro instead: it drives the *measured* head rate to zero, so its
achieved inertial rate is the commanded rate divided by the gyro's gain, with the bias subtracted:

```
        ω_h  =  (ω_c − b)/(1+s)      ⇒  NO `ω_body` term at any `s`.
```

**The fork is real on paper** — one architecture's error is proportional to body rate, the other's is a
constant — and the prediction followed: slice 38's walk should collapse to a point.

⚠ **THE PROBE PATCH'S ONE FREE DECISION, STATED BECAUSE §0.5 IS ENTIRELY ITS CONSEQUENCE:** the servo
COMMANDS from the tracking error exactly as slice 34's does, the command is taken **uncapped**, the
division by `(1+s)` is applied, and the **mechanical rate limit binds the ACHIEVED motion**. The
alternative (cap the command, then divide) differs only where the servo saturates.

---

## §0.2 P0 — THE DEGENERATE, WHICH IS WHAT MADE THE RUNG CREDIBLE

With a perfect gyro `(ω_c − b)/(1+s)` **is** `ω_c`, so the two architectures must be the same servo.
They are:

| arm | rms_r | rms_q | off_med° | miss |
|---|---|---|---|---|
| space rung (feed-forward, `s = 0`) | 1.00097 | 0.04236 | 2.24453 | 0.340 |
| space rung (**NULLING**, `s = 0`) | 1.00097 | 0.04236 | 2.24453 | 0.340 |

`|Δ rms_r| = 9.2e−13`, **max|Δpos| = 1.03e−09 m** over 12 000 ticks. Bit-identity is not expected and
would be a coincidence — the shipped kernel forms `az = head + Δaz` internally while the patch re-forms
`wrap_angle(a1 − head)` and adds it back, so the residual is IEEE rounding.

⚠ **P0b — THE OTHER RUNG IS UNTOUCHED:** `:probe_null_*` live on a BODY-referenced wire moves the
missile by **EXACTLY 0.0 m** (inert by placement, not by a guard — slice 38's own tooth in a new key).

**P0c already showed the mechanism parting**, which is why the gate continued:

| arm | rms_r |
|---|---|
| feed-forward `s = −0.20` | 0.29353 |
| **NULLING** `s = −0.20` | **0.94132** |
| feed-forward `s = −1.00` (dead) | 0.01134 |
| **NULLING** `s = −1.00` (dead) | **0.25281** |
| slice 37's body-referenced rung | 0.01172 |

A dead gyro drops the feed-forward head onto slice 37's other rung (0.01134 against 0.01172 — slice
38's shipped finding, reproduced); the nulling head does not follow it.

---

## §0.3 P1 — THE KILL-SHOT TABLE: THE WALK IS **NOT** FLAT, AND THAT IS THE FIRST HALF OF THE KILL

The onset re-found at each `s`, on slice 37/38's own 0.005 grid, under their **threshold-free
largest-single-step rule**. ⚠ The grid is **one cell wider at each end** than slice 38's — its own
gate-0 lesson, in its own words: *a bracket pinned against the edge of its own grid is not measured,
it is truncated.*

| arm | onset bracket | cells given back |
|---|---|---|
| feed-fwd `s = 0.00` | (−0.210, −0.205] | 0 — **slice 38's shipped bracket EXACTLY** |
| feed-fwd `s = −0.05` | (−0.200, −0.195] | 2 — **slice 38's, EXACTLY** |
| feed-fwd `s = −0.20` | (−0.185, −0.180] | 5 — **slice 38's, EXACTLY** |
| feed-fwd `s = −1.00` | (−0.170, −0.165] | 8 — **slice 38's, and slice 37's BODY rung** |
| **NULLING `s = 0.00`** | (−0.210, −0.205] | 0 |
| **NULLING `s = −0.05`** | (−0.210, −0.205] | **0 — unchanged at a real part** |
| **NULLING `s = −0.20`** | (−0.205, −0.200] | 1 |
| **NULLING `s = −0.40`** | (−0.195, −0.190] | 3 |
| **NULLING `s = −1.00`** | (−0.185, −0.180] | 5 |

⭐ **THE FEED-FORWARD ROWS REPRODUCE SLICE 38's FOUR SHIPPED BRACKETS EXACTLY**, which is what
entitles this harness to speak about the nulling ones at all (slice 38's own `s = 0` discipline).

**Read naively this is the slice:** at −5 %, an ordinary cheap-MEMS part, feed-forward gives back two
cells of margin and nulling gives back **none**. But the nulling column is *not* flat further out, and
where it walks it walks for a reason that has nothing to do with a gyro.

---

## §0.4 ⚠⚠ P2 — THE COLLAPSE. THE RESIDUAL WALK **IS** THE SERVO TIME CONSTANT

Under nulling `ω_h ≈ (tgt − head)/(τ(1+s)) − b/(1+s)`, so `s` is a candidate relabelling of the
SHIPPED, AUTHORED `gimbal_tau_s`. Tested **end to end** — a nulling arm against a pure shipped-path
arm with no patch in it at all:

| NULLING arm | the SHIPPED twin | rms_r | max\|Δpos\| |
|---|---|---|---|
| `s = −0.05`, τ = 0.0500 | `s = 0`, τ = 0.0475 | 0.99758 both | **5.82e−09 m** |
| `s = −0.20`, τ = 0.0500 | `s = 0`, τ = 0.0400 | 0.94132 both | **2.45e−09 m** |
| `s = −0.40`, τ = 0.0500 | `s = 0`, τ = 0.0300 | 0.79306 both | **7.18e−09 m** |
| `s = +0.20`, τ = 0.0500 | `s = 0`, τ = 0.0600 | 1.02562 both | **4.91e−09 m** |

`|Δ rms_r|` spans 5.1e−13 … 2.0e−12, and the **miss agrees to four decimals on every cell**. ⚠ The
`s > 0` row is included deliberately: a collapse that held only on one side would be a coincidence of
sign, not an identity.

**AND THE BIAS COLLAPSES TOO — P3, the hole the advisor caught in P2b's first draft.** P2b labelled
`feed-forward(τ, b/(1+s))` the twin and it was not: under nulling **both** parameters move, so the
true twin of `NULLING(τ = 0.05, s = −0.20, b_z = 0.05)` is `feed-forward(τ = 0.0400, b_z = 0.0625)`.
Re-flown — **on the clean tree, no patch, a pure shipped slice-38 arm** —

| arm | rms_r | off_med° | miss |
|---|---|---|---|
| NULLING τ = 0.05, `s = −0.20`, `b_z = 0.05` | 0.97634 | 2.12049 | 1.2097 |
| **feed-forward τ = 0.0400, `b_z = 0.0625`** | **0.97634** | **2.12049** | **1.2097** |

⇒ **NEITHER CURRENCY EXISTS ON THIS RUNG.** Slice 38 predicted the two would swap; the measurement is
that both are reachable by re-typing two authored numbers a slice-38 wire already carries.

> **THE COMPOSITION, WHICH IS THE WHOLE KILL:**
> `nulling(τ, s, b)` ≡ `nulling(τ(1+s), 0, b/(1+s))` [P1b] ≡ `feed-forward(τ(1+s), 0, b/(1+s))` [P0a].
> A button offering this architecture would be flying a relabelled `gimbal_tau_s`, and the HUD would
> name a servo topology the physics cannot tell apart from the one already shipped.

---

## §0.5 ⚠⚠ THE ONE REGIME THAT DOES **NOT** COLLAPSE — AND IT IS NOT EARNED

The composition needs `(1+s)` bounded away from zero. As `|1+s| → 0` the demanded rate diverges and
the **mechanical limit**, not the servo law, decides what happens:

| NULLING `s` | rms_r | rate-limit saturation, in band | head_max° | miss |
|---|---|---|---|---|
| −0.60 | 0.54541 | 0.00 % | 18.117 | 0.440 |
| −0.90 | 0.04837 | 0.00 % | 18.117 | 1.374 |
| −0.95 | 0.01338 | 0.00 % | 18.117 | 1.473 |
| −1.00 | 0.25281 | **100.00 %** | 18.310 | 1.192 |
| −1.20 | 0.11074 | 0.02 % | **30.000 (the STOP)** | **1199.802** |

⚠⚠ **THIS COLUMN IS ENTIRELY THE CONSEQUENCE OF §0.1's FREE DECISION** (cap the ACHIEVED motion, not
the command) and it is **NOT A RESULT**. It is the corner a gate 1 would have had to model properly —
with an explicit loop gain, a torque limit and a stability analysis of the loop itself — and no claim
in this file rests on it. The honest statement is: **the composition holds wherever the servo is
unsaturated, and the saturated corner was not earned.**

⚠ Note also that −0.90/−0.95 are QUIET for a reason that is now obvious and was not: `τ_eff = τ(1+s)`
is 0.005 / 0.0025, a 10–20× faster servo. Reading those cells as *"a bad gyro stabilizes the missile"*
would have been the writeup's worst available sentence.

---

## §0.6 WHAT SLICE 38's PREDICTION GOT RIGHT

Precisely one thing, and it is worth recording because the arc will meet it again: **the scale factor
does stop acting on the rejection path.** At a real part (−5 %) the nulling head gives back **zero**
cells of margin where the shipped feed-forward head gives back two. The error is in what happens
*instead* — the prediction was that the bias would take over, and the measurement is that the scale
factor simply becomes the servo bandwidth, where a 5 % part buys a 5 % detune of a number the designer
authored anyway.

⇒ the design sentence that survives, and it is a real one:
**on a feed-forward head the gyro's scale factor is a STABILITY spec; on a nulling head it is a
BANDWIDTH spec — and a bandwidth spec is one you already own.**

---

## §0.7 THE LIVE SUCCESSOR — **FINITE LOOP GAIN**, AND WHAT MUST BE PROBED BEFORE IT GETS A PLAN

This model's nulling loop has **infinite loop gain**: it rejects body motion perfectly at every
frequency, which is exactly why it collapsed onto a first-order lag. A real stabilization loop has a
finite gain and its own bandwidth, so its rejection is **frequency-dependent** — near-perfect at DC and
falling off above the loop bandwidth. ⭐ That is adjacent to slice 37's result in the sharpest possible
way: slice 26's limit cycle lives at **1.7–2.1 Hz**, and a finite-gain loop's rejection is falling
*exactly there*.

⚠⚠ **IT IS A DIFFERENT SLICE, NOT A REPAIR OF THIS ONE, AND TWO THINGS MUST BE PROBED FIRST:**

1. **Does a finite-K loop's rejection curve actually differ from a first-order lag's at the ring
   frequency?** — or does it collapse onto slice 37's shipped τ bench the way this one collapsed onto
   τ itself? **This is the identical trap in a new letter**, and the same bench answers it: frozen
   geometry, gain and phase at 1.7 Hz (slice 37's gate-0 bench, `p0_bench.jl`, reusable as-is).
2. **Are `K` and `τ` separable at all?** If they are not, the slice is slice 37's τ axis again — which
   slice 37 already named as a deferral in its own right, and which would then be the honest thing to
   ship instead.

⚠ **DO NOT OPEN THAT PLAN ON THIS SESSION's MOMENTUM** (advisor). It goes back to the user as a
candidate alongside the other standing ones, not as an assumed continuation.

---

## Provenance / how to re-run

The probes need the gate-0 patch **re-applied** (two sites in `missile.jl`'s `elseif _stab` branch: a
bias-only drift at `−b/(1+s)` at slice 38's drift site, and a command/(1+s) slew with the cap taken
after the division). **P3 is the exception and needs no patch at all** — it is a pure shipped arm, and
that is what makes it the strongest single row in the file.

```
& tools/julia.ps1 --project=core M:/claud_projects/temp/slice39g/p0_degen.jl
& tools/julia.ps1 --project=core M:/claud_projects/temp/slice39g/p1_table.jl
& tools/julia.ps1 --project=core M:/claud_projects/temp/slice39g/p2_collapse.jl
& tools/julia.ps1 --project=core M:/claud_projects/temp/slice39g/p3_twin.jl      # clean tree
```

⚠ `tools/test.ps1` must read **7564** afterwards, and `git diff --stat core/src/missile.jl` must be
empty — a probe patch that touches two sites in the seam is exactly the shape that leaves a stray edit
behind (checked: both hold as of this file).
