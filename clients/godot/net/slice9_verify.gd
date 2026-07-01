extends SceneTree
# Headless slice-9 gate-3 verifier (the slice2..8_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-9's PID-autopilot
# "done" criterion as machine checks. Start it against the slice9_pursuit server (it serves one client
# then exits). ALL assertions on the SCALAR telemetry (a_cmd / a_ach / track_gap / los_range); the
# lesson is the commanded-vs-achieved GAP, NOT miss distance (miss conflates guidance + autopilot).
#
#   1. handshake carries `fidelity.autopilot == ideal` (→ the missile-view discriminator; the view stays
#      SPATIAL) + the kp/ki/kd/tau/k_guid sliders, and NO range_axis_m / pri_axis_us / estimator / raim /
#      integrator / cfar / ep / propagation (a guided-missile scene is single-domain — one lesson);
#   2. IDEAL — the perfect actuator: at a MID-FLIGHT sample (t=2 s) the achieved accel ≡ commanded, so
#      `track_gap` ≈ 0 (probed exactly 0). The interceptor CLOSES: stepping to t≈17 s the min `los_range`
#      over the burst reaches the target (probed miss ≈ 5 m), and the commanded `|a_cmd|` GROWS toward
#      intercept (~17 → 800+, the tail-chase — the slice-10 tee-up);
#   3. PID (the autopilot fidelity is LIVE) — reset (→ ideal) then `set_fidelity autopilot pid`, replay
#      to the SAME t=2 s: the DEFAULT gains are P-only, so the achieved accel UNDERSHOOTS and `track_gap`
#      JUMPS OPEN (probed ~6.5, ratio track_gap/a_cmd ≈ 1/3) — the gap the ideal actuator hides, at a
#      bit-identical t. The not-a-dead-knob: dialing the autopilot CHANGES the physics (unlike slice-5/6/7
#      draw-free toggles);
#   4. Kp SLIDER — reset, pid, `set_param kp = 8`: the P-only undershoot SHRINKS (ratio ≈ 1/9 < 1/3) —
#      the 1/(1+Kp) law on the wire (ORDERED, the exact closed form is the pure test_guidance pin);
#   5. Ki SLIDER — reset, pid, `set_param ki = 40, kd = 0.1`: INTEGRAL action drives the settled gap
#      toward ZERO (probed 0.78 ≪ the 6.5 P-only gap) — the intercept recovers.
#
# Determinism (slice 9 has NO RNG — deterministic ODE + PID): the trace at a given t is bit-identical
# for a fixed config, and `step n` lands the clock at exactly n·dt, so each t=2 leg samples an identical
# t. `reset` reloads the YAML → the defaults (ideal, P-only gains), so it MUST precede each set_fidelity/
# set_param (else it clobbers the toggle/slider). `:autopilot` is introduce-safe + physics-changing.
#
# Run (server must be listening on slice9_pursuit.yaml first):
#   godot --headless --path clients/godot --script res://net/slice9_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit of a burst lands exactly on the target t
# (the slice-2/6/7/8 drain contract). 2000 = 125·16 → t=2.0 s (mid-flight, a_cmd small ≪ a_max so the
# undershoot is clean of the clamp). 17008 = 1063·16 → t=17.008 s, just past the intercept (T≈16.97 s).
const STEPS_MID := 2000
const STEPS_HIT := 17008
const GAP_IDEAL_MAX := 1.0e-4     # :ideal track_gap ≈ 0 (probed exactly 0) — the perfect actuator
const GAP_PID_MIN := 2.0          # :pid P-only track_gap opens well above this (probed ~6.5)
const LOS_HIT_MAX := 12.0         # :ideal min los_range reaches the target (probed miss ≈ 5 m)
const ACMD_GROWTH := 5.0          # peak |a_cmd| ≥ this× the mid-flight value (tail-chase; probed ~48×)

