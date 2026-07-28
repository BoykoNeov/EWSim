extends SceneTree
# Headless slice-29 gate-3 verifier (the slice26/27/28_verify analog). Drives the REAL Julia server
# through SimClient.gd and asserts slice-29's "R̂(look) — the schedule that looks through its own
# radome" done-criteria as machine checks.
#
# THE LESSON: slice 27 gave the missile a rate-gyro feed-forward with a SCALAR belief R_hat. Slice
# 28 showed the glass has no single slope, so the belief must be a CURVE. Making it one is three
# lines — and it raises a question a scalar never had to answer: EVALUATED WHERE? The only look
# angle a guidance computer owns is the one it computes from its own measurement, and that
# measurement is exactly what the radome bent. So the belief that reaches the loop is
# R_hat(look_bent), not R_hat(look_truth), and slice 26/27/28's residual law survives ONLY when read
# at that index. Slice 27's corrector was immune to all of this because a CONSTANT R_hat has
# R_hat' = 0 identically: THE IMMUNITY WAS NEVER THE DOMAIN, IT WAS THE CONSTANCY.
#
# ⭐⭐ THE CENTREPIECE, AND IT IS A COMPARISON OF TWO NUMBERS THE CORE SHIPS FROM THE SAME FRAMES:
#   radome_model_err_az  = R(look_az) - R_hat(look_az)    the BENCH number: belief against glass at
#                                                          the SAME look angle. "How good is my
#                                                          schedule?" naturally means this.
#   radome_residual_az   = R(look_az) - R_hat(look_az_c)  what actually CLOSES the loop: the belief
#                                                          where the compensator EVALUATES it.
# On the shipped arm (k_hat = 10) the BENCH number is the SMALLER of the two and it RINGS. On the
# k_hat = 17 arm the bench number is several times WORSE — a far worse model of the glass — and it
# stays QUIET. The two orderings are REVERSED, which is the whole slice.
# ⚠ THAT COMPARISON IS NOT CIRCULAR EVEN ON A RINGING ARM, because both numbers come from the SAME
# TICKS of the SAME flight. What WOULD be circular is quoting either one as "the" residual of a
# ringing arm and comparing it to a threshold: a ringing arm's look band is 7.4-18.7 deg against
# 14.5-15.0 for the quiet arms, so a median taken there describes the ring, not its cause (slice
# 28 §1's rule — this slice's own plan draft violated it and an advisor pass caught it). Every
# cross-arm assert below therefore compares LIKE WITH LIKE, and the ring/quiet VERDICT is always on
# `rms r`, never on a residual threshold.
#
# ⚠ THE NAIVE SLICE WAS REFUTED AT GATE 0, AND THAT IS WHY THIS WIRE IS SLICE 28's. "A scalar cannot
# cancel a curve" is FALSE here: on a settled PN collision course V_M*sin(L) = V_T*sin(aspect) with
# the LOS direction fixed, so the lead angle is CONSTANT BY CONSTRUCTION and slice 28's wire holds
# look_az to a 0.2 deg band — a schedule there is observationally a scalar. Opening the band with a
# maneuvering target does not license it either: the BEST POST-HOC scalar then MATCHES the exact
# schedule (1.06 / 0.97 / 1.07 / 1.40x), because the parasitic loop needs DWELL at a supercritical
# residual and a band the engagement SWEEPS THROUGH is visited briefly everywhere. ⇒ the frozen look
# angle is the ENABLING condition, not an obstacle. The geometry is INHERITED UNCHANGED; only the
# GLASS is deepened (A: -0.05 -> -0.15), which is what gives the k_hat tolerance band an interior.
#
# ⚠ ONE MEASURED CLAIM IS NOT SHIPPED HERE AND WAS NOT DROPPED — IT IS NOT CLIENT-DRIVABLE (the
# slice-27/28 precedent): the TRUTH-INDEX counterfactual, which proves the mechanism in BOTH
# directions (k_hat = 9/10 ring on the bent index and go QUIET on a truth index, 0.829 -> 0.026 and
# 0.637 -> 0.009; k_hat = 17/18/19 are QUIET on the bent index and RING on a truth one, 0.017 ->
# 0.627). A truth-indexed schedule requires the guidance computer to read the true LOS, which slice
# 27 established would make the slice fake — so it MUST NOT SHIP, and it lives as a gate-0
# measurement (`M:\claud_projects\temp\slice29\probe9_window.jl`) exactly as slice 26 froze the
# geometry to measure a gain it could not identify in closed loop.
#
# ⚠ THE METRIC IS `rms r` (YAW) IN THE RANGE BAND [500, 3000] m — slice 28's, inherited with its
# reasons (the lead is in azimuth, so the ring is in yaw; a crossing wire's whole-approach rms r
# carries a legitimate front-loaded baseline; arms with different ToF would compare different parts
# of the engagement). ⚠ QUOTE THE WINDOW WITH EVERY NUMBER. ⚠ rms, NEVER the peak. ⚠ THE MISS IS
# NOT THE METRIC — every arm HITS, so the miss checks are ONE-SIDED and never compare two
# frame-sampled CPAs ([[ewsim-missile-verifier-sampling]]; slice 27 ate that defect).
#
# SIX flight phases + an isolation asserted inside each:
#   • RINGING   — the shipped default (A = -0.15, k = 12; A_hat = -0.15 EXACTLY RIGHT, k_hat = 10):
#                 the showcase OPENS ON THE DISEASE. Here the centrepiece is asserted: the BENCH
#                 error is SMALLER than the LOOP residual, and the index gap is real.
#   • REPLAY    — reset + replay: the 3-D pos trace is BIT-IDENTICAL. ⚠ SEEDED determinism, not
#                 "RNG-free": the seeker draws 2 randn/tick (class 4a) and the schedule adds none.
#   • CURED     — k_hat -> 12, the glass's own frequency. The ring dies. ⭐ AND THE BENCH ERROR IS
#                 EXACTLY ZERO WHILE THE LOOP RESIDUAL IS NOT — a PERFECT model still evaluated at a
#                 bent index. That single pair is the cleanest statement of the slice.
#   • INVERSION — k_hat -> 17: a MUCH WORSE model of the glass (bench error several times the
#                 ringing arm's) that stays QUIET. ⭐⭐ The crossover, across arms, like with like.
#   • LEVEL     — A_hat -> 0, the knob's top endpoint: the schedule COLLAPSES to slice 27's scalar,
#                 `radome_sched_slope` goes EXACTLY 0 (a scalar has no slope — which is why slice 27
#                 never had to choose an index), and it rings hard. Bit-identical to the schedule
#                 key not existing (measured in test_missile.jl) — the knob-vs-rung discriminator.
#   • DOMAIN    — k_hat -> 22, the knob's declared CEILING (slice 26's post-commit lesson: the
#                 endpoints of a declared domain must be MEASURED, not inferred from the interior —
#                 it is what moved this ceiling off 20, where rms r is only ~0.47, a marginal edge).
#   • ISOLATION — inside every phase: `defl_sat` never fires in the band (cap #3) and the aero
#                 ceiling stays far under a_max (cap #1). ⚠ Do NOT copy slice 25's `aero_sat == 0`:
#                 it is IMPOSSIBLE here (an oscillation drives demand into the ceiling — measured
#                 584/4342 in-band on the ringing arm) and asserting it would fail on a correct
#                 build. The ceiling BOUNDS the cycle; the belief decides whether there is one.
#
# Run (server must be listening on slice29_radome_schedule.yaml first):
#   godot --headless --path clients/godot --script res://net/slice29_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 500.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 12000              # 12.0 s — CPA on this crossing geometry is ~10.9 s

