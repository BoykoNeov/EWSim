# test_track.jl — SLICE 53 GATE 2: the TRACK, and the two edges of one pass.
#
# Gate 1 shipped the tail lobe as PHYSICS (a cross-section that tells nose from tail). It shipped no
# way to SEE the consequence: the slice's gauge is a difference of two RUN-RULE EDGES over a pass —
# how far out the track was first gained coming in, against how far out it was finally lost going
# away — and a run rule counted in LOOKS cannot be run by a client that only sees FRAMES.
#
# ⚠⚠ THE STRONGEST TOOTH IN THIS FILE IS THE ORACLE ONE, and it is what makes the whole of gate 0
# quotable: every number in `docs/plans/slice53.md` §2.8 / §2.9 / §2.15 came from an OFFLINE rule
# applied to a per-look array (split at CPA by `argmin`, mirrored edges, `N`* = 3). The core now
# computes those edges LIVE — no history array, and a RANGE-RATE sign instead of an argmin. If the
# two disagree anywhere, the ceiling of 50 and the default of 20 were chosen for a rule the showcase
# does not run. They are therefore compared on the same flights, and against the plan's own printed
# numbers (convention 11: an EXTERNAL anchor, produced by a different program on a different day).

const _TRK_SEEDS = (53, 149, 250, 1, 2, 3, 4, 5)

# ⚠ BUILT BY A FUNCTION, NEVER BY `replace`-ing lines out of one literal — gate 1's own harness trap
# (a deleted line leaves its indentation behind and the next key folds onto the previous one, so a
# malformed variant loads clean and its tooth passes vacuously).
function _trk_yaml(; seed = 53, gain = nothing, drop = "3", revisit = "0.1",
                     dt = "1.0e-3", cfar = false)
    io = IOBuffer()
    println(io, "name: trk_flypast")
    println(io, "seed: ", seed)
    println(io, "dt_physics: ", dt)
    println(io, "emit_every: 16")
    println(io, "fidelity:")
    println(io, "  propagation: free_space")
    println(io, "  detection:   analytic")
    cfar && println(io, "  cfar:        ca")
    println(io, "entities:")
    println(io, "  - id: radar1")
    println(io, "    kind: radar")
    println(io, "    pos: [0, 0, 30]")
    println(io, "    radar:")
    println(io, "      pt_w:         50000")
    println(io, "      gain_db:      35")
    println(io, "      freq_hz:      9.4e9")
    println(io, "      bandwidth_hz: 1.0e6")
    println(io, "      noise_fig_db: 3")
    println(io, "      losses_db:    4")
    println(io, "      pfa:          1.0e-6")
    println(io, "      swerling:     1")
    println(io, "      n_pulses:     1")
    cfar && println(io, "      n_cells:      64")
    revisit === nothing || println(io, "      revisit_s:    ", revisit)
    drop    === nothing || println(io, "      track_drop_looks: ", drop)
    println(io, "  - id: tgt1")
    println(io, "    kind: target")
    println(io, "    pos: [-15000.0, 0.0, 5000.0]")
    println(io, "    vel: [300.0, 0.0, 0.0]")
    println(io, "    target:")
    println(io, "      rcs_m2: 4.0")
    println(io, "      rcs_fineness: 8.0")
    gain === nothing || println(io, "      rcs_tail_gain: ", gain)
    return String(take!(io))
end

# One 200 s flight of wire A. Returns the per-look record the OFFLINE rule needs AND the edges the
# CORE shipped — so the two can be compared without flying twice.
function _trk_fly(dir, seed, gain; secs = 200.0)
    p = joinpath(dir, "wireA_s$(seed)_g$(gain === nothing ? "none" : gain).yaml")
    write(p, _trk_yaml(seed = seed, gain = gain))
    sc = load_scenario(p)
    w, subs, dt = sc.world, sc.subs, sc.dt_physics
    radar = w.entities[:radar1]
    looks = NTuple{3,Float64}[]                      # (detected, range_m, core's look index)
    for _ in 1:round(Int, secs / dt)
        prev = get(radar.comp, :next_look_t, 0.0)
        tick!(w, subs, dt)
        if get(radar.comp, :next_look_t, 0.0) != prev
            tl = w.env[:telemetry]
            push!(looks, (get(radar.comp, :detected, false) ? 1.0 : 0.0,
                          Float64(tl["radar1.target_range_m"]), Float64(tl["radar1.track_look"])))
        end
    end
    return (looks, w.env[:telemetry], w)
end

# THE GATE-0 RULE, transcribed from `M:\claud_projects\temp\slice53\p7_endpoints.jl`: the first
# detection followed by a gap of MORE than `N` look indices ends the run. Deliberately written as an
# array scan over the whole flight — the opposite shape from the incremental thing being checked.
function _trk_offline_edge(arr, N)
    d = findall(u -> u[1] == 1.0, arr)
    isempty(d) && return (NaN, -1.0)
    for i in 1:length(d)-1
        d[i+1] - d[i] > N && return (arr[d[i]][2], arr[d[i]][3])
    end
    return (arr[d[end]][2], arr[d[end]][3])
end
_trk_split(looks) = (k = argmin([u[2] for u in looks]); (looks[1:k], looks[k:end]))

@testset "the GIVE-UP RUN RULE is pure and its GAP ARITHMETIC is hand-checkable (slice 53 gate 2)" begin
    # ⭐ THE EXTERNAL ANCHOR IS ARITHMETIC, NOT A REPLAY: with detections at look `a` then `b`, the
    # `b − a − 1` looks between them are the misses, so the track survives iff `b − a ≤ n_drop`.
    # Every downstream number in this slice rests on that one equivalence, so it is checked over a
    # grid rather than at the shipped value.
    for n_drop in 1:5, gap in 1:8
        alive, misses, dropped = true, 0, false
        for _ in 1:(gap - 1)                      # the misses between the two detections
            alive, misses, _, drp = track_run_step(alive, misses, false, n_drop)
            dropped |= drp
        end
        alive2, misses2, opened, _ = track_run_step(alive, misses, true, n_drop)
        @test dropped == (gap > n_drop)           # ⇐ THE EQUIVALENCE
        @test alive2                              # a detection always leaves a live track…
        @test misses2 == 0                        # …with a reset counter
        @test opened == dropped                   # …and it is an OPEN only if the track had died
    end

    @testset "the state machine's own edges" begin
        # `opened` fires on the TRANSITION only — a second detection continues a track, it does not
        # start one. (An `opened` that fired every look would silently re-latch the gain edge at
        # every detection, which would make the inbound edge read the range at CPA.)
        _, _, o1, _ = track_run_step(false, 0, true, 3);  @test o1
        _, _, o2, _ = track_run_step(true,  0, true, 3);  @test !o2
        # `dropped` fires ONCE. The 4th, 5th… consecutive miss must not re-drop an already dead
        # track — the loss edge is latched on the event, and a repeat would relatch it at a stale
        # range on every look for the rest of the flight.
        a, m, _, d3 = track_run_step(true, 2, false, 3);  @test d3 && !a && m == 3
        a4, m4, _, d4 = track_run_step(a, m, false, 3);   @test !d4 && !a4
        @test m4 == 3                             # ⚠ FROZEN while dead: not a countdown to anything
        # `n_drop` is floored at 1 — 0 would mean "drop before a look has been missed", which has no
        # reading. (The loader refuses it too; this is the consumer-side floor, convention 5.)
        for bad in (0, -7)
            _, _, _, dd = track_run_step(true, 0, false, bad)
            @test dd
        end
        # Types, because the caller stores these in a comp bag and reads them back with `get`.
        st = track_run_step(true, 1, false, 3)
        @test st isa Tuple{Bool,Int,Bool,Bool}
    end