enum P { HANDSHAKE, IDEAL_MID, IDEAL_HIT, PID_MID, KP8, KI }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""                    # missile entity id (discovered from the state stream)
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# accumulators for the IDEAL_HIT burst-scan (min range = intercept; peak/mid a_cmd = tail-chase growth)
var _min_los := 1.0e30
var _peak_acmd := 0.0
var _acmd_mid := 0.0
# recorded lesson numbers
var _t_ideal_mid := 0.0
var _gap_ponly := 0.0
var _ratio_ponly := 0.0

func _initialize() -> void:
	print("S9V_INIT godot=", Engine.get_version_info().string)
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
			_begin_step(STEPS_MID, P.IDEAL_MID)

		P.IDEAL_MID:
			if not _drain_to_T():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			var gap := _tel(_mid + ".track_gap")
			_acmd_mid = _tel(_mid + ".a_cmd")
			_t_ideal_mid = float(_last_state.get("t", -1.0))
			print("S9V_IDEAL_MID mid=%s track_gap=%s a_cmd=%.3f t=%.4f (ideal, perfect actuator)" %
				[_mid, str(gap), _acmd_mid, _t_ideal_mid])
			if not (_acmd_mid > 0.0):
				return _fail("mid-flight a_cmd must be > 0 (got %.3f) — sampled off the engagement" % _acmd_mid)
			if absf(gap) > GAP_IDEAL_MAX:
				return _fail(":ideal must track perfectly (track_gap ≈ 0 < %s), got %s" % [str(GAP_IDEAL_MAX), str(gap)])
			# IDEAL_HIT: reset (→ ideal) then step past the intercept, scanning the burst for min los +
			# peak a_cmd (the tail-chase growth).
			_min_los = 1.0e30; _peak_acmd = 0.0
			_reset_then_step([], STEPS_HIT, P.IDEAL_HIT)

		P.IDEAL_HIT:
			if not _drain_scan():                          # accumulates _min_los + _peak_acmd
				return false
			print("S9V_IDEAL_HIT min_los=%.2f peak|a_cmd|=%.1f (mid %.3f) t=%.4f" %
				[_min_los, _peak_acmd, _acmd_mid, float(_last_state.get("t", -1.0))])
			if not (_min_los < LOS_HIT_MAX):
				return _fail(":ideal interceptor must close (min los_range < %s m), got %.2f" % [str(LOS_HIT_MAX), _min_los])
			if not (_peak_acmd > ACMD_GROWTH * _acmd_mid):
				return _fail("|a_cmd| must GROW toward intercept (peak %.1f > %s× mid %.3f) — the tail-chase" %
					[_peak_acmd, str(ACMD_GROWTH), _acmd_mid])
			# PID: reset then set_fidelity pid (default P-only gains), replay to t=2 s.
			_reset_then_step([_set_fidelity_cmd("autopilot", "pid")], STEPS_MID, P.PID_MID)

		P.PID_MID:
			if not _drain_to_T():
				return false
			_gap_ponly = _tel(_mid + ".track_gap")
			var acmd := _tel(_mid + ".a_cmd")
			_ratio_ponly = _gap_ponly / maxf(acmd, 1.0e-9)
			var t_pid := float(_last_state.get("t", -1.0))
			print("S9V_PID_MID track_gap=%.3f a_cmd=%.3f ratio=%.4f t=%.4f (ideal-mid t=%.4f)" %
				[_gap_ponly, acmd, _ratio_ponly, t_pid, _t_ideal_mid])
			if absf(t_pid - _t_ideal_mid) > 0.5 * _dt:
				return _fail(":pid sample t must be bit-identical to :ideal (%.4f vs %.4f)" % [t_pid, _t_ideal_mid])
			if not (_gap_ponly > GAP_PID_MIN):
				return _fail(":pid P-only must OPEN the gap (track_gap > %s), got %.3f" % [str(GAP_PID_MIN), _gap_ponly])
			# KP8: reset, pid, kp=8 → the undershoot shrinks (ratio drops toward 1/9).
			_reset_then_step([_set_fidelity_cmd("autopilot", "pid"), _set_param_cmd(_mid, "kp", 8.0)], STEPS_MID, P.KP8)

		P.KP8:
			if not _drain_to_T():
				return false
			var gap := _tel(_mid + ".track_gap")
			var acmd := _tel(_mid + ".a_cmd")
			var ratio8 := gap / maxf(acmd, 1.0e-9)
			print("S9V_KP8 track_gap=%.3f a_cmd=%.3f ratio=%.4f (P-only ratio %.4f)" %
				[gap, acmd, ratio8, _ratio_ponly])
			if not (ratio8 < 0.7 * _ratio_ponly):
				return _fail("Kp=8 must SHRINK the undershoot (ratio %.4f < 0.7·%.4f) — the 1/(1+Kp) law" % [ratio8, _ratio_ponly])
			# KI: reset, pid, ki=40 kd=0.1 → integral drives the settled gap toward 0.
			_reset_then_step([_set_fidelity_cmd("autopilot", "pid"),
				_set_param_cmd(_mid, "ki", 40.0), _set_param_cmd(_mid, "kd", 0.1)], STEPS_MID, P.KI)

		P.KI:
			if not _drain_to_T():
				return false
			var gap := _tel(_mid + ".track_gap")
			print("S9V_KI track_gap=%.3f (P-only gap %.3f)" % [gap, _gap_ponly])
			if not (gap < 0.5 * _gap_ponly):
				return _fail("Ki=40 must CLOSE the gap (%.3f < 0.5·%.3f) — integral drives e_ss→0" % [gap, _gap_ponly])
			return _pass()
	return false

