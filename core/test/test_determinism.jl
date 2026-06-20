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
end
