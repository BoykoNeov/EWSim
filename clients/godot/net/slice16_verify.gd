extends SceneTree
# Headless slice-16 gate-3 verifier (the slice8..15_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-16's pitch-plane
# ROTATIONAL-DYNAMICS "done" criteria as machine checks on the SCALAR telemetry (alpha / omega_sp /
# pitch_theta / gamma + the entity pos). The lesson: `att` is now a DYNAMICAL output of the aero pitching
# moment. Cmα<0 (STABLE) → the airframe WEATHERVANES (|α| bounded, rings toward trim, ω_sp REAL); flip Cmα>0
# (UNSTABLE) → it TUMBLES (|α| diverges to the wire ceiling, ω_sp is the FINITE_CEIL sentinel — no real
# short-period frequency). And the ISOLATION headline: the TRAJECTORY (pos) is BYTE-IDENTICAL across the
# Cmα flip — rotation reads (V, γ) but does NOT feed back into (pos, vel) this slice (α→lift is slice 17).
# That pos-invariance is WHY there is no `:airframe` fidelity toggle (it would name a path effect it can't
# produce yet — the convention-4c false-fidelity trap); the lesson lever is the LIVE af_cma KNOB. FOUR phases:
#   • STABLE       — default Cmα=-0.3: max|α| BOUNDED (< 0.30 rad), ω_sp REAL (0 < ω_sp ≪ FINITE_CEIL).
#                    Record the pos trace + max|α| for the replay/isolation comparisons.
#   • STABLE_REPLAY— reset + replay the SAME config → max|α| BIT-IDENTICAL (class-4c RNG-FREE determinism).
#   • UNSTABLE     — reset + set_param af_cma → +0.3 (the LIVE Cmα slider crossing 0, crash-safe): max|α|
#                    DIVERGES (≫ stable — the wire ceiling) AND ω_sp == FINITE_CEIL (no real freq) AND the
#                    pos trace is BIT-IDENTICAL to STABLE (the ISOLATION — rotation ⊥ translation).
#
# Everything is RNG-FREE (no seeker → no w.rng draw) so "byte-identity" is trivial-but-asserted (class 4c).
# Frame sampling: the verifier sees state frames every emit_every (16) ticks — numbers are FRAME-SAMPLED
# (emit_probe pins them: stable max|α|≈0.150 rad, ω_sp≈2.08; unstable max|α|→1e9, ω_sp==1e9; posdiff 0.0).
#
# Run (server must be listening on slice16_airframe.yaml first):
#   godot --headless --path clients/godot --script res://net/slice16_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 8000 = 500·16 covers ~3 short-period rings (T≈2.6 s) with the missile still climbing (no impact ~8 s).
const STEPS := 8000
const CMA_STABLE := -0.3            # the scenario default (STABLE — weathervanes)
const CMA_UNSTABLE := 0.3           # the live slider crosses 0 → UNSTABLE (tumbles)
const ALPHA_STABLE_MAX := 0.30      # stable max|α| ceiling (probe: 0.150 rad — the launch kick, rings down)
const ALPHA_UNSTABLE_MIN := 1.0     # unstable max|α| floor (probe: diverges to the 1e9 wire ceiling)
const FINITE_CEIL := 1.0e9          # the core's _finite ceiling (geometry.jl) — the ω_sp/α sentinel
const OMEGA_SENTINEL := 0.9e9       # ω_sp ≥ this ⇒ the imaginary-freq sentinel (unstable); < ⇒ a real freq

enum P { HANDSHAKE, STABLE, STABLE_REPLAY, UNSTABLE }

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
var _max_abs_alpha := 0.0
var _max_omega := 0.0                 # peak ω_sp seen (real ⇒ small; sentinel ⇒ FINITE_CEIL)
var _keys_seen := false               # the airframe telemetry keys ship (alpha/omega_sp)
var _pos_trace: Array = []            # per-frame [pos_x, pos_z] — the isolation comparison
# recorded across phases
var _stable_alpha := -1.0
var _stable_pos: Array = []

