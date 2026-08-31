# Slice 51 — **WHAT IS A SECOND LOCK WORTH?** (slice 50's ⭐ candidate, "RE-ACQUISITION AS A LESSON IN ITS OWN RIGHT")

**STATUS: GATE 0 — KILLED AS A SLICE, 2026-08-31. THE MECHANISM IS REAL AND IS BANKED; THE PRICE
CANNOT BE MEASURED ON THIS ARC.** Nine probes, `M:\claud_projects\temp\slice51\`. No core change was
made and none is proposed.

The candidate, in `docs/DEFERRALS.md` §"New candidates raised by slice 50":

> **⭐ RE-ACQUISITION AS A LESSON IN ITS OWN RIGHT.** Both live arms **get the lock back** (the
> target's turn carries it past nose-on and the echo recovers), and slice 50 asserts that it happens
> but does NOT price it. What the second lock is worth — how much of the owed heading can still be
> paid, against `t_go` at the moment it returns — is a gauge nobody has measured. ⚠ Beware slice 48's
> finding that **acquisition is not a latch**: a lock re-gained too late is consumed and buys
> nothing, so this candidate must price the RECOVERY, not merely count it.

**It is answered, and the answer is that it cannot be priced.** Two of the three findings below are
worth more than the slice would have been.

---

## §0 THE PRE-REGISTERED FALSIFIERS — fixed in writing before the probes ran

Each was written into the probe file's own header before its table existed (slice 41's discipline).

- **F0 — THE DOMAIN.** Slice 50's existence condition is `F·ω > 4·V_c·R_b/r₀²` with **`r₀²` in the
  denominator**, so a turn that starts LATE must make its crossing at a SMALLER range. If late
  onsets simply never lose the lock, the interesting end of the axis is empty. *(P0 — the cheapest
  possible kill, run first.)*
- **F1 — THE IDENTITY (LESSONS §694).** If the recovery gauge can be read off the NULL arm's series
  at the event tick, it is the event time wearing units and carries no new information. ⭐ Unlike
  slice 50's at-loss gauges this one is expected to SURVIVE, because the arms diverge after the loss
  — but expected is not measured.
- **F2 — THE PREDICTIVE TEST (LESSONS §671).** Monotonicity and `dt`-stability are not enough:
  slice 50's own pre-registered gauge passed both and crossed its threshold five slider steps before
  the event it claimed to predict. **The interval in which the gauge leaves zero must be the interval
  in which the mechanism says the recovery starts working.**
- **F3 — THE MISS IS NOT AVAILABLE.** 44/46/48 banned it and slice 50 re-earned the ban (the CPA
  reverses four times above `F` = 10, because a blind coast is an open-loop integration chaotic in
  its initial condition). The currency is AUTHORITY and the owed heading, never the miss. CPA is
  printed throughout for orientation and is never a gauge.
- **F4 — THE STEP (slice 42's kill).** Any threshold must survive a re-fly at half `dt`.

---

## §I — P0/P0b: THE AXIS. **F0 FIRES AT THE FIRST ROW, THEN PARTLY UN-FIRES**

The natural axis is the one slice 50 named for it and could not author — WHEN the target turns.
⭐ **It needs no core change to probe:** `ManeuveringTarget.integrate!` reads `:a_lat_mps2` from the
comp bag every tick with a default (`missile.jl:1092`), so writing `0.0` until `t0` and the authored
value after it is exactly what a `maneuver.turn_start_s` key would do.

**P0, at the authored `rcs_fineness` = 8.0 — HALF A SECOND OF DELAY DESTROYS THE MECHANISM:**

| turn onset | 0.00 | 0.50 | 1.00 | … | 6.00 |
|---|---|---|---|---|---|
| lock lost? | **yes** | no | no | no | no |
| blind | 2.097 s | — | — | — | — |

That is F0 by the letter, and it is slice 50's existence condition made vivid: the target must commit
to the turn while the range is still large, because the horizon has to fall *through* the range and a
later turn gives it less range to fall through.

**P0b — the (`rcs_fineness`, onset) grid un-fires it partially.** A slenderer body puts more on the
left of the inequality and buys the onset a domain, ~1.5 s wide at every fineness, walking to later
onsets as the body gets slenderer (`.` = no loss, `L` = lost and the echo returns, `X` = lost and
blind through CPA; the number is the blind duration in seconds):

| F \ onset | 0.0 | 0.5 | 1.0 | 1.5 | 2.0 | 3.0 |
|---|---|---|---|---|---|---|
| 8 | L 2.10 | . | . | . | . | . |
| 10 | L 5.02 | L 2.85 | L 1.19 | . | . | . |
| 12 | X 6.59 | L 4.41 | L 3.25 | L 1.92 | . | . |
| 16 | X 6.95 | X 6.38 | X 5.75 | L 4.19 | L 2.70 | . |
| 20 | X 7.22 | X 6.67 | X 6.06 | L 5.07 | L 0.09 | L 1.10 |

⇒ the axis exists at `F` ≥ 12, and **the blind duration is monotone in the onset** — which is exactly
what a recovery wants to be priced against.

---

## §II — P1/P2: THE PRICE, AGAINST TWO COUNTERFACTUALS

A price needs a counterfactual, so every cell flies three engagements identical until the loss tick:

| arm | what it is |
|---|---|
| `shipped` | the wire: the echo goes away and comes back |
| `never_regain` | `rcs_m2` collapsed at the loss ⇒ blind to CPA — **the FLOOR** |
| `never_lost` | `w.fidelity[:seeker_detect] = :none` at the loss ⇒ never blind — **the CEILING** |

**P1, on the shipped wire (`t0` = 0), gate at 1000 m, `owed` = slice 50's shipped gauge `ω_LOS·t_go`
in degrees:**

| F | arm | blind | max `a/a_max` | sat % | owed@gate | CPA |
|---|---|---|---|---|---|---|
| 7.5 | shipped | 0.378 | 0.447 | 0.0 | **0.554** | 0.21 |
| 7.5 | never_regain | 4.165 | 0.011 | 0.0 | 14.000 | 262.17 |
| 8.0 | shipped | 2.097 | **1.000** | 0.3 | **0.490** | 0.39 |
| 8.0 | never_regain | 4.976 | 0.009 | 0.0 | 19.187 | 338.71 |
| 8.5 | shipped | 3.404 | **1.000** | 8.7 | 11.976 | 66.41 |
| 8.5 | never_regain | 5.441 | 0.021 | 0.0 | 29.706 | 488.06 |
| 10.0 | shipped | 5.024 | 0.027 | 0.0 | **37.314** | **570.56** |
| 10.0 | never_regain | 6.106 | 0.027 | 0.0 | **37.314** | **570.56** |

Three regimes, and the third is the finding:

1. **`F` ≤ 8 — the recovery is FREE.** The wire ends within a whisker of the ceiling arm (0.490 vs
   0.555) after paying at most a brief touch of the g-limit.
2. **`F` ≈ 8.5–9.5 — the recovery is bought with the WHOLE AIRFRAME.** `a_cmd` pinned at `a_max` for
   6–10 % of the flight and the missile still owes 10–14°.
3. ⭐⭐⭐ **`F` ≥ 9.25 — the recovery is worth NOTHING, and "nothing" is exact.** P2 measured
   `max|Δpos|` between the `shipped` arm and the `never_regain` arm over the whole flight at
   **0.000e+00 m** on `F` = 9.25, 9.75 and 10.0. The echo comes back before CPA on every one of them.

⚠ **THE CEILING COLUMN IS INVARIANT AND THAT IS THE RIGHT ANSWER, NOT A BROKEN ARM.** `never_lost`
reads 0.5505 / 0.555 / CPA 0.40 at EVERY fineness, because with the range gate removed the shape
touches nothing at all — slice 50's byte-identity (the shape reaches the SEEING and nothing about the
FLYING), read from the other end.

**F1 (the §694 identity) PASSES** — the gauge is not the loss instant in other units, because the
`shipped` and `never_regain` arms are identical until the loss and diverge after it. The whole
measurement lives in that divergence, which is also, in the end, what kills it.

---

## §III — P3: **THE ECHO CAME BACK. THE TRACK DID NOT.**

A lock that changes not one bit of the flight is not a weak lock; it is no lock, so the reason was
measured rather than assumed. The pre-registered hypothesis was the slice-47 *"two flags that are
ALMOST the same flag"* shape for the THIRD time:

> `seeker_detect` is the **RANGE verdict alone** (`missile.jl:3737`; slice 50's own STATUS block says
> so in as many words). The tracker updates on `in_fov` — the CONJUNCTION of the angular window with
> detectability — shipped as `gimbal_valid` (`:3488`). While the missile is blind the head has no
> measurement to slew on, so **the echo can return to a head that is no longer pointing at it.**

**Measured, and it separates with no exceptions and a clean gap:**

| F | 7.5 | 8.0 | 8.5 | 8.75 | 9.0 | **9.25** | 9.5 | **9.75** | **10.0** |
|---|---|---|---|---|---|---|---|---|---|
| `head_off` at the return (deg) | 0.113 | 0.163 | 0.453 | 5.904 | 0.401 | **24.466** | 0.507 | **19.115** | **14.967** |
| track resumes? | yes | yes | yes | yes | yes | **NEVER** | yes | **NEVER** | **NEVER** |

Every arm whose recovery is worthless has the head **outside the 10° window** when the echo arrives;
every arm that recovers has it inside. ⇒ **A LOCK IS NOT GIVEN BACK BY THE ECHO. IT IS GIVEN BACK BY
THE HEAD.**

⚠⚠ **AND THAT SENTENCE IS THE FINDING; THE INEQUALITY BEHIND IT IS A TAUTOLOGY.** `head_off > fov ⟺
no track` **is the definition of `in_fov`** — it is slice 42's `off@lock == fov` column, the
inclusive gate echoing back its own authored constant. So `head_off` at the return is a legitimate
EXPLANATORY variable and would be a legitimate telemetry key; **it can never be the thing a slider is
scored on.** (Recorded so a later slice cannot re-import it as a gauge.)

⚠ **UNEXPLAINED, AND LEFT UNEXPLAINED RATHER THAN SMOOTHED:** `F` = 8.75 sits at 5.904° among
neighbours at 0.4–0.6° and still recovers. Nothing in these probes accounts for it. §V explains why
no probe at this `dt` can.

⭐⭐ **THE ONE THING SLICE 47's LAW DOES NOT COVER.** The naive prediction of where the head ends up —
the LOS rate at the loss times the blind duration, which is slice 47's shipped law (*the handover
error is the picture error × the time spent blind*) — is **right on the arms that recover and 5–6×
too small on the arms that fail**: 3.682 predicted vs 24.466 measured, 4.251 vs 19.115, 4.492 vs
14.967, against 0.101 vs 0.113 and 0.935 vs 0.163 at the recovering end. The head is carried off the
target by **the missile's own blind flying**, not only by the target's motion. ⚠⚠ Quoted here as an
observation and NOT as a law: §V shows it lives entirely inside the region this slice has just
measured to be irreproducible.

---

## §IV — P4/P5/P6/P7: EVERY CANDIDATE AXIS, AND WHY EACH ONE FAILS

- ⚠ **`rcs_fineness` — DISQUALIFIED, chaotic in the middle of its own domain.** The recovered share
  of the heading debt over `F` = 7.5 … 10.0 reads **0.960, 0.976, 0.974, 0.524, 0.597, 0.215, 0.610,
  0.000, 0.371, 0.000, 0.000** — it reverses three times. Same class as `k` (28), `ω_n` (40),
  `σ_seek` (25) and the loss count (49).
- ⚠⚠ **`gimbal_fov_deg` — DISQUALIFIED, AND FOR A REASON WORTH KEEPING: IT CHANGES THE MECHANISM.**
  Slice 46 shipped the coupling — the window IS the beamwidth (`bw_det = 2·fov` → `aperture_gain` →
  `detection_range`, `missile.jl:2681`) — so widening it shortens the horizon. Measured at `F` = 8:
  at `fov` = 6–8° the missile **never detects the target at all**, at 10° it is slice 50's wire, and
  at 16–20° it **starts blind and acquires later** (CPA 0.20 m, no loss at all). ⇒ dragging this
  knob does not move slice 50's engagement; it turns it into **slice 46's**. Not two mechanisms in
  one scenario — two *scenarios* on one knob.
- ⭐ **THE TURN ONSET — the only axis that behaves.** At `F` = 16 the blind duration falls
  monotonically with the onset (6.38 → 6.08 → 5.75 → 4.75 → 4.19 → 3.61 → 2.70 → 1.99 → 1.41 s) and
  the recovered share rises **0, 0, 0, 0, 0, 0, 0.430, 0.802, 0.934** with a threshold between
  onsets 1.75 s and 2.00 s. Below it the flight is bit-identical to one that never got the echo back.
- ⚠ **F2 FIRED ONCE ON A GAUGE-WINDOW DEFECT, AND THE DIAGNOSIS IS LESSONS §536.** The first
  predictive test failed by one slider step: the 1000 m RANGE gate is crossed at ~7.5 s while the
  echo returns at 7.689 s, so that arm was **priced before the event it was meant to price**. A gauge
  must carry its own window. Re-sited to the EVENT — both arms read at the same tick, 0.40 s after
  the return — the gauge behaves at the shipped `dt`. It is the re-sited gauge that §V kills.

---

## ⭐⭐⭐ §V — P8/P9: **WHAT KILLS THE SLICE. THE BOUNDARY DOWNSTREAM OF A BLIND COAST DOES NOT REPRODUCE.**

> ⚠ **THIS HEADING WAS RETRACTED AND REWORDED ON 2026-08-31, SAME DAY.** It first read *"NOTHING
> downstream of a blind coast reproduces"*, which **P9 in this very section contradicts**: once the
> guidance loop CLOSES again the flight re-converges, and the short-end arms agree on every verdict
> at both step sizes. The claim that survives the evidence is narrower and is the one that kills the
> slice: **the BOUNDARY does not reproduce** — which side of *"does the track come back at all"* a
> marginal setting falls on — together with anything read while the loop is still open. ⚠⚠ Left in
> place rather than silently corrected because an over-broad ban retires work that was never in
> danger, and this record is what a future slice will quote. See LESSONS §"A BAN ON A GAUGE".

F4 was the last falsifier and it fired hardest. Run on the **shipped slice-50 scenario with no onset
emulated at all**, full `dt` against half `dt`:

| F | `dt` | `t_loss` | `r_loss` | `t_back` | `head_off`@return | track? | CPA |
|---|---|---|---|---|---|---|---|
| 8.0 | 1e-3 | 3.2760 | 3812.79 | 5.3730 | 0.163 | resumes | 0.391 |
| 8.0 | 5e-4 | 3.2780 | 3811.26 | 5.9685 | 0.454 | resumes | 0.686 |
| | **drift** | **0.061 %** | **0.040 %** | **11.08 %** | **178.9 %** | same | 75.3 % |
| 9.0 | 1e-3 | 2.6350 | 4266.45 | 6.2820 | 0.401 | **resumes** | **33.46** |
| 9.0 | 5e-4 | 2.6355 | 4266.02 | 6.9880 | 11.397 | **NEVER** | **684.91** |
| | **drift** | **0.019 %** | **0.010 %** | **11.24 %** | **2742 %** | ⚠⚠ **FLIPS** | 1947 % |
| 10.0 | 1e-3 | 2.2570 | 4532.25 | 7.2810 | 14.967 | NEVER | 570.56 |
| 10.0 | 5e-4 | 2.2570 | 4532.19 | 7.2455 | 12.393 | NEVER | 554.63 |
| | **drift** | **0.000 %** | **0.001 %** | 0.49 % | 17.2 % | same | 2.8 % |

**Everything measured AT the loss reproduces to 0.08 % or better — slice 50's own result, confirmed
independently. What is measured WHILE THE LOOP IS OPEN does not**, and at `F` = 9.0 — *inside slice
50's shipped slider domain* — halving the step **flips the qualitative verdict**: the track comes back
at one step size and never comes back at the other, with the CPA going 33 m → 685 m. ⚠ Note the row
that is NOT chaos: at `F` = 10.0 the track never returns at either step size and the CPA agrees to
2.8 %. **The instability is not "after the loss" as a blanket region — it is concentrated where the
return is finely balanced**, and `F` = 9.0 is that balance point.

⇒ ⭐⭐⭐ **THE MISS BAN WAS NEVER A BAN ON A GAUGE. IT IS A BAN ON A REGION OF THE FLIGHT.** 44, 46,
48 and 50 each banned the miss on this arc and each gave the same reason — a blind coast is an
open-loop integration, chaotic in its initial condition. The miss was simply the first quantity
anyone tried to read there. **The reason applies verbatim to the return time, the head angle at the
return, the recovered share, and to the yes/no of whether the track ever comes back.**

**P9 — and the short end does not rescue it.** At `F` = 7.4–8.0 the blind phase is 0.38–2.10 s and
the *verdict* is stable (every arm recovers and hits at both step sizes), but no quantity is: the
blind duration moves 8–28 % and `head_off` 3–179 %. ⚠ In fairness those percentages are taken on
near-zero numbers (0.113° vs 0.240°, 0.21 m vs 0.11 m of miss) and change no verdict — **the honest
statement is that the SHORT end is qualitatively robust and quantitatively unpinnable, and the
threshold, which is the only thing a slider lesson could be about, sits in the middle where the
verdict itself moves.** That is slice 42's kill in its own words: a threshold no wider than the
instrument that measures it.

---

## §VI — THE VERDICT

**KILLED AT GATE 0 AS A SLICE.** Not for want of a mechanism, an axis or a counterfactual — all three
were found — but because **the quantity it exists to measure is not reproducible under a halved
integration step, and its threshold moves a whole slider step.** A teaching instrument whose lesson
reverses when the step halves is not a lesson.

⚠ **THIS IS A "LESSON" KILL AND NOT A "MODEL" KILL** (the 2026-08-18 two-test rule). No component was
proposed, nothing shipped is refuted, and no key is removed. `maneuver.turn_start_s` was never
written; if a later slice wants it, §I's emulation shows the seam is clean: **EIGHT** shipped
scenarios author a `maneuver:` block (12, 15, 19, 21, 22×2, 49, 50) and none carries such a key —
absent ⇒ `w.t ≥ 0.0` ⇒ the turn starts at `t` = 0 ⇒ every slice 12–50 wire byte-identical.
**Verified by name, not by construction (LESSONS §752).** ⚠ And the first count taken here was TEN,
because `grep -l 'maneuver:'` matches the two scenarios whose comments say they have **no** such
block (`slice14_salvo`, `slice20_induced_drag`) — §752's own failure, in the very sentence citing it.

## §VII — WHAT IS BANKED (the three findings, in the order they are worth)

1. ⭐⭐⭐ **THE BOUNDARY DOWNSTREAM OF A BLIND COAST DOES NOT REPRODUCE — the miss ban is a ban on a
   REGION.** §V. The most transferable thing here: it tells every future slice on this arc where it
   may and may not read a number. ⚠ Stated as *"nothing downstream reproduces"* in this record's
   first draft and RETRACTED the same day — see the box at the head of §V for the narrower claim the
   evidence actually supports.
2. ⭐⭐⭐ **A LOCK IS GIVEN BACK BY THE HEAD, NOT BY THE ECHO** — and when the head has been carried
   away, the flight is **bit-identical** (`max|Δpos| = 0.000e+00`) to one that never got the target
   back. §II/§III. ⚠ It also sharpens a sentence slice 50 ships: *"lock given back"* on that wire is
   a RANGE-lamp statement, and on the `F` = 10 arm the TRACK never returns.
3. ⭐⭐ **A DEFENSIVE TURN MUST BE EARLY, AND HALF A SECOND IS THE DIFFERENCE.** §I. Slice 50's
   `r₀²`-in-the-denominator condition, made concrete on its own wire.

⚠ **AND ONE NON-FINDING, RECORDED SO IT IS NOT RE-IMPORTED:** `head_off > fov ⟺ no track` is the
definition of `in_fov`, not a measurement (§III).

---

## ⭐⭐ §VIII — WHAT SHIPPED ANYWAY (added 2026-08-31, after the verdict)

§VI closed with *"no component was proposed"* and treated that as the end of it. **That applied the
2026-08-18 two-test rule only half way.** The rule's own words are that a pass-model / fail-lesson
result **"ships as physics + tests + authorable keys"** — the LESSON dies, the hardware does not, and
EWSim is a battlefield simulator as well as a teaching instrument. Slice 51 failed the LESSON test
and was never given the MODEL test. Given it, two things come out.

### 1. `maneuver.turn_start_s` — SHIPPED (the turn onset)

**The model claim, independent of any lesson:** every scenario from 12 to 50 authors a target that
has been turning since `t` = 0 and never stops. That is staging, not a defence. An aircraft breaks
at a MOMENT — when the launch is seen, when the RWR lights — and a simulator that cannot express the
moment cannot express a defensive break at all. §I needed exactly this and had to EMULATE it from
outside the core, which is itself the argument: a quantity a probe must fake is a quantity the
simulator is missing.

- **Consumer** (`core/src/missile.jl`, `ManeuveringTarget.integrate!`): `a_lat` is zeroed until
  `w.t ≥ turn_start_s`. ⚠⚠ **The gate is on the VALUE, not on the call.** `_lateral_accel` with
  `a_lat = 0` returns SIGNED ZEROS — measured `(-0.0, 0.0, -0.0)` on the slice-12 heading — so
  zeroing the value is BIT-identical to the already-shipped `a_lat_mps2: 0.0` path, while an early
  `return zero(Vec3)` would be ≈-equal and not bit-equal. The absolute golden would have found it;
  the advisor found it first.
- **Loader** (`core/src/scenario.jl`): finite and ≥ 0, refused at LOAD. A NaN/Inf makes
  `w.t ≥ turn_start_s` false forever ⇒ the target silently never turns ⇒ a DEAD KNOB, which is the
  one OUTRIGHT kill under the two-test rule. A negative value is a second spelling of `0.0`.
  ⚠ NOT refused beside `a_lat_mps2: 0.0`, unlike `cross_speed_mps`: `a_lat_mps2` is a live slider on
  the shipped 12/15 wires, so the onset goes live the moment a student drags it. `cross_speed_mps`
  is read by NOTHING, EVER — that, and only that, is what the older guard rests on.
- **Named approximation, measured not assumed** (probes `p10_onset_key.jl` / `p11_onset_dt.jl`,
  `M:\claud_projects\temp\slice51\`): the onset is QUANTIZED to a physics step. A value that is an
  exact multiple of `dt` lands exactly (0.5 s is the 501st tick at both 1e-3 and 5e-4); anything else
  lands late by under one step, and that lateness HALVES with `dt` (0.5005 s realizes at 0.5010,
  then at 0.5005). ⚠⚠ It is also the one place `w.t`'s float accumulation is load-bearing: 500 steps
  of 1e-3 accumulate to 0.5000000000000003, i.e. just ABOVE the boundary. Had the drift gone the
  other way, the same authoring would bite one step later. **Do not author an onset AT a step
  boundary when a step matters.**
- **Byte-identity verified BY NAME** (LESSONS §752, and §VI's own near-miss): the eight scenarios
  authoring a `maneuver:` block are 12, 15, 19, 21, 22_departure, 22_stall, 49, 50, and `grep` finds
  `turn_start_s` in none of them. Absent ⇒ the key never lands in the comp bag ⇒
  `get(c, :turn_start_s, 0.0)` ⇒ `w.t ≥ 0.0` true on the first step.
- **Tests:** consumer teeth in `core/test/test_missile.jl` (the onset tick; pre-onset BIT-equality to
  the `a_lat = 0` wire, signed zeros included; `0.0` bit-equal to the key absent; the huge-finite
  null; the `dt` quantization), loader teeth in `core/test/test_scenario.jl` (the control with the
  key absent, the accepted values, and the four refusals).
- ⚠ **This is a KEY, not a HEADLINE.** It ships no scenario, no view, no verifier and no slider — it
  is not slice 52 and must not be quoted as one. Under the two-test rule it is exactly what a
  fail-lesson / pass-model result is entitled to: physics, tests, and an authorable key.

### 2. No re-cue on a returning echo — NAMED, NOT FIXED

§III found that when the echo comes back the track resumes only if the head happens to still be
pointed within its window — and on slice 50's wire it routinely is not, because the head has been
slewing on the estimator's FROZEN rate through the blind phase. **That is not a branch anyone wrote;
it is the absence of one**, which is why it had gone unnamed for seventeen slices. A real seeker
re-cues onto a signal arriving off-boresight, or widens its search when one is expected.

Named at the site where the behaviour falls out (`core/src/missile.jl`, at the
`in_fov = in_fov && _detectable` conjunction). ⚠ **NAMING IS NOT FIXING.** A fix changes seeker
behaviour on slices 34–50 and needs its own decision — carried to `docs/DEFERRALS.md` as a candidate,
with the standing warning that `head_off > fov` is `in_fov`'s definition and can never be its gauge.

⇒ **THE VERDICT, RESTATED:** slice 51 is **DEAD AS A LESSON, ALIVE AS A MODEL** — the standard
verdict word since 2026-08-18, and §VI should have used it.