end

@testset "the TRACKER is KEY-PRESENCE GATED — a wire that authors none is untouched (53 gate 2)" begin
    mktempdir() do dir
        # A radar with no give-up rule runs no tracker, keeps no state and ships no key. This is the
        # `terrain_clearance_m` / slice-49 posture, and it is what keeps slices 1–52 byte-identical.
        p = joinpath(dir, "notracker.yaml"); write(p, _trk_yaml(drop = nothing))
        sc = load_scenario(p); w, subs, dt = sc.world, sc.subs, sc.dt_physics
        @test !haskey(w.entities[:radar1].comp, :track_drop_looks)
        for _ in 1:2000; tick!(w, subs, dt); end
        tl = w.env[:telemetry]
        @test !any(startswith(k, "radar1.track") for k in keys(tl))
        @test !any(startswith(String(k), "trk_") for k in keys(w.entities[:radar1].comp))
        # …and the shipped slice-49 wire, which is the one this instrument was designed against,
        # ships no track key either — it authors no rule.
        s49 = load_scenario(normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice49_aspect.yaml")))
        for _ in 1:2000; tick!(s49.world, s49.subs, s49.dt_physics); end
        @test !any(startswith(k, "radar1.track") for k in keys(s49.world.env[:telemetry]))

        # ⭐⭐ THE PAIRED ARM THAT MOVES. A tooth that only shows the keys ABSENT proves nothing
        # about the ones present, so the same wire with the rule authored ships the whole set — and
        # the FLIGHT is bit-identical either way, because the tracker is a readout over a draw it
        # does not touch (convention 3: the draw topology is invariant).
        q = joinpath(dir, "tracker.yaml"); write(q, _trk_yaml())
        sq = load_scenario(q); wq = sq.world
        for _ in 1:2000; tick!(wq, sq.subs, sq.dt_physics); end
        tq = wq.env[:telemetry]
        for k in ("track_drop_looks", "track_revisit_s", "track_alive", "track_closing",
                  "track_misses", "track_look", "track_gain_range_m", "track_gain_look",
                  "track_loss_range_m", "track_loss_look")
            @test haskey(tq, "radar1.$k")
        end
        @test tq["radar1.track_drop_looks"] == 3.0
        @test tq["radar1.track_revisit_s"] == 0.1
        @test wq.entities[:tgt1].pos == w.entities[:tgt1].pos      # ⇐ same flight, to the bit
        @test wq.entities[:tgt1].vel == w.entities[:tgt1].vel
        for k in ("radar1.snr_db", "radar1.pd", "radar1.detected", "radar1.target_range_m",
                  "radar1.rcs_eff_m2", "radar1.target_aspect_deg")
            @test tq[k] == tl[k]                                   # ⇐ every OLD key unchanged
        end
        # ⚠ THE RULE TRAVELS WITH THE NUMBERS, and that is the point of shipping it (gate-0 §2.14:
        # the metres are a joint property of the lobe and the TRACKER). A HUD cannot print a range
        # without also having the `revisit_s` and the give-up depth it was measured under.
        @test tq["radar1.track_revisit_s"] == load_scenario(q).world.entities[:radar1].comp[:revisit_s]
    end
end

@testset "the LOSS LATCH belongs to the OUTBOUND leg only — the straddling gap (53 gate 2)" begin
    # A gap that STRADDLES closest approach would otherwise latch a "range we lost it at" whose last
    # detection was on the way IN — a number from the wrong leg wearing the right name. The offline
    # rule skipped such a gap structurally (it lies in neither `looks[1:k]` nor `looks[k:end]`);
    # here it is skipped by an explicit arming flag, so it is worth driving by hand.
    # ⚠ Driven through `_track_look!` directly: the sequence needed does not occur on wire A (the
    # target is brightest and closest at CPA, so a 3-miss run there is a `pfa`-scale event), and a
    # branch no shipped wire exercises is exactly the kind that rots.
    radar = Entity(:r1, :radar; pos = Vec3(0.0, 0.0, 0.0),
                   comp = Dict{Symbol,Any}(:track_drop_looks => 3))
    step!(det, R, rdot) = EWSim._track_look!(radar, det, R, rdot)
    step!(true, 9000.0, -300.0)      # inbound, track opens at 9000 m  ⇐ the gain edge
    step!(true, 8000.0, -300.0)
    step!(false, 7000.0, -300.0)     # …then three misses that straddle CPA
    step!(false, 6000.0, -300.0)
    step!(false, 6000.0, +300.0)     # the CPA look itself, and the DROP falls here
    @test radar.comp[:trk_gain_range] == 9000.0
    @test !haskey(radar.comp, :trk_loss_range)          # ⇐ NOT latched: the last detection was inbound
    @test radar.comp[:trk_past_cpa]
    step!(true, 7000.0, +300.0)      # a fresh outbound run…
    step!(true, 8000.0, +300.0)
    step!(false, 9000.0, +300.0)
    step!(false, 10000.0, +300.0)
    step!(false, 11000.0, +300.0)    # …whose drop IS the loss
    @test radar.comp[:trk_loss_range] == 8000.0
    @test radar.comp[:trk_gain_range] == 9000.0         # ⇐ and the outbound run did NOT move the gain
    # The latch is once-only: a later drop must not overwrite the edge with a stale range.
    step!(true, 12000.0, +300.0)
    for _ in 1:3; step!(false, 13000.0, +300.0); end
    @test radar.comp[:trk_loss_range] == 8000.0

    @testset "the CPA look belongs to BOTH legs (the shared-index posture)" begin
        # The offline rule split on a SHARED index `k`, so a track opening at the CPA look is a
        # GAIN and a detection at the CPA look arms the LOSS. An off-by-one here would be invisible
        # on wire A and wrong on any wire whose track is thin at closest approach.
        r2 = Entity(:r2, :radar; pos = Vec3(0.0, 0.0, 0.0),
                    comp = Dict{Symbol,Any}(:track_drop_looks => 3))
        EWSim._track_look!(r2, true, 5000.0, +0.0)      # the CPA look, opening a track
        @test r2.comp[:trk_gain_range] == 5000.0        # ⇐ inbound: the CPA look still counts
        @test r2.comp[:trk_post_cpa_det]                # ⇐ outbound: it counts there too
        @test r2.comp[:trk_past_cpa]                    # and the leg has flipped there
        for _ in 1:3; EWSim._track_look!(r2, false, 5100.0, +300.0); end
        @test r2.comp[:trk_loss_range] == 5000.0
        @test r2.comp[:trk_loss_look] == 1
    end

    @testset "an inbound flicker RESTARTS the gain edge, it does not keep the older one" begin
        # "Where you got it" is where the track you still hold at CPA began — not where an earlier
        # one did that you then lost. (Reading it the other way makes the inbound edge the range of
        # the first lucky detection ever, which is a fading draw and not a tracker's number.)
        r3 = Entity(:r3, :radar; pos = Vec3(0.0, 0.0, 0.0),
                    comp = Dict{Symbol,Any}(:track_drop_looks => 3))
        EWSim._track_look!(r3, true, 20000.0, -300.0)   # a lucky far detection…
        for _ in 1:3; EWSim._track_look!(r3, false, 19000.0, -300.0); end   # …lost again
        @test r3.comp[:trk_gain_range] == 20000.0
        EWSim._track_look!(r3, true, 12000.0, -300.0)   # the track that actually holds
        @test r3.comp[:trk_gain_range] == 12000.0       # ⇐ overwritten, deliberately
    end
end

@testset "⭐⭐⭐ THE SHIPPED TRACKER **IS** THE GATE-0 RULE — on wire A, to the bit (53 gate 2)" begin
    # ⚠ WIRE A, and every number below is quoted with it: x0 = −15 km, 200 s, σ = 4 m², F = 8,
    # `revisit_s` = 0.1, `N`* = 3, seeds (53, …). The metres are a joint property of the tail lobe
    # AND the tracker (gate-0 §2.14) — the SIGN is physics, the SIZE is not.
    mktempdir() do dir
        flights = Dict{Tuple{Int,Any},Any}()
        for (seed, gain) in ((53, nothing), (53, "50.0"), (5, "20.0"))
            looks, tl, _ = _trk_fly(dir, seed, gain)
            flights[(seed, gain)] = (looks, tl)
            inb, outb = _trk_split(looks)
            gr, gl = _trk_offline_edge(reverse(inb), 3)     # MIRRORED: the same function both ways
            lr, ll = _trk_offline_edge(outb, 3)
            @test tl["radar1.track_gain_range_m"] == gr     # ⇐ NOT `≈`. Same rule ⇒ same look ⇒
            @test tl["radar1.track_loss_range_m"] == lr     #    the identical Float64 range.
            @test tl["radar1.track_gain_look"] == gl
            @test tl["radar1.track_loss_look"] == ll
            @test tl["radar1.track_asym_m"] == lr - gr
        end

        # ⭐⭐ THE EXTERNAL ANCHOR: `docs/plans/slice53.md` §2.9's per-seed table, printed by a
        # different program (`p3b_perseed.jl`) before any of this code existed. Seed 53 is the row
        # that goes NEGATIVE at the null, which is the useful one to pin: it says the gauge is a
        # noisy difference of two edges and not a quantity built to be positive.
        looks1,  t1  = flights[(53, nothing)]
        looks50, t50 = flights[(53, "50.0")]
        @test t1["radar1.track_asym_m"] ≈ -531.8 atol = 0.1     # §2.9, seed 53, G = 1
        @test t50["radar1.track_asym_m"] ≈ +6244.0 atol = 0.1   # §2.9, seed 53, G = 50
        @test t1["radar1.track_gain_range_m"] ≈ 7078.0983 atol = 1e-3   # §2.15's invariant list

        # ⭐⭐⭐ AND THE MECHANISM IN ONE TOOTH: the tail lobe is exactly 1.0 on the whole FORWARD
        # hemisphere, so the INBOUND edge is bit-identical at every `G` while the OUTBOUND one moves.
        # That is what makes the gauge a PAIRED measurement (gate-0 §2.15 §0 measured
        # `max |in_G − in_1|` = 0.000000e+00 over 824 flights) — and it is the whole of the slice's
        # claim: no scalar `rcs_m2` can move one leg of a pass without moving the other.
        @test t50["radar1.track_gain_range_m"] == t1["radar1.track_gain_range_m"]
        @test t50["radar1.track_gain_look"]    == t1["radar1.track_gain_look"]
        @test t50["radar1.track_loss_range_m"]  > t1["radar1.track_loss_range_m"]
        @test t50["radar1.track_asym_m"]        > t1["radar1.track_asym_m"]
        # …and the two flights are the SAME REALISATION up to the detections the lobe adds: the
        # target flies an identical trajectory (`rcs_aspect` is in the detection, never the
        # dynamics), so the inbound detection bitmap is identical look for look.
        ki = argmin([u[2] for u in looks1])
        @test [u[1] for u in looks1[1:ki]] == [u[1] for u in looks50[1:ki]]
    end
end

@testset "the ASYMMETRY key ships ONLY when BOTH edges exist — presence decides (53 gate 2)" begin
    # 0.0 is a LEGITIMATE value of this gauge — it is what a fore/aft symmetric target reads — so a
    # sentinel or a `.get(k, 0.0)` default would be indistinguishable from the lesson's own null on
    # an instrument that has simply not finished. Slice 49 shipped a defaulted zero that read as a
    # passed test; slice 50 ruled that where the null equals the default, PRESENCE decides.
    mktempdir() do dir
        p = joinpath(dir, "early.yaml"); write(p, _trk_yaml())
        sc = load_scenario(p); w, subs, dt = sc.world, sc.subs, sc.dt_physics
        for _ in 1:200; tick!(w, subs, dt); end        # 0.2 s: the first look has barely happened
        tl = w.env[:telemetry]
        @test !haskey(tl, "radar1.track_asym_m")       # ⇐ ABSENT, not zero
        @test tl["radar1.track_loss_range_m"] == -1.0  # …and the edge itself says NOT YET
        @test tl["radar1.track_loss_look"] == -1.0
        @test tl["radar1.track_closing"] === true      # still coming in
        # The gain edge exists as soon as a track opens, and it is a real range and not the sentinel.
        for _ in 1:20_000; tick!(w, subs, dt); end
        @test w.env[:telemetry]["radar1.track_gain_range_m"] > 0.0
        @test !haskey(w.env[:telemetry], "radar1.track_asym_m")   # still only ONE edge
    end
end

@testset "the GIVE-UP RULE is LEARNED and VALIDATED at LOAD (slice 53 gate 2)" begin
    mktempdir() do dir
        good = joinpath(dir, "good.yaml"); write(good, _trk_yaml())
        c = load_scenario(good).world.entities[:radar1].comp
        @test c[:track_drop_looks] == 3
        @test c[:track_drop_looks] isa Int             # a COUNT of looks, not an SI Float64
        # Absent ⇒ absent. An unknown `radar:` key is dropped silently by the loader (gate-0 P6a
        # found that on the `target:` block), so "the key is learned at all" is a tooth, not a
        # tautology — without it a scenario could author a give-up rule and fly with none.
        p0 = joinpath(dir, "none.yaml"); write(p0, _trk_yaml(drop = nothing))
        @test !haskey(load_scenario(p0).world.entities[:radar1].comp, :track_drop_looks)

        # ⚠⚠ REFUSED WITHOUT A POSITIVE `revisit_s`, and this is the slice's own §2.14 trap turned
        # into a load error: the rule is counted in LOOKS, so with a look every tick "3 missed
        # looks" is "3 missed INTEGRATION STEPS" — a give-up TIME of 3·dt that moves when `dt` does.
        # Slice 51 died on a boundary that flipped at half `dt`; this refuses the configuration that
        # would build one. ⚠ THE MESSAGE IS PART OF THE TOOTH (gate 1's rule): `ErrorException`
        # alone would also pass on a YAML parse failure, which is a refusal for the wrong reason.
        p1 = joinpath(dir, "norevisit.yaml"); write(p1, _trk_yaml(revisit = nothing))
        @test_throws "needs a positive `revisit_s`" load_scenario(p1)
        p2 = joinpath(dir, "zerorevisit.yaml"); write(p2, _trk_yaml(revisit = "0.0"))
        @test_throws "needs a positive `revisit_s`" load_scenario(p2)
        # A depth below 1 has no reading — the drop would precede the miss.
        for bad in ("0", "-2")
            p = joinpath(dir, "bad$bad.yaml"); write(p, _trk_yaml(drop = bad))
            @test_throws "must be ≥ 1" load_scenario(p)
        end
        # ⚠ AND REFUSED ON A `:cfar` WIRE, where `observe!` takes the PROFILE path and the tracker
        # is not wired at all. A key nothing reads is the `speed` (19) / handover-bias (36) bug, and
        # the two-test rule's only outright kill — so it cannot be authorable there either.
        p3 = joinpath(dir, "cfar.yaml"); write(p3, _trk_yaml(cfar = true))
        @test_throws "POINT detector's tracker only" load_scenario(p3)
        # …while the same CFAR wire WITHOUT the rule still loads, which is what makes the refusal
        # above a statement about the key rather than about the fidelity.
        p4 = joinpath(dir, "cfar_ok.yaml"); write(p4, _trk_yaml(cfar = true, drop = nothing))
        @test load_scenario(p4) isa EWSim.Scenario
    end
end

@testset "⚠⚠ A LIVE DRAG INVALIDATES THE LATCHED EDGES, IN THE CORE (slice 53 gate 2)" begin
    # Slice 49 ruled that a live slider drag invalidates a latch as a Reset does; slice 50 ruled
    # that a latched INSTANT may not re-arm mid-flight. Both put the remedy in the CLIENT, because
    # both latched in the client. This one latches in the CORE and ships as a wire key — and a
    # gate-3 verifier reads the WIRE, not the HUD. A stale `track_asym_m` would be read as a live
    # measurement by a headless proof that never draws a pixel.

    @testset "the flag is CONSUMED at the next look, and only the LATCHES go" begin
        radar = Entity(:r1, :radar; pos = Vec3(0.0, 0.0, 0.0),
                       comp = Dict{Symbol,Any}(:track_drop_looks => 3))
        EWSim._track_look!(radar, true,  9000.0, -300.0)     # inbound: the gain edge
        EWSim._track_look!(radar, true,  8000.0, -300.0)
        EWSim._track_look!(radar, true,  7000.0, +300.0)     # CPA, then the outbound run
        for _ in 1:3; EWSim._track_look!(radar, false, 8000.0, +300.0); end
        @test radar.comp[:trk_gain_range] == 9000.0
        @test radar.comp[:trk_loss_range] == 7000.0
        @test !get(radar.comp, :trk_pass_dirty, false)

        w = World(; seed = 1)
        w.entities[:r1] = radar
        EWSim._mark_track_dirty!(w)
        @test radar.comp[:trk_dirty]
        @test radar.comp[:trk_gain_range] == 9000.0          # ⇐ NOT cleared by the mark itself…
        EWSim._track_look!(radar, false, 9000.0, +300.0)     # …but by the next LOOK, which is where
        @test !haskey(radar.comp, :trk_gain_range)           #   the instrument next speaks.
        @test !haskey(radar.comp, :trk_loss_range)
        @test !haskey(radar.comp, :trk_loss_look)
        @test !haskey(radar.comp, :trk_post_cpa_det)
        @test radar.comp[:trk_pass_dirty]                    # ⇐ and it stays true until a Reset
        @test !radar.comp[:trk_dirty]                        # ⇐ consumed once, not every look
        # ⭐ THE SPLIT SLICE 50 NAMED: the LATCH belongs to the setting, the LIVE STATE belongs to the
        # tick. Keeping the live lines running is what makes the drag a teaching instrument at all.
        @test radar.comp[:trk_look] == 7
        @test radar.comp[:trk_past_cpa]
        @test radar.comp[:trk_misses] == 3

        # A post-CPA drag ends the pass's measurement for good — the gain edge cannot be re-declared
        # on the outbound leg — which is exactly slice 50's "Reset to measure" state, reached by the
        # wire rather than by a HUD word.
        EWSim._track_look!(radar, true, 10000.0, +300.0)
        for _ in 1:3; EWSim._track_look!(radar, false, 11000.0, +300.0); end
        @test radar.comp[:trk_loss_range] == 10000.0         # a NEW loss edge, under the new setting
        @test !haskey(radar.comp, :trk_gain_range)           # …with nothing to difference it against
    end

    @testset "⭐ THE SEAM IS ACTUALLY CALLED — `set_param` marks the tracker (the anti-P6a shape)" begin
        # A hook nothing calls is the same defect as a key nothing reads (gate-0 P6a), and it is
        # invisible to every test that drives `_track_look!` directly. So the drag goes through the
        # SERVER's own command path, exactly as a slider does.
        mktempdir() do dir
            p = joinpath(dir, "knobbed.yaml")
            write(p, _trk_yaml(gain = "20.0") *
                     "knobs:\n  - {target: tgt1, key: rcs_tail_gain, min: 1.0, max: 50.0, label: \"G\"}\n")
            srv = EWSim.Server(load_scenario(p); path = p)
            w = srv.scn.world
            for _ in 1:2000; tick!(w, srv.scn.subs, srv.scn.dt_physics); end
            @test !get(w.entities[:radar1].comp, :trk_dirty, false)
            EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "tgt1",
                                            :key => "rcs_tail_gain", :value => 50.0))
            @test w.entities[:tgt1].comp[:rcs_tail_gain] == 50.0
            @test w.entities[:radar1].comp[:trk_dirty]        # ⇐ THE SEAM
            for _ in 1:200; tick!(w, srv.scn.subs, srv.scn.dt_physics); end
            @test w.env[:telemetry]["radar1.track_pass_dirty"] === true
            @test !haskey(w.env[:telemetry], "radar1.track_asym_m")
            # …and a RESET clears it, because `reset` RELOADS the scenario — fresh entities, fresh
            # comp bags. That is why the tracker needs no reset hook of its own (`_reload!`,
            # server.jl), and the tooth is here so a future change to that path is caught.
            EWSim.handle_command!(srv, Dict(:type => "reset"))
            @test !haskey(srv.scn.world.entities[:radar1].comp, :trk_pass_dirty)
            @test srv.scn.world.entities[:tgt1].comp[:rcs_tail_gain] == 20.0   # the AUTHORED value
        end
    end

    @testset "a wire with NO tracker is untouched by the mark" begin
        # `_mark_track_dirty!` runs on every `set_param` of every scenario ever shipped, so it must
        # find nothing to mark on all of them.
        mktempdir() do dir
            p = joinpath(dir, "notracker.yaml"); write(p, _trk_yaml(drop = nothing))
            w = load_scenario(p).world
            EWSim._mark_track_dirty!(w)
            @test !any(startswith(String(k), "trk_") for k in keys(w.entities[:radar1].comp))
        end
    end
