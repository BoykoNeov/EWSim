extends SceneTree
# Headless slice-4 gate-4 verifier (the slice2_verify / slice3_verify analog). It drives the
# REAL Julia server (tools/server.jl scenarios/slice4_selfscreen.yaml) through SimClient.gd —
# the same protocol code Sandbox.tscn renders off — and asserts slice-4's "done" criterion as
# machine checks, because the burn-through / EP lessons you judge by eye but the wire physics
# can be SILENTLY wrong. It covers BOTH slice-4 scenarios on the wire (the self-screen one the
# server boots on, then `load_scenario` to the standoff one — so the standoff's sidelobe-blanking
# headline is wire-verified too, not left to a smoke-load):
#
#   SELF-SCREEN (the boot scenario):
#     1. handshake carries `fidelity.ep == none` + a jammer-power knob;
#     2. BURN-THROUGH — as the self-screening target closes, J/S (js_db) flips sign: positive
#        (jammed) at long range, negative (burned through) near, and SNR_eff rises with it;
#     3. freq_agility HELPS (matched vs the 1 MHz spot jammer): at a fixed range it raises
#        SNR_eff by a clean margin (the radar hops out of the spot);
#     4. sidelobe_blanking is a NO-OP here (the jammer rides the mainlobe): SNR_eff is
#        BIT-IDENTICAL to ep=none at the same t.
#   STANDOFF (loaded mid-session):
#     5. handshake carries `fidelity.ep == none`;
#     6. sidelobe_blanking HELPS (matched vs the off-axis jammer): js_db drops by ~cancel_db
#        (≈30 dB) — the jammer is cancelled out of the sidelobe;
#     7. freq_agility is a NO-OP here (the jammer is BARRAGE, ≥ the agile band): js_db is
#        BIT-IDENTICAL to ep=none at the same t.
#
# Determinism note (same as slice 2): snr_db/js_db at a given t are pure geometry + link budget
# (RNG-independent), and `step n` lands the clock at exactly n·dt, so every sample is at an
# identical t. `reset` MUST precede `set_fidelity` (reset reloads the YAML → ep:none and would
# clobber the toggle). Step counts are MULTIPLES of emit_every (16) so the last emit of a burst
# lands exactly on the target t (the slice-2 drain contract). `ep` is introduce-safe, so unlike
# slice-3 cfar, set_fidelity :ep after an ep:none boot is accepted by the server.
#
# Run (server must be listening on slice4_selfscreen.yaml first; it serves one client then exits):
#   godot --headless --path clients/godot --script res://net/slice4_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 120.0
const SimClientScript := preload("res://net/SimClient.gd")
const STANDOFF_PATH := "scenarios/slice4_standoff.yaml"

# step counts (multiples of emit_every=16 so the last frame lands exactly on target t).
const STEPS_FAR  := 8336      # self-screen t=8.336s → target ~30 km (jammed,  J/S > 0)
const STEPS_NEAR := 48336     # self-screen t=48.336s → target ~6 km (burned through, J/S < 0)
const STEPS_REF  := 33328     # self-screen t=33.328s → target ~15 km (EP reference range)
const STEPS_SO   := 20000     # standoff   t=20.0s   → target ~30 km (masked by the sidelobe jammer)

const SNR_RISE_DB := 5.0      # min SNR_eff rise freq_agility must give (geometry gives ~10 dB)
const JS_DROP_DB  := 20.0     # min js_db drop sidelobe_blanking must give (cancel_db = 30 dB)
const NOOP_EPS    := 1.0e-6   # a matched/mismatched no-op must be bit-identical to ep=none

enum P {
	HANDSHAKE, BURN_FAR, BURN_NEAR, EP_NONE, EP_AGILE, EP_BLANK, KNOB_PWR,
	SO_HANDSHAKE, SO_NONE, SO_BLANK, SO_AGILE,
}

const KNOB_PJ_HI := 80.0     # raise jammer power 8 W → 80 W (×10 ≈ +10 dB J/S) at the ref range
const JS_RISE_DB := 5.0      # min js_db rise the power bump must produce (geometry gives ~+10 dB)

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _emit := 16
var _dt := 1.0e-3
var _radar := ""
var _t_target := 0.0
var _last_state: Dictionary = {}

# captured samples
var _js_far := 0.0
var _snr_far := 0.0
var _snr_none := 0.0          # self-screen EP reference (ep=none) SNR_eff at STEPS_REF
var _js_none_ref := 0.0       # self-screen (ep=none, default Pj) js_db at STEPS_REF — knob baseline
var _js_so_none := 0.0        # standoff (ep=none) js_db at STEPS_SO

var _t0 := 0.0

