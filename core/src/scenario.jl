# scenario.jl — declarative YAML → (World, subsystems, knobs) (HANDOFF §6, step 5).
#
# The YAML is the single source for save/replay, MC inputs, test fixtures, and the
# core↔client contract. Adding a slice means adding new `kind`s + their component
# blocks here; the loader, protocol and tick loop don't change.
#
# `load_scenario` returns a `Scenario` — a superset of the §6 `(World, subsystems,
# knobs)` triple that also carries the server's timing config (`dt_physics`,
# `emit_every`) so step 7's run loop has a home for them.

using YAML

"""
    Knob(target, key, min, max, label; log = false)

One client-facing slider declared by a scenario. `target`/`key` name an entity and
a parameter in its `comp` bag — the same address the `set_param` command writes — so
a slider works without any protocol change. `log` marks a logarithmic axis.
"""
struct Knob
    target::Symbol
    key::Symbol
    min::Float64
    max::Float64
    label::String
    log::Bool
end
Knob(target, key, mn, mx, label; log = false) =
    Knob(Symbol(target), Symbol(key), Float64(mn), Float64(mx), String(label), Bool(log))

"""
    Scenario(name, world, subs, knobs, dt_physics, emit_every)

A loaded scenario: the `World` (truth + seeded RNG + fidelity), the ordered
subsystem vector, the declared knobs, and the server timing. The subsystem order is
deterministic (sorted by entity id) — it fixes the cross-subsystem RNG draw order,
which is the §1 bug class made free while there is only one emitter.
"""
struct Scenario
    name::String
    world::World
    subs::Vector{Subsystem}
    knobs::Vector{Knob}
    dt_physics::Float64
    emit_every::Int
end

# YAML scalars arrive as Int or Float64; coerce the ones we compute with to Float64.
_f64(x) = Float64(x)
_vec3(v) = Vec3(_f64(v[1]), _f64(v[2]), _f64(v[3]))

# A `radar:` block maps to TWO sinks in one comp bag: the 6 RadarParams fields plus
# the detector config (pfa, swerling, n_pulses). `n_pulses` is the non-coherent
# integration depth (slice 3); it must be ≥ 1 (1 = the slice-1/2 single-pulse path).
# `revisit_s` is optional (defaults to look-every-tick) and drives the scan cadence.
const _RADAR_PARAM_KEYS = (:pt_w, :gain_db, :freq_hz, :bandwidth_hz, :noise_fig_db, :losses_db, :pfa)

function _radar_comp!(comp::Dict{Symbol,Any}, block::AbstractDict)
    for k in _RADAR_PARAM_KEYS
        haskey(block, String(k)) || error("radar block missing required key '$(k)'")
        comp[k] = _f64(block[String(k)])
    end
    comp[:swerling] = Int(get(block, "swerling", 1))
    np = Int(get(block, "n_pulses", 1))
    np ≥ 1 || error("radar n_pulses=$np: must be ≥ 1")
    comp[:n_pulses] = np
    haskey(block, "revisit_s") && (comp[:revisit_s] = _f64(block["revisit_s"]))
    # Optional CFAR config (slice 3): the STATIC profile geometry (n_cells / range_start_m)
    # plus the LIVE window sliders (n_train / n_guard). Only read when present, so a slice-1/2
    # radar block leaves these out of the comp bag entirely (its point path never reads them).
    # A `:cfar` scenario's required-keys are checked in `load_scenario` (clear load error).
    haskey(block, "n_cells")       && (comp[:n_cells]       = Int(block["n_cells"]))
    haskey(block, "range_start_m") && (comp[:range_start_m] = _f64(block["range_start_m"]))
    haskey(block, "n_train")       && (comp[:n_train]       = Int(block["n_train"]))
    haskey(block, "n_guard")       && (comp[:n_guard]       = Int(block["n_guard"]))
    # Optional two-level antenna + EP config (slice 4): the receive pattern (beamwidth /
    # sidelobe floor) and the EP parameters (frequency-agility hop band / sidelobe-blanking
    # cancel depth). Read into the comp bag only when present — `build_env!` / `_ep_factor`
    # already fall back to the radar.jl defaults via `get(comp, …, default)`, so a slice-1/2/3
    # radar block omits them entirely AND toggling `:ep` onto any scenario stays crash-safe.
    # Beamwidth is authored in DEGREES (the natural unit) and stored as RADIANS (the key the
    # antenna model reads), matching the `comp[:beamwidth_rad]` spelling test_jammer.jl uses.
    haskey(block, "beamwidth_deg") && (comp[:beamwidth_rad] = deg2rad(_f64(block["beamwidth_deg"])))
    haskey(block, "sidelobe_db")   && (comp[:sidelobe_db]   = _f64(block["sidelobe_db"]))
    haskey(block, "agile_bw_hz")   && (comp[:agile_bw_hz]   = _f64(block["agile_bw_hz"]))
    haskey(block, "cancel_db")     && (comp[:cancel_db]     = _f64(block["cancel_db"]))
    return comp
end

