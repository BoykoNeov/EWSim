extends SceneTree
# Headless slice-15 gate-3 verifier (the slice10..14_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-15's rate-limited-fin
# "done" criteria as machine checks on the SCALAR telemetry (g_onset / fin_rate_sat / fin_defl_sat /
# saturated / los_range). The lesson: the :fin autopilot rung HARD-CAPS the achieved-g BUILD RATE at
# k_δ·δ̇_max (the g-onset cap — `g_onset` ≤ the cap EVERYWHERE by construction), the RATE limit BINDS
# (`fin_rate_sat` lit) while the DEFLECTION/magnitude limits do NOT (`fin_defl_sat==0 && saturated==0` —
# the isolation, so the cap is a clean RATE cap, not a slice-10 magnitude clamp in a fin costume), YET the
# MISS stays small (PN robust — the "lack of effect" IS the lesson, motivating the deferred 6-DOF). The
# δ̇_max slider is the lever (raise it → the cap RISES + the rate limit binds LESS, miss unchanged); :ideal
# ships NO fin keys (byte-identical wire — its frame-sampled onset is unmeasurable at this cadence, so the
# contrast is the no-key property, not a number). FIVE phases:
#   • FIN_A       — the default :fin caps the g-onset (max g_onset ≤ 1.02·cap), the RATE limit binds
#                   (rate_sat frames > 0) with defl_sat==0 && saturated==0 (isolation), miss small.
#   • FIN_REPLAY  — reset + replay the SAME :fin config → the frame-sampled min los_range is BIT-IDENTICAL
#                   (class-4c RNG-FREE determinism; the held-config replay proof — the slice-14 shape).
#   • RATE_RAISE  — reset + set_param δ̇_max UP: the cap RISES (max g_onset ≫ the default cap) and the rate
#                   limit binds LESS OFTEN (rate_sat frames DROP) while the miss stays small (the lever, the
#                   "lack of effect" — NOT a closing miss; the slice-10 g-limit CONTRAST).
#   • IDEAL       — reset + set_fidelity autopilot ideal (ACCEPTED live — class 4c, the slice-13 :scan-
#                   reject CONTRAST): the wire ships NO g_onset key (byte-identical wire) and the miss
#                   stays small (PN homes fine across the whole plant ladder).
# MISS is measured at CPA from TRUTH los_range (RNG-free — no seeker; the slice-10..14 discipline).
#
# Frame sampling: the verifier sees state frames every emit_every (16) ticks, so numbers are FRAME-SAMPLED,
# COARSER than tick resolution (emit_probe.jl pins them). The g_onset UPPER bound is robust (g_onset
# plateaus AT the cap for the whole slew, proven pointwise at gate 2). rate_sat is a FRAME COUNT (presence
# / a drop), not a peak — frame-sampling-tolerant. defl_sat/sat are sampled ONLY on the first descending
# approach while los_range > R_WIN (avoid the r→0 endgame + post-CPA re-crossings — the slice-10 advisor
# discipline). Miss bounds sit ABOVE the probed frame-sampled value (~9 m), NOT the tick-value (~6 m).
#
# Run (server must be listening on slice15_fin.yaml first):
#   godot --headless --path clients/godot --script res://net/slice15_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 6000 = 375·16 covers the CPA (~4300 ticks) plus the opening range.
const STEPS := 6000
const K_DELTA := 5000.0            # control effectiveness (m/s² per rad) — the scenario's k_δ
const DRMAX_DEFAULT := 0.4         # the scenario default δ̇_max (rad/s)
const DRMAX_RAISED := 2.0          # the raised δ̇_max the slider sends (the cap-rises lever)
const CAP_DEFAULT := K_DELTA * DRMAX_DEFAULT   # 2000 m/s³ — the default g-onset cap k_δ·δ̇_max
const GONSET_CEIL := 1.02 * CAP_DEFAULT        # 2040 — the ≤-cap upper bound (probe: 2000 exact)
const RATE_SAT_MIN := 5            # ≥ this many emit frames must show fin_rate_sat (probe: 11 — the bind)
const CAP_RAISED_MIN := GONSET_CEIL            # raised: max g_onset must exceed the DEFAULT cap (probe: 10000)
const MISS_MAX := 20.0             # frame-sampled miss ceiling (probe: :fin 6.6, :ideal 9.2 — well under)
const R_WIN := 200.0               # mid-course isolation window (sample sat only while los > R_WIN)

