# test_missile.jl — the airframe force model + fixed-step integrators vs their closed
# forms (HANDOFF §10 item 8, slice 8 gate 1). The gate-2 `BallisticMissile` SUBSYSTEM
# tests append here later; gate 1 is the pure math (dynamics.jl).
#
# The HEADLINE (advisor #2): RK4 reproduces the constant-gravity parabola to MACHINE
# EPSILON (it integrates the degree-2 solution exactly) — an `== analytic` pin, not a
# mere `ΔE small` (energy conservation is necessary but not sufficient). Euler's crisp
# lesson is the POSITION error `≈ ½·g·dt·t` (O(dt), pinned); its ENERGY drift is
# phase-dependent and only PROBED (a comment, never asserted). The convergence-order
# test (÷16 RK4, ÷2 Euler) is the external anchor that RK4 isn't a mislabeled RK2 — run
# in a coarse-dt strong-drag regime because on the pure parabola RK4's truncation error
# is ZERO (only roundoff is left, which does NOT halve). Explicit atol throughout.

@testset "missile dynamics — force model + integrators" begin
    g   = G_ACCEL
    gv  = Vec3(0.0, 0.0, -g)
    p0  = Vec3(0.0, 0.0, 0.0)
    grav(v) = total_accel(v; cd_area = 0.0)          # drag off → gravity only
    fly(step, accel, p, v, dt, n) = begin
        for _ in 1:n; p, v = step(accel, p, v, dt); end
        (p, v)
    end
    maxabs(a, b) = maximum(abs.(a .- b))

    @testset "force model: gravity constant, drag quadratic, drag-off is EXACTLY zero" begin
        @test gravity_accel() == gv
        @test gravity_accel() == total_accel(Vec3(500, -30, 200); cd_area = 0.0)   # drag off
        # drag off (cd_area = 0) → drag_accel is the ZERO vector, bit-exact
        @test drag_accel(Vec3(300, 0, 200); cd_area = 0.0) === zero(Vec3)
        # drag opposes velocity, magnitude = (ρ·Cd·A/2m)·‖v‖²
        v = Vec3(100.0, 0.0, 0.0); ρ = 1.225; cda = 0.02; m = 50.0
        ad = drag_accel(v; rho = ρ, cd_area = cda, mass = m)
        @test ad[1] < 0 && ad[2] == 0 && ad[3] == 0                 # opposes +x
        @test abs(ad[1]) ≈ (ρ * cda / (2m)) * 100.0^2 atol=1e-12    # ‖v‖·v with ‖v‖=100
        # zero speed → zero drag (no NaN from ‖v‖·v)
        @test drag_accel(zero(Vec3); cd_area = 0.05) == zero(Vec3)
    end

    @testset "RK4 gravity-only == analytic parabola to MACHINE EPS (the headline)" begin
        v0 = Vec3(300.0, 0.0, 300.0)      # 45°-ish launch
        dt = 0.01; n = 200; t = n * dt    # short flight → roundoff stays ~1e-13
        analytic = p0 + v0 * t + 0.5 * gv * t^2
        prk, vrk = fly(rk4_step, grav, p0, v0, dt, n)
        @test prk ≈ analytic rtol=1e-11                            # position exact
        @test vrk ≈ v0 + gv * t rtol=1e-12                         # velocity exact
        # relative error is at the roundoff floor, not O(dt⁴) — RK4 is EXACT for a parabola
        @test maxabs(prk, analytic) / maximum(abs.(analytic)) < 1e-10
    end

    @testset "Euler gravity-only position error ≈ ½·g·dt·t, and O(dt)" begin
        # For CONSTANT acceleration, forward-Euler's position error is EXACTLY −½·a·dt·t
        # (velocity is exact; position lags by one step's worth each tick). On the z axis
        # a_z = −g, so the z error is +½·g·dt·t (Euler sits ABOVE the true parabola).
        v0 = Vec3(300.0, 0.0, 300.0)
        for dt in (0.02, 0.01)
            n = 400; t = n * dt
            analytic = p0 + v0 * t + 0.5 * gv * t^2
            pe, _ = fly(euler_step, grav, p0, v0, dt, n)
            @test pe[1] ≈ analytic[1] rtol=1e-10                   # x has no accel → exact
            @test (pe[3] - analytic[3]) ≈ 0.5 * g * dt * t rtol=1e-9   # z lag, signed
        end
        # O(dt): at a FIXED final time T, halving dt halves the error (1st order). NB the
        # time must be held fixed (vary n with dt) — the error is ½·g·dt·t, so holding n
        # fixed would change t too and give ÷4, masking the true order.
        errz(dt) = let T = 8.0, n = round(Int, T/dt), t = n*dt
            fly(euler_step, grav, p0, v0, dt, n)[1][3] - (p0 + v0*t + 0.5*gv*t^2)[3]
        end
        @test errz(0.02) / errz(0.01) ≈ 2.0 rtol=1e-6
    end

    @testset "convergence order: RK4 ÷≈16 (4th), Euler ÷≈2 (1st) — the external anchor" begin
        # Coarse dt + STRONG drag so RK4's genuine O(dt⁴) truncation dominates roundoff
        # (on the pure parabola RK4 truncation is ZERO — only roundoff, which won't halve).
        v0 = Vec3(300.0, 0.0, 300.0); m = 50.0
        drag(v) = total_accel(v; rho = 1.225, cd_area = 0.05, mass = m)
        T = 4.0
        state(step, dt) = fly(step, drag, p0, v0, dt, round(Int, T / dt))
        ref = state(rk4_step, 2e-4)[1]                 # fine RK4 reference
        err(step, dt) = maxabs(state(step, dt)[1], ref)
        rk4_ratio   = err(rk4_step,   0.2) / err(rk4_step,   0.1)
        euler_ratio = err(euler_step, 0.2) / err(euler_step, 0.1)
        @test 12.0 < rk4_ratio   < 20.0                # ÷16 (genuinely 4th-order, not RK2)
        @test  1.8 < euler_ratio <  2.2                # ÷2 (1st-order)
    end

    @testset "energy: RK4 drag-off conserves (machine eps); drag-on strictly decreases" begin
        m = 100.0
        E(p, v) = 0.5 * m * (v[1]^2 + v[2]^2 + v[3]^2) + m * g * p[3]
        v0 = Vec3(300.0, 0.0, 300.0); dt = 0.01; n = 800
        # drag off → E conserved to machine eps over the whole flight (the §1 closed-form
        # validation test — necessary, and here near-exact)
        p, v = p0, v0; E0 = E(p, v); maxdE = 0.0
        for _ in 1:n
            p, v = rk4_step(grav, p, v, dt)
            maxdE = max(maxdE, abs((E(p, v) - E0) / E0))
        end
        @test maxdE < 1e-10
        # drag on → Ė = −(ρCdA/2)‖v‖³ < 0, so E decreases MONOTONICALLY (sign-guaranteed)
        drag(v) = total_accel(v; rho = 1.225, cd_area = 0.03, mass = m)
        p, v = p0, v0; E0 = E(p, v); prev = E0; mono = true
        for _ in 1:n
            p, v = rk4_step(drag, p, v, dt)
            e = E(p, v)
            e > prev + 1e-6 && (mono = false)          # allow only roundoff-level upticks
            prev = e
        end
        @test mono                                     # strictly (monotonically) decreasing
        @test prev < E0                                # net energy bled off
        # NB Euler's drag-OFF energy drift is PHASE-DEPENDENT (probed: it drifts slightly
        # UPWARD here, ~+0.05% over the flight — position lags while velocity is exact), so
        # it is NOT a clean monotonic gain/loss. The crisp Euler lesson is the POSITION
        # error above, not energy — so the Euler energy direction is PROBED, never asserted.
    end

    @testset "degenerate guards — never throw, never NaN (straight-up, z=0, huge dt)" begin
        # straight-up shot: v→0 at apex, then falls back. No NaN, comes back down.
        vup = Vec3(0.0, 0.0, 200.0)
        p, v = p0, vup
        for _ in 1:5000; p, v = rk4_step(grav, p, v, 0.01); end
        @test all(isfinite, p) && all(isfinite, v)
        @test p[3] < 0                                 # has fallen back through the launch height
        # launch exactly at z=0 integrates UPWARD on step 1 (doesn't insta-stick)
        p1, _ = rk4_step(grav, Vec3(0,0,0.0), Vec3(0,0,50.0), 0.01)
        @test p1[3] > 0
        # a huge dt must not NaN/throw (the stepper is total, the impact clamp is gate 2)
        ph, vh = euler_step(grav, p0, Vec3(100,0,100), 100.0)
        @test all(isfinite, ph) && all(isfinite, vh)
        # integrator_step dispatch: rk4/euler match their steppers; unknown rung throws
        @test integrator_step(:rk4, grav, p0, Vec3(1,0,2), 0.1) == rk4_step(grav, p0, Vec3(1,0,2), 0.1)
        @test integrator_step(:euler, grav, p0, Vec3(1,0,2), 0.1) == euler_step(grav, p0, Vec3(1,0,2), 0.1)
        @test_throws ErrorException integrator_step(:rk2, grav, p0, Vec3(1,0,0), 0.1)
        @test INTEGRATOR_MODES == (:rk4, :euler)       # two rungs (semi_implicit rejected — probe)
    end
end

# --- gate 2: the BallisticMissile SUBSYSTEM wired into the tick loop -------------------
# The first FORCE-based integrator in `tick!` (phase 1). Pins: integrate! matches the gate-1
# stepper on a realized step; the rk4 WIRED trajectory == analytic parabola (drag off); the
# euler wired trajectory DIFFERS (the fidelity is live — not a dead knob, the slice-2
# propagation shape); the z=0 impact fires ONE `:impact` event + freezes the entity; the
# energy telemetry matches ½m‖v‖²+mgz; finite telemetry on degenerate cases; loader arms +
# rejects. The missile publishes its readout in build_env! (phase 2 — the plan's "phase-1
# telemetry" is wiped by `empty!(w.env)`; advisor-confirmed), so `tick!` (which runs phase 2)
# is what surfaces `w.env[:telemetry]`.
@testset "missile subsystem — wired (phase 1 integrator + phase 2 readout)" begin
    g  = G_ACCEL
    gv = Vec3(0.0, 0.0, -g)
    dt = 0.01

    # A programmatic missile world (the test_jammer/test_gps fixture style): one :missile with
    # `BallisticMissile`, launch pos/vel + comp, under the chosen :integrator rung.
    function missile_world(; integrator = :rk4, pos = Vec3(0, 0, 0.0),
                           vel = Vec3(300.0, 0.0, 300.0), mass = 100.0, cd_area = 0.0, rho = 1.225)
        w = World(seed = 0, fidelity = Dict(:integrator => integrator))
        w.entities[:m1] = Entity(:m1, :missile; pos = pos, vel = vel,
            comp = Dict{Symbol,Any}(:mass_kg => mass, :cd_area_m2 => cd_area, :rho => rho))
        return w, Subsystem[BallisticMissile(:m1)]
    end

    @testset "integrate! matches the gate-1 stepper on a realized step (rk4 and euler)" begin
        for mode in (:rk4, :euler)
            step = mode === :rk4 ? rk4_step : euler_step
            w, subs = missile_world(integrator = mode, cd_area = 0.02, mass = 50.0)
            p0 = w.entities[:m1].pos; v0 = w.entities[:m1].vel
            accel(v) = total_accel(v; rho = 1.225, cd_area = 0.02, mass = 50.0)
            pexp, vexp = step(accel, p0, v0, dt)
            tick!(w, subs, dt)
            @test w.entities[:m1].pos == pexp            # bit-exact match to the pure stepper
            @test w.entities[:m1].vel == vexp
        end
    end

    @testset "rk4 WIRED trajectory == analytic parabola (drag off), euler DIFFERS" begin
        wr, sr = missile_world(integrator = :rk4)
        we, se = missile_world(integrator = :euler)
        p0 = Vec3(0, 0, 0.0); v0 = Vec3(300.0, 0.0, 300.0)
        n = 400; t = n * dt
        for _ in 1:n
            tick!(wr, sr, dt); empty!(wr.events)
            tick!(we, se, dt); empty!(we.events)
        end
        analytic = p0 + v0 * t + 0.5 * gv * t^2
        @test wr.entities[:m1].pos ≈ analytic rtol = 1e-10       # rk4 tracks the parabola
        # euler bows: it sits ABOVE the true parabola in z by ≈ ½·g·dt·t (the gate-1 pin, now
        # through the wired integrator) — a MEASURABLE difference, so the rung is not dead.
        @test we.entities[:m1].pos[3] - analytic[3] ≈ 0.5 * g * dt * t rtol = 1e-6
        @test we.entities[:m1].pos != wr.entities[:m1].pos       # the fidelity is live
    end

    @testset "z=0 impact fires ONE :impact event, freezes the entity, subsequent ticks no-op" begin
        # straight-up shot: rises, apexes (v→0, the zero-vector attitude guard), falls back to z=0.
        w, subs = missile_world(integrator = :rk4, vel = Vec3(0, 0, 120.0))
        n_impact = 0; impact_t = 0.0; frozen_pos = nothing; frozen_vel = nothing
        for i in 1:4000
            tick!(w, subs, dt)
            k = count(e -> e[:kind] === :impact && e[:of] === :m1, w.events)
            n_impact += k
            k > 0 && (impact_t = w.t)
            empty!(w.events)
            if get(w.entities[:m1].comp, :impacted, false)
                frozen_pos === nothing && (frozen_pos = w.entities[:m1].pos)
                frozen_vel === nothing && (frozen_vel = w.entities[:m1].vel)
            end
        end
        @test n_impact == 1                                      # EXACTLY once (latched)
        @test w.entities[:m1].comp[:impacted] === true
        @test w.entities[:m1].pos[3] == 0.0                      # clamped to the ground
        @test w.entities[:m1].vel == zero(Vec3)                  # frozen (velocity zeroed)
        @test frozen_pos == w.entities[:m1].pos                  # no drift after impact (no-op ticks)
        @test frozen_vel == zero(Vec3)
        # a launch at z=0 with UPWARD velocity does NOT insta-impact (integrates up on step 1)
        wl, sl = missile_world(integrator = :rk4, pos = Vec3(0, 0, 0.0), vel = Vec3(100.0, 0, 50.0))
        tick!(wl, sl, dt)
        @test wl.entities[:m1].pos[3] > 0
        @test !get(wl.entities[:m1].comp, :impacted, false)
        @test isempty(wl.events)
    end

    @testset "energy telemetry matches ½m‖v‖²+mgz; ΔE≈0 for rk4 drag-off mid-flight" begin
        m = 100.0
        w, subs = missile_world(integrator = :rk4, mass = m, cd_area = 0.0)
        maxde = 0.0; energy_ok = true; readout_ok = true
        for i in 1:400
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]; e = w.entities[:m1]
            ke = 0.5 * m * (e.vel[1]^2 + e.vel[2]^2 + e.vel[3]^2)
            pe = m * g * e.pos[3]
            energy_ok &= isapprox(tel["m1.ke_j"], ke; atol = 1e-6) &&
                         isapprox(tel["m1.pe_j"], pe; atol = 1e-6) &&
                         isapprox(tel["m1.e_total_j"], ke + pe; atol = 1e-6)
            readout_ok &= isapprox(tel["m1.speed"], sqrt(e.vel[1]^2 + e.vel[2]^2 + e.vel[3]^2); atol = 1e-9) &&
                          tel["m1.alt"] == e.pos[3] && tel["m1.pos_x"] == e.pos[1] && tel["m1.pos_z"] == e.pos[3]
            maxde = max(maxde, abs(tel["m1.de_frac"]))
        end
        @test energy_ok                                         # ke/pe/e_total == ½m‖v‖²+mgz every step
        @test readout_ok                                        # speed/alt/pos_x/pos_z readouts consistent
        @test maxde < 1e-10                                     # rk4 drag-off conserves (machine eps)
        @test w.env[:telemetry]["m1.impacted"] === false        # still flying at 400 steps
        # drag on → ΔE goes NEGATIVE (energy bled): the gate-3 energy-slider lesson, pinned here.
        wd, sd = missile_world(integrator = :rk4, mass = m, cd_area = 0.03)
        for _ in 1:400; tick!(wd, sd, dt); empty!(wd.events); end
        @test wd.env[:telemetry]["m1.de_frac"] < -1e-4          # E bled off under drag
    end

    @testset "finite telemetry on degenerate cases — no throw / no NaN" begin
        # straight-up (v→0 at apex — the zero-vector attitude guard) then already-impacted (frozen).
        w, subs = missile_world(integrator = :rk4, vel = Vec3(0, 0, 80.0))
        keys = ("m1.pos_x", "m1.pos_z", "m1.speed", "m1.alt", "m1.ke_j", "m1.pe_j",
                "m1.e_total_j", "m1.de_frac")
        all_finite = true; att_finite = true
        for _ in 1:3000
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            all_finite &= all(isfinite(tel[k]) for k in keys)
            att_finite &= all(isfinite, w.entities[:m1].att)
        end
        @test all_finite                                        # every readout finite through apex + impact
        @test att_finite                                        # attitude never NaN'd through the apex guard
        @test w.env[:telemetry]["m1.impacted"] === true         # ended frozen, telemetry still finite
    end

    @testset "loader: :missile gets BallisticMissile (NOT ConstantVelocity); arms + rejects" begin
        base = """
        name: m
        seed: 0
        dt_physics: 0.01
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 0.0]
            missile:
              mass_kg: 100.0
              speed: 424.264
              elevation_deg: 45.0
              cd_area_m2: 0.0
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            e = scn.world.entities[:m1]
            @test e.kind === :missile
            # the DOUBLE-INTEGRATION guard: BallisticMissile owns pos/vel, so NO ConstantVelocity
            @test any(s -> s isa BallisticMissile, scn.subs)
            @test !any(s -> s isa ConstantVelocity, scn.subs)
            # launch state SI: speed 424.264 @ 45° → vel ≈ [300, 0, 300] (deg→rad in the x-z plane)
            @test e.vel[1] ≈ 300.0 atol = 1e-2
            @test e.vel[3] ≈ 300.0 atol = 1e-2
            @test e.vel[2] == 0.0
            @test e.comp[:speed] == 424.264 && e.comp[:elevation_deg] == 45.0   # raw stored (knob-addressable)
            @test get(scn.world.fidelity, :integrator, :rk4) === :rk4           # default rung

            # rejects: a missing mass, a negative cd_area (a malformed AUTHORED missile → load error)
            nomass = replace(base, "      mass_kg: 100.0\n" => "")
            p1 = joinpath(dir, "nomass.yaml"); write(p1, nomass)
            @test_throws ErrorException load_scenario(p1)
            negdrag = replace(base, "cd_area_m2: 0.0" => "cd_area_m2: -1.0")
            p2 = joinpath(dir, "negdrag.yaml"); write(p2, negdrag)
            @test_throws ErrorException load_scenario(p2)
        end
    end
end

# --- slice 9 gate 2: the guided missile — the Autopilot wired (phase 4, the closed loop) ------
# The missile's FIRST decide! (outer pursuit + inner PID). Pins: decide! writes comp[:a_ctrl]
# matching the pure kernel on the realized state; the WIRED closed loop INTERCEPTS under :ideal;
# the :pid trajectory DIFFERS (the not-a-dead-knob — physics-changing, no RNG); the P-only
# undershoot is visible in track_gap (the wire ratio tracks 1/(1+Kp) — ORDERED in Kp, the exact
# closed form is the pure test_guidance pin; a_cmd RAMPS on the wire so the ratio is ~, not =);
# integral CLOSES the gap; tick-1 is ballistic (a free byte-identity anchor); a diverging gain
# stays finite (the threaded-clamp crash-guard, MANY ticks — advisor); loader arms + rejects.
@testset "guided missile — Autopilot wired (phase 4: outer pursuit + inner PID)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # A crossing engagement (the de-risked probe geometry): interceptor from the origin at z=1000
    # heading +x @ 600 m/s; a target crossing left→right in +y. a_max is GENEROUS (never binds
    # mid-flight — the undershoot is measured mid-flight where a_cmd is small).
    function guided_world(; autopilot = :ideal, k_guid = 3.0, kp = 2.0, ki = 0.0, kd = 0.0,
                          tau = 0.3, a_max = 3000.0)
        w = World(seed = 0, fidelity = Dict(:autopilot => autopilot))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 1000.0), vel = Vec3(600.0, 0, 0),
            comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => k_guid, :kp => kp, :ki => ki, :kd => kd, :tau => tau, :a_max => a_max))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(8000.0, -3000.0, 1000.0),
            vel = Vec3(0, 300.0, 0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
    end
    # Fly to intercept (or n cap); return (miss, hit, last_telemetry).
    function fly!(w, subs; n = 30000, stop = 5.0)
        miss = Inf; hit = false; tel = w.env
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            miss = min(miss, tel["m1.los_range"])
            (tel["m1.los_range"] < stop) && (hit = true; break)
            get(w.entities[:m1].comp, :impacted, false) && break
        end
        return miss, hit, tel
    end
    # The mid-flight P-only undershoot ratio track_gap/a_cmd (measured where a_cmd is small so the
    # a_max clamp can't bind — the confound the advisor flagged).
    function mid_ratio(; kp, ki = 0.0, kd = 0.0, nsteps = 2000)
        w, subs = guided_world(autopilot = :pid, kp = kp, ki = ki, kd = kd)
        for _ in 1:nsteps; tick!(w, subs, dt); empty!(w.events); end
        tel = w.env[:telemetry]
        return tel["m1.track_gap"] / tel["m1.a_cmd"], tel["m1.track_gap"]
    end

    @testset "decide! writes comp[:a_ctrl] matching autopilot_step on the realized state" begin
        w, subs = guided_world(autopilot = :pid, kp = 2.0)
        tick!(w, subs, dt); empty!(w.events)                 # tick 1: decide! computes the 1st command
        e = w.entities[:m1]; tgt = w.entities[:tgt1]
        # reconstruct from the pure kernel on the POST-integrate state decide! used (state = init)
        a_cmd = clamp_accel(pursuit_accel(e.pos, e.vel, tgt.pos; k_guid = 3.0), 3000.0)
        a_ach, _ = autopilot_step(:pid, a_cmd, autopilot_init(), dt; kp = 2.0, tau = 0.3)
        @test e.comp[:a_ctrl] ≈ clamp_accel(a_ach, 3000.0) atol = 1e-12
        @test e.comp[:a_ctrl] isa Vec3                        # a Vec3 (SVector) — the bit-exact add
    end

    @testset "the WIRED closed loop intercepts under :ideal (track_gap == 0, a_ach == a_cmd)" begin
        w, subs = guided_world(autopilot = :ideal, k_guid = 3.0)
        miss, hit, tel = fly!(w, subs)
        @test hit && miss < 10.0                              # clean intercept (probe: ~4.8 m)
        # :ideal is the perfect actuator: achieved ≡ commanded, so the gap is EXACTLY zero.
        @test tel["m1.track_gap"] == 0.0
    end

    @testset "the :pid trajectory DIFFERS from :ideal (not-a-dead-knob, physics-changing)" begin
        wi, si = guided_world(autopilot = :ideal, k_guid = 3.0)
        wp, sp = guided_world(autopilot = :pid, k_guid = 3.0, kp = 2.0)   # P-only lags
        for _ in 1:2000
            tick!(wi, si, dt); empty!(wi.events)
            tick!(wp, sp, dt); empty!(wp.events)
        end
        # the laggy actuator flies a measurably different path (the fidelity is live, not a dead knob)
        @test norm3(wi.entities[:m1].pos - wp.entities[:m1].pos) > 1.0
    end

    @testset "P-only undershoot on the wire — ordered in Kp, integral closes the gap" begin
        # ideal: no gap. P-only: a real gap tracking ~1/(1+Kp) (the exact closed form is the pure
        # test_guidance pin — a_cmd RAMPS on the wire, adding velocity-lag, so here we pin the
        # un-calibrated ORDERING, not a fitted value).
        r05, _ = mid_ratio(kp = 0.5)
        r2,  _ = mid_ratio(kp = 2.0)
        r8,  _ = mid_ratio(kp = 8.0)
        @test r8 < r2 < r05                                   # larger Kp → smaller undershoot
        @test r8 > 0.0                                        # ...but never zero under P-only
        # each is in the right ballpark of 1/(1+Kp) (loose — the ramp contaminates the exact value)
        @test isapprox(r8, 1/9; atol = 0.05) && isapprox(r2, 1/3; atol = 0.06)
        # integral drives the settled gap DOWN (Ki=0 → Ki=40 at fixed Kp) — the wire closed-form lever
        _, gap0  = mid_ratio(kp = 2.0, ki = 0.0)
        _, gap40 = mid_ratio(kp = 2.0, ki = 40.0, kd = 0.1)
        @test gap40 < gap0
    end

    @testset "tick 1 is ballistic — the free byte-identity anchor (one-tick decide! delay)" begin
        # On tick 1, integrate! (phase 1) runs BEFORE decide! (phase 4), so the missile's first step
        # has no :a_ctrl → pure ballistic (identical to an unguided missile from the same launch).
        wg, sg = guided_world(autopilot = :pid, kp = 2.0)
        wb = World(seed = 0, fidelity = Dict(:integrator => :rk4))
        wb.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 1000.0), vel = Vec3(600.0, 0, 0),
            comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225))
        sb = Subsystem[BallisticMissile(:m1)]
        tick!(wg, sg, dt); empty!(wg.events)
        tick!(wb, sb, dt); empty!(wb.events)
        @test wg.entities[:m1].pos == wb.entities[:m1].pos    # bit-identical first step
        @test wg.entities[:m1].vel == wb.entities[:m1].vel
        @test haskey(wg.entities[:m1].comp, :a_ctrl)          # ...but the command IS now staged for tick 2
    end

    @testset "a diverging gain stays finite over MANY ticks — the threaded-clamp crash-guard" begin
        # A destabilizing gain (huge Kp / tiny τ) makes the discrete PID diverge GEOMETRICALLY over
        # ticks; the subsystem clamps a_ach to a_max and threads it BACK as state, so the plant is
        # bounded and pos never NaNs (advisor: step MANY ticks, a single tick always stays finite).
        w, subs = guided_world(autopilot = :pid, kp = 5.0e5, ki = 1.0e4, kd = 1.0e2, tau = 1.0e-3)
        ok = true
        for _ in 1:1500
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]; e = w.entities[:m1]
            ok &= all(isfinite, e.pos) && all(isfinite, e.vel) &&
                  isfinite(tel["m1.a_ach"]) && isfinite(tel["m1.track_gap"])
            ok || break
        end
        @test ok                                              # no NaN/Inf in pos or telemetry
    end

    @testset "loader: a guided :missile gets [BallisticMissile, Autopilot] + needs a :target" begin
        base = """
        name: g
        seed: 9
        dt_physics: 0.001
        fidelity: {autopilot: ideal}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 1000.0]
            missile:
              mass_kg: 100.0
              speed: 600.0
              elevation_deg: 0.0
              cd_area_m2: 0.0
              guidance: {k_guid: 3.0, kp: 2.0, ki: 40.0, kd: 0.1, tau: 0.3, a_max: 3000.0}
          - id: tgt1
            kind: target
            pos: [8000.0, -3000.0, 1000.0]
            vel: [0.0, 300.0, 0.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            m = scn.world.entities[:m1]
            # a GUIDED missile: BallisticMissile (phase-1 mover) + Autopilot (phase-4 guidance), NOT
            # ConstantVelocity (the double-integration guard).
            @test any(s -> s isa BallisticMissile, scn.subs)
            @test any(s -> s isa Autopilot, scn.subs)
            @test !any(s -> s isa ConstantVelocity && s.id === :m1, scn.subs)
            # the gains land at the CONSUMED comp keys (the slider→consumed-key discipline)
            @test m.comp[:k_guid] == 3.0 && m.comp[:kp] == 2.0 && m.comp[:ki] == 40.0
            @test m.comp[:kd] == 0.1 && m.comp[:tau] == 0.3 && m.comp[:a_max] == 3000.0
            @test get(scn.world.fidelity, :autopilot, :ideal) === :ideal
            # a guided missile with NO :target is rejected at LOAD (the runtime no-target coast guard)
            notgt = replace(base, r"- id: tgt1[\s\S]*" => "")     # tgt1 is last → strip it to EOF
            p1 = joinpath(dir, "notgt.yaml"); write(p1, notgt)
            @test_throws ErrorException load_scenario(p1)
            # a bad guidance gain (tau ≤ 0) is a clear AUTHORED load error
            badtau = replace(base, "tau: 0.3" => "tau: 0.0")
            p2 = joinpath(dir, "badtau.yaml"); write(p2, badtau)
            @test_throws ErrorException load_scenario(p2)
        end
    end
end

# --- slice 10 gate 2: the OUTER law swapped — proportional navigation wired ------------------
# The cascade seam pays off: `decide!` selects `pn_accel` vs `pursuit_accel` on `:guidance` (default
# :pursuit → the byte-identical slice-9 path — pinned in test_determinism), the INNER PID untouched.
# autopilot is :ideal in every arm so MISS isolates the GUIDANCE LAW (the slice-9 track_gap confound
# is lifted). Pins: decide! under :pn writes comp[:a_ctrl] matching pn_accel on the realized state;
# the wired PN loop INTERCEPTS the crossing with a miss ≪ pursuit's (Lesson 1); |a_cmd| FALLS toward
# CPA under :pn vs GROWS under :pursuit (the tail-chase foil, on the wire); the :pursuit↔:pn paths
# DIFFER (not-a-dead-knob); g-limit SATURATION on the wire — a bound a_max lifts the miss, a larger
# a_max closes it (Lesson 2, the deliberate inversion of slice 9's never-bind clamp); loader arms +
# rejects (bad n_pn / r_stop). Numbers PROBED against this live decide!→integrate! path (gate2_wire).
@testset "guided missile — proportional navigation wired (slice 10, :guidance outer law)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # The Lesson-1 crossing (gate2_wire): interceptor [0,0,3000] @ 700 m/s / 12° in x-z; a fast
    # x-z-crossing target [6000,0,4200] descending-and-closing at v[-800,0,200]. a_max GENEROUS
    # (3000, never binds — Lesson 2 held out). r_stop=30 (endgame coast-through). :ideal actuator.
    function pn_world(; guidance = :pn, autopilot = :ideal, n_pn = 4.0, r_stop = 30.0,
                      k_guid = 3.0, a_max = 3000.0,
                      m_vel = Vec3(700cosd(12), 0.0, 700sind(12)),
                      t_pos = Vec3(6000.0, 0.0, 4200.0), t_vel = Vec3(-800.0, 0.0, 200.0))
        w = World(seed = 0, fidelity = Dict(:autopilot => autopilot, :guidance => guidance))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0), vel = m_vel,
            comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => k_guid, :n_pn => n_pn, :r_stop => r_stop,
                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :a_max => a_max))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = t_pos, vel = t_vel,
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
    end
    # Fly to FIRST CPA: min los_range up to where the target has clearly passed and the range is
    # opening (open_hold consecutive steps, ≥50 m past the min) — the honest first-pass miss (an
    # unbounded run lets a tail-chaser spiral back in, hiding the lesson). Collects the a_cmd/
    # a_demand/saturated profiles for the climb-vs-fall + saturation pins.
    function fly_cpa!(w, subs; n = 40000, open_hold = 200)
        miss = Inf; acmd = Float64[]; ademand = Float64[]; nsat = 0; nguid = 0
        opening = 0; prev = Inf
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]; r = tel["m1.los_range"]
            miss = min(miss, r)
            push!(acmd, tel["m1.a_cmd"]); push!(ademand, tel["m1.a_demand"])
            tel["m1.saturated"] > 0.5 && (nsat += 1); nguid += 1
            opening = r > prev ? opening + 1 : 0; prev = r
            get(w.entities[:m1].comp, :impacted, false) && break
            r < 1.0 && break
            (opening >= open_hold && r > miss + 50.0) && break
        end
        return (miss = miss, acmd = acmd, ademand = ademand,
                sat_frac = nsat / max(nguid, 1), n = nguid)
    end
    at(prof, f) = prof[clamp(round(Int, f * length(prof)), 1, length(prof))]

    @testset "decide! under :pn writes comp[:a_ctrl] matching pn_accel on the realized state" begin
        w, subs = pn_world(guidance = :pn, autopilot = :ideal, n_pn = 4.0)
        tick!(w, subs, dt); empty!(w.events)                 # tick 1: decide! computes the 1st command
        e = w.entities[:m1]; tgt = w.entities[:tgt1]
        # reconstruct from the pure kernel on the POST-integrate state (r ≫ r_stop → cutoff inert)
        a_cmd = clamp_accel(pn_accel(e.pos, e.vel, tgt.pos, tgt.vel; N = 4.0), 3000.0)
        @test e.comp[:a_ctrl] ≈ a_cmd atol = 1e-12           # :ideal → a_ctrl == a_cmd (pn path)
        @test e.comp[:a_ctrl] isa Vec3
        # and it is NOT the pursuit command (the branch really swapped — a different vector)
        a_pur = clamp_accel(pursuit_accel(e.pos, e.vel, tgt.pos; k_guid = 3.0), 3000.0)
        @test norm3(e.comp[:a_ctrl] - a_pur) > 1.0
    end

    @testset "PN intercepts the crossing with miss ≪ pursuit (Lesson 1, autopilot :ideal)" begin
        rp = fly_cpa!(pn_world(guidance = :pn)...)
        rq = fly_cpa!(pn_world(guidance = :pursuit)...)
        @test rp.miss < 5.0                                  # PN leads → clean intercept (probe: 0.03 m)
        @test rq.miss > 100.0                                # pursuit tail-chases → big miss (probe: 708 m)
        @test rq.miss > 20 * rp.miss                         # the RATIO is the headline (advisor: not PN abs)
        @test rp.sat_frac == 0.0                             # a_max generous — Lesson 2 held out here
    end

    @testset "|a_cmd| FALLS toward CPA under :pn, GROWS under :pursuit (the tail-chase foil)" begin
        rp = fly_cpa!(pn_world(guidance = :pn)...)
        rq = fly_cpa!(pn_world(guidance = :pursuit)...)
        # PN establishes the lead then coasts: demand falls off its early peak (probe: 213 → 46).
        @test at(rp.acmd, 0.7) < at(rp.acmd, 0.2)
        # pursuit points AT the target: the angle-off opens toward abeam, demand climbs (probe: 63 → 374).
        @test at(rq.acmd, 0.7) > at(rq.acmd, 0.2)
    end

    @testset "the :pursuit↔:pn trajectories DIFFER (not-a-dead-knob, physics-changing)" begin
        wp, sp = pn_world(guidance = :pn)
        wq, sq = pn_world(guidance = :pursuit)
        for _ in 1:3000
            tick!(wp, sp, dt); empty!(wp.events)
            tick!(wq, sq, dt); empty!(wq.events)
        end
        @test norm3(wp.entities[:m1].pos - wq.entities[:m1].pos) > 50.0   # a live outer knob
    end

    @testset "g-limit SATURATION on the wire — a bound a_max lifts the miss, more a_max closes it" begin
        # The hot glimit geometry (gate2_wire): missile 800 m/s / 5° (large heading error), a high
        # fast-crossing target — the unsaturated PN peak demand ≈ 785 m/s². Under a BINDING a_max the
        # missile can't turn hard enough EARLY → the collision triangle isn't set → the miss opens.
        hot = (m_vel = Vec3(800cosd(5), 0.0, 800sind(5)),
               t_pos = Vec3(4000.0, 0.0, 6500.0), t_vel = Vec3(-700.0, 0.0, -150.0))
        rbind = fly_cpa!(pn_world(guidance = :pn, a_max = 300.0; hot...)...)   # a_max BINDS
        rfree = fly_cpa!(pn_world(guidance = :pn, a_max = 1000.0; hot...)...)  # a_max clears the demand
        @test rbind.sat_frac > 0.3                           # the clamp binds most of the early turn (probe: 0.84)
        @test rbind.miss > 100.0                             # saturation opens the miss (probe: 410 m)
        @test rfree.miss < 5.0                               # clearing the demand → clean intercept (probe: 0.7 m)
        @test rbind.miss > 20 * rfree.miss                   # the a_max slider is the lever (Lesson 2)
        @test maximum(rbind.ademand) > 300.0                 # the pre-clamp demand exceeds a_max (saturation real)
    end

    @testset "loader: a guided :missile arms n_pn/r_stop at the consumed keys; rejects bad values" begin
        base = """
        name: pn
        seed: 10
        dt_physics: 0.001
        fidelity: {autopilot: ideal, guidance: pn}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {k_guid: 3.0, n_pn: 4.0, r_stop: 30.0, kp: 2.0, tau: 0.3, a_max: 3000.0}
          - id: tgt1
            kind: target
            pos: [6000.0, 0.0, 4200.0]
            vel: [-800.0, 0.0, 200.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            m = scn.world.entities[:m1]
            @test any(s -> s isa Autopilot, scn.subs)
            # n_pn / r_stop land at the CONSUMED comp keys (the slider→consumed-key discipline)
            @test m.comp[:n_pn] == 4.0 && m.comp[:r_stop] == 30.0
            @test get(scn.world.fidelity, :guidance, :pursuit) === :pn      # the reserved key, now filled
            # a defaulted block (no n_pn/r_stop authored) → the safe defaults (4.0 / 0.0 = cutoff off)
            defs = replace(base, "guidance: {k_guid: 3.0, n_pn: 4.0, r_stop: 30.0, kp: 2.0, tau: 0.3, a_max: 3000.0}" =>
                                  "guidance: {k_guid: 3.0, kp: 2.0, tau: 0.3, a_max: 3000.0}")
            pd = joinpath(dir, "defs.yaml"); write(pd, defs)
            md = load_scenario(pd).world.entities[:m1]
            @test md.comp[:n_pn] == 4.0 && md.comp[:r_stop] == 0.0
            # rejects: n_pn ≤ 0 (would null PN) and r_stop < 0 (meaningless) are AUTHORED load errors
            badn = replace(base, "n_pn: 4.0" => "n_pn: 0.0")
            p1 = joinpath(dir, "badn.yaml"); write(p1, badn)
            @test_throws ErrorException load_scenario(p1)
            badr = replace(base, "r_stop: 30.0" => "r_stop: -5.0")
            p2 = joinpath(dir, "badr.yaml"); write(p2, badr)
            @test_throws ErrorException load_scenario(p2)
        end
    end
end

# --- slice 11 gate 2: the noisy Seeker wired — the missile's FIRST observe! (phase 3) ---------
# "A missile is integrate! + observe! + decide!" (HANDOFF §3) COMPLETES here. PN reads a MEASURED
# LOS (noisy angle → α-β LOS-rate filter) instead of truth. autopilot :ideal / guidance :pn HELD so
# the miss isolates the SEEKER/filter (the slice-10 isolation, one knob further). Pins: observe!
# writes comp[:seeker_omega]/[:seeker_los] and decide! feeds them to pn_accel_from_omega (the phase-
# 3→phase-4 seam); FILTERED miss ≪ RAW miss on the wire (the Lesson); :raw SATURATES while :filtered
# doesn't; the :raw↔:filtered trajectories DIFFER (not-a-dead-knob); the Seeker draws EXACTLY 1
# randn/tick (draw-count-invariance — the FIRST non-vacuous RNG pin in the missile arc); a huge
# σ_seek slider pegs a_max but never crashes a tick; loader arms [BallisticMissile, Seeker,
# Autopilot] + rejects bad gains. Numbers PROBED against this live decide!→integrate! path
# (slice11_gate2_measure): σ=3 mrad, α=0.30, β=0.05 → filtered ~0.9 m, raw ~713 m, sat 0.01 vs 0.80.
@testset "guided missile — noisy seeker + α-β LOS-rate filter wired (slice 11, :seeker)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # The slice-10 crossing (slice10_pn geometry) + a Seeker (phase-3 observe!). SEED matters now —
    # the seeker is the FIRST w.rng consumer in the missile arc (the RNG inflection).
    function seeker_world(; seeker = :filtered, seed = 0, sigma = 3.0e-3, α = 0.30, β = 0.05,
                          n_pn = 4.0, r_stop = 30.0, a_max = 3000.0)
        w = World(seed = seed, fidelity = Dict(:autopilot => :ideal, :guidance => :pn, :seeker => seeker))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
            vel = Vec3(700cosd(12), 0.0, 700sind(12)),
            comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => 3.0, :n_pn => n_pn, :r_stop => r_stop,
                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :a_max => a_max,
                :sigma_seek => sigma, :alpha => α, :beta => β))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
            vel = Vec3(-800.0, 0.0, 200.0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
    end
    # Fly to FIRST CPA (the slice-10 discipline — miss at CPA from TRUTH; the seeker corrupts the
    # guidance, never the CPA measurement). Collects the saturation fraction over steered ticks.
    function fly_cpa!(w, subs; n = 40000, open_hold = 200)
        miss = Inf; nsat = 0; nguid = 0; opening = 0; prev = Inf
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]; r = tel["m1.los_range"]
            miss = min(miss, r)
            tel["m1.saturated"] > 0.5 && (nsat += 1); nguid += 1
            opening = r > prev ? opening + 1 : 0; prev = r
            get(w.entities[:m1].comp, :impacted, false) && break
            r < 1.0 && break
            (opening >= open_hold && r > miss + 50.0) && break
        end
        return (miss = miss, sat_frac = nsat / max(nguid, 1))
    end

    @testset "observe! writes seeker_omega/los; decide! feeds them to pn_accel_from_omega (the seam)" begin
        w, subs = seeker_world(seeker = :filtered, seed = 0)
        for _ in 1:100; tick!(w, subs, dt); empty!(w.events); end   # past tick 1 (ω=0) → a real ω
        e = w.entities[:m1]; c = e.comp; tgt = w.entities[:tgt1]
        @test haskey(c, :seeker_omega) && c[:seeker_omega] isa Vec3
        @test haskey(c, :seeker_los)   && c[:seeker_los]   isa Vec3
        @test norm3(c[:seeker_omega]) > 0.0                          # a real (nonzero) estimated ω — teeth
        # ω is in-plane (∥ ±y): the scalar reconstruction Vec3(0,−λ̇,0) has ZERO x/z components.
        @test c[:seeker_omega][1] == 0.0 && c[:seeker_omega][3] == 0.0
        # decide! consumed EXACTLY what observe! wrote (the phase-3→phase-4 seam): a_ctrl matches
        # pn_accel_from_omega(û_seek, ω_seek, TRUTH Vc) clamped — û FIRST, ω SECOND (an arg-swap
        # flips the command sign). Reads truth Vc from the post-integrate state decide! used.
        Vc = -range_rate(tgt.pos - e.pos, tgt.vel - e.vel)           # truth closing speed (§ scope)
        expected = clamp_accel(pn_accel_from_omega(c[:seeker_los], c[:seeker_omega], Vc; N = 4.0), 3000.0)
        @test c[:a_ctrl] ≈ expected atol = 1e-9
    end

    @testset "filtered miss ≪ raw miss on the wire (the Lesson, autopilot :ideal)" begin
        rf = fly_cpa!(seeker_world(seeker = :filtered, seed = 0)...)
        rr = fly_cpa!(seeker_world(seeker = :raw,      seed = 0)...)
        @test rf.miss < 5.0                                          # α-β recovers ≈ truth (measure: 0.90 m)
        @test rr.miss > 100.0                                        # naïve finite-diff blows up (measure: 713 m)
        @test rr.miss > 20 * rf.miss                                # the RATIO is the headline (measure: 793×)
    end

    @testset ":raw saturates a_max; :filtered does not (the saturation tell, reused from slice 10)" begin
        rf = fly_cpa!(seeker_world(seeker = :filtered, seed = 0)...)
        rr = fly_cpa!(seeker_world(seeker = :raw,      seed = 0)...)
        @test rr.sat_frac > 0.3                                      # N·Vc·(σ/dt) pegs a_max (measure: 0.80)
        @test rf.sat_frac < 0.1                                      # the filter keeps demand in-band (measure: 0.01)
    end

    @testset "the :raw↔:filtered trajectories DIFFER (not-a-dead-knob — the new combo's physics arm)" begin
        wr, sr = seeker_world(seeker = :raw, seed = 0)
        wf, sf = seeker_world(seeker = :filtered, seed = 0)
        for _ in 1:1500
            tick!(wr, sr, dt); empty!(wr.events)
            tick!(wf, sf, dt); empty!(wf.events)
        end
        # a toggle MOVES the missile (trajectory-changing); the DRAW-INVARIANCE half of the new
        # class-4a-AND-physics-changing combo is pinned in test_determinism (measure: max Δpos 122 m).
        @test norm3(wr.entities[:m1].pos - wf.entities[:m1].pos) > 10.0
    end

    @testset "the Seeker draws EXACTLY 1 randn/tick (draw-count-invariance, convention 3)" begin
        # The seeker is the ONLY w.rng consumer, so after N ticks w.rng must equal a fresh
        # Xoshiro(seed) advanced by N randn draws — proving 1 UNCONDITIONAL draw/tick, invariant to
        # the rung. Cross well past intercept (N=3000, post-CPA coast) so late ticks count too.
        for seeker in (:filtered, :raw), N in (500, 3000)
            w, subs = seeker_world(seeker = seeker, seed = 7)
            for _ in 1:N; tick!(w, subs, dt); empty!(w.events); end
            ref = Xoshiro(7); for _ in 1:N; randn(ref); end
            @test randn(copy(ref)) == randn(copy(w.rng))            # exactly N draws over N ticks
        end
    end

    @testset "a huge σ_seek slider pegs a_max but never crashes a tick (live-slider guard)" begin
        # sigma_seek is a KNOB — an absurd live value must not throw / NaN (the α-β β/dt floor + the
        # clamp_accel crash-guard). Peg it (5 rad of angular noise) and fly: no throw, all finite.
        w, subs = seeker_world(seeker = :raw, seed = 0, sigma = 5.0)
        ok = true
        for _ in 1:800
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].comp[:a_ctrl]) && all(isfinite, w.entities[:m1].pos) &&
                  isfinite(tel["m1.a_ach"]) && isfinite(tel["m1.lambda_dot_raw"])
            ok || break
        end
        @test ok
    end

    @testset "loader: a seeker missile arms [BallisticMissile, Seeker, Autopilot]; rejects bad gains" begin
        base = """
        name: sk
        seed: 11
        dt_physics: 0.001
        fidelity: {autopilot: ideal, guidance: pn, seeker: filtered}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {k_guid: 3.0, n_pn: 4.0, r_stop: 30.0, kp: 2.0, tau: 0.3, a_max: 3000.0}
              seeker: {sigma_seek: 0.003, alpha: 0.30, beta: 0.05}
          - id: tgt1
            kind: target
            pos: [6000.0, 0.0, 4200.0]
            vel: [-800.0, 0.0, 200.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            m = scn.world.entities[:m1]
            # a SEEKER missile: BallisticMissile (phase-1) + Seeker (phase-3) + Autopilot (phase-4),
            # NOT ConstantVelocity (the double-integration guard).
            @test any(s -> s isa Seeker, scn.subs)
            @test any(s -> s isa BallisticMissile, scn.subs)
            @test any(s -> s isa Autopilot, scn.subs)
            @test !any(s -> s isa ConstantVelocity && s.id === :m1, scn.subs)
            # the gains land at the CONSUMED comp keys (the slider→consumed-key discipline)
            @test m.comp[:sigma_seek] == 0.003 && m.comp[:alpha] == 0.30 && m.comp[:beta] == 0.05
            @test get(scn.world.fidelity, :seeker, :filtered) === :filtered   # the NEW key, now real
            # rejects: σ<0, α∉(0,1), β≤0 are AUTHORED load errors (a live slider is floored/clamped)
            for (tag, patt, repl) in (("negsig", "sigma_seek: 0.003", "sigma_seek: -0.001"),
                                      ("ahi",    "alpha: 0.30", "alpha: 1.0"),
                                      ("alo",    "alpha: 0.30", "alpha: 0.0"),
                                      ("blo",    "beta: 0.05",  "beta: 0.0"))
                p = joinpath(dir, "$tag.yaml"); write(p, replace(base, patt => repl))
                @test_throws ErrorException load_scenario(p)
            end
        end
    end
end

# --- slice 13 gate 2: the :scan seeker + :decoy wired — countermeasures (seduction vs gate) ----
# The slice-3 CFAR RANGE sandbox lifted onto the LOS-ANGLE axis: instead of ONE noisy truth bearing,
# the :scan seeker paints a lobe per {target, decoy} over a FIXED grid, DRAWS the noisy floor
# (2·N_p·N_bins randn — a draw-TOPOLOGY flip from :raw/:filtered's 1), CFAR-detects the peaks, and
# resolves the tracked bearing by the `discrimination` rung: `:none` blends ALL peaks (SEDUCED by the
# brighter/separated decoy → the aimpoint walks OFF → a miss) while `:gated` keeps only the NN peak to
# the α-β predicted bearing (the RGPO track-gate → the decoy rejected → intercept). THE HEADLINE is the
# AIMPOINT (bearing) error (FINDINGS #1 — clean by construction, independent of endgame saturation),
# with miss corroborating. THE TRUTH-PATH INVARIANT: the decoy is `kind === :decoy`, so `_nearest_target`
# (miss/CPA) ALWAYS references the true target — the seeker is seduced, but the honest miss is vs the
# thing it was supposed to hit. Draw count is EXACTLY 2·N_p·N_bins/tick, decoy-count-independent.
@testset "guided missile — :scan seeker + :decoy countermeasures wired (slice 13, :discrimination)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    Np = 10; Nb = 64                                             # the pinned scan grid (draw = 2·Np·Nb = 1280)

    # The slice-11 crossing + a :scan seeker + (optionally) a born-offset :decoy. The decoy sits Δ≈0.09
    # rad off the target bearing (≫ σ_beam so it RESOLVES into a second CFAR peak), 2× brighter, flying
    # PARALLEL (v = target vel) — the flare/off-board reading (born already-resolved; FINDINGS pivot #2).
    function scan_world(; disc = :none, seed = 6, decoy = true, tgt_amp = 40.0, dcy_amp = 80.0,
                        gate_hw = 0.045, a_max = 3000.0)
        w = World(seed = seed, fidelity = Dict(:autopilot => :ideal, :guidance => :pn,
                                               :seeker => :scan, :discrimination => disc))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
            vel = Vec3(700cosd(12), 0.0, 700sind(12)),
            comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0,
                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :a_max => a_max,
                :sigma_seek => 3.0e-3, :alpha => 0.30, :beta => 0.05,
                :scan_n_bins => Nb, :scan_bin_width => 0.005, :scan_sigma_beam => 0.015,
                :scan_floor => 1.0, :scan_n_pulses => Np, :scan_cfar_variant => :ca,
                :scan_cfar_ntrain => 16, :scan_cfar_nguard => 4, :scan_cfar_pfa => 1.0e-3,
                :gate_halfwidth => gate_hw))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
            vel = Vec3(-800.0, 0.0, 200.0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0, :intensity => tgt_amp))
        subs = Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
        if decoy
            w.entities[:dcy1] = Entity(:dcy1, :decoy; pos = Vec3(5868.0, 0.0, 4735.0),
                vel = Vec3(-800.0, 0.0, 200.0), comp = Dict{Symbol,Any}(:intensity => dcy_amp))
            push!(subs, ConstantVelocity(:dcy1))
        end
        return w, subs
    end

    # Fly to first CPA vs the TRUE target (decoy excluded); collect min-miss + the MIDCOURSE mean
    # aimpoint error |λ_est − λ_target| (the FINDINGS headline, clean of the endgame bearing blow-up).
    function fly_scan!(w, subs; n = 8000, open_hold = 200, aim_lo = 100, aim_hi = 1000)
        tgt = w.entities[:tgt1]
        miss = Inf; prev = Inf; opening = 0; aim_sum = 0.0; aim_n = 0
        for k in 1:n
            tick!(w, subs, dt); empty!(w.events)
            r = los_range(w.entities[:m1].pos, tgt.pos)             # vs the TRUE target (truth-path)
            miss = min(miss, r)
            tel = w.env[:telemetry]
            if aim_lo <= k <= aim_hi && haskey(tel, "m1.aim_error")
                aim_sum += tel["m1.aim_error"]; aim_n += 1
            end
            get(w.entities[:m1].comp, :impacted, false) && break
            r < 1.0 && break
            opening = r > prev ? opening + 1 : 0; prev = r
            (opening >= open_hold && r > miss + 50.0) && break
        end
        return (miss = miss, aim = aim_n == 0 ? NaN : aim_sum / aim_n)
    end

    @testset "observe! paints/scans → seeker_omega/los + n_peaks telemetry (the phase-3 seam)" begin
        w, subs = scan_world(disc = :gated, seed = 6)
        for _ in 1:200; tick!(w, subs, dt); empty!(w.events); end
        c = w.entities[:m1].comp; tel = w.env[:telemetry]
        @test haskey(c, :seeker_omega) && c[:seeker_omega] isa Vec3
        @test c[:seeker_omega][1] == 0.0 && c[:seeker_omega][3] == 0.0   # in-plane ∥ ±y
        @test norm3(c[:seeker_omega]) > 0.0                              # a real estimated ω
        # the NEW scan telemetry — SCALARS only (no Array → no float()-crash); ≥2 peaks (target+decoy)
        @test haskey(tel, "m1.aim_error") && isfinite(tel["m1.aim_error"])
        @test haskey(tel, "m1.n_peaks")   && tel["m1.n_peaks"] >= 1      # CFAR detected ≥1 peak
        @test tel["m1.gated"] == 1.0                                     # the active rung readout
        @test isfinite(tel["m1.target_bearing"]) && isfinite(tel["m1.decoy_bearing"])
    end

    @testset ":none is SEDUCED, :gated HOLDS — aimpoint error (the Lesson, FINDINGS #1)" begin
        rn = fly_scan!(scan_world(disc = :none,  seed = 6)...)
        rg = fly_scan!(scan_world(disc = :gated, seed = 6)...)
        # aimpoint (bearing) error: :none blends the decoy in → walks OFF (≈4°); :gated NN-gates it out
        # (≈0.05°). Conservative one-sided bounds + the RATIO (probe: 3.97° vs 0.056°, ~71×).
        @test rg.aim < deg2rad(0.5)                                     # :gated tracks the truth (< 0.5°)
        @test rn.aim > deg2rad(2.0)                                     # :none is pulled off (> 2°)
        @test rn.aim > 20 * rg.aim                                      # the aim RATIO is the headline
        # miss CORROBORATES (born-offset makes it clean here): :gated intercepts, :none misses wide.
        @test rg.miss < 5.0                                             # :gated intercepts (probe 0.06 m)
        @test rn.miss > 100.0                                           # :none seduced → misses (probe 539 m)
    end

    @testset "the :none↔:gated trajectories DIFFER (not-a-dead-knob; RNG in lockstep)" begin
        wn, sn = scan_world(disc = :none,  seed = 6)
        wg, sg = scan_world(disc = :gated, seed = 6)
        for _ in 1:2000
            tick!(wn, sn, dt); empty!(wn.events)
            tick!(wg, sg, dt); empty!(wg.events)
        end
        # a toggle MOVES the missile (trajectory-changing); the draw-INVARIANCE half (both draw the same
        # 2·Np·Nb) is pinned below + in test_determinism — the "draw-invariant within a 4b host" combo.
        @test norm3(wn.entities[:m1].pos - wg.entities[:m1].pos) > 10.0
    end

    @testset "miss/CPA is vs the true :target, NEVER the :decoy (the truth-path invariant)" begin
        # _nearest_target excludes :decoy (kind === :decoy), so even the SEDUCED :none miss is measured
        # against the true target — the honest miss against the thing the missile was supposed to hit.
        w, subs = scan_world(disc = :none, seed = 6)
        @test EWSim._nearest_target(w, w.entities[:m1]).id === :tgt1     # the decoy is NOT the nearest target
        @test EWSim._nearest_decoy(w, w.entities[:m1]).id === :dcy1      # the decoy IS visible to the seeker
    end

    @testset "draw count EXACTLY 2·N_p·N_bins/tick, decoy-count-INDEPENDENT (convention 3 keystone)" begin
        # The :scan seeker is the ONLY w.rng consumer; after N ticks w.rng == Xoshiro(seed) advanced by
        # 2·Np·Nb·N draws — the topology flip from :raw/:filtered's 1/tick. Pin it decoy PRESENT and
        # ABSENT (the fixed grid → the count can't depend on how many lobes are painted).
        for decoy in (true, false), N in (300, 2000), disc in (:none, :gated)
            w, subs = scan_world(disc = disc, seed = 7, decoy = decoy)
            for _ in 1:N; tick!(w, subs, dt); empty!(w.events); end
            ref = Xoshiro(7); for _ in 1:(2*Np*Nb*N); randn(ref); end
            @test randn(copy(ref)) == randn(copy(w.rng))                # exactly 2·Np·Nb draws/tick
        end
    end

    @testset "composition golden: _observe_scan! λ_est is byte-pinned per rung (convention 2)" begin
        # The draw-count keystone above pins the RNG STREAM; the estimation.jl unit goldens pin each
        # deterministic link (angular_grid / paint_angular_profile! / _draw_profile! / extract_peaks /
        # intensity_centroid / validation_gate). This locks the LAST link — the _observe_scan! WIRING
        # (λ_pred grid center, the tick-1 cued-lock truth seed, the disc→selection arg order, the α-β
        # update) — end-to-end, so a silent refactor can't desync replay while sailing under the loose
        # lesson bounds (aim < 0.5° vs 0.056°, ~9× margin). `===` is Float64 bit-equality; probed off the
        # live tick! path at seed 6 (convention 10). The two rungs DIVERGE from tick 1: `:none` walks the
        # aimpoint OFF toward the brighter decoy (λ_est climbs), `:gated` NN-gates it out (λ_est holds).
        gold = Dict(
            :none  => [0.21621316295743476, 0.23306850480364805, 0.2446078687413303],
            :gated => [0.1957472248935027,  0.1959439136332688,  0.19677838734434888])
        for disc in (:none, :gated)
            w, subs = scan_world(disc = disc, seed = 6)
            for k in 1:3
                tick!(w, subs, dt); empty!(w.events)
                @test w.entities[:m1].comp[:seek_lambda_est] === gold[disc][k]
            end
        end
    end

    @testset "a huge decoy intensity / wide gate never crashes a tick (live-slider guard)" begin
        # intensity + gate_halfwidth are KNOBS — absurd live values just paint a taller lobe / widen the
        # gate; no throw / NaN (√(power/2) stays finite; validation_gate is safe at any halfwidth).
        w, subs = scan_world(disc = :gated, seed = 6, dcy_amp = 5.0e8, gate_hw = 3.0)
        ok = true
        for _ in 1:600
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].comp[:a_ctrl]) && all(isfinite, w.entities[:m1].pos) &&
                  isfinite(tel["m1.aim_error"])
            ok || break
        end
        @test ok
    end

    @testset "loader: a :scan missile + :decoy arm; rejects bad scan/decoy config" begin
        base = """
        name: cm
        seed: 6
        dt_physics: 0.001
        fidelity: {autopilot: ideal, guidance: pn, seeker: scan, discrimination: none}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {k_guid: 3.0, n_pn: 4.0, r_stop: 30.0, kp: 2.0, tau: 0.3, a_max: 3000.0}
              seeker:
                sigma_seek: 0.003
                alpha: 0.30
                beta: 0.05
                n_bins: 64
                bin_width: 0.005
                sigma_beam: 0.015
                n_pulses: 10
                cfar_variant: ca
                cfar_n_train: 16
                cfar_n_guard: 4
                cfar_pfa: 0.001
                gate_halfwidth: 0.045
          - id: tgt1
            kind: target
            pos: [6000.0, 0.0, 4200.0]
            vel: [-800.0, 0.0, 200.0]
            target: {rcs_m2: 1.0, intensity: 40.0}
          - id: dcy1
            kind: decoy
            pos: [5868.0, 0.0, 4735.0]
            vel: [-800.0, 0.0, 200.0]
            decoy: {intensity: 80.0}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            m = scn.world.entities[:m1]; d = scn.world.entities[:dcy1]
            @test any(s -> s isa Seeker, scn.subs)                       # the :scan seeker is armed
            @test d.kind === :decoy                                      # the decoy is :decoy, NOT :target
            @test any(s -> s isa ConstantVelocity && s.id === :dcy1, scn.subs)   # a passive mover
            @test m.comp[:scan_n_bins] == 64 && m.comp[:scan_n_pulses] == 10     # scan config at consumed keys
            @test m.comp[:scan_cfar_variant] === :ca
            @test m.comp[:gate_halfwidth] == 0.045
            @test d.comp[:intensity] == 80.0 && scn.world.entities[:tgt1].comp[:intensity] == 40.0
            @test get(scn.world.fidelity, :discrimination, :none) === :none      # the NEW key, default reveals the fix
            # rejects the AUTHORED bad configs (each a clear load error, not a throw inside observe!):
            for (tag, patt, repl) in (("negint",  "intensity: 80.0",   "intensity: -1.0"),      # decoy intensity < 0
                                      ("oddtrain", "cfar_n_train: 16",  "cfar_n_train: 15"),     # odd n_train
                                      ("nobins",   "n_bins: 64",        "n_bins: 0"),            # N_bins < 1
                                      ("osnp",     "cfar_variant: ca",  "cfar_variant: os"),     # os + n_pulses>1 (throws in cfar)
                                      ("badbeam",  "sigma_beam: 0.015", "sigma_beam: 0.0"),      # σ_beam ≤ 0
                                      ("badhw",    "gate_halfwidth: 0.045", "gate_halfwidth: 0.0")) # hw ≤ 0
                p = joinpath(dir, "$tag.yaml"); write(p, replace(base, patt => repl))
                @test_throws ErrorException load_scenario(p)
            end
        end
    end
end

# --- slice 12 gate 2: augmented PN wired + the ManeuveringTarget curving mover ----------------
# The RNG-free payoff of the missile arc: against a MANEUVERING target (a new phase-1 mover,
# ManeuveringTarget, applying a constant lateral g-turn) plain PN lags by the target-accel term and,
# under a BINDING g-limit, SATURATES → misses; APN's `(N/2)·a_T⊥` feedforward (Autopilot.decide!'s
# `:apn` branch, reading the mover's truth `comp[:a_target]`) anticipates → low demand → intercept
# (HANDOFF §10 item 10 — "g-limit saturation modeled, this is why augmented PN matters"). autopilot
# :ideal HELD so the miss isolates the GUIDANCE LAW. Numbers PROBED against this live wired
# decide!→integrate! path (wire_probe.jl, convention 10) — conservative one-sided bounds, NOT the
# frame-sampling ratio. Determinism/byte-identity is the SLICE-10 shape (physics-changing, NO RNG —
# ManeuveringTarget/`:apn` add no `w.rng` draw; the slice-11 RNG-inflection language INVERTS here).
@testset "guided missile — augmented PN + maneuvering target wired (slice 12, :apn)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # The g-limited engagement (wire_probe): the slice10_pn crossing + a HARD maneuver (a_lat=200,
    # ⟂-v, turn-sign=+1 — the clean CPA direction) + a BINDING a_max=200. r_stop=30, :ideal actuator.
    function apn_world(; guidance = :apn, a_lat = 200.0, turn_sign = 1.0, a_max = 200.0, n_pn = 4.0,
                       maneuver = true,
                       m_vel = Vec3(700cosd(12), 0.0, 700sind(12)),
                       t_pos = Vec3(6000.0, 0.0, 4200.0), t_vel = Vec3(-800.0, 0.0, 200.0))
        w = World(seed = 0, fidelity = Dict(:autopilot => :ideal, :guidance => guidance))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0), vel = m_vel,
            comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => 3.0, :n_pn => n_pn, :r_stop => 30.0,
                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :a_max => a_max))
        tcomp = Dict{Symbol,Any}(:rcs_m2 => 1.0)
        # `maneuver` arms the curving mover (a_lat/turn_sign); else a plain ConstantVelocity target.
        if maneuver
            tcomp[:a_lat_mps2] = a_lat; tcomp[:turn_sign] = turn_sign
            tsub = ManeuveringTarget(:tgt1)
        else
            tsub = ConstantVelocity(:tgt1)
        end
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = t_pos, vel = t_vel, comp = tcomp)
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), tsub]
    end
    # Fly to FIRST CPA (the slice-10 discipline): min los_range up to where the target has clearly
    # passed and range is opening; collect the saturation fraction (the mechanism tell).
    function fly_cpa!(w, subs; n = 40000, open_hold = 200)
        miss = Inf; nsat = 0; nguid = 0; opening = 0; prev = Inf
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]; r = tel["m1.los_range"]
            miss = min(miss, r)
            tel["m1.saturated"] > 0.5 && (nsat += 1); nguid += 1
            opening = r > prev ? opening + 1 : 0; prev = r
            get(w.entities[:m1].comp, :impacted, false) && break
            r < 1.0 && break
            (opening >= open_hold && r > miss + 50.0) && break
        end
        return (miss = miss, sat_frac = nsat / max(nguid, 1), n = nguid)
    end

    @testset "ManeuveringTarget curves the target + writes truth comp[:a_target] (⟂ v, |a|=a_lat)" begin
        w = World(seed = 0)
        w.entities[:t] = Entity(:t, :target; pos = Vec3(6000.0, 0.0, 4200.0), vel = Vec3(-800.0, 0.0, 200.0),
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0, :a_lat_mps2 => 200.0, :turn_sign => 1.0))
        mt = ManeuveringTarget(:t)
        v0 = w.entities[:t].vel; spd0 = norm3(v0); p0 = w.entities[:t].pos
        integrate!(mt, w, dt)                                  # phase-1 mover (its only phase)
        aT = w.entities[:t].comp[:a_target]; v1 = w.entities[:t].vel
        # the TRUTH accel is a COORDINATED turn: ⟂ velocity, magnitude a_lat, planar (x-z, no y) —
        # an INDEPENDENT recompute (⟂ + magnitude), NOT a call to the internal _lateral_accel.
        @test aT isa Vec3
        @test aT[2] == 0.0                                    # planar x-z (no cross-range)
        @test EWSim._dot(aT, v1) ≈ 0.0 atol = 1e-6            # ⟂ to velocity (speed-preserving turn)
        @test norm3(aT) ≈ 200.0 atol = 1e-6                   # magnitude == a_lat
        # curved + speed-preserving (RK4 holds a ⟂-v turn's speed to ~machine eps).
        for _ in 1:2000; integrate!(mt, w, dt); end
        @test norm3(w.entities[:t].vel) ≈ spd0 atol = 1e-3    # speed preserved (probe: -2.7e-12 drift)
        # the heading ROTATED (the path curved away from the straight-line extrapolation).
        v̂0 = v0 / spd0; v̂n = w.entities[:t].vel / norm3(w.entities[:t].vel)
        @test norm3(v̂n - v̂0) > 0.05                           # direction changed (curving)
        straight = p0 + v0 * (2001 * dt)                      # where a CV target would be
        @test norm3(w.entities[:t].pos - straight) > 1.0      # the maneuver bent the path
    end

    @testset "decide! under :apn writes comp[:a_ctrl] matching pn_accel_augmented on the realized state" begin
        w, subs = apn_world(guidance = :apn, a_lat = 200.0, a_max = 3000.0)   # generous a_max → clamp inert
        tick!(w, subs, dt); empty!(w.events)                  # tick 1: mover writes a_target, decide! commands
        e = w.entities[:m1]; tgt = w.entities[:tgt1]
        aT = tgt.comp[:a_target]::Vec3                        # the mover's truth accel this tick
        û = los_unit(e.pos, tgt.pos); rp = tgt.pos - e.pos; rv = tgt.vel - e.vel
        a_apn = clamp_accel(pn_accel_augmented(û, los_rate(rp, rv), -range_rate(rp, rv), aT; N = 4.0), 3000.0)
        @test e.comp[:a_ctrl] ≈ a_apn atol = 1e-10            # :ideal → a_ctrl == a_cmd (the :apn path)
        # the feedforward REALLY added — the command differs from the plain-:pn command (not a no-op).
        a_pn = clamp_accel(pn_accel(e.pos, e.vel, tgt.pos, tgt.vel; N = 4.0), 3000.0)
        @test norm3(e.comp[:a_ctrl] - a_pn) > 1.0             # (N/2)·a_T⊥ shifted the command
    end

    @testset "APN intercepts the maneuvering target where PN SATURATES + misses (the g-limit Lesson)" begin
        rpn  = fly_cpa!(apn_world(guidance = :pn)...)
        rapn = fly_cpa!(apn_world(guidance = :apn)...)
        rpur = fly_cpa!(apn_world(guidance = :pursuit)...)
        @test rpn.miss  > 100.0                               # PN saturates chasing the maneuver → miss (wire: 166.8)
        @test rapn.miss < 5.0                                 # APN anticipates → tight intercept (wire: 0.85)
        @test rpn.miss  > 20 * rapn.miss                      # the RATIO is the headline (advisor: not the abs)
        @test rpn.sat_frac  > 0.3                             # PN's demand PEGS a_max most of the turn (wire: 0.63)
        @test rapn.sat_frac < 0.05                            # APN never saturates — the mechanism (wire: 0.00)
        @test rpur.miss > 100.0                               # the pursuit foil rides along + misses (wire: 261.6)
    end

    @testset "the a_max slider is the lesson knob — a larger a_max lets PN recover; APN flat" begin
        # The g-limit is the BINDING constraint: raise a_max and PN's demand fits → it intercepts too
        # (proving the miss was saturation, not a PN defect). APN is flat (it never needed the headroom).
        rbind = fly_cpa!(apn_world(guidance = :pn,  a_max = 200.0)...)   # binds → miss
        rfree = fly_cpa!(apn_world(guidance = :pn,  a_max = 350.0)...)   # clears the demand → hit
        rapn  = fly_cpa!(apn_world(guidance = :apn, a_max = 200.0)...)
        @test rbind.miss > 100.0                              # a_max=200 saturates PN (wire: 166.8)
        @test rfree.miss < 5.0                                # a_max=350 → PN recovers (wire: 0.3)
        @test rbind.miss > 20 * rfree.miss                    # the slider is the lever
        @test rapn.miss  < 5.0                                # APN intercepts at the BINDING a_max (wire: 0.85)
    end

    @testset "the :pn↔:apn trajectories DIFFER (not-a-dead-knob, physics-changing, no RNG)" begin
        wp, sp = apn_world(guidance = :apn); wq, sq = apn_world(guidance = :pn)
        for _ in 1:3000
            tick!(wp, sp, dt); empty!(wp.events)
            tick!(wq, sq, dt); empty!(wq.events)
        end
        @test norm3(wp.entities[:m1].pos - wq.entities[:m1].pos) > 50.0   # a live outer knob moves the missile
    end

    @testset ":apn on a CONSTANT-VELOCITY target ≈ :pn — the feedforward vanishes (a_T = 0)" begin
        # No maneuver (plain ConstantVelocity target): decide!'s `:apn` branch reads the default
        # a_T = zero(Vec3), so `(N/2)·a_T⊥` vanishes and APN reduces to plain PN (introduce-safe).
        rapn = fly_cpa!(apn_world(guidance = :apn, maneuver = false, a_max = 3000.0)...)
        rpn  = fly_cpa!(apn_world(guidance = :pn,  maneuver = false, a_max = 3000.0)...)
        @test rapn.miss ≈ rpn.miss atol = 1e-6                # feedforward vanishes → same trajectory (wire: |Δ|=0)
    end

    @testset "loader: a `maneuver:` block arms ManeuveringTarget (NOT ConstantVelocity); rejects bad a_lat" begin
        base = """
        name: apn
        seed: 12
        dt_physics: 0.001
        fidelity: {autopilot: ideal, guidance: apn}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {n_pn: 4.0, r_stop: 30.0, kp: 2.0, tau: 0.3, a_max: 200.0}
          - id: tgt1
            kind: target
            pos: [6000.0, 0.0, 4200.0]
            vel: [-800.0, 0.0, 200.0]
            target: {rcs_m2: 1.0, maneuver: {a_lat_mps2: 200.0, turn_sign: 1.0}}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            t = scn.world.entities[:tgt1]
            # a MANEUVERING target gets ManeuveringTarget, NOT ConstantVelocity (the swap).
            @test any(s -> s isa ManeuveringTarget && s.id === :tgt1, scn.subs)
            @test !any(s -> s isa ConstantVelocity && s.id === :tgt1, scn.subs)
            # a_lat/turn_sign land at the CONSUMED comp keys (the slider→consumed-key discipline).
            @test t.comp[:a_lat_mps2] == 200.0 && t.comp[:turn_sign] == 1.0
            @test get(scn.world.fidelity, :guidance, :pursuit) === :apn   # the third rung, now real
            # a PLAIN target (no maneuver: block) stays ConstantVelocity → byte-identical to slices 1..11.
            plain = replace(base, ", maneuver: {a_lat_mps2: 200.0, turn_sign: 1.0}" => "")
            pp = joinpath(dir, "plain.yaml"); write(pp, plain)
            sp = load_scenario(pp)
            @test any(s -> s isa ConstantVelocity && s.id === :tgt1, sp.subs)
            @test !any(s -> s isa ManeuveringTarget, sp.subs)
            # a defaulted maneuver block (no a_lat authored) → a_lat defaults to 0 (straight-line).
            defd = replace(base, "maneuver: {a_lat_mps2: 200.0, turn_sign: 1.0}" => "maneuver: {turn_sign: 1.0}")
            pd = joinpath(dir, "defd.yaml"); write(pd, defd)
            @test load_scenario(pd).world.entities[:tgt1].comp[:a_lat_mps2] == 0.0
            # rejects: a non-finite a_lat is an AUTHORED load error (a huge finite slider just curves harder).
            bad = replace(base, "a_lat_mps2: 200.0" => "a_lat_mps2: .inf")
            pb = joinpath(dir, "bad.yaml"); write(pb, bad)
            @test_throws ErrorException load_scenario(pb)
        end
    end
end

# --- slice 15 gate 2: the rate-limited fin servo wired (:fin) — the g-onset cap on the wire ----
# The :fin autopilot rung on a truth-fed PN missile vs a maneuvering target. Pins the WIRING: the
# achieved-g BUILD RATE is HARD-CAPPED at k_δ·δ̇_max (the g-onset cap — telemetry `g_onset`, ≤ the cap
# EVERYWHERE by construction), the RATE limit BINDS (fin_rate_sat>0) while the DEFLECTION/g-limit does
# NOT (fin_defl_sat==0 && saturated==0 — the isolation, advisor #2), yet the MISS stays small (PN
# robust — the "lack of effect" IS the lesson, motivating 6-DOF). :ideal is UNCAPPED (its vector
# g-onset ≫ the cap); the :ideal↔:pid↔:fin trajectories DIFFER (not-a-dead-knob, class 4c — no RNG).
# The loader validates the fin params >0. The fin telemetry keys are SCALARS (no Array → no float()
# client crash — convention 13). The g-cap δ_max·k_δ=2500 ≤ a_max=2600 (δ_max is the g-limit), and
# the rate cap k_δ·δ̇_max=2000 is DISTINCT from both (δ̇_max=0.4) — the three numbers are separable.
@testset "fin servo wired (slice 15, :fin) — g-onset cap + isolation + PN robustness" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    kδ = 5000.0; δmax = 0.5; Gcap = kδ * δmax                # effective g-cap 2500 ≤ a_max 2600
    R_WIN = 200.0                                            # mid-course window (outside the r_stop=30 endgame)

    # A crossing + maneuvering engagement (the slice-12 geometry) with the rate-limited fin plant.
    # a_max=2600 GENEROUS (δ_max is the g-limit); δ̇_max is the lesson slider; kd=0 (no derivative kick).
    function fin_world(; autopilot = :fin, δ̇max = 0.4, a_lat = 160.0, a_max = 2600.0)
        w = World(seed = 0, fidelity = Dict(:autopilot => autopilot, :guidance => :pn))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
            vel = Vec3(700cosd(12), 0.0, 700sind(12)),
            comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0,
                :kp => 3.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :a_max => a_max,
                :k_delta => kδ, :delta_max => δmax, :delta_rate_max => δ̇max, :tau_fin => 0.02))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
            vel = Vec3(-800.0, 0.0, 200.0),
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0, :a_lat_mps2 => a_lat, :turn_sign => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ManeuveringTarget(:tgt1)]
    end
    # Fly to first CPA, collecting: miss; peak VECTOR g-onset from comp[:a_ctrl] (mode-agnostic, whole
    # flight — the cap holds everywhere by construction, so this is the strongest bound); whether the
    # rate/defl/a_max clamps EVER bind in the mid-course window (r > R_WIN — the clean isolation window).
    function fly!(w, subs; n = 40000)
        miss = Inf; a_prev = nothing; peak_onset = 0.0
        any_rate_sat = false; any_defl_sat = false; any_sat = false; keys_seen = false; last_tel = nothing
        opening = 0; prev = Inf
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]; last_tel = tel; r = tel["m1.los_range"]
            miss = min(miss, r)
            a = w.entities[:m1].comp[:a_ctrl]::Vec3
            a_prev !== nothing && (peak_onset = max(peak_onset, norm3(a - a_prev) / dt))
            a_prev = a
            if haskey(tel, "m1.g_onset")                     # :fin ships these
                keys_seen = true
                if r > R_WIN
                    tel["m1.fin_rate_sat"] > 0.5 && (any_rate_sat = true)
                    tel["m1.fin_defl_sat"] > 0.5 && (any_defl_sat = true)
                    tel["m1.saturated"]    > 0.5 && (any_sat = true)
                end
            end
            get(w.entities[:m1].comp, :impacted, false) && break
            r < 1.0 && break
            opening = r > prev ? opening + 1 : 0; prev = r
            (opening >= 200 && r > miss + 50.0) && break
        end
        return (miss = miss, peak_onset = peak_onset, rate_sat = any_rate_sat,
                defl_sat = any_defl_sat, sat = any_sat, keys = keys_seen, tel = last_tel)
    end

    @testset "the g-onset cap BINDS on the wire, ISOLATED; miss stays small (PN robust)" begin
        rf = fly!(fin_world(autopilot = :fin, δ̇max = 0.4)...)
        cap_onset = kδ * 0.4                                  # 2000 m/s³ (distinct from Gcap=2500, a_max=2600)
        @test rf.keys                                        # the :fin telemetry keys ship
        @test rf.peak_onset <= 1.02 * cap_onset              # achieved-g BUILD RATE HARD-CAPPED (everywhere)
        @test rf.rate_sat                                    # the RATE limit BINDS (the lesson is live)
        @test !rf.defl_sat                                   # δ_max does NOT bind (isolation — advisor #2)
        @test !rf.sat                                        # a_max does NOT bind (isolation — advisor #2)
        @test rf.miss < 10.0                                 # PN homes fine despite the cap (the "lack of effect")
        # the telemetry keys are SCALARS (no Array → no float() client crash — convention 13)
        @test rf.tel["m1.fin_defl"] isa Real && rf.tel["m1.fin_rate"] isa Real && rf.tel["m1.g_onset"] isa Real
        @test rf.tel["m1.fin_rate_sat"] isa Real && rf.tel["m1.fin_defl_sat"] isa Real
    end

    @testset ":ideal is UNCAPPED (g-onset ≫ the cap) + ships NO fin keys (byte-identical wire)" begin
        ri = fly!(fin_world(autopilot = :ideal)...)
        cap_onset = kδ * 0.4
        @test !ri.keys                                       # :ideal ships NO fin telemetry keys
        @test ri.peak_onset > 2.0 * cap_onset                # :ideal follows a_cmd's steps → uncapped onset
    end

    @testset "the :ideal↔:pid↔:fin trajectories DIFFER (not-a-dead-knob, class 4c, no RNG)" begin
        wi, si = fin_world(autopilot = :ideal)
        wp, sp = fin_world(autopilot = :pid)
        wf, sf = fin_world(autopilot = :fin)
        for _ in 1:1500
            tick!(wi, si, dt); empty!(wi.events)
            tick!(wp, sp, dt); empty!(wp.events)
            tick!(wf, sf, dt); empty!(wf.events)
        end
        pi = wi.entities[:m1].pos; pp = wp.entities[:m1].pos; pf = wf.entities[:m1].pos
        @test norm3(pi - pf) > 1.0                           # :ideal vs :fin — the plant reshapes the path
        @test norm3(pp - pf) > 0.1                           # :pid vs :fin — a different plant (rate cap vs lag)
    end

    @testset "loader validates the fin params > 0 (k_delta/delta_max/delta_rate_max/tau_fin)" begin
        base = """
        name: fin
        seed: 3
        dt_physics: 0.001
        fidelity: {autopilot: fin, guidance: pn}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {n_pn: 4.0, r_stop: 30.0, kp: 3.0, tau: 0.3, a_max: 2600.0, k_delta: 5000.0, delta_max: 0.5, delta_rate_max: 0.4, tau_fin: 0.02}
          - id: tgt1
            kind: target
            pos: [6000.0, 0.0, 4200.0]
            vel: [-800.0, 0.0, 200.0]
            target: {rcs_m2: 1.0, maneuver: {a_lat_mps2: 160.0, turn_sign: 1.0}}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            m = scn.world.entities[:m1]
            @test m.comp[:k_delta] == 5000.0 && m.comp[:delta_max] == 0.5
            @test m.comp[:delta_rate_max] == 0.4 && m.comp[:tau_fin] == 0.02
            @test get(scn.world.fidelity, :autopilot, :ideal) === :fin
            # each authored fin param must be > 0 (the mass/a_max/tau LOAD-validation precedent).
            for (field, badval) in (("k_delta: 5000.0", "k_delta: 0.0"),
                                    ("delta_max: 0.5", "delta_max: -0.1"),
                                    ("delta_rate_max: 0.4", "delta_rate_max: 0.0"),
                                    ("tau_fin: 0.02", "tau_fin: -1.0"))
                bad = replace(base, field => badval)
                p = joinpath(dir, "bad_$(field[1:3]).yaml"); write(p, bad)
                @test_throws ErrorException load_scenario(p)
            end
        end
    end
end

# --- slice 14 gate 2: cooperative salvo guidance wired (the capstone, :cooperation) -----------
# N interceptors share time-to-go over an ideal datalink to arrive SIMULTANEOUSLY (HANDOFF §10 item
# 13). The `SalvoCoordinator` (phase-2 build_env!, on a `:datalink` node) pools `kind===:missile`
# t_go into the fixed-at-launch consensus `w.env[:salvo_t_d] = T_d − w.t` (single-writer); each
# `Autopilot.decide!` (phase 4) reads it under `coop===:salvo` and flies impact-time-control guidance
# (PN base + a ⟂-LOS impact-time-error feedback that STRETCHES an early missile). autopilot=:ideal,
# guidance=:pn, NO seeker in every arm (the cooperation lesson isolated as slice 12 isolated APN — no
# RNG, class 4c). Geometry F (gate-0 FINDINGS): a MOVING target at altitude (an AIR intercept, so the
# metric is first-CPA time of los_range, NOT the ground :impact — the plan §4 correction), a NEAR
# missile A (natural t_go≈5.0 s) + a FAR missile B (≈7.4 s) → :solo spreads Δτ≈2.34, :salvo collapses
# it to ≈0.52 (K_it=0.45) while both still hit.
@testset "cooperative salvo guidance wired (slice 14, :cooperation)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)
    TGT0 = Vec3(9000.0, 0.0, 4500.0); TGTV = Vec3(-500.0, 0.0, 0.0)
    MA0  = Vec3(3000.0, 0.0, 3000.0); MB0  = Vec3(0.0, 0.0, 3000.0); SPEED = 750.0

    # geometry-F world: 2 [BallisticMissile, Autopilot] interceptors + a common ConstantVelocity
    # target + a [SalvoCoordinator] :datalink node. cooperation selects :solo (plain PN) vs :salvo.
    function salvo_world(; cooperation = :salvo, k_it = 0.45, seed = 7)
        w = World(seed = seed, fidelity = Dict{Symbol,Symbol}(:guidance => :pn, :autopilot => :ideal,
                                                              :cooperation => cooperation))
        gains() = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
            :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0, :kp => 2.0, :ki => 0.0, :kd => 0.0,
            :tau => 0.3, :a_max => 3000.0, :k_it => k_it)
        w.entities[:mA] = Entity(:mA, :missile; pos = MA0, vel = SPEED * los_unit(MA0, TGT0), comp = gains())
        w.entities[:mB] = Entity(:mB, :missile; pos = MB0, vel = SPEED * los_unit(MB0, TGT0), comp = gains())
        w.entities[:tgt] = Entity(:tgt, :target; pos = TGT0, vel = TGTV, comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        w.entities[:link] = Entity(:link, :datalink; pos = zero(Vec3), comp = Dict{Symbol,Any}())
        subs = Subsystem[BallisticMissile(:mA), Autopilot(:mA), BallisticMissile(:mB), Autopilot(:mB),
                         ConstantVelocity(:tgt), SalvoCoordinator(:link)]
        return w, subs
    end
    # first-CPA time (descending band; [[ewsim-missile-verifier-sampling]]) of each missile's
    # los_range stream — the honest arrival metric for an AIR intercept (excludes post-CPA re-cross).
    function fly_taus(w, subs; n = 9000)
        rA = Float64[]; rB = Float64[]
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            push!(rA, get(tel, "mA.los_range", Inf)); push!(rB, get(tel, "mB.los_range", Inf))
        end
        cpa(r) = (m = r[1]; im = 1; for i in 2:length(r)
                      r[i] < m ? (m = r[i]; im = i) : (i - im > 200 && r[i] > m + 100.0 && break); end; (m, im))
        mA, iA = cpa(rA); mB, iB = cpa(rB)
        return (τA = iA * dt, τB = iB * dt, Δτ = abs(iA - iB) * dt, missA = mA, missB = mB)
    end

    @testset "SalvoCoordinator publishes w.env[:salvo_t_d] == max(t_go) − w.t (single-writer, phase 2)" begin
        w, subs = salvo_world(cooperation = :salvo)
        tick!(w, subs, dt); empty!(w.events)                  # tick 1: coordinator latches T_d, publishes
        @test haskey(w.env, :salvo_t_d)
        # INDEPENDENT recompute of the consensus on the realized (post-tick-1) 2-missile world.
        tgt = w.entities[:tgt]
        tgo(m) = time_to_go(los_range(m.pos, tgt.pos), -range_rate(tgt.pos - m.pos, tgt.vel - m.vel))
        Td = salvo_consensus((tgo(w.entities[:mA]), tgo(w.entities[:mB])))
        # w.t was 0.0 during tick-1 build_env! (pre-increment) → salvo_t_d == T_d (the far missile B's t_go).
        @test w.env[:salvo_t_d] ≈ Td atol = 1e-9
        @test Td ≈ max(tgo(w.entities[:mA]), tgo(w.entities[:mB])) atol = 1e-12   # the SLOWEST sets the pace
        tel = w.env[:telemetry]
        @test haskey(tel, "link.salvo_t_d") && haskey(tel, "link.T_d")             # coordinator scalars
        @test tel["link.T_d"] isa Float64 && tel["link.salvo_t_d"] isa Float64     # SCALARS (no float()-crash)
    end

    @testset "decide! under :salvo matches impact_time_control_accel; :solo is plain PN (the seam)" begin
        # :salvo — a_ctrl matches the ITC law on the realized state (the slice-12 decide!-pin shape).
        w, subs = salvo_world(cooperation = :salvo, k_it = 0.45)
        tick!(w, subs, dt); empty!(w.events)
        std = Float64(w.env[:salvo_t_d])
        for mid in (:mA, :mB)
            e = w.entities[mid]; tgt = w.entities[:tgt]
            a_itc = clamp_accel(impact_time_control_accel(e.pos, e.vel, tgt.pos, tgt.vel, std; N = 4.0, K_it = 0.45), 3000.0)
            @test e.comp[:a_ctrl] ≈ a_itc atol = 1e-9         # :ideal → a_ctrl == a_cmd (the :salvo path)
        end
        # :solo — the SAME geometry flies plain PN (the salvo arm is unreachable; byte-identical to slice-10).
        w2, subs2 = salvo_world(cooperation = :solo)
        tick!(w2, subs2, dt); empty!(w2.events)
        for mid in (:mA, :mB)
            e = w2.entities[mid]; tgt = w2.entities[:tgt]
            a_pn = clamp_accel(pn_accel(e.pos, e.vel, tgt.pos, tgt.vel; N = 4.0), 3000.0)
            @test e.comp[:a_ctrl] ≈ a_pn atol = 1e-12         # plain PN, no cooperation term
        end
        # and the :salvo command DIFFERS from plain PN for the EARLY near missile (the feedback bites).
        eA = w.entities[:mA]; tgtA = w.entities[:tgt]
        a_pnA = clamp_accel(pn_accel(eA.pos, eA.vel, tgtA.pos, tgtA.vel; N = 4.0), 3000.0)
        @test norm3(eA.comp[:a_ctrl] - a_pnA) > 1.0           # the ITC feedback shaped it away from PN
    end

    @testset "Δτ(:salvo) ≪ Δτ(:solo) on the wire — the salvo collapses arrival spread (the Lesson)" begin
        solo  = fly_taus(salvo_world(cooperation = :solo)...)
        salvo = fly_taus(salvo_world(cooperation = :salvo, k_it = 0.45)...)
        # the honest baseline: :solo spreads (near hits first), both hit vs the true target.
        @test solo.Δτ > 2.0                                   # FINDINGS ≈ 2.34 (τA≈5.04, τB≈7.38)
        @test solo.missA < 5.0 && solo.missB < 5.0
        # cooperation collapses the spread — and both STILL hit (timing reshaped, not accuracy).
        @test salvo.Δτ < 1.0                                  # FINDINGS ≈ 0.52 at K=0.45
        @test salvo.missA < 5.0 && salvo.missB < 5.0
        @test solo.Δτ / salvo.Δτ > 3.0                        # the ratio (FINDINGS ≈ 4.5×); pin the RATIO
        # the near missile A STRETCHES (its τ rises toward B's), the far reference B ~unchanged.
        @test salvo.τA > solo.τA + 1.0                        # A delayed by cooperation
        @test abs(salvo.τB - solo.τB) < 0.5                   # B (the slowest) flies ~straight
    end

    @testset "the :solo↔:salvo trajectories DIFFER (not-a-dead-knob, physics-changing, NO RNG)" begin
        wsolo, ssolo = salvo_world(cooperation = :solo)
        wsal,  ssal  = salvo_world(cooperation = :salvo)
        for _ in 1:1500; tick!(wsolo, ssolo, dt); empty!(wsolo.events)
                          tick!(wsal,  ssal,  dt); empty!(wsal.events); end
        @test norm3(wsolo.entities[:mA].pos - wsal.entities[:mA].pos) > 10.0   # the near missile moved
    end

    @testset "miss/CPA is vs the true :target, NEVER the sibling missile or the :datalink node" begin
        w, _ = salvo_world(cooperation = :salvo)
        # _nearest_target (radar / autopilot truth / CPA) filters kind===:target → the common target,
        # NOT the sibling :missile and NOT the :datalink node (the truth-path invariant, per missile).
        @test EWSim._nearest_target(w, w.entities[:mA]) === w.entities[:tgt]
        @test EWSim._nearest_target(w, w.entities[:mB]) === w.entities[:tgt]
        @test w.entities[:link].kind === :datalink            # the node is NEVER :target/:missile
    end

    @testset "NO w.rng draw under :salvo — the class-4c pin (draw-count invariance is VACUOUS)" begin
        # truth-fed PN, no seeker/decoy → NO RNG consumer: a tick must NOT advance the Xoshiro stream
        # (contrast slice-11/13 seekers that draw). Confirms conventions 3/11 do NOT apply here.
        w, subs = salvo_world(cooperation = :salvo)
        for _ in 1:50; tick!(w, subs, dt); empty!(w.events); end
        r0 = copy(w.rng)
        tick!(w, subs, dt); empty!(w.events)                  # one more tick
        @test rand(w.rng) == rand(r0)                         # the stream is UNADVANCED (no draw)
    end

    @testset "loader: a :datalink node arms SalvoCoordinator; k_it knob; rejects bad salvo config" begin
        base = """
        name: salvo
        seed: 7
        dt_physics: 0.001
        fidelity: {guidance: pn, autopilot: ideal, cooperation: solo}
        entities:
          - id: mA
            kind: missile
            pos: [3000.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 750.0
              elevation_deg: 22.0
              guidance: {n_pn: 4.0, r_stop: 30.0, a_max: 3000.0, k_it: 0.45}
          - id: mB
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 750.0
              elevation_deg: 30.0
              guidance: {n_pn: 4.0, r_stop: 30.0, a_max: 3000.0, k_it: 0.45}
          - id: tgt
            kind: target
            pos: [9000.0, 0.0, 4500.0]
            vel: [-500.0, 0.0, 0.0]
            target: {rcs_m2: 1.0}
          - id: link
            kind: datalink
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            # the :datalink node gets a SalvoCoordinator (build_env! only), NO mover (never integrates).
            @test any(s -> s isa SalvoCoordinator && s.id === :link, scn.subs)
            @test !any(s -> s isa ConstantVelocity && s.id === :link, scn.subs)
            @test scn.world.entities[:link].kind === :datalink
            @test scn.world.entities[:mA].comp[:k_it] == 0.45     # the ITC gain at the CONSUMED key
            @test get(scn.world.fidelity, :cooperation, :solo) === :solo   # the new key parsed
            # a defaulted guidance block (no k_it) → the FINDINGS default 0.45.
            defs = replace(base, ", k_it: 0.45" => "")
            pd = joinpath(dir, "defs.yaml"); write(pd, defs)
            @test load_scenario(pd).world.entities[:mA].comp[:k_it] == 0.45
            # rejects: k_it ≤ 0 (would null / sign-flip the cooperation) is an AUTHORED load error.
            badk = replace(base, "k_it: 0.45" => "k_it: 0.0"; count = 1)                 # mA's k_it → 0
            pk = joinpath(dir, "badk.yaml"); write(pk, badk)
            @test_throws ErrorException load_scenario(pk)
            # rejects: a :datalink with < 2 :missile interceptors (nothing to coordinate).
            one = replace(base, r"- id: mB.*?(?=- id: tgt)"s => "")                      # strip the mB block
            po = joinpath(dir, "one.yaml"); write(po, one)
            @test_throws ErrorException load_scenario(po)
        end
    end
end

# --- gate 2: the pitch-plane ROTATIONAL airframe wired into BallisticMissile.integrate! -----
# (slice 16, §11 Tier A). The lesson wired end-to-end: an `airframe:` block gives the missile
# a dynamical `att` — Cmα<0 WEATHERVANES/oscillates (α bounded, restores) vs Cmα>0 TUMBLES (α
# diverges) — the #1 sign trap. The load-bearing property is ISOLATION: rotation reads (V,γ)
# but does NOT feed back into (pos,vel), so the trajectory is BYTE-IDENTICAL to the same missile
# with no airframe block (advisor: read-only w.r.t. translation). Pinned against the LIVE tick,
# not a hand-recompute (convention 10). NO RNG (class 4c — determinism is trivial/vacuous, the
# slice-8/14/15 shape); the wire is byte-identical for a non-airframe missile (gated telemetry).
@testset "airframe rotational dynamics wired (slice 16, pitch-plane :sixdof)" begin
    dt = 1.0e-3
    norm3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # A fast, shallow shot (γ ≈ small, slowly drifting under gravity) so the short-period
    # oscillation reads cleanly; drag off. `af=false` gives the ISOLATION TWIN (no airframe block).
    function af_world(; cma = -0.3, cmd = 0.0, cmq = 0.0, alpha0 = 0.0, delta = 0.0, af = true,
                        vel = Vec3(600.0, 0.0, 40.0))
        w = World(seed = 0, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4))
        comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225)
        if af
            comp[:af_S] = π * 0.1^2; comp[:af_d] = 0.2; comp[:af_I] = 50.0
            comp[:af_cma] = cma; comp[:af_cmd] = cmd; comp[:af_cmq] = cmq
            comp[:af_alpha0] = alpha0; comp[:af_delta] = delta
        end
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 1000.0), vel = vel, comp = comp)
        return w, Subsystem[BallisticMissile(:m1)]
    end
    afp(c) = AirframeParams(c[:af_S], c[:af_d], c[:af_I], c[:af_cma], c[:af_cmd], c[:af_cmq], c[:rho], get(c, :af_cla, 0.0))

    @testset "ISOLATION — rotation does NOT touch (pos,vel): trajectory byte-identical to the twin" begin
        # THE load-bearing property. A stable, an UNSTABLE, and a fin-deflected airframe must ALL
        # leave the translation bit-for-bit equal to the no-airframe twin (rotation is read-only).
        for (cma, alpha0, delta) in ((-0.3, 0.05, 0.0), (+0.3, 0.05, 0.0), (-0.3, 0.0, 0.1))
            waf, saf = af_world(cma = cma, cmd = 0.1, alpha0 = alpha0, delta = delta, af = true)
            wpl, spl = af_world(af = false)
            ok = true
            for _ in 1:1500
                tick!(waf, saf, dt); empty!(waf.events)
                tick!(wpl, spl, dt); empty!(wpl.events)
                ok &= (waf.entities[:m1].pos == wpl.entities[:m1].pos) &&
                      (waf.entities[:m1].vel == wpl.entities[:m1].vel)
            end
            @test ok                                             # bit-exact trajectory (the isolation)
        end
    end

    @testset "wiring mirror — integrate! feeds airframe_step the LIVE (V,γ,δ,params)" begin
        # Reproduce the subsystem's rotational update with the pure lib fed the SAME live (V,γ)
        # from each post-tick velocity (γ = atan(vz,vx), V = ‖v‖ = _norm3). Pins integrate! →
        # airframe_step (convention 11 — an INDEPENDENT recompute, not the same call).
        waf, saf = af_world(cma = -0.3, cmd = 0.1, alpha0 = 0.05, delta = 0.02)
        c = waf.entities[:m1].comp; p = afp(c)
        θref = nothing; qref = nothing; ok = true
        for _ in 1:400
            tick!(waf, saf, dt); empty!(waf.events)
            v = waf.entities[:m1].vel
            V = norm3(v); γ = atan(v[3], v[1])
            if θref === nothing                                  # tick 1: subsystem lazily inits θ=γ+α0, q=0
                θref, qref = airframe_step(γ + 0.05, 0.0, dt; gamma = γ, V = V, delta = 0.02, p = p)
            else
                θref, qref = airframe_step(θref, qref, dt; gamma = γ, V = V, delta = 0.02, p = p)
            end
            ok &= isapprox(c[:pitch_theta], θref; atol = 1e-12) && isapprox(c[:pitch_q], qref; atol = 1e-12)
        end
        @test ok
    end

    @testset "SIGN LESSON — Cmα<0 α stays BOUNDED & restores; Cmα>0 α DIVERGES (the #1 trap)" begin
        # stable: a 0.05 rad initial α oscillates but never grows past it (weathervanes to trim=0).
        ws, ss = af_world(cma = -0.3, alpha0 = 0.05)
        αs = Float64[]
        for _ in 1:1500; tick!(ws, ss, dt); empty!(ws.events); push!(αs, ws.env[:telemetry]["m1.alpha"]); end
        @test maximum(abs.(αs)) < 0.06                           # bounded by ~α0 (never grows)
        @test any(<(0.0), αs) && any(>(0.0), αs)                 # crosses zero → oscillates (restoring)
        @test ws.env[:telemetry]["m1.omega_sp"] > 0             # a real short-period freq (finite, >0)
        # unstable: same perturbation DIVERGES — |α| ends ≫ α0, and ω_sp is NOT a real number.
        wu, su = af_world(cma = +0.3, alpha0 = 0.05)
        αu = Float64[]
        for _ in 1:1500; tick!(wu, su, dt); empty!(wu.events); push!(αu, wu.env[:telemetry]["m1.alpha"]); end
        @test abs(αu[end]) > 10 * 0.05                           # tumbled away (grew ≫ 10×)
        @test wu.env[:telemetry]["m1.omega_sp"] == FINITE_CEIL   # NaN (no real freq) → _finite clamp
    end

    @testset "att comes ALIVE — a dynamical output OF θ (round-trips), ≠ velocity-aligned" begin
        # `att` now ENCODES the integrated pitch θ (nose along (cosθ,0,sinθ)): recover θ back from
        # att and pin it to comp[:pitch_theta]. And it DIFFERS from the velocity-aligned twin — the
        # airframe LAGS the flight path (θ≠γ; a stable airframe weathervanes toward γ but can't
        # follow instantly), so att is a real dynamical quantity, not the kinematic velocity-align.
        wp, sp = af_world(cma = -0.3, alpha0 = 0.08)
        wt, st = af_world(af = false)
        maxdiff = 0.0; roundtrip_ok = true
        for _ in 1:300
            tick!(wp, sp, dt); empty!(wp.events); tick!(wt, st, dt); empty!(wt.events)
            e = wp.entities[:m1]
            nose = rotate(e.att, Vec3(1.0, 0.0, 0.0))            # att sends body-x → the nose vector
            θ_from_att = atan(nose[3], nose[1])                  # recover the pitch angle
            roundtrip_ok &= isapprox(θ_from_att, e.comp[:pitch_theta]; atol = 1e-9)
            maxdiff = max(maxdiff, maximum(abs.(e.att .- wt.entities[:m1].att)))
        end
        @test roundtrip_ok                                       # att encodes θ, recoverable to 1e-9
        @test maxdiff > 1e-3                                     # and differs from velocity-aligned (α ≠ 0)
    end

    @testset "gated wire — a non-airframe missile ships NO rotational keys (byte-identical)" begin
        wpl, spl = af_world(af = false)
        tick!(wpl, spl, dt); empty!(wpl.events)
        tel = wpl.env[:telemetry]
        for k in ("m1.alpha", "m1.pitch_theta", "m1.pitch_q", "m1.gamma", "m1.omega_sp", "m1.alpha_trim")
            @test !haskey(tel, k)                                # absent → wire byte-identical to slices 8–15
        end
        # an airframe missile SHIPS them (the gate is real).
        waf, saf = af_world(cma = -0.3, alpha0 = 0.05)
        tick!(waf, saf, dt); empty!(waf.events)
        @test all(haskey(waf.env[:telemetry], k) for k in ("m1.alpha", "m1.pitch_theta", "m1.gamma"))
    end

    @testset "determinism — an airframe missile replays bit-identical (class 4c, no RNG)" begin
        wa, sa = af_world(cma = -0.2, cmd = 0.1, cmq = -50.0, alpha0 = 0.06, delta = 0.03)
        wb, sb = af_world(cma = -0.2, cmd = 0.1, cmq = -50.0, alpha0 = 0.06, delta = 0.03)
        ok = true
        for _ in 1:800
            tick!(wa, sa, dt); empty!(wa.events); tick!(wb, sb, dt); empty!(wb.events)
            ok &= wa.entities[:m1].comp[:pitch_theta] == wb.entities[:m1].comp[:pitch_theta] &&
                  wa.entities[:m1].comp[:pitch_q]     == wb.entities[:m1].comp[:pitch_q]
        end
        @test ok
    end

    @testset "live Cmα knob never crashes a tick — bounded/finite through a sign cross" begin
        # emulate a live slider dragging Cmα from stable through 0 into unstable mid-flight: att
        # and telemetry must stay FINITE the whole way (short_period_freq NaN-safe, no throw).
        w, subs = af_world(cma = -0.3, alpha0 = 0.04)
        finite = true
        for i in 1:900
            w.entities[:m1].comp[:af_cma] = -0.3 + 0.6 * (i / 900)   # -0.3 → +0.3, crossing 0
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            finite &= all(isfinite, w.entities[:m1].att) &&
                      isfinite(tel["m1.alpha"]) && isfinite(tel["m1.omega_sp"]) &&
                      isfinite(tel["m1.alpha_trim"])             # incl. the Cmα=0 0/0 tick (advisor)
        end
        @test finite                                             # convention 5 — a live knob can't crash a tick
    end

    @testset "loader: an airframe: block arms the rotational keys + rejects bad geometry" begin
        base = """
        name: af
        seed: 0
        dt_physics: 0.001
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 1000.0]
            missile:
              mass_kg: 100.0
              speed: 601.3
              elevation_deg: 3.8
              cd_area_m2: 0.0
              airframe:
                ref_area_m2: 0.0314159
                ref_len_m: 0.2
                inertia_kgm2: 50.0
                cma: -0.3
                cmd: 0.1
                cmq: -8.0
                alpha0: 0.05
                delta: 0.0
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            c = scn.world.entities[:m1].comp
            @test c[:af_cma] == -0.3 && c[:af_I] == 50.0 && c[:af_alpha0] == 0.05   # parsed to the CONSUMED keys
            @test any(s -> s isa BallisticMissile, scn.subs)     # no NEW subsystem — BallisticMissile owns rotation
            # a knob addressing af_cma resolves (the lesson slider names a real comp key).
            @test haskey(c, :af_cma)
            # rejects: I ≤ 0 (a zero pitch inertia divides the moment equation → a tick crash).
            badI = replace(base, "inertia_kgm2: 50.0" => "inertia_kgm2: 0.0")
            pI = joinpath(dir, "badI.yaml"); write(pI, badI)
            @test_throws ErrorException load_scenario(pI)
            # rejects: a non-finite Cma (NaN cd → NaN moment → NaN att → non-finite JSON, conv. 6).
            badC = replace(base, "cma: -0.3" => "cma: .nan")
            pC = joinpath(dir, "badC.yaml"); write(pC, badC)
            @test_throws ErrorException load_scenario(pC)
            # Cmα > 0 (statically UNSTABLE) is NOT rejected — divergence IS a valid lesson state.
            uns = replace(base, "cma: -0.3" => "cma: 0.3")
            pu = joinpath(dir, "uns.yaml"); write(pu, uns)
            @test load_scenario(pu).world.entities[:m1].comp[:af_cma] == 0.3
        end
    end
end

# --- gate 2: the α→lift→γ COUPLING wired into BallisticMissile.integrate! (slice 17, §11 Tier A) --
# The FIRST rotation→translation coupling: with `:airframe === :pitch_coupled` the angle of attack
# α = θ−γ generates a body lift ⟂ v that TURNS the flight path (the whole [pos,vel,θ,q] state
# advances jointly in one rk4_coupled step). The lesson & the false-fidelity guard: a fixed trim
# δ ≠ 0 bends the path into a climbing turn ≠ the ballistic `:point_mass` twin (the INVERSE of
# slice-16's posdiff=0). Pinned against the LIVE tick + the gate-0 fine-precision golden. NO RNG
# (class 4c). The `:point_mass` default keeps every slice-8..16 wire byte-identical.
@testset "airframe α→lift coupling wired (slice 17, :pitch_coupled)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # The gate-0 showcase airframe: δ=0.15 (MANDATORY nonzero — the non-dead toggle), Cla=20,
    # Cmα=-0.3 (stable), Cmq=-150 (damped); climbing 500 m/s @ 40°, gravity ON, drag OFF.
    function cpl_world(; airframe = :pitch_coupled, cla = 20.0, delta = 0.15, cma = -0.3,
                         cmq = -150.0, alpha0 = 0.05)
        w = World(seed = 0, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :airframe => airframe))
        v0 = 500.0; el = deg2rad(40.0)
        comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 50.0,
                                :af_cma => cma, :af_cmd => 0.1, :af_cmq => cmq,
                                :af_alpha0 => alpha0, :af_delta => delta, :af_cla => cla)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 0.0),
                                 vel = Vec3(v0 * cos(el), 0.0, v0 * sin(el)), comp = comp)
        return w, Subsystem[BallisticMissile(:m1)]
    end

    @testset "transient GOLDEN — the wired coupled path pins the STAGE-θ closure (advisor)" begin
        # The ONE assertion that exercises the stage-θ wiring: neither the steady-turn R (α≈const)
        # nor the decoupled limit (Cla=0) catches a closure reading the ENTRY θ instead of the RK4
        # stage TH (an ~0.019 m / 8 s error — measured). Pinned to the gate-0 fine-precision golden
        # (grav on, drag off, δ=0.15, Cla=20, α0=0.05, 8 s @ dt=1e-3), generated with the SAME core
        # primitives (total_accel + lift_accel + rk4_coupled), stage-θ correct.
        w, s = cpl_world()
        for _ in 1:8000; tick!(w, s, dt); empty!(w.events); end
        e = w.entities[:m1]
        @test isapprox(e.pos[1], 2187.823608281557; atol = 1e-6)
        @test isapprox(e.pos[3], 3010.178483035902; atol = 1e-6)
        @test isapprox(e.comp[:pitch_theta], 1.251491571778638; atol = 1e-9)
        @test isapprox(e.comp[:pitch_q], 0.06393471230113383; atol = 1e-9)
    end

    @testset "NON-DEAD toggle — :pitch_coupled CURVES ≠ :point_mass ballistic twin (δ≠0)" begin
        # δ=0.15 ⇒ the coupled path bends into a climbing turn while the :point_mass twin flies the
        # ballistic arc — a MEANINGFUL separation (~1155 m, gate-0). A default δ=0 makes both
        # ballistic → the false-fidelity trap the plan guards against.
        wc, sc = cpl_world(airframe = :pitch_coupled)
        wp, sp = cpl_world(airframe = :point_mass)
        for _ in 1:8000
            tick!(wc, sc, dt); empty!(wc.events)
            tick!(wp, sp, dt); empty!(wp.events)
        end
        @test n3(wc.entities[:m1].pos - wp.entities[:m1].pos) > 500.0   # the toggle is REAL
        # the :point_mass twin IS the ballistic arc: p = p0 + v0 t + ½ g t² (pos/vel untouched by α).
        v0 = 500.0; el = deg2rad(40.0); t = 8.0
        @test isapprox(wp.entities[:m1].pos[1], v0 * cos(el) * t; atol = 1e-6)
        @test isapprox(wp.entities[:m1].pos[3], v0 * sin(el) * t - 0.5 * G_ACCEL * t^2; atol = 1e-6)
    end

    @testset "lift readout — a_lift = Q·S·Cla·α/m, turn radius R = V²/a_lift (coupled-only wire)" begin
        # Pin the telemetry against the live path (convention 10): a_lift recomputed from the SHIPPED
        # α & speed. A :point_mass wire must NOT carry the lift keys (byte-identity — the fin-key gate).
        wc, sc = cpl_world()
        for _ in 1:1200; tick!(wc, sc, dt); empty!(wc.events); end
        tel = wc.env[:telemetry]
        α = tel["m1.alpha"]; V = tel["m1.speed"]
        Q = 0.5 * 1.225 * V^2
        @test isapprox(tel["m1.a_lift"], Q * (π * 0.1^2) * 20.0 * abs(α) / 100.0; rtol = 1e-9)
        @test isapprox(tel["m1.turn_radius_m"], V^2 / tel["m1.a_lift"]; rtol = 1e-9)
        @test tel["m1.a_lift"] > 0.0 && isfinite(tel["m1.turn_radius_m"])
        # the :point_mass twin ships the slice-16 rotational keys but NO lift keys (gated on coupled).
        wp, sp = cpl_world(airframe = :point_mass)
        tick!(wp, sp, dt); empty!(wp.events)
        @test haskey(wp.env[:telemetry], "m1.alpha")                  # slice-16 rotational readout present
        @test !haskey(wp.env[:telemetry], "m1.a_lift")               # …but NO lift keys (coupled-only)
        @test !haskey(wp.env[:telemetry], "m1.turn_radius_m")
    end

    @testset "att comes ALIVE on the coupled path — θ round-trips out of att" begin
        wc, sc = cpl_world()
        ok = true
        for _ in 1:600
            tick!(wc, sc, dt); empty!(wc.events)
            e = wc.entities[:m1]
            nose = rotate(e.att, Vec3(1.0, 0.0, 0.0))
            ok &= isapprox(atan(nose[3], nose[1]), e.comp[:pitch_theta]; atol = 1e-9)
        end
        @test ok
    end

    @testset "loader: airframe.cla parses to :af_cla + rejects non-finite" begin
        base = """
        name: cpl
        seed: 0
        dt_physics: 0.001
        fidelity: {airframe: pitch_coupled}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 0.0]
            missile:
              mass_kg: 100.0
              speed: 500.0
              elevation_deg: 40.0
              cd_area_m2: 0.0
              airframe:
                inertia_kgm2: 50.0
                cma: -0.3
                cmd: 0.1
                cmq: -150.0
                delta: 0.15
                cla: 20.0
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            c = scn.world.entities[:m1].comp
            @test c[:af_cla] == 20.0 && c[:af_delta] == 0.15
            @test scn.world.fidelity[:airframe] == :pitch_coupled     # the NEW fidelity KEY validates
            # a negative/crossing Cla is a lesson-adjacent knob (finite, NOT rejected — mirrors cma).
            neg = replace(base, "cla: 20.0" => "cla: -5.0")
            pn = joinpath(dir, "neg.yaml"); write(pn, neg)
            @test load_scenario(pn).world.entities[:m1].comp[:af_cla] == -5.0
            # rejects: a non-finite Cla (NaN lift → NaN pos → non-finite JSON, convention 6).
            badcla = replace(base, "cla: 20.0" => "cla: .nan")
            pb = joinpath(dir, "badcla.yaml"); write(pb, badcla)
            @test_throws ErrorException load_scenario(pb)
        end
    end
end

# --- gate 2: the INNER α/g AUTOPILOT wired — `a_cmd → α_cmd → δ` (slice 19, §11 Tier A) ---------
# Slice 17 coupled α→lift→γ but left δ an authored FIXED trim: the airframe curved, it did not AIM.
# Here the `:alpha` autopilot rung INVERTS the outer law's command through the aero and closes the
# fin every tick, so the missile flies its own PN command THROUGH THE AIRFRAME. The lesson is the
# FLIGHT-CONDITION g-limit `a_max_aero = Q·S·C_Lα·α_max/m` — the same PN law, the same target: the
# `:point_mass` arm pulls what it needs by fiat and HITS; the `:pitch_coupled` arm must MAKE its
# accel from lift, pegs α at α_max, and MISSES.
#
# EVERY number below is pinned against the LIVE tick! contract (convention 10 — probed first in
# `temp/slice19_gate2/wired.jl`, never hand-recomputed), and the wired path reproduces the gate-0
# probe + the gate-1 bridge EXACTLY (miss 295.167860288156 — no ordering shift). NO RNG (class 4c),
# so "draw-count invariance" is VACUOUS here — do NOT copy the slice-11/13 draw language.
@testset "inner α/g autopilot wired (slice 19, :autopilot === :alpha)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # THE PICK (gate-0 FINDINGS): the slice-12 engagement geometry — m1 at (0,0,3000) launched at
    # elev 12°, a maneuvering target at (6000,0,4200) pulling a_lat=200. mass 140, I=20, Cmα=−1.0
    # (stable), Cmδ=+3.0, Cmq=−150 (overdamped), Cla=20; k_α=1.0/k_q=0.3 AUTHORED (never knobs);
    # α_max=0.2, δ_max=0.4, a_max=3000 (INERT — proven below), V0=700, drag OFF. `af_delta = 0` so
    # TICK 1 — which integrates BEFORE the first decide! writes `:delta_cmd` — injects no transient
    # (advisor); it is also the slice-17 open-loop byte-identity anchor.
    function pick_world(; V0 = 700.0, airframe = :pitch_coupled, alpha_max = 0.2, delta_max = 0.4,
                          a_max = 3000.0, autopilot = :alpha, af_delta = 0.0, cla = 20.0,
                          guided = true)
        w = World(seed = 19, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                            :autopilot => autopilot,
                                                            :airframe => airframe))
        el = deg2rad(12.0)
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => af_delta, :af_cla => cla,
                                :af_alpha_max => alpha_max,
                                :n_pn => 4.0, :a_max => a_max, :delta_max => delta_max,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
                                 vel = Vec3(-800.0, 0.0, 200.0),
                                 comp = Dict{Symbol,Any}(:a_lat_mps2 => 200.0, :turn_sign => 1.0))
        subs = guided ? Subsystem[BallisticMissile(:m1), Autopilot(:m1), ManeuveringTarget(:t1)] :
                        Subsystem[BallisticMissile(:m1), ManeuveringTarget(:t1)]
        return w, subs
    end

    # The engagement to first-CPA. [[ewsim-missile-verifier-sampling]]: take the min over the FIRST
    # DESCENDING band only (post-CPA re-crossings are not the intercept) and gate the diagnostic
    # scans at r > 150 m (the r→0 endgame spikes `a_demand` for reasons that are not the lesson).
    function fly(; T = 14.0, kw...)
        w, s = pick_world(; kw...)
        rmin, prev, closing = Inf, Inf, true
        aero_sat = 0; defl_sat = 0; gated = 0; sat = 0; aa_max = 0.0; α_peak = 0.0; δ_peak = 0.0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            r = n3(w.entities[:t1].pos - w.entities[:m1].pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            tel = w.env[:telemetry]
            if closing && r > 150.0
                gated += 1
                get(tel, "m1.aero_sat", 0.0)  > 0.5 && (aero_sat += 1)
                get(tel, "m1.defl_sat", 0.0)  > 0.5 && (defl_sat += 1)
                get(tel, "m1.saturated", 0.0) > 0.5 && (sat += 1)
                aa_max = max(aa_max, get(tel, "m1.a_max_aero", 0.0))
                α_peak = max(α_peak, abs(get(tel, "m1.alpha", 0.0)))
                δ_peak = max(δ_peak, abs(get(tel, "m1.delta_cmd", 0.0)))
            end
            !closing && break
        end
        return (miss = rmin, aero_sat = aero_sat, defl_sat = defl_sat, gated = gated, sat = sat,
                aa_max = aa_max, α_peak = α_peak, δ_peak = δ_peak, w = w)
    end

    @testset "transient GOLDEN — the closed-loop coupled wiring (the plausible-but-wrong catch)" begin
        # Cheap insurance against a subtly-wrong-but-plausible wiring (a swapped gain, an entry-vs-
        # stage read, a sign). The advisor notes slice-17's stage-θ bug class has NO HOME here — δ is
        # computed ONCE per tick in decide! and held CONSTANT across the next step's four RK4 stages
        # (an EXTERNAL input, not stage-varying state) — so this golden is insurance, not a hunt.
        # Generated from the LIVE tick! path (temp/slice19_gate2/golden.jl), 2000 ticks into the
        # closed loop, well inside the guided window.
        w, s = pick_world()
        for _ in 1:2000; tick!(w, s, dt); empty!(w.events); end
        m = w.entities[:m1]
        @test isapprox(m.pos[1], 1301.66849780737;          atol = 1e-6)
        @test isapprox(m.pos[3], 3487.19526661747;          atol = 1e-6)
        @test isapprox(m.comp[:pitch_theta], 0.304261953442594;   atol = 1e-9)
        @test isapprox(m.comp[:pitch_q], -0.364428404654725;      atol = 1e-9)
        @test isapprox(m.comp[:delta_cmd], -0.0324528304710964;   atol = 1e-9)
    end

    @testset "THE LESSON — :point_mass HITS, :pitch_coupled MISSES (the non-dead toggle)" begin
        # The SAME PN law, the SAME target, the SAME airframe — only the plant model differs. The
        # point-mass twin applies a_ctrl by fiat (capped at the generous authored a_max) and hits;
        # the coupled twin must MAKE its accel from lift and cannot. Pinned in BOTH directions
        # (a one-sided assert would pass if both arms missed).
        c = fly(airframe = :pitch_coupled)
        p = fly(airframe = :point_mass)
        @test isapprox(c.miss, 295.167860288156; atol = 1e-6)   # the aero-limited MISS
        @test isapprox(p.miss, 0.276114602924875; atol = 1e-9)  # the fiat-plant HIT
        @test c.miss / p.miss > 1000.0                          # ~1069× separation
    end

    @testset "THE ISOLATION — STRUCTURAL, *not* `saturated == 0` (the gate-0 correction)" begin
        # Slice-15's `saturated == 0` assertion MUST NOT be copied here — it FAILS, and copying it
        # across is itself the convention-4 copy-paste trap (it was correct THERE because that cap sat
        # downstream of a_max). The ceiling-limited missile diverges → the LOS rate grows → PN's demand
        # escalates genuinely above a_max in the guided window. But every one of those clamps is INERT:
        # a_max clamps a_cmd UPSTREAM of the α inversion, and since a_max_aero < a_max the clamped
        # a_perp STILL pegs α_cmd at ±α_max. The tighter clamp wins downstream.
        c = fly()
        @test c.sat > 100                       # a_max DOES clamp (560×) — and does nothing (next testset)
        # ⇒ assert the STRUCTURAL margin instead: the aero ceiling is far below the magnitude cap.
        @test c.aa_max < 3000.0                 # max a_max_aero = 269.39 vs a_max = 3000 (11× margin)
        @test isapprox(c.aa_max, 269.39; atol = 0.01)
        # THE LESSON FLAG: the aero ceiling BINDS across most of the guided window.
        @test c.aero_sat > 0.5 * c.gated        # 2444/4130 = 59%
        # THE FOURTH CAP is provably NOT binding — structural, not luck: δ_peak is deterministic at
        # launch (α=0, α_cmd pegged) at (|Cmα|/Cmδ + k_α)·α_max = 0.2667 < δ_max = 0.4 (33% margin).
        # Without this, δ_max would be an IMPLICIT α ceiling contaminating the causation twin below.
        @test c.defl_sat == 0
        @test isapprox(c.δ_peak, 0.2667; atol = 1e-3)
        # α_peak = 0.1369 never even reaches the 0.2 clamp — the ACHIEVED α is demand-limited, which
        # is why the authored k_α=1.0 does not leak the ceiling (gate-0 FINDING 14).
        @test isapprox(c.α_peak, 0.1369; atol = 1e-3)
    end

    @testset "a_max is INERT — 3000 ≡ 1e7 BIT-FOR-BIT (pin it so it can't quietly return)" begin
        # Cheap and decisive (gate 0 proved it): slice-10's magnitude clamp fires 560× in the guided
        # window and changes NOTHING, because the tighter aero clamp wins downstream. Pinning it stops
        # a future edit from silently making a_max load-bearing again and stealing the lesson.
        a = fly(a_max = 3000.0)
        b = fly(a_max = 1.0e7)
        @test a.miss === b.miss                          # === : bit-for-bit, not isapprox
        @test a.w.entities[:m1].pos === b.w.entities[:m1].pos
        @test a.sat > 100 && b.sat == 0                  # the clamp fires in a, never in b — same result
    end

    @testset "THE CAUSATION PROOF — α_max moves the ceiling ALONE (binding ≠ causing)" begin
        # The isolation proves the ceiling BINDS; it does NOT prove it CAUSES the miss. The coupled
        # plant also carries a dynamic tracking cost the point-mass plant lacks (a slice-15-class
        # concern) — either could open the miss, and if it were the LAG this slice would have
        # relabeled a slice-15 effect as a new lesson (the false-claim class conventions 4/11 exist to
        # catch). `af_alpha_max` is the CLEAN discriminator: it enters ONLY the α_cmd clamp — absent
        # from pitch_moment/lift_accel/short_period_freq — so it moves the ceiling with ω_sp, Q and
        # geometry FIXED. SPEED IS CONFOUNDED (ω_sp ∝ √Q moves ceiling AND response-speed together) ⇒
        # it is the demo lever, NEVER the causation proof.
        base = fly(alpha_max = 0.2)
        relaxed = fly(alpha_max = 1.5)
        @test isapprox(relaxed.miss, 13.1186763034337; atol = 1e-6)
        # STATE IT AS A COUNTERFACTUAL, NOT A DECOMPOSITION (advisor): relaxing α_max ALONE — every
        # other cap held — recovers 282 of 295 m (95.6%). NOT "the ceiling contributes 282 m": gate 0
        # proved ceiling and dynamics are NOT additive (71 + 12 ≠ 253).
        @test base.miss - relaxed.miss > 280.0
        @test (base.miss - relaxed.miss) / base.miss > 0.95
        @test relaxed.aero_sat < 0.05 * relaxed.gated    # the ceiling stops binding (37/4144)
        # The twin is UNCONTAMINATED: δ_max (the 4th cap) stays clear at the AUTHORED 0.4 throughout,
        # so no other cap is silently standing in for the one under test (gate-0's first twin was
        # fooled exactly here — relaxing the cap under test while another still bound).
        @test relaxed.defl_sat == 0
        # The residual ~13 m is "the airframe + autopilot dynamic tracking cost" — the irreducible
        # price of steering through a real rotational plant with a finite-bandwidth loop. It is NOT
        # "short-period lag" (UNEARNED: 6.3× of ω_sp buys only −10%) and NOT a projection effect
        # (measured −0.081 m — REFUTED). Named as a §1 approximation; the lesson survives it intact.
        @test relaxed.miss > 1.0                          # it does NOT collapse to the point-mass 0.276
    end

    @testset "THE δ SEAM — no autopilot ⇒ no :delta_cmd ⇒ slice-17's af_delta trim (byte-identity)" begin
        # `_integrate_coupled!` reads `get(c, :delta_cmd, get(c, :af_delta, 0.0))`. A slice-17
        # OPEN-LOOP scenario has no Autopilot → nothing ever writes `:delta_cmd` → it reads the
        # authored trim → bit-identical. Byte-identity BY CONSTRUCTION, not by calibration.
        w1, s1 = pick_world(af_delta = 0.15, guided = false)
        w2, s2 = pick_world(af_delta = 0.15, guided = false)
        for _ in 1:2000
            tick!(w1, s1, dt); empty!(w1.events)
            tick!(w2, s2, dt); empty!(w2.events)
        end
        @test w1.entities[:m1].pos === w2.entities[:m1].pos          # replay bit-identical (no RNG)
        @test !haskey(w1.entities[:m1].comp, :delta_cmd)             # the key never appears
        # …and the open-loop trim ACTUALLY FLEW: δ=0.15 bends the path (not a dead fallback).
        w0, s0 = pick_world(af_delta = 0.0, guided = false)
        for _ in 1:2000; tick!(w0, s0, dt); empty!(w0.events); end
        @test n3(w1.entities[:m1].pos - w0.entities[:m1].pos) > 10.0
    end

    @testset "THE :a_ctrl TRIPWIRE — a pure-coupled run NEVER grows the key (finding 1)" begin
        # THE load-bearing design of this slice: the coupled force stays `a_ctrl`-FREE. Adding a fiat
        # control force beside the lift would let the missile over-maneuver, the aero ceiling would
        # never bind, and the point-mass plant would be silently rebuilt in an airframe costume (the
        # slice-15 k_δ-cancellation / slice-16 false-fidelity trap, THIRD occurrence). decide! does
        # not even PERSIST the key under `:alpha`+`:pitch_coupled`, which makes the invariant testable.
        c = fly(airframe = :pitch_coupled)
        @test !haskey(c.w.entities[:m1].comp, :a_ctrl)    # guidance reaches this plant ONLY through δ
        @test haskey(c.w.entities[:m1].comp, :delta_cmd)
        # …while the point_mass REFERENCE ARM does exactly the opposite (it flies a_ctrl, no fin).
        p = fly(airframe = :point_mass)
        @test haskey(p.w.entities[:m1].comp, :a_ctrl)
        @test !haskey(p.w.entities[:m1].comp, :delta_cmd)
    end

    @testset "telemetry — rung-gated; the ceiling ships under BOTH arms (the contrast)" begin
        w, s = pick_world()
        for _ in 1:2000; tick!(w, s, dt); empty!(w.events); end
        tel = w.env[:telemetry]
        # Pin the headline against an INDEPENDENT recompute from the SHIPPED speed (convention 11 —
        # a different expression than the source, so a decomposition slip can't round-trip).
        V = tel["m1.speed"]; Q = 0.5 * 1.225 * V^2
        @test isapprox(tel["m1.a_max_aero"], Q * (π * 0.1^2) * 20.0 * 0.2 / 140.0; rtol = 1e-12)
        @test isapprox(tel["m1.q_dyn"], Q; rtol = 1e-12)
        @test isapprox(tel["m1.a_max_aero"], 264.138155734105; atol = 1e-6)
        # a_ach is the ACHIEVED LIFT, so the slice-9 keys stay HONEST under a binding ceiling: the
        # airframe visibly FAILS TO DELIVER (a_cmd would have claimed perfect tracking).
        @test tel["m1.a_ach"] < tel["m1.a_cmd"]
        @test tel["m1.track_gap"] > 100.0
        @test isapprox(tel["m1.a_ach"], 112.198008667199; atol = 1e-6)
        # every α key is a SCALAR (no Array → no client float() crash) and finite (convention 6).
        for k in ("m1.alpha_cmd", "m1.delta_cmd", "m1.a_max_aero", "m1.q_dyn", "m1.aero_sat",
                  "m1.defl_sat")
            @test tel[k] isa Float64 && isfinite(tel[k])
        end
        # THE REFERENCE ARM ships the SAME key set (gated on the RUNG, not on :pitch_coupled — the
        # deliberate contrast to slice-17's lift keys, which are a produced FORCE). The ceiling is a
        # flight-condition PROPERTY, true whichever plant is active: under :point_mass the demand
        # crosses it and the missile HITS ANYWAY. Same key set across the live toggle ⇒ no stale keys.
        wp, sp = pick_world(airframe = :point_mass)
        for _ in 1:2000; tick!(wp, sp, dt); empty!(wp.events); end
        telp = wp.env[:telemetry]
        @test isapprox(telp["m1.a_max_aero"], 270.045006323127; atol = 1e-6)   # REAL, and ignored
        @test telp["m1.q_dyn"] > 0.0
        @test telp["m1.alpha_cmd"] == 0.0 && telp["m1.delta_cmd"] == 0.0       # no α command issued
        @test telp["m1.aero_sat"] == 0.0 && telp["m1.defl_sat"] == 0.0
        @test telp["m1.track_gap"] == 0.0                                       # :ideal-perfect tracking
        # A slice-1..18 wire ships NONE of them (byte-identity — the fin-key precedent).
        wf, sf = pick_world(autopilot = :ideal)
        tick!(wf, sf, dt); empty!(wf.events)
        for k in ("m1.alpha_cmd", "m1.delta_cmd", "m1.a_max_aero", "m1.q_dyn", "m1.aero_sat",
                  "m1.defl_sat")
            @test !haskey(wf.env[:telemetry], k)
        end
    end

    @testset "no-target / post-impact — the α keys are ZEROED, never stale" begin
        # A decide! early-return must still publish every key it owns (the readout must not blank or
        # freeze at a stale value). Zeroing is HONEST here: the missile is frozen (v=0), so q_dyn =
        # ½ρV² and the ceiling a_max_aero ∝ V² genuinely ARE zero.
        w, s = pick_world()
        w.entities[:m1].comp[:impacted] = true
        tick!(w, s, dt); empty!(w.events)
        tel = w.env[:telemetry]
        for k in ("m1.alpha_cmd", "m1.delta_cmd", "m1.a_max_aero", "m1.q_dyn", "m1.aero_sat",
                  "m1.defl_sat")
            @test tel[k] == 0.0
        end
    end

    @testset "degenerates — a live knob can never crash a tick (convention 5)" begin
        # THE CRASH-SAFETY SITE of this slice is the `a_cmd/Q` divide. `af_cla` is a LIVE slider whose
        # slice-17 range reaches −5, so it can be dragged THROUGH ZERO mid-tick; a throw inside
        # decide! lands in the session's IO/EOF-only catch and SILENTLY DROPS the connection.
        for cla in (20.0, 1.0, 1e-12, 0.0, -1e-12, -5.0)
            w, s = pick_world(cla = cla)
            ok = true
            for _ in 1:300
                tick!(w, s, dt); empty!(w.events)
                m = w.entities[:m1]
                ok &= all(isfinite, (m.pos[1], m.pos[3], m.vel[1], m.vel[3],
                                     m.comp[:pitch_theta], m.comp[:pitch_q], m.comp[:delta_cmd]))
                ok &= all(isfinite, values(filter(kv -> kv[2] isa Float64, w.env[:telemetry])))
            end
            @test ok                                   # no NaN/Inf, no throw — at, through and past 0
        end
        # C_Lα < 0 is NOT degenerate and NOT floored: the divide by a SIGNED C_Lα flips α_cmd's sign
        # and `lift ∝ C_Lα·α` puts the lift back where commanded — self-consistent THROUGH zero.
        wn, sn = pick_world(cla = -20.0)
        for _ in 1:2000; tick!(wn, sn, dt); empty!(wn.events); end
        @test wn.env[:telemetry]["m1.a_max_aero"] > 0.0      # the ceiling is a MAGNITUDE (|C_Lα|)
        # V → 0 (the launch/apex degenerate): the Q floor keeps the divide finite; α_cmd pegs.
        ws, ss = pick_world(V0 = 0.0)
        for _ in 1:200; tick!(ws, ss, dt); empty!(ws.events); end
        @test all(isfinite, (ws.entities[:m1].pos[1], ws.entities[:m1].pos[3]))
        @test isfinite(ws.env[:telemetry]["m1.alpha_cmd"])
    end

    @testset "`:alpha` with NO airframe params ⇒ :ideal, no aero keys (degenerate, not a crash)" begin
        # The rung on a plain point-mass missile: the α command has nothing to actuate, so it
        # degenerates to :ideal's perfect tracking and ships no aero readout (af-params presence is
        # LOAD-static, so the keys can't go stale by being absent).
        w = World(seed = 19, fidelity = Dict{Symbol,Symbol}(:guidance => :pn, :autopilot => :alpha))
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(700.0, 0.0, 0.0),
                                 comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0,
                                                         :n_pn => 4.0, :a_max => 3000.0))
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
                                 vel = Vec3(-800.0, 0.0, 200.0))
        s = Subsystem[BallisticMissile(:m1), Autopilot(:m1)]
        for _ in 1:100; tick!(w, s, dt); empty!(w.events); end
        tel = w.env[:telemetry]
        @test !haskey(tel, "m1.a_max_aero") && !haskey(tel, "m1.alpha_cmd")
        @test haskey(w.entities[:m1].comp, :a_ctrl)              # it flies a_ctrl, like :ideal
        @test isapprox(tel["m1.a_ach"], tel["m1.a_cmd"]; rtol = 1e-12)   # perfect tracking
        @test tel["m1.track_gap"] == 0.0
    end

    @testset "loader — airframe.alpha_max + the α-loop gains parse & reject" begin
        base = """
        name: alim
        seed: 19
        dt_physics: 0.001
        fidelity: {airframe: pitch_coupled, guidance: pn, autopilot: alpha}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance:
                n_pn: 4.0
                a_max: 3000.0
                delta_max: 0.4
                k_alpha: 1.0
                k_q: 0.3
              airframe:
                inertia_kgm2: 20.0
                cma: -1.0
                cmd: 3.0
                cmq: -150.0
                cla: 20.0
                alpha_max: 0.2
          - id: t1
            kind: target
            pos: [6000.0, 0.0, 4200.0]
            vel: [-800.0, 0.0, 200.0]
            target: {rcs_m2: 1.0, maneuver: {a_lat_mps2: 200.0, turn_sign: 1.0}}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            c = scn.world.entities[:m1].comp
            @test c[:af_alpha_max] == 0.2 && c[:k_alpha] == 1.0 && c[:k_q] == 0.3
            @test c[:delta_max] == 0.4                       # slice-15's cap REUSED by the α loop
            @test scn.world.fidelity[:autopilot] === :alpha   # the NEW rung validates through the wire
            # α_max defaults when omitted (a bare airframe block can't KeyError a tick).
            noam = replace(base, "        alpha_max: 0.2\n" => "")
            pd = joinpath(dir, "def.yaml"); write(pd, noam)
            @test load_scenario(pd).world.entities[:m1].comp[:af_alpha_max] == 0.2
            # REJECTS: unlike cma/cla, a LIMIT has no lesson-adjacent negative branch — α_max ≤ 0
            # would clamp every command to ~0 and silently freeze the fin.
            for bad in ("alpha_max: 0.0", "alpha_max: -0.2")
                pb = joinpath(dir, "bad.yaml"); write(pb, replace(base, "alpha_max: 0.2" => bad))
                @test_throws ErrorException load_scenario(pb)
            end
            # k_α > 0 (a zero/negative α-error gain nulls or inverts the loop); k_q ≥ 0 (0 = no rate
            # damping is legal, just ringier; NEGATIVE would ANTI-damp the short period into divergence).
            # One substitution per case — replacing BOTH gain lines would duplicate a YAML key and the
            # load would throw for the wrong reason (a test that malforms its own fixture proves nothing).
            for (old, bad) in (("k_alpha: 1.0", "k_alpha: 0.0"), ("k_alpha: 1.0", "k_alpha: -1.0"),
                               ("k_q: 0.3", "k_q: -0.3"))
                pb = joinpath(dir, "badg.yaml"); write(pb, replace(base, old => bad))
                @test_throws ErrorException load_scenario(pb)
            end
            # k_q == 0 is ACCEPTED (undamped, not invalid).
            pz = joinpath(dir, "kq0.yaml"); write(pz, replace(base, "k_q: 0.3" => "k_q: 0.0"))
            @test load_scenario(pz).world.entities[:m1].comp[:k_q] == 0.0
        end
    end
end

# ── SLICE 20 — INDUCED DRAG WIRED: the missile lowers its own ceiling (§11 Tier A, gate 2) ──
# The bill for the lift (`C_Di = K·C_L²`, along −v̂) enters `_integrate_coupled!`'s STAGE force, so
# the SAME α that turns the path also eats the speed that sets the ceiling that limits the turn —
# the project's first DEGENERATIVE SPIRAL, and the cash-in of slices 17/19's explicit "lift is
# drag-free / speed-preserving" approximation. (NOT a "positive-feedback loop" — the speed bleed is
# SELF-LIMITING: the bill ∝ V²α², so as V falls the bleed rate falls and V ASYMPTOTES. The positive
# sign is on the TRACKING ERROR and only once the demand crosses the falling ceiling. airframe.jl
# carries the full statement.)
#
# THE TWO THINGS THIS BLOCK MUST EARN (the rest is gate 3's verifier):
#   1. ADDITIVITY — key-ABSENT ⇒ the drag arm is unreachable ⇒ slices 16/17/19 bit-identical. The
#      existing slice-19 transient golden pins only `atol = 1e-6`, which a −0.0-scale bit flip would
#      SAIL THROUGH, so byte-identity gets its OWN `===` tooth here.
#   2. NOT A DEAD KNOB — the arc's signature failure (slice 19's gate-3 `speed` was consumed once at
#      load and read by NOTHING per-tick; the fin slice died of a knob shadowed by another cap). K
#      must MOVE THE PHYSICS, live, and be proven to.
# Class 4c: physics-changing, NO RNG (truth-fed PN, no seeker) ⇒ "draw-count invariance" is VACUOUS
# — do NOT copy the slice-11/13 draw language. The 6th consecutive 4c (14/15/16/17/19).
@testset "induced drag wired (slice 20 — the spiral)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # THE GATE-0 PICK (FINDING 9): slice-19's airframe/autopilot VERBATIM (α_max 0.2 — physical at
    # ≈11.5°, NOT unpegged by inflating it), against a NON-maneuvering target at 9 km. The target
    # does not jink: the missile pays for ITS OWN TURN onto the collision course (FINDING 7 REFUTED
    # "a harder engagement costs more" — never write it). |v_t| = 825 > 700 ⇒ it OUTRUNS the missile
    # ⇒ a clean FIRST CPA with no curve-back ([[ewsim-missile-verifier-sampling]]). cd_area = 0, so
    # every m/s lost is provably bought with α (the isolation).
    function k_world(; K = nothing, airframe = :pitch_coupled, cla = 20.0)
        w = World(seed = 20, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                            :autopilot => :alpha,
                                                            :airframe => airframe))
        el = deg2rad(12.0)
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => cla,
                                :af_alpha_max => 0.2,
                                :n_pn => 4.0, :a_max => 3000.0, :delta_max => 0.4,
                                :k_alpha => 1.0, :k_q => 0.3)
        # PRESENCE, not value, is the gate — `K = nothing` must leave the key ABSENT (the loader's
        # `haskey(ab, "k_induced")` shape), which is what makes slices 16/17/19 unreachable-by-drag.
        K === nothing || (comp[:af_k_induced] = K)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(700.0 * cos(el), 0.0, 700.0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(9000.0, 0.0, 4200.0),
                                 vel = Vec3(-800.0, 0.0, 200.0), comp = Dict{Symbol,Any}())
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # To first CPA. The sat/defl scans are LOS-GATED (r > 300 m, t > 0.2 s) — gate-0 FINDING 8: with
    # `r_stop = 0` PN's ω→∞ at r→0 spikes a_cmd to a_max and δ punches δ_max in the last few ticks.
    # Slice 19 could pin an UNGATED `defl_sat == 0` only BECAUSE it misses by 295 m and never enters
    # that regime; a HIT scenario CANNOT, and must gate. Do NOT copy slice 19's assertion here.
    function fly_k(; T = 16.0, kw...)
        w, s = k_world(; kw...)
        rmin, prev, closing = Inf, Inf, true
        aero_sat = 0; defl_sat = 0; gated = 0; t = 0.0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events); t += dt
            r = n3(w.entities[:t1].pos - w.entities[:m1].pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            tel = w.env[:telemetry]
            if closing && r > 300.0 && t > 0.2
                gated += 1
                get(tel, "m1.aero_sat", 0.0) > 0.5 && (aero_sat += 1)
                get(tel, "m1.defl_sat", 0.0) > 0.5 && (defl_sat += 1)
            end
            !closing && break
        end
        m = w.entities[:m1]
        return (miss = rmin, V = n3(m.vel), aero_sat = aero_sat, defl_sat = defl_sat,
                gated = gated, w = w, tel = w.env[:telemetry])
    end

    @testset "ADDITIVITY — key ABSENT ⇒ the drag arm is unreachable (bit-identical, `===`)" begin
        # The `:a_ctrl` precedent: byte-identity BY CONSTRUCTION (the else-arm is slice 17/19's code,
        # textually), not by trusting `K = 0 → zero`. Two absent-key worlds replay bit-identically…
        w1, s1 = k_world(K = nothing); w2, s2 = k_world(K = nothing)
        for _ in 1:3000
            tick!(w1, s1, dt); empty!(w1.events)
            tick!(w2, s2, dt); empty!(w2.events)
        end
        @test w1.entities[:m1].pos === w2.entities[:m1].pos      # class 4c: no RNG, exact replay
        @test w1.entities[:m1].vel === w2.entities[:m1].vel
        @test !haskey(w1.entities[:m1].comp, :af_k_induced)      # the key never appears by itself
        # …and the WIRE is byte-identical: a slice-16/17/19 missile ships NO `a_induced` key (the
        # slice-15 fin-key / slice-17 lift-key precedent — an absent key, not a zero value).
        @test !haskey(w1.env[:telemetry], "m1.a_induced")
        @test haskey(w1.env[:telemetry], "m1.a_lift")            # …while the slice-17 keys DO ship
    end

    @testset "the K=0 arm is a TRUE no-op — bit-exact vs key-absent (the `==` no-op precedent)" begin
        # An AUTHORED `k_induced: 0.0` takes the DRAG closure, the absent key takes slice-19's. If
        # the drag term is honest at K = 0 the two must agree BIT-FOR-BIT — a "calibrated to pass"
        # atol would hide a −0.0-shaped regression (convention 11, the mismatched-EP no-op shape).
        # NOTE this does NOT make the `haskey` guard redundant: the guard makes additivity
        # STRUCTURAL (the else-arm cannot differ from slice 19 — it IS slice 19), where this test
        # only shows the arithmetic happens to agree TODAY, at K = 0, with this exact formula.
        wa, sa = k_world(K = nothing); wb, sb = k_world(K = 0.0)
        for _ in 1:3000
            tick!(wa, sa, dt); empty!(wa.events)
            tick!(wb, sb, dt); empty!(wb.events)
        end
        @test wa.entities[:m1].pos === wb.entities[:m1].pos
        @test wa.entities[:m1].vel === wb.entities[:m1].vel
        @test wb.env[:telemetry]["m1.a_induced"] == 0.0          # …and the bill IS zero, not ε
    end

    @testset "⭐ NOT A DEAD KNOB — K MOVES the physics (the arc's signature failure)" begin
        # Slice 19's gate 3 caught `speed` DEAD (consumed once at load, read by NOTHING per-tick) and
        # gate 2 had PASSED it — a no-crash check passes on a dead knob. So this asserts MOVEMENT,
        # not absence-of-throw. K is fetched EVERY tick by `_integrate_coupled!`'s stage closure.
        free = fly_k(K = 0.0)
        paid = fly_k(K = 0.3)
        @test paid.V < free.V - 200.0                # the bill is REAL (probed: 663.6 → 212.7 m/s)
        @test paid.miss > 20.0 * free.miss           # …and it reaches the outcome (1.27 → 714 m)
        @test paid.tel["m1.a_induced"] > 1.0         # the readout is LIVE, not a constant 0
        @test free.tel["m1.a_induced"] == 0.0
    end

    @testset "⭐ THE SPIRAL — the ceiling FALLS, and the missile is what lowered it" begin
        # THE LESSON, on the live wire. Nothing that sets the ceiling was touched: ρ, S, C_Lα, α_max
        # and mass are IDENTICAL across the two arms — ONLY K differs. Slice 19 moved this ceiling
        # with the ρ knob (a flight condition the ENGINEER dialled); here the MISSILE moves it, by
        # turning. (Slice 19's α_max is DISQUALIFIED as this slice's lever — it now feeds the drag
        # through the achieved α too, so it is no longer isolated. K enters ONLY the drag term.)
        free = fly_k(K = 0.0)
        paid = fly_k(K = 0.3)
        ceil_free = free.tel["m1.a_max_aero"]
        ceil_paid = paid.tel["m1.a_max_aero"]
        @test ceil_paid < 0.4 * ceil_free            # probed 242.1 → 24.9 (a ~10× collapse)
        # THE HEADLINE (gate-0 FINDING 9): at K=0 the aero ceiling NEVER BINDS ONCE in the guided
        # window — it is not a factor at all. The missile's own turn brings it down onto itself.
        @test free.aero_sat == 0                     # 0.0% — nothing to see here…
        @test paid.aero_sat > 0.4 * paid.gated       # …and now it binds ~61% of the approach
        # THE ISOLATION, RE-ESTABLISHED not copied (FINDING 8): the FOURTH cap (δ_max) stays clear
        # under BOTH arms in the LOS-gated window, so it cannot be standing in for the lesson.
        @test free.defl_sat == 0
        @test paid.defl_sat == 0
        @test free.gated > 1000 && paid.gated > 1000  # the window is real, not an empty scan
    end

    @testset "⭐ THE DISCRIMINATOR — induced bills the TURN; parasitic bills the FLIGHT" begin
        # ⚠ THE TOOTH THAT EARNS THIS SLICE ITS TITLE (advisor, load-bearing). Gate-0 FINDING 5:
        # matched on ΔV, a parasitic `cd_area` reproduces the induced miss AND ceiling almost
        # exactly (45.02 m / 173.2 vs 44.17 m / 176.3). So the spiral's DOWNSTREAM —
        # bleed → Q → ceiling → miss — is what ANY speed loss does and is NOT evidence of induced
        # drag. The ONLY distinctive claim is the SOURCE of the bill, and it lives HERE or nowhere:
        #   • induced  = a CLOSED LOOP, written BY THE MANEUVER (∝ α²) — self-inflicted.
        #   • parasitic = an OPEN-LOOP TOLL, set by cd_area — it arrives whatever you do.
        # Without this test the slice's name is unearned by its suite.
        #
        # A STRAIGHT fly-out: the target is parked 400 km away and stationary, so PN's λ̇ ≈ 0, the
        # missile commands ≈ no α, and it coasts on gravity alone. The ATTRIBUTABLE bill is
        # `ΔV(drag) − ΔV(no drag)` on the SAME arm — which cancels gravity and time-of-flight (the
        # confound that REFUTED FINDING 7's demand story; see the header).
        function coast(; K = nothing, cd = 0.0, T = 4.0)
            w, s = k_world(K = K)
            m = w.entities[:m1]
            m.comp[:cd_area_m2] = cd
            w.entities[:t1].pos = Vec3(400000.0, 0.0, 3000.0)
            w.entities[:t1].vel = Vec3(0.0, 0.0, 0.0)
            V0 = n3(m.vel)
            for _ in 1:round(Int, T / dt); tick!(w, s, dt); empty!(w.events); end
            return (dV = V0 - n3(m.vel), α = abs(get(w.env[:telemetry], "m1.alpha", 0.0)))
        end
        base   = coast(K = 0.0)
        ind    = coast(K = 0.3)                  # the SHIPPED knob maximum
        para   = coast(K = 0.0, cd = 0.02)
        @test base.α < 0.01                      # it really is flying straight (α ≈ 0)
        # 1. INDUCED BILLS A STRAIGHT FLIGHT ~NOTHING — α² = 0, so there is nothing to pay for.
        #    (probed: 0.06 m/s over 4 s, against a 700 m/s missile.)
        @test ind.dV - base.dV < 1.0
        # 2. PARASITIC BILLS IT ANYWAY — same flight, same 4 s, no maneuver: ~136 m/s (probed).
        @test para.dV - base.dV > 50.0
        # 3. …and they differ by MORE THAN TWO ORDERS OF MAGNITUDE on the same coast. `K` is
        #    provably NOT `cd_area` in a costume (the convention-4 false-fidelity trap, which this
        #    arc has now hit five times).
        @test (para.dV - base.dV) > 50.0 * (ind.dV - base.dV)
        # 4. THE SAME K, NOW ASKED TO TURN, bills ~450 m/s (fly_k's intercept). The bill is written
        #    by the MANEUVER, not by the airframe's existence — that IS the closed loop.
        @test fly_k(K = 0.0).V - fly_k(K = 0.3).V > 200.0
    end

    @testset "the drag is gated on the COUPLING too — :point_mass has no lift to bill for" begin
        # `a_induced` is KEY-gated AND RUNG-gated (inside the `:pitch_coupled` block — the slice-17
        # lift-keys precedent). Under `:point_mass` there is no α and no lift, so a bill would be
        # meaningless; the reference arm's wire must stay clean.
        pm = fly_k(K = 0.3, airframe = :point_mass)
        @test !haskey(pm.tel, "m1.a_induced")
        @test !haskey(pm.tel, "m1.a_lift")           # (the slice-17 rung gate, still holding)
        @test pm.miss < 5.0                          # …and it still HITS by fiat (a_ctrl, no aero)
    end

    @testset "loader — `k_induced` is PRESENCE-gated and its SIGN is validated (convention 5)" begin
        mktempdir() do dir
            base = """
            name: s20
            seed: 20
            fidelity: {airframe: pitch_coupled, guidance: pn, autopilot: alpha}
            entities:
              - id: m1
                kind: missile
                pos: [0.0, 0.0, 3000.0]
                missile:
                  mass_kg: 140.0
                  speed: 700.0
                  elevation_deg: 12.0
                  guidance: {n_pn: 4.0, a_max: 3000.0, delta_max: 0.4}
                  airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0, cmq: -150.0, cla: 20.0, alpha_max: 0.2, k_induced: 0.15}
              - id: t1
                kind: target
                pos: [9000.0, 0.0, 4200.0]
                vel: [-800.0, 0.0, 200.0]
                target: {rcs_m2: 1.0}
            """
            p = joinpath(dir, "s20.yaml"); write(p, base)
            # The fixture must LOAD CLEAN first: the `@test_throws` cases below are only meaningful
            # if the ONLY thing wrong with them is `k_induced` (a guided missile with no target
            # throws for an unrelated reason and every negative case would pass for free — the
            # slice-19 "a test that malforms its own fixture proves nothing" trap, hit live here).
            @test load_scenario(p).world.entities[:m1].comp[:af_k_induced] == 0.15
            # PRESENCE-GATED: no `k_induced:` ⇒ NO key ⇒ the drag arm is unreachable. This is the
            # slice-18 `alt_hold_m` precedent and it is LOAD-BEARING — gating on the airframe BLOCK
            # would grow the key on slices 16/17/19 (they ALL have airframe blocks) and silently
            # give every one of them a drag term. Convention 2 dead.
            pn_ = joinpath(dir, "none.yaml")
            write(pn_, replace(base, ", k_induced: 0.15" => ""))
            @test !haskey(load_scenario(pn_).world.entities[:m1].comp, :af_k_induced)
            # 0 is LEGAL (drag-free — slices 17/19's approximation, authored explicitly)…
            pz = joinpath(dir, "zero.yaml")
            write(pz, replace(base, "k_induced: 0.15" => "k_induced: 0.0"))
            @test load_scenario(pz).world.entities[:m1].comp[:af_k_induced] == 0.0
            # …while a NEGATIVE K is a drag that ACCELERATES — rejected at LOAD. (Contrast cma/cla,
            # which are validated FINITE only: a negative lift slope is merely inverted and is a
            # lesson-adjacent knob. There is no such branch for K.)
            for bad in ("k_induced: -0.1", "k_induced: .nan")
                pb = joinpath(dir, "bad.yaml"); write(pb, replace(base, "k_induced: 0.15" => bad))
                @test_throws ErrorException load_scenario(pb)
            end
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
@testset "exponential atmosphere wired (slice 21 — the ceiling you lower by CLIMBING)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # THE GATE-0 PICK (F1–F4). Slice-19/20's airframe VERBATIM, but the ENGAGEMENT is new and
    # every part of it is load-bearing:
    #  • a SLOW, DISTANT, HIGH target (22 km out, 14 km up, 250 m/s). F1: "make it climb" is
    #    UNFLYABLE against a fast target — a 700 m/s missile needs ~15 s to climb 6 km, in which a
    #    head-on 800 m/s target covers 12 km, so BOTH arms missed by kilometres (the REACH wall,
    #    not the ceiling). Slow + distant buys the climb the gradient needs.
    #  • the target JINKS (`a_lat = 40`). F2: without it the ρ(z) missile turns EARLY, LOW, in
    #    THICK air, arrives on a good collision course, and by the time it is high and cannot
    #    maneuver IT NO LONGER NEEDS TO — ceiling 16.5 m/s² (1.7 g) at 16 km and it still only
    #    missed by 29 m. PN nulls LOS rate, so terminal demand against a straight-flier → 0 BY
    #    CONSTRUCTION. **LATE DEMAND IS STRUCTURAL, and only a maneuvering target supplies it.**
    #  • ⚠ F3: slice 20 FORBADE a maneuvering target — that rule was about attributing the induced
    #    BILL ("the missile pays for its own turn"). HERE K = 0: THERE IS NO BILL. Do not copy the
    #    rule across. The `:constant` twin flies the IDENTICAL geometry against the IDENTICAL jink
    #    and HITS, which controls for the target completely. Nor is this slice 12: the twin proves
    #    plain PN handles this jink comfortably at sea-level density (its ceiling never binds ONCE).
    #  • K = 0 AND cd_area = 0 — THE ISOLATION. Nothing bleeds speed but gravity, and the twin
    #    carries that same gravity, so the twin difference is PURE ALTITUDE.
    function atm_world(; H = nothing, atmosphere = :exponential, K = nothing,
                       rho0 = 1.225, alat = 40.0, airframe = :pitch_coupled)
        w = World(seed = 21, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                            :autopilot => :alpha,
                                                            :airframe => airframe,
                                                            :atmosphere => atmosphere))
        el = deg2rad(25.0)
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => rho0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.2,
                                :n_pn => 4.0, :a_max => 3000.0, :delta_max => 0.4,
                                :k_alpha => 1.0, :k_q => 0.3)
        # PRESENCE, not value, is the gate (the slice-20 `k_induced` shape): `H = nothing` must
        # leave the key ABSENT, which is what makes slices 8–20 unreachable-by-atmosphere.
        H === nothing || (comp[:af_scale_height] = H)
        K === nothing || (comp[:af_k_induced] = K)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 1000.0),
                                 vel = Vec3(700.0 * cos(el), 0.0, 700.0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(22000.0, 0.0, 14000.0),
                                 vel = Vec3(-250.0, 0.0, 0.0),
                                 comp = Dict{Symbol,Any}(:a_lat_mps2 => alat, :turn_sign => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ManeuveringTarget(:t1)]
    end

    # To first CPA ([[ewsim-missile-verifier-sampling]]: first-descending-band, never a global min).
    #
    # ⚠ THE LOS GATE IS r > 1000, **NOT** slice-20's TEST value of 300 — and this was MEASURED, not
    # copied (it failed first run at 300, which is exactly how the memory says this trap presents).
    # Slice 20's own *wire* used 1000 for this reason and only its Julia test could afford 300.
    # Here the TWIN HITS (1.949 m), so it flies the full r→0 endgame where PN's ω → ∞ spikes a_cmd
    # (slice-20 FINDING 8). Its ceiling then blips against that spike — 94 ticks at a 300 m gate.
    # Those blips are the ARTIFACT, not an aero limit: measured, they lie ENTIRELY within
    # r ∈ [1.9, 362.9] m, and at r > 1000 the count is EXACTLY 0. The 1000 m gate excludes that
    # endgame and is a no-op for the missing arms (whose CPAs are 360 m and 1706 m — never closer),
    # so it cannot flatter them. Slice 19 could assert this UNGATED only because it misses by 295 m
    # and never enters the regime; a HIT scenario cannot. Do NOT lower this.
    function fly_atm(; T = 60.0, kw...)
        w, s = atm_world(; kw...)
        rmin, prev, closing = Inf, Inf, true
        aero_sat = 0; defl_sat = 0; gated = 0; t = 0.0
        α_pk = 0.0; ceil0 = NaN; ceil_end = NaN; ρf0 = NaN; ρf_end = NaN; V0 = NaN; V_end = NaN
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events); t += dt
            m = w.entities[:m1]
            r = n3(w.entities[:t1].pos - m.pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            tel = w.env[:telemetry]
            if closing
                cl = get(tel, "m1.a_max_aero", NaN)
                ρ  = EWSim._airframe_rho(m.comp, w, m.pos[3]) / 1.225
                isnan(ceil0) && (ceil0 = cl; ρf0 = ρ; V0 = n3(m.vel))
                ceil_end = cl; ρf_end = ρ; V_end = n3(m.vel)
                if r > 1000.0 && t > 0.2
                    gated += 1
                    get(tel, "m1.aero_sat", 0.0) > 0.5 && (aero_sat += 1)
                    get(tel, "m1.defl_sat", 0.0) > 0.5 && (defl_sat += 1)
                    α_pk = max(α_pk, abs(get(tel, "m1.alpha", 0.0)))
                end
            end
            !closing && break
        end
        return (miss = rmin, aero_sat = aero_sat, defl_sat = defl_sat, gated = gated, α_pk = α_pk,
                ceil0 = ceil0, ceil_end = ceil_end, ρf0 = ρf0, ρf_end = ρf_end,
                V0 = V0, V_end = V_end, w = w, tel = w.env[:telemetry])
    end

    @testset "ADDITIVITY — key ABSENT ⇒ the ρ(z) arm is unreachable (bit-identical, `===`)" begin
        # The slice-20 induced-drag / slice-9 `:a_ctrl` precedent: byte-identity BY CONSTRUCTION
        # (the else-arm is slice 17/19/20's code, TEXTUALLY), never by trusting `exp(0) == 1`.
        w1, s1 = atm_world(H = nothing); w2, s2 = atm_world(H = nothing)
        for _ in 1:3000
            tick!(w1, s1, dt); empty!(w1.events)
            tick!(w2, s2, dt); empty!(w2.events)
        end
        @test w1.entities[:m1].pos === w2.entities[:m1].pos     # class 4c: no RNG, exact replay
        @test w1.entities[:m1].vel === w2.entities[:m1].vel
        @test !haskey(w1.entities[:m1].comp, :af_scale_height)  # the key never appears by itself
    end

    @testset "⭐ BOTH OFF-STATES ARE THE SAME CODE — `:constant` ≡ key-absent, BIT-FOR-BIT" begin
        # THE RUNG'S CENTRAL STRUCTURAL CLAIM (advisor): the verbatim slice-17/19/20 else-arm
        # serves BOTH the key-absent world AND `:atmosphere === :constant`, so byte-identity for
        # every prior slice is automatic and the three-state wrinkle dissolves. A missile carrying
        # an authored H but running `:constant` must be bit-identical to one with no key at all —
        # `===`, not a calibrated atol (convention 11's mismatched-EP no-op shape).
        wa, sa = atm_world(H = nothing)
        wb, sb = atm_world(H = 8500.0, atmosphere = :constant)
        for _ in 1:4000
            tick!(wa, sa, dt); empty!(wa.events)
            tick!(wb, sb, dt); empty!(wb.events)
        end
        @test wa.entities[:m1].pos === wb.entities[:m1].pos
        @test wa.entities[:m1].vel === wb.entities[:m1].vel
        @test wa.entities[:m1].comp[:pitch_theta] === wb.entities[:m1].comp[:pitch_theta]
        # …and H is INERT under `:constant`: a wildly different scale height changes NOTHING.
        wc, sc = atm_world(H = 2000.0, atmosphere = :constant)
        for _ in 1:4000; tick!(wc, sc, dt); empty!(wc.events); end
        @test wa.entities[:m1].pos === wc.entities[:m1].pos
    end

    @testset "⭐ INERT WITHOUT ITS HOST — `:atmosphere` needs `:pitch_coupled` (half-a-missile guard)" begin
        # `_atm_on`'s THIRD conjunct, pinned. ρ(z) reaches ONLY the coupled path: `_integrate_coupled!`
        # is gated on `:pitch_coupled`, so under `:point_mass` the translation flies `total_accel`'s
        # AUTHORED constant ρ whatever this rung says. The conjunct makes every OTHER ρ-reading site
        # revert with it — without it the readouts (and slice-16's rotational `_integrate_airframe!`)
        # would report ρ(z) while pos/vel flew ρ₀: HALF THE MISSILE IN ONE ATMOSPHERE AND HALF IN
        # ANOTHER. Inert-without-its-host is the slice-14 (`:salvo` needs a `:datalink`) / slice-13
        # (`discrimination` needs `:scan`) shape.
        #
        # The tooth is `===` on the TRAJECTORY, not on the predicate: under `:point_mass` an
        # H = 8500 `:exponential` world must be BIT-IDENTICAL to its `:constant` twin — i.e. the rung
        # is not merely "mostly off", it is unreachable. Note this is a REAL guard and not a
        # tautology: the missile CLIMBS to ~13 km here, where ρ(z)/ρ₀ ≈ 0.2, so a leak of ρ(z) into
        # ANY of the five sites would move θ/q (via the pitching moment) far outside `===`.
        wp, sp = atm_world(H = 8500.0, atmosphere = :exponential, airframe = :point_mass)
        wq, sq = atm_world(H = 8500.0, atmosphere = :constant,    airframe = :point_mass)
        for _ in 1:6000
            tick!(wp, sp, dt); empty!(wp.events)
            tick!(wq, sq, dt); empty!(wq.events)
        end
        @test wp.entities[:m1].pos          === wq.entities[:m1].pos
        @test wp.entities[:m1].vel          === wq.entities[:m1].vel
        @test wp.entities[:m1].comp[:pitch_theta] === wq.entities[:m1].comp[:pitch_theta]
        @test wp.entities[:m1].comp[:pitch_q]     === wq.entities[:m1].comp[:pitch_q]
        # the readout agrees with the plant it describes: under `:point_mass` the air is ρ₀, EXACTLY
        @test EWSim._airframe_rho(wp.entities[:m1].comp, wp, wp.entities[:m1].pos[3]) == 1.225
        @test wp.env[:telemetry]["m1.rho_air"] == 1.225
        # …and it is the COUPLING that switches it on: the SAME H and the SAME rung, coupled ⇒ ρ(z).
        # PROBED, THEN PINNED against the live path (convention 10 — a first draft GUESSED
        # `< 0.6·ρ₀` here and failed at 0.878: at 6 s this missile is only ~2.8 km up, where the air
        # is still ~72% of sea level. The 4.4× collapse is a 60-SECOND story, not a 6-second one).
        wc, sc = atm_world(H = 8500.0, atmosphere = :exponential, airframe = :pitch_coupled)
        for _ in 1:6000; tick!(wc, sc, dt); empty!(wc.events); end
        # the readout IS ρ(z) at the flown height — the non-arbitrary form of "the coupling switched
        # it on" (`==`: same expression, same air, no tolerance to hide behind)
        @test wc.env[:telemetry]["m1.rho_air"] ==
              air_density(wc.entities[:m1].pos[3]; rho0 = 1.225, H = 8500.0)
        @test isapprox(wc.env[:telemetry]["m1.rho_air"], 0.878; atol = 1e-3)   # ~2.8 km up
        @test wc.env[:telemetry]["m1.rho_air"] < 0.95 * 1.225   # …a REAL move off ρ₀, not a wobble
    end

    @testset "the `rho_air` wire key — KEY-gated, ships under BOTH rungs, matches the integrator" begin
        # THE KEY IS THE GATE, NEVER THE RUNG — the deliberate contrast with `a_lift` (a produced
        # force that only exists when coupled). Under `:constant` `rho_air` ships the flat authored
        # ρ₀, and THAT IS THE POINT: the twin's ρ-factor being EXACTLY 1.0 is half the headline, and
        # rung-gating would take it off the wire and leave the client to divide `2·q_dyn/V²` —
        # physics in GDScript, which convention 13 forbids.
        we, se = atm_world(H = 8500.0, atmosphere = :exponential)
        wk, sk = atm_world(H = 8500.0, atmosphere = :constant)
        wn, sn = atm_world(H = nothing)                        # slices 16–20's shape: NO scale height
        for _ in 1:3000
            tick!(we, se, dt); empty!(we.events)
            tick!(wk, sk, dt); empty!(wk.events)
            tick!(wn, sn, dt); empty!(wn.events)
        end
        @test haskey(we.env[:telemetry], "m1.rho_air")         # :exponential ships it…
        @test haskey(wk.env[:telemetry], "m1.rho_air")         # …and so does :constant (BOTH rungs)
        # a slice-16..20 wire must NOT grow a key (byte-identity — the a_induced / fin-key precedent)
        @test !haskey(wn.env[:telemetry], "m1.rho_air")
        # THE READOUT DESCRIBES THE MISSILE THAT IS FLYING (the four-site funnel's whole purpose):
        # `rho_air` is EXACTLY the ρ the closure integrated with, at this tick's post-integrate z.
        m = we.entities[:m1]
        @test we.env[:telemetry]["m1.rho_air"] == air_density(m.pos[3]; rho0 = 1.225, H = 8500.0)
        @test wk.env[:telemetry]["m1.rho_air"] == 1.225        # :constant is FLAT — `==`, not `≈`
        # …and `q_dyn` is built from that SAME ρ (an INDEPENDENT recompute — convention 11's
        # different-algorithm oracle: ½ρV² from the shipped ρ and the shipped speed).
        V = we.env[:telemetry]["m1.speed"]
        @test we.env[:telemetry]["m1.q_dyn"] ≈ 0.5 * we.env[:telemetry]["m1.rho_air"] * V^2 rtol = 1e-12
    end

    @testset "⭐ NOT A DEAD KNOB — H MOVES the physics (the arc's signature failure)" begin
        # slice-19's gate-3 finding: `comp[:speed]` was consumed ONCE at load and read by NOTHING
        # per-tick, and a no-crash test PASSED on it. Assert H MOVES a real quantity, never merely
        # that nothing threw. H is fetched EVERY tick by BOTH integrate! and decide! (via
        # `_airframe_rho`), so it is live by construction — pin it anyway.
        lo = fly_atm(H = 6000.0, T = 12.0)      # thins fast ⇒ a LOW ceiling
        hi = fly_atm(H = 25000.0, T = 12.0)     # thins slowly ⇒ a HIGHER ceiling
        @test lo.ceil_end < hi.ceil_end
        @test lo.ρf_end   < hi.ρf_end
        @test hi.ceil_end / lo.ceil_end > 1.5   # a REAL move, not a rounding wobble
    end

    @testset "⭐⭐ THE HEADLINE — the ceiling spread FACTORIZES EXACTLY: ρ-factor × V-factor" begin
        # gate-0 F6, and the reason this slice can do what slice 20 could NOT. Because
        # `a_max_aero = ½·ρ(z)·V²·S·|C_Lα|·α_max/m`, the within-run ceiling ratio is IDENTICALLY
        # [ρ(z)/ρ(z₀)]·[V/V₀]² — an ALGEBRAIC IDENTITY, not an empirical fit. So ALTITUDE and
        # SPEED separate with NO residual, and the ρ-factor is a PURE-z headline with no V confound
        # (slice 20's collapse ratio could never be decomposed this way — advisor).
        e = fly_atm(H = 8500.0, T = 60.0)
        @test (e.ceil_end / e.ceil0) ≈ (e.ρf_end / e.ρf0) * (e.V_end / e.V0)^2 atol = 1e-12
        # THE ρ-FACTOR COLLAPSES — the lesson, as a number (F4/F6: ≈0.889 → ≈0.203, a 4.4× fall
        # WITHIN ONE RUN, with ρ₀/α_max/mass/geometry ALL HELD. Nobody lowered it; it CLIMBED).
        @test e.ρf0   ≈ 0.889 atol = 5e-3
        @test e.ρf_end < 0.25
        @test e.ρf0 / e.ρf_end > 3.5
    end

    @testset "⭐⭐ THE TWIN's ρ-FACTOR IS *EXACTLY* 1 — constant ρ blames SPEED for everything" begin
        # The sharpest single fact in the slice (F6). The `:constant` arm's ceiling ALSO falls on
        # this climb — by ≈2×, purely from the V bleed, i.e. GRAVITY — and its model attributes
        # 100% of that to speed because its ρ-factor is 1.0 BY DEFINITION. ρ(z) reveals the 4.4× it
        # could not see. `==`, not `≈`: the twin's ρ never moves off ρ₀ by even a bit.
        c = fly_atm(H = nothing, T = 60.0)
        @test c.ρf0 == 1.0
        @test c.ρf_end == 1.0
        @test (c.ceil_end / c.ceil0) ≈ (c.V_end / c.V0)^2 atol = 1e-12   # ALL of it is speed
        @test c.ceil_end < c.ceil0                                        # it does fall — gravity
    end

    @testset "⭐⭐ THE LESSON — the old model HITS, the real atmosphere MISSES (the rung's point)" begin
        # F4, the live side-by-side that IS the punchline and the reason this is a RUNG and not a
        # knob (no slider value reaches `:constant` — H = ∞ is a LIMIT POINT, not a position).
        c = fly_atm(H = nothing,  T = 60.0)     # the OLD model: constant ρ
        e = fly_atm(H = 8500.0,   T = 60.0)     # the truth: Earth's REAL 8500 m scale height
        @test c.miss < 10.0                     # HIT  (gate 0: 1.95 m)
        @test e.miss > 100.0                    # MISS (gate 0: 360.74 m)
        @test e.miss / c.miss > 50.0            # gate 0: 185×
        # THE ISOLATION, re-established not copied: across the whole guided approach the twin's
        # aero ceiling NEVER BINDS ONCE, so nothing in ITS run is aero-limited — the miss is not
        # "the ceiling binds" (slice 19), it is "the ceiling FELL BECAUSE IT CLIMBED". (Gated at
        # r > 1000 — see `fly_atm`: the twin's only binds are the r→0 endgame artifact.)
        @test c.aero_sat == 0
        @test e.aero_sat > 0
        # …and the FOURTH cap (slice-15's δ_max) is provably not standing in, under BOTH arms.
        @test c.defl_sat == 0
        @test e.defl_sat == 0
        # …and `a_max` (slice 10/12's authored MAGNITUDE clamp) is INERT: the aero ceiling is far
        # below it everywhere, so it cannot be what bit (the slice-20 assertion, re-earned).
        @test e.ceil0 < 3000.0
        @test c.ceil0 < 3000.0
    end

    @testset "the α_max clamp does NOT LEAK at the knob's floor (F8 — the bound is MEASURED)" begin
        # slice-19 FINDING 14: α_max bounds the COMMAND, lift uses the ACHIEVED α, so a hot loop
        # overshoots and the ceiling LEAKS. F8 measured the breach at H ≤ 3000 (α_pk ≥ 0.2000) and
        # bounded the knob at 6000 — a 2× margin, the slice-20 K discipline. Pin the FLOOR clean.
        lo = fly_atm(H = 6000.0, T = 60.0)
        @test lo.α_pk < 0.2                       # no leak at the knob's minimum
        @test lo.defl_sat == 0
        @test lo.miss > 100.0                     # …and the floor is still deep in the lesson
    end

    @testset "the atmosphere reaches EVERY airframe site — the readout matches the integrator" begin
        # A hidden inconsistency would be its own bug class: if `decide!` ceilinged against ρ(z)
        # while `build_env!` reported ω_sp from a constant ρ, the wire would describe a different
        # missile than the one flying. Pin that the telemetry ρ IS the integrator's ρ, by checking
        # the published ceiling against `aero_accel_limit` rebuilt from the SAME `_airframe_rho`.
        w, s = atm_world(H = 8500.0)
        for _ in 1:6000; tick!(w, s, dt); empty!(w.events); end
        m = w.entities[:m1]; tel = w.env[:telemetry]
        ρz = EWSim._airframe_rho(m.comp, w, m.pos[3])
        @test ρz < 1.225                                   # it HAS climbed into thinner air
        p = AirframeParams(m.comp[:af_S], m.comp[:af_d], m.comp[:af_I], m.comp[:af_cma],
                           m.comp[:af_cmd], m.comp[:af_cmq], ρz, m.comp[:af_cla])
        @test tel["m1.a_max_aero"] ≈
              aero_accel_limit(n3(m.vel), m.comp[:mass_kg], p; alpha_max = 0.2) atol = 1e-9
        # and ω_sp (build_env!'s slice-16 readout) is likewise on ρ(z), not ρ₀
        @test tel["m1.omega_sp"] ≈ short_period_freq(n3(m.vel), p) atol = 1e-9
    end

    @testset "⭐ THE STAGE-z GOLDEN — the ONLY thing that catches an entry-z read (F9)" begin
        # THE SLICE-17 STAGE-θ TRAP, RECURRING — and this time the golden is not "insurance", it is
        # a HUNT with a measured quarry. `_integrate_coupled!`'s closure MUST read the RK4 STAGE
        # height `P[3]`; reading the ENTRY height `e.pos[3]` compiles clean, is only O(dt²) off per
        # step, and is INVISIBLE to every other test in this file: gate-0 F9 measured it moving the
        # miss by 0.136 m on a 360 m lesson (0.04%), leaving the ρ-factor, the ceiling, the
        # factorization, the twin ratio and the leak bound ALL intact. Nothing but an absolute
        # golden can see it.
        #
        # Generated from the LIVE tick! path at 10 000 ticks (10 s — well into the climb, where ρ(z)
        # is changing fastest). THE MARGIN IS THE TOOTH (convention 11 — an atol that cannot fail is
        # a tautology): the entry-z variant, measured at this exact tick, sits
        #   Δpos_x = 1.778e-3 m, Δpos_z = 3.039e-3 m, Δθ = 1.459e-7 rad
        # away — so atol 1e-6 on position catches it with a ~3000× margin and atol 1e-9 on θ with
        # ~150×. If someone "simplifies" the stage read, these fail loudly.
        w, s = atm_world(H = 8500.0)
        for _ in 1:10000; tick!(w, s, dt); empty!(w.events); end
        m = w.entities[:m1]
        @test isapprox(m.pos[1], 6135.997966610977;            atol = 1e-6)
        @test isapprox(m.pos[3], 3887.913109564929;            atol = 1e-6)
        @test isapprox(m.comp[:pitch_theta],  0.335753272378;  atol = 1e-9)
        @test isapprox(m.comp[:pitch_q],     -0.033490350860;  atol = 1e-9)
    end

    @testset "degenerates — a live H slider can never crash a tick (convention 5)" begin
        # The consumer floor inside `air_density` is the second guard site; the loader is the first.
        # A rogue `set_param` reaching H → 0 (or negative) must not NaN the state: at z = 0 that is
        # `0/0`, and a NaN ρ propagates into `pos` and ships an invalid frame.
        for H in (1.0e-12, 0.0, -5000.0, 1.0e12)
            w, s = atm_world(H = H)
            for _ in 1:200; tick!(w, s, dt); empty!(w.events); end
            m = w.entities[:m1]
            @test all(isfinite, m.pos)
            @test all(isfinite, m.vel)
            @test isfinite(m.comp[:pitch_theta])
            @test isfinite(w.env[:telemetry]["m1.a_max_aero"])
        end
    end

    @testset "loader — `scale_height_m` is PRESENCE-gated and its SIGN is validated (convention 5)" begin
        mktempdir() do dir
            base = """
            name: s21
            seed: 21
            fidelity: {airframe: pitch_coupled, guidance: pn, autopilot: alpha, atmosphere: exponential}
            entities:
              - id: m1
                kind: missile
                pos: [0.0, 0.0, 1000.0]
                missile:
                  mass_kg: 140.0
                  speed: 700.0
                  elevation_deg: 25.0
                  guidance: {n_pn: 4.0, a_max: 3000.0, delta_max: 0.4}
                  airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0, cmq: -150.0, cla: 20.0, alpha_max: 0.2, scale_height_m: 8500.0}
              - id: t1
                kind: target
                pos: [22000.0, 0.0, 14000.0]
                vel: [-250.0, 0.0, 0.0]
                target: {rcs_m2: 1.0, maneuver: {a_lat_mps2: 40.0}}
            """
            p = joinpath(dir, "s21.yaml"); write(p, base)
            # The fixture must LOAD CLEAN first — otherwise the `@test_throws` cases below would
            # pass for free on an unrelated error (the slice-19 "a test that malforms its own
            # fixture proves nothing" trap, which slice 20 hit live).
            @test load_scenario(p).world.entities[:m1].comp[:af_scale_height] == 8500.0
            # PRESENCE-GATED: no `scale_height_m:` ⇒ NO key ⇒ the ρ(z) arm is unreachable even with
            # `atmosphere: exponential` set. The slice-20 `k_induced` / slice-18 `alt_hold_m`
            # precedent, and LOAD-BEARING: slices 16/17/19/20 ALL carry airframe blocks, so gating
            # on the BLOCK would grow the key on every one of them.
            noh = replace(base, ", scale_height_m: 8500.0" => "")
            p2 = joinpath(dir, "s21_noh.yaml"); write(p2, noh)
            @test !haskey(load_scenario(p2).world.entities[:m1].comp, :af_scale_height)
            # THE SIGN IS VALIDATED (unlike cma/cla, which have lesson-adjacent negative branches):
            # H ≤ 0 is an atmosphere that THICKENS with altitude, or a 0/0 at the ground.
            for bad in ("0.0", "-8500.0")
                pb = joinpath(dir, "s21_$bad.yaml")
                write(pb, replace(base, "scale_height_m: 8500.0" => "scale_height_m: $bad"))
                @test_throws ErrorException load_scenario(pb)
            end
            # …and non-finite dies too (a NaN ρ reaches `pos` and ships an invalid frame)
            pn_ = joinpath(dir, "s21_nan.yaml")
            write(pn_, replace(base, "scale_height_m: 8500.0" => "scale_height_m: .nan"))
            @test_throws ErrorException load_scenario(pn_)
            # the knob addresses a REAL comp key (a knob naming a missing key dies at load — the
            # mechanism that would have caught slice-19's DEAD `speed` knob had `speed` been live)
            withknob = base * """
            knobs:
              - {target: m1, key: af_scale_height, min: 6000.0, max: 25000.0, label: "H"}
            """
            pk = joinpath(dir, "s21_knob.yaml"); write(pk, withknob)
            sc = load_scenario(pk)
            @test length(sc.knobs) == 1
            @test sc.knobs[1].key === :af_scale_height
        end
    end
end

# ═════════════════════════════════════════════════════════════════════════════════════════════
@testset "TRUE STALL wired (slice 22 gate 2 — the airframe sets its own ceiling)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # THE GATE-0 PICK (F1): **SLICE 19's geometry, NOT slice 20's.** F1 measured slice 20's
    # engagement INERT for this slice — α_pk 0.085, every arm identical to the centimetre — because
    # a non-maneuvering target never demands enough g to reach the stall. Slice 19's maneuvering
    # target at 6 km with `a_lat = 200` does. ⚠ `a_lat` is a NARROW window: at 400 BOTH arms miss by
    # >1300 m (the slice-21 REACH WALL recurring), so do not "harden" this target.
    #
    # ⚠ `α_max = 0.35 > α_stall = 0.20` — THE DESIGN, AND IT INVERTS SLICE 19 (plan §3). Post-stall
    # must be reached by the COMMAND path, NOT by slice-19 FINDING 14's achieved-α leak above the
    # clamp: a headline built on the leak is CIRCULAR, since closing that leak is a stated payoff of
    # this very slice. So α_max is deliberately NOT the binding limit here — THE PHYSICS SETS THE
    # WALL — and `k_α`/`k_q` stay at their SHIPPED authored values (F2/P6).
    function stall_world(; alpha_stall = nothing, k_drop = 0.7, k_sep = 3.0, alpha_break = 1.0e9,
                           cma_post = 0.0, alpha_sat = 2.0e9, airframe = :pitch_coupled,
                           alpha_max = 0.35, K = nothing)
        w = World(seed = 22, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                            :autopilot => :alpha,
                                                            :airframe => airframe))
        el = deg2rad(12.0)
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max,
                                :n_pn => 4.0, :a_max => 3000.0, :delta_max => 0.4,
                                :k_alpha => 1.0, :k_q => 0.3)
        # PRESENCE, not value, is the gate (the slice-20 `k_induced` / slice-21 `scale_height_m`
        # shape): `alpha_stall = nothing` must leave the key ABSENT, which is what makes slices
        # 16–21 unreachable-by-stall.
        if alpha_stall !== nothing
            comp[:af_alpha_stall] = alpha_stall
            comp[:af_k_drop]      = k_drop
            comp[:af_k_sep]       = k_sep
            comp[:af_alpha_break] = alpha_break
            comp[:af_cma_post]    = cma_post
            comp[:af_alpha_sat]   = alpha_sat
        end
        K === nothing || (comp[:af_k_induced] = K)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(700.0 * cos(el), 0.0, 700.0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
                                 vel = Vec3(-800.0, 0.0, 200.0),
                                 comp = Dict{Symbol,Any}(:a_lat_mps2 => 200.0, :turn_sign => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ManeuveringTarget(:t1)]
    end

    # To first CPA ([[ewsim-missile-verifier-sampling]]: the FIRST DESCENDING band only, never a
    # global min). The diagnostic scans are LOS-gated at r > 300 — the r→0 endgame spikes `a_demand`
    # for reasons that are not the lesson, and both arms here MISS by ≫ 300, so the gate cannot
    # flatter either of them.
    function fly_stall(; T = 14.0, kw...)
        w, s = stall_world(; kw...)
        rmin, prev, closing = Inf, Inf, true
        aero_sat = 0; defl_sat = 0; post_stall = 0; gated = 0; t = 0.0
        α_pk = 0.0; ceil0 = NaN; ceil_min = Inf; ω_ceiled = 0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events); t += dt
            m = w.entities[:m1]
            r = n3(w.entities[:t1].pos - m.pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            tel = w.env[:telemetry]
            if closing
                cl = get(tel, "m1.a_max_aero", NaN)
                isnan(ceil0) && (ceil0 = cl)
                ceil_min = min(ceil_min, cl)
                get(tel, "m1.omega_sp", 0.0) ≥ FINITE_CEIL && (ω_ceiled += 1)
                if r > 300.0 && t > 0.2
                    gated += 1
                    get(tel, "m1.aero_sat", 0.0)   > 0.5 && (aero_sat += 1)
                    get(tel, "m1.defl_sat", 0.0)   > 0.5 && (defl_sat += 1)
                    get(tel, "m1.post_stall", 0.0) > 0.5 && (post_stall += 1)
                    α_pk = max(α_pk, abs(get(tel, "m1.alpha", 0.0)))
                end
            end
            !closing && break
        end
        return (miss = rmin, aero_sat = aero_sat, defl_sat = defl_sat, post_stall = post_stall,
                gated = gated, α_pk = α_pk, ceil0 = ceil0, ceil_min = ceil_min,
                ω_ceiled = ω_ceiled, w = w, tel = w.env[:telemetry])
    end

    @testset "ADDITIVITY — key ABSENT ⇒ the stall arm is unreachable (bit-identical, `===`)" begin
        # The slice-20/21 precedent: byte-identity BY CONSTRUCTION (the stall arm LEADS the branch
        # chain and the four arms below it are slice 17/19/20/21's code TEXTUALLY), never by
        # trusting a coefficient to vanish.
        w1, s1 = stall_world(alpha_stall = nothing); w2, s2 = stall_world(alpha_stall = nothing)
        for _ in 1:3000
            tick!(w1, s1, dt); empty!(w1.events)
            tick!(w2, s2, dt); empty!(w2.events)
        end
        @test w1.entities[:m1].pos === w2.entities[:m1].pos     # class 4c: no RNG, exact replay
        @test w1.entities[:m1].vel === w2.entities[:m1].vel
        @test !haskey(w1.entities[:m1].comp, :af_alpha_stall)   # the key never appears by itself
        # …and no slice-22 key reaches the wire on a prior-slice missile
        tel = w1.env[:telemetry]
        @test !haskey(tel, "m1.post_stall")
        @test !haskey(tel, "m1.a_sep")
    end

    @testset "⭐⭐ THE PARKED KNOB *IS* THE LINEAR PATH, BIT-FOR-BIT — the knob-vs-rung claim" begin
        # THE STRUCTURAL HEART OF DECISION 1, pinned on the WIRE rather than argued. Gate 0 F7
        # REFUTED the plan's rung claim (it asserted linear was `α_stall → ∞`, a LIMIT POINT): a
        # CORNER can be PARKED OUT OF REACH, unlike slice 21's `H` where altitude is the swept
        # variable. So the off-state is knob-reachable and slice 21's own discriminator returns KNOB.
        #
        # ⚠ `===`, NOT a calibrated atol — a tolerance would BEG THE QUESTION. The claim is that a
        # parked corner IS the linear path, and it is only worth anything if it is exact.
        wa, sa = stall_world(alpha_stall = nothing)
        wb, sb = stall_world(alpha_stall = 5.0, alpha_break = 6.0, alpha_sat = 7.0)
        for _ in 1:4000
            tick!(wa, sa, dt); empty!(wa.events)
            tick!(wb, sb, dt); empty!(wb.events)
        end
        @test wa.entities[:m1].pos === wb.entities[:m1].pos
        @test wa.entities[:m1].vel === wb.entities[:m1].vel
        @test wa.entities[:m1].comp[:pitch_theta] === wb.entities[:m1].comp[:pitch_theta]
        # …and the CEILING readout parks with it (the interior peak degenerates to the clamp value)
        @test wa.env[:telemetry]["m1.a_max_aero"] === wb.env[:telemetry]["m1.a_max_aero"]
    end

    @testset "⭐ INERT WITHOUT ITS HOST — stall needs `:pitch_coupled` (the half-a-missile guard)" begin
        # `_stall_on`'s THIRD CONJUNCT, and a DELIBERATE decision rather than copied boilerplate
        # (advisor): the plan warns that **the moment break reaches FURTHER than ρ(z) did** —
        # `pitch_moment` is live on the `:point_mass` rotational path too (`_integrate_airframe!`),
        # so without this conjunct a `:point_mass` wire would integrate θ/q through a BREAKING moment
        # while pos/vel flew a linear-aero fiat accel. HALF THE MISSILE IN ONE AERODYNAMIC MODEL AND
        # HALF IN ANOTHER — slice 21's `_atm_on` latent bug, exactly. Under `:point_mass` every site
        # reverts together, which is coherent: that plant makes its accel by fiat, so there is no
        # lift ceiling for a stall to lower and nothing for the curve to mean.
        wa, sa = stall_world(alpha_stall = nothing, airframe = :point_mass)
        wb, sb = stall_world(alpha_stall = 0.20, alpha_break = 0.28, cma_post = 8.0,
                             alpha_sat = 0.60, airframe = :point_mass)
        for _ in 1:4000
            tick!(wa, sa, dt); empty!(wa.events)
            tick!(wb, sb, dt); empty!(wb.events)
        end
        # the TRAJECTORY is the tooth, not the predicate — an aggressive break authored and INERT
        @test wa.entities[:m1].pos === wb.entities[:m1].pos
        @test wa.entities[:m1].vel === wb.entities[:m1].vel
        @test wa.entities[:m1].comp[:pitch_theta] === wb.entities[:m1].comp[:pitch_theta]
        # …and the `:point_mass` REFERENCE ARM reports the LINEAR ceiling (advisor): the readout must
        # describe the missile that is actually flying, which is slice 21's ρ₀ coherence reused.
        @test wa.env[:telemetry]["m1.a_max_aero"] === wb.env[:telemetry]["m1.a_max_aero"]
        @test !haskey(wb.env[:telemetry], "m1.post_stall")   # no stall keys where there is no stall
    end

    @testset "⭐ NOT A DEAD KNOB — α_stall MOVES the physics (the arc's signature failure)" begin
        # The slice-19 `speed` trap (a knob consumed ONCE at load and read by NOTHING per tick, which
        # a no-crash test passes happily). This asserts the knob reaches the per-tick physics: the
        # trajectory MUST diverge, and it must diverge in the direction the lesson claims.
        parked = fly_stall(alpha_stall = 5.0, alpha_break = 6.0, alpha_sat = 7.0)
        stalled = fly_stall(alpha_stall = 0.20)
        @test parked.miss != stalled.miss
        @test stalled.miss > parked.miss              # the ceiling fell ⇒ the miss OPENS
        @test stalled.post_stall > 0                  # …and the missile genuinely went post-stall
        @test parked.post_stall == 0                  # while the parked twin never does
        # ⚠ THE ISOLATION (P6, and slice-19 FINDING 2's recurrence): commanding α_max ABOVE α_stall
        # means commanding LARGER α than any prior slice, and `δ_peak ≈ (|Cmα|/Cmδ + k_α)·α_max`
        # scales with it. A δ_max that BOUND would make this "slice 15's deflection cap in a stall
        # costume" — the FOURTH cap masquerading as the lesson.
        @test stalled.defl_sat == 0
        @test parked.defl_sat == 0
    end

    @testset "⭐⭐ THE WIRING *IS* THE GATE-0 PROBE — the table reproduced TO THE DIGIT" begin
        # The slice-21 discipline ("the 16/17/19 verifiers reproduce STATUS to the digit") applied to
        # a gate-0 probe: the whole design rests on numbers measured OUTSIDE the engine, so gate 2's
        # job is not merely "something changed" but "the wired physics is the physics that was
        # probed". Any drift — a curve wired to the wrong α, a coefficient in the wrong term, the
        # stall arm reached at the wrong stage — moves these.
        #
        # ⚠ THIS TOOTH IS WHY `k_drop` DEFAULTS TO 0.7: the probe's operating point. At 1.0 the same
        # engagement misses by 278.11 instead — a 16% shift that would have quietly stranded every
        # number the plan is written around, while every structural test still passed.
        parked = fly_stall(alpha_stall = 5.0, alpha_break = 6.0, alpha_sat = 7.0, k_sep = 0.0)
        stalled = fly_stall(alpha_stall = 0.20, k_sep = 0.0)
        @test parked.miss  ≈ 125.14 atol = 0.01      # F8's linear arm
        @test stalled.miss ≈ 240.37 atol = 0.01      # …and the stall arm (1.92× — the consequence)
        @test parked.ceil0  ≈ 471.44 atol = 0.05     # the ceilings the ⭐ identity is stated on
        @test stalled.ceil0 ≈ 269.39 atol = 0.05
        # ⚠ AND THE PARKING OFF-STATE IS EMPIRICAL, NOT ARGUED (F7 — the knob-vs-rung claim's other
        # half): a FINITE α_stall at 0.25 is linear-in-effect because the achieved α self-limits to
        # ~0.24 over every reachable state. This is the measurement that KILLED the plan's rung
        # justification, so it is pinned rather than recounted.
        for as in (0.25, 0.30, 0.35)
            @test fly_stall(alpha_stall = as, k_sep = 0.0).miss ≈ 125.14 atol = 0.01
        end
        @test parked.α_pk ≈ 0.2412 atol = 0.001      # the self-limit itself
    end

    @testset "⭐ THE CEILING IS THE CURVE'S INTERIOR PEAK — on the wire, not just in the formula" begin
        # The readout must agree with `aero_accel_limit`'s `curve` arm at the state it shipped, or
        # the client's aero strip plots a ceiling the missile does not have (slice 21's
        # readout-vs-integrator discipline).
        r = fly_stall(alpha_stall = 0.20)
        m = r.w.entities[:m1]
        p = AirframeParams(π * 0.1^2, 0.2, 20.0, -1.0, 3.0, -150.0, 1.225, 20.0, 0.0)
        c = AeroCurveParams(0.20, 0.7, 3.0, 1.0e9, 0.0, 2.0e9)
        @test r.tel["m1.a_max_aero"] ≈
              aero_accel_limit(n3(m.vel), 140.0, p; alpha_max = 0.35, curve = c) atol = 1e-9
        # …and it is BELOW the linear ceiling by the headline ratio α_stall/α_max (Q cancels because
        # BOTH sides are evaluated at the SAME shipped V — a same-inputs comparison, not run-vs-run)
        @test r.tel["m1.a_max_aero"] /
              aero_accel_limit(n3(m.vel), 140.0, p; alpha_max = 0.35) ≈ 0.20 / 0.35 atol = 1e-12
    end

    @testset "the stall wire keys — KEY-gated, and the readouts match the integrator" begin
        r = fly_stall(alpha_stall = 0.20, K = 0.05)
        m = r.w.entities[:m1]
        θ = Float64(m.comp[:pitch_theta])
        p = AirframeParams(π * 0.1^2, 0.2, 20.0, -1.0, 3.0, -150.0, 1.225, 20.0, 0.05)
        c = AeroCurveParams(0.20, 0.7, 3.0, 1.0e9, 0.0, 2.0e9)
        @test haskey(r.tel, "m1.post_stall")
        @test haskey(r.tel, "m1.a_sep")
        # every aero readout is the NONLINEAR one — a strip plotting a lift the missile did not make
        # is the readout-vs-integrator bug in another costume
        @test r.tel["m1.a_lift"]    ≈ n3(lift_accel_nl(m.vel, θ, 140.0, p, c)) atol = 1e-9
        @test r.tel["m1.a_induced"] ≈ n3(induced_drag_accel_nl(m.vel, θ, 140.0, p, c)) atol = 1e-9
        @test r.tel["m1.a_sep"]     ≈ n3(separation_drag_accel(m.vel, θ, 140.0, p, c)) atol = 1e-9
        # `post_stall` is a SEPARATELY-NAMED FLAG, deliberately NOT folded into `aero_sat` (plan §1,
        # advisor): `aero_sat` means *the α_max clamp bound*, and under this slice α_max is
        # deliberately NOT the binding limit. Conflating them would make the slice-19 flag lie about
        # which cap is doing the work.
        γ = atan(m.vel[3], m.vel[1])
        @test r.tel["m1.post_stall"] == (abs(θ - γ) ≥ 0.20 ? 1.0 : 0.0)
    end

    @testset "⭐ THE ω_sp SENTINEL FIRES IN FLIGHT — first time in project history (F11, P3c)" begin
        # Slice 16 built the `ω² < 0 ⇒ NaN` guard for an AUTHORED `Cmα ≥ 0`; it has NEVER fired
        # mid-run. With a real moment break the airframe FLIES ITSELF into the unstable regime and
        # the sentinel fires DYNAMICALLY — the readout that says *there is no longer an oscillation
        # to have*. ⚠ CONVENTION 6: it must reach the wire as FINITE_CEIL, never a NaN (a NaN in the
        # JSON drops the connection). This walks that path with a departure in progress.
        broke = fly_stall(alpha_stall = 0.20, alpha_break = 0.28, cma_post = 8.0, alpha_sat = 0.60)
        @test broke.ω_ceiled > 0                        # the sentinel FIRED, mid-flight
        @test isfinite(broke.tel["m1.omega_sp"])        # …and the wire stayed finite throughout
        @test isfinite(broke.tel["m1.alpha_trim"])
        @test broke.α_pk > 0.28                         # the airframe reached the break by itself
        # a LINEAR moment (no break authored) cannot depart — the sentinel stays silent, and slices
        # 16–21's wires keep that behaviour (the slice-21 "no global find/replace" precedent)
        lin = fly_stall(alpha_stall = 0.20)
        @test lin.ω_ceiled == 0
    end

    @testset "⭐ THE STAGE-θ GOLDEN — the ONLY thing that catches an entry-θ read in the STALL arm" begin
        # THE SLICE-17 STAGE-θ TRAP, THIRD OCCURRENCE (17 = θ, 21 = z, 22 = θ again in a NEW
        # closure). ⚠ **SLICE 17'S GOLDEN DOES NOT COVER THIS ONE** (advisor): the stall arm is a
        # SEPARATE CLOSURE BODY, so slice 17's golden — which exercises the `curve === nothing`
        # else-arm — never touches these four terms. And this closure has MORE stage-dependent
        # terms than any before it: lift, induced drag, the moment, AND the brand-new separation
        # drag, all functions of the stage α = TH − γ.
        #
        # Slice 17's own finding is why nothing else can catch it: an entry-θ read compiles clean,
        # is only O(dt²) off per step, and is invisible to steady-state tests. Everything else in
        # this testset IS steady-state (miss, ceiling, counts), so relying on the `240.37 ± 0.01`
        # tooth would be luck-of-the-tolerance rather than design.
        #
        # Generated from the LIVE `tick!` path at 5000 ticks (5 s — well post-stall: |α| = 0.259 >
        # α_stall, `post_stall` lit and `a_sep` non-zero, so the new term is genuinely loaded).
        # THE MARGIN IS THE TOOTH (convention 11 — an atol that cannot fail is a tautology): the
        # entry-θ variant, MEASURED at this exact tick by patching the closure and re-running, sits
        #   Δpos_x = 4.321e-3 m, Δpos_z = 5.177e-2 m, Δθ = 2.434e-6 rad, Δq = 3.948e-5 rad/s
        # away — so atol 1e-6 on position catches it with a ~5e4× margin and atol 1e-9 on θ with
        # ~2400×. If someone "simplifies" the stage read to the entry θ, these fail loudly.
        w, s = stall_world(alpha_stall = 0.20, K = 0.05)
        for _ in 1:5000; tick!(w, s, dt); empty!(w.events); end
        m = w.entities[:m1]
        @test isapprox(m.pos[1], 3119.185660380272;            atol = 1e-6)
        @test isapprox(m.pos[3], 3472.784157867183;            atol = 1e-6)
        @test isapprox(m.comp[:pitch_theta], -0.645537288442;  atol = 1e-9)
        @test isapprox(m.comp[:pitch_q],     -0.400928895281;  atol = 1e-9)
        # the golden point is only a golden for THIS slice if the stall physics is actually live
        # there — pin that too, so a future config change cannot quietly move it below the corner
        @test w.env[:telemetry]["m1.post_stall"] == 1.0
        @test w.env[:telemetry]["m1.a_sep"] > 0.0
    end

    @testset "loader — the stall keys are PRESENCE-gated, validated, and knob-addressable" begin
        mktempdir() do dir
            AF = "{inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0, cmq: -150.0, cla: 20.0, " *
                 "alpha_max: 0.35, alpha_stall: 0.20}"
            base = """
            name: s22
            seed: 22
            fidelity: {airframe: pitch_coupled, guidance: pn, autopilot: alpha}
            entities:
              - id: m1
                kind: missile
                pos: [0.0, 0.0, 3000.0]
                missile:
                  mass_kg: 140.0
                  speed: 700.0
                  elevation_deg: 12.0
                  guidance: {n_pn: 4.0, a_max: 3000.0, delta_max: 0.4}
                  airframe: $AF
              - id: t1
                kind: target
                pos: [6000.0, 0.0, 4200.0]
                vel: [-800.0, 0.0, 200.0]
                target: {rcs_m2: 1.0, maneuver: {a_lat_mps2: 200.0}}
            """
            mk(af) = begin
                p = joinpath(dir, "s22_$(hash(af)).yaml")
                write(p, replace(base, AF => af)); p
            end
            # ⚠ THE FIXTURE MUST LOAD CLEAN FIRST — otherwise every `@test_throws` below passes for
            # free on an unrelated error (the slice-19 "a test that malforms its own fixture proves
            # nothing" trap, which slice 20 hit live).
            @test load_scenario(mk(AF)).world.entities[:m1].comp[:af_alpha_stall] == 0.20
            # PRESENCE: no `alpha_stall` ⇒ no key at all (slices 16–21 stay byte-identical). This is
            # LOAD-BEARING: those slices ALL carry airframe blocks, so gating on the BLOCK rather
            # than the KEY would grow the key on every one of them.
            @test !haskey(load_scenario(mk("{cma: -1.0, cmd: 3.0, cla: 20.0}")
                                        ).world.entities[:m1].comp, :af_alpha_stall)
            # …and authoring it brings the whole shape, with the documented defaults
            c = load_scenario(mk(AF)).world.entities[:m1].comp
            @test c[:af_alpha_stall] == 0.20
            # 0.7 is GATE 0's operating point, not a round number: the shipped default is what makes
            # the wiring reproduce the probe's table to the digit (see the reproduction tooth above).
            # `_stall_params`' default must match it — pinned here because a drift between the two
            # would be silent (the loader default only applies to YAML-built worlds).
            @test c[:af_k_drop] == 0.7 && c[:af_k_sep] == 0.0
            # ⚠ THE DEFAULTS PARK THE BREAK OUT OF REACH — authoring `alpha_stall` ALONE gives the
            # LIFT lesson with a LINEAR moment and NO departure. The two lessons are separately
            # authorable, which is what keeps convention 9 satisfiable in one scenario file.
            @test c[:af_alpha_break] > 100.0 && c[:af_cma_post] == 0.0
            @test c[:af_alpha_sat] > c[:af_alpha_break]
            # SIGNS + the domain invariants (convention 5's validate-at-LOAD half)
            @test_throws ErrorException load_scenario(mk("{cla: 20.0, alpha_stall: 0.0}"))
            @test_throws ErrorException load_scenario(mk("{cla: 20.0, alpha_stall: -0.2}"))
            @test_throws ErrorException load_scenario(mk("{cla: 20.0, alpha_stall: 0.2, k_drop: -0.5}"))
            @test_throws ErrorException load_scenario(mk("{cla: 20.0, alpha_stall: 0.2, k_sep: -1.0}"))
            # ⚠ THE DEEP-STALL BOUND IS A LOAD INVARIANT, NOT A SUGGESTION (F9): without a restoring
            # slope above the break the divergence is UNBOUNDED (α ran to 383497 rad in the probe) —
            # a convention-6 crash path AND an epistemic one, since it makes a genuine tumble
            # indistinguishable from a bug.
            @test_throws ErrorException load_scenario(
                mk("{cla: 20.0, alpha_stall: 0.2, alpha_break: 0.6, alpha_sat: 0.3}"))
            # ⚠ ONE LESSON PER SCENARIO, ENFORCED AT LOAD (convention 9; advisor). The stall arm
            # LEADS `_integrate_coupled!`'s branch chain, so a missile authoring BOTH stall and a
            # scale height would silently fly a constant-ρ stall and its ρ(z) would vanish without a
            # word — the slice-21 `_atm_on` latent-bug class. Refuse the pairing instead of letting
            # branch order decide it.
            @test_throws ErrorException load_scenario(
                mk("{cla: 20.0, alpha_stall: 0.2, scale_height_m: 8500.0}"))
            # …and the two LESSON SLIDERS address real comp keys (the mechanism that would have
            # caught slice-19's DEAD `speed` knob had `speed` been live)
            brk = "{inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0, cmq: -150.0, cla: 20.0, " *
                  "alpha_max: 0.35, alpha_stall: 0.20, alpha_break: 0.28, cma_post: 8.0, " *
                  "alpha_sat: 0.60}"
            p = joinpath(dir, "s22_knob.yaml")
            write(p, replace(base, AF => brk) * """
            knobs:
              - {target: m1, key: af_alpha_stall, min: 0.15, max: 0.35, label: "α_stall"}
              - {target: m1, key: af_cma_post, min: 0.0, max: 8.0, label: "Cmα post"}
            """)
            sc = load_scenario(p)
            @test length(sc.knobs) == 2
            @test sc.knobs[1].key === :af_alpha_stall
            @test sc.knobs[2].key === :af_cma_post
        end
    end
end

# --- gate 2: the 6-DOF SUBSTRATE + SKID-TO-TURN wired (slice 23, §11 Tier A) -------------------
# The 3-D superset. `:airframe === :six_dof` reaches `_integrate_6dof!` (the `_integrate_coupled!`
# sibling): `att` is a GENUINE quaternion integrated from a body-rate vector, lift is 2-plane
# (α pitch + β yaw), and the `:alpha` autopilot's `:six_dof` arm inverts the FULL 3-D guidance
# command onto both body ⟂-v axes — the projection-and-throw-away DIES. THE LESSON: against a
# target OFF the x-z plane the `:pitch_coupled` plant discards the y-command and misses ≈ Y (it
# never leaves x-z), while `:six_dof` STT turns to it and intercepts. Class 4c (no RNG — truth-fed
# PN, no seeker ⇒ "draw-count invariance" is VACUOUS). Slices 8–22 are byte-identical (they never
# set `:six_dof`, never mint `:att_q`). Goldens from the LIVE tick! path (temp/slice23_g2_*.jl).
@testset "6-DOF substrate + skid-to-turn wired (slice 23, :airframe === :six_dof)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # THE OUT-OF-PLANE ENGAGEMENT (gate-0 route (a)): the slice-19 airframe, an `:alpha`+`:pn`
    # missile launched IN the x-z plane, chasing a STATIC aero-free target at cross-range +Y. A low
    # authored ρ (0.3) exercises the yaw authority VISIBLY (gate-0 P2b). The 6-DOF-only constants
    # (cy_beta, I_roll, I_zz, c_roll) are authored here; they ALSO default at the consumer (the
    # live-toggle path below proves that). `af_delta = 0` ⇒ tick 1 (integrates before the first
    # decide! writes the δ seam) injects no transient.
    function owp_world(; airframe = :six_dof, Y = 2000.0, rho = 0.3, alpha_max = 0.3,
                         guided = true, af6 = true)
        w = World(seed = 23, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                            :autopilot => :alpha, :airframe => airframe))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => rho,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max,
                                :n_pn => 4.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt)
        if af6                                             # the 6-DOF constants (else: consumer defaults)
            comp[:af_cy_beta] = 20.0; comp[:af_I_roll] = 2.0
            comp[:af_I_zz]    = 20.0; comp[:af_c_roll]  = 50.0
        end
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, Y, 4200.0),
                                 vel = zero(Vec3), comp = Dict{Symbol,Any}())
        subs = guided ? Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:t1)] :
                        Subsystem[BallisticMissile(:m1), ConstantVelocity(:t1)]
        return w, subs
    end

    # First-CPA over the FIRST DESCENDING band ([[ewsim-missile-verifier-sampling]]); the miss IS
    # the cross-range for the discard arm (a static x-z-plane target ⇒ min approach ≥ Y).
    function fly(; T = 25.0, kw...)
        w, s = owp_world(; kw...)
        rmin, prev, closing = Inf, Inf, true
        maxposy = 0.0; β_peak = 0.0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            m = w.entities[:m1]
            r = n3(w.entities[:t1].pos - m.pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            maxposy = max(maxposy, abs(m.pos[2]))
            β_peak  = max(β_peak, abs(get(w.env[:telemetry], "m1.beta_cmd", 0.0)))
            !closing && break
        end
        return (miss = rmin, maxposy = maxposy, β_peak = β_peak, w = w)
    end

    # THE REDUCTION HARNESS — IN-PLANE (Y = 0), full-ρ, a MANEUVERING target so α stays nonzero and
    # the two integration SCHEMES (quaternion-RK4 vs scalar-θ-RK4) are actually EXERCISED (a static
    # low-ρ target barely maneuvers ⇒ the schemes coincide to 0.0, which cannot verify the shrink).
    function inplane_world(airframe, dtx)
        w = World(seed = 23, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                            :autopilot => :alpha, :airframe => airframe))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.2, :af_cy_beta => 20.0, :af_I_roll => 2.0,
                                :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 4.0, :a_max => 3000.0, :delta_max => 0.4,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dtx)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 0.0, 4200.0),
                                 vel = Vec3(-800.0, 0.0, 200.0),
                                 comp = Dict{Symbol,Any}(:a_lat_mps2 => 200.0, :turn_sign => 1.0))
        subs = Subsystem[BallisticMissile(:m1), Autopilot(:m1), ManeuveringTarget(:t1)]
        return w, subs
    end
    function reduction_div(dtx, T)
        wc, sc = inplane_world(:pitch_coupled, dtx)
        w6, s6 = inplane_world(:six_dof, dtx)
        d = 0.0
        for _ in 1:round(Int, T / dtx)
            tick!(wc, sc, dtx); empty!(wc.events)
            tick!(w6, s6, dtx); empty!(w6.events)
            d = max(d, n3(wc.entities[:m1].pos - w6.entities[:m1].pos))
        end
        return d
    end

    @testset "transient GOLDEN — the closed-loop 6-DOF wiring (the plausible-but-wrong catch)" begin
        # Cheap insurance against a subtly-wrong-but-plausible wiring (a swapped ω sign, an
        # entry-vs-stage quaternion read, a pitch/yaw moment-negation slip — airframe3d.jl's #1-sign-
        # trap surface). 2000 ticks into the closed out-of-plane loop, pins the FULL joint state.
        w, s = owp_world()
        for _ in 1:2000; tick!(w, s, dt); empty!(w.events); end
        m = w.entities[:m1]
        @test isapprox(m.pos[1], 1361.7751717943997;  atol = 1e-6)
        @test isapprox(m.pos[2],  121.96186302912966; atol = 1e-6)   # off the x-z plane (the discard died)
        @test isapprox(m.pos[3], 3270.0786453445403;  atol = 1e-6)
        @test isapprox(m.comp[:att_q][1],  0.9764647214745897;    atol = 1e-9)
        @test isapprox(m.comp[:att_q][3], -0.09727277259587536;   atol = 1e-9)
        @test isapprox(m.comp[:att_q][4],  0.19147642968436993;   atol = 1e-9)
        @test isapprox(m.comp[:omega_body][3], 0.057752395670428475; atol = 1e-9)  # yaw rate
        @test isapprox(m.comp[:delta_cmd],     0.004740346051662927;  atol = 1e-9)
        @test isapprox(m.comp[:delta_yaw_cmd], 0.06624098196440556;   atol = 1e-9)  # the 2nd fin channel
    end

    @testset "THE REDUCTION — in-plane 6-DOF ≈ scalar pitch_coupled, and it SHRINKS with dt" begin
        # The reduction is an atol golden, NOT `==` (plan §1): quaternion-RK4 and scalar-θ-RK4 are
        # DIFFERENT SCHEMES for the same ODE. THE WIRING-BUG DETECTOR (advisor): the divergence must
        # SHRINK as dt falls. A floor that does NOT shrink is a constant sign/stage/init offset — a
        # bug — not legitimate scheme difference. Measured: 4.46e-11 (dt=2e-3) → 2.14e-12 (dt=1e-3).
        d1 = reduction_div(1.0e-3, 3.0)
        d2 = reduction_div(2.0e-3, 3.0)
        @test d1 < 1.0e-8                          # the reduction holds TIGHT over a full 3 s engagement
        @test d2 / d1 > 5.0                        # …and shrinks with dt (measured ~20.8×) ⇒ correct wiring
    end

    @testset "P1a STRUCTURAL INVARIANT — an in-plane 6-DOF run keeps out-of-plane states at 0" begin
        # The #1 SIGN TRAP's fifth-occurrence gate (gate-0 P1a): with v_y = 0, target in-plane, roll
        # = 0, the out-of-plane states (roll rate p, yaw rate r, sideslip β, cross-range y) can only
        # move if a body↔inertial `rotate` direction or an ω sign is wrong. Gate-0 measured them at
        # EXACTLY 0.0; the wired path must too.
        w, s = owp_world(Y = 0.0)
        mp = 0.0; mr = 0.0; mβ = 0.0; my = 0.0
        for _ in 1:6000
            tick!(w, s, dt); empty!(w.events)
            tel = w.env[:telemetry]
            mp = max(mp, abs(get(tel, "m1.omega_p", 0.0)))
            mr = max(mr, abs(get(tel, "m1.omega_r", 0.0)))
            mβ = max(mβ, abs(get(tel, "m1.beta", 0.0)))
            my = max(my, abs(w.entities[:m1].pos[2]))
        end
        @test mp == 0.0 && mr == 0.0 && mβ == 0.0 && my == 0.0
    end

    @testset "THE LESSON — :pitch_coupled MISSES ≈ Y (discard), :six_dof HITS (the discard dies)" begin
        # The SAME PN law, the SAME target off the x-z plane — only the plant differs. `:pitch_coupled`
        # projects the command onto n̂ = (−sinγ,0,cosγ) and THROWS AWAY the y-part: it never leaves the
        # x-z plane (max|pos_y| = 0 EXACTLY ⇒ miss ≥ Y, a clean first-CPA), so miss ≈ Y. `:six_dof`
        # keeps the full 3-D command and steers in two body planes to intercept. Pinned BOTH ways.
        c = fly(airframe = :pitch_coupled)
        s = fly(airframe = :six_dof)
        @test c.maxposy == 0.0                                    # the y-command is FULLY discarded
        @test isapprox(c.miss, 2002.366251115639; atol = 1e-6)   # ≈ Y (the out-of-plane miss)
        @test isapprox(s.miss, 0.23039260577585177; atol = 1e-6) # the STT intercept
        @test s.maxposy > 1990.0                                  # …it TURNED to the cross-range target
        @test c.miss / s.miss > 1000.0                            # ~8700× separation
        @test s.β_peak > 0.1                                      # the yaw channel was genuinely exercised
    end

    @testset "determinism — a 6-DOF missile replays bit-identical (class 4c, no RNG)" begin
        function trace()
            w, s = owp_world()
            ps = Vec3[]
            for _ in 1:1500; tick!(w, s, dt); empty!(w.events); push!(ps, w.entities[:m1].pos); end
            ps
        end
        @test trace() == trace()                                  # bit-for-bit (reinterpret-equal)
    end

    @testset "THE :a_ctrl TRIPWIRE — a pure 6-DOF run NEVER grows the key (finding 1, 6-DOF)" begin
        # The 6-DOF plant makes its accel from 2-plane LIFT; `_integrate_6dof!` reads the δ seam, NEVER
        # `:a_ctrl`. Persisting it would rebuild the point-mass plant in a costume (the false-fidelity
        # trap). It flies TWO fin channels, so BOTH δ keys must exist and `:a_ctrl` must not.
        s = fly(airframe = :six_dof)
        @test !haskey(s.w.entities[:m1].comp, :a_ctrl)
        @test haskey(s.w.entities[:m1].comp, :delta_cmd)
        @test haskey(s.w.entities[:m1].comp, :delta_yaw_cmd)     # the 2nd channel
    end

    @testset "INERT without airframe params (P8) — bare :six_dof ≡ :point_mass byte-identical" begin
        # `_integrate_6dof!` is gated on `haskey(:af_cma)`, so a bare missile under `:six_dof` falls to
        # the point-mass path, mints NO `:att_q`/`:omega_body`, and is bit-for-bit the `:point_mass`
        # twin (never a KeyError). The params-presence gate, the `_integrate_coupled!` precedent.
        function bare(airframe)
            w = World(seed = 1, fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :airframe => airframe))
            w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 1000.0),
                                     vel = Vec3(300.0, 0.0, 100.0),
                                     comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.02, :rho => 1.225))
            s = Subsystem[BallisticMissile(:m1)]
            for _ in 1:500; tick!(w, s, dt); empty!(w.events); end
            w.entities[:m1]
        end
        b6 = bare(:six_dof); bp = bare(:point_mass)
        @test b6.pos == bp.pos && b6.vel == bp.vel               # bit-identical to the point-mass twin
        @test !haskey(b6.comp, :att_q) && !haskey(b6.comp, :omega_body)  # no 3-D state minted
    end

    @testset "LIVE-TOGGLE crash safety — a scenario w/o 6-DOF params toggled to :six_dof mid-run" begin
        # `:airframe` is live-settable with NO set_fidelity guard (4c), so a slice-19..22 scenario that
        # never authored cy_beta/I_roll/I_zz/c_roll can be flipped to `:six_dof` at runtime. The
        # consumer defaults (`get(c, :af_…, default)`) must keep the tick crash-free (convention 5).
        w, s = owp_world(af6 = false)                            # airframe params present, 6-DOF ones ABSENT
        for _ in 1:500; tick!(w, s, dt); empty!(w.events); end   # runs already on :six_dof via defaults
        m = w.entities[:m1]
        @test all(isfinite, m.pos) && all(isfinite, m.vel)
        @test all(isfinite, m.comp[:att_q]) && all(isfinite, m.comp[:omega_body])
    end

    @testset "LIVE CROSS-TOGGLE — no STALE readout survives the :airframe cycle (the _atm_on class)" begin
        # The 3-rung `:airframe` button is the whole A/B, so a six_dof↔pitch_coupled cross-toggle IS a
        # showcase path. `:att_q`/`:pitch_theta` are never deleted, so WITHOUT the rung-gate on the two
        # build_env! blocks the stale block would fire on a frozen attitude and overwrite the fresh
        # readout (advisor — the slice-21 `_atm_on` latent-bug class). Both directions must be clean.
        sixk = ("m1.pos_y", "m1.beta", "m1.omega_p", "m1.att_qw", "m1.att_qz", "m1.delta_yaw")
        pitk = ("m1.pitch_theta", "m1.omega_sp", "m1.alpha_trim")
        # six_dof → pitch_coupled: the 6-DOF-only keys must be GONE, the scalar keys present.
        w, s = owp_world(airframe = :six_dof)
        for _ in 1:400; tick!(w, s, dt); empty!(w.events); end
        w.fidelity[:airframe] = :pitch_coupled
        for _ in 1:5; tick!(w, s, dt); empty!(w.events); end
        t = w.env[:telemetry]
        for k in sixk; @test !haskey(t, k); end                 # no stale 6-DOF key on the scalar wire
        @test haskey(t, "m1.pitch_theta") && isfinite(t["m1.alpha"])   # the fresh scalar readout stands
        # pitch_coupled → six_dof: the pitch-only keys must be GONE, the 3-D keys present.
        w2, s2 = owp_world(airframe = :pitch_coupled)
        for _ in 1:400; tick!(w2, s2, dt); empty!(w2.events); end
        w2.fidelity[:airframe] = :six_dof
        for _ in 1:5; tick!(w2, s2, dt); empty!(w2.events); end
        t2 = w2.env[:telemetry]
        for k in pitk; @test !haskey(t2, k); end                # no stale pitch-only key on the 6-DOF wire
        @test haskey(t2, "m1.att_qw") && haskey(t2, "m1.beta")  # the fresh 3-D readout stands
    end

    @testset "gated wire — a :six_dof missile ships the 3-D keys; :pitch_coupled ships NONE of them" begin
        # Byte-identity: the 6-DOF readouts (pos_y, beta, omega_*, att_q*, delta_yaw) key off `:att_q`
        # / `sixdof_diag`, minted ONLY by the 6-DOF path — so a slice-19..22 `:pitch_coupled` wire
        # NEVER grows them, and a `:six_dof` wire NEVER grows `:pitch_theta` (mutually exclusive).
        w6, s6 = owp_world(airframe = :six_dof)
        for _ in 1:1500; tick!(w6, s6, dt); empty!(w6.events); end
        t6 = w6.env[:telemetry]
        for k in ("m1.pos_y", "m1.beta", "m1.beta_cmd", "m1.omega_p", "m1.omega_q", "m1.omega_r",
                  "m1.att_qw", "m1.att_qx", "m1.att_qy", "m1.att_qz", "m1.delta_yaw", "m1.a_lift")
            @test haskey(t6, k) && t6[k] isa Float64 && isfinite(t6[k])   # SCALARS (convention 13)
        end
        @test !haskey(t6, "m1.pitch_theta")                     # the scalar pitch key is NOT minted
        wc, sc = owp_world(airframe = :pitch_coupled)
        for _ in 1:1500; tick!(wc, sc, dt); empty!(wc.events); end
        tc = wc.env[:telemetry]
        for k in ("m1.pos_y", "m1.beta", "m1.beta_cmd", "m1.omega_p", "m1.att_qw", "m1.delta_yaw")
            @test !haskey(tc, k)                                 # a pitch_coupled wire has NONE of them
        end
    end

    @testset "loader — the 6-DOF airframe keys parse to comp + reject bad values" begin
        base = """
        name: s23
        seed: 23
        dt_physics: 0.001
        fidelity: {airframe: six_dof, guidance: pn, autopilot: alpha}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {n_pn: 4.0}
              airframe:
                inertia_kgm2: 20.0
                cma: -1.0
                cmd: 3.0
                cla: 20.0
                alpha_max: 0.3
                cy_beta: 18.0
                inertia_roll_kgm2: 2.0
                inertia_yaw_kgm2: 21.0
                c_roll: 50.0
          - id: t1
            kind: target
            pos: [6000.0, 2000.0, 4200.0]
            vel: [0.0, 0.0, 0.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            c = scn.world.entities[:m1].comp
            @test scn.world.fidelity[:airframe] === :six_dof     # the NEW rung validates through the wire
            @test c[:af_cy_beta] == 18.0
            @test c[:af_I_roll]  == 2.0
            @test c[:af_I_zz]    == 21.0
            @test c[:af_c_roll]  == 50.0
            # the 6-DOF keys DEFAULT when omitted (a live `:airframe` toggle of a scenario that never
            # authored them can't KeyError a tick — convention 5, the consumer-default half).
            nod = join([l for l in split(base, '\n')
                        if !any(occursin(k, l) for k in ("cy_beta", "inertia_roll_kgm2",
                                                         "inertia_yaw_kgm2", "c_roll"))], '\n')
            pd = joinpath(dir, "def.yaml"); write(pd, nod)
            @test !haskey(load_scenario(pd).world.entities[:m1].comp, :af_cy_beta)   # absent ⇒ consumer default
            # REJECTS (each authored input LOAD-validated — convention 5): I_roll ≤ 0, I_zz ≤ 0, a
            # negative (anti-damping) roll damper, a non-finite yaw slope.
            for (from, to) in (("inertia_roll_kgm2: 2.0" => "inertia_roll_kgm2: 0.0"),
                               ("inertia_yaw_kgm2: 21.0" => "inertia_yaw_kgm2: -5.0"),
                               ("c_roll: 50.0"           => "c_roll: -1.0"),
                               ("cy_beta: 18.0"          => "cy_beta: .inf"))
                pb = joinpath(dir, "bad.yaml"); write(pb, replace(base, from => to))
                @test_throws ErrorException load_scenario(pb)
            end
        end
    end
end

# --- gate 2: BANK-TO-TURN + roll-lag wired (slice 24, §11 Tier A) -------------------------------
# The `:steering = (:skid_to_turn, :bank_to_turn)` rung on the HELD `:six_dof` plant. `:bank_to_turn`
# swaps the STT roll damper for the τ_roll bank autopilot (airframe3d.jl `btt_moments`) and the decide
# arm for `steering_bank_command` (single-plane α + a bank command, β→0). Against the SAME static
# out-of-plane target STT hits, BTT MISSES (it must roll ~90° to point its lift cross-range, and the
# roll lags). `:steering` is INERT without `:airframe:six_dof`; default `:skid_to_turn` ⇒ slice 23
# byte-frozen. Class 4c. Goldens from the LIVE tick! path (temp/slice24_gate0/wire_measure.jl).
@testset "bank-to-turn + roll-lag wired (slice 24, :steering === :bank_to_turn)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # The slice-24 world — the slice-23 owp geometry + `:steering` + `:af_tau_roll`. `steering = nothing`
    # ⇒ NO `:steering` key in fidelity (the byte-identity default proof); a Symbol ⇒ set it.
    function btt_world(; steering = :bank_to_turn, τ_roll = 1.0, Y = 2000.0, airframe = :six_dof)
        fid = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                  :autopilot => :alpha, :airframe => airframe)
        steering !== nothing && (fid[:steering] = steering)
        w = World(seed = 24, fidelity = fid)
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 0.3,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.3, :af_cy_beta => 20.0, :af_I_roll => 2.0,
                                :af_I_zz => 20.0, :af_c_roll => 50.0, :af_tau_roll => τ_roll,
                                :n_pn => 4.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, Y, 4200.0),
                                 vel = zero(Vec3), comp = Dict{Symbol,Any}())
        return w, Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end
    function fly(; T = 25.0, kw...)
        w, s = btt_world(; kw...)
        rmin, prev, closing = Inf, Inf, true; maxy = 0.0; bank_pk = 0.0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            m = w.entities[:m1]; r = n3(w.entities[:t1].pos - m.pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            maxy = max(maxy, abs(m.pos[2]))
            bank_pk = max(bank_pk, abs(get(w.env[:telemetry], "m1.bank_deg", 0.0)))
            !closing && break
        end
        return (miss = rmin, maxy = maxy, bank_pk = bank_pk, w = w)
    end

    @testset "BYTE-IDENTITY — default (no :steering key) ≡ :skid_to_turn ≡ slice-23 :six_dof" begin
        # The default is `:skid_to_turn` (plan §1), so a world with NO `:steering` key and one that
        # sets it EXPLICITLY to `:skid_to_turn` must be bit-for-bit identical, AND both must reproduce
        # slice 23's STT miss EXACTLY — the master additive check (the STT path is textually verbatim).
        function trace(steering)
            w, s = btt_world(; steering = steering); ps = Vec3[]
            for _ in 1:1500; tick!(w, s, dt); empty!(w.events); push!(ps, w.entities[:m1].pos); end
            ps
        end
        @test trace(nothing) == trace(:skid_to_turn)             # the default is byte-safe
        st = fly(steering = :skid_to_turn)
        @test isapprox(st.miss, 0.23039260577585177; atol = 1e-9)  # === slice-23's :six_dof STT miss
    end

    @testset "THE LESSON — :bank_to_turn MISSES (roll lag), :skid_to_turn HITS" begin
        # The SAME PN law, the SAME target off the x-z plane, the SAME 6-DOF plant — only the STEERING
        # law differs. STT points lift in two planes at once → intercept. BTT (τ_roll = 1.0) launches
        # wings-level and must roll ~90° to point its single lift plane cross-range; the roll lags, so it
        # is still pointing lift the OLD way for a large part of the flight → miss ~372 m. It DOES turn
        # (maxy well past 0 — not the pitch-plane discard), just LATE.
        b = fly(steering = :bank_to_turn, τ_roll = 1.0)
        s = fly(steering = :skid_to_turn)
        @test isapprox(b.miss, 371.7948191626971;  atol = 1e-6)  # the roll-lag miss (live-wire golden)
        @test isapprox(s.miss, 0.23039260577585177; atol = 1e-6) # the STT intercept
        @test b.miss / s.miss > 1000.0                           # ~1600× separation
        @test b.maxy > 1500.0                                    # BTT TURNED (late) — not the ≈0 discard
    end

    @testset "τ_roll → 0 RECOVERS STT (the CAUSATION lever); large τ_roll SATURATES toward Y" begin
        # The miss is caused by the roll LAG: remove the lag (τ_roll → 0, instant bank) and BTT recovers
        # the STT hit (gate-0 PROBE B). Dial τ_roll up and the roll is too sluggish to point lift in time
        # — the miss saturates toward the pitch-plane DISCARD (≈ Y = 2000 m), NO reversal (PROBE G).
        fast = fly(steering = :bank_to_turn, τ_roll = 0.01)
        slow = fly(steering = :bank_to_turn, τ_roll = 2.0)
        @test isapprox(fast.miss, 0.13295162494180615; atol = 1e-6)  # instant roll ≈ STT (causation)
        @test fast.miss < 1.0                                        # recovered the hit
        @test isapprox(slow.miss, 1535.4860854585859; atol = 1e-6)   # saturating toward Y = 2000
        @test slow.miss > fly(steering=:bank_to_turn, τ_roll=1.0).miss  # monotone in τ_roll (no reversal)
    end

    @testset "IN-PLANE INVARIANT under :bank_to_turn — Y=0 ⇒ no roll, no drift (#1 sign trap 6th)" begin
        # The bank/α sign pair (airframe3d.jl): an in-plane target needs NO bank, so BTT must keep the
        # bank ≡ 0, the roll rate p ≡ 0, and never leave the x-z plane. A flipped sign would induce a
        # spurious roll. Gate-0 PROBE F measured them at EXACTLY 0.0.
        w, s = btt_world(steering = :bank_to_turn, Y = 0.0)
        mp = 0.0; my = 0.0; mbank = 0.0
        for _ in 1:6000
            tick!(w, s, dt); empty!(w.events); tel = w.env[:telemetry]
            mp = max(mp, abs(get(tel, "m1.omega_p", 0.0)))
            mbank = max(mbank, abs(get(tel, "m1.bank_deg", 0.0)))
            my = max(my, abs(w.entities[:m1].pos[2]))
        end
        @test mp == 0.0 && my == 0.0 && mbank == 0.0
    end

    @testset "transient GOLDEN — the closed-loop BTT wiring (the plausible-but-wrong catch)" begin
        # 2000 ticks into the closed out-of-plane BTT loop — pins the FULL joint state + the bank seam
        # (a swapped roll-moment sign, a stale φ_cmd, an entry-vs-stage read would move these).
        w, s = btt_world(steering = :bank_to_turn)
        for _ in 1:2000; tick!(w, s, dt); empty!(w.events); end
        m = w.entities[:m1]
        @test isapprox(m.pos[1], 1385.3290466659; atol = 1e-6)
        @test isapprox(m.pos[2],   32.0823302655; atol = 1e-6)
        @test isapprox(m.pos[3], 3146.3104297288; atol = 1e-6)
        @test isapprox(m.comp[:att_q][1],  0.843799662995; atol = 1e-9)
        @test isapprox(m.comp[:omega_body][1], 0.600555650922; atol = 1e-9)  # roll rate (BTT banks!)
        @test isapprox(m.comp[:phi_cmd],       2.179253044118; atol = 1e-9)  # the bank command seam
        @test isapprox(m.comp[:delta_yaw_cmd], -0.009269785031; atol = 1e-9)
    end

    @testset "gated wire — :bank_to_turn ships bank_deg/phi_cmd; :skid_to_turn ships NEITHER" begin
        # The bank readouts key off `:steering === :bank_to_turn` (RUNG-gated, the slice-23 precedent),
        # so a slice-16..23 / STT wire is byte-identical (never grows them).
        wb, sb = btt_world(steering = :bank_to_turn)
        for _ in 1:800; tick!(wb, sb, dt); empty!(wb.events); end
        tb = wb.env[:telemetry]
        @test haskey(tb, "m1.bank_deg") && tb["m1.bank_deg"] isa Float64 && isfinite(tb["m1.bank_deg"])
        @test haskey(tb, "m1.phi_cmd")  && tb["m1.phi_cmd"] isa Float64
        ws, ss = btt_world(steering = :skid_to_turn)
        for _ in 1:800; tick!(ws, ss, dt); empty!(ws.events); end
        ts = ws.env[:telemetry]
        @test !haskey(ts, "m1.bank_deg") && !haskey(ts, "m1.phi_cmd")   # STT wire has NEITHER
        @test haskey(ts, "m1.beta_cmd")                                 # …but keeps the six_dof yaw keys
    end

    @testset "LIVE CROSS-TOGGLE — no STALE bank readout survives the :steering cycle" begin
        # `:phi_cmd` is minted by the BTT decide arm and never deleted; without the RUNG-gate the
        # bank_deg/phi_cmd block would keep firing on the STT wire after a bank_to_turn→skid_to_turn
        # toggle (the slice-21 `_atm_on` latent-bug class). `w.env` is emptied each tick ⇒ the rung-gate
        # is a complete fix. Both directions clean.
        wb, sb = btt_world(steering = :bank_to_turn)
        for _ in 1:400; tick!(wb, sb, dt); empty!(wb.events); end
        wb.fidelity[:steering] = :skid_to_turn
        for _ in 1:5; tick!(wb, sb, dt); empty!(wb.events); end
        tb = wb.env[:telemetry]
        @test !haskey(tb, "m1.bank_deg") && !haskey(tb, "m1.phi_cmd")   # no stale bank key on the STT wire
        @test haskey(tb, "m1.beta_cmd")                                 # the fresh STT readout stands
        ws, ss = btt_world(steering = :skid_to_turn)
        for _ in 1:400; tick!(ws, ss, dt); empty!(ws.events); end
        ws.fidelity[:steering] = :bank_to_turn
        for _ in 1:5; tick!(ws, ss, dt); empty!(ws.events); end
        @test haskey(ws.env[:telemetry], "m1.bank_deg")                 # the fresh bank readout appears
    end

    @testset "INERT without :six_dof — :bank_to_turn on :pitch_coupled ≡ :skid_to_turn (no roll DOF)" begin
        # The cross-fidelity dependency (plan §1): `:steering` reaches a branch ONLY on the 6-DOF path.
        # On `:pitch_coupled` the scalar plant has no roll DOF, so `:bank_to_turn` is a NO-OP — bit-for-bit
        # the `:skid_to_turn` (i.e. slice-22) trajectory.
        function trace(steering)
            w, s = btt_world(; steering = steering, airframe = :pitch_coupled); ps = Vec3[]
            for _ in 1:1200; tick!(w, s, dt); empty!(w.events); push!(ps, w.entities[:m1].pos); end
            ps
        end
        @test trace(:bank_to_turn) == trace(:skid_to_turn)       # steering inert off the 6-DOF plant
    end

    @testset "determinism — a BTT missile replays bit-identical (class 4c, no RNG)" begin
        function trace()
            w, s = btt_world(steering = :bank_to_turn); ps = Vec3[]
            for _ in 1:1500; tick!(w, s, dt); empty!(w.events); push!(ps, w.entities[:m1].pos); end
            ps
        end
        @test trace() == trace()
    end

    @testset "loader — tau_roll parses to comp + rejects τ ≤ 0; the :steering rung validates" begin
        base = """
        name: s24
        seed: 24
        dt_physics: 0.001
        fidelity: {airframe: six_dof, steering: bank_to_turn, guidance: pn, autopilot: alpha}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              guidance: {n_pn: 4.0}
              airframe:
                inertia_kgm2: 20.0
                cma: -1.0
                cmd: 3.0
                cla: 20.0
                alpha_max: 0.3
                cy_beta: 20.0
                inertia_roll_kgm2: 2.0
                inertia_yaw_kgm2: 20.0
                c_roll: 50.0
                tau_roll: 0.8
          - id: t1
            kind: target
            pos: [6000.0, 2000.0, 4200.0]
            vel: [0.0, 0.0, 0.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            good = joinpath(dir, "good.yaml"); write(good, base)
            scn = load_scenario(good)
            @test scn.world.fidelity[:steering] === :bank_to_turn    # the NEW rung validates through the wire
            @test scn.world.entities[:m1].comp[:af_tau_roll] == 0.8
            # tau_roll DEFAULTS when omitted (a live :steering toggle of a scenario that never authored
            # it can't KeyError a tick — consumer default 1.0).
            nod = join([l for l in split(base, '\n') if !occursin("tau_roll", l)], '\n')
            pd = joinpath(dir, "def.yaml"); write(pd, nod)
            @test !haskey(load_scenario(pd).world.entities[:m1].comp, :af_tau_roll)
            # REJECTS τ ≤ 0 (÷0 in the roll-loop gain ω_n = 1/τ) and a non-finite τ; and a bogus rung.
            for (from, to) in (("tau_roll: 0.8" => "tau_roll: 0.0"),
                               ("tau_roll: 0.8" => "tau_roll: -0.5"),
                               ("tau_roll: 0.8" => "tau_roll: .inf"),
                               ("steering: bank_to_turn" => "steering: wobble_to_turn"))
                pb = joinpath(dir, "bad.yaml"); write(pb, replace(base, from => to))
                @test_throws ErrorException load_scenario(pb)
            end
        end
    end
end

# --- slice 25 gate 2: the TWO-ANGLE seeker wired — the sensor half of the 3-D arc ----------------
# Slice 23 gave the missile an airframe that can turn out of the x–z plane and slice 24 made it
# choose HOW to point its lift — both TRUTH-FED. Here the SEEKER sees in 3-D: an az/el pair, α-β on
# each, and `ω = û × û̇` (frames.jl). The FOIL `:pitch_plane` is slice 11's scalar tracker, whose ω is
# structurally ∥ ±ŷ — so the cross-range command is never FORMED.
#
# The teeth: the 2-DRAW LOCKSTEP (what makes the button legal — both rungs draw 2, the foil DISCARDS
# the azimuth sample); the foil's blindness pinned EXACTLY (`== 0.0`) and PAIRED with a does-see case
# so it cannot pass by producing zero; the P11 INERTNESS invariant (introducing `:seeker_axes` on a
# slice-11 wire is bit-identical — the guard against the slice-21 `_atm_on` / slice-23 `:att_q`
# latent-bug class); and the LOAD refusal of the one ambiguous dispatch corner (§1b).
#
# The autopilot is `:ideal` ON PURPOSE: a fiat-accel plant CAN fly out of plane, so a foil miss here
# is the SENSOR's, isolated from the airframe (the 6-DOF showcase is gate 3).
@testset "guided missile — the TWO-ANGLE seeker wired (slice 25, :seeker_axes)" begin
    dt = 1.0e-3

    # A CROSS-RANGE target (off the x–z plane) — the geometry the in-plane seeker cannot see.
    function seeker3d_world(; axes = :az_el, seeker = :filtered, seed = 25, sigma = 3.0e-4,
                            two_angle = true, Y = 2000.0)
        fid = Dict(:autopilot => :ideal, :guidance => :pn, :seeker => seeker)
        axes === nothing || (fid[:seeker_axes] = axes)
        w = World(seed = seed, fidelity = fid)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
            vel = Vec3(700cosd(12), 0.0, 700sind(12)),
            comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
                :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0,
                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :a_max => 3000.0,
                :sigma_seek => sigma, :alpha => 0.30, :beta => 0.05,
                :seek_two_angle => two_angle))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, Y, 4200.0),
            vel = Vec3(0.0, 0.0, 0.0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1)]
    end
    function fly3d!(w, subs; n = 12000)
        miss = Inf; maxy = 0.0; prev = Inf; opening = 0
        for _ in 1:n
            tick!(w, subs, dt); empty!(w.events)
            r = w.env[:telemetry]["m1.los_range"]
            miss = min(miss, r); maxy = max(maxy, abs(w.entities[:m1].pos[2]))
            opening = r > prev ? opening + 1 : 0; prev = r
            (opening ≥ 200 && r > miss + 50.0) && break
        end
        return (miss = miss, maxy = maxy)
    end

    @testset "the 2-DRAW LOCKSTEP — EXACTLY 2 randn/tick on BOTH rungs (convention 3)" begin
        # The Seeker is the only w.rng consumer, so after N ticks w.rng must equal a fresh
        # Xoshiro(seed) advanced by 2N draws. THIS is what makes the button live-toggleable: the
        # foil DISCARDS n_az, it does not skip the draw. If someone "optimizes" that away, this fails.
        for axes in (:az_el, :pitch_plane), N in (500, 3000)
            w, subs = seeker3d_world(axes = axes, seed = 25)
            for _ in 1:N; tick!(w, subs, dt); empty!(w.events); end
            ref = Xoshiro(25); for _ in 1:(2N); randn(ref); end
            @test randn(copy(ref)) == randn(copy(w.rng))
        end
        # …and a NON-two-angle host still draws exactly 1 (slice 11 untouched by the new dispatch)
        w, subs = seeker3d_world(axes = nothing, two_angle = false, seed = 25)
        for _ in 1:500; tick!(w, subs, dt); empty!(w.events); end
        ref = Xoshiro(25); for _ in 1:500; randn(ref); end
        @test randn(copy(ref)) == randn(copy(w.rng))
    end

    @testset "the FOIL's blindness is EXACT — and PAIRED with a does-see case" begin
        wf, sf = seeker3d_world(axes = :pitch_plane)
        for _ in 1:200; tick!(wf, sf, dt); empty!(wf.events); end
        ωf = wf.entities[:m1].comp[:seeker_omega]
        @test ωf[1] == 0.0 && ωf[3] == 0.0                     # ω ∥ ±ŷ, structurally
        @test wf.env[:telemetry]["m1.omega_oop"] == 0.0        # the headline readout, EXACTLY zero
        @test abs(ωf[2]) > 0.0                                 # it does estimate SOMETHING (teeth)
        # PAIRED: the same geometry through the two-angle rung MUST produce out-of-plane ω
        wa, sa = seeker3d_world(axes = :az_el)
        for _ in 1:200; tick!(wa, sa, dt); empty!(wa.events); end
        @test wa.env[:telemetry]["m1.omega_oop"] > 1.0e-6
        @test abs(wa.entities[:m1].comp[:seeker_omega][3]) > 1.0e-6
        # BOTH trackers kept warm on BOTH rungs (a bumpless live toggle — the slice-11 shape)
        for c in (wf.entities[:m1].comp, wa.entities[:m1].comp)
            for k in (:seek_az_est, :seek_azdot_est, :seek_el_est, :seek_eldot_est,
                      :seek_lambda_est, :seek_lambdadot_est)
                @test haskey(c, k)
            end
            @test c[:seek_azdot_est] != 0.0 && c[:seek_lambdadot_est] != 0.0
        end
    end

    @testset "the rung is NOT a dead knob — the foil never leaves the x–z plane (max|y| == 0.0)" begin
        ra = fly3d!(seeker3d_world(axes = :az_el)...)
        rf = fly3d!(seeker3d_world(axes = :pitch_plane)...)
        @test ra.maxy > 100.0                                  # the two-angle seeker TURNS
        @test rf.maxy == 0.0                                   # the foil: EXACTLY in-plane, always
        @test rf.miss > 1000.0                                 # ⇒ it misses by ≈ the cross-range Y
        @test ra.miss < 50.0                                   # …while the two-angle arm closes
        @test rf.miss / max(ra.miss, 1e-9) > 20.0              # decisive, not a nudge
    end

    @testset "P11 — introducing :seeker_axes on a NON-two-angle wire is INERT (the latent-bug guard)" begin
        # The claim that lets `:seeker_axes` ship with NO set_fidelity guard: the 2-draw topology is
        # gated on the SCENARIO's host marker, never on this key. This is the slice-21 `_atm_on` /
        # slice-23 `:att_q` bug class — both were key-gated blocks firing where they should not.
        function trace25(; introduce_at = -1, axes = :az_el, N = 2000)
            w, subs = seeker3d_world(axes = nothing, two_angle = false, seed = 25)
            out = Float64[]
            for k in 1:N
                k == introduce_at && (w.fidelity[:seeker_axes] = axes)
                tick!(w, subs, dt); empty!(w.events)
                k % 250 == 0 && append!(out, (w.entities[:m1].pos[1], w.entities[:m1].pos[2],
                                              w.entities[:m1].pos[3], randn(copy(w.rng))))
            end
            out
        end
        base25 = trace25()
        @test trace25(introduce_at = 500, axes = :az_el)       == base25   # bit-identical, incl. the
        @test trace25(introduce_at = 500, axes = :pitch_plane) == base25   # next draw off w.rng
    end

    @testset "a huge σ_seek on the 3-D path never crashes a tick (live-slider guard, convention 5)" begin
        w, subs = seeker3d_world(axes = :az_el, seeker = :raw, sigma = 5.0)
        ok = true
        for _ in 1:800
            tick!(w, subs, dt); empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].pos) && all(isfinite, w.entities[:m1].comp[:a_ctrl]) &&
                  isfinite(tel["m1.omega_oop"]) && isfinite(tel["m1.az_dot_est"]) &&
                  isfinite(tel["m1.el_dot_est"]) && isfinite(tel["m1.omega_mag"])
            ok || break
        end
        @test ok
    end

    @testset "loader: two_angle arms the host; :scan × two_angle is a LOAD ERROR (§1b precedence)" begin
        base = """
        name: sk3
        seed: 25
        dt_physics: 0.001
        fidelity: {autopilot: ideal, guidance: pn, seeker: filtered, seeker_axes: az_el}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              seeker: {sigma_seek: 0.0003, alpha: 0.3, beta: 0.05, two_angle: true}
              guidance: {n_pn: 4.0, a_max: 3000.0}
          - id: tgt1
            kind: target
            pos: [6000.0, 2000.0, 4200.0]
            vel: [0.0, 0.0, 0.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            p = joinpath(dir, "ok.yaml"); write(p, base)
            scn = load_scenario(p)
            @test scn.world.entities[:m1].comp[:seek_two_angle] === true
            @test any(s -> s isa Seeker, scn.subs)
            # the ONE ambiguous corner, refused at LOAD rather than silently branch-ordered
            pb = joinpath(dir, "bad.yaml")
            write(pb, replace(base, "seeker: filtered" => "seeker: scan"))
            @test_throws ErrorException load_scenario(pb)
            # …and a missile WITHOUT the marker leaves the key false (the slice-11 path)
            p2 = joinpath(dir, "plain.yaml")
            write(p2, replace(base, ", two_angle: true" => ""))
            @test load_scenario(p2).world.entities[:m1].comp[:seek_two_angle] === false
        end
    end
end

@testset "THE RADOME / body-rate PARASITIC LOOP wired (slice 26 — the arc's named end point)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # The slice-25 engagement on the slice-23/24 6-DOF plant — a two-angle seeker, skid-to-turn,
    # a STATIC cross-range target — with the radome slope as the ONE new authored key. σ = 5e-5:
    # at slice 25's 3e-4 the seeker NOISE ALONE puts 7× the σ=0 baseline of jitter on q and
    # compresses the ring's signature from 106× to 14× (gate-0 P6B). `radome === nothing` mints NO
    # `:radome_slope` key at all — the byte-identity arm, and the shape the loader gates on.
    function rad_world(; radome = nothing, axes = :az_el, airframe = :six_dof, seed = 26,
                         sigma = 5.0e-5, rho = 1.0, alpha_max = 0.3, n_pn = 4.0, Y = 2000.0)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => airframe,
                                                 :seeker => :filtered, :seeker_axes => axes))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => rho,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => n_pn, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => sigma, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        radome === nothing || (comp[:radome_slope] = radome)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, Y, 4200.0),
                                 vel = zero(Vec3), comp = Dict{Symbol,Any}())
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⭐ THE METRIC IS rms BODY RATE over the mid-engagement — NEVER the peak and NEVER the miss.
    # `max|q|` is neither frame-robust nor noise-robust (peaks OVERLAP across the threshold, gate-0
    # P5D/P6C), and the miss is NOT MONOTONE ANYWHERE (1.73 m at R = −0.15 sits BELOW 3.35 m at
    # −0.12 — the 4th occurrence of [[ewsim-df-ellipse-sigma-monotonicity]], here disqualifying the
    # metric rather than bounding a domain). First-CPA over the first descending band as always.
    function ringfly(; T = 12.0, kw...)
        w, s = rad_world(; kw...)
        qs = Float64[]; rmin, prev, closing = Inf, Inf, true
        asat = 0; dsat = 0; nt = 0; αpk = 0.0; epk = 0.0; msat = 0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            tel = w.env[:telemetry]
            push!(qs, Float64(get(tel, "m1.omega_q", 0.0)))
            αpk = max(αpk, abs(Float64(get(tel, "m1.alpha", 0.0))))
            epk = max(epk, abs(Float64(get(tel, "m1.radome_eps", 0.0))))
            asat += Int(Float64(get(tel, "m1.aero_sat", 0.0)) != 0.0)
            dsat += Int(Float64(get(tel, "m1.defl_sat", 0.0)) != 0.0)
            msat += Int(Float64(get(tel, "m1.saturated", 0.0)) != 0.0)
            nt += 1
            r = n3(w.entities[:t1].pos - w.entities[:m1].pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            closing || break
        end
        i0 = max(1, length(qs) ÷ 4); i1 = max(i0 + 1, 3length(qs) ÷ 4)
        rms = sqrt(sum(abs2, @view qs[i0:i1]) / (i1 - i0 + 1))
        return (rms = rms, miss = rmin, qpk = maximum(abs, qs), αpk = αpk, epk = epk,
                asat = asat, dsat = dsat, msat = msat, nt = nt, w = w)
    end

    @testset "BYTE-IDENTITY — no `radome_slope` key ⇒ the slice-25 path, bit-for-bit" begin
        # The structural claim (the slice-20/21 shape): the no-radome arm takes a DIFFERENT BRANCH,
        # it does not add a zero. Never `+ ε` trusting `R = 0 ⇒ 0.0` — the `-0.0` trap AND float
        # non-associativity ((a+ε)+b ≠ a+b in the last ULP) both live on that line.
        function trace(; kw...)
            w, s = rad_world(; kw...)
            out = Float64[]
            for k in 1:2500
                tick!(w, s, dt); empty!(w.events)
                k % 250 == 0 && append!(out, (w.entities[:m1].pos..., w.entities[:m1].vel...,
                                              w.entities[:m1].comp[:att_q]...,
                                              w.entities[:m1].comp[:omega_body]...,
                                              randn(copy(w.rng))))
            end
            out
        end
        base = trace()
        # a SECOND no-radome run is bit-identical to the first (determinism, and the control)
        @test trace() == base
        # ⭐ AND SO IS AN AUTHORED `R = 0` — MEASURED, and stronger than expected. `ε = 0·look` is
        # exactly ±0.0, and `a + ±0.0 === a` for every finite a, so the radome BRANCH at R = 0
        # reproduces the key-absent branch bit-for-bit. That is the KNOB-vs-RUNG discriminator
        # (atmosphere.jl) verified rather than argued: R = 0 is not merely "an in-domain slider
        # value", it is BIT-IDENTICAL to the radome not existing — which is precisely why this is a
        # knob like `af_cma`/`af_k_induced` and NOT a rung like `:atmosphere` (whose off-state is
        # `H = ∞`, a limit point no slider reaches).
        @test trace(radome = 0.0) == base
        # ⚠ The BRANCH still earns its keep: byte-identity here is BY CONSTRUCTION (the no-key arm
        # never forms ε at all), not by a zero that happens to cancel. An unconditional `+ ε` would
        # ride on `0.0 * look` staying finite — which it does not if a look angle ever goes non-finite.
        # …and the RNG stream is in lockstep either way — 2 draws/tick, radome or not (convention 3)
        for R in (nothing, 0.0, -0.10)
            w, s = rad_world(radome = R)
            for _ in 1:600; tick!(w, s, dt); empty!(w.events); end
            ref = Xoshiro(26); for _ in 1:1200; randn(ref); end
            @test randn(copy(ref)) == randn(copy(w.rng))
        end
    end

    @testset "INERTNESS — the radome needs a 6-DOF plant (the latent-bug class, 3rd occurrence)" begin
        # ⚠ RUNG-GATED, NOT key-gated. `:att_q` is minted by `_integrate_6dof!` and NEVER deleted, so
        # a key-gated radome would keep refracting through a FROZEN attitude after a cross-toggle off
        # `:six_dof` (the slice-21 `_atm_on` bug and the slice-23 stale-readout bug, both caught by an
        # advisor at gate 2 — this is the same class's third appearance).
        base = ringfly(airframe = :pitch_coupled, radome = nothing)
        with = ringfly(airframe = :pitch_coupled, radome = -0.30)   # a slope 3× past onset…
        @test with.rms == base.rms                                  # …changes NOTHING off :six_dof
        @test with.miss == base.miss
        @test !haskey(with.w.env[:telemetry], "m1.radome_eps")      # and ships no stale telemetry
        # the LIVE cross-toggle: start in :six_dof (att_q minted), leave it, and the radome must go
        # inert on the very next tick rather than refract through the frozen attitude.
        w, s = rad_world(radome = -0.15)
        for _ in 1:400; tick!(w, s, dt); empty!(w.events); end
        @test haskey(w.entities[:m1].comp, :att_q)
        @test haskey(w.env[:telemetry], "m1.radome_eps")
        w.fidelity[:airframe] = :pitch_coupled
        tick!(w, s, dt); empty!(w.events)
        @test haskey(w.entities[:m1].comp, :att_q)                  # the key SURVIVES (never deleted)
        @test !haskey(w.env[:telemetry], "m1.radome_eps")           # …but the radome does NOT fire
    end

    @testset "⭐ THE LIMIT CYCLE — 0.09 is quiet, 0.10 shakes (and it is not the miss)" begin
        quiet = ringfly(radome = -0.09)
        ring  = ringfly(radome = -0.10)
        zero_ = ringfly(radome = 0.0)
        @test quiet.rms < 0.05                          # below onset the body is QUIET…
        @test ring.rms  > 0.5                           # …and one step past it, it is not
        @test ring.rms / quiet.rms > 10.0               # decisive, not a nudge (gate 0: ~60×)
        @test ring.rms / zero_.rms > 10.0
        @test quiet.rms / zero_.rms < 3.0               # …while R = −0.09 is barely off baseline
        # ⚠ THE MISS IS *NOT* THE METRIC — the ringing arm still HITS. Asserting a miss here would
        # be a false claim (and it is not monotone in R anyway). Pin that it stays a hit, so nobody
        # later "fixes" the scenario by chasing one.
        @test ring.miss < 50.0
        # THE MECHANISM is ε, and it is nonzero only where the radome is (paired null).
        @test ring.epk > 1.0e-3
        @test zero_.epk == 0.0
    end

    @testset "⭐ THE SIGN — only NEGATIVE slopes ring; positive ones DE-TUNE (the #1 trap's 8th)" begin
        neg = ringfly(radome = -0.10)
        pos = ringfly(radome =  0.10)
        @test neg.rms > 0.5
        @test pos.rms < 0.05                            # the mirror case: same |R|, no cycle at all
        @test neg.rms / pos.rms > 10.0
        # …and the positive arm is not merely inert — it perturbs the measurement just as hard.
        @test pos.epk > 1.0e-3
        @test isapprox(pos.epk, neg.epk; rtol = 0.6)
    end

    @testset "⭐ THE ISOLATION — the ceiling BOUNDS the cycle, it does not CAUSE it" begin
        # Slice 25 bought `aero_sat == 0` in both arms. That is IMPOSSIBLE here and must not be
        # copied: an oscillation drives demand, and demand hits the ceiling. The isolation is made a
        # DIFFERENT and stronger way — raise α_max 3× so the ceiling cannot bind at the old
        # amplitude and the ONSET DOES NOT MOVE. Only the amplitude grows.
        q_lo = ringfly(radome = -0.09, alpha_max = 0.3)
        r_lo = ringfly(radome = -0.10, alpha_max = 0.3)
        q_hi = ringfly(radome = -0.09, alpha_max = 0.9)
        r_hi = ringfly(radome = -0.10, alpha_max = 0.9)
        @test q_hi.rms < 0.05 && r_hi.rms > 0.5         # SAME onset at a 3× ceiling
        @test q_lo.rms < 0.05 && r_lo.rms > 0.5
        @test r_hi.rms > r_lo.rms                       # …the ceiling only sets the AMPLITUDE
        @test r_hi.qpk > 1.5 * r_lo.qpk
        # the OTHER caps stay provably clear on the SHIPPED configuration (α_max = 0.3): the fin
        # deflection limit (cap #3) is not what is binding, and `a_max` (cap #1) never binds at all.
        @test r_lo.dsat <= 0.01 * r_lo.nt
        @test q_lo.dsat <= 0.01 * q_lo.nt
        # cap #1 (`a_max`, the authored MAGNITUDE clamp) is structurally out of reach: the aero
        # ceiling itself maxes ≪ a_max, so the α inversion clamps first and `a_max` cannot be what
        # is binding. ⚠ Counted over the run, NOT read off the last tick — the r→0 endgame spikes
        # `a_demand` on the final ticks in EVERY arm ([[ewsim-missile-verifier-sampling]]), and
        # sampling there reads `saturated == 1` on a run that never saturated in the approach.
        @test r_lo.msat <= 0.01 * r_lo.nt
        @test q_lo.msat <= 0.01 * q_lo.nt
        @test Float64(r_lo.w.env[:telemetry]["m1.a_max_aero"]) < 1000.0
    end

    @testset "⭐ THE LOOP GAIN — the threshold is `N·|R|`, so raising N destabilizes EARLIER" begin
        # The teaching payload: a radome slope is not good or bad by itself. Gate 0 measured
        # `N·|R_crit|` = 0.380…0.400 across N ∈ {3,…,8}; two cells of that surface are enough to
        # pin the SCALING here (the full sweep lives in docs/plans/slice26.md §1).
        @test ringfly(radome = -0.08, n_pn = 4.0).rms < 0.05    # inert at N = 4…
        @test ringfly(radome = -0.08, n_pn = 5.0).rms > 0.5     # …and ringing at N = 5, same slope
        @test ringfly(radome = -0.12, n_pn = 3.0).rms < 0.05    # a BIGGER slope is safe at N = 3
    end

    @testset "STRUCTURAL, not noise: σ_seek = 0 still self-excites" begin
        # The tempting story ("a noisy seeker excites the airframe") — REFUTED, and refuting it is
        # what makes this a LOOP lesson rather than a filter one.
        @test ringfly(radome = -0.10, sigma = 0.0).rms > 0.5
        @test ringfly(radome =  0.0,  sigma = 0.0).rms < 0.05
    end

    @testset "the telemetry keys that would otherwise ROT (advisor: shipped but unasserted)" begin
        # `omega_ratio` and `radome_eps_az` are shipped on the wire and read by the HUD, but neither
        # is load-bearing for the headline — which is exactly how a key quietly breaks. One tooth each.
        wq, sq = rad_world(radome = 0.0);   for _ in 1:2000; tick!(wq, sq, dt); empty!(wq.events); end
        wr, sr = rad_world(radome = -0.10); for _ in 1:2000; tick!(wr, sr, dt); empty!(wr.events); end
        # ⚠ `omega_ratio` is a DIAGNOSTIC, not the mechanism — its STATIC response to R is small and
        # smooth, and once the loop rings it is dominated by the cycle's own body-rate feedthrough.
        # So the tooth is deliberately LOOSE at R = 0 (the α-β tracker lags truth, so it sits near
        # but not at 1) and only asserts the SEPARATION once ringing.
        rq = Float64(wq.env[:telemetry]["m1.omega_ratio"])
        rr = Float64(wr.env[:telemetry]["m1.omega_ratio"])
        @test 0.5 < rq < 1.5                       # no radome ⇒ the seeker reports ≈ the truth rate
        @test rr > 2.0 * rq                        # ringing ⇒ the body rate dominates what it reports
        @test isfinite(rq) && isfinite(rr)
        # the zero-relative-velocity guard: ω_truth → 0 must give a huge-but-FINITE ratio, never NaN
        # (convention 6 — the `_finite`/FINITE_CEIL clamp, and the divide that would otherwise 0/0)
        wz, sz = rad_world(radome = -0.10)
        tick!(wz, sz, dt); empty!(wz.events)
        wz.entities[:m1].vel = wz.entities[:t1].vel      # co-moving ⇒ r×v ≡ 0
        tick!(wz, sz, dt)
        @test isfinite(Float64(wz.env[:telemetry]["m1.omega_ratio"]))
        # `radome_eps_az` is the YAW-axis boresight error — real physics (`ε̇_az = −R·ω_z`), and it is
        # NONZERO here precisely because the target is off the x–z plane (an in-plane engagement
        # would leave it at zero, which is why the cross-range geometry is what makes it meaningful).
        @test abs(Float64(wr.env[:telemetry]["m1.radome_eps_az"])) > 1.0e-4
        @test Float64(wq.env[:telemetry]["m1.radome_eps_az"]) == 0.0      # R = 0 ⇒ exactly zero
    end

    @testset "an absurd slope never crashes a tick (live-slider guard, convention 5/6)" begin
        for R in (-1.0e6, 1.0e6, -1.0, 1.0)
            w, s = rad_world(radome = R)
            ok = true
            for _ in 1:600
                tick!(w, s, dt); empty!(w.events)
                tel = w.env[:telemetry]
                ok &= all(isfinite, w.entities[:m1].pos) &&
                      all(isfinite, w.entities[:m1].comp[:att_q]) &&
                      isfinite(tel["m1.radome_eps"]) && isfinite(tel["m1.look_angle"]) &&
                      isfinite(tel["m1.omega_ratio"]) && isfinite(tel["m1.radome_slope"])
                ok || break
            end
            @test ok
        end
    end

    @testset "loader + handshake: the key is PRESENCE-gated and it DROPS the button" begin
        base = """
        name: rad
        seed: 26
        dt_physics: 0.001
        fidelity: {autopilot: alpha, guidance: pn, seeker: filtered, seeker_axes: az_el, airframe: six_dof}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              rho: 1.0
              seeker: {sigma_seek: 0.00005, alpha: 0.3, beta: 0.05, two_angle: true, radome_slope: -0.10}
              guidance: {n_pn: 4.0, a_max: 3000.0, delta_max: 0.5, k_alpha: 1.0, k_q: 0.3}
              airframe: {ref_len_m: 0.2, inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0, cmq: -150.0,
                         cla: 20.0, alpha_max: 0.3, cy_beta: 20.0, inertia_roll_kgm2: 2.0,
                         inertia_yaw_kgm2: 20.0, c_roll: 50.0}
          - id: tgt1
            kind: target
            pos: [6000.0, 2000.0, 4200.0]
            vel: [0.0, 0.0, 0.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            p = joinpath(dir, "ok.yaml"); write(p, base)
            scn = load_scenario(p)
            @test scn.world.entities[:m1].comp[:radome_slope] == -0.10
            # the handshake marker that makes the client DROP the shared button (Option-P′) —
            # ⚠ NOT the slice-20 inherited-cycler precedent: `:pitch_plane` would leave the radome
            # LIVE AND REFRACTING beside slice 25's unrelated 2000 m blind miss.
            info = EWSim._airframe_view_info(scn.world)
            @test info[:radome_view] === true
            @test info[:airframe_6dof] === true
            # PRESENCE-gated: no authored key ⇒ NO comp key ⇒ no marker (slices 23/24/25 keep theirs)
            p2 = joinpath(dir, "plain.yaml")
            write(p2, replace(base, ", radome_slope: -0.10" => ""))
            scn2 = load_scenario(p2)
            @test !haskey(scn2.world.entities[:m1].comp, :radome_slope)
            @test !haskey(EWSim._airframe_view_info(scn2.world), :radome_view)
            @test EWSim._airframe_view_info(scn2.world)[:airframe_6dof] === true
            # …and it is a real, knob-addressable comp key (a slider must name one)
            p3 = joinpath(dir, "knob.yaml")
            write(p3, base * "\nknobs:\n  - {target: m1, key: radome_slope, min: -0.12, max: 0.06, label: R}\n")
            @test length(load_scenario(p3).knobs) == 1
            # a non-finite slope is refused at LOAD (convention 5, validate-at-load half)
            pb = joinpath(dir, "bad.yaml")
            write(pb, replace(base, "radome_slope: -0.10" => "radome_slope: .nan"))
            @test_throws ErrorException load_scenario(pb)
        end
    end
end

@testset "THE RADOME-SLOPE COMPENSATION AUTOPILOT wired (slice 27 — margin, not immunity)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # Slice 26's wire with the COMPENSATOR's estimate as the one new authored key. ⚠ N = 8, not
    # slice 26's 4: the shipped showcase is the missile slice 26's own design trade condemned — a
    # SNAPPY interceptor (`N·|R|/ρ = 0.80`, twice the boundary) carrying a POOR but REAL radome.
    # That wire was chosen on MODEL VALIDITY, not taste: reaching the same loop gain by worsening
    # the glass to R = −0.30 instead puts 5.3% of ticks past a 30° look angle, where the linear
    # `ε = R·look` model is weakest, against 0.06% here (`docs/plans/slice27.md` §5).
    # `slope_est === nothing` mints NO `:radome_slope_est` key — the byte-identity arm.
    function comp_world(; radome = -0.10, slope_est = nothing, axes = :az_el, airframe = :six_dof,
                          seed = 27, sigma = 5.0e-5, rho = 1.0, alpha_max = 0.3, n_pn = 8.0,
                          Y = 2000.0)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => airframe,
                                                 :seeker => :filtered, :seeker_axes => axes))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => rho,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => n_pn, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => sigma, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        radome    === nothing || (comp[:radome_slope] = radome)
        slope_est === nothing || (comp[:radome_slope_est] = slope_est)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, Y, 4200.0),
                                 vel = zero(Vec3), comp = Dict{Symbol,Any}())
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⭐ SLICE 26's METRIC, UNCHANGED: rms body pitch rate over the mid-engagement. NEVER the peak
    # (peaks OVERLAP across the threshold) and NEVER the miss (not monotone anywhere — and on THIS
    # wire the uncompensated arm still HITS at ~2.4 m, which is exactly why the oscillation is the
    # headline). First-CPA over the first descending band ([[ewsim-missile-verifier-sampling]]).
    function compfly(; T = 12.0, kw...)
        w, s = comp_world(; kw...)
        qs = Float64[]; rmin, prev, closing = Inf, Inf, true
        asat = 0; dsat = 0; nt = 0; αpk = 0.0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            tel = w.env[:telemetry]
            push!(qs, Float64(get(tel, "m1.omega_q", 0.0)))
            αpk = max(αpk, abs(Float64(get(tel, "m1.alpha", 0.0))))
            asat += Int(Float64(get(tel, "m1.aero_sat", 0.0)) != 0.0)
            dsat += Int(Float64(get(tel, "m1.defl_sat", 0.0)) != 0.0)
            nt += 1
            r = n3(w.entities[:t1].pos - w.entities[:m1].pos)
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            closing || break
        end
        i0 = max(1, length(qs) ÷ 4); i1 = max(i0 + 1, 3length(qs) ÷ 4)
        rms = sqrt(sum(abs2, @view qs[i0:i1]) / (i1 - i0 + 1))
        return (rms = rms, miss = rmin, qpk = maximum(abs, qs), αpk = αpk,
                asat = asat, dsat = dsat, nt = nt, w = w)
    end

    @testset "BYTE-IDENTITY — no `radome_slope_est` key ⇒ the slice-26 path, bit-for-bit" begin
        # The structural claim (the slice-20/21/26 shape): the no-compensator arm takes a DIFFERENT
        # BRANCH, it does not add a zero. Never `ȧz + ȧz_ff` trusting `R̂ = 0 ⇒ 0.0`.
        function trace(; kw...)
            w, s = comp_world(; kw...)
            out = Float64[]
            for k in 1:2500
                tick!(w, s, dt); empty!(w.events)
                k % 250 == 0 && append!(out, (w.entities[:m1].pos..., w.entities[:m1].vel...,
                                              w.entities[:m1].comp[:att_q]...,
                                              w.entities[:m1].comp[:omega_body]...,
                                              randn(copy(w.rng))))
            end
            out
        end
        base = trace()
        @test trace() == base                              # determinism, and the control
        # ⭐ AN AUTHORED R̂ = 0 IS BIT-IDENTICAL TO THE KEY BEING ABSENT — the same measurement slice
        # 26 made for `R = 0`, and it is what makes this a KNOB rather than a fidelity rung by
        # atmosphere.jl's discriminator (the off-state is knob-reachable, not a limit point).
        @test trace(slope_est = 0.0) == base
        # …and the RNG stream stays in lockstep — the compensator adds NO draw (class 4a,
        # convention 3). Asserted, not assumed.
        for R̂ in (nothing, 0.0, -0.10)
            w, s = comp_world(slope_est = R̂)
            for _ in 1:600; tick!(w, s, dt); empty!(w.events); end
            ref = Xoshiro(27); for _ in 1:1200; randn(ref); end
            @test randn(copy(ref)) == randn(copy(w.rng))
        end
    end

    @testset "INERTNESS — the compensator needs a 6-DOF plant (the latent-bug class, 4th)" begin
        # ⚠ RUNG-GATED ON THE LIVE `:airframe`, not on `haskey(:att_q)`: that key is minted by
        # `_integrate_6dof!` and NEVER deleted, so a key-gated compensator would keep feeding a
        # FROZEN gyro reading forward after a cross-toggle off `:six_dof`. Slice 21's `_atm_on`,
        # slice 23's stale readout and slice 26's radome are occurrences 1–3.
        b = compfly(airframe = :pitch_coupled, slope_est = nothing)
        c = compfly(airframe = :pitch_coupled, slope_est = -0.10)
        @test c.rms == b.rms
        @test c.miss == b.miss
        @test !haskey(c.w.env[:telemetry], "m1.radome_residual")
        # the LIVE cross-toggle: inert on the very next tick
        w, s = comp_world(slope_est = -0.10)
        for _ in 1:400; tick!(w, s, dt); empty!(w.events); end
        @test haskey(w.env[:telemetry], "m1.radome_residual")
        w.fidelity[:airframe] = :pitch_coupled
        tick!(w, s, dt); empty!(w.events)
        @test haskey(w.entities[:m1].comp, :att_q)              # the key SURVIVES (never deleted)
        @test !haskey(w.env[:telemetry], "m1.radome_residual")  # …but the compensator does NOT fire
    end

    @testset "⭐ THE CURE — a matched estimate kills the ring the radome starts" begin
        ring = compfly(radome = -0.10, slope_est = nothing)   # slice 26's disease, at N = 8
        cure = compfly(radome = -0.10, slope_est = -0.10)     # perfect knowledge
        @test ring.rms > 0.5                                  # the loop is ringing…
        @test cure.rms < 0.05                                 # …and the gyro quiets it
        @test ring.rms / cure.rms > 20.0                      # decisive (gate 0: 62×)
        # ⚠ AND THE MISS STAYS AT BASELINE — THE DE-TUNE DISCRIMINATOR (advisor, and it is the
        # sharpest risk in the slice). `ėl` and `q` are COLLINEAR in closed loop (slice 26 P7A,
        # R² = 0.999), so subtracting `R̂·cos·ω_y` from `ėl` is numerically near-indistinguishable
        # from SCALING `ėl` DOWN — i.e. from lowering effective N. A "compensator" that works by
        # DE-TUNING would quiet the ring just as convincingly, and slice 26 measured de-tuning's
        # signature: the miss OPENS from sluggishness. Ring down AND miss at baseline ⇒ cancellation.
        clean = compfly(radome = nothing, slope_est = nothing)
        @test cure.miss < 2.0 * max(clean.miss, 0.5)
        @test cure.miss < ring.miss
    end

    @testset "⭐⭐ THE BOUNDARY IS ON THE RESIDUAL — an OFFSET, not a gain" begin
        # THE HEADLINE, and simultaneously the ISOLATION (the same measurement does both — a
        # de-tuner's onset would move with R̂ as a GAIN, and a gain cannot hold a constant offset).
        # Slice 26's boundary sits at |R| ≈ 0.38/(N·ρ) = 0.0475 here; compensation must SHIFT it by
        # exactly R̂. Sampled at three estimates rather than swept (a full sweep is the verifier's
        # job — this is the tooth).
        for R̂ in (0.0, -0.10, -0.20)
            est = R̂ == 0.0 ? nothing : R̂
            # one step INSIDE the boundary (residual 0.04 < 0.0475) ⇒ quiet
            @test compfly(radome = R̂ - 0.04, slope_est = est).rms < 0.10
            # one step OUTSIDE it (residual 0.10 > 0.0475) ⇒ ringing
            @test compfly(radome = R̂ - 0.10, slope_est = est).rms > 0.5
        end
        # ⭐ THE DIAGONAL: move the glass and the belief TOGETHER and NOTHING HAPPENS. This is what
        # makes TWO knobs ONE lesson (convention 9 is satisfied by the measurement, not by counting
        # sliders) — the missile does not care about glass it KNOWS about.
        for R in (-0.05, -0.20, -0.40)
            @test compfly(radome = R, slope_est = R).rms < 0.10
        end
        # ⚠ AND THE WRONG SIGN IS A WORSE RADOME, NOT A WEAKER CURE — the #1 SIGN TRAP's 9th
        # occurrence, pinned as behaviour. A double-flipped compensator would quiet the ring HERE
        # and ring at R̂ = R, and every number in this slice would be written backwards.
        wrong = compfly(radome = -0.10, slope_est = +0.10)
        @test wrong.rms > 0.5
        @test wrong.miss > compfly(radome = -0.10, slope_est = -0.10).miss
    end

    @testset "THE ISOLATION — the ceiling BOUNDS the cycle, the RESIDUAL decides there is one" begin
        # Slice 26's isolation, re-run on the COMPENSATED boundary. ⚠ `aero_sat == 0` is IMPOSSIBLE
        # (an oscillation drives demand into the ceiling — do NOT copy slice 25's isolation), so:
        # raise α_max 3× and the CROSSING must not move while the AMPLITUDE grows.
        lo_ring = compfly(radome = -0.10, slope_est = nothing, alpha_max = 0.3)
        hi_ring = compfly(radome = -0.10, slope_est = nothing, alpha_max = 0.9)
        lo_cure = compfly(radome = -0.10, slope_est = -0.10,   alpha_max = 0.3)
        hi_cure = compfly(radome = -0.10, slope_est = -0.10,   alpha_max = 0.9)
        @test hi_ring.rms > 1.5 * lo_ring.rms            # a taller ceiling ⇒ a BIGGER cycle…
        @test lo_cure.rms < 0.05 && hi_cure.rms < 0.05   # …but the cured arm stays cured
        # the other caps are provably clear on the arms that ship (slice 26's discipline, as numbers)
        @test lo_cure.dsat / lo_cure.nt < 0.01           # cap #3 (δ_max) — never binds
        @test lo_ring.dsat / lo_ring.nt < 0.01
        @test lo_cure.αpk < 0.3                          # no α_max clamp leak on the cured arm
    end

    @testset "the loader key + telemetry (the residual shipped as a NUMBER — convention 13)" begin
        base = """
        name: s27
        seed: 27
        dt_physics: 1.0e-3
        fidelity: {airframe: six_dof, autopilot: alpha, guidance: pn, seeker: filtered, seeker_axes: az_el}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 3000.0]
            missile:
              mass_kg: 140.0
              speed: 700.0
              elevation_deg: 12.0
              cd_area_m2: 0.0
              rho: 1.0
              seeker: {sigma_seek: 5.0e-5, alpha: 0.30, beta: 0.05, two_angle: true, radome_slope: -0.10, radome_slope_est: -0.06}
              guidance: {n_pn: 8.0, a_max: 3000.0, delta_max: 0.5, k_alpha: 1.0, k_q: 0.3}
              airframe: {ref_len_m: 0.2, inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0, cmq: -150.0,
                         cla: 20.0, alpha_max: 0.3, cy_beta: 20.0, inertia_roll_kgm2: 2.0,
                         inertia_yaw_kgm2: 20.0, c_roll: 50.0}
          - id: tgt1
            kind: target
            pos: [6000.0, 2000.0, 4200.0]
            vel: [0.0, 0.0, 0.0]
            target: {rcs_m2: 1.0}
        """
        mktempdir() do dir
            p = joinpath(dir, "ok.yaml"); write(p, base)
            scn = load_scenario(p)
            @test scn.world.entities[:m1].comp[:radome_slope_est] == -0.06
            # the slice-26 marker is INHERITED unchanged — slice 27 adds no rung, so the button
            # stays DROPPED (third slice in this family: 16, 26, 27).
            @test EWSim._airframe_view_info(scn.world)[:radome_view] === true
            # PRESENCE-gated: no authored estimate ⇒ NO comp key (slice 26 wires untouched)
            p2 = joinpath(dir, "plain.yaml")
            write(p2, replace(base, ", radome_slope_est: -0.06" => ""))
            @test !haskey(load_scenario(p2).world.entities[:m1].comp, :radome_slope_est)
            # …and it is knob-addressable (a slider must name a real comp key)
            p3 = joinpath(dir, "knob.yaml")
            write(p3, base * "\nknobs:\n  - {target: m1, key: radome_slope_est, min: -0.15, max: 0.0, label: Rhat}\n")
            @test length(load_scenario(p3).knobs) == 1
            # a non-finite estimate is refused at LOAD (convention 5, validate-at-load half). ⚠ Only
            # FINITE is checked: a WRONG-SIGN estimate is a legitimate and instructive input (it
            # compensates the wrong way = a strictly worse radome), and what closes the loop is the
            # RESIDUAL, so bounding this key would bound the lesson.
            pb = joinpath(dir, "bad.yaml")
            write(pb, replace(base, "radome_slope_est: -0.06" => "radome_slope_est: .inf"))
            @test_throws ErrorException load_scenario(pb)
        end
        # ⭐ THE RESIDUAL IS SHIPPED AS A NUMBER so the client never subtracts (convention 13 — the
        # slice-21 `rho_air` precedent). It is `R − R̂`, and it is correct even when compensating
        # for glass that is not there.
        w, s = comp_world(radome = -0.10, slope_est = -0.06)
        for _ in 1:200; tick!(w, s, dt); empty!(w.events); end
        tel = w.env[:telemetry]
        @test tel["m1.radome_slope_est"] ≈ -0.06 atol = 1e-15
        @test tel["m1.radome_residual"] ≈ -0.04 atol = 1e-15
        @test haskey(tel, "m1.radome_ff_el")
        # ⭐ AND `radome_ff_el` IS PINNED BY VALUE, NOT MERELY BY PRESENCE (advisor — slice 26 shipped
        # a whole hardening commit on the finding that "a shipped telemetry key with NO tooth is the
        # kind that rots"). The gate-1 axis-asymmetry tooth covers the KERNEL; this covers the SEAM'S
        # USE of it, which is where a refactor would drop the `cos(look_az)` factor or swap the axes.
        # ⚠ Reconstructed at σ = 0 so the measurement is exactly truth + bend: the compensator's look
        # angle comes from the MEASURED (bent) LOS, and reproducing THAT composition is the point —
        # a tooth that recomputed it from `û_tru` would pass on a compensator that illegally read
        # truth. Phase 1 < phase 3, so the post-tick att/ω are the ones observe! consumed.
        let R = -0.10, R̂ = -0.06
            w3, s3 = comp_world(radome = R, slope_est = R̂, sigma = 0.0)
            for _ in 1:200; tick!(w3, s3, dt); empty!(w3.events); end
            m3 = w3.entities[:m1]; t3 = w3.entities[:t1]
            û_t = los_unit(m3.pos, t3.pos)
            az_t, el_t = az_el(û_t)
            εa, εe = radome_error(R, look_angles(m3.comp[:att_q]::Quat, û_t)...)
            û_m = los_unit_from_angles(az_t + εa, el_t + εe)          # the BENT measurement
            la_c, _ = look_angles(m3.comp[:att_q]::Quat, û_m)
            _, ff_e = radome_compensation(R̂, la_c, m3.comp[:omega_body]::Vec3)
            @test w3.env[:telemetry]["m1.radome_ff_el"] ≈ ff_e atol = 1e-12
            @test abs(ff_e) > 1e-6                                    # PAIRED: it is not passing on 0
        end
        # compensating for a radome the missile does NOT have: residual = −R̂, and it is REAL
        # (it de-tunes), not a no-op — which is why the compensator is not gated on the radome key.
        w2, s2 = comp_world(radome = nothing, slope_est = -0.06)
        for _ in 1:200; tick!(w2, s2, dt); empty!(w2.events); end
        @test w2.env[:telemetry]["m1.radome_residual"] ≈ +0.06 atol = 1e-15
        @test !haskey(w2.env[:telemetry], "m1.radome_eps")     # …and no radome telemetry at all
    end
end

@testset "THE RADOME SLOPE CURVE wired (slice 28 — the band the engagement visits)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # Slices 26/27's wire with TWO changes, and BOTH are measured decisions:
    #
    #  (1) THE RIPPLE keys (`radome_ripple` / `radome_ripple_k`) — the one new authored pair.
    #      `ripple === nothing` mints NO key at all: the byte-identity arm, and the shape the
    #      loader and the seam both gate on.
    #  (2) ⚠ A **CROSSING** TARGET, which BREAKS the static Y = 2000 geometry slices 23–27 all
    #      shared. That is not a preference: against a STATIC target the collision course carries
    #      ZERO LEAD, so the look angle decays to 0.04–0.54° over the endgame and a look-angle
    #      dependent slope is a DEAD KNOB there (`docs/plans/slice28.md` §1, measured on a STABLE
    #      arm — a ringing arm's look angle swings BECAUSE it is ringing). A crossing target holds
    #      a sustained LEAD ANGLE of 15–30° for the whole flight. The slice-25 precedent: the
    #      isolation forces the wire, and the wire change is stated rather than slipped in.
    #
    # R₀ = −0.03 is a GOOD radome on slice 26's scale, deliberately: the lesson is that good glass
    # at boresight is not good glass everywhere. k = 12 (a 30° ripple period) is AUTHORED and NOT a
    # knob — the metric is non-monotone in it (plan §8).
    function curve_world(; radome = -0.03, ripple = nothing, k = 12.0, slope_est = -0.03,
                           vy = 200.0, axes = :az_el, airframe = :six_dof, seed = 28,
                           sigma = 5.0e-5, rho = 1.0, alpha_max = 0.3, n_pn = 8.0, Y = 2000.0)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => airframe,
                                                 :seeker => :filtered, :seeker_axes => axes))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => rho,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => n_pn, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => sigma, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        radome    === nothing || (comp[:radome_slope] = radome)
        slope_est === nothing || (comp[:radome_slope_est] = slope_est)
        if ripple !== nothing
            comp[:radome_ripple] = ripple; comp[:radome_ripple_k] = k
        end
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, Y, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0), comp = Dict{Symbol,Any}())
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⚠⚠ TWO DELIBERATE DEPARTURES FROM SLICES 26/27's METRIC, both measured (plan §7) — do NOT
    # copy this block back onto a 26/27 wire:
    #
    #  (a) THE CHANNEL IS **YAW** (`omega_r`), not pitch. The lead angle this wire holds is in
    #      AZIMUTH, so the azimuth channel is the one sitting on the steep part of the curve and
    #      the ring is in yaw. `rms q` is reported BESIDE it as the CHANNEL-SPLIT evidence, not as
    #      the headline.
    #  (b) THE WINDOW IS A **RANGE BAND** [500, 3000] m, not a tick fraction. On a crossing wire
    #      `rms r` carries a LEGITIMATE baseline — the missile turning onto the collision course,
    #      which is front-loaded: 0.172 over the whole approach against 0.0138 inside the band.
    #      And arms with different ToF would otherwise compare DIFFERENT PARTS of the engagement.
    #      ⇒ quote the window with every number.
    # rms, NEVER the peak; and the MISS is not the metric — the ringing arms still HIT (slice 26).
    function curvefly(; T = 16.0, kw...)
        w, s = curve_world(; kw...)
        qs = Float64[]; rs_ = Float64[]; rr = Float64[]
        saz = Float64[]; sel = Float64[]
        tel_mid = Dict{String,Any}()
        rmin, prev, closing = Inf, Inf, true
        asat = 0; dsat = 0; nt = 0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            tel = w.env[:telemetry]
            r = n3(w.entities[:t1].pos - w.entities[:m1].pos)
            push!(qs, Float64(get(tel, "m1.omega_q", 0.0)))
            push!(rs_, Float64(get(tel, "m1.omega_r", 0.0)))
            push!(rr, r)
            push!(saz, Float64(get(tel, "m1.radome_slope_az", NaN)))
            push!(sel, Float64(get(tel, "m1.radome_slope_el", NaN)))
            # ⚠ A MID-WINDOW SNAPSHOT, NOT THE LAST TICK. The telemetry dict left behind when the
            # loop exits is the CPA frame, where the LOS sweeps through the missile and BOTH look
            # angles swing wildly — asserting channel gains there measures the endgame spike, not
            # the operating point ([[ewsim-missile-verifier-sampling]]). Caught by this very test:
            # at CPA the elevation gain read −0.129 against an operating value of −0.03.
            isempty(tel_mid) && r < 2000.0 && (tel_mid = copy(tel))
            asat += Int(Float64(get(tel, "m1.aero_sat", 0.0)) != 0.0)
            dsat += Int(Float64(get(tel, "m1.defl_sat", 0.0)) != 0.0)
            nt += 1
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            closing || break
        end
        win = findall(x -> 500.0 < x < 3000.0, rr)
        rms(v) = isempty(win) ? 0.0 : sqrt(sum(abs2, v[win]) / length(win))
        med(v) = (u = sort(v[win]); isempty(u) ? NaN : u[(length(u) + 1) ÷ 2])
        return (rms_r = rms(rs_), rms_q = rms(qs), miss = rmin, tel_mid = tel_mid,
                slope_az = med(saz), slope_el = med(sel),
                asat = asat, dsat = dsat, nt = nt, nwin = length(win), w = w)
    end

    @testset "BYTE-IDENTITY — no `radome_ripple` key ⇒ the slice-26/27 path, bit-for-bit" begin
        # The structural claim (the slice-20/21/26/27 shape, now at a THIRD nesting level): the
        # no-ripple arm calls `radome_error` VERBATIM, it does not evaluate the curve at amplitude
        # zero. `x + 0.0` is not the identity at x = −0.0 and float addition is not associative.
        function trace(; kw...)
            w, s = curve_world(; kw...)
            out = Float64[]
            for _ in 1:900
                tick!(w, s, dt); empty!(w.events)
                m = w.entities[:m1]
                append!(out, (m.pos[1], m.pos[2], m.pos[3], m.vel[1], m.vel[2], m.vel[3]))
            end
            return out
        end
        base = trace(ripple = nothing)
        @test trace(ripple = nothing) == base                  # determinism, and the control
        # ⭐ AMPLITUDE 0 IS BIT-IDENTICAL TO THE KEY NOT EXISTING — which is what makes `ripple` a
        # KNOB rather than a fidelity rung (atmosphere.jl's discriminator: the off-state is
        # knob-REACHABLE). MEASURED, as slice 26 measured it for R = 0, not argued.
        @test trace(ripple = 0.0) == base
        @test trace(ripple = -0.05) != base                    # …PAIRED with a does-curve arm
    end

    @testset "the DRAW COUNT is unchanged — 2/tick, ripple or not (class 4a, convention 3)" begin
        # The curve is arithmetic on state that already exists, so it cannot move the RNG. Measured
        # the way slices 25/26/27 measure it: an identical seed must leave the stream in the same
        # place after the same number of ticks, whatever the ripple.
        function draws(rip)
            w, s = curve_world(ripple = rip)
            for _ in 1:300; tick!(w, s, dt); empty!(w.events); end
            return randn(w.rng)             # the NEXT draw is the stream's fingerprint
        end
        d0 = draws(nothing)
        @test draws(0.0) == d0
        @test draws(-0.05) == d0
        @test draws(-0.20) == d0
        # ⚠ AND THE FINGERPRINT MUST BE LIVE, or the three lines above cannot tell "lockstep
        # preserved" from "the probe is insensitive" (advisor). A different SEED must move it.
        let w, s2
            w, s2 = curve_world(ripple = -0.05, seed = 99)
            for _ in 1:300; tick!(w, s2, dt); empty!(w.events); end
            @test randn(w.rng) != d0
        end
    end

    @testset "INERTNESS — the ripple needs the radome AND a 6-DOF plant (5th occurrence)" begin
        # Rung-gated on the LIVE `:airframe`, never on a key that is never deleted (the slice-21
        # `_atm_on` / 23 / 26 / 27 latent-bug class). Without `:six_dof` there is no attitude to
        # look through, so the curve cannot reach the seam and no telemetry may be shipped.
        r = curvefly(T = 4.0, airframe = :pitch_coupled, ripple = -0.10)
        @test !haskey(r.w.env[:telemetry], "m1.radome_slope_az")
        @test !haskey(r.w.env[:telemetry], "m1.radome_eps")
        # and WITHOUT `radome_slope` the whole radome branch is off, so the ripple is unreachable
        r2 = curvefly(T = 4.0, radome = nothing, ripple = -0.10)
        @test !haskey(r2.w.env[:telemetry], "m1.radome_slope_az")
    end

    @testset "⭐ THE CURVE RINGS WHERE THE CONSTANT DOES NOT (the slice, on the wire)" begin
        # The SAME boresight slope R₀ = −0.03 and the SAME compensator R̂ = −0.03 — which is
        # EXACTLY right at boresight — flown against the SAME crossing target. The only difference
        # is that the glass has a ripple, so the slope where the seeker is actually looking is not
        # the slope it was characterized at.
        flat  = curvefly(ripple = nothing)
        curve = curvefly(ripple = -0.05)
        @test flat.rms_r  < 0.05                       # a boresight-correct compensator: quiet
        @test curve.rms_r > 0.5                        # the same missile, the same glass: RINGING
        @test curve.rms_r > 15 * flat.rms_r
        # ⚠ THE MISS IS NOT THE METRIC — the ringing arm still HITS (slices 26/27, unchanged).
        @test curve.miss < 5.0
        # ⭐ THE CHANNEL SPLIT: the ring is in YAW, because the lead angle is in AZIMUTH, while the
        # PITCH channel sits near the BORESIGHT slope. A CONSTANT slope cannot produce this — both
        # channels then share one slope and ring together. A second isolation, not a decoration.
        @test curve.rms_q < 0.5 * curve.rms_r
    end

    @testset "⭐ THE LOOP TRACKS THE DERIVATIVE, NOT THE BEND — what LICENSES the slice" begin
        # A slope CURVE is more than a re-parameterization of slice 26's constant only if the loop
        # is driven by the LOCAL DERIVATIVE `dε/dlook` rather than by the BEND `ε` itself. Under
        # slice 26's LINEAR model those are the same number, which is exactly why 26 could not tell
        # them apart. Here they are not: at the operating look angle the shipped curve's DERIVATIVE
        # is −0.10 while its SECANT `ε(L)/L` is −0.05, a factor of two apart.
        #
        # ⚠ THIS TRIO IS MEASURED OFF THE SHIPPED WIRE, DELIBERATELY (R₀ = 0 instead of −0.03), AND
        # THE REASON IS A TRAP THAT SPOILED TWO GATE-0 RUNS: the A/B is only an A/B if the SECANT
        # arm lands INSIDE critical. On the shipped wire the secant is ≈ −0.079, already past
        # |R_crit| ≈ 0.065 for this geometry, so BOTH linear arms would ring and the comparison
        # would prove nothing. R₀ = 0 puts the secant at −0.05 (safe) and the derivative at −0.10
        # (well past). ⚠ AND IT IS NOT CLIENT-DRIVABLE — `radome_slope` is not a slice-28 knob — so
        # it lives here rather than in `slice28_verify.gd` (the slice-27 precedent: its α_max
        # isolation lives in this file because α_max is deliberately not a knob).
        #
        # ⭐ THE PAYLOAD: a radome INSIDE ITS BORESIGHT-ERROR SPEC EVERYWHERE can still ring, because
        # specs are written on `ε` and stability is written on `dε/dlook`.
        L = deg2rad(15.5)                     # the MEASURED median look angle on these arms
        # "matched" is a MEASUREMENT of the shipped kernels, not an assertion about them
        @test radome_slope_curve(0.0, -0.05, 12.0, L) ≈ -0.10 atol = 0.01           # the DERIVATIVE
        @test radome_error_curve(0.0, -0.05, 12.0, L, 0.0)[1] / L ≈ -0.05 atol = 0.01  # the SECANT
        rip = curvefly(radome =  0.0,  ripple = -0.05,   slope_est = 0.0)
        sec = curvefly(radome = -0.05, ripple = nothing, slope_est = 0.0)
        der = curvefly(radome = -0.10, ripple = nothing, slope_est = 0.0)
        @test rip.rms_r > 0.5                 # the CURVE rings
        @test sec.rms_r < 0.10                # a constant matched to its BEND is quiet
        @test der.rms_r > 0.5                 # a constant matched to its SLOPE rings
        @test rip.rms_r > 8 * sec.rms_r       # same bend at the operating point, opposite behaviour
        # ⭐ AND THE CHANNEL SPLIT FALLS OUT OF THE SAME TRIPLE, which is what makes it evidence
        # rather than an observation: a CONSTANT slope gives both channels ONE gain and rings them
        # TOGETHER (measured 0.844 pitch against 0.838 yaw), while the curve puts the two channels at
        # two different points on the same glass and rings only the one with the lead angle.
        @test der.rms_q > 0.5 * der.rms_r
        @test rip.rms_q < 0.25 * rip.rms_r
    end

    @testset "⭐⭐ THE ISOLATION — non-monotone in the GEOMETRY, with the control flat" begin
        # ⚠ THE CONFOUND THIS DEFEATS IS REAL AND WAS MEASURED: a crossing engagement moves the
        # stability boundary ON ITS OWN (constant-R onset |R_crit| ≈ 0.065 crossing vs ≈ 0.05
        # static, WITH NO CURVE ANYWHERE). So "crossing rings, static does not" is partly a claim
        # about crossing engagements. ⇒ HOLD THE GLASS AND SWEEP THE ENGAGEMENT.
        #
        # With k = 12 the slope ripple peaks at look = 15° and returns to R₀ at 30°, so a MONOTONE
        # crossing-speed sweep must go QUIET → RING → QUIET. **A confound cannot produce a
        # non-monotone response to a monotone geometry change.**
        rip  = [curvefly(ripple = -0.05, vy = v).rms_r for v in (0.0, 200.0, 400.0)]
        ctrl = [curvefly(ripple = nothing, vy = v).rms_r for v in (0.0, 200.0, 400.0)]
        @test rip[1] < 0.05                            # slow: the seeker sits near boresight
        @test rip[2] > 0.5                             # mid:  parked on the ripple's steep part
        @test rip[3] < 0.20                            # fast: past the peak, back toward R₀
        @test rip[2] > 8 * rip[1] && rip[2] > 4 * rip[3]
        # THE CONTROL: the same geometry sweep with NO ripple is FLAT and quiet throughout — so the
        # engagement change by itself never rings, and it is the CURVE that the geometry selects
        # from.
        @test all(<(0.05), ctrl)
        @test maximum(ctrl) / minimum(ctrl) < 2.0      # flat, not merely quiet
    end

    @testset "⭐ THE COMPENSATOR: the scalar that works is set by the ENGAGEMENT" begin
        # Slice 27's R̂ is inherited unchanged, and the payload is what it can and cannot buy here.
        # ⚠ THE FIRST VERSION OF THIS CLAIM ("you cannot cancel a function with a scalar") WAS
        # REFUTED AT GATE 0 and must not be re-imported: a scalar tuned to the OPERATING look angle
        # quiets the ring, and it is ALSO safe at boresight (measured across n_pn 8–16 and static
        # Y 2000–6000). The mechanism of that asymmetry is structural — the ripple term
        # `A·(1−cos(k·look))` vanishes IDENTICALLY at look = 0, so `R(0) = R₀` for every amplitude
        # and the boresight engagement cannot see the curve at all.
        # ⇒ what IS true, and is the actionable lesson: characterizing at BORESIGHT is the
        # DANGEROUS choice, because it is exactly right in the one place the loop is never closed.
        bore = curvefly(ripple = -0.05, slope_est = -0.03)    # R̂ = R(0): boresight-correct
        oper = curvefly(ripple = -0.05, slope_est = -0.13)    # R̂ = R(15°): engagement-correct
        @test bore.rms_r > 0.5                                # the natural choice RINGS
        @test oper.rms_r < 0.10                               # the engagement's choice is quiet
        @test bore.rms_r > 8 * oper.rms_r
        # and the SAME engagement-tuned scalar is safe against a STATIC target — the asymmetry,
        # measured rather than assumed away
        @test curvefly(ripple = -0.05, slope_est = -0.13, vy = 0.0).rms_r < 0.05
    end

    @testset "the telemetry keys — shipped as NUMBERS, and 26/27's are NOT redefined" begin
        r = curvefly(ripple = -0.05)
        tel = r.tel_mid                       # ⚠ mid-window, never the CPA frame (see `curvefly`)
        for kk in ("m1.radome_ripple", "m1.radome_slope_az", "m1.radome_slope_el",
                   "m1.radome_residual_az")
            @test haskey(tel, kk) && isfinite(Float64(tel[kk]))
        end
        # ⚠ SLICE 26/27's KEYS KEEP THEIR MEANINGS — `radome_slope` is still the BORESIGHT slope
        # and `radome_residual` is still `R₀ − R̂`, so a 26/27 wire reads the numbers it always did.
        # The look-angle quantities are ADDED beside them, never substituted into them.
        @test Float64(tel["m1.radome_slope"]) ≈ -0.03 atol = 1e-15
        @test Float64(tel["m1.radome_residual"]) ≈ 0.0 atol = 1e-15
        # ⭐ THE TWO CHANNEL GAINS ARE DIFFERENT NUMBERS — the channel split, in telemetry. The
        # lead is in AZIMUTH, so the yaw channel sits well off the boresight slope while the pitch
        # channel sits ON it. ⚠ These are PER-AXIS gains, not an aggregate over the total
        # off-boresight angle: that third quantity is the gain of NEITHER channel (advisor).
        for kk in ("m1.radome_slope_az", "m1.radome_slope_el")
            @test -0.13 - 1e-9 ≤ Float64(tel[kk]) ≤ -0.03 + 1e-9
        end
        @test r.slope_el ≈ -0.03 atol = 5e-3            # pitch channel: ON the boresight slope
        @test r.slope_az < -0.05                        # yaw channel:   well OFF it
        @test abs(r.slope_az - r.slope_el) > 0.03       # …and they are genuinely two numbers
        # and the residual that closes the RINGING loop is the azimuth one
        @test abs(Float64(tel["m1.radome_residual_az"])) > 0.01
        # a no-ripple wire ships NONE of them (the never-stale discipline; 26/27 byte-identical)
        tel0 = curvefly(ripple = nothing).tel_mid
        @test haskey(tel0, "m1.radome_eps")                    # …the radome IS live
        for kk in ("m1.radome_ripple", "m1.radome_slope_az", "m1.radome_slope_el",
                   "m1.radome_residual_az")
            @test !haskey(tel0, kk)
        end
    end

    @testset "an absurd ripple never crashes a tick (live-slider guard, convention 5/6)" begin
        # A declared knob must be crash-safe over ANY value a slider can produce, and `k` must be
        # floored at the consumer as well as validated at load (`ripple/k` at k = 0 divides).
        for (A, kk) in ((-1.0e6, 12.0), (1.0e6, 12.0), (-0.05, 1.0e-12), (-0.05, 1.0e6), (0.0, 12.0))
            r = curvefly(T = 2.0, ripple = A, k = kk)
            for (_, v) in r.w.env[:telemetry]
                v isa Real && @test isfinite(Float64(v))
            end
        end
    end

    @testset "loader: the ripple is PRESENCE-gated (a slice-27 wire cannot grow one)" begin
        base = joinpath(@__DIR__, "..", "..", "scenarios")
        scn27 = load_scenario(joinpath(base, "slice27_radome_comp.yaml"))
        m27 = first(e for (_, e) in scn27.world.entities if e.kind === :missile)
        @test !haskey(m27.comp, :radome_ripple)
        @test !haskey(m27.comp, :radome_ripple_k)
    end
end

@testset "THE SCHEDULED COMPENSATOR wired (slice 29 — evaluated at its OWN bent index)" begin
    dt = 1.0e-3
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

    # Slice 28's wire with TWO changes, both measured decisions:
    #
    #  (1) THE SCHEDULE keys (`radome_ripple_est` / `radome_ripple_k_est`) — the new authored pair.
    #      `ripple_est === nothing` mints NO key: the byte-identity arm, and the shape the loader
    #      and the seam both gate on.
    #  (2) THE GLASS IS DEEPENED, A = −0.05 → −0.15 (AUTHORED). ⚠ THE GEOMETRY IS UNCHANGED and
    #      that is itself a gate-0 result: on a settled PN collision course the lead angle is
    #      CONSTANT BY CONSTRUCTION (V_M·sin L = V_T·sin aspect), so slice 28's wire holds look_az
    #      to a 0.2° band — and opening that band with a maneuvering target does NOT license a
    #      schedule, because the best POST-HOC scalar then matches it (1.06 / 0.97 / 1.07 / 1.40×;
    #      the parasitic loop needs DWELL at a supercritical residual, and a band the engagement
    #      SWEEPS THROUGH is visited briefly everywhere). ⇒ the frozen look angle is the ENABLING
    #      condition, not an obstacle. −0.15 is what gives the k̂ tolerance band an interior
    #      (`docs/plans/slice29.md` §1, §5).
    function sched_world(; radome = -0.03, ripple = -0.15, k = 12.0, slope_est = -0.03,
                           ripple_est = -0.15, k_est = 10.0,
                           vy = 200.0, axes = :az_el, airframe = :six_dof, seed = 29,
                           sigma = 5.0e-5, rho = 1.0, alpha_max = 0.3, n_pn = 8.0, Y = 2000.0)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => airframe,
                                                 :seeker => :filtered, :seeker_axes => axes))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => rho,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => n_pn, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => sigma, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        radome    === nothing || (comp[:radome_slope] = radome)
        slope_est === nothing || (comp[:radome_slope_est] = slope_est)
        if ripple !== nothing
            comp[:radome_ripple] = ripple; comp[:radome_ripple_k] = k
        end
        if ripple_est !== nothing
            comp[:radome_ripple_est] = ripple_est; comp[:radome_ripple_k_est] = k_est
        end
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, Y, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0), comp = Dict{Symbol,Any}())
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # THE METRIC IS SLICE 28's, UNCHANGED AND FOR ITS REASONS: `rms r` (YAW — the lead is in
    # azimuth) in the RANGE BAND [500, 3000] m (a crossing wire's whole-approach rms r carries a
    # legitimate front-loaded baseline; arms with different ToF would compare different parts of
    # the engagement). rms, NEVER the peak; the MISS is not the metric — every arm here HITS.
    function schedfly(; T = 16.0, kw...)
        w, s = sched_world(; kw...)
        qs = Float64[]; rs_ = Float64[]; rr = Float64[]
        res = Float64[]; mde = Float64[]; slp = Float64[]; lkt = Float64[]; lke = Float64[]
        rmin, prev, closing = Inf, Inf, true
        dsat = 0; asat = 0; nt = 0
        for _ in 1:round(Int, T / dt)
            tick!(w, s, dt); empty!(w.events)
            tel = w.env[:telemetry]
            r = n3(w.entities[:t1].pos - w.entities[:m1].pos)
            push!(qs, Float64(get(tel, "m1.omega_q", 0.0)))
            push!(rs_, Float64(get(tel, "m1.omega_r", 0.0)))
            push!(rr, r)
            push!(res, Float64(get(tel, "m1.radome_residual_az", NaN)))
            push!(mde, Float64(get(tel, "m1.radome_model_err_az", NaN)))
            push!(slp, Float64(get(tel, "m1.radome_sched_slope", NaN)))
            push!(lkt, Float64(get(tel, "m1.look_angle", NaN)))
            push!(lke, Float64(get(tel, "m1.look_angle_est", NaN)))
            # ⚠ COUNTED INSIDE THE MEASUREMENT WINDOW ONLY, and that is not bookkeeping: the fin
            # DOES peg during the launch transient on every arm, so a whole-flight count would make
            # the isolation below fail everywhere and say nothing. Measured: 0 in-window on every
            # arm of the k̂ and Â sweeps; nonzero pre-window on all of them.
            (500.0 < r < 3000.0) &&
                (dsat += Int(Float64(get(tel, "m1.defl_sat", 0.0)) != 0.0);
                 asat += Int(Float64(get(tel, "m1.aero_sat", 0.0)) != 0.0))
            nt += 1
            closing && r > prev && (closing = false)
            closing && (rmin = min(rmin, r)); prev = r
            closing || break
        end
        win = findall(x -> 500.0 < x < 3000.0, rr)
        rms(v) = isempty(win) ? 0.0 : sqrt(sum(abs2, v[win]) / length(win))
        med(v) = (u = sort(filter(isfinite, v[win])); isempty(u) ? NaN : u[(length(u) + 1) ÷ 2])
        return (rms_r = rms(rs_), rms_q = rms(qs), miss = rmin,
                res_med = med(res), mde_med = med(mde), slope_med = med(slp),
                look_t = med(lkt), look_e = med(lke),
                dsat = dsat, asat = asat, nt = nt, nwin = length(win), w = w)
    end

    @testset "BYTE-IDENTITY — no `radome_ripple_est` key ⇒ the slice-27/28 path, bit-for-bit" begin
        # The structural claim at a FOURTH nesting level (the slice-20/21/26/27/28 shape): the
        # no-schedule arm calls `radome_compensation` VERBATIM, it does not evaluate the scheduled
        # kernel at amplitude zero. `x + 0.0` is not the identity at x = −0.0 and float addition is
        # not associative.
        function trace(; kw...)
            w, s = sched_world(; kw...)
            out = Float64[]
            for _ in 1:900
                tick!(w, s, dt); empty!(w.events)
                m = w.entities[:m1]
                append!(out, (m.pos[1], m.pos[2], m.pos[3], m.vel[1], m.vel[2], m.vel[3]))
            end
            return out
        end
        base = trace(ripple_est = nothing)
        @test trace(ripple_est = nothing) == base              # determinism, and the control
        # ⭐ Â = 0 IS BIT-IDENTICAL TO THE KEY NOT EXISTING — the schedule collapses to slice 27's
        # SCALAR. That is the knob-vs-rung discriminator (atmosphere.jl's: the off-state is
        # knob-REACHABLE), MEASURED as slices 26/28 measured theirs, not argued.
        @test trace(ripple_est = 0.0) == base
        @test trace(ripple_est = 0.0, k_est = 3.7) == base      # …and k̂ is INERT at Â = 0
        @test trace(ripple_est = -0.15) != base                 # …PAIRED with a does-schedule arm
        @test trace(ripple_est = -0.15, k_est = 17.0) !=
              trace(ripple_est = -0.15, k_est = 10.0)           # k̂ moves the path too
    end

    @testset "DRAW-COUNT INVARIANCE — class 4a, and it is ASSERTED not assumed" begin
        # The schedule is arithmetic on state that already exists: the same draws per tick either
        # way. A draw-topology flip would desync replay (convention 3), so this is pinned rather
        # than inferred from "we added no `randn` call".
        function endrng(; kw...)
            w, s = sched_world(; kw...)
            for _ in 1:400
                tick!(w, s, dt); empty!(w.events)
            end
            return copy(w.rng)
        end
        r0 = endrng(ripple_est = nothing)
        @test endrng(ripple_est = -0.15, k_est = 10.0) == r0
        @test endrng(ripple_est = -0.15, k_est = 22.0) == r0
        @test endrng(ripple_est = -0.30, k_est = 6.0)  == r0
    end

    @testset "⭐⭐ THE CROSSOVER — the RINGING schedule is the BETTER model of the glass" begin
        # THE SLICE, AS FOUR NUMBERS THE CORE SHIPS. `radome_model_err_az` is the belief compared
        # with the glass AT THE SAME LOOK ANGLE — what an engineer computes on the bench, and what
        # "how good is my schedule?" naturally means. `radome_residual_az` is the belief compared
        # with the glass where the compensator ACTUALLY EVALUATES IT: at its own index, formed from
        # the BENT measurement. The two ORDERINGS ARE REVERSED, and the outcome follows the second.
        ring  = schedfly(k_est = 10.0)      # the shipped arm
        cure  = schedfly(k_est = 12.0)      # the belief matched to the glass
        quiet = schedfly(k_est = 17.0)      # a much WORSE model that stays quiet

        @test ring.rms_r > 0.30                                 # it RINGS
        @test quiet.rms_r < 0.05                                # it does NOT
        @test ring.rms_r / quiet.rms_r > 20.0                   # …by a wide margin

        # ⭐ THE MODEL-ERROR ORDERING: the ringing arm is the BETTER model, several times over.
        @test abs(ring.mde_med) < abs(quiet.mde_med)
        @test abs(quiet.mde_med) / abs(ring.mde_med) > 3.0
        # ⭐⭐ AND THE LOOP-RESIDUAL ORDERING IS THE OPPOSITE — which is the whole slice. ⚠ Compared
        # LIKE WITH LIKE: both are `radome_residual_az`, both index-shifted. Setting one arm's
        # index-shifted value against another's model error would prove nothing.
        @test abs(ring.res_med) > abs(quiet.res_med)
        @test abs(ring.res_med) / abs(quiet.res_med) > 3.0
        # ⭐ AND A PERFECT MODEL DOES NOT GIVE A ZERO LOOP RESIDUAL. `k̂ = k` and `Â = A` make the
        # model error EXACTLY zero, and the loop still sees a residual, because the belief is still
        # evaluated 2.4–2.7° off. The cleanest single statement of the slice.
        @test abs(cure.mde_med) < 1e-12                         # the model is EXACT…
        @test abs(cure.res_med) > 0.01                          # …and the loop residual is NOT zero
        @test cure.rms_r < 0.05                                 # (it is still comfortably quiet)

        # ⚠ THE ORDERING CLAIM IS ON MEDIANS, WHICH IS LEGITIMATE ONLY BECAUSE THE `mde`/`res` PAIR
        # COME FROM THE SAME TICKS. A residual quoted as a median on a RINGING arm describes the
        # ring, not its cause (slice 28 §1's rule; this slice's draft violated it and an advisor
        # pass caught it) — so the ring/quiet VERDICT is on `rms r`, never on a residual threshold,
        # and the residual is used only for the ORDERING BETWEEN arms.
        @test ring.nwin > 200 && quiet.nwin > 200               # both windows are real

        # THE ISOLATION, AND IT IS SLICE 26's SHAPE — NOT SLICE 25's (the copy-paste false-claim
        # trap). `defl_sat == 0` in-window on every arm, so the fourth cap (slice 15's DEFLECTION
        # limit) is nowhere near this: the difference between the arms is the guidance loop, not a
        # fin running out of travel. ⚠ But `aero_sat == 0` is IMPOSSIBLE on a ringing arm and must
        # NOT be asserted — an oscillation drives demand into the slice-19 ceiling BY DEFINITION
        # (slice 26's own finding). Measured here: 584/4342 in-window on the ringing arm against
        # 0/4360 on the cured one. The ceiling BOUNDS the cycle; the belief decides whether there
        # is one.
        @test ring.dsat == 0 && quiet.dsat == 0 && cure.dsat == 0
        @test cure.asat == 0 && quiet.asat == 0                # the quiet arms never touch it…
        @test ring.asat > 0                                    # …and the ringing one must
    end

    @testset "⭐ THE INDEX IS REAL AND IT IS THE BEND — `look_angle_est` vs `look_angle`" begin
        # The mechanism as a number: the compensator's own look angle runs BELOW the truth one, and
        # the gap IS the bend it is correcting. Slice 27's discipline made visible — the compensator
        # never reads truth, and this is what that costs.
        r = schedfly(k_est = 12.0)
        @test isfinite(r.look_t) && isfinite(r.look_e)
        @test r.look_t - r.look_e > 1.0                         # degrees — a real, sizeable gap
        @test r.look_t - r.look_e < 6.0                         # …and not a wild one
        # NO GLASS ⇒ NO BEND ⇒ NO INDEX ERROR. The paired control that makes the gap ABOUT the
        # radome rather than about seeker noise or the attitude.
        flat = schedfly(radome = 0.0, ripple = 0.0, k_est = 12.0)
        @test abs(flat.look_t - flat.look_e) < 0.2
    end

    @testset "the k̂ TOLERANCE BAND is CONNECTED and ASYMMETRIC (⇒ a knob, unlike slice 28's k)" begin
        # ⚠ SLICE 28 DISQUALIFIED THE GLASS's `k` FOR NON-MONOTONICITY (quiet/rings/rings/marginal/
        # QUIET/rings). The BELIEF's `k̂` is a DIFFERENT MEASUREMENT and comes out differently: one
        # CONNECTED quiet window about the truth, which a student can walk. Do not copy 28's
        # disqualification across — it was measured on the other side of the comparison.
        rings(k̂) = schedfly(k_est = k̂).rms_r > 0.30
        for k̂ in (6.0, 9.0, 10.0)               ; @test  rings(k̂); end   # BELOW: rings
        for k̂ in (11.0, 12.0, 14.0, 17.0, 19.0) ; @test !rings(k̂); end   # the quiet window
        for k̂ in (20.0, 22.0)                   ; @test  rings(k̂); end   # ABOVE: rings again
        # ⭐ THE ASYMMETRY IS THE LESSON: the quiet window is far wider ABOVE the truth than below.
        # Under-estimate `k̂` by 15% (12 → 10) and it rings; over-estimate by 58% (12 → 19) and it
        # does not.
        @test !rings(19.0) && rings(10.0)
        # BOTH DECLARED ENDPOINTS RING UNAMBIGUOUSLY (slice 26's post-commit rule: measure the
        # declared endpoints, don't infer them from the interior — it moved this ceiling off 20,
        # where `rms r` is only ≈0.47, a marginal edge).
        @test schedfly(k_est = 6.0).rms_r  > 0.6
        @test schedfly(k_est = 22.0).rms_r > 0.6
    end

    @testset "the Â knob — MONOTONE, and over-estimation is the SAFE side (one-sidedness)" begin
        # ⭐⭐ THE CONSTRAINT IS ONE-SIDED — slice 26's finding, used here as a design rule for the
        # first time: only a NEGATIVE residual rings, a POSITIVE one merely de-tunes. So the LEVEL
        # half of the belief has a safe direction, and the metric walks monotonically toward it.
        r0  = schedfly(ripple_est = 0.0,   k_est = 12.0)
        r13 = schedfly(ripple_est = -0.13, k_est = 12.0)
        r15 = schedfly(ripple_est = -0.15, k_est = 12.0)
        r20 = schedfly(ripple_est = -0.20, k_est = 12.0)
        r30 = schedfly(ripple_est = -0.30, k_est = 12.0)
        @test r0.rms_r  > 0.6                     # Â = 0 IS slice 27's scalar, and it rings hard
        @test r13.rms_r > 0.30                    # under-estimating still rings
        @test r15.rms_r < 0.05                    # the truth is quiet
        # OVER-estimating is SAFE and gently degrading — never a ring.
        @test r20.rms_r < 0.05 && r30.rms_r < 0.10
        @test r15.rms_r < r20.rms_r < r30.rms_r   # monotone on the safe side
        # ⭐ AND `radome_sched_slope` IS EXACTLY ZERO AT Â = 0 — the schedule has no slope, which is
        # why slice 27's scalar never had to choose an index. The knob-vs-rung fact, on the wire.
        @test abs(r0.slope_med) < 1e-15
        @test abs(r15.slope_med) > 0.1            # …PAIRED with a does-slope arm
    end

    @testset "INERT without its host, and no live knob can crash a tick (conventions 5/6)" begin
        # RUNG-GATED on the LIVE `:airframe`, never on `haskey(:att_q)` — the slice-21/23/26/27/28
        # latent-bug class, whose SIXTH occurrence this would be. Under `:pitch_coupled` there is no
        # 6-DOF attitude to look through, so the schedule's keys must be absent entirely.
        r = schedfly(T = 2.0, airframe = :pitch_coupled)
        @test !haskey(r.w.env[:telemetry], "m1.radome_sched_slope")
        @test !haskey(r.w.env[:telemetry], "m1.radome_model_err_az")

        # ⚠⚠ THE OTHER BRANCH COMBINATION, AND IT IS THE ONE WITH NO NATURAL PROOF (advisor): a
        # SCHEDULE LIVE WITH NO GLASS. `_sched_on` does NOT imply `_rad_on` — compensating for glass
        # you do not have is a REAL configuration (slice 27's docstring, and it de-tunes rather than
        # no-ops), and in it `R_rad`/`A_rip`/`k_rip`/`look_az` are the else-arm ZEROS. So the two
        # COMPARISON keys must be ABSENT rather than shipping a plausible number computed from a
        # stale zeroed look angle — the slice-21 `_atm_on` / slice-23 stale-readout class, whose
        # SIXTH occurrence this would be. ⭐ The two keys go together: `radome_model_err_az` carries
        # the SAME `_ripple_on` gate as `radome_residual_az`, so a lone half can never reach the HUD.
        let n = schedfly(T = 2.0, radome = nothing, ripple = nothing)
            tel = n.w.env[:telemetry]
            @test !haskey(tel, "m1.radome_model_err_az")     # no glass ⇒ no comparison…
            @test !haskey(tel, "m1.radome_residual_az")      # …and its slice-28 twin, together
            # …while the BELIEF-ONLY readouts DO ship, because they are well defined without glass:
            # the compensator exists, it has a slope, and it has a real (bent-free) index.
            @test haskey(tel, "m1.radome_sched_slope")
            @test haskey(tel, "m1.look_angle_est")
            @test isfinite(Float64(tel["m1.radome_sched_slope"]))
            # and slice 27's hardware residual still reports −R̂₀, which is CORRECT and documented
            # (the true slope defaults to 0 because there is no radome)
            @test Float64(tel["m1.radome_residual"]) ≈ 0.03 atol = 1e-12
        end
        # every live knob value keeps the wire finite (convention 6 — no Inf/NaN to JSON)
        for (Â, k̂) in ((-1.0e6, 12.0), (1.0e6, 12.0), (-0.15, 0.0), (-0.15, -5.0),
                       (-0.15, 1.0e6), (0.0, 12.0))
            rr = schedfly(T = 2.0, ripple_est = Â, k_est = k̂)
            for (_, v) in rr.w.env[:telemetry]
                v isa Real && @test isfinite(Float64(v))
            end
        end
    end

    @testset "loader: the schedule is PRESENCE-gated, and refuses to hang on nothing" begin
        base = joinpath(@__DIR__, "..", "..", "scenarios")
        for f in ("slice26_radome.yaml", "slice27_radome_comp.yaml", "slice28_radome_curve.yaml")
            scn = load_scenario(joinpath(base, f))
            m = first(e for (_, e) in scn.world.entities if e.kind === :missile)
            @test !haskey(m.comp, :radome_ripple_est)
            @test !haskey(m.comp, :radome_ripple_k_est)
        end
        scn29 = load_scenario(joinpath(base, "slice29_radome_schedule.yaml"))
        m29 = first(e for (_, e) in scn29.world.entities if e.kind === :missile)
        @test m29.comp[:radome_ripple_est]   == -0.15
        @test m29.comp[:radome_ripple_k_est] == 10.0
        @test m29.comp[:radome_ripple]       == -0.15      # the GLASS is deeper than slice 28's
        @test m29.comp[:radome_ripple_k]     == 12.0       # …and its k is still AUTHORED
    end
end

@testset "THE ENGAGEMENT AXIS in the radome loop (slice 30 — the crossing-speed knob)" begin
    dt = 1.0e-3

    # Slice 29's wire, with the target's crossing speed moved OFF the authored `vel` and ONTO the
    # `cross_speed_mps` comp key the mover pins (radar.jl `integrate!`). That is the whole enabling
    # change of slice 30: the ENGAGEMENT — which sets the sustained lead, hence the look angle at
    # which the glass is sampled — becomes a knob a client can drag. `cross === nothing` mints NO
    # key and authors `vel_y` directly: the byte-identity reference.
    # `Rhat`/`A` are the compensator's belief and the glass's ripple amplitude — the two knobs the
    # gate-2 wire teeth move (the aim point `R₀+2A` is a function of `A`, so the fixture must be able
    # to change the glass without re-authoring the whole comp bag).
    function eng_world(; vy = 200.0, cross = nothing, seed = 30, Rhat = -0.03, A = -0.15)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => :six_dof,
                                                 :seeker => :filtered, :seeker_axes => :az_el))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.3, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 8.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => 5.0e-5, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true,
                                :radome_slope => -0.03, :radome_ripple => A,
                                :radome_ripple_k => 12.0, :radome_slope_est => Rhat)
        # `vy` (AUTHORED on `vel`) and `cross` (PINNED on the comp key) are INDEPENDENT here on
        # purpose: the two must be free to DISAGREE, because an equal-value pair cannot see the
        # ordering bug (`docs/plans/slice30.md` gate 1).
        tc = Dict{Symbol,Any}()
        cross === nothing || (tc[:cross_speed_mps] = cross)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 2000.0, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0), comp = tc)
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    @testset "DRAW-COUNT INVARIANCE — class 4a, and it is ASSERTED not assumed" begin
        # A target-velocity pin is arithmetic on state that already exists: the seeker's 2 randn/tick
        # are untouched, at any crossing speed. A draw-topology flip would desync replay (convention
        # 3) — so this is pinned, not inferred from "we added no `randn` call". Comparing the FINAL
        # RNG state is the draw-COUNT assert: a Xoshiro advances by steps taken, not values used.
        function endrng(; kw...)
            w, s = eng_world(; kw...)
            for _ in 1:500
                tick!(w, s, dt); empty!(w.events)
            end
            return copy(w.rng)
        end
        r0 = endrng()
        @test endrng(cross = 0.0)   == r0
        @test endrng(cross = 200.0) == r0
        @test endrng(cross = 400.0) == r0
        @test endrng(cross = -260.0) == r0
    end

    @testset "the pin is BIT-IDENTICAL to the same engagement authored on `vel`" begin
        # The knob-vs-rung discriminator carried onto the FULL missile wire, not just the bare mover
        # (test_radar.jl): pinning the crossing speed the target already flies changes NOTHING, so
        # slice 29's shipped numbers are reachable through the new key — which is what lets slice 30
        # keep 29's geometry and add only an axis.
        function trace(; kw...)
            w, s = eng_world(; kw...)
            out = Float64[]
            for _ in 1:900
                tick!(w, s, dt); empty!(w.events)
                m = w.entities[:m1]; t = w.entities[:t1]
                append!(out, (m.pos[1], m.pos[2], m.pos[3], m.vel[1], m.vel[2], m.vel[3],
                              t.pos[1], t.pos[2], t.pos[3]))
            end
            return out
        end
        base = trace()                                       # vy = 200 authored on `vel`, NO key
        @test trace() == base                                # determinism, and the control
        @test trace(vy = 200.0, cross = 200.0) == base       # the pin AT the authored value: EXACT
        @test trace(vy = 200.0, cross = 0.0)   != base       # …PAIRED with arms that DO move it
        @test trace(vy = 200.0, cross = 400.0) != base
        # ⭐⭐ THE ORDERING, on the real missile wire — the DISAGREEING pairs, both directions.
        # A target authored at REST and pinned to 200 must be the same run as one authored at 200:
        # pinned AFTER the `pos` update, tick 1 would advance y on the AUTHORED value (0 here, 200
        # there) and the two would part by 0.2 m forever, while the equal-value test above still
        # passed. And the mirror: authored 200, pinned to rest, must equal a target authored at rest.
        @test trace(vy = 0.0, cross = 200.0) == base
        @test trace(vy = 200.0, cross = 0.0) == trace(vy = 0.0)
    end

    # ------------------------------------------------------------------ gate 2: the wire ----------
    # Run `n` ticks and hand back the telemetry dict of the LAST one (convention 10: every number
    # below is pinned against the ACTUAL build_env!→observe!→decide! path, never a hand-recompute).
    function tel_after(n; drop = Symbol[], kw...)
        w, s = eng_world(; kw...)
        for k in drop; delete!(w.entities[:m1].comp, k); end
        for _ in 1:n
            tick!(w, s, dt); empty!(w.events)
        end
        return w.env[:telemetry]
    end

    @testset "⭐ THE AIM POINT ON THE WIRE — `radome_slope_worst`, and it is a `min`" begin
        # Slice 30 ships ONE new radome number: the most negative local slope the glass reaches
        # ANYWHERE (`min(R₀, R₀+2A)`, frames.jl `radome_slope_worst`) — the value the one-sided design
        # rule aims a scalar `R̂` at. It is shipped as a NUMBER because the client must not evaluate
        # the curve (convention 13, the slice-21 `rho_air` / slice-28 `radome_slope_az` precedent),
        # and because dragging `A` MOVES the rule's own target: a HUD that showed only `R̂` would let
        # a student deepen the glass and silently invalidate the scalar they had already set.
        for (A, want) in ((-0.15, -0.03 + 2 * -0.15), (-0.20, -0.03 + 2 * -0.20),
                          (-0.05, -0.03 + 2 * -0.05), (0.0, -0.03))
            @test tel_after(50; A = A)["m1.radome_slope_worst"] === want
        end
        # ⚠⚠ THE `min`, ON THE WIRE. A POSITIVE amplitude is a meaningful configuration here (positive
        # slopes DE-TUNE rather than ring — slice 26), and there `R₀+2A` is the most POSITIVE slope:
        # the maximally de-tuned aim point, which would INVERT the rule. The shipped key stays `R₀`.
        @test tel_after(50; A = +0.15)["m1.radome_slope_worst"] === -0.03
        @test tel_after(50; A = +0.15)["m1.radome_slope_worst"] != -0.03 + 2 * 0.15

        # ⭐ IT IS A PROPERTY OF THE GLASS, NOT OF THE ENGAGEMENT — the DISCRIMINATING PAIR, and the
        # reason it is a second key rather than a relabelling of slice 28's `radome_slope_az`. The
        # crossing speed moves WHERE the seeker looks, so `radome_slope_az` (the slope THERE) moves
        # with it; the worst case over the whole curve cannot. That split is the whole one-sidedness
        # argument: the rule needs no knowledge of the engagement, which is exactly why it holds
        # across an envelope.
        let a = tel_after(1500; cross = 0.0), b = tel_after(1500; cross = 300.0)
            @test a["m1.radome_slope_worst"] === b["m1.radome_slope_worst"]
            @test a["m1.radome_slope_az"]    != b["m1.radome_slope_az"]
        end

        # NEVER-STALE, both gates: no ripple is a slice-26/27 wire (the glass HAS no curve, and
        # `radome_slope` already ships its only slope), no radome at all is a slice-25 wire.
        @test !haskey(tel_after(50; drop = [:radome_ripple, :radome_ripple_k]), "m1.radome_slope_worst")
        @test  haskey(tel_after(50; drop = [:radome_ripple, :radome_ripple_k]), "m1.radome_slope")
        @test !haskey(tel_after(50; drop = [:radome_slope, :radome_ripple, :radome_ripple_k]),
                      "m1.radome_slope_worst")
        # ⚠ ADDITIVE, NOT byte-identical: slices 28 and 29 DO author a ripple, so their wires GROW
        # this key. Trajectory and RNG stay bit-identical (telemetry is write-only) — the precise
        # claim is stated here rather than left as "byte-identity on the wire".
        @test haskey(tel_after(50), "m1.radome_slope_worst")

        # conventions 5/6 — a live slider can neither crash a tick nor ship a non-finite. `A` is
        # load-validated finite only, and the SIGNED clamp is `_finite_coord` (`_finite` bounds only
        # from above and would let a huge NEGATIVE reach the JSON — the slice-29 `k̂` catch).
        # ⚠⚠ AND THE ASSERT COVERS THE WHOLE WIRE, NOT JUST THE NEW KEY (advisor). Convention 5 is
        # "no throw inside a tick" and convention 6 is "no Inf/NaN to JSON" — a single-key clamp
        # assert can pass while the SAME absurd amplitude NaNs its neighbours, since it also flows
        # into `radome_error_curve`, bends the LOS by an absurd amount, and reaches `look_angles`
        # through the attitude. Measured finite at both signs of A and of R̂ (`probe11_absurd_knobs`).
        for kw in ((; A = -1.0e12), (; A = +1.0e12), (; Rhat = -1.0e12))
            t = tel_after(50; kw...)
            ks = [k for k in keys(t) if occursin("radome", k) || occursin("look", k) ||
                                        occursin("omega_ratio", k)]
            @test length(ks) ≥ 12                       # the set is really there to be checked
            @test all(k -> t[k] isa Real && isfinite(t[k]), ks)
        end
        @test tel_after(50; A = -1.0e12)["m1.radome_slope_worst"] == -FINITE_CEIL
        @test tel_after(50; A = +1.0e12)["m1.radome_slope_worst"] === -0.03   # …the `min` again
    end

    @testset "the ENGAGEMENT LABEL on the wire — `cross_speed_mps`, sign and all" begin
        # The HUD must be able to say which ENGAGEMENT is being flown, not only what the radome
        # believes — the crossing speed IS the new axis. Published from the phase-4 `decide!` block
        # that already owns engagement geometry (`los_range`/`closing_speed`/`range_rate`), not from
        # the seeker: a target's crossing speed is not a sensor quantity, and siting it there would
        # couple it to the `:seeker_axes` host for no reason.
        @test tel_after(50; cross = 200.0)["m1.cross_speed_mps"] === 200.0
        @test tel_after(50; cross = 0.0)["m1.cross_speed_mps"]   === 0.0
        # ⚠ SIGNED, and the loader deliberately declines to forbid it: a negative crossing flies the
        # MIRROR engagement. `_finite_coord`, so this survives the clamp with its sign.
        @test tel_after(50; cross = -260.0)["m1.cross_speed_mps"] === -260.0
        # PRESENCE-gated on the TARGET's own comp key — and it ships the KNOB VALUE, never
        # `tgt.vel[2]`, which would grow a key on every slice-1..29 wire and would report the
        # authored velocity of a target that carries no pin at all.
        @test !haskey(tel_after(50; vy = 200.0), "m1.cross_speed_mps")
        @test  haskey(tel_after(50; vy = 0.0, cross = 200.0), "m1.cross_speed_mps")
        # NEVER-STALE past impact — and unlike the zeroed engagement keys beside it, this one does
        # not go stale: the target keeps crossing at the speed the knob says. So it is published
        # ABOVE the no-target/impacted early return, and BOTH arms ship it exactly once.
        let (w, s) = eng_world(cross = 200.0)
            for _ in 1:50; tick!(w, s, dt); empty!(w.events); end
            w.entities[:m1].comp[:impacted] = true
            tick!(w, s, dt)
            @test w.env[:telemetry]["m1.cross_speed_mps"] === 200.0
            @test w.env[:telemetry]["m1.a_cmd"] === 0.0          # the paired never-stale ZERO
        end
        # conventions 5/6 — a live slider at an absurd magnitude ships finite, clamped, SIGNED, and
        # (advisor) leaves the REST of the wire finite too: a target at 1e12 m/s drives the look
        # angle to ~90° within a few ticks, which is the neighbouring keys' worst case, not this
        # key's. Measured at both signs.
        @test tel_after(50; cross = -1.0e12)["m1.cross_speed_mps"] == -FINITE_CEIL
        @test tel_after(50; cross = +1.0e12)["m1.cross_speed_mps"] ==  FINITE_CEIL
        for v in (-1.0e12, +1.0e12)
            t = tel_after(50; cross = v)
            @test all(k -> t[k] isa Real && isfinite(t[k]),
                      [k for k in keys(t) if occursin("radome", k) || occursin("look", k)])
        end
    end

    @testset "⭐ THE VERDICT SURVIVES A SECOND SEED (the headline is a ring COUNT)" begin
        # ⚠ LOAD-BEARING, NOT HYGIENE (advisor). Slice 30's headline is a RING COUNT over an
        # envelope (6/7 → 0/7), so a single cell flipping on a different seed would change the
        # published number — unlike a ratio, a count has no tolerance to absorb it. Class 4a means
        # the seed is live (5th consecutive slice), so this is asserted rather than assumed: slice
        # 26 measured self-excitation at `σ_seek = 0`, but that is 26's measurement, not this one's.
        #
        # Only the two MARGINAL cells are teeth — the largest QUIET arm under the worst-case scalar
        # and the smallest RINGING arm under the boresight one. They bracket the transition; the
        # other twelve arms of the envelope are probe territory (`probe9_gate2.jl`, which runs all
        # 14 on the scenario wire and reproduces gate 0's emulated numbers to the digit).
        WORST = -0.03 + 2 * -0.15                     # the aim point the shipped key carries
        function rms_r_in_band(; kw...)
            w, s = eng_world(; kw...)
            acc = 0.0; n = 0
            for _ in 1:12000
                tick!(w, s, dt); empty!(w.events)
                m = w.entities[:m1]; t = w.entities[:t1]
                d = t.pos - m.pos; r = sqrt(d[1]^2 + d[2]^2 + d[3]^2)
                # the RANGE BAND (slice 28's window): a crossing wire's rms r has a legitimate
                # front-loaded baseline, and arms with different ToF would otherwise compare
                # different parts of the engagement. Stop at the low edge — the endgame is outside.
                r < 500.0 && break
                r < 3000.0 || continue
                acc += get(m.comp, :omega_body, Vec3(0.0, 0.0, 0.0))[3]^2; n += 1
            end
            return sqrt(acc / n)
        end
        # the QUIET margin cell: vy = 200 under the worst-case scalar (the largest of the seven)
        q30 = rms_r_in_band(cross = 200.0, Rhat = WORST, seed = 30)
        q42 = rms_r_in_band(cross = 200.0, Rhat = WORST, seed = 4242)
        # the RING margin cell: vy = 80 under the boresight scalar (the smallest of the six)
        g30 = rms_r_in_band(cross = 80.0, Rhat = -0.03, seed = 30)
        g42 = rms_r_in_band(cross = 80.0, Rhat = -0.03, seed = 4242)
        @test q30 ≈ 0.0588 atol = 2e-3
        @test q42 ≈ 0.0588 atol = 2e-3
        @test g30 ≈ 0.8546 atol = 5e-3
        @test g42 ≈ 0.8546 atol = 5e-3
        # the VERDICT (the 0.30 line), at BOTH seeds — the assert the ring count is made of
        @test q30 < 0.30 && q42 < 0.30
        @test g30 > 0.30 && g42 > 0.30
        # ⭐ AND THE MARGIN IS THE POINT: the two arms differ from EACH OTHER by ~14.5×, while each
        # moves under 1% with the seed. The verdict gap is orders above the seed sensitivity, which
        # is what makes a COUNT a legitimate headline on a noisy plant.
        @test abs(q30 - q42) < 0.005
        @test abs(g30 - g42) < 0.005
        @test g30 / q30 > 10.0
    end

    @testset "the SHIPPED WIRE: the engagement is a knob, and the compensator is a SCALAR" begin
        # Gate 3's own tooth (the slice-29 "loader: PRESENCE-gated" precedent). The scenario file IS
        # the deliverable here, so the properties the verifier's handshake gate asserts on the WIRE
        # are asserted on the FILE too — a doc claim about a gate lives IN the gate.
        base = joinpath(@__DIR__, "..", "..", "scenarios")
        scn = load_scenario(joinpath(base, "slice30_envelope.yaml"))
        m = first(e for (_, e) in scn.world.entities if e.kind === :missile)
        t = first(e for (_, e) in scn.world.entities if e.kind === :target)
        # THE ENGAGEMENT, on the TARGET — and the authored `vel` AGREES with it, which is the
        # knob-vs-rung discriminator (gate 1 measured that pair bit-identical to no key at all).
        @test t.comp[:cross_speed_mps] == 200.0
        @test t.vel[2] == 200.0
        # THE GLASS: slice 29's depth, its k still AUTHORED.
        @test m.comp[:radome_slope]    == -0.03
        @test m.comp[:radome_ripple]   == -0.15
        @test m.comp[:radome_ripple_k] == 12.0
        # ⚠ THE BELIEF IS A SCALAR, DELIBERATELY — no schedule anywhere on this wire. The claim is
        # about what a SCALAR can guarantee across an envelope, so slice 29's keys would confound it
        # (and would route the client to slice 29's HUD branch).
        @test m.comp[:radome_slope_est] == -0.03
        @test !haskey(m.comp, :radome_ripple_est)
        @test !haskey(m.comp, :radome_ripple_k_est)
        # THREE KNOBS — the engagement, the glass and the belief: three terms of ONE quantity (the
        # engagement residual), which is how convention 9 is satisfied here.
        @test length(scn.knobs) == 3
        kk = Dict(kb.key => kb.target for kb in scn.knobs)
        @test kk[:cross_speed_mps]  === :tgt1        # ⭐ on the TARGET, not the interceptor
        @test kk[:radome_ripple]    === :m1
        @test kk[:radome_slope_est] === :m1
        # …and the disqualified levers are ABSENT (they move the loop gain the lesson is about, the
        # level the belief was characterized against, or the cycle's amplitude).
        for bad in (:n_pn, :rho, :radome_slope, :radome_ripple_k, :af_alpha_max, :sigma_seek, :speed)
            @test !haskey(kk, bad)
        end
        # THE PRESENCE GATE, from the other side: no earlier wire in the arc carries the new key, so
        # none of them grows the `cross_speed_mps` readout (slices 1–29 byte-identical).
        for f in ("slice26_radome.yaml", "slice27_radome_comp.yaml", "slice28_radome_curve.yaml",
                  "slice29_radome_schedule.yaml")
            s = load_scenario(joinpath(base, f))
            for (_, e) in s.world.entities
                @test !haskey(e.comp, :cross_speed_mps)
            end
        end
    end
end

@testset "AN IMPERFECT GYRO in the radome loop (slice 31 — two terms, two currencies)" begin
    dt = 1.0e-3

    # Slice 30's wire (its glass, its engagement), with the compensator's GYRO now imperfect. The
    # engagement stays AUTHORED here — slice 31's claim is PER-ENGAGEMENT, and stacking slice 30's
    # envelope axis on top of it would violate convention 9.
    # `s`/`bz`/`by === nothing` mints NO key: that is the byte-identity reference, and the ONLY path
    # slices 25–30 take.
    function gyro_world(; Rhat = -0.27, s = nothing, bz = nothing, by = nothing,
                          A = -0.15, seed = 31)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => :six_dof,
                                                 :seeker => :filtered, :seeker_axes => :az_el))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.3, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 8.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => 5.0e-5, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true,
                                :radome_slope => -0.03, :radome_ripple => A,
                                :radome_ripple_k => 12.0, :radome_slope_est => Rhat)
        s  === nothing || (comp[:gyro_scale_err] = s)
        bz === nothing || (comp[:gyro_bias_z]    = bz)
        by === nothing || (comp[:gyro_bias_y]    = by)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 2000.0, 4200.0),
                                 vel = Vec3(0.0, 200.0, 0.0),
                                 comp = Dict{Symbol,Any}(:cross_speed_mps => 200.0))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # the missile's own body-rate trace, which is what the ring lives in (the slice-26…30 metric)
    function trace(; n = 900, kw...)
        w, sub = gyro_world(; kw...)
        out = Float64[]
        for _ in 1:n
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]
            ω = get(m.comp, :omega_body, zero(Vec3))
            append!(out, (m.pos[1], m.pos[2], m.pos[3], ω[2], ω[3]))
        end
        return out
    end

    @testset "BYTE-IDENTITY — no gyro key ⇒ the slice-25…30 path, bit-for-bit" begin
        # Convention 2, and it is the CENTRAL risk of this seam: slice 31 is a FIFTH nesting level
        # inside `_observe_point3d!`, where a mis-nested else-arm would silently re-route every
        # earlier radome wire. The key-absent path passes the TRUTH rate through a ternary that does
        # NO arithmetic on it — never `gyro_reading(ω, 0, 0)` trusting the zeros (the `-0.0` trap and
        # float non-associativity), so this is bit-for-bit BY CONSTRUCTION and not by cancellation.
        base = trace()
        @test trace() == base                                   # determinism, same-config
        # …and authoring the keys AT THEIR OFF-VALUES is bit-identical TOO, which is the
        # KNOB-not-rung discriminator measured rather than argued (atmosphere.jl's).
        @test trace(s = 0.0)              == base
        @test trace(bz = 0.0)             == base
        @test trace(s = 0.0, bz = 0.0)    == base
        # …and the paired does-differ case, so the equality above is not vacuous.
        @test trace(s = -0.05) != base
        @test trace(bz = 0.01) != base
    end

    @testset "DRAW-COUNT INVARIANCE — class 4a, and it is ASSERTED not assumed" begin
        # Both gyro error terms are DETERMINISTIC: they add no `randn`, at any value. (Gyro NOISE is
        # deferred on exactly this ground — an unconditional third draw would desync every 25–30
        # replay, convention 3.) Comparing the FINAL RNG state is the draw-COUNT assert.
        function endrng(; kw...)
            w, sub = gyro_world(; kw...)
            for _ in 1:500
                tick!(w, sub, dt); empty!(w.events)
            end
            return copy(w.rng)
        end
        r0 = endrng()
        @test endrng(s = -0.40)   == r0
        @test endrng(s = +0.40)   == r0
        @test endrng(s = -1.0)    == r0
        @test endrng(bz = 0.08)   == r0
        @test endrng(bz = -0.08, s = -0.2) == r0
    end

    @testset "⭐ THE REPARAMETERIZATION — a scale factor IS a belief error, exactly" begin
        # The slice's central risk, named by the advisor before any code and MEASURED at gate 0: a
        # common-mode scale factor is common-mode on the feed-forward product, so `(R̂, s)` flies the
        # SAME MISSILE as `(R̂(1+s), perfect gyro)`. That is why the scale-factor half ships as a
        # TOOTH and the slice's claim is a DESIGN RULE — the FALSE-FIDELITY class (slice 15's `k_δ`,
        # slice 16's refused toggle, slice 19's dead `speed`) caught in the open.
        # ⚠ `atol`, NEVER `==`: `R̂·((1+s)·ω)` and `(R̂·(1+s))·ω` differ in the last ULPs by float
        # non-associativity (gate 0: two of five wire pairs came out bit-identical, three did not),
        # so an equality here would be a false claim about the same physics.
        for (Rh, s) in ((-0.27, -0.05), (-0.33, -0.20), (-0.33, +0.10), (-0.45, +0.30))
            a = trace(Rhat = Rh, s = s)
            b = trace(Rhat = Rh * (1 + s))
            @test maximum(abs.(a .- b)) < 1.0e-8            # metres / rad·s⁻¹ over 900 ticks
        end
        # the PAIRED does-differ case: without the rescale the two beliefs are different missiles.
        @test maximum(abs.(trace(Rhat = -0.27, s = -0.05) .- trace(Rhat = -0.27))) > 1.0
    end

    @testset "⭐ THE DEAD GYRO — `s = −1` IS slice 26's uncompensated missile" begin
        # The reading collapses to the bias alone, so the feed-forward vanishes with it and what is
        # left driving the loop is the FULL slope `R − 0`. Bit-exact on the wire (gate-0 P2), not an
        # `atol`: `(1 + (−1))·ω` is exactly zero and `R̂·0.0` is exactly ±0.0, so both arms add the
        # same signed zero.
        for Rh in (-0.03, -0.27, -0.33)
            @test trace(Rhat = Rh, s = -1.0) == trace(Rhat = 0.0)
        end
    end

    # ⚠⚠ THE WINDOW IS THE RANGE BAND, NOT A TICK SLICE, AND THE FIRST DRAFT OF THIS FILE GOT IT
    # WRONG: slice 28 measured that a crossing wire's rms r carries a LEGITIMATE FRONT-LOADED baseline
    # (0.172 whole-approach against 0.0138 in band), so a tick window over the first second reads the
    # launch transient on EVERY arm and every verdict collapses to "0.14". Fly to CPA and window on
    # `r ∈ [500, 3000] m`, exactly as the verifier and gate 0 do — arms with different ToF would
    # otherwise compare different parts of the engagement.
    function flight(; max_t = 25.0, kw...)
        w, sub = gyro_world(; kw...)
        rs = Float64[]; ωr = Float64[]; azt = Float64[]
        r_prev = Inf
        for _ in 1:Int(round(max_t / dt))
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]; t = w.entities[:t1]
            d = t.pos - m.pos; rr = sqrt(d[1]^2 + d[2]^2 + d[3]^2)
            û = los_unit(m.pos, t.pos)
            push!(rs, rr); push!(ωr, get(m.comp, :omega_body, zero(Vec3))[3])
            push!(azt, atan(û[2], û[1]))
            rr > r_prev && break                       # first CPA (the [[ewsim-missile-verifier-
            r_prev = rr                                #  sampling]] discipline)
        end
        win = findall(r -> 500.0 < r < 3000.0, rs)
        azdot = [(azt[i] - azt[i-1]) / dt for i in win if i > 1]
        return (; rms_r = sqrt(sum(abs2, ωr[win]) / length(win)),
                  azdot = sort(azdot)[cld(length(azdot), 2)],      # median, no extra dependency
                  miss = minimum(rs), reached = r_prev < Inf && length(rs) < Int(round(max_t / dt)))
    end

    @testset "⭐⭐ THE TWO CURRENCIES — a scale factor RINGS, a bias does not" begin
        quiet = flight(Rhat = -0.27)                       # the "tightened" aim point, perfect gyro
        ring  = flight(Rhat = -0.27, s = -0.05)            # …and a realistic cheap-MEMS gyro
        @test quiet.reached && ring.reached                # every arm reached CPA (slice 30's rule)
        @test quiet.rms_r < 0.30                           # the slice-28…30 ring threshold
        @test ring.rms_r  > 0.30
        @test ring.rms_r  > 5 * quiet.rms_r                # THE STABILITY CURRENCY
        # THE OTHER CURRENCY: the same sensor, its other error term — and the verdict does NOT move,
        # at either sign or any magnitude in the knob domain. It has no residual to move.
        for b in (0.005, 0.02, -0.005, -0.02, 0.08, -0.08)
            f = flight(Rhat = -0.33, bz = b)
            @test f.reached
            @test f.rms_r < 0.30                           # slice 30's aim point: quiet at every b
        end
        # …and it is NOT inert while it fails to ring: the aim point moves, LINEARLY in b and with the
        # sign of `R̂·b` (the additive injection, the arc's first).
        let n = flight(Rhat = -0.33), p = flight(Rhat = -0.33, bz = 0.02),
            m = flight(Rhat = -0.33, bz = -0.02)
            @test p.azdot > n.azdot > m.azdot
        end
        # ⚠ AND THE HONEST NARROWING (gate-0 P10): a bias CAN flip a MARGINAL design, because it
        # steers the missile and so moves the LOOK ANGLE, which on CURVED glass moves the ENGAGEMENT
        # residual (slice 28's mechanism arriving through the sensor). It cannot touch a design
        # carrying slice 30's margin — which is the same margin the scale-factor budget is made of.
        @test flight(Rhat = -0.265, bz = -0.02).rms_r > 0.30
        @test flight(Rhat = -0.265, bz = +0.02).rms_r < 0.30
    end

    @testset "the AXIS SPLIT — `b_z` is the crossing wire's loop-closing channel" begin
        # `b_z` drives the AZIMUTH correction, `b_y` the ELEVATION one (frames.jl's kernel tooth), and
        # on a CROSSING engagement the lead — hence the ring — is in AZIMUTH. So the same bias on the
        # two axes must NOT do the same thing; that is why only `b_z` ships as a knob.
        # ⚠ Measured on the AIM POINT in the band, not on max|Δstate| over an early tick window: the
        # launch transient responds to both axes and inverts the comparison (this file's first draft).
        base = flight(Rhat = -0.33)
        dz = abs(flight(Rhat = -0.33, bz = 0.03).azdot - base.azdot)
        dy = abs(flight(Rhat = -0.33, by = 0.03).azdot - base.azdot)
        @test dz > 0.0 && dy > 0.0                          # both are live…
        @test dz > 3 * dy                                   # …and the azimuth axis dominates
    end

    @testset "the telemetry keys — shipped as NUMBERS, and 27/28's are NOT redefined" begin
        # Convention 13: the client never multiplies physics, so the belief the LOOP sees ships as a
        # number. ⚠⚠ AND slice 27/28's `radome_residual`/`radome_residual_az` KEEP THEIR MEANING: slice
        # 28's headline IS that the HARDWARE residual reads 0.000 while the missile rings, so the
        # gyro-effective residual ships ALONGSIDE rather than replacing it (two numbers from the same
        # frames that disagree — this arc's own shape).
        w, sub = gyro_world(Rhat = -0.27, s = -0.05, bz = 0.02)
        local tel
        for _ in 1:400
            tick!(w, sub, dt); empty!(w.events)
            tel = w.env[:telemetry]::Dict{String,Any}
        end
        @test tel["m1.gyro_scale_err"] == -0.05
        @test tel["m1.gyro_bias_z"]    == 0.02
        # the EFFECTIVE belief — the number the HUD must show beside the authored one
        @test tel["m1.radome_slope_est_eff"] ≈ -0.27 * 0.95 atol = 1e-12
        @test tel["m1.radome_slope_est"]     == -0.27          # …and the authored one is UNTOUCHED
        # the design rule re-aimed for the gyro spec: `R_worst/(1+s)`
        @test tel["m1.radome_aim_gyro"] ≈ (-0.03 + 2 * -0.15) / 0.95 atol = 1e-12
        @test tel["m1.radome_slope_worst"] ≈ -0.03 + 2 * -0.15 atol = 1e-12
        # the two residuals DISAGREE by exactly the belief rescale, and BOTH are shipped
        @test haskey(tel, "m1.radome_residual_az") && haskey(tel, "m1.radome_residual_az_eff")
        @test tel["m1.radome_residual_az_eff"] - tel["m1.radome_residual_az"] ≈
              -(-0.27 * -0.05) atol = 1e-9                     # = R̂ − R̂(1+s) = −R̂·s
        # the other currency, as a number — ⚠ and it is the FORMULA, `R̂·b`, nothing else
        @test tel["m1.gyro_inject_az"] ≈ -0.27 * 0.02 atol = 1e-14
        # ⭐ …and the CLOSED-LOOP consequence beside it, which is a DIFFERENT number: the TRUE LOS
        # azimuth rate. PN nulls the MEASURED rate, so whatever the compensator injects is carried by
        # the true geometry. ⚠ The two must NOT be confused — `gyro_inject_az` is exactly
        # proportional to R̂ BY CONSTRUCTION, so evidencing the amplification with it would be the
        # formula restated (the gate-3 verifier's first draft did exactly that). Pinned against an
        # INDEPENDENT recompute from the entities' own state (convention 11's different-algorithm
        # oracle), not against the expression in missile.jl.
        let mm = w.entities[:m1], tt = w.entities[:t1],
            d = tt.pos - mm.pos, v = tt.vel - mm.vel
            @test tel["m1.los_azdot_true"] ≈
                  (d[1] * v[2] - d[2] * v[1]) / (d[1]^2 + d[2]^2) atol = 1e-12
            @test tel["m1.los_azdot_true"] != tel["m1.gyro_inject_az"]
        end
        # …and NONE of them ships without a gyro key (the never-stale discipline).
        w2, sub2 = gyro_world(Rhat = -0.27)
        local t2
        for _ in 1:400
            tick!(w2, sub2, dt); empty!(w2.events)
            t2 = w2.env[:telemetry]::Dict{String,Any}
        end
        for k in ("m1.gyro_scale_err", "m1.gyro_bias_z", "m1.radome_slope_est_eff",
                  "m1.radome_aim_gyro", "m1.radome_residual_az_eff", "m1.gyro_inject_az",
                  "m1.los_azdot_true")
            @test !haskey(t2, k)
        end
        @test haskey(t2, "m1.radome_residual_az")               # …while slice 28's still ships
    end

    @testset "no live gyro knob can crash a tick (conventions 5/6)" begin
        # A throw inside observe! lands in the session's IO/EOF-only catch and drops the connection.
        # `s = −1` drives `radome_aim_gyro`'s denominator to zero — floored at the CONSUMER, and the
        # floor is on the denominator rather than on the knob because the dead gyro must stay FLYABLE.
        for (s, bz) in ((-1.0, 0.0), (-1.0 - 1e-12, 0.05), (-50.0, -5.0), (5.0e3, 5.0e3),
                        (0.0, 1.0e6), (-0.999999, 0.0))
            w, sub = gyro_world(s = s, bz = bz)
            for _ in 1:60
                tick!(w, sub, dt)
                empty!(w.events)
            end
            tel = w.env[:telemetry]::Dict{String,Any}
            for k in ("m1.radome_slope_est_eff", "m1.radome_aim_gyro", "m1.gyro_inject_az",
                      "m1.radome_residual_az_eff", "m1.los_azdot_true")
                @test isfinite(tel[k])
            end
        end
    end

    @testset "loader: the gyro is PRESENCE-gated, and refuses to be a DEAD knob" begin
        mktempdir() do dir
            function write_scn(extra)
                p = joinpath(dir, "g.yaml")
                open(p, "w") do io
                    print(io, "name: g\nseed: 31\ndt_physics: 1.0e-3\n",
                              "fidelity: {airframe: six_dof, autopilot: alpha, guidance: pn,\n",
                              "           seeker: filtered, seeker_axes: az_el}\n",
                              "entities:\n",
                              "  - id: m1\n    kind: missile\n    pos: [0.0, 0.0, 3000.0]\n",
                              "    missile:\n      mass_kg: 140.0\n      speed: 700.0\n",
                              "      elevation_deg: 12.0\n",
                              "      seeker: {two_angle: true, radome_slope: -0.03", extra, "}\n",
                              "      guidance: {n_pn: 8.0}\n",
                              "      airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0,\n",
                              "                 cmq: -150.0, cla: 20.0, cy_beta: 20.0}\n",
                              "  - id: t1\n    kind: target\n    pos: [6000.0, 2000.0, 4200.0]\n",
                              "    vel: [0.0, 200.0, 0.0]\n    target: {rcs_m2: 1.0}\n")
                end
                return p
            end
            # a gyro error with NO compensator to corrupt is a DEAD knob (the slice-19 `speed` class)
            # — REFUSED at load, not silently ignored (the slice-21/28/29 "refused, not
            # branch-ordered" precedent).
            for k in ("gyro_scale_err", "gyro_bias_z", "gyro_bias_y")
                @test_throws ErrorException load_scenario(write_scn(", $k: -0.05"))
            end
            # …with a compensator it loads, and mints ONLY the keys authored.
            s1 = load_scenario(write_scn(", radome_slope_est: -0.27, gyro_scale_err: -0.05"))
            m1 = first(e for (_, e) in s1.world.entities if e.kind === :missile)
            @test m1.comp[:gyro_scale_err] == -0.05
            @test !haskey(m1.comp, :gyro_bias_z) && !haskey(m1.comp, :gyro_bias_y)
            # non-finite is a LOAD error (convention 5: validate-at-load for authored inputs)
            @test_throws ErrorException load_scenario(
                write_scn(", radome_slope_est: -0.27, gyro_scale_err: .nan"))
            @test_throws ErrorException load_scenario(
                write_scn(", radome_slope_est: -0.27, gyro_bias_z: .inf"))
            # ⚠ `s = −1` is NOT refused — the DEAD GYRO is a legitimate degenerate, not a crash path.
            s2 = load_scenario(write_scn(", radome_slope_est: -0.27, gyro_scale_err: -1.0"))
            @test first(e for (_, e) in s2.world.entities
                        if e.kind === :missile).comp[:gyro_scale_err] == -1.0
        end
        # THE PRESENCE GATE FROM THE OTHER SIDE: no earlier wire carries a gyro key, so none of them
        # grows the readouts (slices 1–30 byte-identical).
        base = joinpath(@__DIR__, "..", "..", "scenarios")
        for f in ("slice26_radome.yaml", "slice27_radome_comp.yaml", "slice28_radome_curve.yaml",
                  "slice29_radome_schedule.yaml", "slice30_envelope.yaml")
            s = load_scenario(joinpath(base, f))
            for (_, e) in s.world.entities
                @test !haskey(e.comp, :gyro_scale_err)
                @test !haskey(e.comp, :gyro_bias_z)
                @test !haskey(e.comp, :gyro_bias_y)
            end
        end
    end
end

@testset "THE SEEKER'S FIELD OF VIEW wired (slice 32 — the envelope is what the seeker can see)" begin
    dt = 1.0e-3

    # Slice 30's plant and geometry with the RADOME KEYS ABSENT — the showcase posture, and it is a
    # convention-9 decision, not a simplification: 26–31's wire RINGS by construction, and a ringing
    # arm's look angle swings BECAUSE it rings, so the angle measured on it would be the LOOP's and
    # not the ENGAGEMENT's. `R !== nothing` puts the glass back for the COROLLARY testset only.
    # `fov === nothing` mints NO `:seeker_fov_deg` key: the byte-identity reference, and the ONLY
    # path slices 25–31 take.
    function fov_world(; fov = nothing, vy = 400.0, seed = 32, airframe = :six_dof,
                         R = nothing, A = -0.15, Rhat = nothing)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => airframe,
                                                 :seeker => :filtered, :seeker_axes => :az_el))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.3, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 8.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => 5.0e-5, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        if R !== nothing
            comp[:radome_slope] = R; comp[:radome_ripple] = A; comp[:radome_ripple_k] = 12.0
            Rhat === nothing || (comp[:radome_slope_est] = Rhat)
        end
        fov === nothing || (comp[:seeker_fov_deg] = fov)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 2000.0, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0),
                                 comp = Dict{Symbol,Any}(:cross_speed_mps => vy))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⚠ 6000 TICKS, NOT SLICE 31's 900: the break on the SHIPPED arm happens at t = 4.68 s, so a
    # 0.9 s trace would report "bit-identical" for two arms that end 1500 m apart. The window has to
    # contain the event the byte-identity claim is about.
    function trace(; n = 6000, kw...)
        w, sub = fov_world(; kw...)
        out = Float64[]
        for _ in 1:n
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]
            ω = get(m.comp, :omega_body, zero(Vec3))
            append!(out, (m.pos[1], m.pos[2], m.pos[3], ω[2], ω[3]))
        end
        return out
    end

    # The whole engagement, to FIRST CPA ([[ewsim-missile-verifier-sampling]]: the post-CPA
    # re-crossing is not the miss). PER-TICK, so the miss is exact rather than frame-sampled.
    #
    # ⚠⚠ THE OUT-OF-WINDOW FRACTION IS RANGE-GATED AT r > 200 m, AND THE GATE IS A GATE-2 FINDING,
    # not a convenience: a "quiet" arm is out of the window for ONE OR TWO TICKS at r = 0.1–0.6 m,
    # because the LOS unit vector swings through a large angle as r → 0 in the last millisecond
    # before impact. That is the endgame spike [[ewsim-missile-verifier-sampling]] names, it is
    # GEOMETRY and not the window's verdict, and gate 0's "0.0 %" was a `%.1f` rounding of
    # 0.007–0.017 %. Gated, the quiet arms are EXACTLY 0.000 % and the broken arm does not move
    # (67.943 %, whose out-ticks live at r = 1504–4123 m). The gate-3 verifier must carry it too.
    #
    # ⚠ TWO SATURATION WINDOWS, AND THE PAIR IS ITSELF A GATE-2 FINDING: `sat_band` is the arc's
    # inherited r ∈ [500, 3000] m band and is 0.00 % in EVERY arm — the isolation. The whole-approach
    # number is ~6.5 % and it is ~6.5 % IN THE REFERENCE ARM TOO: a LAUNCH TRANSIENT, the
    # front-loaded baseline slices 28/31 measured in rms r, arriving here in a different quantity.
    # Quote the window with the number.
    function arm(; n = 22000, kw...)
        w, sub = fov_world(; kw...)
        miss = Inf; t_cpa = 0.0; r_prev = Inf; maxy = 0.0; look_max = 0.0
        nt = 0; n_out = 0; n_band = 0; n_sat = 0; t_break = NaN
        for k in 1:n
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]; t = w.entities[:t1]
            tel = get(w.env, :telemetry, Dict{String,Any}())
            r = los_range(m.pos, t.pos)
            if r > 200
                nt += 1
                if get(tel, "m1.seeker_valid", 1.0) == 0.0
                    n_out += 1
                    isnan(t_break) && (t_break = k * dt)
                end
            end
            500 < r < 3000 && (n_band += 1;
                               get(tel, "m1.aero_sat", 0.0) == 1.0 && (n_sat += 1))
            r > 200 && haskey(m.comp, :att_q) && (look_max = max(look_max,
                rad2deg(boresight_angle(m.comp[:att_q]::Quat, los_unit(m.pos, t.pos)))))
            maxy = max(maxy, abs(m.pos[2]))
            r < miss && (miss = r; t_cpa = k * dt)
            r > r_prev && r_prev < 5000 && break
            r_prev = r
        end
        return (; miss, t_cpa, maxy, look_max, t_break, w,
                  out = 100n_out / max(nt, 1), sat_band = 100n_sat / max(n_band, 1))
    end

    @testset "BYTE-IDENTITY — no `seeker_fov_deg` key ⇒ the slice-25…31 path, bit-for-bit" begin
        # Convention 2. The key-absent path is TEXTUALLY the pre-slice-32 one (`in_fov = true` and
        # every tracker branch below unchanged), so this is bit-for-bit BY CONSTRUCTION and not by a
        # predicate that happens to return true.
        base = trace()
        @test trace() == base                                   # determinism, same-config
        # ⭐ AND THE KNOB-vs-RUNG DISCRIMINATOR, MEASURED (atmosphere.jl's): a window wide enough to
        # admit everything this engagement reaches is an IN-DOMAIN SLIDER VALUE that flies the
        # key-absent trajectory bit-for-bit ⇒ KNOB, no fidelity rung, button stays DROPPED.
        # ⚠⚠ WORDED "ON THIS WIRE", NEVER "180° ADMITS EVERYTHING" (gate 1's correction): the
        # angle-space radius `hypot(az, el)` is NOT bounded by π — its supremum is `hypot(π, π/2)` —
        # so a 180° window genuinely REJECTS a LOS behind the missile. This is an empirical statement
        # about the look angles the ENGAGEMENT reaches, and `test_frames.jl` pins the other fact.
        @test trace(fov = 180.0) == base
        @test trace(fov = 40.0)  == base                        # the domain CEILING, also inert here
        # …and the paired does-differ case, so the equalities above are not vacuous. 15° is inside
        # the launch look angle (18.1°), so this arm is out of the window from tick 1.
        @test trace(fov = 15.0) != base
        @test trace(fov = 25.0) != base                         # the shipped arm, past its break
    end

    @testset "DRAW-COUNT INVARIANCE — class 4a, and it is ASSERTED not assumed" begin
        # Convention 3, the sharpest determinism trap and the reason the seam sits BELOW the two
        # `randn` at the top of `_observe_point3d!`: an out-of-window tick DRAWS `n_az`/`n_el` and
        # discards them (slice 25's own lockstep — the foil DISCARDS, it does not SKIP). Gating the
        # DRAW instead of the VALUE would desync every 25–31 replay.
        function draws(fov)
            w, s = fov_world(fov = fov)
            for _ in 1:3000; tick!(w, s, dt); empty!(w.events); end
            return randn(w.rng)             # the NEXT draw is the stream's fingerprint
        end
        d0 = draws(nothing)
        @test draws(180.0) == d0
        @test draws(25.0)  == d0            # 67.9 % of this arm's approach is out of the window
        @test draws(0.0)   == d0            # NEVER LOCKED — not one measurement, all ticks drawn
        @test draws(-5.0)  == d0            # a negative slider: clamped at the consumer, still draws
        # ⚠ AND THE FINGERPRINT MUST BE LIVE (advisor, slice 28), or the four lines above cannot tell
        # "lockstep preserved" from "the probe is insensitive". A different SEED must move it.
        let w, s2
            w, s2 = fov_world(fov = 25.0, seed = 99)
            for _ in 1:3000; tick!(w, s2, dt); empty!(w.events); end
            @test randn(w.rng) != d0
        end
    end

    @testset "INERTNESS — the window needs a 6-DOF plant (the latent-bug class, 6th occurrence)" begin
        # Rung-gated on the LIVE `:airframe`, never on `haskey(:att_q)` alone — the slice-21 `_atm_on`
        # / 23 / 26 / 27 / 29 class. Without `:six_dof` there is no attitude to measure a look angle
        # OFF, so an absurdly tight window must be unreachable and no telemetry may be shipped.
        r = arm(n = 3000, airframe = :pitch_coupled, fov = 1.0)
        @test !haskey(r.w.env[:telemetry], "m1.seeker_valid")
        @test !haskey(r.w.env[:telemetry], "m1.seeker_fov_deg")
        @test !haskey(r.w.env[:telemetry], "m1.look_angle")
        # ⭐ AND THE CROSS-TOGGLE, which is what the latent-bug class is actually about: `:att_q` is
        # minted once by `_integrate_6dof!` and NEVER deleted, so a key-gated window would keep
        # blinding the seeker through a FROZEN attitude after a live flip off `:six_dof`.
        let w, sub
            w, sub = fov_world(fov = 1.0)                       # blind from tick 1 while 6-DOF
            for _ in 1:500; tick!(w, sub, dt); empty!(w.events); end
            @test haskey(w.entities[:m1].comp, :att_q)           # the key exists…
            @test w.env[:telemetry]["m1.seeker_valid"] == 0.0    # …and the window is biting
            w.fidelity[:airframe] = :pitch_coupled               # the live flip
            for _ in 1:200; tick!(w, sub, dt); empty!(w.events); end
            @test haskey(w.entities[:m1].comp, :att_q)           # still there, still stale
            @test !haskey(w.env[:telemetry], "m1.seeker_valid")  # and the window is GONE
        end
    end

    @testset "⭐ THE LESSON — the sensor stops supplying the command, and the miss opens 10⁴×" begin
        # THE OPEN ARM: a 25° seeker against a 400 m/s crossing target. The lead this collision
        # triangle demands is ~28.8°, so the target leaves the window WHILE THE LEAD IS STILL
        # BUILDING (t ≈ 4.7 s), the α-β tracker coasts on a rate that was right for a smaller lead,
        # and the geometry runs away monotonically.
        open  = arm(fov = 25.0, vy = 400.0)
        cureA = arm(fov = 30.0, vy = 400.0)      # WIDEN THE SEEKER — free
        cureB = arm(fov = 25.0, vy = 320.0)      # SLOW THE CROSSING — i.e. DECLINE the engagement
        ref   = arm(vy = 400.0)                  # no window at all
        @test open.miss  > 1000.0
        @test cureA.miss < 1.0
        @test cureB.miss < 1.0
        @test open.miss > 5000 * cureA.miss
        @test open.miss > 5000 * cureB.miss
        # ⭐ CURE A IS EXACTLY THE REFERENCE — widening the seeker past the lead RESTORES the
        # engagement, it does not merely improve it. Bit-for-bit, because the predicate never fires.
        @test cureA.miss === ref.miss
        # THE MECHANISM, as the fraction of the approach with NO measurement (slice 22's `post_stall`
        # discipline: do not let the miss carry the claim alone).
        @test open.out  > 60.0
        @test cureA.out == 0.0 && cureB.out == 0.0 && ref.out == 0.0
        # ⚠ ASSERT THE BREAK EXISTS BEFORE ASSERTING WHEN (advisor): `t_break` is recorded inside the
        # r > 200 m gate, so an arm that only ever lost lock in the endgame would leave it `NaN` and
        # the range comparison below would read FALSE rather than erroring — silent on a retuned wire.
        @test !isnan(open.t_break)
        @test 4.0 < open.t_break < 5.5            # the break, WHILE THE LEAD IS STILL BUILDING
        # ⚠⚠ THE SIGNATURE IS SLICE 23's AND SLICE 25's AND THE MECHANISM IS NEITHER (the copy-paste
        # false-claim trap, 3rd occurrence in this arc). BOTH of those foils fly with `max|y| = 0.0`
        # EXACTLY — the command was thrown away (23) or never formed (25). Here it WAS formed and
        # flown: the missile turns 8 km out of plane and then loses the target mid-flight.
        @test open.maxy > 5000.0
        @test open.look_max > 90.0                # and the look angle runs away, 25° → 100°
        # ⚠ THE ISOLATION, WITH ITS WINDOW: `aero_sat` is 0.00 % in the r ∈ [500, 3000] m band in
        # EVERY arm ⇒ a POINTING miss, not the arc's ceiling miss (19/20/21/22/23/24). The missile
        # has every bit of the authority it needs and no idea where to point it. ⚠ Assert the FLAG
        # as a number; never hand-roll the compare (the sets nest — slices 19/25/26).
        for a in (open, cureA, cureB, ref)
            @test a.sat_band == 0.0
        end
    end

    @testset "⭐⭐ THE ENVELOPE — the verdict flips where `fov` crosses the ENGAGEMENT's lead" begin
        # TWO KNOBS, AND CONVENTION 9 IS SATISFIED BY A MEASUREMENT (never by counting sliders):
        # they are two terms of ONE comparison, `fov` vs `lead(vy)`, and the verdict is reached from
        # BOTH directions. Widening the window and slowing the crossing are the same move.
        @test arm(fov = 20.0, vy = 260.0).out == 0.0     # lead 19.5° — inside a 20° window
        @test arm(fov = 20.0, vy = 320.0).out  > 50.0    # lead 23.8° — outside it
        @test arm(fov = 25.0, vy = 320.0).out == 0.0     # …and a 25° window takes it back
        @test arm(fov = 25.0, vy = 400.0).out  > 50.0    # lead 28.8° — outside again
        @test arm(fov = 30.0, vy = 400.0).out == 0.0     # …and a 30° window flies the WHOLE envelope
        # ⚠ THE VERDICT IS THE ASSERTION, THE MISS IS A QUOTE: the miss MAGNITUDE is NOT monotone in
        # `fov` inside the broken region (a ballistic-scatter number — 4th occurrence of the
        # non-monotone-knob pattern, [[ewsim-df-ellipse-sigma-monotonicity]]).
        let a = arm(fov = 20.0, vy = 320.0), b = arm(fov = 20.0, vy = 400.0)
            @test a.miss > 500.0 && b.miss > 500.0        # both broken…
            @test a.out > 50.0 && b.out > 50.0
        end
        # ⭐ THE FLOOR OF THE AXIS IS A DEAD POINT, AND IT IS DEAD EXACTLY (slice 30's shape): a
        # static target's collision course carries NO lead, so the seeker sits on boresight and the
        # tightest window in the domain is invisible.
        @test arm(fov = 20.0, vy = 0.0).out == 0.0
        @test arm(fov = 20.0, vy = 0.0).miss < 1.0
    end

    @testset "⭐ THE EXTERNAL ANCHOR — the window a seeker needs IS the collision lead" begin
        # Convention 11: an EXTERNAL anchor, not a self-calibrated round-trip. The claim is that the
        # critical FOV is a property of the ENGAGEMENT — `V_m·sin λ = V_t·sin θ` — so it is checked
        # against an INDEPENDENT recompute (acos of the LOS·v̂_t dot, then sin) rather than against
        # the core's own `collision_lead_angle`, whose decomposition is `‖v_t × û‖ / V_m`.
        # ⚠ MEASURED IN THE r ∈ [500, 3000] m BAND, on a NO-WINDOW arm: a broken arm's look angle
        # runs away BECAUSE it is broken, so the anchor may only be read where the seeker still sees.
        function anchor(vy)
            w, sub = fov_world(vy = vy)
            ratios = Float64[]; looks = Float64[]; r_prev = Inf
            for _ in 1:22000
                tick!(w, sub, dt); empty!(w.events)
                m = w.entities[:m1]; t = w.entities[:t1]
                r = los_range(m.pos, t.pos)
                if 500 < r < 3000 && haskey(m.comp, :att_q)
                    û  = los_unit(m.pos, t.pos)
                    Vt = sqrt(sum(abs2, t.vel)); Vm = sqrt(sum(abs2, m.vel))
                    θ  = acos(clamp(sum(t.vel .* û) / max(Vt, 1e-12), -1.0, 1.0))
                    lead = rad2deg(asin(clamp(Vt * sin(θ) / Vm, -1.0, 1.0)))
                    look = rad2deg(boresight_angle(m.comp[:att_q]::Quat, û))
                    push!(looks, look); lead > 1.0 && push!(ratios, look / lead)
                end
                r > r_prev && r_prev < 5000 && break
                r_prev = r
            end
            sort!(looks)
            return (; look_med = looks[cld(length(looks), 2)],
                      lo = minimum(ratios), hi = maximum(ratios))
        end
        for vy in (80.0, 200.0, 320.0, 400.0)
            a = anchor(vy)
            @test 0.96 < a.lo && a.hi < 1.01       # the look angle IS the lead, per tick, to ~1 %
        end
        # ⭐ AND THE ANCHOR PREDICTS THE VERDICT: the critical window BRACKETS the lead this
        # engagement holds (the testset above measures 320 breaking at 20 and flying at 25, and 400
        # breaking at 25 and flying at 30). That is the whole slice as an inequality — the FOV
        # requirement is not a seeker number, it is read off the collision triangle.
        @test 20.0 < anchor(320.0).look_med < 25.0
        @test 25.0 < anchor(400.0).look_med < 30.0
        # ⚠ THE GAP THAT IS NOT ZERO, AND GATE 1 DELIBERATELY REFUSED TO PROVE IT: look angle and
        # collision lead differ by the missile's AERODYNAMIC INCIDENCE. It is small (~1 %) and it
        # needs a FLYING missile, which is why it is measured here and not in `test_frames.jl`.
        @test anchor(400.0).lo < 1.0               # the incidence is real, not a rounding artifact
    end

    @testset "the DEFINED DEGENERATES — never locked, and a window that never opens" begin
        # `fov = 0` (and any negative slider value, clamped at the single consumer site) is the
        # NEVER-LOCKED state: out of the window before the tracker ever had a measurement. It must be
        # DEFINED, FINITE and NON-THROWING (conventions 5/6), not a special case bolted on.
        z = arm(fov = 0.0, vy = 400.0)
        @test z.out == 100.0                       # not one measurement, the whole flight
        @test z.miss > 1000.0
        # ⭐ AND THE SIGNATURE IS SLICE 23's AND 25's, EXACTLY — `max|y| = 0.0` — because a seeker
        # that never locks reports no LOS rate at all, so PN commands nothing out of plane and the
        # missile flies its launch plane. The FOURTH way to that number, and the reason the shipped
        # arm's `max|y| > 5000` above is the discriminating tooth rather than the miss.
        @test z.maxy == 0.0
        # negative is the same state (the clamp lives in `seeker_in_fov` and nowhere else)…
        @test trace(fov = -5.0, n = 2000) == trace(fov = 0.0, n = 2000)
        # …and every readout stays finite through it (convention 6 — no Inf/NaN to JSON).
        for fov in (0.0, -5.0, -1.0e9, 1.0e9, 1.0e-12)
            w, sub = fov_world(fov = fov)
            for _ in 1:400; tick!(w, sub, dt); empty!(w.events); end
            tel = w.env[:telemetry]::Dict{String,Any}
            for k in ("m1.seeker_valid", "m1.seeker_fov_deg", "m1.look_angle", "m1.lead_angle_deg")
                @test isfinite(tel[k])
            end
        end
    end

    @testset "the telemetry keys — and `look_angle` is NOT the radome's zeros" begin
        # ⚠ SAMPLED AT t = 4 s, NOT 0.8 s: the lead BUILDS as the target crosses (2.6° at 0.8 s,
        # 23.6° at 4 s), and a tooth read during the launch transient measures the transient.
        w, sub = fov_world(fov = 25.0, vy = 400.0)
        for _ in 1:4000; tick!(w, sub, dt); empty!(w.events); end
        tel = w.env[:telemetry]::Dict{String,Any}
        m = w.entities[:m1]; t = w.entities[:t1]
        @test tel["m1.seeker_fov_deg"] == 25.0          # the live knob, the LIMIT
        @test tel["m1.seeker_valid"] == 1.0             # still inside it at t = 4 s (it breaks at 4.7)
        # ⚠⚠ THE ADVISOR'S GATE-2 CATCH, PINNED: slice 26's `look_angle` is built from `look_az` /
        # `look_el`, which are the radome else-arm's ZEROS when no glass is authored — and THIS
        # SLICE'S WIRE HAS NO GLASS. A `_rad_on || _fov_on` gate on that expression (the obvious
        # edit, and the one the plan wrote) would ship 0.0 on the one wire the lesson runs on: the
        # slice-29 `radome_model_err_az` stale-readout class, 7th occurrence. It is computed HERE
        # from `û_tru` via the shipped kernel, and this test is the proof it carries a real angle.
        @test tel["m1.look_angle"] > 15.0
        @test tel["m1.look_angle"] ≈
              rad2deg(boresight_angle(m.comp[:att_q]::Quat, los_unit(m.pos, t.pos))) atol = 1e-12
        # ⭐ THE ENGAGEMENT'S OWN REQUIREMENT BESIDE THE HARDWARE'S WINDOW — the pair IS the slice.
        @test tel["m1.lead_angle_deg"] > 25.0
        # ⚠ AND THE ONE-SHOT MISUSE, MEASURED THROUGH THE SHIPPED KEY (the kernel's own docstring
        # warning): evaluated ONCE off the LAUNCH geometry this lead reads 32.90°, against the ~28.8°
        # the engagement actually holds — 14 % strict, because the LOS rotates as the target crosses.
        # Telemetry is per-tick BY CONSTRUCTION, which is the cure; a HUD that samples it once is
        # the disease.
        let w2, sub2
            w2, sub2 = fov_world(fov = 25.0, vy = 400.0)
            tick!(w2, sub2, dt); empty!(w2.events)
            @test w2.env[:telemetry]["m1.lead_angle_deg"] ≈ 32.90 atol = 0.02
        end
        # THE NEVER-STALE DISCIPLINE FROM THE OTHER SIDE: without the key, not one of them ships, so
        # every slice-11/13/25…31 wire is byte-identical.
        let w3, sub3
            w3, sub3 = fov_world(vy = 400.0)
            for _ in 1:4000; tick!(w3, sub3, dt); empty!(w3.events); end
            for k in ("m1.seeker_valid", "m1.seeker_fov_deg", "m1.look_angle", "m1.lead_angle_deg")
                @test !haskey(w3.env[:telemetry], k)
            end
        end
        # …and on a wire that has BOTH, this key is the SAME number the radome block ships —
        # provably, since `boresight_angle ≡ hypot(look_angles(att, û_tru)...)` on the same inputs.
        let w4, sub4
            w4, sub4 = fov_world(fov = 25.0, vy = 200.0, R = -0.03, Rhat = -0.03)
            for _ in 1:4000; tick!(w4, sub4, dt); empty!(w4.events); end
            t4 = w4.env[:telemetry]::Dict{String,Any}
            @test t4["m1.look_angle"] > 10.0
            @test haskey(t4, "m1.radome_eps")          # the radome block ran…
            @test t4["m1.seeker_valid"] == 1.0         # …and so did this one
        end
    end

    @testset "⭐ THE COROLLARY — slice 26's ring can shake the seeker out of its OWN window" begin
        # ⚠ A SECOND MECHANISM ⇒ convention 9 keeps this OFF the showcase wire; it ships here (the
        # slice-28 precedent for relocating a claim that is not client-drivable). BOTH DIRECTIONS
        # ARE ASSERTED, because the second one is also the RE-ACQUISITION evidence.
        #
        # DIRECTION 1 — the ring inflates the look-angle excursion past a window the same engagement
        # would otherwise have flown: at fov 20 / vy 200 the radome-free missile HITS, while the
        # ringing one is out of the window most of the approach and misses by kilometres.
        ring20 = arm(fov = 20.0, vy = 200.0, R = -0.03, Rhat = -0.03)
        free20 = arm(fov = 20.0, vy = 200.0)
        @test free20.out == 0.0 && free20.miss < 1.0
        @test ring20.out > 60.0
        @test ring20.miss > 1000.0
        @test free20.look_max < 20.0 && ring20.look_max > 20.0   # the ring is what breaks the window
        # DIRECTION 2 — A SHORT LOSS IS SURVIVABLE. At fov 25 the SAME ringing arm leaves the window
        # in brief episodes and still HITS. What is terminal is losing the target while the lead is
        # still BUILDING (the shipped arm), not losing it at all.
        ring25 = arm(fov = 25.0, vy = 200.0, R = -0.03, Rhat = -0.03)
        @test 0.0 < ring25.out < 5.0
        @test ring25.miss < 10.0
        # ⭐ AND THIS IS THE PROOF THE COASTING BRANCH RE-ACQUIRES CLEANLY — the line that would
        # otherwise be a live-looking branch with no tooth: the same ringing arm with NO window at
        # all lands within a metre of it, so the brief coasts cost essentially nothing.
        ringref = arm(vy = 200.0, R = -0.03, Rhat = -0.03)
        @test abs(ring25.miss - ringref.miss) < 1.0
        # ⭐⭐ DIRECTION 3, AND IT NARROWS THE CLAIM TO THE TRUE ONE (advisor): the arm above does not
        # ring because it has a RADOME, it rings because its compensator is the BORESIGHT-
        # characterized one slice 30 exists to condemn (`R̂ = R₀`, hardware residual exactly 0.000).
        # Aim `R̂` at the glass's worst-case slope instead — slice 30's rule, `radome_slope_worst` =
        # R₀ + 2A = −0.33 — and THE SAME GLASS FLIES THE SAME 20° WINDOW: 0.00 % out, a peak look
        # angle of 18.14° against the radome-free 18.13°, and a miss BIT-IDENTICAL to the same wire
        # with no window at all. ⇒ the honest sentence is "a compensator that RINGS can shake the
        # seeker out of its own window, and slice 30's design rule prevents it" — the FOV bound is
        # NOT tighter than the stability bound on this glass.
        let ruled = arm(fov = 20.0, vy = 200.0, R = -0.03, Rhat = -0.33)
            @test ruled.out == 0.0
            @test ruled.miss < 1.0
            @test ruled.look_max < 20.0
            @test ruled.miss === arm(vy = 200.0, R = -0.03, Rhat = -0.33).miss   # the window is inert
        end
    end

    @testset "loader: the window is PRESENCE-gated, and refuses to be a DEAD knob" begin
        mktempdir() do dir
            function write_scn(seekextra; two_angle = true)
                p = joinpath(dir, "f.yaml")
                open(p, "w") do io
                    print(io, "name: f\nseed: 32\ndt_physics: 1.0e-3\n",
                              "fidelity: {airframe: six_dof, autopilot: alpha, guidance: pn,\n",
                              "           seeker: filtered, seeker_axes: az_el}\n",
                              "entities:\n",
                              "  - id: m1\n    kind: missile\n    pos: [0.0, 0.0, 3000.0]\n",
                              "    missile:\n      mass_kg: 140.0\n      speed: 700.0\n",
                              "      elevation_deg: 12.0\n",
                              "      seeker: {two_angle: ", two_angle ? "true" : "false",
                              seekextra, "}\n",
                              "      guidance: {n_pn: 8.0}\n",
                              "      airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0,\n",
                              "                 cmq: -150.0, cla: 20.0, cy_beta: 20.0}\n",
                              "  - id: t1\n    kind: target\n    pos: [6000.0, 2000.0, 4200.0]\n",
                              "    vel: [0.0, 400.0, 0.0]\n    target: {rcs_m2: 1.0}\n")
                end
                return p
            end
            # ⚠⚠ THE PATH NOTHING IN THIS SLICE HAD EVER TAKEN UNTIL GATE 2 (advisor): every gate-0
            # probe and both gate-1 wire checks injected the key PROGRAMMATICALLY. This is the YAML
            # → comp path the shipped scenario will actually use.
            s1 = load_scenario(write_scn(", seeker_fov_deg: 25.0"))
            m1 = first(e for (_, e) in s1.world.entities if e.kind === :missile)
            @test m1.comp[:seeker_fov_deg] == 25.0
            # PRESENCE-GATED: no key authored ⇒ no key minted (convention 2 — every earlier wire).
            @test !haskey(first(e for (_, e) in load_scenario(write_scn("")).world.entities
                                if e.kind === :missile).comp, :seeker_fov_deg)
            # A DEAD KNOB IS REFUSED, NOT SILENTLY IGNORED (the slice-21/28/29/31 "refused, not
            # branch-ordered" precedent): the window is applied in `_observe_point3d!`, which only
            # runs on the TWO-ANGLE host, so without it the key would be read by nothing — the
            # slice-19 `speed` class.
            @test_throws ErrorException load_scenario(
                write_scn(", seeker_fov_deg: 25.0"; two_angle = false))
            # non-finite is a LOAD error (convention 5: validate-at-load for authored inputs)…
            @test_throws ErrorException load_scenario(write_scn(", seeker_fov_deg: .nan"))
            @test_throws ErrorException load_scenario(write_scn(", seeker_fov_deg: .inf"))
            # …but a NEGATIVE window is NOT refused: it is the never-locked degenerate, clamped at
            # the single consumer site (`seeker_in_fov`), and a live slider can reach it anyway.
            @test first(e for (_, e) in load_scenario(write_scn(", seeker_fov_deg: -1.0")).world.entities
                        if e.kind === :missile).comp[:seeker_fov_deg] == -1.0
            # and it is KNOB-REGISTERABLE (`_parse_knobs` checks entity + key exist)
            let p = write_scn(", seeker_fov_deg: 25.0")
                txt = read(p, String)
                write(p, txt * "knobs:\n  - {target: m1, key: seeker_fov_deg, min: 20.0, max: 40.0, label: FOV}\n")
                kk = Dict(kb.key => kb.target for kb in load_scenario(p).knobs)
                @test kk[:seeker_fov_deg] === :m1
            end
        end
        # THE PRESENCE GATE FROM THE OTHER SIDE: no earlier wire carries the key, so none of them
        # grows a window (slices 1–31 byte-identical).
        base = joinpath(@__DIR__, "..", "..", "scenarios")
        for f in ("slice25_seeker_3d.yaml", "slice26_radome.yaml", "slice27_radome_comp.yaml",
                  "slice28_radome_curve.yaml", "slice29_radome_schedule.yaml",
                  "slice30_envelope.yaml", "slice31_gyro.yaml")
            s = load_scenario(joinpath(base, f))
            for (_, e) in s.world.entities
                @test !haskey(e.comp, :seeker_fov_deg)
            end
        end
    end

    @testset "gate 3 — the HANDSHAKE MARKER that drops the button, and the SHIPPED wire" begin
        # ⭐ THE MARKER (`seeker_fov_view`), and the reason it is a SEPARATE key rather than a reuse
        # of slice 26's `radome_view`: the two select different HUD BRANCHES. The radome cascade
        # reads `radome_slope`/`radome_residual`/…, NONE of which a FOV wire has, and reading them
        # would ship 0.0 into a label — the stale-readout class this arc has caught seven times. The
        # BUTTON outcome is identical either way (both DROP it), which is why a wire carrying both is
        # safe on that axis.
        # ⚠ THE BUTTON DROP IS THE WHOLE POINT AND IT IS NOT COSMETIC: a FOV wire is a TWO-ANGLE
        # host, so without a marker the client falls through to slice 25's `seeker_axes` cycler,
        # whose other position (`:pitch_plane`) leaves the WINDOW LIVE on a missile that ALSO misses
        # by 2000 m for a wholly unrelated reason. Slice 26's argument, verbatim, one slice on.
        scn = load_scenario(joinpath(@__DIR__, "..", "..", "scenarios", "slice32_fov.yaml"))
        info = EWSim._airframe_view_info(scn.world)
        @test info[:seeker_fov_view] === true
        @test info[:airframe_6dof] === true              # it is still the slice-23 3-D view
        @test !haskey(info, :radome_view)                # ⭐ and there is NO glass on this wire
        # PRESENCE-gated from the other side: every 23–31 wire keeps its own marker set UNCHANGED
        # (the handshake is byte-identical there, which is what makes their UI tests still pass).
        let base = joinpath(@__DIR__, "..", "..", "scenarios")
            for f in ("slice23_out_of_plane.yaml", "slice25_seeker_3d.yaml", "slice26_radome.yaml",
                      "slice30_envelope.yaml", "slice31_gyro.yaml")
                p = joinpath(base, f)
                isfile(p) || continue
                @test !haskey(EWSim._airframe_view_info(load_scenario(p).world), :seeker_fov_view)
            end
        end

        # THE SHIPPED WIRE ITSELF — convention 9 and the disqualified-knob list, asserted rather
        # than described in a comment.
        m1 = scn.world.entities[:m1]; tgt = scn.world.entities[:tgt1]
        @test m1.comp[:seeker_fov_deg] == 25.0          # ⚠ THE SHOWCASE OPENS ON THE DISEASE
        @test tgt.comp[:cross_speed_mps] == 400.0
        @test tgt.vel.y == 400.0                        # the pin and the authored vel AGREE at the
                                                        # default — slice 30's knob-vs-rung
                                                        # discriminator, and it must not drift
        @test m1.comp[:seek_two_angle] === true
        @test scn.world.fidelity[:airframe] === :six_dof
        @test scn.world.fidelity[:seeker_axes] === :az_el
        @test scn.world.fidelity[:seeker] === :filtered
        # ⚠ `steering` OMITTED — the loader default is :skid_to_turn, and slice 24 measured BTT
        # binding the aero ceiling 93.2 % of its approach, which would destroy the aero_sat = 0
        # isolation this slice's whole claim rests on.
        @test !haskey(scn.world.fidelity, :steering)
        # ⚠⚠ THE RADOME KEYS ARE ABSENT BY DESIGN (convention 9): a ringing arm's look angle swings
        # BECAUSE it rings, so the angle measured on one is the LOOP's and not the ENGAGEMENT's.
        for k in (:radome_slope, :radome_slope_est, :radome_ripple, :radome_ripple_k,
                  :gyro_scale_err, :gyro_bias_z, :gyro_bias_y)
            @test !haskey(m1.comp, k)
        end
        # EXACTLY TWO KNOBS, and they are the TWO TERMS OF ONE COMPARISON (`fov` vs `lead(vy)`) —
        # convention 9 satisfied by the measurement, not by counting sliders.
        let kk = Dict(kb.key => kb for kb in scn.knobs)
            @test length(scn.knobs) == 2
            @test kk[:seeker_fov_deg].target === :m1
            @test (kk[:seeker_fov_deg].min, kk[:seeker_fov_deg].max) == (20.0, 40.0)
            @test kk[:cross_speed_mps].target === :tgt1
            @test (kk[:cross_speed_mps].min, kk[:cross_speed_mps].max) == (0.0, 400.0)
            # DISQUALIFIED AND ASSERTED ABSENT: `n_pn`/`rho` move the guidance loop the lesson is
            # not about; `radome_*` is a SECOND mechanism; `sigma_seek` degrades the lesson beside
            # it; `elevation_deg` is the slice-19 DEAD-knob class AND gate 0's P5 artifact;
            # `af_alpha_max` is the arc's aero ceiling, held at 0.0 % here on purpose.
            for k in (:n_pn, :rho, :radome_slope, :radome_slope_est, :sigma_seek,
                      :elevation_deg, :af_alpha_max, :speed)
                @test !haskey(kk, k)
            end
        end
        # ⭐ THE DOMAIN FLOOR'S REASON, PINNED (slice 26's post-commit discipline — endpoints
        # MEASURED, never inferred). Below ~18.12° the seeker never acquires ON THIS WIRE, and that
        # cliff is the SCENARIO's authored launch attitude, not a seeker property (gate 0 P5): it
        # tracks the TICK-1 look angle, which is set by `elevation_deg` = 12° against a target whose
        # launch BEARING is ~18.4° in azimuth. The domain therefore starts ABOVE it, so the slider
        # measures the SEEKER and not the launcher.
        # ⚠ `:att_q` is MINTED ON THE FIRST TICK, not at load (it is a 6-DOF state, not an authored
        # input), so this reads the SHIPPED telemetry after one tick rather than reconstructing an
        # attitude the loader never built — which is also the number gate 0's P5 measured.
        let w = scn.world
            tick!(w, scn.subs, scn.dt_physics)
            look0 = w.env[:telemetry]["m1.look_angle"]
            @test 18.0 < look0 < 18.3                    # the cliff, from the SHIPPED launch state
            @test look0 < 20.0                           # …and the domain floor clears it
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
# SLICE 33 — THE RING IS AN FOV BUDGET ITEM: WHAT THE PARASITIC LOOP COSTS YOU IS THE ENVELOPE.
#
# Slices 26–31 spent six slices on a missile that shakes itself, and every one of them recorded,
# as a standing fact, that THE RINGING ARM STILL HITS (slice 26: "the MISS is NOT the metric —
# the ringing arm STILL HITS (2.18 m)"), which is why the whole family measures `rms q` / `rms r`.
# It is true here too: across the R̂ ladder below, not one ringing arm misses by more than 3.6 m.
# ⭐ THE RING WAS BENIGN BECAUSE THE SEEKER HAD AN INFINITE WINDOW. Slice 32 gave it a real one
# and measured what FOV an engagement demands — the collision triangle's own lead. Give the SAME
# ring a real window and it misses by KILOMETRES, because the excursion the limit cycle adds to
# the look angle is spent out of exactly the budget slice 32 measured.
#
# ⇒ THE FOV A SEEKER NEEDS IS THE ENGAGEMENT'S LEAD **PLUS THE PARASITIC LOOP'S EXCURSION**, and
# slice 30's design rule buys the whole second term back.
#
# ⚠ NO new knob, no new rung, no new instability, no new cap, and NO new draw: both halves already
# fly (26–31's glass, 32's window) and both sliders already ship. What is new is the COMPOSITION,
# ONE telemetry number that measures it (`seeker_fov_margin_deg`), and the design rule it yields.
# There is therefore NO draw-count testset here, deliberately: no new branch and no new `randn` —
# slice 32's own corollary already flew radome × FOV arms under its asserted 2-draw lockstep.
# ─────────────────────────────────────────────────────────────────────────────────────────────
@testset "THE RING IS AN FOV BUDGET ITEM wired (slice 33 — the loop costs you the ENVELOPE)" begin
    dt = 1.0e-3

    # Slice 32's `fov_world` with THE GLASS PUT BACK — and that inversion is the slice. Slice 32
    # deleted the radome keys BY DESIGN (convention 9: a ringing arm's look angle swings BECAUSE it
    # rings, so it would be the LOOP's angle and not the ENGAGEMENT's). Here the composition IS the
    # lesson, which is the legitimate exemption — so the glass is on by default, and `R = nothing`
    # is the radome-free REFERENCE rather than the showcase.
    # ⚠ `af_alpha_max` is a KEYWORD here because slice 26's own instrument for the ring's AMPLITUDE
    # is exactly that knob ("the ceiling BOUNDS the cycle, the radome decides whether there IS
    # one") — it is the CAUSATION probe below and it is HELD on the shipped wire; it is a
    # confounded lever (slice 20 disqualified it for the induced-drag bill) and must never become
    # a slider.
    function budget_world(; fov = nothing, vy = 200.0, seed = 32, R = -0.03, A = -0.15,
                            Rhat = nothing, alpha_max = 0.3)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => :six_dof,
                                                 :seeker => :filtered, :seeker_axes => :az_el))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => alpha_max, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 8.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => 5.0e-5, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        if R !== nothing
            comp[:radome_slope] = R; comp[:radome_ripple] = A; comp[:radome_ripple_k] = 12.0
            Rhat === nothing || (comp[:radome_slope_est] = Rhat)
        end
        fov === nothing || (comp[:seeker_fov_deg] = fov)
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 2000.0, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0),
                                 comp = Dict{Symbol,Any}(:cross_speed_mps => vy))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⚠⚠ SEAM DISCIPLINE 1, BUILT INTO THE RETURN VALUE: `look_max` IS ONLY THE RING'S EXCURSION ON
    # AN ARM WITH NO WINDOW. On a windowed arm it is the POST-LOCK-LOSS RUNAWAY (~90°, slice 32's
    # signature) and reads nothing about the loop. The two are therefore bound at the CALL SITE as
    # `free_*` and `win_*` below, and the ISOLATION testset asserts the difference rather than
    # leaving it to a comment. ⇒ THE PREDICTOR AND THE PREDICTED NEVER COME FROM THE SAME RUN.
    #
    # ⚠⚠ AND `rms_r` IS `NaN`, NOT `0.0`, WHEN THE BAND IS EMPTY — a GATE-2 FINDING and the reason
    # `n_band` is returned at all. A badly broken arm's CPA is 3697 m, so it NEVER ENTERS the arc's
    # r ∈ [500, 3000] m band: a `sum/max(n,1)` would have printed a beautifully quiet `0.00000`
    # computed from ZERO SAMPLES, which is the gate-1 post-review's own catch ("a column that
    # reproduces because it counts nothing is not a reproduction") one gate later, in a new
    # quantity. Every test that quotes a band number asserts `n_band > 0` first.
    #
    # Range gates are slice 32's, inherited with their reasons: `r > 200` on every look-angle and
    # out-of-window number (ungated, the endgame LOS swing makes a QUIET arm read a few hundredths
    # of a percent out — [[ewsim-missile-verifier-sampling]]), band [500, 3000] on `rms r`/`aero_sat`.
    #
    # ⚠⚠ AND `r_firstout` IS UNGATED ON PURPOSE — IT IS THE GATE'S OWN AUDIT, AND A GATE-2 FINDING
    # PAID FOR IN FIVE FAILING ASSERTS. The first draft claimed a window that fits the excursion is
    # BIT-IDENTICAL to no window at all (slice 32's `cureA.miss === ref.miss`, inherited). IT IS
    # NOT, and the reason is the very thing the r > 200 gate exists to exclude: EVERY held arm here
    # leaves the window in the last metres — first out at r = 0.18–8.5 m — because the LOS unit
    # vector swings through a huge angle as r → 0 (look angle 21–162° at those ticks). Those few
    # coasting ticks perturb the CPA by 5e−13…1.4e−7 m. ⇒ THE EXACT CLAIM BELONGS ON THE GATED
    # QUANTITIES (`out`, `look_max` — both bit-exact) and the miss carries a NAMED TOLERANCE with a
    # measured reason. Slice 32's `===` passed only because its 30° window happened not to be
    # crossed before ITS CPA — luck of a wider window, not a law.
    function arm(; n = 22000, kw...)
        w, sub = budget_world(; kw...)
        miss = Inf; r_prev = Inf; look_max = 0.0; marg_min = Inf; worst = NaN
        nt = 0; n_out = 0; n_band = 0; n_sat = 0; sum_r2 = 0.0; t_break = NaN; r_firstout = NaN
        for k in 1:n
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]; t = w.entities[:t1]
            tel = get(w.env, :telemetry, Dict{String,Any}())
            r = los_range(m.pos, t.pos)
            haskey(tel, "m1.radome_slope_worst") && (worst = tel["m1.radome_slope_worst"])
            get(tel, "m1.seeker_valid", 1.0) == 0.0 && isnan(r_firstout) && (r_firstout = r)
            if r > 200
                nt += 1
                if get(tel, "m1.seeker_valid", 1.0) == 0.0
                    n_out += 1
                    isnan(t_break) && (t_break = k * dt)
                end
                haskey(m.comp, :att_q) && (look_max = max(look_max,
                    rad2deg(boresight_angle(m.comp[:att_q]::Quat, los_unit(m.pos, t.pos)))))
                haskey(tel, "m1.seeker_fov_margin_deg") &&
                    (marg_min = min(marg_min, tel["m1.seeker_fov_margin_deg"]))
            end
            if 500 < r < 3000
                n_band += 1
                ω = get(m.comp, :omega_body, zero(Vec3)); sum_r2 += ω[3]^2
                get(tel, "m1.aero_sat", 0.0) == 1.0 && (n_sat += 1)
            end
            r < miss && (miss = r)
            r > r_prev && r_prev < 5000 && break
            r_prev = r
        end
        return (; miss, look_max, t_break, marg_min, worst, n_band, r_firstout, w,
                  rms_r    = n_band == 0 ? NaN : sqrt(sum_r2 / n_band),
                  out      = 100n_out / max(nt, 1),
                  sat_band = n_band == 0 ? NaN : 100n_sat / n_band)
    end

    # HELD, spelled out once and used by every testset below, so the claim is made in exactly one
    # place: the arm never lost the target ANYWHERE ON THE APPROACH (bit-exact, in the gated
    # quantity), it flew the free arm's own excursion to the last bit, and its miss matches the
    # free arm's to within the endgame perturbation measured above.
    # ⚠ `tag` IS NOT DECORATION AND THE INNER `@testset` IS NOT EITHER (advisor): this is called
    # from EIGHT sites, and a bare helper would report the SAME FOUR LINE NUMBERS for every one of
    # them — a regression in the A = −0.20 payload row and a regression in `win_24` would produce
    # byte-identical failure output. A proof that cannot say WHICH ARM broke is a weaker proof.
    function held(win, free, tag)
        @testset "held: $tag" begin
            @test win.out == 0.0                          # not one out-of-window tick, r > 200
            @test win.look_max === free.look_max          # …and the SAME excursion, bit-for-bit
            @test isnan(win.r_firstout) || win.r_firstout < 200.0  # any drop-out is ENDGAME ONLY
            # ⚠ AND THE MARGIN IS STATED, NOT IMPLIED (slice 22's "a ~1.03× margin, stated rather
            # than hidden"; slice 26's "endpoints MEASURED, never inferred"): the endgame
            # perturbation MEASURED across every held arm here spans 5e−13 … 1.4e−7 m, so this is a
            # ~7× margin. It is deliberately NOT tightened to 1.4e−7 — the perturbation is a
            # PHYSICAL quantity that legitimately moves with the wire, and a tripwire that fires on
            # a benign retune is worse than a bound that says what it is.
            @test abs(win.miss - free.miss) < 1.0e-6
        end
    end

    # THE SHARED LADDER, computed ONCE. Glass R₀ = −0.03, A = −0.15 ⇒ `radome_slope_worst` = −0.33
    # (slice 30's aim point), against a vy = 200 m/s crossing target — slice 28's geometry, which is
    # what holds a SUSTAINED lead. `R̂` walks from slice 30's design rule to slice 28's boresight
    # characterization, and the ring grows monotonically along it.
    free_rule = arm(Rhat = -0.33)      # slice 30's rule: quiet
    free_24   = arm(Rhat = -0.24)      # the onset (slice 30's "last decisive ring", −0.24 / 0.709)
    free_18   = arm(Rhat = -0.18)
    free_03   = arm(Rhat = -0.03)      # slice 28's boresight compensator: the loudest ring
    ref_free  = arm(R = nothing)       # NO GLASS AT ALL — the engagement's own requirement

    @testset "the MARGIN on the wire — ONE number whose SIGN is the flying verdict" begin
        # ⭐ `seeker_fov_margin_deg` = `max(fov,0) − boresight_angle`, SIGNED, slice 18's
        # `terrain_clearance_m` precedent: shipped so the client never re-derives the test
        # (convention 13). The HUD needle a ringing radome is visibly seen to EAT.
        let (w, sub) = budget_world(Rhat = -0.03, fov = 21.0)
            flip = 0; cross = 0; agree_max = 0.0
            for k in 1:8000
                tick!(w, sub, dt); empty!(w.events)
                tel = w.env[:telemetry]::Dict{String,Any}
                v = tel["m1.seeker_valid"]; mg = tel["m1.seeker_fov_margin_deg"]
                # AT A POSITIVE WINDOW the shipped keys DO reconstruct it, exactly — same kernel,
                # same `û_tru`, same tick.
                agree_max = max(agree_max,
                                abs(mg - (tel["m1.seeker_fov_deg"] - tel["m1.look_angle"])))
                v == 0.0 && flip == 0 && (flip = k)
                mg < 0.0 && cross == 0 && (cross = k)
            end
            @test agree_max < 1.0e-12
            # ⭐⭐ THE TOOTH THAT IS NOT A TAUTOLOGY (advisor). `margin ≥ 0 ⟺ seeker_in_fov` is
            # `x == x` AT THE KERNEL (gate 1 refused to ship it for exactly that reason), but ON
            # THE WIRE it is a claim about the SEAM: that the readout site passes the PREDICATE'S
            # OWN inputs — the TRUTH LOS `û_tru` and the CLAMPED radian window — and not an
            # estimate, not the authored degrees, not a stale comp key. Walk a trace that breaks
            # and the 1→0 flip lands on the exact tick the shipped margin crosses zero.
            @test flip > 0 && cross > 0
            @test flip == cross
            # ⚠ AND THE ONLY OTHER CLAIM MADE ABOUT THAT TICK IS A PHYSICAL ONE (advisor). A first
            # draft pinned `flip == 1935` — a tick index on one arm of one wire, which is EXACTLY
            # the magic literal the TWO THRESHOLDS testset below forbids two screens later (the
            # slice-21 magic-multiple tooth), and which would fail on any retune with no indication
            # of whether the SEAM broke or the WIRE moved. The structural claim above IS the tooth;
            # this one ties the tick to the MECHANISM instead of to the grid, and it is the same
            # claim `win_03.t_break` carries: the break is EARLY, while the lead is still building.
            @test flip * dt < 2.5
        end
        # ⚠⚠ AND AT A NEGATIVE WINDOW THEY DIVERGE BY EXACTLY `|fov|` — gate 1's clamp-ownership
        # catch, reproduced ON THE WIRE, and the whole reason convention 13 requires the key rather
        # than letting the client subtract two others. `seeker_fov_deg` ships the AUTHORED value (a
        # HUD showing 0° for a negative slider would hide what the student is holding); the margin
        # uses the CLAMPED one, because otherwise its sign would stop agreeing with the predicate.
        let (w, sub) = budget_world(Rhat = -0.03, fov = -5.0)
            for _ in 1:100; tick!(w, sub, dt); empty!(w.events); end
            tel = w.env[:telemetry]::Dict{String,Any}
            @test tel["m1.seeker_fov_deg"] == -5.0
            @test tel["m1.seeker_valid"]   == 0.0                       # the never-locked state
            @test tel["m1.seeker_fov_margin_deg"] ≈ -tel["m1.look_angle"] atol = 1e-12
            @test tel["m1.seeker_fov_margin_deg"] -
                  (tel["m1.seeker_fov_deg"] - tel["m1.look_angle"]) ≈ 5.0 atol = 1e-12
        end
        # NEVER STALE: the key is gated with slice 32's four, so no 11/13/25…31 wire grows one, and
        # a live flip off `:six_dof` takes it away (the `_atm_on` latent-bug class — the gate is on
        # the LIVE rung, never on `haskey(:att_q)`).
        let (w, sub) = budget_world(Rhat = -0.03)
            for _ in 1:500; tick!(w, sub, dt); empty!(w.events); end
            @test !haskey(w.env[:telemetry], "m1.seeker_fov_margin_deg")
        end
        let (w, sub) = budget_world(Rhat = -0.03, fov = 21.0)
            for _ in 1:500; tick!(w, sub, dt); empty!(w.events); end
            @test haskey(w.env[:telemetry], "m1.seeker_fov_margin_deg")
            w.fidelity[:airframe] = :pitch_coupled
            for _ in 1:200; tick!(w, sub, dt); empty!(w.events); end
            @test haskey(w.entities[:m1].comp, :att_q)                   # the state survives…
            @test !haskey(w.env[:telemetry], "m1.seeker_fov_margin_deg") # …the readout does not
        end
        # `_finite_coord`, NOT `_finite` (the slice-29 `k̂` catch, and here it is not hypothetical):
        # the margin is NEGATIVE across the whole out-of-window side, by ~65° on a broken arm.
        @test arm(Rhat = -0.03, fov = 21.0).marg_min < -50.0
    end

    @testset "⭐ THE LESSON — every ringing arm HITS, and the SAME ring with a window misses by km" begin
        # THE STANDING FACT OF SLICES 26–31, RE-MEASURED: on an arm with NO WINDOW, the ring costs
        # nothing you can see in the miss. The loudest arm here rings at rms r 1.07 against the
        # radome-free 0.016 — 67× — and still lands 2.07 m from the target.
        for a in (free_rule, free_24, free_18, free_03, ref_free)
            @test a.miss < 3.6
            @test a.out == 0.0
        end
        @test free_03.rms_r > 60 * ref_free.rms_r          # it RINGS, loudly…
        @test free_03.miss  < 3.6                          # …and it HITS anyway
        # ⭐ AND NOW THE SAME FOUR DESIGNS THROUGH A 21° WINDOW. The two whose excursion fits keep
        # their engagement (`held` — the predicate never fires on the approach); the two whose ring
        # overruns it lose the target while the lead is still building and miss by kilometres.
        win_rule = arm(Rhat = -0.33, fov = 21.0)
        win_24   = arm(Rhat = -0.24, fov = 21.0)
        win_18   = arm(Rhat = -0.18, fov = 21.0)
        win_03   = arm(Rhat = -0.03, fov = 21.0)
        held(win_rule, free_rule, "ladder R̂=−0.33 (slice 30's rule) @ fov 21")
        held(win_24,   free_24,   "ladder R̂=−0.24 (the onset) @ fov 21")
        @test win_18.miss > 2000.0 && win_18.out > 40.0
        @test win_03.miss > 3000.0 && win_03.out > 70.0
        # THE HEADLINE RATIO — the SAME glass, the SAME R̂, the SAME seed, one arm with a window.
        @test win_18.miss > 2000 * free_18.miss
        @test win_03.miss > 1500 * free_03.miss
        # …and the break is EARLY, while the lead is still BUILDING (slice 32's discriminator).
        # ⚠ Assert the break EXISTS before asserting WHEN (slice 32's advisor catch): `t_break` is
        # recorded inside the r > 200 gate, so a NaN would read FALSE rather than erroring.
        @test !isnan(win_18.t_break) && win_18.t_break < 6.0
        @test !isnan(win_03.t_break) && win_03.t_break < 2.5
        @test isnan(win_rule.t_break) && isnan(win_24.t_break)     # never lost, not "lost late"
    end

    @testset "⭐⭐ THE PREDICATE — `held ⟺ fov > excursion`, BRACKETED against the MEASURED angle" begin
        # ⚠⚠ ASSERT THE INEQUALITY, NEVER `ceil` (seam discipline 2). Gate 0 measured
        # `critical fov == ⌈excursion⌉` in 16 of 16 cells, but that identity is an artifact of the
        # 1° measuring grid; the PHYSICAL claim is the inequality, and the tooth is built backwards
        # from the measurement as a BRACKETING PAIR — exactly as slice 32 built its `≤` boundary
        # tooth with `prevfloat`. A `ceil` assert would pin a test to the grid it was never about.
        #
        # ⚠⚠ AND THE BRACKET IS BUILT ON ROWS CLEAR OF THE LAUNCH CLIFF (advisor, before any code).
        # Slice 32's P5 measured this wire's NEVER-ACQUIRES floor at ~18.12°, and it is the
        # SCENARIO'S AUTHORED LAUNCH ATTITUDE, not a seeker property. A bracket straddling the quiet
        # arm's 18.14° excursion would straddle the LAUNCHER — slice 32's own confound shipped as
        # slice 33's headline. Both rows below sit well above it, and that is ASSERTED, not
        # commented.
        for (Rhat, free) in ((-0.18, free_18), (-0.03, free_03))
            exc = free.look_max
            @test exc - 0.1 > 18.2                           # clear of slice 32's P5 cliff
            below = arm(Rhat = Rhat, fov = exc - 0.1)
            above = arm(Rhat = Rhat, fov = exc + 0.1)
            @test below.out > 0.0                            # a tenth of a degree short: it BREAKS
            # ⭐ AND A TENTH OF A DEGREE OVER, IT HOLDS THE WHOLE APPROACH AND FLIES THE FREE ARM'S
            # OWN EXCURSION BIT-FOR-BIT — so the angle the FREE arm measured is exactly the budget
            # the WINDOWED one needs, which is the whole predicate.
            held(above, free, "bracket R̂=$Rhat @ excursion + 0.1°")
        end
    end

    @testset "⭐ TWO THRESHOLDS, NOT ONE — the LOCK bracket and the MISS bracket are ~0.1° apart" begin
        # ⚠⚠ `held` AND `hits` ARE DIFFERENT PREDICATES AND THEY BREAK AT DIFFERENT WINDOWS
        # (advisor). Letting one threshold silently do both jobs is what would read wrong at gate 3.
        # The LOCK threshold is the excursion, sharp to a hundredth of a degree. The MISS threshold
        # sits BELOW it, and the gap between them is the SURVIVABLE BAND — which is also slice 32's
        # re-acquisition evidence, the thing that makes the coasting branch's `_prev`-tracks-the-
        # prediction line EXERCISED rather than defensive.
        exc = free_03.look_max
        # ⚠ PINNED AGAINST THE MEASURED EXCURSION, NEVER A HARDCODED 25.0 — the margin here is
        # 0.011°, below any measuring grid, so a literal would be a magic number the next retune
        # silently breaks (the slice-21 magic-multiple tooth, now pinned against a measured
        # quantity).
        @test 25.0 < exc < 25.1                              # the row this band lives on
        band = arm(Rhat = -0.03, fov = exc - 0.011)          # a HUNDREDTH of a degree short
        lost = arm(Rhat = -0.03, fov = exc - 0.1)            # a TENTH of a degree short
        @test band.out > 0.0 && band.out < 0.5               # ⇒ NOT held: it leaves the window…
        @test band.miss < 2.1                                # …and STILL HITS
        @test abs(band.miss - free_03.miss) < 0.1            # within a tenth of a metre of no window
        @test lost.out > 40.0 && lost.miss > 1000.0          # a tenth of a degree: kilometres
        # ⭐⭐ AND `t_break` IS THE DISCRIMINATOR — SLICE 32's OWN MECHANISM REACHED BY MOVING THE
        # WINDOW instead of the crossing speed: the survivable arm loses lock NEAR CPA, the lost one
        # loses it while the lead is still BUILDING. "A short loss is survivable; what is terminal
        # is a loss while the lead is still building" (slice 32), measured on a new axis.
        @test !isnan(band.t_break) && band.t_break > 9.0
        @test !isnan(lost.t_break) && lost.t_break < 6.0
    end

    @testset "⭐⭐ THE PAYLOAD — slice 30's rule returns the requirement to the RADOME-FREE number" begin
        # Slice 30 shipped `radome_slope_worst` as the aim point that makes a SCALAR compensator
        # unconditionally stable (only a NEGATIVE residual rings, so aiming at the glass's worst-case
        # slope errs in the harmless direction everywhere). ⇒ ITS RULE IS AN ENVELOPE RULE TOO, AND
        # THAT IS SLICE 33's PAYLOAD: aim there and the FOV requirement collapses back onto the
        # engagement's own lead — the requirement a missile with NO GLASS AT ALL would have.
        #
        # ⚠ ASSERTED AS AN EXCURSION COMPARISON, NEVER A CRITICAL-FOV ONE (advisor): seam discipline
        # 2 forbids the `ceil` currency, and this compares like with like.
        # ⚠ AND THE AIM POINT IS READ OFF SLICE 30's SHIPPED TELEMETRY, never recomputed as R₀ + 2A
        # — the cure uses the number the wire computes (it is −0.32999999999999996, not −0.33, which
        # is exactly the kind of literal this project refuses to hardcode).
        for A in (-0.10, -0.15, -0.20)
            worst = arm(n = 50, A = A, Rhat = -0.30).worst   # 50 ticks: the key is per-tick constant
            @test isfinite(worst)
            ruled = arm(A = A, Rhat = worst)
            # THE REQUIREMENT IS THE RADOME-FREE ENGAGEMENT'S OWN, TO WITHIN THE MISSILE'S
            # AERODYNAMIC INCIDENCE — at every depth, i.e. DEPTH-INDEPENDENTLY. The glass gets 2×
            # worse and the number does not move.
            @test abs(ruled.look_max - ref_free.look_max) < 0.02
            @test ruled.miss < 1.0
            # …and a 19° window — sized for the RADOME-FREE engagement — flies it, at every depth.
            held(arm(A = A, Rhat = worst, fov = 19.0), ruled, "payload A=$A @ fov 19")
        end
        # THE CONTRAST, at the SAME depth as the ladder: slice 28's boresight-characterized
        # compensator — hardware residual EXACTLY 0.000 — demands 6.5°+ MORE window than the same
        # glass under slice 30's rule.
        @test free_03.look_max - free_rule.look_max > 6.5
    end

    @testset "⭐ CAUSATION — the ring's AMPLITUDE is the budget item, not the value of `R̂`" begin
        # ⚠ THE OBVIOUS ALTERNATIVE STORY is that the excursion tracks `R̂` for some reason other
        # than the ring — so move the ring's AMPLITUDE with `R̂` and the glass BOTH HELD. `α_max` is
        # slice 26's own instrument for exactly this: it grows the limit cycle's amplitude while
        # leaving its ONSET where it was ("the ceiling BOUNDS the cycle, the radome decides whether
        # there IS one"). ⚠ A CAUSATION PROBE, NEVER A SLIDER — a confounded lever (slice 20
        # disqualified it for the induced-drag bill), HELD on the shipped wire.
        a20 = arm(Rhat = -0.18, alpha_max = 0.20)
        a30 = free_18                                        # the ladder's own arm, α_max = 0.30
        a45 = arm(Rhat = -0.18, alpha_max = 0.45)
        @test a20.rms_r < a30.rms_r < a45.rms_r               # the ring grows…
        @test a20.look_max < a30.look_max < a45.look_max      # …and so does the budget it eats
        # ⇒ THE SAME 21° WINDOW FLIES THE QUIETEST OF THE THREE AND BREAKS ON THE OTHER TWO, at a
        # FIXED `R̂` and FIXED glass. The excursion is the budget item; `R̂` only sets it.
        @test a20.look_max < 21.0 && a45.look_max > 21.0
        held(arm(Rhat = -0.18, alpha_max = 0.20, fov = 21.0), a20,
             "causation α_max=0.20 @ fov 21")
        @test arm(Rhat = -0.18, alpha_max = 0.45, fov = 21.0).miss > 3000.0
    end

    @testset "⚠⚠ THE ISOLATION — the predictor and the predicted must not come from the same run" begin
        # SEAM DISCIPLINE 1, ASSERTED. Slice 32 warned that its metric INVERTS: losing the
        # measurement CUTS the parasitic feed, so on a windowed arm `rms r` FALLS while the miss
        # OPENS. That makes a low `rms r` on a windowed arm indistinguishable between "this design
        # is stable" and "the seeker lost lock and stopped driving the loop" — so every `R̂` is flown
        # TWICE, and only the FREE arm may be read for the ring.
        win_18 = arm(Rhat = -0.18, fov = 21.0)
        @test free_18.n_band > 0 && win_18.n_band > 0         # …before quoting a band number at all
        @test win_18.rms_r < 0.25 && free_18.rms_r > 0.9      # the metric FALLS, ~4.7×…
        @test win_18.miss > 2000 * free_18.miss               # …while the miss OPENS ~2400×
        # AND THE SAME INVERSION IN THE LOOK ANGLE, which is the quantity this slice predicts WITH:
        # the windowed arm's own peak is the POST-LOCK-LOSS RUNAWAY (~90°, slice 32's signature) and
        # is no read of a ring whose actual excursion was 22.1°.
        @test win_18.look_max > 85.0
        @test free_18.look_max < 25.0
        # ⚠⚠ AND THE SHARPEST FORM OF THE SAME HAZARD, A GATE-2 FINDING: on a BADLY broken arm the
        # band metric is not merely misleading, it is UNDEFINED. Its CPA is 3697 m, so it never
        # enters r ∈ [500, 3000] at all — a `sum/max(n,1)` would have printed a beautifully quiet
        # `0.00000` COMPUTED FROM ZERO SAMPLES. The gate-1 post-review's own catch, one gate on:
        # a column that reproduces because it counts nothing is not a reproduction.
        let win_03 = arm(Rhat = -0.03, fov = 21.0)
            @test win_03.miss > 3000.0
            @test win_03.n_band == 0
            @test isnan(win_03.rms_r) && isnan(win_03.sat_band)
        end
        # ⚠⚠ AND DO NOT IMPORT SLICE 32's ISOLATION — IT INVERTS HERE. Slice 32 could write
        # "`aero_sat` is 0.00 % in EVERY arm ⇒ a POINTING miss", because its wire had NO GLASS. On
        # THIS wire the FREE ringing arm saturates HALF its band and HITS at 0.92 m (slice 26's
        # ceiling BOUNDING the cycle), while the broken arm saturates 0.00 % and misses by 2.2 km.
        # ⇒ saturation does not discriminate in either direction here; the WINDOW does.
        @test free_18.sat_band > 40.0 && free_18.miss < 1.0
        @test win_18.sat_band == 0.0  && win_18.miss  > 2000.0
    end

    @testset "loader: the COMPOSITION loads — glass AND a window in ONE yaml, a first" begin
        # ⚠ SLICE 33 ADDS NO KEY, NO KNOB AND NO RUNG, so there is nothing to presence-gate and
        # nothing to refuse (`radome_*` is 26–29's, `seeker_fov_deg` is 32's, and each already has
        # its own loader testset above). THE ONE GENUINELY NEW LOADER FACT is that the COMPOSITION
        # goes through: no scenario has ever authored glass and a window together, every gate-0
        # probe and both gate-1 wire checks injected the keys PROGRAMMATICALLY, and gate 3's wire
        # will be the first YAML to carry both.
        mktempdir() do dir
            p = joinpath(dir, "c.yaml")
            open(p, "w") do io
                print(io, "name: c\nseed: 32\ndt_physics: 1.0e-3\nemit_every: 16\n",
                          "fidelity: {airframe: six_dof, autopilot: alpha, guidance: pn,\n",
                          "           seeker: filtered, seeker_axes: az_el}\n",
                          "entities:\n",
                          "  - id: m1\n    kind: missile\n    pos: [0.0, 0.0, 3000.0]\n",
                          "    missile:\n      mass_kg: 140.0\n      speed: 700.0\n",
                          "      elevation_deg: 12.0\n",
                          "      seeker: {two_angle: true, sigma_seek: 5.0e-5, alpha: 0.30,\n",
                          "               beta: 0.05, radome_slope: -0.03, radome_ripple: -0.15,\n",
                          "               radome_ripple_k: 12.0, radome_slope_est: -0.18,\n",
                          "               seeker_fov_deg: 21.0}\n",
                          "      guidance: {n_pn: 8.0}\n",
                          "      airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0,\n",
                          "                 cmq: -150.0, cla: 20.0, cy_beta: 20.0}\n",
                          "  - id: t1\n    kind: target\n    pos: [6000.0, 2000.0, 4200.0]\n",
                          "    vel: [0.0, 200.0, 0.0]\n",
                          "    target: {rcs_m2: 1.0, cross_speed_mps: 200.0}\n")
            end
            s = load_scenario(p)
            m1 = s.world.entities[:m1]
            for (k, v) in ((:radome_slope, -0.03), (:radome_ripple, -0.15), (:radome_ripple_k, 12.0),
                           (:radome_slope_est, -0.18), (:seeker_fov_deg, 21.0))
                @test m1.comp[k] == v
            end
            # ⭐ AND THE HANDSHAKE MARKER SET IS THE FIRST TO CARRY BOTH — FLAGGED HERE, BUILT AT
            # GATE 3 (advisor). Slice 32's own gate-3 testset asserts `!haskey(info, :radome_view)`
            # on its wire AS A FEATURE; slice 33's wire has glass, so both markers ship. The BUTTON
            # outcome is safe either way (slice 32 wrote that both DROP it), but which HUD BRANCH
            # the client selects is a gate-3 decision, and pinning the fact here means gate 3
            # discovers nothing.
            info = EWSim._airframe_view_info(s.world)
            @test info[:seeker_fov_view] === true
            @test info[:radome_view]     === true
            @test info[:airframe_6dof]   === true
        end
    end

    @testset "gate 3 — the SHIPPED wire, and the FIRST scenario to raise BOTH view markers" begin
        # The gate-2 loader testset above built the composition in a `mktempdir`; this one asserts
        # the SHIPPED YAML, which is the artifact a student actually runs.
        scn = load_scenario(joinpath(@__DIR__, "..", "..", "scenarios", "slice33_budget.yaml"))
        m1 = scn.world.entities[:m1]; tgt = scn.world.entities[:tgt1]

        # ⭐⭐ BOTH MARKERS, WHICH NO SCENARIO IN THE PROJECT HAS EVER SHIPPED TOGETHER. Slice 32's
        # own gate-3 testset asserts `!haskey(info, :radome_view)` on ITS wire AS A FEATURE (its
        # radome keys are absent by convention 9), and that assert MUST STILL PASS — the two wires
        # have to stay distinguishable from the core side, because the client's composition HUD
        # branch keys off exactly this conjunction.
        # ⚠ THE BUTTON OUTCOME IS IDENTICAL EITHER WAY (both markers drop it, at both client sites),
        # so what the conjunction selects is the HUD BRANCH ALONE — and that is not cosmetic: slice
        # 32's `_fov_verdict_label` compares the LEAD against the WINDOW, and on this wire the lead
        # is ~18.1° inside a 21° window, so it would report "IN THE WINDOW — FOV holds the lead" on
        # the arm that misses by 3.7 km. THE LEAD NEVER OUTGREW THE WINDOW; THE RING DID.
        let info = EWSim._airframe_view_info(scn.world)
            @test info[:seeker_fov_view] === true
            @test info[:radome_view]     === true
            @test info[:airframe_6dof]   === true            # still the slice-23 3-D view
        end
        let base = joinpath(@__DIR__, "..", "..", "scenarios")
            # …and every 26–32 wire keeps EXACTLY ONE of the two, so none of them takes the new
            # branch and all their UI tests keep passing.
            for (f, fov, rad) in (("slice32_fov.yaml", true, false),
                                  ("slice26_radome.yaml", false, true),
                                  ("slice30_envelope.yaml", false, true),
                                  ("slice31_gyro.yaml", false, true))
                p = joinpath(base, f)
                isfile(p) || continue
                inf = EWSim._airframe_view_info(load_scenario(p).world)
                @test haskey(inf, :seeker_fov_view) === fov
                @test haskey(inf, :radome_view)     === rad
            end
        end

        # THE WIRE ITSELF — convention 9 and the disqualified-knob list, asserted rather than
        # described in a comment.
        @test m1.comp[:seeker_fov_deg]  == 21.0      # the ladder's window: it fits the two quiet
                                                     # designs' excursions and NOT the two loud ones
        @test m1.comp[:radome_slope]    == -0.03
        @test m1.comp[:radome_ripple]   == -0.15     # ⇒ radome_slope_worst = R₀ + 2A = −0.33
        @test m1.comp[:radome_slope_est] == -0.03    # ⚠ THE SHOWCASE OPENS ON THE DISEASE: slice
                                                     # 28's BORESIGHT characterization, whose
                                                     # HARDWARE residual is EXACTLY 0.000
        @test m1.comp[:radome_slope] - m1.comp[:radome_slope_est] == 0.0
        @test m1.comp[:seek_two_angle] === true
        @test m1.comp[:af_alpha_max] == 0.3          # HELD — slice 26's amplitude instrument stays
                                                     # a gate-0 causation probe, never a slider
        @test tgt.comp[:cross_speed_mps] == 200.0    # slice 28's geometry: a SUSTAINED lead, which
                                                     # is what parks the seeker on steep glass
        @test tgt.vel.y == 200.0                     # the pin and the authored vel AGREE at the
                                                     # default (slice 30's knob-vs-rung
                                                     # discriminator — it must not drift)
        @test scn.world.fidelity[:airframe]    === :six_dof
        @test scn.world.fidelity[:seeker_axes] === :az_el
        @test scn.world.fidelity[:seeker]      === :filtered
        @test !haskey(scn.world.fidelity, :steering) # the loader default :skid_to_turn is the held
                                                     # plant — BTT would be a THIRD mechanism
        # ⚠ NO GYRO KEYS: slice 31's errors are absent, so the compensator here reads a PERFECT
        # rate. Composing three mechanisms is exactly what convention 9 forbids.
        for k in (:gyro_scale_err, :gyro_bias_z, :gyro_bias_y)
            @test !haskey(m1.comp, k)
        end

        # EXACTLY TWO KNOBS — the two halves of ONE comparison, `fov` vs `excursion(R̂)`.
        let kk = Dict(kb.key => kb for kb in scn.knobs)
            @test length(scn.knobs) == 2
            # ⚠ BOTH TARGET THE INTERCEPTOR, unlike slice 30's and 32's two-entity pairs: the window
            # its seeker has and the belief its guidance computer carries are BOTH the missile's.
            @test kk[:seeker_fov_deg].target   === :m1
            @test kk[:radome_slope_est].target === :m1
            # THE DOMAINS, WITH THEIR MEASURED REASONS. The FOV floor 19 is the QUIET-GLASS
            # requirement (it flies the radome-free 18.13° and every arm under slice 30's rule) and
            # is clear of slice 32's P5 never-acquires cliff at ~18.12°, which is the scenario's
            # AUTHORED LAUNCH ATTITUDE and not a seeker property. The ceiling 40 is the FREE READ
            # itself (seam discipline 1: the excursion must come from an arm the window never
            # bites), measured at 0.000 % out on every ladder arm.
            @test (kk[:seeker_fov_deg].min, kk[:seeker_fov_deg].max) == (19.0, 40.0)
            @test kk[:seeker_fov_deg].min > 18.12
            # The R̂ floor reaches PAST slice 30's aim point so cure B is reachable AND overshootable
            # (the one-sided constraint: a positive residual de-tunes, it does not ring); the ceiling
            # is the authored default, bounded by the 30° small-angle budget 28/29/30/31 each
            # declared — the excursion is already 25.01° there.
            @test (kk[:radome_slope_est].min, kk[:radome_slope_est].max) == (-0.36, -0.03)
            @test kk[:radome_slope_est].min <
                  m1.comp[:radome_slope] + 2 * m1.comp[:radome_ripple]
            # DISQUALIFIED AND ASSERTED ABSENT. ⚠ `cross_speed_mps` heads this list and is the one
            # that is new: it is slice 32's OWN axis (it moves the LEAD), so on a wire convention 9
            # already stretches to two mechanisms it would be a THIRD.
            for k in (:cross_speed_mps, :radome_slope, :radome_ripple, :radome_ripple_k,
                      :af_alpha_max, :n_pn, :rho, :sigma_seek, :elevation_deg, :speed,
                      :gyro_scale_err, :gyro_bias_z)
                @test !haskey(kk, k)
            end
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
# SLICE 34 — THE GIMBAL: THE HEAD POINTS WHERE THE GLASS SAYS THE TARGET IS.
#
# Slices 26–33 built the parasitic loop on one geometric fact: the radome bends the ray by an
# amount set by the LOOK ANGLE, and the look angle is the LOS measured off the missile's OWN
# NOSE — a quantity the missile can only move by ROTATING, which is exactly why slice 26 is a
# BODY-RATE instability. A GIMBALLED SEEKER BREAKS THAT IDENTITY: the ray passes through the part
# of the dome the HEAD is aimed at, and the head is aimed by the very measurement the dome just
# bent. The index of the glass becomes a FIXED POINT of the glass.
#
# ⇒ SLICE 26's LOOP IS PARTLY RE-CLOSED THROUGH THE HEAD, WHERE ITS SIGN IS NEGATIVE. Same glass,
# same residual, same seed: strapdown RINGS (rms r 0.93194) and gimballed is QUIET (0.01181).
#
# ⚠ AND IT IS NOT FREE, IN THE ONE CURRENCY A GIMBAL HAS. The margin is bought by the head's
# pointing DECOUPLING from the true LOS, and that decoupling is precisely the tracking error the
# head's own detector window must cover. Slice 33's single number splits in TWO — a STOP (the
# head's travel about the body) and a DETECTOR WINDOW (about the head axis) — and gate 2 measures
# that the two are ONE BUDGET, not two independent limits.
#
# ⚠ NO new draw (class 4a, the head is a deterministic servo on an existing measurement), no new
# rung, no new cap. ONE live slider: `gimbal_fov_deg`. `gimbal_tau_s` and `gimbal_stop_deg` are
# AUTHORED — see the τ testset for the MEASUREMENT that keeps τ out of the slider list, which is
# not the one `docs/plans/slice34.md` §0.4 predicted.
# ─────────────────────────────────────────────────────────────────────────────────────────────
@testset "THE GIMBALLED HEAD wired (slice 34 — the index that looks at itself)" begin
    dt = 1.0e-3

    # Slice 33's `budget_world` with the HEAD keys added. Everything else is held to the digit —
    # the whole point is that the strapdown column must reproduce slices 30/33 exactly, so any
    # movement in the gimbal column is the head and nothing else.
    function gim_world(; vy = 200.0, seed = 32, R = -0.03, A = -0.15, Rhat = nothing,
                         tau = nothing, stop = nothing, gfov = nothing, fov = nothing)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => :six_dof,
                                                 :seeker => :filtered, :seeker_axes => :az_el))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.3, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 8.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => 5.0e-5, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        if R !== nothing
            comp[:radome_slope] = R; comp[:radome_ripple] = A; comp[:radome_ripple_k] = 12.0
            Rhat === nothing || (comp[:radome_slope_est] = Rhat)
        end
        tau  === nothing || (comp[:gimbal_tau_s]    = tau)
        stop === nothing || (comp[:gimbal_stop_deg] = stop)
        gfov === nothing || (comp[:gimbal_fov_deg]  = gfov)
        fov  === nothing || (comp[:seeker_fov_deg]  = fov)     # slice 32's BODY-fixed window
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 2000.0, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0),
                                 comp = Dict{Symbol,Any}(:cross_speed_mps => vy))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⚠⚠ SLICE 33's TWO-RUN DISCIPLINE IS INHERITED AND IT IS MANDATORY HERE FOR A SECOND,
    # INDEPENDENT REASON (§0.7, MEASURED): the head HOLDS when it loses its error signal, so a
    # broken detector window FREEZES the index — and a frozen index produces a CONSTANT bend, which
    # is quiet at every R̂. So on a windowed arm `rms r` FALLS while the miss OPENS, and `off_max`
    # becomes the ~90° post-lock-loss runaway rather than the tracking error. ⇒ THE PREDICTOR
    # (`rms r`, `off_max`) COMES OFF A FREE ARM AND THE PREDICTED (miss, % out) OFF A WINDOWED ONE,
    # bound as `free` / `win` at the call sites below, never read off one run.
    #
    # `rms_r` is NaN, never 0.0, on an empty band (slice 33's gate-2 finding: a badly broken arm's
    # CPA is ~3.6 km and never enters r ∈ [500, 3000], so `sum/max(n,1)` would print a beautifully
    # quiet 0.00000 from ZERO SAMPLES). Every test quoting a band number asserts `n_band > 0`.
    function arm(; n = 22000, trace = false, kw...)
        w, sub = gim_world(; kw...)
        miss = Inf; r_prev = Inf
        look_body_max = 0.0; head_max = 0.0; off_max = 0.0
        nt = 0; n_out = 0; n_band = 0; sum_r2 = 0.0; t_break = NaN
        tr = Vec3[]
        for k in 1:n
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]; t = w.entities[:t1]
            tel = get(w.env, :telemetry, Dict{String,Any}())
            trace && push!(tr, m.pos)
            r = los_range(m.pos, t.pos)
            if r > 200                       # slice 32's endgame-spike gate, inherited with it
                nt += 1
                if get(tel, "m1.gimbal_valid", get(tel, "m1.seeker_valid", 1.0)) == 0.0
                    n_out += 1
                    isnan(t_break) && (t_break = k * dt)
                end
                haskey(m.comp, :att_q) && (look_body_max = max(look_body_max,
                    rad2deg(boresight_angle(m.comp[:att_q]::Quat, los_unit(m.pos, t.pos)))))
                head_max = max(head_max, get(tel, "m1.head_angle_deg", 0.0))
                haskey(tel, "m1.head_off_deg") && (off_max = max(off_max, tel["m1.head_off_deg"]))
            end
            if 500 <= r <= 3000
                n_band += 1
                ω = get(m.comp, :omega_body, zero(Vec3))::Vec3
                sum_r2 += ω[3]^2
            end
            r > r_prev && miss == Inf && (miss = r_prev)
            r_prev = r
            miss < Inf && k > 200 && break
        end
        return (; miss, look_body_max, head_max, off_max, t_break, n_band, trace = tr,
                  rms_r = n_band == 0 ? NaN : sqrt(sum_r2 / n_band),
                  out   = nt == 0 ? 0.0 : 100n_out / nt)
    end

    # The arc's ring/quiet line, the same 0.30 slices 30/33 read their brackets against.
    RING = 0.30
    posdiff(a, b) = (@assert length(a) == length(b);
                     maximum(hypot((x - y)...) for (x, y) in zip(a, b)))

    # THE SHARED LADDER, computed once. Glass R₀ = −0.03, A = −0.15 (⇒ `radome_slope_worst` =
    # −0.33, slice 30's aim point) against slice 28's vy = 200 crossing target. The gimbal column
    # is the SHIPPED head: τ = 0.05, a 30° stop, no detector window.
    strap = Dict(Rh => arm(Rhat = Rh) for Rh in (-0.33, -0.27, -0.24, -0.18, -0.17, -0.16, -0.03))
    gim   = Dict(Rh => arm(Rhat = Rh, tau = 0.05, stop = 30.0)
                 for Rh in (-0.33, -0.27, -0.24, -0.19, -0.18, -0.17, -0.16, -0.12, -0.03))

    @testset "BYTE-IDENTITY — no `gimbal_tau_s` ⇒ the slice-25…33 path, ON THE WIRE" begin
        # Convention 2's master check, and read off the WIRE rather than off the diff: the
        # key-absent arms must reproduce the numbers slices 30 and 33 recorded, to the digit.
        @test strap[-0.24].rms_r ≈ 0.70983 atol = 2.0e-5     # slice 30's "last decisive ring"
        @test strap[-0.18].rms_r ≈ 0.93194 atol = 2.0e-5     # slice 33's ladder, verbatim
        @test strap[-0.03].rms_r ≈ 1.07211 atol = 2.0e-5
        @test strap[-0.33].rms_r ≈ 0.05879 atol = 2.0e-5
        # …and not one head key is even evaluated there (the never-stale discipline).
        let (w, sub) = gim_world(Rhat = -0.18)
            for k in 1:200; tick!(w, sub, dt); empty!(w.events); end
            tel = w.env[:telemetry]::Dict{String,Any}
            for key in ("m1.head_angle_deg", "m1.head_off_deg", "m1.gimbal_valid",
                        "m1.gimbal_fov_deg", "m1.gimbal_stop_deg", "m1.gimbal_fov_margin_deg",
                        "m1.look_body_deg")
                @test !haskey(tel, key)
            end
            @test !haskey(w.entities[:m1].comp, :head_az)
            @test !haskey(w.entities[:m1].comp, :head_tgt_az)
        end
    end

    @testset "⭐⭐ THE HEAD IS INERT WHERE IT SHOULD BE — three controls, all EXACTLY 0" begin
        # The head reaches the trajectory through exactly TWO channels: the radome's INDEX and the
        # detector WINDOW. Remove both and it must be bit-for-bit absent — which is the structural
        # claim, not a courtesy, because it is what says the seam has no third path.
        #
        # ⚠ CONTROL A — NO GLASS, NO WINDOW: inert at EVERY τ, including a head so slow it lags by
        # degrees. A servo with nothing to index and nothing to gate cannot move a missile.
        for τ in (0.0, 0.05, 0.5)
            a = arm(n = 9000, trace = true, R = nothing)
            b = arm(n = 9000, trace = true, R = nothing, tau = τ, stop = 30.0)
            @test posdiff(a.trace, b.trace) == 0.0
        end
        # ⚠ CONTROL B — A WIDE DETECTOR WINDOW IS BIT-IDENTICAL TO THE KEY BEING ABSENT. This is
        # atmosphere.jl's KNOB-vs-RUNG discriminator applied to the slice's ONE slider: the
        # off-state is knob-reachable, so `gimbal_fov_deg` is a KNOB and there is no fidelity rung
        # (and the client button stays dropped). The free arms below rely on it.
        for Rh in (-0.18, -0.16)
            a = arm(n = 9000, trace = true, Rhat = Rh, tau = 0.05, stop = 30.0)
            b = arm(n = 9000, trace = true, Rhat = Rh, tau = 0.05, stop = 30.0, gfov = 40.0)
            @test posdiff(a.trace, b.trace) == 0.0
        end
        # ⚠ CONTROL C — A NON-BINDING STOP IS INERT, bit-for-bit, which is what licenses the
        # UNCONDITIONAL `head_clamp` call at the handover (gate 1's Finding 2: the servo is a
        # contraction only from INSIDE the disc, and the init is the one place a head can be born
        # outside it, so the clamp must run every time and cost nothing when it does not bind).
        for Rh in (-0.18, -0.03)
            a = arm(n = 9000, trace = true, Rhat = Rh, tau = 0.05, stop = 30.0)
            b = arm(n = 9000, trace = true, Rhat = Rh, tau = 0.05)          # no stop authored
            @test posdiff(a.trace, b.trace) == 0.0
        end
    end

    @testset "⚠⚠ BOTH WINDOWS AUTHORED — the head WINS, and it does not throw" begin
        # GATE-2 REVIEW CATCH (advisor), and it was a real crash. `scenario.jl` refuses this
        # combination, but a PROGRAMMATIC world can still build it — and the slice-33 telemetry
        # block reads `fov_rad`, which the availability branch leaves UNASSIGNED once the `_gim`
        # arm is taken. An `UndefVarError` inside `observe!` lands in the session's IO/EOF-only
        # catch and silently drops the connection (convention 5). ⚠ The seam comment at
        # `_fov_on` justified leaving that local unassigned on the grounds that "an unassigned
        # local throws and the suite catches it" — true only while nothing built the combination,
        # which stopped being true the moment a head existed. Fixed with a `!_gim` conjunct on
        # `_fov_on`, which turns the loader's POLICY into the seam's STRUCTURE.
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 30.0, fov = 25.0)
            for k in 1:400; tick!(w, sub, dt); empty!(w.events); end     # …no throw
            tel = w.env[:telemetry]::Dict{String,Any}
            # the HEAD's window is the one that flies…
            @test haskey(tel, "m1.gimbal_valid") && haskey(tel, "m1.head_off_deg")
            # …and NOT ONE slice-32/33 window key ships beside it, so nothing downstream can read
            # a body-fixed verdict off a gimballed seeker.
            for key in ("m1.seeker_valid", "m1.seeker_fov_deg", "m1.seeker_fov_margin_deg")
                @test !haskey(tel, key)
            end
            # ⭐ AND `look_angle` IS STILL THE HEAD'S INDEX — the clobber this conjunct makes
            # impossible rather than merely refused (the slice-29 stale-readout class).
            @test tel["m1.look_angle"] != tel["m1.look_body_deg"]
        end
        # …and the same world is bit-for-bit the one WITHOUT slice 32's key: the body window is
        # not merely out-ranked, it is INERT.
        let a = arm(n = 9000, trace = true, Rhat = -0.18, tau = 0.05, stop = 30.0),
            b = arm(n = 9000, trace = true, Rhat = -0.18, tau = 0.05, stop = 30.0, fov = 25.0)
            @test posdiff(a.trace, b.trace) == 0.0
        end
    end

    @testset "⚠⚠ THE NON-COLLAPSE — §0.2 does NOT reproduce, and that IS the slice" begin
        # GATE-2 FINDING, and it corrects the plan's own reading of its gate-0 result. §0.2
        # measured `max|Δpos| = 0` at τ → 0 and concluded that "the bend keys off head-vs-body" is
        # the FALSE-FIDELITY class — a rewrite with no physics in it. ⚠ THAT ARM TRACKED THE TRUTH
        # LOS (`gimbal_lib.jl`'s default). The head that SHIPS tracks its own BENT, one-tick-delayed
        # measurement, so at τ = 0 it lands on the PREVIOUS tick's BENT angle and NOT on this tick's
        # LOS-vs-body: the collapse is not available, and the amount by which it fails to collapse
        # is the self-referential index with the servo lag taken out.
        for (Rh, want) in ((-0.03, 77.10), (-0.18, 58.21), (-0.33, 55.13))
            a = arm(n = 9000, trace = true, Rhat = Rh)
            b = arm(n = 9000, trace = true, Rhat = Rh, tau = 0.0, stop = 30.0)
            @test posdiff(a.trace, b.trace) ≈ want atol = 0.02
        end
        # ⭐⭐ AND IT IS NOT MERELY NON-ZERO — AT τ = 0 THE MARGIN IS ALREADY THERE IN FULL. This is
        # §0.5's isolation reproduced at the seam without needing its `:truth` / `:delay` probe
        # arms: the minimum-lag head, whose only remaining departure from strapdown is the INDEX,
        # is quiet where the strapdown seeker rings. ⇒ THE MARGIN IS BOUGHT BY THE INDEX.
        let z = arm(Rhat = -0.18, tau = 0.0, stop = 30.0)
            @test z.n_band > 0
            @test z.rms_r ≈ 0.03394 atol = 2.0e-5
            @test z.rms_r < RING                 # QUIET…
            @test strap[-0.18].rms_r > RING      # …where the strapdown seeker RINGS
            @test strap[-0.18].rms_r / z.rms_r > 27.0
        end
    end

    @testset "⭐⭐ THE LESSON — same glass, same residual, same seed: 78.9×" begin
        f = gim[-0.18]; s = strap[-0.18]
        @test f.n_band > 0 && s.n_band > 0
        @test s.rms_r ≈ 0.93194 atol = 2.0e-5
        @test s.rms_r > RING                                        # RINGS
        @test f.rms_r ≈ 0.01181 atol = 2.0e-5
        @test f.rms_r < RING                                        # QUIET
        @test s.rms_r / f.rms_r ≈ 78.9 atol = 0.2
        # ⚠ THE MISS IS NOT THE METRIC, and this is the arc's standing fact since slice 26 — every
        # arm on the whole ladder HITS, ringing or not, so the verdict is always `rms r`.
        @test all(a.miss < 7.0 for a in values(gim))
        @test maximum(a.miss for a in values(strap)) < 7.0
    end

    @testset "⭐ THE BRACKET — two rungs of the ladder, and a SECOND independent tell" begin
        # Quoted BRACKET TO BRACKET and never as one number (slice 30's "sufficient, never tight"
        # discipline): the gimballed onset is (−0.18, −0.16] against the strapdown (−0.27, −0.24].
        @test gim[-0.18].rms_r < RING && gim[-0.16].rms_r > RING     # (−0.18, −0.16]
        @test strap[-0.27].rms_r < RING && strap[-0.24].rms_r > RING # (−0.27, −0.24]
        # ⚠ −0.17 IS MARGINAL AND IS DELIBERATELY NOT ASSERTED AS A VERDICT — it is 0.039, an order
        # above the quiet arms and an order below the ringing one. It is pinned as a NUMBER so a
        # regression that moved it would be visible, without the bracket resting on it.
        @test gim[-0.17].rms_r ≈ 0.03934 atol = 2.0e-5
        @test gim[-0.24].rms_r ≈ 0.02497 atol = 2.0e-5
        @test gim[-0.16].rms_r ≈ 0.35338 atol = 2.0e-5
        # ⭐ THE SECOND TELL, FROM A DIFFERENT QUANTITY — `head_max` STEPS AT THE SAME PLACE. The
        # head's TRAVEL is flat at 18.1172° through every quiet arm (it is tracking the engagement's
        # own lead and nothing else) and jumps to 20.6193° on the first ringing one, which is what
        # makes the bracket a MEASUREMENT and not a threshold read off the metric that defined it.
        for Rh in (-0.33, -0.27, -0.24, -0.19, -0.18, -0.17)
            @test gim[Rh].head_max ≈ 18.1172 atol = 1.0e-3
        end
        @test gim[-0.16].head_max ≈ 20.6193 atol = 1.0e-3
        @test gim[-0.12].head_max ≈ 22.0259 atol = 1.0e-3
        @test gim[-0.03].head_max ≈ 23.6010 atol = 1.0e-3
        @test gim[-0.16].head_max > gim[-0.17].head_max + 2.0
    end

    @testset "⚠⚠ τ — AUTHORED, and the MEASURED reason is NOT the one §0.4 predicted" begin
        # GATE-2 FINDING. §0.4 concluded "τ does NOT move the onset anywhere in [0.02, 0.2] — only
        # the amplitude sags", and made that the reason τ is authored rather than a slider. ⚠ ITS
        # LADDER SKIPPED −0.17 AND −0.16, which is exactly where the bracket is: the sag is
        # monotone EVERYWHERE, and AT THE LINE that same sag crosses the verdict.
        τs = (0.0, 0.02, 0.05, 0.10, 0.20)
        sweep = Dict(Rh => [arm(Rhat = Rh, tau = τ, stop = 30.0).rms_r for τ in τs]
                     for Rh in (-0.18, -0.17, -0.16, -0.12))
        # the sag, on a deep-ringing arm that never goes quiet — §0.4's own row, reproduced
        @test sweep[-0.12] ≈ [1.01270, 0.83567, 0.70207, 0.57877, 0.42355] atol = 2.0e-5
        @test issorted(sweep[-0.12]; rev = true)
        # …and the SAME sag at the line, where it changes the verdict: the bracket walks from
        # (−0.18, −0.17] at τ = 0 to (−0.16, −0.12] at τ = 0.20. ⚠ ALL FOUR CELLS ARE DECISIVE —
        # 0.645 / 0.021 / 0.424 against the 0.30 line. The τ = 0.02 cell at −0.17 (0.26854) is
        # DELIBERATELY NOT READ AS A VERDICT: it sits within 1 % of the line, in exactly the range
        # §0.8 already flagged as ambiguous (0.26719 "on the wrong side of the 0.30 line"), and the
        # same refusal was made two testsets up for −0.17 at τ = 0.05. It is pinned as a NUMBER.
        @test sweep[-0.17][1] > RING                                   # τ = 0 RINGS…
        @test sweep[-0.17][5] < RING                                   # …and τ = 0.20 does not
        @test sweep[-0.16][2] > RING                                   # τ = 0.02 RINGS…
        @test sweep[-0.16][5] < RING                                   # …and τ = 0.20 does not
        @test sweep[-0.12][5] > RING                                   # …while −0.12 still rings
        @test sweep[-0.17] ≈ [0.64469, 0.26854, 0.03934, 0.01562, 0.01261] atol = 2.0e-5
        @test sweep[-0.16] ≈ [0.86787, 0.62591, 0.35338, 0.07508, 0.02061] atol = 2.0e-5
        # ⇒ τ IS A CONFOUNDED LEVER, which is a STRONGER reason to keep it authored than a dead
        # one: it moves the amplitude on every arm, so a student dragging it would be moving the
        # verdict without moving the mechanism. ⭐ AND THE SLICE'S CLAIM SURVIVES THE WHOLE SPAN —
        # at EVERY τ the gimballed arm at the showcase residual is quiet where strapdown rings, so
        # the margin is not a τ artifact at any point in the domain.
        @test all(v < RING for v in sweep[-0.18])
        @test strap[-0.18].rms_r > RING
        # convention 9's real content: ONE slider. τ's own domain would be a second one.
    end

    @testset "⭐⭐ THE PRICE — `held ⟺ tracking error < detector window`, BRACKETED to 0.005°" begin
        # SLICE 32's PREDICATE RETURNS IN THE CURRENCY A GIMBAL ACTUALLY HAS. Slice 32 measured
        # `held ⟺ lead < fov` about the BODY; here the window is the DETECTOR's, about the HEAD,
        # and what it must cover is the TRACKING ERROR. ⚠ THE TWO SIDES COME FROM DIFFERENT RUNS —
        # the error off a FREE arm, the verdict off a WINDOWED one — which is what makes it a
        # measurement rather than a restatement.
        for (Rh, want_off, brk, held) in ((-0.18, 1.955643, 1.9550, 1.9600),
                                          (-0.16, 5.236820, 5.2000, 5.3000))
            free = gim[Rh]
            @test free.off_max ≈ want_off atol = 1.0e-5
            @test arm(Rhat = Rh, tau = 0.05, stop = 30.0, gfov = brk).out  > 0.0   # BREAKS
            @test arm(Rhat = Rh, tau = 0.05, stop = 30.0, gfov = held).out == 0.0  # HOLDS
            @test brk < free.off_max                        # …and the free arm's error is INSIDE
        end
        # ⚠ ON THE QUIET ARM THE BRACKET STRADDLES THE MEASURED ERROR TO 0.005°; on the RINGING one
        # the predictor is CONSERVATIVE by ~1 % (5.2368 predicted, held only from 5.30), because a
        # windowed arm is a DIFFERENT RUN and a ring diverges faster once it clips. Both directions
        # are stated rather than tuned away.
        @test arm(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 1.9600).out == 0.0
        @test arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 5.2400).out > 0.0
        # ⚠ §0.7's `⌈off_max⌉` RULE IS SUFFICIENT BUT NOT TIGHT, and gate 0 could not see that: it
        # swept a 1° grid, on which the ceiling happens to be the first held cell. On a 0.1° grid
        # the −0.16 row holds already at 5.30, 0.7° BELOW the ceiling.
        @test arm(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 2.0).out == 0.0
        @test arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 6.0).out == 0.0
        # ⭐ AND THE RING IS SPENT IN DETECTOR WINDOW — slice 33's payload in the new currency: the
        # requirement is 2.7× larger on the ringing arm than on the quiet one, same glass.
        @test gim[-0.16].off_max / gim[-0.18].off_max > 2.6
    end

    @testset "⚠⚠ THE METRIC INVERSION — no stability verdict may be read on a windowed arm" begin
        # MEASURED, not feared (§0.7). The head HOLDS when it loses its error signal, so a broken
        # window FREEZES the index — and a frozen index produces a CONSTANT bend, which has nothing
        # for `dε/dt` to differentiate. So `rms r` FALLS while the miss OPENS by two orders.
        free = gim[-0.16]
        win  = arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 1.0)
        @test free.n_band > 0 && win.n_band > 0
        @test win.miss ≈ 1254.83 atol = 0.05          # the miss OPENS, 220×
        @test win.miss / free.miss > 200.0
        @test win.rms_r < free.rms_r / 3.9            # …while `rms r` FALLS 4.2×
        @test win.rms_r ≈ 0.08491 atol = 2.0e-5
        # …and the arm's OWN `off_max` is the post-lock-loss runaway (slice 33's signature), not
        # the ring's 5.24° tracking error: 89.2° against a 30° mechanical stop.
        @test win.off_max > 80.0
        @test free.off_max < 6.0
        @test !isnan(win.t_break)
        @test win.t_break ≈ 3.349 atol = 0.01
    end

    @testset "⭐⭐ THE STOP AND THE WINDOW ARE ONE BUDGET, NOT TWO LIMITS" begin
        # GATE-2 FINDING, and no gate-0 arm could have seen it: every one of them ran the stop at
        # 30° or 1e6° against a head travel of at most 23.4°, so THE STOP NEVER BOUND IN ANY ARM
        # THAT HAS EVER FLOWN (gate 1 wrote that down as the reason `head_clamp`'s shape rests on a
        # species argument). Bind it, and the two limits turn out to be coupled: a clamped head
        # cannot reach the LOS, so its DEFICIT is spent out of the DETECTOR budget.
        #
        #     off_head ≈ (head requirement − stop) + free tracking error
        #
        # The showcase arm needs 18.1172° of travel and carries 1.956° of tracking error, so at a
        # detector window `W` the critical stop is ≈ 18.117 − W. MEASURED on three windows:
        for (W, tight, loose, want_off) in ((8.0, 10.0, 11.0, 7.133),
                                            (4.0, 14.0, 16.0, 2.227),
                                            (2.0, 16.0, 18.0, 1.956))
            @test arm(Rhat = -0.18, tau = 0.05, stop = tight, gfov = W).out  > 0.0   # BREAKS
            let ok = arm(Rhat = -0.18, tau = 0.05, stop = loose, gfov = W)
                @test ok.out == 0.0                                                  # HOLDS
                @test ok.head_max ≈ loose atol = 1.0e-9   # the stop BOUND, exactly, on the circle
                @test ok.off_max ≈ want_off atol = 2.0e-3 # …and the deficit landed on the detector
            end
        end
        # ⇒ THE PLAN'S "the stop reproduces slice 33's excursion — a RESTATEMENT" IS CONFIRMED AND
        # SHARPENED: the stop must cover the head's travel requirement (slice 33's number, 18.1172°
        # here), and whatever it fails to cover is charged to the window. A stop below the lead is
        # fatal on its own — the head is pinned, the LOS walks away from it, and the seeker never
        # recovers.
        let dead = arm(Rhat = -0.18, tau = 0.05, stop = 10.0, gfov = 8.0)
            @test dead.out == 100.0
            @test dead.miss > 3000.0
            @test isnan(dead.rms_r)          # never enters the band at all — slice 33's catch
        end
    end

    @testset "THE HANDOVER — `head_clamp` at init, and it is a stated §1 CONDITION" begin
        # §0.8 promoted slice 32's "handover basket" deferral to a LIVE constraint: a head that
        # starts CAGED at boresight must slew the WHOLE LEAD, so during acquisition its window
        # requirement degenerates to the STRAPDOWN one and `off_max` stops measuring the tracking
        # error at all. What ships is a HANDED-OVER head, and every number above is quoted for it.
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 30.0)
            tick!(w, sub, dt)
            c = w.entities[:m1].comp
            û = los_unit(w.entities[:m1].pos, w.entities[:t1].pos)
            la, le = look_angles(c[:att_q]::Quat, û)
            ha, he = head_clamp(la, le, deg2rad(30.0))
            # BIT-EXACT, against the SHIPPED KERNEL — this is gate 1's Finding 2 made enforceable:
            # a per-axis `clamp` here (which the gate-0 probe has) would hand tick 1 the one state
            # from which the servo is not a contraction, and nothing downstream could detect it.
            @test c[:head_az] === ha && c[:head_el] === he
            @test w.env[:telemetry]["m1.head_off_deg"] == 0.0       # …so the error starts at zero
            @test haskey(c, :head_tgt_az)      # its partner is minted on the SAME tick, which is
            @test haskey(c, :head_tgt_el)      # what lets the slew branch index it directly
        end
        # …and with a BINDING stop the handover lands ON THE CIRCLE, in the target's direction —
        # the disc invariant the servo needs, established at tick 1.
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 10.0)
            tick!(w, sub, dt)
            c = w.entities[:m1].comp
            @test hypot(c[:head_az], c[:head_el]) ≈ deg2rad(10.0) atol = 1.0e-12
            @test w.env[:telemetry]["m1.head_angle_deg"] ≈ 10.0 atol = 1.0e-9
        end
    end

    @testset "DRAW-COUNT INVARIANCE — class 4a, and it is ASSERTED not assumed" begin
        # The head is a DETERMINISTIC SERVO on a measurement that already exists, so it adds no
        # `randn` — convention 3, and what keeps the whole 25–33 family replay-compatible.
        for kw in ((;), (tau = 0.05, stop = 30.0), (tau = 0.05, stop = 30.0, gfov = 2.0),
                   (tau = 0.05, stop = 10.0, gfov = 1.0))
            w, sub = gim_world(; Rhat = -0.18, kw...)
            lo = 99; hi = 0
            for k in 1:600
                before = copy(w.rng)
                tick!(w, sub, dt); empty!(w.events)
                # replay the stream forward from the pre-tick state until it matches the post-tick
                # one: the number of `randn` that takes IS the tick's draw count.
                probe = copy(before); cnt = 0
                while probe != w.rng && cnt < 64
                    randn(probe); cnt += 1
                end
                k > 5 && (lo = min(lo, cnt); hi = max(hi, cnt))
            end
            # ⚠ BOTH BOUNDS, so a config that drew 2 on average but 1 and 3 on alternate ticks
            # could not pass — the draw TOPOLOGY is what convention 3 is about, not the mean.
            @test (lo, hi) == (2, 2)
        end
    end

    @testset "STALE READOUT — the rung gate, the SEVENTH occurrence of the `_atm_on` class" begin
        # `:head_az` / `:head_tgt_az` are minted by the seam and NEVER deleted, so a key-gated head
        # would keep slewing — and keep indexing the glass — off a FROZEN attitude after a
        # cross-toggle off `:six_dof`. The gate is the LIVE `:airframe`, and the assert is that the
        # toggle ships NO head keys rather than a plausible frozen set.
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 4.0)
            for k in 1:500; tick!(w, sub, dt); empty!(w.events); end
            live = w.env[:telemetry]::Dict{String,Any}
            @test haskey(live, "m1.gimbal_valid") && haskey(live, "m1.head_off_deg")
            w.fidelity[:airframe] = :pitch_coupled
            tick!(w, sub, dt); empty!(w.events)
            gone = w.env[:telemetry]::Dict{String,Any}
            for key in ("m1.head_angle_deg", "m1.head_off_deg", "m1.gimbal_valid",
                        "m1.gimbal_fov_deg", "m1.gimbal_stop_deg", "m1.gimbal_fov_margin_deg",
                        "m1.look_body_deg")
                @test !haskey(gone, key)
            end
            # ⭐ AND THE HEAD AND THE ATTITUDE IT IS MEASURED AGAINST FREEZE TOGETHER: the comp keys
            # survive (that is the hazard), but `:att_q` is written only by the rung-gated
            # `_integrate_6dof!`, so neither advances while the plant is elsewhere.
            @test haskey(w.entities[:m1].comp, :head_az)
            let fh = w.entities[:m1].comp[:head_az], fa = w.entities[:m1].comp[:att_q]
                for k in 1:50; tick!(w, sub, dt); empty!(w.events); end
                @test w.entities[:m1].comp[:head_az] === fh
                @test w.entities[:m1].comp[:att_q]   === fa
            end
        end
    end

    @testset "the TELEMETRY keys — and `look_angle` is now the HEAD's index" begin
        # ⚠ THE PER-TICK CHECKS ARE COUNTED AND ASSERTED ONCE (slice 33's `viol` shape): an `@test`
        # inside an 8000-tick loop would add 16 000 lines to the suite tally and say nothing more.
        let (w, sub) = gim_world(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 8.0)
            dmax = 0.0; offmax = 0.0; n_sign = 0; n_tri = 0; n_seen = 0
            for k in 1:8000
                n_seen += 1
                tick!(w, sub, dt); empty!(w.events)
                tel = w.env[:telemetry]::Dict{String,Any}
                # ⭐ THE SIGN IS THE VERDICT (slice 18's `terrain_clearance_m` / slice 33's
                # `seeker_fov_margin_deg`): built from the SAME `fov_h` and `off_head` the flying
                # predicate tested, so the two are the same bits and not two opinions.
                (tel["m1.gimbal_fov_margin_deg"] >= 0) == (tel["m1.gimbal_valid"] == 1.0) ||
                    (n_sign += 1)
                # ⭐⭐ SLICE 26's `look_angle` NOW SHIPS THE INDEX THE GLASS ACTUALLY USED, which
                # under a head is the HEAD's own angle — while `look_body_deg` carries the
                # strapdown quantity slice 32 called `look_angle`. They are DIFFERENT NUMBERS, and
                # their difference is bounded by the tracking error (an angle-space triangle
                # inequality: `hypot` is a norm, so ‖a‖ − ‖b‖ ≤ ‖a − b‖).
                d = abs(tel["m1.look_angle"] - tel["m1.look_body_deg"])
                d <= tel["m1.head_off_deg"] + 1.0e-9 || (n_tri += 1)
                dmax = max(dmax, d); offmax = max(offmax, tel["m1.head_off_deg"])
            end
            @test (n_sign, n_tri) == (0, 0)
            # …over a flight that actually ran: counted INSIDE the loop, because asserting the
            # loop bound is `x == x` (convention 11's tautology — advisor).
            @test n_seen == 8000
            # …and the two do genuinely diverge — a tooth that a seam quietly indexing on the nose
            # would fail, which is what makes the claim above a measurement.
            @test dmax > 2.5
            @test offmax > 2.5
        end
        # the LIMITS ship as AUTHORED numbers so the client draws the needles without recomputing
        # anything (convention 13), and `_finite_coord` so a negative slider survives the wire.
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 25.0, gfov = -1.0)
            tick!(w, sub, dt)
            tel = w.env[:telemetry]::Dict{String,Any}
            @test tel["m1.gimbal_stop_deg"] == 25.0
            @test tel["m1.gimbal_fov_deg"]  == -1.0        # AUTHORED, not the clamped value…
            @test tel["m1.gimbal_fov_margin_deg"] == 0.0   # …while the margin uses the CLAMP, so
            @test tel["m1.gimbal_valid"] == 1.0            # the two do NOT reconstruct each other
        end                                                # (slice 33's divergence, verbatim)
        # every key a SCALAR and finite (conventions 6/13) — no Array reaches the client's float()
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 2.0)
            for k in 1:1500; tick!(w, sub, dt); empty!(w.events); end
            tel = w.env[:telemetry]::Dict{String,Any}
            for key in ("m1.head_angle_deg", "m1.head_off_deg", "m1.gimbal_valid",
                        "m1.gimbal_fov_deg", "m1.gimbal_stop_deg", "m1.gimbal_fov_margin_deg",
                        "m1.look_body_deg", "m1.lead_angle_deg", "m1.look_angle")
                @test haskey(tel, key)
                @test tel[key] isa Float64 && isfinite(tel[key])
            end
        end
    end

    @testset "the DEFINED DEGENERATES — a live knob can never crash a tick (conventions 5/6)" begin
        # Every one of these runs to completion and ships finite telemetry; none of them throws
        # inside `observe!`, where the session's IO-only catch would silently drop the connection.
        for kw in ((tau = 0.05, stop = 30.0, gfov = -1.0),   # a window that never opens
                   (tau = 0.05, stop = 30.0, gfov = 0.0),    # …and its boundary
                   (tau = -1.0, stop = 30.0),                # τ < 0 ⇒ the exact landing (τ ≤ dt)
                   (tau = 0.0,  stop = 30.0),                # the minimum-lag head
                   (tau = 0.05, stop = -1.0, gfov = 8.0),    # a CAGED head — a strapdown seeker
                   (tau = 0.05, stop = 30.0, gfov = 1.0e9))  # …and an effectively infinite window
            a = arm(; n = 4000, Rhat = -0.18, kw...)
            @test isfinite(a.head_max) && isfinite(a.off_max) && a.out >= 0.0
        end
        # ⭐ THE CAGED HEAD IS PINNED TO THE ORIGIN, which by `off_axis_angle`'s identity IS the
        # strapdown seeker — gate 1's argument for one kernel rather than two, on the flying path.
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = -1.0, gfov = 8.0)
            n_moved = 0; n_disagree = 0
            for k in 1:300
                tick!(w, sub, dt); empty!(w.events)
                c = w.entities[:m1].comp
                tel = w.env[:telemetry]::Dict{String,Any}
                (hypot(c[:head_az], c[:head_el]) == 0.0 && tel["m1.head_angle_deg"] == 0.0) ||
                    (n_moved += 1)
                # …and with the head at the nose, the detector error IS the strapdown look angle
                isapprox(tel["m1.head_off_deg"], tel["m1.look_body_deg"]; atol = 1.0e-9) ||
                    (n_disagree += 1)
            end
            @test (n_moved, n_disagree) == (0, 0)
        end
    end

    @testset "loader: the head is PRESENCE-gated, and REFUSES a second window" begin
        mktempdir() do dir
            function write_scn(seekextra; two_angle = true)
                p = joinpath(dir, "g.yaml")
                open(p, "w") do io
                    print(io, "name: g\nseed: 32\ndt_physics: 1.0e-3\n",
                              "fidelity: {airframe: six_dof, autopilot: alpha, guidance: pn,\n",
                              "           seeker: filtered, seeker_axes: az_el}\n",
                              "entities:\n",
                              "  - id: m1\n    kind: missile\n    pos: [0.0, 0.0, 3000.0]\n",
                              "    missile:\n      mass_kg: 140.0\n      speed: 700.0\n",
                              "      elevation_deg: 12.0\n",
                              "      seeker: {two_angle: ", two_angle ? "true" : "false",
                              seekextra, "}\n",
                              "      guidance: {n_pn: 8.0}\n",
                              "      airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0,\n",
                              "                 cmq: -150.0, cla: 20.0, cy_beta: 20.0}\n",
                              "  - id: t1\n    kind: target\n    pos: [6000.0, 2000.0, 4200.0]\n",
                              "    vel: [0.0, 200.0, 0.0]\n    target: {rcs_m2: 1.0}\n")
                end
                return p
            end
            mis(p) = first(e for (_, e) in load_scenario(p).world.entities if e.kind === :missile)
            # ⚠⚠ THE YAML → COMP PATH, WHICH NOTHING IN THIS SLICE HAD TAKEN UNTIL NOW: every gate-0
            # probe and every measurement above injects the keys PROGRAMMATICALLY.
            let m = mis(write_scn(", gimbal_tau_s: 0.05, gimbal_stop_deg: 30.0, gimbal_fov_deg: 4.0"))
                @test m.comp[:gimbal_tau_s]    == 0.05
                @test m.comp[:gimbal_stop_deg] == 30.0
                @test m.comp[:gimbal_fov_deg]  == 4.0
            end
            # PRESENCE-GATED: no key authored ⇒ no key minted (convention 2 — every earlier wire).
            for k in (:gimbal_tau_s, :gimbal_stop_deg, :gimbal_fov_deg)
                @test !haskey(mis(write_scn("")).comp, k)
            end
            # A DEAD KNOB IS REFUSED, NOT SILENTLY IGNORED (the slice-21/28/29/31/32 precedent): the
            # head lives in `_observe_point3d!`, which only runs on the TWO-ANGLE host.
            @test_throws ErrorException load_scenario(
                write_scn(", gimbal_tau_s: 0.05"; two_angle = false))
            # …and the two limits are read ONLY inside the head branch, so without a head they are
            # dead too (the slice-31 gyro shape).
            @test_throws ErrorException load_scenario(write_scn(", gimbal_stop_deg: 30.0"))
            @test_throws ErrorException load_scenario(write_scn(", gimbal_fov_deg: 4.0"))
            # ⚠⚠ AND A BODY-FIXED FIELD OF VIEW IS REFUSED BESIDE A HEAD — this one is PHYSICS, not
            # hygiene. A gimballed seeker has no body-fixed window: its body-fixed limit is the
            # STOP and its window is the DETECTOR's. Authoring both would also force the seam to
            # choose which of two `look_angle` readouts wins — the head's index (what the glass
            # used) or the nose's (what slice 32 means) — and refusing is what makes that choice
            # unnecessary rather than silent.
            @test_throws ErrorException load_scenario(
                write_scn(", gimbal_tau_s: 0.05, seeker_fov_deg: 25.0"))
            @test_throws ErrorException load_scenario(
                write_scn(", seeker_fov_deg: 25.0, gimbal_tau_s: 0.05"))   # …in EITHER order
            # non-finite is a LOAD error: a NaN τ propagates into the head state and thence into the
            # bend, so it is validate-at-LOAD's business rather than the consumer's.
            @test_throws ErrorException load_scenario(write_scn(", gimbal_tau_s: .nan"))
            @test_throws ErrorException load_scenario(write_scn(", gimbal_tau_s: .inf"))
            @test_throws ErrorException load_scenario(
                write_scn(", gimbal_tau_s: 0.05, gimbal_fov_deg: .nan"))
            # …but NO positivity guard, deliberately: `τ ≤ dt` is the exact landing, `τ < 0` is
            # caught by that same comparison at the consumer, a non-positive stop is the CAGED head
            # and a non-positive window the never-acquires state — all defined, none a crash path.
            let m = mis(write_scn(", gimbal_tau_s: -1.0, gimbal_stop_deg: -1.0, gimbal_fov_deg: -1.0"))
                @test m.comp[:gimbal_tau_s] == -1.0 && m.comp[:gimbal_fov_deg] == -1.0
            end
            # THE ONE LIVE SLIDER is knob-registerable (`_parse_knobs` checks entity + key exist).
            let p = write_scn(", gimbal_tau_s: 0.05, gimbal_stop_deg: 30.0, gimbal_fov_deg: 4.0")
                write(p, read(p, String) *
                      "knobs:\n  - {target: m1, key: gimbal_fov_deg, min: 1.0, max: 8.0, label: FOV}\n")
                @test Dict(kb.key => kb.target for kb in load_scenario(p).knobs)[:gimbal_fov_deg] === :m1
            end
        end
        # THE PRESENCE GATE FROM THE OTHER SIDE: no earlier wire carries a head, so slices 1–33 are
        # byte-identical by GATING and not by a value that happens to agree.
        let base = joinpath(@__DIR__, "..", "..", "scenarios")
            for f in ("slice25_seeker_3d.yaml", "slice26_radome.yaml", "slice27_radome_comp.yaml",
                      "slice28_radome_curve.yaml", "slice29_radome_schedule.yaml",
                      "slice30_envelope.yaml", "slice31_gyro.yaml", "slice32_fov.yaml",
                      "slice33_budget.yaml")
                p = joinpath(base, f)
                isfile(p) || continue
                for (_, e) in load_scenario(p).world.entities
                    @test !haskey(e.comp, :gimbal_tau_s)
                    @test !haskey(e.comp, :gimbal_fov_deg)
                end
            end
        end
    end

    @testset "the KNOB DOMAIN — `gimbal_fov_deg` ∈ [1, 8], MEASURED at both ends" begin
        # The plan filed this to gate 1, which shipped kernels only. Measured here, on the two
        # residuals the showcase ladder is read at, against the two constraints the plan names.
        #
        # THE CEILING, 8°: the metric is FLAT above the requirement — a wider window is
        # bit-identical to no window at all (CONTROL B above), so nothing is hidden past it, and
        # 8 clears the ringing arm's 5.24° requirement with room to see the cliff either side.
        for wdeg in (8.0, 10.0, 20.0)
            @test arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = wdeg).out == 0.0
        end
        # THE FLOOR, 1°: below it the arm never enters r ∈ [500, 3000] at all, so `rms r` is NaN
        # and a verifier's own band column would count NOTHING (slice 33's gate-2 catch). At 1.0
        # both residuals are deep in the broken regime with a live band, which is what the floor
        # has to guarantee.
        for Rh in (-0.18, -0.16)
            let a = arm(Rhat = Rh, tau = 0.05, stop = 30.0, gfov = 1.0)
                @test a.out > 60.0 && a.miss > 1000.0 && a.n_band > 0 && !isnan(a.rms_r)
            end
            @test isnan(arm(Rhat = Rh, tau = 0.05, stop = 30.0, gfov = 0.5).rms_r)
        end
        # ⚠ AND THE DOMAIN IS NOT MONOTONE IN THE MISS — stated rather than hidden (slice 22's
        # "a ~1.03× margin, stated"). On the RINGING arm the broken regime wiggles by ~4 %
        # (1.9° → 546 m vs 2.0° → 569 m) because a windowed arm is a different trajectory, not a
        # degraded copy of one. The LESSON is the CLIFF at the requirement, which is sharp in both
        # rows, and the domain brackets it rather than resting on the broken regime's ordering.
        let lo = arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 1.9),
            hi = arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 2.0)
            @test lo.miss > 500.0 && hi.miss > 500.0
            @test hi.miss > lo.miss              # the non-monotone cell, PINNED as a fact
        end
    end

    @testset "gate 3 — the TWO SHIPPED WIRES, and the marker the loader's refusal made necessary" begin
        # ⭐⭐ SLICE 34 SHIPS TWO SCENARIOS AND THE PAIR IS THE LESSON (slice 22's precedent — two
        # wires for one slice, when the halves need configurations that cannot coexist). A head is
        # not a fidelity: `gimbal_tau_s` is AUTHORED and there is NO in-domain slider value that
        # removes a head — τ → 0 does not, because the head that ships tracks its own BENT,
        # one-tick-delayed measurement and is ALREADY QUIET there (0.03394 against strapdown's
        # 0.93194, measured three testsets up). So the foil has to be a second wire.
        base = joinpath(@__DIR__, "..", "..", "scenarios")
        gim_scn  = load_scenario(joinpath(base, "slice34_gimbal.yaml"))
        strp_scn = load_scenario(joinpath(base, "slice34_strapdown.yaml"))
        g1 = gim_scn.world.entities[:m1];  gt = gim_scn.world.entities[:tgt1]
        s1 = strp_scn.world.entities[:m1]; st = strp_scn.world.entities[:tgt1]

        # ⚠⚠ THE MARKER, AND IT EXISTS BECAUSE THE LOADER'S REFUSAL LEAVES A HOLE THE CLIENT WOULD
        # FALL THROUGH SILENTLY (gate-3 review, advisor). `seeker_fov_deg` is REFUSED beside a head,
        # so a gimbal wire raises `radome_view` — it HAS glass — and NOT `seeker_fov_view`: both of
        # the client's FOV branches fail their conjunction and slice 26/27/28's RADOME cascade takes
        # it. ⚠ That failure is the stale-readout class's WORST form, because NOTHING IN IT IS
        # STALE: every key that cascade reads (`radome_slope`, `radome_residual*`,
        # `radome_slope_worst`, `omega_r`) is LIVE here, so it would print a fluent ring/quiet
        # verdict about the GLASS on a wire whose whole subject is the HEAD — the wrong subject,
        # from real telemetry, and not one test would have failed.
        let info = EWSim._airframe_view_info(gim_scn.world)
            @test info[:gimbal_view]   === true
            @test info[:radome_view]   === true            # it HAS glass…
            @test !haskey(info, :seeker_fov_view)          # …and CANNOT have slice 32's window
            @test info[:airframe_6dof] === true            # still the slice-23 3-D view
        end
        # THE TWIN raises the 26–33 marker set EXACTLY — no head, no new branch.
        let info = EWSim._airframe_view_info(strp_scn.world)
            @test !haskey(info, :gimbal_view)
            @test info[:radome_view]   === true
            @test !haskey(info, :seeker_fov_view)
            @test info[:airframe_6dof] === true
        end
        # …and NO earlier wire grows one, which is slice 32's `!haskey(info, :radome_view)`-as-a-
        # feature discipline pointed at the new key: the branches must stay distinguishable from the
        # CORE side, because that conjunction is what the client dispatches on.
        for f in ("slice26_radome.yaml", "slice30_envelope.yaml", "slice31_gyro.yaml",
                  "slice32_fov.yaml", "slice33_budget.yaml")
            p = joinpath(base, f)
            isfile(p) || continue
            @test !haskey(EWSim._airframe_view_info(load_scenario(p).world), :gimbal_view)
        end

        # ⭐ THE TWIN IS THE GIMBAL WIRE WITH THE HEAD REMOVED AND NOTHING ELSE CHANGED — asserted
        # key-for-key rather than described in a comment, because the whole claim ("same glass, same
        # residual, same seed") rests on it and a single drifted digit would make the 78.9× a
        # comparison of two different missiles.
        for k in (:radome_slope, :radome_ripple, :radome_ripple_k, :radome_slope_est,
                  :sigma_seek, :alpha, :beta, :seek_two_angle, :n_pn, :a_max, :delta_max,
                  :k_alpha, :k_q, :mass_kg, :cd_area_m2, :rho, :af_cma, :af_cmd, :af_cmq,
                  :af_cla, :af_alpha_max, :af_cy_beta, :af_I, :af_I_roll, :af_I_zz, :af_c_roll,
                  :af_d, :af_S)
            @test g1.comp[k] == s1.comp[k]
        end
        @test g1.pos == s1.pos && g1.vel == s1.vel
        @test gt.pos == st.pos && gt.vel == st.vel
        @test gim_scn.world.seed == strp_scn.world.seed == 32
        @test gim_scn.world.fidelity == strp_scn.world.fidelity
        @test gim_scn.dt_physics == strp_scn.dt_physics == 1.0e-3
        # ⚠ THE SAME EMIT GRID ON BOTH, so the pair is read on one grid — and it is what
        # `slice34_verify.gd`'s `STEPS` must be a MULTIPLE OF (convention 14; slice 31 lost an hour
        # to the silent hang, and this slice's verifier flies BOTH wires through one `load_scenario`
        # so a mismatch would hang on the second half only).
        @test gim_scn.emit_every == strp_scn.emit_every == 16
        # …and the ONE difference, both ways round.
        for k in (:gimbal_tau_s, :gimbal_stop_deg, :gimbal_fov_deg)
            @test haskey(g1.comp, k) && !haskey(s1.comp, k)
        end
        @test !haskey(g1.comp, :seeker_fov_deg) && !haskey(s1.comp, :seeker_fov_deg)

        # THE WIRE ITSELF.
        @test g1.comp[:gimbal_tau_s]    == 0.05     # AUTHORED — a CONFOUNDED lever (τ testset above)
        @test g1.comp[:gimbal_stop_deg] == 30.0     # AUTHORED — a RESTATEMENT of slice 33's excursion
        @test g1.comp[:gimbal_fov_deg]  == 4.0      # the ONE live slider's default
        @test g1.comp[:radome_slope_est] == -0.18   # ⭐⭐ INSIDE the strapdown bracket (−0.27, −0.24]
        @test g1.comp[:radome_slope]     == -0.03   # …and OUTSIDE the gimballed one (−0.18, −0.16]
        @test g1.comp[:radome_ripple]    == -0.15   # ⇒ radome_slope_worst = R₀ + 2A = −0.33
        @test gt.comp[:cross_speed_mps] == 200.0 && gt.vel.y == 200.0   # the pin and `vel` AGREE
        @test gim_scn.world.fidelity[:airframe]    === :six_dof
        @test gim_scn.world.fidelity[:seeker_axes] === :az_el
        @test !haskey(gim_scn.world.fidelity, :steering)   # BTT would be a THIRD mechanism
        for k in (:gyro_scale_err, :gyro_bias_z, :gyro_bias_y)   # slice 31's terms are ABSENT
            @test !haskey(g1.comp, k) && !haskey(s1.comp, k)
        end

        # THE KNOBS — TWO on the head wire (the two halves of ONE comparison, `window` vs
        # `tracking error(R̂)`), ONE on the twin, and the SHARED key is shared over the SAME domain
        # because the experiment is "walk this slider on both wires and read where the ring dies".
        let kg = Dict(kb.key => kb for kb in gim_scn.knobs),
            ks = Dict(kb.key => kb for kb in strp_scn.knobs)
            @test length(gim_scn.knobs) == 2 && length(strp_scn.knobs) == 1
            @test kg[:gimbal_fov_deg].target === :m1 && kg[:radome_slope_est].target === :m1
            # the DETECTOR window: the floor is inside the cliff (the design's free error is 1.956°),
            # the ceiling is THE FREE READ — bit-identical to the key being absent (CONTROL B).
            @test (kg[:gimbal_fov_deg].min, kg[:gimbal_fov_deg].max) == (1.0, 8.0)
            @test kg[:gimbal_fov_deg].max > 5.92     # clear of the LOUDEST arm's own requirement
            @test kg[:gimbal_fov_deg].min < 1.956    # …and the floor is inside the cliff
            # R̂: the SAME domain on both wires, reaching PAST slice 30's aim point (R₀ + 2A) so the
            # rule is reachable AND overshootable (the one-sided constraint).
            @test (kg[:radome_slope_est].min, kg[:radome_slope_est].max) == (-0.36, -0.03)
            @test (ks[:radome_slope_est].min, ks[:radome_slope_est].max) ==
                  (kg[:radome_slope_est].min, kg[:radome_slope_est].max)
            @test kg[:radome_slope_est].min < g1.comp[:radome_slope] + 2 * g1.comp[:radome_ripple]
            @test kg[:radome_slope_est].max == g1.comp[:radome_slope]
            # DISQUALIFIED AND ASSERTED ABSENT — on BOTH wires. ⚠ `gimbal_tau_s` heads this list and
            # its exclusion is the one that is MEASURED rather than argued (the τ testset above): the
            # sag is monotone everywhere and AT THE LINE it crosses the verdict, so a student
            # dragging it would move the verdict without moving the mechanism.
            for k in (:gimbal_tau_s, :gimbal_stop_deg, :cross_speed_mps, :radome_slope,
                      :radome_ripple, :radome_ripple_k, :af_alpha_max, :n_pn, :rho, :sigma_seek,
                      :elevation_deg, :speed, :seeker_fov_deg)
                @test !haskey(kg, k) && !haskey(ks, k)
            end
            @test !haskey(ks, :gimbal_fov_deg)       # …and the twin has no window at all
        end

        # ⭐⭐ THE INDEX, ON THE SHIPPED WIRE: slice 26's `look_angle` ships the HEAD's own angle —
        # `look_az, look_el = head_az, head_el` before the bend is taken — so the two keys carry the
        # SAME NUMBER BY CONSTRUCTION, while `look_body_deg` (the NOSE's angle, what a strapdown
        # seeker would have used) is a DIFFERENT one. That triple IS the slice, and it is asserted
        # as bit-identity and inequality rather than left to the HUD to imply.
        # ⚠⚠ AND THE TICK-1 EXCEPTION IS THE HANDOVER, WHICH IS A §1 CONDITION AND NOT AN ARTIFACT —
        # this testset's first draft asserted "never the nose's" and FAILED on exactly one tick. A
        # HANDED-OVER head initialises to the CLAMPED TRUTH look angles, so on the tick it is born
        # the head's angle IS the nose-referenced one, and the two keys agree BY CONSTRUCTION. From
        # tick 2 the servo is tracking its own BENT measurement and they never agree again. ⇒ the
        # tooth is the DIVERGENCE, pinned as "equal exactly once, at the handover", which is
        # strictly stronger than the claim it replaces: it also proves the handover happened where
        # the scenario says it does (gate 0's §0.8 measured a CAGED head reading 18.117° instead —
        # the strapdown requirement — so this distinguishes the two inits as well).
        let (w, sub) = gim_world(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 4.0)
            n_idx = 0; same_ticks = Int[]
            for k in 1:600
                tick!(w, sub, dt); empty!(w.events)
                tel = w.env[:telemetry]::Dict{String,Any}
                tel["m1.look_angle"] === tel["m1.head_angle_deg"] || (n_idx += 1)
                tel["m1.look_angle"] == tel["m1.look_body_deg"]   && push!(same_ticks, k)
            end
            @test n_idx == 0                       # the glass used the HEAD's index, EVERY tick…
            @test same_ticks == [1]                # …and it is the NOSE's on the handover tick ALONE
        end

        # ⭐ THE SHIPPED DEFAULT WINDOW IS A FREE READ ON THE APPROACH, MEASURED AND NOT ASSUMED —
        # which is what licenses reading a STABILITY verdict off the default arm at all (the two-run
        # discipline forbids one on an arm whose window binds). ⚠ It is NOT bit-identical to the key
        # being absent, and that is stated rather than hidden: the window IS reached in the last
        # metres as the LOS unit vector swings through a large angle at r → 0 (slice 33's own endgame
        # finding), which moves the CPA by ~9e−11 m. The claim is 0.00 % out at r > 200 m.
        let ship = arm(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 4.0), free = gim[-0.18]
            @test ship.out == 0.0
            @test ship.rms_r ≈ free.rms_r atol = 1.0e-9
            @test ship.off_max ≈ free.off_max atol = 1.0e-9
            @test ship.head_max ≈ free.head_max atol = 1.0e-9
            @test abs(ship.miss - free.miss) < 1.0e-6
            # …and the twin's own default arm IS the strapdown ladder's −0.18 rung, to the digit.
            @test strap[-0.18].rms_r ≈ 0.93194 atol = 2.0e-5
            @test strap[-0.18].rms_r / ship.rms_r ≈ 78.9 atol = 0.2
        end

        # ⭐⭐ AND THE R̂ SLIDER IS THE CLIENT-DRIVABLE PAYLOAD ON THE SHIPPED WINDOW: the RING IS
        # SPENT IN DETECTOR WINDOW. Held at the default 4°, walking R̂ up from the showcase residual
        # drives the tracking error past the window and the track breaks — while walking it DOWN to
        # slice 30's aim point holds. ⚠ THE BROKEN ARMS' BAND IS EMPTY (slice 33's gate-2 catch), so
        # no band number may be quoted for them and none is.
        let hold18 = arm(Rhat = -0.18, tau = 0.05, stop = 30.0, gfov = 4.0),
            hold33 = arm(Rhat = -0.33, tau = 0.05, stop = 30.0, gfov = 4.0),
            brk16  = arm(Rhat = -0.16, tau = 0.05, stop = 30.0, gfov = 4.0),
            brk03  = arm(Rhat = -0.03, tau = 0.05, stop = 30.0, gfov = 4.0)
            @test hold18.out == 0.0 && hold33.out == 0.0
            @test hold18.miss < 1.0 && hold33.miss < 1.0
            @test brk16.out > 0.0 && brk16.miss > 100.0
            @test brk03.out > 50.0 && brk03.miss > 3000.0
            @test brk03.n_band == 0              # …and its band is EMPTY, so `rms r` is NaN
            @test isnan(brk03.rms_r)
            # the free arms' own tracking errors are what those windows are being compared against
            @test gim[-0.18].off_max < 4.0 < gim[-0.03].off_max
        end

        # ⭐ THE R̂ SLIDER'S FLOOR, MEASURED ON BOTH WIRES — the gate-3 post-review catch (advisor).
        # The YAML cites slice 26's post-commit rule (ENDPOINTS MEASURED, never inferred from the
        # interior) and then applied it only to the WINDOW knob: R̂'s CEILING is flown everywhere
        # (−0.03, both wires) and its FLOOR was flown NOWHERE. That is exactly the omission slice
        # 26's own post-commit was about, one slice later and in a knob it did not own.
        # ⚠ AND IT IS NOT HYGIENE, BECAUSE OF WHAT THE FLOOR IS FOR: past slice 30's aim point the
        # engagement residual goes POSITIVE, which de-tunes rather than rings (slice 30's one-sided
        # constraint) — but a de-tuned loop LAGS, lag grows the LEAD, and the lead is what the head's
        # TRAVEL must cover (vs the stop) and what sets the TRACKING ERROR (vs the window). If either
        # crossed, the student's own "overshoot cure B" gesture would break the arm.
        let fg   = arm(Rhat = -0.36, tau = 0.05, stop = 30.0, gfov = 4.0),
            fgf  = arm(Rhat = -0.36, tau = 0.05, stop = 30.0, gfov = 8.0),
            fs   = arm(Rhat = -0.36),
            aimg = arm(Rhat = -0.33, tau = 0.05, stop = 30.0, gfov = 4.0)
            # It holds, on BOTH wires, with BOTH limits clear.
            @test fg.out == 0.0 && fs.out == 0.0
            @test fg.miss < 1.0 && fs.miss < 1.0
            @test fg.n_band > 0 && fs.n_band > 0
            @test fg.rms_r < 0.30 && fs.rms_r < 0.30          # QUIET — a de-tune never rings
            @test fg.head_max < 30.0                          # …the STOP does not bind…
            @test fg.off_max  < 4.0                           # …nor the shipped WINDOW…
            @test abs(fgf.miss - fg.miss) < 1.0e-6            # …which is why 4° is inert here too
            # (⚠ `defl_sat` is NOT asserted here — this testset's `arm` does not measure it, and a
            #  claim needs a measurement rather than a plausible-looking line. It is carried on the
            #  wire instead, where `slice34_verify.gd`'s PHASE ISOLATION counts it band-gated on
            #  every arm INCLUDING both floor arms.)
            # ⭐⭐ AND THE OVERSHOOT IS A DE-TUNE THAT *REVERSES*, NOT A PLATEAU — which CORRECTS the
            # scenario comment this catch was found by. The YAML said the student "can overshoot it
            # and see that the requirement STOPS FALLING"; what actually happens is that the RING
            # turns back UP (0.05917 → 0.06946 gimballed, 0.05879 → 0.06911 strapdown) and the MISS
            # grows monotonically past the aim point (0.161 → 0.433, and on to 5.669 at R̂ = −0.50,
            # measured beyond the domain). Slice 30's one-sided constraint is intact — it never
            # RINGS — but "stops falling" was the wrong verb, and the DETECTOR bill is not even
            # monotone here (1.599 → 1.508 → 1.383 at −0.33/−0.36/−0.40, a minimum past the aim
            # point). The floor is where the REVERSAL is visible and both limits still have margin.
            @test fg.rms_r > aimg.rms_r
            @test fs.rms_r > strap[-0.33].rms_r
            @test fg.miss  > aimg.miss
        end
    end
end

# ---------------------------------------------------------------------------------------------
# SLICE 35 — A RATE-LIMITED HEAD: THE BANDWIDTH THAT HOLDS THE TRACK IS THE BANDWIDTH THAT FEEDS
# THE LOOP (§11 Tier-A, gate 2 — the seam, the loader and the telemetry).
#
# Slice 34's head was INFINITELY FAST: `head_slew` moved it a full first-order step every tick with
# no bound on how far. A real gimbal has a servo with a maximum slew rate, and the moment it does the
# head's motion stops being free — it becomes a RESOURCE spent against a demand. THE DEMAND IS SET BY
# THE PARASITIC LOOP: on a settled collision course the head barely moves (slice 34's
# `head_angle_deg` is a *constant* 17.190°) and the band demand is 0.600 °/s; let the loop ring and
# the same head must chase its own oscillation at 60.831 °/s — 53.6× more, ACROSS SLICE 34's OWN
# ONSET BRACKET. See `docs/plans/slice35.md`.
#
# ⭐⭐ AND IT IS THE ARC'S FIRST TWO-SIDED KNOB. Slices 32, 33 and 34 all end "widen it — it is free"
# (a wider FOV, a wider detector window, costing nothing but glass). THAT CURE DOES NOT TRANSFER:
# servo bandwidth is not a window, it is what the parasitic loop FEEDS ON. Slow the head and the ring
# is attenuated while the tracking error it must cover GROWS — one knob, two bounds, pulling in
# opposite directions.
#
# ⚠ NO new rung, no new cap, no new instability, no new draw (class 4a, the ELEVENTH consecutive
# RNG-live slice — 2 randn/tick, the seed load-bearing). Gate 1 shipped the kernel; this is the WIRE.
@testset "A RATE-LIMITED HEAD wired (slice 35 — the bandwidth that feeds the loop)" begin
    dt = 1.0e-3

    # Slice 34's `gim_world` with the SERVO key added, held to the digit for the same reason: the
    # rate-absent column must reproduce slice 34 exactly, so any movement is the servo and nothing
    # else. ⚠ `gfov = nothing` (an ABSENT window ⇒ the 1e6 default) IS THE DEFAULT HERE and slice
    # 34's 4° is not — see the two-sided-knob block below, where it is a load-bearing condition and
    # not a convenience.
    function rate_world(; vy = 200.0, seed = 32, R = -0.03, A = -0.15, Rhat = -0.18,
                          tau = 0.05, stop = 30.0, gfov = nothing, rate = nothing)
        w = World(seed = seed,
                  fidelity = Dict{Symbol,Symbol}(:integrator => :rk4, :guidance => :pn,
                                                 :autopilot => :alpha, :airframe => :six_dof,
                                                 :seeker => :filtered, :seeker_axes => :az_el))
        el = deg2rad(12.0); V0 = 700.0
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.0,
                                :af_S => π * 0.1^2, :af_d => 0.2, :af_I => 20.0,
                                :af_cma => -1.0, :af_cmd => 3.0, :af_cmq => -150.0,
                                :af_alpha0 => 0.0, :af_delta => 0.0, :af_cla => 20.0,
                                :af_alpha_max => 0.3, :af_cy_beta => 20.0,
                                :af_I_roll => 2.0, :af_I_zz => 20.0, :af_c_roll => 50.0,
                                :n_pn => 8.0, :a_max => 3000.0, :delta_max => 0.5,
                                :k_alpha => 1.0, :k_q => 0.3,
                                :kp => 2.0, :ki => 0.0, :kd => 0.0, :tau => 0.3, :dt_s => dt,
                                :sigma_seek => 5.0e-5, :alpha => 0.30, :beta => 0.05,
                                :seek_two_angle => true)
        if R !== nothing
            comp[:radome_slope] = R; comp[:radome_ripple] = A; comp[:radome_ripple_k] = 12.0
            Rhat === nothing || (comp[:radome_slope_est] = Rhat)
        end
        if tau !== nothing
            comp[:gimbal_tau_s] = tau
            stop === nothing || (comp[:gimbal_stop_deg] = stop)
            gfov === nothing || (comp[:gimbal_fov_deg]  = gfov)
            rate === nothing || (comp[:gimbal_rate_dps] = rate)   # DEGREES PER SECOND at the wire
        end
        w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0.0, 0.0, 3000.0),
                                 vel = Vec3(V0 * cos(el), 0.0, V0 * sin(el)), comp = comp)
        w.entities[:t1] = Entity(:t1, :target; pos = Vec3(6000.0, 2000.0, 4200.0),
                                 vel = Vec3(0.0, vy, 0.0),
                                 comp = Dict{Symbol,Any}(:cross_speed_mps => vy))
        return w, Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:t1)]
    end

    # ⚠ TWO REQUIREMENT COLUMNS, AND KEEPING THEM APART IS THIS GATE'S OWN FINDING (see the
    # ACQUISITION block): `off_band` is the tracking error inside the arc's [500, 3000] m band —
    # the only one attributable to the LOOP, because the band excludes the launch turn BY
    # CONSTRUCTION — while `off_max` is the whole-approach maximum, which a rate limit moves for a
    # completely different reason. `dem` is the SHIPPED `head_rate_dps` (PRE-limit) and `ach` the
    # finite difference on the head's own state (what it actually DID); on a bound arm they must
    # DISAGREE, which is the entire reason the telemetry key exists.
    function rarm(; n = 22000, trace = false, kw...)
        w, sub = rate_world(; kw...)
        miss = Inf; r_prev = Inf
        off_band = 0.0; off_max = 0.0; r_at_max = NaN
        n_band = 0; sum_r2 = 0.0; n_sat_band = 0; nt = 0; n_out = 0
        dem = Float64[]; ach = Float64[]; ach_sat = Float64[]
        haz_p = NaN; hel_p = NaN; tel1 = Dict{String,Any}()
        tr = Vec3[]
        for k in 1:n
            tick!(w, sub, dt); empty!(w.events)
            m = w.entities[:m1]; t = w.entities[:t1]; c = m.comp
            tel = get(w.env, :telemetry, Dict{String,Any}())
            k == 1 && (tel1 = copy(tel))
            trace && push!(tr, m.pos)
            r = los_range(m.pos, t.pos)
            haz = Float64(get(c, :head_az, NaN)); hel = Float64(get(c, :head_el, NaN))
            fd = (!isnan(haz_p) && !isnan(haz)) ?
                 rad2deg(hypot(haz - haz_p, hel - hel_p)) / dt : NaN
            haz_p = haz; hel_p = hel
            if r > 200                       # slice 32's endgame-spike gate, inherited with it
                nt += 1
                get(tel, "m1.gimbal_valid", 1.0) == 0.0 && (n_out += 1)
                o = get(tel, "m1.head_off_deg", 0.0)
                o > off_max && (off_max = o; r_at_max = r)
            end
            if 500 <= r <= 3000
                n_band += 1
                off_band = max(off_band, get(tel, "m1.head_off_deg", 0.0))
                ω = get(c, :omega_body, zero(Vec3))::Vec3
                sum_r2 += ω[3]^2
                if haskey(tel, "m1.head_rate_dps")
                    tel["m1.head_rate_sat"] == 1.0 && (n_sat_band += 1)
                    push!(dem, tel["m1.head_rate_dps"])
                    if !isnan(fd)
                        push!(ach, fd)
                        tel["m1.head_rate_sat"] == 1.0 && push!(ach_sat, fd)
                    end
                end
            end
            r > r_prev && miss == Inf && (miss = r_prev)
            r_prev = r
            miss < Inf && k > 200 && break
        end
        pct(v, q) = isempty(v) ? NaN : sort(v)[max(1, ceil(Int, q * length(v)))]
        return (; miss, off_band, off_max, r_at_max, n_band, trace = tr, tel1, ach_sat,
                  rms_r    = n_band == 0 ? NaN : sqrt(sum_r2 / n_band),
                  sat_band = n_band == 0 ? NaN : 100 * n_sat_band / n_band,
                  dem_p95  = pct(dem, 0.95), ach_p95 = pct(ach, 0.95),
                  out      = nt == 0 ? 0.0 : 100 * n_out / nt)
    end

    posdiff35(a, b) = (@assert length(a) == length(b);
                       maximum(hypot((x - y)...) for (x, y) in zip(a, b)))

    @testset "BYTE-IDENTITY — the ABSENT key is slice 34, and it is the ONLY control" begin
        # Convention 2's master check, read off the WIRE. The seam defaults `rate_max` to `Inf`,
        # which gate 1's `sat = dem > cap` polarity makes take the OLD CODE PATH — so slice 34 is
        # bit-identical BY CONSTRUCTION and not by a value that happens to agree.
        for Rh in (-0.33, -0.18, -0.16, -0.03)
            a = rarm(n = 9000, trace = true, Rhat = Rh)
            b = rarm(n = 9000, trace = true, Rhat = Rh, rate = 1.0e6)
            @test posdiff35(a.trace, b.trace) == 0.0
        end
        # …and the slice-34 ladder itself, to the digit (`rate_world` holds everything else).
        @test rarm(Rhat = -0.18).rms_r ≈ 0.01181 atol = 2.0e-5
        @test rarm(Rhat = -0.03).rms_r ≈ 0.88465 atol = 2.0e-5
        @test rarm(Rhat = -0.33).rms_r ≈ 0.05917 atol = 2.0e-5

        # ⚠⚠ AND THE DOMAIN CEILING IS **NOT** THE CONTROL — pinned as a POSITIVE fact so that gate 3
        # cannot author `gimbal_rate_dps = 60` expecting `max|Δpos| == 0` and read the near-miss as a
        # rounding residual in the new branch. The peak demand is an identical 72.542 °/s on EVERY
        # arm (the tick-2 HANDOVER transient), so a 60 °/s servo clips it and the trajectory moves.
        for (Rh, floor_m) in ((-0.33, 0.6), (-0.18, 0.04), (-0.03, 0.16))
            a = rarm(n = 9000, trace = true, Rhat = Rh)
            b = rarm(n = 9000, trace = true, Rhat = Rh, rate = 60.0)
            @test posdiff35(a.trace, b.trace) > floor_m       # measurably NOT inert
        end

        # THE NEVER-STALE DISCIPLINE: no head ⇒ not one servo key is even evaluated.
        let (w, sub) = rate_world(Rhat = -0.18, tau = nothing)
            for k in 1:200; tick!(w, sub, dt); empty!(w.events); end
            tel = w.env[:telemetry]::Dict{String,Any}
            for key in ("m1.head_rate_dps", "m1.head_rate_sat", "m1.gimbal_rate_dps")
                @test !haskey(tel, key)
            end
        end
        # …and WITH a head but no authored rate the cap ships as the FINITE_CEIL sentinel, never the
        # `Inf` that is its true default (convention 6 — no non-finite reaches the wire).
        let a = rarm(n = 3, Rhat = -0.18)
            @test a.tel1["m1.gimbal_rate_dps"] == FINITE_CEIL
        end
    end

    @testset "⭐⭐ THE SHIPPED DEMAND IS PRE-LIMIT — on a BOUND arm it DISAGREES with the motion" begin
        # This is the whole reason `head_slew_full` exists. The plan FORBIDS reconstructing the
        # demand as a post-hoc difference of `:head_az`; here is the measurement that says why —
        # a post-hoc difference reads the CLIPPED motion and would report the CAP as the demand,
        # i.e. it would report the answer as the question.
        let a = rarm(Rhat = -0.03, rate = 8.0)
            @test a.n_band > 0
            @test a.dem_p95 ≈ 214.958 atol = 0.01     # what the servo was ASKED for
            @test a.ach_p95 ≈ 8.000   atol = 1.0e-6   # what it DID — the cap, exactly
            @test a.dem_p95 > 25 * a.ach_p95          # ~27×, and they are not the same number
            # ⭐ ON EVERY SATURATED TICK THE HEAD MOVES EXACTLY THE CAP — both ends of the set, so
            # this is the whole distribution and not one lucky tick. (RADIAL, so the achieved step
            # is `cap` and not `√2·cap` on the diagonal — gate 1's species argument, on the wire.)
            @test !isempty(a.ach_sat)
            @test maximum(a.ach_sat) ≈ 8.0 atol = 1.0e-9
            @test minimum(a.ach_sat) ≈ 8.0 atol = 1.0e-9
        end
        # …and where NOTHING binds the two methods AGREE, which is what makes the disagreement above
        # a measurement rather than a units bug: same arm, same band, one number.
        let a = rarm(Rhat = -0.18, rate = 8.0)
            @test a.sat_band == 0.0
            @test a.dem_p95 ≈ a.ach_p95 atol = 1.0e-9
            @test isempty(a.ach_sat)
        end
        # THE FLAG IS THE KERNEL'S OWN BRANCH, never a hand-rolled compare (the `aero_sat`/
        # `defl_sat`/`gimbal_valid` shape).
        @test rarm(Rhat = -0.03, rate = 8.0).sat_band ≈ 97.14 atol = 0.05
        # THE HANDOVER TICK SHIPS ZERO, AND IT IS THE ABSENCE OF A SLEW: tick 1 calls `head_clamp`
        # and never `head_slew`, so there is no demand to report. A verifier reading tick 1 must not
        # mistake this for a quiet servo.
        let a = rarm(n = 3, Rhat = -0.03, rate = 8.0)
            @test a.tel1["m1.head_rate_dps"]   == 0.0
            @test a.tel1["m1.head_rate_sat"]   == 0.0
            @test a.tel1["m1.gimbal_rate_dps"] == 8.0
        end
    end

    @testset "⭐ THE FROZEN-HEAD DEGENERATE, **FLOWN** — `rate ≤ 0` IS slice 34's `τ = Inf` reductio" begin
        # ⚠ THE LOADER PERMITS `gimbal_rate_dps ≤ 0` DELIBERATELY (no positivity guard — it is a
        # DEFINED degenerate the kernel owns, not a crash path) and the loader block below proves it
        # LOADS. This block proves it FLIES, which is the part a load test cannot reach: at gate 3
        # the key is a DECLARED KNOB, and `set_param` writes a knob with NO clamp and NO
        # revalidation, so a client can put the wire here live (convention 5's clamp-at-CONSUMER —
        # the consumer is `max(rate_max, 0)`).
        #
        # ⭐ AND THE IDENTITY IS EXACT, FROM THE OTHER SIDE. `cap = max(rate, 0)·Δt = 0` ⇒ `sat` is
        # TRUE on every tick with a demand and `sc = 0/dem = 0`, so the head FREEZES at its handover
        # pointing — which is what an infinitely SLUGGISH servo does too. The two ways of freezing
        # the same head agree BIT-FOR-BIT, which is the third direction gate 1's docstring names.
        function frozen(; n = 4000, kw...)
            w, sub = rate_world(; kw...)
            tr = Vec3[]; haz = Float64[]; tel1 = Dict{String,Any}(); telN = Dict{String,Any}()
            for k in 1:n
                tick!(w, sub, dt); empty!(w.events)
                push!(tr, w.entities[:m1].pos)
                push!(haz, Float64(get(w.entities[:m1].comp, :head_az, NaN)))
                k == 1 && (tel1 = copy(w.env[:telemetry]::Dict{String,Any}))
                k == n && (telN = copy(w.env[:telemetry]::Dict{String,Any}))
            end
            return (; tr, haz, tel1, telN)
        end
        # ⚠ `τ = Inf` is an IN-TEST reductio only — the loader refuses a non-finite τ (a NaN
        # propagates into the head state and thence into the bend), so it is reachable here and from
        # no YAML. `rate ≤ 0` is the reachable face of the same state, which is the point.
        stuck = frozen(tau = Inf)
        for rt in (-1.0, 0.0)
            a = frozen(rate = rt)
            @test maximum(hypot((p - q)...) for (p, q) in zip(a.tr, stuck.tr)) == 0.0
            @test maximum(abs.(a.haz .- stuck.haz)) == 0.0
            @test maximum(a.haz) - minimum(a.haz) == 0.0        # the head really is FROZEN
            # …and WHAT THE THREE KEYS READ THERE, so gate 3's HUD is not left inferring it: the cap
            # ships its AUTHORED value (a NEGATIVE one means FROZEN, never FAST — `_finite` clamps
            # only the upper bound, which is correct here and stated so it is not read as the
            # slice-29 `_finite_coord` catch), the flag is LIT on every tick past the handover, and
            # the DEMAND keeps climbing because the LOS keeps moving while the head does not.
            @test a.telN["m1.gimbal_rate_dps"] == rt
            @test a.telN["m1.head_rate_sat"]   == 1.0
            @test a.tel1["m1.head_rate_sat"]   == 0.0            # …except the handover tick
            @test a.telN["m1.head_rate_dps"]   > 100.0           # a demand nothing is answering
        end
        # ⚠ AND THE TICK-2 HANDOVER TRANSIENT IS IDENTICAL ON EVERY ARM — §0.2's "the peak is an
        # artefact and must never be quoted", pinned as the POSITIVE fact behind it (slice 25's
        # "exclude the init ticks" rule in a new quantity). This is also exactly why the domain
        # CEILING is not a bit-identity control: at 60 °/s the cap clips THIS, on every arm alike.
        let peak = [frozen(n = 2, Rhat = Rh).telN["m1.head_rate_dps"]
                    for Rh in (-0.33, -0.18, -0.16, -0.03)]
            @test all(p -> p === peak[1], peak)
            @test peak[1] ≈ 72.542 atol = 0.001
            @test peak[1] > 60.0                                 # …and a 60 °/s servo clips it
        end
    end

    @testset "⭐⭐ THE DEMAND STEPS ACROSS SLICE 34's OWN ONSET BRACKET — 0.600 → 32.155 °/s" begin
        # §0.2's headline, off the SHIPPED key rather than gate 0's finite difference. The quiet
        # ladder sits under 2.5 °/s and the first ringing arm asks for 32 — so a limit anywhere in
        # ~8–40 °/s is inert quiet and binding ringing BY CONSTRUCTION, which is a knob domain that
        # writes itself.
        d = Dict(Rh => rarm(Rhat = Rh).dem_p95 for Rh in (-0.33, -0.24, -0.18, -0.16, -0.03))
        @test d[-0.33] ≈  2.468 atol = 0.01
        @test d[-0.24] ≈  1.663 atol = 0.01
        @test d[-0.18] ≈  0.600 atol = 0.01
        @test d[-0.16] ≈ 32.155 atol = 0.05
        @test d[-0.03] ≈ 60.831 atol = 0.05
        @test d[-0.16] > 50 * d[-0.18]                                # THE STEP: 53.6×
        @test maximum(d[Rh] for Rh in (-0.33, -0.24, -0.18)) < 2.5    # the whole QUIET ladder
    end

    @testset "⭐⭐ THE FIRST TWO-SIDED KNOB — the ring falls while the requirement grows" begin
        # ⚠ AN INFINITE WINDOW IS A LOAD-BEARING CONDITION AND NOT A CONVENIENCE (§0.5): a
        # rate-limited head LAGS, so slice 34's own 4°/8° detector window BREAKS it, the band
        # EMPTIES and every column here goes NaN. Measured on a windowed arm this whole block would
        # report slice 34's frozen-index artefact instead of the servo.
        free = rarm(Rhat = -0.03)
        slow = rarm(Rhat = -0.03, rate = 8.0)
        @test free.n_band > 0 && slow.n_band > 0
        @test free.rms_r    ≈ 0.88465 atol = 2.0e-5     # the ring, ATTENUATED…
        @test slow.rms_r    ≈ 0.38591 atol = 2.0e-5
        @test free.rms_r / slow.rms_r ≈ 2.29 atol = 0.02
        @test free.off_band ≈  5.916  atol = 0.01       # …and PAID FOR in tracking error
        @test slow.off_band ≈ 12.828  atol = 0.01
        @test slow.off_band / free.off_band ≈ 2.17 atol = 0.02
        # ⇒ ONE KNOB, TWO BOUNDS, PULLING IN OPPOSITE DIRECTIONS. Every cure since slice 32 ends
        # "widen it, it's free"; this one cannot, because bandwidth is what the loop feeds on.
        @test slow.rms_r < free.rms_r && slow.off_band > free.off_band

        # ⭐ AND THE SAME SERVO COSTS ~0 ON THE SHIPPED DESIGN — §0.6's better discriminator, a
        # 0-vs-97 split at ONE rate, from two code paths (the demand is formed unconditionally, the
        # flag is the branch predicate).
        let good = rarm(Rhat = -0.18, rate = 8.0)
            @test good.sat_band == 0.0
            @test slow.sat_band ≈ 97.14 atol = 0.05
            @test good.off_band ≈ 2.022 atol = 0.01     # against the free arm's 1.956 — ~0
        end
        # ⭐ SLICE 30's RULE PAYS A THIRD TIME (33 = FOV, 34 = detector window, 35 = servo
        # bandwidth): at R̂ = `radome_slope_worst` = −0.33 the requirement is FLAT across the whole
        # rate domain, so aiming the compensator at the glass's worst-case slope lets you fly the
        # cheapest servo in the catalogue.
        for rt in (nothing, 25.0, 15.0, 10.0, 8.0)
            @test rarm(Rhat = -0.33, rate = rt).off_band ≈ 1.60 atol = 0.02
        end
    end

    @testset "⚠⚠ THE QUIET END IS THE REDUCTIO — 100 % saturation is an open-loop RAMP" begin
        # §0.6's advisor BLOCKING CHECK, and it FIRED. Two different claims produce the falling
        # `rms r` column: (a) the limit ATTENUATED the parasitic feed — the head still closes its own
        # loop, a LOW-PASS, a mechanism; or (b) the servo can no longer follow ANYTHING — an
        # OPEN-LOOP RAMP whose output is `∫ rate_max`, whose bend is therefore nearly constant, and
        # which is quiet for precisely slice 34's FROZEN-HEAD reason. THE DISCRIMINATOR is what
        # fraction of band ticks the limit actually BINDS — and at 2–3 °/s it is ALL of them.
        # ⇒ THE 43× RATIO DOWN THERE IS UNQUOTABLE and this end ships as the REDUCTIO, which is what
        # sets the domain FLOOR. Only the PARTIALLY-saturated region above is a defensible trade.
        for rt in (3.0, 2.0), Rh in (-0.03, -0.18)
            @test rarm(Rhat = Rh, rate = rt).sat_band == 100.0
        end
        # …while the shipped floor is genuinely partial on the loud arm and inert on the quiet one.
        @test 0.0 < rarm(Rhat = -0.03, rate = 8.0).sat_band < 100.0
        @test rarm(Rhat = -0.18, rate = 8.0).sat_band == 0.0
        # ⚠ AND THE STOP CANNOT CONFOUND ANY OF IT: the head's tracking error stays well inside the
        # 30° stop on every arm, so only the RATE limit can hold a step at its cap.
        for rt in (nothing, 8.0, 3.0)
            @test rarm(n = 9000, Rhat = -0.03, rate = rt).off_max < 30.0
        end
    end

    @testset "⭐ THE ISOLATION — the rate limit reaches the trajectory ONLY through the glass" begin
        # Slice 34's "exactly two channels" (the radome INDEX and the detector WINDOW) re-measured
        # for the new knob, as a COLUMN rather than an inference: with no glass to index and no
        # window to gate, a servo bound to 2 °/s — lagging by TWENTY DEGREES — moves the missile not
        # at all. ⚠ NO GLASS **AND NO WINDOW**: leaving the window at 8° measures channel 2.
        base  = rarm(n = 9000, trace = true, R = nothing, Rhat = nothing)
        bmiss = rarm(R = nothing, Rhat = nothing).miss
        # ⚠ THE BASELINE IS PINNED FINITE **BEFORE** THE LOOP, so the `===` below cannot pass
        # vacuously on `Inf === Inf` (an arm that never reaches CPA within `n`).
        @test isfinite(bmiss)
        @test bmiss ≈ 0.19116 atol = 1.0e-5
        for rt in (60.0, 15.0, 8.0, 5.0, 2.0)
            a = rarm(n = 9000, trace = true, R = nothing, Rhat = nothing, rate = rt)
            @test posdiff35(base.trace, a.trace) == 0.0
            @test rarm(R = nothing, Rhat = nothing, rate = rt).miss === bmiss
        end
        # …and the head IS lagging while the trajectory does not move, which is what makes the zero
        # above a measurement and not a dead knob.
        @test rarm(R = nothing, Rhat = nothing, rate = 2.0).off_max > 15.0
        @test rarm(R = nothing, Rhat = nothing).off_max < 3.0
    end

    @testset "⚠⚠ GATE 2's FINDING — a rate limit makes the ACQUISITION TURN the binding requirement" begin
        # The arc's [500, 3000] m band is what makes a tracking-error number attributable to the
        # LOOP: the missile's initial turn onto the collision course happens at r ≈ 6000 m, so the
        # band excludes it BY CONSTRUCTION (§0.4). Under a rate limit that turn becomes the LARGEST
        # tracking error of the whole engagement — and `off_band` cannot see it.
        let a = rarm(Rhat = -0.18, rate = 15.0)
            @test a.off_band ≈ 1.986 atol = 0.01      # the LOOP's requirement — barely moved…
            @test a.off_max  ≈ 5.497 atol = 0.01      # …against the whole-approach maximum, 2.8×
            @test a.r_at_max > 5000.0                 # and it is out at LAUNCH RANGE, not in the band
        end
        # ⚠⚠ AND IT IS THE MISSILE'S TURN, NOT THE LOOP'S — the discriminator is a wire with NO GLASS
        # AT ALL, where `off_band` is a flat 0.031° at every rate while `off_max` runs to twelve
        # degrees. Nothing is ringing; the body is simply rotating faster than the servo can follow.
        for (rt, om) in ((nothing, 2.112), (15.0, 7.223), (8.0, 12.346))
            let a = rarm(R = nothing, Rhat = nothing, rate = rt)
                @test a.off_band ≈ 0.031 atol = 0.005
                @test a.off_max  ≈ om    atol = 0.01
            end
        end
        # ⇒ CONSEQUENCE FOR GATE 3, AND IT SETTLES THE KNOB COUNT: a LIVE detector window would make
        # this wire's break an ACQUISITION break — §0.4's confound promoted to the headline, and
        # slice 34's own lesson re-run as a third mechanism (convention 9). `gimbal_fov_deg` ships
        # AUTHORED AND WIDE, and here is the number it must clear: the worst whole-approach
        # requirement over the R̂ domain at the servo domain's FLOOR.
        @test maximum(rarm(Rhat = Rh, rate = 8.0).off_max
                      for Rh in (-0.36, -0.33, -0.24, -0.18, -0.16, -0.12, -0.03)) ≈ 19.279 atol = 0.02
    end

    @testset "loader: the servo rate is PRESENCE-gated on the head, and refused without one" begin
        mktempdir() do dir
            function write_scn(seekextra; two_angle = true)
                p = joinpath(dir, "r.yaml")
                open(p, "w") do io
                    print(io, "name: r\nseed: 32\ndt_physics: 1.0e-3\n",
                              "fidelity: {airframe: six_dof, autopilot: alpha, guidance: pn,\n",
                              "           seeker: filtered, seeker_axes: az_el}\n",
                              "entities:\n",
                              "  - id: m1\n    kind: missile\n    pos: [0.0, 0.0, 3000.0]\n",
                              "    missile:\n      mass_kg: 140.0\n      speed: 700.0\n",
                              "      elevation_deg: 12.0\n",
                              "      seeker: {two_angle: ", two_angle ? "true" : "false",
                              seekextra, "}\n",
                              "      guidance: {n_pn: 8.0}\n",
                              "      airframe: {inertia_kgm2: 20.0, cma: -1.0, cmd: 3.0,\n",
                              "                 cmq: -150.0, cla: 20.0, cy_beta: 20.0}\n",
                              "  - id: t1\n    kind: target\n    pos: [6000.0, 2000.0, 4200.0]\n",
                              "    vel: [0.0, 200.0, 0.0]\n    target: {rcs_m2: 1.0}\n")
                end
                return p
            end
            mis(p) = first(e for (_, e) in load_scenario(p).world.entities if e.kind === :missile)
            # THE YAML → COMP PATH: DEGREES PER SECOND at the boundary, stored verbatim, and the
            # seam converts ONCE (the `gimbal_stop_deg`/`gimbal_fov_deg` posture).
            let m = mis(write_scn(", gimbal_tau_s: 0.05, gimbal_stop_deg: 30.0, gimbal_rate_dps: 8.0"))
                @test m.comp[:gimbal_rate_dps] == 8.0
            end
            # PRESENCE-GATED: not authored ⇒ not minted, so slices 1–34 are byte-identical by GATING.
            @test !haskey(mis(write_scn(", gimbal_tau_s: 0.05")).comp, :gimbal_rate_dps)
            # A DEAD KNOB IS REFUSED, NOT SILENTLY IGNORED — a rate limit on a STRAPDOWN seeker names
            # a component that is not there (the slice-31/34 posture, third key in the same loop).
            @test_throws ErrorException load_scenario(write_scn(", gimbal_rate_dps: 8.0"))
            @test_throws ErrorException load_scenario(
                write_scn(", gimbal_rate_dps: 8.0"; two_angle = false))
            # non-finite is a LOAD error (validate-at-LOAD for an authored input)…
            @test_throws ErrorException load_scenario(
                write_scn(", gimbal_tau_s: 0.05, gimbal_rate_dps: .nan"))
            @test_throws ErrorException load_scenario(
                write_scn(", gimbal_tau_s: 0.05, gimbal_rate_dps: .inf"))
            # …but NO positivity guard, deliberately: `rate_max ≤ 0` FREEZES the head, which by
            # `off_axis_angle`'s identity is slice 34's `τ = Inf` reductio reached from the other
            # side — a DEFINED degenerate the kernel owns, not a crash path.
            let m = mis(write_scn(", gimbal_tau_s: 0.05, gimbal_rate_dps: -1.0"))
                @test m.comp[:gimbal_rate_dps] == -1.0
            end
            # …and it is knob-registerable (`_parse_knobs` checks the entity + key exist).
            let p = write_scn(", gimbal_tau_s: 0.05, gimbal_stop_deg: 30.0, gimbal_rate_dps: 8.0")
                write(p, read(p, String) *
                      "knobs:\n  - {target: m1, key: gimbal_rate_dps, min: 8.0, max: 60.0, label: R}\n")
                @test Dict(kb.key => kb.target
                           for kb in load_scenario(p).knobs)[:gimbal_rate_dps] === :m1
            end
        end
        # THE PRESENCE GATE FROM THE OTHER SIDE: no shipped wire carries a servo rate, so slices
        # 1–34 are byte-identical by GATING and not by a value that happens to agree.
        let base = joinpath(@__DIR__, "..", "..", "scenarios")
            for f in readdir(base)
                endswith(f, ".yaml") || continue
                for (_, e) in load_scenario(joinpath(base, f)).world.entities
                    @test !haskey(e.comp, :gimbal_rate_dps)
                end
            end
        end
    end
end