# kind → (Entity comp filled from its block, [subsystems for this entity]).
function _build_entity(id::Symbol, kind::Symbol, ent::AbstractDict)
    pos = haskey(ent, "pos") ? _vec3(ent["pos"]) : zero(Vec3)
    vel = haskey(ent, "vel") ? _vec3(ent["vel"]) : zero(Vec3)
    comp = Dict{Symbol,Any}()
    e = Entity(id, kind; pos = pos, vel = vel, comp = comp)

    if kind === :radar
        haskey(ent, "radar") || error("radar entity '$id' has no `radar:` block")
        _radar_comp!(comp, ent["radar"])
        subs = Subsystem[RadarSensor(id; revisit_s = get(comp, :revisit_s, 0.0))]
    elseif kind === :target
        haskey(ent, "target") || error("target entity '$id' has no `target:` block")
        tb = ent["target"]
        comp[:rcs_m2] = _f64(tb["rcs_m2"])
        # Slice 13: the `:scan` seeker paints a lobe of amplitude `comp[:intensity]` (over the unit
        # floor) per source into its angular profile — the target's brightness AS SEEN BY the seeker
        # (the RCS/radiant ratio; the lobe amplitude and the `:none` centroid weight). DEFAULTS to 1.0
        # so slices 1–12 (which never read it) are byte-identical; validated ≥ 0 (a negative amplitude
        # is meaningless — a live huge value just paints a taller lobe, no crash: "a live slider can't
        # crash a tick"). KNOB-addressable (a gate-3 slider names this comp key).
        comp[:intensity] = _f64(get(tb, "intensity", 1.0))
        comp[:intensity] >= 0 ||
            error("target '$id': intensity must be ≥ 0 (got $(comp[:intensity]))")
        # Slice 12: a `maneuver:` sub-block turns the straight-line target into a CURVING one — swap
        # ConstantVelocity → ManeuveringTarget (the augmented-PN foil). `a_lat_mps2`/`turn_sign` land
        # at KNOB-ADDRESSABLE comp keys, read with DEFAULTS at the consumer (a bare block / live
        # slider can't KeyError a tick). A plain target (NO `maneuver:` block) stays ConstantVelocity
        # → byte-identical to slices 1..11 (the additivity master-check). `a_lat_mps2` is load-
        # validated FINITE (a huge live value just curves harder — the "a live slider can't crash a
        # tick" discipline; `turn_sign` defaults to +1, the clean direction — gate-0 probe).
        if haskey(tb, "maneuver")
            mn = tb["maneuver"]
            comp[:a_lat_mps2] = _f64(get(mn, "a_lat_mps2", 0.0))
            comp[:turn_sign]  = _f64(get(mn, "turn_sign", 1.0))
            isfinite(comp[:a_lat_mps2]) ||
                error("target '$id': maneuver.a_lat_mps2 must be finite (got $(comp[:a_lat_mps2]))")
            isfinite(comp[:turn_sign]) ||   # a NaN/Inf sign → NaN accel → NaN pos → non-finite JSON (conv. 6)
                error("target '$id': maneuver.turn_sign must be finite (got $(comp[:turn_sign]))")
            subs = Subsystem[ManeuveringTarget(id)]
        else
            subs = Subsystem[ConstantVelocity(id)]
        end
    elseif kind === :decoy
        # A countermeasure decoy (slice 13): chaff / a flare — a PASSIVE `ConstantVelocity` mover
        # (born already-separated in angle from the target, flying parallel — the "present from t=0,
        # constant velocity, constant intensity" named approximations; no bloom / burn-out / timed
        # ejection). It carries a `comp[:intensity]` lobe amplitude the `:scan` seeker paints just like
        # a target's — but its `kind === :decoy` (NEVER `:target`) so `_nearest_target` (radar / jammer
        # boresight / the Autopilot truth path / the CPA-miss readout) SKIPS it: the seeker may be
        # SEDUCED, but miss/CPA is ALWAYS computed vs the true `:target` (the truth-path invariant).
        # The ONLY consumer that sees the decoy is the `:scan` Seeker's angular profile. `intensity`
        # is KNOB-addressable + validated ≥ 0 (the target-arm precedent; a live huge value just paints
        # a taller lobe — no crash).
        db = get(ent, "decoy", Dict{Any,Any}())
        comp[:intensity] = _f64(get(db, "intensity", 1.0))
        comp[:intensity] >= 0 ||
            error("decoy '$id': intensity must be ≥ 0 (got $(comp[:intensity]))")
        subs = Subsystem[ConstantVelocity(id)]
    elseif kind === :clutter
        # A passive range-band clutter source (slice 3): elevated-mean exponential power
        # over [range, range+extent] of the radar's profile. NO subsystem — it owns no
        # physics of its own; the radar's CFAR `observe!` reads its `pos`/`extent_m`/`cnr_db`.
        haskey(ent, "clutter") || error("clutter entity '$id' has no `clutter:` block")
        cb = ent["clutter"]
        comp[:extent_m] = _f64(cb["extent_m"])
        comp[:cnr_db]   = _f64(cb["cnr_db"])
        subs = Subsystem[]
    elseif kind === :jammer
        # A noise jammer (slice 4): an ENTITY with a `build_env!`-only [`Jammer`](@ref)
        # subsystem (it raises the radar's noise floor through `w.env`, never by a direct call)
        # PLUS a `ConstantVelocity` mover so it can close (self-screen) or hold station
        # (standoff). Unlike `:clutter` it owns a subsystem of its own.
        haskey(ent, "jammer") || error("jammer entity '$id' has no `jammer:` block")
        jb = ent["jammer"]
        for k in (:pt_w, :gain_db, :bandwidth_hz)
            haskey(jb, String(k)) || error("jammer '$id' block missing required key '$k'")
            comp[k] = _f64(jb[String(k)])
        end
        # bandwidth_hz must be > 0: a non-positive value would throw a DomainError inside
        # `jam_noise_ratio` → `build_env!` → `tick!`, and the session's IO/EOF-only catch would
        # silently drop the connection (the slice-2/3 tick-throw watch-item). It is NOT a live
        # slider (gate-4 sliders are pt_w / range), so reject it at LOAD as a clear error.
        comp[:bandwidth_hz] > 0 ||
            error("jammer '$id': bandwidth_hz must be > 0 (got $(comp[:bandwidth_hz]))")
        subs = Subsystem[ConstantVelocity(id), Jammer(id)]
    elseif kind === :emitter
        # An RF emitter (slice 5): the DF target. A `ConstantVelocity` mover lets it fly the
        # good→bad-geometry path that sweeps GDOP. It owns no sensor of its own — the DF
        # sensors bear IT. Minimal comp (no rcs: DF works off the bearing, not a radar echo).
        subs = Subsystem[ConstantVelocity(id)]
    elseif kind === :df_sensor
        # A bearings-only DF sensor (slice 5): a `df_sensor:` block carries `sigma_theta_deg`
        # (authored AND stored in DEGREES — `comp[:sigma_theta_deg]`, the key `DFSensor.observe!`
        # reads and converts to radians at the consumer). DEGREES is the comp key (NOT radians)
        # precisely because σθ is a LIVE slider (gate 3): a `set_param sigma_theta_deg` must write
        # the same key the consumer reads, and the slider/readout stay in the authored unit. Plus
        # a `ConstantVelocity` mover (usually static, vel = 0). One noisy bearing/look in phase 3.
        haskey(ent, "df_sensor") || error("df_sensor entity '$id' has no `df_sensor:` block")
        sb = ent["df_sensor"]
        haskey(sb, "sigma_theta_deg") ||
            error("df_sensor '$id' block missing required key 'sigma_theta_deg'")
        σdeg = _f64(sb["sigma_theta_deg"])
        # σθ ≤ 0 → infinite weights (1/σ²) → NaN fix. NOT a live slider's value (a live drag is
        # clamped at the consumer, `_SIGMA_THETA_FLOOR`); reject a bad AUTHORED value at LOAD as
        # a clear error (the jammer `bandwidth_hz > 0` precedent).
        σdeg > 0 || error("df_sensor '$id': sigma_theta_deg must be > 0 (got $σdeg)")
        comp[:sigma_theta_deg] = σdeg
        subs = Subsystem[ConstantVelocity(id), DFSensor(id)]
    elseif kind === :df_station
        # The C2 / fusion node (slice 5): a phase-4 `Geolocator` crossing all bearings into a
        # fix + error ellipse + GDOP. An optional `geolocator:` block sets `nsigma` (the error-
        # ellipse confidence scale, default 1-σ). A `ConstantVelocity` mover for uniformity.
        nsig = haskey(ent, "geolocator") ? _f64(get(ent["geolocator"], "nsigma", 1.0)) : 1.0
        subs = Subsystem[ConstantVelocity(id), Geolocator(id; nsigma = nsig)]
    elseif kind === :pulse_emitter
        # A pulse emitter (slice 6): a constant-PRI radar the ESM intercepts. A `pulse_emitter:`
        # block carries `pri_us`/`phase_us`/`pulse_width_us` — authored in µs (the natural unit),
        # stored SI SECONDS (the key `PulseEmitter.build_env!` reads — the §1 µs/s trifecta, the
        # `beamwidth_deg→rad` mirror). Plus a `ConstantVelocity` mover (usually static). Publishes
        # its params to `env[:emitters]` in phase 2. NB: distinct from slice-5 DF's `:emitter` kind.
        haskey(ent, "pulse_emitter") || error("pulse_emitter entity '$id' has no `pulse_emitter:` block")
        pb = ent["pulse_emitter"]
        for (ck, uk) in ((:pri, "pri_us"), (:phase, "phase_us"), (:pulse_width, "pulse_width_us"))
            haskey(pb, uk) || error("pulse_emitter '$id' block missing required key '$uk'")
            comp[ck] = _f64(pb[uk]) * 1.0e-6                    # µs → SI seconds
        end
        # PRI ≤ 0 → an infinite emit loop in `_draw_toa_stream` (`phase + k·PRI` never advances)
        # → a hung tick. Not a live slider; reject a bad AUTHORED value at LOAD (the jammer
        # `bandwidth_hz > 0` / df `sigma_theta_deg > 0` precedent).
        comp[:pri] > 0 || error("pulse_emitter '$id': pri_us must be > 0 (got $(pb["pri_us"]))")
        subs = Subsystem[ConstantVelocity(id), PulseEmitter(id)]
    elseif kind === :esm
        # The ESM intercept + fusion platform (slice 6): a `ConstantVelocity` mover + an
        # `ESMReceiver` (phase-3, the one draw site) + a `Deinterleaver` (phase-4). An `esm:`
        # block carries the STATIC config (`t_dwell_us`, `n_spurious`, and the histogram /
        # extraction params, all with sane defaults matching gate-1's proven set) plus the LIVE
        # sliders `jitter_us` (µs) + `p_intercept`. Static params define the draw count / axis, so
        # they are load-time only; only jitter/intercept are live (draw-count-invariant). Times
        # authored in µs, stored SI seconds (the §1 boundary).
        haskey(ent, "esm") || error("esm entity '$id' has no `esm:` block")
        eb = ent["esm"]
        haskey(eb, "t_dwell_us") || error("esm '$id' block missing required key 't_dwell_us'")
        comp[:t_dwell]     = _f64(eb["t_dwell_us"])         * 1.0e-6
        comp[:bin_width]   = _f64(get(eb, "bin_us",      20.0))   * 1.0e-6
        comp[:max_lag]     = _f64(get(eb, "max_lag_us",  3000.0)) * 1.0e-6
        comp[:seq_tol]     = _f64(get(eb, "seq_tol_us",  30.0))   * 1.0e-6
        comp[:assoc_tol]   = _f64(get(eb, "assoc_tol_us", 50.0))  * 1.0e-6
        comp[:levels]      = Int(get(eb, "levels", 15))
        comp[:min_seq]     = Int(get(eb, "min_seq", 10))
        comp[:thresh_frac] = _f64(get(eb, "thresh_frac", 0.4))
        comp[:n_spurious]  = Int(get(eb, "n_spurious", 0))
        comp[:jitter_us]   = _f64(get(eb, "jitter_us", 0.0))     # LIVE slider (µs)
        comp[:p_intercept] = _f64(get(eb, "p_intercept", 1.0))   # LIVE slider
        haskey(eb, "revisit_s") && (comp[:revisit_s] = _f64(eb["revisit_s"]))
        # Load-time guards (crash-safety: a malformed AUTHORED config must fail as a clear load
        # error, not a hung/OOB tick inside the session's IO-only catch).
        comp[:t_dwell]   > 0 || error("esm '$id': t_dwell_us must be > 0 (got $(eb["t_dwell_us"]))")
        comp[:bin_width] > 0 || error("esm '$id': bin_us must be > 0")
        comp[:max_lag]   > comp[:bin_width] ||
            error("esm '$id': max_lag_us must exceed bin_us (need ≥ 1 histogram bin)")
        comp[:levels]  ≥ 1 || error("esm '$id': levels must be ≥ 1")
        subs = Subsystem[ConstantVelocity(id), ESMReceiver(id; revisit_s = get(comp, :revisit_s, 0.0)),
                         Deinterleaver(id)]
    elseif kind === :gps_satellite
        # A GPS satellite (slice 7): a flat-local fictional far point source (named
        # approximation — NO ECEF/orbits) the receiver measures a pseudorange to. A
        # `gps_satellite:` block carries the SATELLITE clock error `clock_err_m` (a per-SV
        # constant bias, distinct from the receiver clock the solver recovers) + the injected
        # `fault_bias_m` (the spoof/failure bias — a LIVE slider in the RAIM scene, so it is the
        # comp key `set_param` addresses). All SI metres (no unit conversion — the §1 boundary is
        # trivial here). Plus a `ConstantVelocity` mover so it can drift (the DOP sweep).
        # Publishes its ephemeris to `env[:gps_sats]` in phase 2.
        gb = get(ent, "gps_satellite", Dict{Any,Any}())
        comp[:clock_err_m]  = _f64(get(gb, "clock_err_m", 0.0))
        comp[:fault_bias_m] = _f64(get(gb, "fault_bias_m", 0.0))     # LIVE slider (RAIM scene)
        subs = Subsystem[ConstantVelocity(id), GpsSatellite(id)]
    elseif kind === :gps_receiver
        # The GPS receiver + solver platform (slice 7): a `ConstantVelocity` mover (usually
        # static) + a `GpsReceiver` (phase-3, THE ONE DRAW SITE) + a `GpsSolver` (phase-4). A
        # `gps_receiver:` block carries the STATIC config (all draw-count / geometry defining, so
        # load-time only): `sigma_range_m` (ranging noise σ), `sigma_mp_m` (multipath σ),
        # `iono_zenith_m`/`tropo_zenith_m` (the deterministic-delay magnitudes), `clock_bias_m`
        # (the receiver's TRUE c·b the solver recovers — SI metres, printed as ns), the POST-DRAW
        # `elevation_mask_deg`, and `raim_threshold` (the EMPIRICAL σ-multiple RAIM threshold —
        # gnss.jl route (iii); NB the plan landmark's `pfa_raim` is stale, gate-1 rejected the
        # χ²/Pfa route because exclude→odd-DOF needs an erf, so the comp key is `raim_threshold`).
        # The five error terms are toggled by fidelity, not read here as knobs.
        rb = get(ent, "gps_receiver", Dict{Any,Any}())
        comp[:sigma_range_m]      = _f64(get(rb, "sigma_range_m", 3.0))
        comp[:sigma_mp_m]         = _f64(get(rb, "sigma_mp_m", 1.0))
        comp[:iono_zenith_m]      = _f64(get(rb, "iono_zenith_m", 5.0))
        comp[:tropo_zenith_m]     = _f64(get(rb, "tropo_zenith_m", 2.4))
        comp[:clock_bias_m]       = _f64(get(rb, "clock_bias_m", 0.0))
        comp[:elevation_mask_deg] = _f64(get(rb, "elevation_mask_deg", 0.0))
        comp[:raim_threshold]     = _f64(get(rb, "raim_threshold", 5.0))
        haskey(rb, "revisit_s") && (comp[:revisit_s] = _f64(rb["revisit_s"]))
        comp[:sigma_range_m] > 0 ||
            error("gps_receiver '$id': sigma_range_m must be > 0 (got $(comp[:sigma_range_m]))")
        subs = Subsystem[ConstantVelocity(id), GpsReceiver(id; revisit_s = get(comp, :revisit_s, 0.0)),
                         GpsSolver(id)]
    elseif kind === :missile
        # A ballistic projectile (slice 8): a `missile:` block carries `mass_kg`, the launch
        # `speed` (m/s) + `elevation_deg` (deg → the x-z-plane launch velocity), the lumped
        # drag `cd_area_m2` (drag off = 0), and optional `rho` (air density). The entity gets a
        # `BallisticMissile` (the phase-1 force integrator that OWNS pos/vel advancement) and
        # **NOT** a `ConstantVelocity` — two phase-1 movers on one entity would double-integrate
        # (the watch-item). The launch state is SI: `speed`/`elevation_deg` are stored RAW in
        # comp too (so gate-3 launch knobs can address them — a knob must name a real comp key)
        # while `vel` is derived here.
        haskey(ent, "missile") || error("missile entity '$id' has no `missile:` block")
        mb = ent["missile"]
        for k in ("mass_kg", "speed", "elevation_deg")
            haskey(mb, k) || error("missile '$id' block missing required key '$k'")
        end
        comp[:mass_kg]       = _f64(mb["mass_kg"])
        comp[:cd_area_m2]    = _f64(get(mb, "cd_area_m2", 0.0))
        comp[:rho]           = _f64(get(mb, "rho", 1.225))
        comp[:speed]         = _f64(mb["speed"])            # raw (knob-addressable, gate 3)
        comp[:elevation_deg] = _f64(mb["elevation_deg"])    # raw (knob-addressable, gate 3)
        el = deg2rad(comp[:elevation_deg])                  # deg → rad; x-z plane (no cross-range)
        e.vel = Vec3(comp[:speed] * cos(el), 0.0, comp[:speed] * sin(el))
        # Load-time guards (a malformed AUTHORED missile fails as a clear load error; a LIVE
        # slider is clamped at the consumer — mass floor / drag-off — so it can't crash a tick).
        comp[:mass_kg]    > 0 || error("missile '$id': mass_kg must be > 0 (got $(comp[:mass_kg]))")
        comp[:cd_area_m2] ≥ 0 ||
            error("missile '$id': cd_area_m2 must be ≥ 0 (got $(comp[:cd_area_m2]))")
        comp[:rho]        ≥ 0 || error("missile '$id': rho must be ≥ 0 (got $(comp[:rho]))")
        subs = Subsystem[BallisticMissile(id)]
        # Slice 11: a `seeker:` sub-block adds the phase-3 `Seeker` (the missile's first sensor) —
        # a noisy LOS-angle seeker feeding the α-β LOS-rate filter that PN reads instead of truth.
        # Its `sigma_seek`/`alpha`/`beta` land at KNOB-ADDRESSABLE comp keys (a gate-3 slider must
        # name a real comp key) read with DEFAULTS at the consumer (a bare block / live slider can't
        # KeyError a tick). Armed BEFORE the Autopilot so the entity is `[BallisticMissile, Seeker,
        # Autopilot]` (the plan's order; phases separate observe!/decide! regardless). A slice-1..10
        # missile has NO `seeker:` block → no Seeker → no `w.rng` draw → byte-identical (the seeker
        # is the FIRST missile-arc RNG consumer; byte-identity comes from it NOT EXISTING). The
        # α-β gains are load-validated (0<α<1, β>0) so a live filter can't be silently nulled; σ≥0
        # (a negative angular noise is meaningless — the consumer also floors it).
        if haskey(mb, "seeker")
            sb = mb["seeker"]
            comp[:sigma_seek] = _f64(get(sb, "sigma_seek", 3.0e-3))   # 1-σ LOS angular noise (rad)
            comp[:alpha]      = _f64(get(sb, "alpha", 0.30))          # α-β angle gain (0<α<1)
            comp[:beta]       = _f64(get(sb, "beta",  0.05))          # α-β rate gain (β>0)
            comp[:sigma_seek] >= 0 ||
                error("missile '$id': seeker.sigma_seek must be ≥ 0 (got $(comp[:sigma_seek]))")
            (0 < comp[:alpha] < 1) ||
                error("missile '$id': seeker.alpha must be in (0,1) (got $(comp[:alpha]))")
            comp[:beta] > 0 ||
                error("missile '$id': seeker.beta must be > 0 (got $(comp[:beta]))")
            # Slice 13: the `:scan` seeker (fidelity `seeker: scan`) forms a NOISY angular-power
            # PROFILE over a FIXED grid (the slice-3 CFAR sandbox on the LOS-ANGLE axis) instead of
            # ONE noisy truth bearing. The grid/beam/CFAR/gate config lands here (STATIC — draw-count/
            # axis defining, so load-time only, NOT live sliders; only `intensity`/`gate_halfwidth`
            # are knobs), read with DEFAULTS at the consumer (the gate-0 FINDINGS operating point). A
            # `:raw`/`:filtered` seeker never reads these keys → they are inert there (slices 1–12
            # byte-identical). All LOAD-validated: a malformed config must fail as a clear load error,
            # NOT a throw inside `cfar_scan`/`_draw_profile!` → observe! → the session's IO-only catch.
            comp[:scan_n_bins]      = Int(get(sb, "n_bins", 64))            # fixed grid cell count
            comp[:scan_bin_width]   = _f64(get(sb, "bin_width", 0.005))     # bin angular width (rad)
            comp[:scan_sigma_beam]  = _f64(get(sb, "sigma_beam", 0.015))    # Gaussian lobe σ (rad)
            comp[:scan_floor]       = _f64(get(sb, "floor", 1.0))           # homogeneous noise floor
            comp[:scan_n_pulses]    = Int(get(sb, "n_pulses", 10))          # N_p integration (draw ×2·N_p·N_bins)
            comp[:scan_cfar_variant]= Symbol(get(sb, "cfar_variant", "ca")) # CFAR detector variant
            comp[:scan_cfar_ntrain] = Int(get(sb, "cfar_n_train", 16))      # training cells (even)
            comp[:scan_cfar_nguard] = Int(get(sb, "cfar_n_guard", 4))       # guard cells
            comp[:scan_cfar_pfa]    = _f64(get(sb, "cfar_pfa", 1.0e-3))     # CFAR design Pfa
            comp[:gate_halfwidth]   = _f64(get(sb, "gate_halfwidth", 0.045))# α-β validation-gate half-width (rad, KNOB)
            comp[:scan_n_bins]  ≥ 1 ||
                error("missile '$id': seeker.n_bins must be ≥ 1 (got $(comp[:scan_n_bins]))")
            comp[:scan_bin_width]  > 0 ||
                error("missile '$id': seeker.bin_width must be > 0 (got $(comp[:scan_bin_width]))")
            comp[:scan_sigma_beam] > 0 ||
                error("missile '$id': seeker.sigma_beam must be > 0 (got $(comp[:scan_sigma_beam]))")
            comp[:scan_floor]      > 0 ||   # √(power/2) in _draw_profile!; a ≤0 floor makes the noise σ imaginary/NaN
                error("missile '$id': seeker.floor must be > 0 (got $(comp[:scan_floor]))")
            comp[:scan_n_pulses]   ≥ 1 ||
                error("missile '$id': seeker.n_pulses must be ≥ 1 (got $(comp[:scan_n_pulses]))")
            comp[:scan_cfar_variant] in CFAR_VARIANTS ||
                error("missile '$id': seeker.cfar_variant must be one of $(CFAR_VARIANTS) " *
                      "(got :$(comp[:scan_cfar_variant]))")
            iseven(comp[:scan_cfar_ntrain]) && comp[:scan_cfar_ntrain] ≥ 2 ||
                error("missile '$id': seeker.cfar_n_train must be even and ≥ 2 (got $(comp[:scan_cfar_ntrain]))")
            comp[:scan_cfar_nguard] ≥ 0 ||
                error("missile '$id': seeker.cfar_n_guard must be ≥ 0 (got $(comp[:scan_cfar_nguard]))")
            (0 < comp[:scan_cfar_pfa] < 1) ||
                error("missile '$id': seeker.cfar_pfa must be in (0,1) (got $(comp[:scan_cfar_pfa]))")
            comp[:gate_halfwidth]  > 0 ||
                error("missile '$id': seeker.gate_halfwidth must be > 0 (got $(comp[:gate_halfwidth]))")
            # The OS/SO/GO CFAR closed forms are N_p=1 ONLY (`cfar_alpha`/`_cfar_pfa` THROW for
            # n_pulses>1). With the seeker running N_p>1, an authored os/so/go variant would throw
            # inside `cfar_scan` → observe! → session death — reject the combo at LOAD (advisor).
            (comp[:scan_cfar_variant] in (:os, :so, :go) && comp[:scan_n_pulses] > 1) &&
                error("missile '$id': seeker.cfar_variant :$(comp[:scan_cfar_variant]) requires " *
                      "n_pulses == 1 (got $(comp[:scan_n_pulses])); use :ca for multi-pulse integration")
            push!(subs, Seeker(id))
        end
        # Slice 9: a GUIDED missile carries a `guidance:` sub-block (k_guid/kp/ki/kd/tau/a_max). Its
        # presence adds the `Autopilot` (phase-4 decide!) and reads the gains into comp — the gain
        # keys are KNOB-ADDRESSABLE (a gate-3 slider must name a real comp key), and the consumer
        # (Autopilot.decide!) reads them with DEFAULTS too so a bare block / live slider can't
        # KeyError a tick. A BALLISTIC slice-8 missile has NO `guidance:` block → stays
        # `[BallisticMissile]` only, byte-identical. The Autopilot target-locks the nearest `:target`
        # at runtime (single target in slice 9), validated PRESENT at LOAD by `_validate_missile`.
        if haskey(mb, "guidance")
            gb = ent["missile"]["guidance"]
            comp[:k_guid] = _f64(get(gb, "k_guid", 3.0))
            comp[:n_pn]   = _f64(get(gb, "n_pn", 4.0))          # slice-10 PN navigation constant
            comp[:r_stop] = _f64(get(gb, "r_stop", 0.0))        # slice-10 endgame cutoff (0 = off)
            comp[:kp]     = _f64(get(gb, "kp", 2.0))
            comp[:ki]     = _f64(get(gb, "ki", 0.0))
            comp[:kd]     = _f64(get(gb, "kd", 0.0))
            comp[:tau]    = _f64(get(gb, "tau", 0.3))
            comp[:a_max]  = _f64(get(gb, "a_max", 3000.0))
            # Load-time guards for the AUTHORED values (a live tau→0 slider is clamped at the
            # consumer via `max(tau, _FRAME_EPS)`; a_max is fixed config, not a slider). n_pn>0 (a
            # zero/negative gain would silently null PN); r_stop≥0 (a negative cutoff is meaningless —
            # 0 = off, the byte-identity default).
            comp[:tau]    > 0 || error("missile '$id': guidance.tau must be > 0 (got $(comp[:tau]))")
            comp[:a_max]  > 0 || error("missile '$id': guidance.a_max must be > 0 (got $(comp[:a_max]))")
            comp[:n_pn]   > 0 || error("missile '$id': guidance.n_pn must be > 0 (got $(comp[:n_pn]))")
            comp[:r_stop] >= 0 || error("missile '$id': guidance.r_stop must be ≥ 0 (got $(comp[:r_stop]))")
            push!(subs, Autopilot(id))
        end
    else
        error("unknown entity kind :$kind for '$id' (knows :radar, :target, :decoy, :clutter, " *
              ":jammer, :emitter, :df_sensor, :df_station, :pulse_emitter, :esm, " *
              ":gps_satellite, :gps_receiver, :missile)")
    end
    return e, subs
