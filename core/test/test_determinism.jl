# test_determinism.jl — same seed + same scenario ⇒ bit-identical trace.
#
# This is the contract that makes everything else (replay, MC-vs-truth, teaching
# reproducibility) possible. The fixture below is a minimal subsystem that both
# integrates kinematics AND draws from the world's single RNG stream, so the
# test actually exercises seeded reproducibility rather than trivially passing
# on a static world.

# --- fixture: a constant-velocity walker with seeded process noise ---
struct RandomWalker <: Subsystem
    id::Symbol
    sigma::Float64          # process-noise stddev, m/√s
end

function EWSim.integrate!(rw::RandomWalker, w::World, dt::Float64)
    e = w.entities[rw.id]
    # Draw from the world's single seeded stream — order of draws is what makes
    # the trace reproducible. Brownian scaling (√dt) keeps it dimensionally sane.
    noise = Vec3(randn(w.rng), randn(w.rng), randn(w.rng)) .* (rw.sigma * sqrt(dt))
    e.pos = e.pos + e.vel * dt + noise
end

function run_trace(seed; nsteps = 500, dt = 1.0e-3)
    w = World(seed = seed)
    w.entities[:walker] = Entity(:walker, :target;
                                 pos = Vec3(0.0, 0.0, 0.0),
                                 vel = Vec3(1.0, -2.0, 0.5))
    subs = Subsystem[RandomWalker(:walker, 0.3)]
    trace = Vector{Vec3}(undef, nsteps)
    for i in 1:nsteps
        tick!(w, subs, dt)
        trace[i] = w.entities[:walker].pos
    end
    return w, trace
end

