extends SceneTree
# Headless slice-25 gate-3 verifier (the slice24_verify analog). Drives the REAL Julia server through
# SimClient.gd and asserts slice-25's "a seeker in the 6-DOF loop" done-criteria as machine checks.
#
# THE LESSON: slice 23 gave the missile an airframe that can turn OUT of the x–z plane and slice 24
# made it choose how to point its lift — both TRUTH-FED. Give it a REAL seeker and slice 11's sensor
# carries the SAME approximation one layer up: a SCALAR in-plane bearing whose reconstructed LOS rate
# ω = (0, −λ̇, 0) is STRUCTURALLY incapable of an out-of-plane component. The 6-DOF airframe is never
# TOLD to turn. Measure an azimuth/elevation PAIR instead (ω = û × û̇) and the same airframe intercepts.
#
# FIVE phases:
#   • PITCH_PLANE — the default MISSES (frame CPA ≈ 2000 m) with max|y| == 0.0 EXACTLY and the seeker's
#                   reported out-of-plane ω == 0.0 EXACTLY on EVERY frame (the structural tell — this
#                   is not a tuning artifact), and `aero_sat` NEVER fires.
#   • REPLAY      — reset + replay the SAME config → the 3-D pos trace is BIT-IDENTICAL. ⚠ UNLIKE
#                   slices 14–24 this is NOT RNG-free: the seeker draws 2 randn/tick, so this is
#                   SEEDED determinism (class 4a — the seed is load-bearing again, first since 13).
#   • AZ_EL       — set_fidelity seeker_axes → az_el (the LIVE toggle, the ONE button): the SAME
#                   airframe, the SAME PN law, the SAME target — INTERCEPT (frame CPA ≈ 9.6 m).
#   • ISOLATION   — asserted INSIDE both flight phases: `aero_sat` is 0 in BOTH arms, so the miss is a
#                   POINTING miss and NOT the arc's seventh `a_max_aero` ceiling miss. ⚠ The FLAG is
#                   asserted, never a hand-rolled `demand > ceiling` compare: `aero_sat` keys off the
#                   ⟂-v PROJECTION while `a_demand` is full-magnitude, so the sets NEST (slice 19).
#   • SIGMA_LIVE  — the NOT-A-DEAD-KNOB tripwire (the slice-19 discipline): set_param sigma_seek to the
#                   bottom of its declared domain and assert it MOVES the trajectory while the hit and
#                   the isolation SURVIVE. σ is the REALISM lever, not the lesson lever — the button is.
#
# FRAME SAMPLING IS LOAD-BEARING ([[ewsim-missile-verifier-sampling]]). State frames every emit_every
# (16) ticks. The MISS side samples FAITHFULLY (2000.071 frame vs 2000.044 per-tick); the HIT side
# samples COARSELY (9.555 frame vs 0.008 per-tick). ⚠ ALL bounds are pinned against the FRAME-SAMPLED
# wire and the RATIO quoted is the FRAME one (209×) — the 258131× per-tick ratio is a lucky near-zero
# CPA on this seed and must never be pinned. CPA on the FIRST DESCENDING BAND.
#
# Run (server must be listening on slice25_seeker_3d.yaml first):
#   godot --headless --path clients/godot --script res://net/slice25_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 300.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 11520              # 11.52 s — the static 6-km cross-range target's CPA is ≈ 8.7 s

# Bounds — ALL pinned against the FRAME-SAMPLED live wire (temp/slice25_gate0/wire.jl):
const BLIND_MISS_MIN := 1500.0    # pitch_plane frame CPA (measured 2000.071) — ≈ the cross-range offset
const BLIND_MISS_MAX := 2500.0
const HIT_MAX := 30.0             # az_el frame CPA (measured 9.555; the true 0.008 is unreachable on frames)
const TURN_MIN := 1000.0          # az_el max|y| (measured 2839) — it really did fly out of plane
const RATIO_MIN := 30.0           # blind/az_el FRAME ratio (measured 209× — a ~7× margin)
const SIGMA_MIN := 5.0e-5         # the bottom of the declared sigma_seek domain

enum P { HANDSHAKE, PITCH_PLANE, REPLAY, AZ_EL, SIGMA_LIVE }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _max_y := 0.0
var _max_oop := -1.0
var _n_sat := 0
var _n_appr := 0
var _pos_trace: Array = []
var _blind_pos: Array = []
var _blind_miss := 0.0
var _azel_pos: Array = []
var _azel_miss := 0.0

