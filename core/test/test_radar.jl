# test_radar.jl — the radar SUBSYSTEM dispatch on the propagation knob (slice-2 step 2).
#
# rf.jl's two_ray physics is pinned closed-form in test_propagation; test_radar_eq pins
# free-space. THIS file pins the SUBSYSTEM wiring in `observe!`: it dispatches on
# `w.fidelity[:propagation]`, decomposes geometry into slant/ground, applies the
# below-horizon POLICY, and never lets -Inf/NaN reach the telemetry bag (the wire). Six
# contracts, each against an independent truth:
#   1. default (no fidelity set) == free_space — slice-1 behaviour is untouched;
#   2. two_ray telemetry == the independent snr_two_ray closed form (slant ≠ ground geom);
#   3. a below-horizon target is masked: visible=false, finite floor, pd ≈ pfa, no crash;
#   4. no Inf/NaN reaches the wire at a perfect null (F⁴=0) — the JSON frame round-trips;
#   5. the draw stream is fidelity-independent (determinism: detect_once stays unconditional);
#   6. an unknown propagation rung errors loudly (named, not silent).

using JSON3

# A radar at (0,0,h_r) and one target at (tx,0,h_t); clean λ=0.03 numbers so the two_ray
# phase geometry has no rounding to argue about. `prop = nothing` leaves the fidelity map
# empty (to exercise the get(...,:free_space) default); otherwise it seeds :propagation.
function _radar_world(; prop = :free_space, seed = 1, h_r = 10.0,
                        tx = 20_000.0, h_t = 30.0, rcs = 1.0, pfa = 1.0e-6, sw = 1)
    fid = prop === nothing ? Dict{Symbol,Symbol}() : Dict(:propagation => prop)
    w = World(seed = seed, fidelity = fid)
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, h_r),
        comp = Dict{Symbol,Any}(:pt_w => 1000.0, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6,
            :noise_fig_db => 0.0, :losses_db => 0.0, :pfa => pfa, :swerling => sw))
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(tx, 0, h_t),
        comp = Dict{Symbol,Any}(:rcs_m2 => rcs))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0), ConstantVelocity(:tgt1)]
    return w, subs
end

# Tick once (target is static — vel = 0) and return the published telemetry bag.
function _telemetry(w, subs)
    tick!(w, subs, 1.0e-3)
    return state_frame(w)[:telemetry]
end

