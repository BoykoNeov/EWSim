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
    # Slice 30: an OPTIONAL CROSSING-SPEED hold — a `comp[:cross_speed_mps]` key (a declared knob
    # in the envelope scenario) pins the mover's vel_y so a LIVE slider can fly the ENGAGEMENT
    # itself: the crossing speed sets the lead angle the seeker holds, hence the look angle at
    # which the radome's slope curve is sampled (slice 28), hence the residual that closes slice
    # 26's parasitic loop. The engagement becomes an AXIS the client can drive — which is what
    # turns slice 26's one-sidedness observation into a design rule over an ENVELOPE.
    # PRESENCE-gated (the `:alt_hold_m` / `:af_cma` precedent): no key → the `pos` line below is
    # the whole mover, bit-identical for every slice-1..29 scenario. Any finite value is safe at
    # the consumer (a live slider can't crash a tick — convention 5); vel_x/vel_z stay as authored.
    #
    # ⚠⚠ THE PIN GOES **BEFORE** THE INTEGRATE LINE, AND THIS IS NOT WHERE `alt_hold_m` PUTS IT
    # (advisor, load-bearing — `docs/plans/slice30.md` gate 1). `alt_hold_m` pins a POSITION: the
    # pin is idempotent AND is itself the observable, so after the update is correct. This pins a
    # VELOCITY that the `pos` update on the same tick has already consumed — pinned after, the
    # first step of every run advances on the AUTHORED vel_y and the knob is dead for one tick.
    # ⚠ An EQUAL-VALUE byte-identity test cannot see that bug (both orders agree when the pin
    # equals the authored value); only a DISAGREEING pair can (test_radar.jl, "THE ORDERING").
    #
    # ⚠ SCOPE, CHECKED (advisor): the loader mints this key in the `:target` arm ONLY, but this
    # mover is also mounted by `:decoy`/`:jammer`/`:emitter`/`:df_sensor`/`:df_station`/
    # `:pulse_emitter`/`:esm`/`:gps_satellite`, and the pin fires on ANY comp bag carrying it.
    # No guard here on purpose: no loader arm can mint it on those kinds, so the path is
    # unreachable — and `alt_hold_m` below has the identical shape and has shipped since slice 18.
    # (The one soft edge: `_parse_knobs` only checks that entity+key EXIST, so a knob aimed at a
    # key no arm mints is a load error by absence, not by kind.)
    haskey(e.comp, :cross_speed_mps) &&
        (e.vel = Vec3(e.vel[1], Float64(e.comp[:cross_speed_mps]), e.vel[3]))
    e.pos = e.pos + e.vel * dt
    # Slice 18: an OPTIONAL altitude hold — a `comp[:alt_hold_m]` key (a declared knob in a
    # terrain scenario) pins the mover's z so a LIVE slider can fly the target up/down through
    # the terrain shadow (the lesson lever; a pos component is not knob-addressable, this key
    # is). PRESENCE-gated (the `:af_cma` precedent): no key → the two lines above are the
    # whole mover, bit-identical for every slice-1..17 scenario. Any finite value is safe at
    # the consumer (a live slider can't crash a tick — convention 5); vel_z stays whatever
    # was authored (a held z with vel_z = 0 is the natural authoring).
    haskey(e.comp, :alt_hold_m) &&
        (e.pos = Vec3(e.pos[1], e.pos[2], Float64(e.comp[:alt_hold_m])))
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

# The authored heightfield record off a `:terrain` entity's comp (the `_radar_params`
# precedent). Hills live as FLAT SCALAR keys `hillK_a/x/y/s` + `:n_hills` (loader-
# validated complete per index) so the knob machinery could address one later
# (hill-knob-with-grid-refresh is a named slice-18 deferral — terrain is LOAD-STATIC).
function _terrain_params(c::AbstractDict)
    n = Int(get(c, :n_hills, 0))
    TerrainParams(h0 = Float64(get(c, :h0, 0.0)),
                  a     = [Float64(c[Symbol("hill$(k)_a")]) for k in 1:n],
                  cx    = [Float64(c[Symbol("hill$(k)_x")]) for k in 1:n],
                  cy    = [Float64(c[Symbol("hill$(k)_y")]) for k in 1:n],
                  sigma = [Float64(c[Symbol("hill$(k)_s")]) for k in 1:n],
                  los_step_m = Float64(get(c, :los_step_m, 25.0)))
end

# The world's (single — loader-enforced) `:terrain` entity's heightfield, or `nothing`.
# Consulted ONLY under the `:terrain` propagation rung, so every other rung's code path
# is textually untouched (byte-identity for slices 1–17 by construction).
function _world_terrain(w::World)
    ids = sort!(Symbol[id for (id, e) in w.entities if e.kind === :terrain])
    isempty(ids) && return nothing
    return _terrain_params(w.entities[ids[1]].comp)
end

# The propagation-fidelity rungs the radar dispatch knows. SINGLE source of truth for
# both the `_target_snr` dispatch (below) and the server's `set_fidelity` validation
# (server.jl) — they must not drift, or the wire would accept a value that crashes
# `tick!` inside `observe!` (HANDOFF §10, slice2 step 2). `:terrain` (slice 18) is the
# THIRD rung: free-space link budget + a hard terrain-shadow LOS mask (terrain.jl) —
# class 4a exactly like the first two (the mask gates only `(snr, visible)`; the
# `detect_once` draw stays unconditional), introduce-safe and live-settable with NO
# `set_fidelity` guard. On a world with NO `:terrain` entity the rung is bit-exact
# `:free_space` (the slice-4 mismatched-EP no-op precedent — a live toggle on any
# slice-1..17 scenario can neither crash a tick nor move a byte).
const PROPAGATION_MODES = (:free_space, :two_ray, :terrain)

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
# `:seeker_axes` (slice-25 two-angle seeker; rungs `SEEKER_AXES_MODES` from estimation.jl) selects the
# seeker's measurement DIMENSIONALITY — `:az_el` keeps the LOS rate's out-of-plane component, the foil
# `:pitch_plane` discards it. Class 4a WITHIN a 2-draw host: BOTH rungs draw exactly 2 randn/tick (the
# foil DISCARDS the azimuth sample — convention 3, "gate the value, never the draw"), so a live toggle
# keeps the RNG in lockstep and needs NO `set_fidelity` guard, UNLIKE `:cfar`/`:scan`. The 2-draw
# topology is gated on the SCENARIO's host marker (`:seek_two_angle`, from the `seeker:` block) and
# NOT on this key, which is what makes INTRODUCING it on a slice-11/13 wire inert rather than a
# replay-desyncing draw flip (the P11 invariant, pinned in `test_missile.jl`).
# `:airframe` (slice-17 α→lift→γ coupling; rungs `AIRFRAME_MODES` from airframe.jl) is a NEW fidelity
# KEY (contrast slice-15's `:fin`, a new RUNG of `:autopilot`) — also class 4c (physics-changing, no
# RNG). `:point_mass↔:pitch_coupled` CHANGES the trajectory (α generates a body lift that bends the
# path) but the scenario is truth-fed open-loop with NO seeker → "draw-count invariance" is VACUOUS
# and there is NO draw-topology to flip → introduce-SAFE, live-settable, NO `set_fidelity` guard (the
# `:integrator`/`:autopilot`/`:apn`/`:cooperation` precedent). Byte-identity for slices 1–16 is by
# CONSTRUCTION: the coupled `integrate!` branch is unreachable without BOTH `:af_cma` AND
# `:airframe===:pitch_coupled` (default `:point_mass`). Referencing AIRFRAME_MODES is one-list-no-drift.
const LIVE_FIDELITY_MODES = (propagation = PROPAGATION_MODES, cfar = CFAR_MODES,
                             ep = EP_MODES, estimator = ESTIMATOR_MODES,
                             deinterleaver = DEINTERLEAVER_MODES,
                             iono = GPS_TOGGLE, tropo = GPS_TOGGLE, clock = GPS_TOGGLE,
                             multipath = GPS_TOGGLE, noise = GPS_TOGGLE, raim = RAIM_MODES,
                             integrator = INTEGRATOR_MODES, autopilot = AUTOPILOT_MODES,
                             guidance = GUIDANCE_MODES, seeker = SEEKER_MODES,
                             seeker_axes = SEEKER_AXES_MODES,
                             discrimination = DISCRIMINATION_MODES,
                             cooperation = COOPERATION_MODES,
                             airframe = AIRFRAME_MODES,
                             atmosphere = ATMOSPHERE_MODES,
                             steering = STEERING_MODES,
                             seeker_head = SEEKER_HEAD_MODES,
                             head_servo = HEAD_SERVO_MODES,
                             seeker_detect = SEEKER_DETECT_MODES)

