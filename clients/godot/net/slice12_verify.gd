extends SceneTree
# Headless slice-12 gate-3 verifier (the slice8..11_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-12's augmented-PN /
# g-limit "done" criteria as machine checks on the SCALAR telemetry (a_cmd / a_demand / saturated /
# los_range). The lesson: against a MANEUVERING target under a BINDING g-limit, :apn INTERCEPTS (low
# demand, no saturation) while :pn SATURATES and MISSES; raising a_max lets :pn RECOVER (proving the
# g-limit was the binding constraint — HANDOFF §10 item 10, "g-limit saturation modeled, this is WHY
# augmented PN matters"). FOUR phases:
#   • APN_A       — the default :apn intercepts the maneuvering target (min los_range small) with NO
#                   early-turn saturation (the demand stays clear of a_max — the mechanism contrast).
#   • APN_REPLAY  — reset + replay the SAME :apn config → the frame-sampled min los_range is BIT-
#                   IDENTICAL (RNG-free determinism; the held-config replay proof).
#   • PN          — set_fidelity guidance pn: PN SATURATES the early/mid turn (`saturated` lit while the
#                   range is still large, a_demand > a_max) and the miss OPENS (min los_range large).
#   • PN_RECOVER  — reset + guidance pn + set_param a_max UP: PN RECOVERS (the miss closes, no early
#                   saturation) — the g-limit-is-the-constraint payoff, the not-a-dead-knob a_max lever.
# MISS is measured at CPA from TRUTH positions (the seeker/guidance noise never corrupts CPA — the
# slice-10/11 discipline). autopilot = :ideal so miss isolates the GUIDANCE LAW.
#
# Frame sampling: the verifier sees state frames every emit_every (16) ticks, so the frame-sampled min
# los_range is COARSER than the true CPA (probe: :apn true 0.59 m → frame-sampled 6.61 m). Thresholds
# are set against the FRAME-SAMPLED numbers (emit_probe.jl). `saturated`/`a_demand` are post-terminal-
# cutoff, so they read 0 near CPA AND spike in the r→0 endgame (before r_stop) — so approach saturation
# is sampled ONLY while los_range > ENDGAME_RANGE, on the first descending pass (avoid the r→0 spike +
# post-CPA re-crossings — the slice-10 advisor discipline).
#
# Run (server must be listening on slice12_apn.yaml first):
#   godot --headless --path clients/godot --script res://net/slice12_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 6000 = 375·16 covers the CPAs (:apn ~4116 ticks, :pn ~4325, :pursuit longer) plus the opening range.
const STEPS := 6000
const APN_HIT_MAX := 30.0        # :apn frame-sampled min los_range (probe: 6.61 m)
const PN_MISS_MIN := 50.0        # :pn saturates against the maneuver → big miss (probe: 166.9 m)
const PN_FREE_AMAX := 350.0      # the raised a_max that clears the demand (lesson window ~[100,350])
const PN_FREE_MISS_MAX := 30.0   # with a_max raised, :pn RECOVERS (probe: 3.8 m)
const ENDGAME_RANGE := 300.0     # sample approach saturation only while los_range > this (avoid r→0 spike)

enum P { HANDSHAKE, APN_A, APN_REPLAY, PN, PN_RECOVER }

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
var _min_los := 1.0e30
var _sat_approach := false       # `saturated` lit on the first descending approach while los > ENDGAME_RANGE
var _demand_approach := 0.0      # max a_demand on that approach (the saturation-is-real tell)
var _past_endgame := false       # latched once los first drops below ENDGAME_RANGE (ignore post-CPA re-crossings)
# recorded across phases
var _apn_min := 1.0e30

