extends SceneTree
# slice33_verify.gd — THE RING IS AN FOV BUDGET ITEM: WHAT THE PARASITIC LOOP COSTS YOU IS THE
# ENVELOPE (slice 33 gate 3, convention 14's first proof).
#
# Drives the REAL server over the wire against `scenarios/slice33_budget.yaml` and asserts the
# lesson AS A NUMBER, plus a held-seed bit-identical replay.
#
#   godot --headless --path clients/godot --script res://net/slice33_verify.gd     (exit 0 = pass)
#
# ─────────────────────────────────────────────────────────────────────────────────────────────
# WHAT THIS FILE PROVES
#
# Slices 26–31 spent six slices on a missile that shakes itself, and every one of them recorded, as
# a standing fact, that THE RINGING ARM STILL HITS (slice 26: "the MISS is NOT the metric — the
# ringing arm STILL HITS (2.18 m)"), which is why the whole family measures `rms q` / `rms r`. The
# ring was benign BECAUSE THE SEEKER HAD AN INFINITE WINDOW. Slice 32 then gave the seeker a real
# window and NO GLASS, and measured the requirement as the engagement's own lead angle.
#
# ⇒ THE FOV A SEEKER NEEDS IS THE ENGAGEMENT'S LEAD **PLUS THE PARASITIC LOOP'S EXCURSION**, and
# slice 30's design rule buys the whole second term back — depth-independently.
#
# ⚠⚠ THE TWO-RUN DISCIPLINE IS THE STRUCTURE OF THIS FILE, NOT A COMMENT IN IT (seam discipline 1).
# `rms r` and `look_max` are BOTH meaningless on a windowed arm: losing the measurement CUTS the
# parasitic feed, so `rms r` FALLS while the miss OPENS (measured below: 4.72x down, 604x out), and
# the windowed arm's own `look_max` is the POST-LOCK-LOSS RUNAWAY (~90 deg, slice 32's signature)
# rather than any read of the ring. So EVERY design is flown TWICE — once with the FOV slider at its
# domain ceiling (the FREE read, which supplies the excursion) and once through the shipped window
# (the ENVELOPE read) — and the free arms are the ONLY ones any ring number is taken from.
#
# ⚠⚠ AND THE FREE READ IS ITSELF A MEASUREMENT, NOT AN ASSUMPTION. A live wire always carries the
# key, so "no window" is unreachable here; `fov = 40` stands in for it, and PHASE FREE asserts
# `out == 0.0` on every one of those arms — the window is never reached, so the number is the ring's.
#
# ⚠⚠ THE EMIT GRID UNDER-READS THE EXCURSION BY MORE THAN THE SURVIVABLE BAND IS WIDE — A GATE-3
# FINDING, AND IT DECIDES WHAT THIS FILE MAY CLAIM. The server emits every 16th tick, so the peak
# look angle a verifier sees is the largest SAMPLED one: 24.9946 deg here against the 25.0108 the
# core actually flies, a 0.016 deg deficit. Gate 2 measured the survivable band at ~0.011-0.05 deg
# wide. ⇒ THE FINEST CELL IN THAT BAND IS BELOW THIS FILE'S RESOLUTION: a window placed 0.011 deg
# under the FRAME-sampled excursion is really ~0.027 deg under the true one, and it lands in the
# tens-of-metres regime (20.6 m) rather than the 2.0 m one `test_missile.jl` measures PER TICK. So
# the sub-degree claim is made per-tick in the test suite, and THIS file makes the claim its own
# resolution supports — which is still the whole of TWO THRESHOLDS, because `t_break` separates them
# cleanly (r = 707 m, near CPA, against r = 3543 m with the lead still building).
# ⚠ Everything else here is one-sided and sized on FRAME numbers: [[ewsim-missile-verifier-sampling]]
# — a MISS samples faithfully, a HIT samples COARSELY (the free arms read 1.4-3.9 m where the core
# flies 0.18-2.07).
#
# ⚠ THE ISOLATION IS NOT SLICE 32's AND MUST NOT BE COPIED FROM IT. Slice 32 could assert
# `aero_sat == 0` in EVERY arm because its wire had NO GLASS. On this wire the FREE ringing arm
# saturates 80.7 % of its band AND HITS (slice 26's ceiling BOUNDING the cycle), while the broken arm
# saturates 0.00 % and misses by kilometres — saturation does not discriminate in either direction
# here, THE WINDOW does. What IS asserted on every arm is `defl_sat == 0` (measured 0 throughout).
#
# ⚠⚠ AND A BAND METRIC ON A BADLY BROKEN ARM IS NOT MISLEADING BUT UNDEFINED (gate 2's finding). The
# shipped default's CPA is 3697 m, so it NEVER ENTERS the arc's r in [500, 3000] band: n_band = 0.
# A `sum/max(n,1)` would print a beautifully quiet `rms r = 0.00000` computed from ZERO SAMPLES. Every
# band number below is guarded by `n_band > 0` first, and the zero-sample arm is asserted AS SUCH.
#
# ⚠ ONLY %.Nf / %d / %s APPEAR IN ANY FORMAT IN THIS FILE. `%g` and `%.2e` are NOT GDScript
# specifiers, and an unknown one makes the WHOLE `%` fail SILENTLY — the line prints as its own
# format string ON A GREEN RUN (slice 21's bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 1800.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — BOTH sliders live here on this wire

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16). The server emits every 16th
# tick, so a STEPS that is not a multiple makes the last frame land BELOW `STEPS*dt` and `_drain_scan`
# waits forever, SILENTLY, with no output at all — slice 31 lost an hour to exactly this and it reads
# like a slow wire. 12800 = 16 * 800.
# ⚠ SIZED OFF THE SLOWEST ARM, MEASURED: ToF spans 7.00 s (the broken default, which flies past
# early) to 11.25 s (the quiet cure-B arm). 12.8 s leaves ~1.5 s of headroom, and EVERY arm asserts
# it REACHED CPA rather than trusting the sizing.
const STEPS := 12800

const FOV_SHIP := 21.0            # the shipped window — the ladder's, and it is NOT sized for the
                                  # engagement (19 flies that); the ring spends the other 4 degrees
const FOV_FREE := 40.0            # the domain CEILING = the FREE read (seam discipline 1)
const FOV_CURE := 26.0            # CURE A — widen the seeker to fit the ring's excursion
const RHAT_SHIP := -0.03          # slice 28's BORESIGHT characterization: hardware residual 0.000
const RHAT_18 := -0.18
const RHAT_24 := -0.24            # slice 30's measured onset ("last decisive ring", -0.24 / 0.709)
const RHAT_33 := -0.33            # slice 30's RULE — but CURE B reads it off the WIRE, not this
const BRACKET := 0.1              # the predicate bracket, either side of the MEASURED excursion
const BAND_OFF := 0.011           # the survivable-band offset (see the emit-grid note above)

