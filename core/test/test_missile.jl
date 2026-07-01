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
