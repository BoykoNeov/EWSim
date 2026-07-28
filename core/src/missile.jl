# missile.jl — the BallisticMissile subsystem: the FIRST force-based integrator in the
# tick loop (HANDOFF §3, §10 item 8, slice 8 gate 2).
#
# Slices 1–7 lit phases 2/3/4 of the tick contract repeatedly but only ever used phase 1
# (`integrate!`) for TRIVIAL kinematics — `ConstantVelocity`'s `pos += vel·dt`. The
# BallisticMissile is the first phase-1 mover that solves an actual Newtonian ODE
# (forces → accel → vel → pos) via the gate-1 steppers in `dynamics.jl`, under the shared
# `frames.jl` frame algebra. It lights NO NEW phase — its novelty is REAL dynamics where
# every prior slice had passive movers, plus the first live use of `frames.jl`
# (velocity-aligned attitude). `BallisticMissile` itself stays `integrate!`-ONLY: its
# `observe!`/`decide!` are empty and the airframe never adds them. Guidance and the seeker ride on
# SEPARATE subsystems layered onto the same `:missile` entity — the phase-4 `Autopilot` (slice 9,
# below) and the phase-3 `Seeker` (slice 11, below) — so "a missile is integrate! + observe! +
# decide!" (HANDOFF §3) is assembled from three subsystems, not folded into this one.
#
# Included AFTER radar.jl (mirroring geolocation.jl/esm.jl/gps.jl) but with NO back-dep on
# radar's radar/jammer symbols: it reuses only `dynamics.jl` (`total_accel`,
# `integrator_step`, `INTEGRATOR_MODES`, `G_ACCEL`), `frames.jl` (`quat_from_two_vectors`),
# gnss.jl's `_norm3`, and geometry.jl's `_finite`/`_finite_coord` — all in scope before it.
#
# TELEMETRY PHASE — a NAMED deviation from the plan's phrasing (advisor-confirmed): the plan
# sketch says "phase-1 writes into env[:telemetry] like the radar readout", but `tick!` calls
# `empty!(w.env)` immediately AFTER phase 1, so a phase-1 telemetry write is wiped before the
# frame is built (and the radar readout is actually PHASE-3 observe!, post-empty!). So the
# missile's ENERGY/POSITION readout is published from `build_env!` (phase 2, post-empty!,
# reading the post-integrate state) — a DERIVED quantity, order-independent, RNG-free, and NOT
# a sensing/guidance phase (those stay empty for slices 9–11). `integrate!` owns the physics;
# `build_env!` owns the readout.
#
# DETERMINISM (advisor #1 — the one place copying the slice-5/6/7 template gives a FALSE
# claim): there is NO RNG in slice 8, so "RNG lockstep" / "draw-count-invariance" is VACUOUS,
# not a property to prove. Three distinct claims, never conflated:
#   1. INTRODUCE-SAFE — absent a `:missile` entity nothing reads `:integrator`, so introducing
#      it mid-run on any slice-1..7 scenario is a no-op → slices 1–7 byte-identical.
#   2. same-config replay is bit-identical — deterministic, TRIVIALLY (no RNG to desync).
#   3. a mid-run `:integrator` toggle CHANGES the trajectory (the not-a-dead-knob property) —
#      the OPPOSITE of slices 5/6/7's toggle invariance. `:integrator` is a PHYSICS-CHANGING
#      fidelity (the slice-2 `propagation` shape), NOT toggle-bit-identical.
#
# NAMED APPROXIMATIONS (HANDOFF §1 — the force-model ones live in dynamics.jl; the two here):
#   • within-`dt` impact clamp — the ground crossing is clamped to `z = 0` within one step, NOT
#     sub-step root-found (sub-mm at guidance rates); named, not implied.
#   • velocity-aligned attitude is KINEMATIC-ONLY — a point-mass body has no attitude dynamics
#     (no fin/actuator model — 6-DOF is deferred, §11 Tier A); `att` is set to point body-x
#     along `v` purely for the client's nose direction, never fed back into the force.

# Total mechanical energy `E = ½·m·‖v‖² + m·g·z` (KE + flat-earth PE), joules — the "lesson as
# a number" (HANDOFF §1). Drag off + `:rk4` conserves it to machine eps over the flight; drag
# on bleeds it monotonically. Shared by the e0 init and the readout.
_missile_ke(mass, vel) = 0.5 * mass * (vel[1]^2 + vel[2]^2 + vel[3]^2)
_missile_pe(mass, pos) = mass * G_ACCEL * pos[3]
_missile_energy(mass, pos, vel) = _missile_ke(mass, vel) + _missile_pe(mass, pos)

# A mass floor at the consumer so a live/degenerate config can't divide-by-zero in the drag
# term or the energy (mass is loader-validated > 0, so this is belt-and-braces, the
# `_SIGMA_RANGE_FLOOR` precedent).
const _MISSILE_MASS_FLOOR = 1.0e-9
# Below this |E₀| the fractional conservation error `ΔE = (E−E₀)/E₀` is ill-defined (a launch
# at z=0 with v→0) → report 0.0 rather than a blow-up (which `_finite` would clamp anyway).
const _MISSILE_E_FLOOR = 1.0e-9

"""
    BallisticMissile(id)

The ballistic projectile `id` as a phase-1 `integrate!`-only subsystem — the FIRST
force-based integrator in the tick loop. Each physics step it solves the airframe ODE
`(ṗ, v̇) = (v, a(v))` (with `a = total_accel`, dynamics.jl) via the gate-1 stepper selected
by the `:integrator` fidelity (`get(w.fidelity, :integrator, :rk4)`), advancing the entity's
`(pos, vel)`. It owns `pos`/`vel` advancement, so the loader gives a `:missile` entity
`[BallisticMissile]` and **NOT** `ConstantVelocity` (two phase-1 movers would double-integrate).

Airframe config lives in the entity `comp` bag, read with DEFAULTS at the consumer so a bare
`:missile` block or a live slider can't `KeyError`/crash a tick (the "a live config can't crash
a tick" watch-item): `:mass_kg`, `:cd_area_m2` (the lumped `Cd·A`; drag off = `0`), `:rho`
(air density, default `1.225`). On the ground crossing (`z ≤ 0` descending) it clamps `z = 0`,
zeroes the velocity, latches `comp[:impacted] = true` (subsequent ticks no-op — the frozen
splash), and emits ONE `:impact` event. Sets a velocity-aligned attitude each step
(`quat_from_two_vectors([1,0,0], v̂)`, exercising `frames.jl` live + its apex `v→0` guard).
"""
struct BallisticMissile <: Subsystem
    id::Symbol
end

function integrate!(m::BallisticMissile, w::World, dt::Float64)
    e = w.entities[m.id]
    c = e.comp
    mass    = max(Float64(get(c, :mass_kg, 1.0)), _MISSILE_MASS_FLOOR)
    rho     = Float64(get(c, :rho, 1.225))
    cd_area = Float64(get(c, :cd_area_m2, 0.0))
    # E₀ = the launch energy, the ΔE reference. Lazily set on the first tick from the pre-step
    # (launch) state, so a loader-built AND a programmatically-built missile agree; survives
    # `reset` for free (reload → fresh comp → re-init from the reloaded launch state).
    haskey(c, :e0_j) || (c[:e0_j] = _missile_energy(mass, e.pos, e.vel))

    # Once impacted the missile is frozen: no more integration (the readout still republishes
    # in build_env!, so the frame never blanks). The latch makes the :impact event one-shot.
    if !get(c, :impacted, false)
      # SLICE 17 COUPLING GATE (§11 Tier A): when the missile carries airframe params AND the
      # `:airframe` fidelity is `:pitch_coupled`, the angle of attack α = θ−γ generates a body
      # lift ⟂ v that TURNS the flight path — the whole `[pos, vel, θ, q]` state advances JOINTLY
      # in one `rk4_coupled` step (`_integrate_coupled!`). Else (the DEFAULT `:point_mass` — every
      # slice-8..16 scenario) the point-mass `integrator_step` + the slice-16 isolated / slice-8
      # velocity-aligned attitude, TEXTUALLY UNCHANGED below (byte-identity — the coupled branch
      # is unreachable without BOTH `:af_cma` AND the new fidelity key). Class 4c (no RNG).
      if haskey(c, :af_cma) && get(w.fidelity, :airframe, :point_mass) === :pitch_coupled
        _integrate_coupled!(m, e, c, w, mass, rho, cd_area, dt)
      elseif haskey(c, :af_cma) && get(w.fidelity, :airframe, :point_mass) === :six_dof
        # SLICE 23 6-DOF GATE (§11 Tier A) — the 3-D superset. A NEW rung reaching a NEW branch
        # (`_integrate_6dof!`), gated identically to `:pitch_coupled` above but on `:six_dof`. The
        # `att` becomes a GENUINE 3-D quaternion integrated from a body-rate vector ω = (p, q, r)
        # (parallel comp keys `:att_q`/`:omega_body`, NEVER `:pitch_theta`/`:pitch_q`), and the
        # guidance command keeps its FULL 3-D direction so lift can point ANYWHERE off v̂ (STT). The
        # `:pitch_coupled` line above and the `else` below are TEXTUALLY VERBATIM — a slice-8..22
        # scenario never sets `:six_dof`, never grows the 3-D keys → byte-identical by construction
        # (the scalar `rk4_coupled` path is UNREACHABLE from a quaternion representation, and vice
        # versa; the reduction is an atol golden, not `==` — plan §1). Class 4c (no RNG).
        _integrate_6dof!(m, e, c, w, mass, rho, cd_area, dt)
      else
        mode = get(w.fidelity, :integrator, :rk4)
        # GUIDANCE SEAM (slice 9): a GUIDED missile carries a control specific force `:a_ctrl`
        # (a Vec3, written by the Autopilot's phase-4 decide! LAST tick → applied HERE this tick,
        # the one-tick delay). The `haskey` GUARD makes a BALLISTIC missile (no :a_ctrl) take the
        # EXACT slice-8 closure — byte-identity BY CONSTRUCTION, not by trusting
        # `total_accel(v) + zero(Vec3)` (`-0.0 + 0.0 → +0.0` flips a bit the reinterpret
        # determinism tests catch). `:a_ctrl` is a Vec3 so the SVector+SVector add stays bit-exact.
        accel = if haskey(c, :a_ctrl)
            a_ctrl = c[:a_ctrl]::Vec3
            v -> total_accel(v; rho = rho, cd_area = cd_area, mass = mass) + a_ctrl
        else
            v -> total_accel(v; rho = rho, cd_area = cd_area, mass = mass)
        end
        p′, v′ = integrator_step(mode, accel, e.pos, e.vel, dt)
        if p′[3] ≤ 0.0
            # Ground impact: clamp z=0 within the step (named approx — no sub-step root-find),
            # freeze, and emit ONE :impact event. A launch at z=0 with an UPWARD velocity rises
            # (`p′[3] > 0`) so it does NOT insta-impact; a descending crossing does. Events live
            # in `w.events` (NOT env — so not wiped by `empty!(w.env)`), cleared by the server
            # after the frame ships (the detection-event precedent).
            p′ = Vec3(p′[1], p′[2], 0.0)
            v′ = zero(Vec3)
            c[:impacted] = true
            push!(w.events, Dict{Symbol,Any}(:kind => :impact, :of => m.id))
        end
        e.pos = p′
        e.vel = v′
        # ATTITUDE — two regimes, gated on airframe-params presence (slice 16, §11 Tier A):
        #   • NO airframe params (slices 8–15, the DEFAULT) → velocity-aligned attitude
        #     (kinematic-only named approx): body-x along v̂. BYTE-IDENTICAL to slice 8 — the
        #     `haskey(c, :af_cma)` guard makes a non-airframe missile take the EXACT prior line
        #     (the `:a_ctrl` guard precedent — no RNG, no state, so class-4c introduce-safe).
        #   • airframe params PRESENT → att is a DYNAMICAL output of the pitch-plane rotational
        #     integrator: `att` finally comes alive (Cmα<0 weathervanes/oscillates, Cmα>0
        #     tumbles). Rotation reads the live flight condition (V, γ) but does NOT feed back
        #     into (pos, vel) — the slice-16 ISOLATION (α→lift coupling is slice 17). At θ = γ
        #     (α = 0) this reduces to the velocity-aligned quaternion (same convention).
        if haskey(c, :af_cma)
            _integrate_airframe!(e, c, w, v′, dt)
        else
            # Velocity-aligned attitude (kinematic-only, named approx): body-x along v̂ gives the
            # client a nose direction and exercises `frames.jl` in the live tick; the apex/impact
            # `v→0` hits `quat_from_two_vectors`'s zero-vector guard (→ identity, no NaN).
            e.att = quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), v′)
        end
      end
    end
    return nothing
end

# Slice 17 — the COUPLED pitch-plane integrate! branch (`:airframe === :pitch_coupled`). The
# angle of attack α = θ−γ generates a body lift ⟂ v (airframe.jl `lift_accel`) that turns the
# flight path, and the attitude `(θ, q)` evolves under the aero moment — the WHOLE `[pos, vel,
# θ, q]` state advances JOINTLY in ONE `rk4_coupled` step. The stiff short-period must NOT be
# operator-split from translation; the coupling IS the mid-step (V, γ) re-evaluation inside each
# RK4 stage (gate-0 finding).
#
# THE FIN δ (slice 19 CLOSED the loop): read from `:delta_cmd` — the scalar deflection the phase-4
# `:alpha` autopilot commanded LAST tick (`decide!` → next tick's `integrate!`, the same one-tick
# delay as `:a_ctrl`) — falling back to slice-17's FIXED authored `af_delta` trim when no autopilot
# closes it. So a slice-17 OPEN-LOOP scenario has no `:delta_cmd` key → reads `af_delta` → BIT-
# IDENTICAL; and tick 1 (integrate! precedes the first decide!) likewise flies `af_delta`.
#
# `:a_ctrl` STAYS OUT OF THIS FORCE — DELIBERATELY, and the slice-17 comment that once stood here
# saying otherwise was WRONG (slice-19 finding 1, load-bearing). The whole content of the slice-19
# lesson is that the achievable maneuver accel IS THE LIFT CEILING `a_max_aero = Q·S·C_Lα·α_max/m`.
# Adding the autopilot's `:a_ctrl` back into the joint force would give the missile lift PLUS a
# direct fixed-`a_max` control force: it would over-maneuver, the aero ceiling would NEVER BIND, and
# the point-mass plant would be silently rebuilt in an airframe costume (the slice-15 k_δ-cancellation
# / slice-16 false-fidelity trap, THIRD occurrence in this arc). Guidance reaches this plant ONLY
# through δ. `Autopilot.decide!` does not even persist `:a_ctrl` under `:alpha`+`:pitch_coupled`, so a
# pure-coupled run never grows the key.
#
# RK4-ONLY: this branch
# does NOT honor the `:integrator` euler rung (the coupled short-period is stiff — euler would be a
# different, divergent lesson; convention 9 keeps the showcase from mixing them, and it can't
# crash). NO RNG (class 4c). The `:point_mass` path above is byte-identical to slices 8–16.
# --- SLICE 21: the EXPONENTIAL ATMOSPHERE gate (§11 Tier A) -----------------------------------
# `true` when this missile carries an authored scale height, the `:atmosphere` rung is live, AND
# the airframe is COUPLED. The ONE place the gate is expressed, so the five ρ-reading airframe
# sites cannot drift apart (convention 7's one-list-no-drift, applied to a predicate). Slices 8–20
# have no `:af_scale_height`, and the rung DEFAULTS to `:constant` — so this is `false` on every
# prior scenario by BOTH halves, and each caller's else-arm is the prior slice's code TEXTUALLY
# VERBATIM (byte-identity by construction, not by trusting `exp(0) == 1`; the `-0.0` trap the
# slice-20 induced-drag gate documents).
#
# ⭐ THE THIRD CONJUNCT IS NOT DECORATION — `:atmosphere` IS INERT WITHOUT `:pitch_coupled`, the
# slice-14 (`:salvo` inert without a `:datalink`) / slice-13 (`discrimination` inert without
# `:scan`) shape. ρ(z) reaches ONLY the coupled path: `_integrate_coupled!` is itself gated on
# `:pitch_coupled`, so under `:point_mass` the translation flies `total_accel`'s AUTHORED constant
# ρ no matter what this rung says. Without this conjunct the readouts (and slice-16's rotational
# `_integrate_airframe!`) would report ρ(z) while pos/vel flew ρ₀ — HALF THE MISSILE IN ONE
# ATMOSPHERE AND HALF IN ANOTHER, and a readout that describes a different missile than the one on
# screen is exactly what the four-site `_airframe_rho` funnel exists to prevent. Under
# `:point_mass` every site reverts to ρ₀ together, which is COHERENT: that plant makes its accel by
# fiat, so there is no lift ceiling for the air to lower and nothing for ρ(z) to mean.
_atm_on(c::Dict{Symbol,Any}, w::World) =
    haskey(c, :af_scale_height) &&
    get(w.fidelity, :atmosphere, :constant) === :exponential &&
    get(w.fidelity, :airframe, :point_mass) === :pitch_coupled

# The airframe's air density at height `z` — ρ(z) under the live rung, else the authored constant.
# **Returns the IDENTICAL expression the frozen paths already had when gated off**, which is what
# makes the four call sites safe to reroute through it. `H` is floored inside `air_density`
# (convention 5's clamp-at-consumer — it is a live slider).
_airframe_rho(c::Dict{Symbol,Any}, w::World, z::Float64) =
    _atm_on(c, w) ? air_density(z; rho0 = Float64(get(c, :rho, 1.225)),
                                H = Float64(c[:af_scale_height])) :
                    Float64(get(c, :rho, 1.225))

# --- SLICE 22: the NONLINEAR-AERO (TRUE STALL) gate (§11 Tier A) -------------------------------
# `true` when this missile carries an authored stall corner AND the airframe is COUPLED. The ONE
# place the gate is expressed (the `_atm_on` precedent — convention 7's one-list-no-drift applied
# to a predicate), so the integrator and every readout cannot drift apart.
#
# ⚠ THERE IS NO RUNG HERE, AND THAT IS MEASURED, NOT AN OVERSIGHT. The plan's gate-2 sketch says
# "`LIVE_FIDELITY_MODES` gains `aero_curve`" — **that sketch is STALE and contradicts its own
# Decision 1**: gate-0 F7 REFUTED the rung claim (the plan asserted linear was `α_stall → ∞`, a
# limit point). The achieved α SELF-LIMITS to ~0.24 across the whole viable geometry family, so an
# α_stall parked at ≥ 0.25 is linear-in-effect over EVERY REACHABLE STATE — the off-state IS
# knob-reachable, so slice 21's own discriminator returns KNOB (the `af_cma`/`af_k_induced` shape).
# So: KEY-gated, no `AERO_CURVE_MODES`, no `set_fidelity`, no button. `test_aero_curve.jl` ASSERTS
# their absence, so adding one later is a deliberate act that breaks a test.
#
# ⭐ THE `:pitch_coupled` CONJUNCT IS A DELIBERATE DECISION, NOT INHERITED BOILERPLATE (advisor).
# The plan warns (§gate 2) that **the moment break reaches FURTHER than ρ(z) did**: `pitch_moment`
# is live on the `:point_mass` rotational path too (`_integrate_airframe!`), so without this
# conjunct a `:point_mass` wire would integrate θ/q through a BREAKING moment while pos/vel flew a
# linear-aero fiat accel — half the missile in one aerodynamic model and half in another, which is
# EXACTLY slice 21's `_atm_on` latent bug. Under `:point_mass` every site reverts to linear
# together, which is coherent: that plant makes its accel by fiat, so there is no lift ceiling for
# a stall to lower and nothing for the curve to mean. `_integrate_airframe!` is therefore
# UNTOUCHED by this slice.
_stall_on(c::Dict{Symbol,Any}, w::World) =
    haskey(c, :af_alpha_stall) &&
    get(w.fidelity, :airframe, :point_mass) === :pitch_coupled

# The authored nonlinear-aero shape (aero_curve.jl). Defaults keep every field in its documented
# domain if a scenario authors only the corner: `k_drop = 1` (lift falls as fast as it rose),
# `K_sep = 0` (no separation bill), and — critically — `α_break`/`α_sat` default ABOVE the stall,
# so authoring `alpha_stall` ALONE gives the LIFT lesson with a LINEAR moment (no departure). The
# two lessons are separately authorable; the LOADER validates every field (convention 5).
_stall_params(c::Dict{Symbol,Any}) =
    AeroCurveParams(Float64(c[:af_alpha_stall]),
                    Float64(get(c, :af_k_drop, 0.7)),
                    Float64(get(c, :af_k_sep, 0.0)),
                    Float64(get(c, :af_alpha_break, 1.0e9)),
                    Float64(get(c, :af_cma_post, 0.0)),
                    Float64(get(c, :af_alpha_sat, 2.0e9)))