end

function _parse_fidelity(data::AbstractDict)
    fid = Dict{Symbol,Symbol}()
    if haskey(data, "fidelity")
        for (k, v) in data["fidelity"]
            fid[Symbol(k)] = Symbol(v)
        end
    end
    return fid
end

# A fidelity VALUE that reaches a tick dispatch (`observe!`/`decide!`) as an unknown rung throws
# INSIDE `tick!` — and both the startup warmup and, more sharply, a mid-session `load_scenario`
# run that throwing tick inside the session's IO/EOF-only try (server.jl), silently killing the
# connection. Every other authored input is validated at LOAD (bandwidth>0, σθ>0, pri>0, …), but
# the fidelity map — the one authored input that can still reach a throwing tick — was not. Close
# it here, mirroring `set_fidelity`'s live check: `LIVE_FIDELITY_MODES` (radar.jl) is EXACTLY the
# set of keys a tick dispatches on, so a bad VALUE on one of those keys is the precise crash
# boundary. Keys NOT in that table (e.g. `detection`, which governs only the offline ROC batch and
# is never tick-dispatched — or an unknown key nothing reads) can't crash a tick, so their values
# pass; an UNRECOGNIZED key is `@warn`ed, not rejected, so a typo like `propogation:` (which would
# silently default the lesson away) is at least visible without hard-failing a future inert key.
const _KNOWN_FIDELITY_KEYS = (keys(LIVE_FIDELITY_MODES)..., :detection)