end

# ══════════════════════════════════════════════════════════════════════════════════════════════
# SLICE 53 GATE 3 — THE SHOWCASE WIRE, ITS MARKER, AND THE LADDER IT IS QUOTED ON.
#
# Gate 2 shipped the tracker against a probe-built wire. Gate 3 authors it as `slice53_taillobe.yaml`
# and hands a student one slider. Everything a HUD line, a scenario header or a verifier CONSTANT
# quotes about that file is pinned here, so an edit to the YAML breaks in the core rather than in a
# screenshot (the slice-49 posture).
#
# ⚠ THE SEED IS 250 AND IT WAS CHOSEN BY A RULE FIXED BEFORE THE FLIGHTS (probe `g3_seed.jl`,
# gate-3 log): monotone over the coarse ladder; both authored drags moving by ≥ 1 km; and — the
# discriminator — an OPENING reading above F3's attributability bar of max-null × 3 = 2905 m. It is
# the only one of the 8 gate-0 seeds that passes. ⚠⚠ Seed 53, the obvious name-matching pick, FAILS:
# it opens at +1820 m, 1085 m BELOW the bar it would have to be attributable against.
# ══════════════════════════════════════════════════════════════════════════════════════════════

const _SCEN53 = normpath(joinpath(@__DIR__, "..", "..", "scenarios", "slice53_taillobe.yaml"))

