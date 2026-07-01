extends SceneTree
# Headless slice-6 gate-3 verifier (the slice2/3/4/5_verify analog). It drives the REAL Julia server
# (tools/server.jl scenarios/slice6_deinterleave.yaml) through SimClient.gd — the same protocol code
# Sandbox.tscn renders off — and asserts slice-6's "done" criterion as machine checks, because the
# PRI-deinterleaver lesson you judge by eye but the wire physics can be SILENTLY wrong:
#
#   1. handshake carries `fidelity.deinterleaver == cdif` (→ the ESM view) + the static PRI axis
#      `pri_axis_us` (len n_bins) + `dwell_us`, the jitter/intercept knobs, and NO range_axis_m
#      (a multi-emitter EW scenario is not CFAR); and `len(pri_axis_us) == len(histogram)` (the
#      axis labels every bar — an axis/binning mismatch the peak check alone would miss);
#   2. the DIFFERENCE HISTOGRAM raises peaks at each emitter's true PRI (1300/1700/2300 µs) above
#      the shipped threshold — the killer visual, pinned numerically;
#   3. the DEINTERLEAVER fidelity — the load-bearing `n_pri` flip: `set_fidelity deinterleaver`
#      cdif→sdif drops n_pri 4→3 (cdif declares a PHANTOM emitter at 2×1300≈2600 µs; sdif's
#      subharmonic check removes it), with the clock t BIT-IDENTICAL across rungs (held seed →
#      the rung is draw-free, the slice-4 :ep contract). And the SHARPEST form (advisor): the
#      histogram + threshold arrays are BIT-IDENTICAL across rungs — only the detected-PRI markers
#      (pri_us: 4 → 3) change. "Same bars, same threshold line, different markers" — the whole
#      shared-cumulative-pipeline claim, exact under the held seed;
#   4. the MEASUREMENT-QUALITY sliders (on the FIXED histogram, never the display-only toa/assign
#      arrays — the watch-item): `set_param jitter_us` blurs the peaks (max(histogram) drops);
#      `set_param p_intercept` thins the stream (sum(histogram) drops).
#
# `assoc_pct`'s DIRECTION (cdif vs sdif) is NOT asserted — the probe shows 0.9375 == 0.9375, exactly
# the plan's "direction unproven" caveat (commensurate-PRI coincidences cap it < 1 even noise-free);
# only finite + in [0,1] is checked. Determinism note (like slice 2/4/5): the stream at a given t is
# deterministic given the seed, and `step n` lands the clock at exactly n·dt, so each rung samples at
# an identical t. `reset` MUST precede `set_fidelity`/`set_param` (reset reloads the YAML →
# deinterleaver:cdif, jitter:0, p_intercept:1, and would clobber the toggle/slider). Step counts are
# MULTIPLES of emit_every (16) so the last emit of a burst lands exactly on the target t (the slice-2
# drain contract). `:deinterleaver` is introduce-safe, so set_fidelity after a cdif boot is accepted.
#
# Run (server must be listening on slice6_deinterleave.yaml first; it serves one client then exits):
#   godot --headless --path clients/godot --script res://net/slice6_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 120.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 160            # t=0.16s → ≥3 look-ticks (revisit 50 ms); all phases use it (identical t)
const BIN_US := 20.0          # histogram bin width (gate-1 proven) → bin index = floor(τ_us / 20)
const TRUE_PRIS := [1300.0, 1700.0, 2300.0]   # the three emitter fundamentals (µs)
const N_TRUE := 3
const N_CDIF := 4             # cdif: 3 fundamentals + a phantom at 2×1300 ≈ 2600 µs
const JITTER_BLUR := 40.0     # a big TOA jitter (µs, 2 bins) → the peaks smear
const BLUR_FRAC := 0.6        # jittered max(hist) must be < this × the clean max (probe: 16 vs 51)
const P_THIN := 0.4           # a low p_intercept → the stream thins
const THIN_FRAC := 0.5        # thinned sum(hist) must be < this × the clean sum (probe: 125 vs 687)

enum P { HANDSHAKE, CDIF, SDIF, JITTER, THIN }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _emit := 16
var _dt := 1.0e-3
var _esm := ""
var _pri_axis: Array = []
var _t_target := 0.0
var _last_state: Dictionary = {}