func _initialize() -> void:
	print("S25V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.PITCH_PLANE)

		# --- :pitch_plane — slice 11's scalar tracker on a 6-DOF plant: never COMMANDED sideways ------
		P.PITCH_PLANE:
			if not _drain_scan():
				return false
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_blind_pos = _pos_trace.duplicate(true)
			_blind_miss = _min_los
			print("S25V_PITCH_PLANE miss(frame)=%.3f  max|y|=%.6f  max_omega_oop=%.9f  aero_sat=%d/%d" % [_min_los, _max_y, _max_oop, _n_sat, _n_appr])
			if not (_min_los > BLIND_MISS_MIN and _min_los < BLIND_MISS_MAX):
				return _fail(":pitch_plane must MISS by ≈ the cross-range offset (frame CPA in (%.0f, %.0f) m), got %.2f" % [BLIND_MISS_MIN, BLIND_MISS_MAX, _min_los])
			# THE STRUCTURAL TELL, pinned EXACTLY: the missile never leaves the x–z plane, because the
			# seeker's ω has no out-of-plane component to command one. Not "small" — ZERO.
			if not (_max_y == 0.0):
				return _fail(":pitch_plane must never leave the x–z plane (max|y| == 0.0 EXACTLY — the command is never FORMED), got %.9f" % _max_y)
			if not (_max_oop == 0.0):
				return _fail("the in-plane seeker's reported out-of-plane ω must be EXACTLY 0.0 on every frame (ω ∥ ±ŷ by construction), got %.9f" % _max_oop)
			# THE ISOLATION — this is a POINTING miss, not the arc's 7th ceiling miss (advisor).
			if not (_n_sat == 0):
				return _fail("the :pitch_plane miss must be a POINTING miss, not a ceiling miss: aero_sat must NEVER fire over the approach, got %d/%d frames" % [_n_sat, _n_appr])
			if not (_n_appr > 100):
				return _fail("the approach window must actually contain frames to check (got %d) — the isolation assert would be vacuous" % _n_appr)
			_reset_then_scan([], STEPS, P.REPLAY)

		P.REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_blind_pos, _pos_trace)
			print("S25V_REPLAY posdiff_vs_pitch_plane=%s m  miss=%.3f (must be 0.0 — SEEDED determinism, class 4a)" % [rdiff, _min_los])
			# ⚠ NOT the slice-14..24 "RNG-free" claim: the seeker draws 2 randn/tick, so this is the
			# SEEDED replay contract (same seed ⇒ same draws ⇒ same trace) — the seed is load-bearing
			# again for the first time since slice 13.
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — same seed ⇒ same 2 draws/tick ⇒ same trace (class 4a)" % rdiff)
			if not (_min_los == _blind_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _blind_miss])
			_reset_then_scan([_set_fidelity_cmd("seeker_axes", "az_el")], STEPS, P.AZ_EL)

		# --- :az_el — an az/el PAIR → the LOS-rate VECTOR → the SAME airframe intercepts --------------
		P.AZ_EL:
			if not _drain_scan():
				return false
			_azel_pos = _pos_trace.duplicate(true)
			_azel_miss = _min_los
			var ratio := _blind_miss / maxf(_min_los, 1.0e-9)
			print("S25V_AZ_EL miss(frame)=%.3f  max|y|=%.2f  max_omega_oop=%.6f  aero_sat=%d/%d  ratio=%.1fx" % [_min_los, _max_y, _max_oop, _n_sat, _n_appr, ratio])
			if not (_min_los < HIT_MAX):
				return _fail(":az_el must INTERCEPT (frame CPA < %.0f m — sub-metre UNREACHABLE on frames), got %.2f" % [HIT_MAX, _min_los])
			if not (_max_y > TURN_MIN):
				return _fail(":az_el must actually fly OUT of the plane (max|y| > %.0f m), got %.2f" % [TURN_MIN, _max_y])
			if not (_max_oop > 0.0):
				return _fail("the az/el seeker must report a NONZERO out-of-plane ω (the component the foil cannot have), got %.9f" % _max_oop)
			if not (ratio > RATIO_MIN):
				return _fail("the :seeker_axes toggle must be NON-DEAD: blind/az_el FRAME ratio > %.0fx, got %.1fx" % [RATIO_MIN, ratio])
			# THE ISOLATION, the other half: the arm that HITS is not saturated either, so the whole
			# A/B lives below the aero ceiling and the difference is attributable to the SENSOR alone.
			if not (_n_sat == 0):
				return _fail("the :az_el arm must also be UNSATURATED (aero_sat 0 over the approach) — else the A/B is confounded by the ceiling, got %d/%d" % [_n_sat, _n_appr])
			_reset_then_scan([_set_fidelity_cmd("seeker_axes", "az_el"),
							  _set_param_cmd("m1", "sigma_seek", SIGMA_MIN)], STEPS, P.SIGMA_LIVE)

		# --- the σ_seek slider — NOT a dead knob, and NOT the lesson lever ---------------------------
		P.SIGMA_LIVE:
			if not _drain_scan():
				return false
			var sdiff := _pos_max_diff(_azel_pos, _pos_trace)
			# ⚠ `%g` is NOT a GDScript specifier — an unknown one makes the WHOLE `%` fail and the line
			# prints as its own format string ON A GREEN RUN (the slice-21 gate-3 finding; this file
			# reproduced it). Use %.6f. A number that does not print is not a proof.
			print("S25V_SIGMA_LIVE σ=%.6f  miss(frame)=%.3f  posdiff_vs_default_σ=%.3f m  aero_sat=%d/%d" % [SIGMA_MIN, _min_los, sdiff, _n_sat, _n_appr])
			# The slice-19 NOT-A-DEAD-KNOB tripwire: assert the slider MOVES the physics, never merely
			# that nothing threw. (comp[:sigma_seek] is read EVERY tick by observe!, so it is live —
			# unlike comp[:speed], which is consumed ONCE at load.)
			if not (sdiff > 0.0):
				return _fail("sigma_seek must be a LIVE knob — dropping it to %g must MOVE the trajectory (posdiff > 0), got %.9f" % [SIGMA_MIN, sdiff])
			# …and at the bottom of its DECLARED domain the hit and the isolation both survive: the
			# domain is bounded by where the POINTING-MISS isolation holds, not by the physics.
			if not (_min_los < HIT_MAX):
				return _fail("at σ = %g (the bottom of the declared domain) :az_el must still intercept (< %.0f m), got %.2f" % [SIGMA_MIN, HIT_MAX, _min_los])
			if not (_n_sat == 0):
				return _fail("the declared σ domain must keep the isolation (aero_sat 0), got %d/%d" % [_n_sat, _n_appr])
			return _pass()
	return false

