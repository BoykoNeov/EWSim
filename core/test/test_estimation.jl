# test_estimation.jl — the bearings-only position fix vs closed forms AND an MC band
# (HANDOFF §9, slice 5 gate 1; the slice-1 analytic-vs-MC pattern reprised in 2-D).
#
# Closed-form anchors: a noise-free fix hits truth EXACTLY (both estimators); a
# 2-sensor 90° crossing is the geometric intersection. The MC anchors are the
# advisor-#1 load-bearing ones, each of which passes by the WRONG comparison if you
# are not careful:
#   • the pseudolinear BIAS is a MC MEAN offset (a covariance check misses it — a
#     biased estimator can have right-shaped scatter around the wrong centre), with
#     the KNOWN sign (range underestimated, fix pulled toward the sensors), and :ml
#     strictly reduces ‖bias‖ (an external anchor, not self-calibrated);
#   • CRLB ≈ MC scatter is matched against the ≈unbiased :ml fix on GOOD geometry
#     (matching CRLB to the biased pseudolinear scatter would be a category error);
#   • the linearized ellipse UNDER-predicts the true scatter on BAD geometry (the
#     named approximation boundary — a real effect, pinned).
# MC uses its OWN Xoshiro, never a world rng (the slice-1 batch precedent).

# Empirical MC mean + sample covariance of the fix over N noisy looks (own seeded
# stream). Calling it with the SAME seed for two estimators feeds them IDENTICAL
# bearing draws (the comprehension draws randn in sensor order), so PL and ML means
# are directly comparable — the numbers below were pinned from a throwaway probe.
function _mc_fix(em, sensors, sigmas, est, N, seed)
    θ0  = [atan(em[2]-s[2], em[1]-s[1]) for s in sensors]
    rng = Xoshiro(seed)
    sx = 0.0; sy = 0.0; sxx = 0.0; syy = 0.0; sxy = 0.0
    for _ in 1:N
        θ = [EWSim.wrap_angle(θ0[i] + sigmas[i]*randn(rng)) for i in eachindex(θ0)]
        p, _ = bearings_fix(θ, sensors, sigmas; estimator = est)
        sx += p[1]; sy += p[2]; sxx += p[1]^2; syy += p[2]^2; sxy += p[1]*p[2]
    end
    mx = sx/N; my = sy/N
    meanp = SVector(mx, my)
    cov   = SMatrix{2,2,Float64}(sxx/N - mx^2, sxy/N - mx*my, sxy/N - mx*my, syy/N - my^2)
    return meanp, cov
end

_ell_area(C) = sqrt(max(C[1,1]*C[2,2] - C[1,2]^2, 0.0))   # ∝ 1σ ellipse area (drop π)

@testset "estimation: bearings-only fix + CRLB" begin

    @testset "noise-free → fix == truth exactly (both estimators)" begin
        truth   = SVector(5000.0, 3000.0)
        sensors = [Vec3(0,0,0), Vec3(10000,0,0), Vec3(0,8000,0)]
        σ = deg2rad(1.0); sig = fill(σ, length(sensors))
        θ = [atan(truth[2]-s[2], truth[1]-s[1]) for s in sensors]
        for est in (:pseudolinear, :ml)
            p, _ = bearings_fix(θ, sensors, sig; estimator = est)
            @test hypot(p[1]-truth[1], p[2]-truth[2]) < 1e-6
        end
    end

    @testset "2-sensor 90° crossing → the geometric intersection" begin
        # A at origin sees (5000,0) along +x (line y=0); B at (5000,5000) sees it
        # along −y (line x=5000); they cross at (5000,0).
        em = SVector(5000.0, 0.0)
        S  = [Vec3(0,0,0), Vec3(5000,5000,0)]
        σ  = deg2rad(1.0)
        θ  = [atan(em[2]-s[2], em[1]-s[1]) for s in S]
        p, _ = bearings_fix(θ, S, fill(σ,2); estimator = :pseudolinear)
        @test hypot(p[1]-em[1], p[2]-em[2]) < 1e-6
    end

    @testset "pseudolinear bias (MC mean offset, known sign) + :ml reduces ‖bias‖" begin
        # 40 km emitter, ±10 km cross-baseline, σ=1°: observable but shallow enough
        # that the pseudolinear bias is large and clean (a 30 km geometry is ~unbiased,
        # a 50 km one collapses — this is the sweet spot, pinned from the probe).
        em  = SVector(40000.0, 0.0)
        S   = [Vec3(0,10000,0), Vec3(0,0,0), Vec3(0,-10000,0)]
        sig = fill(deg2rad(1.0), length(S))
        N   = 6000
        meanpl, covpl = _mc_fix(em, S, sig, :pseudolinear, N, 20260629)
        meanml, _     = _mc_fix(em, S, sig, :ml,           N, 20260629)
        biaspl = hypot(meanpl[1]-em[1], meanpl[2]-em[2])    # ≈ 1265 m
        biasml = hypot(meanml[1]-em[1], meanml[2]-em[2])    # ≈ 98 m
        se     = hypot(sqrt(covpl[1,1]/N), sqrt(covpl[2,2]/N))  # MC stderr of the mean ≈ 37 m
        @test meanpl[1] < em[1]              # KNOWN sign: range underestimated (pulled to sensors)
        @test biaspl > 600                    # a large, real bias (probe ≈ 1265 m)
        @test biaspl > 4*se                   # ≫ MC noise (probe ≈ 34σ) → a true bias, not scatter
        @test biasml < biaspl/3               # :ml removes most of it (probe ≈ 13×)
    end

    @testset "CRLB ≈ ML MC scatter (good geometry)" begin
        em  = SVector(5000.0, 3000.0)
        S   = [Vec3(0,0,0), Vec3(10000,0,0), Vec3(0,8000,0), Vec3(10000,8000,0)]
        σ   = deg2rad(1.0); sig = fill(σ, length(S))
        # CRLB at truth: the cov the (≈unbiased) ML reports on noise-free bearings.
        θ0 = [atan(em[2]-s[2], em[1]-s[1]) for s in S]
        _, Ccrlb = bearings_fix(θ0, S, sig; estimator = :ml)
        _, Cmc   = _mc_fix(em, S, sig, :ml, 5000, 424242)
        ratio = _ell_area(Cmc) / _ell_area(Ccrlb)            # probe ≈ 1.008
        @test 0.75 < ratio < 1.35
    end

    @testset "bad geometry: the linearized ellipse UNDER-predicts (named approximation)" begin
        em  = SVector(80000.0, 0.0)
        S   = [Vec3(0,1000,0), Vec3(0,0,0), Vec3(0,-1000,0)]   # near-collinear, far emitter
        σ   = deg2rad(2.0); sig = fill(σ, length(S))
        θ0  = [atan(em[2]-s[2], em[1]-s[1]) for s in S]
        _, Clin = bearings_fix(θ0, S, sig; estimator = :ml)    # linearized ellipse (at truth)
        _, Cmc  = _mc_fix(em, S, sig, :ml, 5000, 99)           # true scatter
        @test _ell_area(Cmc) > 2*_ell_area(Clin)               # probe ≈ 304× — under-prediction
    end

    @testset "unknown estimator is rejected" begin
        S = [Vec3(0,0,0), Vec3(10000,0,0)]
        @test_throws ErrorException bearings_fix([0.0, 0.1], S, fill(0.02,2); estimator = :nope)
    end
end
