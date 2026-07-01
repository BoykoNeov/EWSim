# gps.jl — the GPS subsystems that light PHASES 2 + 3 + 4 of the tick contract in ONE
# pipeline (HANDOFF §3, §9 REUSE milestone, §10 item 7, slice-7 gate 2).
#
# This lights NO NEW phase — it reuses the build_env!→observe!→decide! shape a THIRD time
# (after the jammer→radar coupling, the DFSensor→Geolocator pair, and the emitter→ESM→
# deinterleaver chain). Its novelty is CROSS-DOMAIN CODE REUSE: the SAME `gauss_newton`
# scaffold that fixed a DF emitter (slice 5, N=2) trilaterates a GPS receiver here (N=4 —
# x, y, z, and the receiver clock bias c·b via `position_fix`), and the SAME `(HᵀH)⁻¹` DOP
# math that drew a DF error ellipse computes GPS dilution-of-precision. All the GPS-specific
# math (pseudorange model, error terms, the fix, DOP decomposition, RAIM) lives in the pure
# `gnss.jl` (gate 1); this file is only the SUBSYSTEMS (the esm.jl / geolocation.jl analog):
#
#   • GpsSatellite — phase-2 `build_env!`: publishes its ephemeris (`id`, `pos`, satellite
#                    `clock_err`, injected `fault_bias`) as a [`SatEphemeris`](@ref) record
#                    into `w.env[:gps_sats]`. RNG-free (the §3 build_env! contract).
#   • GpsReceiver  — phase-3 `observe!`, THE ONE DRAW SITE: reads every `env[:gps_sats]`
#                    record and, on a look-tick, generates + measures the pseudorange vector
#                    (deterministic geometry + toggled bias terms + the two drawn stochastic
#                    terms) into `w.env[:pseudoranges]`.
#   • GpsSolver    — phase-4 `decide!`: reads the pseudoranges, trilaterates + DOP + RAIM per
#                    the six fidelity keys ([`raim_solve`](@ref)/[`dop_components`](@ref)),
#                    and publishes the fix / DOP / RAIM telemetry.
#
# Phases 2→3→4 run in that fixed order in `tick!`, so a GpsSatellite's ephemeris is guaranteed
# visible to the receiver, and the receiver's pseudoranges to the solver, the SAME tick
# (correctness-by-construction, as the prior three couplings got). `env` is cleared + rebuilt
# each tick, so a stale fix can't leak. The §3 coupling done right — satellites→receiver and
# receiver→solver both THROUGH `env`, never a direct call — with the receiver + solver
# co-located on one entity for an independently-testable `env[:pseudoranges]` handoff.
#
# This file is included AFTER radar.jl (mirroring geolocation.jl/esm.jl) but has NO back-dep on
# radar's radar/jammer symbols: it reuses geometry.jl's `_finite`/`FINITE_CEIL` +
# geolocation.jl's `_finite_coord` (both in scope) and gnss.jl's pure GPS math (`_norm3`,
# `sat_az_el`, `pseudorange`, `iono_delay`/`tropo_delay`/`mp_scale`, `position_fix`,
# `dop_components`, `raim_solve`, `GPS_TOGGLE`/`RAIM_MODES`).
#
# NO DRAW-TOPOLOGY HAZARD (the slice-2/4/5/6 shape, NOT slice-3's `:cfar` guard): the receiver
# draws a FIXED count (`2·n_sats` — multipath then noise per CONFIGURED satellite, both
# UNCONDITIONAL) every look, independent of every fidelity key AND slider value. The five error
# toggles gate the CONTRIBUTION (0.0 when off), never the DRAW; the elevation mask, RAIM
# exclusion, and any live dropout are ALL POST-DRAW filters on which measurements enter the
# SOLVE — never gates on the draw. So all six keys (`iono`/`tropo`/`clock`/`multipath`/`noise` =
# GPS_TOGGLE, `raim` = RAIM_MODES) are introduce-safe AND toggle-bit-identical (the
# `:ep`/`:estimator`/`:deinterleaver` contract), and a non-GPS scenario is byte-identical to
# slices 1–6 (the radar/jammer/DF/ESM RNG path is untouched).
#
# NAMED APPROXIMATIONS (HANDOFF §1 — the pure ones live in gnss.jl's docstrings; the two here):
#   • RAIM threshold is an EMPIRICAL σ-multiple (gnss.jl route (iii)), NOT a χ²/Pfa quantile —
#     so the receiver comp key is `raim_threshold` (a dimensionless σ-multiple), NOT the plan
#     landmark's stale `pfa_raim` (which gate-1 rejected because exclude→odd-DOF needs an erf).
#   • Protection level is a crude `threshold · σ_range · PDOP` proxy of the HPL/VPL max-slope
#     bound (a readout, not asserted heavily) — named approximate.

