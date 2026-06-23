# test_jammer.jl — the Jammer build_env! subsystem + the radar's SNR_eff coupling
# (slice-4 step 2, gate 2). rf.jl's J/S primitives are pinned closed-form in test_jamming;
# THIS file pins the SUBSYSTEM wiring: `build_env!` populating `env[:jamming]` (the FIRST
# phase-2 contribution), `_observe_point!` reading it → SNR_eff = SNR/(1+ΣJNR), the
# jnr_db/js_db telemetry, the self-screen burn-through crossover, and the determinism contract
# (jamming changes detection BOOLEANS, never the draw stream). Slice-4 stays "slice-2-shaped":
# deterministic SNR modulation, no draw-topology hazard (contrast slice-3's :cfar guard).

# A radar at the origin, one target at `tx`, and (optionally) a jammer. Default `jpos = nothing`
# co-locates the jammer with the target (self-screening: same pos AND vel ⇒ R_j = R_target, θ = 0
# → mainlobe Gr every tick); pass `jpos`/`jvel` to place it OFF-AXIS for a standoff (sidelobe Gr).
# The radar carries the gate-3 two-level-antenna + EP config (`:beamwidth_rad :sidelobe_db
# :agile_bw_hz :cancel_db`); `ep` (default `:none`) sets the live EP fidelity. free_space
# propagation: slice-4 is "one lesson per scenario" — no two_ray lobing on the signal path.
function _jammer_world(; tx = 30_000.0, vx = 0.0, jam = true, pj_w = 100.0, gj_db = 10.0,
                         bj_hz = 1.0e6, rcs = 1.0, pfa = 1.0e-6, sw = 1, seed = 1,
                         jpos = nothing, jvel = nothing, ep = :none,
                         beamwidth_rad = deg2rad(3.0), sidelobe_db = 30.0,
                         agile_bw_hz = 1.0e7, cancel_db = 30.0)
    fid = Dict{Symbol,Symbol}(:propagation => :free_space)
    ep === :none || (fid[:ep] = ep)
    w = World(seed = seed, fidelity = fid)
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
            :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => pfa, :swerling => sw,
            :beamwidth_rad => beamwidth_rad, :sidelobe_db => sidelobe_db,
            :agile_bw_hz => agile_bw_hz, :cancel_db => cancel_db))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(tx, 0, 0), vel = Vec3(vx, 0, 0),
        comp = Dict{Symbol,Any}(:rcs_m2 => rcs))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0), ConstantVelocity(:tgt1)]
    if jam
        jp = jpos === nothing ? Vec3(tx, 0, 0) : jpos
        jv = jvel === nothing ? Vec3(vx, 0, 0) : jvel
        w.entities[:jam1] = Entity(:jam1, :jammer; pos = jp, vel = jv,
            comp = Dict{Symbol,Any}(:pt_w => pj_w, :gain_db => gj_db, :bandwidth_hz => bj_hz))
        push!(subs, ConstantVelocity(:jam1))
        push!(subs, Jammer(:jam1))
    end
    return w, subs
end

# Tick once and return the published telemetry bag (the wire view).
_jam_tel(w, subs) = (tick!(w, subs, 1.0e-3); state_frame(w)[:telemetry])

