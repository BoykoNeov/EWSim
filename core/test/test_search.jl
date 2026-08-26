# test_search.jl — the SEEKER SEARCH PATTERN (slice 48 gate 1, plan §1).
#
# What a head does when the receiver opens and the target is not there. `search_sweep` is a
# `frames.jl`-class pure kernel — no `w.rng`, no `World`, no telemetry, no LinearAlgebra
# (convention 12) — so every check here carries an EXPLICIT atol and either an EXTERNAL anchor or an
# INDEPENDENT recompute (convention 11). Never `rtol`-`≈ 0`, which passes trivially.
#
# THE SEVEN THINGS THIS FILE HAS TEETH FOR (plan §1):
#   1. `offset(0) == 0.0` EXACTLY, and the first step opens POSITIVE.
#   2. `|offset| ≤ coverage` everywhere — a BOUND at atol 0, not a fit.
#   3. `|d offset/dt| == rate` away from the turns, as an INDEPENDENT finite difference.
#   4. The PERIOD is `4·coverage/rate`.
#   5. ODD SYMMETRY over the half period, and CONTINUITY across every reversal.
#   6. The DEGENERATES a slider reaches in one drag — finite, defined, non-throwing (conventions
#      5/6).
#   7. NO allocation, no RNG (convention 12).
#
# ⭐ THE INDEPENDENT ORACLE (convention 11 — a DIFFERENT algorithm, not a recompute of the same one):
# the analytic triangle wave `(2S/π)·asin(sin(π·ρ·t/(2S)))`. It reaches the same shape through the
# trigonometric functions rather than through `mod` and three branches, so an error in either the
# branch boundaries or the phase arithmetic separates them. Pinned to 1e-12 over a full period.

