extends SceneTree
# Headless slice-5 gate-3 verifier (the slice2/3/4_verify analog). It drives the REAL Julia server
# (tools/server.jl scenarios/slice5_geoloc.yaml) through SimClient.gd — the same protocol code
# Sandbox.tscn renders off — and asserts slice-5's "done" criterion as machine checks, because the
# GDOP/ellipse + estimator lessons you judge by eye but the wire physics can be SILENTLY wrong:
#
#   1. handshake carries `fidelity.estimator == pseudolinear` (→ the plan view) + σθ knobs, and NO
#      range_axis_m (a DF scenario is not CFAR);
#   2. GDOP + ELLIPSE STRETCH — as the emitter flies +x from GOOD geometry (t=8 s, x≈23 km) into
#      BAD geometry (t=40 s, x≈55 km), GDOP climbs AND the ellipse a/b ratio grows (the LOPs go from
#      near-orthogonal to grazing);
#   3. the ESTIMATOR fidelity — at the BAD sample, set_fidelity estimator pseudolinear→ml cuts the
#      fix error err_m sharply (the biased closed form collapses toward the sensors; ml walks it
#      back toward truth), and the clock t is BIT-IDENTICAL across the two rungs (held seed → the
#      rung is draw-free, the slice-4 :ep contract);
#   4. the σθ SLIDER — at the GOOD sample, scaling EVERY sensor's sigma_theta_deg (set_param) scales
#      the ellipse semi-axis ell_a ∝ σθ while GDOP stays BIT-IDENTICAL (advisor #2 on the wire:
#      GDOP is pure geometry at unit σ; the ellipse carries σθ). Uses tiny σθ (0.01°→0.02°) so the
#      realized geometry is σ-free and the scaling is clean (the ewsim-df-ellipse-sigma-monotonicity
#      gotcha: at realistic σθ a single live realization at a high-GDOP point is NOT monotone; the
#      good-geometry sample + tiny σ sidesteps it).
#
# Determinism note (like slice 2/4): the fix at a given t is deterministic given the drawn bearings,
# and `step n` lands the clock at exactly n·dt, so each rung's sample is at an identical t. `reset`
# MUST precede `set_fidelity`/`set_param` (reset reloads the YAML → estimator:pseudolinear, σθ:2.0,
# and would clobber the toggle). Step counts are MULTIPLES of emit_every (16) so the last emit of a
# burst lands exactly on the target t (the slice-2 drain contract). `:estimator` is introduce-safe,
# so set_fidelity :estimator after a pseudolinear boot is accepted by the server.
#
# Run (server must be listening on slice5_geoloc.yaml first; it serves one client then exits):
#   godot --headless --path clients/godot --script res://net/slice5_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 120.0
const SimClientScript := preload("res://net/SimClient.gd")

# step counts (multiples of emit_every=16 so the last frame lands exactly on target t).
const STEPS_GOOD := 8000      # t=8.0s  → emitter x≈23 km (GOOD geometry: low gdop, round ellipse)
const STEPS_BAD  := 40000     # t=40.0s → emitter x≈55 km (BAD geometry: high gdop, stretched ellipse)

const SIG_LO := 0.01          # tiny σθ (deg) for the clean ellipse-scaling leg
const SIG_HI := 0.02          # 2× σθ → expect ell_a ≈ 2× (cov ∝ σθ²)
const GDOP_RATIO_MIN := 1.5   # gdop(bad) must exceed gdop(good) by ≥ this (probe: ~3.4×)
const RATIO_GROW_MIN := 1.3   # ellipse a/b must grow good→bad by ≥ this (probe: 1.85→3.63 = 1.96×)
const ERR_DROP_FRAC  := 0.5   # ml err_m must be < this × pseudolinear err_m (probe: 0.13×)
const GDOP_EPS := 1.0e-3      # σθ-invariance: |gdop_hi − gdop_lo| ≤ this (truth-based → ~exact)
const ELL_RTOL := 0.05        # ell_a ≈ 2× within this rtol (probe: ratio 2.0003)

enum P { HANDSHAKE, GOOD, BAD, EST_ML, SIG_LO_P, SIG_HI_P }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _emit := 16
var _dt := 1.0e-3
var _station := ""
var _sensors: Array = []
var _t_target := 0.0
var _last_state: Dictionary = {}