# --- stepping / draining (the slice-4..8 contract) ----------------------------------------

func _begin_step(n: int, next: P) -> void:
	_inbox.clear()
	_last_state = {}
	_t_target = _now_t() + n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_then_step(cmds: Array, n: int, next: P) -> void:
	_inbox.clear()
	_last_state = {}
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt              # reset zeroes the clock
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

# Scan variant: accumulate the MIN los_range (the intercept — closest approach, which the last frame
# overshoots) and the PEAK |a_cmd| (the tail-chase growth) across every drained frame of the burst.
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		var tel: Dictionary = f.get("telemetry", {})
		if tel.has(_mid + ".los_range"):
			_min_los = minf(_min_los, float(tel[_mid + ".los_range"]))
		if tel.has(_mid + ".a_cmd"):
			_peak_acmd = maxf(_peak_acmd, float(tel[_mid + ".a_cmd"]))
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
		return "handshake carries no fidelity map (missile-view discriminator / §12 badge blind)"
	if not fid.has("autopilot"):
		return "a guided-missile scenario handshake must carry `autopilot` (the missile-view discriminator)"
	if str(fid.get("autopilot", "")) != "ideal":
		return "slice9_pursuit default autopilot should be 'ideal' (the clean intercept), got '%s'" % str(fid.get("autopilot", ""))
	# one lesson per scenario: no other-slice fidelity keys (incl. the reserved slice-10 :guidance), no
	# cfar/esm/geoloc/gps view axes.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator", "guidance"]:
		if fid.has(other):
			return "a guided-missile scenario should carry ONLY `autopilot` (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a guided-missile scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the PID-gain sliders must be exposed (the live tuning levers)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	for want in ["kp", "ki", "kd", "tau", "k_guid"]:
		if not keys.has(want):
			return "slice9_pursuit handshake must expose the '%s' slider" % want
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
	print("S9V OK: :ideal tracks perfectly (track_gap ≈ 0) and the interceptor closes (min los_range " +
		"reaches the target) while |a_cmd| grows toward intercept (the tail-chase); :pid opens the gap " +
		"(P-only undershoot), Kp shrinks it (the 1/(1+Kp) law), Ki closes it (integral → e_ss 0) — all " +
		"on the wire, physics-changing, bit-identical t")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S9V FAIL: " + msg)
	print("S9V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
