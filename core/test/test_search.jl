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

# ══════════════════════════════════════════════════════════════════════════════════════════════
# SLICE 52 GATE 1 — THE **COVERAGE** AXIS, AS A LAW OF THE SAME KERNEL (`docs/plans/slice52.md`).
#
# Slice 48 shipped `search_sweep` and varied only its RATE. Slice 52's axis is the other argument,
# the half-amplitude `S`, and gate 0 measured three things about it that NOTHING IN THE REPO
# ENFORCES — they live in the plan doc and in probes under `M:\claud_projects\temp\slice52\`. This
# section is that enforcement, and it is a GATE 1 because every one of them is a property of the
# pure wave rather than of a flight:
#
#   1. THE FIRST NEGATIVE EXTREME IS AT `3S/ρ`, and nothing earlier reaches it. This is the whole
#      mechanism behind gate 0 §IV's *FIRST-EXCURSION-OR-NEVER*: the deficit GROWS while the search
#      runs, so if the band does not cover the target on the first pass out, no later pass will.
#   2. THE SCALE LAW — `t` enters only through `ρt/S`. This is the STRUCTURAL reason `t_lock` comes
#      out very nearly linear in `S`, and it fixes the wave's own contribution to that slope at
#      `2/ρ`. ⚠⚠ IT DOES NOT MAKE THE FLOWN NUMBER A CONSEQUENCE, and gate 0 §II's claim that it
#      does — *"0.04000 s/° = 2/60 to four digits"* — is a FALSE IDENTITY: `2/60` is 0.033333, and
#      the flown chord is 20 % ABOVE it. What the wire adds is the target's own angular motion
#      during the sweep, which no kernel law contains. Retracted and measured in gate 2, tooth C.
#   3. THE `2S` WRONG-HALF LAW — a target at `−a` of the cue is first covered at `(2S + a)/ρ`.
#      Slice 43 banked it on an 8 °/s servo over a ~7 s window; gate 0 measured it on the shipped
#      kernel at 60–240 °/s; here it is an IDENTITY, with the `2/ρ` slope as its derivative.
#      ⚠ AND IT IS THE FIXED-TARGET CASE — a LOWER BOUND on the wire, never the flown cost.
#   + THE MODEL TEST's KERNEL HALF for the coverage (slice 48's §0.7 tooth is RATE-only), and the
#     `S ≤ 0` degenerate across the PHASE rather than at one time — because `S` is slice 52's
#     SLIDER and `S ≤ 0` is its floor, which is a load it did not carry while it was authored.
#
# ⚠ THESE ARE INVARIANCES, NOT A SECOND ORACLE. The independent oracle is `tri_oracle` above; what
# is asserted below are relations BETWEEN points of the same kernel, which is the only honest thing
# a scale law can be. ⚠ And the REACH half of the lesson — *`S < a` and `−a` is never reached, at
# any `t`* — is deliberately NOT a test: it is slice 48's tooth 2 (`|offset| ≤ S`) restated in this
# slice's currency, and convention 11 bans a tautology dressed as a tooth.
# ══════════════════════════════════════════════════════════════════════════════════════════════

@testset "seeker search COVERAGE — the S axis (slice 52 gate 1)" begin

    @testset "1. ⭐⭐ THE FIRST NEGATIVE EXTREME IS AT 3S/ρ — first-excursion-or-never" begin
        for (ρ, S) in ((60.0, 25.0), (60.0, 6.0), (240.0, 5.0), (12.0, 45.0))
            @test search_sweep( S / ρ, ρ, S) ≈  S atol = 1e-12 * S   # …out to the wrong side first
            @test search_sweep(3S / ρ, ρ, S) ≈ -S atol = 1e-12 * S   # …and only THEN to the other
            # ⚠ AND IT IS THE **FIRST** TIME, which is what makes `3S/ρ` a deadline rather than a
            # coincidence. 256 samples strictly inside (0, 3S/ρ) — read as a MINIMUM rather than as
            # 256 assertions, for §2's ledger reason — none of which may have reached −S already.
            @test minimum(search_sweep(3S / ρ * k / 257, ρ, S) for k in 1:256) > -S   # atol 0
        end
        # EXACTLY, where the arithmetic is binary-exact (§4's form, one level up).
        for (ρ, S) in ((1.0, 1.0), (2.0, 8.0), (0.5, 4.0))
            @test search_sweep(3S / ρ, ρ, S) === -S
        end
    end

    @testset "2. ⭐⭐ THE SCALE LAW — t enters ONLY through ρt/S (the unit triangle)" begin
        # `offset(t; ρ, S) = S · f(ρt/S)`, with `f` the unit triangle — amplitude 1, period 4, which
        # is what this same kernel IS at `(ρ, S) = (1, 1)`. ⇒ every time the wave takes to do
        # anything scales as `S/ρ`, which is §II's linear `t_lock` before a missile is involved.
        for (ρ, S) in ((60.0, 25.0), (240.0, 5.0), (7.0, 90.0), (0.5, 1.5))
            for k in 0:32
                t = 1.37 * 4S / ρ * k / 32                 # 1.37 periods — not commensurate
                @test search_sweep(t, ρ, S) ≈ S * search_sweep(ρ * t / S, 1.0, 1.0) atol = 1e-12 * S
            end
        end
    end

    @testset "3. ⭐⭐⭐ THE 2S WRONG-HALF LAW — reaching −a costs (2S + a)/ρ, so dt/dS = 2/ρ" begin
        # The sweep always opens toward +offset (§0.8 — a head that knew which way to look would not
        # need to search), so a target `a` degrees to the WRONG side is not covered until the head
        # has climbed to +S, come back through the cue and gone out to −a. Every degree of coverage
        # is therefore paid TWICE, and THAT is slice 52's sentence.
        for (ρ, a) in ((60.0, 3.0), (240.0, 1.0), (12.0, 8.0))
            for S in (a, 2a, 5.0, 12.5, 25.0, 45.0)
                S < a && continue                  # narrower than the deficit ⇒ never reached at all
                t★ = (2S + a) / ρ
                @test search_sweep(t★, ρ, S) ≈ -a atol = 1e-12 * S
                # …and, again, it is the FIRST time — the cost is paid once, up front, not per pass.
                @test minimum(search_sweep(t★ * k / 257, ρ, S) for k in 1:256) > -a
            end
            # THE SLOPE, as an INDEPENDENT finite difference across S at FIXED a (convention 11):
            # widening the sweep by 1° delays first cover of the SAME target by exactly `2/ρ` s.
            # ⚠⚠ "AT FIXED `a`" IS THE WHOLE CAVEAT, and gate 2 tooth C is where it is paid: on the
            # wire `a` is NOT fixed — the cue walks away from the truth at ~6.85 °/s while the head
            # travels — so this exact derivative is a LOWER BOUND that the flight beats by 20 %.
            for (S1, S2) in ((5.0, 6.0), (12.5, 25.0), (25.0, 45.0))
                S1 < a && continue                 # …the same guard, and it BITES at a = 8°
                @test ((2S2 + a) / ρ - (2S1 + a) / ρ) / (S2 - S1) ≈ 2 / ρ atol = 1e-12
                @test search_sweep((2S2 + a) / ρ, ρ, S2) ≈
                      search_sweep((2S1 + a) / ρ, ρ, S1) atol = 1e-12 * S2
            end
        end
    end

    @testset "4. ⚠ THE COVERAGE IS READ ON EVERY CALL — the MODEL test's KERNEL half" begin
        # Slice 48's §0.7 tooth stands between the RATE and the slice-36 dead-knob class. Slice 52's
        # slider is the OTHER argument and needs its own: a coverage baked at search onset would
        # make these two calls agree. ⚠ Gate 0 §0 recorded MODEL as "PASS **by inspection**"; this
        # is that inspection converted into a tooth, which is the only form the two-test rule's one
        # outright kill may be claimed in.
        # ⚠⚠ AND THE TIME AT WHICH IT IS READ IS THE TRAP, CAUGHT BY THIS TOOTH FAILING ON ITS
        # FIRST RUN AT `t` = 0.3: **A COVERAGE CHANGE IS INVISIBLE UNTIL THE FIRST REVERSAL.** On the
        # opening leg the offset is `ρt` and `S` does not enter it at all, so 25.0° and 25.5°
        # returned the SAME 18.0 and the model test read as a dead knob. `t` = 0.5 is past the turn
        # for both (`S/ρ` = 0.4167 s at the wider one). ⭐ That is §1's mechanism arriving in a place
        # this plan did not expect it — the coverage is not a thing the sweep HAS, it is a thing the
        # sweep does not reach until it has run for `S/ρ`.
        t = 0.5
        @test search_sweep(t, 60.0, 25.0) != search_sweep(t, 60.0, 12.0)
        @test search_sweep(t, 60.0, 25.0) != search_sweep(t, 60.0, 25.5)
        # …and the OPENING LEG is asserted the other way up, so the property above is pinned rather
        # than merely dodged: before `S/ρ` the two ARE equal, and a tooth read there proves nothing.
        @test search_sweep(0.3, 60.0, 25.0) === search_sweep(0.3, 60.0, 25.5) === 18.0
    end

    @testset "5. ⚠ S ≤ 0 IS A **SLIDER FLOOR** NOW — 0.0 at every PHASE, not at one time" begin
        # §6 pins `S ≤ 0` at a single `t`, which was enough while the coverage was an authored
        # constant. It is slice 52's dragged knob, so its floor is reached MID-SWEEP from an
        # arbitrary phase, and the guard is pinned across the phase instead.
        for S in (0.0, -1e-12, -1.0, -25.0), t in (0.0, 1e-9, 0.25, 1.0, 3.7, 1e4)
            @test search_sweep(t, 60.0, S) === 0.0
        end
    end
end

# ══════════════════════════════════════════════════════════════════════════════════════════════
# GATE 2 — THE WIRE. The kernel above is a wave; these are the teeth for the SEAM that feeds it.
#
# ⚠ FLOWN AGAINST THE SHIPPED YAML, not a hand-built fixture (convention 10 — pin against the LIVE
# oracle, never against a second hand-recompute). The base wire is `slice47_midcourse.yaml` with the
# showcase cell's four authored numbers dialled in on the comp bag, which is exactly what gate 3's
# scenario will author: a wider trunnion (45°), a bigger picture error (140 m/s), a smaller target
# (rcs 0.020) and the error direction FLIPPED, so the always-+ sweep opens AWAY from the target.
#
# THE SIX THINGS THIS SECTION HAS TEETH FOR:
#   A. THE NULL IS THE SHIPPED WIRE — ρ = 0 with the anchor is BIT-IDENTICAL to no anchor at all.
#   B. `:search_t0` STAMPS WHEN THE SWEEP STARTS, not when the receiver opened (the drag-up arm).
#   C. THE SEAM SMOKE — the head is commanded to BELIEF + offset, and NEVER to the truth it is
#      hunting for (the `head_tgt` oracle hazard, `docs/DEFERRALS.md`: 3620.675 → 0.110 m).
#   D. THE MODEL TEST — the rate is READ EVERY TICK; changing it mid-search moves the next offset.
#   E. DRAW TOPOLOGY (convention 3) — two ρ consume the SAME number of draws over the same ticks.
#   F. ACQUISITION IS NOT A LATCH — the search RESUMES after a lock that did not survive.
#   + the loader's refusals, each of which is a crash guard or a dead-knob guard.
# ══════════════════════════════════════════════════════════════════════════════════════════════

