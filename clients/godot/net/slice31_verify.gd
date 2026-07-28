extends SceneTree
# Headless slice-31 gate-3 verifier (the slice26/27/28/29/30_verify analog). Drives the REAL Julia
# server through SimClient.gd and asserts slice-31's "an imperfect gyro" done-criteria as machine
# checks.
#
# THE LESSON: every compensator slices 27-30 built multiplies a RATE GYRO READING by a believed
# slope and subtracts it, and all four assumed that reading is TRUTH. It is not — and the two ways
# it fails land in TWO DIFFERENT CURRENCIES. A SCALE FACTOR is common-mode on the product, so the
# belief that reaches the loop is exactly R_hat*(1+s): it lands back on slice 26/27's RESIDUAL and
# moves the STABILITY BOUNDARY. A BIAS never touches the belief — it injects a constant spurious LOS
# rate R_hat*b, which moves the AIM POINT and has no residual to move.
#
# ⭐⭐ SO THE HEADLINE IS THAT SLICE 30's MARGIN IS A GYRO BUDGET. Slice 30 measured its rule as
# SUFFICIENT, NEVER TIGHT — the envelope goes quiet ABOVE the aim point. Slice 31 says what that
# margin BUYS: aiming at the glass's worst-case slope tolerates a -21% scale-factor error, while a
# design "sharpened" to the onset measured on this very wire (-0.260) tolerates almost none and rings
# on a realistic 5% one. The shipped wire IS that sharpened design, and it opens RINGING.
# ⭐ AND IT HAS TWO DIFFERENT CURES, one slider each — which is the slice on one screen:
#     gyro_scale_err -> 0                  BUY A BETTER GYRO
#     radome_slope_est -> radome_aim_gyro  DESIGN MORE CONSERVATIVELY
#
# ⚠⚠ AND THE FILE SAYS OUT LOUD WHAT GATE 0 FOUND, BECAUSE IT IS AN ASSERT HERE (phase EQUIV): the
# scale-factor half is a REPARAMETERIZATION OF A SHIPPED KNOB, not a new mechanism — (R_hat, s) flies
# the SAME MISSILE as (R_hat*(1+s), perfect gyro). That is the project's FALSE-FIDELITY class (slice
# 15's k_delta cancellation, slice 16's refused toggle, slice 19's dead `speed` knob) caught in the
# open and shipped as a TOOTH. ⚠ It is asserted as an `atol`, NEVER as bit-identity: the two
# multiplication orders differ in the last ULPs, so an equality would be a false claim about the same
# physics. The BIAS is the term no other knob on this wire reaches, and phase PRICE is the claim that
# needs it.
#
# ⚠⚠ "A BIAS NEVER RINGS" IS TOO STRONG AND THIS FILE ASSERTS THE NARROWED VERSION (phase MARGINAL).
# A bias steers the missile, which moves the LOOK ANGLE, which on CURVED glass moves the ENGAGEMENT
# residual — slice 28's mechanism arriving through the SENSOR. The curve's extremum sits at look =
# 15 deg and this engagement holds ~13.6, so a NEGATIVE bias walks the seeker UP ONTO THE STEEPEST
# GLASS. It flips a MARGINAL design (R_hat = -0.265, 0.005 past the onset) and cannot touch one
# carrying slice 30's margin. ⇒ THE MARGIN IS MEASURED TWICE, IN BOTH CURRENCIES.
#
# ⚠ THE METRIC, THE WINDOW AND THE CHANNEL ARE SLICE 28/29/30's: rms r (YAW) in the RANGE BAND
# [500, 3000] m. ⚠ QUOTE THE WINDOW WITH EVERY NUMBER. ⚠ rms, NEVER the peak. ⚠ THE MISS IS NOT THE
# METRIC — every arm here HITS, and a frame-sampled CPA on an ~11 m grid cannot resolve the
# differences ([[ewsim-missile-verifier-sampling]]: a HIT samples COARSELY; slice 27's verifier ate
# exactly that defect). Nothing in this file asserts a miss comparison.
#
# THE ARMS (17 flights, driven as reset -> set_param -> step, so every knob is applied at t = 0):
#   • DISEASE   x1 — the shipped wire: R_hat = -0.27 (sharpened past the onset) with s = -0.05.
#                    Expect RING. Reads `radome_slope_worst` and `radome_aim_gyro` OFF THE WIRE.
#   • REPLAY    x1 — the same arm re-flown: bit-identical (class 4a; both gyro terms are
#                    DETERMINISTIC and add no draw).
#   • CURE A    x1 — s -> 0. Expect QUIET.
#   • CURE B    x1 — R_hat -> `radome_aim_gyro` (read off the wire, never recomputed in GDScript).
#                    Expect QUIET *and* the EFFECTIVE belief to land exactly on slice 30's
#                    `radome_slope_worst` — the rule tying itself to slice 30's number.
#   • EQUIV     x1 — R_hat = -0.2565 with a PERFECT gyro: the same flight as DISEASE, to an atol.
#   • SAME_EFF  x2 — a THIRD aim point (-0.30) with s chosen to land on each side of the onset:
#                    the verdict follows R_hat*(1+s) and NOT s. The convention-9 discriminator.
#   • BIAS      x4 — the bias swept across its whole domain at slice 30's aim point R_worst, with a
#                    PERFECT gyro (so the MARGINAL contrast below moves exactly ONE thing — the
#                    belief). Expect QUIET at every one, while the aim point moves with b.
#   • MARGINAL  x2 — the honest narrowing: the SAME bias magnitude, opposite signs, on a design
#                    only 0.005 past the onset. One rings, one does not.
#   • PRICE     x4 — ⭐ the claim only the BIAS can produce: with the same bias present, CURE B costs
#                    measurably MORE aim-point error than CURE A. Quiet-to-quiet, per-frame.
#   • ISOLATION — inside every full arm: `defl_sat` never fires in the band (cap #3), the aero
#                 ceiling stays far under a_max (cap #1), the small-angle bend model stays inside its
#                 30 deg budget, and the arm reached CPA. ⚠ Do NOT copy slice 25's `aero_sat == 0`
#                 globally: it is IMPOSSIBLE on a ringing arm (slice 26). It IS asserted on the QUIET
#                 bias/price arms, where an aim-point claim could otherwise be confounded by slice
#                 19's ceiling (advisor).
#
# Run (server must be listening on slice31_gyro.yaml first):
#   godot --headless --path clients/godot --script res://net/slice31_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 1800.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor (every knob on this wire lives here)

