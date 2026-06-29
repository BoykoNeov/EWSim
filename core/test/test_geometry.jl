# test_geometry.jl — the shared geometry / DOP primitives vs their closed forms
# (HANDOFF §9, slice 5 gate 1).
#
# Like two_ray (slice 2) these are DETERMINISTIC, so every check is an exact closed
# form with an EXPLICIT atol (never rtol-`≈0`, which passes trivially). The §1 sign
# trifecta (bearing quadrants + residual wrap) is pinned first; then eig/ellipse vs a
# hand-diagonalized matrix; then the GDOP lessons — orthogonal-crossing is the minimum,
# a degenerate geometry stays huge-but-FINITE (the singular guard), the ellipse
# elongates ALONG the LOS (advisor #3), far sensors weigh less (1/R²), and — the
# advisor-#2 pin — GDOP is geometry-only (σθ-INVARIANT) while the ellipse axes scale
# LINEARLY with σθ.

@testset "geometry / DOP primitives" begin

    # --- independent recompute helpers (NOT estimation.jl — keep the geometry test
    #     self-contained): the unit-σ Jacobian rows [−sinθ/R, cosθ/R] and the
    #     σ-weighted covariance C = (Σ (1/σ²) Hᵢ Hᵢᵀ)⁻¹ for a sensor geometry. ---
    jac_rows(sensors, p) = [let dx = p[1]-s[1], dy = p[2]-s[2], R2 = dx^2+dy^2
                                SVector(-dy/R2, dx/R2)
                            end for s in sensors]
    function cov_at(sensors, p, σ)
        m11 = 0.0; m12 = 0.0; m22 = 0.0
        for h in jac_rows(sensors, p)
            w = 1/σ^2
            m11 += w*h[1]*h[1]; m12 += w*h[1]*h[2]; m22 += w*h[2]*h[2]
        end
        det = m11*m22 - m12^2
        SMatrix{2,2,Float64}(m22/det, -m12/det, -m12/det, m11/det)
    end

    @testset "bearing signs in four quadrants + wrap round-trip (the §1 trifecta)" begin
        o = Vec3(0,0,0)
        @test bearing(o, Vec3( 1, 0, 0)) ≈  0.0  atol=1e-12
        @test bearing(o, Vec3( 0, 1, 0)) ≈  π/2  atol=1e-12
        @test bearing(o, Vec3(-1, 0, 0)) ≈  π    atol=1e-12
        @test bearing(o, Vec3( 0,-1, 0)) ≈ -π/2  atol=1e-12
        @test bearing(o, Vec3( 1, 1, 0)) ≈  π/4  atol=1e-12
        # z is ignored — planar bearing (2-D azimuth-only, named approximation)
        @test bearing(Vec3(0,0,5), Vec3(1,0,999)) ≈ 0.0 atol=1e-12
        # wrap → [−π,π], invariant under ±2π, idempotent on a small residual
        @test wrap_angle(0.3)        ≈ 0.3 atol=1e-12
        @test wrap_angle(0.3 + 2π)   ≈ 0.3 atol=1e-12
        @test wrap_angle(0.3 - 2π)   ≈ 0.3 atol=1e-12
        @test abs(wrap_angle(3π))    ≈ π   atol=1e-12
        # a residual that LOOKS like ~2π must wrap to the small angle, not yank the fix
        @test wrap_angle((π - 0.01) - (-π + 0.01)) ≈ -0.02 atol=1e-12
    end

    @testset "eig2x2 vs hand-diagonalized matrix + ell_deg wrap at ±90°" begin
        # axis-aligned
        λ1, λ2, ang = eig2x2(@SMatrix [4.0 0.0; 0.0 1.0])
        @test λ1 ≈ 4.0 atol=1e-12
        @test λ2 ≈ 1.0 atol=1e-12
        @test ang ≈ 0.0 atol=1e-12
        # rotated: build C = R(φ) diag(9,1) R(φ)ᵀ at φ=30° and recover (λ, φ)
        φ = deg2rad(30.0); c = cos(φ); s = sin(φ); l1 = 9.0; l2 = 1.0
        a  = c^2*l1 + s^2*l2
        d  = c*s*(l1 - l2)
        cc = s^2*l1 + c^2*l2
        e1, e2, eang = eig2x2(SMatrix{2,2,Float64}(a, d, d, cc))
        @test e1 ≈ l1 atol=1e-9
        @test e2 ≈ l2 atol=1e-9
        @test eang ≈ φ atol=1e-9
        # major axis along y → principal angle hits the ±90° boundary
        _, _, eangy = eig2x2(@SMatrix [1.0 0.0; 0.0 4.0])
        @test abs(eangy) ≈ π/2 atol=1e-12
    end

    @testset "error_ellipse axes = nsigma·√λ" begin
        C = @SMatrix [4.0 0.0; 0.0 1.0]
        a1, b1, _ = error_ellipse(C; nsigma = 1.0)
        @test (a1, b1) == (2.0, 1.0)
        a3, b3, _ = error_ellipse(C; nsigma = 3.0)
        @test (a3, b3) == (6.0, 3.0)
    end

    @testset "GDOP monotone (orthogonal crossing is the minimum)" begin
        # emitter at origin; two sensors at EQUAL range D, varying crossing angle —
        # isolates the angle (the 1/R weighting is identical for both).
        D = 5000.0
        sens(α) = Vec3(D*cos(α), D*sin(α), 0.0)
        emit = SVector(0.0, 0.0)
        g_ortho   = gdop(jac_rows([sens(0.0), sens(π/2)],         emit))   # 90° crossing
        g_shallow = gdop(jac_rows([sens(0.0), sens(deg2rad(10))], emit))   # 10° crossing
        @test g_ortho < g_shallow
        # a WIDER baseline (crossing nearer 90°) lowers gdop
        narrow = gdop(jac_rows([Vec3(-1000,0,0), Vec3(1000,0,0)], SVector(0.0, 5000.0)))
        wide   = gdop(jac_rows([Vec3(-4000,0,0), Vec3(4000,0,0)], SVector(0.0, 5000.0)))
        @test wide < narrow
    end

    @testset "degenerate geometry → huge but FINITE (the singular guard, never Inf/NaN)" begin
        # exactly parallel rows (collinear LOS) → HᵀH singular → clamps to the ceiling
        @test gdop([SVector(1.0, 0.0), SVector(2.0, 0.0)]) == FINITE_CEIL
        # near-collinear stays finite NATURALLY (huge, below the ceiling)
        gn = gdop([SVector(1.0, 0.0), SVector(1.0, 1e-7)])
        @test isfinite(gn) && gn > 1e3 && gn < FINITE_CEIL
        # a blown-up covariance → ellipse axes clamp, angle stays finite
        a, b, ang = error_ellipse(@SMatrix [1e30 0.0; 0.0 1e30])
        @test a == FINITE_CEIL && b == FINITE_CEIL && isfinite(ang)
    end

    @testset "bad geometry: ellipse elongates ALONG the LOS (advisor #3)" begin
        # far emitter, short cross-baseline → range (x) poorly determined, y well —
        # so the major axis points down-range (≈ x, the LOS), not across.
        far     = SVector(50000.0, 0.0)
        sensors = [Vec3(0, 500, 0), Vec3(0, -500, 0)]
        λ1, λ2, ang = eig2x2(cov_at(sensors, far, deg2rad(1.0)))
        @test λ1 > 50*λ2                       # very elongated
        @test abs(ang) < deg2rad(5)            # major axis ≈ along x (the LOS / down-range)
    end

    @testset "far sensors weigh less (1/R² Fisher weighting widens the ellipse, advisor #3)" begin
        # emitter at origin; S1 fixed; move S2 radially OUT (same 90° crossing angle,
        # only its range grows) → its 1/R² info drops → the ellipse area grows.
        emit = SVector(0.0, 0.0)
        S1   = Vec3(5000, 0, 0)
        near = cov_at([S1, Vec3(0, 5000, 0)],  emit, deg2rad(1.0))
        far  = cov_at([S1, Vec3(0, 50000, 0)], emit, deg2rad(1.0))
        area(C) = sqrt(max(C[1,1]*C[2,2] - C[1,2]^2, 0.0))
        @test area(far) > area(near)
    end

    @testset "GDOP is geometry-only (σθ-INVARIANT); ellipse scales with σθ (advisor #2)" begin
        emit    = SVector(5000.0, 0.0)
        sensors = [Vec3(0,0,0), Vec3(0,5000,0), Vec3(10000,4000,0)]
        H = jac_rows(sensors, emit)
        g = gdop(H)
        @test isfinite(g) && g > 0
        # gdop never takes σ → recomputing it is the SAME number (the invariance pin)
        @test gdop(jac_rows(sensors, emit)) == g
        σ1 = deg2rad(0.5); σ2 = deg2rad(1.0)              # σ2 = 2·σ1
        a1, b1, _ = error_ellipse(cov_at(sensors, emit, σ1))
        a2, b2, _ = error_ellipse(cov_at(sensors, emit, σ2))
        @test a2/a1 ≈ 2.0 atol=1e-9                        # axes scale LINEARLY with σθ
        @test b2/b1 ≈ 2.0 atol=1e-9
        # the exact decomposition σ_pos = gdop·σθ: √trace(C) = √(a²+b²) = gdop·σ
        @test hypot(a1, b1) ≈ g*σ1 rtol=1e-9
        @test hypot(a2, b2) ≈ g*σ2 rtol=1e-9
    end
end