# Fly the SHIPPED file, optionally overriding the tail gain. 100 s is chosen against a measurement,
# not rounded: the last edge this file asserts is declared at look 950 (`G` = 50), so 1000 looks
# leaves 50 of margin — P7a §C's arm-specific censoring check, at the length the test actually flies.
function _fly53(G; secs = 100.0)
    sc = load_scenario(_SCEN53)
    w, subs, dt = sc.world, sc.subs, sc.dt_physics
    G === nothing || (w.entities[:tgt1].comp[:rcs_tail_gain] = G)
    r = w.entities[:radar1]
    gl = -1; asp_gain = NaN
    for _ in 1:round(Int, secs / dt)
        prev = get(r.comp, :next_look_t, 0.0)
        tick!(w, subs, dt)
        if get(r.comp, :next_look_t, 0.0) != prev
            ngl = Int(get(w.env[:telemetry], "radar1.track_gain_look", -1.0))
            # The aspect AT THE LOOK THE GAIN EDGE WAS DECLARED — sampled on the transition, because
            # the edge is latched and the aspect is not.
            if ngl != gl && ngl > 0
                gl = ngl
                asp_gain = w.env[:telemetry]["radar1.target_aspect_deg"]
            end
        end
    end
    tel = w.env[:telemetry]
    (gain = tel["radar1.track_gain_range_m"], gl = Int(tel["radar1.track_gain_look"]),
     loss = tel["radar1.track_loss_range_m"], ll = Int(tel["radar1.track_loss_look"]),
     asym = get(tel, "radar1.track_asym_m", nothing), asp_gain = asp_gain,
     nlook = Int(tel["radar1.track_look"]), pos = copy(w.entities[:tgt1].pos),
     dirty = tel["radar1.track_pass_dirty"], scn = sc, world = w)
