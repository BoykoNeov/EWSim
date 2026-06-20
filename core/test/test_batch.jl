# test_batch.jl — the ROC batch (slice-1 step 6, gate 3).
#
# Gate 3 is "analytic ≈ MC convergence": the same closed-form-vs-simulation pattern
# as test_detection, but now through the full run_batch → artifact → load_roc path the
# Pluto notebook depends on. Five contracts, each against an independent truth:
#   1. the artifact's analytic plane equals an INDEPENDENT closed-form recompute on the
#      grid — this catches a transpose / plane-swap in the bytes↔array reconstruction
#      (a dim-order bug would make the recompute miss);
#   2. the MC plane lands in the analytic Pd's Wilson 4σ band across the grid (the
#      convergence lesson, as a regression);  NB: no byte-identity assert — HANDOFF
#      reserves the batch as the distribution path (§1/§12), so pinning bytes would
#      forbid the threads/GPU it leaves room for;
#   3. the descriptor + on-disk file agree: shape = [n_pfa, n_snr, 2], the `.bin` is
#      exactly prod(shape)·8 bytes, and load_roc reads back those dims;
#   4. a batch leaves `w.rng` untouched — the live deterministic trace must survive a
#      sweep run against the same World (the §1 invariant that motivates the own-RNG rule);
#   5. analytic Pd is monotone increasing in SNR for every Pfa (a cheap sanity rail).

using JSON3, Random

const _SCEN_BATCH = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice1_roc.yaml"))

# Wilson score interval (robust near Pd ≈ 0) at z σ — the test_detection band reused.
function _wilson(p, n, z)
    center = (p + z^2 / (2n)) / (1 + z^2 / n)
    half   = z * sqrt(p * (1 - p) / n + z^2 / (4n^2)) / (1 + z^2 / n)
    return center - half, center + half
end

@testset "batch (ROC sweep)" begin

    # A small, fast grid written to a tempdir so the real shared/roc_radar1.bin is
    # never touched by the suite. Trials kept modest; the 4σ band absorbs the variance.
    dir    = mktempdir()
    pfas   = [1e-6, 1e-4]
    trials = 60_000
    scn = load_scenario(_SCEN_BATCH)
    desc = run_batch(scn; kind = :roc, pfa_grid = pfas,
                     snr_db_start = 0.0, snr_db_stop = 16.0, snr_db_count = 9,
                     trials = trials, outdir = dir, name = "roc_test")
    sw = Int(scn.world.entities[:radar1].comp[:swerling])

    @testset "descriptor + on-disk file agree (HANDOFF §5)" begin
        @test desc[:type] == "artifact"
        @test desc[:shape] == [length(pfas), 9, 2]
        @test desc[:dtype] == "f64"
        @test desc[:swerling] == sw
        @test desc[:trials] == trials
        @test length(desc[:pfa_grid]) == length(pfas)
        @test length(desc[:snr_db_grid]) == 9
        binpath = desc[:path]
        @test isfile(binpath)
        @test filesize(binpath) == prod(desc[:shape]) * sizeof(Float64)
        @test isfile(EWSim._meta_of(binpath))
    end

    roc = load_roc(desc[:path])

    @testset "load_roc round-trips the grid + dims" begin
        @test size(roc.pd_analytic) == (length(pfas), 9)
        @test size(roc.pd_mc)       == (length(pfas), 9)
        @test roc.pfa_grid    == desc[:pfa_grid]
        @test roc.snr_db_grid == desc[:snr_db_grid]
        @test roc.swerling    == sw
    end

    @testset "analytic plane == independent closed-form recompute (no transpose)" begin
        for (i, pfa) in enumerate(roc.pfa_grid), (j, sdb) in enumerate(roc.snr_db_grid)
            want = pd_analytic(EWSim.db2lin(sdb), pfa; swerling = sw)
            @test roc.pd_analytic[i, j] ≈ want rtol = 1e-12
        end
    end

    @testset "MC plane within analytic Pd's Wilson 4σ band (convergence)" begin
        z = 4.0
        for i in eachindex(roc.pfa_grid), j in eachindex(roc.snr_db_grid)
            lo, hi = _wilson(roc.pd_mc[i, j], trials, z)
            @test lo ≤ roc.pd_analytic[i, j] ≤ hi
        end
    end

    @testset "analytic Pd is monotone increasing in SNR" begin
        for i in eachindex(roc.pfa_grid)
            @test issorted(roc.pd_analytic[i, :])
        end
    end

    @testset "a batch leaves the live RNG stream untouched (HANDOFF §1)" begin
        # Peek the world's stream via independent copies (no consumption); a batch run
        # in between must not change what the next live draw would produce.
        before = rand(copy(scn.world.rng), UInt64, 4)
        run_batch(scn; kind = :roc, pfa_grid = pfas,
                  snr_db_start = 0.0, snr_db_stop = 16.0, snr_db_count = 9,
                  trials = 1_000, outdir = dir, name = "roc_rngcheck")
        after = rand(copy(scn.world.rng), UInt64, 4)
        @test before == after
    end

    @testset "kind other than :roc is rejected" begin
        @test_throws ErrorException run_batch(scn; kind = :doppler, outdir = dir)
    end

    rm(dir; force = true, recursive = true)
end