# One satellite's published ephemeris — the `env[:gps_sats]` record (INTERNAL, like
# `EmitterParams`/`BearingRecord`/`JamContribution`). Carries the position (Vec3, SI metres),
# the SATELLITE clock error (`clock_err`, a per-SV constant bias — distinct from the receiver
# clock bias `c·b` the solver recovers, a common confusion), and the injected `fault_bias` (the
# spoof/SV-failure bias; always physically present in the pseudorange, gated by nothing — the
# RAIM rung only decides whether to detect/exclude it). Appended in the loader's sorted-id
# order; the receiver re-sorts defensively so the cross-satellite draw order is self-contained.
const SatEphemeris = @NamedTuple{id::Symbol, pos::Vec3, clock_err::Float64, fault_bias::Float64}

# The measured pseudorange vector the receiver hands the solver — the `env[:pseudoranges]`
# record (INTERNAL). Parallel arrays over the CONFIGURED satellites (sorted id): `sat_ids`,
# `positions` (the geometry the solver re-uses), `rho` (measured metres), and `visible` (the
# elevation-mask result — a POST-DRAW flag on which sats may enter the solve; RAIM may exclude
# further). Every configured satellite appears (the draw is unconditional); `visible` is the
# first filter the solver applies.
const PseudorangeSet = @NamedTuple{sat_ids::Vector{Symbol}, positions::Vector{Vec3},
                                   rho::Vector{Float64}, visible::Vector{Bool}}

# A σ_range floor (metres) applied at the CONSUMER so the RAIM statistic's `/σ` normalization
# can't divide by zero (σ_range is load-time static + loader-validated > 0, so this is a belt-
# and-braces guard, the `_SIGMA_THETA_FLOOR` precedent).
const _SIGMA_RANGE_FLOOR = 1.0e-6

# --- GpsSatellite: a phase-2 ephemeris publisher --------------------------------

"""
    GpsSatellite(id)

The GPS satellite `id` as a phase-2 `build_env!` subsystem — it publishes its ephemeris
([`SatEphemeris`](@ref): `pos`, satellite `clock_err`, injected `fault_bias`) into
`w.env[:gps_sats]`. RNG-free and order-independent (the §3 build_env! contract — the receiver
collects them). A `ConstantVelocity` mover (the loader pairs one) lets it drift to sweep DOP
good→bad (the gate-3 lesson). **Flat-local fictional satellite (named approximation, HANDOFF
§1): a far point source in the sim's SI inertial frame — NO ECEF/WGS84/orbit propagation.**
"""
struct GpsSatellite <: Subsystem
    id::Symbol
end

function build_env!(sat::GpsSatellite, w::World)
    e = w.entities[sat.id]
    sats = get!(() -> SatEphemeris[], w.env, :gps_sats)
    push!(sats, (id = sat.id, pos = e.pos,
                 clock_err  = Float64(get(e.comp, :clock_err_m, 0.0)),
                 fault_bias = Float64(get(e.comp, :fault_bias_m, 0.0))))
    return nothing
end

# --- GpsReceiver: the phase-3 one-draw-site -------------------------------------

