extends SceneTree
# Headless slice-26 gate-3 verifier (the slice25_verify analog). Drives the REAL Julia server through
# SimClient.gd and asserts slice-26's "radome / body-rate parasitic loop" done-criteria as machine checks.
#
# THE LESSON: the seeker does not look at the target directly — it looks through a RADOME, which
# refracts by ε ≈ R·(look angle off the body centerline). The bend therefore depends on the missile's
# OWN ATTITUDE, so a body rate MOVES THE LINE OF SIGHT THE SEEKER REPORTS with the target perfectly
# still. That closes a feedback path — q → look → ε → apparent λ̇ → PN → a_cmd → α → q — and past a
# critical loop gain N·|R| the loop is UNSTABLE: the missile shakes itself into a sustained limit cycle.
#
# ⚠ A NEW KIND OF GATE-3 PROOF FOR THE SUITE: THE METRIC IS AN OSCILLATION, NOT A MISS. Slice 20's
# plan sketched this shape for a limit cycle it never got to ship (its actuator-path cycle died at
# gate 0 — δ_max shadows δ̇_max, FINDING 7); the sensor path produces one. So this file asserts an
# rms BODY RATE, and it deliberately asserts that the ringing arm STILL HITS — chasing a miss here
# would be a false claim (and the miss is not monotone in R anyway).
#
# ⚠ AND UNLIKE EVERY MISS IN THIS ARC THE METRIC IS FRAME-ROBUST. A ~2 Hz ring sampled at 62.5 Hz
# (emit_every 16) reproduces the per-tick rms to 3 digits — the REVERSE of the usual sampling caveat
# ([[ewsim-missile-verifier-sampling]]), and exactly why the oscillation is the better headline.
# ⚠ BUT THE WINDOW STILL MATTERS: this file's rms is over FRAMES that are CLOSING and outside the
# r→0 endgame (r > 1000 m). The plan/scenario also quote a MIDDLE-HALF-OF-TICKS rms, and the two
# windows give DIFFERENT ratios (23× here vs 71× there) because this window includes the early
# transient. Both are honest; each must be quoted with its window. The pass text below INTERPOLATES
# what THIS run measured (the slice-25 gate-3 bug #2 — pass text quoting a probe the file cannot
# reproduce — fixed structurally rather than by care).
#
# FIVE phases:
#   • RINGING   — the shipped default R = −0.10, one step past the measured onset: rms q over the
#                 approach ≫ baseline, ε nonzero, AND THE MISSILE STILL HITS.
#   • REPLAY    — reset + replay the SAME config → the 3-D pos trace is BIT-IDENTICAL. ⚠ SEEDED
#                 determinism, not "RNG-free": the seeker draws 2 randn/tick (class 4a, as slice 25).
#   • QUIET     — set_param radome_slope → −0.09 (ONE step back across the threshold): the ring
#                 COLLAPSES. This is the whole lesson in one slider move.
#   • MIRROR    — set_param radome_slope → +0.06 (the top of the declared domain): the SAME |R| class
#                 of perturbation with the OPPOSITE SIGN does not ring at all. Only NEGATIVE slopes
#                 close the loop; positive ones de-tune (the #1 sign trap's 8th occurrence).
#   • DOMAIN_MIN — set_param radome_slope → −0.12, the BOTTOM of the declared knob domain: a state a
#                 student can drag to, where `aero_sat` runs ~95%. **The endpoints of a declared
#                 domain must be MEASURED, not inferred from the interior** — so the isolation is
#                 re-asserted there, and the metric is shown to PLATEAU rather than grow (which is
#                 why the domain stops where it does).
#   • ISOLATION — asserted INSIDE every flight phase: `defl_sat` never fires (cap #3) and the aero
#                 ceiling stays ≪ a_max (cap #1), so neither is what is binding. ⚠ THE OTHER HALF OF
#                 THE ISOLATION — that raising α_max 3× leaves the ONSET exactly where it is, so the
#                 ceiling BOUNDS the cycle rather than CAUSING it — lives in `test_missile.jl`,
#                 because α_max is DELIBERATELY not a knob (it sets the cycle's amplitude, the one
#                 thing the isolation must hold fixed). ⚠ Do NOT copy slice 25's `aero_sat == 0`: it
#                 is IMPOSSIBLE here (an oscillation drives demand, demand hits the ceiling) and
#                 asserting it would fail on a correct build.
#
# Run (server must be listening on slice26_radome.yaml first):
#   godot --headless --path clients/godot --script res://net/slice26_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 300.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 11520              # 11.52 s — CPA on this geometry is ≈ 9.4 s