# 12.8 s: the slowest arm measured is ~11.8 s to CPA, and every arm must turn the corner or its
# "miss" is only a last closing range (slice 30's discipline, inherited).
# ⚠⚠ AND IT MUST BE A MULTIPLE OF `emit_every` (16), WHICH IS A REAL TRAP THIS FILE FELL INTO. The
# server emits every 16th tick, so with STEPS = 15000 the LAST frame it ever sends is t = 14.992 —
# and `_drain_scan` waits for `t >= STEPS*dt` = 15.000, which never arrives. The run then hangs
# silently until MAX_SECONDS with no output at all, which reads exactly like a slow wire (two hours
# were spent measuring the core and the emit path before the arithmetic was checked: the core runs
# 27k ticks/s and the verifier drains 5k ticks/s, so a 15 s arm takes ~3 s, not minutes). Slice 30's
# 20000 = 16*1250 lands exactly and never showed it. 12800 = 16*800.
const STEPS := 12800

# The authored wire, mirrored so the asserts can name it.
const RHAT_SHIP := -0.27          # the SHARPENED aim point (just past the onset -0.260)
const S_SHIP    := -0.05          # a realistic cheap-MEMS scale-factor error
const RHAT_EQUIV := -0.2565       # = RHAT_SHIP * (1 + S_SHIP): the reparameterization twin
const RHAT_THIRD := -0.30         # a THIRD aim point for the same-effective-belief phase
const S_THIRD_RING  := -0.145     # -> effective -0.2565 (the DISEASE's own effective belief)
const S_THIRD_QUIET := -0.070     # -> effective -0.2790 (clear of the onset)
const RHAT_MARGIN := -0.265       # 0.005 past the measured onset: the MARGINAL design
const B_MARGIN := 0.02            # the same magnitude, both signs, on that marginal design
const BIASES := [-0.08, -0.02, 0.02, 0.08]

# Bounds — pinned against gate 0 on THIS wire at THIS seed, with margin.
const RING_LINE := 0.30           # the verdict line the whole arc has used
                                  # measured here: DISEASE 0.402 (1.34x above), CURE A 0.031
const CURE_MIN_RATIO := 4.0       # measured 13.0x (cure A) and 7.6x (cure B)
const EQUIV_ATOL := 1.0e-3        # measured max|dpos| 6.4e-11 m over the whole flight
const HIT_MAX := 60.0             # every arm intercepts; the metric is the OSCILLATION
const CEIL_MAX := 1000.0          # a_max_aero << a_max 3000 => cap #1 out of reach
const LOOK_MAX_DEG := 30.0        # the small-angle bend model's validity budget, ON THE WIRE
const PRICE_MIN_RATIO := 1.3      # measured 1.68-1.75x across both signs of b
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}

# per-arm accumulators (window = closing frames with 500 < los_range < 3000)
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _r_sum := 0.0                 # sum of omega_r^2 — THE metric (yaw)
var _q_sum := 0.0                 # the channel-split companion (pitch)
var _n_appr := 0
var _n_defl := 0
var _n_aero := 0
var _max_ceil := 0.0
var _max_look := 0.0
var _max_eps := 0.0
var _worst := 0.0                 # radome_slope_worst — slice 30's aim point, OFF THE WIRE
var _aimg := 0.0                  # radome_aim_gyro — slice 31's re-aimed point, OFF THE WIRE
var _eff := 0.0                   # radome_slope_est_eff — the belief the LOOP sees
var _sval := 0.0                  # gyro_scale_err, as the wire reports it
var _bval := 0.0                  # gyro_bias_z
var _inj_list: Array = []         # gyro_inject_az — the additive injection (the FORMULA)
var _azd_list: Array = []         # los_azdot_true — the CLOSED-LOOP consequence (the aim point)
var _rez_list: Array = []         # radome_residual_az_eff — the residual that decides
var _rez0_list: Array = []        # radome_residual_az — slice 28's key, MEANING UNCHANGED
var _azr_list: Array = []         # los_omega_true is not shipped; the aim point is read as below
var _pos_trace: Array = []

func _initialize() -> void:
	print("S31V_INIT godot=", Engine.get_version_info().string)
	_t0 = _now()
	_client = SimClientScript.new()
	_client.frame_received.connect(func(obj: Dictionary) -> void: _inbox.append(obj))
	_client.start(HOST, PORT)

func _process(_dt_frame: float) -> bool:
	if _now() - _t0 > MAX_SECONDS:
		return _fail("TIMEOUT in arm %s" % _tag(), 2)
	_client.poll()

	if not _handshaked:
		var f := _take("scenario")
		if f.is_empty():
			return false
		var verr := _check_handshake(f)
		if verr != "":
			return _fail(verr)
		_dt = float(f.get("dt_physics", 1.0e-3))
		_handshaked = true
		_build_arms()
		_start_next()
		return false

	if not _drain_scan():
		return false
	var aerr := _finish_arm()
	if aerr != "":
		return _fail(aerr)
	if _idx + 1 >= _arms.size():
		return _verdict()
	_start_next()
	return false

# --- the flight plan ------------------------------------------------------------------------

func _build_arms() -> void:
	# 1) THE DISEASE — the shipped wire, untouched. It also READS the two aim points off the wire.
	_arms.append({"tag": "disease"})
	# 2) REPLAY — bit-identical, held seed (class 4a: both gyro terms are deterministic).
	_arms.append({"tag": "replay"})
	# 3) CURE A — buy a better gyro.
	_arms.append({"tag": "cureA", "s": 0.0})
	# 4) CURE B — design more conservatively, at the rule's OWN re-aimed point read off the wire.
	_arms.append({"tag": "cureB", "rhat_from": "disease"})
	# 5) ⭐ THE REPARAMETERIZATION TWIN — a PERFECT gyro at the belief the scale factor produces.
	_arms.append({"tag": "equiv", "s": 0.0, "rhat": RHAT_EQUIV})
	# 6) SAME EFFECTIVE BELIEF, DIFFERENT KNOBS — the verdict follows R_hat*(1+s), not s.
	_arms.append({"tag": "third_ring", "rhat": RHAT_THIRD, "s": S_THIRD_RING})
	_arms.append({"tag": "third_quiet", "rhat": RHAT_THIRD, "s": S_THIRD_QUIET})
	# 7) THE OTHER CURRENCY — the bias across its whole domain, at the conservative aim point.
	# ⚠ `s` IS PINNED TO 0 HERE ON PURPOSE (advisor): these arms are the CONTRAST for the MARGINAL
	# pair below, which flies a perfect gyro, and leaving the authored s = -0.05 in place would move
	# TWO things between the two halves of that comparison (the aim point AND the sensor). With s = 0
	# the only difference is the belief — which is the one thing the phase is about.
	for b in BIASES:
		_arms.append({"tag": "bias:%d" % int(round(b * 1000.0)), "rhat": -0.33, "s": 0.0, "b": b})
	# 8) ⚠ THE HONEST NARROWING — the same bias magnitude, opposite signs, on a MARGINAL design.
	_arms.append({"tag": "marg_neg", "rhat": RHAT_MARGIN, "s": 0.0, "b": -B_MARGIN})
	_arms.append({"tag": "marg_pos", "rhat": RHAT_MARGIN, "s": 0.0, "b": +B_MARGIN})
	# 9) ⭐ THE PRICE OF CURE B — the claim only the BIAS can produce, measured quiet-to-quiet as the
	#    CHANGE in the aim-point error between the two cures at the same bias (and at both signs, so
	#    it is not a sign artifact).
	_arms.append({"tag": "pA0", "s": 0.0})
	_arms.append({"tag": "pA1", "s": 0.0, "b": 0.01})
	_arms.append({"tag": "pB0", "rhat_from": "disease"})
	_arms.append({"tag": "pB1", "rhat_from": "disease", "b": 0.01})

