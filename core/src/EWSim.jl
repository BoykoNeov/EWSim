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
include("radar.jl")
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
# Detection
export detection_threshold, pd_analytic, pd_montecarlo, detect_once
# Slice-1 subsystems + scenario loader
export ConstantVelocity, RadarSensor, Knob, Scenario, load_scenario
# Offline batch sweeps (ROC artifact + slice-2 coverage diagram)
export run_batch, roc_grid, load_roc, coverage_grid, load_coverage
# Interactive socket run loop (the live/driver path)
export Server, run_server!, RunMode, PAUSED, REALTIME, FAST, scenario_frame

end # module EWSim
