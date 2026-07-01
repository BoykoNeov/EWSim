# esm.jl — the multi-emitter EW subsystems that light PHASES 2 + 3 + 4 of the tick
# contract IN ONE PIPELINE (HANDOFF §3, §10 item 6, slice-6 gate 2) — the phase-contract
# CAPSTONE.
#
# Slice 4 lit build_env! (phase 2, the jammer noise floor); slice 5 lit decide! (phase 4,
# the geolocator). Slice 6 runs all three derived phases as ONE chain through `w.env`:
#
#   • PulseEmitter  — phase-2 `build_env!`: publishes its constant-PRI train PARAMS
#                     (pri/phase/pulse_width/pos + true id) to `w.env[:emitters]`. RNG-free,
#                     order-independent — it does NOT generate pulses (that would be hundreds
#                     of TOAs every tick); the receiver does, on look-ticks.
#   • ESMReceiver   — phase-3 `observe!`, the ONE DRAW SITE: reads every `env[:emitters]`
#                     record and, on a look-tick, generates the full interleaved Time-of-
#                     Arrival stream (deterministic emit grid + per-pulse TOA jitter +
#                     probability-of-intercept drop + static spurious TOAs), stamps each pulse
#                     with its truth id, and writes the sorted stream to `env[:toa_stream]`.
#   • Deinterleaver — phase-4 `decide!`: reads the stream, runs the difference-histogram / PRI
#                     extraction / association per the `:deinterleaver` fidelity, and publishes
#                     the histogram/threshold arrays + n_pri/assoc_pct/n_true telemetry.
#
# Phases 2→3→4 run in that fixed order in `tick!`, so a PulseEmitter's params are guaranteed
# visible to the receiver, and the receiver's stream to the Deinterleaver, the SAME tick
# (correctness-by-construction, as the jammer→radar and DFSensor→Geolocator couplings got).
# `env` is cleared + rebuilt each tick, so a stale stream can't leak. The §3 coupling done
# right — emitters→receiver and receiver→deinterleaver both THROUGH `env`, never a direct call.
#
# This file is included AFTER radar.jl (mirroring geolocation.jl) but has NO back-dep on
# radar's symbols: R/c propagation delay is pedagogically inert for the PRI lesson and OMITTED
# (a constant per-emitter offset cancels in the same-emitter differences the true-PRI peaks
# come from), so the ESM needs no `_range`. It reuses geometry.jl's `_finite` (in scope,
# geometry.jl precedes radar.jl) and deinterleave.jl's pure PRI math (`difference_histogram`,
# `detect_pris`, `associate`, `assoc_pct`, `DEINTERLEAVER_MODES`, `SPURIOUS_ID`).
#
# NAMED APPROXIMATIONS (HANDOFF §1 — no hidden approximations), all living HERE (the
# subsystem), not in the pure lib:
#   • Jitter is RECEIVER TOA-measurement noise, NOT emitter PRI instability. Receiver jitter
#     is independent per pulse (every lag stays at √2·σ); an emitter's intrinsic PRI random-
#     walk would grow the level-c spread ∝√c and degrade the higher-lag histogram peaks CDIF
#     leans on — so true emitter PRI instability is the HARDER, deferred case. We model the
#     easier one and say so.
#   • Geometry frozen over the dwell (range evaluated once at look time) — and per the R/c
#     omission above the range barely matters anyway.
#   • R/c propagation delay OMITTED (see include-order note). TDOA geolocation, which WOULD
#     exploit those offsets, is a future slice.
#   • DWELL WINDOW is PHASE-REFERENCED `[0, T_dwell)`, NOT the plan's literal `[t, t+T_dwell)`
#     (a deliberate, documented deviation — advisor). The emit grid is `phase + k·PRI` for
#     `k ≥ 0` while `< T_dwell`, matching gate-1's `gen_stream`. This makes the candidate
#     count a function of STATIC config only (not `w.t`), so the per-look draw count is truly
#     time-invariant and the exact-draw reconstruction test is `w.t`-independent. The scene is
#     deliberately static (emitters need not move — the interactive levers are measurement
#     quality + the algorithm, not motion), so nothing is lost. Consequence stated plainly:
#     the stream is structurally identical every look; only the drawn noise differs.
#
# NO DRAW-TOPOLOGY HAZARD (the slice-2/4/5 shape, NOT slice-3's `:cfar` guard): the receiver
# draws a FIXED count (`2·n_candidate + n_spurious`) independent of the `:deinterleaver` rung
# AND of the live slider VALUES (a slider scales a draw or flips a keep-decision, never the
# draw COUNT). Generation + every draw live in phase-3 `observe!`, so the phase-4 rung selects
# only post-processing. Hence `:deinterleaver` is introduce-safe AND toggle-bit-identical
# (the `:ep`/`:estimator` contract), and an ESM-free scenario is byte-identical to slices 1–5.

