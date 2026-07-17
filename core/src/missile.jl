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
# `true` when this missile carries an authored scale height AND the `:atmosphere` rung is live.
# The ONE place the gate is expressed, so the four ρ-reading airframe sites cannot drift apart
# (convention 7's one-list-no-drift, applied to a predicate). Slices 8–20 have no
# `:af_scale_height`, and the rung DEFAULTS to `:constant` — so this is `false` on every prior
# scenario by BOTH halves, and each caller's else-arm is the prior slice's code TEXTUALLY
# VERBATIM (byte-identity by construction, not by trusting `exp(0) == 1`; the `-0.0` trap the
# slice-20 induced-drag gate documents).
_atm_on(c::Dict{Symbol,Any}, w::World) =
    haskey(c, :af_scale_height) && get(w.fidelity, :atmosphere, :constant) === :exponential

# The airframe's air density at height `z` — ρ(z) under the live rung, else the authored constant.
# **Returns the IDENTICAL expression the frozen paths already had when gated off**, which is what
# makes the four call sites safe to reroute through it. `H` is floored inside `air_density`
# (convention 5's clamp-at-consumer — it is a live slider).
_airframe_rho(c::Dict{Symbol,Any}, w::World, z::Float64) =
    _atm_on(c, w) ? air_density(z; rho0 = Float64(get(c, :rho, 1.225)),
                                H = Float64(c[:af_scale_height])) :
                    Float64(get(c, :rho, 1.225))

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
    f = if _atm_on(c, w)
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
    if haskey(c, :af_cma) && haskey(c, :pitch_theta)
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
        tel["$sid.omega_sp"]    = _finite(short_period_freq(_norm3(e.vel), p))  # NaN (unstable) → FINITE_CEIL
        tel["$sid.alpha_trim"]  = _finite_coord(trim_alpha(Float64(get(c, :af_delta, 0.0)), p))
        # SLICE 17 lift readout — shipped ONLY when the COUPLING is LIVE (`:airframe ===
        # :pitch_coupled`), further-gated INSIDE the af_cma block so a slice-16 `:point_mass` wire
        # stays byte-identical (lift keys must NOT appear there — the slice-15 fin-key precedent;
        # lift only physically exists when coupled). |a_lift| = the turn accel; turn radius R =
        # V²/|a_lift| (α→0 ⇒ |a_lift|→0 ⇒ R→∞ → FINITE_CEIL; the omega_sp NaN path already proves
        # `_finite` ceils the degenerate). RNG-free, own keys → order-independent.
        if get(w.fidelity, :airframe, :point_mass) === :pitch_coupled
            aLm = _norm3(lift_accel(e.vel, θ, mass, p))
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
                tel["$sid.a_induced"] = _finite(_norm3(induced_drag_accel(e.vel, θ, mass, p)))
            end
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
    return Dict{Symbol,Any}(:airframe_view => true, :airframe_target => String(missiles[1]))
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
# fidelity step); planar in x-z (the elevation view's plane, no cross-range — the slice-10 precedent).

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
    alpha_coupled = false                                      # slice-19: true ⇒ the plant flies δ, NOT :a_ctrl
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
            a_max_aero = aero_accel_limit(V_af, mass_af, p_af; alpha_max = alpha_max)
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
                a_ctrl     = lift_accel(e.vel, θ_af, mass_af, p_af)
                alpha_diag = (alpha_cmd = α_cmd, delta_cmd = δ_cmd, aero_sat = aero_sat,
                              defl_sat = defl_sat, a_max_aero = a_max_aero, q_dyn = q_dyn)
            else
                # THE REFERENCE ARM (`:point_mass`): no plant to fly ⇒ `:ideal`'s perfect tracking. The
                # α-loop outputs are ZEROED (no α command was issued — honest, not a computed-but-unused
                # value), while the ceiling/flight-condition readouts stay REAL: the point-mass plant
                # crosses `a_max_aero` and HITS ANYWAY, which is exactly the contrast.
                a_ctrl     = a_cmd
                alpha_diag = (alpha_cmd = 0.0, delta_cmd = 0.0, aero_sat = false,
                              defl_sat = false, a_max_aero = a_max_aero, q_dyn = q_dyn)
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
    alpha_coupled || (c[:a_ctrl] = a_ctrl)

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
        tel["$sid.q_dyn"]      = _finite(alpha_diag.q_dyn)            # ½ρV² — the flight condition (only V moves it)
        tel["$sid.aero_sat"]   = alpha_diag.aero_sat ? 1.0 : 0.0      # the AERO ceiling binding? (THE LESSON flag)
        tel["$sid.defl_sat"]   = alpha_diag.defl_sat ? 1.0 : 0.0      # δ_max binding? (the ISOLATION — must stay 0)
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
function observe!(s::Seeker, w::World)
    e = w.entities[s.id]
    c = e.comp
    rung = get(w.fidelity, :seeker, :filtered)
    rung === :scan ? _observe_scan!(s, w, e, c) : _observe_point!(s, w, e, c, rung)
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
