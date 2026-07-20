# aero_curve.jl — NONLINEAR AERO COEFFICIENTS: true stall, separation drag, and the Cm(α)
# break (slice 22, §11 Tier-A). The pure-lib half; the wiring lives in airframe.jl/missile.jl.
#
# WHAT THIS CLOSES. Slices 17–21 all ran a LINEAR aero: `C_L = C_Lα·α`, unbounded, with lift
# growing forever as you pull. That is the arc's nearest named deferral (carried explicitly by
# 19, 20 AND 21), and it is what bounds two SHIPPED knobs — slice 19's FINDING 14 leak (α_max
# clamps the COMMAND while lift uses the ACHIEVED α) is only survivable because nothing punishes
# an over-α excursion. Here the airframe finally sets its own ceiling.
#
# ⭐ THE HEADLINE IS AN ALGEBRAIC IDENTITY (gate-0 F8) — slice 21's ρ-factor in a NEW LETTER:
#
#     a_max_aero(linear) = Q·S·|C_Lα|·α_max / m
#     a_max_aero(stall)  = Q·S· C_L_peak   / m,   C_L_peak = C_Lα·α_stall
#     ⇒ ratio ≡ α_stall / α_max            — Q, S, C_Lα and m ALL CANCEL
#
# Measured Δ ≤ 1.1e-16 across four (α_stall, α_max) pairs. It is a SAME-INPUTS FORMULA
# comparison (never run-vs-run — convention 10/11), which is exactly why it is exact.
#
# ★ KNOB, NOT RUNG — MEASURED, AND THE PLAN'S CLAIM LOST (gate-0 F7, USER DECISION 2026-07-19).
# The plan asserted "linear is α_stall → ∞, a LIMIT POINT ⇒ RUNG" and told gate 0 to verify it.
# It does not survive. Apply slice 21's discriminator (atmosphere.jl's header — do NOT re-derive):
# *is the off-state (a) a distinct code path and (b) NOT knob-reachable?* Here (b) FAILS: the
# achieved α SELF-LIMITS to ~0.24 across the whole VIABLE geometry family (the linear arm's α_pk
# capped at 0.2408 even at a_lat = 400 — past that is the REACH WALL, not higher α), so an
# α_stall parked anywhere ≥ ~0.25 is linear-in-effect OVER ALL REACHABLE STATES — not by
# coincidence of one scenario. At α_stall = 0.25 the miss IS the linear miss to the printed digit.
#
#   **α_stall MOVES A CORNER, and a corner can be parked out of reach** — exactly slice 16's
#   `af_cma` (park it stable, nothing happens), and the OPPOSITE of slice 21's `H`, which cannot
#   be parked because ALTITUDE IS THE SWEPT VARIABLE. The same escape exists for α_break
#   (≥ 0.32 ⇒ the departure never happens), so the "rung door stays open for the Cm break"
#   clarification was ALSO measured shut. Slice 22 is a KNOB slice, permanently.
#
# ⚠ Constraining the α_stall slider's top below α_max to manufacture a rung would be GAMING the
# discriminator, not applying it. And record the meta-point: **the discriminator is a CONVENTION,
# not a law** — a rung could be shipped anyway for the crisp A/B, but it would have to be named a
# DELIBERATE DEVIATION; it cannot be claimed to SUPPORT one here, because it says the opposite.
#
# THE FIVE FORCED PIECES (gate 0 grew this from three; none is optional, all are additive):
#   1. C_L(α)      — ODD, peaks at α_stall, FALLS after. The ceiling. (the headline)
#   2. C_Dsep(α)   — EVEN, exactly 0 below α_stall. Separation drag: the post-stall bill.
#   3. Cm(α)       — ODD, loses its restoring slope past α_break. Relaxed static stability.
#   4. α_break ≠ α_stall — **TWO ANGLES, MEASURED (F3; the plan's "one angle" is REFUTED)**:
#      with α_break == α_stall the CONTROLLED lift-collapse window has literally ZERO width (the
#      airframe departs at the same α where lift peaks, so "pull harder, get less lift" is never
#      visible — and that regime is what the true-drop curve was chosen FOR). Optimum α_break =
#      0.28 vs α_stall = 0.20 → collapse 0.877 s, THEN departure 0.717 s. Bounded on BOTH sides:
#      below ~0.22 the collapse vanishes, at ≥0.32 the break is never reached.
#   5. α_sat      — the DEEP-STALL BOUND, Cm's THIRD slope (F9). ⚠ REQUIRED FOR PHYSICALITY, not
#      polish: without it a linear-in-α divergent moment grows unbounded and α runs to 383497 rad
#      (F6) — a convention-6 crash path (a wire NaN drops the connection), and it makes a real
#      tumble INDISTINGUISHABLE from a bug. With it the divergence saturates into a second
#      high-α equilibrium — deep-stall lock-in, a REAL phenomenon. It barely moves the miss
#      (1594.70 identical at α_sat ∞/1.20/0.90): a PHYSICALITY fix, NOT a lesson lever.
#
# ⚠ TWO LESSONS, TWO METRICS — AND THE SECOND ONE'S METRIC IS NOT THE MISS (F4, F10, F11):
#   • the CEILING (knob `af_alpha_stall`): headline = the α_stall/α_max identity; the miss
#     corroborates (125.14 → 240.37, 1.92×, aero_sat 26.3%, defl_sat == 0).
#   • RELAXED STATIC STABILITY (knob `af_cma_post`): headline = the AUTHORITY THRESHOLD. A
#     statically unstable airframe is PERFECTLY FLYABLE until the autopilot runs out of authority
#     — a SHARP cliff between Cma_post 4 (holds, α_pk 0.310) and 8 (LOSES, α_pk 2.778 ≈ 159°, a
#     bounded deep-stall tumble) — plus slice 16's ω_sp NaN sentinel firing IN FLIGHT for the
#     first time in project history (0.747 s). ⚠ **THE MISS IS NOT THE METRIC HERE AND THAT IS
#     FINAL**: even at full tumble it moves 240.37 → 243.67 = +1.4%. A missile that departs 0.7 s
#     before CPA keeps its momentum and lands in much the same place. A miss-based lesson line
#     would actually be measuring the LIFT collapse and MIS-ATTRIBUTING it to the break.
#
# THE #1 SIGN TRAP, 4th OCCURRENCE — and note WHERE. 16 = the moment sign, 17 = the lift
# direction, 19 = the a→α→δ→M→α→lift→γ̇ chain, and piece 3 puts this slice back inside
# `pitch_moment` — THE EXACT FUNCTION SLICE 16's TRAP WAS FOUND IN. The break is therefore pinned
# by SIGN (∂Cm/∂α < 0 below α_break, > 0 above), never by magnitude.
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden ones):
#   • PIECEWISE-LINEAR curves, not a smooth polar. Real C_L(α) rounds over its peak; this one
#     has a corner. Chosen for the CLOSED-FORM peak (`cl_peak` — the exact-identity headline
#     depends on it) and because a corner is what makes the knob a knob. The corner is also why
#     the deep-stall C_L stays LINEAR in its post-stall slope rather than rolling off toward the
#     flat-plate limit — at the tumble α (2.78 rad) that under-states C_L badly, but the tumble's
#     headline is ATTITUDE and ω_sp, never lift, and re-shaping it would invalidate every gate-0
#     number. A flat-plate C_L(α) is DEFERRED and named.
#   • NO HYSTERESIS — real separation re-attaches at a LOWER α than it separates at. These curves
#     are SINGLE-VALUED in α, with no memory.
#   • MACH-FREE — inherited deliberately from atmosphere.jl §1. α_stall and C_Lα do not vary with
#     Mach here; a real interceptor's do.
#   • PITCH-PLANE — a real departure goes OUT-OF-PLANE; this one departs strictly in-plane. **This
#     is the sharpest remaining approximation in the slice** (piece 3 makes departure real, and
#     the pitch-plane reduction is what keeps it flat). Dies only with bank-to-turn / 3-D.
#   • The AUTOPILOT'S INVERSION STAYS LINEAR — `alpha_command` still inverts C_L = C_Lα·α. A
#     stall-aware autopilot would have to invert the real curve, with the MULTIVALUED past-peak
#     inverse that implies. DEFERRED and named; this slice deliberately leaves it linear.
#
# NOTE THERE IS NO `AERO_CURVE_MODES` HERE, AND THAT IS DELIBERATE (F7 above) — no fidelity rung,
# no LIVE_FIDELITY_MODES entry, no set_fidelity path, no client button. The convention-7
# one-list-no-drift rule has nothing to bind because there is no mode tuple. The knobs' own
# in-domain top IS the linear twin; key ABSENCE is the bit-exact slices-1–21 path.

