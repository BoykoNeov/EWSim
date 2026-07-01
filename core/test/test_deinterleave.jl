# test_deinterleave.jl — the pure PRI-deinterleaving lib vs its closed forms and the
# STRUCTURAL subharmonic trap (HANDOFF §9, slice-6 gate 1).
#
# Like two_ray / geometry (slices 2 / 5) this lib is DETERMINISTIC — there is no RNG in
# it (the draw lives in the ESM receiver, gate 2). So every check is exact with an
# EXPLICIT atol (never rtol-`≈0`). The headline is the phantom subharmonic pinned as a
# REAL over-detection (not passed by construction): on a stable, well-separated,
# non-harmonic 3-emitter stream cdif returns 4 PRIs (3 fundamentals + a phantom at
# 2×min) and sdif returns exactly 3 — the `n_pri` flip that is the slice's lesson.
#
# Units are FIRST-CLASS here (the §1 trifecta): PRIs are authored in µs, the lib works
# in SI seconds; a µs/s slip is this project's signature bug, so a units round-trip is
# pinned. All the params below (bin 20 µs, search band 3000 µs, C=15 levels, threshold
# 0.4·peak) were chosen PRINCIPLED-then-observed with a throwaway probe (the slice-3/4/5
# discipline). The binding search-band constraint (advisor, probe-confirmed) is the tight
# window `2·min_PRI < max_lag < 2·(second-smallest PRI)` = (2600, 3400) µs here: only the
# ONE phantom (2×1300) is in-band, the next harmonic (2×1700=3400) is out. `max_lag=3000`
# sits central (2700–3300 all give cdif=4); 2500→cdif=3 (dead knob), 3500→cdif=5. NB it is
# NOT "just above the max fundamental" — that's a coincidence here (2×1300≈2300) and fails
# for clustered PRI sets. The 0.4 threshold sits on a wide plateau (cdif=4 holds for
# threshold ∈ [0.30, 0.62]·peak; max in-band spurious peak 15 vs min kept count 32), NOT a
# knife-edge. SEQUENCE-SEARCH is INERT on this stable stream (min_seq 0/10/30 give the same
# PRIs — the threshold does the work); it discriminates only on noisy TOAs (gate 2).

