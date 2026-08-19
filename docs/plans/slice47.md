# Slice 47 — THE MIDCOURSE PHASE (what a blind missile flies on, and what a wrong picture costs)

**Status: GATES 0, 1 AND 2 — RUN AND CLOSED (2026-08-19). GATE 3 (the showcase) IS NEXT — its
inherited constraints are §6.8. Suite green at 9254 tests.**

⭐ **The design fork is decided — THE SEEKER HEAD IS CUED ON THE MISSILE'S BELIEF, not on truth**
(user, 2026-08-19: *“we are attempting to be closer to reality”*). Seven probes ran; **P1 (blocking)
PASSED**, **P5 REFUTED this plan's own proposed headline**, and **P7 discharged the azimuth seam**.
⚠ **Read §4 before §1** — two things written in §0 are corrected there by measurement.

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
| **P6** | Where does the cost GO if the squeeze does not close? | added after P5 fell. ⚠ **Its ERROR arm is CONFOUNDED and not quotable** (§4.4); the fov control arm (P6b) is clean and carries the replacement headline. |
| **P7** ⭐ | Can the missile steer OUT OF ITS LAUNCH PLANE at all? (raised by the advisor once the BELIEF branch was chosen: P1's error axis is cross-range ⇒ the midcourse steers in AZIMUTH, and `scenario.jl:350` forces `vel[2] = 0`) | **If cross-range does not develop, or sideslip diverges, or the resultant incidence pins — §1 MUST OPEN THE LAUNCH-HEADING SEAM FIRST**, which is a different and larger slice. **RUN, PASSED** (§4.6): branch (a), the seam is a note. |

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

⭐ **THE FORK IS DECIDED (user, 2026-08-19): "we are attempting to be closer to reality" ⇒ THE HEAD
IS CUED ON THE BELIEF.** §4.1's table is resolved on its first row. That decision is what makes this
one slice with one lesson rather than two freebies priced together: **the midcourse computes where
the target will be, it flies there, AND it points the head there — one picture, one quality figure,
one thing to be wrong about.** Everything below assumes it.

⚠ Pure means `core/src/guidance.jl`-class: no `w.rng`, no `World`, no `Entity`, no telemetry
(convention 12). Everything here is a function of numbers and `Vec3`s, and every one of them is
testable in `runtests.jl` with an INDEPENDENT recompute (convention 11).

### §1.1 The three primitives

1. **`intercept_time(p_rel, v_rel, V_m)`** — the constant-velocity closed form: the smallest
   positive root of `‖p_rel + v_rel·t‖ = V_m·t`, i.e. the quadratic
   `(‖v_rel‖² − V_m²)t² + 2(p_rel·v_rel)t + ‖p_rel‖² = 0`. ⚠ It has **three** degenerate cases and
   each needs a defined, finite, non-throwing answer (conventions 5/6): no positive root (the target
   outruns the missile), a near-zero leading coefficient (co-speed — the quadratic degenerates to
   linear), and a negative discriminant. **A `NaN` here reaches JSON.**
2. **`predicted_intercept_point(p_m, p_t, v_t, V_m)`** → `(pip::Vec3, t_go::Float64)` — dead-reckon
   the target straight-line to `intercept_time` and return where it will be. **This IS the belief**:
   the midcourse's entire picture of the future is one point and one time.
3. **`midcourse_accel(p_m, v_m, pip; k, a_max)`** — the lateral command that flies the missile at
   the PIP. ⭐ **Take the SIMPLEST law that is honestly a midcourse: steer the velocity vector onto
   the line-of-sight to the PIP** — `a = k·V·(û_pip − v̂)⊥`, a pure attitude-pursuit of a fixed
   point, clamped through the SHIPPED `clamp_accel`. It is deliberately NOT PN: PN needs a LOS rate
   and the whole premise is that there is no seeker.

### §1.2 ⚠⚠ THE SLICE-39 CHECK, RUN BEFORE ANY OF THIS IS WRITTEN

*"A reparameterization must not ship as an ARCHITECTURE."* The obvious failure mode: **is "fly at a
predicted intercept point" just PN against a displaced virtual target?** Answer it in a gate-0-style
reduction probe (`p8_reduction.jl`), not in prose. The expected answer is **no, and for a reason
that is the slice's content**: PN's command is `N·Vc·(ω×û)` — it is driven by a LOS **rate**, which
a blind missile does not have and cannot have. Pursuit of a fixed point is driven by an **angle**.
⚠ **If the probe shows the two are algebraically the same on this wire, say so and ship the small
thing** — a `:midcourse` guidance arm that is PN against a virtual target, three lines, no
architecture.

### §1.3 The belief's ERROR is an AUTHORED, DETERMINISTIC PERTURBATION

⚠ **§0.5 rule 3 is absolute: NO PER-TICK RNG DRAW.** The launch-time picture is wrong by a **signed
authored constant**, applied ONCE at launch and then dead-reckoned:

```
    belief_t(0) = truth_t(0) + Δp        Δp = :midcourse_pos_err_m   (Vec3, authored, default 0)
    belief_v(0) = truth_v(0) + Δv        Δv = :midcourse_vel_err_mps (Vec3, authored, default 0)
```

⭐ **AND THE SLIDER IS `Δv`, NOT `Δp`, FOR A MEASURED REASON**: P1 showed the handover error is the
angle between where the target IS and where the picture SAID — an error that **GROWS through the
blind phase** because it is a velocity error integrating. A position error is a constant offset that
the closing geometry mostly eats. ⚠ **P4 (monotonicity over the domain) is re-run on the COMMANDED
trajectory at gate 2** — P1's linearity was measured ballistic and does not transfer for free (§4.2).

### §1.4 ⚠⚠ P9 — THE SECOND GATE-1 PROBE, AND IT DECIDES §3.3's DEFAULT CELL

**§2.5 check 2 and §3.3 cannot both be casually true on the same wire (advisor), and the tension is
real physics rather than a drafting slip.** §3.3 demands a geometry where **doing nothing is wrong**,
pinned by a third arm (midcourse absent) that must MISS. §2.5 check 2 asserts the `Δv = 0` arm still
closes to `cpa < 3 m`. But slice 46's wire hits at **2.998 m BALLISTICALLY** — so breaking the
free ride means authoring a **new geometry**, and on that geometry the perfect midcourse must fly a
**substantial** correction. **Whether a `k·V·(û_pip − v̂)⊥` pursuit converges to a few metres there is
UNMEASURED.**

⇒ **`p9_null.jl`, at gate 1, before §3.3's default cell is fixed:** on a candidate geometry where
ballistic misses, does the **zero-error** midcourse close to a few metres, and at what `midcourse_k`?

| outcome | what it means |
|---|---|
| closes at the authored `k` | §3.3's three arms all stand; write the scenario |
| closes only after tuning `k` | **learn it HERE, not at gate 2** — and `k` becomes an authored number with a measured justification rather than a guess |
| does not close at any `k` | ⚠ **pursuit of a fixed point is the wrong law for this geometry** and §1.1's item 3 must change — cheap now, expensive after gate 2 |

⚠ **Do not carry this to gate 2.** It is one probe on the shipped wire with an authored target
displacement, and it is the difference between a showcase with three arms that mean something and
one whose null arm hits for a reason nobody measured.

### §1.5 Tests (`core/test/test_midcourse.jl`, new file, added to `runtests.jl`)

- **`intercept_time` against an INDEPENDENT recompute** — construct `(p_rel, v_rel, V_m)` from a
  KNOWN answer (pick `t*`, place the target so the root is exactly `t*`), assert to `atol = 1e-9`.
  Then the three degenerate cases assert **finite, defined, non-throwing** — never a value.
- **The zero-error identity** — `Δp = Δv = 0` ⇒ the PIP is the true intercept point ⇒ `midcourse_accel`
  points along the true collision course ⇒ **its lateral component is 0 to `atol`.** ⭐ This is the
  slice-19 tripwire in its strongest form and it is also the null the showcase opens on.
- **The sign test** — a target believed to be crossing FASTER must be led FURTHER. Assert the sign of
  the lateral command against the sign of `Δv`, in the inertial frame, both directions. ⚠ Units /
  frames / signs are the bug trifecta.
- **`clamp_accel` reuse** — assert the command is the SHIPPED clamp, not a second implementation.

---

## §2 — GATE 2: THE WIRE

### §2.1 The guidance arm — `missile.jl:1187`

A new `elseif` in the guidance chain, **with every existing arm textually verbatim** (§0.3 rule 1).
⚠ **Never `a_dem + a_midcourse`.** The gate is **key presence AND the seeker never having locked**:

```julia
elseif guid === :pn && haskey(c, :midcourse) && !get(c, :seek_init, false)
    midcourse_accel(e.pos, e.vel, predicted_intercept_point(e.pos, belief_p, belief_v, ‖e.vel‖)…)
```

⚠⚠ **THE GATE IS THE AUTHORED ANCHOR `:midcourse`, AND *NOT* A COMPUTED KEY LIKE `:midcourse_pip`
(advisor).** A PIP is something the missile *works out*, so `haskey(c, :midcourse_pip)` would be true
on every wire the moment the arm exists — **a tautology, which is the exact failure `:seeker_omega`
already demonstrates at this very line** (§0/P0: written unconditionally, so its `haskey` guard gates
nothing). Presence gates must test a key **a scenario author wrote and a slice 11–46 wire did not.**

**WHERE THE BELIEF LIVES, AND IN WHICH PHASE — the load-bearing detail:**

1. **The launch snapshot is minted ONCE, lazily, on the first tick** (`:midcourse_p0`, `:midcourse_v0`,
   `:midcourse_t0`) from the truth plus the authored `Δp`/`Δv` — **the `:att_q` lazy-init shape at
   `missile.jl:439`**, which survives reset via reload.
2. **The believed target position is a PURE DEAD-RECKON of that snapshot** —
   `belief_p(t) = p₀ + v₀·(t − t₀)` — so it is computable **in place, in whichever phase needs it,
   with no cross-phase dependency at all.** ⭐ That is what makes the cue clean: the head's cue
   direction is formed in **phase 3** (`observe!`) and the guidance command in **phase 4** (`decide!`)
   **from the same three stored numbers**, not from each other. No ordering hazard, and no repeat of
   convention 8's telemetry-phase gotcha.
3. **The PIP is recomputed EVERY TICK inside the arm**, never stored-and-reused: the missile is
   moving, so the intercept solution moves with it. `:midcourse_pip` exists **only as telemetry** (the
   client draws the belief point — convention 13, zero physics in GDScript).

⚠⚠ **THE ORDER OF THE CHAIN IS ITSELF A DECISION.** The new arm must sit **before** the
`haskey(c, :seeker_omega)` arm, because that arm is taken on **every tick of every seeker wire**
(§0/P0) and would shadow this one entirely. Putting it first and gating it on `!seek_init` is what
makes the handover a HANDOVER: midcourse until the tracker initialises, PN after, one switch, one
tick. ⚠ **Pin the switch tick in a test** — an off-by-one there is a whole tick of the wrong law at
the moment the slice is about.

### §2.2 ⚠⚠ THE CUE ARM IS THE RISKIEST EDIT IN THE SLICE, AND IT IS NOT A NEW ARM

`missile.jl:2437` writes `:head_tgt_az` / `:head_tgt_el` **UNCONDITIONALLY under `_gim`** from the
measured (truth-derived) angles, and **slice 46's whole detection horizon reads through them.**
Belief-cueing means gating an EXISTING unconditional write that a shipped slice depends on — which
is a different and harder thing than adding a gated arm, and the ABSOLUTE GOLDEN is the check that
catches a mistake here (§0.3 rule 3, convention 2).

⭐⭐ **AND P2 EXPOSED THE ACTUAL FREEBIE, WHICH IS SHARPER THAN "THE HEAD SEES TRUTH".** The slew is
gated at `:2103` / `:2129` on `off_axis_angle(head_az, head_el, look_az_b, look_el_b) ≤ fov_h` — the
**angular** window alone. `look_az_b` comes from `û_tru` (`:1879`). But `_detectable` (`:2413`,
slice 46's link budget) gates only the **measurement**. ⇒ **the head today slews on an error signal
for which there is no detection** — it tracks an echo the receiver cannot hear. That is not a
missing feature, it is the cue and the track being the same code path.

**The fix is a MODE, and it is small:**

| while… | the head is… | its slew target is… |
|---|---|---|
| **not detectable** (slice 46's gate open) | **CUED** — open-loop, no window gate, because a cue is a command and not an error signal | the **BELIEF** LOS, in body angles via the shipped `look_angles` |
| **detectable** | **TRACKING** — discipline 3's two-evaluation gate, VERBATIM | the measurement, `:2437` VERBATIM |

⭐ **THIS GIVES STRUCTURAL BYTE-IDENTITY FOR FREE, AND IT IS THE GOOD KIND — the arm is UNREACHABLE
on a wire without slice 46's rung.** With `detect_pt_w` absent, `_detectable ≡ true` (`:2415` else),
so cue mode never runs and slices 11–45 are byte-identical **by construction**, not by a zero that
cancels.

⚠ **THE ORDERING CONSTRAINT IS REAL AND MUST NOT BE PAPERED OVER.** `_detectable` is computed at
`:2413`; the slew runs at `:2103`, ~300 lines earlier. ⇒ the MODE is stored beside `:head_tgt_*` at
`:2437` and consumed by the NEXT tick's slew — **the same one-tick seam discipline the servo already
lives under** (discipline 2: the servo tracks the one-tick-delayed stored pair). Do not recompute
detectability at `:2103`: that is a SECOND IMPLEMENTATION of the gate, the exact trap this file names
for `off_axis_angle`.

### §2.3 P3's ANSWER — A SECOND QUANTITY, AND THE REASON IS PHYSICS NOT BOOKKEEPING

**Slice 36's `gimbal_handover_err_deg` MUST NOT be driven** (§4.5): it is a **STATIC tick-1 BIRTH
OFFSET** consumed once in the `!seek_init` branch at `missile.jl:1999`. The belief error is a **RAMP**
whose value AT THE LOCK INSTANT is the whole point (0 → 280 → 676 m of PIP error, §4.2). **A constant
cannot express a ramp**, so driving 36's key would freeze the error at its launch value, which is
zero. ⇒ the two coexist and are different physics: 36 asks *"what if the head is born pointing
wrong?"*, 47 asks *"what if the missile has flown to the wrong place?"* ⚠ 36's `:stabilized` load
refusal is inherited untouched — do not quietly widen it.

### §2.4 The keys, and what refuses what at load

| key | frame / units | default | validated |
|---|---|---|---|
| `midcourse: true` (or the law name) | — | absent ⇒ **no arm at all** | the ANCHOR: the loader refuses the error keys without it |
| `midcourse_vel_err_mps` | inertial, m/s, `Vec3` | `[0,0,0]` | finite |
| `midcourse_pos_err_m` | inertial, m, `Vec3` | `[0,0,0]` | finite |
| `midcourse_k` | — | authored, NEVER a knob | `> 0` |

⚠ **`a_max` is REUSED, never a second ceiling** (the slice-19 FINDING-14 shape): a midcourse that can
pull more than the airframe is a lie the airframe pays for at handover.
⚠ **CLAMP AT THE CONSUMER for anything live, VALIDATE AT LOAD for anything authored** (convention 5).

### §2.5 The gate-2 checks

1. **ABSOLUTE GOLDEN, both directions** — keys absent ⇒ byte-identical to slice 46; and the
   `detect_pt_w`-absent wire ⇒ cue mode provably unreachable.
2. **THE ZERO-ERROR NULL IS NOT BYTE-IDENTITY AND MUST NOT BE ASSERTED AS SUCH.** With `Δv = 0` the
   midcourse still COMMANDS (a small correction of the launch heading); §0.1 measured that
   perfect-midcourse ≈ ballistic ≈ hits, which is a metres-level agreement, not a bit-level one.
   Assert **`cpa < 3 m` and `max |a_cmd|` while blind small**, never `dtraj == 0`.
3. **The switch tick**, pinned (§2.1).
4. **P4 RE-RUN ON THE COMMANDED TRAJECTORY** — P1's 0.4970 °/% is provisional (§4.2). The gate-2
   number is the one gate 3 quotes. ⚠ **AND THE RE-RUN ALSO RECORDS THE PEAK BLIND-PHASE `a_cmd`
   ACROSS THE WHOLE SLIDER DOMAIN, CHECKED AGAINST P7's CLEAN BRACKET** (advisor): P7 measured the
   out-of-plane seam clean for injected rates `≲ 0.002 rad/s`, i.e. 96–191 m of blind-phase
   cross-range, and *absurd* above it (473 m of displacement before the seeker even opens ⇒ a 163 m
   miss). **A slider whose top end PINS THE AIRFRAME BEFORE LOCK is a different slice** — the lesson
   is a bad handover, not a midcourse that flew itself into saturation.
5. **The slice-19 tripwire** — a test asserting **each** authored key MOVES a measured quantity.
   ⚠ This is the MODEL test, and it is the only outright kill available (§0.7).

---

## §3 — GATE 3: THE SHOWCASE

**`scenarios/slice47_midcourse.yaml`, `net/slice47_verify.gd`, `net/slice47_ui_test.gd`.**

### §3.1 The lesson, and the one slider

> **HOW GOOD DOES THE LAUNCH-TIME PICTURE HAVE TO BE?** A missile that cannot see its target flies on
> what it was told at launch. Being told wrong costs nothing until the seeker opens its eyes — and
> then it is paid all at once, in the one place the missile cannot get more of.

**The slider is the midcourse velocity error**, quoted in **METRES of predicted-intercept-point error
at the lock range**, not in per cent (§4.2: a percentage is a fraction of *this* target's speed and is
scenario-specific; metres is the currency a midcourse is specified in).

### §3.2 The headline columns — and the two gauges that are FORBIDDEN

| column | why |
|---|---|
| **handover error at lock (deg)** vs the window | the direct output of the midcourse |
| **peak `a_cmd` after lock, % of `a_max`, GATED `r > 200 m`** | slice 46's currency; §0.5 rule 2 — never quote the ungated figure |
| **hold %** | the acquisition verdict, and the only honest column on a broken arm (§0.5 rule 4) |

⚠⚠ **MISS IS FORBIDDEN AS THE GAUGE** (§0.5 rule 1 — killed twice). ⚠⚠ **AND SO IS
`gimbal_fov_margin_deg`**, which is §4.4's new finding one level up: over the exact interval where
P6b loses the engagement (authority 8.55 % → PINNED, hold 100 % → 6.90 %, CPA 2.6 → 271.9 m), the
angle margin *improves* monotonically. **A gauge that reads "better" while the engagement is lost is
not a gauge.**

### §3.3 The scenario, and the ONE thing it must not inherit

⚠⚠ **THE FREE RIDE IS AUTHORED (§0) AND THIS SCENARIO MUST NOT RE-AUTHOR IT.** Slice 46's target is
authored INTO the missile's ballistic plane, so doing nothing is right. Slice 47's default cell must
be one where **doing nothing is wrong**: the null arm (`Δv = 0`) hits because the midcourse FLIES,
not because the launch heading happened to be the answer. ⭐ **Pin that with a third arm — midcourse
absent — which must MISS.** Without it the showcase measures nothing, which is how slices 44 and 45
died.

⚠ The blind phase is reached by **SHRINKING THE TARGET** (`rcs_m2`), never by lengthening the launch
range — slice 44 §V measured that an unpowered missile at 3000 m falls into the ground before it
flies 20 km (§0.2). Inherit slice 46's `rcs_m2 = 0.001` default: 6955 blind ticks, `R_acq` 1436.7 m.

⚠ **ONE LIVE KNOB beside ONE fidelity button** (the 32/34/37/40/46 shape, convention 9).

### §3.4 The four proofs (convention 14) and the traps that have cost real hours

**verifier · UI test · headless smoke-load · windowed shot.** ⚠ `STEPS` **must** be a multiple of
`emit_every` (else a SILENT hang). ⚠ `%g` / `%.2e` are not GDScript specifiers and one bad one kills
the whole `%` silently. ⚠⚠ **The HUD width budget is INHERITED (55 body / 30 headline) and asserted
in PIXELS** — slice 46's 100/96-CHAR tooth passed GREEN while every line clipped at 1152 **and**
1920 px. ⚠ A rung that stops EMITTING makes the client's `.get(k, 0.0)` print a **defaulted zero as
a passed test** — the cue-mode keys must emit on every tick of both modes or not exist. ⚠ Anything
computed inside `_draw` has NO headless proof. ⚠ **The Godot client is pure — ZERO physics**
(convention 13): the belief point is DRAWN from telemetry, never dead-reckoned in GDScript.

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
| ⭐ **the BELIEF** — **CHOSEN** | **ANGLE** — P1's axis is live, linear, ~0.50 °/%, past the window at 280 m of PIP error | fixing the cue is **IN SCOPE**, not deferred. ⚠ P1's table establishes the axis is live, defensible and monotone; **its COEFFICIENT is PROVISIONAL and is re-measured at gate 2 on the COMMANDED trajectory** (§4.2) |
| **TRUTH** (today, unchanged) — **NOT TAKEN** | **AUTHORITY and GEOMETRY only** — the angle gate never sees it | P1's 20.5 % would be **NOT this slice's number**, and the cost would have to be measured without P6's confound (§4.4) |

> ⭐⭐ **DECIDED, 2026-08-19, BY THE USER: "we are attempting to be closer to reality" ⇒ THE BELIEF.**
> A real seeker head is cued by whatever told the missile where to look, and on a blind missile that
> is the midcourse, not omniscience. The cue and the guidance become ONE component with ONE authored
> quality figure, which is also how convention 9 is satisfied — one lesson (*how good does the
> launch-time picture have to be?*) rather than two freebies priced in one scenario. §§1–3 are
> written on this branch; the truth branch is closed.

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
⚠⚠ **AND THE COEFFICIENT IS PROVISIONAL, WHICH THE PARAGRAPH ABOVE ALREADY IMPLIES AND THIS LINE
MAKES EXPLICIT (advisor).** P1 sampled the handover geometry along the **BALLISTIC** trajectory — the
one the missile flies when it commands nothing (P0). Once a belief-cued midcourse commands toward a
WRONG predicted intercept point, the missile actively flies the wrong way, so the geometry at lock is
**not** the geometry P1 sampled. ⇒ **the 0.4970 °/% is an order of magnitude and a SIGN, not the
headline number.** What P1 establishes — and it is what the blocking probe was for — is that the axis
is **live, defensible and monotone**. The number gate 3 quotes is re-measured at gate 2 on the
commanded trajectory (§2.5 check 4).
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

### §4.6 P7 — **THE AZIMUTH SEAM IS NOT A BLOCKER, AND THE SHIPPED WIRE ALREADY FLIES IT** (2026-08-19)

⚠ **THIS PROBE WAS RUN BECAUSE THE FORK WAS DECIDED (§4.1), AND CHOOSING THE BELIEF PROMOTED §4.5's
"structural finding" INTO GATE 1's PRECONDITION** (advisor). P1's entire error axis is **cross-range**
— it was produced by perturbing the target's crossing speed — so **a midcourse that corrects it steers
in AZIMUTH**, and the launch state has an explicit `0.0` cross-range velocity with `:att_q` minted
from pitch alone. Two very different §1s hang on that: an ordinary lateral-acceleration midcourse, or
a slice that must first open the launch-heading seam.

**METHOD — no core patch, and the injection is at the honest seam.** `p7_azimuth.jl` appends a probe
`Subsystem` to `sc.subs`; its `observe!` therefore runs **after** the seeker's (`subsystem.jl`: fixed
phase order, list order within a phase) and overwrites `:seeker_omega` **while `!seek_init`**. PN then
makes a real command through the real chain — `pn_accel_from_omega` → `clamp_accel` →
`steering_command` → `alpha_autopilot_delta` (both fins) → `_integrate_6dof!`. While never-locked
`:seeker_los` is `los_unit_from_angles(0,0) = (1,0,0)`, so an injected `ω` about `+ẑ` gives
`a = N·Vc·(ω×û) = (0, N·Vc·ω_z, 0)` — **pure cross-range.** That is the seam exercised, which is all
this probe needs; it is not the law.

**SOUNDNESS FIRST** — the injection-absent arm is bit-identical to the raw wire:

```
dtraj(raw, subsystem-installed-but-wz=0) = 0.00e+00   lock 6956 vs 6956   cpa 2.9976 vs 2.9976
```

**P7.1 — IT TURNS OUT OF PLANE CLEANLY** (`α_max` = 0.30 rad = 17.19° is the RESULTANT
`hypot(α,β)` ceiling, slice 23):

```
 wz rad/s     lock t    y @lock     vy @lock    max|al|    max|be|    max res     aero     defl     cpa m
   0.0000     6.9560       0.00        0.000     8.7081     9.5764    12.7744     1235        0     2.998
   0.0010     6.9040      96.52       28.618    11.4856     4.1225    12.1850      561        0     2.304
   0.0020     6.8640     191.31       57.122    11.3254     4.3939    12.1467      542        0     2.730
   0.0050     6.8180     472.75      141.258    10.4262    12.1651    12.7449     7143        0   162.612
   0.0100     7.0420     990.00      273.247     0.1658     2.2917     2.2961        0        0  1167.745
   0.0200    14.0000    4058.23      129.985     0.2008     4.5705     4.5728        0        0  2079.682
```

⭐ Cross-range develops **linearly in the injected rate** over the small-command domain (96.5 / 191.3
m at lock for 0.001 / 0.002), the resultant incidence never approaches `α_max`, and **`defl_sat` is 0
on every single arm** — the fin limit never binds. The `α`/`β` columns on the small arms are the
**post-lock endgame**, not the blind phase (the `wz = 0` control shows the same 8.7 / 9.6°, and its
blind phase is uncommanded by P0). ⚠ `wz ≥ 0.005` is an **absurd** midcourse — 473 m of cross-range
before the seeker even opens — and it misses by 163 m and then 1168 m; the usable domain is
`wz ≲ 0.002`, which conveniently brackets the 96–191 m of blind-phase displacement a real midcourse
correction is worth.

**P7.2 — AND THE SHIPPED WIRE ALREADY DOES THIS, WHICH IS THE STRONGEST FORM OF THE ANSWER.** At
`rcs_m2 = 1.0` slice 46's horizon (8078.9 m) exceeds the 6436.7 m launch range, so the seeker locks
at **tick 1** and PN commands cross-range from the start against a target authored at `y = +2000`:

```
lock tick 1   max|alpha| 0.7490 deg   max|beta| 0.8340 deg   max resultant 0.8344 deg
aero_sat 0   defl_sat 0   cpa 2.3824 m
   tick        t            y           vy      alpha       beta    |a_cmd|
   1000    1.000         5.73       12.957     0.1149     0.6999      25.58
   4000    4.000        81.15       31.251     0.6468     0.0606      15.02
   8000    8.000       204.58       29.185     0.7217    -0.0480      46.54
```

⭐⭐ **THE MISSILE LEAVES ITS LAUNCH PLANE ON THE TOP ROW OF SLICE 46's OWN LADDER, hits at 2.38 m,
and never saturates anything.** The in-plane birth is an **initial condition**, not a constraint.

**P7.3 — THE NOSE FOLLOWS THE FLOWN VELOCITY: SIDESLIP TRIMS, IT DOES NOT RAMP.** Under a *constant*
injected command the sideslip holds flat for five seconds and then unwinds smoothly through the
handover:

```
   tick        t            y           vy   beta deg    |a_cmd|
   1000    1.000        15.15       35.422     2.2516      58.86
   3000    3.000       172.07      121.388     2.2908      59.80
   5000    5.000       498.42      203.815     2.1865      57.77
   7042    7.042       990.00      273.247     1.4940      37.55   <- LOCK
  10000   10.000      1822.05      259.321    -1.7367      48.45
  14000   14.000      2579.25      113.339    -2.1995      54.93
```

**A trim value, not a divergence.** None of the four pre-registered falsifiers fires.

> ⭐⭐⭐ **VERDICT: BRANCH (a). §1 IS AN ORDINARY LATERAL-ACCELERATION MIDCOURSE AND THE SEAM IS A
> NOTE, NOT A SLICE.** The 6-DOF plant has a full yaw channel (`af_cy_beta`, `I_zz`, `delta_yaw_cmd`)
> and `steering_command` resolves a full 3-D demand onto **two** body axes with no
> projection-and-discard — slice 23's "the discard dies" — so an azimuth-steering midcourse is
> already-flown physics on this exact wire.

⚠ **WHAT SURVIVES AS A NAMED DEFERRAL, AND IT IS A LATENT GAP RATHER THAN A BUG.** `missile.jl:439`
minting `:att_q` from `atan(vel[3], vel[1])` is **consistent today** precisely because
`scenario.jl:350` forces `vel[2] = 0` — nose along velocity, `α = β = 0` at launch, which is the
correct initial condition. It becomes a **wrong number the moment a launch-AZIMUTH key is authored**,
because the attitude would then be minted from a velocity component it silently drops. ⇒ **file it
beside the launch-altitude(21) MODEL GAP: a seam reserved and not yet opened, with the tripwire being
that whoever adds `azimuth_deg` to `scenario.jl` must fix `:att_q` in the same commit.** Slice 47 does
**not** need it — the midcourse steers, it does not launch crooked.

### §4.7 GATE-0 VERDICT — **GATE 0 IS CLOSED. §§1–3 ARE WRITTEN.**

- **P0 ✓** the gap is real and is worse than the backlog said — the blind missile is BALLISTIC.
  **P2 ✓** a third freebie, and it turned out to be the slice's **central design fork** rather than a
  footnote. **P1 ✓ THE BLOCKING PROBE PASSES** — defensible (280 m of PIP error), linear, monotone;
  ⚠ its COEFFICIENT is provisional (§4.2). **P5 ✗ REFUTED** — the three-way squeeze is prose, because
  `t_lock` saturates against the CPA: **a feedback loop through a saturating variable is not a
  feedback loop.** **P6 ✓/⚠** — the cost transfers to AUTHORITY, on a clean control; the error arm is
  confounded and not quotable. **P7 ✓** — the azimuth seam is **not** a blocker, branch (a) (§4.6).
- ⭐ **THE FORK IS DECIDED (§4.1): THE HEAD IS CUED ON THE BELIEF.** §§1–3 are written on that branch.
- ⚠ **THE x–z-PLANE LAUNCH FINDING IS DISCHARGED BY P7** and demoted to a **named latent gap**: the
  attitude init is consistent today because the loader forces `vel[2] = 0`, and becomes wrong only if
  a launch-azimuth key is ever authored (§4.6, closing paragraph). It is **not** slice 47 work.
- ⚠ **P3 IS ANSWERED FROM THE CODE, NOT FROM A PROBE, AND THAT IS THE RIGHT CALL (advisor).** Slice
  36's `gimbal_handover_err_deg` is a **STATIC tick-1 BIRTH OFFSET** — `missile.jl:1999`, consumed
  once, inside the `!seek_init` branch, read from a key that is never re-read. The belief error
  **GROWS THROUGH THE BLIND PHASE** (0 → 280 → 676 m of PIP error, §4.2): a **RAMP** whose value AT
  THE LOCK INSTANT is the whole point. **A constant cannot express a ramp**, so driving 36's key would
  freeze the error at its launch value, which is zero. ⇒ ⭐ **a second quantity, and the reason is
  that the two are different physics** — 36 asks *"what if the head is born pointing wrong?"*, 47 asks
  *"what if the missile has flown to the wrong place?"* — **not** that their frames disagree. This is
  a mechanism argument from lines already read, not a prediction awaiting measurement; §2.3 carries it.
- ⚠ **WHAT GATE 1 STILL OWES A PROBE:** the slice-39 reduction check (§1.2) — *is pursuit of a
  predicted intercept point just PN against a displaced virtual target?* That one is cheap, it is
  pre-registered, and it is the only remaining way this slice ships an architecture where three lines
  would do.

---

## §5 — GATE 1: THE LOG

### §5.1 P8 — **NOT A REPARAMETERIZED PN, AND PRIMITIVE 3 IS A SHIPPED KERNEL** (2026-08-19)

`p8_reduction.jl` (log: `p8log.txt`). The slice-39 check, run **before any of §1 was written**, and it
owes **two** answers rather than one (advisor): *is the midcourse a reparameterized PN?* and *is it
the shipped pursuit law?*

**P8.b FIRST, because a wrong answer there means everything else measures the wrong function.**

```
max |hand-written §1.1 expression − shipped pursuit_accel| over 2000 geometries: 0.000e+00 m/s²
```

⭐ **`k·V·(û_pip − v̂)⊥` IS `pursuit_accel(p_m, v_m, pip; k_guid = k)`, BIT-IDENTICALLY.** So §1.1
item 3 is a **clamp around a shipped kernel**, never a second implementation of one — there is
exactly one pursuit kernel in the core, and `test_midcourse.jl` carries that as a tooth.

**P8.a — vs PN, sampled along the shipped wire's flown trajectory** (convention 10: the wire is the
oracle, never a hand-recompute). `MID` = pursuit-to-PIP (⟂ the HEADING); `PNF` = PN against that same
PIP as a virtual target (⟂ the LINE OF SIGHT); `PNT` = the shipped truth PN, as a reference:

```
   tick    range m   t_go s  lead deg      |MID|      |PNF|  ∠(MID,PNF)  ∠(MID,PNT) |MID|/|PNF|
   1000     5710.9   7.7726    2.5964    94.8591    32.5113      2.5964     18.3555     2.9177
   2000     4986.5   6.7932    2.9644   108.0027    42.3394      2.9644     18.5383     2.5509
   3000     4264.0   5.8108    3.5849   130.2471    59.6554      3.5849     18.4289     2.1833
   4000     3543.8   4.8260    4.5392   164.4492    90.5836      4.5392     18.4474     1.8154
   5000     2826.2   3.8398    6.0079   216.9874   149.8649      6.0079     18.9895     1.4479
   6000     2112.3   2.8544    8.4469   303.8761   280.8095      8.4469     20.5657     1.0821
   7000     1405.4   1.8755   13.2287   472.4402   653.9217     13.2287     24.4074     0.7225
   8000      680.8   0.8934    3.3202   119.1963   355.1692      3.3202     14.6529     0.3356
```

⭐⭐ **`∠(MID,PNF)` EQUALS THE LEAD ANGLE TO FOUR DECIMALS ON EVERY ROW.** That is the determinant
argument measured on the wire rather than asserted in prose: writing `c = û·v̂`, pursuit commands
along `û − c·v̂` and PN along `c·û − v̂`, which are parallel iff `c² − 1 = 0` — only where the
pointing error is zero and **both commands vanish**. The two laws are perpendicular to *different*
vectors, and the angle between them **is** the pointing error itself.
⭐ **AND THE MAGNITUDES DO NOT SCALE TOGETHER: `|MID|/|PNF|` walks 2.9177 → 0.3356, a 48.5× spread
along ONE engagement**, because PN carries a `1/r` that pursuit does not. So a `k` tuned at one range
is wrong at every other, and no fixed `(k, N)` pair exists.

**P8.c — the one fit worth running** (advisor: one fixed virtual displacement + one fixed `N` for the
whole trajectory; a per-tick refit is not a reparameterization and was not run). Fitted at tick 1000
over `d ∈ [−3000, 3000] m` × `N ∈ [0.25, 40]`:

```
BEST FIT at tick 1000: d = +1450.0 m, N = 40.00  → residual 28.4976 m/s² (|MID| = 94.8591)
   tick        |MID|    |PN(d,N)|     residual resid/|MID|
   1000      94.8591      89.9262      28.4976      0.3004
   3000     130.2471     559.2354     443.8512      3.4078
   5000     216.9874    1809.1785    1645.2437      7.5822
   8000     119.1963    6617.2547    6567.0845     55.0947
```

**The fit cannot even close at the instant it is fitted** — a 30 % residual, with `N` pinned at the
grid's edge (itself the tell that no solution lies inside) — and it degrades to 55× downrange.

> ⭐⭐⭐ **VERDICT: the reduction FAILS, which is the good outcome.** Pursuit of a predicted intercept
> point is not PN against a displaced virtual target under any fixed reparameterization, so §1.2's
> "ship the small thing" branch does not fire and slice 39's discipline is satisfied. **But P8.b
> makes the ship small anyway, for a different reason: the new law is a CLAMP AROUND A KERNEL THE
> CORE ALREADY HAS.** The architecture added is three functions, one of which is one line.

### §5.2 P9 — **THE NULL CLOSES, AND THE `k` WINDOW IS BOUNDED AT BOTH ENDS** (2026-08-19)

`p9_null.jl` (log: `p9log.txt`). §1.4's probe: on a geometry where ballistic MISSES, does the
zero-error midcourse close to a few metres, and at what `midcourse_k`?

**METHOD — NO CORE PATCH, and it is P7's seam generalised from one axis to an arbitrary command.**
A probe `Subsystem` appended to `sc.subs` runs its `observe!` after the seeker's and, while
`!seek_init`, overwrites **both** `:seeker_omega` and `:seeker_los`. Since the shipped arm computes
`(N·Vc)·(ω × û)`, choosing `û := v̂` (the missile's own heading) and `ω := (v̂ × a_mid)/(N·Vc)` returns
`a_mid` **exactly** — a pursuit command is already ⟂ `v̂`. It then flows through the real chain:
`_terminal_cutoff` (a no-op at `r_stop = 0`) → the SHIPPED `clamp_accel` → `steering_command` →
`alpha_autopilot_delta` → both fins → `_integrate_6dof!`. The injection is intentionally
**unclamped**: §1.1 item 3 clamps through the shipped clamp, and this is that clamp.

**P9.0 SOUNDNESS — the advisor's blocking item, because P7 overwrote ONE key and this overwrites TWO.**
First from the code: `:seeker_los` / `:seeker_omega` are **write-only sinks**, recomputed from
`az_est`/`el_est` every tick at `missile.jl:2629-2630` and read at exactly one place, the guidance arm
at `:1188` (grep over `core/src`: no other reader), so the overwrite cannot feed back into the α-β
filter. Then measured:

```
raw wire       : lock 6956   cpa 2.9976 m   peak a_cmd post-lock (r>200) 23.55 %
k = 0 injected : lock 6956   cpa 2.9976 m   peak a_cmd post-lock (r>200) 23.55 %   dtraj 0.00e+00 m
injection self-check: worst |a_cmd_flown − a_cmd_intended| = 0.000e+00 m/s²  (guard fired 0, injected 6955)
```

⭐ **BIT-IDENTICAL, and the self-check is exact on all 6955 injected ticks** — the seam delivers
precisely the command asked for. ⚠ The `Vc` guard (`|N·Vc| < 1` ⇒ skip, because `ω = (v̂ × a_mid)/(N·Vc)`
would otherwise divide by zero and `clamp_accel` would SAFELY return zero, i.e. the command would
silently vanish and read as "the law does not work") **never fired**, which is itself the answer to
whether it was needed here.

**P9.1 — THE THIRD ARM (§3.3). Displace the target in cross-range, midcourse ABSENT:**

```
   Δy₀ m     lock   t_lock s   r_lock m        cpa m auth % r>200    hold %   aeroSat   maxRes°
       0     6956     6.9560     1436.3       2.9976        23.55    100.00      1235   12.7744
     150     7057     7.0570     1436.6      70.2253       100.00     53.61      6933   12.7841
     300     7182     7.1820     1436.0     209.7832       100.00     54.79      6763   12.7654
     600     7510     7.5100     1436.3     827.8718         0.00     50.59         0    0.1402
    1000     8210     8.2100     1436.5    1203.7137         0.00     37.90         0    0.1402
    1500       -1          —          —    1678.7287         0.00       NaN         0    0.1402
    2500       -1          —          —    2634.1871         0.00       NaN         0    0.1402
```

⚠ **THE `cpa` COLUMN IS NOT QUOTABLE ON ANY ROW BELOW THE FIRST** (§0.5 rule 4 — verdict, never
metres, on an arm that lost the track). The verdicts are what matter, and there are **two distinct
failure modes**, which is more than the plan expected:

- **Δy₀ = 150–300 m** — the head still reaches the target, the tracker initialises, and **PN pins the
  airframe trying to recover** (authority 100 %, 6763–6933 saturated frames, hold ≈ 54 %).
- **Δy₀ ≥ 600 m** — ⭐⭐ **the head cannot reach the target at all.** At handover the target sits ~50°
  off the missile's axis against a **30° gimbal stop**, so `in_fov` is never true, the tracker never
  initialises, the never-locked estimate reports zero, and the missile flies **BALLISTIC to the
  end** — `auth 0.00 %`, `aeroSat 0`, `maxRes 0.1402°`, i.e. it never manoeuvres once. `lock` here is
  the RANGE gate opening (`seeker_detect` is slice 46's link-budget flag), not a track; the `hold`
  figures below 100 % are the range gate re-closing as the missile flies **past**.

> ⭐⭐⭐ **THAT SECOND MODE IS THE STRONGEST FORM OF §3.3's "DOING NOTHING IS WRONG", AND IT IS BETTER
> THAN THE ONE THE PLAN ASKED FOR.** Without a midcourse the target is not merely off-boresight at
> handover — **it is outside the head's mechanical travel.** The midcourse's job is not to shorten a
> correction, it is to arrive with the target *inside the head's reach at all*.
> ⚠ **AND THAT IS ALSO A POINTING ERROR THE MISSILE CANNOT RESOLVE — the search family's stated
> precondition (§0.8).** It is a NOTE, not a claim: slice 47 does not measure a search, and §0.8's
> rule stands until slice 48 does.

**P9.2 — THE NULL ARM (Δp = Δv = 0): does pursuit-of-the-PIP close, and at what `k`?**
⚠ CPA alone decides nothing (advisor): a cell is admissible only if it closes **with zero saturation
frames**. `aeroB` / `aeroP` are aero-saturated frames **before** / **after** lock.

```
Δy₀ = 600 m                                  Δy₀ = 1000 m                    Δy₀ = 1500 m
   k    cpa m  blind%  auth%  aeroB  aeroP      k    cpa m  blind%  auth%  aeroB  aeroP      k  blind%  auth%  aeroB  aeroP
0.25   2.4326    1.11  21.07      0    888   0.25  12.6659    1.54 100.00      0   6656   0.25    2.06 100.00      0   6326
0.50   2.3574    1.59   8.14      0     36   0.50   2.4418    2.29   9.75      0     50   0.50    3.11  12.53      0     74
1.00   2.9447    3.18   4.18      0      1   1.00   2.3981    4.57   4.27      0      4   1.00    6.22   4.74      0      8
2.00   2.7019    6.35   2.89      0      0   2.00   2.7267    9.14   3.21      0      0   2.00   12.43   3.52    246      2
3.00   2.8507    9.52   2.83      0      0   3.00   2.3932   13.70   2.92    269      0   3.00   18.65   2.99    526      0
5.00   2.7559   15.86   2.75    273      0   5.00   2.4850   22.84   2.80    484      0   5.00   31.08   2.79    721      0
8.00   2.9217   25.38   2.72    395      0   8.00   2.6549   36.54   2.76    593      0   8.00   49.73   2.81    827      0
```

⚠⚠ **THE `cpa` COLUMN ABOVE IS AN ARTEFACT OF THE PROBE'S OWN STOPPING RULE AND IS NOT A
MEASUREMENT** (advisor, caught after the first commit). `p9_null.jl` breaks its loop at `r < 3 m` and
records the range **on that same tick**; at 700 m/s and `dt = 1e-3` the missile closes 0.7 m per tick,
so *every* arm that gets inside 3 m necessarily reports something in (2.3, 3.0]. That is "got inside
3 m", not closure quality — the exact class of error that cost slice 44 its §VII.1 figure. Re-flown
**through** the closest approach (`p9b_cpa.jl`, log `p9blog.txt`), stopping on the turn-round instead
of on a radius:

```
   Δy₀ m       k          cpa m          Δy₀ m       k          cpa m
    1000    0.25        12.6659           2500    0.25       320.3806
    1000    0.50         0.1381           2500    0.50         0.2335
    1000    1.00         0.1349           2500    1.00         0.2781
    1000    2.00         0.2721           2500    2.00         0.0234
    1000    3.00         0.1468           2500    3.00         0.2013
  ── CONTROL: slice 46's own wire, Δy₀ = 0, no midcourse ──  0.9874  (its verifier's exact figure)
```

⭐ **The control reproduces slice 46's published 0.9874 m to the digit, which is what licenses the
rest of the table**, and the real closures are **0.13–0.28 m** — an order of magnitude better than the
censored column, and better than the wire's own. ⚠ Even these are FRAME-QUANTISED
([[ewsim-missile-verifier-sampling]]: a HIT samples coarsely, ~0.7 m per tick), so the quotable claim
is the ORDER and the ORDERING ACROSS `k`, never the digits — and by §0.5 rule 1 the miss is not the
gauge in the first place. ⚠⚠ **CONSEQUENCE FOR GATE 2: §2.5 check 2's `cpa < 3 m` is TAUTOLOGICAL on
any arm that reaches 3 m if it inherits this stopping rule.** Write it as an assertion on a CPA
integrated through the turn-round, or it is a check with no teeth.

⭐⭐ **THE ANSWER IS §1.4's MIDDLE OUTCOME — it closes, but the admissible `k` is a WINDOW BOUNDED AT
BOTH ENDS, and the two ends are different physics:**

- **`k` too small** — the midcourse is too lazy, arrives with a residual, and **the ENDGAME pays**:
  post-lock authority pins at 100 % and the airframe saturates for thousands of frames (`aeroP`). At
  the larger displacements `k = 0.25` does not close at all (320 m at Δy₀ = 2500, 522 m at 4000).
- **`k` too large** — the midcourse **saturates the airframe BEFORE lock** (`aeroB`), which is
  §2.5 check 4's explicit disqualifier: *a slider whose top end pins the airframe before lock is a
  different slice.*

**The window NARROWS as the required correction grows, and it narrows from the top:**

```
   correction   admissible k        clean at k = 1.0?
       600 m      0.5 … 3.0                yes
      1000 m      0.5 … 2.0                yes
      1500 m      0.5 … 1.0                yes
      2500 m      0.5 … 1.0                yes
      4000 m      0.5 only                  no (aeroB 458)
```

⇒ ⭐ **`midcourse_k = 1.0` IS THE AUTHORED VALUE AND IT NOW HAS A MEASURED JUSTIFICATION** — the only
gain clean across the whole plausible domain (600–2500 m of cross-range correction: peak blind demand
3.2–9.2 % of `a_max`, **zero** saturation frames before lock, hold 100 %, and the intercept closes).
This is exactly what §1.4 said to learn here rather than at gate 2.

⭐⭐ **AND IT DISCHARGES THE ADVISOR'S WARNING THAT P7's BRACKET WOULD NOT TRANSFER — IT DOES NOT.**
P7 called 473 m of blind-phase cross-range *absurd* (a 163 m miss). Here the null arm flies **893 m**
of cross-range while blind at Δy₀ = 1000 and hits at **2.40 m** for **4.57 %** of `a_max` with zero
saturation. The difference is the SHAPE of the command, not its size: P7 held a **constant injected
rate** through the whole blind phase (displacement grows quadratically, demand never stops), while a
heading correction **does its work early and then flies straight**. ⇒ **a method lesson worth
carrying: a probe that injects a CONSTANT RATE prices a DIFFERENT manoeuvre from the one a converging
law actually flies, and its "absurd" boundary does not transfer.**

**P9.3 — ONE NONZERO-Δv ARM (the advisor's cheap add; NOT a substitute for §2.5 check 4's gate-2 P4
re-run).** Does the midcourse's own authority swamp the error axis on the new geometry?

```
   Δy₀ m       k    Δvy m/s       cpa m  blind a_cmd%  auth % r>200    hold %    aeroB
    1000    1.00        0.0      2.3981          4.57          4.27    100.00        0
    1000    1.00      -30.0      2.6709          3.65         21.62    100.00        0
    1000    1.00       30.0      2.6175          5.48         20.87    100.00        0
    2500    1.00        0.0      2.9003          9.15          4.57    100.00        0
    2500    1.00      -30.0      2.4796          8.38         22.32    100.00        0
    2500    1.00       30.0      2.4627          9.90         22.11    100.00        0
```

⭐ **THE ERROR AXIS IS ALIVE AND IT MOVES THE §3.2 HEADLINE COLUMN BY 5×** — a ±30 m/s belief error
takes the post-lock authority from 4.27 % to ~21 % while the miss stays flat (0.13 → 0.29 / 0.39 m on
the uncensored re-fly), which is §0.5 rule 1 (*miss is not the gauge*) confirmed on slice 47's own
wire before gate 2 is written.

⚠⚠ **AND THIS BLOCK PRICES THE *TRUTH*-CUED HEAD, WHILE GATE 2 SHIPS THE *BELIEF*-CUED ONE — SO IT
IS NOT A GATE-2 NUMBER** (advisor; the same caveat P1 carried as "the positions are off the wire; the
cue mechanism is ASSUMED"). Every P9 arm ran the shipped unconditional truth-derived cue at
`missile.jl:2437`. With `Δv = 0` that is harmless (belief ≡ truth). With `Δv ≠ 0` it is not: once
§2.2's cue arm exists, the head points at the **believed** LOS while the target is somewhere else, so
the handover error lands on the **10° window** instead of being absorbed by a head that was watching
truth the whole time. At ±30 m/s the arm may not acquire at all — the same failure mode as the ABSENT
arm — which would turn the slider's upper domain into "never locks" and leave the authority column
with nothing to move over. ⇒ **the FIRST thing gate 2 measures once the cue arm exists is P9.3's ±Δv
arms re-run with the handover error checked against `fov`, BEFORE `slice47_midcourse.yaml` is
authored.** The 4.27 % → 21 % spread is a promise, not a result.
⚠ **AND THE RESPONSE IS SYMMETRIC IN THE SIGN OF `Δv` (21.62 vs 20.87; 22.32 vs 22.11), SO THE
SLIDER IS V-SHAPED, NOT MONOTONE** — slice 36's basket precedent. The gate-2 P4 re-run must read
monotonicity in **|Δv|**, or the axis must be authored as a magnitude; a signed slider judged for
monotonicity would fire this project's standing disqualifier on an artefact of the sign convention.

### §5.3 GATE-1 STATUS — **THE TWO PROBES ARE RUN AND THE PRIMITIVES ARE SHIPPED**

- **P8 ✓** the reduction FAILS (the good outcome): not a reparameterized PN, and primitive 3 is a
  clamp around the shipped `pursuit_accel`, bit-identically.
- **P9 ✓** §1.4's middle outcome: the null closes, `midcourse_k = 1.0` is measured rather than
  guessed, and §3.3's third arm is pinned by a **stronger** mechanism than the plan expected (the
  gimbal STOP, not a shortfall of correction time).
- **§1.1's three primitives are in `core/src/guidance.jl`**, exported, with the four degenerate
  branches of `intercept_time` each returning a chosen `0.0` (⇒ `pip = p_t` ⇒ pursuit of the believed
  present position, never a zero command).
- **§1.5's tests are in `core/test/test_midcourse.jl`**, wired into `runtests.jl`. Suite green at
  **9191** tests (7808 before). Teeth: a known-root construction; the `‖pip − p_m‖ = V_m·t_go`
  identity; all four degenerate branches; the zero-error null *and* its off-null control *and* the
  two-body propagation that makes it a COLLISION-course identity rather than merely an aligned one;
  the sign in both directions on the cross-range axis; the **frame pin** on argument 2 (see below);
  `midcourse_accel == clamp_accel ∘ pursuit_accel` bit for bit; the P8.a lead-angle identity; and a
  bit-equality pin against `p9_null.jl`'s own arithmetic, so the measured `k` window is calibrated
  against the function that ships.
- ⚠⚠ **THE TRIFECTA SEAM GATE 2 WILL WALK INTO.** `intercept_time`'s second argument is the target's
  **ABSOLUTE** velocity, not a relative one — the missile's velocity does not appear in the solution
  at all, only its SPEED. The guidance chain has a hoisted `rel_vel = tgt.vel - e.vel` three lines
  above where the arm goes, and passing that returns a plausible positive number rather than an
  error. The parameter is named `v_t` for that reason and a test pins the difference.

**⚠ WHAT GATE 2 INHERITS — four items, and two of them are corrections to this log:**

1. **§3.3's default cell is `Δy₀ = +1000 m` of cross-range** (target authored at `y = 3000` instead
   of 2000) with **`midcourse_k = 1.0`**.
2. ⚠⚠ **§2.5 check 2's `cpa < 3 m` IS TAUTOLOGICAL** if it inherits the probe's `r < 3` stopping
   rule — assert on a CPA integrated **through the turn-round** (§5.2's P9b block), or the check has
   no teeth.
3. ⚠⚠ **P9.3's 4.27 % → 21 % authority spread IS NOT A GATE-2 NUMBER** — it was measured with the
   shipped TRUTH-cued head, and §2.2 ships a BELIEF-cued one. Re-run those arms with the handover
   error checked against `fov` **before** `slice47_midcourse.yaml` is authored.
4. **The P4 re-run must be read in `|Δv|`, not signed `Δv`** — the response is V-shaped (§5.2, P9.3).


## §6 — GATE 2: THE LOG

**Status: GATE 2 — RUN AND CLOSED (2026-08-19). Suite green at 9254 tests (9191 before).**

### §6.0 WHAT SHIPPED

Five edits, and the order below is the order they matter in.

1. **`_midcourse_belief!` (`missile.jl`, above `decide!(::Autopilot, …)`)** — the lazy-once mint of
   `:midcourse_p0` / `:midcourse_v0` / `:midcourse_t0` (truth + the authored error, at `w.t`) and the
   pure dead-reckon of it. ⭐ **A FUNCTION AND NOT A CROSS-PHASE KEY**, which is what §2.1 said and
   what makes the two consumers independent: the head's cue in phase 3 and the guidance command in
   phase 4 read the same three stored numbers, never each other, so there is no ordering hazard and
   no repeat of convention 8's telemetry-phase gotcha.
2. **The guidance arm** — a new `elseif` **above** the `:seeker_omega` arm, gated
   `guid === :pn && haskey(c, :midcourse) && !get(c, :seek_init, false)`.
3. **The cue arm** — the previously UNCONDITIONAL `head_tgt_*` write is now a two-arm branch:
   `haskey(c, :midcourse) && !_detectable && !seek_init` ⇒ the belief LOS, else the measurement
   **verbatim**. The mode is stored as `:head_cued` and consumed by the **next** tick's slew, which
   bypasses the `off_axis_angle ≤ fov_h` window when cued (both servo frames).
4. **The loader** — `midcourse` (the anchor), `midcourse_k`, `midcourse_pos_err_m`,
   `midcourse_vel_err_mps`; the last three **refused** without the anchor, `midcourse: false`
   refused rather than treated as off, `k > 0` and the errors finite.
5. **Telemetry** — `midcourse_active` / `midcourse_tgo` / `midcourse_pip_{x,y,z}` /
   `midcourse_pip_err_m` from the guidance side, `head_cued` / `head_cue_err_deg` from the seeker's.
   All anchor-gated, all never-stale.

⚠ **`midcourse_k` IS NOT IN `_DEAD_KNOB_KEYS`, AND THAT IS A DECISION** (advisor). That list is for
keys whose deadness is **STRUCTURAL** (consumed once at load); this one is read inside the arm on
every blind tick, so the list's error text — *"consumed ONCE at tick 1 … dead in the hand"* — would
be a **false statement about the wire**, and its own comment forbids it becoming a registry. §2.4's
"NEVER a knob" is a SHOWCASE policy and is enforced by not declaring it in `knobs:`.

### §6.1 THE PREMISE, DISCHARGED — AND THE DEFAULT CELL IS WHY

Gate-0 P0's finding is not merely reproduced, it is **made load-bearing**. On slice 46's own
geometry the authored launch heading *is* the midcourse solution, so a perfect midcourse would have
nothing to do. Moved **+1000 m in cross-range** (§5.3's inherited default cell):

```
             blind peak |a_cmd|      lock            CPA
  BALLISTIC       0.000000 m/s²      NEVER      1203.7137 m
  MIDCOURSE     137.158272 m/s²    7.1330 s         0.1349 m     (4.57 % of a_max)
  switch: overlap 0 ticks, gap 0 ticks
```

⭐ **The ballistic arm never acquires at all.** That is stronger than P0's "it arrives anyway": off
the launch plane, commanding nothing does not merely cost accuracy, it costs the **acquisition**.

### §6.2 P4 RE-RUN ON THE COMMANDED TRAJECTORY — §2.5 CHECK 4

⚠⚠ **The first read of this table was WRONG and the way it was wrong is worth keeping.** Sampling
`head_cue_err_deg` **at the lock tick** returns the honest `0.0` of a head that is already TRACKING
(`_detectable` flips *before* `seek_init` is set — see §6.3). The quantity is **the last BLIND
tick's** value: what the head was being told when the receiver finally heard something.

```
   err%   cue@handover   pip err m   pre-lock pk%   lock t      CPA m   post-lock pk%   hold%
    0.0        0.0000         0.0         4.57      7.1330      0.135        4.27      100.00
    5.0        2.5647        84.0         4.27      7.1580      0.124        8.46      100.00
   10.0        5.1647       166.8         3.96      7.1890      0.273       14.28      100.00
   14.0        7.2707       232.2         3.71      7.2160      0.314       20.21      100.00
   17.0        8.8738         —           3.53      7.2390      1.333       24.33      100.00
   18.0        9.4122       296.9         3.47      7.2470      0.692       25.99      100.00
   19.0        9.9580         —           3.40      7.2560      2.542       27.97      100.00
   19.5       10.2282         —           3.37      NEVER     316.549        0.00         —
   20.0       10.4986       415.4         3.34      NEVER     324.870        0.00         —
   25.0       13.2689       512.5         3.03      NEVER     408.654        0.00         —
```

**THE NUMBER GATE 3 QUOTES: 0.5116 → 0.5308 °/%**, walking gently with the error (0.5116 at 2 %,
0.5165 at 10 %, 0.5229 at 18 %). ⭐ P1's provisional **0.4970 °/% measured BALLISTIC is CONFIRMED
and corrected UPWARD by ~4 %** — the commanded trajectory diverges slightly more than the free one,
which is the direction that makes the axis *easier* to reach, not harder. The axis is **live,
linear, monotone and defensible**.

### ⭐⭐⭐ §6.3 THE CLIFF IS THE WINDOW, AND IT IS THE SLICE

The handover error crosses the authored **10° detector window between 19.0 % and 19.5 %** of
belief-velocity error, and **the engagement flips exactly there**: 9.9580° → acquires at 7.2560 s →
arrives at **2.542 m**; 10.2282° → **NEVER ACQUIRES** → **316.549 m**. A quarter of a degree.

⇒ **THE LESSON, IN ONE SENTENCE.** *A midcourse is not judged by how far off its picture is, but by
whether the target is still inside the detector window at the instant the receiver first hears it —
and everything before that instant looks fine.*

**AND THE INTERMEDIATE STORY IS SLICE 46's SHAPE, REPRODUCED IN A NEW CURRENCY.** Across the whole
surviving domain the **miss says nothing** (0.124 → 0.273 → 0.314 → 0.692 → 2.542 m, up and down)
while **post-lock authority walks 4.27 → 27.97 % monotonically**. A verifier reading miss would
again report a component that does nothing.

### §6.4 §2.5 CHECK 4's OTHER HALF — P7's BRACKET, AND THE READ THAT SEPARATES CAUSE FROM CONSEQUENCE

P7 forbade *"a slider whose top end PINS THE AIRFRAME BEFORE LOCK"* — that is a different slice. A
whole-flight read makes it look as if this one does: the broken arms show **22.77 %** of `a_max` and
**441 ticks of aero saturation**. ⚠⚠ **THAT READ IS AN ARTIFACT OF THE FAILURE, NOT ITS CAUSE.** A
missile that never acquires keeps flying midcourse all the way to CPA, so the saturation happens
**long after** the handover would have been. Read **before the handover range (r > 1437 m)**:

```
  blind peak |a_cmd| / a_max, r > 1437 m :  4.57 % (0 %) … 3.03 % (25 %)   — DECREASING
  aero_sat ticks, r > 1437 m             :  0 on EVERY arm in the domain, broken ones included
```

⭐ **AND THE SIGN IS THE INTERESTING PART: a wronger picture makes the midcourse work LESS hard.**
It believes the target needs less lead, flies a lazier correction, and pays the whole bill at
handover. P7's constraint is satisfied with margin, and `pre` vs `all` is the pair that proves it.

### §6.5 P9.3 RE-RUN WITH THE BELIEF-CUED HEAD — §5.3 INHERITANCE ITEM 3, DISCHARGED

P9.3's 4.27 % → 21 % authority spread was measured with the shipped **TRUTH**-cued head. Re-run on
the **BELIEF**-cued one, signed `Δv` (m/s on the crossing axis):

```
   Δv     cue@handover   pre-lock pk%   lock t      CPA m   post-lock pk%
  −50        13.2689         3.03        NEVER    408.654        0.00
  −40        10.4986         3.34        NEVER    324.870        0.00
  −30         7.8056         3.65       7.2240      0.287       21.62
  −10         2.5647         4.27       7.1580      0.124        8.46
    0         0.0000         4.57       7.1330      0.135        4.27
  +10         2.5427         4.87       7.1120      0.146        8.43
  +30         7.6013         5.48       7.0840      0.389       20.87
  +40        10.1327         5.77       7.0760      1.281       28.18
  +50        12.6762         6.07        NEVER    388.806        0.00
```

⭐ **P9.3's SPREAD SURVIVES THE CUE CHANGE ALMOST EXACTLY** (4.27 → ~21 % at |Δv| = 30, against its
4.27 → 21 %), so the number carried into §3.3 is sound. §5.3 item 4's instruction to read `|Δv|`
is **confirmed**: the response is V-shaped in the cue error. ⚠ **BUT IT IS NOT SYMMETRIC**, and the
asymmetry is real rather than noise — the **−** side breaks between −30 and −40 while the **+** side
survives to +40, because a belief that the target crosses *faster* leads further and buys time. Gate
3's slider should therefore be authored on the **−** side, where the cliff is inside a defensible
error magnitude (19.5 % of the crossing speed).

### §6.6 THE FIVE GATE-2 CHECKS, EACH WITH ITS TOOTH

| §2.5 | check | where it lives | verdict |
|---|---|---|---|
| 1 | **ABSOLUTE GOLDEN, both directions** | `test_missile.jl`, "BYTE-IDENTITY, BOTH DIRECTIONS" | ✓ `max|Δpos| == 0` over 4000 ticks with the ANCHOR PRESENT and both arms structurally unreachable (rcs 1 m² ⇒ lock on tick 1); and `head_cued == 0` for the whole flight at three belief errors with `detect_pt_w` absent |
| 2 | **the zero-error null is METRES, not bits** | same file, "THE ZERO-ERROR NULL" | ✓ CPA 0.1349 m **integrated through the turn-round**, blind command < 10 % of `a_max`, hold 100 %. ⚠ §5.3 item 2's tautology is closed: nothing stops until the range has been rising for 200 ticks |
| 3 | **the switch tick** | same file, "THE SWITCH IS ONE TICK" | ✓ overlap 0, gap 0, `act_n == lock_i − 1`, and the lock tick itself TRACKS |
| 4 | **P4 re-run + P7's bracket** | §6.2 / §6.4 above | ✓ 0.512–0.531 °/%; pre-handover peak 3.0–4.6 %, aero saturation 0 everywhere |
| 5 | **the slice-19 tripwire** | same file, "THE SLICE-19 TRIPWIRE" | ✓ all four authored keys move `max|Δpos|`, plus the mint pinned against truth-plus-error |

### ⚠⚠ §6.7 THE ONE-TICK CLOCK OFFSET, AND IT COST TWO FAILED ASSERTIONS

`tick!` advances `w.t` **after all four phases**, so during tick *n* every phase reads
`w.t = (n−1)·dt` while phase 1 has **already** moved the entities to `n·dt`. The mint therefore
stamps `t0 = 0.0` beside a target position that is one step old *in the world clock's terms* — and
because every later dead-reckon reads the **same** lagging clock, the offset appears on both sides
and **divides out exactly**: `p0 + v0·((n−1)·dt − 0)` is the target's true position at tick *n*, to
the last bit, for a constant-velocity target.

⚠ Both failures were in the TEST, not the wire, and both looked like tolerance problems:
`t0 == w.t` (0.0 vs 0.001), and a recompute using the **post**-tick `w.t` landing **0.2 m** ahead —
which is exactly `200 m/s × dt`, one step of target motion. **A wrong-number of precisely the size
that reads like a rounding issue and is not one.** Both clocks are now pinned in the same testset,
the correct one to `< 1e-9` and the wrong one to `200·dt`, so the cancellation is a MEASUREMENT.

### §6.8 WHAT GATE 3 INHERITS

1. **The default cell**: target at `y = 3000` (`Δy₀ = +1000 m`), `midcourse_k = 1.0`, rcs 0.001,
   window 10°, servo 240 °/s — the wire every number above was measured on.
2. **The slider is the belief VELOCITY error on the crossing axis, on the MINUS side**, domain
   0 → ~25 % of the crossing speed, with the cliff at **19.0 / 19.5 %**. ⚠ Author the cliff INSIDE
   the domain — it is the lesson — but the HUD headline must be **`head_cue_err_deg` against
   `gimbal_fov_deg`** and **post-lock `a_cmd_frac`**, never the miss (§3.2's forbidden gauges, and
   §6.3's table is the reason).
3. ⚠⚠ **The verifier must read `head_cue_err_deg` on the LAST BLIND TICK**, never at the lock tick,
   where it is 0.0 by construction. §6.2's first table was wrong this way. The same applies to
   `midcourse_pip_err_m`, which the guidance arm stops publishing the moment PN takes over.
4. ⚠ **Read the authority GATED AT r > 200 m** ([[ewsim-missile-verifier-sampling]]): ungated, the
   hold reads 90 % on arms that never break and the endgame spikes every guidance quantity.
5. **The broken arms never lock, so they run midcourse to CPA** — a verifier that assumes a lock
   instant exists will read `NaN`/`-1` on exactly the cells that carry the lesson.

---
