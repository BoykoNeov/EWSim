extends SceneTree
# Headless slice-32 gate-3 verifier (the slice26..31_verify analog). Drives the REAL Julia server
# through SimClient.gd and asserts slice-32's "the seeker's field of view" done-criteria as machine
# checks.
#
# THE LESSON: slices 26-31 made the LOOK ANGLE the central quantity of the whole radome family, and
# then each of them bounded its knob domains by that angle reaching 30 deg — declared every time as a
# §1 MODEL-VALIDITY caveat. A REAL seeker makes the same angle a PHYSICAL STOP: past its field of
# view there is no measurement at all. So the caveat and the hardware coincide, and the arc's FIRST
# SENSOR-SIDE CAP lands (every previous cap in this project is airframe or actuator).
#
# ⭐⭐ AND WHAT IT CAPS IS THE ENGAGEMENT, NOT THE ACCURACY. A crossing target must be LED; the lead is
# a closed-form property of the collision triangle (V_m*sin(lambda) = V_t*sin(theta), shipped live as
# `lead_angle_deg`); and the missile must hold that lead ALL THE WAY IN. If the lead exceeds the
# window the seeker loses the target WHILE THE LEAD IS STILL BUILDING, the alpha-beta tracker coasts
# on a rate that was right for a smaller lead, and the geometry runs away monotonically.
#
#     THE LESSON, IN ONE SENTENCE. The FOV a seeker needs is not a seeker number — it is the
#     ENGAGEMENT's own lead angle, so a field of view does not cost you accuracy, it costs you the
#     ENVELOPE: the set of targets you may engage at all.
#
# ⭐ TWO CURES, ONE SLIDER EACH — AND THE ASYMMETRY IS THE PAYLOAD:
#     seeker_fov_deg  25 -> 30    WIDEN THE SEEKER      (free: you keep the engagement)
#     cross_speed_mps 400 -> 320  DECLINE THE CROSSING  (not free: you gave the target up)
#
# ⚠⚠ THE SIGNATURE IS SLICE 23's AND SLICE 25's AND THE MECHANISM IS NEITHER (the copy-paste
# false-claim trap, 3rd occurrence in this arc). 23 THREW the out-of-plane command away; 25 NEVER
# FORMED it; here it was formed and flown and then the SENSOR STOPPED SUPPLYING IT MID-FLIGHT. The
# discriminating tooth is `max|y|`, NOT the miss: the fov = 0 degenerate reaches 23/25's
# `max|y| = 0.0` signature by a FOURTH route (a seeker that never locks reports no LOS rate, so PN
# commands nothing out of plane), while the SHIPPED broken arm turns hard out of plane first.
#
# ⚠ THE METRIC IS THE MISS, AND THAT INVERTS 28-31's. `rms r` must NOT be inherited here, because
# losing the measurement CUTS the parasitic feed — on a ringing wire a tight FOV would LOWER rms r
# while OPENING the miss, and the slice would be written backwards. Here the miss opens ~10^4x, and a
# BIG miss samples FAITHFULLY ([[ewsim-missile-verifier-sampling]] cuts the right way for once; the
# HIT arms are the ones that sample coarsely, so every hit assert here is ONE-SIDED).
#
# ⚠ ASSERT THE VERDICT AND THE OUT-OF-WINDOW FRACTION; QUOTE THE MISS. The miss MAGNITUDE is not a
# reliable ordering inside the broken region (it is a ballistic-scatter number — this run measures
# 2487 m at fov 20 against 1505 m at fov 25 on the same crossing, and the ordering is not the claim).
# The VERDICT is sharp and it is what the envelope is made of.
#
# ⚠ TWO WINDOWS, BOTH LOAD-BEARING, AND A FIRST DRAFT OF THIS FILE'S OWN PROBE GOT BOTH WRONG:
#   * every look-angle / out-of-window number is RANGE-GATED at r > 200 m — a quiet arm leaves the
#     window for one or two ticks at r = 0.1-0.6 m as the LOS unit vector swings through a large
#     angle in the last millisecond before impact (gate 2 measured it; `%.1f` had hidden it as
#     "0.0 %"), and
#   * the statistics stop at CPA. Past it the LOS flips through 180 deg as the missile flies away and
#     the range climbs back above the gate, so a whole-run fraction reads ~4-5 % on arms that are
#     EXACTLY 0.000 % on the approach.
#
# ⚠ ISOLATION: `aero_sat` is 0 in the r in [500, 3000] m band in EVERY arm, broken or not ⇒ a
# POINTING miss, NOT the arc's ceiling miss (19-24). The FLAG is asserted as a number; the compare is
# never hand-rolled (the sets nest — slice 19). ⚠ The whole-approach figure is ~6.5 % and it is
# ~6.5 % in the REFERENCE arm too: a launch transient, the front-loaded baseline 28/31 measured in
# `rms r` arriving here in a different quantity.
#
# ⚠⚠ `lead_angle_deg` MAY NOT ANCHOR A LOOK-ANGLE CLAIM, and this file makes none. The INDEPENDENT
# recompute that pins look ~ lead lives in `test_missile.jl` (gate 2, an `acos` of the LOS dot v_t
# then `sin` — a different algorithm), because using the core's own kernel as its own oracle is the
# self-calibrated round-trip this project names as a trap. What IS asserted here is the ENVELOPE
# relation between two quantities that come from DIFFERENT code paths — `collision_lead_angle` (the
# engagement) against `seeker_in_fov`'s verdict on `boresight_angle` (the hardware) — namely that the
# track survives exactly when the lead fits inside the window, reached from BOTH directions.
#
# THE ARMS (11 flights, driven as reset -> set_param -> step, so every knob is applied at t = 0):
#   • OPEN      x1 — the shipped wire (fov 25 deg, crossing 400 m/s). Expect the track to BREAK.
#   • REPLAY    x1 — the same arm re-flown: bit-identical (class 4a — the window gates the VALUE,
#                    never the DRAW, so both rungs draw their 2 randn/tick).
#   • CURE A    x1 — fov -> 30. Expect the track to hold, 0.000 % out of window.
#   • CURE B    x1 — crossing -> 320. Expect the same, by moving the OTHER term of the comparison.
#   • WIDE      x1 — fov -> 180: the knob-vs-rung identity, asserted BIT-IDENTICAL to cure A.
#   • DOMAIN MAX x1 — fov -> 40, the declared ceiling: also bit-identical ⇒ the ceiling is INERT, and
#                    that is the MEASURED reason the domain stops at 40 rather than at 180.
#   • NEVER     x1 — fov -> 0: the defined never-locked degenerate. `max|y|` EXACTLY 0.0.
#   • ENVELOPE  x3 — (20, 260) holds / (20, 320) breaks / (25, 320) holds, which with OPEN (25, 400)
#                    and CURE A (30, 400) is the envelope flipping from BOTH directions.
#   • e20_400   x1 — a third broken cell, quoted for the miss magnitude and asserted only on verdict.
#
# Run (server must be listening on slice32_fov.yaml first):
#   godot --headless --path clients/godot --script res://net/slice32_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 1800.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor (the FOV knob lives here)
const TID := "tgt1"               # the target (the crossing-speed knob lives here)

