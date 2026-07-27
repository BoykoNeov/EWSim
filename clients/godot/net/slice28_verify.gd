extends SceneTree
# Headless slice-28 gate-3 verifier (the slice26/27_verify analog). Drives the REAL Julia server
# through SimClient.gd and asserts slice-28's "R(look) — the slope curve, and the band the
# engagement visits" done-criteria as machine checks.
#
# THE LESSON: a radome's boresight-error slope is not a NUMBER, it is a CURVE in look angle. Slice
# 26's parasitic loop is closed by that curve's LOCAL DERIVATIVE at the look angle the missile is
# actually flying — and WHICH look angle that is belongs to the ENGAGEMENT, not to the radome. A
# static target's collision course carries zero lead and settles the seeker onto boresight, where
# the curve is flat by construction; a CROSSING target holds a sustained lead and parks it on a
# steep part of the glass. So slice 27's compensator, characterized at boresight — the natural place
# to characterize it — is exactly right where it is never used and wrong where the loop is closed.
# ⇒ "know your slope" sharpens into "KNOW YOUR SLOPE CURVE OVER THE BAND THE ENGAGEMENT VISITS".
#
# ⭐⭐ THE CENTREPIECE ASSERT, AND SLICE 27 COULD NOT HAVE WRITTEN IT: on the shipped wire the
# HARDWARE residual `radome_residual` = R0 - R_hat is EXACTLY 0.000 — the compensator's belief
# matches the glass it was characterized against, perfectly — AND THE MISSILE RINGS, because the
# ENGAGEMENT residual `radome_residual_az` = R(look_az) - R_hat is ~-0.078 where the seeker is
# actually looking. The CURED phase below is the mirror image: hardware +0.100, engagement 0.000,
# and the body is quiet. Slice 27 had only ONE of those two keys, because it had only one slope.
#
# ⚠ TWO PHASES THE PLAN LISTED FOR THIS FILE LIVE IN `test_missile.jl` INSTEAD, AND NEITHER WAS
# DROPPED — NEITHER IS CLIENT-DRIVABLE (the slice-27 precedent: its alpha_max isolation lives there
# because alpha_max is deliberately not a knob):
#   • the NON-MONOTONE crossing-speed sweep with both controls (the slice's headline isolation) —
#     the target's velocity is not a comp key, so `set_param` cannot reach it;
#   • the matched-SECANT / matched-DERIVATIVE triple (the fact that LICENSES the slice) —
#     `radome_slope` is not a slice-28 knob, and the trio must be flown at R0 = 0 anyway so that the
#     secant arm lands INSIDE critical (on this wire the secant is ~-0.079, already past
#     |R_crit| ~ 0.065, and BOTH linear arms would ring — the trap that spoiled two gate-0 runs).
#
# ⚠ THE METRIC IS `rms r` (YAW), a DELIBERATE DEPARTURE from slices 26/27's `rms q` (pitch), not
# "the arc's metric, continued": the lead angle is in AZIMUTH, so the ring is in yaw. `rms q` is
# asserted BESIDE it as the CHANNEL-SPLIT evidence — one radome, two channels, two operating points,
# a signature no CONSTANT slope can produce (a constant rings both channels together, measured
# 0.844 pitch against 0.838 yaw in the derivative arm of the triple above).
# ⚠ THE WINDOW IS A RANGE BAND [500, 3000] m on the CLOSING leg, and every number is quoted with it
# (slice 26's two-windows-two-ratios rule). It is a band and not a tick fraction for two measured
# reasons: on a crossing wire `rms r` carries a LEGITIMATE front-loaded baseline (the turn onto the
# collision course — 0.172 over the whole approach against 0.0138 inside the band), and arms with
# different ToF would otherwise compare DIFFERENT PARTS of the engagement.
# ⭐ The metric is FRAME-ROBUST (per-tick 1.04174 vs frame-sampled 1.04145), which is why the
# oscillation beats any miss here. ⚠ rms, NEVER the peak. ⚠ THE MISS IS NOT THE METRIC — every arm
# still HITS, so the miss checks below are ONE-SIDED and never compare two frame-sampled CPAs
# ([[ewsim-missile-verifier-sampling]]: a HIT samples coarsely; slice 27 ate that defect).
#
# FIVE flight phases + an isolation asserted inside each:
#   • RINGING  — the shipped default (R0 = -0.03, A = -0.05, R_hat = -0.03 = R(0)): the showcase
#                OPENS ON THE DISEASE, so the body is already ringing when a client connects. This
#                is where the hardware-residual-zero centrepiece is asserted.
#   • REPLAY   — reset + replay the same config: the 3-D pos trace is BIT-IDENTICAL. ⚠ SEEDED
#                determinism, not "RNG-free": the seeker draws 2 randn/tick (class 4a) and the CURVE
#                ADDS NO DRAW.
#   • FLAT     — A -> 0 (the knob's top endpoint): the ring dies, and the TWO CHANNEL GAINS COLLAPSE
#                onto ONE number, R0. `A = 0` is bit-identical to the ripple key not existing
#                (measured in test_missile.jl) — the knob-vs-rung discriminator, on a slider.
#   • CURED    — A back at -0.05, R_hat -> -0.13 = R(15 deg): THE SCALAR THAT WORKS IS SET BY THE
#                ENGAGEMENT. The glass is UNCHANGED and still steep where the seeker looks; only the
#                BELIEF moved, and it moved AWAY from the hardware's boresight truth.
#   • DOMAIN   — A -> -0.10, the knob's declared FLOOR (slice 26's post-commit lesson: the endpoints
#                of a declared domain must be MEASURED, not inferred from the interior). It rings
#                harder, the local slope reaches the curve's exact BOUND R0 + 2A = -0.23 — bounded is
#                WHY this form shipped and the cubic was killed at gate 0 — and the small-angle
#                model's validity budget still holds (no in-band frame past a 30 deg look angle).
#   • ISOLATION — inside every phase: `defl_sat` never fires in the band (cap #3) and the aero
#                ceiling stays far under a_max (cap #1). ⚠ Do NOT copy slice 25's `aero_sat == 0`:
#                it is IMPOSSIBLE here (an oscillation drives demand into the ceiling — 59% of the
#                ringing band) and asserting it would fail on a correct build. ⚠ Nor copy slice 27's
#                `defl_sat == 0` unexamined: the WHOLE-FLIGHT tick count is 1-2 on several arms; it
#                is 0 for every in-band FRAME, which is what is asserted and what was measured.
#
# Run (server must be listening on slice28_radome_curve.yaml first):
#   godot --headless --path clients/godot --script res://net/slice28_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 400.0
const SimClientScript := preload("res://net/SimClient.gd")