func _start_next() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("rhat"):
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(arm["rhat"])))
	elif arm.has("rhat_from"):
		# ⚠ READ OFF THE WIRE, never recomputed in GDScript (convention 13, and the only version that
		# cannot drift when the glass or the gyro moves): `radome_aim_gyro` = R_worst/(1+s).
		var src: Dictionary = _res[str(arm["rhat_from"])]
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(src["aimg"])))
	if arm.has("s"):
		cmds.append(_set_param_cmd(MID, "gyro_scale_err", float(arm["s"])))
	if arm.has("b"):
		cmds.append(_set_param_cmd(MID, "gyro_bias_z", float(arm["b"])))
	_reset_scan_accum()
	_inbox.clear()
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = STEPS * _dt
	_client.send({"type": "step", "n": STEPS})

# Record the arm, and assert the invariants that must hold on EVERY arm.
func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var m := {
		"rms_r": _rms(_r_sum), "rms_q": _rms(_q_sum), "miss": _min_los, "turned": _turned,
		"n": _n_appr, "defl": _n_defl, "aero": _n_aero, "ceil": _max_ceil, "look": _max_look,
		"eps": _max_eps, "worst": _worst, "aimg": _aimg, "eff": _eff, "s": _sval, "b": _bval,
		"inj": _median(_inj_list), "azd": _median(_azd_list), "rez": _median(_rez_list),
		"rez0": _median(_rez0_list),
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	# ⚠ ONLY %.Nf / %d / %s APPEAR IN ANY FORMAT IN THIS FILE (the slice-21/25 recurrence: an unknown
	# specifier makes the WHOLE `%` fail SILENTLY and the line prints as its own format string on a
	# GREEN run). That includes flag/width forms that would be fine in C — do not "tidy" this.
	print(("S31V_ARM   %s  R_hat=%+.4f  s=%+.3f  b=%+.3f  ->  LOOP SEES %+.5f   rms_r=%.5f %s  " +
		   "rms_q=%.5f  n=%d  resid_eff=%+.5f  resid28=%+.5f  inject=%+.6f  aim_gyro=%+.4f  " +
		   "worst=%+.4f  look_max=%.1f  miss=%.3f  cpa=%s  aero_sat=%d  defl_sat=%d") %
		  [tag, _rhat_of(m), m["s"], m["b"], m["eff"], m["rms_r"],
		   "RING " if m["rms_r"] > RING_LINE else "quiet", m["rms_q"], m["n"], m["rez"],
		   m["rez0"], m["inj"], m["aimg"], m["worst"], m["look"], m["miss"],
		   "Y" if m["turned"] else "N", m["aero"], m["defl"]])
	if not (_n_appr > 100):
		return ("arm %s: the [500,3000] m band must contain frames to measure (got %d) — every " +
				"assert on this arm would be vacuous") % [tag, _n_appr]
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was " +
				"still closing at the end, so its miss (%.3f m) is a last closing range and not a " +
				"CPA at all") % [tag, STEPS, _min_los]
	if not (_max_look < LOOK_MAX_DEG):
		return ("arm %s: the small-angle bend model `eps = R(look)*look` must stay inside its " +
				"validity budget — no in-band frame past a %.0f deg look angle, got %.1f. ⚠ This " +
				"is what bounds the BIAS knob's domain: gate 0 measured the budget blowing at " +
				"b = -0.14 and +0.18 rad/s (72%% / 78%% of in-band frames past 30 deg)") % [tag, LOOK_MAX_DEG, _max_look]
	if not (_n_defl == 0 and _max_ceil < CEIL_MAX):
		return ("arm %s: the ISOLATION must hold — defl_sat must NEVER fire on an in-band frame " +
				"(cap #3, got %d/%d) and the aero ceiling must stay << a_max = 3000 (cap #1, got " +
				"%.1f >= %.0f). ⚠ `aero_sat` is EXPECTED on ringing arms and is NOT asserted here " +
				"(got %d): an oscillation drives demand into the ceiling — the ceiling BOUNDS the " +
				"limit cycle rather than causing it (slice 26). Do not copy slice 25's " +
				"aero_sat == 0 globally; it IS asserted on the quiet bias/price arms below") % [tag, _n_defl, _n_appr, _max_ceil, CEIL_MAX, _n_aero]
	if not (_min_los < HIT_MAX):
		return ("arm %s: every arm on this wire still intercepts (< %.0f m — the metric is the " +
				"OSCILLATION, not the miss), got %.3f") % [tag, HIT_MAX, _min_los]
	if not (_max_eps > 1.0e-6):
		return ("arm %s: the radome must actually be REFRACTING (max|radome_eps| > 1e-6 rad), got " +
				"%.9f. The glass never changes across this file — only the BELIEF and its SENSOR " +
				"do") % [tag, _max_eps]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var dis: Dictionary = _res["disease"]
	var cA: Dictionary = _res["cureA"]
	var cB: Dictionary = _res["cureB"]

	# ⭐⭐ PHASE 1 — THE DISEASE, AND IT IS A COMPETENT-LOOKING DESIGN WITH A REALISTIC GYRO.
	print("S31V_DISEASE  R_hat=%+.2f (sharpened past the onset) with s=%+.2f  ->  the loop sees %+.5f  ->  rms_r %.5f in the [500,3000] m band" %
		  [RHAT_SHIP, S_SHIP, float(dis["eff"]), float(dis["rms_r"])])
	if not (float(dis["rms_r"]) > RING_LINE):
		return _fail(("THE DISEASE: the shipped wire must RING (rms r %.5f > %.2f). It is a " +
			"'competent' design — R_hat = %+.2f, aimed just past the onset measured on this very " +
			"wire — carrying a scale-factor error a cheap MEMS gyro really has. If this stops " +
			"ringing the wire has stopped showing the problem") %
			[float(dis["rms_r"]), RING_LINE, RHAT_SHIP])
	# THE MECHANISM AS A NUMBER: the belief the LOOP sees is NOT the belief the designer set.
	if not (absf(float(dis["eff"]) - RHAT_SHIP * (1.0 + S_SHIP)) < EXACT):
		return _fail(("the wire must SHIP the effective belief R_hat*(1+s) as a number (convention " +
			"13 — the client never multiplies physics): expected %+.6f, the wire says %+.6f") %
			[RHAT_SHIP * (1.0 + S_SHIP), float(dis["eff"])])
	if not (float(dis["eff"]) > RHAT_SHIP):
		return _fail(("the scale factor must walk the effective belief toward the RINGING side " +
			"(less negative): R_hat %+.4f -> %+.5f. Only UNDER-reading destabilizes — the " +
			"one-sidedness slices 26 and 30 built on, inherited") % [RHAT_SHIP, float(dis["eff"])])
	# ⚠ AND SLICE 28's KEY IS NOT REDEFINED: the two residuals ship side by side and DISAGREE by
	# exactly the belief rescale. Slice 28's headline is that its residual reads what the HARDWARE
	# implies; folding the gyro into it would make its meaning depend on which keys are present.
	if not (absf((float(dis["rez"]) - float(dis["rez0"])) - (-RHAT_SHIP * S_SHIP)) < 1.0e-6):
		return _fail(("the two residuals must ship SIDE BY SIDE and differ by exactly the belief " +
			"rescale: resid_eff %+.6f - resid28 %+.6f = %+.6f, expected -R_hat*s = %+.6f. Slice " +
			"28's `radome_residual_az` KEEPS ITS MEANING (advisor) — two numbers from the same " +
			"frames that disagree is this arc's own shape") %
			[float(dis["rez"]), float(dis["rez0"]), float(dis["rez"]) - float(dis["rez0"]),
			 -RHAT_SHIP * S_SHIP])

	# ⭐ PHASE 2 — TWO CURES, ONE SLIDER EACH, AND THEY ARE DIFFERENT ENGINEERING.
	print("S31V_CURES    CURE A (gyro s -> 0): rms_r %.5f (%.1fx)   |   CURE B (R_hat -> aim_gyro %+.4f, read off the wire): rms_r %.5f (%.1fx)   [the gyro is UNCHANGED on cure B]" %
		  [float(cA["rms_r"]), float(dis["rms_r"]) / maxf(float(cA["rms_r"]), 1.0e-12),
		   float(dis["aimg"]), float(cB["rms_r"]),
		   float(dis["rms_r"]) / maxf(float(cB["rms_r"]), 1.0e-12)])
	if not (float(cA["rms_r"]) < RING_LINE
			and float(dis["rms_r"]) > CURE_MIN_RATIO * float(cA["rms_r"])):
		return _fail(("CURE A — BUY A BETTER GYRO: dragging gyro_scale_err to 0 must quiet the " +
			"loop (rms r %.5f < %.2f) by more than %.1fx (got %.1fx)") %
			[float(cA["rms_r"]), RING_LINE, CURE_MIN_RATIO,
			 float(dis["rms_r"]) / maxf(float(cA["rms_r"]), 1.0e-12)])
	if not (absf(float(cA["s"])) < EXACT):
		return _fail("CURE A must actually have set the gyro error to 0 (the wire reports s = %+.5f)" % float(cA["s"]))
	if not (float(cB["rms_r"]) < RING_LINE
			and float(dis["rms_r"]) > CURE_MIN_RATIO * float(cB["rms_r"])):
		return _fail(("CURE B — DESIGN MORE CONSERVATIVELY: with the SAME imperfect gyro (s = " +
			"%+.5f), aiming R_hat at the rule's own re-aimed point must quiet the loop (rms r " +
			"%.5f < %.2f) by more than %.1fx (got %.1fx). Two cures for one disease, and they are " +
			"different engineering: buy a better sensor, or stop needing one") %
			[float(cB["s"]), float(cB["rms_r"]), RING_LINE, CURE_MIN_RATIO,
			 float(dis["rms_r"]) / maxf(float(cB["rms_r"]), 1.0e-12)])
	if not (absf(float(cB["s"]) - S_SHIP) < EXACT):
		return _fail(("CURE B must leave the GYRO UNTOUCHED — that is the whole point of it (the " +
			"wire reports s = %+.5f, expected %+.5f)") % [float(cB["s"]), S_SHIP])
	# ⭐⭐ AND THE RULE TIES ITSELF TO SLICE 30's NUMBER: aiming at R_worst/(1+s) makes the LOOP see
	# EXACTLY slice 30's aim point R_worst. That is the design rule as an identity on the wire.
	if not (absf(float(cB["eff"]) - float(cB["worst"])) < 1.0e-6):
		return _fail(("⭐⭐ THE RULE, AS AN IDENTITY ON THE WIRE: aiming R_hat at `radome_aim_gyro` " +
			"= R_worst/(1+s) must make the LOOP see exactly slice 30's aim point — effective " +
			"belief %+.6f against `radome_slope_worst` %+.6f. Slice 30's rule is not replaced, it " +
			"is RE-AIMED for the sensor") % [float(cB["eff"]), float(cB["worst"])])

	# ⭐ PHASE 3 — THE REPARAMETERIZATION, ASSERTED RATHER THAN HIDDEN.
	var eq_d := _pos_max_diff(dis["pos"], _res["equiv"]["pos"])
	print("S31V_EQUIV    (R_hat %+.4f, s %+.2f) vs (R_hat %+.4f, PERFECT gyro): max|dpos| = %.12f m over the flight, rms_r %.5f vs %.5f" %
		  [RHAT_SHIP, S_SHIP, RHAT_EQUIV, eq_d, float(dis["rms_r"]), float(_res["equiv"]["rms_r"])])
	if not (eq_d < EQUIV_ATOL):
		return _fail(("⭐ THE REPARAMETERIZATION: a common-mode scale factor is common-mode on the " +
			"feed-forward product, so (R_hat, s) must fly the SAME MISSILE as (R_hat*(1+s), " +
			"perfect gyro) — max|dpos| %.9f m must be under %.4f. This is the slice's own " +
			"FALSE-FIDELITY finding, asserted rather than hidden: the scale-factor half " +
			"REINTERPRETS a shipped knob and adds no mechanism by itself. ⚠ An `atol`, NEVER " +
			"bit-identity — the two multiplication orders differ in the last ULPs") %
			[eq_d, EQUIV_ATOL])

	# ⭐⭐ PHASE 4 — THE VERDICT FOLLOWS THE EFFECTIVE BELIEF, NOT THE KNOB (convention 9's
	# discriminator: reach the same state from a different direction and check the verdict agrees).
	var tr: Dictionary = _res["third_ring"]
	var tq: Dictionary = _res["third_quiet"]
	print("S31V_SAMEEFF  a THIRD aim point %+.2f: s=%+.3f -> loop sees %+.5f -> rms_r %.5f %s   |   s=%+.3f -> loop sees %+.5f -> rms_r %.5f %s" %
		  [RHAT_THIRD, S_THIRD_RING, float(tr["eff"]), float(tr["rms_r"]),
		   "RING" if float(tr["rms_r"]) > RING_LINE else "quiet",
		   S_THIRD_QUIET, float(tq["eff"]), float(tq["rms_r"]),
		   "RING" if float(tq["rms_r"]) > RING_LINE else "quiet"])
	if not (float(tr["rms_r"]) > RING_LINE and float(tq["rms_r"]) < RING_LINE):
		return _fail(("THE BOUNDARY IS A FUNCTION OF R_hat*(1+s) ALONE: at a THIRD aim point " +
			"(%+.2f) the arm whose effective belief matches the ringing one (%+.5f) must ring " +
			"(%.5f) and the arm clear of the onset (%+.5f) must not (%.5f). Neither `s` alone nor " +
			"`R_hat` alone predicts the verdict — which is why the three knobs are three terms of " +
			"ONE quantity (convention 9)") %
			[RHAT_THIRD, float(tr["eff"]), float(tr["rms_r"]), float(tq["eff"]),
			 float(tq["rms_r"])])
	if not (absf(float(tr["eff"]) - float(dis["eff"])) < 2.0e-3):
		return _fail(("…and the ringing third-aim-point arm must land on essentially the DISEASE's " +
			"own effective belief (%+.5f against %+.5f) — that is what makes it the same state " +
			"reached from a different direction") % [float(tr["eff"]), float(dis["eff"])])

	# ⭐⭐ PHASE 5 — THE OTHER CURRENCY: the bias moves the AIM POINT and never the VERDICT.
	var inj_lo := 0.0
	var inj_hi := 0.0
	for b in BIASES:
		var bm: Dictionary = _res["bias:%d" % int(round(b * 1000.0))]
		print("S31V_BIAS     b=%+.3f rad/s -> injects %+.6f rad/s   rms_r %.5f %s   aero_sat %d/%d   miss %.3f" %
			  [b, float(bm["inj"]), float(bm["rms_r"]),
			   "RING" if float(bm["rms_r"]) > RING_LINE else "quiet", int(bm["aero"]),
			   int(bm["n"]), float(bm["miss"])])
		if not (float(bm["rms_r"]) < RING_LINE):
			return _fail(("⭐⭐ THE OTHER CURRENCY: a BIAS has no residual to move, so on a design " +
				"carrying slice 30's margin it must NOT ring at ANY value in its domain — at " +
				"b = %+.3f rad/s the arm read rms r %.5f. The scale factor lands on the RESIDUAL " +
				"(a stability boundary); the bias lands on the AIM POINT (an additive injection, " +
				"the arc's first)") % [b, float(bm["rms_r"])])
		# ⚠ THE ISOLATION FOR AN AIM-POINT CLAIM (advisor): a large bias drives demand, and slice
		# 19's ceiling would confound it. Asserted HERE, on the quiet arms, and NOT globally.
		if not (int(bm["aero"]) == 0):
			return _fail(("the aim-point claim must not be confounded by slice 19's ceiling: " +
				"`aero_sat` must never fire on a QUIET bias arm (b = %+.3f fired on %d of %d " +
				"in-band frames). ⚠ This is asserted on the bias/price arms ONLY — on a RINGING " +
				"arm aero_sat firing is expected and correct (slice 26)") %
				[b, int(bm["aero"]), int(bm["n"])])
		if b < 0.0:
			inj_lo = float(bm["inj"])
		else:
			inj_hi = float(bm["inj"])
	if not (inj_lo > 0.0 and inj_hi < 0.0):
		return _fail(("…and the injection must be LIVE and SIGNED — `gyro_inject_az` = R_hat*b, so " +
			"with R_hat < 0 a positive bias injects a NEGATIVE rate and vice versa (got %+.6f at " +
			"the negative end and %+.6f at the positive one). A bias that changed nothing would " +
			"make this phase vacuous") % [inj_lo, inj_hi])

	# ⚠ PHASE 6 — THE HONEST NARROWING: a bias CAN flip a MARGINAL design, by moving the LOOK ANGLE.
	var mn: Dictionary = _res["marg_neg"]
	var mp: Dictionary = _res["marg_pos"]
	print("S31V_MARGINAL R_hat=%+.4f (0.005 past the onset), PERFECT gyro: b=%+.3f -> rms_r %.5f %s (look %.1f deg)   |   b=%+.3f -> rms_r %.5f %s (look %.1f deg)" %
		  [RHAT_MARGIN, -B_MARGIN, float(mn["rms_r"]),
		   "RING" if float(mn["rms_r"]) > RING_LINE else "quiet", float(mn["look"]),
		   B_MARGIN, float(mp["rms_r"]),
		   "RING" if float(mp["rms_r"]) > RING_LINE else "quiet", float(mp["look"])])
	if not (float(mn["rms_r"]) > RING_LINE and float(mp["rms_r"]) < RING_LINE):
		return _fail(("⚠ THE HONEST NARROWING: 'a bias never rings' is TOO STRONG. A bias steers " +
			"the missile, which moves the LOOK ANGLE, which on CURVED glass moves the ENGAGEMENT " +
			"residual (slice 28's mechanism arriving through the SENSOR) — the curve's extremum " +
			"is at look = 15 deg and this engagement holds ~13.6, so a NEGATIVE bias walks the " +
			"seeker UP ONTO THE STEEPEST GLASS. On a design only 0.005 past the onset that must " +
			"FLIP THE VERDICT: b = %+.3f gave %.5f (expected RING) and b = %+.3f gave %.5f " +
			"(expected quiet). The precise claim is that a bias has NO STABILITY VERDICT OF ITS " +
			"OWN, and that slice 30's margin buys immunity to BOTH gyro terms") %
			[-B_MARGIN, float(mn["rms_r"]), B_MARGIN, float(mp["rms_r"])])
	# …and the SAME two biases on the CONSERVATIVE design do NOT flip it (the margin, twice measured)
	if not (float(_res["bias:-20"]["rms_r"]) < RING_LINE
			and float(_res["bias:20"]["rms_r"]) < RING_LINE):
		return _fail("…while the SAME bias magnitudes on the conservative aim point must both stay quiet — that contrast IS the margin")

	# ⭐ PHASE 7 — THE PRICE OF CURE B: the claim only the BIAS can produce.
	# ⚠⚠ MEASURED ON THE CLOSED-LOOP CONSEQUENCE, NOT ON `gyro_inject_az`. That key is R_hat*b and
	# NOTHING ELSE, so its ratio between two aim points is |R_hat_B|/|R_hat_A| BY ARITHMETIC (1.29
	# here) — asserting it would be the formula restated, which is convention 11's tautology trap
	# (the first draft of this file did exactly that). `los_azdot_true` is the TRUE LOS azimuth rate:
	# PN nulls the MEASURED rate, so whatever the compensator injects is carried by the true
	# geometry, and the DIFFERENCE between the bias-on and bias-off arms is the aim-point error the
	# bias actually bought. Per frame, with no CPA sampling in it.
	var eA: float = absf(float(_res["pA1"]["azd"]) - float(_res["pA0"]["azd"]))
	var eB: float = absf(float(_res["pB1"]["azd"]) - float(_res["pB0"]["azd"]))
	print("S31V_PRICE    the SAME bias (b=+0.010) on the two cures: CURE A (R_hat %+.4f) aim-point error %+.6f rad/s   |   CURE B (R_hat %+.4f) %+.6f rad/s   (%.2fx)   [both QUIET, aero_sat 0; measured on los_azdot_true, NOT on the R_hat*b formula]" %
		  [_rhat_of(_res["pA1"]), eA, _rhat_of(_res["pB1"]), eB, eB / maxf(eA, 1.0e-12)])
	for t in ["pA1", "pB1"]:
		if not (float(_res[t]["rms_r"]) < RING_LINE and int(_res[t]["aero"]) == 0):
			return _fail(("the PRICE must be read QUIET-TO-QUIET and unconfounded: arm %s read " +
				"rms r %.5f and aero_sat %d/%d") %
				[t, float(_res[t]["rms_r"]), int(_res[t]["aero"]), int(_res[t]["n"])])
	if not (eB > PRICE_MIN_RATIO * eA):
		return _fail(("⭐ TWO CURES FOR ONE DISEASE, AND ONLY ONE OF THEM IS FREE: with the SAME " +
			"bias present, CURE B (design deeper) must cost more than %.1fx the CLOSED-LOOP " +
			"aim-point error of CURE A (buy a better gyro) — got %.2fx (%.6f against %.6f rad/s " +
			"of true LOS azimuth rate). The injection is R_hat*b, so the scalar that buys " +
			"stability buys the sensor's own bias with it — and this is measured on " +
			"`los_azdot_true`, NOT on the R_hat*b formula, whose ratio would be arithmetic. " +
			"⚠ THIS IS THE ONE CLAIM ON THIS WIRE THAT NO OTHER KNOB CAN PRODUCE — the " +
			"scale-factor half is a reparameterization of R_hat (phase EQUIV)") %
			[PRICE_MIN_RATIO, eB / maxf(eA, 1.0e-12), eB, eA])

	# PHASE 8 — REPLAY: held-seed, bit-identical (class 4a; both gyro terms add no draw).
	var rdiff := _pos_max_diff(dis["pos"], _res["replay"]["pos"])
	print("S31V_REPLAY   posdiff_vs_disease = %s m  (must be 0.0 — SEEDED determinism, class 4a: a DETERMINISTIC gyro error adds NO draw; gyro NOISE is deferred on exactly that ground)" % rdiff)
	if not (rdiff == 0.0):
		return _fail(("held-config replay must be BIT-IDENTICAL (posdiff %s m) — a limit cycle is " +
			"deterministic, not chaotic-looking noise, and neither gyro error term may disturb " +
			"the draw topology") % rdiff)
	# THE KNOBS ARE LIVE — the slice-19 NOT-A-DEAD-KNOB tripwire, on both new keys.
	if not (_pos_max_diff(dis["pos"], cA["pos"]) > 0.0):
		return _fail("`gyro_scale_err` must be a LIVE knob — changing it must MOVE the trajectory")
	if not (_pos_max_diff(_res["bias:80"]["pos"], _res["bias:-80"]["pos"]) > 0.0):
		return _fail("`gyro_bias_z` must be a LIVE knob — changing it must MOVE the trajectory")
	return _pass()