"""
    AeroCurveParams

The immutable authored NONLINEAR-aero shape constants — the `AirframeParams` precedent (which
holds the LINEAR coefficients and the reference geometry; these two are read side by side and
are deliberately NOT merged, so a slice-1–21 `AirframeParams` construction is untouched).

Validated at LOAD (convention 5 — a live tick reads every one of these):

  * `alpha_stall > 0` — the lift-curve corner (rad). `C_L` peaks here.
  * `k_drop ≥ 0`      — the post-stall lift slope as a FRACTION of `C_Lα` (dimensionless). `0`
                        ⇒ lift FLATLINES past the stall (no drop); `1` ⇒ it falls as fast as it
                        rose. Never negative — that would make lift RESUME growing past stall.
  * `K_sep ≥ 0`       — the separation-drag factor (1/rad²). `0` ⇒ no post-stall drag bill.
  * `alpha_break > 0` — where `∂Cm/∂α` flips sign (rad). ⚠ **Authored SEPARATELY from
                        `alpha_stall` and normally ABOVE it — F3: equal angles give the
                        controlled-collapse regime ZERO width.**
  * `Cma_post`        — the post-break static-stability slope (1/rad). `> 0` DIVERGES (the
                        lesson); the AUTHORITY CLIFF sits between 4 and 8.
  * `alpha_sat > alpha_break` — the deep-stall bound (rad), where `Cm` becomes RESTORING again.
                        ⚠ REQUIRED (F9): without it the divergence is unbounded (α → 3.8e5).

⚠ THE OFF-STATE IS IN-DOMAIN PARKING, NOT A LIMIT (F7): park `alpha_stall ≥ α_max` and the
curves ARE the linear ones over every reachable α. That is what makes these KNOBS.
"""
struct AeroCurveParams
    alpha_stall::Float64
    k_drop::Float64
    K_sep::Float64
    alpha_break::Float64
    Cma_post::Float64
    alpha_sat::Float64