# captured samples
var _gdop_good := 0.0
var _ratio_good := 0.0
var _gdop_bad := 0.0
var _ratio_bad := 0.0
var _err_pl := 0.0
var _t_bad := 0.0
var _ella_lo := 0.0
var _gdop_lo := 0.0

var _t0 := 0.0

func _initialize() -> void:
	print("S5V_INIT godot=", Engine.get_version_info().string)
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
			_emit = int(f.get("emit_every", 16))
			_dt = float(f.get("dt_physics", 1.0e-3))
			if _emit != 16:
				return _fail("verifier assumes emit_every=16 (step counts are multiples of 16); got %d" % _emit)
			_begin_step(STEPS_GOOD, P.GOOD)

		P.GOOD:
			if not _drain_to_T():
				return false
			if _station == "":
				_station = _station_id(_last_state)
				_sensors = _sensor_ids(_last_state)
			if _station == "":
				return _fail("no :df_station entity in the state stream")
			if _sensors.size() < 2:
				return _fail("expected ≥2 :df_sensor entities, got %d" % _sensors.size())
			# bearing LOP telemetry the plan view draws must be present + finite for each sensor.
			for s in _sensors:
				if not _finite_tel(_last_state, s + ".bearing_deg"):
					return _fail("sensor %s ships no finite bearing_deg" % s)
			_gdop_good = _tel(_last_state, _station + ".gdop")
			_ratio_good = _ratio_of(_last_state)
			if not (_gdop_good > 0.0 and _ratio_good > 0.0):
				return _fail("GOOD sample gdop/ratio not positive-finite (gdop=%.3f ratio=%.3f)" % [_gdop_good, _ratio_good])
			# reset (→ YAML pseudolinear/σθ=2, t=0) then fly to the BAD geometry.
			_reset_then_step([], STEPS_BAD, P.BAD)

		P.BAD:
			if not _drain_to_T():
				return false
			_gdop_bad = _tel(_last_state, _station + ".gdop")
			_ratio_bad = _ratio_of(_last_state)
			_err_pl = _tel(_last_state, _station + ".err_m")
			_t_bad = float(_last_state.get("t", -1.0))
			print("S5V_STRETCH good: gdop=%.0f a/b=%.2f | bad: gdop=%.0f a/b=%.2f | pseudolinear err=%.0f m" %
				[_gdop_good, _ratio_good, _gdop_bad, _ratio_bad, _err_pl])
			if _gdop_bad <= _gdop_good * GDOP_RATIO_MIN:
				return _fail("GDOP must climb good→bad by ≥%.1f× (good %.0f, bad %.0f)" % [GDOP_RATIO_MIN, _gdop_good, _gdop_bad])
			if _ratio_bad <= _ratio_good * RATIO_GROW_MIN:
				return _fail("ellipse a/b must grow good→bad by ≥%.1f× (good %.2f, bad %.2f)" % [RATIO_GROW_MIN, _ratio_good, _ratio_bad])
			# estimator leg: reset (→pseudolinear), set ml, replay to the SAME bad t.
			_reset_then_step([_set_fidelity_cmd("estimator", "ml")], STEPS_BAD, P.EST_ML)

		P.EST_ML:
			if not _drain_to_T():
				return false
			var err_ml := _tel(_last_state, _station + ".err_m")
			var t_ml := float(_last_state.get("t", -1.0))
			print("S5V_ESTIMATOR bad geometry: pseudolinear err=%.0f m | ml err=%.0f m (drop=%.2f×) | t pl=%.6f ml=%.6f" %
				[_err_pl, err_ml, _err_pl / max(err_ml, 1e-9), _t_bad, t_ml])
			if err_ml >= _err_pl * ERR_DROP_FRAC:
				return _fail("ml must cut err_m below %.2f× pseudolinear (pl %.0f, ml %.0f)" % [ERR_DROP_FRAC, _err_pl, err_ml])
			if absf(t_ml - _t_bad) > 0.5 * _dt:
				return _fail("clock must be bit-identical across rungs under a held seed (pl t=%.6f, ml t=%.6f)" % [_t_bad, t_ml])
			# σθ slider leg at the GOOD sample: scale EVERY sensor's σθ; expect ell_a ∝ σθ, gdop fixed.
			_reset_then_step(_sigma_cmds(SIG_LO), STEPS_GOOD, P.SIG_LO_P)

		P.SIG_LO_P:
			if not _drain_to_T():
				return false
			_ella_lo = _tel(_last_state, _station + ".ell_a")
			_gdop_lo = _tel(_last_state, _station + ".gdop")
			_reset_then_step(_sigma_cmds(SIG_HI), STEPS_GOOD, P.SIG_HI_P)

		P.SIG_HI_P:
			if not _drain_to_T():
				return false
			var ella_hi := _tel(_last_state, _station + ".ell_a")
			var gdop_hi := _tel(_last_state, _station + ".gdop")
			print("S5V_SIGMA σθ=%.2f°: ell_a=%.3f gdop=%.4f | σθ=%.2f°: ell_a=%.3f gdop=%.4f" %
				[SIG_LO, _ella_lo, _gdop_lo, SIG_HI, ella_hi, gdop_hi])
			if absf(gdop_hi - _gdop_lo) > GDOP_EPS:
				return _fail("GDOP must be σθ-INVARIANT (geometry at unit σ): %.4f vs %.4f" % [_gdop_lo, gdop_hi])
			var want := 2.0 * _ella_lo
			if absf(ella_hi - want) > ELL_RTOL * want:
				return _fail("ell_a must scale ∝σθ (2× σθ → 2× ell_a): lo %.3f, hi %.3f (want ≈%.3f)" % [_ella_lo, ella_hi, want])
			return _pass()
	return false

