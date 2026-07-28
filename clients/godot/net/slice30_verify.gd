extends SceneTree
# Headless slice-30 gate-3 verifier (the slice26/27/28/29_verify analog). Drives the REAL Julia
# server through SimClient.gd and asserts slice-30's "the envelope, and the one-sided constraint"
# done-criteria as machine checks.
#
# THE LESSON: slice 26 measured — and never used — the fact that the radome constraint is ONE-SIDED.
# Only a NEGATIVE residual closes the parasitic loop; a positive one merely de-tunes the seeker. If
# that is true, then a plain SCALAR R_hat set at or below the most negative slope the glass reaches
# ANYWHERE is stable in EVERY engagement — not because it is accurate anywhere, but because it errs
# in the harmless direction everywhere. You do not need a schedule, you do not need to know which
# engagement you will fly, and you do not need slice 29's index at all. What you need is a BOUND.
# ⇒ GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY, and slice 27's "know your slope to within
# 0.38/(N*rho)" is revealed as a TWO-SIDED reading of a ONE-SIDED constraint.
#
# ⭐⭐ SO THE HEADLINE IS A RING COUNT OVER AN ENVELOPE, NOT A RATIO ON ONE ARM. Slices 26–29 each
# flew ONE engagement, so "the residual" could be spoken of as a number. Here the crossing speed is a
# SLIDER (`cross_speed_mps`, the gate-1 ConstantVelocity seam), the ENVELOPE is the worst cell over
# seven of them, and a compensator PASSES stability iff it rings at ZERO of the seven. The
# boresight-characterized scalar slice 28 shipped rings at 6/7. The worst-case scalar — the number
# the core ships as `radome_slope_worst` — rings at 0/7.
# ⚠ A COUNT HAS NO TOLERANCE TO ABSORB NOISE, which is why gate 2 re-ran all 14 arms at a second
# seed (6/7 vs 6/7, 0/7 vs 0/7; every cell moved < 0.2%). The verdict line is the same 0.30 the whole
# slice has used, and the measured margins are printed with every count.
#
# ⭐ AND THE BOUND IS NOT FREE — THE SECOND HALF IS THE PRICE. Over-compensation cuts the effective
# navigation ratio, so the scalar has TWO bounds: STABILITY FROM BELOW, ACCURACY FROM ABOVE. They
# close on each other as the glass worsens, which is the classical fixed-gain-versus-gain-scheduling
# argument made quantitative on a measured plant.
#
# ⚠⚠ THE PRICE IS ASSERTED ON `omega_ratio`, NOT ON THE MISS, AND THAT IS NOT A PREFERENCE (advisor).
# The plan's price column (0.213 / 1.075 / 4.150 m) was measured by a Julia probe computing a
# PER-TICK CPA. This file reads FRAMES: at `emit_every = 16` and Vc ~ 690 m/s the frame grid is
# ~11 m, so a sub-metre price difference is entirely inside the sampling error
# ([[ewsim-missile-verifier-sampling]]: a HIT samples COARSELY — slice 27's verifier ate exactly this
# defect, comparing two frame-sampled CPAs of 3.305 and 5.269 m). `omega_ratio` is per-frame
# telemetry with no CPA sampling in it. The miss is asserted ONE-SIDED everywhere ("still
# intercepts") EXCEPT at the DOMAIN corner, where the gap (21.6 m against 4.2 m) is twice the frame
# grid and survives it — and that arm is flown at vy = 0 for exactly that reason.
#
# ⚠⚠ AND `omega_ratio` IS A DE-TUNE MEASURE ONLY ON A QUIET ARM (gate-0 P4c): on a ringing arm it
# reads 1.5–16 — that is the limit cycle corrupting the reported LOS rate, not a de-tune (slice 26:
# it is a DIAGNOSTIC, never the mechanism). So every price arm asserts `rms r` QUIET *before* its
# omega_ratio is read. Implemented naively this phase becomes a ring-vs-quiet comparison and the
# slice would state that rule and violate it in the same file.
#
# ⚠ THE RULE IS SUFFICIENT, NEVER TIGHT. On this glass the envelope is already 0/7 at R_hat = -0.28,
# above the rule's -0.33, because the loop needs the residual to reach the ONSET (~ -0.055) and not
# merely to be negative. The bracket is MEASURED here rather than rounded: R_hat = -0.24 still rings
# decisively on the envelope's last-ringing cell (vy = 200). ⚠ The actual boundary sits between
# -0.26 (0.3168 — 1.06x the verdict line, MARGINAL) and -0.27 (0/7), and a marginal cell is NOT
# asserted: slice 26's post-commit rule is that a published number is a measured one with margin.
#
# ⚠ THE METRIC, THE WINDOW AND THE CHANNEL ARE SLICE 28/29's: rms r (YAW) in the RANGE BAND
# [500, 3000] m. ⚠ QUOTE THE WINDOW WITH EVERY NUMBER. ⚠ rms, NEVER the peak.
# ⚠ AND THE WINDOW MATTERS MORE HERE THAN ANYWHERE IN THE ARC: the crossing speed is a slider, so
# ToF genuinely varies arm to arm (9.4 s at vy = 0 to 18.3 s at the domain corner — the FIRST wire in
# this arc where it does). A fixed range band is what makes those arms comparable at all, every arm
# asserts it reached CPA before its miss is quoted, and STEPS is sized off the SLOWEST arm.
#
# THE ARMS (31 flights, driven as reset -> set_param -> step, so every knob is applied at t = 0):
#   • BORESIGHT  x7 — the shipped R_hat = -0.03 across the envelope. Expect 6/7 RING. The DEAD POINT
#                     (vy = 0) is asserted here: no lead, no curve, residual EXACTLY ~0.
#   • REPLAY     x1 — the default arm re-flown: the 3-D pos trace is BIT-IDENTICAL. ⚠ SEEDED
#                     determinism, not "RNG-free" (class 4a: 2 randn/tick, and a velocity pin adds
#                     none).
#   • WORST-CASE x7 — R_hat set to the `radome_slope_worst` READ OFF THE WIRE (never recomputed in
#                     GDScript — convention 13, and the version that cannot drift when A moves).
#                     Expect 0/7. ⇒ THE HEADLINE.
#   • TIGHT      x8 — 0/7 at -0.28 (above the rule) plus one still-ringing arm at -0.24.
#   • PRICE      x6 — three glass depths, each with R_hat at ITS OWN wire-read aim point (a 64-tick
#                     AIM flight reads the key, then the full arm flies it). QUIET-TO-QUIET.
#   • DOMAIN     x2 — the A-floor x R_hat-floor corner against its own aim point, at vy = 0.
#   • ISOLATION — inside every full arm: `defl_sat` never fires in the band (cap #3), the aero
#                 ceiling stays far under a_max (cap #1), and the small-angle bend model stays inside
#                 its 30 deg budget. ⚠ Do NOT copy slice 25's `aero_sat == 0`: it is IMPOSSIBLE on a
#                 ringing arm (an oscillation drives demand into the ceiling) and asserting it would
#                 fail on a correct build.
#
# Run (server must be listening on slice30_envelope.yaml first):
#   godot --headless --path clients/godot --script res://net/slice30_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 1800.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor (the radome knobs live here)
const TID := "tgt1"               # the crossing target (the ENGAGEMENT knob lives here)

