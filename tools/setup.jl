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
# Slice-1 deps. Random + Test are stdlibs (no download); StaticArrays is already
# in the depot. JSON3 / YAML / SpecialFunctions land when their slice-1 step does.
Pkg.add(["StaticArrays", "Random", "Test"])
Pkg.precompile()

println("\nSETUP DONE — project at ", CORE)
