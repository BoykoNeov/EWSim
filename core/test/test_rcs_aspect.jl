# test_rcs_aspect.jl — ASPECT-DEPENDENT RADAR CROSS-SECTION (slice 49 gate 1, plan §0.3 / §3 / §7).
#
# How visible you are depends on which way you are pointing. Three pure kernels, all
# `frames.jl`-class — no `w.rng`, no `World`, no telemetry, no LinearAlgebra (convention 12) — so
# every check here carries an EXPLICIT atol and either an EXTERNAL anchor or an INDEPENDENT
# recompute (convention 11). Never `rtol`-`≈ 0`, which passes trivially.
#
# WHAT THIS FILE HAS TEETH FOR:
#   1. `rcs_aspect` at its three hand-computable anchors — broadside EXACT, nose/tail `σ/F⁴`,
#      sphere aspect-INDEPENDENT.
#   2. An INDEPENDENT oracle: the RAW physical-optics ellipsoid `π a²b²c²/(…)²` built from actual
#      semi-axes, which reaches the same curve through a different expression.
#   3. ⚠⚠ `aspect_angle`'s SIGN — target→observer, pinned at 0 / π/2 / π on hand-built geometries.
#      A flipped vector reflects θ about π/2, which `rcs_aspect`'s fore/aft symmetry HIDES, so the
#      angle must be pinned on its own and not through the σ it feeds.
#   4. The degenerates a slider or a scenario reaches in one step — finite, defined, non-throwing.
#   5. ⭐ THE ONE THAT WOULD HAVE KILLED THE SLICE AT GATE 2: `_lateral_accel`'s `:vertical` branch
#      is BYTE-IDENTICAL to the slices 12–48 expression, and `:horizontal` genuinely leaves it.
#   6. The plan's own measured claim (§2): σ moves ~40× between 65° and 82° at F = 10 — the
#      "σ^(1/4) so nothing matters" reflex, pinned as a number so it cannot come back.

