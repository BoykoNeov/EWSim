extends Node
class_name SimClient
# Thin TCP client for the EWSim Julia server (HANDOFF §5): a 4-byte big-endian
# length prefix + UTF-8 JSON, one object per frame, both directions. This is the
# SOLE protocol implementation the spatial client uses — Sandbox.gd renders off
# it, the headless step-7 verifier asserts off it, so the wire logic that can be
# *silently* wrong lives in exactly one tested place. The framing mirrors
# net/seam_test.gd, which already proved the seam against tools/echo_server.jl.
#
# No rendering dependency: all IO is driven by poll(). In a live scene _process
# calls poll() each frame; a headless harness (no scene, so no node _process)
# instantiates SimClient and calls poll() itself. Either way the state machine,
# framing, and signals are identical.
#
# Lifecycle: start(host, port) → retries connecting until the server's warmup
# finishes → emits `frame_received(obj)` per decoded JSON object (the first is
# the §5 `scenario` handshake) → `disconnected` on EOF. send(obj) frames+sends
# one command (§5 client→server).

signal connected
signal disconnected
signal frame_received(obj: Dictionary)

enum State { IDLE, CONNECTING, CONNECTED, CLOSED }

var _peer := StreamPeerTCP.new()
var _rx := PackedByteArray()
var _need := -1                 # expected payload length; -1 = awaiting the 4-byte header
var _host := "127.0.0.1"
var _port := 8765
var _state: State = State.IDLE

func start(host := "127.0.0.1", port := 8765) -> void:
	_host = host
	_port = port
	_state = State.CONNECTING
	_peer.connect_to_host(_host, _port)

func is_live() -> bool:
	return _state == State.CONNECTED

# Frame+send one command dict (§5 client→server). No-op until connected.
func send(obj: Dictionary) -> void:
	if _state != State.CONNECTED:
		return
	var payload := JSON.stringify(obj).to_utf8_buffer()
	var n := payload.size()
	# 4-byte BIG-ENDIAN length, written explicitly (don't trust platform endianness).
	var hdr := PackedByteArray([(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff])
	_peer.put_data(hdr)
	_peer.put_data(payload)

func close() -> void:
	if _state != State.CLOSED:
		_peer.disconnect_from_host()
		_state = State.CLOSED

func _process(_dt: float) -> void:
	poll()

# Drive the connection one step: advance the connect handshake, ingest available
# bytes, and emit a `frame_received` per complete frame. Safe to call every frame.
func poll() -> void:
	if _state == State.IDLE or _state == State.CLOSED:
		return
	_peer.poll()
	var st := _peer.get_status()

	if _state == State.CONNECTING:
		if st == StreamPeerTCP.STATUS_CONNECTING:
			return
		elif st == StreamPeerTCP.STATUS_CONNECTED:
			_peer.set_no_delay(true)            # interactive: don't Nagle small command frames
			_state = State.CONNECTED
			connected.emit()
		else:
			# refused / not up yet (server still warming) — retry until the caller times out.
			_peer.connect_to_host(_host, _port)
			return

	# CONNECTED: a dropped peer shows up as ERROR/NONE here.
	if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
		_state = State.CLOSED
		disconnected.emit()
		return

	var avail := _peer.get_available_bytes()
	if avail > 0:
		var res: Array = _peer.get_data(avail)  # [error, PackedByteArray]
		if res[0] == OK:
			_rx.append_array(res[1])
	_drain_frames()

# Parse as many whole frames as `_rx` holds. TCP may split a frame across reads,
# so a partial header/payload just returns and waits for the next poll().
func _drain_frames() -> void:
	while true:
		if _need < 0:
			if _rx.size() < 4:
				return
			_need = (int(_rx[0]) << 24) | (int(_rx[1]) << 16) | (int(_rx[2]) << 8) | int(_rx[3])
			_rx = _rx.slice(4)
		if _rx.size() < _need:
			return
		var payload := _rx.slice(0, _need)
		_rx = _rx.slice(_need)
		_need = -1
		var obj = JSON.parse_string(payload.get_string_from_utf8())
		if typeof(obj) == TYPE_DICTIONARY:
			frame_received.emit(obj)