func _initialize() -> void:
	print("S4V_INIT godot=", Engine.get_version_info().string)
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
			var verr := _check_handshake(f, "ep", true)
			if verr != "":
				return _fail(verr)
			_emit = int(f.get("emit_every", 16))
			_dt = float(f.get("dt_physics", 1.0e-3))
			if _emit != 16:
				return _fail("verifier assumes emit_every=16 (step counts are multiples of 16); got %d" % _emit)
			_begin_step(STEPS_FAR, P.BURN_FAR)

		P.BURN_FAR:
			if not _drain_to_T():
				return false
			if _radar == "":
				_radar = _radar_id(_last_state)
			_js_far = _js_of(_last_state)
			_snr_far = _snr_of(_last_state)
			if _js_far <= 0.0:
				return _fail("burn-through: far target (~30 km) should be JAMMED (js_db>0); got %.2f" % _js_far)
			# continue closing (NO reset — one engagement) to the near sample
			_begin_step(STEPS_NEAR - STEPS_FAR, P.BURN_NEAR)

		P.BURN_NEAR:
			if not _drain_to_T():
				return false
			var js_near := _js_of(_last_state)
			var snr_near := _snr_of(_last_state)
			print("S4V_BURN far: js=%.2f snr=%.2f | near: js=%.2f snr=%.2f" % [_js_far, _snr_far, js_near, snr_near])
			if js_near >= 0.0:
				return _fail("burn-through: near target (~6 km) should be BURNED THROUGH (js_db<0); got %.2f" % js_near)
			if snr_near <= _snr_far:
				return _fail("burn-through: SNR_eff should RISE as the target closes (far %.2f → near %.2f)" % [_snr_far, snr_near])
			# EP reference: reset (→ YAML ep:none, t=0) then step to the fixed reference range.
			_reset_then_step([], STEPS_REF, P.EP_NONE)

		P.EP_NONE:
			if not _drain_to_T():
				return false
			_snr_none = _snr_of(_last_state)
			_js_none_ref = _js_of(_last_state)        # knob baseline (default Pj) at the ref range
			# freq_agility (matched vs the spot jammer) at the SAME reference range.
			_reset_then_step([_set_fidelity_cmd("ep", "freq_agility")], STEPS_REF, P.EP_AGILE)

		P.EP_AGILE:
			if not _drain_to_T():
				return false
			var snr_agile := _snr_of(_last_state)
			print("S4V_EP_SELF none: snr=%.2f | freq_agility: snr=%.2f (Δ=%.2f)" % [_snr_none, snr_agile, snr_agile - _snr_none])
			if snr_agile <= _snr_none + SNR_RISE_DB:
				return _fail("freq_agility should RAISE SNR_eff ≥ %.1f dB vs none (none %.2f, agile %.2f)" %
					[SNR_RISE_DB, _snr_none, snr_agile])
			# sidelobe_blanking is a NO-OP on this mainlobe self-screen jammer (bit-identical).
			_reset_then_step([_set_fidelity_cmd("ep", "sidelobe_blanking")], STEPS_REF, P.EP_BLANK)

		P.EP_BLANK:
			if not _drain_to_T():
				return false
			var snr_blank := _snr_of(_last_state)
			print("S4V_EP_NOOP none: snr=%.6f | sidelobe_blanking: snr=%.6f" % [_snr_none, snr_blank])
			if abs(snr_blank - _snr_none) > NOOP_EPS:
				return _fail("sidelobe_blanking must be a NO-OP on a mainlobe jammer (none %.6f, blank %.6f)" %
					[_snr_none, snr_blank])
			# THE jammer-power knob (the slice-4 headline interaction): raise jam1.pt_w via set_param
			# at the same range and the crossover must move — more power → more jam → js_db rises
			# (the slice-1 sandbox_verify precedent: prove the slider→core→telemetry loop on the wire,
			# not just that the slider emits set_param). reset BEFORE set_param (reset reloads Pj=8).
			_reset_then_step([{"type": "set_param", "target": "jam1", "key": "pt_w", "value": KNOB_PJ_HI}],
				STEPS_REF, P.KNOB_PWR)

		P.KNOB_PWR:
			if not _drain_to_T():
				return false
			var js_hi := _js_of(_last_state)
			print("S4V_KNOB Pj=8: js=%.2f | Pj=%.0f: js=%.2f (Δ=%.2f)" % [_js_none_ref, KNOB_PJ_HI, js_hi, js_hi - _js_none_ref])
			if js_hi <= _js_none_ref + JS_RISE_DB:
				return _fail("raising jammer power must raise js_db ≥ %.1f dB (Pj=8 %.2f, Pj=%.0f %.2f)" %
					[JS_RISE_DB, _js_none_ref, KNOB_PJ_HI, js_hi])
			# Switch to the standoff scenario (re-handshake) to wire-verify the sidelobe lesson.
			# Clear _last_state so the next _begin_step bases off the fresh clock (0), not the
			# stale self-screen t (load_scenario zeroes the server clock).
			_inbox.clear()
			_last_state = {}
			_client.send({"type": "load_scenario", "path": STANDOFF_PATH})
			_radar = ""
			_phase = P.SO_HANDSHAKE

		P.SO_HANDSHAKE:
			var f := _take("scenario")
			if f.is_empty():
				return false
			var verr := _check_handshake(f, "ep", false)
			if verr != "":
				return _fail("standoff " + verr)
			if str(f.get("name", "")) != "slice4_standoff":
				return _fail("load_scenario did not switch to slice4_standoff (got '%s')" % str(f.get("name", "")))
			_emit = int(f.get("emit_every", 16))
			_dt = float(f.get("dt_physics", 1.0e-3))
			_begin_step(STEPS_SO, P.SO_NONE)

		P.SO_NONE:
			if not _drain_to_T():
				return false
			if _radar == "":
				_radar = _radar_id(_last_state)
			_js_so_none = _js_of(_last_state)
			if _js_so_none <= 0.0:
				return _fail("standoff: target (~30 km) should be MASKED by the sidelobe jammer (js_db>0); got %.2f" % _js_so_none)
			# sidelobe_blanking (matched vs the off-axis jammer) at the SAME range.
			_reset_then_step([_set_fidelity_cmd("ep", "sidelobe_blanking")], STEPS_SO, P.SO_BLANK)

		P.SO_BLANK:
			if not _drain_to_T():
				return false
			var js_blank := _js_of(_last_state)
			print("S4V_SO_BLANK none: js=%.2f | sidelobe_blanking: js=%.2f (Δ=%.2f)" % [_js_so_none, js_blank, _js_so_none - js_blank])
			if js_blank >= _js_so_none - JS_DROP_DB:
				return _fail("sidelobe_blanking should DROP js_db ≥ %.1f dB (none %.2f, blank %.2f)" %
					[JS_DROP_DB, _js_so_none, js_blank])
			# freq_agility is a NO-OP vs this BARRAGE jammer (bit-identical js_db).
			_reset_then_step([_set_fidelity_cmd("ep", "freq_agility")], STEPS_SO, P.SO_AGILE)

		P.SO_AGILE:
			if not _drain_to_T():
				return false
			var js_agile := _js_of(_last_state)
			print("S4V_SO_NOOP none: js=%.6f | freq_agility: js=%.6f" % [_js_so_none, js_agile])
			if abs(js_agile - _js_so_none) > NOOP_EPS:
				return _fail("freq_agility must be a NO-OP on a BARRAGE jammer (none %.6f, agile %.6f)" %
					[_js_so_none, js_agile])
			return _pass()
	return false