# 20 s: the SLOWEST arm measured is the domain corner at vy = 400 (18.30 s to CPA), and every arm
# must turn the corner or its "miss" is only a last closing range (advisor).
const STEPS := 20000
const AIM_STEPS := 64             # 4 frames — enough to read `radome_slope_worst` off the wire

# The envelope. ⚠ HARD-CODED, and 170 is deliberately absent: gate 2 published the count over
# exactly these seven, and 170 is the largest quiet cell under the worst-case scalar (it would move
# the published margin).
const VYS := [0.0, 80.0, 130.0, 200.0, 260.0, 320.0, 400.0]

# The authored wire, mirrored so the asserts can name it.
const R0_GLASS   := -0.03         # the boresight slope R0 (authored, not a knob)
const A_GLASS    := -0.15         # the ripple amplitude A (the shipped glass; a knob)
const RHAT_SHIP  := -0.03         # the shipped BELIEF: characterized at BORESIGHT, and it rings
const RHAT_ABOVE := -0.28         # ABOVE the rule's -0.33 — and already 0/7 (sufficient, not tight)
const RHAT_STILL := -0.24         # …and still ringing here: the bracket, measured
const A_PRICE := [-0.10, -0.15, -0.20]
const A_FLOOR := -0.20            # the A knob's declared floor
const RHAT_FLOOR := -0.55         # the R_hat knob's declared floor (the de-tune face)

# Bounds — pinned against probe 12/13/14 on THIS wire at THIS seed, with margin.
const RING_LINE := 0.30           # the verdict line the whole slice has used (gate 0 / gate 2)
                                  # measured: smallest RING 0.8546 (2.85x above), largest quiet
                                  # under a passing scalar 0.1447 (2.07x below)
const HIT_MAX := 60.0             # every arm intercepts; the corner de-tunes to ~21.6 m
const CEIL_MAX := 1000.0          # a_max_aero << a_max 3000 => cap #1 out of reach
const LOOK_MAX_DEG := 30.0        # the small-angle bend model's validity budget, ON THE WIRE
const DEAD_RESID := 1.0e-4        # the vy = 0 dead point: measured -0.000008
const PRICE_MIN_DROP := 1.5       # omega_ratio must fall decisively across the glass depths
                                  # (measured 0.7782 -> 0.4053, 1.92x)
const CORNER_MISS_MIN := 15.0     # measured 21.567 m at the corner (vy = 0)
const CORNER_AIM_MAX := 8.0       # …against 4.150 m at its own aim point. The 17 m gap is 1.5x the
                                  # ~11 m frame grid, which is the only reason a MISS is assertable
                                  # here and nowhere else in this file.
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0

var _arms: Array = []             # the flight plan, built at handshake
var _idx := -1                    # index of the arm in flight
var _res: Dictionary = {}         # tag -> measured Dictionary

# per-arm accumulators (window = closing frames with 500 < los_range < 3000)
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false              # did the arm actually reach CPA? (ToF varies with vy)
var _max_y := 0.0
var _r_sum := 0.0                 # sum of omega_r^2 — THE metric (yaw)
var _q_sum := 0.0                 # sum of omega_q^2 — the channel-split companion (pitch)
var _n_appr := 0
var _n_defl := 0
var _n_aero := 0
var _max_ceil := 0.0
var _max_look := 0.0
var _max_eps := 0.0
var _orat_list: Array = []        # omega_ratio — the DE-TUNE measure (quiet arms only)
var _rez_list: Array = []         # radome_residual_az — the ENGAGEMENT residual
var _worst := 0.0                 # radome_slope_worst, read OFF THE WIRE (never recomputed here)
var _cross := 0.0                 # cross_speed_mps, the engagement label
var _pos_trace: Array = []

