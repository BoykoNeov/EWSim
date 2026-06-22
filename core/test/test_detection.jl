# test_detection.jl — analytic Pd vs Monte-Carlo Pd, now with N-pulse non-coherent
# integration and the full Swerling 0–4 set (HANDOFF §8/§13 validation; slice-3 step 1).
#
# The headline check is unchanged: the closed forms must land within sampling error of
# an independent simulation. The band is a deliberately generous 4σ around the MC
# estimate — wide enough to never spuriously fire on chance or an RNG/version shift,
# yet far tighter than the swing any real formula bug (wrong threshold, factor-of-2 in
# SNR, wrong Swerling/integration form, an under-sized series truncation) would produce.
# Three new things slice 3 must pin: (a) the N_p=1 sampler stays byte-identical to
# slice 1 (an absolute golden — `test_determinism` only compares run-to-run, so it
# cannot catch a draw-order regression that corrupts both runs the same way); (b) every
# Swerling's integrated analytic Pd sits in the MC band, INCLUDING a high-N·SNR point
# that exposes a mis-sized truncation cap on the slow/4-DOF series; (c) integration
# actually separates the fast cases from the slow (SW2≠SW1, SW4≠SW3 at N_p>1).

using Random

# Wilson score interval (robust near Pd ≈ 0 and 1), widened to z σ. Returns (lo, hi).
function _wilson(pm, n, z)
    center = (pm + z^2 / (2n)) / (1 + z^2 / n)
    half   = z * sqrt(pm * (1 - pm) / n + z^2 / (4n^2)) / (1 + z^2 / n)
    return center - half, center + half
end

