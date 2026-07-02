# missile.jl — the BallisticMissile subsystem: the FIRST force-based integrator in the
# tick loop (HANDOFF §3, §10 item 8, slice 8 gate 2).
#
# Slices 1–7 lit phases 2/3/4 of the tick contract repeatedly but only ever used phase 1
# (`integrate!`) for TRIVIAL kinematics — `ConstantVelocity`'s `pos += vel·dt`. The
# BallisticMissile is the first phase-1 mover that solves an actual Newtonian ODE
# (forces → accel → vel → pos) via the gate-1 steppers in `dynamics.jl`, under the shared
# `frames.jl` frame algebra. It lights NO NEW phase — its novelty is REAL dynamics where
# every prior slice had passive movers, plus the first live use of `frames.jl`
# (velocity-aligned attitude). `BallisticMissile` itself stays `integrate!`-ONLY: its
# `observe!`/`decide!` are empty and the airframe never adds them. Guidance and the seeker ride on
# SEPARATE subsystems layered onto the same `:missile` entity — the phase-4 `Autopilot` (slice 9,
# below) and the phase-3 `Seeker` (slice 11, below) — so "a missile is integrate! + observe! +
# decide!" (HANDOFF §3) is assembled from three subsystems, not folded into this one.
#
# Included AFTER radar.jl (mirroring geolocation.jl/esm.jl/gps.jl) but with NO back-dep on
# radar's radar/jammer symbols: it reuses only `dynamics.jl` (`total_accel`,
# `integrator_step`, `INTEGRATOR_MODES`, `G_ACCEL`), `frames.jl` (`quat_from_two_vectors`),
# gnss.jl's `_norm3`, and geometry.jl's `_finite`/`_finite_coord` — all in scope before it.
#
# TELEMETRY PHASE — a NAMED deviation from the plan's phrasing (advisor-confirmed): the plan
# sketch says "phase-1 writes into env[:telemetry] like the radar readout", but `tick!` calls
# `empty!(w.env)` immediately AFTER phase 1, so a phase-1 telemetry write is wiped before the
# frame is built (and the radar readout is actually PHASE-3 observe!, post-empty!). So the
# missile's ENERGY/POSITION readout is published from `build_env!` (phase 2, post-empty!,
# reading the post-integrate state) — a DERIVED quantity, order-independent, RNG-free, and NOT
# a sensing/guidance phase (those stay empty for slices 9–11). `integrate!` owns the physics;
# `build_env!` owns the readout.
#
# DETERMINISM (advisor #1 — the one place copying the slice-5/6/7 template gives a FALSE
# claim): there is NO RNG in slice 8, so "RNG lockstep" / "draw-count-invariance" is VACUOUS,
# not a property to prove. Three distinct claims, never conflated:
#   1. INTRODUCE-SAFE — absent a `:missile` entity nothing reads `:integrator`, so introducing
#      it mid-run on any slice-1..7 scenario is a no-op → slices 1–7 byte-identical.
#   2. same-config replay is bit-identical — deterministic, TRIVIALLY (no RNG to desync).
#   3. a mid-run `:integrator` toggle CHANGES the trajectory (the not-a-dead-knob property) —
#      the OPPOSITE of slices 5/6/7's toggle invariance. `:integrator` is a PHYSICS-CHANGING
#      fidelity (the slice-2 `propagation` shape), NOT toggle-bit-identical.
#
# NAMED APPROXIMATIONS (HANDOFF §1 — the force-model ones live in dynamics.jl; the two here):
#   • within-`dt` impact clamp — the ground crossing is clamped to `z = 0` within one step, NOT
#     sub-step root-found (sub-mm at guidance rates); named, not implied.
#   • velocity-aligned attitude is KINEMATIC-ONLY — a point-mass body has no attitude dynamics
#     (no fin/actuator model — 6-DOF is deferred, §11 Tier A); `att` is set to point body-x
#     along `v` purely for the client's nose direction, never fed back into the force.