function _integrate_coupled!(m::BallisticMissile, e::Entity, c::Dict{Symbol,Any}, w::World,
                             mass::Float64, rho::Float64, cd_area::Float64, dt::Float64)
    # Lazy launch init of the JOINT attitude from the PRE-step (launch) flight-path angle — θ is
    # part of the jointly-integrated state, so it is seeded BEFORE the step (contrast the
    # point-mass `_integrate_airframe!`, which seeds from the POST-step v′). Survives reset via
    # reload; `:af_alpha0` is the authored nose-off-velocity perturbation (default 0).
    if !haskey(c, :pitch_theta)
        γ0 = atan(e.vel[3], e.vel[1])
        c[:pitch_theta] = γ0 + Float64(get(c, :af_alpha0, 0.0))
        c[:pitch_q]     = 0.0
    end
    # `K` (slice 20's induced-drag factor) rides in the params as the LAST field. Building it here
    # UNCONDITIONALLY is byte-safe: `pitch_moment`/`lift_accel`/`short_period_freq` never read `K`,
    # so their arithmetic is untouched. What is NOT byte-safe is CALLING the drag term — see below.
    p = AirframeParams(Float64(c[:af_S]), Float64(c[:af_d]), Float64(c[:af_I]),
                       Float64(c[:af_cma]), Float64(c[:af_cmd]), Float64(c[:af_cmq]),
                       rho, Float64(get(c, :af_cla, 0.0)), Float64(get(c, :af_k_induced, 0.0)))
    # THE δ SEAM (slice 19): the `:alpha` autopilot's commanded deflection if it ran last tick, else
    # slice-17's authored open-loop trim (the byte-identity fallback — see the header).
    δ = Float64(get(c, :delta_cmd, get(c, :af_delta, 0.0)))
    θ, q = Float64(c[:pitch_theta]), Float64(c[:pitch_q])
    # The coupled derivative f(pos, vel, TH, Q) -> (ṗ, v̇, θ̇, q̈). CRITICAL (advisor): the lift AND
    # the moment read the STAGE pitch `TH` (the RK4 stage argument), NEVER the entry `θ` closed over
    # above — using the entry θ compiles clean and is only O(dt²) off per step, invisible to the
    # steady-turn R test (α≈const) and the decoupled test (Cla=0), so the stage-θ wiring is pinned
    # by a transient golden in test_missile. ṗ = vel; v̇ = the point-mass force (gravity+drag, the
    # SAME `total_accel` closure) + the lift (⟂ v, α = TH−γ); θ̇ = q (the stage `Q`); q̈ = M/I.
    #
    # SLICE 20 — TWO CLOSURES, NOT ONE WITH A `+ 0` (advisor, load-bearing). The induced-drag arm is
    # reachable ONLY when the missile carries an authored `:af_k_induced`; the else-arm is slice
    # 17/19 TEXTUALLY VERBATIM. Adding `+ induced_drag_accel(...)` unconditionally and trusting
    # K = 0 → zero would NOT be byte-identical: a `0.0*v` can mint `-0.0` components and
    # `a + (-0.0)` flips a bit (`-0.0 + 0.0 → +0.0`) — exactly the trap the `:a_ctrl` guard above
    # documents and the reinterpret determinism tests catch. Same `p`, same δ, same stage-θ
    # discipline; the ONLY difference is the extra force term. Class 4c (no RNG).
    #
    # SLICE 22 — THE STALL ARM LEADS, AND THE FOUR ARMS BELOW IT ARE UNTOUCHED. Adding stall as a
    # SECOND DIMENSION would have doubled 4 closures to 8; as a LEADING branch it adds ONE and every
    # prior arm stays textually verbatim (advisor). ⚠ That is only sound because **stall × the
    # exponential atmosphere is RULED OUT AT LOAD, not by branch order** — a missile carrying both
    # `af_alpha_stall` and `af_scale_height` is a LOAD ERROR (convention 9: one lesson per scenario;
    # and a silent precedence here would be the slice-21 `_atm_on` latent-bug class exactly). So the
    # stall arm is constant-ρ by construction, `p` and the curve are built ONCE outside the closure,
    # and there is no per-stage params rebuild to get wrong.
    #
    # Induced drag is included UNCONDITIONALLY in this arm (contrast the two arms below, which must
    # split on `haskey(:af_k_induced)`). There is no byte-identity to preserve on a path NO PRIOR
    # SLICE CAN REACH, so the `-0.0` hazard that forces the split down there does not arise; with
    # `K = 0` the term is EXACTLY `Vec3(0,0,0)` and the arithmetic is deterministic either way.
    f = if _stall_on(c, w)
        curve = _stall_params(c)
        # ⚠ EVERY TERM READS THE STAGE PITCH `TH`, NEVER the entry θ — slice 17's stage-θ fix, and
        # the NEW separation term carries the SAME hazard because it too is α-dependent (plan gate
        # 2). All four aero terms below are functions of the stage α = TH − γ.
        (P, Vv, TH, Q) -> begin
            γ = atan(Vv[3], Vv[1])
            a = total_accel(Vv; rho = rho, cd_area = cd_area, mass = mass) +
                lift_accel_nl(Vv, TH, mass, p, curve) +
                induced_drag_accel_nl(Vv, TH, mass, p, curve) +
                separation_drag_accel(Vv, TH, mass, p, curve)
            (Vv, a, Q, pitch_moment_nl(TH - γ, δ, Q, _norm3(Vv), p, curve) / p.I)
        end
    elseif _atm_on(c, w)
        # ── SLICE 21 — THE EXPONENTIAL-ATMOSPHERE ARM. `ρ` is no longer a number: it is read
        # PER RK4 STAGE from the STAGE HEIGHT `P[3]`.
        #
        # ★ THE STAGE-z FIX (the slice-17 STAGE-θ FIX's exact analog, load-bearing for the same
        # reason): `P` — the stage position — has been threaded through this closure since slice
        # 17 and READ BY NOTHING. This is what finally reads it. Using the ENTRY height
        # (`e.pos[3]`, closed over) instead compiles clean and is only O(dt²) off per step:
        # gate-0 F9 MEASURED it at max|Δz| = 0.77 m over 90 s, moving the miss 0.136 m on a
        # 360 m lesson — 0.04%, INVISIBLE to every steady-state test (the ρ-factor, the ceiling
        # and the miss ratio all survive it). ONLY the transient golden in test_missile.jl
        # catches it. Do NOT "simplify" this to the entry height.
        #
        # The params are REBUILT PER STAGE with the stage ρ (an isbits struct — stack-allocated,
        # free) rather than threading a `rho` kwarg through six aero functions. That is what
        # keeps `lift_accel`/`induced_drag_accel`/`pitch_moment` MEASUREMENT-AGNOSTIC AND z-FREE
        # (§12): the aero lib never learns about altitude, it just gets a `p` whose rho is the
        # stage value. The stage ρ ALSO goes to `total_accel`, so this arm is fully
        # self-consistent — parasitic drag, lift, induced drag and the moment all see ONE air.
        H_sh = Float64(c[:af_scale_height])
        if haskey(c, :af_k_induced)
            (P, Vv, TH, Q) -> begin
                ρs  = air_density(P[3]; rho0 = rho, H = H_sh)      # ← THE STAGE HEIGHT
                p_s = AirframeParams(p.S, p.d, p.I, p.Cma, p.Cmd, p.Cmq, ρs, p.Cla, p.K)
                γ = atan(Vv[3], Vv[1])
                a = total_accel(Vv; rho = ρs, cd_area = cd_area, mass = mass) +
                    lift_accel(Vv, TH, mass, p_s) + induced_drag_accel(Vv, TH, mass, p_s)
                (Vv, a, Q, pitch_moment(TH - γ, δ, Q, _norm3(Vv), p_s) / p_s.I)
            end
        else
            (P, Vv, TH, Q) -> begin
                ρs  = air_density(P[3]; rho0 = rho, H = H_sh)      # ← THE STAGE HEIGHT
                p_s = AirframeParams(p.S, p.d, p.I, p.Cma, p.Cmd, p.Cmq, ρs, p.Cla, p.K)
                γ = atan(Vv[3], Vv[1])
                a = total_accel(Vv; rho = ρs, cd_area = cd_area, mass = mass) +
                    lift_accel(Vv, TH, mass, p_s)
                (Vv, a, Q, pitch_moment(TH - γ, δ, Q, _norm3(Vv), p_s) / p_s.I)
            end
        end
    elseif haskey(c, :af_k_induced)
        # ── SLICES 17/19/20, TEXTUALLY VERBATIM from here down. This arm serves BOTH key-absent
        # AND `:atmosphere === :constant`, so the rung's OFF state and every prior slice take
        # literally the same code — byte-identity by construction (advisor).
        (P, Vv, TH, Q) -> begin
            γ = atan(Vv[3], Vv[1])
            a = total_accel(Vv; rho = rho, cd_area = cd_area, mass = mass) +
                lift_accel(Vv, TH, mass, p) + induced_drag_accel(Vv, TH, mass, p)
            (Vv, a, Q, pitch_moment(TH - γ, δ, Q, _norm3(Vv), p) / p.I)
        end
    else
        (P, Vv, TH, Q) -> begin
            γ = atan(Vv[3], Vv[1])
            a = total_accel(Vv; rho = rho, cd_area = cd_area, mass = mass) +
                lift_accel(Vv, TH, mass, p)
            (Vv, a, Q, pitch_moment(TH - γ, δ, Q, _norm3(Vv), p) / p.I)
        end
    end
    p′, v′, θ′, q′ = rk4_coupled(f, e.pos, e.vel, θ, q, dt)
    if p′[3] ≤ 0.0
        # Ground impact — the point-mass branch's clamp / freeze / one-shot `:impact` event,
        # duplicated here (kept SEPARATE from the point-mass code so its arithmetic stays
        # byte-identical; advisor). θ′/q′ hold the attitude at the impact instant; next tick the
        # `:impacted` latch skips integration entirely (no further rotation).
        p′ = Vec3(p′[1], p′[2], 0.0)
        v′ = zero(Vec3)
        c[:impacted] = true
        push!(w.events, Dict{Symbol,Any}(:kind => :impact, :of => m.id))
    end
    e.pos = p′
    e.vel = v′
    c[:pitch_theta] = θ′
    c[:pitch_q]     = q′
    # Nose direction from the integrated pitch θ′ (θ = γ ⇒ identical to velocity-aligned; the
    # slice-16 convention). The v→0 degenerate rides `quat_from_two_vectors`'s zero guard.
    e.att = quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), Vec3(cos(θ′), 0.0, sin(θ′)))
    return nothing
end

# Slice 23 — the 6-DOF integrate! branch (`:airframe === :six_dof`). The 3-D superset of
# `_integrate_coupled!`: the SAME [pos, vel] force integration + gravity/drag, but `att` is now a
# genuine quaternion advanced from a body-rate vector ω = (p, q, r) under the 3-D rigid-body
# dynamics (airframe3d.jl `stt_moments` → `body_rate_deriv` → `attitude_kinematics`), and the lift
# is 2-plane (`lift_accel_3d`: pitch lift ∝ α on n̂_pitch AND yaw side-force ∝ β on n̂_yaw), so the
# ⟂-v accel can point ANYWHERE off v̂. `_integrate_coupled!`'s `:pitch_theta`/`:pitch_q` are
# UNTOUCHED — this path mints its OWN `:att_q`/`:omega_body` keys (parallel state), so a
# slice-16..22 wire is byte-identical (it never reaches here). Class 4c (no RNG).
#
# ⚠ THE 2-CHANNEL δ SEAM: the `:alpha` autopilot's `:six_dof` arm (phase-4 decide!) writes BOTH
# `:delta_cmd` (pitch fin) AND `:delta_yaw_cmd` (yaw fin) LAST tick; this integrate! reads them
# (the one-tick delay, the `:a_ctrl`/`:delta_cmd` precedent). Absent (slice-17-style open loop or
# a fresh live toggle) they default to slice-17's authored `:af_delta` / 0 — the byte-identity
# fallback. NAMED APPROXIMATION (plan §4): lift is drag-free (⟂ v, speed-preserving as slice 17);
# induced/separation drag and ρ(z) on the 6-DOF path are a later composition, not this slice — so
# there is ONE closure here, not the four `_integrate_coupled!` carries.
#
# ⭐ THE SIGN WIRING is airframe3d.jl's (the #1 SIGN TRAP's FIFTH occurrence) — the pitch aero
# moment maps to −y (negated), the yaw to +z (not), physical rates α̇=−ω_y, β̇=+ω_z. All of it lives
# in `stt_moments`; this branch just calls it. The P1a structural invariant (an in-plane run keeps
# the out-of-plane states at the FP floor) is the gate-1 sign check; the reduction golden (in-plane
# 6-DOF ≈ scalar `_integrate_coupled!` to a dt-measured atol) is the gate-2 wiring check.
function _integrate_6dof!(m::BallisticMissile, e::Entity, c::Dict{Symbol,Any}, w::World,
                          mass::Float64, rho::Float64, cd_area::Float64, dt::Float64)
    # Lazy launch init of the JOINT attitude from the PRE-step (launch) flight-path angle — like
    # `_integrate_coupled!`'s θ seed, but as a quaternion (nose along (cosθ₀,0,sinθ₀), the same
    # `quat_from_two_vectors` convention the pitch path and the gate-0 P1b reduction probe use) and
    # a zero body-rate. `:af_alpha0` is the authored nose-off-velocity perturbation (default 0).
    # Survives reset via reload.
    if !haskey(c, :att_q)
        γ0 = atan(e.vel[3], e.vel[1])
        θ0 = γ0 + Float64(get(c, :af_alpha0, 0.0))
        c[:att_q]      = quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), Vec3(cos(θ0), 0.0, sin(θ0)))
        c[:omega_body] = zero(Vec3)
    end
    # AirframeParams as in `_integrate_coupled!` (the K field rides unread — `lift_accel_3d`/
    # `stt_moments` never touch it, so its presence is byte-safe). The 6-DOF-only aero/inertia
    # constants default at the CONSUMER (a live `:airframe` toggle of a slice-19..22 scenario that
    # never authored them can't crash a tick — convention 5; load validates them WHEN authored).
    p = AirframeParams(Float64(c[:af_S]), Float64(c[:af_d]), Float64(c[:af_I]),
                       Float64(c[:af_cma]), Float64(c[:af_cmd]), Float64(c[:af_cmq]),
                       rho, Float64(get(c, :af_cla, 0.0)), Float64(get(c, :af_k_induced, 0.0)))
    c_yaw  = Float64(get(c, :af_cy_beta, p.Cla))            # symmetric cruciform default (plan §3)
    c_roll = Float64(get(c, :af_c_roll, 50.0))             # roll damper (STT holds p≈0; gate-0 P5)
    Idiag  = Vec3(Float64(get(c, :af_I_roll, p.I)),        # I_xx (roll); default I_yy (roll stays ≈0)
                  p.I,                                      # I_yy (pitch) = the scalar path's inertia
                  Float64(get(c, :af_I_zz, p.I)))          # I_zz (yaw) = I_yy by symmetry
    δp = Float64(get(c, :delta_cmd,     get(c, :af_delta, 0.0)))
    δy = Float64(get(c, :delta_yaw_cmd, 0.0))
    q0 = c[:att_q]::Quat
    ω0 = c[:omega_body]::Vec3
    # SLICE 24 — the STEERING law selects the ROLL channel. `:bank_to_turn` swaps the STT roll damper
    # (`stt_moments`' `−c_roll·p`) for the τ_roll bank autopilot (airframe3d.jl `btt_moments`), reading
    # the bank COMMAND `:phi_cmd` written by LAST tick's decide! (the `:delta_cmd` seam's sibling; tick
    # 1 defaults to 0 ⇒ wings-level, no roll). Default `:skid_to_turn` ⇒ `stt_moments` VERBATIM (slice
    # 23 byte-frozen — a slice-1..23 wire never sets `:steering`). `:steering` is INERT without
    # `:six_dof` (this branch IS the 6-DOF path; the scalar plant has no roll DOF — plan §1). τ_roll
    # clamped > 0 at the consumer (a live slider can't crash — convention 5; the AUTHORED value is
    # load-validated). I_xx (roll inertia) sits in the roll-loop gain — a NON-knob (plan §3).
    steering = get(w.fidelity, :steering, :skid_to_turn)
    τ_roll   = max(Float64(get(c, :af_tau_roll, 1.0)), _FRAME_EPS)
    φ_cmd    = Float64(get(c, :phi_cmd, 0.0))
    # The joint 6-DOF derivative f(pos, vel, q, ω) -> (ṗ, v̇, q̇, ω̇). CRITICAL (the slice-17 stage-θ
    # / slice-21 stage-z discipline): the lift AND the moment read the STAGE quaternion `Qq` and
    # stage rate `W` (the RK4 stage arguments), NEVER the entry `q0`/`ω0` closed over above — the
    # coupling IS the mid-stage re-evaluation (`rk4_6dof` renormalizes q each stage). ṗ = vel;
    # v̇ = the point-mass force (gravity+drag, the SAME `total_accel` closure) + the 2-plane lift;
    # q̇ = ½ q ⊗ [0,ω]; ω̇ = I⁻¹(M − ω×Iω). The stage `P` (position) is threaded for the
    # `rk4_6dof` contract and reserved for a future ρ(z) on this path (slice 21's stage-z seam),
    # read by nothing this slice — deliberately, lift is constant-ρ (drag-free) here.
    f = (P, Vv, Qq, W) -> begin
        a  = total_accel(Vv; rho = rho, cd_area = cd_area, mass = mass) +
             lift_accel_3d(Vv, Qq, mass, p; c_yaw = c_yaw)
        q̇  = attitude_kinematics(Qq, W)
        M  = steering === :bank_to_turn ?
             btt_moments(Qq, Vv, W, δp, δy, φ_cmd, p; I_xx = Idiag[1], τ_roll = τ_roll) :
             stt_moments(Qq, Vv, W, δp, δy, p; c_roll = c_roll)
        ω̇  = body_rate_deriv(W, M, Idiag)
        (Vv, a, q̇, ω̇)
    end
    p′, v′, q′, ω′ = rk4_6dof(f, e.pos, e.vel, q0, ω0, dt)
    if p′[3] ≤ 0.0
        # Ground impact — the point-mass / coupled branch clamp / freeze / one-shot `:impact` event,
        # duplicated here (kept SEPARATE so its arithmetic stays byte-identical; advisor). q′/ω′ hold
        # the attitude/rate at impact; next tick the `:impacted` latch skips integration entirely.
        p′ = Vec3(p′[1], p′[2], 0.0)
        v′ = zero(Vec3)
        c[:impacted] = true
        push!(w.events, Dict{Symbol,Any}(:kind => :impact, :of => m.id))
    end
    e.pos = p′
    e.vel = v′
    c[:att_q]      = q′
    c[:omega_body] = ω′
    e.att          = q′                                   # `att` maps body→inertial (airframe3d.jl)
    return nothing
end

# Pitch-plane rotational integration (slice 16). Advances the airframe attitude `(θ, q)` in
# comp under the aero moment (airframe.jl), with the flight condition `(V, γ)` FROZEN over the
# step — read from the just-integrated velocity `v′`, NOT fed back into it (the isolation). The
# angle of attack `α = θ − γ`; on the FIRST tick `θ` is lazily initialized to `γ + α₀` (the
# authored initial perturbation `:af_alpha0`, default 0), so the missile can be launched nose
# off the velocity vector to excite the oscillation. `att` is then set from `θ` (nose along
# `(cosθ, 0, sinθ)`), the same `quat_from_two_vectors` convention as the velocity-aligned path.
function _integrate_airframe!(e::Entity, c::Dict{Symbol,Any}, w::World, v′::Vec3, dt::Float64)
    Vspeed = _norm3(v′)
    γ = atan(v′[3], v′[1])                                # pitch-plane flight-path angle
    if !haskey(c, :pitch_theta)                           # lazy launch init (survives reset via reload)
        c[:pitch_theta] = γ + Float64(get(c, :af_alpha0, 0.0))
        c[:pitch_q]     = 0.0
    end
    # SLICE 21: ρ(z) under the live `:atmosphere` rung, else the authored constant — the SAME
    # expression as before when gated off (byte-identical; `w` was threaded in for this). Read at
    # the POST-step height, matching this path's post-step (V, γ): the slice-16 rotation is
    # ISOLATED (it cannot move `pos` — posdiff = 0), so there is no stage to resolve here and no
    # stage-z subtlety. The COUPLED path is where the stage height matters.
    p = AirframeParams(Float64(c[:af_S]), Float64(c[:af_d]), Float64(c[:af_I]),
                       Float64(c[:af_cma]), Float64(c[:af_cmd]), Float64(c[:af_cmq]),
                       _airframe_rho(c, w, e.pos[3]), Float64(get(c, :af_cla, 0.0)))
    δ = Float64(get(c, :af_delta, 0.0))                   # open-loop fin deflection (no autopilot this slice)
    θ, q = Float64(c[:pitch_theta]), Float64(c[:pitch_q])
    θ′, q′ = airframe_step(θ, q, dt; gamma = γ, V = Vspeed, delta = δ, p = p)
    c[:pitch_theta] = θ′
    c[:pitch_q]     = q′
    # Nose direction from the integrated pitch angle → the client's attitude (θ = γ ⇒ identical
    # to velocity-aligned). The `v→0`/degenerate case rides quat_from_two_vectors's guards.
    e.att = quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), Vec3(cos(θ′), 0.0, sin(θ′)))
    return nothing
end