end

"""
    lift_coefficient(alpha, Cla, c::AeroCurveParams) -> C_L

The nonlinear lift curve — **ODD in α**, slope `Cla` below `α_stall`, slope `−k_drop·Cla` above:

    |α| < α_stall :  C_L = Cla·α
    |α| ≥ α_stall :  C_L = sign(α)·( Cla·α_stall − k_drop·Cla·(|α| − α_stall) )

CONTINUOUS at the corner by construction (both arms give `Cla·α_stall` at `|α| = α_stall`), so
the peak is exactly [`cl_peak`](@ref) — the closed form the headline identity rests on.

⚠ **THIS IS THE PROJECT'S SINGLE SOURCE OF `C_L`.** Both `lift_accel` (the turn) and
`induced_drag_accel` (slice 20's `K·C_L²` bill) MUST route through it. If they diverge the
missile turns on one lift and is invoiced for another, and nothing else in the test set catches
it — hence the explicit consistency tooth in `test_aero_curve.jl`.

ODD (not even) because lift must REVERSE with the sign of α: a nose-down α pulls the flight path
down. Getting this even would silently make every negative-α maneuver lift the wrong way — the
#1 sign trap's 4th occurrence.
"""
function lift_coefficient(alpha::Float64, Cla::Float64, c::AeroCurveParams)
    a = abs(alpha)
    mag = a < c.alpha_stall ? Cla * a :
          Cla * c.alpha_stall - c.k_drop * Cla * (a - c.alpha_stall)
    return alpha < 0.0 ? -mag : mag
end

"""
    cl_peak(Cla, c::AeroCurveParams) -> C_L_peak

The CLOSED-FORM maximum of [`lift_coefficient`](@ref): `C_L_peak = Cla·α_stall`, attained exactly
at `|α| = α_stall`.

This is the whole slice in one expression. Substituting it into the ceiling gives the ⭐ headline
identity — `a_max_aero(stall)/a_max_aero(linear) ≡ α_stall/α_max`, with `Q`, `S`, `Cla` and `m`
all cancelling (gate-0 F8, Δ ≤ 1.1e-16). Because it is closed-form, the identity is EXACT rather
than measured, which is what lets it be pinned as a same-inputs formula comparison.
"""
cl_peak(Cla::Float64, c::AeroCurveParams) = Cla * c.alpha_stall

