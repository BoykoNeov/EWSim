# deinterleave.jl — pulse-train deinterleaving by PRI (HANDOFF §9-style SHARED LIB,
# slice-6 gate 1).
#
# A single ESM receiver hearing M radars at once sees ONE jumbled Time-of-Arrival
# stream, not M clean trains. This lib recovers each emitter's Pulse Repetition
# Interval (PRI) from that soup, the classic difference-histogram way, and groups the
# pulses back onto their trains. It is a genuinely NEW §9 lib (the PRI-histogram math
# is not the GDOP/LS/CFAR family) — pure, no `w.rng`, closed-form, dependency-free
# (only base Julia; no StaticArrays/LinearAlgebra), so a future PRI-transform rung or a
# comms-EW hop-deinterleaver reuses it. It takes plain `Vector{Float64}` TOAs and
# returns plain PRI / assignment data — it knows nothing about World/Subsystem types.
#
# Everything is SI seconds in / out (the §1 units trifecta — a µs/s slip is this
# project's signature bug; the loader/telemetry boundary converts µs↔s, never here).
#
# The lesson (the `:deinterleaver` fidelity, `cdif ↔ sdif`):
#   • The DIFFERENCE HISTOGRAM (count of pulse-pair time-differences vs lag) raises
#     peaks at each emitter's PRI out of the density soup — that emergence IS the
#     killer visual.
#   • :cdif (the BIASED baseline / named approximation, HANDOFF §1) — a stable train
#     at PRI = T piles cumulative difference-counts at 2T, 3T… nearly as tall as T
#     (level-2 pairs sit at 2T, etc.), and a 2T-spaced subsequence DOES exist, so a
#     naive "accept every peak that forms a train" declares a PHANTOM emitter at the
#     subharmonic — a radar that isn't there.
#   • :sdif (Milojević–Popović, the higher-fidelity rung) — before accepting a
#     candidate τ, reject it if a sub-multiple (τ/2, τ/3, …) is ALSO a candidate: the
#     fundamental, not its harmonic, is the real PRI. This single added rule removes
#     the phantom (the de-risked result: cdif = 4 → sdif = 3 on [1300,1700,2300] µs).
#
# Three mechanisms, three jobs (advisor) — but their labour is UNEVEN on a stable
# stream:
#   1. the histogram SEARCH BAND (`max_lag`) + THRESHOLD bound HOW MANY harmonics become
#      candidates — on the deterministic showcase these two do ALL the discrimination.
#   2. the SEQUENCE SEARCH is meant to remove above-threshold bins that are not real
#      trains (cross-emitter coincidence lags). **On a perfectly-stable stream it is
#      INERT** (probe-confirmed: `min_seq ∈ {0,10,30,50}` give the IDENTICAL PRI set) —
#      every pairwise lag of periodic emitters recurs, so a coincidence lag forms just
#      as good a "train" as a real one; only the threshold separates them. Its
#      DISCRIMINATING role appears with spurious / jittered TOAs (the receiver draw,
#      gate 2) and is validated there, not here. It stays in the pipeline (it is the
#      real algorithm and it matters once the stream is noisy), documented honestly.
#   3. the SUBHARMONIC CHECK (sdif only) removes real harmonics whose fundamental is
#      present — the SOLE cdif↔sdif differentiator.
#
# The SEARCH BAND is the subtle scenario constraint (advisor): `max_lag` must satisfy
# `2·min_PRI < max_lag < 2·(second-smallest PRI)` so EXACTLY the one phantom (2×min) is
# in-band and the next harmonic (2×second-smallest) is out. Too small → the phantom is
# excluded → cdif == sdif, a DEAD KNOB; too large → a harmonic forest → cdif ≫ n_true.
# "Just above the largest fundamental" is NOT the rule — it happens to work here only
# because 2×1300 ≈ 2300; for a clustered set like [2000,2300,2600] it excludes the
# phantom (2×2000=4000) and kills the lesson. Gate 3's scenario MUST honour the window.
#
# Named approximations (HANDOFF §1) that live in the SUBSYSTEM (esm.jl), not here —
# receiver-side TOA jitter (not emitter PRI instability), frozen dwell geometry, R/c
# omitted — are documented there. This lib is the pure math; it is deterministic given
# the TOA stream (no draw-topology hazard, like slices 2/4/5).
#
# The faithful sequential-per-level / adaptive-exponential-threshold SDIF (and Nelson's
# PRI-transform) are NAMED FUTURE REFINEMENTS — the shared-cumulative + post-filter
# form here is what the de-risk probe proved and keeps the display coherent (same bars,
# same threshold line, only the markers move between rungs).