@testset "determinism" begin
    wa, a = run_trace(42)
    wb, b = run_trace(42)

    @testset "same seed ⇒ identical trace" begin
        @test length(a) == 500
        @test a == b                                   # elementwise-exact equality
        # bit-identity, including sign of zero — the strict form of the contract
        flat(v) = reinterpret(UInt64, reduce(vcat, v))
        @test flat(a) == flat(b)
    end

    @testset "clock advances deterministically" begin
        @test wa.t == wb.t
        @test wa.t ≈ 500 * 1.0e-3
        @test isempty(wa.env)                          # env is cleared at end of each tick's rebuild
    end

    @testset "RNG is actually exercised" begin
        _, c = run_trace(43)
        @test a != c                                   # different seed ⇒ different trace
        @test a[end] != Vec3(500e-3, -2 * 500e-3, 0.5 * 500e-3)  # noise moved it off the deterministic line
    end

    # A live fidelity toggle (slice-2 set_fidelity) mutates the World mid-run exactly like
    # set_param, so it must NOT break replay. detect_once draws the same randn count under
    # either propagation rung, so the stream stays in lockstep across the flip — only the
    # detection OUTCOMES change. Capture the per-look detection trace across a toggle and
    # assert two same-seed runs match bit-for-bit. (A static target keeps the geometry —
    # hence pd — constant within each segment, so the trace is a pure RNG fingerprint.)
    @testset "a mid-run fidelity toggle replays deterministically" begin
        function toggle_trace(seed; toggle_at = 200, nsteps = 400)
            w = World(seed = seed, fidelity = Dict(:propagation => :free_space))
            w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 10),
                comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                    :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                    :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1))
            w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(9000.0, 0, 30),
                comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))             # SNR ≈ 17 ⇒ pd ≈ 0.47, off the rails
            subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
            hits = Bool[]
            for i in 1:nsteps
                i == toggle_at && (w.fidelity[:propagation] = :two_ray)   # the live toggle
                tick!(w, subs, 1.0e-3)
                push!(hits, any(e -> e[:kind] === :detection, w.events))
                empty!(w.events)
            end
            return w, hits
        end
        wa, ta = toggle_trace(20260621)
        wb, tb = toggle_trace(20260621)
        @test ta == tb                                  # identical detection trace across the toggle
        @test rand(copy(wa.rng)) == rand(copy(wb.rng))  # ...and the streams end in lockstep
        @test any(ta) && !all(ta)                       # non-trivial: rng genuinely flips outcomes
    end

    # The slice-3 CFAR analog, and the SHARPER form: a CFAR look draws 2·N_p·N_cells randn
    # for the profile, and the rung (fixed/ca/…) selects ONLY the pure thresholding rule — so
    # toggling it must leave the RNG stream untouched (draw-count-invariant) while changing
    # the detections. The discriminating test runs the SAME seed three ways: toggle twice
    # (identical), and toggle vs no-toggle (SAME rng end-state — proves the draw count didn't
    # change — but DIFFERENT detection trace — proves the rung actually mattered). A static
    # clutter band is what the rung resolves differently (fixed lights it, ca holds it).
    @testset "a mid-run cfar toggle replays deterministically (draw-count invariant)" begin
        dr = EWSim.C_LIGHT / (2 * 1.0e6)
        function cfar_trace(seed; toggle_at = 60, nsteps = 120, do_toggle = true)
            w = World(seed = seed, fidelity = Dict(:cfar => :fixed))
            w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
                comp = Dict{Symbol,Any}(:pt_w => 1.0e4, :gain_db => 30.0,
                    :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                    :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-3, :swerling => 1,
                    :n_pulses => 1, :n_cells => 200, :range_start_m => 0.0,
                    :n_train => 16, :n_guard => 2))
            w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(20_000.0, 0, 0),
                comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
            w.entities[:clut1] = Entity(:clut1, :clutter; pos = Vec3(8_000.0, 0, 0),
                comp = Dict{Symbol,Any}(:extent_m => 60 * dr, :cnr_db => 18.0))
            subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
            counts = Int[]
            for i in 1:nsteps
                (do_toggle && i == toggle_at) && (w.fidelity[:cfar] = :ca)   # the live toggle
                tick!(w, subs, 1.0e-3)
                push!(counts, count(e -> e[:kind] === :detection, w.events))
                empty!(w.events)
            end
            return w, counts
        end
        wa, ta = cfar_trace(20260622; do_toggle = true)
        wb, tb = cfar_trace(20260622; do_toggle = true)
        @test ta == tb                                  # same seed + same toggle ⇒ identical
        @test rand(copy(wa.rng)) == rand(copy(wb.rng))  # ...streams in lockstep

        wn, tn = cfar_trace(20260622; do_toggle = false)        # stays :fixed throughout
        @test rand(copy(wa.rng)) == rand(copy(wn.rng))  # toggle did NOT change the draw count
        @test ta != tn                                  # ...but the rung changed the detections
    end

    # The slice-4 contrast: `:ep` carries NO introduce-guard (unlike `:cfar`) because EP only
    # SCALES a deterministic JNR scalar — no randn draw changes — so it may be both TOGGLED and
    # INTRODUCED mid-run and still replay bit-identical. The discriminating geometry is a
    # self-screen SPOT jammer tuned to the burn-through knee (pj_w=1e-3 at 5 km → pd≈0.04 without
    # agility, ≈0.61 with freq_agility): freq_agility's +10 dB tips ~half the looks across the
    # threshold, so EP genuinely FLIPS detections — a dead EP (factor stuck at 1) would leave the
    # trace unchanged and fail the `ta != tn` leg, the slice-3 cfar "not-a-dead-knob" pattern.
    @testset "a mid-run ep introduce/toggle replays deterministically (draw-count invariant)" begin
        function ep_trace(seed; toggle_at = 100, nsteps = 200, jam = true,
                          start_ep = nothing, set_ep = :freq_agility)
            fid = Dict{Symbol,Symbol}(:propagation => :free_space)
            start_ep === nothing || (fid[:ep] = start_ep)
            w = World(seed = seed, fidelity = fid)
            w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
                comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
                    :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
                    :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => 1.0e-6, :swerling => 1,
                    :agile_bw_hz => 1.0e7))
            w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(5_000.0, 0, 0),
                comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
            subs = Subsystem[RadarSensor(:radar1), ConstantVelocity(:tgt1)]
            if jam
                w.entities[:jam1] = Entity(:jam1, :jammer; pos = Vec3(5_000.0, 0, 0),
                    comp = Dict{Symbol,Any}(:pt_w => 1.0e-3, :gain_db => 0.0, :bandwidth_hz => 1.0e6))
                push!(subs, ConstantVelocity(:jam1)); push!(subs, Jammer(:jam1))
            end
            hits = Bool[]
            for i in 1:nsteps
                (set_ep !== nothing && i == toggle_at) && (w.fidelity[:ep] = set_ep)
                tick!(w, subs, 1.0e-3)
                push!(hits, any(e -> e[:kind] === :detection, w.events)); empty!(w.events)
            end
            return w, hits
        end

        # INTRODUCE :ep on a scenario that started WITHOUT it — twice ⇒ identical, and lockstep.
        wa, ta = ep_trace(20260623; start_ep = nothing)
        wb, tb = ep_trace(20260623; start_ep = nothing)
        @test ta == tb
        @test rand(copy(wa.rng)) == rand(copy(wb.rng))
        # vs NEVER introducing: SAME rng end-state (introduce changed no draws) but DIFFERENT trace
        # (EP genuinely flipped detections — the not-a-dead-knob proof).
        wn, tn = ep_trace(20260623; start_ep = nothing, set_ep = nothing)
        @test rand(copy(wa.rng)) == rand(copy(wn.rng))
        @test ta != tn
        @test any(ta) && !all(ta)                       # non-trivial: rng genuinely flips outcomes

        # TOGGLE the VALUE of a pre-existing :ep key (starts :none) — same determinism, and an
        # absent :ep key is byte-identical to :ep=:none, so this trace equals the introduce trace.
        wc, tc = ep_trace(20260623; start_ep = :none)
        @test tc == ta
        @test rand(copy(wc.rng)) == rand(copy(wa.rng))

        # The SHARPEST introduce-safe form (advisor): on a JAMMER-FREE world, introducing :ep is a
        # guaranteed no-op — `contribs === nothing` short-circuits before :ep is ever read — so the
        # rng end-state AND trace are bit-identical to never touching it. The existing goldens never
        # set :ep, so this closes the one gap they leave (a slice-1/2/3 scenario can be `:ep`-toggled).
        wj, tj = ep_trace(20260623; jam = false, start_ep = nothing)                    # introduce
        wk, tk = ep_trace(20260623; jam = false, start_ep = nothing, set_ep = nothing)  # never
        @test tj == tk
        @test rand(copy(wj.rng)) == rand(copy(wk.rng))
    end

    # Slice 5: the DF/geolocation pair lights phase 4 (decide!). Each DFSensor draws exactly
    # one randn/look (the bearing noise) and the Geolocator's fix is closed-form — so a DF
    # scenario is deterministic given the drawn bearings (the slice-2/4 shape, no draw-topology
    # hazard). Pin a same-seed bit-identical fix trace, AND the draw-free rung switch: same seed,
    # :pseudolinear vs :ml → SAME rng end-state (the rung adds no draw) but DIFFERENT fixes (ml
    # debiases — not a dead knob, on the biased 40 km / ±10 km / 1° geometry).
    @testset "a DF scenario replays bit-identically (phase-4 decide!)" begin
        function df_trace(seed; estimator = :pseudolinear, nsteps = 100,
                          start_est = estimator, toggle_at = 0, toggle_to = nothing)
            fid = Dict{Symbol,Symbol}()
            start_est === nothing || (fid[:estimator] = start_est)   # nothing → INTRODUCE later
            w = World(seed = seed, fidelity = fid)
            w.entities[:emit1] = Entity(:emit1, :emitter; pos = Vec3(40_000.0, 0, 0),
                                        vel = Vec3(-150.0, 0, 0))
            w.entities[:dfs1] = Entity(:dfs1, :df_sensor; pos = Vec3(0.0, -10_000.0, 0),
                comp = Dict{Symbol,Any}(:sigma_theta_deg => 1.0))
            w.entities[:dfs2] = Entity(:dfs2, :df_sensor; pos = Vec3(0.0, 10_000.0, 0),
                comp = Dict{Symbol,Any}(:sigma_theta_deg => 1.0))
            w.entities[:stn1] = Entity(:stn1, :df_station; pos = Vec3(0.0, 0, 0))
            subs = Subsystem[]
            for id in sort!(collect(keys(w.entities)))
                e = w.entities[id]
                e.kind === :emitter    && push!(subs, ConstantVelocity(id))
                e.kind === :df_sensor  && (push!(subs, ConstantVelocity(id)); push!(subs, DFSensor(id)))
                e.kind === :df_station && (push!(subs, ConstantVelocity(id)); push!(subs, Geolocator(id)))
            end
            fixes = Float64[]
            for i in 1:nsteps
                (toggle_to !== nothing && i == toggle_at) && (w.fidelity[:estimator] = toggle_to)
                tick!(w, subs, 1.0e-3)
                tel = w.env[:telemetry]
                push!(fixes, tel["stn1.fix_x"]); push!(fixes, tel["stn1.fix_y"])
            end
            return w, fixes
        end
        wa, fa = df_trace(99); wb, fb = df_trace(99)
        @test fa == fb
        @test reinterpret(UInt64, fa) == reinterpret(UInt64, fb)   # bit-identity incl sign of zero
        wp, fp = df_trace(99; estimator = :pseudolinear)
        wm, fm = df_trace(99; estimator = :ml)
        @test rand(copy(wp.rng)) == rand(copy(wm.rng))             # draw count rung-invariant
        @test fp != fm                                             # ...but the fix differs (ml debiases)

        # The fidelity plumbing went live in gate 2 (`LIVE_FIDELITY_MODES[:estimator]` + the Geolocator
        # dispatch), so pin the live-toggle determinism on a SINGLE world here too (the `:ep` contract):
        # `:estimator` is draw-free, so toggling OR introducing it mid-run replays bit-identical, and a
        # toggle-vs-never run shares the rng end-state (no draw change) while the fix differs (live knob).
        wt1, ft1 = df_trace(99; start_est = :pseudolinear, toggle_at = 50, toggle_to = :ml)
        wt2, ft2 = df_trace(99; start_est = :pseudolinear, toggle_at = 50, toggle_to = :ml)
        @test ft1 == ft2 && reinterpret(UInt64, ft1) == reinterpret(UInt64, ft2)   # same-seed toggle bit-identical
        wn, fn = df_trace(99; start_est = :pseudolinear)                            # never toggled
        @test rand(copy(wt1.rng)) == rand(copy(wn.rng))           # toggle changed NO draws
        @test ft1 != fn                                          # ...but the rung flip changed the fix
        # INTRODUCE :estimator onto a world that started WITHOUT the key → still bit-identical, twice.
        wi1, fi1 = df_trace(99; start_est = nothing, toggle_at = 50, toggle_to = :ml)
        wi2, fi2 = df_trace(99; start_est = nothing, toggle_at = 50, toggle_to = :ml)
        @test reinterpret(UInt64, fi1) == reinterpret(UInt64, fi2)
    end

    # Slice 6: the multi-emitter EW pipeline lights phases 2+3+4 in one chain (the capstone).
    # The ESMReceiver is the ONE draw site (jitter randn + intercept rand per candidate + spurious
    # rand, all in phase-3 observe!); the Deinterleaver's phase-4 rung is PURE (no draw) — so a
    # slice-6 scenario is deterministic given the drawn stream (the slice-2/4/5 shape, no draw-
    # topology hazard). Pin (a) a same-seed bit-identical TOA-STREAM trace (the RNG fingerprint,
    # sharper than n_pri alone — advisor), (b) the draw-free rung switch: cdif vs sdif → SAME rng
    # end-state (the rung adds no draw) but DIFFERENT n_pri (4 vs 3 — not a dead knob), and (c) a
    # mid-run :deinterleaver toggle AND introduce both bit-identical.
    @testset "a multi-emitter EW scenario replays bit-identically (phases 2+3+4)" begin
        function esm_trace(seed; start_mode = :cdif, nsteps = 40, toggle_at = 0, toggle_to = nothing,
                           jitter_us = 3.0, p_intercept = 0.9, n_spurious = 5, revisit_s = 0.005)
            fid = Dict{Symbol,Symbol}()
            start_mode === nothing || (fid[:deinterleaver] = start_mode)   # nothing → INTRODUCE later
            w = World(seed = seed, fidelity = fid)
            for (i, (pri, ph)) in enumerate(zip([1300.0, 1700.0, 2300.0], [0.0, 300.0, 700.0]))
                id = Symbol("pe", i)
                w.entities[id] = Entity(id, :pulse_emitter; pos = Vec3(10_000.0 * i, 0, 0),
                    comp = Dict{Symbol,Any}(:pri => pri * 1e-6, :phase => ph * 1e-6,
                                            :pulse_width => 1e-6))
            end
            w.entities[:esm1] = Entity(:esm1, :esm; pos = Vec3(0, 0, 0),
                comp = Dict{Symbol,Any}(:t_dwell => 80_000.0 * 1e-6, :bin_width => 20.0 * 1e-6,
                    :max_lag => 3000.0 * 1e-6, :seq_tol => 30.0 * 1e-6, :assoc_tol => 50.0 * 1e-6,
                    :levels => 15, :min_seq => 10, :thresh_frac => 0.4, :n_spurious => n_spurious,
                    :jitter_us => jitter_us, :p_intercept => p_intercept))
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
            toas = Float64[]; npri = Int[]
            for i in 1:nsteps
                (toggle_to !== nothing && i == toggle_at) && (w.fidelity[:deinterleaver] = toggle_to)
                tick!(w, subs, 1.0e-3)
                append!(toas, w.env[:toa_stream].toas)                  # the drawn-stream fingerprint
                push!(npri, Int(w.env[:telemetry]["esm1.n_pri"]))
            end
            return w, toas, npri
        end
        wa, ta, na = esm_trace(6); wb, tb, nb = esm_trace(6)
        @test ta == tb && reinterpret(UInt64, ta) == reinterpret(UInt64, tb)   # bit-identical TOA stream
        @test na == nb

        # draw-free rung switch: cdif vs sdif share the rng end-state (no draw change) but n_pri differs.
        wc, tc, nc = esm_trace(6; start_mode = :cdif)
        ws, ts, ns = esm_trace(6; start_mode = :sdif)
        @test reinterpret(UInt64, tc) == reinterpret(UInt64, ts)   # same drawn stream (rung is phase-4)
        @test rand(copy(wc.rng)) == rand(copy(ws.rng))             # ...and rng end-states in lockstep
        @test nc != ns                                             # ...but the detected count differs (4 vs 3)

        # mid-run TOGGLE the value of a pre-existing key — bit-identical, twice; and same stream as
        # never-toggling (the rung is draw-free) while n_pri flips at the toggle.
        wt1, tt1, nt1 = esm_trace(6; start_mode = :cdif, toggle_at = 20, toggle_to = :sdif)
        wt2, tt2, nt2 = esm_trace(6; start_mode = :cdif, toggle_at = 20, toggle_to = :sdif)
        @test reinterpret(UInt64, tt1) == reinterpret(UInt64, tt2) && nt1 == nt2
        @test reinterpret(UInt64, tt1) == reinterpret(UInt64, tc)  # toggle changed NO draws
        @test nt1 != nc                                            # ...but the rung flip changed n_pri
        # INTRODUCE :deinterleaver onto a world that started WITHOUT the key → still bit-identical.
        wi1, ti1, _ = esm_trace(6; start_mode = nothing, toggle_at = 20, toggle_to = :sdif)
        wi2, ti2, _ = esm_trace(6; start_mode = nothing, toggle_at = 20, toggle_to = :sdif)
        @test reinterpret(UInt64, ti1) == reinterpret(UInt64, ti2)
        @test reinterpret(UInt64, ti1) == reinterpret(UInt64, tc)  # introduce added no draws either
    end

    # Slice 7: the GPS pipeline reuses build_env!→observe!→decide! a THIRD time (the §9 cross-
    # domain reuse). The GpsReceiver is the ONE draw site (2·n_sats — multipath then noise per
    # satellite, all in phase-3 observe!); the GpsSolver's phase-4 fix/DOP/RAIM is PURE (no draw)
    # and the five error toggles gate a CONTRIBUTION, never a draw — so a slice-7 scenario is
    # deterministic given the drawn pseudoranges (the slice-2/4/5/6 shape, no draw-topology
    # hazard). Pin (a) a same-seed bit-identical PSEUDORANGE trace (the RNG fingerprint, sharper
    # than pos_err — the slice-6 advisor lesson), (b) the draw-free rung switch: raim off vs
    # exclude → SAME rng end-state but DIFFERENT n_sats_used, and (c) mid-run toggle AND introduce
    # of EACH of the six keys bit-identical.
    @testset "a GPS scenario replays bit-identically (the §9 reuse pipeline)" begin
        _gsat(az, el; r = 20_000_000.0) = (a = deg2rad(az); e = deg2rad(el);
            Vec3(r * cos(e) * cos(a), r * cos(e) * sin(a), r * sin(e)))
        AZEL = [(0.0, 70.0), (60.0, 35.0), (120.0, 40.0), (180.0, 30.0), (240.0, 45.0), (300.0, 55.0)]
        function gps_trace(seed; toggle_key = nothing, toggle_val = :on, toggle_at = 0,
                           start_fid = Dict{Symbol,Symbol}(), nsteps = 30, revisit_s = 0.003)
            w = World(seed = seed, fidelity = copy(start_fid))
            for (i, (az, el)) in enumerate(AZEL)
                id = Symbol("sv", i)
                w.entities[id] = Entity(id, :gps_satellite; pos = _gsat(az, el),
                    comp = Dict{Symbol,Any}(:clock_err_m => (i == 2 ? 10.0 : 0.0),
                                            :fault_bias_m => (i == 3 ? 80.0 : 0.0)))
            end
            w.entities[:rx1] = Entity(:rx1, :gps_receiver; pos = Vec3(1000.0, -500.0, 0.0),
                comp = Dict{Symbol,Any}(:sigma_range_m => 3.0, :sigma_mp_m => 1.5,
                    :iono_zenith_m => 5.0, :tropo_zenith_m => 2.4, :clock_bias_m => 30.0,
                    :elevation_mask_deg => 0.0, :raim_threshold => 5.0))
            subs = Subsystem[]
            for id in sort!(collect(keys(w.entities)))
                e = w.entities[id]
                if e.kind === :gps_satellite
                    push!(subs, ConstantVelocity(id)); push!(subs, GpsSatellite(id))
                elseif e.kind === :gps_receiver
                    push!(subs, ConstantVelocity(id)); push!(subs, GpsReceiver(id; revisit_s = revisit_s))
                    push!(subs, GpsSolver(id))
                end
            end
            rho = Float64[]; nused = Int[]
            for i in 1:nsteps
                (toggle_key !== nothing && i == toggle_at) && (w.fidelity[toggle_key] = toggle_val)
                tick!(w, subs, 1.0e-3)
                append!(rho, w.env[:pseudoranges].rho)                  # the drawn ρ fingerprint
                push!(nused, Int(w.env[:telemetry]["rx1.n_sats_used"]))
            end
            return w, rho, nused
        end
        # NB the ρ VALUES carry the toggled error-term CONTRIBUTIONS (iono/noise/... add to the
        # measurement), so a toggle changes ρ while keeping the DRAW COUNT fixed. The invariant to
        # pin across toggles is therefore the RNG END-STATE (draw-count-invariance), NOT the ρ
        # stream — a raim toggle leaves ρ identical too (it is pure phase-4), but the five error
        # toggles change ρ by design. The same-seed replay below pins the ρ stream (no toggle).
        wa, ra, na = gps_trace(7); wb, rb, nb = gps_trace(7)
        @test ra == rb && reinterpret(UInt64, ra) == reinterpret(UInt64, rb)   # bit-identical ρ stream
        @test na == nb

        # draw-free rung switch: raim :off vs :exclude share the rng end-state (no draw change)
        # but n_sats_used differs (6 vs 5 — the fault is excluded; not a dead knob).
        wo, ro, no = gps_trace(7; start_fid = Dict(:raim => :off))
        we, re, ne = gps_trace(7; start_fid = Dict(:raim => :exclude))
        @test reinterpret(UInt64, ro) == reinterpret(UInt64, re)   # same drawn stream (rung is phase-4)
        @test rand(copy(wo.rng)) == rand(copy(we.rng))             # ...and rng end-states in lockstep
        @test no != ne                                             # ...but n_sats_used differs (6 vs 5)

        # mid-run TOGGLE and INTRODUCE of EACH of the six keys → the RNG END-STATE is bit-identical
        # to never-toggling (the toggle changes NO draw — the whole introduce-safe claim). ρ VALUES
        # differ for the five error toggles (the contribution enters), so pin the rng state, not ρ.
        wn, _, _ = gps_trace(7)                                    # baseline (no fidelity keys)
        rng_base = rand(copy(wn.rng))
        for key in (:iono, :tropo, :clock, :multipath, :noise, :raim)
            val = key === :raim ? :exclude : :on
            wk, _, _ = gps_trace(7; toggle_key = key, toggle_val = val, toggle_at = 15)
            @test rand(copy(wk.rng)) == rng_base                   # introduce/toggle added no draws
        end
    end

    # Slice 8: the FIRST force-based integrator (BallisticMissile, phase 1). There is NO RNG in
    # slice 8 (a closed-form ODE solve), so — advisor #1, the one place copying the slice-5/6/7
    # template gives a FALSE claim — "draw-count-invariance" / "rng lockstep" is VACUOUS. Pin the
    # THREE distinct claims instead: (1) INTRODUCE-safe (introducing :integrator on a NON-missile
    # world is a no-op → byte-identical); (2) same-config replay is bit-identical (trivially, no
    # RNG to desync); (3) a mid-run :integrator toggle CHANGES the trajectory (the not-a-dead-knob
    # property — the OPPOSITE of slices 5/6/7's toggle-invariance; :integrator is physics-changing).
    @testset "a missile scenario: replay bit-identical, but the integrator toggle CHANGES it" begin
        function missile_trace(seed; integrator = :rk4, nsteps = 800, toggle_at = 0, toggle_to = nothing,
                               start_int = integrator)
            fid = Dict{Symbol,Symbol}()
            start_int === nothing || (fid[:integrator] = start_int)   # nothing → INTRODUCE later
            w = World(seed = seed, fidelity = fid)
            w.entities[:m1] = Entity(:m1, :missile; pos = Vec3(0, 0, 0.0), vel = Vec3(300.0, 0, 300.0),
                comp = Dict{Symbol,Any}(:mass_kg => 100.0, :cd_area_m2 => 0.0, :rho => 1.225))
            subs = Subsystem[BallisticMissile(:m1)]
            trace = Float64[]
            for i in 1:nsteps
                (toggle_to !== nothing && i == toggle_at) && (w.fidelity[:integrator] = toggle_to)
                tick!(w, subs, 1.0e-3)
                append!(trace, w.entities[:m1].pos); append!(trace, w.entities[:m1].vel)
                empty!(w.events)
            end
            return w, trace
        end

        # (2) same-config replay bit-identical (the pos/vel fingerprint, reinterpret — sign of zero).
        _, ta = missile_trace(0; integrator = :rk4)
        _, tb = missile_trace(0; integrator = :rk4)
        @test ta == tb && reinterpret(UInt64, ta) == reinterpret(UInt64, tb)

        # (3) a mid-run rk4→euler toggle CHANGES the trajectory (the not-a-dead-knob property —
        # the OPPOSITE of the last three slices). Toggle early (step 100) with plenty of steps left
        # so the divergence is numerically unambiguous. Both runs are internally deterministic.
        _, tk1 = missile_trace(0; start_int = :rk4, toggle_at = 100, toggle_to = :euler)
        _, tk2 = missile_trace(0; start_int = :rk4, toggle_at = 100, toggle_to = :euler)
        @test reinterpret(UInt64, tk1) == reinterpret(UInt64, tk2)   # each internally deterministic
        _, tnever = missile_trace(0; integrator = :rk4)              # never toggled
        @test tk1 != tnever                                          # ...but the toggle changed the flight

        # (1) INTRODUCE-safe: introducing :integrator on a NON-missile world (the RandomWalker
        # fixture) is a no-op — nothing reads the key without a BallisticMissile — so the trace is
        # byte-identical to never touching it (the slice-1..7-stay-byte-identical claim, in miniature).
        function walker_trace(; introduce = false, at = 100, nsteps = 300)
            w = World(seed = 42)
            w.entities[:walker] = Entity(:walker, :target; pos = Vec3(0.0, 0.0, 0.0),
                                         vel = Vec3(1.0, -2.0, 0.5))
            subs = Subsystem[RandomWalker(:walker, 0.3)]
            tr = Vec3[]
            for i in 1:nsteps
                introduce && i == at && (w.fidelity[:integrator] = :euler)
                tick!(w, subs, 1.0e-3)
                push!(tr, w.entities[:walker].pos)
            end
            return w, tr
        end
        wi, ti = walker_trace(introduce = true)
        wn, tn = walker_trace(introduce = false)
        @test ti == tn                                              # introduce :integrator = no-op
        @test rand(copy(wi.rng)) == rand(copy(wn.rng))              # ...and the rng stream untouched
    end
end