@testset "seeker search — THE WIRE (slice 48 gate 2)" begin
    scen_dir = joinpath(@__DIR__, "..", "..", "scenarios")
    sl47     = joinpath(scen_dir, "slice47_midcourse.yaml")

    # The gate-3 cell, built on the shipped YAML. `anchor = false` gives the slice-47 wire verbatim.
    function search_scn(; rho = 60.0, cov = 25.0, gain = 140.0, rcs = 0.020,
                          sgn = 1.0, stop = 45.0, anchor = true)
        sc = load_scenario(sl47)
        c  = sc.world.entities[:m1].comp
        c[:midcourse_err_gain]    = gain
        c[:midcourse_vel_err_mps] = Vec3(0.0, sgn, 0.0)
        c[:gimbal_stop_deg]       = stop
        sc.world.entities[:tgt1].comp[:rcs_m2] = rcs
        if anchor
            c[:seeker_search] = true
            c[:seeker_search_coverage_deg] = cov
            c[:seeker_search_rate_dps]     = rho
        end
        sc
    end
    tel_of(sc) = get(sc.world.env, :telemetry, Dict{String,Any}())
    telv(sc, k, d = NaN) = Float64(get(tel_of(sc), "m1.$k", d))

    @testset "A. THE NULL IS THE SHIPPED WIRE — ρ = 0 is BIT-IDENTICAL to no anchor at all" begin
        # ⭐ THE TOOTH THE WHOLE SHOWCASE RESTS ON. The slider's floor must be what ships TODAY — a
        # held head that never acquires — and not "a search with a zero sweep", which would still
        # re-command the head onto the LIVE belief every tick and would be a behaviour nothing has
        # measured. That is why the branch is gated on ρ > 0 as well as on the anchor, and this is
        # the assertion that keeps it that way.
        a = search_scn(rho = 0.0); b = search_scn(rho = 0.0, anchor = false)
        reached = false
        for k in 1:9000
            tick!(a.world, a.subs, a.dt_physics)
            tick!(b.world, b.subs, b.dt_physics)
            # the state the search would own: the receiver hears it, the window does not have it
            telv(a, "seeker_detect", 0.0) == 1.0 && telv(a, "gimbal_valid", 1.0) == 0.0 &&
                (reached = true)
        end
        @test reached                                   # ⚠ or the identity below is VACUOUS
        ma = a.world.entities[:m1]; mb = b.world.entities[:m1]
        @test ma.pos == mb.pos                          # bit-for-bit, not `atol`
        @test ma.vel == mb.vel
        @test ma.comp[:head_az] == mb.comp[:head_az]
        @test ma.comp[:head_el] == mb.comp[:head_el]
        @test telv(a, "head_searching", -1.0) == 0.0    # minted, and honestly zero
        # …and the anchorless wire mints NONE of the new keys (byte-identity ON THE WIRE, the
        # slice-47 shape): a client of slices 34–47 sees exactly what it saw before.
        for k in ("head_searching", "search_offset_deg", "search_deficit_deg",
                  "search_elapsed_s", "search_t_lock_s", "search_rate_dps", "search_coverage_deg")
            @test !haskey(tel_of(b), "m1.$k")
            @test haskey(tel_of(a), "m1.$k")
        end
        # THE "NEVER LOCKED" SENTINEL is −1.0 and not a 0.0 — a search that locks on its first tick
        # is a REAL 0.0, so the two cannot share a value (the arms carrying the lesson never lock).
        @test telv(a, "search_t_lock_s", 0.0) == -1.0
    end

    # Fly to the first tick of the search state and hand back the scenario, still live.
    function fly_to_search!(sc; maxticks = 12000)
        for k in 1:maxticks
            tick!(sc.world, sc.subs, sc.dt_physics)
            telv(sc, "head_searching", 0.0) == 1.0 && return k
        end
        return -1
    end

    @testset "B. `:search_t0` STAMPS AT THE SWEEP, NOT AT HANDOVER (the drag-up arm)" begin
        # ⚠ THE FALSIFIER, WRITTEN DOWN FIRST: a clock stamped when the RECEIVER opened would hand a
        # dragged-up sweep a silent head start — the first commanded offset would be
        # `search_sweep(t_now − t_handover, …)`, some arbitrary point mid-leg, instead of 0. This is
        # the one defect no other test in this file can see.
        sc = search_scn(rho = 0.0)                       # opens at the NULL, like the showcase
        blind = -1
        for k in 1:12000                                 # …fly to well inside the blind window
            tick!(sc.world, sc.subs, sc.dt_physics)
            if telv(sc, "seeker_detect", 0.0) == 1.0 && telv(sc, "gimbal_valid", 1.0) == 0.0
                blind = k; break
            end
        end
        @test blind > 0
        for k in 1:400; tick!(sc.world, sc.subs, sc.dt_physics); end   # 0.4 s of NOT searching
        @test telv(sc, "head_searching", -1.0) == 0.0
        @test telv(sc, "search_elapsed_s", -1.0) == 0.0
        sc.world.entities[:m1].comp[:seeker_search_rate_dps] = 60.0    # ← the drag
        tick!(sc.world, sc.subs, sc.dt_physics)
        @test telv(sc, "head_searching", 0.0) == 1.0
        @test telv(sc, "search_elapsed_s", -1.0) == 0.0                # t0 is NOW
        @test telv(sc, "search_offset_deg", 1.0) == 0.0                # …so the sweep starts at 0
        # and it then walks at exactly the commanded rate (an INDEPENDENT finite difference on the
        # shipped telemetry, not a read-back of the kernel).
        o0 = telv(sc, "search_offset_deg"); tick!(sc.world, sc.subs, sc.dt_physics)
        o1 = telv(sc, "search_offset_deg")
        @test (o1 - o0) / sc.dt_physics ≈ 60.0 atol = 1e-6
    end

    @testset "C. THE SEAM SMOKE — commanded to the BELIEF + offset, NEVER to the truth" begin
        sc = search_scn(rho = 60.0)
        k0 = fly_to_search!(sc)
        @test k0 > 0
        m = sc.world.entities[:m1]; t = sc.world.entities[:tgt1]; c = m.comp
        for k in 1:600
            tick!(sc.world, sc.subs, sc.dt_physics)
            telv(sc, "head_searching", 0.0) == 1.0 || continue
            # 1. THE COMMAND IS THE KERNEL, FED THE SEAM's OWN ELAPSED CLOCK AND CONVERTED ONCE.
            off = rad2deg(search_sweep(telv(sc, "search_elapsed_s"),
                                       deg2rad(telv(sc, "search_rate_dps")),
                                       deg2rad(telv(sc, "search_coverage_deg"))))
            @test telv(sc, "search_offset_deg") ≈ off atol = 1e-9
            # 2. ⚠⚠ THE ORACLE HAZARD. `head_tgt_az` must be the BELIEF direction plus that offset —
            #    never the truth-derived `az_m` the tracking arm writes unconditionally. Recomputed
            #    here from the belief the guidance itself holds.
            #    ⚠⚠ AND THE CLOCK IS THE TRAP, WHICH SLICE 47 ALREADY PAID FOR ONCE (its §6.7):
            #    `tick!` advances `w.t` AFTER `observe!`, so a recompute that reads the POST-tick
            #    `w.t` dead-reckons the belief ONE STEP OF TARGET MOTION too far — 0.2 m at 200 m/s,
            #    a wrong number of exactly the size that reads like a rounding issue. Both clocks
            #    are pinned here, the right one to 1e-12 and the wrong one as a MEASURED miss, so a
            #    future edit cannot quietly swap them. ⚠ The belief is recomputed INLINE rather than
            #    through `_midcourse_belief!` — an INDEPENDENT recompute (convention 11), and the
            #    only way to evaluate it at a time other than `w.t`.
            belief(tt) = (c[:midcourse_p0] +
                          (c[:midcourse_v0] +
                           get(c, :midcourse_vel_err_mps, zero(c[:midcourse_v0])) *
                           Float64(c[:midcourse_err_gain])) * (tt - Float64(c[:midcourse_t0])))
            bp = belief(sc.world.t - sc.dt_physics)                 # …what `observe!` actually saw
            cen_az, cen_el = look_angles(c[:att_q], los_unit(m.pos, bp))
            @test Float64(c[:head_tgt_az]) ≈ cen_az + deg2rad(off) atol = 1e-12
            @test Float64(c[:head_tgt_el]) ≈ cen_el                atol = 1e-12
            wrong_az, _ = look_angles(c[:att_q], los_unit(m.pos, belief(sc.world.t)))
            @test !isapprox(Float64(c[:head_tgt_az]), wrong_az + deg2rad(off); atol = 1e-9)
            # 3. …and the truth is somewhere ELSE. If the seam ever fell through to the truth write
            #    this gap would collapse to ~0 and the search would be an oracle (slice 42: the
            #    probe that did this went 3620.675 m → 0.110 m).
            tru_az, tru_el = look_angles(c[:att_q], los_unit(m.pos, t.pos))
            @test off_axis_angle(Float64(c[:head_tgt_az]), Float64(c[:head_tgt_el]),
                                 tru_az, tru_el) > deg2rad(0.1)
            # 4. THE DEFICIT IS THE CURRENCY: cue-to-truth MINUS the window, positive while the
            #    search is still looking, and in the SAME degrees as `gimbal_fov_deg` beside it.
            @test telv(sc, "search_deficit_deg") ≈
                  rad2deg(off_axis_angle(cen_az, cen_el, tru_az, tru_el)) -
                  telv(sc, "gimbal_fov_deg") atol = 1e-9
            @test telv(sc, "search_deficit_deg") > 0.0
            # 5. …and a searching head is BY DEFINITION not a valid one.
            @test telv(sc, "gimbal_valid", 1.0) == 0.0
        end
        # 6. THE HEAD ACTUALLY MOVES. A pattern the servo never executes is the failure mode this
        #    probe family has been bitten by FOUR times (`docs/LESSONS.md`) — so assert the travel
        #    on the HEAD's own angle, not on the command.
        @test abs(rad2deg(Float64(c[:head_az]))) > 0.0
    end

    @testset "D. THE MODEL TEST — the rate is READ EVERY TICK (§0.7's only outright kill)" begin
        # A knob consumed at load, or baked at search onset, is a BUG rather than a dead lesson.
        a = search_scn(rho = 60.0); b = search_scn(rho = 60.0)
        @test fly_to_search!(a) > 0
        @test fly_to_search!(b) > 0
        for k in 1:120                                   # …both mid-leg, in lockstep
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
        end
        @test telv(a, "search_offset_deg") == telv(b, "search_offset_deg")
        b.world.entities[:m1].comp[:seeker_search_rate_dps] = 180.0
        tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
        @test telv(a, "search_offset_deg") != telv(b, "search_offset_deg")
        @test telv(b, "search_rate_dps") == 180.0        # …and the wire says which rate it used
    end

    @testset "E. DRAW TOPOLOGY — two ρ, the SAME number of draws (convention 3)" begin
        # ⚠ COMPARED AFTER A FIXED TICK COUNT, never at CPA: the two arms fly DIFFERENT trajectories
        # by construction, so a comparison at the end of the flight would be comparing two different
        # numbers of ticks. The claim is that the per-tick draw COUNT is invariant to the slider —
        # the search moves the HEAD and gates the DETECTION, and it must never gate the DRAW.
        a = search_scn(rho = 60.0); b = search_scn(rho = 240.0)
        differed = false
        for k in 1:8000
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
            telv(a, "search_offset_deg") == telv(b, "search_offset_deg") || (differed = true)
        end
        @test differed                                  # ⚠ or the stream check below is VACUOUS
        @test a.world.entities[:m1].pos != b.world.entities[:m1].pos        # …two DIFFERENT flights
        @test rand(a.world.rng) == rand(b.world.rng)                       # …one stream position
    end

    @testset "F. ⭐ ACQUISITION IS NOT A LATCH — the search RESUMES after a lock that died" begin
        # ⚠⚠ THIS RETRACTS THE PLAN's §2.2, AND IT IS THE ONE PREDICATE MEASUREMENT DECIDED. With a
        # `!seek_init` conjunct the first lock ENDS the search forever — and a lock taken with less
        # margin than one tick of LOS drift does not survive the next tick, so the head freezes and
        # the missile flies straight with a `search_t_lock_s` on the wire saying it found the target.
        # Measured: 3 of 23 cells on one wire, 1 of 21 on the other; without the conjunct, 0 of 44.
        # This is the arm that carried the defect (ρ = 210 on the SLOWER-belief wire, which grazed
        # the rim at 0.0013° of margin).
        sc = search_scn(rho = 210.0, sgn = -1.0)
        locked = false; resumed = false
        for k in 1:12000
            tick!(sc.world, sc.subs, sc.dt_physics)
            telv(sc, "gimbal_valid", 0.0) == 1.0 && (locked = true)
            locked && telv(sc, "head_searching", 0.0) == 1.0 && (resumed = true)
            resumed && break
        end
        @test locked
        @test resumed
        @test telv(sc, "search_t_lock_s", -1.0) >= 0.0   # …the FIRST lock is still what is latched
    end

    @testset "THE LOADER's REFUSALS — each a crash guard or a dead-knob guard" begin
        base = read(sl47, String)
        head = "gimbal_rate_dps: 240.0,"
        @test occursin(head, base)
        with(x) = replace(base, head => "$head $x", count = 1)
        mktempdir() do dir
            function loads(tag, txt)
                p = joinpath(dir, "$tag.yaml"); write(p, txt); load_scenario(p)
            end
            fails(tag, txt) = @test_throws ErrorException loads(tag, txt)

            # THE HAPPY PATH — the anchor plus the coverage, and the RATE defaults to the null.
            sc = loads("ok", with("seeker_search: true, seeker_search_coverage_deg: 25.0,"))
            c  = sc.world.entities[:m1].comp
            @test c[:seeker_search] === true
            @test c[:seeker_search_coverage_deg] == 25.0
            @test c[:seeker_search_rate_dps] == 0.0        # THE NULL, and a knob can attach to it
            # `false` is not a way to turn it off — the PRESENCE is the gate (the midcourse posture)
            fails("anchor_false", with("seeker_search: false, seeker_search_coverage_deg: 25.0,"))
            # the two keys are DEAD without the anchor, so they are refused rather than ignored
            fails("rate_no_anchor", with("seeker_search_rate_dps: 60.0,"))
            fails("cov_no_anchor",  with("seeker_search_coverage_deg: 25.0,"))
            # …and the anchor without a coverage is a search with nowhere to look
            fails("anchor_no_cov",  with("seeker_search: true,"))
            # VALUE BOUNDS, on the AUTHORED input only (a live slider is floored at the consumer)
            fails("neg_rate", with("seeker_search: true, seeker_search_coverage_deg: 25.0, " *
                                   "seeker_search_rate_dps: -1.0,"))
            fails("zero_cov", with("seeker_search: true, seeker_search_coverage_deg: 0.0,"))
            fails("nan_rate", with("seeker_search: true, seeker_search_coverage_deg: 25.0, " *
                                   "seeker_search_rate_dps: .nan,"))
            # ⚠ A STRAPDOWN SEEKER HAS NO HEAD TO SWEEP — the pattern would have nowhere to go.
            gim = "gimbal_tau_s: 0.05, gimbal_stop_deg: 30.0, gimbal_fov_deg: 10.0,\n" *
                  "               gimbal_rate_dps: 240.0,"
            @test occursin(gim, base)
            fails("no_head", replace(base, gim => "seeker_search: true, " *
                                                  "seeker_search_coverage_deg: 25.0,", count = 1))
            # AND THE KNOB: live-settable WITH the anchor, refused without it (the existence check
            # in `_parse_knobs` is what reaches it — the key is not a comp parameter at all there).
            knob = "  - {target: m1, key: midcourse_err_gain,"
            @test occursin(knob, base)
            srch = "  - {target: m1, key: seeker_search_rate_dps, min: 0.0, max: 240.0,\n" *
                   "     label: \"sweep rate (deg/s)\"}\n"
            ok = loads("knob_ok", replace(with("seeker_search: true, " *
                                               "seeker_search_coverage_deg: 25.0,"),
                                          knob => srch * knob, count = 1))
            @test any(k -> k.key === :seeker_search_rate_dps, ok.knobs)
            fails("knob_no_anchor", replace(base, knob => srch * knob, count = 1))
        end
    end