# The deinterleaver-fidelity rungs (slice 6). The SINGLE source of truth: the
# extractor validates against this, and gate-2's `LIVE_FIDELITY_MODES` will REFERENCE
# it (the `CFAR_MODES`/`ESTIMATOR_MODES` one-list-no-drift lesson). Defined HERE
# (deinterleave.jl is included before radar.jl) so that reference needs no include-order
# gymnastics.
#   • :cdif — accept every train-forming peak (declares the phantom subharmonic).
#   • :sdif — additionally reject a candidate whose sub-multiple is also a candidate.
const DEINTERLEAVER_MODES = (:cdif, :sdif)

# A spurious (noise/clutter) TOA carries this sentinel truth id (no emitter). The
# receiver stamps it (esm.jl); `assoc_pct` scores true pulses only, so a spurious pulse
# can never be "correct."
const SPURIOUS_ID = :spurious

"""
    difference_histogram(toas, bin_width, max_lag; levels = 1) -> Vector{Float64}

The CUMULATIVE difference histogram of a sorted TOA stream: for levels `c = 1…levels`,
bin every level-`c` difference `t_{i+c} − t_i` (over `i = 1…N−c`) that falls in
`(0, max_lag)` into a `bin_width`-wide bin, summing all levels into one curve.

`n_bins = floor(max_lag / bin_width)`; bin `b` covers `[(b−1)·bw, b·bw)` with center
`(b−0.5)·bw`. Interleaving scatters an emitter's PRI across lags — with M roughly-equal
emitters the same-emitter pulses sit ≈M apart in the merged stream, so its PRI shows up
near level `c ≈ M`; accumulating `c = 1…levels` (`levels ≳ M·few`) collects it.

Pure, no RNG. **`toas` is assumed sorted ascending** (the receiver ships a sorted
stream; the top-level [`detect_pris`](@ref) sorts defensively). SI seconds throughout.
"""
function difference_histogram(toas::AbstractVector{<:Real}, bin_width::Real, max_lag::Real;
                              levels::Integer = 1)
    bw = Float64(bin_width); ml = Float64(max_lag)
    n_bins = max(1, floor(Int, ml / bw))
    hist = zeros(Float64, n_bins)
    N = length(toas)
    @inbounds for c in 1:levels
        c ≥ N && break
        for i in 1:(N - c)
            d = Float64(toas[i + c]) - Float64(toas[i])
            (d ≤ 0.0 || d ≥ ml) && continue
            b = floor(Int, d / bw) + 1
            (1 ≤ b ≤ n_bins) && (hist[b] += 1.0)
        end
    end
    return hist
end

# Count-weighted centroid PRI of a peak at bin `b`, over `b` and its immediate
# neighbors — refines the coarse `(b−0.5)·bw` bin-center (which leaves a ≤½-bin
# offset) to the sub-bin true PRI. Falls back to the bin center if the local mass is 0.
function _bin_centroid(hist::AbstractVector{<:Real}, b::Int, bin_width::Float64)
    lo = max(1, b - 1); hi = min(length(hist), b + 1)
    num = 0.0; den = 0.0
    @inbounds for j in lo:hi
        num += hist[j] * (j - 0.5) * bin_width
        den += hist[j]
    end
    return den > 0 ? num / den : (b - 0.5) * bin_width
end

# Is bin `b` a local peak (≥ both neighbors), at or above `thresh`? Array ends compare
# against the one in-bounds neighbor. Ties (a flat top) count as a peak at the left
# edge of the plateau only, to avoid double-declaring one peak.
function _is_peak(hist::AbstractVector{<:Real}, b::Int, thresh::Float64)
    hb = hist[b]
    hb ≥ thresh || return false
    left  = b > 1              ? hist[b - 1] : -Inf
    right = b < length(hist)   ? hist[b + 1] : -Inf
    return hb > left && hb ≥ right          # strict-left / weak-right breaks plateau ties
end

