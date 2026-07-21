extends SceneTree
# Headless slice-24 gate-3 verifier (the slice23_verify analog). Drives the REAL Julia server through
# SimClient.gd and asserts slice-24's BANK-TO-TURN + roll-lag "done" criteria as machine checks. The
# lesson: skid-to-turn points its ⟂-v lift anywhere INSTANTLY (two body planes), so it intercepts the
# out-of-plane target; bank-to-turn makes lift in ONE plane and must ROLL to point it, and with a
# finite roll bandwidth τ_roll the roll LAGS — so against the SAME target it MISSES. FOUR phases:
#   • BANK_TO_TURN  — the default MISSES (frame CPA ≈ 372 m). The missile DOES bank and turn (max|y|
#                     well past 0 — it is NOT the pitch-plane discard), just LATE. The roll lag.
#   • REPLAY        — reset + replay the SAME config → the 3-D pos trace is BIT-IDENTICAL (class-4c
#                     RNG-free determinism — truth-fed PN, no seeker, no w.rng draw).
#   • SKID_TO_TURN  — set_fidelity steering → skid_to_turn (the LIVE toggle, the ONE button): the SAME
#                     PN law, the SAME 6-DOF plant, INTERCEPTS (frame CPA ≈ 5 m). The separation is a
#                     RATIO (the non-dead toggle).
#   • TAU_RECOVER   — reset (bank_to_turn) + set_param af_tau_roll → 0.01 (THE CAUSATION LEVER): with an
#                     ~instant roll the bank no longer lags, so bank-to-turn RECOVERS the STT hit (frame
#                     CPA ≈ 5 m). The miss did not merely correlate with the steering mode — the roll
#                     LAG CAUSED it (remove the lag, remove the miss).
#
# FRAME SAMPLING IS LOAD-BEARING ([[ewsim-missile-verifier-sampling]]). State frames every emit_every
# (16) ticks. The MISS side (bank_to_turn, ≈372) samples FAITHFULLY. The HIT sides (skid_to_turn,
# tau_recover) sample COARSELY — closing ≈ 685 m/s ⇒ frames land ≈ 11 m apart near CPA, so the TRUE
# ≈0.2 m intercept frame-samples to ≈ 5 m. All bounds pinned against the FRAME-SAMPLED live-wire
# numbers (temp/slice24_gate0/framesample.jl), never the true CPA. CPA on the FIRST DESCENDING BAND.
#
# RNG-FREE (truth-fed PN, no seeker) ⇒ "draw-count invariance" is VACUOUS (class 4c).
#
# Run (server must be listening on slice24_bank_to_turn.yaml first):
#   godot --headless --path clients/godot --script res://net/slice24_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 300.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 11520              # 11.52 s — the static 6-km target's CPA is ≈ 8.7 s (band latched before drain ends)

# Bounds — ALL pinned against the FRAME-SAMPLED live wire (temp/slice24_gate0/framesample.jl):
const BANK_MISS_MIN := 300.0      # bank_to_turn frame CPA (measured 371.8) — the roll lag misses
const BANK_MISS_MAX := 600.0      # …but it TURNED (not the ≈2000 discard) — a bounded miss
const HIT_MAX := 25.0             # skid_to_turn / recovered frame CPA (measured 5.01 / 5.33; sub-metre unreachable)
const TURN_MIN := 1000.0          # bank_to_turn max|y| (measured ≈3000) — it banked and turned, LATE
const RATIO_MIN := 15.0           # bank/skid frame ratio (measured 74× — ~5× margin)

enum P { HANDSHAKE, BANK_TO_TURN, REPLAY, SKID_TO_TURN, TAU_RECOVER }

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
var _pos_trace: Array = []
var _bank_pos: Array = []
var _bank_miss := 0.0

