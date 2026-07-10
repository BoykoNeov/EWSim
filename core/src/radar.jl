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
:losses_db :pfa :swerling :n_pulses`. (`:swerling`/`:n_pulses` set the detector
statistic — not live sliders, they change the per-look draw count.) Per tick
`observe!`:

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

# The CFAR-fidelity rungs the radar dispatch knows. REFERENCES detection.jl's
# `CFAR_VARIANTS` (the primitives' source of truth) rather than re-listing — the slice-2
# `PROPAGATION_MODES` drift lesson: one list feeds both the `observe!` dispatch and the
# server's `set_fidelity` validation, so the wire can't accept a rung `cfar_scan` rejects.
const CFAR_MODES = CFAR_VARIANTS

# The EP (electronic-protection) rungs the radar applies against jamming (slice-4 gate 3).
# A NAMED, CONDITIONED modifier per rung (`_ep_factor`), never a flat fudge — `:none` is the
# baseline, `:freq_agility` helps only vs a SPOT jammer, `:sidelobe_blanking` only vs a
# SIDELOBE (standoff) jammer. Single source of truth for the dispatch AND the server table.
const EP_MODES = (:none, :freq_agility, :sidelobe_blanking)

# The fidelity keys `set_fidelity` may toggle LIVE, each mapped to its allowed rungs. The
# single source of truth for server.jl's `set_fidelity` validation — it references the same
# mode tuples the `observe!` dispatch uses, so a value accepted on the wire can never reach
# a tick that throws (the slice-2 lesson, generalised to a per-key table). NB: presence of
# `:cfar` changes the RNG draw topology (point path → profile path), so the server also
# guards against INTRODUCING it mid-run — see `handle_command!` (server.jl). `:ep` carries NO
# such guard (it only scales a deterministic scalar — no draw-count change — so it is
# introduce-safe, the sharp contrast to `:cfar`; slice-4 gate 3). `:estimator` (slice-5 DF;
# rungs `ESTIMATOR_MODES` from estimation.jl, in scope here) is likewise introduce-safe — a
# DFSensor draws exactly one randn/look regardless of rung, so the Geolocator's rung selects
# only deterministic post-processing (no draw-count change; landed in gate 2 — the core
# fidelity plumbing precedes the gate-3 client toggle/scenario).
# `:deinterleaver` (slice-6 EW; rungs `DEINTERLEAVER_MODES` from deinterleave.jl, in scope
# here) is likewise introduce-safe — the ESM receiver's TOA draw is rung-invariant (the whole
# draw lives in phase-3 observe!), so the Deinterleaver's rung selects only phase-4 post-
# processing (no draw-count change; the `:ep`/`:estimator` contract, NOT slice-3's `:cfar` guard).
# The six GPS keys (slice-7; `GPS_TOGGLE`/`RAIM_MODES` from gnss.jl, in scope here) are ALL
# introduce-safe too — the GpsReceiver draws `2·n_sats` unconditionally (phase-3 observe!), so a
# toggle gates a term's CONTRIBUTION and the raim rung selects only phase-4 post-processing (no
# draw-count change). NB the keys `iono/tropo/clock/multipath/noise` are generic words
# NAMESPACED BY CONSUMPTION — only a GpsSolver reads them (the `:estimator`-without-a-Geolocator
# precedent), so a non-GPS scenario toggling one is a harmless no-op.
# `:integrator` (slice-8 missile; rungs `INTEGRATOR_MODES` from dynamics.jl, in scope here) is
# likewise introduce-safe — absent a `:missile` entity nothing reads it, so a set_fidelity on
# any slice-1..7 scenario is a no-op (the `:ep`/`:estimator` contract, NOT slice-3's `:cfar`
# guard). BUT UNLIKE those it is PHYSICS-CHANGING, NOT toggle-bit-identical: there is no RNG in
# slice 8, so "draw-count-invariance" is vacuous, and a rk4↔euler toggle CHANGES the trajectory
# (the slice-2 `propagation` shape). Introduce-safe ≠ toggle-invariant — keep the two separate.
# `:autopilot` (slice-9 guided missile; rungs `AUTOPILOT_MODES` from guidance.jl, in scope here)
# is the SAME shape as `:integrator` — introduce-safe (absent an `Autopilot` subsystem nothing
# reads it) AND physics-changing (a :ideal↔:pid toggle changes the trajectory, no RNG). Do NOT
# copy the slice-5/6/7 toggle-invariance language onto it.
# `:guidance` (slice-10 OUTER law; rungs `GUIDANCE_MODES` from guidance.jl, in scope here) is the
# SAME shape again — introduce-safe (absent a consumer nothing reads it; `decide!` defaults to
# `:pursuit`, the slice-9 law, so introducing the key on any slice-1..9 scenario is byte-identical)
# AND physics-changing (a :pursuit↔:pn toggle CHANGES the trajectory, no RNG). Orthogonal to
# `:autopilot` (outer vs inner loop); slice-10 scenarios pin `:autopilot=:ideal` so the one client
# button toggles one lesson. Referencing GUIDANCE_MODES here (not re-listing) is one-list-no-drift.
# `:seeker` (slice-11 noisy seeker; rungs `SEEKER_MODES` from estimation.jl, in scope here) is a
# GENUINELY NEW fidelity-class COMBO — do NOT copy either prior template: it is DRAW-INVARIANT
# (class 4a, the `:estimator` shape — the Seeker draws ONE `randn` sample every tick on BOTH rungs,
# the filter is pure post-processing, so `set_fidelity` may INTRODUCE it freely, UNLIKE `:cfar`'s
# draw-topology flip) YET TRAJECTORY-CHANGING (the slice-10 shape — a `:raw↔:filtered` toggle selects
# which ω PN consumes, so it MOVES the missile; NOT toggle-bit-identical, NOT a dead knob). It is
# ALSO the FIRST `w.rng` consumer in the missile arc, so the slice-8/9/10 "RNG-is-vacuous" language
# does NOT apply here; byte-identity for slices 1–10 comes from NO Seeker existing (nothing reads the
# key). Orthogonal to `:guidance`/`:autopilot` (slice-11 pins `:guidance=:pn`, `:autopilot=:ideal`).
# `:seeker` gains a THIRD rung `:scan` (slice-13 countermeasures; `SEEKER_MODES` from estimation.jl,
# already appended at gate 1) — but `:scan` is NOT the class-4a shape of `:raw`/`:filtered`: it FLIPS
# the draw topology (1 → 2·N_p·N_bins/tick, the profile floor `_draw_profile!` draws), so it is
# INTRODUCE-REJECTED like `:cfar` (server.jl `set_fidelity`, the mixed-introduce-safety guard) while
# `:raw↔:filtered` stay live. `:discrimination` (slice-13; rungs `DISCRIMINATION_MODES` from
# estimation.jl) is the peak-resolution selector for the `:scan` seeker — DRAW-INVARIANT among its
# rungs (both build the SAME profile / SAME draws, differ only in post-detection peak SELECTION → the
# toggle is draw-count-invariant and introduce-safe once `:scan` is on) YET TRAJECTORY-CHANGING (a
# `:none↔:gated` toggle MOVES the missile — not a dead knob), and INERT unless `seeker=:scan` (no
# profile → no peaks → the key does nothing; the `:raim`-without-GPS coupling). NOT free-standing
# class-4a — it is "draw-invariant within the 4b `:scan` host" (convention 4c, the copy-paste trap).
# `:cooperation` (slice-14 salvo capstone; rungs `COOPERATION_MODES` from guidance.jl, in scope here)
# is class 4c — the `:integrator`/`:autopilot`/`:apn` shape, NOT slice-13's draw-topology 4b. A
# `:solo↔:salvo` toggle CHANGES the trajectory (the faster interceptor stretches its path via the
# impact-time-control feedback) but the scenario is truth-fed PN with NO seeker → NO `w.rng` consumer,
# so "draw-count invariance" is VACUOUS (do NOT copy slice-13's draw language) and there is NO
# draw-topology to flip → `:cooperation` is introduce-SAFE and live-settable: `set_fidelity` needs NO
# new guard (CONTRAST slice-13 `:scan` / slice-3 `:cfar`, which reject introduce). Byte-identity for
# slices 1–13 is by CONSTRUCTION — absent a `SalvoCoordinator` (`:datalink` entity) nothing writes
# `w.env[:salvo_t_d]`, and under `coop === :solo` the `decide!` salvo arm is unreachable. Orthogonal to
# `:guidance`/`:autopilot`/`:seeker` (slice-14 pins `guidance=:pn`, `autopilot=:ideal`, no seeker so the
# ONE button toggles the ONE cooperation lesson). Referencing COOPERATION_MODES (not re-listing) is
# one-list-no-drift.
const LIVE_FIDELITY_MODES = (propagation = PROPAGATION_MODES, cfar = CFAR_MODES,
                             ep = EP_MODES, estimator = ESTIMATOR_MODES,
                             deinterleaver = DEINTERLEAVER_MODES,
                             iono = GPS_TOGGLE, tropo = GPS_TOGGLE, clock = GPS_TOGGLE,
                             multipath = GPS_TOGGLE, noise = GPS_TOGGLE, raim = RAIM_MODES,
                             integrator = INTEGRATOR_MODES, autopilot = AUTOPILOT_MODES,
                             guidance = GUIDANCE_MODES, seeker = SEEKER_MODES,
                             discrimination = DISCRIMINATION_MODES,
                             cooperation = COOPERATION_MODES)

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

# --- Jammer: a build_env! noise-floor source (slice-4 step 2) --------------------
#
# The FIRST subsystem to use phase 2 of the tick contract (build_env!, subsystem.jl): a
# noise jammer doesn't SENSE — it raises the radar's interference floor. It writes its
# per-radar jammer-to-noise contributions into the derived `w.env[:jamming]` blackboard, and
# the radar's `observe!` reads them back (SNR_eff = SNR/(1+ΣJNR)). This is the §3
# cross-subsystem coupling done right: through `env`, never by one subsystem calling another.
# `env` is rebuilt fresh each tick (tick!), so a stale floor can't leak.

# One jammer's contribution to one radar's interference floor — the `env[:jamming]` record.
# NOT a pre-summed scalar: the radar needs the per-contribution structure to apply EP
# CONDITIONALLY (slice-4 gate 3) — `in_beam` (mainlobe vs sidelobe → sidelobe_blanking) and
# `bj_hz` (jammer bandwidth → freq_agility). `build_env!` fills `in_beam`/`gr_db` from the
# two-level `antenna_gain` about the radar's boresight (its nearest target); `jnr` is J/N (linear).
const JamContribution = @NamedTuple{jnr::Float64, in_beam::Bool, bj_hz::Float64}

# Two-level antenna + EP defaults (slice-4 gate 3). The antenna pattern (beamwidth/sidelobe)
# and the EP config (agile band / cancel depth) are RADAR comp keys; these defaults make a
# jammer scene work without them AND — crucially — make `:ep` INTRODUCE-SAFE: a `set_fidelity
# :ep` may land on ANY scenario, so `_ep_factor` must read these via `get(comp, …, default)`
# and can never `KeyError` inside a tick (the slice-2/3 "a live config can't crash a tick").
const _DEFAULT_BEAMWIDTH_RAD = deg2rad(3.0)     # ~3° mainlobe (half-beamwidth 1.5°)
const _DEFAULT_SIDELOBE_DB   = 30.0             # sidelobe floor 30 dB below the mainlobe peak
const _DEFAULT_AGILE_BW_HZ   = 1.0e7            # frequency-agility hop band (10 MHz)
const _DEFAULT_CANCEL_DB     = 30.0             # sidelobe-blanking cancellation depth

