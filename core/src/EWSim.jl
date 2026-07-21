"""
    EWSim

Headless Julia simulation core for the EWSim teaching-through-play simulator.
The "truth" lives here — physics, RNG, scenario state, the fixed-dt tick loop —
and is reachable with no GUI (`core/test/runtests.jl` is the contract enforcer).

See HANDOFF.md for the architecture and the design commitments. Clients (Godot,
Pluto) are thin and replaceable; nothing in this module knows they exist.
"""
module EWSim

using StaticArrays
using Random

include("world.jl")
include("subsystem.jl")
include("protocol.jl")
include("rf.jl")
include("detection.jl")
include("geometry.jl")
include("estimation.jl")
include("deinterleave.jl")
include("gnss.jl")
include("frames.jl")
include("dynamics.jl")
include("aero_curve.jl")
include("airframe.jl")
include("airframe3d.jl")
include("atmosphere.jl")
include("terrain.jl")
include("guidance.jl")
include("radar.jl")
include("esm.jl")
include("geolocation.jl")
include("gps.jl")
include("missile.jl")
include("scenario.jl")
include("batch.jl")
include("server.jl")

# World + types
export Vec3, Quat, Entity, World, reset!
# Tick contract
export Subsystem, integrate!, build_env!, observe!, decide!, tick!
# Wire protocol
export write_frame, read_frame, state_frame
# RF / link budget
export RadarParams, snr_freespace, snr_db_freespace, wavelength, db2lin, lin2db
# RF / two-ray propagation (slice 2)
export snr_two_ray, snr_db_two_ray, two_ray_phase, two_ray_factor4, horizon_range
# RF / jamming + burn-through (slice 4)
export jam_noise_ratio, antenna_gain, burnthrough_range
# Detection
export detection_threshold, pd_analytic, pd_montecarlo, detect_once
# CFAR adaptive thresholding (slice 3)
export cfar_alpha, cfar_threshold, cfar_scan
# DF / geolocation shared libs (slice 5): geometry/DOP + estimation scaffold
export bearing, wrap_angle, eig2x2, error_ellipse, gdop, FINITE_CEIL
export linear_ls, gauss_newton, bearings_fix, ESTIMATOR_MODES
export alpha_beta_los_step, SEEKER_MODES
# Countermeasures — the :scan seeker angular-profile processing primitives (slice 13 gate 1)
export angular_grid, paint_angular_profile!, intensity_centroid, extract_peaks, validation_gate, DISCRIMINATION_MODES
# GPS shared-lib reuse (slice 7): N-dim solver siblings + GPS pseudorange positioning
export dop, dop_components
export sat_az_el, iono_delay, tropo_delay, mp_scale, pseudorange
export position_fix, raim_statistic, raim_suspect, raim_solve, GPS_TOGGLE, RAIM_MODES
# Multi-emitter EW / PRI deinterleaving shared lib (slice 6): difference histogram +
# cdif/sdif PRI extraction + pulse↔emitter association
export difference_histogram, detect_pris, associate, assoc_pct, DEINTERLEAVER_MODES, SPURIOUS_ID
# Missile frame / LOS shared lib (slice 8, §9): quaternion algebra + inertial↔body
# transforms + the sign-critical LOS kernel (slices 10–13 ride this)
export qmul, qconj, qinv, qnormalize, quat_from_axis_angle, quat_from_two_vectors
export rotate, rotate_inv, los_unit, los_range, range_rate, los_rate, az_el
# Missile airframe dynamics (slice 8): force model + fixed-step integrators
export gravity_accel, drag_accel, total_accel, rk4_step, euler_step, integrator_step
export INTEGRATOR_MODES, G_ACCEL
# Pitch-plane ROTATIONAL dynamics (slice 16, §11 Tier A — the 6-DOF airframe's first half):
# aero pitching moment + rotational integrator + the short-period/trim closed forms.
# `AirframeParams` is an authored-input record (the RadarParams precedent — exported).
export AirframeParams, pitch_moment, rk4_rot, airframe_step, short_period_freq, trim_alpha
# Slice 17 (§11 Tier A): the α→lift→γ coupling — body lift ⟂ v + the joint 8-scalar RK4 stepper
# + the `:airframe = point_mass | pitch_coupled` fidelity list. `AirframeParams` gains `Cla`.
export lift_accel, rk4_coupled, AIRFRAME_MODES
# Slice 19 (§11 Tier A): the INNER α/g autopilot — the aero inversion `a_cmd → α_cmd → δ` +
# the flight-condition g-limit `a_max_aero = Q·S·C_Lα·α_max/m` (THE lesson's headline readout).
# `AirframeParams` gains NO field — α_max and the loop gains are LIMITS, not aero coefficients
# (they ride in comp and arrive as kwargs).
export alpha_command, aero_accel_limit, alpha_autopilot_delta
# Slice 20 (§11 Tier A): INDUCED DRAG — the bill for the lift (C_Di = K·C_L², along −v̂), which
# cashes slices 17/19's explicit "lift is drag-free / speed-preserving" approximation: pull α →
# bleed V → Q falls → the ceiling falls. The project's first DEGENERATIVE SPIRAL — NOT a
# "positive-feedback loop": the speed bleed is SELF-LIMITING (∝V²α² ⇒ V asymptotes; see airframe.jl).
# `AirframeParams` gains `K` (LAST field, 0 ⇒ drag-free = slices 17/19). NO new fidelity rung —
# `af_k_induced` is a KNOB (the slice-16 `af_cma` precedent: a rung must name physics the knob
# cannot express, and `:free` IS `K = 0`).
export induced_drag_accel
# Slice 21 (§11 Tier A): the EXPONENTIAL ATMOSPHERE ρ(z) = ρ₀·exp(−z/H) — the honest completion
# of slices 19/20's constant-ρ, which makes "high altitude" a REAL lever (the missile's own
# CLIMB moves Q, and the maneuver ceiling with it) instead of a phrase the docs forbid. Unlike
# slice 16's `af_cma` / slice 20's `af_k_induced` this DOES get a rung: constant ρ is `H = ∞`, a
# LIMIT POINT no slider value reaches, and it is a distinct code path (atmosphere.jl's header
# records the general knob-vs-rung discriminator). `H` is the severity knob on the
# `:exponential` arm. NOT §11's RF "layered atmosphere/ducting" — that is the `propagation` knob.
export air_density, ATMOSPHERE_MODES
# Slice 22 (§11 Tier A): NONLINEAR AERO — true stall, separation drag and the Cm(α) break, which
# closes the LINEAR-aero deferral slices 19/20/21 all carried explicitly. The airframe finally
# sets its own ceiling: C_L PEAKS at α_stall and FALLS, so pulling harder past the stall buys
# LESS turn. ⭐ The headline is an ALGEBRAIC identity — ceiling ratio ≡ α_stall/α_max, with Q, S,
# C_Lα and m ALL cancelling (slice 21's ρ-factor in a new letter). ⚠ NO fidelity rung and NO mode
# tuple, MEASURED not assumed (the plan's rung claim LOST at gate 0): unlike slice 21's `H`, a
# corner CAN be parked out of reach — α_stall ≥ ~0.25 is linear-in-effect over every reachable
# state — so slice 21's own knob-vs-rung discriminator returns KNOB, exactly like slice 16's
# `af_cma` and slice 20's `af_k_induced`. `AirframeParams` is deliberately NOT merged with
# `AeroCurveParams` (slices 1–21 construct it untouched).
export AeroCurveParams, lift_coefficient, cl_peak, separation_drag_coefficient, moment_coefficient
# Slice 22 gate 2 — the LOCAL ∂Cm/∂α (the ONE source both readout linearizations take their slope
# from) and the NONLINEAR-AERO SIBLINGS. Each `_nl` twin branches AROUND its linear original, which
# is left TEXTUALLY VERBATIM (the multiply-grouping byte-identity trap this project has caught
# twice). `separation_drag_accel` is the NEW additive post-stall term — mandatory, not optional:
# lift-collapse + drag-rise IS what stall is. ⚠ `alpha_command` is deliberately NOT in this list —
# the autopilot's inversion stays LINEAR (a stall-aware autopilot is a named deferral).
export moment_slope, lift_accel_nl, induced_drag_accel_nl, separation_drag_accel, pitch_moment_nl,
       short_period_freq_nl, trim_alpha_nl