# --- stepping / scanning (the slice-24 contract, verbatim + the aero_sat / omega_oop accumulators) --

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
	_t_target = n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_max_y = 0.0
	_max_oop = -1.0
	_n_sat = 0
	_n_appr = 0
	_pos_trace = []

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		var mpos := _missile_pos(f)
		if not mpos.is_empty():
			_pos_trace.append(mpos)
			_max_y = maxf(_max_y, absf(mpos[1]))
		var tel: Dictionary = f.get("telemetry", {})
		if _mid != "" and tel.has(_mid + ".omega_oop"):
			_max_oop = maxf(_max_oop, float(tel[_mid + ".omega_oop"]))
		if _mid != "" and tel.has(_mid + ".los_range"):
			var r := float(tel[_mid + ".los_range"])
			if r > _prev_los:
				_closing = false
			if _closing:
				_min_los = minf(_min_los, r)
				# The APPROACH window for the isolation check: closing and outside the r→0 endgame
				# (the LOS gate — [[ewsim-missile-verifier-sampling]]). aero_sat is read as the CORE's
				# FLAG, never recomputed from a_demand vs a_max_aero (the sets nest — slice 19).
				if r > 1000.0:
					_n_appr += 1
					if float(tel.get(_mid + ".aero_sat", 0.0)) > 0.5:
						_n_sat += 1
			_prev_los = r
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

func _missile_pos(f: Dictionary) -> Array:
	for e in f.get("entities", []):
		if str(e.get("id", "")) == _mid:
			var p: Array = e.get("pos", [])
			if p.size() >= 3:
				return [float(p[0]), float(p[1]), float(p[2])]
	return []

