extends SceneTree
# Headless slice-7 gate-3 verifier (the slice2..6_verify analog). It drives the REAL Julia server
# through SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-7's GPS
# "done" criterion as machine checks over BOTH scenarios (advisor: don't leave the RAIM lesson to a
# smoke-load). Start it against the slice7_dop server; it `load_scenario`s slice7_raim itself.
#
#   DOP scene (slice7_dop.yaml):
#     1. handshake carries `fidelity.raim == off` (→ the GPS/sky view discriminator) + the error-term
#        toggles (iono/tropo/noise on), and NO range_axis_m / pri_axis_us / estimator (a GPS scene is
#        not cfar/esm/geoloc — one lesson per scenario);
#     2. the DOPs are finite + positive, VDOP > HDOP on the shipped upper-hemisphere layout, and the
#        DECOMPOSITION identities hold exactly: gdop² = pdop²+tdop², pdop² = hdop²+vdop² (clean pins);
#     3. the DOP SWEEPS with the constellation drift — GDOP rises ≥ 20% from t≈0.1 s to t≈6 s (probed
#        3.05 → 4.57 as sv2+sv4 climb toward zenith and the spread collapses);
#     4. the ERROR BUDGET — `set_fidelity clock on` (draw-held, bit-identical t) moves pos_err_m by a
#        clear margin (probed 11.1 → 43.6 m: distinct per-SV clock errors corrupt POSITION). `clock`
#        is the REPRESENTATIVE wire toggle (the biggest lever); each of the five terms' individual
#        budget effect is pinned at the unit level in test_gps.jl (gate 2), and the receiver's per-key
#        wire dispatch is identical (`get(w.fidelity, key, :off)`), so one wire toggle suffices here.
#   RAIM scene (slice7_raim.yaml, via load_scenario):
#     5. handshake `fidelity.raim == detect` + the fault_bias_m slider; default fault (100 m) →
#        raim_flag == 1 (flag up on connect), n_sats_used == 6 (detect does not exclude);
#     6. the FAULT SLIDER is the not-a-dead-knob crossover: set_param fault_bias_m LOW (20 m) → flag
#        0 (below threshold); HIGH (120 m) → flag 1 — raises at the crossover, bit-identical t;
#     7. `set_fidelity raim exclude` DROPS n_sats_used to 5 (the bad satellite excluded, fault_sat>0)
#        and COLLAPSES pos_err_m (probed 211 → 5.6 m — the snap-back), all under a held seed.
#   All assertions on the SCALARS (pos_err_m / DOPs / raim_*); never the display-only sat_* arrays.
#
# Determinism note (slice 2/4/5/6): the trace at a given t is deterministic given the seed, and
# `step n` lands the clock at exactly n·dt, so each leg samples at an identical t. `reset` MUST
# precede set_fidelity/set_param (reset reloads the YAML → the defaults, and would clobber a toggle/
# slider). Every GPS key is introduce-safe (no draw hazard), so set_fidelity after boot is accepted.
#
# Run (server must be listening on slice7_dop.yaml first; it serves one client then exits):
#   godot --headless --path clients/godot --script res://net/slice7_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")
const RAIM_PATH := "scenarios/slice7_raim.yaml"

# Step counts are MULTIPLES of emit_every (16) so the LAST emit of a burst lands exactly on the
# target t (the slice-2/6 drain contract — an off-multiple count leaves the last frame short of t
# and the drain never reaches _t_target). 96 = 6·16 (t=0.096, ≥2 looks at revisit 50 ms); 5904 =
# 369·16 → early+late = 6000 (t=6.0, the drift-swept DOP sample).
const STEPS_EARLY := 96          # t=0.096 s — the DOP@early sample
const STEPS_LATE := 5904         # continue to t=6.0 s — the DOP@late sample (drift swept the geometry)
const STEPS_TOG := 96            # t=0.096 s for the error-toggle + all RAIM samples (identical t)
const GDOP_SWEEP := 1.20         # GDOP@late must exceed GDOP@early by ≥ this factor (probed 4.57/3.05)
const POSERR_TOG_MARGIN := 8.0   # `clock on` must move pos_err by ≥ this many m (probed Δ≈32)
const FAULT_LO := 20.0           # below threshold → flag 0 (probed stat 4.14)
const FAULT_HI := 120.0          # above threshold → flag 1 (probed stat > 14)
const POSERR_COLLAPSE := 0.5     # exclude pos_err must be < this × the detect pos_err (probed 5.6/211)

