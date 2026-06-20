# subsystem.jl — the tick contract (HANDOFF.md §3).
#
# Every subsystem implements any SUBSET of four phase methods; defaults are
# no-ops. Ordering across phases is enforced by `tick!`, not self-reported by
# subsystems — that fixed ordering is what keeps runs deterministic. Subsystems
# never call each other; they communicate only through `w.env` and `w.entities`.

abstract type Subsystem end

# Phase 1 — advance kinematics / fuel / clocks.
integrate!(::Subsystem, ::World, ::Float64) = nothing
# Phase 2 — contribute to the derived RF/signal field (order-independent).
build_env!(::Subsystem, ::World)            = nothing
# Phase 3 — sensors read env+world -> measurements (seeded noise belongs here).
observe!(::Subsystem, ::World)              = nothing
# Phase 4 — estimators/guidance -> commands acted on next tick.
decide!(::Subsystem, ::World)               = nothing

"""
    tick!(w, subs, dt) -> w

Advance the world by one physics step. The four phases run in a fixed order
across all subsystems; `w.env` is rebuilt fresh in phase 2 each tick. This is
the unit of determinism — same seed + same subsystems + same dt ⇒ identical
trace.
"""
function tick!(w::World, subs::Vector{<:Subsystem}, dt::Float64)
    for s in subs; integrate!(s, w, dt); end    # 1. kinematics
    empty!(w.env)
    for s in subs; build_env!(s, w);    end     # 2. derive environment
    for s in subs; observe!(s, w);      end     # 3. sense
    for s in subs; decide!(s, w);       end     # 4. guide / estimate / act
    w.t += dt
    return w
end