# The radar's boresight target (NAMED rule, gate 3): the NEAREST `:target`, ties broken by
# sorted id (ascending iteration + strict `<` keeps the first). `nothing` if no target — the
# caller then treats a jammer as in-mainlobe (conservative), so `build_env!` can't throw on a
# jammer-only scene (the "a live config can't crash a tick" watch-item).
function _nearest_target(w::World, radar::Entity)
    best = nothing; bestR = Inf
    for tid in sort!(Symbol[id for (id, e) in w.entities if e.kind === :target])
        R = _range(w.entities[tid].pos, radar.pos)
        if R < bestR
            bestR = R; best = w.entities[tid]
        end
    end
    return best
end

# Angle (rad, ∈ [0,π]) of point `p` off the radar→target boresight line, for the two-level
# antenna pattern. `acos` of the normalized dot of (target−radar) and (p−radar); the cosine is
# clamped to [-1,1] (float round-off can nudge it past ±1 and NaN the `acos`), and a degenerate
# zero-length vector (the target sitting ON the radar) returns 0 → treated as on-axis.
function _boresight_angle(radar_pos::Vec3, tgt_pos::Vec3, p::Vec3)
    u = tgt_pos - radar_pos
    v = p - radar_pos
    nu = sqrt(sum(abs2, u)); nv = sqrt(sum(abs2, v))
    (nu == 0 || nv == 0) && return 0.0
    return acos(clamp(sum(u .* v) / (nu * nv), -1.0, 1.0))