# 16.0 s: the SLOWEST arm measured on this wire is 15.313 s to CPA (cure A / the reference), and
# every arm must turn the corner or its "miss" is only a last closing range (slice 30's discipline,
# and ToF varies 5.3-15.4 s here — a wider spread than any earlier wire in this arc).
# ⚠⚠ AND IT MUST BE A MULTIPLE OF `emit_every` (16) — convention 14, the trap slice 31 lost an hour
# to. The server emits every 16th tick, so a STEPS that is not a multiple makes the last frame land
# BELOW `STEPS*dt` and `_drain_scan` waits forever, silently, with no output at all. 16000 = 16*1000.
const STEPS := 16000

# The authored wire, mirrored so the asserts can name it.
const FOV_SHIP := 25.0            # the shipped window — THE SHOWCASE OPENS ON THE DISEASE
const VY_SHIP := 400.0            # the shipped crossing: the top of slice 30's envelope
const FOV_CURE := 30.0            # CURE A — widen the seeker (free)
const VY_CURE := 320.0            # CURE B — decline the crossing (not free)
const FOV_MAX := 40.0             # the declared domain ceiling
const FOV_WIDE := 180.0           # the knob-vs-rung identity value (⚠ NOT "the whole sphere" — the
                                  # angle-space radius hypot(az, el) has supremum ~201.246 deg; this
                                  # is an EMPIRICAL statement about what THIS engagement reaches, and
                                  # `test_frames.jl` pins both facts)

# Bounds — pinned against a probe of THIS YAML wire at THIS seed, with margin. ⚠ Those probe numbers
# are PER-TICK; this file measures FRAMES on an ~16 ms grid, so the HIT asserts are ONE-SIDED and the
# BREAK asserts are the tight ones.
const BREAK_MISS_MIN := 500.0     # measured 1504.7 m (open), 2487.3 (fov 20), 1076.0 (20 @ 320)
const HIT_MAX := 30.0             # per-tick 0.07-0.20 m; ~11 m of frame grid sits under this
const OUT_BREAK_MIN := 50.0       # measured 67.9 % (open), 77.8 %, 71.1 % — per-tick, r > 200 m
const MAXY_BREAK_MIN := 5000.0    # measured 8129 m: it WAS formed and flown (the 23/25 tooth)
const LOOK_MAX_DEG := 30.0        # the small-angle bend budget — asserted on the QUIET arms only
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

# per-arm accumulators
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0                  # closing frames with r > 200 m — the look-angle window
var _n_out := 0                   # …of which the seeker had NO measurement
var _max_look := 0.0
var _n_band := 0                  # closing frames with 500 < r < 3000 — the isolation window
var _n_aero := 0
var _n_defl := 0
var _max_ceil := 0.0
var _lead_list: Array = []        # lead_angle_deg in the isolation band (the ENGAGEMENT's demand)
var _fov_seen := 0.0              # seeker_fov_deg, as the wire reports it
var _max_y := 0.0
var _t_break := -1.0
var _r_break := -1.0
var _pos_trace: Array = []       # the WHOLE run — replay determinism and the live-knob tripwire
var _pos_appr: Array = []        # the CLOSING LEG ONLY — the inertness claim (see below)

func _initialize() -> void:
	print("S32V_INIT godot=", Engine.get_version_info().string)
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
	# 1) THE DISEASE — the shipped wire, untouched.
	_arms.append({"tag": "open"})
	# 2) REPLAY — bit-identical, held seed (class 4a: the window gates the VALUE, never the DRAW).
	_arms.append({"tag": "replay"})
	# 3) CURE A — widen the seeker. The FREE cure: the engagement is kept.
	_arms.append({"tag": "cureA", "fov": FOV_CURE})
	# 4) CURE B — slow the crossing. NOT free: this is declining the target.
	_arms.append({"tag": "cureB", "vy": VY_CURE})
	# 5) THE KNOB-VS-RUNG IDENTITY — an in-domain slider value that flies the key-absent trajectory.
	_arms.append({"tag": "wide", "fov": FOV_WIDE})
	# 6) THE DOMAIN CEILING, MEASURED RATHER THAN INFERRED (slice 26's post-commit discipline).
	_arms.append({"tag": "fov40", "fov": FOV_MAX})
	# 7) THE DEGENERATE — fov = 0 is a DEFINED never-locked state, not a crash path.
	_arms.append({"tag": "never", "fov": 0.0})
	# 8) THE ENVELOPE, FLIPPED FROM BOTH DIRECTIONS.
	_arms.append({"tag": "e20_260", "fov": 20.0, "vy": 260.0})
	_arms.append({"tag": "e20_320", "fov": 20.0, "vy": VY_CURE})
	_arms.append({"tag": "e25_320", "fov": FOV_SHIP, "vy": VY_CURE})
	_arms.append({"tag": "e20_400", "fov": 20.0})

