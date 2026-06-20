# world.jl — World, Entity, the canonical Vec3/Quat aliases, and the time model.
#
# Conventions (see HANDOFF.md §1, §3): everything here is SI, Float64, in the
# inertial frame. Quaternions are body<-inertial with identity = [1,0,0,0].
# Units/frames/signs are the bug trifecta — they are pinned here on purpose.

const Vec3 = SVector{3, Float64}            # inertial position / velocity, metres, m/s
const Quat = SVector{4, Float64}            # body<-inertial, identity = [1,0,0,0]

"""
    Entity(id, kind; pos, vel, att, comp)

A thing in the world. `comp` is a typed-by-convention bag of component
parameters (RCS, emitter params, seeker, ...) that subsystems read and write.
Physics lives in subsystems, not in the entity.
"""
mutable struct Entity
    id::Symbol
    kind::Symbol                            # :radar :target :jammer :missile :gps_sv :receiver ...
    pos::Vec3                               # m, inertial
    vel::Vec3                               # m/s, inertial
    att::Quat                               # quaternion body<-inertial
    comp::Dict{Symbol, Any}                 # component bag
end

Entity(id::Symbol, kind::Symbol;
       pos::Vec3 = zero(Vec3),
       vel::Vec3 = zero(Vec3),
       att::Quat = Quat(1, 0, 0, 0),
       comp::Dict{Symbol, Any} = Dict{Symbol, Any}()) =
    Entity(id, kind, pos, vel, att, comp)

"""
    World

The single source of truth. `env` is a derived blackboard cleared and rebuilt
every tick — cross-subsystem coupling flows through it, never through direct
calls between subsystems. `rng` is the one seeded stream that makes replay
bit-identical.
"""
mutable struct World
    t::Float64                              # sim time, s
    entities::Dict{Symbol, Entity}
    env::Dict{Symbol, Any}                  # DERIVED per-tick blackboard; cleared each tick
    events::Vector{Dict{Symbol, Any}}       # one-shot events emitted this tick
    rng::Xoshiro                            # the single seeded stream of truth
    fidelity::Dict{Symbol, Symbol}          # :propagation => :free_space, :detection => :analytic, ...
    seed::UInt64                            # remembered so reset! can restore the stream
end

"""
    World(; seed = 0, t = 0.0, fidelity = Dict())

Construct an empty world with a freshly-seeded RNG stream.
"""
function World(; seed::Integer = 0,
                 t::Float64 = 0.0,
                 fidelity::Dict{Symbol, Symbol} = Dict{Symbol, Symbol}())
    s = UInt64(seed)
    return World(t,
                 Dict{Symbol, Entity}(),
                 Dict{Symbol, Any}(),
                 Vector{Dict{Symbol, Any}}(),
                 Xoshiro(s),
                 fidelity,
                 s)
end

"""
    reset!(w; seed = w.seed)

Restore the RNG stream and clock so a scenario can be replayed bit-identically.
Entities are left to the scenario loader to repopulate.
"""
function reset!(w::World; seed::Integer = w.seed)
    w.seed = UInt64(seed)
    w.rng = Xoshiro(w.seed)
    w.t = 0.0
    empty!(w.env)
    empty!(w.events)
    return w
end