end

"""
    Jammer(id)

The noise jammer `id` as a `build_env!`-only subsystem. Its emitter config lives in the
entity `comp` bag (`:pt_w :gain_db :bandwidth_hz`), and a `ConstantVelocity` mover (the
loader pairs one with it) lets it close or hold station. Each tick `build_env!` computes a
one-way (beacon) JNR ([`jam_noise_ratio`](@ref), rf.jl) at every radar and appends a
[`JamContribution`](@ref) to `w.env[:jamming][radar_id]`. The radar's RECEIVE gain toward the
jammer is the two-level antenna pattern ([`antenna_gain`](@ref)) about the radar's boresight
(its nearest target): a self-screening jammer rides the mainlobe (`θ≈0`, `Gr=G`, `in_beam`),
a standoff jammer sits in a sidelobe (much smaller `Gr`, `!in_beam`) — the per-contribution
`in_beam`/`bj_hz` is exactly what the radar's EP (`_ep_factor`) conditions on. Multiple jammers'
contributions are additive and order-independent (the §3 build_env! contract — the radar SUMS
them, so append order is irrelevant).
"""
struct Jammer <: Subsystem
    id::Symbol
end

function build_env!(j::Jammer, w::World)
    jammer = w.entities[j.id]
    pj = Float64(jammer.comp[:pt_w])
    gj = Float64(jammer.comp[:gain_db])
    bj = Float64(jammer.comp[:bandwidth_hz])
    for (rid, radar) in w.entities
        radar.kind === :radar || continue
        R_j = _range(jammer.pos, radar.pos)
        # A jammer co-located with the radar (R_j = 0) would divide-by-zero in the one-way link
        # budget; skip that contribution (a degenerate, non-physical placement) so build_env! →
        # tick! can NEVER throw and kill the session (the slice-2/3 "a live config can't crash a
        # tick" watch-item; the gate-4 range slider can drive R_j, so guard at the consumer).
        R_j > 0 || continue
        rp = _radar_params(radar.comp)
        # Gate 3: two-level receive gain. The radar boresights its NEAREST target; the jammer's
        # angle off that line picks the mainlobe Gr (self-screen, θ≈0 → cancels the echo in J/S)
        # vs the sidelobe floor (standoff, off-axis → uncancelled, weaker — what sidelobe-blanking
        # attacks). No target → conservative mainlobe (can't throw on a jammer-only scene). The
        # antenna pattern (beamwidth/sidelobe) is the radar's, read with defaults.
        bw   = Float64(get(radar.comp, :beamwidth_rad, _DEFAULT_BEAMWIDTH_RAD))
        sldb = Float64(get(radar.comp, :sidelobe_db,   _DEFAULT_SIDELOBE_DB))
        tgt  = _nearest_target(w, radar)
        if tgt === nothing
            gr_db = rp.gain_db; in_beam = true
        else
            θ = _boresight_angle(radar.pos, tgt.pos, jammer.pos)
            in_beam = θ ≤ bw / 2                 # same inclusive boundary as antenna_gain's step
            gr_db   = antenna_gain(rp, θ; beamwidth_rad = bw, sidelobe_db = sldb)
        end
        jnr = jam_noise_ratio(rp, pj, gj, bj, R_j; gr_db = gr_db)
        jamming = get!(() -> Dict{Symbol,Vector{JamContribution}}(), w.env, :jamming)
        push!(get!(() -> JamContribution[], jamming, rid), (jnr = jnr, in_beam = in_beam, bj_hz = bj))
    end
    return nothing
