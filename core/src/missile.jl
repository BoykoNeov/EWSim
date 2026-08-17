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
    # SLICE 32 — the SEEKER FOV marker, and it has the SAME job for the SAME reason: drop the shared
    # button. Slice 26's argument transfers VERBATIM and that is why it is worth restating rather
    # than cross-referencing — a FOV wire is also a two-angle host, so the inherited cycler would
    # again be slice 25's `seeker_axes`, whose other position (`:pitch_plane`) leaves the WINDOW LIVE
    # on a missile that ALSO misses by 2000 m for a wholly unrelated reason. Two mechanisms in one
    # view is what convention 9 exists to prevent.
    #
    # ⚠ IT IS A SEPARATE MARKER, NOT A REUSE OF `radome_view`, because the two select different HUD
    # BRANCHES (the radome cascade reads `radome_slope`/`radome_residual`, none of which a FOV wire
    # has — reading them would ship 0.0 into a label, the stale-readout class this arc has caught
    # seven times). The BUTTON outcome is identical either way, so a wire carrying BOTH is safe on
    # that axis; the client resolves the HUD order explicitly and says why at the branch. Such a wire
    # is NOT client-drivable today (the corollary lives in `test_missile.jl` — a second mechanism,
    # convention 9), so the order is a statement of intent, not a shipped path.
    any(haskey(w.entities[m].comp, :seeker_fov_deg) for m in missiles) &&
        (info[:seeker_fov_view] = true)
    # SLICE 34 — the GIMBALLED HEAD marker, and it exists because the LOADER'S REFUSAL LEAVES A HOLE
    # THE CLIENT WOULD FALL THROUGH SILENTLY (gate-3 review, advisor). `scenario.jl` refuses
    # `seeker_fov_deg` beside `gimbal_tau_s` — a gimballed seeker has no body-fixed window — so a
    # gimbal wire raises `radome_view` (it HAS glass) and NOT `seeker_fov_view`. Without a marker of
    # its own the client's dispatch would fall past both FOV branches into slice 26/27/28's RADOME
    # cascade.
    #
    # ⚠⚠ AND THAT FAILURE IS WORSE THAN THE STALE-READOUT CLASS THIS ARC HAS CAUGHT EIGHT TIMES,
    # because nothing in it is stale: a gimbal wire carries `radome_slope`, `radome_residual*`,
    # `radome_slope_worst` and `omega_q`/`omega_r`, so every number that cascade reads is LIVE and
    # PLAUSIBLE. It would print a confident ring/quiet verdict about the GLASS on a wire whose whole
    # subject is the HEAD — the wrong subject, drawn from real telemetry, and not one test would
    # fail. Slice 33's composition branch is the precedent for the fix and the reason it is a
    # SEPARATE key rather than a reuse: the branches read DIFFERENT quantities, and a gimbal wire has
    # neither `seeker_fov_deg` nor `seeker_fov_margin_deg` (the seam ships `gimbal_fov_deg` /
    # `gimbal_fov_margin_deg`, about the HEAD axis, and `head_off_deg` rather than a body look).
    #
    # ⚠ THE BUTTON OUTCOME NEEDS NO EDIT AT EITHER CLIENT SITE — `radome_view` is raised here too and
    # already drops it, exactly as slice 33 found for its own composition. What this marker selects is
    # the HUD BRANCH ALONE, which is the half that is NOT identical.
    any(haskey(w.entities[m].comp, :gimbal_tau_s) for m in missiles) && (info[:gimbal_view] = true)
    # SLICE 35 — the RATE-LIMITED SERVO marker. ⚠⚠ THE MARKER-HOLE RE-CHECK THE PLAN DEMANDED CAME
    # BACK **NEGATIVE**, AND THAT NEGATIVE RESULT IS WORTH MORE THAN THE KEY BELOW. Slice 34's marker
    # was load-bearing against a REAL HOLE: the loader refuses `seeker_fov_deg` beside a head, so a
    # gimbal wire raises neither FOV marker and would have fallen THROUGH both branches into slice
    # 26/27/28's radome cascade — a fluent verdict about the GLASS on a wire whose subject is the
    # HEAD. Nothing of the kind happens here. A slice-35 wire is a slice-34 wire PLUS one key: the
    # loader refuses nothing extra, `gimbal_view` is raised and routes correctly, and the branch it
    # selects is about the HEAD, which is still the right subject.
    #
    # ⇒ THIS MARKER IS A BRANCH SELECTOR, NOT A HOLE PLUG, and the distinction is written down here
    # so the next slice does not learn the wrong rule from the fact that both slices added a key.
    # What it selects is the half slice 34's HUD cannot say: slice 34's lines pair the head's
    # TRACKING ERROR against the DETECTOR WINDOW, which on this wire is authored wide and never
    # binds — so that HUD would report a comfortable budget and never mention the SERVO, which is
    # the entire subject. The numbers it draws would all be true; the slice would simply be invisible.
    #
    # ⚠ A HANDSHAKE MARKER RATHER THAN A TELEMETRY VALUE-GUARD, and the reason is not only that every
    # view decision in this family is made at the handshake: `gimbal_rate_dps` ships the FINITE_CEIL
    # sentinel on a slice-34 wire (convention 6 — never an `Inf` on the JSON), so a value-guard would
    # be a MAGIC-NUMBER compare against 1e9, which is exactly the shape this arc keeps replacing with
    # measured quantities.
    # ⚠ THE BUTTON NEEDS NO EDIT AT EITHER CLIENT SITE — `radome_view` and `gimbal_view` are both
    # raised here and either already drops it (slice 33's finding, third occurrence).
    any(haskey(w.entities[m].comp, :gimbal_rate_dps) for m in missiles) &&
        (info[:gimbal_rate_view] = true)
    # SLICE 36 — the HANDOVER BASKET marker. ⚠⚠ THE RE-CHECK CAME BACK **POSITIVE**, AND IT IS THE
    # STRONGER OF THE TWO POSSIBLE ANSWERS: this marker does slice 34's job AND slice 32's, which is
    # exactly what slice 35's did NOT do ("a BRANCH SELECTOR, not a hole plug" — do not carry that
    # sentence forward to this key). Two independent failures, and the FIRST is the one no earlier
    # slice of this arc could have had:
    #
    # ⚠⚠ (1) THE BUTTON DROP STOPS BEING FREE, because THIS IS THE FIRST NO-GLASS WIRE OF THE ARC.
    # `radome_view` above is raised by `haskey(:radome_slope)` and slices 26–35 all had glass, so every
    # one of them got the drop for free by riding it (slice 33 wrote that down as a finding and 34/35
    # inherited it). Slice 36 drops the glass — for §0.2's exact-inertness and §0.6's isolation reasons,
    # a decision internal to this slice — so `radome_view` is ABSENT here, and `seeker_fov_view` is
    # absent too because `scenario.jl` REFUSES `seeker_fov_deg` beside a head. Both of the client's
    # drop-the-button branches therefore fail, its dispatch falls through to slice 25's `seeker_axes`
    # cycler, and the button comes BACK — whose other position (`:pitch_plane`) would leave the handover
    # error LIVE beside slice 25's unrelated 2000 m blind miss. That is slice 26's own argument, and it
    # is the reason the drop needs BOTH client sites (its 4th occurrence).
    #
    # ⚠⚠ (2) AND THE HUD WOULD BE SLICE 35's, WHICH ON THIS WIRE PRINTS TWO ZEROS FOR GLASS THAT DOES
    # NOT EXIST. `gimbal_rate_view` IS raised here (the servo is this slice's one slider), so slice 35's
    # branch takes the wire, and its own line 4 — the one it calls THE CURE — reads `radome_slope_est`
    # and `radome_slope_worst`. Neither is shipped without a compensator and a ripple, so it renders
    # `R̂ +0.000   aim point R₀+2A +0.000`: the stale-readout class this arc has now caught nine times,
    # landing on another slice's payoff line. ⇒ not merely an INVISIBLE slice (slice 35's failure mode,
    # where every number is true and the subject is unmentioned) but an invisible slice PLUS two
    # fabricated numbers.
    #
    # ⚠ KEY-GATED on the comp key, exactly as the four markers above are, so a slice-26..35 wire is
    # byte-identical and a slice-36 wire is recognized by the one thing that distinguishes it.
    any(haskey(w.entities[m].comp, :gimbal_handover_err_deg) for m in missiles) &&
        (info[:gimbal_handover_view] = true)
    # SLICE 37 — the SERVO REFERENCE FRAME marker, and ⭐⭐ IT IS THE FIRST OF THIS FAMILY WHOSE JOB IS
    # TO **UN-DROP** THE SHARED FIDELITY BUTTON. Every marker above exists to DROP it: slices 26–36
    # each had no rung to cycle (the lesson was a slider every time), so `radome_view`,
    # `seeker_fov_view` and `gimbal_handover_view` all hide it, and 32/33/34/35 rode one of them for
    # free. `:seeker_head` IS a genuine two-rung fidelity — the first since slice 25 — so on this wire
    # the button is the LESSON, and the client's dispatch would otherwise hide it three times over
    # (this wire raises `radome_view`, `gimbal_view` AND `gimbal_rate_view`).
    #
    # ⚠⚠ SO THE FAMILY'S RULE INVERTS HERE AND THAT SENTENCE IS THE POINT OF THIS COMMENT: a later
    # slice reading only the five markers above would learn *"a gimbal marker drops the button"*, and
    # would then be unable to ship a rung on this wire without re-deriving why. The rule is not "drop";
    # it is *the button shows what there is to cycle, and these wires mostly have nothing*.
    #
    # ⚠ GATED ON THE **FIDELITY**, NOT ON A COMP KEY — the first marker in this family that is, and
    # deliberately, because the thing that distinguishes a slice-37 wire IS the rung. A comp-key gate
    # is not available at all here (there is no slice-37 comp key: the rung reuses slice 34's head),
    # and a value-guard on `:space_stabilized` would be WRONG in the one direction that matters — this
    # wire OPENS on `:body_referenced` (the good design, so the press is what breaks it), so gating on
    # the non-default rung would hide the button on exactly the arm the showcase starts from.
    # ⚠ The loader REFUSES `seeker_head` without a head for EITHER rung (`scenario.jl`), so this can
    # never be raised on a wire with no servo to talk about, and slices 1–36 author no such key ⇒ they
    # are byte-identical and their markers are untouched.
    haskey(w.fidelity, :seeker_head) && (info[:gimbal_frame_view] = true)
    # ⭐⭐ SLICE 38 — AN IMPERFECT HEAD GYRO, the 8th marker of this family, and it exists for the HUD
    # rather than for the button. A slice-38 wire is a slice-37 wire PLUS one comp key, so it raises
    # `gimbal_frame_view` too and the button is ALREADY correct there (the rung is live and it is one
    # end of this slice's own axis — pressing it is meaningful here in a way it is not on 32–36).
    # ⚠⚠ WHAT IS **NOT** CORRECT IS THE HUD, AND THAT IS THE ~10th OCCURRENCE OF THE STALE-READOUT
    # CLASS (advisor, predicted before any client code): slice 37's block is a FRAME COMPARISON whose
    # cure line names `radome_slope_est` against `radome_slope_worst`. Every key it reads is LIVE on
    # this wire, so it would print a fluent, entirely true verdict about the SERVO'S FRAME on a wire
    # whose subject is the GYRO — slice 34's own worst form, where nothing is stale.
    # ⇒ this is slice 35's "a BRANCH SELECTOR, not a hole plug", and the branch must be checked FIRST
    # at BOTH client sites for the reason slice 37 wrote down: this wire raises `radome_view`,
    # `gimbal_view`, `gimbal_rate_view` AND `gimbal_frame_view`, so any later branch wins.
    # ⚠ GATED ON THE COMP KEY, not on the fidelity, and that is the OPPOSITE choice from slice 37's
    # one line above — for the same reason it made its own: what distinguishes THIS wire is the
    # imperfect gyro, which is a comp key, and the rung is shared with slice 37.
    any(haskey(w.entities[m].comp, :head_gyro_scale_err) ||
        haskey(w.entities[m].comp, :head_gyro_bias_y)   ||
        haskey(w.entities[m].comp, :head_gyro_bias_z) for m in missiles) &&
        (info[:gimbal_gyro_view] = true)
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

    # SLICE 34 — THE GIMBALLED HEAD, AND THE INDEX THAT LOOKS AT ITSELF. Slices 26–31 built the
    # parasitic loop on one geometric fact: the radome bends the ray by an amount set by the LOOK
    # ANGLE, and the look angle is the LOS measured off the missile's OWN NOSE — a quantity the
    # missile can only move by ROTATING, which is exactly why slice 26 is a BODY-RATE instability.
    # A GIMBALLED SEEKER BREAKS THAT IDENTITY. Its head has its own pointing angles, the ray passes
    # through the part of the dome the HEAD is aimed at, and — this is the whole slice — the head is
    # aimed by the very measurement the dome just bent. The index of the glass becomes a FIXED POINT
    # of the glass, so part of the bend's own variation is absorbed by the head's pointing instead of
    # being handed to guidance: slice 26's loop is partly re-closed through the HEAD, where its sign
    # is NEGATIVE. See `docs/plans/slice34.md`.
    #
    # ⚠⚠ AND THE MARGIN IS NOT BOUGHT BY THE SERVO LAG — gate 0 measured that and the distinction is
    # the slice. Under the head that actually ships (the one tracking its own BENT measurement) τ
    # does NOT move the onset anywhere in [0.02, 0.2]; only the amplitude sags, which is why `τ` is
    # AUTHORED and not a slider. And the ISOLATION arm carried the same ONE-TICK SAMPLING DELAY on
    # the TRUTH LOS and reproduced the truth-tracking head to three decimals at every R̂ (0.40752 vs
    # 0.40798, 0.69399 vs 0.69538, 0.97186 vs 0.97277) while the bent head departed from both ⇒ THE
    # MARGIN IS BOUGHT BY THE INDEX, not by the delay. A slice resting on a one-tick lag would be
    # resting on noise (§0.5).
    #
    # ⚠ THREE SEAM DISCIPLINES, and they are the physics rather than housekeeping:
    #   1. THE HEAD SLEWS BEFORE THE BEND IS TAKEN (this block sits ABOVE the radome). The other
    #      ordering leaves a one-tick lag that SURVIVES τ → 0 and would fake exactly the mechanism
    #      §0.5 measured to be worth nothing.
    #   2. THE SERVO TRACKS THE BENT, ONE-TICK-DELAYED MEASUREMENT (`:head_tgt_*`, stored below,
    #      AFTER `az_m`/`el_m` are formed). A real head slews on its own detector's error signal, and
    #      slice 27's rule names why ("compensate with a signal that is not itself corrupted by what
    #      you are compensating"). The `:truth`-tracking variant was measured at gate 0 and does NOT
    #      ship. ⚠ There is deliberately NO FALLBACK to the truth angles here (advisor): `:head_az`
    #      and `:head_tgt_az` are minted on the SAME tick by the handover below and by the store
    #      below it, so the else-arm indexes both directly. A `get(c, :head_tgt_az, look_az_b)`
    #      fallback would put a TRUTH read on the one path whose whole thesis is that the head never
    #      sees truth — un-exercised, and fake if it ever ran.
    #   3. THE DETECTOR WINDOW IS EVALUATED TWICE, AGAINST DIFFERENT QUANTITIES, and collapsing them
    #      changes the physics: the SLEW is gated on the error BEFORE this tick's slew (there is no
    #      error signal to slew on if the target was already out), AVAILABILITY on the error AFTER.
    #      When the target is outside the window the head HOLDS — no error signal, no slew — which is
    #      the α-β tracker's coast one layer out, and the mechanism behind §0.7's METRIC INVERSION:
    #      a broken window FREEZES the index, and a frozen index is QUIET at every R̂ (§0.4), so
    #      `rms r` FALLS while the miss opens. ⇒ no stability verdict may be read on a windowed arm.
    #
    # ⚠ RUNG-GATED ON THE LIVE `:airframe`, never on `haskey(:head_az)` — the slice-21 `_atm_on` /
    # 23 / 26 / 27 / 29 / 32 latent-bug class, whose SEVENTH occurrence this would be. `:head_az` is
    # minted here and NEVER deleted, so a key-gated head would keep slewing (and keep indexing the
    # glass) off a FROZEN attitude after a cross-toggle off `:six_dof`. ⭐ And the head and the
    # attitude it is measured against are gated by the SAME rung — `:att_q` is written only by
    # `_integrate_6dof!`, which is itself rung-gated — so they freeze and resume TOGETHER; the head
    # never runs against an attitude from a different plant. `haskey(:att_q)` stays ONLY as a crash
    # guard (convention 5), it is not the semantic gate.
    #
    # ⚠ A BODY-FIXED `seeker_fov_deg` IS REFUSED ALONGSIDE THIS AT LOAD (`scenario.jl`, the slice-21
    # "refused rather than silently branch-ordered" precedent), so the `elseif` on the availability
    # branch below is unreachable from any YAML. A gimballed seeker has no body-fixed window: the
    # STOP is that limit, and slice 32's key under a head would be an unmodelled THIRD window.
    #
    # ⭐⭐ SLICE 37 — THE SERVO'S REFERENCE FRAME, and the deferral's own wording was REFUTED before
    # any probe ran. `docs/plans/slice34.md:931` named this slice as *"a rate-stabilized head
    # measures inertial LOS rate DIRECTLY"* — and line 1652 above is `az_el(û_tru)`, NOT
    # `look_angles(att, û_tru)`: this seeker has reported INERTIAL LOS angles since slice 25 and the
    # α-β tracker an INERTIAL rate, so the shipped model is ALREADY a perfectly body-motion-isolated
    # MEASUREMENT and the promised headline cannot be shipped. What is body-referenced is the SERVO —
    # `head_tgt = look_angles(att, …)` and `head_slew_full` rate-limits its step in BODY coordinates,
    # so the servo's job includes TRACKING OUT the missile's own rotation. `:space_stabilized` holds
    # the head's pointing in the INERTIAL frame instead (head-mounted rate gyros), and body motion is
    # REJECTED PASSIVELY rather than tracked out. See `docs/plans/slice37.md` PART II.
    #
    # ⚠⚠ AND IT REMOVES MARGIN RATHER THAN ADDING IT — THE CLASSICAL REASON GIMBALS EXIST INVERTS ON
    # THIS WIRE. The position servo's LAG WAS DOING STABILITY WORK: it LOW-PASSES body motion out of
    # the glass's INDEX (measured against `1/√(1+(2πfτ)²)` to 3–4 digits, against UNITY GAIN exactly
    # at every frequency for the stabilized head), and slice 26's limit cycle lives at 1.7–2.1 Hz
    # where that filter is worth 12–16 % of gain and ~30° of phase. Stabilizing gives back ≈40–45 %
    # of the margin slice 34's gimbal bought, AT THE SHIPPED τ = 0.05 (gate 1 measured BOTH terms
    # moving with τ: the honest range over `τ ∈ [0.005, 0.2]` is 0 % to 79 %).
    #
    # ⚠⚠ RUNG-GATED ON THE LIVE `:airframe` THROUGH `_gim`, NEVER ON `haskey(c, :head_i_az)` — the
    # latent-bug class this arc has caught SEVEN times (21's `_atm_on`, 23, 26, 27, 29, 32, 34), and
    # here it would be WORSE than every earlier occurrence: a cross-toggle off `:six_dof` FREEZES the
    # attitude, and a frozen attitude makes the body↔inertial conversion the IDENTITY — so the two
    # rungs would silently BECOME EACH OTHER rather than visibly break.
    _six = get(w.fidelity, :airframe, :point_mass) === :six_dof
    _gim = haskey(c, :gimbal_tau_s) && haskey(c, :att_q) && _six
    _stab = _gim && get(w.fidelity, :seeker_head, :body_referenced) === :space_stabilized
    # ⭐⭐ SLICE 40 — THE SERVO'S ORDER. Slices 34–39's head is a FIRST-ORDER LAG with a rate limit;
    # a real gimbal has INERTIA, so its servo is second-order (`frames.jl HEAD_SERVO_MODES`). That
    # is a new MECHANISM rather than a refinement, because a first-order lag is BOUNDED in both
    # currencies — index gain ≤ 1 and phase ≥ −90°, at every frequency for every τ — so it could
    # only ever make the glass's index quieter, which is exactly how slice 37's margin was bought.
    # A second-order servo leaves both bounds, and on slice 34's own shipped design TWO of them ring
    # with index gains 32× APART (3.073 and 0.095, against the shipped lag's 0.882) ⇒ neither number,
    # read at a fixed frequency, orders the outcome. See `docs/plans/slice40.md`.
    #
    # ⚠⚠ RUNG-GATED THROUGH `_gim` ON THE LIVE `:airframe`, never on `haskey(c, :gimbal_omega_hz)` —
    # the latent-bug class this arc has caught EIGHT times (21's `_atm_on`, 23, 26, 27, 29, 32, 34,
    # 37). The rate state below is minted here and never deleted, so a key-gated servo would keep
    # integrating an inertia against a FROZEN attitude after a cross-toggle off `:six_dof`.
    _so = _gim && get(w.fidelity, :head_servo, :first_order) === :second_order
    look_az_b = 0.0; look_el_b = 0.0     # the LOS in the BODY frame — what a STRAPDOWN seeker indexes
    head_az   = 0.0; head_el   = 0.0     # the HEAD's pointing angles, in the body frame
    off_head  = 0.0; fov_h     = 0.0     # the detector's off-head-axis error, and its window
    # SLICE 35 — the SERVO's own two numbers: the STEP it was asked for this tick (radians,
    # post-gain, pre-limit, pre-stop) and whether `rate_max` actually bound. ⚠ THEIR ZERO INITIALISER
    # IS LOAD-BEARING ON TWO PATHS AND IS NOT DEFENSIVE PADDING. (1) THE HANDOVER tick calls
    # `head_clamp` and never `head_slew`, so there is no demand to report and tick 1 ships 0 — a
    # verifier reading tick 1 sees a zero that is the ABSENCE of a slew, not a quiet servo. (2) When
    # the target is OUTSIDE the detector window the head HOLDS (seam discipline 3), so again nothing
    # is demanded and nothing saturates: `head_rate_sat` reads 0 on a BROKEN arm for exactly the
    # reason `rms r` falls there, which is why the plan's two-run discipline covers FOUR quantities
    # and not slice 34's three. A frozen head does not saturate.
    head_dem  = 0.0; head_sat  = false
    # SLICE 40 — the second-order servo's RATE STATE (rad/s, in whichever frame the pointing is
    # held in) and its two authored numbers. ⚠ THE LOCALS EXIST ON BOTH RUNGS AND THE STATE IS
    # PERSISTED ONLY ON THE SECOND-ORDER ONE: a first-order head HAS no rate state, which is why
    # entering this rung mid-run starts from rest rather than resuming a stale one (see the stamp
    # below — slice 37's `:head_frame` posture, in a second quantity).
    r_az = 0.0; r_el = 0.0; ωn_h = 0.0; ζ_h = 0.0
    if _gim
        look_az_b, look_el_b = look_angles(c[:att_q]::Quat, û_tru)
        # Degrees at the YAML boundary, radians inside (the `seeker_fov_deg` posture — the seam
        # converts once). ⚠ NO DOUBLE CLAMP: `head_clamp` owns `max(stop, 0)` and the NaN-stop
        # degenerate, `head_slew` owns `τ < 0` / `dt ≤ 0` (slice 33's "the clamp changed owner").
        # The window's own `max(·, 0)` is clamped HERE and exactly once, and both the predicate and
        # the shipped margin below read THIS local — so the sign and the verdict are the same bits.
        stop_h = deg2rad(Float64(get(c, :gimbal_stop_deg, 1.0e6)))
        fov_h  = max(deg2rad(Float64(get(c, :gimbal_fov_deg, 1.0e6))), 0.0)
        # ⭐⭐ SLICE 35 — THE SERVO'S MAXIMUM SLEW RATE. Slice 34's head was INFINITELY FAST: it moved
        # a full first-order step every tick with no bound on how far. A real gimbal has a servo, and
        # the moment it does the head's motion stops being free and becomes a RESOURCE spent against
        # a demand — and THE DEMAND IS SET BY THE PARASITIC LOOP. On a settled collision course the
        # head barely moves (slice 34's `head_angle_deg` is a *constant* 17.190°) and the band demand
        # is 0.600 °/s; let the loop ring and the same head must chase its own oscillation at
        # 60.831 °/s, 53.6× more, ACROSS SLICE 34's OWN ONSET BRACKET (gate 0 §0.2). See
        # `docs/plans/slice35.md`.
        # ⚠ THE ABSENT-KEY DEFAULT IS `Inf` AND THAT IS THE BIT-IDENTITY CONTROL — never a large
        # finite number, and specifically NOT the domain ceiling: gate 0 §0.6 measured
        # `gimbal_rate_dps = 60` reading `sat_band` 8.64 % with `rms r` 0.88469 against the free
        # 0.88465, because the PEAK demand is an identical 72.542 °/s on every arm (the tick-2
        # HANDOVER transient). An arm authored at 60 expecting `max|Δpos| == 0` lands as a NEAR-MISS
        # that reads like a rounding bug in the new branch. `Inf` takes the OLD CODE PATH (gate 1's
        # `sat = dem > cap` polarity), so slice 34 is bit-identical BY CONSTRUCTION.
        # ⚠ `deg2rad` ON A PER-SECOND QUANTITY IS STILL JUST `deg2rad`: deg→rad is a pure scale
        # factor and the seconds are untouched. The seam converts ONCE, here, as it does for the stop
        # and the window — the loader stores the authored degrees.
        rate_h = deg2rad(Float64(get(c, :gimbal_rate_dps, Inf)))
        if _so
            # ⭐ SLICE 40 — Hz AT THE YAML BOUNDARY, RAD/S INSIDE: the seam converts ONCE, here, as
            # it does for the stop, the window and the rate limit. `gimbal_zeta` is dimensionless
            # and is the SLIDER (convention 5's clamp-at-CONSUMER lives inside the kernel, which
            # clamps a negative damping ratio to zero rather than flying a divergence).
            ωn_h = 2π * Float64(get(c, :gimbal_omega_hz, 0.0))
            ζ_h  = Float64(get(c, :gimbal_zeta, 1.0))
            # ⚠⚠ THE RATE STATE IS ZEROED ON ENTERING THE RUNG, NOT CARRIED. `:head_servo_frame`
            # stamps which servo ORDER the head's state was last held in — slice 37's `:head_frame`
            # posture in a second quantity — and the reason is physical rather than defensive: a
            # first-order head has NO rate state, so there is nothing to resume from and a stale
            # one would be a velocity the head never had. ⭐ THE STAMP, NOT `haskey`, IS THE
            # CURRENCY TEST (slice 37's ⚠): `:head_rate_az` is minted here and never deleted.
            if get(c, :head_servo_frame, :first_order) === :second_order
                r_az = Float64(get(c, :head_rate_az, 0.0))
                r_el = Float64(get(c, :head_rate_el, 0.0))
            end
        end
        if !haskey(c, :head_az)
            # THE HANDOVER — the head is handed the target at launch, and it is LOAD-BEARING rather
            # than a nicety (§0.8, slice 32's P5 vindicated). Against a head that starts CAGED at
            # boresight the whole lead must be slewed, so during acquisition the window requirement
            # DEGENERATES TO THE STRAPDOWN ONE (18.1172° — slice 32's own number) and `off_max` over
            # a full flight stops measuring the tracking error at all; it even moves the ring verdict
            # at the bracket's edge. ⇒ THE SHIPPED HEAD IS HANDED OVER, and that is a stated §1
            # condition of every number this slice quotes. Making the handover itself addressable is
            # the named successor.
            # ⚠ `head_clamp`, NEVER A PER-AXIS `clamp` (gate 1's Finding 2, and the gate-0 probe has
            # exactly that bug): the servo is a contraction toward the target ONLY FROM INSIDE the
            # disc, and this is the one place a head can be born outside it. The call is
            # unconditional because the kernel is bit-for-bit inert when it does not bind.
            #
            # ⭐⭐ SLICE 36 — THE HANDOVER BASKET, and the successor named directly above is now
            # spent. The head is born `gimbal_handover_err_deg` degrees off the true body-frame LOS
            # in AZIMUTH, and the finding is that THE OPTIMUM IS NOT ZERO. The body-frame LOS is not
            # a fixed target: over the approach it travels +18.11° → −15.15° (a 33.2° EXCURSION, and
            # it CROSSES THROUGH ZERO) as the missile swings its nose onto the collision course, so a
            # head handed over ON the LOS must chase that whole journey and a rate-limited servo
            # falls 12.35° behind doing it, while a head handed over 8° ALONG the journey never falls
            # further behind than the 8° it started with. The requirement is therefore a **V** — its
            # left arm `|err|` EXACTLY (the tick-1 peak, before the servo has done anything) and its
            # right arm the CHASE COST — and the cheapest basket sits at the KINK, which the servo
            # moves. See `docs/plans/slice36.md`.
            #
            # ⚠ THE SIGN IS THE ENGAGEMENT'S, NOT THE TARGET'S. `err < 0` means ALONG THE BODY-FRAME
            # LOS EXCURSION, whose DIRECTION THE CROSSING SIGN SETS — never "toward where the target
            # is going" (the #1 SIGN TRAP's 11th occurrence, and it would be wrong prose rather than
            # wrong code). Against the reversed crossing the excursion nearly vanishes (a 2.2° swing
            # against 33.2°), the requirement is exactly `|err|` at EVERY servo rate, and the optimum
            # returns to zero — which is the tooth that makes this a statement about the ENGAGEMENT
            # rather than about handover errors (gate 0 §0.4).
            #
            # ⭐ NO NEW KERNEL, AND THAT IS A DECISION WITH A REASON. The offset is an ARGUMENT to an
            # existing clamp: `head_clamp` already owns the stop, the CAGED (`stop ≤ 0`) degenerate,
            # the NaN-stop degenerate and the sign of the returned zeros, so a `head_handover`
            # wrapper would have exactly ONE call site and would be a SECOND place for stop policy to
            # drift — the trap this file already names for `off_axis_angle` and `head_slew`. ⇒
            # `frames.jl` is UNTOUCHED by this slice and every prior slice is bit-identical BY
            # CONSTRUCTION, not by a measurement (slice 35's gate-1 shape inverted).
            #
            # ⚠⚠ THE OFFSET GOES **INSIDE** `head_clamp`, NEVER AFTER IT — or a head is born outside
            # its own mechanical stop, which is the ONE state the servo cannot recover from (the
            # contraction toward the target holds only from inside the disc). The tell that it went
            # in inside is that at `err > +11.9°` the head is born ON the circle with its ELEVATION
            # SCALED RADIALLY, not left alone; pinned below.
            #
            # ⚠⚠ THE BIT-IDENTITY CONTROL IS THE ABSENT KEY, NEVER `= 0.0` (slice 35's blocking pin,
            # verbatim). A separate `haskey` branch with the else-arm slice 34/35's line TEXTUALLY
            # UNCHANGED — never `head_clamp(look_az_b + err, …)` trusting `err = 0` to be inert,
            # because `-0.0 + 0.0` is `+0.0` (the trap 20/21/26 all name). ⚠ Whether `= 0.0` IS
            # bit-identical to absent is MEASURED and not assumed, and it is measured on the ONE
            # geometry where it can differ — an IN-PLANE (`Y = 0`) arm, where `look_az_b` is a signed
            # zero. On the crossing wire `look_az_b ≈ +0.316 rad` and `+ 0.0` is trivially inert, so
            # that arm carries no information (advisor).
            #
            # ⭐ SLICE 37 — THE SPACE-STABILIZED HANDOVER IS THE SAME BIRTH IN THE OTHER FRAME, and
            # it is `head_clamp_inertial`'s SECOND CALLER, which is why gate 1 split that kernel out
            # at all (slice 34 split `head_clamp` for exactly this reason: the handover must clamp
            # the way the servo does). The head is born on the TRUTH LOS — the same physical
            # direction as the body arm below — but its STATE is the inertial pair, and the STOP is
            # still taken in the BODY frame, because a gimbal's mechanical travel is body-relative
            # no matter what frame its servo closes in.
            # ⚠⚠ `gimbal_handover_err_deg` IS REFUSED BESIDE THIS RUNG AT LOAD (`scenario.jl`), and
            # the reason is the false-claim class rather than hygiene: slice 36's basket, its V and
            # its sign convention are all stated in the BODY frame ("ALONG THE BODY-FRAME LOS
            # EXCURSION"), so an INERTIAL-azimuth offset would be a different physical birth wearing
            # a measured slice's name. The load refusal is complete cover even though the rung is
            # live-settable: the handover is consumed ONCE, at tick 1, so a toggle can never reach
            # this branch with that key live.
            if _stab
                i_az, i_el, head_az, head_el =
                    head_clamp_inertial(az_tru, el_tru, c[:att_q]::Quat, stop_h)
                c[:head_i_az] = i_az; c[:head_i_el] = i_el
            elseif haskey(c, :gimbal_handover_err_deg)
                head_az, head_el =
                    head_clamp(look_az_b + deg2rad(Float64(c[:gimbal_handover_err_deg])),
                               look_el_b, stop_h)
            else
                head_az, head_el = head_clamp(look_az_b, look_el_b, stop_h)   # ── 34/35 VERBATIM ──
            end
        elseif _stab
            # ── SLICE 37 — THE SPACE-STABILIZED SERVO ─────────────────────────────────────────────
            # The state is the INERTIAL pair; the body pair is RECOMPUTED from it every tick and
            # NEVER integrated, so nothing accumulates (`head_clamp_inertial`'s own contract).
            head_az = Float64(c[:head_az]); head_el = Float64(c[:head_el])
            # ⭐ THE INERTIAL STATE IS MINTED AT THE RUNG BOUNDARY AND ONLY THERE (advisor). `:head_az`
            # is kept live by BOTH rungs, so on the first tick after a toggle the head's pointing is
            # carried across EXACTLY — the same physical direction, re-expressed once through the
            # CURRENT attitude — and neither rung pays a per-tick conversion it does not use.
            # ⚠ THE STAMP, NOT `haskey`, IS THE CURRENCY TEST. `:head_i_az` is minted here and NEVER
            # deleted (the house rule), so after a body-referenced stint it is present and STALE;
            # `:head_frame` records which frame the head's state was last held in, which is the
            # physical question ("where is this pointing being held?") rather than bookkeeping of a
            # redundant angle. A `haskey` mint would silently resume a pointing direction the missile
            # abandoned seconds ago.
            i_az, i_el = get(c, :head_frame, :body_referenced) === :space_stabilized ?
                (Float64(c[:head_i_az]), Float64(c[:head_i_el])) :
                az_el(rotate(c[:att_q]::Quat, los_unit_from_angles(head_az, head_el)))
            # ── SLICE 38 — AN IMPERFECT HEAD GYRO ────────────────────────────────────────────────
            # Everything above holds this pointing in space FOR FREE, which is slice 37's §1
            # approximation named FIRST among its deferrals: a PERFECT head-mounted rate gyro,
            # rejecting body motion at EXACTLY unity gain at every frequency. A real one has a scale
            # factor and a bias, and feeding its reading forward leaves the pointing drifting at
            # `−s·ω − b` (frames.jl `head_drift_inertial`, which composes slice 31's `gyro_reading`).
            # ⇒ slice 37's whole margin becomes a GYRO SPEC: its onset bracket walks from its own
            # space bracket at s = 0 to its own body bracket at a dead gyro, and −5 % — an ordinary
            # cheap-MEMS part — gives back a quarter of it.
            #
            # ⚠⚠ THE ORDERING IS A DECISION, NOT AN INHERITANCE (advisor, before the edit). This runs
            # BEFORE `head_clamp_inertial`, so a drift that pushes the head into its MECHANICAL STOP
            # is clamped in the SAME tick — the head cannot drift through its own gimbal limit. The
            # alternative (clamp, then drift) differs exactly when the stop binds, and it would let
            # the stored pointing sit outside the stop for a tick. ⚠ GATE 0 NEVER BOUND THE STOP
            # (`head_max` 18.1–18.8° against 30°), so this is untested territory rather than
            # something 37 settled: `test_missile.jl` pins it on a wire where the stop DOES bind.
            # This is slice 37 §II.9's class — the body carries the head BEFORE the detector is read
            # — and the same discipline applies: say which order, and pin it.
            #
            # ⚠ INERT ON THE BODY RUNG BY PLACEMENT, NOT BY A GUARD: this is inside the `elseif
            # _stab` arm, so a body-referenced wire never reaches it and the keys are introduce-safe
            # there (pinned as `max|Δpos| == 0.0` in `test_missile.jl`, the other-rung twin of the
            # key-absent tooth). ⚠ AND IT IS NOT ON THE TICK-1 HANDOVER BRANCH, correctly: nothing
            # has elapsed for a gyro to drift THROUGH.
            #
            # ⚠ THE FOURTH ATTITUDE-TIMING SITE (slice 37's gate-2 fix named three, and it says so
            # in this file). `:omega_body` here is PHASE 1's output — the rate belonging to att(k),
            # which is the SAME attitude `:att_q` holds on this line and the same one the carry and
            # the stop below use. All four sites therefore agree on the tick, which is the property
            # that was violated the last time this block was edited.
            #
            # ⭐ THE ELSE IS SLICE 37 VERBATIM — no `head_drift_inertial(…, 0.0, …)` trusting the
            # zeros. The kernel returns its input BIT-FOR-BIT at a zero residual, so an authored
            # `s = 0` is byte-identical to the keys being absent BY CONSTRUCTION; routing the
            # key-absent case through the call anyway would make that a MEASUREMENT instead, and
            # would re-open the `-0.0` trap slices 20/21/26/27/28/29 each closed structurally.
            if haskey(c, :head_gyro_scale_err) || haskey(c, :head_gyro_bias_y) ||
               haskey(c, :head_gyro_bias_z)
                i_az, i_el = head_drift_inertial(i_az, i_el,
                                                 get(c, :omega_body, zero(Vec3))::Vec3,
                                                 Float64(get(c, :head_gyro_scale_err, 0.0)),
                                                 Vec3(0.0,
                                                      Float64(get(c, :head_gyro_bias_y, 0.0)),
                                                      Float64(get(c, :head_gyro_bias_z, 0.0))),
                                                 c[:att_q]::Quat, dt)
            end
            # ⚠⚠ THE BODY CARRIES THE HEAD **BEFORE** THE DETECTOR IS READ, AND THE ORDERING IS A
            # GATE-2 POST-REVIEW FIX (advisor). `:head_az` was written by tick k−1's `observe!`, i.e.
            # it is this pointing expressed in **att(k−1)** — but `integrate!` is PHASE 1 and this is
            # PHASE 3, so `:att_q` here is already att(k), and on THIS rung the head's body angle
            # moves with attitude even when the servo does nothing. Gating the slew on the stored
            # pair would therefore have measured "the error the detector HAD" against the WRONG
            # ATTITUDE, and would have made discipline 3's two evaluations differ by attitude timing
            # as well as by the slew — which is not what discipline 3 says they differ by (on the
            # body rung there is no such gap, because a body-referenced head's stored pair is still
            # current). ⚠ AND NO CHECK OF THIS GATE COULD SEE IT: the gate's headline validation is
            # that the shipped seam reproduces gate 1's ladder cell for cell, but gate 1's PROBE
            # patched the same hunk and made the same choice — cell-for-cell agreement proves
            # `seam == probe`, never that either is right. This is the THIRD place attitude timing
            # enters the head (§II.4 names the other two) and the plan now says so.
            # ⭐ THE CLAMP IS THE SAME CALL THE HOLD PATH USED TO MAKE, MOVED ABOVE THE GATE, WHICH IS
            # BOTH THE FIX AND A SIMPLIFICATION: the body rotating under a space-stabilized head can
            # drag it into its own mechanical STOP with no slew involved, so the stop is taken FIRST
            # and the detector then reads where the head actually is. The `else` arm is gone — a head
            # outside its detector window simply does not slew, which is now the only thing that
            # branch ever meant.
            i_az, i_el, head_az, head_el = head_clamp_inertial(i_az, i_el, c[:att_q]::Quat, stop_h)
            # ⚠⚠ THE HOLD IS PHYSICS HERE, NOT HOUSEKEEPING, AND IT IS WHERE THE TWO RUNGS PART MOST
            # VISIBLY. A body-referenced head with no error signal HOLDS ITS BODY ANGLE and its index
            # freezes (slice 34 §0.4: a frozen index makes a CONSTANT bend, quiet at every R̂). A
            # space-stabilized one holds its INERTIAL angle, so its body angle — the glass's index,
            # the stop's quantity and the detector's reference — KEEPS MOVING at unity gain while the
            # missile rotates under it, AND THE STOP CAN STILL BIND while the head is holding. No
            # slew, so nothing is demanded and nothing saturates: the zero initialisers above are
            # what a held tick reports on BOTH rungs. Measured (gate 2): over one broken window a
            # body head moves 0.00000° EXACTLY across 5229 held ticks and this one travels 46.80°.
            # discipline 3, first evaluation (the body arm's, verbatim in meaning): the error the
            # detector HAS, now that the body has carried the head and the stop has been taken.
            if off_axis_angle(head_az, head_el, look_az_b, look_el_b) ≤ fov_h
                if _so
                    # SLICE 40 on slice 37's rung — the SAME kernel with the frame changed, exactly
                    # as `head_slew_inertial` is `head_slew_full`. ⚠⚠ THIS ARM WAS PREDICTED TO BE
                    # NEARLY INERT AND GATE 2 REFUTED IT (6.1× on a design this rung flies quiet):
                    # the servo is fed slice 34's bent-measurement fixed point as well as body
                    # motion, and a resonance amplifies either. The claim ships on the body arm
                    # because it is LARGER there, not because this one is quiet.
                    i_az, i_el, head_az, head_el, r_az, r_el, head_dem, head_sat =
                        head_slew_second_order_inertial(i_az, i_el, r_az, r_el,
                                                        Float64(c[:head_tgt_i_az]),
                                                        Float64(c[:head_tgt_i_el]),
                                                        c[:att_q]::Quat, ωn_h, ζ_h, dt, stop_h;
                                                        rate_max = rate_h)
                else
                    i_az, i_el, head_az, head_el, head_dem, head_sat =
                        head_slew_inertial(i_az, i_el,
                                           Float64(c[:head_tgt_i_az]), Float64(c[:head_tgt_i_el]),
                                           c[:att_q]::Quat, Float64(c[:gimbal_tau_s]), dt, stop_h;
                                           rate_max = rate_h)
                end
            end
            c[:head_i_az] = i_az; c[:head_i_el] = i_el
        else
            head_az = Float64(c[:head_az]); head_el = Float64(c[:head_el])
            # discipline 3, first evaluation: the error the detector HAD, before this tick's slew.
            if off_axis_angle(head_az, head_el, look_az_b, look_el_b) ≤ fov_h
                # ⚠ `head_slew_full`, NOT `head_slew` — the SHIPPED kernel returning the two
                # quantities the servo knows and its pointing does not. The plan FORBIDS
                # reconstructing them as a post-hoc difference of `:head_az`, and forbids the seam
                # re-forming `wrap_angle(tgt − head)·gain/dt` and the `step > cap` comparison itself:
                # that is a SECOND IMPLEMENTATION of the kernel — the trap this file already names
                # for `off_axis_angle` — and here it is worse than cosmetic, because a FLAG built
                # from a re-derived predicate can DISAGREE with the branch it claims to report, at
                # the boundary tick where the disagreement is least visible. `head_slew` is these
                # four values' first two, bit-for-bit (pinned over 2 000 cells at gate 1).
                if _so
                    # ⭐⭐ SLICE 40 — THE SECOND-ORDER SERVO, in the BODY frame. This is where the
                    # rung's claim lives, and gate 2 measured WHY it is here: not because the other
                    # frame is untouched (that prediction was REFUTED — a resonance also amplifies
                    # slice 34's bent-measurement fixed point, which is live on both frames, 6.1×)
                    # but because the effect is LARGER here, 44×, where the servo is additionally
                    # fed the missile's own body motion. See `frames.jl HEAD_SERVO_MODES`.
                    head_az, head_el, r_az, r_el, head_dem, head_sat =
                        head_slew_second_order(head_az, head_el, r_az, r_el,
                                               Float64(c[:head_tgt_az]), Float64(c[:head_tgt_el]),
                                               ωn_h, ζ_h, dt, stop_h; rate_max = rate_h)
                else
                    # ── 34/35/36/37 VERBATIM — the else-arm is the bit-identity control ──────────
                    head_az, head_el, head_dem, head_sat =
                        head_slew_full(head_az, head_el,
                                       Float64(c[:head_tgt_az]), Float64(c[:head_tgt_el]),
                                       Float64(c[:gimbal_tau_s]), dt, stop_h; rate_max = rate_h)
                end
            end
        end
        c[:head_az] = head_az; c[:head_el] = head_el
        # SLICE 37 — WHICH FRAME THE POINTING IS CURRENTLY HELD IN. Written on BOTH rungs because
        # that is what makes a mid-run toggle exact in both directions: the body pair above is live
        # on both rungs, so the space arm re-expresses it ONCE at the boundary and the body arm
        # simply resumes off it (slice 34's own cross-toggle posture — the head does not un-exist,
        # it carries its pointing across). ⚠ A Symbol, deliberately: this is PROVENANCE, not a second
        # copy of the state, and duplicating an ANGLE on the rung that does not use it is what would
        # turn slices 34–36's "byte-identical BY CONSTRUCTION" into "by measurement".
        c[:head_frame] = _stab ? :space_stabilized : :body_referenced
        # SLICE 40 — the servo's RATE STATE and the stamp that says which ORDER held it. Written on
        # BOTH rungs for the same reason `:head_frame` is: the first-order arm stamps `:first_order`
        # and stores the zeros its locals carry, so re-entering the second-order rung starts from
        # rest BY CONSTRUCTION rather than by a guard that could be forgotten. ⚠ The keys are minted
        # inside `_gim`, so a wire with no head carries neither (slices 1–33 byte-identical).
        c[:head_rate_az] = r_az; c[:head_rate_el] = r_el
        c[:head_servo_frame] = _so ? :second_order : :first_order
        # …and the second evaluation: the error the detector HAS. This one is the availability
        # verdict and the shipped margin. ⚠ THE SHIPPED KERNEL, never an inline `hypot(wrap_angle(…))`
        # restatement of it (slice 32's gate-1 correction: an inline form makes `test_frames.jl`
        # prove a SECOND implementation and nothing about what flies) — and it is `off_axis_angle`
        # with the HEAD as the reference axis, which is `boresight_angle`'s own shape with the nose
        # replaced. That a CAGED head reproduces `boresight_angle` exactly is gate 1's finding, and
        # it is why there is one kernel here and not two.
        off_head = off_axis_angle(head_az, head_el, look_az_b, look_el_b)
        # ⭐⭐ SLICE 36 (gate 2) — THE REQUIREMENT IS A **MAX OVER THE APPROACH**, SO THE CORE HOLDS
        # IT. `head_off_deg` above is instantaneous, and the quantity this slice is about — *how much
        # detector window did this handover need?* — is its running maximum. ⚠ THE REASON IT LIVES
        # HERE IS CONVENTION 13 AND **NOT** SLICE 33's EMIT-GRID FINDING, and that was settled by a
        # go/no-go measurement rather than by inheritance: the frame grid under-reads this peak by
        # 0.0003–0.0031°, which is **0.27 % of the margin that decides the verdict** at the tightest
        # cell (8.840° against a 10° window) and the frame verdict agrees with the tick verdict in
        # every cell measured. Slice 33's language would have been a BORROWED CLAIM. ⭐ And the
        # mechanism is slice 35's own knob: a RATE-LIMITED head cannot move more than
        # `rate·emit·dt` between frames, so the very servo limit that CREATES the requirement also
        # BOUNDS how much a frame grid can hide of it. What licenses the key is simply that a max
        # over ticks is not a thing a client that receives one tick in sixteen can form at all.
        #
        # ⚠ CUMULATIVE, AND ACROSS A CROSS-TOGGLE TOO — the deliberate choice, because `:head_az`
        # itself persists through one (the head does not un-exist when `:airframe` leaves `:six_dof`;
        # it FREEZES, and on toggle-back the seam takes the SLEW branch off the stored angles). A
        # peak that reset there would be the only piece of head state that did, and it would read
        # LOWER than the tracking error the head has actually had. Nothing accrues while `_gim` is
        # false because this line is inside its gate.
        # ⚠⚠ AND IT IS RAW — NO RANGE GATE. The last metres of a HIT swing the LOS through large
        # angles (slice 34: every held arm leaves its window at r = 0.18–8.55 m), so this key runs
        # away at CPA on an arm that hit. That is correct for a live HUD, which reads it during the
        # approach; a VERIFIER must read it AT A RANGE and never at the end
        # ([[ewsim-missile-verifier-sampling]] — the endgame spike, in a new quantity). Measured and
        # pinned in `test_missile.jl`.
        off_peak = max(Float64(get(c, :head_off_peak, 0.0)), off_head)
        c[:head_off_peak] = off_peak
    end

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
        # ⭐⭐ SLICE 34 — THE INDEX. The glass bends the ray where the ANTENNA IS POINTED, so under a
        # gimballed head the look angle the curve is evaluated at is the HEAD's own angle, not the
        # LOS-vs-body angle. That is the rewrite `frames.jl` names as the reason this is its own
        # slice — and gate 0 measured that at ZERO SERVO LAG it collapses: the head angle IS the
        # LOS-vs-body angle then, so the glass sees the same index and `max|Δpos| = 0` EXACTLY over
        # 9000 ticks on ringing glass (§0.2). ⇒ "the bend keys off head-vs-body" is a TOOTH, never
        # the headline; what the slice actually rests on is that the head is aimed by the BENT
        # measurement, which is the branch above.
        # ⚠ STRUCTURAL BYTE-IDENTITY (the slice-20/21/26/27/28 shape): a BRANCH, whose else-arm is
        # the slice-26…33 line VERBATIM. Never `head_az` seeded from the look angle and trusted to
        # be equal — the `-0.0` trap and float non-associativity both apply, and a no-gimbal wire
        # must be bit-for-bit slice 33 BY CONSTRUCTION rather than by a value that happens to agree.
        if _gim
            look_az, look_el = head_az, head_el
        else
            look_az, look_el = look_angles(c[:att_q]::Quat, û_tru)
        end
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

    # SLICE 32 — THE SEEKER'S FIELD OF VIEW. Slices 26–31 made the LOOK ANGLE a first-class
    # quantity and then bounded every knob domain by it reaching 30° — a §1 MODEL-VALIDITY caveat.
    # A real seeker has a FIELD OF VIEW, which makes that same angle a PHYSICAL STOP: past it there
    # is NO MEASUREMENT AT ALL and the tracker must COAST. ⭐ And what it caps is not a force or a
    # rate but the ENGAGEMENT — the window a seeker needs is the collision triangle's own LEAD
    # ANGLE (frames.jl `collision_lead_angle`), so too small a window costs not ACCURACY but the
    # ENVELOPE. The arc's FIRST SENSOR-SIDE CAP (10/12 magnitude, 15 jerk + deflection, 19
    # flight-condition, 22 the lift curve's interior peak — all airframe or actuator).
    # See `docs/plans/slice32.md`.
    #
    # ⚠ THE PREDICATE IS THE SHIPPED KERNEL, NOT AN INLINE RESTATEMENT OF IT (advisor, gate 1;
    # convention 14's "anything computed inside `_draw` has no headless proof", one layer down): an
    # inline `hypot(look_angles(...)...) ≤ fov` would make `test_frames.jl` prove a SECOND
    # implementation and nothing about what flies. ⚠ And the negative-`fov` clamp (convention 5)
    # still has exactly ONE owner — `seeker_fov_margin` since slice 33, which `seeker_in_fov` now
    # DELEGATES to (the predicate is defined as that margin's sign, which is how slice 33's shipped
    # number got onto the flying path with no edit here). This converts degrees to radians and hands
    # the result straight in, deliberately NOT clamping twice — unchanged, and the reason this line
    # is a REWORD and not a behaviour note.
    # ⚠ The FOV quantity is the TOTAL off-boresight angle — a CIRCULAR window. That is the quantity
    # the radome comments above correctly warn is the WRONG one for the per-axis glass, and the
    # RIGHT one here (a rectangular / per-axis FOV is a named deferral).
    # ⚠ Computed from the TRUTH LOS: whether the target is inside the seeker's window is PHYSICS,
    # not an estimate — the contrast with the compensator two blocks below, which must use the BENT
    # measurement. And rung-gated on the LIVE `:airframe`, never on `haskey(:att_q)` alone (the
    # slice-21 `_atm_on` / 23 / 26 / 27 latent-bug class, whose FIFTH occurrence this would be).
    # ⚠⚠ SLICE 34's `!_gim` CONJUNCT IS A CRASH GUARD, NOT A PREFERENCE (advisor, gate-2 review).
    # `scenario.jl` REFUSES a YAML that authors both windows, but a PROGRAMMATIC world can still
    # build one — and without this conjunct that world THROWS inside `observe!`: the availability
    # branch below takes its `_gim` arm, so `fov_rad` is never assigned, and the slice-33 telemetry
    # block further down passes it to `seeker_fov_margin`. An `UndefVarError` there lands in the
    # session's IO/EOF-only catch and silently drops the connection (convention 5). ⚠ AND IT WAS
    # REACHABLE: the comment below justifies leaving `fov_rad` unassigned on the grounds that "an
    # unassigned local throws and the suite catches it" — true only while nothing builds the
    # combination, which stopped being true the moment a head existed.
    # ⭐ ONE CONJUNCT, THREE POLICY CLAIMS TURNED STRUCTURAL: the FOV telemetry block cannot run
    # under a head, so slice 26's head-indexed `look_angle` CANNOT be clobbered by the truth-
    # referenced one (impossible rather than merely refused), and the `elseif` below is unreachable
    # rather than throwing. The loader refusal STAYS — it is the "refused, not silently ignored"
    # discipline, and it is what tells a scenario author which seeker they are building.
    _fov_on = haskey(c, :seeker_fov_deg) && haskey(c, :att_q) && !_gim &&
              get(w.fidelity, :airframe, :point_mass) === :six_dof
    # ⚠ `fov_rad` is DELIBERATELY LEFT UNASSIGNED on the non-FOV path (advisor) — an `= Inf`
    # else-arm would SILENTLY supply a plausible value to any future reader, where an unassigned
    # local throws and the suite catches it. The convention-6 "no Inf/NaN to JSON" hazard, one step
    # upstream. ⚠ SO THE `seeker_fov_deg` READOUT SHIPS `c[:seeker_fov_deg]`, NEVER THIS LOCAL: it
    # is the AUTHORED value in DEGREES, where this is the converted radians AND the wrong number on
    # a negative slider. Slice 33's `seeker_fov_margin_deg` DOES pass this local to the kernel —
    # legally, because that readout sits under the very same `_fov_on` gate, and because the margin
    # is defined on the CLAMPED window (which the kernel owns) rather than the authored one.
    # ⚠ SLICE 34 — UNDER A HEAD THE WINDOW IS THE DETECTOR'S, ABOUT THE HEAD AXIS. A gimballed
    # seeker has no body-fixed field of view — the mechanical STOP is its body-fixed limit — so the
    # two are alternatives and not a conjunction: `scenario.jl` refuses a YAML that authors both,
    # and `_fov_on` carries `!_gim` so a programmatic one cannot reach the `elseif` either.
    # ⚠ This is the SECOND evaluation of the detector error (discipline 3): the error AFTER the
    # slew, where the slew gate above read the error BEFORE it.
    if _gim
        in_fov = off_head ≤ fov_h
    elseif _fov_on
        fov_rad = deg2rad(Float64(c[:seeker_fov_deg]))
        in_fov  = seeker_in_fov(c[:att_q]::Quat, û_tru, fov_rad)
    else
        in_fov  = true
    end

    # SEAM DISCIPLINE 2 — the servo's target for the NEXT tick: the MEASURED LOS rotated into the
    # body frame, i.e. what this tick's detector actually reported, BEND AND NOISE INCLUDED. It must
    # be stored HERE, after `az_m`/`el_m` are formed, and the head must have slewed on the PREVIOUS
    # one above — that ordering is the self-referential index the whole slice rests on.
    # ⚠ UNCONDITIONAL UNDER `_gim`, and paired with the handover's `:head_az` mint: the two keys are
    # written on the same tick, which is what lets the slew branch index `:head_tgt_az` directly
    # instead of falling back to a truth read (advisor).
    # ⭐ SLICE 37 — THE SPACE-STABILIZED SERVO'S TARGET HAS NO ATTITUDE IN IT AT ALL: it is the
    # MEASURED INERTIAL angles themselves, which is the whole content of the rung (and the origin of
    # the one-tick attitude residual gate 1 located in §II.4 — the body arm expresses its target in
    # `att(k)` and consumes it at `k+1`, where this one is attitude-free).
    # ⚠ BOTH ARE WRITTEN ON BOTH RUNGS, and that is a decision with a reason rather than symmetry for
    # its own sake: the inertial pair is FREE (it is the measurement, no conversion), and keeping the
    # body pair unconditional leaves slices 34/35/36's line TEXTUALLY UNBRANCHED — which is the form
    # their byte-identity claim takes. The alternative (each rung storing only its own frame's
    # target) makes the FIRST tick after a toggle-back consume a target stale by however long the
    # other rung ran, which is a real wrong-number rather than a bookkeeping cost.
    if _gim
        head_tgt_az, head_tgt_el = look_angles(c[:att_q]::Quat, los_unit_from_angles(az_m, el_m))
        c[:head_tgt_az] = head_tgt_az; c[:head_tgt_el] = head_tgt_el
        c[:head_tgt_i_az] = az_m; c[:head_tgt_i_el] = el_m
    end

    # Lazy first-tick init (the `_observe_point!` shape): seed every memory, all rates 0.
    if !in_fov && !get(c, :seek_init, false)
        # NEVER LOCKED — out of the window before the tracker ever had a measurement. A DEFINED,
        # finite, non-throwing state (conventions 5/6): no estimate, no rate, `seek_init` stays
        # false so the first in-window tick initializes normally.
        ȧz_raw = 0.0; ėl_raw = 0.0; λ̇_raw = 0.0
        az_est = 0.0; el_est = 0.0; λ_est = 0.0
        ȧz_est = 0.0; ėl_est = 0.0; λ̇_est = 0.0
    elseif !in_fov
        # COASTING — the target is outside the window, so there is no measurement to correct with.
        # The α-β tracker runs its PREDICT step alone (innovation ≡ 0): the angle extrapolates on
        # the last rate, and the RATE — which is what PN consumes — is FROZEN.
        az_est = Float64(c[:seek_az_est])     + Float64(c[:seek_azdot_est])     * dt
        el_est = Float64(c[:seek_el_est])     + Float64(c[:seek_eldot_est])     * dt
        λ_est  = Float64(c[:seek_lambda_est]) + Float64(c[:seek_lambdadot_est]) * dt
        ȧz_est = Float64(c[:seek_azdot_est])
        ėl_est = Float64(c[:seek_eldot_est])
        λ̇_est  = Float64(c[:seek_lambdadot_est])
        c[:seek_az_est] = az_est; c[:seek_el_est] = el_est; c[:seek_lambda_est] = λ_est
        # `_prev` tracks the PREDICTION while coasting, so the `:raw` foil differences a sane pair
        # on re-acquisition instead of one spanning the whole gap.
        # ⚠ AND IT IS EXERCISED, not merely defensive (advisor, gate 2 — "do not leave a
        # live-looking branch with no proof"): the RE-ACQUISITION arm of `test_missile.jl`'s slice-32
        # COROLLARY testset (a ringing radome at `fov = 25`) leaves and re-enters the window in brief
        # episodes and still lands within a metre of the same wire with no window at all.
        c[:seek_az_prev] = az_est; c[:seek_el_prev] = el_est; c[:seek_lambda_prev] = λ_est
        ȧz_raw = 0.0; ėl_raw = 0.0; λ̇_raw = 0.0
    elseif !get(c, :seek_init, false)
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
    # SLICE 32 — the FIELD-OF-VIEW readouts, shipped ONLY while a window is authored (the never-stale
    # discipline; a slice-11/13/25…31 wire is byte-identical BY GATING — `_fov_on` is false on every
    # one of them, so not a single key here is even evaluated there). All SCALARS (convention 13 —
    # the client recomputes nothing; convention 6 — `_finite`/`_finite_coord` on every one).
    if _fov_on
        # ⭐ THE DISCRIMINATOR, per slice 22's `post_stall` discipline: do NOT let the miss carry the
        # mechanism claim alone, and do NOT expect an existing flag to discriminate (`aero_sat` is
        # 0.0 % in EVERY arm of this slice, broken or not — the miss is a POINTING miss). 1/0, and
        # the fraction of the approach it spends at 0 IS the verdict gate 3 asserts.
        # ⚠ FROM THE LOCAL `in_fov`, never from a comp key: a first draft parked it in
        # `c[:seek_in_fov]`, which is the stale-readout class this arc has now caught six times
        # (`_atm_on` 21 / 23 / 26 / 27 / 29) — comp keys are never deleted, so a cross-toggle off
        # `:six_dof` would leave a plausible-looking validity flag frozen at its last value.
        tel["$sid.seeker_valid"]   = in_fov ? 1.0 : 0.0
        # The live knob — the LIMIT itself, so the client can draw it beside the angle.
        # ⚠ `_finite_coord`, NOT `_finite` (the slice-29 `k̂` catch): `_finite` clamps only the UPPER
        # bound, so a large NEGATIVE slider value would reach the JSON unclamped. And it ships the
        # AUTHORED value rather than the effective `max(fov, 0)` — the clamp lives at exactly one
        # site (`seeker_in_fov`), and a HUD that silently showed 0° for a negative slider would hide
        # what the student is holding. The two differ only on the degenerate never-locked side.
        tel["$sid.seeker_fov_deg"] = _finite_coord(Float64(c[:seeker_fov_deg]))
        # ⭐ THE ANGLE THE LIMIT IS AGAINST — the TOTAL off-boresight angle, i.e. the CIRCULAR-window
        # quantity the predicate actually tests (`boresight_angle`, the shipped kernel — never an
        # inline restatement of it, gate 1's load-bearing correction).
        # ⚠⚠ COMPUTED HERE FROM `û_tru`, NOT HOISTED OUT OF THE RADOME BLOCK (advisor). Slice 26's
        # `look_angle` above is built from `look_az`/`look_el`, which are the else-arm ZEROS when
        # `_rad_on` is false — and THIS SLICE'S SHOWCASE WIRE HAS THE RADOME KEYS ABSENT BY DESIGN
        # (convention 9: a ringing arm's look angle swings BECAUSE it rings, so it would be the
        # LOOP's angle and not the ENGAGEMENT's). A `_rad_on || _fov_on` gate on that expression —
        # the obvious edit, and what the plan wrote — would ship 0.0 on the one wire the lesson runs
        # on, the slice-29 `radome_model_err_az` stale-readout catch verbatim.
        # ⚠ On a wire that has BOTH, this is provably the SAME number the radome block already
        # shipped (`boresight_angle ≡ hypot(look_angles(att, û_tru)...)`, same inputs, same ops), so
        # the duplicate write is bit-for-bit consistent rather than a second opinion.
        tel["$sid.look_angle"] = _finite(rad2deg(boresight_angle(c[:att_q]::Quat, û_tru)))
        # SLICE 33 — ⭐ HOW MUCH WINDOW IS LEFT, SIGNED. `max(fov,0) − boresight_angle`, in the same
        # degrees as the two keys above, and its SIGN IS THE VERDICT (`margin ≥ 0 ⟺ seeker_valid`)
        # — slice 18's `terrain_clearance_m` precedent exactly: ship the margin so the client never
        # re-derives the test (convention 13 — the client NEVER re-tests occlusion). What it buys is
        # a HUD needle that a ringing radome is visibly seen to EAT, which is slice 33's whole
        # lesson: the parasitic loop's excursion is spent out of THIS budget.
        # ⚠ THE KERNEL IS CALLED AGAIN HERE rather than hoisting a local out of the `_fov_on` block
        # above (advisor). `look_angle` on the line above already has exactly this posture, and it
        # keeps ONE flying comparison site (`seeker_in_fov`, ~line 1673) instead of creating an
        # ambiguity about which kernel flies; three `boresight_angle` calls a tick is nothing at 27k
        # ticks/s. Same `att`, same `û_tru`, same `fov_rad` ⇒ the shipped sign and the flying
        # verdict are the SAME BITS, not two opinions — which is what `test_missile.jl` pins by
        # walking a broken trace and finding the 1→0 flip on the exact tick this crosses zero.
        # ⚠ `_finite_coord`, NOT `_finite` (the slice-29 `k̂` catch, and here it is not hypothetical):
        # the margin is NEGATIVE on the whole out-of-window side, by ~65° on a broken arm's runaway
        # and by `-fov` on the never-locked degenerate, and `_finite` clamps only the UPPER bound.
        # ⚠⚠ AND IT USES THE CLAMPED WINDOW WHILE `seeker_fov_deg` ABOVE SHIPS THE AUTHORED ONE, so
        # the two keys DO NOT RECONSTRUCT THIS ONE on a negative slider (gate 1's catch — the
        # kernel's docstring carries the reasoning). That divergence is the reason convention 13
        # requires the key rather than letting the client subtract: a client doing `fov − look` is
        # off by exactly `|fov|` there, on the very side the never-locked state is defined by.
        tel["$sid.seeker_fov_margin_deg"] =
            _finite_coord(rad2deg(seeker_fov_margin(c[:att_q]::Quat, û_tru, fov_rad)))
        # ⭐⭐ THE ENGAGEMENT'S OWN REQUIREMENT, BESIDE THE WINDOW THE HARDWARE HAS — the pair IS the
        # slice. `V_m·sin λ = V_t·sin θ` (frames.jl `collision_lead_angle`): the lead this collision
        # triangle DEMANDS, in the same degrees as `look_angle` and `seeker_fov_deg`, so a student
        # reads the verdict off three numbers rather than being told it.
        # ⚠ PER TICK, WHICH IS THE POINT: the kernel's docstring warns that evaluating it ONCE off
        # the LAUNCH geometry reads 32.90° against the 28.84° the engagement actually holds (14 %
        # strict) because the LOS rotates as the target crosses. Telemetry is per-tick by
        # construction, so shipping it here is the CURE for that misuse, not an instance of it.
        # ⚠⚠ AND GATE 3 MAY NOT USE THIS KEY AS THE ANCHOR FOR THE LOOK-ANGLE CLAIM. The P3b
        # external anchor (convention 11) is that the critical FOV EQUALS this lead — proven by an
        # INDEPENDENT recompute. Reading the core's own key back and comparing it to the core's own
        # look angle is the self-calibrated round-trip this project names as a trap.
        tel["$sid.lead_angle_deg"] = _finite(rad2deg(
            collision_lead_angle(_norm3(e.vel), tgt.vel, û_tru)))
    end
    # SLICE 34 — the GIMBAL readouts, shipped ONLY while a head is authored (the never-stale
    # discipline; a slice-11/13/25…33 wire is byte-identical BY GATING — `_gim` is false on every one
    # of them, so not a single key here is even evaluated there). ⚠ AND THE GATE IS THE RUNG, so a
    # cross-toggle off `:six_dof` ships NO head keys at all rather than a frozen plausible set — the
    # latent-bug class this arc has now caught six times. All SCALARS, all `_finite*` (conventions
    # 6/13 — the client recomputes nothing).
    if _gim
        # ⭐ THE PRICE, IN THE ONE CURRENCY A GIMBAL HAS. Slice 33's single number splits in TWO:
        # a STOP (the head's TRAVEL about the body, which reproduces slice 33's excursion — a
        # RESTATEMENT, not a new claim) and a DETECTOR WINDOW (about the head axis — new, and where
        # the margin the self-referential index buys is paid for).
        # ⚠ `hypot`, DELIBERATELY NOT `off_axis_angle(0, 0, …)` — and the difference is not cosmetic.
        # This number is read against the STOP, and the stop is `head_clamp`'s UNWRAPPED `hypot`; a
        # wrapped reading would disagree with the clamp exactly where a head with NO stop leaves the
        # principal interval, which `head_slew`'s docstring pins as a real state. The telemetry must
        # have the same shape as the clamp that produced it — the same species argument that made
        # the stop CIRCULAR in the first place.
        tel["$sid.head_angle_deg"] = _finite(rad2deg(hypot(head_az, head_el)))
        tel["$sid.gimbal_stop_deg"] = _finite_coord(Float64(get(c, :gimbal_stop_deg, 1.0e6)))
        tel["$sid.head_off_deg"]    = _finite(rad2deg(off_head))
        # ⚠ `_finite_coord`, NOT `_finite`, on the window and the margin (the slice-29 `k̂` catch):
        # `_finite` clamps only the UPPER bound, and the margin is NEGATIVE across the whole
        # out-of-window side. The window ships the AUTHORED degrees while the margin is built on the
        # CLAMPED radians — slice 33's divergence exactly, and for its reason: the two keys must not
        # be expected to reconstruct the third on a negative slider, which is the defined
        # never-acquires state.
        tel["$sid.gimbal_fov_deg"] = _finite_coord(Float64(get(c, :gimbal_fov_deg, 1.0e6)))
        # ⭐ HOW MUCH DETECTOR WINDOW IS LEFT, SIGNED — slice 18's `terrain_clearance_m` / slice 33's
        # `seeker_fov_margin_deg` precedent: THE SIGN IS THE VERDICT. Built from the SAME local
        # `fov_h` and the SAME `off_head` the predicate above tested, so the shipped sign and the
        # flying verdict are the same bits and not two opinions. ⭐⭐ And it is the currency of §0.7's
        # measured predicate `held ⟺ tracking error < detector window`, which is slice 32's
        # predicate returning in the quantity a gimbal actually has.
        tel["$sid.gimbal_fov_margin_deg"] = _finite_coord(rad2deg(fov_h - off_head))
        tel["$sid.gimbal_valid"] = in_fov ? 1.0 : 0.0
        # ⭐⭐ SLICE 36 — THE REQUIREMENT, AND THE MARGIN AGAINST IT. `head_off_deg` is what the
        # detector must cover THIS TICK; `head_off_peak_deg` is what it had to cover to get here,
        # which is the number a handover basket is designed against. The running max is formed at
        # the seam beside `off_head` (see there for why the core holds it — convention 13, and NOT
        # slice 33's emit grid, which was measured and came back 0.27 % of the deciding margin).
        # ⚠⚠ IT IS THE TWO-RUN DISCIPLINE's FIFTH QUANTITY AND IT FAILS **LARGE** — on a
        # never-acquired arm it is the POST-BREAK RUNAWAY (65–120°), where slice 34's frozen
        # `head_angle_deg` failed plausibly-but-small. A requirement may only be read off a
        # FREE-WINDOW arm; on a windowed arm this key reports what the break did, not what the
        # design needed.
        # ⚠⚠ AND IT IS AN **APPROACH** QUANTITY — THE ENDGAME IS PERMANENT HERE IN A WAY IT IS
        # NOWHERE ELSE IN THIS ARC. Slice 34 measured that every held arm leaves its window at
        # r = 0.18–8.55 m as the LOS swings past; an INSTANTANEOUS key spikes there and recovers,
        # but a PEAK CANNOT FORGET. Measured: this key reads the clean requirement (8.84 / 8.09 /
        # 9.50 / 2.11 on the four cells below) unchanged from r = 3000 m down to r = 200 m, and then
        # runs to **179.4998° at CPA on every arm, hit or miss** — the target is simply behind the
        # head by then. ⇒ a reader takes it AT A RANGE, never at the end, and gate 3's HUD owns
        # freezing the display there. That is [[ewsim-missile-verifier-sampling]]'s endgame spike in
        # the ONE telemetry shape for which it is irreversible, and it is why the SECOND key drafted
        # here — a signed peak MARGIN, slice 33's shape — WAS MEASURED AND DROPPED: its whole value
        # would have been that it latches and never recovers, and its whole defect is the same
        # sentence, since the endgame breach fires it on 100 % of arms INCLUDING every hit. The
        # verdict already ships per tick as `gimbal_valid`, which recovers when the geometry does,
        # and slice 32's LATCH is the client's to hold over it.
        tel["$sid.head_off_peak_deg"] = _finite(rad2deg(off_peak))
        # The AUTHORED handover error beside it, SIGNED and in the same degrees, so the client
        # reads the basket's coordinate off the wire instead of being told it (the
        # `gimbal_stop_deg` / `gimbal_fov_deg` / `gimbal_rate_dps` posture — convention 13). ⚠ Its
        # default is a true 0.0 and not a `FINITE_CEIL` sentinel, because a head with no authored
        # error IS handed over perfectly: `err = 0` is the physical default, which is exactly why
        # slice 34/35's wires are the `err = 0` row of this slice's own grid.
        tel["$sid.gimbal_handover_err_deg"] =
            _finite_coord(Float64(get(c, :gimbal_handover_err_deg, 0.0)))
        # ⭐⭐ SLICE 35 — THE SERVO'S OWN TWO NUMBERS, and they are the two SIDES of one claim: what
        # the head was ASKED for, and whether it could deliver it. Gate 0 measured both, and they
        # come from DIFFERENT code paths in the kernel (the demand is formed unconditionally, the
        # flag is the branch predicate) — which is what makes the pair a measurement rather than one
        # fact told twice: the band demand STEPS 0.600 → 60.831 °/s across slice 34's onset bracket
        # (§0.2) and at the SAME 8 °/s servo the shipped design saturates 0.00 % of the band against
        # the boresight-characterized one's 97.14 % (§0.6).
        #
        # ⚠ THE DIVISION LIVES HERE AND THAT IS THE KERNEL'S OWN DECISION. `head_slew_full` returns
        # the demand as a STEP IN RADIANS, deliberately: `step/Δt` at `Δt = 0` would manufacture a
        # non-finite from finite input (convention 6), so the division — and the degrees — belong to
        # the seam, where this family's unit conversions already live. The `dt ≤ 0` degenerate is
        # therefore the SEAM's to own, and it ships 0.0 rather than an `Inf` the `_finite` ceiling
        # would then disguise as a real 1e9 °/s.
        # ⚠ A ZERO HERE IS AMBIGUOUS BY CONSTRUCTION and the plan's two-run discipline is why it is
        # written down: tick 1 (the HANDOVER, which calls `head_clamp` and never slews) and every
        # tick with the target OUTSIDE the detector window (the head HOLDS — no error signal, no
        # slew) both ship 0.0 demand and 0.0 sat. ⇒ `head_rate_sat` READS 0 ON A BROKEN ARM for the
        # same reason `rms r` FALLS there, and it joins `rms r` / `head_off_deg` / `head_angle_deg`
        # as the FOURTH quantity that may not be read off a windowed run.
        # ⚠⚠ SLICE 37 — THIS KEY MEASURES THE SERVO'S OWN FRAME, AND THAT FRAME CHANGES WITH THE
        # `:seeker_head` RUNG. Under `:body_referenced` the demand is the step in BODY angles (so it
        # includes tracking out the missile's own rotation); under `:space_stabilized` it is the step
        # in INERTIAL angles, which is what the head must slew at with body motion already rejected.
        # ⇒ A CLIENT COMPARING THIS NUMBER ACROSS A BUTTON PRESS IS COMPARING TWO FRAMES' DEMANDS —
        # which is not a defect but the rung's whole content (gate 0 §II.1 measured the ratio at
        # 8.19× on a ringing design and 0.86× on a quiet one: an inertial servo buys essentially
        # nothing when the missile is not shaking). Said here rather than only in the plan, because
        # the key NAME does not change and nothing on the wire would otherwise say so.
        tel["$sid.head_rate_dps"]  = _finite(dt > 0.0 ? rad2deg(head_dem) / dt : 0.0)
        # ⚠ THE FLAG, never a hand-rolled compare of the two keys above against the authored rate
        # (the `aero_sat` / `defl_sat` / `gimbal_valid` shape): it is the kernel's OWN branch
        # predicate, so what ships is what BOUND, not what a reader would infer bound. The demand is
        # PRE-limit and the rate is authored in deg/s, so a client reconstructing `dem > rate` would
        # be re-deriving the comparison across two unit conversions and a `max(·, 0)`.
        tel["$sid.head_rate_sat"]  = head_sat ? 1.0 : 0.0
        # The authored servo rate beside them, so the demand and its cap are read in the SAME units
        # off the SAME wire (the `gimbal_stop_deg` / `gimbal_fov_deg` precedent — the client
        # recomputes nothing, convention 13). A head with no authored rate ships the FINITE_CEIL
        # sentinel rather than the `Inf` that is its true default (convention 6).
        tel["$sid.gimbal_rate_dps"] = _finite(Float64(get(c, :gimbal_rate_dps, Inf)))
        # ⭐⭐ SLICE 40 — THE SERVO'S OWN TWO NUMBERS, shipped ONLY while its keys are authored (the
        # slice-31/38 posture: a first-order wire carries none of them, so slices 34–39 stay
        # byte-identical ON THE WIRE as well as in the core).
        if haskey(c, :gimbal_omega_hz) || haskey(c, :gimbal_zeta)
            tel["$sid.gimbal_omega_hz"] = _finite(Float64(get(c, :gimbal_omega_hz, 0.0)))
            tel["$sid.gimbal_zeta"]     = _finite(Float64(get(c, :gimbal_zeta, 1.0)))
            # ⭐⭐ THE QUANTITY THE WHOLE SLICE IS DENOMINATED IN: the servo's INDEX GAIN — how much
            # of the missile's own body motion arrives at the part of the dome the ray goes through.
            # It is the closed-form magnitude of `H(jω) = ω_n²/((jω)² + 2ζω_n(jω) + ω_n²)` read at
            # the ring's own 1.7 Hz, which is where slices 26–39 measured the limit cycle to live.
            #
            # ⚠⚠ IT IS SHIPPED FROM THE CORE AND NOT LEFT TO THE CLIENT (convention 13), AND IT IS
            # SHIPPED FOR **BOTH** RUNGS SO THE BUTTON COMPARES LIKE WITH LIKE — the first-order
            # head's own `1/√(1+(2πfτ)²)` is the number slice 37 measured its entire margin out of
            # (0.882 at this frequency), and a HUD that printed the second-order gain beside nothing
            # would invite the reader to compare it against 1.
            #
            # ⚠ AND IT IS A LABEL, NOT A VERDICT — read at ONE frequency chosen by six earlier
            # slices, on a wire where gate 0 could NOT measure the frequency the loop actually
            # closes at (`docs/plans/slice40.md` §0.7). Two arms of this very slice ring with these
            # numbers 32× apart, which is the payload: what it names is the servo, not the outcome.
            let f_ring = 1.7
                w_hz = Float64(get(c, :gimbal_omega_hz, 0.0))
                z    = max(Float64(get(c, :gimbal_zeta, 1.0)), 0.0)
                g = if _so && w_hz > 0.0
                        rr = f_ring / w_hz
                        1.0 / sqrt((1.0 - rr^2)^2 + (2 * z * rr)^2)
                    else
                        1.0 / sqrt(1.0 + (2π * f_ring * Float64(get(c, :gimbal_tau_s, 0.0)))^2)
                    end
                tel["$sid.head_index_gain"] = _finite(g)
            end
        end
        # ⭐⭐ SLICE 38 — THE HEAD GYRO's OWN NUMBERS, shipped ONLY while one of its keys is authored
        # (the slice-31 posture: a wire with a perfect head gyro carries no gyro keys at all, so
        # slices 34–37 stay byte-identical on the wire as well as in the core).
        if haskey(c, :head_gyro_scale_err) || haskey(c, :head_gyro_bias_y) ||
           haskey(c, :head_gyro_bias_z)
            # ⚠⚠ NAMED BY **WHICH SENSOR**, NOT BY WHICH ERROR TERM (advisor). This missile now
            # carries TWO corrupted gyros: slice 31's `gyro_scale_err` / `gyro_bias_z` feed the
            # COMPENSATOR (they multiply a believed slope and land on the aim point and the
            # residual), while these feed the HEAD's own stabilization loop and land on how much
            # body motion reaches the glass's INDEX. They are different sensors with the same two
            # error terms, and a HUD that prints "scale factor" twice would be unreadable.
            tel["$sid.head_gyro_scale_err"] = _finite_coord(
                Float64(get(c, :head_gyro_scale_err, 0.0)))
            tel["$sid.head_gyro_bias_z"] = _finite_coord(
                Float64(get(c, :head_gyro_bias_z, 0.0)))
            # ⭐ THE REJECTION GAIN — what fraction of the missile's own body motion the head FAILS
            # to reject, i.e. the quantity slice 37 measured its entire margin out of. `s = 0` is a
            # perfect head (0 % leaked); `s = −1` is a dead gyro (100 % leaked, the head simply
            # carried along by the body). ⚠ IT IS **NOT** THE INDEX GAIN, and the distinction is
            # gate 0's first refutation: the index gain is what the glass sees AFTER the servo has
            # also acted, so it runs 1.000 → 0.886 rather than 1 → 0 (a head carried by the body is
            # STILL SLEWED by its servo, which is precisely slice 37's other rung). This key is the
            # LEAK, which is a property of the sensor alone and therefore the honest thing to put on
            # a wire beside a slider that sets it.
            tel["$sid.head_gyro_leak"] = _finite_coord(
                abs(Float64(get(c, :head_gyro_scale_err, 0.0))))
            # ⚠ SHIPPED ALONGSIDE slice 27/28's `radome_residual*`, NEVER FOLDED INTO THEM (the
            # slice-31 instruction, and it was right there too): those keys keep meaning "what the
            # GLASS and the BELIEF disagree by", and this slice moves neither. What it moves is how
            # much of the body's motion arrives at the index where that disagreement is evaluated.
        end
        # ⚠ THE TWO QUANTITIES THE STOP AND THE WINDOW ARE READ AGAINST ARE DIFFERENT ANGLES, and
        # shipping both is what stops a HUD comparing the wrong pair (the plan's gate-3 note): the
        # ENGAGEMENT's lead is what the head's TRAVEL must cover (vs the STOP), while the TRACKING
        # ERROR is what the DETECTOR window must cover. `look_body_deg` is the strapdown seeker's own
        # look angle — the number slice 32 called `look_angle` — kept under its own name because
        # slice 26's `look_angle` above now ships the HEAD's index, which is what the glass used.
        tel["$sid.look_body_deg"] = _finite(rad2deg(boresight_angle(c[:att_q]::Quat, û_tru)))
        # ⭐⭐ SLICE 36 — THE SAME LOOK, **SIGNED**, IN THE AXIS THE HANDOVER ERROR IS AUTHORED IN, and
        # it exists because THE LINE ABOVE CANNOT SHOW A SIGN. `look_body_deg` is a `hypot`, and gate 0
        # §0.4 attributed the basket's asymmetry to the body-frame LOS *settling* 18.1° → 15.2° on
        # exactly that evidence — a story that was WRONG (the #1 SIGN TRAP's 10th occurrence). Logged
        # signed, the azimuth **CROSSES THROUGH ZERO**: +18.11° at t = 0.001 s to −15.15° by t = 10 s, a
        # 33.2° EXCURSION, as the missile swings its nose onto the collision course. That excursion is
        # the whole mechanism — a head handed over ON the LOS must chase the entire journey while one
        # handed over part-way along it starts with a head start — so the number a student must WATCH is
        # this one, and until now it existed only in a probe. ⚠ Against the REVERSED crossing the same
        # quantity is nearly STATIC (a 2.2° swing), which is why the requirement is EXACTLY |err| there
        # at every servo rate: the rate-dependence belongs to the ENGAGEMENT, not to handover errors.
        # ⚠ `_finite_coord`, NOT `_finite` — the value is negative over most of the approach and
        # `_finite` clamps only the upper bound (the slice-29 `k̂` catch, 4th application).
        # ⚠ RECOMPUTED from `att_q` and `û_tru` exactly as the line above is, NOT plumbed out of the
        # seam's `look_az_b`: the two are the same call on the same inputs, and the recompute keeps this
        # publisher free of state it would otherwise have to be handed (the shape every key here has).
        tel["$sid.look_body_az_deg"] =
            _finite_coord(rad2deg(look_angles(c[:att_q]::Quat, û_tru)[1]))
        # Slice 32's key, VERBATIM in meaning and inputs (`_fov_on` is unreachable beside `_gim`, so
        # this is the only writer on a gimbal wire): the collision triangle's own demand, per tick.
        tel["$sid.lead_angle_deg"] = _finite(rad2deg(
            collision_lead_angle(_norm3(e.vel), tgt.vel, û_tru)))
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