end

# ══════════════════════════════════════════════════════════════════════════════════════════════
# SLICE 52 GATE 2 — THE COVERAGE AT THE **SEAM** (`docs/plans/slice52.md` §XI).
#
# The block above is a WAVE: `search_sweep` has no target, no servo and no engagement, so every
# law in it is exact. Between that wave and the head there is a gimbal with a lag and a stop; in
# front of the head there is a target whose angle is RUNNING AWAY while the search travels. This
# section is what the coverage axis does once those three are in the loop, and two of its results
# are visible at NO OTHER GATE:
#
#   ⭐⭐⭐ THE WIRE PAYS **MORE** THAN THE `2S` LAW, AND THE EXCESS IS THE RACE. Gate 1 tooth 3
#         pins `dt_first-cover/dS = 2/ρ` for a target that HOLDS STILL. Flown, the same derivative
#         at ρ = 60 is 0.040000 s/° against `2/ρ` = 0.033333 — **20 % over** — because the deficit
#         grows by ~6.85 °/s while the head is out on the wrong side.
#   ⭐⭐⭐ THE HEAD DOES NOT FLY THE COVERAGE YOU AUTHOR. The servo is a low-pass on the sweep, so
#         the realized peak-to-peak is 0.52–0.86 of what the command actually swept and shrinks
#         as the sweep's PERIOD shortens ⇒ the floor `S*` RISES with the rate: 5.00° at ρ = 60,
#         5.75 at 120, 7.50 at 240. A faster sweep needs a WIDER one — the opposite of the
#         intuition slice 48's rate knob leaves behind, and no property of the kernel.
#
# ⚠ FLOWN AGAINST THE SHIPPED `slice48_search.yaml`, not slice 48's `search_scn` fixture: every
# number in gate 0 §§I–VIII was measured on that file, slice 48's own gate 3 already proves the
# fixture and the file are the same wire, and the fixture is scoped inside the block above.
# ⚠⚠ AND EVERY FLIGHT STOPS INSIDE THE CLOSING PHASE (`nmax` = 7000 against a CPA near tick 8900),
# because a longer one picks up the POST-INTERCEPT re-search — the episode trap that printed
# "never acquired" beside a 1 cm hit at gate 0 §VIII, and its THIRD occurrence on this slice.
# ══════════════════════════════════════════════════════════════════════════════════════════════

