# test_aero_curve.jl — the nonlinear aero coefficients: true stall, separation drag, and the
# Cm(α) break (slice 22 gate 1).
#
# Deterministic like atmosphere (21), terrain (18) and geometry (5): every check is an exact
# closed form with an EXPLICIT atol (never rtol-`≈0`; convention 11). The teeth, in order:
#
#   1. the PARITY table — C_L ODD, C_Dsep EVEN, Cm ODD. The #1 sign trap's 4th occurrence
#      (see aero_curve.jl's header): getting C_L even would silently lift the wrong way on
#      every negative-α maneuver.
#   2. the CLOSED-FORM PEAK vs an independent grid maximum (convention 11: a DIFFERENT
#      algorithm as the oracle, not a re-typed formula).
#   3. ⭐ THE HEADLINE IDENTITY — the ceiling ratio ≡ α_stall/α_max, Q/S/C_Lα/m all cancelling.
#      Pinned against gate-0 F8's four MEASURED pairs.
#   4. the PARKING off-state, BIT-EXACT (`===`) — F7, and the reason this slice ships KNOBS and
#      not a rung. Not `≈`: the whole knob-vs-rung argument is that parking reproduces the
#      linear curve EXACTLY over every reachable α, so a calibrated tolerance would beg the
#      question.
#   5. the BREAK pinned BY SIGN, never magnitude (aero_curve.jl's header — the trap is inside
#      the very function slice 16's was found in).
#   6. the DEEP-STALL BOUND — Cm's third slope (F9), which is REQUIRED for physicality: without
#      it α ran to 383497 rad in the probe (a convention-6 crash path).
#   7. CONTINUITY at all three corners, and the degenerates (convention 5/6).
#
# ⚠ NOT TESTED HERE, BY CONSTRUCTION: the `C_L` CONSISTENCY tooth — that `lift_accel` (the turn)
# and `induced_drag_accel` (slice 20's bill) route through ONE `lift_coefficient`. That is the
# sharpest check in the slice, but it is a WIRING claim about airframe.jl and it lands in
# test_airframe.jl at gate 2. Recorded here so it cannot be forgotten by whoever reads gate 1
# and concludes the curve is fully covered. It is not.

