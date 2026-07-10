# test_server.jl — the interactive socket run loop (server.jl; slice-1 step-7 prereq).
#
# server.jl is where the event lifecycle MOVED off the caller: test_scenario used to own
# `empty!(w.events)` between emits, the loop now does it. So the load-bearing test here is
# the emit→clear one — and it must run on a fixture where a detection PROVABLY fires, else
# (on the shipping 42 km scenario, unknown Pd) a "no event" assert passes without testing
# anything. Five contracts, each against an independent truth:
#   1. handle_command! mutates World/mode/seed exactly as the §5 table says;
#   2. set_seed + reset compose into a clean, seeded replay (seed survives reset);
#   3. the run_batch param rename (snr_db_grid_start/stop) maps through (else bounds default);
#   4. warmup! never perturbs the live World or clobbers the real shared/ artifact;
#   5. over a REAL socket: handshake + emit + one-shot event clear + clean EOF teardown.

using EWSim
using JSON3
using Sockets
using Random

const _SCEN_SRV = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice1_roc.yaml"))

# An in-memory scenario with a detection that PROVABLY fires: R = 9 km but pt_w boosted
# 10× over the test_scenario fixture → SNR ≈ 170 → Pd ≈ 1, so every look produces an event.
# `revisit_s` gates the looks, so frames BETWEEN looks are event-free — which is what lets
# the lifecycle test see an event clear (an empty frame after an event frame).
function _detect_scenario(seed; emit_every = 4, revisit_s = 0.02)
    w = World(seed = seed, fidelity = Dict(:propagation => :free_space))
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:pt_w => 1.0e4, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
            :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9000.0, 0, 0),
        comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = revisit_s), ConstantVelocity(:tgt1)]
    knobs = Knob[Knob(:radar1, :pt_w, 1.0e3, 2.0e5, "Pt [W]"; log = true)]
    return Scenario("detect", w, subs, knobs, 1.0e-3, emit_every)
end

# An in-memory CFAR scenario (the slice-3 dispatch): :cfar fidelity present, a radar with the
# profile config (n_cells/n_train/n_guard), one target, one clutter band.
function _cfar_scenario(seed; emit_every = 4, ncells = 128)
    w = World(seed = seed, fidelity = Dict(:cfar => :ca))
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:pt_w => 1.0e4, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6, :noise_fig_db => 0.0,
            :losses_db => 0.0, :pfa => 1.0e-3, :swerling => 1, :n_pulses => 1,
            :n_cells => ncells, :range_start_m => 0.0, :n_train => 16, :n_guard => 2))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(10_000.0, 0, 0),
        comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0), ConstantVelocity(:tgt1)]
    knobs = Knob[Knob(:radar1, :n_train, 4.0, 64.0, "N train"),
                 Knob(:radar1, :n_guard, 0.0, 8.0, "N guard")]
    return Scenario("cfar", w, subs, knobs, 1.0e-3, emit_every)
end

# An in-memory DF/geolocation scenario (the slice-5 dispatch): :estimator fidelity present, one
# emitter + 3 sensors on a y-baseline + a fusion station (the phase-4 Geolocator). Subsystems in
# sorted-id order (the loader's RNG-order contract).
function _geoloc_scenario(seed; emit_every = 4)
    w = World(seed = seed, fidelity = Dict(:estimator => :pseudolinear))
    w.entities[:emit1] = Entity(:emit1, :emitter; pos = Vec3(40_000.0, 0, 0), vel = Vec3(-150.0, 0, 0))
    for (i, y) in enumerate((-15_000.0, 0.0, 15_000.0))
        sid = Symbol("dfs", i)
        w.entities[sid] = Entity(sid, :df_sensor; pos = Vec3(0.0, y, 0),
            comp = Dict{Symbol,Any}(:sigma_theta_deg => 2.0))
    end
    w.entities[:stn1] = Entity(:stn1, :df_station; pos = Vec3(0.0, 0, 0))
    subs = Subsystem[]
    for id in sort!(collect(keys(w.entities)))
        e = w.entities[id]
        e.kind === :emitter    && push!(subs, ConstantVelocity(id))
        e.kind === :df_sensor  && (push!(subs, ConstantVelocity(id)); push!(subs, DFSensor(id)))
        e.kind === :df_station && (push!(subs, ConstantVelocity(id)); push!(subs, Geolocator(id)))
    end
    return Scenario("geoloc", w, subs, Knob[], 1.0e-3, emit_every)
end

# A slice-6 multi-emitter EW scenario fixture (radar-free, ESM-driven): 3 stable pulse emitters +
# one ESM carrying gate-1's proven histogram params. Lights phases 2+3+4; no radar (so warmup!'s
# ROC batch is skipped) and no `:cfar`/`:estimator` — just the `:deinterleaver` fidelity.
function _esm_scenario(seed; emit_every = 4)
    w = World(seed = seed, fidelity = Dict(:deinterleaver => :cdif))
    for (i, (pri, ph)) in enumerate(zip((1300.0, 1700.0, 2300.0), (0.0, 300.0, 700.0)))
        id = Symbol("pe", i)
        w.entities[id] = Entity(id, :pulse_emitter; pos = Vec3(10_000.0 * i, 0, 0),
            comp = Dict{Symbol,Any}(:pri => pri * 1e-6, :phase => ph * 1e-6, :pulse_width => 1e-6))
    end
    w.entities[:esm1] = Entity(:esm1, :esm; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:t_dwell => 80_000.0 * 1e-6, :bin_width => 20.0 * 1e-6,
            :max_lag => 3000.0 * 1e-6, :seq_tol => 30.0 * 1e-6, :assoc_tol => 50.0 * 1e-6,
            :levels => 15, :min_seq => 10, :thresh_frac => 0.4, :n_spurious => 0,
            :jitter_us => 0.0, :p_intercept => 1.0))
    subs = Subsystem[]
    for id in sort!(collect(keys(w.entities)))
        e = w.entities[id]
        if e.kind === :pulse_emitter
            push!(subs, ConstantVelocity(id)); push!(subs, PulseEmitter(id))
        elseif e.kind === :esm
            push!(subs, ConstantVelocity(id)); push!(subs, ESMReceiver(id; revisit_s = 0.05))
            push!(subs, Deinterleaver(id))
        end
    end
    return Scenario("esm", w, subs, Knob[], 1.0e-3, emit_every)
end

# A slice-7 GPS scenario fixture (radar-free, GPS-driven): 6 satellites (the probed upper-
# hemisphere spread) + one receiver/solver. Lights phases 2+3+4; no radar (so warmup!'s ROC
# batch is skipped) and no `:cfar` — the six GPS fidelity keys default off/off.
function _gps_scenario(seed; emit_every = 4, fidelity = Dict{Symbol,Symbol}())
    _gsat(az, el; r = 20_000_000.0) = (a = deg2rad(az); e = deg2rad(el);
        Vec3(r * cos(e) * cos(a), r * cos(e) * sin(a), r * sin(e)))
    azel = [(0.0, 70.0), (60.0, 35.0), (120.0, 40.0), (180.0, 30.0), (240.0, 45.0), (300.0, 55.0)]
    w = World(seed = seed, fidelity = fidelity)
    for (i, (az, el)) in enumerate(azel)
        id = Symbol("sv", i)
        w.entities[id] = Entity(id, :gps_satellite; pos = _gsat(az, el),
            comp = Dict{Symbol,Any}(:clock_err_m => 0.0, :fault_bias_m => 0.0))
    end
    w.entities[:rx1] = Entity(:rx1, :gps_receiver; pos = Vec3(1000.0, -500.0, 0.0),
        comp = Dict{Symbol,Any}(:sigma_range_m => 3.0, :sigma_mp_m => 1.0, :iono_zenith_m => 5.0,
            :tropo_zenith_m => 2.4, :clock_bias_m => 30.0, :elevation_mask_deg => 0.0,
            :raim_threshold => 5.0))
    subs = Subsystem[]
    for id in sort!(collect(keys(w.entities)))
        e = w.entities[id]
        if e.kind === :gps_satellite
            push!(subs, ConstantVelocity(id)); push!(subs, GpsSatellite(id))
        elseif e.kind === :gps_receiver
            push!(subs, ConstantVelocity(id)); push!(subs, GpsReceiver(id; revisit_s = 0.05))
            push!(subs, GpsSolver(id))
        end
    end
    return Scenario("gps", w, subs, Knob[], 1.0e-3, emit_every)
end

# A slice-8 missile scenario fixture (radar-free, missile-driven): one ballistic projectile with
# a BallisticMissile (the first force-based phase-1 integrator). No radar (so warmup!'s ROC batch
# is skipped), no draw stream (deterministic ODE). `:integrator` defaults :rk4.
function _missile_scenario(seed; emit_every = 4, fidelity = Dict(:integrator => :rk4))
    w = World(seed = seed, fidelity = fidelity)
    w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 0.0), vel = Vec3(300.0, 0, 300.0),
        comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225))
    subs = Subsystem[BallisticMissile(:m1)]
    return Scenario("missile", w, subs, Knob[], 1.0e-3, emit_every)
end

