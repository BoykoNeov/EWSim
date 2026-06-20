# test_detection.jl — analytic Pd vs Monte-Carlo Pd (HANDOFF §8 validation test).
#
# The headline check is the analytic-vs-MC agreement: the closed forms must land
# within sampling error of an independent simulation across the SNR grid. This is a
# regression guard, not the convergence *demo* (that is the Pluto notebook, step 6),
# so the band is a deliberately generous 4σ around the MC estimate — wide enough to
# never spuriously fire on chance or an RNG/version shift, yet far tighter than the
# 0.1–0.5 Pd swing any real formula bug (wrong threshold, factor-of-2 in SNR, wrong
# Swerling form) would produce. The seed is fixed so a failure is reproducible.

using Random

@testset "detection (analytic vs Monte Carlo)" begin

    @testset "threshold ↔ Pfa round-trip" begin
        for pfa in (1e-2, 1e-4, 1e-6, 1e-8)
            th = EWSim.detection_threshold(pfa)
            @test th ≈ -log(pfa)
            @test exp(-th) ≈ pfa                       # noise-only survival is Pfa
        end
    end

    @testset "limits pin the special-function boundaries" begin
        # SNR = 0 ⇒ Pd = Pfa for both cases  (Q₁(0,b) = e^(−b²/2); Exp(1) survival)
        for sw in (0, 1)
            @test EWSim.pd_analytic(0.0, 1e-6; swerling=sw) ≈ 1e-6 rtol=1e-9
        end
        # Pfa = 1 (Tₕ = 0) ⇒ always detect  (Q₁(a,0) = 1)
        @test EWSim.pd_analytic(5.0, 1.0; swerling=0) ≈ 1.0 atol=1e-12
        @test EWSim.pd_analytic(5.0, 1.0; swerling=1) ≈ 1.0 atol=1e-12
        # Monotone increasing in SNR
        pds = [EWSim.pd_analytic(EWSim.db2lin(x), 1e-6; swerling=1) for x in -10:2:20]
        @test issorted(pds)
    end

    @testset "Swerling 1 matches its closed form exactly" begin
        snr, pfa = 8.0, 1e-5
        @test EWSim.pd_analytic(snr, pfa; swerling=1) ≈ pfa^(1 / (1 + snr))
    end

    @testset "analytic Pd within MC sampling error across SNR grid" begin
        pfa, trials, z = 1e-4, 200_000, 4.0      # 4σ band (≈0.005 in Pd at this N)
        rng = Xoshiro(20260620)
        for sw in (0, 1), snr_db in -2.0:2.0:16.0
            snr = EWSim.db2lin(snr_db)
            pa = EWSim.pd_analytic(snr, pfa; swerling=sw)
            pm = EWSim.pd_montecarlo(snr, pfa, rng; swerling=sw, trials=trials)
            # Wilson score interval (robust near Pd ≈ 0) widened to z = 4.
            n = trials
            center = (pm + z^2 / (2n)) / (1 + z^2 / n)
            half   = z * sqrt(pm * (1 - pm) / n + z^2 / (4n^2)) / (1 + z^2 / n)
            @test center - half ≤ pa ≤ center + half
        end
    end

    @testset "unimplemented Swerling cases are rejected" begin
        @test_throws ArgumentError EWSim.pd_analytic(5.0, 1e-6; swerling=3)
        @test_throws ArgumentError EWSim.pd_montecarlo(5.0, 1e-6, Xoshiro(1); swerling=2, trials=10)
    end
end
