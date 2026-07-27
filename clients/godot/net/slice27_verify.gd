extends SceneTree
# Headless slice-27 gate-3 verifier (the slice26_verify analog). Drives the REAL Julia server through
# SimClient.gd and asserts slice-27's "radome-slope compensation autopilot" done-criteria as machine
# checks.
#
# THE LESSON: the missile already carries a rate gyro, so subtract the parasitic term back out.
# Slice 26 measured the coupling exactly (ε̇_el = +R·cos(look_az)·ω_y, ε̇_az = −R·ω_z), so feeding it
# forward with the slope the guidance computer BELIEVES it has (R̂) cancels the parasitic path TO THE
# ACCURACY OF THAT BELIEF. What is left driving the loop is the RESIDUAL R − R̂, and slice 26's
# boundary comes back unchanged with the substitution: N·|R − R̂|/ρ ≈ 0.38. ⇒ COMPENSATION BUYS
# MARGIN, NOT IMMUNITY, and the design requirement is not a better radome but a BETTER-KNOWN one.
#
# ⚠ THE SHARPEST RISK IN THE SLICE, AND WHAT THIS FILE IS BUILT TO RULE OUT: that the compensator
# quiets the ring by DE-TUNING rather than by cancelling. Slice 26 measured that `ėl` and `q` are
# COLLINEAR in closed loop (R² = 0.999), so subtracting `R̂·cos·ω_y` from `ėl` is numerically
# near-indistinguishable from SCALING `ėl` DOWN — i.e. from lowering effective N — and a "cure" that
# works that way would quiet the ring just as convincingly. Two discriminators, both asserted here:
#   (a) the boundary moves as an OFFSET, not a gain — the MARGIN and DIAGONAL phases below, and
#   (b) the MISS STAYS AT BASELINE (slice 26 measured de-tuning's signature as the miss OPENING
#       from sluggishness). Ring down AND miss at baseline ⇒ cancellation.
#
# ⚠ THE METRIC IS SLICE 26's, UNCHANGED: an rms BODY RATE, never a miss. And this wire ENFORCES that
# discipline rather than tempting you away from it — THE UNCOMPENSATED ARM STILL HITS (~2.4 m). The
# rms metric is also FRAME-ROBUST (per-tick 0.81712 vs frame-sampled 0.81704), which is exactly why
# the oscillation beats any miss here.
# ⚠ WINDOW: as in slice 26 this file's rms is over FRAMES that are CLOSING and outside the r→0
# endgame (r > 1000 m). The plan and scenario also quote a MIDDLE-HALF-OF-TICKS rms; the two windows
# give DIFFERENT ratios, and each must be quoted with its window. The pass text INTERPOLATES what
# THIS run measured (the slice-21/25 gate-3 bug, fixed structurally rather than by care).
#
# SIX phases:
#   • RINGING  — the shipped default (R = −0.10, R̂ = 0): slice 26's disease at N = 8. The showcase
#                OPENS ON THE DISEASE, so the body is already ringing when a client connects.
#   • REPLAY   — reset + replay the SAME config → the 3-D pos trace is BIT-IDENTICAL. ⚠ SEEDED
#                determinism, not "RNG-free": the seeker draws 2 randn/tick (class 4a), and the
#                COMPENSATOR ADDS NO DRAW.
#   • CURED    — set_param radome_slope_est → −0.10 (matched knowledge): the ring COLLAPSES **and
#                the miss stays at baseline**. That pairing is the de-tune discriminator.
#   • MARGIN   — ⭐ R̂ HELD at −0.10 while the GLASS degrades to R = −0.20 (the R knob's floor): the
#                same compensator that cured the first radome RINGS AGAIN on a worse one. MARGIN,
#                NOT IMMUNITY — and it is the boundary moving as an OFFSET (residual back to −0.10,
#                exactly the ringing residual of phase 1).
#   • DIAGONAL — ⭐⭐ R and R̂ moved TOGETHER to −0.15 (the R̂ knob's floor — so this phase MEASURES a
#                declared domain endpoint, slice 26's post-commit lesson): worse glass than the
#                shipped wire, perfectly known, and it is QUIET. THE MISSILE DOES NOT CARE ABOUT
#                GLASS IT KNOWS ABOUT — which is what makes TWO knobs ONE lesson (convention 9 is
#                satisfied by this measurement, not by counting sliders).
#   • ISOLATION — asserted INSIDE every flight phase: `defl_sat` never fires (cap #3) and the aero
#                ceiling stays ≪ a_max (cap #1). ⚠ Do NOT copy slice 25's `aero_sat == 0`: it is
#                IMPOSSIBLE here (an oscillation drives demand into the ceiling) and asserting it
#                would fail on a correct build. The other half — that raising α_max 3× leaves the
#                CROSSING exactly where it is — lives in `test_missile.jl`, because α_max is
#                DELIBERATELY not a knob (it sets the cycle's amplitude, the one thing the isolation
#                must hold fixed).
#
# ⚠ The WRONG-SIGN tooth (R̂ > 0 compensates the wrong way and is exactly a WORSE radome) is pinned
# in `test_missile.jl`, not here: the R̂ knob's declared domain tops out at 0.0, and a verifier that
# drove a knob outside its own declared domain would be testing a state no student can reach.
#
# Run (server must be listening on slice27_radome_comp.yaml first):
#   godot --headless --path clients/godot --script res://net/slice27_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 300.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 11520              # 11.52 s — CPA on this geometry is ≈ 9.4 s

