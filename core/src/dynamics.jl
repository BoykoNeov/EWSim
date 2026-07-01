# dynamics.jl — the airframe force model + fixed-step integrators (HANDOFF §10 item 8,
# slice 8 gate 1). Pure, RNG-free, no LinearAlgebra — the §9 house style.
#
# The FIRST force-based dynamics in the project: slices 1–7 only ever moved passive
# bodies (`ConstantVelocity`'s `pos += vel·dt`). Here the specific force is
# `a(v) = g_vec + a_drag(v)` and a fixed `dt` step advances `(p, v)` by solving the
# first-order ODE `(ṗ, v̇) = (v, a(v))`. The stepping functions are pure
# `(accel, p, v, dt) → (p', v')` closures — unit-tested closed-form here, wired into the
# `BallisticMissile` subsystem in gate 2 (missile.jl, after radar.jl).
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden ones):
#   • flat-earth CONSTANT gravity `g` (no round-earth / inverse-square / Coriolis — the
#     project's frozen flat-earth/inertial stance);
#   • quadratic drag with CONSTANT air density `ρ`, point-mass (no atmosphere layering,
#     no attitude dynamics), lumped into `Cd·A`;
#   • passive body — no thrust / staging / variable mass (a rocket motor is a later slice).
#
# ROADMAP DEVIATION, NAMED (advisor #3): HANDOFF §10 item 8 sketches the switchable
# fidelity as `airframe = point_mass | 6dof`, but 6-DOF is deferred (§11 Tier A) and a
# one-value fidelity is a dead button. So slice 8's fidelity is the INTEGRATOR METHOD
# `integrator ∈ (:rk4, :euler)` — the "build/validate your integrator before you trust
# your missile" lesson made interactive (RK4 exact vs Euler bowing). The airframe stays
# implicitly `point_mass`; when 6-DOF lands it adds `airframe` alongside.

# The integrator-fidelity rungs. The SINGLE source of truth (the `ESTIMATOR_MODES` /
# `GPS_TOGGLE` "mode-const-before-radar, one-list-no-drift" precedent): gate-2's
# `LIVE_FIDELITY_MODES` (radar.jl) REFERENCES this, and `BallisticMissile.integrate!`
# dispatches on it — so a value the wire accepts can never reach a tick that throws.
# Defined HERE (dynamics.jl is included before radar.jl) so that reference needs no
# include-order gymnastics. Two rungs suffice (a probe rejected a `:semi_implicit` third
# rung — see test_missile.jl): `:rk4` (default, exact for constant-g) and `:euler` (the
# O(dt) lesson rung).
const INTEGRATOR_MODES = (:rk4, :euler)

# Standard gravity, m/s² (WGS/CGPM). Flat-earth constant field pointing along −z.
const G_ACCEL = 9.80665

"""
    gravity_accel() -> Vec3

The constant flat-earth gravitational specific force `[0, 0, −g]` (m/s²), independent of
position (named approximation — no round-earth / inverse-square / Coriolis). Because it
is position-independent, gravity-only motion is EXACTLY the degree-2 parabola
`p(t) = p₀ + v₀·t + ½·g_vec·t²` — the closed form the RK4 test pins against.
"""
gravity_accel() = Vec3(0.0, 0.0, -G_ACCEL)

"""
    drag_accel(v::Vec3; rho = 1.225, cd_area = 0.0, mass = 1.0) -> Vec3

Quadratic (Newtonian) aerodynamic drag specific force opposing velocity:

    a_drag(v) = −(ρ·Cd·A / (2·m))·‖v‖·v

magnitude ∝ ‖v‖². `cd_area` is the lumped `Cd·A` (m²); the ballistic coefficient is
`β = m/(Cd·A)`, so larger β → less drag → longer range. **Drag off is `cd_area = 0` →
a_drag = 0 EXACTLY** (the clean parabola + energy conservation). Constant `ρ` (named
approximation — no altitude/atmosphere layering). A (near-)zero speed returns zero (no
NaN from the `‖v‖·v` term).
"""
function drag_accel(v::Vec3; rho::Real = 1.225, cd_area::Real = 0.0, mass::Real = 1.0)
    (cd_area <= 0.0 || mass <= 0.0) && return zero(Vec3)
    speed = _norm3(v)
    speed < _FRAME_EPS && return zero(Vec3)
    k = rho * cd_area / (2.0 * mass)      # 1/(2β)·ρ
    return -(k * speed) * v
end

"""
    total_accel(v::Vec3; rho = 1.225, cd_area = 0.0, mass = 1.0) -> Vec3

Total specific force `a(v) = g_vec + a_drag(v)`. Depends only on velocity (gravity is
constant, drag ∝ v) — so a stepper needs only the velocity to evaluate the field.
"""
total_accel(v::Vec3; rho::Real = 1.225, cd_area::Real = 0.0, mass::Real = 1.0) =
    gravity_accel() + drag_accel(v; rho = rho, cd_area = cd_area, mass = mass)

# --- fixed-step integrators (pure `(accel, p, v, dt) -> (p', v')`) ---------------
# `accel` is a closure `v -> a(v)` (the force field); the steppers never see rho/cd/mass.

"""
    rk4_step(accel, p::Vec3, v::Vec3, dt) -> (p′, v′)

One classical 4-stage Runge-Kutta step of the first-order system `(ṗ, v̇) = (v, a(v))`.

**RK4 is EXACT for constant-gravity projectile motion** — it integrates the degree-2
polynomial solution with zero truncation error, so gravity-only `:rk4` reproduces the
analytic parabola to MACHINE EPSILON (the striking gate-1 pin). With drag it is the
accurate reference (O(dt⁴) local error). The default rung.
"""
function rk4_step(accel, p::Vec3, v::Vec3, dt::Float64)
    # y = (p, v); dy/dt = (v, a(v)). a depends only on v.
    k1v = accel(v)
    k2v = accel(v + (dt/2) * k1v)
    k3v = accel(v + (dt/2) * k2v)
    k4v = accel(v + dt * k3v)
    k1p = v
    k2p = v + (dt/2) * k1v
    k3p = v + (dt/2) * k2v
    k4p = v + dt * k3v
    p′ = p + (dt/6) * (k1p + 2*k2p + 2*k3p + k4p)
    v′ = v + (dt/6) * (k1v + 2*k2v + 2*k3v + k4v)
    return p′, v′
end

"""
    euler_step(accel, p::Vec3, v::Vec3, dt) -> (p′, v′)

One explicit forward-Euler step: `p′ = p + v·dt`, `v′ = v + a(v)·dt` (position uses the
OLD velocity). O(dt) global error; for gravity-only the position error is `≈ ½·g·dt·t`
(pinned in gate 1), which visibly bows the parabola at a coarse `dt`. The lesson rung.
"""
function euler_step(accel, p::Vec3, v::Vec3, dt::Float64)
    a = accel(v)
    return p + dt * v, v + dt * a
end

"""
    integrator_step(mode::Symbol, accel, p, v, dt) -> (p′, v′)

Dispatch a single step on the integrator-fidelity rung `mode ∈ INTEGRATOR_MODES`. An
unknown rung throws (the wire is validated against `INTEGRATOR_MODES`, so this fires only
on a programming error).
"""
function integrator_step(mode::Symbol, accel, p::Vec3, v::Vec3, dt::Float64)
    mode === :rk4   && return rk4_step(accel, p, v, dt)
    mode === :euler && return euler_step(accel, p, v, dt)
    error("integrator_step: unknown integrator :$mode ($(join(INTEGRATOR_MODES, " | ")))")
end