# A GUIDED missile scenario (slice 9): an interceptor with [BallisticMissile, Autopilot] pursuing a
# crossing :target, under the :autopilot fidelity, with the PID gains in comp (slider-addressable).
function _guided_scenario(seed; emit_every = 4, fidelity = Dict(:autopilot => :ideal))
    w = World(seed = seed, fidelity = fidelity)
    w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 1000.0), vel = Vec3(600.0, 0, 0),
        comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225,
            :k_guid => 3.0, :kp => 2.0, :ki => 40.0, :kd => 0.1, :tau => 0.3, :a_max => 3000.0))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(8000.0, -3000.0, 1000.0),
        vel = Vec3(0, 300.0, 0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    subs = Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
    knobs = Knob[Knob(:m1, :k_guid, 0.5, 1.0e3, "k guid"), Knob(:m1, :kp, 0.1, 5.0e5, "Kp"),
                 Knob(:m1, :ki, 0.0, 1.0e4, "Ki"), Knob(:m1, :kd, 0.0, 1.0e2, "Kd"),
                 Knob(:m1, :tau, 1.0e-6, 2.0, "tau")]
    return Scenario("guided", w, subs, knobs, 1.0e-3, emit_every)
end

# A slice-10 PN scenario: the guided interceptor under `:guidance` (default :pn) with the slice-10
# comp keys (n_pn/r_stop) and N/a_max/r_stop as live sliders. a_max is deliberately SMALL (300 — the
# glimit shape) so the slider test exercises the DELIBERATELY-BINDING clamp guard (a huge N → a demand
# far above a_max → clamp, never a throw). The hot glimit geometry (gate2_wire).
function _pn_scenario(seed; emit_every = 4, fidelity = Dict(:autopilot => :ideal, :guidance => :pn))
    w = World(seed = seed, fidelity = fidelity)
    w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
        vel = Vec3(800cosd(5), 0, 800sind(5)),
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
            :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0, :kp => 2.0, :ki => 0.0, :kd => 0.0,
            :tau => 0.3, :a_max => 300.0))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(4000.0, 0, 6500.0),
        vel = Vec3(-700.0, 0, -150.0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    subs = Subsystem[BallisticMissile(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
    knobs = Knob[Knob(:m1, :n_pn, 1.0, 1.0e3, "N (nav const)"),
                 Knob(:m1, :a_max, 10.0, 1.0e4, "a_max (g-limit)"),
                 Knob(:m1, :r_stop, 0.0, 200.0, "r_stop (endgame)")]
    return Scenario("pn", w, subs, knobs, 1.0e-3, emit_every)
end

# A slice-11 seeker scenario: the guided interceptor with [BallisticMissile, Seeker, Autopilot] under
# `:seeker` (default :filtered) — the FIRST server scenario that consumes w.rng (the Seeker draws one
# randn/tick), so it carries a seed. σ_seek/α/β are live sliders. The slice-10 crossing (clean filtered
# intercept, catastrophic raw miss).
function _seeker_scenario(seed; emit_every = 4,
                          fidelity = Dict(:autopilot => :ideal, :guidance => :pn, :seeker => :filtered))
    w = World(seed = seed, fidelity = fidelity)
    w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
        vel = Vec3(700cosd(12), 0, 700sind(12)),
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
            :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0, :kp => 2.0, :ki => 0.0, :kd => 0.0,
            :tau => 0.3, :a_max => 3000.0, :sigma_seek => 3.0e-3, :alpha => 0.30, :beta => 0.05))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, 0, 4200.0),
        vel = Vec3(-800.0, 0, 200.0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    subs = Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1), ConstantVelocity(:tgt1)]
    knobs = Knob[Knob(:m1, :sigma_seek, 0.0, 0.05, "σ_seek (LOS noise)"),
                 Knob(:m1, :alpha, 0.01, 0.99, "α (angle gain)"),
                 Knob(:m1, :beta, 1.0e-4, 1.0, "β (rate gain)")]
    return Scenario("seeker", w, subs, knobs, 1.0e-3, emit_every)
end

# A slice-12 APN scenario: the guided interceptor under `:guidance` (default :apn) vs a MANEUVERING
# target ([ManeuveringTarget], a_lat=200 ⟂-v turn) under a BINDING a_max=200 — the g-limited APN
# engagement (wire_probe). RNG-FREE (no seeker → no w.rng draw). a_lat/n_pn/a_max are live sliders (a
# huge a_lat just curves harder — the "a live slider can't crash a tick" guard, now on the target).
function _apn_scenario(seed; emit_every = 4, a_lat = 200.0,
                       fidelity = Dict(:autopilot => :ideal, :guidance => :apn))
    w = World(seed = seed, fidelity = fidelity)
    w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
        vel = Vec3(700cosd(12), 0, 700sind(12)),
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
            :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0, :kp => 2.0, :ki => 0.0, :kd => 0.0,
            :tau => 0.3, :a_max => 200.0))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, 0, 4200.0), vel = Vec3(-800.0, 0, 200.0),
        comp = Dict{Symbol,Any}(:rcs_m2 => 1.0, :a_lat_mps2 => a_lat, :turn_sign => 1.0))
    subs = Subsystem[BallisticMissile(:m1), Autopilot(:m1), ManeuveringTarget(:tgt1)]
    knobs = Knob[Knob(:tgt1, :a_lat_mps2, 0.0, 1.0e3, "a_lat (target g)"),
                 Knob(:m1, :n_pn, 1.0, 1.0e3, "N (nav const)"),
                 Knob(:m1, :a_max, 10.0, 1.0e4, "a_max (g-limit)")]
    return Scenario("apn", w, subs, knobs, 1.0e-3, emit_every)
end

# A slice-13 :scan-seeker countermeasures scenario: the guided interceptor with a :scan seeker (the
# angular-profile CFAR path) + a true target + a born-offset :decoy, under `:discrimination` (default
# :none, so the button reveals the fix). `intensity` + `gate_halfwidth` are LIVE sliders (a huge value
# just paints/widens harder — no crash). The :scan seeker draws 2·N_p·N_bins/tick (the topology flip).
function _scan_scenario(seed; emit_every = 4,
                        fidelity = Dict(:autopilot => :ideal, :guidance => :pn,
                                        :seeker => :scan, :discrimination => :none))
    w = World(seed = seed, fidelity = fidelity)
    w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 3000.0),
        vel = Vec3(700cosd(12), 0, 700sind(12)),
        comp = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
            :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0, :kp => 2.0, :ki => 0.0, :kd => 0.0,
            :tau => 0.3, :a_max => 3000.0, :sigma_seek => 3.0e-3, :alpha => 0.30, :beta => 0.05,
            :scan_n_bins => 64, :scan_bin_width => 0.005, :scan_sigma_beam => 0.015,
            :scan_floor => 1.0, :scan_n_pulses => 10, :scan_cfar_variant => :ca,
            :scan_cfar_ntrain => 16, :scan_cfar_nguard => 4, :scan_cfar_pfa => 1.0e-3,
            :gate_halfwidth => 0.045))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(6000.0, 0, 4200.0),
        vel = Vec3(-800.0, 0, 200.0), comp = Dict{Symbol,Any}(:rcs_m2 => 1.0, :intensity => 40.0))
    w.entities[:dcy1] = Entity(:dcy1, :decoy; pos = Vec3(5868.0, 0, 4735.0),
        vel = Vec3(-800.0, 0, 200.0), comp = Dict{Symbol,Any}(:intensity => 80.0))
    subs = Subsystem[BallisticMissile(:m1), Seeker(:m1), Autopilot(:m1),
                     ConstantVelocity(:tgt1), ConstantVelocity(:dcy1)]
    knobs = Knob[Knob(:dcy1, :intensity, 0.0, 500.0, "decoy intensity"),
                 Knob(:m1, :gate_halfwidth, 0.005, 0.2, "gate hw (rad)")]
    return Scenario("scan", w, subs, knobs, 1.0e-3, emit_every)
end

