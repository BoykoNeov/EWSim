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
