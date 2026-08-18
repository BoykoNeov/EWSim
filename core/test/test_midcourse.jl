# test_midcourse.jl — the MIDCOURSE PHASE's pure primitives (slice 47 gate 1, plan §1.5).
#
# What a BLIND missile flies on. These are `guidance.jl`-class pure functions — no `w.rng`, no
# `World`, no `Entity`, no telemetry (convention 12) — so every check here is an EXPLICIT closed
# form with an EXPLICIT atol and an INDEPENDENT recompute (convention 11). Never `rtol`-`≈ 0`,
# which passes trivially.
#
# THE FIVE THINGS THIS FILE HAS TEETH FOR:
#   1. `intercept_time` against a KNOWN root, constructed backwards from a chosen `t*`.
#   2. The FOUR degenerate branches — finite, defined, non-throwing. ⚠ Four, not three: the
#      co-speed case has a sub-case where the LINEAR term vanishes too.
#   3. The ZERO-ERROR IDENTITY — a missile already on the true collision course commands NOTHING.
#      This is the slice-19 tripwire in its strongest form and it is the null the showcase opens on.
#   4. THE SIGN, in both directions, read on the CROSS-RANGE axis (units/frames/signs are the bug
#      trifecta, HANDOFF §1). A target believed to be crossing FASTER must be led FURTHER.
#   5. NO SECOND KERNEL — `midcourse_accel` IS `clamp_accel ∘ pursuit_accel` (gate-1 probe P8.b
#      measured them bit-identical), and it is NOT a reparameterized PN (P8.a: the two commands
#      differ in direction by exactly the LEAD ANGLE, which is the `c² − 1 = 0` determinant on the
#      wire). Both are asserted here so a future edit cannot quietly fork either claim.