# A slice-14 cooperative-salvo scenario (geometry F): 2 [BallisticMissile, Autopilot] interceptors
# (near A, far B) at asymmetric ranges + a common ConstantVelocity target + a [SalvoCoordinator]
# :datalink node, under `:cooperation` (default :solo, so the button reveals the fix). RNG-FREE
# (truth-fed PN, no seeker → class 4c). `k_it` (the ITC gain) is a LIVE slider (a huge value just
# curves harder then clamps — no crash). `:cooperation` is live-settable both directions (no guard).
function _salvo_scenario(seed; emit_every = 4,
                         fidelity = Dict(:guidance => :pn, :autopilot => :ideal, :cooperation => :solo))
    w = World(seed = seed, fidelity = fidelity)
    TGT0 = Vec3(9000.0, 0.0, 4500.0); MA0 = Vec3(3000.0, 0.0, 3000.0); MB0 = Vec3(0.0, 0.0, 3000.0)
    gains() = Dict{Symbol,Any}(:mass_kg => 140.0, :cd_area_m2 => 0.0, :rho => 1.225,
        :k_guid => 3.0, :n_pn => 4.0, :r_stop => 30.0, :kp => 2.0, :ki => 0.0, :kd => 0.0,
        :tau => 0.3, :a_max => 3000.0, :k_it => 0.45)
    w.entities[:mA] = Entity(:mA, :missile; pos = MA0, vel = 750.0 * los_unit(MA0, TGT0), comp = gains())
    w.entities[:mB] = Entity(:mB, :missile; pos = MB0, vel = 750.0 * los_unit(MB0, TGT0), comp = gains())
    w.entities[:tgt] = Entity(:tgt, :target; pos = TGT0, vel = Vec3(-500.0, 0.0, 0.0),
        comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
    w.entities[:link] = Entity(:link, :datalink; pos = zero(Vec3), comp = Dict{Symbol,Any}())
    subs = Subsystem[BallisticMissile(:mA), Autopilot(:mA), BallisticMissile(:mB), Autopilot(:mB),
                     ConstantVelocity(:tgt), SalvoCoordinator(:link)]
    knobs = Knob[Knob(:mA, :k_it, 0.01, 2.0, "K_it (ITC gain)"), Knob(:mB, :k_it, 0.01, 2.0, "K_it (ITC gain)")]
    return Scenario("salvo", w, subs, knobs, 1.0e-3, emit_every)
end

@testset "server" begin

    @testset "handle_command! mutates state per the §5 table" begin
        srv = EWSim.Server(_detect_scenario(1))
        w = srv.scn.world

        # set_param is the universal knob channel — writes into the entity's comp bag
        EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "radar1",
                                        :key => "pt_w", :value => 2500))
        @test w.entities[:radar1].comp[:pt_w] == 2500.0
        @test w.entities[:radar1].comp[:pt_w] isa Float64           # type preserved (was Float)

        # run / pause / step set mode + budget; step implies paused stepping
        EWSim.handle_command!(srv, Dict(:type => "run", :mode => "fast", :speed => 4.0))
        @test srv.mode === EWSim.FAST && srv.speed == 4.0
        EWSim.handle_command!(srv, Dict(:type => "pause"))
        @test srv.mode === EWSim.PAUSED
        EWSim.handle_command!(srv, Dict(:type => "step", :n => 50))
        @test srv.mode === EWSim.PAUSED && srv.step_budget == 50

        # set_seed reseeds the stream IN PLACE (clock/entities untouched)
        t_before = w.t
        EWSim.handle_command!(srv, Dict(:type => "set_seed", :value => 7))
        @test srv.seed == 7
        @test w.t == t_before                                       # clock not rewound
        @test rand(copy(w.rng)) == rand(Xoshiro(7))                 # stream is a fresh Xoshiro(7)

        # an unknown command is rejected, not silently ignored
        @test_throws ErrorException EWSim.handle_command!(srv, Dict(:type => "frobnicate"))
        # set_param on a missing entity fails loudly (a silent no-op would hide a typo)
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_param", :target => "ghost", :key => "x", :value => 1))
        # set_param on a real entity but a NON-KNOB key is rejected — writing it would bypass the
        # load-time guards (e.g. `swerling` reaches pd_analytic and throws inside the next tick,
        # killing the session). Only declared knobs are live-settable. `:swerling` is a real comp
        # key on radar1 but NOT a knob in this fixture, so it must be refused.
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_param", :target => "radar1", :key => "swerling", :value => 7))
    end

    @testset "a bad load_scenario is atomic — the session keeps serving the old scenario" begin
        # This is the payoff of validating fidelity at LOAD: a mid-session load_scenario of a file
        # with a bad fidelity rung throws INSIDE handle_command! (the command try catches it →
        # error frame → keep serving), and because the build+validate happens before any `srv`
        # field is touched, `srv` is left EXACTLY on the old scenario — not a fatal tick death, not
        # a half-loaded limbo. (Without the guard the load would succeed and the NEXT tick would
        # throw in the tick loop, which the outer catch rethrows → session death.)
        srv = EWSim.Server(_detect_scenario(1))
        old_scn = srv.scn; old_path = srv.path
        bad = tempname() * ".yaml"
        write(bad, """
        name: bad_fid
        fidelity: {propagation: bogus}
        entities:
          - id: radar1
            kind: radar
            pos: [0,0,0]
            radar: {pt_w: 1, gain_db: 1, freq_hz: 1.0e9, bandwidth_hz: 1.0e6,
                    noise_fig_db: 0, losses_db: 0, pfa: 1.0e-6, swerling: 1}
        """)
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "load_scenario", :path => bad))
        @test srv.scn === old_scn        # unchanged — still the old scenario
        @test srv.path == old_path       # not even the path was poisoned (atomic swap)
        rm(bad; force = true)
    end

    @testset "set_fidelity toggles propagation live (slice-2 extension)" begin
        srv = EWSim.Server(_detect_scenario(1))
        w = srv.scn.world
        @test get(w.fidelity, :propagation, :free_space) === :free_space   # the scenario default

        EWSim.handle_command!(srv, Dict(:type => "set_fidelity",
                                        :key => "propagation", :value => "two_ray"))
        @test w.fidelity[:propagation] === :two_ray                        # written through
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity",
                                        :key => "propagation", :value => "free_space"))
        @test w.fidelity[:propagation] === :free_space                     # toggles back

        # A bad value must be REJECTED before it lands — else it would reach observe! and
        # throw inside tick!, where the session's outer catch (IO/EOF only) lets it kill the
        # connection. The reject must also leave the live fidelity untouched.
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "propagation", :value => "telepathy"))
        @test w.fidelity[:propagation] === :free_space                     # unchanged by the bad cmd
        # A non-propagation fidelity key is not live-settable in slice 2 (loud, not silent).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "detection", :value => "monte_carlo"))
    end

    @testset "set_fidelity generalises to a per-key table + guards introducing :cfar" begin
        # On a CFAR scenario the cfar rung is live-settable across its modes...
        srv = EWSim.Server(_cfar_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:cfar] === :ca
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "cfar", :value => "go"))
        @test w.fidelity[:cfar] === :go
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "cfar", :value => "os"))
        @test w.fidelity[:cfar] === :os
        # ...a bad rung is REJECTED before it lands (would throw in observe! → kill session),
        # and leaves the live value untouched.
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "cfar", :value => "bogus"))
        @test w.fidelity[:cfar] === :os
        # propagation is still live-settable from the SAME table (no regression).
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "propagation", :value => "two_ray"))
        @test w.fidelity[:propagation] === :two_ray

        # Draw-topology guard: a scenario WITHOUT :cfar must reject INTRODUCING it (the
        # point→profile draw-count flip would desync a mid-run replay). Introducing
        # propagation (same draw count either rung) stays allowed.
        srv2 = EWSim.Server(_detect_scenario(1))                 # no :cfar key
        w2 = srv2.scn.world
        @test !haskey(w2.fidelity, :cfar)
        @test_throws ErrorException EWSim.handle_command!(srv2,
            Dict(:type => "set_fidelity", :key => "cfar", :value => "ca"))
        @test !haskey(w2.fidelity, :cfar)                       # still absent after the reject
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "propagation", :value => "two_ray"))
        @test w2.fidelity[:propagation] === :two_ray
    end

    @testset "set_fidelity :ep — write/reject + introduce-safe (no :cfar-style guard)" begin
        # Slice-4 gate 3: `:ep` joins the per-key LIVE_FIDELITY_MODES table. Unlike `:cfar` it
        # carries NO introduce-guard — EP only scales a deterministic scalar (no draw-count
        # change), so it is safe to set on ANY scenario, even one that never had an `:ep` key. Use
        # a plain (non-cfar, non-jammer) scenario to prove exactly that introduce-safety.
        srv = EWSim.Server(_detect_scenario(1))
        w = srv.scn.world
        @test !haskey(w.fidelity, :ep)                          # the scenario default: no EP key
        # INTRODUCING :ep mid-run is ALLOWED (the sharp contrast to :cfar's introduce-reject)...
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "ep", :value => "freq_agility"))
        @test w.fidelity[:ep] === :freq_agility
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "ep", :value => "sidelobe_blanking"))
        @test w.fidelity[:ep] === :sidelobe_blanking            # ...and changing the value too
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "ep", :value => "none"))
        @test w.fidelity[:ep] === :none
        # ...a bad rung is REJECTED before it lands (would throw in observe! → kill the session),
        # leaving the live value untouched.
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "ep", :value => "cloaking"))
        @test w.fidelity[:ep] === :none                         # unchanged by the bad cmd
    end

    @testset "set_fidelity :estimator — write/reject + introduce-safe (slice-5 DF)" begin
        # Slice-5 gate 3: `:estimator` joins the per-key LIVE_FIDELITY_MODES table (referencing
        # ESTIMATOR_MODES). Like `:ep` and unlike `:cfar` it carries NO introduce-guard — each
        # DFSensor draws exactly one randn/look regardless of rung, so the rung selects only the
        # Geolocator's deterministic post-processing (no draw-count change) — introduce-safe.
        srv = EWSim.Server(_geoloc_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:estimator] === :pseudolinear          # the scenario default rung
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "estimator", :value => "ml"))
        @test w.fidelity[:estimator] === :ml
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "estimator", :value => "pseudolinear"))
        @test w.fidelity[:estimator] === :pseudolinear
        # ...a bad rung is REJECTED before it lands (would throw in decide! → kill the session),
        # leaving the live value untouched.
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "estimator", :value => "kalman"))
        @test w.fidelity[:estimator] === :pseudolinear

        # INTRODUCING :estimator on a scenario WITHOUT it is ALLOWED (the sharp contrast to :cfar's
        # introduce-reject) — a non-DF world simply has no Geolocator to consume it, so it's a
        # harmless write (the slice-4 :ep introduce-safety, on a new key). Use a plain radar
        # scenario to prove exactly that.
        srv2 = EWSim.Server(_detect_scenario(1))
        w2 = srv2.scn.world
        @test !haskey(w2.fidelity, :estimator)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "estimator", :value => "ml"))
        @test w2.fidelity[:estimator] === :ml
    end

    @testset "set_fidelity :deinterleaver — write/reject + introduce-safe (slice-6 EW)" begin
        # Slice-6 gate 3: `:deinterleaver` joins the per-key LIVE_FIDELITY_MODES table (referencing
        # DEINTERLEAVER_MODES). Like `:ep`/`:estimator` and unlike `:cfar` it carries NO
        # introduce-guard — the ESMReceiver draws a fixed count/look regardless of the rung (the
        # whole draw is phase-3), so the rung selects only the Deinterleaver's phase-4
        # post-processing (no draw-count change) — introduce-safe AND toggle-bit-identical.
        srv = EWSim.Server(_esm_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:deinterleaver] === :cdif              # the scenario default rung
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "deinterleaver", :value => "sdif"))
        @test w.fidelity[:deinterleaver] === :sdif
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "deinterleaver", :value => "cdif"))
        @test w.fidelity[:deinterleaver] === :cdif
        # ...a bad rung is REJECTED before it lands (would throw in decide! → kill the session),
        # leaving the live value untouched.
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "deinterleaver", :value => "nelson"))
        @test w.fidelity[:deinterleaver] === :cdif

        # INTRODUCING :deinterleaver on a scenario WITHOUT it is ALLOWED (the sharp contrast to
        # :cfar's introduce-reject) — a non-ESM world has no Deinterleaver to consume it, so it's a
        # harmless write (the :ep/:estimator introduce-safety). Use a plain radar scenario.
        srv2 = EWSim.Server(_detect_scenario(1))
        w2 = srv2.scn.world
        @test !haskey(w2.fidelity, :deinterleaver)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "deinterleaver", :value => "sdif"))
        @test w2.fidelity[:deinterleaver] === :sdif
    end

    @testset "warmup! tolerates an ESM scenario (slice-6, radar-free, phases 2+3+4)" begin
        # An ESM scenario is radar-free like slice-5 DF, so warmup!'s ROC-batch warm is skipped
        # (the radar-guard); the tick!+state_frame warm still runs — and here it warms the FULL
        # phase-2+3+4 capstone (PulseEmitter→ESMReceiver→Deinterleaver) plus the array-telemetry
        # (histogram/threshold) round-trip. It must NOT throw and must leave the live World pristine.
        srv = EWSim.Server(_esm_scenario(6))
        t0   = srv.scn.world.t
        pos0 = srv.scn.world.entities[:pe1].pos
        EWSim.warmup!(srv)                                          # must NOT throw (no radar)
        @test srv.scn.world.t == t0
        @test srv.scn.world.entities[:pe1].pos == pos0
        @test rand(copy(srv.scn.world.rng)) == rand(Xoshiro(6))    # live rng untouched
    end

    @testset "set_fidelity: the six GPS keys — write/reject + introduce-safe (slice-7)" begin
        # Slice-7 gate 2: the six GPS keys (iono/tropo/clock/multipath/noise = GPS_TOGGLE, raim =
        # RAIM_MODES) join the per-key LIVE_FIDELITY_MODES table. Like :ep/:estimator/:deinterleaver
        # and unlike :cfar they carry NO introduce-guard — the GpsReceiver draws 2·n_sats/look
        # regardless of any key (the whole draw is phase-3), so each key selects only a term's
        # contribution / the phase-4 raim post-processing (no draw-count change) — introduce-safe.
        srv = EWSim.Server(_gps_scenario(1))
        w = srv.scn.world
        for key in ("iono", "tropo", "clock", "multipath", "noise")
            EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => key, :value => "on"))
            @test w.fidelity[Symbol(key)] === :on
            EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => key, :value => "off"))
            @test w.fidelity[Symbol(key)] === :off
        end
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "raim", :value => "detect"))
        @test w.fidelity[:raim] === :detect
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "raim", :value => "exclude"))
        @test w.fidelity[:raim] === :exclude
        # ...bad rungs REJECTED before landing (would throw in decide!/observe! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "raim", :value => "maybe"))
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "noise", :value => "loud"))

        # INTRODUCING a GPS key on a scenario WITHOUT it is ALLOWED (the :ep/:estimator/:deinterleaver
        # contract, NOT :cfar's introduce-reject) — a non-GPS world has no GpsSolver to consume it.
        srv2 = EWSim.Server(_detect_scenario(1))
        w2 = srv2.scn.world
        @test !haskey(w2.fidelity, :raim)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "raim", :value => "detect"))
        @test w2.fidelity[:raim] === :detect
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "iono", :value => "on"))
        @test w2.fidelity[:iono] === :on
    end

    @testset "warmup! tolerates a GPS scenario (slice-7, radar-free, phases 2+3+4)" begin
        # A GPS scenario is radar-free like slice-5/6, so warmup!'s ROC-batch warm is skipped (the
        # radar-guard); the tick!+state_frame warm still runs — warming the FULL phase-2+3+4 §9
        # reuse pipeline (GpsSatellite→GpsReceiver→GpsSolver) plus the display-array telemetry
        # round-trip. It must NOT throw and must leave the live World pristine.
        srv = EWSim.Server(_gps_scenario(6))
        t0   = srv.scn.world.t
        pos0 = srv.scn.world.entities[:sv1].pos
        EWSim.warmup!(srv)                                          # must NOT throw (no radar)
        @test srv.scn.world.t == t0
        @test srv.scn.world.entities[:sv1].pos == pos0
        @test rand(copy(srv.scn.world.rng)) == rand(Xoshiro(6))    # live rng untouched
    end

    @testset "set_fidelity :integrator — write/reject + introduce-safe (slice-8 missile)" begin
        # Slice-8 gate 2: :integrator (rungs INTEGRATOR_MODES) joins the per-key LIVE_FIDELITY_MODES
        # table. Like :ep/:estimator/:deinterleaver and unlike :cfar it carries NO introduce-guard —
        # absent a :missile entity nothing reads it, so it may be introduced on any scenario. NB
        # (advisor #1): UNLIKE those keys it is PHYSICS-CHANGING not toggle-bit-identical (there is
        # no RNG in slice 8) — introduce-safe ≠ toggle-invariant; the trajectory-change is pinned in
        # test_determinism, here we pin only the wire write/reject + introduce-allowed.
        srv = EWSim.Server(_missile_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:integrator] === :rk4                     # the scenario default
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "integrator", :value => "euler"))
        @test w.fidelity[:integrator] === :euler
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "integrator", :value => "rk4"))
        @test w.fidelity[:integrator] === :rk4
        # ...a bad rung is REJECTED before landing (would throw in integrate! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "integrator", :value => "leapfrog"))

        # INTRODUCING :integrator on a scenario WITHOUT it is ALLOWED (the :ep/:estimator/:deinterleaver
        # contract, NOT :cfar's introduce-reject) — a non-missile world has no BallisticMissile to
        # consume it, so it's a harmless no-op write. Use a plain radar scenario.
        srv2 = EWSim.Server(_detect_scenario(1))
        w2 = srv2.scn.world
        @test !haskey(w2.fidelity, :integrator)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "integrator", :value => "euler"))
        @test w2.fidelity[:integrator] === :euler
    end

    @testset "warmup! tolerates a missile scenario (slice-8, radar-free, phase-1 integrator)" begin
        # A missile scenario is radar-free like slice-5/6/7, so warmup!'s ROC-batch warm is skipped
        # (the radar-guard); the tick!+state_frame warm still runs — warming the phase-1 force
        # integrator + the phase-2 energy telemetry round-trip. It must NOT throw and must leave the
        # live World pristine.
        srv = EWSim.Server(_missile_scenario(8))
        t0   = srv.scn.world.t
        pos0 = srv.scn.world.entities[:m1].pos
        EWSim.warmup!(srv)                                          # must NOT throw (no radar)
        @test srv.scn.world.t == t0
        @test srv.scn.world.entities[:m1].pos == pos0              # deepcopy warm didn't move the live missile
    end

    @testset "set_fidelity :autopilot — write/reject + introduce-safe (slice-9 guided missile)" begin
        # Slice-9 gate 2: :autopilot (rungs AUTOPILOT_MODES) joins the per-key LIVE_FIDELITY_MODES
        # table. Like :integrator/:ep and unlike :cfar it carries NO introduce-guard (absent an
        # Autopilot subsystem nothing reads it). Also like :integrator it is PHYSICS-CHANGING not
        # toggle-bit-identical (no RNG) — the trajectory-change is pinned in test_determinism; here
        # we pin only the wire write/reject + introduce-allowed.
        srv = EWSim.Server(_guided_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:autopilot] === :ideal                    # the scenario default
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "autopilot", :value => "pid"))
        @test w.fidelity[:autopilot] === :pid
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "autopilot", :value => "ideal"))
        @test w.fidelity[:autopilot] === :ideal
        # ...a bad rung is REJECTED before landing (would throw in decide! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "autopilot", :value => "bang_bang"))
        # INTRODUCING :autopilot on a scenario WITHOUT it is ALLOWED (the :integrator/:ep contract,
        # NOT :cfar's introduce-reject) — a non-guided world has no Autopilot to consume it.
        srv2 = EWSim.Server(_detect_scenario(1))
        @test !haskey(srv2.scn.world.fidelity, :autopilot)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "autopilot", :value => "pid"))
        @test srv2.scn.world.fidelity[:autopilot] === :pid
    end

    @testset "live PID-gain sliders survive the tick (a diverging gain hits the clamp, not a throw)" begin
        # The gains (kp/ki/kd/tau/k_guid) are LIVE sliders — a destabilizing value would diverge the
        # discrete PID, but the a_max clamp threads the bounded plant output back, so the tick can't
        # throw / NaN the session (the "a live slider can't crash a tick" watch-item, over MANY ticks).
        srv = EWSim.Server(_guided_scenario(2; fidelity = Dict(:autopilot => :pid)))
        w = srv.scn.world
        for (k, v) in (("kp", 5.0e5), ("ki", 1.0e4), ("kd", 1.0e2), ("tau", 1.0e-6), ("k_guid", 1.0e3))
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "m1", :key => k, :value => v))
        end
        @test w.entities[:m1].comp[:kp] == 5.0e5                    # slider wrote the consumed comp key
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics)             # must NOT throw
            empty!(w.events)
            ok &= all(isfinite, w.entities[:m1].pos)
        end
        @test ok                                                   # pos stayed finite through the divergence
    end

    @testset "set_fidelity :guidance — write/reject + introduce-safe (slice-10 PN outer law)" begin
        # Slice-10 gate 2: :guidance (rungs GUIDANCE_MODES) joins the per-key LIVE_FIDELITY_MODES table
        # AUTOMATICALLY (the per-key check reads it; _KNOWN_FIDELITY_KEYS = keys(LIVE_FIDELITY_MODES) —
        # no server change). Like :autopilot/:integrator and unlike :cfar it carries NO introduce-guard
        # (absent an Autopilot subsystem nothing reads it) AND is PHYSICS-CHANGING (the trajectory
        # change is pinned in test_determinism; here only the wire write/reject + introduce-allowed).
        srv = EWSim.Server(_pn_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:guidance] === :pn                        # the scenario default
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "guidance", :value => "pursuit"))
        @test w.fidelity[:guidance] === :pursuit
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "guidance", :value => "pn"))
        @test w.fidelity[:guidance] === :pn
        # ...a bad rung is REJECTED before landing (would throw in decide! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "guidance", :value => "homing"))
        # INTRODUCING :guidance on a scenario WITHOUT it is ALLOWED — a slice-9 guided world (Autopilot
        # present, no :guidance key, defaulting to :pursuit) and a non-missile world both accept it.
        srv2 = EWSim.Server(_guided_scenario(1))
        @test !haskey(srv2.scn.world.fidelity, :guidance)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "guidance", :value => "pn"))
        @test srv2.scn.world.fidelity[:guidance] === :pn
        srv3 = EWSim.Server(_detect_scenario(1))
        EWSim.handle_command!(srv3, Dict(:type => "set_fidelity", :key => "guidance", :value => "pn"))
        @test srv3.scn.world.fidelity[:guidance] === :pn           # inert on a radar world (nothing reads it)
    end

    @testset "live N / a_max / r_stop sliders survive the tick (a huge N hits the clamp, not a throw)" begin
        # N (n_pn), a_max, and r_stop are LIVE sliders. A huge N drives the PN demand far above a_max,
        # but clamp_accel caps it — the tick can't throw / NaN the session. This is the "a live slider
        # can't crash a tick" watch-item, now including the DELIBERATELY-BINDING a_max (the glimit
        # inversion of slice 9's never-bind clamp — the guard role the clamp keeps even when it binds).
        srv = EWSim.Server(_pn_scenario(2))
        w = srv.scn.world
        for (k, v) in (("n_pn", 1.0e3), ("a_max", 50.0), ("r_stop", 150.0))
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "m1", :key => k, :value => v))
        end
        @test w.entities[:m1].comp[:n_pn] == 1.0e3                  # slider wrote the consumed comp key
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics)             # must NOT throw
            empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].pos) && isfinite(tel["m1.a_cmd"]) &&
                  isfinite(tel["m1.a_demand"]) && isfinite(tel["m1.los_rate"])
            ok || break
        end
        @test ok                                                   # pos + telemetry finite through the huge-N demand
    end

    @testset "set_fidelity :seeker — write/reject + introduce-safe (slice-11 noisy seeker)" begin
        # Slice-11 gate 2: :seeker (rungs SEEKER_MODES from estimation.jl) joins the per-key
        # LIVE_FIDELITY_MODES table AUTOMATICALLY (no server change). The NEW fidelity-class COMBO:
        # DRAW-INVARIANT (class 4a — both rungs draw the same 1 randn/tick, the filter is pure
        # post-processing → like :ep/:estimator and UNLIKE :cfar it carries NO introduce-guard) YET
        # TRAJECTORY-CHANGING (the trajectory change is pinned in test_determinism; here only the wire
        # write/reject + introduce-allowed).
        srv = EWSim.Server(_seeker_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:seeker] === :filtered                    # the scenario default
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "seeker", :value => "raw"))
        @test w.fidelity[:seeker] === :raw
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "seeker", :value => "filtered"))
        @test w.fidelity[:seeker] === :filtered
        # ...a bad rung is REJECTED before landing (would throw in observe! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "seeker", :value => "kalman"))
        # INTRODUCING :seeker mid-run is ALLOWED (class 4a — introducing it changes NO draw count, the
        # sharp contrast to :cfar's introduce-reject): inert on a radar world (no Seeker reads it), and
        # draw-count-safe on a seeker world that omitted the key (defaulting to :filtered).
        srv2 = EWSim.Server(_detect_scenario(1))
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "seeker", :value => "raw"))
        @test srv2.scn.world.fidelity[:seeker] === :raw            # inert on a radar world (nothing reads it)
        srv3 = EWSim.Server(_seeker_scenario(1; fidelity = Dict(:autopilot => :ideal, :guidance => :pn)))
        @test !haskey(srv3.scn.world.fidelity, :seeker)           # a seeker world that omitted the key
        EWSim.handle_command!(srv3, Dict(:type => "set_fidelity", :key => "seeker", :value => "raw"))
        @test srv3.scn.world.fidelity[:seeker] === :raw           # introduced mid-run — draw-count-safe
    end

    @testset "live σ_seek / α / β sliders survive the tick (a huge σ pegs a_max, not a throw)" begin
        # σ_seek, α, β are LIVE sliders — the FIRST live sliders on a path with an RNG draw. An absurd
        # σ drives the raw finite-diff λ̇ to thousands of m/s² → the a_max clamp caps it (never a
        # throw); α→edge / β→edge can't NaN the α-β step (the β/dt floor). The "a live slider can't
        # crash a tick" watch-item, now with a draw in the loop.
        srv = EWSim.Server(_seeker_scenario(2;
            fidelity = Dict(:autopilot => :ideal, :guidance => :pn, :seeker => :raw)))
        w = srv.scn.world
        for (k, v) in (("sigma_seek", 5.0), ("alpha", 0.99), ("beta", 1.0))
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "m1", :key => k, :value => v))
        end
        @test w.entities[:m1].comp[:sigma_seek] == 5.0            # slider wrote the consumed comp key
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics)            # must NOT throw
            empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].pos) && isfinite(tel["m1.a_cmd"]) &&
                  isfinite(tel["m1.a_demand"]) && isfinite(tel["m1.lambda_dot_raw"]) &&
                  isfinite(tel["m1.lambda_dot_filt"])
            ok || break
        end
        @test ok                                                  # pos + seeker telemetry finite through the huge σ
    end

    @testset "set_fidelity :guidance :apn — the third rung write/reject + introduce-safe (slice-12)" begin
        # Slice-12: `:apn` is a NEW value of the existing `:guidance` key (GUIDANCE_MODES += :apn), so
        # it flows through the SAME per-key LIVE_FIDELITY_MODES check AUTOMATICALLY (one-list-no-drift —
        # no server change). Physics-changing, NO RNG (like :pn, UNLIKE :cfar it carries no introduce-
        # guard). The trajectory change is pinned in test_determinism; here only the wire write/reject.
        srv = EWSim.Server(_apn_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:guidance] === :apn                       # the scenario default (the third rung, real)
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "guidance", :value => "pn"))
        @test w.fidelity[:guidance] === :pn
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "guidance", :value => "apn"))
        @test w.fidelity[:guidance] === :apn
        # cycle through all three rungs on the wire (the 3-ring the Godot cycler drives).
        for v in ("pursuit", "pn", "apn")
            EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "guidance", :value => v))
            @test w.fidelity[:guidance] === Symbol(v)
        end
        # a bad rung is REJECTED before landing (would throw in decide! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "guidance", :value => "augmented"))
        # INTRODUCING :apn mid-run on a scenario that omitted :guidance is ALLOWED (physics-changing, no
        # RNG — no draw-topology hazard, the :pn precedent; the maneuvering mover already runs regardless).
        srv2 = EWSim.Server(_apn_scenario(1; fidelity = Dict(:autopilot => :ideal)))
        @test !haskey(srv2.scn.world.fidelity, :guidance)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "guidance", :value => "apn"))
        @test srv2.scn.world.fidelity[:guidance] === :apn
    end

    @testset "live a_lat / N / a_max sliders survive the tick (a huge a_lat curves harder, not a throw)" begin
        # a_lat (the target maneuver g) is a LIVE slider on the TARGET — the first live slider on the
        # maneuvering mover. An absurd a_lat just curves the target harder (the _lateral_accel is bounded
        # by construction: a unit ⟂ direction × a_lat) and the missile's a_max clamp caps its response —
        # the tick can't throw / NaN the session. The "a live slider can't crash a tick" watch-item.
        srv = EWSim.Server(_apn_scenario(2))
        w = srv.scn.world
        for (tgt, k, v) in (("tgt1", "a_lat_mps2", 5.0e3), ("m1", "n_pn", 1.0e3), ("m1", "a_max", 50.0))
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => tgt, :key => k, :value => v))
        end
        @test w.entities[:tgt1].comp[:a_lat_mps2] == 5.0e3         # slider wrote the consumed comp key
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics)            # must NOT throw
            empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].pos) && all(isfinite, w.entities[:tgt1].pos) &&
                  isfinite(tel["m1.a_cmd"]) && isfinite(tel["m1.a_demand"])
            ok || break
        end
        @test ok                                                  # missile + target pos + telemetry finite
    end

    @testset "set_fidelity :discrimination — write/introduce-safe; :scan introduce/remove REJECTED (slice-13)" begin
        # Slice-13 gate 2: `:discrimination` (rungs DISCRIMINATION_MODES) joins the per-key
        # LIVE_FIDELITY_MODES table AUTOMATICALLY (one-list-no-drift). It is DRAW-INVARIANT among its
        # rungs (both paint+draw the same profile, differ only in peak selection) → introduce-safe, no
        # guard. But `:seeker → :scan` FLIPS the draw topology (1 → 2·N_p·N_bins), so INTRODUCING or
        # REMOVING :scan is REJECTED (the cfar precedent, BOTH directions — the sharpest form).
        srv = EWSim.Server(_scan_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:discrimination] === :none                # the scenario default (reveals the fix)
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "discrimination", :value => "gated"))
        @test w.fidelity[:discrimination] === :gated
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "discrimination", :value => "none"))
        @test w.fidelity[:discrimination] === :none
        # a bad rung is REJECTED before landing (would throw in observe! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "discrimination", :value => "adaptive"))
        # THE 4b GUARD — REMOVING :scan mid-run (:scan → :filtered) is REJECTED (topology flip 1280→1).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "seeker", :value => "filtered"))
        @test w.fidelity[:seeker] === :scan                        # rung untouched after the reject
        # ...and INTRODUCING :scan on a non-scan (slice-11) seeker world is REJECTED too (the other
        # direction — 1→1280). A :raw↔:filtered switch on that world stays live (both 1 draw/tick).
        srv2 = EWSim.Server(_seeker_scenario(1))                   # seeker = :filtered
        @test_throws ErrorException EWSim.handle_command!(srv2,
            Dict(:type => "set_fidelity", :key => "seeker", :value => "scan"))
        @test srv2.scn.world.fidelity[:seeker] === :filtered       # still :filtered after the reject
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "seeker", :value => "raw"))
        @test srv2.scn.world.fidelity[:seeker] === :raw            # :raw↔:filtered stays live (no topology flip)
    end

    @testset "live decoy intensity / gate_halfwidth sliders survive the tick (no crash, slice-13)" begin
        # intensity + gate_halfwidth are LIVE sliders on the :scan path (which DRAWS 2·N_p·N_bins/tick).
        # An absurd intensity just paints a taller lobe (√(power/2) stays finite); a wide gate widens the
        # NN acceptance (validation_gate is safe at any halfwidth). Neither throws / NaNs the session.
        srv = EWSim.Server(_scan_scenario(2;
            fidelity = Dict(:autopilot => :ideal, :guidance => :pn, :seeker => :scan, :discrimination => :gated)))
        w = srv.scn.world
        for (tgt, k, v) in (("dcy1", "intensity", 5.0e8), ("m1", "gate_halfwidth", 3.0))
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => tgt, :key => k, :value => v))
        end
        @test w.entities[:dcy1].comp[:intensity] == 5.0e8         # slider wrote the consumed comp key
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics)            # must NOT throw
            empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].pos) && isfinite(tel["m1.aim_error"]) &&
                  isfinite(tel["m1.lambda_used"]) && isfinite(tel["m1.a_cmd"])
            ok || break
        end
        @test ok                                                  # pos + scan telemetry finite through the huge slider
    end

    @testset "set_fidelity :cooperation — write + introduce-safe BOTH directions (slice-14, class 4c)" begin
        # Slice-14: `:cooperation` (rungs COOPERATION_MODES) joins the per-key LIVE_FIDELITY_MODES table
        # AUTOMATICALLY (one-list-no-drift — no server change). Class 4c (physics-changing, no RNG — the
        # :apn/:integrator shape): NO draw-topology to flip → live-settable BOTH directions with NO guard,
        # the sharp CONTRAST to slice-13's `:scan` (which rejects introduce/remove). The trajectory change
        # is pinned in test_determinism; here only the wire write/reject + the no-guard property.
        srv = EWSim.Server(_salvo_scenario(1))
        w = srv.scn.world
        @test w.fidelity[:cooperation] === :solo                   # the scenario default (the button reveals the fix)
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "cooperation", :value => "salvo"))
        @test w.fidelity[:cooperation] === :salvo                  # INTRODUCE-direction :solo→:salvo — ACCEPTED
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "cooperation", :value => "solo"))
        @test w.fidelity[:cooperation] === :solo                   # REMOVE-direction :salvo→:solo — ALSO accepted
        # cycle the 2-ring the Godot cooperation button drives — every step clean (no topology guard).
        for v in ("salvo", "solo", "salvo")
            EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "cooperation", :value => v))
            @test w.fidelity[:cooperation] === Symbol(v)
        end
        # a bad rung is REJECTED before landing (would throw in decide! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "cooperation", :value => "swarm"))
        # INTRODUCING :cooperation mid-run on a scenario that omitted the key is ALLOWED (class 4c — the
        # coordinator already publishes salvo_t_d regardless; :solo just doesn't read it). The CONTRAST to
        # :scan: no `cur != new` topology guard fires.
        srv2 = EWSim.Server(_salvo_scenario(1; fidelity = Dict(:guidance => :pn, :autopilot => :ideal)))
        @test !haskey(srv2.scn.world.fidelity, :cooperation)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "cooperation", :value => "salvo"))
        @test srv2.scn.world.fidelity[:cooperation] === :salvo
    end

    @testset "live k_it slider survives the tick (a huge K_it curves harder + clamps, not a throw)" begin
        # k_it (the ITC cooperation gain) is a LIVE slider on each interceptor. An absurd K_it just drives a
        # huge impact-time-error feedback that clamp_accel caps at a_max — the tick can't throw / NaN the
        # session (the "a live slider can't crash a tick" watch-item; the VC_FLOOR keeps t_go finite too).
        srv = EWSim.Server(_salvo_scenario(2))
        w = srv.scn.world
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "cooperation", :value => "salvo"))
        for m in ("mA", "mB")
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => m, :key => "k_it", :value => 500.0))
        end
        @test w.entities[:mA].comp[:k_it] == 500.0                 # slider wrote the consumed comp key
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics)            # must NOT throw
            empty!(w.events)
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:mA].pos) && all(isfinite, w.entities[:mB].pos) &&
                  isfinite(tel["mA.a_cmd"]) && isfinite(tel["mA.t_go"]) && isfinite(tel["link.salvo_t_d"])
            ok || break
        end
        @test ok                                                  # both missiles + salvo telemetry finite
    end

    @testset "set_fidelity :autopilot :fin — the third plant rung write/reject + introduce-safe (slice-15, class 4c)" begin
        # Slice-15: `:fin` is a NEW value of the existing `:autopilot` key (AUTOPILOT_MODES += :fin), so
        # it flows through the SAME per-key LIVE_FIDELITY_MODES check AUTOMATICALLY (one-list-no-drift —
        # no server change). Physics-changing, NO RNG → NO draw-topology to flip → NO introduce-guard
        # (the :apn/:cooperation precedent; the CONTRAST to slice-13 :scan's introduce-reject). The
        # trajectory change is pinned in test_determinism; here only the wire write/reject/introduce.
        srv = EWSim.Server(_apn_scenario(1; fidelity = Dict(:autopilot => :fin, :guidance => :pn)))
        w = srv.scn.world
        @test w.fidelity[:autopilot] === :fin                      # the scenario default (the third plant rung)
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "autopilot", :value => "pid"))
        @test w.fidelity[:autopilot] === :pid                      # :fin→:pid — accepted (live)
        EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "autopilot", :value => "fin"))
        @test w.fidelity[:autopilot] === :fin                      # :pid→:fin (INTRODUCE-direction) — accepted
        # cycle the 3-ring the Godot autopilot cycler drives (every step clean — no topology guard).
        for v in ("ideal", "pid", "fin")
            EWSim.handle_command!(srv, Dict(:type => "set_fidelity", :key => "autopilot", :value => v))
            @test w.fidelity[:autopilot] === Symbol(v)
        end
        # a bad rung is REJECTED before landing (would throw in decide! → kill the session).
        @test_throws ErrorException EWSim.handle_command!(srv,
            Dict(:type => "set_fidelity", :key => "autopilot", :value => "bangbang"))
        # INTRODUCING :fin mid-run on a scenario that omitted :autopilot is ALLOWED (class 4c — the
        # CONTRAST to slice-13 :scan's introduce-reject; decide! reads default fin params, no crash).
        srv2 = EWSim.Server(_apn_scenario(1; fidelity = Dict(:guidance => :pn)))
        @test !haskey(srv2.scn.world.fidelity, :autopilot)
        EWSim.handle_command!(srv2, Dict(:type => "set_fidelity", :key => "autopilot", :value => "fin"))
        @test srv2.scn.world.fidelity[:autopilot] === :fin
        for _ in 1:50; tick!(srv2.scn.world, srv2.scn.subs, srv2.scn.dt_physics); empty!(srv2.scn.world.events); end
        @test all(isfinite, srv2.scn.world.entities[:m1].pos)      # a tick under the introduced :fin is clean
    end

    @testset "a degenerate fin param can't crash a tick (δ̇_max→0 / τ_s→0 / k_δ→0 floored at the consumer)" begin
        # The "a live slider can't crash a tick" discipline (convention 5): the fin CONSUMER floors
        # δ̇_max/τ_s/k_δ at _FRAME_EPS (decide!/fin_autopilot_step), so a slider driven to 0 (or absurd)
        # slews slower / divides safely — no throw, no NaN. Mutate the comp directly (the δ̇_max KNOB
        # declaration is a gate-3 scenario concern; here we prove the CONSUMER guard in isolation).
        srv = EWSim.Server(_apn_scenario(2; fidelity = Dict(:autopilot => :fin, :guidance => :pn)))
        w = srv.scn.world
        w.entities[:m1].comp[:delta_rate_max] = 0.0
        w.entities[:m1].comp[:tau_fin] = 0.0
        w.entities[:m1].comp[:k_delta] = 0.0                       # even a 0 effectiveness (divisor) is floored
        ok = true
        for _ in 1:500
            tick!(w, srv.scn.subs, srv.scn.dt_physics); empty!(w.events)   # must NOT throw
            tel = w.env[:telemetry]
            ok &= all(isfinite, w.entities[:m1].pos) && isfinite(tel["m1.a_ach"]) &&
                  isfinite(get(tel, "m1.g_onset", 0.0)) && isfinite(get(tel, "m1.fin_defl", 0.0))
            ok || break
        end
        @test ok                                                   # no throw, no NaN — the tick survives
    end

    @testset "warmup! tolerates a guided-missile scenario (slice-9, radar-free, phase 1+4)" begin
        # A guided missile is radar-free, so warmup!'s ROC-batch warm is skipped; the tick!+state_frame
        # warm still runs — warming the phase-1 integrator + the phase-4 Autopilot decide! + the accel
        # telemetry. It must NOT throw and must leave the live World pristine.
        srv = EWSim.Server(_guided_scenario(9))
        t0 = srv.scn.world.t; pos0 = srv.scn.world.entities[:m1].pos
        EWSim.warmup!(srv)
        @test srv.scn.world.t == t0
        @test srv.scn.world.entities[:m1].pos == pos0
    end

    @testset "scenario_frame ships the static ESM/PRI axis (handshake-once)" begin
        # A slice-6 scenario ships its STATIC histogram axes in the handshake (the CFAR range-axis
        # precedent — they can't change frame-to-frame). `pri_axis_us` is the client's ESM-view
        # discriminator; its length must equal the shipped histogram length (n_bins) — the
        # handshake↔telemetry consistency an axis/binning mismatch would break.
        srv = EWSim.Server(_esm_scenario(1))
        f = EWSim.scenario_frame(srv)
        @test f[:fidelity][:deinterleaver] === :cdif             # the §12 badge sees the rung
        @test f[:esm] === :esm1
        @test f[:n_bins] == 150                                  # 3000 µs / 20 µs bins
        @test f[:dwell_us] ≈ 80_000.0
        @test f[:bin_us] ≈ 20.0
        @test length(f[:pri_axis_us]) == 150
        @test f[:pri_axis_us][1] ≈ 10.0                          # first bin center (0.5·bin_us)
        @test f[:pri_axis_us][end] ≈ 2990.0                      # last bin center
        @test !haskey(f, :range_axis_m)                          # NOT a CFAR scenario
        # the shipped histogram (a live tick's telemetry) has EXACTLY n_bins entries — the axis
        # labels every bar (advisor: catch an axis/binning mismatch the peak check would miss).
        tick!(srv.scn.world, srv.scn.subs, srv.scn.dt_physics)
        tel = state_frame(srv.scn.world)[:telemetry]
        @test length(tel["esm1.histogram"]) == length(f[:pri_axis_us])
    end

    @testset "a live n_train/n_guard slider can't crash the tick (consumer clamp)" begin
        # set_param writes a DECLARED KNOB (n_train/n_guard are knobs here), so a slider dragged to
        # an odd n_train or a negative guard reaches observe! directly — which must CLAMP it, never
        # throw into tick! (the slice-2 set_fidelity / h≥0 watch-item, generalised: a live knob
        # can't kill the session). The loader rejects an odd AUTHORED n_train; this is the
        # live-drag half of that guard, exercised through the real set_param → tick path.
        srv = EWSim.Server(_cfar_scenario(3))
        EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "radar1",
                                        :key => "n_train", :value => 15))   # odd
        EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "radar1",
                                        :key => "n_guard", :value => -1))   # negative
        @test srv.scn.world.entities[:radar1].comp[:n_train] == 15           # written raw...
        tick!(srv.scn.world, srv.scn.subs, srv.scn.dt_physics)              # ...tick survives the clamp
        tel = state_frame(srv.scn.world)[:telemetry]
        @test all(isfinite, tel["radar1.profile_db"])
        @test all(isfinite, tel["radar1.threshold_db"])
    end

    @testset "scenario_frame ships the static CFAR range axis (handshake-once)" begin
        srv = EWSim.Server(_cfar_scenario(7; ncells = 128))
        f = EWSim.scenario_frame(srv)
        @test f[:fidelity][:cfar] === :ca                        # the §12 badge sees the rung
        @test f[:n_cells] == 128
        @test f[:dr_m] ≈ EWSim.C_LIGHT / (2 * 1.0e6)             # Δr = c/2B
        @test length(f[:range_axis_m]) == 128
        @test f[:range_axis_m][1] == 0.0
        @test f[:range_axis_m][2] ≈ f[:dr_m]                     # axis steps by Δr
        # a non-CFAR scenario carries no range axis (keys simply absent)
        g = EWSim.scenario_frame(EWSim.Server(_detect_scenario(1)))
        @test !haskey(g, :range_axis_m) && !haskey(g, :n_cells)
    end

    @testset "scenario_frame ships the airframe_view marker (slice 16, handshake-once)" begin
        # A slice-16 rotational-dynamics scenario carries NO fidelity — the integrator is gated on
        # airframe PARAMS-PRESENCE (:af_cma) and the Cmα SLIDER is the lesson. The handshake ships an
        # `airframe_view` marker (the `_cfar_axis_info`/`_esm_axis_info` view-hint precedent) so the client
        # recognizes the view and drops the fidelity button (nothing to cycle — the advisor Option-P′ path,
        # NOT an :airframe false-fidelity toggle). Assert the marker + target ship, the fidelity map is
        # EMPTY, the af_cma knob is exposed, and no cfar/esm axis leaks in.
        dir = mktempdir()
        af = joinpath(dir, "af.yaml"); write(af, """
        name: af_test
        seed: 16
        dt_physics: 1.0e-3
        emit_every: 16
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 0.0]
            missile:
              mass_kg: 100.0
              speed: 500.0
              elevation_deg: 40.0
              cd_area_m2: 0.0
              airframe: {cma: -0.3, cmq: -150.0, alpha0: 0.15}
        knobs:
          - {target: m1, key: af_cma, min: -0.5, max: 0.5, label: "Cma"}
        """)
        srv = EWSim.Server(load_scenario(af); path = af)
        f = EWSim.scenario_frame(srv)
        @test f[:airframe_view] === true
        @test f[:airframe_target] == "m1"
        @test isempty(f[:fidelity])                              # NO fidelity — the params-presence gate
        @test any(k -> k[:key] === :af_cma, f[:knobs])           # the Cmα slider is exposed (the lesson lever)
        @test !haskey(f, :range_axis_m) && !haskey(f, :pri_axis_us)   # not a cfar/esm view
        # a NON-airframe missile (slice 8, no `airframe:` block) ships NO marker (the gate is params-presence)
        b = joinpath(dir, "ballistic.yaml"); write(b, """
        name: ballistic_test
        seed: 8
        dt_physics: 1.0e-3
        emit_every: 16
        fidelity: {integrator: rk4}
        entities:
          - id: m1
            kind: missile
            pos: [0.0, 0.0, 0.0]
            missile: {mass_kg: 100.0, speed: 500.0, elevation_deg: 40.0, cd_area_m2: 0.0}
        """)
        g = EWSim.scenario_frame(EWSim.Server(load_scenario(b); path = b))
        @test !haskey(g, :airframe_view) && !haskey(g, :airframe_target)
    end

    @testset "set_seed + reset compose into a clean seeded replay" begin
        srv = EWSim.Server(load_scenario(_SCEN_SRV); path = _SCEN_SRV)
        # advance, moving the target off its start
        for _ in 1:20
            tick!(srv.scn.world, srv.scn.subs, srv.scn.dt_physics); srv.step_count += 1
        end
        moved = srv.scn.world.entities[:tgt1].pos
        @test srv.step_count == 20

        EWSim.handle_command!(srv, Dict(:type => "set_seed", :value => 999))
        EWSim.handle_command!(srv, Dict(:type => "reset"))
        @test srv.scn.world.t == 0.0                                # clock zeroed
        @test srv.step_count == 0                                   # counter zeroed
        @test srv.scn.world.entities[:tgt1].pos != moved           # entity back to YAML start
        @test srv.scn.world.entities[:tgt1].pos == Vec3(42000, 0, 3000)
        @test srv.seed == 999                                      # held seed SURVIVES reset
        @test srv.scn.world.seed == 999                            # ...and is applied to the world
        @test rand(copy(srv.scn.world.rng)) == rand(Xoshiro(999))  # stream reseeded to it
    end

    @testset "load_scenario swaps in the new scenario + adopts its seed" begin
        srv = EWSim.Server(_detect_scenario(123))                  # in-memory, seed 123, no path
        resp = EWSim.handle_command!(srv, Dict(:type => "load_scenario", :path => _SCEN_SRV))
        @test resp[:type] == "scenario"                            # handshake frame returned
        @test resp[:name] == "slice1_roc"
        @test srv.path == _SCEN_SRV
        @test srv.seed == 42                                       # adopted the new YAML's seed
        @test srv.scn.world.seed == 42
        @test haskey(srv.scn.world.entities, :radar1)
        # the scenario frame carries the YAML knobs so a client can build its sliders
        @test any(k -> k[:key] === :pt_w, resp[:knobs])
        @test any(k -> k[:key] === :rcs_m2 && k[:log] === true, resp[:knobs])
        # each knob carries its live comp value so a slider opens at the truth, not at `min`
        @test any(k -> k[:key] === :pt_w && k[:value] == 1500.0, resp[:knobs])
        # ...and the actual fidelity map, so the client's §12 badge isn't a hardcoded label
        @test resp[:fidelity][:propagation] === :free_space
    end

    @testset "run_batch maps the §5 grid bounds (snr_db_grid_start/stop rename)" begin
        srv = EWSim.Server(load_scenario(_SCEN_SRV); path = _SCEN_SRV)
        dir = mktempdir()
        # the wire spelling differs from the internal kwargs — if the adapter dropped the
        # mapping, the bounds would silently default to 0–20 / 64 pts.
        desc = EWSim.handle_command!(srv, Dict(:type => "run_batch", :kind => "roc",
            :params => Dict(:trials => 32, :pfa_grid => [1.0e-6],
                            :snr_db_grid_start => 3.0, :snr_db_grid_stop => 17.0,
                            :snr_db_grid_count => 5, :outdir => dir, :name => "t_roc")))
        @test desc[:type] == "artifact"
        @test desc[:snr_db_grid][1]   == 3.0                       # start mapped, not defaulted to 0
        @test desc[:snr_db_grid][end] == 17.0                      # stop  mapped, not defaulted to 20
        @test length(desc[:snr_db_grid]) == 5                      # count mapped, not defaulted to 64
        @test desc[:shape] == [1, 5, 2]
        @test isfile(joinpath(dir, "t_roc.bin"))                   # wrote where asked, not shared/
    end

    @testset "warmup! leaves the live World + shared/ untouched" begin
        srv = EWSim.Server(_detect_scenario(5))
        t0   = srv.scn.world.t
        pos0 = srv.scn.world.entities[:tgt1].pos
        EWSim.warmup!(srv)
        @test srv.scn.world.t == t0                                # clock not advanced
        @test srv.scn.world.entities[:tgt1].pos == pos0           # entity not moved
        @test rand(copy(srv.scn.world.rng)) == rand(Xoshiro(5))    # live rng never drawn from
    end

    @testset "warmup! tolerates a radar-free scenario (slice-5 DF, no ROC batch)" begin
        # The ROC-batch warm resolves a radar; a DF scenario has NONE, so warmup! must skip it
        # rather than throw (an unguarded run_batch would kill the server before it ever listened).
        # The tick!+state_frame warm still runs (it warms the phase-4 decide!/Geolocator path) and
        # must leave the live World pristine, exactly like the radar case.
        srv = EWSim.Server(_geoloc_scenario(5))
        t0   = srv.scn.world.t
        pos0 = srv.scn.world.entities[:emit1].pos
        EWSim.warmup!(srv)                                          # must NOT throw (no radar)
        @test srv.scn.world.t == t0
        @test srv.scn.world.entities[:emit1].pos == pos0
        @test rand(copy(srv.scn.world.rng)) == rand(Xoshiro(5))    # live rng untouched
    end

    @testset "steps_this_iteration paces by mode" begin
        srv = EWSim.Server(_detect_scenario(1; emit_every = 16))
        cap = 16 * 10                                              # emit_every · _MAX_CATCHUP
        srv.mode = EWSim.PAUSED; srv.step_budget = 5
        @test EWSim.steps_this_iteration(srv, 0.1) == 5            # PAUSED: just the budget
        srv.step_budget = 0
        @test EWSim.steps_this_iteration(srv, 0.1) == 0
        srv.mode = EWSim.REALTIME; srv.speed = 1.0
        @test EWSim.steps_this_iteration(srv, 0.016) == 16         # 16 ms / 1 ms = 16 steps
        @test EWSim.steps_this_iteration(srv, 100.0) == cap        # capped: no spiral of death
        srv.mode = EWSim.FAST
        @test EWSim.steps_this_iteration(srv, 0.0) == 16           # fixed chunk = emit_every
    end

    @testset "loopback: handshake, emit, one-shot event clear, EOF teardown (real sockets)" begin
        # PAUSED + step ⇒ deterministic lockstep (no wall-clock pacing to make it flaky):
        # each step(emit_every) yields exactly one state frame.
        srv = EWSim.Server(_detect_scenario(20260620; emit_every = 4, revisit_s = 0.02))
        port, listener = listenany(ip"127.0.0.1", UInt16(45654))
        task = @async EWSim._accept_serve!(srv, listener)
        cli  = connect(ip"127.0.0.1", port)

        # 1. handshake frame arrives first so the client can build sliders before any state
        hello = read_frame(cli)
        @test String(hello.type) == "scenario"

        # 2. one step of emit_every ticks → exactly one state frame, well-formed
        write_frame(cli, Dict("type" => "step", "n" => 4))
        f = read_frame(cli)
        @test String(f.type) == "state"
        @test [String(e.id) for e in f.entities] == ["radar1", "tgt1"]   # sorted-by-id
        @test haskey(f.telemetry, Symbol("radar1.snr_db"))
        @test haskey(f.telemetry, Symbol("radar1.pd"))

        # 3. event lifecycle: an event must appear on some frame AND a later frame must be
        #    event-free. If empty!(w.events) after emit were broken, events would only
        #    accumulate and NO post-event frame would ever be empty — so this discriminates.
        saw_event = false
        saw_clear_after = false
        for _ in 1:80
            write_frame(cli, Dict("type" => "step", "n" => 4))
            fr = read_frame(cli)
            if saw_event && isempty(fr.events)
                saw_clear_after = true
                break
            end
            if !isempty(fr.events)
                saw_event = true
                @test String(fr.events[1].kind) == "detection"
                @test String(fr.events[1].by) == "radar1"
                @test fr.events[1].t == fr.t                 # event stamped with its frame time
            end
        end
        @test saw_event                                       # a detection actually fired
        @test saw_clear_after                                 # ...and was one-shot (cleared next)

        # 4. a malformed command must NOT kill the session — the server replies on an
        #    `error` frame and keeps serving (the @test_throws above only proves the
        #    function rejects it; this proves the LOOP survives one bad frame over the wire).
        write_frame(cli, Dict("type" => "no_such_command"))
        err = read_frame(cli)
        @test String(err.type) == "error"
        write_frame(cli, Dict("type" => "step", "n" => 4))    # ...and is still alive
        @test String(read_frame(cli).type) == "state"

        # 5. clean EOF teardown: client leaves, the server task returns without throwing
        close(cli)
        wait(task)
        @test istaskdone(task)
        close(listener)
    end
end
