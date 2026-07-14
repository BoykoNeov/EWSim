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

# --- gate 2: the `:terrain` propagation rung + loader + handshake ------------------
#
# The wiring contracts (the test_radar propagation-dispatch discipline, extended):
#   1. an occluded target is masked exactly like below-horizon (visible=false, floored
#      dB, pd ≈ pfa, SIGNED negative clearance on the wire);
#   2. a clear target is bit-exact free-space SNR (the rung adds a mask, not a model)
#      and ships a positive clearance;
#   3. NO terrain entity ⇒ `:terrain` is a bit-exact `==` free-space NO-OP (the
#      mismatched-EP precedent — a live toggle on any prior slice moves no byte);
#   4. the draw stream is rung-independent across all THREE rungs (class 4a: a masked
#      target still costs its draw — detect_once unconditional);
#   5. the clearance key is RUNG-gated (a `:free_space` frame from the SAME world ships
#      no terrain key — the slice-17 lift-keys precedent);
#   6. the masked frame survives the REAL wire (no Inf/NaN — convention 6);
#   7. the YAML loader: hills land as flat `hillK_*` keys, every malformed authored
#      input rejects at LOAD, a second terrain entity rejects (cross-entity check);
#   8. `_terrain_info` ships the gate-1 grid verbatim + ids; absent terrain → nothing;
#      and `alt_hold_m` pins the mover's z (the knob-addressable altitude lever).

# Radar mast at (0,0,30), one hill A @ (5000,0) σ=800 mid-path, target at (10000,0,h_t).
# With los_step 25 a sample lands EXACTLY on the peak (len 10 km ⇒ s-grid hits x=5000),
# so the masked-case clearance is EXACT: ray_z(5000) − (h0 + A).
function _terrain_world(; prop = :terrain, seed = 1, h_t = 100.0, hill_a = 200.0,
                          with_terrain = true, rcs = 1.0)
    w = World(seed = seed, fidelity = Dict(:propagation => prop))
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 30.0),
        comp = Dict{Symbol,Any}(:pt_w => 1.0e4, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
            :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(10_000.0, 0, h_t),
        comp = Dict{Symbol,Any}(:rcs_m2 => rcs))
    if with_terrain
        w.entities[:ter1] = Entity(:ter1, :terrain;
            comp = Dict{Symbol,Any}(:h0 => 0.0, :n_hills => 1, :hill1_a => hill_a,
                :hill1_x => 5000.0, :hill1_y => 0.0, :hill1_s => 800.0,
                :grid_n => 9, :xmin => -1000.0, :xmax => 11_000.0,
                :ymin => -3000.0, :ymax => 3000.0, :los_step_m => 25.0))
    end
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0), ConstantVelocity(:tgt1)]
    return w, subs
end

_tick_tel(w, subs) = (tick!(w, subs, 1.0e-3); state_frame(w)[:telemetry])

