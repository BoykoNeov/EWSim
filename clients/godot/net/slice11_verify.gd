extends SceneTree
# Headless slice-11 gate-3 verifier (the slice2..10_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-11's noisy-seeker /
# LOS-rate-filter "done" criteria as machine checks against the SCALAR telemetry. One scenario
# (slice11_seeker), so this runs against a single server:
#   • FILTERED (the yaml default): the α-β LOS-rate filter yields a smooth λ̇ → :pn LEADS the crossing to
#     a TIGHT intercept (small frame-sampled min los_range), `saturated` mostly OFF, and λ̇_filt is FAR
#     smoother than the naïve λ̇_raw (var(λ̇_filt) ≪ var(λ̇_raw) — the whole lesson: the filter recovers
#     the rate WITHOUT differentiating).
#   • RAW (`set_fidelity seeker raw`): the naïve finite-difference amplifies the σ_seek angle noise by
#     1/dt → PN's N·Vc·λ̇ pegs `a_max` (`saturated` lit in the EARLY turn while the range is still large),
#     the command direction is near-random, and the miss OPENS WIDE (large min los_range).
#   • REPLAY (the RNG inflection — the FIRST non-vacuous missile-arc replay): the seeker is the first
#     w.rng consumer in the missile arc, so a same-seed reset must reproduce the trajectory BIT-FOR-BIT.
#     Assert on an RNG-AFFECTED value (the missile pos_x/pos_z sequence, NOT `t = n·dt` which is
#     RNG-independent and would pass vacuously) — capture two filtered runs and compare element-wise.
#
# Frame sampling: the verifier sees state frames every emit_every (16) ticks, so the frame-sampled min
# los_range is COARSER than the true CPA (probe seed 6: filtered true 0.39 m → frame-sampled ~0.39 m as
# the CPA lands on an emit boundary; the slice-10 PN_HIT_MAX precedent). Bounds are CONSERVATIVE one-sided
# (filtered < 30, raw > 300 — NOT the ratio; the raw miss is a random walk and the filtered side is
# floored by the frame sampling). `saturated`/`a_demand` are post-terminal-cutoff, so they read 0 near CPA
# AND spike in the r→0 endgame — so early-turn saturation is sampled ONLY while los_range > EARLY_RANGE
# (the slice-10 first-descending-band / _past_early latch, reused verbatim).
#
# Run (server must be listening on scenarios/slice11_seeker.yaml first):
#   godot --headless --path clients/godot --script res://net/slice11_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 240.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the slice-2..10 drain
# contract). 6000 = 375·16 covers the filtered CPA (~4300 ticks) and the raw approach/CPA. The replay
# capture is shorter (2000 = 125·16) — enough frames to prove bit-identity without a full flight.
const STEPS := 6000
const REPLAY_STEPS := 2000
const FILTERED_HIT_MAX := 30.0   # :filtered frame-sampled min los_range (probe seed 6: ~0.39 m)
const RAW_MISS_MIN := 300.0      # :raw degrades to a wide miss (probe seed 6: ~1391 m)
const EARLY_RANGE := 2500.0      # sample early-turn saturation only while los_range > this (avoid endgame)

enum P { HANDSHAKE, FILT, RAW, REPLAY_A, REPLAY_B }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# scan accumulators (reset per burst)
var _min_los := 1.0e30
var _sat_early := false           # `saturated` lit on the APPROACH while los_range > EARLY_RANGE
var _sat_count := 0               # frames with `saturated` lit (the raw-is-broken fraction)
var _frame_count := 0
var _past_early := false          # latched once los first drops below EARLY_RANGE (ignore post-CPA re-crossings)
var _lam_raw: Array = []          # λ̇_raw samples (the noisy finite-diff — jitters)
var _lam_filt: Array = []         # λ̇_filt samples (the α-β estimate — smooth)
var _pos_seq: Array = []          # [pos_x, pos_z] per frame — the RNG-affected replay identity value

# recorded across phases
var _filt_min := 1.0e30
var _replay_a: Array = []

