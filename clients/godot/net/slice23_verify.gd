extends SceneTree
# Headless slice-23 gate-3 verifier (the slice8..22_verify analog). Drives the REAL Julia server
# through SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-23's
# 6-DOF SUBSTRATE + SKID-TO-TURN "done" criteria as machine checks. The lesson: a pitch-plane
# airframe can only pull g in the plane it is already in, so against a target OFF the x–z plane the
# `:pitch_coupled` plant DISCARDS the cross-range command and misses ≈ Y; the `:six_dof` STT plant
# keeps the full 3-D command and YAWS to intercept. FIVE phases:
#   • PITCH_COUPLED  — the default MISSES ≈ Y = 2000 m (the cross-range offset IS the miss); the
#                      missile never leaves the x–z plane (max|y| == 0.0 EXACTLY — the discard).
#   • REPLAY         — reset + replay the SAME config → the 3-D pos trace is BIT-IDENTICAL (class-4c
#                      RNG-FREE determinism — truth-fed PN, no seeker, no w.rng draw).
#   • SIX_DOF        — reset + set_fidelity airframe → six_dof (the LIVE toggle, the ONE button):
#                      the SAME PN law INTERCEPTS (frame CPA ≈ 5 m), and the missile TURNS out of
#                      plane (max|y| reaches ≈ Y — it flew to the cross-range target). The separation
#                      is asserted as a RATIO (the non-dead toggle).
#   • CY_ZERO        — reset (six_dof) + set_param af_cy_beta → 0 (THE CAUSATION LEVER): with the yaw
#                      side-force authority KILLED, the STT plant can no longer turn out of plane and
#                      DEGENERATES EXACTLY to the discard (miss ≈ Y, max|y| == 0.0) — so the
#                      out-of-plane authority did not merely correlate with the hit, it CAUSED it.
#
# FRAME SAMPLING IS LOAD-BEARING ([[ewsim-missile-verifier-sampling]]). The verifier sees state
# frames every emit_every (16) ticks. The MISS side (pitch_coupled, ≈2002) samples FAITHFULLY (a
# wide miss has near-zero radial rate at CPA). The HIT side (six_dof) samples COARSELY — closing
# ≈ 700 m/s ⇒ frames land ≈ 11 m apart near CPA, so the TRUE 0.230 m intercept frame-samples to
# ≈ 5.0 m. All bounds are pinned against the FRAME-SAMPLED live-wire numbers (temp/slice23_*.jl),
# never the true CPA — a sub-metre bound would FAIL on a real hit. CPA is measured on the FIRST
# DESCENDING BAND only (the static target gives one clean approach — but the latch is explicit).
#
# The out-of-plane position is read from the STATE FRAME'S ENTITY pos (full 3-D, shipped for EVERY
# entity on EVERY wire) — NOT the `pos_y` telemetry key (which ships only on the six_dof wire). So
# the pitch_coupled "max|y| == 0.0" discard check works on the arm that has no pos_y key at all.
#
# Everything is RNG-FREE (truth-fed PN, no seeker) so "draw-count invariance" is VACUOUS (class 4c).
#
# Run (server must be listening on slice23_out_of_plane.yaml first):
#   godot --headless --path clients/godot --script res://net/slice23_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 300.0
const SimClientScript := preload("res://net/SimClient.gd")

# 11520 = 720·16 = 11.52 s. The static 6-km target gives a CPA at ≈ 8.7 s on every arm, so the
# first-descending band is closed and latched well before the drain ends. Multiple of emit_every.
const STEPS := 11520

# Bounds — ALL pinned against the FRAME-SAMPLED live wire (temp/slice23_framesample.jl):
const MISS_Y := 2000.0            # the target's cross-range offset (the discard's miss ≈ this)
const DISCARD_MISS_MIN := 1900.0  # pitch_coupled frame CPA (measured 2002.37) — the discard misses ≈ Y
const HIT_MAX := 25.0             # six_dof frame CPA (measured 5.01; true 0.230 — sub-metre unreachable)
const TURN_MIN := 2000.0          # six_dof max|y| (measured 2720) — it flew to the cross-range target
const RATIO_MIN := 50.0           # discard/six_dof frame ratio (measured 399.6× — 8× margin)

enum P { HANDSHAKE, PITCH_COUPLED, REPLAY, SIX_DOF, CY_ZERO }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# scan accumulators (reset per burst)
var _min_los := 1.0e30            # CPA on the FIRST DESCENDING BAND only
var _prev_los := 1.0e30
var _closing := true              # latched false at the first ascent (no post-CPA re-crossing)
var _max_y := 0.0                 # max |missile y| — the out-of-plane excursion (from the entity pos)
var _pos_trace: Array = []        # per-frame [x, y, z] — the replay comparison (full 3-D)
# recorded across phases
var _coupled_pos: Array = []
var _coupled_miss := 0.0

