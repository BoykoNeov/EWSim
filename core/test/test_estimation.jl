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

# --- the α-β LOS-rate filter (slice 11 gate 1) --------------------------------------
# The recursive seeker filter (NOT a gauss_newton reuse — those are batch). These are
# OPEN-LOOP primitive checks (synthetic ramp + noise, NO guidance loop): NECESSARY but
# NOT SUFFICIENT (advisor #1) — the (α,β) that minimise open-loop variance are NOT the
# ones that minimise closed-loop miss (over-smoothing → lag near CPA → the β U-shape),
# which the gate-0 probe / gate-2 wire test SWEEP. Here we pin the PRIMITIVE's math:
#   • rate convergence — a clean constant-ω ramp drives λ̇_est → ω_true (external anchor:
#     the KNOWN ramp rate, α-β's zero-lag property for a constant-velocity input, NOT a
#     self-calibrated round-trip);
#   • variance reduction — on a NOISY ramp Var(λ̇_filt) ≪ Var(λ̇_raw), with λ̇_raw anchored
#     to the analytic finite-diff std `σ√2/dt` (the external "why the filter matters"
#     baseline — the noise the naïve :raw path amplifies); own Xoshiro (convention 11);
#   • α/β scaling — larger β tracks a ramp FASTER (open-loop; the gain does what it says —
#     explicitly NOT a miss claim, which is the closed-loop U-shape story);
#   • degenerate guards — dt→0 / huge meas / extreme gains stay finite (no throw / no NaN).
@testset "estimation: α-β LOS-rate filter (seeker, slice 11)" begin
    dt = 1e-3

    @testset "SEEKER_MODES is the (:raw, :filtered) source of truth" begin
        @test SEEKER_MODES == (:raw, :filtered)
    end

    # Run the scalar α-β filter over a CLEAN constant-ω LOS ramp λ(k) = λ0 + ω_true·k·dt,
    # returning the final (λ_est, λ̇_est). Init on the first sample (the Seeker's gate-2 init).
    function ramp_track(ω_true, α, β; λ0 = 0.1, nsteps = 2000)
        λ_meas(k) = λ0 + ω_true * (k * dt)
        λ_est = λ_meas(0); λ̇_est = 0.0
        for k in 1:nsteps
            λ_est, λ̇_est = alpha_beta_los_step(λ_est, λ̇_est, λ_meas(k), dt; α = α, β = β)
        end
        return λ_est, λ̇_est
    end

    @testset "rate convergence: clean ramp → λ̇_est == ω_true (external anchor)" begin
        # α-β has ZERO steady-state lag for a constant-velocity (ramp) input, so the estimated
        # rate converges to the KNOWN ramp rate (not a self-calibrated round-trip). Probe: the
        # residual settles to ~1e-13 by 2000 steps — atol=1e-6 clears it with vast margin.
        for ω_true in (0.5, -0.3, 0.13)
            _, λ̇ = ramp_track(ω_true, 0.5, 0.2)
            @test λ̇ ≈ ω_true atol = 1e-6
        end
    end

    @testset "variance reduction: Var(λ̇_filt) ≪ Var(λ̇_raw ≈ σ√2/dt) (own Xoshiro)" begin
        # A NOISY ramp: λ_meas = clean ramp + σ·randn. The :raw foil finite-differences
        # consecutive noisy angles (λ̇_raw = wrap(λ_meas−λ_prev)/dt) — std ≈ σ√2/dt analytically
        # (the noise the filter must reject). The α-β estimate's std is ≫ smaller (probe ~11.8×).
        σ = 3e-3; ω_true = 0.5; α = 0.5; β = 0.1
        rng = Xoshiro(11)
        λ_clean(k) = 0.1 + ω_true * (k * dt)
        λ_prev = λ_clean(0) + σ * randn(rng)
        λ_est = λ_prev; λ̇_est = 0.0
        nsteps = 8000; burn = 2000
        n = 0; sraw = 0.0; sraw2 = 0.0; sfil = 0.0; sfil2 = 0.0
        for k in 1:nsteps
            λ_meas = λ_clean(k) + σ * randn(rng)
            λ̇_raw  = EWSim.wrap_angle(λ_meas - λ_prev) / dt
            λ_est, λ̇_est = alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α = α, β = β)
            if k > burn
                n += 1
                sraw += λ̇_raw; sraw2 += λ̇_raw^2
                sfil += λ̇_est; sfil2 += λ̇_est^2
            end
            λ_prev = λ_meas
        end
        std_raw = sqrt(sraw2/n - (sraw/n)^2)
        std_fil = sqrt(sfil2/n - (sfil/n)^2)
        analytic_raw = σ * sqrt(2) / dt                          # the external finite-diff baseline
        @test std_raw ≈ analytic_raw rtol = 0.05                 # probe: 4.241 vs 4.243 (raw IS the amplifier)
        @test std_fil < std_raw / 8                              # probe: ~11.8× reduction — the filter works
    end

    @testset "α/β scaling: larger β tracks a ramp faster (open-loop, NOT a miss claim)" begin
        # From a zero-rate start on a clean ramp, a LARGER β drives λ̇_est toward ω_true in
        # fewer steps (the gain does what it says). Measure the rate error at a FIXED early
        # step count: β=0.10 is far ahead of β=0.02 (probe: err@100 4e-12 vs 2e-3). This is an
        # OPEN-LOOP tracking-speed claim — the closed-loop "which β gives the best miss" is the
        # β U-shape (gate 0 / gate 2), deliberately NOT asserted here.
        ω_true = 0.5
        track_err(β) = abs(ramp_track(ω_true, 0.4, β; nsteps = 100)[2] - ω_true)
        @test track_err(0.10) < track_err(0.02)                  # larger β → faster tracking
        @test track_err(0.02) < 1e-2                             # even the slow gain is tracking (probe ~2e-3)
    end

    @testset "degenerate guards: dt→0 / huge meas / extreme gains stay finite" begin
        # dt→0: the β/dt rate-correction is floored (no divide-by-zero) → huge-but-FINITE, no NaN.
        g = alpha_beta_los_step(0.1, 0.2, 0.15, 0.0; α = 0.5, β = 0.1)
        @test all(isfinite, g)
        # a huge measurement is bounded by wrap_angle → the innovation stays in [−π,π] → finite.
        g = alpha_beta_los_step(0.1, 0.2, 1.0e9, dt; α = 0.5, β = 0.1)
        @test all(isfinite, g)
        # extreme gains (α at the 0 and 1 edges, β large) — still no throw / no NaN (the caller
        # validates 0<α<1, β>0 at LOAD — gate 2 — but the primitive itself must stay safe).
        @test all(isfinite, alpha_beta_los_step(0.1, 0.2, 0.15, dt; α = 0.0, β = 0.0))
        @test all(isfinite, alpha_beta_los_step(0.1, 0.2, 0.15, dt; α = 1.0, β = 0.9))
    end
end