# Sequence-search support for a candidate PRI τ: the number of pulses that have a
# partner at spacing ≈ τ (within `tol`) somewhere in the stream — i.e. how many pulses
# participate in a τ-spaced train. A real PRI (or its harmonic — every T-pulse has a
# partner at 2T too) scores high. On a PERFECTLY-STABLE stream a cross-emitter
# coincidence lag ALSO scores high (its lag recurs periodically), so this is INERT there
# (see the module notes); it earns its keep on spurious/jittered TOAs (gate 2). O(N²),
# N ≲ few hundred over a dwell.
function _sequence_support(toas::AbstractVector{<:Real}, τ::Float64, tol::Float64)
    N = length(toas)
    cnt = 0
    @inbounds for i in 1:N
        ti = Float64(toas[i])
        hit = false
        for j in 1:N
            j == i && continue
            if abs(abs(Float64(toas[j]) - ti) - τ) ≤ tol
                hit = true; break
            end
        end
        hit && (cnt += 1)
    end
    return cnt
end

# Is τ an integer (≥2) multiple of `base`, within `tol` of the nearest such multiple?
# (the SDIF subharmonic test — τ is a harmonic of a smaller candidate `base`).
function _is_harmonic(τ::Float64, base::Float64, tol::Float64)
    base > 0 || return false
    n = round(Int, τ / base)
    return n ≥ 2 && abs(τ - n * base) ≤ tol
end

"""
    detect_pris(toas; mode = :cdif, bin_width, max_lag, levels,
                thresh_frac = 0.25, seq_tol, min_seq, sub_tol = seq_tol) -> Vector{Float64}

Recover the emitter PRIs from a (sorted) interleaved TOA stream. Builds the cumulative
[`difference_histogram`](@ref), takes every local-peak bin at or above
`thresh_frac · max(hist)` whose sequence-search support (pulses forming a τ-train,
tolerance `seq_tol`) reaches `min_seq`, and returns the centroid-refined PRIs.

`mode` selects the fidelity rung ([`DEINTERLEAVER_MODES`](@ref)):
  • `:cdif` — accept every surviving candidate (declares the phantom subharmonic).
  • `:sdif` — additionally drop a candidate τ that is an integer multiple (within
    `sub_tol`) of a SMALLER accepted candidate (the subharmonic check removes the
    phantom; the fundamental is the real PRI).

Both rungs share the SAME histogram, threshold, and sequence search — only the
acceptance rule differs (a crisp same-bars / different-markers visual). PRIs are
returned sorted ascending. Pure, no RNG. SI seconds in / out. `toas` is sorted
defensively.
"""
function detect_pris(toas::AbstractVector{<:Real};
                     mode::Symbol = :cdif,
                     bin_width::Real, max_lag::Real, levels::Integer,
                     thresh_frac::Real = 0.4,
                     seq_tol::Real, min_seq::Integer, sub_tol::Real = seq_tol)
    mode in DEINTERLEAVER_MODES ||
        throw(ArgumentError("deinterleaver mode :$mode not one of $(DEINTERLEAVER_MODES)"))
    t = issorted(toas) ? toas : sort(toas)
    length(t) < 2 && return Float64[]                     # degenerate: no differences

    bw   = Float64(bin_width)
    hist = difference_histogram(t, bw, max_lag; levels = levels)
    peak = maximum(hist)
    peak ≤ 0 && return Float64[]

    thresh = Float64(thresh_frac) * peak
    st     = Float64(seq_tol)
    ms     = Int(min_seq)

    # Candidate peaks, ascending in PRI (the order the subharmonic check needs — a
    # harmonic is only ever rejected against a SMALLER accepted fundamental).
    candidates = Float64[]
    @inbounds for b in 1:length(hist)
        _is_peak(hist, b, thresh) || continue
        τ = _bin_centroid(hist, b, bw)
        _sequence_support(t, τ, st) ≥ ms || continue      # not a real train → drop
        push!(candidates, τ)
    end

    mode === :cdif && return candidates

    # :sdif — accept ascending, dropping a τ whose sub-multiple is already accepted.
    stol = Float64(sub_tol)
    accepted = Float64[]
    @inbounds for τ in candidates
        any(base -> _is_harmonic(τ, base, stol), accepted) && continue
        push!(accepted, τ)
    end
    return accepted
end

