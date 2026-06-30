# server.jl — the interactive socket run loop (HANDOFF §4, §5; the slice-1 step-7 prereq).
#
# This is the LIVE/interactive driver of the World: a Godot or Pluto client connects over
# TCP, the server ticks the World and streams `state` frames (§5), and commands flowing
# back (set_param / run / pause / step / set_seed / reset / load_scenario / run_batch)
# steer it. The headless/replay path (runtests, run_batch.jl) needs none of this — the
# truth is the World, and this loop is just one possible driver of it.
#
# SINGLE-MUTATOR DISCIPLINE (load-bearing, not tidiness). A reader task does exactly ONE
# thing: block on `read_frame` and enqueue parsed commands onto a Channel. ALL World
# mutation — both command handling and `tick!` — runs on the MAIN loop. That is what keeps
# World a single-mutator structure: no locks, and determinism survives because nothing
# races `tick!`. The reader is `@async` (cooperative, single OS thread) on purpose, so the
# no-race property is STRUCTURAL, not timing-dependent. If `handle_command!` ever moved
# into the reader task it would race the tick loop.

using Sockets

@enum RunMode PAUSED REALTIME FAST

# Cap on steps advanced per outer iteration: bounds REALTIME catch-up after a stall (no
# spiral-of-death) and chunks PAUSED/FAST so commands still interleave between batches.
const _MAX_CATCHUP = 10

# Wire mode string → RunMode (the §5 `run` command's `mode` field).
function _runmode(s)::RunMode
    m = Symbol(lowercase(String(s)))
    m === :paused   && return PAUSED
    m === :realtime && return REALTIME
    m === :fast     && return FAST
    error("server: unknown run mode '$s' (paused|realtime|fast)")
end

"""
    Server(scn; path = nothing, seed = scn.world.seed, mode = PAUSED, speed = 1.0)

The interactive driver around a loaded [`Scenario`](@ref). `scn` carries the
World+subsystems+timing; `path` is the YAML source — needed *only* for `reset` /
`load_scenario` reload, so it may be `nothing` for an in-memory scenario (e.g. a test
fixture). `seed` is held on the server so it SURVIVES a `reset` (the determinism contract:
`set_seed` then `reset` gives a clean replay at the chosen seed).
"""
mutable struct Server
    scn::Scenario
    path::Union{String,Nothing}
    mode::RunMode
    speed::Float64          # realtime multiplier
    step_budget::Int        # remaining steps for a `step(n)` while PAUSED
    step_count::Int         # steps since load; drives the `emit_every` gate
    seed::UInt64            # remembered across reset; `set_seed` updates it
end

Server(scn::Scenario; path = nothing, seed::Integer = scn.world.seed,
       mode::RunMode = PAUSED, speed::Real = 1.0) =
    Server(scn, path === nothing ? nothing : String(path),
           mode, Float64(speed), 0, 0, UInt64(seed))

# --- command handling (runs on the MAIN loop only) -------------------------------------

# Coerce a wire value to match an existing comp entry's type, so set_param on an integer
# knob (e.g. :swerling) doesn't silently turn it into a Float and break a `::Int` read.
_coerce_like(existing::Integer, v)      = Int(round(v))
_coerce_like(existing::AbstractFloat, v) = Float64(v)
_coerce_like(::Any, v)                   = v

# Rebuild the World+subsystems from the source YAML and re-apply the held seed + zero the
# clock/counters. `reset` routes through here, so a reset is always a clean, seeded start
# at `srv.seed` (which `set_seed` may have changed). Needs a path — an in-memory scenario
# has nothing to reload from.
function _reload!(srv::Server)
    srv.path !== nothing ||
        error("server: reset/load_scenario needs a scenario path (in-memory scenario)")
    srv.scn = load_scenario(srv.path)
    reset!(srv.scn.world; seed = srv.seed)   # override the YAML seed with the held one
    srv.step_count  = 0
    srv.step_budget = 0
    return srv
end