# Slice 23 (§11 Tier A): the 6-DOF SUBSTRATE + SKID-TO-TURN (airframe3d.jl) — the 3-D superset of
# the pitch-plane airframe. `att` becomes a genuine quaternion integrated from a body-rate ω, the
# guidance command keeps its full 3-D direction (the pitch-plane "discard" DIES), and STT makes
# lift in BOTH body planes (α→pitch, β→yaw). `AIRFRAME_MODES` gains `:six_dof`; `AirframeParams`
# is UNTOUCHED (C_Yβ rides as a kwarg defaulting to C_Lα — symmetric cruciform). Class 4c.
export body_incidence, body_perp_axes, lift_accel_3d, attitude_kinematics, body_rate_deriv,
       stt_moments, rk4_6dof, steering_command, pitch_rate_phys, yaw_rate_phys
# Slice 24 (§11 Tier A): BANK-TO-TURN + roll-lag — the steering law that must ROLL to point its
# single lift plane before it can turn. STT (slice 23) points lift in two planes at once; BTT makes
# lift in ONE plane (α only, β→0 coordinated) and banks with FINITE bandwidth τ_roll → against the
# same out-of-plane target BTT MISSES where STT hit. `STEERING_MODES = (:skid_to_turn, :bank_to_turn)`
# is the NEW `:steering` rung (inert without `:airframe:six_dof`); τ_roll the knob; ζ = 1 the sole-
# lever approximation. `AirframeParams` UNTOUCHED (I_xx/τ_roll ride in comp, arrive as kwargs). 4c.
export STEERING_MODES, bank_angle, steering_bank_command, btt_roll_moment, btt_moments
# Missile guidance (slice 9): the outer pursuit law + the inner PID autopilot (pure).
# `AutopilotState` is an INTERNAL state record (the JamContribution/BearingRecord precedent —
# not exported); `autopilot_init` IS exported (the test constructs the zero state bare).
export pursuit_accel, autopilot_step, clamp_accel, autopilot_init, AUTOPILOT_MODES
# Slice 10: the OUTER proportional-navigation law (pursuit_accel's sibling) + its fidelity rungs.
export pn_accel, pn_accel_from_omega, GUIDANCE_MODES
# Slice 12: augmented PN — TPN + (N/2)·a_T⊥ target-accel feedforward (the :apn rung).
export pn_accel_augmented
# Slice 14 (capstone): cooperative salvo — time-to-go + impact-time-control (the :salvo rung).
export time_to_go, salvo_consensus, impact_time_control_accel, COOPERATION_MODES
# Slice 18 (§11 Tier A): the authored Gaussian-hill heightfield + sampled-profile LOS
# occlusion (the :terrain propagation rung's pure primitives + the handshake grid).
export TerrainParams, terrain_height, terrain_clearance, terrain_los_clear, terrain_grid
# Slice 15 (§11 Tier A): the rate-limited fin servo (the :fin autopilot rung). `FinState` follows
# `AutopilotState` (INTERNAL state record — not exported); `fin_actuator_init` IS exported (bare
# zero-state construction in the test). `AUTOPILOT_MODES` (already exported) gains :fin.
export fin_autopilot_step, fin_actuator_init
# Slice-1 subsystems + scenario loader (Jammer is the slice-4 build_env! subsystem;
# DFSensor/Geolocator are the slice-5 observe!→decide! DF pair that light phase 4)
export ConstantVelocity, RadarSensor, Jammer, DFSensor, Geolocator, Knob, Scenario, load_scenario
# Multi-emitter EW subsystems (slice 6): the phase-2+3+4 capstone pipeline
export PulseEmitter, ESMReceiver, Deinterleaver
# GPS subsystems (slice 7): the §9 cross-domain reuse pipeline (build_env!→observe!→decide!)
export GpsSatellite, GpsReceiver, GpsSolver
# Missile subsystems: the ballistic airframe (slice 8, phase 1) + the guided Autopilot
# (slice 9, phase 4 — the missile's first decide!: outer pursuit + inner PID) + the noisy
# Seeker (slice 11, phase 3 — the missile's first observe!: noisy LOS + α-β LOS-rate filter) +
# the ManeuveringTarget curving mover (slice 12, phase 1 — the augmented-PN foil) + the
# SalvoCoordinator cooperative-guidance shared-state node (slice 14, phase 2 — the capstone datalink)
export BallisticMissile, Autopilot, Seeker, ManeuveringTarget, SalvoCoordinator
# Offline batch sweeps (ROC artifact + slice-2 coverage diagram)
export run_batch, roc_grid, load_roc, coverage_grid, load_coverage
# Interactive socket run loop (the live/driver path)
export Server, run_server!, RunMode, PAUSED, REALTIME, FAST, scenario_frame

end # module EWSim
