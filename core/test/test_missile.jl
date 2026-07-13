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
