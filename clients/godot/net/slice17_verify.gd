extends SceneTree
# Headless slice-17 gate-3 verifier (the slice8..16_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-17's α→lift→γ
# COUPLING "done" criteria as machine checks on the SCALAR telemetry (pos_x/pos_z + a_lift/turn_radius).
# The lesson: the angle of attack α = θ−γ generates a body lift ⟂ v that TURNS the flight path — the REAL
# path-changing `:airframe` toggle (the INVERSE of slice-16's posdiff=0.0 isolation). FOUR phases:
#   • COUPLED       — default :pitch_coupled: the path CURVES (a climbing turn). Record the pos trace +
#                     confirm the lift telemetry keys (a_lift / turn_radius_m) SHIP. This is the baseline.
#   • COUPLED_REPLAY— reset + replay the SAME config → the pos trace is BIT-IDENTICAL (class-4c RNG-FREE
#                     determinism — no seeker, no w.rng draw).
#   • POINT_MASS    — reset + set_fidelity airframe → point_mass (the LIVE toggle): the path is BALLISTIC,
#                     posdiff vs COUPLED is LARGE (> threshold — the toggle is REAL) AND the a_lift keys are
#                     GONE (the coupled-only gated wire). Also pins the ballistic end to p0+v0t+½gt².
#   • DELTA0        — reset (→ :pitch_coupled) + set_param af_delta → 0 (the LEVER): the path STRAIGHTENS
#                     toward ballistic (posdiff vs POINT_MASS ≪ the COUPLED-vs-POINT_MASS toggle — δ drives
#                     the turn; the small residual is the α0 transient decaying to trim α=0).
#
# Everything is RNG-FREE (truth-fed, open-loop, no seeker) so "byte-identity" is trivial-but-asserted
# (class 4c). Frame-sampled every emit_every (16) ticks. Probe pins (live wire): coupled end
# (2187.8, 3010.2), ballistic end (3064.2, 2257.3) → posdiff 1155 m; δ=0 vs ballistic 91 m (12.7×).
#
# Run (server must be listening on slice17_coupling.yaml first):
#   godot --headless --path clients/godot --script res://net/slice17_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 8000 = 500·16 = 8 s: the coupled path bends into a clear turn, the missile still climbing (no impact).
const STEPS := 8000
const G_ACCEL := 9.81               # the core's gravity (dynamics.jl) — the ballistic-end anchor
const V0 := 500.0                   # launch speed (m/s) — the scenario
const ELEV_DEG := 40.0              # launch elevation (deg) — the scenario
const POSDIFF_TOGGLE_MIN := 500.0   # coupled-vs-point_mass posdiff floor (probe: 1155 m — the toggle is REAL)
const DELTA0_STRAIGHT_MAX := 300.0  # δ=0 coupled vs ballistic ceiling (probe: 91 m — the lever straightens)

enum P { HANDSHAKE, COUPLED, COUPLED_REPLAY, POINT_MASS, DELTA0 }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _name := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# scan accumulators (reset per burst)
var _lift_keys_seen := false          # the coupled-only a_lift / turn_radius_m keys ship
var _max_alift := 0.0
var _pos_trace: Array = []            # per-frame [pos_x, pos_z] — the coupling / toggle comparison
# recorded across phases
var _coupled_pos: Array = []          # the :pitch_coupled baseline trace
var _ballistic_pos: Array = []        # the :point_mass trace

