# Slice 34 — THE GIMBAL: THE HEAD POINTS WHERE THE GLASS SAYS THE TARGET IS (§11 Tier-A)

The TWELFTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro, 32 = the seeker's field of view, 33 = the ring as
an FOV budget item), and the successor slices 32 AND 33 both nominated:

> *"⭐ **A REAL GIMBAL — and it now has its lesson, banked at gate 0.** … **The lesson it should
> carry: the gimbal that saves your envelope PARKS YOU ON THE WORST GLASS.** … ⚠ It REWRITES 26–31's
> `look_az` (the bend would key off head-vs-body), which is the byte-identity surface of six slices,
> so it needs a presence-gated head state with the strapdown else-arm VERBATIM."*
> — `docs/plans/slice33.md`, Deferred (NAMED)

**Status: GATE 2 COMPLETE (2026-08-09, suite 6295 → 6515). Gate 0 = 9 probes, gate 1 = the kernels,
gate 2 = the seam + the loader + the wired testset. GATE 3 PENDING (the scenario, the client, the
four proofs).
⚠⚠ BOTH HALVES OF THE BANKED DEFERRAL WERE REFUTED AT GATE 0 (§0.1, §0.2) and the live claim was
found in a THIRD place (§0.4) — the slice-33 shape exactly, and the refutations are load-bearing.
⚠⚠ AND GATE 2 CORRECTED THREE OF GATE 0's OWN READINGS (§2.1, §2.3, §2.4) — including §0.2's, whose
collapse is a property of the `:truth` head and NOT of the head that ships. Probe scripts in
`M:\claud_projects\temp\slice34\`.**

---

## The one-paragraph statement of the lesson

Slices 26–31 built the parasitic loop on one geometric fact: the radome bends the ray by an amount
set by the LOOK ANGLE, and the look angle is the LOS measured off the missile's own nose. That is a
quantity the missile can only move by ROTATING — which is exactly why the loop closes through the
body and why slice 26 is a body-rate instability. **A gimballed seeker breaks that identity.** Its
head has its own pointing angles, the ray passes through the part of the dome the head is AIMED at,
and — this is the whole slice — **the head is aimed by the very measurement the dome just bent.**
The index of the glass becomes a FIXED POINT of the glass: the head points where the bent
measurement says the target is, so part of the bend's own variation is absorbed by the head's
pointing instead of being handed to guidance. Slice 26's loop is partly re-closed through the HEAD,
where its sign is NEGATIVE. On the shipped glass and R̂ ladder the onset walks from `(−0.27, −0.24]`
strapdown to `(−0.18, −0.16]` gimballed — ⚠ **quoted BRACKET TO BRACKET, never as one number**
(slice 30's "sufficient, never tight" discipline: the gap those two brackets admit spans 0.06 to
0.11, so a single "≈0.08" would be asserted at gate 2 and fail) — and at `R̂ = −0.18` the SAME
glass, SAME residual, SAME seed gives **rms r 0.93194 (RINGS) strapdown vs 0.01181 (QUIET)
gimballed, 78.9×**.

> **THE LESSON, IN ONE SENTENCE.** A strapdown seeker's radome index is handed to it by the
> airframe; a gimballed seeker's is handed to it by its own last measurement — and an index that
> looks at itself is an index that fights back.

⚠ **AND IT IS NOT FREE, IN THE ONE CURRENCY A GIMBAL HAS.** The margin is bought by the head's
pointing DECOUPLING from the true LOS, and the size of that decoupling is precisely the tracking
error the head's own detector window must cover. Slice 33's single number splits in two: a STOP
(the head's travel about the body, which reproduces slice 33's excursion — **a restatement, not a
new claim**) and a DETECTOR WINDOW (about the head axis — new, and where the margin is paid for).

---

## §0 — Gate 0 (9 probes, 2026-08-09)

⚠ **METHOD.** `GimbalSeeker` is a probe-local COPY of `missile.jl::_observe_point3d!` with a head
state inserted; the core was NOT touched. Because a hand-copy can differ from the shipped seam in
ways that masquerade as physics, **P0 validates the copy before anything is claimed from it**
(convention 10, one layer stricter than usual). All arms: glass `R₀ = −0.03, A = −0.15, k = 12`
(⇒ `radome_slope_worst = −0.33`), `vy = 200`, seed 32, `dt = 1e-3`, 22 000 ticks — slice 33's wire
verbatim, so every strapdown column is checkable against `docs/plans/slice33.md`.

### ⚠⚠ §0.1 — REFUTATION 1: THE BANKED LESSON IS FALSE, AND ONE COLUMN KILLS IT (`p0_collapse.jl`)

The banked lesson was *"the gimbal that saves your envelope PARKS YOU ON THE WORST GLASS"* — a
strapdown seeker's body chases the LOS so the look angle stays near the lead, while a gimbal
deliberately HOLDS the head at the full lead, out on slice 28's steep glass. **It rests on a
contrast that does not exist.** With the head degenerate (τ → 0), the probe measures

| arm | `look_body_max` | `head_max` |
|---|---|---|
| strapdown, R̂ = −0.03 | 24.984° | — |
| gimbal τ→0, R̂ = −0.03 | 24.984° | **24.984°** |
| strapdown, R̂ = −0.33 | 18.138° | — |
| gimbal τ→0, R̂ = −0.33 | 18.138° | **18.138°** |

**The head parks nowhere the body was not already looking.** A strapdown seeker's look angle IS the
full lead — that is what slice 32 measured and named (`held ⟺ lead < fov`) and what slice 33 spent
its excursion budget on. The banked framing imagined a strapdown seeker whose nose tracks the LOS;
it does not, and cannot, because a missile points its nose along its velocity plus incidence.

### ⚠⚠ §0.2 — REFUTATION 2: THE `look_az` REWRITE COLLAPSES (the advisor's blocking check)

The deferral's stated reason for being a big slice is that it *"rewrites 26–31's `look_az` (the bend
would key off head-vs-body)"*. Measured, on RINGING glass so the bend is live and large:

**`max|Δpos| = 0` over 9 000 ticks — EXACTLY, at both R̂ = −0.03 and R̂ = −0.33.**

At zero servo lag the head angle IS the LOS-vs-body angle, so the glass sees the same index and the
bend is unchanged. This is the FALSE-FIDELITY class — slice 15's `k_δ` cancellation, slice 19's dead
`speed`, slice 31's `R̂(1+s)` reparameterization — and it means **"the bend keys off head-vs-body"
ships as a TOOTH, never as the headline.** ⭐ It doubles as the copy's validation: `GimbalSeeker`
degenerate is bit-identical to the shipped `Seeker`, so every later probe rides on a verified copy.

### §0.3 — Is the servo lag material at all? (`p1_tau.jl`, `p2_onset.jl`, `p3_split.jl`)

The failure mode to rule out next is slice 25's: seeker noise × the BTT roll loop was a ~1000:1
low-pass and shipped **DEAD, not deferred**. With a head slewing toward the TRUE LOS (`:truth`):

| τ (s) | RINGING (R̂ = −0.03) `off_max` | rms r | QUIET (R̂ = −0.33) `off_max` | rms r |
|---|---|---|---|---|
| 0.000 | 0.0000° | 1.07211 | 0.0000° | 0.05879 |
| 0.020 | 1.8285° | 0.97277 | 0.4176° | 0.05893 |
| 0.050 | 3.7680° | 0.86863 | 0.8551° | 0.05919 |
| 0.200 | 7.6777° | 0.64831 | 2.1164° | 0.06089 |
| 0.400 | 9.5767° | 0.54579 | 3.2032° | 0.06209 |

Not dead: the lag both quiets the loop and costs detector error, and the RING inflates the error
~4× over the quiet arm at matched τ. **P2 then ran slice 27's discriminator** (an OFFSET moves the
onset; a GAIN scales the whole ladder) and found the onset walking −0.27 → −0.21 as τ goes 0 → 0.2,
with the quiet rows barely moving (−0.33: 0.05879 → 0.06089) — a boundary shift, not a de-tune.
**P3 measured the price:** at R̂ = −0.24 the critical detector window grows 0.25° → 5.0° as τ goes
0 → 0.2, while `rms r` falls 0.70983 → 0.04306 and the head travel requirement RETURNS to 18.118°.

⚠ **`head_max` IS NON-MONOTONE IN τ** (20.62 → 22.29 → 23.42 → 18.12 → 18.12): a partially
suppressed ring makes the head chase MORE before the ring dies. **This is the 5th occurrence of the
non-monotone-knob pattern in this arc** (slice 19's ρ, 20's K, 22's α_stall, 28's k) and any knob
domain chosen across that peak would reverse the lesson.

### ⚠⚠ §0.4 — THE FORK, AND WHERE THE CLAIM ACTUALLY LIVES (`p4_bent.jl`, `p5_bent_onset.jl`)

§0.3's head slews toward the TRUTH LOS. **A real head cannot: it slews on its own detector's error
signal, which is the BENT, NOISY measurement — and slice 27 already made that a rule** ("compensate
with a signal that is not itself corrupted by what you are compensating"). The honest head
(`:bent`) tracks the previous tick's MEASURED LOS-in-body. Two checks, then the fork:

* **(A) It does not reverse the direction.** `:bent` is never worse than `:truth`; at R̂ = −0.24 it
  is far quieter (0.02609 vs 0.40798 at τ = 0.02), at R̂ = −0.03 the two agree within 2%.
* **(B) No delay-driven re-destabilization** out to τ = 3.2 s (a lag normally buys phase, not
  margin). `rms r` stays ≈0.04 while `off_max` grows to 13.7°.

**But the fork is real, and it decides the slice's shape:** under `:bent`, τ does NOT move the onset
anywhere in `[0.02, 0.2]` — only the amplitude sags. The full ladder:

| R̂ | strapdown | `:bent` τ=0.02 | τ=0.05 | τ=0.10 | τ=0.20 | **τ=1e9 (frozen)** |
|---|---|---|---|---|---|---|
| −0.33 | 0.05879 | 0.06037 | 0.05917 | 0.05905 | 0.05930 | 0.07895 |
| −0.27 | 0.03070 | 0.03832 | 0.03701 | 0.03691 | 0.03763 | 0.05927 |
| −0.24 | **0.70983** | 0.02609 | 0.02497 | 0.02459 | 0.02545 | 0.05017 |
| −0.18 | 0.93194 | 0.01166 | 0.01181 | 0.01162 | 0.01042 | 0.03368 |
| −0.12 | 1.03165 | **0.83567** | 0.70207 | 0.57877 | 0.42355 | 0.02101 |
| −0.03 | 1.07211 | 0.99009 | 0.88465 | 0.79182 | 0.66688 | **0.01472** |

⇒ **τ is an AUTHORED §1 PARAMETER, NOT A SLIDER** (the slice-19 dead-knob discipline applied
BEFORE the knob exists rather than after it ships). The single live slider is the detector window.

⭐⭐ **AND THE FROZEN ARM PINS THE MECHANISM RATHER THAN INFERRING IT FROM A TREND** (slice 21's
ρ-factor standard). A head frozen in the BODY frame produces a CONSTANT bend — there is nothing for
`dε/dt` to differentiate — and it is quiet at **every** R̂ including −0.03 (0.01472, a 72.8× drop
from the strapdown arm). ⚠ **It is a REDUCTIO, not a design:** its detector error runs to **33.08°**
(P6C), i.e. it has stopped being a gimbal and become a staring seeker whose window is the whole
lead. **That is what makes the trade STRUCTURAL and not incidental — the motion that holds the
track is the motion that feeds the loop.**

### ⭐⭐ §0.5 — THE ISOLATION: WHAT ACTUALLY BUYS THE MARGIN (`p7_isolation.jl`)

Under `:bent` the onset moves a full two rungs of the ladder while τ does nothing across a 10× span.
So the margin is NOT the servo lag, and two candidates remain — one of which would be a probe
artifact:

* **(i) the SELF-REFERENTIAL INDEX** — the head points where the bent measurement says the target
  is, so the bend indexes on a quantity the bend itself moved. Real physics.
* **(ii) the ONE-TICK SAMPLING DELAY** that `:bent` necessarily carries. **A 1 ms delay worth 0.08
  of radome residual would be an implementation artifact of the probe**, and shipping it as physics
  would be the false-fidelity class for the THIRD time in one gate.

**The isolation arm `:delay` carries (ii) without (i)** — the same one-tick sampling delay applied
to the TRUTH LOS:

| R̂ | strapdown | `:truth` | **`:delay`** | `:bent` |
|---|---|---|---|---|
| −0.24 | 0.70983 | 0.40798 | **0.40752** | 0.02609 |
| −0.18 | 0.93194 | 0.69538 | **0.69399** | 0.01166 |
| −0.03 | 1.07211 | 0.97277 | **0.97186** | 0.99009 |

(τ = 0.02; the pattern holds at 0.05 and 0.20.) **`:delay` reproduces `:truth` to three decimals at
every R̂ — the sampling delay contributes NOTHING — while `:bent` departs from both.** ⇒ the margin
is bought by the INDEX, and the slice has a mechanism rather than a coincidence.

### §0.6 — The bracket, at the arc's own resolution (`p6_bracket.jl`)

The shift IS the payload, so it is quoted as a MEASURED bracket, never interpolated. `:bent`,
τ = 0.05:

| R̂ | rms r | `off_max` | `head_max` | miss |
|---|---|---|---|---|
| −0.19 | 0.01215 | 1.926° | 18.117° | 0.170 m |
| −0.18 | 0.01181 | 1.956° | 18.117° | 0.187 m |
| −0.17 | 0.03934 | 3.762° | 18.117° | 3.631 m |
| −0.16 | **0.35338** | 5.237° | **20.619°** | 5.695 m |
| −0.12 | 0.70207 | 5.587° | 22.026° | 6.500 m |

⇒ onset bracket **(−0.18, −0.16]**, with −0.17 MARGINAL and not asserted; strapdown's own bracket on
this glass is **(−0.27, −0.24]** (slice 30's "last decisive ring −0.24/0.709", reproduced to the
digit). ⭐ **AND `head_max` STEPS AT THE SAME PLACE** — 18.117° through the quiet arms, 20.619° at
the first ringing one — a SECOND, INDEPENDENT tell from a different quantity, which is what makes
the bracket a measurement rather than a threshold read off the metric that defined it.

⚠ **THE MISS IS NOT THE METRIC** — every arm in every table above HITS (0.05–7.5 m). That is the
arc's standing fact since slice 26 and it is unchanged here; the verdict is always `rms r`.

### ⭐⭐ §0.7 — IS THE DETECTOR WINDOW A LIVE KNOB? (`p8_window.jl`, an advisor BLOCKING check)

⚠ Every `:bent` number in §0.4–§0.6 was measured at `fov = 1e6`. **Gate 0 had NO `:bent` arm where a
finite window BINDS**, and the plan proposes exactly that as the slice's one live slider — so it
was flown before §1 was written. `:bent`, τ = 0.05, stop 30°:

| R̂ | free `off_max` | 1.0° | 1.5° | 2.0° | 4.0° | 6.0° | critical |
|---|---|---|---|---|---|---|---|
| −0.18 (quiet) | 1.9556° | 1028.8 m | 728.2 m | **0.185 m HOLD** | HOLD | HOLD | **2.0°** |
| −0.16 (ringing) | 5.2368° | 1254.8 m | 1186.5 m | 568.9 m | 269.2 m | **5.695 m HOLD** | **6.0°** |

⭐⭐ **SLICE 32's PREDICATE RETURNS IN THE NEW CURRENCY: `held ⟺ tracking error < detector window`,**
and `⌈off_max⌉` calls the critical window exactly in both rows (2 and 6). ⚠ As in slice 32, the two
sides come from DIFFERENT CODE PATHS on DIFFERENT RUNS — the error off a FREE arm, the verdict off a
WINDOWED one — which is what makes it a measurement rather than a restatement. ⭐ **AND THE RING IS
SPENT IN DETECTOR WINDOW, 3× (2° → 6°)** — slice 33's payload, in the quantity a gimbal actually has.

⚠⚠ **THE METRIC INVERSION ARRIVES THROUGH A NEW DOOR, AND IT IS MEASURED, NOT FEARED.** The head
HOLDS when it loses its error signal, so a broken window FREEZES the index — and §0.4's frozen arm is
quiet at every R̂. Confirmed: at R̂ = −0.16, `rms r` **FALLS 0.35338 → 0.08491** while the miss OPENS
to 1254.8 m, with `off_max` running to **89.9°** (slice 33's post-lock-loss runaway signature).
⇒ **SLICE 33's TWO-RUN DISCIPLINE IS MANDATORY HERE, NOT INHERITED AS A COURTESY**: the predictor
(`off_max`, `rms r`) comes off the FREE arm, the predicted (miss, % out) off the WINDOWED one, and no
stability verdict may ever be read on a windowed arm.

### ⚠⚠ §0.8 — THE HANDOVER IS LOAD-BEARING (same probe; slice 32's P5 vindicated)

The head initialises to the truth look angles on tick 1 — a TRUTH read on a path whose whole thesis
is that the head never sees truth. Expected immaterial (one tick, then the servo converges).
**It is not.** Against a head that starts CAGED at boresight:

| R̂ | init | rms r | `off_max` | miss |
|---|---|---|---|---|
| −0.18 | handover | 0.01181 | **1.9556°** | 0.187 m |
| −0.18 | boresight | 0.01305 | **18.1172°** | 0.172 m |
| −0.16 | handover | 0.35338 | 5.2368° | 5.695 m |
| −0.16 | boresight | **0.26719** | 18.1172° | 1.883 m |

**A caged head must slew the WHOLE LEAD, so during acquisition its window requirement degenerates to
the strapdown one** (18.12° — slice 32's own number) and `off_max` over the full flight stops
measuring the tracking error at all. ⚠ **AND THE RING VERDICT IS TOUCHED**: at R̂ = −0.16 the caged
arm's 0.26719 sits on the wrong side of the 0.30 line the bracket was read against. ⇒ **the §0.6
bracket is quoted FOR THE HANDOVER INIT**, which is what ships, and gate 1 must either window
`off_max` past the acquisition transient or author the handover as a stated §1 condition. This is
precisely the deferral slice 32's P5 named ("the handover basket as an authored quantity") arriving
as a live constraint rather than a nicety.

---

## §1 — Gate 1 (COMPLETE, 2026-08-09 — 6215 → 6295)

**THREE kernels in `frames.jl`, and one of them REDEFINES a shipped symbol:**

```julia
off_axis_angle(ref_az, ref_el, az, el) = hypot(wrap_angle(az - ref_az), wrap_angle(el - ref_el))
boresight_angle(att, los) = off_axis_angle(0.0, 0.0, look_angles(att, los)...)     # ← REDEFINED
head_clamp(az, el, stop) -> (az, el)                        # the CIRCULAR mechanical stop
head_slew(head_az, head_el, tgt_az, tgt_el, τ, dt, stop)    # the servo, ending in head_clamp
```

### ⭐⭐ ONE KERNEL GENERALIZED, AND THE ARGUMENT IS PHYSICS, NOT REUSE

The plan left this open — *"gate 1 decides whether that is one kernel generalized or two, and must
say which and why."* It is ONE, and the decisive reason is not that both are `hypot` of two wrapped
differences (which is only an implementation coincidence) but that **§0.8 already measured the
degenerate as a physical state**: a head CAGED at boresight must slew the whole lead, so its window
requirement degenerates to the strapdown one — **18.1172°, slice 32's own number.** ⇒ a strapdown
seeker IS a caged gimbal, and `boresight_angle` IS `off_axis_angle` at `ref = (0,0)`. The structural
argument is slice 33's, one layer up ("a quantity that does not fly is a quantity `test_frames.jl`
proves a SECOND implementation of"); shipping the head angle BESIDE `boresight_angle` would have
left gate 1 with a kernel nothing calls and two implementations of one measurement.

⚠ **THE IDENTITY IS ABOUT THE ANGLE, NOT ABOUT THE SENSOR** (advisor). `seeker_fov_deg` /
`seeker_fov_margin_deg` KEEP their slice-32/33 meaning (LOS-vs-BODY) and the head quantities ship
ALONGSIDE — slice 28's `radome_residual*` precedent. That the degenerates coincide is not a licence
to collapse them, which would silently rewrite two slices' asserts.

### ⚠ THE REDEFINITION IS BIT-IDENTICAL, MEASURED THREE WAYS AND NEVER ARGUED

`wrap_angle` is `rem(θ, 2π, RoundNearest)`, the EXACT identity on `az_el`'s codomain — 0 mismatches
in 200 000 samples, both boundaries included (`g1_wrapcheck.jl`) — and `x − 0.0 === x`. But the
composed expression is what ships, so it is the composed expression that is pinned:

1. **`test_frames.jl`, 4000 randomized `(att, los)`, `===`** against the LITERAL slice-32 expression
   `hypot(look_angles(att, los)...)` — ⚠ **never against the new kernel**, which is now the
   definition and would make the tooth `x == x` (convention 11's tautology, which slice 33's own
   gate 1 walked into). The sweep is asserted to REACH the wide corner (`b_hi > 3.0 rad`, 400+ cells
   past 2 rad) so it is not crowded near zero.
2. **ON THE WIRE** (`g1_wire_identity.jl`, convention 2's "reading the diff is not enough"): slice
   33's own engagement flown at four R̂, comparing per tick on the attitudes the flight really
   reaches — **0 mismatches in 35 346 ticks**, with the look angle reaching **165.4°**, i.e. through
   the post-CPA LOS flip, which is exactly the corner where a wrap could have diverged. The
   `seeker_fov_margin` path is checked on the same ticks.
3. The full suite green at **6276**, including `test_missile.jl`'s slice-32 (156) and slice-33 (153)
   WIRED testsets. ⚠ A green `test_determinism.jl` / `_sample_z` golden is **not** evidence here
   (advisor) — neither touches `boresight_angle`.

### ⚠⚠ FINDING 1 — "THE EQUATOR IS EXACT" IS FALSE, AND §0.7's CLAIM SURVIVES ANYWAY

`boresight_angle` declares the angle-space-radius approximation with the reference at the ORIGIN
(+0.364° at a true 30° cone). With an OFFSET reference it is a DIFFERENT quantity, so it was
re-measured rather than inherited (`g1_radius.jl`, `g1_gap_at_op.jl`), and the natural thing to
write — *the equator is exact, because an azimuth difference subtends `cos(el)` times its own size*
— **is wrong**: at `ref_el = 0` the ERROR's own excursion off the equator still contributes, cubically
(**0.00009°** at a 1.96° error, **0.00159°** at 5.0°), independent of `ref_az`. What is true is the
ELEVATION dependence: lift the reference to 10° and the same 1.96° error gives **0.030°, 330×**.

⭐ **The measurement's own control came first** (convention 10): at `ref = (0,0)` the identical code
reproduces `boresight_angle`'s shipped **+0.36416° at φ ≈ 47°**.

⇒ **§0.7's `⌈off_max⌉` = critical window claim is safe with three orders to spare.** The head sits at
`|el| ≤ 0.84°` on the shipped wire (`g1_headel.jl` — the crossing lead is essentially pure AZIMUTH),
so at the two operating points the bracket is read at the gap is **0.0004°** and **0.0034°**, against
a 0.5° bracket resolution and a 1° window grid. Over the whole plausible domain (`ref_az ≤ 30°`,
`|ref_el| ≤ 10°`, error `≤ 8°`) it peaks at **0.139°**, still under that resolution.

### ⚠⚠ FINDING 2 — THE CONTRACTION CAVEAT IS SHARPER THAN THE ADVISOR PREDICTED, AND IT LANDS ON GATE 2

The advisor's blocking note was that a "the error never grows" tooth is FALSE when the stop binds,
since a radial clamp pulls the head off the line to the target. Measured (`g1_contract.jl`,
400 000 randomized cells per regime), the truth is two-sided and sharper:

| head starts | growths / 400 000 | worst Δ |
|---|---|---|
| INSIDE or ON the stop | **0** | 0 |
| already OUTSIDE the stop | 144 698 | **2.924 rad** |

⇒ **the disc is INVARIANT and the step is a contraction on it UNCONDITIONALLY** — including across
a binding clamp. The failure needs a head handed in already outside its stop, which the servo cannot
produce because `head_slew` is the SOLE writer of the head and clamps every tick. ⭐ **So the caveat
is not a test exclusion, it is a GATE-2 CONSTRAINT ON THE HANDOVER**: §0.8's init must apply this
same CIRCULAR clamp, or tick 1 hands in the one state that breaks the invariant. Both regimes ship
as teeth — the sweep asserts the clamp actually bound (200+ cells), and the growth case is the exact
cell the search returned (0.688 → 3.612 rad).

⚠⚠ **AND A CONSTRAINT STATED IN A PLAN IS NOT ENFORCEABLE** (advisor, post-review). The clamp lives
in the SEAM at handover, where `head_slew` cannot see it — so nothing at gate 1 could fail if gate 2
got it wrong, and **the code gate 2 will be copied from already has the bug**: `gimbal_lib.jl`'s init
clamps PER AXIS, exactly the form Finding 3 rejects. ⇒ the clamp was split out as **`head_clamp`**,
its own kernel with its own testset, so both callers share ONE site — slice 33's `seeker_fov_margin`
owning the FOV clamp, precisely. It is also now the fourth numbered seam discipline below.

### ⚠⚠ FINDING 3 — THE PROBE'S STOP WAS PER-AXIS WHILE ITS OWN TELEMETRY READ THE CIRCULAR MAGNITUDE

`gimbal_lib.jl` clamps `head_az` and `head_el` INDEPENDENTLY (`clamp(x, -stop, stop)`) and then
reports `head_angle_deg = rad2deg(hypot(head_az, head_el))` "vs the STOP" — two different shapes,
one of which permits `√2·stop`. **No gate-0 arm ever bound the stop in EITHER form** (every arm ran
`stop = 1e6°` or `30°` against a `head_max` of at most 23.42°, §0.3/§0.7), which is why the
inconsistency was invisible. The shipped stop is **CIRCULAR**, chosen on species grounds — the stop
must have the same shape as the telemetry that reads it and as the detector window — and ⚠ **gate 0
cannot discriminate the two forms, so this docstring and `test_frames.jl` are its ONLY evidence.**
A later slice authoring a tighter stop inherits a branch no flying arm has ever taken; a
RECTANGULAR / per-axis stop stays a named deferral. Written down now rather than discovered at
gate 3.

### The teeth

`off_axis_angle` — the 4000-cell bit-identity vs the slice-32 literal; the PAIRED "the reference is
not ignored" case (a head 18° off the nose reads 2° on a LOS the NOSE is 20° from — without which
the identity would also hold for a kernel that dropped its first two arguments); the WRAP paired
with a does-not-wrap case and the naive 358° exhibited; symmetry in the two argument pairs over 2000
cells (`===`); the §1 approximation with its control and its two operating points; hand-computed
exact cases (a 3-4-5 in angle space); conventions 5/6.

`head_clamp` — INERT bit-for-bit when it does not bind (what lets the handover call it
unconditionally); onto the circle along the same ray when it does, with the exact residual
`‖tgt‖ − stop`; ⚠ **the PER-AXIS form EXHIBITED differing** (`√2·stop` on the diagonal), which is
the only place in the suite the two shapes are ever compared; the CAGED and NaN-stop degenerates,
relocated here rather than duplicated.

`head_slew` — ⭐ **THE EXACT LANDING BY ASSIGNMENT** over 12 000 cells (`===`), PAIRED with the
arithmetic form `head + wrap(tgt − head)` **exhibited failing** (100+ of 3000), because §0.2's
`max|Δpos| = 0` bit-identity control is the slice's own false-fidelity check and a rounding residual
would turn it into a near-miss; the first-order decay against the EXTERNAL anchor `(1 − dt/τ)^n`;
the short-way-round wrap paired, plus the fact that a head with NO stop may leave the principal
interval and still converge (3000 steps); ⭐ **the FIXED POINT at the stop** — on the circle, in the
target's direction, and `===` stable over 200 further steps (slice 24's killed ±90° bank law is the
precedent: a projection at a limit is where chatter hides) — ⚠ **with the WHERE pinned by the exact
residual `‖tgt‖ − stop`, not by a converged ratio**, which after a 20 000-step burn-in is tighter
than any loose `atol` and so could not have caught a head settling on the wrong point of the circle
(advisor); both contraction regimes; the degenerate
table (`τ = Inf` FROZEN — §0.4's reductio; `dt ≤ 0`; `τ < 0`; `stop ≤ 0` CAGED; NaN `stop` = no
stop, NaN `τ` propagates as an authored input's problem); and the two `-0.0` corners written down
rather than dodged (a frozen head's `-0.0 + 0.0` is `+0.0`; a caged head's zeros inherit the step's
sign, which is ASSERTED harmless because `wrap_angle(az − (−0.0))` is `az`).

### What did NOT ship, deliberately

**The rate limit.** `gimbal_rate_max` exists in the probe and was NEVER EXERCISED by any gate-0 arm
(advisor-confirmed), so shipping it would be a knob with no measurement behind it — the slice-19
dead-knob discipline — and it also cleans up the exact-landing branch. Named deferral. **The
`:truth`-tracking head**, measured at §0.3/§0.5 and recorded there. **Any seam edit**: `missile.jl`
is untouched at gate 1, and the comp keys `:head_az` / `:head_el` are gate 2's.

---

---

## §2 — Gate 2 (COMPLETE, 2026-08-09 — 6295 → 6515, +220)

The seam in `missile.jl::_observe_point3d!`, the loader in `scenario.jl`, and the wired testset.
**FOUR FINDINGS, THREE OF WHICH CORRECT GATE 0's OWN READING OF ITS PROBE** — the probe was a
hand-copy (`gimbal_lib.jl`) and gate 0 said so; what it did not say is which of its columns were
properties of the *variant it flew* rather than of the *head that ships*.

### The seam, and the four disciplines it had to enforce

```julia
_gim = haskey(c, :gimbal_tau_s) && haskey(c, :att_q) && :airframe === :six_dof   # discipline 1
```

1. **RUNG-GATED, never `haskey(:head_az)`** — the SEVENTH occurrence of the slice-21 `_atm_on`
   class. `:head_az` is minted by the seam and never deleted, so a key-gated head would keep
   slewing — and keep indexing the glass — off a FROZEN attitude after a cross-toggle off
   `:six_dof`. ⭐ And the head and the attitude it is measured against are gated by the SAME rung
   (`:att_q` is written only by the rung-gated `_integrate_6dof!`), so they freeze and resume
   TOGETHER — asserted, not assumed, and it converts a "probably fine" into an invariant.
2. **THE HEAD SLEWS BEFORE THE BEND IS TAKEN** (the block sits above the radome).
3. **THE SERVO TRACKS THE BENT, ONE-TICK-DELAYED MEASUREMENT** (`:head_tgt_*`, stored *after*
   `az_m`/`el_m` are formed). ⚠ **There is deliberately NO truth fallback** (advisor): the probe has
   `get(c, :head_tgt_az, look_az_b)`, a TRUTH read on the one path whose whole thesis is that the
   head never sees truth. `:head_az` and `:head_tgt_az` are minted on the SAME tick, so the slew
   branch indexes both directly and the un-exercised branch does not exist.
4. **THE HANDOVER CALLS `head_clamp` UNCONDITIONALLY** — gate 1's Finding 2 made enforceable. The
   probe's per-axis `clamp` is exactly the bug that finding predicted would be copied.

⚠ **THE DETECTOR WINDOW IS EVALUATED TWICE, AGAINST DIFFERENT QUANTITIES, and collapsing them
changes the physics**: the SLEW is gated on the error BEFORE this tick's slew (no error signal, no
slew — the head HOLDS), AVAILABILITY on the error AFTER. The hold is the mechanism behind §0.7's
metric inversion and it is wired, not commented.

### ⚠⚠ §2.0 — THE LOADER REFUSES `seeker_fov_deg` BESIDE A HEAD, AND THAT IS PHYSICS

A gimballed seeker has NO body-fixed window: its body-fixed limit is the mechanical STOP and its
window is the DETECTOR's, about the head axis. Slice 32's key under a head would be an unmodelled
THIRD window — the slice-21 "refused, not branch-ordered" precedent. ⭐ **And it closes a real
defect** (advisor): the `_fov_on` telemetry block rewrites `look_angle` from the TRUTH LOS *after*
the radome block wrote the head-indexed value, so a wire authoring both would silently ship the
NOSE's index where the glass used the HEAD's — the slice-29 stale-readout catch in a new place.
Refusing makes that choice unnecessary rather than silent.

⚠⚠ **AND THE REFUSAL WAS NOT ENOUGH — THE COMBINATION CRASHED THE TICK** (gate-2 review, advisor;
the same shape as gate 1's Finding 2, one layer out: *a constraint stated in a policy is not
enforceable where the policy cannot reach*). A PROGRAMMATIC world can still author both, and the
availability branch then takes its `_gim` arm, leaving `fov_rad` UNASSIGNED — which slice 33's
telemetry block passes to `seeker_fov_margin`. `UndefVarError` inside `observe!`, landing in the
session's IO/EOF-only catch: a silently dropped connection, convention 5's exact failure. ⚠ The seam
comment justified leaving that local unassigned *because* "an unassigned local throws and the suite
catches it" — true only while nothing built the combination, which stopped being true the moment a
head existed. **Fixed with a `!_gim` conjunct on `_fov_on`**, which converts three POLICY claims into
STRUCTURE: the FOV telemetry block cannot run under a head, the `look_angle` clobber is impossible
rather than merely refused, and the `elseif` is unreachable rather than throwing. The loader refusal
STAYS — it is what tells a scenario author which seeker they are building. Both halves are teeth: the
combination now flies (head keys ship, not one slice-32/33 window key does, `look_angle ≠
look_body_deg`) and is BIT-IDENTICAL to the world without slice 32's key — the body window is not
out-ranked, it is INERT.

⚠ **BUT REFUSAL COSTS TWO KEYS GATE 3 NEEDS** (advisor, and it is the non-obvious half):
`lead_angle_deg` and the truth-referenced look angle live ONLY under `_fov_on`. So `_gim` ships them
itself, plus `look_body_deg` (the strapdown quantity slice 32 called `look_angle`, kept under its own
name because slice 26's `look_angle` now carries the HEAD's index) and a SIGNED
`gimbal_fov_margin_deg` — slice 18's `terrain_clearance_m` / slice 33's `seeker_fov_margin_deg`
shape, **THE SIGN IS THE VERDICT**, built from the SAME `fov_h` and `off_head` the flying predicate
tested so the two are the same bits and not two opinions. Decided at gate 2 rather than a gate late,
which is what slice 33's ledger records the cost of.

### ⚠⚠ §2.1 — FINDING 1: §0.2's COLLAPSE DOES NOT REPRODUCE, AND THAT IS THE SLICE

§0.2 measured `max|Δpos| = 0` at τ → 0 and concluded that "the bend keys off head-vs-body" is the
FALSE-FIDELITY class. ⚠ **That arm tracked the TRUTH LOS** (`gimbal_lib.jl`'s default). The head that
SHIPS tracks its own BENT, one-tick-delayed measurement, so at τ = 0 it lands on the PREVIOUS tick's
BENT angle and not on this tick's LOS-vs-body. Measured on the shipped seam, 9 000 ticks:

| R̂ | `max|Δpos|` vs the strapdown `Seeker` |
|---|---|
| −0.03 | **77.10 m** |
| −0.18 | **58.21 m** |
| −0.33 | **55.13 m** |

⭐⭐ **AND IT IS NOT MERELY NON-ZERO — AT τ = 0 THE MARGIN IS ALREADY THERE IN FULL.** The
minimum-lag head, whose only remaining departure from strapdown is the INDEX, reads `rms r`
**0.03394 (QUIET)** where the strapdown seeker reads 0.93194 (RINGING), 27.5×. ⇒ **§0.5's isolation
reproduced at the seam without needing its `:truth` / `:delay` probe arms: THE MARGIN IS BOUGHT BY
THE INDEX.**

⇒ the false-fidelity control §0.2 promised is not available, and **THREE BIT-IDENTITY CONTROLS SHIP
IN ITS PLACE, ALL EXACTLY 0**:

* **A — NO GLASS, NO WINDOW ⇒ inert at EVERY τ** (0.0, 0.05, 0.5). The head reaches the trajectory
  through exactly two channels, the radome's INDEX and the detector WINDOW; this is the structural
  claim that there is no third.
* **B — A WIDE `gimbal_fov_deg` IS BIT-IDENTICAL TO THE KEY ABSENT** — atmosphere.jl's KNOB-vs-RUNG
  discriminator applied to the slice's ONE slider ⇒ KNOB, no rung, button stays dropped. The free
  arms of every table below rely on it.
* **C — A NON-BINDING STOP IS INERT**, which is what licenses the unconditional `head_clamp` at the
  handover.

### ⭐⭐ §2.2 — THE LESSON, WIRED, AND THE BRACKET'S SECOND TELL

Same glass (R₀ = −0.03, A = −0.15), same residual, same seed, τ = 0.05, a 30° stop:

| R̂ | strapdown `rms r` | gimballed `rms r` | `off_max` | `head_max` | miss |
|---|---|---|---|---|---|
| −0.33 | 0.05879 | 0.05917 | 1.599° | 18.117° | 0.161 m |
| −0.27 | 0.03070 | 0.03701 | 1.761° | 18.117° | 0.032 m |
| −0.24 | **0.70983** | 0.02497 | 1.831° | 18.117° | 0.050 m |
| −0.18 | **0.93194** | **0.01181** | 1.956° | 18.117° | 0.187 m |
| −0.17 | 0.95537 | 0.03934 | 3.762° | 18.117° | 3.631 m |
| −0.16 | 0.97044 | **0.35338** | 5.237° | **20.619°** | 5.695 m |
| −0.12 | 1.03165 | 0.70207 | 5.587° | 22.026° | 6.500 m |
| −0.03 | 1.07211 | 0.88465 | 5.916° | 23.601° | 5.246 m |

**THE HEADLINE: 0.93194 RINGS vs 0.01181 QUIET, 78.9×.** Onset bracket **(−0.18, −0.16]** gimballed
against **(−0.27, −0.24]** strapdown — quoted BRACKET TO BRACKET, with −0.17 MARGINAL and pinned as
a NUMBER rather than asserted as a verdict. ⭐ **AND `head_max` STEPS AT THE SAME PLACE** — flat at
18.117° through every quiet arm and 20.619° at the first ringing one: a SECOND tell from a DIFFERENT
quantity, which is what makes the bracket a measurement and not a threshold read off the metric that
defined it. ⚠⚠ **BUT `head_max` IS A FREE-ARM QUANTITY TOO, AND IT FAILS MORE QUIETLY THAN THE
OTHERS** (advisor): on a WINDOWED arm the head HOLDS at the break, so `head_max` freezes at its
pre-break value — every broken arm at R̂ = −0.16 reads **18.117°**, the QUIET arms' number, against
the ring's actual 20.619°. It does not run away like `off_max`; it reads a plausible, wrong,
*smaller* number. Every `head_max` above is off a FREE arm. ⚠ **THE MISS IS NOT THE METRIC** — every
arm on both ladders HITS (< 7 m), the arc's standing fact since slice 26.

### ⚠⚠ §2.3 — FINDING 2: τ IS AUTHORED, BUT NOT FOR §0.4's REASON

§0.4 concluded *"τ does NOT move the onset anywhere in `[0.02, 0.2]` — only the amplitude sags"* and
made that the reason τ is authored. ⚠ **ITS LADDER SKIPPED −0.17 AND −0.16, WHICH IS EXACTLY WHERE
THE BRACKET IS.** The sag is monotone EVERYWHERE, and at the line that same sag crosses the verdict:

| R̂ | τ=0 | τ=0.02 | τ=0.05 | τ=0.10 | τ=0.20 |
|---|---|---|---|---|---|
| −0.18 | 0.03394 | 0.01166 | 0.01181 | 0.01162 | 0.01042 |
| −0.17 | **0.64469** | 0.26854 | 0.03934 | 0.01562 | 0.01261 |
| −0.16 | **0.86787** | **0.62591** | **0.35338** | 0.07508 | 0.02061 |
| −0.12 | 1.01270 | 0.83567 | 0.70207 | 0.57877 | 0.42355 |

⇒ the bracket walks from **(−0.18, −0.17] at τ ≤ 0.02** to **(−0.16, −0.12] at τ = 0.20**. τ is a
**CONFOUNDED LEVER**, which is a STRONGER reason to keep it authored than a dead one: it moves the
amplitude on every arm, so a student dragging it moves the verdict without moving the mechanism.
⭐ **AND THE SLICE'S CLAIM SURVIVES THE WHOLE SPAN** — at EVERY τ the showcase arm is quiet where
strapdown rings, so the margin is not a τ artifact anywhere in the domain.

### ⚠⚠ §2.4 — FINDING 3: §0.7's `⌈off_max⌉` RULE IS SUFFICIENT BUT NOT TIGHT

Gate 0 swept a **1° grid**, on which the ceiling happens to be the first held cell — so it read
*"`⌈off_max⌉` calls the critical window exactly in both rows (2 and 6)"*. On a **0.1° grid** the
−0.16 row holds already at **5.30**, 0.7° BELOW the ceiling. The real predicate is the free arm's own
`off_max`:

| R̂ | free `off_max` | last BREAK | first HOLD | verdict |
|---|---|---|---|---|
| −0.18 (quiet) | **1.955643°** | 1.9550° | 1.9600° | straddled to **0.005°** |
| −0.16 (ringing) | **5.236820°** | 5.2400° | 5.3000° | CONSERVATIVE by ~1 % |

⇒ **SLICE 32's PREDICATE RETURNS IN THE CURRENCY A GIMBAL HAS: `held ⟺ tracking error < detector
window`**, and the two sides come from DIFFERENT RUNS (the error off a FREE arm, the verdict off a
WINDOWED one), which is what makes it a measurement rather than a restatement. ⚠ The ~1 % slack on
the ringing arm is the two-run divergence itself — a windowed arm is a DIFFERENT TRAJECTORY and a
ring diverges faster once it clips. Both directions stated rather than tuned away. ⭐ **AND THE RING
IS SPENT IN DETECTOR WINDOW, 2.7×** (1.956° → 5.237°) — slice 33's payload in the new currency.

### ⭐⭐ §2.5 — FINDING 4: THE STOP AND THE WINDOW ARE ONE BUDGET, NOT TWO LIMITS

**No gate-0 arm could have seen this**: every one ran the stop at 30° or 1e6° against a head travel
of at most 23.4°, so THE STOP NEVER BOUND IN ANY ARM THAT HAS EVER FLOWN — gate 1 wrote that down
as the reason `head_clamp`'s circular shape rests on a species argument. Bind it, and the two limits
are coupled: a clamped head cannot reach the LOS, so its DEFICIT is spent out of the DETECTOR budget.

    off_head ≈ (head travel requirement − stop) + free tracking error

| detector window | critical stop | `off_max` at the first holding stop |
|---|---|---|
| 8° | (10, 11] | 7.133° |
| 4° | (14, 16] | 2.227° |
| 2° | (16, 18] | 1.956° |

against an 18.1172° travel requirement and a 1.956° free tracking error. ⇒ **the plan's "the stop
reproduces slice 33's excursion — a RESTATEMENT" is CONFIRMED AND SHARPENED**: the stop must cover
slice 33's number, and whatever it fails to cover is charged to the window. A stop below the lead is
fatal on its own (100 % out, 3619 m, and the band is EMPTY so `rms r` is undefined — slice 33's own
gate-2 catch).

### ⚠⚠ §2.6 — THE TWO-RUN DISCIPLINE, MEASURED RATHER THAN INHERITED

At R̂ = −0.16 through a 1° window: the miss OPENS **220×** (5.695 → 1254.83 m) while `rms r` FALLS
**4.2×** (0.35338 → 0.08491) and the arm's own `off_max` reads **89.2°** — the post-lock-loss runaway
— against the ring's actual 5.24°. ⇒ **NO STABILITY VERDICT MAY EVER BE READ ON A WINDOWED ARM**;
the predictor comes off a FREE arm and the predicted off a WINDOWED one, bound at the call sites.

⚠⚠ **THE LIST IS THREE QUANTITIES, NOT TWO, AND THE THIRD IS THE DANGEROUS ONE.** `rms r` FALLS and
`off_max` RUNS AWAY — both visibly wrong. **`head_max` FREEZES** at the value it held when the track
broke, so a windowed arm reads 18.117° where its ring is 20.619°: a plausible number, in range, on
the low side. A gate-3 verifier that reads the excursion off a windowed run gets the QUIET arm's
answer and would report that the ring costs nothing.

### The knob domain — MEASURED here, because the plan filed it to gate 1 (which shipped kernels only)

**`gimbal_fov_deg` ∈ [1, 8]°.** The CEILING because the metric is FLAT above the requirement
(CONTROL B: a wider window is bit-identical to no window at all), and 8 clears the ringing arm's
5.24° with room to see the cliff either side. The FLOOR because below 1° the arm never enters
r ∈ [500, 3000] at all, so a band column would count NOTHING — slice 33's gate-2 catch, live again.
⚠ **The broken regime is NOT monotone in the miss** (1.9° → 546 m vs 2.0° → 569 m, ~4 %) because a
windowed arm is a different trajectory rather than a degraded copy of one; the LESSON is the CLIFF,
which is sharp in both rows, and the domain brackets it rather than resting on that ordering. Pinned
as a fact rather than hidden.

### Class, and what convention 2 got

**4a**, the 10th consecutive RNG-live slice. **Draw count ASSERTED, both bounds** — 2 `randn`/tick on
all four configurations (a config drawing 1 and 3 on alternate ticks could not pass; the topology is
what convention 3 is about, not the mean). Byte-identity read ON THE WIRE rather than off the diff:
the key-absent arms reproduce slices 30/33's ladder to the digit in the suite, and **`slice33_verify`
was re-run against the live server** — `S33V OK`, exit 0, reproducing STATUS exactly (rms r 1.07151 /
0.93167 / 0.70969 / 0.05887, excursions 24.995 / 22.113 / 20.608 / 18.115°, break at t = 1.936 s /
r = 5247.0 m, 3696.892 m and 949×, replay `max|Δpos| = 0.000000`). The remaining 26–32 verifiers
belong at gate 3 beside the shipped wire, the slice-33 precedent.

⚠ Per the gate-1 note, gate 2 did NOT re-verify the `boresight_angle` REDEFINITION — that is
measured three ways already. The three bit-identity claims are separate things and only that one was
skipped.

---

## What ships (gates 1–3, PLANNED)

### The core

* `frames.jl` — the head kernels, beside `look_angles`/`boresight_angle` (measurement geometry in
  the body frame, which is exactly what a head angle is). **SHIPPED at gate 1 — see §1, which also
  records the two things this list got wrong: the angle helper is ONE kernel generalized (with
  `boresight_angle` redefined from it), and the stop needed its own `head_clamp` because the
  handover is a second caller:**
  * `head_slew(head_az, head_el, tgt_az, tgt_el, τ, dt, stop) -> (az, el)` — the first-order servo
    with the mechanical STOP. ⚠ `τ ≤ dt` must LAND EXACTLY by ASSIGNMENT, not by arithmetic
    (`head + (tgt − head)` is not `tgt` in IEEE doubles, and §0.2's bit-identity claim is the
    slice's own false-fidelity control — the tooth must be able to pass).
  * the detector's off-head-axis angle — the quantity the head's window is compared against. ⚠
    **CIRCULAR, like `boresight_angle` and unlike the per-axis glass**, for the same reason: a
    detector window is one window about one axis. ⚠⚠ **DO NOT SHIP A SECOND ANGLE-MAGNITUDE HELPER
    BESIDE `boresight_angle` WITHOUT FIRST TRYING TO REDEFINE ONE FROM THE OTHER** (advisor; slice
    33's gate 1 got its cleanest result exactly that way, and `boresight_angle`'s own docstring
    warns about a parallel implementation). It is `hypot` of two wrapped differences, which is
    `boresight_angle`'s shape with the head as the reference axis rather than the nose — gate 1
    decides whether that is one kernel generalized or two, and must say which and why.
* Comp keys `:head_az` / `:head_el`, PARALLEL to `:att_q` / `:omega_body` (the slice-23 precedent),
  minted by the seam and never deleted.

### The seam — three disciplines that must be WRITTEN, not discovered at gate 3

1. **PRESENCE-GATED on `:gimbal_tau_s` AND rung-gated on the LIVE `:airframe === :six_dof`**, never
   on `haskey(:head_az)` — that is the slice-21 `_atm_on` / 23 / 26 / 27 / 32 latent-bug class,
   whose SEVENTH occurrence this would be. The else-arm is slice 33 VERBATIM.
2. **THE HEAD SLEWS BEFORE THE BEND IS TAKEN.** The other ordering leaves a one-tick lag that
   SURVIVES τ → 0 and would fake a mechanism — and §0.5 measured that a one-tick lag is worth
   nothing, so a slice resting on one would be resting on noise.
3. **THE SERVO TRACKS THE BENT MEASUREMENT (`:bent`), AND THAT IS THE SLICE.** Tracking truth is
   both less realistic and a different physics (§0.4/§0.5); slice 27's rule names why. The
   `:truth` variant does NOT ship — it was measured and is recorded here.
4. **THE HANDOVER INIT CALLS `head_clamp`, NOT A PER-AXIS `clamp`** (added at gate 1, §1 Finding 2).
   The servo is a contraction only from INSIDE the disc; the init is the one place a head can be
   born outside it. `gimbal_lib.jl`'s init has the per-axis form — do not copy it.

### Telemetry (all scalars, `_finite*`, shipped ONLY under the gimbal gate — the never-stale rule)

`head_angle_deg` (travel, vs the STOP) · `head_off_deg` (the detector error, vs the WINDOW) ·
`gimbal_valid` · and slice 26's `look_angle` continues to ship the index the glass ACTUALLY used,
which under a head is the head's own angle. ⚠ **`seeker_fov_deg` / `seeker_fov_margin_deg` KEEP
THEIR SLICE-32/33 MEANING** (LOS-vs-body) and the head quantities ship ALONGSIDE — slice 28's
`radome_residual*` precedent. Redefining them would silently rewrite two slices' asserts.

⚠ **SUPERSEDED BY §2.0 — SHIPPED LARGER, AND FOR A MEASURED REASON.** The loader REFUSES
`seeker_fov_deg` beside a head (a gimballed seeker has no body-fixed window), which removes
`lead_angle_deg` and the truth-referenced look angle from the wire entirely — so `_gim` ships them
itself, plus `look_body_deg`, `gimbal_fov_deg`, `gimbal_stop_deg` and a SIGNED
`gimbal_fov_margin_deg`. The "keep their meaning" instruction is satisfied by ABSENCE rather than by
coexistence.

### Convention 9 and the knob count

ONE live slider: **`gimbal_fov_deg`** (the detector window) — **and §0.7 measured that it BINDS
rather than assuming it** (critical 2.0° quiet / 6.0° ringing, with a sharp cliff either side, so
the domain has real range). `gimbal_tau_s` and `gimbal_stop_deg` are AUTHORED — τ because §0.4
measured it does not move the onset over any realistic band (the dead-knob discipline applied before
the knob exists), the stop because it reproduces slice 33's excursion and is therefore a
RESTATEMENT. Domain to be MEASURED at gate 1; the non-monotone `head_max` peak of §0.3 and the
acquisition transient of §0.8 are the two constraints to bracket against.

⚠ **CORRECTED AT GATE 2 ON BOTH COUNTS.** The domain was MISFILED to gate 1, which shipped kernels
only — it is measured at §2, `gimbal_fov_deg ∈ [1, 8]°`. And τ's authored-ness rests on §2.3's
reading, not §0.4's: τ DOES move the bracket at the line (§0.4's ladder skipped −0.17/−0.16), so it
is a CONFOUNDED lever rather than a dead one — a stronger reason for the same decision. §2.5 also
CONFIRMS the stop's "restatement" status by binding it for the first time in the slice's history.

### Class and the button

**4a** (RNG-live, draw-invariant — no new draw; the head is a deterministic servo on an existing
measurement), the 10th consecutive. ⚠ **The button is expected DROPPED (10th)** but needs a
MECHANISM, not an assertion — slice 32's finding. This wire raises `radome_view` AND a new gimbal
marker, so the composition branch of slice 33's HUD is the starting point and the verdict helpers
must be re-examined: **slice 33's HUD compares LEAD vs WINDOW, and under a head the window the lead
is compared against is the STOP, while the DETECTOR window is compared against the tracking error.
A HUD that keeps slice 33's single comparison will print a verdict on the wrong pair.**

### The wire (proposed — gate 1 confirms)

Slice 33's wire held: glass R₀ = −0.03, A = −0.15, vy = 200, seed 32. **`R̂ = −0.18`** is the
showcase residual — strapdown 0.93194 (RINGS) vs gimballed 0.01181 (QUIET), **78.9×**, same glass,
same residual, same seed. ⚠ `STEPS` must be a MULTIPLE of `emit_every` (convention 14; slice 31 lost
an hour to the silent hang).

### The four proofs (convention 14)

`net/slice34_verify.gd`, `net/slice34_ui_test.gd`, a `Sandbox.tscn` headless smoke-load, a windowed
shot. ⚠ Re-run the 26–33 verifiers ON THE WIRE as the byte-identity check — this slice touches the
index six slices are built on, so reading the diff is not enough.

---

## Deferred (NAMED)

* **THE HANDOVER BASKET as an authored quantity** — §0.8 promoted this from slice 32's named
  deferral to a LIVE constraint on this slice: a caged head's window requirement IS the strapdown
  one until it acquires. What ships here is a HANDED-OVER head, stated as a §1 condition; making the
  handover itself addressable is the successor.
* **A RATE-LIMITED HEAD.** `gimbal_rate_max` is implemented in the probe and was NEVER EXERCISED —
  every result above has it absent. A real head has one, and it is the natural home of a
  slew-rate-limited lock loss.
* **MEMORY TRACK / RE-ACQUISITION.** Once the target leaves the detector window the probe's head
  HOLDS — no error signal, no slew — so the break is TERMINAL. A real head coasts on its last
  inertial rate. This is the same choice slice 32 made for the α-β tracker, now one layer out.
* **A RECTANGULAR / PER-AXIS STOP** — a two-axis gimbal really does have independent mechanical
  stops (slice 32's deferral, sharper here: this slice ships one circular window AND one circular
  stop).
* **THE HEAD'S OWN GYRO** — a rate-stabilized head measures inertial LOS rate directly, which is
  the classical reason gimbals exist and a DIFFERENT mechanism from anything here.
* Everything 26–33 named and did not spend: seeker range / SNR acquisition limits; the handover
  basket as an authored quantity; estimating `R̂` in flight (blocked by 26's P7A, sharpened by 29);
  a 2-D slope `R(look_az, look_el)`; an asymmetric error curve; a SINGLE IMU; gyro NOISE
  (draw-topology, convention 3); per-axis scale factors and misalignment; the out-of-plane
  MANEUVERING target; aero + inertial cross-coupling / departure.