func _initialize() -> void:
	print("S30V_INIT godot=", Engine.get_version_info().string)
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
	# 1) THE DISEASE: the boresight-characterized scalar, across the envelope.
	for vy in VYS:
		_arms.append({"tag": "bore:%d" % int(vy), "cross": vy})
	# 2) REPLAY of the default arm — bit-identical, held seed (class 4a).
	_arms.append({"tag": "replay", "cross": 200.0})
	# 3) ⭐⭐ THE HEADLINE: the same envelope with R_hat at the wire's own worst-case slope.
	#    `rhat_from` reads `radome_slope_worst` off a PREVIOUS arm's telemetry — the client never
	#    computes R0+2A (convention 13, and the only version that cannot drift when A moves).
	for vy in VYS:
		_arms.append({"tag": "worst:%d" % int(vy), "cross": vy, "rhat_from": "bore:200"})
	# 4) SUFFICIENT, NEVER TIGHT: quiet already above the rule, and a measured still-ringing bracket.
	for vy in VYS:
		_arms.append({"tag": "above:%d" % int(vy), "cross": vy, "rhat": RHAT_ABOVE})
	_arms.append({"tag": "still:200", "cross": 200.0, "rhat": RHAT_STILL})
	# 5) THE PRICE: three glass depths, each aimed at ITS OWN wire-read worst-case slope. The AIM
	#    flight is 64 ticks — it exists only to read the key, and it carries no in-band frames.
	for a in A_PRICE:
		var tg := "aim:%d" % int(round(a * 100.0))
		_arms.append({"tag": tg, "ripple": a, "aim": true})
		_arms.append({"tag": "price:%d" % int(round(a * 100.0)), "ripple": a,
					  "cross": 200.0, "rhat_from": tg})
	# 6) THE DOMAIN CORNER, at vy = 0 — where the de-tune miss is LARGEST (least lead) and therefore
	#    the one place a frame-sampled CPA can carry the claim.
	_arms.append({"tag": "corner_aim", "ripple": A_FLOOR, "cross": 0.0,
				  "rhat_from": "aim:-20"})
	_arms.append({"tag": "corner", "ripple": A_FLOOR, "cross": 0.0, "rhat": RHAT_FLOOR})

func _start_next() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("cross"):
		cmds.append(_set_param_cmd(TID, "cross_speed_mps", float(arm["cross"])))
	if arm.has("ripple"):
		cmds.append(_set_param_cmd(MID, "radome_ripple", float(arm["ripple"])))
	if arm.has("rhat"):
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(arm["rhat"])))
	elif arm.has("rhat_from"):
		var src: Dictionary = _res[str(arm["rhat_from"])]
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(src["worst"])))
	var n: int = AIM_STEPS if bool(arm.get("aim", false)) else STEPS
	_reset_scan_accum()
	_inbox.clear()
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt
	_client.send({"type": "step", "n": n})