@testset "jammer subsystem (build_env! + SNR_eff coupling)" begin

    @testset "build_env! writes env[:jamming] (the FIRST phase-2 contribution)" begin
        # The §3 coupling: a jammer's build_env! populates the derived env blackboard; the radar
        # reads it back. Pin the record SHAPE (jnr/in_beam/bj_hz) and the JNR value vs rf.jl.
        w, subs = _jammer_world(tx = 30_000.0)
        tick!(w, subs, 1.0e-3)
        @test haskey(w.env, :jamming)
        @test haskey(w.env[:jamming], :radar1)
        contribs = w.env[:jamming][:radar1]
        @test length(contribs) == 1                       # one jammer → one contribution
        c  = contribs[1]
        rp = EWSim._radar_params(w.entities[:radar1].comp)
        R_j = sqrt(sum(abs2, w.entities[:jam1].pos - w.entities[:radar1].pos))
        @test c.jnr ≈ jam_noise_ratio(rp, 100.0, 10.0, 1.0e6, R_j) rtol = 1e-12  # mainlobe gr = gain_db
        @test c.in_beam == true                           # gate 2: mainlobe placeholder
        @test c.bj_hz   == 1.0e6                           # carried for gate-3 freq_agility
    end

    @testset "a present jammer drops SNR_eff to SNR/(1+JNR) (telemetry closed form)" begin
        w,  subs  = _jammer_world(tx = 30_000.0, jam = true)
        w0, subs0 = _jammer_world(tx = 30_000.0, jam = false)
        tel  = _jam_tel(w,  subs)
        tel0 = _jam_tel(w0, subs0)
        rp = EWSim._radar_params(w.entities[:radar1].comp)
        R  = 30_000.0
        snr_th  = snr_freespace(rp, 1.0, R)
        jnr     = jam_noise_ratio(rp, 100.0, 10.0, 1.0e6, R)
        snr_eff = snr_th / (1 + jnr)
        @test tel["radar1.snr_db"] ≈ lin2db(snr_eff) rtol = 1e-12    # snr_db carries SNR_eff
        @test tel["radar1.snr_db"] < tel0["radar1.snr_db"]           # jamming lowered the readout
        @test tel["radar1.jnr_db"] ≈ lin2db(jnr) rtol = 1e-12
        @test tel["radar1.js_db"]  ≈ lin2db(jnr / snr_th) atol = 1e-9  # J/S = JNR / SNR_thermal
        # ...and the unjammed snr_db is unchanged from the bare radar eq (no 1/(1+JNR) applied).
        @test tel0["radar1.snr_db"] ≈ lin2db(snr_th) rtol = 1e-12
    end

    @testset "self-screen burn-through: J/S flips sign across burnthrough_range" begin
        # Jammer rides the target (co-located). At the rf.jl burn-through range J/S = 1
        # (js_db ≈ 0); OUTSIDE it the jammer masks (J/S > 1, js_db > 0), INSIDE the signal
        # burns through (J/S < 1, js_db < 0). Pin the LESSON deterministically on js_db, not on
        # the random detection boolean (advisor: the oracle-style burn-through claim).
        rp   = EWSim._radar_params(_jammer_world()[1].entities[:radar1].comp)
        R_bt = burnthrough_range(rp, 1.0, 100.0, 10.0, 1.0e6)
        @test R_bt > 0
        js_db_at(R) = _jam_tel(_jammer_world(tx = R, jam = true)...)["radar1.js_db"]
        @test js_db_at(2.0 * R_bt) > 0           # outside: jammed
        @test js_db_at(0.5 * R_bt) < 0           # inside: burn-through
        @test abs(js_db_at(R_bt)) < 1e-6         # at R_bt: J/S = 1 ⇒ 0 dB
        # the self-screen J/S ∝ R² law shows in the readout: +6 dB per range-doubling.
        @test js_db_at(2.0 * R_bt) - js_db_at(R_bt) ≈ 20 * log10(2) atol = 1e-6
    end

    @testset "jamming changes detections, not the draw stream (RNG lockstep)" begin
        # detect_once is UNCONDITIONAL → the same randn count per look whether or not a jammer
        # lowers SNR. So jammer-on and jammer-off advance w.rng IDENTICALLY (lockstep) while the
        # detection booleans differ. Geometry: a ~9 km target the radar detects ~half the time
        # unjammed, masked to ≈pfa under the (huge) self-screen JNR. The jammer's build_env! has
        # NO RNG and ConstantVelocity has none, so a jammer adds ZERO draws — the lockstep is exact.
        won, son = _jammer_world(tx = 9_000.0, jam = true,  seed = 20260623)
        wof, sof = _jammer_world(tx = 9_000.0, jam = false, seed = 20260623)
        hits_on = Bool[]; hits_of = Bool[]
        for _ in 1:200
            tick!(won, son, 1.0e-3)
            push!(hits_on, any(e -> e[:kind] === :detection, won.events)); empty!(won.events)
            tick!(wof, sof, 1.0e-3)
            push!(hits_of, any(e -> e[:kind] === :detection, wof.events)); empty!(wof.events)
        end
        @test rand(copy(won.rng)) == rand(copy(wof.rng))   # draw count is jammer-invariant
        @test hits_on != hits_of                           # ...but jamming changed the outcomes
        @test count(hits_of) > count(hits_on)              # unjammed detects more (jamming masks)
    end

    @testset "a no-jammer frame carries NO jnr_db/js_db key (slices 1-3 telemetry unchanged)" begin
        # The conditional-emission contract: without a jammer the radar ships exactly the
        # slice-1/2 keys (the byte-identity goldens cover the RNG; this pins the wire surface).
        w, subs = _jammer_world(jam = false)
        tel = _jam_tel(w, subs)
        @test !haskey(tel, "radar1.jnr_db")
        @test !haskey(tel, "radar1.js_db")
        @test haskey(tel, "radar1.snr_db") && haskey(tel, "radar1.pd") &&
              haskey(tel, "radar1.detected") && haskey(tel, "radar1.visible")
    end

    # --- gate 3: two-level antenna (standoff sidelobe) + conditioned EP ---------------

    @testset "a standoff jammer enters a SIDELOBE (two-level Gr + real in_beam)" begin
        # Gate 3: the radar boresights its nearest target (on +X); an OFF-AXIS standoff jammer
        # sits in a sidelobe, so build_env! uses gr_db = gain_db − sidelobe_db (NOT the mainlobe
        # gain) and marks in_beam = false. Geometry: target at 30 km on +X, jammer at (28k, 8k)
        # → ~16° off boresight ≫ 1.5° half-beamwidth. Pin in_beam AND the exact sidelobe JNR.
        jpos = Vec3(28_000.0, 8_000.0, 0.0)
        w, subs = _jammer_world(tx = 30_000.0, jpos = jpos)
        tick!(w, subs, 1.0e-3)
        c  = w.env[:jamming][:radar1][1]
        rp = EWSim._radar_params(w.entities[:radar1].comp)
        R_j = sqrt(sum(abs2, jpos - w.entities[:radar1].pos))
        @test c.in_beam == false                                           # off-axis → sidelobe
        # exact sidelobe closed form (receive gain knocked down by sidelobe_db = 30 dB)...
        @test c.jnr ≈ jam_noise_ratio(rp, 100.0, 10.0, 1.0e6, R_j; gr_db = 30.0 - 30.0) rtol = 1e-12
        # ...i.e. exactly db2lin(-sidelobe_db) below the MAINLOBE JNR at the same range (≪).
        jnr_mainlobe = jam_noise_ratio(rp, 100.0, 10.0, 1.0e6, R_j)        # gr_db = gain_db default
        @test c.jnr ≈ jnr_mainlobe * db2lin(-30.0) rtol = 1e-12
        @test c.jnr < jnr_mainlobe / 100                                   # sanity: a big drop
        # a SELF-SCREEN jammer (co-located w/ the target) rides θ ≈ 0 → mainlobe, in_beam = true.
        ws, ss = _jammer_world(tx = 30_000.0)                              # jpos defaults to target
        tick!(ws, ss, 1.0e-3)
        cs = ws.env[:jamming][:radar1][1]
        @test cs.in_beam == true
        @test cs.jnr ≈ jam_noise_ratio(rp, 100.0, 10.0, 1.0e6, 30_000.0) rtol = 1e-12  # mainlobe
    end

    @testset "EP is CONDITIONED: matched reduces J/S, mismatched is an EXACT no-op (2×2)" begin
        # The slice's second lesson, pinned as a 2×2 so a FLAT fudge can't pass: each EP rung
        # helps ONLY in its matching condition and is a *bit-exact* no-op otherwise (==, not ≈ —
        # a flat multiplier would fail the no-op leg, the slice-2/3 "calibrated-to-pass" trap).
        ss = Vec3(30_000.0, 0, 0)            # self-screen → mainlobe (in_beam)
        so = Vec3(28_000.0, 8_000.0, 0.0)    # standoff    → sidelobe (!in_beam)
        # js_db at the configured EP rung (jammer present ⇒ the key always ships).
        js(; jpos, ep, bj_hz = 1.0e6) =
            _jam_tel(_jammer_world(tx = 30_000.0, jpos = jpos, ep = ep, bj_hz = bj_hz)...)["radar1.js_db"]

        # sidelobe_blanking: attacks a SIDELOBE jammer (standoff), no-op on a MAINLOBE one.
        @test js(jpos = so, ep = :sidelobe_blanking) < js(jpos = so, ep = :none)   # matched: reduces J/S
        @test js(jpos = so, ep = :none) - js(jpos = so, ep = :sidelobe_blanking) ≈ 30.0 atol = 1e-6  # by cancel_db
        @test js(jpos = ss, ep = :sidelobe_blanking) == js(jpos = ss, ep = :none)  # mismatched: EXACT no-op

        # freq_agility: attacks a SPOT jammer (B_j < B_agile), no-op on BARRAGE (B_j ≥ B_agile).
        @test js(jpos = ss, ep = :freq_agility) < js(jpos = ss, ep = :none)        # matched: spot reduces
        @test js(jpos = ss, ep = :none) - js(jpos = ss, ep = :freq_agility) ≈ 10.0 atol = 1e-6  # 10·log10(1e7/1e6)
        @test js(jpos = ss, ep = :freq_agility, bj_hz = 2.0e7) ==
              js(jpos = ss, ep = :none,         bj_hz = 2.0e7)                      # mismatched: EXACT no-op
        # ...and matched EP raises the SNR_eff readout too (J/S↓ ⇒ snr_db↑), the visible lesson.
        @test _jam_tel(_jammer_world(tx = 30_000.0, jpos = ss, ep = :freq_agility)...)["radar1.snr_db"] >
              _jam_tel(_jammer_world(tx = 30_000.0, jpos = ss, ep = :none)...)["radar1.snr_db"]
    end

    @testset "EP defaults: toggling :ep on a radar with NO EP config can't crash the tick" begin
        # The introduce-safe contract REQUIRES the comp-default fallbacks (`_DEFAULT_CANCEL_DB` /
        # `_DEFAULT_AGILE_BW_HZ`, and the `_DEFAULT_BEAMWIDTH_RAD`/`_DEFAULT_SIDELOBE_DB` antenna
        # pattern): a `set_fidelity :ep` may land on ANY scenario, including a radar whose comp
        # never carried EP/antenna config. Build exactly that radar (none of those keys) with a
        # present jammer, tick under each MATCHED EP rung, and pin that it (a) doesn't throw —
        # `_jam_tel` ticks, so a throw fails the test — and (b) applies the DEFAULT depth (same
        # "a live config can't crash a tick" crash-safety parity every other gate pins).
        function bare_world(; jpos, ep, bj_hz = 1.0e6)
            fid = Dict{Symbol,Symbol}(:propagation => :free_space)
            ep === :none || (fid[:ep] = ep)
            w = World(seed = 1, fidelity = fid)
            w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
                comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                    :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                    :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
            w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(30_000.0, 0, 0),
                comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
            w.entities[:jam1] = Entity(:jam1, :jammer; pos = jpos,
                comp = Dict{Symbol,Any}(:pt_w => 100.0, :gain_db => 10.0, :bandwidth_hz => bj_hz))
            subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1),
                             ConstantVelocity(:jam1), Jammer(:jam1)]
            return w, subs
        end
        # sidelobe_blanking on a STANDOFF jammer uses the DEFAULT cancel depth (no :cancel_db, and
        # the standoff sits in the sidelobe under the DEFAULT beamwidth/sidelobe pattern too).
        so = Vec3(28_000.0, 8_000.0, 0.0)
        js_none  = _jam_tel(bare_world(jpos = so, ep = :none)...)["radar1.js_db"]
        js_blank = _jam_tel(bare_world(jpos = so, ep = :sidelobe_blanking)...)["radar1.js_db"]
        @test js_none - js_blank ≈ EWSim._DEFAULT_CANCEL_DB atol = 1e-6
        # freq_agility on a SPOT jammer uses the DEFAULT agile band (no :agile_bw_hz in comp).
        ss = Vec3(30_000.0, 0, 0)                       # self-screen → mainlobe; spot B_j=1e6
        js_n2 = _jam_tel(bare_world(jpos = ss, ep = :none)...)["radar1.js_db"]
        js_a2 = _jam_tel(bare_world(jpos = ss, ep = :freq_agility)...)["radar1.js_db"]
        @test js_n2 - js_a2 ≈ 10 * log10(EWSim._DEFAULT_AGILE_BW_HZ / 1.0e6) atol = 1e-6
    end

    @testset "loader :jammer arm builds comp + [ConstantVelocity, Jammer]; rejects bad bandwidth" begin
        # The subsystem tests above build worlds programmatically, so they never hit the loader's
        # :jammer arm — exercise it (and the crash-critical bandwidth guard) directly here.
        ent = Dict("id" => "jam1", "kind" => "jammer", "pos" => [5000, 0, 100],
                   "vel" => [-200, 0, 0],
                   "jammer" => Dict("pt_w" => 200.0, "gain_db" => 12.0, "bandwidth_hz" => 2.0e6))
        e, subs = EWSim._build_entity(:jam1, :jammer, ent)
        @test e.kind === :jammer
        @test e.comp[:pt_w] == 200.0 && e.comp[:gain_db] == 12.0 && e.comp[:bandwidth_hz] == 2.0e6
        @test length(subs) == 2
        @test any(s -> s isa ConstantVelocity, subs)
        @test any(s -> s isa Jammer, subs)
        # a non-positive bandwidth must be a clear LOAD error (else it kills the session at tick).
        bad = Dict("id" => "jam1", "kind" => "jammer",
                   "jammer" => Dict("pt_w" => 200.0, "gain_db" => 12.0, "bandwidth_hz" => 0.0))
        @test_throws ErrorException EWSim._build_entity(:jam1, :jammer, bad)
        # a missing `jammer:` block is a clear load error too.
        @test_throws ErrorException EWSim._build_entity(:jam1, :jammer,
                                        Dict("id" => "jam1", "kind" => "jammer"))
    end
end