const STEPS := 12000              # 12.0 s — CPA on this crossing geometry is ~10.9 s

# The authored wire, mirrored here so the asserts can name it.
const R0        := -0.03          # the BORESIGHT slope: R(0) = R0 for EVERY amplitude
const A_SHIP    := -0.05          # the shipped ripple amplitude
const FLAT_A    :=  0.0           # the A knob's top endpoint (flat glass)
const DOMAIN_A  := -0.10          # the A knob's declared FLOOR
const CURE_EST  := -0.13          # R(15 deg): the ENGAGEMENT-correct characterization

# Bounds — pinned against measurements on THIS wire, with margin.
const RING_RMS_MIN  := 0.40       # measured 1.0414 (shipped) / 1.0930 (domain floor)
const QUIET_RMS_MAX := 0.10       # measured 0.0145 (flat) / 0.0129 (cured)
const RATIO_MIN     := 8.0        # measured ~72x (flat) / ~81x (cured) — decisive, not a nudge
const HIT_MAX       := 50.0       # every arm still intercepts (the metric is the OSCILLATION)
const CEIL_MAX      := 1000.0     # a_max_aero (measured 321.3) << a_max 3000 => cap #1 out of reach
const LOOK_MAX_DEG  := 30.0       # the small-angle bend model's validity budget, ON THE WIRE
                                  # (measured max 22.4 shipped / 24.2 at the domain floor)
const SPLIT_MIN     := 0.02       # the two channel gains must be genuinely two numbers
const EXACT         := 1.0e-9     # "exactly", allowing for the JSON round trip

enum P { HANDSHAKE, RINGING, REPLAY, FLAT, CURED, DOMAIN }

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
var _max_eps := 0.0
var _max_ff := 0.0
var _n_defl := 0
var _n_aero := 0
var _max_ceil := 0.0
var _max_look := 0.0
var _saz_min := 1.0e30
var _saz_max := -1.0e30
var _sel_min := 1.0e30
var _sel_max := -1.0e30
var _rez_min := 1.0e30
var _rez_max := -1.0e30
var _res_min := 1.0e30
var _res_max := -1.0e30
var _pos_trace: Array = []