# µs ↔ SI-seconds boundary (the §1 units trifecta): PRIs/jitter/dwell are authored + displayed
# in µs, stored + computed in SI seconds. The loader converts in; the telemetry converts out.
const _US = 1.0e-6

# The per-dwell candidate-pulse bound (HANDOFF §1: no silent truncation). `T_dwell / min_PRI`
# can explode the histogram + wire frame (100 ms / 10 µs = 10 000 TOAs/frame); the loader
# rejects a runaway AUTHORED config at LOAD (`_validate_esm`, scenario.jl) so a fat frame is a
# clear error, not a mystery slowdown. The de-risk probe ran ~150 pulses; this cap leaves ample
# margin for the showcase while catching a genuine blow-up.
const _ESM_MAX_PULSES = 1000

# One pulse emitter's published parameters — the `env[:emitters]` record (INTERNAL, like
# `JamContribution`/`BearingRecord`). Carries the constant-PRI train (pri/phase/pulse_width, SI
# seconds), the truth `id` (the receiver stamps it onto every pulse — ground truth for the
# association score, the slice-5 err_m-vs-truth analog), and `pos` (carried for a future TDOA
# slice; the PRI lesson ignores it). Appended in sorted-emitter-id order (the PulseEmitter subs
# run in the loader's sorted-id order), so the receiver's cross-emitter draw order is deterministic.
const EmitterParams = @NamedTuple{id::Symbol, pri::Float64, phase::Float64,
                                  pulse_width::Float64, pos::Vec3}

# The interleaved TOA stream the receiver hands the deinterleaver — the `env[:toa_stream]`
# record (INTERNAL). Parallel arrays: sorted ascending `toas` (SI seconds) and the per-pulse
# truth `ids` (a spurious TOA carries `SPURIOUS_ID`). The deinterleaver re-sorts defensively.
const ToaStream = @NamedTuple{toas::Vector{Float64}, truth::Vector{Symbol}}

# --- PulseEmitter: a phase-2 param publisher ------------------------------------

"""
    PulseEmitter(id)

The pulse emitter `id` as a phase-2 `build_env!` subsystem — it publishes its constant-PRI
train PARAMS (`comp[:pri] :phase :pulse_width`, SI seconds) + truth id + `pos` as an
[`EmitterParams`](@ref) record into `w.env[:emitters]`. RNG-free and order-independent (the
§3 build_env! contract — the receiver collects them). It does NOT generate pulses; that is
the receiver's phase-3 job, on look-ticks only (hundreds of TOAs/tick otherwise). A
`ConstantVelocity` mover (the loader pairs one) lets it move, though the scene is static.
"""
struct PulseEmitter <: Subsystem
    id::Symbol
end

