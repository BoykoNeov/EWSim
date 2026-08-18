# Slice 47 — THE MIDCOURSE PHASE (what a blind missile flies on, and what a wrong picture costs)

**Status: GATE 0 — PLANNED, NOT YET PROBED (2026-08-18).**

**What this slice is:** the missile stops getting its blind phase for free. Today, between launch and
the moment the seeker's horizon opens, the missile commands **nothing at all** and its head is cued
**off the truth**, and it arrives anyway because the engagement was authored so that doing nothing is
right. This slice gives the blind phase a *guidance law* (fly toward a predicted intercept point
computed from the launch-time target picture) and gives that law an *error* — because the picture is
never perfect, and how wrong it can be is the only thing here that a student can be asked to judge.

---

## §0 — THE PREMISE, MEASURED, AND IT CORRECTS THE BACKLOG

⚠⚠ **`docs/DEFERRALS.md` §"New candidates raised by slice 46" says the default cell is *"flying pure
PN off a target it cannot see"*. THAT IS WRONG, and P0 measured it wrong on the shipped wire**
(`M:\claud_projects\temp\slice47\p0_blind.jl`, `scenarios/slice46_horizon.yaml`, unmodified):

```
blind ticks = 6955   lock t = 6.9560 s   MAX |a_cmd| WHILE BLIND = 0.000000 m/s^2
```

Not "small". **Exactly zero, for 6955 consecutive ticks, and then it arrives at 2.998 m.** The
mechanism is structural, not tuned: the Seeker's `observe!` writes `:seeker_omega` **unconditionally**
(`core/src/missile.jl:2629`, function-level, outside the availability chain), so `missile.jl:1187`'s
`elseif guid === :pn && haskey(c, :seeker_omega)` is taken on **every** tick of **every** seeker wire
in the arc — the truth-PN fallthrough at `:1191` is unreachable there. While never-locked the
estimator's own init zeroes every state (`:2443`, "NEVER LOCKED — … no estimate, no rate"), so
`ω = 0` and `pn_accel_from_omega` returns the zero vector. **A blind missile in this arc is
ballistic.** It is not guided badly; it is not guided.

