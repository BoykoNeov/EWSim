# test_esm.jl — the multi-emitter EW subsystems wired through the tick contract (slice-6
# gate 2, the test_jammer.jl / test_geolocation.jl analog). The PRI-histogram MATH is pinned
# closed-form in test_deinterleave.jl; THIS file pins the SUBSYSTEM PIPELINE — the phase
# 2+3+4 capstone: `PulseEmitter.build_env!` publishing `env[:emitters]` (phase 2), the
# `ESMReceiver.observe!` drawing the interleaved TOA stream into `env[:toa_stream]` (phase 3,
# the ONE draw site, in the §1-pinned order), and `Deinterleaver.decide!` reproducing
# `detect_pris`/`assoc_pct` on the realized stream (phase 4). Slice-6 is "slice-2/4/5-shaped":
# deterministic given the drawn stream, NO draw-topology hazard (the rung selects only phase-4
# post-processing). The headline is the `n_pri` flip reproduced ON THE WIRED STREAM: cdif=4
# (phantom subharmonic) vs sdif=3 (== n_true).

# An ESM world: N pulse emitters (the de-risked [1300,1700,2300] µs by default) + one ESM
# platform, assembled in SORTED-ID order (the loader's contract, which fixes the RNG draw
# order). The ESM comp carries gate-1's PROVEN param set (bin 20 µs, max_lag 3000 µs, C=15,
# thresh 0.4, seq_tol 30 µs, min_seq 10, assoc_tol 50 µs). `mode` sets the `:deinterleaver`
# fidelity (nothing → the Deinterleaver defaults :cdif).
const _ESM_US = 1.0e-6
function _esm_world(; pris_us = [1300.0, 1700.0, 2300.0], phases_us = [0.0, 300.0, 700.0],
                     dwell_us = 80_000.0, jitter_us = 0.0, p_intercept = 1.0, n_spurious = 0,
                     mode = nothing, seed = 6, revisit_s = 0.0)
    fid = Dict{Symbol,Symbol}()
    mode === nothing || (fid[:deinterleaver] = mode)
    w = World(seed = seed, fidelity = fid)
    for (i, (pri, ph)) in enumerate(zip(pris_us, phases_us))
        id = Symbol("pe", i)
        w.entities[id] = Entity(id, :pulse_emitter; pos = Vec3(10_000.0 * i, 0, 0),
            comp = Dict{Symbol,Any}(:pri => pri * _ESM_US, :phase => ph * _ESM_US,
                                    :pulse_width => 1.0 * _ESM_US))
    end
    w.entities[:esm1] = Entity(:esm1, :esm; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:t_dwell => dwell_us * _ESM_US, :bin_width => 20.0 * _ESM_US,
            :max_lag => 3000.0 * _ESM_US, :seq_tol => 30.0 * _ESM_US, :assoc_tol => 50.0 * _ESM_US,
            :levels => 15, :min_seq => 10, :thresh_frac => 0.4,
            :n_spurious => n_spurious, :jitter_us => jitter_us, :p_intercept => p_intercept))
    subs = Subsystem[]
    for id in sort!(collect(keys(w.entities)))
        e = w.entities[id]
        if e.kind === :pulse_emitter
            push!(subs, ConstantVelocity(id)); push!(subs, PulseEmitter(id))
        elseif e.kind === :esm
            push!(subs, ConstantVelocity(id)); push!(subs, ESMReceiver(id; revisit_s = revisit_s))
            push!(subs, Deinterleaver(id))
        end
    end
    return w, subs
end

# Tick once → (env[:emitters], env[:toa_stream], telemetry). Post-tick env still holds this
# tick's contents (cleared at the START of the next tick's phase 2).
function _esm_step(w, subs)
    tick!(w, subs, 1.0e-3)
    return w.env[:emitters], w.env[:toa_stream], w.env[:telemetry]
end