end

# EP (electronic protection) factor on ONE jammer's JNR — a NAMED, CONDITIONED modifier, never
# a flat scalar (a flat fudge would "help" against the wrong jammer; advisor). Conditioned on the
# per-contribution structure the jammer baked in: `bj_hz` (freq_agility) and `in_beam`
# (sidelobe_blanking). `:none` → 1.0 EXACTLY (byte-identical to no EP). Reads the radar's EP
# config (agile band, cancel depth) with DEFAULTS so toggling `:ep` onto any scenario can't crash.
function _ep_factor(ep::Symbol, c::JamContribution, comp::AbstractDict)
    ep === :none && return 1.0
    if ep === :freq_agility
        # The radar hops over an agile band; a narrow (SPOT) jammer covers only B_j/B_agile of the
        # hops → big benefit. A BARRAGE jammer (B_j ≥ B_agile) covers them all → min(1,·)=1, a
        # no-op (the conditioning: agility is useless once the jammer spans the whole hop band).
        b_agile = Float64(get(comp, :agile_bw_hz, _DEFAULT_AGILE_BW_HZ))
        return min(1.0, c.bj_hz / b_agile)
    elseif ep === :sidelobe_blanking
        # Attenuates a jammer arriving through a SIDELOBE; a MAINLOBE (self-screen) jammer can't be
        # blanked without blanking the target → no-op (the conditioning). Cancel depth from comp.
        c.in_beam && return 1.0
        return db2lin(-Float64(get(comp, :cancel_db, _DEFAULT_CANCEL_DB)))
    else
        error("RadarSensor: ep fidelity :$ep not implemented ($(join(EP_MODES, " | ")))")
    end
end