⭐⭐ **AND THE SECOND HALF OF THE PREMISE IS WORSE THAN THE FIRST: the free ride is AUTHORED.** The
missile launches from `[0, 0, 3000]` at 700 m/s, 12° up, **in the x–z plane** (no azimuth key), and
the target is authored at `[6000, 2000, 4200]` with `vy = −200` — i.e. **flying INTO the missile's
ballistic plane.** Doing nothing is the right answer on this wire *by construction of the scenario*,
which is exactly the class of thing this project keeps discovering the expensive way (slice 44: *"the
physics is not what failed, what failed is the WIRE"*). ⇒ **the correction goes into `DEFERRALS.md`
at the doc ritual whatever this slice's verdict turns out to be** — it is a fact about the shipped
tree, independent of whether slice 47 ships.

⚠ **A THIRD FREEBIE IS SUSPECTED AND NOT YET MEASURED (P2 below settles it): the head appears to be
CUED OFF TRUTH while blind.** `:head_tgt_az` / `:head_tgt_el` are written unconditionally under
`_gim` at `missile.jl:2437` from the MEASURED angles `az_m`/`el_m`, which are formed from truth
regardless of whether the range gate passed — while the slew branch at `:2088` states that *"a head
outside its detector window simply does not slew"*. Those two sentences cannot both be the whole
story, and which one wins decides whether the head arrives at the lock instant pointing at the target
or pointing where the target was at launch. Slice 46's own scenario header already flags the
posture — *"before the horizon opens the head is CUED rather than tracking — modelling the cue and the
search that follows a bad one is the next slice"* — and this is that slice.

## §0.1 — WHY THE OBVIOUS LESSON IS DEAD BEFORE IT IS BUILT, AND WHAT REPLACES IT

⚠⚠ **"MIDCOURSE vs NO MIDCOURSE" CANNOT BE THIS SLICE'S AXIS, and pre-registering that is the single
most valuable line in this gate.** Today: blind costs zero and the missile hits at 2.998 m. Add a
midcourse that flies at a *correct* predicted intercept point and it will command something small and
also hit. **Perfect-midcourse ≈ ballistic ≈ hits, on this wire, because the launch heading is already
the collision course.** A gate-3 slider on "is the midcourse on?" would measure a null and this
component would be killed for the second time in this arc by its own showcase — which is precisely
what slices 44 and 45 did (`docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT").

⭐⭐ **THE AXIS IS MIDCOURSE *ERROR*, and the constraint chain that makes it bite is ALREADY BUILT
AND BANKED — this slice re-derives none of it:**

```
    midcourse error  →  heading error at the lock instant  →  handover error
                     →  slice 43's OVERLAP DEFICIT  |err| − fov   →  acquisition cost, or no lock
```

with **slice 46's aperture identity underneath it**: buying window to survive a worse handover
**shortens the horizon** (`R_acq · fov = 80789.2 m·deg`), which **lengthens the blind phase**, which
**grows the error**. ⭐ **That three-way squeeze is a law no shipped slice states, and it is the honest
headline for 47:** slices 32–36 said a wider window is free; slice 46 said it costs reach; slice 47
would say **it costs reach, and reach is what was keeping the error small in the first place** — so
the window is not merely two-sided, it is two-sided *through a feedback path*.

⚠ **AND IT IS A CONDITIONAL HEADLINE. P1 (below) is the blocking probe and it runs before anything is
written past this section.** If a physically defensible midcourse error cannot drive the handover
error past the 10° window, the headline dies here — at zero cost — instead of at gate 3.

> ⚠⚠ **RESULT (2026-08-19, §4): P1 PASSED — the error axis is real, linear and monotone, and it
> crosses the window at a 20.5 % target-velocity misestimate. BUT P5 FALSIFIED THE SQUEEZE: widening
> the window IMPROVES the angle margin monotonically, because the lock time SATURATES against the
> CPA. The three-way squeeze written above is PROSE, NOT PHYSICS, on this wire.** What replaces it is
> in §4.3: the cost does not vanish, it MOVES — into slice 46's own currency. **Read §4 before §1.**

## §0.2 — THE CONSTRAINT THAT IS CITED, NOT RE-PROBED

⚠ **DO NOT SPEND A PROBE TRYING TO REACH "OUTSIDE THE HORIZON" BY MOVING THE LAUNCH.** Slice 44 §V
measured it and slice 46's scenario header quotes it: an unpowered missile with zero drag area at
3000 m needs **≥ 28 s** to fly 20 km, and **gravity alone drops it 3845 m into the ground first.** A
BOOST PHASE is its own slice and is not in scope here. ⇒ **the blind phase is reached the way slice 46
reaches it — by SHRINKING THE TARGET** (the `rcs_m2` ladder already gives 434 → 6955 blind frames),
**and the cost comes from the launch HEADING being wrong, never from the launch RANGE being long.**
This is slice 46 citing slice 44's gate 0 rather than re-flying it, one slice on.

## §0.3 — THE SEAM, AND THE ONE LINE EVERY SLICE 11–46 FLIES THROUGH

`core/src/missile.jl:1187`. Because the seeker writes `:seeker_omega` unconditionally, that branch is
taken on every tick of every seeker wire in the arc, and the zero command while blind is an **accident
of the never-locked init**, not a designed behaviour. Constraints that follow, and they are not
negotiable:

1. ⚠⚠ **A midcourse arm is gated on NEW KEY / RUNG PRESENCE, with every existing arm TEXTUALLY
   VERBATIM** — the "STRUCTURAL BYTE-IDENTITY (the slice-20/21/26 shape)" pattern this file already
   uses at `:2608`. **Never `a_dem + a_midcourse`** trusting a zero to cancel: `-0.0 + 0.0` is `+0.0`
   and float addition is not associative, and this file names that trap three times already.
2. ⚠ **The BIT-IDENTITY CONTROL IS THE ABSENT KEY, never `= 0.0`** (slice 35's blocking pin, slice
   36's verbatim restatement). Absent midcourse keys ⇒ absent arm ⇒ byte-identical 11–46.
3. ⚠ **The ABSOLUTE GOLDEN is the check that matters**, not `test_determinism` — the latter
   structurally cannot catch a draw-ORDER regression (convention 2).

## §0.4 — REUSE, DON'T REBUILD

- **Slice 36 already owns handover-error machinery** (`gimbal_handover_err_deg`, a birth offset fed
  **inside** `head_clamp` at `missile.jl:1999`, with its stop policy, its V-shaped basket and its sign
  convention all measured). ⭐ **Slice 47's whole content is that this quantity stops being AUTHORED
  and becomes the OUTPUT of the midcourse.** ⚠ But they are not the same quantity — 36's is where the
  *head* is born; 47's is where the *missile* has flown to. **P3 settles whether 36's key can be
  DRIVEN or whether the two must coexist**; if it can be driven, most of gate 2 is plumbing.
- ⚠ **Slice 36's key is REFUSED AT LOAD beside the `:stabilized` rung** (`:1988`) for a stated
  false-claim reason (36's basket is stated in the BODY frame). Any driving of it inherits that
  refusal — do not quietly widen it.
- **Slice 43's law is BANKED and cited, not re-derived**: `travel = deficit/(1−ω/ρ)`, the sweep floor,
  `ρ* = min_t[…]`, the U-shaped best moment (`docs/DEFERRALS.md`, confirmed 4/4 on untuned
  geometries).
- **Slice 46's aperture identity is SHIPPED PHYSICS** (`rf.jl`, `aperture_gain` / `detection_range`)
  and is read, not recomputed.

## §0.5 — PRE-REGISTERED: THE FOUR THINGS THIS SLICE MUST NOT DO

1. ⚠⚠ **MISS IS NOT THE GAUGE. IT HAS BEEN KILLED TWICE.** Slice 44 killed the component on it; slice
   46 measured it **non-monotone over a 10 000× range** of target size (0.2237 → 0.2783 → 0.0858 →
   0.1167 → 0.0453 → 0.9874) while the authority column rose strictly the whole way. **Slice 47 moves
   the ACQUISITION INSTANT and the handover error — exactly the class miss cannot show.** Headline
   columns: **handover error at lock**, **peak `a_cmd` after lock as % of `a_max`**, **hold %**.
2. ⚠⚠ **ENDGAME-GATE EVERY NEW GUIDANCE-DERIVED READOUT AT `r > 200 m`.** This is slice 46's own new
   method lesson (`docs/LESSONS.md`), earned by catching slice 44 §VII.1's "100.00 % of `a_max`" as an
   r → 0 artefact: gated, the same cell reads **10.45 %** against **3.10 %**. Every headline column
   above is guidance-derived. ⚠ **Never quote the ungated figure.**
3. ⚠⚠ **NO PER-TICK RNG DRAW.** A stochastic datalink or a noisy launch-time picture is an
   unconditional per-tick `randn` and **desyncs every 25–46 replay** (convention 3: the per-look draw
   COUNT must be invariant to rung, slider AND target). ⇒ **gates 1–2 ship an AUTHORED DETERMINISTIC
   midcourse error — a signed bias, a knob, no draw.** A stochastic datalink is a **named deferral
   whose draw topology is planned BEFORE it is proposed**, not after (slice 13's `:scan` 4b shape is
   the pattern if it is ever taken up).
4. ⚠ **VERDICT, NEVER METRES, ON ANY ARM THAT LOST THE TRACK.** Slice 44 §VII.3: failure magnitudes
   walk 320 → 627 m across 4× `dt` while the verdict is step-independent. Broken-arm assertions are
   `hold% <` / never-locks booleans, never a metre tolerance.

## §0.6 — THE PROBES, WITH THEIR FALSIFIERS WRITTEN DOWN FIRST

⚠ House discipline: **probe empirically, THEN pin against the live wire oracle — never against a
hand-recompute** (convention 10, `docs/LESSONS.md`). Probes live in `M:\claud_projects\temp\slice47`.

| # | question | falsifier — what would kill it |
|---|---|---|
| **P0** | What does a blind missile do today? | **RUN, PASSED.** `a_cmd ≡ 0` for 6955 ticks; the gap is real and is "no midcourse at all". |
| **P1** ⭐ **BLOCKING** | Can a physically defensible midcourse error drive the handover error **past the 10° window** at the lock instant? | **If no defensible error reaches the window, THE HEADLINE IS DEAD** — the squeeze in §0.1 has no domain and the slice needs a different lever. ⚠ Sweep until it does, then ask whether the value required is defensible or absurd; **an absurd required error is a kill, not a result.** |
| **P2** | While blind, is the head CUED OFF TRUTH, or does it HOLD at its birth direction? (§0 third freebie) | Either answer is informative; **the kill is finding a THIRD free thing that has to be paid for in the same slice** — that would make 47 two lessons stacked (convention 9) and the cue would split off as its own slice. |
| **P3** | Can slice 36's `gimbal_handover_err_deg` be **driven** by the midcourse, or must a second quantity coexist? | If driving it violates 36's stated body-frame sign convention or its `:stabilized` load refusal, **it must NOT be driven** — a second key is cheaper than a measured slice's name on a different physical birth. |
| **P4** | Does the midcourse **error** move the headline columns MONOTONICALLY over a defensible domain? | ⚠ **Non-monotonicity is this project's standing disqualifier for a SHOWCASE SLIDER** (`k` 28, `ω_n` 40, `σ_seek` 25, miss-vs-`K` 20/22) — it does not kill the component, it kills the slider. If it reverses, the axis moves to whatever *is* monotone. |
| **P5** | Does the three-way squeeze in §0.1 actually CLOSE — does widening `fov` to survive a bad handover cost enough horizon to make the error worse? | **If widening the window is still net-free, the squeeze is prose, not physics**, and the slice ships as a component-fidelity slice (the shape `DEFERRALS.md` §"What this changes about what to build" makes legal) with the null as documentation. |

## §0.7 — THE TWO-TEST VERDICT, DECLARED IN ADVANCE

Per `CLAUDE.md` §"TWO AIMS ⇒ TWO TESTS ⇒ TWO VERDICTS":

- **MODEL test** — a midcourse law read by the physics every tick of the blind phase, in its own
  units/signs/frames, with the slice-19 tripwire (a test asserting each authored key MOVES a measured
  quantity). **This is the only outright kill available**, and it is the bar this slice must clear to
  ship at all.
- **LESSON test** — does the midcourse ERROR move the headline columns on an authored scenario?
  Failing it costs the **headline**, not the hardware: the component still ships as physics + tests +
  authorable keys, with the measured null as documentation.

⚠ **AND SLICE 39's DISCIPLINE IS UNTOUCHED: a reparameterization must not ship as an ARCHITECTURE.**
Before gate 1, check the obvious one — *is "fly toward a predicted intercept point with a bias" just
PN against a displaced virtual target?* If it is algebraically that, say so and ship it as the small
thing it is.

## §0.8 — SCOPE, AND WHAT THIS DOES **NOT** CLAIM

**Slice 47 ships the midcourse phase only. The SEARCH PATTERN stays slice 48.**

⚠⚠ **DO NOT CLAIM THE SEARCH FAMILY IS UNBLOCKED UNTIL IT IS MEASURED.** `DEFERRALS.md` states the
remaining unblocker as *"something to fly on while blind"* plus *"a launch outside the horizon"*. Slice
47 supplies the first and slice 46 supplied the authoring for the second — but a search needs a
**pointing error it cannot resolve**, and whether 47's midcourse error produces one is P1's and P5's
business, not an assumption. **The plan's closing section records the measured answer, in one line,
either way.**

Gate-3 traps inherited and worth one line each (`docs/CONVENTIONS.md` §14, `docs/LESSONS.md`):
a verifier's `STEPS` **must** be a multiple of `emit_every` (else a SILENT hang); `%g` / `%.2e` are
not GDScript specifiers and one bad one kills the whole `%` silently; **the HUD width budget is
INHERITED (55 body / 30 headline) and asserted in PIXELS** — slice 46's 100/96-CHAR tooth passed
GREEN while every line clipped at 1152 **and** 1920 px; and a rung that stops EMITTING makes the
client's `.get(k, 0.0)` print a DEFAULTED ZERO as a PASSED TEST.

---

## §1 — GATE 1: THE PURE PRIMITIVES

*Not written. Blocked on P1 — see §0.1.*

## §2 — GATE 2: THE WIRE

*Not written.*

## §3 — GATE 3: THE SHOWCASE

*Not written.*

## §4 — THE LOG (what actually happened)

### §4.0 P0 — RUN, AND IT CORRECTED THE BACKLOG (2026-08-18)

`p0_blind.jl`, `scenarios/slice46_horizon.yaml` unmodified, default cell (`rcs_m2 = 0.001`):

```
   tick       t    |a_cmd|      r_los      r_acq      det      |v|         z
    800   0.800     0.0000     5856.1     1436.7        0    698.4    3113.8
   4000   4.000     0.0000     3543.8     1436.7        0    692.6    3522.2
   6400   6.400     0.0000     1828.3     1436.7        0    689.0    3779.4
   6956   6.956     0.0000     1436.3     1436.7        1    688.2    3833.0   <- LOCK
   7200   7.200   627.2139     1264.9     1436.7        1    687.9    3857.2
   8800   8.800  1118.9539       72.5     1436.7        1    683.3    4177.0
blind ticks = 6955   lock t = 6.9560 s   MAX |a_cmd| WHILE BLIND = 0.000000 m/s^2
```

⭐ The lock instant reproduces slice 46's own ladder row to four decimals (6.9560 s, `R_acq` 1436.7 m),
so the probe is on the shipped wire and not a lookalike. **`DEFERRALS.md`'s "flying pure PN off a
target it cannot see" is corrected to "flying NOTHING — commanding exactly zero for 6955 ticks — and
arriving because the scenario authored the target into the missile's ballistic plane."**

### §4.1 P2 — THE THIRD FREEBIE IS REAL: THE HEAD IS CUED OFF TRUTH, FOR FREE (2026-08-19)

`p2_cue.jl`, shipped wire, default cell. Through the entire 6955-tick blind phase the detector's
off-head-axis error never leaves the noise:

```
   tick       t   det    head_off  fov_margin look_body_az  head_angle   rate_sat
      1   0.001     0     0.00000    10.00000    18.10198    18.11386          0
   4000   4.000     0     0.05979     9.94021    19.80346    19.84793          0
   6400   6.400     0     0.19190     9.80810    23.31121    23.82132          0
   6956   6.956     1     0.30212     9.69788    25.31614    26.15544          0   <- LOCK
MAX head_off_deg WHILE BLIND = 0.302005 deg   head_off AT LOCK = 0.302123 deg   (window = 10 deg)
```

⭐ **The head tracks the true LOS through 25° of body-frame travel while the seeker cannot see
anything, and arrives at the lock instant 0.30° off a 10° window.** `:head_tgt_az` wins over the
"does not slew" comment (§0): the target is written unconditionally under `_gim` from the measured
angles, so the head is *externally cued off truth* for the whole blind phase, free and perfect.
⇒ **THE BLIND PHASE IS FREE IN THREE SEPARATE WAYS** — no guidance command (P0), a perfect cue (P2),
and an authored launch heading that is already the collision course (§0).

⚠⚠ **AND THE CUE IS NOT DEFERRABLE — IT IS THE SLICE'S CENTRAL DESIGN FORK, WHICH §4.2 BELOW ASSUMES
AN ANSWER TO.** P1's quantity is the angle between where the target IS and where the launch-time
picture SAID it would be. **That is a handover error only if the head is cued on the PICTURE.** On the
shipped mechanism it is cued on TRUTH, so on today's wire a 20.5 % midcourse error produces a **0.30°**
handover error, not 10.2°. P1 measured the geometry of a design that does not exist yet — legitimate
gate-0 work, and the reason gate 0 exists — but §1 cannot be written until the fork is chosen:

| the head is cued on… | what a midcourse error costs | consequence for this slice |
|---|---|---|
| **the BELIEF** (a real datalink/midcourse cue) | **ANGLE** — P1's axis is live, linear, 0.4970 °/%, past the window at 280 m of PIP error | fixing the cue is **IN SCOPE**, not deferred; P1's table is this slice's number |
| **TRUTH** (today, unchanged) | **AUTHORITY and GEOMETRY only** — the angle gate never sees it | P1's 20.5 % is **NOT this slice's number**, and the cost must be measured without P6's confound (§4.4) |

⭐ **The physical answer is the belief**: a seeker head is cued by whatever told the missile where to
look, and on a blind missile that is the midcourse, not omniscience. But it must be CHOSEN and
written down, not inherited — and choosing it means the cue and the guidance are ONE component with
one authored quality figure, which is also how convention 9 is satisfied (one lesson: *how good does
the launch-time picture have to be*), rather than two freebies priced in one scenario.

### §4.2 P1 — PASSED, AND THE AXIS IS LINEAR (2026-08-19) ⭐ **THE BLOCKING PROBE**

`p1_error.jl` / `p5_squeeze.jl`. **No core patch is needed and that is the probe's whole idea: the
AUTHORED LAUNCH HEADING *IS* the midcourse solution for the AUTHORED target** (P0), so perturbing the
target's true crossing speed turns that heading into a wrong midcourse. The missile is uncommanded
while blind, so its flown trajectory is **bit-identical across every arm** (`dtraj = 0.00e+00`,
asserted per arm — this is also an independent confirmation of P0's mechanism). At the lock instant,
`û_true` comes from the perturbed run and `û_pred` from the baseline run at the same tick and the
same flown missile position. ⚠ **THE POSITIONS ARE OFF THE WIRE; THE CUE MECHANISM IS ASSUMED** — this
table prices the "cued on the belief" branch of §4.1's fork and is void on the other one.

```
  err%   vy_true   lock t   traj-identical   PIP err @lock   HANDOVER ERR   vs 10° window
   0.0    -200.0   6.9560         0.00e+00           0.0 m         0.0000   inside
   5.0    -210.0   6.9160         0.00e+00          69.2 m         2.5025   inside
  10.0    -220.0   6.8820         0.00e+00         137.6 m         4.9928   inside
  15.0    -230.0   6.8510         0.00e+00         205.5 m         7.4720   inside
  20.0    -240.0   6.8250         0.00e+00         273.0 m         9.9547   inside
  20.5    -241.0   6.8230         0.00e+00               —        10.2057   *** PAST ***
  30.0    -260.0   6.7860         0.00e+00         407.2 m        14.9618   *** PAST ***
  50.0    -300.0   6.7580         0.00e+00         675.8 m        25.3970   *** PAST ***
```

⭐⭐ **THE WINDOW IS CROSSED AT 280 m OF PREDICTED-INTERCEPT-POINT ERROR, READ AT A 1437 m LOCK
RANGE.** ⚠ **Quote it in METRES, not in the 20.5 % it corresponds to**: the percentage is a fraction of
*this target's* 200 m/s and is scenario-specific, while a PIP error in metres is the currency a
midcourse is actually specified and judged in, and it needs no side-claim about how good a launching
radar's track is. 280 m at 6.8 s of blind flight is an ordinary midcourse, not an absurd one, so the
falsifier in §0.6 does not fire: **the headline axis is defensible.**
⭐ And it is **STRICTLY LINEAR at 0.4970 °/%** across the whole domain (0.5023 / 1.0038 / 2.5025 /
4.9928 / 7.4720 / 9.9547 at 1/2/5/10/15/20 %), which clears P4's non-monotonicity disqualifier
outright — the axis this project usually has to hunt for is simply a straight line here.
⭐ **The lock instant barely moves** (6.9560 → 6.8250 s over the whole domain, 1.9 %), so the effect
is almost pure handover error rather than a lock-timing confound.

### §4.3 P5 — **FALSIFIED. THE THREE-WAY SQUEEZE DOES NOT CLOSE** (2026-08-19)

§0.1 predicted that widening the window to survive a bad handover would shorten the horizon enough
(46's `R_acq · fov` identity) to lengthen the blind phase and make the error worse — a self-defeating
cure. **Measured, at a fixed 15 % midcourse error, it is not true:**

⚠⚠ **THE TABLE IS RESTATED ON THE ADMISSIBLE SUBSET, AND THAT IS THIS PLAN'S OWN RULE BITING ITS OWN
EVIDENCE.** §0.5 rule 4 forbids quoting METRES (or degrees) on any arm that lost the track, and P6b
shows `fov ≥ 15` at hold 17.25 % / 6.90 % with the CPA opened to 160 / 272 m — **those rows are broken
arms and their margins are sampling a divergence, not measuring one.** The refutation stands on the
rows where the track holds (`hold ≥ 99.94 %`):

```
fov deg    R_acq m      R*fov   lock t (s)     handover  MARGIN fov-err   hold %
    6.0     2394.4    14366.6       5.5270       3.6971         2.3029   100.00
    8.0     1795.8    14366.6       6.3530       5.6045         2.3955   100.00   better
   10.0     1436.7    14366.6       6.8510       7.4720         2.5280   100.00   better
   12.0     1197.2    14366.6       7.1850       9.3015         2.6985    99.94   better
  ---- broken arms, VERDICT ONLY, margins not quotable (rule 4) ----------------------
   15.0      957.8    14366.6       7.5210            —              —    20.11
   25.0      574.7    14366.6       8.0710            —              —    11.65
```

**2.30 → 2.70° over a 2× window, monotonically better, every row with the track intact.** The identity
itself is confirmed to the digit (`R·fov` constant at 14366.6 m·deg = 80789 · 0.001^¼,
which is slice 46's constant carried down the RCS ladder). But **the margin improves monotonically:
widening the window is still the cure for the angle.** ⭐ **THE REASON IS A SATURATION, and it is the
transferable part: `t_lock` cannot grow past the CPA.** Over the admissible 2× window the lock time
moves only 5.53 → 7.19 s against a hard 8.9 s ceiling, so the accumulated error grows barely faster
than the window that must contain it (`err/fov` walks 0.616 → 0.700 → 0.747 → 0.775 and *asymptotes*
rather than crossing 1.0 — the broken rows continue the same asymptote to 0.81, which is why they add
nothing the admissible rows do not already say). ⇒ **A FEEDBACK LOOP THROUGH A SATURATING VARIABLE IS
NOT A FEEDBACK LOOP.** Write the squeeze down as refuted; do not ship it as a law.

### §4.4 P6 — THE COST DOES NOT VANISH, IT MOVES (2026-08-19) ⚠ **AND P6's ERROR ARM IS CONFOUNDED**

⚠⚠ **FIRST, THE METHOD CATCH, BECAUSE IT INVALIDATES HALF OF THIS PROBE'S OWN OUTPUT.** P1's
perturbation changes the target's TRUE velocity, which is fine for a purely geometric quantity
(measured at one instant, from one flown missile position) but **NOT fine for anything that depends on
the closing engagement**: a target misestimated as 15 % *faster* really is faster, so it enters the
horizon EARLIER and the missile locks with MORE authority left, not less. The tell is that the error
arm outperforms its own control (authority 15.79 % against 23.55 % at fov 10). ⇒ **P6's error-arm
authority column is NOT QUOTABLE**, and the general form is worth carrying: **a probe that perturbs
the TRUTH to emulate a wrong BELIEF is clean only for quantities read at a single instant; anything
integrated over the approach is measuring a different engagement.** A belief that is wrong *while the
truth is fixed* cannot be probed on this wire at all, because the wire has no belief — building one
is what the slice is for.

**SECOND, THE CONTROL ARM (P6b), WHICH IS CLEAN — one target, one picture, only `fov` varying:**

```
fov deg    R_acq m  lock tick   authority %    hold %      CPA m
    6.0     2394.4       5604          8.55    100.00      2.610
   10.0     1436.7       6956         23.55     99.90      2.998
   15.0      957.8       7647        100.00     17.25    159.457
   25.0      574.7       8235        100.00      6.90    271.866
```

⭐⭐ **WIDENING THE WINDOW IS CATASTROPHIC EVEN WITH A PERFECT PICTURE, AND THE ANGLE GATE NEVER SEES
IT COMING.** Over the same 6 → 25° sweep where P5's angle margin *improved* from 2.30° to 4.73°, the
airframe goes 8.55 % → PINNED, the track collapses 100 % → 6.90 %, and the CPA opens 2.6 m → 271.9 m.
**Both columns are read on the same runs.** This is slice 46's law re-measured on the `fov` axis
instead of the RCS axis, and it settles what replaces §0.1's refuted squeeze:

> ⭐⭐⭐ **THE HEADLINE THAT SURVIVES P5. A wider window does buy tolerance to a bad handover — and it
> is never the right way to buy it, because the reach it sells is what the airframe was going to spend
> on the intercept. ⇒ THE MIDCOURSE'S JOB IS NOT TO WIDEN THE WINDOW BUT TO KEEP THE ERROR SMALL
> ENOUGH THAT NOBODY HAS TO.** The angle margin says "wider is better" over the exact interval where
> the engagement is being lost — which is §0.5 rule 1 (miss is not the gauge) recurring one level up:
> **`gimbal_fov_margin_deg` is not the gauge either.**

### §4.5 GATE-0 VERDICT, AND WHAT §1 MUST DO

- **P0 ✓** the gap is real and is worse than the backlog said. **P2 ✓** a third freebie, deferred as
  physics not showcase. **P1 ✓ THE BLOCKING PROBE PASSES** — defensible, linear, monotone.
  **P5 ✗ REFUTED** — the squeeze is prose. **P6 ✓/⚠** — the cost transfers to authority, on a clean
  control; the error arm is confounded and not quotable.
- ⚠ **A STRUCTURAL FINDING FOR §1, FOUND WHILE BUILDING P1's CLEAN ARM AND NOT YET DISCHARGED: THE
  LAUNCH STATE IS CONFINED TO THE x–z PLANE.** `scenario.jl:350` builds `e.vel` from
  `speed`/`elevation_deg` with an explicit `0.0` cross-range component, and `missile.jl:439` mints
  `:att_q` from `atan(e.vel[3], e.vel[1])` — **pitch only, `e.vel[2]` unread.** So a missile cannot
  today be launched on a heading with any azimuth at all, and a midcourse that steers in azimuth must
  open that seam or be born with an instant sideslip. ⚠ Check it against the `speed`(19) /
  launch-altitude(21) class before touching it: an initial condition consumed once at load is
  legitimate, but an attitude init that silently drops a velocity component is the other thing.
- ⚠ **P3 IS NOT YET RUN, AND P1's OWN TABLE PREDICTS IT ANSWERS NO.** Slice 36's
  `gimbal_handover_err_deg` is a **STATIC tick-1 BIRTH OFFSET** (`missile.jl:1999`, consumed once, in
  the `!seek_init` branch). The belief error P1 measured **GROWS THROUGH THE BLIND PHASE** — 0 → 280 →
  676 m of PIP error, i.e. a RAMP whose value at the lock instant is the whole point. **A constant
  cannot express a ramp**, so driving 36's key would freeze the error at its launch value, which is
  zero. ⇒ ⭐ **that, and not the frame mismatch, is the reason to mint a second quantity** — it is a
  statement about the two things being different physics rather than about bookkeeping. ⚠ MEASURE it
  before writing it down; it is a prediction from a table, not a probe result.