func _initialize() -> void:
	print("S24V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.BANK_TO_TURN)

		# --- :bank_to_turn — the single-plane airframe must ROLL to point its lift → the roll lags → MISS
		P.BANK_TO_TURN:
			if not _drain_scan():
				return false
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_bank_pos = _pos_trace.duplicate(true)
			_bank_miss = _min_los
			print("S24V_BANK_TO_TURN miss(frame)=%.3f  max|y|=%.2f  frames=%d" % [_min_los, _max_y, _pos_trace.size()])
			if not (_min_los > BANK_MISS_MIN and _min_los < BANK_MISS_MAX):
				return _fail(":bank_to_turn must MISS by the roll lag (frame CPA in (%.0f, %.0f) m), got %.2f" % [BANK_MISS_MIN, BANK_MISS_MAX, _min_los])
			# It BANKED and TURNED — max|y| well past 0 (NOT the pitch-plane discard, which never leaves
			# x-z). The miss is a TIMING/late-turn miss, not a discard: BTT does reach the cross-range, LATE.
			if not (_max_y > TURN_MIN):
				return _fail(":bank_to_turn must still TURN out of plane (max|y| > %.0f m — a late turn, not the discard), got %.2f" % [TURN_MIN, _max_y])
			_reset_then_scan([], STEPS, P.REPLAY)

		P.REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_bank_pos, _pos_trace)
			print("S24V_REPLAY posdiff_vs_bank=%s m  miss=%.3f (must be 0.0 — class-4c RNG-free)" % [rdiff, _min_los])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c)" % rdiff)
			if not (_min_los == _bank_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _bank_miss])
			_reset_then_scan([_set_fidelity_cmd("steering", "skid_to_turn")], STEPS, P.SKID_TO_TURN)

		# --- :skid_to_turn — lift in two planes at once, no roll → intercept (the slice-23 plant) --------
		P.SKID_TO_TURN:
			if not _drain_scan():
				return false
			var ratio := _bank_miss / maxf(_min_los, 1.0e-9)
			print("S24V_SKID_TO_TURN miss(frame)=%.3f  max|y|=%.2f  ratio=%.1fx (STT hits where BTT missed)" % [_min_los, _max_y, ratio])
			if not (_min_los < HIT_MAX):
				return _fail(":skid_to_turn must INTERCEPT (frame CPA < %.0f m — sub-metre UNREACHABLE on the wire), got %.2f" % [HIT_MAX, _min_los])
			if not (ratio > RATIO_MIN):
				return _fail("the :steering toggle must be NON-DEAD: bank/skid frame ratio > %.0fx, got %.1fx" % [RATIO_MIN, ratio])
			_reset_then_scan([_set_param_cmd("m1", "af_tau_roll", 0.01)], STEPS, P.TAU_RECOVER)

		# --- af_tau_roll → 0 — THE CAUSATION PROOF: an ~instant roll removes the lag → the miss vanishes -
		P.TAU_RECOVER:
			if not _drain_scan():
				return false
			print("S24V_TAU_RECOVER τ_roll=0.01  miss(frame)=%.3f (instant roll ⇒ no lag ⇒ bank_to_turn RECOVERS the hit)" % _min_los)
			# With τ_roll → 0 the bank no longer lags: the single-plane lift points at the target from the
			# start, so bank_to_turn recovers the STT intercept. This is what licenses the causal claim —
			# the roll LAG (not the steering mode per se) CAUSED the miss (remove the lag, remove the miss).
			if not (_min_los < HIT_MAX):
				return _fail("τ_roll → 0 must RECOVER the hit (frame CPA < %.0f m) — the roll LAG caused the miss, got %.2f" % [HIT_MAX, _min_los])
			return _pass()
	return false

# --- stepping / scanning (the slice-23 contract, verbatim) --------------------------------

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
		if _mid != "" and tel.has(_mid + ".los_range"):
			var r := float(tel[_mid + ".los_range"])
			if r > _prev_los:
				_closing = false
			if _closing:
				_min_los = minf(_min_los, r)
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
	# Slice 24 reuses slice-23's airframe_view + airframe_6dof discriminators (a missile carrying
	# :af_cy_beta) — the 3-D view + the shared button. The NEW thing: the fidelity carries `steering`,
	# so the button is the STEERING cycler (skid_to_turn ↔ bank_to_turn) with :airframe HELD :six_dof
	# (convention 9 — ONE toggled fidelity). Default :bank_to_turn (the showcase opens on the MISS).
	if not bool(f.get("airframe_view", false)):
		return "a slice-24 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-24 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator — a missile carrying :af_cy_beta)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("steering", "")) != "bank_to_turn":
		return "a slice-24 scenario must default :steering to bank_to_turn (the showcase opens on the roll-lag MISS), got %s" % str(fid.get("steering", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-24 scenario must HOLD :airframe at six_dof (the plant both steering laws run on), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-24 scenario must AUTHOR the autopilot at :alpha (the inner α/β/g loop), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-24 scenario must hold :guidance at :pn (convention 9 — ONE toggled fidelity), got %s" % str(fid.get("guidance", "<absent>"))
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-24 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-24 scenario must NOT ship terrain_grid (that flips the client to the slice-18 terrain 3-D view)"
	# the roll-lag lever must be exposed (the causation lever the TAU_RECOVER phase drives).
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("af_tau_roll"):
		return "slice-24 handshake must expose the 'af_tau_roll' slider — the roll time constant (the causation lever)"
	if keys.has("speed"):
		return "slice-24 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding); a working one would also lengthen the flight and evaporate the cold-start lesson (plan §5)"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S24V OK: skid-to-turn points its ⟂-v lift anywhere INSTANTLY (two body planes, no roll) and " +
		"intercepts the out-of-plane target (≈5 m frame-sampled); bank-to-turn makes lift in ONE plane and " +
		"must ROLL to point it, and with a τ_roll = 1.0 s roll time constant the roll LAGS — so it banks and " +
		"turns LATE (max|y| → ~3000, NOT the discard) and MISSES by ≈372 m (~74× the STT intercept) on the ONE " +
		"live :steering toggle. Driving τ_roll → 0 removes the lag and bank-to-turn RECOVERS the hit (≈5 m) — so " +
		"the roll LAG, not the steering mode per se, CAUSED the miss. You must bank before you turn. " +
		"Physics-changing, RNG-free, live-settable (class 4c).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S24V FAIL: " + msg)
	print("S24V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
