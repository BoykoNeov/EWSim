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