# Generate + measure the pseudorange vector for ONE epoch — THE ONE DRAW SITE of the slice, in
# the EXACT §1-pinned order (the determinism golden rides on this; the sqrt(snr/2)/noise-then-
# signal bug class). Draw order, unconditional:
#   1. satellites in SORTED-ID order (sorted defensively so the order is self-contained, not
#      dependent on subsystem-assembly order);
#   2. per satellite draw MULTIPATH (`randn`) THEN NOISE (`randn`), BOTH UNCONDITIONALLY (so a
#      toggle gates the CONTRIBUTION, never the draw COUNT).
# Total draws = `2·n_sats`, FIXED by the CONFIGURED satellite count (independent of every
# fidelity key AND slider value). The five error terms are folded in per their toggle (iono/
# tropo/clock deterministic → no draw; multipath/noise use the drawn value iff on); the fault
# bias is ALWAYS added (deterministic physical spoof). The elevation `visible` flag is a
# POST-DRAW filter (computed here, applied by the solver). Pure of world state — takes plain
# params + an rng — so gate 2's exact-draw test replays it off a fresh `Xoshiro`.
function _draw_pseudoranges(sats::Vector{SatEphemeris}, rx::Vec3, cb::Float64,
                            σ_range::Float64, σ_mp::Float64, iono_z::Float64, tropo_z::Float64,
                            iono_on::Bool, tropo_on::Bool, clock_on::Bool,
                            mp_on::Bool, noise_on::Bool, mask_rad::Float64, rng::AbstractRNG)
    sorted = sort(sats, by = s -> s.id)                    # 1. satellites, sorted id
    n = length(sorted)
    ids = Vector{Symbol}(undef, n); positions = Vector{Vec3}(undef, n)
    rho = Vector{Float64}(undef, n); visible = Vector{Bool}(undef, n)
    @inbounds for (j, s) in enumerate(sorted)
        _, el      = sat_az_el(s.pos, rx)
        mp_draw    = randn(rng)                            # 2a. MULTIPATH (unconditional)
        noise_draw = randn(rng)                            # 2b. NOISE (unconditional)
        mp_term    = mp_on    ? mp_scale(el) * σ_mp * mp_draw : 0.0
        noise_term = noise_on ? σ_range * noise_draw          : 0.0
        iono_term  = iono_on  ? iono_delay(el, iono_z)        : 0.0
        tropo_term = tropo_on ? tropo_delay(el, tropo_z)      : 0.0
        clock_term = clock_on ? s.clock_err                   : 0.0
        rho[j] = pseudorange(s.pos, rx, cb; clock_err = clock_term, fault_bias = s.fault_bias,
                             iono = iono_term, tropo = tropo_term, mp = mp_term, noise = noise_term)
        ids[j] = s.id; positions[j] = s.pos; visible[j] = el ≥ mask_rad
    end
    return ids, positions, rho, visible
end

"""
    GpsReceiver(id; revisit_s = 0.0)

The GPS receiver `id` as a phase-3 `observe!` subsystem — THE ONE DRAW SITE. On a look-tick
(gated to `revisit_s` via `comp[:next_look_t]`, the radar/ESM cadence) it reads every
[`SatEphemeris`](@ref) in `w.env[:gps_sats]`, generates + measures the pseudorange vector
([`_draw_pseudoranges`](@ref), the §1-pinned draw order), and writes a [`PseudorangeSet`](@ref)
to `w.env[:pseudoranges]`. Between looks the last realization is republished (the readout never
blanks — the slice-1/2/3/6 pattern).

The receiver config lives in the `:gps_receiver` entity's `comp` bag (all load-time static —
they define the draw count / geometry): `:sigma_range_m` (ranging noise σ), `:sigma_mp_m`
(multipath σ), `:iono_zenith_m`/`:tropo_zenith_m` (the deterministic-delay magnitudes),
`:clock_bias_m` (the receiver's TRUE `c·b` the solver recovers), `:elevation_mask_deg` (the
POST-DRAW visibility mask), and `:raim_threshold` (read by the co-located solver). The five
error terms are toggled by the fidelity keys `iono/tropo/clock/multipath/noise` (default `:off`
absent — scenarios author the on-terms explicitly, keeping every key introduce-safe); the
draw is unconditional regardless (no draw-topology hazard).
"""
struct GpsReceiver <: Subsystem
    id::Symbol
    revisit_s::Float64
