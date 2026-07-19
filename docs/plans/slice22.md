# Slice 22 — NONLINEAR `C_L(α)` / TRUE STALL: the ceiling the airframe sets (§11 Tier-A)

**Status: PLANNED (gate 0 not yet run). Gates 0–3 pending.** The aero arc's nearest and most
load-bearing named deferral — carried explicitly by slices 19, 20 and 21, and the one that closes
the LEAK bounding two shipped knobs.

Slices 19–21 gave cap #4 (`a_max_aero`) three movers, and **all three moved `Q`**:

| slice | mover | mechanism |
|---|---|---|
| 19 | the ENGINEER | the `rho` knob — dialling a flight condition by hand |
| 20 | the MISSILE, by TURNING | induced drag bleeds V → Q falls |
| 21 | the MISSILE, by WHERE IT FLIES | `ρ(z) = ρ₀·exp(−z/H)` — climb → Q falls |

**Slice 22 moves the OTHER factor.** `a_max_aero = Q·S·C_Lα·α_max/m` has always assumed the lift
curve is a straight line out to `α_max` — that the airframe will keep trading α for lift forever.
It will not. Past `α_stall` the flow SEPARATES: **`C_L` peaks and then FALLS**, and the drag that
was negligible in attached flow RISES steeply. The ceiling is not `C_Lα·α_max`; it is the curve's
own INTERIOR PEAK, `C_L(α_stall)`, and no amount of Q buys past it.

> **THE LESSON, IN ONE SENTENCE.** Every prior cap in this project is a MAGNITUDE that saturates —
> pull harder, get no more. This one is a **DERIVATIVE THAT CHANGES SIGN**: past the peak, pulling
> HARDER turns you LESS *and* costs you MORE. That reversal is new in the suite, and it is why the
> user chose the true-drop curve over a saturating one (see "The curve-form decision" below).

---

## Read these FIRST — the four things settled while planning

### 1. `alpha_command` IS NOT TOUCHED — and that is the design, not a shortcut

The lesson lives ENTIRELY on the **achieved** side. The inner autopilot inverts
`a_perp → α_cmd = a_perp·m/(Q_eff·S·C_Lα)` on the **LINEAR** `C_Lα`, and it KEEPS DOING SO.

This is right on three counts, not one:
- **It is realistic.** An autopilot carries an internal linear model of its airframe. A linear
  inversion that OVER-commands α as the real curve goes concave is precisely slice-19's
  command-vs-achieved gap MADE PHYSICAL — the same lesson, one layer deeper.
- **It sidesteps the MULTIVALUED INVERSE.** Past the peak two α give one `C_L`. Inverting the real
  curve would author a genuine ambiguity/crash surface into a first stall slice. Leaving the
  inversion linear means the ambiguity is never constructed. (⚠ It is therefore INHERITED BY
  WHOEVER LATER WANTS A STALL-AWARE AUTOPILOT — name it as a deferral, do not pretend it is gone.)
- **It shrinks the blast radius to the two functions that carry the physics.**

