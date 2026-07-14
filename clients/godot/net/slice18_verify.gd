extends SceneTree
# Headless slice-18 gate-3 verifier (the slice8..17_verify analog). Drives the REAL Julia server through
# SimClient.gd and asserts slice-18's TERRAIN-MASKING "done" criteria as machine checks on the scalar
# telemetry (visible / detected / terrain_clearance_m / snr_db). The lesson: a ridge between a mast radar
# and a LOW penetrator occludes the LOS — dark the whole approach, then the ~4.8-km POP-UP; altitude
# collapses the shadow. FOUR phases after the handshake:
#   • TERRAIN       — the default rung: the run STARTS masked (visible=false, snr at the wire floor,
#                     clearance NEGATIVE), POPS UP once (exactly one false→true transition, x in the
#                     probe band), detections happen ONLY while visible, clearance sign follows visible.
#   • TERRAIN_REPLAY— reset + replay the SAME config → the (visible, snr) trace is BIT-IDENTICAL
#                     (held-seed determinism THROUGH the masked draws — the rung gates booleans, never
#                     the draw, so the stream replays exactly).
#   • FREE_SPACE    — reset + set_fidelity propagation → free_space (the LIVE 3-ring toggle): the SAME
#                     seed sees the target from frame 1 (visible every frame, detections in the window
#                     terrain kept dark) AND the terrain_clearance_m key is GONE (rung-gated wire).
#   • ALT           — reset (→ terrain) + set_param alt_hold_m → 1000 (the LESSON KNOB): the shadow
#                     collapses — visible every frame, clearance POSITIVE throughout (probe: ≥ +31 m).
#
# Probe pins (live wire, seed 18): pop-up t=36.724 s x=4819 m; start clearance −208.6; first detection
# t=36.801 s; alt-1000 min clearance +31.4 m; free_space start SNR 32.2 dB (detects from the start).
#
# Run (server must be listening on slice18_terrain.yaml first):
#   godot --headless --path clients/godot --script res://net/slice18_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 240.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 40000 = 2500·16 = 40 s: covers the 36.7-s pop-up + a visible tail. 8000 = 500·16 = 8 s: deep inside
# the masked window (the free_space / altitude contrast phases).
const STEPS_FULL := 40000
const STEPS_EARLY := 8000
const POPUP_X_LO := 4300.0        # the pop-up x band (probe: 4819 m — generous, not seed-tuned)
const POPUP_X_HI := 5300.0
const SNR_FLOOR := -120.0         # the core's _SNR_DB_FLOOR (a masked frame ships exactly this)

enum P { HANDSHAKE, TERRAIN, TERRAIN_REPLAY, FREE_SPACE, ALT }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0
var _radar := ""
var _target := ""

# per-burst scan accumulators
var _trace: Array = []            # per-frame [visible, detected, clearance_or_null, snr_db, tgt_x]
var _clr_key_frames := 0          # frames carrying terrain_clearance_m (the rung-gated key)
# recorded across phases
var _terrain_trace: Array = []

func _initialize() -> void:
	print("S18V_INIT godot=", Engine.get_version_info().string)
	_t0 = _now()
	_client = SimClientScript.new()
	_client.frame_received.connect(func(obj: Dictionary) -> void: _inbox.append(obj))
	_client.start(HOST, PORT)