enum P { HANDSHAKE, FIN_A, FIN_REPLAY, RATE_RAISE, IDEAL }

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
var _max_gonset := 0.0
var _rate_sat_frames := 0        # # emit frames with fin_rate_sat lit on the first approach (los > R_WIN)
var _defl_sat_seen := false      # fin_defl_sat lit on the approach (isolation violation if true)
var _sat_seen := false           # saturated (a_max) lit on the approach (isolation violation if true)
var _keys_seen := false          # the :fin telemetry keys ship (false for :ideal/:pid)
var _past_endgame := false       # latched once los first drops below R_WIN (ignore post-CPA re-crossings)
# recorded across phases
var _fin_min := 1.0e30
var _fin_rate_frames := 0

func _initialize() -> void:
	print("S15V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.FIN_A)

		# --- :fin caps the g-onset, isolated; miss stays small --------------------------------
		P.FIN_A:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_fin_min = _min_los
			_fin_rate_frames = _rate_sat_frames
			print("S15V_FIN min_los=%.2f max_gonset=%.1f rate_sat_frames=%d defl_sat=%s sat=%s keys=%s" %
				[_min_los, _max_gonset, _rate_sat_frames, str(_defl_sat_seen), str(_sat_seen), str(_keys_seen)])
			if not _keys_seen:
				return _fail(":fin must ship the g_onset / fin_rate_sat telemetry keys")
			if not (_max_gonset <= GONSET_CEIL):
				return _fail(":fin g-onset must be CAPPED at k_δ·δ̇_max (≤ %.0f), got peak %.1f" % [GONSET_CEIL, _max_gonset])
			if not (_rate_sat_frames >= RATE_SAT_MIN):
				return _fail("the RATE limit must BIND (≥ %d emit frames with fin_rate_sat), got %d" % [RATE_SAT_MIN, _rate_sat_frames])
			if _defl_sat_seen or _sat_seen:
				return _fail("ISOLATION violated: fin_defl_sat/saturated lit on the approach (the cap is a MAGNITUDE clamp, not a clean rate cap)")
			if not (_min_los < MISS_MAX):
				return _fail(":fin must still HOME despite the capped g-onset (min los_range < %.0f m), got %.2f" % [MISS_MAX, _min_los])
			# REPLAY: reset (→ fin default) and re-fly the SAME config — frame-sampled min must match bit-for-bit.
			_reset_then_scan([], STEPS, P.FIN_REPLAY)

		P.FIN_REPLAY:
			if not _drain_scan():
				return false
			print("S15V_REPLAY min_los=%.6f (must EQUAL the first :fin run — class-4c RNG-free determinism)" % _min_los)
			if _min_los != _fin_min:
				return _fail("held-config replay must be BIT-IDENTICAL (%.6f != %.6f) — RNG-free determinism" % [_min_los, _fin_min])
			# RATE_RAISE: reset (→ fin) then set_param δ̇_max UP → the cap rises + the rate limit binds less.
			_reset_then_scan([_set_param_cmd("m1", "delta_rate_max", DRMAX_RAISED)], STEPS, P.RATE_RAISE)

		# --- raising δ̇_max RAISES the cap + binds LESS; miss unchanged ------------------------
		P.RATE_RAISE:
			if not _drain_scan():
				return false
			print("S15V_RAISE min_los=%.2f max_gonset=%.1f rate_sat_frames=%d (δ̇_max=%.1f — cap RISES, binds LESS)" %
				[_min_los, _max_gonset, _rate_sat_frames, DRMAX_RAISED])
			if not (_max_gonset > CAP_RAISED_MIN):
				return _fail("raising δ̇_max must RAISE the g-onset cap (max g_onset > %.0f), got %.1f" % [CAP_RAISED_MIN, _max_gonset])
			if not (_rate_sat_frames < _fin_rate_frames):
				return _fail("raising δ̇_max must make the RATE limit bind LESS (rate_sat frames %d must be < the default %d)" % [_rate_sat_frames, _fin_rate_frames])
			if _sat_seen:
				return _fail("a raised δ̇_max must NOT trip the magnitude a_max (the demand still fits under the clamp)")
			if not (_min_los < MISS_MAX):
				return _fail("the miss must stay SMALL as the cap rises (the 'lack of effect' — min los_range < %.0f m), got %.2f" % [MISS_MAX, _min_los])
			# IDEAL: reset (→ fin) then set_fidelity autopilot ideal — accepted live, ships NO fin keys.
			_reset_then_scan([_set_fidelity_cmd("autopilot", "ideal")], STEPS, P.IDEAL)

		# --- :ideal is accepted live + ships no fin keys; miss still small --------------------
		P.IDEAL:
			if not _drain_scan():
				return false
			print("S15V_IDEAL min_los=%.2f keys=%s (autopilot ideal — accepted LIVE, ships NO fin keys)" %
				[_min_los, str(_keys_seen)])
			if _keys_seen:
				return _fail(":ideal must ship NO g_onset / fin_rate_sat keys (byte-identical wire — the plant is bypassed)")
			if not (_min_los < MISS_MAX):
				return _fail(":ideal must still HOME (min los_range < %.0f m), got %.2f — PN robust across the plant ladder" % [MISS_MAX, _min_los])
			return _pass()
	return false

# --- stepping / scanning (the slice-10..14 contract) --------------------------------------

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
	_max_gonset = 0.0
	_rate_sat_frames = 0
	_defl_sat_seen = false
	_sat_seen = false
	_keys_seen = false
	_past_endgame = false

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: accumulate min los_range + the peak g_onset (over ALL frames — the cap holds everywhere) + the
# first-descending-approach rate/defl/a_max saturation (only while los_range > R_WIN — avoids the r→0
# endgame AND post-CPA re-crossings where a diverged missile spikes demand into a_max).
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
			if r <= R_WIN:
				_past_endgame = true
			if tel.has(_mid + ".g_onset"):
				_keys_seen = true
				_max_gonset = maxf(_max_gonset, float(tel[_mid + ".g_onset"]))
				if not _past_endgame and r > R_WIN:
					if float(tel.get(_mid + ".fin_rate_sat", 0.0)) > 0.5:
						_rate_sat_frames += 1
					if float(tel.get(_mid + ".fin_defl_sat", 0.0)) > 0.5:
						_defl_sat_seen = true
					if float(tel.get(_mid + ".saturated", 0.0)) > 0.5:
						_sat_seen = true
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
		return "handshake carries no fidelity map (the missile-view discriminator / the autopilot badge blind)"
	if str(fid.get("autopilot", "")) != "fin":
		return "a slice-15 scenario handshake must carry autopilot:fin (the rate-limited fin plant / the cycled lesson), got '%s'" % str(fid.get("autopilot", ""))
	# guidance is HELD at :pn so the fin-plant lesson is uncontaminated by the outer law
	if str(fid.get("guidance", "")) != "pn":
		return "slice-15 must hold guidance at 'pn' (isolates the fin-plant lesson), got '%s'" % str(fid.get("guidance", ""))
	# one lesson per scenario: no OTHER-slice fidelity keys, no cfar/esm/geoloc/gps view axes, no seeker.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator", "seeker", "cooperation"]:
		if fid.has(other):
			return "a slice-15 scenario should carry ONLY autopilot+guidance (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-15 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the δ̇_max / a_lat / a_max sliders must be exposed (the live fin-rate + maneuver + magnitude levers)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	for want in ["delta_rate_max", "a_lat_mps2", "a_max"]:
		if not keys.has(want):
			return "slice-15 handshake must expose the '%s' slider" % want
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S15V OK: :fin HARD-CAPS the achieved-g build rate at k_δ·δ̇_max (rate limit binds, deflection/" +
		"magnitude limits do NOT — a clean isolated rate cap) yet the missile HOMES (PN robust — the 'lack " +
		"of effect'); raising δ̇_max raises the cap and binds less with the miss unchanged; :ideal is accepted " +
		"live and ships no fin keys — all on the wire, physics-changing (class 4c), RNG-free")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S15V FAIL: " + msg)
	print("S15V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