end

@testset "slice 53 gate 3 — the showcase wire" begin
    @testset "the scenario is what every downstream number was measured on" begin
        sc = load_scenario(_SCEN53)
        @test sc isa EWSim.Scenario
        @test sc.name == "slice53_taillobe"
        tgt = sc.world.entities[:tgt1]
        @test tgt.comp[:rcs_tail_gain] == 20.0        # the AUTHORED opening — mid-lesson
        @test tgt.comp[:rcs_fineness] == 8.0          # FIXED, not a knob: the shape is held still
        @test tgt.comp[:rcs_m2] == 4.0                # …and still means the BROADSIDE peak
        @test !haskey(tgt.comp, :maneuver)            # a STRAIGHT pass: the tracker assumes ONE CPA
        rad = sc.world.entities[:radar1]
        # ⚠⚠ THE RULE THE METRES ARE A JOINT PROPERTY OF (§2.14). Change either of these two and
        # every number in the YAML header, the HUD and the verifier is a measurement of something
        # else — so they are pinned here rather than left to the file.
        @test rad.comp[:track_drop_looks] == 3
        @test rad.comp[:revisit_s] == 0.1
        @test rad.comp[:swerling] == 1                # what makes the NULL arm read noise, not zero
        # EXACTLY ONE LIVE KNOB (convention 9), and both endpoints are the measured ones.
        @test length(sc.knobs) == 1
        @test sc.knobs[1].key === :rcs_tail_gain && sc.knobs[1].target === :tgt1
        @test sc.knobs[1].min == 1.0 && sc.knobs[1].max == 50.0
        # ⚠ LINEAR, and NOT for slice 49's or 52's reason — the half-effect of a 1→50 domain sits at
        # G = 20.2, which is 39.2 % of a LINEAR drag and 76.8 % of a LOG one. `log` is a real field
        # on `Knob` and seven shipped scenarios author it, so this is a CHOICE and not an absence.
        @test !sc.knobs[1].log
        @test length(sc.knobs[1].label) ≤ 110         # the HUD width budget (slice 32's shots)
        @test sc.world.fidelity[:propagation] === :free_space
        # ⚠ CONVENTION 14: a verifier's STEPS must be a multiple of `emit_every` or it hangs
        # SILENTLY. Pin the value the .gd scripts divide by, so an edit to one breaks here first.
        @test sc.emit_every == 16
        @test sc.dt_physics == 1.0e-3
        @test sc.world.entities[:tgt1].pos == Vec3(-15000.0, 0.0, 5000.0)
        @test sc.world.entities[:tgt1].vel == Vec3(300.0, 0.0, 0.0)
    end

    @testset "⭐⭐ the view marker is the PAIR, and it takes the HUD without taking the button" begin
        sc = load_scenario(_SCEN53)
        info = EWSim._tail_view_info(sc.world)
        @test info !== nothing
        @test info[:tail_view] === true
        @test info[:tail_target] == "tgt1"
        @test info[:tail_observer] == "radar1"
        # ⚠ …AND SLICE 49's MARKER IS STILL RAISED, DELIBERATELY. It owns the BUTTON job on this
        # view — dropping the `free_space ↔ two_ray` toggle, which is the right drop here for slice
        # 49's own reason (multipath is a SECOND way for a target to vanish). The client checks
        # `tail_view` FIRST for the HUD and leaves the button where it is.
        asp = EWSim._aspect_view_info(sc.world)
        @test asp !== nothing && asp[:aspect_view] === true &&
              asp[:aspect_target] == "tgt1" && asp[:aspect_observer] == "radar1"
        # …and the handshake carries BOTH, which is what the client actually parses.
        f = EWSim.scenario_frame(EWSim.Server(sc; path = _SCEN53))
        @test f[:tail_view] === true && f[:aspect_view] === true
        @test f[:tail_target] == "tgt1" && f[:tail_observer] == "radar1"
    end

    @testset "HALF A PAIR IS NOT A MARKER — both halves, both directions" begin
        mktempdir() do dir
            # A TAIL LOBE WITH NO TRACKING RADAR. Slice 49's wire is exactly this once a gain is
            # injected: a shaped, tail-lobed target and a radar that keeps no track. It has an
            # asymmetry; it has none THIS view can quote, and every `track_*` line would render off
            # `.get(k, 0.0)` — "GOT IT 0.00 km @ look #0", six defaulted numbers on a green run.
            p1 = joinpath(dir, "notracker.yaml")
            write(p1, _trk_yaml(gain = "20.0", drop = nothing))
            @test EWSim._tail_view_info(load_scenario(p1).world) === nothing
            # A TRACKING RADAR WITH NO TAIL LOBE. The tracker is generic — a plain fly-past wire may
            # legitimately author it — and its two edges are then a fading-noise difference with no
            # lesson behind them. The block's headline would claim an asymmetry nothing produced.
            p2 = joinpath(dir, "nogain.yaml")
            write(p2, _trk_yaml(gain = nothing, drop = "3"))
            @test EWSim._tail_view_info(load_scenario(p2).world) === nothing
            # …and BOTH present raises it, which is the paired control for the two above.
            p3 = joinpath(dir, "both.yaml")
            write(p3, _trk_yaml(gain = "20.0", drop = "3"))
            @test EWSim._tail_view_info(load_scenario(p3).world)[:tail_view] === true
        end
        # ⭐ THE GATE IS PRESENCE, NEVER THE VALUE — slice 50's rule (the lesson's NULL and a dead
        # instrument's DEFAULT must not read the same). The showcase's headline drag is G = 20 → 1,
        # and `set_param` writes the comp bag IN PLACE, so a marker gated on `G > 1` would blank on
        # exactly the arm that proves the null. Driven through the SERVER's own command path, which
        # is the one a slider uses.
        srv = EWSim.Server(load_scenario(_SCEN53); path = _SCEN53)
        EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "tgt1",
                                        :key => "rcs_tail_gain", :value => 1.0))
        @test srv.scn.world.entities[:tgt1].comp[:rcs_tail_gain] == 1.0
        @test EWSim._tail_view_info(srv.scn.world)[:tail_view] === true
    end

    @testset "…and NO OTHER SHIPPED WIRE raises it" begin
        # An enumerated carrier SET rather than an `isempty`, for the reason slices 36–50 each
        # rediscovered: an `isempty` goes on passing forever while quietly ceasing to say anything
        # the moment a second wire is added.
        base = normpath(joinpath(@__DIR__, "..", "..", "scenarios"))
        carriers = String[]
        for f in sort(readdir(base))
            endswith(f, ".yaml") || continue
            EWSim._tail_view_info(load_scenario(joinpath(base, f)).world) === nothing ||
                push!(carriers, f)
        end
        @test carriers == ["slice53_taillobe.yaml"]
    end

    @testset "⭐⭐⭐ THE LADDER — the anchors every HUD line and verifier constant is quoted from" begin
        a1  = _fly53(1.0)
        a20 = _fly53(nothing)        # the AUTHORED wire, untouched — G = 20
        a50 = _fly53(50.0)
        # ⭐⭐⭐ THE INBOUND EDGE IS IDENTICAL TO THE BIT AT EVERY SETTING, WHICH IS THE WHOLE PAIRED
        # CONSTRUCTION. `===` and not `≈`: the kernel's lobe is `max(0, −cos θ)²`, identically ZERO
        # on the forward hemisphere, so at the look the track opens the multiplier is exactly 1.0
        # and no `G` can reach it. Gate 0 measured `max |in_G − in_1|` = 0.000000e+00 over 824
        # flights; this is that statement on the shipped file.
        @test a1.gain === a20.gain === a50.gain
        @test a1.gl == a20.gl == a50.gl == 375
        # …and the reason, IN ONE NUMBER: the edge is declared at an aspect of 52.7°, forward of
        # broadside. ⚠ If a future edit moves the geometry so this passes 90°, the gauge stops being
        # a paired difference and becomes a difference of two things the slider moves.
        @test a1.asp_gain < 90.0
        @test a1.asp_gain ≈ 52.746902 atol = 1.0e-5
        # EXTERNAL ANCHOR (convention 11): 6243.9596 m is `docs/plans/slice53.md` §4.2's own printed
        # inbound-gain invariant for seed 250, produced by a different program on a different day.
        @test a1.gain ≈ 6243.9596 atol = 1.0e-3
        # THE THREE CELLS THE SHOWCASE IS AUTHORED AROUND — the null it drags back to, the opening,
        # and the ceiling. ⚠ The null is NOT zero and is not asserted as zero: identical σ on the
        # two legs still means different Swerling-1 draws, so it is fading noise (+583 m here, and
        # −658 … +968 m over the 8 gate-0 seeds).
        @test a1.asym  ≈ 583.1126641439   atol = 1.0e-6
        @test a20.asym ≈ 3516.4676010084  atol = 1.0e-6
        @test a50.asym ≈ 8113.9608866603  atol = 1.0e-6
        @test (a1.ll, a20.ll, a50.ll) == (657, 781, 950)
        @test a1.loss ≈ 6827.0723124844 atol = 1.0e-6
        # ⭐⭐ AND THE GAUGE IS A DIFFERENCE OF WIRE VALUES, NOT A THIRD MEASUREMENT — the identity a
        # client must never recompute (convention 13, and the one that keeps the HUD and the
        # verifier reading ONE quantity).
        for a in (a1, a20, a50)
            @test a.asym === a.loss - a.gain
        end
        # BOTH REQUIRED DRAGS MOVE, by the margins the ceiling was chosen on (§2.15 §5).
        @test a50.asym - a20.asym > 4000.0        # 20 → 50, the only all-seed-clean interval
        @test a20.asym - a1.asym  > 2900.0        # 20 → 1, back to the null
        # …and MONOTONE across them, which is the filter that killed `k` (28), `ω_n` (40) and
        # `σ_seek` (25) as showcase sliders.
        @test a1.asym < a20.asym < a50.asym
        # ⭐ THE TRAJECTORY IS BYTE-IDENTICAL ACROSS THE WHOLE SLIDER — slice 49's sharpest tooth,
        # one key over. The shape is read by the SEEING and by nothing else, so the slider changes
        # nothing about the flight and everything about what comes back.
        @test a1.pos == a50.pos
        # NOT CENSORED at the length this file flies: the last edge sits 50 looks inside the window
        # against a give-up depth of 3. ⚠ ARM-SPECIFIC (slice 52's trap) — asserted at the arm whose
        # edge is LATEST, not at the arm that happens to be convenient.
        @test a50.nlook - a50.ll ≥ 3 * a50.scn.world.entities[:radar1].comp[:track_drop_looks]
        @test a50.nlook == 1000
        # A FRESH LOAD IS NEVER DIRTY — the baseline the drag teeth below are read against.
        @test a1.dirty === false && a20.dirty === false && a50.dirty === false
    end

    @testset "⭐⭐ A DRAG PAST CLOSEST APPROACH ENDS THE PASS — on the SHIPPED wire, through the SERVER" begin
        # ⚠⚠ THIS IS THE PATH GATE 2's FOLLOW-UP SHIPPED FOR, AND IT IS ALSO THE ONE `CLAUDE.md`
        # says no gate-3 proof has ever exercised (*no gate-3 proof DRAGS a slider*, slice 52). The
        # `.gd` verifier drags it too; this is the core-side half, on the file a student opens.
        srv = EWSim.Server(load_scenario(_SCEN53); path = _SCEN53)
        w, subs, dt = srv.scn.world, srv.scn.subs, srv.scn.dt_physics
        # Fly to t = 60 s — PAST closest approach (t = 50 s, x = 0) and past the gain edge at look
        # 375. Both edges exist here; the loss edge does not yet.
        for _ in 1:60_000; tick!(w, subs, dt); end
        @test w.entities[:radar1].comp[:trk_past_cpa]
        @test haskey(w.entities[:radar1].comp, :trk_gain_range)
        @test w.env[:telemetry]["radar1.track_pass_dirty"] === false
        EWSim.handle_command!(srv, Dict(:type => "set_param", :target => "tgt1",
                                        :key => "rcs_tail_gain", :value => 50.0))
        for _ in 1:40_000; tick!(w, subs, dt); end
        tel = w.env[:telemetry]
        # ⭐⭐⭐ THE ASSERTION, AND IT IS ABOUT AN ABSENT KEY. The gain edge was deleted at the next
        # look, and `:trk_past_cpa` is NEVER cleared — so it can never be re-declared on the
        # outbound leg, and `track_asym_m` is gone for the rest of the pass. That is slice 50's
        # "Reset to measure" reached through the WIRE, where a headless verifier can read it,
        # instead of through a HUD word, where one cannot.
        @test tel["radar1.track_pass_dirty"] === true
        @test !haskey(tel, "radar1.track_asym_m")
        @test tel["radar1.track_gain_range_m"] == -1.0     # the NOT-YET sentinel, not a stale range
        @test tel["radar1.track_gain_look"] == -1.0
        # ⭐ …WHILE THE LIVE LINES KEEP RUNNING. The latch belongs to the SETTING; alive / misses /
        # look / leg belong to the TICK, and keeping them is what makes the slider a teaching
        # instrument rather than a screen that goes blank when you touch it.
        @test tel["radar1.track_look"] == 1000.0
        @test tel["radar1.track_closing"] === false
        @test haskey(tel, "radar1.track_misses") && haskey(tel, "radar1.track_alive")
        # …and the RULE keys still ship beside them, because a client must never be able to print a
        # metre without them (§2.14).
        @test tel["radar1.track_drop_looks"] == 3.0 && tel["radar1.track_revisit_s"] == 0.1
    end