func _initialize() -> void:
	print("S17V_INIT godot=", Engine.get_version_info().string)
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
			_name = str(f.get("name", ""))
			_begin_scan(STEPS, P.COUPLED)

		# --- :pitch_coupled: the path CURVES; the lift telemetry ships ------------------------------
		P.COUPLED:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_coupled_pos = _pos_trace.duplicate(true)
			print("S17V_COUPLED end=(%.1f, %.1f)  max_a_lift=%.3f  lift_keys=%s  frames=%d" %
				[_end_x(_pos_trace), _end_z(_pos_trace), _max_alift, str(_lift_keys_seen), _pos_trace.size()])
			if not _lift_keys_seen:
				return _fail(":pitch_coupled missile must ship the a_lift / turn_radius_m coupling telemetry keys")
			if not (_max_alift > 0.0):
				return _fail(":pitch_coupled must produce a nonzero lift (a_lift > 0), got %s" % _max_alift)
			# REPLAY: reset (→ :pitch_coupled default) and re-fly — the pos trace must match bit-for-bit.
			_reset_then_scan([], STEPS, P.COUPLED_REPLAY)

		P.COUPLED_REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_coupled_pos, _pos_trace)
			print("S17V_REPLAY posdiff_vs_coupled=%s m (must be 0.0 — class-4c RNG-free determinism)" % rdiff)
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism" % rdiff)
			# POINT_MASS: reset (→ :pitch_coupled) then set_fidelity airframe → point_mass (the LIVE toggle).
			_reset_then_scan([_set_fidelity_cmd("airframe", "point_mass")], STEPS, P.POINT_MASS)

		# --- :point_mass: the path is BALLISTIC; posdiff LARGE; the lift keys are GONE --------------
		P.POINT_MASS:
			if not _drain_scan():
				return false
			_ballistic_pos = _pos_trace.duplicate(true)
			var posdiff := _pos_max_diff(_coupled_pos, _pos_trace)
			var t := STEPS * _dt
			var xb: float = V0 * cos(deg_to_rad(ELEV_DEG)) * t
			var zb: float = V0 * sin(deg_to_rad(ELEV_DEG)) * t - 0.5 * G_ACCEL * t * t
			var end_err := absf(_end_x(_pos_trace) - xb) + absf(_end_z(_pos_trace) - zb)
			print("S17V_POINT_MASS end=(%.1f, %.1f)  analytic=(%.1f, %.1f)  posdiff_vs_coupled=%s m  lift_keys=%s" %
				[_end_x(_pos_trace), _end_z(_pos_trace), xb, zb, posdiff, str(_lift_keys_seen)])
			if _lift_keys_seen:
				return _fail(":point_mass must NOT ship the a_lift / turn_radius_m keys (coupled-only gated wire)")
			if not (posdiff > POSDIFF_TOGGLE_MIN):
				return _fail("the :airframe toggle must CHANGE the trajectory (posdiff > %.0f m, the INVERSE of slice-16's 0.0), got %s" % [POSDIFF_TOGGLE_MIN, posdiff])
			if not (end_err < 5.0):
				return _fail(":point_mass must fly the BALLISTIC arc p0+v0t+½gt² (end err %s m)" % end_err)
			# DELTA0: reset (→ :pitch_coupled) then set_param af_delta → 0 (the LEVER straightens the path).
			_reset_then_scan([_set_param_cmd("m1", "af_delta", 0.0)], STEPS, P.DELTA0)

		# --- af_delta → 0: the path STRAIGHTENS toward ballistic (the lever) ------------------------
		P.DELTA0:
			if not _drain_scan():
				return false
			var straight := _pos_max_diff(_ballistic_pos, _pos_trace)
			var toggle := _pos_max_diff(_coupled_pos, _ballistic_pos)
			print("S17V_DELTA0 end=(%.1f, %.1f)  posdiff_vs_ballistic=%s m  (the toggle was %s m — the lever)" %
				[_end_x(_pos_trace), _end_z(_pos_trace), straight, toggle])
			if not (straight < DELTA0_STRAIGHT_MAX):
				return _fail("af_delta→0 must STRAIGHTEN the path toward ballistic (< %.0f m), got %s" % [DELTA0_STRAIGHT_MAX, straight])
			if not (straight < 0.5 * toggle):
				return _fail("af_delta→0 must leave FAR less curve than the δ=0.15 toggle (%s ≥ 0.5·%s)" % [straight, toggle])
			return _pass()
	return false

# --- stepping / scanning (the slice-10..16 contract) --------------------------------------

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
	_lift_keys_seen = false
	_max_alift = 0.0
	_pos_trace = []

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: record the per-frame [pos_x, pos_z] trace (the toggle/lever comparison) and note whether the
# coupled-only a_lift / turn_radius_m keys ship. All RNG-free — no seeker draws, so the trace is
# deterministic (COUPLED_REPLAY asserts bit-identity).
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		var tel: Dictionary = f.get("telemetry", {})
		if _mid != "" and tel.has(_mid + ".pos_x"):
			_pos_trace.append([float(tel.get(_mid + ".pos_x", 0.0)), float(tel.get(_mid + ".pos_z", 0.0))])
			if tel.has(_mid + ".a_lift"):
				_lift_keys_seen = true
				_max_alift = maxf(_max_alift, absf(float(tel[_mid + ".a_lift"])))
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

func _pos_max_diff(a: Array, b: Array) -> float:
	var n := mini(a.size(), b.size())
	if n == 0:
		return 1.0e30                       # no overlap ⇒ treat as a failure
	var m := 0.0
	for i in n:
		m = maxf(m, absf(a[i][0] - b[i][0]))
		m = maxf(m, absf(a[i][1] - b[i][1]))
	return m

func _end_x(a: Array) -> float:
	return float(a[-1][0]) if not a.is_empty() else 0.0

func _end_z(a: Array) -> float:
	return float(a[-1][1]) if not a.is_empty() else 0.0

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
	# Slice 17 ships the `airframe_view` marker (from the airframe params) AND an `:airframe` fidelity
	# (point_mass ↔ pitch_coupled — the REAL toggle, the difference from slice 16, which carries none).
	if not bool(f.get("airframe_view", false)):
		return "a slice-17 handshake must ship airframe_view=true (the airframe view discriminator)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("airframe", "")) != "pitch_coupled":
		return "a slice-17 scenario must default the :airframe fidelity to pitch_coupled, got %s" % str(fid.get("airframe", "<absent>"))
	# one lesson per scenario: no view axes (that would flip the client to cfar/esm/geoloc/gps).
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-17 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the turn levers (af_delta / af_cla) must be exposed.
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not (keys.has("af_delta") and keys.has("af_cla")):
		return "slice-17 handshake must expose the 'af_delta' and 'af_cla' sliders — the turn levers"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S17V OK: the angle of attack α = θ−γ generates a body lift ⟂ v that TURNS the flight path — " +
		":pitch_coupled CURVES vs :point_mass ballistic (posdiff ≫ 0, the INVERSE of slice-16's 0.0), the " +
		"lift telemetry is coupled-only, the held-seed replay is bit-identical, and af_delta→0 STRAIGHTENS " +
		"the path (δ drives the turn). Physics-changing, RNG-free, live-settable (class 4c).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S17V FAIL: " + msg)
	print("S17V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
