# geolocation.jl — the DF/geolocation subsystems that light PHASE 4 of the tick
# contract (HANDOFF §3, §10 item 5, slice 5 gate 2).
#
# Slices 1–3 used only observe!/integrate!; slice 4 lit build_env! (phase 2). This
# file lights `decide!` (phase 4) for the first time — the natural milestone after
# slice 4 lit phase 2. Two coupled subsystems, communicating ONLY through `w.env`
# (the §3 mechanism), now across the **observe!→decide! seam**:
#
#   • DFSensor  — phase-3 `observe!`: reads the (single) emitter's truth pos, computes
#                 the true bearing, draws ONE noisy bearing (one randn/look), and appends
#                 a `BearingRecord` to `w.env[:bearings]` + publishes `<id>.bearing_deg`.
#   • Geolocator — phase-4 `decide!`: reads ALL of `env[:bearings]`, runs the position
#                 fix (per the `:estimator` fidelity), the linearized covariance/ellipse,
#                 and the GDOP, then publishes the fix/ellipse/gdop telemetry.
#
# Phase 3 runs before phase 4 in `tick!`, so a DFSensor's bearing is guaranteed visible
# to the Geolocator the SAME tick (the correctness-by-construction the jammer→radar
# coupling got from phase-2-before-3). `env` is cleared + rebuilt each tick, so a stale
# fix can't leak.
#
# This file is included AFTER radar.jl (it reuses `_range`; the stale "before radar"
# include rationale dissolved once gate 1 moved `ESTIMATOR_MODES` into estimation.jl).
# It has NO back-dep on radar's radar/jammer symbols beyond `_range`. 2-D azimuth-only.

# One DF sensor's bearing measurement — the `env[:bearings]` record. NOT a pre-solved
# fix: the geolocator needs each sensor's position + σ to build the A/H/W rows. Kept
# INTERNAL (like `JamContribution`); the record shape is `theta` (measured, wrapped),
# `pos` (sensor location, Vec3 — z carried but ignored by the planar fix), `sigma`
# (per-sensor 1-σ bearing accuracy, radians). Records are appended in sorted-sensor-id
# order (the DFSensor subs run in the scenario's sorted-id order), so the RNG draw order
# AND the normal-equation sum order are deterministic across runs — the §1 bug class
# made free while there is a single emitter (no re-sort needed; the record has no id).
const BearingRecord = @NamedTuple{theta::Float64, pos::Vec3, sigma::Float64}

# A 1-σ floor (rad) applied at the CONSUMER so a σθ slider dragged to 0 (gate 3) can't
# feed infinite weights (1/σ²) into `bearings_fix` and NaN the fix — the "a live config
# can't crash a tick" watch-item. The loader separately rejects an AUTHORED σθ ≤ 0.
const _SIGMA_THETA_FLOOR = 1.0e-9

# A SIGNED finite clamp for a coordinate readout (fix_x/fix_y may be negative): a singular
# geometry can blow the 2×2 solve to ±Inf/NaN → JSON poison, so map non-finite to
# FINITE_CEIL and clamp the magnitude. The non-negative readouts (err_m/gdop/ell_a/ell_b)
# reuse geometry.jl's `_finite`; this is its signed sibling, same FINITE_CEIL ceiling.
_finite_coord(x::Real) = isfinite(x) ? clamp(float(x), -FINITE_CEIL, FINITE_CEIL) : FINITE_CEIL

# The single emitter nearest `from` (sorted-id tie-break), mirroring radar.jl's
# `_nearest_target` rule. `nothing` if there is no emitter (a sensor-only scene) — the
# callers then skip, so neither subsystem can throw on a malformed/partial world.
function _nearest_emitter(w::World, from::Vec3)
    best = nothing; bestR = Inf
    for eid in sort!(Symbol[id for (id, e) in w.entities if e.kind === :emitter])
        R = _range(w.entities[eid].pos, from)
        if R < bestR
            bestR = R; best = w.entities[eid]
        end
    end
    return best
end

# --- DFSensor: a phase-3 bearing producer ---------------------------------------

"""
    DFSensor(id)

The DF sensor `id` as a phase-3 `observe!` subsystem. Each tick it bearings the nearest
`:emitter` (single-emitter scope, sorted-id tie-break): the true planar azimuth
[`bearing`](@ref)`(sensor, emitter)` plus one Gaussian draw `N(0, σθ)` (the sensor's
`comp[:sigma_theta_rad]`), wrapped to (−π, π]. It appends a [`BearingRecord`](@ref) to
`w.env[:bearings]` (the §3 coupling — the Geolocator reads it back in phase 4) and
publishes `<id>.bearing_deg`.

**Exactly one `randn`/look**, independent of any fidelity rung — so (like slices 2 and
4, unlike slice 3) there is NO draw-topology hazard: the `:estimator` rung selects only
the Geolocator's post-processing, never a draw. **2-D azimuth-only** (HANDOFF §1): the
sensor/emitter z is carried but ignored for the bearing.
"""
struct DFSensor <: Subsystem
    id::Symbol
end