function build_env!(pe::PulseEmitter, w::World)
    e = w.entities[pe.id]
    emitters = get!(() -> EmitterParams[], w.env, :emitters)
    push!(emitters, (id = pe.id, pri = Float64(e.comp[:pri]),
                     phase = Float64(e.comp[:phase]),
                     pulse_width = Float64(e.comp[:pulse_width]), pos = e.pos))
    return nothing
end

# --- ESMReceiver: the phase-3 one-draw-site --------------------------------------

# Generate the interleaved TOA stream for ONE dwell — THE ONE DRAW SITE of the slice, in the
# EXACT §1-pinned order (the determinism golden rides on this; the `sqrt(snr/2)` / noise-then-
# signal bug class). Draw order, unconditional except where noted:
#   1. emitters in SORTED-ID order (sorted defensively so the order is self-contained, not
#      dependent on subsystem-assembly order);
#   2. within an emitter, pulses in EMIT order (k ascending), grid `phase + k·PRI` over
#      `[0, T_dwell)` (phase-referenced — see the module note);
#   3. per candidate pulse: draw JITTER (`randn`) THEN INTERCEPT (`rand`), BOTH UNCONDITIONALLY
#      (so `p_intercept` flips the keep/drop DECISION, never the draw COUNT), keeping the
#      jittered TOA iff the intercept draw `< p_intercept`;
#   4. THEN the static `n_spurious` uniform (`rand`) TOAs LAST.
# Total draws = `2·n_candidate + n_spurious`, FIXED by static config (independent of the rung
# or any slider value). Pure of world state — takes plain params + an rng — so gate 2's
# exact-draw test replays it off a fresh `Xoshiro`. Returns sorted TOAs + parallel truth ids.
function _draw_toa_stream(emitters::Vector{EmitterParams}, t_dwell::Float64,
                          σ_toa::Float64, p_intercept::Float64, n_spurious::Int,
                          rng::AbstractRNG)
    toas = Float64[]; truth = Symbol[]
    for ep in sort(emitters, by = e -> e.id)          # 1. emitters, sorted id
        k = 0
        while ep.phase + k * ep.pri < t_dwell         # 2. pulses, emit order
            t_emit   = ep.phase + k * ep.pri
            jittered = t_emit + σ_toa * randn(rng)    # 3a. JITTER draw (unconditional)
            kept     = rand(rng) < p_intercept        # 3b. INTERCEPT draw (unconditional)
            if kept
                push!(toas, jittered); push!(truth, ep.id)
            end
            k += 1
        end
    end
    for _ in 1:n_spurious                             # 4. spurious LAST
        push!(toas, rand(rng) * t_dwell)
        push!(truth, SPURIOUS_ID)
    end
    order = sortperm(toas)                            # sort (consumes no RNG)
    return toas[order], truth[order]
end

"""
    ESMReceiver(id; revisit_s = 0.0)

The ESM intercept receiver `id` as a phase-3 `observe!` subsystem — THE ONE DRAW SITE. On a
look-tick (gated to `revisit_s` via `comp[:next_look_t]`, the radar's cadence) it reads every
[`EmitterParams`](@ref) in `w.env[:emitters]` and generates the interleaved TOA stream over
the dwell ([`_draw_toa_stream`](@ref), the §1-pinned draw order), stamps each pulse with its
truth id, stores the realization in `comp`, and writes it to `w.env[:toa_stream]`. Between
looks the last realization is republished (the readout never blanks — the slice-1/2/3
pattern). The receiver config lives in the `:esm` entity's `comp` bag: static `:t_dwell`
`:n_spurious` and the histogram/extraction params (`:bin_width :max_lag :levels :thresh_frac
:seq_tol :min_seq :assoc_tol` — read by the co-located Deinterleaver), plus the LIVE sliders
`:jitter_us` (µs, converted at the consumer) + `:p_intercept` (both draw-count-invariant).
"""
struct ESMReceiver <: Subsystem
    id::Symbol
    revisit_s::Float64