end
GpsReceiver(id::Symbol; revisit_s::Real = 0.0) = GpsReceiver(id, Float64(revisit_s))

function observe!(rx::GpsReceiver, w::World)
    e = w.entities[rx.id]
    c = e.comp
    is_look = w.t + 1e-12 ≥ get(c, :next_look_t, 0.0)
    if is_look
        σ_range = max(Float64(get(c, :sigma_range_m, 3.0)), 0.0)
        σ_mp    = max(Float64(get(c, :sigma_mp_m, 0.0)), 0.0)
        iono_z  = Float64(get(c, :iono_zenith_m, 0.0))
        tropo_z = Float64(get(c, :tropo_zenith_m, 0.0))
        cb      = Float64(get(c, :clock_bias_m, 0.0))
        mask    = deg2rad(Float64(get(c, :elevation_mask_deg, 0.0)))
        iono_on  = get(w.fidelity, :iono, :off)      === :on
        tropo_on = get(w.fidelity, :tropo, :off)     === :on
        clock_on = get(w.fidelity, :clock, :off)     === :on
        mp_on    = get(w.fidelity, :multipath, :off) === :on
        noise_on = get(w.fidelity, :noise, :off)     === :on
        sats = collect(SatEphemeris, get(w.env, :gps_sats, SatEphemeris[]))
        ids, positions, rho, vis = _draw_pseudoranges(sats, e.pos, cb, σ_range, σ_mp, iono_z,
            tropo_z, iono_on, tropo_on, clock_on, mp_on, noise_on, mask, w.rng)
        c[:pr_ids] = ids; c[:pr_pos] = positions; c[:pr_rho] = rho; c[:pr_vis] = vis
        c[:next_look_t] = get(c, :next_look_t, 0.0) + rx.revisit_s
    end
    if haskey(c, :pr_rho)                              # republish (readout never blanks)
        w.env[:pseudoranges] = PseudorangeSet((c[:pr_ids]::Vector{Symbol},
            c[:pr_pos]::Vector{Vec3}, c[:pr_rho]::Vector{Float64}, c[:pr_vis]::Vector{Bool}))
    end
    return nothing
end

# --- GpsSolver: a phase-4 fusion node -------------------------------------------

"""
    GpsSolver(id)

The GPS solver `id` (co-located on the receiver entity) as a phase-4 `decide!` subsystem —
reads `w.env[:pseudoranges]` (the receiver's phase-3 output), filters to the ELEVATION-VISIBLE
satellites, and runs the RAIM-aware fix ([`raim_solve`](@ref), dispatching on the `:raim`
fidelity) which internally trilaterates ([`position_fix`](@ref) at N=4 — the §9 shared
`gauss_newton`), computes the DOP matrix `Q = (HᵀH)⁻¹`, and detects/excludes a faulted
satellite. Publishes the fix / DOP / RAIM telemetry:

  • SCALARS (the verifier asserts on these): `pos_err_m` (‖fix − receiver truth‖),
    `fix_x/.fix_y/.fix_z` (signed), `clock_bias_ns` (the solved `c·b` in ns — the §1
    metres→time boundary), `gdop/.pdop/.hdop/.vdop/.tdop` ([`dop_components`](@ref)),
    `raim_stat`, `raim_flag` (0/1), `n_sats_used`, `fault_sat` (the excluded satellite's
    CONFIGURED index, 0 if none), `protection_level_m`.
  • DISPLAY ARRAYS (never asserted — the slice-6 rule): `sat_az_deg/.sat_el_deg` (the sky
    plot), `sat_resid_m` (the RAIM residual bars), `sat_used` (Bool per configured satellite —
    in-solve / elevation-masked / RAIM-excluded).

All scalars are clamped finite ([`_finite`](@ref)/[`_finite_coord`](@ref), ceiling
[`FINITE_CEIL`](@ref)) so a singular / under-determined geometry (< 4 visible satellites, a
coplanar/clustered constellation, a RAIM exclusion into < 4) ships a huge-but-finite value,
never Inf/NaN — and never throws the tick (the "a live config can't crash a tick" watch-item).
DOP is UNIT-variance geometry (σ-invariant — the slice-5 σθ-trap on the GPS surface); the
pseudorange σ enters `pos_err ≈ PDOP·σ_range` at the readout, never inside `Q`. Publishes
nothing if no pseudorange set exists (a GPS-free world never writes `env[:pseudoranges]`).
"""
struct GpsSolver <: Subsystem
    id::Symbol
