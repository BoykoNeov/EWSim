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

---

# PART II — THE GATE-0 RESULTS (2026-08-18)

**VERDICT: THE LAW OF §0.2 IS DEAD AS WRITTEN. NO CODE SHIPS. THE SUITE IS UNCHANGED.**
Five probes, one temporary core patch (applied and reverted, tree clean). The V exists in
acquisition TIME and **does not exist in MISS**, and the reason is worth more than the law was.

## §I — P1: THE AUTHORED SEEKER OUTRANGES THE ENGAGEMENT (the first surprise)

The seeker was authored from a real class and written down before any flight: 200 W, 16 GHz,
10 ms coherent integration (B = 100 Hz), NF 4 dB, L 5 dB, eta 0.6, threshold 10 dB, against the
scenario's own `rcs_m2 = 1.0`.

| fov (half-angle) | G (dB) | implied aperture | **R_acq** | SNR at 6437 m |
|---|---|---|---|---|
| 3° | 28.37 | 0.183 m | **26 930 m** | 34.86 dB |
| 10° | 17.92 | 0.055 m | **8 079 m** | 13.95 dB |
| 20° | 11.89 | 0.027 m | **4 040 m** | 1.91 dB |

⭐ **P2 PASSES EXACTLY**: `R_acq · fov` is constant to **0.0000 %** across a 4× fov range and the
log-log slope is **−1.000000**. The aperture identity is what flies. `r_acq` was checked against
`snr_freespace` (SNR at `R_acq` = +10.0000 dB at fov 3/6/12) rather than hand-recomputed.

⚠⚠ **AND THE HEADLINE IS THE RATIO, NOT THE RANGE: `R_acq / R_launch` = 8079 / 6437 = 1.255 AT THE
SHIPPED WINDOW.** The missile is launched **INSIDE its own seeker's horizon**. On the shipped wire
the gate is not merely weak — at fov 10 / rcs 1.0 it is **exactly inert**: `t_lock` 0.0010 s and miss
0.2237 m, byte-identical to no gate at all. **That is the dead-knob falsifier of P1 firing at the
shipped configuration**, and everything after it is an investigation of how far the wire must be bent
before the gate does anything.

## §II — P0(a): THE COMPOSED V IS REAL — AND P7 CAUGHT THE ARM IT WAS BUILT ON