# Bounds — ALL pinned against the live wire measured with THIS FILE'S window rule (closing frames
# with r > 1000 m; temp/slice26_gate0/window.jl), with margin:
const RING_RMS_MIN  := 0.40       # R = −0.10 rms q  (measured 0.804 — a 2× margin)
const QUIET_RMS_MAX := 0.10       # R = −0.09 rms q  (measured 0.0349) and +0.06 (0.0136)
const RATIO_MIN     := 8.0        # ring/quiet       (measured 23.0× across the threshold)
const MIRROR_MIN    := 8.0        # ring/mirror      (measured 59.3× for the opposite sign)
const HIT_MAX       := 50.0       # the ringing arm STILL HITS (measured 2.18 m frame CPA)
const CEIL_MAX      := 1000.0     # a_max_aero (measured 329.84) ≪ a_max 3000 ⇒ cap #1 out of reach
const QUIET_SLOPE   := -0.09      # one step back across the measured onset (−0.09 / −0.095)
const MIRROR_SLOPE  := 0.06       # the TOP of the declared knob domain — an in-domain mirror
const DOMAIN_MIN    := -0.12      # the BOTTOM of the declared domain (see the DOMAIN_MIN phase)

enum P { HANDSHAKE, RINGING, REPLAY, QUIET, MIRROR, DOMAIN_MIN_P }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# per-scan accumulators
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _max_y := 0.0
var _q_sum := 0.0                 # Σ q² over the approach window (the rms metric)
var _n_appr := 0
var _max_eps := 0.0
var _max_look := 0.0
var _n_defl := 0
var _n_aero := 0
var _max_ceil := 0.0
var _pos_trace: Array = []

# carried across phases
var _ring_pos: Array = []
var _ring_rms := 0.0
var _ring_miss := 0.0
var _ring_eps := 0.0
var _ring_aero := 0
var _ring_appr := 0
var _quiet_rms := 0.0
var _mirror_rms := 0.0

