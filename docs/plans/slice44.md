# Slice 44 — **CAN THE SEEKER ACTUALLY SEE IT: THE WINDOW'S PRICE IS A DEADLINE** (§11 Tier-A)

**STATUS: GATE 0, PRE-PROBE. Written before any number for this slice exists.**
Everything below §0.3 is a *prediction, a domain, or a falsifier* — never a measurement. Where a
probe refutes a prediction the refutation is marked AT the prediction and recorded in the results
section; the prediction is never quietly edited to match (slices 41/42/43's discipline, and the only
reason all three kills were cheap).

⚠ **THE TITLE IS PROVISIONAL AND IS NAMED FROM A PREDICTION.** If P0 refutes the V (§0.5) the slice
is renamed or killed. Do not quote the title as a finding.

---

## ⚠⚠ §0.0 THE ADMISSION TICKET — WHY THIS IS NOT SLICE 42/43 RE-RUN

Slices 42 and 43 both ended blocked on **one sentence**, written in `docs/DEFERRALS.md` and sharpened
by slice 43's own finding 1:

> *A wider window is FREE in this model, so a search-pattern slice cannot be motivated — widening the
> glass by 2° and travelling 2° further are THE SAME ACT, and only one of them costs time.*

**This slice attacks that sentence directly and it is the named carrier for it** (`SEEKER RANGE / SNR
ACQUISITION LIMITS`, the precondition both slices deferred to). Two things make it different in kind
from 39/41/42/43, and they are the two traps that killed those four:

1. ⭐ **IT ADDS A CURRENCY, NOT A POLE.** Slice 41's kill rule — *a pole differs from a gain only in
   that its phase varies with frequency, and this loop's command is a single 1.6488 Hz line* — bites
   any new **dynamic element** on this family. A detection threshold is not a dynamic element: it is
   a second **gate**, on a state variable (range) the angle gate does not touch. The spectrum probe
   (`p2_spectrum.jl`) is not the relevant pre-check here and running it would be cargo cult.
