# run_batch.jl — generate the ROC artifact headless, no client (HANDOFF §7, step 6).
#
#   pwsh tools/julia.ps1 --project=core tools/run_batch.jl [scenarios/slice1_roc.yaml]
#
# Writes shared/roc_radar1.bin + roc_radar1.meta.json (the full 3 × 64 grid the Pluto
# notebook reads). This is the headless twin of the server's `run_batch` command — the
# socket path lands with server.jl (step 7); the physics + artifact are identical.

using EWSim

scen = length(ARGS) ≥ 1 ? ARGS[1] :
       normpath(joinpath(@__DIR__, "..", "scenarios", "slice1_roc.yaml"))

scn  = load_scenario(scen)
desc = run_batch(scn; kind = :roc)        # defaults: 3 Pfa × 64 SNR (0–20 dB) × 100k trials

println("scenario : ", scen)
println("artifact : ", desc[:path])
println("meta     : ", first(splitext(desc[:path])) * ".meta.json")
println("shape    : ", desc[:shape], "   axes=", desc[:axes])
println("swerling : ", desc[:swerling], "   trials=", desc[:trials])
println("pfa_grid : ", desc[:pfa_grid])
println("snr_db   : ", desc[:snr_db_grid][1], " … ", desc[:snr_db_grid][end],
        " (", length(desc[:snr_db_grid]), " pts)")