end
ESMReceiver(id::Symbol; revisit_s::Real = 0.0) = ESMReceiver(id, Float64(revisit_s))

function observe!(rx::ESMReceiver, w::World)
    esm = w.entities[rx.id]
    c   = esm.comp
    is_look = w.t + 1e-12 ≥ get(c, :next_look_t, 0.0)
    if is_look
        # LIVE sliders sanitized at the consumer (the "a live config can't crash a tick"
        # watch-item): jitter_us ≥ 0 (µs→s), p_intercept clamped to [0,1] (so a slider to 0 →
        # an empty dwell, which the extractor tolerates; to >1 can't over-keep). n_spurious is
        # STATIC (changing it changes the draw count → replay desync — draw-count-invariant).
        σ_toa   = max(Float64(get(c, :jitter_us, 0.0)) * _US, 0.0)
        p_int   = clamp(Float64(get(c, :p_intercept, 1.0)), 0.0, 1.0)
        n_spur  = max(0, Int(get(c, :n_spurious, 0)))
        t_dwell = Float64(c[:t_dwell])
        emitters = collect(EmitterParams, get(w.env, :emitters, EmitterParams[]))
        toas, truth = _draw_toa_stream(emitters, t_dwell, σ_toa, p_int, n_spur, w.rng)
        c[:toa_stream]  = toas
        c[:truth_ids]   = truth
        c[:next_look_t] = get(c, :next_look_t, 0.0) + rx.revisit_s
    end
    if haskey(c, :toa_stream)                         # republish (readout never blanks)
        w.env[:toa_stream] = ToaStream((c[:toa_stream]::Vector{Float64},
                                        c[:truth_ids]::Vector{Symbol}))
    end
    return nothing
end

# --- Deinterleaver: a phase-4 fusion node ---------------------------------------

"""
    Deinterleaver(id)

The co-located deinterleaver `id` as a phase-4 `decide!` subsystem — reads
`w.env[:toa_stream]` (the receiver's phase-3 output), builds the cumulative difference
histogram, extracts the emitter PRIs per the `:deinterleaver` fidelity (`get(w.fidelity,
:deinterleaver, :cdif)` — [`detect_pris`](@ref)), associates each pulse to its train
([`associate`](@ref)), and publishes:

  • `<id>.n_pri` (detected PRI count — the load-bearing scalar that FLIPS between rungs:
    cdif over-counts a phantom subharmonic, sdif recovers `n_true`) + `<id>.n_true` (the
    truth emitter count, from the `:pulse_emitter` entity count — NOT distinct-in-stream, so
    a `p_intercept`→0 slider can't lower it);
  • `<id>.assoc_pct` (the association purity, finite);
  • `<id>.histogram` + `<id>.threshold` (the FIXED-length cumulative-count curve + its flat
    detection threshold — CORE output, the client never recomputes it; the CFAR array-
    telemetry precedent). Both are RUNG-INDEPENDENT (the shared cumulative pipeline) — the
    rung changes ONLY which PRIs are marked (a crisp same-bars / different-markers visual);
  • `<id>.pri_us` / `<id>.toa_us` / `<id>.assign` (display-only variable-length arrays —
    NEVER asserted on; the tests pin the scalars + the fixed histogram).

Pure / no RNG (the draw is the receiver's), so the rung selects only post-processing — no
draw-topology hazard. All params come from the `:esm` entity's `comp` bag (static, load-time).
Publishes nothing if no stream exists (an ESM-free world never writes `env[:toa_stream]`).
"""
struct Deinterleaver <: Subsystem
    id::Symbol
end

