# test_guidance.jl — the missile guidance kernel vs its closed forms (HANDOFF §10 item 9,
# slice 9 gate 1).
#
# Like dynamics/frames these are DETERMINISTIC (no RNG in the missile arc), so every check
# is an exact closed form with an EXPLICIT atol (never rtol-`≈0`, which passes trivially).
# The §2 headline is the P-only steady-state undershoot `1/(1+Kp)` — the `½·g·dt·t` of
# slice 9 — pinned at the probe values `Kp=2 → 1/3`, `Kp=8 → 1/9` (closed-form, NOT
# calibrated-to-pass); integral drives it to 0; derivative damps the integral-induced
# ringing (the ordering anchor, like slice-1's Swerling-loss ordering). The §1 pursuit law
# is pinned on the ⟂-to-velocity identity, the LOS-side SIGN (the frames.jl discipline),
# and the tail-chase `‖a_cmd‖`-grows-toward-intercept (the slice-10 tee-up as a test).

@testset "guidance / pursuit law + PID autopilot" begin
    norm3_test(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)   # test-local (no LinearAlgebra dep)
    dt = 1e-3

    # Settle the inner loop under a CONSTANT command, returning (a_ach_final, peak_magnitude).
    # The peak captures overshoot/ringing; the final captures the steady-state.
    function settle(mode; kp, ki, kd, tau, a_cmd, tsettle = 8.0)
        st = autopilot_init()
        a  = zero(Vec3)
        peak = 0.0
        for _ in 1:round(Int, tsettle / dt)
            a, st = autopilot_step(mode, a_cmd, st, dt; kp = kp, ki = ki, kd = kd, tau = tau)
            peak = max(peak, norm3_test(a))
        end
        return a, peak
    end

    @testset "P-only steady-state undershoot == 1/(1+Kp) (the §2 headline)" begin
        a_cmd = Vec3(100.0, 0.0, 0.0)
        # Plant τ·ȧ = u − a with u = Kp·(a_cmd − a) has the exact fixed point
        # a* = Kp/(1+Kp)·a_cmd (Euler preserves it), so e_ss/a_cmd = 1/(1+Kp) exactly.
        for (kp, target) in ((2.0, 1/3), (8.0, 1/9))
            a, _ = settle(:pid; kp = kp, ki = 0.0, kd = 0.0, tau = 0.3, a_cmd = a_cmd)
            ratio = norm3_test(a_cmd - a) / norm3_test(a_cmd)
            @test ratio ≈ target atol = 1e-4                     # probe: 0.333333 / 0.111111
        end
    end

    @testset "integral drives the steady-state error to ~0" begin
        a_cmd = Vec3(100.0, 0.0, 0.0)
        # Same Kp=2 (which alone leaves 1/3 undershoot), now with Ki>0 → e_ss → 0.
        a, _ = settle(:pid; kp = 2.0, ki = 10.0, kd = 0.0, tau = 0.3, a_cmd = a_cmd)
        ratio = norm3_test(a_cmd - a) / norm3_test(a_cmd)
        @test ratio < 1e-6                                        # probe: ~1e-14 fully settled
    end

    @testset "derivative damps the integral-induced ringing (ordering anchor)" begin
        a_cmd = Vec3(100.0, 0.0, 0.0)
        # A strongly-integral loop (Ki=40) genuinely overshoots (~27%); adding derivative
        # reduces the overshoot peak. (At tiny Ki the naive derivative-on-error first-step
        # KICK would dominate — the honest boundary; we anchor where the I-ringing is real.)
        _, peak_PI  = settle(:pid; kp = 2.0, ki = 40.0, kd = 0.0, tau = 0.3, a_cmd = a_cmd)
        _, peak_PID = settle(:pid; kp = 2.0, ki = 40.0, kd = 0.1, tau = 0.3, a_cmd = a_cmd)
        @test peak_PI  > norm3_test(a_cmd)          # PI overshoots (probe: ~127 vs cmd 100)
        @test peak_PID < peak_PI                     # D damps it (probe: ~123 < 127)
    end

    @testset ":ideal is exact passthrough (the perfect-actuator reference)" begin
        a_cmd = Vec3(12.0, -3.0, 7.0)
        st0 = autopilot_init()
        a, st1 = autopilot_step(:ideal, a_cmd, st0, dt; kp = 5.0, ki = 9.0, kd = 0.2)
        @test a === a_cmd                            # bit-exact passthrough (SVector identity)
        @test st1 === st0                            # state untouched (the loop is dormant)
        # gains are inert under :ideal (the documented "PID sliders do nothing when ideal")
        a2, _ = autopilot_step(:ideal, a_cmd, st0, dt; kp = 0.0, ki = 0.0, kd = 0.0)
        @test a2 === a_cmd
    end

    @testset "pursuit_accel geometry — ⟂ to velocity, LOS-side sign, tail-chase growth" begin
        # ⟂ to heading: perp·v̂ = 0 by construction (a pure turn, the coast assumption).
        m_pos = Vec3(0.0, 0.0, 1000.0)
        m_vel = Vec3(600.0, 0.0, 0.0)
        for t_pos in (Vec3(8000.0, 3000.0, 1000.0), Vec3(5000.0, -2000.0, 1500.0))
            a_cmd = pursuit_accel(m_pos, m_vel, t_pos; k_guid = 3.0)
            v̂ = m_vel / norm3_test(m_vel)
            @test (a_cmd[1]*v̂[1] + a_cmd[2]*v̂[2] + a_cmd[3]*v̂[3]) ≈ 0.0 atol = 1e-9
        end
        # LOS-side SIGN (the frames.jl LOS discipline): a target on the +y side of the +x
        # heading commands a +y turn; a target on the −y side commands a −y turn.
        a_left  = pursuit_accel(m_pos, m_vel, Vec3(8000.0,  3000.0, 1000.0); k_guid = 3.0)
        a_right = pursuit_accel(m_pos, m_vel, Vec3(8000.0, -3000.0, 1000.0); k_guid = 3.0)
        @test a_left[2]  > 0.0
        @test a_right[2] < 0.0
        # Tail-chase: on a fixed lateral-offset closing geometry, ‖a_cmd‖ GROWS as range
        # closes (the angle off boresight opens toward abeam) — the slice-10 tee-up.
        t_fixed = Vec3(8000.0, 800.0, 1000.0)
        far  = pursuit_accel(Vec3(0.0,    0.0, 1000.0), m_vel, t_fixed; k_guid = 3.0)
        near = pursuit_accel(Vec3(7000.0, 0.0, 1000.0), m_vel, t_fixed; k_guid = 3.0)
        @test norm3_test(near) > norm3_test(far)
    end

    @testset "pn_accel — collision-course-zero anchor + PN-vs-pursuit contrast (Lesson 1)" begin
        # The DEFINING PN property (the sailor's rule, an EXTERNAL anchor not a round-trip):
        # on a constant-bearing / decreasing-range COLLISION course ω = 0 → a_cmd = 0. Build a
        # genuine collision triangle: target crossing +y, missile leading it so the relative
        # velocity is PURE closing (anti-parallel to the LOS). Missile heading (600,300,0),
        # target (5000,0,0) moving (0,300,0) → v_rel = (−600,0,0) ∥ −r → ω = 0.
        m_col = Vec3(0.0, 0.0, 0.0); mv_col = Vec3(600.0, 300.0, 0.0)
        t_col = Vec3(5000.0, 0.0, 0.0); tv_col = Vec3(0.0, 300.0, 0.0)
        a_pn  = pn_accel(m_col, mv_col, t_col, tv_col; N = 4.0)
        @test norm3_test(a_pn) < 1e-9                       # PN: nothing to do, lead is set
        # THE CONTRAST (Lesson 1, static form): at that SAME collision geometry pursuit still
        # commands a big turn — it chases the target POSITION, wastefully breaking the triangle.
        a_pur = pursuit_accel(m_col, mv_col, t_col; k_guid = 3.0)
        @test norm3_test(a_pur) > 500.0                     # probe: 900 m/s² — PN ≪ pursuit
        # Move OFF the collision course (add lateral relative velocity) → ω ≠ 0 → PN grows off
        # its ~0 floor (the "PN falls TOWARD collision" signature, read in reverse).
        a_off = pn_accel(m_col, mv_col, t_col, Vec3(0.0, 600.0, 0.0); N = 4.0)
        @test norm3_test(a_off) > 100.0                     # probe: 144 m/s² ≫ collision ~0
    end

    @testset "pn_accel — crossing geometry: ⟂ LOS, magnitude, SIGN (both sign sources)" begin
        # Missile at origin heading +x at vm; target ahead at (D,0,0) CROSSING +y at vy. Closed
        # form: û=(1,0,0), Vc=vm, ω=(0,0,vy/D), a_cmd = N·Vc·(ω×û) = (0, N·vm·vy/D, 0).
        vm, D, vy, N = 600.0, 5000.0, 200.0, 4.0
        m_pos = Vec3(0.0, 0.0, 0.0); m_vel = Vec3(vm, 0.0, 0.0); t_pos = Vec3(D, 0.0, 0.0)
        a_cmd = pn_accel(m_pos, m_vel, t_pos, Vec3(0.0, vy, 0.0); N = N)
        û = los_unit(m_pos, t_pos)
        # ⟂ to the LOS (a_cmd·û == 0 — the ω×û construction).
        @test (a_cmd[1]*û[1] + a_cmd[2]*û[2] + a_cmd[3]*û[3]) ≈ 0.0 atol = 1e-9
        # INDEPENDENT recompute — the closed form N·vm·vy/D is a DIFFERENT expression than the
        # cross-product path (advisor: the structural ‖a‖=N·Vc·‖ω‖ identity holds for ANY impl —
        # even the magnitude-preserving `û×ω` order flip — so pin the concrete vector instead).
        @test a_cmd ≈ Vec3(0.0, N*vm*vy/D, 0.0) atol = 1e-9        # probe: (0, 96, 0)
        # SIGN source #1 (crossing sense — keys off target VELOCITY, unlike pursuit's position):
        # a +y-crossing target commands a +y lead; flip the crossing to −y and the lead flips.
        # A `û×ω` order swap OR a `+range_rate` Vc-sign flip would send BOTH the wrong way.
        a_neg = pn_accel(m_pos, m_vel, t_pos, Vec3(0.0, -vy, 0.0); N = N)
        @test a_cmd[2] > 0.0                                       # lead +y for +y crossing
        @test a_neg[2] < 0.0                                       # lead −y for −y crossing
        @test a_neg ≈ Vec3(0.0, -N*vm*vy/D, 0.0) atol = 1e-9      # symmetric magnitude
        # N-linearity (SIGN source #2 lives in Vc's sign, exercised above): the gain does what
        # it says — magnitude linear in N.
        a_2N = pn_accel(m_pos, m_vel, t_pos, Vec3(0.0, vy, 0.0); N = 2*N)
        @test norm3_test(a_2N) ≈ 2 * norm3_test(a_cmd) atol = 1e-9
    end

    @testset "pn_accel refactor — byte-identical truth path + from_omega recompute (slice 11)" begin
        # The slice-11 `pn_accel_from_omega` seam must keep the slice-10 truth path BIT-IDENTICAL
        # (convention 2 — a reassociation would 1-ULP-desync slice-10 replay). On the slice10_pn
        # engagement geometry, the wrapper reproduces the slice-10 INLINE arithmetic
        # `(N·Vc)·_cross(ω,û)` EXACTLY (===, SVector bit-equality) — NOT `≈`.
        m_pos = Vec3(0.0, 0.0, 3000.0)
        m_vel = Vec3(700*cos(deg2rad(12)), 0.0, 700*sin(deg2rad(12)))
        t_pos = Vec3(6000.0, 0.0, 4200.0); t_vel = Vec3(-800.0, 0.0, 200.0); N = 4.0
        r = t_pos - m_pos; v = t_vel - m_vel
        û = los_unit(m_pos, t_pos); ω = los_rate(r, v); Vc = -range_rate(r, v)
        inline = (N * Vc) * EWSim._cross(ω, û)                     # the exact slice-10 expression
        @test pn_accel(m_pos, m_vel, t_pos, t_vel; N = N) === inline
        @test pn_accel_from_omega(û, ω, Vc; N = N) === inline      # the wrapper delegates bit-exactly

        # INDEPENDENT recompute — expand ω×û component-wise and scale by N·Vc by hand (a
        # different expression path; a `û×ω` transpose in the impl would flip the sign vs this).
        ox, oy, oz = ω[1], ω[2], ω[3]; ux, uy, uz = û[1], û[2], û[3]
        hand = Vec3(oy*uz - oz*uy, oz*ux - ox*uz, ox*uy - oy*ux) * (N * Vc)
        @test pn_accel_from_omega(û, ω, Vc; N = N) ≈ hand atol = 1e-9

        # NO missile-velocity term in the seam (advisor #6): m_vel enters pn_accel ONLY through
        # û/ω/Vc, so reconstructing those from a different m_vel still reproduces it bit-exactly.
        m_vel2 = Vec3(500.0, 30.0, 120.0)
        v2 = t_vel - m_vel2; ω2 = los_rate(t_pos - m_pos, v2); Vc2 = -range_rate(t_pos - m_pos, v2)
        @test pn_accel(m_pos, m_vel2, t_pos, t_vel; N = N) === pn_accel_from_omega(û, ω2, Vc2; N = N)
    end

    @testset "pn_accel_augmented — APN feedforward: reduces to PN, ⟂-LOS, sign, N-scaling (slice 12)" begin
        # Crossing geometry (same as above): û=(1,0,0), base PN = (0, N·vm·vy/D, 0). The APN
        # feedforward adds (N/2)·a_T⊥ where a_T⊥ is the TARGET accel ⟂ LOS. RNG-free (truth a_T).
        vm, D, vy, N = 600.0, 5000.0, 200.0, 4.0
        m_pos = Vec3(0.0, 0.0, 0.0); m_vel = Vec3(vm, 0.0, 0.0); t_pos = Vec3(D, 0.0, 0.0); t_vel = Vec3(0.0, vy, 0.0)
        r = t_pos - m_pos; v = t_vel - m_vel
        û = los_unit(m_pos, t_pos); ω = los_rate(r, v); Vc = -range_rate(r, v)
        base = pn_accel_from_omega(û, ω, Vc; N = N)                # the plain-PN command (the anchor)

        # (1) a_T = 0 → the feedforward VANISHES → APN reduces to PN EXACTLY (introduce-safe /
        # :apn-on-CV ≈ :pn; == ignores signed-zero so the `+zero(Vec3)` +0.0 trap is harmless here).
        @test pn_accel_augmented(û, ω, Vc, zero(Vec3); N = N) == base

        # (2) DIRECT feedforward recompute — a DIFFERENT expression than the impl (catches a `−`
        # sign flip or a transpose). a_T with a ∥-LOS part (x) that MUST be projected out.
        a_T = Vec3(100.0, 200.0, 50.0)                            # ∥ part = x=100 (removed), ⟂ part = (0,200,50)
        a_apn = pn_accel_augmented(û, ω, Vc, a_T; N = N)
        ff_hand = (N / 2) * Vec3(0.0, 200.0, 50.0)               # (N/2)·a_T⊥, a_T⊥ hand-projected onto ⟂û
        @test (a_apn - base) ≈ ff_hand atol = 1e-9               # the feedforward is exactly (N/2)·a_T⊥
        @test a_apn ≈ base + ff_hand atol = 1e-9

        # (3) a_T ∥ û (a PURELY RADIAL maneuver) → a_T⊥ = 0 → NO feedforward (the projection kills
        # it; a radial accel changes range, not LOS rate, so PN needs no lead for it).
        @test pn_accel_augmented(û, ω, Vc, Vec3(777.0, 0.0, 0.0); N = N) == base

        # (4) the feedforward is ⟂ LOS (a_apn − base) · û == 0 — the (N/2)·a_T⊥ construction.
        @test EWSim._dot(a_apn - base, û) ≈ 0.0 atol = 1e-9

        # (5) SIGN — the feedforward ADDS along +a_T⊥ (a `−` would make :apn WORSE than :pn, the
        # silent failure). a_T with +y,+z ⟂-components → the command shifts +y,+z vs plain PN.
        @test a_apn[2] > base[2]                                  # +y target accel → +y feedforward
        @test a_apn[3] > base[3]                                  # +z target accel → +z feedforward
        # flip a_T⊥ → the feedforward flips (symmetric), still ⟂ LOS.
        a_flip = pn_accel_augmented(û, ω, Vc, Vec3(100.0, -200.0, -50.0); N = N)
        @test (a_flip - base) ≈ -ff_hand atol = 1e-9

        # (6) the feedforward scales with N (isolate it on a COLLISION course where base PN = 0, so
        # a_apn IS the pure feedforward (N/2)·a_T⊥ → doubling N doubles a_apn).
        m_c = Vec3(0.0, 0.0, 0.0); mv_c = Vec3(vm, 0.0, 0.0); t_c = Vec3(D, 0.0, 0.0); tv_c = Vec3(vm, 0.0, 0.0)
        rc = t_c - m_c; vc = tv_c - mv_c
        ûc = los_unit(m_c, t_c); ωc = los_rate(rc, vc); Vcc = -range_rate(rc, vc)
        @test pn_accel_from_omega(ûc, ωc, Vcc; N = N) == zero(Vec3)   # collision course → base PN = 0
        aN  = pn_accel_augmented(ûc, ωc, Vcc, a_T; N = N)
        a2N = pn_accel_augmented(ûc, ωc, Vcc, a_T; N = 2 * N)
        @test aN ≈ (N / 2) * Vec3(0.0, 200.0, 50.0) atol = 1e-9  # pure feedforward, base = 0
        @test a2N ≈ 2 * aN atol = 1e-9                            # linear in N

        # (7) the rung exists in the one-list source of truth (LIVE_FIDELITY_MODES references it).
        @test :apn in GUIDANCE_MODES
    end

    @testset "salvo — time_to_go + salvo_consensus + impact-time-control (slice 14 gate 1)" begin
        # The cooperative salvo law: t_go ≈ R/V_c, the team consensus t_d = max t_go, and an
        # impact-time-control command = PN base + a ⟂-LOS feedback that STRETCHES an early missile.
        # RNG-free (truth-fed PN, no seeker — class 4c). Every check is an explicit-atol closed form
        # or an independent recompute (convention 11 — no self-calibrated tautology).

        # (1) time_to_go = R / V_c on a clean closing geometry (V_c ≫ VC_FLOOR → the floor is inert).
        @test time_to_go(5000.0, 600.0) ≈ 5000.0 / 600.0 atol = 1e-12
        # the V_c → 0 / receding guard (convention 6): a bare R/V_c would blow up; the VC_FLOOR floor
        # gives a large-but-FINITE t_go = R/VC_FLOOR (NOT a "returns 0" sentinel — gate-0 FINDINGS).
        @test time_to_go(5000.0, 0.0)    === 5000.0 / EWSim.VC_FLOOR    # V_c = 0  → floored
        @test time_to_go(5000.0, -300.0) === 5000.0 / EWSim.VC_FLOOR    # receding → floored, finite
        @test isfinite(time_to_go(5000.0, -1e9))                        # never Inf/NaN

        # (2) salvo_consensus = maximum (the SLOWEST missile sets the pace) + the SINGLETON additivity
        # anchor: one element → itself, bit-exact `===` (the :salvo-on-a-solo bridge — convention 11).
        @test salvo_consensus((3.0, 7.0, 5.0)) == 7.0
        @test salvo_consensus([2.0, 9.0, 4.0]) == 9.0
        @test salvo_consensus((4.2,)) === 4.2                           # singleton → itself, bit-exact

        # (3) the cooperation rung is in the one-list source of truth (LIVE_FIDELITY_MODES refs it, gate 2).
        @test COOPERATION_MODES === (:solo, :salvo)

        # ---- impact_time_control_accel on a fixed geometry (missile with a ⟂-LOS velocity handle) ----
        m_pos = Vec3(0.0, 0.0, 0.0); m_vel = Vec3(600.0, 100.0, 0.0)    # heading +x with a +y ⟂ component
        t_pos = Vec3(5000.0, 0.0, 0.0); t_vel = Vec3(0.0, 0.0, 0.0)     # stationary target on the +x LOS
        N = 4.0; K_it = 0.45
        base = pn_accel(m_pos, m_vel, t_pos, t_vel; N = N)              # the PN base term (REUSED unchanged)
        û    = los_unit(m_pos, t_pos)                                   # = (1,0,0)
        v⊥   = m_vel - EWSim._dot(m_vel, û) * û                         # = (0,100,0), the ⟂-LOS velocity

        # (4) BIT-EXACT no-op at err == 0 (t_d == this missile's own t_go): the command `===` plain PN
        # via the EARLY RETURN of pn_accel(...) — NOT `base + zero(Vec3)` (whose −0.0+0.0→+0.0 flips a
        # sign bit). The LAW-LEVEL solo degenerate anchor (gate-0 FINDINGS moved it here).
        Vc0  = -range_rate(t_pos - m_pos, t_vel - m_vel)               # recompute V_c the impl's way
        tgo0 = time_to_go(los_range(m_pos, t_pos), Vc0)                # ...and t_go → t_d = tgo0 ⇒ err = 0.0
        @test impact_time_control_accel(m_pos, m_vel, t_pos, t_vel, tgo0; N = N, K_it = K_it) === base

        # (5) DIRECT feedback recompute — a DIFFERENT expression than the impl (catches a transpose /
        # sign slip). An EARLY missile (t_d > t_go ⇒ err > 0) gets base + K_it·err·‖v‖·v̂⊥.
        t_d  = tgo0 + 0.6667                                           # t_d > t_go ⇒ err ≈ +0.6667 (EARLY)
        a    = impact_time_control_accel(m_pos, m_vel, t_pos, t_vel, t_d; N = N, K_it = K_it)
        err  = t_d - tgo0
        fb_hand = (K_it * err * norm3_test(m_vel)) * (v⊥ / norm3_test(v⊥))
        @test (a - base) ≈ fb_hand atol = 1e-9                         # the feedback is exactly K_it·err·‖v‖·v̂⊥
        @test a ≈ base + fb_hand atol = 1e-9

        # (6) THE SIGN ANCHOR (the trifecta trap) — an EARLY missile flies a LONGER arc. The feedback
        # lies along +v⊥ (grows the heading error → longer path → later arrival, the intended delay).
        # A kinematic assertion (dot with the ⟂-LOS velocity > 0), NOT a self-calibrated round-trip.
        @test EWSim._dot(a - base, v⊥) > 0.0                           # feedback along +v⊥ ⇒ delay
        # a LATE missile (t_d < t_go ⇒ err < 0) flips it (shortens toward the LOS — symmetric).
        a_late = impact_time_control_accel(m_pos, m_vel, t_pos, t_vel, tgo0 - 0.5; N = N, K_it = K_it)
        @test EWSim._dot(a_late - base, v⊥) < 0.0

        # (7) the head-on guard — a missile flying STRAIGHT down the LOS has no ⟂ handle (‖v⊥‖ ≈ 0),
        # so the feedback is undefined this tick → return the PN base (`===`), even with err ≠ 0.
        m_head = Vec3(600.0, 0.0, 0.0)                                 # v ∥ û ⇒ v⊥ = 0
        base_h = pn_accel(m_pos, m_head, t_pos, t_vel; N = N)
        @test impact_time_control_accel(m_pos, m_head, t_pos, t_vel, tgo0 + 2.0; N = N, K_it = K_it) === base_h

        # (8) BOUNDED as V_c → 0 (the ITCG terminal blow-up, distinct from PN's r→0): an abeam
        # geometry (V_c = 0) floors t_go via VC_FLOOR → the command stays FINITE (no Inf/NaN to JSON).
        m_ab = Vec3(0.0, 600.0, 0.0)                                   # flying +y, abeam the +x target
        a_ab = impact_time_control_accel(m_pos, m_ab, t_pos, t_vel, 9.0; N = N, K_it = K_it)
        @test all(isfinite, a_ab)
    end

    @testset "pn_accel — degenerate guards + endgame r→0 (finite, then CONSUMER-clamped)" begin
        # v→0 (relative velocity zero: missile matches target velocity) → ω=0, Vc=0 → zero.
        @test pn_accel(Vec3(0,0,0), Vec3(600,0,0), Vec3(5000,0,0), Vec3(600,0,0); N=4.0) == zero(Vec3)
        # coincident missile/target (zero LOS) → zero, finite (no NaN).
        a0 = pn_accel(Vec3(5,5,5), Vec3(600,0,0), Vec3(5,5,5), Vec3(0,0,0); N=4.0)
        @test a0 == zero(Vec3)
        @test all(isfinite, a0)
        # zero closing speed (Vc=0, pure-abeam instant: r ⟂ v_rel) → zero command (the N·Vc factor).
        @test pn_accel(Vec3(0,0,0), Vec3(0,0,0), Vec3(5000,0,0), Vec3(0,200,0); N=4.0) == zero(Vec3)
        # huge N stays finite (the a_max clamp caps it at the consumer — gate 2).
        ahuge = pn_accel(Vec3(0,0,0), Vec3(600,0,0), Vec3(5000,0,0), Vec3(0,200,0); N=1e9)
        @test all(isfinite, ahuge)
        # ENDGAME r→0 (HANDOFF §10.10): pn_accel alone is huge-but-FINITE (frames' 1e-12 guard is
        # far too small — probe: 3.84e6 at r=0.125 m). It is bounded at the CONSUMER, NOT here:
        # the r_stop cutoff + a_max clamp live in decide! (gate 2). Gate-1 form (advisor): finite,
        # and clamp_accel caps it to a_max.
        a_end = pn_accel(Vec3(0,0,0), Vec3(600,0,0), Vec3(0.125,0,0), Vec3(0,200,0); N=4.0)
        @test all(isfinite, a_end)
        @test norm3_test(a_end) > 1e5                              # genuinely huge (probe: 3.84e6)
        @test norm3_test(clamp_accel(a_end, 300.0)) ≈ 300.0 atol = 1e-6   # consumer bounds it
    end

    @testset "clamp_accel caps magnitude, preserves direction, zero-safe" begin
        # |a|=500 > a_max=100 → scaled to 100 along the same direction (0.6,0.8,0).
        capped = clamp_accel(Vec3(300.0, 400.0, 0.0), 100.0)
        @test norm3_test(capped) ≈ 100.0 atol = 1e-9
        @test capped ≈ Vec3(60.0, 80.0, 0.0) atol = 1e-9
        # |a| ≤ a_max → returned unchanged (bit-exact — the clamp never binds in-scenario).
        small = Vec3(3.0, 4.0, 0.0)
        @test clamp_accel(small, 100.0) === small
        # zero-safe: no NaN at a = 0 (apex / no command).
        z = clamp_accel(zero(Vec3), 100.0)
        @test z == zero(Vec3)
        @test all(isfinite, z)
    end

    @testset "degenerate guards — v→0, coincident, huge gains (no throw / no NaN)" begin
        # pursuit: zero speed (apex/launch) → zero command
        @test pursuit_accel(Vec3(0,0,0), zero(Vec3), Vec3(1000,0,0)) == zero(Vec3)
        # pursuit: coincident missile/target (zero LOS) → zero command, finite
        a0 = pursuit_accel(Vec3(5,5,5), Vec3(600,0,0), Vec3(5,5,5))
        @test a0 == zero(Vec3)
        @test all(isfinite, a0)
        # pursuit: a huge k_guid stays finite (the clamp then caps it in the subsystem)
        ahuge = pursuit_accel(Vec3(0,0,1000), Vec3(600,0,0), Vec3(8000,3000,1000); k_guid = 1e9)
        @test all(isfinite, ahuge)
        @test norm3_test(clamp_accel(ahuge, 300.0)) ≈ 300.0 atol = 1e-6
        # autopilot: a SINGLE step with huge gains / τ→0 stays finite (multi-step stability
        # is the subsystem's a_max job — gate 2). No throw, no immediate NaN.
        a, st = autopilot_step(:pid, Vec3(100,0,0), autopilot_init(), dt;
                               kp = 1e6, ki = 1e6, kd = 1e3, tau = 0.0)
        @test all(isfinite, a)
        @test all(isfinite, st.a_ach) && all(isfinite, st.e_int) && all(isfinite, st.e_prev)
        # unknown rung throws (the wire is validated against AUTOPILOT_MODES, so this is a
        # programming-error guard, like integrator_step's)
        @test_throws ErrorException autopilot_step(:bogus, Vec3(1,0,0), autopilot_init(), dt)
    end
end
