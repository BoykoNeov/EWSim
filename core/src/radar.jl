# radar.jl — the concrete slice-1 subsystems that wire rf.jl + detection.jl into
# the tick contract (HANDOFF §3, §8, slice-1 step 5).
#
# Two subsystems, both stateless config — all mutable state lives in the world
# (entity `comp` bags / `w.env` / `w.rng`), which is what keeps replay bit-identical
# and lets the universal `set_param` channel (HANDOFF §5) move a knob live:
#
#   • ConstantVelocity — phase-1 mover: pos += vel·dt. No RNG, no forces.
#   • RadarSensor      — phase-3 sensor: range → SNR → Pd every tick (continuous
#                        readout), with a discrete detection draw + event gated to a
#                        revisit cadence (the per-scan blip).
#
# Cross-subsystem coupling is read-only through `w.entities`/`w.env`; subsystems
# never call each other (HANDOFF §3).

# --- ConstantVelocity: the passive constant-velocity mover ----------------------

"""
    ConstantVelocity(id)

Advances entity `id` by `pos += vel·dt` each physics step. Constant-velocity,
no process noise — the deterministic fly-by of slice 1. A static entity (radar)
simply carries `vel = 0` and stays put, so the loader can hand every entity a
mover without special-casing.
"""
struct ConstantVelocity <: Subsystem
    id::Symbol
end

function integrate!(cv::ConstantVelocity, w::World, dt::Float64)
    e = w.entities[cv.id]
    e.pos = e.pos + e.vel * dt
    return nothing
end

# --- RadarSensor: range → SNR → Pd → detection ----------------------------------

"""
    RadarSensor(id; revisit_s = 0.0)

The monostatic radar `id` as a tick-contract sensor. Its transmit/receive chain
and detector config live in the entity's `comp` bag (so a slider writing `comp`
takes effect live): `:pt_w :gain_db :freq_hz :bandwidth_hz :noise_fig_db
:losses_db :pfa :swerling`. Per tick `observe!`:

  • computes SNR (free-space radar eq) and analytic Pd against every `:target`,
    publishing the strongest target's `snr_db`/`pd`/`detected` to `w.env[:telemetry]`
    under `"<id>.snr_db"` etc. — a continuous readout, fresh every frame;
  • on look ticks (gated to `revisit_s`) draws one physical detection per target
    (`detect_once`) from `w.rng`, persists the result in `comp[:detected]`, and
    pushes a one-shot `:detection` event per target that crossed threshold.

`revisit_s = 0` looks every tick. SNR/Pd are continuous; only the draw + blip are
discrete, so the readout never blanks between scans (the env blackboard is rebuilt
each tick).
"""
struct RadarSensor <: Subsystem
    id::Symbol
    revisit_s::Float64
end
RadarSensor(id::Symbol; revisit_s::Real = 0.0) = RadarSensor(id, Float64(revisit_s))

_radar_params(c::AbstractDict) = RadarParams(c[:pt_w], c[:gain_db], c[:freq_hz],
                                             c[:bandwidth_hz], c[:noise_fig_db], c[:losses_db])

# Euclidean range without pulling in LinearAlgebra (StaticArrays subtraction + sum).
_range(a::Vec3, b::Vec3) = sqrt(sum(abs2, a - b))

# Horizontal (ground) range — drops the vertical (z) component. Distinct from the 3-D
# slant range: two_ray runs the link budget on slant but the multipath phase and the
# 4/3-Earth horizon on ground (rf.jl `two_ray_phase` / `horizon_range`).
_ground_range(a::Vec3, b::Vec3) = hypot(a[1] - b[1], a[2] - b[2])

# The propagation-fidelity rungs the radar dispatch knows. SINGLE source of truth for
# both the `_target_snr` dispatch (below) and the server's `set_fidelity` validation
# (server.jl) — they must not drift, or the wire would accept a value that crashes
# `tick!` inside `observe!` (HANDOFF §10, slice2 step 2).
const PROPAGATION_MODES = (:free_space, :two_ray)

# A perfect null (F⁴=0, even above the horizon), an antenna on the reflecting plane
# (h→0), or a below-horizon mask all drive SNR→0, and `lin2db(0) = -Inf` would poison the
# JSON state frame (the slice-2 watch-item, same class as the slice-1 %g bug). Floor the
# dB readout so the wire never carries Inf/NaN; the floor sits far below any real
# free-space reading, so it is invisible except on a genuine null/mask.
const _SNR_DB_FLOOR = -120.0
_snr_db_wire(snr_lin::Real) = snr_lin > 0 ? max(lin2db(snr_lin), _SNR_DB_FLOOR) : _SNR_DB_FLOOR