# Total mechanical energy `E = ½·m·‖v‖² + m·g·z` (KE + flat-earth PE), joules — the "lesson as
# a number" (HANDOFF §1). Drag off + `:rk4` conserves it to machine eps over the flight; drag
# on bleeds it monotonically. Shared by the e0 init and the readout.
_missile_ke(mass, vel) = 0.5 * mass * (vel[1]^2 + vel[2]^2 + vel[3]^2)
_missile_pe(mass, pos) = mass * G_ACCEL * pos[3]
_missile_energy(mass, pos, vel) = _missile_ke(mass, vel) + _missile_pe(mass, pos)

# A mass floor at the consumer so a live/degenerate config can't divide-by-zero in the drag
# term or the energy (mass is loader-validated > 0, so this is belt-and-braces, the
# `_SIGMA_RANGE_FLOOR` precedent).
const _MISSILE_MASS_FLOOR = 1.0e-9
# Below this |E₀| the fractional conservation error `ΔE = (E−E₀)/E₀` is ill-defined (a launch
# at z=0 with v→0) → report 0.0 rather than a blow-up (which `_finite` would clamp anyway).
const _MISSILE_E_FLOOR = 1.0e-9

"""
    BallisticMissile(id)

The ballistic projectile `id` as a phase-1 `integrate!`-only subsystem — the FIRST
force-based integrator in the tick loop. Each physics step it solves the airframe ODE
`(ṗ, v̇) = (v, a(v))` (with `a = total_accel`, dynamics.jl) via the gate-1 stepper selected
by the `:integrator` fidelity (`get(w.fidelity, :integrator, :rk4)`), advancing the entity's
`(pos, vel)`. It owns `pos`/`vel` advancement, so the loader gives a `:missile` entity
`[BallisticMissile]` and **NOT** `ConstantVelocity` (two phase-1 movers would double-integrate).

Airframe config lives in the entity `comp` bag, read with DEFAULTS at the consumer so a bare
`:missile` block or a live slider can't `KeyError`/crash a tick (the "a live config can't crash
a tick" watch-item): `:mass_kg`, `:cd_area_m2` (the lumped `Cd·A`; drag off = `0`), `:rho`
(air density, default `1.225`). On the ground crossing (`z ≤ 0` descending) it clamps `z = 0`,
zeroes the velocity, latches `comp[:impacted] = true` (subsequent ticks no-op — the frozen
splash), and emits ONE `:impact` event. Sets a velocity-aligned attitude each step
(`quat_from_two_vectors([1,0,0], v̂)`, exercising `frames.jl` live + its apex `v→0` guard).
"""
struct BallisticMissile <: Subsystem
    id::Symbol
end