@testset "radar propagation dispatch" begin

    @testset "default fidelity is free_space (slice-1 untouched)" begin
        # No :propagation in the map → the get(...,:free_space) default must fire.
        w, subs = _radar_world(prop = nothing)
        rad = w.entities[:radar1];  tgt = w.entities[:tgt1]
        R   = sqrt(sum(abs2, tgt.pos - rad.pos))
        rp  = EWSim._radar_params(rad.comp)
        tel = _telemetry(w, subs)
        @test tel["radar1.snr_db"] ≈ lin2db(snr_freespace(rp, 1.0, R)) rtol = 1e-12
        @test tel["radar1.visible"] == true                  # free space = infinite LOS
    end

    @testset "two_ray telemetry == snr_two_ray closed form (slant ≠ ground)" begin
        # High-grazing geometry: ground = 2000, h_t = 1000 ⇒ slant = 2231.6 ≠ ground, so a
        # slant/ground swap in the dispatch would show. Well inside horizon(10,1000) ≈ 143 km.
        w, subs = _radar_world(prop = :two_ray, tx = 2000.0, h_t = 1000.0)
        rad = w.entities[:radar1];  tgt = w.entities[:tgt1]
        rp  = EWSim._radar_params(rad.comp)
        slant  = sqrt(sum(abs2, tgt.pos - rad.pos))
        ground = hypot(tgt.pos[1] - rad.pos[1], tgt.pos[2] - rad.pos[2])
        expect = snr_two_ray(rp, 1.0, slant; h_r = 10.0, h_t = 1000.0, ground_m = ground)
        tel = _telemetry(w, subs)
        @test tel["radar1.snr_db"] ≈ lin2db(expect) rtol = 1e-12
        @test tel["radar1.visible"] == true
        # ...and it genuinely differs from free space (F⁴ ≠ 1 at this geometry).
        @test !(tel["radar1.snr_db"] ≈ lin2db(snr_freespace(rp, 1.0, slant)))
    end

    @testset "below-horizon target is masked (visible=false, finite floor)" begin
        # radar z=10, target z=30 ⇒ horizon ≈ 35.6 km; put the target at 100 km ground.
        w, subs = _radar_world(prop = :two_ray, tx = 100_000.0, h_t = 30.0)
        tel = _telemetry(w, subs)
        @test tel["radar1.visible"] == false
        @test isfinite(tel["radar1.snr_db"])                 # NOT -Inf
        @test tel["radar1.snr_db"] == EWSim._SNR_DB_FLOOR    # masked → floor
        @test tel["radar1.pd"] ≤ 1.0e-5                      # SNR 0 ⇒ pd ≈ pfa
    end

    @testset "no Inf/NaN reaches the wire at a perfect null (JSON round-trip)" begin
        # A perfect null ABOVE the horizon (a null, not a mask): h_r·h_t = 300, so
        # Δφ = 4π·300/(0.03·R_g) = 2π at R_g = 20 km (< 35.6 km horizon) ⇒ F⁴ = 0 ⇒ SNR = 0.
        # lin2db(0) = -Inf would make JSON3 emit invalid JSON (the slice-2 watch-item).
        w, subs = _radar_world(prop = :two_ray, tx = 20_000.0, h_t = 30.0)
        tick!(w, subs, 1.0e-3)
        frame = state_frame(w)
        sdb = frame[:telemetry]["radar1.snr_db"]
        @test isfinite(sdb)                                  # the whole point: not -Inf
        @test sdb ≤ -100.0                                   # it IS a deep null (floored)
        @test frame[:telemetry]["radar1.visible"] == true    # above horizon: a null, not a mask
        # the frame must survive the REAL wire (JSON3 throws on Inf/NaN).
        io = IOBuffer(); write_frame(io, frame); seekstart(io)
        back = read_frame(io)
        @test isfinite(back.telemetry[Symbol("radar1.snr_db")])
    end

    @testset "draw stream is fidelity-independent (detect_once unconditional)" begin
        # free_space and two_ray must advance w.rng identically (same randn count per look),
        # so toggling fidelity never desyncs seeded replay. Use a BELOW-horizon (masked,
        # SNR=0) two_ray geometry — the strongest case: a masked target still costs its
        # draws. After K identical looks the two streams must sit at the same point.
        wf, sf = _radar_world(prop = :free_space, seed = 20260621, tx = 100_000.0, h_t = 30.0)
        wt, st = _radar_world(prop = :two_ray,    seed = 20260621, tx = 100_000.0, h_t = 30.0)
        for _ in 1:50
            tick!(wf, sf, 1.0e-3)
            tick!(wt, st, 1.0e-3)
        end
        @test rand(copy(wf.rng)) == rand(copy(wt.rng))       # streams in lockstep
    end

    @testset "an unknown propagation rung errors (named, not silent)" begin
        w, subs = _radar_world(prop = :telepathy)
        @test_throws ErrorException tick!(w, subs, 1.0e-3)
    end
end

# --- CFAR profile dispatch (slice-3 step 3) -------------------------------------
#
# A scenario carrying a :cfar fidelity routes observe! to the PROFILE path: build a
# range-power profile every look, draw it (the one RNG call), threshold with the active
# rung. The contracts here pin the SUBSYSTEM wiring (the CFAR closed forms are in test_cfar,
# the draw is _draw_profile!): the rung selects the rule not the draw (determinism seam),
# fixed false-alarms across a clutter band while CA holds it (the lesson), arrays never ship
# Inf/NaN, a target-free profile still ships, the draw order is golden-pinned, bad rung errors.

# Δr = c/2B with B = 1 MHz ≈ 149.9 m — shared by the fixtures and the band-index math.
const _CFAR_DR = EWSim.C_LIGHT / (2 * 1.0e6)

