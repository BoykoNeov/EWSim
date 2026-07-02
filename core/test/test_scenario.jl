# test_scenario.jl — the loader + the live-stream wiring (slice-1 step 5).
#
# Four contracts, each against an independent truth:
#   1. the YAML parses into the world/subsystems/knobs the schema (HANDOFF §6) names;
#   2. the live telemetry snr_db/pd equal the closed-form rf.jl/detection.jl values
#      for the geometry of a moving target (the readout is honest);
#   3. the per-look detection fraction lands in the analytic Pd's confidence band on
#      a STATIC geometry (clean Bernoulli) — the analytic-vs-MC pattern at subsystem
#      level — and the detection sequence actually depends on the seed;
#   4. a fresh load reproduces a byte-identical frame trace (the §1 determinism
#      contract through the loader, where hash-ordered Dict iteration could break it).

using JSON3

const _SCEN  = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice1_roc.yaml"))
const _SCEN2 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice2_tworay.yaml"))
const _SCEN3 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice3_cfar.yaml"))
const _SCEN4S = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice4_selfscreen.yaml"))
const _SCEN4O = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice4_standoff.yaml"))
const _SCEN5 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice5_geoloc.yaml"))
const _SCEN6 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice6_deinterleave.yaml"))
const _SCEN7D = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice7_dop.yaml"))
const _SCEN7R = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice7_raim.yaml"))
const _SCEN8 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice8_ballistic.yaml"))
const _SCEN9 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice9_pursuit.yaml"))

# Build the static fixture used by the Bernoulli + seed-dependence checks. λ = 0.03,
# G = 1e3, F = L = 0 (clean hand-numbers) and R = 9 km put SNR ≈ 17 (Pd ≈ 0.47) —
# well off the 0/1 rails, where a wrong threshold / SNR factor shows as a fraction miss.
function _static_world(seed)
    w = World(seed = seed, fidelity = Dict(:propagation => :free_space))
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
            :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9000.0, 0, 0),
        comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0), ConstantVelocity(:tgt1)]
    return w, subs
end

function _static_hits(seed; N = 40_000)
    w, subs = _static_world(seed)
    hits = 0
    for _ in 1:N
        tick!(w, subs, 1.0e-3)
        hits += count(e -> e[:kind] === :detection, w.events)
        empty!(w.events)                       # test owns the event lifecycle (no server loop yet)
    end
    return hits
end

# Serialize a fresh load's frame trace to raw JSON bytes (events stamped + cleared
# each step, mimicking the future server loop).
function _frame_trace(nsteps)
    scn = load_scenario(_SCEN)
    chunks = Vector{Vector{UInt8}}(undef, nsteps)
    for i in 1:nsteps
        tick!(scn.world, scn.subs, scn.dt_physics)
        chunks[i] = Vector{UInt8}(JSON3.write(state_frame(scn.world)))
        empty!(scn.world.events)
    end
    return chunks
end