"""
    associate(toas, pris; tol) -> Vector{Int}

Assign each pulse of the (sorted) stream to the detected-PRI train it best belongs to,
by TWO-SIDED support: a genuine train member has a partner at `−τ` AND `+τ`. For pulse
`i`, score each PRI `pris[j]` by how many of its two neighbor slots (`t_i ± pris[j]`)
hold a pulse within `tol` (0, 1, or 2), and assign to the highest-scoring PRI (score
≥ 1); ties break toward the SMALLER τ (the fundamental, not its harmonic — advisor).
Score 0 (no partner either side) ⇒ `0` (unassigned — a spurious pulse or a stray).
Returns indices into `pris` (0 = unassigned), aligned to the input `toas` order.

Two-sided support beats single-sided nearest-neighbor on commensurate PRIs: an interior
member scores 2 for its own train but only 1 (or 0) for a cross-emitter coincidence, so
the fundamental wins. Perfect (1.0) separation is only guaranteed for a lone train; with
several interleaved stable emitters real coincidences cap it slightly below 1 even on a
noise-free stream (the honest boundary — `assoc_pct` is finite, its cdif-vs-sdif
direction left unpinned; see [`assoc_pct`](@ref)). Shared by BOTH rungs (the rung
changes only WHICH PRIs are found). Pure, no RNG. `toas` assumed sorted ascending.
"""
function associate(toas::AbstractVector{<:Real}, pris::AbstractVector{<:Real}; tol::Real)
    N = length(toas); K = length(pris)
    assign = zeros(Int, N)
    (K == 0 || N == 0) && return assign
    tl = Float64(tol)
    order = sortperm(collect(Float64.(pris)))       # ascending τ → fundamental wins ties
    @inbounds for i in 1:N
        ti = Float64(toas[i])
        best = 0; bestsup = 0; bestres = Inf
        for jj in order
            τ = Float64(pris[jj])
            rminus = Inf; rplus = Inf                # nearest residual on each side
            for k in 1:N
                k == i && continue
                dt = Float64(toas[k]) - ti
                if dt > 0
                    r = abs(dt - τ); r < rplus && (rplus = r)
                else
                    r = abs(-dt - τ); r < rminus && (rminus = r)
                end
            end
            sup = (rminus ≤ tl ? 1 : 0) + (rplus ≤ tl ? 1 : 0)
            res = min(rminus, rplus)
            # higher support wins; equal support → smaller residual (ascending τ already
            # broke the exact tie toward the fundamental via the strict comparisons).
            if sup > bestsup || (sup == bestsup && sup > 0 && res < bestres)
                bestsup = sup; bestres = res; best = jj
            end
        end
        assign[i] = bestsup ≥ 1 ? best : 0
    end
    return assign
end

"""
    assoc_pct(assign, truth) -> Float64

Fraction of TRUE (non-[`SPURIOUS_ID`](@ref)) pulses assigned to the correct emitter,
scored against the receiver-stamped `truth` ids (aligned to `assign`). Each assigned
group's emitter is its MAJORITY truth id; a pulse is correct if its truth id equals its
group's majority (a spurious pulse never counts, and unassigned pulses count against).
Returns a fraction in `[0, 1]`; if there are no true pulses it is `1.0` (vacuously
clean) — always finite, never NaN.

The phantom subharmonic MAY steal pulses from its fundamental and lower cdif's
`assoc_pct`, but only if association doesn't tie-break toward the higher-support
fundamental — so its DIRECTION (cdif < sdif) is left unpinned (advisor); `n_pri` is the
de-risked headline scalar. This just computes the score, finite.
"""
function assoc_pct(assign::AbstractVector{<:Integer}, truth::AbstractVector{Symbol})
    n_true = count(!=(SPURIOUS_ID), truth)
    n_true == 0 && return 1.0
    K = isempty(assign) ? 0 : maximum(assign)
    correct = 0
    for g in 1:K
        counts = Dict{Symbol, Int}()
        @inbounds for i in eachindex(assign)
            assign[i] == g || continue
            counts[truth[i]] = get(counts, truth[i], 0) + 1
        end
        isempty(counts) && continue
        maj = argmax(counts)                     # the group's majority truth id
        maj === SPURIOUS_ID && continue          # a spurious-majority group scores 0
        correct += counts[maj]
    end
    return correct / n_true
end