@testset "aspect-dependent RCS (slice 49)" begin

    # ── THE INDEPENDENT ORACLE (convention 11 — a DIFFERENT expression, not a recompute) ───────
    # The RAW ellipsoid from real semi-axes: radial `r` twice, body `L` once, θ from the BODY axis.
    #     σ = π·a²b²c² / (a²sin²θcos²φ + b²sin²θsin²φ + c²cos²θ)²   with a = b = r, c = L, φ = 0
    # `rcs_aspect` is this divided through by its own θ = π/2 value; the oracle keeps the metres
    # and the π, so a slip in the normalization algebra separates them.
    function ellipsoid_raw(r, L, θ)
        num = π * r^2 * r^2 * L^2
        den = (r^2 * sin(θ)^2 + L^2 * cos(θ)^2)^2
        return num / den
    end

    @testset "the three anchors" begin
        σ_bs = 4.0
        # 1. BROADSIDE IS EXACT AT EVERY FINENESS — the normalization's whole point.
        for F in (1.0, 1.5, 3.0, 10.0, 40.0)
            @test rcs_aspect(σ_bs, F, π/2) == σ_bs        # atol 0: an EXACT identity, not a fit
        end
        # 2. NOSE-ON AND TAIL-ON ARE σ/F⁴ — hand-computed, not recomputed from the formula.
        @test rcs_aspect(σ_bs, 10.0, 0.0) ≈ 4.0 / 10_000 atol = 1e-15    # 40 dB down
        @test rcs_aspect(σ_bs, 10.0, π)   ≈ 4.0 / 10_000 atol = 1e-15
        @test rcs_aspect(σ_bs,  3.0, 0.0) ≈ 4.0 / 81      atol = 1e-14   # 19.1 dB down
        @test rcs_aspect(σ_bs,  2.0, 0.0) ≈ 0.25          atol = 1e-15   # 4/16, by hand
        # 3. A SPHERE IS ASPECT-INDEPENDENT — the NULL the showcase's slider floor sits on.
        for θ in range(0, π; length = 37)
            @test rcs_aspect(σ_bs, 1.0, θ) ≈ σ_bs atol = 1e-12
        end
    end

    @testset "against the raw-ellipsoid oracle" begin
        r, L = 0.5, 5.0                     # F = 10, a slender body
        F    = L / r
        σ_bs = ellipsoid_raw(r, L, π/2)     # the oracle's OWN broadside value, in m²
        @test σ_bs ≈ π * L^2 atol = 1e-12   # …and that value is π L², by hand
        for θ in range(0, π; length = 73)
            @test rcs_aspect(σ_bs, F, θ) ≈ ellipsoid_raw(r, L, θ) rtol = 1e-12
        end
        # A DIFFERENT shape, so the agreement is not an artifact of one aspect ratio.
        r2, L2 = 1.2, 3.6
        σ2 = ellipsoid_raw(r2, L2, π/2)
        for θ in range(0, π; length = 37)
            @test rcs_aspect(σ2, L2 / r2, θ) ≈ ellipsoid_raw(r2, L2, θ) rtol = 1e-12
        end
    end

    @testset "⚠⚠ aspect_angle's SIGN is target→observer" begin
        # Target at the origin flying +x. The observer's placement fixes the answer BY HAND.
        tp = Vec3(0.0, 0.0, 0.0)
        tv = Vec3(250.0, 0.0, 0.0)
        # DEAD AHEAD of the target ⇒ NOSE-ON ⇒ 0. (Reverse the vector and this reads π.)
        @test aspect_angle(tp, tv, Vec3(1000.0, 0.0, 0.0)) ≈ 0.0   atol = 1e-12
        # DEAD ASTERN ⇒ TAIL-ON ⇒ π.
        @test aspect_angle(tp, tv, Vec3(-1000.0, 0.0, 0.0)) ≈ π    atol = 1e-12
        # ABEAM, both sides and out of plane ⇒ BROADSIDE ⇒ π/2 (no left/right distinction: the
        # angle is unsigned by construction, which is what an axisymmetric body means).
        @test aspect_angle(tp, tv, Vec3(0.0,  1000.0, 0.0)) ≈ π/2  atol = 1e-12
        @test aspect_angle(tp, tv, Vec3(0.0, -1000.0, 0.0)) ≈ π/2  atol = 1e-12
        @test aspect_angle(tp, tv, Vec3(0.0, 0.0,  1000.0)) ≈ π/2  atol = 1e-12
        # 45° forward quarter — an INDEPENDENT hand geometry, not a recompute.
        @test aspect_angle(tp, tv, Vec3(1000.0, 1000.0, 0.0)) ≈ π/4 atol = 1e-12
        # ⭐ THE SLICE-49 SHOWCASE GEOMETRY, hand-checked: a radar at the origin, the target due
        # +y of it at 25 km / 5 km alt flying +x, is BROADSIDE; after turning 90° onto −y it is
        # NOSE-ON to that same radar.
        tgt = Vec3(0.0, 25_000.0, 5_000.0)
        @test aspect_angle(tgt, Vec3(250.0, 0.0, 0.0), Vec3(0.0, 0.0, 0.0)) ≈ π/2 atol = 1e-12
        @test aspect_angle(tgt, Vec3(0.0, -250.0, 0.0), Vec3(0.0, 0.0, 0.0)) ≈
              atan(5_000.0, 25_000.0) atol = 1e-12
        # …and the SEEKER geometry P0 measured off slice48_search.yaml: 63.88° at launch.
        @test rad2deg(aspect_angle(Vec3(6000.0, 3000.0, 4200.0), Vec3(0.0, -200.0, 0.0),
                                   Vec3(0.0, 0.0, 3000.0))) ≈ 63.8823 atol = 1e-3
    end

    @testset "degenerates — finite, defined, non-throwing (conventions 5/6)" begin
        # A STATIONARY target has no nose ⇒ BROADSIDE ⇒ rcs_aspect returns the AUTHORED σ, i.e.
        # the degenerate reduces to the scalar model rather than to a NaN.
        @test aspect_angle(Vec3(0.0,0.0,0.0), zero(Vec3), Vec3(10.0,0.0,0.0)) == 0.5π
        @test rcs_aspect(4.0, 10.0, aspect_angle(Vec3(0.0,0.0,0.0), zero(Vec3),
                                                 Vec3(10.0,0.0,0.0))) == 4.0
        # A COINCIDENT observer, likewise.
        @test aspect_angle(Vec3(5.0,5.0,5.0), Vec3(1.0,0.0,0.0), Vec3(5.0,5.0,5.0)) == 0.5π
        # Never NaN, never Inf, for any placement on a sphere of directions.
        for θ in range(0, π; length = 13), φ in range(0, 2π; length = 13)
            a = aspect_angle(Vec3(0.0,0.0,0.0), Vec3(1.0,0.0,0.0),
                             Vec3(sin(θ)*cos(φ), sin(θ)*sin(φ), cos(θ)))
            @test isfinite(a) && 0.0 ≤ a ≤ π
            @test isfinite(rcs_aspect(4.0, 10.0, a)) && rcs_aspect(4.0, 10.0, a) > 0
        end
        # The DOMAIN throws are by design (the `detection_range` posture — clamped at the CONSUMER).
        @test_throws DomainError rcs_aspect(0.0, 10.0, 0.5)
        @test_throws DomainError rcs_aspect(-1.0, 10.0, 0.5)
        @test_throws DomainError rcs_aspect(4.0, 0.0, 0.5)
        @test_throws DomainError rcs_aspect(4.0, -3.0, 0.5)
        # F < 1 is an OBLATE body and is LEGAL — brighter nose-on than broadside.
        @test rcs_aspect(4.0, 0.5, 0.0) ≈ 4.0 / 0.0625 atol = 1e-12
        @test rcs_aspect(4.0, 0.5, 0.0) > rcs_aspect(4.0, 0.5, π/2)
    end

    @testset "⚠⚠ σ^(1/4) does NOT make aspect negligible (plan §2)" begin
        # The trap that produced a wrong prediction at gate 0: the denominator is SQUARED, so for a
        # slender body σ moves an order of magnitude over the broadside QUARTER, where a sin² lobe
        # would be flat. These are the plan's own numbers, pinned so the reflex cannot come back.
        σ65 = rcs_aspect(1.0, 10.0, deg2rad(65.0))
        σ72 = rcs_aspect(1.0, 10.0, deg2rad(72.605))
        σ82 = rcs_aspect(1.0, 10.0, deg2rad(82.0))
        # ⚠ 41.00, not the 40.1 the plan's §2 first wrote by hand — that draft mis-squared
        # cos 82°, and the test caught it. The plan is corrected to match; the CLAIM (an order of
        # magnitude over seventeen degrees, where a sin² lobe gives ~1.2×) is untouched.
        @test σ82 / σ65 ≈ 41.00 atol = 0.05        # 41×, over SEVENTEEN degrees
        @test σ72 / σ65 ≈ 3.60  atol = 0.05
        # …which is 2.53× in RANGE, because detection_range goes as σ^(1/4). Reached INDEPENDENTLY
        # through the shipped link budget rather than by taking the root of the ratio above.
        rp = RadarParams(200.0, 30.0, 16.0e9, 100.0, 4.0, 5.0)
        @test detection_range(rp, σ82) / detection_range(rp, σ65) ≈ (41.00)^0.25 atol = 0.01
        # MONOTONE from nose to broadside at every fineness > 1 — the property the showcase's
        # gauge rests on (an INDEPENDENT sweep, not an appeal to the formula).
        for F in (1.5, 3.0, 6.0, 10.0)
            prev = -Inf
            for θd in 0.0:1.0:90.0
                σ = rcs_aspect(1.0, F, deg2rad(θd))
                @test σ > prev
                prev = σ
            end
        end
    end

    @testset "⭐ the turn plane — :vertical is BYTE-identical, :horizontal genuinely differs" begin
        # `_lateral_accel` is module-internal; reach it the way the other internals are reached.
        lat = EWSim._lateral_accel
        for v in (Vec3(250.0, 0.0, 0.0), Vec3(180.0, -60.0, 12.0), Vec3(-90.0, 30.0, -40.0))
            for a in (0.0, 9.80665, 45.0), sg in (1.0, -1.0)
                # THE BYTE-IDENTITY TOOTH: the default arm and the explicit `:vertical` arm are the
                # SAME BITS as the two-argument expression slices 12–48 flew. `==` on Vec3, atol 0.
                legacy = (a * sg / sqrt(v[1]^2 + v[3]^2)) * Vec3(-v[3], 0.0, v[1])
                @test lat(v, a, sg)            == legacy
                @test lat(v, a, sg, :vertical) == legacy
                # …and the horizontal arm is the x–y sibling, +90° about +z.
                h = lat(v, a, sg, :horizontal)
                @test h == (a * sg / sqrt(v[1]^2 + v[2]^2)) * Vec3(-v[2], v[1], 0.0)
                # ⚠ A TURN IS ⟂ TO VELOCITY IN ITS OWN PLANE — that is what "coordinated" means,
                # and it is what keeps the turn speed-preserving. Checked INDEPENDENTLY by dot
                # product, not by re-deriving the perpendicular.
                @test abs(h[1]*v[1] + h[2]*v[2]) ≤ 1e-9 * max(a, 1.0) * hypot(v[1], v[2])
                @test h[3] == 0.0                      # the horizontal turn never touches z
                @test lat(v, a, sg)[2] == 0.0          # …and the vertical one never touches y
                # MAGNITUDE is `a` on both planes (a > 0), independently of direction.
                a > 0 && @test hypot(h[1], h[2], h[3]) ≈ a atol = 1e-9
            end
        end
        # The zero-guards: no NaN when the in-plane speed vanishes on EITHER plane.
        @test EWSim._lateral_accel(Vec3(0.0, 250.0, 0.0), 40.0, 1.0, :vertical)   == zero(Vec3)
        @test EWSim._lateral_accel(Vec3(0.0, 0.0, 250.0), 40.0, 1.0, :horizontal) == zero(Vec3)
        @test EWSim._lateral_accel(zero(Vec3), 40.0, 1.0, :horizontal)            == zero(Vec3)
        # ONE LIST, NO DRIFT (convention 7): the loader validates against this tuple.
        @test TARGET_TURN_PLANES == (:vertical, :horizontal)
        @test TARGET_TURN_PLANES[1] === :vertical      # the DEFAULT is first, and stays first
    end