function _validate_fidelity(world::World)
    for (key, val) in world.fidelity
        modes = get(LIVE_FIDELITY_MODES, key, nothing)
        if modes !== nothing
            val in modes ||
                error("fidelity: $key '$val' unknown ($(join(modes, " | ")))")
        elseif !(key in _KNOWN_FIDELITY_KEYS)
            @warn "fidelity: '$key' is not a recognized fidelity key (nothing reads it)" key
        end
    end
    return world
end

function _parse_knobs(data::AbstractDict, world::World)
    knobs = Knob[]
    haskey(data, "knobs") || return knobs
    for k in data["knobs"]
        target = Symbol(k["target"]); key = Symbol(k["key"])
        # a knob must address a real entity + a real comp key, or a slider would
        # silently do nothing — fail at load instead (HANDOFF §6: target+key must exist).
        haskey(world.entities, target) || error("knob target '$target' is not an entity")
        haskey(world.entities[target].comp, key) ||
            error("knob '$target.$key' has no matching comp parameter")
        push!(knobs, Knob(target, key, k["min"], k["max"], k["label"]; log = get(k, "log", false)))
    end
    return knobs
end

"""
    load_scenario(path) -> Scenario

Parse a slice-1 scenario YAML into a ready-to-run `Scenario`. Builds the seeded
`World` (seed + fidelity), the entities with their `comp` bags, the subsystem vector
in deterministic (sorted-by-id) order, and the validated knob list.
"""
function load_scenario(path::AbstractString)
    data = YAML.load_file(path)

    name       = String(get(data, "name", "scenario"))
    seed       = Int(get(data, "seed", 0))
    dt_physics = _f64(get(data, "dt_physics", 1.0e-3))
    emit_every = Int(get(data, "emit_every", 16))

    world = World(seed = seed, fidelity = _parse_fidelity(data))

    # Build entities, then assemble the subsystem vector in sorted-id order so the
    # RNG draw sequence is reproducible regardless of YAML/Dict ordering.
    per_entity = Dict{Symbol,Vector{Subsystem}}()
    for ent in get(data, "entities", Any[])
        id   = Symbol(ent["id"])
        kind = Symbol(ent["kind"])
        e, subs = _build_entity(id, kind, ent)
        world.entities[id] = e
        per_entity[id] = subs
    end

    subs = Subsystem[]
    for id in sort!(collect(keys(per_entity)))
        append!(subs, per_entity[id])
    end

    _validate_fidelity(world)
    _validate_cfar(world)
    _validate_geoloc(world)
    _validate_esm(world)
    _validate_gps(world)
    _validate_missile(world)
    knobs = _parse_knobs(data, world)
    return Scenario(name, world, subs, knobs, dt_physics, emit_every)