@testset "midcourse / predicted-intercept guidance (slice 47)" begin
    n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)           # test-local (no LinearAlgebra dep, convention 12)
    dot3(a, b) = a[1]*b[1] + a[2]*b[2] + a[3]*b[3]

    @testset "intercept_time == a KNOWN root, constructed backwards" begin
        # Pick the answer FIRST, then build a geometry whose root is exactly it (an INDEPENDENT
        # construction, not a recompute of the same formula): put the target where it must be at
        # t = 0 so that at t = t* it sits exactly V_m·t* away from the missile's position.
        for (t★, V_m) in ((3.0, 700.0), (0.25, 1000.0), (12.5, 340.0), (7.125, 512.5))
            v_t   = Vec3(-31.0, 220.0, -7.5)                  # an arbitrary CV target
            p_m   = Vec3(0.0, 0.0, 0.0)
            # where the target must BE at t★: any point exactly V_m·t★ from the missile
            dir   = Vec3(0.6, -0.64, 0.48)                    # a unit vector (0.36+0.4096+0.2304 = 1)
            @test n3(dir) ≈ 1.0 atol = 1e-15
            meet  = p_m + (V_m * t★) * dir                    # the meeting point
            p_t   = meet - v_t * t★                           # ⇒ the target's position at t = 0
            @test intercept_time(p_t - p_m, v_t, V_m) ≈ t★ atol = 1e-9

            # …and the PIP lands ON the meeting point, with the defining identity ‖pip−p_m‖ = V_m·t_go
            pip, t_go = predicted_intercept_point(p_m, p_t, v_t, V_m)
            @test t_go ≈ t★ atol = 1e-9
            @test n3(pip - meet) ≈ 0.0 atol = 1e-8
            @test n3(pip - p_m) ≈ V_m * t_go atol = 1e-8      # THE identity (docstring's tooth)
        end
    end

    @testset "the SMALLEST positive root is the one returned" begin
        # A head-on closing geometry has TWO positive roots (the missile could meet the target on
        # the way in or, flying past and turning, on the way back). The midcourse wants the FIRST.
        p_rel = Vec3(4000.0, 0.0, 0.0)
        v_rel = Vec3(-300.0, 0.0, 0.0)                        # closing head-on
        V_m   = 700.0
        t = intercept_time(p_rel, v_rel, V_m)
        # independent recompute of BOTH roots from the quadratic
        a = n3(v_rel)^2 - V_m^2; b = 2dot3(p_rel, v_rel); c = n3(p_rel)^2
        s = sqrt(b^2 - 4a*c)
        r1, r2 = (-b - s) / (2a), (-b + s) / (2a)
        pos = sort(filter(>(0.0), [r1, r2]))
        @test length(pos) >= 1
        @test t ≈ minimum(pos) atol = 1e-12
        @test t ≈ 4000.0 / 1000.0 atol = 1e-12                # closing at 700+300 = 1000 m/s
    end

    @testset "the FOUR degenerate branches — finite, defined, non-throwing" begin
        # ⚠ Every one returns 0.0 BY CHOICE, not as a failure code: t_go = 0 ⇒ pip = p_t ⇒ the law
        # degrades to pure pursuit of the BELIEVED PRESENT POSITION. A zero COMMAND would have been
        # the other option and it is precisely slice 47 P0's bug (a blind missile that flies
        # ballistic because a never-initialised estimate reports zero).
        V_m = 700.0

        # 1. the target OUTRUNS the missile — negative discriminant, no real root
        t1 = intercept_time(Vec3(0.0, 5000.0, 0.0), Vec3(2000.0, 0.0, 0.0), V_m)
        @test isfinite(t1) && t1 == 0.0

        # 2. CO-SPEED — |‖v_rel‖² − V_m²| under the relative epsilon ⇒ the quadratic goes LINEAR
        t2 = intercept_time(Vec3(-3000.0, 0.0, 0.0), Vec3(V_m, 0.0, 0.0), V_m)
        @test isfinite(t2) && t2 > 0.0                        # a stern chase at equal speed: linear root
        @test t2 ≈ 3000.0^2 / (2 * 3000.0 * V_m) atol = 1e-9  # = −c/b, recomputed independently

        # 3. CO-SPEED **and** the linear term vanishes too (a pure crossing at equal speed) —
        #    the sub-case that makes this FOUR branches rather than three
        t3 = intercept_time(Vec3(3000.0, 0.0, 0.0), Vec3(0.0, V_m, 0.0), V_m)
        @test isfinite(t3) && t3 == 0.0

        # 4. both roots in the PAST (the target is receding from a point already passed)
        t4 = intercept_time(Vec3(1.0, 0.0, 0.0), Vec3(-2000.0, 0.0, 0.0), 1.0)
        @test isfinite(t4) && t4 >= 0.0

        # …and the truly degenerate inputs cannot produce a NaN either (convention 6: no Inf/NaN
        # to JSON — this value reaches the wire through the PIP and the telemetry).
        for (p, v, V) in ((zero(Vec3), zero(Vec3), 0.0), (zero(Vec3), zero(Vec3), 700.0),
                          (Vec3(1e9, 0.0, 0.0), zero(Vec3), 1e-9))
            t = intercept_time(p, v, V)
            @test isfinite(t) && t >= 0.0
            pip, tg = predicted_intercept_point(zero(Vec3), p, v, V)
            @test all(isfinite, pip) && isfinite(tg)
        end
    end

    @testset "THE ZERO-ERROR IDENTITY — a missile on the true collision course commands NOTHING" begin
        # ⭐ The slice-19 tripwire in its strongest form, and the null the showcase opens on: with
        # Δp = Δv = 0 the PIP is the TRUE intercept point, so a missile already flying at it has
        # zero pointing error and the midcourse's LATERAL command is identically zero.
        p_m = Vec3(0.0, 0.0, 3000.0)
        p_t = Vec3(6000.0, 2000.0, 4200.0)
        v_t = Vec3(0.0, -200.0, 0.0)
        V_m = 700.0
        pip, t_go = predicted_intercept_point(p_m, p_t, v_t, V_m)
        @test t_go > 0.0
        v_m = (V_m / n3(pip - p_m)) * (pip - p_m)             # aim the missile AT the PIP, at speed V_m
        @test n3(v_m) ≈ V_m atol = 1e-9
        a = midcourse_accel(p_m, v_m, pip; k = 1.0, a_max = 3000.0)
        @test n3(a) ≈ 0.0 atol = 1e-9                         # EXPLICIT atol, never ≈ 0

        # …and it is a real null rather than a dead function: nudge the heading off the PIP and the
        # command appears, and it points BACK toward the PIP (the ⟂-to-heading component of û_pip).
        v_off = Vec3(v_m[1], v_m[2] + 20.0, v_m[3])
        a_off = midcourse_accel(p_m, v_off, pip; k = 1.0, a_max = 3000.0)
        @test n3(a_off) > 1.0
        @test dot3(a_off, v_off) ≈ 0.0 atol = 1e-6            # ⟂ the heading: a pure turn, no speed change
        û = (pip - p_m) / n3(pip - p_m)
        @test dot3(a_off, û) > 0.0                            # it turns TOWARD the PIP, not away
    end

    @testset "THE SIGN — a target believed to cross FASTER is led FURTHER (both directions)" begin
        # ⚠ Units / frames / signs are the bug trifecta. The geometry is CONSTRUCTED here rather
        # than inherited from a scenario, and the sign is read on the CROSS-RANGE (+y) axis
        # specifically — the command is ⟂ the heading, so "lateral" is otherwise underdetermined.
        p_m = Vec3(0.0, 0.0, 3000.0)
        p_t = Vec3(6000.0, 0.0, 3000.0)                       # dead ahead, same altitude
        v_m = Vec3(700.0, 0.0, 0.0)                           # flying straight at it
        V_m = 700.0

        # a target believed STATIONARY is dead ahead ⇒ no lead, no command
        pip0, _ = predicted_intercept_point(p_m, p_t, zero(Vec3), V_m)
        @test n3(midcourse_accel(p_m, v_m, pip0; k = 1.0)) ≈ 0.0 atol = 1e-9

        # believed crossing toward +y ⇒ the PIP moves to +y ⇒ the command must push toward +y
        pipP, tP = predicted_intercept_point(p_m, p_t, Vec3(0.0, 150.0, 0.0), V_m)
        aP = midcourse_accel(p_m, v_m, pipP; k = 1.0)
        @test pipP[2] > 0.0 && tP > 0.0
        @test aP[2] > 0.0

        # believed crossing toward −y ⇒ mirrored, and by the SAME magnitude (the geometry is symmetric)
        pipN, tN = predicted_intercept_point(p_m, p_t, Vec3(0.0, -150.0, 0.0), V_m)
        aN = midcourse_accel(p_m, v_m, pipN; k = 1.0)
        @test pipN[2] < 0.0 && tN > 0.0
        @test aN[2] < 0.0
        @test aP[2] ≈ -aN[2] atol = 1e-9
        @test tP ≈ tN atol = 1e-12

        # …and FASTER means FURTHER: monotone in the believed crossing speed, both directions.
        lead(vy) = predicted_intercept_point(p_m, p_t, Vec3(0.0, vy, 0.0), V_m)[1][2]
        cmd(vy)  = midcourse_accel(p_m, v_m, predicted_intercept_point(p_m, p_t, Vec3(0.0, vy, 0.0), V_m)[1]; k = 1.0)[2]
        for vy in (50.0, 100.0, 150.0, 200.0, 250.0)
            @test lead(vy) > lead(vy - 50.0)                  # led further
            @test cmd(vy)  > cmd(vy - 50.0)                   # commanded harder
            @test lead(-vy) < lead(-(vy - 50.0))              # …and mirrored
            @test cmd(-vy)  < cmd(-(vy - 50.0))
        end
    end

    @testset "NO SECOND KERNEL — midcourse_accel IS clamp_accel ∘ pursuit_accel (P8.b)" begin
        # ⭐ The gate-1 reduction probe measured the hand-written `k·V·(û_pip − v̂)⊥` expression
        # BIT-IDENTICAL to the shipped `pursuit_accel` over 2000 random geometries (max difference
        # 0.000e+00). This tooth is what stops a future edit forking a second pursuit kernel — and a
        # second magnitude limiter beside the DESIGNATED crash-guard `clamp_accel`.
        for trial in 1:200
            h(n, s) = 2.0 * ((sin(n * 12.9898 + s) * 43758.5453) % 1.0) - 1.0
            p_m = Vec3(1000h(trial,1.0), 1000h(trial,2.0), 1000h(trial,3.0))
            v_m = Vec3(700h(trial,4.0),  700h(trial,5.0),  700h(trial,6.0))
            pip = Vec3(9000h(trial,7.0), 9000h(trial,8.0), 9000h(trial,9.0))
            n3(v_m) < 1.0 && continue
            for (k, a_max) in ((1.0, 3000.0), (3.0, 50.0), (0.5, 1.0e9))
                @test midcourse_accel(p_m, v_m, pip; k = k, a_max = a_max) ==
                      clamp_accel(pursuit_accel(p_m, v_m, pip; k_guid = k), a_max)   # BIT-identical
            end
            # …and the hand-written §1.1 expression is that same kernel, bit for bit
            v̂ = v_m / n3(v_m)
            û = los_unit(p_m, pip)
            @test (3.0 * n3(v_m)) * (û - dot3(û, v̂) * v̂) == pursuit_accel(p_m, v_m, pip; k_guid = 3.0)
        end
        # the clamp BINDS, and at the shipped ceiling — not merely present
        a = midcourse_accel(Vec3(0.0,0.0,0.0), Vec3(700.0,0.0,0.0), Vec3(1000.0,1000.0,0.0);
                            k = 50.0, a_max = 250.0)
        @test n3(a) ≈ 250.0 atol = 1e-9
    end

    @testset "NOT A REPARAMETERIZED PN — the commands differ by the LEAD ANGLE (P8.a)" begin
        # ⭐ The slice-39 discipline as a test: *a reparameterization must not ship as an
        # ARCHITECTURE*. Writing c = û·v̂, pursuit-of-a-PIP commands along `û − c·v̂` (⟂ the HEADING)
        # while PN against that same point commands along `c·û − v̂` (⟂ the LINE OF SIGHT). Those are
        # parallel iff c² − 1 = 0 — only where the pointing error is zero and both vanish. On the
        # shipped wire the angle between them equalled the LEAD ANGLE to four decimals on every
        # sampled instant; here it is pinned at a constructed geometry.
        p_m = Vec3(0.0, 0.0, 3000.0)
        v_m = Vec3(684.7, 0.0, 145.5)
        pip = Vec3(5000.0, 900.0, 3800.0)
        mid = midcourse_accel(p_m, v_m, pip; k = 3.0, a_max = 1.0e9)
        pnf = pn_accel(p_m, v_m, pip, zero(Vec3); N = 8.0)     # PN against the PIP as a virtual target
        @test n3(mid) > 1.0 && n3(pnf) > 1.0
        v̂ = v_m / n3(v_m)
        û = los_unit(p_m, pip)
        lead = acos(clamp(dot3(û, v̂), -1.0, 1.0))
        between = acos(clamp(dot3(mid, pnf) / (n3(mid) * n3(pnf)), -1.0, 1.0))
        @test between ≈ lead atol = 1e-9                       # THE determinant argument, pinned
        @test lead > 0.01                                      # …at a geometry where it is not vacuous

        # …and the MAGNITUDES scale differently, so no fixed (k, N) can hold across an engagement:
        # pursuit is k·V·sinθ with NO 1/r, PN carries one. Halve the range, and only PN doubles.
        far  = p_m + 2.0 * (pip - p_m)
        m_f = midcourse_accel(p_m, v_m, far; k = 3.0, a_max = 1.0e9)
        p_f = pn_accel(p_m, v_m, far, zero(Vec3); N = 8.0)
        @test !isapprox(n3(mid) / n3(pnf), n3(m_f) / n3(p_f); atol = 1e-3)
    end

    @testset "PINNED against the gate-1 probe's arithmetic (p9_null.jl's `t_int`)" begin
        # ⚠ The `midcourse_k` window P9 measured (k = 1.0 clean over 600–2500 m of correction) is
        # only meaningful if the SHIPPED function is the one the probe flew. This reproduces the
        # probe's kernel verbatim and asserts BIT equality — not `≈` — over a spread of geometries.
        function probe_t_int(p_rel, v_rel, V_m)
            a = n3(v_rel)^2 - V_m^2
            b = 2.0 * dot3(p_rel, v_rel)
            cc = n3(p_rel)^2
            if abs(a) < 1e-9 * max(1.0, V_m^2)
                abs(b) < 1e-12 && return 0.0
                t = -cc / b
                return t > 0.0 ? t : 0.0
            end
            disc = b^2 - 4a * cc
            disc < 0.0 && return 0.0
            s = sqrt(disc)
            t1 = (-b - s) / (2a); t2 = (-b + s) / (2a)
            lo, hi = minmax(t1, t2)
            lo > 0.0 && return lo
            hi > 0.0 && return hi
            return 0.0
        end
        for trial in 1:500
            h(n, s) = 2.0 * ((sin(n * 12.9898 + s) * 43758.5453) % 1.0) - 1.0
            p_rel = Vec3(6000h(trial,1.0), 6000h(trial,2.0), 6000h(trial,3.0))
            v_rel = Vec3(300h(trial,4.0),  300h(trial,5.0),  300h(trial,6.0))
            V_m   = 700.0
            @test intercept_time(p_rel, v_rel, V_m) === probe_t_int(p_rel, v_rel, V_m)
        end
        # …including on the degenerate branches the ordinary geometries never visit
        for (p, v, V) in ((Vec3(0.0,5000.0,0.0), Vec3(2000.0,0.0,0.0), 700.0),
                          (Vec3(-3000.0,0.0,0.0), Vec3(700.0,0.0,0.0), 700.0),
                          (Vec3(3000.0,0.0,0.0), Vec3(0.0,700.0,0.0), 700.0),
                          (zero(Vec3), zero(Vec3), 0.0))
            @test intercept_time(p, v, V) === probe_t_int(p, v, V)
        end
    end
end