"""
    _target_snr(prop, rp, radar, tgt) -> (snr_lin, visible)

Single-target SNR under the active `propagation` fidelity, plus a horizon-visibility
flag. `:free_space` is infinite-LOS phenomenology (no ground, always visible).
`:two_ray` adds the flat-earth multipath (`snr_two_ray`, decomposed slant/ground) and
the 4/3-Earth horizon: a target whose ground range exceeds `horizon_range` has no line
of sight and is masked to SNR 0 (NOT -Inf — see [`_snr_db_wire`](@ref)). rf.jl stays
pure phenomenology; the below-horizon POLICY and the degenerate guards live here, per
HANDOFF §1/§10 and the slice-2 plan.
"""
function _target_snr(prop::Symbol, rp::RadarParams, radar::Entity, tgt::Entity)
    R   = _range(tgt.pos, radar.pos)
    rcs = tgt.comp[:rcs_m2]
    if prop === :free_space
        return snr_freespace(rp, rcs, R), true
    elseif prop === :two_ray
        # Heights above the reflecting plane (z=0); clamp ≥0 so a fly-by dipping below the
        # plane can't feed a negative into `horizon_range`'s sqrt and crash the live tick.
        h_r = max(radar.pos[3], 0.0)
        h_t = max(tgt.pos[3], 0.0)
        ground = _ground_range(tgt.pos, radar.pos)
        # Directly overhead (ground→0): flat-earth small-grazing two_ray is invalid (Δφ→∞)
        # and `snr_two_ray` guards ground>0. Treat the rare exact-overhead instant as
        # visible free space (no grazing bounce at zenith) rather than crash.
        ground > 0 || return snr_freespace(rp, rcs, R), true
        ground ≤ horizon_range(h_r, h_t) || return 0.0, false        # below the radar horizon → masked
        return snr_two_ray(rp, rcs, R; h_r = h_r, h_t = h_t, ground_m = ground), true
    else
        error("RadarSensor: propagation fidelity :$prop not implemented " *
              "($(join(PROPAGATION_MODES, " | ")))")
    end
end

function observe!(r::RadarSensor, w::World)
    radar = w.entities[r.id]
    # Propagation fidelity is named, not hidden: dispatch on the :propagation knob
    # (default :free_space). `_target_snr` owns the per-rung physics + the below-horizon
    # policy, and raises the unknown-rung error (HANDOFF §10, slice2 step 2).
    prop = get(w.fidelity, :propagation, :free_space)

    rp  = _radar_params(radar.comp)
    pfa = Float64(radar.comp[:pfa])
    sw  = Int(radar.comp[:swerling])
    th  = detection_threshold(pfa)

    # Sorted target ids → deterministic RNG draw order across targets (HANDOFF §1).
    target_ids = sort!(Symbol[id for (id, e) in w.entities if e.kind === :target])
    isempty(target_ids) && return nothing

    is_look = w.t + 1e-12 ≥ get(radar.comp, :next_look_t, 0.0)

    best_snr = -Inf
    best_pd  = 0.0
    best_visible = true
    any_detect = false
    for tid in target_ids
        tgt = w.entities[tid]
        snr, vis = _target_snr(prop, rp, radar, tgt)
        pd  = pd_analytic(snr, pfa; swerling = sw)
        if snr > best_snr
            best_snr = snr
            best_pd  = pd
            best_visible = vis
        end
        # The detection draw is UNCONDITIONAL on every look — `_sample_z` issues the same
        # randn() calls regardless of SNR, so the RNG stream advances identically across
        # fidelities (a masked/null target still "costs" its draws). Gating this on
        # snr>0 / visible would skip draws and desync seeded replay (a determinism
        # violation visible only in a trace diff). A masked target (snr=0) simply detects
        # with prob ≈ pfa.
        if is_look && detect_once(snr, th, w.rng; swerling = sw)
            any_detect = true
            # t is stamped by state_frame at emit (events are sent on the frame they
            # occur, HANDOFF §5) — keeps event time == frame time.
            push!(w.events, Dict{Symbol,Any}(:kind => :detection, :by => r.id, :of => tid))
        end
    end

    if is_look
        radar.comp[:detected]  = any_detect
        radar.comp[:next_look_t] = get(radar.comp, :next_look_t, 0.0) + r.revisit_s
    end

    # Continuous readout every tick; `detected` is the last look's verdict (persisted
    # in comp so it survives ticks between scans). `snr_db` is floored so a two_ray null
    # / below-horizon mask (SNR→0) never ships -Inf; `visible` carries the horizon verdict
    # (always true under free_space — infinite LOS).
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(r.id)
    tel["$sid.snr_db"]   = _snr_db_wire(best_snr)
    tel["$sid.pd"]       = best_pd
    tel["$sid.detected"] = get(radar.comp, :detected, false)
    tel["$sid.visible"]  = best_visible
    return nothing
end