# A perfect null (F⁴=0, even above the horizon), an antenna on the reflecting plane
# (h→0), or a below-horizon mask all drive SNR→0, and `lin2db(0) = -Inf` would poison the
# JSON state frame (the slice-2 watch-item, same class as the slice-1 %g bug). Floor the
# dB readout so the wire never carries Inf/NaN; the floor sits far below any real
# free-space reading, so it is invisible except on a genuine null/mask.
const _SNR_DB_FLOOR = -120.0
_snr_db_wire(snr_lin::Real) = snr_lin > 0 ? max(lin2db(snr_lin), _SNR_DB_FLOOR) : _SNR_DB_FLOOR

"""
    _aspect_view_info(w::World) -> Union{Nothing, Dict}

The slice-49 view marker — the `terrain_grid` / `airframe_view` handshake-once pattern. Raised when
ANY target carries a `:rcs_fineness`, so the client draws the aspect block (which way the target is
pointing, and what it costs) instead of the plain radar view. `nothing` on every slice-1..48
scenario, where the keys simply do not appear.

⚠ **GATED ON THE COMP KEY, NOT ON A FIDELITY** — slice 38/46/47/48's choice and for their reason.
There is no `aspect` rung to gate on and there deliberately is not one: "no aspect at all" is
reachable from the SLIDER's own floor (`rcs_fineness = 1`, a sphere), so a rung would duplicate a
slider position, and the shape is what an author writes.

⚠⚠ **THE MARKER-HOLE CHECK COMES BACK POSITIVE.** Without it a slice-49 wire is, to the client,
a slice-2 wire: it would draw the two-ray propagation view and its fidelity button would offer
`free_space ↔ two_ray` — a lesson about MULTIPATH lobing, on a scenario whose target vanishes for
forty seconds for a completely different reason. Two mechanisms in one view is what convention 9
exists to prevent, and the drop-out would read as a propagation null. The marker also carries the
target id so the HUD can name the entity whose aspect it is quoting — an aspect belongs to a
target-observer PAIR, and a HUD that said "aspect 25°" with no subject would be the ~13th
stale-readout of this family.
"""
function _aspect_view_info(w::World)
    tgts = sort!(Symbol[id for (id, e) in w.entities
                        if e.kind === :target && haskey(e.comp, :rcs_fineness)])
    isempty(tgts) && return nothing
    radars = sort!(Symbol[id for (id, e) in w.entities if e.kind === :radar])
    # ⚠⚠ SLICE 50 — THE OBSERVER IS **REQUIRED**, AND IT WAS OPTIONAL HERE UNTIL A WIRE EXISTED THAT
    # COULD REACH THE GAP. As first written this returned `aspect_view = true` with the observer key
    # simply omitted when no radar was present. On every slice-1..49 scenario that arm is
    # unreachable (the only shaped target ships beside a radar), so it read as harmless defensive
    # code — but slice 50 authors a shaped target with a MISSILE and no radar, and the client keys
    # EVERY line of the aspect block off `_aspect_observer`. Empty-string observer ⇒ every
    # `.get(key, default)` returns its default ⇒ the block renders "HOLDING IT: 90° broadside /
    # echo 0 m² — 0.0 dB below broadside / range 0.0 km  Pd 0.00  SEEN" over a target turning
    # nose-on at 3 g and seconds from being lost. Six fabricated numbers, no failing test, and the
    # two loudest of them asserting the exact opposite of the lesson.
    #
    # ⭐ THE MARKER IS THE PAIR, SO HALF A PAIR IS NOT A MARKER. A radarless shaped target still has
    # an aspect — it simply has none THIS view can quote, and the honest answer is to leave the
    # handshake silent so the client keeps its own view. `missile.jl`'s `seeker_aspect_view` takes
    # the missile-side wire, off the missile's own `target_aspect_deg` / `rcs_eff_m2`.
    # ⚠ BYTE-IDENTICAL ON EVERY SHIPPED WIRE: `slice49_aspect.yaml` is the only scenario that raises
    # this at all and it authors `radar1`, so the returned Dict is unchanged there, key for key.
    isempty(radars) && return nothing
    return Dict{Symbol,Any}(:aspect_view => true, :aspect_target => String(tgts[1]),
                            :aspect_observer => String(radars[1]))
end

"""
    _tail_view_info(w::World) -> Union{Nothing, Dict}

⭐⭐ **THE SLICE-53 VIEW MARKER** — the `terrain_grid` / `airframe_view` / `aspect_view`
handshake-once pattern, and the 15th of the family. Raised when a target carries a
`:rcs_tail_gain` **and** a radar carries a `:track_drop_looks`. `nothing` on every slice-1..52
scenario, where the keys simply do not appear.

⚠⚠ **THE MARKER IS THE PAIR, SO HALF A PAIR IS NOT A MARKER** — slice 50 forced exactly that onto
[`_aspect_view_info`](@ref) above, and the argument transfers without a change of a word. This
block's every line is either a property of the TARGET's rear hemisphere (`rcs_tail_gain`, the aspect
readouts) or a property of the RADAR's give-up rule (`track_*`), and the headline `track_asym_m` is
the two multiplied together. A shaped-and-tail-lobed target with no tracking radar has an asymmetry;
it simply has none THIS view can quote, and the honest answer is to leave the handshake silent so
the client keeps whatever view it had.

⚠ **GATED ON THE COMP KEYS, NOT ON A FIDELITY**, for slice 38/46/47/48/49's reason: there is no tail
rung to gate on and there deliberately is not one — "no tail lobe at all" is reachable from the
SLIDER's own floor (`G` = 1), so a rung would duplicate a slider position.

⭐ **AND THE GATE MUST NOT BE THE LESSON'S NULL** (slice 50: the lesson's NULL and a dead
instrument's DEFAULT must not read the same). The showcase's headline drag is `G` = 20 → 1, and
`set_param` writes the comp bag IN PLACE — the key stays PRESENT at every slider position — so this
marker rides through the null instead of blanking on exactly the arm that proves it. Gating on the
VALUE (`> 1`) would have gone dark there; gating on PRESENCE does not.

⚠ **HUD ONLY — THE BUTTON STAYS SLICE 49's**, the `_s52_view` / `_seeker_detect_view` posture. A
slice-53 wire authors an `:rcs_fineness` too, so `_aspect_view_info` raises alongside this and the
client's `_setup_spatial_fid_btn` already drops the `free_space ↔ two_ray` toggle on its branch —
which is the correct drop here for slice 49's exact reason (multipath is a SECOND way for a target
to vanish, on a scenario about a third). What this marker takes from `aspect_view` is the HUD block
and slice 49's own gauge: the longest closing loss run is a DURATION on the inbound leg, and on this
wire it would accumulate all pass under a label that belongs to a different slice.
"""
function _tail_view_info(w::World)
    tgts = sort!(Symbol[id for (id, e) in w.entities
                        if e.kind === :target && haskey(e.comp, :rcs_tail_gain)])
    isempty(tgts) && return nothing
    radars = sort!(Symbol[id for (id, e) in w.entities
                          if e.kind === :radar && haskey(e.comp, :track_drop_looks)])
    isempty(radars) && return nothing
    return Dict{Symbol,Any}(:tail_view => true, :tail_target => String(tgts[1]),
                            :tail_observer => String(radars[1]))
end

