# runtests.jl — the contract enforcer (HANDOFF.md §1, §13).
#
# Every model ships with a test that checks it against an analytic truth or the
# determinism contract. If it can't run here with no GUI, it's in the wrong place.
#
# Run:  pwsh tools/test.ps1     (or)     julia --project=core core/test/runtests.jl

using Test
using EWSim
using StaticArrays
using Random

@testset "EWSim" begin
    include("test_determinism.jl")
    include("test_protocol.jl")
    # slice 1 adds: test_radar_eq.jl, test_detection.jl, test_frames.jl
end