func _initialize() -> void:
	print("S12V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.APN_A)

		# --- :apn intercepts the maneuvering target (default) -----------------------------
		P.APN_A:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_apn_min = _min_los
			print("S12V_APN min_los=%.2f sat_approach=%s demand_approach=%.0f (:apn — should INTERCEPT, NO sat)" %
				[_min_los, str(_sat_approach), _demand_approach])
			if not (_min_los < APN_HIT_MAX):
				return _fail(":apn must INTERCEPT the maneuvering target (min los_range < %s m), got %.2f" % [str(APN_HIT_MAX), _min_los])
			if _sat_approach:
				return _fail(":apn must NOT saturate — the feedforward keeps the demand low (mechanism contrast)")
			# REPLAY: reset (→ apn default) and re-fly the SAME config — frame-sampled min must match bit-for-bit.
			_reset_then_scan([], STEPS, P.APN_REPLAY)

		P.APN_REPLAY:
			if not _drain_scan():
				return false
			print("S12V_REPLAY min_los=%.2f (must EQUAL the first :apn run — RNG-free determinism)" % _min_los)
			if _min_los != _apn_min:
				return _fail("held-config replay must be BIT-IDENTICAL (%.6f != %.6f) — RNG-free determinism" % [_min_los, _apn_min])
			# PN: reset (→ apn) then set_fidelity guidance pn, replay the same burst.
			_reset_then_scan([_set_fidelity_cmd("guidance", "pn")], STEPS, P.PN)

		# --- :pn saturates + misses against the same maneuver -----------------------------
		P.PN:
			if not _drain_scan():
				return false
			print("S12V_PN min_los=%.1f sat_approach=%s demand_approach=%.0f (:pn — should SATURATE + MISS)" %
				[_min_los, str(_sat_approach), _demand_approach])
			if not _sat_approach:
				return _fail(":pn must SATURATE against the maneuver (`saturated` lit while los > %s m)" % str(ENDGAME_RANGE))
			if not (_demand_approach > 200.0):
				return _fail(":pn approach a_demand (%.0f) must exceed a_max=200 — saturation is real, not an artifact" % _demand_approach)
			if not (_min_los > PN_MISS_MIN):
				return _fail(":pn saturation must OPEN the miss (min los_range > %s m), got %.1f" % [str(PN_MISS_MIN), _min_los])
			if not (_min_los > 5.0 * _apn_min):
				return _fail(":pn miss (%.1f) must be ≫ :apn miss (%.1f) — the augmented-PN Lesson ratio" % [_min_los, _apn_min])
			# RECOVER: reset (→ apn) then guidance pn + set_param a_max UP — the miss closes (g-limit lever).
			_reset_then_scan([_set_fidelity_cmd("guidance", "pn"), _set_param_cmd("m1", "a_max", PN_FREE_AMAX)], STEPS, P.PN_RECOVER)

		P.PN_RECOVER:
			if not _drain_scan():
				return false
			print("S12V_RECOVER min_los=%.1f sat_approach=%s (a_max=%s — :pn should RECOVER)" %
				[_min_los, str(_sat_approach), str(PN_FREE_AMAX)])
			if not (_min_los < PN_FREE_MISS_MAX):
				return _fail("raising a_max must let :pn RECOVER (min los_range < %s m), got %.1f — the g-limit is the constraint" % [str(PN_FREE_MISS_MAX), _min_los])
			if _sat_approach:
				return _fail("a raised a_max must NOT saturate the approach (the demand now fits under the clamp)")
			return _pass()
	return false

# --- stepping / scanning (the slice-9/10 contract) ----------------------------------------

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
	_sat_approach = false
	_demand_approach = 0.0
	_past_endgame = false

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: accumulate min los_range and the first-descending-approach saturation (only while los_range >
# ENDGAME_RANGE — avoids the r→0 endgame spike AND post-CPA re-crossings where a diverged missile spikes
# the demand into a clearing a_max).
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		var tel: Dictionary = f.get("telemetry", {})
		if _mid != "" and tel.has(_mid + ".los_range"):
			var r := float(tel[_mid + ".los_range"])
			_min_los = minf(_min_los, r)
			if r <= ENDGAME_RANGE:
				_past_endgame = true
			if not _past_endgame and r > ENDGAME_RANGE:
				if float(tel.get(_mid + ".saturated", 0.0)) > 0.5:
					_sat_approach = true
				_demand_approach = maxf(_demand_approach, float(tel.get(_mid + ".a_demand", 0.0)))
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

func _find_missile(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "missile":
			return str(e.get("id", ""))
	return ""

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (missile-view discriminator / the guidance badge blind)"
	if not fid.has("guidance"):
		return "a slice-12 scenario handshake must carry `guidance` (the missile-view discriminator / the cycled lesson)"
	if str(fid.get("guidance", "")) != "apn":
		return "slice-12 default guidance should be 'apn' (the augmented-PN intercept), got '%s'" % str(fid.get("guidance", ""))
	# autopilot is HELD at :ideal so miss isolates the guidance law (the slice-9 track_gap confound lifted)
	if str(fid.get("autopilot", "")) != "ideal":
		return "slice-12 must hold autopilot at 'ideal' (isolates the guidance-law lesson), got '%s'" % str(fid.get("autopilot", ""))
	# one lesson per scenario: no OTHER-slice fidelity keys, no cfar/esm/geoloc/gps view axes, no seeker.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator", "seeker"]:
		if fid.has(other):
			return "a slice-12 scenario should carry ONLY guidance+autopilot (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-12 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the a_lat / N / a_max sliders must be exposed (the live maneuver + guidance levers)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	for want in ["a_lat_mps2", "n_pn", "a_max"]:
		if not keys.has(want):
			return "slice-12 handshake must expose the '%s' slider" % want
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S12V OK: :apn leads the MANEUVERING target to a tight intercept with the demand clear of a_max, " +
		":pn saturates chasing the maneuver and MISSES wide, and raising a_max lets :pn recover — proving the " +
		"g-limit was the binding constraint (HANDOFF §10.10) — all on the wire, physics-changing, RNG-free")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S12V FAIL: " + msg)
	print("S12V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