# Phase-2 readout (see the TELEMETRY PHASE note above): the energy/position scalars, derived
# from the post-integrate state so they match the entity `pos` shipping in the same frame. No
# RNG, own keys only → order-independent (the build_env! contract). All `_finite`-clamped so a
# degenerate config ships huge-but-finite, never Inf/NaN.
function build_env!(m::BallisticMissile, w::World)
    e = w.entities[m.id]
    c = e.comp
    mass  = max(Float64(get(c, :mass_kg, 1.0)), _MISSILE_MASS_FLOOR)
    ke    = _missile_ke(mass, e.vel)
    pe    = _missile_pe(mass, e.pos)
    etot  = ke + pe
    e0    = Float64(get(c, :e0_j, etot))
    de    = abs(e0) < _MISSILE_E_FLOOR ? 0.0 : (etot - e0) / e0
    tel   = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid   = String(m.id)
    tel["$sid.pos_x"]     = _finite_coord(e.pos[1])
    tel["$sid.pos_z"]     = _finite_coord(e.pos[3])
    tel["$sid.speed"]     = _finite(_norm3(e.vel))
    tel["$sid.alt"]       = _finite_coord(e.pos[3])
    tel["$sid.ke_j"]      = _finite(ke)
    tel["$sid.pe_j"]      = _finite_coord(pe)                 # signed (z<0 → negative PE)
    tel["$sid.e_total_j"] = _finite_coord(etot)
    tel["$sid.de_frac"]   = _finite_coord(de)                 # (E−E₀)/E₀; ≈0 for RK4 drag-off
    tel["$sid.impacted"]  = get(c, :impacted, false)
    # AIRFRAME rotational readout (slice 16) — shipped ONLY when the missile carries airframe
    # params (the slice-15 fin-key precedent: gated so a non-airframe missile's wire is
    # byte-identical). The lesson quantities: θ (pitch), γ (flight path), α = θ−γ (angle of
    # attack — the headline; → α_trim if stable, diverges if unstable), q (pitch rate), and the
    # short-period frequency ω_sp (NaN-safe → _finite). All derived from the post-integrate
    # state, RNG-free, own keys → order-independent (the build_env! contract).
    # ⚠ THE `!== :six_dof` MIRROR GUARD (advisor): `:pitch_theta` is likewise never deleted, so after
    # a `:pitch_coupled → :six_dof` toggle it would linger and this block would ship STALE pitch-only
    # keys (`pitch_theta`/`omega_sp`/`alpha_trim`/…) on a 6-DOF wire. Gating it OFF under `:six_dof`
    # keeps the two rotational readouts mutually exclusive on the live rung. Byte-identical for slices
    # 8–22 (never `:six_dof`, so the added conjunct is always true).
    if haskey(c, :af_cma) && haskey(c, :pitch_theta) &&
       get(w.fidelity, :airframe, :point_mass) !== :six_dof
        θ  = Float64(c[:pitch_theta])
        q  = Float64(c[:pitch_q])
        γ  = atan(e.vel[3], e.vel[1])
        # SLICE 21: ρ(z) under the live rung, else the authored constant (byte-identical off).
        # The readout must use the SAME air the integrator flew, or ω_sp / a_lift / turn_radius /
        # a_induced would describe a different missile than the one on screen.
        p  = AirframeParams(Float64(c[:af_S]), Float64(c[:af_d]), Float64(c[:af_I]),
                            Float64(c[:af_cma]), Float64(c[:af_cmd]), Float64(c[:af_cmq]),
                            _airframe_rho(c, w, e.pos[3]), Float64(get(c, :af_cla, 0.0)),
                            Float64(get(c, :af_k_induced, 0.0)))   # slice 20: K (readout only here)
        tel["$sid.pitch_theta"] = _finite_coord(θ)
        tel["$sid.gamma"]       = _finite_coord(γ)
        tel["$sid.alpha"]       = _finite_coord(θ - γ)        # angle of attack (rad)
        tel["$sid.pitch_q"]     = _finite_coord(q)            # pitch rate (rad/s)
        # SLICE 22 — the nonlinear curve, or `nothing` on every prior wire. `_stall_on` already
        # requires `:pitch_coupled`, so this is `nothing` throughout the block below on a slice-16
        # `:point_mass` scenario and each else-arm is the prior code TEXTUALLY VERBATIM.
        curve = _stall_on(c, w) ? _stall_params(c) : nothing
        α_ach = θ - γ
        # ⭐ THE LOCAL-SLOPE READOUTS (advisor, and half the slice's headline). Under a BREAKING
        # moment these two must be evaluated at `∂Cm/∂α|α`, not the constant `Cma`: past `α_break`
        # the local slope is `Cma_post > 0`, so **ω_sp goes NaN AT THE MOMENT OF DEPARTURE** — the
        # readout that says *there is no longer an oscillation to have*, and the first time slice
        # 16's sentinel has ever fired mid-run in this project (F11: 0.747 s from t = 3.435). Left
        # on the constant `Cma` they would report a healthy real ω_sp and a finite trim for a
        # DEPARTED airframe — a readout describing a different missile than the one on screen,
        # which is slice 21's `_atm_on` bug class precisely. The NaN rides `_finite` → FINITE_CEIL
        # (convention 6, walked with a departure in progress at gate 3 — a genuinely untested path).
        tel["$sid.omega_sp"]    = _finite(curve === nothing ?
                                          short_period_freq(_norm3(e.vel), p) :
                                          short_period_freq_nl(_norm3(e.vel), α_ach, p, curve))
        tel["$sid.alpha_trim"]  = _finite_coord(curve === nothing ?
                                          trim_alpha(Float64(get(c, :af_delta, 0.0)), p) :
                                          trim_alpha_nl(Float64(get(c, :af_delta, 0.0)), α_ach, p, curve))
        # POST-STALL — a SEPARATELY-NAMED FLAG, deliberately NOT folded into `aero_sat` (plan §1,
        # advisor). `aero_sat` means *the α_max clamp bound*, and under this slice α_max is
        # deliberately NOT the binding limit — the physics sets the wall. Conflating them would
        # make the slice-19 flag lie about which cap is doing the work. KEY-gated (absent on every
        # prior wire), and read off the ACHIEVED α — the whole lesson lives on the achieved side.
        if curve !== nothing
            tel["$sid.post_stall"] = abs(α_ach) ≥ curve.alpha_stall ? 1.0 : 0.0
        end
        # SLICE 17 lift readout — shipped ONLY when the COUPLING is LIVE (`:airframe ===
        # :pitch_coupled`), further-gated INSIDE the af_cma block so a slice-16 `:point_mass` wire
        # stays byte-identical (lift keys must NOT appear there — the slice-15 fin-key precedent;
        # lift only physically exists when coupled). |a_lift| = the turn accel; turn radius R =
        # V²/|a_lift| (α→0 ⇒ |a_lift|→0 ⇒ R→∞ → FINITE_CEIL; the omega_sp NaN path already proves
        # `_finite` ceils the degenerate). RNG-free, own keys → order-independent.
        if get(w.fidelity, :airframe, :point_mass) === :pitch_coupled
            # SLICE 22 — the SAME `lift_coefficient` the integrator turned on (the consistency
            # discipline extended to the readout: a strip plotting a lift the missile did not make
            # is the slice-21 readout-vs-integrator bug in another costume).
            aLm = _norm3(curve === nothing ? lift_accel(e.vel, θ, mass, p) :
                                             lift_accel_nl(e.vel, θ, mass, p, curve))
            Vsp = _norm3(e.vel)
            tel["$sid.a_lift"]        = _finite(aLm)                                  # m/s² (⟂ v)
            tel["$sid.turn_radius_m"] = _finite(aLm > 0.0 ? Vsp * Vsp / aLm : FINITE_CEIL)
            # SLICE 20 — THE BILL FOR THE LIFT. Shipped ONLY when the missile carries an authored
            # `:af_k_induced` (KEY-gated) and the coupling is LIVE (RUNG-gated, inside this block) —
            # the slice-17 lift-keys / slice-15 fin-keys precedent, doubled: a slice-16/17/19 wire
            # must not grow a key (byte-identity), and induced drag only physically exists where
            # there is lift to bill for. `a_induced` is the ⟂-complement of `a_lift` — the SAME α
            # builds both, one turns the path and one eats the speed that lets you turn it.
            if haskey(c, :af_k_induced)
                tel["$sid.a_induced"] = _finite(_norm3(curve === nothing ?
                                          induced_drag_accel(e.vel, θ, mass, p) :
                                          induced_drag_accel_nl(e.vel, θ, mass, p, curve)))
            end
            # SLICE 22 — SEPARATION DRAG, the post-stall bill. Shipped alongside `a_induced` so the
            # client can show the two moving OPPOSITE ways past the peak: induced FALLS as `C_L`
            # collapses (slice 20's term, still CORRECT past stall — it is not "fixed" here) while
            # this one CLIMBS. That contrast is how the two are told apart, and it is why the
            # separation term is MANDATORY rather than optional (plan §2).
            if curve !== nothing
                tel["$sid.a_sep"] = _finite(_norm3(separation_drag_accel(e.vel, θ, mass, p, curve)))
            end
        end
    end
    # SLICE 23 — THE 6-DOF READOUT (a SEPARATE gated block, the slice-16 pitch block's 3-D twin).
    # Gated on `:att_q` — minted ONLY by `_integrate_6dof!`, so a slice-8..22 wire (no `:att_q`)
    # ships NONE of these → byte-identical (the pitch block above reads `:pitch_theta`, which a
    # 6-DOF missile never mints, so the two are mutually exclusive on a from-the-start scenario; a
    # rare live pitch_coupled→six_dof cross-toggle can leave a STALE `:pitch_theta` block alongside
    # this fresh one — finite, non-crashing, and not a showcase path). The lesson quantities: the
    # cross-range `pos_y` (the out-of-plane axis the discard cannot reach), the pitch/yaw incidences
    # α/β, the body rates (p, q, r), the attitude quaternion (4 SCALARS — convention 13, no Array —
    # for the client's 3-D nose), and the 2-plane lift magnitude / turn radius. RNG-free, own keys.
    # ⚠ RUNG-GATED, NOT merely `haskey(:att_q)` (advisor — the slice-21 `_atm_on` latent-bug class):
    # `:att_q` is minted by `_integrate_6dof!` and NEVER deleted, so after the 3-rung `:airframe`
    # cycler leaves `:six_dof` this block would keep firing on a FROZEN attitude and — being appended
    # AFTER the pitch block — OVERWRITE the fresh scalar `alpha`/`gamma`/`a_lift` with garbage from a
    # stale `att_q` (a readout describing a different missile than the one flying). Gating on the LIVE
    # rung makes it fire ONLY while `:six_dof` is actually active; `w.env` is emptied each tick so this
    # is a COMPLETE fix (no key-deletion needed). Byte-identical for slices 8–22 (they never reach
    # `:six_dof`). The pitch block above carries the mirror `!== :six_dof` guard for the same reason.
    if haskey(c, :af_cma) && haskey(c, :att_q) &&
       get(w.fidelity, :airframe, :point_mass) === :six_dof
        qa = c[:att_q]::Quat
        ω  = get(c, :omega_body, zero(Vec3))::Vec3
        γ  = atan(e.vel[3], e.vel[1])
        α, β = body_incidence(qa, e.vel)
        # Constant-ρ AirframeParams (no atmosphere on the 6-DOF path this slice — named deferral).
        p6 = AirframeParams(Float64(c[:af_S]), Float64(c[:af_d]), Float64(c[:af_I]),
                            Float64(c[:af_cma]), Float64(c[:af_cmd]), Float64(c[:af_cmq]),
                            Float64(get(c, :rho, 1.225)), Float64(get(c, :af_cla, 0.0)),
                            Float64(get(c, :af_k_induced, 0.0)))
        c_yaw6 = Float64(get(c, :af_cy_beta, p6.Cla))
        tel["$sid.pos_y"]   = _finite_coord(e.pos[2])         # the out-of-plane axis (the discard's tell)
        tel["$sid.gamma"]   = _finite_coord(γ)                # x-z flight-path angle
        tel["$sid.alpha"]   = _finite_coord(α)                # pitch incidence (rad)
        tel["$sid.beta"]    = _finite_coord(β)                # sideslip — the NEW angle this slice makes ≠ 0
        tel["$sid.omega_p"] = _finite_coord(ω[1])             # roll rate (STT holds ≈ 0)
        tel["$sid.omega_q"] = _finite_coord(ω[2])             # pitch rate
        tel["$sid.omega_r"] = _finite_coord(ω[3])             # yaw rate
        tel["$sid.att_qw"]  = _finite_coord(qa[1])            # attitude quaternion [w,x,y,z] (body→inertial)
        tel["$sid.att_qx"]  = _finite_coord(qa[2])
        tel["$sid.att_qy"]  = _finite_coord(qa[3])
        tel["$sid.att_qz"]  = _finite_coord(qa[4])
        aLm = _norm3(lift_accel_3d(e.vel, qa, mass, p6; c_yaw = c_yaw6))
        Vsp = _norm3(e.vel)
        tel["$sid.a_lift"]        = _finite(aLm)                                  # m/s² (⟂ v, 2-plane)
        tel["$sid.turn_radius_m"] = _finite(aLm > 0.0 ? Vsp * Vsp / aLm : FINITE_CEIL)
        # SLICE 24 — the BANK readouts, gated on `:bank_to_turn` (RUNG-gated, the slice-23 six_dof-block
        # precedent — so a slice-16..23 / `:skid_to_turn` wire is byte-identical; `w.env` is emptied each
        # tick, no stale key survives a cross-toggle). `bank_deg` is the client's roll indicator (STT
        # holds ≈ 0; BTT rolls to ~±90° to point its single lift plane cross-range); `phi_cmd` the command.
        if get(w.fidelity, :steering, :skid_to_turn) === :bank_to_turn
            tel["$sid.bank_deg"] = _finite_coord(rad2deg(bank_angle(qa, e.vel)))
            tel["$sid.phi_cmd"]  = _finite_coord(get(c, :phi_cmd, 0.0))
        end
    end
    return nothing
end

"""
    _airframe_view_info(w::World) -> Union{Nothing, Dict}

The slice-16 airframe VIEW HINT, shipped ONCE at handshake (the `_cfar_axis_info` /
`_esm_axis_info` precedent — a static, scenario-derived marker the client discriminates its
view on, NOT a per-frame quantity). Returns `nothing` unless some `:missile` entity carries
airframe params (`:af_cma`), in which case it ships `airframe_view => true` and the target id.

This is the Option-P′ resolution (advisor): slice 16 gates the rotational integrator on
PARAMS-PRESENCE, not a `:airframe` fidelity rung — the trajectory is byte-identical across a
Cmα flip (rotation is isolated from translation this slice), so a `point_mass|6dof` fidelity
would name a path effect it cannot produce until slice-17's α→lift coupling (the convention-4c
false-fidelity / dead-knob trap). The lesson lever is the LIVE `af_cma` KNOB (a slider, not a
button); this marker only lets the client recognize the airframe view and drop the fidelity
button (nothing to cycle) — the `range_axis_m`→cfar handshake-key mechanism, no new fidelity.
"""
function _airframe_view_info(w::World)
    missiles = sort!(Symbol[id for (id, e) in w.entities
                            if e.kind === :missile && haskey(e.comp, :af_cma)])
    isempty(missiles) && return nothing
    # SLICE 23 — the 3-D-airframe DISCRIMINATOR (the terrain_grid / range_axis_m precedent). A missile
    # carrying an authored `:af_cy_beta` (the 6-DOF-only key — key-gated at load, so slices 16–22 never
    # have it) declares 6-DOF intent: the client upgrades the 2-D airframe overlay to the terrain-style
    # 3-D view (the out-of-plane trail) and the `:airframe` cycler to the 3-ring point_mass ↔
    # pitch_coupled ↔ six_dof. `false`/absent on every slice-16..22 wire ⇒ they keep the 2-D view.
    info = Dict{Symbol,Any}(:airframe_view => true, :airframe_target => String(missiles[1]))
    any(haskey(w.entities[m].comp, :af_cy_beta) for m in missiles) && (info[:airframe_6dof] = true)
    # SLICE 26 — the RADOME marker, and its job is to make the client DROP the shared fidelity
    # button (Option-P′ again — slice 16's own resolution, and slice 16 is the right analogue: a
    # live knob spanning a stability boundary, with no button at all).
    #
    # ⚠ THE SLICE-20 PRECEDENT DELIBERATELY DOES NOT TRANSFER (advisor). Slice 20 kept the inherited
    # cycler because its other position (`:point_mass`) makes induced drag INERT — nothing false is
    # displayed. A radome wire is a two-angle host, so the inherited cycler would be slice 25's
    # `seeker_axes`, and its other position (`:pitch_plane`) leaves the radome LIVE AND REFRACTING on
    # a missile that ALSO misses by 2000 m for a wholly unrelated reason. Two mechanisms compounding
    # in one view is exactly what convention 9 exists to prevent — and it is the "identical
    # signature, different mechanism" trap slice 25 spent a section on. So: no button, one slider.
    any(haskey(w.entities[m].comp, :radome_slope) for m in missiles) && (info[:radome_view] = true)
    return info
end

# --- the MANEUVERING TARGET: a curving phase-1 mover (slice 12, HANDOFF §10 item 10) ----------
# The maneuvering FOIL for the augmented-PN lesson. ConstantVelocity (radar.jl) flies a straight
# line; ManeuveringTarget applies a CONSTANT lateral acceleration ⟂ its velocity (a coordinated,
# speed-preserving g-turn IN THE x-z PLANE), so the target CURVES — the thing plain PN can't lead.
# Against it plain PN lags by the target-accel term and, under a binding g-limit, SATURATES → misses;
# APN's `(N/2)·a_T⊥` feedforward (Autopilot.decide!'s `:apn` branch above) anticipates the maneuver →
# low demand → intercept (HANDOFF §10 item 10: "g-limit saturation modeled — this is why augmented
# PN matters").
#
# REUSES `integrator_step(:rk4, ...)` (dynamics.jl) — the SAME stepper the missile flies — with an
# `a_lat·perp(v)` closure, but SELF-CONTAINED: it ALWAYS steps `:rk4`, NOT coupled to the missile's
# `:integrator` fidelity (else the target's path would move when the MISSILE's integrator toggles —
# a cross-lesson leak). A ⟂-v turn is speed-preserving; RK4 holds the speed to machine eps over the
# flight (probe: −2.7e-12 m/s drift over 8 s), so target-integration error ≪ the guidance lag.
#
# DETERMINISM (the slice-8/10 shape — NOT slice-11's): NO RNG (truth kinematics), so "draw-count
# invariance" is VACUOUS. Introduce-safe: a plain `:target` gets `ConstantVelocity` (byte-identical) —
# only a `maneuver:` block swaps in ManeuveringTarget. GRAVITY-FREE / kinematic (it feels ONLY its
# commanded `a_T`, not `−g` — the ConstantVelocity lineage; the missile's own gravity leaves a small
# honest `:apn` residual — gravity-comp PN is DEFERRED, HANDOFF §10 / convention 9).
#
# NAMED APPROXIMATIONS (HANDOFF §1): a CONSTANT lateral accel (no jink/weave program — a later
# fidelity step); planar in x-z (the elevation view's plane, no cross-range — the slice-10 precedent);
# and — the one the AERO ARC makes load-bearing — **the target is AERODYNAMICALLY FREE**. It has no
# mass, no Q, no C_Lα, no α, no attitude, no drag of any kind: `a_lat` is DELIVERED BY FIAT, the turn
# is speed-preserving to machine eps, and NOTHING caps it. So the target has no `a_max_aero` ceiling
# (slice 19), pays no induced-drag bill for its turn (slice 20), and never feels ρ(z) (slice 21) —
# it is the missile-side plant of slices 15–21 with EVERY constraint removed. This is DELIBERATE and
# it is what licenses slice 20's headline ("the target does NOT maneuver: the missile pays for its
# OWN turn onto the collision course") and the convention-9 isolation generally — an aerodynamically
# constrained target would make an aero miss PARTLY the target's problem, muddying every ceiling
# lesson in the arc. DEFERRED (HANDOFF §11 Tier-A): giving the target its own aero ceiling + energy
# bleed, so a defensive turn COSTS it — a real lesson, but its own slice, and NOT inside this one.

# The coordinated-turn lateral accel: `a_lat·sign` along the in-plane (x-z) unit ⟂ to v (v̂ rotated
# +90° in x-z: `(vx,vz) → (−vz,vx)`). At v→0 (or a purely-vertical v) the in-plane speed vanishes →
# zero accel (no NaN — the pursuit/frames zero-guard house style). Shared by the RK4 step AND the
# truth `a_T` publish so they agree by construction.
function _lateral_accel(v::Vec3, a_lat::Float64, sign::Float64)
    vx, vz = v[1], v[3]
    s = sqrt(vx * vx + vz * vz)
    s < _FRAME_EPS && return zero(Vec3)
    return (a_lat * sign / s) * Vec3(-vz, 0.0, vx)
end

"""
    ManeuveringTarget(id)

Advances entity `id` on a CONSTANT-lateral-accel coordinated g-turn in the x-z plane — the curving
maneuvering foil for the augmented-PN lesson (slice 12), the accelerating sibling of
[`ConstantVelocity`](@ref). Each physics step it solves `(ṗ, v̇) = (v, a_lat·perp(v))` via
`integrator_step(:rk4, …)` (dynamics.jl — the same stepper the missile flies, but ALWAYS `:rk4`, NOT
coupled to the missile's `:integrator`), advancing `(pos, vel)`. It owns pos/vel advancement, so the
loader gives a maneuvering `:target` `[ManeuveringTarget]` and **NOT** `ConstantVelocity` (two phase-1
movers would double-integrate). A ⟂-v turn is speed-preserving (RK4 holds it to machine eps).

Config in the entity `comp` bag, read with DEFAULTS so a bare/live config can't crash a tick:
`:a_lat_mps2` (lateral accel magnitude, m/s²; `0` → straight-line, the APN feedforward vanishes) and
`:turn_sign` (`±1`, the turn direction; default `+1`). Writes `comp[:a_target]::Vec3` — the TRUTH
target accel THIS tick (from the post-step velocity) — which the missile's phase-4 `:apn` `decide!`
reads for the feedforward (phase-1 write < phase-4 read; comp survives `empty!(w.env)`). GRAVITY-FREE
(feels only `a_T` — the ConstantVelocity lineage; § gravity handling above).
"""
struct ManeuveringTarget <: Subsystem
    id::Symbol
end

function integrate!(mt::ManeuveringTarget, w::World, dt::Float64)
    e     = w.entities[mt.id]
    c     = e.comp
    a_lat = Float64(get(c, :a_lat_mps2, 0.0))
    tsign = Float64(get(c, :turn_sign, 1.0))
    p′, v′ = integrator_step(:rk4, v -> _lateral_accel(v, a_lat, tsign), e.pos, e.vel, dt)
    e.pos = p′
    e.vel = v′
    # The TRUTH target accel THIS tick, from the POST-step velocity (matches what the phase-4 `:apn`
    # decide! consumes). `a_lat = 0` → zero → the APN feedforward vanishes (`:apn`-on-CV ≈ `:pn`).
    c[:a_target] = _lateral_accel(v′, a_lat, tsign)
    return nothing
end

# --- the GUIDED missile: the Autopilot subsystem (slice 9, HANDOFF §10 item 9) ----------------
# The missile's FIRST `decide!` (phase 4 — the phase slice 5 lit for the DF Geolocator): "a missile
# is integrate! (airframe) + observe! (seeker) + decide! (guidance)" (HANDOFF §3). The Autopilot
# runs the CASCADE — an OUTER pursuit law (the honest tail-chaser stand-in slice 10 replaces with
# PN) commanding a lateral accel, closed by an INNER PID autopilot through a first-order airframe
# lag — and writes `comp[:a_ctrl]` for the NEXT tick's BallisticMissile.integrate! (the guidance
# seam above). The airframe (impact/energy/attitude) is REUSED verbatim: a guided missile keeps
# `[BallisticMissile, Autopilot]` (phase-1 mover + phase-4 guidance), NOT a duplicating
# GuidedMissile. `pursuit_accel`/`autopilot_step` (the pure guidance.jl kernel) are the only physics.
#
# DETERMINISM (the slice-8 discipline — do NOT copy the slice-5/6/7 template): there is NO RNG in
# the missile arc, so "RNG lockstep" is VACUOUS. `:autopilot` is introduce-safe (absent an Autopilot
# nothing reads it → any slice-1..8 scenario byte-identical) but PHYSICS-CHANGING (a :ideal↔:pid
# toggle CHANGES the trajectory — the not-a-dead-knob property, the OPPOSITE of slices 5/6/7).
#
# NAMED APPROXIMATIONS (HANDOFF §1; the guidance-law ones live in guidance.jl): guidance reads
# TARGET TRUTH (no seeker — slice 11); the one-tick decide!→integrate! delay (tick 1 is ballistic —
# a free byte-identity anchor; the 1 ms control lag is negligible at guidance rate).
struct Autopilot <: Subsystem
    id::Symbol
