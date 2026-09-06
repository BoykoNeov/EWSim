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