# Bounds — pinned against the gate-0 measurements with margin. ⚠ Gate 0 measured a MID-HALF-OF-TICKS
# rms (ringing 0.844, cured 0.0135, 62.4×); THIS file's window (closing frames, r > 1000 m) includes
# the early transient and so reports a smaller ratio, exactly as slice 26's did (71× → 23×).
const RING_RMS_MIN  := 0.40       # the uncompensated arm must RING   (gate 0: 0.844 mid-half)
const QUIET_RMS_MAX := 0.10       # a matched estimate must be QUIET  (gate 0: 0.0135 mid-half)
const RATIO_MIN     := 8.0        # ring/cured — decisive, not a nudge
const HIT_MAX       := 50.0       # every arm still intercepts (the metric is the OSCILLATION)
const CEIL_MAX      := 1000.0     # a_max_aero (measured 329.87) ≪ a_max 3000 ⇒ cap #1 out of reach
const CURE_MISS_MAX := 15.0       # ⚠ the DE-TUNE bound, and it is a FRAME-SAMPLING bound: at
                                  # emit_every 16 and ~700 m/s the grid is ~11 m wide, so a perfect
                                  # intercept can report up to ~5.6 m. 15 m is ~1.3 frame steps —
                                  # far under the 18.8 m gate 0 measured for a REAL de-tune (P6C),
                                  # and it is why this check is ONE-SIDED (see the CURED phase).
const CURE_EST      := -0.10      # matched knowledge: R̂ = R
const WORSE_SLOPE   := -0.20      # the R knob's declared FLOOR — a radome it was not designed for
const DIAG_SLOPE    := -0.15      # the R̂ knob's declared FLOOR, moved WITH the glass (the diagonal)

enum P { HANDSHAKE, RINGING, REPLAY, CURED, MARGIN, DIAGONAL }

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
var _n_defl := 0
var _n_aero := 0
var _max_ceil := 0.0
var _resid_min := 1.0e30
var _resid_max := -1.0e30
var _max_ff := 0.0
var _pos_trace: Array = []

# carried across phases
var _ring_pos: Array = []
var _ring_rms := 0.0
var _ring_miss := 0.0
var _ring_eps := 0.0
var _ring_aero := 0
var _ring_appr := 0
var _cure_rms := 0.0
var _cure_miss := 0.0
var _cure_ff := 0.0
var _cure_eps := 0.0
var _margin_rms := 0.0
var _diag_rms := 0.0