function decide!(d::Deinterleaver, w::World)
    stream = get(w.env, :toa_stream, nothing)
    stream === nothing && return nothing
    toas  = stream.toas
    truth = stream.truth
    c = w.entities[d.id].comp

    mode = get(w.fidelity, :deinterleaver, :cdif)
    mode in DEINTERLEAVER_MODES ||
        error("Deinterleaver: deinterleaver fidelity :$mode not implemented " *
              "($(join(DEINTERLEAVER_MODES, " | ")))")

    bw = Float64(c[:bin_width]); ml = Float64(c[:max_lag]); lv = Int(c[:levels])
    tf = Float64(c[:thresh_frac]); st = Float64(c[:seq_tol]); ms = Int(c[:min_seq])
    at = Float64(c[:assoc_tol])

    # The cumulative histogram + its flat threshold line are RUNG-INDEPENDENT (shared
    # pipeline); the rung changes only the accepted-PRI markers. Threshold = thresh_frac·peak,
    # the same scalar `detect_pris` uses, shipped as a flat curve so the client draws the line.
    hist   = difference_histogram(toas, bw, ml; levels = lv)
    peak   = isempty(hist) ? 0.0 : maximum(hist)
    thresh = fill(tf * peak, length(hist))

    pris   = detect_pris(toas; mode = mode, bin_width = bw, max_lag = ml, levels = lv,
                         thresh_frac = tf, seq_tol = st, min_seq = ms)
    assign = associate(toas, pris; tol = at)
    ap     = assoc_pct(assign, truth)
    n_true = count(e -> e.kind === :pulse_emitter, values(w.entities))

    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(d.id)
    tel["$sid.n_pri"]     = length(pris)
    tel["$sid.n_true"]    = n_true
    tel["$sid.assoc_pct"] = _finite(ap)
    tel["$sid.histogram"] = _finite.(hist)            # fixed-length core object (counts)
    tel["$sid.threshold"] = _finite.(thresh)          # fixed-length flat line
    tel["$sid.pri_us"]    = pris  ./ _US              # variable, display only (µs)
    tel["$sid.toa_us"]    = toas  ./ _US              # variable, display only (µs)
    tel["$sid.assign"]    = assign                    # variable, display only
    return nothing
end

# --- ESM static-axis handshake info (the CFAR `_cfar_axis_info` analog) -----------

"""
    _esm_axis_info(w) -> Union{Dict, Nothing}

The static ESM/PRI axes a slice-6 scenario ships ONCE in the `scenario` handshake (they
can't change frame-to-frame — the histogram bins + dwell are load-time static). Mirrors
`_cfar_axis_info`: returns `nothing` for a non-ESM world (the keys simply don't appear), so
`scenario_frame` merges it only when there is an `:esm` entity. Ships:

  • `pri_axis_us` — the difference-histogram bin CENTERS in µs (`(b−0.5)·bin_width`), the
    τ-axis the client labels the histogram against (the `range_axis_m` analog — CORE output,
    the client never recomputes the binning);
  • `dwell_us` — the collection dwell in µs (the raster's time span);
  • `bin_us` / `n_bins` — the bin width + count (so the client can size the histogram);
  • `esm` — the ESM entity id whose `<id>.histogram`/`.threshold`/… telemetry to render.

The presence of `pri_axis_us` in the handshake is the client's ESM-view discriminator (the
`range_axis_m`→cfar precedent). One ESM per scenario (`_validate_esm`); the first by sorted
id if somehow more.
"""
function _esm_axis_info(w::World)
    esms = sort!(Symbol[id for (id, e) in w.entities if e.kind === :esm])
    isempty(esms) && return nothing
    esm    = w.entities[esms[1]]
    bw     = Float64(esm.comp[:bin_width]); ml = Float64(esm.comp[:max_lag])
    n_bins = max(1, floor(Int, ml / bw))
    axis   = collect(((1:n_bins) .- 0.5) .* bw ./ _US)     # bin centers, µs
    return Dict{Symbol,Any}(:esm => esms[1], :dwell_us => Float64(esm.comp[:t_dwell]) / _US,
                            :bin_us => bw / _US, :n_bins => n_bins, :pri_axis_us => axis)
end