function integrate!(m::BallisticMissile, w::World, dt::Float64)
    e = w.entities[m.id]
    c = e.comp
    mass    = max(Float64(get(c, :mass_kg, 1.0)), _MISSILE_MASS_FLOOR)
    rho     = Float64(get(c, :rho, 1.225))
    cd_area = Float64(get(c, :cd_area_m2, 0.0))
    # E₀ = the launch energy, the ΔE reference. Lazily set on the first tick from the pre-step
    # (launch) state, so a loader-built AND a programmatically-built missile agree; survives
    # `reset` for free (reload → fresh comp → re-init from the reloaded launch state).
    haskey(c, :e0_j) || (c[:e0_j] = _missile_energy(mass, e.pos, e.vel))

    # Once impacted the missile is frozen: no more integration (the readout still republishes
    # in build_env!, so the frame never blanks). The latch makes the :impact event one-shot.
    if !get(c, :impacted, false)
        mode = get(w.fidelity, :integrator, :rk4)
        # GUIDANCE SEAM (slice 9): a GUIDED missile carries a control specific force `:a_ctrl`
        # (a Vec3, written by the Autopilot's phase-4 decide! LAST tick → applied HERE this tick,
        # the one-tick delay). The `haskey` GUARD makes a BALLISTIC missile (no :a_ctrl) take the
        # EXACT slice-8 closure — byte-identity BY CONSTRUCTION, not by trusting
        # `total_accel(v) + zero(Vec3)` (`-0.0 + 0.0 → +0.0` flips a bit the reinterpret
        # determinism tests catch). `:a_ctrl` is a Vec3 so the SVector+SVector add stays bit-exact.
        accel = if haskey(c, :a_ctrl)
            a_ctrl = c[:a_ctrl]::Vec3
            v -> total_accel(v; rho = rho, cd_area = cd_area, mass = mass) + a_ctrl
        else
            v -> total_accel(v; rho = rho, cd_area = cd_area, mass = mass)
        end
        p′, v′ = integrator_step(mode, accel, e.pos, e.vel, dt)
        if p′[3] ≤ 0.0
            # Ground impact: clamp z=0 within the step (named approx — no sub-step root-find),
            # freeze, and emit ONE :impact event. A launch at z=0 with an UPWARD velocity rises
            # (`p′[3] > 0`) so it does NOT insta-impact; a descending crossing does. Events live
            # in `w.events` (NOT env — so not wiped by `empty!(w.env)`), cleared by the server
            # after the frame ships (the detection-event precedent).
            p′ = Vec3(p′[1], p′[2], 0.0)
            v′ = zero(Vec3)
            c[:impacted] = true
            push!(w.events, Dict{Symbol,Any}(:kind => :impact, :of => m.id))
        end
        e.pos = p′
        e.vel = v′
        # Velocity-aligned attitude (kinematic-only, named approx): body-x along v̂ gives the
        # client a nose direction and exercises `frames.jl` in the live tick; the apex/impact
        # `v→0` hits `quat_from_two_vectors`'s zero-vector guard (→ identity, no NaN).
        e.att = quat_from_two_vectors(Vec3(1.0, 0.0, 0.0), v′)
    end
    return nothing
end

# Phase-2 readout (see the TELEMETRY PHASE note above): the energy/position scalars, derived
# from the post-integrate state so they match the entity `pos` shipping in the same frame. No
# RNG, own keys only → order-independent (the build_env! contract). All `_finite`-clamped so a
# degenerate config ships huge-but-finite, never Inf/NaN.
function build_env!(m::BallisticMissile, w::World)
    e = w.entities[m.id]
    c = e.comp
    mass  = max(Float64(get(c, :mass_kg, 1.0)), _MISSILE_MASS_FLOOR)
    ke    = _missile_ke(mass, e.vel)
    pe    = _missile_pe(mass, e.pos)
    etot  = ke + pe
    e0    = Float64(get(c, :e0_j, etot))
    de    = abs(e0) < _MISSILE_E_FLOOR ? 0.0 : (etot - e0) / e0
    tel   = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid   = String(m.id)
    tel["$sid.pos_x"]     = _finite_coord(e.pos[1])
    tel["$sid.pos_z"]     = _finite_coord(e.pos[3])
    tel["$sid.speed"]     = _finite(_norm3(e.vel))
    tel["$sid.alt"]       = _finite_coord(e.pos[3])
    tel["$sid.ke_j"]      = _finite(ke)
    tel["$sid.pe_j"]      = _finite_coord(pe)                 # signed (z<0 → negative PE)
    tel["$sid.e_total_j"] = _finite_coord(etot)
    tel["$sid.de_frac"]   = _finite_coord(de)                 # (E−E₀)/E₀; ≈0 for RK4 drag-off
    tel["$sid.impacted"]  = get(c, :impacted, false)
    return nothing
end

