# test_terrain.jl — the authored Gaussian-hill heightfield + sampled-profile LOS
# occlusion vs closed forms (slice 18 gate 1).
#
# Like geometry (slice 5) these are DETERMINISTIC — every check is an exact closed
# form with an EXPLICIT atol (never rtol-`≈0`; convention 11). The teeth, in order:
# hand-computed HEIGHT literals (a re-typed formula can't self-confirm), a LEVEL-ray
# clearance that is bit-exact, a peak-sampled hill where clearance == z − A EXACTLY
# (blocking monotone + sign-exact across the A = z threshold), bit-exact (p1, p2)
# symmetry, endpoint EXCLUSION (a mast on the ground must not self-block), the
# degenerate zero-length LOS, and the row-major GRID LAYOUT pinned against an
# ASYMMETRIC terrain (the transpose canary — a mirrored client mesh is silent).

@testset "terrain heightfield + LOS occlusion (slice 18 gate 1)" begin

    @testset "heights vs hand-computed literals" begin
        # one hill: A=100 @ (0,0), σ=200, base plane h0=5
        t = TerrainParams(h0 = 5.0, a = [100.0], cx = [0.0], cy = [0.0], sigma = [200.0])
        @test terrain_height(t, 0.0, 0.0) ≈ 105.0 atol = 1e-12          # peak = h0 + A
        # at r = σ the falloff is exactly e^(−1/2) = 0.60653065971263342…
        @test terrain_height(t, 200.0, 0.0) ≈ 5.0 + 60.653065971263342 atol = 1e-9
        @test terrain_height(t, 0.0, -200.0) ≈ 5.0 + 60.653065971263342 atol = 1e-9
        # far field decays to the base plane
        @test terrain_height(t, 1e6, 0.0) ≈ 5.0 atol = 1e-12
        # two-hill superposition: hand-evaluated at x=250, y=0 for
        #   A₁=100 @ (0,0) σ=200      → 100·e^(−250²/(2·200²)) = 100·e^(−0.78125)
        #   A₂=50  @ (500,0) σ=100    → 50·e^(−250²/(2·100²))  = 50·e^(−3.125)
        # e^(−0.78125) = 0.45783335…, e^(−3.125) = 0.04393693…
        t2 = TerrainParams(a = [100.0, 50.0], cx = [0.0, 500.0], cy = [0.0, 0.0],
                           sigma = [200.0, 100.0])
        @test terrain_height(t2, 250.0, 0.0) ≈ 45.783336177161427 + 2.1968465725802851 atol = 1e-6
    end

    @testset "level-ray clearance over the bare plane is bit-exact" begin
        flat = TerrainParams(h0 = 0.0)
        # level ray: every interior sample sees ray_z − h0 = z exactly
        @test terrain_clearance(flat, Vec3(0, 0, 40), Vec3(3000, 0, 40)) == 40.0
        # a raised base plane subtracts exactly
        flat7 = TerrainParams(h0 = 7.0)
        @test terrain_clearance(flat7, Vec3(0, 0, 40), Vec3(0, 3000, 40)) == 33.0
        # tilted ray: min over INTERIOR samples brackets min(z1, z2) within one step's rise
        c = terrain_clearance(flat, Vec3(0, 0, 10), Vec3(1000, 0, 110))
        @test 10.0 < c ≤ 10.0 + 100.0 * (25.0 / 1000.0) + 1e-9    # first sample ≤ one step in
        # a ray dipping BELOW the plane mid-path is negative (buried)
        @test terrain_clearance(flat, Vec3(0, 0, -50), Vec3(1000, 0, -50)) == -50.0
    end

    @testset "peak-sampled hill: clearance == z − A exactly; blocking sign + monotone" begin
        # hill @ x=500 on a 0→1000 ray with step 5: n = 199 interior samples, s = i/200,
        # so sample i=100 lands EXACTLY on the peak → worst clearance == z − (h0 + A).
        mk(A) = TerrainParams(a = [A], cx = [500.0], cy = [0.0], sigma = [100.0],
                              los_step_m = 5.0)
        p1 = Vec3(0, 0, 50); p2 = Vec3(1000, 0, 50)
        @test terrain_clearance(mk(20.0), p1, p2) ≈ 30.0 atol = 1e-9
        @test terrain_clearance(mk(49.0), p1, p2) ≈  1.0 atol = 1e-9
        @test terrain_clearance(mk(51.0), p1, p2) ≈ -1.0 atol = 1e-9
        @test terrain_clearance(mk(90.0), p1, p2) ≈ -40.0 atol = 1e-9
        # the verdict flips exactly across A = z (hard shadow, sign IS the verdict)
        @test terrain_los_clear(mk(49.0), p1, p2)
        @test !terrain_los_clear(mk(51.0), p1, p2)
        # monotone: taller hill ⇒ strictly smaller clearance
        cs = [terrain_clearance(mk(A), p1, p2) for A in (10.0, 30.0, 50.0, 70.0)]
        @test all(diff(cs) .< 0)
    end

    @testset "symmetry is bit-exact: swapping endpoints visits the same samples" begin
        t = TerrainParams(h0 = 2.0, a = [80.0, 40.0], cx = [300.0, 900.0],
                          cy = [-50.0, 120.0], sigma = [150.0, 90.0], los_step_m = 17.0)
        p1 = Vec3(-100, -200, 35); p2 = Vec3(1200, 400, 140)
        @test terrain_clearance(t, p1, p2) == terrain_clearance(t, p2, p1)
        @test terrain_los_clear(t, p1, p2) == terrain_los_clear(t, p2, p1)
    end

    @testset "endpoints are EXCLUDED — a mast on the ground does not self-block" begin
        # radar sitting ON the peak (clearance AT p1 would be 0); the ray is level at
        # the peak height so every INTERIOR sample clears (the hill falls away).
        t = TerrainParams(a = [100.0], cx = [0.0], cy = [0.0], sigma = [100.0])
        @test terrain_los_clear(t, Vec3(0, 0, 100), Vec3(2000, 0, 100))
        @test terrain_clearance(t, Vec3(0, 0, 100), Vec3(2000, 0, 100)) > 0.0
    end

    @testset "degenerate + short-hop LOS never throw (convention 5)" begin
        t = TerrainParams(h0 = 10.0)
        # zero-length: clearance AT the point
        @test terrain_clearance(t, Vec3(5, 5, 25), Vec3(5, 5, 25)) == 15.0
        # a hop shorter than the step still probes once (n clamps to 1 → the midpoint)
        @test terrain_clearance(t, Vec3(0, 0, 12), Vec3(3, 0, 14)) == 3.0
    end

    @testset "grid layout: row-major over y then x, corners on the extents (transpose canary)" begin
        # ASYMMETRIC terrain: the hill hugs (xmax, ymin) — under a transpose the big
        # values would jump to the (xmin, ymax) corner and the pin below fails loudly.
        t = TerrainParams(a = [60.0], cx = [400.0], cy = [-400.0], sigma = [150.0])
        n = 5; xmin, xmax, ymin, ymax = -500.0, 500.0, -500.0, 500.0
        g = terrain_grid(t, xmin, xmax, ymin, ymax, n)
        @test length(g) == n * n
        for iy in 1:n, ix in 1:n
            x = xmin + (ix - 1) * (xmax - xmin) / (n - 1)
            y = ymin + (iy - 1) * (ymax - ymin) / (n - 1)
            @test g[(iy - 1) * n + ix] == terrain_height(t, x, y)
        end
        # corners land exactly on the extent corners
        @test g[1]         == terrain_height(t, xmin, ymin)
        @test g[n]         == terrain_height(t, xmax, ymin)
        @test g[(n - 1) * n + 1] == terrain_height(t, xmin, ymax)
        @test g[n * n]     == terrain_height(t, xmax, ymax)
        # the hill's corner is the hot one — the layout claim as an ORDERING fact
        @test g[n] == maximum(g)                         # (xmax, ymin) is the peak cell
        @test g[(n - 1) * n + 1] == minimum(g)           # (xmin, ymax) is the far corner
    end
end
