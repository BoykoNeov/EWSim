# test_airframe.jl — the pitch-plane rotational dynamics library vs its closed forms
# (HANDOFF §11 Tier A, slice 16 gate 1).
#
# Like dynamics/frames these are DETERMINISTIC, so every check is an exact closed form with
# an EXPLICIT atol (never rtol-`≈0`, which passes trivially — convention 11). The §1
# co-headline is SIGNS: the `Cmα` static-stability sign is the #1 trap, so the moment SIGN
# is pinned DIRECTLY (advisor tooth #1) — not just the oscillation frequency, which a double
# sign flip (α = θ−γ AND M-sign) would survive. V and γ are FROZEN in every closed-form test
# (advisor tooth #2 — Q = ½ρV² drifts with V, γ drifts with lift; the ω_sp/trim anchors are
# the flight-path-frozen short-period reduction). The damping test measures the log-decrement
# and pins ζ, not just ω_sp (advisor tooth #3 — a q̄ = q·d/(2V) factor-of-2 / ref-length slip
# leaves the frequency right but the damping wrong), and asserts the oscillation CENTER sits
# at α_trim (with Cmq = 0 the undamped swing must be centered on trim, not ending there).

@testset "airframe / pitch-plane rotational dynamics vs closed forms" begin
    # A representative slender missile (probed, temp/slice16_probe): 0.2 m dia, I = 50 kg·m².
    V = 500.0                       # airspeed, m/s — FROZEN in every anchor below
    S = π * 0.1^2                   # ref area (0.2 m dia)
    d = 0.2                         # ref length (diameter)
    I = 50.0                        # pitch moment of inertia
    ρ = 1.225
    Q = 0.5 * ρ * V^2               # dynamic pressure, for hand-recomputes
    QSd = Q * S * d

    # A statically STABLE airframe (Cmα < 0) is the workhorse; unstable/torque-free are spun
    # up per-test with their own params.
    stable(; Cma = -0.3, Cmd = 0.0, Cmq = 0.0) = AirframeParams(S, d, I, Cma, Cmd, Cmq, ρ)

    # A local RK4 driver over a fixed window (γ, V, δ frozen) → (t, θ, q) traces.
    function trace(p; theta0, q0, gamma, delta, T, dt = 1e-4)
        n = round(Int, T / dt)
        ts = Vector{Float64}(undef, n + 1); ths = similar(ts); qs = similar(ts)
        ts[1] = 0.0; ths[1] = theta0; qs[1] = q0
        th, q = theta0, q0
        for i in 1:n
            th, q = airframe_step(th, q, dt; gamma = gamma, V = V, delta = delta, p = p)
            ts[i+1] = i * dt; ths[i+1] = th; qs[i+1] = q
        end
        return ts, ths, qs
    end

    @testset "moment SIGN — the #1 trap, pinned directly (advisor tooth #1)" begin
        # α > 0 (nose up). Cmα < 0 must give a nose-DOWN (negative, restoring) moment.
        @test pitch_moment(0.05, 0.0, 0.0, V, stable(Cma = -0.3)) < 0.0
        # Cmα > 0 gives a nose-UP (positive, divergent) moment for the same α > 0.
        @test pitch_moment(0.05, 0.0, 0.0, V, stable(Cma = +0.3)) > 0.0
        # α < 0 flips the restoring sign (Cmα < 0 → positive, nose-up restoring).
        @test pitch_moment(-0.05, 0.0, 0.0, V, stable(Cma = -0.3)) > 0.0
        # Exact value: M = Q·S·d·Cmα·α (δ = q = 0). An INDEPENDENT recompute (convention 11).
        @test pitch_moment(0.05, 0.0, 0.0, V, stable(Cma = -0.3)) ≈ QSd * (-0.3) * 0.05 atol = 1e-9
        # The control term: pure δ (α = q = 0) → M = Q·S·d·Cmδ·δ.
        @test pitch_moment(0.0, 0.02, 0.0, V, stable(Cma = -0.3, Cmd = 0.1)) ≈ QSd * 0.1 * 0.02 atol = 1e-9
        # V ≤ floor → zero moment (the ÷V guard + Q→0; no NaN at rest).
        @test pitch_moment(0.05, 0.02, 1.0, 0.0, stable(Cma = -0.3, Cmd = 0.1, Cmq = -8.0)) == 0.0
    end

    @testset "torque-free (all Cm = 0) → q constant, θ linear" begin
        p = stable(Cma = 0.0)
        ts, ths, qs = trace(p; theta0 = 0.1, q0 = 0.02, gamma = 0.0, delta = 0.0, T = 4.0)
        @test qs[end] ≈ 0.02 atol = 1e-12                       # q unchanged (no moment)
        @test ths[end] ≈ 0.1 + 0.02 * 4.0 atol = 1e-9           # θ = θ0 + q·t exactly
    end

    @testset "static restore (Cmα<0) → SHM at ω_sp, RK4 exact (advisor tooth #2: V,γ frozen)" begin
        p = stable(Cma = -0.3)
        ω = short_period_freq(V, p)
        @test ω ≈ sqrt(0.3 * QSd / I) atol = 1e-12              # closed form, independent recompute
        Tsp = 2π / ω
        # α(t) = α0·cos(ω t) about 0 (δ = 0, γ = 0 so α = θ). Pin the integrator to the analytic
        # solution over 3 full periods — RK4 is exact for the linear ODE (machine eps).
        α0 = 0.08
        ts, ths, qs = trace(p; theta0 = α0, q0 = 0.0, gamma = 0.0, delta = 0.0, T = 3 * Tsp)
        analytic = α0 .* cos.(ω .* ts)
        @test maximum(abs.(ths .- analytic)) < 1e-9             # ~1e-15 in practice
        # q(t) = −α0·ω·sin(ω t): the velocity round-trip (catches a θ̇ = q sign slip).
        @test maximum(abs.(qs .+ α0 .* ω .* sin.(ω .* ts))) < 1e-6
    end

    @testset "unstable (Cmα>0) → divergence, NO real ω_sp" begin
        p = stable(Cma = +0.3)
        @test isnan(short_period_freq(V, p))                    # √ of positive-inside → NaN (no freq)
        ts, ths, qs = trace(p; theta0 = 0.01, q0 = 0.0, gamma = 0.0, delta = 0.0, T = 2.0)
        @test abs(ths[end]) > 0.1                               # grew ≫ 10× from θ0 = 0.01 (tumble)
        @test all(diff(abs.(ths)) .≥ -1e-9)                     # monotone growth (no oscillation)
    end

    @testset "trim (Cmα<0, δ≠0) → osc CENTER at α_trim (advisor tooth #3)" begin
        p = stable(Cma = -0.3, Cmd = 0.1)
        δ = 0.05
        αtrim = trim_alpha(δ, p)
        @test αtrim ≈ -(0.1 / -0.3) * 0.05 atol = 1e-12         # = +(Cmd/|Cma|)·δ = 0.01667
        Tsp = 2π / short_period_freq(V, p)
        # Start at α = 0 (γ = 0) → undamped swing 0 .. 2·α_trim, centered on α_trim.
        ts, ths, qs = trace(p; theta0 = 0.0, q0 = 0.0, gamma = 0.0, delta = δ, T = 3 * Tsp)
        center = (maximum(ths) + minimum(ths)) / 2
        @test center ≈ αtrim atol = 1e-4                        # the CENTER is trim, not the endpoint
        @test minimum(ths) ≈ 0.0 atol = 1e-4                    # swings down to the start
        @test maximum(ths) ≈ 2 * αtrim atol = 1e-4             # and up to 2·trim
        # δ = 0 → trim EXACTLY 0 for any Cmα (no 0/0 NaN when a live Cmα slider crosses 0).
        @test trim_alpha(0.0, stable(Cma = 0.0, Cmd = 0.1)) === 0.0
        @test trim_alpha(0.0, stable(Cma = -0.3, Cmd = 0.1)) === 0.0
    end

    @testset "γ offset: α = θ − γ, oscillation about θ = γ (frame round-trip)" begin
        # Same stable airframe but γ = 0.2. Restoring is about α = 0, i.e. θ = γ. Start θ = γ
        # (α = 0) with a q kick → SHM in α about 0, i.e. θ about γ. Pins the α = θ−γ definition.
        p = stable(Cma = -0.3)
        γ = 0.2
        ω = short_period_freq(V, p)
        Tsp = 2π / ω
        ts, ths, qs = trace(p; theta0 = γ, q0 = 0.01, gamma = γ, delta = 0.0, T = 3 * Tsp)
        center = (maximum(ths) + minimum(ths)) / 2
        @test center ≈ γ atol = 1e-4                            # θ oscillates about γ (α about 0)
    end

    @testset "damping (Cmq<0) → log-decrement pins ζ (advisor tooth #3)" begin
        # Cmq = −200 → ζ ≈ 0.16 (a clean, measurable decay; q̄ = q·d/2V is small at V=500, so a
        # large Cmq is needed — a real feature, not a tuning fudge). ζ = −Cmq·QSd·d/(4·V·I·ω).
        p = stable(Cma = -0.3, Cmq = -200.0)
        ω = short_period_freq(V, p)
        ζ = -(-200.0) * QSd * d / (4 * V * I * ω)
        @test 0.1 < ζ < 0.25                                    # sanity: a visible-but-underdamped decay
        # Trace from α0 = 0.08 (γ = 0, δ = 0 → decays to 0), collect successive positive peaks.
        ts, ths, qs = trace(p; theta0 = 0.08, q0 = 0.0, gamma = 0.0, delta = 0.0, T = 8.0)
        peaks = Float64[]; ptimes = Float64[]
        for i in 2:length(ths)-1
            if ths[i] > ths[i-1] && ths[i] > ths[i+1] && ths[i] > 0
                push!(peaks, ths[i]); push!(ptimes, ts[i])
            end
        end
        @test length(peaks) ≥ 2
        # Log-decrement δ_ln = ln(peak₁/peak₂) = 2πζ/√(1−ζ²) — pins the DAMPING, not the freq.
        δ_meas = log(peaks[1] / peaks[2])
        δ_pred = 2π * ζ / sqrt(1 - ζ^2)
        @test δ_meas ≈ δ_pred atol = 0.02
        # Damped period between peaks = 2π/ω_d, ω_d = ω√(1−ζ²).
        ω_d = ω * sqrt(1 - ζ^2)
        @test (ptimes[2] - ptimes[1]) ≈ 2π / ω_d atol = 1e-2
        # And it actually decays: |peak₂| < |peak₁|.
        @test peaks[2] < peaks[1]
    end

    @testset "rk4_rot generic stepper: constant-q̈ → exact quadratic θ, linear q" begin
        # A constant angular accel closure q̈ = a₀ integrates EXACTLY under RK4 (degree-2 θ):
        # θ(t) = θ0 + q0·t + ½·a₀·t², q(t) = q0 + a₀·t. The rk4_step-for-rotation analog of
        # dynamics.jl's constant-g parabola pin.
        a₀ = 0.7
        θ, q = 0.1, -0.05
        dt = 1e-3
        for _ in 1:1000
            θ, q = rk4_rot((_th, _q) -> a₀, θ, q, dt)
        end
        t = 1.0
        @test θ ≈ 0.1 + (-0.05) * t + 0.5 * a₀ * t^2 atol = 1e-9
        @test q ≈ -0.05 + a₀ * t atol = 1e-12
    end

    @testset "load-guard rationale: the params a live tick divides by (convention 5)" begin
        # These are the values scenario.jl validates > 0 at LOAD (I in the ÷I; V-floor covers V).
        # A well-formed set constructs and evaluates finitely; the guard lives in the loader, but
        # pin here that a zero I would blow the moment equation (documents WHY the loader checks).
        good = AirframeParams(S, d, I, -0.3, 0.1, -8.0, ρ)
        @test isfinite(pitch_moment(0.05, 0.02, 0.1, V, good))
        bad = AirframeParams(S, d, 0.0, -0.3, 0.1, -8.0, ρ)     # I = 0 (loader REJECTS this)
        @test !isfinite(pitch_moment(0.05, 0.0, 0.0, V, bad) / bad.I)   # ÷0 → Inf (why the guard exists)
    end
end
