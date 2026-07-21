# test_airframe3d.jl — the 6-DOF substrate + skid-to-turn library vs its structural invariants
# and closed forms (HANDOFF §11 Tier A, slice 23 gate 1). Deterministic, so every check is an
# EXPLICIT atol (never rtol-`≈0` — convention 11). The §1 co-headline is SIGNS: the body↔inertial
# `rotate` direction and the per-axis ω sign are the #1 trap's FIFTH occurrence, so they are pinned
# BY SIGN (a magnitude-only test would survive a double flip). Teeth mirror the gate-0 probes.

@testset "airframe3d / 6-DOF substrate + skid-to-turn" begin
    # A representative slender missile (gate-0 probe family, temp/slice23_gate0).
    MASS = 140.0; S = 0.05; d = 1.0; Iyy = 60.0
    Cma = -2.0; Cmd = 3.0; Cmq = -5.0; ρ = 1.225; Cla = 20.0
    Idiag = Vec3(2.0, Iyy, Iyy)                 # I_xx ≪ I_yy = I_zz (slender missile)
    par(rho=ρ) = AirframeParams(S, d, Iyy, Cma, Cmd, Cmq, rho, Cla, 0.0)
    # attitudes with the nose along a chosen direction (matches lift_accel's θ convention).
    att_pitch(θ) = quat_from_two_vectors(Vec3(1.0,0.0,0.0), Vec3(cos(θ),0.0,sin(θ)))
    att_yaw(ψ)   = quat_from_two_vectors(Vec3(1.0,0.0,0.0), Vec3(cos(ψ),sin(ψ),0.0))
    norm3(v) = sqrt(v[1]^2+v[2]^2+v[3]^2)
    dot3(a,b) = a[1]*b[1]+a[2]*b[2]+a[3]*b[3]

    @testset "body_incidence: α = θ−γ in-plane, β = 0; n̂_pitch = (−sinγ,0,cosγ)" begin
        θ, γ = 0.10, 0.03
        q = att_pitch(θ); v = 800.0*Vec3(cos(γ),0.0,sin(γ))
        α, β = body_incidence(q, v)
        @test isapprox(α, θ-γ; atol=1e-12)
        @test isapprox(β, 0.0; atol=1e-12)
        np, ny = body_perp_axes(q, v/norm3(v))
        @test isapprox(np, Vec3(-sin(γ),0.0,cos(γ)); atol=1e-12)
        # yaw axis is +y for a pitch-only attitude
        @test isapprox(ny, Vec3(0.0,1.0,0.0); atol=1e-12)
    end

    @testset "lift_accel_3d reduces to lift_accel in-plane; +α ⇒ γ̇ > 0 (#1 sign trap)" begin
        θ = 0.08; γ = 0.0; p = par()
        q = att_pitch(θ); v = 800.0*Vec3(cos(γ),0.0,sin(γ))
        a3 = lift_accel_3d(v, q, MASS, p)
        aref = lift_accel(v, θ, MASS, p)
        @test isapprox(a3, aref; atol=1e-9)              # 3-D superset ≡ pitch-plane lift
        @test isapprox(dot3(a3, v/norm3(v)), 0.0; atol=1e-9)   # ⟂ v
        @test a3[3] > 0.0                                # +α, Cla>0 ⇒ lift UP ⇒ γ̇ > 0
        # mirror: nose BELOW velocity ⇒ lift DOWN (a double flip would survive |·|)
        @test lift_accel_3d(v, att_pitch(-θ), MASS, p)[3] < 0.0
    end

    @testset "yaw sign: +β ⇒ side-force toward +y, ⟂ v" begin
        ψ = 0.08; p = par()
        q = att_yaw(ψ); v = 800.0*Vec3(1.0,0.0,0.0)
        α, β = body_incidence(q, v)
        @test β > 0.0 && isapprox(α, 0.0; atol=1e-12)
        a3 = lift_accel_3d(v, q, MASS, p)
        @test a3[2] > 0.0                                # side-force toward +y
        @test isapprox(dot3(a3, v/norm3(v)), 0.0; atol=1e-9)   # ⟂ v
        @test isapprox(a3[3], 0.0; atol=1e-9)            # no out-of-yaw-plane component
    end

    @testset "attitude_kinematics + quaternion round-trip" begin
        q = att_pitch(0.2)
        v = Vec3(3.0,-4.0,5.0)
        @test isapprox(rotate_inv(q, rotate(q, v)), v; atol=1e-12)
        # +ω_y rotates the nose +x→−z (gate-0 C1 — the convention the moment mapping accounts for)
        qk = q; dt = 1e-4
        for _ in 1:1000; qk = qnormalize(qk + dt*attitude_kinematics(qk, Vec3(0.0,0.5,0.0))); end
        nz0 = rotate(att_pitch(0.2), Vec3(1.0,0.0,0.0))
        nz1 = rotate(qk, Vec3(1.0,0.0,0.0))
        @test nz1[3] < nz0[3]                            # nose z decreased ⇒ +ω_y pitched down
    end

    @testset "body_rate_deriv: ω×(I·ω) = 0 at single-axis ω, nonzero when tumbling" begin
        # single-axis (pure pitch rate) ⇒ gyroscopic term vanishes ⇒ ω̇ = M/I exactly
        M = Vec3(0.0, 12.0, 0.0)
        wd = body_rate_deriv(Vec3(0.0, 3.0, 0.0), M, Idiag)
        @test isapprox(wd, Vec3(0.0, 12.0/Iyy, 0.0); atol=1e-12)
        # a tumbling ω (two axes) ⇒ the coupling term is LIVE (I_xx ≠ I_yy)
        ω = Vec3(4.0, 0.0, 2.0)
        Iω = Vec3(Idiag[1]*ω[1], Idiag[2]*ω[2], Idiag[3]*ω[3])
        cpl = Vec3(ω[2]*Iω[3]-ω[3]*Iω[2], ω[3]*Iω[1]-ω[1]*Iω[3], ω[1]*Iω[2]-ω[2]*Iω[1])
        @test norm3(cpl) > 1.0                            # not a decorative zero
        @test isapprox(body_rate_deriv(ω, zero(Vec3), Idiag),
                       Vec3(-cpl[1]/Idiag[1], -cpl[2]/Idiag[2], -cpl[3]/Idiag[3]); atol=1e-9)
    end

    # A local 6-DOF driver (open-loop, fixed δ) and the SCALAR rk4_coupled reference (replicates
    # _integrate_coupled!'s else-arm) for the reduction and structural-invariant teeth.
    function run6(; θ0, γ0, δp, δy, ωx0=0.0, n, dt=1e-3, rho=ρ, cd=0.0)
        p = par(rho)
        pos=Vec3(0.,0.,5000.); v=800.0*Vec3(cos(γ0),0.0,sin(γ0)); q=att_pitch(θ0); ω=Vec3(ωx0,0.,0.)
        f=(P,Vv,Q,W)->(Vv, total_accel(Vv;rho=rho,cd_area=cd,mass=MASS)+lift_accel_3d(Vv,Q,MASS,p),
                       attitude_kinematics(Q,W),
                       body_rate_deriv(W, stt_moments(Q,Vv,W,δp,δy,p;c_roll=50.0), Idiag))
        stats=(mp=0.0,mr=0.0,mβ=0.0,mqx=0.0,mqz=0.0)
        for _ in 1:n
            pos,v,q,ω = rk4_6dof(f,pos,v,q,ω,dt)
            _,β = body_incidence(q,v)
            stats=(mp=max(stats.mp,abs(ω[1])), mr=max(stats.mr,abs(ω[3])), mβ=max(stats.mβ,abs(β)),
                   mqx=max(stats.mqx,abs(q[2])), mqz=max(stats.mqz,abs(q[4])))
        end
        return pos, v, q, ω, stats
    end
    function run_scalar(; θ0, γ0, δp, n, dt=1e-3, rho=ρ, cd=0.0)
        p = par(rho)
        pos=Vec3(0.,0.,5000.); v=800.0*Vec3(cos(γ0),0.0,sin(γ0)); θ=θ0; qr=0.0
        f=(P,Vv,TH,Q)->begin γ=atan(Vv[3],Vv[1])
            (Vv, total_accel(Vv;rho=rho,cd_area=cd,mass=MASS)+lift_accel(Vv,TH,MASS,p),
             Q, pitch_moment(TH-γ,δp,Q,norm3(Vv),p)/p.I) end
        for _ in 1:n; pos,v,θ,qr=rk4_coupled(f,pos,v,θ,qr,dt); end
        return pos, v
    end

    @testset "P1a STRUCTURAL INVARIANT: in-plane run keeps (p,r,β,q_x,q_z) at the FP floor" begin
        _,_,_,_,st = run6(θ0=0.0, γ0=0.0, δp=0.05, δy=0.0, n=6000)
        @test st.mp < 1e-13 && st.mr < 1e-13 && st.mβ < 1e-13
        @test st.mqx < 1e-13 && st.mqz < 1e-13
    end

    @testset "reduction golden: in-plane 6-DOF ≡ scalar rk4_coupled (TIGHT, gate-0 P1b)" begin
        # gate-0 measured the diff at ~3e-12 m over 2 s at dt=1e-3 — the quaternion-RK4 and
        # scalar-θ-RK4 are structurally near-identical for pure pitch. Pin well below meter-scale.
        p6,_,_,_,_ = run6(θ0=0.02, γ0=0.02, δp=0.05, δy=0.0, n=2000)
        ps,_       = run_scalar(θ0=0.02, γ0=0.02, δp=0.05, n=2000)
        @test norm3(p6 - ps) < 1e-6
    end

    @testset "steering_command: RESULTANT clamp caps |inc| at α_max (gate-0 P4)" begin
        p = par(); αmax = 0.30; V = 800.0
        q = att_pitch(0.0); v = V*Vec3(1.0,0.0,0.0)
        Q = 0.5*ρ*V^2; amax_aero = Q*S*abs(Cla)*αmax/MASS
        np, ny = body_perp_axes(q, v/V)
        # demand at 45°, resultant magnitude = the single-axis ceiling ⇒ hypot(α,β)=α_max, NOT sat
        a_edge = (amax_aero/sqrt(2))*np + (amax_aero/sqrt(2))*ny
        αc, βc, sat = steering_command(a_edge, v, q, MASS, p; alpha_max=αmax)
        @test isapprox(hypot(αc,βc), αmax; atol=1e-9) && sat == false
        # over-drive 1.5× ⇒ clamped to the SAME resultant α_max (repointed, not more g), sat
        a_over = 1.5*a_edge
        αo, βo, sato = steering_command(a_over, v, q, MASS, p; alpha_max=αmax)
        @test isapprox(hypot(αo,βo), αmax; atol=1e-9) && sato == true
        # pure-pitch demand at the ceiling ⇒ agrees with the scalar alpha_command's α (single-axis)
        a_pitch = amax_aero*np
        αp, βp, _ = steering_command(a_pitch, v, q, MASS, p; alpha_max=αmax)
        αsc, _ = alpha_command(a_pitch, v, MASS, p; alpha_max=αmax)
        @test isapprox(αp, αsc; atol=1e-9) && isapprox(βp, 0.0; atol=1e-9)
    end

    @testset "degenerate paths stay finite (convention 5)" begin
        p = par()
        @test all(isfinite, lift_accel_3d(Vec3(1e-9,0.,0.), att_pitch(0.0), MASS, p))
        @test all(isfinite, stt_moments(att_pitch(0.0), Vec3(1e-9,0.,0.), zero(Vec3), 0.05, 0.0, p; c_roll=50.0))
        s = steering_command(Vec3(100.,0.,0.), Vec3(1e-9,0.,0.), att_pitch(0.0), MASS, p; alpha_max=0.3)
        @test isfinite(s[1]) && isfinite(s[2])
        @test qnormalize(Quat(0.,0.,0.,0.)) == Quat(1.,0.,0.,0.)   # identity fallback
    end

    # ── SLICE 24 — BANK-TO-TURN + roll-lag ────────────────────────────────────────────────────
    # A representative climbing airframe at low ρ (the showcase flight condition — the STT plant
    # works, so a BTT roll lag can visibly cost the intercept). Teeth mirror gate-0 PROBES F/G/B.
    STEER_MODE_LIST = STEERING_MODES

    @testset "bank_angle: wings-level ≡ 0; a roll about v̂ reads that bank (#1 sign trap 6th)" begin
        V0=700.0; el=deg2rad(12.0); v = V0*Vec3(cos(el),0.0,sin(el))
        qlvl = att_pitch(el)                                     # nose along v, body-up = world-up ⟂ v
        @test isapprox(bank_angle(qlvl, v), 0.0; atol=1e-12)     # wings level
        vh = v/norm3(v)
        qroll = qmul(quat_from_axis_angle(vh, π/3), qlvl)        # roll +60° about v̂
        @test isapprox(bank_angle(qroll, v), π/3; atol=1e-9)     # reads the bank, signed
        @test isapprox(bank_angle(qmul(quat_from_axis_angle(vh,-π/3),qlvl), v), -π/3; atol=1e-9)
    end

    @testset "steering_bank_command: NEAREST-REPRESENTATION reversible lift (PROBE F/G)" begin
        p = par(0.3); αmax=0.30; V0=700.0; el=deg2rad(12.0)
        v = V0*Vec3(cos(el),0.0,sin(el)); qlvl = att_pitch(el)
        # in-plane UP demand ⇒ bank 0, α > 0
        φ,α,_ = steering_bank_command(Vec3(0.,0.,300.), v, qlvl, MASS, p; alpha_max=αmax)
        @test isapprox(φ, 0.0; atol=1e-6) && α > 0.0
        # in-plane DOWN demand ⇒ bank 0 (NOT ±π — the fix), α < 0 (reversible lift, no 180° roll)
        φ,α,_ = steering_bank_command(Vec3(0.,0.,-300.), v, qlvl, MASS, p; alpha_max=αmax)
        @test isapprox(φ, 0.0; atol=1e-6) && α < 0.0
        # cross-range +y demand ⇒ |bank| ≈ 90°, α carries the (positive) demand
        φ,α,_ = steering_bank_command(Vec3(0.,300.,0.), v, qlvl, MASS, p; alpha_max=αmax)
        @test isapprox(abs(φ), π/2; atol=1e-6) && α > 0.0
        # COMMITMENT (no chatter at ±90°): already rolled to −90°, a +y demand STAYS near −90°
        vh = v/norm3(v); q90 = qmul(quat_from_axis_angle(vh, -π/2), qlvl)
        φ,_,_ = steering_bank_command(Vec3(0.,300.,0.), v, q90, MASS, p; alpha_max=αmax)
        @test isapprox(φ, -π/2; atol=1e-6)                       # nearest rep = stay, not flip to +90°
        # sat: demand above the ceiling sets sat; below clears it
        Q = 0.5*0.3*V0^2; aero = Q*S*abs(Cla)*αmax/MASS
        @test steering_bank_command(Vec3(0.,2*aero,0.), v, qlvl, MASS, p; alpha_max=αmax)[3] == true
        @test steering_bank_command(Vec3(0.,0.3*aero,0.), v, qlvl, MASS, p; alpha_max=αmax)[3] == false
    end

    @testset "steering_bank_command decomposition ≡ demanded ⟂-v lift when banked (τ→0 recovery)" begin
        # At the commanded bank AND α, the single-plane lift (Q·S/m)·C_Lα·α·n̂_pitch(φ) must reproduce
        # the demanded ⟂-v accel (direction AND magnitude) — the same ⟂-v vector STT makes in two
        # planes. The causation license in kernel form: instant roll ⇒ BTT ≡ STT (gate-0 PROBE B).
        p = par(0.3); αmax=0.30; V0=700.0; el=deg2rad(12.0)
        v = V0*Vec3(cos(el),0.0,sin(el)); qlvl = att_pitch(el); vh=v/norm3(v)
        a_dem = Vec3(0.0, 120.0, 40.0)                           # a below-ceiling out-of-plane demand
        a_perp = a_dem - dot3(a_dem,vh)*vh
        φ,α,sat = steering_bank_command(a_dem, v, qlvl, MASS, p; alpha_max=αmax)
        @test sat == false
        # n̂_pitch at bank φ = û_ref rotated by φ about v̂ (the bank_angle convention, reconstructed)
        uref = Vec3(0.,0.,1.) - dot3(Vec3(0.,0.,1.),vh)*vh; uref = uref/norm3(uref)
        wref = Vec3(vh[2]*uref[3]-vh[3]*uref[2], vh[3]*uref[1]-vh[1]*uref[3], vh[1]*uref[2]-vh[2]*uref[1])
        np = cos(φ)*uref + sin(φ)*wref
        Q = 0.5*0.3*V0^2
        a_made = (Q*S/MASS)*Cla*α*np                             # single-plane pitch lift at (φ, α)
        @test isapprox(a_made, a_perp; atol=1e-6)                # BTT reproduces the STT ⟂-v vector
    end

    @testset "btt_roll_moment: ζ=1 bank autopilot — sign + exact form" begin
        Ix=2.0; τ=0.8; ωn=1/τ
        @test btt_roll_moment(0.0, 0.5, 0.0, Ix, τ) > 0.0        # +Δφ error ⇒ roll toward command
        @test btt_roll_moment(0.5, 0.5, 0.0, Ix, τ) == 0.0       # no error, no rate ⇒ no moment
        @test btt_roll_moment(0.0, 0.0, 2.0, Ix, τ) < 0.0        # rolling with no error ⇒ damps
        @test isapprox(btt_roll_moment(0.1, 0.4, 0.7, Ix, τ),
                       Ix*(ωn^2*(0.4-0.1) - 2*ωn*0.7); atol=1e-12)
    end

    @testset "btt_moments ≡ stt_moments pitch/yaw (duplicate-not-share); roll swapped" begin
        p = par(); q = att_pitch(0.05); v = 800.0*Vec3(1.,0.,0.); ω = Vec3(0.3,0.2,0.1)
        Ms = stt_moments(q, v, ω, 0.05, 0.02, p; c_roll=50.0)
        Mb = btt_moments(q, v, ω, 0.05, 0.02, 0.0, p; I_xx=Idiag[1], τ_roll=0.8)
        @test isapprox(Mb[2], Ms[2]; atol=1e-12) && isapprox(Mb[3], Ms[3]; atol=1e-12)  # pitch/yaw identical
        @test Mb[1] != Ms[1]                                     # roll: autopilot ≠ damper
        @test isapprox(Mb[1], btt_roll_moment(bank_angle(q,v), 0.0, ω[1], Idiag[1], 0.8); atol=1e-12)
    end

    # A local CLOSED-LOOP STT/BTT driver (guidance → steering law → δ/φ_cmd → moments → integrate) —
    # the gate-3 verifier's unit shadow. Static aero-free target; returns (cpa, maxy, p_pk, bank_pk, β_pk).
    function run_cl(; plant, τ_roll=1.0, tpos, rho=0.3, tmax=12.0, dt=1e-3, αmax=0.30)
        # SHOWCASE airframe (the overdamped params of scenarios/slice24 — Cmq=−150, not the sea-level
        # slender-missile `par()`, whose light damping oscillates the closed loop). Idiag_s = (I_xx=2,
        # I_yy=I_zz=20). This reproduces the gate-0 numbers (STT hits, slow BTT misses).
        Cla_s=20.0; p = AirframeParams(π*0.1^2, 0.2, 20.0, -1.0, 3.0, -150.0, rho, Cla_s)
        Idiag_s=Vec3(2.0, 20.0, 20.0); c_roll=50.0
        mass=MASS; kα=1.0; kq=0.3; δmax=0.5; a_max=3000.0
        pos=Vec3(0.,0.,3000.); V0=700.0; el=deg2rad(12.0); vel=V0*Vec3(cos(el),0.,sin(el))
        q=att_pitch(el); ω=zero(Vec3); δp=0.0; δy=0.0; φcmd=0.0
        min_r=Inf; maxy=0.0; p_pk=0.0; bank_pk=0.0; β_pk=0.0
        for _ in 1:round(Int,tmax/dt)
            f=(P,Vv,Q,W)->begin
                a = total_accel(Vv;rho=rho,cd_area=0.0,mass=mass)+lift_accel_3d(Vv,Q,mass,p;c_yaw=Cla_s)
                M = plant===:stt ? stt_moments(Q,Vv,W,δp,δy,p;c_roll=c_roll) :
                                   btt_moments(Q,Vv,W,δp,δy,φcmd,p;I_xx=Idiag_s[1],τ_roll=τ_roll)
                (Vv, a, attitude_kinematics(Q,W), body_rate_deriv(W,M,Idiag_s))
            end
            pos,vel,q,ω = rk4_6dof(f,pos,vel,q,ω,dt)
            a_cmd = clamp_accel(pn_accel(pos,vel,tpos,zero(Vec3);N=4.0), a_max)
            αa,βa = body_incidence(q,vel)
            if plant===:stt
                αc,βc,_ = steering_command(a_cmd,vel,q,mass,p;alpha_max=αmax,c_yaw=Cla)
                δp,_ = alpha_autopilot_delta(αc,αa,pitch_rate_phys(ω),p;k_alpha=kα,k_q=kq,delta_max=δmax)
                δy,_ = alpha_autopilot_delta(βc,βa,yaw_rate_phys(ω),p;k_alpha=kα,k_q=kq,delta_max=δmax)
            else
                φcmd,αc,_ = steering_bank_command(a_cmd,vel,q,mass,p;alpha_max=αmax)
                δp,_ = alpha_autopilot_delta(αc,αa,pitch_rate_phys(ω),p;k_alpha=kα,k_q=kq,delta_max=δmax)
                δy,_ = alpha_autopilot_delta(0.0,βa,yaw_rate_phys(ω),p;k_alpha=kα,k_q=kq,delta_max=δmax)
            end
            r=norm3(tpos-pos); min_r=min(min_r,r); maxy=max(maxy,abs(pos[2]))
            p_pk=max(p_pk,abs(ω[1])); bank_pk=max(bank_pk,abs(bank_angle(q,vel))); β_pk=max(β_pk,abs(βa))
        end
        return (cpa=min_r, maxy=maxy, p_pk=p_pk, bank_pk=bank_pk, β_pk=β_pk)
    end

    @testset "in-plane ⇒ NO roll (PROBE F); out-of-plane ⇒ ROLLS (the complement, advisor)" begin
        inp = run_cl(plant=:btt, τ_roll=0.8, tpos=Vec3(6000.,0.,4200.))
        @test inp.p_pk < 1e-12 && inp.maxy < 1e-9 && inp.bank_pk < 1e-12   # a law that never rolls passes THIS...
        oop = run_cl(plant=:btt, τ_roll=0.8, tpos=Vec3(6000.,2000.,4200.))
        @test oop.p_pk > 0.1 && oop.maxy > 500.0 && oop.bank_pk > deg2rad(60)  # ...so pin that it DOES roll
    end

    @testset "τ_roll→0 recovers STT; slow τ_roll MISSES (the A/B in miniature, PROBE B/H)" begin
        tp = Vec3(6000.,2000.,4200.)
        stt  = run_cl(plant=:stt, tpos=tp)
        fast = run_cl(plant=:btt, τ_roll=0.01, tpos=tp)
        slow = run_cl(plant=:btt, τ_roll=1.0,  tpos=tp)
        @test stt.cpa < 5.0                                     # STT hits
        @test fast.cpa < 20.0                                   # instant roll ≈ STT (causation license)
        @test slow.cpa > 50.0                                   # slow roll MISSES (the roll lag bites)
        @test slow.cpa > 10*fast.cpa                            # decisive separation
        @test slow.β_pk < 0.15 && stt.β_pk > 0.20               # BTT β regulated→0 vs STT β COMMANDED
    end
end