@testset "scenario" begin

    @testset "loader parses slice1_roc.yaml (HANDOFF §6)" begin
        scn = load_scenario(_SCEN)
        @test scn.name == "slice1_roc"
        @test scn.world.seed == 42
        @test scn.dt_physics ≈ 1.0e-3
        @test scn.emit_every == 16
        @test scn.world.fidelity[:propagation] === :free_space
        @test scn.world.fidelity[:detection]   === :analytic

        r = scn.world.entities[:radar1]
        @test r.kind === :radar
        @test r.pos == Vec3(0, 0, 10)
        @test r.comp[:pt_w] === 1500.0 && r.comp[:gain_db] === 35.0
        @test r.comp[:freq_hz] === 9.4e9 && r.comp[:bandwidth_hz] === 1.0e6
        @test r.comp[:noise_fig_db] === 3.0 && r.comp[:losses_db] === 4.0
        @test r.comp[:pfa] === 1.0e-6 && r.comp[:swerling] === 1

        t = scn.world.entities[:tgt1]
        @test t.kind === :target
        @test t.pos == Vec3(42000, 0, 3000) && t.vel == Vec3(-250, 0, 0)
        @test t.comp[:rcs_m2] === 5.0

        # subsystem vector is sorted by id (radar1 < tgt1) — fixes RNG draw order
        @test length(scn.subs) == 2
        @test scn.subs[1] isa RadarSensor && scn.subs[2] isa ConstantVelocity

        @test length(scn.knobs) == 2
        k1, k2 = scn.knobs
        @test k1.target === :radar1 && k1.key === :pt_w && k1.min == 100 && k1.max == 5000
        @test k2.target === :tgt1 && k2.key === :rcs_m2 && k2.log === true
    end

    @testset "loader parses slice2_tworay.yaml (two_ray showcase)" begin
        # Cheap insurance: a malformed showcase YAML should fail HERE as a clear test, not
        # downstream as a confusing server-launch timeout in the Godot slice-2 verifier.
        scn = load_scenario(_SCEN2)
        @test scn.name == "slice2_tworay"
        @test scn.world.fidelity[:propagation] === :two_ray
        @test haskey(scn.world.entities, :radar1) && haskey(scn.world.entities, :tgt1)
        @test scn.world.entities[:radar1].kind === :radar
        @test scn.world.entities[:tgt1].kind   === :target
        # propagation is a fidelity (toggled by set_fidelity), NOT a comp param — it must
        # never appear as a slider knob, or a drag would write a bogus comp entry.
        @test all(k -> k.key !== :propagation, scn.knobs)
        # the showcase opens with the target BEYOND the 4/3-Earth horizon (the dark start).
        rad = scn.world.entities[:radar1];  tgt = scn.world.entities[:tgt1]
        ground0 = hypot(tgt.pos[1] - rad.pos[1], tgt.pos[2] - rad.pos[2])
        @test ground0 > horizon_range(rad.pos[3], tgt.pos[3])
    end

    @testset "loader parses slice3_cfar.yaml (CFAR showcase)" begin
        # Cheap insurance, like the slice-2 loader test: a malformed showcase YAML should fail
        # HERE as a clear test, not downstream as a confusing server-launch timeout in the
        # Godot slice-3 verifier.
        scn = load_scenario(_SCEN3)
        @test scn.name == "slice3_cfar"
        @test scn.world.fidelity[:cfar] === :ca            # default rung (the toggle reveals the rest)

        r = scn.world.entities[:radar1]
        @test r.kind === :radar
        @test r.comp[:n_cells] == 300
        @test r.comp[:n_train] == 16 && iseven(r.comp[:n_train])
        @test r.comp[:n_guard] == 2
        @test r.comp[:range_start_m] == 0.0

        # the clutter band loads as a passive :clutter entity (no subsystem of its own)
        c = scn.world.entities[:clut1]
        @test c.kind === :clutter
        @test c.comp[:extent_m] == 6000.0 && c.comp[:cnr_db] == 20.0

        @test scn.world.entities[:tgtA].kind === :target
        @test scn.world.entities[:tgtB].kind === :target

        # cfar is a fidelity (toggle button), NOT a slider knob — a drag must never write it.
        # The live sliders are exactly the CFAR window + design Pfa.
        @test all(k -> k.key !== :cfar, scn.knobs)
        @test Set(k.key for k in scn.knobs) == Set([:n_train, :n_guard, :pfa])

        # both targets fall on the profile grid AND within ~N_guard+N_train cells of each other,
        # so the strong interferer leaks into the victim's training window (the masking geometry).
        rp     = EWSim._radar_params(r.comp)
        dr     = EWSim._cfar_dr(rp)
        rstart = Float64(r.comp[:range_start_m]);  ncells = Int(r.comp[:n_cells])
        cellA  = EWSim._range_to_cell(EWSim._range(scn.world.entities[:tgtA].pos, r.pos), rstart, dr, ncells)
        cellB  = EWSim._range_to_cell(EWSim._range(scn.world.entities[:tgtB].pos, r.pos), rstart, dr, ncells)
        @test cellA != 0 && cellB != 0                     # on the grid (not off the range axis)
        @test 0 < abs(cellA - cellB) ≤ r.comp[:n_guard] + r.comp[:n_train]

        # the clutter band's near edge sits in the profile interior, so its CA spike is visible
        # (not buried in the truncated-window cells at the very start of the axis).
        cedge = EWSim._range_to_cell(EWSim._range(c.pos, r.pos), rstart, dr, ncells)
        @test cedge != 0 && cedge > r.comp[:n_guard] + r.comp[:n_train] ÷ 2
    end

    @testset "loader parses slice4_selfscreen.yaml (self-screen / burn-through)" begin
        # Cheap insurance like the slice-2/3 loader tests: a malformed showcase fails HERE as a
        # clear test, not downstream as a confusing server-launch timeout in the Godot verifier.
        scn = load_scenario(_SCEN4S)
        @test scn.name == "slice4_selfscreen"
        @test scn.world.fidelity[:ep] === :none                # default EP rung (cycler reveals rest)
        # propagation is deliberately ABSENT (advisor: one fidelity → the client button is
        # unambiguously the ep cycler; radar.jl defaults propagation to free_space internally).
        @test !haskey(scn.world.fidelity, :propagation)

        r = scn.world.entities[:radar1]
        @test r.kind === :radar
        # the two-level antenna + EP keys must be POPULATED from YAML — they are the radar.jl
        # defaults numerically, so a SILENTLY failed read would still pass every wire test;
        # haskey is the discriminating check (a missing read leaves the key absent), and the
        # beamwidth pins the degrees→radians conversion (authored 3°, stored as deg2rad(3)).
        @test haskey(r.comp, :beamwidth_rad) && r.comp[:beamwidth_rad] ≈ deg2rad(3.0)
        @test haskey(r.comp, :sidelobe_db)   && r.comp[:sidelobe_db]   == 30.0
        @test haskey(r.comp, :agile_bw_hz)   && r.comp[:agile_bw_hz]   == 1.0e7
        @test haskey(r.comp, :cancel_db)     && r.comp[:cancel_db]     == 30.0

        j = scn.world.entities[:jam1]
        @test j.kind === :jammer
        @test j.comp[:pt_w] == 8.0 && j.comp[:gain_db] == 0.0
        @test j.comp[:bandwidth_hz] == 1.0e6                   # SPOT — freq_agility can outrun it
        # self-screening: the jammer is CO-LOCATED with the target (rides the mainlobe).
        t = scn.world.entities[:tgt1]
        @test j.pos == t.pos && j.vel == t.vel

        # the jammer owns a ConstantVelocity mover AND a Jammer subsystem; sorted-id order is
        # jam1 (CV, Jammer) < radar1 (RadarSensor) < tgt1 (CV) → 4 subsystems total.
        @test length(scn.subs) == 4
        @test count(s -> s isa Jammer, scn.subs) == 1
        @test count(s -> s isa RadarSensor, scn.subs) == 1

        # ep is a fidelity (cycler button), never a slider knob; the live sliders are the
        # jammer power + target RCS (the burn-through levers).
        @test all(k -> k.key !== :ep, scn.knobs)
        @test Set((k.target, k.key) for k in scn.knobs) == Set([(:jam1, :pt_w), (:tgt1, :rcs_m2)])

        # the target opens BEYOND its burn-through range (the dark start, masked by the jammer):
        # ground range > R_bt (J/S = 1), where R_bt is the rf.jl closed form for this geometry.
        rp  = EWSim._radar_params(r.comp)
        Rbt = burnthrough_range(rp, t.comp[:rcs_m2], j.comp[:pt_w], j.comp[:gain_db], j.comp[:bandwidth_hz])
        R0  = EWSim._range(t.pos, r.pos)
        @test 1.0e4 ≤ Rbt ≤ 3.0e4                              # R_bt in the tuned 10–30 km window
        @test R0 > Rbt
    end

    @testset "loader parses slice4_standoff.yaml (standoff / sidelobe blanking)" begin
        scn = load_scenario(_SCEN4O)
        @test scn.name == "slice4_standoff"
        @test scn.world.fidelity[:ep] === :none
        @test !haskey(scn.world.fidelity, :propagation)

        r = scn.world.entities[:radar1]
        @test haskey(r.comp, :beamwidth_rad) && r.comp[:beamwidth_rad] ≈ deg2rad(3.0)
        @test haskey(r.comp, :cancel_db) && r.comp[:cancel_db] == 30.0

        j = scn.world.entities[:jam1];  t = scn.world.entities[:tgt1]
        @test j.kind === :jammer
        @test j.vel == zero(Vec3)                              # standoff: holds station (orbits)
        # offset in ALTITUDE (z), not cross-range (y): the elevation view collapses y, so a
        # y-offset would render ON the boresight line and hide the off-axis lesson; z renders
        # as a visibly elevated marker with an identical 3-D boresight angle (advisor catch).
        @test j.pos[2] == 0.0 && j.pos[3] > 0.0
        # the jammer sits firmly in a SIDELOBE: its angle off the radar→target boresight exceeds
        # the half-beamwidth (so the live antenna model applies the sidelobe Gr, not the mainlobe).
        θ = EWSim._boresight_angle(r.pos, t.pos, j.pos)
        @test θ > r.comp[:beamwidth_rad] / 2
        # BARRAGE jammer (B_j ≥ the agile band) → freq_agility is a no-op here (the 2×2 lesson).
        @test j.comp[:bandwidth_hz] ≥ r.comp[:agile_bw_hz]

        @test all(k -> k.key !== :ep, scn.knobs)
        @test Set((k.target, k.key) for k in scn.knobs) == Set([(:jam1, :pt_w)])
    end

    @testset "loader parses slice5_geoloc.yaml (DF / geolocation, plan view)" begin
        # Cheap insurance like the slice-2/3/4 loader tests: a malformed showcase fails HERE as a
        # clear test, not downstream as a confusing server-launch timeout in the Godot verifier.
        scn = load_scenario(_SCEN5)
        @test scn.name == "slice5_geoloc"
        @test scn.world.fidelity[:estimator] === :pseudolinear   # default estimator (cycler reveals :ml)
        # NO radar/jammer/cfar physics — a DF scenario is jamming-free + radar-free (the slice-3
        # one-lesson rule), so the DF path never touches the radar/jammer RNG (slices 1-4 byte-id).
        @test !haskey(scn.world.fidelity, :propagation)
        @test !haskey(scn.world.fidelity, :cfar)
        @test !haskey(scn.world.fidelity, :ep)
        @test !any(e -> e.kind in (:radar, :jammer, :target, :clutter), values(scn.world.entities))

        # one emitter (a CV mover, no rcs — DF works off the bearing, not a radar echo).
        em = scn.world.entities[:emit1]
        @test em.kind === :emitter
        @test !haskey(em.comp, :rcs_m2)
        @test em.vel[1] > 0 && em.vel[2] == 0      # flies +x (down-range) → sweeps good→bad geometry

        # exactly three DF sensors on the x=0 cross-range baseline, σθ stored RAW in DEGREES (the
        # LIVE slider unit — haskey is the discriminating check; a `set_param sigma_theta_deg` must
        # write the same key the consumer reads, so the comp key is :sigma_theta_deg NOT _rad).
        sensors = sort!([id for (id, e) in scn.world.entities if e.kind === :df_sensor])
        @test sensors == [:dfs1, :dfs2, :dfs3]
        for sid in sensors
            s = scn.world.entities[sid]
            @test s.pos[1] == 0.0                  # on the x=0 baseline
            @test haskey(s.comp, :sigma_theta_deg) && s.comp[:sigma_theta_deg] == 2.0
            @test !haskey(s.comp, :sigma_theta_rad)
        end
        # the baseline spreads in cross-range (y) so the bearings cross — sensors at distinct y.
        @test length(unique(scn.world.entities[sid].pos[2] for sid in sensors)) == 3

        # one fusion station carrying a Geolocator (phase-4 decide!) at 1-σ.
        st = scn.world.entities[:stn1]
        @test st.kind === :df_station
        gi = findfirst(s -> s isa Geolocator, scn.subs)
        @test gi !== nothing && scn.subs[gi].nsigma == 1.0
        @test count(s -> s isa DFSensor, scn.subs) == 3

        # the emitter opens in GOOD geometry (abeam the baseline: down-range x < the baseline
        # half-span), so it FLIES into bad geometry — the stretch lesson sweeps over the run.
        baseline_halfspan = maximum(abs(scn.world.entities[sid].pos[2]) for sid in sensors)
        @test em.pos[1] < baseline_halfspan

        # estimator is a fidelity (the cycler button), never a slider; the live sliders are the
        # three sensors' σθ (the ellipse-size lesson) — and they address :sigma_theta_deg.
        @test all(k -> k.key === :sigma_theta_deg, scn.knobs)
        @test Set(k.target for k in scn.knobs) == Set([:dfs1, :dfs2, :dfs3])
    end

    @testset "loader parses slice6_deinterleave.yaml (multi-emitter EW, ESM view)" begin
        # Cheap insurance like the slice-2/3/4/5 loader tests: a malformed showcase fails HERE as a
        # clear test, not downstream as a confusing server-launch timeout in the Godot verifier.
        scn = load_scenario(_SCEN6)
        @test scn.name == "slice6_deinterleave"
        @test scn.world.fidelity[:deinterleaver] === :cdif       # default rung (cycler reveals :sdif)
        # NO radar/jammer/DF physics — a multi-emitter EW scenario is single-domain (the one-lesson
        # rule), so the ESM path never touches the radar/jammer/DF RNG (slices 1-5 stay byte-id).
        @test !haskey(scn.world.fidelity, :propagation)
        @test !haskey(scn.world.fidelity, :cfar)
        @test !haskey(scn.world.fidelity, :ep)
        @test !haskey(scn.world.fidelity, :estimator)
        @test !any(e -> e.kind in (:radar, :jammer, :target, :clutter, :emitter, :df_sensor,
                                   :df_station), values(scn.world.entities))

        # exactly three stable, non-harmonic pulse emitters — the de-risked [1300,1700,2300] µs,
        # stored SI SECONDS (the key PulseEmitter.build_env! reads — the §1 µs→s conversion; haskey
        # on :pri (not a µs key) is the discriminating check that the conversion actually ran).
        emitters = sort!([id for (id, e) in scn.world.entities if e.kind === :pulse_emitter])
        @test emitters == [:pe1, :pe2, :pe3]
        pris_us = [scn.world.entities[id].comp[:pri] / 1.0e-6 for id in emitters]
        @test pris_us ≈ [1300.0, 1700.0, 2300.0] atol = 1e-9    # µs → SI seconds round-trip
        for id in emitters
            e = scn.world.entities[id]
            @test haskey(e.comp, :pri) && !haskey(e.comp, :pri_us)  # stored SI seconds, not raw µs
            @test e.comp[:pri] > 0                                  # a valid emit grid (no infinite loop)
        end

        # the SEARCH-BAND constraint the lesson rides on: max_lag ∈ (2·min_PRI, 2·second_smallest_PRI)
        # so EXACTLY the one phantom (2×1300=2600 µs) is in-band and the next harmonic (2×1700=3400)
        # is out. A scenario that violates this kills the lesson (dead knob or a harmonic forest).
        esm = first(e for (_, e) in scn.world.entities if e.kind === :esm)
        sorted_pris = sort(pris_us)
        max_lag_us = esm.comp[:max_lag] / 1.0e-6
        @test 2 * sorted_pris[1] < max_lag_us < 2 * sorted_pris[2]

        # exactly one ESM platform with the histogram/extraction params stored SI seconds + the two
        # LIVE sliders present (µs unit for jitter). The static params are load-time; jitter/intercept
        # are the interactive levers.
        @test count(e -> e.kind === :esm, values(scn.world.entities)) == 1
        @test esm.comp[:t_dwell] ≈ 80_000.0e-6 atol = 1e-12
        @test esm.comp[:bin_width] ≈ 20.0e-6 atol = 1e-15
        @test esm.comp[:levels] == 15 && esm.comp[:thresh_frac] == 0.4
        @test haskey(esm.comp, :jitter_us) && haskey(esm.comp, :p_intercept)
        @test count(s -> s isa PulseEmitter, scn.subs) == 3
        @test count(s -> s isa ESMReceiver, scn.subs) == 1
        @test count(s -> s isa Deinterleaver, scn.subs) == 1

        # deinterleaver is a fidelity (the cycler button), never a slider; the live sliders address
        # the two MEASUREMENT-QUALITY knobs on the ESM (both on comp keys the consumer reads).
        @test all(k -> k.target === :esm1, scn.knobs)
        @test Set(k.key for k in scn.knobs) == Set([:jitter_us, :p_intercept])
    end

    @testset "loader parses slice7_dop.yaml (GPS DOP / error-budget, sky view)" begin
        # Cheap insurance like the slice-2..6 loader tests: a malformed showcase fails HERE as a
        # clear test, not downstream as a confusing server-launch timeout in the Godot verifier.
        scn = load_scenario(_SCEN7D)
        @test scn.name == "slice7_dop"
        # `raim` present is the GPS-view discriminator (raim ∈ fidelity → the client sky/DOP view).
        # DOP scene default: a realistic error subset (iono+tropo+noise) + raim off (no fault here).
        @test scn.world.fidelity[:raim] === :off
        @test scn.world.fidelity[:iono] === :on
        @test scn.world.fidelity[:tropo] === :on
        @test scn.world.fidelity[:noise] === :on
        @test scn.world.fidelity[:clock] === :off
        @test scn.world.fidelity[:multipath] === :off
        # NO radar/jammer/DF/ESM physics — GPS is single-domain (the one-lesson rule), so the GPS
        # path never touches those RNG streams and slices 1-6 stay byte-identical.
        @test !haskey(scn.world.fidelity, :propagation)
        @test !haskey(scn.world.fidelity, :cfar)
        @test !haskey(scn.world.fidelity, :ep)
        @test !haskey(scn.world.fidelity, :estimator)
        @test !haskey(scn.world.fidelity, :deinterleaver)
        @test !any(e -> e.kind in (:radar, :jammer, :target, :clutter, :emitter, :df_sensor,
                                   :df_station, :pulse_emitter, :esm), values(scn.world.entities))

        # ≥ 4 satellites (the 4×4 x/y/z/clock solve) + exactly one receiver.
        sats = sort!([id for (id, e) in scn.world.entities if e.kind === :gps_satellite])
        @test length(sats) ≥ 4
        @test count(e -> e.kind === :gps_receiver, values(scn.world.entities)) == 1
        # distinct per-SV clock errors (stored SI metres — a common value would be absorbed by the
        # receiver clock; the `clock` toggle corrupts POSITION only because they DIFFER, advisor).
        clkerrs = [scn.world.entities[id].comp[:clock_err_m] for id in sats]
        @test length(unique(clkerrs)) > 1
        # no fault in the DOP scene (all fault_bias_m = 0 — the fault is the slice7_raim lesson).
        @test all(scn.world.entities[id].comp[:fault_bias_m] == 0.0 for id in sats)
        # at least one satellite drifts (the DOP-sweep lesson) — a nonzero velocity.
        @test any(EWSim._norm3(scn.world.entities[id].vel) > 0 for id in sats)

        # receiver config stored SI metres; the clock bias key is METRES (the §1 c·b-metres
        # convention — haskey :clock_bias_m, NOT a seconds/ns key, is the discriminating unit check).
        rx = first(e for (_, e) in scn.world.entities if e.kind === :gps_receiver)
        @test haskey(rx.comp, :clock_bias_m) && rx.comp[:clock_bias_m] == 30.0
        @test rx.comp[:sigma_range_m] == 3.0
        @test haskey(rx.comp, :raim_threshold)
        @test count(s -> s isa GpsSatellite, scn.subs) == length(sats)
        @test count(s -> s isa GpsReceiver, scn.subs) == 1
        @test count(s -> s isa GpsSolver, scn.subs) == 1

        # the error terms are FIDELITY (the button row), never sliders; the DOP scene has NO knobs
        # (its levers are the toggles + the drift). If it grew a knob it must not address an error key.
        @test all(k -> k.key ∉ (:iono, :tropo, :clock, :multipath, :noise, :raim), scn.knobs)
    end

    @testset "loader parses slice7_raim.yaml (GPS RAIM / fault, sky+residual view)" begin
        scn = load_scenario(_SCEN7R)
        @test scn.name == "slice7_raim"
        # raim present (the discriminator) + DEFAULT :detect so the integrity flag is visible on
        # connect (the default fault is above threshold). noise on (a realistic stat); others off.
        @test scn.world.fidelity[:raim] === :detect
        @test scn.world.fidelity[:noise] === :on
        @test !haskey(scn.world.fidelity, :propagation)
        @test !haskey(scn.world.fidelity, :cfar)
        @test !haskey(scn.world.fidelity, :ep)
        @test !haskey(scn.world.fidelity, :estimator)
        @test !haskey(scn.world.fidelity, :deinterleaver)
        @test !any(e -> e.kind in (:radar, :jammer, :target, :clutter, :emitter, :df_sensor,
                                   :df_station, :pulse_emitter, :esm), values(scn.world.entities))

        # RAIM needs OVER-determination: ≥ 5 satellites (n−4 ≥ 1 residual DOF; :exclude drops to
        # n−1 and must stay ≥ 4). This scene ships 6.
        sats = sort!([id for (id, e) in scn.world.entities if e.kind === :gps_satellite])
        @test length(sats) ≥ 5
        @test count(e -> e.kind === :gps_receiver, values(scn.world.entities)) == 1

        # exactly one satellite carries a nonzero fault_bias_m (the spoof), stored SI metres (the
        # haskey/value on :fault_bias_m — NOT a scaled key — is the discriminating unit check; the
        # slice-4/6 "keys equal defaults so the load must actually have run" rule).
        faults = [(id, scn.world.entities[id].comp[:fault_bias_m]) for id in sats]
        faulted = [id for (id, f) in faults if f != 0.0]
        @test length(faulted) == 1
        @test scn.world.entities[faulted[1]].comp[:fault_bias_m] == 100.0

        # the ONE live slider is the fault bias on the spoofed satellite (addresses the comp key the
        # GpsSatellite reads); the raim rung is a fidelity (the cycler button), never a slider.
        @test length(scn.knobs) == 1
        @test scn.knobs[1].target === faulted[1]
        @test scn.knobs[1].key === :fault_bias_m
        @test all(k -> k.key ∉ (:iono, :tropo, :clock, :multipath, :noise, :raim), scn.knobs)
        @test count(s -> s isa GpsSatellite, scn.subs) == length(sats)
        @test count(s -> s isa GpsSolver, scn.subs) == 1
    end

    @testset "loader parses slice8_ballistic.yaml (missile integrator showcase, spatial view)" begin
        # Cheap insurance like the slice-2..7 loader tests: a malformed showcase fails HERE as a clear
        # test, not downstream as a confusing server-launch timeout in the Godot verifier.
        scn = load_scenario(_SCEN8)
        @test scn.name == "slice8_ballistic"
        # `integrator` present is the missile-view discriminator (the client STAYS spatial — no new
        # render mode — and only repurposes the shared fidelity button). Default :rk4 (the clean
        # conserved parabola on connect; the lesson is what the toggle/slider REVEAL).
        @test scn.world.fidelity[:integrator] === :rk4
        # NO other-slice fidelity or entities — single-domain (the one-lesson rule), so slices 1-7 stay
        # byte-identical (the missile path touches no radar/detection/DF/ESM/GPS RNG stream).
        @test !haskey(scn.world.fidelity, :propagation)
        @test !haskey(scn.world.fidelity, :cfar)
        @test !haskey(scn.world.fidelity, :ep)
        @test !haskey(scn.world.fidelity, :estimator)
        @test !haskey(scn.world.fidelity, :deinterleaver)
        @test !haskey(scn.world.fidelity, :raim)
        @test !any(e -> e.kind in (:radar, :jammer, :target, :clutter, :emitter, :df_sensor,
                                   :df_station, :pulse_emitter, :esm, :gps_satellite, :gps_receiver),
                   values(scn.world.entities))

        # exactly one :missile entity
        missiles = [id for (id, e) in scn.world.entities if e.kind === :missile]
        @test length(missiles) == 1
        m = scn.world.entities[missiles[1]]
        # The DOUBLE-INTEGRATION guard (the discriminating check): a force-integrated body gets
        # BallisticMissile (which OWNS pos/vel advancement) and NOT ConstantVelocity — two phase-1
        # movers would advance pos twice.
        msubs = scn.subs
        @test any(s -> s isa BallisticMissile, msubs)
        @test !any(s -> s isa ConstantVelocity, msubs)
        @test count(s -> s isa BallisticMissile, msubs) == 1

        # launch state: speed/elevation authored in m/s + DEGREES → the x-z-plane `vel = speed·
        # [cos,0,sin]` derived at load (deg→rad); the RAW speed/elevation_deg are ALSO stored (a knob
        # could address them). haskey/value is the discriminating check (the slice-4/6/7 rule — the
        # derived vel must actually have run, not silently defaulted).
        @test m.comp[:speed] == 250.0 && m.comp[:elevation_deg] == 45.0
        @test m.comp[:mass_kg] == 10.0
        @test m.comp[:cd_area_m2] == 0.0          # drag OFF default (the clean parabola)
        @test m.comp[:rho] == 1.225
        expected = 250.0 * cosd(45.0)             # = 250·sin(45°) too (45°)
        @test isapprox(m.vel[1], expected; atol = 1e-9)
        @test isapprox(m.vel[3], expected; atol = 1e-9)
        @test m.vel[2] == 0.0                     # x-z plane only (no cross-range)

        # the ONE live slider is the drag coefficient (addresses the comp key BallisticMissile reads
        # every step — the one well-defined-mid-flight lever); the integrator is a fidelity (the
        # cycler button), never a slider; launch geometry is load-time static (not a knob).
        @test length(scn.knobs) == 1
        @test scn.knobs[1].target === missiles[1]
        @test scn.knobs[1].key === :cd_area_m2
        @test all(k -> k.key ∉ (:integrator, :speed, :elevation_deg), scn.knobs)
    end

    @testset "loader parses slice9_pursuit.yaml (guided missile / PID autopilot, spatial view)" begin
        # Cheap insurance (the slice-2..8 pattern): a malformed showcase fails HERE, not downstream.
        scn = load_scenario(_SCEN9)
        @test scn.name == "slice9_pursuit"
        # `autopilot` present is the missile-view discriminator (the client STAYS spatial, repurposing
        # the shared fidelity button to the :ideal↔:pid cycler). Default :ideal → the clean intercept
        # on connect (the lesson is what the toggle/sliders REVEAL).
        @test scn.world.fidelity[:autopilot] === :ideal
        # NO other-slice fidelity, and CRITICALLY no `:integrator` and no reserved `:guidance` (slice 10)
        # — single-lesson (slices 1-8 byte-identical; the guidance path touches no radar/detection RNG).
        for k in (:propagation, :cfar, :ep, :estimator, :deinterleaver, :raim, :integrator, :guidance)
            @test !haskey(scn.world.fidelity, k)
        end
        @test !any(e -> e.kind in (:radar, :jammer, :clutter, :emitter, :df_sensor, :df_station,
                                   :pulse_emitter, :esm, :gps_satellite, :gps_receiver),
                   values(scn.world.entities))

        # exactly one guided :missile + one :target (the pursuit pair)
        missiles = [id for (id, e) in scn.world.entities if e.kind === :missile]
        targets  = [id for (id, e) in scn.world.entities if e.kind === :target]
        @test length(missiles) == 1 && length(targets) == 1
        m = scn.world.entities[missiles[1]]
        # a GUIDED missile gets [BallisticMissile (phase-1 airframe), Autopilot (phase-4 guidance)] and
        # NOT ConstantVelocity — the double-integration guard (the discriminating check).
        @test any(s -> s isa BallisticMissile, scn.subs)
        @test any(s -> s isa Autopilot, scn.subs)
        @test !any(s -> s isa ConstantVelocity && s.id === missiles[1], scn.subs)
        # launch heading: CLIMBING at 10° at 600 m/s in the x-z plane → vel = 600·[cos10°, 0, sin10°]
        # (no cross-range in the LAUNCH vector; the engagement stays planar in x-z so the pursuit is
        # visible in the elevation view). deg→rad pinned; vel[2] == 0 (no y).
        @test m.comp[:speed] == 600.0 && m.comp[:elevation_deg] == 10.0
        @test isapprox(m.vel[1], 600.0 * cosd(10.0); atol = 1e-9)
        @test isapprox(m.vel[3], 600.0 * sind(10.0); atol = 1e-9)
        @test m.vel[2] == 0.0
        # the guidance gains land at the CONSUMED comp keys (the slider→consumed-key discipline). The
        # DEFAULT gains are P-ONLY (ki = kd = 0) so the :ideal→:pid toggle opens a dramatic gap the Ki
        # slider closes; haskey is the discriminating check (a silently-failed read would still default).
        for (k, v) in ((:k_guid, 3.0), (:kp, 2.0), (:ki, 0.0), (:kd, 0.0), (:tau, 0.3), (:a_max, 1500.0))
            @test haskey(m.comp, k) && m.comp[k] == v
        end

        # the live sliders address the gain comp keys (kp/ki/kd/tau/k_guid); the autopilot method is the
        # fidelity BUTTON not a knob, and a_max (the crash-guard) / launch geometry are NOT sliders.
        @test length(scn.knobs) == 5
        @test Set(k.key for k in scn.knobs) == Set((:kp, :ki, :kd, :tau, :k_guid))
        @test all(k -> k.target === missiles[1], scn.knobs)
        @test all(k -> k.key ∉ (:autopilot, :a_max, :speed, :elevation_deg), scn.knobs)
    end

    @testset "n_pulses ≥ 1 loads and is stored; < 1 is rejected (slice 3)" begin
        mk(np) = begin
            f = tempname() * ".yaml"
            write(f, """
            name: np
            entities:
              - id: radar1
                kind: radar
                pos: [0,0,0]
                radar: {pt_w: 1, gain_db: 1, freq_hz: 1.0e9, bandwidth_hz: 1.0e6,
                        noise_fig_db: 0, losses_db: 0, pfa: 1.0e-6, swerling: 1, n_pulses: $np}
            """)
            f
        end
        good = mk(3)
        scn  = load_scenario(good)
        @test scn.world.entities[:radar1].comp[:n_pulses] == 3        # integration depth stored
        rm(good; force = true)

        # an omitted n_pulses defaults to the single-pulse path (and is still stored).
        f1 = mk(1); scn1 = load_scenario(f1)
        @test scn1.world.entities[:radar1].comp[:n_pulses] == 1
        rm(f1; force = true)

        bad = mk(0)
        @test_throws ErrorException load_scenario(bad)               # n_pulses < 1 is invalid
        rm(bad; force = true)
    end

    @testset "fidelity values are validated at LOAD (crash-boundary guard)" begin
        # A bad fidelity VALUE on a tick-dispatched key (LIVE_FIDELITY_MODES) would throw inside
        # the first tick! — at startup an ugly warmup crash, but mid-session (load_scenario) it
        # runs in the session's IO/EOF-only try and silently kills the connection. Reject at LOAD,
        # the bandwidth>0 / n_pulses≥1 discipline. Keys NOT tick-dispatched (detection, unknown)
        # can't crash a tick, so their values pass.
        mk(fid) = begin
            f = tempname() * ".yaml"
            write(f, """
            name: fid
            fidelity: {$fid}
            entities:
              - id: radar1
                kind: radar
                pos: [0,0,0]
                radar: {pt_w: 1, gain_db: 1, freq_hz: 1.0e9, bandwidth_hz: 1.0e6,
                        noise_fig_db: 0, losses_db: 0, pfa: 1.0e-6, swerling: 1}
              - id: tgt1
                kind: target
                pos: [9000,0,0]
                target: {rcs_m2: 1.0}
            """)
            f
        end
        # a bogus rung on a tick-dispatched key is rejected
        b1 = mk("propagation: bogus")
        @test_throws ErrorException load_scenario(b1); rm(b1; force = true)
        b2 = mk("cfar: bogus")
        @test_throws ErrorException load_scenario(b2); rm(b2; force = true)
        # a valid rung loads
        g1 = mk("propagation: two_ray")
        scn = load_scenario(g1)
        @test scn.world.fidelity[:propagation] === :two_ray; rm(g1; force = true)
        # `detection` is NOT tick-dispatched (offline ROC batch only) — any value passes, so the
        # three shipping slice-1/2/3 scenarios that declare it still load.
        g2 = mk("propagation: free_space, detection: monte_carlo")
        scn2 = load_scenario(g2)
        @test scn2.world.fidelity[:detection] === :monte_carlo; rm(g2; force = true)
    end

    @testset "loader parses a :cfar scenario with a :clutter band (slice 3)" begin
        f = tempname() * ".yaml"
        write(f, """
        name: cfar_t
        seed: 7
        fidelity:
          cfar: ca
        entities:
          - id: radar1
            kind: radar
            pos: [0, 0, 0]
            radar: {pt_w: 1.0e4, gain_db: 30, freq_hz: 9.4e9, bandwidth_hz: 1.0e6,
                    noise_fig_db: 0, losses_db: 0, pfa: 1.0e-3, swerling: 1, n_pulses: 1,
                    n_cells: 200, range_start_m: 0, n_train: 16, n_guard: 2}
          - id: clut1
            kind: clutter
            pos: [10000, 0, 0]
            clutter: {extent_m: 3000, cnr_db: 18}
          - id: tgt1
            kind: target
            pos: [20000, 0, 0]
            target: {rcs_m2: 1.0}
        """)
        scn = load_scenario(f)
        @test scn.world.fidelity[:cfar] === :ca
        c = scn.world.entities[:clut1]
        @test c.kind === :clutter
        @test c.comp[:extent_m] == 3000.0 && c.comp[:cnr_db] == 18.0
        r = scn.world.entities[:radar1]
        @test r.comp[:n_cells] == 200 && r.comp[:n_train] == 16 && r.comp[:n_guard] == 2
        # clutter contributes NO subsystem (the radar reads it) — subs are radar + target movers
        @test length(scn.subs) == 2
        @test scn.subs[1] isa RadarSensor && scn.subs[2] isa ConstantVelocity
        rm(f; force = true)

        # a :cfar scenario MUST give the radar n_cells (else the handshake range-axis / first
        # observe! would crash inside the session's IO-only try) — caught at LOAD as a clear
        # error, the n_pulses-validation pattern.
        f2 = tempname() * ".yaml"
        write(f2, """
        name: bad_nocells
        fidelity: {cfar: ca}
        entities:
          - id: radar1
            kind: radar
            pos: [0, 0, 0]
            radar: {pt_w: 1, gain_db: 1, freq_hz: 1.0e9, bandwidth_hz: 1.0e6,
                    noise_fig_db: 0, losses_db: 0, pfa: 1.0e-3, swerling: 1}
        """)
        @test_throws ErrorException load_scenario(f2)
        rm(f2; force = true)

        # an odd n_train in an AUTHORED CFAR scenario fails at load (a live drag is clamped
        # instead — that's the consumer-side guard in _observe_cfar!).
        f3 = tempname() * ".yaml"
        write(f3, """
        name: bad_oddtrain
        fidelity: {cfar: ca}
        entities:
          - id: radar1
            kind: radar
            pos: [0, 0, 0]
            radar: {pt_w: 1, gain_db: 1, freq_hz: 1.0e9, bandwidth_hz: 1.0e6,
                    noise_fig_db: 0, losses_db: 0, pfa: 1.0e-3, swerling: 1,
                    n_cells: 64, n_train: 15}
        """)
        @test_throws ErrorException load_scenario(f3)
        rm(f3; force = true)
    end

    @testset "live telemetry equals the closed form (moving target)" begin
        scn = load_scenario(_SCEN)
        for _ in 1:10
            tick!(scn.world, scn.subs, scn.dt_physics)
        end
        tgt = scn.world.entities[:tgt1]
        rad = scn.world.entities[:radar1]
        # target advanced under constant velocity
        @test tgt.pos ≈ Vec3(42000, 0, 3000) + Vec3(-250, 0, 0) * (10 * scn.dt_physics)

        R   = sqrt(sum(abs2, tgt.pos - rad.pos))
        rp  = EWSim._radar_params(rad.comp)
        snr = snr_freespace(rp, tgt.comp[:rcs_m2], R)
        tel = state_frame(scn.world)[:telemetry]
        @test tel["radar1.snr_db"] ≈ lin2db(snr) rtol = 1e-12
        @test tel["radar1.pd"] ≈ pd_analytic(snr, rad.comp[:pfa]; swerling = rad.comp[:swerling])
        @test haskey(tel, "radar1.detected")
    end

    @testset "detection fraction in analytic Pd band (static, Bernoulli)" begin
        w, subs = _static_world(20260620)
        rp  = EWSim._radar_params(w.entities[:radar1].comp)
        snr = snr_freespace(rp, 1.0, 9000.0)
        pd  = pd_analytic(snr, 1.0e-6; swerling = 1)
        @test 0.1 < pd < 0.9                       # only meaningful off the 0/1 rails

        N    = 40_000
        hits = _static_hits(20260620; N = N)
        frac = hits / N
        z = 4.0                                    # 4σ Wilson band — wide vs chance, tight vs a real bug
        center = (frac + z^2 / (2N)) / (1 + z^2 / N)
        half   = z * sqrt(frac * (1 - frac) / N + z^2 / (4N^2)) / (1 + z^2 / N)
        @test center - half ≤ pd ≤ center + half

        # the live readout agrees with the closed form for the same geometry
        # (tick the fixture world once to publish telemetry into env)
        tick!(w, subs, 1.0e-3)
        tel = state_frame(w)[:telemetry]
        @test tel["radar1.pd"] ≈ pd
        @test tel["radar1.snr_db"] ≈ lin2db(snr)
    end

    @testset "detection sequence depends on the seed" begin
        @test _static_hits(1; N = 40_000) != _static_hits(2; N = 40_000)
    end

    @testset "a detection event round-trips on the wire (HANDOFF §5)" begin
        # The Pd≈0.47 fixture detects within a few looks at a fixed seed, so this is
        # deterministic, not flaky. Capture the first detection-bearing frame and push
        # it through the real framing — the one path the event-free frames never cover
        # (schema {kind,by,of,t}, the state_frame :t stamp, Symbol→string, detected==true).
        w, subs = _static_world(20260620)
        frame = nothing
        for _ in 1:200
            tick!(w, subs, 1.0e-3)
            if !isempty(w.events)
                frame = state_frame(w)         # stamps event :t, pulls telemetry from env
                break
            end
            empty!(w.events)
        end
        @test frame !== nothing                # the fixture must actually fire a detection

        io = IOBuffer(); write_frame(io, frame); seekstart(io)
        back = read_frame(io)
        @test String(back.type) == "state"
        @test length(back.events) == 1
        ev = back.events[1]
        @test String(ev.kind) == "detection"
        @test String(ev.by) == "radar1"
        @test String(ev.of) == "tgt1"
        @test ev.t == back.t                   # event carries the frame time (the stamp)
        @test back.telemetry[Symbol("radar1.detected")] == true
        # the event references a real entity by the same string id the client will see
        @test any(e -> String(e.id) == String(ev.of), back.entities)
    end

    @testset "fresh load ⇒ byte-identical frame trace (determinism through loader)" begin
        a = _frame_trace(250)
        b = _frame_trace(250)
        @test length(a) == 250
        @test a == b                               # same file ⇒ identical wire bytes
        @test a[1] != a[250]                       # ...and the trace is non-trivial (target moved)
    end
end