@testset "ESM pipeline (build_env!→observe!→decide!, phases 2+3+4 capstone)" begin

    @testset "PulseEmitter publishes env[:emitters] (phase 2 — record shape + sorted order)" begin
        # The §3 phase-2 producer: each PulseEmitter appends an EmitterParams record. Pin the
        # SHAPE (id/pri/phase/pulse_width/pos), the µs→s storage, and the sorted-id append order.
        w, subs = _esm_world()
        emitters, _, _ = _esm_step(w, subs)
        @test length(emitters) == 3
        @test [e.id for e in emitters] == [:pe1, :pe2, :pe3]           # sorted-id append order
        @test emitters[1].pri   ≈ 1300.0 * _ESM_US atol = 1e-15        # stored SI seconds
        @test emitters[2].phase ≈  300.0 * _ESM_US atol = 1e-15
        @test emitters[1].pos == Vec3(10_000.0, 0, 0)
        @test eltype(emitters) == EWSim.EmitterParams
    end

    @testset "ESMReceiver draws env[:toa_stream] in the EXACT §1 order (the determinism golden)" begin
        # The phase-3 ONE draw site, pinned bit-for-bit. Reconstruct the drawn stream off a fresh
        # Xoshiro by REPLAYING THE §1 DRAW ORDER MANUALLY (independent of `_draw_toa_stream` — a
        # genuine check that the receiver loop matches the spec, the sqrt(snr/2)/draw-order bug
        # class the plan warns about). Order: emitters sorted-id (pe1,pe2,pe3); within an emitter
        # k-ascending; per pulse JITTER(randn) THEN INTERCEPT(rand), both unconditional; spurious
        # (rand) LAST. Use non-trivial jitter + p_intercept<1 + spurious so every draw path fires.
        SEED = 4242; DWELL = 80_000.0 * _ESM_US; σ = 3.0 * _ESM_US; PINT = 0.85; NSPUR = 7
        pris_us = [1300.0, 1700.0, 2300.0]; phases_us = [0.0, 300.0, 700.0]
        w, subs = _esm_world(jitter_us = 3.0, p_intercept = PINT, n_spurious = NSPUR, seed = SEED)
        _, stream, _ = _esm_step(w, subs)

        rng = Xoshiro(SEED)
        raw_toas = Float64[]; raw_truth = Symbol[]
        for i in 1:3                                                   # emitters, sorted id
            id = Symbol("pe", i); pri = pris_us[i] * _ESM_US; ph = phases_us[i] * _ESM_US
            k = 0
            while ph + k * pri < DWELL                                 # pulses, emit order
                t_emit = ph + k * pri
                jit  = t_emit + σ * randn(rng)                         # JITTER (unconditional)
                keep = rand(rng) < PINT                                # INTERCEPT (unconditional)
                keep && (push!(raw_toas, jit); push!(raw_truth, id))
                k += 1
            end
        end
        for _ in 1:NSPUR                                               # spurious LAST
            push!(raw_toas, rand(rng) * DWELL); push!(raw_truth, EWSim.SPURIOUS_ID)
        end
        order = sortperm(raw_toas)
        exp_toas = raw_toas[order]; exp_truth = raw_truth[order]

        @test stream.toas == exp_toas
        @test reinterpret(UInt64, stream.toas) == reinterpret(UInt64, exp_toas)  # bit-identity
        @test stream.truth == exp_truth
        # ...and the stream is bounded + truth-stamped: some pulses dropped (p_intercept<1),
        # NSPUR spurious present, all TOAs in [0, dwell).
        @test count(==(EWSim.SPURIOUS_ID), stream.truth) == NSPUR
        @test length(stream.toas) < 144 + NSPUR                       # < the p=1 candidate count
        @test all(0.0 .≤ stream.toas .< DWELL + 1e-6)                 # (+σ tail slack)
    end

    @testset "clean stream: exactly 144 candidates, no spurious, all truth-stamped" begin
        # With jitter=0 / p_intercept=1 / n_spurious=0 the stream IS gate-1's gen_stream: 62+47+35
        # = 144 pulses, every one carrying its emitter's truth id (no SPURIOUS_ID).
        w, subs = _esm_world()                                        # defaults: clean
        _, stream, _ = _esm_step(w, subs)
        @test length(stream.toas) == 144
        @test !any(==(EWSim.SPURIOUS_ID), stream.truth)
        @test Set(stream.truth) == Set([:pe1, :pe2, :pe3])
        @test issorted(stream.toas)
    end

    @testset "Deinterleaver reproduces detect_pris/assoc on the realized stream (phase 4)" begin
        # The phase-4 consumer reads env[:toa_stream] the SAME tick and reproduces the lib exactly
        # (it IS the call). Pin n_pri + assoc_pct against detect_pris/associate on the realized
        # stream, for BOTH rungs.
        for mode in (:cdif, :sdif)
            w, subs = _esm_world(mode = mode, seed = 11)
            _, stream, tel = _esm_step(w, subs)
            pris = detect_pris(stream.toas; mode = mode, bin_width = 20.0 * _ESM_US,
                               max_lag = 3000.0 * _ESM_US, levels = 15, thresh_frac = 0.4,
                               seq_tol = 30.0 * _ESM_US, min_seq = 10)
            ap = assoc_pct(associate(stream.toas, pris; tol = 50.0 * _ESM_US), stream.truth)
            @test tel["esm1.n_pri"] == length(pris)
            @test tel["esm1.assoc_pct"] ≈ ap atol = 1e-12
            @test tel["esm1.n_true"] == 3                             # the :pulse_emitter count
        end
    end

    @testset "THE HEADLINE: cdif n_pri=4 (phantom), sdif n_pri=3 — the flip on the wired stream" begin
        # The load-bearing scalar reproduced end-to-end through the pipeline (advisor #4): the
        # clean [1300,1700,2300] µs stream → cdif over-counts a phantom at 2×min, sdif recovers
        # n_true. Same seed so the two runs see the SAME drawn stream (the rung is the only change).
        wc, sc = _esm_world(mode = :cdif, seed = 6)
        ws, ss = _esm_world(mode = :sdif, seed = 6)
        _, _, telc = _esm_step(wc, sc)
        _, _, tels = _esm_step(ws, ss)
        @test telc["esm1.n_pri"] == 4                                 # cdif: 3 fundamentals + phantom
        @test tels["esm1.n_pri"] == 3                                 # sdif: == n_true
        @test tels["esm1.n_true"] == 3
    end

    @testset "the ESM telemetry survives the REAL wire (state_frame → JSON round-trip)" begin
        # The array-telemetry widening (histogram/threshold/pri_us/toa_us/assign) must serialize
        # through the actual §5 framing, not just live in env[:telemetry] — the CFAR-array
        # round-trip precedent (test_radar). JSON3 throws on Inf/NaN, so this also pins the finite
        # contract on the wire. Entities (:pulse_emitter/:esm) go through state_frame's entity path.
        w, subs = _esm_world(mode = :cdif, seed = 6)
        tick!(w, subs, 1.0e-3)
        frame = state_frame(w)
        io = IOBuffer(); write_frame(io, frame); seekstart(io); back = read_frame(io)
        tel = back.telemetry
        @test back.t == frame[:t]
        @test length(tel[Symbol("esm1.histogram")]) == 150
        @test all(isfinite, tel[Symbol("esm1.histogram")])
        @test all(isfinite, tel[Symbol("esm1.threshold")])
        @test tel[Symbol("esm1.n_pri")] == 4 && tel[Symbol("esm1.n_true")] == 3
        @test length(tel[Symbol("esm1.assign")]) == 144        # variable arrays serialize too
        @test length(tel[Symbol("esm1.toa_us")]) == 144
        # the entities survive too (both new kinds render on the wire).
        kinds = Set(Symbol(e.kind) for e in back.entities)
        @test :pulse_emitter in kinds && :esm in kinds
    end

    @testset "the histogram raises peaks at the true PRIs (over a realized stream)" begin
        # The killer visual, pinned numerically: the shipped fixed-length histogram has local-peak
        # bins at 1300/1700/2300 µs (and the 2600 µs phantom). Rung-INDEPENDENT (same for cdif/sdif).
        w, subs = _esm_world(seed = 6)
        _, _, tel = _esm_step(w, subs)
        h = tel["esm1.histogram"]
        @test length(h) == 150                                        # 3000 µs / 20 µs bins
        binof(τ_us) = floor(Int, (τ_us * _ESM_US) / (20.0 * _ESM_US)) + 1
        for τ in (1300.0, 1700.0, 2300.0, 2600.0)
            b = binof(τ)
            @test h[b] > 0 && h[b] ≥ h[b - 2] && h[b] ≥ h[b + 2]      # a genuine local peak
        end
        # threshold is a flat line at thresh_frac·peak (rung-independent, CORE output).
        thr = tel["esm1.threshold"]
        @test length(thr) == 150 && all(thr .≈ 0.4 * maximum(h))
    end

    @testset "the :deinterleaver rung selects post-processing, NOT a draw (RNG lockstep)" begin
        # No draw-topology hazard (the slice-4/5 pattern): the receiver draws a fixed count per
        # look regardless of the rung (the whole draw is phase-3). So cdif and sdif advance w.rng
        # IDENTICALLY (lockstep) while n_pri differs (4 vs 3) — the not-a-dead-knob proof, and the
        # sharp "the rung is pure phase-4 post-processing" check.
        wc, sc = _esm_world(mode = :cdif, revisit_s = 0.0, seed = 77)
        ws, ss = _esm_world(mode = :sdif, revisit_s = 0.0, seed = 77)
        local telc, tels
        for _ in 1:30
            _, _, telc = _esm_step(wc, sc)
            _, _, tels = _esm_step(ws, ss)
        end
        @test rand(copy(wc.rng)) == rand(copy(ws.rng))                # draw count is rung-invariant
        @test telc["esm1.n_pri"] != tels["esm1.n_pri"]               # ...but the detected count differs
    end

    @testset "telemetry keys present + FINITE, incl. a degenerate empty dwell (no throw)" begin
        # The "a live config can't crash a tick" watch-item on a new surface: a p_intercept→0
        # slider drops every pulse → an empty stream; the histogram/extractor return sensible
        # empties + clamped-finite telemetry, never an OOB/throw (`_esm_step` ticks, so a throw
        # fails). n_pri=0, assoc_pct vacuously 1.0.
        w, subs = _esm_world(p_intercept = 0.0, n_spurious = 0, mode = :cdif, seed = 6)
        _, stream, tel = _esm_step(w, subs)
        @test isempty(stream.toas)
        for k in ("esm1.n_pri", "esm1.n_true", "esm1.assoc_pct")
            @test haskey(tel, k) && isfinite(tel[k])
        end
        @test tel["esm1.n_pri"] == 0
        @test tel["esm1.assoc_pct"] == 1.0                            # no true pulses → vacuous
        @test all(isfinite, tel["esm1.histogram"]) && all(iszero, tel["esm1.histogram"])
        @test all(isfinite, tel["esm1.threshold"])
        # a normal frame ships every documented key (scalars + fixed arrays + display arrays).
        _, _, tel2 = _esm_step(_esm_world(seed = 6)...)
        for k in ("esm1.n_pri", "esm1.n_true", "esm1.assoc_pct", "esm1.histogram",
                  "esm1.threshold", "esm1.pri_us", "esm1.toa_us", "esm1.assign")
            @test haskey(tel2, k)
        end
    end

    @testset "an ESM-free world writes no emitters / stream / ESM telemetry (slices 1-5 untouched)" begin
        # The ESM adds NO code to the radar path; a radar-only world never writes env[:emitters]
        # / env[:toa_stream] and ships no esm telemetry. (The byte-identity goldens + determinism
        # cover the RNG; this pins the wire surface, the test_jammer/geolocation pattern.)
        w = World(seed = 1, fidelity = Dict{Symbol,Symbol}(:propagation => :free_space))
        w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
            comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9_000.0, 0, 0),
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
        tick!(w, subs, 1.0e-3)
        @test !haskey(w.env, :emitters)
        @test !haskey(w.env, :toa_stream)
        @test !any(k -> occursin("esm", k) || endswith(k, ".n_pri"), keys(w.env[:telemetry]))
    end

    # --- loader arms (the programmatic worlds above never hit `_build_entity`) ---------

    @testset "loader builds :pulse_emitter / :esm; rejects bad PRI / dwell / count / bound" begin
        # :pulse_emitter — pri/phase/pulse_width authored µs, stored SI seconds; CV + PulseEmitter.
        pe, ps = EWSim._build_entity(:pe1, :pulse_emitter,
            Dict("id" => "pe1", "kind" => "pulse_emitter", "pos" => [10_000, 0, 0],
                 "pulse_emitter" => Dict("pri_us" => 1300.0, "phase_us" => 0.0, "pulse_width_us" => 1.0)))
        @test pe.kind === :pulse_emitter
        @test pe.comp[:pri] ≈ 1300.0e-6 atol = 1e-15                  # µs → SI seconds (the §1 conversion)
        @test pe.comp[:phase] == 0.0
        @test pe.comp[:pulse_width] ≈ 1.0e-6 atol = 1e-15
        @test length(ps) == 2 && any(s -> s isa PulseEmitter, ps) &&
              any(s -> s isa ConstantVelocity, ps)
        # pri_us ≤ 0 (infinite emit loop) and a missing block are clear LOAD errors.
        @test_throws ErrorException EWSim._build_entity(:pe1, :pulse_emitter,
            Dict("id" => "pe1", "kind" => "pulse_emitter",
                 "pulse_emitter" => Dict("pri_us" => 0.0, "phase_us" => 0.0, "pulse_width_us" => 1.0)))
        @test_throws ErrorException EWSim._build_entity(:pe1, :pulse_emitter,
            Dict("id" => "pe1", "kind" => "pulse_emitter"))

        # :esm — static params µs→s (defaults = gate-1's proven set), CV + ESMReceiver + Deinterleaver.
        ee, es = EWSim._build_entity(:esm1, :esm,
            Dict("id" => "esm1", "kind" => "esm", "pos" => [0, 0, 0],
                 "esm" => Dict("t_dwell_us" => 80_000.0, "jitter_us" => 2.0, "p_intercept" => 0.9)))
        @test ee.kind === :esm
        @test ee.comp[:t_dwell] ≈ 80_000.0e-6 atol = 1e-12           # µs → SI seconds
        @test ee.comp[:bin_width] ≈ 20.0e-6 atol = 1e-15            # default bin (gate-1 proven)
        @test ee.comp[:max_lag] ≈ 3000.0e-6 atol = 1e-15           # default search band
        @test ee.comp[:levels] == 15 && ee.comp[:min_seq] == 10 && ee.comp[:thresh_frac] == 0.4
        @test ee.comp[:jitter_us] == 2.0 && ee.comp[:p_intercept] == 0.9   # live sliders, µs unit
        @test length(es) == 3 && any(s -> s isa ESMReceiver, es) &&
              any(s -> s isa Deinterleaver, es) && any(s -> s isa ConstantVelocity, es)
        # bad t_dwell / degenerate max_lag / missing block are clear LOAD errors.
        @test_throws ErrorException EWSim._build_entity(:esm1, :esm,
            Dict("id" => "esm1", "kind" => "esm", "esm" => Dict("t_dwell_us" => 0.0)))
        @test_throws ErrorException EWSim._build_entity(:esm1, :esm,
            Dict("id" => "esm1", "kind" => "esm",
                 "esm" => Dict("t_dwell_us" => 80_000.0, "bin_us" => 5000.0, "max_lag_us" => 100.0)))
        @test_throws ErrorException EWSim._build_entity(:esm1, :esm,
            Dict("id" => "esm1", "kind" => "esm"))

        # _validate_esm: ≥2 pulse emitters + exactly 1 esm, and the bounded-pulse guard.
        function mk_esm_world(; n_emit = 2, dwell_us = 80_000.0, pri_us = 1300.0)
            wv = World()
            for i in 1:n_emit
                id = Symbol("pe", i)
                wv.entities[id] = Entity(id, :pulse_emitter;
                    comp = Dict{Symbol,Any}(:pri => pri_us * 1e-6, :phase => 0.0, :pulse_width => 1e-6))
            end
            wv.entities[:esm1] = Entity(:esm1, :esm;
                comp = Dict{Symbol,Any}(:t_dwell => dwell_us * 1e-6, :bin_width => 20e-6,
                    :max_lag => 3000e-6, :levels => 15))
            return wv
        end
        @test_throws ErrorException EWSim._validate_esm(mk_esm_world(n_emit = 1))   # only 1 emitter
        @test EWSim._validate_esm(mk_esm_world(n_emit = 3)) isa World              # 3 emitters + 1 esm ok
        # bounded-pulse guard: a 100 ms dwell over a 10 µs PRI → ~10 000 candidates ≫ the cap.
        @test_throws ErrorException EWSim._validate_esm(
            mk_esm_world(n_emit = 2, dwell_us = 100_000.0, pri_us = 10.0))
        # a non-ESM world is untouched (the trigger is ESM-entity presence).
        @test EWSim._validate_esm(World()) isa World
    end
end