# --- the GUIDED missile: the Autopilot subsystem (slice 9, HANDOFF §10 item 9) ----------------
# The missile's FIRST `decide!` (phase 4 — the phase slice 5 lit for the DF Geolocator): "a missile
# is integrate! (airframe) + observe! (seeker) + decide! (guidance)" (HANDOFF §3). The Autopilot
# runs the CASCADE — an OUTER pursuit law (the honest tail-chaser stand-in slice 10 replaces with
# PN) commanding a lateral accel, closed by an INNER PID autopilot through a first-order airframe
# lag — and writes `comp[:a_ctrl]` for the NEXT tick's BallisticMissile.integrate! (the guidance
# seam above). The airframe (impact/energy/attitude) is REUSED verbatim: a guided missile keeps
# `[BallisticMissile, Autopilot]` (phase-1 mover + phase-4 guidance), NOT a duplicating
# GuidedMissile. `pursuit_accel`/`autopilot_step` (the pure guidance.jl kernel) are the only physics.
#
# DETERMINISM (the slice-8 discipline — do NOT copy the slice-5/6/7 template): there is NO RNG in
# the missile arc, so "RNG lockstep" is VACUOUS. `:autopilot` is introduce-safe (absent an Autopilot
# nothing reads it → any slice-1..8 scenario byte-identical) but PHYSICS-CHANGING (a :ideal↔:pid
# toggle CHANGES the trajectory — the not-a-dead-knob property, the OPPOSITE of slices 5/6/7).
#
# NAMED APPROXIMATIONS (HANDOFF §1; the guidance-law ones live in guidance.jl): guidance reads
# TARGET TRUTH (no seeker — slice 11); the one-tick decide!→integrate! delay (tick 1 is ballistic —
# a free byte-identity anchor; the 1 ms control lag is negligible at guidance rate).
struct Autopilot <: Subsystem
    id::Symbol
end

# Phase 1: capture the tick `dt` into comp. `decide!` (phase 4) has NO dt argument, but the PID
# integrates at the tick dt (fixed-step). This is the ONLY reason the Autopilot touches phase 1 —
# it does NOT move the entity (BallisticMissile owns pos/vel). Keeping the capture HERE (not in
# BallisticMissile.integrate!) means a BALLISTIC slice-8 missile — which has no Autopilot — gets NO
# new comp key, so its determinism fingerprints stay byte-identical.
function integrate!(a::Autopilot, w::World, dt::Float64)
    w.entities[a.id].comp[:dt_s] = dt
    return nothing
end