end

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# SLICE 54 GATE 1 — the RANGE-GATED half of the give-up tracker: the four pure pieces that decide
# whether a look DETECTED THIS TRACK, over a picture of cells instead of one boolean over truth.
#
# ⚠⚠ THE EXTERNAL ANCHOR OF THIS SECTION IS `docs/plans/slice54.md` §2.5.1, which ruled the gate
# rule BEFORE the tracker was written and computed its value by hand on paper:
#     |ṙ|·revisit_s/Δr = 300·0.1/149.896 = 0.2001 cells → ceil = 1.
# Every probe P3..P7 then flew that gate, and §2.8's shipped curve is what these pieces must
# reproduce. A tooth that only re-derives the formula from the same formula proves nothing
# (convention 11), so the anchors below are the PLAN's arithmetic, not this code's.
# ═════════════════════════════════════════════════════════════════════════════════════════════════

@testset "slice54 gate1 — the range-gated give-up tracker (pure)" begin
    c_light = 299_792_458.0
    dr_1mhz = c_light / (2 * 1.0e6)              # 149.896... m — the shipped wire's range cell
    @test isapprox(dr_1mhz, 149.896229, atol = 1e-5)

    @testset "α/β are PINNED — editing them changes every number in the plan" begin
        # ⚠⚠ NOT a tautology: these constants set the SCALE of §2.8's answer (gate-0 §2.8.2 — the
        # count of looks is a joint property of the gate and the filter; only the DIRECTION is
        # physics). A silent edit would leave the shipped curve unreproducible from the ledger, so
        # the values are nailed to the ones every probe flew.
        @test TRACK_ALPHA == 0.5
        @test TRACK_BETA  == 0.1
        @test TRACK_GATE_MAX_CELLS == 8
    end

    @testset "track_gate_cells — the PRE-REGISTERED rule, on the plan's own arithmetic" begin
        # THE ANCHOR: §2.5.1's hand computation — the number the slice ruled it would ship.
        @test track_gate_cells(300.0, 0.1, dr_1mhz) == 1
        # …and the SIGN of the rate cannot matter: opening and closing look alike to a window.
        @test track_gate_cells(-300.0, 0.1, dr_1mhz) == 1

        # ⭐ INDEPENDENT RECOMPUTE at a rate where the rule is NOT its own floor: 3000 m/s spans
        # 3000·0.1 = 300 m = 2.0014 cells → 3.
        @test isapprox(3000.0 * 0.1 / dr_1mhz, 2.0014, atol = 1e-4)   # the recompute, shown
        @test track_gate_cells(3000.0, 0.1, dr_1mhz) == 3

        # ⭐⭐ THE `revisit_s` TOOTH — the whole reason the gate is COMPUTED and not hardcoded. The
        # SAME physical motion on a radar that revisits twice as fast needs HALF the window, so a
        # gate frozen at the shipped "1 cell" would silently be a different tracker on that wire.
        @test track_gate_cells(3000.0, 0.05, dr_1mhz) == 2      # 150 m = 1.0007 cells → 2
        @test track_gate_cells(3000.0, 0.2,  dr_1mhz) == 5      # 600 m = 4.0031 cells → 5
        # …and the same motion in a FINER range cell needs MORE cells (Δr halves at 2 MHz).
        @test track_gate_cells(3000.0, 0.1, c_light / (2 * 2.0e6)) == 5

        # The floor: a track with no rate estimate yet must still be able to associate at all.
        @test track_gate_cells(0.0, 0.1, dr_1mhz) == 1
        # The cap, which bounds the gate↔rate feedback path.
        @test track_gate_cells(1.0e9, 0.1, dr_1mhz) == TRACK_GATE_MAX_CELLS
        @test track_gate_cells(Inf,   0.1, dr_1mhz) == 1        # non-finite → the safe floor
        # Monotone non-decreasing in |rdot| — a faster track never gets a NARROWER window.
        @test issorted([track_gate_cells(v, 0.1, dr_1mhz) for v in 0.0:137.0:12_000.0])

        # ⚠ Convention 5: a live knob can never crash a tick. Every degenerate input floors.
        for bad in ((300.0, 0.0, dr_1mhz), (300.0, 0.1, 0.0), (300.0, -0.1, dr_1mhz),
                    (300.0, 0.1, -1.0), (NaN, 0.1, dr_1mhz), (300.0, NaN, dr_1mhz),
                    (300.0, 0.1, NaN))
            @test track_gate_cells(bad...) == 1
        end

        # ⭐⭐⭐ THE CAP NEVER BINDS ON THE SHIPPED WIRE — so §2.8's curve is the UNCAPPED rule's and
        # the cap is a guard, not a tuning constant that quietly set the slice's answer.
        @test all(track_gate_cells(v, 0.1, dr_1mhz) == 1 for v in -300.0:5.0:300.0)
    end

    @testset "track_associate — NEAREST inside the gate, and it is not the strongest" begin
        gate = 1.0 * dr_1mhz                     # the shipped ±1 cell
        # NEAREST, not first and not last: 1050 is 50 m from the prediction, 900 is 100 m.
        @test track_associate(1000.0, [900.0, 1050.0], 200.0) == 2
        # The gate EXCLUDES what lies outside it — that look is a MISS for this track.
        @test track_associate(1000.0, [800.0, 1300.0], gate) == 0
        # The BOUNDARY is inclusive (`d ≤ g`); an off-by-one here is a different tracker.
        # ⚠ The "just outside" case is probed a whole METRE out, not by `nextfloat`: at a range of
        # 1000 m the ulp is ~1e-13, so `1000 + nextfloat(gate)` rounds back to `1000 + gate` and the
        # tooth would test nothing. A tooth that cannot fail is not a tooth (convention 11).
        @test track_associate(1000.0, [1000.0 + gate], gate) == 1
        @test track_associate(1000.0, [1000.0 + gate + 1.0], gate) == 0
        @test track_associate(1000.0, [1000.0 - gate], gate) == 1        # …symmetric, both sides
        @test track_associate(1000.0, [1000.0 - gate - 1.0], gate) == 0
        # Ties → the LOWER index, so a replay is deterministic in the caller's cell order.
        @test track_associate(1000.0, [950.0, 1050.0], 100.0) == 1
        # Nothing detected at all → 0, which the caller also reads as a MISS.
        @test track_associate(1000.0, Float64[], gate) == 0
        # Degenerate inputs floor to "no association" rather than throwing.
        @test track_associate(NaN, [1000.0], gate) == 0
        @test track_associate(1000.0, [1000.0], NaN) == 0
        @test track_associate(1000.0, [1000.0], -1.0) == 0
    end

    @testset "track_reopen — STRONGEST, ungated, and that asymmetry IS the lesson" begin
        @test track_reopen([1.0, 5.0, 3.0]) == 2
        @test track_reopen(Float64[]) == 0
        @test track_reopen([5.0, 5.0]) == 1                     # ties → lower index
        @test track_reopen([-3.0, -1.0]) == 2                   # works below unity power
        # ⭐⭐ THE CONTRAST TOOTH, in one place: on the SAME picture a live track and a dead one
        # choose DIFFERENT cells. Prediction 1000 m; a quiet near cell at 1010 m and a loud far one
        # at 5000 m. A live track keeps the near one; a dead one is captured by the loud one — and
        # that is the whole two-sidedness of patience, in three lines.
        rngs = [1010.0, 5000.0]; pows = [2.0, 90.0]
        @test track_associate(1000.0, rngs, 1.0 * dr_1mhz) == 1
        @test track_reopen(pows) == 2
    end

    @testset "track_ab_step — the α–β filter, and β's units are the trap" begin
        # COAST (no measurement): move to the prediction, keep the rate. INDEPENDENT recompute.
        r1, v1 = track_ab_step(1000.0, -300.0, 0.1, nothing)
        @test isapprox(r1, 1000.0 + (-300.0) * 0.1, atol = 1e-12)     # = 970.0
        @test v1 == -300.0
        # UPDATE, hand-computed against α = 0.5, β = 0.1, revisit 0.1:
        #   pred  = 1000 + (-300)(0.1)  = 970;   resid = 990 − 970 = 20
        #   r′    = 970 + 0.5·20        = 980
        #   rdot′ = −300 + (0.1/0.1)·20 = −280
        r2, v2 = track_ab_step(1000.0, -300.0, 0.1, 990.0)
        @test isapprox(r2, 980.0,  atol = 1e-12)
        @test isapprox(v2, -280.0, atol = 1e-12)

        # ⭐⭐ β IS DIVIDED BY THE REVISIT BECAUSE IT CORRECTS A RATE FROM A POSITION. The same
        # residual seen twice as fast implies twice the rate error; applied bare, a faster-revisiting
        # radar would silently run a different filter (gate-0 §3.1).
        #   at revisit 0.05: pred = 985; resid = 5;  rdot′ = −300 + (0.1/0.05)·5 = −290
        r3, v3 = track_ab_step(1000.0, -300.0, 0.05, 990.0)
        @test isapprox(r3, 985.0 + 0.5 * 5.0, atol = 1e-12)           # = 987.5
        @test isapprox(v3, -290.0, atol = 1e-12)
        # …stated as the INVARIANT rather than as two more numbers: the rate correction per unit
        # residual scales as 1/revisit_s.
        for rev in (0.2, 0.1, 0.05, 0.025)
            _, v = track_ab_step(0.0, 0.0, rev, 10.0)                 # pred = 0, resid = 10
            @test isapprox(v, TRACK_BETA * 10.0 / rev, atol = 1e-12)
        end

        # A perfect measurement leaves the rate ALONE — zero residual, zero correction.
        r4, v4 = track_ab_step(1000.0, -300.0, 0.1, 970.0)
        @test isapprox(r4, 970.0, atol = 1e-12) && isapprox(v4, -300.0, atol = 1e-12)

        # ⚠ Convention 5 again: a degenerate revisit coasts in place, never divides by zero.
        @test track_ab_step(1000.0, -300.0, 0.0,  990.0) == (1000.0, -300.0)
        @test track_ab_step(1000.0, -300.0, -0.1, 990.0) == (1000.0, -300.0)
        @test all(isfinite, track_ab_step(1000.0, -300.0, 0.1, NaN))
    end

    @testset "the four pieces compose into the probes' tracker (the ORACLE tooth)" begin
        # ⭐⭐⭐ THE STRONGEST TOOTH HERE: an INDEPENDENT reimplementation of the offline tracker from
        # `M:\claud_projects\temp\slice54\p7_band.jl` (lines 88..110) — transcribed from the PROBE,
        # not from the shipped functions — run over a hand-built picture and required to agree
        # look-for-look with the composition of the four shipped pieces. If they diverge, the core
        # does not run the rule that produced §2.8's table and no number in the plan is quotable.
        rev = 0.1
        # The picture: 12 looks. A target closes 1000 → 725 m at −250 m/s (25 m per look) and is the
        # LOUDEST thing in the profile while it is there; a quieter decoy sits at 5000 m throughout;
        # the target is missing on looks 5..8 — a gap the give-up rule must ride — and back after.
        #
        # ⚠ THE TARGET MUST OUT-SHOUT THE DECOY OR NEITHER ARM EVER HOLDS IT: `track_reopen` takes
        # the STRONGEST cell, so a louder decoy captures the track on look 1 and both arms sit on
        # 5000 m for the whole pass. That is correct behaviour and it silently voids the
        # demonstration below — found by this tooth failing, and worth keeping as the reason the
        # powers are the way round they are.
        looks = map(1:12) do k
            tgt_r   = 1000.0 - 25.0 * (k - 1)
            present = !(5 ≤ k ≤ 8)
            (rng = present ? [tgt_r, 5000.0] : [5000.0],
             pow = present ? [40.0, 3.0]     : [3.0])
        end

        # --- the independent reimplementation (probe semantics, written out longhand) ---
        function probe_tracker(lks, n_drop)
            alive = false; misses = 0; r = 0.0; rdot = 0.0; out = Tuple{Bool,Float64}[]
            for u in lks
                if alive
                    pred = r + rdot * rev
                    gate = max(1, min(8, ceil(Int, abs(rdot) * rev / dr_1mhz))) * dr_1mhz
                    bi, bd = 0, Inf
                    for (i, rr) in enumerate(u.rng)
                        d = abs(rr - pred); (d ≤ gate && d < bd) && (bi = i; bd = d)
                    end
                    if bi != 0
                        resid = u.rng[bi] - pred
                        r = pred + 0.5 * resid; rdot += (0.1 / rev) * resid; misses = 0
                    else
                        r = pred; misses += 1; misses ≥ n_drop && (alive = false)
                    end
                elseif !isempty(u.rng)
                    _, i = findmax(u.pow); alive = true; misses = 0; r = u.rng[i]; rdot = 0.0
                end
                push!(out, (alive, r))
            end
            out
        end

        # --- the composition of the SHIPPED pieces ---
        function shipped_tracker(lks, n_drop)
            alive = false; misses = 0; r = 0.0; rdot = 0.0; out = Tuple{Bool,Float64}[]
            for u in lks
                if alive
                    pred = r + rdot * rev
                    i    = track_associate(pred, u.rng,
                                           track_gate_cells(rdot, rev, dr_1mhz) * dr_1mhz)
                    r, rdot = track_ab_step(r, rdot, rev, i == 0 ? nothing : u.rng[i])
                    alive, misses, _, _ = track_run_step(alive, misses, i != 0, n_drop)
                else
                    i = track_reopen(u.pow)
                    if i != 0
                        r = u.rng[i]; rdot = 0.0
                        alive, misses, _, _ = track_run_step(alive, misses, true, n_drop)
                    end
                end
                push!(out, (alive, r))
            end
            out
        end

        for n_drop in 1:6
            a = probe_tracker(looks, n_drop); b = shipped_tracker(looks, n_drop)
            @test length(a) == length(b)
            for k in eachindex(a)
                @test a[k][1] == b[k][1]                       # same alive/dead, look for look
                @test isapprox(a[k][2], b[k][2], atol = 1e-9)  # …and the same range
            end
        end

        # ⭐ AND THE COMPOSITION EXHIBITS THE LESSON'S MECHANISM ON 12 LOOKS: at n_drop = 1 the
        # 4-look gap kills the track, which then RE-OPENS on the loud decoy and is wrong for the
        # rest of the pass; at n_drop = 5 it rides the gap and is still on the target at the end.
        impatient = shipped_tracker(looks, 1)
        patient   = shipped_tracker(looks, 5)
        @test impatient[12][1] && isapprox(impatient[12][2], 5000.0, atol = 250.0)
        @test patient[12][1]   && patient[12][2] < 1000.0
    end
end