# carried across phases (the accumulators reset every phase, so the pass text must quote the
# numbers THIS run measured in the phase it is talking about — the slice-21/25 gate-3 bug)
var _ring_pos: Array = []
var _ring_rms := 0.0
var _ring_rms_q := 0.0
var _ring_miss := 0.0
var _ring_rez := 0.0
var _ring_rez_lo := 0.0
var _ring_res := 0.0
var _ring_saz := 0.0
var _ring_saz_lo := 0.0
var _ring_sel := 0.0
var _ring_look := 0.0
var _ring_aero := 0
var _ring_appr := 0
var _flat_rms := 0.0
var _cure_rms := 0.0
var _cure_saz := 0.0
var _cure_rez := 0.0
var _dom_rms := 0.0
var _dom_saz := 0.0
var _dom_look := 0.0

func _initialize() -> void:
	print("S28V_INIT godot=", Engine.get_version_info().string)
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

		# --- the shipped default: a compensator characterized at BORESIGHT, on curved glass --------
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
			_ring_rez = _rez_max          # the CLOSEST-to-zero engagement residual in the band
			_ring_rez_lo = _rez_min       # …and the far end: the pass text quotes the RANGE, because
			_ring_res = _res_max          # a single extreme quoted as "the" value is a half-truth
			_ring_saz = _saz_max          # the FLATTEST local yaw-channel slope in the band
			_ring_saz_lo = _saz_min       # …and the steepest
			_ring_sel = _sel_max
			_ring_look = _max_look
			_ring_aero = _n_aero
			_ring_appr = _n_appr
			print("S28V_RINGING A=%.3f R0=%.3f R_hat=%.3f  rms_r=%.5f  rms_q=%.5f  hw_residual=[%.6f,%.6f]  engagement_residual_az=[%.5f,%.5f]  R(look_az)=[%.5f,%.5f]  R(look_el)=[%.5f,%.5f]  look_max=%.1f deg  max|eps|=%.5f  miss(frame)=%.3f  max|y|=%.1f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [A_SHIP, R0, R0, rms, _rms_q(), _res_min, _res_max, _rez_min, _rez_max, _saz_min, _saz_max, _sel_min, _sel_max, _max_look, _max_eps, _min_los, _max_y, _n_aero, _n_appr, _n_defl, _max_ceil])
			if not (_n_appr > 100):
				return _fail("the [500,3000] m band must contain frames to measure (got %d) — every assert below would be vacuous" % _n_appr)
			if not (rms > RING_RMS_MIN):
				return _fail("the shipped wire (R0 = %.2f, A = %.2f, R_hat = R(0) = %.2f) must RING in YAW: rms omega_r > %.2f rad/s in the band, got %.5f" % [R0, A_SHIP, R0, RING_RMS_MIN, rms])
			# ⭐⭐ THE CENTREPIECE. The HARDWARE residual is EXACTLY zero — the compensator's belief
			# matches the slope the glass was characterized at, perfectly — and it rings anyway.
			if not (absf(_res_min) < EXACT and absf(_res_max) < EXACT):
				return _fail("the HARDWARE residual R0 - R_hat must be EXACTLY 0 on this wire (that is the whole point: a perfectly-characterized radome), got [%.9f, %.9f]" % [_res_min, _res_max])
			# …while the ENGAGEMENT residual, where the seeker is actually looking, is nowhere near 0
			if not (_rez_max < -0.03):
				return _fail("the ENGAGEMENT residual R(look_az) - R_hat must be far from zero across the WHOLE band (< -0.03), got a closest-to-zero value of %.5f. If this is ~0 the seeker is sitting on the glass's flat spot and the slice has no operating point" % _rez_max)
			# ⭐ THE CHANNEL SPLIT — the second isolation. The lead is in AZIMUTH, so the yaw channel
			# sits well off the boresight slope while the pitch channel sits ON it. A CONSTANT slope
			# cannot produce this (it gives both channels one gain and rings them together).
			if not (_rms_q() < 0.5 * rms):
				return _fail("THE CHANNEL SPLIT: the ring must be in YAW, not shared — rms omega_q (%.5f) must be under half rms omega_r (%.5f). Both channels ringing together is the signature of a CONSTANT slope" % [_rms_q(), rms])
			if not (_saz_max < -0.05):
				return _fail("the YAW channel must sit well OFF the boresight slope for the whole band (R(look_az) < -0.05), got a flattest value of %.5f" % _saz_max)
			if not (absf(_sel_min - R0) < 0.005 and absf(_sel_max - R0) < 0.005):
				return _fail("the PITCH channel must sit ON the boresight slope %.3f (the lead is in azimuth, look_el ~ 0), got R(look_el) in [%.5f, %.5f]" % [R0, _sel_min, _sel_max])
			if not (absf(_saz_max - _sel_max) > SPLIT_MIN):
				return _fail("the two channel gains must be genuinely TWO NUMBERS on ONE radome (separation > %.2f), got %.5f vs %.5f" % [SPLIT_MIN, _saz_max, _sel_max])
			if not (_max_eps > 1.0e-4):
				return _fail("the radome must actually perturb the measurement (max|radome_eps| > 1e-4 rad), got %.6f" % _max_eps)
			if not _look_ok():
				return _fail(_look_msg())
			# ⚠ THE MISS IS *NOT* THE METRIC (slices 26/27, unchanged). Pinning that the ringing arm
			# HITS stops a later slice from "fixing" this scenario by chasing a miss.
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
			print("S28V_REPLAY posdiff_vs_ringing=%s m  rms_r=%.5f (must be 0.0 — SEEDED determinism, class 4a: the curve adds NO draw)" % [rdiff, _rms_r()])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — a limit cycle is deterministic, not chaotic-looking noise" % rdiff)
			if not (_min_los == _ring_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _ring_miss])
			_reset_then_scan([_set_param_cmd("m1", "radome_ripple", FLAT_A)], STEPS, P.FLAT)

		# --- FLAT GLASS: the A knob's top endpoint. The channel split COLLAPSES. -------------------
		P.FLAT:
			if not _drain_scan():
				return false
			_flat_rms = _rms_r()
			var fratio := _ring_rms / maxf(_flat_rms, 1.0e-12)
			print("S28V_FLAT A=%.3f  rms_r=%.5f  ring/flat=%.1fx  R(look_az)=[%.6f,%.6f]  R(look_el)=[%.6f,%.6f]  engagement_residual_az=[%.6f,%.6f]  max|eps|=%.5f  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d" % [FLAT_A, _flat_rms, fratio, _saz_min, _saz_max, _sel_min, _sel_max, _rez_min, _rez_max, _max_eps, _min_los, _n_aero, _n_appr, _n_defl])
			if not (_flat_rms < QUIET_RMS_MAX):
				return _fail("flat glass (A = 0) must be QUIET: rms omega_r < %.2f, got %.5f. With R_hat = R0 the boresight-characterized compensator is now correct EVERYWHERE, because there is nowhere else to be" % [QUIET_RMS_MAX, _flat_rms])
			if not (fratio > RATIO_MIN):
				return _fail("the ripple must be DECISIVE: ring/flat rms ratio > %.0fx, got %.1fx" % [RATIO_MIN, fratio])
			# ⭐ THE CHANNEL SPLIT VANISHES — both gains collapse onto R0, from the core, as numbers.
			# The paired opposite of the RINGING phase's split assert.
			if not (absf(_saz_min - R0) < EXACT and absf(_saz_max - R0) < EXACT
					and absf(_sel_min - R0) < EXACT and absf(_sel_max - R0) < EXACT):
				return _fail("with A = 0 BOTH channel gains must be exactly the boresight slope %.3f — the curve is gone and the two operating points collapse onto one. Got R(look_az) in [%.9f, %.9f], R(look_el) in [%.9f, %.9f]" % [R0, _saz_min, _saz_max, _sel_min, _sel_max])
			if not (absf(_rez_min) < EXACT and absf(_rez_max) < EXACT):
				return _fail("with A = 0 and R_hat = R0 the ENGAGEMENT residual must be exactly 0 everywhere, got [%.9f, %.9f]" % [_rez_min, _rez_max])
			# THE GLASS IS STILL THERE — it is FLAT, not absent. What changed is the CURVE.
			if not (_max_eps > 1.0e-5):
				return _fail("flat glass still REFRACTS (R0 = %.2f is still a radome): max|eps| > 1e-5, got %.6f" % [R0, _max_eps])
			# …and the knob is LIVE (the slice-19 NOT-A-DEAD-KNOB tripwire): it MOVED the physics.
			if not (_pos_max_diff(_ring_pos, _pos_trace) > 0.0):
				return _fail("radome_ripple must be a LIVE knob — changing it must MOVE the trajectory")
			if not _look_ok():
				return _fail(_look_msg())
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_slope_est", CURE_EST)], STEPS, P.CURED)

		# --- ⭐ THE SCALAR THAT WORKS IS SET BY THE ENGAGEMENT, NOT BY THE RADOME ------------------
		P.CURED:
			if not _drain_scan():
				return false
			_cure_rms = _rms_r()
			_cure_saz = _saz_max
			_cure_rez = _rez_max
			var cratio := _ring_rms / maxf(_cure_rms, 1.0e-12)
			print("S28V_CURED A=%.3f R_hat=%.3f  rms_r=%.5f  ring/cured=%.1fx  hw_residual=[%.6f,%.6f]  engagement_residual_az=[%.6f,%.6f]  R(look_az)=[%.5f,%.5f]  max|ff|=%.5f  max|eps|=%.5f  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d" % [A_SHIP, CURE_EST, _cure_rms, cratio, _res_min, _res_max, _rez_min, _rez_max, _saz_min, _saz_max, _max_ff, _max_eps, _min_los, _n_aero, _n_appr, _n_defl])
			if not (_cure_rms < QUIET_RMS_MAX):
				return _fail("an ENGAGEMENT-correct estimate (R_hat = R(15 deg) = %.2f) must quiet the loop: rms omega_r < %.2f, got %.5f" % [CURE_EST, QUIET_RMS_MAX, _cure_rms])
			if not (cratio > RATIO_MIN):
				return _fail("the cure must be DECISIVE: ring/cured rms ratio > %.0fx, got %.1fx" % [RATIO_MIN, cratio])
			# ⭐⭐ THE MIRROR OF THE CENTREPIECE: the estimate is now WRONG about the hardware by a
			# full 0.100 — and RIGHT about the engagement. Both numbers come from the core.
			if not (absf(_res_min - (R0 - CURE_EST)) < EXACT and absf(_res_max - (R0 - CURE_EST)) < EXACT):
				return _fail("the HARDWARE residual must now be exactly %.3f — the compensator has been deliberately DE-characterized away from the boresight truth. Got [%.9f, %.9f]" % [R0 - CURE_EST, _res_min, _res_max])
			if not (absf(_rez_min) < 0.01 and absf(_rez_max) < 0.01):
				return _fail("the ENGAGEMENT residual R(look_az) - R_hat must collapse to ~0 across the band (|.| < 0.01) — that is the quantity that decides. Got [%.6f, %.6f]" % [_rez_min, _rez_max])
			# THE GLASS DID NOT CHANGE. The local slope where the seeker looks is still steep; only
			# the BELIEF moved. (A cure that worked by flattening the glass would show up here.)
			if not (_saz_max < -0.10):
				return _fail("the GLASS is unchanged and must still be steep where the seeker looks (R(look_az) < -0.10 across the band), got a flattest value of %.5f. Only the BELIEF moved" % _saz_max)
			# THE FEED-FORWARD IS ACTUALLY DOING SOMETHING — the mechanism, not just the outcome.
			if not (_max_ff > 1.0e-4):
				return _fail("the gyro feed-forward must be nonzero on the cured arm (max|radome_ff_el| > 1e-4 rad/s), got %.6f" % _max_ff)
			if not (_max_eps > 1.0e-5):
				return _fail("the cured arm must still be REFRACTING (the LOOP is what changed, not the glass): max|eps| > 1e-5, got %.6f" % _max_eps)
			if not (_pos_max_diff(_ring_pos, _pos_trace) > 0.0):
				return _fail("radome_slope_est must be a LIVE knob — changing it must MOVE the trajectory")
			# ⚠ ONE-SIDED, AND NEVER A COMPARISON OF TWO FRAME-SAMPLED CPAs (slice 27's own defect):
			# both arms HIT and at emit_every 16 / ~700 m/s the frame grid is ~11 m wide, so a
			# perfect intercept can report several metres. The per-tick misses (0.364 ringing ->
			# 0.197 cured) are pinned in test_missile.jl, where per-tick sampling is available.
			if not (_min_los < HIT_MAX):
				return _fail("the cured arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _look_ok():
				return _fail(_look_msg())
			if not _isolation_ok():
				return _fail(_isolation_msg())
			_reset_then_scan([_set_param_cmd("m1", "radome_ripple", DOMAIN_A)], STEPS, P.DOMAIN)

		# --- ⭐ THE DECLARED DOMAIN ENDPOINT, MEASURED (slice 26's post-commit lesson) -------------
		P.DOMAIN:
			if not _drain_scan():
				return false
			_dom_rms = _rms_r()
			_dom_saz = _saz_min
			_dom_look = _max_look
			print("S28V_DOMAIN A=%.3f (declared floor)  rms_r=%.5f  R(look_az)=[%.5f,%.5f]  bound R0+2A=%.5f  engagement_residual_az=[%.5f,%.5f]  look_max=%.1f deg  miss(frame)=%.3f  aero_sat=%d/%d  defl_sat=%d  ceil_max=%.2f" % [DOMAIN_A, _dom_rms, _saz_min, _saz_max, R0 + 2.0 * DOMAIN_A, _rez_min, _rez_max, _max_look, _min_los, _n_aero, _n_appr, _n_defl, _max_ceil])
			if not (_dom_rms > RING_RMS_MIN):
				return _fail("the A knob's declared FLOOR must still ring (rms omega_r > %.2f), got %.5f" % [RING_RMS_MIN, _dom_rms])
			# ⭐ BOUNDEDNESS, MEASURED — and it is WHY this curve form shipped. The slope ripple is
			# bounded to [R0, R0+2A] by construction, so the slope can be driven far past critical
			# while the BEND stays small. A cubic (killed at gate 0) has an UNBOUNDED slope: the
			# amplitude that puts the off-axis slope past critical also makes the bend diverge, the
			# miss explodes to km, and the small-angle model carries the lesson exactly where it is
			# invalid. Assert BOTH halves: the bound is RESPECTED, and it is actually REACHED.
			if not (_saz_min > R0 + 2.0 * DOMAIN_A - EXACT):
				return _fail("the local slope must respect the curve's exact bound R0 + 2A = %.3f (that boundedness is why this form shipped and the cubic was killed), got a minimum of %.9f" % [R0 + 2.0 * DOMAIN_A, _saz_min])
			if not (_saz_min < R0 + 2.0 * DOMAIN_A + 0.02):
				return _fail("the engagement must actually VISIT the steep end of the curve, i.e. the bound %.3f must be REACHED and not merely respected, got a minimum of %.5f" % [R0 + 2.0 * DOMAIN_A, _saz_min])
			# THE ENDPOINT'S MODEL-VALIDITY BUDGET — measured at the endpoint, not inferred from the
			# interior. This is what bounds the domain, and it is asserted rather than described.
			if not _look_ok():
				return _fail("the DECLARED DOMAIN ENDPOINT must stay inside the small-angle bend model's budget: " + _look_msg())
			if not (_min_los < HIT_MAX):
				return _fail("the domain-floor arm must still intercept (< %.0f m), got %.2f" % [HIT_MAX, _min_los])
			if not _isolation_ok():
				return _fail("the ISOLATION must survive at the DECLARED DOMAIN ENDPOINT: " + _isolation_msg())
			return _pass()
	return false

# --- the metric + the isolation ------------------------------------------------------------

func _rms_r() -> float:
	return sqrt(_r_sum / maxf(float(_n_appr), 1.0)) if _n_appr > 0 else 0.0

func _rms_q() -> float:
	return sqrt(_q_sum / maxf(float(_n_appr), 1.0)) if _n_appr > 0 else 0.0

func _isolation_ok() -> bool:
	# cap #3 (the fin DEFLECTION limit) and cap #1 (the authored `a_max` MAGNITUDE clamp) must both
	# be out of the picture, so the only cap in play is the flight-condition ceiling — which slice
	# 26 measured BOUNDS the cycle (raise alpha_max 3x and the onset does not move) rather than
	# causing it.
	return _n_defl == 0 and _max_ceil < CEIL_MAX

func _isolation_msg() -> String:
	return ("the ISOLATION must hold: defl_sat must NEVER fire on an in-band frame (cap #3, got " +
		"%d/%d) and the aero ceiling must stay << a_max = 3000 (cap #1, got %.2f >= %.0f). " +
		"⚠ `aero_sat` is EXPECTED to fire on the ringing arms and is NOT asserted — an oscillation " +
		"drives demand, and demand hits the ceiling; the ceiling BOUNDS the limit cycle rather than " +
		"causing it (slice 26's alpha_max 3x invariance). Do not copy slice 25's aero_sat == 0. " +
		"⚠ Nor slice 27's defl_sat == 0 over ALL ticks: the whole-flight count is 1-2 here, and it " +
		"is the IN-BAND frame count that was measured at 0.") % [_n_defl, _n_appr, _max_ceil, CEIL_MAX]

func _look_ok() -> bool:
	return _max_look < LOOK_MAX_DEG

func _look_msg() -> String:
	return ("the small-angle bend model `eps = R(look)*look` must stay inside its validity budget " +
		"— no in-band frame past a %.0f deg look angle (measured max 22.4 on the shipped arm, 24.2 " +
		"at the domain floor). Got %.1f deg. ⚠ This is the objection slice 27 used to REJECT " +
		"R = -0.30, and it is what bounds this slice's knob domain") % [LOOK_MAX_DEG, _max_look]

# --- stepping / scanning (the slice-26/27 contract + the curve accumulators) -----------------

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
	_max_eps = 0.0
	_max_ff = 0.0
	_n_defl = 0
	_n_aero = 0
	_max_ceil = 0.0
	_max_look = 0.0
	_saz_min = 1.0e30
	_saz_max = -1.0e30
	_sel_min = 1.0e30
	_sel_max = -1.0e30
	_rez_min = 1.0e30
	_rez_max = -1.0e30
	_res_min = 1.0e30
	_res_max = -1.0e30
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
				# THE WINDOW: a fixed RANGE BAND on the closing leg. The upper edge drops the
				# front-loaded turn onto the collision course (a LEGITIMATE yaw rate, 0.172 vs
				# 0.0138 inside the band); the lower edge drops the r->0 endgame, where the LOS
				# sweeps past the nose ([[ewsim-missile-verifier-sampling]]).
				if r > 500.0 and r < 3000.0:
					_n_appr += 1
					var rr := float(tel.get(_mid + ".omega_r", 0.0))
					var qq := float(tel.get(_mid + ".omega_q", 0.0))
					_r_sum += rr * rr
					_q_sum += qq * qq
					_max_eps = maxf(_max_eps, absf(float(tel.get(_mid + ".radome_eps", 0.0))))
					_max_ff = maxf(_max_ff, absf(float(tel.get(_mid + ".radome_ff_el", 0.0))))
					_max_ceil = maxf(_max_ceil, float(tel.get(_mid + ".a_max_aero", 0.0)))
					_max_look = maxf(_max_look, float(tel.get(_mid + ".look_angle", 0.0)))
					# the per-AXIS channel gains and BOTH residuals, straight from the core — the
					# client never evaluates the curve or subtracts anything (convention 13)
					var saz := float(tel.get(_mid + ".radome_slope_az", 1.0e30))
					var sel := float(tel.get(_mid + ".radome_slope_el", 1.0e30))
					var rez := float(tel.get(_mid + ".radome_residual_az", 1.0e30))
					var res := float(tel.get(_mid + ".radome_residual", 1.0e30))
					_saz_min = minf(_saz_min, saz); _saz_max = maxf(_saz_max, saz)
					_sel_min = minf(_sel_min, sel); _sel_max = maxf(_sel_max, sel)
					_rez_min = minf(_rez_min, rez); _rez_max = maxf(_rez_max, rez)
					_res_min = minf(_res_min, res); _res_max = maxf(_res_max, res)
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
	# Slice 28 REUSES slice 26's view AND its button-dropping marker unchanged — it adds no rung, so
	# there is still nothing to cycle (the slice-16 Option-P' resolution, FOURTH use: 16, 26, 27, 28).
	if not bool(f.get("airframe_view", false)):
		return "a slice-28 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-28 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-28 handshake must ship radome_view=true — the slice-26 marker that DROPS the shared button, INHERITED unchanged because slice 28 adds no rung to cycle"
	var fid: Dictionary = f.get("fidelity", {})
	# EVERY fidelity is HELD — a SLIDER lesson with no toggled rung at all. `A = 0` is an in-domain
	# slider value AND bit-identical to the ripple key not existing (measured in test_missile.jl),
	# so the knob-vs-rung discriminator returns KNOB, as it did for slice 26's R and slice 27's R_hat.
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-28 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS an azimuth look angle at all. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-28 scenario must HOLD :airframe at six_dof — the radome, its compensator AND the ripple are all INERT without it (no attitude to look through), and the gate is on the LIVE rung, never on :att_q which is minted once and never deleted. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-28 scenario must AUTHOR the autopilot at :alpha (the inner alpha/beta/g loop the parasitic path closes through), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-28 scenario must hold :guidance at :pn (the N in the N*|R(look) - R_hat| loop gain), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-28 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-28 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the ceiling 93%% of its approach and cannot isolate anything)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-28 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("radome_ripple"):
		return "slice-28 handshake must expose the 'radome_ripple' slider — the slope CURVE's amplitude is the new lesson (there is no button)"
	if not keys.has("radome_slope_est"):
		return "slice-28 handshake must ALSO expose 'radome_slope_est' — slice 27's compensator, inherited, and the payload is which scalar it must be set to"
	if keys.size() != 2:
		return "slice-28 must expose EXACTLY TWO knobs (got %d) — they are the two halves of ONE quantity, the ENGAGEMENT residual R(look_az) - R_hat, which the core ships as a number; every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate").
	if keys.has("n_pn"):
		return "slice-28 must NOT expose an 'n_pn' knob — it is live-read every tick and moves the LOOP GAIN the lesson is ABOUT (N*|R(look) - R_hat|). Slices 26 and 27 both disqualified it — the confounded-lever rule"
	if keys.has("rho"):
		return "slice-28 must NOT expose a 'rho' knob — |R_crit| is proportional to rho, so it too moves the loop gain"
	if keys.has("radome_ripple_k"):
		return "slice-28 must NOT expose a 'radome_ripple_k' knob — the metric is NON-MONOTONE in k (quiet/rings/rings/marginal/quiet/rings at k = 4/6/8.2/12/16/24), because k decides WHERE ON THE WIGGLE the operating look angle lands. The monotonicity rule, 4th occurrence (slices 19, 22)"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-28 must NOT expose an 'alpha_max' knob — it sets the limit cycle's AMPLITUDE, i.e. the one thing the isolation must hold fixed"
	if keys.has("sigma_seek"):
		return "slice-28 must NOT expose 'sigma_seek' — it compresses the contrast beside the lesson (slices 26/27's reasoning, unchanged)"
	if keys.has("speed"):
		return "slice-28 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
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
	print(("S28V OK: a radome's error slope is not a NUMBER, it is a CURVE in look angle — and the " +
		"parasitic loop slice 26 built is closed by that curve's LOCAL DERIVATIVE at the look angle " +
		"the engagement actually holds. ⭐⭐ THE WHOLE SLICE IS ONE PAIR OF NUMBERS THE CORE SHIPS: on " +
		"the shipped wire the HARDWARE residual R0 - R_hat is EXACTLY %.3f — the compensator's belief " +
		"matches the glass it was characterized against, perfectly — and the missile RINGS at rms " +
		"omega_r %.5f rad/s in the [500,3000] m band, because the ENGAGEMENT residual R(look_az) - " +
		"R_hat runs %.5f to %.5f across that band — never near zero — where the seeker is actually " +
		"looking (a crossing target holds a sustained lead, measured %.1f deg peak off boresight). " +
		"⭐ THE RING IS IN YAW AND THAT IS THE SECOND " +
		"ISOLATION — one radome, TWO channels, two operating points: R(look_az) runs %.4f to %.4f " +
		"against R(look_el) pinned at %.4f, rms omega_r %.5f against rms omega_q %.5f. A CONSTANT slope cannot " +
		"produce this; it gives both channels one gain and rings them together (the matched-DERIVATIVE " +
		"arm in test_missile.jl does exactly that). ⭐ FLATTEN THE GLASS (A -> %.2f, the knob's top " +
		"endpoint) and the two gains COLLAPSE onto the single number %.3f, the engagement residual " +
		"goes to exactly 0 and the body is quiet (rms %.5f, %.1fx). ⭐⭐ OR LEAVE THE GLASS ALONE AND " +
		"MOVE THE BELIEF: R_hat -> %.2f = R(15 deg) makes the compensator WRONG about the hardware by " +
		"a full %.3f and RIGHT about the engagement (residual %.5f), the local slope where the seeker " +
		"looks is never flatter than %.4f — unchanged glass — and the ring collapses to %.5f (%.1fx). ⇒ THE SCALAR " +
		"THAT WORKS IS SET BY THE ENGAGEMENT, NOT BY THE RADOME, and characterizing at BORESIGHT is " +
		"the natural AND DANGEROUS choice: R(0) = R0 for every amplitude, so it is exactly right in " +
		"the one place the loop is never closed. ⭐ AT THE A KNOB'S DECLARED FLOOR (%.2f) it rings " +
		"harder (rms %.5f), the local slope REACHES the curve's exact bound R0 + 2A = %.3f (measured " +
		"%.5f — that BOUNDEDNESS is why this form shipped and the cubic was killed at gate 0: an " +
		"unbounded slope makes the bend diverge and the miss explode to km) and the small-angle " +
		"model's budget still holds (%.1f deg peak, under %.0f). ⚠ THE METRIC IS THE OSCILLATION, NOT " +
		"THE MISS — every arm still hits (%.2f m frame CPA on the ringing one). ⚠ The ISOLATION is " +
		"slice 26's: aero_sat DOES fire (%d/%d in-band frames on the ringing arm — a CONSEQUENCE), " +
		"while defl_sat never fires in the band and the ceiling stays far under a_max. Class 4a: the " +
		"curve is arithmetic on state that already exists, it adds NO draw, and replay is " +
		"bit-identical.")
		% [_ring_res, _ring_rms, _ring_rez_lo, _ring_rez, _ring_look, _ring_saz_lo, _ring_saz,
		   _ring_sel, _ring_rms, _ring_rms_q,
		   FLAT_A, R0, _flat_rms, _ring_rms / maxf(_flat_rms, 1.0e-12),
		   CURE_EST, R0 - CURE_EST, _cure_rez, _cure_saz, _cure_rms,
		   _ring_rms / maxf(_cure_rms, 1.0e-12),
		   DOMAIN_A, _dom_rms, R0 + 2.0 * DOMAIN_A, _dom_saz, _dom_look, LOOK_MAX_DEG,
		   _ring_miss, _ring_aero, _ring_appr])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S28V FAIL: " + msg)
	print("S28V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