func _start_next() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("fov"):
		cmds.append(_set_param_cmd(MID, "seeker_fov_deg", float(arm["fov"])))
	if arm.has("vy"):
		cmds.append(_set_param_cmd(TID, "cross_speed_mps", float(arm["vy"])))
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
	var out_pc: float = 100.0 * float(_n_out) / maxf(float(_n_gate), 1.0)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		"look": _max_look, "band": _n_band, "aero": _n_aero, "defl": _n_defl,
		"ceil": _max_ceil, "lead": _median(_lead_list), "fov": _fov_seen, "maxy": _max_y,
		"tbrk": _t_break, "rbrk": _r_break, "pos": _pos_trace.duplicate(true),
		"appr": _pos_appr.duplicate(true),
	}
	_res[tag] = m
	# ⚠ ONLY %.Nf / %d / %s APPEAR IN ANY FORMAT IN THIS FILE (the slice-21/25 recurrence: an unknown
	# specifier makes the WHOLE `%` fail SILENTLY and the line prints as its own format string on a
	# GREEN run). That includes flag/width forms that would be fine in C — do not "tidy" this.
	print(("S32V_ARM   %s  fov=%.1f  ->  %s   miss=%.3f  out=%.3f%% of %d gated frames  " +
		   "look_max=%.2f  lead=%.2f  max|y|=%.1f  break t=%.3f r=%.1f  cpa=%s  aero_sat=%d/%d  " +
		   "defl_sat=%d  ceil_max=%.1f") %
		  [tag, m["fov"], "TRACK BROKEN" if out_pc > 0.0 else "held", m["miss"], out_pc, m["gate"],
		   m["look"], m["lead"], m["maxy"], m["tbrk"], m["rbrk"], "Y" if m["turned"] else "N",
		   m["aero"], m["band"], m["defl"], m["ceil"]])
	if not (_n_gate > 100):
		return ("arm %s: the r > 200 m window must contain frames to measure (got %d) — every " +
				"look-angle and out-of-window assert on this arm would be vacuous") % [tag, _n_gate]
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was " +
				"still closing at the end, so its miss (%.3f m) is a last closing range and not a " +
				"CPA at all. ⚠ ToF varies 5.3-15.4 s across this file, the widest spread in the " +
				"arc, so STEPS is sized off the SLOWEST arm") % [tag, STEPS, _min_los]
	# ⚠ THE ISOLATION, AND IT IS THE WHOLE REASON THIS IS A POINTING MISS AND NOT THE ARC's SEVENTH
	# CEILING MISS. Asserted as the FLAG's own count, never a hand-rolled compare (slice 19: the sets
	# nest, because `aero_sat` keys off the perpendicular-v projection while `a_demand` is a
	# magnitude). ⚠ Skipped only where the band is EMPTY — the `fov = 0` arm never gets within
	# 4786 m of the target, which is itself the point of that arm.
	if _n_band > 0 and not (_n_aero == 0 and _n_defl == 0):
		return ("arm %s: the miss must be a POINTING miss, not the aero-ceiling miss slices 19-24 " +
				"ship — `aero_sat` fired on %d of %d in-band frames and `defl_sat` on %d. The " +
				"missile has every bit of the authority it needs and no idea where to point it; if " +
				"this ever fires, the wire has started showing slice 19's lesson instead") % [tag, _n_aero, _n_band, _n_defl]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var op: Dictionary = _res["open"]
	var cA: Dictionary = _res["cureA"]
	var cB: Dictionary = _res["cureB"]

	# ⭐⭐ PHASE 1 — THE DISEASE, AND IT IS A MISS OUT OF A MISSILE WITH FULL AUTHORITY.
	print("S32V_OPEN     fov %.1f deg against a %.0f m/s crossing: the track BREAKS at t = %.3f s / r = %.1f m, the seeker is out of its window %.3f %% of the approach, and the miss is %.3f m — with aero_sat %d of %d in-band frames" %
		  [FOV_SHIP, VY_SHIP, float(op["tbrk"]), float(op["rbrk"]), float(op["out"]),
		   float(op["miss"]), int(op["aero"]), int(op["band"])])
	if not (float(op["miss"]) > BREAK_MISS_MIN):
		return _fail(("THE DISEASE: the shipped wire must MISS (%.3f m > %.0f). A %.0f deg seeker " +
			"cannot fly a %.0f m/s crossing, because the lead this collision triangle demands is " +
			"bigger than the window — and the loss happens WHILE THE LEAD IS STILL BUILDING, so the " +
			"coasting tracker's frozen rate is one that was right for a smaller lead") %
			[float(op["miss"]), BREAK_MISS_MIN, FOV_SHIP, VY_SHIP])
	if not (float(op["out"]) > OUT_BREAK_MIN):
		return _fail(("…and it must be the WINDOW that does it: the seeker must have no measurement " +
			"for more than %.0f %% of the approach (got %.3f %%, range-gated at r > 200 m). This is " +
			"the discriminator, not the miss — a miss alone could come from anywhere") %
			[OUT_BREAK_MIN, float(op["out"])])
	# ⭐⭐ THE TOOTH THAT SEPARATES THIS FROM SLICES 23 AND 25 (the copy-paste false-claim trap).
	if not (float(op["maxy"]) > MAXY_BREAK_MIN):
		return _fail(("⭐⭐ THE MECHANISM IS NEITHER 23's NOR 25's, AND max|y| IS WHAT SAYS SO: slice " +
			"23 THREW the out-of-plane command away and slice 25 NEVER FORMED it, both leaving " +
			"max|y| = 0.0 EXACTLY. Here it WAS formed and flown — the missile turns hard out of " +
			"plane and only THEN loses the target — so max|y| must be large (%.1f m > %.0f). The " +
			"miss magnitudes are ~2000 m in all three; only this number tells them apart") %
			[float(op["maxy"]), MAXY_BREAK_MIN])
	if not (float(op["tbrk"]) > 0.0 and float(op["rbrk"]) > 2000.0):
		return _fail(("…and the break must happen EARLY, at long range, while the lead is still " +
			"building (t = %.3f s, r = %.1f m). A loss in the endgame is survivable — the corollary " +
			"in `test_missile.jl` measures a ringing arm losing lock for 0.4 %% of its approach and " +
			"still hitting. What is terminal is losing it on the way in") %
			[float(op["tbrk"]), float(op["rbrk"])])

	# ⭐ PHASE 2 — TWO CURES, ONE SLIDER EACH, AND THEY ARE NOT THE SAME ENGINEERING.
	print("S32V_CURES    CURE A (widen the seeker to %.0f deg): miss %.3f m, %.3f %% out, look_max %.2f deg   |   CURE B (slow the crossing to %.0f m/s): miss %.3f m, %.3f %% out, look_max %.2f deg   [cure A KEEPS the engagement; cure B DECLINES it]" %
		  [FOV_CURE, float(cA["miss"]), float(cA["out"]), float(cA["look"]),
		   VY_CURE, float(cB["miss"]), float(cB["out"]), float(cB["look"])])
	for t in ["cureA", "cureB"]:
		var c: Dictionary = _res[t]
		if not (float(c["out"]) == 0.0):
			return _fail(("CURE %s: with the lead inside the window the seeker must NEVER lose the " +
				"target — %.3f %% of %d range-gated frames were out. ⚠ EXACTLY 0.000 is the right " +
				"bar and it needs the r > 200 m gate to be true: ungated, a healthy intercept leaves " +
				"the window for one or two ticks at r = 0.1-0.6 m as the LOS swings through a large " +
				"angle in the last millisecond, and `%%.1f` reported that as 0.0 (gate 2)") %
				[t, float(c["out"]), int(c["gate"])])
		if not (float(c["miss"]) < HIT_MAX):
			return _fail(("CURE %s must INTERCEPT (%.3f m < %.0f). ⚠ ONE-SIDED ON PURPOSE: a HIT " +
				"samples COARSELY on this ~16 ms frame grid (~11 m between samples at closing " +
				"speed), so the per-tick 0.1-0.2 m cannot be reproduced here and is not asserted " +
				"[[ewsim-missile-verifier-sampling]]") % [t, float(c["miss"]), HIT_MAX])
		if not (float(c["look"]) < LOOK_MAX_DEG):
			return _fail(("CURE %s: the small-angle bend model's validity budget must hold on a " +
				"TRACKING arm — no range-gated frame past a %.0f deg look angle, got %.2f. ⚠ This " +
				"is asserted on the QUIET arms ONLY: on a BROKEN arm the look angle running to " +
				"90-100 deg is the runaway itself, not a modelling violation") %
				[t, LOOK_MAX_DEG, float(c["look"])])
	var ratio_a: float = float(op["miss"]) / maxf(float(cA["miss"]), 1.0e-9)
	var ratio_b: float = float(op["miss"]) / maxf(float(cB["miss"]), 1.0e-9)
	if not (ratio_a > 20.0 and ratio_b > 20.0):
		return _fail(("both cures must move the miss by orders of magnitude (%.1fx and %.1fx). ⚠ The " +
			"RATIOS are frame-sampled and therefore UNDERSTATED: the numerator samples faithfully " +
			"(a big miss) and the denominator coarsely (a hit)") % [ratio_a, ratio_b])

	# ⭐ PHASE 3 — KNOB, NOT RUNG, AND THE DOMAIN CEILING IS MEASURED RATHER THAN INFERRED.
	# ⚠⚠ ON THE APPROACH, AND THE RESTRICTION IS A MEASUREMENT, NOT A CONVENIENCE. Compared over the
	# WHOLE run these three arms differ by 35.7 m — because PAST CPA the target is BEHIND the missile,
	# the LOS swings through 150-180 deg, and a 30 or 40 deg window correctly drops it while a 180 deg
	# one does not. That is the post-CPA LOS flip gate 0's P4 already named (it saw 3.5e-9 m between
	# 45/60/90 there), and it is the window doing its job on a target nobody is chasing any more. The
	# claim being made is about the ENGAGEMENT, so it is measured on the closing leg — where it is
	# EXACT, and where the two other arms are exact against each other over the whole run too.
	var d_wide := _pos_max_diff(cA["appr"], _res["wide"]["appr"])
	var d_40 := _pos_max_diff(cA["appr"], _res["fov40"]["appr"])
	print("S32V_INERT    once the window contains the lead it is INERT ON THE APPROACH: fov %.0f vs %.0f vs %.0f fly max|dpos| = %s m and %s m apart over the closing leg (%d frames) — an in-domain slider value that reproduces the key-absent trajectory is a KNOB, not a rung (atmosphere.jl's discriminator), and it is the MEASURED reason the domain stops at %.0f. ⚠ Over the WHOLE run the 180 deg arm separates by %s m: past CPA the target is BEHIND the missile and a narrow window correctly drops it (the post-CPA LOS flip, not the approach)" %
		  [FOV_CURE, FOV_MAX, FOV_WIDE, d_40, d_wide, int(cA["appr"].size()), FOV_MAX,
		   _pos_max_diff(cA["pos"], _res["wide"]["pos"])])
	if not (d_wide == 0.0 and d_40 == 0.0):
		return _fail(("⭐ THE KNOB-VS-RUNG DISCRIMINATOR, MEASURED: with the lead inside the window " +
			"the FOV must be BIT-IDENTICAL ON THE CLOSING LEG across %.0f / %.0f / %.0f deg (got " +
			"max|dpos| %s m and %s m). That is what makes `seeker_fov_deg` a KNOB with no rung " +
			"and no button — and it " +
			"also makes the domain CEILING a measurement rather than a preference: every cell above " +
			"%.0f is the same flight. ⚠ It is an EMPIRICAL statement about the look angles THIS " +
			"engagement reaches, never 'a 180 deg window admits everything' — the angle-space radius " +
			"hypot(az, el) has supremum ~201.246 deg, pinned in test_frames.jl") %
			[FOV_CURE, FOV_MAX, FOV_WIDE, d_40, d_wide, FOV_MAX])
	# …and the knob is LIVE where it matters (the slice-19 NOT-A-DEAD-KNOB tripwire).
	if not (_pos_max_diff(op["pos"], cA["pos"]) > 0.0):
		return _fail("`seeker_fov_deg` must be a LIVE knob — changing it across the envelope boundary must MOVE the trajectory")
	if not (_pos_max_diff(op["pos"], cB["pos"]) > 0.0):
		return _fail("`cross_speed_mps` must be a LIVE knob — changing it must MOVE the trajectory")

	# ⭐⭐ PHASE 4 — THE FOURTH ROUTE TO THE 23/25 SIGNATURE, WHICH IS WHY THE MISS IS NOT THE TOOTH.
	var nv: Dictionary = _res["never"]
	print("S32V_NEVER    fov 0 deg — the DEFINED never-locked state (not a crash path): %.3f %% out of window, miss %.1f m, max|y| = %s m" %
		  [float(nv["out"]), float(nv["miss"]), float(nv["maxy"])])
	if not (float(nv["out"]) == 100.0):
		return _fail(("fov = 0 must be the NEVER-LOCKED degenerate — no measurement on any frame " +
			"(got %.3f %% out of %d). A negative slider reaches the same state through the single " +
			"clamp site `seeker_in_fov`, which is why the loader validates FINITE ONLY and imposes " +
			"no fake positivity bound") % [float(nv["out"]), int(nv["gate"])])
	if not (float(nv["maxy"]) == 0.0):
		return _fail(("⭐⭐ …and it must reach slices 23 and 25's OWN signature by a FOURTH route: a " +
			"seeker that never locks reports no LOS rate, so PN commands nothing out of plane and " +
			"max|y| is EXACTLY 0.0 (got %s). THIS is why the shipped broken arm's max|y| > %.0f m is " +
			"the discriminating tooth and the ~2000 m miss is not — three different mechanisms in " +
			"this arc produce the same miss and only this number separates them") %
			[float(nv["maxy"]), MAXY_BREAK_MIN])

	# ⭐⭐ PHASE 5 — THE ENVELOPE: THE VERDICT FLIPS WHERE THE LEAD CROSSES THE WINDOW, FROM BOTH
	# DIRECTIONS. ⚠ The two quantities compared come from DIFFERENT code paths — the lead from
	# `collision_lead_angle` (the engagement's geometry) and the verdict from `seeker_in_fov`'s test
	# on `boresight_angle` (the hardware's) — so this is a measurement, not a restatement. ⚠ And it
	# is NOT the look-angle anchor: that INDEPENDENT recompute lives in `test_missile.jl` (gate 2).
	# ⚠⚠ AND THE LEAD IS READ OFF THE ARM THAT *HELD* AT EACH CROSSING SPEED, NEVER OFF THE BROKEN
	# ONE. This is slice 29's P10a arriving in a new quantity and it is not a formality: once the
	# track breaks, the coasting missile's geometry runs away, and the lead the collision triangle
	# then "demands" is a property of the RUNAWAY rather than of the engagement — measured here at
	# 32.69 deg on the broken arm against 28.89 on the arm that held at the SAME 400 m/s crossing,
	# an inflation of nearly 4 deg. A broken arm's own lead would make this predicate partly
	# self-fulfilling; the held arm's is the engagement's uncontaminated demand. (Asserted below.)
	var lead_at := {260.0: float(_res["e20_260"]["lead"]), VY_CURE: float(_res["e25_320"]["lead"]),
					VY_SHIP: float(cA["lead"])}
	var cells := [
		{"tag": "e20_260", "fov": 20.0, "vy": 260.0, "hold": true},
		{"tag": "e20_320", "fov": 20.0, "vy": VY_CURE, "hold": false},
		{"tag": "e25_320", "fov": FOV_SHIP, "vy": VY_CURE, "hold": true},
		{"tag": "open", "fov": FOV_SHIP, "vy": VY_SHIP, "hold": false},
		{"tag": "cureA", "fov": FOV_CURE, "vy": VY_SHIP, "hold": true},
		{"tag": "e20_400", "fov": 20.0, "vy": VY_SHIP, "hold": false},
	]
	for c in cells:
		var mm: Dictionary = _res[str(c["tag"])]
		var held: bool = float(mm["out"]) == 0.0
		var demand: float = float(lead_at[float(c["vy"])])
		print("S32V_ENVELOPE fov %.0f deg vs a %.0f m/s crossing needing a %.2f deg lead  ->  %s   (out %.3f %%, miss %.3f m; this arm's own lead reads %.2f deg)" %
			  [float(c["fov"]), float(c["vy"]), demand,
			   "HELD" if held else "BROKEN", float(mm["out"]), float(mm["miss"]),
			   float(mm["lead"])])
		if held != bool(c["hold"]):
			return _fail(("THE ENVELOPE: at fov %.0f deg against a %.0f m/s crossing the track was " +
				"expected to %s and did not (out %.3f %%, miss %.3f m). The envelope is the set of " +
				"engagements a given window can fly, and it flips from BOTH directions — widen the " +
				"seeker or slow the target and the same cell changes verdict") %
				[float(c["fov"]), float(c["vy"]), "HOLD" if bool(c["hold"]) else "BREAK",
				 float(mm["out"]), float(mm["miss"])])
		# ⭐ AND THE LEAD IS WHAT PREDICTS IT — the ENGAGEMENT's own number against the HARDWARE's.
		if held != (demand < float(c["fov"])):
			return _fail(("⭐⭐ THE LESSON AS A PREDICATE: the track holds EXACTLY when the collision " +
				"triangle's own lead fits inside the window. At fov %.0f deg the engagement demands " +
				"%.2f deg and the track %s — the two must agree. The FOV a seeker needs is not a " +
				"seeker number; it is the ENGAGEMENT's. ⚠ The lead comes from `collision_lead_angle` " +
				"and the verdict from `seeker_in_fov` on `boresight_angle` — different code paths, " +
				"so this is a measurement and not a restatement. ⚠ And the demand is read off the " +
				"arm that HELD at this crossing speed, never off a broken one (slice 29's P10a)") %
				[float(c["fov"]), demand, "HELD" if held else "BROKE"])
	# ⚠ THE CONTAMINATION, ASSERTED RATHER THAN ASSUMED: a broken arm's own lead really is inflated.
	if not (float(op["lead"]) > float(cA["lead"]) + 1.0):
		return _fail(("the runaway must actually INFLATE the broken arm's lead, or the care taken " +
			"above is theatre: at the same %.0f m/s crossing the broken arm reads %.2f deg and the " +
			"arm that held reads %.2f. THAT is why every demand quoted here comes from a held arm — " +
			"slice 29's P10a (a ringing arm's look band swings BECAUSE it rings) in a new quantity") %
			[VY_SHIP, float(op["lead"]), float(cA["lead"])])
	# …and the lead must MOVE with the engagement, or the predicate above is vacuous.
	if not (float(cA["lead"]) > float(_res["e25_320"]["lead"]) + 1.0
			and float(_res["e25_320"]["lead"]) > float(_res["e20_260"]["lead"]) + 1.0):
		return _fail(("the lead must RISE with the crossing speed or the predicate is vacuous: %.2f " +
			"deg at 260 m/s, %.2f at 320, %.2f at 400. That monotone rise IS the envelope axis") %
			[float(_res["e20_260"]["lead"]), float(_res["e25_320"]["lead"]),
			 float(cA["lead"])])

	# PHASE 6 — REPLAY: held-seed, bit-identical (class 4a — the window gates the VALUE, never the
	# DRAW; an out-of-window tick still draws its `n_az`/`n_el` and DISCARDS them, which is slice
	# 25's own lockstep and what keeps 25-31 bit-identical).
	var rdiff := _pos_max_diff(op["pos"], _res["replay"]["pos"])
	print("S32V_REPLAY   posdiff_vs_open = %s m  (must be 0.0 — SEEDED determinism, class 4a: the EIGHTH consecutive RNG-live slice, so the seed is load-bearing and conventions 3/11 apply)" % rdiff)
	if not (rdiff == 0.0):
		return _fail(("held-config replay must be BIT-IDENTICAL (posdiff %s m). A coasting tracker " +
			"is deterministic, and the window must not disturb the draw topology — the draw-count " +
			"identity itself is ASSERTED in `test_missile.jl`, not assumed") % rdiff)
	return _pass()

