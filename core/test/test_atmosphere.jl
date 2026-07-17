# test_atmosphere.jl — the exponential atmosphere ρ(z) = ρ₀·exp(−z/H) vs closed forms
# (slice 21 gate 1).
#
# Deterministic, like terrain (slice 18) and geometry (slice 5): every check is an exact
# closed form with an EXPLICIT atol (never rtol-`≈0`; convention 11). The teeth, in order:
# hand-computed density LITERALS (a re-typed formula cannot self-confirm), the z = 0 identity
# BIT-EXACT (this is what makes the rung's two arms agree at the ground), the e-folding at
# z = H, strict monotonicity in z, the H → ∞ limit (the LIMIT the rung exists because no
# slider reaches), the negative-z floor and the H floor (convention 5/6 — a live knob can
# never crash a tick), and the ATMOSPHERE_MODES contract.

@testset "exponential atmosphere ρ(z) (slice 21 gate 1)" begin

    @testset "densities vs hand-computed literals" begin
        # ρ(z) = 1.225·exp(−z/8500). Hand-evaluated, NOT re-typed from the source:
        #   z = 8500  → 1.225·e^(−1)      = 1.225·0.36787944117144233 = 0.45065231…
        #   z = 4250  → 1.225·e^(−0.5)    = 1.225·0.60653065971263342 = 0.74300005…
        #   z = 17000 → 1.225·e^(−2)      = 1.225·0.13533528323661270 = 0.16578572…
        @test air_density(8500.0)  ≈ 0.45065231543501685 atol = 1e-12
        @test air_density(4250.0)  ≈ 0.74300005814797594 atol = 1e-12
        @test air_density(17000.0) ≈ 0.16578572196485056 atol = 1e-12
        # a NON-default scale height + reference: ρ₀ = 1.0, H = 5000 at z = 10000 → e^(−2)
        @test air_density(10000.0; rho0 = 1.0, H = 5000.0) ≈ 0.13533528323661270 atol = 1e-12
        # THE SHOWCASE NUMBERS (slice 21 gate 0 F4/F6 — the ρ-factor headline). Earth's real
        # scale height, at the launch and intercept heights of slice21_atmosphere.yaml. These
        # are the ENDS of the 4.4× ρ-factor collapse the lesson headlines.
        @test air_density( 1000.0) / 1.225 ≈ 0.889 atol = 1e-3        # launch  ρ/ρ₀ ≈ 0.889
        @test air_density(13570.0) / 1.225 ≈ 0.203 atol = 1e-3        # CPA     ρ/ρ₀ ≈ 0.203
    end

    @testset "the z = 0 identity is BIT-EXACT (the rung's two arms agree at the ground)" begin
        # `==`, not `≈`: at z = 0 the `:exponential` arm must return the authored `rho0`
        # UNCHANGED — `exp(-0.0/H) == 1.0` exactly, and `ρ₀*1.0 == ρ₀`. This is what lets the
        # scenario reinterpret the authored `rho` as "the density AT SEA LEVEL" without the two
        # rungs disagreeing at the reference height (a calibrated ≈ would hide a real offset).
        @test air_density(0.0) == 1.225
        @test air_density(0.0; rho0 = 0.9, H = 3000.0) == 0.9
        @test air_density(0.0; rho0 = 1.0, H = 1.0e9) == 1.0
    end

    @testset "the e-folding: ρ(H)/ρ₀ == e^(−1) for ANY H (H IS the scale height)" begin
        # The EXTERNAL anchor (convention 11): `H` is not a free curve-fit parameter, it is
        # DEFINED as the rise over which the air thins by a factor of e. Pin the definition
        # itself, at several H — a wrong sign or a stray 2 would survive a single-H check.
        for H in (1000.0, 5000.0, 8500.0, 25000.0)
            @test air_density(H; rho0 = 1.0, H = H) ≈ exp(-1.0) atol = 1e-15
            @test air_density(2H; rho0 = 1.0, H = H) ≈ exp(-2.0) atol = 1e-15
        end
    end

    @testset "strictly decreasing in z (the GRADIENT — the whole physical content)" begin
        prev = air_density(0.0)
        for z in 500.0:500.0:30000.0
            ρ = air_density(z)
            @test ρ < prev                     # STRICT — a flat step would be a constant profile
            @test ρ > 0.0                      # never negative, never zero in the live range
            prev = ρ
        end
    end

    @testset "the H → ∞ limit IS constant ρ (the limit NO slider reaches — why the rung exists)" begin
        # The rung's whole justification: `:constant` is `H = ∞`, a LIMIT POINT. A finite H only
        # APPROACHES it — which is why `:constant` is a distinct code path and not a knob value.
        # Pin BOTH halves: the limit is real (huge H → ρ₀), AND convergence is SLOW enough that
        # no sane slider reaches it (at z = 14 km even H = 1e5 is still 13% down — a slider would
        # need SIX orders of magnitude, which is the measured fact behind the design decision).
        # atol 1e-6, not 1e-9, and the gap is the POINT: at H = 1e12 the residual is
        # ρ₀·(14000/1e12) ≈ 1.7e-8 — the limit is APPROACHED, never reached. A tighter atol
        # fails on real physics, not on a bug (it did, first run).
        @test air_density(14000.0; H = 1.0e12) ≈ 1.225 atol = 1e-6
        @test air_density(14000.0; H = 1.0e12) != 1.225            # …and never EQUAL, for any finite H
        @test air_density(14000.0; H = 1.0e5)  <  1.225 * 0.88     # still 12%+ down at H = 100 km
        @test air_density(14000.0; H = 2.5e4)  <  1.225 * 0.60     # the knob's own max: 40%+ down
    end

    @testset "degenerates: a live knob can NEVER crash a tick (conventions 5/6)" begin
        # z < 0 is FLOORED to 0 ⇒ ρ ≤ ρ₀ (below the reference the model stops thickening). An RK4
        # STAGE legitimately probes z < 0 near the ground, and exp(−z/H) at a catastrophically
        # negative z mints Inf → NaN pos → an invalid frame.
        @test air_density(-1.0)    == air_density(0.0)
        @test air_density(-5000.0) == 1.225
        @test air_density(-1.0e12) == 1.225                    # would be Inf unfloored
        @test isfinite(air_density(-1.0e300))
        # H → 0 with z = 0 is `0/0 = NaN` — THE crash path this floor exists for.
        @test isfinite(air_density(0.0; H = 0.0))
        @test !isnan(air_density(0.0; H = 0.0))
        @test air_density(0.0; H = 0.0) == 1.225               # the z=0 identity survives the floor
        @test air_density(0.0; H = -100.0) == 1.225            # a negative H floors too
        @test air_density(1000.0; H = 0.0) == 0.0              # an airless world: exp(−1000/1) → 0
        @test isfinite(air_density(1000.0; H = -100.0))
        # a huge z underflows exp to EXACTLY 0 (vacuum) — finite by itself, no guard needed
        @test air_density(1.0e9) == 0.0
        @test isfinite(air_density(1.0e300))
        # ρ₀ = 0 (a vacuum world) is legal and stays exactly 0 at every height
        @test air_density(5000.0; rho0 = 0.0) == 0.0
    end

    @testset "ATMOSPHERE_MODES — the one-list-no-drift contract (convention 7)" begin
        @test ATMOSPHERE_MODES == (:constant, :exponential)
        @test ATMOSPHERE_MODES[1] === :constant        # the DEFAULT arm = slices 8–20's physics
        @test length(ATMOSPHERE_MODES) == 2
        # referenced ONCE by LIVE_FIDELITY_MODES — never re-listed (the drift-catch)
        @test EWSim.LIVE_FIDELITY_MODES.atmosphere === ATMOSPHERE_MODES
    end
end