end

# --- slice 49 GATE 2: THE WIRE -----------------------------------------------------------------
#
# Gate 1 pinned the kernels. These pin the SEAM: that the aspect model reaches the physics through
# exactly ONE site (`_effective_rcs`), that the key-absent path is the slices-1..48 line and not an
# algebraic special case, that the loader refuses what the consumer cannot survive, and that the
# horizontal turn is a real turn on the real mover.
#
# ⭐⭐ THE ONE THAT MATTERS is "TWO OBSERVERS, ONE TARGET, TWO CROSS-SECTIONS". Every equal-value
# tooth below also passes if aspect were a property stamped on the target once per tick — the
# slice-30 lesson, one arc over (only a DISAGREEING pair separates the orders). A radar and a
# missile looking at the same target at the same instant must read DIFFERENT σ, or the seam is
# wrong in a way no single-observer test can see.

# A bare radar + target world: no movers, truth written by the caller, so the aspect under test is
# exactly the geometry named. `fineness === nothing` withholds the key — the presence gate is the
# thing under test.
function _aspect_world(; tgt_pos = Vec3(0.0, 25_000.0, 5_000.0), tgt_vel = Vec3(250.0, 0.0, 0.0),
                         rcs = 4.0, fineness = nothing, radar_pos = Vec3(0.0, 0.0, 30.0))
    w = World(seed = 49)
    comp = Dict{Symbol,Any}(:rcs_m2 => rcs)
    fineness === nothing || (comp[:rcs_fineness] = fineness)
    w.entities[:tgt1] = Entity(:tgt1, :target; pos = tgt_pos, vel = tgt_vel, comp = comp)
    w.entities[:radar1] = Entity(:radar1, :radar; pos = radar_pos, vel = zero(Vec3),
        comp = Dict{Symbol,Any}(:pt_w => 50_000.0, :gain_db => 35.0, :freq_hz => 9.4e9,
                                :bandwidth_hz => 1.0e6, :noise_fig_db => 3.0, :losses_db => 4.0,
                                :pfa => 1.0e-6, :swerling => 1, :n_pulses => 1, :revisit_s => 0.1))
    return w, Subsystem[RadarSensor(:radar1; revisit_s = 0.1)]
