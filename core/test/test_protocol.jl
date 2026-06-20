# test_protocol.jl — wire framing is the #1 integration risk (HANDOFF §12),
# so it gets pinned Julia-side before any client touches it. These tests assert
# the exact byte layout, not just round-trip success — endianness bugs hide in
# round-trips that happen to be symmetric.

using EWSim
using JSON3
using Sockets

@testset "protocol" begin

    @testset "round-trip through a buffer" begin
        msg = Dict("type" => "hello", "seq" => 7, "payload" => "jULiA↔godot ✓",
                   "vec" => [1.0, -2.5, 3.0])
        io = IOBuffer()
        n = write_frame(io, msg)
        seekstart(io)
        got = read_frame(io)
        @test String(got.type) == "hello"
        @test got.seq == 7
        @test String(got.payload) == "jULiA↔godot ✓"     # non-ASCII survives UTF-8
        @test collect(Float64.(got.vec)) == [1.0, -2.5, 3.0]
        @test eof(io)                                     # consumed exactly the frame
    end

    @testset "header is 4-byte big-endian length" begin
        io = IOBuffer()
        write_frame(io, Dict("a" => 1))
        bytes = take!(io)
        payload_len = length(bytes) - 4
        hdr = bytes[1:4]
        @test ntoh(reinterpret(UInt32, hdr)[1]) == payload_len    # big-endian decode
        # most-significant byte first: a small payload has 0x00 0x00 0x00 in front
        @test hdr[1] == 0x00 && hdr[2] == 0x00 && hdr[3] == 0x00
        @test hdr[4] == UInt8(payload_len)
    end

    @testset "two frames in one stream delimit cleanly" begin
        io = IOBuffer()
        write_frame(io, Dict("i" => 1))
        write_frame(io, Dict("i" => 2))
        seekstart(io)
        @test read_frame(io).i == 1
        @test read_frame(io).i == 2
        @test eof(io)
    end

    @testset "state_frame shape (HANDOFF §5)" begin
        w = World(seed = 1)
        w.t = 12.34
        w.entities[:tgt1]   = Entity(:tgt1, :target; pos = Vec3(42000, 0, 3000))
        w.entities[:radar1] = Entity(:radar1, :radar; pos = Vec3(0, 0, 10))
        f = state_frame(w; telemetry = Dict("radar1.snr_db" => 13.2,
                                            "radar1.detected" => true))
        @test f[:type] == "state"
        @test f[:t] == 12.34
        @test length(f[:entities]) == 2
        # entities are emitted sorted by id for reproducible wire output
        @test [e[:id] for e in f[:entities]] == [:radar1, :tgt1]
        @test f[:entities][2][:pos] == [42000.0, 0.0, 3000.0]
        @test f[:telemetry]["radar1.detected"] == true

        # and it survives the wire
        io = IOBuffer(); write_frame(io, f); seekstart(io)
        back = read_frame(io)
        @test String(back.type) == "state"
        @test back.t == 12.34
    end

    @testset "tcp loopback (real sockets, not just IOBuffer)" begin
        # Exercises blocking socket reads, flush, and OS segment-splitting — the
        # variables IOBuffer can't surface. This isolates the Julia TCP path so a
        # later Godot failure can't be confused for a framing bug on our side.
        port, server = listenany(ip"127.0.0.1", UInt16(34567))
        srv = @async begin
            conn = accept(server)
            try
                f = read_frame(conn)
                write_frame(conn, Dict("echo_seq" => f.seq, "ok" => true))
            finally
                close(conn)
            end
        end
        cli = connect(ip"127.0.0.1", port)
        write_frame(cli, Dict("type" => "hello", "seq" => 99))
        reply = read_frame(cli)
        @test reply.echo_seq == 99
        @test reply.ok == true
        close(cli); close(server); wait(srv)
    end
end