"""
    _giveup_view_info(w::World) -> Union{Nothing, Dict}

⭐⭐ **THE SLICE-54 VIEW MARKER** — the 16th of the `terrain_grid` / `aspect_view` / `tail_view`
handshake-once family. Raised when a radar authors a **`:track_sweep_max` ≥ 1**, i.e. when the wire
actually ships a NET-vs-patience CURVE for the client to draw. `nothing` on every slice-1…53
scenario, where the key does not appear.

⚠⚠ **THE GATE IS THE AUTHOR'S KEY AND NOT THE SLIDER'S VALUE**, which is the standing rule this
family keeps re-learning (slice 53: *gate a view marker on the author's KEY, never the slider's
VALUE*). This slice's slider is `track_drop_looks`, and it is dragged across its WHOLE domain as the
lesson — including to 1, the null. A marker gated on any function of that value would go dark on
exactly the arm the user is meant to compare against. `track_sweep_max` is authored once and never
moves, so the marker rides through every slider position.

⚠ **AND THE MARKER SEPARATES WIRES THAT DIFFER ONLY BY THE SLIDER** — the other half of the same
rule. `slice54_giveup.yaml` and `slice54_giveup_clean.yaml` differ ONLY in `pfa`; both raise this
marker and both draw the same block, because the lesson is *the curve moved*, not *a different
instrument appeared*. The block's job is to make the two curves comparable, so it must be the SAME
block. ⇒ the marker names the RADAR, and the HUD reads the curve off the wire.

⚠ **HUD ONLY — IT TAKES NO BUTTON.** A slice-54 wire is a `:cfar` scenario, so the client's CFAR
profile view already owns the display and its own fidelity button; this marker adds the tracker
block beside it and changes nothing else. ⚠ It must NOT be gated on `:track_drop_looks` alone: slice
53's point-path wire authors that key too, and would raise a block whose curve does not exist.
"""
function _giveup_view_info(w::World)
    radars = sort!(Symbol[id for (id, e) in w.entities
                          if e.kind === :radar && Int(get(e.comp, :track_sweep_max, 0)) ≥ 1])
    isempty(radars) && return nothing
    return Dict{Symbol,Any}(:giveup_view => true, :giveup_observer => String(radars[1]))
end

"""
    _effective_rcs(tgt::Entity, obs_pos::Vec3) -> Float64   (m²)

**THE ONE PLACE ASPECT IS APPLIED** (slice 49). The target's radar cross-section as seen from
`obs_pos`: its authored `:rcs_m2` when it has no shape, and [`rcs_aspect`](@ref) of that value at
[`aspect_angle`](@ref) when it carries a `:rcs_fineness`.

⚠⚠ **THERE IS EXACTLY ONE OF THESE, AND THAT IS THE POINT.** `missile.jl`'s seeker horizon calls
THIS function rather than repeating the two lines, because `missile.jl:2624`'s own standing comment
says a seeker-side RCS copy *"would give one target two RCS numbers that can silently disagree
(convention 7's exact failure)"* — and an aspect model applied at one consumer and not the other is
that failure exactly. It lives in `radar.jl` (not a §9 pure lib) because it consumes an `Entity`;
the PHYSICS it calls is pure and lives in `rf.jl` / `frames.jl`.

⚠ **THE ABSENT KEY IS AN EARLY RETURN, NOT `F = 1`.** A target with no `:rcs_fineness` returns
`comp[:rcs_m2]` on the line it has returned it on since slice 1 — no `sincos`, no division, no
rounding — so every slice 1–48 wire is byte-identical. Routing through `rcs_aspect` with `F = 1`
would be algebraically equal and NOT bit-equal (`sin²+cos²` is not always exactly 1.0), which is a
distinction convention 2 makes load-bearing.

⚠ Clamped at the CONSUMER (convention 5): a live slider can drive `:rcs_fineness` to a value
`rcs_aspect` would throw a `DomainError` on, and a throw inside `observe!` silently drops the
client's connection. The floor ships a huge-but-finite σ (convention 6), never an ±Inf.

⭐ **SLICE 53 — THE TAIL LOBE ENTERS HERE AND NOWHERE ELSE, AND IT IS AN UNCONDITIONAL MULTIPLY,
NOT A SECOND PRESENCE GATE.** `:rcs_tail_gain` is read with `get(…, 1.0)` INSIDE the shaped branch,
so there is exactly one new expression and no new call site. Three deliberate consequences:

* A target with no `:rcs_fineness` takes the early return above and never sees the gain — which is
  why the LOADER refuses a tail gain authored without a fineness (`scenario.jl`). ⚠⚠ Gate 0's P6a
  found the pair of defects that makes this load-time refusal load-bearing: an unknown `target:`
  key is DROPPED silently, so "author it and watch nothing happen" is the `speed` (19) /
  handover-bias (36) dead-knob failure wearing a legitimate-looking run.
* A shaped target with no tail gain gets `G` = 1.0, whose bracket is exactly 1.0, so slice 49's and
  50's wires are bit-identical (measured, gate 0 P5 — all three nulls exact, no extra branch).
* `G` is FLOORED, not ceilinged: a live slider dragged to 0 or below would throw a `DomainError`
  inside `observe!`, so it is clamped to a tiny positive; there is no upper clamp because every
  large-but-FINITE `G` is crash-safe and just paints a brighter tail (the `:rcs_fineness` posture,
  and convention 6 is satisfied by finiteness, not by smallness). ⚠ A live slider carrying a
  literal `Inf` is a PRE-EXISTING hazard of this readout and NOT this key's: `:rcs_fineness` = Inf
  already drives `best_rcs` → 0 and ships `rcs_loss_db` = +Inf below. `set_param` does not clamp to
  the knob's declared min/max, so the guard is the same one it has always been — the authored
  values are load-validated finite, and the shipped client only sends what its slider spans.
"""
function _effective_rcs(tgt::Entity, obs_pos::Vec3)
    haskey(tgt.comp, :rcs_fineness) || return tgt.comp[:rcs_m2]     # ← the slices 1–48 line
    σ = max(Float64(tgt.comp[:rcs_m2]), 1.0e-12)
    F = max(Float64(tgt.comp[:rcs_fineness]), 1.0e-9)
    G = max(Float64(get(tgt.comp, :rcs_tail_gain, 1.0)), 1.0e-9)
    return rcs_aspect(σ, F, aspect_angle(tgt.pos, tgt.vel, obs_pos); tail_gain = G)
end

"""
    _mark_track_dirty!(w) -> nothing

⚠⚠ **A LIVE DRAG INVALIDATES A LATCHED MEASUREMENT AS A RESET DOES** (slice 49's rule, slice 50's
remedy). Called from `set_param` — the ONE place a knob moves mid-run — and it marks every
tracking radar so the next look throws away edges that were declared under the OLD setting.

⭐ **WHY THIS IS IN THE CORE AND NOT IN THE HUD, WHICH IS WHERE SLICES 49 AND 50 PUT IT.** Their
latches were computed IN the client from wire values, so a client-side disarm was the whole fix.
This latch lives in the core and SHIPS AS A WIRE KEY — and a gate-3 verifier reads the wire, not
the HUD. A stale `track_asym_m` would be read as a live measurement by a headless proof that never
draws a pixel, which is the green-but-false proof this arc has paid for before.

⚠ **BOTH EDGES GO, AND THE CONSERVATISM IS DELIBERATE.** For THIS slice's knob the gain edge would
in fact be unchanged (the tail lobe is exactly 1.0 on the forward hemisphere — gate 0 §2.15 §0
measured `max |in_G − in_1|` = 0.000000e+00 over 824 flights), but the tracker is generic and is
not told WHICH knob moved: `pt_w`, `pfa` or an `rcs_m2` would move both. An instrument may refuse
to show a number it can no longer stand behind; it may never show one measured on a different
configuration.

⚠ A drag past closest approach therefore ends the pass's measurement for good — the gain edge
cannot be re-declared on the outbound leg — and the honest state is slice 50's "Reset to measure",
not a re-armed number. `track_pass_dirty` carries that on the wire; only a Reset clears it, because
`reset` reloads the scenario and the comp bag with it.
"""
function _mark_track_dirty!(w::World)
    for (_, e) in w.entities
        e.kind === :radar && haskey(e.comp, :track_drop_looks) && (e.comp[:trk_dirty] = true)
    end
    return nothing
end

