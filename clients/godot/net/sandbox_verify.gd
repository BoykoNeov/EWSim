extends SceneTree
# Headless step-7 verifier (the slice-1 analog of net/seam_test.gd). It drives the
# REAL Julia server (tools/server.jl) through SimClient.gd — the same protocol code
# Sandbox.tscn renders off — and asserts HANDOFF §8's "done" criterion as machine
# checks, because the rendering you judge by eye but the protocol layer can be
# *silently* wrong:
#
#   1. the first frame is the §5 `scenario` handshake, carrying both declared knobs
#      (pt_w, rcs_m2), each knob's live `value`, and the §12 `fidelity` map;
#   2. stepping yields a well-formed `state` frame: entities sorted [radar1, tgt1],
#      telemetry exposing radar SNR/Pd;
#   3. THE deliverable — a `set_param` on a slider key changes the physics: cranking
#      RCS 0.1 → 100 m² makes radar1.pd rise from ~0 to ~0.35 at the start geometry.
#      This proves slider → set_param → core → telemetry end to end, which IS step 7;
#   4. `run realtime` advances sim time (the default play mode actually ticks);
#   5. clean disconnect.
#
# Run (server must be listening first; it serves one client then exits):
#   godot --headless --path clients/godot --script res://net/sandbox_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 20.0
const SimClientScript := preload("res://net/SimClient.gd")

enum P { HANDSHAKE, LOW, HIGH, RT1, RT2 }

var _client                       # SimClient (preloaded so we never depend on class_name registration)
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _emit := 16
var _radar := ""                  # discovered radar id → its telemetry keys
var _pd_low := -1.0
var _t1 := -1.0
var _t0 := 0.0

func _initialize() -> void:
	print("SBV_INIT godot=", Engine.get_version_info().string)
	_t0 = _now()
	_client = SimClientScript.new()
	_client.frame_received.connect(func(obj: Dictionary) -> void: _inbox.append(obj))
	_client.start(HOST, PORT)

func _process(_dt: float) -> bool:
	if _now() - _t0 > MAX_SECONDS:
		return _fail("TIMEOUT in phase %s" % P.keys()[_phase], 2)
	_client.poll()                # node not in the tree → drive its IO ourselves

	match _phase:
		P.HANDSHAKE:
			var f := _take("scenario")
			if f.is_empty():
				return false
			var verr := _check_handshake(f)
			if verr != "":
				return _fail(verr)
			_emit = int(f.get("emit_every", 16))
			# crank RCS to its floor, then one scan-step → a state frame at low Pd
			_client.send({"type": "set_param", "target": "tgt1", "key": "rcs_m2", "value": 0.1})
			_client.send({"type": "step", "n": _emit})
			_phase = P.LOW

		P.LOW:
			var f := _take("state")
			if f.is_empty():
				return false
			var verr := _check_state(f)
			if verr != "":
				return _fail(verr)
			_pd_low = float(f["telemetry"].get(_radar + ".pd", -1.0))
			# crank RCS to its ceiling, step again → state frame at high Pd
			_client.send({"type": "set_param", "target": "tgt1", "key": "rcs_m2", "value": 100.0})
			_client.send({"type": "step", "n": _emit})
			_phase = P.HIGH

		P.HIGH:
			var f := _take("state")
			if f.is_empty():
				return false
			var pd_high := float(f["telemetry"].get(_radar + ".pd", -1.0))
			print("SBV_PD low=%.4f high=%.4f" % [_pd_low, pd_high])
			if not (pd_high - _pd_low > 0.1):
				return _fail("set_param did NOT move Pd: low=%.4f high=%.4f (expected a rise)" % [_pd_low, pd_high])
			# now prove the default play mode actually ticks under wall clock
			_inbox.clear()
			_client.send({"type": "run", "mode": "realtime", "speed": 1.0})
			_phase = P.RT1

		P.RT1:
			var f := _take("state")
			if f.is_empty():
				return false
			_t1 = float(f.get("t", -1.0))
			_phase = P.RT2

		P.RT2:
			var f := _take("state")
			if f.is_empty():
				return false
			var t2 := float(f.get("t", -1.0))
			if not (t2 > _t1):
				return false          # wait for a frame that actually advanced
			print("SBV_REALTIME t1=%.3f t2=%.3f" % [_t1, t2])
			_client.send({"type": "pause"})
			return _pass()
	return false

# Pop the first inbox frame of `type`, or {} if none yet. Other types are dropped
# (the spatial view ignores artifact/error frames during these phases too).
func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _check_handshake(f: Dictionary) -> String:
	var knobs: Array = f.get("knobs", [])
	var have := {}
	for k in knobs:
		have[str(k.get("key", ""))] = k
	if not have.has("pt_w") or not have.has("rcs_m2"):
		return "handshake missing a declared knob (have keys %s)" % str(have.keys())
	if not have["pt_w"].has("value"):
		return "handshake knob pt_w has no live `value`"
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (§12 badge would be hardcoded)"
	return ""

func _check_state(f: Dictionary) -> String:
	var ids: Array = []
	for e in f.get("entities", []):
		ids.append(str(e.get("id", "")))
		if str(e.get("kind", "")) == "radar":
			_radar = str(e.get("id", ""))
	if ids != ["radar1", "tgt1"]:
		return "entities not sorted [radar1, tgt1]: got %s" % str(ids)
	if _radar == "":
		return "no radar entity in state frame"
	var tel: Dictionary = f.get("telemetry", {})
	if not tel.has(_radar + ".snr_db") or not tel.has(_radar + ".pd"):
		return "telemetry missing %s.snr_db/.pd (have %s)" % [_radar, str(tel.keys())]
	return ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("SBV OK: handshake+knobs+fidelity, sorted state, set_param→Pd rise, realtime advance")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("SBV FAIL: " + msg)
	print("SBV FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()        # never parented to the tree → free it ourselves
		_client = null