# captured clean (cdif) sample
var _hist_cdif: Array = []
var _thr_cdif: Array = []
var _clean_max := 0.0
var _clean_sum := 0.0
var _t_cdif := 0.0

var _t0 := 0.0

func _initialize() -> void:
	print("S6V_INIT godot=", Engine.get_version_info().string)
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
			_esm = str(f.get("esm", ""))
			_pri_axis = f.get("pri_axis_us", [])
			if _emit != 16:
				return _fail("verifier assumes emit_every=16 (step counts are multiples of 16); got %d" % _emit)
			_begin_step(STEPS, P.CDIF)

		P.CDIF:
			if not _drain_to_T():
				return false
			var hist: Array = _tel_arr(_last_state, _esm + ".histogram")
			var thr: Array = _tel_arr(_last_state, _esm + ".threshold")
			var pri: Array = _tel_arr(_last_state, _esm + ".pri_us")
			var n_pri := int(_tel(_last_state, _esm + ".n_pri"))
			var n_true := int(_tel(_last_state, _esm + ".n_true"))
			var ap := _tel(_last_state, _esm + ".assoc_pct")
			# handshake↔telemetry consistency: the axis labels every bar.
			if _pri_axis.size() != hist.size():
				return _fail("pri_axis_us (%d) != histogram (%d) — axis/binning mismatch" % [_pri_axis.size(), hist.size()])
			if n_true != N_TRUE:
				return _fail("n_true should be %d (the emitter count), got %d" % [N_TRUE, n_true])
			if n_pri != N_CDIF or pri.size() != N_CDIF:
				return _fail("cdif must declare %d PRIs (3 fundamentals + phantom), got n_pri=%d pri=%d" % [N_CDIF, n_pri, pri.size()])
			if not (ap >= 0.0 and ap <= 1.0):
				return _fail("assoc_pct must be finite in [0,1], got %f" % ap)
			# the histogram raises a peak above threshold at each TRUE PRI (the killer visual).
			var t0 := float(thr[0]) if thr.size() > 0 else 0.0
			for tau in TRUE_PRIS:
				var idx := int(tau / BIN_US)
				if idx >= hist.size() or float(hist[idx]) <= t0:
					return _fail("no above-threshold peak at PRI %.0f µs (bin %d, h=%.1f, thr=%.1f)" % [tau, idx, float(hist[idx]) if idx < hist.size() else -1.0, t0])
			_hist_cdif = hist
			_thr_cdif = thr
			_clean_max = _arr_max(hist)
			_clean_sum = _arr_sum(hist)
			_t_cdif = float(_last_state.get("t", -1.0))
			print("S6V_CDIF n_pri=%d pri=%s assoc=%.4f | hist max=%.0f sum=%.0f thr=%.1f | t=%.6f" %
				[n_pri, str(pri), ap, _clean_max, _clean_sum, t0, _t_cdif])
			# sdif leg: reset (→cdif), set sdif, replay to the SAME t.
			_reset_then_step([_set_fidelity_cmd("deinterleaver", "sdif")], STEPS, P.SDIF)

		P.SDIF:
			if not _drain_to_T():
				return false
			var hist: Array = _tel_arr(_last_state, _esm + ".histogram")
			var thr: Array = _tel_arr(_last_state, _esm + ".threshold")
			var pri: Array = _tel_arr(_last_state, _esm + ".pri_us")
			var n_pri := int(_tel(_last_state, _esm + ".n_pri"))
			var ap := _tel(_last_state, _esm + ".assoc_pct")
			var t_sdif := float(_last_state.get("t", -1.0))
			print("S6V_SDIF n_pri=%d pri=%s assoc=%.4f | t=%.6f (cdif t=%.6f)" % [n_pri, str(pri), ap, t_sdif, _t_cdif])
			# the load-bearing flip: 4 → 3 (the phantom removed).
			if n_pri != N_TRUE or pri.size() != N_TRUE:
				return _fail("sdif must recover %d PRIs (phantom removed), got n_pri=%d pri=%d" % [N_TRUE, n_pri, pri.size()])
			if not (ap >= 0.0 and ap <= 1.0):
				return _fail("sdif assoc_pct must be finite in [0,1], got %f" % ap)
			# bit-identical clock across rungs (held seed → the rung is draw-free).
			if absf(t_sdif - _t_cdif) > 0.5 * _dt:
				return _fail("clock must be bit-identical across rungs under a held seed (cdif t=%.6f, sdif t=%.6f)" % [_t_cdif, t_sdif])
			# THE SHARPEST CHECK (advisor): same bars, same threshold line — ONLY the markers move.
			if not _arrays_equal(hist, _hist_cdif):
				return _fail("histogram must be RUNG-INDEPENDENT (shared cumulative pipeline) — it changed cdif→sdif")
			if not _arrays_equal(thr, _thr_cdif):
				return _fail("threshold must be RUNG-INDEPENDENT — it changed cdif→sdif")
			# jitter leg: reset (→cdif, jitter 0), crank jitter_us, replay.
			_reset_then_step([_set_param_cmd(_esm, "jitter_us", JITTER_BLUR)], STEPS, P.JITTER)

		P.JITTER:
			if not _drain_to_T():
				return false
			var hist: Array = _tel_arr(_last_state, _esm + ".histogram")
			var jmax := _arr_max(hist)
			print("S6V_JITTER jitter_us=%.0f → hist max=%.0f (clean %.0f)" % [JITTER_BLUR, jmax, _clean_max])
			if jmax >= BLUR_FRAC * _clean_max:
				return _fail("TOA jitter must BLUR the peaks: max(hist) %.0f should be < %.2f × clean %.0f" % [jmax, BLUR_FRAC, _clean_max])
			# intercept leg: reset (→cdif, p_intercept 1), drop p_intercept, replay.
			_reset_then_step([_set_param_cmd(_esm, "p_intercept", P_THIN)], STEPS, P.THIN)

		P.THIN:
			if not _drain_to_T():
				return false
			var hist: Array = _tel_arr(_last_state, _esm + ".histogram")
			var tsum := _arr_sum(hist)
			print("S6V_THIN p_intercept=%.1f → hist sum=%.0f (clean %.0f)" % [P_THIN, tsum, _clean_sum])
			if tsum >= THIN_FRAC * _clean_sum:
				return _fail("low P(intercept) must THIN the stream: sum(hist) %.0f should be < %.2f × clean %.0f" % [tsum, THIN_FRAC, _clean_sum])
			return _pass()
	return false

