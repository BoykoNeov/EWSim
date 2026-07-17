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
    stable(; Cma = -0.3, Cmd = 0.0, Cmq = 0.0, Cla = 0.0) = AirframeParams(S, d, I, Cma, Cmd, Cmq, ρ, Cla)

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
        good = AirframeParams(S, d, I, -0.3, 0.1, -8.0, ρ, 0.0)
        @test isfinite(pitch_moment(0.05, 0.02, 0.1, V, good))
        bad = AirframeParams(S, d, 0.0, -0.3, 0.1, -8.0, ρ, 0.0)     # I = 0 (loader REJECTS this)
        @test !isfinite(pitch_moment(0.05, 0.0, 0.0, V, bad) / bad.I)   # ÷0 → Inf (why the guard exists)
    end

    # ── SLICE 17 — the α→lift→γ coupling primitives (lift_accel + rk4_coupled) ──
    # The rotation slice 16 BANKED (θ, q) now feeds translation: α = θ−γ makes a body lift ⟂ v
    # that turns the flight path. The teeth: the #1 SIGN trap (α>0 ⇒ γ̇>0, pinned BY the ⟂-dot AND
    # the sign, not magnitude), the decoupled limit (Cla=0 ⇒ joint step ≡ slice-8 + slice-16
    # steppers BIT-EXACT — the additive-slice guarantee at the primitive level), and the
    # steady-turn radius R = 2m/(ρSC_Lα·α) closed form (the load-bearing anchor).
    mag(u) = sqrt(u[1]^2 + u[2]^2 + u[3]^2)
    dot3(u, w) = u[1]*w[1] + u[2]*w[2] + u[3]*w[3]     # slice 20 (the ∥/⟂ split); no LinearAlgebra

    @testset "slice-17: lift_accel — sign (#1 trap), ⟂ v, magnitude, zero-safe" begin
        mass = 100.0
        p = stable(Cma = -0.3, Cla = 20.0)
        # Level flight (γ=0), α = +0.05 (nose above v): lift points +z (UP) → γ̇ > 0 (the sign).
        vel = Vec3(V, 0.0, 0.0)
        aL = lift_accel(vel, 0.05, mass, p)                 # γ = 0 ⇒ α = θ = 0.05
        @test aL[3] > 0.0                                   # UP — a nose-up α lifts the path up
        @test aL[1] ≈ 0.0 atol = 1e-12                      # level: no along-track component
        # ⟂ v to machine eps — level AND climbing (a DOUBLE sign flip survives a magnitude test).
        @test abs(aL[1]*vel[1] + aL[2]*vel[2] + aL[3]*vel[3]) / V < 1e-9
        γc = 0.5; velc = Vec3(V*cos(γc), 0.0, V*sin(γc))
        aLc = lift_accel(velc, γc + 0.05, mass, p)          # climbing, same α = +0.05
        @test abs(aLc[1]*velc[1] + aLc[2]*velc[2] + aLc[3]*velc[3]) / V < 1e-9
        # Magnitude = Q·S·C_Lα·α / m (an INDEPENDENT recompute, convention 11).
        @test mag(aL) ≈ (0.5*ρ*V^2) * S * 20.0 * 0.05 / mass atol = 1e-9
        # α < 0 flips lift DOWN; α = 0 → exactly zero lift.
        @test lift_accel(vel, -0.05, mass, p)[3] < 0.0
        @test lift_accel(vel, 0.0, mass, p) == Vec3(0.0, 0.0, 0.0)
        # V ≤ floor → zero (Q→0 + the ÷V guard; a launch/apex tick can't crash — convention 5).
        @test lift_accel(Vec3(0.0, 0.0, 0.0), 0.05, mass, p) == Vec3(0.0, 0.0, 0.0)
    end

    @testset "slice-17: rk4_coupled generic — constant (force, q̈) integrates EXACTLY" begin
        # The joint analog of the rk4_rot constant-q̈ pin: RK4 is exact for degree-2 states.
        # θ(t)=θ0+q0 t+½ q̈ t², q=q0+q̈ t, pos=p0+v0 t+½ a0 t², vel=v0+a0 t.
        a0 = Vec3(0.3, -0.1, 0.7); qdd = 0.4
        f = (P, Vv, TH, Q) -> (Vv, a0, Q, qdd)             # ṗ=v, v̇=a0, θ̇=q, q̈=const
        pos = Vec3(1.0, 2.0, 3.0); vel = Vec3(10.0, 0.0, -5.0); θ = 0.1; q = -0.05
        dt = 1e-3
        for _ in 1:1000
            pos, vel, θ, q = rk4_coupled(f, pos, vel, θ, q, dt)
        end
        t = 1.0
        @test pos ≈ Vec3(1.0, 2.0, 3.0) + Vec3(10.0, 0.0, -5.0)*t + 0.5*a0*t^2 atol = 1e-9
        @test vel ≈ Vec3(10.0, 0.0, -5.0) + a0*t atol = 1e-11
        @test θ ≈ 0.1 + (-0.05)*t + 0.5*qdd*t^2 atol = 1e-9
        @test q ≈ -0.05 + qdd*t atol = 1e-12
    end

    @testset "slice-17: decoupled limit (Cla=0) ≡ integrator_step ⊕ airframe_step, BIT-EXACT" begin
        # With Cla=0 AND no translational force, the joint step must reproduce the slice-8
        # translation stepper AND the slice-16 rotation stepper bit-for-bit — the additive-slice
        # guarantee at the primitive level. `==`, not atol (advisor): if it ever drifts to 1-ULP
        # the culprit is expression structure, not physics. ISOLATE to inertial (grav/drag off) —
        # under gravity the joint re-evaluates V,γ mid-step (the coupling) ⇒ only ≈, not =.
        p = stable(Cma = -0.3, Cmd = 0.1, Cmq = -150.0, Cla = 0.0)
        mass = 100.0; δ = 0.15; dt = 1e-3
        pos0 = Vec3(0.0, 0.0, 0.0); vel0 = Vec3(V*cos(0.4), 0.0, V*sin(0.4))
        θ0 = 0.4 + 0.1; q0 = 0.0
        f = (P, Vv, TH, Q) -> begin
            γ = atan(Vv[3], Vv[1]); Vs = mag(Vv)
            (Vv, lift_accel(Vv, TH, mass, p), Q, pitch_moment(TH - γ, δ, Q, Vs, p) / p.I)
        end
        pj, vj, θj, qj = rk4_coupled(f, pos0, vel0, θ0, q0, dt)
        # reference: integrator_step (pos/vel, zero accel — Cla=0 ⇒ no lift), airframe_step (θ,q).
        pr, vr = integrator_step(:rk4, _ -> Vec3(0.0, 0.0, 0.0), pos0, vel0, dt)
        γ0 = atan(vel0[3], vel0[1]); V0 = mag(vel0)
        θr, qr = airframe_step(θ0, q0, dt; gamma = γ0, V = V0, delta = δ, p = p)
        @test pj == pr                                      # translation bit-exact (zero force)
        @test vj == vr
        @test θj == θr                                      # rotation bit-exact (V,γ frozen ⇒ ≡ airframe_step)
        @test qj == qr
    end

    @testset "slice-17: steady-turn radius R = 2m/(ρ·S·C_Lα·α), ⟂-lift preserves speed" begin
        # Isolation: gravity/drag OFF, Cmq=0 (clean trim). Init AT equilibrium (θ=γ+α_trim,
        # q=steady γ̇). Lift ⟂ v bends the path into a CIRCLE of radius R, SPEED-independent (|v|
        # const). The load-bearing anchor — R is a finite-diff γ̇ ⇒ tight atol, not == (advisor).
        mass = 100.0; δ = 0.15
        p = stable(Cma = -0.3, Cmd = 0.1, Cmq = 0.0, Cla = 20.0)
        α_trim = trim_alpha(δ, p)                           # -(Cmd/Cma)·δ, exact at Cmq=0
        R_formula = 2*mass / (ρ * S * 20.0 * α_trim)        # ≈ 5196.9 m
        γ0 = 0.4
        gdot0 = ((0.5*ρ*V^2) * S * 20.0 * α_trim / mass) / V   # steady γ̇ = a_lift/V
        θ0 = γ0 + α_trim
        vel0 = Vec3(V*cos(γ0), 0.0, V*sin(γ0))
        f = (P, Vv, TH, Q) -> begin
            γ = atan(Vv[3], Vv[1]); Vs = mag(Vv)
            (Vv, lift_accel(Vv, TH, mass, p), Q, pitch_moment(TH - γ, δ, Q, Vs, p) / p.I)
        end
        pos, vel, θ, q = Vec3(0.0, 0.0, 0.0), vel0, θ0, gdot0
        dt = 1e-3; T = 10.0; n = round(Int, T/dt)
        αmin = Inf; αmax = -Inf
        for _ in 1:n
            pos, vel, θ, q = rk4_coupled(f, pos, vel, θ, q, dt)
            α = θ - atan(vel[3], vel[1])
            αmin = min(αmin, α); αmax = max(αmax, α)
        end
        @test αmin ≈ α_trim atol = 1e-4                     # α held at trim ⇒ a STEADY turn
        @test αmax ≈ α_trim atol = 1e-4
        @test mag(vel) ≈ V atol = 1e-6                      # lift ⟂ v ⇒ speed preserved
        γend = atan(vel[3], vel[1])
        R_meas = V / ((γend - γ0) / T)                      # V / γ̇_measured
        @test R_meas ≈ R_formula atol = 1e-2                # ≈5197 m; finite-diff ⇒ tight-not-exact
    end

    # ── SLICE 19 — the INNER α/g AUTOPILOT: the aero inversion + the flight-condition g-limit ──
    # Slice 17's δ was a fixed authored trim; here `a_cmd` is INVERTED THROUGH THE AERO into
    # α_cmd and thence δ. The teeth: the SIGN chain arrow-by-arrow (#1 trap, THIRD occurrence —
    # the chain is longer now, so an even number of flips has more places to hide and a
    # magnitude-only test would pass); the `a_max_aero ↔ α_max` ROUND-TRIP (the clamp IS the
    # limit — the two names must agree by construction, not calibration); the crash-safety
    # degenerates at the `a_cmd/Q` divide (convention 5 — `af_cla` is a LIVE slider reaching −5);
    # and the δ law's steady state pinned against slice-16's INDEPENDENTLY-written `trim_alpha`
    # (an external anchor, convention 11 — not a self-calibrated round-trip).
    # The gate-0 PICK's airframe (temp/slice19_probe): Cma=−1, Cmd=+3, Cmq=−150, Cla=20, k_α=1,
    # k_q=0.3, α_max=0.2, mass=140.
    mass19 = 140.0
    p19    = stable(Cma = -1.0, Cmd = 3.0, Cmq = -150.0, Cla = 20.0)
    KA, KQ = 1.0, 0.3

    @testset "slice-19: the SIGN chain, arrow by arrow (#1 trap — a double flip must not hide)" begin
        # Level flight (γ=0) ⇒ the lift direction n̂ = (−sin0, 0, cos0) = +z. Demand +z (pull UP):
        # EVERY arrow of `a_perp → α_cmd → δ → M → α → lift → γ̇` must come out POSITIVE. Pinned
        # individually (gate-0 GOAL A) — asserting only the final γ̇ would survive an even flip.
        vel = Vec3(V, 0.0, 0.0); n̂ = Vec3(0.0, 0.0, 1.0)
        a_cmd = Vec3(0.0, 0.0, 100.0)
        a_perp = a_cmd[1]*n̂[1] + a_cmd[2]*n̂[2] + a_cmd[3]*n̂[3]
        @test a_perp > 0.0                                          # arrow 1: demand +z
        α_cmd, sat = alpha_command(a_cmd, vel, mass19, p19; alpha_max = 1.0)
        @test α_cmd > 0.0                                           # arrow 2: nose ABOVE velocity
        @test sat == false                                          # α_max generous ⇒ not binding
        δ, dsat = alpha_autopilot_delta(α_cmd, 0.0, 0.0, p19; k_alpha = KA, k_q = KQ, delta_max = 0.5)
        @test δ > 0.0                                               # arrow 3: Cma<0, Cmd>0 ⇒ δ>0
        @test dsat == false
        @test pitch_moment(0.0, δ, 0.0, V, p19) > 0.0               # arrow 4: NOSE-UP moment
        aL = lift_accel(vel, α_cmd, mass19, p19)                    # γ=0 ⇒ θ=α_cmd ⇒ α=α_cmd
        @test aL[1]*n̂[1] + aL[2]*n̂[2] + aL[3]*n̂[3] > 0.0            # arrow 5: lift toward +n̂
        @test abs(aL[1]*vel[1] + aL[2]*vel[2] + aL[3]*vel[3]) / V < 1e-9   # arrow 6: lift ⟂ v
        @test (aL[1]*n̂[1] + aL[2]*n̂[2] + aL[3]*n̂[3]) / V > 0.0      # arrow 7: γ̇ > 0 — path chases nose
        # THE MIRROR: demand −z must flip every arrow. (A sign error that survives BOTH the
        # forward chain and the mirror has to be an even flip in each — the reason for arrow-wise.)
        α2, _ = alpha_command(Vec3(0.0, 0.0, -100.0), vel, mass19, p19; alpha_max = 1.0)
        δ2, _ = alpha_autopilot_delta(α2, 0.0, 0.0, p19; k_alpha = KA, k_q = KQ, delta_max = 0.5)
        aL2 = lift_accel(vel, α2, mass19, p19)
        @test α2 < 0.0
        @test δ2 < 0.0
        @test pitch_moment(0.0, δ2, 0.0, V, p19) < 0.0
        @test aL2[3] < 0.0
        # Antisymmetry: the inversion is LINEAR in the demand (exact, not just sign-flipped).
        @test α2 ≈ -α_cmd atol = 1e-15
    end

    @testset "slice-19: a_max_aero closed form + the α_max ROUND-TRIP (the clamp IS the limit)" begin
        # An INDEPENDENT recompute (different expression grouping — convention 11 catches a
        # decomposition slip, not a copy of the implementation).
        αm = 0.2
        aa = aero_accel_limit(700.0, mass19, p19; alpha_max = αm)
        @test aa ≈ ((0.5 * ρ * 700.0^2) * S) * (20.0 * αm) / mass19 atol = 1e-9
        @test aa > 0.0
        # Scaling laws — the physics the name claims: ∝ V² (via Q) and ∝ α_max (linear).
        @test aero_accel_limit(1400.0, mass19, p19; alpha_max = αm) ≈ 4 * aa atol = 1e-6
        @test aero_accel_limit(700.0, mass19, p19; alpha_max = 2αm) ≈ 2 * aa atol = 1e-9
        # THE ROUND-TRIP: a demand of EXACTLY a_max_aero ⇒ α_cmd is EXACTLY α_max. The two names
        # agree by construction. `atol`, not `==`: α_raw lands ~1 ULP off α_max (measured 2.8e-17
        # at gate 0), so the clamp may not engage and the raw value is returned.
        vel = Vec3(700.0, 0.0, 0.0)
        α_rt, sat_rt = alpha_command(Vec3(0.0, 0.0, aa), vel, mass19, p19; alpha_max = αm)
        @test α_rt ≈ αm atol = 1e-15
        # ⇒ `sat` is EXACTLY the statement `|a_perp| > a_max_aero` — the flag and the readout are
        # the same fact. Pinned either side of the boundary (not AT it — that is the 1-ULP coin flip).
        @test alpha_command(Vec3(0.0, 0.0, 1.5aa), vel, mass19, p19; alpha_max = αm)[2] == true
        @test alpha_command(Vec3(0.0, 0.0, 0.5aa), vel, mass19, p19; alpha_max = αm)[2] == false
    end

    @testset "slice-19: the α_max clamp binds — BOTH sides (a stuck-true sat must fail)" begin
        αm = 0.2; vel = Vec3(700.0, 0.0, 0.0)
        aa = aero_accel_limit(700.0, mass19, p19; alpha_max = αm)
        # ABOVE the ceiling: pegged at ±α_max EXACTLY (the clamp), sat set.
        αhi, shi = alpha_command(Vec3(0.0, 0.0, 1.5aa), vel, mass19, p19; alpha_max = αm)
        @test αhi == αm                                     # `==`: the clamp returns the bound itself
        @test shi == true
        αlo, slo = alpha_command(Vec3(0.0, 0.0, -1.5aa), vel, mass19, p19; alpha_max = αm)
        @test αlo == -αm
        @test slo == true
        # BELOW the ceiling: UNCLAMPED (the raw inversion) and sat CLEAR — without this arm a
        # stuck-true `sat` / an always-clamping bug would pass the binding test alone.
        αmid, smid = alpha_command(Vec3(0.0, 0.0, 0.5aa), vel, mass19, p19; alpha_max = αm)
        @test smid == false
        @test αmid ≈ 0.5 * αm atol = 1e-15                  # linear in the demand ⇒ exactly half
        @test abs(αmid) < αm
    end

    @testset "slice-19: the out-of-plane DISCARD (the §1 pitch-plane approximation, pinned)" begin
        # A pitch-plane α autopilot CANNOT make y-accel: the signed projection onto n̂ (which has
        # no y component) drops it. Pinned as a named approximation, not left implicit — a target
        # maneuvering out of plane is UNFLYABLE by construction and must not read as a bug.
        vel = Vec3(700.0, 0.0, 0.0)
        α_planar, _ = alpha_command(Vec3(0.0, 0.0, 100.0), vel, mass19, p19; alpha_max = 1.0)
        α_oop, _    = alpha_command(Vec3(0.0, 5000.0, 100.0), vel, mass19, p19; alpha_max = 1.0)
        @test α_oop == α_planar                             # a huge y demand changes NOTHING
        # A PURELY out-of-plane demand ⇒ zero α_cmd (nothing the pitch plane can do about it).
        @test alpha_command(Vec3(0.0, 5000.0, 0.0), vel, mass19, p19; alpha_max = 1.0)[1] == 0.0
        # The along-v̂ component is likewise unproducible by lift (⟂ v) — also discarded.
        @test alpha_command(Vec3(5000.0, 0.0, 0.0), vel, mass19, p19; alpha_max = 1.0)[1] ≈ 0.0 atol = 1e-12
        # In a CLIMB the projection follows the rotated n̂ = (−sinγ, 0, cosγ) — the frame is the
        # velocity's, not the world's (a frame slip would show here and nowhere else).
        γc = 0.5; velc = Vec3(700.0*cos(γc), 0.0, 700.0*sin(γc))
        n̂c = Vec3(-sin(γc), 0.0, cos(γc))
        αc, _ = alpha_command(100.0 * n̂c, velc, mass19, p19; alpha_max = 1.0)
        @test αc ≈ α_planar atol = 1e-12                    # same ⟂ demand, same α — γ-invariant
        @test alpha_command(100.0 * Vec3(cos(γc), 0.0, sin(γc)), velc, mass19, p19;
                            alpha_max = 1.0)[1] ≈ 0.0 atol = 1e-12   # along v̂ ⇒ nothing
    end

    @testset "slice-19: the a_cmd/Q divide — crash-safety degenerates (convention 5)" begin
        # THE crash-safety site of this slice: `α_cmd = a_perp·m/(Q·S·C_Lα)`. A throw inside
        # decide! lands in the session's IO/EOF-only catch and SILENTLY DROPS the connection, so
        # every degenerate must come back finite. (gate-0 GOAL G — all confirmed live.)
        αm = 0.2
        # V → 0 (launch/apex): Q→0 ⇒ the floor holds the divide; α_cmd pegs at α_max, sat set.
        for vel in (Vec3(0.0, 0.0, 0.0), Vec3(1e-9, 0.0, 0.0))
            α, s = alpha_command(Vec3(0.0, 0.0, 100.0), vel, mass19, p19; alpha_max = αm)
            @test isfinite(α)
            @test abs(α) ≤ αm
            @test s == true                                 # tiny Q ⇒ demand looks infinite
        end
        # C_Lα → 0 (the LIVE `af_cla` slider dragged through zero): no lift authority ⇒ α_cmd = 0
        # and SATURATED (the ceiling is zero — you cannot pull anything). No divide, no Inf.
        p0 = stable(Cma = -1.0, Cmd = 3.0, Cmq = -150.0, Cla = 0.0)
        @test alpha_command(Vec3(0.0, 0.0, 100.0), Vec3(700.0, 0.0, 0.0), mass19, p0;
                            alpha_max = αm) == (0.0, true)
        @test aero_accel_limit(700.0, mass19, p0; alpha_max = αm) == 0.0
        # C_Lα < 0 (the slider's range reaches −5) is NOT degenerate: α_cmd FLIPS SIGN and the
        # lift lands back on +n̂ exactly as commanded — the inversion is self-consistent through
        # zero (gate-0 FINDING 9). This is why the limit takes |C_Lα| but the command takes the
        # SIGNED C_Lα; a stray `abs` in the command would break this and nothing else.
        pn_ = stable(Cma = -1.0, Cmd = 3.0, Cmq = -150.0, Cla = -20.0)
        vel = Vec3(700.0, 0.0, 0.0)
        aa_neg = aero_accel_limit(700.0, mass19, pn_; alpha_max = 1.0)
        @test aa_neg > 0.0                                  # a MAGNITUDE — a negative slope still lifts
        @test aa_neg ≈ aero_accel_limit(700.0, mass19, p19; alpha_max = 1.0) atol = 1e-9
        α_neg, _ = alpha_command(Vec3(0.0, 0.0, 100.0), vel, mass19, pn_; alpha_max = 1.0)
        @test α_neg < 0.0                                   # opposite α for the SAME +z demand
        @test lift_accel(vel, α_neg, mass19, pn_)[3] > 0.0  # …and the lift still points UP
        # The realized lift matches the demand either way — the sign convention closes the loop.
        @test lift_accel(vel, α_neg, mass19, pn_)[3] ≈ 100.0 atol = 1e-9
        α_pos, _ = alpha_command(Vec3(0.0, 0.0, 100.0), vel, mass19, p19; alpha_max = 1.0)
        @test lift_accel(vel, α_pos, mass19, p19)[3] ≈ 100.0 atol = 1e-9
        # Every finite knob combination the sliders can reach stays finite (no NaN escapes).
        for cla in (20.0, 1e-12, 0.0, -1e-12, -5.0, -20.0), Vk in (0.0, 1.0, 700.0, 2000.0)
            pk = stable(Cma = -1.0, Cmd = 3.0, Cmq = -150.0, Cla = cla)
            α, _ = alpha_command(Vec3(0.0, 0.0, 100.0), Vec3(Vk, 0.0, 0.0), mass19, pk; alpha_max = αm)
            @test isfinite(α)
            @test isfinite(aero_accel_limit(Vk, mass19, pk; alpha_max = αm))
        end
    end

    @testset "slice-19: the δ law — trim consistency vs slice-16's `trim_alpha` (external anchor)" begin
        # AT the commanded α with zero pitch rate, the feedback terms vanish and the law returns
        # its FEEDFORWARD — which must be the EXACT inverse of `trim_alpha`, written independently
        # two slices earlier. Round-tripping through a function this one never calls is a genuine
        # external anchor (convention 11), not a self-calibration.
        α_cmd = 0.12
        δ_ss, ds = alpha_autopilot_delta(α_cmd, α_cmd, 0.0, p19; k_alpha = KA, k_q = KQ, delta_max = 0.5)
        @test ds == false
        @test trim_alpha(δ_ss, p19) ≈ α_cmd atol = 1e-15    # δ → α round-trip closes
        @test δ_ss ≈ -(p19.Cma / p19.Cmd) * α_cmd atol = 1e-15
        # …and that δ makes the net pitching moment ZERO at α_cmd — the definition of trim.
        @test pitch_moment(α_cmd, δ_ss, 0.0, V, p19) ≈ 0.0 atol = 1e-9
        # The feedback arms, isolated: an α BELOW command demands MORE δ; a positive q (nose
        # already pitching up) demands LESS (the rate loop damps). Signs pinned individually.
        δ_lo, _ = alpha_autopilot_delta(α_cmd, α_cmd - 0.05, 0.0, p19; k_alpha = KA, k_q = KQ, delta_max = 0.5)
        @test δ_lo > δ_ss
        @test δ_lo ≈ δ_ss + KA * 0.05 atol = 1e-12
        δ_q, _ = alpha_autopilot_delta(α_cmd, α_cmd, 0.4, p19; k_alpha = KA, k_q = KQ, delta_max = 0.5)
        @test δ_q < δ_ss
        @test δ_q ≈ δ_ss - KQ * 0.4 atol = 1e-12
        # δ_max binds ⇒ clamped EXACTLY at the bound and `defl_sat` set (slice-15's DEFLECTION cap
        # — the FOURTH cap in this plant, and an IMPLICIT α ceiling at ≈(Cmd/|Cma|)·δ_max. The
        # showcase pins defl_sat == 0 so it is provably NOT binding while α_max is — FINDING 2).
        δ_c, dc = alpha_autopilot_delta(0.9, 0.0, 0.0, p19; k_alpha = KA, k_q = KQ, delta_max = 0.4)
        @test δ_c == 0.4
        @test dc == true
        @test alpha_autopilot_delta(-0.9, 0.0, 0.0, p19; k_alpha = KA, k_q = KQ, delta_max = 0.4)[1] == -0.4
        # Cmδ ≈ 0 (no fin authority): the feedforward DROPS rather than dividing by zero — the
        # feedback survives, δ stays finite. (M = Cmδ·δ = 0 anyway: the fin is simply irrelevant.)
        p_nofin = stable(Cma = -1.0, Cmd = 0.0, Cmq = -150.0, Cla = 20.0)
        δ_nf, _ = alpha_autopilot_delta(0.12, 0.0, 0.0, p_nofin; k_alpha = KA, k_q = KQ, delta_max = 0.5)
        @test isfinite(δ_nf)
        @test δ_nf ≈ KA * 0.12 atol = 1e-15                 # feedforward gone, feedback remains
    end

    @testset "slice-19: the CLOSED-LOOP α step — no steady-state error (why :ff_fb won)" begin
        # The (V,γ)-FROZEN α-step response (the slice-16 isolation reused as a test technique —
        # it separates the closed-loop rotational dynamics from the engagement). The gate-0 pick's
        # whole claim: `:ff_fb` settles ON the command, damped. The two halves it beat: feedforward
        # ALONE rings (+68…+96% overshoot — only aero damping opposes it), feedback ALONE carries a
        # steady-state undershoot (the arm below pins it against its closed form).
        # T = 6 s: the shipped gains (k_α=1, k_q=0.3) are SLOWER than the probe's k_α=5, so the
        # residual is 1.8e-9 at 4 s but 1.9e-13 by 6 s (floor 2.9e-15 by 8 s) — probed, not guessed.
        pstep = AirframeParams(S, d, 20.0, -1.0, 3.0, -150.0, ρ, 20.0)   # the PICK's I = 20
        α_cmd = 0.15; γf = 0.0; Vf = 700.0; dt = 1e-3; T19 = 6.0

        # A local (V,γ)-frozen closed-loop driver. `law` is the δ rule under test — the SHIPPED one
        # for the real arms, a feedback-ONLY stand-in for the contrast arm below.
        function αstep(law; cmd)
            θ, q, δ = 0.0, 0.0, 0.0; peak = 0.0
            for _ in 1:round(Int, T19 / dt)
                qdd = (th, qq) -> pitch_moment(th - γf, δ, qq, Vf, pstep) / pstep.I
                θ, q = rk4_rot(qdd, θ, q, dt)
                peak = max(peak, abs(θ - γf))
                δ = law(cmd, θ - γf, q)
            end
            return (α = θ - γf, q = q, δ = δ, peak = peak)
        end
        ff_fb = (cmd, α, q) -> alpha_autopilot_delta(cmd, α, q, pstep;
                                                     k_alpha = KA, k_q = KQ, delta_max = 0.5)[1]

        r = αstep(ff_fb; cmd = α_cmd)
        @test r.α ≈ α_cmd atol = 1e-12                      # settles ON command — NO offset
        @test r.q ≈ 0.0 atol = 1e-12                        # …and at rest, not still ringing
        @test r.peak ≤ α_cmd * 1.05                         # ~0% overshoot (:static rings to +96%)
        # The settled δ IS the trim δ — the loop converges onto the feedforward, feedback → 0.
        @test r.δ ≈ -(pstep.Cma / pstep.Cmd) * α_cmd atol = 1e-12
        # The command is TRACKED, not merely approached from one side: a NEGATIVE step settles too
        # (the mirror — an asymmetric law would pass the positive step alone).
        @test αstep(ff_fb; cmd = -α_cmd).α ≈ -α_cmd atol = 1e-12

        # WHY THE FEEDFORWARD IS LOAD-BEARING, not decoration — the contrast, pinned against an
        # EXTERNAL closed form (convention 11: hand-derived, not read off the implementation).
        # Feedback ALONE balances k_α·(α_cmd−α)·Cmδ against Cmα·α, settling at
        #     α_ss = Cmδ·k_α/(Cmδ·k_α − Cmα)·α_cmd = 3/(3+1) = 3/4 of command — a 25% UNDERSHOOT,
        # which is **the slice-9 `1/(1+Kp)` undershoot recurring, one loop deeper** (gate-0
        # FINDING 4 measured the same closed form at ITS probe gains: 5/6 = −16.67%). The shipped
        # law removes it EXACTLY — that gap (0.0375 rad) is 10 orders of magnitude above the
        # atol above, so these two arms genuinely separate the laws rather than co-passing.
        fb_only = (cmd, α, q) -> clamp(KA * (cmd - α) - KQ * q, -0.5, 0.5)
        rfb = αstep(fb_only; cmd = α_cmd)
        α_ss_form = pstep.Cmd * KA / (pstep.Cmd * KA - pstep.Cma) * α_cmd
        @test rfb.α ≈ α_ss_form atol = 1e-12                # the undershoot IS the closed form
        @test rfb.α ≈ 0.75 * α_cmd atol = 1e-12             # …= 3/4 exactly at these gains
        @test α_cmd - rfb.α > 0.03                          # a REAL error the feedforward kills
    end

    # ── SLICE 20 — INDUCED DRAG: the bill for the lift (C_Di = K·C_L², along −v̂) ──
    # The teeth, in the order they'd catch a real bug:
    #   • K = 0 ⇒ EXACTLY zero (`==`) — slices 17/19's "lift is drag-free" approximation restored,
    #     and the additivity guarantee for every prior slice.
    #   • the DIRECTION: ∥ −v̂ and ⟂ n̂ — `induced_drag_accel` is `lift_accel`'s orthogonal
    #     complement (the #1 sign trap: a leaked ⟂ component would be a second, unnamed lift that
    #     a magnitude-only test would never see; a sign flip would be a drag that ACCELERATES).
    #   • EVEN in α (C_L²) — the bill doesn't care WHICH WAY you turn. An odd-in-α slip (dropping
    #     the square, or `abs`) survives a positive-α-only test.
    #   • the CLOSED FORM by hand, explicit atol (convention 11 — never rtol-`≈0`).
    #   • the ⟂/∥ SPLIT vs `lift_accel` on the SAME α — the two terms partition the aero force.
    afp20(; Cla = 20.0, Kd = 0.0) = AirframeParams(S, d, 20.0, -1.0, 3.0, -150.0, ρ, Cla, Kd)

    @testset "slice-20: K = 0 ⇒ EXACTLY zero (lift is drag-free again — the additivity tooth)" begin
        # `==`, not `≈`: slices 16–19 must be BIT-identical, and the 8-arg AirframeParams (their
        # construction site) must default K to 0. A "calibrated to pass" atol would hide a
        # `-0.0`-shaped regression — the mismatched-EP-no-op precedent (convention 11).
        vel = Vec3(700.0, 0.0, 0.0)
        @test induced_drag_accel(vel, 0.15, 140.0, afp20(Kd = 0.0)) == Vec3(0.0, 0.0, 0.0)
        # The 8-arg form (slices 16–19's sites, VERBATIM) must BE the K = 0 airframe.
        p8 = AirframeParams(S, d, 20.0, -1.0, 3.0, -150.0, ρ, 20.0)
        @test p8.K == 0.0
        @test induced_drag_accel(vel, 0.15, 140.0, p8) == Vec3(0.0, 0.0, 0.0)
        # α = 0 costs EXACTLY nothing even with K on — THE discriminator vs parasitic `cd_area`,
        # which bills a straight flight anyway (gate-0 FINDING 4: 0.06 m/s vs 75–136 m/s over the
        # same fly-out). This is the α²-SOURCE that earns the slice its title.
        @test induced_drag_accel(vel, 0.0, 140.0, afp20(Kd = 0.3)) == Vec3(0.0, 0.0, 0.0)
        # …and with NO lift curve there is no lift to bill for, at any α.
        @test induced_drag_accel(vel, 0.15, 140.0, afp20(Cla = 0.0, Kd = 0.3)) == Vec3(0.0, 0.0, 0.0)
    end

    @testset "slice-20: DIRECTION — ∥ −v̂, ⟂ n̂ (the #1 trap: drag must SLOW, never TURN)" begin
        mass = 140.0; p = afp20(Kd = 0.3)
        # A CLIMBING missile, so a frame slip cannot hide behind γ = 0 (the slice-17 tooth's shape).
        γc = 0.4; Vc = 700.0
        vel = Vec3(Vc*cos(γc), 0.0, Vc*sin(γc))
        aD = induced_drag_accel(vel, γc + 0.12, mass, p)             # α = +0.12
        v̂ = (1/Vc) * vel
        n̂ = Vec3(-sin(γc), 0.0, cos(γc))                             # `lift_accel`'s direction
        @test dot3(aD, v̂) < 0.0                                      # OPPOSES motion — it is DRAG
        @test dot3(aD, n̂) ≈ 0.0 atol = 1e-12                         # …and turns NOTHING (⟂ n̂)
        # It is ANTI-parallel to v, exactly: |dot(â, v̂)| = 1.
        @test dot3((1/mag(aD)) * aD, v̂) ≈ -1.0 atol = 1e-12
        @test aD[2] == 0.0                                            # pitch plane — no y (§1)
        # THE ORTHOGONAL COMPLEMENT: on the SAME α, lift is ⟂ v and drag is ∥ v. Together they
        # partition the aero force — neither can do the other's job.
        aL = lift_accel(vel, γc + 0.12, mass, p)
        @test dot3(aL, v̂) ≈ 0.0 atol = 1e-9                          # lift turns, never slows
        @test dot3(aL, aD) ≈ 0.0 atol = 1e-9                          # …so the two are ⟂
    end

    @testset "slice-20: EVEN in α (C_L²) — the bill ignores WHICH WAY you turn" begin
        mass = 140.0; p = afp20(Kd = 0.3); vel = Vec3(700.0, 0.0, 0.0)   # γ = 0 ⇒ α = θ
        up   = induced_drag_accel(vel,  0.12, mass, p)
        down = induced_drag_accel(vel, -0.12, mass, p)
        @test up == down                                              # EVEN — bit-for-bit, not ≈
        # …while LIFT is ODD in α (it flips) — the pair proves the square is really there. Dropping
        # the `^2` (or writing `abs`) would make drag odd too and this contrast would collapse.
        @test lift_accel(vel, 0.12, mass, p)[3] ≈ -lift_accel(vel, -0.12, mass, p)[3] atol = 1e-12
        # QUADRATIC, not linear: doubling α QUADRUPLES the bill (α² — the polar's whole content).
        a1 = mag(induced_drag_accel(vel, 0.05, mass, p))
        a2 = mag(induced_drag_accel(vel, 0.10, mass, p))
        @test a2 ≈ 4.0 * a1 atol = 1e-9
    end

    @testset "slice-20: the CLOSED FORM by hand (explicit atol — convention 11)" begin
        # a_ind = Q·S·K·(C_Lα·α)² / m, hand-computed here from the DEFINITION rather than read off
        # the implementation. γ = 0 ⇒ v̂ = +x ⇒ the whole bill lands on −x.
        mass = 140.0; Vt = 700.0; Kd = 0.3; Cla = 20.0; α = 0.12
        p = afp20(Cla = Cla, Kd = Kd)
        vel = Vec3(Vt, 0.0, 0.0)
        Qt = 0.5 * ρ * Vt^2
        expect = Qt * S * Kd * (Cla * α)^2 / mass                     # ≈ 194.0 m/s²
        aD = induced_drag_accel(vel, α, mass, p)
        @test aD[1] ≈ -expect atol = 1e-9                             # −x: pure deceleration
        @test aD[3] ≈ 0.0 atol = 1e-12
        @test mag(aD) ≈ expect atol = 1e-9
        # LINEAR in K (it is a lumped factor, so the knob must scale the bill exactly) …
        @test mag(induced_drag_accel(vel, α, mass, afp20(Cla = Cla, Kd = 2*Kd))) ≈ 2*expect atol = 1e-9
        # … and ∝ Q ∝ V² — the coupling that closes the loop: as V bleeds, the bill shrinks too.
        # (Half the speed ⇒ a QUARTER of the Q ⇒ a quarter of the bill.)
        @test mag(induced_drag_accel(Vec3(Vt/2, 0.0, 0.0), α, mass, p)) ≈ expect/4 atol = 1e-9
    end

    @testset "slice-20: degenerates — a live knob can never crash a tick (convention 5)" begin
        mass = 140.0; p = afp20(Kd = 0.3)
        # V → 0 (launch/apex): the ÷V in v̂ = v/V is the crash site (the `lift_accel` precedent).
        @test induced_drag_accel(Vec3(0.0, 0.0, 0.0), 0.15, mass, p) == Vec3(0.0, 0.0, 0.0)
        @test induced_drag_accel(Vec3(1e-9, 0.0, 0.0), 0.15, mass, p) == Vec3(0.0, 0.0, 0.0)
        # Everything finite across the knob's shipped range at a plausible flight condition — the
        # `_finite` wire contract starts here (convention 6: no Inf/NaN can reach JSON).
        for Kd in (0.0, 0.05, 0.15, 0.3), αt in (-0.2, 0.0, 0.2)
            a = induced_drag_accel(Vec3(700.0, 0.0, 0.0), αt, mass, afp20(Kd = Kd))
            @test all(isfinite, (a[1], a[2], a[3]))
        end
        # C_Lα < 0 (the slice-17/19 slider reaches −5): lift flips, but the BILL DOES NOT — C_L² is
        # even in C_Lα too. A negative lift-curve slope still costs you speed to use.
        @test mag(induced_drag_accel(Vec3(700.0, 0.0, 0.0), 0.12, mass, afp20(Cla = -20.0, Kd = 0.3))) ≈
              mag(induced_drag_accel(Vec3(700.0, 0.0, 0.0), 0.12, mass, afp20(Cla = 20.0, Kd = 0.3))) atol = 1e-9
    end

    @testset "slice-20: ⭐ THE SPIRAL, in the primitives — lift ⟂ v holds speed, drag ∥ v eats it" begin
        # The gate-0 lesson reduced to its smallest honest form (the (V,γ)-frozen technique will
        # NOT do here — the whole point is that V is NOT frozen). Fly a STEADY-α turn twice: once
        # with K = 0 (slice 17/19's plant) and once with K > 0, gravity OFF so the ONLY difference
        # is the bill. Then read `aero_accel_limit` — THE ceiling — at the end of both.
        mass = 140.0; α = 0.12; V0 = 700.0; dt = 1e-3; T = 3.0
        function fly(Kd)
            p = afp20(Kd = Kd)
            pos, vel = Vec3(0.0, 0.0, 0.0), Vec3(V0, 0.0, 0.0)
            θ = α                                              # γ = 0 ⇒ hold α by holding θ ≈ γ+α
            for _ in 1:round(Int, T/dt)
                f = (P, Vv, TH, Q) -> begin
                    γ = atan(Vv[3], Vv[1])
                    aero = lift_accel(Vv, TH, mass, p) + induced_drag_accel(Vv, TH, mass, p)
                    (Vv, aero, Q, 0.0)                         # q̈ = 0: θ is DRIVEN, not dynamic
                end
                # Hold α constant by carrying θ with γ (an ideal autopilot — isolates the drag).
                pos, vel, _, _ = rk4_coupled(f, pos, vel, θ, 0.0, dt)
                θ = atan(vel[3], vel[1]) + α
            end
            return (V = mag(vel), ceil = aero_accel_limit(mag(vel), mass, afp20(Kd = Kd);
                                                          alpha_max = 0.2))
        end
        free = fly(0.0)       # lift is DRAG-FREE — slices 17/19's named approximation
        paid = fly(0.3)       # …and now it isn't
        # The thresholds below are MEASURED on this exact 3 s constant-α turn (free.V = 700.000,
        # paid.V = 467.30, ratio = 0.4456), then loosened for margin — NOT guessed and NOT
        # calibrated-to-pass (convention 11: an earlier draft guessed them from the ENGAGEMENT's
        # numbers and failed; the physics was right and the guesses were wrong).
        # 1. THE APPROXIMATION THIS SLICE CASHES: with K = 0, a hard 3 s turn is SPEED-FREE.
        @test free.V ≈ V0 atol = 1e-6                          # measured: 700.0000000000181
        # 2. THE BILL: the SAME turn, K on, bleeds the missile hard (measured ΔV = 232.7 m/s).
        @test paid.V < 500.0                                   # measured 467.30
        @test V0 - paid.V > 200.0                              # measured 232.70 — a THIRD of V0
        # 3. ⭐ THE SPIRAL: the ceiling FELL — and nobody lowered it. ρ, S, C_Lα, α_max and mass
        #    are all IDENTICAL between the two arms; ONLY the turn's own bill differs. The g you
        #    pull is paid for out of the g you can pull — a DEGENERATIVE spiral, NOT a "positive
        #    feedback loop" (the speed bleed is SELF-LIMITING: ∝V²α² ⇒ V asymptotes; see airframe.jl).
        @test free.ceil ≈ aero_accel_limit(V0, mass, afp20(); alpha_max = 0.2) atol = 1e-4
        @test paid.ceil < 0.5 * free.ceil                      # measured 0.4456 — the ceiling HALVES
        # 4. …and it fell BECAUSE of the speed, not by some other route: the ceiling ∝ V² EXACTLY.
        #    This is the tightest tooth in the set (it agrees to ~1e-16) and it is what makes the
        #    loop a LOOP: the bill is paid in V, and V² is what sets the ceiling.
        @test paid.ceil / free.ceil ≈ (paid.V / free.V)^2 atol = 1e-12
    end
end