enum P { HANDSHAKE, DOP_EARLY, DOP_LATE, ERR_TOGGLE, RAIM_HANDSHAKE, RAIM_DETECT, RAIM_LOW, RAIM_HIGH, RAIM_EXCLUDE }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _rx := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# captured references
var _gdop_early := 0.0
var _poserr_early := 0.0
var _t_early := 0.0
var _poserr_detect := 0.0
var _t_low := 0.0

func _initialize() -> void:
	print("S7V_INIT godot=", Engine.get_version_info().string)
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
			var verr := _check_dop_handshake(f)
			if verr != "":
				return _fail(verr)
			_dt = float(f.get("dt_physics", 1.0e-3))
			_begin_step(STEPS_EARLY, P.DOP_EARLY)

		P.DOP_EARLY:
			if not _drain_to_T():
				return false
			if _rx == "":
				_rx = _find_rx(_last_state)
			if _rx == "":
				return _fail("no gps_receiver entity in the state stream (telemetry prefix unknown)")
			var gdop := _tel(_rx + ".gdop")
			var pdop := _tel(_rx + ".pdop")
			var hdop := _tel(_rx + ".hdop")
			var vdop := _tel(_rx + ".vdop")
			var tdop := _tel(_rx + ".tdop")
			# finite + positive
			for pair in [["gdop", gdop], ["pdop", pdop], ["hdop", hdop], ["vdop", vdop], ["tdop", tdop]]:
				if not (float(pair[1]) > 0.0 and float(pair[1]) < 1.0e8):
					return _fail("%s must be finite + positive, got %s" % [pair[0], str(pair[1])])
			# VDOP > HDOP on the shipped upper-hemisphere layout (the bonus geometry lesson)
			if not (vdop > hdop):
				return _fail("VDOP (%.3f) must exceed HDOP (%.3f) on the overhead spread" % [vdop, hdop])
			# decomposition identities (exact by definition — a clean wire pin)
			if absf(gdop * gdop - (pdop * pdop + tdop * tdop)) > 0.01 * gdop * gdop:
				return _fail("gdop² (%.4f) must equal pdop²+tdop² (%.4f)" % [gdop * gdop, pdop * pdop + tdop * tdop])
			if absf(pdop * pdop - (hdop * hdop + vdop * vdop)) > 0.01 * pdop * pdop:
				return _fail("pdop² (%.4f) must equal hdop²+vdop² (%.4f)" % [pdop * pdop, hdop * hdop + vdop * vdop])
			_gdop_early = gdop
			_poserr_early = _tel(_rx + ".pos_err_m")
			_t_early = float(_last_state.get("t", -1.0))
			print("S7V_DOP_EARLY rx=%s gdop=%.3f pdop=%.3f hdop=%.3f vdop=%.3f tdop=%.3f pos_err=%.2f t=%.4f" %
				[_rx, gdop, pdop, hdop, vdop, tdop, _poserr_early, _t_early])
			_begin_step(STEPS_LATE, P.DOP_LATE)     # continue drifting to t≈6 s

		P.DOP_LATE:
			if not _drain_to_T():
				return false
			var gdop_late := _tel(_rx + ".gdop")
			print("S7V_DOP_LATE gdop=%.3f (early %.3f, ratio %.2f) t=%.4f" %
				[gdop_late, _gdop_early, gdop_late / _gdop_early, float(_last_state.get("t", -1.0))])
			if not (gdop_late > _gdop_early * GDOP_SWEEP):
				return _fail("DOP must sweep with the drift: GDOP@late %.3f should be ≥ %.2f × GDOP@early %.3f" %
					[gdop_late, GDOP_SWEEP, _gdop_early])
			# error budget: reset (→ default, clock off) then clock ON, replay to the SAME early t.
			_reset_then_step([_set_fidelity_cmd("clock", "on")], STEPS_EARLY, P.ERR_TOGGLE)

		P.ERR_TOGGLE:
			if not _drain_to_T():
				return false
			var pe := _tel(_rx + ".pos_err_m")
			var t_tog := float(_last_state.get("t", -1.0))
			print("S7V_ERR_TOGGLE pos_err clock-on=%.2f (default %.2f, Δ=%.2f) t=%.4f (early t=%.4f)" %
				[pe, _poserr_early, pe - _poserr_early, t_tog, _t_early])
			if absf(t_tog - _t_early) > 0.5 * _dt:
				return _fail("error-toggle t must be bit-identical to the early sample (%.4f vs %.4f)" % [t_tog, _t_early])
			if absf(pe - _poserr_early) < POSERR_TOG_MARGIN:
				return _fail("`clock on` must move pos_err_m by ≥ %.1f m (default %.2f, clock-on %.2f)" %
					[POSERR_TOG_MARGIN, _poserr_early, pe])
			# switch to the RAIM scenario (re-handshake). Clear state so the next step bases off t=0.
			_inbox.clear()
			_last_state = {}
			_rx = ""
			_client.send({"type": "load_scenario", "path": RAIM_PATH})
			_phase = P.RAIM_HANDSHAKE

		P.RAIM_HANDSHAKE:
			var rf := _take("scenario")
			if rf.is_empty():
				return false
			if str(rf.get("name", "")) != "slice7_raim":
				return _fail("load_scenario did not switch to slice7_raim (got '%s')" % str(rf.get("name", "")))
			var rfid: Dictionary = rf.get("fidelity", {})
			if str(rfid.get("raim", "")) != "detect":
				return _fail("slice7_raim default raim should be 'detect' (flag visible on connect), got '%s'" % str(rfid.get("raim", "")))
			if rf.has("range_axis_m") or rf.has("pri_axis_us"):
				return _fail("a GPS scenario must not ship range_axis_m / pri_axis_us")
			# the fault slider must be exposed; capture its target (the spoofed satellite id) so the
			# set_param legs address the same satellite the scenario faults (discovered, not hardcoded).
			_fault_target = ""
			for k in rf.get("knobs", []):
				if str(k.get("key", "")) == "fault_bias_m":
					_fault_target = str(k.get("target", ""))
			if _fault_target == "":
				return _fail("slice7_raim handshake must expose the fault_bias_m slider")
			_dt = float(rf.get("dt_physics", 1.0e-3))
			_begin_step(STEPS_TOG, P.RAIM_DETECT)

		P.RAIM_DETECT:
			if not _drain_to_T():
				return false
			if _rx == "":
				_rx = _find_rx(_last_state)
			var flag := _tel(_rx + ".raim_flag")
			var stat := _tel(_rx + ".raim_stat")
			var nused := _tel(_rx + ".n_sats_used")
			_poserr_detect = _tel(_rx + ".pos_err_m")
			print("S7V_RAIM_DETECT flag=%.0f stat=%.3f n_used=%.0f pos_err=%.2f (default fault 100 m)" %
				[flag, stat, nused, _poserr_detect])
			if flag != 1.0:
				return _fail("default fault (100 m) must raise the integrity flag under :detect, got flag=%.0f" % flag)
			if nused != 6.0:
				return _fail(":detect must NOT exclude — n_sats_used should stay 6, got %.0f" % nused)
			# fault slider LOW → below threshold → flag clears.
			_reset_then_step([_set_param_cmd(_rx_sat(), "fault_bias_m", FAULT_LO)], STEPS_TOG, P.RAIM_LOW)

		P.RAIM_LOW:
			if not _drain_to_T():
				return false
			var flag := _tel(_rx + ".raim_flag")
			_t_low = float(_last_state.get("t", -1.0))
			print("S7V_RAIM_LOW fault=%.0f flag=%.0f stat=%.3f t=%.4f" % [FAULT_LO, flag, _tel(_rx + ".raim_stat"), _t_low])
			if flag != 0.0:
				return _fail("a sub-threshold fault (%.0f m) must NOT flag, got flag=%.0f" % [FAULT_LO, flag])
			# fault slider HIGH → above threshold → flag raises (the crossover).
			_reset_then_step([_set_param_cmd(_rx_sat(), "fault_bias_m", FAULT_HI)], STEPS_TOG, P.RAIM_HIGH)

		P.RAIM_HIGH:
			if not _drain_to_T():
				return false
			var flag := _tel(_rx + ".raim_flag")
			var t_hi := float(_last_state.get("t", -1.0))
			print("S7V_RAIM_HIGH fault=%.0f flag=%.0f stat=%.3f t=%.4f (low t=%.4f)" %
				[FAULT_HI, flag, _tel(_rx + ".raim_stat"), t_hi, _t_low])
			if flag != 1.0:
				return _fail("a supra-threshold fault (%.0f m) must flag, got flag=%.0f" % [FAULT_HI, flag])
			if absf(t_hi - _t_low) > 0.5 * _dt:
				return _fail("crossover samples must be at a bit-identical t (%.4f vs %.4f)" % [t_hi, _t_low])
			# exclude: drop the bad satellite, snap the fix back (default fault 100 restored by reset).
			_reset_then_step([_set_fidelity_cmd("raim", "exclude")], STEPS_TOG, P.RAIM_EXCLUDE)

		P.RAIM_EXCLUDE:
			if not _drain_to_T():
				return false
			var nused := _tel(_rx + ".n_sats_used")
			var fault_sat := _tel(_rx + ".fault_sat")
			var pe := _tel(_rx + ".pos_err_m")
			print("S7V_RAIM_EXCLUDE n_used=%.0f fault_sat=%.0f pos_err=%.2f (detect pos_err %.2f)" %
				[nused, fault_sat, pe, _poserr_detect])
			if nused != 5.0:
				return _fail(":exclude must drop the bad satellite — n_sats_used should be 5, got %.0f" % nused)
			if fault_sat <= 0.0:
				return _fail(":exclude must identify the faulted satellite (fault_sat > 0), got %.0f" % fault_sat)
			if not (pe < POSERR_COLLAPSE * _poserr_detect):
				return _fail(":exclude must collapse pos_err_m (< %.2f × detect %.2f), got %.2f" %
					[POSERR_COLLAPSE, _poserr_detect, pe])
			return _pass()
	return false