func _initialize() -> void:
	print("S26V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.RINGING)

		# --- the shipped default R = −0.10 — ONE STEP PAST THE ONSET, and the body shakes ----------
		P.RINGING:
			if not _drain_scan():
				return false
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			var rms := _rms_q()
			_ring_pos = _pos_trace.duplicate(true)
			_ring_rms = rms
			_ring_miss = _min_los
			_ring_eps = _max_eps
			_ring_aero = _n_aero
			_ring_appr = _n_appr      # the RINGING phase's own window — the pass text must not
			                          # quote it against a LATER phase's frame count
			print("S26V_RINGING rms_q=%.5f  max|eps|=%.5f rad  miss(frame)=%.3f  max|y|=%.1f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [rms, _max_eps, _min_los, _max_y, _n_aero, _n_appr, _n_defl, _max_ceil])
			if not (_n_appr > 100):
				return _fail("the approach window must contain frames to measure (got %d) — every assert below would be vacuous" % _n_appr)
			if not (rms > RING_RMS_MIN):
				return _fail("the shipped R = −0.10 must RING: rms body rate over the approach > %.2f rad/s, got %.5f" % [RING_RMS_MIN, rms])
			# THE MECHANISM: a nonzero boresight error. Without ε there is no feedback path at all.
			if not (_max_eps > 1.0e-3):
				return _fail("the radome must actually perturb the measurement (max|radome_eps| > 1e-3 rad), got %.6f" % _max_eps)
			# ⚠ THE MISS IS *NOT* THE METRIC — the ringing arm still HITS, and pinning that here stops
			# a later slice from "fixing" this scenario by chasing a miss that was never the claim.
			if not (_min_los < HIT_MAX):
				return _fail("the ringing arm must STILL HIT (< %.0f m — the metric is the OSCILLATION, not the miss), got %.2f" % [HIT_MAX, _min_los])
			if not (_max_y > 1000.0):
				return _fail("the missile must still fly the cross-range engagement (max|y| > 1000 m), got %.1f" % _max_y)
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([], STEPS, P.REPLAY)

		P.REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_ring_pos, _pos_trace)
			print("S26V_REPLAY posdiff_vs_ringing=%s m  rms_q=%.5f (must be 0.0 — SEEDED determinism, class 4a)" % [rdiff, _rms_q()])
			# ⚠ NOT a "RNG-free" claim (slices 14–24): the seeker draws 2 randn/tick radome or not, so
			# this is the SEEDED replay contract — same seed ⇒ same draws ⇒ same trace. A limit cycle
			# replaying bit-for-bit is a stronger statement than a smooth trajectory doing so.
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — a limit cycle is deterministic, not chaotic-looking noise" % rdiff)
			if not (_min_los == _ring_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _ring_miss])
			_reset_then_scan([_set_param_cmd("m1", "radome_slope", QUIET_SLOPE)], STEPS, P.QUIET)

		# --- ONE STEP BACK ACROSS THE THRESHOLD — the whole lesson in a single slider move ---------
		P.QUIET:
			if not _drain_scan():
				return false
			_quiet_rms = _rms_q()
			var ratio := _ring_rms / maxf(_quiet_rms, 1.0e-12)
			print("S26V_QUIET slope=%.3f  rms_q=%.5f  ring/quiet=%.1fx  miss(frame)=%.3f  max|eps|=%.5f  aero_sat=%d/%d" % [QUIET_SLOPE, _quiet_rms, ratio, _min_los, _max_eps, _n_aero, _n_appr])
			if not (_quiet_rms < QUIET_RMS_MAX):
				return _fail("at R = %.2f (one step back across the onset) the body must be QUIET: rms < %.2f rad/s, got %.5f" % [QUIET_SLOPE, QUIET_RMS_MAX, _quiet_rms])
			if not (ratio > RATIO_MIN):
				return _fail("the threshold must be DECISIVE: ring/quiet rms ratio > %.0fx across ONE 0.01 step in R, got %.1fx" % [RATIO_MIN, ratio])
			# …and the knob is LIVE (the slice-19 NOT-A-DEAD-KNOB tripwire): it moved the physics, it
			# did not merely fail to throw. `comp[:radome_slope]` is read EVERY tick by observe!.
			if not (_pos_max_diff(_ring_pos, _pos_trace) > 0.0):
				return _fail("radome_slope must be a LIVE knob — changing it must MOVE the trajectory")
			# THE QUIET ARM STILL REFRACTS. This is what makes the threshold a THRESHOLD and not an
			# on/off switch: the perturbation is present on both sides, only the LOOP is not.
			if not (_max_eps > 1.0e-4):
				return _fail("the quiet arm must still be REFRACTING (the loop is what changed, not the glass): max|eps| > 1e-4, got %.6f" % _max_eps)
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_slope", MIRROR_SLOPE)], STEPS, P.MIRROR)

		# --- THE SIGN — the opposite slope does not ring (the #1 sign trap's 8th occurrence) -------
		P.MIRROR:
			if not _drain_scan():
				return false
			_mirror_rms = _rms_q()
			var mratio := _ring_rms / maxf(_mirror_rms, 1.0e-12)
			print("S26V_MIRROR slope=%.3f  rms_q=%.5f  ring/mirror=%.1fx  miss(frame)=%.3f  max|eps|=%.5f" % [MIRROR_SLOPE, _mirror_rms, mratio, _min_los, _max_eps])
			if not (_mirror_rms < QUIET_RMS_MAX):
				return _fail("a POSITIVE slope must NOT ring (only negative ones close the loop): rms < %.2f, got %.5f" % [QUIET_RMS_MAX, _mirror_rms])
			if not (mratio > MIRROR_MIN):
				return _fail("the sign asymmetry must be decisive: ring/mirror rms ratio > %.0fx, got %.1fx" % [MIRROR_MIN, mratio])
			if not (_max_eps > 1.0e-4):
				return _fail("the positive-slope arm must perturb the measurement just as hard (max|eps| > 1e-4), got %.6f" % _max_eps)
			if not (_min_los < HIT_MAX):
				return _fail("the positive-slope arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			_reset_then_scan([_set_param_cmd("m1", "radome_slope", DOMAIN_MIN)], STEPS, P.DOMAIN_MIN_P)

		# --- THE DECLARED DOMAIN'S BOTTOM END — a state a student can drag to (advisor) -------------
		P.DOMAIN_MIN_P:
			if not _drain_scan():
				return false
			var dmin_rms := _rms_q()
			print("S26V_DOMAIN_MIN slope=%.3f  rms_q=%.5f  miss(frame)=%.3f  defl_sat=%d/%d  aero_sat=%d/%d  ceil_max=%.2f  max|eps|=%.5f" % [DOMAIN_MIN, dmin_rms, _min_los, _n_defl, _n_appr, _n_aero, _n_appr, _max_ceil, _max_eps])
			# ⚠ THE ENDPOINTS OF A DECLARED DOMAIN MUST BE MEASURED, NOT INFERRED FROM THE INTERIOR
			# (the [[ewsim-missile-verifier-sampling]] "the range gate can dictate which arms you may
			# ship" discipline, applied to a KNOB domain). The phases above cover −0.10 / −0.09 /
			# +0.06; a student dragging the slider to its MINIMUM lands here, where `aero_sat` runs
			# ~95% — so the isolation has to be shown to survive at the end, not assumed to.
			if not _isolation_ok():
				return _fail("the ISOLATION must survive at the DOMAIN MINIMUM: " + _isolation_msg())
			if not (dmin_rms > RING_RMS_MIN):
				return _fail("the domain minimum must still be past the onset (rms > %.2f), got %.5f" % [RING_RMS_MIN, dmin_rms])
			# …and the metric PLATEAUS past onset rather than growing (the α_max clamp bounds the
			# cycle) — which is precisely why the domain stops here instead of running further.
			if not (dmin_rms < 2.0 * _ring_rms):
				return _fail("past the onset the metric must PLATEAU, not grow (domain-min rms %.5f vs shipped %.5f)" % [dmin_rms, _ring_rms])
			if not (_min_los < HIT_MAX):
				return _fail("even at the domain minimum the missile must still close (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			return _pass()
	return false

# --- the metric + the isolation ------------------------------------------------------------

func _rms_q() -> float:
	return sqrt(_q_sum / maxf(float(_n_appr), 1.0)) if _n_appr > 0 else 0.0

func _isolation_ok() -> bool:
	# cap #3 (the fin DEFLECTION limit) and cap #1 (the authored `a_max` MAGNITUDE clamp) must both be
	# out of the picture, so the only cap in play is the flight-condition ceiling — which the α_max
	# test in `test_missile.jl` shows BOUNDS the cycle rather than causing it.
	return _n_defl == 0 and _max_ceil < CEIL_MAX

func _isolation_msg() -> String:
	return ("the ISOLATION must hold: defl_sat must NEVER fire over the approach (cap #3, got %d/%d) " +
		"and the aero ceiling must stay ≪ a_max = 3000 (cap #1, got %.2f ≥ %.0f). " +
		"⚠ `aero_sat` is EXPECTED to fire here and is NOT asserted — an oscillation drives demand, " +
		"and demand hits the ceiling; the ceiling BOUNDS the limit cycle (α_max invariance, " +
		"test_missile.jl) rather than causing it. Do not copy slice 25's aero_sat == 0.") % [_n_defl, _n_appr, _max_ceil, CEIL_MAX]

# --- stepping / scanning (the slice-25 contract + the rms/eps/cap accumulators) --------------

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
	_q_sum = 0.0
	_n_appr = 0
	_max_eps = 0.0
	_max_look = 0.0
	_n_defl = 0
	_n_aero = 0
	_max_ceil = 0.0
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
				# THE APPROACH WINDOW: closing and outside the r→0 endgame. The endgame must be
				# excluded from BOTH the rms and the cap counts — the LOS sweeps past the nose in
				# the last few metres, spiking the look angle to ~104° and `a_demand` with it
				# ([[ewsim-missile-verifier-sampling]]).
				if r > 1000.0:
					_n_appr += 1
					var q := float(tel.get(_mid + ".omega_q", 0.0))
					_q_sum += q * q
					_max_eps = maxf(_max_eps, absf(float(tel.get(_mid + ".radome_eps", 0.0))))
					_max_look = maxf(_max_look, float(tel.get(_mid + ".look_angle", 0.0)))
					_max_ceil = maxf(_max_ceil, float(tel.get(_mid + ".a_max_aero", 0.0)))
					if float(tel.get(_mid + ".defl_sat", 0.0)) > 0.5:
						_n_defl += 1
					if float(tel.get(_mid + ".aero_sat", 0.0)) > 0.5:
						_n_aero += 1
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
	# Slice 26 REUSES slices 23/24/25's 3-D airframe view, and adds ONE marker whose only job is to
	# make the client DROP the shared fidelity button (the slice-16 Option-P′ resolution).
	if not bool(f.get("airframe_view", false)):
		return "a slice-26 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-26 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-26 handshake must ship radome_view=true — the marker that DROPS the shared button. ⚠ The slice-20 'keep the inherited cycler' precedent does NOT transfer: the inherited cycler here is slice 25's seeker_axes, and its other position (:pitch_plane) would leave the radome LIVE AND REFRACTING beside slice 25's unrelated 2000 m blind miss — two mechanisms in one view, which is what convention 9 exists to prevent"
	var fid: Dictionary = f.get("fidelity", {})
	# EVERY fidelity is HELD — this is a SLIDER lesson with no toggled rung at all (the slice-16/20
	# shape). `R = 0` is an in-domain slider value AND bit-identical to the radome not existing
	# (test_missile.jl), so the knob-vs-rung discriminator returns KNOB.
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-26 scenario must HOLD :seeker_axes at az_el (the arm that HITS, so the RING is the only thing degrading it), got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-26 scenario must HOLD :airframe at six_dof — the radome is INERT without it (there is no attitude to look through), and the gate is on the LIVE rung, not on :att_q which is never deleted, got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-26 scenario must AUTHOR the autopilot at :alpha (the inner α/β/g loop the parasitic path closes through), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-26 scenario must hold :guidance at :pn (the N in the N·|R| loop gain), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-26 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-26 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the ceiling 93%% of its approach and cannot isolate anything)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-26 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("radome_slope"):
		return "slice-26 handshake must expose the 'radome_slope' slider — the lesson IS the slider (there is no button)"
	if keys.size() != 1:
		return "slice-26 must expose EXACTLY ONE knob (got %d) — convention 9, and every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate"). Each of these MOVES the lesson and would let a student cross the threshold
	# without touching the radome at all — the confounded-lever rule.
	if keys.has("n_pn"):
		return "slice-26 must NOT expose an 'n_pn' knob — it is live-read every tick and moves the LOOP GAIN the lesson is ABOUT (N·|R|), so a student could cross the threshold with the radome untouched and conclude the slope did it"
	if keys.has("rho"):
		return "slice-26 must NOT expose a 'rho' knob — |R_crit| ∝ ρ, so it too moves the loop gain, and slice 25 measured its isolated domain at only [1.0, 1.5]"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-26 must NOT expose an 'alpha_max' knob — it sets the limit cycle's AMPLITUDE, i.e. the one thing the isolation must hold fixed"
	if keys.has("sigma_seek"):
		return "slice-26 must NOT expose 'sigma_seek' (slice 25's own knob) — on THIS wire its top compresses the ring's signature from 106× to 14×, i.e. a knob that DEGRADES the lesson beside it"
	if keys.has("speed"):
		return "slice-26 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	# ⚠ EVERY NUMBER HERE IS INTERPOLATED FROM WHAT THIS RUN MEASURED (the slice-21/25 gate-3 bug,
	# fixed structurally). ⚠ And `%g` is NOT a GDScript specifier — an unknown one makes the WHOLE
	# `%` fail and the line prints as its own format string ON A GREEN RUN. Only %.Nf / %d / %s here.
	print(("S26V OK: the seeker looks through a RADOME, which bends the line of sight by an amount that " +
		"depends on WHERE IT IS LOOKING (max|radome_eps| = %.5f rad on the shipped arm) — so the missile's " +
		"OWN body rotation moves the LOS it reports, with the target standing still. That closes a feedback " +
		"path from the airframe back into guidance, and past a critical LOOP GAIN N·|R| it is UNSTABLE: at " +
		"R = -0.10 the body rings at rms %.5f rad/s over the approach, and ONE 0.01 step back to R = %.2f " +
		"collapses it to %.5f (%.1fx) — the glass is still refracting on BOTH sides (the LOOP is what " +
		"changed, not the perturbation). The sign is one-sided: R = +%.2f perturbs just as hard and does not " +
		"ring at all (%.1fx). ⚠ THE METRIC IS THE OSCILLATION, NOT THE MISS — the ringing arm STILL HITS " +
		"(%.2f m) and the miss is not monotone in R. ⚠ The ISOLATION is NOT slice 25's: aero_sat DOES fire " +
		"(%d/%d frames — an oscillation drives demand into the ceiling) and that is a CONSEQUENCE; the " +
		"ceiling BOUNDS the cycle rather than causing it (the alpha_max-invariance half is pinned in " +
		"test_missile.jl), while defl_sat NEVER fires and the ceiling stays far under a_max. This is the " +
		"GUIDANCE LIMIT CYCLE slice 15 named, slice 19 deferred and slice 20 hunted and KILLED on the " +
		"ACTUATOR path — it lives on the SENSOR path. Class 4a: seeded-deterministic, replay bit-identical.")
		% [_ring_eps, _ring_rms, QUIET_SLOPE, _quiet_rms, _ring_rms / maxf(_quiet_rms, 1.0e-12),
		   MIRROR_SLOPE, _ring_rms / maxf(_mirror_rms, 1.0e-12), _ring_miss, _ring_aero, _ring_appr])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S26V FAIL: " + msg)
	print("S26V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
