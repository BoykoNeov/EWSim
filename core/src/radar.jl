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

function observe!(r::RadarSensor, w::World)
    radar = w.entities[r.id]
    # propagation fidelity is named, not hidden: free_space is the only rung wired in
    # slice 1; two_ray dispatches here later behind the same knob (HANDOFF §10).
    prop = get(w.fidelity, :propagation, :free_space)
    prop == :free_space || error("RadarSensor: propagation fidelity :$prop not implemented (slice 1: :free_space)")

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
    any_detect = false
    for tid in target_ids
        tgt = w.entities[tid]
        R   = _range(tgt.pos, radar.pos)
        snr = snr_freespace(rp, tgt.comp[:rcs_m2], R)
        pd  = pd_analytic(snr, pfa; swerling = sw)
        if snr > best_snr
            best_snr = snr
            best_pd  = pd
        end
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
    # in comp so it survives ticks between scans).
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(r.id)
    tel["$sid.snr_db"]   = lin2db(best_snr)
    tel["$sid.pd"]       = best_pd
    tel["$sid.detected"] = get(radar.comp, :detected, false)
    return nothing
end