# --- stepping / draining (the slice-4/5/6 contract) ---------------------------------------

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

# --- helpers ------------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _find_rx(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "gps_receiver":
			return str(e.get("id", ""))
	return ""

# The faulted satellite id — discovered from the state entities (the sv carrying the fault). The
# slice7_raim.yaml faults sv3; discover it robustly rather than hardcode, by the one gps_satellite
# the fault slider targets (the handshake knob's target). Captured from the RAIM handshake.
var _fault_target := ""
func _rx_sat() -> String:
	return _fault_target

func _check_dop_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (GPS-view discriminator / §12 badge blind)"
	if not fid.has("raim"):
		return "a GPS scenario handshake must carry `raim` (the GPS-view discriminator)"
	if str(fid.get("raim", "")) != "off":
		return "slice7_dop default raim should be 'off' (no fault), got '%s'" % str(fid.get("raim", ""))
	if str(fid.get("iono", "")) != "on" or str(fid.get("tropo", "")) != "on" or str(fid.get("noise", "")) != "on":
		return "slice7_dop should default a realistic error subset (iono+tropo+noise on)"
	if fid.has("propagation") or fid.has("cfar") or fid.has("ep") or fid.has("estimator") or fid.has("deinterleaver"):
		return "a GPS scenario should carry ONLY the GPS fidelity keys (one lesson per scenario)"
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a GPS scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _tel(key: String) -> float:
	var tel: Dictionary = _last_state.get("telemetry", {})
	return float(tel.get(key, -1.0e30)) if tel.has(key) else -1.0e30

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S7V OK: DOP finite + decomposes (gdop²=pdop²+tdop², pdop²=hdop²+vdop²), VDOP>HDOP, sweeps " +
		"with drift; `clock` toggle moves pos_err; RAIM fault slider raises the flag at the crossover; " +
		":exclude drops a satellite and collapses pos_err (the snap-back)")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S7V FAIL: " + msg)
	print("S7V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