"""
    _track_look!(radar, detected, R, rdot) -> nothing

⭐⭐ **SLICE 53 gate 2 — THE TRACKER, AND IT IS A MODEL, NOT A READOUT.** One look of a give-up
track over the strongest target, plus the TWO EDGES of a single pass that the slice's gauge is the
difference of:

* **the GAIN edge** — the range at which the track that is running at closest approach was first
  opened, i.e. *how far out you first got it while it was coming in*;
* **the LOSS edge** — the range at the last detection before the track is finally given up on the
  way out, i.e. *how far out you were still following it home*;
* and their difference, **the pass's ASYMMETRY**. With a fore/aft SYMMETRIC cross-section the two
  legs present the identical σ at equal range, so the difference is fading noise about zero; a TAIL
  LOBE (`rcs_tail_gain`) moves the outbound edge and nothing else.

⚠⚠ **WHY THIS IS IN THE CORE AND NOT IN THE HUD.** The rule is counted in LOOKS. The client sees
FRAMES (`emit_every` = 16 ⇒ ~6 frames per look at `revisit_s` = 0.1), and "3 frames without a
detection" is not "3 missed looks" — it is a different rule that changes meaning with the emit
cadence. That is gate-0 §2.14's own trap (a rule counted in samples silently changes meaning when
the sample rate changes), and the client also has no look-boundary marker to recover the looks
from. The gauge, the verifier's number and the HUD's number are therefore ONE quantity computed
ONCE, here (conventions 7 and 13).

⚠ **THE LEG IS THE RANGE RATE's SIGN, AND `trk_past_cpa` IS A LATCH — A NAMED APPROXIMATION.** The
pass is assumed to have ONE closest approach: the first look with `rdot ≥ 0` ends the inbound leg
for good. A target that closes, opens and closes again (slice 49's orbiting wire is exactly that)
would keep the FIRST crossing, so this instrument belongs on a straight pass and the scenario that
authors the key is the thing that guarantees it. ⭐ The CPA look itself belongs to BOTH legs — it
can open a track (gain) and it can be the first detection of the outbound run (loss) — which is
what the offline gate-0 rule did by splitting `looks[1:k]` / `looks[k:end]` on a SHARED index `k`.

⚠ **THE LOSS LATCH IS ARMED BY A POST-CPA DETECTION, NOT BY THE DROP ALONE.** A gap that STRADDLES
closest approach would otherwise latch a "loss" whose last detection was on the way IN — a number
from the wrong leg. The offline rule skipped such a gap structurally (it is in neither array); here
it is skipped by `trk_post_cpa_det`, and the next run's end is latched instead.

⚠ **NOT LATCHING IS A REAL STATE.** If the flight ends while the track is still alive there is no
loss edge, and the key is simply ABSENT from the wire rather than shipped as a sentinel that reads
like a measurement — `track_asym_m` likewise ships only when BOTH edges exist, because 0.0 is a
legitimate value of an asymmetry (it is the null!) and a defaulted zero would read as "perfectly
symmetric" on an instrument that has not finished (slice 50: presence decides).
"""
function _track_look!(radar::Entity, detected::Bool, R::Float64, rdot::Float64)
    n_drop = Int(radar.comp[:track_drop_looks])
    # ⚠⚠ THE DRAG, CONSUMED HERE (see `_mark_track_dirty!`). Both EDGES and the loss latch's arming
    # go; the live state (alive / misses / look / leg) does NOT, because it describes the tick and
    # not a past measurement — which is slice 50's own split, one instrument over: the latch belongs
    # to the setting, the live lines belong to the tick, and keeping the live lines running is what
    # makes the drag a teaching instrument at all.
    if get(radar.comp, :trk_dirty, false)
        for k in (:trk_gain_range, :trk_gain_look, :trk_loss_range, :trk_loss_look, :trk_post_cpa_det)
            delete!(radar.comp, k)
        end
        radar.comp[:trk_pass_dirty] = true
        radar.comp[:trk_dirty] = false
    end
    look   = Int(get(radar.comp, :trk_look, 0)) + 1
    radar.comp[:trk_look] = look
    # The leg. `past_before` is the state the PREVIOUS look left, so the CPA look — the first with
    # a non-negative range rate — still counts as inbound for the gain edge and as outbound for the
    # loss one, the shared-index posture the gate-0 rule had.
    past_before = get(radar.comp, :trk_past_cpa, false)::Bool
    past_now    = past_before || rdot ≥ 0.0
    radar.comp[:trk_past_cpa] = past_now

    alive, misses, opened, dropped =
        track_run_step(get(radar.comp, :trk_alive, false)::Bool,
                       Int(get(radar.comp, :trk_misses, 0)), detected, n_drop)
    radar.comp[:trk_alive]  = alive
    radar.comp[:trk_misses] = misses

    if detected
        radar.comp[:trk_last_range] = R          # the range the NEXT drop will be declared at
        radar.comp[:trk_last_look]  = look
        past_now && (radar.comp[:trk_post_cpa_det] = true)
        if opened
            # ⚠ THE GAIN EDGE IS OVERWRITTEN ON EVERY INBOUND OPEN, DELIBERATELY: an inbound
            # flicker that costs the track restarts it, and "where you got it" is where the track
            # you still hold at CPA began — not where an earlier, abandoned one did.
            past_before || (radar.comp[:trk_gain_range] = R; radar.comp[:trk_gain_look] = look)
        end
    end
    if dropped && get(radar.comp, :trk_post_cpa_det, false) && !haskey(radar.comp, :trk_loss_range)
        radar.comp[:trk_loss_range] = radar.comp[:trk_last_range]
        radar.comp[:trk_loss_look]  = radar.comp[:trk_last_look]
    end
    return nothing
end