# Record the arm, and assert the invariants that must hold on EVERY full arm.
func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var is_aim := bool(arm.get("aim", false))
	var m := {
		"rms_r": _rms(_r_sum), "rms_q": _rms(_q_sum), "miss": _min_los, "turned": _turned,
		"n": _n_appr, "defl": _n_defl, "aero": _n_aero, "ceil": _max_ceil, "look": _max_look,
		"eps": _max_eps, "orat": _median(_orat_list), "rez": _median(_rez_list),
		"worst": _worst, "cross": _cross, "max_y": _max_y, "pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	if is_aim:
		# An AIM flight exists only to read the design rule's target off the wire.
		print("S30V_AIM   %s  A=%+.2f  radome_slope_worst(off the wire)=%+.5f" %
			  [tag, float(arm.get("ripple", A_GLASS)), _worst])
		if not (_worst < 0.0):
			return ("the AIM flight must read a NEGATIVE `radome_slope_worst` off the wire (got " +
					"%+.6f). It is min(R0, R0+2A) — the most negative slope the glass reaches " +
					"ANYWHERE — and the whole design rule is to aim AT it" % _worst)
		return ""
	# ⚠ ONLY %.Nf / %d / %s APPEAR IN ANY FORMAT IN THIS FILE (the slice-21/25 recurrence: an unknown
	# specifier makes the WHOLE `%` fail SILENTLY and the line prints as its own format string on a
	# GREEN run). That includes flag/width forms that would be fine in C — do not "tidy" this.
	print(("S30V_ARM   %s cross=%.0f m/s  rms_r=%.5f %s  rms_q=%.5f  n=%d  " +
		   "omega_ratio=%.4f  resid_az=%+.5f  worst=%+.4f  look_max=%.1f  miss=%.3f  " +
		   "cpa=%s  max|y|=%.0f  aero_sat=%d  defl_sat=%d  ceil_max=%.1f") %
		  [tag, m["cross"], m["rms_r"], "RING " if m["rms_r"] > RING_LINE else "quiet",
		   m["rms_q"], m["n"], m["orat"], m["rez"], m["worst"], m["look"], m["miss"],
		   "Y" if m["turned"] else "N", m["max_y"], m["aero"], m["defl"], m["ceil"]])
	if not (_n_appr > 100):
		return ("arm %s: the [500,3000] m band must contain frames to measure (got %d) — every " +
				"assert on this arm would be vacuous") % [tag, _n_appr]
	# ⚠ ToF VARIES WITH THE CROSSING SPEED (9.4 s to 18.3 s across this file), so an arm that ran out
	# of steps still closing would report its LAST RANGE as a "miss". Sizing STEPS off the slowest
	# arm is not enough on its own — the turn is asserted (advisor).
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was " +
				"still closing at the end, so its miss (%.3f m) is a last closing range and not a " +
				"CPA at all. ⚠ ToF varies with the crossing speed on this wire (the first in the " +
				"arc where it does)") % [tag, STEPS, _min_los]
	if not (_max_look < LOOK_MAX_DEG):
		return ("arm %s: the small-angle bend model `eps = R(look)*look` must stay inside its " +
				"validity budget — no in-band frame past a %.0f deg look angle, got %.1f. ⚠ This " +
				"is the objection slice 27 used to REJECT R = -0.30, inherited, and it is what " +
				"bounds the crossing-speed knob's CEILING") % [tag, LOOK_MAX_DEG, _max_look]
	if not (_n_defl == 0 and _max_ceil < CEIL_MAX):
		return ("arm %s: the ISOLATION must hold — defl_sat must NEVER fire on an in-band frame " +
				"(cap #3, got %d/%d) and the aero ceiling must stay << a_max = 3000 (cap #1, got " +
				"%.1f >= %.0f). ⚠ `aero_sat` is EXPECTED to fire on ringing arms and is NOT " +
				"asserted (got %d here): an oscillation drives demand, and demand hits the " +
				"ceiling — the ceiling BOUNDS the limit cycle rather than causing it (slice 26). " +
				"Do not copy slice 25's aero_sat == 0") % [tag, _n_defl, _n_appr, _max_ceil,
															CEIL_MAX, _n_aero]
	if not (_min_los < HIT_MAX):
		return ("arm %s: every arm on this wire still intercepts (< %.0f m — the metric is the " +
				"OSCILLATION, not the miss), got %.3f") % [tag, HIT_MAX, _min_los]
	if not (_max_eps > 1.0e-6):
		return ("arm %s: the radome must actually be REFRACTING (max|radome_eps| > 1e-6 rad), got " +
				"%.9f. The glass never changes across this file — only the belief and the " +
				"engagement do") % [tag, _max_eps]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	# ⭐⭐ PHASE 1/2 — THE HEADLINE, IN THE ENVELOPE'S OWN UNITS: a ring COUNT, not a ratio.
	var n_bore := _ring_count("bore:")
	var n_worst := _ring_count("worst:")
	var n_above := _ring_count("above:")
	var worst_wire: float = float(_res["bore:200"]["worst"])
	print("S30V_ENVELOPE boresight R_hat=%+.2f rings %d/%d   |   worst-case R_hat=%+.4f (READ OFF THE WIRE) rings %d/%d   |   above-the-rule R_hat=%+.2f rings %d/%d" %
		  [RHAT_SHIP, n_bore, VYS.size(), worst_wire, n_worst, VYS.size(), RHAT_ABOVE, n_above, VYS.size()])
	if not (n_bore == VYS.size() - 1):
		return _fail(("THE DISEASE: the BORESIGHT-characterized scalar (R_hat = %+.2f, whose " +
			"HARDWARE residual against R0 is exactly 0.000) must ring on %d of the %d envelope " +
			"cells — every one except the dead point at vy = 0. Got %d. If this drops, the wire " +
			"has stopped showing the problem the rule solves") %
			[RHAT_SHIP, VYS.size() - 1, VYS.size(), n_bore])
	if not (float(_res["bore:0"]["rms_r"]) < RING_LINE):
		return _fail(("the one QUIET boresight cell must be the DEAD POINT at vy = 0 (rms r %.5f " +
			"must be < %.2f) — with no crossing there is no lead, the seeker sits on boresight, and " +
			"R(look) = R0 exactly. That is the floor of the crossing-speed knob and the reason the " +
			"axis is real") % [float(_res["bore:0"]["rms_r"]), RING_LINE])
	# ⭐ THE DEAD POINT AS A RESIDUAL, not merely as a quiet arm.
	var dead_rez: float = absf(float(_res["bore:0"]["rez"]))
	if not (dead_rez < DEAD_RESID):
		return _fail(("the DEAD POINT must be dead EXACTLY: at vy = 0 the engagement residual " +
			"R(look_az) - R_hat must be ~0 (|median| < %.6f), got %.6f. This is what makes the " +
			"crossing-speed knob's FLOOR a measured endpoint rather than an inferred one (slice " +
			"26's post-commit rule)") % [DEAD_RESID, dead_rez])
	# ⭐⭐ THE RESULT.
	if not (n_worst == 0):
		return _fail(("⭐⭐ THE HEADLINE: a SCALAR aimed at the glass's worst-case slope (%+.4f, " +
			"read off the wire as `radome_slope_worst`) must ring at ZERO of the %d envelope " +
			"cells, got %d. Because only a NEGATIVE residual closes slice 26's loop, erring in " +
			"the harmless direction EVERYWHERE buys stability in EVERY engagement — no schedule, " +
			"no knowledge of which engagement will be flown, no index. GAIN SCHEDULING BUYS " +
			"PERFORMANCE, NOT STABILITY") % [worst_wire, VYS.size(), n_worst])
	# The COUNT is the claim, so its MARGINS are published beside it (a count has no tolerance).
	var min_ring := 1.0e30
	var max_quiet := 0.0
	for vy in VYS:
		var rb: float = float(_res["bore:%d" % int(vy)]["rms_r"])
		if rb > RING_LINE:
			min_ring = minf(min_ring, rb)
		max_quiet = maxf(max_quiet, float(_res["worst:%d" % int(vy)]["rms_r"]))
	print("S30V_MARGINS  smallest RING %.5f (%.2fx above the %.2f line)   largest quiet under the worst-case scalar %.5f (%.2fx below it)" %
		  [min_ring, min_ring / RING_LINE, RING_LINE, max_quiet, RING_LINE / max_quiet])
	if not (min_ring > 2.0 * RING_LINE and max_quiet < 0.5 * RING_LINE):
		return _fail(("the COUNT must not rest on marginal cells: the smallest RING (%.5f) must " +
			"clear the %.2f line by 2x and the largest quiet (%.5f) must sit 2x under it. A ratio " +
			"has tolerance to absorb noise; a COUNT does not — one cell flipping changes the " +
			"published number (gate 2's second-seed check exists for this reason)") %
			[min_ring, RING_LINE, max_quiet])
	# ⭐ THE GLASS DID NOT CHANGE — only the BELIEF did. The engagement residual FLIPS SIGN, which is
	# the one-sidedness stated as a number rather than as prose.
	var bore_rez: float = float(_res["bore:200"]["rez"])
	var worst_rez: float = float(_res["worst:200"]["rez"])
	if not (bore_rez < 0.0 and worst_rez > 0.0):
		return _fail(("THE ONE-SIDEDNESS, AS A NUMBER: on the same glass at the same crossing " +
			"speed the boresight scalar leaves a NEGATIVE engagement residual (%+.5f — it rings) " +
			"and the worst-case scalar an over-compensated POSITIVE one (%+.5f — it de-tunes). " +
			"Only the negative side closes the loop; that asymmetry IS the design rule") %
			[bore_rez, worst_rez])

	# ⭐ PHASE — SUFFICIENT, NEVER TIGHT (the bracket, measured).
	var still_rms: float = float(_res["still:200"]["rms_r"])
	print("S30V_TIGHT    R_hat=%+.2f rings %d/%d (the rule aims at %+.4f)   |   R_hat=%+.2f still RINGS on the envelope's last-ringing cell (vy=200): rms_r %.5f" %
		  [RHAT_ABOVE, n_above, VYS.size(), worst_wire, RHAT_STILL, still_rms])
	if not (n_above == 0):
		return _fail(("SUFFICIENT, NEVER TIGHT: the envelope must already be QUIET at R_hat = " +
			"%+.2f, which is ABOVE the rule's %+.4f — got %d/%d ringing. The loop needs the " +
			"residual to reach the ONSET (~ -0.055), not merely to be negative, so the rule " +
			"carries built-in margin: a BOUND TO BE EXCEEDED, not an estimate to be matched") %
			[RHAT_ABOVE, worst_wire, n_above, VYS.size()])
	if not (still_rms > 2.0 * RING_LINE):
		return _fail(("…and the margin must be BRACKETED, not rounded: at R_hat = %+.2f the " +
			"envelope's last-ringing cell must STILL ring decisively (rms r > %.2f), got %.5f. " +
			"Without this the 'sufficient' claim is one-sided and -0.33 could be read as a " +
			"measured threshold — which it is not") % [RHAT_STILL, 2.0 * RING_LINE, still_rms])

	# ⭐⭐ PHASE — THE PRICE. ⚠ QUIET-TO-QUIET, and on `omega_ratio`, never on a frame-sampled CPA.
	var prices: Array = []
	for a in A_PRICE:
		var pm: Dictionary = _res["price:%d" % int(round(a * 100.0))]
		prices.append(pm)
		if not (float(pm["rms_r"]) < RING_LINE):
			return _fail(("THE PRICE MUST BE READ QUIET-TO-QUIET: at A = %+.2f, aimed at its own " +
				"worst-case slope %+.4f, the arm must be QUIET (rms r %.5f < %.2f) before its " +
				"omega_ratio is quoted. On a RINGING arm omega_ratio reads 1.5-16 — that is the " +
				"limit cycle corrupting the reported LOS rate, NOT a de-tune (slice 26: it is a " +
				"DIAGNOSTIC, never the mechanism), and comparing it to a quiet arm's would make " +
				"this phase the ring-vs-quiet comparison the slice forbids") %
				[a, float(pm["worst"]), float(pm["rms_r"]), RING_LINE])
	var or_shallow: float = float(prices[0]["orat"])
	var or_deep: float = float(prices[2]["orat"])
	print("S30V_PRICE    A=%+.2f aim %+.4f omega_ratio %.4f   ->   A=%+.2f aim %+.4f omega_ratio %.4f   ->   A=%+.2f aim %+.4f omega_ratio %.4f   (%.2fx, ALL QUIET)" %
		  [A_PRICE[0], float(prices[0]["worst"]), or_shallow,
		   A_PRICE[1], float(prices[1]["worst"]), float(prices[1]["orat"]),
		   A_PRICE[2], float(prices[2]["worst"]), or_deep, or_shallow / maxf(or_deep, 1.0e-12)])
	if not (or_shallow > float(prices[1]["orat"]) and float(prices[1]["orat"]) > or_deep):
		return _fail(("THE PRICE MUST GROW MONOTONICALLY WITH THE GLASS: omega_ratio must FALL as " +
			"the aim point deepens, got %.4f / %.4f / %.4f at A = %+.2f / %+.2f / %+.2f. The " +
			"SAME stability guarantee costs more navigation ratio on worse glass — that is the " +
			"accuracy bound closing on the stability bound") %
			[or_shallow, float(prices[1]["orat"]), or_deep, A_PRICE[0], A_PRICE[1], A_PRICE[2]])
	if not (or_shallow > PRICE_MIN_DROP * or_deep):
		return _fail(("…and the price must be DECISIVE, not a nudge: omega_ratio must fall by more " +
			"than %.1fx across the glass depths, got %.2fx (%.4f -> %.4f)") %
			[PRICE_MIN_DROP, or_shallow / maxf(or_deep, 1.0e-12), or_shallow, or_deep])
	# …and the aim point MOVED with the glass — the reason the HUD shows it live.
	if not (float(prices[0]["worst"]) > float(prices[1]["worst"])
			and float(prices[1]["worst"]) > float(prices[2]["worst"])):
		return _fail(("the aim point itself must MOVE with the glass (%+.4f / %+.4f / %+.4f at " +
			"A = %+.2f / %+.2f / %+.2f) — which is exactly why the HUD must show it LIVE beside " +
			"R_hat: a student who deepens the glass silently invalidates the R_hat they set") %
			[float(prices[0]["worst"]), float(prices[1]["worst"]), float(prices[2]["worst"]),
			 A_PRICE[0], A_PRICE[1], A_PRICE[2]])

	# ⭐ PHASE — THE DOMAIN CORNER: the DE-TUNE FACE, and the ONE place a miss carries a claim.
	var c_miss: float = float(_res["corner"]["miss"])
	var a_miss: float = float(_res["corner_aim"]["miss"])
	var c_or: float = float(_res["corner"]["orat"])
	var a_or: float = float(_res["corner_aim"]["orat"])
	print("S30V_DOMAIN   A=%+.2f (knob floor), vy=0: aim point R_hat=%+.4f -> miss %.3f m, omega_ratio %.4f   |   OVER-COMPENSATED to the R_hat floor %+.2f -> miss %.3f m (%.1fx), omega_ratio %.4f (%.2fx)" %
		  [A_FLOOR, float(_res["corner_aim"]["worst"]), a_miss, a_or, RHAT_FLOOR, c_miss,
		   c_miss / maxf(a_miss, 1.0e-12), c_or, a_or / maxf(c_or, 1.0e-12)])
	if not (float(_res["corner"]["rms_r"]) < RING_LINE):
		return _fail(("the DOMAIN CORNER must still be QUIET (rms r %.5f < %.2f) — over-compensation " +
			"never rings, it only de-tunes, and that ONE-SIDEDNESS is the whole rule") %
			[float(_res["corner"]["rms_r"]), RING_LINE])
	if not (c_or < a_or):
		return _fail(("the de-tune must DEEPEN when R_hat is dragged past the aim point: " +
			"omega_ratio %.4f at the floor must be under %.4f at the aim point") % [c_or, a_or])
	# ⚠ THE ONE MISS ASSERT IN THIS FILE, AND IT IS FLOWN AT vy = 0 FOR THAT REASON: the de-tune miss
	# is largest where the lead is smallest, and only there does the gap (17 m) clear the ~11 m frame
	# grid ([[ewsim-missile-verifier-sampling]]). At vy = 200 the same pair is 10.0 vs 0.6 m — inside
	# the sampling error, and asserting it would measure the emit rate.
	if not (c_miss > CORNER_MISS_MIN and a_miss < CORNER_AIM_MAX):
		return _fail(("THE ACCURACY BOUND, AS A MISS: at the corner the over-compensated arm must " +
			"miss by more than %.0f m (got %.3f) while its own aim point stays under %.0f m (got " +
			"%.3f). ⚠ This is the ONLY miss comparison in this file, and it is flown at vy = 0 " +
			"because the de-tune miss is largest where the lead is smallest — the %.0f m gap is " +
			"the only one in the slice that clears the ~11 m frame grid") %
			[CORNER_MISS_MIN, c_miss, CORNER_AIM_MAX, a_miss, c_miss - a_miss])

	# PHASE — REPLAY: held-seed, bit-identical (class 4a; a velocity pin adds no draw).
	var rdiff := _pos_max_diff(_res["bore:200"]["pos"], _res["replay"]["pos"])
	print("S30V_REPLAY   posdiff_vs_bore:200 = %s m  (must be 0.0 — SEEDED determinism, class 4a: the crossing-speed pin adds NO draw)" % rdiff)
	if not (rdiff == 0.0):
		return _fail(("held-config replay must be BIT-IDENTICAL (posdiff %s m) — a limit cycle is " +
			"deterministic, not chaotic-looking noise, and the envelope axis must not have " +
			"disturbed the draw topology") % rdiff)
	if not (float(_res["replay"]["miss"]) == float(_res["bore:200"]["miss"])):
		return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" %
			[float(_res["replay"]["miss"]), float(_res["bore:200"]["miss"])])
	# THE KNOB IS LIVE — the slice-19 NOT-A-DEAD-KNOB tripwire, on the NEW key.
	if not (_pos_max_diff(_res["bore:200"]["pos"], _res["bore:0"]["pos"]) > 0.0):
		return _fail("`cross_speed_mps` must be a LIVE knob — changing it must MOVE the trajectory")
	if not (absf(float(_res["bore:0"]["cross"])) < EXACT
			and absf(float(_res["bore:200"]["cross"]) - 200.0) < EXACT):
		return _fail(("the wire must LABEL the engagement it is flying: `cross_speed_mps` read %.3f " +
			"and %.3f on the vy = 0 and vy = 200 arms") %
			[float(_res["bore:0"]["cross"]), float(_res["bore:200"]["cross"])])
	return _pass()

