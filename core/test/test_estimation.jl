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

    @testset "SEEKER_MODES is the (:raw, :filtered, :scan) source of truth" begin
        @test SEEKER_MODES == (:raw, :filtered, :scan)               # slice-13 :scan appended (the 4b rung)
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

# The slice-13 countermeasures primitives (gate 1): the seeker angular-profile processing
# layer — paint a lobe per return over a FIXED grid, cluster CFAR detections into peaks,
# resolve the tracked bearing by discrimination. PURE / RNG-free / wrap-safe. Teeth
# (convention 11): a DIFFERENT-expression recompute for the centroid (catches a transpose /
# a wrap slip); the ±π SEAM (the slice-5 wrap trap); a symmetric midpoint EXTERNAL anchor;
# the NN+halfwidth-reject gate semantics (gate-0 FINDINGS — NOT keep-in-gate-then-centroid);
# the additivity anchor (a singleton centroid returns its bearing EXACTLY, `===`); the
# determinism keystone (the profile LENGTH is decoy-count-INDEPENDENT — paint the fixed grid).
@testset "estimation: countermeasures seeker primitives (slice 13)" begin

    @testset "DISCRIMINATION_MODES is the (:none, :gated) source of truth" begin
        @test DISCRIMINATION_MODES == (:none, :gated)
    end

    @testset "angular_grid: centered, ascending, length == N_bins (the off-by-one pin)" begin
        # The centering `grid[i] = boresight + (i−(N_bins+1)/2)·bin_w` is its OWN off-by-one trap
        # (gate-1 forward-flag) — a half-bin shift misaligns the whole profile vs boresight. Pin it
        # with a closed-form round-trip so it can't hide in observe!.
        bore = 0.20; bw = 0.005; N = 64
        g = angular_grid(bore, N, bw)
        @test length(g) == N                                          # length == N_bins, always
        @test issorted(g)                                            # ascending (extract_peaks needs it)
        @test all(k -> g[k+1] - g[k] ≈ bw, 1:N-1)                    # uniform bin_w spacing (atol via ≈)
        # EVEN N: the boresight falls BETWEEN the two central bins (N/2 at −bw/2, N/2+1 at +bw/2).
        @test g[N ÷ 2]     ≈ bore - bw/2 atol = 1e-12
        @test g[N ÷ 2 + 1] ≈ bore + bw/2 atol = 1e-12
        @test (g[N ÷ 2] + g[N ÷ 2 + 1]) / 2 ≈ bore atol = 1e-12      # the window is centered on boresight
        # ODD N: the CENTER bin sits EXACTLY on the boresight.
        go = angular_grid(bore, 65, bw)
        @test go[33] ≈ bore atol = 1e-12                             # bin (65+1)/2 = 33 == boresight
        # LENGTH is boresight-INDEPENDENT (the determinism grid — the draw count is fixed by N_bins).
        @test length(angular_grid(-1.7, N, bw)) == N
        @test length(angular_grid( 2.9, N, bw)) == N
        # A KNOWN bearing lands in the expected bin (the round-trip): a source ON bin (N/2+4)'s
        # center is nearest that bin — a half-bin shift in the centering would move argmin.
        src = g[N ÷ 2 + 4]
        @test argmin(abs.(g .- src)) == N ÷ 2 + 4
    end

    @testset "paint_angular_profile!: floor + additive Gaussian lobes, wrap-safe, fixed length" begin
        grid  = collect(-0.1:0.005:0.1)                              # a fixed angular grid (41 bins)
        power = similar(grid)

        # ONE lobe: peaks AT the source bearing, floors far away, sits above the floor everywhere.
        paint_angular_profile!(power, grid, [(0.0, 40.0)]; σ_beam = 0.015, floor = 1.0)
        @test length(power) == length(grid)
        @test grid[argmax(power)] == 0.0                             # the peak bin is the source bearing
        @test power[argmax(power)] ≈ 41.0 atol = 1e-9               # floor + amp at Δλ=0
        @test power[1]   ≈ 1.0 atol = 1e-6                          # a bin ≫ σ_beam away → the bare floor
        @test all(>=(1.0), power)                                    # never below the floor

        # ADDITIVITY over sources (the linear-power superposition — the decoy adds its own lobe):
        # profile(A ∪ B) − floor == (profile(A) − floor) + (profile(B) − floor), elementwise.
        pa = similar(grid); pb = similar(grid); pab = similar(grid)
        paint_angular_profile!(pa,  grid, [(-0.03, 40.0)];              σ_beam = 0.015, floor = 1.0)
        paint_angular_profile!(pb,  grid, [( 0.04, 80.0)];              σ_beam = 0.015, floor = 1.0)
        paint_angular_profile!(pab, grid, [(-0.03, 40.0), (0.04, 80.0)]; σ_beam = 0.015, floor = 1.0)
        @test pab .- 1.0 ≈ (pa .- 1.0) .+ (pb .- 1.0) atol = 1e-12

        # LENGTH is decoy-count-INDEPENDENT (the determinism keystone — paint the fixed grid,
        # never per-return): 0, 1, 2 sources all write exactly length(grid) cells.
        for srcs in ([], [(0.0, 40.0)], [(-0.03, 40.0), (0.04, 80.0)])
            paint_angular_profile!(power, grid, srcs; σ_beam = 0.015, floor = 1.0)
            @test length(power) == length(grid)
        end

        # WRAP-SAFE painting: a source near +π lobes onto grid cells near −π (angularly adjacent
        # across the seam) — a naïve (grid−λ) would floor them (the slice-5 seam trap).
        seam_grid  = [3.10, 3.14, -3.14, -3.10]
        seam_power = similar(seam_grid)
        paint_angular_profile!(seam_power, seam_grid, [(3.14, 40.0)]; σ_beam = 0.02, floor = 1.0)
        @test seam_power[3] > 30.0                                   # the −3.14 cell (wrap-dist ≈ 0.003) IS lit
    end

    @testset "intensity_centroid: singleton ===, weighted mean, ±π seam, symmetric anchor" begin
        # ADDITIVITY ANCHOR: a single already-wrapped peak returns its bearing EXACTLY (=== ).
        @test intensity_centroid([(0.37, 5.0)]) === 0.37
        @test intensity_centroid([(-1.20, 2.0)]) === -1.20
        # EMPTY → nothing (the Seeker then coasts on the prediction).
        @test intensity_centroid(Tuple{Float64, Float64}[]) === nothing

        # INTENSITY-WEIGHTED MEAN, pinned by a DIFFERENT expression (Σwλ/Σw, valid off the seam).
        peaks = [(0.10, 1.0), (0.20, 3.0)]
        expect = (1.0 * 0.10 + 3.0 * 0.20) / (1.0 + 3.0)             # = 0.175
        @test intensity_centroid(peaks) ≈ expect atol = 1e-12
        @test intensity_centroid(peaks) ≈ 0.175   atol = 1e-12

        # SYMMETRIC EXTERNAL ANCHOR: equal weights → the geometric midpoint, ref-independent.
        @test intensity_centroid([(0.1, 1.0), (0.3, 1.0)]) ≈ 0.2 atol = 1e-12

        # ±π SEAM: a target near +π and a decoy near −π blend to the TOP of the circle (≈ ±π),
        # NOT a jump to 0 (the naïve mean bug). c = wrap(3.1 + ½·wrap(−3.1−3.1)) ≈ π.
        c = intensity_centroid([(3.1, 1.0), (-3.1, 1.0)])
        @test abs(c) > 3.0                                           # near ±π (naïve mean would give ≈ 0)
        @test abs(abs(c) - π) < 0.05                                 # actually at the seam top
    end

    @testset "extract_peaks: contiguous-run clustering → power-weighted centroids" begin
        grid = [i * 0.01 for i in 0:20]                             # 21 bins, 0.00 … 0.20
        z    = fill(1.0, 21)
        z[4] = 2.0; z[5] = 5.0; z[6] = 3.0                          # run A: bins 4–6 (strongest at 5)
        z[14] = 4.0; z[15] = 6.0                                     # run B: bins 14–15
        det  = falses(21); det[4:6] .= true; det[14:15] .= true

        peaks = extract_peaks(grid, z, det)
        @test length(peaks) == 2                                    # two separated runs → two peaks

        # Peak angle = the run's POWER-WEIGHTED centroid, pinned by a DIFFERENT expression
        # (Σ grid·z / Σ z, valid off the seam); strength = Σ z over the run.
        cenA = (0.03*2.0 + 0.04*5.0 + 0.05*3.0) / (2.0 + 5.0 + 3.0)  # = 0.041
        cenB = (0.13*4.0 + 0.14*6.0)             / (4.0 + 6.0)       # = 0.136
        @test peaks[1][1] ≈ cenA atol = 1e-12
        @test peaks[1][2] ≈ 10.0 atol = 1e-12                       # strength A = Σ z
        @test peaks[2][1] ≈ cenB atol = 1e-12
        @test peaks[2][2] ≈ 10.0 atol = 1e-12

        # ONE run → one peak; NO detections → an EMPTY vector (coast, never track nothing).
        @test length(extract_peaks(grid, z, det .& (grid .< 0.10))) == 1
        @test isempty(extract_peaks(grid, z, falses(21)))
    end

    @testset "validation_gate: nearest-neighbor within halfwidth, else coast (nothing)" begin
        # NEAREST (not brightest): a brighter decoy at 0.19 is IGNORED for the closer target at
        # 0.10 — the discriminator CFAR cannot be (a bright decoy is a strong detection).
        peaks = [(0.10, 5.0), (0.19, 20.0)]
        @test validation_gate(peaks, 0.10, 0.045) === 0.10          # target kept, brighter decoy rejected
        # The decoy leaving the gate: prediction on the target, only the decoy in the list, beyond
        # halfwidth → COAST (nothing); the caller holds the prediction (never tracks the decoy).
        @test validation_gate([(0.20, 1.0)], 0.10, 0.045) === nothing
        # Empty peaks → nothing.
        @test validation_gate(Tuple{Float64, Float64}[], 0.10, 0.045) === nothing
        # In-gate boundary: nearest within halfwidth is kept.
        @test validation_gate([(0.14, 1.0)], 0.10, 0.045) === 0.14
        # WRAP-SAFE gate: a peak near −π and a prediction near +π are angularly ADJACENT.
        @test validation_gate([(-3.13, 1.0)], 3.13, 0.045) === -3.13
    end
end
