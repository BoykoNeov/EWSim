# protocol.jl — the wire (HANDOFF.md §5).
#
# Framing, both directions: a 4-byte big-endian unsigned length prefix, then that
# many bytes of UTF-8 JSON. One JSON object per frame. That is the entire
# transport spec — small enough to read off the wire while debugging, which is
# why JSON beats msgpack here.

using JSON3

"""
    write_frame(io, obj) -> Int

Serialize `obj` to UTF-8 JSON, write a 4-byte big-endian length prefix and the
JSON bytes, and flush. Returns the payload length. Header + payload go out in
one `write` each; the OS may still split them across TCP segments — the reader
must not assume a frame arrives whole (see `read_frame`).
"""
function write_frame(io::IO, obj)::Int
    payload = Vector{UInt8}(JSON3.write(obj))
    n = length(payload)
    n ≤ typemax(UInt32) || error("frame too large: $n bytes")
    write(io, hton(UInt32(n)))        # 4-byte big-endian length
    write(io, payload)
    flush(io)
    return n
end

"""
    read_frame(io) -> JSON3.Object

Read a 4-byte big-endian length, then *exactly* that many payload bytes, then
parse. `read(io, UInt32)` and `read!` both block until the full count arrives, so
partial TCP segments are handled correctly. Throws `EOFError` on a clean
disconnect before a full frame — callers use that to detect the peer leaving.
"""
function read_frame(io::IO)
    n = ntoh(read(io, UInt32))                       # exact 4-byte read, big-endian
    payload = read!(io, Vector{UInt8}(undef, n))     # exact n-byte read
    return JSON3.read(payload)
end

# --- state frame (HANDOFF.md §5: server → client state stream) ---

# Entities are emitted in a stable (sorted-by-id) order so the wire output is
# reproducible frame-to-frame; the truth is `World`, not frame ordering.
function _entity_json(e::Entity)
    return Dict{Symbol,Any}(
        :id   => e.id,
        :kind => e.kind,
        :pos  => collect(e.pos),
        :att  => collect(e.att),
    )
end

"""
    state_frame(w; telemetry = Dict(), events = w.events) -> Dict

Build the `type = "state"` frame for the current world. `telemetry` is a flat
`string → number/bool` bag so any client can bind a readout to a key without a
schema change; `events` are one-shot (sent on the frame they occur, then cleared
by the server loop).
"""
function state_frame(w::World;
                     telemetry::AbstractDict = Dict{String,Any}(),
                     events = w.events)
    ents = [_entity_json(w.entities[id]) for id in sort!(collect(keys(w.entities)))]
    return Dict{Symbol,Any}(
        :type      => "state",
        :t         => w.t,
        :entities  => ents,
        :telemetry => telemetry,
        :events    => events,
    )
end