func _initialize() -> void:
	print("S27V_INIT godot=", Engine.get_version_info().string)
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

		# --- the shipped default: a compensator that BELIEVES NOTHING (R̂ = 0) ⇒ slice 26's disease --
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
			_ring_appr = _n_appr
			print("S27V_RINGING R_hat=0  rms_q=%.5f  residual=[%.4f,%.4f]  max|eps|=%.5f  miss(frame)=%.3f  max|y|=%.1f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [rms, _resid_min, _resid_max, _max_eps, _min_los, _max_y, _n_aero, _n_appr, _n_defl, _max_ceil])
			if not (_n_appr > 100):
				return _fail("the approach window must contain frames to measure (got %d) — every assert below would be vacuous" % _n_appr)
			if not (rms > RING_RMS_MIN):
				return _fail("the shipped wire (R = −0.10, R̂ = 0) must RING: rms body rate > %.2f rad/s, got %.5f" % [RING_RMS_MIN, rms])
			# ⭐ THE RESIDUAL IS SHIPPED AS A NUMBER (convention 13 — the client never subtracts), and
			# with R̂ = 0 it is the bare slope: the compensator is PRESENT and believing nothing.
			if not (absf(_resid_min + 0.10) < 1.0e-9 and absf(_resid_max + 0.10) < 1.0e-9):
				return _fail("with R̂ = 0 the shipped residual must be exactly the bare slope −0.100 (the compensator is present and believes nothing), got [%.6f, %.6f]" % [_resid_min, _resid_max])
			if not (_max_eps > 1.0e-3):
				return _fail("the radome must actually perturb the measurement (max|radome_eps| > 1e-3 rad), got %.6f" % _max_eps)
			# ⚠ THE MISS IS *NOT* THE METRIC — slice 26's discipline, inherited. Pinning that the
			# ringing arm HITS stops a later slice from "fixing" this scenario by chasing a miss.
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
			print("S27V_REPLAY posdiff_vs_ringing=%s m  rms_q=%.5f (must be 0.0 — SEEDED determinism, class 4a)" % [rdiff, _rms_q()])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — a limit cycle is deterministic, not chaotic-looking noise" % rdiff)
			if not (_min_los == _ring_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _ring_miss])
			_reset_then_scan([_set_param_cmd("m1", "radome_slope_est", CURE_EST)], STEPS, P.CURED)

		# --- MATCHED KNOWLEDGE — the gyro cancels the loop the glass closed ------------------------
		P.CURED:
			if not _drain_scan():
				return false
			_cure_rms = _rms_q()
			_cure_miss = _min_los
			_cure_ff = _max_ff        # ⚠ carried: the accumulators reset every phase, so the pass
			_cure_eps = _max_eps      #   text must quote THIS phase's numbers, not the last one's
			var ratio := _ring_rms / maxf(_cure_rms, 1.0e-12)
			print("S27V_CURED R_hat=%.3f  rms_q=%.5f  ring/cured=%.1fx  residual=[%.4f,%.4f]  miss(frame)=%.3f  max|eps|=%.5f  max|ff|=%.5f  aero_sat=%d/%d" % [CURE_EST, _cure_rms, ratio, _resid_min, _resid_max, _min_los, _max_eps, _max_ff, _n_aero, _n_appr])
			if not (_cure_rms < QUIET_RMS_MAX):
				return _fail("a MATCHED estimate (R̂ = R = %.2f) must quiet the loop: rms < %.2f rad/s, got %.5f" % [CURE_EST, QUIET_RMS_MAX, _cure_rms])
			if not (ratio > RATIO_MIN):
				return _fail("the cure must be DECISIVE: ring/cured rms ratio > %.0fx, got %.1fx" % [RATIO_MIN, ratio])
			# the residual — the quantity that decides — is now ZERO, from the core, as a number
			if not (absf(_resid_min) < 1.0e-9 and absf(_resid_max) < 1.0e-9):
				return _fail("a matched estimate must drive the shipped residual R − R̂ to exactly 0 (it is what closes the loop), got [%.6f, %.6f]" % [_resid_min, _resid_max])
			# …and the knob is LIVE (the slice-19 NOT-A-DEAD-KNOB tripwire): it MOVED the physics.
			if not (_pos_max_diff(_ring_pos, _pos_trace) > 0.0):
				return _fail("radome_slope_est must be a LIVE knob — changing it must MOVE the trajectory")
			# THE FEED-FORWARD IS ACTUALLY DOING SOMETHING — the mechanism, not just the outcome.
			if not (_max_ff > 1.0e-4):
				return _fail("the gyro feed-forward must be nonzero on the cured arm (max|radome_ff_el| > 1e-4 rad/s), got %.6f" % _max_ff)
			# THE GLASS IS STILL REFRACTING. What changed is the LOOP, not the perturbation — the same
			# distinction slice 26's quiet arm makes, one level up.
			if not (_max_eps > 1.0e-4):
				return _fail("the cured arm must still be REFRACTING (the LOOP is what changed, not the glass): max|eps| > 1e-4, got %.6f" % _max_eps)
			# ⭐⭐ THE DE-TUNE DISCRIMINATOR (advisor) — AND IT IS DELIBERATELY ONE-SIDED HERE.
			# A compensator that worked by lowering effective N would quiet the ring AND OPEN the
			# miss from sluggishness (slice 26 measured that signature at 0.23 → 7.66 m; gate-0 P6C
			# measured it on THIS wire at 18.8 m for a residual of +0.4 and 31.4 m at +0.15 on the
			# harder one). So the check is that the miss does not open into de-tune territory.
			# ⚠ IT MUST NOT BE WRITTEN AS `cured_miss <= ringing_miss`, AND THIS FILE FAILED THAT WAY
			# FIRST: both arms HIT, and [[ewsim-missile-verifier-sampling]] says a HIT samples
			# COARSELY. At emit_every = 16 and ~700 m/s the frame grid is ~11 m wide, so a perfect
			# intercept can report any frame CPA up to ~half of that — measured, 3.305 m on the
			# ringing arm against 5.269 on the cured one, with per-tick values of 2.447 and 0.316.
			# Comparing two frame-sampled hits measures the grid, not the physics. The PER-TICK
			# comparison (cure.miss < ring.miss, and within 2× of the no-radome baseline) is pinned
			# in `test_missile.jl`, where per-tick sampling is available.
			if not (_min_los < CURE_MISS_MAX):
				return _fail("the cure must NOT be a DE-TUNE: the frame CPA must stay inside the sampling floor (< %.0f m, ~1.3 frame steps at %.0f m/frame), got %.3f m. A compensator that quiets the loop by lowering effective N opens the miss from sluggishness — gate 0 measured 18.8 m at a residual of +0.4 (P6C)" % [CURE_MISS_MAX, 11.2, _min_los])
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_slope_est", CURE_EST),
							  _set_param_cmd("m1", "radome_slope", WORSE_SLOPE)], STEPS, P.MARGIN)

		# --- ⭐ MARGIN, NOT IMMUNITY — the same compensator on a radome it was not designed for -----
		P.MARGIN:
			if not _drain_scan():
				return false
			_margin_rms = _rms_q()
			print("S27V_MARGIN R=%.3f R_hat=%.3f  rms_q=%.5f  residual=[%.4f,%.4f]  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d" % [WORSE_SLOPE, CURE_EST, _margin_rms, _resid_min, _resid_max, _min_los, _n_aero, _n_appr, _n_defl])
			# The residual is back to −0.10 — EXACTLY the ringing residual of phase 1, reached from a
			# completely different (R, R̂) pair. That is the boundary moving as an OFFSET.
			if not (absf(_resid_min + 0.10) < 1.0e-9 and absf(_resid_max + 0.10) < 1.0e-9):
				return _fail("holding R̂ = %.2f while the glass degrades to %.2f must give a residual of exactly −0.100 — the SAME residual as the uncompensated shipped arm, reached from a different (R, R̂) pair. Got [%.6f, %.6f]" % [CURE_EST, WORSE_SLOPE, _resid_min, _resid_max])
			if not (_margin_rms > RING_RMS_MIN):
				return _fail("MARGIN, NOT IMMUNITY: with the SAME residual (−0.10) the loop must ring again even though the compensator is on — rms > %.2f, got %.5f. If this arm is quiet, the compensator is not shifting a boundary, it is suppressing the metric" % [RING_RMS_MIN, _margin_rms])
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_slope_est", DIAG_SLOPE),
							  _set_param_cmd("m1", "radome_slope", DIAG_SLOPE)], STEPS, P.DIAGONAL)

		# --- ⭐⭐ THE DIAGONAL — worse glass, perfectly known, and nothing happens -------------------
		P.DIAGONAL:
			if not _drain_scan():
				return false
			_diag_rms = _rms_q()
			print("S27V_DIAGONAL R=R_hat=%.3f  rms_q=%.5f  residual=[%.4f,%.4f]  miss(frame)=%.3f  max|eps|=%.5f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [DIAG_SLOPE, _diag_rms, _resid_min, _resid_max, _min_los, _max_eps, _n_aero, _n_appr, _n_defl, _max_ceil])
			# ⚠ THIS PHASE ALSO MEASURES A DECLARED DOMAIN ENDPOINT (slice 26's post-commit lesson —
			# "the endpoints of a declared domain must be MEASURED, not inferred from the interior"):
			# R̂ = −0.15 is the R̂ slider's FLOOR, a state a student can drag to.
			if not (absf(_resid_min) < 1.0e-9 and absf(_resid_max) < 1.0e-9):
				return _fail("moving BOTH knobs together must hold the residual at exactly 0, got [%.6f, %.6f]" % [_resid_min, _resid_max])
			if not (_diag_rms < QUIET_RMS_MAX):
				return _fail("THE DIAGONAL: glass 1.5× worse than the shipped wire, PERFECTLY KNOWN, must be QUIET (rms < %.2f) — the missile does not care about glass it KNOWS about, which is what makes two knobs ONE lesson. Got %.5f" % [QUIET_RMS_MAX, _diag_rms])
			if not (_max_eps > 1.0e-4):
				return _fail("the diagonal arm must still be REFRACTING harder than the shipped one (max|eps| > 1e-4), got %.6f" % _max_eps)
			if not (_min_los < HIT_MAX):
				return _fail("the diagonal arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _isolation_ok():
				return _fail("the ISOLATION must survive at the DECLARED DOMAIN ENDPOINT: " + _isolation_msg())
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
		"⚠ `aero_sat` is EXPECTED to fire on the ringing arms and is NOT asserted — an oscillation " +
		"drives demand, and demand hits the ceiling; the ceiling BOUNDS the limit cycle (the α_max " +
		"3× invariance is pinned in test_missile.jl) rather than causing it. Do not copy slice 25's " +
		"aero_sat == 0.") % [_n_defl, _n_appr, _max_ceil, CEIL_MAX]

# --- stepping / scanning (the slice-26 contract + the residual/ff accumulators) --------------

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
	_n_defl = 0
	_n_aero = 0
	_max_ceil = 0.0
	_resid_min = 1.0e30
	_resid_max = -1.0e30
	_max_ff = 0.0
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
				# THE APPROACH WINDOW: closing and outside the r→0 endgame, which must be excluded
				# from BOTH the rms and the cap counts — the LOS sweeps past the nose in the last few
				# metres ([[ewsim-missile-verifier-sampling]]).
				if r > 1000.0:
					_n_appr += 1
					var q := float(tel.get(_mid + ".omega_q", 0.0))
					_q_sum += q * q
					_max_eps = maxf(_max_eps, absf(float(tel.get(_mid + ".radome_eps", 0.0))))
					_max_ff = maxf(_max_ff, absf(float(tel.get(_mid + ".radome_ff_el", 0.0))))
					_max_ceil = maxf(_max_ceil, float(tel.get(_mid + ".a_max_aero", 0.0)))
					var rd := float(tel.get(_mid + ".radome_residual", 1.0e30))
					_resid_min = minf(_resid_min, rd)
					_resid_max = maxf(_resid_max, rd)
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
	# Slice 27 REUSES slice 26's view AND its button-dropping marker unchanged — it adds no rung, so
	# there is still nothing to cycle (the slice-16 Option-P′ resolution, third use: 16, 26, 27).
	if not bool(f.get("airframe_view", false)):
		return "a slice-27 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-27 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-27 handshake must ship radome_view=true — the slice-26 marker that DROPS the shared button, INHERITED unchanged because slice 27 adds no rung to cycle"
	var fid: Dictionary = f.get("fidelity", {})
	# EVERY fidelity is HELD — a SLIDER lesson with no toggled rung at all. `R̂ = 0` is an in-domain
	# slider value AND bit-identical to the compensator not existing (measured in test_missile.jl),
	# so the knob-vs-rung discriminator returns KNOB, exactly as it did for slice 26's R.
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-27 scenario must HOLD :seeker_axes at az_el, got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-27 scenario must HOLD :airframe at six_dof — BOTH the radome and its compensator are INERT without it (no attitude to look through, no gyro to feed forward), and the gate is on the LIVE rung, not on :att_q which is never deleted. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-27 scenario must AUTHOR the autopilot at :alpha (the inner α/β/g loop the parasitic path closes through), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-27 scenario must hold :guidance at :pn (the N in the N·|R − R̂| loop gain), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-27 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-27 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the ceiling 93%% of its approach and cannot isolate anything)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-27 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("radome_slope_est"):
		return "slice-27 handshake must expose the 'radome_slope_est' slider — the compensator's BELIEF is the lesson (there is no button)"
	if not keys.has("radome_slope"):
		return "slice-27 handshake must ALSO expose 'radome_slope' — the two knobs are two halves of ONE quantity (the residual R − R̂), and the DIAGONAL phase below is what proves it"
	if keys.size() != 2:
		return "slice-27 must expose EXACTLY TWO knobs (got %d) — convention 9 is satisfied here by the MEASUREMENT that they are one quantity (the diagonal), not by counting sliders, and every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate"). Each of these MOVES the boundary and would let a student cross it without
	# touching either slope — the confounded-lever rule.
	if keys.has("n_pn"):
		return "slice-27 must NOT expose an 'n_pn' knob — it is live-read every tick and moves the LOOP GAIN the lesson is ABOUT (N·|R − R̂|). Slice 26 disqualified it for this reason and the objection is STRONGER here: a student could cross the boundary with BOTH slopes untouched and conclude the compensator did it"
	if keys.has("rho"):
		return "slice-27 must NOT expose a 'rho' knob — |R_crit| ∝ ρ, so it too moves the loop gain"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-27 must NOT expose an 'alpha_max' knob — it sets the limit cycle's AMPLITUDE, i.e. the one thing the isolation must hold fixed"
	if keys.has("sigma_seek"):
		return "slice-27 must NOT expose 'sigma_seek' — on this wire its top compresses the contrast from 63.8x to 23.4x, i.e. a knob that DEGRADES the lesson beside it (slice 26's reasoning, re-measured)"
	if keys.has("speed"):
		return "slice-27 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	# ⚠ EVERY NUMBER HERE IS INTERPOLATED FROM WHAT THIS RUN MEASURED (the slice-21/25 gate-3 bug,
	# fixed structurally). ⚠ And `%g`/`%.2e` are NOT GDScript specifiers — an unknown one makes the
	# WHOLE `%` fail and the line prints as its own format string ON A GREEN RUN. Only %.Nf/%d/%s.
	print(("S27V OK: the missile already carries a rate gyro, so the parasitic term slice 26 built can be " +
		"FED FORWARD AND SUBTRACTED — and it cancels to the accuracy of the slope estimate it is given. " +
		"With the compensator believing NOTHING (R_hat = 0) the shipped R = -0.10 rings at rms %.5f rad/s " +
		"over the approach; a MATCHED estimate (R_hat = %.2f) collapses it to %.5f (%.1fx) with the glass " +
		"still refracting just as hard (max|eps| %.5f) and the gyro feed-forward actually working " +
		"(max %.5f rad/s). ⭐ IT IS A CANCELLATION, NOT A DE-TUNE: both arms still INTERCEPT (frame CPA " +
		"%.3f -> %.3f m, both inside the ~11 m frame grid — the per-tick 2.447 -> 0.316 comparison is " +
		"pinned in test_missile.jl), where a compensator that merely lowered effective N would have " +
		"OPENED the miss instead (gate 0 measured 18.8 m at a residual of +0.4). ⭐ AND IT BUYS MARGIN, " +
		"NOT IMMUNITY: holding that same R_hat while " +
		"the GLASS degrades to %.2f puts the residual back at -0.100 and THE LOOP RINGS AGAIN (rms %.5f) — " +
		"the boundary MOVED, it did not vanish. ⭐⭐ Move BOTH together instead (R = R_hat = %.2f, glass 1.5x " +
		"worse than shipped, perfectly known) and the residual is 0 and the body is QUIET (rms %.5f): THE " +
		"MISSILE DOES NOT CARE ABOUT GLASS IT KNOWS ABOUT, which is what makes two sliders ONE lesson. " +
		"⇒ slice 26's boundary N*|R|/rho ~ 0.38 returns verbatim as N*|R - R_hat|/rho, so the design " +
		"requirement is not a better radome but a BETTER-KNOWN one (here, to +/-0.0475). ⚠ THE METRIC IS " +
		"THE OSCILLATION, NOT THE MISS — every arm still hits (%.2f m on the ringing one). ⚠ The ISOLATION " +
		"is slice 26's: aero_sat DOES fire (%d/%d frames on the ringing arm — a CONSEQUENCE), while " +
		"defl_sat never fires and the ceiling stays far under a_max. Class 4a: the compensator adds NO " +
		"draw, and replay is bit-identical.")
		% [_ring_rms, CURE_EST, _cure_rms, _ring_rms / maxf(_cure_rms, 1.0e-12), _cure_eps, _cure_ff,
		   _ring_miss, _cure_miss, WORSE_SLOPE, _margin_rms, DIAG_SLOPE, _diag_rms,
		   _ring_miss, _ring_aero, _ring_appr])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S27V FAIL: " + msg)
	print("S27V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