func _ring_count(prefix: String) -> int:
	var n := 0
	for vy in VYS:
		if float(_res[prefix + str(int(vy))]["rms_r"]) > RING_LINE:
			n += 1
	return n

# --- scanning -------------------------------------------------------------------------------

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_turned = false
	_max_y = 0.0
	_r_sum = 0.0
	_q_sum = 0.0
	_n_appr = 0
	_n_defl = 0
	_n_aero = 0
	_max_ceil = 0.0
	_max_look = 0.0
	_max_eps = 0.0
	_orat_list = []
	_rez_list = []
	_worst = 0.0
	_cross = 0.0
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
			_max_y = maxf(_max_y, absf(mpos[1]))
		var tel: Dictionary = f.get("telemetry", {})
		# the design rule's aim point and the engagement label — read off the wire on EVERY frame,
		# never recomputed here (convention 13: physics in GDScript is the forbidden move)
		if tel.has(MID + ".radome_slope_worst"):
			_worst = float(tel[MID + ".radome_slope_worst"])
		if tel.has(MID + ".cross_speed_mps"):
			_cross = float(tel[MID + ".cross_speed_mps"])
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				# THE WINDOW: a fixed RANGE BAND on the closing leg (slice 28/29's, inherited with
				# its reasons — and load-bearing here, where ToF varies arm to arm).
				if r > 500.0 and r < 3000.0:
					_n_appr += 1
					var rr := float(tel.get(MID + ".omega_r", 0.0))
					var qq := float(tel.get(MID + ".omega_q", 0.0))
					_r_sum += rr * rr
					_q_sum += qq * qq
					_max_eps = maxf(_max_eps, absf(float(tel.get(MID + ".radome_eps", 0.0))))
					_max_ceil = maxf(_max_ceil, float(tel.get(MID + ".a_max_aero", 0.0)))
					_max_look = maxf(_max_look, float(tel.get(MID + ".look_angle", 0.0)))
					_orat_list.append(float(tel.get(MID + ".omega_ratio", 0.0)))
					_rez_list.append(float(tel.get(MID + ".radome_residual_az", 0.0)))
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
# is inflated by the cycle's own symmetric excursions (slice 29's verifier failed on exactly that,
# 1.6x against the median's 3.7x).
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
	# Slice 30 REUSES slice 26's view AND its button-dropping marker unchanged — it adds no rung, so
	# there is still nothing to cycle (slice-16 Option-P', SIXTH use: 16, 26, 27, 28, 29, 30).
	if not bool(f.get("airframe_view", false)):
		return "a slice-30 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-30 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-30 handshake must ship radome_view=true — the slice-26 marker that DROPS the shared button, INHERITED unchanged because slice 30 adds no rung to cycle"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-30 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS an azimuth look angle at all. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-30 scenario must HOLD :airframe at six_dof — the radome and its compensator are both INERT without it (no attitude to look through), and the gate is on the LIVE rung, never on :att_q. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-30 scenario must AUTHOR the autopilot at :alpha (the inner loop the parasitic path closes through), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-30 scenario must hold :guidance at :pn (the N in the loop gain), got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-30 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-30 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the ceiling 93% of its approach and cannot isolate anything)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-30 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	# ⭐ THREE KNOBS, and convention 9 is satisfied by a MEASUREMENT (gate 0's 245-arm grid: of the
	# 196 arms whose in-flight residual never went supercritical, 196 are quiet and NONE rings), not
	# by counting sliders. They are three terms of ONE quantity — the engagement residual the core
	# ships as `radome_residual_az`.
	if not keys.has("cross_speed_mps"):
		return "slice-30 handshake must expose the 'cross_speed_mps' slider — the ENGAGEMENT is this slice's new axis, and it is the whole reason the claim could not ship inside slice 29"
	if str(keys["cross_speed_mps"]) != TID:
		return "the 'cross_speed_mps' knob must target the TARGET entity '%s' (got '%s') — it pins the ConstantVelocity mover's vel_y" % [TID, str(keys["cross_speed_mps"])]
	if not keys.has("radome_ripple"):
		return "slice-30 handshake must expose 'radome_ripple' (the glass depth A) — it is what MOVES the rule's own aim point R0+2A"
	if not keys.has("radome_slope_est"):
		return "slice-30 handshake must expose 'radome_slope_est' (the scalar belief R̂) — the rule is a statement about where to put it"
	if keys.size() != 3:
		return "slice-30 must expose EXACTLY THREE knobs (got %d) — the engagement, the glass and the belief, i.e. the three terms of the one residual that decides; every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate").
	if keys.has("radome_ripple_est") or keys.has("radome_ripple_k_est"):
		return "slice-30 must NOT expose slice 29's SCHEDULE knobs (radome_ripple_est / radome_ripple_k_est) — this wire's compensator is slice 27's SCALAR, deliberately: the whole claim is about what a SCALAR can guarantee, and a schedule beside it would confound the lesson AND route the client to slice 29's HUD branch"
	if keys.has("n_pn"):
		return "slice-30 must NOT expose an 'n_pn' knob — it is live-read every tick and moves the LOOP GAIN the lesson is ABOUT (the confounded-lever rule, 26/27/28/29)"
	if keys.has("rho"):
		return "slice-30 must NOT expose a 'rho' knob — |R_crit| is proportional to rho, so it too moves the loop gain"
	if keys.has("radome_slope"):
		return "slice-30 must NOT expose 'radome_slope' — R0 is the LEVEL the compensator was characterized against, and a student who can move both the level and the belief has no comparison left"
	if keys.has("radome_ripple_k"):
		return "slice-30 must NOT expose 'radome_ripple_k' — slice 28 disqualified the glass's k by NON-MONOTONICITY"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-30 must NOT expose an 'alpha_max' knob — it sets the limit cycle's AMPLITUDE, i.e. the one thing the isolation must hold fixed"
	if keys.has("sigma_seek"):
		return "slice-30 must NOT expose 'sigma_seek' — it compresses the contrast beside the lesson (26/27/28/29's reasoning, unchanged)"
	if keys.has("speed"):
		return "slice-30 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
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
	var worst_wire: float = float(_res["bore:200"]["worst"])
	var p0: Dictionary = _res["price:%d" % int(round(A_PRICE[0] * 100.0))]
	var p2: Dictionary = _res["price:%d" % int(round(A_PRICE[2] * 100.0))]
	print(("S30V OK: slice 26 measured — and never used — the fact that the radome constraint is " +
		"ONE-SIDED: only a NEGATIVE residual closes the parasitic loop, a positive one merely " +
		"de-tunes. ⭐⭐ SO THE LESSON IS A RING COUNT OVER AN ENVELOPE. Slices 26-29 each flew ONE " +
		"engagement; here the crossing speed is a slider, the envelope is %d of them, and the " +
		"boresight-characterized scalar slice 28 shipped (R̂ = %+.2f, whose HARDWARE residual is " +
		"exactly 0.000) RINGS AT %d OF %d — quiet only at the dead point vy = 0, where there is no " +
		"lead at all and the engagement residual is %+.6f. Aim the SAME KIND of scalar at the " +
		"glass's worst-case slope instead — %+.4f, read off the wire as `radome_slope_worst`, never " +
		"recomputed in the client — and it rings at %d OF %d, at every glass depth measured. The " +
		"smallest ring clears the %.2f verdict line by %.2fx and the largest quiet sits %.2fx under " +
		"it, so the COUNT does not rest on a marginal cell. ⇒ STABILITY IS UNCONDITIONALLY " +
		"PURCHASABLE WITH A SCALAR — it is not accurate anywhere, it errs in the harmless direction " +
		"everywhere — SO GAIN SCHEDULING BUYS PERFORMANCE, NOT STABILITY, and slice 27's 'know your " +
		"slope to within 0.38/(N*rho)' is a TWO-SIDED reading of a ONE-SIDED constraint. ⭐ THE " +
		"ONE-SIDEDNESS AS A NUMBER: at vy = 200 the same glass leaves the boresight scalar a " +
		"NEGATIVE engagement residual (%+.5f, rms omega_r %.5f rad/s in the [500,3000] m band) and " +
		"the worst-case scalar an over-compensated POSITIVE one (%+.5f, rms %.5f). ⚠ SUFFICIENT, " +
		"NEVER TIGHT: the envelope is ALREADY 0/%d at R̂ = %+.2f, above the rule's %+.4f, because " +
		"the loop needs the residual to reach the ONSET and not merely to be negative — and the " +
		"margin is BRACKETED, not rounded: at %+.2f the last-ringing cell still rings at %.5f. " +
		"⭐⭐ AND THE BOUND IS NOT FREE — THE SECOND HALF IS THE PRICE, and it is read QUIET-TO-QUIET " +
		"on omega_ratio (a frame-sampled CPA cannot resolve sub-metre differences on an ~11 m grid): " +
		"the SAME guarantee costs omega_ratio %.4f at A = %+.2f, %.4f at %+.2f and %.4f at %+.2f — " +
		"%.2fx of navigation ratio — because the aim point itself moves down with the glass " +
		"(%+.4f -> %+.4f), which is why the HUD shows it LIVE beside R̂. ⭐ Drag R̂ past that aim " +
		"point to its floor %+.2f and the de-tune face is on show: still QUIET (over-compensation " +
		"never rings), but the miss opens from %.3f m to %.3f m at vy = 0. ⇒ THE SCALAR HAS TWO " +
		"BOUNDS — STABILITY FROM BELOW, ACCURACY FROM ABOVE — AND THEY CLOSE ON EACH OTHER AS THE " +
		"GLASS WORSENS. ⚠ NO NEW INSTABILITY, NO NEW CAP, NO NEW GAIN: the loop is slice 26's, and " +
		"what slice 30 adds is an AXIS. ⚠ The isolation is slice 26's (aero_sat DOES fire on the " +
		"ringing arms — %d in-band frames on the shipped one — while defl_sat never fires and the " +
		"ceiling stays far under a_max), and the look angle never leaves the small-angle budget " +
		"(%.1f deg peak, under %.0f). Class 4a: a velocity pin adds NO draw, and replay is " +
		"bit-identical.")
		% [VYS.size(), RHAT_SHIP, _ring_count("bore:"), VYS.size(),
		   float(_res["bore:0"]["rez"]), worst_wire, _ring_count("worst:"), VYS.size(),
		   RING_LINE, _min_ring() / RING_LINE, RING_LINE / _max_quiet(),
		   float(_res["bore:200"]["rez"]), float(_res["bore:200"]["rms_r"]),
		   float(_res["worst:200"]["rez"]), float(_res["worst:200"]["rms_r"]),
		   VYS.size(), RHAT_ABOVE, worst_wire, RHAT_STILL, float(_res["still:200"]["rms_r"]),
		   float(p0["orat"]), A_PRICE[0],
		   float(_res["price:%d" % int(round(A_PRICE[1] * 100.0))]["orat"]), A_PRICE[1],
		   float(p2["orat"]), A_PRICE[2], float(p0["orat"]) / maxf(float(p2["orat"]), 1.0e-12),
		   float(p0["worst"]), float(p2["worst"]),
		   RHAT_FLOOR, float(_res["corner_aim"]["miss"]), float(_res["corner"]["miss"]),
		   int(_res["bore:200"]["aero"]), float(_res["bore:200"]["look"]), LOOK_MAX_DEG])
	_teardown()
	quit(0)
	return true

func _min_ring() -> float:
	var m := 1.0e30
	for vy in VYS:
		var x: float = float(_res["bore:%d" % int(vy)]["rms_r"])
		if x > RING_LINE:
			m = minf(m, x)
	return m

func _max_quiet() -> float:
	var m := 0.0
	for vy in VYS:
		m = maxf(m, float(_res["worst:%d" % int(vy)]["rms_r"]))
	return m

func _fail(msg: String, code := 1) -> bool:
	push_error("S30V FAIL: " + msg)
	print("S30V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