end

# Phase 1: capture the tick `dt` into comp. `decide!` (phase 4) has NO dt argument, but the PID
# integrates at the tick dt (fixed-step). This is the ONLY reason the Autopilot touches phase 1 —
# it does NOT move the entity (BallisticMissile owns pos/vel). Keeping the capture HERE (not in
# BallisticMissile.integrate!) means a BALLISTIC slice-8 missile — which has no Autopilot — gets NO
# new comp key, so its determinism fingerprints stay byte-identical.
function integrate!(a::Autopilot, w::World, dt::Float64)
    w.entities[a.id].comp[:dt_s] = dt
    return nothing
end

# Phase 4: the closed guidance loop. Reads the missile + its nearest `:target` (`_nearest_target`,
# reused from radar.jl — truth-fed, no seeker), computes the OUTER pursuit command, runs the INNER
# PID (dispatch on `:autopilot`), clamps to `a_max`, and writes `comp[:a_ctrl]` (next tick) + the
# PID state. The readout goes into `w.env[:telemetry]` HERE — unlike the slice-8 energy readout
# (which had to move to build_env! because `empty!(w.env)` wipes phase-1 writes), a decide! write
# is AFTER the single empty! (tick contract), so it survives. The lesson is `track_gap` (commanded
# vs achieved), where the `1/(1+Kp)` undershoot is directly visible, NOT miss distance (advisor).
function decide!(a::Autopilot, w::World)
    e   = w.entities[a.id]
    c   = e.comp
    sid = String(a.id)
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    tgt = _nearest_target(w, e)

    # SLICE 30 — THE ENGAGEMENT AXIS, labelled. The crossing speed the `ConstantVelocity` mover is
    # pinned to (radar.jl `integrate!`) is what sets the sustained lead angle the seeker holds, hence
    # WHERE ON THE GLASS slice 28's slope curve is sampled, hence the residual that closes slice 26's
    # loop — so the HUD must be able to say which engagement is being flown, not just what the radome
    # believes. Published HERE, in the block that already owns engagement geometry (`los_range`,
    # `closing_speed`, `range_rate`) rather than in the seeker's readout: a target's crossing speed is
    # not a sensor quantity, and siting it there would needlessly couple it to the `:seeker_axes`
    # host (advisor).
    #
    # ⚠ PRESENCE-gated on the TARGET's own comp key, and it ships the KNOB VALUE — never `tgt.vel[2]`,
    # which would grow a key on every prior wire (slices 1–29 byte-identical) and would read the
    # authored velocity on a target that carries no pin. Placed ABOVE the no-target early return so
    # both arms ship it once: unlike the never-stale ZEROS below, this one does not go stale
    # post-impact — the target keeps crossing at the speed the knob says.
    # ⚠ SIGNED ⇒ `_finite_coord`: a negative crossing flies the MIRROR engagement, which is exactly
    # the sign the loader deliberately declines to forbid.
    if tgt !== nothing && haskey(tgt.comp, :cross_speed_mps)
        tel["$sid.cross_speed_mps"] = _finite_coord(Float64(tgt.comp[:cross_speed_mps]))
    end

    # No target (misconfigured — load validates ≥1) or already impacted (engagement over): no
    # command, coast/frozen. Publish zero/finite telemetry so the readout never blanks.
    if tgt === nothing || get(c, :impacted, false)
        tel["$sid.a_cmd"]         = 0.0
        tel["$sid.a_ach"]         = 0.0
        tel["$sid.track_gap"]     = 0.0
        tel["$sid.los_range"]     = _finite(tgt === nothing ? 0.0 : los_range(e.pos, tgt.pos))
        tel["$sid.range_rate"]    = 0.0
        tel["$sid.a_demand"]      = 0.0                        # slice-10 keys — never stale
        tel["$sid.saturated"]     = 0.0
        tel["$sid.los_rate"]      = 0.0
        tel["$sid.closing_speed"] = 0.0
        # Slice-14 salvo keys — never stale (gated on a coordinator being present, so a slice-9..13
        # scenario without one ships NO new key → byte-identical). Zeroed post-impact / no-target.
        if haskey(w.env, :salvo_t_d)
            tel["$sid.t_go"]            = 0.0
            tel["$sid.impact_time_err"] = 0.0
        end
        # Slice-15 fin keys — never stale (gated on `:autopilot === :fin`, so a slice-1..14 / non-fin
        # scenario ships NONE → byte-identical). Zeroed post-impact / no-target (the missile is frozen).
        if get(w.fidelity, :autopilot, :ideal) === :fin
            tel["$sid.fin_defl"]     = 0.0
            tel["$sid.fin_rate"]     = 0.0
            tel["$sid.fin_rate_sat"] = 0.0
            tel["$sid.fin_defl_sat"] = 0.0
            tel["$sid.g_onset"]      = 0.0
        end
        # Slice-19 α/g keys — never stale (gated on `:autopilot === :alpha` + airframe params, the
        # SAME condition as the readout below, so a slice-1..18 / non-alpha scenario ships NONE →
        # byte-identical). Zeroed post-impact / no-target — and honestly so: the missile is frozen
        # (v = 0), so `q_dyn = ½ρV²` and the ceiling `a_max_aero ∝ V²` genuinely ARE zero.
        if get(w.fidelity, :autopilot, :ideal) === :alpha && haskey(c, :af_cma)
            tel["$sid.alpha_cmd"]  = 0.0
            tel["$sid.delta_cmd"]  = 0.0
            tel["$sid.a_max_aero"] = 0.0
            tel["$sid.q_dyn"]      = 0.0
            tel["$sid.aero_sat"]   = 0.0
            tel["$sid.defl_sat"]   = 0.0
            # Slice-23 yaw keys — the same never-stale discipline, gated on `:six_dof` so a
            # `:pitch_coupled` `:alpha` scenario (slices 19–22) ships NONE → byte-identical.
            if get(w.fidelity, :airframe, :point_mass) === :six_dof
                tel["$sid.beta_cmd"]  = 0.0
                tel["$sid.delta_yaw"] = 0.0
            end
        end
        return nothing
    end

    mode   = get(w.fidelity, :autopilot, :ideal)
    guid   = get(w.fidelity, :guidance, :pursuit)             # slice-10 OUTER law; DEFAULT :pursuit
    coop   = get(w.fidelity, :cooperation, :solo)             # slice-14 cooperation modifier; DEFAULT :solo
    k_it   = max(Float64(get(c, :k_it, 0.45)), 0.0)           # ITC gain (clamp-at-consumer: ≥0, no sign flip)
    k_guid = Float64(get(c, :k_guid, 3.0))
    n_pn   = Float64(get(c, :n_pn, 4.0))                       # PN navigation constant (:pn only)
    r_stop = Float64(get(c, :r_stop, 0.0))                     # §2 endgame cutoff; DEFAULT 0 = no-op
    kp     = Float64(get(c, :kp, 2.0))
    ki     = Float64(get(c, :ki, 0.0))
    kd     = Float64(get(c, :kd, 0.0))
    tau    = Float64(get(c, :tau, 0.3))
    a_max  = Float64(get(c, :a_max, 3000.0))
    dt     = Float64(get(c, :dt_s, 1.0e-3))

    # Relative kinematics (TRUTH) — the seeker ω-source branch reads truth `Vc` from these (§ scope:
    # only the LOS ANGLE is noisy) and the telemetry below reuses them. Hoisted here from the old
    # inline telemetry site so the branch can read `Vc`; the truth `pn_accel` path is UNTOUCHED (it
    # computes its own r/v internally), so slice-10 stays byte-identical.
    rel_pos = tgt.pos - e.pos
    rel_vel = tgt.vel - e.vel

    # OUTER law → commanded lateral accel (§3 seam, slice 10 — the INNER PID below is UNCHANGED).
    # Select on `:guidance` (default `:pursuit` = the exact slice-9 path → byte-identical): PN leads
    # (nulls λ̇), pursuit tail-chases. The §2 terminal cutoff coasts the missile through the r→0
    # endgame (r_stop=0 default is an EXACT no-op → slice-9 unaffected); then clamp to a_max. In
    # slice10_pn a_max is generous (never binds); in slice10_glimit it BINDS ON PURPOSE — g-limit
    # saturation is the lesson, the deliberate inversion of slice 9's crash-guard-only clamp.
    #
    # SLICE-11 SEEKER SEAM: if the phase-3 `Seeker.observe!` wrote an estimate THIS tick
    # (`haskey(c, :seeker_omega)` — observe! ran before this phase-4 decide!), PN reads the seeker's
    # ω_est/û_est via `pn_accel_from_omega(û, ω, Vc)` (with TRUTH `Vc` — § scope) INSTEAD of truth
    # pos/vel. The `pn_accel_from_omega` arg order is û FIRST, ω SECOND (it computes `_cross(ω, û)` —
    # a swap would flip the command sign). Byte-identity for slices 1–10: with NO Seeker there is no
    # `:seeker_omega`, so this branch is never taken → the exact slice-10 truth `pn_accel`. The seeker
    # only overrides PN's ω-SOURCE, so it is gated on `guid === :pn` (pursuit reads the LOS directly,
    # no ω) — keeping `:seeker`/`:guidance`/`:autopilot` orthogonal.
    # SLICE-12 APN SEAM: `:apn` = TPN + a `(N/2)·a_T⊥` feedforward on the TARGET's truth accel
    # (`tgt.comp[:a_target]`, written this tick by the phase-1 `ManeuveringTarget` mover; phase-1 <
    # phase-4, and comp survives `empty!(w.env)`). Against a maneuvering target plain PN saturates
    # under the g-limit and misses; APN anticipates the maneuver → low demand → intercept (HANDOFF
    # §10 item 10). Reads TRUTH û/ω/Vc (the exact `:pn` truth path) — no seeker (slice-12 scenarios
    # carry none; the `:seeker_omega` branch stays `:pn`-gated). `get(...,:a_target, zero(Vec3))`
    # defaults to zero on a CV target → the feedforward vanishes → `:apn` ≈ `:pn`. The fetch +
    # feedforward live INSIDE this branch so the `:pn`/`:pursuit`/seeker paths are TEXTUALLY
    # unchanged → slices 1–11 byte-identical.
    # SLICE-14 SALVO SEAM: cooperative impact-time-control guidance (the capstone). Gated on
    # `coop === :salvo && haskey(w.env, :salvo_t_d)` — UNREACHABLE without BOTH the `:cooperation`
    # rung AND the `SalvoCoordinator` (which alone writes `salvo_t_d`, in phase-2 build_env!). So a
    # slice-1..13 scenario (no `:cooperation` key → `coop === :solo`; no coordinator → no field)
    # NEVER takes this arm → falls through to the EXACT prior arithmetic below, textually unchanged
    # → byte-identical. `impact_time_control_accel` = PN base + a ⟂-LOS impact-time-error feedback
    # that STRETCHES an EARLY missile toward the shared desired remaining time `w.env[:salvo_t_d]`
    # (`= T_d − w.t`, the fixed-at-launch consensus). Reads TRUTH target pos/vel (no seeker — slice-14
    # is truth-fed PN, the cooperation lesson isolated as slice 12 isolated APN; the `:seeker_omega`
    # branch stays below it and slice-14 scenarios carry no Seeker). The fetch + call live INSIDE this
    # branch (the slice-12 `a_T`-fetch-inside-the-branch bit trap).
    a_dem = if guid === :pn && coop === :salvo && haskey(w.env, :salvo_t_d)
                impact_time_control_accel(e.pos, e.vel, tgt.pos, tgt.vel,
                                          Float64(w.env[:salvo_t_d]); N = n_pn, K_it = k_it)
            elseif guid === :pn && haskey(c, :seeker_omega)
                pn_accel_from_omega(c[:seeker_los]::Vec3, c[:seeker_omega]::Vec3,
                                    -range_rate(rel_pos, rel_vel); N = n_pn)
            elseif guid === :pn
                pn_accel(e.pos, e.vel, tgt.pos, tgt.vel; N = n_pn)
            elseif guid === :apn
                pn_accel_augmented(los_unit(e.pos, tgt.pos), los_rate(rel_pos, rel_vel),
                                   -range_rate(rel_pos, rel_vel),
                                   get(tgt.comp, :a_target, zero(Vec3))::Vec3; N = n_pn)
            else
                pursuit_accel(e.pos, e.vel, tgt.pos; k_guid = k_guid)
            end
    a_dem = _terminal_cutoff(a_dem, los_range(e.pos, tgt.pos), r_stop)
    a_cmd = clamp_accel(a_dem, a_max)

    # INNER PID autopilot → achieved accel (dispatch on the fidelity rung).
    state      = get(c, :ap_state, autopilot_init())::AutopilotState
    a_ach_prev = state.a_ach                                   # slice-15 g-onset readout (pre-step a_ach)
    fin_diag   = nothing                                       # slice-15 fin telemetry (set only when :fin)
    alpha_diag = nothing                                       # slice-19 α/g telemetry (set only when :alpha)
    sixdof_diag = nothing                                      # slice-23 2-plane yaw telemetry (set only when :six_dof)
    alpha_coupled = false                                      # slice-19: true ⇒ the plant flies δ, NOT :a_ctrl
    alpha_6dof    = false                                      # slice-23: true ⇒ the 6-DOF plant flies (δp,δy), NOT :a_ctrl
    # SLICE-19 α/g SEAM (§11 Tier A) — THE INNER LOOP: `a_cmd → α_cmd → δ`. The outer law's command is
    # INVERTED THROUGH THE AERO (airframe.jl `alpha_command`) into an angle-of-attack command and thence
    # a fin deflection (`alpha_autopilot_delta`), so the missile flies its own PN command *through the
    # airframe* rather than by fiat. Gated on `mode === :alpha` — UNREACHABLE for a slice-1..18 scenario
    # (`get(w.fidelity,:autopilot,:ideal)` never returns `:alpha`) → the `:fin`/`else` arms below are the
    # slice-9/10/12/15 arithmetic TEXTUALLY UNCHANGED → byte-identical. Like `:fin` it NEVER routes
    # through `autopilot_step` (its kernels live in airframe.jl). Every param is fetched INSIDE the
    # branch (the slice-12/15 fetch-in-branch bit trap) and floored/defaulted at the consumer (a live
    # slider can't crash a tick — convention 5; the AUTHORED values are LOAD-validated).
    #
    # THE CROSS-FIDELITY DEPENDENCY — THE FIRST IN THE SUITE (guidance.jl `AUTOPILOT_MODES` states it
    # in full): the α loop needs a ROTATIONAL PLANT to fly. With one (`:airframe === :pitch_coupled`
    # AND airframe params) it commands the fin δ and the maneuver accel is MADE BY LIFT, ceilinged at
    # `a_max_aero = Q·S·C_Lα·α_max/m` — THE LESSON. Without one the α command has nothing to actuate,
    # so it degenerates to `:ideal`'s fiat `a_ctrl` capped only by the authored `a_max` — the REFERENCE
    # ARM that HITS. `:airframe` is therefore the ONE toggled fidelity of the showcase (convention 9),
    # with the autopilot AUTHORED at `:alpha`.
    if mode === :alpha
        has_af        = haskey(c, :af_cma)
        alpha_coupled = has_af && get(w.fidelity, :airframe, :point_mass) === :pitch_coupled
        # SLICE 23 — the SAME `:alpha` autopilot inverting its command through the 6-DOF plant. The
        # cross-fidelity dependency (slice 19's, extended): `:alpha` under `:six_dof` steers in TWO
        # body planes (α pitch + β yaw) so the ⟂-v command keeps its FULL 3-D direction — the discard
        # dies. `:pitch_coupled` (scalar, discards y) and `:point_mass` (fiat) are unchanged below.
        alpha_6dof    = has_af && get(w.fidelity, :airframe, :point_mass) === :six_dof
        if has_af
            mass_af = max(Float64(get(c, :mass_kg, 1.0)), _MISSILE_MASS_FLOOR)
            # SLICE 21 — ρ(z) under the live `:atmosphere` rung, else slice-19/20's authored
            # constant (the identical expression when gated off ⇒ byte-identical). THIS IS THE
            # LESSON'S SITE: `a_max_aero = Q·S·C_Lα·α_max/m` with `Q = ½·ρ(z)·V²`, so the ceiling
            # the α inversion clamps against now FALLS AS THE MISSILE CLIMBS. Slice 19 moved this
            # ceiling with the `rho` KNOB (an engineer dialling a flight condition) and slice 20
            # made the missile lower it BY TURNING (V bleed); here the missile lowers it BY
            # CLIMBING — and unlike slice 20's, this one factorizes EXACTLY: the ceiling ratio is
            # identically [ρ(z)/ρ(z₀)]·[V/V₀]², so ALTITUDE and SPEED separate with no residual
            # (gate-0 F6, verified to 1.4e-17). ρ(z) is read at the CURRENT height — phase 4 runs
            # after phase 1, so `e.pos` is this tick's post-integrate state, the same one
            # `build_env!` ships.
            rho_af  = _airframe_rho(c, w, e.pos[3])
            # α_max IS the lesson's ceiling (the α_cmd clamp is `a_max_aero` expressed in code). The
            # AirframeParams construction is DUPLICATED from `_integrate_coupled!`/`build_env!` rather
            # than factored into a shared helper — "duplicate, don't share" (the `fin_autopilot_step`
            # precedent) keeps those frozen paths textually untouched.
            alpha_max = max(Float64(get(c, :af_alpha_max, 0.2)), _FRAME_EPS)
            p_af = AirframeParams(Float64(c[:af_S]), Float64(c[:af_d]), Float64(c[:af_I]),
                                  Float64(c[:af_cma]), Float64(c[:af_cmd]), Float64(c[:af_cmq]),
                                  rho_af, Float64(get(c, :af_cla, 0.0)))
            V_af  = _norm3(e.vel)
            # THE HEADLINE READOUT — computed under BOTH arms (see the telemetry note below): the
            # ceiling is a FLIGHT-CONDITION PROPERTY of the airframe, true whichever plant is active.
            # SLICE 22 — under an authored stall the ceiling is the lift curve's INTERIOR PEAK, not
            # its linear extrapolation to the clamp (`aero_accel_limit`'s `curve` arm). `_stall_on`
            # requires `:pitch_coupled`, so the `:point_mass` REFERENCE ARM still reports the LINEAR
            # ceiling (advisor) — the same coherence slice 21 chose for ρ₀: that plant makes its
            # accel by fiat on a linear-aero model, and the readout must describe the missile that
            # is actually flying. ⚠ The α_stall/α_max headline identity is a SAME-INPUTS FORMULA
            # tooth in the tests, NEVER a comparison of these two live arms — separation drag makes
            # V (hence Q) diverge between them, so a run-vs-run would confound itself (plan §3).
            curve_af   = _stall_on(c, w) ? _stall_params(c) : nothing
            a_max_aero = aero_accel_limit(V_af, mass_af, p_af; alpha_max = alpha_max,
                                          curve = curve_af)
            q_dyn      = 0.5 * rho_af * V_af^2
            if alpha_coupled
                # k_α/k_q are AUTHORED CONSTANTS and MUST NEVER BE KNOBS (gate-0 FINDING 14): the α_max
                # clamp bounds the COMMAND while lift uses the ACHIEVED α, so a hot loop overshoots the
                # clamp and the ceiling LEAKS (at k_α=100 the miss collapses 295→63 m and the fin goes
                # bang-bang). NEVER declare a `knobs:` entry targeting `:k_alpha`/`:k_q`. δ_max is
                # slice-15's DEFLECTION cap REUSED (the same airframe's fin limit in rad; `:alpha` and
                # `:fin` never co-run) — the FOURTH cap in this plant, pinned NON-binding (`defl_sat == 0`)
                # so α_max is PROVABLY the one that binds.
                k_alpha   = Float64(get(c, :k_alpha, 1.0))
                k_q       = Float64(get(c, :k_q, 0.3))
                delta_max = max(Float64(get(c, :delta_max, 0.5)), _FRAME_EPS)
                # The ACHIEVED α = θ−γ from the POST-integrate state (phase 1 < phase 4 — the SAME state
                # `build_env!` ships as `<sid>.alpha`, which is why no `alpha_ach` key is duplicated here).
                # `:pitch_theta` is created by `_integrate_coupled!`'s lazy launch init on tick 1, so it
                # exists by the first decide!; the `get` default (θ = γ ⇒ α = 0) is belt-and-braces.
                γ_af  = atan(e.vel[3], e.vel[1])
                θ_af  = Float64(get(c, :pitch_theta, γ_af))
                α_cmd, aero_sat = alpha_command(a_cmd, e.vel, mass_af, p_af; alpha_max = alpha_max)
                δ_cmd, defl_sat = alpha_autopilot_delta(α_cmd, θ_af - γ_af,
                                                        Float64(get(c, :pitch_q, 0.0)), p_af;
                                                        k_alpha = k_alpha, k_q = k_q,
                                                        delta_max = delta_max)
                # THE δ SEAM (the `:a_ctrl` pattern reused): this phase-4 decide! writes the commanded
                # deflection; the NEXT tick's phase-1 `_integrate_coupled!` reads it — the SAME one-tick
                # delay as `:a_ctrl`. Absent the key it reads slice-17's authored `af_delta` trim, so a
                # slice-17 OPEN-LOOP scenario (no Autopilot → no write) stays bit-identical BY
                # CONSTRUCTION. Tick 1 is likewise flown on `af_delta` (integrate! precedes the first
                # decide!) — author `af_delta: 0` so tick 1 injects no transient.
                c[:delta_cmd] = δ_cmd
                # THE ACHIEVED CONTROL ACCEL IS THE LIFT — that IS the whole content of `a_max_aero`: a
                # coupled airframe can only make its maneuver accel aerodynamically. Threading it into
                # the LOCAL `a_ctrl` keeps the slice-9 `a_ach`/`track_gap` keys HONEST (under a binding
                # ceiling they show the airframe FAILING TO DELIVER, where `a_cmd` would claim perfect
                # tracking). It is NOT persisted to comp — see the store guard below (finding 1).
                # SLICE 22 — the achieved accel is the lift the NONLINEAR curve actually made. Left
                # on the linear twin, `a_ach`/`track_gap` would credit the airframe with lift it did
                # not produce past the stall — the exact dishonesty this key exists to prevent.
                a_ctrl     = curve_af === nothing ? lift_accel(e.vel, θ_af, mass_af, p_af) :
                                                    lift_accel_nl(e.vel, θ_af, mass_af, p_af, curve_af)
                alpha_diag = (alpha_cmd = α_cmd, delta_cmd = δ_cmd, aero_sat = aero_sat,
                              defl_sat = defl_sat, a_max_aero = a_max_aero, q_dyn = q_dyn,
                              rho_air = rho_af)
            elseif alpha_6dof
                # SLICE 23 — THE 2-PLANE STT INVERSION (the discard dies). The guidance command
                # `a_cmd` is a FULL 3-D Vec3 (`pn_accel`'s natural out-of-plane component survives
                # `clamp_accel`, which scales magnitude); `steering_command` (airframe3d.jl) resolves
                # it onto the two body ⟂-v axes and inverts each through the aero — the SAME scalar
                # `alpha_command` inversion, twice, with NO projection-and-throw-away. The ceiling is
                # the RESULTANT clamp `hypot(α,β) ≤ α_max` (gate-0 P4): STT REPOINTS the pitch-plane
                # authority in 3-D, it does not get more of it, so `a_max_aero`/`q_dyn` above are the
                # SAME single-axis values and `aero_sat` is the resultant tell. k_α/k_q/δ_max are the
                # slice-19 gains REUSED (NEVER knobs — FINDING 14); C_Yβ defaults to C_Lα (symmetric
                # cruciform). δ_max is pinned NON-binding (`defl_sat == 0`, now BOTH fins) so the
                # resultant α_max is provably the cap that binds.
                k_alpha   = Float64(get(c, :k_alpha, 1.0))
                k_q       = Float64(get(c, :k_q, 0.3))
                delta_max = max(Float64(get(c, :delta_max, 0.5)), _FRAME_EPS)
                c_yaw_af  = Float64(get(c, :af_cy_beta, p_af.Cla))
                # The ACHIEVED (α, β) and body rate from the POST-integrate 6-DOF state (phase 1 <
                # phase 4 — the SAME `:att_q`/`:omega_body` `build_env!` ships). `:att_q` is minted by
                # `_integrate_6dof!`'s lazy init on tick 1, so it exists by the first decide!; the
                # `get` default (velocity-aligned ⇒ α = β = 0) is belt-and-braces.
                q_att = get(c, :att_q,
                            quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), e.vel))::Quat
                ω_bod = get(c, :omega_body, zero(Vec3))::Vec3
                α_ach, β_ach = body_incidence(q_att, e.vel)
                # SLICE 24 — the STEERING law. `:bank_to_turn` makes lift in ONE plane (α only) and
                # BANKS to point it: `steering_bank_command` returns the bank command `φ_cmd` (→ the
                # roll autopilot in next tick's `_integrate_6dof!`, the `:delta_cmd` seam's sibling) and
                # the SIGNED single-plane α; the yaw channel drives β → 0 (COORDINATED flight, NOT "STT
                # minus β" — plan §2). Default `:skid_to_turn` ⇒ the slice-23 STT inversion VERBATIM
                # (β COMMANDED in two planes). `:steering` is inert without `:six_dof` (this arm).
                if get(w.fidelity, :steering, :skid_to_turn) === :bank_to_turn
                    φ_cmd, α_cmd, aero_sat = steering_bank_command(a_cmd, e.vel, q_att, mass_af, p_af;
                                                                   alpha_max = alpha_max)
                    β_cmd = 0.0
                    c[:phi_cmd] = φ_cmd
                    δp_cmd, defl_p = alpha_autopilot_delta(α_cmd, α_ach, pitch_rate_phys(ω_bod), p_af;
                                                           k_alpha = k_alpha, k_q = k_q,
                                                           delta_max = delta_max)
                    δy_cmd, defl_y = alpha_autopilot_delta(0.0, β_ach, yaw_rate_phys(ω_bod), p_af;
                                                           k_alpha = k_alpha, k_q = k_q,
                                                           delta_max = delta_max)
                else
                    α_cmd, β_cmd, aero_sat = steering_command(a_cmd, e.vel, q_att, mass_af, p_af;
                                                              alpha_max = alpha_max, c_yaw = c_yaw_af)
                    δp_cmd, defl_p = alpha_autopilot_delta(α_cmd, α_ach, pitch_rate_phys(ω_bod), p_af;
                                                           k_alpha = k_alpha, k_q = k_q,
                                                           delta_max = delta_max)
                    δy_cmd, defl_y = alpha_autopilot_delta(β_cmd, β_ach, yaw_rate_phys(ω_bod), p_af;
                                                           k_alpha = k_alpha, k_q = k_q,
                                                           delta_max = delta_max)
                end
                # THE 2-CHANNEL δ SEAM: BOTH fins written for next tick's `_integrate_6dof!` (the
                # slice-19 `:delta_cmd` pattern, doubled). Tick 1 flies `af_delta`/0 (integrate!
                # precedes the first decide!) — author `af_delta: 0` so tick 1 injects no transient.
                c[:delta_cmd]     = δp_cmd
                c[:delta_yaw_cmd] = δy_cmd
                # THE ACHIEVED CONTROL ACCEL IS THE 2-PLANE LIFT — keeps `a_ach`/`track_gap` honest
                # (under a binding ceiling they show the airframe FAILING TO DELIVER). NOT persisted
                # to comp (the coupled-plant guard below — the slice-19 FINDING 1 trap, now 6-DOF).
                a_ctrl   = lift_accel_3d(e.vel, q_att, mass_af, p_af; c_yaw = c_yaw_af)
                defl_sat = defl_p || defl_y                    # BOTH fins (the isolation tell)
                alpha_diag  = (alpha_cmd = α_cmd, delta_cmd = δp_cmd, aero_sat = aero_sat,
                               defl_sat = defl_sat, a_max_aero = a_max_aero, q_dyn = q_dyn,
                               rho_air = rho_af)
                sixdof_diag = (beta_cmd = β_cmd, delta_yaw = δy_cmd)
            else
                # THE REFERENCE ARM (`:point_mass`): no plant to fly ⇒ `:ideal`'s perfect tracking. The
                # α-loop outputs are ZEROED (no α command was issued — honest, not a computed-but-unused
                # value), while the ceiling/flight-condition readouts stay REAL: the point-mass plant
                # crosses `a_max_aero` and HITS ANYWAY, which is exactly the contrast.
                #
                # ⚠ SLICE 21 CHANGED WHAT "REAL" MEANS HERE, and it is worth knowing before you wonder:
                # `_atm_on` requires `:pitch_coupled`, so on a scenario carrying `:af_scale_height` this
                # arm's `a_max_aero` reports the **ρ₀** ceiling — NOT the ρ(z) one — even under
                # `:atmosphere === :exponential`. That is the coherent reading (this plant flies constant-ρ
                # `total_accel`, so ρ₀ IS its flight condition, and the readout must describe the missile
                # that is flying), and it is unreachable from the slice-21 showcase, which authors
                # `:pitch_coupled` fixed and puts `:atmosphere` on the button. Slices 16–20 carry no scale
                # height, so nothing there is affected either way.
                a_ctrl     = a_cmd
                alpha_diag = (alpha_cmd = 0.0, delta_cmd = 0.0, aero_sat = false,
                              defl_sat = false, a_max_aero = a_max_aero, q_dyn = q_dyn,
                              rho_air = rho_af)
            end
        else
            # `:alpha` on a missile with NO airframe params at all — degenerate but not a crash: it is
            # `:ideal` with no aero readout to ship (the keys stay absent; LOAD-static, so not stale).
            a_ctrl = a_cmd
        end
        # Keep the PID plant state WARM (the `:pid`/`:fin` shape) so a live rung toggle away from
        # `:alpha` is bumpless. `e_int`/`e_prev` are carried untouched — `:alpha` runs no PID.
        state′ = (a_ach = a_ctrl, e_int = state.e_int, e_prev = state.e_prev)
    # SLICE-15 FIN SEAM: `:fin` = the SAME PID command driving a rate/deflection-limited fin servo
    # (`a = k_δ·δ`; guidance.jl `fin_autopilot_step`). Gated on `mode === :fin` — UNREACHABLE for a
    # slice-1..14 scenario (`get(w.fidelity,:autopilot,:ideal)` never returns `:fin`) → the `else`
    # arm is the slice-9/10/12 arithmetic TEXTUALLY UNCHANGED → byte-identical (the `+0.0`/spelling
    # bit trap; the PID arithmetic is DUPLICATED into `fin_autopilot_step`, not shared). Fin params
    # fetched INSIDE the branch (the slice-12 fetch-in-branch discipline) and floored at the consumer
    # (a live δ̇_max slider can't crash a tick — convention 5; LOAD-validated >0 for authored inputs).
    elseif mode === :fin
        tau_fin        = max(Float64(get(c, :tau_fin, tau)), _FRAME_EPS)        # fin servo τ; default = :pid tau
        k_delta        = max(Float64(get(c, :k_delta, 5000.0)), _FRAME_EPS)     # control effectiveness (divisor >0)
        delta_max      = max(Float64(get(c, :delta_max, 0.5)), _FRAME_EPS)      # deflection limit (rad)
        delta_rate_max = max(Float64(get(c, :delta_rate_max, 2.0)), _FRAME_EPS) # THE LESSON SLIDER (rad/s)
        fin = get(c, :fin_state, fin_actuator_init())::FinState
        a_ach, state′, fin′, fin_diag = fin_autopilot_step(a_cmd, state, fin, dt; kp = kp, ki = ki,
                                            kd = kd, tau_s = tau_fin, k_delta = k_delta,
                                            delta_max = delta_max, delta_rate_max = delta_rate_max)
        # Crash-guard (tuned NOT to bind: k_δ·δ_max ≤ a_max → δ_max is the g-cap, the RATE limit is
        # the isolated lesson). Thread the CLAMPED value back as the plant's a_ach (as :pid does).
        a_ach  = clamp_accel(a_ach, a_max)
        state′ = (a_ach = a_ach, e_int = state′.e_int, e_prev = state′.e_prev)
        c[:fin_state] = fin′
        a_ctrl = a_ach
    else
        a_ach, state′ = autopilot_step(mode, a_cmd, state, dt; kp = kp, ki = ki, kd = kd, tau = tau)
        if mode === :pid
            # BOUND the plant: clamp the achieved accel and thread the CLAMPED value back as the plant
            # state, so a badly-tuned (diverging) discrete PID can't run a_ach → Inf → NaN in pos
            # (advisor). `e_int` is left unclamped (it winds up only harmlessly at any real tick count).
            a_ach  = clamp_accel(a_ach, a_max)
            state′ = (a_ach = a_ach, e_int = state′.e_int, e_prev = state′.e_prev)
        end
        # :ideal returns a_ach == a_cmd (already clamped), so a_ctrl == a_cmd (perfect tracking, gap 0);
        # :pid uses the (already-clamped) plant output.
        a_ctrl = mode === :pid ? a_ach : clamp_accel(a_ach, a_max)
    end
    c[:ap_state] = state′
    # SLICE-19, FINDING 1 (LOAD-BEARING): the COUPLED plant makes its maneuver accel FROM LIFT —
    # `_integrate_coupled!` reads `:delta_cmd` and NEVER `:a_ctrl`. A fiat control force applied
    # BESIDE the lift would rebuild the point-mass plant wearing an airframe costume: the missile
    # would over-maneuver, the aero ceiling would never bind, and the lesson would be silently
    # deleted (the slice-15 k_δ-cancellation / slice-16 false-fidelity trap, THIRD occurrence).
    # Persisting the key would be inert TODAY (the coupled path ignores it) but is exactly that
    # latent trap, so under `:alpha`+`:pitch_coupled` it is NOT PERSISTED AT ALL — a pure-coupled
    # run NEVER GROWS `:a_ctrl`, a tripwire test_missile asserts (advisor). The LOCAL `a_ctrl` still
    # carries the achieved lift for the honest `a_ach`/`track_gap` readout below. For
    # `:ideal`/`:pid`/`:fin` the guard is ALWAYS false ⇒ the store is byte-for-byte as before.
    # SLICE 23: the 6-DOF plant makes its accel from 2-plane LIFT (`_integrate_6dof!` reads
    # `:delta_cmd`/`:delta_yaw_cmd`, NEVER `:a_ctrl`) — the SAME FINDING-1 trap as `:pitch_coupled`,
    # so it too must not grow `:a_ctrl`. `alpha_6dof` is false on every slice-1..22 path ⇒ the guard
    # is unchanged for them.
    (alpha_coupled || alpha_6dof) || (c[:a_ctrl] = a_ctrl)

    # Telemetry: the slice-9 keys (the tracking GAP) PLUS the slice-10 PN/saturation readouts. The
    # slice-10 lesson is MISS at CPA (isolated at :ideal — the verifier's job) + the saturation the
    # `a_demand`(pre-clamp) vs `a_cmd`(post-clamp) split makes visible. All `_finite`-clamped (no
    # Inf/NaN to JSON — the r→0 pre-clamp `a_demand` can be huge; §2 layer 3). `rel_pos`/`rel_vel`
    # are computed above (hoisted for the seeker branch).
    a_demand = _norm3(a_dem)                                   # PRE-clamp, POST-cutoff (saturation)
    tel["$sid.a_cmd"]         = _finite(_norm3(a_cmd))         # post-clamp (slice-9 key)
    tel["$sid.a_ach"]         = _finite(_norm3(a_ctrl))
    tel["$sid.track_gap"]     = _finite(_norm3(a_cmd - a_ctrl))
    tel["$sid.los_range"]     = _finite(los_range(e.pos, tgt.pos))
    tel["$sid.range_rate"]    = _finite_coord(range_rate(rel_pos, rel_vel))  # signed (neg = closing)
    tel["$sid.a_demand"]      = _finite(a_demand)              # PRE-clamp demand (the saturation tell)
    tel["$sid.saturated"]     = a_demand > a_max ? 1.0 : 0.0  # g-limit binding? (the Lesson-2 flag)
    tel["$sid.los_rate"]      = _finite(_norm3(los_rate(rel_pos, rel_vel)))  # ‖ω‖ (the PN driver)
    tel["$sid.closing_speed"] = _finite_coord(-range_rate(rel_pos, rel_vel))  # Vc (POSITIVE closing)
    # Slice-14 salvo diagnostics — SHIPPED WHENEVER A COORDINATOR IS PRESENT (`salvo_t_d` published),
    # so BOTH `:solo` and `:salvo` salvo-scenarios readout this missile's time-to-go and the impact-
    # time error the cooperation term nulls (under `:solo` the error is shown but NOT applied — the
    # lesson: what the salvo law WOULD correct). ABSENT in a slice-9..13 scenario (no coordinator →
    # no key) → those frames byte-identical. Per-missile (the shared `salvo_t_d`/`T_d` are the
    # coordinator's keys). `impact_time_err > 0` ⇒ EARLY ⇒ `:salvo` stretches.
    if haskey(w.env, :salvo_t_d)
        std_rem  = Float64(w.env[:salvo_t_d])                 # shared desired REMAINING time-to-go
        tgo_self = time_to_go(los_range(e.pos, tgt.pos), -range_rate(rel_pos, rel_vel))
        tel["$sid.t_go"]            = _finite(tgo_self)
        tel["$sid.impact_time_err"] = _finite_coord(std_rem - tgo_self)  # >0 ⇒ early ⇒ stretch
    end
    # Slice-15 fin diagnostics — SHIPPED WHENEVER mode === :fin (a slice-1..14 / :ideal / :pid
    # scenario ships NONE → byte-identical wire). All SCALARS (no Array → no float() client crash).
    # The g-onset readout IS the slice-15 lesson: the achieved-g BUILD RATE ‖a_ach−a_ach_prev‖/dt,
    # hard-capped at k_δ·δ̇_max by the rate limit (vs :ideal's uncapped step). fin_rate_sat lights
    # while the RATE limit binds (the lesson flag); fin_defl_sat must stay 0 (the isolation — the
    # deflection/g-limit does NOT bind, so the cap is a clean RATE cap, not slice-10's magnitude one).
    if mode === :fin && fin_diag !== nothing
        tel["$sid.fin_defl"]     = _finite(fin_diag.delta)               # ‖δ‖ (rad) — the fin deflection
        tel["$sid.fin_rate"]     = _finite(fin_diag.delta_rate)          # ‖δ̇‖ (rad/s) — the slew rate
        tel["$sid.fin_rate_sat"] = fin_diag.rate_sat ? 1.0 : 0.0         # RATE limit binding? (the lesson flag)
        tel["$sid.fin_defl_sat"] = fin_diag.defl_sat ? 1.0 : 0.0         # DEFLECTION limit binding? (isolation)
        tel["$sid.g_onset"]      = _finite(_norm3(a_ctrl - a_ach_prev) / dt)  # achieved-g build rate (≤ k_δ·δ̇_max)
    end
    # Slice-19 α/g diagnostics — SHIPPED WHENEVER `mode === :alpha` AND the missile carries airframe
    # params (a slice-1..18 / :ideal / :pid / :fin scenario ships NONE → byte-identical wire). All
    # SCALARS (no Array → no client float() crash), all `_finite`-clamped (convention 6). The ACHIEVED
    # α is NOT duplicated here — `build_env!` already ships it as `<sid>.alpha` from the same
    # post-integrate state (one source of truth).
    #
    # GATED ON THE RUNG, NOT ON `:pitch_coupled` — the DELIBERATE CONTRAST to slice-17's lift keys
    # (advisor): `a_lift` is a PRODUCED FORCE that only physically exists when coupled, but
    # `a_max_aero`/`q_dyn` are FLIGHT-CONDITION PROPERTIES of the airframe, true whichever plant model
    # is active. Shipping them under BOTH arms is what makes the headline readout work — the client
    # plots `a_max_aero` vs `a_demand` and THE CROSSING IS THE VERDICT (the analog of slice-18's
    # clearance sign): under `:point_mass` the demand crosses the ceiling and the missile HITS ANYWAY
    # (the plant ignores it); under `:pitch_coupled` that same crossing IS the miss. Gating on the rung
    # also keeps the key SET invariant across the live `:airframe` toggle → no stale keys.
    if mode === :alpha && alpha_diag !== nothing
        tel["$sid.alpha_cmd"]  = _finite_coord(alpha_diag.alpha_cmd)  # signed α command (rad); 0 under :point_mass
        tel["$sid.delta_cmd"]  = _finite_coord(alpha_diag.delta_cmd)  # signed fin deflection (rad); 0 under :point_mass
        tel["$sid.a_max_aero"] = _finite(alpha_diag.a_max_aero)       # THE HEADLINE: Q·S·|C_Lα|·α_max/m
        # ½ρV² — the flight condition. Through slice 20 ONLY V could move it (ρ was a number an
        # engineer typed); slice 21's `:atmosphere` rung makes ρ = ρ(z) too, so BOTH factors move.
        tel["$sid.q_dyn"]      = _finite(alpha_diag.q_dyn)
        tel["$sid.aero_sat"]   = alpha_diag.aero_sat ? 1.0 : 0.0      # the AERO ceiling binding? (THE LESSON flag)
        tel["$sid.defl_sat"]   = alpha_diag.defl_sat ? 1.0 : 0.0      # δ_max binding? (the ISOLATION — must stay 0)
        # SLICE 21 — THE AIR THE MISSILE IS ACTUALLY FLYING IN (kg/m³). KEY-gated on an authored
        # `:af_scale_height` (the slice-20 `a_induced` / slice-15 fin-key precedent): slices 16–20
        # carry no scale height, so their wire is byte-identical.
        #
        # ⭐ IT SHIPS UNDER **BOTH** RUNGS, AND THAT IS LOAD-BEARING — the KEY is the gate, never the
        # rung (the deliberate contrast with `a_lift`, which is a produced force that only exists
        # when coupled). Under `:constant` this is the flat authored ρ₀ **and that is precisely the
        # lie the slice exposes**: the twin's ρ-factor is EXACTLY 1.0, i.e. the old model attributes
        # 100% of its ceiling loss to speed. Rung-gating this key would take the twin's half of the
        # headline off the wire and leave the client to divide `2·q_dyn/V²` — physics in GDScript,
        # which convention 13 forbids. The CORE computes; the client displays.
        if haskey(c, :af_scale_height)
            tel["$sid.rho_air"] = _finite(alpha_diag.rho_air)
        end
    end
    # SLICE 23 — THE YAW-CHANNEL COMMAND READOUTS. Shipped ONLY when the 6-DOF STT arm ran
    # (`sixdof_diag !== nothing` ⇒ `:six_dof` this tick), so a `:pitch_coupled`/`:point_mass`
    # `:alpha` wire (slices 19–22) NEVER grows a yaw key → byte-identical (the separate-gated-block
    # discipline — advisor). `beta_cmd`/`delta_yaw` are the yaw twins of the shared `alpha_cmd`/
    # `delta_cmd` above; the resultant `aero_sat`/`defl_sat` already shipped in the alpha_diag block.
    if mode === :alpha && sixdof_diag !== nothing
        tel["$sid.beta_cmd"]  = _finite_coord(sixdof_diag.beta_cmd)   # signed β command (rad)
        tel["$sid.delta_yaw"] = _finite_coord(sixdof_diag.delta_yaw)  # signed yaw fin deflection (rad)
    end
    return nothing