"""
    scenario_frame(srv) -> Dict

A small `type = "scenario"` handshake frame, sent on connect and after `load_scenario`,
so a client can build its sliders from the YAML knob list (min/max/label/log) without a
second source of truth. Also ships the World's `fidelity` map so a client can show the
"this is a <fidelity> approximation" badge §12 requires in every view — reflecting the
*actual* fidelity, not a hardcoded label. NB: this is an EXTENSION to the §5 command table
(which defines the state stream + the command set but no scenario-info reply) — kept tiny.
"""
function scenario_frame(srv::Server)
    scn = srv.scn
    # `value` is the knob's CURRENT comp setting (validated to exist at load), so a client's
    # slider opens at the live value instead of snapping to `min` and lying until first drag.
    knobs = [Dict{Symbol,Any}(:target => k.target, :key => k.key, :min => k.min,
                              :max => k.max, :label => k.label, :log => k.log,
                              :value => scn.world.entities[k.target].comp[k.key])
             for k in scn.knobs]
    frame = Dict{Symbol,Any}(:type => "scenario", :name => scn.name,
                             :dt_physics => scn.dt_physics, :emit_every => scn.emit_every,
                             :fidelity => copy(scn.world.fidelity), :knobs => knobs)
    # A CFAR scenario ships the STATIC range axis once here (it can't change frame-to-frame),
    # so the client labels its range-power plot's x-axis from core output without recomputing
    # any physics (HANDOFF §1). Only the noisy profile/threshold/detections are per-frame
    # telemetry. `nothing` for a non-CFAR scenario (the keys simply don't appear).
    info = _cfar_axis_info(scn.world)
    info === nothing || merge!(frame, info)
    return frame
end

# §5 `run_batch` command → `run_batch` kwargs. The wire spells the grid bounds
# `snr_db_grid_start/stop` (with trials/pfa_grid under `params`); the internal kwargs are
# `snr_db_start/stop`. MAP them — this is the one rename batch.jl's NB warns about (drop it
# and the bounds silently default to 0–20). `outdir`/`name` are accepted so a client (and
# the tests) can target a directory other than the shared default. Runs INLINE for slice 1
# (blocks the loop a couple seconds during the sweep): single-writer-safe, and matches
# batch.jl's documented single-threaded stance. The out-of-band Threads/@spawn seam (§4)
# lands when a slice actually needs the loop kept un-stalled.
function _run_batch_cmd(srv::Server, cmd)
    p = get(cmd, :params, Dict{Symbol,Any}())
    kwargs = Dict{Symbol,Any}(:kind => Symbol(get(cmd, :kind, "roc")))
    haskey(p, :target)            && (kwargs[:target]       = p[:target])
    haskey(p, :rcs_m2)            && (kwargs[:rcs_m2]       = p[:rcs_m2])
    haskey(p, :trials)            && (kwargs[:trials]       = Int(p[:trials]))
    haskey(p, :pfa_grid)          && (kwargs[:pfa_grid]     = Float64.(collect(p[:pfa_grid])))
    haskey(p, :snr_db_grid_start) && (kwargs[:snr_db_start] = Float64(p[:snr_db_grid_start]))
    haskey(p, :snr_db_grid_stop)  && (kwargs[:snr_db_stop]  = Float64(p[:snr_db_grid_stop]))
    haskey(p, :snr_db_grid_count) && (kwargs[:snr_db_count] = Int(p[:snr_db_grid_count]))
    haskey(p, :name)              && (kwargs[:name]         = String(p[:name]))
    haskey(p, :outdir)            && (kwargs[:outdir]       = String(p[:outdir]))
    return run_batch(srv.scn; kwargs...)   # already the §5 `type=artifact` descriptor frame
end