end

function decide!(g::GpsSolver, w::World)
    prs = get(w.env, :pseudoranges, nothing)
    prs === nothing && return nothing
    rx = w.entities[g.id]
    c  = rx.comp

    σ_range = max(Float64(get(c, :sigma_range_m, 3.0)), _SIGMA_RANGE_FLOOR)
    thr     = Float64(get(c, :raim_threshold, 5.0))
    raim    = get(w.fidelity, :raim, :off)
    raim in RAIM_MODES ||
        error("GpsSolver: raim fidelity :$raim not implemented ($(join(RAIM_MODES, " | ")))")

    ids = prs.sat_ids; positions = prs.positions; rho = prs.rho; vis = prs.visible
    n_cfg   = length(ids)
    vis_idx = [j for j in 1:n_cfg if vis[j]]              # POST-DRAW: only visible sats solve

    res = raim_solve(positions[vis_idx], rho[vis_idx], σ_range; mode = raim, threshold = thr)
    fix = res.pos; cb = res.cb
    gd, pd, hd, vd, td = dop_components(res.Q; singular = res.singular)

    # Map raim_solve's results (indexed into the VISIBLE subset) back to CONFIGURED indices, so
    # `sat_used`/`fault_sat` line up with the display arrays. With an elevation mask
    # `vis_idx ≠ 1:n_cfg`, so this scatter + `fault_sat = vis_idx[res.fault_sat]` are the one
    # genuinely subtle correctness spot — pinned by a masked-AND-excluded test (advisor #2).
    sat_used = fill(false, n_cfg)
    for (k, j) in enumerate(vis_idx)
        sat_used[j] = res.used[k]
    end
    fault_cfg = res.fault_sat == 0 ? 0 : vis_idx[res.fault_sat]

    truth = rx.pos
    err   = _norm3(fix - truth)
    # Residuals per CONFIGURED satellite against the final fix (masked/excluded sats too, so the
    # RAIM bar chart shows every satellite's residual). az/el from truth for the sky plot.
    resid = Float64[rho[j] - (_norm3(positions[j] - fix) + cb) for j in 1:n_cfg]
    az = Float64[rad2deg(sat_az_el(positions[j], truth)[1]) for j in 1:n_cfg]
    el = Float64[rad2deg(sat_az_el(positions[j], truth)[2]) for j in 1:n_cfg]
    pl = thr * σ_range * pd                                # crude HPL/VPL proxy (named approx)

    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(g.id)
    tel["$sid.pos_err_m"]         = _finite(err)
    tel["$sid.fix_x"]             = _finite_coord(fix[1])
    tel["$sid.fix_y"]             = _finite_coord(fix[2])
    tel["$sid.fix_z"]             = _finite_coord(fix[3])
    tel["$sid.clock_bias_ns"]     = _finite_coord(cb / C_LIGHT * 1.0e9)   # c·b metres → ns
    tel["$sid.gdop"]              = _finite(gd)
    tel["$sid.pdop"]              = _finite(pd)
    tel["$sid.hdop"]              = _finite(hd)
    tel["$sid.vdop"]              = _finite(vd)
    tel["$sid.tdop"]              = _finite(td)
    tel["$sid.raim_stat"]         = _finite(res.stat)
    tel["$sid.raim_flag"]         = res.flag ? 1 : 0
    tel["$sid.n_sats_used"]       = count(sat_used)
    tel["$sid.fault_sat"]         = fault_cfg
    tel["$sid.protection_level_m"] = _finite(pl)
    tel["$sid.sat_az_deg"]        = az                    # variable, display only
    tel["$sid.sat_el_deg"]        = el                    # variable, display only
    tel["$sid.sat_resid_m"]       = _finite_coord.(resid) # variable, display only (signed)
    tel["$sid.sat_used"]          = sat_used              # variable, display only
    return nothing
end
