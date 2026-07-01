# test_gnss.jl — GPS pseudorange positioning / DOP / RAIM vs closed forms + MC bands
# (HANDOFF §9 REUSE milestone, slice 7 gate 1).
#
# Like two_ray / geometry (slices 2, 5) the deterministic checks are exact closed forms
# with EXPLICIT atol (never rtol-`≈0`); the stochastic error terms use their OWN Xoshiro
# (the slice-1 batch precedent). The load-bearing anchors:
#   • the §9 REUSE pin — the generalized N-dim Cholesky (`_solve_normal`, which GPS calls
#     at N=4) reproduces the DF 2×2 cofactor (`_solve2x2`) at N=2: the generalization is
#     faithful, not a fork;
#   • DOP is pure GEOMETRY (σ-invariant) — position error scales with σ_range, the DOP
#     does NOT (the slice-5 σθ-trap on the GPS surface); VDOP > HDOP on the SHIPPED
#     upper-hemisphere layout (a placement property, verified — NOT asserted universal);
#   • RAIM detects a fault, IDs the RIGHT satellite by largest normalized residual (the
#     real single-fault step, not tuned to pass), excludes it and RECOVERS truth, and
#     `:off` NEVER flags; over-determination is required (n=4 → dof 0 → blind).
# Slices 1–6 stay byte-identical (gnss.jl touches no radar/detection path).

# Independent 4×4 inverse (Gauss-Jordan with partial pivoting) — a DIFFERENT algorithm
# than the Cholesky `_solve_normal` under test, so comparing `dop`'s Q against it is a
# genuine recompute (the slice-2 "oracle, not a hand-copy of the same formula" rule).
function _inv4(A)
    n = size(A, 1)
    M = [A[i, j] for i in 1:n, j in 1:n]
    I = [Float64(i == j) for i in 1:n, j in 1:n]
    for c in 1:n
        piv = c
        for r in c+1:n
            abs(M[r, c]) > abs(M[piv, c]) && (piv = r)
        end
        if piv != c
            M[c, :], M[piv, :] = M[piv, :], M[c, :]
            I[c, :], I[piv, :] = I[piv, :], I[c, :]
        end
        d = M[c, c]
        M[c, :] ./= d; I[c, :] ./= d
        for r in 1:n
            r == c && continue
            f = M[r, c]
            M[r, :] .-= f .* M[c, :]
            I[r, :] .-= f .* I[c, :]
        end
    end
    return I
end

_n3(v) = sqrt(v[1]^2 + v[2]^2 + v[3]^2)

# A far point source at (az, el) from the origin — the flat-local fictional satellite
# (named approximation): ~20 000 km "up", NO ECEF/orbit. The gate-1 probe layout.
_mksat(az, el; r = 20_000_000.0) =
    (a = deg2rad(az); e = deg2rad(el);
     Vec3(r * cos(e) * cos(a), r * cos(e) * sin(a), r * sin(e)))