# --- scanning -------------------------------------------------------------------------------

func _rhat_of(m: Dictionary) -> float:
	# the AUTHORED belief, recovered from the two numbers the wire ships (eff = R_hat*(1+s))
	return float(m["eff"]) / maxf(1.0 + float(m["s"]), 1.0e-6)

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_turned = false
	_r_sum = 0.0
	_q_sum = 0.0
	_n_appr = 0
	_n_defl = 0
	_n_aero = 0
	_max_ceil = 0.0
	_max_look = 0.0
	_max_eps = 0.0
	_worst = 0.0
	_aimg = 0.0
	_eff = 0.0
	_sval = 0.0
	_bval = 0.0
	_inj_list = []
	_azd_list = []
	_rez_list = []
	_rez0_list = []
	_azr_list = []
	_pos_trace = []

func _drain_scan() -> bool:
	var last_t := -1.0
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue

		var mpos := _missile_pos(f)
		if not mpos.is_empty():
			_pos_trace.append(mpos)
		var tel: Dictionary = f.get("telemetry", {})
		# the two aim points and the effective belief — read OFF THE WIRE on every frame, never
		# recomputed here (convention 13: physics in GDScript is the forbidden move)
		if tel.has(MID + ".radome_slope_worst"):
			_worst = float(tel[MID + ".radome_slope_worst"])
		if tel.has(MID + ".radome_aim_gyro"):
			_aimg = float(tel[MID + ".radome_aim_gyro"])
		if tel.has(MID + ".radome_slope_est_eff"):
			_eff = float(tel[MID + ".radome_slope_est_eff"])
		if tel.has(MID + ".gyro_scale_err"):
			_sval = float(tel[MID + ".gyro_scale_err"])
		if tel.has(MID + ".gyro_bias_z"):
			_bval = float(tel[MID + ".gyro_bias_z"])
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				# THE WINDOW: a fixed RANGE BAND on the closing leg (slice 28/29/30's, inherited
				# with its reasons — a crossing wire's whole-approach rms carries a legitimate
				# front-loaded baseline).
				if r > 500.0 and r < 3000.0:
					_n_appr += 1
					var rr := float(tel.get(MID + ".omega_r", 0.0))
					var qq := float(tel.get(MID + ".omega_q", 0.0))
					_r_sum += rr * rr
					_q_sum += qq * qq
					_max_eps = maxf(_max_eps, absf(float(tel.get(MID + ".radome_eps", 0.0))))
					_max_ceil = maxf(_max_ceil, float(tel.get(MID + ".a_max_aero", 0.0)))
					_max_look = maxf(_max_look, float(tel.get(MID + ".look_angle", 0.0)))
					_inj_list.append(float(tel.get(MID + ".gyro_inject_az", 0.0)))
					_azd_list.append(float(tel.get(MID + ".los_azdot_true", 0.0)))
					_rez_list.append(float(tel.get(MID + ".radome_residual_az_eff", 0.0)))
					_rez0_list.append(float(tel.get(MID + ".radome_residual_az", 0.0)))
					if float(tel.get(MID + ".defl_sat", 0.0)) > 0.5:
						_n_defl += 1
					if float(tel.get(MID + ".aero_sat", 0.0)) > 0.5:
						_n_aero += 1
			_prev_los = r
		last_t = float(f.get("t", -1.0))
	if last_t < 0.0:
		return false
	return last_t >= _t_target - 0.5 * _dt

