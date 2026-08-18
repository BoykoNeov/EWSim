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

# --- slice 46: THE APERTURE AND THE HORIZON ---------------------------------------------------
#
# Teeth, not tautologies (convention 11): the horizon is checked by feeding the returned range BACK
# into `snr_db_freespace` — an INDEPENDENT recompute along the forward path, so a slip in either
# direction shows up as a threshold that is not the threshold. The scaling tests each move ONE input
# and pin ONE exponent (the ¼ power the R⁴ law leaves behind), which catches a wrong power even when
# the absolute value happens to agree. And the `R_acq·θ` invariance is the composed identity slice
# 44's gate 0 measured on the flying wire (0.0000 % over 4×, log-log slope −1.000000) — the same
# number, here against the kernels rather than against a flight.
@testset "aperture + detection horizon (slice 46)" begin
    rp = EWSim.RadarParams(
        1000.0,                  # pt_w
        30.0,                    # gain_db   → G  = 1e3
        EWSim.C_LIGHT / 0.03,    # freq_hz   → λ  = 0.03 m
        1.0e6,                   # bandwidth_hz
        0.0,                     # noise_fig_db
        0.0,                     # losses_db
    )
    σ = 1.0

    @testset "the horizon is where the SNR crosses the threshold" begin
        for snr_min_db in (0.0, 6.0, 10.0, 13.5, 20.0)
            R = EWSim.detection_range(rp, σ; snr_min_db = snr_min_db)
            # THE TOOTH: walk the forward model to the returned range and read what it gives.
            @test EWSim.snr_db_freespace(rp, σ, R) ≈ snr_min_db atol = 1e-12
            # …and the gate it implies is a real inequality on both sides of it.
            @test EWSim.snr_db_freespace(rp, σ, 0.99R) > snr_min_db
            @test EWSim.snr_db_freespace(rp, σ, 1.01R) < snr_min_db
        end
    end

    @testset "the ¼ power: 16× the budget buys 2× the range" begin
        R = EWSim.detection_range(rp, σ)
        rp16 = EWSim.RadarParams(16 * rp.pt_w, rp.gain_db, rp.freq_hz,
                                 rp.bandwidth_hz, rp.noise_fig_db, rp.losses_db)
        @test EWSim.detection_range(rp16, σ) ≈ 2R                    # Pt: 16× ⇒ 2×
        @test EWSim.detection_range(rp, 16σ) ≈ 2R                    # σ:  16× ⇒ 2×
        # Bandwidth is NOISE, so it runs the other way: 16× the bandwidth is half the range. This is
        # the integration-time lever wearing its reciprocal (`B = 1/T_int`) — the reason a seeker
        # buys reach with a longer look rather than a bigger transmitter.
        rpB = EWSim.RadarParams(rp.pt_w, rp.gain_db, rp.freq_hz,
                                16 * rp.bandwidth_hz, rp.noise_fig_db, rp.losses_db)
        @test EWSim.detection_range(rpB, σ) ≈ R / 2
        # +6 dB of ANTENNA gain is +12 dB of SNR is 2× range (the gain enters twice, Tx and Rx).
        rpG = EWSim.RadarParams(rp.pt_w, rp.gain_db + 6.0206, rp.freq_hz,
                                rp.bandwidth_hz, rp.noise_fig_db, rp.losses_db)
        @test EWSim.detection_range(rpG, σ) ≈ 2R rtol = 1e-5
        # Noise figure and losses subtract from the budget: +12.04 dB of loss is HALF the range.
        rpL = EWSim.RadarParams(rp.pt_w, rp.gain_db, rp.freq_hz,
                                rp.bandwidth_hz, 6.0206, 6.0206)
        @test EWSim.detection_range(rpL, σ) ≈ R / 2 rtol = 1e-5
        # THE TRIPWIRE (the slice-19 discipline): every field of the chain MOVES the horizon. A
        # parameter that leaves this number untouched is a dead knob, and this is where it is caught.
        @test EWSim.detection_range(rp16, σ) != R
        @test EWSim.detection_range(rpB,  σ) != R
        @test EWSim.detection_range(rpG,  σ) != R
        @test EWSim.detection_range(rpL,  σ) != R
    end

    @testset "the aperture identity, against a hand-computed solid angle" begin
        θ = deg2rad(4.0)                                  # a 4° FULL beamwidth
        @test EWSim.aperture_gain(θ; eta = 0.6) ≈ 0.6 * 4π / θ^2
        # η is linear in the gain, and the default is the conventional 0.6.
        @test EWSim.aperture_gain(θ; eta = 0.3) ≈ EWSim.aperture_gain(θ; eta = 0.6) / 2
        @test EWSim.aperture_gain(θ) == EWSim.aperture_gain(θ; eta = 0.6)
        # ⚠ THE HALF-ANGLE TRAP, PINNED: a detector window quoted off-axis is a HALF-angle, and
        # handing it in unconverted is a 4× (6 dB) gain error. Nothing warns you; this does.
        fov_half = deg2rad(2.0)
        @test EWSim.aperture_gain(2 * fov_half) ≈ EWSim.aperture_gain(fov_half) / 4
        # An EXTERNAL anchor for the aperture: 16 GHz is λ = 18.74 mm, and a 2° beam off that dish
        # needs 1.02λ/θ = 0.537 m of it — a number an antenna handbook agrees with, not a restatement.
        @test EWSim.wavelength(16.0e9) ≈ 0.018737 atol = 1e-6
        @test EWSim.aperture_diameter(16.0e9, deg2rad(2.0)) ≈ 0.5476 atol = 5e-4
        @test EWSim.aperture_diameter(16.0e9, deg2rad(4.0)) ≈
              EWSim.aperture_diameter(16.0e9, deg2rad(2.0)) / 2          # D ∝ 1/θ
    end

    @testset "⭐ R_acq · fov is CONSTANT — coverage and reach are one variable" begin
        # THE COMPOSED IDENTITY. R ∝ (G²)^¼ = G^½ and G ∝ 1/θ², so R ∝ 1/θ: buy 2× the window and
        # you have sold half your range, exactly. This is slice 44's flown measurement (0.0000 % over
        # a 4× fov range, log-log slope −1.000000) reproduced against the kernels.
        seeker(fov_deg) = EWSim.RadarParams(
            200.0, EWSim.lin2db(EWSim.aperture_gain(2 * deg2rad(fov_deg); eta = 0.6)),
            16.0e9, 1 / 0.010, 4.0, 5.0)
        fovs = (3.0, 6.0, 12.0)
        Rs   = [EWSim.detection_range(seeker(f), 1.0; snr_min_db = 10.0) for f in fovs]
        prod = [R * f for (R, f) in zip(Rs, fovs)]
        @test all(p -> isapprox(p, prod[1]; rtol = 1e-12), prod)        # 0.0000 %, over 4×
        # …and the same statement as a SLOPE, which is how the flight measured it.
        slope = (log(Rs[3]) - log(Rs[1])) / (log(fovs[3]) - log(fovs[1]))
        @test slope ≈ -1.0 atol = 1e-12
        # The authored Ku-band seeker of slice 44's gate 0, at the window this arc actually flies:
        # 8079 m against a 6437 m launch — the missile starts INSIDE its own seeker's horizon, which
        # is why the gate is inert on THIS engagement and why midcourse is its own slice.
        @test EWSim.detection_range(seeker(10.0), 1.0; snr_min_db = 10.0) ≈ 8079.0 rtol = 5e-4
    end

    @testset "guards" begin
        @test_throws DomainError EWSim.aperture_gain(0.0)
        @test_throws DomainError EWSim.aperture_gain(-0.1)
        @test_throws DomainError EWSim.aperture_gain(0.1; eta = 0.0)
        @test_throws DomainError EWSim.aperture_diameter(16.0e9, 0.0)
        @test_throws DomainError EWSim.detection_range(rp, 0.0)
        @test_throws DomainError EWSim.detection_range(rp, -1.0)
    end
end
