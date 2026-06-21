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

const _SCEN_BATCH    = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice1_roc.yaml"))
const _SCEN_COVERAGE = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice2_tworay.yaml"))

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

    @testset "kind other than :roc/:coverage is rejected" begin
        @test_throws ErrorException run_batch(scn; kind = :doppler, outdir = dir)
    end

    rm(dir; force = true, recursive = true)
end

# --- slice-2 coverage diagram (stretch). ---------------------------------------------
#
# A range×altitude SNR grid is deterministic (closed form, no RNG), so unlike the ROC
# there is no MC band — the regression is an exact recompute. But the recompute must be
# INDEPENDENT, and the subtlety the whole slice obsesses over is the slant/ground
# decomposition (link budget on slant, multipath phase + horizon on ground). A hand
# recompute here would just replicate any decomposition mistake. So the oracle is the
# LIVE `_target_snr` (radar.jl) — the actual sandbox path, already pinned by test_radar
# (closed-form geom) and slice2_verify.gd (the 15.10→7.70 dB wire flip). Cross-checking
# `coverage_grid` against it in one loop proves three things at once: the decomposition
# matches, there is no (i,j)→(R_g,h_t) transpose, and the diagram shows what the sandbox
# shows. `coverage_grid` re-derives the masking independently (it does NOT call
# `_target_snr`), so the two are genuine cross-checks, not a tautology.
@testset "batch (coverage diagram)" begin
    dir = mktempdir()
    scn = load_scenario(_SCEN_COVERAGE)            # slice2_tworay: radar1 (30 m mast), tgt1 (rcs 5)

    # Small grid (like ROC's 2×9) so the all-cells oracle loop is trivially fast. Range
    # starts > 0 (snr_freespace/snr_two_ray need slant/ground > 0).
    nr, na = 8, 6
    desc = run_batch(scn; kind = :coverage,
                     range_start = 5_000.0, range_stop = 75_000.0, range_count = nr,
                     alt_start = 0.0, alt_stop = 2_000.0, alt_count = na,
                     outdir = dir, name = "cov_test")

    radar = scn.world.entities[:radar1]
    rp    = EWSim._radar_params(radar.comp)
    h_r   = Float64(radar.pos[3])                  # 30 m mast
    rcs   = Float64(scn.world.entities[:tgt1].comp[:rcs_m2])   # 5.0 m²

    @testset "descriptor + on-disk file agree (HANDOFF §5)" begin
        @test desc[:type]  == "artifact"
        @test desc[:shape] == [nr, na, 2]
        @test desc[:dtype] == "f64"
        @test desc[:axes][3] == "[free_space_db, two_ray_db]"
        @test desc[:rcs_m2] == rcs
        @test desc[:h_r]    == h_r
        @test desc[:refl]   == -1.0
        @test length(desc[:range_grid]) == nr
        @test length(desc[:alt_grid])   == na
        binpath = desc[:path]
        @test isfile(binpath)
        @test filesize(binpath) == prod(desc[:shape]) * sizeof(Float64)
        @test isfile(EWSim._meta_of(binpath))
    end

    cov = load_coverage(desc[:path])

    @testset "load_coverage round-trips the grid + dims" begin
        @test size(cov.free_space_db) == (nr, na)
        @test size(cov.two_ray_db)    == (nr, na)
        @test cov.range_grid == desc[:range_grid]
        @test cov.alt_grid   == desc[:alt_grid]
        @test cov.rcs_m2 == rcs
        @test cov.h_r    == h_r
    end

    @testset "both planes == live _target_snr oracle (decomposition + no transpose)" begin
        for (i, R_g) in enumerate(cov.range_grid), (j, h_t) in enumerate(cov.alt_grid)
            radar_e = Entity(:r, :radar; pos = Vec3(0.0, 0.0, h_r))
            tgt_e   = Entity(:t, :target; pos = Vec3(R_g, 0.0, h_t),
                             comp = Dict{Symbol,Any}(:rcs_m2 => rcs))
            fs_lin, _ = EWSim._target_snr(:free_space, rp, radar_e, tgt_e)
            tr_lin, _ = EWSim._target_snr(:two_ray,   rp, radar_e, tgt_e)
            @test cov.free_space_db[i, j] ≈ EWSim._snr_db_wire(fs_lin) rtol = 1e-12
            @test cov.two_ray_db[i, j]    ≈ EWSim._snr_db_wire(tr_lin) rtol = 1e-12
        end
    end

    @testset "artifact carries no Inf/NaN (the slice-2 wire watch-item)" begin
        @test all(isfinite, cov.free_space_db)
        @test all(isfinite, cov.two_ray_db)
    end

    @testset "below-horizon corner masked to the floor — the MODEL, not the geometry" begin
        # Lowest altitude (h_t=0 → horizon_range(30,0) ≈ 22.6 km), farthest range (75 km):
        # ground range is beyond the 4/3-Earth horizon, so two_ray masks to the floor. The
        # free_space plane (no ground, infinite LOS) stays finite & above the floor at the
        # SAME cell — the mask is the propagation MODEL, not the geometry (slice2_verify.gd).
        @test cov.two_ray_db[end, 1]    == EWSim._SNR_DB_FLOOR
        @test isfinite(cov.free_space_db[end, 1])
        @test cov.free_space_db[end, 1] > EWSim._SNR_DB_FLOOR
    end

    @testset "the grid is not degenerate (some two_ray cells well above the floor)" begin
        # A coarse grid can land cells on nulls, so don't pin a single cell; just assert
        # the lobed plane has real signal somewhere (rules out an all-floored bug).
        @test any(cov.two_ray_db .> EWSim._SNR_DB_FLOOR)
    end

    @testset "a coverage run leaves the live RNG stream untouched (no RNG at all)" begin
        before = rand(copy(scn.world.rng), UInt64, 4)
        run_batch(scn; kind = :coverage, range_start = 5_000.0, range_stop = 75_000.0,
                  range_count = 4, alt_start = 0.0, alt_stop = 1_000.0, alt_count = 4,
                  outdir = dir, name = "cov_rngcheck")
        after = rand(copy(scn.world.rng), UInt64, 4)
        @test before == after
    end

    @testset "rcs_m2 defaults to the sole target but an explicit override is honored" begin
        @test desc[:rcs_m2] == rcs                 # the default path (used above)
        d2 = run_batch(scn; kind = :coverage, rcs_m2 = 12.5,
                       range_start = 5_000.0, range_stop = 75_000.0, range_count = 4,
                       alt_start = 0.0, alt_stop = 1_000.0, alt_count = 4,
                       outdir = dir, name = "cov_rcs")
        @test d2[:rcs_m2] == 12.5
    end

    rm(dir; force = true, recursive = true)
end