func _initialize() -> void:
	print("S23V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.PITCH_COUPLED)

		# --- :pitch_coupled — the pitch-plane airframe DISCARDS the cross-range command → MISSES ≈ Y ---
		P.PITCH_COUPLED:
			if not _drain_scan():
				return false
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_coupled_pos = _pos_trace.duplicate(true)
			_coupled_miss = _min_los
			print("S23V_PITCH_COUPLED miss(frame)=%.3f  max|y|=%.4f  frames=%d" % [_min_los, _max_y, _pos_trace.size()])
			if not (_min_los > DISCARD_MISS_MIN):
				return _fail(":pitch_coupled must MISS the out-of-plane target ≈ Y (frame CPA > %.0f m), got %.2f" % [DISCARD_MISS_MIN, _min_los])
			# THE DISCARD — the missile never leaves the x–z plane (the whole point). EXACTLY 0.0: the
			# y-command is fully projected out, so the y-position never moves off the launch plane.
			if not (_max_y == 0.0):
				return _fail("the DISCARD requires max|y| == 0.0 EXACTLY (the pitch plane cannot leave x–z), got %s" % _max_y)
			_reset_then_scan([], STEPS, P.REPLAY)

		P.REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_coupled_pos, _pos_trace)
			print("S23V_REPLAY posdiff_vs_pitch_coupled=%s m  miss=%.3f (must be 0.0 / identical — class-4c RNG-free)" % [rdiff, _min_los])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c)" % rdiff)
			if not (_min_los == _coupled_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _coupled_miss])
			_reset_then_scan([_set_fidelity_cmd("airframe", "six_dof")], STEPS, P.SIX_DOF)

		# --- :six_dof — the STT plant keeps the full 3-D command and YAWS to intercept -----------------
		P.SIX_DOF:
			if not _drain_scan():
				return false
			var ratio := _coupled_miss / maxf(_min_los, 1.0e-9)
			print("S23V_SIX_DOF miss(frame)=%.3f  max|y|=%.2f  ratio=%.1fx (the discard died)" % [_min_los, _max_y, ratio])
			if not (_min_los < HIT_MAX):
				return _fail(":six_dof must INTERCEPT the out-of-plane target (frame CPA < %.0f m — sub-metre is UNREACHABLE on the wire), got %.2f" % [HIT_MAX, _min_los])
			# IT TURNED — the STT plant flew OUT of the launch plane to the cross-range target. This is
			# what the pitch plane cannot do; the y-excursion is the discard dying, made a number.
			if not (_max_y > TURN_MIN):
				return _fail(":six_dof must TURN out of plane toward the +Y target (max|y| > %.0f m), got %.2f" % [TURN_MIN, _max_y])
			if not (ratio > RATIO_MIN):
				return _fail("the :airframe toggle must be NON-DEAD: pitch_coupled/six_dof frame ratio > %.0fx, got %.1fx" % [RATIO_MIN, ratio])
			_reset_then_scan([_set_fidelity_cmd("airframe", "six_dof"), _set_param_cmd("m1", "af_cy_beta", 0.0)], STEPS, P.CY_ZERO)

		# --- af_cy_beta → 0 — THE CAUSATION PROOF: kill the yaw authority, the discard returns ---------
		P.CY_ZERO:
			if not _drain_scan():
				return false
			print("S23V_CY_ZERO cy_beta=0  miss(frame)=%.3f  max|y|=%.4f (yaw authority OFF ⇒ degenerates to the discard)" % [_min_los, _max_y])
			# With C_Yβ = 0 the yaw channel has NO side-force authority: the STT plant cannot turn out
			# of plane and DEGENERATES EXACTLY to the pitch-plane discard. This is what licenses the
			# causal claim — the out-of-plane authority did not merely correlate with the hit, it CAUSED
			# it. Pinned as the SAME degenerate the pitch_coupled arm showed (miss ≈ Y, max|y| == 0.0).
			if not (_min_los > DISCARD_MISS_MIN):
				return _fail("killing C_Yβ must RESTORE the miss (frame CPA > %.0f m) — the yaw authority CAUSED the intercept, got %.2f" % [DISCARD_MISS_MIN, _min_los])
			if not (_max_y == 0.0):
				return _fail("killing C_Yβ must collapse the out-of-plane turn (max|y| == 0.0 EXACTLY — no yaw side-force), got %s" % _max_y)
			return _pass()
	return false