# Total jammer-to-noise ratio a radar sees from the phase-2 `env[:jamming]` contributions, after
# the radar's EP. The additive sum (multiple jammers' JNR add at the radar's input) folds in the
# per-contribution `_ep_factor` HERE — this is the single seam where EP plugs in, conditioned on
# each contribution's `in_beam`/`bj_hz`. Called only when `contribs` exists; absent a jammer the
# caller short-circuits to 0.0, so SNR_eff = SNR/(1+0) ≡ SNR (slices 1-3 byte-identical), and with
# `ep = :none` every factor is 1.0 so the sum is bit-identical to the bare gate-2 JNR.
function _radar_jnr(contribs::Vector{JamContribution}, ep::Symbol, comp::AbstractDict)
    total = 0.0
    @inbounds for c in contribs
        total += c.jnr * _ep_factor(ep, c, comp)
    end
    return total
end

"""
    observe!(r::RadarSensor, w)

The radar's per-tick sense phase. Dispatches on the **detector fidelity**: a scenario
carrying a `:cfar` fidelity key builds + draws a range-power PROFILE every look
([`_observe_cfar!`](@ref)); without it, the slice-1/2 per-target POINT detector runs
([`_observe_point!`](@ref)), byte-identical. The two paths draw a DIFFERENT number of
randn per look (`2·N_p·N_cells` vs `2·N_p` per target), which is why `:cfar` cannot be
introduced mid-run (server.jl's `set_fidelity` guard) — the choice is fixed by the
scenario, not toggled live (only the CFAR *rung* toggles, draw-count-invariant).
"""
function observe!(r::RadarSensor, w::World)
    if haskey(w.fidelity, :cfar)
        _observe_cfar!(r, w)
    else
        _observe_point!(r, w)
    end
    return nothing
end

# The slice-1/2 point detector: per-target SNR → analytic Pd readout + one gated
# `detect_once` draw per target. UNCHANGED from slice 2 (moved verbatim under the
# `observe!` dispatch above) — a no-`:cfar` scenario stays byte-identical, which
# `test_determinism` / `test_radar` pin.
function _observe_point!(r::RadarSensor, w::World)
    radar = w.entities[r.id]
    # Propagation fidelity is named, not hidden: dispatch on the :propagation knob
    # (default :free_space). `_target_snr` owns the per-rung physics + the below-horizon
    # policy, and raises the unknown-rung error (HANDOFF §10, slice2 step 2).
    prop = get(w.fidelity, :propagation, :free_space)

    rp  = _radar_params(radar.comp)
    pfa = Float64(radar.comp[:pfa])
    sw  = Int(radar.comp[:swerling])
    np  = Int(get(radar.comp, :n_pulses, 1))    # non-coherent integration depth (slice 3)
    th  = detection_threshold(pfa, np)

    # Jamming (slice 4): a Jammer's `build_env!` (phase 2) may have written this radar's
    # per-jammer JNR contributions into `w.env[:jamming]`; sum them to the elevated noise floor.
    # Absent any jammer the key is missing → `jnr_total = 0` → `SNR_eff = SNR/(1+0)` ≡ `SNR`
    # bit-for-bit, so slices 1-3 stay byte-identical (no draw changes, and the jnr_db/js_db keys
    # are suppressed below — both pinned by tests). `contribs !== nothing` is the jamming flag.
    # EP (slice-4 gate 3) is the radar's countermeasure: the `:ep` fidelity (default `:none`)
    # CONDITIONALLY scales each jammer's JNR in `_radar_jnr` (the seam). Read only when a jammer
    # is present — so a no-jammer frame never consults `:ep` (jnr_total = 0.0, byte-identical), and
    # introducing `:ep` on a jammer-free scenario is a guaranteed no-op (the introduce-safe contract).
    jamming   = get(w.env, :jamming, nothing)
    contribs  = jamming === nothing ? nothing : get(jamming, r.id, nothing)
    jnr_total = contribs === nothing ? 0.0 :
                _radar_jnr(contribs, get(w.fidelity, :ep, :none), radar.comp)

    # Sorted target ids → deterministic RNG draw order across targets (HANDOFF §1).
    target_ids = sort!(Symbol[id for (id, e) in w.entities if e.kind === :target])
    isempty(target_ids) && return nothing

    is_look = w.t + 1e-12 ≥ get(radar.comp, :next_look_t, 0.0)

    best_snr_eff = -Inf      # strongest target's EFFECTIVE (post-jamming) SNR → snr_db + pd
    best_snr_th  = -Inf      # ...its THERMAL S/N → js_db (J/S = JNR / SNR_thermal)
    best_pd  = 0.0
    best_visible = true
    any_detect = false
    for tid in target_ids
        tgt = w.entities[tid]
        snr_th, vis = _target_snr(prop, rp, radar, tgt)
        # Raise the interference floor N → N+J: SNR_eff = (S/N)/(1+JNR). With no jammer
        # (jnr_total = 0.0) this is `snr_th / 1.0 === snr_th`, so the detector sees an identical
        # value and the draw stream is untouched. Jamming changes detection BOOLEANS, never the
        # draw COUNT (detect_once stays unconditional — same randn count regardless of SNR), so
        # jammer-on/off replay in RNG lockstep (the slice-1 invariant; draw-invariance test).
        snr_eff = snr_th / (1 + jnr_total)
        pd  = pd_analytic(snr_eff, pfa; swerling = sw, n_pulses = np)
        if snr_eff > best_snr_eff
            best_snr_eff = snr_eff
            best_snr_th  = snr_th
            best_pd  = pd
            best_visible = vis
        end
        if is_look && detect_once(snr_eff, th, w.rng; swerling = sw, n_pulses = np)
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

    # Continuous readout every tick; `detected` is the last look's verdict (persisted in comp so
    # it survives ticks between scans). `snr_db` now carries SNR_eff (post-jamming; ≡ thermal SNR
    # when unjammed), floored so a two_ray null / below-horizon mask (SNR→0) never ships -Inf;
    # `visible` carries the horizon verdict (always true under free_space — infinite LOS).
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(r.id)
    tel["$sid.snr_db"]   = _snr_db_wire(best_snr_eff)
    tel["$sid.pd"]       = best_pd
    tel["$sid.detected"] = get(radar.comp, :detected, false)
    tel["$sid.visible"]  = best_visible
    # jnr_db / js_db ship ONLY when this radar actually sees a jammer — so a no-jammer frame is
    # unchanged (slices 1-3). js_db is the dB DIFFERENCE jnr_db − snr_th_db: exactly
    # lin2db(JNR/S) when both are above the floor (log identity), and wire-safe (finite,
    # correct-direction) if S→0 (a masked/no-target frame), where lin2db(JNR/S) would be +Inf →
    # JSON poison (the slice-2 null watch-item, here on the J/S readout). >0 = jammed, <0 = burn-through.
    if contribs !== nothing
        tel["$sid.jnr_db"] = _snr_db_wire(jnr_total)
        tel["$sid.js_db"]  = _snr_db_wire(jnr_total) - _snr_db_wire(best_snr_th)
    end
    return nothing