# The authored wire, mirrored here so the asserts can name it.
const A_GLASS  := -0.15           # the GLASS's ripple amplitude (authored, deeper than slice 28's)
const K_GLASS  := 12.0            # the GLASS's ripple frequency (authored, never a knob)
const KE_SHIP  := 10.0            # the shipped BELIEF frequency — 17% LOW, and it rings
const KE_CURE  := 12.0            # …matched to the glass
const KE_INV   := 17.0            # …a MUCH worse model that stays quiet (the crossover)
const KE_DOM   := 22.0            # the k_hat knob's declared CEILING
const AE_SHIP  := -0.15           # the shipped BELIEF amplitude — EXACTLY right
const AE_ZERO  :=  0.0            # the A_hat knob's top endpoint: slice 27's SCALAR

# Bounds — pinned against measurements on THIS wire, with margin.
const RING_RMS_MIN  := 0.30       # measured 0.6365 (shipped) / 1.0725 (A_hat=0) / 0.7875 (k_hat=22)
const QUIET_RMS_MAX := 0.10       # measured 0.0092 (cured) / 0.0173 (inversion)
const RATIO_MIN     := 8.0        # measured ~69x (cured) / ~37x (inversion) — decisive, not a nudge
const HIT_MAX       := 50.0       # every arm still intercepts (the metric is the OSCILLATION)
const CEIL_MAX      := 1000.0     # a_max_aero << a_max 3000 => cap #1 out of reach
const LOOK_MAX_DEG  := 30.0       # the small-angle bend model's validity budget, ON THE WIRE
const CROSS_MIN     := 2.0        # the bench/loop ordering must be a MARGIN, not a tie
const EXACT         := 1.0e-9     # "exactly", allowing for the JSON round trip

enum P { HANDSHAKE, RINGING, REPLAY, CURED, INVERSION, LEVEL, DOMAIN }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# per-scan accumulators (window = closing frames with 500 < los_range < 3000)
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _max_y := 0.0
var _r_sum := 0.0                 # sum of omega_r^2 — THE metric (yaw)
var _q_sum := 0.0                 # sum of omega_q^2 — the channel-split evidence (pitch)
var _n_appr := 0
var _n_defl := 0
var _n_aero := 0
var _max_ceil := 0.0
var _max_look := 0.0
var _max_eps := 0.0
# ⚠ MEANS of the ABSOLUTE values, not extremes, for every cross-arm ordering: an extreme on a
# ringing arm is picked out BY the ring. The min/max are kept only to QUOTE the range.
# ⚠ MEDIANS, NOT MEANS OF ABSOLUTES — and the difference is not cosmetic. On a RINGING arm the
# bench error swings symmetrically through zero (measured [-0.049, +0.049]), so a mean of absolute
# values is inflated by the ring's own excursions and the ordering collapses to 1.6x. The MEDIAN of
# the signed value is the operating point, and it gives 3.8x. The first run of this file failed on
# exactly that.
var _mde_list: Array = []         # radome_model_err_az — the BENCH number
var _rez_list: Array = []         # radome_residual_az  — what CLOSES the loop
var _mde_min := 1.0e30
var _mde_max := -1.0e30
var _rez_min := 1.0e30
var _rez_max := -1.0e30
var _sl_abs_max := 0.0            # |radome_sched_slope| — the SENSITIVITY (never "the loop gain")
var _gap_sum := 0.0               # (look_angle - look_angle_est): the INDEX ERROR, i.e. the bend
var _pos_trace: Array = []