@testset "seeker search COVERAGE — THE WIRE (slice 52 gate 2)" begin
    scen52 = joinpath(@__DIR__, "..", "..", "scenarios", "slice48_search.yaml")

    # The shipped file with the two search numbers written onto the comp bag — which is exactly
    # what a slider does (`missile.jl:2954` re-reads both every searching tick) and exactly what
    # gate 0's probes did. The file authors ρ = 0.0, so EVERY arm must write the rate: forget it
    # on one and its "NEVER" passes because the branch never opened.
    function cov_scn(; S = 25.0, rho = 60.0, stop = nothing, gain = nothing)
        sc = load_scenario(scen52)
        c  = sc.world.entities[:m1].comp
        c[:seeker_search_coverage_deg] = Float64(S)
        c[:seeker_search_rate_dps]     = Float64(rho)
        stop === nothing || (c[:gimbal_stop_deg]    = Float64(stop))
        gain === nothing || (c[:midcourse_err_gain] = Float64(gain))
        sc
    end
    telc(sc)            = get(sc.world.env, :telemetry, Dict{String,Any}())
    tvc(sc, k, d = NaN) = Float64(get(telc(sc), "m1.$k", d))

    @testset "0. THE OVERRIDES WRITE KEYS SOMETHING READS (the dead-knob guard on the HARNESS)" begin
        # ⚠ Every arm below is a comp-bag write. A typo'd key would be silently inert and would
        # turn this whole section into assertions about the NULL arm (`docs/LESSONS.md` §45).
        sc = load_scenario(scen52); c = sc.world.entities[:m1].comp
        for k in (:seeker_search_coverage_deg, :seeker_search_rate_dps,
                  :gimbal_stop_deg, :midcourse_err_gain)
            @test haskey(c, k)
        end
        # …and the head's own state, which the flights below read for the REALIZED sweep (tooth G),
        # is minted by the seam rather than authored — so it is asserted after a tick, not at load.
        @test !haskey(c, :head_az)
        tick!(sc.world, sc.subs, sc.dt_physics)
        @test haskey(c, :head_az)
    end

    # ONE FLIGHT, EVERY COLUMN — stopped at the FIRST lock, and never past `nmax` ticks.
    # `t_lock` < 0 is the shipped "never" sentinel. `reach` is the widest COMMANDED offset (which
    # is NOT what the head flew — tooth G), `nclamp` the searching ticks spent on the mechanical
    # stop, `def` the deficit series over the first search episode, and `ptp_head`/`ptp_cmd` the
    # realized sweep against the commanded one.
    function fly52(; S, rho = 60.0, stop = nothing, gain = nothing, nmax = 7000, keep_pos = false)
        sc  = cov_scn(; S, rho, stop, gain)
        c   = sc.world.entities[:m1].comp
        stp = Float64(c[:gimbal_stop_deg])
        pos = Vec3[]; def = Float64[]; cmd = Float64[]; hd = Float64[]
        nsrch = 0; nclamp = 0; nvalid = 0; k_srch = 0; reach = 0.0; maxhead = 0.0; tl = -1.0
        for k in 1:nmax
            tick!(sc.world, sc.subs, sc.dt_physics)
            keep_pos && push!(pos, sc.world.entities[:m1].pos)
            tvc(sc, "gimbal_valid", 0.0) == 1.0 && (nvalid += 1)
            if tvc(sc, "head_searching", 0.0) == 1.0
                nsrch += 1; k_srch == 0 && (k_srch = k)
                reach = max(reach, abs(tvc(sc, "search_offset_deg")))
                maxhead = max(maxhead, tvc(sc, "head_angle_deg", 0.0))
                tvc(sc, "head_angle_deg", 0.0) ≥ stp - 1.0e-6 && (nclamp += 1)
                push!(def, tvc(sc, "search_deficit_deg"))
                push!(cmd, tvc(sc, "search_offset_deg"))
                push!(hd,  rad2deg(Float64(c[:head_az])))
            end
            tl = tvc(sc, "search_t_lock_s", -1.0)
            tl ≥ 0.0 && break                       # …the first lock ENDS the measurement
        end
        (; t_lock = tl, k_srch, nsrch, nclamp, nvalid, reach, maxhead, def, pos,
           ptp_cmd  = isempty(cmd) ? NaN : maximum(cmd) - minimum(cmd),
           ptp_head = isempty(hd)  ? NaN : maximum(hd)  - minimum(hd))
    end

    @testset "A. ⭐⭐ THE COVERAGE IS LIVE — BUT INVISIBLE UNTIL THE FIRST REVERSAL" begin
        # ⚠⚠ THIS IS THE TOOTH GATE 1 WROTE ITS WARNING FOR. Slice 48's rate twin (tooth D above)
        # ticks 120 steps — 0.12 s — past search onset and then asserts the offsets DIFFER one
        # tick after the drag. Copied verbatim onto the coverage it asserts that two EQUAL numbers
        # differ: on the opening leg the offset is `ρt` and `S` does not enter the arithmetic at
        # all, so a 25° sweep and a 12° sweep are the SAME WAVE until the narrower one turns at
        # `S/ρ`. The fix is to SAMPLE PAST `min(S₁,S₂)/ρ`, never to loosen the comparison.
        a = cov_scn(); b = cov_scn()
        ka = 0; kb = 0
        for k in 1:12000
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
            ka == 0 && tvc(a, "head_searching", 0.0) == 1.0 && (ka = k)
            kb == 0 && tvc(b, "head_searching", 0.0) == 1.0 && (kb = k)
            ka > 0 && kb > 0 && break
        end
        @test ka > 0 && ka == kb                       # …the same wire, to the tick (4936)
        for k in 1:120
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
        end
        @test tvc(a, "search_elapsed_s") ≈ 0.120 atol = 1e-9
        @test tvc(a, "search_offset_deg") == tvc(b, "search_offset_deg")   # …bit-for-bit equal
        @test tvc(a, "search_offset_deg") ≈ 7.2 atol = 1e-9                # = 0.12 s × 60 °/s
        b.world.entities[:m1].comp[:seeker_search_coverage_deg] = 12.0            # ← THE DRAG
        tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
        # ⭐ THE WIRE SAYS THE KNOB MOVED ON THE VERY NEXT TICK — which is what a HUD reads — while
        # the BEHAVIOUR cannot move yet. Two different claims, and both are pinned.
        @test tvc(b, "search_coverage_deg") == 12.0
        @test tvc(a, "search_coverage_deg") == 25.0
        @test tvc(a, "search_offset_deg") == tvc(b, "search_offset_deg")
        # …and it stays invisible for the rest of the NARROWER arm's opening leg: 12/60 = 0.200 s.
        blind = 0
        for k in 1:78
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
            tvc(a, "search_offset_deg") == tvc(b, "search_offset_deg") && (blind += 1)
        end
        @test blind == 78                              # …to elapsed 0.1990, one tick short of 12/60
        @test tvc(a, "search_offset_deg") ≈ 11.94 atol = 1e-9
        for k in 1:121
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
        end
        @test tvc(a, "search_elapsed_s") ≈ 0.320 atol = 1e-9
        @test tvc(a, "search_offset_deg") ≈ 19.2 atol = 1e-9   # still climbing to its own 25° turn
        @test tvc(b, "search_offset_deg") ≈  4.8 atol = 1e-9   # …and the 12° arm is on its way back
        @test tvc(a, "search_offset_deg") - tvc(b, "search_offset_deg") > 1.0
    end

    @testset "B. ⭐⭐⭐ THE CLIFF, AND A FLOOR THAT IS THE NULL TO THE BIT" begin
        # The boundary may be pinned at all only because F1 cleared it: `S*` = 5.00° at BOTH `dt`
        # = 1e-3 and 5e-4, zero movement, no cell flipping LOCK ↔ NEVER (gate 0 §V) — which is
        # where slices 42 and 51 died. ⚠ F6 still holds: the LOCATION is not the headline.
        nul = fly52(S = 0.0,  keep_pos = true)
        lo  = fly52(S = 4.75, keep_pos = true)
        hi  = fly52(S = 5.0)
        @test nul.t_lock < 0.0 && lo.t_lock < 0.0            # …neither ever finds it
        @test hi.t_lock ≈ 0.2660 atol = 1e-6                 # …and a quarter of a degree more does
        # ⚠ THE NON-VACUITY TWIN, in the `sweep reached ±` form gate 0 §VII carried for the same
        # reason: a NEVER that never SEARCHED would pass this testset for the wrong reason.
        @test nul.nsrch > 1000 && lo.nsrch == nul.nsrch
        @test nul.reach == 0.0
        @test lo.reach ≈ 4.74 atol = 1e-9
        # ⭐ …and with the head demonstrably sweeping, the whole floor is the NULL trajectory to the
        # last bit: nothing the head does reaches the guidance until something is LOCKED.
        @test length(lo.pos) == length(nul.pos)
        @test all(p == q for (p, q) in zip(lo.pos, nul.pos))
    end

    @testset "C. ⭐⭐⭐ THE FLOWN COST EXCEEDS THE 2S LAW — gate 1's 2/ρ is the FIXED-TARGET case" begin
        # ⚠⚠ THE RETRACTION, STATED WHERE IT CAN BE READ: gate 0 §II wrote "0.04000 s/° = 2/60 to
        # four digits". `2/60` is 0.033333. The flown chord is 20 % ABOVE the kernel's law, not
        # equal to it — and slice 43 had already banked the same excess on its own wire (0.262 →
        # 0.347 s/° against a bound of 0.250: *"the target moves while you look the wrong way, and
        # that excess IS the finding"*, `docs/DEFERRALS.md`). Gate 2 restores it.
        S  = (6.0, 10.0, 20.0, 25.0, 45.0)
        tl = [fly52(S = s).t_lock for s in S]
        @test all(t -> t ≥ 0.0, tl)
        @test tl ≈ [0.2990, 0.4490, 0.8290, 1.0230, 1.8590] atol = 1e-6
        @test all(tl[k] > tl[k - 1] for k in 2:length(tl))               # F6 — no chatter
        chord = (tl[end] - tl[1]) / (S[end] - S[1])
        @test chord ≈ 0.040000 atol = 1e-7
        @test chord > 2 / 60.0                                   # ⭐ THE INEQUALITY IS THE PHYSICS
        @test chord / (2 / 60.0) ≈ 1.2000 atol = 1e-3
        # …and it is not an artifact of ONE rate: the same excess at 4× the sweep speed.
        t10 = fly52(S = 10.0, rho = 240.0).t_lock
        t45 = fly52(S = 45.0, rho = 240.0).t_lock
        @test t10 ≈ 0.1290 atol = 1e-6
        @test t45 ≈ 0.4410 atol = 1e-6
        c240 = (t45 - t10) / 35.0
        @test c240 ≈ 0.0089143 atol = 1e-6
        @test c240 > 2 / 240.0
        # ⚠ AND IT MAY ONLY BE READ OVER A WIDE BRACKET. `t_lock` is quantized at `dt` = 1e-3, so
        # an ADJACENT pair cannot resolve the excess at all: the 5→6 chord measures 0.0330, BELOW
        # `2/ρ` by a third of one tick. A local slope here is an instrument reading rather than a
        # physical one — the same shape as gate 0 §V's *re-fly a narrow threshold at half `dt`*.
        @test (fly52(S = 6.0).t_lock - fly52(S = 5.0).t_lock) / 1.0 < 2 / 60.0
    end

    @testset "D. ⭐⭐ THE RACE — the deficit GROWS while the search runs (no such thing at gate 1)" begin
        # This is the mechanism behind BOTH of the section's headline results and behind gate 0
        # §IV's FIRST-EXCURSION-OR-NEVER: the sweep centre is the LIVE dead-reckoned belief, and it
        # walks away from the truth at ~6.85 °/s while the head is out on the wrong side. The
        # kernel cannot see this — it has no target.
        r = fly52(S = 25.0)
        @test length(r.def) > 1000
        @test r.def[1]   ≈ 1.3423 atol = 1e-4                  # the deficit INHERITED at onset
        @test r.def[end] ≈ 8.3535 atol = 1e-4                  # …and what it had become at the lock
        @test all(r.def[k] > r.def[k - 1] for k in 2:length(r.def))   # STRICTLY, on every tick
        @test (r.def[end] - r.def[1]) / (length(r.def) * 1.0e-3) ≈ 6.854 atol = 1e-2
        # ⇒ a sweep must cover not the deficit it INHERITS but the one it will face after it has
        # travelled, which is why `S*` runs several times the deficit at onset (gate 0 §VIII).
        @test r.def[end] > 5 * r.def[1]
    end

    @testset "E. THE TRUNNION IS NOT THE SLIDER — the 2× stop, on the ONE cell where it BINDS" begin
        # Slice 41's rule: to prove a clamp is not setting your metric, VARY THE CLAMP.
        # ⚠⚠ AND THE CELL HAD TO BE FOUND, NOT ASSUMED. Gate 0 §VI carried a contamination column
        # reading 2.43 % at `S` = 25 and 18.97 % at `S` = 30 — but it was computed over the WHOLE
        # flight, and over the ACQUISITION (search onset → first lock) the stop binds on exactly
        # ZERO ticks in both of those cells. All of that 19 % is the POST-LOCK re-search, i.e. an
        # episode `t_lock` was never read on. Measured pre-lock at stop 45: `S` = 25/30/35/40 all
        # 0 clamped ticks, peak head angle 27.54 / 32.52 / 37.51 / 42.49° against a 45° stop.
        # ⇒ the honest row is `S` = 45, and it is the only one on the ladder.
        a = fly52(S = 45.0, stop = 45.0)
        b = fly52(S = 45.0, stop = 60.0)
        c = fly52(S = 45.0, stop = 90.0)
        # ⚠ A TICK COUNT IS NOT PINNED EXACTLY. The 102 this was measured at came off a probe whose
        # window ends at tick 7000; `fly52`'s ends at the lock, and two windows that differ by one
        # tick make an `== 102` a coin toss. The ZEROS are pinned exactly, because "the stop never
        # binds" is a claim rather than a count.
        @test a.nclamp > 50                              # ⚠ or the invariance below is VACUOUS
        @test a.maxhead ≈ 45.0 atol = 1e-9               # …pinned ON the stop, ~102 ticks of them
        @test b.nclamp == 0
        @test c.nclamp == 0
        @test b.maxhead ≈ 47.479 atol = 0.05             # …the travel the 45° stop was removing
        @test a.t_lock ≈ 1.8590 atol = 1e-6
        @test a.t_lock == b.t_lock                       # …EXACTLY, not `atol`, and named in pairs
        @test b.t_lock == c.t_lock                       #    so a failure says WHICH stop moved it
        # ⭐ AND THE REASON: `search_sweep` recomputes its phase from `t_since_start` with no
        # accumulator, so a clamped head does not fall BEHIND its own schedule — it resumes the
        # commanded angle the instant the command re-enters the travel. ⚠ Honest only while the
        # servo is faster than the sweep; on slice 35's 8 °/s head it would not be.
    end

    @testset "F. ⭐⭐⭐ S* IS NOT A CONSTANT — it TRACKS THE PICTURE ERROR" begin
        # THE LESSON, at the seam. `midcourse_err_gain` is slice 47's authored picture quality and
        # it sets the deficit the search inherits; the narrowest coverage that still acquires moves
        # with it. ⚠ Convention 9 keeps the picture error an authored FIXTURE in the showcase — it
        # is varied HERE, in a test, precisely so the scenario need not carry a second slider.
        never180 = fly52(S = 11.0,  gain = 180.0)
        lock180  = fly52(S = 11.25, gain = 180.0)
        @test never180.t_lock < 0.0 && never180.nsrch > 1000    # …searched hard, never covered
        @test lock180.t_lock ≈ 0.5850 atol = 1e-6
        # ⇒ at slice 48's authored picture error 5.00° acquires (tooth B); at 180 it does not, and
        # the floor has moved to 11.25 — a knob whose right value the SEEKER cannot know.
        @test fly52(S = 5.0, gain = 180.0).t_lock < 0.0
        @test never180.def[1] ≈ 4.6069 atol = 1e-4              # …the inherited deficit, 3.4× B's
        # ⚠⚠ AND THE EPISODE MUST BE ASSERTED, NOT FOUND. With a GOOD picture the handover lands
        # inside the window and the missile never searches at all during the engagement — the only
        # search on that wire is a POST-INTERCEPT one against a target now astern, which gate 0
        # §VIII first read as "never acquired" beside a 1 cm hit.
        good = fly52(S = 25.0, gain = 100.0)
        @test good.nsrch == 0 && good.k_srch == 0               # …no search episode AT ALL, here
        @test good.nvalid > 1000                                # …because it could see all along
        @test good.t_lock < 0.0                                 # ⚠ and THIS is not a failure
    end

    @testset "G. ⭐⭐⭐ THE HEAD DOES NOT FLY THE COVERAGE YOU AUTHOR — so S* RISES WITH THE RATE" begin
        # Gate 0 read `search_offset_deg` — the COMMAND — everywhere, and the command is a triangle
        # of amplitude exactly `S`. Between it and the head sits the gimbal, and a lag is a
        # LOW-PASS: the head's peak-to-peak is a FRACTION of the commanded one (which is itself
        # short of `2S` when the lock arrives mid-leg, so both are read on the same window), and it
        # falls as the sweep's period `4S/ρ` shrinks toward `gimbal_tau_s`. Slice 43 measured the
        # same thing on its own wire (realized sweep −19.73° → −4.39° as ρ went 8 → 64) and named
        # it *THE HEAD, NOT THE COMMAND, IS WHAT SEARCHES*; here it is on the shipped kernel.
        slow = fly52(S = 25.0, rho =  60.0)
        fast = fly52(S = 25.0, rho = 240.0)
        @test slow.ptp_cmd ≈ 36.30 atol = 1e-2
        @test fast.ptp_cmd ≈ 38.80 atol = 1e-2
        @test slow.ptp_head / slow.ptp_cmd ≈ 0.8637 atol = 1e-3
        @test fast.ptp_head / fast.ptp_cmd ≈ 0.5216 atol = 1e-3
        @test fast.ptp_head / fast.ptp_cmd < slow.ptp_head / slow.ptp_cmd < 1.0
        # ⚠ BOTH RATIOS ARE READ ON THE ACQUISITION WINDOW, WHICH THE LOCK TRUNCATES: neither arm
        # completes a full excursion before it locks (0.2670 s of a 0.4167 s period at ρ = 240),
        # so the ABSOLUTE fraction carries some of that truncation and only the ORDERING is the
        # lag's. Read without the truncation — `S` = 45, where the period is 0.75 / 3.00 s — the
        # same ordering is 0.6728 at ρ = 240 against 0.8883 at 60 (gate 0's probe §9).
        # ⭐⭐⭐ AND THE CONSEQUENCE IS A SIGN NOBODY WOULD GUESS: the same 6° sweep that acquires at
        # 60 °/s NEVER acquires at 240 °/s, because at 240 the head flies only a third of it. The
        # floor is 5.00° at ρ = 60, 5.75 at 120 and 7.50 at 240 (bracketed at 0.25°).
        @test fly52(S = 6.0, rho =  60.0).t_lock ≈ 0.2990 atol = 1e-6
        @test fly52(S = 6.0, rho = 240.0).t_lock < 0.0
        # ⚠ THIS QUALIFIES TWO SENTENCES OF GATE 0. §II's *"at ρ = 240 the whole ladder is benign"*
        # is true only ABOVE 7.50°, and slice 48's *faster is monotone better* is a statement about
        # ITS authored 25° coverage, not about the rate axis at every width. ⚠ It is NOT a kill of
        # either: both hold where they were measured.
    end

    @testset "H. DRAW TOPOLOGY — two COVERAGES, the SAME number of draws (convention 3)" begin
        # ⚠ 6000 ticks, not slice 48's 4000: the search does not open until tick 4936 on this wire,
        # and a comparison that stops before then compares two identical pre-search flights and
        # asserts nothing (measured — the first run of this probe reported `differed = false`).
        a = cov_scn(S = 6.0); b = cov_scn(S = 25.0)
        differed = false
        for k in 1:6000
            tick!(a.world, a.subs, a.dt_physics); tick!(b.world, b.subs, b.dt_physics)
            tvc(a, "search_offset_deg") == tvc(b, "search_offset_deg") || (differed = true)
        end
        @test differed                                                   # ⚠ or the check is VACUOUS
        @test a.world.entities[:m1].pos != b.world.entities[:m1].pos     # …two DIFFERENT flights
        @test rand(a.world.rng) == rand(b.world.rng)                     # …one stream position
    end

    @testset "I. THE SLIDER'S FLOOR AT THE CONSUMER — and the wire's ECHO is not the value USED" begin
        # Convention 5: an authored input is validated at LOAD (slice 48's `zero_cov` refusal above)
        # and a LIVE knob is floored at the CONSUMER. Dragged to its floor mid-sweep the head stops
        # sweeping and the tick survives — for 200 more ticks, which is the part a one-tick check
        # would miss.
        for bad in (0.0, NaN)
            sc = cov_scn()
            for k in 1:12000
                tick!(sc.world, sc.subs, sc.dt_physics)
                tvc(sc, "head_searching", 0.0) == 1.0 && break
            end
            for k in 1:150; tick!(sc.world, sc.subs, sc.dt_physics); end
            @test tvc(sc, "search_offset_deg") ≈ 9.0 atol = 1e-9        # …mid-leg, 0.15 s × 60
            sc.world.entities[:m1].comp[:seeker_search_coverage_deg] = bad
            for k in 1:201; tick!(sc.world, sc.subs, sc.dt_physics); end
            @test tvc(sc, "head_searching", 0.0) == 1.0                 # …still in the search state
            @test tvc(sc, "search_offset_deg") == 0.0                   # …with a sweep of nothing
            for k in ("search_offset_deg", "search_deficit_deg", "search_elapsed_s",
                      "search_t_lock_s", "search_coverage_deg", "head_angle_deg", "head_off_deg")
                @test isfinite(tvc(sc, k))                              # convention 6, after a drag
            end
        end
        # ⚠⚠ AND THE ONE THING A VIEW MUST NOT DO WITH THIS KEY. `search_coverage_deg` echoes the
        # BAG, finite-clamped (`_finite`), while the KERNEL floors a non-finite `S` to 0.0 — so on
        # a NaN the wire reports `FINITE_CEIL` beside a sweep of exactly zero, and a HUD that drew
        # the band from the echo would draw 1e9°. Pinned, not fixed: no shipped path reaches it
        # (the loader refuses a NaN and a slider is clamped to its authored range), and gate 3's
        # band must be drawn from `search_offset_deg` under `head_searching`, never from the echo.
        sc = cov_scn()
        for k in 1:12000
            tick!(sc.world, sc.subs, sc.dt_physics)
            tvc(sc, "head_searching", 0.0) == 1.0 && break
        end
        sc.world.entities[:m1].comp[:seeker_search_coverage_deg] = NaN
        tick!(sc.world, sc.subs, sc.dt_physics)
        @test tvc(sc, "search_coverage_deg") == EWSim.FINITE_CEIL
        @test tvc(sc, "search_offset_deg")   == 0.0
    end
