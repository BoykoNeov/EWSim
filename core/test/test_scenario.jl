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