"""
    _track_cfar_look!(radar, ranges, powers, revisit_s, dr, truth_range) -> nothing

⭐⭐⭐ **SLICE 54 gate 2 — THE GIVE-UP TRACKER OVER A *PICTURE*, AND THE FIRST TRACK IN THIS ARC THAT
CAN BE WRONG ABOUT WHERE IT IS.** A **SIBLING** of [`_track_look!`], not a branch of it: the two
share only the pure `track_run_step`, because slice 53's gain/loss edges and one-CPA latch assume a
TRUTH range this tracker is deliberately no longer handed.

The point-path tracker is told `any_detect` over the strongest target and stamped with that target's
real range, so a track it holds on nothing is silently right. Here the look arrives as a list of
DETECTED CELLS — some of which are threshold crossings in noise or clutter (`pfa`, and a clutter
band's edges) — and the tracker must decide FOR ITSELF which one, if any, is its own. It can pick
the wrong one, and then it reports a range that is not the target's. That is the whole point.

⚠⚠ **THE TWO ASSOCIATION RULES DIFFER ON PURPOSE, AND THE DIFFERENCE IS THE LESSON:**

* **ALIVE → `track_associate`** — the NEAREST detected cell inside a gate about the prediction.
  Conservative: a live track already believes something, and the loudest return in the profile is
  not evidence about the thing it is holding.
* **DEAD → `track_reopen`** — the STRONGEST detected cell in the whole profile, UNGATED. Credulous:
  a dropped track has no prediction left to gate against, so it takes the loudest thing there is.

⇒ **patience is TWO-SIDED**: holding on longer rides a fade and keeps a target that is still there,
and *also* keeps a track that has already been captured by a false alarm. Gate-0 §2.8.1 measured both
halves — every arm's score rises and then falls, and the fall steepens as the picture dirties.

⚠⚠ **THE GATE IS COMPUTED FROM THE WIRE EVERY LOOK, NEVER HARDCODED.** `track_gate_cells` and the
α–β filter are both expressed in `revisit_s`, which no loader fixes, so a radar that revisits twice
as fast silently runs a different tracker unless the rule is evaluated rather than frozen. This is
slice 53's *a rule counted in samples changes meaning when the sample rate does*, one instrument
over — and gate-0 §2.8.2 is what makes it load-bearing: the COUNT of looks is a joint property of
the gate and the gauge's band; only the DIRECTION is physics.

⚠⚠ **`truth_range` REACHES THE GAUGE AND NEVER THE TRACKER.** The scoring below compares where the
track thinks it is against where the target actually is — that is a teaching instrument, and it is
the only gauge that can tell *a long track* from *a track in the wrong place* (gate-0 F3: a
false-alarm model touches only the detection, so every DURATION gauge is the slider in other units).
⚠ It is passed in AFTER every association decision has been made and is read by nothing else. A
truth value inside the association path would rebuild exactly the defect this slice exists to remove.

**THE GAUGE IS `good − bad`, SCORED ON POSITION AND ACCUMULATED OVER THE PASS**: a look counts
`good` when the track is alive and within `ok_cells` of truth, `bad` when it is alive and outside.
A dead track scores neither — being wrong is a cost, being silent is not.

⚠⚠ **A LIVE DRAG RESETS THE COUNTERS, AND IT HAS TO** (slice 52's re-arm rule; slice 53's latch
rule). `n_drop` is the thing under study and the counters are cumulative, so a run that spans a drag
would report a MIXTURE of two settings as though it were one measurement — the shape of slice 52's
peak-hold trap, where a knob that FELL could not be seen. The reset is consumed from `:trk_dirty`,
which `_mark_track_dirty!` sets unconditionally on any `set_param`. ⚠ The LIVE state (alive / misses
/ range / rate) is NOT reset: it describes the tick, not a past measurement — slice 53's own split.

⚠ **NAMED APPROXIMATIONS** (§1's trifecta discipline): ONE track per radar (the family's posture);
the gate is a fixed range window, not a covariance gate; the α–β constants are fixed
([`TRACK_ALPHA`]/[`TRACK_BETA`], pinned by test); the re-open is ungated; and there is no track
initiation logic — the first detected cell opens a track, so a single false alarm on a quiet
profile starts one.
"""
function _track_cfar_look!(radar::Entity, ranges::Vector{Float64}, powers::Vector{Float64},
                           revisit_s::Float64, dr::Float64, truth_range::Float64)
    n_drop = Int(radar.comp[:track_drop_looks])
    # ⚠⚠ THE DRAG, CONSUMED HERE — the AUTHORED arm's cumulative gauge only. Never the live state
    # (which describes the tick, not a past measurement — slice 53's split), and NEVER THE SWEEP:
    # the sweep is not a measurement OF the slider's setting, it is the curve the slider INDEXES
    # INTO, and blanking it on a drag would erase the very thing the user is reading.
    if get(radar.comp, :trk_dirty, false)
        radar.comp[:trk_good] = 0
        radar.comp[:trk_bad]  = 0
        radar.comp[:trk_scored_from] = Int(get(radar.comp, :trk_look, 0)) + 1
        radar.comp[:trk_dirty] = false
    end
    look = Int(get(radar.comp, :trk_look, 0)) + 1
    radar.comp[:trk_look] = look
    # The gauge's counters EXIST as soon as the tracker has run a look, so that "0 bad" is a
    # readable measurement rather than a missing key. ⚠ 0 is a legitimate value of both (a clean
    # picture with an impatient rule is never wrong — measured: `pfa` 1e-6 at `n_drop` 1..2), which
    # is exactly why they may not be left absent and defaulted at the reader (slice 50: a defaulted
    # zero and a real zero read the same, so PRESENCE has to decide).
    if !haskey(radar.comp, :trk_good)
        radar.comp[:trk_good] = 0; radar.comp[:trk_bad] = 0
        radar.comp[:trk_scored_from] = look
    end

    ok_m = Float64(get(radar.comp, :track_ok_cells, 1.0)) * dr

    # ── THE AUTHORED ARM: the track the view draws and the slider selects ────────────────────────
    alive, misses, r, rdot, gate_cells =
        _trk_arm_step(get(radar.comp, :trk_alive, false)::Bool,
                      Int(get(radar.comp, :trk_misses, 0)),
                      Float64(get(radar.comp, :trk_range, 0.0)),
                      Float64(get(radar.comp, :trk_rdot,  0.0)),
                      ranges, powers, revisit_s, dr, n_drop)
    radar.comp[:trk_alive]      = alive
    radar.comp[:trk_misses]     = misses
    radar.comp[:trk_range]      = r
    radar.comp[:trk_rdot]       = rdot
    radar.comp[:trk_gate_cells] = gate_cells
    err = abs(r - truth_range)
    if alive
        if err ≤ ok_m
            radar.comp[:trk_good] = Int(get(radar.comp, :trk_good, 0)) + 1
        else
            radar.comp[:trk_bad]  = Int(get(radar.comp, :trk_bad,  0)) + 1
        end
    end
    radar.comp[:trk_err_m] = err

    # ── ⭐⭐⭐ THE SWEEP: THE WHOLE CURVE, ON ONE PASS ────────────────────────────────────────────
    #
    # `n_drop` = 1…`track_sweep_max` run as SHADOW ARMS over the SAME picture, so the slice's
    # headline — *the score rises with patience and then falls, and where it peaks is set by how
    # dirty the picture is* — is visible in ONE flight instead of sixteen.
    #
    # ⚠⚠ **WHY THIS IS NOT OPTIONAL POLISH.** Gate-0 §2.5.3 and §2.8.2 measured that the ARGMAX is
    # a coin flip between neighbouring cells of a nearly flat top (peak NET moves 1.9 % across a 4×
    # gate) while the CURVE's shape is invariant. A readout printing "best = 4" would be reporting
    # the noise; the teaching object is the SHAPE. And the alternative — re-flying the pass once per
    # setting — is ~80 minutes of wall clock for one curve, which is not an instrument.
    #
    # ⭐⭐ IT IS ALSO A STRONGER COMPARISON THAN THE PROBES MADE: every arm sees the IDENTICAL draws,
    # so the curve is PAIRED, where the gate-0 ladder had to average six seeds to say the same
    # thing. Each arm differs from its neighbours ONLY in the give-up rule.
    #
    # ⚠⚠ NO RNG, AND THAT IS THE ONE WAY THIS COULD SILENTLY BREAK. Every arm reads the same
    # already-drawn `ranges`/`powers` and draws nothing — `_draw_profile!` stays the only RNG of a
    # look and its count is `2·N_p·N_cells` however many arms run (pinned by a tooth comparing the
    # profile arrays with the sweep PRESENT vs ABSENT).
    #
    # ⚠ The arms are INDEPENDENT STATE, one entry per arm per vector — an arm sharing the authored
    # track's `trk_*` bag would alias it. Arm `k` is required BY TEST to equal a tracker authored at
    # `track_drop_looks` = `k`, which is what makes the curve quotable.
    nsw = Int(get(radar.comp, :track_sweep_max, 0))
    if nsw ≥ 1
        if !haskey(radar.comp, :trk_sw_alive) ||
           length(radar.comp[:trk_sw_alive]::Vector{Bool}) != nsw
            radar.comp[:trk_sw_alive]  = fill(false, nsw)
            radar.comp[:trk_sw_misses] = zeros(Int, nsw)
            radar.comp[:trk_sw_range]  = zeros(Float64, nsw)
            radar.comp[:trk_sw_rdot]   = zeros(Float64, nsw)
            radar.comp[:trk_sw_good]   = zeros(Int, nsw)
            radar.comp[:trk_sw_bad]    = zeros(Int, nsw)
            radar.comp[:trk_sw_gate]   = ones(Int, nsw)
        end
        sa = radar.comp[:trk_sw_alive]::Vector{Bool}
        sm = radar.comp[:trk_sw_misses]::Vector{Int}
        sr = radar.comp[:trk_sw_range]::Vector{Float64}
        sv = radar.comp[:trk_sw_rdot]::Vector{Float64}
        sg = radar.comp[:trk_sw_good]::Vector{Int}
        sb = radar.comp[:trk_sw_bad]::Vector{Int}
        sc = radar.comp[:trk_sw_gate]::Vector{Int}
        @inbounds for k in 1:nsw
            a, m, rr, vv, gc =
                _trk_arm_step(sa[k], sm[k], sr[k], sv[k], ranges, powers, revisit_s, dr, k)
            sa[k] = a; sm[k] = m; sr[k] = rr; sv[k] = vv; sc[k] = gc
            if a
                abs(rr - truth_range) ≤ ok_m ? (sg[k] += 1) : (sb[k] += 1)
            end
        end
    end
    return nothing
end

