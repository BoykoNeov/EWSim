# atmosphere.jl — the EXPONENTIAL ATMOSPHERE `ρ(z) = ρ₀·exp(−z/H)` (HANDOFF §11 Tier A,
# slice 21 gate 1). Pure, RNG-free, no LinearAlgebra — the §9 house style. One function and
# one mode tuple; this is the smallest pure lib in the project, and deliberately so.
#
# THE APPROXIMATION THIS CASHES. Slices 19 and 20 shipped `ρ` as an AUTHORED PER-MISSILE
# CONSTANT and were under standing orders to say *"low dynamic pressure (thin air / slow)"* and
# NEVER unqualified *"high altitude"* — because ρ was a number an engineer typed, not a
# consequence of where the missile flew. Only V could move `Q = ½ρV²`. Here ρ finally becomes a
# function of z, and the phrase is EARNED:
#
#     pull up → climb → ρ(z) falls → Q falls → a_max_aero = Q·S·C_Lα·α_max/m falls
#
# ⚠ THE CAVEAT LIFTS ONLY WHERE THIS LIVES. A slice-19/20 wire carries no `af_scale_height` and
# runs `:atmosphere === :constant`: its ρ is still a constant an engineer chose, and the OLD
# language still governs there. Do NOT do a global find/replace.
#
# WHY A RUNG AND NOT JUST A KNOB (settled at the gate-0 advisor pass — the general result is
# worth more than the slice, so it is recorded here rather than in the plan alone). The suite's
# ACTUAL discriminator is **is the off-state (a) a distinct code path and (b) not knob-reachable?**
#   • KNOB (`af_cma` slice 16, `af_k_induced` slice 20): the off-state is an IN-DOMAIN SLIDER
#     VALUE (`K = 0` is the slider's own minimum, exact) — continuous, no separate path.
#   • RUNG (`:airframe`, `:propagation`, and now `:atmosphere`): the off-state is a DISTINCT CODE
#     PATH and NO knob value reaches it.
# Constant ρ is `H = ∞` — a LIMIT POINT, not a slider position (within 1% at z = 14 km needs
# H ≈ 1.4e6 m). So slice 20's "a `:free` rung IS `K = 0`" reasoning DOES NOT TRANSFER, and the
# tempting counter-argument (":constant names no physics ρ(z) lacks — only the ABSENCE of a
# gradient") is word-for-word what `:airframe = point_mass` and `:propagation = free_space`
# already are: applied consistently it would delete two shipped rungs, so it cannot be the test.
# The rung also IS the lesson — the punchline is the live side-by-side (the old model HITS, the
# real atmosphere MISSES), and no knob value can reach the old model.
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden ones):
#   • ISOTHERMAL / single-scale-height exponential — NOT a layered standard atmosphere (no
#     troposphere lapse + stratosphere break). The lumped `H` is to a real ρ(z) profile what
#     `cd_area`'s lumped `Cd·A` is to a real drag polar: one honest parameter, named as such.
#   • NO temperature / speed-of-sound / Mach effects — the aero lib is deliberately Mach-free, so
#     `C_Lα` does NOT vary with altitude here. (A real interceptor's does. Named deferral.)
#   • FLAT-EARTH z (the `gravity_accel` lineage) — `z` is the inertial-frame height, not a geodetic
#     altitude, and there is no round-earth correction.
#   • THE AERO ATMOSPHERE ONLY. This is NOT §11's RF "layered atmosphere / ducting / tropospheric
#     scatter" entry, which lives behind the `propagation` knob and is a SEPARATE slice. Do not
#     conflate them: nothing here touches the radar path.
#   • ρ(z) reaches the COUPLED airframe path ONLY (`_integrate_coupled!`, missile.jl). The
#     point-mass/ballistic drag path keeps a constant ρ, because `dynamics.jl`'s steppers take a
#     `v -> a(v)` closure with NO position in it; changing that contract to `(p, v) -> a` touches
#     slice 8's `rk4_step`/`euler_step` — the byte-identity surface of every ballistic slice — for
#     a path that carries no altitude lesson. NAMED DEFERRAL: it deserves its own slice.
#     ⇒ THE CONSEQUENCE, ENFORCED IN CODE, NOT MERELY DOCUMENTED: `:atmosphere` IS INERT WITHOUT
#     `:airframe === :pitch_coupled` — missile.jl's `_atm_on` carries that conjunct, so under
#     `:point_mass` EVERY ρ-reading site (readouts included) reverts to ρ₀ TOGETHER. Without it
#     the readouts and slice-16's rotational `_integrate_airframe!` would report ρ(z) while pos/vel
#     flew ρ₀ — half the missile in one atmosphere and half in another. Inert-without-its-host is
#     the slice-14 (`:salvo` needs a `:datalink`) / slice-13 (`discrimination` needs `:scan`) shape.