end

# A `:cfar` scenario must give each radar enough to BUILD the profile + ship the static
# range axis at handshake. Check at LOAD (the established pattern — like `n_pulses ≥ 1`), so
# a malformed CFAR scenario fails as a clear load error rather than a `KeyError` inside
# `_cfar_axis_info` at handshake or inside `observe!` on the first tick — either of which
# runs in the session's IO/EOF-only try and would silently kill the connection (the slice-2
# tick-throw watch-item). `n_train` is also checked even here for a clear authoring error;
# a LIVE odd n_train is separately clamped in `_observe_cfar!` (a slider can't crash a tick).
function _validate_cfar(world::World)
    haskey(world.fidelity, :cfar) || return world
    for (id, e) in world.entities
        e.kind === :radar || continue
        (haskey(e.comp, :n_cells) && e.comp[:n_cells] ≥ 1) ||
            error("radar '$id': a :cfar scenario needs `n_cells ≥ 1` in the radar block")
        if haskey(e.comp, :n_train)
            (e.comp[:n_train] ≥ 2 && iseven(e.comp[:n_train])) ||
                error("radar '$id': n_train must be even ≥ 2 (N/2 training cells per side); " *
                      "got $(e.comp[:n_train])")
        end
    end
    return world
end

# A DF/geolocation scenario needs a crossable geometry: ≥ 2 DF sensors (two LOPs to cross),
# exactly ONE emitter (single-emitter scope — multi-emitter association is §10 item 6), and a
# fusion station. Validate at LOAD (the `_validate_cfar` pattern) so a malformed DF scenario
# fails as a clear load error rather than a silent no-fix (a lone sensor → the Geolocator's
# `< 2` guard quietly publishes nothing) or a `KeyError` inside a tick. Triggered by the
# presence of ANY DF/emitter entity (a DF scenario sets no required fidelity key — `:estimator`
# defaults `:pseudolinear`), so a pure slice-1/4 scenario is untouched.
function _validate_geoloc(world::World)
    n_sensor = 0; n_station = 0; n_emitter = 0
    for (_, e) in world.entities
        e.kind === :df_sensor  && (n_sensor  += 1)
        e.kind === :df_station && (n_station += 1)
        e.kind === :emitter    && (n_emitter += 1)
    end
    (n_sensor == 0 && n_station == 0 && n_emitter == 0) && return world   # not a DF scenario
    n_sensor ≥ 2 ||
        error("a DF/geolocation scenario needs ≥ 2 :df_sensor entities (got $n_sensor)")
    n_emitter == 1 ||
        error("a DF/geolocation scenario needs exactly one :emitter (got $n_emitter)")
    n_station ≥ 1 ||
        error("a DF/geolocation scenario needs ≥ 1 :df_station (got $n_station)")
    return world