"""
    handle_command!(srv, cmd) -> Union{Nothing, Dict}

Apply one parsed client command (a JSON object) per the §5 command table, mutating
World/mode/seed in place. Returns a frame to send back (the artifact descriptor for
`run_batch`, the scenario frame for `load_scenario`) or `nothing`. Runs on the MAIN loop
only — see the single-mutator note at the top of this file.
"""
function handle_command!(srv::Server, cmd)
    typ = Symbol(String(cmd[:type]))
    w   = srv.scn.world

    if typ === :set_param
        target = Symbol(String(cmd[:target]));  key = Symbol(String(cmd[:key]))
        haskey(w.entities, target) || error("set_param: no entity '$target'")
        comp = w.entities[target].comp
        comp[key] = _coerce_like(get(comp, key, nothing), Float64(cmd[:value]))
        return nothing

    elseif typ === :set_fidelity
        # Live fidelity toggle — a slice-2 EXTENSION to the §5 table (mirrors the
        # scenario_frame precedent; §11 Tier A's "protocol doesn't change" holds for
        # YAML+reload, but *live* toggling needs this one command). VALIDATE here: a bad
        # value reaching `observe!` would throw inside `tick!`, and the session's outer
        # catch only swallows IO/EOF — so a tick-time error would kill the connection.
        # `LIVE_FIDELITY_MODES` is radar.jl's single per-key source of truth (no drift):
        # the key must be live-settable and the value one of its rungs.
        key = Symbol(String(cmd[:key]));  val = Symbol(String(cmd[:value]))
        modes = get(LIVE_FIDELITY_MODES, key, nothing)
        modes === nothing &&
            error("set_fidelity: '$key' is not live-settable " *
                  "($(join(keys(LIVE_FIDELITY_MODES), " | ")))")
        val in modes ||
            error("set_fidelity: $key '$val' unknown ($(join(modes, " | ")))")
        # Draw-topology guard (slice-3): `set_fidelity` may CHANGE the value of a fidelity
        # key already present, but must NOT INTRODUCE `:cfar` on a scenario that started
        # without it — that flips the legacy point path (2·N_p draws/target) to the profile
        # path (2·N_p·N_cells draws) and would desync a mid-run replay. Changing
        # `:propagation`'s value is always safe (same draw count either rung).
        (key === :cfar && !haskey(w.fidelity, :cfar)) &&
            error("set_fidelity: cannot introduce :cfar mid-run — a non-CFAR scenario draws " *
                  "a different RNG topology; load a CFAR scenario instead")
        w.fidelity[key] = val
        return nothing

    elseif typ === :set_seed
        srv.seed = UInt64(Int(cmd[:value]))
        w.rng = Xoshiro(srv.seed)            # reseed the stream in place; clock/entities untouched
        return nothing

    elseif typ === :run
        srv.mode = _runmode(get(cmd, :mode, "realtime"))
        haskey(cmd, :speed) && (srv.speed = Float64(cmd[:speed]))
        return nothing

    elseif typ === :pause
        srv.mode = PAUSED
        return nothing

    elseif typ === :step
        srv.mode = PAUSED                    # stepping is a paused-mode action
        srv.step_budget += max(0, Int(get(cmd, :n, 1)))
        return nothing

    elseif typ === :reset
        _reload!(srv)                        # fresh entities, held seed re-applied, clock zeroed
        return nothing

    elseif typ === :load_scenario
        srv.path = String(cmd[:path])
        srv.scn  = load_scenario(srv.path)
        srv.seed = srv.scn.world.seed        # adopt the NEW scenario's seed
        srv.step_count = 0;  srv.step_budget = 0
        srv.mode = PAUSED
        return scenario_frame(srv)

    elseif typ === :run_batch
        return _run_batch_cmd(srv, cmd)

    else
        error("server: unknown command type '$typ'")
    end
end

# --- pacing (pure math, unit-tested directly) ------------------------------------------

"""
    steps_this_iteration(srv, wall_dt) -> Int

How many physics steps to advance this outer iteration, by mode:
  • `PAUSED`   — only a queued `step` budget (capped per iter so commands still interleave);
  • `REALTIME` — pace to wall clock: `wall_dt · speed / dt`, capped so a long stall can't
                 trigger a spiral-of-death catch-up;
  • `FAST`     — a fixed chunk (the emit cadence) per iteration, so the loop yields and
                 drains commands between chunks instead of running away.
Pure function of (mode, speed, budget, dt, emit_every, wall_dt).
"""
function steps_this_iteration(srv::Server, wall_dt::Float64)
    cap = srv.scn.emit_every * _MAX_CATCHUP
    if srv.mode === PAUSED
        return clamp(srv.step_budget, 0, cap)
    elseif srv.mode === REALTIME
        return clamp(round(Int, wall_dt * srv.speed / srv.scn.dt_physics), 0, cap)
    else  # FAST
        return srv.scn.emit_every
    end
end

# --- the socket loop -------------------------------------------------------------------

# Reader task: parse frames → enqueue. NEVER mutates the World (single-mutator rule). Ends
# on a clean disconnect (EOFError) or a closed socket (IOError); closes the channel so the
# main loop sees the peer left.
function _reader_loop(sock, cmds::Channel)
    try
        while true
            put!(cmds, read_frame(sock))
        end
    catch e
        (e isa EOFError || e isa Base.IOError || e isa InvalidStateException) || rethrow()
    finally
        isopen(cmds) && close(cmds)
    end
end