@testset "gnss: GPS positioning / DOP / RAIM (§9 reuse)" begin
    # The PROBED spread constellation (6 sats, VDOP>HDOP confirmed) + a receiver near
    # the origin with a 30 m (≈100 ns) clock bias.
    SATS = [_mksat(0, 70), _mksat(60, 35), _mksat(120, 40),
            _mksat(180, 30), _mksat(240, 45), _mksat(300, 55)]
    RX   = Vec3(1000.0, -500.0, 0.0)
    CB   = 30.0    # metres (c·b)

    clean_rho(idx, cb = CB) = [pseudorange(SATS[j], RX, cb) for j in idx]

    @testset "noise-free fix == truth exactly (exactly-4 solve AND over-determined)" begin
        for idx in (1:4, 1:6)
            pos, cb, Q, sing = position_fix(SATS[idx], clean_rho(idx))
            @test !sing
            @test _n3(pos - RX) < 1e-5
            @test abs(cb - CB) < 1e-5
        end
    end

    @testset "§9 reuse pin: N=2 _solve_normal reproduces _solve2x2 (faithful, not a fork)" begin
        # A well-conditioned 2×2 normal system: the generalized Cholesky (the N=4 GPS
        # solver, here at N=2) matches the DF 2×2 cofactor to floating-point.
        M = [5.0 1.5; 1.5 3.0]; g = [2.0, -1.0]
        x, Minv, sing = EWSim._solve_normal(M, g)
        p, cov = EWSim._solve2x2(M[1,1], M[1,2], M[2,2], g[1], g[2])
        @test !sing
        @test x[1] ≈ p[1] atol=1e-12
        @test x[2] ≈ p[2] atol=1e-12
        @test Minv[1,1] ≈ cov[1,1] atol=1e-12
        @test Minv[1,2] ≈ cov[1,2] atol=1e-12
        @test Minv[2,2] ≈ cov[2,2] atol=1e-12
    end

    @testset "DOP decomposition vs independent recompute + VDOP>HDOP (probed layout)" begin
        pos, cb, Q, sing = position_fix(SATS, clean_rho(1:6))
        # Independent Q = (HᵀH)⁻¹ via Gauss-Jordan on the unit-LOS rows at the fix.
        HtH = zeros(4, 4)
        for j in 1:6
            d = SATS[j] - pos; r = _n3(d); u = d / r
            h = (-u[1], -u[2], -u[3], 1.0)
            for a in 1:4, c in 1:4
                HtH[a, c] += h[a] * h[c]
            end
        end
        Qind = _inv4(HtH)
        for a in 1:4, c in 1:4
            @test Q[a, c] ≈ Qind[a, c] atol=1e-6
        end
        g, p, h, v, t = dop_components(Q; singular = sing)
        # Decomposition identities (wiring pins — algebraic tautologies of the split).
        @test g^2 ≈ p^2 + t^2 rtol=1e-9
        @test p^2 ≈ h^2 + v^2 rtol=1e-9
        # VDOP > HDOP on THIS upper-hemisphere layout — a placement property (named), NOT
        # a universal (the one-sided vertical-info bonus lesson).
        @test v > h
        @test all(x -> isfinite(x) && x > 0, (g, p, h, v, t))
    end

    @testset "DOP is geometry-only (σ-invariant); pos error = PDOP·σ_range (the slice-5 trap)" begin
        # DOP takes ONLY the geometry — the pseudorange σ enters at the readout, never in Q.
        _, _, Q, _ = position_fix(SATS, clean_rho(1:6))
        _, pdop, _, _, _ = dop_components(Q)
        # MC scatter (own Xoshiro): RMS position error scales LINEARLY with σ_range while
        # the DOP is a single fixed number — σ-invariance as an error-budget check.
        function rms(sig, seed, N = 4000)
            rng = Xoshiro(seed); s = 0.0
            for _ in 1:N
                rho = [pseudorange(SATS[j], RX, CB; noise = sig * randn(rng)) for j in 1:6]
                p, _, _, _ = position_fix(SATS, rho)
                s += _n3(p - RX)^2
            end
            return sqrt(s / N)
        end
        r1 = rms(1.0, 777); r2 = rms(2.0, 777)
        @test r2 / r1 ≈ 2.0 atol=0.05             # scatter ∝ σ (probe 2.0000)
        @test r1 / 1.0 ≈ pdop rtol=0.05           # RMS_pos ≈ PDOP·σ (probe 4.665 vs 4.683)
    end

    @testset "error budget: deterministic iono shifts the fix (known sign, no draw)" begin
        # iono is a POSITIVE (delayed) range bias, elevation-scaled. All sats delayed →
        # the common-mode is absorbed by the receiver CLOCK (cb rises), the residual
        # elevation-dependence leaks into position (pos error grows from ≈0). No draw.
        idx = 1:6
        p0, cb0, _, _ = position_fix(SATS, clean_rho(idx))
        els = [sat_az_el(SATS[j], RX)[2] for j in idx]
        rho_i = [pseudorange(SATS[j], RX, CB; iono = iono_delay(els[j], 5.0)) for j in idx]
        pi, cbi, _, _ = position_fix(SATS, rho_i)
        @test _n3(p0 - RX) < 1e-4                 # clean fix is on truth
        @test cbi > cb0                            # KNOWN sign: clock absorbs the +delay
        @test cbi - cb0 > 10.0                     # a real, large bias (probe ≈ 14.4 m)
        @test _n3(pi - RX) > 5.0                   # iono contributes position error (probe ≈ 9.9 m)
        # a per-SATELLITE clock error (one SV) biases the fix by a known amount.
        rho_c = [pseudorange(SATS[j], RX, CB; clock_err = (j == 2 ? 10.0 : 0.0)) for j in idx]
        pc, _, _, _ = position_fix(SATS, rho_c)
        @test _n3(pc - RX) > 10.0                  # probe ≈ 27 m
    end

    @testset "error terms: tropo + multipath contracts (the remaining two of five)" begin
        # tropo — same deterministic obliquity shape as iono (z/sin(el)), NOT
        # Saastamoinen: positive, exact obliquity where uncapped, larger at low elevation.
        z = 2.4
        @test tropo_delay(deg2rad(30.0), z) ≈ z / sin(deg2rad(30.0)) atol=1e-9   # exact obliquity
        @test tropo_delay(deg2rad(30.0), z) > 0
        @test tropo_delay(deg2rad(10.0), z) > tropo_delay(deg2rad(60.0), z)      # worse low (sign)
        # mp_scale — the multipath elevation weight, worse near the horizon (ground bounce).
        @test mp_scale(deg2rad(10.0)) > mp_scale(deg2rad(60.0))
        @test mp_scale(deg2rad(90.0)) ≈ 1.0 atol=1e-9                            # unity at zenith

        # multipath VARIANCE (own Xoshiro, the fifth error term): mp = mp_scale(el)·σ_mp·randn
        # inflates the fix scatter, LINEARLY in σ_mp (each mp term scales with σ_mp).
        els = [sat_az_el(SATS[j], RX)[2] for j in 1:6]
        function rms_mp(σ_mp, seed, N = 4000)
            rng = Xoshiro(seed); s = 0.0
            for _ in 1:N
                rho = [pseudorange(SATS[j], RX, CB; mp = mp_scale(els[j]) * σ_mp * randn(rng)) for j in 1:6]
                p, _, _, _ = position_fix(SATS, rho)
                s += _n3(p - RX)^2
            end
            return sqrt(s / N)
        end
        m1 = rms_mp(1.0, 313); m2 = rms_mp(2.0, 313)
        @test m1 > 0                               # multipath draws inflate the scatter
        @test m2 / m1 ≈ 2.0 atol=0.05              # linear in σ_mp (the drawn-term contract)
    end

    @testset "RAIM: detect / fault-ID / exclude / off (the real single-fault algorithm)" begin
        σ = 3.0; thr = 5.0
        rho = clean_rho(1:6)
        # clean → :detect does NOT flag; the statistic is ≈ 0 (self-consistent).
        rc = raim_solve(SATS, rho, σ; mode = :detect, threshold = thr)
        @test !rc.flag && rc.stat < thr
        @test rc.stat < 1e-6                       # noise-free → residuals ≈ 0

        # inject a fault on satellite 3 (a spoof / SV failure bias).
        rf = copy(rho); rf[3] += 60.0
        # :off NEVER flags (the naïve baseline that trusts the spoof).
        ro = raim_solve(SATS, rf, σ; mode = :off, threshold = thr)
        @test !ro.flag && count(ro.used) == 6 && ro.fault_sat == 0
        # :detect raises the flag; the statistic is well above threshold (probe ≈ 8.2).
        rd = raim_solve(SATS, rf, σ; mode = :detect, threshold = thr)
        @test rd.flag && rd.stat > thr
        # fault ID picks the RIGHT satellite by largest normalized residual (the real step).
        @test raim_suspect(SATS, rf, rd.pos, rd.cb, σ) == 3
        # :exclude drops sat 3, RECOVERS truth (snap-back), n_used = 5, flag clears.
        re = raim_solve(SATS, rf, σ; mode = :exclude, threshold = thr)
        @test re.fault_sat == 3 && !re.used[3] && count(re.used) == 5
        @test _n3(re.pos - RX) < 1e-4              # fix snaps back onto truth
        @test !re.flag
        # :exclude with NO fault leaves every satellite in (nothing to exclude).
        re2 = raim_solve(SATS, rho, σ; mode = :exclude, threshold = thr)
        @test count(re2.used) == 6 && re2.fault_sat == 0 && !re2.flag
        # bad mode rejected.
        @test_throws ErrorException raim_solve(SATS, rho, σ; mode = :nope)
    end

    @testset "RAIM needs over-determination: n=4 (dof 0) is blind to a fault" begin
        rf4 = [pseudorange(SATS[j], RX, CB; fault_bias = (j == 2 ? 100.0 : 0.0)) for j in 1:4]
        r = raim_solve(SATS[1:4], rf4, 3.0; mode = :detect, threshold = 5.0)
        @test r.stat == 0.0 && !r.flag            # no redundancy → the fault is invisible
    end

    @testset "singular geometry → FINITE_CEIL exactly, no throw" begin
        CEIL5 = (FINITE_CEIL, FINITE_CEIL, FINITE_CEIL, FINITE_CEIL, FINITE_CEIL)
        # fewer than 4 satellites → rank-deficient 4×4 → ceiling exactly.
        for k in 1:3
            pos, cb, Q, sing = position_fix(SATS[1:k], clean_rho(1:k))
            @test sing
            @test dop_components(Q; singular = sing) == CEIL5
        end
        # coplanar 4 satellites (all azimuth 0 → the y-direction is unobservable).
        cop = [_mksat(0, 20), _mksat(0, 40), _mksat(0, 60), _mksat(0, 80)]
        rhoc = [pseudorange(cop[j], RX, CB) for j in 1:4]
        _, _, Qc, sc = position_fix(cop, rhoc)
        @test sc
        @test dop_components(Qc; singular = sc) == CEIL5
        # empty satellite list → degenerate, finite, no throw.
        pos, cb, Q, sing = position_fix(Vec3[], Float64[])
        @test sing
        @test all(isfinite, dop_components(Q; singular = sing))
    end

    @testset "units: clock bias ns round-trip (the §1 metres-vs-seconds trifecta)" begin
        # Author a clock bias in ns → c·b metres → recover via the fix → back to ns.
        cb_ns = 123.0
        cb_m  = cb_ns * 1e-9 * EWSim.C_LIGHT
        rho = clean_rho(1:6, cb_m)
        pos, cb, Q, sing = position_fix(SATS, rho)
        @test cb / EWSim.C_LIGHT * 1e9 ≈ cb_ns atol=1e-6    # metres → ns round-trips
        @test _n3(pos - RX) < 1e-5
        @test abs(cb - cb_m) < 1e-5                          # metres recovered
    end
end