# --- stepping / scanning (the slice-10..19 contract) --------------------------------------

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
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_max_y = 0.0
	_pos_trace = []

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: CPA on the FIRST DESCENDING BAND (the static target gives one clean approach — but latch it
# explicitly rather than trusting the geometry), plus the max |missile y| over that approach (the
# out-of-plane excursion), read from the STATE-FRAME ENTITY pos (full 3-D, all wires).
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		# the missile's full 3-D position from the entity list (NOT telemetry — pos_y ships only on
		# the six_dof wire, but the entity pos is 3-D on EVERY wire).
		var mpos := _missile_pos(f)
		if not mpos.is_empty():
			_pos_trace.append(mpos)
			_max_y = maxf(_max_y, absf(mpos[1]))
		var tel: Dictionary = f.get("telemetry", {})
		if _mid != "" and tel.has(_mid + ".los_range"):
			var r := float(tel[_mid + ".los_range"])
			if r > _prev_los:
				_closing = false          # CPA passed — stop accumulating (no re-crossing)
			if _closing:
				_min_los = minf(_min_los, r)
			_prev_los = r
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

func _missile_pos(f: Dictionary) -> Array:
	for e in f.get("entities", []):
		if str(e.get("id", "")) == _mid:
			var p: Array = e.get("pos", [])
			if p.size() >= 3:
				return [float(p[0]), float(p[1]), float(p[2])]
	return []

func _pos_max_diff(a: Array, b: Array) -> float:
	var n := mini(a.size(), b.size())
	if n == 0:
		return 1.0e30                       # no overlap ⇒ treat as a failure
	var m := 0.0
	for i in n:
		for k in 3:
			m = maxf(m, absf(a[i][k] - b[i][k]))
	return m

# --- helpers ------------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _find_missile(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "missile":
			return str(e.get("id", ""))
	return ""

func _check_handshake(f: Dictionary) -> String:
	# Slice 23 reuses slice-17..19's `airframe_view` marker AND ships the NEW `airframe_6dof`
	# discriminator (a missile carrying an authored :af_cy_beta) that upgrades the client to the 3-D
	# view + the 3-ring cycler. The `:airframe` fidelity is THE BUTTON with the autopilot AUTHORED at
	# :alpha (the cross-fidelity dependency: a_ctrl by fiat under :point_mass, δ_pitch under
	# :pitch_coupled, TWO fins under :six_dof).
	if not bool(f.get("airframe_view", false)):
		return "a slice-23 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-23 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator — a missile carrying :af_cy_beta)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("airframe", "")) != "pitch_coupled":
		return "a slice-23 scenario must default :airframe to pitch_coupled (the showcase opens on the discard/miss), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-23 scenario must AUTHOR the autopilot at :alpha (the inner α/β/g loop), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-23 scenario must hold :guidance at :pn (convention 9 — ONE toggled fidelity), got %s" % str(fid.get("guidance", "<absent>"))
	# one lesson per scenario: no view axes (cfar/esm/geoloc/gps), and no terrain grid (the slice-18
	# 3-D branch — a DIFFERENT 3-D view, the multi-view discriminator).
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-23 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-23 scenario must NOT ship terrain_grid (that flips the client to the slice-18 terrain 3-D view — a DIFFERENT 3-D view)"
	# the out-of-plane authority lever must be exposed (the causation lever the CY_ZERO phase drives).
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("af_cy_beta"):
		return "slice-23 handshake must expose the 'af_cy_beta' slider — the out-of-plane authority (the causation lever)"
	if keys.has("speed"):
		return "slice-23 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load and read by NOTHING per-tick (the slice-19 DEAD-knob finding); rho is the live Q lever"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S23V OK: a pitch-plane airframe can only pull g in the plane it is already in — so against a " +
		"target OFF the x–z plane the :pitch_coupled plant DISCARDS the cross-range command and misses ≈ Y " +
		"(2002 m, max|y| == 0.0 — it never leaves the launch plane), while the :six_dof SKID-TO-TURN plant " +
		"keeps the full 3-D command and YAWS to intercept (≈5 m frame-sampled, max|y| → 2720 — it flew to the " +
		"cross-range target), a ~400× separation on the ONE live :airframe toggle. Killing the yaw authority " +
		"(af_cy_beta → 0) DEGENERATES the STT plant EXACTLY back to the discard (miss ≈ Y, max|y| == 0.0) — so " +
		"the out-of-plane authority did not merely correlate with the hit, it CAUSED it. The discard, unflyable " +
		"BY CONSTRUCTION since slice 19, now intercepts. Physics-changing, RNG-free, live-settable (class 4c).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S23V FAIL: " + msg)
	print("S23V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