end

# A multi-emitter EW (slice 6) scenario needs a deinterleavable stream: ≥ 2 `:pulse_emitter`
# (a single train is trivial — the density soup needs ≥ 2 interleaved) and exactly ONE `:esm`
# (single-receiver scope — multi-receiver TDOA is a future slice). Validate at LOAD (the
# `_validate_cfar`/`_validate_geoloc` pattern), triggered by ESM-entity presence so a non-ESM
# scenario is untouched. Also BOUND the per-dwell candidate-pulse count (`_ESM_MAX_PULSES`,
# esm.jl): `T_dwell / min_PRI` can explode the histogram + wire frame, and a fat frame must be
# a clear authoring error, not a mystery slowdown (HANDOFF §1: no silent truncation).
function _validate_esm(world::World)
    n_emitter = 0; n_esm = 0
    for (_, e) in world.entities
        e.kind === :pulse_emitter && (n_emitter += 1)
        e.kind === :esm           && (n_esm      += 1)
    end
    (n_emitter == 0 && n_esm == 0) && return world       # not an ESM scenario
    n_emitter ≥ 2 ||
        error("a multi-emitter EW scenario needs ≥ 2 :pulse_emitter entities (got $n_emitter)")
    n_esm == 1 ||
        error("a multi-emitter EW scenario needs exactly one :esm (got $n_esm)")
    esm   = first(e for (_, e) in world.entities if e.kind === :esm)
    dwell = Float64(esm.comp[:t_dwell])
    total = 0
    for (_, e) in world.entities
        e.kind === :pulse_emitter || continue
        total += floor(Int, dwell / Float64(e.comp[:pri])) + 1     # candidate count over the dwell
    end
    total ≤ _ESM_MAX_PULSES ||
        error("ESM dwell too long: ~$total candidate pulses over the dwell exceeds the " *
              "$_ESM_MAX_PULSES bound (shorten t_dwell_us or raise the PRIs)")
    return world