# Drive one connected client to completion (returns on clean disconnect / EOF). Owns all
# World mutation and all socket writes; the reader task only feeds it commands.
function _serve_session!(srv::Server, sock)
    cmds   = Channel{Any}(128)
    reader = @async _reader_loop(sock, cmds)
    try
        write_frame(sock, scenario_frame(srv))      # handshake: client builds its sliders first
        last_wall = time()
        while isopen(sock)
            # 1. drain queued commands — the main loop is the sole World mutator. A bad/
            #    unknown command must NOT tear down the session (one GDScript typo would kill
            #    the server mid-debug): report it on an `error` frame and keep serving. A
            #    write failure (IOError) is the peer leaving — let it reach the outer catch.
            while isready(cmds)
                local resp
                try
                    resp = handle_command!(srv, take!(cmds))
                catch e
                    e isa Base.IOError && rethrow()
                    write_frame(sock, Dict{Symbol,Any}(:type => "error",
                                                       :message => sprint(showerror, e)))
                    continue
                end
                resp === nothing || write_frame(sock, resp)
            end
            (!isopen(cmds) && !isready(cmds)) && break   # reader hit EOF and we've drained → peer gone

            # 2. advance + emit. Events are one-shot: cleared right after the frame they
            #    ship on. (Wart, accepted: under emit_every batching an event's stamped :t
            #    can lag its real tick by up to emit_every·dt (~16 ms) — fine for a blip.)
            now = time();  wall_dt = now - last_wall;  last_wall = now
            n = steps_this_iteration(srv, wall_dt)
            for _ in 1:n
                tick!(srv.scn.world, srv.scn.subs, srv.scn.dt_physics)
                srv.step_count += 1
                if srv.step_count % srv.scn.emit_every == 0
                    write_frame(sock, state_frame(srv.scn.world))
                    empty!(srv.scn.world.events)
                end
            end
            srv.mode === PAUSED && (srv.step_budget -= n)

            yield()                                       # let the reader run even in FAST (so `pause` lands)
            # idle: don't busy-spin a core. Sleep whenever no steps ran (PAUSED with no
            # budget, OR REALTIME whose sub-ms wall_dt rounds to 0 steps — the default play
            # mode, so this is the one that would otherwise peg 100% CPU). FAST runs flat out.
            (srv.mode !== FAST && n == 0) && sleep(0.005)
        end
    catch e
        (e isa Base.IOError || e isa EOFError) || rethrow()   # peer vanished mid-write
    finally
        close(sock)                  # unblock the reader → it closes `cmds` and exits
        try; wait(reader); catch; end
    end
    return srv
end

# Accept ONE client on an already-bound listener and serve it (no warmup/listen here, so a
# test can drive it on its own `listenany` socket without a fixed port).
function _accept_serve!(srv::Server, listener)
    sock = accept(listener)
    try
        _serve_session!(srv, sock)
    finally
        close(sock)
    end
    return srv
end

"""
    warmup!(srv) -> srv

Pay Julia's first-call compilation for the hot paths (one `tick!` + the `state_frame`
round-trip + a tiny ROC batch) before a client connects, so the first interactive
round-trip never races the compiler (the §12 TTFX watch-item). Operates on a `deepcopy`
of the World and a `mktempdir` for the batch, so warming NEVER perturbs the live World or
clobbers the real `shared/roc_radar1.bin`.

The `tick!`+`state_frame` warm covers EVERY scenario's interactive hot path (incl. slice-5's
phase-4 `decide!`→`Geolocator`→`bearings_fix`). The ROC batch warm is **radar-specific**
(`run_batch kind=:roc` resolves a radar) — a radar-free DF scenario (slice 5) has none, so
guard it on a radar's presence rather than crash `warmup!` (which would kill the server before
it ever listened). A DF scenario never runs a ROC sweep, so skipping it warms nothing it needs.
"""
function warmup!(srv::Server)
    snap = deepcopy(srv.scn.world)
    tick!(snap, srv.scn.subs, srv.scn.dt_physics)
    let io = IOBuffer()
        write_frame(io, state_frame(snap)); seekstart(io); read_frame(io)
    end
    if any(e -> e.kind === :radar, values(srv.scn.world.entities))
        mktempdir() do dir                        # tiny sweep into a tempdir → real artifact untouched
            run_batch(srv.scn; kind = :roc, pfa_grid = [1.0e-6], snr_db_count = 2,
                      trials = 16, outdir = dir, name = "warmup")
        end
    end
    return srv
end

"""
    run_server!(srv; port = 8765, ready = nothing) -> srv

Warm up, listen on `127.0.0.1:port`, accept ONE client (single-client v1; multiplex
later), and serve it via the §4 loop until it disconnects. `ready`, if given, is called
with the bound port once listening (the headless runner prints a marker; a test passes a
callback). Returns when the client leaves.
"""
function run_server!(srv::Server; port::Integer = 8765, ready = nothing)
    warmup!(srv)
    listener = listen(ip"127.0.0.1", UInt16(port))
    try
        ready === nothing || ready(Int(port))
        _accept_serve!(srv, listener)
    finally
        close(listener)
    end
    return srv
end
