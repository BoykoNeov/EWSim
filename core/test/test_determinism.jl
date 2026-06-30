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
end