function observe!(s::DFSensor, w::World)
    sensor  = w.entities[s.id]
    emitter = _nearest_emitter(w, sensor.pos)
    emitter === nothing && return nothing            # no emitter → nothing to bear (guard)
    σ       = max(Float64(sensor.comp[:sigma_theta_rad]), _SIGMA_THETA_FLOOR)
    θ_true  = bearing(sensor.pos, emitter.pos)
    θ_hat   = wrap_angle(θ_true + σ * randn(w.rng))  # the ONE draw of a look
    bearings = get!(() -> BearingRecord[], w.env, :bearings)
    push!(bearings, (theta = θ_hat, pos = sensor.pos, sigma = σ))
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    tel["$(s.id).bearing_deg"] = rad2deg(θ_hat)
    return nothing
end

# --- Geolocator: a phase-4 fusion node ------------------------------------------

"""
    Geolocator(id; nsigma = 1.0)

The C2 / fusion node `id` as a phase-4 `decide!` subsystem — the FIRST subsystem to use
phase 4 of the tick contract. It reads every [`BearingRecord`](@ref) in `w.env[:bearings]`
and computes:

  • the position fix + linearized covariance via [`bearings_fix`](@ref), dispatching on
    the `:estimator` fidelity (`get(w.fidelity, :estimator, :pseudolinear)` — the rung
    selects only post-processing, draw-free);
  • the `nsigma`-σ error ellipse from that covariance ([`error_ellipse`](@ref) — `C`
    carries σθ, so the ellipse axes scale with the σθ slider);
  • the GDOP from the emitter's TRUTH geometry ([`gdop`](@ref) at unit σ) — NOT the noisy
    fix, so GDOP is a pure-geometry readout, σθ-invariant and jitter-free (advisor #2: the
    ellipse carries σθ, GDOP is geometry only);
  • `err_m = ‖fix − emitter_truth‖`, the accuracy/bias readout (the lesson as a number).

Publishes `<id>.fix_x/.fix_y/.err_m/.gdop/.ell_a/.ell_b/.ell_deg`. All readouts are
clamped finite ([`_finite`](@ref)/`_finite_coord`, ceiling [`FINITE_CEIL`](@ref)) so a
singular geometry (collinear sensors / emitter on the baseline / σθ→0) ships a huge-but-
finite value, never Inf/NaN — and never throws the tick (the "a live config can't crash a
tick" watch-item). **2-D azimuth-only.** Needs ≥ 2 bearings to cross; below that it
publishes nothing (the loader guarantees ≥ 2 sensors, so this is a safety guard).
"""
struct Geolocator <: Subsystem
    id::Symbol
    nsigma::Float64
end
Geolocator(id::Symbol; nsigma::Real = 1.0) = Geolocator(id, Float64(nsigma))

function decide!(g::Geolocator, w::World)
    bearings = get(w.env, :bearings, nothing)
    (bearings === nothing || length(bearings) < 2) && return nothing   # need ≥2 LOPs to cross

    thetas    = [b.theta for b in bearings]
    positions = [b.pos   for b in bearings]
    sigmas    = [b.sigma for b in bearings]

    estimator = get(w.fidelity, :estimator, :pseudolinear)
    fix, cov  = bearings_fix(thetas, positions, sigmas; estimator = estimator)

    # GDOP + err_m off the emitter's TRUTH geometry: GDOP must be σθ-invariant and
    # fix-free (advisor #2), so its H rows are the unit-σ AOA Jacobian [−sinθ/R̂, cosθ/R̂]
    # about the TRUE emitter, not the noisy fix (which would jitter GDOP every tick and
    # move it when the σθ slider re-rolls the noise). The ellipse, by contrast, comes from
    # `cov` (measured bearings + σθ) — that split is the whole "GDOP geometry, ellipse σθ"
    # lesson. A jammer-free, single-emitter world: the station's nearest emitter IS it.
    station = w.entities[g.id]
    emitter = _nearest_emitter(w, station.pos)
    gd  = FINITE_CEIL
    err = FINITE_CEIL
    if emitter !== nothing
        ex = emitter.pos[1]; ey = emitter.pos[2]
        H  = Vector{SVector{2,Float64}}(undef, length(bearings))
        @inbounds for i in eachindex(bearings)
            dx = ex - bearings[i].pos[1]; dy = ey - bearings[i].pos[2]
            R2 = max(dx * dx + dy * dy, 1e-12)
            H[i] = SVector(-dy / R2, dx / R2)         # [−sinθ/R̂, cosθ/R̂] at unit σ
        end
        gd  = gdop(H)
        err = hypot(fix[1] - ex, fix[2] - ey)
    end

    a, b, ang = error_ellipse(cov; nsigma = g.nsigma)

    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(g.id)
    tel["$sid.fix_x"]  = _finite_coord(fix[1])
    tel["$sid.fix_y"]  = _finite_coord(fix[2])
    tel["$sid.err_m"]  = _finite(err)
    tel["$sid.gdop"]   = _finite(gd)
    tel["$sid.ell_a"]  = _finite(a)            # major semi-axis (m), nsigma·√λ₁
    tel["$sid.ell_b"]  = _finite(b)            # minor semi-axis (m), nsigma·√λ₂
    tel["$sid.ell_deg"] = rad2deg(ang)         # ellipse orientation (deg), NOT radians
    return nothing
end