@testset "nonlinear aero curves: stall / separation drag / Cm break (slice 22 gate 1)" begin

    # The gate-0 showcase shape (probe FINDINGS F3): α_break = 0.28 sits ABOVE α_stall = 0.20 —
    # the TWO-ANGLE result. Equal angles give the controlled lift-collapse window ZERO width.
    c    = AeroCurveParams(0.20, 1.0, 4.0, 0.28, 8.0, 0.60)
    Cla  = 20.0
    Cma  = -8.0

    @testset "the PARITY table (the #1 sign trap, 4th occurrence)" begin
        for a in 0.0:0.025:1.5
            # C_L is ODD — lift REVERSES with α. Nose-down α pulls the path DOWN.
            @test lift_coefficient(-a, Cla, c) ≈ -lift_coefficient(a, Cla, c) atol = 1e-15
            # C_Dsep is EVEN — drag opposes motion whichever way you pulled.
            @test separation_drag_coefficient(-a, c) == separation_drag_coefficient(a, c)
            # Cm is ODD — a restoring moment must restore TOWARD zero from both sides.
            @test moment_coefficient(-a, Cma, c) ≈ -moment_coefficient(a, Cma, c) atol = 1e-15
        end
        # …and the parity is STRUCTURAL, not an artifact of the sampled grid: spot-check the
        # three regimes of Cm explicitly (below break / above break / above sat).
        @test moment_coefficient(-0.10, Cma, c) == -moment_coefficient(0.10, Cma, c)
        @test moment_coefficient(-0.45, Cma, c) == -moment_coefficient(0.45, Cma, c)
        @test moment_coefficient(-0.90, Cma, c) == -moment_coefficient(0.90, Cma, c)
    end

    @testset "C_L: the stall is REAL — lift PEAKS and then FALLS" begin
        # Below the stall: the slices-17–21 linear curve, exactly.
        @test lift_coefficient(0.10, Cla, c) == Cla * 0.10
        @test lift_coefficient(0.19, Cla, c) == Cla * 0.19
        # AT the stall: both arms agree (continuity by construction) and this IS the peak.
        @test lift_coefficient(0.20, Cla, c) ≈ Cla * 0.20 atol = 1e-15
        # PAST the stall: lift FALLS. This is the entire physical content of the slice — the
        # STRICT inequality is the tooth (a flatline would be k_drop = 0, a different curve).
        @test lift_coefficient(0.30, Cla, c) < lift_coefficient(0.20, Cla, c)
        @test lift_coefficient(0.40, Cla, c) < lift_coefficient(0.30, Cla, c)
        # …and it falls at the AUTHORED rate: k_drop = 1 ⇒ as fast as it rose.
        # C_L(0.30) = 20·0.20 − 1·20·(0.30−0.20) = 4.0 − 2.0 = 2.0
        @test lift_coefficient(0.30, Cla, c) ≈ 2.0 atol = 1e-14
        # k_drop = 0 FLATLINES instead (the authored no-drop shape — still a stall, no recovery)
        cflat = AeroCurveParams(0.20, 0.0, 4.0, 0.28, 8.0, 0.60)
        @test lift_coefficient(0.90, Cla, cflat) == lift_coefficient(0.20, Cla, cflat)
        # k_drop NEVER makes lift RESUME growing past the stall (that would be a negative k_drop
        # — validated out at load; pinned here as the shape contract)
        @test lift_coefficient(0.90, Cla, cflat) <= cl_peak(Cla, cflat)
    end

    @testset "cl_peak — the CLOSED FORM vs an INDEPENDENT grid maximum (convention 11)" begin
        # The oracle is a DIFFERENT algorithm: brute-force max over a fine grid. A re-typed
        # `Cla*alpha_stall` would confirm nothing.
        for cc in (c,
                   AeroCurveParams(0.15, 0.5, 4.0, 0.28, 8.0, 0.60),
                   AeroCurveParams(0.35, 2.0, 4.0, 0.50, 8.0, 0.90))
            grid_max = maximum(lift_coefficient(a, Cla, cc) for a in 0.0:1.0e-5:1.5)
            @test cl_peak(Cla, cc) == grid_max
            # attained exactly AT the stall angle, nowhere else below it
            @test lift_coefficient(cc.alpha_stall, Cla, cc) ≈ cl_peak(Cla, cc) atol = 1e-14
        end
    end

    @testset "⭐ THE HEADLINE IDENTITY: ceiling ratio ≡ α_stall/α_max (gate-0 F8)" begin
        # a_max_aero(linear) = Q·S·|C_Lα|·α_max/m ; a_max_aero(stall) = Q·S·C_L_peak/m
        # ⇒ ratio = (Cla·α_stall)/(Cla·α_max) = α_stall/α_max — Q, S, C_Lα and m ALL CANCEL.
        # A SAME-INPUTS FORMULA comparison (convention 10/11), never run-vs-run — which is
        # exactly why it is EXACT rather than merely close. These are gate 0's four measured
        # pairs; the deltas reproduce F8's table (≤ 1.1e-16).
        for (astall, amax) in ((0.20, 0.35), (0.15, 0.35), (0.25, 0.40), (0.10, 0.50))
            cc    = AeroCurveParams(astall, 1.0, 4.0, 0.28, 8.0, 0.60)
            ratio = cl_peak(Cla, cc) / (Cla * amax)
            @test ratio ≈ astall / amax atol = 1e-15
        end
        # …and the cancellation is REAL, not a coincidence of Cla = 20: sweep the factors that
        # are supposed to drop out and assert the ratio does not move.
        cc = AeroCurveParams(0.20, 1.0, 4.0, 0.28, 8.0, 0.60)
        for Cl in (5.0, 20.0, 137.0)
            @test cl_peak(Cl, cc) / (Cl * 0.35) ≈ 0.20 / 0.35 atol = 1e-15
        end
    end

    @testset "★ THE PARKING OFF-STATE IS BIT-EXACT LINEAR (F7 — why this is a KNOB, not a rung)" begin
        # Park every corner ABOVE the reachable α (gate 0 measured the achieved α self-limiting
        # to ~0.24 across the whole viable geometry family) and all three curves ARE the linear
        # slices-17–21 ones — `===`, to the bit, over every reachable α. This is the measured
        # fact that KILLED the plan's rung claim: the off-state IS knob-reachable, so the
        # slice-21 discriminator (atmosphere.jl's header) returns KNOB.
        cpark = AeroCurveParams(0.35, 1.0, 4.0, 9.9, 8.0, 99.0)
        for a in 0.0:0.005:0.34
            @test lift_coefficient(a, Cla, cpark)     === Cla * a
            @test moment_coefficient(a, Cma, cpark)   === Cma * a
            @test separation_drag_coefficient(a, cpark) === 0.0
        end
        # NEGATIVE α parks identically — the arm the sign trap would break.
        # ⚠ `===` and not `==` everywhere EXCEPT α = 0: `Cla*(-0.0)` is `-0.0` while the odd
        # branch returns `+0.0` (the `-0.0` trap this project has hit before). Numerically
        # identical and harmless downstream (`-0.0 + x == 0.0 + x` for all x), but stated
        # rather than hidden — the parked claim is `===` for a ≠ 0 and `==` at zero.
        for a in 0.005:0.005:0.34
            @test lift_coefficient(-a, Cla, cpark)   === Cla * (-a)
            @test moment_coefficient(-a, Cma, cpark) === Cma * (-a)
        end
        @test lift_coefficient(-0.0, Cla, cpark)   == Cla * (-0.0)
        @test moment_coefficient(-0.0, Cma, cpark) == Cma * (-0.0)
    end

    @testset "C_Dsep: EXACTLY zero below the stall, quadratic above" begin
        # "exactly 0.0", not "small" — a parked α_stall must leave slices 17–21's drag bill
        # untouched TO THE BIT.
        for a in 0.0:0.01:0.199
            @test separation_drag_coefficient(a, c) === 0.0
        end
        @test separation_drag_coefficient(0.20, c) === 0.0        # AT the corner: still zero
        # Above: K_sep·(|α|−α_stall)². At α = 0.30 → 4.0·0.10² = 0.04
        @test separation_drag_coefficient(0.30, c) ≈ 0.04 atol = 1e-15
        @test separation_drag_coefficient(0.45, c) ≈ 4.0 * 0.25^2 atol = 1e-14
        # QUADRATIC, not linear: doubling the excess QUADRUPLES the drag (the shape tooth —
        # a linear bill would pass a single-point check)
        @test separation_drag_coefficient(0.40, c) ≈ 4.0 * separation_drag_coefficient(0.30, c) atol = 1e-14
        # K_sep = 0 ⇒ no bill at any α (the authored off-state for this term alone)
        cnodrag = AeroCurveParams(0.20, 1.0, 0.0, 0.28, 8.0, 0.60)
        @test separation_drag_coefficient(1.20, cnodrag) === 0.0
    end

    @testset "the two drags move OPPOSITE ways past the stall (they are DISTINCT terms)" begin
        # Slice 20's INDUCED drag ∝ C_L² is the price of the turn you GOT; separation drag is
        # the price of the turn you did NOT get. Past the stall C_L collapses, so the induced
        # bill FALLS while the separation bill CLIMBS. If these ever moved together, one of them
        # is mis-wired — this is the tooth that says they are genuinely different physics.
        cl2(a) = lift_coefficient(a, Cla, c)^2
        @test cl2(0.40) < cl2(0.30)                                        # induced FALLS
        @test separation_drag_coefficient(0.40, c) > separation_drag_coefficient(0.30, c)  # sep CLIMBS
    end

    @testset "Cm: the BREAK, pinned BY SIGN — never magnitude (the #1 sign trap)" begin
        # RESTORING below α_break (Cma < 0 ⇒ ∂Cm/∂α < 0): a nose-up disturbance makes a
        # nose-DOWN moment. This is what "statically stable" MEANS.
        @test moment_coefficient(0.20, Cma, c) < moment_coefficient(0.10, Cma, c)
        @test moment_coefficient(0.27, Cma, c) < moment_coefficient(0.20, Cma, c)
        # DIVERGING above it (Cma_post > 0 ⇒ ∂Cm/∂α > 0): the airframe pitches FURTHER up.
        # Getting this backwards makes an unstable airframe self-right and deletes the entire
        # second lesson, while still passing any magnitude-based check.
        @test moment_coefficient(0.45, Cma, c) > moment_coefficient(0.30, Cma, c)
        @test moment_coefficient(0.59, Cma, c) > moment_coefficient(0.45, Cma, c)
        # Below the break it is EXACTLY the slices-16–21 linear term.
        @test moment_coefficient(0.10, Cma, c) === Cma * 0.10
        # Cma_post = 0 ⇒ NEUTRAL past the break (flat) — the intermediate authored shape
        cneutral = AeroCurveParams(0.20, 1.0, 4.0, 0.28, 0.0, 0.60)
        @test moment_coefficient(0.45, Cma, cneutral) ≈ moment_coefficient(0.28, Cma, cneutral) atol = 1e-15
        # Cma_post < 0 ⇒ still restoring, merely LESS so (relaxed, not unstable)
        crelaxed = AeroCurveParams(0.20, 1.0, 4.0, 0.28, -2.0, 0.60)
        @test moment_coefficient(0.45, Cma, crelaxed) < moment_coefficient(0.28, Cma, crelaxed)
    end

    @testset "the DEEP-STALL BOUND: Cm's THIRD slope (F9 — REQUIRED, not polish)" begin
        # Above α_sat the moment is RESTORING again — this is what bounds the divergence into a
        # second high-α equilibrium (deep-stall lock-in). Without it a linear-in-α divergent
        # moment grows unbounded and the probe ran α to 383497 rad: a convention-6 crash path
        # AND an epistemic one (it makes a real tumble indistinguishable from a bug).
        @test moment_coefficient(0.90, Cma, c) < moment_coefficient(0.70, Cma, c)
        @test moment_coefficient(1.50, Cma, c) < moment_coefficient(0.90, Cma, c)
        # THE BOUND ITSELF: Cm must CROSS ZERO somewhere above α_sat — that crossing IS the
        # second equilibrium. Without a third slope Cm stays positive forever and α diverges.
        @test moment_coefficient(0.60, Cma, c) > 0.0            # still diverging at the corner
        @test moment_coefficient(3.00, Cma, c) < 0.0            # restoring hard by the tumble α
        # …and the trim α of that second equilibrium is finite and physical (gate 0 measured the
        # tumble parking near 2.78 rad ≈ 159°). Bracket it rather than pin a magic number.
        αs = 0.60:0.001:3.00
        idx = findfirst(a -> moment_coefficient(a, Cma, c) <= 0.0, collect(αs))
        @test idx !== nothing
        @test 0.60 < collect(αs)[idx] < 3.00
        # a HIGHER α_sat pushes the lock-in further out (the bound is where you author it)
        cfar = AeroCurveParams(0.20, 1.0, 4.0, 0.28, 8.0, 1.20)
        @test moment_coefficient(0.90, Cma, cfar) > moment_coefficient(0.90, Cma, c)
    end

    @testset "CONTINUITY at all three corners (no jump = no impulsive moment/lift)" begin
        # A discontinuity here would inject an instantaneous force step into the RK4 stage —
        # physically wrong and numerically poisonous. Central difference across each corner.
        h = 1.0e-9
        for (f, x) in ((a -> lift_coefficient(a, Cla, c),            c.alpha_stall),
                       (a -> separation_drag_coefficient(a, c),      c.alpha_stall),
                       (a -> moment_coefficient(a, Cma, c),          c.alpha_break),
                       (a -> moment_coefficient(a, Cma, c),          c.alpha_sat))
            @test abs(f(x + h) - f(x - h)) < 1.0e-8
        end
    end

    @testset "degenerates: a live knob can NEVER crash a tick (conventions 5/6)" begin
        # Every one of these is reachable from a slider at an extreme, or from an RK4 stage
        # probing a wild α. None may mint Inf/NaN (convention 6 — a wire NaN drops the session).
        for cc in (c,
                   AeroCurveParams(1.0e-9, 1.0, 4.0, 1.0e-9, 8.0, 1.0e-9),   # corners at ~0
                   AeroCurveParams(1.0e9,  1.0, 4.0, 1.0e9,  8.0, 1.0e9),    # corners parked absurdly
                   AeroCurveParams(0.20,   0.0, 0.0, 0.28,   0.0, 0.60))     # every effect off
            for a in (0.0, -0.0, 1.0e-12, 0.2, -0.2, 3.0, -3.0, 1.0e6, -1.0e6)
                @test isfinite(lift_coefficient(a, Cla, cc))
                @test isfinite(separation_drag_coefficient(a, cc))
                @test isfinite(moment_coefficient(a, Cma, cc))
            end
            @test isfinite(cl_peak(Cla, cc))
        end
        # separation drag is NEVER negative (a negative bill would ACCELERATE the missile —
        # the slice-20 negative-K trap in a new letter)
        for a in -3.0:0.05:3.0
            @test separation_drag_coefficient(a, c) >= 0.0
        end
    end

    @testset "NO mode tuple — the rung question is MEASURED SHUT (F7)" begin
        # Convention 7 (one-list-no-drift) has nothing to bind here, deliberately: slice 22
        # ships KNOBS, so there is no AERO_CURVE_MODES, no LIVE_FIDELITY_MODES entry, no
        # set_fidelity path and no client button. Asserted rather than merely absent, so that
        # adding one later is a DELIBERATE act that breaks a test and forces the argument to be
        # re-made (aero_curve.jl's header: the discriminator says KNOB, and shipping a rung
        # anyway would have to be named a deviation).
        @test !isdefined(EWSim, :AERO_CURVE_MODES)
        @test !hasproperty(EWSim.LIVE_FIDELITY_MODES, :aero_curve)
        @test !hasproperty(EWSim.LIVE_FIDELITY_MODES, :stall)
    end
end
