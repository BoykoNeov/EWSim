# server.jl — the real interactive EWSim server entrypoint (HANDOFF §4; slice-1 step 7).
#
#   pwsh tools/julia.ps1 --project=core tools/server.jl [scenarios/slice1_roc.yaml] [port]
#
# Loads a scenario, warms the hot paths, then streams `state` frames to one connected
# client (Godot/Pluto) and applies its commands (§5). This is the headless twin the Godot
# Sandbox scene connects to. The EWSIM_SERVER_* stdout markers let an orchestrator gate on
# readiness (same pattern as tools/echo_server.jl).

using EWSim

scen = length(ARGS) ≥ 1 ? ARGS[1] :
       normpath(joinpath(@__DIR__, "..", "scenarios", "slice1_roc.yaml"))
port = length(ARGS) ≥ 2 ? parse(Int, ARGS[2]) : 8765

scn = load_scenario(scen)
srv = EWSim.Server(scn; path = scen)

println("EWSIM_SERVER_WARMING scenario=", scen); flush(stdout)
try
    run_server!(srv; port = port,
        ready = p -> (println("EWSIM_SERVER_LISTENING port=", p); flush(stdout)))
    println("EWSIM_SERVER_DONE"); flush(stdout)
catch e
    println("EWSIM_SERVER_ERROR ", sprint(showerror, e)); flush(stdout)
    rethrow()
end