# --- stepping / draining ------------------------------------------------------------------

# Issue a fresh `step n` burst (no reset) and drain toward t = base + n·dt in `next` phase, where
# base is the CURRENT clock (so a continuous close — FAR→NEAR — accumulates; a fresh handshake
# has _last_state={} → base 0). Read base BEFORE clearing _last_state.
func _begin_step(n: int, next: P) -> void:
	var base := _now_t()
	_inbox.clear()
	_last_state = {}
	_t_target = base + n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

# reset (→ YAML default ep:none, t=0), apply any pre-commands (e.g. set_fidelity), then step n.
# Order matters: reset BEFORE set_fidelity (reset would clobber the toggle — the slice-2 rule).
func _reset_then_step(cmds: Array, n: int, next: P) -> void:
	_inbox.clear()
	_last_state = {}
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt          # reset zeroes the clock
	_client.send({"type": "step", "n": n})
	_phase = next

# current sim clock from the last drained state (0 before any state seen this phase)
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

func _radar_id(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "radar":
			return str(e.get("id", ""))
	return ""

func _snr_of(state: Dictionary) -> float:
	return float((state.get("telemetry", {}) as Dictionary).get(_radar + ".snr_db", -999.0))

func _js_of(state: Dictionary) -> float:
	# js_db ships ONLY when the radar sees a jammer (it always does in these scenarios). A missing
	# key would read as 0.0 and silently pass the sign checks — guard with a sentinel instead.
	var tel: Dictionary = state.get("telemetry", {})
	return float(tel.get(_radar + ".js_db", -999.0)) if tel.has(_radar + ".js_db") else -999.0

func _check_handshake(f: Dictionary, fid_key: String, need_knobs: bool) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (§12 badge / toggle would be blind)"
	if str(fid.get(fid_key, "")) != "none":
		return "scenario default %s should be 'none', got '%s'" % [fid_key, str(fid.get(fid_key, ""))]
	if fid.has("propagation"):
		return "slice-4 scenario should NOT carry a propagation fidelity (button must be the ep cycler)"
	if need_knobs:
		var knobs: Array = f.get("knobs", [])
		var saw_jam_power := false
		for k in knobs:
			if str(k.get("target", "")) == "jam1" and str(k.get("key", "")) == "pt_w":
				saw_jam_power = true
		if not saw_jam_power:
			return "handshake has no jammer-power (jam1.pt_w) knob"
	return ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S4V OK: self-screen burn-through (J/S flips), freq_agility helps + sidelobe_blanking no-op; " +
		"standoff sidelobe_blanking drops J/S + freq_agility no-op (barrage)")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S4V FAIL: " + msg)
	print("S4V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
