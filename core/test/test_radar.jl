# test_radar.jl — the radar SUBSYSTEM dispatch on the propagation knob (slice-2 step 2).
#
# rf.jl's two_ray physics is pinned closed-form in test_propagation; test_radar_eq pins
# free-space. THIS file pins the SUBSYSTEM wiring in `observe!`: it dispatches on
# `w.fidelity[:propagation]`, decomposes geometry into slant/ground, applies the
# below-horizon POLICY, and never lets -Inf/NaN reach the telemetry bag (the wire). Six
# contracts, each against an independent truth:
#   1. default (no fidelity set) == free_space — slice-1 behaviour is untouched;
#   2. two_ray telemetry == the independent snr_two_ray closed form (slant ≠ ground geom);
#   3. a below-horizon target is masked: visible=false, finite floor, pd ≈ pfa, no crash;
#   4. no Inf/NaN reaches the wire at a perfect null (F⁴=0) — the JSON frame round-trips;
#   5. the draw stream is fidelity-independent (determinism: detect_once stays unconditional);
#   6. an unknown propagation rung errors loudly (named, not silent).

using JSON3

# A radar at (0,0,h_r) and one target at (tx,0,h_t); clean λ=0.03 numbers so the two_ray
# phase geometry has no rounding to argue about. `prop = nothing` leaves the fidelity map
# empty (to exercise the get(...,:free_space) default); otherwise it seeds :propagation.
function _radar_world(; prop = :free_space, seed = 1, h_r = 10.0,
                        tx = 20_000.0, h_t = 30.0, rcs = 1.0, pfa = 1.0e-6, sw = 1)
    fid = prop === nothing ? Dict{Symbol,Symbol}() : Dict(:propagation => prop)
    w = World(seed = seed, fidelity = fid)
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, h_r),
        comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
            :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => pfa, :swerling => sw))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(tx, 0, h_t),
        comp = Dict{Symbol,Any}(:rcs_m2 => rcs))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0), ConstantVelocity(:tgt1)]
    return w, subs
end

# Tick once (target is static — vel = 0) and return the published telemetry bag.
function _telemetry(w, subs)
    tick!(w, subs, 1.0e-3)
    return state_frame(w)[:telemetry]
end

@testset "radar propagation dispatch" begin

    @testset "default fidelity is free_space (slice-1 untouched)" begin
        # No :propagation in the map → the get(...,:free_space) default must fire.
        w, subs = _radar_world(prop = nothing)
        rad = w.entities[:radar1];  tgt = w.entities[:tgt1]
        R   = sqrt(sum(abs2, tgt.pos - rad.pos))
        rp  = EWSim._radar_params(rad.comp)
        tel = _telemetry(w, subs)
        @test tel["radar1.snr_db"] ≈ lin2db(snr_freespace(rp, 1.0, R)) rtol = 1e-12
        @test tel["radar1.visible"] == true                  # free space = infinite LOS
    end

    @testset "two_ray telemetry == snr_two_ray closed form (slant ≠ ground)" begin
        # High-grazing geometry: ground = 2000, h_t = 1000 ⇒ slant = 2231.6 ≠ ground, so a
        # slant/ground swap in the dispatch would show. Well inside horizon(10,1000) ≈ 143 km.
        w, subs = _radar_world(prop = :two_ray, tx = 2000.0, h_t = 1000.0)
        rad = w.entities[:radar1];  tgt = w.entities[:tgt1]
        rp  = EWSim._radar_params(rad.comp)
        slant  = sqrt(sum(abs2, tgt.pos - rad.pos))
        ground = hypot(tgt.pos[1] - rad.pos[1], tgt.pos[2] - rad.pos[2])
        expect = snr_two_ray(rp, 1.0, slant; h_r = 10.0, h_t = 1000.0, ground_m = ground)
        tel = _telemetry(w, subs)
        @test tel["radar1.snr_db"] ≈ lin2db(expect) rtol = 1e-12
        @test tel["radar1.visible"] == true
        # ...and it genuinely differs from free space (F⁴ ≠ 1 at this geometry).
        @test !(tel["radar1.snr_db"] ≈ lin2db(snr_freespace(rp, 1.0, slant)))
    end

    @testset "below-horizon target is masked (visible=false, finite floor)" begin
        # radar z=10, target z=30 ⇒ horizon ≈ 35.6 km; put the target at 100 km ground.
        w, subs = _radar_world(prop = :two_ray, tx = 100_000.0, h_t = 30.0)
        tel = _telemetry(w, subs)
        @test tel["radar1.visible"] == false
        @test isfinite(tel["radar1.snr_db"])                 # NOT -Inf
        @test tel["radar1.snr_db"] == EWSim._SNR_DB_FLOOR    # masked → floor
        @test tel["radar1.pd"] ≤ 1.0e-5                      # SNR 0 ⇒ pd ≈ pfa
    end

    @testset "no Inf/NaN reaches the wire at a perfect null (JSON round-trip)" begin
        # A perfect null ABOVE the horizon (a null, not a mask): h_r·h_t = 300, so
        # Δφ = 4π·300/(0.03·R_g) = 2π at R_g = 20 km (< 35.6 km horizon) ⇒ F⁴ = 0 ⇒ SNR = 0.
        # lin2db(0) = -Inf would make JSON3 emit invalid JSON (the slice-2 watch-item).
        w, subs = _radar_world(prop = :two_ray, tx = 20_000.0, h_t = 30.0)
        tick!(w, subs, 1.0e-3)
        frame = state_frame(w)
        sdb = frame[:telemetry]["radar1.snr_db"]
        @test isfinite(sdb)                                  # the whole point: not -Inf
        @test sdb ≤ -100.0                                   # it IS a deep null (floored)
        @test frame[:telemetry]["radar1.visible"] == true    # above horizon: a null, not a mask
        # the frame must survive the REAL wire (JSON3 throws on Inf/NaN).
        io = IOBuffer(); write_frame(io, frame); seekstart(io)
        back = read_frame(io)
        @test isfinite(back.telemetry[Symbol("radar1.snr_db")])
    end

    @testset "draw stream is fidelity-independent (detect_once unconditional)" begin
        # free_space and two_ray must advance w.rng identically (same randn count per look),
        # so toggling fidelity never desyncs seeded replay. Use a BELOW-horizon (masked,
        # SNR=0) two_ray geometry — the strongest case: a masked target still costs its
        # draws. After K identical looks the two streams must sit at the same point.
        wf, sf = _radar_world(prop = :free_space, seed = 20260621, tx = 100_000.0, h_t = 30.0)
        wt, st = _radar_world(prop = :two_ray,    seed = 20260621, tx = 100_000.0, h_t = 30.0)
        for _ in 1:50
            tick!(wf, sf, 1.0e-3)
            tick!(wt, st, 1.0e-3)
        end
        @test rand(copy(wf.rng)) == rand(copy(wt.rng))       # streams in lockstep
    end

    @testset "an unknown propagation rung errors (named, not silent)" begin
        w, subs = _radar_world(prop = :telepathy)
        @test_throws ErrorException tick!(w, subs, 1.0e-3)
    end
end
