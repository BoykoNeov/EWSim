# test_geolocation.jl — the DF/geolocation subsystems wired through the tick contract
# (slice-5 gate 2, the test_jammer.jl analog). The geometry/estimation MATH is pinned
# closed-form in test_geometry.jl / test_estimation.jl; THIS file pins the SUBSYSTEM
# wiring: `DFSensor.observe!` populating `env[:bearings]` (the producer across the
# observe!→decide! seam), `Geolocator.decide!` reading it back into a fix/ellipse/gdop
# (the FIRST phase-4 contribution), the finite telemetry under a singular geometry, the
# GDOP/ellipse stretch over a closing trace, the σθ-invariance of GDOP, and the
# draw-stream contract (the rung selects post-processing, never a draw). Slice-5 is
# "slice-4-shaped": deterministic given the drawn bearings, no draw-topology hazard.

# A DF world: one emitter, ≥2 sensors on a baseline, one fusion station — assembled with
# the subsystem vector in SORTED-ID order (the loader's contract, which fixes the RNG draw
# + normal-equation sum order). `estimator = nothing` leaves the fidelity map empty (the
# Geolocator then defaults `:pseudolinear`); pass `:pseudolinear`/`:ml` to set the rung.
function _df_world(; emitter_pos = Vec3(40_000.0, 0.0, 0.0), emitter_vel = zero(Vec3),
                     sensor_positions = [Vec3(0.0, -10_000.0, 0.0), Vec3(0.0, 10_000.0, 0.0)],
                     sigma_deg = 1.0, estimator = nothing, nsigma = 1.0, seed = 1)
    fid = Dict{Symbol,Symbol}()
    estimator === nothing || (fid[:estimator] = estimator)
    w = World(seed = seed, fidelity = fid)
    w.entities[:emit1] = Entity(:emit1, :emitter; pos = emitter_pos, vel = emitter_vel)
    for (i, p) in enumerate(sensor_positions)
        sid = Symbol("dfs", i)
        w.entities[sid] = Entity(sid, :df_sensor; pos = p,
            comp = Dict{Symbol,Any}(:sigma_theta_deg => sigma_deg))
    end
    w.entities[:stn1] = Entity(:stn1, :df_station; pos = Vec3(0.0, 0.0, 0.0))
    subs = Subsystem[]
    for id in sort!(collect(keys(w.entities)))
        e = w.entities[id]
        if e.kind === :emitter
            push!(subs, ConstantVelocity(id))
        elseif e.kind === :df_sensor
            push!(subs, ConstantVelocity(id)); push!(subs, DFSensor(id))
        elseif e.kind === :df_station
            push!(subs, ConstantVelocity(id)); push!(subs, Geolocator(id; nsigma = nsigma))
        end
    end
    return w, subs
end

# Tick once and return (env[:bearings], telemetry) — the post-tick env still holds this
# tick's contents (it is cleared at the START of the NEXT tick's phase 2).
function _df_step(w, subs)
    tick!(w, subs, 1.0e-3)
    return w.env[:bearings], w.env[:telemetry]
end