# --- scanning -------------------------------------------------------------------------------

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_turned = false
	_n_gate = 0
	_n_out = 0
	_max_look = 0.0
	_n_band = 0
	_n_aero = 0
	_n_defl = 0
	_max_ceil = 0.0
	_lead_list = []
	_fov_seen = 0.0
	_max_y = 0.0
	_t_break = -1.0
	_r_break = -1.0
	_pos_trace = []
	_pos_appr = []

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
		if tel.has(MID + ".seeker_fov_deg"):
			_fov_seen = float(tel[MID + ".seeker_fov_deg"])
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				if not mpos.is_empty():
					_pos_appr.append(mpos)
					# ⚠ ACCUMULATED ON THE CLOSING LEG ONLY, like everything else here: past CPA the
					# missile flies on and |y| would keep growing for reasons that have nothing to do
					# with the window.
					_max_y = maxf(_max_y, absf(float(mpos[1])))
				# WINDOW 1 — the look-angle / out-of-window window, RANGE-GATED at r > 200 m.
				if r > 200.0:
					_n_gate += 1
					_max_look = maxf(_max_look, float(tel.get(MID + ".look_angle", 0.0)))
					if float(tel.get(MID + ".seeker_valid", 1.0)) < 0.5:
						_n_out += 1
						if _t_break < 0.0:
							_t_break = float(f.get("t", -1.0))
							_r_break = r
				# WINDOW 2 — the ISOLATION band, slice 28/29/30/31's [500, 3000] m, inherited with
				# its reasons (a crossing wire's whole-approach numbers carry a legitimate
				# front-loaded launch transient, and arms with different ToF would otherwise compare
				# different parts of the engagement — which matters MORE here than anywhere, since
				# ToF spans 5.3-15.4 s across this file).
				if r > 500.0 and r < 3000.0:
					_n_band += 1
					_max_ceil = maxf(_max_ceil, float(tel.get(MID + ".a_max_aero", 0.0)))
					_lead_list.append(float(tel.get(MID + ".lead_angle_deg", 0.0)))
					if float(tel.get(MID + ".aero_sat", 0.0)) > 0.5:
						_n_aero += 1
					if float(tel.get(MID + ".defl_sat", 0.0)) > 0.5:
						_n_defl += 1
			_prev_los = r
		last_t = float(f.get("t", -1.0))
	if last_t < 0.0:
		return false
	return last_t >= _t_target - 0.5 * _dt

