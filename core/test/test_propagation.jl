# test_propagation.jl — flat-earth two-ray multipath + 4/3-Earth horizon vs their
# closed forms (HANDOFF §8 validation; slice 2 step 1).
#
# two_ray is *deterministic*, so unlike the detector (analytic-vs-MC bands) every
# check here is an exact closed form: the lobe peak (+12.04 dB), the null (→0), the
# small-grazing R⁸ envelope (−24.08 dB/octave), the ρ=0 ≡ free-space identity, and
# the horizon distance. Each test moves one knob and pins one fact.

@testset "two-ray propagation" begin
    # λ = 0.03 m exactly, so the phase geometry has no rounding to argue about.
    rp = EWSim.RadarParams(
        1000.0,                  # pt_w
        30.0,                    # gain_db
        EWSim.C_LIGHT / 0.03,    # freq_hz   → λ = 0.03 m
        1.0e6,                   # bandwidth_hz
        0.0, 0.0,                # noise_fig_db, losses_db
    )
    λ = 0.03
    σ = 1.0
    h_r, h_t = 10.0, 30.0        # h_r·h_t = 300

    # Δφ = 4π·h_r·h_t/(λ·R_g) = 4π·300/(0.03·R_g) = 4π·10000/R_g.
    #   R_g = 40_000 → Δφ = π   (lobe peak: sin(Δφ/2)=1 → F⁴=16)
    #   R_g = 20_000 → Δφ = 2π  (null:      sin(Δφ/2)=0 → F⁴=0)
    Rpeak = 40_000.0
    Rnull = 20_000.0

    @testset "phase formula (independent recompute)" begin
        @test EWSim.two_ray_phase(λ, h_r, h_t, Rpeak) ≈ π   rtol=1e-12
        @test EWSim.two_ray_phase(λ, h_r, h_t, Rnull) ≈ 2π  rtol=1e-12
    end

    @testset "lobe peak: F⁴ = 16 ⇒ +12.04 dB over free space" begin
        # ratio is exactly F⁴ when both SNRs use the same slant range.
        s_fs = EWSim.snr_freespace(rp, σ, Rpeak)
        s_tr = EWSim.snr_two_ray(rp, σ, Rpeak; h_r=h_r, h_t=h_t, ground_m=Rpeak)
        @test s_tr / s_fs ≈ 16.0 rtol=1e-12
        @test EWSim.lin2db(s_tr / s_fs) ≈ 40*log10(2) atol=1e-9   # 12.0412 dB
    end

    @testset "null: rays cancel ⇒ F⁴ → 0" begin
        # `≈ 0` with only rtol always fails (rtol·0 = 0); pin with atol.
        s_tr = EWSim.snr_two_ray(rp, σ, Rnull; h_r=h_r, h_t=h_t, ground_m=Rnull)
        s_fs = EWSim.snr_freespace(rp, σ, Rnull)
        @test s_tr ≈ 0.0 atol = 1e-12 * s_fs                     # ~60 dB below free space
        @test EWSim.two_ray_factor4(2π) ≈ 0.0 atol=1e-20
    end

    @testset "small-grazing envelope: SNR ∝ R⁻⁸ (−24.08 dB / octave)" begin
        # Far field: Δφ = 4π·10000/1e7 ≈ 0.0126 rad ≪ 1, so sin(Δφ/2)≈Δφ/2 and
        # F⁴ ∝ R_g⁻⁴; with snr_fs ∝ R⁻⁴ the envelope falls as R⁻⁸. Double both the
        # slant and the ground range (heights fixed) and the drop is 80·log10(2).
        Rg = 1.0e7
        slant1 = hypot(Rg, h_t - h_r)
        slant2 = hypot(2Rg, h_t - h_r)
        s1 = EWSim.snr_two_ray(rp, σ, slant1; h_r=h_r, h_t=h_t, ground_m=Rg)
        s2 = EWSim.snr_two_ray(rp, σ, slant2; h_r=h_r, h_t=h_t, ground_m=2Rg)
        @test EWSim.lin2db(s1 / s2) ≈ 80*log10(2) atol=0.01      # 24.0824 dB
    end

    @testset "budget uses slant range, phase uses ground range (not swappable)" begin
        # Every other test has slant ≈ ground, so a swap of the two arguments would
        # pass silently. A high-grazing geometry (slant clearly ≠ ground) pins the
        # decomposition SNR_two_ray = snr_freespace(slant)·F⁴(Δφ from ground).
        h_t2, gnd = 1000.0, 2000.0
        slant = hypot(gnd, h_t2 - h_r)                           # 2231.6 m ≠ 2000 m
        Δφ = EWSim.two_ray_phase(λ, h_r, h_t2, gnd)
        @test EWSim.snr_two_ray(rp, σ, slant; h_r=h_r, h_t=h_t2, ground_m=gnd) ≈
              EWSim.snr_freespace(rp, σ, slant) * EWSim.two_ray_factor4(Δφ) rtol=1e-12
    end

    @testset "ρ = 0 recovers free space exactly (no ground)" begin
        for R in (Rpeak, Rnull, 1.0e5)
            @test EWSim.snr_two_ray(rp, σ, R; h_r=h_r, h_t=h_t, ground_m=R, refl=0.0) ==
                  EWSim.snr_freespace(rp, σ, R)
        end
        @test EWSim.two_ray_factor4(1.234; refl=0.0) == 1.0
    end

    @testset "h → 0 degeneracy: antenna on the plane ⇒ perpetual null" begin
        # F⁴ = (1 + ρ² + 2ρ·cos 0)² = (2 − 2)² = 0 for ρ = −1. Pinned, not thrown:
        # a fly-by may cross z = 0 and must not crash the live sim.
        @test EWSim.snr_two_ray(rp, σ, Rpeak; h_r=0.0, h_t=h_t, ground_m=Rpeak) == 0.0
        @test EWSim.snr_two_ray(rp, σ, Rpeak; h_r=h_r, h_t=0.0, ground_m=Rpeak) == 0.0
    end

    @testset "4/3-Earth horizon distance" begin
        # Coefficient √(2·k·R_e) recomputed at full precision (≈4121.8, NOT 4122).
        coeff = sqrt(2 * (4/3) * 6.371e6)
        @test EWSim.horizon_range(h_r, h_t) ≈ coeff * (sqrt(h_r) + sqrt(h_t)) rtol=1e-12
        @test EWSim.horizon_range(h_r, h_t) ≈ 4122.0 * (sqrt(h_r) + sqrt(h_t)) rtol=1e-3

        # Additivity in √h: each antenna's contribution adds independently.
        @test EWSim.horizon_range(h_r, 0.0) + EWSim.horizon_range(0.0, h_t) ≈
              EWSim.horizon_range(h_r, h_t) rtol=1e-12

        # A concrete geometry that is below the horizon (the masking the radar gates
        # on in step 2): radar at 10 m, target at 30 m → horizon ≈ 35.6 km.
        d_h = EWSim.horizon_range(h_r, h_t)
        @test 35_000 < d_h < 36_000
        @test 100_000.0 > d_h                                    # 100 km target is masked
    end

    @testset "guards: ground range must be > 0 (only Inf/NaN input)" begin
        @test_throws DomainError EWSim.snr_two_ray(rp, σ, Rpeak; h_r=h_r, h_t=h_t, ground_m=0.0)
        @test_throws DomainError EWSim.snr_two_ray(rp, σ, Rpeak; h_r=h_r, h_t=h_t, ground_m=-1.0)
    end
end