end

# --- CFAR profile path (slice-3 step 3) -----------------------------------------
#
# Within a CFAR scenario `observe!` builds a range-power PROFILE every look and draws it,
# instead of the legacy per-target point detector. The profile is the slice's new core
# object: a vector of linear-power range cells (each Δr = c/2B wide, from the matched-filter
# bandwidth — physically honest, HANDOFF §1). The CFAR rung (`w.fidelity[:cfar]`) selects
# ONLY the thresholding rule ([`cfar_scan`](@ref), pure); the profile DRAW is identical for
# every rung, so a mid-run rung toggle is bit-identical (the slice-3 determinism trap —
# test_determinism pins it).
#
# Cell model — a NAMED approximation (HANDOFF §1): each cell is a fast-Rayleigh square-law
# statistic z_i = Σ_{p=1}^{N_p} |x_p|², x_p ~ CN(0, power_i), drawn as 2 randn/pulse/cell.
# The per-cell linear power is computed DETERMINISTICALLY first — noise floor 1, + clutter
# (elevated-mean exponential over a band), + each target's `_target_snr` (so the profile
# composes with `:propagation` → lobing AND the below-horizon mask). Noise/clutter cells
# stay exponential at N_p=1 (Gamma(N_p,1) integrated), so the CA/OS closed forms hold in the
# homogeneous interior. The TARGET folds into the same variance (SW2-like fluctuation in the
# profile) — distinct from the scalar `pd` readout, which stays the analytic Pd at the design
# `pfa` for the scenario's configured `swerling` (the plan's explicit definition; a reference
# readout, not the CFAR cell's detection probability — the profile/threshold arrays carry that).
# The draw count is ALWAYS 2·N_p·N_cells, independent of the rung AND of where the target
# sits — that invariance is what keeps the RNG stream in lockstep across a live toggle.

const _CFAR_DEFAULT_NTRAIN = 16
const _CFAR_DEFAULT_NGUARD = 2

# Range-cell width from the matched-filter (noise) bandwidth: Δr = c/(2·B).
_cfar_dr(rp::RadarParams) = C_LIGHT / (2 * rp.bandwidth_hz)

