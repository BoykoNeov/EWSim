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
        comp[:rcs_m2] = _f64(ent["target"]["rcs_m2"])
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
    else
        error("unknown entity kind :$kind for '$id' (knows :radar, :target, :clutter, " *
              ":jammer, :emitter, :df_sensor, :df_station, :pulse_emitter, :esm)")
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

    _validate_cfar(world)
    _validate_geoloc(world)
    _validate_esm(world)
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
