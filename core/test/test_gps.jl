# test_gps.jl — the GPS subsystems wired through the tick contract (slice-7 gate 2, the
# test_esm.jl / test_geolocation.jl analog). The GPS MATH (pseudorange model, fix, DOP, RAIM)
# is pinned closed-form in test_gnss.jl; THIS file pins the SUBSYSTEM PIPELINE — the §9 reuse
# in the tick loop: `GpsSatellite.build_env!` publishing `env[:gps_sats]` (phase 2), the
# `GpsReceiver.observe!` drawing the pseudorange vector into `env[:pseudoranges]` (phase 3, the
# ONE draw site, in the §1-pinned order), and `GpsSolver.decide!` reproducing
# `raim_solve`/`dop_components` on the realized pseudoranges (phase 4). Slice-7 is
# "slice-2/4/5/6-shaped": deterministic given the drawn pseudoranges, NO draw-topology hazard
# (every fidelity key selects only which term / post-processing enters, never a draw).

const _GPS_R = 20_000_000.0
# A far point source at (az, el) from the origin — the flat-local fictional satellite (named
# approximation), the test_gnss probe layout (6 sats, VDOP>HDOP confirmed).
_gps_sat(az, el; r = _GPS_R) = (a = deg2rad(az); e = deg2rad(el);
    Vec3(r * cos(e) * cos(a), r * cos(e) * sin(a), r * sin(e)))
const _GPS_AZEL = [(0.0, 70.0), (60.0, 35.0), (120.0, 40.0),
                   (180.0, 30.0), (240.0, 45.0), (300.0, 55.0)]
_gn3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

# A GPS world: N satellites (the probed upper-hemisphere spread) + one receiver, assembled in
# SORTED-ID order (the loader's contract, which fixes the RNG draw order). `fid` sets the six
# fidelity keys; `faults`/`clock_errs` are per-satellite-index bias dicts.
function _gps_world(; azel = _GPS_AZEL, rx = Vec3(1000.0, -500.0, 0.0), cb = 30.0,
                    fid = Dict{Symbol,Symbol}(), σ_range = 3.0, σ_mp = 1.0, iono_z = 5.0,
                    tropo_z = 2.4, mask_deg = 0.0, raim_thr = 5.0,
                    faults = Dict{Int,Float64}(), clock_errs = Dict{Int,Float64}(),
                    seed = 7, revisit_s = 0.0)
    w = World(seed = seed, fidelity = fid)
    for (i, (az, el)) in enumerate(azel)
        id = Symbol("sv", i)
        w.entities[id] = Entity(id, :gps_satellite; pos = _gps_sat(az, el),
            comp = Dict{Symbol,Any}(:clock_err_m => get(clock_errs, i, 0.0),
                                    :fault_bias_m => get(faults, i, 0.0)))
    end
    w.entities[:rx1] = Entity(:rx1, :gps_receiver; pos = rx,
        comp = Dict{Symbol,Any}(:sigma_range_m => σ_range, :sigma_mp_m => σ_mp,
            :iono_zenith_m => iono_z, :tropo_zenith_m => tropo_z, :clock_bias_m => cb,
            :elevation_mask_deg => mask_deg, :raim_threshold => raim_thr))
    subs = Subsystem[]
    for id in sort!(collect(keys(w.entities)))
        e = w.entities[id]
        if e.kind === :gps_satellite
            push!(subs, ConstantVelocity(id)); push!(subs, GpsSatellite(id))
        elseif e.kind === :gps_receiver
            push!(subs, ConstantVelocity(id)); push!(subs, GpsReceiver(id; revisit_s = revisit_s))
            push!(subs, GpsSolver(id))
        end
    end
    return w, subs
end

# Tick once → (env[:gps_sats], env[:pseudoranges], telemetry).
function _gps_step(w, subs)
    tick!(w, subs, 1.0e-3)
    return w.env[:gps_sats], w.env[:pseudoranges], w.env[:telemetry]
end

