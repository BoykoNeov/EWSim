# test_frames.jl — the shared frame / LOS library vs its closed forms (HANDOFF §9,
# slice 8 gate 1).
#
# Like geometry/two_ray these are DETERMINISTIC, so every check is an exact closed form
# with an EXPLICIT atol (never rtol-`≈0`, which passes trivially). The §1 co-headline
# here is SIGNS: the quaternion round-trip / known-rotation orientation, and above all
# the LOS-rate SIGN on a concrete crossing (the #1 "missile flies away" bug) and the
# range_rate sign (negative = closing) — pinned on VALUE and SIGN, not just magnitude.
# The azimuth == geometry.jl `bearing` pin is the §9 reuse-faithfulness proof.

@testset "frames / quaternion + LOS kernel" begin
    id = Quat(1, 0, 0, 0)
    norm3_test(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)   # test-local (no LinearAlgebra dep)

    @testset "quaternion round-trip + inverse (the day-one §1 test)" begin
        q = quat_from_axis_angle(Vec3(1.0, 2.0, 3.0), 0.7)   # arbitrary unit rotation
        for v in (Vec3(1,0,0), Vec3(0,1,0), Vec3(0,0,1), Vec3(-2.5, 4.0, 1.5))
            @test rotate_inv(q, rotate(q, v)) ≈ v atol=1e-12          # inertial↔body pair
            @test rotate(q, rotate_inv(q, v)) ≈ v atol=1e-12
        end
        # q ⊗ q⁻¹ = identity (up to sign; check the rotation acts as identity)
        prod = qmul(q, qinv(q))
        @test rotate(prod, Vec3(1,2,3)) ≈ Vec3(1,2,3) atol=1e-12
        # a unit rotation preserves length
        @test norm3_test(rotate(q, Vec3(3,4,0))) ≈ 5.0 atol=1e-12
        # qnormalize of a scaled quaternion is unit; a zero quaternion → identity (guard)
        @test qnormalize(2.0 * q) ≈ q atol=1e-12
        @test qnormalize(Quat(0,0,0,0)) == id
    end

    @testset "known rotations — 90° about ẑ, SIGN-checked (x̂→ŷ, ŷ→−x̂)" begin
        qz = quat_from_axis_angle(Vec3(0,0,1), π/2)
        @test rotate(qz, Vec3(1,0,0)) ≈ Vec3(0, 1, 0) atol=1e-12      # +x → +y (right-hand)
        @test rotate(qz, Vec3(0,1,0)) ≈ Vec3(-1, 0, 0) atol=1e-12     # +y → −x
        @test rotate(qz, Vec3(0,0,1)) ≈ Vec3(0, 0, 1) atol=1e-12      # axis fixed
        # 90° about x̂ sends ŷ → ẑ
        qx = quat_from_axis_angle(Vec3(1,0,0), π/2)
        @test rotate(qx, Vec3(0,1,0)) ≈ Vec3(0, 0, 1) atol=1e-12
        # a zero-length axis is no rotation
        @test quat_from_axis_angle(Vec3(0,0,0), 1.3) == id
    end

    @testset "quat_from_two_vectors aligns a→b (+ antiparallel & zero-vector guards)" begin
        # generic: rotate(q2v(a,b), â) ∥ b̂ (unit, same direction)
        a = Vec3(1.0, 0.0, 0.0); b = Vec3(0.0, 0.0, 2.0)
        q = quat_from_two_vectors(a, b)
        @test rotate(q, a / norm3_test(a)) ≈ b / norm3_test(b) atol=1e-12
        # already aligned → identity
        @test quat_from_two_vectors(Vec3(0,3,0), Vec3(0,7,0)) == id
        # antiparallel: rotation axis undefined → π about SOME ⟂ axis, must send a→−a (no NaN)
        qanti = quat_from_two_vectors(Vec3(1,0,0), Vec3(-1,0,0))
        @test all(isfinite, qanti)
        @test rotate(qanti, Vec3(1,0,0)) ≈ Vec3(-1,0,0) atol=1e-12
        # antiparallel along z too (different ⟂-axis branch)
        qaz = quat_from_two_vectors(Vec3(0,0,1), Vec3(0,0,-1))
        @test rotate(qaz, Vec3(0,0,1)) ≈ Vec3(0,0,-1) atol=1e-12
        # zero-vector guard (v→0 at apex of a straight-up shot) → identity, never NaN
        @test quat_from_two_vectors(Vec3(0,0,0), Vec3(1,0,0)) == id
        @test quat_from_two_vectors(Vec3(1,0,0), Vec3(0,0,0)) == id
    end

    @testset "LOS-rate SIGN on a concrete left→right crossing (the #1 bug, advisor)" begin
        # missile at origin looking along +x; target dead ahead at +x, moving +y
        # ("left→right" across the boresight). ω = (r×v)/‖r‖² = (0,0, +v_y/R) → +ẑ.
        r  = Vec3(1000.0, 0.0, 0.0)
        vr = Vec3(0.0, 50.0, 0.0)
        ω = los_rate(r, vr)
        @test ω[3] > 0                                   # SIGN, not just magnitude
        @test ω ≈ Vec3(0.0, 0.0, 0.05) atol=1e-12        # v_y/R = 50/1000
        # reverse the cross-velocity → the sign flips (right→left)
        @test los_rate(r, Vec3(0.0, -50.0, 0.0))[3] < 0
        # purely radial motion → zero LOS rate (nothing to turn toward)
        @test los_rate(r, Vec3(-100.0, 0.0, 0.0)) ≈ zero(Vec3) atol=1e-12
        # zero-range guard → zero, never NaN
        @test los_rate(zero(Vec3), vr) == zero(Vec3)
    end

    @testset "range_rate sign (negative = CLOSING) + los_unit / los_range" begin
        r = Vec3(1000.0, 0.0, 0.0)
        @test range_rate(r, Vec3(-100.0, 0.0, 0.0)) ≈ -100.0 atol=1e-12   # closing
        @test range_rate(r, Vec3( 100.0, 0.0, 0.0)) ≈  100.0 atol=1e-12   # opening
        @test range_rate(r, Vec3(0.0, 80.0, 0.0))   ≈    0.0 atol=1e-12   # pure crossing
        @test range_rate(zero(Vec3), r) == 0.0                            # zero-range guard
        @test los_unit(Vec3(0,0,0), Vec3(0,3,4)) ≈ Vec3(0, 0.6, 0.8) atol=1e-12
        @test los_unit(Vec3(5,5,5), Vec3(5,5,5)) == zero(Vec3)            # zero-range guard
        @test los_range(Vec3(0,0,0), Vec3(3,4,0)) ≈ 5.0 atol=1e-12
    end

    @testset "az_el + the §9 reuse-faithfulness pin (azimuth == geometry `bearing`)" begin
        @test az_el(Vec3(1,0,0)) == (0.0, 0.0)
        @test az_el(Vec3(0,1,0))[1] ≈ π/2 atol=1e-12
        @test az_el(Vec3(0,0,1))[2] ≈ π/2 atol=1e-12                      # straight up
        @test az_el(Vec3(-1,0,0))[1] ≈ π   atol=1e-12
        # the §9 pin: az_el's azimuth uses the SAME atan(Δy,Δx) as geometry.jl's bearing,
        # so on a shared z=0 example they AGREE (conceptually shared, not code-merged)
        for (f, t) in ((Vec3(3,4,0), Vec3(10,9,0)),
                       (Vec3(0,0,0), Vec3(-2,5,0)),
                       (Vec3(1,1,0), Vec3(1,-4,0)))
            @test az_el(los_unit(f, t))[1] ≈ bearing(f, t) atol=1e-12
        end
    end

    # --- slice 25 gate 1: the two-angle (az/el) LOS reconstruction ---------------------
    # The seeker in the 6-DOF loop measures an ANGLE PAIR and must rebuild BOTH the LOS
    # direction and the LOS-rate VECTOR from it. The oracle is `los_rate` itself (the
    # identity ω = û × û̇ ≡ (r×v)/‖r‖², plan §3) computed through a DIFFERENT algorithm —
    # convention 11's independent recompute, not a self-calibrated round-trip.

    @testset "los_unit_from_angles ↔ az_el round-trip (the measurement→direction inverse)" begin
        @test los_unit_from_angles(0.0, 0.0) ≈ Vec3(1, 0, 0) atol=1e-12
        @test los_unit_from_angles(π/2, 0.0) ≈ Vec3(0, 1, 0) atol=1e-12
        @test los_unit_from_angles(0.0, π/2) ≈ Vec3(0, 0, 1) atol=1e-12
        for u in (Vec3(1,0,0), Vec3(0,-1,0), Vec3(0.3,-0.4,0.5), Vec3(-2.0,1.0,-3.0))
            û = u / norm3_test(u)
            az, el = az_el(û)
            @test los_unit_from_angles(az, el) ≈ û atol=1e-12          # round-trip
            @test norm3_test(los_unit_from_angles(az, el)) ≈ 1.0 atol=1e-12
        end
        # the ±π azimuth SEAM: −x is reachable from either side and both rebuild the same û
        @test los_unit_from_angles( π, 0.0) ≈ Vec3(-1, 0, 0) atol=1e-12
        @test los_unit_from_angles(-π, 0.0) ≈ Vec3(-1, 0, 0) atol=1e-12
    end

    @testset "los_rate_from_angles ≡ los_rate (the EXACT oracle, convention 11)" begin
        # An INDEPENDENT closed form for the angle rates from the kinematics (a different
        # algorithm from `los_rate_from_angles`, which is the point):
        #   az = atan(y,x)     ⇒ ȧz = (x·v_y − y·v_x)/(x²+y²)
        #   el = atan(z,ϱ)     ⇒ ėl = (v_z·ϱ − z·ϱ̇)/(ϱ² + z²),  ϱ̇ = (x·v_x + y·v_y)/ϱ
        function angle_rates(r, v)
            ϱ  = hypot(r[1], r[2])
            ȧz = (r[1]*v[2] - r[2]*v[1]) / (r[1]^2 + r[2]^2)
            ϱ̇  = (r[1]*v[1] + r[2]*v[2]) / ϱ
            ėl = (v[3]*ϱ - r[3]*ϱ̇) / (ϱ^2 + r[3]^2)
            return ȧz, ėl
        end
        for (r, v) in ((Vec3(1000.0,    0.0,    0.0), Vec3(-300.0,  50.0,   20.0)),
                       (Vec3(6000.0, 2000.0, 1200.0), Vec3(-700.0, 120.0, -240.0)),
                       (Vec3(-500.0,  900.0, -300.0), Vec3( 110.0, -60.0,   90.0)),
                       (Vec3(  10.0,   -4.0,    7.0), Vec3(  -1.0,   2.5,   -3.0)))
            az, el = az_el(r / norm3_test(r))
            ȧz, ėl = angle_rates(r, v)
            ω_ang  = los_rate_from_angles(az, el, ȧz, ėl)
            ω_tru  = los_rate(r, v)
            # ABSOLUTE atol scaled to the rate magnitude — the identity is EXACT, so this
            # is a floating-point-floor check, not a tolerance to be tuned.
            @test ω_ang ≈ ω_tru atol=1e-12 * max(1.0, norm3_test(ω_tru))
        end
    end

    @testset "the IN-PLANE invariant PAIRED with a does-turn case (the #1 SIGN TRAP, 7th)" begin
        # In-plane: the target sits in the x–z plane and stays there (az ≡ 0, ȧz ≡ 0) ⇒ the
        # LOS rate is PURELY ±y. This is the foil's whole content — a seeker that measures
        # only elevation can never produce ω_x/ω_z. Pinned EXACTLY (`== 0.0`), because the
        # kernel's az terms multiply sin(0) = 0 identically.
        ω_in = los_rate_from_angles(0.0, 0.3, 0.0, 0.02)
        @test ω_in[1] == 0.0
        @test ω_in[3] == 0.0
        @test ω_in[2] < 0                       # climbing LOS (ėl > 0) ⇒ ω ∥ −ŷ
        # PAIRED does-turn case, so the test cannot pass by producing zero: give it an
        # azimuth rate and the out-of-plane components MUST appear.
        ω_out = los_rate_from_angles(0.0, 0.3, 0.02, 0.0)
        @test abs(ω_out[3]) > 1e-3              # ω_z is what turns the missile in cross-range
        @test ω_out != zero(Vec3)
        # SIGN, pinned against truth on a concrete right-going crossing (target dead ahead
        # on +x at 1000 m, moving +y): ω = +ẑ·v_y/R — the same case the los_rate testset pins.
        r = Vec3(1000.0, 0.0, 0.0); v = Vec3(0.0, 50.0, 0.0)
        az, el = az_el(r / norm3_test(r))
        @test los_rate_from_angles(az, el, 50.0/1000.0, 0.0) ≈ los_rate(r, v) atol=1e-12
        @test los_rate_from_angles(az, el, 50.0/1000.0, 0.0)[3] > 0
        # zero rates ⇒ zero ω (a static LOS commands nothing)
        @test los_rate_from_angles(0.7, -0.2, 0.0, 0.0) == zero(Vec3)
    end

    @testset "SEEKER_AXES_MODES — the one-list-no-drift const (convention 7)" begin
        @test SEEKER_AXES_MODES == (:pitch_plane, :az_el)
        @test :az_el in SEEKER_AXES_MODES && :pitch_plane in SEEKER_AXES_MODES
        # it is a SEPARATE key from SEEKER_MODES (the tracker), NOT a fourth rung of it
        @test isempty(intersect(SEEKER_AXES_MODES, SEEKER_MODES))
    end
end