# --- stepping / draining (the slice-4 contract) -------------------------------------------

func _begin_step(n: int, next: P) -> void:
	var base := _now_t()
	_inbox.clear()
	_last_state = {}
	_t_target = base + n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_then_step(cmds: Array, n: int, next: P) -> void:
	_inbox.clear()
	_last_state = {}
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt          # reset zeroes the clock
	_client.send({"type": "step", "n": n})
	_phase = next

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

func _drain_to_T() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# --- frame helpers ------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _sigma_cmds(deg: float) -> Array:
	# one set_param per sensor — the ellipse scales ∝σθ only when ALL sensors scale together (cov is
	# a sum of per-sensor Fisher terms ∝ 1/σ²; moving one sensor doesn't give a clean global factor).
	var out: Array = []
	for s in _sensors:
		out.append({"type": "set_param", "target": s, "key": "sigma_theta_deg", "value": deg})
	return out

func _station_id(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "df_station":
			return str(e.get("id", ""))
	return ""

func _sensor_ids(state: Dictionary) -> Array:
	var out: Array = []
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "df_sensor":
			out.append(str(e.get("id", "")))
	out.sort()
	return out

func _tel(state: Dictionary, key: String) -> float:
	# a missing telemetry key would read as a sentinel and fail the asserts (not silently pass).
	var tel: Dictionary = state.get("telemetry", {})
	return float(tel.get(key, -1.0e30)) if tel.has(key) else -1.0e30

func _finite_tel(state: Dictionary, key: String) -> bool:
	var tel: Dictionary = state.get("telemetry", {})
	if not tel.has(key):
		return false
	var v := float(tel[key])
	return not (is_nan(v) or is_inf(v))

func _ratio_of(state: Dictionary) -> float:
	var a := _tel(state, _station + ".ell_a")
	var b := _tel(state, _station + ".ell_b")
	return a / b if b > 0.0 else -1.0

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (§12 badge / plan-view discriminator would be blind)"
	if str(fid.get("estimator", "")) != "pseudolinear":
		return "scenario default estimator should be 'pseudolinear', got '%s'" % str(fid.get("estimator", ""))
	if fid.has("propagation") or fid.has("cfar") or fid.has("ep"):
		return "a slice-5 DF scenario should carry ONLY the estimator fidelity (one lesson per scenario)"
	if f.has("range_axis_m"):
		return "a DF scenario must NOT ship range_axis_m (that flips the client to the CFAR view)"
	var knobs: Array = f.get("knobs", [])
	var saw_sigma := false
	for k in knobs:
		if str(k.get("key", "")) == "sigma_theta_deg":
			saw_sigma = true
	if not saw_sigma:
		return "handshake has no sigma_theta_deg (σθ) knob"
	return ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S5V OK: GDOP + ellipse stretch good→bad; estimator pseudolinear→ml cuts err_m (bit-identical t); " +
		"σθ slider scales ell_a ∝σθ while GDOP stays fixed")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S5V FAIL: " + msg)
	print("S5V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