end

# ══════════════════════════════════════════════════════════════════════════════════════════════
# GATE 3 — THE SHIPPED SCENARIO, FLOWN OFF THE **YAML** RATHER THAN OFF A FIXTURE.
#
# ⚠ Every number in the gate-2 section above was measured on `slice47_midcourse.yaml` with the cell's
# four values written into the comp bag. That is the right shape for gates 1–2 and it is NOT a proof
# that the file a student loads is the same wire: a fixture and a YAML can drift for a whole slice
# before anyone notices (convention 10 — pin against the LIVE oracle, never against a second hand
# recompute). These arms fly the file.
# ══════════════════════════════════════════════════════════════════════════════════════════════

@testset "seeker search — THE SHIPPED SCENARIO (slice 48 gate 3)" begin
    base = joinpath(@__DIR__, "..", "..", "scenarios")
    scn  = load_scenario(joinpath(base, "slice48_search.yaml"))
    mm   = scn.world.entities[:m1]; tt = scn.world.entities[:tgt1]

    @testset "THE AUTHORED WIRE — slice 47's, with FOUR numbers changed and each one named" begin
        @test scn.name == "slice48_search"
        @test scn.world.seed == 32 && scn.dt_physics == 1.0e-3 && scn.emit_every == 16
        # THE SEARCH ITSELF — the anchor, the reserve axis, and the slider's authored floor.
        @test mm.comp[:seeker_search] === true
        @test mm.comp[:seeker_search_coverage_deg] == 25.0
        @test mm.comp[:seeker_search_rate_dps] == 0.0      # ⭐ THE DEFAULT OPENS ON THE DISEASE:
                                                           # a head that does not sweep at all
        # ⚠ THE FOUR THAT DIFFER FROM SLICE 47, asserted as DIFFERENCES so a silent revert is caught.
        s47 = load_scenario(joinpath(base, "slice47_midcourse.yaml"))
        m47 = s47.world.entities[:m1]; t47 = s47.world.entities[:tgt1]
        @test mm.comp[:gimbal_stop_deg] == 45.0 && m47.comp[:gimbal_stop_deg] == 30.0
        # ⭐⭐⭐ THE DIRECTION IS FLIPPED, and it is the sharpest of the four: `search_sweep` always
        # opens toward +azimuth and has no truth to read, so WHICH HALF it opens into is a property
        # of this file. On slice 47's direction the target sits at +12.94° from the cue and the sweep
        # would open straight at it — every cell locking inside 0.27 s, and the slider teaching
        # nothing. Flipped, the target is at −11.34° and the wrong half is paid for in full.
        @test mm.comp[:midcourse_vel_err_mps] == Vec3(0.0, 1.0, 0.0)
        @test m47.comp[:midcourse_vel_err_mps] == Vec3(0.0, -1.0, 0.0)
        @test tt.comp[:rcs_m2] == 0.020 && t47.comp[:rcs_m2] == 0.001
        @test mm.comp[:midcourse_err_gain] == 140.0
        # …AND EVERYTHING ELSE IS SLICE 47's WIRE TO THE DIGIT. Anything that moves between the two
        # files beyond the four above is unaccounted for.
        for k in (:gimbal_fov_deg, :gimbal_rate_dps, :gimbal_tau_s, :detect_pt_w, :detect_freq_hz,
                  :detect_tint_s, :detect_nf_db, :detect_loss_db, :detect_eta, :detect_snr_min_db,
                  :sigma_seek, :alpha, :beta, :n_pn, :a_max, :midcourse_k)
            @test mm.comp[k] == m47.comp[k]
        end
        @test tt.pos == t47.pos && tt.vel == t47.vel
        @test mm.pos == m47.pos
    end

    @testset "THE MARKER — raised BESIDE 46's and 47's, and nobody else's" begin
        let inf = EWSim._airframe_view_info(scn.world)
            @test inf !== nothing
            @test haskey(inf, :search_view)
            @test haskey(inf, :midcourse_view)          # STILL raised — the belief IS the sweep centre
            @test haskey(inf, :seeker_detect_view)      # STILL raised — the button stays 46's
            @test haskey(inf, :gimbal_view) && haskey(inf, :gimbal_rate_view)
            for absent in (:radome_view, :seeker_fov_view, :gimbal_servo_view, :gimbal_frame_view,
                           # ⚠ SLICE 52's OWN MARKER IS ABSENT HERE, AND THAT IS WHAT KEEPS THE TWO
                           # WIRES APART: this file authors the search and NOT the instrument
                           # (`seeker_search_realized`), so slice 52's HUD — which is checked FIRST
                           # in the client — cannot take slice 48's wire.
                           :search_realized_view)
                @test !haskey(inf, absent)
            end
        end
        # …and NO OTHER WIRE raises it. An enumerated carrier SET rather than an `isempty`, for the
        # reason slices 36–47 each rediscovered: an `isempty` goes on passing forever while quietly
        # ceasing to say anything the moment a second wire is added.
        let carriers = String[]
            for f in readdir(base)
                endswith(f, ".yaml") || continue
                inf = EWSim._airframe_view_info(load_scenario(joinpath(base, f)).world)
                inf !== nothing && haskey(inf, :search_view) && push!(carriers, f)
            end
            # ⚠⚠ **TWO CARRIERS SINCE SLICE 52, AND GATE 1 PREDICTED THIS FAILURE IN WRITING**
            # (`docs/plans/slice52.md` §X): a slice-52 wire IS a slice-48 wire with a different
            # slider, so it authors `:seeker_search` and raises this marker too. The list is
            # EXTENDED rather than the check loosened — an `isempty`/`in` would go on passing
            # forever while quietly ceasing to say anything.
            # ⚠ What separates the two wires is slice 52's own `search_realized_view`, whose carrier
            # set is enumerated in that slice's own gate-3 block below.
            @test carriers == ["slice48_search.yaml", "slice52_coverage.yaml"]
        end
    end

    @testset "CONVENTION 9 — exactly ONE knob, and both endpoints have reasons" begin
        @test length(scn.knobs) == 1
        k = scn.knobs[1]
        @test k.target === :m1 && k.key === :seeker_search_rate_dps
        @test k.min == 0.0 && k.max == 240.0       # floor = the NULL; ceiling = the SERVO's own limit
        @test k.max == mm.comp[:gimbal_rate_dps]   # …and that is not a coincidence, it is the reason
        @test !k.log                               # the floor region must READ as a region
        # ⚠ EVERY DISQUALIFIED CANDIDATE IS ASSERTED ABSENT rather than merely left out.
        @test !any(kb.key === :seeker_search_coverage_deg for kb in scn.knobs)  # §0.7's reserve axis
        @test !any(kb.key === :midcourse_err_gain for kb in scn.knobs)          # slice 47's slider
        @test !any(kb.key === :rcs_m2 for kb in scn.knobs)                      # slice 46's
        @test !any(kb.key === :gimbal_fov_deg for kb in scn.knobs)              # TWO-SIDED since 46
    end

    # THE FLOWN ARMS. ⚠ Two only, and each is a claim no static check can make.
    function fly_file(rho; n = 9600)
        sc = load_scenario(joinpath(base, "slice48_search.yaml"))
        sc.world.entities[:m1].comp[:seeker_search_rate_dps] = rho   # …the way `set_param` does
        pos = Vector{Vec3}(); tl = -1.0; auth = 0.0; nsrch = 0; rmin = Inf; prev = Inf; closing = true
        for k in 1:n
            tick!(sc.world, sc.subs, sc.dt_physics)
            e = sc.world.entities[:m1]
            push!(pos, e.pos)
            tel = get(sc.world.env, :telemetry, Dict{String,Any}())
            Float64(get(tel, "m1.head_searching", 0.0)) == 1.0 && (nsrch += 1)
            tl = Float64(get(tel, "m1.search_t_lock_s", -1.0))
            r = Float64(get(tel, "m1.los_range", Inf))
            closing && r > prev && prev < 1e29 && (closing = false)
            prev = r
            closing && (rmin = min(rmin, r))
            # ⚠ BOTH GATES — r > 200 m AND the closing band. Gated on range alone the POST-CPA
            # re-crossing climbs back through 200 m from the far side and every guidance quantity
            # goes wild there ([[ewsim-missile-verifier-sampling]]).
            closing && tl >= 0.0 && r > 200.0 &&
                (auth = max(auth, abs(Float64(get(tel, "m1.a_cmd_frac", 0.0)))))
        end
        (; pos, t_lock = tl, auth, nsrch, cpa = rmin)
    end

    @testset "⭐⭐⭐ THE FLOOR IS BIT-IDENTICAL — the miss is not this slice's gauge, as an identity" begin
        # Across the whole floor region the head sweeps hard and the missile flies the SAME
        # trajectory to the last bit, because nothing the head does reaches the guidance until
        # something is LOCKED. A verifier reading the miss over that region would report a slider
        # that does nothing — which is how slices 44 and 45 died.
        a = fly_file(0.0; n = 7000)
        b = fly_file(35.0; n = 7000)
        @test a.nsrch == 0                       # ρ = 0 ⇒ the branch is shut: THE SHIPPED WIRE
        @test b.nsrch > 1000                     # …while 35 °/s sweeps for seconds
        @test a.t_lock < 0.0 && b.t_lock < 0.0   # …and neither ever finds it
        @test all(p == q for (p, q) in zip(a.pos, b.pos))     # bit-for-bit, not `atol`
    end

    @testset "⭐⭐⭐ THE EDGE — 0.086 s of earlier lock inverts the engagement" begin
        # 60 °/s: found in 1.023 s, PINNED at the airframe's limit, and STILL missing by 32 m.
        # 65 °/s: found 0.086 s sooner, a third of the airframe, and it arrives.
        lo = fly_file(60.0)
        hi = fly_file(65.0)
        @test lo.t_lock ≈ 1.0230 atol = 1e-3
        @test hi.t_lock ≈ 0.9370 atol = 1e-3
        @test 0.0 < lo.t_lock - hi.t_lock < 0.25          # a TWELFTH of a second, not a landslide
        @test lo.auth ≥ 0.99 && lo.cpa > 30.0             # everything spent, and still a miss
        @test hi.auth < 0.50 && hi.cpa < 5.0              # a third spent, and an arrival
        # ⚠ AND THE AUTHORITY IS NOT MONOTONE IN ρ — asserted, so nobody "fixes" the verifier into
        # claiming it is. It climbs to saturation as the lock gets late and FALLS once the lock is
        # early enough that little is demanded at all.
        @test hi.auth < lo.auth
        @test fly_file(240.0).auth < hi.auth
    end