func _initialize() -> void:
	print("S16V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.STABLE)

		# --- Cmα<0: the airframe weathervanes — |α| bounded, ω_sp real -------------------------
		P.STABLE:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_stable_alpha = _max_abs_alpha
			_stable_pos = _pos_trace.duplicate(true)
			print("S16V_STABLE max|alpha|=%.5f rad  max_omega_sp=%.4f  keys=%s  frames=%d" %
				[_max_abs_alpha, _max_omega, str(_keys_seen), _pos_trace.size()])
			if not _keys_seen:
				return _fail(":af_cma missile must ship the alpha / omega_sp airframe telemetry keys")
			if not (_max_abs_alpha < ALPHA_STABLE_MAX):
				return _fail("Cmα<0 must keep |α| BOUNDED (weathervane; max|α| < %.2f rad), got %.5f" % [ALPHA_STABLE_MAX, _max_abs_alpha])
			if not (_max_omega > 0.0 and _max_omega < OMEGA_SENTINEL):
				return _fail("Cmα<0 must have a REAL short-period ω_sp (0 < ω_sp ≪ ceiling), got %s" % _max_omega)
			# REPLAY: reset (→ Cmα default) and re-fly — the frame-sampled max|α| must match bit-for-bit.
			_reset_then_scan([], STEPS, P.STABLE_REPLAY)

		P.STABLE_REPLAY:
			if not _drain_scan():
				return false
			print("S16V_REPLAY max|alpha|=%.6f (must EQUAL the first STABLE run — class-4c RNG-free determinism)" % _max_abs_alpha)
			if _max_abs_alpha != _stable_alpha:
				return _fail("held-config replay must be BIT-IDENTICAL (%.6f != %.6f) — RNG-free determinism" % [_max_abs_alpha, _stable_alpha])
			# UNSTABLE: reset (→ Cmα default) then set_param af_cma → +0.3 (the live slider crossing 0).
			_reset_then_scan([_set_param_cmd("m1", "af_cma", CMA_UNSTABLE)], STEPS, P.UNSTABLE)

		# --- Cmα>0: the airframe tumbles — |α| diverges, ω_sp is the sentinel; pos UNCHANGED ----
		P.UNSTABLE:
			if not _drain_scan():
				return false
			var posdiff := _pos_max_diff(_stable_pos, _pos_trace)
			# GDScript's % formatter supports only %f/%d/%s (no %g/%e) — use %s for the diverged/scientific values.
			print("S16V_UNSTABLE max|alpha|=%s  max_omega_sp=%s  posdiff_vs_stable=%s m  frames=%d" %
				[_max_abs_alpha, _max_omega, posdiff, _pos_trace.size()])
			if not (_max_abs_alpha > ALPHA_UNSTABLE_MIN):
				return _fail("Cmα>0 must DIVERGE (tumble; max|α| > %.1f rad), got %s" % [ALPHA_UNSTABLE_MIN, _max_abs_alpha])
			if not (_max_omega >= OMEGA_SENTINEL):
				return _fail("Cmα>0 must have NO real ω_sp (the FINITE_CEIL sentinel ≥ %s), got %s" % [OMEGA_SENTINEL, _max_omega])
			if not (_max_abs_alpha > 3.0 * _stable_alpha):
				return _fail("the UNSTABLE |α| (%s) must far exceed the STABLE |α| (%.5f) — the sign lesson" % [_max_abs_alpha, _stable_alpha])
			# THE ISOLATION HEADLINE: pos BYTE-IDENTICAL across the Cmα flip (rotation ⊥ translation).
			if not (posdiff == 0.0):
				return _fail("ISOLATION violated: pos must be BIT-IDENTICAL across the Cmα flip (rotation must not feed translation), got max diff %s m" % posdiff)
			return _pass()
	return false

# --- stepping / scanning (the slice-10..15 contract) --------------------------------------

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
	_max_abs_alpha = 0.0
	_max_omega = 0.0
	_keys_seen = false
	_pos_trace = []

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: accumulate max|α| + peak ω_sp (over ALL frames) and record the per-frame [pos_x, pos_z] trace for
# the isolation comparison. All RNG-free — no seeker draws, so the trace is deterministic.
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		var tel: Dictionary = f.get("telemetry", {})
		if _mid != "" and tel.has(_mid + ".alpha"):
			_keys_seen = true
			_max_abs_alpha = maxf(_max_abs_alpha, absf(float(tel[_mid + ".alpha"])))
			_max_omega = maxf(_max_omega, float(tel.get(_mid + ".omega_sp", 0.0)))
			_pos_trace.append([float(tel.get(_mid + ".pos_x", 0.0)), float(tel.get(_mid + ".pos_z", 0.0))])
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
	# Slice 16 carries NO fidelity block — the rotational integrator is gated on airframe PARAMS-PRESENCE,
	# and the handshake ships an `airframe_view` marker (server-side, from the params) instead. Assert the
	# marker is present and the fidelity map is EMPTY (the Cmα slider is the lesson, not a fidelity button).
	if not bool(f.get("airframe_view", false)):
		return "a slice-16 handshake must ship airframe_view=true (the rotational-dynamics view discriminator)"
	var fid: Dictionary = f.get("fidelity", {})
	if not fid.is_empty():
		return "a slice-16 scenario must carry NO fidelity (params-presence gate, not an :airframe rung), found %s" % str(fid.keys())
	# one lesson per scenario: no view axes (that would flip the client to cfar/esm/geoloc/gps).
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-16 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the Cmα slider (af_cma) must be exposed — the live lesson lever.
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("af_cma"):
		return "slice-16 handshake must expose the 'af_cma' (Cmα) slider — the lesson lever"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S16V OK: `att` is a DYNAMICAL output of the aero pitching moment — Cmα<0 WEATHERVANES (|α| " +
		"bounded, ω_sp real) vs Cmα>0 TUMBLES (|α| diverges, ω_sp is the sentinel), the live Cmα slider " +
		"crosses 0 crash-safe, and the TRAJECTORY is BYTE-IDENTICAL across the flip (rotation ⊥ translation " +
		"— the slice-16 isolation; α→lift coupling is slice 17). Physics-changing, RNG-free (class 4c).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S16V FAIL: " + msg)
	print("S16V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