func _pos_max_diff(a: Array, b: Array) -> float:
	var n := mini(a.size(), b.size())
	if n == 0:
		return 1.0e30
	var m := 0.0
	for i in n:
		for k in 3:
			m = maxf(m, absf(a[i][k] - b[i][k]))
	return m

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
	# Slice 25 REUSES slice-23/24's airframe_view + airframe_6dof discriminators (the 3-D view). The
	# NEW thing: the fidelity carries `seeker_axes`, so the shared button is the SEEKER-AXES cycler —
	# checked BEFORE `steering`/`airframe` in the client (the "check the NEW key first" rule).
	if not bool(f.get("airframe_view", false)):
		return "a slice-25 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-25 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator — a missile carrying :af_cy_beta)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "pitch_plane":
		return "a slice-25 scenario must default :seeker_axes to pitch_plane (the showcase opens on the BLIND miss), got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-25 scenario must HOLD :airframe at six_dof (the plant that CAN fly the command — which is what makes the foil's miss the SENSOR's fault), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-25 scenario must AUTHOR the autopilot at :alpha (the inner α/β/g loop), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-25 scenario must hold :guidance at :pn (convention 9 — ONE toggled fidelity), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-25 scenario must HOLD :seeker at :filtered (a 3-D :raw arm is slice 11's lesson in a new letter — convention 9), got %s" % str(fid.get("seeker", "<absent>"))
	# THE PLANT IS HELD AT SKID-TO-TURN by OMISSION (advisor): bank_to_turn binds aero_sat 93.2% of its
	# approach, which would make the isolation above impossible. An authored `steering` key would also
	# claim the shared button (the client checks seeker_axes first, but convention 9 wants ONE key).
	if fid.has("steering"):
		return "a slice-25 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire is saturated 93%% of its approach and cannot isolate the sensor)"
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-25 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-25 scenario must NOT ship terrain_grid (that flips the client to the slice-18 terrain 3-D view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("sigma_seek"):
		return "slice-25 handshake must expose the 'sigma_seek' slider (the realism lever the SIGMA_LIVE phase drives)"
	# The DISQUALIFICATIONS live IN the gate, not only in the plan: `rho`'s isolated domain is only
	# [1.0, 1.5] and it moves the one thing this slice must hold (the ceiling); `speed` is consumed
	# ONCE at load (the slice-19 DEAD-knob finding); `beta` breaks the isolation at ≥ 0.15 (P8b).
	if keys.has("rho"):
		return "slice-25 must NOT expose a 'rho' knob — its ISOLATED domain is only [1.0, 1.5] (a 1.5× span) and it moves the aero ceiling this slice must hold fixed"
	if keys.has("speed"):
		return "slice-25 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
	if keys.has("beta"):
		return "slice-25 must NOT expose the α-β 'beta' gain as a knob — β ≥ 0.15 breaks the pointing-miss isolation (gate-0 P8b, the slice-11 U-shape)"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	# ⚠ EVERY NUMBER HERE IS INTERPOLATED FROM WHAT THIS RUN MEASURED — never a hard-coded figure
	# copied from a probe. The slice-21 gate-3 bug #2 was pass text quoting per-tick truth while the
	# file measured FRAMES; and this file's own frame grid does NOT match the Julia probe's (the
	# server's emit phase differs), so the HIT arm's sampled CPA moves between runs while the
	# one-sided bounds hold. Quote what was measured, or do not quote.
	print(("S25V OK: slice 23 gave the missile an airframe that can turn OUT of the x–z plane, but a seeker " +
		"that measures only ONE in-plane bearing reconstructs an LOS rate with NO out-of-plane component " +
		"(reported omega_oop == 0.0 EXACTLY on every frame), so the 6-DOF missile is never TOLD to turn: it " +
		"stays dead in the plane (max|y| == 0.0 EXACTLY) and misses by %.2f m — the same signature as slice " +
		"23's discard from a WHOLLY different cause. Measure an az/el PAIR instead (ω = û × û̇) and the SAME " +
		"airframe, SAME PN law, SAME target INTERCEPTS: %.3f m frame-sampled (%.0f×). ⚠ The true CPA is " +
		"sub-metre and frames CANNOT resolve it — a miss samples faithfully, a hit samples coarsely, so the " +
		"asserts are ONE-SIDED bounds, never the ratio. ⚠ A POINTING miss, NOT the arc's seventh ceiling " +
		"miss: aero_sat NEVER fires in EITHER arm. Draw-invariant (2 randn/tick both rungs — the foil " +
		"DISCARDS the azimuth sample) yet trajectory-changing, live-settable, SEEDED-deterministic (class 4a).")
		% [_blind_miss, _azel_miss, _blind_miss / maxf(_azel_miss, 1.0e-9)])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S25V FAIL: " + msg)
	print("S25V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