"""
    _trk_arm_step(alive, misses, r, rdot, ranges, powers, revisit_s, dr, n_drop)
        -> (alive′, misses′, r′, rdot′, gate_cells)

ONE look of ONE give-up track over a CFAR picture — the whole rule, in one place.

⚠⚠ **THE AUTHORED TRACK AND EVERY SHADOW ARM OF THE SWEEP CALL THIS SAME FUNCTION**, which is what
makes *arm `k` of the curve* and *a scenario authored at `track_drop_looks` = `k`* the same thing by
construction rather than by coincidence. Duplicating the rule for the sweep would let the curve and
the slider drift apart silently — and the curve is what the lesson is read off.

Pure apart from its arguments: it draws nothing, reads no world state, and sees no truth (the gauge
scores the result afterwards — see [`_track_cfar_look!`]).
"""
function _trk_arm_step(alive::Bool, misses::Int, r::Float64, rdot::Float64,
                       ranges::Vector{Float64}, powers::Vector{Float64},
                       revisit_s::Float64, dr::Float64, n_drop::Int)
    gate_cells = track_gate_cells(rdot, revisit_s, dr)
    local detected::Bool
    if alive
        pred = r + rdot * revisit_s
        i    = track_associate(pred, ranges, gate_cells * dr)
        r, rdot = track_ab_step(r, rdot, revisit_s, i == 0 ? nothing : ranges[i])
        detected = i != 0
    else
        # A DEAD track has no prediction to gate against: it restarts on the loudest cell there is.
        i = track_reopen(powers)
        if i != 0
            r = ranges[i]; rdot = 0.0
        end
        detected = i != 0
    end
    a, m, _, _ = track_run_step(alive, misses, detected, n_drop)
    return (a, m, r, rdot, gate_cells)
end

"""
    _target_snr(prop, rp, radar, tgt, ter=nothing) -> (snr_lin, visible)

Single-target SNR under the active `propagation` fidelity, plus a horizon-visibility
flag. `:free_space` is infinite-LOS phenomenology (no ground, always visible).
`:two_ray` adds the flat-earth multipath (`snr_two_ray`, decomposed slant/ground) and
the 4/3-Earth horizon: a target whose ground range exceeds `horizon_range` has no line
of sight and is masked to SNR 0 (NOT -Inf — see [`_snr_db_wire`](@ref)). `:terrain`
(slice 18) is the free-space link budget + a HARD terrain-shadow mask: an occluded
LOS (`terrain_los_clear`, terrain.jl) masks to `(0.0, false)` — exactly the
below-horizon policy shape; `ter` is the world's heightfield (`_world_terrain`,
looked up ONCE per observe call by the caller and ONLY under this rung), and
`ter === nothing` (no `:terrain` entity) falls through to bit-exact free space (the
mismatched-EP no-op precedent — a live rung toggle can never crash a tick). rf.jl /
terrain.jl stay pure phenomenology; the masking POLICY and the degenerate guards live
here, per HANDOFF §1/§10 and the slice-2/18 plans.
"""
function _target_snr(prop::Symbol, rp::RadarParams, radar::Entity, tgt::Entity,
                     ter::Union{Nothing,TerrainParams} = nothing)
    R   = _range(tgt.pos, radar.pos)
    rcs = _effective_rcs(tgt, radar.pos)
    if prop === :free_space
        return snr_freespace(rp, rcs, R), true
    elseif prop === :terrain
        ter === nothing && return snr_freespace(rp, rcs, R), true
        terrain_los_clear(ter, radar.pos, tgt.pos) || return 0.0, false
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
    # The heightfield is consulted ONLY under the `:terrain` rung (slice 18) — every other
    # rung's path is textually identical to slice 17 (byte-identity; the lookup draws nothing).
    ter  = prop === :terrain ? _world_terrain(w) : nothing

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
    best_pos = w.entities[target_ids[1]].pos   # strongest target's pos → terrain clearance readout
    best_vel = w.entities[target_ids[1]].vel   # …and its velocity → the tracker's closing/opening leg
    # ⭐ SLICE 49: the strongest target's ASPECT and its aspect-adjusted RCS, carried alongside so
    # the readouts below describe the SAME target the SNR does. `nothing` while no shaped target has
    # been seen — the key-presence gate for the telemetry (a wire with no `:rcs_fineness` anywhere
    # ships no new keys and is byte-identical, the `terrain_clearance_m` / `jnr_db` precedent).
    best_asp = nothing; best_rcs = nothing
    # ⭐ …AND THE COST, AS **ONE CORE-COMPUTED NUMBER** — the `js_db` posture verbatim (a dB
    # DIFFERENCE is formed HERE so the client never subtracts, convention 13). The client CANNOT
    # form this one anyway: `rcs_m2` is a comp key an author writes and has never been on the wire,
    # so a HUD would have nothing to measure σ_eff against.
    best_loss = nothing
    any_detect = false
    for tid in target_ids
        tgt = w.entities[tid]
        snr_th, vis = _target_snr(prop, rp, radar, tgt, ter)
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
            best_pos = tgt.pos
            # ⭐ SLICE 53 gate 2: …AND ITS VELOCITY, carried for one reason only — the
            # tracker below needs the RANGE RATE's SIGN to know which LEG of a pass it is
            # on, and `range_rate` needs a relative velocity. No physics reads it.
            best_vel = tgt.vel
            if haskey(tgt.comp, :rcs_fineness)
                best_asp = aspect_angle(tgt.pos, tgt.vel, radar.pos)
                best_rcs = _effective_rcs(tgt, radar.pos)
                # dB BELOW BROADSIDE, and the NAME carries the sign so no reader has to guess it:
                # positive = this much quieter than the authored `rcs_m2`. Never ±Inf — `rcs_aspect`'s
                # denominator `(sin²θ + F²cos²θ)²` is strictly positive for every `F > 0`, and the
                # consumer's own floor keeps `F` there.
                # ⚠ SLICE 53 — "QUIETER" IS NOW THE COMMON CASE, NOT THE ONLY ONE, AND A HUD MUST
                # NOT WORD IT AS THOUGH IT WERE. A tail gain multiplies the rear hemisphere, so
                # σ_eff EXCEEDS the authored `rcs_m2` — and this reads NEGATIVE — wherever
                # `G > F⁴·(…)`, i.e. astern of a body that is not slender enough to pay for its own
                # lobe (`F` = 1 with any `G` > 1; `F` = 8 needs `G` > 4096). The oblate case at
                # line ~695 already documented a negative reading, so the SIGN CONVENTION is
                # unchanged and needs no new key — only the wording downstream of it does.
                best_loss = lin2db(max(Float64(tgt.comp[:rcs_m2]), 1.0e-12) / best_rcs)
            else
                best_asp = nothing; best_rcs = nothing; best_loss = nothing
            end
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
        # ⭐ SLICE 53 gate 2 — THE TRACK, which is the thing the detector is not. Runs ONLY when
        # the radar authors a `track_drop_looks`, so every slice-1..52 wire ships no new key and
        # is byte-identical (the `terrain_clearance_m` / slice-49 precedent). It reads `any_detect`
        # AFTER the draw and draws nothing itself — convention 3's draw topology is untouched.
        haskey(radar.comp, :track_drop_looks) &&
            _track_look!(radar, any_detect, _range(best_pos, radar.pos),
                         range_rate(best_pos - radar.pos, best_vel - radar.vel))
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
    # Slice 18: the SIGNED LOS clearance to the strongest target — the lesson's number
    # (positive = clears by that many metres, negative = buried; sign IS the verdict).
    # Shipped ONLY under the `:terrain` rung WITH a heightfield present (the slice-17
    # lift-keys precedent: key-presence gated on the RUNG, so a non-terrain wire — and
    # every slice-1..17 scenario — is byte-identical). `_finite_coord`: symmetric clamp,
    # a signed readout must keep its sign (convention 6).
    ter === nothing ||
        (tel["$sid.terrain_clearance_m"] = _finite_coord(terrain_clearance(ter, radar.pos, best_pos)))
    # jnr_db / js_db ship ONLY when this radar actually sees a jammer — so a no-jammer frame is
    # unchanged (slices 1-3). js_db is the dB DIFFERENCE jnr_db − snr_th_db: exactly
    # lin2db(JNR/S) when both are above the floor (log identity), and wire-safe (finite,
    # correct-direction) if S→0 (a masked/no-target frame), where lin2db(JNR/S) would be +Inf →
    # JSON poison (the slice-2 null watch-item, here on the J/S readout). >0 = jammed, <0 = burn-through.
    if contribs !== nothing
        tel["$sid.jnr_db"] = _snr_db_wire(jnr_total)
        tel["$sid.js_db"]  = _snr_db_wire(jnr_total) - _snr_db_wire(best_snr_th)
    end
    # ⭐ SLICE 49 — WHICH WAY THE TARGET IS POINTING, AND WHAT THAT COSTS IT. Shipped ONLY when the
    # strongest target carries a `:rcs_fineness` (key-presence gated, so every slice-1..48 wire is
    # byte-identical). DEGREES on the wire, radians inside — the `gimbal_*_deg` boundary posture.
    # ⚠ ALL FOUR are READOUTS with no consumer in the physics, which is why they belong here: the
    # detection verdict is `detected`/`pd` above, and a HUD that showed only those could not say
    # WHY the target vanished. Aspect is the reason; σ_eff is the mechanism; the dB is the PRICE;
    # the range is what the price is being paid IN.
    if best_asp !== nothing
        tel["$sid.target_aspect_deg"] = _finite_coord(rad2deg(best_asp))
        tel["$sid.rcs_eff_m2"]        = _finite(best_rcs)
        # ⚠ SIGNED, so `_finite_coord` and not `_finite`: an OBLATE body (`F < 1`, legal and
        # documented at `rcs_aspect`) is BRIGHTER nose-on than broadside and this reads NEGATIVE.
        # A magnitude-only clamp would silently turn a gain into a loss.
        tel["$sid.rcs_loss_db"]       = _finite_coord(best_loss)
        # ⭐⭐ AND THE RANGE, WHICH IS WHAT MAKES THE DROP-OUT A LESSON RATHER THAN A NUMBER. The
        # gauge this slice is measured on is the longest loss run **WHILE CLOSING** (the scenario's
        # own header), and until now this radar shipped no range at all — so a client could only
        # ever have timed a WHOLE-FLIGHT loss. On this wire the target passes CPA at ~7.8 km and
        # opens again, so a whole-flight clock keeps counting on the outbound leg and drifts ABOVE
        # the 36.50 s the ladder quotes: the HUD would print a number that is not the slice's.
        # Shipped HERE, gated with the other two, so the HUD and the verifier read the SAME
        # quantity from the SAME place (convention 7) — and so "range given up" is a subtraction of
        # two wire values rather than a geometry recompute in GDScript (convention 13).
        tel["$sid.target_range_m"]    = _finite(_range(best_pos, radar.pos))
    end
    # ⭐⭐ SLICE 53 gate 2 — THE TRACK AND ITS TWO EDGES. Key-presence gated on the radar's OWN
    # `track_drop_looks` (see `_track_look!`), so a wire that authors no tracker ships no new key
    # and is byte-identical — and, deliberately, the gate is NOT the target's `rcs_tail_gain`: the
    # showcase's headline drag is `G` = 20 → 1 back to the null, and an instrument that blanked at
    # `G` = 1 would go dark on exactly the arm that proves the null (slice 50: presence decides,
    # and the lesson's NULL must not read like a dead instrument's default).
    if haskey(radar.comp, :track_drop_looks)
        # ⚠⚠ THE RULE SHIPS BESIDE ITS NUMBERS, AND THAT IS NOT DECORATION (gate-0 §2.14): the
        # metres below are a joint property of the tail lobe AND the tracker, so a readout that
        # quotes them without `revisit_s` and the give-up depth is not quoting a measurement. Both
        # travel on the wire so no client can print one without the other.
        tel["$sid.track_drop_looks"]  = Float64(radar.comp[:track_drop_looks])
        tel["$sid.track_revisit_s"]   = r.revisit_s
        tel["$sid.track_alive"]       = get(radar.comp, :trk_alive, false)
        tel["$sid.track_closing"]     = !get(radar.comp, :trk_past_cpa, false)
        tel["$sid.track_misses"]      = Float64(get(radar.comp, :trk_misses, 0))
        tel["$sid.track_look"]        = Float64(get(radar.comp, :trk_look, 0))
        # ⚠ −1.0 is "NOT YET", never a range: the slice-48 `search_t_lock_s` sentinel posture, and
        # unambiguous here because a range is strictly positive. The LOOK indices carry the same
        # sentinel and exist for the dead-zone constraint gate 0 §2.9 pinned — a drag can move the
        # edge by ZERO metres and still be alive, so the readout must be able to say how many LOOKS
        # the edge sits at rather than only how many metres.
        tel["$sid.track_gain_range_m"] = _finite(get(radar.comp, :trk_gain_range, -1.0))
        tel["$sid.track_gain_look"]    = Float64(get(radar.comp, :trk_gain_look, -1))
        tel["$sid.track_loss_range_m"] = _finite(get(radar.comp, :trk_loss_range, -1.0))
        tel["$sid.track_loss_look"]    = Float64(get(radar.comp, :trk_loss_look, -1))
        # ⚠⚠ "THE SETTINGS MOVED DURING THIS PASS" — true from the first live drag until a Reset.
        # A pass that spans two settings is not a measurement of either, and past closest approach
        # the gain edge can never be re-declared, so this is the wire's way of saying what slice 50
        # says in words: **Reset to measure.** It is a property of the PASS, not of the numbers
        # still on the wire — anything present after a drag was declared after it (both edges are
        # deleted), so a surviving edge is never stale, it is only lonely.
        tel["$sid.track_pass_dirty"]   = get(radar.comp, :trk_pass_dirty, false)
        # ⭐⭐⭐ THE GAUGE — and it ships ONLY when both edges exist. 0.0 is a LEGITIMATE value here
        # (it is what a fore/aft symmetric target reads), so a sentinel or a defaulted zero would be
        # indistinguishable from the lesson's own null on an instrument that has not finished.
        # `_finite_coord`, not `_finite`: the sign IS the verdict and a dimmer tail reads NEGATIVE.
        if haskey(radar.comp, :trk_gain_range) && haskey(radar.comp, :trk_loss_range)
            tel["$sid.track_asym_m"] =
                _finite_coord(radar.comp[:trk_loss_range] - radar.comp[:trk_gain_range])
        end
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
    _terrain_info(w) -> Union{Dict, Nothing}