⚠ **`_AIRFRAME_DENOM_FLOOR`, `_AIRFRAME_Q_FLOOR`, the `C_Lα<0` self-consistency (slice-19 FINDING 9)
and the `sat` round-trip all live in `alpha_command` and are UNCHANGED.** Do not "helpfully" make
`sat` stall-aware — `sat` means *the α_max clamp bound*, and under this slice α_max is deliberately
NOT the binding limit (see #3). A new, separately-named flag reports stall.

### 2. THE DRAG IS ADDITIVE, NOT A CORRECTION — slice 20's term is CORRECT past stall

The tempting-but-wrong framing (caught at the advisor pass, and it would have oversized the slice):
*"`C_Di = K·C_L²` goes invalid past stall, so slice 20's headline term must be fixed."*

**It does not, and it must not be.** Induced drag genuinely DOES fall with lift² — slice 20's term
falling past the peak is CORRECT PHYSICS. What is missing is **SEPARATION DRAG**, which was
legitimately ≈0 in attached flow (which is why slices 17–21 never needed it) and rises steeply past
stall. So:

    total aero drag = induced (slice 20, VERBATIM, correctly FALLING past the peak)
                    + separation (NEW, gated, RISING — dominates past the peak)

`induced_drag_accel` is **not edited except for its shared `C_L`** (see #4). Byte-identity is
preserved the way slices 20/21 preserved it: a presence-gated branch, the else-arm textually
verbatim, and **never** a coefficient→0 that is trusted to vanish (the `-0.0` trap).

**AND IT IS NOT A SECOND LESSON.** Lift-collapse + drag-rise **IS** what stall is — one rung, one
phenomenon, one event: *pull past the peak → less lift AND more drag → you depart.* Convention 9 is
satisfied because there is one toggled fidelity, not two. A stalled missile that decelerated LESS
would not be an approximation, it would be the OPPOSITE of the lesson — which is exactly why the
separation term is **MANDATORY, NOT OPTIONAL**.

**Shape of the separation term** — it **KEYS ON α, NEVER ON `C_L`** (past stall `C_L` FALLS while
the drag must RISE; keying it on `C_L` would make the drag fall too, reproducing the very error):

    C_Dsep = K_sep · (max(0, |α| − α_stall))²        (lumped one-coefficient — the K / cd_area precedent)
    a_sep  = −(Q·S·C_Dsep / m)·v̂                     (ALONG −v̂, like induced — slows, never turns)

**EVEN in α**, mirroring `induced_drag_accel`'s even-in-α tooth. So the parity table — which ships
as a consistency tooth — is: **`C_L` ODD, both drag terms EVEN.** Up and down stall identically.

### 3. ⚠ THE LARGEST CONSEQUENCE OF THE TRUE-DROP CHOICE: `α_max > α_stall`, WHICH INVERTS SLICE 19

**This blocks the scenario, and it must not be written around.**

To reach post-stall the ACHIEVED α must exceed `α_stall`. There are exactly two routes:

- **Via the LEAK (`α_max ≤ α_stall`)** — the command never reaches stall, so departure could only
  happen through slice-19 FINDING 14's achieved-α overshoot above the clamp. **REJECTED.** It is
  gain-dependent, fragile, and **CIRCULAR**: closing that leak is a stated payoff of this very
  slice. A headline built on the leak evaporates the moment the leak closes.
- **Via the COMMAND (`α_max > α_stall`)** — ⭐ **THE DESIGN.** The autopilot COMMANDS INTO STALL.
  `α_max` becomes a soft high limit and **THE PHYSICS SETS THE WALL.**

**This INVERTS slice 19's relationship and the plan says so out loud.** In slice 19 `α_max` was the
BINDING clamp and `a_max_aero` was that clamp expressed as an accel. Here `α_max` is deliberately
NOT binding; the ceiling is the CURVE'S INTERIOR PEAK. Concretely:

    slice 19–21:  a_max_aero = Q·S·|C_Lα|·α_max / m           (linear extrapolation to the clamp)
    slice 22:     a_max_aero = Q·S·C_L_peak     / m,   C_L_peak = max_{|α| ≤ α_max} |C_L(α)|

⚠ **`aero_accel_limit` now computes an INTERIOR MAX, not a value at the clamp.** For the shipped
curve `C_L_peak = |C_L(α_stall)|` in closed form (do NOT ship a numeric search — a closed-form peak
is the anchor the tests pin). Presence-gate it: key absent ⇒ the slice-19/20/21 formula VERBATIM, so
those three slices stay byte-identical and this is a NEW RUNG'S number, not a regression in theirs.

⭐ **The headline tooth this makes possible, which slices 19–21 STRUCTURALLY COULD NOT WRITE:**
**hold `Q` EXACTLY constant across the rung flip and show the ceiling still drops.** Same ρ, same V,
same S, same mass, same α_max — only the curve changed. That is what proves slice 22 moved the
OTHER factor and is not "slice 21 again with a different letter."

### 4. THE BYTE-IDENTITY TRAP IS A MULTIPLY GROUPING — do NOT refactor the off-arm

`lift_accel` today computes `L = Q * p.S * p.Cla * α`, i.e. `((Q·S)·Cla)·α`. Routing the off-state
through a shared helper as `L = Q * p.S * _cl(α)` gives `(Q·S)·(Cla·α)` — **a different multiply
grouping, a possible 1-ULP shift**, and the absolute golden + determinism tests are bit-exact. This
project has already caught this class TWICE (`√(snr/2)` vs `√snr·√½`).

**Each off-arm stays TEXTUALLY VERBATIM; the stall path branches AROUND it.** Same for
`induced_drag_accel`'s `C_L = p.Cla * α`.

---

## The curve-form decision (settled by the user, recorded with its cost)

Two forms were costed. **SATURATING** (C_L → an asymptote, never drops) was the advisor's and my
recommendation: one lesson, monotone inverse, no separation term needed, smallest blast radius.
**TRUE-DROP** (C_L peaks, then falls) was **the user's decision**, and it is the better lesson —
the sign reversal above is genuinely new in the suite, and it ships departure directly instead of
deferring it.

**Its true size, made visible here so gate 2 is not a surprise:** true-drop honestly done =
**stall curve + separation drag + the inverted clamp relationship (#3)**. Every one of those three
is FORCED by the choice, none is optional, and all three are additive and gated.

**The rung justification is UNCHANGED by the form choice** — apply slice 21's discriminator
(recorded in `atmosphere.jl`'s header, do not re-derive): *is the off-state (a) a distinct code path
and (b) NOT knob-reachable?* The linear curve is **`α_stall → ∞`** — a LIMIT POINT, not a slider
position. ⇒ **RUNG**, `fidelity.aero_curve = linear | stall`.

⚠ **VERIFY THIS AT GATE 0, DO NOT ASSUME IT.** If a FINITE `α_stall` parked above the operating
range is linear-in-effect, the off-state IS knob-reachable and this is a **KNOB** (the
`af_k_induced` shape), not a rung — and the rung justification evaporates. The `H ≈ 1.4e6` probe in
slice 21 is the template: show what finite `α_stall` would be needed for <1% deviation over the
achieved-α range, and show the scenario cannot reach it.

---

## Gate 0 — probes to run BEFORE writing any library code

The empirical-first discipline (convention 10). Each probe is throwaway; the NUMBERS come back and
the design may change (slices 19, 20 and 21 were all changed by their gate 0).

- **P1 — the rung/knob discriminator (#4 above).** What finite `α_stall` makes the stall curve
  indistinguishable from linear over the achieved α range? Confirm it is out of any sane slider
  domain. **If this fails, the slice is a KNOB and the plan is rewritten.**
- **P2 — does the missile actually reach post-stall α, via COMMAND?** With `α_max > α_stall`, sweep
  the engagement and measure the achieved-α histogram. Post-stall excursion must be reached by the
  COMMAND path with `k_α`/`k_q` at their SHIPPED authored values — **and must NOT depend on the
  FINDING-14 leak** (verify by checking it survives a gain reduction).
- **P3 — is the departure RECOVERABLE or TERMINAL?** Both are shippable lessons but they are
  DIFFERENT lessons and the headline must match the one that happens. (A stable `Cmα` plus the
  rate-damped inner loop may weathervane back out; the separation drag's V-bleed may not let it.)
- **P4 — `K_sep` domain, MEASURED like slice 20's K.** Find the range that is monotone and clean,
  then ship with a ≥2× margin (slice 20's discipline: at K≥0.8 `defl_sat` went 0→1289).
- **P5 — the CONVENTION-9 SEPARATION.** Hold `cd_area = 0` and keep `K` modest; confirm slice 20's
  induced spiral does NOT compete with the stall headline. They live at different α regimes but the
  scenario must be shown to keep them apart, not assumed to.
- **P6 — does `defl_sat` stay 0?** Slice 19's FINDING 2 (the δ_max cap silently contaminating a
  causation twin) recurs here: commanding α_max ABOVE α_stall means commanding LARGER α than any
  prior slice, and `δ_peak ≈ (|Cmα|/Cmδ + k_α)·α_max` scales with it. **A δ_max that binds would
  make this "slice 15's deflection cap in a stall costume."** Assert `defl_sat == 0`.
- **P7 — the CAUSATION COUNTERFACTUAL** (slice 19's "BINDING ≠ CAUSING" discipline). Relaxing
  `α_stall` ALONE must recover most of the miss. Identify what is NOT isolated: `α_stall` enters
  BOTH `C_L(α)` AND `C_Dsep` — so unlike slice 19's clean α_max it is **confounded by construction**
  and may need the two effects separated by a second probe (a stall curve with `K_sep = 0`).

---

## Gates 1–3 (sketch — to be firmed by gate 0's findings)

**Gate 1 — the pure lib.** New `aero_curve.jl` (included BEFORE `radar.jl` so `LIVE_FIDELITY_MODES`
can reference `AERO_CURVE_MODES` — convention 1). Contents: `lift_coefficient(α, p)` (ODD, peaks at
α_stall, falls after), `separation_drag_coefficient(α, p)` (EVEN, zero below α_stall), the
closed-form `cl_peak(p)`, and `const AERO_CURVE_MODES = (:linear, :stall)` (defined ONCE —
convention 7). Tests: the parity table (C_L odd, both drags even), the closed-form peak, the
linear-limit agreement as `α_stall → ∞`, the `C_L` consistency tooth (lift and its induced bill use
the SAME `C_L` — else the turn and the invoice disagree), and the sign chain (this arc's #1 trap,
now on its FOURTH occurrence: 16 moment sign, 17 lift direction, 19 the a→α→δ→M→α→lift→γ̇ chain).

**Gate 2 — the wiring.** `lift_accel` and `induced_drag_accel` get presence-gated stall branches
sharing ONE `C_L(α)`; the new `a_sep` term joins inside `_integrate_coupled!`'s closure (reading the
STAGE state — slice 17's stage-θ and slice 21's stage-z fixes are the precedent, and this term is
α-dependent so it has the same hazard); `aero_accel_limit` returns the interior peak under the rung;
`LIVE_FIDELITY_MODES` gains `aero_curve`. Class **4c** (physics-changing, NO RNG — truth-fed PN, no
seeker ⇒ "draw-count invariance" is VACUOUS; the 8th consecutive 4c; live-settable, NO
`set_fidelity` guard). ⚠ Check `:aero_curve` INERTNESS without `:pitch_coupled` — slice 21's `_atm_on`
third-conjunct bug is the direct precedent and it was a LATENT BUG FIX found at gate 3.

**Gate 3 — the four proofs** (convention 14): `slice22_verify.gd`, `slice22_ui_test.gd`, the
`Sandbox.tscn` headless smoke-load, and a windowed shot aimed at the CLAIMED branch. The client
should REUSE slice 19's airframe view + aero strip (slices 20/21 both did); the button is the
`:aero_curve` cycler — ⚠ **`_setup_spatial_fid_btn` now has FOUR view-claiming keys to order**
(`:atmosphere` was checked first for slice 21); this is the one-button rule's **4th occurrence**.
⚠ Slice-21 gate-3's three PROOF bugs are live watch-items: `%.2e` is not a GDScript specifier (an
unknown one makes the WHOLE `%` fail SILENTLY), frame-sampling error is ASYMMETRIC (a miss samples
faithfully, a HIT samples coarsely), and magic-multiple teeth must be pinned against a MEASURED
value. See [[ewsim-missile-verifier-sampling]] for the LOS range-gate rule.

---

## Named deferrals (write them down; do not let them leak into this slice)

- **A STALL-AWARE AUTOPILOT** — inverting the real curve, with the multivalued past-peak inverse
  that implies (#1). This slice deliberately leaves the inversion linear.
- **Mach / compressibility** — the aero lib is deliberately Mach-free (`atmosphere.jl` §1), so
  `α_stall` and `C_Lα` do not vary with Mach here. A real interceptor's do.
- **Hysteresis** — real separation re-attaches at a LOWER α than it separates at. The shipped curve
  is single-valued in α, with no memory.
- **Roll/yaw departure** — the pitch-plane reduction still holds; a real departure goes
  out-of-plane. That dies only with bank-to-turn / 3-D.
- **ρ(z) on the ballistic path** (slice 21's deferral, unchanged) and the RF layered
  atmosphere / ducting entry — **do not conflate either with this slice**.