end

@testset "aspect-dependent RCS — THE WIRE (slice 49 gate 2)" begin

    @testset "⚠⚠ BYTE-IDENTITY — no `rcs_fineness` ⇒ the slices-1..48 line, bit-for-bit" begin
        w, _ = _aspect_world()
        tgt = w.entities[:tgt1]
        # The presence gate short-circuits before ANY arithmetic, so the returned value is the
        # authored object itself — `===`, not an approximate compare.
        @test EWSim._effective_rcs(tgt, Vec3(0.0, 0.0, 30.0)) === tgt.comp[:rcs_m2]
        # …at every geometry, including ones where an aspect model would bite hardest.
        for op in (Vec3(0.0,0.0,0.0), Vec3(1e5,0.0,0.0), Vec3(0.0,25_000.0,5_000.0),
                   Vec3(-3e4, 1e4, -2e3))
            @test EWSim._effective_rcs(tgt, op) === tgt.comp[:rcs_m2]
        end
        # ⭐ PAIRED with an arm that DOES branch, so the claim is not vacuous (a test that only
        # compares two key-absent runs proves determinism, not gating).
        # ⚠ The observer must be OFF BROADSIDE for this to bite. The default geometry here is
        # exactly abeam, where sigma legitimately EQUALS the authored value at every fineness — a
        # first draft paired against that point and read as a pass-with-no-branch.
        w2, _ = _aspect_world(fineness = 10.0)
        @test EWSim._effective_rcs(w2.entities[:tgt1], Vec3(1.0e5, 25_000.0, 5_000.0)) !=
              w2.entities[:tgt1].comp[:rcs_m2]
        # ⚠⚠ AND `F = 1` IS **NOT** THE BYTE-IDENTITY PATH — that is the whole reason the gate is on
        # the KEY. A sphere is the LESSON null; the absent key is the WIRE null. Both must produce
        # the same NUMBER while being reached by different code.
        w3, _ = _aspect_world(fineness = 1.0)
        @test EWSim._effective_rcs(w3.entities[:tgt1], Vec3(0.0,0.0,30.0)) ≈ 4.0 atol = 1e-13
    end

    @testset "⭐⭐ TWO OBSERVERS, ONE TARGET, TWO CROSS-SECTIONS" begin
        # The target flies +x at 25 km due +y of the radar: BROADSIDE to an observer abeam of it
        # and NOSE-ON to one sitting dead ahead — at the SAME INSTANT, off the SAME comp bag.
        w, _ = _aspect_world(fineness = 10.0)
        tgt = w.entities[:tgt1]
        σ_abeam  = EWSim._effective_rcs(tgt, Vec3(0.0, 25_000.0, 6_000.0))
        σ_ahead  = EWSim._effective_rcs(tgt, Vec3(50_000.0, 25_000.0, 5_000.0))
        σ_astern = EWSim._effective_rcs(tgt, Vec3(-50_000.0, 25_000.0, 5_000.0))
        @test σ_abeam  ≈ 4.0            atol = 1e-12
        @test σ_ahead  ≈ 4.0 / 10_000   atol = 1e-15      # 40 dB down
        @test σ_astern ≈ 4.0 / 10_000   atol = 1e-15      # fore/aft symmetric, the NAMED approx
        @test σ_abeam / σ_ahead ≈ 10_000 atol = 1e-6      # 10⁴ apart, one target, one tick
    end

    @testset "the seam reaches the radar through the ONE site" begin
        # `_target_snr` must read the aspect value, not the raw key — checked against an
        # INDEPENDENT link-budget recompute off `rcs_aspect`, not off `_effective_rcs` (which
        # would be the same call twice).
        w, subs = _aspect_world(fineness = 10.0, tgt_vel = Vec3(0.0, -250.0, 0.0))
        tick!(w, subs, 1.0e-3)
        tel = w.env[:telemetry]
        tgt, rdr = w.entities[:tgt1], w.entities[:radar1]
        rp = RadarParams(50_000.0, 35.0, 9.4e9, 1.0e6, 3.0, 4.0)
        θ  = aspect_angle(tgt.pos, tgt.vel, rdr.pos)
        σ  = rcs_aspect(4.0, 10.0, θ)
        R  = los_range(rdr.pos, tgt.pos)
        @test tel["radar1.snr_db"] ≈ lin2db(snr_freespace(rp, σ, R)) atol = 1e-9
        # …and the flown σ is three orders below the authored key, so this could not have passed
        # off `comp[:rcs_m2]`.
        @test σ < 4.0 / 1000
        # THE READOUTS, describing the same target the SNR does. DEGREES on the wire.
        @test tel["radar1.target_aspect_deg"] ≈ rad2deg(θ) atol = 1e-9
        @test tel["radar1.rcs_eff_m2"]        ≈ σ          atol = 1e-15
    end

    @testset "the new telemetry is KEY-PRESENCE gated (no defaulted zeros on old wires)" begin
        # ⚠ The CLAUDE.md trap: a client `.get(k, 0.0)` prints a DEFAULTED ZERO as a passed test.
        # These keys must be ABSENT on a scalar wire, never present-and-zero.
        w, subs = _aspect_world()                       # no fineness
        tick!(w, subs, 1.0e-3)
        @test !haskey(w.env[:telemetry], "radar1.target_aspect_deg")
        @test !haskey(w.env[:telemetry], "radar1.rcs_eff_m2")
        @test haskey(w.env[:telemetry], "radar1.snr_db")          # …the old keys still ship
        w2, subs2 = _aspect_world(fineness = 6.0)
        tick!(w2, subs2, 1.0e-3)
        @test haskey(w2.env[:telemetry], "radar1.target_aspect_deg")
        @test haskey(w2.env[:telemetry], "radar1.rcs_eff_m2")
    end

    @testset "a live slider can never crash a tick (convention 5)" begin
        # The loader refuses `F <= 0`, but a live `set_param` writes straight to the comp bag and
        # `rcs_aspect` throws a DomainError by design. The CONSUMER floor is what stands between
        # that and a dropped connection.
        for bad in (0.0, -3.0, -1.0e-30)
            w, subs = _aspect_world(fineness = bad)
            @test (tick!(w, subs, 1.0e-3); true)
            v = w.env[:telemetry]["radar1.rcs_eff_m2"]
            @test isfinite(v) && v > 0
        end
        # A degenerate RCS too, and a huge-but-finite fineness — finite out, never an infinity.
        w, subs = _aspect_world(rcs = 0.0, fineness = 1.0e6)
        @test (tick!(w, subs, 1.0e-3); true)
        @test isfinite(w.env[:telemetry]["radar1.rcs_eff_m2"])
        @test isfinite(w.env[:telemetry]["radar1.snr_db"])
    end

    @testset "⭐ the HORIZONTAL turn is a real turn on the real mover" begin
        # `ManeuveringTarget`, not the kernel: the plane must survive the comp bag and the RK4 step.
        function turn(plane; n = 20_000, dt = 1.0e-3)
            w = World(seed = 49)
            comp = Dict{Symbol,Any}(:rcs_m2 => 1.0, :a_lat_mps2 => 30.0, :turn_sign => 1.0)
            plane === nothing || (comp[:turn_plane] = plane)
            w.entities[:tgt1] = Entity(:tgt1, :target; pos = Vec3(0.0, 25_000.0, 5_000.0),
                                       vel = Vec3(250.0, 0.0, 0.0), comp = comp)
            subs = Subsystem[ManeuveringTarget(:tgt1)]
            tr = Float64[]
            for _ in 1:n
                tick!(w, subs, dt)
                e = w.entities[:tgt1]
                append!(tr, (e.pos[1], e.pos[2], e.pos[3], e.vel[1], e.vel[2], e.vel[3]))
            end
            return tr, w.entities[:tgt1]
        end
        tr_absent,     e_absent = turn(nothing)
        tr_vertical,   e_vert   = turn(:vertical)
        tr_horizontal, e_horz   = turn(:horizontal)
        # ⚠⚠ THE BYTE-IDENTITY TOOTH, THROUGH THE WHOLE MOVER: absent is :vertical, bit-for-bit over
        # 20 000 ticks of pos AND vel — the full trace, not a summary.
        @test tr_absent == tr_vertical
        @test tr_absent != tr_horizontal          # …PAIRED, so the claim is not vacuous
        # The VERTICAL turn never leaves the x–z plane; the HORIZONTAL never leaves x–y.
        @test e_vert.pos[2] == 25_000.0 && e_vert.vel[2] == 0.0
        @test e_horz.pos[3] == 5_000.0  && e_horz.vel[3] == 0.0
        @test e_vert.pos[3] != 5_000.0            # …and each DOES move in its own plane
        @test e_horz.pos[2] != 25_000.0
        # A coordinated turn is SPEED-PRESERVING on either plane (RK4 holds it to machine eps) —
        # an INDEPENDENT invariant, not a restatement of the perpendicular.
        for e in (e_vert, e_horz)
            @test hypot(e.vel[1], e.vel[2], e.vel[3]) ≈ 250.0 rtol = 1e-9
        end
        # …and after 20 s at 30 m/s the heading has swept a/v*t = 2.4 rad — hand-computed from the
        # turn rate, not read back off the trace.
        @test atan(e_horz.vel[2], e_horz.vel[1]) ≈ 30.0 / 250.0 * 20.0 rtol = 1e-6
    end
end