const BREAK_MISS_MIN := 1000.0    # measured 3696.9 (default), 2192.0 (R̂ -0.18), 1475.1 (bracket lo)
const HIT_MAX := 10.0             # measured 1.4-3.9 m frame-sampled; the core flies 0.18-2.07
const OUT_BREAK_MIN := 40.0       # measured 72.6 / 42.4 / 46.0 % — frame-sampled, r > 200 m
const RING_RMS_MIN := 0.9         # the loud free arms: 1.0715 / 0.9317 (against 0.0589 at the rule)
const QUIET_RMS_MAX := 0.1        # slice 30's rule, free: 0.05887
const RUNAWAY_LOOK_MIN := 85.0    # the post-lock-loss signature: 90.8 / 90.6 deg
const MODEL_VALID_DEG := 30.0     # the small-angle bend budget 28/29/30/31 each declared
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
var _min_marg := 1.0e30           # the SIGNED budget's floor — slice 33's one new number
var _n_band := 0                  # closing frames with 500 < r < 3000 — the isolation window
var _n_aero := 0
var _n_defl := 0
var _sum_r2 := 0.0                # for rms r — the RING, and legible on the FREE arms ONLY
var _max_y := 0.0
var _t_break := -1.0
var _r_break := -1.0
var _worst := 0.0                 # slice 30's aim point, READ OFF THE WIRE (never recomputed)
var _fov_seen := 0.0
var _rhat_seen := 0.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S33V_INIT godot=", Engine.get_version_info().string)
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
	# ⚠⚠ THE FREE LADDER RUNS FIRST, AND THAT ORDERING IS LOAD-BEARING RATHER THAN TIDY: the bracket,
	# the band and CURE B are all specified RELATIVE to numbers these arms MEASURE (the excursion, and
	# slice 30's aim point off the wire's own telemetry). Nothing below hardcodes 25.0 or -0.33 — the
	# margin at the bracket is a tenth of a degree and the aim point is -0.32999999999999996, so a
	# literal would be a magic number the next retune silently breaks (the slice-21 magic-multiple
	# tooth, pinned against a measured quantity instead).
	# 1) THE FREE LADDER — the FOV slider at its ceiling: the STABILITY read and the EXCURSION.
	_arms.append({"tag": "f03", "fov": FOV_FREE, "rhat": RHAT_SHIP})
	_arms.append({"tag": "f18", "fov": FOV_FREE, "rhat": RHAT_18})
	_arms.append({"tag": "f24", "fov": FOV_FREE, "rhat": RHAT_24})
	_arms.append({"tag": "f33", "fov": FOV_FREE, "rhat": RHAT_33})
	# 2) THE DISEASE — the shipped wire, untouched (fov 21, R̂ = R₀, slice 28's boresight compensator).
	_arms.append({"tag": "open"})
	# 3) REPLAY — bit-identical, held seed (class 4a: the window gates the VALUE, never the DRAW).
	_arms.append({"tag": "replay"})
	# 4) THE SAME LADDER THROUGH THE SHIPPED WINDOW — the ENVELOPE read.
	_arms.append({"tag": "w18", "fov": FOV_SHIP, "rhat": RHAT_18})
	_arms.append({"tag": "w24", "fov": FOV_SHIP, "rhat": RHAT_24})
	# 5) CURE B — aim R̂ at slice 30's rule. ⚠ `rhat_ref` reads `radome_slope_worst` OFF THE WIRE.
	_arms.append({"tag": "cureB", "fov": FOV_SHIP, "rhat_ref": "f03"})
	# 6) THE PREDICATE, AS A BRACKETING PAIR AROUND THE MEASURED EXCURSION — never `ceil` (seam
	#    discipline 2: `critical == ceil(excursion)` held 16/16 at gate 0, but that is an artifact of a
	#    1 deg measuring grid and the PHYSICAL claim is the inequality `held <=> fov > excursion`).
	_arms.append({"tag": "brlo", "fov_ref": "f03", "fov_off": -BRACKET, "rhat": RHAT_SHIP})
	_arms.append({"tag": "brhi", "fov_ref": "f03", "fov_off": BRACKET, "rhat": RHAT_SHIP})
	# 7) TWO THRESHOLDS — `held` and `hits` are DIFFERENT predicates and they break at different
	#    windows. A hundredth of a degree short leaves the window LATE and lands within tens of
	#    metres; a tenth short leaves it while the lead is still building and misses by kilometres.
	_arms.append({"tag": "band", "fov_ref": "f03", "fov_off": -BAND_OFF, "rhat": RHAT_SHIP})
	# 8) CURE A — widen the seeker to fit the ring the design is already flying.
	_arms.append({"tag": "cureA", "fov": FOV_CURE, "rhat": RHAT_SHIP})