"""
    separation_drag_coefficient(alpha, c::AeroCurveParams) -> C_Dsep

The post-stall separation drag — **EVEN in α**, and EXACTLY zero below the stall:

    C_Dsep = K_sep · max(0, |α| − α_stall)²

EVEN (not odd) because drag opposes motion regardless of which way you pulled: a −0.3 rad
excursion separates the flow exactly as a +0.3 rad one does. The `max(0, ·)` makes the
below-stall arm exactly `0.0` — not "small", which matters for the byte-identity story (a parked
`α_stall` must leave slices 17–21's drag bill untouched to the bit).

This is a NEW ADDITIVE term, which is itself part of why slice 22 is a knob slice: slice 20's
`af_k_induced` set the precedent that a new additive term is a knob, not a rung.

DISTINCT from slice 20's INDUCED drag (`K·C_L²`, the price of the turn you got) — this is the
price of the turn you did NOT get. Past the stall they move OPPOSITE ways: induced drag FALLS as
`C_L` collapses while separation drag CLIMBS. Both act on `−v̂`.
"""
function separation_drag_coefficient(alpha::Float64, c::AeroCurveParams)
    excess = abs(alpha) - c.alpha_stall
    return excess <= 0.0 ? 0.0 : c.K_sep * excess * excess
end

"""
    moment_coefficient(alpha, Cma, c::AeroCurveParams) -> Cm_alpha_contribution

The **THREE-SLOPE** static-stability moment contribution — the `Cmα·α` term of
[`pitch_moment`](@ref) generalized, **ODD in α**, and CONTINUOUS at both corners:

    |α| < α_break            :  Cma·α                                   (RESTORING, Cma < 0)
    α_break ≤ |α| < α_sat    :  Cma·α_break + Cma_post·(|α| − α_break)   (DIVERGING, Cma_post > 0)
    |α| ≥ α_sat              :  … + Cma·(|α| − α_sat)                    (RESTORING again)

carrying the sign of `α` throughout.

⚠ **THREE slopes, not two — the third is REQUIRED (gate-0 F9), not polish.** A two-slope Cm gives
a linear-in-α divergent moment, hence UNBOUNDED exponential growth: α ran to **383497 rad** in
the probe. That is a convention-6 crash path (the wire cannot carry it) AND an epistemic one — it
makes a genuine tumble indistinguishable from a bug. The third slope bounds the divergence into a
SECOND HIGH-α EQUILIBRIUM, which is deep-stall lock-in: a real phenomenon, physically the
post-stall body acting as a flat plate. **With the bound, a divergence that saturates is a real
tumble; without it, every divergence is noise.**

⚠ **PINNED BY SIGN, NEVER MAGNITUDE.** This function is the 4th occurrence of the arc's #1 sign
trap and it is inside the very function slice 16's trap was found in. The teeth assert
`∂Cm/∂α < 0` below `α_break` and `> 0` above it; getting the break backwards would make an
unstable airframe self-right and delete the entire second lesson while still "passing" any
magnitude-based check.

Returns the `Cmα`-term CONTRIBUTION only — the `Cmδ·δ` control and `Cmq·q̄` damping terms are
unchanged and stay in `pitch_moment`. At `α_break ≥` any reachable α this returns EXACTLY `Cma·α`,
i.e. the slices-16–21 linear term to the bit (the parking off-state, F7).
"""
function moment_coefficient(alpha::Float64, Cma::Float64, c::AeroCurveParams)
    a = abs(alpha)
    mag = if a < c.alpha_break
        Cma * a
    elseif a < c.alpha_sat
        Cma * c.alpha_break + c.Cma_post * (a - c.alpha_break)
    else
        Cma * c.alpha_break + c.Cma_post * (c.alpha_sat - c.alpha_break) + Cma * (a - c.alpha_sat)
    end
    return alpha < 0.0 ? -mag : mag
end