The STATIC terrain block a slice-18 scenario ships ONCE in the `scenario` handshake
(the `_cfar_axis_info` / `_esm_axis_info` / `_airframe_view_info` precedent — it is
LOAD-STATIC by design; hills are not live knobs, see docs/plans/slice18.md). Ships:

  • `terrain_grid` — the row-major `terrain_n × terrain_n` height sample (metres) the
    client MESHES — core output, the client never recomputes a height (HANDOFF §1);
  • `terrain_n` / `terrain_extent_m = [xmin, xmax, ymin, ymax]` — the grid shape;
  • `terrain` — the terrain entity id; `radar` / `target` — the first (sorted) radar
    and target ids, so the client knows whose `.visible`/`.terrain_clearance_m`
    telemetry colors the LOS ray without guessing by kind.

**`terrain_grid` presence is the client's 3-D-view discriminator** (the
`range_axis_m`→cfar precedent). `nothing` for a non-terrain world (the keys simply
don't appear). Grid heights are closed-form finite (convention 6 needs no clamp).
"""
function _terrain_info(w::World)
    tids = sort!(Symbol[id for (id, e) in w.entities if e.kind === :terrain])
    isempty(tids) && return nothing
    c = w.entities[tids[1]].comp
    n = Int(c[:grid_n])
    xmin = Float64(c[:xmin]); xmax = Float64(c[:xmax])
    ymin = Float64(c[:ymin]); ymax = Float64(c[:ymax])
    info = Dict{Symbol,Any}(:terrain => tids[1], :terrain_n => n,
                            :terrain_extent_m => [xmin, xmax, ymin, ymax],
                            :terrain_grid => terrain_grid(_terrain_params(c),
                                                          xmin, xmax, ymin, ymax, n))
    radars  = sort!(Symbol[id for (id, e) in w.entities if e.kind === :radar])
    targets = sort!(Symbol[id for (id, e) in w.entities if e.kind === :target])
    isempty(radars)  || (info[:radar]  = radars[1])
    isempty(targets) || (info[:target] = targets[1])
    return info
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
    # Slice 18: terrain masking composes with the CFAR profile exactly as `:propagation`
    # always has — through `_target_snr` (a shadowed target's bump is 0). Looked up ONLY
    # under the `:terrain` rung; the clearance READOUT stays point-path-only (the slice-18
    # scenario is a point-detector lesson — convention 9).
    ter   = prop === :terrain ? _world_terrain(w) : nothing
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
    # ⭐ SLICE 54: the strongest target's TRUE range, carried for the TRACKER'S GAUGE and nothing
    # else — it is what the track's own range is scored against. `NaN` while no target has been
    # seen; the gauge's comparison is then false either way, so an empty world scores nothing.
    best_range = NaN
    cell_target = Dict{Int,Symbol}()            # cell → target id, for the event :of tag
    bumps = Tuple{Int,Float64}[]                # (cell, linear SNR) to add to the profile power
    target_ids = sort!(Symbol[id for (id, e) in w.entities if e.kind === :target])
    for tid in target_ids
        tgt = w.entities[tid]
        snr, vis = _target_snr(prop, rp, radar, tgt, ter)
        pd  = pd_analytic(snr, pfa; swerling = sw, n_pulses = np)
        Rt  = _range(tgt.pos, radar.pos)
        ci  = _range_to_cell(Rt, rstart, dr, ncells)
        if ci != 0
            get!(cell_target, ci, tid)          # first (sorted) target wins a shared cell
            push!(bumps, (ci, snr))
        end
        if snr > best_snr
            best_snr = snr; best_pd = pd; best_visible = vis; best_cell = ci
            best_range = Rt
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

        # ⭐⭐⭐ SLICE 54 gate 2 — THE TRACK OVER THE PICTURE. Runs ONLY when the radar authors a
        # `track_drop_looks`, so every slice-1..53 wire ships no new key and is byte-identical (the
        # `terrain_clearance_m` / slice-49 precedent, and the same posture `_track_look!` has on the
        # point path). ⚠⚠ IT READS `detections` **AFTER** `_draw_profile!` AND DRAWS NOTHING — the
        # ONLY RNG of a CFAR look is that one call, whose count is `2·N_p·N_cells` regardless of
        # rung, slider or geometry, so convention 3's draw topology is untouched by the tracker and
        # by `track_drop_looks` (pinned by the draw-invariance tooth).
        #
        # ⚠⚠ TRUTH GOES TO THE GAUGE, NOT TO THE TRACKER. `best_cell` is the STRONGEST TARGET's cell
        # and is computed above for the readout; the tracker is handed the detected cells and their
        # powers ONLY, and truth reaches `_track_cfar_look!` as a separate argument used solely to
        # SCORE where the track ended up. A truth value inside the association path would rebuild
        # the exact defect this slice exists to remove (gate-0 §1).
        if haskey(radar.comp, :track_drop_looks)
            det   = radar.comp[:detections]::Vector{Bool}
            zprof = radar.comp[:profile_z]::Vector{Float64}
            hits  = findall(det)
            _track_cfar_look!(radar,
                              Float64[_cell_range(ci, rstart, dr) for ci in hits],
                              Float64[zprof[ci] for ci in hits],
                              r.revisit_s, dr,
                              best_range)
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
    # ⭐⭐⭐ SLICE 54 gate 2 — THE TRACK'S OWN LINES. Key-presence gated on `track_drop_looks`, so a
    # wire that authors no tracker ships NO new key and stays byte-identical.
    #
    # ⚠⚠ THE RULE KEYS SHIP BESIDE THE GAUGE, ALWAYS — gate-0 §2.8.2 measured that the COUNT of
    # looks is a JOINT property of the give-up rule, the tracker's GATE and the gauge's BAND (the
    # same arm reads 5, 7, 9 or 11 depending on two constants that are not physics). Only the
    # DIRECTION is physics. A client that could print a score without `track_drop_looks`,
    # `track_revisit_s`, `track_gate_cells` and `track_ok_cells` beside it would be printing a
    # number that cannot be reproduced — slice 53's `revisit_s`/N* rule, one instrument over.
    if haskey(radar.comp, :track_drop_looks)
        tel["$sid.track_drop_looks"] = Float64(radar.comp[:track_drop_looks])
        tel["$sid.track_revisit_s"]  = r.revisit_s
        tel["$sid.track_gate_cells"] = Float64(get(radar.comp, :trk_gate_cells, 1))
        tel["$sid.track_ok_cells"]   = Float64(get(radar.comp, :track_ok_cells, 1.0))
        tel["$sid.track_alive"]      = get(radar.comp, :trk_alive, false)
        tel["$sid.track_misses"]     = Float64(get(radar.comp, :trk_misses, 0))
        tel["$sid.track_range_m"]    = _finite_coord(Float64(get(radar.comp, :trk_range, 0.0)))
        tel["$sid.track_rdot"]       = _finite_coord(Float64(get(radar.comp, :trk_rdot, 0.0)))
        # THE GAUGE: looks the track spent ON the target, looks it spent somewhere ELSE, and their
        # difference. Scored on POSITION, never on duration (gate-0 F3) — a long track is not a
        # failure, a track in the WRONG PLACE is.
        good = Int(get(radar.comp, :trk_good, 0)); bad = Int(get(radar.comp, :trk_bad, 0))
        tel["$sid.track_good_looks"] = Float64(good)
        tel["$sid.track_bad_looks"]  = Float64(bad)
        tel["$sid.track_net"]        = Float64(good - bad)
        # ⚠⚠ F7's DISAMBIGUATOR, AND IT IS NOT DECORATION. `track_drop_looks` is an INTEGER slider
        # (`set_param` coerces through `Int(round(v))`), so its domain is ~8 discrete positions and
        # FLAT STRETCHES ARE GUARANTEED — gate-0 §2.5.3/§2.8.1 measured that the peak sits on a
        # nearly flat top. Without a counter that visibly advances, a flat stretch reads as *the
        # instrument is dead* rather than as *this setting scores the same*. `track_look` is the
        # look index; `track_scored_from` is the look the CURRENT counters started at, so a client
        # can show how much of the pass this setting actually owns after a drag.
        tel["$sid.track_look"]         = Float64(get(radar.comp, :trk_look, 0))
        tel["$sid.track_scored_from"]  = Float64(get(radar.comp, :trk_scored_from, 1))
        # The live position error the gauge is thresholding — floored, never ±Inf (convention 6).
        # ⚠ ABSENT until a look has run, because 0.0 is a legitimate value of an error and a
        # defaulted zero would read as a PERFECT track on an instrument that has not started
        # (slice 50: presence decides).
        haskey(radar.comp, :trk_err_m) &&
            (tel["$sid.track_err_m"] = _finite_coord(Float64(radar.comp[:trk_err_m])))
        # ⭐⭐⭐ THE CURVE ITSELF — NET against `n_drop` = 1…`track_sweep_max`, every arm scored on
        # the SAME picture this pass drew. This is the slice's teaching object: gate-0 §2.5.3 and
        # §2.8.2 measured that the ARGMAX is a coin flip on a nearly flat top while the SHAPE is
        # invariant, so the wire ships the shape and lets the client draw it. ⚠ The client MUST NOT
        # reduce this to "best = k" — that is the number the plan proved is not reproducible.
        # ⚠ Absent when no sweep is authored (`track_sweep_max` = 0), so nothing is defaulted.
        if haskey(radar.comp, :trk_sw_good)
            sg = radar.comp[:trk_sw_good]::Vector{Int}
            sb = radar.comp[:trk_sw_bad]::Vector{Int}
            tel["$sid.track_sweep_net"]  = Float64[sg[k] - sb[k] for k in eachindex(sg)]
            tel["$sid.track_sweep_good"] = Float64.(sg)
            tel["$sid.track_sweep_bad"]  = Float64.(sb)
            tel["$sid.track_sweep_max"]  = Float64(length(sg))
            # ⚠ The widest gate any arm reached. The pre-registered rule yields 1 cell on the
            # authored wire; a SEDUCED arm can pick up a large rate estimate and ask for more, and
            # if this ever reads `TRACK_GATE_MAX_CELLS` the cap has BOUND and the gate is no longer
            # the pre-registered rule — which the showcase would have to say out loud.
            tel["$sid.track_sweep_gate_max"] =
                Float64(maximum(radar.comp[:trk_sw_gate]::Vector{Int}))
        end
    end
    return nothing
end