end

# A GPS (slice 7) scenario needs a solvable constellation: ≥ 4 `:gps_satellite` (the 4×4
# trilateration solves for x/y/z + the receiver clock — fewer is rank-deficient) and exactly
# ONE `:gps_receiver` (single-receiver scope). Validate at LOAD (the `_validate_cfar`/
# `_validate_geoloc`/`_validate_esm` pattern), triggered by GPS-entity presence so a non-GPS
# scenario is untouched (a GPS scenario sets no required fidelity key — the error terms default
# `:off`, `:raim` defaults `:off`). NB the RAIM lesson needs OVER-determination (≥ 5 for a
# residual DOF); that is the RAIM scene's authoring responsibility (the loader enforces only the
# ≥ 4 solvability floor — a 4-satellite DOP scene is legal).
function _validate_gps(world::World)
    n_sat = 0; n_rx = 0
    for (_, e) in world.entities
        e.kind === :gps_satellite && (n_sat += 1)
        e.kind === :gps_receiver  && (n_rx  += 1)
    end
    (n_sat == 0 && n_rx == 0) && return world            # not a GPS scenario
    n_sat ≥ 4 ||
        error("a GPS scenario needs ≥ 4 :gps_satellite entities to solve x/y/z/clock (got $n_sat)")
    n_rx == 1 ||
        error("a GPS scenario needs exactly one :gps_receiver (got $n_rx)")
    return world