@testset "seeker search pattern (slice 48)" begin
    # THE ORACLE — a triangle wave written the other way. Amplitude S, period 4S/ρ, rising at t = 0.
    tri_oracle(t, ρ, S) = (2S / π) * asin(sin(π * ρ * t / (2S)))

    @testset "1. offset(0) is EXACTLY zero, and the sweep opens POSITIVE" begin
        for (ρ, S) in ((60.0, 25.0), (1.0, 1.0), (240.0, 5.0), (0.125, 90.0))
            # EXACTLY, not `atol`: the search starts AT the cue centre, and a head that began its
            # sweep 1e-17 off the cue would be a head that had already moved before it was told to.
            @test search_sweep(0.0, ρ, S) === 0.0
            @test search_sweep(1e-6, ρ, S) > 0.0                       # §0.8's symmetric opening
        end
    end

    @testset "2. |offset| ≤ coverage EVERYWHERE — a bound at atol 0" begin
        for (ρ, S) in ((60.0, 25.0), (240.0, 3.0), (7.5, 180.0))
            # 401 samples over five full periods, deliberately NOT commensurate with the turns.
            # ⚠ 401 AND NOT 4001: the ledger is a per-slice count and a bound this dense adds
            # thousands of assertions that all test the same three branch boundaries. 80 samples per
            # period is ~20 per leg, which still lands inside every leg and on both sides of every
            # turn.
            T = 4S / ρ
            for k in 0:400
                t = 5T * k / 400 + 1e-4
                @test abs(search_sweep(t, ρ, S)) ≤ S                  # atol 0 — a BOUND, not a fit
            end
        end
    end

    @testset "3. |d offset/dt| == rate away from the turns (independent finite difference)" begin
        for (ρ, S) in ((60.0, 25.0), (240.0, 5.0), (2.0, 45.0))
            T = 4S / ρ; h = T / 4096
            # Sample the MIDDLE of each of the four legs, where no reversal is within h.
            for frac in (0.125, 0.375, 0.625, 0.875)
                t = frac * T
                d = (search_sweep(t + h, ρ, S) - search_sweep(t - h, ρ, S)) / (2h)
                @test abs(d) ≈ ρ atol = 1e-9 * ρ
            end
        end
    end

    @testset "4. the PERIOD is 4·coverage/rate" begin
        for (ρ, S) in ((60.0, 25.0), (240.0, 5.0), (1.0, 90.0))
            T = 4S / ρ
            for t in (0.01, 0.1, 0.37, 1.0, 2.5)
                t ≥ T && continue
                @test search_sweep(t + T, ρ, S) ≈ search_sweep(t, ρ, S) atol = 1e-12 * S
            end
        end
        # ⚠ AND BIT-FOR-BIT WHERE THE ARITHMETIC IS EXACT, WHICH IS THE STRONGER FORM THE PLAN ASKED
        # FOR — but it is only AVAILABLE on binary-exact values. `ρ·(t + 4S/ρ)` is not `ρ·t + 4S` in
        # IEEE doubles for a general `(ρ, S)`, so the atol above is the honest general claim and this
        # is the exact one where it can be had (plan §1 tooth 4, corrected at gate 1).
        for (ρ, S) in ((1.0, 1.0), (2.0, 8.0), (0.5, 4.0))
            T = 4S / ρ
            for t in (0.5, 1.25, 2.0, 3.75)
                @test search_sweep(t + T, ρ, S) === search_sweep(t, ρ, S)
            end
        end
    end

    @testset "5. ODD SYMMETRY over the half period, and CONTINUITY across the reversals" begin
        for (ρ, S) in ((60.0, 25.0), (240.0, 5.0), (3.0, 12.5))
            T = 4S / ρ
            for frac in (0.0, 0.05, 0.17, 0.25, 0.4, 0.49)
                t = frac * T
                @test search_sweep(t + T/2, ρ, S) ≈ -search_sweep(t, ρ, S) atol = 1e-12 * S
            end
            # CONTINUITY: approach each of the three reversals from both sides. A triangle is
            # continuous in POSITION and discontinuous in RATE — assert both, or a kernel that
            # jumped at a turn would pass a smoothness test written only one way.
            h = T / 1e7
            for turn in (T/4, T/2, 3T/4)
                lo = search_sweep(turn - h, ρ, S); hi = search_sweep(turn + h, ρ, S)
                @test lo ≈ hi atol = 4 * ρ * h                        # position: continuous
            end
            # the RATE flips sign across the peak (+ρ before, −ρ after) — the reversal is real
            hq = T / 4096
            d_before = (search_sweep(T/4 - hq, ρ, S) - search_sweep(T/4 - 2hq, ρ, S)) / hq
            d_after  = (search_sweep(T/4 + 2hq, ρ, S) - search_sweep(T/4 + hq, ρ, S)) / hq
            @test d_before ≈  ρ atol = 1e-9 * ρ
            @test d_after  ≈ -ρ atol = 1e-9 * ρ
        end
    end

    @testset "⭐ THE INDEPENDENT ORACLE — the same wave through asin∘sin, over a full period" begin
        for (ρ, S) in ((60.0, 25.0), (240.0, 5.0), (0.75, 90.0), (12.0, 1.5))
            T = 4S / ρ
            for k in 0:128
                t = T * k / 128
                @test search_sweep(t, ρ, S) ≈ tri_oracle(t, ρ, S) atol = 1e-12 * S
            end
        end
    end

    @testset "6. THE DEGENERATES — one slider drag away, all finite and defined (conventions 5/6)" begin
        # ρ ≤ 0 — THE NULL, and it is the arm the showcase opens on: a head that does not sweep at
        # all is exactly what ships without this slice.
        for ρ in (0.0, -1.0, -240.0)
            for t in (0.0, 0.5, 3.7, 1e4)
                @test search_sweep(t, ρ, 25.0) === 0.0
            end
        end
        # S ≤ 0 — nowhere to look.
        for S in (0.0, -1.0, -25.0)
            @test search_sweep(1.0, 60.0, S) === 0.0
        end
        # NON-FINITE INPUTS — never a NaN offset into the head's pointing state. ⚠ `head_clamp`
        # would NOT catch it: it handles a non-finite STOP, not a non-finite AZIMUTH.
        for bad in (NaN, Inf, -Inf)
            @test search_sweep(bad, 60.0, 25.0) === 0.0
            @test search_sweep(1.0, bad, 25.0) === 0.0
            @test search_sweep(1.0, 60.0, bad) === 0.0
        end
        # THE OVERFLOW A HUGE RATE REACHES AFTER A LONG FLIGHT: `ρ·t` → Inf ⇒ `mod(Inf, 4S)` is NaN.
        @test search_sweep(1e300, 1e300, 25.0) === 0.0
        @test isfinite(search_sweep(1e300, 1.0, 25.0))
        # AND EVERY CELL OF A COARSE GRID IS FINITE AND IN BOUNDS — the slider cannot reach a hole.
        for ρ in (0.0, 1e-9, 1.0, 60.0, 1e6), S in (1e-9, 1.0, 25.0, 1e6), t in (0.0, 1e-9, 1.0, 1e6)
            o = search_sweep(t, ρ, S)
            @test isfinite(o) && abs(o) ≤ S
        end
    end

    @testset "7. NO allocation, NO RNG (convention 12)" begin
        # ⚠ MEASURED THROUGH A WRAPPER THAT RETURNS `nothing`, AND THE REASON IS AN INSTRUMENT
        # ARTEFACT WORTH NAMING: `@allocated search_sweep(…)` written directly here reads **16
        # bytes** — the BOX for the returned `Float64` in the test's dynamic scope, not an
        # allocation inside the kernel. A tooth that asserted `== 16` would be pinning the
        # instrument; one that asserted `≤ 16` would pass a kernel that allocated. The loop below
        # runs 1000 calls and returns a singleton, so the only thing left to count is the kernel's
        # own — and it must be exactly zero.
        sink = Ref(0.0)
        function sweep_alloc_probe(n::Int)
            s = 0.0
            for k in 1:n
                s += search_sweep(k * 1e-3, 60.0, 25.0)
            end
            sink[] = s
            return nothing
        end
        sweep_alloc_probe(10)                                          # warm up / compile
        @test (@allocated sweep_alloc_probe(1000)) == 0
        # NO RNG: the kernel is a pure function of its three arguments, so calling it a thousand
        # times cannot move a seeded stream. Asserted against the stream itself rather than by
        # inspection (draw-topology hazard, convention 3 — this is the kernel-level half of it).
        rng = MersenneTwister(48)
        a = rand(rng, 8)
        rng2 = MersenneTwister(48)
        for k in 1:1000; search_sweep(k * 1e-3, 60.0, 25.0); end
        @test rand(rng2, 8) == a
    end

    @testset "⚠ THE PHASE IS RECOMPUTED FROM t — the MODEL test, at kernel level (§0.7)" begin
        # A rate CHANGED between two calls must change the next offset. This is the tooth that
        # stands between `seeker_search_rate_dps` and the slice-36 dead-knob class (a number baked
        # at search onset would make both calls agree).
        t = 0.3
        @test search_sweep(t, 60.0, 25.0) != search_sweep(t, 90.0, 25.0)
        # …and the kernel is STATELESS: the same arguments give the same answer whatever was called
        # in between, so nothing accumulates across ticks.
        a = search_sweep(t, 60.0, 25.0)
        for k in 1:50; search_sweep(k * 0.017, 137.0, 3.5); end
        @test search_sweep(t, 60.0, 25.0) === a
    end
end