# The MEDIAN of the series — the operating-point value. On an arm whose track has broken the lead
# runs away with the geometry, so a MEAN would be dominated by the runaway rather than by the lead
# the engagement actually demanded (slice 29's verifier failed on the mirror-image defect).
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
	# Slice 32 REUSES slice 23's 3-D airframe view and adds its OWN button-dropping marker — it has no
	# rung to cycle either (slice-16 Option-P′, EIGHTH use: 16, 26, 27, 28, 29, 30, 31, 32).
	if not bool(f.get("airframe_view", false)):
		return "a slice-32 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-32 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("seeker_fov_view", false)):
		return "a slice-32 handshake must ship seeker_fov_view=true — the marker that DROPS the shared button. Without it the client falls through to slice 25's `seeker_axes` cycler, whose other position (:pitch_plane) leaves the WINDOW LIVE on a missile that ALSO misses by 2000 m for a wholly unrelated reason: two mechanisms in one view, which convention 9 exists to prevent"
	# ⚠⚠ AND THE RADOME MARKER MUST BE ABSENT — the radome keys are off this wire BY DESIGN
	# (convention 9): a ringing arm's look angle swings BECAUSE it rings, so the angle measured on one
	# is the LOOP's and not the ENGAGEMENT's. The radome × FOV corollary is a SECOND mechanism and
	# lives in `test_missile.jl` (the slice-28 precedent for relocating a non-client-drivable claim).
	if bool(f.get("radome_view", false)):
		return "a slice-32 scenario must carry NO radome (radome_view was true) — a ringing arm's look angle swings BECAUSE it rings, so the look angle measured on one belongs to the LOOP and not to the ENGAGEMENT. The corollary is measured in test_missile.jl, off this wire"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-32 scenario must HOLD :seeker_axes at az_el — the window lives in `_observe_point3d!`, the two-angle host, which is also why the LOADER refuses `seeker_fov_deg` without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-32 scenario must HOLD :airframe at six_dof — the window is INERT without it (there is no attitude to measure a look angle OFF), and the gate is on the LIVE rung, never on :att_q, which is minted once and never deleted. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-32 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-32 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-32 scenario must HOLD :seeker at :filtered — the alpha-beta tracker is what COASTS when the measurement stops, and the coast is the mechanism. Got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-32 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — slice 24 measured a bank_to_turn wire binding the aero ceiling 93.2% of its approach, which would destroy the aero_sat = 0 isolation this slice's whole claim rests on)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-32 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	# ⭐ TWO KNOBS, and convention 9 is satisfied by a MEASUREMENT (phase ENVELOPE above), not by
	# counting sliders: they are the two terms of ONE comparison, `fov` vs `lead(vy)`, and the verdict
	# flips exactly where the difference crosses zero — reached from both directions.
	if not keys.has("seeker_fov_deg"):
		return "slice-32 handshake must expose the 'seeker_fov_deg' slider — the HARDWARE side of the comparison, and CURE A"
	if not keys.has("cross_speed_mps"):
		return "slice-32 handshake must expose slice 30's 'cross_speed_mps' slider — the ENGAGEMENT side, and CURE B. Inherited unchanged, because the lead is a property of the engagement and this slice is about what the window has to contain"
	if str(keys["seeker_fov_deg"]) != MID:
		return "the 'seeker_fov_deg' knob must target the interceptor '%s' (got '%s')" % [MID, str(keys["seeker_fov_deg"])]
	if str(keys["cross_speed_mps"]) != TID:
		return "the 'cross_speed_mps' knob must target the TARGET '%s' — it is the engagement's axis, not the missile's (got '%s')" % [TID, str(keys["cross_speed_mps"])]
	if keys.size() != 2:
		return "slice-32 must expose EXACTLY TWO knobs (got %d) — the window and the engagement that has to fit inside it; every other candidate is disqualified below" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate").
	if keys.has("radome_slope") or keys.has("radome_slope_est") or keys.has("radome_ripple"):
		return "slice-32 must NOT expose any radome knob — a SECOND MECHANISM on the showcase wire (convention 9). The radome × FOV corollary is measured in test_missile.jl instead"
	if keys.has("n_pn"):
		return "slice-32 must NOT expose an 'n_pn' knob — it moves the guidance loop this lesson is not about (the confounded-lever rule, 26/27/28/29/30/31)"
	if keys.has("rho"):
		return "slice-32 must NOT expose a 'rho' knob — it moves the aero ceiling, i.e. the one thing the isolation holds at 0"
	if keys.has("sigma_seek"):
		return "slice-32 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it (26/27/28/29/30/31's reasoning, unchanged)"
	if keys.has("elevation_deg"):
		return "slice-32 must NOT expose 'elevation_deg' — TWICE disqualified: it is the slice-19 DEAD-knob class (position and attitude are built once at LOAD and `reset` re-reads the YAML), AND gate 0's P5 found it is what sets this wire's never-acquires floor, so a slider on it would measure the LAUNCHER and not the SEEKER"
	if keys.has("alpha_max") or keys.has("af_alpha_max"):
		return "slice-32 must NOT expose an 'alpha_max' knob — it is the arc's aero ceiling, held at 0.0 % here on purpose so the miss is a POINTING miss"
	if keys.has("speed"):
		return "slice-32 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
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
	var op: Dictionary = _res["open"]
	var cA: Dictionary = _res["cureA"]
	var cB: Dictionary = _res["cureB"]
	var nv: Dictionary = _res["never"]
	print(("S32V OK: slices 26-31 each made the LOOK ANGLE their central quantity and then bounded " +
		"every knob domain by it reaching 30 deg — a §1 MODEL-VALIDITY caveat, declared five times. " +
		"A real seeker makes the same angle a PHYSICAL STOP, so the caveat and the hardware coincide " +
		"and the arc's FIRST SENSOR-SIDE CAP lands (every earlier cap in this project is airframe or " +
		"actuator). ⭐⭐ AND WHAT IT CAPS IS THE ENGAGEMENT: a %.0f deg seeker against a %.0f m/s " +
		"crossing loses the target at t = %.3f s / r = %.1f m — WHILE THE LEAD IS STILL BUILDING — " +
		"is out of its window %.3f %% of the approach (range-gated at r > 200 m) and misses by " +
		"%.1f m, out of a missile with aero_sat %d of %d in-band frames: every bit of the authority " +
		"it needs and no idea where to point it. ⭐ TWO CURES, ONE SLIDER EACH, AND THE ASYMMETRY IS " +
		"THE PAYLOAD: widen the seeker to %.0f deg -> %.3f m (%.0fx) and the engagement is KEPT, or " +
		"slow the crossing to %.0f m/s -> %.3f m (%.0fx) and the engagement is DECLINED. ⭐⭐ THE " +
		"ENVELOPE IS THE LESSON AS A PREDICATE: the track holds EXACTLY when the collision " +
		"triangle's own lead fits inside the window, checked over six cells from BOTH directions — " +
		"%.2f deg of lead at 260 m/s flies a 20 deg window, %.2f at 320 breaks it and flies 25, " +
		"%.2f at 400 breaks that and flies 30 — every demand read off the arm that HELD at that " +
		"crossing speed, because a BROKEN arm's own lead is inflated by the runaway it is in " +
		"(%.2f against %.2f at the same 400 m/s: slice 29's P10a in a new quantity). ⇒ THE FOV A " +
		"SEEKER NEEDS IS NOT A SEEKER NUMBER, IT " +
		"IS THE ENGAGEMENT'S OWN LEAD ANGLE, so a field of view does not cost you accuracy, it costs " +
		"you the ENVELOPE. ⚠ KNOB, NOT RUNG, AND THE IDENTITY IS ON THE CLOSING LEG: past CPA the " +
		"target is BEHIND the missile and a narrow window correctly drops it, which is the post-CPA " +
		"LOS flip and not the approach. ⚠⚠ THE SIGNATURE IS SLICE 23's AND SLICE 25's AND THE MECHANISM IS " +
		"NEITHER: both left max|y| = 0.0 EXACTLY (the command thrown away; the command never " +
		"formed), and so does the fov = 0 degenerate here by a FOURTH route (%s m, %.1f %% out — a " +
		"seeker that never locks reports no LOS rate). The shipped broken arm reaches max|y| = " +
		"%.1f m: it WAS formed and flown, and the sensor stopped supplying it MID-FLIGHT. That " +
		"number is the tooth; the ~2000 m miss is not. ⚠ THE METRIC IS THE MISS AND THAT INVERTS " +
		"28-31's — losing the measurement CUTS the parasitic feed, so rms r would fall while the " +
		"miss opened and the slice would be written backwards. ⚠ KNOB, NOT RUNG, MEASURED: with the " +
		"lead inside the window, fov %.0f / %.0f / %.0f fly BIT-IDENTICAL trajectories (%s m), which " +
		"is also the measured reason the domain ceiling is %.0f. ⚠ NO NEW INSTABILITY, NO NEW LOOP " +
		"GAIN, NO NEW PLANT — slice 26's positive-feedback language stays with 26-31 and slice 20's " +
		"'degenerative spiral' stays forbidden; what is new is a HARD SENSOR LIMIT and, through it, " +
		"an ENGAGEMENT ENVELOPE. ⚠ SCOPE: a STRAPDOWN window, not a gimbal servo — a head with its " +
		"own state would REWRITE 26-31's look_az, and it is a named deferral. The isolation holds " +
		"(aero_sat and defl_sat both 0 in the [500,3000] m band in every arm, so this is a POINTING " +
		"miss), the quiet arms stay inside the %.0f deg small-angle budget (%.2f deg peak), and " +
		"replay is bit-identical: class 4a, the EIGHTH consecutive RNG-live slice, with the window " +
		"gating the VALUE and never the DRAW.")
		% [FOV_SHIP, VY_SHIP, float(op["tbrk"]), float(op["rbrk"]), float(op["out"]),
		   float(op["miss"]), int(op["aero"]), int(op["band"]),
		   FOV_CURE, float(cA["miss"]), float(op["miss"]) / maxf(float(cA["miss"]), 1.0e-9),
		   VY_CURE, float(cB["miss"]), float(op["miss"]) / maxf(float(cB["miss"]), 1.0e-9),
		   float(_res["e20_260"]["lead"]), float(_res["e25_320"]["lead"]), float(cA["lead"]),
		   float(op["lead"]), float(cA["lead"]),
		   float(nv["maxy"]), float(nv["out"]), float(op["maxy"]),
		   FOV_CURE, FOV_MAX, FOV_WIDE, _pos_max_diff(cA["appr"], _res["wide"]["appr"]), FOV_MAX,
		   LOOK_MAX_DEG, float(cA["look"])])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S32V FAIL: " + msg)
	print("S32V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