end

# --- the NOISY SEEKER: the missile's FIRST observe! (slice 11, HANDOFF §10 item 11) ------------
# "A missile is integrate! (airframe) + observe! (seeker) + decide! (guidance)" (HANDOFF §3): the
# Seeker fills the phase-3 observe! missile.jl:11 anticipated ("observe!/decide! stay EMPTY here —
# guidance/seekers are slices 9–11"), COMPLETING that sentence. It replaces slice 10's truth-fed PN
# (pn_accel reading target truth) with a MEASURED line-of-sight: the seeker senses the LOS *angle*
# with white angular noise (`sigma_seek`), and the α-β filter (estimation.jl `alpha_beta_los_step`)
# estimates the LOS *rate* λ̇ WITHOUT differentiating it — the whole slice-11 lesson (the `:raw`
# finite-difference foil amplifies the angle noise by 1/dt → PN's `N·Vc·λ̇` pegs `a_max`, the miss
# opens; the α-β filter recovers a smooth λ̇ → tight intercept).
#
# THE RNG INFLECTION — do NOT copy the slice-8/9/10 "RNG is VACUOUS" boilerplate; it INVERTS here.
# The Seeker is the FIRST `w.rng` consumer in the missile arc, so conventions 3 (unconditional draw)
# and 11 (own Xoshiro for MC) now APPLY. `observe!` draws ONE `randn(w.rng)` sample UNCONDITIONALLY
# every tick — a FIXED count invariant to the `:seeker` rung, the `sigma_seek`/`alpha`/`beta`
# sliders, target geometry, AND post-impact (the missile freezes but the target keeps moving, so
# observe! keeps running — the `detect_once`/`_draw_pseudoranges` "draw-then-gate-the-VALUE"
# template). Gate only the value PN consumes, never the draw. `:seeker` is a GENUINELY NEW
# fidelity-class combo (named at `SEEKER_MODES`, estimation.jl): DRAW-INVARIANT (class 4a — both
# rungs draw the same 1 sample, so `set_fidelity` may INTRODUCE it, UNLIKE `:cfar`) YET
# TRAJECTORY-CHANGING (a `:raw↔:filtered` toggle MOVES the missile — the slice-10 shape). Copy
# NEITHER the slice-5 "toggle-bit-identical" NOR the slice-8/9/10 "no-RNG" language. Byte-identity
# for slices 1–10 comes from the Seeker NOT EXISTING there, NOT a draw-skipping `:truth` rung (there
# is none; "truth-fed PN" IS slice 10 — no Seeker).
#
# SCALAR IN-PLANE (gate-0 FINDINGS decision 3): the engagement is planar in x-z, ω ∥ ±y, so the
# seeker tracks a SCALAR LOS angle `λ = atan(Δz, Δx)` and reconstructs `ω = Vec3(0, −λ̇, 0)` for PN
# (with r=(rx,0,rz), v=(vx,0,vz): `los_rate_y = (rz·vx − rx·vz)/r²` and `λ̇ = −ω_y`). Scalar avoids
# the vector form's tangent-injection / cross-innovation-sign / renormalize bug surface. `Vc` stays
# TRUTH (only the angle is noisy — one lesson per scenario, § scope; decide! supplies it).
struct Seeker <: Subsystem
    id::Symbol