func _start_next() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("fov"):
		cmds.append(_set_param_cmd(MID, "seeker_fov_deg", float(arm["fov"])))
	elif arm.has("fov_ref"):
		# PINNED AGAINST WHAT THIS RUN MEASURED, not against a literal.
		var base: float = float(_res[str(arm["fov_ref"])]["look"])
		cmds.append(_set_param_cmd(MID, "seeker_fov_deg", base + float(arm["fov_off"])))
	if arm.has("rhat"):
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(arm["rhat"])))
	elif arm.has("rhat_ref"):
		# ⚠ SLICE 30's AIM POINT READ OFF ITS OWN SHIPPED TELEMETRY, never recomputed as R₀ + 2A —
		# the cure uses the number the WIRE computes, which is -0.32999999999999996 and not -0.33.
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(_res[str(arm["rhat_ref"])]["worst"])))
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
	# ⚠⚠ NaN, NOT 0.0, WHEN THE BAND IS EMPTY (gate 2's finding, and this file inherits it because
	# the shipped DEFAULT arm is exactly the arm it was found on: its CPA is 3697 m, so it never
	# enters r in [500, 3000] at all). A `sum/max(n,1)` here would print a beautifully quiet
	# `rms r = 0.00000` COMPUTED FROM ZERO SAMPLES on the arm that misses by 3.7 km — the gate-1
	# post-review's own catch ("a column that reproduces because it counts nothing is not a
	# reproduction") arriving one gate later in a new quantity.
	var rms := NAN if _n_band == 0 else sqrt(_sum_r2 / float(_n_band))
	var aero_pc := NAN if _n_band == 0 else 100.0 * float(_n_aero) / float(_n_band)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		"look": _max_look, "marg": _min_marg, "band": _n_band, "aero": aero_pc,
		"defl": _n_defl, "rms": rms, "maxy": _max_y, "tbrk": _t_break, "rbrk": _r_break,
		"worst": _worst, "fov": _fov_seen, "rhat": _rhat_seen, "pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S33V_ARM   %-6s fov=%.3f  R̂=%+.4f  ->  %s   miss=%.3f  out=%.3f%% of %d gated frames  " +
		   "look_max=%.3f  margin_min=%.2f  rms_r=%.5f (%d band frames)  aero=%.2f%%  defl=%d  " +
		   "max|y|=%.1f  break t=%.3f r=%.1f  cpa=%s") %
		  [tag, m["fov"], m["rhat"], "TRACK BROKEN" if out_pc > 0.0 else "held", m["miss"], out_pc,
		   m["gate"], m["look"], m["marg"], m["rms"], m["band"], m["aero"], m["defl"], m["maxy"],
		   m["tbrk"], m["rbrk"], "Y" if m["turned"] else "N"])
	if not (_n_gate > 100):
		return ("arm %s: the r > 200 m window must contain frames to measure (got %d) — every " +
				"look-angle, budget and out-of-window assert on this arm would be vacuous") % [tag, _n_gate]
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was still " +
				"closing at the end, so its miss (%.3f m) is a last closing range and not a CPA at " +
				"all. ⚠ ToF varies 7.00-11.25 s across this file, so STEPS is sized off the SLOWEST " +
				"arm and every arm asserts this rather than trusting the sizing") % [tag, STEPS, _min_los]
	# ⚠⚠ THE ISOLATION HERE IS `defl_sat`, AND NOT SLICE 32's `aero_sat` — DO NOT COPY THAT ONE, IT
	# INVERTS. Slice 32's wire had NO GLASS, so it could assert `aero_sat == 0` in every arm and call
	# the miss a POINTING miss. On this wire the FREE ringing arm saturates 80.7 % of its band AND
	# HITS (slice 26: the ceiling BOUNDS the cycle, the radome decides whether there IS one), while
	# the broken arm saturates 0.00 % and misses by kilometres. Saturation does not discriminate in
	# either direction here; THE WINDOW does. What is invariant, and measured 0 on every arm, is that
	# the FIN never pegs — so the missile always had the authority, which is what makes the fourth cap
	# (slice 19's) and the second (slice 15's) both innocent of this miss.
	if not (_n_defl == 0):
		return ("arm %s: `defl_sat` fired on %d frames — the fin must never peg on this wire. If this " +
				"ever fires, the miss has acquired an ACTUATOR component (slice 15's cap) and neither " +
				"the ring nor the window is cleanly the cause any more") % [tag, _n_defl]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var f03: Dictionary = _res["f03"]
	var f18: Dictionary = _res["f18"]
	var f24: Dictionary = _res["f24"]
	var f33: Dictionary = _res["f33"]
	var op: Dictionary = _res["open"]
	var w18: Dictionary = _res["w18"]
	var w24: Dictionary = _res["w24"]
	var cA: Dictionary = _res["cureA"]
	var cB: Dictionary = _res["cureB"]

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE FREE — ⭐ THE STANDING FACT OF SLICES 26-31, RE-MEASURED, AND THE FREE READ'S OWN LICENCE.
	print("S33V_FREE     the FOV slider at its ceiling (%.0f deg): R̂ %+.2f / %+.2f / %+.2f / %+.2f -> rms r %.5f / %.5f / %.5f / %.5f, excursion %.3f / %.3f / %.3f / %.3f deg, and the miss is %.3f / %.3f / %.3f / %.3f m — EVERY ONE OF THEM HITS" %
		  [FOV_FREE, float(f03["rhat"]), float(f18["rhat"]), float(f24["rhat"]), float(f33["rhat"]),
		   float(f03["rms"]), float(f18["rms"]), float(f24["rms"]), float(f33["rms"]),
		   float(f03["look"]), float(f18["look"]), float(f24["look"]), float(f33["look"]),
		   float(f03["miss"]), float(f18["miss"]), float(f24["miss"]), float(f33["miss"])])
	for k in ["f03", "f18", "f24", "f33"]:
		var a: Dictionary = _res[k]
		# ⚠⚠ THE FREE READ IS A MEASUREMENT, NOT AN ASSUMPTION (seam discipline 1). A live wire always
		# carries the key, so "no window" is unreachable — `fov = 40` stands in for it, and it is only
		# legitimate if the window is NEVER REACHED on these arms. If this fires, the excursion column
		# is contaminated by the post-lock-loss runaway and every prediction below is built on it.
		if not (float(a["out"]) == 0.0):
			return _fail(("PHASE FREE, arm %s: the free-read arm must never leave its window (%.3f %% " +
				"out). The FOV domain ceiling stands in for 'no window at all', and the excursion it " +
				"supplies is only the RING's if the window is never reached — otherwise it is the " +
				"~90 deg post-lock-loss runaway and this file predicts with the wrong number") %
				[k, float(a["out"])])
		if not (float(a["miss"]) < HIT_MAX):
			return _fail(("PHASE FREE, arm %s: THE STANDING FACT OF SLICES 26-31 must hold — a ringing " +
				"arm with an infinite window STILL HITS (%.3f m, must be < %.1f). Slice 26 wrote it " +
				"first ('the MISS is NOT the metric — the ringing arm STILL HITS'), and 27/28/29/30/31 " +
				"each inherited it. If this fires, the ring has started costing accuracy and slice " +
				"33's entire framing — that what it costs is the ENVELOPE and not the miss — is wrong") %
				[k, float(a["miss"]), HIT_MAX])
	# ⭐ THE RING IS REAL AND IT IS MONOTONE IN R̂ — the ladder walks from slice 30's design rule to
	# slice 28's boresight characterization and the excursion grows all the way.
	if not (float(f03["rms"]) > RING_RMS_MIN and float(f33["rms"]) < QUIET_RMS_MAX):
		return _fail(("PHASE FREE: the ladder must actually span quiet to loud — rms r %.5f at the " +
			"boresight compensator (must be > %.1f) against %.5f under slice 30's rule (must be < %.1f)") %
			[float(f03["rms"]), RING_RMS_MIN, float(f33["rms"]), QUIET_RMS_MAX])
	if not (float(f03["look"]) > float(f18["look"]) and float(f18["look"]) > float(f24["look"])
			and float(f24["look"]) > float(f33["look"])):
		return _fail(("PHASE FREE: the excursion must grow MONOTONICALLY with the ring — %.3f / %.3f / " +
			"%.3f / %.3f deg down the ladder. The whole claim is that the budget item IS the ring's " +
			"amplitude, so a non-monotone column would mean something else is moving the look angle") %
			[float(f03["look"]), float(f18["look"]), float(f24["look"]), float(f33["look"])])
	# ⚠ AND THE LOUDEST ARM STAYS INSIDE THE SMALL-ANGLE BEND BUDGET 28/29/30/31 EACH DECLARED — which
	# is the measured reason the R̂ slider's ceiling is the authored value and not 0.
	if not (float(f03["look"]) < MODEL_VALID_DEG):
		return _fail(("PHASE FREE: the loudest excursion (%.3f deg) must stay inside the %.0f deg " +
			"small-angle bend budget that 28/29/30/31 each declared as a §1 MODEL-VALIDITY caveat — " +
			"it is what bounds the R̂ slider's ceiling on this wire") % [float(f03["look"]), MODEL_VALID_DEG])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE DISEASE — ⭐⭐ THE SAME DESIGN, THE SAME GLASS, THE SAME SEED, THROUGH A REAL WINDOW.
	print("S33V_DISEASE  the SAME R̂ %+.2f through the shipped %.0f deg window: the track BREAKS at t = %.3f s / r = %.1f m — WHILE THE LEAD IS STILL BUILDING — the seeker is outside its window %.3f %% of the approach, the budget floor is %.2f deg, and the miss is %.3f m against the free arm's %.3f m (%.0fx)" %
		  [float(op["rhat"]), FOV_SHIP, float(op["tbrk"]), float(op["rbrk"]), float(op["out"]),
		   float(op["marg"]), float(op["miss"]), float(f03["miss"]),
		   float(op["miss"]) / maxf(float(f03["miss"]), 1.0e-9)])
	if not (float(op["miss"]) > BREAK_MISS_MIN):
		return _fail(("THE DISEASE: the shipped wire must MISS (%.3f m > %.0f). The compensator is " +
			"slice 28's BORESIGHT characterization — its HARDWARE residual is EXACTLY 0.000, the glass " +
			"matches the bench perfectly — and it rings anyway, because the ENGAGEMENT residual at the " +
			"look angle a crossing target sustains is not zero. That ring was FREE for six slices; " +
			"here it is spent out of a %.0f deg window") % [float(op["miss"]), BREAK_MISS_MIN, FOV_SHIP])
	if not (float(op["out"]) > OUT_BREAK_MIN):
		return _fail(("…and it must be the WINDOW that does it: the seeker must have no measurement for " +
			"more than %.0f %% of the approach (got %.3f %%, range-gated at r > 200 m). This is the " +
			"discriminator, not the miss") % [OUT_BREAK_MIN, float(op["out"])])
	if not (float(op["tbrk"]) > 0.0 and float(op["rbrk"]) > 2000.0):
		return _fail(("…and the break must happen EARLY, at long range, WHILE THE LEAD IS STILL " +
			"BUILDING (t = %.3f s, r = %.1f m). Slice 32: 'a short loss is survivable; what is terminal " +
			"is a loss while the lead is still building' — and phase THRESHOLDS below reaches that same " +
			"sentence by moving the WINDOW instead of the crossing speed") % [float(op["tbrk"]), float(op["rbrk"])])
	# ⭐⭐ THE HEADLINE RATIO — and note WHICH two arms it is between: same R̂, same glass, same seed.
	if not (float(op["miss"]) > 100.0 * float(f03["miss"])):
		return _fail(("⭐⭐ THE HEADLINE: the SAME design must miss by ~1000x more with a window than " +
			"without one (%.3f vs %.3f m). This is the whole slice — nothing about the missile changed " +
			"except how much of the sky its seeker can see") % [float(op["miss"]), float(f03["miss"])])
	# ⚠⚠ AND THE BAND METRIC ON THIS ARM IS UNDEFINED, NOT QUIET — asserted, because a harness that
	# printed 0.00000 here would look like the best-behaved arm in the file.
	if not (int(op["band"]) == 0):
		return _fail(("the shipped default's CPA is ~3.7 km, so it must NEVER ENTER the r in [500, 3000] " +
			"m band (got %d frames). Gate 2 found this the hard way: on a badly broken arm a band " +
			"metric is not merely misleading, it is UNDEFINED, and a `sum/max(n,1)` would have printed " +
			"a beautifully quiet rms r computed from ZERO SAMPLES") % int(op["band"]))
	# ⭐ THE DISCRIMINATING TOOTH AGAINST SLICES 23 AND 25 (the copy-paste false-claim trap): both left
	# max|y| = 0.0 EXACTLY. Here the missile TURNED — the command was formed and flown — and only then
	# lost the target.
	if not (float(op["maxy"]) > 1000.0):
		return _fail(("the mechanism is neither slice 23's nor slice 25's, and max|y| is what says so: " +
			"both left max|y| = 0.0 EXACTLY (the command thrown away; the command never formed). Here " +
			"it WAS formed and flown (%.1f m) and the sensor stopped supplying it MID-FLIGHT") % float(op["maxy"]))

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE LADDER — ⭐ WHERE THE WINDOW BITES, DOWN THE SAME LADDER. Two designs fit inside 21 deg
	# and keep their engagement; two do not and lose it.
	print("S33V_LADDER   through the SHIPPED %.0f deg window: R̂ %+.2f (excursion %.3f) -> %.3f m, %+.2f (%.3f) -> %.3f m, %+.2f (%.3f) -> %.3f m, %+.2f (%.3f) -> %.3f m" %
		  [FOV_SHIP, float(f33["rhat"]), float(f33["look"]), float(cB["miss"]),
		   float(w24["rhat"]), float(f24["look"]), float(w24["miss"]),
		   float(w18["rhat"]), float(f18["look"]), float(w18["miss"]),
		   float(op["rhat"]), float(f03["look"]), float(op["miss"])])
	# The two that FIT: `held` is asserted on the GATED quantities, never as bit-identity to the free
	# arm. ⚠⚠ GATE 2 PAID FIVE FAILING ASSERTS FOR THAT DISTINCTION: every held arm leaves the window
	# in the last metres (first out at r = 0.18-8.55 m) because the LOS unit vector swings through a
	# huge angle as r -> 0, and those few coasting ticks perturb the CPA. Slice 32's `===` passed only
	# because its 30 deg window happened not to be crossed before ITS CPA — luck of a wider window,
	# not a law.
	var herr := _held(w24, f24, "w24 (R̂ %+.2f, excursion %.3f deg, inside a %.0f deg window)" % [float(w24["rhat"]), float(f24["look"]), FOV_SHIP])
	if herr != "":
		return _fail(herr)
	herr = _held(cB, f33, "cureB (R̂ at slice 30's rule, excursion %.3f deg)" % float(f33["look"]))
	if herr != "":
		return _fail(herr)
	# The two that DO NOT.
	for pair in [["w18", f18], ["open", f03]]:
		var a: Dictionary = _res[str(pair[0])]
		var fr: Dictionary = pair[1]
		if not (float(a["out"]) > 0.0 and float(a["miss"]) > BREAK_MISS_MIN):
			return _fail(("PHASE LADDER, arm %s: an excursion of %.3f deg does not fit a %.0f deg " +
				"window, so this arm must LOSE the track and miss by kilometres (got %.3f %% out, " +
				"%.3f m)") % [str(pair[0]), float(fr["look"]), FOV_SHIP, float(a["out"]), float(a["miss"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE PREDICATE — ⭐⭐ `held <=> fov > excursion`, AS A BRACKETING PAIR AROUND THE MEASURED ANGLE.
	var blo: Dictionary = _res["brlo"]
	var bhi: Dictionary = _res["brhi"]
	print("S33V_PREDICATE  against a MEASURED excursion of %.3f deg: a window %.1f deg SHORT breaks (%.3f %% out, %.3f m) and %.1f deg OVER holds (%.3f %% out, %.3f m) and flies the free arm's own excursion (%.3f vs %.3f deg)" %
		  [float(f03["look"]), BRACKET, float(blo["out"]), float(blo["miss"]), BRACKET,
		   float(bhi["out"]), float(bhi["miss"]), float(bhi["look"]), float(f03["look"])])
	# ⚠⚠ BOTH BRACKET ROWS MUST SIT CLEAR OF SLICE 32's P5 LAUNCH CLIFF (~18.12 deg), which is THE
	# SCENARIO'S AUTHORED LAUNCH ATTITUDE and not a seeker property. A bracket straddling it would
	# straddle the LAUNCHER — slice 32's own confound shipped as slice 33's headline.
	if not (float(f03["look"]) - BRACKET > 18.2):
		return _fail(("PHASE PREDICATE: the bracket must sit clear of the ~18.12 deg NEVER-ACQUIRES " +
			"cliff (%.3f - %.1f = %.3f must exceed 18.2). That cliff is the scenario's AUTHORED LAUNCH " +
			"ATTITUDE, not a seeker property (slice 32's gate-0 P5), so a bracket reaching it would be " +
			"measuring the launcher") % [float(f03["look"]), BRACKET, float(f03["look"]) - BRACKET])
	if not (float(blo["out"]) > 0.0 and float(blo["miss"]) > BREAK_MISS_MIN):
		return _fail(("PHASE PREDICATE: a window a tenth of a degree BELOW the measured excursion must " +
			"BREAK (%.3f %% out, %.3f m). ⚠ ASSERTED AS AN INEQUALITY, NEVER AS `ceil` — gate 0 measured " +
			"`critical == ceil(excursion)` in 16 of 16 cells, but that identity is an artifact of a 1 " +
			"deg measuring grid") % [float(blo["out"]), float(blo["miss"])])
	herr = _held(bhi, f03, "brhi (a tenth of a degree OVER the measured excursion)")
	if herr != "":
		return _fail(herr)

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE THRESHOLDS — ⭐ `held` AND `hits` ARE DIFFERENT PREDICATES, AND `t_break` SEPARATES THEM.
	var bnd: Dictionary = _res["band"]
	print("S33V_THRESH   %.3f deg under the excursion: out %.3f %% and the miss is %.3f m, lock lost at t = %.3f s / r = %.1f m (NEAR CPA) — against %.1f deg under: out %.3f %%, miss %.3f m, lock lost at t = %.3f s / r = %.1f m (the lead still building)" %
		  [BAND_OFF, float(bnd["out"]), float(bnd["miss"]), float(bnd["tbrk"]), float(bnd["rbrk"]),
		   BRACKET, float(blo["out"]), float(blo["miss"]), float(blo["tbrk"]), float(blo["rbrk"])])
	if not (float(bnd["out"]) > 0.0 and float(bnd["miss"]) < 100.0):
		return _fail(("PHASE THRESHOLDS: a window a HUNDREDTH of a degree under the excursion must leave " +
			"the window (%.3f %% out) and STILL essentially hit (%.3f m, must be < 100). This is the " +
			"coasting branch's re-acquisition evidence — without it that branch is live-looking with no " +
			"tooth. ⚠ The finest cell (2.0 m at 0.011 deg per tick) is BELOW this file's resolution: " +
			"the emit grid under-reads the excursion by ~0.016 deg, which is WIDER than the band, so " +
			"the sub-degree claim is made per-tick in test_missile.jl") % [float(bnd["out"]), float(bnd["miss"])])
	# ⭐⭐ AND `t_break` IS THE DISCRIMINATOR — slice 32's own mechanism reached by moving the WINDOW
	# instead of the crossing speed.
	if not (float(bnd["rbrk"]) < float(blo["rbrk"]) and float(bnd["tbrk"]) > float(blo["tbrk"])):
		return _fail(("PHASE THRESHOLDS: the SURVIVABLE arm must lose lock LATE and CLOSE (t = %.3f s, " +
			"r = %.1f m) and the LOST one EARLY and FAR (t = %.3f s, r = %.1f m). That ordering IS the " +
			"mechanism — 'a short loss is survivable; what is terminal is a loss while the lead is " +
			"still building'") % [float(bnd["tbrk"]), float(bnd["rbrk"]), float(blo["tbrk"]), float(blo["rbrk"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE CURES — ⭐ TWO CURES, ONE SLIDER EACH, AND THE ASYMMETRY IS THE PAYLOAD.
	print("S33V_CURES    from the shipped %.3f m miss: CURE A widens the seeker to %.0f deg -> %.3f m (%.0fx), CURE B aims R̂ at the wire's own radome_slope_worst = %.4f -> %.3f m (%.0fx) and the requirement falls from %.3f to %.3f deg" %
		  [float(op["miss"]), FOV_CURE, float(cA["miss"]), float(op["miss"]) / maxf(float(cA["miss"]), 1.0e-9),
		   float(cB["rhat"]), float(cB["miss"]), float(op["miss"]) / maxf(float(cB["miss"]), 1.0e-9),
		   float(f03["look"]), float(f33["look"])])
	herr = _held(cA, f03, "cureA (widen the window to fit the ring the design already flies)")
	if herr != "":
		return _fail(herr)
	# ⭐⭐ THE PAYLOAD — SLICE 30's RULE IS AN ENVELOPE RULE, NOT ONLY A STABILITY RULE. Asserted as an
	# EXCURSION comparison, never a critical-FOV one (seam discipline 2 forbids the `ceil` currency,
	# and this compares like with like).
	if not (float(f03["look"]) - float(f33["look"]) > 6.0):
		return _fail(("⭐⭐ THE PAYLOAD: slice 28's boresight-characterized compensator must demand " +
			"MEASURABLY more window than the SAME GLASS under slice 30's rule (%.3f - %.3f = %.3f deg, " +
			"must exceed 6). Slice 30 shipped `radome_slope_worst` as the aim point that makes a scalar " +
			"compensator unconditionally STABLE; this says the same rule buys back the ENVELOPE") %
			[float(f03["look"]), float(f33["look"]), float(f03["look"]) - float(f33["look"])])
	# ⚠ AND THE CURE-B ARM MUST BE THE QUIET ONE — if the aim point stopped quieting the loop, the
	# excursion collapse above would be some other effect wearing its clothes.
	if not (float(f33["rms"]) < QUIET_RMS_MAX and float(f33["miss"]) < HIT_MAX):
		return _fail(("PHASE CURES: slice 30's aim point must actually QUIET the loop (rms r %.5f < %.1f) " +
			"while hitting (%.3f m)") % [float(f33["rms"]), QUIET_RMS_MAX, float(f33["miss"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE ISOLATION — ⚠⚠ THE PREDICTOR AND THE PREDICTED MUST NOT COME FROM THE SAME RUN.
	print("S33V_ISOLATE  at a FIXED R̂ %+.2f, the windowed arm's rms r FALLS %.2fx (%.5f -> %.5f) while its miss OPENS %.0fx (%.3f -> %.3f m), and its own look_max reads %.3f deg — the post-lock-loss runaway, against the ring's actual %.3f deg" %
		  [float(w18["rhat"]), float(f18["rms"]) / maxf(float(w18["rms"]), 1.0e-9), float(f18["rms"]),
		   float(w18["rms"]), float(w18["miss"]) / maxf(float(f18["miss"]), 1.0e-9), float(f18["miss"]),
		   float(w18["miss"]), float(w18["look"]), float(f18["look"])])
	if not (int(f18["band"]) > 0 and int(w18["band"]) > 0):
		return _fail("PHASE ISOLATION: both arms must have band frames before any band number is quoted (%d, %d)" % [int(f18["band"]), int(w18["band"])])
	if not (float(w18["rms"]) < float(f18["rms"]) and float(w18["miss"]) > float(f18["miss"])):
		return _fail(("PHASE ISOLATION: slice 32's metric inversion must be MEASURED, not assumed — " +
			"losing the measurement CUTS the parasitic feed, so `rms r` must FALL (%.5f -> %.5f) while " +
			"the miss OPENS (%.3f -> %.3f m). This is exactly why a low rms r on a windowed arm cannot " +
			"tell 'this design is stable' from 'the seeker lost lock and stopped driving the loop', and " +
			"why every design in this file is flown TWICE") %
			[float(f18["rms"]), float(w18["rms"]), float(f18["miss"]), float(w18["miss"])])
	if not (float(w18["look"]) > RUNAWAY_LOOK_MIN and float(f18["look"]) < MODEL_VALID_DEG):
		return _fail(("PHASE ISOLATION: and the SAME inversion in the quantity this file predicts WITH — " +
			"the windowed arm's own look_max must be the ~90 deg post-lock-loss runaway (%.3f > %.0f) " +
			"and no read at all of a ring whose actual excursion was %.3f deg. THE PREDICTOR AND THE " +
			"PREDICTED MUST NOT COME FROM THE SAME RUN") %
			[float(w18["look"]), RUNAWAY_LOOK_MIN, float(f18["look"])])
	# ⚠⚠ AND DO NOT IMPORT SLICE 32's ISOLATION — the free RINGING arm saturates its band AND HITS.
	if not (float(f03["aero"]) > 40.0 and float(f03["miss"]) < HIT_MAX):
		return _fail(("PHASE ISOLATION: slice 32's `aero_sat == 0` isolation does NOT transfer and this " +
			"asserts the inversion instead — the FREE ringing arm must saturate a large part of its band " +
			"(%.2f %%) and HIT anyway (%.3f m), which is slice 26's ceiling BOUNDING the cycle. " +
			"Saturation does not discriminate in either direction on this wire; the WINDOW does") %
			[float(f03["aero"]), float(f03["miss"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE REPLAY — class 4a, held seed, bit-identical.
	var d := _pos_max_diff(op["pos"], _res["replay"]["pos"])
	print("S33V_REPLAY   the same wire twice at the held seed: max|Δpos| = %.6f m over %d frames" %
		  [d, mini((op["pos"] as Array).size(), (_res["replay"]["pos"] as Array).size())])
	if not (d <= EXACT):
		return _fail(("REPLAY: two runs of the shipped wire at the same seed must be BIT-IDENTICAL " +
			"(max|Δpos| = %.9f m). Class 4a — the window gates the VALUE and never the DRAW (an " +
			"out-of-window tick still draws `n_az`/`n_el` and DISCARDS them, slice 25's lockstep), and " +
			"the radome adds no draw at all") % d)

	return _pass()

# ⚠⚠ `held` IS NOT BIT-IDENTITY, AND GATE 2 PAID FIVE FAILING ASSERTS TO LEARN IT. A first draft
# inherited slice 32's `cureA.miss === ref.miss` and claimed a window that fits the excursion flies
# the free arm bit-for-bit. IT DOES NOT: every held arm leaves the window in the last metres — first
# out at r = 0.18-8.55 m, at look angles of 21-162 deg — because the LOS unit vector swings through a
# huge angle as r -> 0, and those few coasting ticks perturb the CPA by 5e-13 … 1.4e-7 m. That is the
# very thing the r > 200 m gate exists to exclude. ⇒ THE EXACT CLAIM LIVES ON THE GATED QUANTITIES,
# and the miss carries a tolerance with a measured reason.
# ⚠ `tag` IS NOT DECORATION: this is called from five sites, and a bare helper would report the same
# line number for every one — a proof that cannot say WHICH ARM broke is a weaker proof.
func _held(win: Dictionary, free: Dictionary, tag: String) -> String:
	if not (float(win["out"]) == 0.0):
		return ("HELD FAILED for %s: not one out-of-window frame is permitted on the APPROACH " +
				"(r > 200 m), got %.3f %%") % [tag, float(win["out"])]
	# ⭐ AND THIS IS A TOOTH RATHER THAN A RESTATEMENT OF `out == 0.0`, FOR TWO MEASURED REASONS
	# (advisor asked whether the frame grid could be hiding a perturbation here).
	# (i) IT IS GENUINE BIT-IDENTITY, NOT QUANTIZATION AGREEMENT. `look_max` is accumulated ONLY
	#     inside r > 200 m, and gate 2 measured the held arms' perturbation living at r = 0.18-8.55 m
	#     — INSIDE the endgame, i.e. OUTSIDE this window. So on the gated segment the two arms really
	#     are the same trajectory, and both sample the SAME emit-grid indices, so a difference would
	#     appear at the same frame rather than being rounded away. (That is also why the MISS below
	#     needs a tolerance and this does not: the miss is measured where the perturbation lives.)
	# (ii) IT CLAIMS SOMETHING `out` CANNOT. `out == 0.0` says the PREDICATE never fired; this says
	#     the window had NO OTHER EFFECT. They coincide only because `seeker_fov_deg` couples to the
	#     flight through exactly one gate — which is the invariant worth pinning, since a future
	#     second coupling (a window-dependent noise or gain) would leave `out` at 0.0 and drift this.
	if not (absf(float(win["look"]) - float(free["look"])) <= EXACT):
		return ("HELD FAILED for %s: it must fly the FREE arm's own excursion (%.6f vs %.6f deg). If " +
				"these differ, the window PERTURBED the trajectory it was supposed to merely contain, " +
				"and the excursion is no longer a property of the ring alone") % [tag, float(win["look"]), float(free["look"])]
	# ⚠ A NAMED TOLERANCE WITH A MEASURED REASON, deliberately NOT tightened to the 1.4e-7 m gate 2
	# measured: the endgame perturbation is a PHYSICAL quantity that legitimately moves with the wire,
	# and a tripwire that fires on a benign retune is worse than a bound that says what it is.
	if not (absf(float(win["miss"]) - float(free["miss"])) < 1.0e-6):
		return ("HELD FAILED for %s: the miss must match the free arm's to within the endgame " +
				"perturbation (%.9f vs %.9f m)") % [tag, float(win["miss"]), float(free["miss"])]
	# ⭐ AND THE SIGNED BUDGET MUST HAVE STAYED NON-NEGATIVE ON THE APPROACH — slice 33's one new
	# number, asserted as the thing whose SIGN IS THE VERDICT (slice 18's `terrain_clearance_m`).
	if not (float(win["marg"]) >= 0.0):
		return ("HELD FAILED for %s: the shipped budget `seeker_fov_margin_deg` must never go negative " +
				"on the approach (floor %.3f deg). Its SIGN IS THE VERDICT — that is why the key exists " +
				"and why the client never re-derives the test") % [tag, float(win["marg"])]
	return ""

# --- the scan -------------------------------------------------------------------------------

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_turned = false
	_n_gate = 0
	_n_out = 0
	_max_look = 0.0
	_min_marg = 1.0e30
	_n_band = 0
	_n_aero = 0
	_n_defl = 0
	_sum_r2 = 0.0
	_max_y = 0.0
	_t_break = -1.0
	_r_break = -1.0
	_worst = 0.0
	_fov_seen = 0.0
	_rhat_seen = 0.0
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
		if tel.has(MID + ".seeker_fov_deg"):
			_fov_seen = float(tel[MID + ".seeker_fov_deg"])
		if tel.has(MID + ".radome_slope_est"):
			_rhat_seen = float(tel[MID + ".radome_slope_est"])
		if tel.has(MID + ".radome_slope_worst"):
			_worst = float(tel[MID + ".radome_slope_worst"])
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				if not mpos.is_empty():
					_max_y = maxf(_max_y, absf(float(mpos[1])))
				# WINDOW 1 — the look-angle / budget / out-of-window window, RANGE-GATED at r > 200 m.
				# ⚠ Ungated, the endgame LOS swing makes a QUIET arm read a few hundredths of a percent
				# out and its look_max read 21-162 deg (slice 32's reason, and gate 2's five asserts).
				if r > 200.0:
					_n_gate += 1
					_max_look = maxf(_max_look, float(tel.get(MID + ".look_angle", 0.0)))
					_min_marg = minf(_min_marg, float(tel.get(MID + ".seeker_fov_margin_deg", 1.0e30)))
					if float(tel.get(MID + ".seeker_valid", 1.0)) < 0.5:
						_n_out += 1
						if _t_break < 0.0:
							_t_break = float(f.get("t", -1.0))
							_r_break = r
				# WINDOW 2 — the ISOLATION band, 28/29/30/31's [500, 3000] m, inherited with its
				# reasons (a crossing wire's whole-approach rms r carries a legitimate front-loaded
				# launch transient, and arms with different ToF would compare different parts of the
				# engagement). ⚠ THE CHANNEL IS YAW: the lead is in AZIMUTH on this crossing geometry,
				# so the yaw channel sits on the steep part of the slope curve while pitch sits near
				# the boresight slope — slice 28's channel finding, and a `q` metric would meter the
				# quiet channel of a shaking missile.
				if r > 500.0 and r < 3000.0:
					_n_band += 1
					var rr := float(tel.get(MID + ".omega_r", 0.0))
					_sum_r2 += rr * rr
					if float(tel.get(MID + ".aero_sat", 0.0)) > 0.5:
						_n_aero += 1
					if float(tel.get(MID + ".defl_sat", 0.0)) > 0.5:
						_n_defl += 1
			_prev_los = r
		last_t = float(f.get("t", -1.0))
	if last_t < 0.0:
		return false
	return last_t >= _t_target - 0.5 * _dt

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
	if not bool(f.get("airframe_view", false)):
		return "a slice-33 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-33 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	# ⭐⭐ THE FIRST WIRE IN THE PROJECT TO RAISE BOTH MARKERS, AND BOTH ARE ASSERTED. Slice 32's own
	# gate-3 testset asserts `!haskey(info, :radome_view)` on ITS wire AS A FEATURE — the radome was
	# off it by design (convention 9). Here the COMPOSITION IS the lesson, so both ship, and the client
	# takes a branch that exists only for this case: without it `_seeker_fov_view` wins and prints
	# slice 32's LEAD-vs-window verdict, which on this wire reads "IN THE WINDOW — FOV holds the lead"
	# on the arm that misses by 3.7 km (the lead is ~18.1 deg inside a 21 deg window — the lead never
	# outgrew the window, THE RING did), while the entire radome cascade goes undrawn.
	if not bool(f.get("seeker_fov_view", false)):
		return "a slice-33 handshake must ship seeker_fov_view=true — half of the composition, and the marker that DROPS the shared button"
	if not bool(f.get("radome_view", false)):
		return "a slice-33 handshake must ship radome_view=true — the OTHER half. This is the first wire in the project to raise both, and the client's composition HUD branch keys off exactly that conjunction"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-33 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS a look angle at all, and the loader refuses `seeker_fov_deg` without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-33 scenario must HOLD :airframe at six_dof — BOTH halves are inert without it, and the gate is on the LIVE rung, never on :att_q, which is minted once and never deleted. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-33 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-33 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-33 scenario must HOLD :seeker at :filtered — the alpha-beta tracker is what COASTS when the measurement stops, and the coast is half the mechanism. Got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-33 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the aero ceiling 93.2% of its approach, a THIRD mechanism on a wire convention 9 is already stretched to two)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-33 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	# ⭐⭐ TWO KNOBS — the two halves of ONE comparison, `fov` vs `excursion(R̂)`. Convention 9 is
	# satisfied BY MEASUREMENT (the slice-27 DIAGONAL precedent): move both together and `held` does
	# not change. ⚠ STATED AS TRACKING, NEVER AS `fov = ceil(excursion(R̂))` — seam discipline 2.
	if not keys.has("seeker_fov_deg"):
		return "slice-33 handshake must expose the 'seeker_fov_deg' slider — the HARDWARE side, and CURE A"
	if not keys.has("radome_slope_est"):
		return "slice-33 handshake must expose the 'radome_slope_est' slider — the DESIGN side, and CURE B: the belief is the only thing an engineer can change, since the glass is hardware"
	if str(keys["seeker_fov_deg"]) != MID or str(keys["radome_slope_est"]) != MID:
		return "both knobs must target the interceptor '%s' — unlike slices 30/32, neither half of this comparison lives on the target" % MID
	if keys.size() != 2:
		return "slice-33 must expose EXACTLY TWO knobs (got %d) — the budget and the ring that spends it" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate").
	if keys.has("cross_speed_mps"):
		return "slice-33 must NOT expose 'cross_speed_mps' — it is slice 32's OWN axis (it moves the LEAD), and on this wire it would be a THIRD mechanism beside the ring and the window (convention 9, which the composition already stretches to two)"
	if keys.has("af_alpha_max") or keys.has("alpha_max"):
		return "slice-33 must NOT expose an 'alpha_max' knob — it is slice 26's instrument for the ring's AMPLITUDE and a confounded lever (slice 20 disqualified it for the induced-drag bill). It is the gate-0 CAUSATION PROBE and is HELD on the shipped wire"
	if keys.has("radome_slope") or keys.has("radome_ripple") or keys.has("radome_ripple_k"):
		return "slice-33 must NOT expose the GLASS itself — a radome's slope curve is HARDWARE, and the whole arc's point since slice 27 is that what an engineer can change is what they BELIEVE about it. `radome_ripple_k` is additionally disqualified by non-monotonicity (slice 28)"
	if keys.has("n_pn"):
		return "slice-33 must NOT expose an 'n_pn' knob — it moves the parasitic boundary (N·|R − R̂|/ρ) AND the guidance loop (the confounded-lever rule, 26/27/28/29/30/31/32)"
	if keys.has("rho"):
		return "slice-33 must NOT expose a 'rho' knob — it moves the parasitic boundary and the aero ceiling at once"
	if keys.has("sigma_seek"):
		return "slice-33 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it (26-32's reasoning, unchanged)"
	if keys.has("elevation_deg"):
		return "slice-33 must NOT expose 'elevation_deg' — TWICE disqualified: the slice-19 DEAD-knob class (position and attitude are built once at LOAD and `reset` re-reads the YAML), AND slice 32's P5 found it is what sets this wire's never-acquires floor, so a slider on it would measure the LAUNCHER"
	if keys.has("speed"):
		return "slice-33 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
	return ""

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

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	# ⚠ EVERY NUMBER HERE IS INTERPOLATED FROM WHAT THIS RUN MEASURED (the slice-21/25 gate-3 bug,
	# fixed structurally rather than by care).
	var f03: Dictionary = _res["f03"]
	var f18: Dictionary = _res["f18"]
	var f33: Dictionary = _res["f33"]
	var op: Dictionary = _res["open"]
	var w18: Dictionary = _res["w18"]
	var cA: Dictionary = _res["cureA"]
	var cB: Dictionary = _res["cureB"]
	var bnd: Dictionary = _res["band"]
	var blo: Dictionary = _res["brlo"]
	print(("S33V OK: slices 26-31 each recorded, as a standing fact, that THE RINGING ARM STILL HITS — " +
		"slice 26 wrote it first and 27/28/29/30/31 each inherited it, which is why the whole family " +
		"measures rms q / rms r and not a miss. It is true here too: at the FOV slider's ceiling the " +
		"boresight-characterized compensator rings at rms r %.5f — %.0fx the %.5f slice 30's rule " +
		"leaves — and still lands %.3f m from the target. THE RING WAS BENIGN BECAUSE THE SEEKER HAD AN " +
		"INFINITE WINDOW. ⭐⭐ Give it a real one and the SAME design, the SAME glass and the SAME seed " +
		"loses the track at t = %.3f s / r = %.1f m — WHILE THE LEAD IS STILL BUILDING — spends %.3f %% " +
		"of its approach outside the window, drives the shipped budget seeker_fov_margin_deg down to " +
		"%.2f deg, and misses by %.1f m (%.0fx). ⇒ A LIMIT CYCLE YOU WERE TOLD TO MEASURE IN rad/s IS " +
		"SPENT IN DEGREES OF FIELD OF VIEW: the ring costs you not accuracy but the ENVELOPE. ⭐ THE " +
		"FOV A SEEKER NEEDS IS THE ENGAGEMENT'S LEAD PLUS THE PARASITIC LOOP'S EXCURSION, and the " +
		"second term is continuous and monotone in the ring — %.3f / %.3f / %.3f / %.3f deg as R̂ walks " +
		"from slice 30's rule to slice 28's boresight characterization. ⭐⭐ THE PREDICATE, BRACKETED " +
		"AGAINST THE MEASURED ANGLE AND NEVER `ceil`: a window %.1f deg under the excursion BREAKS " +
		"(%.3f %% out, %.1f m) and %.1f deg over HOLDS and flies the free arm's own excursion to the " +
		"bit. ⭐ TWO THRESHOLDS, NOT ONE — `held` and `hits` are different predicates: %.3f deg under, " +
		"the seeker leaves the window for %.3f %% of the approach and still lands %.1f m out, losing " +
		"lock at r = %.1f m NEAR CPA, where the %.1f deg cell loses it at r = %.1f m with the lead " +
		"still building. ⭐⭐ AND THE PAYLOAD IS THAT SLICE 30's RULE IS AN ENVELOPE RULE, NOT ONLY A " +
		"STABILITY RULE: aim R̂ at the wire's own radome_slope_worst = %.4f and the requirement falls " +
		"from %.3f to %.3f deg — the radome-free engagement's own number — so the same glass flies the " +
		"same 21 deg window at %.3f m. TWO CURES, ONE SLIDER EACH: widen the seeker to %.0f deg " +
		"(%.3f m) or stop the bill being charged. ⚠⚠ THE PREDICTOR AND THE PREDICTED NEVER COME FROM " +
		"THE SAME RUN, and this file is STRUCTURED that way: on a windowed arm rms r FALLS %.2fx while " +
		"the miss OPENS %.0fx, and its own look_max reads %.3f deg — the post-lock-loss runaway — " +
		"against the ring's actual %.3f deg. ⚠ THE ISOLATION IS NOT SLICE 32's AND INVERTS: the free " +
		"ringing arm saturates %.2f %% of its band AND HITS (slice 26's ceiling BOUNDING the cycle) " +
		"while the broken arm saturates none and misses by kilometres — saturation discriminates in " +
		"neither direction here, the WINDOW does; what IS invariant is defl_sat = 0 on every arm. " +
		"⚠ The badly broken arm's band is EMPTY (%d frames), so its rms r is UNDEFINED rather than " +
		"quiet. ⚠ NO new rung, knob, instability, cap or draw — both halves already flew and both " +
		"sliders already shipped; what is new is the COMPOSITION, the one number that measures it, and " +
		"the design rule it yields. Class 4a, the NINTH consecutive RNG-live slice, replay " +
		"bit-identical.")
		% [float(f03["rms"]), float(f03["rms"]) / maxf(float(f33["rms"]), 1.0e-9), float(f33["rms"]),
		   float(f03["miss"]),
		   float(op["tbrk"]), float(op["rbrk"]), float(op["out"]), float(op["marg"]),
		   float(op["miss"]), float(op["miss"]) / maxf(float(f03["miss"]), 1.0e-9),
		   float(f33["look"]), float(_res["f24"]["look"]), float(f18["look"]), float(f03["look"]),
		   BRACKET, float(blo["out"]), float(blo["miss"]), BRACKET,
		   BAND_OFF, float(bnd["out"]), float(bnd["miss"]), float(bnd["rbrk"]), BRACKET, float(blo["rbrk"]),
		   float(cB["rhat"]), float(f03["look"]), float(f33["look"]), float(cB["miss"]),
		   FOV_CURE, float(cA["miss"]),
		   float(f18["rms"]) / maxf(float(w18["rms"]), 1.0e-9),
		   float(w18["miss"]) / maxf(float(f18["miss"]), 1.0e-9), float(w18["look"]), float(f18["look"]),
		   float(f03["aero"]), int(op["band"])])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S33V FAIL: " + msg)
	print("S33V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