@testset "terrain propagation rung (slice 18 gate 2)" begin

    @testset "occluded target is masked (visible=false, floor, negative clearance)" begin
        # LEVEL ray at z=30 (mast height == target height): the worst sample sits EXACTLY
        # on the peak ⇒ clearance = 30 − 200 = −170 exact. (A TILTED ray's minimum of
        # ray_z − gaussian sits slightly OFF-peak — linear ray vs quadratic crest — so the
        # tilted case below is bracketed, not pinned.)
        w, subs = _terrain_world(h_t = 30.0, hill_a = 200.0)
        tel = _tick_tel(w, subs)
        @test tel["radar1.visible"] == false
        @test tel["radar1.snr_db"] == EWSim._SNR_DB_FLOOR
        @test tel["radar1.pd"] ≤ 1.0e-5                       # SNR 0 ⇒ pd ≈ pfa
        @test tel["radar1.terrain_clearance_m"] ≈ -170.0 atol = 1e-9
        # tilted ray (target at 100 m): peak-sample value −135 bounds it from above
        wt, st = _terrain_world(h_t = 100.0, hill_a = 200.0)
        telt = _tick_tel(wt, st)
        @test telt["radar1.visible"] == false
        @test -136.0 < telt["radar1.terrain_clearance_m"] ≤ -135.0
    end

    @testset "clear target is bit-exact free-space SNR + positive clearance" begin
        # target at 2 km altitude: ray z at the peak = 30 + 0.5·1970 = 1015 ≫ 200.
        w, subs = _terrain_world(h_t = 2000.0, hill_a = 200.0)
        rad = w.entities[:radar1]; tgt = w.entities[:tgt1]
        rp = EWSim._radar_params(rad.comp)
        R  = sqrt(sum(abs2, tgt.pos - rad.pos))
        tel = _tick_tel(w, subs)
        @test tel["radar1.visible"] == true
        @test tel["radar1.snr_db"] == lin2db(snr_freespace(rp, 1.0, R))   # bit-exact, not ≈
        @test tel["radar1.terrain_clearance_m"] > 0.0
    end

    @testset "NO terrain entity ⇒ :terrain is a bit-exact free-space no-op" begin
        # The mismatched-EP `==` discipline: a live `set_fidelity propagation terrain` on a
        # terrain-less scenario must move NO byte — same telemetry, same RNG position.
        wt, st = _terrain_world(prop = :terrain,    with_terrain = false, seed = 20260714)
        wf, sf = _terrain_world(prop = :free_space, with_terrain = false, seed = 20260714)
        for _ in 1:20
            tick!(wt, st, 1.0e-3); tick!(wf, sf, 1.0e-3)
        end
        @test state_frame(wt)[:telemetry] == state_frame(wf)[:telemetry]
        @test rand(copy(wt.rng)) == rand(copy(wf.rng))
        @test !haskey(state_frame(wt)[:telemetry], "radar1.terrain_clearance_m")
    end

    @testset "draw stream is rung-independent across all THREE rungs (class 4a)" begin
        # The masked terrain geometry is the strongest case: a shadowed target still costs
        # its draw. All three rungs must leave w.rng at the same stream position.
        w1, s1 = _terrain_world(prop = :free_space, seed = 20260714)
        w2, s2 = _terrain_world(prop = :two_ray,    seed = 20260714)
        w3, s3 = _terrain_world(prop = :terrain,    seed = 20260714)
        for _ in 1:50
            tick!(w1, s1, 1.0e-3); tick!(w2, s2, 1.0e-3); tick!(w3, s3, 1.0e-3)
        end
        r = rand(copy(w1.rng))
        @test r == rand(copy(w2.rng))
        @test r == rand(copy(w3.rng))
    end

    @testset "the clearance key is RUNG-gated (a free_space frame ships no terrain key)" begin
        # SAME world (terrain entity present) — only the rung differs. The slice-17
        # lift-keys precedent: key-presence gates on the RUNG, not on entity presence,
        # so a prior-slice wire can't grow a key from a stray terrain block.
        wf, sf = _terrain_world(prop = :free_space)
        tel = _tick_tel(wf, sf)
        @test !haskey(tel, "radar1.terrain_clearance_m")
        wt, st = _terrain_world(prop = :terrain)
        @test haskey(_tick_tel(wt, st), "radar1.terrain_clearance_m")
    end

    @testset "masked frame survives the REAL wire (no Inf/NaN)" begin
        w, subs = _terrain_world(h_t = 100.0, hill_a = 200.0)
        tick!(w, subs, 1.0e-3)
        frame = state_frame(w)
        io = IOBuffer(); write_frame(io, frame); seekstart(io)
        back = read_frame(io)
        @test isfinite(back.telemetry[Symbol("radar1.snr_db")])
        @test isfinite(back.telemetry[Symbol("radar1.terrain_clearance_m")])
        @test back.telemetry[Symbol("radar1.visible")] == false
    end

    # --- loader + handshake ---------------------------------------------------------

    _yaml_head = """
    name: t18
    seed: 18
    dt_physics: 1.0e-3
    emit_every: 4
    fidelity:
      propagation: terrain
    entities:
      - id: radar1
        kind: radar
        pos: [0, 0, 30]
        radar:
          pt_w: 10000
          gain_db: 30
          freq_hz: 1.0e10
          bandwidth_hz: 1.0e6
          noise_fig_db: 0
          losses_db: 0
          pfa: 1.0e-6
          swerling: 1
      - id: tgt1
        kind: target
        pos: [10000, 0, 100]
        vel: [-200, 0, 0]
        target:
          rcs_m2: 1.0
          alt_hold_m: 100
    """

    _terrain_block(; sigma = 800.0, grid_n = 9, xmax = 11000.0, step = 25.0, akey = "a") = """
      - id: ter1
        kind: terrain
        terrain:
          h0: 0
          grid_n: $(grid_n)
          los_step_m: $(step)
          xmin: -1000
          xmax: $(xmax)
          ymin: -3000
          ymax: 3000
          hills:
            - {$(akey): 200, x: 5000, y: 0, sigma: $(sigma)}
            - {a: 90, x: 8000, y: 500, sigma: 400}
    """

    _load(body) = mktempdir() do dir
        p = joinpath(dir, "t18.yaml")
        write(p, body)
        load_scenario(p)
    end

    @testset "loader: hills land as flat hillK_* keys; malformed inputs reject at LOAD" begin
        scn = _load(_yaml_head * _terrain_block())
        c = scn.world.entities[:ter1].comp
        @test c[:n_hills] == 2
        @test c[:hill1_a] == 200.0 && c[:hill1_x] == 5000.0 && c[:hill1_s] == 800.0
        @test c[:hill2_a] == 90.0  && c[:hill2_y] == 500.0  && c[:hill2_s] == 400.0
        @test scn.world.entities[:tgt1].comp[:alt_hold_m] == 100.0
        # each guard fires as a clear LOAD error (never a tick throw):
        @test_throws ErrorException _load(_yaml_head * _terrain_block(sigma = 0.0))     # σ ≤ 0
        @test_throws ErrorException _load(_yaml_head * _terrain_block(grid_n = 1))      # grid_n < 2
        @test_throws ErrorException _load(_yaml_head * _terrain_block(xmax = -1000.0))  # xmax ≤ xmin
        @test_throws ErrorException _load(_yaml_head * _terrain_block(step = 0.0))      # los_step ≤ 0
        @test_throws ErrorException _load(_yaml_head * _terrain_block(akey = "amp"))    # incomplete hill
        # a SECOND terrain entity rejects (the single-heightfield scope)
        two = _yaml_head * _terrain_block() *
              replace(_terrain_block(), "id: ter1" => "id: ter2")
        @test_throws ErrorException _load(two)
    end

    @testset "handshake: _terrain_info ships the gate-1 grid verbatim + the view ids" begin
        scn = _load(_yaml_head * _terrain_block())
        info = EWSim._terrain_info(scn.world)
        @test info !== nothing
        @test info[:terrain] === :ter1 && info[:radar] === :radar1 && info[:target] === :tgt1
        @test info[:terrain_n] == 9
        @test info[:terrain_extent_m] == [-1000.0, 11_000.0, -3000.0, 3000.0]
        # the grid is EXACTLY the gate-1 sample of the authored heightfield
        t = TerrainParams(a = [200.0, 90.0], cx = [5000.0, 8000.0], cy = [0.0, 500.0],
                          sigma = [800.0, 400.0])
        @test info[:terrain_grid] == terrain_grid(t, -1000.0, 11_000.0, -3000.0, 3000.0, 9)
        # `terrain_grid` presence reaches the CLIENT handshake via scenario_frame (the
        # 3-D-view discriminator), and a terrain-less world ships nothing.
        frame = scenario_frame(EWSim.Server(scn))
        @test haskey(frame, :terrain_grid) && frame[:terrain_n] == 9
        @test EWSim._terrain_info(_terrain_world(with_terrain = false)[1]) === nothing
    end

    @testset "alt_hold_m pins the mover's z live (the altitude lever)" begin
        scn = _load(_yaml_head * _terrain_block())
        w = scn.world
        for _ in 1:100
            tick!(w, scn.subs, 1.0e-3)
        end
        @test w.entities[:tgt1].pos[3] == 100.0                 # held against vel_z drift
        @test w.entities[:tgt1].pos[1] < 10_000.0               # x still integrates
        w.entities[:tgt1].comp[:alt_hold_m] = 900.0             # the live slider write
        tick!(w, scn.subs, 1.0e-3)
        @test w.entities[:tgt1].pos[3] == 900.0
    end
end
