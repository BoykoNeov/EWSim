# test_cfar.jl — CFAR adaptive thresholding (slice-3 step 2; gate 2 in docs/plans/slice3.md).
#
# The discipline is the same analytic-vs-Monte-Carlo pattern the rest of detection.jl
# uses, applied to the four CFAR variants (CA/GO/SO/OS):
#   • The CLOSED FORMS are pinned against an independent recompute (CA `N(Pfa^(−1/N)−1)`,
#     OS `∏(N−i)/(N−i+α)`) and self-consistency round-trips (`α → Pfa(α) ≈ pfa`). The
#     `N→∞` CA limit anchors the CFAR loss vanishing to the fixed `−ln(Pfa)` threshold.
#   • The ORDERING INVARIANT `Pfa_GO ≤ Pfa_CA ≤ Pfa_SO` is checked at a COMMON α (not
#     per-variant-calibrated — that would be equal by construction and pass for the wrong
#     reason, the slice-2 "explicit atol not rtol≈0" trap). It catches a swapped GO/SO.
#   • The SO/GO forward forms and the INTEGRATED (N_p>1) CA Beta form have no clean
#     analytic anchor here, so they are validated by MC PFA-MAINTENANCE: draw noise-only
#     window-sized profiles and confirm the calibrated α holds the design Pfa in the
#     homogeneous interior. A wrong α (wrong SO/GO/Beta derivation) shifts the false-alarm
#     rate out of the Wilson band. All closed-form asserts are at N_p=1 (exponential
#     cells); N_p>1 (Gamma cells) is CA-only and MC-only — Gamma-cell ≠ exponential-cell.
#   • Edge cells: a scan must produce a finite, positive threshold at EVERY cell (the
#     array ends included) and never index out of bounds.

using Random

# Wilson score interval widened to z σ (same helper as test_detection).
_wilson_cfar(pm, n, z) = ( (pm + z^2/(2n))/(1 + z^2/n) - z*sqrt(pm*(1-pm)/n + z^2/(4n^2))/(1 + z^2/n),
                           (pm + z^2/(2n))/(1 + z^2/n) + z*sqrt(pm*(1-pm)/n + z^2/(4n^2))/(1 + z^2/n) )

# One Gamma(N_p, 1) cell = sum of N_p unit exponentials (noise-only integrated power).
_gamma_cell(rng, np) = (s = 0.0; for _ in 1:np; s += randexp(rng); end; s)