end

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# SLICE 52 GATE 3 — THE SHIPPED SCENARIO: **HOW WIDE SHOULD A SEEKER SEARCH?**
#
# `scenarios/slice52_coverage.yaml` is slice 48's wire with the sweep RATE nailed down at a MEASURED
# 60 °/s and the other half of `search_sweep` handed to the student. Gate 1 pinned the WAVE, gate 2
# flew slice 48's file with the two search numbers written onto the comp bag; this block asserts the
# SHIPPED FILE — what an author wrote, what the client is told, and the three claims the showcase
# makes that no earlier gate could make because no scenario existed to make them on.
#
# ⭐⭐⭐ THE ONE THING HERE THAT IS NEW PHYSICS-SIDE: `seeker_search_realized`. Gate 2 measured that
# the head flies only a fraction of the sweep it is commanded (a lag is a low-pass, and a sweep's
# period is `4S/ρ`), and a slice whose whole subject is HOW WIDE cannot leave the width the head
# ACTUALLY flew off the wire. The key is an INSTRUMENT rather than a flag — it turns on
# `search_realized_deg` / `search_realized_peak_deg`, both formed every searching tick — and it is
# also what raises this slice's view marker, because the two wires are otherwise indistinguishable
# to the client (gate 1 §X wrote that problem down before this file existed).
# ═════════════════════════════════════════════════════════════════════════════════════════════════
@testset "seeker search COVERAGE — THE SHIPPED SCENARIO (slice 52 gate 3)" begin
    base52 = normpath(joinpath(@__DIR__, "..", "..", "scenarios"))
    scn52  = load_scenario(joinpath(base52, "slice52_coverage.yaml"))
    scn48  = load_scenario(joinpath(base52, "slice48_search.yaml"))
    m52    = scn52.world.entities[:m1].comp
    m48    = scn48.world.entities[:m1].comp

    @testset "THE AUTHORED WIRE — slice 48's, with THREE numbers changed and each one named" begin
        @test scn52.world.seed == scn48.world.seed == 32
        @test scn52.dt_physics == scn48.dt_physics == 1.0e-3
        @test scn52.world.fidelity == scn48.world.fidelity      # the six rungs, to the digit
        # 1. THE SWEEP RATE — slice 48's slider FLOOR (its null) becomes this wire's authored
        #    fixture, and 60 °/s is a MEASURED choice: at 240 the whole coverage ladder is benign
        #    and the slider teaches nothing, at 60 it spans never / pinned / cheap.
        @test m52[:seeker_search_rate_dps] == 60.0
        @test m48[:seeker_search_rate_dps] == 0.0
        # 2. THE COVERAGE — the same authored 25.0 on both files; what changed is that here it is
        #    THE SLIDER (asserted under convention 9 below).
        @test m52[:seeker_search_coverage_deg] == m48[:seeker_search_coverage_deg] == 25.0
        # 3. THE INSTRUMENT — authored here and DELIBERATELY NOT there, which is what keeps slice
        #    48's frames byte-identical (convention 2: slices are ADDITIVE).
        @test m52[:seeker_search_realized] === true
        @test !haskey(m48, :seeker_search_realized)
        # …AND EVERYTHING ELSE IS SLICE 48's WIRE TO THE DIGIT. Anything that moves between the two
        # files beyond the three above is unaccounted for.
        for k in (:seeker_search, :gimbal_fov_deg, :gimbal_rate_dps, :gimbal_tau_s, :gimbal_stop_deg,
                  :detect_pt_w, :detect_freq_hz, :detect_tint_s, :detect_nf_db, :detect_loss_db,
                  :detect_eta, :detect_snr_min_db, :sigma_seek, :alpha, :beta, :n_pn, :a_max,
                  :midcourse, :midcourse_k, :midcourse_err_gain, :midcourse_vel_err_mps)
            @test m52[k] == m48[k]
        end
        t52 = scn52.world.entities[:tgt1]; t48 = scn48.world.entities[:tgt1]
        @test t52.pos == t48.pos && t52.vel == t48.vel
        @test t52.comp[:rcs_m2] == t48.comp[:rcs_m2] == 0.020
        @test scn52.world.entities[:m1].pos == scn48.world.entities[:m1].pos
        # ⚠ THE PICTURE ERROR IS A FIXTURE ON BOTH WIRES AND IT MATTERS MORE HERE: it is the
        # quantity that SETS the right coverage (gate 2 tooth F — S* runs 5.00° at 140 and 11.25°
        # at 180), so a second slider on it would let a student move the answer and the question at
        # the same time.
        @test m52[:midcourse_err_gain] == 140.0
    end

    @testset "THE MARKER — the 14th, raised BESIDE 48's / 47's / 46's, and by nobody else" begin
        let inf = EWSim._airframe_view_info(scn52.world)
            @test inf !== nothing
            @test haskey(inf, :search_realized_view)
            @test haskey(inf, :search_view)             # STILL raised — this IS a search wire
            @test haskey(inf, :midcourse_view)          # STILL raised — the belief IS the centre
            @test haskey(inf, :seeker_detect_view)      # STILL raised — the button stays 46's
            @test haskey(inf, :gimbal_view) && haskey(inf, :gimbal_rate_view)
            for absent in (:radome_view, :seeker_fov_view, :gimbal_servo_view, :gimbal_frame_view,
                           :seeker_aspect_view)
                @test !haskey(inf, absent)
            end
        end
        # ⚠⚠ THE ENUMERATED CARRIER SET, AND IT IS THE HALF THAT ACTUALLY DOES THE WORK. Slice 48's
        # `search_view` now has TWO carriers (asserted in its own block above), so it can no longer
        # tell the two wires apart — this marker is the one that can, and an `isempty` here would go
        # on passing forever while quietly ceasing to say anything.
        let carriers = String[]
            for f in readdir(base52)
                endswith(f, ".yaml") || continue
                inf = EWSim._airframe_view_info(load_scenario(joinpath(base52, f)).world)
                inf !== nothing && haskey(inf, :search_realized_view) && push!(carriers, f)
            end
            @test carriers == ["slice52_coverage.yaml"]
        end
    end

    @testset "CONVENTION 9 — exactly ONE knob, and NEITHER endpoint is zero" begin
        @test length(scn52.knobs) == 1
        k = scn52.knobs[1]
        @test k.target === :m1 && k.key === :seeker_search_coverage_deg
        # ⚠⚠ THE FLOOR IS 1.0 AND **NOT 0**, and the difference from slice 48's slider is the
        # lesson rather than a detail. A sweep rate of 0 is a true null — a head that does not sweep
        # at all. A coverage of 0 is a different object: the search branch still runs, the head is
        # still commanded, the sweep is merely zero-amplitude — and the loader refuses it outright
        # as an authored value. 1.0° is a head that VISIBLY sweeps and STILL never gets there, which
        # is the failure this axis teaches: REACH, not inaction.
        @test k.min == 1.0
        @test k.min > 0.0
        # ⚠ THE CEILING IS THE LAST CELL THE MECHANICAL STOP STAYS OUT OF — measured, not rounded:
        # the head peaks at 42.49° against the authored 45° trunnion at S = 40, and at S = 45 the
        # stop binds for 102 ticks BEFORE the lock (gate 2 tooth E). A showcase whose top cell is
        # clamped would be teaching the trunnion beside the coverage.
        @test k.max == 40.0
        @test k.max < m52[:gimbal_stop_deg]
        @test !k.log                               # the floor region must READ as a region
        # ⚠ EVERY DISQUALIFIED CANDIDATE IS ASSERTED ABSENT rather than merely left out — and the
        # first one is the interesting one: slice 48's OWN slider. The two knobs COMPOSE (the floor
        # is 5.00° at 60 °/s and 7.50° at 240), so dragging both would let a student move the floor
        # and the width at once.
        for dead in (:seeker_search_rate_dps, :midcourse_err_gain, :rcs_m2, :gimbal_fov_deg,
                     :gimbal_stop_deg, :gimbal_rate_dps, :midcourse_vel_err_mps)
            @test !any(kb -> kb.key === dead, scn52.knobs)
        end
    end

    # ONE FLIGHT OFF THE SHIPPED FILE, stopped at the FIRST lock and never past `nmax` ticks.
    # ⚠⚠ NOTHING PAST THE FIRST LOCK, on purpose (gate 2's rule): a longer flight picks up the
    # POST-INTERCEPT re-search, which is this slice's fourth occurrence of the episode trap.
    # `S === nothing` flies the file's own authored coverage — the arm the showcase OPENS on.
    function fly52g3(; S = nothing, rho = nothing, nmax = 7000, keep_pos = false)
        sc = load_scenario(joinpath(base52, "slice52_coverage.yaml"))
        c  = sc.world.entities[:m1].comp
        S   === nothing || (c[:seeker_search_coverage_deg] = Float64(S))
        rho === nothing || (c[:seeker_search_rate_dps]     = Float64(rho))
        stp = Float64(c[:gimbal_stop_deg])
        pos = Vec3[]
        nsrch = 0; nclamp = 0; tl = -1.0
        pk_cmd = 0.0; pk_real = 0.0; pk_head = 0.0; def_last = NaN
        peak_key = 0.0; cmd_key = 0.0
        for k in 1:nmax
            tick!(sc.world, sc.subs, sc.dt_physics)
            tel = get(sc.world.env, :telemetry, Dict{String,Any}())
            tv(key, d = NaN) = Float64(get(tel, "m1.$key", d))
            keep_pos && push!(pos, sc.world.entities[:m1].pos)
            if tv("head_searching", 0.0) == 1.0
                nsrch += 1
                pk_cmd  = max(pk_cmd,  abs(tv("search_offset_deg")))
                pk_real = max(pk_real, abs(tv("search_realized_deg")))
                pk_head = max(pk_head, abs(tv("head_angle_deg", 0.0)))
                peak_key = tv("search_realized_peak_deg", NaN)
                cmd_key  = tv("search_offset_peak_deg", NaN)
                def_last = tv("search_deficit_deg")
                abs(tv("head_angle_deg", 0.0)) >= stp - 1.0e-6 && (nclamp += 1)
            end
            tl = tv("search_t_lock_s", -1.0)
            tl >= 0.0 && break
        end
        (; t_lock = tl, nsrch, nclamp, pk_cmd, pk_real, pk_head, def_last, peak_key, cmd_key, pos,
           frac = pk_real / max(pk_cmd, 1.0e-12))
    end

    @testset "⭐ THE INSTRUMENT SHIPS — two keys, on THIS wire and on no earlier one" begin
        # The slice-52 frame carries the realized pair; slice 48's frame does NOT, which is the
        # byte-identity claim stated as a key-set fact rather than as a sentence.
        s52 = load_scenario(joinpath(base52, "slice52_coverage.yaml"))
        s48 = load_scenario(joinpath(base52, "slice48_search.yaml"))
        for _ in 1:5200                                    # past the 4.936 s handover
            tick!(s52.world, s52.subs, s52.dt_physics)
            tick!(s48.world, s48.subs, s48.dt_physics)
        end
        t52 = get(s52.world.env, :telemetry, Dict{String,Any}())
        t48 = get(s48.world.env, :telemetry, Dict{String,Any}())
        @test haskey(t52, "m1.search_realized_deg") && haskey(t52, "m1.search_realized_peak_deg")
        @test haskey(t52, "m1.search_offset_peak_deg")
        for k in ("m1.search_realized_deg", "m1.search_realized_peak_deg",
                  "m1.search_offset_peak_deg")
            @test !haskey(t48, k)
        end
        # …and NOTHING ELSE about the frame differs: the two key SETS are equal once the new pair is
        # removed. A slice that grew a key on an old wire would fail here rather than in a golden.
        @test setdiff(Set(keys(t52)), Set(keys(t48))) ==
              Set(["m1.search_realized_deg", "m1.search_realized_peak_deg",
                   "m1.search_offset_peak_deg"])
        @test isempty(setdiff(Set(keys(t48)), Set(keys(t52))))
        # ⚠ NEVER-STALE: the pair ships on EVERY frame once the anchor is authored, including
        # BEFORE the first sweep, where a key that stopped emitting would read downstream as a
        # defaulted 0.0 — and here 0.0 means "the head never moved", which is the slider's own
        # floor verdict (`docs/CONVENTIONS.md` §14).
        let s = load_scenario(joinpath(base52, "slice52_coverage.yaml"))
            tick!(s.world, s.subs, s.dt_physics)
            tel = get(s.world.env, :telemetry, Dict{String,Any}())
            @test Float64(tel["m1.head_searching"]) == 0.0        # not searching yet…
            @test haskey(tel, "m1.search_realized_deg")           # …and the keys are there anyway
            @test tel["m1.search_realized_peak_deg"] == 0.0
            @test tel["m1.search_offset_peak_deg"] == 0.0
        end
    end

    @testset "⭐⭐⭐ THE HEAD DOES NOT FLY THE COVERAGE YOU AUTHOR — on the SHIPPED file" begin
        # The commanded sweep is a triangle of amplitude exactly S; between it and the sky sits a
        # 0.05 s lag, and the sweep's period is `4S/ρ` — so the NARROWER the sweep the less of it
        # survives. Read over the ACQUISITION only (the lock ends the measurement).
        fr = Float64[]
        for S in (1.0, 2.0, 4.0, 6.0, 10.0, 16.0, 25.0, 40.0)
            r = fly52g3(; S)
            @test r.nsrch > 100
            @test r.pk_real < r.pk_cmd                     # the head NEVER reaches the command
            @test r.pk_real ≈ r.peak_key atol = 1.0e-9     # the core's own peak-hold IS this number
            # ⚠⚠ AND THE **COMMANDED** PEAK IS ON THE WIRE TOO, which is a VIEW prohibition made
            # structural: gate 2 tooth I measured that `search_coverage_deg` echoes the bag
            # finite-clamped while the kernel floors a non-finite S to 0.0, so a HUD sizing its
            # band from that echo would draw a billion degrees over a motionless head. The band is
            # drawn from THIS key — a peak of `search_offset_deg` — and never from the echo.
            @test r.pk_cmd ≈ r.cmd_key atol = 1.0e-9
            push!(fr, r.frac)
        end
        # ⭐⭐ STRICTLY RISING WITH THE WIDTH: 0.27 at 1°, 0.65 at 6°, 0.92 at 25°, 0.95 at 40°.
        @test all(fr[i] < fr[i + 1] for i in 1:(length(fr) - 1))
        @test fr[1] ≈ 0.2659 atol = 1.0e-3
        @test fr[end] ≈ 0.9492 atol = 1.0e-3
        # ⭐⭐⭐ AND FALLING WITH THE **RATE** AT A FIXED WIDTH, which is gate 2's headline G on the
        # shipped file: a faster sweep has a shorter period against the same fixed lag, so the head
        # flies less of it — and the FLOOR RISES with the rate (5.00° at 60 °/s, 7.50° at 240).
        # **A faster sweep needs a wider one.** The two knobs compose; they do not substitute.
        f60  = fly52g3(; S = 25.0, rho = 60.0).frac
        f120 = fly52g3(; S = 25.0, rho = 120.0).frac
        f240 = fly52g3(; S = 25.0, rho = 240.0).frac
        @test f60 > f120 > f240
        @test f60 ≈ 0.9188 atol = 1.0e-3
        @test f240 ≈ 0.7021 atol = 1.0e-3
    end

    @testset "⭐⭐⭐ THE CLIFF, AND IT IS THE **FLOWN** BAND THAT SETS IT" begin
        lo = fly52g3(; S = 4.75)
        hi = fly52g3(; S = 5.00)
        @test lo.t_lock < 0.0                    # NEVER — and the head swept the whole time
        @test lo.nsrch > 1000
        @test hi.t_lock ≈ 0.2660 atol = 1.0e-3
        # ⭐⭐⭐ THE TOOTH THIS SECTION EXISTS FOR. At the cliff the gap the sweep had to cover was
        # 2.8035°, the AUTHORED coverage was 5.00° — nearly two degrees more than needed — and the
        # head FLEW only 3.2429°, four tenths of a degree past the gap. A student sizing this sweep
        # from the authored number alone would predict the floor at about 3° and be wrong by two
        # thirds, because the number they were reading is not the sweep the head flies.
        @test hi.def_last ≈ 2.8035 atol = 1.0e-3
        @test hi.pk_cmd - hi.def_last > 2.0          # the AUTHORED band overshoots the gap…
        @test 0.0 < hi.pk_real - hi.def_last < 0.5   # …and the FLOWN one only just clears it
        # ⚠ AND THE LAST FAILING CELL IS NOT A CELL WHERE THE COMMAND WAS TOO NARROW: 4.74° of
        # commanded reach against the same ~2.8° gap. It fails on what the head FLEW (3.02°) and on
        # the phase of the race, not on the number an author wrote.
        @test lo.pk_cmd ≈ 4.7400 atol = 1.0e-3
        @test lo.pk_real ≈ 3.0198 atol = 1.0e-3
    end

    @testset "⭐⭐⭐ THE FLOOR IS A REGION, AND IT IS BIT-IDENTICAL ACROSS IT" begin
        # Nothing the head does reaches the guidance until something is LOCKED, so every cell of the
        # floor flies the SAME missile — while the head is demonstrably doing different things in
        # each (the `pk_real` row exists precisely so a zero difference cannot be misread as a head
        # that did nothing). A verifier reading the miss over this region would report a slider that
        # does nothing, which is how slices 44 and 45 died.
        b = fly52g3(; S = 1.0, keep_pos = true)
        @test b.t_lock < 0.0 && b.nsrch > 1000
        for S in (2.0, 3.0, 4.0, 4.75)
            a = fly52g3(; S, keep_pos = true)
            @test a.t_lock < 0.0
            @test length(a.pos) == length(b.pos)
            @test all(p == q for (p, q) in zip(a.pos, b.pos))       # bit-for-bit, not `atol`
            @test a.pk_real > b.pk_real                             # …and the heads DIFFER, visibly
        end
    end

    @testset "⚠ THE CEILING IS CLEAN — the trunnion stays OUT of the acquisition below it" begin
        # The stop is authored at 45.0 and the slider stops at 40.0 for a measured reason.
        top = fly52g3(; S = 40.0)
        @test top.nclamp == 0
        @test top.pk_head ≈ 42.492 atol = 1.0e-2
        @test top.pk_head < m52[:gimbal_stop_deg]
        # …and one step past the ceiling the stop DOES bind, before the lock — which is the whole
        # reason 40 and not 45 (gate 2 tooth E; and `t_lock` survives it, so this is a hygiene
        # choice about what the showcase TEACHES, not a claim that the gauge would break).
        over = fly52g3(; S = 45.0)
        @test over.nclamp > 50
        @test over.t_lock ≈ 1.8590 atol = 1.0e-3
    end

    @testset "⭐⭐⭐ THE PEAKS RE-ARM ON A DRAG — the lying-HUD bug this slice nearly shipped" begin
        # ⚠⚠ A PEAK THAT IS ONLY EVER `max`-ED IS PERMANENTLY STALE THE MOMENT THE KNOB FALLS, and
        # the falling direction is the one the HUD's own cure line asks for (*"now NARROW it"*).
        # Measured before the fix: dragging 25° → 6° mid-search left `search_offset_peak_deg` at
        # 21.84 and the realized peak at 18.85 for the REST OF THE FLIGHT, so the band drew a 22°
        # sweep over a head covering ±6 and the headline named a width the slider did not show.
        # ⚠ Slice 49's rule — *a live SLIDER DRAG invalidates a latched instrument exactly as a
        # Reset does, and reaches NONE of the four gate-3 proofs* — so it is asserted here.
        sc = load_scenario(joinpath(base52, "slice52_coverage.yaml"))
        c  = sc.world.entities[:m1].comp
        for _ in 1:5300
            tick!(sc.world, sc.subs, sc.dt_physics)
        end
        tv52(k) = Float64(get(get(sc.world.env, :telemetry, Dict{String,Any}()), "m1.$k", NaN))
        @test tv52("head_searching") == 1.0            # …mid-search, or this proves nothing
        told_before = tv52("search_offset_peak_deg")
        @test told_before ≈ 21.84 atol = 1.0e-2
        t0_before = Float64(c[:search_t0])
        # THE DRAG — a comp-bag write, which is exactly what `set_param` does.
        c[:seeker_search_coverage_deg] = 6.0
        tick!(sc.world, sc.subs, sc.dt_physics)
        # ⭐ THE COMMAND RE-ARMS ON THE VERY NEXT TICK: the peak is now a fresh partial excursion of
        # the NEW sweep, nowhere near the old 21.84.
        @test tv52("search_offset_peak_deg") < 2.5
        for _ in 1:1200
            tick!(sc.world, sc.subs, sc.dt_physics)
        end
        @test tv52("head_searching") == 1.0            # …still searching, so the window is real
        @test tv52("search_coverage_deg") == 6.0
        @test tv52("search_offset_peak_deg") ≈ 6.0 atol = 1.0e-3
        # ⭐⭐⭐ AND THE REALIZED PEAK LANDS ON THE **UN-DRAGGED 6° ARM'S OWN NUMBER**, which is the
        # only check that proves the re-arm measures the new sweep rather than merely forgetting the
        # old one: 4.0004 against that arm's 4.1572, i.e. a flown fraction of 0.667 against 0.693.
        @test tv52("search_realized_peak_deg") ≈ 4.0004 atol = 1.0e-2
        @test abs(tv52("search_realized_peak_deg") / tv52("search_offset_peak_deg") - 0.6929) < 0.05
        # ⚠⚠ AND `:search_t0` IS **UNTOUCHED** — re-stamping the phase would move the commanded
        # offset itself and destroy gate 2 tooth A's measured property (a drag is invisible for
        # `min(S₁,S₂)/ρ`, bit-identical for 78 more ticks and diverging at exactly 0.2000 s).
        @test Float64(c[:search_t0]) === t0_before
        # ⚠ THE RESTART INSTANT IS THE CENTRE CROSSING, NOT RE-ENTRY INTO THE NEW BAND. Restarting
        # at re-entry samples the head AT THE RIM — it is transiting inward through the whole band —
        # and reported 0.99 where the un-dragged arm measures 0.69: a stale peak swapped for a
        # flattering one. This bound is what separates the two implementations.
        @test tv52("search_realized_peak_deg") < 5.0
        # ⚠⚠ AND THE PIN ABOVE IS ONE DRAG **PHASE**, SO IT IS NOT THE LAW — F1's own discipline
        # (*a threshold measured at one operating point is not a law*) turned on the FIX rather than
        # on the lesson. Flown at six phases spanning more than a quarter of the 1.667 s sweep
        # period, the settled fraction is 0.6662 … 0.6784 and the commanded peak is EXACTLY 6.0
        # every time — so the general claim is a BOUND, and the tight `atol` above belongs only to
        # the phase it was measured at. ⚠ A drag at tick 5600 reads 4.0705, which that `atol` would
        # fail; three phases are re-flown here so nobody tightens the bound onto one of them.
        for k_drag in (5450, 5600, 5900)
            sc2 = load_scenario(joinpath(base52, "slice52_coverage.yaml"))
            c2  = sc2.world.entities[:m1].comp
            for _ in 1:k_drag
                tick!(sc2.world, sc2.subs, sc2.dt_physics)
            end
            c2[:seeker_search_coverage_deg] = 6.0
            for _ in 1:1400
                tick!(sc2.world, sc2.subs, sc2.dt_physics)
            end
            t2 = get(sc2.world.env, :telemetry, Dict{String,Any}())
            told2  = Float64(t2["m1.search_offset_peak_deg"])
            flown2 = Float64(t2["m1.search_realized_peak_deg"])
            @test Float64(t2["m1.head_searching"]) == 1.0    # …still hunting, or the cell is empty
            @test told2 ≈ 6.0 atol = 1.0e-6                  # the COMMAND re-arms exactly, always
            @test 0.66 < flown2 / told2 < 0.69               # …and the head's share is phase-robust
        end
    end

    @testset "THE LOADER's REFUSALS for the new anchor — a crash guard and a dead-knob guard" begin
        # ⚠ `false` is refused rather than honoured: presence is the gate (the `seeker_search` /
        # `midcourse` posture), so a `false` would author the instrument while meaning the opposite.
        let y = joinpath(mktempdir(), "s.yaml")
            write(y, "name: t\n" *
                     "entities:\n" *
                     "  - {id: m1, kind: missile, pos: [0.0, 0.0, 0.0],\n" *
                     "     missile: {seeker: {gimbal_tau_s: 0.05, seeker_search: true,\n" *
                     "                        seeker_search_coverage_deg: 25.0,\n" *
                     "                        seeker_search_realized: false}}}\n")
            @test_throws ErrorException load_scenario(y)
        end
        # ⚠⚠ AND REFUSED WITHOUT THE SEARCH ITSELF — the dead-knob guard this project has caught six
        # times: the realized sweep is formed on the SEARCH arm of the seam, so on a wire with no
        # search there is nothing to measure and the key would be read by nothing.
        let y = joinpath(mktempdir(), "s.yaml")
            write(y, "name: t\n" *
                     "entities:\n" *
                     "  - {id: m1, kind: missile, pos: [0.0, 0.0, 0.0],\n" *
                     "     missile: {seeker: {gimbal_tau_s: 0.05, seeker_search_realized: true}}}\n")
            @test_throws ErrorException load_scenario(y)
        end
    end
end
