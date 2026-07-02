extends SceneTree
# Headless slice-10 gate-3 verifier (the slice2..9_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-10's PN / g-limit
# "done" criteria as machine checks. It BRANCHES on the handshake scenario `name`, so it is run TWICE,
# once per server:
#   • slice10_pn    → LESSON 1: :pn INTERCEPTS the crossing (min los_range small) with |a_cmd| FALLING
#                     toward CPA; `set_fidelity guidance pursuit` DEGRADES it (large min-range) with
#                     |a_cmd| CLIMBING (the tail-chase). MISS is honest here (autopilot = :ideal).
#   • slice10_glimit→ LESSON 2: under :pn the a_max clamp BINDS in the early turn (`saturated` lit while
#                     the range is still large, a_demand > a_max) and the miss OPENS; `set_param a_max`
#                     UP shrinks the miss (the not-a-dead-knob g-limit lever), with no early saturation.
# ALL assertions on the SCALAR telemetry (a_cmd / a_demand / saturated / los_range).
#
# Frame sampling: the verifier sees state frames every emit_every (16) ticks, so the frame-sampled min
# los_range is COARSER than the true CPA (probe: :pn true 0.03 m → frame-sampled ~2.9 m; the slice-9
# LOS_HIT_MAX=12 precedent). Thresholds are set against the FRAME-SAMPLED numbers (gate3_framesampled).
# `saturated`/`a_demand` are post-terminal-cutoff, so they read 0 near CPA AND spike in the r→0 endgame
# (before r_stop) — so early-turn saturation is sampled ONLY while los_range > EARLY_RANGE (advisor).
#
# Run (server must be listening on the chosen slice-10 scenario first):
#   godot --headless --path clients/godot --script res://net/slice10_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the slice-2/6/7/8/9 drain
# contract). 6000 = 375·16 covers both CPAs on slice10_pn (:pn ~4286 ticks, :pursuit ~5269). 8000 =
# 500·16 covers the glimit CPAs.
const STEPS_PN := 6000
const STEPS_GL := 8000
const PN_HIT_MAX := 15.0        # :pn frame-sampled min los_range (probe: 2.87 m)
const PURSUIT_MISS_MIN := 100.0 # :pursuit degrades to a big miss (probe: 708 m)
const GL_BIND_MISS_MIN := 100.0 # glimit default a_max=300: saturation opens the miss (probe: 410 m)
const GL_FREE_MISS_MAX := 15.0  # glimit a_max raised: the miss closes (probe: 1.6 m)
const GL_AMAX_FREE := 1200.0    # the raised a_max that clears the ~785 m/s² demand
const EARLY_RANGE := 2500.0     # sample early-turn saturation only while los_range > this (avoid endgame)

enum P { HANDSHAKE, PN_A, PN_B, GL_BIND, GL_FREE }

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
var _acmd_far := -1.0           # a_cmd, FIRST descending pass through the far band [4500,5000] m (early)
var _acmd_near := -1.0          # a_cmd, FIRST descending pass through the near band [3000,3500] m (mid)
var _sat_early := false         # `saturated` lit on the APPROACH while los_range > EARLY_RANGE
var _demand_early := 0.0        # max a_demand on the approach while los_range > EARLY_RANGE
var _past_early := false        # latched once los first drops below EARLY_RANGE (ignore post-CPA re-crossings)
# recorded across phases
var _pn_min := 1.0e30

