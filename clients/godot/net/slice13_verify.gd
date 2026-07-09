extends SceneTree
# Headless slice-13 gate-3 verifier (the slice2..12_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-13's countermeasures
# "done" criteria as machine checks against the SCALAR telemetry. The lesson: a DECOY seduces a CFAR-
# scanning seeker; the α-β predicted-LOS GATE rejects it. One scenario (slice13_decoy), seeker=:scan /
# guidance=:pn / autopilot=:ideal HELD, the button toggling `discrimination`. FIVE phases:
#   • NONE (the yaml default): no discrimination → the intensity-weighted centroid of ALL detected peaks
#     walks the AIM toward the brighter decoy → the aim error is LARGE (several degrees) and the missile
#     MISSES the TRUE target (large min los_range). THE HEADLINE IS THE AIMPOINT ERROR |λ_est − λ_target|
#     (the gate-0 pivot — clean by construction, independent of endgame saturation), miss corroborates.
#   • GATED (set_fidelity discrimination gated): the nearest peak to the α-β PREDICTED bearing is kept
#     (the target-locked track rejects the separated decoy → the RGPO track-gate, in angle) → the aim
#     HOLDS on the truth (tiny aim error) and the missile INTERCEPTS (small min los_range).
#   • REPLAY (the RNG inflection RE-INVERTS to APPLIES — the :scan seeker DRAWS 2·N_p·N_bins/tick): a
#     same-seed reset must reproduce the trajectory BIT-FOR-BIT. Assert on an RNG-AFFECTED value (the
#     missile pos_x/pos_z sequence, NOT `t = n·dt` which is RNG-independent) — capture two runs, compare
#     element-wise (the slice-11 RNG-consumer discipline, one lesson deeper).
#   • SCAN_REJECT (the 4b guard on the wire): `set_fidelity seeker raw` REMOVES :scan → a draw-topology
#     flip (2·N_p·N_bins → 1) that would desync replay → the server REJECTS it with an `error` frame and
#     the seeker STAYS :scan (the trajectory is unperturbed). The mixed-introduce-safety proof:
#     `set_fidelity discrimination gated/none` is live (draw-invariant), `set_fidelity seeker scan`-touch
#     is refused.
# MISS/CPA is ALWAYS measured vs the true `:target` (the decoy is `kind :decoy` → `_nearest_target` skips
# it — the truth-path invariant); the number that opens under :none is the HONEST truth-miss.
#
# Frame sampling: the verifier sees state frames every emit_every (16) ticks. The AIM error is sampled
# over a MIDCOURSE window t ∈ [AIM_LO, AIM_HI] (pre-endgame — the decoy is resolved AND inside ±FOV/2
# there; re-probed on the emit grid, emit_probe.jl seed 6: none aim 4.83°/miss 598 m vs gated aim
# 0.054°/miss 4.16 m). Bounds are CONSERVATIVE one-sided (NOT the ratio — [[ewsim-missile-verifier-
# sampling]]): none aim > 3°, gated aim < 0.3°, none/gated ratio > 20×; none miss > 200 m, gated < 30 m.
#
# Run (server must be listening on scenarios/slice13_decoy.yaml first):
#   godot --headless --path clients/godot --script res://net/slice13_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 240.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 6000 = 375·16 covers the CPA (~4300 ticks) plus the opening range. The replay capture is shorter
# (2000 = 125·16) — enough frames to prove bit-identity without a full flight.
const STEPS := 6000
const REPLAY_STEPS := 2000
const AIM_LO := 0.4              # midcourse aim window (s) — decoy resolved AND inside ±FOV/2, pre-endgame
const AIM_HI := 1.4
const NONE_AIM_MIN := 0.0523599   # deg2rad(3.0): :none aim must be SEDUCED (probe 4.83° = 0.0842 rad)
const GATED_AIM_MAX := 0.0052360  # deg2rad(0.3): :gated aim HOLDS on truth (probe 0.054° = 0.00094 rad)
const AIM_RATIO_MIN := 20.0       # none/gated aim ratio (probe ~89×) — the Lesson ratio, one-sided
const NONE_MISS_MIN := 200.0      # :none misses the TRUE target (probe 597.6 m) — corroboration
const GATED_MISS_MAX := 30.0      # :gated intercepts (probe 4.16 m)

enum P { HANDSHAKE, NONE, GATED, REPLAY_A, REPLAY_B, SCAN_REJECT }

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
var _aim_win: Array = []          # aim_error samples within [AIM_LO, AIM_HI] (the midcourse headline)
var _pos_seq: Array = []          # [pos_x, pos_z] per frame — the RNG-affected replay identity value
var _decoy_out_of_fov := false    # latched if the decoy walks past ±FOV/2 during the aim window (lesson guard)

# recorded across phases
var _none_aim := 0.0
var _none_miss := 1.0e30
var _replay_a: Array = []
var _saw_error := false           # an `error` frame arrived (the scan-reject proof)