# Range of cell `ci` (1-based) and its inverse (range → cell index, 0 if off the grid).
_cell_range(ci::Int, rstart::Float64, dr::Float64) = rstart + (ci - 1) * dr
function _range_to_cell(R::Float64, rstart::Float64, dr::Float64, ncells::Int)
    idx = round(Int, (R - rstart) / dr) + 1
    return (1 ≤ idx ≤ ncells) ? idx : 0
end

# Draw one fast-Rayleigh range-power profile into `z` from the deterministic `power` vector:
# 2·N_p randn per cell, cell-by-cell in index order (the RNG draw contract). For power=1
# (noise) each pulse is |CN(0,1)|² = Exp(1), so z_i ~ Gamma(N_p,1) — the homogeneous floor
# the CA/OS α calibrates against. This is the ONLY RNG call of a CFAR look; the cell-count
# (= length(power)) and per-cell draw count are fixed by config, never by geometry, so the
# stream advances identically across rungs and target positions (the determinism contract).
function _draw_profile!(z::Vector{Float64}, power::Vector{Float64}, rng::AbstractRNG, n_pulses::Int)
    @inbounds for i in eachindex(power)
        σ = sqrt(power[i] / 2)                 # per-quadrature σ of CN(0, power_i)
        acc = 0.0
        for _ in 1:n_pulses
            xI = randn(rng) * σ
            xQ = randn(rng) * σ
            acc += xI * xI + xQ * xQ
        end
        z[i] = acc
    end
    return z
end

# The static range axis of a CFAR scenario's radar — shipped ONCE in the handshake
# (`scenario_frame`, server.jl), never per frame (it can't change). `nothing` if the
# scenario isn't CFAR. Single radar (slice-3 scope); the loader guarantees `n_cells ≥ 1`
# for a `:cfar` scenario, so this can't `KeyError` at handshake (which runs inside the
# session's IO/EOF-only try — a throw there would kill the connection before the client
# ever builds its range-power view).
function _cfar_axis_info(w::World)
    haskey(w.fidelity, :cfar) || return nothing
    radars = sort!(Symbol[id for (id, e) in w.entities if e.kind === :radar])
    isempty(radars) && return nothing
    radar  = w.entities[radars[1]]
    dr     = _cfar_dr(_radar_params(radar.comp))
    rstart = Float64(get(radar.comp, :range_start_m, 0.0))
    ncells = Int(radar.comp[:n_cells])
    axis   = collect(rstart .+ (0:(ncells - 1)) .* dr)
    return Dict{Symbol,Any}(:radar => radars[1], :dr_m => dr, :n_cells => ncells,
                            :range_start_m => rstart, :range_axis_m => axis)
end