⭐ **One flight carries the whole curve.** Before any lock the seeker publishes no estimate and no
rate, so PN commands nothing and **the pre-lock trajectory is fov-independent** — so a single
never-locking arm yields `t_angle(fov)` from `head_off_deg(t)` and `t_range(fov)` from `los_range(t)`
for *every* fov at once (slice 43 §V.2's own method, reused).

⚠⚠ **P7 FIRED FIRST AND IT WAS THE RIGHT ORDER.** The first arm chosen (`err_az = +12` at the
shipped 30° stop) is **clamped at birth** — 18.1020 + 12 = 30.1020 > 30, so `head_clamp` moved it
−0.1091° and it sits **pinned on the stop 100 % of ticks**. That is precisely the configuration
`docs/DEFERRALS.md` records slice 43 as having **withdrawn** as stop contamination.
⭐ **The discriminator cleared the MECHANISM but not the arm**: at stops of 45° and 60° nothing pins
(0.00 %), and the dip that carries the left arm survives — **9.2547° at t = 6.507 s against 9.1767°
at t = 6.488 s** — so the dip is the WINDOW's geometry and not the stop's. The arm was re-flown at
`err = +10`, which does not clamp (birth head_az 28.1020, 0 % pinned), and every number below is
from that clean arm.

⚠ **A SECOND CATCH, ON MY OWN FALSIFIER.** The first pass reported *"best fov 12.0, INTERIOR"* at
rcs 1.0 — but 12.0, 12.2 and 12.4 all read `t_acq` = 0.001 s. **That is a plateau at the first tick,
which is the grid-edge failure wearing a different dress**, and the `edge` test could not see it. A
plateau/tie check was added and the rcs 1.0 column then fails honestly at every budget ≥ −3 dB.

With the plateau check in place the composed V is **genuine**: at `err = +10`, rcs 0.1 m², the
minimum is INTERIOR at every budget from −12 to +6 dB, the left arm binds on **ANGLE** and the right
on **RANGE** (P3's attribution measured, not inferred), and `fov*` moves **≈1° per 6 dB** — 8.2° at
−12 dB to 10.0° at +6 dB. **The existence and the attribution survive ±12 dB; only the location
moves.**

## ⚠⚠⚠ §III — P0(b): THE V DOES NOT TRANSFER TO MISS, AND THE ANOMALY IS FLAT

The composed `t_acq` is exact. Flown with the gate in the loop, **miss does not follow it**:

| arm | binding gate | `t_lock` | `r_lock` | **miss** |
|---|---|---|---|---|
| fov 8.0, no range gate | ANGLE | 5.442 s | 2510 m | **361.97 m — FAIL** |
| fov 20, rcs 0.1, 0 dB | RANGE | 5.777 s | 2271 m | **0.058 m — HIT** |

**The same lock time, the same lock range, opposite verdicts.** A second spent range-blocked and a
second spent angle-blocked are not the same second, so `t_acq` cannot be the currency and the V
composed in §II prices nothing.

## ⭐⭐⭐ §IV — P10: THE ISOLATION, AND THE MECHANISM IS ONE ALREADY SHIPPED

Holding the window wide enough that the angle gate never binds and sweeping `R_acq` **alone**:

| `R_acq` | `t_lock` | miss (fov 12) | **hold %** |
|---|---|---|---|
| none | 0.001 s | 0.2237 | 99.99 |
| 4000 m | 3.367 s | 0.3491 | 99.96 |
| 3000 m | 4.758 s | 0.3267 | 99.98 |
| **2000 m** | **6.158 s** | **0.2514** | 99.96 |
| 1500 m | 6.866 s | **85.84** | **31.20** |
| 1000 m | 7.586 s | 143.81 | 80.50 |
| 500 m | never | 305.11 | — |

> ⭐⭐ **A DELAYED ACQUISITION COSTS NOTHING.** Locking at **6.158 s of an 8.9 s flight, at 2000 m**,
> lands 0.2514 m — indistinguishable from locking at the first tick. There is no gradual price at
> all: the arm is flat from `R_acq` = infinity down to 2000 m.

⭐⭐ **AND WHEN IT FINALLY BREAKS, IT BREAKS AS A *HOLD* FAILURE, NOT AN *ACQUIRE* FAILURE.** The
`hold %` column is the whole story, and the control makes it unambiguous — the narrow-window arms of
§III never had an acquisition problem either:

| fov | `t_lock` | **hold %** | `t_lost` | miss |
|---|---|---|---|---|
| 8.0 | 5.442 | **1.24** | 5.482 | 361.97 |
| 8.6 | 4.147 | **0.71** | 4.179 | 438.89 |
| 8.8 | 3.698 | **0.63** | 3.729 | 402.17 |
| **9.0** | 3.216 | **99.98** | 8.859 | **0.19** |

**Those arms acquire and lose the track within ~0.03 s** — they hold for less than 1.3 % of the
remaining flight. ⇒ **the failure is slices 32/34/35's ALREADY-SHIPPED lesson** (the window and the
servo must cover the tracking error, and slice 43 measured the LOS rate rising **318×** across this
flight), not a new acquisition lesson. ⭐ Confirmed from the other side: at a FIXED `R_acq` = 1500 m
a **wider** window rescues the late lock outright — fov 12 → 85.84 m, fov 16 → **0.32 m**.

## ⭐⭐ §V — P11: THE BOUNDARY, AND IT IS 28 dB AWAY

With the aperture coupling ON, sweeping fov at each budget and taking the best miss available:

| budget | `R_acq(10°)` | **`R_acq`/`R_launch`** | best fov | **best miss** | hold % |
|---|---|---|---|---|---|
| **0 dB (as authored)** | 8079 m | **1.255** | 23.0° | **0.0015 m** | 99.96 |
| −12 dB | 4049 m | 0.629 | 19.5° | 0.0137 m | 99.93 |
| −24 dB | 2029 m | 0.315 | 9.5° | 0.0359 m | 99.93 |
| −26 dB | 1809 m | 0.281 | 8.5° | 0.1282 m | 99.97 |
| **−28 dB** | 1612 m | **0.250** | 12.0° | **7.80 m** | **55.04** |
| −36 dB | 1017 m | 0.158 | 8.0° | 28.85 m | 20.13 |

> ⚠⚠⚠ **THE DESIGNER CAN ALWAYS JUST WIDEN THE WINDOW AND STILL HIT, UNTIL THE LINK BUDGET SITS
> ~28 dB BELOW A PLAUSIBLE SEEKER** — a **0.0025 m²** target instead of 1.0 m², or 1/400 of the
> transmit power, or 1/400 of the integration time. And at that boundary the failure is *still* the
> hold failure (`hold %` 55.04), not a new one. ⚠ Restricting fov to the family's own 1–12° domain
> does not move the boundary (best fov is already 8.5–12° from −24 dB down).

## ⭐⭐⭐ §VI — WHAT THIS KILLS, WHAT SURVIVES, AND WHAT THE REAL PRECONDITION IS

> ⚠⚠⚠ **1. THE 42/43 BLOCKER SURVIVES THIS SLICE. `SEEKER RANGE / SNR ACQUISITION LIMITS` IS NOT
> THE UNBLOCKER `docs/DEFERRALS.md` NAMED IT AS.** It was supposed to make a wider window cost
> something. Measured: on this wire a wider window costs nothing at any plausible budget, and where
> it finally does, the cost is a hold failure already owned by slices 32/34/35.
>
> ⭐⭐ **2. THE REASON, AND IT IS THE TRANSFERABLE RULE: A DETECTION GATE CAN ONLY PRICE A DESIGN
> VARIABLE IF THE ENGAGEMENT IS LAUNCHED OUTSIDE THE SENSOR'S HORIZON.** Here `R_acq/R_launch` =
> **1.255** at the authored seeker — the missile begins the flight already able to see the target,
> so the gate has nothing to gate. **This is a property of the WIRE, not of the seeker**: slices
> 26–43's engagement is a 6.4 km, 8.9 s TERMINAL engagement, chosen for the radome loop.
>
> ⭐ **3. SO THE PRECONDITION IS RENAMED, AND IT IS NOT AN RF FEATURE.** What a search-pattern slice
> actually needs is **an engagement launched beyond the seeker's horizon — i.e. a midcourse phase.**
> ⚠ And that is a real slice, not a scenario edit: this wire's missile is unpowered with zero drag
> area, launched at 3000 m, so a 20 km engagement takes >= 28 s over which gravity alone drops it
> **3845 m** — into the ground. A midcourse-range wire needs propulsion or lofting first.
>
> ⭐ **4. WHAT SURVIVES AS MEASURED PHYSICS** (worth carrying even though nothing ships): the
> aperture identity holds exactly on the flying wire (`R_acq · fov` constant to 0.0000 %, slope
> −1.000000); every budget term enters `R_acq⁴` identically, so **a dB of RCS, a dB of power and a dB
> of integration time are the same act** (`r_acq(10°, rcs 0.1, 0 dB)` = `r_acq(10°, rcs 1.0, −10 dB)`
> = 4543.111 m, to the digit); and **a late lock with correct pointing is nearly free** while a late
> lock with wrong pointing is fatal.
>
> ⚠ **5. METHOD: THE COMPOSED CURVE WAS RIGHT AND THE CURRENCY WAS WRONG.** `t_acq` was measured
> correctly, the V was real in it, and it priced nothing — because the metric that decides the
> engagement is miss, and miss on this wire is bimodal (0.0015–0.36 m against 85–438 m, nothing
> between). ⭐ **Before composing a trade out of two times, check that the two seconds are
> interchangeable.** They were not: a second spent unable to SEE costs nothing, a second spent
> POINTED WRONG is unrecoverable.

---

# ⚠⚠⚠ §VII — P12: THE THREE PRE-REGISTERED CHECKS THAT HAD NOT RUN, AND **TWO OF THEM REFUTE §III/§IV**

§0.5 registered P7 (contamination columns on *every* table) and P6 (half `dt`). §IV and §V were
written before either ran on the tables the verdict rests on. Both ran. **The kill stands; two of
its sentences do not.**

## ⭐⭐ §VII.1 CHECK 1 — THE AUTHORITY COLUMN, AND THE "FREE" ARM IS FREE UP TO **EXACTLY 100 %**

| `R_acq` | `t_lock` | miss | hold % | **peak `a_cmd` after lock** | **% of `a_max`** | aero % |
|---|---|---|---|---|---|---|
| none | 0.001 s | 0.2237 | 99.99 | 573.0 | **19.10** | 0.00 |
| 4000 m | 3.367 s | 0.3491 | 99.96 | 436.2 | **14.54** | 0.00 |
| 3000 m | 4.758 s | 0.3267 | 99.98 | 1039.7 | **34.66** | 0.00 |
| **2000 m** | **6.158 s** | **0.2514** | 99.96 | **3000.0** | **100.00** | 0.09 |
| 1500 m | 6.866 s | 85.84 | **31.20** | 627.3 | 20.91 | 20.32 |

> ⚠ **§IV's SENTENCE — *"A DELAYED ACQUISITION COSTS NOTHING"* — IS TOO WIDE AND IS CORRECTED HERE.**
> It costs nothing **in miss** only while the airframe still has the authority to null what the delay
> accumulated, and **the last free cell spends exactly all of it**: `a_cmd` = 3000.0 against
> `a_max` = 3000.0, i.e. **100.00 %**, where the no-gate arm uses 19.10 %.
> ⭐ **So the flat arm is not slack — it is a budget being spent, and the flatness of MISS hides it.**
> The cost of a late lock is real and it is paid in **manoeuvre authority**, which the miss column
> cannot show until the authority runs out.
> ⚠ And past that the failure is *not* an authority failure: at `R_acq` = 1500 the peak demand falls
> back to 20.91 % precisely because the track is gone (hold 31.20 %) and there is nothing to command.
> ⭐ **Two different limits end the free interval within 500 m of each other, and reading only miss
> would have shown neither.** (Slice 41's kill inverted: there a clamp BOUND and hid a real effect;
> here a limit is spent to the last percent and the headline metric stays flat.)

## ⚠⚠⚠ §VII.2 CHECK 2 — **§III's ASYMMETRY IS THE *SERVO'S*, NOT THE WINDOW'S. §IV AND §VI.4 ARE REFUTED.**

| fov | `srate` 8 °/s (shipped) | `srate` 30 °/s | `srate` 60 °/s |
|---|---|---|---|
| 8.0 | **361.97 m**, hold 1.24 % | **0.2209 m**, hold 99.97 % | 0.2209 m, hold 99.97 % |
| 8.6 | **438.89 m**, hold 0.71 % | **0.1931 m**, hold 99.98 % | 0.1931 m, hold 99.98 % |
| 8.8 | **402.17 m**, hold 0.63 % | **0.1036 m**, hold 99.98 % | 0.1036 m, hold 99.98 % |
| 9.0 | 0.1872 m, hold 99.98 % | 0.1872 m (identical) | 0.1872 m (identical) |

**`t_lock` is IDENTICAL down the rows** (5.4420 / 4.1470 / 3.6980) — the servo changes nothing about
*acquiring*, only about *keeping*.

> ⚠⚠ **THE REFUTED SENTENCES, quoted so they are not re-imported:**
> * §III/§VI.4: *"a late lock with correct pointing is nearly free while a late lock with wrong
>   pointing is fatal"* — **WRONG.** The pointing is not what kills it.
> * §IV: *"the failure is slices 32/34/35's already-shipped lesson"* — **too broad, and the wrong
>   member of the list.** It is **slice 35's alone**: the head's slew rate.
>
> ⭐⭐ **THE CORRECT SENTENCE: A LOCK AT THE WINDOW'S EDGE HANDS THE SERVO A FULL-WINDOW SLEW, AND AT
> 8 °/s IT CANNOT CLOSE 8.6° BEFORE THE LOS RUNS AWAY.** Triple the slew rate and every one of those
> arms hits, from the same lock instant. **The window's size sets the SLEW the servo is handed; the
> servo decides whether that is survivable.** ⚠ 30 and 60 °/s are byte-identical to each other on
> every row, so this is a THRESHOLD in slew rate somewhere in (8, 30] and not a proportional effect —
> not bracketed here, and it must not be quoted as one.
> ⚠ **This does NOT rescue the slice.** It relocates the narrow-window failure onto an axis slice 35
> already shipped and priced, which makes the acquisition framing *less* load-bearing, not more.

## ⭐ §VII.3 CHECK 3 — HALF `dt` (P6): THE BOUNDARY HOLDS, THE FAILURE MAGNITUDES DO NOT

| cell | `dt` 2e−3 | `dt` 1e−3 | `dt` 5e−4 |
|---|---|---|---|
| `R_acq` 2000 (free) | 0.4196 | 0.2514 | 0.1129 — **hit at all three** |
| `R_acq` 1500 (breaks) | **84.86**, hold 31.43 | **85.84**, hold 31.20 | **86.80**, hold 31.39 |
| fov 8.6 (servo) | 319.81 | 438.89 | 626.54 — **fail at all three** |

> ⭐ **THE HEADLINE SURVIVES.** The free/broken boundary between `R_acq` 2000 and 1500 — which the
> −28 dB figure of §V hangs off — is **step-independent**: the broken cell reproduces to 2 % and its
> `hold %` to 0.2 points across a 4× range of `dt`. This is not slice 42's one-integration-step band.
> ⚠ **But the FAILURE MAGNITUDES are strongly step-dependent** (320 → 627 m on the servo arm, a 2×
> walk in the direction of finer steps). ⇒ **quote the VERDICT, never the metres, on any arm that has
> lost the track** — once the track is gone the trajectory is diverging and the miss is sampling a
> divergence, not measuring one.

## ⭐ §VII.4 AN INHERITED CLAIM CONTRADICTED IN PASSING — FLAGGED, NOT BURIED

`docs/DEFERRALS.md` records slice 43's verdict on this wire as **BIMODAL**: *"largest rescue 0.3398 m,
smallest failure 305.1118 m, nothing between."* §V's −28 dB row lands at **7.7996 m with hold 55.04 %**
and §IV's `R_acq` 1500 row at **85.84 m with hold 31.20 %** — both inside that supposedly empty gap.

> ⚠ **THERE IS A PARTIAL-RESCUE MODE AND SLICE 43 DID NOT SEE IT** because nothing in its grid could
> produce one: its arms either held the track or never acquired. **A track that is acquired, held for
> part of the endgame and then lost lands in between**, and any later slice that assumes the gap is
> empty will trip over it. Not pursued here; recorded so it is not re-discovered as a surprise.

## §VII.5 THE VERDICT AFTER P12 — UNCHANGED, AND ITS REASONS ARE NARROWER

**The kill stands and is not weakened by any of the three checks:** the range gate is still inert at
the shipped configuration, still free across 28 dB, and the free interval still ends for reasons
(authority exhaustion, then a servo-rate hold failure) that belong to slices already shipped.
⭐ **What P12 changes is the ACCOUNT, and in the direction the method predicts:** every one of the
three corrections narrowed a sentence that had been written wider than its measurement — the same
failure mode slice 43's gate 0 recorded three times and this gate's §VI.5 took credit for avoiding.
⭐⭐ **It did not avoid it; the pre-registered columns caught it.** That is the argument for the
columns, not for the author.
