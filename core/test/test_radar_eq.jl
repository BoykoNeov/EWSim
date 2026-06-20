# test_radar_eq.jl — free-space radar equation vs an independent hand calc, plus
# the scaling laws that isolate each exponent (HANDOFF §8 validation tests).
#
# The absolute check is computed in the dB domain — a separate derivation from the
# linear implementation, so a transcription slip in one path doesn't hide in the
# other. The scaling tests each move one input and pin one exponent (R⁴, G², …),
# which catches a wrong power even if the absolute constant happened to agree.

@testset "radar equation" begin
    # λ = 0.03 m exactly (so the hand calc has no rounding to argue about).
    rp = EWSim.RadarParams(
        1000.0,                  # pt_w
        30.0,                    # gain_db   → G  = 1e3
        EWSim.C_LIGHT / 0.03,    # freq_hz   → λ  = 0.03 m
        1.0e6,                   # bandwidth_hz
        0.0,                     # noise_fig_db → F = 1
        0.0,                     # losses_db    → L = 1
    )
    σ = 1.0
    R = 1.0e4

    @testset "absolute value vs dB-domain hand calc" begin
        λ = 0.03
        snr_db_expected =
            10*log10(1000.0) +               # Pt
            2*30.0 +                          # G²  (one-way gain, used Tx and Rx)
            20*log10(λ) +                     # λ²
            10*log10(σ) -                     # σ
            30*log10(4π) -                    # (4π)³
            40*log10(R) -                     # R⁴
            10*log10(EWSim.K_BOLTZMANN) -
            10*log10(EWSim.T0_REF) -
            10*log10(1.0e6)                   # B   (F, L are 0 dB here)
        @test EWSim.snr_db_freespace(rp, σ, R) ≈ snr_db_expected rtol=1e-12
    end

    base = EWSim.snr_freespace(rp, σ, R)

    @testset "R⁴ scaling: 2× range ⇒ −12.04 dB" begin
        s2 = EWSim.snr_freespace(rp, σ, 2R)
        @test EWSim.lin2db(base / s2) ≈ 40*log10(2) atol=1e-9      # 12.0412 dB
        @test s2 ≈ base / 16                                       # exact R⁴
    end

    @testset "linear in Pt and σ, inverse in B" begin
        rpP = EWSim.RadarParams(2rp.pt_w, rp.gain_db, rp.freq_hz, rp.bandwidth_hz, rp.noise_fig_db, rp.losses_db)
        rpB = EWSim.RadarParams(rp.pt_w, rp.gain_db, rp.freq_hz, 2rp.bandwidth_hz, rp.noise_fig_db, rp.losses_db)
        @test EWSim.snr_freespace(rpP, σ, R) ≈ 2base               # ∝ Pt
        @test EWSim.snr_freespace(rp, 2σ, R) ≈ 2base               # ∝ σ
        @test EWSim.snr_freespace(rpB, σ, R) ≈ base / 2            # ∝ 1/B (noise ∝ B)
    end

    @testset "G² scaling: +3 dB of gain ⇒ +6 dB of SNR" begin
        rpG = EWSim.RadarParams(rp.pt_w, rp.gain_db + 3.0, rp.freq_hz, rp.bandwidth_hz, rp.noise_fig_db, rp.losses_db)
        @test EWSim.snr_db_freespace(rpG, σ, R) - EWSim.snr_db_freespace(rp, σ, R) ≈ 6.0 atol=1e-9
    end

    @testset "noise figure and losses subtract in dB" begin
        rpFL = EWSim.RadarParams(rp.pt_w, rp.gain_db, rp.freq_hz, rp.bandwidth_hz, 3.0, 4.0)
        @test EWSim.snr_db_freespace(rp, σ, R) - EWSim.snr_db_freespace(rpFL, σ, R) ≈ 7.0 atol=1e-9
    end

    @testset "guards" begin
        @test_throws DomainError EWSim.snr_freespace(rp, σ, 0.0)
        @test_throws DomainError EWSim.snr_freespace(rp, σ, -1.0)
    end
end