end

# Phase 1: capture the tick `dt` into comp (the α-β predict step needs it; `observe!` has no `dt`
# arg — cf. `RadarSensor.observe!`). Its OWN capture key `:dt_s_seeker` (self-contained, advisor #4)
# — NOT a lean on the Autopilot's `:dt_s`, whose presence assumes the Autopilot is armed alongside
# the Seeker (the missile.jl `Autopilot.integrate!` dt-capture precedent). Does NOT move the entity.
function integrate!(s::Seeker, w::World, dt::Float64)
    w.entities[s.id].comp[:dt_s_seeker] = dt
    return nothing
end

# Phase 3: the missile's first sensor read. Draw the angle-noise sample UNCONDITIONALLY (convention
# 3), measure the noisy LOS angle, update BOTH the raw finite-difference memory AND the α-β filter
# state every tick (so a mid-run `:raw↔:filtered` toggle keeps both paths warm and stays
# draw-count-invariant — the rung selects only WHICH ω is written), and write the chosen ω/û into
# comp for the phase-4 `decide!` (the tick contract's phase order hands off THIS tick — no one-tick
# delay for the estimate; the seeker senses this tick's truth + noise). RNG-free after the one draw
# (the filter is deterministic post-processing).
# Phase 3 dispatcher: the `:scan` rung (slice-13 countermeasures) runs a WHOLLY different draw
# topology (`2·N_p·N_bins` for the angular-profile floor) from `:raw`/`:filtered` (`1` randn), so it
# is a SEPARATE code path — NOT a value-branch inside the point path. Reading `:seeker` is pure (no
# RNG), so this dispatch does not perturb the draw ORDER: a `:raw`/`:filtered`/no-scan scenario runs
# `_observe_point!` with `n = randn(w.rng)` as its literal first statement → slices 1–12 byte-identical
# BY CONSTRUCTION (the slice-11 body is textually UNCHANGED below). `:scan` is introduce/remove-rejected
# at `set_fidelity` (server.jl, the 4b guard), so this branch is only ever reached from a `:scan`-loaded
# scenario — never toggled onto a live point-path replay.
# SLICE-25 THREE-WAY DISPATCH — the PRECEDENCE is explicit, and the one ambiguous corner is refused
# at LOAD, not ordered around (`_validate_missile`; the slice-21 "stall × ρ(z) is a LOAD ERROR"
# precedent — `docs/plans/slice25.md` §1b). The TWO-ANGLE path is selected by the SCENARIO's host
# marker `:seek_two_angle` (from the `seeker:` block), NEVER by the `:seeker_axes` fidelity: that is
# precisely what makes introducing `:seeker_axes` live on a slice-11/13 wire INERT (P11) instead of a
# 1→2 draw-topology flip that would desync replay. `:seeker` (the TRACKER: raw ↔ filtered) and
# `:seeker_axes` (the DIMENSIONALITY) are ORTHOGONAL on the host.
#
#   no host marker            → `_observe_scan!` / `_observe_point!` exactly as before (slices 11/13
#                               byte-identical — `_observe_point!` still runs `randn(w.rng)` as its
#                               literal first statement)
#   host marker + :raw/:filtered → `_observe_point3d!` (2 draws, both rungs)
#   host marker + :scan       → UNREACHABLE (refused at LOAD)
function observe!(s::Seeker, w::World)
    e = w.entities[s.id]
    c = e.comp
    rung = get(w.fidelity, :seeker, :filtered)
    if get(c, :seek_two_angle, false) === true
        _observe_point3d!(s, w, e, c, rung)
    else
        rung === :scan ? _observe_scan!(s, w, e, c) : _observe_point!(s, w, e, c, rung)
    end
    return nothing
end

# The slice-11 point seeker — ONE noisy truth bearing → raw finite-diff + α-β filter. VERBATIM the
# slice-11 body (the only change: `rung` is now a parameter, not re-read here — a pure move that
# leaves the RNG draw order bit-identical). Kept textually unchanged so the golden + determinism
# tests replay bit-for-bit (the `+0.0`/spelling bit trap — do NOT reformat the arithmetic).
function _observe_point!(s::Seeker, w::World, e::Entity, c::AbstractDict, rung::Symbol)
    # CONVENTION 3 — the unconditional draw, FIRST, before any target/geometry/impact gate. A FIXED
    # 1 draw/tick (scalar in-plane; the vector form's 2 ⟂ draws are NOT used — FINDINGS decision 3).
    n = randn(w.rng)

    tgt = _nearest_target(w, e)
    tgt === nothing && return nothing        # no LOS to measure (load validates ≥1 target); draw taken

    dt = Float64(get(c, :dt_s_seeker, 1.0e-3))
    σ  = max(Float64(get(c, :sigma_seek, 3.0e-3)), 0.0)   # σ≥0 floor (a live slider can't go negative)
    α  = Float64(get(c, :alpha, 0.30))                    # α-β gains (load-validated 0<α<1, β>0; the
    β  = Float64(get(c, :beta,  0.05))                    # filter floors β/dt, so no consumer re-clamp)

    # Truth LOS in the x-z engagement plane and the noisy MEASURED angle (NOT wrapped — only the
    # filter's/raw's innovation-DIFFERENCE wraps; wrapping the absolute angle here is a needless op).
    û_tru  = los_unit(e.pos, tgt.pos)
    λ_tru  = atan(û_tru[3], û_tru[1])
    λ_meas = λ_tru + σ * n

    # Lazy first-tick init (the `e0_j` precedent): seed the raw memory + α-β state, λ̇ = 0 both paths.
    if !get(c, :seek_init, false)
        c[:seek_lambda_prev]   = λ_meas
        c[:seek_lambda_est]    = λ_meas
        c[:seek_lambdadot_est] = 0.0
        c[:seek_init]          = true
        λ̇_raw = 0.0
        λ_est = λ_meas; λ̇_est = 0.0
    else
        # RAW foil: finite-difference consecutive noisy angles (amplifies the angle noise by 1/dt).
        λ_prev = Float64(c[:seek_lambda_prev])
        λ̇_raw  = wrap_angle(λ_meas - λ_prev) / dt
        c[:seek_lambda_prev] = λ_meas
        # FILTERED: one α-β predict–correct step (updates state EVERY tick, both rungs → warm + invariant).
        λ_est = Float64(c[:seek_lambda_est]); λ̇_est = Float64(c[:seek_lambdadot_est])
        λ_est, λ̇_est = alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α = α, β = β)
        c[:seek_lambda_est]    = λ_est
        c[:seek_lambdadot_est] = λ̇_est
    end

    # The rung selects WHICH (λ̇, λ) PN consumes; the draw count is identical either way. Reconstruct
    # the in-plane `ω = Vec3(0, −λ̇, 0)` and `û = (cos λ, 0, sin λ)` from the CHOSEN rate/angle (a
    # CONSISTENT estimate source — FINDINGS decision f). `decide!` supplies TRUTH `Vc`.
    λ̇_used, λ_used = rung === :raw ? (λ̇_raw, λ_meas) : (λ̇_est, λ_est)
    c[:seeker_omega] = Vec3(0.0, -λ̇_used, 0.0)
    c[:seeker_los]   = Vec3(cos(λ_used), 0.0, sin(λ_used))

    # Seeker telemetry — phase-3 observe! is POST-`empty!(w.env)` (the radar-readout phase), so a
    # direct `w.env[:telemetry]` write survives. All SCALARS (no Array → no `float()`-crash in the
    # client). λ̇ is SIGNED → `_finite_coord`; σ is a magnitude → `_finite`.
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(s.id)
    tel["$sid.lambda_dot_raw"]  = _finite_coord(λ̇_raw)         # naïve finite-diff (jitters under :raw)
    tel["$sid.lambda_dot_filt"] = _finite_coord(λ̇_est)         # α-β estimate (smooth — always available)
    tel["$sid.lambda_dot_used"] = _finite_coord(λ̇_used)        # the one PN actually consumed this tick
    tel["$sid.sigma_seek"]      = _finite(σ)
    return nothing
end