# A CFAR radar world. Target at `tgt_x` (20 km → cell ~134 at 256 cells); optional wide
# clutter band of `clut_cells` cells from 10 km at `cnr_db` (CNR over the noise floor).
function _cfar_world(; variant = :ca, seed = 1, ncells = 256, ntrain = 16, nguard = 2,
                       pfa = 1.0e-3, target = true, clut_cells = 0, cnr_db = 18.0,
                       tgt_x = 20_000.0)
    w = World(seed = seed, fidelity = Dict(:cfar => variant))
    w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 0),
        comp = Dict{Symbol,Any}(:pt_w => 1.0e4, :gain_db => 30.0,
            :freq_hz => EWSim.C_LIGHT / 0.03, :bandwidth_hz => 1.0e6, :noise_fig_db => 0.0,
            :losses_db => 0.0, :pfa => pfa, :swerling => 1, :n_pulses => 1,
            :n_cells => ncells, :range_start_m => 0.0, :n_train => ntrain, :n_guard => nguard))
    subs = Subsystem[RadarSensor(:radar1; revisit_s = 0.0)]
    if target
        w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(tgt_x, 0, 0),
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0))
        push!(subs, ConstantVelocity(:tgt1))
    end
    if clut_cells > 0
        w.entities[:clut1] = Entity(:clut1, :clutter; pos = Vec3(10_000.0, 0, 0),
            comp = Dict{Symbol,Any}(:extent_m => clut_cells * _CFAR_DR, :cnr_db => cnr_db))
    end
    return w, subs
end