func _process(_dt_frame: float) -> bool:
	if _now() - _t0 > MAX_SECONDS:
		return _fail("TIMEOUT in phase %s" % P.keys()[_phase], 2)
	_client.poll()

	match _phase:
		P.HANDSHAKE:
			var f := _take("scenario")
			if f.is_empty():
				return false
			var verr := _check_handshake(f)
			if verr != "":
				return _fail(verr)
			_dt = float(f.get("dt_physics", 1.0e-3))
			_radar = str(f.get("radar", ""))
			_target = str(f.get("target", ""))
			_begin_scan(STEPS_FULL, P.TERRAIN)

		# --- the default :terrain run: dark approach → the pop-up --------------------------------
		P.TERRAIN:
			if not _drain_scan():
				return false
			_terrain_trace = _trace.duplicate(true)
			var n := _trace.size()
			if n < 100:
				return _fail("too few state frames (%d)" % n)
			# starts MASKED: visible=false, snr at the exact wire floor, clearance NEGATIVE
			if bool(_trace[0][0]):
				return _fail("the run must START terrain-masked (visible=false), frame 0 is visible")
			if float(_trace[0][3]) != SNR_FLOOR:
				return _fail("a masked frame must ship snr_db == the wire floor %s, got %s" % [SNR_FLOOR, _trace[0][3]])
			if _trace[0][2] == null or float(_trace[0][2]) >= 0.0:
				return _fail("a masked frame must ship a NEGATIVE terrain_clearance_m, got %s" % str(_trace[0][2]))
			# exactly ONE false→true transition, inside the probe band; visible stays on after it
			var popup_i := -1
			var transitions := 0
			for i in range(1, n):
				if bool(_trace[i][0]) and not bool(_trace[i - 1][0]):
					transitions += 1
					popup_i = i
				elif not bool(_trace[i][0]) and bool(_trace[i - 1][0]):
					transitions += 1
			if transitions != 1 or popup_i < 0:
				return _fail("expected EXACTLY one masked→visible pop-up transition, got %d" % transitions)
			var popup_x := float(_trace[popup_i][4])
			if popup_x < POPUP_X_LO or popup_x > POPUP_X_HI:
				return _fail("the pop-up must land at x in [%d, %d] m (probe 4819), got %.0f" % [POPUP_X_LO, POPUP_X_HI, popup_x])
			# detections ONLY while visible; at least one after the pop-up
			var det_masked := 0
			var det_visible := 0
			for i in n:
				if bool(_trace[i][1]):
					if bool(_trace[i][0]):
						det_visible += 1
					else:
						det_masked += 1
			if det_masked != 0:
				return _fail("NO detection may fire while terrain-masked, got %d masked-frame detections" % det_masked)
			if det_visible == 0:
				return _fail("the popped-up target must be DETECTED (0 visible-frame detections)")
			# the clearance SIGN follows the verdict on every frame that ships it
			for i in n:
				if _trace[i][2] != null and (float(_trace[i][2]) > 0.0) != bool(_trace[i][0]):
					return _fail("terrain_clearance_m sign must MATCH the visible verdict (frame %d: clr=%s vis=%s)" % [i, str(_trace[i][2]), str(_trace[i][0])])
			if _clr_key_frames != n:
				return _fail("every :terrain frame must ship terrain_clearance_m (got %d of %d)" % [_clr_key_frames, n])
			print("S18V_TERRAIN frames=%d popup_x=%.0f det_visible=%d det_masked=0 clr0=%.1f" %
				[n, popup_x, det_visible, float(_trace[0][2])])
			_reset_then_scan([], STEPS_FULL, P.TERRAIN_REPLAY)

		P.TERRAIN_REPLAY:
			if not _drain_scan():
				return false
			if _trace.size() != _terrain_trace.size():
				return _fail("replay frame count differs (%d vs %d)" % [_trace.size(), _terrain_trace.size()])
			for i in _trace.size():
				if _trace[i] != _terrain_trace[i]:
					return _fail("held-seed replay must be BIT-IDENTICAL (frame %d differs: %s vs %s) — the mask gates booleans, never the draw" % [i, str(_trace[i]), str(_terrain_trace[i])])
			print("S18V_REPLAY %d frames bit-identical (held-seed determinism through the masked draws)" % _trace.size())
			_reset_then_scan([_set_fidelity_cmd("propagation", "free_space")], STEPS_EARLY, P.FREE_SPACE)

		# --- free_space, same seed: the terrain-dark window is fully tracked ----------------------
		P.FREE_SPACE:
			if not _drain_scan():
				return false
			var det := 0
			for fr in _trace:
				if not bool(fr[0]):
					return _fail("free_space must see the target EVERY frame (infinite LOS), got a masked frame")
				if bool(fr[1]):
					det += 1
			if det == 0:
				return _fail("free_space must DETECT inside the window terrain kept dark (0 detections in the first 8 s)")
			if _clr_key_frames != 0:
				return _fail("a free_space frame must NOT ship terrain_clearance_m (rung-gated key), got %d frames" % _clr_key_frames)
			print("S18V_FREE_SPACE frames=%d all visible, detections=%d, clearance key absent (rung-gated)" % [_trace.size(), det])
			_reset_then_scan([_set_param_cmd("tgt1", "alt_hold_m", 1000.0)], STEPS_EARLY, P.ALT)

		# --- altitude 1000 m: the shadow collapses ------------------------------------------------
		P.ALT:
			if not _drain_scan():
				return false
			var min_clr := 1.0e30
			for fr in _trace:
				if not bool(fr[0]):
					return _fail("at 1000 m the target must be visible EVERY frame (the shadow collapses), got a masked frame")
				if fr[2] != null:
					min_clr = minf(min_clr, float(fr[2]))
			if not (min_clr > 0.0):
				return _fail("at 1000 m the LOS clearance must stay POSITIVE (probe: ≥ +31 m), got %s" % min_clr)
			print("S18V_ALT frames=%d all visible, min_clearance=%.1f m (altitude buys detectability)" % [_trace.size(), min_clr])
			return _pass()
	return false