# Phase 4: the closed guidance loop. Reads the missile + its nearest `:target` (`_nearest_target`,
# reused from radar.jl — truth-fed, no seeker), computes the OUTER pursuit command, runs the INNER
# PID (dispatch on `:autopilot`), clamps to `a_max`, and writes `comp[:a_ctrl]` (next tick) + the
# PID state. The readout goes into `w.env[:telemetry]` HERE — unlike the slice-8 energy readout
# (which had to move to build_env! because `empty!(w.env)` wipes phase-1 writes), a decide! write
# is AFTER the single empty! (tick contract), so it survives. The lesson is `track_gap` (commanded
# vs achieved), where the `1/(1+Kp)` undershoot is directly visible, NOT miss distance (advisor).
function decide!(a::Autopilot, w::World)
    e   = w.entities[a.id]
    c   = e.comp
    sid = String(a.id)
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    tgt = _nearest_target(w, e)

    # No target (misconfigured — load validates ≥1) or already impacted (engagement over): no
    # command, coast/frozen. Publish zero/finite telemetry so the readout never blanks.
    if tgt === nothing || get(c, :impacted, false)
        tel["$sid.a_cmd"]         = 0.0
        tel["$sid.a_ach"]         = 0.0
        tel["$sid.track_gap"]     = 0.0
        tel["$sid.los_range"]     = _finite(tgt === nothing ? 0.0 : los_range(e.pos, tgt.pos))
        tel["$sid.range_rate"]    = 0.0
        tel["$sid.a_demand"]      = 0.0                        # slice-10 keys — never stale
        tel["$sid.saturated"]     = 0.0
        tel["$sid.los_rate"]      = 0.0
        tel["$sid.closing_speed"] = 0.0
        return nothing
    end

    mode   = get(w.fidelity, :autopilot, :ideal)
    guid   = get(w.fidelity, :guidance, :pursuit)             # slice-10 OUTER law; DEFAULT :pursuit
    k_guid = Float64(get(c, :k_guid, 3.0))
    n_pn   = Float64(get(c, :n_pn, 4.0))                       # PN navigation constant (:pn only)
    r_stop = Float64(get(c, :r_stop, 0.0))                     # §2 endgame cutoff; DEFAULT 0 = no-op
    kp     = Float64(get(c, :kp, 2.0))
    ki     = Float64(get(c, :ki, 0.0))
    kd     = Float64(get(c, :kd, 0.0))
    tau    = Float64(get(c, :tau, 0.3))
    a_max  = Float64(get(c, :a_max, 3000.0))
    dt     = Float64(get(c, :dt_s, 1.0e-3))

    # Relative kinematics (TRUTH) — the seeker ω-source branch reads truth `Vc` from these (§ scope:
    # only the LOS ANGLE is noisy) and the telemetry below reuses them. Hoisted here from the old
    # inline telemetry site so the branch can read `Vc`; the truth `pn_accel` path is UNTOUCHED (it
    # computes its own r/v internally), so slice-10 stays byte-identical.
    rel_pos = tgt.pos - e.pos
    rel_vel = tgt.vel - e.vel

    # OUTER law → commanded lateral accel (§3 seam, slice 10 — the INNER PID below is UNCHANGED).
    # Select on `:guidance` (default `:pursuit` = the exact slice-9 path → byte-identical): PN leads
    # (nulls λ̇), pursuit tail-chases. The §2 terminal cutoff coasts the missile through the r→0
    # endgame (r_stop=0 default is an EXACT no-op → slice-9 unaffected); then clamp to a_max. In
    # slice10_pn a_max is generous (never binds); in slice10_glimit it BINDS ON PURPOSE — g-limit
    # saturation is the lesson, the deliberate inversion of slice 9's crash-guard-only clamp.
    #
    # SLICE-11 SEEKER SEAM: if the phase-3 `Seeker.observe!` wrote an estimate THIS tick
    # (`haskey(c, :seeker_omega)` — observe! ran before this phase-4 decide!), PN reads the seeker's
    # ω_est/û_est via `pn_accel_from_omega(û, ω, Vc)` (with TRUTH `Vc` — § scope) INSTEAD of truth
    # pos/vel. The `pn_accel_from_omega` arg order is û FIRST, ω SECOND (it computes `_cross(ω, û)` —
    # a swap would flip the command sign). Byte-identity for slices 1–10: with NO Seeker there is no
    # `:seeker_omega`, so this branch is never taken → the exact slice-10 truth `pn_accel`. The seeker
    # only overrides PN's ω-SOURCE, so it is gated on `guid === :pn` (pursuit reads the LOS directly,
    # no ω) — keeping `:seeker`/`:guidance`/`:autopilot` orthogonal.
    a_dem = if guid === :pn && haskey(c, :seeker_omega)
                pn_accel_from_omega(c[:seeker_los]::Vec3, c[:seeker_omega]::Vec3,
                                    -range_rate(rel_pos, rel_vel); N = n_pn)
            elseif guid === :pn
                pn_accel(e.pos, e.vel, tgt.pos, tgt.vel; N = n_pn)
            else
                pursuit_accel(e.pos, e.vel, tgt.pos; k_guid = k_guid)
            end
    a_dem = _terminal_cutoff(a_dem, los_range(e.pos, tgt.pos), r_stop)
    a_cmd = clamp_accel(a_dem, a_max)

    # INNER PID autopilot → achieved accel (dispatch on the fidelity rung).
    state = get(c, :ap_state, autopilot_init())::AutopilotState
    a_ach, state′ = autopilot_step(mode, a_cmd, state, dt; kp = kp, ki = ki, kd = kd, tau = tau)
    if mode === :pid
        # BOUND the plant: clamp the achieved accel and thread the CLAMPED value back as the plant
        # state, so a badly-tuned (diverging) discrete PID can't run a_ach → Inf → NaN in pos
        # (advisor). `e_int` is left unclamped (it winds up only harmlessly at any real tick count).
        a_ach  = clamp_accel(a_ach, a_max)
        state′ = (a_ach = a_ach, e_int = state′.e_int, e_prev = state′.e_prev)
    end
    c[:ap_state] = state′
    # :ideal returns a_ach == a_cmd (already clamped), so a_ctrl == a_cmd (perfect tracking, gap 0);
    # :pid uses the (already-clamped) plant output.
    a_ctrl = mode === :pid ? a_ach : clamp_accel(a_ach, a_max)
    c[:a_ctrl] = a_ctrl

    # Telemetry: the slice-9 keys (the tracking GAP) PLUS the slice-10 PN/saturation readouts. The
    # slice-10 lesson is MISS at CPA (isolated at :ideal — the verifier's job) + the saturation the
    # `a_demand`(pre-clamp) vs `a_cmd`(post-clamp) split makes visible. All `_finite`-clamped (no
    # Inf/NaN to JSON — the r→0 pre-clamp `a_demand` can be huge; §2 layer 3). `rel_pos`/`rel_vel`
    # are computed above (hoisted for the seeker branch).
    a_demand = _norm3(a_dem)                                   # PRE-clamp, POST-cutoff (saturation)
    tel["$sid.a_cmd"]         = _finite(_norm3(a_cmd))         # post-clamp (slice-9 key)
    tel["$sid.a_ach"]         = _finite(_norm3(a_ctrl))
    tel["$sid.track_gap"]     = _finite(_norm3(a_cmd - a_ctrl))
    tel["$sid.los_range"]     = _finite(los_range(e.pos, tgt.pos))
    tel["$sid.range_rate"]    = _finite_coord(range_rate(rel_pos, rel_vel))  # signed (neg = closing)
    tel["$sid.a_demand"]      = _finite(a_demand)              # PRE-clamp demand (the saturation tell)
    tel["$sid.saturated"]     = a_demand > a_max ? 1.0 : 0.0  # g-limit binding? (the Lesson-2 flag)
    tel["$sid.los_rate"]      = _finite(_norm3(los_rate(rel_pos, rel_vel)))  # ‖ω‖ (the PN driver)
    tel["$sid.closing_speed"] = _finite_coord(-range_rate(rel_pos, rel_vel))  # Vc (POSITIVE closing)
    return nothing