# --- stepping / draining (the slice-4/5 contract) -----------------------------------------

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

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _tel(state: Dictionary, key: String) -> float:
	var tel: Dictionary = state.get("telemetry", {})
	return float(tel.get(key, -1.0e30)) if tel.has(key) else -1.0e30

func _tel_arr(state: Dictionary, key: String) -> Array:
	var tel: Dictionary = state.get("telemetry", {})
	return tel.get(key, []) if tel.has(key) else []

func _arr_max(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m

func _arr_sum(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s

func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if float(a[i]) != float(b[i]):
			return false
	return true

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (§12 badge / ESM-view discriminator would be blind)"
	if str(fid.get("deinterleaver", "")) != "cdif":
		return "scenario default deinterleaver should be 'cdif' (phantom visible on connect), got '%s'" % str(fid.get("deinterleaver", ""))
	if fid.has("propagation") or fid.has("cfar") or fid.has("ep") or fid.has("estimator"):
		return "a slice-6 EW scenario should carry ONLY the deinterleaver fidelity (one lesson per scenario)"
	if f.has("range_axis_m"):
		return "an ESM scenario must NOT ship range_axis_m (that flips the client to the CFAR view)"
	if not f.has("pri_axis_us"):
		return "handshake must ship pri_axis_us (the ESM-view discriminator + histogram τ-axis)"
	if not f.has("dwell_us"):
		return "handshake must ship dwell_us (the raster time span)"
	var knobs: Array = f.get("knobs", [])
	var saw_jit := false
	var saw_pint := false
	for k in knobs:
		if str(k.get("key", "")) == "jitter_us":
			saw_jit = true
		if str(k.get("key", "")) == "p_intercept":
			saw_pint = true
	if not (saw_jit and saw_pint):
		return "handshake must expose the jitter_us + p_intercept sliders"
	return ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S6V OK: histogram peaks at the true PRIs; deinterleaver cdif→sdif flips n_pri 4→3 " +
		"(same bars + threshold, only the markers move) with bit-identical t; jitter blurs / " +
		"p_intercept thins the histogram")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S6V FAIL: " + msg)
	print("S6V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