func _initialize() -> void:
	print("S13V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.NONE)

		# --- NONE (the yaml default): the seeker is SEDUCED → big aim error + a miss ----------------
		P.NONE:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_none_aim = _mean(_aim_win)
			_none_miss = _min_los
			print("S13V_NONE aim_mid=%.3f° miss=%.1f (n_aim=%d) — should be SEDUCED (big aim + miss)" %
				[rad_to_deg(_none_aim), _min_los, _aim_win.size()])
			if _decoy_out_of_fov:
				return _fail("the decoy walked OUTSIDE ±FOV/2 during the aim window — :none stops being seduced, the lesson collapses (re-probe the geometry)")
			if _aim_win.size() < 20:
				return _fail("too few midcourse aim samples (%d) to judge the headline" % _aim_win.size())
			if not (_none_aim > NONE_AIM_MIN):
				return _fail(":none must be SEDUCED (mid aim error > %.2f°), got %.3f°" % [rad_to_deg(NONE_AIM_MIN), rad_to_deg(_none_aim)])
			if not (_min_los > NONE_MISS_MIN):
				return _fail(":none must MISS the true target (min los_range > %s m), got %.1f" % [str(NONE_MISS_MIN), _min_los])
			# GATED: reset (→ none default) then set_fidelity discrimination gated, replay the same burst.
			_reset_then_scan([_set_fidelity_cmd("discrimination", "gated")], STEPS, P.GATED)

		# --- GATED (set_fidelity discrimination gated): the gate REJECTS the decoy → intercept --------
		P.GATED:
			if not _drain_scan():
				return false
			var gated_aim := _mean(_aim_win)
			print("S13V_GATED aim_mid=%.3f° miss=%.2f (n_aim=%d) — should HOLD (tiny aim + intercept)" %
				[rad_to_deg(gated_aim), _min_los, _aim_win.size()])
			if not (gated_aim < GATED_AIM_MAX):
				return _fail(":gated aim must HOLD on truth (mid aim error < %.2f°), got %.3f°" % [rad_to_deg(GATED_AIM_MAX), rad_to_deg(gated_aim)])
			if not (_min_los < GATED_MISS_MAX):
				return _fail(":gated must INTERCEPT the true target (min los_range < %s m), got %.2f" % [str(GATED_MISS_MAX), _min_los])
			# THE LESSON RATIO (the fusion is real): :none's aim is ≫ :gated's — the α-β gate is the
			# discriminator (CFAR alone can't reject a brighter decoy).
			if not (_none_aim > AIM_RATIO_MIN * gated_aim):
				return _fail(":none aim (%.3f°) must be ≫ :gated aim (%.3f°) — the discrimination Lesson ratio (> %s×)" %
					[rad_to_deg(_none_aim), rad_to_deg(gated_aim), str(AIM_RATIO_MIN)])
			if not (_none_miss > _min_los):
				return _fail(":none miss (%.1f) must exceed :gated miss (%.2f) — miss corroborates the aim headline" % [_none_miss, _min_los])
			# REPLAY A: reset (→ none default, held seed re-applied) and capture the pos sequence.
			_reset_then_scan([], REPLAY_STEPS, P.REPLAY_A)

		# --- REPLAY (the :scan seeker DRAWS → same-seed bit-identity is non-vacuous) -------------------
		P.REPLAY_A:
			if not _drain_scan():
				return false
			_replay_a = _pos_seq.duplicate(true)
			print("S13V_REPLAY_A captured %d frames (none default, held seed)" % _replay_a.size())
			if _replay_a.size() < 10:
				return _fail("replay-A captured too few frames (%d) to prove identity" % _replay_a.size())
			_reset_then_scan([], REPLAY_STEPS, P.REPLAY_B)

		P.REPLAY_B:
			if not _drain_scan():
				return false
			var b := _pos_seq
			print("S13V_REPLAY_B captured %d frames; comparing element-wise to A" % b.size())
			if b.size() != _replay_a.size():
				return _fail("replay frame COUNT differs (A=%d B=%d) — the stream desynced" % [_replay_a.size(), b.size()])
			for i in b.size():
				# BIT-identical: both runs go through the SAME JSON serialization, so identical float64s
				# round-trip identically — element-wise == is the honest same-seed replay check (on
				# pos_x/pos_z, an RNG-AFFECTED value under the 1280-draw/tick :scan seeker, NOT `t`).
				if b[i][0] != _replay_a[i][0] or b[i][1] != _replay_a[i][1]:
					return _fail("replay DESYNC at frame %d: A=(%s,%s) B=(%s,%s) — same seed must reproduce bit-for-bit" %
						[i, str(_replay_a[i][0]), str(_replay_a[i][1]), str(b[i][0]), str(b[i][1])])
			# SCAN_REJECT: the 4b guard on the wire — removing :scan must be REFUSED with an error frame.
			_saw_error = false
			_inbox.clear()
			_client.send(_set_fidelity_cmd("seeker", "raw"))   # REMOVE :scan → topology flip → rejected
			_client.send({"type": "step", "n": 16})            # a short step so the session keeps serving
			_t_target = _now_t() + 16 * _dt
			_phase = P.SCAN_REJECT

		# --- SCAN_REJECT: the server rejects removing :scan (an `error` frame; the seeker stays :scan) -
		P.SCAN_REJECT:
			while not _inbox.is_empty():
				var f: Dictionary = _inbox.pop_front()
				if str(f.get("type", "")) == "error":
					_saw_error = true
					print("S13V_SCAN_REJECT server error (expected): %s" % str(f.get("message", "")))
			if _now() - _t0 < MAX_SECONDS and not _saw_error:
				return false                                    # keep polling until the error frame lands
			if not _saw_error:
				return _fail("removing :scan (set_fidelity seeker raw) must be REJECTED with an error frame (the 4b topology guard)")
			return _pass()
	return false

# --- stepping / scanning (the slice-9/10/11 contract) -------------------------------------

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
	_aim_win = []
	_pos_seq = []
	_decoy_out_of_fov = false

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: accumulate min los_range (vs the TRUE target), the midcourse aim_error samples (the headline),
# the missile pos sequence (the RNG-affected replay identity), and whether the decoy stayed inside
# ±FOV/2 during the aim window (the lesson-collapse guard — if it walks out, only the target paints).
const FOV_HALF := 0.16            # N_bins·bin_width/2 = 64·0.005/2 (the ±FOV/2 grid half-width, rad)

func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		var tel: Dictionary = f.get("telemetry", {})
		var t := float(f.get("t", 0.0))
		if _mid != "" and tel.has(_mid + ".los_range"):
			var r := float(tel[_mid + ".los_range"])
			_min_los = minf(_min_los, r)
			_pos_seq.append([tel.get(_mid + ".pos_x", 0.0), tel.get(_mid + ".pos_z", 0.0)])
			if t >= AIM_LO and t <= AIM_HI:
				if tel.has(_mid + ".aim_error"):
					_aim_win.append(float(tel[_mid + ".aim_error"]))
				# decoy inside the grid: |wrap(decoy_bearing − lambda_est)| < FOV/2 (boresight = λ_est)
				if tel.has(_mid + ".decoy_bearing") and tel.has(_mid + ".lambda_est"):
					var off: float = absf(_wrap(float(tel[_mid + ".decoy_bearing"]) - float(tel[_mid + ".lambda_est"])))
					if off >= FOV_HALF:
						_decoy_out_of_fov = true
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# --- helpers ------------------------------------------------------------------------------

func _wrap(a: float) -> float:
	# ±π wrap (the bearings are atan(Δz,Δx) ∈ [−π,π]); a plain difference can straddle the seam.
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a

func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
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
		return "handshake carries no fidelity map (discrimination-view discriminator / §12 badge blind)"
	if not fid.has("discrimination"):
		return "a slice-13 scenario handshake must carry `discrimination` (the view discriminator / the cycled lesson)"
	if str(fid.get("discrimination", "")) != "none":
		return "slice-13 default discrimination should be 'none' (so the button REVEALS the fix), got '%s'" % str(fid.get("discrimination", ""))
	# seeker=:scan / guidance=:pn / autopilot=:ideal are HELD so the miss isolates DISCRIMINATION (conv. 9)
	if str(fid.get("seeker", "")) != "scan":
		return "slice-13 must hold seeker at 'scan' (the angular-profile-CFAR path the gate reuses), got '%s'" % str(fid.get("seeker", ""))
	if str(fid.get("guidance", "")) != "pn":
		return "slice-13 must hold guidance at 'pn' (the seeker feeds PN's ω), got '%s'" % str(fid.get("guidance", ""))
	if str(fid.get("autopilot", "")) != "ideal":
		return "slice-13 must hold autopilot at 'ideal' (isolates the discrimination lesson), got '%s'" % str(fid.get("autopilot", ""))
	# one lesson per scenario: no OTHER-slice fidelity keys, no cfar/esm/geoloc/gps view axes.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator"]:
		if fid.has(other):
			return "a slice-13 scenario should carry ONLY discrimination+seeker+guidance+autopilot (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-13 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the discrimination-lesson sliders must be exposed (the decoy intensity + the gate half-width levers)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	for want in ["intensity", "gate_halfwidth"]:
		if not keys.has(want):
			return "slice-13 handshake must expose the '%s' slider" % want
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S13V OK: a DECOY seduces the undiscriminated :scan seeker (:none — the intensity-weighted " +
		"centroid walks the aim off the truth → a MISS of the TRUE target), the α-β predicted-LOS GATE " +
		"rejects it (:gated — the RGPO track-gate in angle → the aim holds → intercept); the :scan seeker " +
		"DRAWS so the same-seed replay reproduces the trajectory bit-for-bit, and removing :scan is refused " +
		"(the 4b topology guard) — all on the wire, draw-invariant-among-rungs yet trajectory-changing, " +
		"miss ALWAYS vs the true target (the decoy never hijacks the truth path)")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S13V FAIL: " + msg)
	print("S13V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