"""
    _observe_cfar!(r::RadarSensor, w)

The CFAR detector: build a range-power profile each look, draw it, and threshold it with
the active `:cfar` rung. Publishes the slice-1/2 strongest-target scalars (analytic, every
tick) PLUS the per-cell `profile_db` / `threshold_db` / `detections` arrays, and pushes one
`:detection` event per detected cell (a target-cell hit carries `:of`; a clutter/noise
false alarm carries only `:cell` / `:range`). See the module note above for the cell model
and the determinism contract.
"""
function _observe_cfar!(r::RadarSensor, w::World)
    radar = w.entities[r.id]
    prop  = get(w.fidelity, :propagation, :free_space)
    variant = w.fidelity[:cfar]
    variant in CFAR_MODES ||
        error("RadarSensor: cfar fidelity :$variant not implemented " *
              "($(join(CFAR_MODES, " | ")))")

    rp  = _radar_params(radar.comp)
    pfa = Float64(radar.comp[:pfa])
    sw  = Int(radar.comp[:swerling])
    np  = Int(get(radar.comp, :n_pulses, 1))

    # Window knobs are LIVE (set_param sliders), so sanitize at the CONSUMER — a slider
    # dragged to an odd n_train (or a negative guard) must NEVER throw inside `cfar_scan` →
    # `tick!` → kill the session (the slice-2 set_fidelity / h≥0 watch-item, generalised:
    # a live knob can't crash the tick). The loader rejects a malformed AUTHORED value as a
    # clear load error; this clamps the live drag to the nearest legal window.
    raw_nt  = Int(get(radar.comp, :n_train, _CFAR_DEFAULT_NTRAIN))
    raw_ng  = Int(get(radar.comp, :n_guard, _CFAR_DEFAULT_NGUARD))
    n_train = max(2, 2 * (raw_nt ÷ 2))          # force even ≥ 2 (N/2 training cells per side)
    n_guard = max(0, raw_ng)

    dr     = _cfar_dr(rp)
    rstart = Float64(get(radar.comp, :range_start_m, 0.0))
    ncells = Int(radar.comp[:n_cells])

    # Strongest-target scalars (analytic, NO RNG) — published every tick for the readout,
    # exactly as the point path does. NB: do NOT early-return on an empty target list — a
    # clutter-only (or momentarily target-free) CFAR profile must still draw + ship (it is a
    # core sandbox view). `best_snr = -Inf` then floors cleanly through `_snr_db_wire`.
    best_snr = -Inf; best_pd = 0.0; best_visible = true; best_cell = 0
    cell_target = Dict{Int,Symbol}()            # cell → target id, for the event :of tag
    bumps = Tuple{Int,Float64}[]                # (cell, linear SNR) to add to the profile power
    target_ids = sort!(Symbol[id for (id, e) in w.entities if e.kind === :target])
    for tid in target_ids
        tgt = w.entities[tid]
        snr, vis = _target_snr(prop, rp, radar, tgt)
        pd  = pd_analytic(snr, pfa; swerling = sw, n_pulses = np)
        ci  = _range_to_cell(_range(tgt.pos, radar.pos), rstart, dr, ncells)
        if ci != 0
            get!(cell_target, ci, tid)          # first (sorted) target wins a shared cell
            push!(bumps, (ci, snr))
        end
        if snr > best_snr
            best_snr = snr; best_pd = pd; best_visible = vis; best_cell = ci
        end
    end

    is_look = w.t + 1e-12 ≥ get(radar.comp, :next_look_t, 0.0)
    if is_look
        # 1. deterministic power profile: noise floor 1 + clutter band(s) + target bumps.
        power = ones(Float64, ncells)
        for (_, e) in w.entities
            e.kind === :clutter || continue
            # Clutter occupies a RANGE band [R_near, R_near+extent] on the same (slant)
            # axis the targets use — a hard-edged elevated-mean exponential (named approx).
            Rc  = _range(e.pos, radar.pos)
            ext = Float64(get(e.comp, :extent_m, 0.0))
            cnr = db2lin(Float64(get(e.comp, :cnr_db, 0.0)))
            @inbounds for ci in 1:ncells
                Rcell = _cell_range(ci, rstart, dr)
                (Rc ≤ Rcell ≤ Rc + ext) && (power[ci] += cnr)
            end
        end
        @inbounds for (ci, snr) in bumps
            power[ci] += snr
        end

        # 2. draw the noisy profile (the ONLY RNG of the look) + scan (pure, no RNG).
        z = Vector{Float64}(undef, ncells)
        _draw_profile!(z, power, w.rng, np)
        threshold, detections = cfar_scan(z; variant = variant, n_train = n_train,
                                          n_guard = n_guard, pfa = pfa, n_pulses = np)

        # 3. store the realization — republished as telemetry every tick between looks
        #    (so the readout never blanks between scans, the slice-1/2 pattern).
        radar.comp[:profile_z]     = z
        radar.comp[:threshold_lin] = threshold
        radar.comp[:detections]    = detections
        radar.comp[:detected]      = (best_cell != 0) && detections[best_cell]

        # 4. one :detection event per detected cell. A target-cell hit carries :of; a
        #    clutter/noise false alarm carries only :cell/:range — the clutter-edge spike IS
        #    false alarms, so the lesson surface is explicit, not implicit (slice-3 plan §5).
        @inbounds for ci in 1:ncells
            detections[ci] || continue
            ev = Dict{Symbol,Any}(:kind => :detection, :by => r.id, :cell => ci,
                                  :range => _cell_range(ci, rstart, dr))
            haskey(cell_target, ci) && (ev[:of] = cell_target[ci])
            push!(w.events, ev)
        end

        radar.comp[:next_look_t] = get(radar.comp, :next_look_t, 0.0) + r.revisit_s
    end

    # Telemetry: slice-1/2 scalars (strongest target) + the new per-cell arrays. Arrays are
    # floored through `_snr_db_wire` so an empty/null cell (lin2db(0) = -Inf) never reaches
    # the wire (the slice-2 watch-item, now over a whole array). The threshold curve is CORE
    # output — shipped, never recomputed in the client (HANDOFF §1: physics in the core).
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(r.id)
    tel["$sid.snr_db"]   = _snr_db_wire(best_snr)
    tel["$sid.pd"]       = best_pd
    tel["$sid.detected"] = get(radar.comp, :detected, false)
    tel["$sid.visible"]  = best_visible
    if haskey(radar.comp, :profile_z)
        tel["$sid.profile_db"]   = _snr_db_wire.(radar.comp[:profile_z])
        tel["$sid.threshold_db"] = _snr_db_wire.(radar.comp[:threshold_lin])
        tel["$sid.detections"]   = radar.comp[:detections]
    end
    return nothing
end
