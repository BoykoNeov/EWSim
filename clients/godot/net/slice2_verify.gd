extends SceneTree
# Headless slice-2 step-3 verifier (the analog of net/sandbox_verify.gd). It drives the
# REAL Julia server (tools/server.jl scenarios/slice2_tworay.yaml) through SimClient.gd —
# the same protocol code Sandbox.tscn renders off — and asserts slice-2's "done" criterion
# as machine checks, because the lobing/horizon you judge by eye but the wire + the live
# `set_fidelity` toggle can be *silently* wrong:
#
#   1. the handshake carries `fidelity.propagation == two_ray` (the scenario default);
#   2. HORIZON MASKING — the first state frame (target at ~70 km, beyond the 63.8 km
#      4/3-Earth horizon) reports `radar1.visible == false` under two_ray;
#   3. stepping to the sample time T (target within the horizon) reports `visible == true`
#      and a finite, non-floored SNR — the target is in line of sight and lobing;
#   4. THE deliverable — the live toggle flips the physics AT THE SAME t: reset (which
#      reverts the server to the YAML two_ray) THEN set_fidelity free_space, replay to the
#      SAME T, and the telemetry SNR moves by a clean margin (here ~7 dB) while t is
#      bit-identical. Replaying under free_space, the far target is `visible == true`
#      (free_space ignores the ground) — the mask was the two_ray model, not the geometry.
#
# Determinism note: SNR at a given t is pure geometry (RNG-independent), and `step n` lands
# the clock at exactly n·dt in BOTH the two_ray pass and the free_space replay, so the two
# samples are at an identical t and an identical target position — the only difference is
# the propagation rung the toggle switched. reset MUST precede set_fidelity: reset reloads
# the YAML and would clobber the toggle back to two_ray (slice2 plan / server.jl _reload!).
#
# Run (server must be listening on slice2_tworay.yaml first; it serves one client, then exits):
#   godot --headless --path clients/godot --script res://net/slice2_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 40.0
const SimClientScript := preload("res://net/SimClient.gd")

const SAMPLE_STEPS := 28000       # reach t = SAMPLE_STEPS·dt = 28.0 s: target ~57 km, well
                                  # within the 63.8 km horizon, on a smooth lobe flank
const SNR_GAP_DB := 2.0           # min |Δsnr_db| the toggle must produce at the sample t
                                  # (the geometry gives ~7 dB here — margin to spare)

enum P { HANDSHAKE, TWO, FREE }

var _client                       # SimClient (preloaded — never depend on class_name registration)
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _emit := 16
var _dt := 1.0e-3
var _t_target := 28.0
var _radar := ""

# per-draining-phase accumulators (reset on phase entry)
var _first_state: Dictionary = {}
var _last_state: Dictionary = {}

# captured under two_ray
var _far_vis_two := true          # first-frame visibility (beyond horizon → should be false)
var _vis_two := false             # visibility at the sample t (within horizon → should be true)
var _snr_two := 0.0
var _t_two := -1.0
# captured under free_space
var _far_vis_free := false        # first-frame visibility (free_space ignores ground → true)

var _t0 := 0.0

func _initialize() -> void:
	print("S2V_INIT godot=", Engine.get_version_info().string)
	_t0 = _now()
	_client = SimClientScript.new()
	_client.frame_received.connect(func(obj: Dictionary) -> void: _inbox.append(obj))
	_client.start(HOST, PORT)

func _process(_dt_frame: float) -> bool:
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
			_dt = float(f.get("dt_physics", 1.0e-3))
			_t_target = SAMPLE_STEPS * _dt
			_enter_draining()
			_client.send({"type": "step", "n": SAMPLE_STEPS})    # two_ray pass (the default)
			_phase = P.TWO

		P.TWO:
			if not _drain_to_T():
				return false
			var verr := _capture_two()
			if verr != "":
				return _fail(verr)
			# Hand off to the free_space replay. Clear stale two_ray frames first so none can
			# masquerade as the replay, then reset (→ YAML two_ray, t=0) BEFORE set_fidelity
			# (the order matters — reset would clobber the toggle), then replay to the same T.
			_inbox.clear()
			_enter_draining()
			_client.send({"type": "reset"})
			_client.send({"type": "set_fidelity", "key": "propagation", "value": "free_space"})
			_client.send({"type": "step", "n": SAMPLE_STEPS})
			_phase = P.FREE

		P.FREE:
			if not _drain_to_T():
				return false
			return _finish()
	return false