end

# A missile (slice 8) scenario needs at least one `:missile` to fly. Validate at LOAD (the
# `_validate_cfar`/…/`_validate_gps` pattern), triggered by missile-entity presence so a non-
# missile scenario is untouched (a missile scenario sets no REQUIRED fidelity key — `:integrator`
# defaults `:rk4`). The per-missile guards (positive mass/ρ, non-negative cd_area) live in the
# `:missile` build arm above (they throw during `_build_entity`), so this is the presence/count
# floor; the double-integration guard (BallisticMissile, NOT ConstantVelocity) is structural in
# the build arm and pinned by the loader test.
function _validate_missile(world::World)
    n_missile = 0; guided = false; n_target = 0
    for (_, e) in world.entities
        e.kind === :missile && (n_missile += 1)
        # A GUIDED missile is marked by the guidance comp keys (`:a_max` is set only in the
        # `guidance:` build arm) — it needs a `:target` to pursue.
        (e.kind === :missile && haskey(e.comp, :a_max)) && (guided = true)
        e.kind === :target && (n_target += 1)
    end
    n_missile == 0 && return world                       # not a missile scenario
    # Slice 9: a guided missile's Autopilot target-locks the nearest `:target` at runtime — so a
    # guided scenario must ship ≥ 1 (validated at LOAD, the `_validate_gps`/`_validate_esm` pattern,
    # so a mis-authored guided missile fails as a clear load error, not a runtime no-target coast).
    (guided && n_target < 1) &&
        error("a guided missile scenario needs ≥ 1 :target to pursue (got $n_target)")
    return world
end
