# test_determinism.jl — same seed + same scenario ⇒ bit-identical trace.
#
# This is the contract that makes everything else (replay, MC-vs-truth, teaching
# reproducibility) possible. The fixture below is a minimal subsystem that both
# integrates kinematics AND draws from the world's single RNG stream, so the
# test actually exercises seeded reproducibility rather than trivially passing
# on a static world.

# --- fixture: a constant-velocity walker with seeded process noise ---
struct RandomWalker <: Subsystem
    id::Symbol
    sigma::Float64          # process-noise stddev, m/√s
end

function EWSim.integrate!(rw::RandomWalker, w::World, dt::Float64)
    e = w.entities[rw.id]
    # Draw from the world's single seeded stream — order of draws is what makes
    # the trace reproducible. Brownian scaling (√dt) keeps it dimensionally sane.
    noise = Vec3(randn(w.rng), randn(w.rng), randn(w.rng)) .* (rw.sigma * sqrt(dt))
    e.pos = e.pos + e.vel * dt + noise
end

function run_trace(seed; nsteps = 500, dt = 1.0e-3)
    w = World(seed = seed)
    w.entities[:walker] = Entity(:walker, :target;
                                 pos = Vec3(0.0, 0.0, 0.0),
                                 vel = Vec3(1.0, -2.0, 0.5))
    subs = Subsystem[RandomWalker(:walker, 0.3)]
    trace = Vector{Vec3}(undef, nsteps)
    for i in 1:nsteps
        tick!(w, subs, dt)
        trace[i] = w.entities[:walker].pos
    end
    return w, trace
end

@testset "determinism" begin
    wa, a = run_trace(42)
    wb, b = run_trace(42)

    @testset "same seed ⇒ identical trace" begin
        @test length(a) == 500
        @test a == b                                   # elementwise-exact equality
        # bit-identity, including sign of zero — the strict form of the contract
        flat(v) = reinterpret(UInt64, reduce(vcat, v))
        @test flat(a) == flat(b)
    end

    @testset "clock advances deterministically" begin
        @test wa.t == wb.t
        @test wa.t ≈ 500 * 1.0e-3
        @test isempty(wa.env)                          # env is cleared at end of each tick's rebuild
    end

    @testset "RNG is actually exercised" begin
        _, c = run_trace(43)
        @test a != c                                   # different seed ⇒ different trace
        @test a[end] != Vec3(500e-3, -2 * 500e-3, 0.5 * 500e-3)  # noise moved it off the deterministic line
    end

    # A live fidelity toggle (slice-2 set_fidelity) mutates the World mid-run exactly like
    # set_param, so it must NOT break replay. detect_once draws the same randn count under
    # either propagation rung, so the stream stays in lockstep across the flip — only the
    # detection OUTCOMES change. Capture the per-look detection trace across a toggle and
    # assert two same-seed runs match bit-for-bit. (A static target keeps the geometry —
    # hence pd — constant within each segment, so the trace is a pure RNG fingerprint.)
    @testset "a mid-run fidelity toggle replays deterministically" begin
        function toggle_trace(seed; toggle_at = 200, nsteps = 400)
            w = World(seed = seed, fidelity = Dict(:propagation => :free_space))
            w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 10),
                comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                    :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                    :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
            w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9000.0, 0, 30),
                comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))             # SNR ≈ 17 ⇒ pd ≈ 0.47, off the rails
            subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
            hits = Bool[]
            for i in 1:nsteps
                i == toggle_at && (w.fidelity[:propagation] = :two_ray)   # the live toggle
                tick!(w, subs, 1.0e-3)
                push!(hits, any(e -> e[:kind] === :detection, w.events))
                empty!(w.events)
            end
            return w, hits
        end
        wa, ta = toggle_trace(20260621)
        wb, tb = toggle_trace(20260621)
        @test ta == tb                                  # identical detection trace across the toggle
        @test rand(copy(wa.rng)) == rand(copy(wb.rng))  # ...and the streams end in lockstep
        @test any(ta) && !all(ta)                       # non-trivial: rng genuinely flips outcomes
    end
end