end

# --- the NOISY SEEKER: the missile's FIRST observe! (slice 11, HANDOFF §10 item 11) ------------
# "A missile is integrate! (airframe) + observe! (seeker) + decide! (guidance)" (HANDOFF §3): the
# Seeker fills the phase-3 observe! missile.jl:11 anticipated ("observe!/decide! stay EMPTY here —
# guidance/seekers are slices 9–11"), COMPLETING that sentence. It replaces slice 10's truth-fed PN
# (pn_accel reading target truth) with a MEASURED line-of-sight: the seeker senses the LOS *angle*
# with white angular noise (`sigma_seek`), and the α-β filter (estimation.jl `alpha_beta_los_step`)
# estimates the LOS *rate* λ̇ WITHOUT differentiating it — the whole slice-11 lesson (the `:raw`
# finite-difference foil amplifies the angle noise by 1/dt → PN's `N·Vc·λ̇` pegs `a_max`, the miss
# opens; the α-β filter recovers a smooth λ̇ → tight intercept).
#
# THE RNG INFLECTION — do NOT copy the slice-8/9/10 "RNG is VACUOUS" boilerplate; it INVERTS here.
# The Seeker is the FIRST `w.rng` consumer in the missile arc, so conventions 3 (unconditional draw)
# and 11 (own Xoshiro for MC) now APPLY. `observe!` draws ONE `randn(w.rng)` sample UNCONDITIONALLY
# every tick — a FIXED count invariant to the `:seeker` rung, the `sigma_seek`/`alpha`/`beta`
# sliders, target geometry, AND post-impact (the missile freezes but the target keeps moving, so
# observe! keeps running — the `detect_once`/`_draw_pseudoranges` "draw-then-gate-the-VALUE"
# template). Gate only the value PN consumes, never the draw. `:seeker` is a GENUINELY NEW
# fidelity-class combo (named at `SEEKER_MODES`, estimation.jl): DRAW-INVARIANT (class 4a — both
# rungs draw the same 1 sample, so `set_fidelity` may INTRODUCE it, UNLIKE `:cfar`) YET
# TRAJECTORY-CHANGING (a `:raw↔:filtered` toggle MOVES the missile — the slice-10 shape). Copy
# NEITHER the slice-5 "toggle-bit-identical" NOR the slice-8/9/10 "no-RNG" language. Byte-identity
# for slices 1–10 comes from the Seeker NOT EXISTING there, NOT a draw-skipping `:truth` rung (there
# is none; "truth-fed PN" IS slice 10 — no Seeker).
#
# SCALAR IN-PLANE (gate-0 FINDINGS decision 3): the engagement is planar in x-z, ω ∥ ±y, so the
# seeker tracks a SCALAR LOS angle `λ = atan(Δz, Δx)` and reconstructs `ω = Vec3(0, −λ̇, 0)` for PN
# (with r=(rx,0,rz), v=(vx,0,vz): `los_rate_y = (rz·vx − rx·vz)/r²` and `λ̇ = −ω_y`). Scalar avoids
# the vector form's tangent-injection / cross-innovation-sign / renormalize bug surface. `Vc` stays
# TRUTH (only the angle is noisy — one lesson per scenario, § scope; decide! supplies it).
struct Seeker <: Subsystem
    id::Symbol
