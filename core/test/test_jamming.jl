# test_jamming.jl — noise jamming + the burn-through crossover vs their closed forms
# (HANDOFF §8 validation; slice 4 step 1).
#
# Jamming physics is *deterministic* (a noise-floor modulation, like two_ray — not the
# detector's analytic-vs-MC bands), so every check here is an exact closed form. Each test
# moves one knob and pins one fact: the one-way-vs-two-way asymmetry that IS burn-through,
# the self-screen (R²) and standoff (R_t⁴) J/S laws, barrage dilution, the two-level
# antenna pattern, the burn-through range, and the benign F/L + (corrected) B_r behavior.

@testset "jamming / burn-through" begin
    # λ = 0.03 m exactly (same convention as test_propagation), F = L = 0 dB so the base
    # geometry has nothing to argue about; the F/L test below dials them up.
    rp = EWSim.RadarParams(
        1000.0,                  # pt_w
        30.0,                    # gain_db
        EWSim.C_LIGHT / 0.03,    # freq_hz   → λ = 0.03 m
        1.0e6,                   # bandwidth_hz  (B_r)
        0.0, 0.0,                # noise_fig_db, losses_db
    )
    σ     = 1.0                  # target RCS, m²
    pj_w  = 100.0                # jammer transmit power, W
    gj_db = 10.0                 # jammer antenna gain toward the radar, dB
    bj_hz = 1.0e6                # jammer bandwidth = B_r → spot (overlap 1) by default

    @testset "burn-through asymmetry: JNR ∝ R_j⁻² (−6 dB) vs signal R⁻⁴ (−12 dB)" begin
        # The whole lesson in one place: over the SAME range-doubling the one-way jammer
        # loses exactly half the dB the two-way echo does, so the signal catches up.
        R1, R2 = 10_000.0, 20_000.0                              # one octave
        jnr1 = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R1)
        jnr2 = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R2)
        s1   = EWSim.snr_freespace(rp, σ, R1)
        s2   = EWSim.snr_freespace(rp, σ, R2)
        @test EWSim.lin2db(jnr1 / jnr2) ≈ 20 * log10(2) atol=1e-9   # 6.0206 dB  (R_j⁻²)
        @test EWSim.lin2db(s1   / s2)   ≈ 40 * log10(2) atol=1e-9   # 12.0412 dB (R⁻⁴)
        @test EWSim.lin2db(jnr1 / jnr2) ≈ EWSim.lin2db(s1 / s2) / 2 atol=1e-9
    end

    @testset "self-screening: J/S ∝ R² (+6 dB per range-doubling)" begin
        # Jammer rides the target (R_j = R, mainlobe Gr = G). J/S = (K_j/K_s)·R² — halve the
        # range, J/S drops 6 dB, the signal burns through.
        js(R) = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R) / EWSim.snr_freespace(rp, σ, R)
        @test js(20_000.0) / js(10_000.0) ≈ 4.0 rtol=1e-12          # ∝ R²
        @test EWSim.lin2db(js(20_000.0) / js(10_000.0)) ≈ 20 * log10(2) atol=1e-9
    end

    @testset "standoff: J/S ∝ R_t⁴ (+12 dB per target-range-doubling — the steeper crossover)" begin
        # Jammer holds station (R_j fixed → J constant); only the target range R_t moves.
        # S ∝ R_t⁻⁴ → J/S ∝ R_t⁴. (The sidelobe Gr is a constant prefactor that cancels in
        # this ratio — its magnitude is pinned by the antenna test below.)
        jnr = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, 50_000.0)   # standoff, constant
        js(Rt) = jnr / EWSim.snr_freespace(rp, σ, Rt)
        @test js(20_000.0) / js(10_000.0) ≈ 16.0 rtol=1e-12         # ∝ R_t⁴
        @test EWSim.lin2db(js(20_000.0) / js(10_000.0)) ≈ 40 * log10(2) atol=1e-9
    end

    @testset "barrage dilution: overlap = min(1, B_r/B_j)" begin
        R = 20_000.0
        jnr_spot    = EWSim.jam_noise_ratio(rp, pj_w, gj_db, 1.0e6, R)  # B_j = B_r   → overlap 1
        jnr_barrage = EWSim.jam_noise_ratio(rp, pj_w, gj_db, 1.0e7, R)  # B_j = 10·B_r→ overlap 0.1
        @test jnr_barrage / jnr_spot ≈ 0.1 rtol=1e-12
        @test EWSim.lin2db(jnr_barrage / jnr_spot) ≈ -10.0 atol=1e-9    # −10 dB dilution
        # A jammer NARROWER than the passband still counts as overlap 1 (all of it lands in
        # band) — overlap saturates at 1, never exceeds it.
        jnr_narrow = EWSim.jam_noise_ratio(rp, pj_w, gj_db, 1.0e5, R)   # B_j = B_r/10
        @test jnr_narrow ≈ jnr_spot rtol=1e-12
    end

    @testset "two-level antenna pattern: mainlobe vs sidelobe floor" begin
        bw = deg2rad(3.0)        # 3° beamwidth
        sl = 30.0                # 30 dB sidelobes
        g  = rp.gain_db
        # in-beam → full mainlobe gain
        @test EWSim.antenna_gain(rp, 0.0;        beamwidth_rad=bw, sidelobe_db=sl) == g
        @test EWSim.antenna_gain(rp, bw/2 - 1e-9; beamwidth_rad=bw, sidelobe_db=sl) == g
        # boundary is INCLUSIVE: θ = beamwidth/2 is still mainlobe (the exact, deliberate step)
        @test EWSim.antenna_gain(rp, bw/2;       beamwidth_rad=bw, sidelobe_db=sl) == g
        # outside → flat sidelobe floor g − sidelobe_db
        @test EWSim.antenna_gain(rp, bw/2 + 1e-9; beamwidth_rad=bw, sidelobe_db=sl) == g - sl
        @test EWSim.antenna_gain(rp, π/2;        beamwidth_rad=bw, sidelobe_db=sl) == g - sl
        # sign-symmetric (the model reads |θ|)
        @test EWSim.antenna_gain(rp, -π/2;       beamwidth_rad=bw, sidelobe_db=sl) == g - sl
        # the standoff JNR (sidelobe Gr) is exactly `sidelobe_db` weaker than the self-screen
        # mainlobe JNR — physically why standoff jamming is weaker.
        R = 30_000.0
        jnr_main = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R; gr_db = g)
        jnr_side = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R; gr_db = g - sl)
        @test EWSim.lin2db(jnr_side / jnr_main) ≈ -sl atol=1e-9
    end

    @testset "burnthrough_range: J/S = js_margin at R_bt (self-screen closed form)" begin
        js(R) = EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R) / EWSim.snr_freespace(rp, σ, R)
        R_bt = EWSim.burnthrough_range(rp, σ, pj_w, gj_db, bj_hz)
        @test R_bt > 0
        # at R_bt, J/S = 1 exactly (the algebra inverts) — pin with atol, the ≈1 rtol trap.
        @test js(R_bt) ≈ 1.0 atol=1e-9
        # inside → signal dominates (J/S < 1, burn-through); outside → jammed (J/S > 1).
        @test js(0.5 * R_bt) < 1.0
        @test js(2.0 * R_bt) > 1.0
        # a tighter J/S margin (< 1) needs a CLOSER range → smaller R_bt, scaling as √margin.
        R_bt_10 = EWSim.burnthrough_range(rp, σ, pj_w, gj_db, bj_hz; js_margin = 0.1)
        @test R_bt_10 < R_bt
        @test R_bt_10 / R_bt ≈ sqrt(0.1) rtol=1e-12
        @test js(R_bt_10) ≈ 0.1 atol=1e-9
    end

    @testset "F and L cancel in J/S (benign common-mode approximation)" begin
        R = 25_000.0
        js(rpx) = EWSim.jam_noise_ratio(rpx, pj_w, gj_db, bj_hz, R) / EWSim.snr_freespace(rpx, σ, R)
        rp_lossy = EWSim.RadarParams(rp.pt_w, rp.gain_db, rp.freq_hz, rp.bandwidth_hz, 7.0, 5.0)
        @test js(rp_lossy) ≈ js(rp) rtol=1e-12                      # J/S invariant to F, L
        # they DO enter both link budgets — they just cancel in the ratio (sanity).
        @test EWSim.snr_freespace(rp_lossy, σ, R) < EWSim.snr_freespace(rp, σ, R)
        @test EWSim.jam_noise_ratio(rp_lossy, pj_w, gj_db, bj_hz, R) <
              EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R)
    end

    @testset "radar-bandwidth behavior (the CORRECT B_r law, not the inverted assertion)" begin
        # Guards against the landmine "B_r cancels in J/S" — true ONLY for a spot jammer.
        R = 25_000.0
        mkrp(br) = EWSim.RadarParams(rp.pt_w, rp.gain_db, rp.freq_hz, br, rp.noise_fig_db, rp.losses_db)
        rp1, rp2 = mkrp(1.0e6), mkrp(2.0e6)
        js(rpx, bj) = EWSim.jam_noise_ratio(rpx, pj_w, gj_db, bj, R) / EWSim.snr_freespace(rpx, σ, R)

        # SPOT (B_j ≤ B_r ⇒ overlap = 1): J/S is B_r-INVARIANT (thermal B_r cancels, no overlap term).
        bj_spot = 5.0e5
        @test js(rp1, bj_spot) ≈ js(rp2, bj_spot) rtol=1e-12

        # BARRAGE — B_j held FIXED across the two B_r values (a barrage jammer's bandwidth is a
        # property of the jammer, NOT tied to B_r; this is the exact distinction that inverts the law).
        bj_bar = 1.0e7
        #  • JNR is B_r-INVARIANT: J (∝ overlap = B_r/B_j) and N (∝ B_r) scale together.
        @test EWSim.jam_noise_ratio(rp1, pj_w, gj_db, bj_bar, R) ≈
              EWSim.jam_noise_ratio(rp2, pj_w, gj_db, bj_bar, R) rtol=1e-12
        #  • J/S ∝ B_r: S ∝ 1/B_r (thermal), JNR flat ⇒ J/S doubles when B_r doubles.
        @test js(rp2, bj_bar) / js(rp1, bj_bar) ≈ 2.0 rtol=1e-12
    end

    @testset "guards: only Inf/NaN-producing inputs throw" begin
        @test_throws DomainError EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, 0.0)
        @test_throws DomainError EWSim.jam_noise_ratio(rp, pj_w, gj_db, bj_hz, -1.0)
        @test_throws DomainError EWSim.jam_noise_ratio(rp, pj_w, gj_db, 0.0, 20_000.0)   # B_j = 0
        @test_throws DomainError EWSim.burnthrough_range(rp, σ, pj_w, gj_db, bj_hz; js_margin = 0.0)
        @test_throws DomainError EWSim.burnthrough_range(rp, σ, pj_w, gj_db, bj_hz; js_margin = -1.0)
    end
end