@testset "radar CFAR profile dispatch" begin

    @testset "profile telemetry is well-formed and round-trips (no Inf/NaN)" begin
        w, subs = _cfar_world(variant = :ca, clut_cells = 40)
        tick!(w, subs, 1.0e-3)
        frame = state_frame(w);  tel = frame[:telemetry]
        @test length(tel["radar1.profile_db"])   == 256        # per-cell arrays present
        @test length(tel["radar1.threshold_db"]) == 256
        @test length(tel["radar1.detections"])   == 256
        @test all(isfinite, tel["radar1.profile_db"])          # never -Inf/NaN
        @test all(isfinite, tel["radar1.threshold_db"])
        @test eltype(tel["radar1.detections"]) === Bool
        # slice-1/2 scalars stay (existing consumers bind to them)
        @test haskey(tel, "radar1.snr_db") && haskey(tel, "radar1.pd") &&
              haskey(tel, "radar1.detected") && haskey(tel, "radar1.visible")
        # the REAL wire (JSON3 throws on Inf/NaN): array telemetry round-trips intact
        io = IOBuffer(); write_frame(io, frame); seekstart(io); back = read_frame(io)
        @test all(isfinite, back.telemetry[Symbol("radar1.profile_db")])
        @test length(back.telemetry[Symbol("radar1.threshold_db")]) == 256
    end

    @testset "rung selects the rule, not the draw (determinism seam)" begin
        # Same seed under two rungs: the profile DRAW is identical (rng ends in lockstep), but
        # the thresholding rule changes the detections. A clutter band makes them differ.
        wf, sf = _cfar_world(variant = :fixed, seed = 42, clut_cells = 60)
        wc, sc = _cfar_world(variant = :ca,    seed = 42, clut_cells = 60)
        tick!(wf, sf, 1.0e-3);  tick!(wc, sc, 1.0e-3)
        @test rand(copy(wf.rng)) == rand(copy(wc.rng))           # draw-count invariant
        @test state_frame(wf)[:telemetry]["radar1.detections"] !=
              state_frame(wc)[:telemetry]["radar1.detections"]   # rule changed the outcomes
    end

    @testset "fixed lights the clutter band interior; ca holds it (the lesson)" begin
        # A flat threshold false-alarms across the elevated clutter band; CA tracks the floor
        # and holds the design Pfa in the band interior. Count interior detections at fixed
        # seeds (deterministic). The single-edge spike is the CA-vs-GO/OS lesson (gate 4);
        # the band INTERIOR is the clean, unambiguous fixed-vs-CA discriminator (advisor catch).
        lo = round(Int, 10_000.0 / _CFAR_DR) + 1
        interior = (lo + 10):(lo + 57)              # ~48 band cells, away from straddling edges
        function band_hits(v)
            w, s = _cfar_world(variant = v, seed = 777, clut_cells = 60, cnr_db = 18.0)
            tick!(w, s, 1.0e-3)
            return count(state_frame(w)[:telemetry]["radar1.detections"][interior])
        end
        nf = band_hits(:fixed);  nc = band_hits(:ca)
        @test nf > 20                               # flat threshold lit most of the band
        @test nc ≤ 2                                # CFAR held Pfa≈1e-3 over ~48 cells ⇒ ≈0
        @test nf > 10 * (nc + 1)                    # a decisive contrast, not a fluke
    end

    @testset "clutter-only profile still draws + ships (no targets)" begin
        # A target-free CFAR view is valid (the sandbox shows the noise+clutter floor). The
        # path must NOT early-return on an empty target list (advisor catch); best_snr=-Inf
        # then floors cleanly through _snr_db_wire.
        w, subs = _cfar_world(variant = :ca, target = false, clut_cells = 40)
        tick!(w, subs, 1.0e-3)
        tel = state_frame(w)[:telemetry]
        @test length(tel["radar1.profile_db"]) == 256
        @test all(isfinite, tel["radar1.profile_db"])
        @test tel["radar1.snr_db"] == EWSim._SNR_DB_FLOOR       # no target ⇒ -Inf ⇒ floor
        @test tel["radar1.pd"] == 0.0
        @test tel["radar1.detected"] == false
    end

    @testset "draw golden: _draw_profile! draw order is pinned" begin
        # Pin the exact randn draw order/values of the profile sampler so a future refactor
        # can't silently desync the CFAR draw stream (the _sample_z golden discipline applied
        # to the new path; test_determinism only compares run-to-run). `===` is bit-equality.
        power = [1.0, 1.0, 5.0, 1.0, 20.0, 1.0]
        g1 = [0.8164645986087463, 3.040171342917835, 0.4101595506616429,
              0.17782242068769563, 5.5640856137949335, 0.5278312304628222]
        z = Vector{Float64}(undef, 6)
        EWSim._draw_profile!(z, power, Xoshiro(20260622), 1)
        @test all(z .=== g1)
        g3 = [3.93866785165891, 0.9838579318402645, 16.774422550829435,
              1.5919361208140081, 81.48105839890393, 4.654186082948093]
        EWSim._draw_profile!(z, power, Xoshiro(20260622), 3)
        @test all(z .=== g3)
    end

    @testset "detection events carry the cell/range; :of only on a target hit" begin
        # Target injection + the event CONTRACT (the slice-3 plan's "lesson surface", §5): a
        # target-cell hit carries :of/:cell/:range with the RIGHT index — the off-by-one-prone
        # `_range_to_cell`, verified through the full observe path, not in isolation — while a
        # clutter false alarm carries :cell/:range but NO :of. A static high-SNR target (~28 dB)
        # fires its cell nearly every look, so "seen over the dwell" is robust, not seed-tuned.
        w, subs = _cfar_world(variant = :ca, seed = 20260622, clut_cells = 0)
        w.entities[:tgt1].comp[:rcs_m2] = 100.0
        rad = w.entities[:radar1]
        R = sqrt(sum(abs2, w.entities[:tgt1].pos - rad.pos))
        expect_cell = round(Int, R / _CFAR_DR) + 1
        seen = nothing
        for _ in 1:30
            tick!(w, subs, 1.0e-3)
            for ev in w.events
                get(ev, :of, nothing) === :tgt1 && (seen = ev)
            end
            empty!(w.events)
        end
        @test seen !== nothing                       # the target cell detected over the dwell
        @test seen[:of] === :tgt1
        @test seen[:by] === :radar1
        @test seen[:cell] == expect_cell             # _range_to_cell index pinned end-to-end
        @test seen[:range] ≈ _CFAR_DR * (expect_cell - 1)

        # a clutter false alarm under :fixed: :cell/:range present, NO :of (no target there).
        wf, sf = _cfar_world(variant = :fixed, seed = 99, clut_cells = 60)
        tick!(wf, sf, 1.0e-3)
        fa = nothing
        for ev in wf.events
            if !haskey(ev, :of)
                fa = ev
                break
            end
        end
        @test fa !== nothing                         # the clutter band false-alarmed
        @test haskey(fa, :cell) && haskey(fa, :range)
        @test !haskey(fa, :of)                       # a noise/clutter cell is not "of" a target
    end

    @testset "an unknown cfar rung errors (named, not silent)" begin
        w, subs = _cfar_world(variant = :telepathy)
        @test_throws ErrorException tick!(w, subs, 1.0e-3)
    end