# --- draining: keep the FIRST state frame (far/horizon) and the LATEST; done at t ≥ T -----

func _enter_draining() -> void:
	_first_state = {}
	_last_state = {}

func _drain_to_T() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _first_state.is_empty():
			_first_state = f
		_last_state = f
	if _last_state.is_empty():
		return false
	# the last emit of a `step n` burst lands at exactly n·dt; tolerate <½ tick of slack
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# --- captures / assertions ----------------------------------------------------------------

func _capture_two() -> String:
	if _radar == "":
		_radar = _radar_id(_last_state)
	if _radar == "":
		return "no radar entity in the two_ray state stream"
	_far_vis_two = _vis_of(_first_state)
	_vis_two = _vis_of(_last_state)
	_snr_two = _snr_of(_last_state)
	_t_two = float(_last_state.get("t", -1.0))
	# below the horizon at the start, in line of sight at the sample t, finite SNR there
	if _far_vis_two:
		return "two_ray: target at the start (≈70 km) should be below horizon (visible:false)"
	if not _vis_two:
		return "two_ray: target at t=%.3f should be within horizon (visible:true)" % _t_two
	if _snr_two <= -119.0:
		return "two_ray: sample SNR is floored (%.2f dB) — pick a non-null sample t" % _snr_two
	return ""

func _finish() -> bool:
	_far_vis_free = _vis_of(_first_state)
	var snr_free := _snr_of(_last_state)
	var t_free := float(_last_state.get("t", -1.0))
	print("S2V_SAMPLE t_two=%.6f t_free=%.6f  snr_two=%.3f snr_free=%.3f  Δ=%.3f dB" %
		[_t_two, t_free, _snr_two, snr_free, _snr_two - snr_free])
	print("S2V_VIS far_two=%s far_free=%s vis_two@T=%s" % [_far_vis_two, _far_vis_free, _vis_two])
	# same t (the replay lands on the identical clock)
	if abs(t_free - _t_two) > 1.0e-9:
		return _fail("toggle samples not at the same t: two=%.9f free=%.9f" % [_t_two, t_free])
	# the toggle moved the physics: SNR differs by a clean margin at that identical t
	if abs(_snr_two - snr_free) <= SNR_GAP_DB:
		return _fail("set_fidelity did NOT flip SNR: two=%.3f free=%.3f (Δ≤%.1f dB)" %
			[_snr_two, snr_free, SNR_GAP_DB])
	# free_space ignores the ground, so the far target that two_ray masked is now visible
	if not _far_vis_free:
		return _fail("free_space far target should be visible (horizon is a two_ray effect)")
	return _pass()

# --- frame helpers ------------------------------------------------------------------------

# Pop the first inbox frame of `type`, or {} if none yet (other types dropped).
func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _radar_id(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "radar":
			return str(e.get("id", ""))
	return ""

func _snr_of(state: Dictionary) -> float:
	return float((state.get("telemetry", {}) as Dictionary).get(_radar + ".snr_db", -999.0))

func _vis_of(state: Dictionary) -> bool:
	return bool((state.get("telemetry", {}) as Dictionary).get(_radar + ".visible", true))

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (§12 badge / toggle would be blind)"
	if str(fid.get("propagation", "")) != "two_ray":
		return "scenario default propagation should be two_ray, got '%s'" % str(fid.get("propagation", ""))
	var knobs: Array = f.get("knobs", [])
	if knobs.is_empty():
		return "handshake has no knobs"
	return ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S2V OK: handshake two_ray, horizon mask (visible false→true), set_fidelity flips SNR at same t")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S2V FAIL: " + msg)
	print("S2V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()        # never parented to the tree → free it ourselves
		_client = null