# The slice-25 TWO-ANGLE seeker — the missile's sensor finally sees in 3-D (§11 Tier-A, the third
# slice of the bank-to-turn / 3-D arc). Slice 23 gave the missile an airframe that can turn OUT of the
# x–z plane and slice 24 made it choose HOW to point its lift; both were TRUTH-FED. This is the
# SENSOR half, and it cashes the deferral slice 11 wrote into its own source (`_observe_point!` above:
# "Scalar avoids the vector form's tangent-injection / cross-innovation-sign / renormalize bug
# surface"). The seeker measures an azimuth/elevation PAIR, α-β tracks EACH, and rebuilds the LOS-rate
# VECTOR `ω = û × û̇` (`los_rate_from_angles`, frames.jl — IDENTICALLY the quantity `los_rate`
# computes from truth, which makes truth an EXACT oracle rather than a calibrated one).
#
# THE LESSON lives in the `:seeker_axes` rung, and the FOIL is the point: `:pitch_plane` runs slice
# 11's SCALAR tracker on `λ = atan(Δz, Δx)` and rebuilds `ω = (0, −λ̇, 0)` — an LOS rate STRUCTURALLY
# incapable of an out-of-plane component. Against a cross-range target the missile then flies straight
# down the x–z plane and misses by the full offset, with `max|y| = 0.0` EXACTLY: the SAME signature as
# slice 23's `:pitch_coupled` discard from a WHOLLY different cause (there the autopilot THREW the
# command away; here it was never FORMED, because the measurement had no such component in it).
#
# ⚠ THE 2-DRAW LOCKSTEP (convention 3, and what makes the showcase button LEGAL): BOTH rungs draw
# EXACTLY 2 `randn` — `:pitch_plane` takes `n_az` and DISCARDS it. Gate the VALUE, never the draw. Do
# NOT "optimize away" the unused draw: without it the toggle is a 1↔2 draw-topology flip mid-replay
# and `set_fidelity` would have to reject the very switch the button exists to make (the `:cfar` 4b
# guard). Measured 2.0 draws/tick on both rungs (gate-0 P9) ⇒ class 4a within the 2-draw host.
#
# ⚠ BOTH TRACKERS ARE UPDATED EVERY TICK (the slice-11 raw+filtered precedent, one level up): the az/el
# pair AND the scalar λ, so a live `:seeker_axes` toggle is BUMPLESS and the state evolution is
# rung-INVARIANT — the rung selects only WHICH (ω, û) the phase-4 `decide!` consumes.
#
# ONE isotropic σ (`sigma_seek`) on both angles is a NAMED approximation (a real seeker's az/el
# channels differ); `Vc` stays TRUTH, exactly as in slice 11 (§ scope: only the ANGLES are noisy).
function _observe_point3d!(s::Seeker, w::World, e::Entity, c::AbstractDict, rung::Symbol)
    # CONVENTION 3 — the unconditional draws, FIRST, before any target/geometry/impact gate, and the
    # SAME COUNT on both `:seeker_axes` rungs (the foil discards `n_az` below, it does not skip it).
    n_az = randn(w.rng)
    n_el = randn(w.rng)

    tgt = _nearest_target(w, e)
    tgt === nothing && return nothing        # no LOS to measure (load validates ≥1 target); draws taken

    dt = Float64(get(c, :dt_s_seeker, 1.0e-3))
    σ  = max(Float64(get(c, :sigma_seek, 3.0e-3)), 0.0)   # σ≥0 floor (a live slider can't go negative)
    α  = Float64(get(c, :alpha, 0.30))                    # α-β gains (load-validated 0<α<1, β>0)
    β  = Float64(get(c, :beta,  0.05))
    axes = get(w.fidelity, :seeker_axes, :az_el)

    # Truth angles and the noisy MEASUREMENTS. `az_el` (frames.jl) is the same convention the
    # reconstruction inverts; `λ` is slice 11's in-plane bearing, measured with the ELEVATION sample
    # (the in-plane bearing IS an elevation-like angle in x–z — the azimuth sample is the one the foil
    # structurally cannot use). NOT wrapped here — only the innovation DIFFERENCES wrap.
    û_tru        = los_unit(e.pos, tgt.pos)
    az_tru, el_tru = az_el(û_tru)
    λ_tru        = atan(û_tru[3], û_tru[1])

    # SLICE 26 — THE RADOME. The seeker does not look at the target directly: it looks THROUGH a
    # radome, which refracts by `ε = R·(look angle off the boresight)` (frames.jl `radome_error`).
    # The bend therefore depends on the missile's OWN ATTITUDE, which closes a feedback path from
    # the airframe back into guidance — `q → look → ε → apparent λ̇ → PN → a_cmd → α → q` — and past
    # a critical loop gain (MEASURED at `N·|R|/ρ ≈ 0.38`) that loop is UNSTABLE and the missile
    # shakes itself into a sustained limit cycle. See `docs/plans/slice26.md`.
    #
    # ⚠ STRUCTURAL BYTE-IDENTITY (the slice-20/21 shape): a BRANCH, with the else-arm slice-25
    # VERBATIM — never `az_tru + ε + σ*n` trusting `R = 0 ⇒ ε = 0.0`. Two reasons, both real: the
    # `-0.0` trap, and float non-associativity ((a+ε)+b ≠ a+b in the last ULP). A no-radome wire is
    # bit-for-bit slice 25 BY CONSTRUCTION, not by a zero that happens to cancel.
    #
    # ⚠ RUNG-GATED ON THE LIVE `:airframe`, NOT merely on `haskey(:att_q)` (the slice-21 `_atm_on` /
    # slice-23 stale-readout latent-bug class, whose THIRD occurrence this would be): `:att_q` is
    # minted by `_integrate_6dof!` and NEVER deleted, so after a cross-toggle off `:six_dof` a
    # key-gated radome would keep refracting through a FROZEN attitude — a boresight error computed
    # from an attitude the missile is no longer flying. `haskey(:att_q)` stays ONLY as a crash guard
    # (convention 5: a live knob can never throw inside a tick), it is not the semantic gate.
    _rad_on = haskey(c, :radome_slope) && haskey(c, :att_q) &&
              get(w.fidelity, :airframe, :point_mass) === :six_dof
    if _rad_on
        R_rad = Float64(c[:radome_slope])
        look_az, look_el = look_angles(c[:att_q]::Quat, û_tru)
        # SLICE 28 — THE SLOPE CURVE. Slices 26/27 both assumed the glass has ONE slope; a real
        # radome's error slope is a CURVE in look angle, because the ray passes through different
        # glass at different look angles. `R(look) = R₀ + A·(1−cos(k·look))` (frames.jl
        # `radome_slope_curve`), and the bend is its EXACT integral — so the parasitic loop, which
        # is driven by `dε/dlook`, is closed by the curve's LOCAL DERIVATIVE at the look angle the
        # missile is actually flying. ⭐ And WHICH look angle that is belongs to the ENGAGEMENT,
        # not to the radome: a static target's collision course carries zero lead and settles the
        # seeker onto boresight (MEASURED at 0.04–0.54° on slices 23–27's wire — this key would be
        # a DEAD KNOB there), while a crossing target holds a sustained lead of 15–30°.
        # See `docs/plans/slice28.md`.
        #
        # ⚠ STRUCTURAL BYTE-IDENTITY, the slice-20/21/26/27 shape, THIRD nesting level here: the
        # else-arm calls `radome_error` VERBATIM. Never the curve kernel at amplitude 0 — `x + 0.0`
        # is not the identity at `x = −0.0` and float addition is not associative, so a no-ripple
        # wire is bit-for-bit slice 26/27 BY CONSTRUCTION rather than by a zero that cancels. (The
        # kernels' own reduction IS pinned bit-for-bit in `test_frames.jl` — that exactness is the
        # knob-vs-rung argument, atmosphere.jl's discriminator; it is not the seam's mechanism.)
        _ripple_on = haskey(c, :radome_ripple)
        if _ripple_on
            A_rip = Float64(c[:radome_ripple])
            k_rip = Float64(get(c, :radome_ripple_k, 12.0))
            ε_az, ε_el = radome_error_curve(R_rad, A_rip, k_rip, look_az, look_el)
        else
            A_rip = 0.0; k_rip = 0.0
            ε_az, ε_el = radome_error(R_rad, look_az, look_el)
        end
        az_m = az_tru + ε_az + σ * n_az
        el_m = el_tru + ε_el + σ * n_el
        λ_m  = λ_tru  + ε_el + σ * n_el     # ONE physical bend of ONE measurement — both trackers see it
    else
        R_rad = 0.0; look_az = 0.0; look_el = 0.0; ε_az = 0.0; ε_el = 0.0
        _ripple_on = false; A_rip = 0.0; k_rip = 0.0
        az_m = az_tru + σ * n_az            # ── slice-25 VERBATIM below ──
        el_m = el_tru + σ * n_el
        λ_m  = λ_tru  + σ * n_el
    end

    # Lazy first-tick init (the `_observe_point!` shape): seed every memory, all rates 0.
    if !get(c, :seek_init, false)
        c[:seek_az_prev]  = az_m; c[:seek_el_prev]  = el_m; c[:seek_lambda_prev]   = λ_m
        c[:seek_az_est]   = az_m; c[:seek_el_est]   = el_m; c[:seek_lambda_est]    = λ_m
        c[:seek_azdot_est] = 0.0; c[:seek_eldot_est] = 0.0; c[:seek_lambdadot_est] = 0.0
        c[:seek_init]     = true
        ȧz_raw = 0.0; ėl_raw = 0.0; λ̇_raw = 0.0
        az_est = az_m; el_est = el_m; λ_est = λ_m
        ȧz_est = 0.0; ėl_est = 0.0; λ̇_est = 0.0
    else
        # RAW foil rates: finite-difference consecutive noisy angles (amplifies σ by 1/dt).
        ȧz_raw = wrap_angle(az_m - Float64(c[:seek_az_prev]))     / dt
        ėl_raw = wrap_angle(el_m - Float64(c[:seek_el_prev]))     / dt
        λ̇_raw  = wrap_angle(λ_m  - Float64(c[:seek_lambda_prev])) / dt
        c[:seek_az_prev] = az_m; c[:seek_el_prev] = el_m; c[:seek_lambda_prev] = λ_m
        # FILTERED: one α-β predict–correct step per angle — ALL THREE trackers every tick, both
        # rungs (warm + rung-invariant state ⇒ a bumpless live toggle).
        az_est, ȧz_est = alpha_beta_los_step(Float64(c[:seek_az_est]),
                                             Float64(c[:seek_azdot_est]), az_m, dt; α = α, β = β)
        el_est, ėl_est = alpha_beta_los_step(Float64(c[:seek_el_est]),
                                             Float64(c[:seek_eldot_est]), el_m, dt; α = α, β = β)
        λ_est,  λ̇_est  = alpha_beta_los_step(Float64(c[:seek_lambda_est]),
                                             Float64(c[:seek_lambdadot_est]), λ_m, dt; α = α, β = β)
        c[:seek_az_est] = az_est; c[:seek_azdot_est] = ȧz_est
        c[:seek_el_est] = el_est; c[:seek_eldot_est] = ėl_est
        c[:seek_lambda_est] = λ_est; c[:seek_lambdadot_est] = λ̇_est
    end

    # The rung selects WHICH (ω, û) PN consumes — the draw count is identical either way, and so is
    # every tracker's state. `:seeker` picks the tracker within the chosen dimensionality (a
    # CONSISTENT estimate source — the slice-11 FINDINGS decision f, now in two angles).
    # SLICE 27 — THE RADOME-SLOPE COMPENSATION AUTOPILOT (the engineering answer slice 26 named as
    # its own successor). The missile already carries a rate gyro — the α/β autopilot has fed on
    # `:omega_body` since slice 23 — so FEED THE PARASITIC TERM FORWARD AND SUBTRACT IT: with the
    # slope the guidance computer BELIEVES it has (`R̂ = :radome_slope_est`),
    #
    #     Δȧz = +R̂·ω_z ,     Δėl = −R̂·cos(look_az)·ω_y      (frames.jl `radome_compensation`)
    #
    # cancels slice 26's gain TO THE ACCURACY OF THAT BELIEF. ⭐ What is left driving the loop is
    # the RESIDUAL `R − R̂`, and slice 26's boundary returns verbatim with the substitution:
    # `N·|R − R̂|/ρ ≈ 0.38` (MEASURED to ±3% across N ∈ {3…8} and ρ ∈ {0.6…2.0}, `docs/plans/
    # slice27.md` §1). ⇒ compensation buys MARGIN, NOT IMMUNITY, and the design requirement stops
    # being "a better radome" and becomes "a better-KNOWN one" — here, to within 0.38/(N·ρ).
    #
    # ⚠ IT IS NOT AN EQUIVALENT RADOME (gate-0 P3B — the finding that keeps the slice honest). The
    # look angle moves for TWO reasons: the BODY rotating, which the gyro sees, and the LOS itself
    # rotating, which it does not. The body-rate half cancels exactly — hence the exact boundary —
    # but the LOS-driven half survives, so over-compensation DE-TUNES rather than helping. Say "the
    # residual sets the STABILITY BOUNDARY", never "the residual is an equivalent radome".
    #
    # ⚠ THE COMPENSATOR NEVER READS TRUTH. The radome bends the REAL ray (`look_az`/`look_el` above,
    # from `û_tru`) — that is the PHYSICS. The correction must use what a guidance computer actually
    # has: its own INS attitude, the gyro, and the BENT measurement. So the look angle here is
    # recomputed from `az_m`/`el_m`, and its own error is second order in the bend. Feeding it the
    # truth look angle would make the slice fake (advisor).
    #
    # ⚠ RUNG-GATED ON THE LIVE `:airframe`, exactly as the radome is — never on `haskey(:att_q)`
    # alone (the slice-21 `_atm_on` / slice-23 stale-readout / slice-26 latent-bug class, whose
    # FOURTH occurrence this would be). ⚠ And NOT gated on the radome's own key: compensating for
    # glass you do not have is a real configuration (residual = −R̂ ⇒ it de-tunes), not a no-op.
    ȧz_ff = 0.0; ėl_ff = 0.0; R̂_rad = 0.0
    _sched_on = false; Â_est = 0.0; k̂_est = 0.0; look_az_c = 0.0; look_el_c = 0.0
    _gyro_on = false; s_gyro = 0.0; by_gyro = 0.0; bz_gyro = 0.0      # slice 31
    _comp_on = haskey(c, :radome_slope_est) && haskey(c, :att_q) &&
               get(w.fidelity, :airframe, :point_mass) === :six_dof
    if _comp_on
        R̂_rad = Float64(c[:radome_slope_est])
        # The compensator's OWN look angle: the MEASURED (bent) LOS rotated into the body frame.
        look_az_c, look_el_c = look_angles(c[:att_q]::Quat, los_unit_from_angles(az_m, el_m))
        # SLICE 29 — THE SCHEDULED COMPENSATOR. Slice 28 showed the glass has no single slope, so
        # the belief must be a CURVE too: `R̂(look) = R̂₀ + Â·(1 − cos(k̂·look))` (frames.jl
        # `radome_compensation_scheduled`), applied PER AXIS — the azimuth channel's belief at
        # `look_az_c`, the elevation channel's at `look_el_c` (slice 28's gate-2 hardening, now on
        # the compensator side).
        #
        # ⭐⭐ AND THE INDEX IS THE SLICE. A schedule has to be EVALUATED somewhere, and the only
        # look angle a guidance computer owns is `look_az_c`/`look_el_c` — computed from the BENT
        # measurement, which is exactly what the radome did to it. So the belief that reaches the
        # loop is `R̂(look_bent)`, not `R̂(look_truth)`, and slice 26/27/28's residual law survives
        # ONLY when read at this index: measured at a common reference look angle, the TRUTH-indexed
        # residual gets two of three arms WRONG (it predicts quiet for the arm that rings and
        # ringing for the arm that stays quiet) while the index-shifted one gets every arm right
        # (`docs/plans/slice29.md` §3, gate-0 P10c). ⚠ `look_az`/`look_el` (TRUTH, off `û_tru`) are
        # RIGHT THERE in this function and are what the GLASS bends at — passing them here instead
        # would be the natural edit and would silently delete the slice. Slice 27's rule: the
        # compensator never reads truth.
        #
        # ⚠ STRUCTURAL BYTE-IDENTITY (the slice-20/21/26/27/28 shape, FOURTH nesting level): the
        # else-arm calls `radome_compensation` VERBATIM. Never the scheduled kernel at amplitude 0 —
        # `x + 0.0` is not the identity at `x = −0.0` and float addition is not associative, so a
        # slice-27/28 wire is bit-for-bit unchanged BY CONSTRUCTION. (The kernels' own reduction IS
        # pinned bit-for-bit in `test_frames.jl` — that exactness is the knob-vs-rung argument,
        # atmosphere.jl's discriminator; it is not the seam's mechanism.)
        #
        # SLICE 31 — AN IMPERFECT GYRO. Slices 27/28/29/30 all fed the feed-forward the TRUE body
        # rate and all four named that as a §1 approximation. Here the compensator reads what a real
        # rate gyro REPORTS, `ω̃ = (1+s)·ω + b` (frames.jl `gyro_reading`), and the two error terms
        # land in DIFFERENT CURRENCIES:
        #   • a SCALE FACTOR is common-mode on the product `R̂·ω̃`, so the belief that reaches the loop
        #     is EXACTLY `R̂(1+s)` — back onto slice 26/27's RESIDUAL, moving the STABILITY BOUNDARY,
        #     and ONE-SIDED like slice 26/30's constraint (with `R̂ < 0`, a gyro that UNDER-reads
        #     walks the effective belief toward the ringing side; over-reading merely de-tunes);
        #   • a BIAS never touches the belief. It injects a CONSTANT spurious LOS rate `R̂·b` — the
        #     arc's FIRST ADDITIVE entry — which moves the AIM POINT, not the boundary, and is
        #     TWO-SIDED: no safe direction.
        # ⭐ Both are scaled by `|R̂|`, which slice 30's design rule DELIBERATELY MAXIMIZES: the
        # scalar that buys unconditional stability buys the gyro's own errors with it, so the aim
        # point becomes `R_worst/(1+s)`. See `docs/plans/slice31.md`.
        #
        # ⚠ THE EQUIVALENCE IS A TOOTH, NOT A HEADLINE (the FALSE-FIDELITY trap, slice 15's `k_δ` /
        # slice 19's dead `speed`): `R̂(1+s)` is a value `radome_slope_est` can already take, so the
        # scale-factor half adds NO mechanism by itself. What it adds is that the error is
        # MULTIPLICATIVE — absolute size `|R̂|·|s|` — which no additive parameterization expresses.
        #
        # ⚠ STRUCTURAL BYTE-IDENTITY (the slice-20/21/26/27/28/29 shape, FIFTH nesting level): with
        # no gyro-error key the TRUTH rate is passed VERBATIM by a TERNARY that does no arithmetic on
        # it — never `gyro_reading(ω, 0.0, zero(Vec3))` trusting the zeros (the `-0.0` trap and float
        # non-associativity). A slice-27/28/29/30 wire is bit-for-bit unchanged BY CONSTRUCTION.
        # ⚠ GYRO NOISE IS ABSENT ON DRAW-TOPOLOGY GROUNDS, not by oversight: a per-tick random rate
        # error is an unconditional THIRD `randn` on a path that has drawn exactly two since slice
        # 25, so it would desync every 25–30 replay (convention 3; the slice-13 `:scan` 4b shape).
        ω_tru_g = get(c, :omega_body, zero(Vec3))::Vec3
        _gyro_on = haskey(c, :gyro_scale_err) || haskey(c, :gyro_bias_y) || haskey(c, :gyro_bias_z)
        s_gyro  = Float64(get(c, :gyro_scale_err, 0.0))
        by_gyro = Float64(get(c, :gyro_bias_y, 0.0))
        bz_gyro = Float64(get(c, :gyro_bias_z, 0.0))
        ω_gyro = _gyro_on ?
                 gyro_reading(ω_tru_g, s_gyro, Vec3(0.0, by_gyro, bz_gyro)) :
                 ω_tru_g
        _sched_on = haskey(c, :radome_ripple_est)
        if _sched_on
            Â_est = Float64(c[:radome_ripple_est])
            k̂_est = Float64(get(c, :radome_ripple_k_est, 12.0))
            ȧz_ff, ėl_ff = radome_compensation_scheduled(R̂_rad, Â_est, k̂_est,
                                                         look_az_c, look_el_c, ω_gyro)
        else
            ȧz_ff, ėl_ff = radome_compensation(R̂_rad, look_az_c, ω_gyro)
        end
    end

    # ⚠ STRUCTURAL BYTE-IDENTITY (the slice-20/21/26 shape): a BRANCH, with the else-arm slice-26
    # VERBATIM — never `ȧz + ȧz_ff` trusting `R̂ = 0 ⇒ Δ = 0.0`. The `-0.0` trap and float
    # non-associativity both apply, and a no-compensator wire must be bit-for-bit slice 26 BY
    # CONSTRUCTION rather than by a zero that happens to cancel. (Measured at gate 0: `R̂ = 0` is
    # bit-identical to the key being absent, `max|Δq| = 0.0` — which is what makes this a KNOB
    # rather than a fidelity rung, by atmosphere.jl's discriminator.)
    if axes === :az_el
        azu, elu, ȧz, ėl = rung === :raw ? (az_m, el_m, ȧz_raw, ėl_raw) :
                                           (az_est, el_est, ȧz_est, ėl_est)
        ω = _comp_on ? los_rate_from_angles(azu, elu, ȧz + ȧz_ff, ėl + ėl_ff) :
                       los_rate_from_angles(azu, elu, ȧz, ėl)
        û = los_unit_from_angles(azu, elu)
    else
        λu, λ̇u = rung === :raw ? (λ_m, λ̇_raw) : (λ_est, λ̇_est)
        # The in-plane foil carries the SAME single physical correction the bend was applied to
        # (`ε` went onto `λ` as well — one bend of one measurement, slice 26), so the elevation
        # feed-forward is what it sees. ω ∥ ±ŷ either way: the slice-25 blindness is untouched.
        ω = _comp_on ? Vec3(0.0, -(λ̇u + ėl_ff), 0.0) :
                       Vec3(0.0, -λ̇u, 0.0)            # slice 11's reconstruction, VERBATIM in shape
        û = Vec3(cos(λu), 0.0, sin(λu))
    end
    c[:seeker_omega] = ω
    c[:seeker_los]   = û

    # Telemetry — phase-3 `observe!` is POST-`empty!(w.env)`, so a direct write survives. All SCALARS
    # (no Array → no `float()` crash in the client). Shipped ONLY on this path (the never-stale
    # discipline), so slices 11/13 wires are byte-identical.
    #
    # `omega_oop` IS THE HEADLINE READOUT: the out-of-plane content of the LOS rate the seeker
    # reports. Under `:pitch_plane` it is EXACTLY 0.0 by construction (ω ∥ ±ŷ) — the blindness made
    # visible, one number, no client-side physics (convention 13).
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(s.id)
    tel["$sid.az_dot_est"]  = _finite_coord(ȧz_est)             # α-β azimuth rate (the new axis)
    tel["$sid.el_dot_est"]  = _finite_coord(ėl_est)             # α-β elevation rate
    tel["$sid.omega_oop"]   = _finite(hypot(ω[1], ω[3]))        # ‖out-of-plane ω‖ — 0.0 on the foil
    tel["$sid.omega_mag"]   = _finite(_norm3(ω))                # ‖ω‖ (the PN driver)
    tel["$sid.sigma_seek"]  = _finite(σ)
    # SLICE 26 — the RADOME readouts, shipped ONLY while the radome is live (the never-stale
    # discipline; a slice-11/13/25 wire is byte-identical). All SCALARS (convention 13 — the client
    # recomputes nothing; convention 6 — `_finite`/`_finite_coord` on every one).
    if _rad_on
        tel["$sid.radome_slope"] = _finite_coord(R_rad)                     # the live knob value
        # ⭐ THE MECHANISM: the boresight error this tick. `ε_el` is the ELEVATION bend — the one
        # that closes the pitch loop (`ε̇_el = +R·cos(look_az)·ω_y`, frames.jl `radome_error`).
        tel["$sid.radome_eps"]    = _finite_coord(ε_el)                     # signed, rad
        tel["$sid.radome_eps_az"] = _finite_coord(ε_az)                     # signed, rad
        tel["$sid.look_angle"]    = _finite(rad2deg(hypot(look_az, look_el)))  # off boresight, deg
        # ⚠ A DIAGNOSTIC, NOT THE MECHANISM (advisor). Once the loop is ringing this ratio is
        # dominated by the cycle's own body-rate feedthrough, so it is a CONSEQUENCE of the ring —
        # the same fact as the body rate, told twice. Never quote it as independent evidence: the
        # STATIC effect of R on the reported rate is small and smooth (0.593 at R = +0.6).
        ω_t = los_rate(tgt.pos - e.pos, tgt.vel - e.vel)
        n_t = _norm3(ω_t)
        tel["$sid.omega_ratio"] = _finite(n_t > 1.0e-12 ? _norm3(ω) / n_t : FINITE_CEIL)
        # SLICE 28 — the SLOPE-CURVE readouts, shipped ONLY while the ripple is authored (the
        # never-stale discipline; a slice-26/27 wire is byte-identical). ⚠ NOTHING ABOVE IS
        # REDEFINED: `radome_slope` still ships `R₀` and slice 27's `radome_residual` below still
        # ships `R₀ − R̂`, so 26/27 wires read the same numbers they always did. The look-angle
        # quantities are ADDED beside them.
        if _ripple_on
            tel["$sid.radome_ripple"] = _finite_coord(A_rip)               # the live knob value A
            # ⭐ THE QUANTITIES THE LESSON IS ABOUT: the LOCAL slope where the seeker is looking —
            # shipped as NUMBERS so the client never evaluates the curve (convention 13; the
            # slice-21 `rho_air` precedent).
            #
            # ⚠ PER AXIS, AND THAT IS NOT A DETAIL (advisor). The curve is applied to EACH look
            # angle separately (`ε_az = f(look_az)`, `ε_el = f(look_el)`), so the two channels have
            # two DIFFERENT gains — `R(look_az)` closes the yaw loop and `R(look_el)` the pitch one
            # (times slice 26's `cos(look_az)`). An earlier draft shipped ONE key evaluated at the
            # TOTAL off-boresight angle `hypot(look_az, look_el)`, which is a THIRD quantity that is
            # the gain of NEITHER channel; it agreed numerically only because this wire holds
            # `look_el ≈ 0`, and it would have reached the HUD and the shots — the places a student
            # reads the lesson — as the wrong number. The number the client shows must be a number
            # the physics uses.
            #
            # ⭐ AND THE PAIR IS THE CHANNEL SPLIT MADE VISIBLE: on a crossing engagement the lead
            # is in AZIMUTH, so these two keys sit at DIFFERENT points on the same glass — which is
            # a signature no CONSTANT slope can produce (a constant gives both channels one slope
            # and rings them together).
            tel["$sid.radome_slope_az"] = _finite_coord(
                radome_slope_curve(R_rad, A_rip, k_rip, look_az))
            tel["$sid.radome_slope_el"] = _finite_coord(
                radome_slope_curve(R_rad, A_rip, k_rip, look_el))
            # SLICE 30 — ⭐⭐ THE NUMBER THE DESIGN RULE AIMS AT: the most negative local slope this
            # glass reaches ANYWHERE (`min(R₀, R₀+2A)`, frames.jl `radome_slope_worst`). Because the
            # radome constraint is ONE-SIDED — only a NEGATIVE residual closes slice 26's loop, a
            # positive one merely de-tunes — a SCALAR `R̂` at or below this value is stable in EVERY
            # engagement, without knowing which engagement will be flown. That is the slice: gain
            # scheduling buys PERFORMANCE, not STABILITY.
            #
            # ⚠ SHIPPED AS A NUMBER because the client must not evaluate the curve (convention 13,
            # the slice-21 `rho_air` / slice-28 `radome_slope_az` precedent) — and it is LIVE for a
            # second reason the HUD depends on: dragging `A` MOVES THE RULE'S OWN TARGET, so a
            # student who deepens the glass silently invalidates the `R̂` they already set.
            # ⚠ A BOUND, NOT A THRESHOLD (§3): the loop needs the residual to reach the ONSET, not
            # merely to be negative, so the envelope goes quiet ABOVE this value (−0.28 vs the rule's
            # −0.33 on the shipped glass). Sufficient, never tight — label it that way in the HUD.
            # ⚠ SIGNED ⇒ `_finite_coord`, not `_finite` (which clamps only the upper bound and would
            # let a large negative slider reach the JSON unclamped — the slice-29 `k̂` catch).
            tel["$sid.radome_slope_worst"] = _finite_coord(radome_slope_worst(R_rad, A_rip))
        end
    end
    # SLICE 27 — the COMPENSATOR readouts, shipped ONLY while the compensator is live (the
    # never-stale discipline; a slice-11/13/25/26 wire is byte-identical). All SCALARS.
    if _comp_on
        tel["$sid.radome_slope_est"] = _finite_coord(R̂_rad)                 # the live knob value R̂
        # ⭐ THE QUANTITY THAT DECIDES, shipped as a NUMBER so the client never subtracts (the
        # slice-21 `rho_air` precedent: physics in GDScript is convention 13's forbidden move).
        # `R − R̂` — what is LEFT driving the parasitic loop after the gyro has had its say. The
        # true slope is read from comp rather than from `R_rad` so this is correct even on a wire
        # that compensates for glass it does not have (residual = −R̂).
        tel["$sid.radome_residual"]  = _finite_coord(Float64(get(c, :radome_slope, 0.0)) - R̂_rad)
        # SLICE 28 — ⭐ THE RESIDUAL THAT ACTUALLY CLOSES THE LOOP once the slope is a CURVE:
        # `R(look) − R̂`, evaluated where the seeker is looking. On a slice-26/27 wire this key is
        # ABSENT (no ripple authored) and `radome_residual` above is the whole story — which is
        # exactly the point of slice 28: that key is a property of the HARDWARE, this one is a
        # property of the ENGAGEMENT.
        # ⚠ ON THE AZIMUTH CHANNEL, named as such rather than called "local": that is the channel
        # a crossing engagement's lead angle moves, and therefore the one whose residual closes the
        # loop that rings here. The elevation channel's residual is `radome_slope_el − R̂`, which the
        # client can read off the two keys above if it ever needs it.
        # ⚠⚠ SLICE 29 GENERALIZES THE SECOND TERM, AND WHICH LOOK ANGLE EACH SIDE USES IS THE WHOLE
        # SLICE. The GLASS bends at the TRUTH look angle (`look_az`, off `û_tru`) — that is physics.
        # The BELIEF is evaluated wherever the compensator evaluates it, which is its OWN bent index
        # (`look_az_c`). So under a schedule this key is `R(look_az) − R̂(look_az_c)`: the same
        # QUANTITY as slice 28's (the engagement residual on the loop-closing axis), with `R̂` no
        # longer constant. ⭐ It is the ONLY version that predicts the outcome — the both-truth
        # version gets two of three measured arms wrong (gate-0 P10c). ⚠ A slice-26/27/28 wire is
        # byte-identical BY GATING (`_sched_on` false ⇒ the expression is slice 28's, character for
        # character), and for a CONSTANT `R̂` the two indices give the same number anyway — which is
        # precisely why slice 27 never had to choose one.
        if _ripple_on
            tel["$sid.radome_residual_az"] = _finite_coord(
                radome_slope_curve(R_rad, A_rip, k_rip, look_az) -
                (_sched_on ? radome_slope_curve(R̂_rad, Â_est, k̂_est, look_az_c) : R̂_rad))
        end
        # SLICE 29 — the SCHEDULE's own readouts, shipped ONLY while it is live (the never-stale
        # discipline; a slice-27/28 wire is byte-identical). All SCALARS, all at the COMPENSATOR'S
        # OWN INDEX, because that is where the belief actually acts.
        if _sched_on
            tel["$sid.radome_ripple_est"] = _finite_coord(Â_est)                 # the live knob Â
            # ⚠ `_finite_coord`, NOT `_finite`: `_finite` clamps only the UPPER bound, so a large
            # NEGATIVE slider value would reach the JSON unclamped. `k̂` is load-validated finite but
            # NOT sign-constrained (nothing divides by it — see the loader), so it is a SIGNED
            # readout and takes the signed clamp, like every other radome scalar (convention 6).
            tel["$sid.radome_ripple_k_est"] = _finite_coord(k̂_est)               # the live knob k̂
            # ⭐ THE SENSITIVITY, NOT A LOOP GAIN — say it that way (the slice's own gate-0
            # correction, made twice). `R̂' = Â·k̂·sin(k̂·look)` sizes and signs what the indexing
            # error costs; the RESIDUAL above is what actually decides. Shipped as a NUMBER so the
            # client never differentiates (convention 13, the slice-21 `rho_air` precedent).
            tel["$sid.radome_sched_slope"] = _finite_coord(
                radome_schedule_slope(Â_est, k̂_est, look_az_c))
            # the scheduled belief PER AXIS, each at ITS OWN channel's index — the compensator-side
            # twin of slice 28's `radome_slope_az`/`_el`, and the channel split seen from the cure.
            tel["$sid.radome_slope_est_az"] = _finite_coord(
                radome_slope_curve(R̂_rad, Â_est, k̂_est, look_az_c))
            tel["$sid.radome_slope_est_el"] = _finite_coord(
                radome_slope_curve(R̂_rad, Â_est, k̂_est, look_el_c))
            # ⭐ THE INDEX ITSELF, beside slice 26's TRUTH `look_angle`: the gap between these two
            # numbers IS the bend, and it is the mechanism made visible. A student who sees only the
            # residual cannot tell why a better model of the glass rings.
            tel["$sid.look_angle_est"] = _finite(rad2deg(hypot(look_az_c, look_el_c)))
            # ⭐⭐ THE MODEL ERROR — A DIAGNOSTIC, AND THE OTHER HALF OF THE SLICE AS A NUMBER. This
            # is the belief compared with the glass AT THE SAME LOOK ANGLE: what an engineer computes
            # on the bench, where there is no bend to index through, and what "how good is my
            # schedule?" naturally means. ⚠ IT IS NOT WHAT CLOSES THE LOOP — `radome_residual_az` is
            # — and the two CROSS OVER, which is the whole slice: the shipped `k̂ = 10` is a BETTER
            # model of the glass than `k̂ = 17` and RINGS, while 17 is a far worse model and stays
            # quiet, because indexed 2.4–2.7° low they land the other way round. Shipped so the
            # comparison is a READING of two core numbers rather than a claim (convention 13); it is
            # a diagnostic in the slice-26 `omega_ratio` sense, and must be labelled as one.
            #
            # ⚠ GATED ON `_ripple_on`, i.e. on THERE BEING GLASS TO COMPARE AGAINST — the same gate
            # `radome_residual_az` carries, so the PAIR ships together or not at all (and a lone
            # half would be exactly the reading the four-way HUD mirror exists to prevent).
            # ⚠⚠ AND THAT GATE IS NOT COSMETIC: `_sched_on` can be true while `_rad_on` is FALSE —
            # compensating for glass you do not have is a REAL configuration (slice 27's docstring),
            # and there `R_rad`/`A_rip`/`k_rip`/`look_az` are all the else-arm ZEROS, so an ungated
            # key would ship `0 − R̂(0) = −R̂₀` computed from a look angle that is not the one anything
            # is looking at — a plausible NUMBER from stale state, which is the slice-21 `_atm_on` /
            # slice-23 stale-readout class this arc has now caught six times. Pinned by a test rather
            # than reasoned about (advisor).
            if _ripple_on
                tel["$sid.radome_model_err_az"] = _finite_coord(
                    radome_slope_curve(R_rad, A_rip, k_rip, look_az) -
                    radome_slope_curve(R̂_rad, Â_est, k̂_est, look_az))
            end
        end
        # The feed-forward the gyro actually contributed this tick, on the loop-closing axis — the
        # MECHANISM made visible beside `radome_eps`, which is the disease it is treating.
        tel["$sid.radome_ff_el"]     = _finite_coord(ėl_ff)                  # rad/s
        # SLICE 31 — the IMPERFECT GYRO's readouts, shipped ONLY while a gyro-error key is authored
        # (the never-stale discipline; a slice-25…30 wire is byte-identical). All SCALARS.
        if _gyro_on
            tel["$sid.gyro_scale_err"] = _finite_coord(s_gyro)               # the live knob s
            tel["$sid.gyro_bias_z"]    = _finite_coord(bz_gyro)              # the live knob b (rad/s)
            # ⭐⭐ THE BELIEF THE LOOP ACTUALLY SEES, shipped as a NUMBER (convention 13 — the client
            # never multiplies physics). A scale-factor error is COMMON-MODE on the feed-forward
            # product `R̂·ω̃`, so what closes the loop is `R̂(1+s)` and NOT the `radome_slope_est` the
            # designer set. ⚠ THAT EQUIVALENCE IS EXACT (gate-0 §1: the same flight to 1e−11 m), which
            # is why this key is the one the HUD must show beside `radome_slope_worst` — a student who
            # reads only the authored belief cannot see why a competent design rings.
            tel["$sid.radome_slope_est_eff"] = _finite_coord(R̂_rad * (1.0 + s_gyro))
            # ⭐ THE DESIGN RULE, RE-AIMED FOR THE GYRO SPEC. Slice 30's rule aims `R̂` at
            # `radome_slope_worst`; with a scale-factor error the rule survives while `R̂(1+s)` clears
            # it, so the aim point becomes `R_worst/(1+s)`. ⚠ Convention 5: `s = −1` (the DEAD GYRO)
            # is inside the reach of a live slider and would divide by zero — floored, and the floor
            # is on the DENOMINATOR rather than on the knob, because `s = −1` must stay FLYABLE (it is
            # slice 26's uncompensated missile, a legitimate degenerate).
            # ⚠ Shipped only where there is glass to aim at (`_ripple_on`), the gate its slice-30
            # companion `radome_slope_worst` carries — a lone half is the stale-readout class.
            _ripple_on && (tel["$sid.radome_aim_gyro"] =
                _finite_coord(radome_slope_worst(R_rad, A_rip) / max(1.0 + s_gyro, 1.0e-6)))
            # ⭐ THE ENGAGEMENT RESIDUAL READ AGAINST THE EFFECTIVE BELIEF — the number that predicts
            # the verdict once the gyro is imperfect.
            # ⚠⚠ SHIPPED ALONGSIDE `radome_residual_az`, WHICH KEEPS SLICE 28's MEANING UNCHANGED
            # (advisor). Slice 28's headline IS that the HARDWARE residual reads exactly 0.000 while
            # the missile rings; folding the gyro into that key would make its meaning depend on which
            # keys happen to be present, and would leave the 28/29/30 verifiers passing by equal
            # values rather than by construction. TWO numbers from the SAME frames that DISAGREE is
            # this arc's own shape (28's hardware-vs-engagement pair, 29's bench-vs-loop pair) — and
            # the HUD must label both.
            if _ripple_on
                tel["$sid.radome_residual_az_eff"] = _finite_coord(
                    radome_slope_curve(R_rad, A_rip, k_rip, look_az) -
                    (_sched_on ? radome_slope_curve(R̂_rad, Â_est, k̂_est, look_az_c) : R̂_rad) *
                    (1.0 + s_gyro))
            end
            # THE OTHER CURRENCY, AS A NUMBER: the constant spurious LOS rate the BIAS injects on the
            # loop-closing axis, `R̂·b` — additive, with no residual to move, and the one term of this
            # sensor that no belief whatsoever can reproduce (`gyro_reading`'s tooth at ω = 0).
            # ⚠ THIS IS THE FORMULA, NOT THE CONSEQUENCE — it is `R̂·b` and nothing else, so it is
            # EXACTLY proportional to `R̂` by construction and must NEVER be used to evidence the
            # amplification claim (that would be the formula restated, convention 11's tautology
            # trap; the first draft of the gate-3 verifier did exactly this and its ratio was
            # 0.3474/0.27 = 1.29 by arithmetic alone). It is a HUD number: what the bias is worth
            # right now, beside the belief that scales it.
            tel["$sid.gyro_inject_az"] = _finite_coord(R̂_rad * bz_gyro)      # rad/s
            # ⭐ THE CLOSED-LOOP CONSEQUENCE, which is a different number: the TRUE LOS azimuth rate.
            # PN drives the MEASURED rate toward zero, so whatever the compensator injects has to be
            # carried by the TRUE geometry — the aim-point error, per frame, with no CPA sampling in
            # it ([[ewsim-missile-verifier-sampling]]: a HIT samples COARSELY, so a frame-sampled
            # miss cannot carry this claim — slice 27's verifier ate exactly that defect and slice
            # 30 states the rule).
            # ⚠ A TRUTH DIAGNOSTIC, exactly like `omega_ratio` beside it, and labelled as one: the
            # seeker never sees this. Closed form rather than a difference of angles, so it carries
            # no finite-difference noise: `d(atan2(dy,dx))/dt = (dx·vy − dy·vx)/(dx² + dy²)`.
            let d = tgt.pos - e.pos, v = tgt.vel - e.vel
                den = d[1] * d[1] + d[2] * d[2]
                tel["$sid.los_azdot_true"] = _finite_coord(
                    den > 1.0e-12 ? (d[1] * v[2] - d[2] * v[1]) / den : 0.0)   # rad/s
            end
        end
    end
    return nothing