end

# --- slice 30: the CROSSING-SPEED pin on ConstantVelocity (the ENGAGEMENT axis) -------------
#
# `ConstantVelocity` is the most-shared mover in the project (targets, decoys, jammers, DF
# emitters/sensors, pulse emitters, ESM, GPS satellites all mount it), so a new key inside its
# `integrate!` is exactly the shared-symbol hazard convention 2 is about. These teeth pin the
# MECHANICS of the pin; the loader half lives in test_scenario.jl and the draw-count identity
# in test_missile.jl.
#
# ⭐⭐ THE ONE THAT MATTERS IS "THE ORDERING". Every EQUAL-VALUE test — including the byte-identity
# and knob-vs-rung ones below — passes with the pin written on the WRONG side of the `pos` update,
# because both orders agree when the pinned value equals the authored one. Only a DISAGREEING pair
# separates them (`docs/plans/slice30.md` gate 1: gate 0's own bit-identity probe could not see
# the bug, and the plan's first draft shipped it).

# A bare phase-1 mover: one target, one `ConstantVelocity`, no sensors. `cross`/`alt` mint their
# comp keys only when non-`nothing` — the presence gate is the thing under test.
function _mover_world(; vel = Vec3(-200.0, 0.0, 0.0), pos = Vec3(10_000.0, 0.0, 100.0),
                        cross = nothing, alt = nothing)
    w = World(seed = 30)
    comp = Dict{Symbol,Any}(:rcs_m2 => 1.0)
    cross === nothing || (comp[:cross_speed_mps] = cross)
    alt   === nothing || (comp[:alt_hold_m]      = alt)
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = pos, vel = vel, comp = comp)
    return w, Subsystem[ConstantVelocity(:tgt1)]
end

# The full state trace (pos+vel, every tick) — a bit-for-bit record, not a summary.
function _mover_trace(; n = 400, dt = 1.0e-3, kw...)
    w, subs = _mover_world(; kw...)
    out = Float64[]
    for _ in 1:n
        tick!(w, subs, dt)
        e = w.entities[:tgt1]
        append!(out, (e.pos[1], e.pos[2], e.pos[3], e.vel[1], e.vel[2], e.vel[3]))
    end
    return out
end