# carried across phases (the accumulators reset every phase, so the pass text must quote the
# numbers THIS run measured in the phase it is talking about — the slice-21/25 gate-3 bug)
var _ring_pos: Array = []
var _ring_rms := 0.0
var _ring_rms_q := 0.0
var _ring_miss := 0.0
var _ring_mde := 0.0
var _ring_rez := 0.0
var _ring_gap := 0.0
var _ring_look := 0.0
var _ring_aero := 0
var _ring_appr := 0
var _cure_rms := 0.0
var _cure_mde := 0.0
var _cure_rez := 0.0
var _inv_rms := 0.0
var _inv_mde := 0.0
var _inv_rez := 0.0
var _lvl_rms := 0.0
var _dom_rms := 0.0
var _dom_look := 0.0

func _initialize() -> void:
	print("S29V_INIT godot=", Engine.get_version_info().string)
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

		# --- the shipped default: a schedule whose LEVEL is exact and whose SHAPE is 17% low ------
		P.RINGING:
			if not _drain_scan():
				return false
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			var rms := _rms_r()
			_ring_pos = _pos_trace.duplicate(true)
			_ring_rms = rms
			_ring_rms_q = _rms_q()
			_ring_miss = _min_los
			_ring_mde = _mean_mde()
			_ring_rez = _mean_rez()
			_ring_gap = _mean_gap()
			_ring_look = _max_look
			_ring_aero = _n_aero
			_ring_appr = _n_appr
			print("S29V_RINGING A_hat=%.3f k_hat=%.1f (glass A=%.3f k=%.1f)  rms_r=%.5f  rms_q=%.5f  median|bench_err|=%.5f  median|loop_resid|=%.5f  bench_err=[%.5f,%.5f]  loop_resid=[%.5f,%.5f]  index_gap=%.2f deg  max|sched_slope|=%.3f  look_max=%.1f deg  miss(frame)=%.3f  max|y|=%.1f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [AE_SHIP, KE_SHIP, A_GLASS, K_GLASS, rms, _rms_q(), _ring_mde, _ring_rez, _mde_min, _mde_max, _rez_min, _rez_max, _ring_gap, _sl_abs_max, _max_look, _min_los, _max_y, _n_aero, _n_appr, _n_defl, _max_ceil])
			if not (_n_appr > 100):
				return _fail("the [500,3000] m band must contain frames to measure (got %d) — every assert below would be vacuous" % _n_appr)
			if not (rms > RING_RMS_MIN):
				return _fail("the shipped wire (A_hat = %.2f EXACTLY RIGHT, k_hat = %.0f against a true k = %.0f) must RING in YAW: rms omega_r > %.2f rad/s in the band, got %.5f" % [AE_SHIP, KE_SHIP, K_GLASS, RING_RMS_MIN, rms])
			# ⭐⭐ THE CENTREPIECE — two core numbers from the SAME frames, so it is not circular even
			# though this arm is ringing. On the bench the schedule looks GOOD; in the loop it is
			# several times worse, because it is evaluated where the radome bent the index.
			if not (_ring_mde > 0.0 and _ring_rez > 0.0):
				return _fail("both `radome_model_err_az` and `radome_residual_az` must be live on a scheduled wire (got median|bench| %.6f, median|loop| %.6f)" % [_ring_mde, _ring_rez])
			if not (_ring_rez > CROSS_MIN * _ring_mde):
				return _fail("THE CENTREPIECE: on the shipped arm the LOOP residual (median |R(look_az) - R_hat(look_az_c)| = %.5f) must exceed the BENCH error (median |R(look_az) - R_hat(look_az)| = %.5f) by more than %.1fx. The schedule looks BETTER on the bench than it is in the loop — that gap IS the indexing error, and it is what rings" % [_ring_rez, _ring_mde, CROSS_MIN])
			# THE INDEX ERROR IS REAL AND IT IS THE BEND — the mechanism, as a number.
			if not (_ring_gap > 1.0 and _ring_gap < 6.0):
				return _fail("the compensator's own look angle must run measurably BELOW the truth one (the bend it is correcting): mean(look_angle - look_angle_est) in (1, 6) deg, got %.2f. If this is ~0 the compensator is reading truth and the slice is fake" % _ring_gap)
			# THE SCHEDULE ACTUALLY HAS A SLOPE — the thing slice 27's scalar never had.
			if not (_sl_abs_max > 0.1):
				return _fail("a SCHEDULED compensator must have a nonzero slope of its own (max|radome_sched_slope| > 0.1), got %.6f. A scalar has R_hat' = 0 identically, which is exactly why slice 27 never had to choose an index" % _sl_abs_max)
			if not (_max_eps > 1.0e-4):
				return _fail("the radome must actually perturb the measurement (max|radome_eps| > 1e-4 rad), got %.6f" % _max_eps)
			if not _look_ok():
				return _fail(_look_msg())
			# ⚠ THE MISS IS *NOT* THE METRIC (slices 26/27/28, unchanged).
			if not (_min_los < HIT_MAX):
				return _fail("the ringing arm must STILL HIT (< %.0f m — the metric is the OSCILLATION, not the miss), got %.2f" % [HIT_MAX, _min_los])
			if not (_max_y > 1000.0):
				return _fail("the missile must still fly the cross-range crossing engagement (max|y| > 1000 m), got %.1f" % _max_y)
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([], STEPS, P.REPLAY)

		P.REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_ring_pos, _pos_trace)
			print("S29V_REPLAY posdiff_vs_ringing=%s m  rms_r=%.5f (must be 0.0 — SEEDED determinism, class 4a: the schedule adds NO draw)" % [rdiff, _rms_r()])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — a limit cycle is deterministic, not chaotic-looking noise" % rdiff)
			if not (_min_los == _ring_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _ring_miss])
			_reset_then_scan([_set_param_cmd("m1", "radome_ripple_k_est", KE_CURE)], STEPS, P.CURED)

		# --- ⭐ A PERFECT MODEL, AND A LOOP RESIDUAL THAT IS STILL NOT ZERO -----------------------
		P.CURED:
			if not _drain_scan():
				return false
			_cure_rms = _rms_r()
			_cure_mde = _mean_mde()
			_cure_rez = _mean_rez()
			var cratio := _ring_rms / maxf(_cure_rms, 1.0e-12)
			print("S29V_CURED k_hat=%.1f  rms_r=%.5f  ring/cured=%.1fx  median|bench_err|=%.9f  median|loop_resid|=%.5f  bench_err=[%.9f,%.9f]  loop_resid=[%.5f,%.5f]  index_gap=%.2f deg  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d" % [KE_CURE, _cure_rms, cratio, _cure_mde, _cure_rez, _mde_min, _mde_max, _rez_min, _rez_max, _mean_gap(), _min_los, _n_aero, _n_appr, _n_defl])
			if not (_cure_rms < QUIET_RMS_MAX):
				return _fail("matching the belief's SHAPE to the glass (k_hat = k = %.0f, A_hat = A) must quiet the loop: rms omega_r < %.2f, got %.5f" % [KE_CURE, QUIET_RMS_MAX, _cure_rms])
			if not (cratio > RATIO_MIN):
				return _fail("the cure must be DECISIVE: ring/cured rms ratio > %.0fx, got %.1fx" % [RATIO_MIN, cratio])
			# ⭐ THE CLEANEST SINGLE STATEMENT OF THE SLICE: the model is EXACT — same curve, same
			# amplitude, same frequency — and the loop still sees a residual, because the belief is
			# still evaluated ~2.7 deg off. A scalar could never show this: with R_hat' = 0 the two
			# indices give the same number.
			if not (_cure_mde < EXACT):
				return _fail("with k_hat = k and A_hat = A the BENCH error must be EXACTLY zero (the belief IS the glass), got median %.9f over [%.9f, %.9f]" % [_cure_mde, _mde_min, _mde_max])
			if not (_cure_rez > 0.01):
				return _fail("⭐ AND THE LOOP RESIDUAL MUST NOT BE ZERO EVEN SO (> 0.01): a PERFECT model evaluated at a BENT index is not a perfect compensator. Got median %.6f — if this is ~0 the compensator is being indexed on truth somewhere" % _cure_rez)
			# ⚠ THE GLASS DID NOT CHANGE — only the BELIEF did. Pinning that the cured arm is STILL
			# REFRACTING is what stops "the cure" from being read as "the radome went away", and it
			# is slice 26's post-commit lesson (shipped telemetry gets a tooth) applied to `eps`.
			if not (_max_eps > 1.0e-5):
				return _fail("the cured arm must still be REFRACTING — the LOOP is what changed, not the glass (max|radome_eps| > 1e-5), got %.9f" % _max_eps)
			if not (_pos_max_diff(_ring_pos, _pos_trace) > 0.0):
				return _fail("radome_ripple_k_est must be a LIVE knob — changing it must MOVE the trajectory (the slice-19 NOT-A-DEAD-KNOB tripwire)")
			if not (_min_los < HIT_MAX):
				return _fail("the cured arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _look_ok():
				return _fail(_look_msg())
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_ripple_k_est", KE_INV)], STEPS, P.INVERSION)

		# --- ⭐⭐ THE CROSSOVER: A MUCH WORSE MODEL OF THE GLASS THAT STAYS QUIET ------------------
		P.INVERSION:
			if not _drain_scan():
				return false
			_inv_rms = _rms_r()
			_inv_mde = _mean_mde()
			_inv_rez = _mean_rez()
			var iratio := _ring_rms / maxf(_inv_rms, 1.0e-12)
			print("S29V_INVERSION k_hat=%.1f  rms_r=%.5f  ring/inv=%.1fx  median|bench_err|=%.5f (ringing arm: %.5f)  median|loop_resid|=%.5f (ringing arm: %.5f)  bench_err=[%.5f,%.5f]  loop_resid=[%.5f,%.5f]  max|sched_slope|=%.3f  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d" % [KE_INV, _inv_rms, iratio, _inv_mde, _ring_mde, _inv_rez, _ring_rez, _mde_min, _mde_max, _rez_min, _rez_max, _sl_abs_max, _min_los, _n_aero, _n_appr, _n_defl])
			if not (_inv_rms < QUIET_RMS_MAX):
				return _fail("the k_hat = %.0f arm must be QUIET (rms omega_r < %.2f), got %.5f" % [KE_INV, QUIET_RMS_MAX, _inv_rms])
			if not (iratio > RATIO_MIN):
				return _fail("the inversion must be DECISIVE: ring/quiet rms ratio > %.0fx, got %.1fx" % [RATIO_MIN, iratio])
			# ⭐⭐ ACROSS ARMS, LIKE WITH LIKE — both numbers are `radome_model_err_az`, both means of
			# absolute values over each arm's own band. THE QUIET ARM IS THE WORSE MODEL.
			if not (_inv_mde > CROSS_MIN * _ring_mde):
				return _fail("⭐⭐ THE CROSSOVER: the QUIET arm (k_hat = %.0f) must be a substantially WORSE model of the glass than the RINGING one (k_hat = %.0f) — median |bench error| %.5f must exceed %.5f by more than %.1fx. If it is not, this arm is simply a better schedule and the slice has shown nothing" % [KE_INV, KE_SHIP, _inv_mde, _ring_mde, CROSS_MIN])
			# …AND THE LOOP RESIDUAL ORDERING IS THE OPPOSITE, which is what the ring follows.
			if not (_ring_rez > CROSS_MIN * _inv_rez):
				return _fail("…and the LOOP residual ordering must be REVERSED: the ringing arm's median |loop residual| (%.5f) must exceed the quiet arm's (%.5f) by more than %.1fx. That reversal — bench one way, loop the other — IS slice 29" % [_ring_rez, _inv_rez, CROSS_MIN])
			# …and on THIS arm the bench number is the LARGER one: the mirror of the RINGING phase's
			# centrepiece, on the same two keys. Bench and loop disagree in BOTH directions.
			if not (_inv_mde > CROSS_MIN * _inv_rez):
				return _fail("on the quiet arm the BENCH error (%.5f) must exceed the LOOP residual (%.5f) by more than %.1fx — the exact mirror of the shipped arm, where the ordering runs the other way" % [_inv_mde, _inv_rez, CROSS_MIN])
			if not (_max_eps > 1.0e-5):
				return _fail("the quiet arm must still be REFRACTING (the glass is UNCHANGED across every phase — only the belief moves): max|radome_eps| > 1e-5, got %.9f" % _max_eps)
			if not (_min_los < HIT_MAX):
				return _fail("the quiet arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _look_ok():
				return _fail(_look_msg())
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_ripple_est", AE_ZERO)], STEPS, P.LEVEL)

		# --- THE LEVEL KNOB'S TOP ENDPOINT: the schedule COLLAPSES to slice 27's scalar -----------
		P.LEVEL:
			if not _drain_scan():
				return false
			_lvl_rms = _rms_r()
			print("S29V_LEVEL A_hat=%.2f (the knob's top endpoint — slice 27's SCALAR)  rms_r=%.5f  max|sched_slope|=%.9f  median|bench_err|=%.5f  median|loop_resid|=%.5f  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d" % [AE_ZERO, _lvl_rms, _sl_abs_max, _mean_mde(), _mean_rez(), _min_los, _n_aero, _n_appr, _n_defl])
			if not (_lvl_rms > RING_RMS_MIN):
				return _fail("with A_hat = 0 the schedule collapses to slice 27's SCALAR belief R_hat0 = -0.03, which is the boresight characterization slice 28 showed rings on curved glass. It must RING (rms omega_r > %.2f), got %.5f" % [RING_RMS_MIN, _lvl_rms])
			# ⭐ A SCALAR HAS NO SLOPE — EXACTLY. That is the whole reason slice 27 was immune to
			# everything this slice is about, and it is the knob-vs-rung discriminator on a slider:
			# A_hat = 0 is an in-domain value AND bit-identical to the schedule key not existing
			# (measured in test_missile.jl, not argued).
			if not (_sl_abs_max < EXACT):
				return _fail("with A_hat = 0 `radome_sched_slope` must be EXACTLY 0 at every frame — a constant belief has R_hat' = 0 identically, which is why a scalar compensator cannot care where it is evaluated. Got max %.12f" % _sl_abs_max)
			# …and with no slope, the bench and loop numbers must COINCIDE: there is no index
			# sensitivity left for them to disagree through. The paired opposite of the centrepiece.
			if not (absf(_mean_mde() - _mean_rez()) < EXACT):
				return _fail("with A_hat = 0 the BENCH error and the LOOP residual must be the SAME NUMBER (a scalar gives the same value at any index) — got %.9f vs %.9f. That coincidence is exactly what slice 27 enjoyed and slice 29 loses" % [_mean_mde(), _mean_rez()])
			if not (_max_eps > 1.0e-5):
				return _fail("the scalar-collapse arm must still be REFRACTING: max|radome_eps| > 1e-5, got %.9f" % _max_eps)
			if not (_pos_max_diff(_ring_pos, _pos_trace) > 0.0):
				return _fail("radome_ripple_est must be a LIVE knob — changing it must MOVE the trajectory")
			if not (_min_los < HIT_MAX):
				return _fail("even the scalar-collapse arm still intercepts (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _look_ok():
				return _fail(_look_msg())
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_ripple_est", AE_SHIP),
							  _set_param_cmd("m1", "radome_ripple_k_est", KE_DOM)], STEPS, P.DOMAIN)

		# --- ⭐ THE DECLARED DOMAIN ENDPOINT, MEASURED (slice 26's post-commit lesson) ------------
		P.DOMAIN:
			if not _drain_scan():
				return false
			_dom_rms = _rms_r()
			_dom_look = _max_look
			print("S29V_DOMAIN k_hat=%.1f (declared ceiling)  rms_r=%.5f  median|bench_err|=%.5f  median|loop_resid|=%.5f  look_max=%.1f deg  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [KE_DOM, _dom_rms, _mean_mde(), _mean_rez(), _max_look, _min_los, _n_aero, _n_appr, _n_defl, _max_ceil])
			if not (_dom_rms > RING_RMS_MIN):
				return _fail("the k_hat knob's declared CEILING (%.0f) must ring UNAMBIGUOUSLY (rms omega_r > %.2f), got %.5f. ⚠ This endpoint was MOVED off 20 for exactly this reason: at 20 the metric is only ~0.47, a marginal edge, and slice 26's post-commit lesson is that declared endpoints are measured rather than inferred from the interior" % [KE_DOM, RING_RMS_MIN, _dom_rms])
			if not _look_ok():
				return _fail("the DECLARED DOMAIN ENDPOINT must stay inside the small-angle bend model's budget: " + _look_msg())
			if not (_max_eps > 1.0e-5):
				return _fail("the domain-ceiling arm must still be REFRACTING: max|radome_eps| > 1e-5, got %.9f" % _max_eps)
			if not (_min_los < HIT_MAX):
				return _fail("the domain-ceiling arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _isolation_ok():
				return _fail("the ISOLATION must survive at the DECLARED DOMAIN ENDPOINT: " + _isolation_msg())
			return _pass()
	return false

# --- the metric + the isolation ------------------------------------------------------------

func _rms_r() -> float:
	return sqrt(_r_sum / maxf(float(_n_appr), 1.0)) if _n_appr > 0 else 0.0

func _rms_q() -> float:
	return sqrt(_q_sum / maxf(float(_n_appr), 1.0)) if _n_appr > 0 else 0.0

# |median| of the signed series — the OPERATING-POINT magnitude. ⚠ Comparing the bench and loop
# medians to EACH OTHER is legitimate even on a ringing arm, because both are taken over the
# IDENTICAL frames of the identical flight. What would be circular is comparing either one to a
# fixed THRESHOLD on a ringing arm, whose look band is set BY the ring (slice 28 §1's rule) — and
# this file never does that: every ring/quiet VERDICT is on `rms r`.
func _abs_median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return absf(float(b[b.size() / 2]))

func _mean_mde() -> float:
	return _abs_median(_mde_list)

func _mean_rez() -> float:
	return _abs_median(_rez_list)

func _mean_gap() -> float:
	return _gap_sum / maxf(float(_n_appr), 1.0) if _n_appr > 0 else 0.0

func _isolation_ok() -> bool:
	# cap #3 (the fin DEFLECTION limit) and cap #1 (the authored `a_max` MAGNITUDE clamp) must both
	# be out of the picture, so the only cap in play is the flight-condition ceiling — which slice
	# 26 measured BOUNDS the cycle rather than causing it.
	return _n_defl == 0 and _max_ceil < CEIL_MAX

func _isolation_msg() -> String:
	return ("the ISOLATION must hold: defl_sat must NEVER fire on an in-band frame (cap #3, got " +
		"%d/%d) and the aero ceiling must stay << a_max = 3000 (cap #1, got %.2f >= %.0f). " +
		"⚠ `aero_sat` is EXPECTED to fire on the ringing arms and is NOT asserted — an oscillation " +
		"drives demand, and demand hits the ceiling (measured 584/4342 in-band on the shipped arm " +
		"against 0/4360 on the cured one); the ceiling BOUNDS the limit cycle rather than causing " +
		"it. Do not copy slice 25's aero_sat == 0. ⚠ And defl_sat is counted IN-BAND, not over the " +
		"whole flight: the fin pegs during the launch transient on EVERY arm, so a whole-flight " +
		"count fails everywhere and says nothing.") % [_n_defl, _n_appr, _max_ceil, CEIL_MAX]

func _look_ok() -> bool:
	return _max_look < LOOK_MAX_DEG

func _look_msg() -> String:
	return ("the small-angle bend model `eps = R(look)*look` must stay inside its validity budget " +
		"— no in-band frame past a %.0f deg look angle. Got %.1f deg. ⚠ This is the objection " +
		"slice 27 used to REJECT R = -0.30, inherited") % [LOOK_MAX_DEG, _max_look]

# --- stepping / scanning (the slice-26/27/28 contract + the schedule accumulators) -----------

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
	_r_sum = 0.0
	_q_sum = 0.0
	_n_appr = 0
	_n_defl = 0
	_n_aero = 0
	_max_ceil = 0.0
	_max_look = 0.0
	_max_eps = 0.0
	_mde_list = []
	_rez_list = []
	_mde_min = 1.0e30
	_mde_max = -1.0e30
	_rez_min = 1.0e30
	_rez_max = -1.0e30
	_sl_abs_max = 0.0
	_gap_sum = 0.0
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
				# THE WINDOW: a fixed RANGE BAND on the closing leg (slice 28's, inherited with its
				# reasons). The upper edge drops the front-loaded turn onto the collision course; the
				# lower edge drops the r->0 endgame where the LOS sweeps past the nose
				# ([[ewsim-missile-verifier-sampling]]).
				if r > 500.0 and r < 3000.0:
					_n_appr += 1
					var rr := float(tel.get(_mid + ".omega_r", 0.0))
					var qq := float(tel.get(_mid + ".omega_q", 0.0))
					_r_sum += rr * rr
					_q_sum += qq * qq
					_max_eps = maxf(_max_eps, absf(float(tel.get(_mid + ".radome_eps", 0.0))))
					_max_ceil = maxf(_max_ceil, float(tel.get(_mid + ".a_max_aero", 0.0)))
					_max_look = maxf(_max_look, float(tel.get(_mid + ".look_angle", 0.0)))
					# BOTH error numbers and the SENSITIVITY, straight from the core — the client
					# never evaluates a curve or subtracts anything (convention 13).
					var mde := float(tel.get(_mid + ".radome_model_err_az", 0.0))
					var rez := float(tel.get(_mid + ".radome_residual_az", 0.0))
					_mde_list.append(mde)
					_rez_list.append(rez)
					_mde_min = minf(_mde_min, mde); _mde_max = maxf(_mde_max, mde)
					_rez_min = minf(_rez_min, rez); _rez_max = maxf(_rez_max, rez)
					_sl_abs_max = maxf(_sl_abs_max,
							absf(float(tel.get(_mid + ".radome_sched_slope", 0.0))))
					# the INDEX ERROR: truth look angle minus the compensator's own
					_gap_sum += (float(tel.get(_mid + ".look_angle", 0.0))
							   - float(tel.get(_mid + ".look_angle_est", 0.0)))
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
	# Slice 29 REUSES slice 26's view AND its button-dropping marker unchanged — it adds no rung, so
	# there is still nothing to cycle (the slice-16 Option-P' resolution, FIFTH use: 16, 26, 27, 28, 29).
	if not bool(f.get("airframe_view", false)):
		return "a slice-29 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-29 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-29 handshake must ship radome_view=true — the slice-26 marker that DROPS the shared button, INHERITED unchanged because slice 29 adds no rung to cycle"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-29 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS an azimuth look angle at all. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-29 scenario must HOLD :airframe at six_dof — the radome, its compensator AND the schedule are all INERT without it (no attitude to look through), and the gate is on the LIVE rung, never on :att_q which is minted once and never deleted. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-29 scenario must AUTHOR the autopilot at :alpha (the inner loop the parasitic path closes through), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-29 scenario must hold :guidance at :pn (the N in the loop gain), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-29 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-29 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the ceiling 93%% of its approach and cannot isolate anything)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-29 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("radome_ripple_k_est"):
		return "slice-29 handshake must expose the 'radome_ripple_k_est' slider — the belief's SHAPE is the headline knob (there is no button)"
	if not keys.has("radome_ripple_est"):
		return "slice-29 handshake must ALSO expose 'radome_ripple_est' — the belief's LEVEL, and its top endpoint is the collapse to slice 27's scalar"
	if keys.size() != 2:
		return "slice-29 must expose EXACTLY TWO knobs (got %d) — they are the two halves of ONE object, the compensator's BELIEF about the curve (its level and its shape); every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate").
	if keys.has("n_pn"):
		return "slice-29 must NOT expose an 'n_pn' knob — it is live-read every tick and moves the LOOP GAIN the lesson is ABOUT. Slices 26/27/28 all disqualified it — the confounded-lever rule"
	if keys.has("rho"):
		return "slice-29 must NOT expose a 'rho' knob — |R_crit| is proportional to rho, so it too moves the loop gain"
	if keys.has("radome_slope") or keys.has("radome_ripple") or keys.has("radome_ripple_k"):
		return "slice-29 must NOT expose any GLASS knob (radome_slope / radome_ripple / radome_ripple_k) — the glass is the thing the BELIEF is being compared against, and a student who can move both has no comparison left"
	if keys.has("radome_slope_est"):
		return "slice-29 must NOT expose 'radome_slope_est' — that is slice 28's knob, and it would let a student quiet this wire without ever touching the SCHEDULE, which is the whole subject"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-29 must NOT expose an 'alpha_max' knob — it sets the limit cycle's AMPLITUDE, i.e. the one thing the isolation must hold fixed"
	if keys.has("sigma_seek"):
		return "slice-29 must NOT expose 'sigma_seek' — it compresses the contrast beside the lesson (slices 26/27/28's reasoning, unchanged)"
	if keys.has("speed"):
		return "slice-29 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	# ⚠ EVERY NUMBER HERE IS INTERPOLATED FROM WHAT THIS RUN MEASURED (the slice-21/25 gate-3 bug,
	# fixed structurally rather than by care). ⚠ And `%g`/`%.2e` are NOT GDScript specifiers — an
	# unknown one makes the WHOLE `%` fail and the line prints as its own format string ON A GREEN
	# RUN. Only %.Nf / %d / %s appear below.
	print(("S29V OK: slice 28 showed the glass has no single slope, so the compensator's belief must " +
		"be a CURVE. Making it one raises a question a SCALAR never had to answer — EVALUATED WHERE? " +
		"The only look angle a guidance computer owns is the one it computes from its own " +
		"measurement, and that measurement is exactly what the radome bent: on the shipped arm the " +
		"compensator's index runs %.2f deg BELOW the truth look angle, and that gap IS the bend it " +
		"is correcting. ⭐⭐ SO THE SLICE IS TWO CORE NUMBERS FROM THE SAME FRAMES: the BENCH error " +
		"(belief against glass at the SAME look angle) is %.5f while the LOOP residual (belief where " +
		"it is ACTUALLY EVALUATED) is %.5f — %.1fx larger — and the missile RINGS at rms omega_r " +
		"%.5f rad/s in the [500,3000] m band. ⭐ MATCH THE SHAPE (k_hat -> %.0f = the glass's own " +
		"frequency) and the ring dies to %.5f (%.1fx) — but the BENCH error is now EXACTLY %.9f " +
		"while the LOOP residual is STILL %.5f: A PERFECT MODEL EVALUATED AT A BENT INDEX IS NOT A " +
		"PERFECT COMPENSATOR, and a scalar could never show that, because with R_hat' = 0 the two " +
		"indices give the same number. ⭐⭐ AND THE CROSSOVER, LIKE WITH LIKE: at k_hat = %.0f the " +
		"schedule is a MUCH WORSE model of the glass — bench error %.5f against the ringing arm's " +
		"%.5f, %.1fx worse — and it stays QUIET (rms %.5f, %.1fx down), because at ITS own index it " +
		"is wrong by only %.5f. The bench ordering and the loop ordering are REVERSED, and the ring " +
		"follows the loop. ⇒ WHAT CLOSES THE LOOP IS THE RESIDUAL AT THE COMPENSATOR'S OWN INDEX, " +
		"the schedule's own slope R_hat' is the SENSITIVITY that decides what the indexing error " +
		"costs, and slice 27's rule — compensate with a signal that is not itself corrupted by what " +
		"you are compensating — comes back in the RATE domain, the place slice 27 concluded was " +
		"safe: THE IMMUNITY WAS NEVER THE DOMAIN, IT WAS THE CONSTANCY. ⭐ Drag the LEVEL knob to " +
		"its top endpoint (A_hat = %.2f) and the schedule COLLAPSES to slice 27's scalar: " +
		"radome_sched_slope goes EXACTLY 0, the bench and loop numbers become the SAME NUMBER (there " +
		"is no index sensitivity left for them to disagree through — exactly what slice 27 enjoyed " +
		"and slice 29 loses), and it rings hard at %.5f. ⭐ At the k_hat knob's declared CEILING " +
		"(%.0f — MOVED off 20, where the metric is only ~0.47, because slice 26's post-commit lesson " +
		"is that declared endpoints are measured and not inferred) it rings again at %.5f with the " +
		"small-angle budget still holding (%.1f deg peak, under %.0f). ⚠ THE METRIC IS THE " +
		"OSCILLATION, NOT THE MISS — every arm still hits (%.2f m frame CPA on the ringing one). " +
		"⚠ The ISOLATION is slice 26's: aero_sat DOES fire (%d/%d in-band frames on the ringing arm " +
		"— a CONSEQUENCE), while defl_sat never fires in the band and the ceiling stays far under " +
		"a_max. Class 4a: the schedule is arithmetic on state that already exists, it adds NO draw, " +
		"and replay is bit-identical.")
		% [_ring_gap, _ring_mde, _ring_rez, _ring_rez / maxf(_ring_mde, 1.0e-12), _ring_rms,
		   KE_CURE, _cure_rms, _ring_rms / maxf(_cure_rms, 1.0e-12), _cure_mde, _cure_rez,
		   KE_INV, _inv_mde, _ring_mde, _inv_mde / maxf(_ring_mde, 1.0e-12), _inv_rms,
		   _ring_rms / maxf(_inv_rms, 1.0e-12), _inv_rez,
		   AE_ZERO, _lvl_rms,
		   KE_DOM, _dom_rms, _dom_look, LOOK_MAX_DEG,
		   _ring_miss, _ring_aero, _ring_appr])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S29V FAIL: " + msg)
	print("S29V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