2. ⭐ **IT PRICES THE ALTERNATIVE, WHICH IS EXACTLY WHAT SLICE 43 SAID IT COULD NOT DO** (§0.1 of
   `docs/plans/slice43.md`: *"the servo ceiling prices the SEARCH; it does not price the
   ALTERNATIVE"*). The alternative to searching is widening. This makes widening cost something.

## ⚠⚠⚠ §0.1 WHAT THIS DOES **NOT** CLAIM — stated first, in the negative

> **1. THE PRICE IS NOT A RANGE. IT IS A DEADLINE.**
> A missile closes range monotonically to CPA, so on free-space geometry a brightness gate can
> **never permanently deny** acquisition — the SNR only rises. It **delays**. Any sentence of the
> form *"a wide window cannot see the target"* is FALSE on this wire and must not be written. The
> honest form is *"a wide window cannot see it YET"*.
>
> **2. "DOUBLING THE WINDOW HALVES THE ACQUISITION RANGE" IS THE MECHANISM, NOT THE LESSON.** It is
> an aperture identity (§0.3) and it is one line of algebra. On its own it does not clear the 42/43
> blocker, because a designer reading it can still just accept the shorter range. What clears the
> blocker is §0.2's V — and the V is what P0 must MEASURE, not assume.
>
> **3. NO PROBABILITY OF DETECTION IN THIS SLICE.** The first rung is a deterministic
> `snr ≥ snr_min`. A `detect_once` draw inside the seeker is a **draw-topology flip** (convention 3)
> and would desync replay on every slice 11/13/25–43 wire. It is a named deferral (§0.8), never a
> rung here, and no gate-3 text may imply otherwise.
>
> **4. THE GATE IS ONE-WAY ON THIS GEOMETRY AND THAT WILL BE STATED, NOT HIDDEN.** SNR rises
> monotonically, so `snr_ok` flips false→true once and never back. The seeker's existing COAST branch
> is therefore **not reachable through this gate** on a closing free-space engagement. What would make
> it two-sided is a `two_ray` null or a receding target — both named (§0.8), neither built. This arc
> has already been caught once shipping a live-looking branch with no proof; the branch is not being
> shipped, the sentence is.

## ⭐ §0.2 THE CANDIDATE LAW — **THE V, AND EACH ARM OWNS A DIFFERENT GATE**

Acquisition needs **two** conditions, and they move in **opposite directions** in the one authored
number `fov`:

> * **`t_angle(fov)`** — the first moment the target is inside the angular window. **DECREASING in
>   fov**, and slice 43 already measured its exchange rate exactly: the cost of acquiring is the
>   overlap deficit `|err| − fov`, so a degree of window buys a degree of deficit one-for-one.
> * **`t_range(fov)`** — the first moment the target is bright enough, i.e. when the closing range
>   falls below `R_acq`. **INCREASING in fov**, because the same aperture that sets the window sets
>   the gain (§0.3): `R_acq ∝ 1/fov`.
> * ⭐⭐ **`t_acq(fov) = max(t_angle, t_range)` ⇒ V-SHAPED, WITH AN INTERIOR OPTIMUM `fov*`.**

⭐⭐⭐ **AND THIS IS WHAT DISSOLVES THE 42/43 BLOCKER, IN SLICE 43's OWN WORDS.** Slice 43 finding 1
said widening the glass and travelling further are the same act. **Under the coupling they are not:
widening moves the DEADLINE, and searching does not.** Slice 43 finding 6 supplies the teeth —
the required-sweep-rate curve is U-shaped with a best moment at t\* ≈ 4.0 s of a ~7 s engagement, so
**a window wide enough that its brightness gate opens at t = 5 s has bought coverage it cannot use.**

⚠ **THE OPTIMUM IS ONLY A BUDGET IF EACH ARM IS SEPARATELY ATTRIBUTED.** `CLAUDE.md` disqualifies
knobs by non-monotonicity (`k`, `ω_n`, `σ_seek`) — but what those failed was that **the LESSON
reversed**, not that a curve had an interior minimum (slice 33 shipped an FOV budget). The
discriminator, pre-registered: **the left arm must be measured to bind on ANGLE and the right arm on
RANGE, each by its own instrument, never inferred from the V's shape.** If both arms cannot be
attributed, this is not a budget and it does not ship.

## §0.3 THE PHYSICS, AND WHERE IT LIVES

One aperture serves transmit and receive, so the window and the reach are the **same** hardware:

```
G = eta * 4pi / Omega  ~=  eta * 4pi / (theta_az * theta_el)   (pencil beam, theta in radians)
SNR ∝ G^2                                       (monostatic, two-way — rf.jl's radar equation)
=> SNR ∝ theta^-4   =>   R_acq ∝ SNR^(1/4)|_{SNR = snr_min} ∝ 1/theta
```

* The kernel is **`gain_from_beamwidth`** and it belongs in **`rf.jl`**, beside `wavelength` /
  `snr_freespace` — measurement-agnostic, cross-domain, dependency-free (convention 12). The ground
  radar could consume it; this slice does not make it.
* **`snr_freespace(::RadarParams, rcs, range)` ALREADY EXISTS AND IS REUSED VERBATIM.** No second
  radar equation is written. (Convention 2's byte-identity surface is untouched: the ground-radar
  path calls the same function with the same arguments it always did.)
* **`rcs_m2` ALREADY EXISTS ON TARGETS** and is a live consumed key (`radar.jl:289`, `batch.jl`'s
  coverage grid), not a load-time-only key. A seeker consumer is **additive**.

## §0.4 THE SEAM — three lines, and each one is a discipline

`_observe_point3d!` currently gates acquisition on **one** conjunct (`missile.jl` ~2301–2307):

```
in_fov = off_head <= fov_h        (gimballed)  /  seeker_in_fov(...)  (body-fixed)  /  true
```

The change is `in_fov && snr_ok`, and:

1. **`snr_ok = true` unless a `seeker_rf:` block exists.** ABSENT-KEY GATED, never `= 0.0` — slice
   35's blocking pin. ⇒ all 7693 tests bit-identical, the master check (convention 2).
2. **No new `randn`.** The gate is a comparison, not a draw (convention 3).
3. **The telemetry goes out from phase 3 `observe!`**, with the seeker readout, not from phase 1
   (convention 8's `empty!(w.env)` gotcha).

## ⭐⭐ §0.5 THE PROBES, PRE-REGISTERED WITH THEIR FALSIFIERS

Harness: `M:\claud_projects\temp\slice44\`, extending slice 43's `lib43.jl` / `lib42.jl` `w37` wire —
slice 36's shipped handover, static target, seed 32, window 10°, servo 8 °/s, stop 30°. Launch range
is ~6437 m and the engagement is ~7 s, so **the whole question is whether `R_acq` lands inside that
band, and P1 REPORTS where it lands rather than authoring it there.**

| # | probe | what it decides | ⚠ PRE-REGISTERED FALSIFIER |
|---|---|---|---|
| **P0** | ⭐⭐⭐ **`t_acq` vs `fov`, coupling ON, on slice 43's own no-search arm** (err −12 / fov 10, where the angle gate is already violated at birth and `Δaz₀(t)` / `Δel(t)` telemetry already exists) | **THE SLICE.** V or no V. | **`t_acq` FLAT in `fov` (< 2 % across a 4× sweep), or its minimum AT A GRID EDGE ⇒ the slice is decoration and dies here.** |
| **P1** | the link budget as authored: `R_acq` for a real seeker class, reported across the fov sweep | does the gate BIND at all | **`R_acq` > launch range at every fov ⇒ the target is always bright enough ⇒ DEAD KNOB (slice 19's `speed`, 31's `(R̂,s)`, 36's bias key). `R_acq` < CPA at every fov ⇒ nothing ever acquires ⇒ equally dead.** |
| **P2** | the exponent: fit `R_acq · fov` across a **4× fov range** | is the aperture identity actually what flies | **`R_acq ∝ 1/fov` violated by > 2 % ⇒ the seam is not consuming the coupling I think it is (an instrument bug, the class that cost slices 42/43 three probes).** |
| **P3** | ⭐ **ARM ATTRIBUTION**: on each side of `fov*`, which conjunct was false at `t_acq − dt` | budget vs coincidence | **Both arms attributed to the SAME gate ⇒ NOT a budget ⇒ does not ship (§0.2).** |
| **P4** | ⚠ **THE REPARAMETERIZATION GATE** (§0.6) | is the aperture story architecture or narrative | see §0.6 — **both outcomes are pre-registered and only one of them is a kill.** |
| **P5** | the NULL cell, always flown: coupling off, `snr_min` = −inf | the step is read against the null first | **Any headline number byte-identical to the null ⇒ the effect is the null relabelled (slice 42 gate 1's exact death).** |
| **P6** | ⚠ **HALF `dt`** on the headline cells (2e−3 / 1e−3 / 5e−4) | is the finding one integration step wide | **`t_acq` moving with `dt` ⇒ `docs/LESSONS.md`'s rule fires and the finding is the integrator's, not the seeker's.** |
| **P7** | contamination columns IN BAND on every arm — `stop%`, `sat%`, `aero%` (slice 41's price) | is a clamp doing the talking | **Read FIRST on every table. A rate/stop/α clamp binding through the band voids the cell.** |

## ⚠⚠ §0.6 THE REPARAMETERIZATION GATE — and it is NOT automatically a kill

The dangerous version is **not** "one knob with two consequences" (that is a budget — angle and range
are different state variables and the trajectory decides which binds). The dangerous version is:

> **Hold `fov` FIXED and sweep `snr_min` alone**, which moves `R_acq` without touching the window. If
> the miss-vs-`R_acq` curve at fixed `fov` reproduces the miss-vs-`fov` curve under the coupling **by
> a change of variables**, then the aperture story is narrative and `R_acq` is just a knob.

**BOTH OUTCOMES ARE WRITTEN DOWN NOW so that a hit does not get read as a slice kill:**

* **Coupling is DECORATION** ⇒ the range/SNR gate **still ships** — it is new physics and it still
  prices the window in time. `G = f(fov)` becomes an **authored relation**, not an architecture, and
  the slice says so in those words.
* **Slice is DEAD** ⇒ only if **P0** shows `t_acq` flat in `fov`, or **P1** shows the gate never
  binds. Nothing else in this file is load-bearing enough to kill it.

## ⚠⚠⚠ §0.7 THE BIGGEST RISK IS THE ONE I AM ABOUT TO AUTHOR

`R_acq ∝ (Pt · G² · λ² · σ / B)^(1/4)`, so **12 dB of authoring error moves the acquisition range
2×**. The back-of-envelope reached a plausible in-band number only by pushing the integration
bandwidth hard. **Authoring the parameters until the crossover lands where the lesson appears IS
authoring the lesson**, and it would be the fifth plausible sentence this arc has produced.

**THE GUARD, in three parts:**
1. **Pick aperture / power / integration from a REAL seeker class and write the numbers down BEFORE
   flying** (a Ku-band active seeker, ~0.15 m aperture, ~10² W class, coherent integration) — then
   **REPORT** where `R_acq` lands. If it lands out of band, that is P1 firing, not a reason to retune.
2. **EVERY FALSIFIER ABOVE IS ABOUT SHAPE, NOT dB** — the exponent, the interior minimum, the arm
   attribution. None of them moves if the constant is off by 6 dB.
3. **Quote the sensitivity** the way slice 37 quoted its ~40–45 %: state what the headline does under
   a ±6 dB perturbation of the authored budget, and if the verdict moves, the verdict is authored.

## §0.8 DEFERRALS NAMED IN ADVANCE (so they are not smuggled in as rungs)

* **A SEMI-ACTIVE SEEKER CHANGES THE EXPONENT** — the illuminator supplies `R_t²` and the seeker's
  own aperture enters ONCE, so `R_acq ∝ fov^(−1/2)`. A second data point on the same coupling and a
  clean fidelity rung. Named, not built.
* **PROBABILITY OF DETECTION / a Pd draw in the seeker** — the slice-13 `:scan` 4b draw-topology
  shape is the only legal way in (§0.1 item 3).
* **A TWO-SIDED GATE** — `two_ray` nulls or a receding target would make `snr_ok` flip back and give
  the coast branch a second cause (§0.1 item 4).
* **THE SEARCH-PATTERN SLICE ITSELF** — if P0's V holds, slice 43's law finally has a priced
  alternative and `docs/DEFERRALS.md`'s blocker is lifted. ⚠ That is a CONSEQUENCE to record, not a
  thing to build inside this slice.
* **A SCANNING SEEKER** (narrow beam swept over a wider FOV) — the OTHER coupling: coverage costs
  DWELL, not gain. ⚠ It is the search-pattern slice wearing an RF hat; keeping it out of gate 0 is
  what keeps this slice's V attributable to two gates instead of three.