# The scale-height floor. `af_scale_height` is a LIVE SLIDER, so it is floored AT THE CONSUMER as
# well as validated at LOAD (convention 5's two guard sites). This is a genuine crash path, not
# ceremony: at `H → 0` AND `z = 0` the exponent is `0/0 → NaN`, and a NaN ρ propagates to NaN
# `pos` — an invalid state frame — while a throw inside `integrate!` lands in the session's
# IO/EOF-only catch and SILENTLY DROPS THE CONNECTION. Floored, a rogue `H → 0` simply gives
# ρ = 0 above the ground (`exp(-z/1) → 0`, an underflow, not a NaN): an airless world, which is
# honest and cannot crash.
const _ATM_H_FLOOR = 1.0

"""
    air_density(z; rho0 = 1.225, H = 8500.0) -> ρ

The isothermal exponential atmosphere — air density (kg/m³) at height `z` (m):

    ρ(z) = ρ₀·exp(−z / H)

`rho0` is the SEA-LEVEL reference density (the missile's authored `rho`, which under
`:atmosphere === :exponential` is reinterpreted from "the density" to "the density AT z = 0" —
at `z = 0` the two readings coincide EXACTLY, which is what makes the rung's `:constant` arm and
this arm agree at the ground). `H` is the SCALE HEIGHT: the rise over which the air thins by a
factor of `e`. **Earth's is ≈ 8500 m**, and the slice-21 showcase ships that REAL value rather
than a tuned one.

`H` is the whole physical content of this function: it is not the density (that is `rho0`) but the
RATE AT WHICH THE DENSITY THINS — the one degree of freedom no constant ρ has. A constant profile
is `H → ∞`, a LIMIT this function approaches but never reaches for finite `H` (hence the rung —
see the header).

Degenerates (a live knob can never crash a tick — convention 5):
  • `z < 0` is FLOORED to 0 ⇒ ρ ≤ ρ₀. Below the reference height the model simply stops
    thickening. This is NOT cosmetic: an RK4 stage legitimately probes `z < 0` near the ground
    (and a wild transient stage can probe it anywhere), and `exp(−z/H)` at a catastrophically
    negative `z` mints `Inf` → NaN `pos` → an invalid frame (convention 6, the no-Inf/NaN rule).
  • `H` is floored at `_ATM_H_FLOOR` — see that constant: `H = 0` with `z = 0` is `0/0 = NaN`.
  • A huge `z` underflows `exp` to EXACTLY 0 (an airless vacuum) — finite, no guard needed.
"""
air_density(z::Real; rho0::Real = 1.225, H::Real = 8500.0) =
    rho0 * exp(-max(Float64(z), 0.0) / max(Float64(H), _ATM_H_FLOOR))

# The `:atmosphere` fidelity rungs (slice 21) — `:constant` (slices 8–20: ρ is an authored
# per-missile number; ONLY V moves Q) vs `:exponential` (ρ = ρ₀·exp(−z/H); the missile's own
# ALTITUDE moves Q, and the maneuver ceiling with it). Defined HERE, in the pure lib, and
# referenced ONCE by `LIVE_FIDELITY_MODES` and the server's `set_fidelity` — never re-listed
# (convention 7's one-list-no-drift, the drift-catch).
#
# Class 4c: physics-changing, NO RNG (this arc is truth-fed PN with no seeker, so "draw-count
# invariance" is VACUOUS here — do NOT copy the slice-11/13 draw language). Live-settable with NO
# `set_fidelity` guard (the `:integrator`/`:autopilot`/`:apn`/`:cooperation`/`:airframe`
# precedent; the CONTRAST is slice-13 `:scan`, which flips draw topology and rejects introduction).
const ATMOSPHERE_MODES = (:constant, :exponential)
