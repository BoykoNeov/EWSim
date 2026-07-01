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
include("radar.jl")
include("esm.jl")
include("geolocation.jl")
include("gps.jl")
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
# GPS shared-lib reuse (slice 7): N-dim solver siblings + GPS pseudorange positioning
export dop, dop_components
export sat_az_el, iono_delay, tropo_delay, mp_scale, pseudorange
export position_fix, raim_statistic, raim_suspect, raim_solve, GPS_TOGGLE, RAIM_MODES
# Multi-emitter EW / PRI deinterleaving shared lib (slice 6): difference histogram +
# cdif/sdif PRI extraction + pulse↔emitter association
export difference_histogram, detect_pris, associate, assoc_pct, DEINTERLEAVER_MODES, SPURIOUS_ID
# Slice-1 subsystems + scenario loader (Jammer is the slice-4 build_env! subsystem;
# DFSensor/Geolocator are the slice-5 observe!→decide! DF pair that light phase 4)
export ConstantVelocity, RadarSensor, Jammer, DFSensor, Geolocator, Knob, Scenario, load_scenario
# Multi-emitter EW subsystems (slice 6): the phase-2+3+4 capstone pipeline
export PulseEmitter, ESMReceiver, Deinterleaver
# GPS subsystems (slice 7): the §9 cross-domain reuse pipeline (build_env!→observe!→decide!)
export GpsSatellite, GpsReceiver, GpsSolver
# Offline batch sweeps (ROC artifact + slice-2 coverage diagram)
export run_batch, roc_grid, load_roc, coverage_grid, load_coverage
# Interactive socket run loop (the live/driver path)
export Server, run_server!, RunMode, PAUSED, REALTIME, FAST, scenario_frame

end # module EWSim