end

# Phase 1: capture the tick `dt` into comp (the α-β predict step needs it; `observe!` has no `dt`
# arg — cf. `RadarSensor.observe!`). Its OWN capture key `:dt_s_seeker` (self-contained, advisor #4)
# — NOT a lean on the Autopilot's `:dt_s`, whose presence assumes the Autopilot is armed alongside
# the Seeker (the missile.jl `Autopilot.integrate!` dt-capture precedent). Does NOT move the entity.
function integrate!(s::Seeker, w::World, dt::Float64)
    w.entities[s.id].comp[:dt_s_seeker] = dt
    return nothing
end

# Phase 3: the missile's first sensor read. Draw the angle-noise sample UNCONDITIONALLY (convention
# 3), measure the noisy LOS angle, update BOTH the raw finite-difference memory AND the α-β filter
# state every tick (so a mid-run `:raw↔:filtered` toggle keeps both paths warm and stays
# draw-count-invariant — the rung selects only WHICH ω is written), and write the chosen ω/û into
# comp for the phase-4 `decide!` (the tick contract's phase order hands off THIS tick — no one-tick
# delay for the estimate; the seeker senses this tick's truth + noise). RNG-free after the one draw
# (the filter is deterministic post-processing).
function observe!(s::Seeker, w::World)
    e = w.entities[s.id]
    c = e.comp
    # CONVENTION 3 — the unconditional draw, FIRST, before any target/geometry/impact gate. A FIXED
    # 1 draw/tick (scalar in-plane; the vector form's 2 ⟂ draws are NOT used — FINDINGS decision 3).
    n = randn(w.rng)

    tgt = _nearest_target(w, e)
    tgt === nothing && return nothing        # no LOS to measure (load validates ≥1 target); draw taken

    dt = Float64(get(c, :dt_s_seeker, 1.0e-3))
    σ  = max(Float64(get(c, :sigma_seek, 3.0e-3)), 0.0)   # σ≥0 floor (a live slider can't go negative)
    α  = Float64(get(c, :alpha, 0.30))                    # α-β gains (load-validated 0<α<1, β>0; the
    β  = Float64(get(c, :beta,  0.05))                    # filter floors β/dt, so no consumer re-clamp)

    # Truth LOS in the x-z engagement plane and the noisy MEASURED angle (NOT wrapped — only the
    # filter's/raw's innovation-DIFFERENCE wraps; wrapping the absolute angle here is a needless op).
    û_tru  = los_unit(e.pos, tgt.pos)
    λ_tru  = atan(û_tru[3], û_tru[1])
    λ_meas = λ_tru + σ * n

    # Lazy first-tick init (the `e0_j` precedent): seed the raw memory + α-β state, λ̇ = 0 both paths.
    if !get(c, :seek_init, false)
        c[:seek_lambda_prev]   = λ_meas
        c[:seek_lambda_est]    = λ_meas
        c[:seek_lambdadot_est] = 0.0
        c[:seek_init]          = true
        λ̇_raw = 0.0
        λ_est = λ_meas; λ̇_est = 0.0
    else
        # RAW foil: finite-difference consecutive noisy angles (amplifies the angle noise by 1/dt).
        λ_prev = Float64(c[:seek_lambda_prev])
        λ̇_raw  = wrap_angle(λ_meas - λ_prev) / dt
        c[:seek_lambda_prev] = λ_meas
        # FILTERED: one α-β predict–correct step (updates state EVERY tick, both rungs → warm + invariant).
        λ_est = Float64(c[:seek_lambda_est]); λ̇_est = Float64(c[:seek_lambdadot_est])
        λ_est, λ̇_est = alpha_beta_los_step(λ_est, λ̇_est, λ_meas, dt; α = α, β = β)
        c[:seek_lambda_est]    = λ_est
        c[:seek_lambdadot_est] = λ̇_est
    end

    # The rung selects WHICH (λ̇, λ) PN consumes; the draw count is identical either way. Reconstruct
    # the in-plane `ω = Vec3(0, −λ̇, 0)` and `û = (cos λ, 0, sin λ)` from the CHOSEN rate/angle (a
    # CONSISTENT estimate source — FINDINGS decision f). `decide!` supplies TRUTH `Vc`.
    rung = get(w.fidelity, :seeker, :filtered)
    λ̇_used, λ_used = rung === :raw ? (λ̇_raw, λ_meas) : (λ̇_est, λ_est)
    c[:seeker_omega] = Vec3(0.0, -λ̇_used, 0.0)
    c[:seeker_los]   = Vec3(cos(λ_used), 0.0, sin(λ_used))

    # Seeker telemetry — phase-3 observe! is POST-`empty!(w.env)` (the radar-readout phase), so a
    # direct `w.env[:telemetry]` write survives. All SCALARS (no Array → no `float()`-crash in the
    # client). λ̇ is SIGNED → `_finite_coord`; σ is a magnitude → `_finite`.
    tel = get!(() -> Dict{String,Any}(), w.env, :telemetry)
    sid = String(s.id)
    tel["$sid.lambda_dot_raw"]  = _finite_coord(λ̇_raw)         # naïve finite-diff (jitters under :raw)
    tel["$sid.lambda_dot_filt"] = _finite_coord(λ̇_est)         # α-β estimate (smooth — always available)
    tel["$sid.lambda_dot_used"] = _finite_coord(λ̇_used)        # the one PN actually consumed this tick
    tel["$sid.sigma_seek"]      = _finite(σ)
    return nothing
end