func _initialize() -> void:
	print("S10V_INIT godot=", Engine.get_version_info().string)
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
			# branch on the scenario: slice10_pn → Lesson 1; slice10_glimit → Lesson 2
			if _name == "slice10_glimit":
				_begin_scan(STEPS_GL, P.GL_BIND)
			else:
				_begin_scan(STEPS_PN, P.PN_A)

		# --- LESSON 1 (slice10_pn) --------------------------------------------------------
		P.PN_A:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_pn_min = _min_los
			print("S10V_PN min_los=%.2f a_cmd far=%.1f near=%.1f (:pn — should FALL near→far)" %
				[_min_los, _acmd_far, _acmd_near])
			if not (_min_los < PN_HIT_MAX):
				return _fail(":pn must INTERCEPT the crossing (min los_range < %s m), got %.2f" % [str(PN_HIT_MAX), _min_los])
			if not (_acmd_far > 0.0 and _acmd_near > 0.0):
				return _fail(":pn a_cmd bands not both sampled (far=%.1f near=%.1f)" % [_acmd_far, _acmd_near])
			if not (_acmd_near < _acmd_far):
				return _fail(":pn |a_cmd| must FALL toward CPA (near %.1f < far %.1f) — the collision triangle" % [_acmd_near, _acmd_far])
			# PURSUIT: reset (→ pn) then set_fidelity guidance pursuit, replay the same burst.
			_reset_then_scan([_set_fidelity_cmd("guidance", "pursuit")], STEPS_PN, P.PN_B)

		P.PN_B:
			if not _drain_scan():
				return false
			print("S10V_PURSUIT min_los=%.2f a_cmd far=%.1f near=%.1f (:pursuit — should CLIMB near>far)" %
				[_min_los, _acmd_far, _acmd_near])
			if not (_min_los > PURSUIT_MISS_MIN):
				return _fail(":pursuit must DEGRADE (min los_range > %s m), got %.2f" % [str(PURSUIT_MISS_MIN), _min_los])
			if not (_min_los > 10.0 * _pn_min):
				return _fail("pursuit miss (%.1f) must be ≫ PN miss (%.1f) — the Lesson-1 ratio" % [_min_los, _pn_min])
			if not (_acmd_near > _acmd_far):
				return _fail(":pursuit |a_cmd| must CLIMB toward abeam (near %.1f > far %.1f) — the tail-chase" % [_acmd_near, _acmd_far])
			return _pass("slice10_pn (Lesson 1)")

		# --- LESSON 2 (slice10_glimit) ----------------------------------------------------
		P.GL_BIND:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			print("S10V_GL_BIND min_los=%.1f sat_early=%s demand_early=%.0f (a_max=300, should SATURATE)" %
				[_min_los, str(_sat_early), _demand_early])
			if not _sat_early:
				return _fail("glimit default (a_max=300) must SATURATE in the early turn (`saturated` lit while los>%s m)" % str(EARLY_RANGE))
			if not (_demand_early > 300.0):
				return _fail("glimit early a_demand (%.0f) must exceed a_max=300 — saturation is real, not an artifact" % _demand_early)
			if not (_min_los > GL_BIND_MISS_MIN):
				return _fail("glimit saturation must OPEN the miss (min los_range > %s m), got %.1f" % [str(GL_BIND_MISS_MIN), _min_los])
			# FREE: reset (→ a_max=300) then set_param a_max UP, replay — the miss closes, no early saturation.
			_reset_then_scan([_set_param_cmd("m1", "a_max", GL_AMAX_FREE)], STEPS_GL, P.GL_FREE)

		P.GL_FREE:
			if not _drain_scan():
				return false
			print("S10V_GL_FREE min_los=%.1f sat_early=%s (a_max=%s, should CLOSE the miss)" %
				[_min_los, str(_sat_early), str(GL_AMAX_FREE)])
			if not (_min_los < GL_FREE_MISS_MAX):
				return _fail("raising a_max must CLOSE the miss (min los_range < %s m), got %.1f — the g-limit lever" % [str(GL_FREE_MISS_MAX), _min_los])
			if _sat_early:
				return _fail("a raised a_max must NOT saturate the early turn (the demand now fits under the clamp)")
			return _pass("slice10_glimit (Lesson 2)")
	return false

# --- stepping / scanning (the slice-9 contract) -------------------------------------------

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
	_acmd_far = -1.0
	_acmd_near = -1.0
	_sat_early = false
	_demand_early = 0.0
	_past_early = false

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: accumulate min los_range, the far/near a_cmd band samples (the fall-vs-climb tell), and the
# early-turn saturation (only while los_range > EARLY_RANGE — avoids the r→0 endgame spike).
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
			var acmd := float(tel.get(_mid + ".a_cmd", -1.0))
			# FIRST-write-wins per band (only the DESCENDING approach pass — los crosses each band on the
			# way IN; ignore post-CPA re-crossings where the diverged missile spikes a_cmd to the clamp).
			# Both bands sit ABOVE PN's terminal r→0 spike (~los 2800 m) so the fall/climb is clean.
			if _acmd_far < 0.0 and r >= 4500.0 and r <= 5000.0 and acmd >= 0.0:
				_acmd_far = acmd
			if _acmd_near < 0.0 and r >= 3000.0 and r <= 3500.0 and acmd >= 0.0:
				_acmd_near = acmd
			# early-turn saturation: sample ONLY on the first descending approach through the early
			# region (los > EARLY_RANGE, before los first drops below it) — the r→0 endgame spikes AND
			# the post-CPA divergence both saturate a clearing a_max, so they must be excluded (advisor C).
			if r <= EARLY_RANGE:
				_past_early = true
			if not _past_early and r > EARLY_RANGE:
				if float(tel.get(_mid + ".saturated", 0.0)) > 0.5:
					_sat_early = true
				_demand_early = maxf(_demand_early, float(tel.get(_mid + ".a_demand", 0.0)))
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
	if not fid.has("guidance"):
		return "a slice-10 scenario handshake must carry `guidance` (the missile-view discriminator / the cycled lesson)"
	if str(fid.get("guidance", "")) != "pn":
		return "slice-10 default guidance should be 'pn' (the clean intercept / the saturating law), got '%s'" % str(fid.get("guidance", ""))
	# autopilot is HELD at :ideal so miss isolates the guidance law (the slice-9 track_gap confound lifted)
	if str(fid.get("autopilot", "")) != "ideal":
		return "slice-10 must hold autopilot at 'ideal' (isolates the guidance-law lesson), got '%s'" % str(fid.get("autopilot", ""))
	# one lesson per scenario: no OTHER-slice fidelity keys, no cfar/esm/geoloc/gps view axes.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator"]:
		if fid.has(other):
			return "a slice-10 scenario should carry ONLY guidance+autopilot (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-10 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the N / a_max / r_stop sliders must be exposed (the live guidance levers)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	for want in ["n_pn", "a_max", "r_stop"]:
		if not keys.has(want):
			return "slice-10 handshake must expose the '%s' slider" % want
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass(which: String) -> bool:
	print("S10V OK (%s): :pn leads the crossing to a tight intercept with |a_cmd| falling toward the " % which +
		"collision triangle, :pursuit tail-chases into a big miss with |a_cmd| climbing; g-limit saturation " +
		"opens the miss and the a_max slider closes it — all on the wire, physics-changing")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S10V FAIL: " + msg)
	print("S10V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
