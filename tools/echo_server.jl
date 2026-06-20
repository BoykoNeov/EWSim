# echo_server.jl — throwaway server whose only job is to prove the Godot↔Julia
# socket seam (HANDOFF §12, slice-1 step 3). It is NOT the real server; it just
# round-trips frames so the Godot client's framing can be verified against a
# known-good Julia peer.
#
#   pwsh tools/julia.ps1 tools/echo_server.jl
#
# Stdout markers (EWSIM_ECHO_*) let an orchestrator gate on readiness and result.

using EWSim
using Sockets

const PORT = 8765

function serve_one(server)
    conn = accept(server)
    println("EWSIM_ECHO_CLIENT_CONNECTED"); flush(stdout)
    nframes = 0
    try
        while true
            f = read_frame(conn)                       # EOFError on clean disconnect
            # Reply from PRIMITIVE fields only — never re-serialize the parsed
            # object, so a JSON nesting bug can't masquerade as a seam failure.
            seq = haskey(f, :seq) ? f.seq : -1
            write_frame(conn, Dict("type" => "echo", "seq" => seq, "server_t" => time()))
            nframes += 1
            println("EWSIM_ECHO_FRAME seq=", seq); flush(stdout)
        end
    catch e
        e isa EOFError || rethrow()
    finally
        close(conn)
    end
    println("EWSIM_ECHO_DONE frames=", nframes); flush(stdout)
end

function main()
    # Pay framing TTFX once before announcing readiness, so the client's first
    # round-trip isn't racing Julia's compiler.
    let io = IOBuffer()
        write_frame(io, Dict("warmup" => true)); seekstart(io); read_frame(io)
    end
    server = listen(ip"127.0.0.1", PORT)
    println("EWSIM_ECHO_LISTENING port=", PORT); flush(stdout)
    try
        serve_one(server)
    finally
        close(server)
    end
end

main()