@testset "deinterleave / PRI histogram primitives" begin

    US = 1.0e-6                          # µs → SI seconds (the boundary conversion)

    # Library params (SI seconds) — one shared set for BOTH the 3- and 2-emitter
    # fixtures (advisor's overfit guard: same params must do both, else they're tuned).
    BW      = 20.0 * US                  # histogram bin width
    MAXLAG  = 3000.0 * US                # PRI search band (just above the 2300 µs max)
    LEVELS  = 15                         # cumulative difference levels (C ≳ M·few)
    TFRAC   = 0.4                        # detection threshold as a fraction of peak
    SEQTOL  = 30.0 * US                  # sequence-search spacing tolerance
    MINSEQ  = 10                         # min pulses to call a train a PRI
    ATOL    = 50.0 * US                  # association neighbour tolerance

    # A stable interleaved TOA stream in SI seconds (no jitter / no spurious — the
    # phantom is STRUCTURAL, it must appear with zero RNG). Returns sorted TOAs + the
    # parallel truth ids (the receiver stamps these in gate 2).
    function gen_stream(pris_us, phases_us; dwell_us = 80_000.0)
        toas = Float64[]; truth = Symbol[]
        for (idx, (pri, ph)) in enumerate(zip(pris_us, phases_us))
            id = Symbol("e", idx); k = 0
            while ph + k * pri < dwell_us
                push!(toas, (ph + k * pri) * US); push!(truth, id); k += 1
            end
        end
        p = sortperm(toas)
        return toas[p], truth[p]
    end

    detect(toas; mode) = detect_pris(toas; mode = mode, bin_width = BW, max_lag = MAXLAG,
                                     levels = LEVELS, thresh_frac = TFRAC,
                                     seq_tol = SEQTOL, min_seq = MINSEQ)

    @testset "difference histogram raises the PRI peak AND its subharmonic (the trap)" begin
        # a LONE stable train: its PRI peak is real; the level-2/3 differences pile a
        # peak at 2×PRI / 3×PRI too — the structural cause of the phantom.
        toas, _ = gen_stream([1300.0], [0.0])
        h = difference_histogram(toas, BW, MAXLAG; levels = LEVELS)
        binof(τ_us) = floor(Int, (τ_us * US) / BW) + 1
        @test h[binof(1300.0)] > 0                       # the true PRI peak
        @test h[binof(2600.0)] > 0                       # the 2×PRI subharmonic pile-up
        # both are local maxima well above their neighbours (a genuine peak, not noise)
        @test h[binof(1300.0)] ≥ h[binof(1300.0) - 2]
        @test h[binof(2600.0)] ≥ h[binof(2600.0) - 2]
    end

    @testset "3-emitter [1300,1700,2300] µs: cdif=4 (+phantom), sdif=3 — the n_pri flip" begin
        toas, _ = gen_stream([1300.0, 1700.0, 2300.0], [0.0, 300.0, 700.0])
        cdif = sort(detect(toas; mode = :cdif))
        sdif = sort(detect(toas; mode = :sdif))

        # THE HEADLINE: cdif over-detects (phantom), sdif recovers the truth count.
        @test length(cdif) == 4
        @test length(sdif) == 3                          # == n_true

        # sdif returns exactly the 3 fundamentals, centroid-refined to within a bin.
        # (Observed error is < ½-bin — largest 7 µs on the 1700 µs PRI, which lands on a
        # bin edge; asserting one full bin keeps this robust if gate 2 retunes bin_width.)
        for (got, want) in zip(sdif, [1300.0, 1700.0, 2300.0])
            @test got ≈ want * US atol = BW
        end
        # cdif's extra PRI is the phantom at 2×min = 2×1300 = 2600 µs (a REAL
        # over-detection — pinned to the subharmonic, not `≈0`).
        @test cdif[4] ≈ 2600.0 * US atol = BW
        # and cdif's first three ARE the fundamentals (the phantom is the addition).
        for (got, want) in zip(cdif[1:3], [1300.0, 1700.0, 2300.0])
            @test got ≈ want * US atol = BW
        end
    end

    @testset "2-emitter [1300,1700] µs: cdif over-detects, sdif recovers (sharper)" begin
        # Note: with the SAME principled search band, only the 2×min phantom (2600) is
        # in-band; 3×1300 = 3900 falls OUTSIDE it, so cdif=3 (not 4). Still the lesson —
        # cdif hallucinates the subharmonic, sdif removes it.
        toas, _ = gen_stream([1300.0, 1700.0], [0.0, 300.0])
        cdif = sort(detect(toas; mode = :cdif))
        sdif = sort(detect(toas; mode = :sdif))
        @test length(cdif) == 3
        @test length(sdif) == 2
        for (got, want) in zip(sdif, [1300.0, 1700.0])
            @test got ≈ want * US atol = BW
        end
        @test cdif[3] ≈ 2600.0 * US atol = BW            # the 2×1300 phantom
    end

    @testset "subharmonic check in isolation (SDIF's real rule, not a fudge)" begin
        # the internal predicate: a 2×/3× multiple with its base present → harmonic;
        # a fundamental (ratio 1) → not.
        @test EWSim._is_harmonic(2600.0 * US, 1300.0 * US, SEQTOL) == true
        @test EWSim._is_harmonic(3900.0 * US, 1300.0 * US, SEQTOL) == true
        @test EWSim._is_harmonic(1700.0 * US, 1300.0 * US, SEQTOL) == false   # ratio ≈1.31
        @test EWSim._is_harmonic(2300.0 * US, 1300.0 * US, SEQTOL) == false   # ratio ≈1.77
        # non-integer near-multiple is NOT rejected (guards against false-rejecting a
        # real fundamental — why the [1300,1700,2300] ratios were chosen non-harmonic).
        @test EWSim._is_harmonic(2650.0 * US, 1300.0 * US, SEQTOL) == false   # 60 µs off 2×

        # end-to-end: a lone stable train → cdif marks the phantom, sdif drops ONLY it.
        toas, _ = gen_stream([1300.0], [0.0])
        cdif = sort(detect(toas; mode = :cdif))
        sdif = sort(detect(toas; mode = :sdif))
        @test length(cdif) == 2
        @test cdif[1] ≈ 1300.0 * US atol = BW
        @test cdif[2] ≈ 2600.0 * US atol = BW
        @test length(sdif) == 1
        @test sdif[1] ≈ 1300.0 * US atol = BW
    end

    @testset "association: finite, 1.0 on a lone train, high on interleaved" begin
        # a LONE clean train — association is unambiguous ⇒ exactly 1.0 (every pulse to
        # its emitter; the phantom's group is still all-emitter-1, so cdif scores 1.0 too).
        toas1, truth1 = gen_stream([1300.0], [0.0])
        for mode in (:cdif, :sdif)
            a = associate(toas1, detect(toas1; mode = mode); tol = ATOL)
            @test assoc_pct(a, truth1) == 1.0
        end

        # 3 interleaved emitters — real coincidences cap it slightly below 1 (the honest
        # boundary; direction cdif-vs-sdif NOT pinned, only finite + high).
        toas3, truth3 = gen_stream([1300.0, 1700.0, 2300.0], [0.0, 300.0, 700.0])
        for mode in (:cdif, :sdif)
            a  = associate(toas3, detect(toas3; mode = mode); tol = ATOL)
            ap = assoc_pct(a, truth3)
            @test isfinite(ap) && 0.0 ≤ ap ≤ 1.0
            @test ap > 0.8                                # high, not perfect
        end

        # a true pulse marooned in a spurious-MAJORITY group scores 0 (a spurious pulse
        # can never be the "correct emitter").
        @test assoc_pct([1, 1, 1], [SPURIOUS_ID, SPURIOUS_ID, :e1]) == 0.0
        @test assoc_pct(Int[], Symbol[]) == 1.0           # no true pulses → vacuous 1.0
    end

    @testset "units round-trip (µs ↔ SI seconds — the §1 trifecta)" begin
        # author a PRI in µs, feed SI seconds, recover it back in µs within a bin.
        pri_us = 1550.0
        toas, _ = gen_stream([pri_us], [0.0])
        got = detect(toas; mode = :sdif)
        @test length(got) == 1
        @test got[1] / US ≈ pri_us atol = (BW / US) / 2   # within ½-bin, in µs
    end

    @testset "degenerate streams do not throw (empty / single pulse / one emitter)" begin
        @test difference_histogram(Float64[], BW, MAXLAG; levels = LEVELS) == zeros(150)
        @test detect(Float64[]; mode = :cdif) == Float64[]
        @test detect([1.0e-3]; mode = :sdif) == Float64[]           # single pulse → no diffs
        @test associate(Float64[], [1.3e-3]; tol = ATOL) == Int[]
        @test associate([1.0e-3], Float64[]; tol = ATOL) == [0]     # no PRIs → unassigned
        # a lone emitter is a valid (if trivial) recovery, never a throw.
        toas, truth = gen_stream([1700.0], [0.0])
        @test !isempty(detect(toas; mode = :sdif))
        @test assoc_pct(associate(toas, detect(toas; mode = :sdif); tol = ATOL), truth) == 1.0
        # bad mode rejected
        @test_throws ArgumentError detect_pris(toas; mode = :nope, bin_width = BW,
            max_lag = MAXLAG, levels = LEVELS, seq_tol = SEQTOL, min_seq = MINSEQ)
    end
end