@testset "detection (analytic vs Monte Carlo)" begin

    @testset "threshold ↔ Pfa round-trip" begin
        for pfa in (1e-2, 1e-4, 1e-6, 1e-8)
            th = EWSim.detection_threshold(pfa)
            @test th ≈ -log(pfa)
            @test exp(-th) ≈ pfa                       # noise-only survival is Pfa
        end
        # N_p = 1 must be the bare −ln(Pfa), float-exact (the slice-1/2 path leans on it).
        for pfa in (1e-2, 1e-5, 1e-8)
            @test EWSim.detection_threshold(pfa, 1) === -log(pfa)
        end
        # N_p > 1: the Erlang-survival inverse must invert — survival at Tₕ recovers Pfa.
        for np in (2, 3, 8, 16), pfa in (1e-2, 1e-4, 1e-6)
            th = EWSim.detection_threshold(pfa, np)
            @test EWSim._erlang_surv(th, np) ≈ pfa rtol=1e-6
            @test th > -log(pfa)                        # integrating noise raises the bar
        end
    end

    @testset "limits pin the special-function boundaries" begin
        # SNR = 0 ⇒ Pd = Pfa for EVERY Swerling case, single- and multi-pulse.
        for sw in 0:4, np in (1, 5)
            @test EWSim.pd_analytic(0.0, 1e-6; swerling=sw, n_pulses=np) ≈ 1e-6 rtol=1e-6
        end
        # Pfa = 1 (Tₕ = 0) ⇒ always detect.
        for sw in 0:4, np in (1, 4)
            @test EWSim.pd_analytic(5.0, 1.0; swerling=sw, n_pulses=np) ≈ 1.0 atol=1e-9
        end
        # Monotone increasing in SNR, every case.
        for sw in 0:4, np in (1, 6)
            pds = [EWSim.pd_analytic(EWSim.db2lin(x), 1e-6; swerling=sw, n_pulses=np) for x in -10:2:20]
            @test issorted(pds)
        end
        # Non-coherent integration gain: more pulses ⇒ higher Pd at the same per-pulse SNR.
        for sw in 0:4
            @test EWSim.pd_analytic(EWSim.db2lin(4.0), 1e-6; swerling=sw, n_pulses=10) >
                  EWSim.pd_analytic(EWSim.db2lin(4.0), 1e-6; swerling=sw, n_pulses=1)
        end
    end

    @testset "Swerling 1 matches its closed form exactly" begin
        snr, pfa = 8.0, 1e-5
        @test EWSim.pd_analytic(snr, pfa; swerling=1) ≈ pfa^(1 / (1 + snr))
    end

    @testset "N_p = 1 collapses the new cases onto slice 1" begin
        # Single-pulse: SW1 ≡ SW2 (Rayleigh) and SW3 ≡ SW4 (4-DOF) — fast vs slow only
        # matters once you integrate. Also: explicit n_pulses=1 == the default for 0/1.
        for snr_db in (-2.0, 4.0, 10.0), pfa in (1e-3, 1e-6)
            snr = EWSim.db2lin(snr_db)
            @test EWSim.pd_analytic(snr, pfa; swerling=2, n_pulses=1) ≈
                  EWSim.pd_analytic(snr, pfa; swerling=1, n_pulses=1)
            @test EWSim.pd_analytic(snr, pfa; swerling=4, n_pulses=1) ≈
                  EWSim.pd_analytic(snr, pfa; swerling=3, n_pulses=1)
            @test EWSim.pd_analytic(snr, pfa; swerling=0, n_pulses=1) ==
                  EWSim.pd_analytic(snr, pfa; swerling=0)
            @test EWSim.pd_analytic(snr, pfa; swerling=1, n_pulses=1) ==
                  EWSim.pd_analytic(snr, pfa; swerling=1)
        end
    end

    @testset "N_p = 1 sampler is byte-identical to slice 1 (golden)" begin
        # Captured from the slice-2 `_sample_z` BEFORE the N-pulse generalization. Pins
        # the exact randn draw order/values so the refactor cannot silently desync seeded
        # replay (the N_p=1 path radar.jl runs for every slice-1/2 scenario). `===` is
        # bit-equality on Float64. Order: SW0 draws (nI,nQ); SW1 draws (nI,nQ,sI,sQ).
        g0 = [1.857807367404183, 10.109100628599714, 5.317787067915033,
              6.112724842221791, 8.617174228854312]
        rng = Xoshiro(11111)
        for v in g0
            @test EWSim._sample_z(rng, sqrt(4.0), sqrt(4.0 / 2), 0, 1) === v
        end
        g1 = [11.442229853163663, 1.043312927010234, 2.4472296427405835,
              8.050632622023851, 18.577238342688865]
        rng = Xoshiro(22222)
        for v in g1
            @test EWSim._sample_z(rng, sqrt(9.0), sqrt(9.0 / 2), 1, 1) === v
        end
    end

    @testset "analytic Pd within MC sampling error across SNR grid (slice-1 single pulse)" begin
        pfa, trials, z = 1e-4, 200_000, 4.0      # 4σ band (≈0.005 in Pd at this N)
        rng = Xoshiro(20260620)
        for sw in (0, 1), snr_db in -2.0:2.0:16.0
            snr = EWSim.db2lin(snr_db)
            pa = EWSim.pd_analytic(snr, pfa; swerling=sw)
            pm = EWSim.pd_montecarlo(snr, pfa, rng; swerling=sw, trials=trials)
            lo, hi = _wilson(pm, trials, z)
            @test lo ≤ pa ≤ hi
        end
    end

    @testset "all 5 Swerling: integrated analytic Pd within MC band (N_p = 8)" begin
        # The integration validation AND the truncation-cap guard: at 15 dB, N_p·SNR ≈ 253,
        # so the SW1/SW3 geometric/NB series tail (ρ,μ → 1) is long — a Poisson-sized cap
        # would under-sum Pd by ~0.01 and fall out of the band. The saturation-aware
        # accumulator must land it. SW0/SW2/SW4 ride along on the same grid.
        np, pfa, trials, z = 8, 1e-4, 80_000, 4.0
        rng = Xoshiro(20260622)
        for sw in 0:4, snr_db in (0.0, 6.0, 11.0, 15.0)
            snr = EWSim.db2lin(snr_db)
            pa = EWSim.pd_analytic(snr, pfa; swerling=sw, n_pulses=np)
            pm = EWSim.pd_montecarlo(snr, pfa, rng; swerling=sw, n_pulses=np, trials=trials)
            lo, hi = _wilson(pm, trials, z)
            @test lo ≤ pa ≤ hi
        end
    end

    @testset "integration separates fast from slow (SW2≠SW1, SW4≠SW3 at N_p>1)" begin
        # The whole reason integration is in this slice: decorrelated (fast) fluctuation
        # integrates differently from correlated (slow). Scan the operating curve and
        # require a clear gap SOMEWHERE (direction flips across the curve, so test |Δ|).
        np, pfa = 8, 1e-4
        gap21 = maximum(abs(EWSim.pd_analytic(EWSim.db2lin(x), pfa; swerling=2, n_pulses=np) -
                            EWSim.pd_analytic(EWSim.db2lin(x), pfa; swerling=1, n_pulses=np))
                        for x in -4.0:1.0:14.0)
        gap43 = maximum(abs(EWSim.pd_analytic(EWSim.db2lin(x), pfa; swerling=4, n_pulses=np) -
                            EWSim.pd_analytic(EWSim.db2lin(x), pfa; swerling=3, n_pulses=np))
                        for x in -4.0:1.0:14.0)
        @test gap21 > 0.05
        @test gap43 > 0.05
        # And single-pulse they coincide (already pinned above) — so the separation is the
        # integration, not a model mix-up.
        @test EWSim.pd_analytic(EWSim.db2lin(6.0), pfa; swerling=2, n_pulses=1) ≈
              EWSim.pd_analytic(EWSim.db2lin(6.0), pfa; swerling=1, n_pulses=1)
    end

    @testset "Swerling fluctuation-loss ordering (external anchor for SW3/SW4)" begin
        # SW3/SW4 reduce to nothing slice-1 validated, and `analytic ≈ MC` only proves the
        # derivation matches the *sampler's* model (both share |a|²~Gamma(2,snr/2)) — not
        # that the model is textbook Swerling 3/4. The fluctuation-loss ordering is an
        # EXTERNAL anchor: it brackets SW3 (4-DOF) strictly between the anchored steady
        # (SW0) and Rayleigh (SW1) cases, so a gross DOF/scale slip in the new model would
        # break it where `≈MC` cannot (advisor catch). Steadier targets win at high Pd; the
        # order reverses at low SNR (a fluctuation tail occasionally lifts a weak return
        # over threshold). Same for the fast family SW0/SW4/SW2.
        pd(snr_db, pfa, sw, np) = EWSim.pd_analytic(EWSim.db2lin(snr_db), pfa; swerling=sw, n_pulses=np)

        # high Pd, single pulse: SW0 > SW3 > SW1 strictly — SW3 interior to the two anchors.
        let p = [pd(18.0, 1e-6, sw, 1) for sw in 0:4]
            @test p[1] > p[4] > p[2]                   # SW0 > SW3 > SW1
            @test p[1] - p[2] > 0.1                     # genuine spread, not all-saturated
        end
        # high Pd, integrated (N_p=8): the steady-side ordering survives integration.
        let p = [pd(16.0, 1e-6, sw, 8) for sw in 0:4]
            @test p[1] > p[4] > p[2]                   # SW0 > SW3 > SW1
            @test p[4] - p[2] > 0.03                    # SW3 clearly above SW1
        end
        # low SNR, integrated: the ordering REVERSES for both families — the discriminating
        # check (a wrong-DOF SW3/SW4 would not sit between SW1/SW2 and SW0 here).
        let p = [pd(0.0, 1e-4, sw, 8) for sw in 0:4]
            @test p[2] > p[4] > p[1]                   # SW1 > SW3 > SW0  (slow family)
            @test p[3] > p[5] > p[1]                   # SW2 > SW4 > SW0  (fast family)
            @test p[2] - p[1] > 0.02 && p[3] - p[1] > 0.01   # real separation, not noise
        end
    end

    @testset "out-of-range Swerling / n_pulses are rejected" begin
        @test_throws ArgumentError EWSim.pd_analytic(5.0, 1e-6; swerling=5)
        @test_throws ArgumentError EWSim.pd_analytic(5.0, 1e-6; swerling=-1)
        @test_throws ArgumentError EWSim.pd_analytic(5.0, 1e-6; n_pulses=0)
        @test_throws ArgumentError EWSim.pd_montecarlo(5.0, 1e-6, Xoshiro(1); swerling=7, trials=10)
        @test_throws ArgumentError EWSim.detect_once(5.0, 1.0, Xoshiro(1); n_pulses=0)
    end
end
