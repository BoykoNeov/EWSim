# run_coverage.jl — generate the slice-2 coverage artifact headless (slice 2 stretch).
#
#   pwsh tools/julia.ps1 --project=core tools/run_coverage.jl [scenarios/slice2_tworay.yaml]
#
# Writes shared/coverage_radar1.bin + coverage_radar1.meta.json — a range×altitude SNR
# grid, computed two ways (free_space + two_ray) — that the Pluto notebook
# (clients/notebooks/slice2_coverage.jl) reads back and plots as side-by-side heatmaps.
# The headless twin of the ROC's run_batch.jl; same physics as the live radar (the grid
# is pinned against `_target_snr` in test_batch.jl), just swept offline over geometry.
#
# Defaults (radar mast h_r from the scenario): ground range 10–80 km, altitude 0–600 m
# at 400×480. That window frames the LOW-elevation band where the lobe fan is teachable:
# a 30 m X-band mast packs ~940 lobes over the upper hemisphere, so short-range/high-
# altitude (high elevation angle) aliases into moiré, while 10–80 km × 0–600 m keeps
# ~2–4 grid cells per lobe and centres the scenario's 100 m target in the lobing band.
# Tune via the kwargs (range_start/stop/count, alt_start/stop/count) below.

using EWSim

scen = length(ARGS) ≥ 1 ? ARGS[1] :
       normpath(joinpath(@__DIR__, "..", "scenarios", "slice2_tworay.yaml"))

scn  = load_scenario(scen)
desc = run_batch(scn; kind = :coverage)   # defaults: 300 range × 400 alt × 2 (free_space, two_ray)

rng = desc[:range_grid]
alt = desc[:alt_grid]
println("scenario : ", scen)
println("artifact : ", desc[:path])
println("meta     : ", first(splitext(desc[:path])) * ".meta.json")
println("shape    : ", desc[:shape], "   axes=", desc[:axes])
println("rcs_m2   : ", desc[:rcs_m2], "   h_r=", desc[:h_r], " m   refl=", desc[:refl])
println("range    : ", rng[1] / 1e3, " … ", rng[end] / 1e3, " km (", length(rng), " pts)")
println("altitude : ", alt[1], " … ", alt[end], " m (", length(alt), " pts)")
println("horizon  : ground range > ", round(horizon_range(desc[:h_r], 0.0) / 1e3; digits = 1),
        " km is below the 4/3-Earth horizon at sea level (rises with target altitude)")