@testset "CFAR (analytic closed forms vs Monte-Carlo Pfa-maintenance)" begin

    @testset "CA: closed-form α, round-trip, and the N→∞ CFAR-loss anchor" begin
        for N in (8, 16, 32, 64), pfa in (1e-2, 1e-4, 1e-6)
            α = EWSim.cfar_alpha(:ca, N, pfa)
            @test α ≈ N * (pfa^(-1 / N) - 1)                 # the exact closed form
            @test EWSim._cfar_pfa(:ca, α, N) ≈ pfa rtol = 1e-9   # forward round-trip
            @test α > -log(pfa)                              # CFAR loss is positive (finite N)
        end
        # N → ∞: the cell-averaged estimate sharpens to the true noise mean, so α relaxes
        # MONOTONICALLY down to the fixed-threshold −ln(Pfa) (the CFAR-loss anchor).
        for pfa in (1e-3, 1e-6)
            a8, a64, a512, a4096 = (EWSim.cfar_alpha(:ca, N, pfa) for N in (8, 64, 512, 4096))
            @test a8 > a64 > a512 > a4096 > -log(pfa)
            @test a4096 ≈ -log(pfa) rtol = 5e-3              # essentially converged
        end
    end

    @testset "OS: Rohling product form, round-trip, and the k=1 closed value" begin
        # Forward Pfa matches an independent recompute of ∏_{i=0}^{k−1}(N−i)/(N−i+α).
        for N in (16, 24), k in (8, 12, 18), α in (3.0, 12.0, 40.0)
            k > N && continue
            ref = prod((N - i) / (N - i + α) for i in 0:(k - 1))
            @test EWSim._cfar_pfa(:os, α, N; k = k) ≈ ref rtol = 1e-12
        end
        # Inverse round-trips, and k=1 has the closed value N/(N+α)=pfa ⇒ α=N(1/pfa−1).
        for N in (16, 24), pfa in (1e-2, 1e-4)
            for k in (1, 8, round(Int, 0.75N))
                α = EWSim.cfar_alpha(:os, N, pfa; k = k)
                @test EWSim._cfar_pfa(:os, α, N; k = k) ≈ pfa rtol = 1e-6
            end
            @test EWSim.cfar_alpha(:os, N, pfa; k = 1) ≈ N * (1 / pfa - 1) rtol = 1e-6
        end
    end

    @testset "SO/GO: round-trip and the M=1 (N=2) hand value" begin
        for N in (8, 16, 32), pfa in (1e-2, 1e-4)
            for v in (:so, :go)
                α = EWSim.cfar_alpha(v, N, pfa)
                @test EWSim._cfar_pfa(v, α, N) ≈ pfa rtol = 1e-6
            end
        end
        # N=2 ⇒ M=1: each half is a single Exp(1) cell, min(g1,g2)~Exp(2), so
        # Pfa_SO = E[e^{−α·min}] = 2/(2+α); GO = 2(1+α)^(−1) − Pfa_SO.
        for α in (1.0, 5.0, 20.0)
            @test EWSim._cfar_pfa(:so, α, 2) ≈ 2 / (2 + α) rtol = 1e-12
            @test EWSim._cfar_pfa(:go, α, 2) ≈ 2 / (1 + α) - 2 / (2 + α) rtol = 1e-12
        end
    end

    @testset "ordering invariant at a COMMON α: Pfa_GO ≤ Pfa_CA ≤ Pfa_SO" begin
        # GO (greatest-of) over-estimates the floor → fewer false alarms; SO (smallest-of)
        # under-estimates → more. CA sits between. Deliberately at a SHARED α so the
        # inequality is a real model property, not equal-by-calibration.
        for N in (8, 16, 32), α in (2.0, 6.0, 15.0, 40.0)
            pgo = EWSim._cfar_pfa(:go, α, N)
            pca = EWSim._cfar_pfa(:ca, α, N)
            pso = EWSim._cfar_pfa(:so, α, N)
            @test pgo ≤ pca ≤ pso
            @test pso > pgo                                  # genuine spread (not all equal)
        end
    end

    @testset "MC Pfa-maintenance: calibrated α holds design Pfa in the interior" begin
        # The combined-path check (slice-3 plan). For each variant draw window-sized
        # noise-only profiles, compute the threshold at the centre cell (a full window),
        # and confirm the false-alarm fraction sits in the design-Pfa Wilson band. This
        # is what validates the SO/GO forward forms and the integrated CA Beta form —
        # a wrong α moves the rate out of the band. α is hoisted (it's independent of the
        # random draw); the public `cfar_threshold` is shown to match it separately below.
        N, ng, pfa, T, z = 16, 2, 1e-2, 200_000, 4.0
        nh  = N ÷ 2
        L   = 2 * (ng + nh) + 1                              # exactly one full window
        cut = ng + nh + 1
        cases = [(:ca, 1), (:ca, 5), (:go, 1), (:so, 1), (:os, 1)]   # GO/SO/OS: N_p=1 only
        for (ci, (v, np)) in enumerate(cases)
            kk  = EWSim._os_default_k(N)
            α   = EWSim.cfar_alpha(v, N, pfa; n_pulses = np, k = kk)
            buf = v === :os ? Vector{Float64}(undef, N) : Float64[]
            prof = Vector{Float64}(undef, L)
            rng  = Xoshiro(0xC7A0 + ci)                      # a distinct stream per case (by index)
            hits = 0
            for _ in 1:T
                @inbounds for c in 1:L
                    prof[c] = _gamma_cell(rng, np)
                end
                est = EWSim._cfar_estimate(prof, cut, v, nh, ng, kk, buf)
                prof[cut] > α * est && (hits += 1)
            end
            pm = hits / T
            lo, hi = _wilson_cfar(pm, T, z)
            @test lo ≤ pfa ≤ hi
        end

        # The public `cfar_threshold` uses the SAME α and estimator (no re-spelling): on a
        # fixed profile it equals the hoisted α·estimate. Pins the convention end-to-end.
        prof = collect(range(0.5, 3.0; length = L))
        for v in (:ca, :go, :so, :os)
            kk  = EWSim._os_default_k(N)
            α   = EWSim.cfar_alpha(v, N, pfa; k = kk)
            buf = v === :os ? Vector{Float64}(undef, N) : Float64[]
            est = EWSim._cfar_estimate(prof, cut, v, nh, ng, kk, buf)
            @test EWSim.cfar_threshold(prof, cut; variant = v, n_train = N, n_guard = ng, pfa = pfa) ≈ α * est
        end
    end

    @testset "scan: edge cells finite & positive, no out-of-bounds, detections track" begin
        rng = Xoshiro(20260622)
        L = 300
        profile = [_gamma_cell(rng, 1) for _ in 1:L]
        profile[150] = 50.0                                  # a planted strong target cell
        for v in (:fixed, :ca, :go, :so, :os)
            th, det = EWSim.cfar_scan(profile; variant = v, n_train = 16, n_guard = 2, pfa = 1e-3)
            @test length(th) == L
            @test length(det) == L
            @test all(isfinite, th)                          # never -Inf/NaN
            @test all(>(0.0), th)                            # positive linear-power threshold
            @test isfinite(th[1]) && th[1] > 0               # the array ENDS explicitly
            @test isfinite(th[L]) && th[L] > 0
            @test det == (profile .> th)                     # detections are the comparison
            @test det[150]                                   # the strong cell crosses
        end
        # :fixed is a flat threshold == the non-adaptive detection_threshold.
        thf, _ = EWSim.cfar_scan(profile; variant = :fixed, n_train = 16, n_guard = 2, pfa = 1e-3)
        @test all(==(EWSim.detection_threshold(1e-3, 1)), thf)
        # A profile SHORTER than the window still scans (global-mean fallback, no OOB).
        short = [_gamma_cell(rng, 1) for _ in 1:5]
        for v in (:ca, :go, :so, :os)
            th, _ = EWSim.cfar_scan(short; variant = v, n_train = 16, n_guard = 2, pfa = 1e-2)
            @test length(th) == 5 && all(isfinite, th) && all(>(0.0), th)
        end
    end

    @testset "invalid arguments are rejected" begin
        @test_throws ArgumentError EWSim.cfar_alpha(:go, 16, 1e-3; n_pulses = 2)   # GO/SO/OS N_p=1 only
        @test_throws ArgumentError EWSim.cfar_alpha(:so, 16, 1e-3; n_pulses = 4)
        @test_throws ArgumentError EWSim.cfar_alpha(:os, 16, 1e-3; n_pulses = 2)
        @test_throws ArgumentError EWSim._cfar_pfa(:so, 5.0, 15)                   # odd N has no equal halves
        @test_throws ArgumentError EWSim.cfar_alpha(:bogus, 16, 1e-3)
        @test_throws ArgumentError EWSim.cfar_scan(zeros(50); variant = :ca, n_train = 15, n_guard = 2, pfa = 1e-3)  # odd n_train
        @test_throws ArgumentError EWSim.cfar_scan(zeros(50); variant = :bogus, n_train = 16, n_guard = 2, pfa = 1e-3)
    end
end
