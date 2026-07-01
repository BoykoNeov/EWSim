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
end