@testset "the CROSSING-SPEED pin on ConstantVelocity (slice 30 — the engagement axis)" begin

    @testset "BYTE-IDENTITY — no `cross_speed_mps` key ⇒ the slice-1..29 mover, bit-for-bit" begin
        # The presence gate short-circuits before any arithmetic, so the key-absent path is
        # TEXTUALLY the shipped `pos += vel·dt`. Paired with a does-pin arm so the claim is not
        # vacuous (a test that only ever compares two no-key runs proves determinism, not gating).
        base = _mover_trace()
        @test _mover_trace() == base                        # determinism, and the control
        @test _mover_trace(cross = 200.0) != base           # …PAIRED with an arm that DOES pin
        @test _mover_trace(cross = -200.0) != _mover_trace(cross = 200.0)   # the SIGN is live
    end

    @testset "THE KNOB-vs-RUNG DISCRIMINATOR — pinning the AUTHORED value is bit-identical" begin
        # The off-state is knob-REACHABLE (atmosphere.jl's discriminator): a `cross_speed_mps`
        # equal to the authored `vel_y` is the same run, bit-for-bit — so this is a KNOB, and the
        # fact is MEASURED rather than argued (the slice-26/28/29 rule).
        auth = _mover_trace(vel = Vec3(-200.0, 200.0, 0.0))
        @test _mover_trace(vel = Vec3(-200.0, 200.0, 0.0), cross = 200.0) == auth
        @test _mover_trace(vel = Vec3(-200.0, 0.0, 0.0), cross = 0.0) == _mover_trace()
    end

    @testset "⭐⭐ THE ORDERING — the DISAGREEING pair, the only tooth that sees the bug" begin
        # Authored vel_y = 200 pinned to 0 must be the SAME RUN as a target authored vel_y = 0
        # with no key at all: the pin runs BEFORE the `pos` update, so the 200 is never integrated.
        # Written after the update, tick 1 advances y by 200·dt = 0.2 m and every later tick
        # carries that offset — a permanent 0.2 m the equal-value teeth above cannot see.
        @test _mover_trace(vel = Vec3(-200.0, 200.0, 0.0), cross = 0.0) == _mover_trace()
        # …and the same fact in the observable the plan states, legible because this fixture is
        # authored at y = 0: EXACTLY zero, not "small".
        w, subs = _mover_world(vel = Vec3(-200.0, 200.0, 0.0), cross = 0.0)
        ymax = 0.0
        for _ in 1:400
            tick!(w, subs, 1.0e-3)
            ymax = max(ymax, abs(w.entities[:tgt1].pos[2]))
        end
        @test ymax == 0.0
    end

    @testset "the pin HOLDS every tick, and a live write lands on the very next one" begin
        # Not just the first tick: the pin is re-applied each `integrate!`, so it overrides an
        # authored vel_y for the whole run (a one-shot assignment would drift back only if some
        # other subsystem wrote vel — but the CONTRACT is a per-tick pin, and that is what
        # composes with a slider).
        dt = 1.0e-3
        w, subs = _mover_world(vel = Vec3(-200.0, 200.0, 0.0), cross = 50.0)
        for _ in 1:100; tick!(w, subs, dt); end
        e = w.entities[:tgt1]
        @test e.vel[2] == 50.0                              # THE PIN — exact, it is an assignment
        @test e.vel[1] == -200.0                            # …and vel_x/vel_z are untouched
        @test e.vel[3] == 0.0
        # the POSITION is an accumulation of 100 floats and is NOT exactly 5.0 (convention 11:
        # an explicit atol, never an `==` on a summed float).
        @test e.pos[2] ≈ 100 * 50.0 * dt atol = 1.0e-9
        @test e.pos[1] ≈ 10_000.0 - 100 * 200.0 * dt atol = 1.0e-9   # x still integrates
        # the LIVE slider write (the test_terrain.jl:335 `alt_hold_m` shape): it takes effect on
        # the NEXT tick, which is what a `set_param` mid-run needs.
        e.comp[:cross_speed_mps] = -300.0
        tick!(w, subs, dt)
        @test e.vel[2] == -300.0
    end

    @testset "it COMPOSES with `alt_hold_m` — disjoint coordinates, one pins vel.y one pos.z" begin
        dt = 1.0e-3
        w, subs = _mover_world(vel = Vec3(-200.0, 0.0, 40.0), pos = Vec3(10_000.0, 0.0, 100.0),
                               cross = 120.0, alt = 300.0)
        for _ in 1:100; tick!(w, subs, dt); end
        e = w.entities[:tgt1]
        @test e.pos[3] == 300.0                             # the altitude hold, exact (a pos pin)
        @test e.vel[2] == 120.0                             # the crossing pin, exact (a vel pin)
        @test e.pos[2] ≈ 100 * 120.0 * dt atol = 1.0e-9     # y integrates on the PINNED speed
        @test e.pos[1] ≈ 10_000.0 - 100 * 200.0 * dt atol = 1.0e-9
        # order-independence of the two keys: the composed run is the composition, not a fight.
        @test _mover_trace(vel = Vec3(-200.0, 0.0, 40.0), cross = 120.0, alt = 300.0) !=
              _mover_trace(vel = Vec3(-200.0, 0.0, 40.0), cross = 120.0)
    end

    @testset "no live value can crash a tick (convention 5 — finite in, finite out)" begin
        # There is no consumer clamp by design (the `alt_hold_m` / slice-28 `radome_ripple`
        # posture: the sign matters and every magnitude is crash-safe), so pin the claim.
        dt = 1.0e-3
        for v in (0.0, -1.0e6, 1.0e6)
            w, subs = _mover_world(cross = v)
            for _ in 1:50; tick!(w, subs, dt); end
            p = w.entities[:tgt1].pos
            @test all(isfinite, (p[1], p[2], p[3]))
        end
    end
end