func _initialize() -> void:
	print("S11V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.FILT)

		# --- FILTERED (the yaml default) --------------------------------------------------
		P.FILT:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_filt_min = _min_los
			var vr := _variance(_lam_raw)
			var vf := _variance(_lam_filt)
			print("S11V_FILT min_los=%.2f sat_frac=%.2f var(lam_raw)=%.3f var(lam_filt)=%.3f" %
				[_min_los, float(_sat_count) / maxf(1.0, _frame_count), vr, vf])
			if not (_min_los < FILTERED_HIT_MAX):
				return _fail(":filtered must INTERCEPT the crossing (frame-sampled min los_range < %s m), got %.2f" % [str(FILTERED_HIT_MAX), _min_los])
			# the α-β filter's whole point: λ̇_filt is SMOOTHER than the naïve λ̇_raw (same run, same draws)
			if not (vf < vr):
				return _fail(":filtered λ̇_filt must be SMOOTHER than λ̇_raw (var %.4f < %.4f) — the α-β variance reduction" % [vf, vr])
			# RAW: reset (→ filtered) then set_fidelity seeker raw, replay the same burst.
			_reset_then_scan([_set_fidelity_cmd("seeker", "raw")], STEPS, P.RAW)

		# --- RAW (set_fidelity seeker raw) ------------------------------------------------
		P.RAW:
			if not _drain_scan():
				return false
			print("S11V_RAW min_los=%.1f sat_frac=%.2f sat_early=%s (naïve finite-diff — should MISS WIDE)" %
				[_min_los, float(_sat_count) / maxf(1.0, _frame_count), str(_sat_early)])
			if not (_min_los > RAW_MISS_MIN):
				return _fail(":raw must DEGRADE (min los_range > %s m), got %.1f" % [str(RAW_MISS_MIN), _min_los])
			if not (_min_los > 10.0 * _filt_min):
				return _fail("raw miss (%.1f) must be ≫ filtered miss (%.1f) — the Lesson ratio" % [_min_los, _filt_min])
			# corroborating: the raw noise pegs a_max in the EARLY turn (saturation is real, not the endgame)
			if not _sat_early:
				return _fail(":raw must SATURATE in the early turn (`saturated` lit while los>%s m) — PN amplifies the angle noise by Vc/dt" % str(EARLY_RANGE))
			# REPLAY A: reset (→ filtered default, held seed re-applied) and capture the pos sequence.
			_reset_then_scan([], REPLAY_STEPS, P.REPLAY_A)

		# --- REPLAY (the first non-vacuous missile-arc same-seed identity) -----------------
		P.REPLAY_A:
			if not _drain_scan():
				return false
			_replay_a = _pos_seq.duplicate(true)
			print("S11V_REPLAY_A captured %d frames (filtered, held seed)" % _replay_a.size())
			if _replay_a.size() < 10:
				return _fail("replay-A captured too few frames (%d) to prove identity" % _replay_a.size())
			_reset_then_scan([], REPLAY_STEPS, P.REPLAY_B)

		P.REPLAY_B:
			if not _drain_scan():
				return false
			var b := _pos_seq
			print("S11V_REPLAY_B captured %d frames; comparing element-wise to A" % b.size())
			if b.size() != _replay_a.size():
				return _fail("replay frame COUNT differs (A=%d B=%d) — the stream desynced" % [_replay_a.size(), b.size()])
			for i in b.size():
				# BIT-identical: both runs go through the SAME JSON serialization, so identical float64s
				# round-trip identically — element-wise == is the honest same-seed replay check (on
				# pos_x/pos_z, an RNG-AFFECTED value, NOT the RNG-independent clock `t`).
				if b[i][0] != _replay_a[i][0] or b[i][1] != _replay_a[i][1]:
					return _fail("replay DESYNC at frame %d: A=(%s,%s) B=(%s,%s) — same seed must reproduce bit-for-bit" %
						[i, str(_replay_a[i][0]), str(_replay_a[i][1]), str(b[i][0]), str(b[i][1])])
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
	_sat_early = false
	_sat_count = 0
	_frame_count = 0
	_past_early = false
	_lam_raw = []
	_lam_filt = []
	_pos_seq = []

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: accumulate min los_range, the early-turn saturation (only while los_range > EARLY_RANGE — avoids
# the r→0 endgame spike), the λ̇ raw/filt samples (the smoothness tell), and the missile pos sequence
# (the RNG-affected replay-identity value).
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
			_frame_count += 1
			if float(tel.get(_mid + ".saturated", 0.0)) > 0.5:
				_sat_count += 1
			# early-turn saturation: sample ONLY on the first descending approach through the early
			# region (los > EARLY_RANGE, before los first drops below it) — the r→0 endgame spikes AND
			# the post-CPA divergence both saturate a clearing a_max, so they must be excluded (slice-10).
			if r <= EARLY_RANGE:
				_past_early = true
			if not _past_early and r > EARLY_RANGE:
				if float(tel.get(_mid + ".saturated", 0.0)) > 0.5:
					_sat_early = true
			_lam_raw.append(float(tel.get(_mid + ".lambda_dot_raw", 0.0)))
			_lam_filt.append(float(tel.get(_mid + ".lambda_dot_filt", 0.0)))
			_pos_seq.append([tel.get(_mid + ".pos_x", 0.0), tel.get(_mid + ".pos_z", 0.0)])
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# --- helpers ------------------------------------------------------------------------------

func _variance(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := 0.0
	for v in a:
		m += float(v)
	m /= a.size()
	var s := 0.0
	for v in a:
		var d := float(v) - m
		s += d * d
	return s / a.size()

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
		return "handshake carries no fidelity map (seeker-view discriminator / §12 badge blind)"
	if not fid.has("seeker"):
		return "a slice-11 scenario handshake must carry `seeker` (the seeker-view discriminator / the cycled lesson)"
	if str(fid.get("seeker", "")) != "filtered":
		return "slice-11 default seeker should be 'filtered' (the clean intercept), got '%s'" % str(fid.get("seeker", ""))
	# guidance HELD at :pn and autopilot at :ideal so the miss isolates the SEEKER/FILTER (convention 9)
	if str(fid.get("guidance", "")) != "pn":
		return "slice-11 must hold guidance at 'pn' (the seeker feeds PN's ω), got '%s'" % str(fid.get("guidance", ""))
	if str(fid.get("autopilot", "")) != "ideal":
		return "slice-11 must hold autopilot at 'ideal' (isolates the seeker lesson), got '%s'" % str(fid.get("autopilot", ""))
	# one lesson per scenario: no OTHER-slice fidelity keys, no cfar/esm/geoloc/gps view axes.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator"]:
		if fid.has(other):
			return "a slice-11 scenario should carry ONLY seeker+guidance+autopilot (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-11 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the seeker sliders must be exposed (the live noise + filter levers)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	for want in ["sigma_seek", "alpha", "beta"]:
		if not keys.has(want):
			return "slice-11 handshake must expose the '%s' slider" % want
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S11V OK: the α-β LOS-rate filter (:filtered) leads the crossing to a tight intercept with a " +
		"SMOOTH λ̇, :raw's naïve finite-diff amplifies the seeker angle noise → PN pegs a_max (saturated) " +
		"and the miss opens wide; the same-seed replay reproduces the missile trajectory bit-for-bit " +
		"(the first non-vacuous missile-arc replay) — all on the wire, draw-invariant yet trajectory-changing")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S11V FAIL: " + msg)
	print("S11V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
