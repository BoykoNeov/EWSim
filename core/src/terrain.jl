# terrain.jl — authored analytic heightfield + LOS occlusion (slice 18 gate 1).
#
# The FIRST terrain in the project. The heightfield is a base plane plus a sum of
# GAUSSIAN HILLS — a deliberately ANALYTIC choice: closed-form (every test anchor
# exact), smooth (no mesh-resolution artifacts in the physics), trivially
# YAML-authorable, and ZERO RNG (nothing to desync — simpler even than a class-4a
# rung needs; seeded fractal terrain is a named deferral in docs/plans/slice18.md).
#
#     h(x, y) = h0 + Σᵢ aᵢ · exp(−((x−cxᵢ)² + (y−cyᵢ)²) / (2σᵢ²))
#
# Occlusion is a SAMPLED-PROFILE line-of-sight test: walk the straight p1→p2
# segment at a fixed step and compare ray height to terrain height. Flat-earth
# WITHIN the terrain patch — the same named approximation class as two_ray's flat
# reflecting plane (HANDOFF §1); the 4/3-Earth horizon stays a separate `:two_ray`
# concern. The shadow is HARD (binary mask, exactly the existing below-horizon
# policy shape); knife-edge diffraction is the named fidelity rung ABOVE this.
#
# Pure, no `w.rng`, dependency-free (no LinearAlgebra — the §9 house style).
# Everything is SI Float64, inertial frame, z-up.

"""
    TerrainParams(; h0=0.0, a=Float64[], cx=Float64[], cy=Float64[],
                    sigma=Float64[], los_step_m=25.0)

Authored-input record for an analytic Gaussian-hill heightfield (the
`RadarParams`/`AirframeParams` precedent). Hills are PARALLEL VECTORS
(`a[i]` peak height above the base plane, `(cx[i], cy[i])` center, `sigma[i]`
the Gaussian radius); `h0` is the base-plane height; `los_step_m` the LOS
sampling step. Validation (σ > 0, equal lengths, step > 0) happens at scenario
LOAD (convention 5), not here — this is the pure-math record.
"""
struct TerrainParams
    h0::Float64
    a::Vector{Float64}
    cx::Vector{Float64}
    cy::Vector{Float64}
    sigma::Vector{Float64}
    los_step_m::Float64
end
TerrainParams(; h0::Real = 0.0, a = Float64[], cx = Float64[], cy = Float64[],
                sigma = Float64[], los_step_m::Real = 25.0) =
    TerrainParams(Float64(h0), Float64.(collect(a)), Float64.(collect(cx)),
                  Float64.(collect(cy)), Float64.(collect(sigma)), Float64(los_step_m))

"""
    terrain_height(t::TerrainParams, x, y) -> Float64   (metres)

The heightfield closed form: `h0 + Σᵢ aᵢ·exp(−((x−cxᵢ)² + (y−cyᵢ)²)/(2σᵢ²))`.
Finite by construction for finite inputs (a Gaussian never overflows downward —
convention 6 needs no clamp here).
"""
function terrain_height(t::TerrainParams, x::Real, y::Real)
    h = t.h0
    @inbounds for i in eachindex(t.a)
        dx = x - t.cx[i]; dy = y - t.cy[i]
        h += t.a[i] * exp(-(dx * dx + dy * dy) / (2 * t.sigma[i] * t.sigma[i]))
    end
    return h
end

"""
    terrain_clearance(t::TerrainParams, p1::Vec3, p2::Vec3) -> Float64   (metres, SIGNED)

Signed minimum line-of-sight clearance `min over the ray of (ray_z − h(x, y))`,
sampled at `t.los_step_m` along the straight p1→p2 segment, **endpoints
EXCLUDED** — a mast standing on the ground (or a target skimming it) must not
self-block; only the terrain BETWEEN the two ends can occlude. Positive = the
ray clears by that many metres at its worst point; negative = buried that deep.

The sampler walks a FIXED fraction grid `s = i/(n+1), i = 1..n` (n from the
segment length ÷ step, ≥ 1 so even a short hop is probed once) — symmetric in
(p1, p2) by construction: swapping the endpoints visits the same set of points,
so `terrain_clearance(t, p1, p2) == terrain_clearance(t, p2, p1)` bit-exactly
(pinned; an asymmetric walk would make "who shoots first" physical).

Degenerate p1 == p2 (zero-length LOS): returns the clearance AT the point —
finite, never a throw (a live tick can't crash — convention 5).
"""
function terrain_clearance(t::TerrainParams, p1::Vec3, p2::Vec3)
    dx = p2[1] - p1[1]; dy = p2[2] - p1[2]; dz = p2[3] - p1[3]
    len = sqrt(dx * dx + dy * dy + dz * dz)
    n = max(1, ceil(Int, len / t.los_step_m) - 1)   # interior samples (endpoints excluded)
    worst = Inf
    @inbounds for i in 1:n
        s = i / (n + 1)
        c = (p1[3] + s * dz) - terrain_height(t, p1[1] + s * dx, p1[2] + s * dy)
        c < worst && (worst = c)
    end
    return worst
end

"""
    terrain_los_clear(t::TerrainParams, p1::Vec3, p2::Vec3) -> Bool

`terrain_clearance(t, p1, p2) > 0` — true when the straight line of sight
clears the terrain everywhere between the endpoints. The hard-shadow verdict
the `:terrain` propagation rung gates `(snr, visible)` on (gate 2).
"""
terrain_los_clear(t::TerrainParams, p1::Vec3, p2::Vec3) =
    terrain_clearance(t, p1, p2) > 0.0

"""
    terrain_grid(t::TerrainParams, xmin, xmax, ymin, ymax, n) -> Vector{Float64}

The n×n height sample a scenario ships ONCE in the `scenario` handshake (the
`range_axis_m` handshake-once precedent) so the client can DRAW the terrain
without recomputing any physics (HANDOFF §1). **ROW-MAJOR over y then x**:
element `(iy−1)·n + ix` is the height at

    x = xmin + (ix−1)·(xmax−xmin)/(n−1),   y = ymin + (iy−1)·(ymax−ymin)/(n−1)

(ix, iy ∈ 1..n; the four grid corners land exactly on the extent corners). The
layout is pinned against an ASYMMETRIC terrain in the tests — a transpose slip
here silently mirrors every hill the client renders.
"""
function terrain_grid(t::TerrainParams, xmin::Real, xmax::Real,
                      ymin::Real, ymax::Real, n::Integer)
    g = Vector{Float64}(undef, n * n)
    @inbounds for iy in 1:n, ix in 1:n
        x = xmin + (ix - 1) * (xmax - xmin) / (n - 1)
        y = ymin + (iy - 1) * (ymax - ymin) / (n - 1)
        g[(iy - 1) * n + ix] = terrain_height(t, x, y)
    end
    return g
end
