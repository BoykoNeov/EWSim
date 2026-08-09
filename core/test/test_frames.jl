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

    # --- SLICE 26: the RADOME / body-rate parasitic loop (the arc's named end point) ---------
    @testset "look_angles — the LOS off the missile's own boresight" begin
        û = los_unit(Vec3(0.0, 0.0, 3000.0), Vec3(6000.0, 2000.0, 4200.0))
        # DEGENERATE: the identity attitude is the inertial frame, so the look angles ARE az/el.
        la, le = look_angles(Quat(1, 0, 0, 0), û)
        az0, el0 = az_el(û)
        @test la == az0
        @test le == el0
        # A nose pointed AT the target sees zero look angle (the boresight definition). Build the
        # attitude from `quat_from_two_vectors` — the same constructor `_integrate_6dof!` uses.
        q_on = quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), û)
        la2, le2 = look_angles(q_on, û)
        @test abs(la2) < 1e-12
        @test abs(le2) < 1e-12
        # And it is `az_el ∘ rotate_inv` — an INDEPENDENT recompute, not the same call renamed.
        q_off = quat_from_axis_angle(Vec3(0.0, -1.0, 0.0), 0.17)
        @test collect(look_angles(q_off, û)) ≈ collect(az_el(rotate_inv(q_off, û))) atol=0.0
    end

    @testset "radome_error — R = 0 is EXACT, PAIRED with a does-perturb case" begin
        # `slope == 0` must give exactly (0.0, 0.0) — pinned bit-for-bit. The shipped no-radome
        # path is a KEY-ABSENT branch upstream of this, so this exactness is belt AND braces.
        @test radome_error(0.0, 0.31, -0.22) === (0.0, -0.0)
        @test radome_error(0.0, 0.31, -0.22)[1] == 0.0
        @test radome_error(0.0, 0.31, -0.22)[2] == 0.0
        # PAIRED does-perturb case, so the test cannot pass by producing zero.
        εa, εe = radome_error(-0.10, 0.32, 0.19)
        @test εa ≈ -0.032 atol=1e-15
        @test εe ≈ -0.019 atol=1e-15
        # LINEAR in the slope AND in the look angle (the model's whole content).
        @test radome_error(0.05, 0.4, 0.4)[1] ≈ 2 * radome_error(0.05, 0.2, 0.2)[1] atol=1e-15
        @test radome_error(0.10, 0.4, 0.4)[2] ≈ 2 * radome_error(0.05, 0.4, 0.4)[2] atol=1e-15
        # a zero look angle (nose ON the target) refracts NOTHING, at any slope
        @test radome_error(-0.5, 0.0, 0.0) === (-0.0, -0.0)
    end

    @testset "THE PARASITIC GAIN on a FROZEN GEOMETRY (the #1 SIGN TRAP, 8th occurrence)" begin
        # ⚠ THE GEOMETRY IS FROZEN ON PURPOSE — the target, the missile and the TRUE LOS all hold
        # still and ONLY the attitude rotates, so d(look)/dt is 100% body rate with nothing to
        # confound it. This is NOT stylistic: in closed loop `ėl` and `q` are COLLINEAR (a missile
        # that is tracking pitches at nearly the rate the LOS rotates), so an in-loop fit returns
        # R² = 0.999 with meaningless coefficients (gate-0 P7A). A parasitic gain cannot be
        # measured on a tracking missile.
        û = los_unit(Vec3(0.0, 0.0, 3000.0), Vec3(6000.0, 2000.0, 4200.0))
        R  = -0.10
        dt = 1.0e-3
        # ε̇ under a body rate ω, by finite difference of the shipped kernels
        function eps_dot(ω::Vec3)
            q0 = Quat(1.0, 0.0, 0.0, 0.0)
            q1 = qnormalize(qmul(q0, quat_from_axis_angle(ω, norm3_test(ω) * dt)))
            a0, e0 = radome_error(R, look_angles(q0, û)...)
            a1, e1 = radome_error(R, look_angles(q1, û)...)
            return ((a1 - a0) / dt, (e1 - e0) / dt)
        end
        look_az, _ = look_angles(Quat(1, 0, 0, 0), û)
        # PITCH: ε̇_el = +R·cos(look_az)·ω_y — the sign that makes the loop, measured not cited.
        ėa_up, ėe_up = eps_dot(Vec3(0.0, -1.0, 0.0))        # nose UP is a −y rotation (slice 23)
        @test ėe_up ≈ R * cos(look_az) * (-1.0) atol=2e-4
        # ⚠ AND ITS SIGN IS POSITIVE — `R < 0` times `ω_y < 0`. THAT IS THE LOOP: a nose-up rate
        # RAISES the apparent elevation, which reads as a climbing LOS, which commands more
        # nose-up. (This line was first written `< 0` from the transliterated textbook `−R·q` and
        # the paired coefficient assert above contradicted it — the #1 sign trap caught in its own
        # test, which is the entire reason the assertion is PAIRED.)
        @test ėe_up > 0
        # THE LOOP'S SIGN, stated as the physics rather than as a coefficient: with R < 0 a
        # nose-up rate makes the APPARENT elevation move the SAME way the true one would if the
        # target were climbing — so the guidance sees a climbing LOS and pitches up harder.
        # `ε_el` itself (not its rate) is what the measurement carries:
        q_up = quat_from_axis_angle(Vec3(0.0, -1.0, 0.0), 0.05)    # nose up 0.05 rad
        _, εe_up = radome_error(R, look_angles(q_up, û)...)
        _, εe_0  = radome_error(R, look_angles(Quat(1, 0, 0, 0), û)...)
        @test εe_up > εe_0                                   # pitching up RAISES the apparent el
        # YAW: ε̇_az = −R·ω_z, EXACT (no cosine factor on this axis).
        ėa_yaw, ėe_yaw = eps_dot(Vec3(0.0, 0.0, 1.0))
        @test ėa_yaw ≈ -R * 1.0 atol=2e-4
        @test abs(ėe_yaw) < 1e-3                             # a pure yaw does not move elevation
        # PAIRED NULL: at R = 0 every one of those rates is EXACTLY zero — no loop, no cycle.
        let R0 = 0.0
            q1 = qnormalize(qmul(Quat(1.0, 0.0, 0.0, 0.0),
                                 quat_from_axis_angle(Vec3(0.0, -1.0, 0.0), dt)))
            @test radome_error(R0, look_angles(q1, û)...) === (-0.0, -0.0) ||
                  radome_error(R0, look_angles(q1, û)...) == (0.0, 0.0)
        end
        # SIGN ASYMMETRY: flipping the slope flips the parasitic term (it is LINEAR in R), which
        # is why one sign destabilizes and the other de-tunes.
        let Rp = +0.10
            q1 = qnormalize(qmul(Quat(1.0, 0.0, 0.0, 0.0),
                                 quat_from_axis_angle(Vec3(0.0, -1.0, 0.0), dt)))
            _, εe_p = radome_error(Rp, look_angles(q1, û)...)
            _, εe_n = radome_error(-Rp, look_angles(q1, û)...)
            @test εe_p ≈ -εe_n atol=1e-15
        end
    end

    @testset "radome_compensation — THE CANCELLATION (slice 27; the #1 SIGN TRAP's 9th)" begin
        # ⚠ THE SAME FROZEN GEOMETRY, AND FOR THE SAME REASON (slice 26's P7A stands): in closed
        # loop `ėl` and `q` are COLLINEAR, so a compensator can no more be IDENTIFIED on a tracking
        # missile than the parasitic gain it cancels. Freeze the geometry; measure; then pair.
        û = los_unit(Vec3(0.0, 0.0, 3000.0), Vec3(6000.0, 2000.0, 4200.0))
        R  = -0.10
        dt = 1.0e-3
        # The PARASITIC rate the radome actually produces under a body rate ω — by finite difference
        # of the SHIPPED kernels, exactly as the slice-26 testset above does it.
        function eps_dot(ω::Vec3)
            q0 = Quat(1.0, 0.0, 0.0, 0.0)
            q1 = qnormalize(qmul(q0, quat_from_axis_angle(ω, norm3_test(ω) * dt)))
            a0, e0 = radome_error(R, look_angles(q0, û)...)
            a1, e1 = radome_error(R, look_angles(q1, û)...)
            return ((a1 - a0) / dt, (e1 - e0) / dt)
        end
        # The same finite difference at an ARBITRARY slope — the "bare radome at the residual
        # slope" reference the last block compares against.
        function eps_dot_slope(slope::Float64, ω::Vec3)
            q0 = Quat(1.0, 0.0, 0.0, 0.0)
            q1 = qnormalize(qmul(q0, quat_from_axis_angle(ω, norm3_test(ω) * dt)))
            a0, e0 = radome_error(slope, look_angles(q0, û)...)
            a1, e1 = radome_error(slope, look_angles(q1, û)...)
            return ((a1 - a0) / dt, (e1 - e0) / dt)
        end
        look_az, _ = look_angles(Quat(1, 0, 0, 0), û)

        # ⭐ THE TOOTH THAT WOULD HAVE CAUGHT THE DOUBLE SIGN FLIP. Compensation must CANCEL the
        # measured parasitic rate — the correction PLUS the parasitic term ≈ 0 — with the estimate
        # MATCHED to the truth (R̂ = R). Asserting the formula against itself would pass with BOTH
        # signs negated, which doubles the term at R̂ = R and quiets the ring at R̂ = −R instead:
        # the slice would then be written up backwards (advisor, gate 0).
        for ω in (Vec3(0.0, -1.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, 1.0),
                  Vec3(0.0, -0.6, 0.8))
            ėa_p, ėe_p = eps_dot(ω)                          # what the radome ADDS
            Δa,   Δe   = radome_compensation(R, look_az, ω)  # what the gyro SUBTRACTS
            @test abs(ėe_p + Δe) < 2e-4                      # ELEVATION: cancelled, all rates
        end
        # AZIMUTH cancels on a PURE YAW rate — the term the two-term law models.
        let (ėa_p, _) = eps_dot(Vec3(0.0, 0.0, 1.0)), (Δa, _) = radome_compensation(R, look_az, Vec3(0.0, 0.0, 1.0))
            @test abs(ėa_p + Δa) < 2e-4
        end

        # ⚠⚠ AND WHAT IT DOES **NOT** CANCEL — MEASURED AND PINNED, NOT HIDDEN (gate-1 finding).
        # Slice 26's own frozen-geometry table already showed it: a PITCH rate also moves AZIMUTH
        # (`ε̇_az/R = −0.0598` at ω = (0,−1,0)) for an OFF-BORESIGHT LOS — a CROSS-TERM the classic
        # two-term feed-forward does not model. So the azimuth channel keeps a residual under pitch,
        # and this testset FIRST failed on exactly that (0.005984 against a 2e-4 tolerance). It is a
        # §1 named approximation of the compensator, not a defect in it — and it does not touch the
        # slice's claim, because the ELEVATION channel is the one that closes the pitch loop (its
        # gain is 0.9487 against the cross-term's 0.0598, ~16×) and the residual law was MEASURED
        # end-to-end with this very law, holding to ±3% across N ∈ {3…8} and ρ ∈ {0.6…2.0}.
        # Pinned against the cross-coefficient MEASURED from the shipped kernel — never a magic
        # constant (convention 11).
        k_cross = eps_dot_slope(1.0, Vec3(0.0, 1.0, 0.0))[1]      # az rate per unit ω_y per unit slope
        k_pitch = eps_dot_slope(1.0, Vec3(0.0, 1.0, 0.0))[2]      # el rate per unit ω_y per unit slope
        @test abs(k_cross) > 0.01                                  # it is REAL — not a rounding artifact
        @test abs(k_cross / k_pitch) < 0.10                        # and it is SMALL — ~16× down
        let ω = Vec3(0.0, 1.0, 0.0)
            ėa_p, _ = eps_dot(ω)
            Δa,   _ = radome_compensation(R, look_az, ω)
            @test abs(ėa_p + Δa) ≈ abs(R * k_cross) atol = 2e-4    # the residual IS the cross-term
        end

        # ⭐ THE AXIS-ASYMMETRY TOOTH — the one the cancellation test alone CANNOT catch. The
        # parasitic gain carries `cos(look_az)` on the PITCH axis and NOTHING on the yaw axis, so a
        # compensator that applied the cosine to BOTH axes (or to NEITHER) still cancels at
        # `look_az ≈ 0` and would pass a single frozen-geometry test taken at a small look angle.
        # The shipped wire's look-angle deciles START at 14°, where `cos` is 0.97 — close enough to
        # hide it. So assert the axes SEPARATELY, at a look angle big enough to see the cosine.
        @test look_az > 0.25                                  # ≈ 18.4° here — cos = 0.949, not 1
        let (Δa, Δe) = radome_compensation(R, look_az, Vec3(0.0, 0.0, 1.0))   # PURE YAW
            @test Δa == R * 1.0                               # yaw axis: NO cosine factor
            @test Δe == 0.0                                   # and it does not touch elevation
        end
        let (Δa, Δe) = radome_compensation(R, look_az, Vec3(0.0, 1.0, 0.0))   # PURE PITCH
            @test Δa == 0.0                                   # pitch does not touch azimuth
            @test Δe ≈ -R * cos(look_az) atol = 1e-15         # pitch axis: the cosine IS there
            @test Δe != -R                                    # ⇐ the assert that fails if it is dropped
        end

        # R̂ = 0 corrects NOTHING, at any body rate (the knob-reachable off-state — what makes this
        # a KNOB and not a fidelity rung), PAIRED with a does-correct case so it cannot pass by
        # producing zero.
        @test radome_compensation(0.0, look_az, Vec3(0.3, -0.7, 0.5)) == (0.0, -0.0) ||
              radome_compensation(0.0, look_az, Vec3(0.3, -0.7, 0.5)) == (0.0, 0.0)
        @test radome_compensation(-0.1, look_az, Vec3(0.3, -0.7, 0.5)) != (0.0, 0.0)
        # A ZERO BODY RATE corrects nothing at any slope — the parasitic path is a BODY-RATE path,
        # which is the entire reason a gyro is the right sensor for it.
        @test radome_compensation(-0.5, look_az, zero(Vec3)) == (-0.0, 0.0) ||
              radome_compensation(-0.5, look_az, zero(Vec3)) == (0.0, 0.0)
        # LINEAR in the estimate AND in the body rate (the model's whole content).
        @test radome_compensation(-0.20, look_az, Vec3(0.0, 1.0, 1.0))[2] ≈
              2 * radome_compensation(-0.10, look_az, Vec3(0.0, 1.0, 1.0))[2] atol = 1e-15
        @test radome_compensation(-0.10, look_az, Vec3(0.0, 2.0, 2.0))[1] ≈
              2 * radome_compensation(-0.10, look_az, Vec3(0.0, 1.0, 1.0))[1] atol = 1e-15
        # ⚠ AND THE RESIDUAL IS WHAT SURVIVES: compensating with R̂ leaves exactly the parasitic
        # rate of a radome of slope (R − R̂). THIS is the slice's headline expressed on the kernel —
        # the STABILITY BOUNDARY's variable, and the reason a MISMATCHED estimate is the design
        # case rather than an afterthought. ⚠ It is a boundary, NOT an equivalent radome: the
        # LOS-driven half of the bend survives (gate-0 P3B) — see the docstring.
        for R̂ in (0.0, -0.05, -0.10, -0.15)
            ω = Vec3(0.0, -0.8, 0.4)
            ėa_p, ėe_p = eps_dot(ω)
            Δa,   Δe   = radome_compensation(R̂, look_az, ω)
            ėa_r, ėe_r = eps_dot_slope(R - R̂, ω)            # a BARE radome at the residual slope
            @test abs((ėe_p + Δe) - ėe_r) < 2e-4             # ELEVATION: EXACTLY the residual slope
            # ⚠ AZIMUTH is the residual slope PLUS the uncancelled cross-term, and the gap is
            # EXACTLY `R̂·k_cross·ω_y` — pinned rather than tolerated, so the approximation is
            # characterized instead of merely surviving. ⇒ on the loop-closing axis compensation IS
            # a slope offset; on the other axis it is a slope offset plus a known second-order term.
            @test ((ėa_p + Δa) - ėa_r) ≈ R̂ * k_cross * ω[2] atol = 2e-4
        end
    end

    @testset "radome slope CURVE — the DERIVATIVE identity (slice 28)" begin
        # ⭐ THE TOOTH THAT IS THE SLICE: `radome_error_curve` is the EXACT integral of
        # `radome_slope_curve`, so finite-differencing the shipped BEND must reproduce the shipped
        # SLOPE. This pins the two kernels TO EACH OTHER rather than restating either formula —
        # and it is what makes "the parasitic loop follows the DERIVATIVE, not the bend" a
        # statement about the shipped code instead of about the plan.
        R₀, A, k = -0.03, -0.05, 12.0
        h = 1.0e-6
        for u in (0.0, 0.05, 0.15, 0.262, 0.40, -0.20, -0.45)
            fd = (radome_error_curve(R₀, A, k, u + h, 0.0)[1] -
                  radome_error_curve(R₀, A, k, u - h, 0.0)[1]) / (2h)
            @test fd ≈ radome_slope_curve(R₀, A, k, u) atol = 1e-8
        end
        # the SAME identity on the ELEVATION axis (the curve is applied per angle, not to a
        # magnitude — a kernel that curved only azimuth would pass every azimuth-only test)
        for u in (0.10, -0.30)
            fd = (radome_error_curve(R₀, A, k, 0.0, u + h)[2] -
                  radome_error_curve(R₀, A, k, 0.0, u - h)[2]) / (2h)
            @test fd ≈ radome_slope_curve(R₀, A, k, u) atol = 1e-8
        end

        # ⭐ `R(0) == slope0` EXACTLY for EVERY amplitude — the ripple term vanishes identically at
        # boresight. This is not a convenience: it is the MECHANISM of the slice's central
        # asymmetry (characterizing at boresight measures a number STRUCTURALLY insensitive to the
        # curve, hence exactly right in the one place the loop is never closed).
        for Aa in (0.0, -0.02, -0.05, -0.10, +0.07)
            @test radome_slope_curve(R₀, Aa, k, 0.0) === Float64(R₀)
        end

        # BOUNDEDNESS — the property that killed the cubic. R ∈ [R₀, R₀+2A] over any look sweep.
        let lo = min(R₀, R₀ + 2A), hi = max(R₀, R₀ + 2A)
            for u in range(-1.0, 1.0; length = 101)
                Ru = radome_slope_curve(R₀, A, k, u)
                @test lo - 1e-12 ≤ Ru ≤ hi + 1e-12
            end
        end

        # ODDNESS of the bend (a SYMMETRIC radome) — bit-for-bit, PAIRED with a does-curve case.
        for u in (0.13, 0.37, 0.62)
            @test radome_error_curve(R₀, A, k, u, 0.0)[1] ==
                  -radome_error_curve(R₀, A, k, -u, 0.0)[1]
        end
        @test radome_error_curve(R₀, A, k, 0.30, 0.0)[1] != radome_error_curve(R₀, 0.0, k, 0.30, 0.0)[1]

        # ⚠ THE REDUCTION, BIT-FOR-BIT: amplitude 0 IS slice 26's linear kernel. That exactness is
        # what makes `ripple` a KNOB rather than a fidelity rung (atmosphere.jl's discriminator —
        # MEASURED, not argued). ⚠ The SEAM still branches: `x + 0.0` is not the identity at
        # x = −0.0 and float addition is not associative, so the shipped no-ripple path calls
        # `radome_error` verbatim rather than relying on this.
        for (ua, ue) in ((0.31, -0.22), (0.0, 0.0), (-0.45, 0.18))
            @test radome_error_curve(-0.10, 0.0, k, ua, ue) == radome_error(-0.10, ua, ue)
        end
        # k is FLOORED at the consumer, so a zero/negative k cannot divide-by-zero a live tick
        # (convention 5 — the slice-21 scale-height precedent). Finite, not necessarily meaningful.
        @test all(isfinite, radome_error_curve(R₀, A, 0.0, 0.3, -0.2))
        @test all(isfinite, radome_error_curve(R₀, A, -5.0, 0.3, -0.2))
    end

    @testset "THE PARASITIC GAIN MOVES WITH LOOK ANGLE (slice 28; the #1 SIGN TRAP's 10th)" begin
        # ⚠⚠ THE TOOTH MUST BE MEASURED AT **TWO DIFFERENT LOOK ANGLES**. A frozen-geometry test at
        # ONE look angle passes for a CONSTANT-slope kernel too and would prove nothing — the whole
        # claim of slice 28 is that the coefficient MOVES. So: same frozen geometry as slices 26/27
        # (target, missile and true LOS all still, only the attitude rotating — slice 26's P7A: a
        # parasitic gain cannot be measured on a tracking missile), two DIFFERENT boresights, and
        # the measured coefficient must match `radome_slope_curve` AT EACH.
        R₀, A, k = -0.03, -0.05, 12.0
        dt = 1.0e-5
        û  = los_unit(Vec3(0.0, 0.0, 3000.0), Vec3(6000.0, 2000.0, 4200.0))

        # ε̇_el under a pitch rate, with the missile's nose PRE-ROTATED by `yaw0` so the LOS sits at
        # a chosen look angle. Finite difference of the SHIPPED curve kernel.
        function gain_at(yaw0::Float64)
            q0 = quat_from_axis_angle(Vec3(0.0, 0.0, 1.0), yaw0)
            ω  = Vec3(0.0, -1.0, 0.0)                       # nose UP is a −y rotation (slice 23)
            q1 = qnormalize(qmul(q0, quat_from_axis_angle(ω, norm3_test(ω) * dt)))
            a0, e0 = radome_error_curve(R₀, A, k, look_angles(q0, û)...)
            a1, e1 = radome_error_curve(R₀, A, k, look_angles(q1, û)...)
            laz, lel = look_angles(q0, û)
            return ((e1 - e0) / dt, laz, lel)
        end

        # TWO look angles, chosen either side of the ripple's first extremum (peak at k·look = π,
        # i.e. look = 0.262 rad = 15°): the coefficient must DIFFER, and match the curve at each.
        ėe_a, laz_a, lel_a = gain_at(0.0)    # LOS sits at its natural azimuth off the nose
        ėe_b, laz_b, lel_b = gain_at(-0.45)  # nose yawed away ⇒ a much larger look azimuth
        @test !(laz_a ≈ laz_b)                                   # the two probes really do differ
        # ⭐ SLICE 26's LAW WITH `R` → `R(look)`: a pure PITCH rate moves `look_el`, so the
        # ELEVATION coefficient is the curve's slope AT `look_el`, scaled by cos(look_az).
        # ⚠ THIS ASSERT WAS FIRST WRITTEN WITH `R(0)` IN PLACE OF `R(look_el)` — on the assumption
        # that this frozen geometry has `look_el ≈ 0`. IT DOES NOT (`look_el` = 0.187 rad), and the
        # test caught it: 0.1055 measured against 0.0285 predicted, ~3.7× out. The kernel was
        # right and the expectation was wrong — which is exactly the failure mode a
        # "restate the formula" tooth would have hidden.
        @test ėe_a ≈ radome_slope_curve(R₀, A, k, lel_a) * cos(laz_a) * (-1.0) atol = 2e-5
        @test ėe_b ≈ radome_slope_curve(R₀, A, k, lel_b) * cos(laz_b) * (-1.0) atol = 2e-5
        # A yaw pre-rotation leaves ELEVATION untouched (a rotation about ẑ preserves it), so the
        # two pitch coefficients share `R(look_el)` and differ ONLY through cos(look_az). The
        # AZIMUTH channel below is the one that moves along the CURVE — that IS the channel split.
        @test lel_a ≈ lel_b atol = 1e-12
        @test ėe_a ≉ ėe_b                                        # cos(look_az) alone already moves it

        # ⭐ THE AZIMUTH CHANNEL IS WHERE THE CURVE BITES, and this is the assert that a
        # constant-slope kernel CANNOT pass: under a pure YAW rate the coefficient is the curve's
        # slope AT THE LOOK AZIMUTH, so it must MOVE between the two probes and match at each.
        function gain_az_at(yaw0::Float64)
            q0 = quat_from_axis_angle(Vec3(0.0, 0.0, 1.0), yaw0)
            ω  = Vec3(0.0, 0.0, 1.0)
            q1 = qnormalize(qmul(q0, quat_from_axis_angle(ω, norm3_test(ω) * dt)))
            a0, _ = radome_error_curve(R₀, A, k, look_angles(q0, û)...)
            a1, _ = radome_error_curve(R₀, A, k, look_angles(q1, û)...)
            laz, _ = look_angles(q0, û)
            return ((a1 - a0) / dt, laz)
        end
        ėa_a, laz_a2 = gain_az_at(0.0)
        ėa_b, laz_b2 = gain_az_at(-0.45)
        @test ėa_a ≈ -radome_slope_curve(R₀, A, k, laz_a2) atol = 2e-5
        @test ėa_b ≈ -radome_slope_curve(R₀, A, k, laz_b2) atol = 2e-5
        # THE HEADLINE, ON THE KERNEL: the two coefficients are NOT the same number, and their
        # ratio is the ratio of the curve at the two look angles — the same glass, two engagements.
        @test abs(ėa_a - ėa_b) > 0.01
        @test (ėa_a / ėa_b) ≈ radome_slope_curve(R₀, A, k, laz_a2) /
                              radome_slope_curve(R₀, A, k, laz_b2) atol = 5e-3
        # PAIRED CONTROL: with amplitude 0 the SAME two probes give the SAME coefficient — which is
        # exactly why a one-look-angle test proves nothing.
        let g(y) = begin
                q0 = quat_from_axis_angle(Vec3(0.0, 0.0, 1.0), y)
                q1 = qnormalize(qmul(q0, quat_from_axis_angle(Vec3(0.0, 0.0, 1.0), dt)))
                (radome_error_curve(R₀, 0.0, k, look_angles(q1, û)...)[1] -
                 radome_error_curve(R₀, 0.0, k, look_angles(q0, û)...)[1]) / dt
            end
            @test g(0.0) ≈ g(-0.45) atol = 2e-5
        end
    end

    @testset "the SCHEDULED compensator — its SLOPE, and its INDEX (slice 29)" begin
        R₀, A, k = -0.03, -0.15, 12.0
        û  = los_unit(Vec3(0.0, 0.0, 3000.0), Vec3(6000.0, 2000.0, 4200.0))
        look_az, _ = look_angles(Quat(1, 0, 0, 0), û)

        # ⭐ THE DERIVATIVE IDENTITY — the sibling of slice 28's integral identity, and what makes
        # "the schedule's own slope" a statement about the SHIPPED code rather than about the plan.
        # `radome_schedule_slope` must BE the derivative of the belief `radome_slope_curve` builds,
        # so finite-difference the one and compare to the other. Pins the two kernels TO EACH OTHER
        # rather than restating either formula (convention 11).
        h = 1.0e-6
        for u in (0.0, 0.05, 0.15, 0.262, 0.40, -0.20, -0.45)
            fd = (radome_slope_curve(R₀, A, k, u + h) -
                  radome_slope_curve(R₀, A, k, u - h)) / (2h)
            @test fd ≈ radome_schedule_slope(A, k, u) atol = 1e-6
        end
        # ⭐ AND IT IS ZERO AT THE CURVE'S OWN EXTREMUM — the fact that makes the first-order form
        # fail exactly at `k̂ = k` on this wire (gate-0 P10c: −0.001 predicted vs −0.022 actual), and
        # therefore the reason the shipped claim quotes the index-shifted RESIDUAL and uses this
        # only as the sensitivity that explains it.
        @test radome_schedule_slope(A, k, π / k) ≈ 0.0 atol = 1e-15   # look = 15° at k = 12
        @test radome_schedule_slope(A, k, 0.0) === -0.0 ||
              radome_schedule_slope(A, k, 0.0) == 0.0
        # slice 27's scalar has NO slope, at any look angle — the whole reason it never had to
        # choose an index. PAIRED with a does-vary case so it cannot pass by producing zero.
        for u in (0.0, 0.12, 0.26, 0.44)
            @test radome_schedule_slope(0.0, k, u) == 0.0
        end
        @test radome_schedule_slope(A, k, 0.12) != 0.0

        # ⚠ THE REDUCTION, BIT-FOR-BIT: amplitude 0 IS slice 27's kernel, at every look angle and
        # every body rate. That exactness is what makes `Â` a KNOB and not a fidelity rung
        # (atmosphere.jl's discriminator — MEASURED, not argued), PAIRED with a does-schedule case.
        for (ua, ue) in ((0.31, -0.22), (0.0, 0.0), (-0.45, 0.18))
            for ω in (Vec3(0.0, -0.8, 0.4), Vec3(0.3, -0.7, 0.5), zero(Vec3))
                @test radome_compensation_scheduled(-0.03, 0.0, k, ua, ue, ω) ==
                      radome_compensation(-0.03, ua, ω)
            end
        end
        @test radome_compensation_scheduled(-0.03, A, k, 0.31, -0.22, Vec3(0.0, -0.8, 0.4)) !=
              radome_compensation(-0.03, 0.31, Vec3(0.0, -0.8, 0.4))

        # ⭐ PER AXIS — slice 28's gate-2 hardening applied to the COMPENSATOR. The two channels must
        # take the belief at THEIR OWN look angle. A kernel using one value at `hypot(look_az,
        # look_el)` — or `look_az` for both — agrees numerically whenever `look_el ≈ 0`, which is
        # exactly the wire this slice ships, so assert it at angles where they differ a lot.
        let ua = 0.262, ue = -0.40                      # az at the ripple PEAK, el far from it
            R̂a = radome_slope_curve(-0.03, A, k, ua)
            R̂e = radome_slope_curve(-0.03, A, k, ue)
            @test !(R̂a ≈ R̂e)                            # the probe really does separate them
            Δa, Δe = radome_compensation_scheduled(-0.03, A, k, ua, ue, Vec3(0.0, 1.0, 1.0))
            @test Δa ≈ R̂a atol = 1e-15                  # yaw channel: the AZIMUTH belief, no cosine
            @test Δe ≈ -R̂e * cos(ua) atol = 1e-15       # pitch channel: the ELEVATION belief
            @test Δe ≉ -R̂a * cos(ua)                    # ⇐ fails if the azimuth belief is reused
            # and the axis split itself (slice 27's tooth shape, inherited)
            @test radome_compensation_scheduled(-0.03, A, k, ua, ue, Vec3(0.0, 0.0, 1.0))[2] == 0.0
            @test radome_compensation_scheduled(-0.03, A, k, ua, ue, Vec3(0.0, 1.0, 0.0))[1] == 0.0
        end

        # ⭐⭐ THE INDEX TOOTH — THE #1 SIGN TRAP's 11th OCCURRENCE, AND THE SLICE ITSELF.
        # Evaluating the schedule at a BENT index instead of the truth one perturbs the correction
        # by ≈ R̂'·δ, and the SIGN of that perturbation must FLIP between a `k̂` below the true `k`
        # and one above — because `R̂'` does. ⚠ A test at ONE `k̂` passes for a constant-slope
        # compensator and proves nothing (slice 28's two-look-angles rule, transposed to `k̂`).
        # This is the kernel-level statement of the measured result that a schedule which is a
        # BETTER model of the glass can ring while a worse one stays quiet.
        let u_true = π / k, δ = deg2rad(-2.6)           # 15°, and the MEASURED index error on the wire
            ω = Vec3(0.0, 0.0, 1.0)                     # pure yaw ⇒ read the azimuth channel
            function shift(k̂)
                tru = radome_compensation_scheduled(R₀, A, k̂, u_true,     0.0, ω)[1]
                ben = radome_compensation_scheduled(R₀, A, k̂, u_true + δ, 0.0, ω)[1]
                return ben - tru
            end
            # ⚠ THE SIGNS HERE WERE WRITTEN BACKWARDS ON THE FIRST DRAFT AND THE TEST CAUGHT IT
            # (the trap's 11th occurrence claiming its first victim in this slice): the shift is in
            # the BELIEF `R̂`, and the residual `R − R̂` moves the OTHER WAY. Under-estimating `k̂`
            # RAISES `R̂` at a smaller index ⇒ the residual goes MORE NEGATIVE ⇒ closer to ringing,
            # which is the measured direction (gate-0 P10c: `k̂` = 10's residual −0.041 → −0.067).
            @test shift(10.0) > +0.01                   # k̂ BELOW k: the belief applied is LESS steep
            @test shift(17.0) < -0.01                   # k̂ ABOVE k: MORE steep
            @test sign(shift(10.0)) != sign(shift(17.0))          # the flip, stated as such
            # and each matches the first-order sensitivity AWAY from the extremum. ⚠ The atols are
            # WIDE ON PURPOSE and they are the docstring's caveat as a number: over a 2.6° step the
            # second-order term is already 25–30% of the first-order one, which is precisely why the
            # shipped claim quotes the exact index-shifted RESIDUAL and uses `R̂'` only to explain it.
            @test shift(10.0) ≈ radome_schedule_slope(A, 10.0, u_true) * δ atol = 1.5e-2
            @test shift(17.0) ≈ radome_schedule_slope(A, 17.0, u_true) * δ atol = 2.5e-2
            # ⚠ AND AT k̂ = k THE FIRST-ORDER TERM VANISHES EXACTLY while the ACTUAL shift does not —
            # the second-order term, pinned so the docstring's caveat is a tested statement rather
            # than a hedge. The measured wire agrees: a residual of −0.022 where first order says 0.
            @test abs(radome_schedule_slope(A, k, u_true)) < 1e-14   # exactly the extremum
            @test abs(shift(k)) > 1e-3                               # yet the shift is REAL
            @test shift(k) ≈ 0.5 * (A * k^2 * cos(k * u_true)) * δ^2 atol = 2e-3   # ⇐ it is 2nd order
            # a CONSTANT belief cannot be shifted by its index at all — the paired control that
            # makes every assert above about SCHEDULING rather than about compensation.
            let tru = radome_compensation(R₀, u_true, ω)[1],
                ben = radome_compensation(R₀, u_true + δ, ω)[1]
                @test ben == tru
            end
        end

        # THE CANCELLATION still holds when the belief MATCHES the glass and both are read at the
        # SAME angle — slice 27's tooth, re-run against the CURVE kernels so the scheduled law is
        # pinned to the physics it claims to cancel, not merely to its own formula.
        let dt = 1.0e-3
            function eps_dot_curve(ω::Vec3)
                q0 = Quat(1.0, 0.0, 0.0, 0.0)
                q1 = qnormalize(qmul(q0, quat_from_axis_angle(ω, norm3_test(ω) * dt)))
                a0, e0 = radome_error_curve(R₀, A, k, look_angles(q0, û)...)
                a1, e1 = radome_error_curve(R₀, A, k, look_angles(q1, û)...)
                return ((a1 - a0) / dt, (e1 - e0) / dt)
            end
            laz, lel = look_angles(Quat(1, 0, 0, 0), û)
            for ω in (Vec3(0.0, -1.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, -0.6, 0.8))
                _, ėe_p = eps_dot_curve(ω)
                _, Δe   = radome_compensation_scheduled(R₀, A, k, laz, lel, ω)
                @test abs(ėe_p + Δe) < 2e-3            # ELEVATION: cancelled against the CURVE
            end
        end

        # k̂ is not divided by anywhere (unlike `radome_error_curve`'s `ripple/k`), but a live slider
        # must still never produce a non-finite correction (conventions 5/6).
        @test all(isfinite, radome_compensation_scheduled(R₀, A, 0.0, 0.3, -0.2, Vec3(1.0, 1.0, 1.0)))
        @test all(isfinite, radome_compensation_scheduled(R₀, A, -5.0, 0.3, -0.2, Vec3(1.0, 1.0, 1.0)))
        @test isfinite(radome_schedule_slope(A, 0.0, 0.3))
    end

    @testset "the WORST-CASE SLOPE — a BOUND on the curve, in both signs (slice 30)" begin
        # ⭐ THE TOOTH IS AGAINST THE CURVE, NOT AGAINST THE FORMULA (convention 11: an INDEPENDENT
        # recompute as the oracle). `radome_slope_worst` claims to be the minimum of
        # `radome_slope_curve` over ALL look angles, so the oracle is a DENSE SWEEP of that kernel —
        # which is the thing slice 30's design rule actually needs to be true, and a `min` written
        # the other way round (or a `+2A` with no `min`) fails it on one of the two signs.
        for (R₀, A, k) in ((-0.03, -0.15, 12.0), (-0.03, -0.20, 12.0), (0.02, -0.10, 6.0),
                           (-0.03, +0.09, 12.0), (0.05, +0.20, 4.0), (-0.10, 0.0, 12.0))
            # a full period of the ripple, so the extremum at `k·look = π` is genuinely reached
            sweep = [radome_slope_curve(R₀, A, k, u) for u in range(0.0, 2π / k; length = 4001)]
            @test radome_slope_worst(R₀, A) ≈ minimum(sweep) atol = 1e-9
            @test radome_slope_worst(R₀, A) ≤ minimum(sweep) + 1e-9      # it is a BOUND: never above
        end

        # ⚠⚠ THE TWO SIGNS SPLIT, AND THAT IS WHY IT IS A `min` AND NOT THE LITERAL `R₀+2A`. Inside
        # slice 30's `A ∈ [−0.20, 0]` knob domain the two agree exactly (first pair); for a POSITIVE
        # authored amplitude — a meaningful configuration here, since positive slopes DE-TUNE rather
        # than ring (slice 26) — `R₀+2A` is the most POSITIVE slope, i.e. the maximally de-tuned aim
        # point, which would INVERT the one-sided rule this kernel exists to serve.
        # ⚠ pinned against the EXPRESSION `R₀+2A`, not against the decimal −0.33: the sum is
        # −0.32999999999999996 in Float64, so a literal would be asserting float formatting rather
        # than the identity (and `≈` here would hide which of the two branches was taken).
        @test radome_slope_worst(-0.03, -0.15) === -0.03 + 2 * -0.15      # == R₀+2A (the knob domain)
        @test radome_slope_worst(-0.03, +0.15) === -0.03                  # == R₀ — NOT R₀+2A = +0.27
        @test radome_slope_worst(-0.03, +0.15) != -0.03 + 2 * 0.15        # the paired does-differ case

        # `A = 0` gives EXACTLY `R₀` — the flat glass's only slope, and the boresight scalar's own
        # target: the off-state is knob-reachable (the KNOB-not-rung discriminator, as everywhere in
        # this family). Bit-exact, not `≈`.
        for R in (0.0, -0.03, -0.30, +0.06, -0.0)
            @test radome_slope_worst(R, 0.0) === Float64(R)
        end

        # MONOTONE in the glass depth over the shipped domain — the "price of the identical guarantee"
        # half of the slice needs the aim point to MOVE with A, and to move DOWN (deeper glass ⇒ a
        # more negative scalar ⇒ more de-tune). A rule that stalled would make the two bounds
        # incomparable.
        let ws = [radome_slope_worst(-0.03, A) for A in (0.0, -0.05, -0.10, -0.15, -0.20)]
            @test issorted(ws; rev = true)
            @test ws[end] < ws[1]
        end

        # conventions 5/6 — the live-slider guard. Both arguments are load-validated finite, but the
        # kernel must not manufacture a non-finite from finite input at any magnitude.
        @test isfinite(radome_slope_worst(-1.0e6, -1.0e6))
        @test isfinite(radome_slope_worst(0.0, -1.0e-300))
    end

    @testset "AN IMPERFECT GYRO — two error terms, two currencies (slice 31)" begin
        # The kernel is three lines; what has to be pinned is that its two terms enter the
        # FEED-FORWARD differently, because that split is the whole slice.
        ω = Vec3(0.3, -0.7, 0.45)

        # ⭐ THE REPARAMETERIZATION, AND IT IS PINNED AS AN `atol` — NEVER AS BIT-IDENTITY. A
        # common-mode scale factor is common-mode on the product `R̂·ω̃`, so the belief that reaches
        # the loop is exactly `R̂(1+s)`. ⚠ `R̂·((1+s)·ω)` and `(R̂·(1+s))·ω` differ in the last ULP by
        # float non-associativity, so a `===` here would be a FALSE claim about the same physics
        # (gate 0 measured both: two of five wire pairs came out bit-identical and three did not).
        for (R̂, s) in ((-0.27, -0.05), (-0.33, -0.20), (-0.03, +1.00), (-0.45, +0.30))
            with_err = radome_compensation(R̂, 0.31, gyro_reading(ω, s, zero(Vec3)))
            as_belief = radome_compensation(R̂ * (1 + s), 0.31, ω)
            @test with_err[1] ≈ as_belief[1] atol = 1e-15
            @test with_err[2] ≈ as_belief[2] atol = 1e-15
        end
        # …and the PAIRED does-differ case: without the scale factor the two are NOT the same
        # correction (a test that only checks the equivalence passes for a kernel that ignores `s`).
        @test radome_compensation(-0.27, 0.31, gyro_reading(ω, -0.05, zero(Vec3)))[1] !=
              radome_compensation(-0.27, 0.31, ω)[1]

        # ⭐⭐ THE BIAS IS NOT A BELIEF ERROR — the split that makes the two terms different currencies.
        # No `R̂′` whatsoever reproduces a biased reading, because the bias contributes a term that
        # does NOT scale with ω: at ω = 0 the scale factor produces EXACTLY nothing while the bias
        # still injects `R̂·b`. That is the additive-vs-multiplicative distinction, as a tooth.
        let b = Vec3(0.0, 0.0, 0.02)
            @test gyro_reading(zero(Vec3), -0.5, zero(Vec3)) == zero(Vec3)          # scale: nothing
            @test gyro_reading(zero(Vec3), 0.0, b)[3] == 0.02                       # bias: something
            @test radome_compensation(-0.33, 0.31, gyro_reading(zero(Vec3), 0.0, b))[1] ==
                  -0.33 * 0.02                                                      # the injection
            @test radome_compensation(-0.33, 0.31, gyro_reading(zero(Vec3), -0.5, zero(Vec3)))[1] == 0.0
        end

        # THE AXIS SPLIT (gate-0 P6, and slice 27's own axis-asymmetry tooth inherited): `b_z` drives
        # the AZIMUTH correction ONLY and `b_y` the ELEVATION correction ONLY. A kernel that put the
        # bias on the wrong axis, or on both, still cancels at ω = 0 and would pass a magnitude test.
        let Δz = radome_compensation(-0.33, 0.31, gyro_reading(zero(Vec3), 0.0, Vec3(0.0, 0.0, 0.05))),
            Δy = radome_compensation(-0.33, 0.31, gyro_reading(zero(Vec3), 0.0, Vec3(0.0, 0.05, 0.0)))
            @test Δz[1] != 0.0 && Δz[2] == 0.0
            @test Δy[2] != 0.0 && Δy[1] == 0.0
        end

        # ⚠ THE DEAD GYRO `s = −1`: the reading collapses to the bias alone, the feed-forward vanishes
        # with it, and the missile IS slice 26's uncompensated missile. Measured bit-identical on the
        # wire at gate 0 (max|Δpos| = 0.0 against `R̂ = 0`), so it is pinned bit-exact here too.
        @test gyro_reading(ω, -1.0, zero(Vec3)) == zero(Vec3)
        @test radome_compensation(-0.33, 0.31, gyro_reading(ω, -1.0, zero(Vec3))) ==
              radome_compensation(0.0, 0.31, ω)

        # The KNOB-not-rung discriminator (atmosphere.jl's): the off-state is knob-reachable and EXACT.
        # ⚠ Bit-exact componentwise, and it must hold for a NEGATIVE zero component too (the `-0.0`
        # trap) — which is precisely why the shipped seam still BRANCHES upstream rather than calling
        # this at zero.
        for v in (ω, Vec3(0.0, -0.0, 0.0), Vec3(-1e-300, 0.0, 1e6))
            @test gyro_reading(v, 0.0, zero(Vec3)) == v
        end

        # …and it is not vacuous: a non-zero `s` or `b` DOES move the reading (the paired does-perturb).
        @test gyro_reading(ω, 0.01, zero(Vec3)) != ω
        @test gyro_reading(ω, 0.0, Vec3(0.0, 0.0, 1e-6)) != ω

        # The scale factor is COMMON-MODE across all three axes (a §1 named approximation — per-axis
        # scale factors and misalignment are a named deferral). Pin the ratio, not just the change.
        let g = gyro_reading(ω, 0.25, zero(Vec3))
            for i in 1:3
                @test g[i] ≈ 1.25 * ω[i] atol = 1e-15
            end
        end

        # conventions 5/6 — a live slider can never make this manufacture a non-finite from finite
        # input, at any magnitude either knob's domain can reach (and well beyond it).
        @test all(isfinite, gyro_reading(Vec3(1e6, -1e6, 1e6), -1.0e3, Vec3(1e6, 1e6, 1e6)))
        @test all(isfinite, gyro_reading(zero(Vec3), -1.0, zero(Vec3)))
    end

    @testset "SEEKER_AXES_MODES — the one-list-no-drift const (convention 7)" begin
        @test SEEKER_AXES_MODES == (:pitch_plane, :az_el)
        @test :az_el in SEEKER_AXES_MODES && :pitch_plane in SEEKER_AXES_MODES
        # it is a SEPARATE key from SEEKER_MODES (the tracker), NOT a fourth rung of it
        @test isempty(intersect(SEEKER_AXES_MODES, SEEKER_MODES))
    end

    # --- SLICE 32 — THE SEEKER'S FIELD OF VIEW (§11 Tier-A) -------------------------------
    #
    # The window (`boresight_angle` / `seeker_in_fov`) and the ENGAGEMENT that sets it
    # (`collision_lead_angle`). ⚠ WHAT THESE TESTS DO NOT PROVE, deliberately: that the look
    # angle EQUALS the collision lead. That is a statement about a flying missile — the two
    # differ by the aerodynamic incidence (α/β), MEASURED at −0.06…+0.03° against a ~29° lead
    # on the shipped wire (gate-0 §5) — and it needs a wire, so it is gate 3's, not gate 1's.
    # What gate 1 owns is that each kernel is the quantity it claims to be.
    @testset "seeker FOV (slice 32) — the window, and the engagement that sets it" begin

        exact_cone(q, los) = acos(clamp(rotate_inv(q, los)[1], -1.0, 1.0))   # the INDEPENDENT
        rect_in(q, los, f) = maximum(abs.(look_angles(q, los))) ≤ f          # angle + the FOIL

        @testset "boresight_angle — the total off-boresight angle" begin
            # the degenerate: the nose pointing straight at the target reads EXACTLY zero
            @test boresight_angle(id, Vec3(1.0, 0.0, 0.0)) === 0.0
            # and it is the angle-space RADIUS of the look angles (the definitional pin)
            for (a, e) in ((0.2, -0.1), (-0.4, 0.35), (0.9, 0.0), (0.0, -0.8))
                û = los_unit_from_angles(a, e)
                @test boresight_angle(id, û) ≈ hypot(a, e) atol = 1e-12
            end

            # ⚠ THE §1 APPROXIMATION, MEASURED IN BOTH DIRECTIONS. The radius equals the EXACT
            # cone half-angle `acos(u_body[1])` on either axis plane, and OVERSTATES it off them.
            ψ = deg2rad(30.0)
            for û in (Vec3(cos(ψ),  sin(ψ), 0.0),        # pure azimuth  (clock  0°)
                      Vec3(cos(ψ), -sin(ψ), 0.0),        # pure azimuth  (clock 180°)
                      Vec3(cos(ψ), 0.0,  sin(ψ)),        # pure elevation (clock  90°)
                      Vec3(cos(ψ), 0.0, -sin(ψ)))        # pure elevation (clock 270°)
                @test boresight_angle(id, û) ≈ exact_cone(id, û) atol = 1e-12
                @test boresight_angle(id, û) ≈ ψ atol = 1e-12
            end
            # off the axes it is LARGER — never smaller — and the excess peaks near a 45° clock
            # angle at +0.364° for a true 30° cone (measured; the number bounds the approximation)
            excess = Float64[]
            for φd in 0.0:1.0:360.0
                φ = deg2rad(φd)
                û = Vec3(cos(ψ), sin(ψ) * cos(φ), sin(ψ) * sin(φ))
                push!(excess, boresight_angle(id, û) - exact_cone(id, û))
            end
            @test minimum(excess) ≥ -1e-15                       # NEVER under-reports
            @test rad2deg(maximum(excess)) ≈ 0.3642 atol = 5e-4  # and by at most this much
            let φ = deg2rad(47.0), û = Vec3(cos(ψ), sin(ψ)*cos(φ), sin(ψ)*sin(φ))
                @test boresight_angle(id, û) - exact_cone(id, û) ≈ maximum(excess) atol = 1e-6
            end

            # ⚠⚠ AND IT IS NOT BOUNDED BY π — the counterexample that keeps anyone from writing
            # "180° is the whole sphere". The supremum is hypot(π, π/2) ≈ 201.246°.
            û_corner = los_unit_from_angles(deg2rad(180.0), deg2rad(20.0))
            @test rad2deg(boresight_angle(id, û_corner)) ≈ 181.108 atol = 1e-3
            @test boresight_angle(id, û_corner) > π
            @test !seeker_in_fov(id, û_corner, π)                # a 180° window REJECTS it
            @test  seeker_in_fov(id, û_corner, hypot(π, π/2))    # the true sup admits it
            let sup = 0.0
                for azd in -180.0:1.0:180.0, eld in -90.0:1.0:90.0
                    sup = max(sup, boresight_angle(id, los_unit_from_angles(deg2rad(azd),
                                                                            deg2rad(eld))))
                end
                @test sup ≤ hypot(π, π/2) + 1e-12
                @test rad2deg(sup) ≈ 201.246 atol = 1e-2
            end

            # ⭐ ROTATION INVARIANCE (the transpose / frame-error catch, and the stochastic half
            # of convention 1 — there is nothing else random to test here). Rotating the WHOLE
            # configuration must not move the angle: the body-frame LOS is unchanged, so the
            # radius is too. Its own Xoshiro, never `w.rng` (convention 11). ⚠ Note this is NOT
            # invariance under ROLL about the boresight — the radius genuinely varies with the
            # clock angle (the excess sweep above IS that variation).
            let rng = Xoshiro(3232), dev_comp = 0.0, dev_inv = 0.0, spread = 0.0
                for _ in 1:400
                    att = qnormalize(quat_from_axis_angle(Vec3(randn(rng), randn(rng),
                                                               randn(rng)), 3.0 * randn(rng)))
                    los = let v = Vec3(randn(rng), randn(rng), randn(rng))
                        v / sqrt(v[1]^2 + v[2]^2 + v[3]^2)
                    end
                    g = qnormalize(quat_from_axis_angle(Vec3(randn(rng), randn(rng),
                                                              randn(rng)), 3.0 * randn(rng)))
                    # `qmul(g, att)` is the composition R(g)·R(att) — pinned here, not assumed
                    dev_comp = max(dev_comp, maximum(abs.(rotate(qmul(g, att), los) .-
                                                          rotate(g, rotate(att, los)))))
                    b = boresight_angle(att, los)
                    dev_inv = max(dev_inv, abs(boresight_angle(qmul(g, att), rotate(g, los)) - b))
                    spread = max(spread, b)
                end
                @test dev_comp ≤ 1e-12
                @test dev_inv  ≤ 1e-12
                @test spread   > 2.0      # the sweep really did reach wide angles, not just small
            end
        end

        @testset "seeker_in_fov — the predicate, its boundary and its degenerates" begin
            q = quat_from_axis_angle(Vec3(0.3, 1.0, -0.4), 0.35)
            û = los_unit_from_angles(0.21, -0.13)

            # ⚠ THE `≤` BOUNDARY, PINNED WITHOUT A TOLERANCE — built BACKWARDS from the kernel,
            # because no float LOS lands bit-exactly on `deg2rad(25.0)`.
            let b = boresight_angle(q, û)
                @test  seeker_in_fov(q, û, b)              # x ≤ x, exact by construction
                @test !seeker_in_fov(q, û, prevfloat(b))   # one ULP tighter REJECTS
                @test  seeker_in_fov(q, û, nextfloat(b))
            end

            # ⭐ THE CIRCULAR-vs-RECTANGULAR DISCRIMINATOR — the tooth that kills a per-axis
            # implementation. At (0.8f, 0.8f) the radius is 1.131·f (OUT of a circular window)
            # while `max(|az|,|el|)` is 0.8·f (IN a rectangular one): the two windows DISAGREE,
            # and the assert says which one ships. PAIRED with (0.6f, 0.6f), where the radius is
            # 0.849·f and both agree — so this is not merely "everything is out".
            let f = deg2rad(25.0)
                out = los_unit_from_angles(0.8f, 0.8f)
                @test boresight_angle(id, out) ≈ hypot(0.8f, 0.8f) atol = 1e-12
                @test !seeker_in_fov(id, out, f)          # CIRCULAR: outside
                @test  rect_in(id, out, f)                # RECTANGULAR: would be inside
                inn = los_unit_from_angles(0.6f, 0.6f)
                @test  seeker_in_fov(id, inn, f) && rect_in(id, inn, f)   # both agree
            end

            # conventions 5/6 — a live slider can never throw, and `fov ≤ 0` is the DEFINED
            # NEVER-LOCKED state (not a sentinel): only an exactly-on-boresight LOS is admitted.
            @test !seeker_in_fov(id, los_unit_from_angles(1e-9, 0.0), 0.0)
            @test  seeker_in_fov(id, Vec3(1.0, 0.0, 0.0), 0.0)     # boresight_angle === 0.0
            for bad in (-0.0, -1e-9, -1.0, -1e9, -Inf)
                @test !seeker_in_fov(q, û, bad)
                @test  seeker_in_fov(id, Vec3(1.0, 0.0, 0.0), bad) # clamps to 0, never throws
            end
            @test seeker_in_fov(q, û, Inf)
            # ⚠ NaN (slice 33) — a claim about `max`, not a tautology: `max(NaN, 0.0)` PROPAGATES,
            # so both forms are false and the never-locked side stays the defined state. A `max`
            # written the other way round (or an `ifelse` that swallowed it) would admit everything.
            @test !seeker_in_fov(q, û, NaN)
            @test !seeker_in_fov(id, Vec3(1.0, 0.0, 0.0), NaN)

            # THE SEAM'S OWN EXPRESSION (advisor, gate 1): the shipped predicate is THIS kernel,
            # so degrees→radians is the only step `missile.jl` performs, and it does NOT clamp —
            # the clamp has exactly one owner (`seeker_fov_margin`, which this delegates to since
            # slice 33; it was this function's own until then). Both orders agree at every sign.
            for fov_deg in (-5.0, 0.0, 12.5, 25.0, 180.0)
                @test seeker_in_fov(q, û, deg2rad(fov_deg)) ==
                      (boresight_angle(q, û) ≤ deg2rad(max(fov_deg, 0.0)))
            end
        end

        @testset "collision_lead_angle — the ENGAGEMENT's own requirement" begin
            x̂ = Vec3(1.0, 0.0, 0.0)

            # the degenerates: a target running directly along the LOS needs NO lead, either way
            @test collision_lead_angle(300.0, Vec3( 200.0, 0.0, 0.0), x̂) === 0.0   # receding
            @test collision_lead_angle(300.0, Vec3(-200.0, 0.0, 0.0), x̂) === 0.0   # head-on
            @test collision_lead_angle(300.0, zero(Vec3), x̂) === 0.0               # static
            # and the pure crossing is the closed form exactly: asin(100/200) = π/6
            @test collision_lead_angle(200.0, Vec3(0.0, 100.0, 0.0), x̂) ≈ π/6 atol = 1e-15
            @test collision_lead_angle(200.0, Vec3(0.0, 0.0, -100.0), x̂) ≈ π/6 atol = 1e-15

            # ⭐ THE DEFINING RELATION, recomputed by a DIFFERENT algorithm (convention 11):
            # `V_m·sin λ = V_t·sin θ` with θ from `acos(v̂_t·û)` — an angle-domain route where the
            # kernel takes a cross-product one.
            let rng = Xoshiro(32032), dev_rel = 0.0, max_perp = 0.0, λ_lo = Inf, λ_hi = -Inf,
                n_closing = 0, n_planar = 0
                for _ in 1:400
                    û = let v = Vec3(randn(rng), randn(rng), randn(rng))
                        v / sqrt(v[1]^2 + v[2]^2 + v[3]^2)
                    end
                    v_t = Vec3(80.0*randn(rng), 80.0*randn(rng), 80.0*randn(rng))
                    V_t = sqrt(v_t[1]^2 + v_t[2]^2 + v_t[3]^2)
                    V_m = 400.0 + 400.0 * rand(rng)          # fast enough that λ never saturates
                    θ   = acos(clamp((v_t[1]*û[1] + v_t[2]*û[2] + v_t[3]*û[3]) / V_t, -1.0, 1.0))
                    λ   = collision_lead_angle(V_m, v_t, û)
                    dev_rel = max(dev_rel, abs(V_m * sin(λ) - V_t * sin(θ)))
                    λ_lo = min(λ_lo, λ); λ_hi = max(λ_hi, λ)

                    # ⭐⭐ AND IT REALLY IS A COLLISION LEAD, not merely an arcsine: fly the
                    # missile at that lead in the (û, v_t) plane and the relative velocity's
                    # PERPENDICULAR component cancels to zero — checked with the projection
                    # subtraction the kernel deliberately avoids.
                    w = v_t - (v_t[1]*û[1] + v_t[2]*û[2] + v_t[3]*û[3]) * û
                    nw = sqrt(w[1]^2 + w[2]^2 + w[3]^2)
                    if nw > 1e-9
                        n_planar += 1
                        ŵ    = w / nw
                        v_m  = V_m * (cos(λ) * û + sin(λ) * ŵ)
                        rel  = v_t - v_m
                        perp = rel - (rel[1]*û[1] + rel[2]*û[2] + rel[3]*û[3]) * û
                        max_perp = max(max_perp, sqrt(perp[1]^2 + perp[2]^2 + perp[3]^2))
                        # V_m > V_t here ⇒ the geometry CLOSES (negative range rate)
                        (rel[1]*û[1] + rel[2]*û[2] + rel[3]*û[3]) < 0.0 && (n_closing += 1)
                    end
                end
                @test dev_rel  ≤ 1e-9            # the closed form IS `V_m·sin λ = V_t·sin θ`
                @test max_perp ≤ 1e-9            # ...and flying it actually cancels the crossing
                @test n_closing == n_planar == 400
                @test 0.0 ≤ λ_lo && λ_hi < π/2   # never saturated on this (fast-missile) sweep
                @test λ_hi > deg2rad(20.0)       # and the sweep did reach real lead angles
            end

            # ⚠ THE SATURATION SENTINEL, PAIRED — and its meaning is "NO FOV SUFFICES", never
            # "you need 90°". Below the limit it is continuous and strictly interior; at and past
            # it there is no collision course at all and the value is FLAT at exactly π/2, which
            # is why nothing downstream may read it as a requirement number.
            @test collision_lead_angle(100.0, Vec3(0.0, 100.0 * (1 - 1e-9), 0.0), x̂) < π/2
            @test collision_lead_angle(100.0, Vec3(0.0, 100.0 * (1 - 1e-9), 0.0), x̂) >
                  deg2rad(89.99)
            for V_perp in (100.0, 100.0 + 1e-9, 250.0, 1.0e6)
                @test collision_lead_angle(100.0, Vec3(0.0, V_perp, 0.0), x̂) === π/2
            end
            # the zero-speed guard saturates the same way and never divides by zero
            @test collision_lead_angle(0.0, Vec3(0.0, 100.0, 0.0), x̂) === π/2
            @test isfinite(collision_lead_angle(0.0, zero(Vec3), x̂))
            @test all(isfinite, (collision_lead_angle(1e-30, Vec3(1e6, -1e6, 1e6), x̂),
                                 collision_lead_angle(1e9, Vec3(1e-30, 1e-30, 1e-30), x̂)))

            # SPEED, NOT VELOCITY (the signature that keeps "required" from becoming "achieved"):
            # the lead depends only on the target's CROSS-LOS speed, so any along-LOS component
            # is invisible to it — the sharpest statement of what this quantity is.
            let v_perp = Vec3(0.0, 120.0, 0.0)
                base = collision_lead_angle(500.0, v_perp, x̂)
                for along in (-900.0, -1.0, 0.0, 1.0, 900.0)
                    @test collision_lead_angle(500.0, v_perp + Vec3(along, 0.0, 0.0), x̂) ≈
                          base atol = 1e-15
                end
            end
        end
    end

    # --- SLICE 33 — THE RING IS AN FOV BUDGET ITEM (§11 Tier-A) ---------------------------
    #
    # ⚠ WHAT THIS TESTSET DOES NOT PROVE, deliberately — the slice-32 shape one slice on. The
    # slice's claim is that a limit cycle's look-angle EXCURSION is spent out of the FOV budget,
    # i.e. that the critical window tracks the excursion. That is a statement about a flying
    # missile with glass in front of it, measured over TWO runs (§ the seam discipline below),
    # and no pure kernel can reach it. What gate 1 owns is the ONE new quantity: that its SIGN
    # is exactly the shipped verdict, and that the subtraction it is written as agrees with the
    # comparison it replaced — including at the boundary, where a tolerance would hide the only
    # place they could differ.
    @testset "seeker_fov_margin (slice 33) — the budget, and its SIGN as the verdict" begin
        q  = quat_from_axis_angle(Vec3(0.3, 1.0, -0.4), 0.35)
        û  = los_unit_from_angles(0.21, -0.13)

        # the definitional pin, at both signs of the slider — `max(fov,0) − boresight_angle`
        for fov in (-1.0, -0.0, 0.0, 0.05, 0.35, 3.0)
            @test seeker_fov_margin(q, û, fov) ===
                  max(fov, 0.0) - boresight_angle(q, û)
        end

        # PAIRED polarity with the magnitude pinned (house style — not merely "one of each"):
        # a 20° LOS inside a 25° window has 5° of budget left; the same LOS against a 15°
        # window is 5° over. Exact degrees, because `id` + a pure-azimuth LOS makes the radius
        # the azimuth itself (`boresight_angle` above).
        let û20 = los_unit_from_angles(deg2rad(20.0), 0.0)
            @test rad2deg(seeker_fov_margin(id, û20, deg2rad(25.0))) ≈ +5.0 atol = 1e-12
            @test rad2deg(seeker_fov_margin(id, û20, deg2rad(15.0))) ≈ -5.0 atol = 1e-12
            @test  seeker_in_fov(id, û20, deg2rad(25.0))
            @test !seeker_in_fov(id, û20, deg2rad(15.0))
        end

        # ⭐⭐ THE SIGN IS THE VERDICT — AND THE TOOTH IS AGAINST THE COMPARISON FORM WRITTEN
        # LONGHAND, NEVER AGAINST THE PREDICATE (which is now DEFINED from this margin, so
        # `(margin ≥ 0) == seeker_in_fov(...)` would be `x == x`, convention 11's tautology).
        # The oracle is the expression slice 32 shipped: `boresight_angle ≤ max(fov, 0)`.
        # ⚠ AND IT IS SWEPT AT THE BOUNDARY, because that is the ONLY place a subtraction could
        # diverge from a comparison. Two distinct finite doubles never subtract to zero (their
        # difference is at least an ulp, and Sterbenz makes it exact when they are close) and
        # rounding to nearest preserves sign — so the equivalence is EXACT, with no tolerance.
        # That is a fact about IEEE doubles, not about the algebra, and it is what licenses
        # defining the predicate from the margin at all. Its own Xoshiro (convention 11).
        # ⚠ Accumulate and assert ONCE (the house style of the rotation sweep above) — an `@test`
        # inside a 6000-cell loop would move the suite's own ledger by more than the whole slice.
        let rng = Xoshiro(3333), n_mismatch = 0, n_in = 0, n_out = 0,
            n_edge_zero = 0, n_edge_neg = 0, b_hi = 0.0
            for _ in 1:600
                att = qnormalize(quat_from_axis_angle(Vec3(randn(rng), randn(rng), randn(rng)),
                                                      3.0 * randn(rng)))
                los = let v = Vec3(randn(rng), randn(rng), randn(rng))
                    v / sqrt(v[1]^2 + v[2]^2 + v[3]^2)
                end
                b = boresight_angle(att, los)
                b_hi = max(b_hi, b)
                for fov in (b, prevfloat(b), nextfloat(b), b * (1 - 1e-15), b * (1 + 1e-15),
                            b - 1e-12, b + 1e-12, 0.5 * b, 2.0 * b, -b)
                    m = seeker_fov_margin(att, los, fov)
                    # THE EQUIVALENCE, EXACT — the subtraction's sign IS the comparison
                    (m ≥ 0.0) == (b ≤ max(fov, 0.0)) || (n_mismatch += 1)
                    (m ≥ 0.0) ? (n_in += 1) : (n_out += 1)
                end
                # ...and the boundary itself: `x − x` is EXACTLY +0.0 (never `−0.0`, which would
                # still pass `≥ 0` but would break any client testing `margin > 0`), while ONE
                # ULP tighter is STRICTLY negative — the slice-32 `prevfloat` tooth, inherited.
                seeker_fov_margin(att, los, b) === 0.0            && (n_edge_zero += 1)
                seeker_fov_margin(att, los, prevfloat(b)) < 0.0   && (n_edge_neg  += 1)
            end
            @test n_mismatch  == 0                  # 6000 cells, no tolerance anywhere
            @test n_edge_zero == 600 == n_edge_neg
            # the sweep really did land on BOTH sides — not "everything is out" — and really did
            # reach wide angles, so the boundary cases are not all crowded near zero
            @test n_in == n_out == 3000
            @test b_hi > 2.0
        end

        # STRICTLY MONOTONE IN THE WINDOW above the clamp, FLAT below it. This is what makes
        # "widen the seeker" a one-slider cure with a well-posed bracket at gate 3 (seam
        # discipline 2: assert the INEQUALITY, never a `ceil` of the excursion — a bracketing
        # pair needs the margin to cross zero exactly once in `fov`).
        let ms = [seeker_fov_margin(q, û, f) for f in (0.1, 0.2, 0.3, 0.4, 0.5)]
            @test issorted(ms) && ms[1] < ms[end]
            @test all(diff(ms) .> 0.0)
            for dead in (-0.0, -1e-9, -1.0, -1e9, -Inf)      # the clamp: all one value
                @test seeker_fov_margin(q, û, dead) === -boresight_angle(q, û)
            end
        end

        # ⚠⚠ THE DIVERGENCE THAT MUST BE WRITTEN DOWN: THE SHIPPED KEYS DO NOT RECONSTRUCT THIS
        # ONE ON A NEGATIVE SLIDER (advisor). The wire ships `seeker_fov_deg` AUTHORED (slice 32
        # — a HUD showing 0° for a negative slider would hide what the student is holding) while
        # the margin uses the CLAMPED window, so a client deriving `fov − look_angle` disagrees
        # with the core. ⭐ And it does not merely differ in MAGNITUDE — it FLIPS THE VERDICT on
        # exactly the LOS the never-locked state is defined by: an on-boresight target is IN a
        # `fov = −1` window (only that one is), where the subtraction says OUT.
        let f_neg = deg2rad(-5.0), û20 = los_unit_from_angles(deg2rad(20.0), 0.0)
            @test rad2deg(seeker_fov_margin(id, û20, f_neg)) ≈ -20.0 atol = 1e-12  # CLAMPED
            @test rad2deg(f_neg - boresight_angle(id, û20))  ≈ -25.0 atol = 1e-12  # the naive
            # the verdict flip, and the PAIRED case where the two forms agree exactly
            @test seeker_fov_margin(id, Vec3(1.0, 0.0, 0.0), -1.0) === 0.0     # IN (never-locked)
            @test seeker_in_fov(id, Vec3(1.0, 0.0, 0.0), -1.0)
            @test -1.0 - boresight_angle(id, Vec3(1.0, 0.0, 0.0)) < 0.0        # naive: OUT
            @test seeker_fov_margin(id, û20, deg2rad(25.0)) ===
                  deg2rad(25.0) - boresight_angle(id, û20)                     # agree at fov > 0
        end

        # conventions 5/6 — a live slider can never crash a tick, and the kernel must not
        # manufacture a non-finite from finite input at any magnitude. NaN PROPAGATES (the
        # predicate's own degenerate table asserts the resulting verdict is `false`).
        @test isfinite(seeker_fov_margin(q, û, 1.0e9))
        @test isfinite(seeker_fov_margin(q, û, -1.0e9))
        @test seeker_fov_margin(q, û, Inf) == Inf
        @test isnan(seeker_fov_margin(q, û, NaN))
        @test seeker_fov_margin(q, û, 25) === seeker_fov_margin(q, û, 25.0)   # Real, not Float64
    end

    @testset "the GIMBALLED HEAD (slice 34) — its own axis, and the servo that aims it" begin
        # The head has its own pointing angles, so the detector's window is about the HEAD, not the
        # nose. `off_axis_angle` is that measurement generalized — and `boresight_angle` is now
        # DEFINED as its `ref = (0,0)` case, which is the CAGED head, i.e. a strapdown seeker.

        @testset "off_axis_angle — the reference axis, and boresight as its caged degenerate" begin
            # PAIRED exact cases computed by hand, not by the kernel's own formula: a 3-4-5 in
            # angle space off the origin, and a pure-azimuth separation off an OFFSET reference.
            @test rad2deg(off_axis_angle(0.0, 0.0, deg2rad(3.0), deg2rad(4.0))) ≈ 5.0 atol = 1e-12
            @test rad2deg(off_axis_angle(deg2rad(18.0), 0.0, deg2rad(20.0), 0.0)) ≈ 2.0 atol = 1e-12
            @test off_axis_angle(0.37, -0.12, 0.37, -0.12) === 0.0        # the axis itself
            @test off_axis_angle(0, 0, 3, 4) === off_axis_angle(0.0, 0.0, 3.0, 4.0)  # Real, not F64

            # ⭐⭐ THE BIT-IDENTITY THAT LICENSES THE REDEFINITION — AND THE ORACLE IS THE LITERAL
            # SLICE-32 EXPRESSION, never the new kernel (`boresight_angle` IS the new kernel now,
            # so testing against it would be `x == x` — convention 11's tautology, which slice 33's
            # own gate 1 walked into one layer up). `wrap_angle` is `rem(θ, 2π, RoundNearest)`, the
            # exact identity on `az_el`'s codomain, and `x − 0.0 === x`; this is what MEASURES that
            # rather than arguing it. Own Xoshiro; accumulate and assert ONCE (a 4000-cell `@test`
            # loop would move the suite's ledger by more than the whole slice).
            let rng = Xoshiro(3434), n_bad = 0, b_hi = 0.0, n_wide = 0
                for _ in 1:4000
                    att = qnormalize(quat_from_axis_angle(Vec3(randn(rng), randn(rng), randn(rng)),
                                                          4.0 * randn(rng)))
                    los = let v = Vec3(randn(rng), randn(rng), randn(rng))
                        v / sqrt(v[1]^2 + v[2]^2 + v[3]^2)
                    end
                    b = boresight_angle(att, los)
                    b === hypot(look_angles(att, los)...) || (n_bad += 1)   # the slice-32 literal
                    b_hi = max(b_hi, b)
                    b > 2.0 && (n_wide += 1)
                end
                @test n_bad == 0                       # 4000 cells, `===`, no tolerance anywhere
                @test b_hi > 3.0 && n_wide > 400       # the sweep really did reach the wide corner
            end

            # ⭐ AND THE REFERENCE IS NOT IGNORED — the paired half, without which the identity
            # above would also hold for a kernel that dropped its first two arguments. A head 18°
            # off the nose reads a 2° error on a LOS the NOSE is 20° away from.
            let q = quat_from_axis_angle(Vec3(0.0, 0.0, 1.0), 0.0), û = los_unit_from_angles(deg2rad(20.0), 0.0)
                laz, lel = look_angles(q, û)
                @test rad2deg(off_axis_angle(deg2rad(18.0), 0.0, laz, lel)) ≈  2.0 atol = 1e-12
                @test rad2deg(boresight_angle(q, û))                       ≈ 20.0 atol = 1e-12
            end

            # ⚠ THE WRAP IS LOAD-BEARING, AND IT IS THE ONE THING THE ORIGIN-REFERENCED FORM NEVER
            # NEEDED (with `ref = 0` the codomain is already principal). PAIRED with a does-not-wrap
            # case, so the tooth cannot pass by wrapping where it does not belong — and the naive
            # unwrapped value is EXHIBITED, because that is the failure it exists to catch.
            @test rad2deg(off_axis_angle(deg2rad(-179.0), 0.0, deg2rad(179.0), 0.0)) ≈ 2.0 atol = 1e-9
            @test rad2deg(abs(deg2rad(179.0) - deg2rad(-179.0)))                     ≈ 358.0 atol = 1e-9
            @test rad2deg(off_axis_angle(deg2rad(-9.0), 0.0, deg2rad(9.0), 0.0))     ≈ 18.0 atol = 1e-12

            # ⚠ SYMMETRIC IN ITS TWO PAIRS — what says it measures a SEPARATION and not a signed
            # departure (`wrap_angle` is odd except at exactly ±π, where both signs give the same
            # magnitude and `hypot` squares them anyway).
            let rng = Xoshiro(3435), n_bad = 0
                for _ in 1:2000
                    a, b, c, d = (2π * rand(rng) - π), (π * rand(rng) - π/2),
                                 (2π * rand(rng) - π), (π * rand(rng) - π/2)
                    off_axis_angle(a, b, c, d) === off_axis_angle(c, d, a, b) || (n_bad += 1)
                end
                @test n_bad == 0
            end

            # ⚠ THE ANGLE-SPACE RADIUS vs THE EXACT CONE HALF-ANGLE — the §1 approximation inherited
            # from `boresight_angle`, but a DIFFERENT quantity with an OFFSET reference, so it is
            # MEASURED here rather than inherited. ⚠ THE CONTROL COMES FIRST (convention 10 — pin
            # the new instrument against a SHIPPED number before believing anything it says): at
            # `ref = (0,0)` this same comparison must reproduce `boresight_angle`'s own docstring
            # figure, +0.364° at a true 30° cone.
            cone_angle(ra, re, a, e) = let u1 = los_unit_from_angles(ra, re),
                                           u2 = los_unit_from_angles(a, e)
                acos(clamp(u1[1]*u2[1] + u1[2]*u2[2] + u1[3]*u2[3], -1.0, 1.0))
            end
            let ε = deg2rad(30.0), g_hi = -Inf
                for i in 0:3599                       # a true 30° cone, swept by clock angle
                    φ = 2π * i / 3600
                    az, el = az_el(Vec3(cos(ε), sin(ε) * cos(φ), sin(ε) * sin(φ)))
                    g_hi = max(g_hi, rad2deg(off_axis_angle(0.0, 0.0, az, el)) - 30.0)
                end
                @test g_hi ≈ 0.36416 atol = 1e-4       # the shipped docstring number, reproduced
            end
            # ...and now the offset case, at the two operating points gate 0's bracket is read at.
            # ⭐ THE GAP IS DRIVEN BY THE REFERENCE'S ELEVATION, NOT ITS AZIMUTH — an azimuth
            # difference subtends `cos(el)` times its own size, so ON THE EQUATOR the only departure
            # left is the ERROR's own excursion off it: CUBIC in the error (0.00009° at 1.96°,
            # 0.00159° at 5.0°) and independent of `ref_az`. ⚠ "The equator is EXACT" would be the
            # natural thing to write and it is FALSE — gate 1 measured 1.6e−3° there. Lift the
            # reference to 10° and the SAME 1.96° error gives 0.030°, 330× more, which is what
            # "driven by the elevation" means, asserted rather than said. On the shipped wire the
            # head sits at |el| ≤ 0.84° (the crossing lead is essentially pure AZIMUTH), which is
            # why the two operating points land three orders under the 0.5° resolution the §0.6
            # bracket is quoted at.
            worst_gap(ha, he, err) = let ra = deg2rad(ha), re = deg2rad(he), ε = deg2rad(err), g = -Inf
                for i in 0:719
                    φ = 2π * i / 720
                    a = ra + ε * cos(φ); e = re + ε * sin(φ)
                    g = max(g, rad2deg(off_axis_angle(ra, re, a, e) - cone_angle(ra, re, a, e)))
                end
                g
            end
            @test worst_gap(18.1054, 0.8138, 1.9556) ≈ 0.000400 atol = 2e-5   # QUIET   R̂ = −0.18
            @test worst_gap(20.6191, 0.8317, 5.2368) ≈ 0.003404 atol = 2e-5   # RINGING R̂ = −0.16
            @test worst_gap(16.0,   10.0,    8.0)    ≈ 0.13936  atol = 1e-4   # the domain's worst
            @test worst_gap(16.0,   10.0,    8.0)     < 0.5                   # still under the grid
            # the ELEVATION dependence, PAIRED — the equator's residual cubic term against the same
            # error lifted to 10°, and the equator's independence from `ref_az` (18° vs 30°)
            @test worst_gap(18.0,     0.0,   1.9556) ≈ 0.000090 atol = 5e-6
            @test worst_gap(18.0,    10.0,   1.9556) ≈ 0.029990 atol = 5e-5   # 330× the equator
            @test worst_gap(30.0,     0.0,   5.0)    ≈ 0.001588 atol = 5e-6
            @test worst_gap( 5.0,     0.0,   5.0)    ≈ worst_gap(30.0, 0.0, 5.0) atol = 1e-6

            # conventions 5/6 — never manufacture a non-finite from finite input, at any magnitude
            @test isfinite(off_axis_angle(1.0e9, -1.0e9, -1.0e9, 1.0e9))
            @test off_axis_angle(0.0, 0.0, 0.0, 0.0) === 0.0
            @test isnan(off_axis_angle(NaN, 0.0, 0.1, 0.1))
        end

        @testset "head_clamp — the ONE stop site, shared with the seam's handover" begin
            # ⚠⚠ IT IS A KERNEL BECAUSE IT HAS TWO CALLERS (advisor). `head_slew` ends in it, and
            # so must gate 2's HANDOVER init — gate 1 measured that the servo contracts toward the
            # target only from INSIDE the disc, and it is this clamp every tick that keeps the head
            # there. A handover that clamped some other way would hand tick 1 the one state that
            # breaks the invariant, and the servo could not detect it. One site ⇒ one tooth.
            let stop = deg2rad(30.0)
                # INERT when it does not bind — bit-for-bit, which is what lets the handover call
                # it unconditionally (never `min` trusting equality, the `-0.0`/rounding trap)
                for (a, e) in ((0.1, -0.2), (0.0, 0.0), (-0.0, 0.0), (deg2rad(30.0), 0.0))
                    @test head_clamp(a, e, stop) === (a, e)
                end
                # ...and when it DOES bind: onto the circle, along the same ray, so the direction
                # is preserved exactly and only the magnitude moves
                let a = deg2rad(70.0), e = deg2rad(40.0), p = head_clamp(a, e, stop)
                    @test hypot(p...) ≈ stop atol = 1e-15
                    @test p[1] / p[2] ≈ a / e atol = 1e-12
                    @test off_axis_angle(p[1], p[2], a, e) ≈ hypot(a, e) - stop atol = 1e-12
                end
                # ⚠ CIRCULAR, NOT PER AXIS — the form the gate-0 probe actually used, EXHIBITED
                # differing, since no gate-0 arm ever bound the stop and nothing there could tell
                # them apart. A per-axis clamp leaves the head at `√2·stop` on the diagonal.
                let a = deg2rad(70.0), e = deg2rad(70.0)
                    @test hypot(clamp(a, -stop, stop), clamp(e, -stop, stop)) ≈ sqrt(2) * stop atol = 1e-12
                    @test hypot(head_clamp(a, e, stop)...) ≈ stop atol = 1e-15
                end
                # the degenerates this kernel OWNS (relocated from `head_slew`, not duplicated)
                for dead in (0.0, -0.0, -1.0, -1.0e9)
                    p = head_clamp(0.3, -0.4, dead)
                    @test iszero(p[1]) && iszero(p[2])                  # CAGED
                end
                @test head_clamp(0.3, -0.4, NaN) === (0.3, -0.4)        # NaN ⇒ NO stop, not NaN
                @test head_clamp(0.3, -0.4, Inf) === (0.3, -0.4)
                @test all(isfinite, head_clamp(1.0e9, -1.0e9, 1.0e-9))
                @test head_clamp(3, 4, 1) === head_clamp(3.0, 4.0, 1.0) # Real, not Float64
                @test head_clamp(3, 4, 1)[1] ≈ 0.6 atol = 1e-15         # the 3-4-5, projected
            end
        end

        @testset "head_slew — the servo, the stop, and the exact landing" begin
            dt = 1.0e-3

            # ⭐ THE EXACT LANDING IS AN ASSIGNMENT, NOT ARITHMETIC — the slice's own FALSE-FIDELITY
            # CONTROL, so the tooth must be ABLE to pass: gate 0's §0.2 claim is `max|Δpos| = 0`
            # over 9 000 ticks against the SHIPPED strapdown seeker, and a rounding residual in this
            # branch would turn that bit-identity into a near-miss. ⚠ Only INSIDE THE STOP.
            let rng = Xoshiro(3436), n_bad = 0, n_arith_bad = 0
                for _ in 1:3000
                    h_az = 0.6 * randn(rng); h_el = 0.3 * randn(rng)
                    t_az = 0.6 * randn(rng); t_el = 0.3 * randn(rng)
                    for τ in (0.0, dt, 0.5 * dt, -1.0)          # τ ≤ dt ⇒ the servo lands this tick
                        head_slew(h_az, h_el, t_az, t_el, τ, dt, Inf) === (t_az, t_el) ||
                            (n_bad += 1)
                    end
                    # ...and the form the kernel deliberately does NOT use, exhibited failing
                    (h_az + wrap_angle(t_az - h_az) === t_az) || (n_arith_bad += 1)
                end
                @test n_bad == 0                # 12 000 cells, `===`, no tolerance
                @test n_arith_bad > 100         # `head + (tgt − head)` is NOT `tgt` in IEEE doubles
            end

            # THE FIRST-ORDER RESPONSE, against an EXTERNAL anchor (convention 11) — the geometric
            # decay `(1 − dt/τ)^n`, not a self-calibrated round-trip through the kernel's own gain.
            let τ = 0.05, tgt = 0.20, n = 400
                az, el = 0.0, 0.0
                for _ in 1:n
                    az, el = head_slew(az, el, tgt, 0.0, τ, dt, Inf)
                end
                @test tgt - az ≈ tgt * (1 - dt / τ)^n atol = 1e-12
                @test el === 0.0                      # the idle axis does not drift
            end

            # ⚠ THE SERVO TAKES THE SHORT WAY ROUND — PAIRED with a does-not-wrap case, and with
            # the naive long-way step exhibited. ⭐ AND THE HEAD MAY LEAVE THE PRINCIPAL INTERVAL
            # when there is no stop to hold it: that is DEFINED, not a bug, because the next tick's
            # error is wrapped again. Pinned by converging from the wrapped start.
            let τ = 10 * dt
                az, _ = head_slew(deg2rad(179.0), 0.0, deg2rad(-179.0), 0.0, τ, dt, Inf)
                @test rad2deg(az) ≈ 179.2 atol = 1e-9          # forward through π, not back to 0
                @test rad2deg(az) > 179.0                      # the long way would go DOWN
                a2, _ = head_slew(deg2rad(179.0), 0.0, deg2rad(170.0), 0.0, τ, dt, Inf)
                @test rad2deg(a2) ≈ 178.1 atol = 1e-9          # the does-not-wrap half
                az2 = deg2rad(179.0)
                for _ in 1:3000
                    az2, _ = head_slew(az2, 0.0, deg2rad(-179.0), 0.0, τ, dt, Inf)
                end
                @test abs(rad2deg(wrap_angle(az2 - deg2rad(-179.0)))) < 1e-6   # it converged
            end

            # ⭐ THE FIXED POINT AT THE STOP — slice 24's killed ±90° bank law is the precedent and
            # the reason to check: a projection at a limit is exactly where CHATTER hides. A target
            # far beyond the stop drives the head ONTO the circle in the target's direction, and it
            # STAYS — bit-for-bit, not merely to a tolerance.
            let stop = deg2rad(30.0), τ = 20 * dt,
                t_az = deg2rad(70.0), t_el = deg2rad(40.0)
                az, el = 0.0, 0.0
                for _ in 1:20000
                    az, el = head_slew(az, el, t_az, t_el, τ, dt, stop)
                end
                # ⚠ ON the circle, and — the half a converged ratio cannot discriminate (advisor:
                # after a 20 000-step burn-in `az/el` is far tighter than any loose atol, so it
                # could not catch a head that settled on the WRONG POINT of the circle) — the EXACT
                # RESIDUAL a correct radial projection leaves: `‖tgt‖ − stop`, to 1e−12.
                @test hypot(az, el) ≈ stop atol = 1e-12                 # ON the circle
                @test off_axis_angle(az, el, t_az, t_el) ≈ hypot(t_az, t_el) - stop atol = 1e-12
                @test az / el ≈ t_az / t_el atol = 1e-12                # in the TARGET's direction
                prev = (az, el)
                for _ in 1:200
                    prev = head_slew(prev[1], prev[2], t_az, t_el, τ, dt, stop)
                end
                @test prev === (az, el)                                 # and it STAYS — no chatter
                # the gain-1 branch reaches the same fixed point in ONE step and holds it exactly
                let p1 = head_slew(0.0, 0.0, t_az, t_el, 0.0, dt, stop)
                    @test hypot(p1...) ≈ stop atol = 1e-12
                    @test head_slew(p1[1], p1[2], t_az, t_el, 0.0, dt, stop) === p1
                end
            end

            # ⚠⚠ CONTRACTION — AND THE EXPECTED CAVEAT IS SHARPER THAN EXPECTED, MEASURED BOTH WAYS.
            # A radial clamp CAN pull the head off the line to the target, so "the error never
            # grows" looked like it needed the stop-binding case excluded. It does not: with the
            # head starting INSIDE OR ON the stop, the disc is INVARIANT and the step is a
            # contraction toward the target UNCONDITIONALLY — 0 growths in 400 000 randomized cells
            # ACROSS a binding stop (gate 1, `g1_contract.jl`), and the sweep below is that result
            # in miniature WITH the stop live rather than switched off. ⭐ It fails only for a head
            # handed in ALREADY OUTSIDE its stop, which the seam cannot produce — `head_slew` is the
            # SOLE writer of the head and clamps every tick — and which is therefore a constraint on
            # gate 2's HANDOVER: the init must use this same circular clamp, or tick 1 hands in the
            # one state that breaks the invariant.
            let rng = Xoshiro(3437), n_grew = 0, n_clamped = 0, stop = deg2rad(20.0)
                for _ in 1:4000
                    r = deg2rad(20.0) * rand(rng); φ = 2π * rand(rng)
                    h_az = r * cos(φ); h_el = r * sin(φ)                 # INSIDE or ON the stop
                    t_az = 0.9 * randn(rng); t_el = 0.6 * randn(rng)     # often far OUTSIDE it
                    τ = 10.0^(-3 + 3 * rand(rng))
                    e0 = off_axis_angle(h_az, h_el, t_az, t_el)
                    n_az, n_el = head_slew(h_az, h_el, t_az, t_el, τ, dt, stop)
                    off_axis_angle(n_az, n_el, t_az, t_el) > e0 + 1e-15 && (n_grew += 1)
                    hypot(n_az, n_el) ≥ prevfloat(stop) && (n_clamped += 1)
                end
                @test n_grew == 0
                @test n_clamped > 200        # the stop really did bind — not a vacuous sweep
            end
            # ...and the case that DOES grow, EXHIBITED, so the boundary of the claim is a
            # measurement and not a tolerance loosened until the sweep passed (the exact cell
            # `g1_contract.jl`'s search returned, worst of 144 698 growths in 400 000):
            let stop = 0.9977185735528811, h = (-1.914199240810994, 3.4856072840668766),
                t = (3.9660355165643364, -2.24037075226863), gain = 0.2565091776771703
                e0 = off_axis_angle(h[1], h[2], t[1], t[2])
                @test hypot(h...) > stop                                 # handed in OUTSIDE
                n = head_slew(h[1], h[2], t[1], t[2], dt / gain, dt, stop)
                @test off_axis_angle(n[1], n[2], t[1], t[2]) > e0 + 2.9   # 0.688 → 3.612 rad
            end

            # ⚠ THE DEGENERATE TABLE (convention 5 — a live knob can never crash a tick), each with
            # its meaning. ⭐ `τ = Inf` is §0.4's FROZEN HEAD, the reductio that pins the mechanism:
            # a head frozen in the BODY frame produces a CONSTANT bend, and it is quiet at every R̂.
            let h_az = 0.31, h_el = -0.17, t_az = -0.44, t_el = 0.22
                @test head_slew(h_az, h_el, t_az, t_el, Inf, dt, Inf) === (h_az, h_el)   # FROZEN
                @test head_slew(h_az, h_el, t_az, t_el, 1.0e9, dt, Inf) !== (h_az, h_el) # not yet
                @test head_slew(h_az, h_el, t_az, t_el, 0.05, 0.0, Inf) === (h_az, h_el) # dt = 0
                @test head_slew(h_az, h_el, t_az, t_el, 0.05, -1.0, Inf) === (h_az, h_el)# dt < 0
                @test head_slew(h_az, h_el, t_az, t_el, -1.0, dt, Inf) === (t_az, t_el)  # τ < 0
                @test head_slew(h_az, h_el, t_az, t_el, 0.0, 0.0, Inf) === (t_az, t_el)  # both 0
                # `stop ≤ 0` is the CAGED head — which by `off_axis_angle`'s identity is exactly the
                # strapdown seeker, the physics reading of this slice's own degenerate. ⚠ THE SIGN
                # OF THE ZERO IS INHERITED FROM THE STEP (`x·0.0` keeps `x`'s sign — the `-0.0`
                # trap, which this codebase names on every structural byte-identity claim), so the
                # tooth is componentwise ZERO, not `=== (0.0, 0.0)`. It is harmless downstream and
                # that is ASSERTED, not assumed: a caged head's own off-axis angle is the strapdown
                # look angle to the last bit, because `wrap_angle(az − (−0.0))` is `az`.
                for dead in (0.0, -0.0, -1.0, -1.0e9)
                    p = head_slew(h_az, h_el, t_az, t_el, 0.05, dt, dead)
                    @test iszero(p[1]) && iszero(p[2])
                    @test off_axis_angle(p[1], p[2], 0.21, -0.13) ===
                          off_axis_angle(0.0, 0.0, 0.21, -0.13)
                end
                # a NaN stop is NEITHER clamped NOR propagated — it degenerates to NO stop
                # (convention 6's direction: never manufacture a non-finite from finite input)
                @test head_slew(h_az, h_el, t_az, t_el, 0.0, dt, NaN) === (t_az, t_el)
                # a NaN τ DOES propagate: it is an AUTHORED input, so it is validate-at-LOAD's
                # business, not this consumer's (convention 5's two guard sites)
                @test all(isnan, head_slew(h_az, h_el, t_az, t_el, NaN, dt, Inf))
                # convention 6 — finite in, finite out, at any magnitude
                @test all(isfinite, head_slew(h_az, h_el, 1.0e9, -1.0e9, 1.0e-9, dt, 1.0e9))
                @test head_slew(0, 0, 1, 1, 0, 1, 10) === head_slew(0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 10.0)
            end
            # ⚠ THE SIGNED-ZERO CORNER OF THE FROZEN CLAIM, written down rather than dodged (the
            # `-0.0` trap this codebase names on every structural byte-identity claim): a frozen
            # head adds `wrap_angle(err)·0.0`, and `-0.0 + 0.0` is `+0.0`. So the freeze is `===`
            # for every head this slice can reach and `==` at that one point.
            @test head_slew(-0.0, 0.5, 0.4, 0.5, Inf, dt, Inf)[1] === 0.0
            @test head_slew(-0.0, 0.5, 0.4, 0.5, Inf, dt, Inf)[1] == -0.0
        end

        @testset "head_slew — THE RATE LIMIT (slice 35), and the control it must not break" begin
            dt = 1.0e-3

            # ⚠⚠ THE BIT-IDENTITY CONTROL, AND IT IS THE WHOLE REASON THE LIMIT IS INERT BY BRANCH.
            # Slice 34's `τ → 0 ⇒ max|Δpos| = 0` strapdown collapse carries a REFUTATION, so a
            # rounding residual here would turn that control into a near-miss and read like a bug in
            # the new branch. Three claims, and the third is the one the wire rests on: the ABSENT
            # kwarg, an `Inf` rate, and a NON-BINDING FINITE rate all take the OLD CODE PATH.
            let rng = Xoshiro(3538), n_absent = 0, n_free = 0, n_land = 0, n_moved = 0
                for _ in 1:4000
                    h_az = 0.6 * randn(rng); h_el = 0.3 * randn(rng)
                    t_az = 0.6 * randn(rng); t_el = 0.3 * randn(rng)
                    τ = 10.0^(-3 + 3 * rand(rng)); stop = deg2rad(30.0)
                    ref = head_slew(h_az, h_el, t_az, t_el, τ, dt, stop)
                    dem = head_slew_full(h_az, h_el, t_az, t_el, τ, dt, stop)[3]
                    head_slew(h_az, h_el, t_az, t_el, τ, dt, stop; rate_max = Inf) === ref ||
                        (n_absent += 1)
                    # a limit ABOVE the demand — inert, and `===`, never "rounds to the same"
                    head_slew(h_az, h_el, t_az, t_el, τ, dt, stop;
                              rate_max = 1.0e3 * dem / dt + 1.0) === ref || (n_free += 1)
                    # ⭐ the EXACT LANDING with a non-binding limit PRESENT — the kernel half of the
                    # τ → 0 collapse (the wire half is gate 2/3's, and it is stated there)
                    head_slew(h_az, h_el, t_az, t_el, 0.0, dt, Inf;
                              rate_max = 1.0e6) === (t_az, t_el) || (n_land += 1)
                    # ...and the non-vacuity: a limit BELOW the demand really does move the answer
                    head_slew(h_az, h_el, t_az, t_el, τ, dt, stop;
                              rate_max = 0.5 * dem / dt) === ref && (n_moved += 1)
                end
                @test n_absent == 0 && n_free == 0 && n_land == 0
                @test n_moved == 0            # 4 000 cells, EVERY one moved — not a vacuous sweep
            end

            # ⚠⚠ AND THE CONTROL ARM IS THE ABSENT KEY / `Inf`, NOT THE DOMAIN CEILING (advisor,
            # blocking): gate 0 §0.2 measures the PEAK demand at an identical 72.542 °/s on every
            # arm — the tick-2 HANDOVER transient — so a `gimbal_rate_dps = 60` control BINDS, and
            # §0.6's rate-60 row agrees on the wire (`sat_band` 8.64 %, `rms r` 0.88469 vs the free
            # 0.88465). Pinned as arithmetic here so gate 3 cannot author 60 as a bit-identity arm.
            let h = (0.20, -0.10), τ = 0.0, stop = Inf,
                t = (0.20 + deg2rad(72.542) * dt, -0.10)            # a step demanding EXACTLY §0.2
                f = head_slew_full(h[1], h[2], t[1], t[2], τ, dt, stop)
                @test rad2deg(f[3] / dt) ≈ 72.542 atol = 1e-9        # the demand, in the same units
                @test f[4] === false                                 # free: nothing bound
                @test head_slew(h..., t..., τ, dt, stop; rate_max = deg2rad(60.0)) !== (t[1], t[2])
                @test head_slew(h..., t..., τ, dt, stop; rate_max = Inf) === (t[1], t[2])
            end

            # ⚠ RADIAL, NOT PER AXIS — `head_clamp`'s own tooth in the new quantity, and the same
            # species argument (the limit must have the shape of the telemetry that reads it). A
            # per-axis rate clamp leaves the STEP at `√2·cap` on the diagonal, EXHIBITED differing.
            let h = (0.0, 0.0), t = (0.4, 0.4), cap_r = 10.0        # rad/s ⇒ cap = 0.01 rad
                p = head_slew(h..., t..., 0.0, dt, Inf; rate_max = cap_r)
                @test hypot(p...) ≈ cap_r * dt atol = 1e-15          # ON the cap circle
                @test p[1] ≈ p[2] atol = 1e-15                       # ...along the demanded ray
                per_axis = (clamp(t[1], -cap_r * dt, cap_r * dt), clamp(t[2], -cap_r * dt, cap_r * dt))
                @test hypot(per_axis...) ≈ sqrt(2) * cap_r * dt atol = 1e-15
            end
            # ...and off the diagonal: the DIRECTION of the demanded step is preserved exactly while
            # only its magnitude moves — the property that makes the limit a servo bound and not a
            # re-aiming (the `head_clamp` "same ray" tooth, about the HEAD rather than the origin)
            let h = (0.31, -0.17), t = (-0.44, 0.22), τ = 0.05, cap_r = 3.0
                fr = head_slew_full(h..., t..., τ, dt, Inf)
                p  = head_slew(h..., t..., τ, dt, Inf; rate_max = cap_r)
                @test hypot(p[1] - h[1], p[2] - h[2]) ≈ cap_r * dt atol = 1e-15
                @test (p[1] - h[1]) / (p[2] - h[2]) ≈
                      (fr[1] - h[1]) / (fr[2] - h[2]) atol = 1e-12
                # the demanded step points AT the target, so a step of length `cap` moves the error
                # down by EXACTLY `cap` — the limit spends bandwidth, it does not re-aim
                @test off_axis_angle(p..., t...) ≈
                      off_axis_angle(h..., t...) - cap_r * dt atol = 1e-12
            end

            # ⚠ THE ORDERING IS PINNED: the rate limit shapes the STEP, then the stop has the last
            # word (the stop is the OUTER authority). The two orders are NOT the same map — the
            # rate limit is radial about the HEAD, the stop radial about the ORIGIN — so the reverse
            # order is EXHIBITED giving a different head, which is what makes this a measurement.
            let stop = deg2rad(30.0), h = (deg2rad(25.0), 0.0), t = (deg2rad(25.0), deg2rad(60.0)),
                cap_r = deg2rad(10.0) / dt
                p = head_slew(h..., t..., 0.0, dt, stop; rate_max = cap_r)
                @test hypot(p[1] - h[1], p[2] - h[2]) ≈ deg2rad(10.0) atol = 1e-15  # rate bound…
                @test hypot(p...) < stop                                            # …stop did not
                # the REVERSE order (clamp first, then rate-limit the step to the clamped point)
                let c = head_clamp(t..., stop), v = (c[1] - h[1], c[2] - h[2]), m = hypot(v...),
                    sc = min(1.0, deg2rad(10.0) / m)
                    @test !isapprox(h[1] + v[1] * sc, p[1]; atol = 1e-6)
                end
                # ...and a step the rate limit leaves LONGER than the stop allows is still stopped
                let p2 = head_slew(0.0, 0.0, deg2rad(70.0), 0.0, 0.0, dt, stop;
                                   rate_max = deg2rad(50.0) / dt)
                    @test hypot(p2...) ≈ stop atol = 1e-15
                end
            end

            # ⚠⚠ CONTRACTION SURVIVES THE LIMIT — the 4 000-cell sweep above this testset, re-run
            # with a randomized rate limit sized so that BOTH limits bind on a healthy share of the
            # cells (advisor). The limited step is a point ON the segment to the unlimited endpoint,
            # so it cannot grow the error; measured rather than argued, and the counters below are
            # what say the sweep exercised the branch. ⚠ The rate band is CHOSEN, and the reason is
            # a measurement: a tighter band starves the STOP counter (at `10^(0.5…3)` the steps are
            # so short the head rarely reaches the disc edge — 1570 rate-bound but only 156
            # stop-bound), and it is the cells where BOTH bind that pin the ORDERING in a sweep
            # rather than in one constructed case. ⭐ `n_grew == 0` holds across FOUR DECADES of
            # limit (`10^(0.5…3)` through `10^(2…5)`), so the claim is not a property of this band.
            let rng = Xoshiro(3539), n_grew = 0, n_rate = 0, n_stop = 0, n_both = 0,
                stop = deg2rad(20.0)
                for _ in 1:4000
                    r = deg2rad(20.0) * rand(rng); φ = 2π * rand(rng)
                    h_az = r * cos(φ); h_el = r * sin(φ)             # INSIDE or ON the stop
                    t_az = 0.9 * randn(rng); t_el = 0.6 * randn(rng)
                    τ = 10.0^(-3 + 3 * rand(rng))
                    rate = 10.0^(1 + 3 * rand(rng))                  # rad/s
                    e0 = off_axis_angle(h_az, h_el, t_az, t_el)
                    f = head_slew_full(h_az, h_el, t_az, t_el, τ, dt, stop; rate_max = rate)
                    off_axis_angle(f[1], f[2], t_az, t_el) > e0 + 1e-15 && (n_grew += 1)
                    on_stop = hypot(f[1], f[2]) ≥ prevfloat(stop)
                    f[4] && (n_rate += 1)
                    on_stop && (n_stop += 1)
                    f[4] && on_stop && (n_both += 1)
                end
                @test n_grew == 0
                @test n_rate > 200 && n_stop > 200   # BOTH limits really bound — not vacuous
                @test n_both > 50                    # ...and both on the SAME tick, 83 measured
            end

            # ⭐ THE DEMAND IS PRE-LIMIT, AND IT IS WHAT §0.2's PROBE MEASURED. Gate 0 read the
            # demanded rate as a finite difference on the head's own angles with NO limit present —
            # i.e. what the head ACTUALLY DID, which is exactly what a limit would clip — so the
            # kernel's `demand` is pinned AGAINST that finite difference, not against its own
            # formula. ⚠ And it does NOT move when the limit binds: it is the demand, not the
            # delivery, which is what makes it a telemetry quantity worth shipping.
            let h = (0.10, -0.05), t = (0.90, 0.40), τ = 0.05, stop = deg2rad(80.0)
                fr = head_slew_full(h..., t..., τ, dt, stop)
                @test fr[3] ≈ hypot(fr[1] - h[1], fr[2] - h[2]) atol = 1e-15   # the finite diff
                @test fr[4] === false
                let cap_r = 0.5 * fr[3] / dt, fl = head_slew_full(h..., t..., τ, dt, stop;
                                                                  rate_max = cap_r)
                    @test fl[3] === fr[3]                                      # UNMOVED by the cap
                    @test fl[4] === true
                    @test hypot(fl[1] - h[1], fl[2] - h[2]) ≈ cap_r * dt atol = 1e-15
                end
            end
            # ...and `head_slew` IS its first two elements — the delegation, so there is ONE
            # implementation and the flag cannot disagree with the pointing it reports on
            let rng = Xoshiro(3540), n_bad = 0
                for _ in 1:2000
                    a = (0.5 * randn(rng), 0.3 * randn(rng), 0.5 * randn(rng), 0.3 * randn(rng))
                    τ = 10.0^(-3 + 3 * rand(rng)); rt = 10.0^(0.5 + 2.5 * rand(rng))
                    f = head_slew_full(a..., τ, dt, deg2rad(30.0); rate_max = rt)
                    head_slew(a..., τ, dt, deg2rad(30.0); rate_max = rt) === (f[1], f[2]) ||
                        (n_bad += 1)
                end
                @test n_bad == 0
            end

            # ⚠ THE DEGENERATE TABLE (convention 5), and the NaN-cap rows are here because the
            # gate-0 probe patch GOT THEM WRONG: under the plan's own `step ≤ cap` shorthand the
            # DEFAULT `rate_max = Inf` at `Δt = 0` gives `cap = Inf·0.0 = NaN`, falls into the
            # limiting branch, and returns NaN — regressing three of slice 34's shipped degenerates.
            # Guarding the BINDING branch (`step > cap`) makes every non-finite cap inert for free.
            let h_az = 0.31, h_el = -0.17, t_az = -0.44, t_el = 0.22
                @test head_slew(h_az, h_el, t_az, t_el, 0.05, 0.0, Inf;
                                rate_max = 1.0) === (h_az, h_el)     # dt = 0, FINITE rate
                @test head_slew(h_az, h_el, t_az, t_el, 0.05, -1.0, Inf;
                                rate_max = 1.0) === (h_az, h_el)     # dt < 0
                @test head_slew(h_az, h_el, t_az, t_el, 0.05, 0.0, Inf;
                                rate_max = Inf) === (h_az, h_el)     # the DEFAULT's own NaN cap
                # ⭐ AND `τ = 0 ∧ dt = 0` PARTS COMPANY WITH SLICE 34 — the one row where a finite
                # limit is STRICTLY STRONGER than the unlimited head, and it is the physical
                # answer: `cap = rate·Δt` is ZERO at `Δt = 0`, so a servo with a finite rate cannot
                # teleport in zero time, and the exact-landing ASSIGNMENT is unreachable. Slice
                # 34's row survives for the DEFAULT (`cap = Inf·0.0 = NaN` ⇒ no limit) and is
                # asserted as such above. ⚠ Written as an EQUALITY to the frozen head rather than
                # as "it did not land": the two are the same bits, which is the `rate_max ≤ 0`
                # identity below arriving from a third direction.
                @test head_slew(h_az, h_el, t_az, t_el, 0.0, 0.0, Inf;
                                rate_max = 1.0) === (h_az, h_el)
                @test head_slew(h_az, h_el, t_az, t_el, 0.0, 0.0, Inf; rate_max = 1.0) ===
                      head_slew(h_az, h_el, t_az, t_el, Inf, dt, Inf)
                @test head_slew(h_az, h_el, t_az, t_el, 0.0, 0.0, Inf) === (t_az, t_el)  # slice 34
                # a NaN rate is NO limit, never a NaN head (convention 6's direction — the same
                # posture `head_clamp` takes for a NaN stop, and by the same `>` branch)
                @test head_slew(h_az, h_el, t_az, t_el, 0.05, dt, Inf; rate_max = NaN) ===
                      head_slew(h_az, h_el, t_az, t_el, 0.05, dt, Inf)
                @test head_slew_full(h_az, h_el, t_az, t_el, 0.05, dt, Inf; rate_max = NaN)[4] ===
                      false
                # ⭐ `rate_max ≤ 0` FREEZES THE HEAD — and by `off_axis_angle`'s identity that is
                # slice 34's `τ = Inf` reductio reached from the OTHER SIDE, so the two are pinned
                # to AGREE bit-for-bit rather than merely to "both be frozen". Both reduce to
                # `head + wrap_angle(err)·(…)·0.0`, which is why `===` is reachable at all.
                let frozen = head_slew(h_az, h_el, t_az, t_el, Inf, dt, Inf)
                    for dead in (0.0, -0.0, -1.0, -1.0e9)
                        p = head_slew(h_az, h_el, t_az, t_el, 0.05, dt, Inf; rate_max = dead)
                        @test p === frozen
                        @test p === (h_az, h_el)
                    end
                end
                # ⚠ the SIGNED-ZERO corner, paired exactly as the `τ = Inf` freeze is above: the
                # frozen head adds `±0.0`, and `-0.0 + 0.0` is `+0.0` — so the freeze is `===` for
                # every head this slice can reach and `==` at that one point
                @test head_slew(-0.0, 0.5, 0.4, 0.5, 0.05, dt, Inf; rate_max = 0.0)[1] === 0.0
                @test head_slew(-0.0, 0.5, 0.4, 0.5, 0.05, dt, Inf; rate_max = 0.0)[1] == -0.0
                # a caged head under a live rate limit is still the STRAPDOWN seeker, to the bit
                for dead in (0.0, -1.0)
                    p = head_slew(h_az, h_el, t_az, t_el, 0.05, dt, dead; rate_max = 5.0)
                    @test iszero(p[1]) && iszero(p[2])
                    @test off_axis_angle(p[1], p[2], 0.21, -0.13) ===
                          off_axis_angle(0.0, 0.0, 0.21, -0.13)
                end
                # convention 6 — finite in, finite out, at any magnitude, under a live limit
                @test all(isfinite, head_slew(h_az, h_el, 1.0e9, -1.0e9, 1.0e-9, dt, 1.0e9;
                                              rate_max = 1.0e-9))
                @test all(isfinite, head_slew(h_az, h_el, 1.0e9, -1.0e9, 1.0e-9, dt, 1.0e9;
                                              rate_max = 1.0e9))
                # a NaN τ still PROPAGATES (validate-at-LOAD's business), and does not bind the cap
                @test all(isnan, head_slew(h_az, h_el, t_az, t_el, NaN, dt, Inf; rate_max = 5.0))
                @test head_slew_full(h_az, h_el, t_az, t_el, NaN, dt, Inf; rate_max = 5.0)[4] ===
                      false
                # `Real`, not `Float64` — the kwarg takes the same widening as the positionals
                @test head_slew(0, 0, 1, 1, 0, 1, 10; rate_max = 1) ===
                      head_slew(0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 10.0; rate_max = 1.0)
            end
        end
    end
end
