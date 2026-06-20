# setup.jl — one-time project bootstrap.
#
# Creates core/Project.toml (name + generated uuid) if absent, then resolves the
# slice-1 dependencies into a Manifest. Run once:
#
#   pwsh tools/julia.ps1 tools/setup.jl
#
# Re-running is safe; it just re-resolves.

import Pkg
using UUIDs

const CORE = normpath(joinpath(@__DIR__, "..", "core"))
const PROJ = joinpath(CORE, "Project.toml")

if !isfile(PROJ)
    open(PROJ, "w") do io
        println(io, "name = \"EWSim\"")
        println(io, "uuid = \"", uuid4(), "\"")
        println(io, "authors = [\"BoykoNeov <boikoneov@gmail.com>\"]")
        println(io, "version = \"0.1.0\"")
    end
    @info "wrote new Project.toml" PROJ
end

Pkg.activate(CORE)
# Slice-1 deps. Random / Sockets / Test are stdlibs (no download); StaticArrays,
# JSON3 and YAML download once into the depot. Keep this list in sync with the
# steps as they land so a fresh clone resolves in one `setup.jl`.
Pkg.add(["StaticArrays", "Random", "Sockets", "Test", "JSON3", "YAML"])
Pkg.precompile()

println("\nSETUP DONE — project at ", CORE)
