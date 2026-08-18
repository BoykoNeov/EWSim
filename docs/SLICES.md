# EWSim — the slice digest (one paragraph per slice)

**This file is NOT loaded into context automatically.** It is the middle rung of a
three-level ledger; read the level you actually need:

| You need | Read |
|---|---|
| *What was slice N's lesson, in a paragraph* | **this file** |
| *Slice N's exact numbers, test names, gate-by-gate detail* | `docs/STATUS.md`, grep `## Slice N` |
| *What slice N was planned to be, and its gate-0 probes* | `docs/plans/sliceN.md` |
| *What to build next, and what was already KILLED* | `docs/DEFERRALS.md` |
| *The frozen architecture decisions* | `HANDOFF.md` |

## How to find a slice here

- Slices **1–28** are the bullet list in §2 — `grep -n '^- \*\*Slice 23' docs/SLICES.md`
- Slices **29–40** are the running narrative in §1 — `grep -n 'And slice 34' docs/SLICES.md`
- The arc-level story (which slice opened/closed which arc) is §3.

---

## 1. The current head of the arc (slices 1–40 as one running narrative)

**Slices 1–40 COMPLETE & green — 7222 tests at slice 36 gate 3; slice 37 took it to 7496, slice 38 to 7564, and slice 40 is DONE at 7693.** (⚠ SLICES 39, 41, 42 AND **44** ARE KILL RECORDS, NOT SLICES, and **43 IS A GATE-0 LAW RECORD** — the nulling-loop head servo died at gate 0 (`docs/plans/slice39.md`), the second-order FIN actuator died at gate 0 on reparameterization (`docs/plans/slice41.md`), and the search pattern / acquisition margin died at gate 0 and gate 1 respectively (`docs/plans/slice42.md`). None shipped code; the suite is unchanged at 7693.)
(⚠ the count FELL *at slice 35 gate 3* — 6892 → 6876 — and that direction is accounted for: ~87 new asserts in,
~103 out, because a per-entity scenario sweep collapsed into ONE strictly-stronger exact-set assert. The 6876 →
6988 → 7057 → 7067 → 7222 walk since then is slice 36's four gates.) **The committed roadmap (HANDOFF §10 items 1–13) is DONE; slices 15–36
are into the §11 Tier-A horizon — slice 15 did the actuator/fin half of "6-DOF airframe + actuator/fin dynamics",
slice 16 the rotational half (pitch-plane θ,q), slice 17 the α→lift→γ TRANSLATION-COUPLING half (the real
path-changing `:airframe` toggle), slice 18 TERRAIN MASKING behind a third `:propagation` rung + the client's
FIRST true 3-D view (a user-directed insertion — the inner autopilot shifted to slice 19), slice 19 the CLOSED
INNER LOOP (`a_cmd→α_cmd→δ`) + the flight-condition g-limit, slice 20 INDUCED DRAG — the missile LOWERS ITS OWN
CEILING by maneuvering — slice 21 the EXPONENTIAL ATMOSPHERE: the ceiling you lower by CLIMBING (ρ(z) at
last, so "high altitude" is EARNED language and not a caveat), slice 22 NONLINEAR C_L(α) / TRUE STALL —
the ceiling the AIRFRAME itself sets, which moves the ONE factor of `a_max_aero` that 19/20/21 all left
alone — slice 23 the 6-DOF SUBSTRATE + SKID-TO-TURN: the OUT-OF-PLANE ENGAGEMENT, where the pitch plane's
out-of-plane DISCARD (unflyable BY CONSTRUCTION since slice 19) finally intercepts — `att` becomes a genuine 3-D
quaternion and STT makes lift in TWO body planes at once — and slice 24 BANK-TO-TURN + ROLL-LAG: the `:steering`
rung on the HELD `:six_dof` plant, where BTT makes lift in ONE plane and must ROLL to point it with a finite
τ_roll bandwidth, so against the SAME out-of-plane target STT hit BTT MISSES (you must bank before you turn) —
and the gate-3 correction that its miss is a DOWNSTREAM aero-ceiling miss (the roll lag drives the demand into
the slice-19 ceiling, `aero_sat` 93.2% of the approach vs 0.2% for STT; τ_roll→0 removes both the lag and the
saturation), NOT the kinematic one-liner — slice 25 A SEEKER IN THE 6-DOF LOOP, where slice 11's SCALAR in-plane
seeker leaves the 6-DOF missile blind out of plane and it misses by the full 2000 m cross-range FROM THE SENSOR,
and slice 26 THE RADOME / BODY-RATE PARASITIC LOOP — the arc's NAMED END POINT and the GUIDANCE LIMIT CYCLE slice
15 named, slice 19 deferred and slice 20 hunted and KILLED on the ACTUATOR path: the seeker looks through glass
that bends the LOS by `ε = R·(look angle)`, so the missile's OWN body rate moves the LOS it reports, and past a
LOOP GAIN `N·|R|/ρ ≈ 0.38` the missile SHAKES ITSELF into a sustained limit cycle — with a NOISELESS seeker and
a stationary target — and slice 27 THE RADOME-SLOPE COMPENSATION AUTOPILOT, the ENGINEERING ANSWER slice 26 named
as its own successor: the missile already carries a rate gyro, so feed slice 26's coupling forward with the slope
you BELIEVE you have (`R̂`) and subtract it — and it cancels TO THE ACCURACY OF THAT BELIEF, so what closes the
loop is the RESIDUAL `R − R̂` and slice 26's boundary returns VERBATIM as `N·|R − R̂|/ρ ≈ 0.38`. COMPENSATION BUYS
MARGIN, NOT IMMUNITY: the design requirement stops being "a better radome" and becomes "a BETTER-KNOWN one" —
and slice 28 `R(look)`: THE SLOPE CURVE, AND THE BAND THE ENGAGEMENT VISITS, which cashes the deferral BOTH 26
and 27 named. 26 and 27 both assumed the glass has ONE slope; it does not, and the parasitic loop is closed by
the curve's LOCAL DERIVATIVE at the look angle the missile is actually flying — which belongs to the ENGAGEMENT,
not to the radome. Against a CROSSING target the seeker holds a sustained ~15° lead and parks on steep glass, so
a compensator characterized at BORESIGHT is exactly right where the loop is never closed: the HARDWARE residual
`R₀ − R̂` is EXACTLY 0.000 AND IT RINGS, because the ENGAGEMENT residual `R(look_az) − R̂` is −0.078. "Know your
slope" sharpens into "KNOW YOUR SLOPE CURVE OVER THE BAND THE ENGAGEMENT VISITS".** (−0.078 is the MEDIAN of
that residual; it spans −0.100…−0.052 over the measurement band, and the verifier asserts the whole range.)
**And slice 29 `R̂(look)`: THE SCHEDULE THAT LOOKS THROUGH ITS OWN RADOME — the engineering answer 28 named. Make the
belief a curve too and a question a scalar never had to answer appears: EVALUATED WHERE? The only look angle a
guidance computer owns is the one the radome already bent, so what closes the loop is the residual at the
COMPENSATOR'S OWN INDEX. The core ships BOTH numbers from the SAME frames and they DISAGREE: the shipped k̂ = 10 is a
BETTER model of the glass (bench error 0.014) than k̂ = 17 (0.088, 6.3× worse) and it RINGS while 17 stays QUIET,
because at their own indices they are wrong by 0.052 and 0.012. ⭐ And a PERFECT model (k̂ = k, bench error EXACTLY
0.000000000) still leaves a loop residual of 0.023. Slice 27's rule — compensate with a signal not itself corrupted
by what you are compensating — returns in the RATE domain: THE IMMUNITY WAS NEVER THE DOMAIN, IT WAS THE CONSTANCY
(a scalar has R̂' ≡ 0). ⚠⚠ FOUR GATE-0 REFUTATIONS ARE LOAD-BEARING: "a scalar cannot cancel a curve" is FALSE (the
lead angle is CONSTANT BY CONSTRUCTION on a settled collision course — slice 28's wire holds look_az to a 0.2° band,
so a schedule there IS a scalar, i.e. false fidelity); opening the band with a maneuvering target does not license it
either (the BEST POST-HOC scalar MATCHES the schedule, 1.06/0.97/1.07/1.40×, because the loop needs DWELL at a
supercritical residual and a swept band is visited briefly everywhere — ⇒ THE FROZEN LOOK ANGLE IS THE ENABLING
CONDITION, so 29 keeps 28's geometry and deepens only the GLASS to A = −0.15); ⭐⭐ THE RADOME CONSTRAINT IS ONE-SIDED
(only a NEGATIVE residual rings, a positive one de-tunes) so a scalar at the envelope's worst-case slope is
UNCONDITIONALLY STABLE ⇒ GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY, and slice 27's 0.38/(N·ρ) is a TWO-sided
reading of a ONE-sided constraint — ⚠ that claim is MULTI-ENGAGEMENT and NOT client-drivable, so it is deferred as
the strongest successor (its enabling change is a presence-gated `cross_speed_mps` on ConstantVelocity, exactly slice
18's `alt_hold_m`); and the residual-RANGE mechanism was killed at the operating point. ⚠⚠ A FIFTH advisor catch hit
the centrepiece: a RINGING arm's look band is 7.4–18.7° against the quiet arms' 14.5–15.0°, so no residual may be
quoted as a median there (the ring/quiet VERDICT is always on rms r) — and the ≈0.055 onset had to be RE-MEASURED on
this wire (≈ −0.056, from a constant-R̂ sweep, whose R̂' ≡ 0 makes its residual unambiguous). What IS legitimate on a
ringing arm is comparing the bench and loop numbers TO EACH OTHER, since both come from identical frames — and the
verifier's first run failed at 1.6× using a MEAN OF ABSOLUTES (inflated by the ring's symmetric excursions); the
MEDIAN gives 3.7×. (5500)
**And slice 30 SHIPPED 29's own strongest deferral — THE ENVELOPE, AND THE ONE-SIDED CONSTRAINT — by making the
ENGAGEMENT addressable (a presence-gated `cross_speed_mps` on ConstantVelocity, exactly slice 18's `alt_hold_m`).
⭐⭐ THE HEADLINE IS A RING COUNT, NOT A RATIO: 26–29 each flew ONE engagement, so "the residual" could be spoken of
as a number; here the crossing speed is a SLIDER and the envelope is the worst cell over vy ∈ {0,80,130,200,260,320,
400}. The BORESIGHT-characterized scalar (hardware residual EXACTLY 0.000) rings 6/7; a scalar aimed at the glass's
worst-case slope (`radome_slope_worst` = min(R₀,R₀+2A) = −0.33, READ OFF THE WIRE) rings 0/7 — and gate 0 measured
the same 0/7 across FIVE glass depths (a 3× range of slope span; the shipped verifier flies ONE — attribute it).
⇒ STABILITY IS UNCONDITIONALLY PURCHASABLE WITH A SCALAR (it errs in the HARMLESS direction everywhere),
so GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY. ⚠ SUFFICIENT, NEVER TIGHT — 0/7 already at −0.28, and the
bracket is MEASURED (last decisive ring −0.24/0.709; the boundary between −0.26 [1.06× the line, MARGINAL, NOT
asserted] and −0.27). ⭐ THE BOUND IS NOT FREE ⇒ TWO BOUNDS, STABILITY FROM BELOW AND ACCURACY FROM ABOVE, closing on
each other as the glass worsens: ω_ratio 0.781/0.565/0.404 at A = −0.10/−0.15/−0.20 (the aim point itself moving
−0.23→−0.43). ⚠⚠ THE PRICE IS ON ω_ratio, NOT THE MISS (advisor): gate 0's price column is a PER-TICK CPA and the
verifier reads FRAMES on an ~11 m grid — slice 27's defect. The ONE miss claim is the DOMAIN CORNER, flown at vy = 0
because the de-tune miss is largest where the lead is smallest (21.68 vs 4.24 m; at vy = 200 it is 10.0 vs 0.6 and
would measure the emit rate). ⚠⚠ AND ω_ratio IS A DE-TUNE MEASURE ONLY ON A QUIET ARM, so every price arm asserts
QUIET first. ⚠ ToF VARIES ARM TO ARM (9.4→18.3 s) — a first for this arc: STEPS sized off the SLOWEST arm AND every
arm asserts it REACHED CPA. ⚠ NO new instability/cap/gain — 30 adds an AXIS. ⚠⚠ The HUD discriminator is
`cross_speed_mps`, NOT `radome_slope_worst` (gate 2: the aim point is ADDITIVE on every ripple wire, so 28/29 grow
it). 196/196 quiet-arm grid settles convention 9 for THREE knobs. Class 4a, button DROPPED (6th). (5644)**
**And slice 31 AN IMPERFECT GYRO: THE MARGIN IS A GYRO BUDGET — the §1 approximation 27/28/29/30 ALL named (their
gyro is PERFECT). The compensator multiplies a GYRO READING by a believed slope, so make the reading real —
`ω̃ = (1+s)·ω + b` — and THE TWO ERROR TERMS OF ONE SENSOR LAND IN TWO DIFFERENT CURRENCIES: a SCALE FACTOR is
common-mode on the product, so the belief reaching the loop is EXACTLY `R̂(1+s)` (back onto the RESIDUAL — a
STABILITY boundary, ONE-SIDED like 26/30's), while a BIAS injects a constant `R̂·b` — THE ARC'S FIRST ADDITIVE
ENTRY — which moves the AIM POINT and has no residual to move. ⇒ SLICE 30's "SUFFICIENT, NEVER TIGHT" MARGIN IS
NOT SLACK, IT IS A GYRO BUDGET: its conservative aim point tolerates −21% of scale factor, a design SHARPENED to
the measured onset tolerates ~3%. ⚠⚠ THE ADVISOR'S BLOCKING RISK FIRED BEFORE ANY CODE: the scale-factor half is
EXACTLY a reparameterization of a SHIPPED KNOB (`(R̂,s)` flies the SAME MISSILE as `(R̂(1+s), perfect gyro)` —
max|Δpos| 7.76e−10 m on the wire), i.e. the FALSE-FIDELITY class (15's `k_δ`, 19's dead `speed`), so it ships as a
TOOTH and the slice is a DESIGN-RULE slice ⚠ pinned as an `atol`, NEVER bit-identity. The wire OPENS RINGING on a
COMPETENT-LOOKING design (R̂ = −0.27 sharpened past the onset −0.260, s = −0.05 = a real cheap-MEMS error ⇒ the
loop sees −0.2565, rms r 0.42395) and has ⭐ TWO CURES, ONE SLIDER EACH: `s → 0` (13.3×) or `R̂ → radome_aim_gyro`
= R_worst/(1+s) (7.2×) with the SAME bad gyro — and cure B's effective belief lands on `radome_slope_worst`
EXACTLY. ⭐⭐ THE OTHER CURRENCY: a bias NEVER rings across its whole domain, both signs, at slice 30's aim point
(aero_sat 0 on every arm) while the miss moves 7500× ⚠ BUT "NEVER RINGS" WAS TOO STRONG — it STEERS the missile,
moving the LOOK ANGLE and hence the ENGAGEMENT residual (slice 28's mechanism THROUGH THE SENSOR), so on a
MARGINAL design 0.005 past the onset b = −0.02 RINGS it and b = +0.02 does not. ⇒ THE MARGIN IS MEASURED TWICE,
IN BOTH CURRENCIES. ⭐ The one claim only the BIAS can produce: TWO CURES, AND ONLY ONE IS FREE — designing
deeper costs 1.97× the aim-point error of buying a better gyro ⚠⚠ measured on `los_azdot_true`, NEVER on
`gyro_inject_az` (= `R̂·b`, whose ratio is arithmetic — the verifier's first draft asserted exactly that
tautology). ⚠⚠ AT REALISTIC GYRO GRADES NEITHER TERM MATTERS (2.1 °/hr moves rms r by 0.00001) — the slice-15
"lack of effect IS the lesson" shape, QUANTIFIED, and the reason the pencil-sharpening pair is the headline;
domains are chosen for VISIBILITY, not realism, and the scenario says so. ⚠ Slice 27/28's `radome_residual*` KEEP
their meaning — the gyro-effective residual ships ALONGSIDE (advisor). ⚠ The SHOT caught a real client defect
(the verdict compared `R̂(1+s)` against the SLIDER-side aim point — opposite sides of the (1+s) factor). ⚠⚠ AND A
HARNESS TRAP WORTH MORE THAN THE HOUR IT COST: `STEPS` MUST BE A MULTIPLE OF `emit_every` (15000 with emit 16 ⇒
the last frame is t = 14.992 and the verifier waits forever for 15.000, hanging SILENTLY — it reads exactly like
a slow wire; the core runs 27k ticks/s and the verifier drains 5k). Class 4a (7th), button DROPPED (7th). (5798)**
**And slice 32 THE SEEKER'S FIELD OF VIEW: THE ENVELOPE IS SET BY WHAT THE SEEKER CAN SEE — the deferral EVERY ONE
of 26–31 named and each one sharpened. Those six made the LOOK ANGLE their central quantity and then bounded every
knob domain by it reaching 30°, declared FIVE TIMES as a §1 MODEL-VALIDITY caveat. A real seeker makes that same
angle a PHYSICAL STOP: past its field of view there is NO MEASUREMENT AT ALL. ⇒ the caveat and the hardware
coincide, and the arc's FIRST SENSOR-SIDE CAP lands (every earlier cap is airframe or actuator: 10/12's magnitude
clamp, 15's jerk/deflection, 19's flight-condition ceiling, 22's interior peak). ⭐⭐ AND WHAT IT CAPS IS THE
ENGAGEMENT, NOT THE ACCURACY: a crossing target must be LED, the lead is the collision triangle's own closed form
(`V_m·sin λ = V_t·sin θ`, shipped live as `lead_angle_deg`), and the missile must hold it ALL THE WAY IN — so THE
FOV A SEEKER NEEDS IS NOT A SEEKER NUMBER, IT IS THE ENGAGEMENT'S, and a field of view costs you not ACCURACY but
the ENVELOPE. ⭐ TWO CURES, ONE SLIDER EACH, AND THE ASYMMETRY IS THE PAYLOAD: widen the seeker (free — you KEEP
the engagement) or slow the crossing (not free — you DECLINE it). Wire (seed 32, frames, r > 200 gate, closing
leg): fov 25 vs vy 400 BREAKS at t = 4.688 s / r = 4120 m WHILE THE LEAD IS STILL BUILDING, 67.98% out of window,
miss 1504.7 vs 0.480 (fov 30) and 1.126 (vy 320). ⭐⭐ THE ENVELOPE IS A PREDICATE — `held ⟺ lead < fov` over SIX
cells from BOTH directions (19.52° flies 20, 23.76° breaks 20 and flies 25, 28.89° breaks 25 and flies 30) — and
the two quantities come from DIFFERENT CODE PATHS (`collision_lead_angle` vs `seeker_in_fov` on `boresight_angle`),
so it is a measurement, not a restatement. ⚠⚠ THE SIGNATURE IS 23's AND 25's AND THE MECHANISM IS NEITHER: both
left `max|y| = 0.0` EXACTLY (thrown away; never formed), and `fov = 0` reaches it by a FOURTH route — here it WAS
formed and flown (`max|y|` 8125 m) and the SENSOR STOPPED SUPPLYING IT MID-FLIGHT ⇒ `max|y|` is the tooth, the
~2000 m miss is not. ⚠ THE METRIC IS THE MISS AND THAT INVERTS 28–31's (losing the measurement CUTS the parasitic
feed, so rms r would FALL while the miss OPENED). ⚠ ISOLATION: `aero_sat` and `defl_sat` BOTH 0 in the [500,3000]
band in EVERY arm ⇒ a POINTING miss — full authority, no idea where to point it. ⚠⚠ TWO GATE-3 CORRECTIONS, BOTH
ABOUT *WHERE* A NUMBER IS MEASURED: the 180° knob-vs-rung identity holds ON THE CLOSING LEG and is FALSE by 35.7 m
over the whole run (past CPA the target is BEHIND the missile and a narrow window correctly drops it — the
verifier's first run FAILED here); and ⭐⭐ A BROKEN ARM'S OWN LEAD IS INFLATED BY THE RUNAWAY IT IS IN (32.69° vs
28.89° at the same crossing) — SLICE 29's P10a IN A NEW QUANTITY, so every demand is read off the arm that HELD,
and the inflation is itself asserted. ⚠⚠ P5 WAS AN ADVISOR BLOCKING CHECK THAT FIRED: the 18.12° never-acquires
floor is the AUTHORED LAUNCH ATTITUDE, not a seeker property (it tracks the tick-1 look angle to 0.008°), which
KILLED the "max of two curves" framing and set the domain floor above the cliff. ⚠ Gate 2's blocking catch would
have shipped 0.0 (gating `look_angle` on `_rad_on || _fov_on` reads slice 26's radome-else-arm ZEROS on a wire with
no glass — the stale-readout class, 7th). ⚠ SCOPE: a STRAPDOWN window, NOT a gimbal servo (a head with its own
state would REWRITE 26–31's `look_az`) — the strongest successor is THE GIMBAL ON THE RADOME WIRE, measured here as
a corollary and kept off the showcase by convention 9: a compensator that RINGS can shake the seeker out of its own
window (3774.6 m at fov 20), AND SLICE 30's DESIGN RULE PREVENTS IT — aim R̂ at `radome_slope_worst` and the same
glass flies the same window, bit-identical to no window at all ⇒ the FOV bound is NOT tighter than the stability
bound. ⚠ NOT zero client code: the plan asserted "button DROPPED" and named no MECHANISM — a FOV wire holds
`seeker_axes`, so without a marker it inherits slice 25's cycler, whose `:pitch_plane` leaves the WINDOW LIVE
beside an unrelated 2000 m miss. A NEW `seeker_fov_view` marker drops it (Option-P′, 8th; BOTH sites), proven BY
MIRROR. Class 4a (8th consecutive RNG-live), button DROPPED (8th). (6028)**
**And slice 33 THE RING IS AN FOV BUDGET ITEM: WHAT THE PARASITIC LOOP COSTS YOU IS THE ENVELOPE — the successor
32 nominated (⚠ its name is LOOSE and this did NOT inherit it: a REAL GIMBAL is a separate, bigger slice and this
stays STRAPDOWN). Slices 26–31 each recorded, as a standing fact, that THE RINGING ARM STILL HITS — which is WHY
the whole family measures rms q / rms r — and it is true here too: across three glass depths and the full R̂
ladder NOT ONE ringing arm misses by more than 3.53 m. ⭐⭐ THE RING WAS BENIGN BECAUSE THE SEEKER HAD AN INFINITE
WINDOW. Give it a real one and the SAME glass, SAME R̂, SAME seed misses by KILOMETRES ⇒ THE FOV A SEEKER NEEDS IS
THE ENGAGEMENT'S LEAD **PLUS THE PARASITIC LOOP'S EXCURSION**, the second term continuous and monotone in the
ring (18.14 → 20.62 → 22.12 → 23.92 → 25.01° as R̂ walks from slice 30's rule to slice 28's boresight
characterization). ⭐⭐ THE PAYLOAD: SLICE 30's RULE IS AN ENVELOPE RULE, NOT ONLY A STABILITY RULE — aim R̂ at
`radome_slope_worst` and the requirement returns to 18.14°, the radome-free engagement's own 18.13°, at
A = −0.10/−0.15/−0.20 i.e. DEPTH-INDEPENDENTLY. ⚠ NO new rung/knob/instability/cap/draw — both halves already
flew and both sliders already shipped; what is new is the COMPOSITION, ONE number that measures it
(`seeker_fov_margin_deg`, SIGNED, slice 18's `terrain_clearance_m` shape — the SIGN IS THE VERDICT), and the
design rule. Slice 30's shape precisely. ⚠⚠ GATE 0's OPENING HYPOTHESIS WAS REFUTED AND THAT IS LOAD-BEARING:
the stability onset and the FOV break arrive at the SAME R̂ bracket ⇒ slice 32's "the FOV bound is NOT tighter
than the stability bound on this glass" STANDS; what changes is that the REQUIREMENT becomes CONTINUOUS in the
residual where 32 had one number. ⚠⚠ THE TWO-RUN DISCIPLINE IS THE SHIPPED STRUCTURE, NOT A COMMENT — `rms r`
and `look_max` are BOTH meaningless on a windowed arm (rms r FALLS 4.72× while the miss OPENS 604×; the arm's
own look_max is the ~90° POST-LOCK-LOSS RUNAWAY against the ring's actual 22.1°) ⇒ THE PREDICTOR AND THE
PREDICTED NEVER COME FROM THE SAME RUN, every design flown TWICE, and the FREE read is itself MEASURED
(`out == 0.0` asserted, since a live wire always carries the key). ⚠⚠ GATE 2 PAID FIVE FAILING ASSERTS FOR
"HELD" ≠ BIT-IDENTITY (every held arm leaves the window at r = 0.18–8.55 m as the LOS swings; slice 32's `===`
passed by LUCK OF A WIDER WINDOW) and caught a band metric that would have printed a quiet rms r = 0.00000 FROM
ZERO SAMPLES on the 3.7 km arm. ⚠⚠ GATE 3's OWN FINDING: THE EMIT GRID UNDER-READS THE EXCURSION BY 0.016°,
WIDER THAN THE 0.011–0.05° SURVIVABLE BAND ⇒ the finest cell is BELOW a frame verifier's resolution and stays
per-tick in the suite ([[ewsim-missile-verifier-sampling]] in a NEW quantity — the EXCURSION, not the miss).
⚠⚠ THE ISOLATION INVERTS 32's AND MUST NOT BE COPIED: the FREE ringing arm saturates 80.7% AND HITS (slice 26's
ceiling BOUNDING the cycle) while the broken arm saturates 0.00% and misses by km — saturation discriminates in
NEITHER direction, the WINDOW does; `defl_sat == 0` is what IS invariant. ⭐⭐ CLIENT: the FIRST wire to raise
BOTH `seeker_fov_view` AND `radome_view`, so a COMPOSITION HUD branch on the CONJUNCTION, checked FIRST — the
BUTTON needs NO EDIT at either site (the OPPOSITE of slice 26's "the drop needs BOTH"), but the HUD does,
because slice 32's verdict compares LEAD vs WINDOW and here the lead (~18.1°) FITS the 21° window ⇒ it would
print "IN THE WINDOW — FOV holds the lead" ON THE ARM MISSING BY 3.7 km. THE LEAD NEVER OUTGREW THE WINDOW;
THE RING DID — asserted by calling BOTH helpers on the SAME numbers and requiring them to DISAGREE. ⭐ And BOTH
INSTRUMENTS must stay live on one wire (`_radome_qpeak` + `_fov_lost` are INDEPENDENT `if`s, not a chain — a
chained dispatch freezes one half and prints "loop STABLE" forever). ⚠ The verdict helper takes the RANGE as an
ARGUMENT (else "breaking" fires at a CLEAN INTERCEPT and paints the CURE arm a failure). ⚠ THE SHOT'S AIMING
DEFECT IS THE INVERSION ITSELF: a 4300 m gate cleared the 3696.9 m CPA and still caught the AFTERMATH (look 56°,
ring decayed — the feed is CUT once the seeker stops measuring); re-aimed to 5000 m it shows the MECHANISM.
Class 4a (9th consecutive), button DROPPED (9th). (6215)**
**And slice 34 THE GIMBAL: THE HEAD POINTS WHERE THE GLASS SAYS THE TARGET IS — the successor 32 AND 33 both
nominated (⚠ BOTH HALVES OF THE BANKED DEFERRAL WERE REFUTED AT GATE 0 and the live claim was found in a THIRD
place — the slice-33 shape exactly). Slices 26–33 built the parasitic loop on ONE geometric fact: the radome bends
the ray by an amount set by the LOOK ANGLE, and the look angle is the LOS off the missile's OWN NOSE — a quantity
it can only move by ROTATING, which is why slice 26 is a BODY-RATE instability. ⭐⭐ A GIMBALLED SEEKER BREAKS THAT
IDENTITY: the ray passes through the part of the dome the HEAD is aimed at, and THE HEAD IS AIMED BY THE VERY
MEASUREMENT THE DOME JUST BENT. The index of the glass becomes a FIXED POINT of the glass, so slice 26's loop is
partly RE-CLOSED THROUGH THE HEAD, where its sign is NEGATIVE. ⭐⭐ THE HEADLINE IS A COMPARISON BETWEEN TWO WIRES
AND THAT IS WHY THE SLICE SHIPS TWO SCENARIOS (slice 22's precedent): a head is NOT a fidelity — `gimbal_tau_s` is
AUTHORED and NO in-domain slider removes a head, τ → 0 least of all (the shipped head tracks its own BENT,
one-tick-delayed measurement, so at τ = 0 it is STILL QUIET at 0.03394 — ⭐⭐ WHICH IS ALSO THE ISOLATION: at zero
servo lag the margin is already there IN FULL ⇒ THE MARGIN IS BOUGHT BY THE INDEX, not the servo). Same glass
(R₀ = −0.03, A = −0.15), same R̂ = −0.18, same seed 32: the STRAPDOWN twin rings at rms r 0.93167 and the GIMBALLED
wire sits at 0.01207 — 77.2× frame / 78.9× per tick — and BOTH HIT. ⭐ THE ONSET WALKS TWO RUNGS OF THE SAME LADDER
FROM THE SAME SLIDER — (−0.27, −0.24] strapdown vs (−0.18, −0.16] gimballed, quoted BRACKET TO BRACKET (the gap
spans 0.06–0.11, so "≈0.08" is a number neither wire supports) — and `head_max` STEPS AT THE SAME PLACE, a SECOND
tell from a DIFFERENT quantity. ⚠ AND IT IS NOT FREE IN THE ONE CURRENCY A GIMBAL HAS: SLICE 33's SINGLE NUMBER
SPLITS IN TWO, a STOP (the head's TRAVEL — slice 33's excursion RESTATED) and a DETECTOR WINDOW (about the head
axis — NEW, and where the margin is paid for), and gate 2 measured the two are ONE BUDGET. ⭐⭐ SLICE 32's PREDICATE
RETURNS IN THE NEW CURRENCY, `held ⟺ tracking error < detector window` (bracketed to 0.005° quiet, CONSERVATIVE
~1% ringing, the two sides from DIFFERENT RUNS), and ⭐ THE RING IS SPENT IN DETECTOR WINDOW, 3.7×. ⚠⚠ THE TWO-RUN
DISCIPLINE'S LIST IS THREE QUANTITIES AND THE THIRD FAILS QUIETLY: a broken window FREEZES the index and a frozen
index makes a CONSTANT bend (quiet at every R̂), so rms r FALLS and the tracking error RUNS AWAY to ~90° — both
visibly wrong — but `head_angle_deg` FREEZES at the QUIET arms' 17.190° against the ring's 20.616°: plausible, in
range, TOO SMALL. ⚠⚠ GATE 3's FIRST FINDING WAS A BLOCKING CLIENT DEFECT NO TEST WOULD HAVE CAUGHT (advisor, before
any gate-3 code): the loader refuses `seeker_fov_deg` beside a head, so a gimbal wire raises `radome_view` and NOT
`seeker_fov_view` ⇒ both FOV branches fail and slice 26/27/28's RADOME CASCADE takes it — the stale-readout class's
WORST form, because NOTHING IN IT IS STALE (every key that cascade reads is LIVE here), so it would print a fluent
verdict about the GLASS on a wire whose subject is the HEAD. ⇒ a NEW `gimbal_view` marker + a branch checked FIRST;
⚠ gate 3 is therefore a CORE edit, unlike slice 33's, and the BUTTON still needs no edit at either site. ⚠ THE
DEFAULT WINDOW IS A FREE READ *ON THE APPROACH* AND NOT BIT-IDENTICAL (9.15e−11 m at 4° vs EXACTLY 0 at the 8°
ceiling — the window is reached in the last metres as the LOS swings), and ⚠⚠ THE `held` TOLERANCE IS A FUNCTION OF
THE WINDOW (the verifier's first run FAILED at slice 33's flat 1e−6: a 2.05° window moves the CPA 0.020 m where the
shipped 4° one moves it 1e−10). ⭐ THE HANDOVER IS VISIBLE IN THE INDEX TRIPLE — `look_angle` is the HEAD's angle
every tick and the NOSE's on tick 1 ALONE, which is the handover, pinned as `same_ticks == [1]`. ⭐⭐ THE ISOLATION
IS NEITHER 32's NOR 33's: at the same R̂ the twin saturates the slice-19 ceiling 48.36% while the gimbal wire
touches 0.00% ⇒ THE DIFFERENCE IS THE INDEX, NOT AUTHORITY (`defl_sat == 0` is what IS invariant). Class 4a (10th
consecutive), button DROPPED (10th). (6628)**
**And slice 35 A RATE-LIMITED HEAD: THE BANDWIDTH THAT HOLDS THE TRACK IS THE BANDWIDTH THAT FEEDS THE LOOP — the
deferral slice 34 named SECOND. Slice 34's head was INFINITELY FAST (`head_slew` moved it a full first-order step
every tick with no bound on how far). A real gimbal has a servo with a maximum slew rate, and the moment it does the
head's motion stops being free — it becomes a RESOURCE spent against a demand, and ⭐⭐ THE DEMAND IS SET BY THE
PARASITIC LOOP: on a settled collision course the LOS barely moves in the body frame, so a quiet design asks for
0.562 °/s in the engagement band, while ONE RUNG UP SLICE 34's OWN ONSET LADDER the same head must chase its own
oscillation at 32.418 — **57.7×, across a bracket the R̂ slider walks**. ⭐⭐ AND THIS IS THE ARC's FIRST TWO-SIDED
KNOB: 32, 33 and 34 all end *"widen it — it's free"*, and THAT CURE DOES NOT TRANSFER, because servo bandwidth is
not a window, it is what the loop FEEDS ON. Walk the slider 60 → 8 °/s and the RING is attenuated 0.88479 → 0.38556
(2.29×, MONOTONE across all five rungs) while the tracking error it must cover GROWS 5.915 → 12.825° (2.17×) — one
knob, two bounds, NO FREE DIRECTION. ⚠ Quoted ENDPOINT TO ENDPOINT: the interior is NON-MONOTONE (13.244° at 15 °/s
against 12.825 at 8) and PINNED POSITIVELY, the ~5th occurrence of that pattern after 19/20/22/28. ⭐⭐ THE SHARPEST
SINGLE PAIR IS A 0-vs-97 SPLIT AT ONE SERVO: at 8 °/s slice 34's shipped design saturates its rate limit on
**0.00 %** of the band and this wire's boresight-characterized default on **96.98 %** — and THAT is what the domain
FLOOR is chosen on (a servo simultaneously FREE for a good design and BINDING for a bad one, a stronger reason than
"it stops being a servo"). ⭐ SLICE 30's RULE PAYS A THIRD TIME (33 = FOV, 34 = detector window, 35 = SERVO
BANDWIDTH): at `radome_slope_worst` the requirement moves 0.0019° across the WHOLE rate domain and the limit binds
0.00 % at both ends ⇒ aim R̂ at the glass's worst-case slope and fly the cheapest servo in the catalogue.
⚠⚠ THE BREAK IS NOT THIS SLICE's CLAIM — the advisor's own ship/no-ship gate came back NEGATIVE at gate 0 (a WIDER
window rescues a rate-limited arm ⇒ the break is slice 34's mechanism), so the novelty is the REQUIREMENT and the
TRADE, RELOCATED rather than defended. ⚠⚠ AND THE QUIET END IS A REDUCTIO: past ~5 °/s the limit binds on 100.00 %
of band ticks — an OPEN-LOOP RAMP, quiet for slice 34's FROZEN-HEAD reason — so its 43× is UNQUOTABLE and that is
what sets the FLOOR. ⚠⚠ GATE 2's FINDING SETTLED THE KNOB COUNT: a rate limit makes the ACQUISITION TURN the
binding requirement (`off_band` 1.956 → 2.022 while `off_max` TRIPLES to 8.051 out at LAUNCH RANGE, and the same
happens with NO GLASS AT ALL) ⇒ `gimbal_fov_deg` — slice 34's ONE live slider — goes AUTHORED AND WIDE, on a NUMBER.
⚠⚠ AND GATE 3's BLOCKING FINDING WAS THAT THAT NUMBER RESTED ON A COARSE GRID OF A QUANTITY ALREADY MEASURED
NON-MONOTONE IN BOTH SLIDERS (advisor, before the YAML): re-flown over **184 cells**, the coarse answer SURVIVED —
the surface is maximal at the CORNER at 19.279° — so the window is authored at 25.0 and the verifier DERIVES "the
corner IS the maximum" from its own arms rather than trusting the grid. ⚠⚠ THE MARKER-HOLE RE-CHECK CAME BACK
**NEGATIVE** and the failure it prevents is an **INVISIBLE SLICE, NOT A WRONG NUMBER**: a slice-35 wire is a
slice-34 wire PLUS one key, so `gimbal_view` routes it correctly and the subject is right — but slice 34's HUD pairs
the tracking error against a DETECTOR WINDOW that never binds here, so it would print a comfortable budget, name the
INDEX, and never mention the SERVO. ⭐⭐ ON ONE STATE IT IS WORSE THAN SILENT: when a slow servo has BOUGHT the ring
down, slice 34's helper reads "SELF-INDEXED — the loop is quiet", CREDITING THE INDEX FOR A QUIET THE BANDWIDTH PAID
FOR. ⇒ `gimbal_rate_view` is a BRANCH SELECTOR, not a hole plug, and the distinction is written into four files.
⚠ A VERIFIER TOOTH THAT PASSED 12/12 WAS A TAUTOLOGY (advisor, post-green — the flag and the demand-vs-cap are the
same comparison rearranged); it is KEPT with its claim downgraded to a units check, and ⭐ THE TOOTH WITH CONTENT IS
THE ZERO (a 0.0 demand is the HANDOVER tick or a HELD head, so `head_rate_sat` reads FREE on a broken arm for the
reason `rms r` reads QUIET — the two-run discipline's FOURTH quantity, now asserted EMPTY in band). ⚠ The client's
new instrument is a THIRD SHAPE beside slice 27's peak-hold and slice 32's latch — an EMA DUTY, earned because a
rate limit binds on a FRACTION of ticks. ⚠ SHOT B WAS RE-TAKEN: a raw `set_param` moves the PHYSICS while the
slider label keeps the old number — a LYING PICTURE on a green run, slice 19's press-the-button lesson in a new
widget. ONE wire (the claim lives inside one slider's domain). Class 4a (11th consecutive), button DROPPED (11th).
(6876)**
**And slice 36 THE HANDOVER BASKET: THE CHEAPEST PLACE TO HAND A SEEKER ITS TARGET IS NOT AT THE TARGET — the
deferral slice 32 named as its P5, slice 34 promoted to a LIVE CONSTRAINT and slice 35 sharpened into the family's
strongest remaining candidate. Since slice 34 the head has been handed its target PERFECTLY (tick 1 initialises it
to the clamped TRUTH look angles — a truth read on a path whose whole thesis is that the head never sees truth),
and slice 35 found the resulting ACQUISITION TURN to be the largest slew demand in the whole engagement and gated
it away with a band and a wide window. Make the handover an AUTHORED SIGNED ERROR and the question that was gated
away has an answer nobody in the arc predicted. ⭐⭐ THE WINDOW A SEEKER NEEDS IS NOT `|err|`: the body-frame LOS is
NOT A FIXED TARGET — it travels **+18.11° → −15.15°, a 33.2° EXCURSION THROUGH ZERO** — so a head handed over ON
the LOS must chase that whole journey (a rate-limited servo falls 12.35° behind) while one handed over PART-WAY
ALONG IT starts with a head start. The requirement is a **V**: left arm `|err|` EXACTLY (the tick-1 peak, an
INITIAL CONDITION, before the servo has done anything), right arm the CHASE COST, and the cheapest basket is the
KINK — which the SERVO MOVES (argmin −2 → −4 → −8° as it slows 60 → 8 °/s, a 1.54× saving). ⭐⭐ THE SHOWCASE IS A
BASKET THAT EXCLUDES THE PERFECT HANDOVER: at 8 °/s behind a 10° window err = 0 loses the track and misses by
**3290.079 m** while err = −6 HOLDS and hits — and −10 breaks again the other way, so ZERO IS OUTSIDE THE SET THAT
HOLDS. ⭐⭐ AND THE BIAS BUYS WHAT SLICE 35 SAID COULD NOT BE BOUGHT: slice 35's servo was the arc's first TWO-SIDED
knob with no free direction, and here the biased wire reads **FLAT 6.00000° over 100 of 105 fine-grid cells** —
A CORRECTLY BIASED HANDOVER MAKES THE SERVO RATE STOP MATTERING, because no bandwidth touches an initial
condition. ⭐ AND IT IS FREE IN ACCURACY, BIT-EXACTLY (`miss === 0.19116048719212922` and the same CPA position to
17 digits across the whole domain — slice 32's asymmetry with the cost column at 0). ⚠ NOT slice 33's second term
and NOT a radome claim: the break is GLASS-INDIFFERENT (3620.131 with the glass vs 3620.675 without) and the wire
carries NO GLASS — the arc's first since slice 25 — so the budget 32 and 33 built gains a THIRD term:
`window ≥ the ENGAGEMENT's lead (32) + the LOOP's excursion (33) + THE HANDOVER BASKET (36)`. ⚠⚠ THE KEY IS
STRUCTURALLY A DEAD KNOB (consumed once at tick 1 — slice 19's `speed`, 5th in this arc, and the FIRST caught
BEFORE the key was written), so it is AUTHORED, `_parse_knobs` refuses it BY NAME (the project's first by-name
refusal — the existing guard could not have caught it, because this one IS a comp key), and the contrast is TWO
SCENARIOS with slice 35's servo as the ONE slider. ⚠⚠ THE WINDOW's CRITERION IS INVERTED FROM SLICE 35's (it must
SIT INSIDE the requirement's range on one wire and ABOVE it on the other), re-flown over 210 cells at 0.5 °/s
because the requirement is NON-MONOTONE in both sliders: the ≥-window set is EXACTLY FIVE CELLS, CONTIGUOUS and
anchored at the slow end, and the crossing is a MEASURED bracket 10.0 → 10.5 °/s. ⚠ THE FLOOR IS SLICE 35's NUMBER
FOR A DIFFERENT REASON (its ring-based justification does not survive the loss of the glass — 20.6 % band
saturation at 5 °/s, not 100 %): what bounds it is the BIASED wire's own claim, which FAILS at 6 °/s ⇒ THE BIAS
BUYS MARGIN, NOT IMMUNITY. ⚠⚠ THE BUTTON DROP WAS NOT FREE AND THE PLAN PREDICTED IT WOULD BE: `radome_view` is
keyed on authored GLASS, so on the arc's first no-glass wire BOTH client drop-branches fail and slice 25's cycler
returns ⇒ `gimbal_handover_view` does slice 34's job AND slice 32's (the drop needs BOTH sites, 4th occurrence),
and slice 35's "a branch selector, not a hole plug" DOES NOT TRANSFER. ⚠ Its HUD half is the STALE-READOUT class's
9th occurrence, landing on slice 35's own CURE line (`R̂ +0.000   aim point R₀+2A +0.000` for keys that do not
exist). ⭐⭐ A THIRD TELEMETRY KEY SHIPPED AT GATE 3 because the HUD could not otherwise draw the mechanism: every
shipped head angle is a `hypot` and A HYPOT CANNOT SHOW A SIGN (gate 0 read the excursion as a 3° "settle" off
`head_max` and was WRONG — the #1 SIGN TRAP's 10th occurrence), so `look_body_az_deg` is SIGNED. ⚠⚠ EVERY
EXCURSION FIGURE CARRIES ITS GRID: **+18.11° → −15.15° (33.2°) PER TICK** (gate 0 / the core suite) against
**+18.003° → −15.179° (33.182°) PER FRAME** (the verifier and both shots — the first frame is 16 ms after the
handover tick and lands 0.102° below it), and the verifier's frame constant was first mis-named `AZ_BIRTH` behind a
tolerance wide enough to hide that gap — slice 21/25's frames-vs-ticks defect in a CONSTANT rather than a print. ⚠⚠ THE ENDGAME
ARTIFACT NOW APPEARS IN THREE QUANTITIES WITH TWO DIFFERENT GATES, each caught by a FAILING assert: the running
max hits 179.4998° at CPA on EVERY arm (⇒ the client FREEZES its display, a FOURTH instrument shape), the core's
excursion tooth read 182.02° ungated by RANGE, and the verifier's read 359.778° ungated on the CLOSING LEG (the
azimuth wrapping through ±180° — slice 32's gate-3 correction verbatim). ⭐⭐ AND THE EXCURSION IS THE TWO-RUN
DISCIPLINE's SIXTH QUANTITY: 33.182° on a HELD arm against 110.473° (~3.3×) on the broken one. ⭐⭐ THE SHARPEST
NUMBER REVISES GATE 2's OWN GO/NO-GO: gate 2 measured the emit grid at 0.03–0.27 % of the deciding margin and
declared slice 33's finding BORROWED — but only on cells whose peak is a SMOOTH interior maximum. On the biased
wire the requirement is ONE TICK WIDE and a client receiving one tick in sixteen under-reads it by 0.247–1.002°
(against 0.009° on the foil) ⇒ gate 2's own rule — re-run the comparison that entitled the claim — applied to
itself. ⚠⚠ AND THE WINDOWED SHOT FOUND A DISPLAY DEFECT NO TEST WOULD HAVE: three LIVE, TRUE numbers whose INVITED
ARITHMETIC was the runaway, under a correct verdict line (slice 33's defect in a new quantity) — plus the 3rd
right-edge overrun after 26/28. TWO wires. Class 4a (12th consecutive), button DROPPED (12th — and the FIRST that
needed an edit to stay dropped). (7222)**
**And slice 37 THE HEAD'S OWN GYRO: A SPACE-STABILIZED SERVO GIVES BACK THE MARGIN THE POSITION SERVO'S
LAG WAS QUIETLY BUYING — the deferral slice 34 named THIRD, and ⚠⚠ ITS OWN WORDING WAS REFUTED BEFORE
ANY PROBE RAN. "A rate-stabilized head measures inertial LOS rate DIRECTLY, the classical reason gimbals
exist" is ALREADY TRUE of the shipped model (`missile.jl:1652` is `az_el(û_tru)`, NOT `look_angles(…)`),
so the seeker has reported INERTIAL angles since slice 25. What is body-referenced is the SERVO, and the
live claim is its REFERENCE FRAME. ⭐⭐ STABILIZING IT REMOVES MARGIN — THE CLASSICAL REASON GIMBALS EXIST
INVERTS ON THIS WIRE — because the position servo's LAG was doing stability work nobody asked it for: it
LOW-PASSES the missile's own body motion out of the radome's INDEX, and slice 26's limit cycle lives at
1.7–2.1 Hz, exactly where a τ = 0.05 s filter is worth 12–16 % of gain and ~30° of phase. ⭐⭐ THE
DEMONSTRATION IS ONE BUTTON PRESS ON A DESIGN THAT WAS ALREADY GOOD: at R̂ = −0.18 (slice 34's own shipped
design) the body-referenced head is QUIET (rms r 0.01195, intercept 2.084 m) and one press — same glass,
same seed, same servo, same handover — makes the SAME missile RING at 1.00094, 83.8× frame, and it STILL
HITS. ⭐ THE ONSET IS FOUND TWICE, ONCE PER SERVO FRAME, quoted BRACKET TO BRACKET (body (−0.170, −0.165]
at 4.32×, space (−0.210, −0.205] at 9.09×) and the two are asserted DISJOINT FROM BOTH SIDES, which is
what makes it ONE ladder walked twice rather than two readings of one boundary. ⚠⚠ THE ONSET RULE IS THE
LARGEST SINGLE-STEP RATIO AND STAYS THRESHOLD-FREE — gate 0's advisor catch, load-bearing here: the body
rung reads 0.17284 at −0.165, an order of magnitude above its own plateau AND BELOW the arc's 0.30 ring
line, so a threshold would have mis-bracketed it; the ~40–45 % of margin given back is quoted as a RANGE
while the ORDER of the rungs is what is asserted. ⭐⭐ THE SLIDER'S FLOOR IS SLICE 30's AIM POINT AND IT IS
WHERE THE BUTTON GOES DEAD (1.022×, both quiet) ⇒ aim R̂ at the glass's worst-case slope and THE
ARCHITECTURE DOES NOT MATTER — the rule pays a FOURTH time (33 = FOV, 34 = detector window, 35 = servo
bandwidth, 37 = the REFERENCE FRAME), and the proof is a control that visibly stops working. ⚠ THE
CEILING'S OBVIOUS JUSTIFICATION WAS TESTED AND REFUTED (the body rung saturates up to 64.6 % past it, but
removing the rate limit moves its ring by at most 1.04× — slice 35's mechanism is NOT leaking in); it
rests instead on the arm where BOTH rungs ring, the only kind on which a demand comparison is legal, and
there the space head RINGS 1.70× HARDER AND ASKS FOR 3.15× LESS PEAK SLEW (0.00 % vs 17.5 % saturated) ⇒
the body-referenced servo's demand is almost all BODY MOTION — ⚠ which does NOT license "the stabilized
head is the cheaper build": cheaper in SERVO BANDWIDTH, dearer in STABILITY MARGIN. ⭐⭐ THE CLIENT FINDING
IS A BUTTON INVERSION THAT REVERSES TWELVE SLICES OF PRECEDENT: 26–36 each had no rung to cycle, so
`radome_view`/`seeker_fov_view`/`gimbal_handover_view` all HIDE the shared button and 32/33/34/35 rode one
for free — `:seeker_head` IS a rung (the first since slice 25) and this wire raises THREE of those drop
markers, so a NEW `gimbal_frame_view` exists to UN-DROP it. ⚠ THE RULE IS NOT "a gimbal marker drops the
button"; it is *the button shows what there is to cycle, and these wires mostly have nothing*. ⚠ GATED ON
THE FIDELITY, not a comp key (the first in this family) and on the KEY not the VALUE — the wire opens on
`:body_referenced`, so a value guard would hide the button on exactly the arm the showcase starts from.
⭐ THE MIRROR IS THE EXACT INVERSE OF SLICE 36's: there stripping the marker made a button APPEAR that had
to be dropped; here it makes it VANISH. ⚠⚠ THE HUD HALF IS AN INVITED SUBTRACTION (slice 36's gate-3
defect in a new quantity): `head_rate_dps` keeps its name across the button and MEANS A DIFFERENT THING ON
EACH SIDE OF IT, and at the ceiling the press makes it FALL 3.15× while the ring RISES 1.70× ⇒ THE FRAME
IS PRINTED INSIDE THE SAME STRING AS THE NUMBER. ⭐⭐ AND THE SHOT CAUGHT A NUMBER LYING, which only a
capture could: the first pair read `ring r −0.019` on the QUIET arm against `+0.021` on the one ringing
84× harder (a limit cycle crosses zero twice per cycle), so the DECAYING PEAK's VALUE now sits beside the
live rate (0.02 vs 1.08, ~54×) — slices 26–36 drew only the tag and that was fine because nothing on those
wires invited a frame-to-frame comparison; HERE THE WHOLE DEMONSTRATION IS TWO FRAMES EITHER SIDE OF ONE
PRESS. ⚠ The same pair caught a 59-char cure line against the ~55 budget (the right-edge overrun's 4th
occurrence after 26/28/36). ⚠⚠ A FRAME VERIFIER STRUCTURALLY CANNOT SEE THE PRESS AND THE FRAME GRID
MISREADS IT: the space→body press shows a 0.939° step in `head_angle_deg` (~16× a normal frame, reading
exactly like a RE-BIRTH) while PER TICK the head moves 0.0074°, ~9× LESS than the tick before — the frame
figure is the SPACE rung's own unity-gain carry-along accumulated over 16 ticks ⇒ THE PRESS IS VISIBLE IN
THE RATE, NOT THE POSITION, and the verifier asserts NOTHING about it (the tooth is per-tick, in
`test_missile.jl`). ⚠⚠ AND THE MID-RUN PRESS ARM NEEDED TWO LEGS because the server DRAINS EVERY QUEUED
COMMAND BEFORE IT STEPS AT ALL — `[step K, set_fidelity, step N−K]` back-to-back applies the toggle at
tick 0 and silently measures a from-launch arm. ⚠ RUNG, NOT KNOB, and the gate is answered by a BOUND
(a 25× faster servo at a 50× smaller τ stops at 4.796° of index gain and cannot reach the stabilized
head's 3.861°). Class 4a (13th consecutive RNG-live), replay bit-identical ON BOTH RUNGS, BUTTON BACK
(the first since slice 25). ⚠ The proofs FIRST ran on port 8770 — an unrelated python process held
8765 — and ✅ the 8765 re-run is DISCHARGED (verifier `S37V OK` reproducing every number to the digit,
and the smoke-load green with BOTH halves captured). (7496)**
**And slice 38 AN IMPERFECT HEAD GYRO: SLICE 37's MARGIN IS A GYRO SPEC — the deferral slice 37
named FIRST. Slice 37's whole result rests on a PERFECT gyro: its stabilized head rejects body
motion at EXACTLY unity gain at every frequency, because the model simply STORES the inertial
angles. Give the gyro a scale-factor error and the rejection LEAKS (`ω − ω̃ = −s·ω − b`, so the
pointing DRIFTS), and ⭐⭐ SLICE 37's STABILITY BOUNDARY WALKS WITH GYRO QUALITY — on slice 37's own
0.005 grid under its own threshold-free largest-step rule, every bracket INTERIOR: s = 0 →
(−0.210, −0.205], which is slice 37's SPACE bracket EXACTLY; −0.02 → (−0.205, −0.200]; −0.05 →
(−0.200, −0.195]; −0.20 → (−0.185, −0.180]; a DEAD gyro → (−0.170, −0.165], which is its BODY
bracket EXACTLY. ⇒ THE TWO ARCHITECTURES SLICE 37 SHIPPED AS A BUTTON ARE THE TWO ENDS OF ONE
HARDWARE SPEC, and A WORSE GYRO IS A MORE STABLE MISSILE: −5 % of scale factor, an ordinary
cheap-MEMS part, gives back a QUARTER of the margin and −20 % gives back FIVE EIGHTHS. ⭐ THE DOMAIN
FLOOR IS A MEASUREMENT (invisible at 1 %, resolves at 2 %), so the claim rests on a real part.
⚠⚠ TWO PREDICTIONS WERE REFUTED AT GATE 0, BOTH LOAD-BEARING: the index gain is NOT `|1+s|` and
`s = −1` is NOT a frozen index (it walks 1.00000 → 0.88608 with phase 0° → −27.578°, landing on the
body rung's own 0.88405 / −27.561° — the error was conflating THE DRIFT CANCELLING BODY MOTION with
THE SERVO BEING OFF, since a head carried by the body is STILL SLEWED by its servo, which IS the
other rung); and THE BIAS WAS TO BE THE HEADLINE AND IS THE WEAK HALF (it needs ~10³× a bad real
gyro — 103 °/hr moves rms r by 0.00064 — while the scale factor is a real part). The bias ships as
the SECOND CURRENCY: a TWO-SIDED knob (43.2× in rms r while the tracking error moves the OTHER way,
2.70° → 0.96°), and ⭐⭐ SLICE 30's RULE PAYS A FIFTH TIME — at the aim point the bias moves the
tracking error 3.9× and the ring moves 1.0×, the FIRST time the rule buys off a SENSOR error rather
than a design choice. ⚠⚠ THREE GATES PASSED BY MEASUREMENT: the BLOCKING one (does the bias collapse
onto slice 32's LEAD axis? the lead holds at 14.59–14.68° across the whole sweep while `head_off`
moves 2.84 → 1.31 and the verdict moves with it); the (s, R) COLLAPSE (20.2× against glass scaled
×0.8, 3.3× the other way against glass AND belief scaled — `s` adds PHASE and scaling a slope
cannot); and ⚠⚠ THE RUNG BOUND, WHICH HELD ONLY IN THE NARROW FORM — the walk REACHES the body
bracket at a dead gyro, so NO CLAIM MAY BE MADE IN THE RING METRIC, and what survives is 1.556 m of
trajectory separation on the ringing arm (0.089 quiet, against 40.29 for the honest pair), two
distinct code paths, and a gyro reading ZERO physically BEING an unstabilized head. ⚠⚠ GATE 1 PAID
TWO WRONG ORACLES THAT BOTH LOOKED LIKE TOLERANCE PROBLEMS: `acos` of a dot product is
precision-limited to ~1.2e−04 rad on a 2e−4 rotation, and predicting the swept angle as `|Ω|·dt` is
WRONG BY CONSTRUCTION (a vector rotated about an axis moves by `|Ω|·dt·sin ψ`) — 24 % on the widest
cell, and swapping the FIRST oracle left the number BIT-FOR-BIT UNCHANGED, which is what exposed it.
Against an independent Rodrigues recompute the kernel is exact to 3.554e−16. ⚠ GATE 2's ORDERING IS
DRIFT-THEN-CLAMP (the head cannot drift THROUGH its gimbal limit, pinned where the stop binds on
5572 ticks) and A GUESS BESIDE IT WAS WRITTEN AS AN ASSERT AND REFUTED BY IT (a perfect-gyro arm
binds that stop slightly MORE, 5582 vs 5572) ⇒ the testset proves the ORDERING INVARIANT and nothing
about causation. ⭐⭐ THE CLIENT IS A MARKER WHOSE ONLY JOB IS THE HUD (`gimbal_gyro_view`, the 8th of
this family): a slice-38 wire raises FOUR earlier route markers and the BUTTON is already correct —
for a REASON, since the two rungs are the two ENDS of this slider's axis — while slice 37's HUD block
would print a fluent, entirely TRUE frame-comparison verdict, plus a cure line naming a slider this
wire does not have, above a lesson about the SENSOR (the stale-readout class's WORST form, ~10th
occurrence). ⭐⭐ AND THE STATE ONLY THIS BRANCH CAN NAME IS A DEAD KNOB — on the body-referenced rung
the slider is BIT-IDENTICALLY INERT (`max|Δpos| = 0.0`), so the HUD says so: A LIVE CONTROL THAT DOES
NOTHING IS THE STALE-READOUT CLASS IN A NEW FORM, not a stale number but a dead one. ⚠⚠ AND THE SHOT
CAUGHT A DEFECT THE UI TEST HAD JUST PASSED — TWO WIDTH BUDGETS, NOT ONE: both new headlines ran off
the right edge (50 and 47 chars) while the width tooth passed at the BODY lines' ~55, because the
headline is drawn LARGER and from a different origin and its budget is ~30 (slice 37's longest is
exactly 30, obeyed by this whole family without anyone writing it down) — the overrun's 5th
occurrence after 26/28/36/37 and the FIRST in a headline. ⚠ FOUR CARRIER/MIRROR ASSERTS FIRED AND
WERE RIGHT TO (slice 35's list earning its keep a THIRD time). ONE wire, ONE slider, and it OPENS ON
THE STABILIZED RUNG — the opposite of slice 37's choice, because the slider's job is to make a
RINGING missile quiet by making its gyro WORSE. Wire: 0.63736 → 0.01967 (32.4×), the ladder MONOTONE
across all 9 cells with a SINGLE 18.8× knee, the ceiling ringing HARDER than perfect. Class 4a (14th
consecutive RNG-live), replay bit-identical at both slider ends, button KEPT (slice 37's). (7564)**
**And slice 40 A HEAVIER GIMBAL: THE SECOND-ORDER HEAD SERVO — the deferral slices 35, 37 AND 38 each
named and none spent. Slices 34–39's head is a FIRST-ORDER LAG with a rate limit; a real gimbal has
INERTIA, so its servo is second-order — and that is a new MECHANISM rather than a refinement, because
of what a lag CANNOT do. Slice 37 measured its whole margin in GAIN (the lag LOW-PASSES body motion
out of the radome's index, 0.882 at the ring's 1.7 Hz against a STRAPDOWN seeker's exactly 1.000), and
⭐⭐ A FIRST-ORDER LAG IS BOUNDED IN BOTH CURRENCIES — gain ≤ 1 AND phase ≥ −90°, at every frequency for
every τ — so it could only ever make the index QUIETER. A second-order servo leaves both bounds.
⭐⭐ THE HEADLINE IS A PAIR OF WIRES WHOSE INDEX GAINS DIFFER BY 32×, AND BOTH RING: on slice 34's own
shipped design (R̂ = −0.18, which the lag flies QUIET at rms r 0.01181), ω_n = 2 Hz / ζ = 0.10 rings at
0.51659 (44×) with an index gain of 3.073 — ABOVE a strapdown seeker's 1.00, i.e. WORSE THAN NO GIMBAL
AT ALL — while ω_n = 0.5 Hz / ζ = 0.10 rings at 0.42414 (36×) with an index gain of 0.095, A TENTH OF
THE LAG's, its phase run out to −176°. ⇒ A SERVO NINE TIMES QUIETER THAN THE SHIPPED LAG RINGS THIRTY-
SIX TIMES HARDER. ⚠⚠ AND THE CONVERSE IS MEASURED TOO, WHICH IS WHAT KEEPS THE CLAIM HONEST: phase past
−90° does NOT by itself ring (0.5 Hz at ζ = 1.0 sits at −147° and reads 0.0184, QUIET) ⇒ the claim
stops at **NEITHER NUMBER, READ AT A FIXED FREQUENCY, ORDERS THE OUTCOME**, and NO loop-crossover
argument is made — because the frequency the loop closes at is the one quantity this gate could NOT
measure. ⭐ THE SENTENCE THE TWO WIRES EXIST TO SAY: **INERTIA IS NOT THE ENEMY, UNDAMPED INERTIA IS** —
the same added inertia buys +0.072 of R̂ of margin at ζ = 1.0 (⚠ quoted in R̂ and NOT in "cells" —
that bracket is on a 0.010 grid extended toward zero, while a cell means 0.005 everywhere else in
this family; onset (−0.100, −0.090] against the
shipped head's (−0.170, −0.165]) and rings at EVERY cell of that grid at ζ = 0.1; THE DAMPING DECIDES
THE SIGN OF WHAT THE INERTIA DOES. ⚠ RUNG (`:head_servo`), and the reparameterization gate slice 39
died on is answered by a BOUND: no τ reaches gain > 1 or phase < −90° analytically, and in flight the
shipped knob's own domain swept 800× over τ ∈ [0.001, 0.8] spans rms r 0.0104…0.0343 and NEVER RINGS,
15× below the quieter second-order arm. ⚠ At large ζ it nearly collapses onto a lag of τ_eff = 2ζ/ω_n
(1.059/1.056/1.016/1.005 — CLOSE, never identical, always the same direction), which is where the
button goes quiet. ⚠⚠ THE DISCRETIZATION IS PART OF THE CLAIM AND IS PINNED (advisor, before the
kernel): the claim lives in the lightly-damped regime, exactly where an integrator's own numerical
damping could masquerade as physics — the step response converges at FIRST ORDER against the closed
form (ratio 10.02 for a 10× dt) and the discrete free response's effective ζ is within 0.0003–0.011 OF
ONE DOMAIN CELL. ⚠⚠ FOUR PREDICTIONS WERE REFUTED AND ALL FOUR ARE LOAD-BEARING: (1) the advisor's
BLOCKING kill-risk — does the TRACK BREAK before the resonance rings? — was flown FIRST and came back
`out_band = 0.00 %` on EVERY arm of every ladder; (2) ⚠⚠ THE RING'S OWN FREQUENCY IS NOT MEASURABLE ON
THIS WIRE, which killed the sharpest available claim (*the loop rings where the gimbal resonates*):
the probe's own CONTROL row failed (0.80 Hz where 26–39 measure 1.7–2.1), and re-flown under slice 26
§P7B's conditions the two estimators DISAGREE on the control itself (0.91 vs 0.23) ⇒ recorded as
UNTESTED, not as refuted physics; (3) "well-damped buys margin" does not generalise — at ζ = 1.0 it
depends on ω_n (0 cells at 5 Hz, +3 at 2, and +0.072 of R̂ at 0.5 — the last on a coarser 0.010
grid, so it is quoted in R̂ rather than in cells), and the 5 Hz row explains itself (τ_eff =
0.0637, within 27 % of the shipped 0.05 — the overdamped collapse arriving in flight); (4) ⭐⭐ THE
SEAM'S OWN PREDICTION, REFUTED AT GATE 2 — the resonance is NOT inert on slice 37's space-stabilized
rung (6.1× on a design that rung flies quiet, `out_band` 0.00 %), because BODY MOTION IS ONLY ONE OF
THE TWO THINGS THIS SERVO IS FED: the other is slice 34's own fixed point (the head is aimed by the
BENT measurement), live on both frames. **A LAG LOW-PASSES WHATEVER IT IS FED; A RESONANCE AMPLIFIES
IT.** ⚠ Its first reading would have been wrong TWICE (at R̂ = −0.18 that arm shows rms r FALLING while
the miss opens 944× — the metric inversion — with its head pinned at the stop). ⚠⚠ GATE 1 CAUGHT THE
KERNEL'S OWN INELASTIC-STOP DECISION BECOMING REACHABLE (`head_max = 30.000` EXACTLY on the heavy
wire): opening the stop moved the ring ~1 %, so the mechanism was never the clamp — but the arm was
not CLEAN ⇒ wire B authors 50°, and ⭐ THE RING IS SPENT IN GIMBAL TRAVEL (41.5° vs the quiet arms'
18.117°), slice 33/34's budget claim in a THIRD currency. ⚠ Wire B also authors its detector window
WIDE ON A NUMBER (35°, PROVEN non-binding because the wire flies BIT-IDENTICALLY at 45°). ⚠⚠ AND
`gimbal_rate_dps` IS AUTHORED WIDE (120 °/s) AS AN ISOLATION WITH A CROSS-REFERENCE: at slice 37's 40
the limit binds 20–53 % of band ticks AND ATTENUATES the ring (0.656 vs the free 0.800) — slice 35's
two-sided knob on a new architecture ⇒ THE SHIPPED SERVO WAS PARTLY HIDING THIS. ⭐ THE ANALYTIC EDGE
ζ = 1/√2 IS INSIDE THE SLIDER'S DOMAIN and the shipped `head_index_gain` crosses 1.0 across it
(1.11838 → 0.81058), asserted as a CROSSING rather than by re-deriving the closed form. TWO WIRES, ONE
SLIDER EACH (ζ; ω_n is AUTHORED and DISQUALIFIED BY NON-MONOTONICITY — slice 28's `k`, 4th occurrence),
and TWO CURES, ONE CONTROL EACH: the BUTTON back to an architecture that cannot ring, the SLIDER
damping the one that can. ⭐⭐ CLIENT: the 9th marker `gimbal_servo_view`, only the SECOND to UN-DROP the
shared button, and its HUD half is the stale-readout class's ~11th occurrence in its WORST form —
slice 35's block would print "servo FREE" against a rate limit authored wide precisely so it never
binds. ⭐⭐ The state only this branch can name is a DEAD KNOB (ζ is BIT-IDENTICALLY inert on the lag
rung), and THE GAIN LINE IS A LABEL AND NEVER A VERDICT because the other wire refuses that reading.
⚠⚠ THE SHOT CAUGHT A DEFECT NO TEST HAD: the cure line advised damping an arm already damped — every
number true, the INSTRUCTION stale. Class 4a (15th consecutive RNG-live), replay bit-identical at both
slider ends AND both rungs, button BACK. (7693)**

**⚠⚠ SLICE 41 IS A KILL RECORD, NOT A SLICE — a second-order FIN actuator died at gate 0, and the
suite stayed at 7693 (`docs/plans/slice41.md`).** The candidate was the one slice 40 named as its own:
slice 15's fin is a first-order lag with a rate limit for exactly the reason slices 34–40's head was,
so give the fin an INERTIA too. The kernel was clean, the seam was clean (nine wires bit-exact across
five distinct `:delta_cmd` writers), and the physics was REAL — the inherited sign even inverted, which
is the headline the plan had hoped for: a lag on the head's feed-forward path had been *"silently doing
stability work"*, but the same component inside the MAIN control loop **eats phase margin and
destabilizes**. At one step inside slice 26's own stability boundary the ring goes 1.27× / 1.58× /
1.93× / 4.45× at 60 / 40 / 30 / 20 Hz, monotone and unclamped, and the radome threshold itself walks
−0.0926 → −0.0901: *a cheaper actuator needs a better radome*. ⭐ And it is a MARGIN effect, not a
cost — off the shoulder a 20 Hz actuator is free to seven figures, so an actuator's phase lag is free
while you have margin and ruinous when you do not. **None of it survived P5.** Two independent
single-axis `(k_α, k_q)` retunes each reproduce the actuator's ENTIRE threshold curve to 0.00–1.01 %,
against a falsifier of 2.7–3.2 % that was fixed in writing one commit before the measurement existed.
⭐⭐ **THE REASON IS WORTH MORE THAN THE SLICE WAS: a pole differs from a gain ONLY in that its phase
VARIES with frequency, and this loop's fin command is a single 1.6488 Hz line — so the loop samples one
point of a phase curve, and one point of a phase curve is a number, which is what a gain is.** Slice
38's *"`s` adds PHASE and scaling a slope cannot"* is true but has teeth only where the loop is
broadband; on a single-mode limit cycle it has none. ⚠ The gate also walked into and out of three traps
now banked in `docs/LESSONS.md`: run at the wire's AUTHORED design the whole slice reads a 0.4 % INERT
kill, because the α_max clamp binds 78 % of band ticks there and a clamped amplitude cannot move; P5
worded as a POINT fit answers *yes* (`k_α = 1.01` matches the 60 Hz arm to 0.9 %) and would have killed
the slice at the right time for the wrong reason; and the pre-registered confirmation leg returned a
PASS in which every arm also sat within 0.9 % of the CONTROL — a test whose control passes is not a
test. **The pre-registration is what saved it from a wrong death and then delivered the right one.**

**⚠⚠ SLICE 42 IS A KILL RECORD, NOT A SLICE — a search pattern died at gate 0, the acquisition
margin that replaced it died at gate 1, and the suite stayed at 7693 (`docs/plans/slice42.md`).** The
slice opened on a genuinely appealing trade: a seeker that SWEEPS can find a target it never
acquired, so buy coverage with TIME instead of with GLASS. Gate 0 measured it fairly and then said
the honest thing — **in this simulator a wider window is FREE.** A single 15° window rescues every
showcase cell on the geometry that would ship, and nothing in the model charges for sensitivity,
resolution or range as the window opens, so the trade cannot be motivated from inside the model at
all. That is not a defect of the search; it is a named approximation of the detector, and it is the
reason the surviving law is deferred rather than dead. What DID survive is a clean two-parameter one:
**guess the search direction right and coverage is free — the minimum sweep rate is flat across a 6×
range of it — guess wrong and every extra degree must be bought back in rate**, monotonically, until
past a point no rate buys it at all. ⭐ Gate 0 also produced two instrument bugs that each read
exactly like physics (a sweep rebuilt from the head's own position crawls at 1/50 rate; a sweep that
steps the HEAD rather than a COMMAND never reverses once the gimbal stop binds), which is where the
discipline **check a probe where the CLAMPS bind** comes from. ⚠⚠ Then the slice pivoted onto what
looked like a sharper finding — an ACQUISITION KNIFE-EDGE: with the detector window walked onto the
handover offset exactly, the seeker locks, and the lock is worth nothing. It reads beautifully and it
was the null case wearing a label. **The tell was in its own table: the "worthless lock" cell's miss
was byte-identical to the never-locks cell's**, so the lock moved no number that any verdict depends
on, and the `off@lock` column that read the window to four decimals was the inclusive `off ≤ fov`
gate echoing back its own authored constant. ⭐⭐⭐ Gate 1 then made the kill structural rather than a
matter of magnitude: re-fly the rim at three integration steps and **the dead band halves when the
step halves — it is `ω_LOS · dt`, one tick of line-of-sight motion, 0.0036° against a 10° window.**
The one non-degenerate rescue (that the required margin is set by the RACE between the LOS rate and
the servo) is refuted in the same probe, because a 7.5× faster servo returns the same miss to the
digit, and the same offset on the OTHER SIGN does not die at all — there the LOS walks INTO the
window and mints its own margin. ⭐ The real mechanism, traced tick by tick rather than inferred, is
better than the claim it replaces: **the head's command is written at the END of the tick, so the
servo is idle for exactly one tick — and being one tick late is not something a faster servo fixes.**
The margin a lock needs is one tick of line-of-sight motion, and the telemetry prints that increment
directly. ⭐ **A finding whose SIZE is set by the integrator's step cannot be
a lesson about hardware**, and the discipline that falls out is cheap and general: before shipping a
narrow threshold effect, re-fly it at half `dt`. ⚠ Four times now in this arc — 39, 41, the search
half of 42 and its acquisition half — **the probe was right, the table was right, and the SENTENCE on
top of the table was wrong**, and every one of the four was caught by a criterion written down before
the measurement existed.

⭐⭐⭐ **Slice 43's gate 0 then went back for the one thing slice 42 left standing — and found that the
table it was standing on had been flown with the servo switched off.** The frontier probe never set its
drive mode, so every cell TELEPORTED the head to the search command: no lag, no rate limit, at sweep
rates the shipped 8 °/s head cannot produce. Re-flown through the real servo, most of slice 42's numbers
survive — but the two sentences on top of them do not. Its *"past 20° of coverage no rate buys it back"*
was **its own 1..16 grid edge**; the answers are 18 and 22 °/s. And its *"guess right and coverage is
FREE"* is inside out: **the head locks 2.07° into a pattern authored 3–30° wide, so coverage is not free,
it is NEVER REACHED** — which is why the row was flat, and why a flat row is evidence of nothing until you
know where the mechanism stopped. ⭐⭐ What replaces both is a cleaner thing that neither slice had written
down: **the cost of acquiring is the OVERLAP DEFICIT — how far the target sits OUTSIDE the window edge —
and not the pointing error at all.** A head 14° off behind a 12° window and a head 12° off behind a 10°
window are the same problem, and they return the same travel, the same lock time and the same miss to
every digit printed. It closes to a formula — the head must cover the deficit PLUS whatever the target
adds while it travels, so the travel is the deficit divided by one minus the ratio of the line-of-sight
rate to the sweep rate, and the lock time is that over the sweep rate plus the servo's own lag. ⚠ The
first version of that sentence quoted a fixed 3.6 % correction and was wrong in an instructive way:
eight cells, all at ONE sweep rate. The mechanism it named — the target running away while you travel —
is itself a function of how long you take, so the correction MUST move with the rate, and it does
(3 % to 36 %). **Count the axes a claim varies over, not the cells.** Corrected, the drift term turns out
to BE the line-of-sight rate, matched against the telemetry rather than fitted. ⭐⭐⭐ And the sharpest thing in the
gate came from getting that wrong twice more. There IS a hard floor on how slowly you may sweep, and the
first two explanations for it — that the search is racing a line of sight which accelerates away, and that
the pattern simply never turns around in time — were both measured and both refuted. What actually holds
the slow arm out is that **a search that moves in one direction is looking through a window that is round
in two.** At the slowest rate the head closed the axis it was sweeping to 9.75° — comfortably inside a 10°
window on that axis — and never acquired anyway, because two and a half degrees of drift had accumulated
on the axis it never touches, and the gate measures the two together. A quarter of the window's radius was
spent on a channel the search does not move. ⚠ And the first sentence written about that was
wrong in the way this gate kept being wrong: it said the slow search *inflates its own target while it
works*, which the code cannot do — the sweep never touches the second axis at all. That drift is on a
clock of its own, identical whether anything is searching or not. **It is a deadline, not a feedback:** the
unswept channel spends the window down on its own schedule, and all the sweep rate decides is whether the
axis it does move closes before the budget runs out. ⭐⭐⭐ Said that way the floor stops being a measurement
and becomes a derivation — take the two curves off the arm that never acquires anything, ask at each instant
what rate would be needed, and the answer has a clean minimum: **1.0174 degrees per second, at four seconds
in.** Flown afterwards, 1.01 never acquires and 1.02 does, locking at 3.8 s. ⭐⭐⭐ And then the same
arithmetic was run on three geometries it had never seen — a bigger miss, a much bigger miss, and a wider
window — and it called all three, each landing on exactly the slowest rate that still works with the rate
one notch below it failing, and each predicting **when** the lock would happen to within a tenth of a
second. That is what turns a worked example into a law. ⭐⭐ And the shape of that curve
is the lesson: it is a U, so **a search has a best moment — too early and the swept axis has not closed,
too late and the other one has eaten the window — and a search that misses the moment cannot recover by
continuing.** ⭐⭐ It also hands an older deferral the flying arm it had been missing — a square window of the
same size would have locked this one and a round one does not — and that quietly matters for whether any
of this can ever be built: the search slice has been blocked because nothing in the model charges for a
wider window, and here is a way the window matters that has nothing to do with charging for it. Its
SHAPE. Which is a much cheaper thing to add than a sensitivity model. Guess the direction wrong and you pay twice the coverage in travel, at a
price that **accelerates** rather than scaling: 5 % over the geometric bound at small coverage, 39 % at
large, and past a point no lock at all — because the target keeps moving while you look the wrong way,
and that excess is the whole finding. ⚠ The last piece is a trap rather than a lesson: an open-loop
sweep generator **winds up** against the head's rate limit, and what saturates is not the rate but the
AMPLITUDE — command a 20° pattern at 64 °/s to an 8 °/s head and it sweeps 4.4° and fails outright, at a
coverage that rescues comfortably when commanded at 8. Anti-windup fixes it, and then the
reparameterization gate — run against the finding before it was written down, which is the habit this
arc has finally learned — shows simply refusing to author a rate above the servo's limit gives the same
verdict in all sixteen cells. So it ships as a caution, not an architecture. ⚠⚠ And the slice stays
BLOCKED for the reason slice 42 gave it, which the new law makes **sharper**: a wider window reduces the
deficit one-for-one, so widening the glass and travelling further are the same act — and only one of
them costs time. Nothing here can be motivated until the window costs something.

Full gate-by-gate
as-built detail (exact numbers, test names, watch-items, advisor-catches, per-slice run commands)
lives in **`docs/STATUS.md`**; pre-implementation plans in `docs/plans/sliceN.md`.

---

## 2. Per-slice digest, slices 1–28

- **Slice 1** — radar → detection → ROC. Free-space radar eq, analytic+MC Pd (Swerling 0/1),
  the wire protocol + Godot socket seam, the server run-loop, the `batch.jl`/ROC path. (227)
- **Slice 2** — propagation fidelity: `two_ray` lobing + 4/3-Earth horizon mask behind
  `:propagation`; coverage-diagram stretch. (420)
- **Slice 3** — CFAR sandbox + N-pulse integration (Swerling 0–4): CA/GO/SO/OS adaptive
  threshold, the masked-close-target lesson; `:cfar` (the one draw-topology flip). (798)
- **Slice 4** — jamming / EP: J/S burn-through, standoff vs self-screen, `:ep`
  none/freq_agility/sidelobe_blanking. First `build_env!`. (923)
- **Slice 5** — DF / geolocation: bearings-only fix, GDOP error ellipse, `:estimator`
  pseudolinear vs ml. First `decide!` (Godot plan/top-down view). (1055)
- **Slice 6** — multi-emitter EW: PRI-histogram deinterleaver, CDIF phantom vs SDIF subharmonic
  check, `:deinterleaver`. The phase-contract capstone (build_env!+observe!+decide!). (1238)
- **Slice 7** — GPS: pseudoranges → trilateration → DOP + RAIM (`:raim` off/detect/exclude).
  The §9 cross-domain-reuse milestone (same `gauss_newton` fixes DF N=2 and GPS N=4). (1492)
- **Slice 8** — ballistic missile: the force-integrator + `frames.jl`; `:integrator` rk4 vs
  euler (physics-changing, not toggle-invariant). First phase-1 force-based mover. (1633)
- **Slice 9** — PID autopilot under a pursuit outer law; `:autopilot` ideal vs pid, the
  commanded-vs-achieved track-gap lesson. First missile `decide!`. (1723)
- **Slice 10** — proportional navigation (outer loop) + g-limit saturation-as-lesson; `:guidance`
  pursuit vs pn (the reserved key filled, physics-changing). MISS is the honest headline (pn ≪
  pursuit); the a_max clamp BINDS on purpose (the slice-9 inversion). Closes the missile arc. (1829)
- **Slice 11** — noisy seeker + LOS-rate filtering; `:seeker` raw vs filtered — the naïve finite-diff
  `λ̇=Δλ/dt` amplifies angle noise → PN pegs a_max & misses wide, the α-β tracker recovers a smooth λ̇
  → tight intercept. The missile's **first phase-3 `observe!`** ("integrate!+observe!+decide!" COMPLETE)
  and the **first `w.rng` consumer in the missile arc** (the RNG inflection — conventions 3/11 now apply;
  byte-identity from *no Seeker* on prior slices). NEW fidelity-class combo: draw-invariant (4a,
  introducible) AND trajectory-changing. (1921)
- **Slice 12** — augmented PN (`(N/2)·a_T⊥` feedforward on the target's truth accel) + a `ManeuveringTarget`
  phase-1 mover; `:guidance` gains a THIRD rung `:apn` (the 3-ring pursuit→pn→apn). Vs a maneuvering target
  under a BINDING `a_max`, plain `:pn` SATURATES → misses (~167 m); `:apn` anticipates → low demand → tight
  intercept (~0.85 m, the CV baseline). The g-limit IS the constraint (raise a_max → pn recovers). **The RNG
  inflection INVERTS BACK** — no seeker → no `w.rng` draw → the slice-10 shape ("draw-count invariance VACUOUS"
  again). Reads TRUTH `a_T` ("even a perfect seeker still lags"); gravity-comp PN + estimated `a_T` DEFERRED.
  Closes HANDOFF §10 item 10. (2008)

- **Slice 13 (roadmap item 12) — countermeasures COMPLETE**: a `:decoy` seduces the slice-11 seeker; the
  slice-3 CFAR sandbox lifts onto the LOS-ANGLE axis (`:scan` rung); seduction (`:none` intensity-blend of ALL
  CFAR peaks) vs discrimination (`:gated` α-β predicted-LOS **nearest-neighbour** gate = the RGPO track-gate in
  angle). The FUSION lives in the discrimination half: `cfar_scan` DETECTS the peaks in the noisy angular profile
  (a real job — two lobes in fast-Rayleigh noise), the α-β predicted gate DISCRIMINATES which peak to keep (CFAR
  alone can't reject a BRIGHTER decoy). The HEADLINE is AIMPOINT error `|λ_est−λ_target|` (clean by construction;
  miss corroborates) under a GENEROUS `a_max` (a POINTING miss, ≠ slice-12's saturation miss). RNG inflection
  RE-INVERTS to APPLIES (a seeker draws again, conventions 3/11); `:scan` is class 4b (draw-topology flip
  `1`→`2·N_p·N_bins`, introduce/remove-rejected like `:cfar`), `discrimination` draw-invariant-within-the-4b-host
  + inert without `:scan`. The `:decoy` kind is NEVER `:target` (`_nearest_target` skips it → miss/CPA ALWAYS vs
  the true target — the seeker is seduced but the miss is honest). `Seeker.observe!` split into `_observe_point!`
  (slice-11 VERBATIM, 1 draw) / `_observe_scan!` (2·N_p·N_bins, tick-1 truth-cued lock, paint→`_draw_profile!`→
  `cfar_scan`→`extract_peaks`→`:none` blend / `:gated` NN gate). Emit-grid wire (seed 6): `:none` aim 4.83°/miss
  598 m vs `:gated` aim 0.054°/miss 4.16 m (~89×), draw EXACTLY 1280/tick; the born-resolved parallel decoy stays
  inside ±FOV/2 across the aim window. Four proofs green (verifier + UI + smoke-load + windowed shot: `:none` aim
  ray walks to the ✦ decoy, `:gated` holds on the target). Closes HANDOFF §10 item 12 — "fuses the whole suite".
  Deferred (NAMED): the range-gate RGPO variant vs a tracking radar; RF/IR seeker split; decoy dynamics
  (bloom/burn-out/ejection); 2-D az×el/monopulse; salvo. (2159)

- **Slice 14 (roadmap item 13) — cooperative salvo guidance COMPLETE (THE CAPSTONE)**: N=2 interceptors SHARE
  their time-to-go over an IDEAL datalink so they arrive SIMULTANEOUSLY. A `[SalvoCoordinator]` `:datalink` node
  (a NEW non-physical kind, phase-2 `build_env!`, SINGLE writer) pools every `kind===:missile` interceptor's truth
  `t_go≈R/V_c` into the team consensus `T_d=max_j t_go_j(0)` — FIXED-AT-LAUNCH (the robustness default; a per-tick
  or ratcheted consensus SELF-POLLUTES: the stretch it induces collapses V_c and inflates `t_go=R/V_c`, running T_d
  to ~99–105 s — probe8/9), republished as the shared REMAINING time `w.env[:salvo_t_d]=T_d−w.t`. The NEW
  `:cooperation` fidelity (`(:solo,:salvo)`): `:solo` = plain PN to each missile's natural `t_go` → SPREAD arrivals;
  `:salvo` = `impact_time_control_accel` (PN base + a `(K_it·err·‖v‖)·v̂⊥` ⟂-LOS feedback, `err=salvo_t_d−t_go>0 ⇒
  EARLY ⇒ STRETCH`) drives every missile's `t_go→T_d` → the near missile WEAVES a stretched S-curve to delay while
  the far reference flies ~straight → both arrive TOGETHER (Δτ collapses **2.35→0.53 s, ~4.5×** on the emit-grid
  wire) while each still HITS (cooperation reshapes TIMING, not accuracy). `a_max=3000` GENEROUS — the residual Δτ
  is a CONTROL-AUTHORITY/gain artifact, NOT a g-limit (the OPPOSITE of slice-12; do NOT import saturation language).
  The RNG inflection INVERTS BACK to VACUOUS (truth-fed PN, NO seeker → NO `w.rng` consumer) — class **4c**
  (physics-changing, no RNG; `:cooperation` LIVE-SETTABLE, NO `set_fidelity` guard — the `:integrator`/`:autopilot`/
  `:apn` precedent, the CONTRAST to slice-13 `:scan`'s introduce-reject). The FIRST multi-interceptor scenario +
  the FIRST `:datalink` kind. The solo degenerate is a LAW-level `err==0` bit-exact `pn_accel` early-return (a
  1-missile salvo is loader-forbidden); additivity for slices 1–13 is BY GATING (`:salvo` unreachable without the
  mode AND the coordinator). The metric SELF-JUSTIFIES → no defender model (deferred). Closes HANDOFF §10 item 13.
  Deferred (NAMED): consensus filtering / noisy-latent-lossy datalink (Tier-C); cooperative estimation (A) + WTA
  (B); the approach-ANGLE variant; a point-defense model; N>2 / heterogeneous; decoys in the salvo. (2259)

- **Slice 15 (§11 Tier-A, FIRST horizon extension) — a RATE-LIMITED FIN SERVO COMPLETE**: the actuator/fin half of
  the Tier-A "6-DOF airframe + actuator/fin dynamics" entry (6-DOF DEFERRED). A THIRD `:autopilot` rung `:fin`
  (`(:ideal,:pid,:fin)`): the SAME PID feeds a fin-deflection command `δ_cmd=clamp(u/k_δ,δ_max)`; the fin slews
  through a first-order servo whose rate is HARD-CAPPED at `δ̇_max` (rad/s); `a_ach=k_δ·δ`. THE CRUX (advisor,
  load-bearing): a LINEAR fin servo collapses to the `:pid` plant relabeled (`k_δ` cancels — the convention-4c
  false-fidelity trap), so the NONLINEAR limits (δ̇_max, δ_max) carry the ENTIRE fidelity — PROVEN by the
  `:pid`-equivalence-at-δ̇/δ→∞ test. THE LESSON (gate-0 EMPIRICAL PIVOT, 12 probes): the fin rate limit CAPS THE
  G-ONSET RATE `|da_ach/dt| ≤ k_δ·δ̇_max` (telemetry `g_onset`, ≤ the cap EVERYWHERE by construction) — a jerk cap
  cleanly DISTINCT from slice-9's steady-state gain undershoot `1/(1+Kp)`, slice-10/12's MAGNITUDE cap `a_max`. The
  ISOLATION (advisor #2, ASSERTED): `k_δ·δ_max=2500 ≤ a_max=2600` and the maneuver tuned so `fin_defl_sat==0 &&
  saturated==0` in the guided window → the cap is a CLEAN rate cap, not a slice-10 magnitude clamp in a fin costume
  (the three numbers separable: rate cap 2000, g cap 2500, mag cap 2600). THE "LACK OF EFFECT" IS THE LESSON
  (user-ratified): the MISS does NOT open — point-mass PN is robust to actuator rate limiting (the planned
  "saturation opens the miss" did NOT materialize) — which is precisely WHY the DRAMATIC failure modes (guidance
  limit cycle, α-limited maneuverability, radome/body-rate parasitic loop) genuinely need the DEFERRED 6-DOF (the
  fin state δ that 6-DOF's moment equation consumes is now BANKED). Class **4c** (physics-changing, NO RNG —
  truth-fed PN, no seeker; "draw-count invariance VACUOUS", the 2nd consecutive 4c after slice 14; LIVE-SETTABLE,
  NO `set_fidelity` guard — the `:integrator`/`:autopilot`/`:apn`/`:cooperation` precedent, CONTRAST slice-13
  `:scan`). `AutopilotState` STRUCTURALLY FROZEN (δ in its own `:fin_state` — advisor #4); the `:ideal`/`:pid` arm
  TEXTUALLY UNCHANGED (slices 1–14 byte-identical). Emit-grid wire (seed 15): `:fin` δ̇=0.4 → g_onset caps at 2000
  (=k_δ·δ̇_max), rate_sat binds, defl_sat/sat=0, miss 6.6; raise δ̇=2.0 → cap RISES to 10000 + binds LESS (rate_sat
  7→1) + miss UNCHANGED (the lever, the "lack of effect"); `:ideal` ships NO fin keys (byte-identical wire), miss
  9.2. Four proofs green (verifier + UI 3-ring ideal→pid→fin + smoke-load + windowed shot: the curved fin-limited
  trail + a_cmd 441 vs a_ach 330 lag). The client routes the shared button to a PER-SCENARIO autopilot 3-ring on
  `autopilot==:fin` (slice-9 stays a 2-ring). OPENS HANDOFF §11 Tier-A. Deferred (NAMED): the 6-DOF airframe /
  angle-of-attack half (trigger recorded); a 2nd-order actuator (ω_a/ζ_a); per-channel fin allocation / hinge-
  moment / stall; the actuator feeding a MOMENT (→α→lift) = 6-DOF. (2347)

- **Slice 16 (§11 Tier-A, the 6-DOF airframe's FIRST HALF) — pitch-plane ROTATIONAL DYNAMICS COMPLETE**: the
  DEFERRED rotational half of Tier-A's "6-DOF airframe + actuator/fin dynamics" (slice 15 did the fin half). The
  FIRST rotational state in the project — `att`, a KINEMATIC velocity-alignment through slices 8–15, becomes a
  DYNAMICAL OUTPUT of the aero pitching moment (the ROTATION analog of slice 8's ballistic force-integrator that
  made `pos` force-integrated). New pure lib `airframe.jl` (`AirframeParams`, `pitch_moment` M=QSd·(Cmα·α+Cmδ·δ+
  Cmq·q̄), `rk4_rot` the generic (θ,q) stepper — shaped so slice-17's joint [pos,vel,θ,q] step reuses the closure,
  `short_period_freq` NaN-guarded, `trim_alpha` δ=0→0). THE LESSON (the af_cma slider, a live KNOB not a fidelity
  button): Cmα<0 WEATHERVANES (α oscillates about trim at ω_sp=√(−Cmα·QSd/I), damped by Cmq, nose tracks γ) vs
  Cmα>0 TUMBLES (|α| diverges, ω_sp imaginary → FINITE_CEIL sentinel). #1 SIGN TRAP → the moment SIGN pinned
  DIRECTLY (advisor tooth #1), V/γ-frozen SHM RK4-exact ~1e-15, damping log-decrement pins ζ. THE ISOLATION (the
  headline proof): rotation reads (V,γ) but does NOT feed (pos,vel) — no α→lift this slice (slice 17) → the
  TRAJECTORY is BYTE-IDENTICAL across the Cmα flip (verifier posdiff=**0.0**). This is WHY there is NO `:airframe`
  fidelity toggle — a path-bit-identical toggle would name a coupling it can't produce yet (the convention-4c
  FALSE-FIDELITY trap, the slice-15 k_δ-cancellation precedent). **Option-P′** (advisor-reconciled): a handshake
  `airframe_view` marker (the range_axis_m→cfar precedent) makes the client recognize the view + DROP the shared
  button (nothing to cycle), core stays PARAMS-PRESENCE gated (`haskey(c,:af_cma)`, slices 8–15 byte-identical).
  Class **4c** (physics-changing, NO RNG — truth-fed, no seeker → "draw-count invariance VACUOUS", the 3rd
  consecutive 4c after 14/15; LIVE-SETTABLE, no `set_fidelity` guard). The Godot marker draws the NOSE off θ vs a
  CYAN VELOCITY reference off γ — the gap IS α, labeled. Four proofs green (verifier: STABLE max|α|=0.150/ω_sp=2.40
  real, REPLAY bit-identical, UNSTABLE max|α|→1e6/ω_sp=1e9 sentinel, posdiff=0.0; UI: button HIDDEN + af_cma
  slider→set_param; smoke-load DONE; TWO contrasting shots — stable α=3.2° nose≈v vs mild-unstable α=23.8° nose
  off v/ω_sp sentinel). Deferred (NAMED): **slice 17 = the inner α/g autopilot + α→lift→γ coupling** (the real
  path-changing `:airframe` toggle lands THEN — a stable Cmα gains a coupling to name; the fin state δ from slice
  15 feeds the moment equation); then α-limited-maneuverability miss → bank-to-turn (3-D quaternion+ω, the
  geometry→frames "2-D first" precedent) → radome/body-rate parasitic loop. SLICE-17 CLIENT NOTE: the airframe
  branch is checked FIRST in `_setup_spatial_fid_btn` — value-guard it when slice 17 adds an `:airframe` fidelity
  alongside `af_cma` (else it hides the button slice 17 wants). (2409)

- **Slice 17 (§11 Tier-A, the 6-DOF airframe's SECOND HALF) — the α→lift→γ COUPLING COMPLETE**: the FIRST
  rotation→translation coupling in the project. Slice 16 made `att` a dynamical output but ISOLATED it (posdiff=0);
  slice 17 CLOSES the loop — **α = θ−γ generates a body lift ⟂ v that TURNS the flight path** (α→lift→γ̇), and the
  REAL path-changing `:airframe = point_mass | pitch_coupled` toggle finally lands (slice 16 refused it — the
  convention-4c false-fidelity trap). OPEN-LOOP (δ a FIXED authored trim — the inner α/g autopilot is slice 18).
  New `airframe.jl`: `lift_accel` (`(Q·S·Cla·α/m)·(−sinγ,0,cosγ)`; +Cla ⇒ γ̇>0 for α>0 = the #1 SIGN TRAP, pinned
  by `dot⟂v` AND γ̇-sign), `rk4_coupled` (a FRESH 8-scalar joint `[pos,vel,θ,q]` RK4 — re-evals V,γ mid-stage = the
  coupling, NOT operator-split), `AIRFRAME_MODES`; `AirframeParams` gains `Cla`. The LESSON & anchor: the
  STEADY-TURN RADIUS `R = 2m/(ρSC_Lα·α) ≈ 5197 m` (SPEED-INDEPENDENT). `missile.jl` `_integrate_coupled!` gates on
  `haskey(:af_cma) && :airframe===:pitch_coupled` (point-mass block wrapped VERBATIM in the else — byte-identity).
  **THE STAGE-θ FIX (advisor, load-bearing):** the deriv closure reads the RK4 STAGE θ (`TH`), NEVER the entry θ —
  the entry-θ bug is only ~0.019 m/8 s, invisible to the R & decoupled tests, so ONLY a transient GOLDEN catches
  it. Lift telemetry (a_lift/turn_radius_m) gated on `:pitch_coupled` NOT af_cma (else a slice-16 wire breaks).
  `LIVE_FIDELITY_MODES` gains `airframe = AIRFRAME_MODES` (the ONLY plumbing edit; NO set_fidelity guard). Class
  **4c** (physics-changing, NO RNG — "draw-count invariance VACUOUS", the 4th consecutive; live-settable). CLIENT:
  the `:airframe` cycler comes BACK, REUSING `_fid_kind="airframe"` (the curved-trail + nose/velocity/α drawing all
  carry over) with the drop VALUE-GUARDED on `_fidelity.has("airframe")` (slice 17 shows it, slice 16 still drops).
  Scenario `slice17_coupling.yaml` (δ=0.15 MANDATORY nonzero — the non-dead toggle; Cla=20; grav on, drag off): the
  live wire gives coupled (2187.8,3010.2) vs ballistic (3064.2,2257.3) → posdiff 1155 m; δ→0 straightens to 91 m.
  Four proofs green (verifier S17V OK: coupled CURVES vs point_mass ballistic posdiff 876 m [the INVERSE of
  slice-16's 0.0], lift keys coupled-only, replay bit-identical, δ→0 straightens; UI: cycler shows+wraps+set_fidelity,
  sliders set_param, slice-16 handshake STILL drops the button = value-guard both ways; smoke-load DONE; windowed
  shot: the CURVED coupled trail + nose leading the cyan v(γ) by the labeled α gap, button "airframe: pitch_coupled").
  Deferred (NAMED): **slice 18 = the inner α/g autopilot** (invert PN `a_cmd→α_cmd=a_cmd·m/(Q·S·C_Lα)→δ`, the
  slice-15 δ feeding `Cmδ·δ`; the `a_cmd/Q` divide = a crash-safety Q-floor) + the flight-condition aero g-limit
  `a_max_aero=Q·S·C_Lα·α_max/m` miss (distinct from slice-10's fixed a_max); induced drag; then bank-to-turn / 3-D
  (quaternion+ω) → radome/body-rate parasitic loop. (2488)

- **Slice 18 (§11 Tier-A "higher fidelity behind existing knobs" — `propagation` is the named seam) — TERRAIN
  MASKING + the 3-D client view COMPLETE**: the FIRST terrain in the project and the client's FIRST true 3-D view
  (a USER-DIRECTED insertion 2026-07-14 — the inner α/g autopilot slice17.md slotted as "18" SHIFTS to slice 19,
  trigger intact). New pure lib `terrain.jl`: an authored ANALYTIC Gaussian-hill heightfield (`h0 + Σ aᵢ·exp(…)`,
  ZERO RNG — nothing to desync), `terrain_clearance` (SIGNED min ray_z−h over interior samples, endpoints EXCLUDED
  [a mast can't self-block], fixed `s=i/(n+1)` grid ⇒ bit-exact (p1,p2) SYMMETRY), `terrain_los_clear` (the HARD
  shadow — knife-edge diffraction is the named rung above), `terrain_grid` (the row-major wire sample; layout
  pinned vs an ASYMMETRIC terrain — the transpose canary). `PROPAGATION_MODES` gains **:terrain** (free-space link
  budget + the LOS mask → `(0.0,false)` occluded — the below-horizon-policy shape; **no terrain entity ⇒ bit-exact
  :free_space**, the mismatched-EP `==` no-op precedent). Class **4a** (draw-invariant — detect_once draws
  unconditionally, the mask gates booleans; 3-rung RNG-lockstep pinned; introduce-safe, live-settable, NO guard —
  the FIRST 4a since slice 11, breaking the 14–17 4c streak). Terrain = a NON-PHYSICAL `kind: terrain` entity (the
  `:datalink` precedent; hills → FLAT `hillK_*` comp keys, ≤1 entity enforced, **LOAD-STATIC** — the handshake grid
  ships ONCE so hills are NOT live knobs [named deferral]); `_terrain_info` ships grid/extents/ids at handshake —
  **`terrain_grid` presence is the client's 3-D-view discriminator**. `<radar>.terrain_clearance_m` (signed,
  `_finite_coord`) is RUNG-gated (the slice-17 lift-keys precedent). NEW general lever: `ConstantVelocity` gains a
  presence-gated `alt_hold_m` comp (altitude becomes knob-addressable; absent prior ⇒ byte-identical). THE LESSON
  (probe, live wire, seed 18): the 120-m penetrator is DARK the whole approach behind the 250-m ridge → POP-UP at
  t=36.72 s / x=4819 m (clearance −208.6→+, SNR floor→50.7 dB, ZERO detections while masked); alt→1000 COLLAPSES
  the shadow (min clearance +31.4 m); free_space same seed tracks from frame 1 — altitude buys detectability, the
  clearance SIGN is the verdict. CLIENT: `_enter_terrain_mode` builds a CanvasLayer(−1)/SubViewport Node3D world —
  the heightmap ArrayMesh (height-tinted vertex colors), emissive markers, the LOS ray colored by the CORE's
  `visible` verdict (client NEVER re-tests occlusion), fading trail, orbit/zoom camera; sim(x,y,z-up)→Godot(x,
  z·2.5,−y) with T3D_VEXAG=2.5 DISPLAY-ONLY + HUD-labeled (§12). The shared button = the propagation cycler
  upgraded to the FULL 3-ring via PER-SCENARIO `_prop_rungs` (the `_autopilot_rungs` precedent, sliced from ONE
  `PROP_RUNGS` const — slices 1/2 keep the 2-ring, no phantom rung). Four proofs green (S18V: masked start at the
  exact floor + EXACTLY one transition @ x 4816 + detections only-visible + clearance-sign≡verdict + 2500-frame
  replay BIT-IDENTICAL through the masked draws + free_space contrast + alt collapse; S18UI: mode/grid/3-ring
  wraps/set_param/off-tree 3-D build + the plain-handshake 2-ring guard; smoke-load DONE; TWO shots: red ray dying
  into the crest "TERRAIN MASKED −205 m" vs green ray over it "LOS CLEAR +32 m" detected:YES). Banks the
  heightfield land CLUTTER needs. Deferred (NAMED): knife-edge diffraction; terrain multipath/clutter; fractal
  terrain; hill-knob grid re-ship; DF/ESM/seeker terrain occlusion. (2604)

- **Slice 19 (§11 Tier-A, the 6-DOF arc's CLOSED INNER LOOP) — the inner α/g AUTOPILOT COMPLETE**: the missile
  finally flies its own PN command *through the airframe* instead of by fiat. Slice 17's fin δ was a FIXED
  authored trim (the airframe curved, it did not AIM); slice 19 inverts the guidance command through the aero —
  **`a_cmd → α_cmd = a_perp·m/(Q_eff·S·C_Lα) → δ`** (`alpha_command` + `alpha_autopilot_delta`, the `:ff_fb`
  feedforward-trim-inversion + rate-damped feedback law) — on the **FIRST COUPLED AND GUIDED missile** in the
  project (slice 17 was open-loop, no target). THE LESSON: the achievable maneuver accel IS the FLIGHT-CONDITION
  lift ceiling **`a_max_aero = Q·S·C_Lα·α_max/m` ≈ 269**; the SAME PN law on `:point_mass` applies `a_ctrl` by
  fiat and **HITS (0.276 m)** while `:pitch_coupled` must MAKE its g from lift, the demand exceeds the ceiling
  **59%** of the approach, and it **MISSES by 295.168 m (1069×)**. The cap is DISTINCT from every prior one (the
  copy-paste false-claim trap): 10/12's `a_max` = an authored MAGNITUDE clamp, 15's `k_δ·δ̇_max` = a JERK cap and
  `δ_max` = a DEFLECTION cap — 19's is a **FLIGHT-CONDITION** cap (what the air gives you *right now*). **The
  ISOLATION is STRUCTURAL — `saturated == 0` FAILS and must NOT be copied from slice 15**: `a_max` clamps 560×
  INERTLY (3000 ≡ 1e7 bit-for-bit) because it clamps `a_cmd` UPSTREAM of the α inversion and the tighter clamp
  wins downstream ⇒ assert `max(a_max_aero) < a_max` (269 ≪ 3000) + `defl_sat == 0` (the FOURTH cap). **BINDING
  ≠ CAUSING** — the counterfactual licenses the claim: relaxing **α_max ALONE** (it enters ONLY the α_cmd clamp,
  absent from `pitch_moment`/`lift_accel`/`short_period_freq`) recovers **282 of 295 m = 95.4%**; the ~13 m
  residual is "the airframe + autopilot DYNAMIC TRACKING COST" (a §1 named approximation — NOT "short-period
  lag", NOT a projection effect). `:a_ctrl` STAYS OUT of the coupled force (adding it rebuilds the point-mass
  plant in an airframe costume and deletes the lesson — the 3rd occurrence of that trap); the `:alpha` rung's
  behaviour DEPENDS on `:airframe` (a_ctrl under `:point_mass`, δ under `:pitch_coupled`) — **the FIRST
  cross-fidelity dependency in the suite, written down, not implied**.
  **GATE-3 FINDING (blocking): the planned `speed` demo knob is DEAD** — `comp[:speed]` is consumed ONCE at load
  to build `e.vel` and read by NOTHING per-tick, and `reset` reloads the YAML; gate 0 swept it by re-authoring
  per run and gate 2's no-crash drag PASSES on a dead knob (**the dead-knob face of the false-fidelity class —
  4th in this arc, first caught at gate 3**). **`rho` is the live Q lever** (fetched every tick by BOTH
  integrate! and decide! ⇒ zero new consumer code; Q ∝ ρ exactly linear; confounded like speed [ω_sp ∝ √ρ] ⇒ DEMO
  only, α_max stays the causation knob; and unlike speed it can't break the first-CPA condition — a working
  speed knob at V0 > 825 would outrun the target). Knob **ρ ∈ [0.6, 1.3]** — bounded to the MONOTONE region: the
  miss PEAKS at ρ≈0.5 and FALLS below it (at ρ=0.1 it misses by LESS than the default — the missile stops trying
  and flies ballistically), which would REVERSE the lesson (the [[ewsim-df-ellipse-sigma-monotonicity]] pattern
  recurring). ρ-as-knob makes the constant-ρ approximation INTERACTIVE — **say "low dynamic pressure (thin air)",
  NEVER unqualified "high altitude"** (ρ is not derived from z; the exponential atmosphere is DEFERRED). The
  NOT-A-DEAD-KNOB TRIPWIRE now ships (verifier + `test_server` assert ρ MOVES `a_max_aero`, not merely that
  nothing threw). Class **4c** (physics-changing, NO RNG — truth-fed, no seeker ⇒ "draw-count invariance
  VACUOUS"; live-settable, NO guard — the 5th 4c after 14/15/16/17). CLIENT: the slice-17 airframe view REUSED
  wholesale (`_fid_kind="airframe"`) + the NEW headline `_draw_aero_strip` (cyan ceiling vs orange demand, breach
  band red, border lights on `aero_sat`) — **the plot is ILLUSTRATIVE and says so**: `aero_sat` keys off the ⟂-v
  PROJECTION while `a_demand` is full-magnitude, so the sets nest (the verifier asserts the FLAG, never a
  hand-rolled compare). Four proofs green (S19V: 295.186 vs 3.844 = 76.8× frame-sampled, replay posdiff 0.0, the
  ρ lever drops the ceiling 0.49× live, the α_max sweep recovers 95.4%; S19UI: the value-guard THREE ways — 16
  drops / 19 shows / 18 stays 3-D; smoke-load + 16/17/18 re-smoked + all 9 prior UI tests green; TWO shots at tick
  4130: coupled los 295.19 / a_cmd 282 vs a_ach 180 / α −7.8° vs point_mass los 3.84 / track_gap 0). Deferred
  (NAMED at the time — **since RESOLVED, see slice 20**): the exponential atmosphere (makes "high altitude"
  REAL); a SCALAR rate-limited fin inside the coupled loop (slice-15's banked δ → the guidance limit cycle) —
  **that candidate is now DEAD, killed at gate 0: `δ_max` SHADOWS `δ̇_max`, `docs/plans/slice20.md`**; induced
  drag (C_Di ∝ C_L² — the g-bleeds-V-lowers-Q spiral) — **DONE, slice 20**; nonlinear C_L(α)/true stall;
  bank-to-turn / 3-D (the out-of-plane discard dies only there) → the radome/body-rate parasitic loop (now the
  empirically-motivated home of the limit cycle); a seeker in the coupled loop (flips back to 4a/RNG-live). (2864)

- **Slice 20 (§11 Tier-A) — INDUCED DRAG: THE MISSILE LOWERS ITS OWN CEILING BY MANEUVERING**: the project's
  FIRST DEGENERATIVE SPIRAL, cashing an approximation slices 17/19 shipped EXPLICITLY ("lift is drag-free /
  speed-preserving ⟂ v"). Lift ⟂ v turns the path; **induced drag ∥ −v̂ SENDS THE INVOICE** — `C_Di = K·C_L²`,
  `a_ind = −(Q·S·K·C_L²/m)·v̂` (`induced_drag_accel`, `lift_accel`'s ORTHOGONAL COMPLEMENT: same α, same Q·S;
  one turns at constant speed, one slows without turning) — and the invoice is paid in the very currency that
  buys the turn: **pull α → bleed V → Q falls → `a_max_aero` falls → the ceiling CATCHES the demand → you can't
  pull → you miss.** Slice 19: the ceiling is a flight condition that BINDS. Slice 20: it is a flight condition
  **YOU DEGRADE BY USING IT** — slice 19 moved it with the ρ knob (an ENGINEER dialling a flight condition);
  here the MISSILE moves it, by turning. **NO new cap — it makes cap #4 SELF-LOWERING; the novelty is the
  FEEDBACK.** **THE HEADLINE IS THE CEILING COLLAPSE RATIO** (0.92× FLAT → **0.12×**, an 8.4× fall WITHIN one
  run) — pure ceiling and monotone-safe BY CONSTRUCTION, so it is what evidences "lowers its own CEILING";
  `aero_sat 0/366 → 55.1%` is the CONSEQUENCE (it moves on ceiling AND demand), though a stark one: **at K=0
  the ceiling NEVER BINDS ONCE.** ρ/S/C_Lα/α_max/mass ALL HELD; only K changed. Wire (frame-sampled, seed 20,
  LOS-gated at **r > 1000 — NOT slice-19's 300**): K=0 miss 8.59 (HIT) / K=0.15 103.14 / K=0.3 **714.12** (83×);
  `defl_sat` 0 in every arm; replay posdiff 0.0. **⚠ THE CLAIM IS BOUNDED (the sharpest constraint here):
  "bleed→ceiling→miss" is what ANY speed loss does — matched on ΔV a parasitic `cd_area` reproduces it (45.02 m
  /173.2 vs 44.17/176.3) — so ONLY the α²-SOURCE makes it *induced*, and that ships as a TOOTH, not prose**
  (straight coast: induced <1 m/s vs parasitic >50, a >50× split — `test_missile.jl` "THE DISCRIMINATOR").
  **⚠ "DEGENERATIVE SPIRAL", NEVER "positive feedback"**: the speed bleed is SELF-LIMITING (bill ∝ V²α² ⇒ dV/dt
  PEAKS at −88.8 then DECAYS to −35.8; V asymptotes ≈213, ceiling ≈25 — neither reaches 0). The positive sign is
  on the TRACKING ERROR and only CONDITIONALLY (below the ceiling PN converges — *negative* feedback, which is
  WHY PN works; past the crossing the sign flips). **⚠ NOT "a harder engagement costs more" — REFUTED** (the
  attributable bill FALLS 194→117 as the target jinks: shorter ToF + the α clamp). The target does NOT maneuver:
  **the missile pays for its own turn onto the collision course.** Byte-identity is STRUCTURAL — a SECOND
  closure gated on `haskey(:af_k_induced)`, the else-arm slice 17/19 VERBATIM (never `+ a_ind` trusting
  K=0→zero: the `-0.0` trap); loader PRESENCE-gated on the KEY not the BLOCK (16/17/19 all have airframe
  blocks); K's SIGN validated (a negative K ACCELERATES). **NO new rung** (a rung must name physics the knob
  can't express; `:free` IS K=0 — the slice-16 `af_cma` precedent); **ONE knob** `af_k_induced ∈ [0, 0.3]`
  (MEASURED: monotone+clean to 0.6; at K≥0.8 `defl_sat` 0→1289 and α_pk overshoots α_max = slice-19's LEAK ⇒ a
  2× margin) — **α_max/ρ DISQUALIFIED and asserted ABSENT** (α_max now feeds the bill through the ACHIEVED α ⇒
  no longer isolated, unlike slice 19 where it touched only the clamp; ρ moves ceiling AND bill). Class **4c**
  (6th consecutive; no RNG ⇒ draw-invariance VACUOUS). **ZERO new client code** — slice 19's airframe view
  carries it (the aero strip already plotted the ceiling; it just starts FALLING). Four proofs green (S20V;
  S20UI 4-way value-guard + exactly ONE slider; smoke; shot at tick 6000 aimed at the CLAIMED branch — cyan
  ceiling 269→138, demand crossing at 301, AERO SAT lit). Slices 1–19 byte-identical, proven ON THE WIRE (the
  16/17/19 verifiers reproduce STATUS to the digit). (2935)

- **Slice 21 (§11 Tier-A) — THE EXPONENTIAL ATMOSPHERE: THE CEILING YOU LOWER BY CLIMBING**: the honest completion
  of 19/20's constant-ρ, and the aero arc's last opening deferral. Slices 19/20 were under STANDING ORDERS to say
  "low dynamic pressure (thin air)" and NEVER unqualified "high altitude" — ρ was a number an ENGINEER TYPED, not a
  consequence of where the missile flew, and only V could move `Q = ½ρV²`. Here `ρ = ρ₀·exp(−z/H)` and the phrase is
  EARNED: **climb → ρ(z) falls → Q falls → `a_max_aero` falls → you cannot pull → you miss** (⚠ THE CAVEAT LIFTS
  ONLY HERE — a 19/20 wire has no `af_scale_height` and runs `:constant`; no global find/replace). **NO new cap —
  the SAME cap #4, a THIRD MOVER**: 19 the ENGINEER moved it (the ρ knob), 20 the MISSILE moved it by TURNING (V
  bleed), 21 by **WHERE IT FLIES** — and the climb is not optional, it is the only way to a 14 km target.
  **⭐ THE HEADLINE IS THE ρ-FACTOR, AND IT FACTORIZES EXACTLY** — what slice 20 could never do: since
  `a_max_aero = ½ρ(z)V²·S·|C_Lα|·α_max/m`, the within-run ceiling ratio is IDENTICALLY `[ρ(z)/ρ(z₀)]·[V/V₀]²`, an
  ALGEBRAIC identity — so ALTITUDE and SPEED separate with **NO residual** (measured ON THE WIRE at the
  ceiling-min frame: residual **EXACTLY 0.0**). **⭐⭐ THE SHARPEST FACT: the twin's ρ-factor is EXACTLY 1.0** (`==`).
  The `:constant` arm's ceiling ALSO falls (0.524×) — but that is GRAVITY bleeding V, and its model books **100% of
  it to speed BY DEFINITION**, because it has no z in its ρ at all. **That is the whole slice in one number**, and
  it is WHY `rho_air` is KEY-gated not RUNG-gated (the twin's half of the headline must BE on the wire; rung-gating
  would leave the client dividing `2·q_dyn/V²` — physics in GDScript, convention 13). New pure lib `atmosphere.jl`
  (the project's SMALLEST — one function + one mode tuple; z floored at 0 and H at 1.0, BOTH real crash paths: an
  RK4 stage probes z<0 → Inf → NaN pos, and H=0 with z=0 is `0/0`). **★ THE KNOB-vs-RUNG DISCRIMINATOR (the general
  result, in atmosphere.jl's header because it outlives the slice)**: *is the off-state (a) a distinct code path and
  (b) NOT knob-reachable?* KNOB (`af_cma`, `af_k_induced`) = an IN-DOMAIN slider value; RUNG (`:airframe`,
  `:propagation`, `:atmosphere`) = a distinct path no knob reaches. Constant ρ is `H = ∞`, a LIMIT POINT — so slice
  20's "a `:free` rung IS K=0" does NOT transfer. The tempting refusal (":constant names no physics ρ(z) lacks")
  was ADVISOR-KILLED: it is word-for-word `point_mass`/`free_space`, so it would delete two shipped rungs.
  **THE STAGE-z FIX**: the slice hinges on an argument ALREADY THERE — `_integrate_coupled!`'s closure has been
  `f(P,Vv,TH,Q)` since slice 17 and `P` (the RK4 STAGE POSITION) **was read by nothing**; ρ(z) finally reads it at
  ZERO contract change (slice 17's stage-θ fix exactly; params REBUILT PER STAGE keep the aero lib z-FREE — it
  never learns about altitude, it just gets a `p` whose rho is the stage value). Byte-identity STRUCTURAL: the
  else-arm is 17/19/20 VERBATIM and serves BOTH key-absent AND `:constant` (never `exp(0)==1` — the `-0.0` trap).
  **`:atmosphere` is INERT without `:pitch_coupled`** (`_atm_on`'s third conjunct — a gate-3 LATENT BUG FIX: ρ(z)
  reaches the coupled path only, and slice-16's `_integrate_airframe!` would otherwise have INTEGRATED θ/q in ρ(z)
  while pos/vel flew ρ₀ = half the missile in each atmosphere; the slice-13/14 inert-without-its-host shape).
  ⚠ **NOT zero client code** (unlike slice 20): the lesson IS a button and the scenario ALSO ships `:airframe:
  pitch_coupled` HELD — **two view-claiming fidelity keys, a first** — so `_setup_spatial_fid_btn` checks
  `:atmosphere` FIRST (the slice-13/14 one-button rule, 3rd occurrence); everything else REUSES slice 19's airframe
  view. Class **4c** (7th consecutive; no RNG ⇒ draw-invariance VACUOUS; live-settable, no guard). ONE knob
  `af_scale_height ∈ [6000,25000]` (MEASURED: H≤3000 LEAKS α_max — slice-19 FINDING 14; ρ₀/α_max/K DISQUALIFIED and
  asserted ABSENT; **launch altitude is a DEAD knob** — position is load-only, `reset` reloads the YAML: **H is the
  live face of z**). ⚠ **The miss does NOT reverse in H — that prediction was REFUTED**: slice 20's K reversed
  because its penalty was SPEED; thin air costs ZERO speed, only AUTHORITY. Wire (frame-sampled, seed 21, LOS-gated
  r>1000): `:exponential` miss **360.8** / ceiling 239→31 / ρ-factor **0.248** / aero_sat 25.6% vs `:constant` miss
  **3.1** (**117×**; per-tick 1.95/185×) / **aero_sat 0/2628 — NEVER BINDS ONCE**; H=25000 → 7.1; `defl_sat` 0 in
  every arm; replay posdiff 0.0. Four proofs green (S21V; S21UI with a **FIVE-WAY** value-guard; smoke + 16–20
  re-smoked; shot at the CROSSING — ceiling 81.7 vs demand 83.4, AERO SAT lit). **⚠ Three gate-3 bugs, all in the
  PROOF not the physics**: `%.2e` is NOT a GDScript specifier (an unknown one makes the WHOLE `%` fail SILENTLY →
  the headline printed as `"%.9f"` on a GREEN run — *a number that does not print is not a proof*); the pass text
  QUOTED PER-TICK truth while the file measures FRAMES (**a miss samples faithfully — radial rate is 0 at CPA — but
  a HIT samples COARSELY**: ~13 m between samples); and a MAGIC-MULTIPLE tooth (now pinned against the EXP arm's
  MEASURED ρ-factor). (3182)

- **Slice 22 (§11 Tier-A) — NONLINEAR `C_L(α)` / TRUE STALL: THE CEILING THE AIRFRAME SETS**: slices 19/20/21 gave
  cap #4 three movers and **ALL THREE MOVED Q** (the engineer's ρ knob; the missile's own turn via V; where it
  flies via ρ(z)). **Slice 22 moves the OTHER FACTOR** — all three assumed the lift curve is a STRAIGHT LINE out
  to α_max. Past α_stall the flow SEPARATES: **C_L PEAKS and FALLS**, and the ceiling is the curve's own INTERIOR
  PEAK — no amount of Q buys past it. **THE REVERSAL IS NEW IN THE SUITE**: every prior cap is a MAGNITUDE that
  SATURATES; this one is a **DERIVATIVE THAT CHANGES SIGN** — past the peak, pulling HARDER turns you LESS *and*
  costs you MORE (which is why the user chose true-drop over a saturating curve; a saturating one cannot produce
  the control-loop reversal at all). ⭐ **THE HEADLINE IS AN EXACT IDENTITY**: at fixed Q the linear→stall ceiling
  ratio is IDENTICALLY `α_stall/α_max` (Q, S, C_Lα, m ALL CANCEL) — 471.435… → 269.391…, ratio ≡ 4/7 with **|Δ| =
  0.0 bit-for-bit**, slice 21's ρ-factor identity in a new letter. ⚠ **A SAME-INPUTS FORMULA TOOTH, NEVER a
  run-vs-run** (separation drag makes V, hence Q, diverge between arms). **KNOB, NOT RUNG — and the plan predicted
  the OPPOSITE**: it asserted linear was `α_stall → ∞` (a limit point ⇒ rung) and gate 0 **REFUTED** it — the
  achieved α SELF-LIMITS to ~0.24 over every reachable state, so a finite α_stall ≥ 0.25 is linear-in-effect and
  **the knob's own TOP is the in-scenario linear twin**; `test_aero_curve.jl` ASSERTS the fidelity's absence.
  ⚠ **α_max 0.35 > α_stall 0.20 INVERTS SLICE 19**: reaching stall via the FINDING-14 LEAK was REJECTED as
  gain-dependent and CIRCULAR (closing that leak is this slice's own payoff), so the autopilot **COMMANDS INTO
  STALL** and THE PHYSICS SETS THE WALL. The inner loop keeps inverting on the LINEAR C_Lα deliberately — it is
  REALISTIC (an autopilot carries a linear model of its airframe ⇒ **slice-19's command-vs-achieved gap MADE
  PHYSICAL**) and it SIDESTEPS the multivalued past-peak inverse (a named deferral, not a solved problem).
  Separation drag is **MANDATORY, not a lever** (measured 0.9% over its whole range — a PHYSICALITY term; the
  teeth carry it: exactly 0 below stall, EVEN in α, along −v̂, moving OPPOSITE to induced drag past the peak) and
  **slice 20's induced term is NOT "fixed"** — `C_Di = K·C_L²` falling past the peak is CORRECT physics.
  **⭐⭐ THE SHARPEST GATE-3 FINDING: `aero_sat` DOES NOT DISCRIMINATE AT ALL** — it fires **53/215 frames on the
  PARKED LINEAR arm and 53/215 on the STALL arm, the SAME COUNT**, because it keys off the **α_max CLAMP both arms
  SHARE** while the ceiling that moved is the interior peak. So there is a real regime **past the physics ceiling
  with the command not yet pegged** where it stays 0. **`post_stall` is the discriminator: EXACTLY 0 vs 56.**
  ⇒ the ONE client edit (**NOT zero, unlike slice 20**): the aero strip's breach indicator keys on `post_stall`,
  presence-gated so 19/20/21 are byte-identical; the button stays the AIRFRAME cycler by slice-20's PRECEDENT.
  **TWO SCENARIOS, and the split is a MEASURED CONFIG CONFLICT** (the lift half needs k_drop 0.7 / δ_max 0.4, the
  departure half k_drop 1.0 / δ_max 1.0, and at 0.7 the cliff is INVISIBLE) — one verifier auto-detects which.
  **HALF B = RELAXED STATIC STABILITY**: *a statically unstable airframe is perfectly flyable — UNTIL THE
  AUTOPILOT RUNS OUT OF AUTHORITY; the THRESHOLD is the lesson, not the tumble.* ⭐⭐ **A THREE-POINT CLAIM WHOSE
  LESSON IS THE MIDDLE** — 0-vs-8 would show "neutral vs lost", a WEAKER and DIFFERENT claim, because cma_post 0 is
  **NEUTRAL past the break, not unstable at all** (sentinel SILENT). The lesson is **cma_post 4: the ω_sp sentinel
  FIRES (60 frames / 947 ticks — genuinely no short-period mode) and the autopilot HOLDS IT ANYWAY** (α@500 0.434,
  miss 1.078× baseline); only at 8 does it LOSE it (α@500 1.008 = 57.8°). ⭐ **SLICE 16's ω_sp SENTINEL FIRES IN
  FLIGHT — FIRST TIME IN PROJECT HISTORY** (built for an AUTHORED Cmα ≥ 0; reaches the wire as FINITE_CEIL, never
  a NaN), and it is **SLICE 16's TUMBLE NOW SELF-INFLICTED** — an engineer typed the unstable case there; here the
  airframe FLIES ITSELF INTO IT. ⚠ **THE MISS IS NOT THE METRIC for half B** (+1.4% even at full tumble — a
  missile that departs 0.7 s before CPA keeps its momentum) ⚠ and **"time with ω_sp ceiled" RUNS BACKWARDS**
  (60 frames at cma_post 4 vs 33 at 8 — α blows past α_sat into the deep-stall RESTORING region), so it is a
  BOOLEAN tell, never a severity measure. ⚠ **α IS SAMPLED AT FIXED RANGE (500 m), NOT AT CPA** — the break is
  reached at t=3.12/r=1475 in EVERY arm, α_pk lands ON the CPA frame, and **the lift file's LOS gate of 1000 would
  DELETE this lesson** (α@1000 spans only 0.297→0.399): the correct gate DIFFERS between the halves. Knob domains
  MEASURED: `af_alpha_stall ∈ [0.15,0.35]` (the miss TURNS at ≈0.12 and REVERSES — the 3rd occurrence of that
  pattern) and `af_cma_post ∈ [0,10]` (defl_sat exactly 0 through 10, monotone, first binds 65 at 10.5 — a ~1.03×
  margin, NOT slice-20's 2×, stated rather than hidden). ⚠ **NEVER quote gate-0's 2.7779 departure α** — it was
  measured with δ_max 0.4 BINDING, which AMPLIFIED the divergence (relieving it drops α_pk 3.02 → 1.22); the clean
  progression is 0.64 → 0.97 → 1.22. Class **4c** (8th consecutive; no RNG ⇒ draw-invariance VACUOUS);
  **INERT without `:pitch_coupled`** (the third conjunct is deliberate — `pitch_moment` is live on the point-mass
  rotational path, so without it half the missile would fly a breaking moment and half a linear-aero fiat accel);
  **stall × ρ(z) is a LOAD ERROR**, refused rather than silently branch-ordered. Four proofs green (verifier both
  halves; UI test with FOUR teeth on the G10 edit incl. the MIRROR case proving a SWITCH not an `or`, + a SIX-WAY
  value-guard, + all seven prior UI tests re-run; smoke-load both servers; TWO shots — "POST-STALL" lit on the
  stall wire, and the departure with `omega_sp 1000000000`, the nose 34.2° off velocity, and the trail CURLING
  BACK ON ITSELF). Deferred (NAMED): a STALL-AWARE AUTOPILOT (the multivalued inverse); HYSTERESIS; Mach;
  **ROLL/YAW DEPARTURE — the sharpest remaining approximation** (this one departs strictly IN-PLANE; dies only
  with bank-to-turn / 3-D); DEPARTURE RECOVERY / a spin model (the ONSET ships, not the aftermath). (4180)

- **Slice 23 (§11 Tier-A, the FIRST slice of the bank-to-turn / 3-D arc) — 6-DOF SUBSTRATE + SKID-TO-TURN: THE
  OUT-OF-PLANE ENGAGEMENT**: cashes the sharpest approximation the whole aero arc carried. Since slice 19,
  `alpha_command` PROJECTS the guidance command onto the in-plane direction `n̂ = (−sinγ, 0, cosγ)` and **DISCARDS
  the out-of-plane component** — a target off the x–z plane was *unflyable BY CONSTRUCTION*. Slice 23 makes `att` a
  GENUINE 3-D quaternion integrated from a body-rate vector `ω = (p, q, r)` (NEW comp keys `:att_q`/`:omega_body`,
  PARALLEL to `:pitch_theta`/`:pitch_q`), keeps the guidance command's FULL 3-D direction, and adds a SKID-TO-TURN
  autopilot that makes lift in BOTH body planes at once (α → pitch lift, β → yaw side-force). **THE LESSON: a
  pitch-plane airframe can only pull g in the plane it is already in; STT makes lift in two body planes at once —
  and the out-of-plane target that was unflyable becomes a hit.** New pure lib `airframe3d.jl` (reuses frames.jl's
  quaternion algebra). Gate-0 (8 probes) HELD the plan: **P4 → the RESULTANT clamp `hypot(α,β) ≤ α_max`** (the
  total maneuver-g ceiling is the SAME `a_max_aero` as the pitch plane — STT REPOINTS the authority in 3-D, it does
  not get MORE); include the ω×Iω term; a static cross-range target (the discard's miss ≈ Y is clean). One new
  load-bearing finding: **the pitch/yaw MOMENT SIGN is NOT symmetric** (physical nose-up is a −y body rotation but
  nose-toward-+y is a +z, so the pitch moment is NEGATED onto −y and the yaw is not, `α̇ = −ω_y`, `β̇ = +ω_z` — the
  #1 SIGN TRAP's 5th occurrence). `:airframe` gains a THIRD rung `:six_dof` (the A/B: `:pitch_coupled` discards and
  misses, `:six_dof` STT intercepts). Wire (Y=2000 cross-range, ρ=0.3, static aero-free target): `:pitch_coupled`
  miss **2002.37 m** with `max|pos_y| = 0.0 EXACTLY` (fully discarded — never leaves x–z) vs `:six_dof` **0.230 m**
  with `max|y| → 2720` (it TURNED); ~8700× (frame-sampled 399.6×). The CAUSATION lever `af_cy_beta → 0` kills the
  yaw authority and DEGENERATES the STT plant EXACTLY back to the discard. The reduction golden must SHRINK with dt
  (the advisor's wiring-bug detector — 4.46e-11 → 2.14e-12, ~20.8×, not `==`). ⚠ A gate-2 ADVISOR CATCH — the
  slice-21 `_atm_on` latent-bug class recurring: the `build_env!` six_dof readout block was first key-gated on
  `haskey(:att_q)`, which is never deleted, so a cross-toggle off `:six_dof` fired the stale block on a FROZEN
  attitude; FIXED by rung-gating BOTH rotational blocks on the LIVE `:airframe`. CLIENT: a NEW handshake
  discriminator `airframe_6dof` (a missile carrying authored `:af_cy_beta`) upgrades to a TRUE 3-D view REUSING
  slice-18's terrain SubViewport machinery (`_mode = "airframe3d"`) MINUS the heightfield; the `:airframe` cycler
  is now 3-RING via a PER-SCENARIO `_airframe_rungs` (slice 17/19 stay 2-ring — six_dof is a dead rung there). Class
  **4c** (9th consecutive — truth-fed PN, no seeker ⇒ "draw-count invariance" VACUOUS; live-settable, no
  set_fidelity guard). Four proofs green (verifier: the discard/hit miss split + af_cy_beta→0 causation + replay
  bit-identical; UI: the 3-D routing + 3-ring cycler + FIVE-way multi-view value-guard + all seven prior UI tests
  re-run; smoke-load; TWO contrasting shots — the six_dof trail CURVING out of the plane vs the pitch_coupled
  STRAIGHT trail, "cross-range +1024 m" vs "+0 m"). Slices 1–22 byte-identical. Deferred (NAMED): **slice 24 =
  BANK-TO-TURN + roll-lag** (the same substrate, α-only lift + a finite-bandwidth roll autopilot, the `:steering`
  rung); aero+inertial cross-coupling / departure; a SEEKER in the 6-DOF loop; an out-of-plane MANEUVERING target;
  induced/separation drag + ρ(z) on the 6-DOF path. (4276)

- **Slice 24 (§11 Tier-A, the bank-to-turn arc's PAYOFF) — BANK-TO-TURN + ROLL-LAG: the steering law that must
  bank before it turns.** Slice 23's SKID-TO-TURN makes lift in BOTH body planes at once (α pitch + β yaw) → it
  points its ⟂-v accel anywhere with NO roll and intercepts the out-of-plane target. BANK-TO-TURN makes lift in
  ONE plane (α only; β driven → 0, COORDINATED) and must ROLL the body to point it, with a FINITE bandwidth
  τ_roll → against the SAME target STT hit, BTT MISSES. The `:steering = (:skid_to_turn, :bank_to_turn)` rung on
  the HELD `:six_dof` plant (the ONE toggled fidelity; INERT without `:airframe:six_dof` — the cross-fidelity
  dependency, steering-on-airframe). New `airframe3d.jl`: `STEERING_MODES`, `bank_angle` (roll about v̂ — the #1
  SIGN TRAP's 6th occurrence), `steering_bank_command` (REVERSIBLE-LIFT + NEAREST-REPRESENTATION bank — gate-0
  killed the naive ±90° flip, which churns 180° in-plane [PROBE F] / chatters at the 90° singularity [PROBE G]),
  `btt_roll_moment` (the ζ=1 bank autopilot, τ_roll the SOLE lever — I_xx a NON-knob), `btt_moments` (the
  `stt_moments` sibling — pitch/yaw DUPLICATED, roll swapped). ⭐⭐ **THE GATE-3 MECHANISM CORRECTION (advisor):
  the BTT miss is a DOWNSTREAM AERO-CEILING miss, NOT the kinematic "time banking is time not turning" — the
  roll lag leaves the missile behind → the catch-up demand pegs the SAME slice-19 ceiling (`aero_sat` 93.2% of
  the bank_to_turn approach vs 0.2% for STT; τ_roll→0 removes BOTH the lag AND the saturation, 93.2%→0.2%). The
  19/23 CONTRAST, precise: the ceiling binds in 19/20/21/22/23/24, but under `:bank_to_turn` it binds BECAUSE
  the roll lag leaves the missile behind (downstream of the steering law), under 19/23 from the FLIGHT CONDITION
  itself. Slice 24 adds no new cap — a new UPSTREAM CAUSE that drives demand into the existing cap.** Gate-0
  (8 probes) forced the nearest-rep law + one framing correction (route (a) static is the COLD-START face; the
  SUSTAINED-TRACKING face, an out-of-plane MANEUVERING target, is a NAMED DEFERRAL); the ω×Iω term goes LIVE
  under BTT (p≠0) but is IMMATERIAL to the miss (≤3% — the RATES stay small under coordinated flight, NOT the
  diagonal-I cross-coefficients [~0.9]). Wire (seed 24, frame-sampled): STT **0.230** (== slice 23 — byte-
  identical STT path) vs BTT τ_roll=1.0 **371.79** (74× frame / 1614× per-tick, max|y|→2704 — it TURNED, LATE);
  τ_roll→0.01 RECOVERS **0.133** (causation — the roll LAG caused the miss), τ_roll=2.0 SATURATES **1535**
  (toward the discard ≈ Y=2000, no reversal); in-plane Y=0 → max|y|=0.0 EXACTLY (the sign invariant). ⚠ The
  recovery drives `af_tau_roll → 0.01`, BELOW the slider min 0.1 (a headless causation probe, not in-range); a
  direct `set_param af_tau_roll = 0` stays FINITE (`_FRAME_EPS` floor — convention 6). CLIENT: the slice-24
  handshake reuses slice 23's 3-D airframe view but routes the button to the STEERING cycler (a within-airframe3d
  SWITCH, value-guarded so slice 23 keeps the airframe cycler); the HUD labels the steering law + shows bank φ, a
  magenta lift-axis vector shows the bank. Class **4c** (10th consecutive). Four proofs green (verifier: the miss
  split + af_tau_roll→0 causation + bit-identical replay; UI: the steering cycler + the slice-23 MIRROR [a SWITCH
  not an `or`] + a SIX-way value-guard + prior UI tests re-run; smoke-load → `DONE`; TWO shots — BTT bank φ=120°
  + aero_sat=1 [the shipped branch] vs STT omega_p≈0 + β=6.9° [the else]). Slices 1–23 byte-identical, proven ON
  THE WIRE (slice23_verify re-run reproduces SIX_DOF 5.011 / ratio 399.6× / CY_ZERO 2002.373). (4335)

- **Slice 25 (§11 Tier-A, the 3-D arc's SENSOR slice) — A SEEKER IN THE 6-DOF LOOP: the seeker that cannot see
  out of the plane.** Slices 23/24 gave the missile an airframe that can turn out of the x–z plane and a choice
  of how to point its lift — both TRUTH-FED. Slice 11's seeker measures a SCALAR in-plane bearing and rebuilds
  `ω = (0,−λ̇,0)`, STRUCTURALLY incapable of an out-of-plane component, so **the 6-DOF missile is never TOLD to
  turn**: same 2000 m miss, from the SENSOR. ⚠ **SAME SIGNATURE AS SLICE 23's FOIL, DIFFERENT MECHANISM** (the
  copy-paste false-claim trap): 23's autopilot THREW the command away; here the plant is `:six_dof` and fully
  capable — the command was never FORMED. New `frames.jl` kernels `los_unit_from_angles` / `los_rate_from_angles`
  (`ω = û × û̇`, the #1 SIGN TRAP's 7th) — **the oracle is an IDENTITY** (`(r×v)/‖r‖² ≡ û × û̇`), pinned vs an
  INDEPENDENT closed-form `(ȧz,ėl)` recompute; ⚠ measure it EXCLUDING the init ticks (tick-1 3.4e-2 vs 8.9e-5
  after — round 1 nearly read it as a sign error). NEW key `:seeker_axes = (:pitch_plane, :az_el)`, NOT a 4th
  `SEEKER_MODES` rung (those name the TRACKER, not the DIMENSIONALITY). ⭐⭐ **THE 2-DRAW LOCKSTEP makes the
  button legal**: both rungs draw 2 randn/tick and the foil DISCARDS the azimuth sample (gate the VALUE, never
  the draw) — else the toggle is a 1↔2 draw-topology flip and `set_fidelity` must reject the switch the
  showcase needs. The HOST is the scenario's `two_angle` marker, NOT the fidelity ⇒ introducing the key on a
  slice-11/13 wire is INERT (P11, a test). Dispatch precedence EXPLICIT; `two_angle × seeker: scan` is a LOAD
  ERROR (slice-21 "refused, not branch-ordered"). ⭐ **THE ISOLATION forced a retune off slice 24's wire**
  (advisor): at ρ=0.3 the hit-arm saturates 93.9% and misses 1268 m; at ρ=1.0/σ=0.3 mrad **`aero_sat` is 0 in
  BOTH arms** ⇒ a POINTING miss, NOT the arc's 7th ceiling miss (asserted as a number, the FLAG never a
  hand-rolled compare — the sets nest). Class **4a — the 10-slice 4c streak (14–24) ENDS and the seed is
  load-bearing again for the first time since 13**; replay is SEEDED determinism, not "RNG-free". Wire (seed
  25): pitch_plane **2000.044** with max|y| and omega_oop **0.0 EXACTLY** vs az_el sub-metre per-tick;
  ⚠ the verifier's frame grid ≠ the probe's and a HIT samples COARSELY (1.373 / 1456× vs 9.555 / 209×) — the
  asserts are ONE-SIDED and **the pass text INTERPOLATES what the run measured**. ⚠ This file reproduced slice
  21's `%g`-is-not-a-GDScript-specifier bug verbatim (the whole `%` fails silently on a GREEN run). ONE knob
  `sigma_seek ∈ [5e-5,3e-4]` — the REALISM lever, NOT the lesson (non-monotone in σ); `rho` DISQUALIFIED (its
  isolated domain is only [1.0,1.5]) along with `beta`/`speed`, asserted ABSENT in the verifier. Four proofs
  green (SEVEN-way UI value-guard; TWO shots: "BLIND out of plane" +0 m / ω_oop 0.00000 vs "AZ/EL — LOS rate in
  3-D" +983 m / 0.00929). Slices 1–24 byte-identical, proven ON THE WIRE (23/24 verifiers re-run to the digit).
  Deferred (NAMED): **RADOME / body-rate parasitic loop** (this slice is its prerequisite); seeker FOV/gimbal;
  monopulse / az×el CFAR; a measured Vc; the 3-D `:raw` arm; **seeker noise × the BTT roll loop = DEAD, not
  deferred** (a ~1000:1 low-pass: std(Δφ_cmd) 1.07 vs std(Δφ_ach) 1.6e-5 — the slice-20 dead-fin precedent). (4399)

- **Slice 26 (§11 Tier-A, the 3-D arc's NAMED END POINT) — THE RADOME / BODY-RATE PARASITIC LOOP: the seeker
  that sees the missile's own nose.** The seeker does not look at the target directly — it looks through a
  RADOME, which REFRACTS by an amount depending on WHERE IT IS LOOKING: `ε ≈ R·(look angle off the boresight)`.
  So the missile's OWN body rotation MOVES the LOS it reports, with the target standing still — a feedback path
  `q → look → ε → apparent λ̇ → PN → a_cmd → α → q`. **This is the GUIDANCE LIMIT CYCLE slice 15 NAMED, slice 19
  DEFERRED and slice 20 HUNTED AND KILLED on the ACTUATOR path** (`δ_max` shadows `δ̇_max`, its FINDING 7) —
  it lives on the SENSOR path. ⚠ **THE PROJECT'S FIRST TRUE POSITIVE-FEEDBACK INSTABILITY, and the phrase slice
  20 FORBIDS is EARNED here**: a LOOP GAIN, a STABILITY BOUNDARY, and SELF-EXCITATION FROM ZERO INPUT (at
  σ_seek = 0 — a NOISELESS seeker — R = −0.10 still rings, 106×). Do not import slice 20's "degenerative
  spiral" language, and do not export slice 26's. ⭐⭐ **THE THRESHOLD FACTORIZES AS A LOOP GAIN**:
  `N·|R_crit| ≈ 0.38` to ±3% across N ∈ {3…8} and `|R_crit| ∝ ρ` — a MEASURED boundary, NOT an algebraic
  identity (do not write it in slice 21/22's language). The payload is the DESIGN TRADE: **you cannot buy N
  without buying glass.** ⭐ **THE METRIC IS AN OSCILLATION, NOT A MISS — a NEW KIND of gate-3 proof** (slice
  20's plan sketched it for the cycle it never shipped): rms body pitch rate **0.01245 → 0.88138 rad/s = 70.8×**
  between R = −0.09 and −0.10. ⚠ **The MISS is NOT the metric and is NOT MONOTONE ANYWHERE — the ringing arm
  STILL HITS (2.18 m)**, and `max|q|` is neither frame- nor noise-robust (peaks OVERLAP across the threshold):
  **rms, never the peak.** ⭐ And the rms metric IS frame-robust (0.88372 frame vs 0.88138 tick), **REVERSING
  the arc's usual sampling caveat** — which is exactly why it beats any miss here. ⚠ TWO WINDOWS, TWO RATIOS,
  both honest (mid-half ticks 70.8× / the verifier's closing-frames 23.0×) — quote each with its window.
  ⭐ **THE ISOLATION IS NOT SLICE 25's and must not copy it**: `aero_sat == 0` is IMPOSSIBLE (an oscillation
  drives demand into the ceiling, 60.8%). Instead **raise α_max 3× and THE ONSET DOES NOT MOVE** — only the
  amplitude grows: **the ceiling BOUNDS the cycle, the radome decides whether there IS one.** ⚠ `Cmq` from −50
  to −250 leaves the onset EXACTLY where it was ⇒ **"more aero damping fixes it" is REFUTED**; this is a
  GUIDANCE-loop instability (k_q supplies ~98% of the damping — slice-20 FINDING 3), ringing near 1.7–2.1 Hz vs
  the airframe's own 1.396 Hz. ⭐ **The mechanism is FRAME-EXACT and measuring it caught a SIGN ERROR in the
  plan's own first draft (#1 sign trap's 8th)**: on a FROZEN geometry `ε̇_el = +R·cos(look_az)·ω_y`,
  `ε̇_az = −R·ω_z` — the textbook `−R·θ̇` transliterated to `−R·q` is the WRONG SIGN here (nose-up is a −y
  rotation, so `θ̇ = −ω_y`), and it survived into a hand-written test until the PAIRED coefficient assert
  contradicted it. ⚠ **AND IT CANNOT BE IDENTIFIED IN CLOSED LOOP** (R² = 0.999 with `a/R` = 1.9…5.5 — `ėl` and
  `q` are collinear on a tracking missile): **freeze the geometry.** ⚠ Only NEGATIVE slopes ring; positive ones
  DE-TUNE (`ω_app/ω_true` → 0.593, the miss opens from sluggishness) — one knob, two failure modes, the `af_cma`
  shape. ⚠ **`omega_ratio` is a DIAGNOSTIC, not the mechanism** — once ringing it is the same fact as `rms q`
  told twice. ⭐ **BYTE-IDENTITY MEASURED STRONGER THAN EXPECTED: an authored `R = 0` is BIT-IDENTICAL to the
  key being absent**, which VERIFIES the knob-vs-rung discriminator instead of arguing it. RUNG-gated on the
  LIVE `:airframe === :six_dof`, never on `haskey(:att_q)` (the slice-21/23 latent-bug class, 3rd occurrence).
  Class **4a** (2nd consecutive; the seed is load-bearing). ⚠ **THE BUTTON IS DROPPED and the slice-20
  inherited-cycler precedent DOES NOT TRANSFER**: `:pitch_plane` would leave the radome LIVE beside slice 25's
  unrelated 2000 m blind miss — two mechanisms in one view. Slice-16 Option-P′, and the drop needs BOTH the
  mode-entry AND `_update_fid_btn`. ONE knob `radome_slope ∈ [−0.12,+0.06]` (bounded by the metric's PLATEAU);
  `n_pn`/`rho`/`af_alpha_max`/`sigma_seek` DISQUALIFIED and asserted ABSENT in the gate. Four proofs green
  (S26V 0.80408 vs 0.03493 = 23.0×, mirror 59.2×, replay 0.0; EIGHT-way UI guard; TWO shots at the same range:
  "RADOME PARASITIC LOOP — RINGING" q +1.168 vs "RADOME — refracting, loop STABLE" q +0.019). Slices 1–25
  byte-identical, proven ON THE WIRE (23/24/25 verifiers re-run to the digit). ⭐ Post-commit
  (advisor): the DECLARED DOMAIN'S ENDPOINTS are now MEASURED, not inferred from the interior — a
  `DOMAIN_MIN` phase at −0.12 (where aero_sat runs 95%) shows `defl_sat` 0/499 and the metric
  PLATEAUING, which is the measured reason the domain stops there; and the two shipped-but-unasserted
  telemetry keys (`omega_ratio`, `radome_eps_az`) got a tooth each. (4476)

- **Slice 27 (§11 Tier-A, the 3-D arc's ENGINEERING ANSWER) — THE RADOME-SLOPE COMPENSATION AUTOPILOT: buying
  margin with a gyro.** Slice 26 named this slice as its own successor. The missile already carries a rate gyro
  (the α/β autopilot has fed on `:omega_body` since slice 23), so feed slice 26's MEASURED coupling forward with
  the slope the guidance computer BELIEVES it has (`R̂`) and subtract it: `Δȧz = +R̂·ω_z`, `Δėl = −R̂·cos(look_az)·ω_y`
  (`frames.jl` `radome_compensation`). ⚠ **THOSE SIGNS ARE THE NEGATION of slice 26's parasitic gain (the #1 SIGN
  TRAP's 9th) and the plan's first draft had BOTH flipped** — which DOUBLES the term at `R̂ = R` while still
  producing a plausible sweep (the ring quiets at `R̂ = −R`) and the slice gets written up backwards; the tooth is
  the CANCELLATION measured against the SHIPPED `radome_error` on a FROZEN geometry, never the formula restated.
  ⭐⭐ **THE BOUNDARY SHIFTS ONE-FOR-ONE — AND THE SAME MEASUREMENT IS THE ISOLATION**: the onset RESIDUAL is
  CONSTANT at −0.095 across a 6× span of R̂, an OFFSET not a gain. That matters because the obvious alternative
  story is DE-TUNING (slice 26 measured `ėl` and `q` COLLINEAR, R² = 0.999, so the correction is numerically
  near-indistinguishable from scaling `ėl` down = lowering effective N), and **a gain cannot produce a constant
  offset**; the miss staying at baseline is the second discriminator. ⭐ Slice 26's law returns VERBATIM:
  `N·|R − R̂|/ρ` = 0.390/0.400/0.400/0.390/0.400 at N = 3…8 (⚠ a MEASURED boundary, never an "identity" — slice
  26's rule). The payload is a REQUIREMENT NUMBER: *you cannot buy N without buying glass — or you can buy a gyro
  and KNOW your glass to within `0.38/(N·ρ)`* (here ±0.0475). ⚠⚠ **BUT IT IS NOT AN EQUIVALENT RADOME**: over-
  compensating to a residual of +0.15 misses by 31.4 m where a BARE +0.15 radome misses by 0.47 — the look angle
  moves for TWO reasons and **a gyro can only cancel what a gyro can see** (the body-rate half exactly, hence the
  exact boundary; the LOS-driven half survives). ⭐ **THE ARCHITECTURE WAS MEASURED, NOT ASSUMED**: an ANGLE-domain
  corrector RINGS at `R̂ = R = −0.50` despite PERFECT knowledge, because it needs the look angle and can only see
  it THROUGH the bend it is removing (error second order in `R·R̂`) ⇒ **compensate with a signal that is not itself
  corrupted by what you are compensating** — a general result, and `:angle` does NOT ship. ⚠⚠ **GATE-1 FINDING:
  the two-term law leaves the PITCH→AZIMUTH cross-term uncancelled** (the testset FAILED on it first, 0.005984 vs
  a 2e-4 tolerance) — a §1 approximation OF THE COMPENSATOR, harmless because ELEVATION is the loop-closing
  channel (0.9487 vs 0.0598, ~16×), now PINNED at `R̂·k_cross·ω_y` against a MEASURED coefficient. Wire (seed 27,
  N = 8, R = −0.10 — ⚠ the wire chosen on **MODEL VALIDITY**: the alternative R = −0.30 puts 5.3% of ticks past a
  30° look angle vs 0.06% here, and `n_pn` stays AUTHORED, never a knob): rms q 0.844 → 0.0135 (62.4× per-tick,
  54.7× frame). ⭐ **TWO KNOBS, convention 9 satisfied by a MEASUREMENT not by counting sliders** — the DIAGONAL
  (move both together and NOTHING happens), both knobs crossing at the SAME residual (−0.045 from opposite
  directions), and the (R, R̂) grid being a DIAGONAL BAND of which **slice 26 is the `R̂ = 0` column**. Class **4a**
  (3rd consecutive RNG-live; draw-count identity ASSERTED); KNOB not rung (`R̂ = 0` is BIT-IDENTICAL to the
  compensator not existing, measured); the button stays DROPPED (16/26/27). ⚠ **The shot harness CAUGHT A REAL
  DEFECT**: the first shot read "COMPENSATED — loop STABLE" on the RINGING arm, because a limit cycle crosses zero
  twice per cycle so an INSTANTANEOUS verdict mislabels half the frames — fixed with a display-only PEAK-HOLD
  (an instrument, not physics) plus a three-state label. ⚠ **And the VERIFIER caught a second**: its first de-tune
  assert compared two FRAME-sampled CPAs (3.305 vs 5.269) — that measures the ~11 m frame grid, not the physics
  ([[ewsim-missile-verifier-sampling]]: a HIT samples COARSELY). Four proofs green (S27V FIVE phases incl. ⭐ MARGIN
  — the same R̂ on worse glass RINGS AGAIN — and ⭐⭐ DIAGONAL; S27UI NINE-way guard + the slice-26 HUD mirror; smoke;
  TWO shots). Slices 1–26 byte-identical, proven ON THE WIRE (25/26 verifiers re-run to the digit). (4545)

- **Slice 28 (§11 Tier-A, the 3-D arc's SIXTH slice) — `R(look)`: THE SLOPE CURVE, AND THE BAND THE ENGAGEMENT
  VISITS.** Slices 26 and 27 both assumed the glass has ONE slope. It does not: a radome's error slope is a CURVE
  in look angle, and slice 26's loop is closed by its **LOCAL DERIVATIVE at the look angle the missile is actually
  flying** — which is set by the ENGAGEMENT, not by the radome. ⭐⭐ **THE WHOLE SLICE IS ONE PAIR OF NUMBERS THE
  CORE SHIPS, and slice 27 could not have written it (it had one of the two keys, because it had one slope):** the
  HARDWARE residual `radome_residual` = `R₀ − R̂` is **EXACTLY 0.000** — the compensator matches the glass it was
  characterized against, perfectly — **and the missile RINGS**, because the ENGAGEMENT residual
  `radome_residual_az` = `R(look_az) − R̂` runs −0.100…−0.052. Drag R̂ to −0.13 = R(15°) and the two numbers TRADE
  PLACES (hardware +0.100, engagement 0.000) and it goes quiet ⇒ **the scalar that works is set by the ENGAGEMENT,
  and characterizing at BORESIGHT is the natural AND DANGEROUS choice** (`R(0) = R₀` for every amplitude — exactly
  right in the one place the loop is never closed). ⚠⚠ **THE WIRE CHANGES AND THE MEASUREMENT IS THE REASON** —
  the FIRST slice of the arc to break the shared static Y=2000 geometry: a static target's collision course carries
  ZERO LEAD (|look| 0.04°→0.54°, measured on a STABLE arm — a ringing arm's look angle swings BECAUSE it rings) so
  `R(look)` would be a DEAD KNOB there; a CROSSING target (vy=200) holds a sustained ~15° lead. ⭐⭐ **THE ISOLATION
  IS NON-MONOTONE IN THE GEOMETRY** (QUIET→RING→QUIET, rms r 0.016/1.042/0.011 at vy 0/200/400, with the no-ripple
  CONTROL flat quiet throughout) — and it defeats a REAL confound: crossing moves the constant-R onset to
  |R_crit|≈0.065 vs 0.05 static WITH NO CURVE ANYWHERE. **A confound cannot produce a non-monotone response to a
  monotone change.** ⭐ **WHAT LICENSES THE SLICE: THE LOOP TRACKS THE DERIVATIVE, NOT THE BEND** — RIPPLE 1.064
  rings / matched-SECANT 0.016 quiet / matched-DERIVATIVE 0.838 rings ⇒ a radome inside its boresight-ERROR spec
  everywhere can still ring. ⚠ Measured at R₀=0 deliberately (on the shipped wire the secant is past critical and
  BOTH arms would ring — the trap that spoiled two gate-0 runs). ⚠ **THE METRIC IS `rms r` (YAW), a DELIBERATE
  departure from 26/27's rms q** (the lead is in AZIMUTH) — and the pitch channel beside it is **THE CHANNEL
  SPLIT**, the second isolation: R(look_az) −0.130…−0.082 vs R(look_el) pinned at −0.030, rms r 1.042 vs rms q
  0.101, **a signature no CONSTANT slope can produce** (a constant rings both together, 0.838/0.844). ⚠ Window =
  RANGE BAND [500,3000] m (a crossing wire's rms r has a LEGITIMATE front-loaded baseline: 0.172 whole-approach vs
  0.0138 in band; arms with different ToF would compare different parts of the engagement); frame-robust; the miss
  is NOT the metric (every arm hits). ⭐ Curve form = a BOUNDED slope ripple `R₀ + A(1−cos(k·look))` with ε its
  exact integral — **the CUBIC was KILLED at gate 0** (unbounded slope ⇒ the bend diverges, miss → km, onset and
  breakdown too close for a domain). ⚠⚠ **TWO planned verifier phases MOVED to `test_missile.jl` — NEITHER IS
  CLIENT-DRIVABLE** (target velocity isn't a comp key; `radome_slope` isn't a slice-28 knob) — the slice-27
  precedent, and the relocation is stated in the verifier header. TWO knobs (A ∈ [−0.10,0], R̂ ∈ [−0.15,0]) = two
  halves of ONE quantity; `k` AUTHORED and DISQUALIFIED BY NON-MONOTONICITY (4th occurrence). Class **4a** (4th
  consecutive RNG-live); KNOB not rung (A=0 bit-identical to the key absent, measured); button DROPPED (16/26/27/28).
  ⚠ NOT zero client code: a THREE-WAY HUD switch + **both instruments follow the RINGING channel** (`omega_r` here,
  `omega_q` on 26/27 — a peak-hold left on pitch meters the QUIET channel). ⚠ The first shot ran two new lines off
  the right edge (~55 chars fit at 15 px). ⚠ **`N·|R−R̂|/ρ ≈ 0.38` IS NOT GEOMETRY-FREE** — ≈0.52 here; the FORM
  transfers, not the number. Four proofs green (S28V FIVE phases: RINGING 1.04145 / REPLAY 0.0 / FLAT 72.1× with
  both gains collapsed onto −0.030 / ⭐⭐ CURED 80.7× with the residuals mirrored / ⭐ DOMAIN reaching the exact bound
  −0.23000; S28UI TEN-way guard + the THREE-WAY mirror + the channel switch on identical telemetry; smoke; TWO
  shots at the same range). Slices 1–27 byte-identical, proven ON THE WIRE (25/26/27 verifiers re-run to the
  digit). (5013)

---

## 3. The arc narrative — which slice opened and closed what

(The missile guidance arc — slices 8–12 — and its CAPSTONE slice 14 are COMPLETE; the countermeasures arc opened
with slice 13. HANDOFF §10 items 1–13 — the committed roadmap — are all DONE; slices 15–24 are into the §11 Tier-A
horizon — slice 15 the actuator/fin half, slice 16 the 6-DOF airframe's rotational half (pitch-plane θ,q), slice 17
the α→lift→γ TRANSLATION-COUPLING half (the real path-changing `:airframe` toggle), slice 18 terrain masking + the
3-D client view, slice 19 the CLOSED INNER LOOP (`a_cmd→α_cmd→δ`) + the flight-condition g-limit — which COMPLETES
the Tier-A "6-DOF airframe + actuator/fin dynamics" entry in the pitch plane (15 = fin, 16 = rotation, 17 = the
α→lift coupling, 19 = the closed loop) — slice 20 INDUCED DRAG, which makes that closed loop's ceiling
SELF-LOWERING (the aero arc's first feedback, and the first slice whose lesson is a KNOB with no button at all),
slice 21 the EXPONENTIAL ATMOSPHERE, which gives that same ceiling a THIRD mover — WHERE THE MISSILE FLIES —
and CLOSES 19+20's constant-ρ approximation ("high altitude" is now earned language, not a standing caveat), and
slice 22 NONLINEAR C_L(α) / TRUE STALL, which finally moves the OTHER FACTOR: 19/20/21 all moved Q, while all three
assumed the lift curve runs straight out to α_max. It does not — past α_stall C_L PEAKS AND FALLS, so the ceiling
is the curve's own INTERIOR PEAK, and the cap stops being a MAGNITUDE THAT SATURATES and becomes a DERIVATIVE THAT
CHANGES SIGN. Slice 22 also closes the ceiling-LEAK path that BOUNDED slice 21's H floor, and its second half
(RELAXED STATIC STABILITY) makes slice 16's authored tumble SELF-INFLICTED — the airframe flies itself unstable,
and slice 16's ω_sp sentinel fires in flight for the first time in the project's history.
**The slice-20 slot was CONTESTED**: the planned SCALAR rate-limited fin inside the coupled loop [the guidance
limit cycle] is **DEAD, not deferred** — gate 0 killed it in 4 probes (`δ_max` structurally SHADOWS `δ̇_max`: the
fin only needs to move fast when the command does, which requires high k_α or low damping, and BOTH peg deflection
first — see `docs/plans/slice20.md`, a worthwhile general result). **The FULL 6-DOF airframe is now UNDERWAY:
slice 23 OPENED the bank-to-turn / 3-D arc with the 6-DOF substrate + SKID-TO-TURN — the pitch-plane out-of-plane
discard finally dies (the out-of-plane target, unflyable BY CONSTRUCTION since slice 19, now intercepts). Scoped
STT-first as a 2-slice arc, and slice 24 = BANK-TO-TURN + roll-lag CLOSED it (the same substrate, single-plane
lift + a finite-bandwidth roll autopilot, the `:steering = (:skid_to_turn, :bank_to_turn)` rung on the HELD
`:six_dof` plant — against the SAME out-of-plane target STT hit, BTT MISSES because it must ROLL to point its
one lift plane and the roll LAGS). ⚠ The slice-24 gate-3 correction (advisor): the BTT miss is a DOWNSTREAM
aero-ceiling miss — the roll lag leaves the missile behind, the catch-up demand pegs the SAME slice-19 ceiling
(`aero_sat` 93.2% of the approach vs 0.2% for STT; τ_roll→0 removes BOTH the lag and the saturation) — NOT the
kinematic "time banking is time not turning" one-liner, and the 19/23 contrast must be written precisely (the
ceiling binds in both, but under BTT it binds BECAUSE of the roll lag, downstream; under 19/23 from the flight
condition itself). **The arc then took its SENSOR slices and CLOSED: slice 25 put a real seeker in the 6-DOF
loop (slice 11's scalar in-plane bearing rebuilds ω = (0,−λ̇,0), so the missile that CAN turn out of plane is
never TOLD to — 2000 m from the SENSOR), and slice 26 cashed the arc's NAMED END POINT, the RADOME / body-rate
parasitic loop: the seeker looks through glass whose bend depends on the LOOK ANGLE, so the missile's own body
rate feeds back into the LOS it reports, and past a LOOP GAIN N·|R|/ρ ≈ 0.38 it SHAKES ITSELF into a sustained
limit cycle — the guidance limit cycle slice 15 named and slice 20 killed on the ACTUATOR path, alive on the
SENSOR path, and the project's FIRST true positive-feedback instability. Slice 27 then cashed slice 26's OWN
named successor — the RADOME-SLOPE COMPENSATION AUTOPILOT — and the arc's engineering answer turns out to be a
PARTIAL one, exactly quantifiably: a rate-gyro feed-forward cancels the parasitic term to the accuracy of the
slope estimate it is given, so what closes the loop is the RESIDUAL `R − R̂` and slice 26's boundary returns
verbatim as `N·|R − R̂|/ρ ≈ 0.38` — MARGIN, NOT IMMUNITY, and "how good is my radome?" becomes "how well do I
KNOW it?". And slice 28 CASHED the deferral 26 and 27 both named — `R(look)`, the SLOPE CURVE: the residual stops
being a property of the HARDWARE and becomes a property of the ENGAGEMENT, because the loop is closed by the
curve's LOCAL DERIVATIVE where the seeker is actually looking. A crossing target holds a sustained lead, so a
BORESIGHT-characterized compensator has a HARDWARE residual of exactly 0.000 and rings anyway; the same glass
goes quiet when R̂ is set to the slope the ENGAGEMENT flies. ⇒ "know your slope" becomes "KNOW YOUR SLOPE CURVE
OVER THE BAND THE ENGAGEMENT VISITS". And slice 29 cashed 28's OWN named successor, `R̂(look)` — the SCHEDULED
compensator — where the answer turns out to hinge on something a scalar never had to face: a schedule must be
EVALUATED somewhere, and the only look angle a guidance computer owns is the one the radome already bent. ⇒ what
closes the loop is the residual at the COMPENSATOR'S OWN INDEX, and a schedule that is a BETTER model of the glass
can ring while a much worse one stays quiet. And slice 30 SHIPPED 29's own strongest deferral — THE ENVELOPE AND
THE ONE-SIDED CONSTRAINT — by making the ENGAGEMENT a slider (`cross_speed_mps`): because only a NEGATIVE residual
rings, a SCALAR aimed at the glass's worst-case slope is stable in EVERY engagement (6/7 → 0/7), so what a
schedule buys is ACCURACY, not stability — and the bound is paid for in navigation ratio, giving the scalar TWO
bounds that close on each other as the glass worsens. And slice 31 cashed the §1 approximation all four of
26/27/28/29/30 carried — a PERFECT gyro — and found that the sensor's two error terms land in two DIFFERENT
CURRENCIES (a scale factor on the RESIDUAL, i.e. a stability boundary; a bias on the AIM POINT, additive and with
no residual to move), which turns slice 30's "sufficient, never tight" margin into a GYRO BUDGET: −21% of scale
factor at the conservative aim point, ~3% at a sharpened one. And slice 32 cashed the deferral EVERY ONE of 26–31
named and each one sharpened — THE SEEKER'S FIELD OF VIEW — turning the look angle from a §1 MODEL-VALIDITY caveat
into a PHYSICAL STOP, and with it the arc's FIRST SENSOR-SIDE CAP. What a field of view caps is not a force or a
rate but the ENGAGEMENT: the window a seeker needs is the collision triangle's own LEAD ANGLE, so too small a
window costs not ACCURACY but the ENVELOPE — the set of targets you may engage at all. The track breaks WHILE THE
LEAD IS STILL BUILDING, the α-β tracker coasts on a rate that was right for a smaller lead, and the geometry runs
away — a 1505 m miss out of a missile with 0.0% of its approach saturated. And slice 33 SHIPPED THE COMPOSITION
32 kept off its own wire by convention 9 — THE RING IS AN FOV BUDGET ITEM — where the exemption is that the
composition IS the lesson: six slices of a missile that shakes itself all recorded, as a standing fact, that the
ringing arm STILL HITS, and that was only ever true because the seeker's window was INFINITE. The excursion a
parasitic loop adds to the look angle is spent out of exactly the budget 32 measured, so the FOV a seeker needs
is the engagement's lead PLUS the loop's excursion — and slice 30's design rule buys the whole second term back,
depth-independently. A limit cycle you were told to measure in rad/s is spent in DEGREES OF FIELD OF VIEW.
And slice 34 CLOSED the arc's sensor half with the successor 32 and 33 both nominated — THE GIMBAL — where the
whole family's founding assumption finally moves: for eight slices the radome has been indexed on the LOS off the
missile's own NOSE, which is why the loop closes through the body at all. Give the seeker a head and the ray goes
through the part of the dome the HEAD is aimed at — and the head is aimed by the very measurement the dome just
bent, so the index of the glass becomes a FIXED POINT of the glass and slice 26's loop is partly re-closed through
the head with a NEGATIVE sign. The same glass, the same believed slope and the same seed ring strapdown and stay
quiet gimballed, and the onset walks two rungs of the ladder. But the margin is bought by the head's pointing
DECOUPLING from the true LOS, and that decoupling is exactly the tracking error the head's own detector must
cover — so slice 33's single number splits into a STOP and a DETECTOR WINDOW, and slice 32's predicate returns in
the currency a gimbal actually has. And slice 35 took the deferral 34 named SECOND and, in doing so, found the one
place where this arc's habitual cure stops working. Slice 34's head was infinitely fast; give it a real servo and
its motion stops being free — it becomes a RESOURCE, and the demand on that resource is set by the parasitic loop
itself, stepping 57.7× across the very onset bracket slice 34 measured. Slices 32, 33 and 34 all end the same way,
*widen it and it costs you nothing but glass*; that cure does not transfer, because servo bandwidth is not a window
— it is what the loop FEEDS ON. Slow the head and the ring is genuinely attenuated while the tracking error it must
cover grows, so for the first time in the arc one knob carries two bounds pulling in opposite directions and there
is no free direction to run in. What you CAN still do is aim R̂ at the glass's worst-case slope, and slice 30's rule
pays for the third time: at the aim point the servo is free at every rate in the catalogue. And slice 36 shipped
the deferral this family had carried longest — 32 named it, 34 promoted it to a live constraint, 35 sharpened it and
gated it away — by making the HANDOVER itself an authored quantity. Every slice since 34 handed the head its target
perfectly, and the question that was gated away turns out to have an answer nobody predicted: the window a seeker
needs is not the handover error. The body-frame LOS is not a fixed target — it crosses through zero over the
approach — so a head handed over ON the line of sight must chase that entire journey while one handed over part-way
along it starts with a head start, and the requirement is a V whose kink the servo moves. The cheapest place to
hand a seeker its target is not at the target: it is part-way to where the target is GOING, and how far depends on
how fast a servo you bought. Zero is outside the basket that holds — and biasing onto the kink buys the one thing
slice 35 proved could not be bought on its own axis, because the left arm of the V is an initial condition and no
bandwidth touches an initial condition.
And slice 37 closed the sensor half's last structural question — not what the head can see or how fast it
can move, but WHICH FRAME ITS SERVO CLOSES IN. The deferral that named it promised the textbook headline,
that a stabilized head measures inertial LOS rate directly; that turned out to be already true and
unshippable, because this seeker has reported inertial angles since slice 25. What is body-referenced is
the servo — and stabilizing it makes the missile shake. For eleven slices the position servo's LAG had
been doing stability work nobody asked it for, quietly low-passing the missile's own body motion out of
the glass's index at exactly the frequency the limit cycle lives at. Take the lag away and the index sees
the body in full: the same design, the same glass, the same seed, one button press, and a quiet missile
rings 84× harder. The classical reason gimbals exist inverts here — and the onset is found twice, once
per servo frame, so it is a mechanism and not a cell. What you can still do is aim the belief at the
glass's worst-case slope, where slice 30's rule pays for the fourth time and the button simply stops
doing anything at all.**

⭐⭐⭐ **Slice 44 then went and built the thing three slices had been waiting for — and found there was
nothing for it to do.** Since slice 42 the whole family had been blocked on one sentence: a wider seeker
window is FREE in this model, so nobody would ever pay for a search when they could just widen the glass.
The named cure was to give the window a price by asking whether the seeker can actually SEE the target,
not merely point at it — because one aperture serves both, and a wider window is a smaller antenna. That
part is exactly true and it flew exactly: double the window, halve the range, to six decimal places. The
part that failed was the engagement. **This missile is launched 6.4 km from its target and its seeker can
see 8 km, so it begins the flight already able to see — the gate has nothing to gate**, and the whole
apparatus is inert on the shipped wire. Bending the wire until it bites takes a target four hundred times
smaller than the one authored. ⇒ **A limit can only price a design if the design is on the wrong side of
it to begin with**, and where the engagement starts is a property of the SCENARIO, not of the sensor. So
the precondition is renamed rather than removed: a search-pattern slice needs a missile launched BEYOND
its seeker's reach — a midcourse phase — and that is its own slice, because this one is unpowered and a
launch that far out simply falls out of the sky before it arrives.

⭐⭐ **Two things it measured on the way are worth more than the law it went looking for.** The first is
that a late lock is not free after all — it is just not paid in the currency anyone was watching. The
last arm that still hits flies at **exactly 100 % of the airframe's available turn**, having spent every
bit of it undoing what the delay cost, while the miss column sits flat at a quarter of a metre and shows
nothing. One step further and the demand FALLS, because by then the track is gone and there is nothing
left to command: two different limits end the free interval within 500 m of each other, and the headline
number reveals neither. The second is that the narrow-window failures this arc has been reading as a
WINDOW problem are a SERVO problem. A lock right at the rim hands the head a full-window slew to close,
and at the shipped 8 °/s it cannot close it before the line of sight runs away — triple the slew rate and
every one of those 400-metre misses becomes a hit, from the identical instant of lock. ⚠ And the first
write-up of this gate said the opposite of both, in sentences wider than their own measurements; what
caught them was the contamination columns the plan had registered before any number existed. **Five times
now in this arc the probe was right, the table was right, and the sentence on top of the table was
wrong.**

⭐⭐⭐ **Slice 45 asked a question the family had been carrying since slice 34 without ever testing it:
the seeker decides "can I see it?" by adding up the left-right error and the up-down error into one
distance and comparing that to one radius — a circle. Real hardware is often a rectangle: two
independent limits, one per axis. Does the SHAPE matter, or only the size?** The plan argued from the
hardware that the mechanical gimbal was the half worth changing (a real gimbal has an azimuth ring
and an elevation trunnion, genuinely independent) while the seeker's radio beam is genuinely round.
That argument was sound and it picked the wrong half. **The gimbal's elevation limit turned out not
to matter at all**: pin the head's elevation travel to a twentieth of a degree, so tight that the
limit is jammed against two thirds of the time, and the missile hits exactly as it did with seventy
times the freedom — the same miss, to every digit, across a 750-fold range. It is the seventh knob
this project has found that looks like a design choice and is not.

⚠⚠ **And the first write-up killed the other half too, wrongly — the correction is the more useful
half of the slice.** On every arm where the seeker is TRACKING, a square window and a round one give
bit-for-bit identical results, because a tracker holds the target near the middle of its window and
the corners — the only place the two shapes differ — are never visited. That looked conclusive. But
the plan's own first sub-claim had named an arm the write-up never flew: the one where the head is
SEARCHING. Flown, it reverses the verdict. A searching head deliberately sweeps one axis out to the
edge, which is exactly where the corners are, and there the square window turns a 305-metre miss into
a 0.23-metre hit, and lets the search succeed at a 9 % slower sweep. ⭐⭐ **So the shape of a window
is invisible to a tracker and visible to a searcher — which is a fact about what the seeker is DOING,
not about the geometry it is flying.** The honest caveat came with it: a circle just 0.7 % bigger
rescues the same arm, so the square's advantage is not that it works but that it works CHEAPLY —
spend the square's own budget on a circle and the missile never finds the target at all. ⚠ Nothing
ships, for a new reason: the only arm where the shape matters lives inside a feature that has not
been built, so this belongs INSIDE the search slice rather than before it. And it does not unlock
that slice either — it makes searching cheaper when what was needed was to make a wider window
costlier — which leaves the search with exactly one candidate unblocker left, the long-range shot
slice 44 named. ⭐ **The method lesson is about the gate's own failure: a gate is not finished while a
sub-claim its own plan wrote down first still has no row in any table.**

## Slice 46 — the seeker's detection horizon (2026-08-18)

Until now the seeker's question was purely "is the target inside the window I am pointing at?" — an
angle question, answered at any range. This slice gives it a receiver: the echo has to be strong
enough to hear, so a distant or a stealthy target is invisible even when it is dead centre in the
window. **And the two halves turn out to be one design variable, not two.** The window IS the beam
the antenna makes, a narrow beam needs a big dish, and a big dish reaches further — so reach times
window is a constant of the design (measured at 80789 metre-degrees, dead flat across a fourfold
range). Slices 32–36 taught that widening the window is free; with a receiver it is exactly not.
Making the target sixteen times bigger buys only twice the range, which is why the obvious lever is
the weak one.

**The number this slice exists for is not the miss.** This is the same physics slice 44 built and
killed two days earlier for reading flat: across the whole range of the new knob the miss barely
moved, so it looked like a component that did nothing. What was moving was how hard the airframe had
to pull. A missile that acquires late has less time to correct, and it pays for that in turn — not in
where it lands. Along this slice's ladder the peak demand runs 2.5 → 3.0 → 7.4 → 100 → 100 percent of
everything the airframe has, while the miss wanders up and then down with no order to it at all. The
cell in the deepest trouble is one that still HITS: it is flying at a hundred percent of its limit to
do so, and there is no other number on the screen that can say that. ⭐⭐ **A flat headline is not
evidence of a flat effect — it can be the wrong gauge pointed at a real one.**

⚠ **And slice 44's own authority figure needed correcting, which is a lesson in itself.** It reported
its "free" cell at 100 % of the limit; that reading was taken through the last fraction of a second
before impact, where every guidance number spikes because the geometry is degenerate. Excluded, the
same cell reads 10 %, against 3 % for the untouched arm — the effect is smaller, cleaner, and now
strictly ordered. The spike was the non-monotone thing, not the physics.

⚠⚠ **The client half cost two findings that only a photograph could produce.** Every line of the new
readout ran off the right edge of the screen — at two different window sizes — while the test meant
to prevent exactly that passed green. Two compounding reasons: the readout is anchored to the right
edge, so a wider window does not help; and the test counted CHARACTERS while the screen draws PIXELS,
and these lines are full of arrows and symbols that are one character and many pixels. The budget was
also one this slice invented for itself instead of inheriting the one an earlier slice had already
measured and paid for. **A budget a slice declares for itself is not a budget** — and the fix is to
measure the thing you actually care about (width on screen) rather than a proxy for it. Second, on
the rung where the receiver is switched off the core sends none of the new numbers, so the readout
was filling in zeros and printing "range 2846 m versus horizon 0 m" in the green it uses for a passed
check — a value that was never computed, displayed as a test that passed. Both lines now refuse to
report a comparison that was never made.