# --- stepping / scanning (the slice-10..17 contract) --------------------------------------

func _begin_scan(n: int, next: P) -> void:
	_reset_scan_accum()
	_inbox.clear()
	_last_state = {}
	_t_target = _now_t() + n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_then_scan(cmds: Array, n: int, next: P) -> void:
	_reset_scan_accum()
	_inbox.clear()
	_last_state = {}
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt              # reset zeroes the clock
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_scan_accum() -> void:
	_trace = []
	_clr_key_frames = 0

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: record per-frame [visible, detected, clearance|null, snr_db, tgt_x] off the radar telemetry
# + the target entity pos (the pop-up x anchor). Everything is CORE output.
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		var tel: Dictionary = f.get("telemetry", {})
		if _radar != "" and tel.has(_radar + ".visible"):
			var clr = null
			if tel.has(_radar + ".terrain_clearance_m"):
				clr = float(tel[_radar + ".terrain_clearance_m"])
				_clr_key_frames += 1
			var tx := 0.0
			for e in f.get("entities", []):
				if str(e.get("id", "")) == _target:
					tx = float(e.get("pos", [0, 0, 0])[0])
			_trace.append([bool(tel[_radar + ".visible"]), bool(tel.get(_radar + ".detected", false)),
				clr, float(tel.get(_radar + ".snr_db", 0.0)), tx])
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# --- helpers ------------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _check_handshake(f: Dictionary) -> String:
	# Slice 18 ships the STATIC terrain block (the 3-D-view discriminator) + the propagation
	# 3-ring default :terrain + the altitude lesson knob.
	if not f.has("terrain_grid"):
		return "a slice-18 handshake must ship terrain_grid (the 3-D-view discriminator)"
	var n := int(f.get("terrain_n", 0))
	if n < 2:
		return "terrain_n must be ≥ 2, got %d" % n
	var grid: Array = f.get("terrain_grid", [])
	if grid.size() != n * n:
		return "terrain_grid must be n² = %d heights, got %d" % [n * n, grid.size()]
	var ext: Array = f.get("terrain_extent_m", [])
	if ext.size() != 4 or float(ext[1]) <= float(ext[0]) or float(ext[3]) <= float(ext[2]):
		return "terrain_extent_m must be an ordered [xmin, xmax, ymin, ymax], got %s" % str(ext)
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("propagation", "")) != "terrain":
		return "a slice-18 scenario must default propagation to :terrain, got %s" % str(fid.get("propagation", "<absent>"))
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-18 scenario must NOT ship range_axis_m / pri_axis_us (one view per scenario)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("alt_hold_m"):
		return "slice-18 handshake must expose the 'alt_hold_m' slider — the altitude lesson knob"
	if str(f.get("radar", "")) == "" or str(f.get("target", "")) == "":
		return "slice-18 handshake must name the radar + target ids (the LOS telemetry binding)"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S18V OK: terrain masks the low penetrator the whole approach (visible=false, snr at the wire " +
		"floor, clearance NEGATIVE) until the ~4.8-km pop-up (exactly one transition, detections ONLY " +
		"while visible); the held-seed replay is bit-identical THROUGH the masked draws (class 4a — the " +
		"mask gates booleans, never the draw); free_space on the same seed tracks from frame 1 with the " +
		"clearance key GONE (rung-gated wire); and altitude 1000 m collapses the shadow (clearance " +
		"positive throughout). Altitude buys detectability — and vice versa.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S18V FAIL: " + msg)
	print("S18V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