end

# The seeker's painted sources (slice-13 `:scan`): the in-plane LOS bearing + `:intensity` lobe
# amplitude of EVERY `:target` AND `:decoy` (the ONLY consumer that sees decoys). Sorted by id so the
# deterministic `power` accumulation order is canonical (the sorted-id house style; the draw itself is
# over cells, source-order-independent). The decoy carries `kind === :decoy`, so this is where the
# seeker CAN be seduced — while `_nearest_target` (radar / autopilot truth / CPA) skips it.
function _scan_sources(w::World, e::Entity)
    srcs = Tuple{Float64,Float64}[]
    for id in sort!(Symbol[id for (id, o) in w.entities if o.kind === :target || o.kind === :decoy])
        o = w.entities[id]
        û = los_unit(e.pos, o.pos)
        push!(srcs, (atan(û[3], û[1]), Float64(get(o.comp, :intensity, 1.0))))
    end
    return srcs
end

# The nearest `:decoy` to the missile — for the seduced-LOS telemetry/visual only (NOT the truth path;
# `_nearest_target` still governs miss/CPA). `nothing` if the scenario ships no decoy.
function _nearest_decoy(w::World, e::Entity)
    best = nothing; bestR = Inf
    for id in sort!(Symbol[id for (id, o) in w.entities if o.kind === :decoy])
        R = _range(w.entities[id].pos, e.pos)
        R < bestR && (bestR = R; best = w.entities[id])
    end
    return best
end

# The slice-13 `:scan` seeker — the slice-3 CFAR RANGE sandbox lifted onto the LOS-ANGLE axis. Instead
# of ONE noisy truth bearing, the seeker forms a NOISY angular-power PROFILE over a FIXED grid, CFAR-
# detects the peaks (target + decoy lobes), and resolves the tracked bearing by the `discrimination`
# rung (`:none` blend-all → SEDUCED; `:gated` α-β-predicted NN gate → the decoy REJECTED). THE DRAW
# TOPOLOGY FLIPS: `_draw_profile!` draws EXACTLY `2·N_p·N_bins` randn EVERY tick (incl. tick 1, over the
# FIXED grid → decoy-count-independent, convention 3) — vs the point path's 1. The measurement NOISE
# MOVED into the profile floor, so there is NO `+σ·randn` output draw and the slice-11 `sigma_seek`
# slider goes INERT here (the live noise knob is now the profile SNR / `pfa`). PN consumes the α-β
# estimate (like `:filtered`); the gate reuses the α-β PREDICTED bearing as its center = the RGPO
# track-gate. CUED-LOCK precondition (the load-bearing seam): tick-1 seeds the α-β from the TRUTH LOS
# to `_nearest_target` (which excludes `:decoy`) so the track starts ON the target — robust even with
# the decoy present at t=0; a tick-1 peak-pick seed could land on a brighter decoy and INVERT the lesson.
function _observe_scan!(s::Seeker, w::World, e::Entity, c::AbstractDict)
    dt = Float64(get(c, :dt_s_seeker, 1.0e-3))
    α  = Float64(get(c, :alpha, 0.30))
    β  = Float64(get(c, :beta,  0.05))

    # Static scan config (load-validated; read with the FINDINGS-pinned defaults at the consumer).
    N_bins   = Int(get(c, :scan_n_bins, 64))
    bin_w    = Float64(get(c, :scan_bin_width, 0.005))
    σ_beam   = Float64(get(c, :scan_sigma_beam, 0.015))
    floor    = Float64(get(c, :scan_floor, 1.0))
    n_pulses = Int(get(c, :scan_n_pulses, 10))                 # SAME N_p feeds the draw AND cfar_scan
    variant  = Symbol(get(c, :scan_cfar_variant, :ca))
    n_train  = Int(get(c, :scan_cfar_ntrain, 16))
    n_guard  = Int(get(c, :scan_cfar_nguard, 4))
    pfa      = Float64(get(c, :scan_cfar_pfa, 1.0e-3))
    hw       = Float64(get(c, :gate_halfwidth, 0.045))
    disc     = get(w.fidelity, :discrimination, :none)         # DEFAULT :none — the button reveals the fix

    tgt = _nearest_target(w, e)                                # truth target (decoy excluded by kind)

    # CUED-LOCK: tick-1 seed the α-β from the TRUTH LOS to the true target (NOT a peak pick). λ̇ = 0.
    if !get(c, :seek_init, false)
        λ0 = 0.0
        if tgt !== nothing
            û0 = los_unit(e.pos, tgt.pos); λ0 = atan(û0[3], û0[1])
        end
        c[:seek_lambda_est]    = λ0
        c[:seek_lambdadot_est] = 0.0
        c[:seek_lambda_prev]   = λ0            # keep the raw memory warm (inert under :scan; harmless)
        c[:seek_init]          = true
    end

    λ_est = Float64(c[:seek_lambda_est]); λ̇_est = Float64(c[:seek_lambdadot_est])
    λ_pred = λ_est + λ̇_est * dt                # the α-β prediction = grid BORESIGHT + the gate center

    # Paint the FIXED grid centered on the prediction (tracking boresight; draw count is boresight-
    # independent), then DRAW the noisy floor — the 2·N_p·N_bins topology flip, EVERY tick incl. tick 1.
    grid  = angular_grid(λ_pred, N_bins, bin_w)
    power = Vector{Float64}(undef, N_bins)
    paint_angular_profile!(power, grid, _scan_sources(w, e); σ_beam = σ_beam, floor = floor)
    z = Vector{Float64}(undef, N_bins)
    _draw_profile!(z, power, w.rng, n_pulses)

    # CFAR-detect (the slice-3 sandbox, UNCHANGED) → cluster into (λ, strength) peaks.
    _, detections = cfar_scan(z; variant = variant, n_train = n_train,
                              n_guard = n_guard, pfa = pfa, n_pulses = n_pulses)
    peaks = extract_peaks(grid, z, detections)

    # Resolve the tracked bearing by the discrimination rung; COAST on the prediction if none is kept
    # (empty peaks, or `:gated` finds nothing in-gate) — λ_meas = λ_pred → the α-β innovation is EXACTLY
    # 0 (a clean dead-reckon on the prediction, never "track nothing"). The rung is DRAW-INVARIANT here:
    # both paths ran the SAME paint + SAME 2·N_p·N_bins draws; they differ ONLY in this peak SELECTION.
    sel    = disc === :gated ? validation_gate(peaks, λ_pred, hw) : intensity_centroid(peaks)
    λ_meas = sel === nothing ? λ_pred : sel

    # The EXACT slice-11 α-β update on the resolved bearing (the gate reuses this state next tick).
    λ_est, λ̇_est = alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α = α, β = β)
    c[:seek_lambda_est]    = λ_est
    c[:seek_lambdadot_est] = λ̇_est

    # PN consumes the α-β estimate (like `:filtered`); reconstruct ω/û from it. `decide!` supplies Vc.
    c[:seeker_omega] = Vec3(0.0, -λ̇_est, 0.0)
    c[:seeker_los]   = Vec3(cos(λ_est), 0.0, sin(λ_est))

    # Telemetry — SCALARS only (no Array → no `float()`-crash); the profile/detections are NOT shipped.
    λ_tgt = 0.0
    if tgt !== nothing
        ût = los_unit(e.pos, tgt.pos); λ_tgt = atan(ût[3], ût[1])
    end
    dcy   = _nearest_decoy(w, e)
    λ_dcy = 0.0
    if dcy !== nothing
        ûd = los_unit(e.pos, dcy.pos); λ_dcy = atan(ûd[3], ûd[1])
    end
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(s.id)
    tel["$sid.lambda_used"]     = _finite_coord(λ_meas)             # the resolved bearing PN tracked
    tel["$sid.lambda_est"]      = _finite_coord(λ_est)              # α-β estimate
    tel["$sid.lambda_dot_used"] = _finite_coord(λ̇_est)             # the rate PN consumed
    tel["$sid.target_bearing"]  = _finite_coord(λ_tgt)             # truth LOS to the TRUE target
    tel["$sid.decoy_bearing"]   = _finite_coord(λ_dcy)             # truth LOS to the nearest decoy
    tel["$sid.aim_error"]       = _finite(abs(wrap_angle(λ_est - λ_tgt)))  # THE headline (FINDINGS #1)
    tel["$sid.n_peaks"]         = length(peaks)                    # CFAR peak count (int scalar)
    tel["$sid.gated"]           = disc === :gated ? 1.0 : 0.0      # the active discrimination rung
    return nothing
end

# --- the SALVO COORDINATOR: the cooperative-guidance shared-state seam (slice 14, HANDOFF §10 item 13) --
# The CAPSTONE's NEW phase-2 `build_env!` subsystem, on a non-physical `kind === :datalink` entity (no
# mover — it never integrates). It realizes "N interceptors SHARING STATE" literally: it reads the truth
# time-to-go of every `kind === :missile` interceptor over an IDEAL datalink (zero-latency, lossless),
# reduces them to the team consensus `T_d = max_j t_go_j` ONCE at launch, and publishes the shared
# REMAINING desired time-to-go `w.env[:salvo_t_d] = T_d − w.t` each tick as the SINGLE writer. Each
# `Autopilot.decide!` (phase 4) only READS it; build_env! (phase 2) runs post-`empty!(w.env)`, so the
# field survives to phase 4 (the slice-4 jammer / slice-8 energy telemetry-phase precedent).
#
# FIXED-AT-LAUNCH consensus (gate-0 FINDINGS — the robustness default, advisor): T_d is computed ONCE
# (the `e0_j` lazy-latch precedent) and republished as `T_d − w.t`. A per-tick `max t_go` recompute — and
# every continuous-ratchet variant — was REJECTED by probe8/9: cooperative guidance induces the very
# stretch maneuver that collapses each missile's V_c and INFLATES its `t_go = R/V_c`, so a live consensus
# self-pollutes and runs T_d away (to ~99–105 s). The one-shot launch exchange IS the state-sharing; each
# missile then independently tracks `(T_d − t_now)`. NAMED APPROXIMATION: the ideal datalink — a
# noisy/latent/lossy link + consensus filtering is the HANDOFF §11 Tier-C horizon (DEFERRED, convention 9).
#
# DETERMINISM (class 4c — the slice-12 shape, NOT slice-13's 4b): NO RNG (a deterministic max over truth
# t_go), so "draw-count invariance" is VACUOUS (do NOT copy slice-13's draw language). Byte-identity for
# slices 1–13 is BY CONSTRUCTION — the coordinator exists ONLY in a slice-14 salvo scenario; absent a
# `:datalink` entity nothing writes `salvo_t_d`, and under `cooperation ∈ {unset, :solo}` nothing reads it.
# It adds NO draw anywhere and touches no shared symbol on the detection path.
#
# THE TEAM SET is gathered by `kind === :missile` (the esm/gps count-by-kind precedent — never hard-coded
# ids), sorted for a canonical order; each interceptor's target is its own `_nearest_target` (the single
# common `:target`; `:decoy`/`:datalink` excluded by that filter's `kind === :target`). So N missiles never
# target each other or the datalink node — miss/CPA is ALWAYS vs the true target (the truth-path invariant).
struct SalvoCoordinator <: Subsystem
    id::Symbol
end

function build_env!(sc::SalvoCoordinator, w::World)
    e    = w.entities[sc.id]
    c    = e.comp
    mids = sort!(Symbol[id for (id, o) in w.entities if o.kind === :missile])   # the interceptor team
    isempty(mids) && return nothing                          # no interceptors → nothing to coordinate

    # Each interceptor's truth time-to-go vs its own nearest `:target` (decoy/datalink excluded by kind);
    # VC_FLOOR-guarded finite (a stretching missile's V_c → 0 can't blow up t_go → no Inf/NaN, convention 6).
    t_gos = Float64[]
    for mid in mids
        m   = w.entities[mid]
        tgt = _nearest_target(w, m)
        tgt === nothing && continue                          # a missile with no target contributes no t_go
        Vc  = -range_rate(tgt.pos - m.pos, tgt.vel - m.vel)  # closing speed (POSITIVE when closing)
        push!(t_gos, time_to_go(los_range(m.pos, tgt.pos), Vc))
    end
    isempty(t_gos) && return nothing

    # FIXED-AT-LAUNCH T_d: latch ONCE on the first build_env! (post-first-integrate — a ~1·dt shift from
    # the pure-launch state, the only clean option since integrate! runs first; survives `reset` via the
    # reloaded comp). Republish the shared REMAINING time every tick. `salvo_consensus` = max (the SLOWEST
    # missile — the only common time all can reach, since a missile can stretch but not shorten). Store a
    # raw Float64 for the phase-4 read (T_d, w.t both finite ⇒ the difference is finite); the telemetry
    # copy below is `_finite`-clamped. w.t = (i−1)·dt here (pre-increment), so tick 1 publishes T_d.
    haskey(c, :salvo_td) || (c[:salvo_td] = salvo_consensus(t_gos))
    T_d = Float64(c[:salvo_td])
    w.env[:salvo_t_d] = T_d - w.t

    # Telemetry — SCALARS only (no Array → no `float()`-crash): the shared field + the fixed T_d. The
    # per-missile ARRIVAL time is NOT stamped here: geometry F is an AIR intercept (target at altitude),
    # so the missile reaches CPA and COASTS PAST — the `BallisticMissile` :impact (ground, z≤0) fires
    # only on the later fall, NOT at the intercept. The Δτ metric is therefore the first-CPA time of each
    # missile's `los_range` stream (already on the wire from `Autopilot.decide!`), computed CONSUMER-side
    # by the verifier/tests (the slice-10..12 miss-distance discipline; [[ewsim-missile-verifier-sampling]]'s
    # descending-band first-CPA) — not a core stamp. The coordinator stays single-purpose (publish `salvo_t_d`).
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(sc.id)
    tel["$sid.salvo_t_d"] = _finite_coord(w.env[:salvo_t_d])  # remaining consensus (signed: <0 past T_d)
    tel["$sid.T_d"]       = _finite(T_d)                      # the fixed launch consensus
    return nothing
end