@testset "geolocation subsystems (observe!→decide!, phase 4 lit)" begin

    @testset "DFSensor writes env[:bearings] (the producer; record shape + exact draw)" begin
        # The §3 coupling producer: a DFSensor's observe! appends a BearingRecord. Pin the
        # record SHAPE (theta/pos/sigma), the sorted-id append order, AND the EXACT draw —
        # only the two DFSensors draw (CV/Geolocator don't), in sorted order dfs1 then dfs2,
        # so a fresh Xoshiro(seed) reproduces the noise. Also pins the bearing closed form.
        sp = [Vec3(0.0, -10_000.0, 0.0), Vec3(0.0, 10_000.0, 0.0)]
        w, subs = _df_world(emitter_pos = Vec3(40_000.0, 0.0, 0.0),
                            sensor_positions = sp, sigma_deg = 1.0, seed = 7)
        recs, _ = _df_step(w, subs)
        @test length(recs) == 2
        @test recs[1].pos == sp[1] && recs[2].pos == sp[2]      # sorted-id append order
        @test recs[1].sigma ≈ deg2rad(1.0) && recs[2].sigma ≈ deg2rad(1.0)
        # exact draw reconstruction: dfs1 draws first, dfs2 second, off Xoshiro(7).
        rng = Xoshiro(7); n1 = randn(rng); n2 = randn(rng); σ = deg2rad(1.0)
        θt1 = bearing(sp[1], Vec3(40_000.0, 0.0, 0.0))
        θt2 = bearing(sp[2], Vec3(40_000.0, 0.0, 0.0))
        @test recs[1].theta ≈ wrap_angle(θt1 + σ * n1) rtol = 1e-12
        @test recs[2].theta ≈ wrap_angle(θt2 + σ * n2) rtol = 1e-12
        # ...and the per-sensor bearing_deg telemetry (degrees, NOT radians).
        tel = w.env[:telemetry]
        @test tel["dfs1.bearing_deg"] ≈ rad2deg(recs[1].theta) rtol = 1e-12
    end

    @testset "Geolocator fix matches bearings_fix on the realized bearings (the consumer)" begin
        # The phase-4 consumer reads env[:bearings] the SAME tick and reproduces bearings_fix
        # exactly (it IS the call). Pin both estimator rungs against the realized draw.
        for est in (:pseudolinear, :ml)
            w, subs = _df_world(sigma_deg = 1.0, estimator = est, seed = 11)
            recs, tel = _df_step(w, subs)
            thetas    = [b.theta for b in recs]
            positions = [b.pos   for b in recs]
            sigmas    = [b.sigma for b in recs]
            fix, _ = bearings_fix(thetas, positions, sigmas; estimator = est)
            @test tel["stn1.fix_x"] ≈ fix[1] rtol = 1e-12
            @test tel["stn1.fix_y"] ≈ fix[2] rtol = 1e-12
        end
    end

    @testset "telemetry keys present + FINITE even under a near-collinear geometry" begin
        # The singular-geometry watch-item: two sensors nearly in line with a far emitter →
        # near-parallel LOPs → singular 2×2 → the readouts must clamp finite (no Inf/NaN JSON
        # poison) and the tick must NOT throw. `_df_step` ticks, so a throw fails the test.
        w, subs = _df_world(emitter_pos = Vec3(40_000.0, 0.0, 0.0),
                            sensor_positions = [Vec3(0.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0)],
                            sigma_deg = 1.0, seed = 3)
        _, tel = _df_step(w, subs)
        for k in ("stn1.fix_x", "stn1.fix_y", "stn1.err_m", "stn1.gdop",
                  "stn1.ell_a", "stn1.ell_b", "stn1.ell_deg")
            @test haskey(tel, k) && isfinite(tel[k])
        end
        @test tel["stn1.gdop"]  ≤ FINITE_CEIL
        @test tel["stn1.ell_a"] ≤ FINITE_CEIL
        @test tel["stn1.ell_a"] ≥ tel["stn1.ell_b"]            # a is the MAJOR semi-axis
        # a good geometry is finite AND much tighter — the singular case is the degenerate end.
        wg, sg = _df_world(emitter_pos = Vec3(5_000.0, 0.0, 0.0), sigma_deg = 1.0, seed = 3)
        _, telg = _df_step(wg, sg)
        @test telg["stn1.gdop"] < tel["stn1.gdop"]             # good geometry → far smaller DOP
    end

    @testset "GDOP + ellipse STRETCH as the emitter crosses into bad geometry" begin
        # The slice's lesson, pinned deterministically (GDOP is TRUTH-based → no fix jitter):
        # an emitter abeam the baseline midline crosses near-90° (good, round ellipse); far
        # down-range the LOPs graze (bad, ellipse elongates ALONG the LOS). Both GDOP and the
        # ellipse a/b ratio grow with range.
        function geom(ex; seed = 5)
            w, subs = _df_world(emitter_pos = Vec3(ex, 0.0, 0.0),
                                sensor_positions = [Vec3(0.0, -10_000.0, 0.0),
                                                    Vec3(0.0,  10_000.0, 0.0)],
                                sigma_deg = 1.0, seed = seed)
            _, tel = _df_step(w, subs)
            return tel["stn1.gdop"], tel["stn1.ell_a"] / tel["stn1.ell_b"]
        end
        g_good, r_good = geom(5_000.0)
        g_bad,  r_bad  = geom(200_000.0)
        @test g_bad > g_good                                  # GDOP degrades down-range
        @test r_bad > r_good                                  # ellipse elongates (a/b grows)
    end

    @testset "GDOP is σθ-INVARIANT while the ellipse SCALES with σθ (advisor #2)" begin
        # The σθ-slider lesson at the subsystem level: GDOP is built from emitter TRUTH at unit
        # σ, so scaling σθ (same seed → same randn, scaled noise) leaves it BIT-IDENTICAL, while
        # the error ellipse (cov carries σθ) scales ∝ σθ. This is the wire-level form of the
        # gate-3 `set_param sigma_theta scales ell_a but not gdop` assertion. Use a TINY σ (so the
        # realized bearings ≈ truth and the A/R̂ geometry is σ-independent): then cov = (AᵀWA)⁻¹
        # with W ∝ 1/σ² gives cov ∝ σ², so doubling σ doubles ell_a CLEANLY — a single
        # large-σ realization isn't monotone (the angles, hence the geometry, move with the draw).
        tel(σ; seed = 9) = _df_step(_df_world(sigma_deg = σ, seed = seed)...)[2]
        t1 = tel(0.01); t2 = tel(0.02)
        @test t2["stn1.gdop"] == t1["stn1.gdop"]              # EXACT: GDOP truth-based, σθ-free
        @test t2["stn1.ell_a"] ≈ 2 * t1["stn1.ell_a"] rtol = 1e-2   # ellipse ∝ σθ (the slider)
        @test t2["stn1.ell_b"] ≈ 2 * t1["stn1.ell_b"] rtol = 1e-2
    end

    @testset "the :estimator rung selects post-processing, NOT a draw (RNG lockstep + bias)" begin
        # No draw-topology hazard (the slice-4 pattern, NOT slice-3's :cfar guard): a DFSensor
        # draws exactly one randn/look regardless of rung. So pseudolinear and ml advance w.rng
        # IDENTICALLY (lockstep) while the FIX differs — and on the biased 40 km / ±10 km / 1°
        # geometry (gate-1's bias geometry, ‖bias‖≈1.3 km) the difference is ≫ float noise, so
        # it is a real "not a dead knob" check, not a calibrate-to-pass tautology.
        wp, sp = _df_world(sigma_deg = 1.0, estimator = :pseudolinear, seed = 123)
        wm, sm = _df_world(sigma_deg = 1.0, estimator = :ml,           seed = 123)
        local telp, telm
        for _ in 1:50
            _, telp = _df_step(wp, sp)
            _, telm = _df_step(wm, sm)
        end
        @test rand(copy(wp.rng)) == rand(copy(wm.rng))        # draw count is rung-invariant
        @test telp["stn1.fix_x"] != telm["stn1.fix_x"]        # ...but the fix differs (ml debiases)
        # ml should also be the more ACCURATE rung on this biased geometry — a directional anchor
        # (not self-calibrated): averaged err over the run, ml < pseudolinear. Re-run accumulating.
        wp2, sp2 = _df_world(sigma_deg = 1.0, estimator = :pseudolinear, seed = 123)
        wm2, sm2 = _df_world(sigma_deg = 1.0, estimator = :ml,           seed = 123)
        ep = 0.0; em = 0.0
        for _ in 1:200
            _, tp = _df_step(wp2, sp2); _, tm = _df_step(wm2, sm2)
            ep += tp["stn1.err_m"]; em += tm["stn1.err_m"]
        end
        @test em < ep                                         # ml reduces the mean fix error
    end

    @testset "a DF-free world writes no bearings / DF telemetry (slices 1-4 untouched)" begin
        # Geolocation adds NO code to the radar path; a radar-only world never writes
        # env[:bearings] and ships no station/bearing telemetry. (The byte-identity goldens +
        # test_determinism cover the RNG; this pins the wire surface, the test_jammer pattern.)
        w = World(seed = 1, fidelity = Dict{Symbol,Symbol}(:propagation => :free_space))
        w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
            comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9_000.0, 0, 0),
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
        tick!(w, subs, 1.0e-3)
        @test !haskey(w.env, :bearings)
        @test !any(k -> startswith(k, "stn") || endswith(k, ".bearing_deg"),
                   keys(w.env[:telemetry]))
    end

    # --- loader arms (the programmatic worlds above never hit `_build_entity`) ---------

    @testset "loader builds :emitter / :df_sensor / :df_station; rejects bad σθ + count" begin
        # :emitter ≈ a target with a CV mover, no rcs.
        ee, es = EWSim._build_entity(:emit1, :emitter,
            Dict("id" => "emit1", "kind" => "emitter", "pos" => [40_000, 0, 0],
                 "vel" => [-150, 0, 0]))
        @test ee.kind === :emitter
        @test length(es) == 1 && es[1] isa ConstantVelocity

        # :df_sensor — sigma_theta_deg stored RAW as comp[:sigma_theta_deg] (DEGREES is the live
        # slider unit, gate 3; the consumer DFSensor.observe! converts to rad), CV + DFSensor subs.
        se, ss = EWSim._build_entity(:dfs1, :df_sensor,
            Dict("id" => "dfs1", "kind" => "df_sensor", "pos" => [0, 0, 0],
                 "df_sensor" => Dict("sigma_theta_deg" => 2.0)))
        @test se.kind === :df_sensor
        @test haskey(se.comp, :sigma_theta_deg) && se.comp[:sigma_theta_deg] == 2.0
        @test length(ss) == 2 && any(s -> s isa DFSensor, ss) &&
              any(s -> s isa ConstantVelocity, ss)
        # σθ ≤ 0 and a missing block are clear LOAD errors.
        @test_throws ErrorException EWSim._build_entity(:dfs1, :df_sensor,
            Dict("id" => "dfs1", "kind" => "df_sensor",
                 "df_sensor" => Dict("sigma_theta_deg" => 0.0)))
        @test_throws ErrorException EWSim._build_entity(:dfs1, :df_sensor,
            Dict("id" => "dfs1", "kind" => "df_sensor"))

        # :df_station — optional geolocator: nsigma → Geolocator.nsigma (default 1.0).
        te, ts = EWSim._build_entity(:stn1, :df_station,
            Dict("id" => "stn1", "kind" => "df_station", "pos" => [0, 0, 0],
                 "geolocator" => Dict("nsigma" => 2.0)))
        @test te.kind === :df_station
        gi = findfirst(s -> s isa Geolocator, ts)
        @test gi !== nothing && ts[gi].nsigma == 2.0
        td, _ = EWSim._build_entity(:stn2, :df_station,        # no geolocator block → default
            Dict("id" => "stn2", "kind" => "df_station"))
        @test td.kind === :df_station

        # _validate_geoloc: a DF scenario needs ≥2 sensors + exactly 1 emitter + a station.
        wbad = World()
        wbad.entities[:emit1] = Entity(:emit1, :emitter)
        wbad.entities[:dfs1]  = Entity(:dfs1, :df_sensor;
            comp = Dict{Symbol,Any}(:sigma_theta_deg => 1.0))
        wbad.entities[:stn1]  = Entity(:stn1, :df_station)
        @test_throws ErrorException EWSim._validate_geoloc(wbad)      # only 1 sensor
        wbad.entities[:dfs2] = Entity(:dfs2, :df_sensor;
            comp = Dict{Symbol,Any}(:sigma_theta_deg => 1.0))
        @test EWSim._validate_geoloc(wbad) === wbad                   # now valid (2 sensors)
        # a non-DF world is untouched (the trigger is DF-entity presence).
        @test EWSim._validate_geoloc(World()) isa World
    end
end