@testset "GPS pipeline (build_env!→observe!→decide!, the §9 reuse in the tick loop)" begin

    @testset "GpsSatellite publishes env[:gps_sats] (phase 2 — record shape + sorted order)" begin
        # The §3 phase-2 producer: each GpsSatellite appends a SatEphemeris record. Pin the SHAPE
        # (id/pos/clock_err/fault_bias), the SI-metre storage, and the sorted-id append order.
        w, subs = _gps_world(clock_errs = Dict(2 => 7.0), faults = Dict(3 => 50.0))
        sats, _, _ = _gps_step(w, subs)
        @test length(sats) == 6
        @test [s.id for s in sats] == [:sv1, :sv2, :sv3, :sv4, :sv5, :sv6]
        @test sats[2].clock_err == 7.0
        @test sats[3].fault_bias == 50.0
        @test sats[1].pos == _gps_sat(0.0, 70.0)
        @test eltype(sats) == EWSim.SatEphemeris
    end

    @testset "GpsReceiver draws env[:pseudoranges] in the EXACT §1 order (the determinism golden)" begin
        # The phase-3 ONE draw site, pinned bit-for-bit. Reconstruct the drawn ρ off a fresh
        # Xoshiro by REPLAYING THE §1 DRAW ORDER MANUALLY (independent of `_draw_pseudoranges` —
        # a genuine check the receiver loop matches the spec, the draw-order bug class). Order:
        # satellites sorted-id (sv1..sv6); per satellite MULTIPATH(randn) THEN NOISE(randn), both
        # unconditional. All five terms ON + a per-SV clock error + a fault so every path fires.
        SEED = 4242; RX = Vec3(1000.0, -500.0, 0.0); CB = 30.0
        σr = 3.0; σmp = 1.5; ioz = 5.0; trz = 2.4
        clk = Dict(2 => 7.0); flt = Dict(3 => 50.0)
        fid = Dict(:iono => :on, :tropo => :on, :clock => :on, :multipath => :on, :noise => :on)
        w, subs = _gps_world(σ_range = σr, σ_mp = σmp, iono_z = ioz, tropo_z = trz,
                             clock_errs = clk, faults = flt, fid = fid, seed = SEED)
        _, prs, _ = _gps_step(w, subs)

        rng = Xoshiro(SEED); exp_rho = Float64[]
        for i in 1:6
            spos = _gps_sat(_GPS_AZEL[i]...)
            _, el = sat_az_el(spos, RX)
            mp_draw = randn(rng)                          # MULTIPATH (unconditional)
            noise_draw = randn(rng)                       # NOISE (unconditional)
            ρ = pseudorange(spos, RX, CB;
                clock_err = get(clk, i, 0.0), fault_bias = get(flt, i, 0.0),
                iono = iono_delay(el, ioz), tropo = tropo_delay(el, trz),
                mp = mp_scale(el) * σmp * mp_draw, noise = σr * noise_draw)
            push!(exp_rho, ρ)
        end
        @test prs.rho == exp_rho
        @test reinterpret(UInt64, prs.rho) == reinterpret(UInt64, exp_rho)   # bit-identity
        @test prs.sat_ids == [:sv1, :sv2, :sv3, :sv4, :sv5, :sv6]
        @test all(prs.visible)                            # no mask → all visible
        @test length(prs.positions) == 6
    end

    @testset "GpsSolver reproduces raim_solve/dop_components on the realized ρ (phase 4)" begin
        # The phase-4 consumer reads env[:pseudoranges] the SAME tick and reproduces the lib
        # exactly (it IS the call). Pin the scalars against raim_solve/dop_components on the
        # realized ρ (noise+multipath on so ρ is a genuine draw, not the clean geometry).
        fid = Dict(:noise => :on, :multipath => :on, :raim => :detect)
        w, subs = _gps_world(fid = fid, seed = 11)
        _, prs, tel = _gps_step(w, subs)
        res = raim_solve(prs.positions, prs.rho, 3.0; mode = :detect, threshold = 5.0)
        gd, pd, hd, vd, td = dop_components(res.Q; singular = res.singular)
        @test tel["rx1.pos_err_m"] ≈ _gn3(res.pos - Vec3(1000.0, -500.0, 0.0)) atol = 1e-9
        @test tel["rx1.fix_x"] ≈ res.pos[1] atol = 1e-9
        @test tel["rx1.clock_bias_ns"] ≈ res.cb / EWSim.C_LIGHT * 1e9 atol = 1e-6
        @test tel["rx1.gdop"] ≈ gd atol = 1e-6
        @test tel["rx1.pdop"] ≈ pd atol = 1e-6
        @test tel["rx1.hdop"] ≈ hd atol = 1e-6
        @test tel["rx1.vdop"] ≈ vd atol = 1e-6
        @test tel["rx1.tdop"] ≈ td atol = 1e-6
        @test tel["rx1.raim_stat"] ≈ res.stat atol = 1e-9
        @test tel["rx1.n_sats_used"] == 6
        @test tel["rx1.vdop"] > tel["rx1.hdop"]           # the probed upper-hemisphere layout
    end

    @testset "the six-key fidelity plumbing: each error toggle enters the budget; raim rungs" begin
        # Each of the five error toggles adds its term's contribution to pos_err_m (the error-
        # budget-as-a-number); the raim rung changes detect/exclude/off. Baseline = all off,
        # noise-free/bias-free → fix on truth. clock_err on sv2 so the :clock toggle bites.
        clk = Dict(2 => 10.0)
        w0, s0 = _gps_world(clock_errs = clk, seed = 5)
        _, _, t0 = _gps_step(w0, s0)
        @test t0["rx1.pos_err_m"] < 1e-3                  # all off → fix == truth

        for key in (:iono, :tropo, :clock)                # deterministic biases (no draw)
            w, s = _gps_world(fid = Dict(key => :on), clock_errs = clk, seed = 5)
            _, _, t = _gps_step(w, s)
            @test t["rx1.pos_err_m"] > t0["rx1.pos_err_m"]
        end
        for key in (:multipath, :noise)                   # stochastic (fixed seed → deterministic)
            w, s = _gps_world(fid = Dict(key => :on), clock_errs = clk, seed = 5)
            _, _, t = _gps_step(w, s)
            @test t["rx1.pos_err_m"] > t0["rx1.pos_err_m"]
        end

        # raim rungs on a faulted constellation (fault on sv3, over-determined n=6, dof 2).
        flt = Dict(3 => 80.0)
        woff, soff = _gps_world(faults = flt, fid = Dict(:raim => :off), seed = 5)
        _, _, toff = _gps_step(woff, soff)
        @test toff["rx1.raim_flag"] == 0 && toff["rx1.n_sats_used"] == 6   # naïve baseline
        wdet, sdet = _gps_world(faults = flt, fid = Dict(:raim => :detect), seed = 5)
        _, _, tdet = _gps_step(wdet, sdet)
        @test tdet["rx1.raim_flag"] == 1                                   # flag raises
        wex, sex = _gps_world(faults = flt, fid = Dict(:raim => :exclude), seed = 5)
        _, _, tex = _gps_step(wex, sex)
        @test tex["rx1.n_sats_used"] == 5 && tex["rx1.fault_sat"] == 3     # drops the fault
        @test tex["rx1.pos_err_m"] < toff["rx1.pos_err_m"]                 # snap-back
    end

    @testset "masked AND excluded: vis_idx≠1:n exercises the index mapping (advisor)" begin
        # The one genuinely subtle correctness spot: with an elevation mask `vis_idx ≠ 1:n_cfg`,
        # the solver must map raim_solve's VISIBLE-SUBSET indices (`res.fault_sat`, `res.used`)
        # back to CONFIGURED indices — `fault_sat = vis_idx[res.fault_sat]` and the `sat_used`
        # scatter. A `sat_used[k] = res.used[k]` (forgetting the map) passes when all sats are
        # visible (identity), so this pins the solver's bookkeeping against an INDEPENDENT
        # raim_solve on the SAME realized ρ. We verify the SOLVER'S MAPPING, not RAIM ID accuracy
        # (the crude largest-residual ID is a named approximation — correct-ID exclusion is pinned
        # on the standard layout in the six-key test). Custom 7-sat layout: sv2 is low (el 25),
        # masked at 30° → 6 visible (dof 2, exclusion fires); a fault drives an exclusion whose
        # VISIBLE-index differs from its CONFIGURED index (the non-identity map).
        azel = [(0.0, 70.0), (60.0, 25.0), (120.0, 40.0), (180.0, 45.0),
                (240.0, 50.0), (300.0, 55.0), (30.0, 65.0)]
        flt = Dict(4 => 100.0)
        w, subs = _gps_world(azel = azel, mask_deg = 30.0, faults = flt,
                             fid = Dict(:raim => :exclude), seed = 5)
        _, prs, tel = _gps_step(w, subs)
        @test !prs.visible[2] && count(prs.visible) == 6                   # sv2 masked (of 7)

        # independent reference: run raim_solve on the visible subset of the realized ρ and map back.
        vis_idx  = [j for j in 1:7 if prs.visible[j]]
        res      = raim_solve(prs.positions[vis_idx], prs.rho[vis_idx], 3.0;
                              mode = :exclude, threshold = 5.0)
        exp_fault = res.fault_sat == 0 ? 0 : vis_idx[res.fault_sat]
        exp_used  = falses(7); for (k, j) in enumerate(vis_idx); exp_used[j] = res.used[k]; end
        @test res.flag                                                     # exclusion actually fired
        @test res.fault_sat != exp_fault                                   # vis-index ≠ config-index
        @test vis_idx != collect(1:7)                                      # mask made vis_idx ≠ 1:n
        @test tel["rx1.fault_sat"]   == exp_fault                          # solver's map == reference
        @test tel["rx1.sat_used"]    == exp_used
        @test tel["rx1.n_sats_used"] == count(exp_used)
    end

    @testset "the GPS telemetry survives the REAL wire (state_frame → JSON round-trip)" begin
        # The scalars + display arrays (sat_az_deg/sat_el_deg/sat_resid_m/sat_used) must serialize
        # through the actual §5 framing (JSON3 throws on Inf/NaN → this also pins the finite
        # contract on the wire). Entities (:gps_satellite/:gps_receiver) go through state_frame.
        w, subs = _gps_world(fid = Dict(:noise => :on, :raim => :detect),
                             faults = Dict(3 => 80.0), seed = 6)
        tick!(w, subs, 1.0e-3)
        frame = state_frame(w)
        io = IOBuffer(); write_frame(io, frame); seekstart(io); back = read_frame(io)
        tel = back.telemetry
        @test back.t == frame[:t]
        for k in ("rx1.pos_err_m", "rx1.gdop", "rx1.pdop", "rx1.hdop", "rx1.vdop", "rx1.tdop",
                  "rx1.raim_stat", "rx1.clock_bias_ns", "rx1.protection_level_m")
            @test isfinite(tel[Symbol(k)])
        end
        @test tel[Symbol("rx1.raim_flag")] == 1
        @test tel[Symbol("rx1.n_sats_used")] == 6
        @test length(tel[Symbol("rx1.sat_az_deg")]) == 6                  # display arrays serialize
        @test length(tel[Symbol("rx1.sat_resid_m")]) == 6
        @test length(tel[Symbol("rx1.sat_used")]) == 6
        kinds = Set(Symbol(e.kind) for e in back.entities)
        @test :gps_satellite in kinds && :gps_receiver in kinds
    end

    @testset "the six keys select post-processing/terms, NOT a draw (RNG lockstep, all six)" begin
        # No draw-topology hazard (the slice-4/5/6 pattern): the receiver draws 2·n_sats
        # UNCONDITIONALLY per look regardless of ANY key (the whole draw is phase-3). So toggling
        # each of the six advances w.rng IDENTICALLY (lockstep) — the sharp introduce-safe proof.
        # A fault present so raim's rung actually changes the flag/n_used (not a dead knob).
        base_fid() = Dict{Symbol,Symbol}()
        flt = Dict(3 => 80.0)
        wb, sb = _gps_world(faults = flt, clock_errs = Dict(2 => 10.0), seed = 99)
        for _ in 1:20; _gps_step(wb, sb); end
        rng_end = rand(copy(wb.rng))
        for (key, val) in ((:iono, :on), (:tropo, :on), (:clock, :on), (:multipath, :on),
                           (:noise, :on), (:raim, :exclude))
            wk, sk = _gps_world(fid = Dict(key => val), faults = flt,
                                clock_errs = Dict(2 => 10.0), seed = 99)
            for _ in 1:20; _gps_step(wk, sk); end
            @test rand(copy(wk.rng)) == rng_end                          # draw count is key-invariant
        end
        # ...and each toggle actually CHANGES the output (not dead): raim :exclude drops n_used.
        we, se = _gps_world(fid = Dict(:raim => :exclude), faults = flt,
                            clock_errs = Dict(2 => 10.0), seed = 99)
        _, _, te = _gps_step(we, se)
        @test te["rx1.n_sats_used"] == 5
    end

    @testset "telemetry FINITE incl. a degenerate all-but-one-masked case (no throw)" begin
        # The "a live config can't crash a tick" watch-item on a new surface: an aggressive mask
        # leaves < 4 visible satellites → the 4×4 normal matrix is rank-deficient → position_fix
        # falls to FINITE_CEIL, DOPs ship the ceiling, no Inf/NaN, NO throw (`_gps_step` ticks).
        w, subs = _gps_world(mask_deg = 65.0, seed = 6)          # only sv1 (el 70) visible
        _, prs, tel = _gps_step(w, subs)
        @test count(prs.visible) == 1
        for k in ("rx1.pos_err_m", "rx1.gdop", "rx1.pdop", "rx1.hdop", "rx1.vdop", "rx1.tdop",
                  "rx1.raim_stat", "rx1.clock_bias_ns")
            @test haskey(tel, k) && isfinite(tel[k])
        end
        @test tel["rx1.gdop"] == FINITE_CEIL                    # singular → ceiling exactly
        @test tel["rx1.n_sats_used"] ≤ 1
        # a normal frame ships every documented scalar + display array.
        _, _, tel2 = _gps_step(_gps_world(seed = 6)...)
        for k in ("rx1.pos_err_m", "rx1.fix_x", "rx1.fix_y", "rx1.fix_z", "rx1.clock_bias_ns",
                  "rx1.gdop", "rx1.pdop", "rx1.hdop", "rx1.vdop", "rx1.tdop", "rx1.raim_stat",
                  "rx1.raim_flag", "rx1.n_sats_used", "rx1.fault_sat", "rx1.protection_level_m",
                  "rx1.sat_az_deg", "rx1.sat_el_deg", "rx1.sat_resid_m", "rx1.sat_used")
            @test haskey(tel2, k)
        end
    end

    @testset "a GPS-free world writes no gps_sats / pseudoranges / GPS telemetry (slices 1-6 untouched)" begin
        # GPS adds NO code to the radar path; a radar-only world never writes env[:gps_sats] /
        # env[:pseudoranges] and ships no GPS telemetry. (The byte-identity goldens + determinism
        # cover the RNG; this pins the wire surface, the test_esm/geolocation pattern.)
        w = World(seed = 1, fidelity = Dict{Symbol,Symbol}(:propagation => :free_space))
        w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
            comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9_000.0, 0, 0),
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
        tick!(w, subs, 1.0e-3)
        @test !haskey(w.env, :gps_sats)
        @test !haskey(w.env, :pseudoranges)
        @test !any(k -> occursin("gdop", k) || occursin("pos_err", k), keys(w.env[:telemetry]))
    end

    # --- loader arms (the programmatic worlds above never hit `_build_entity`) ----------

    @testset "loader builds :gps_satellite / :gps_receiver; rejects bad σ_range / count" begin
        # :gps_satellite — clock_err_m/fault_bias_m SI metres (optional block, all defaults); CV + GpsSatellite.
        se, ss = EWSim._build_entity(:sv1, :gps_satellite,
            Dict("id" => "sv1", "kind" => "gps_satellite", "pos" => [1e6, 2e6, 20e6],
                 "gps_satellite" => Dict("clock_err_m" => 7.0, "fault_bias_m" => 50.0)))
        @test se.kind === :gps_satellite
        @test se.comp[:clock_err_m] == 7.0 && se.comp[:fault_bias_m] == 50.0
        @test length(ss) == 2 && any(s -> s isa GpsSatellite, ss) &&
              any(s -> s isa ConstantVelocity, ss)
        # a satellite with NO block defaults both biases to 0 (introduce-safe authoring).
        se0, _ = EWSim._build_entity(:sv1, :gps_satellite, Dict("id" => "sv1", "kind" => "gps_satellite"))
        @test se0.comp[:clock_err_m] == 0.0 && se0.comp[:fault_bias_m] == 0.0

        # :gps_receiver — static config with gate-1 defaults; CV + GpsReceiver + GpsSolver.
        re, rs = EWSim._build_entity(:rx1, :gps_receiver,
            Dict("id" => "rx1", "kind" => "gps_receiver", "pos" => [0, 0, 0],
                 "gps_receiver" => Dict("sigma_range_m" => 3.0, "clock_bias_m" => 30.0,
                                        "elevation_mask_deg" => 5.0, "raim_threshold" => 5.0)))
        @test re.kind === :gps_receiver
        @test re.comp[:sigma_range_m] == 3.0 && re.comp[:clock_bias_m] == 30.0
        @test re.comp[:elevation_mask_deg] == 5.0 && re.comp[:raim_threshold] == 5.0
        @test re.comp[:sigma_mp_m] == 1.0 && re.comp[:iono_zenith_m] == 5.0   # defaults
        @test length(rs) == 3 && any(s -> s isa GpsReceiver, rs) &&
              any(s -> s isa GpsSolver, rs) && any(s -> s isa ConstantVelocity, rs)
        # σ_range ≤ 0 is a clear LOAD error (the RAIM `/σ` normalization guard).
        @test_throws ErrorException EWSim._build_entity(:rx1, :gps_receiver,
            Dict("id" => "rx1", "kind" => "gps_receiver",
                 "gps_receiver" => Dict("sigma_range_m" => 0.0)))

        # _validate_gps: ≥4 satellites + exactly 1 receiver, triggered by GPS-entity presence.
        function mk_gps_world(; n_sat = 4, n_rx = 1)
            wv = World()
            for i in 1:n_sat
                id = Symbol("sv", i)
                wv.entities[id] = Entity(id, :gps_satellite; pos = _gps_sat(60.0 * i, 40.0),
                    comp = Dict{Symbol,Any}(:clock_err_m => 0.0, :fault_bias_m => 0.0))
            end
            for i in 1:n_rx
                id = Symbol("rx", i)
                wv.entities[id] = Entity(id, :gps_receiver;
                    comp = Dict{Symbol,Any}(:sigma_range_m => 3.0))
            end
            return wv
        end
        @test EWSim._validate_gps(mk_gps_world(n_sat = 6)) isa World          # 6 sats + 1 rx ok
        @test_throws ErrorException EWSim._validate_gps(mk_gps_world(n_sat = 3))  # < 4 sats
        @test_throws ErrorException EWSim._validate_gps(mk_gps_world(n_rx = 2))   # 2 receivers
        @test EWSim._validate_gps(World()) isa World                          # non-GPS world untouched
    end
end