func _rms(sq: float) -> float:
	return sqrt(sq / maxf(float(_n_appr), 1.0)) if _n_appr > 0 else 0.0

# The MEDIAN of the signed series — the operating-point value. On a ringing arm a mean of absolutes
# is inflated by the cycle's own symmetric excursions (slice 29's verifier failed on exactly that).
func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _missile_pos(f: Dictionary) -> Array:
	for e in f.get("entities", []):
		if str(e.get("id", "")) == MID:
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

# --- helpers --------------------------------------------------------------------------------

func _tag() -> String:
	return str(_arms[_idx]["tag"]) if _idx >= 0 and _idx < _arms.size() else "<handshake>"

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _check_handshake(f: Dictionary) -> String:
	# Slice 31 REUSES slice 26's view AND its button-dropping marker unchanged — it adds no rung, so
	# there is still nothing to cycle (slice-16 Option-P', SEVENTH use: 16, 26, 27, 28, 29, 30, 31).
	if not bool(f.get("airframe_view", false)):
		return "a slice-31 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-31 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-31 handshake must ship radome_view=true — the slice-26 marker that DROPS the shared button, INHERITED unchanged because slice 31 adds no rung to cycle"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-31 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS an azimuth look angle at all. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-31 scenario must HOLD :airframe at six_dof — the radome, its compensator and therefore its gyro are ALL inert without it, and the gate is on the LIVE rung, never on :att_q. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-31 scenario must AUTHOR the autopilot at :alpha (the inner loop the parasitic path closes through), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-31 scenario must hold :guidance at :pn (the N in the loop gain), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-31 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-31 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the ceiling 93% of its approach and cannot isolate anything)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-31 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	# ⭐ THREE KNOBS, and convention 9 is satisfied by a MEASUREMENT (phases EQUIV and SAMEEFF above),
	# not by counting sliders: they are literally the three terms of the product the compensator
	# subtracts, R_hat*((1+s)*omega + b).
	if not keys.has("gyro_scale_err"):
		return "slice-31 handshake must expose the 'gyro_scale_err' slider — CURE A, and the term that lands on the RESIDUAL"
	if not keys.has("gyro_bias_z"):
		return "slice-31 handshake must expose the 'gyro_bias_z' slider — the OTHER currency, and the only term on this wire that no existing knob can reach"
	if not keys.has("radome_slope_est"):
		return "slice-31 handshake must expose 'radome_slope_est' (the belief R_hat) — CURE B, and the rule is a statement about where to put it"
	for k in ["gyro_scale_err", "gyro_bias_z", "radome_slope_est"]:
		if str(keys[k]) != MID:
			return "the '%s' knob must target the interceptor '%s' (got '%s')" % [k, MID, str(keys[k])]
	if keys.size() != 3:
		return "slice-31 must expose EXACTLY THREE knobs (got %d) — the sensor's two error terms and the belief they multiply; every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate").
	if keys.has("cross_speed_mps"):
		return "slice-31 must NOT expose slice 30's ENGAGEMENT axis — this slice's claim is PER-ENGAGEMENT, and stacking the envelope axis on top of it violates convention 9 (one lesson per scenario)"
	if keys.has("radome_ripple"):
		return "slice-31 must NOT expose 'radome_ripple' — it MOVES the rule's own aim point underneath the comparison this slice is making about the SENSOR"
	if keys.has("gyro_bias_y"):
		return "slice-31 must NOT expose 'gyro_bias_y' — it drives the ELEVATION channel, and on a CROSSING wire the loop closes in AZIMUTH (measured ~10x smaller). It stays a supported comp key so the channel split is testable"
	if keys.has("radome_ripple_est") or keys.has("radome_ripple_k_est"):
		return "slice-31 must NOT expose slice 29's SCHEDULE knobs — this wire's compensator is slice 27's SCALAR, and a schedule would confound the lesson AND route the client to slice 29's HUD branch"
	if keys.has("n_pn"):
		return "slice-31 must NOT expose an 'n_pn' knob — it is live-read every tick and moves the LOOP GAIN the lesson is ABOUT (the confounded-lever rule, 26/27/28/29/30)"
	if keys.has("rho"):
		return "slice-31 must NOT expose a 'rho' knob — |R_crit| is proportional to rho, so it too moves the loop gain"
	if keys.has("radome_slope"):
		return "slice-31 must NOT expose 'radome_slope' — R0 is the LEVEL the compensator was characterized against"
	if keys.has("radome_ripple_k"):
		return "slice-31 must NOT expose 'radome_ripple_k' — slice 28 disqualified the glass's k by NON-MONOTONICITY"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-31 must NOT expose an 'alpha_max' knob — it sets the limit cycle's AMPLITUDE, i.e. the one thing the isolation must hold fixed"
	if keys.has("sigma_seek"):
		return "slice-31 must NOT expose 'sigma_seek' — it compresses the contrast beside the lesson (26/27/28/29/30's reasoning, unchanged)"
	if keys.has("speed"):
		return "slice-31 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
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
	var dis: Dictionary = _res["disease"]
	var cA: Dictionary = _res["cureA"]
	var cB: Dictionary = _res["cureB"]
	var eA: float = absf(float(_res["pA1"]["azd"]) - float(_res["pA0"]["azd"]))
	var eB: float = absf(float(_res["pB1"]["azd"]) - float(_res["pB0"]["azd"]))
	print(("S31V OK: slices 27-30 all fed their radome compensator the TRUE body rate and all four " +
		"named that as a §1 approximation. Cash it, and the SAME SENSOR fails in TWO CURRENCIES. " +
		"⭐⭐ THE SHIPPED WIRE IS A COMPETENT-LOOKING DESIGN WITH A REALISTIC GYRO AND IT RINGS: " +
		"R̂ = %+.2f, sharpened to just past the onset measured on this very wire, with a %+.1f%% " +
		"scale-factor error — the loop therefore sees %+.5f, not the %+.2f the designer set, and " +
		"rms omega_r is %.5f rad/s in the [500,3000] m band. ⭐ TWO CURES, ONE SLIDER EACH, AND " +
		"THEY ARE DIFFERENT ENGINEERING: drag the gyro error to 0 and it falls to %.5f (%.1fx), or " +
		"leave the gyro exactly as it is and aim R̂ at the rule's own re-aimed point %+.4f — " +
		"`radome_aim_gyro` = R_worst/(1+s), read OFF THE WIRE — and it falls to %.5f (%.1fx), with " +
		"the loop then seeing %+.5f, which is slice 30's `radome_slope_worst` %+.5f EXACTLY. ⇒ " +
		"SLICE 30's MARGIN IS A GYRO BUDGET: its rule is SUFFICIENT, NEVER TIGHT, and what that " +
		"slack BUYS is tolerance to your own sensor. ⚠⚠ AND THE SCALE-FACTOR HALF IS A " +
		"REPARAMETERIZATION, ASSERTED HERE RATHER THAN HIDDEN: (R̂ %+.4f, s %+.2f) flies the SAME " +
		"MISSILE as (R̂ %+.4f, a PERFECT gyro) to max|dpos| %.9f m — the FALSE-FIDELITY class " +
		"(slice 15's k_delta, slice 19's dead `speed`) caught in the open. What it CANNOT express " +
		"is that the error is MULTIPLICATIVE, which is why the aim point moves to R_worst/(1+s). " +
		"The verdict follows the EFFECTIVE belief and nothing else: at a THIRD aim point %+.2f, " +
		"s = %+.3f lands on %+.5f and RINGS (%.5f) while s = %+.3f lands on %+.5f and stays quiet " +
		"(%.5f). ⭐⭐ THE OTHER CURRENCY: a BIAS has no residual to move — across its whole domain, " +
		"both signs, on the conservative design it NEVER rings (worst %.5f) while injecting a " +
		"constant spurious LOS rate R̂·b that flips sign with it, with aero_sat 0 on every arm so " +
		"no aim-point claim is confounded by slice 19's ceiling. ⚠ BUT 'A BIAS NEVER RINGS' IS TOO " +
		"STRONG AND THE NARROWED VERSION IS ASSERTED: it steers the missile, which moves the LOOK " +
		"ANGLE, which on CURVED glass moves the ENGAGEMENT residual (slice 28's mechanism through " +
		"the SENSOR) — on a design only 0.005 past the onset, b = %+.3f RINGS it (%.5f) while " +
		"b = %+.3f does not (%.5f), and the SAME pair leaves the conservative design untouched. ⇒ " +
		"THE MARGIN IS MEASURED TWICE, IN BOTH CURRENCIES, AND IT IS THE SAME MARGIN. ⭐ FINALLY " +
		"THE CLAIM ONLY THE BIAS CAN PRODUCE — TWO CURES FOR ONE DISEASE AND ONLY ONE OF THEM IS " +
		"FREE: with the same bias present, curing by DESIGNING DEEPER costs %.2fx the CLOSED-LOOP " +
		"aim-point error of curing by BUYING A BETTER GYRO (%.6f against %.6f rad/s of true LOS " +
		"azimuth rate — measured on `los_azdot_true`, never on the R̂·b formula, whose ratio would " +
		"be arithmetic), because the injection is R̂·b and the scalar that buys stability buys the " +
		"sensor's own bias with it. ⚠ NO NEW " +
		"INSTABILITY, NO NEW CAP, NO NEW PLANT, NO NEW LOOP GAIN — the loop is slice 26's; what " +
		"slice 31 adds is an ERROR SOURCE on an existing signal path. ⚠ The isolation is slice " +
		"26's (defl_sat never fires, the ceiling stays under a_max, and aero_sat IS expected on " +
		"ringing arms — %d in-band frames on the shipped one), the look angle never leaves the " +
		"small-angle budget (%.1f deg peak, under %.0f), and replay is bit-identical: class 4a, " +
		"and a DETERMINISTIC gyro error adds no draw (gyro NOISE is deferred on exactly that " +
		"ground).")
		% [RHAT_SHIP, 100.0 * S_SHIP, float(dis["eff"]), RHAT_SHIP, float(dis["rms_r"]),
		   float(cA["rms_r"]), float(dis["rms_r"]) / maxf(float(cA["rms_r"]), 1.0e-12),
		   float(dis["aimg"]), float(cB["rms_r"]),
		   float(dis["rms_r"]) / maxf(float(cB["rms_r"]), 1.0e-12),
		   float(cB["eff"]), float(cB["worst"]),
		   RHAT_SHIP, S_SHIP, RHAT_EQUIV, _pos_max_diff(dis["pos"], _res["equiv"]["pos"]),
		   RHAT_THIRD, S_THIRD_RING, float(_res["third_ring"]["eff"]),
		   float(_res["third_ring"]["rms_r"]), S_THIRD_QUIET, float(_res["third_quiet"]["eff"]),
		   float(_res["third_quiet"]["rms_r"]), _worst_bias_rms(),
		   -B_MARGIN, float(_res["marg_neg"]["rms_r"]), B_MARGIN, float(_res["marg_pos"]["rms_r"]),
		   eB / maxf(eA, 1.0e-12), eB, eA,
		   int(dis["aero"]), float(dis["look"]), LOOK_MAX_DEG])
	_teardown()
	quit(0)
	return true

func _worst_bias_rms() -> float:
	var m := 0.0
	for b in BIASES:
		m = maxf(m, float(_res["bias:%d" % int(round(b * 1000.0))]["rms_r"]))
	return m

func _fail(msg: String, code := 1) -> bool:
	push_error("S31V FAIL: " + msg)
	print("S31V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
