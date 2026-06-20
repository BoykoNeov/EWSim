extends SceneTree
# Headless seam test (slice-1 step 3): round-trips length-prefixed JSON frames
# against tools/echo_server.jl to prove the Godot↔Julia socket seam — partial
# reads, big-endian length parsing, PackedByteArray/UTF-8 handling. This is the
# one artifact that actually proves the seam; the Julia-side tests can't.
#
#   godot --headless --path clients/godot --script res://net/seam_test.gd
#
# Exit codes: 0 = all round-trips verified, 1 = mismatch, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const N := 5                       # round-trips to verify
const MAX_SECONDS := 15.0          # hard self-timeout — must never hang the loop

var _peer := StreamPeerTCP.new()
var _rx := PackedByteArray()
var _need := -1                    # expected payload length; -1 = awaiting header
var _sent := 0
var _recv := 0
var _ok := 0                       # in-order seq matches verified
var _t0 := 0.0
var _connected := false

func _initialize() -> void:
	print("SEAM_INIT godot=", Engine.get_version_info().string)  # proves --script ran
	_t0 = _now()
	_peer.connect_to_host(HOST, PORT)   # async; _process drives it to completion

func _finalize() -> void:
	print("SEAM_FINALIZE sent=%d recv=%d ok=%d" % [_sent, _recv, _ok])

func _process(_delta: float) -> bool:
	if _now() - _t0 > MAX_SECONDS:
		push_error("SEAM TIMEOUT (sent=%d recv=%d ok=%d)" % [_sent, _recv, _ok])
		return _done(2)

	_peer.poll()
	var st := _peer.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		return false
	if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
		_peer.connect_to_host(HOST, PORT)   # server not up yet / refused — retry until timeout
		return false

	if not _connected:
		_connected = true
		print("SEAM_CONNECTED")

	while _sent < N:
		_send_frame({"type": "hello", "seq": _sent, "payload": "jULiA<->godot ✓"})
		_sent += 1

	var avail := _peer.get_available_bytes()
	if avail > 0:
		var res: Array = _peer.get_data(avail)   # [error, PackedByteArray]
		if res[0] == OK:
			_rx.append_array(res[1])
	_parse_frames()

	if _recv >= N:
		var passed := (_ok == N)
		print("SEAM %s: %d/%d round-trips verified" % ["OK" if passed else "FAIL", _ok, N])
		return _done(0 if passed else 1)
	return false

func _parse_frames() -> void:
	while true:
		if _need < 0:
			if _rx.size() < 4:
				return
			# 4-byte BIG-ENDIAN length, decoded explicitly (don't trust the default LE)
			_need = (int(_rx[0]) << 24) | (int(_rx[1]) << 16) | (int(_rx[2]) << 8) | int(_rx[3])
			_rx = _rx.slice(4)
		if _rx.size() < _need:
			return
		var payload := _rx.slice(0, _need)
		_rx = _rx.slice(_need)
		_need = -1
		var txt := payload.get_string_from_utf8()
		var obj = JSON.parse_string(txt)
		# echoes arrive in send order, so the k-th echo must carry seq == k
		if typeof(obj) == TYPE_DICTIONARY and obj.get("type") == "echo" and int(obj.get("seq", -1)) == _ok:
			_ok += 1
		_recv += 1
		print("SEAM_RECV #%d: %s" % [_recv, txt])

func _send_frame(d: Dictionary) -> void:
	var payload := JSON.stringify(d).to_utf8_buffer()
	var n := payload.size()
	var hdr := PackedByteArray([(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff])
	_peer.put_data(hdr)
	_peer.put_data(payload)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _done(code: int) -> bool:
	_peer.disconnect_from_host()
	quit(code)
	return true
