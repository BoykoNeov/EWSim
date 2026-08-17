extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-38 gate-3 verifier — AN IMPERFECT HEAD GYRO: SLICE 37's MARGIN IS A GYRO SPEC.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice38_head_gyro.yaml
#   godot --headless --path clients/godot --script res://net/slice38_verify.gd     (exit 0 = pass)
#
# THE LESSON. Slice 37 showed that stabilizing the seeker head in space REMOVES stability margin,
# because the position servo's LAG had been quietly low-passing the missile's own body motion out of
# the radome's INDEX. That result rests entirely on a PERFECT gyro: the shipped stabilized head
# rejects body motion at EXACTLY unity gain at every frequency, because the model simply STORES the
# inertial angles. Give the gyro a scale-factor error and the rejection LEAKS — a fraction `|s|` of
# the body motion comes back into the index — and slice 37's stability boundary WALKS with gyro
# quality. ⇒ THE TWO ARCHITECTURES SLICE 37 SHIPPED AS A BUTTON ARE THE TWO ENDS OF ONE HARDWARE
# SPEC, and A WORSE GYRO IS A MORE STABLE MISSILE.
#
# ⚠⚠ THE HEADLINE — the onset bracket walking from slice 37's own SPACE bracket to its own BODY one —
# IS NOT MEASURED HERE, AND THAT IS DELIBERATE (the slice-27/28 precedent, stated rather than
# implied): it needs `radome_slope_est`, which is AUTHORED on this wire and not a knob, so it is NOT
# CLIENT-DRIVABLE. It lives in `test_missile.jl`, which flies four cells of it on the shipped seam,
# and in full in `docs/plans/slice38.md`. What this file proves is the SLIDER's own claim on the
# shipped wire, at the design where the slider decides the verdict.
#
# ⭐⭐ THE SHOWCASE IS ONE SLIDER, AND IT RUNS THE WRONG WAY ROUND ON PURPOSE. The wire opens on the
# PERFECT gyro (s = 0) — slice 37's "improvement", fully stabilized — and it RINGS. Drag the slider
# to a −5 % scale factor, an ordinary cheap-MEMS part, and the SAME missile with the SAME glass, the
# SAME believed slope and the SAME seed goes QUIET. Nobody buys a bad gyro on purpose; the design
# rule is that slice 37's margin has to be BUDGETED against the sensor that maintains it.
#
# ⚠⚠ AND THE SLIDER IS **INERT ON THE OTHER SIDE OF THE BUTTON**, WHICH IS ASSERTED AS BIT-IDENTITY.
# A body-referenced head has no stabilization gyro to corrupt, so on that rung every value of this
# slider flies the SAME missile. A live control that does nothing is the stale-readout class in a NEW
# form — not a stale number but a DEAD KNOB — which is why `gimbal_gyro_view`'s HUD names the state,
# and why this file measures it as `max|Δpos| == 0.0` rather than describing it.
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`) and every constant is sized off a FRAME column
# ([[ewsim-missile-verifier-sampling]] — the error is ASYMMETRIC: a MISS samples faithfully, a HIT
# samples COARSELY). `rms r` is frame-robust (slice 26 measured it, which is why this family uses it).
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — the one slider and the head both live here

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16). The server emits every 16th tick,
# so a STEPS that is not a multiple makes the last frame land BELOW `STEPS*dt` and `_drain_scan` waits
# forever, SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 12800 = 16 * 800.
# ⚠ SIZED OFF THE SLOWEST ARM, MEASURED: ToF spans 10.98 s (the ceiling) to 11.28 s (the aim point on
# the stabilized rung). 12.8 s leaves ~1.5 s of headroom, and EVERY arm asserts it REACHED CPA rather
# than trusting the sizing.
const STEPS := 12800
const PRESS_AT := 6400            # the MID-RUN press tick — also a multiple of 16, for the same reason

const BODY := "body_referenced"
const SPACE := "space_stabilized"

# THE R̂ SLIDER. The DEFAULT is slice 34's own shipped design, where the body-referenced head is QUIET
# and the space-stabilized one RINGS — the showcase, and the only place a single press is dramatic.
# THE SLIDER — the head gyro's SCALE-FACTOR error `s`, dimensionless (−0.05 = the gyro reads 5 % LOW).
# The DEFAULT is a PERFECT gyro, which is slice 37's own space-stabilized rung EXACTLY, and on this
# wire's design (R̂ = −0.20, AUTHORED) it RINGS. That is what makes a single drag dramatic.
const S_DEF := 0.0
const S_CURE := -0.05             # a real cheap-MEMS part — and it QUIETS the same missile
# The ladder's other cells, spanning the domain. ⚠ The transition is a SINGLE step between −0.03 and
# −0.05, so both sides of it are flown.
const S_CEIL := 0.10              # an OVER-reading gyro: over-rejects, and rings HARDER than perfect
const S_002 := 0.02
const S_M01 := -0.01
const S_M02 := -0.02
const S_M03 := -0.03
const S_M08 := -0.08
const S_FLOOR := -0.20            # the ring has reached its PLATEAU — the measured reason to stop

# ⚠ THE ARC's RING LINE, AND IT IS USED ONLY WHERE THE TWO SIDES DIFFER BY MORE THAN AN ORDER OF
# MAGNITUDE (the showcase). The ladder's own bracket is established by the largest-step rule instead —
# slice 37's gate-0 advisor catch, inherited with its reason.
const RING := 0.30
# A SANITY BOUND, NOT THE METRIC. Every arm on this wire HITS — the arc's standing fact since slice
# 26, and the reason the verdict is `rms r` and never a miss.
const HIT_MAX := 40.0
const WIN_AUTH := 25.0            # the AUTHORED detector window (not a knob here)
const STOP_AUTH := 30.0           # the AUTHORED mechanical stop
const RATE_AUTH := 40.0           # the AUTHORED servo — slice 35's slider, held here
const RHAT_AUTH := -0.20          # the AUTHORED design — slice 37's slider, held here
const MODEL_VALID_DEG := 30.0     # the small-angle bend budget 28-37 each declared
const EXACT := 1.0e-9


var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
var _pending_press := ""          # the mid-run arm's second leg (see `_launch_arm`)

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}

# per-arm accumulators — ALL CLOSING-LEG ONLY (past CPA the target is BEHIND the missile and every
# angle here is meaningless; slice 32's gate-3 correction, inherited with its reason)
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0                  # closing frames with r > 200 m — the angle / window window
var _n_out := 0                   # …of which the head had NO error signal
var _max_head := 0.0              # the head's TRAVEL (vs the STOP) — slice 33's excursion, RESTATED
var _max_off := 0.0               # the head's TRACKING ERROR, WHOLE APPROACH — what the window must clear
var _min_marg := 1.0e30           # the SIGNED detector budget — THE SIGN IS THE VERDICT
var _n_band := 0                  # closing frames with 500 < r < 3000 — the isolation window
var _off_band := 0.0
var _n_sat := 0                   # …frames where the SERVO's rate limit BOUND (the core's own flag)
var _dems: Array = []             # …the PRE-LIMIT demanded head rate, deg/s (percentiles, never a peak)
var _n_zero_dem := 0
var _n_aero := 0
var _n_defl := 0
var _sum_r2 := 0.0                # for rms r — the RING (yaw: the lead is in AZIMUTH here)
var _rhat_seen := 0.0
# SLICE 38 — the SLIDER's own value, READ OFF THE WIRE rather than trusted from the `set_param`
# that was sent. That is the difference between proving the slider MOVED THE PHYSICS and proving a
# command was accepted (slice 19's not-a-dead-knob tripwire, and slice 35's re-taken shot: a raw
# `set_param` can move the physics while a label keeps the old number, and the inverse is just as
# possible).
var _s_seen := 0.0
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _worst := 0.0                 # slice 30's aim point, READ OFF THE WIRE (never recomputed)
var _pos_trace: Array = []

func _initialize() -> void:
	print("S38V_INIT godot=", Engine.get_version_info().string)
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
		_launch_arm()
		return false

	if not _drain_scan():
		return false
	# ⭐⭐ THE MID-RUN ARM'S SECOND LEG — THE BUTTON PRESS AT A NAMED TICK, and it must be sent HERE
	# rather than queued with the first `step`. The server DRAINS EVERY QUEUED COMMAND BEFORE IT STEPS
	# AT ALL (`_serve_session!`'s loop), so [step K, set_fidelity, step N-K] sent back-to-back applies
	# the toggle at tick 0 and silently measures a from-launch arm instead. The first leg must be
	# FLOWN before the press is sent.
	if _pending_press != "":
		var rung := _pending_press
		_pending_press = ""
		_client.send({"type": "set_fidelity", "key": "seeker_head", "value": rung})
		_t_target = STEPS * _dt
		_client.send({"type": "step", "n": STEPS - PRESS_AT})
		return false
	var aerr := _finish_arm()
	if aerr != "":
		return _fail(aerr)
	if _idx + 1 >= _arms.size():
		return _verdict()
	_launch_arm()
	return false

# --- the flight plan ------------------------------------------------------------------------

func _build_arms() -> void:
	# 1) ⭐⭐ THE SHOWCASE — ONE SLIDER ON A DESIGN THAT WAS ALREADY BAD, and its REPLAY at BOTH ends
	#    (class 4a: the seed is LOAD-BEARING, and a replay proven at only one slider value would leave
	#    the drift branch unproven exactly where it does its work).
	_arms.append({"tag": "open", "s": S_DEF})
	_arms.append({"tag": "replay", "s": S_DEF})
	_arms.append({"tag": "cure", "s": S_CURE})
	_arms.append({"tag": "cure_rep", "s": S_CURE})
	# 2) ⭐ THE LADDER over the slider's whole domain. ⚠ These exist to establish MONOTONICITY and the
	#    transition's bracket by the LARGEST-STEP rule; nothing here compares an `rms r` to a threshold.
	for sv in [S_CEIL, S_002, S_M01, S_M02, S_M03, S_M08, S_FLOOR]:
		_arms.append({"tag": "s%d" % int(round(1000.0 * sv)), "s": sv})
	# 3) ⭐⭐ THE SLIDER IS INERT ON THE OTHER SIDE OF THE BUTTON — the client HUD's own finding, and it
	#    is asserted as BIT-IDENTITY rather than described. A body-referenced head has no stabilization
	#    gyro to corrupt, so these two arms must be the SAME MISSILE to the last bit.
	_arms.append({"tag": "inert0", "s": S_DEF, "rung": BODY})
	_arms.append({"tag": "inert20", "s": S_FLOOR, "rung": BODY})
	# 4) ⭐ THE PRESS ITSELF, MID-FLIGHT — the button is slice 37's and it is LIVE here, so the one
	#    thing gates 0-2 could not cover is the actual `set_fidelity` reaching the rung boundary at an
	#    arbitrary tick. Pressed on the RINGING arm, it must quiet it: the body-referenced rung has no
	#    gyro leak at all, which is the same fact as phase INERT told from the other direction.
	_arms.append({"tag": "midpress", "s": S_DEF, "press": BODY})


func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `space_stabilized` and the slider
	# to its authored 0.0 every arm — each arm must re-send its own. That is exactly what makes these
	# arms the CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", SPACE)) != SPACE:
		_client.send({"type": "set_fidelity", "key": "seeker_head", "value": str(arm["rung"])})
	# ⚠ SENT ON EVERY ARM INCLUDING THE DEFAULT ONE, so that the `open` arm proves the SLIDER's own
	# path to its authored value rather than merely inheriting it from the YAML.
	_client.send(_set_param_cmd(MID, "head_gyro_scale_err", float(arm["s"])))
	if arm.has("press"):
		# TWO LEGS — see `_process`. Fly to the press tick FIRST, then press, then fly the rest.
		_pending_press = str(arm["press"])
		_t_target = PRESS_AT * _dt
		_client.send({"type": "step", "n": PRESS_AT})
	else:
		_t_target = STEPS * _dt
		_client.send({"type": "step", "n": STEPS})


# Record the arm, and assert the invariants that must hold on EVERY arm.
func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var out_pc: float = 100.0 * float(_n_out) / maxf(float(_n_gate), 1.0)
	# ⚠⚠ NaN, NOT 0.0, WHEN THE BAND IS EMPTY — slice 33's gate-2 finding, inherited: a `sum/max(n,1)`
	# would print a beautifully quiet `rms r = 0.00000` COMPUTED FROM ZERO SAMPLES on exactly the arm
	# where it is undefined.
	var rms := NAN if _n_band == 0 else sqrt(_sum_r2 / float(_n_band))
	var sat_pc := NAN if _n_band == 0 else 100.0 * float(_n_sat) / float(_n_band)
	var aero_pc := NAN if _n_band == 0 else 100.0 * float(_n_aero) / float(_n_band)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		"head": _max_head, "off": _max_off, "offb": _off_band,
		"marg": NAN if _min_marg > 1.0e29 else _min_marg,
		"band": _n_band, "aero": aero_pc, "defl": _n_defl, "rms": rms, "sat": sat_pc,
		"dem95": _pct(_dems, 0.95), "rhat": _rhat_seen, "s": _s_seen,
		"rung": str(arm.get("rung", SPACE)),
		"win": _win_seen, "stop": _stop_seen, "rate": _rate_seen, "worst": _worst,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	# ⭐ THE NOT-A-DEAD-KNOB TRIPWIRE (slice 19's, inherited and load-bearing here): the value the arm
	# FLEW is read back off the wire and compared against the one it SENT. A slider that is accepted
	# and then ignored would otherwise produce a perfectly clean, perfectly flat ladder — and this
	# slice's whole subject is a key that IS legitimately inert on the other rung, so "it did nothing"
	# is a reading this file has to be able to tell apart from "it never arrived".
	if str(arm.get("rung", SPACE)) == SPACE and absf(_s_seen - float(arm["s"])) > EXACT:
		return ("arm %s: the wire flew head_gyro_scale_err = %+.6f but the arm sent %+.6f — the slider " +
				"was accepted and not applied") % [tag, _s_seen, float(arm["s"])]
	print(("S38V_ARM   %-9s %-16s s=%+.3f R̂=%+.4f  ->  miss=%.3f  rms_r=%.5f  demand_p95=%.3f deg/s  " +
		   "sat_band=%.2f%% (%d band frames)  off_band=%.3f  off_max=%.3f  head_max=%.3f  " +
		   "margin_min=%.2f  out=%.3f%% of %d gated  aero=%.2f%%  defl=%d  cpa=%s") %
		  [tag, m["rung"], m["s"], m["rhat"], m["miss"], m["rms"], m["dem95"], m["sat"], m["band"],
		   m["offb"], m["off"], m["head"], m["marg"], out_pc, m["gate"], m["aero"], m["defl"],
		   "Y" if m["turned"] else "N"])
	if not (_n_gate > 100):
		return ("arm %s: the r > 200 m window must contain frames to measure (got %d) — every angle, " +
				"budget and out-of-window assert on this arm would be vacuous") % [tag, _n_gate]
	if not (_n_band > 100):
		return ("arm %s: the [500, 3000] m band must contain frames (got %d) — rms r, sat_band and the " +
				"demand percentile are ALL band quantities, and slice 33's gate-2 catch was exactly a " +
				"band metric computed from zero samples") % [tag, _n_band]
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was still " +
				"closing at the end, so its miss (%.3f m) is a last closing range and not a CPA. ToF " +
				"spans 10.98-11.28 s across this file, so STEPS is sized off the SLOWEST arm and every " +
				"arm asserts this rather than trusting the sizing") % [tag, STEPS, _min_los]
	# ⚠⚠ THE DETECTOR WINDOW MUST NEVER BITE, ON ANY ARM, AND THIS IS THE LOAD-BEARING PRECONDITION OF
	# THE WHOLE FILE rather than a hygiene check. `rms r`, `head_off_deg`, `head_angle_deg` and
	# `head_rate_sat` are ALL meaningless on a windowed arm (the two-run discipline, five quantities as
	# of gate 2's hold-branch finding): a broken window FREEZES the head's index, a frozen index makes
	# a CONSTANT bend, and a constant bend is QUIET AT EVERY R̂ — so the ring would FALL and the servo
	# would read FREE, both of which look like good news. This slice reads a RING VERDICT on every arm
	# it flies, so every arm must clear it.
	if not (out_pc == 0.0):
		return ("arm %s: THE DETECTOR WINDOW MUST NEVER BITE (%.3f %% of gated frames out). It is " +
				"AUTHORED at %.1f deg against a worst whole-approach requirement of 5.391 deg measured " +
				"over the whole slider on both rungs, precisely so that every `rms r` here is a " +
				"STABILITY read. A windowed arm freezes the index, and a frozen index is QUIET at " +
				"every R̂ — the ring would fall and the servo would read free") % [tag, out_pc, WIN_AUTH]
	if not (_max_off < _win_seen):
		return (("arm %s: the whole-approach tracking error (%.3f deg) must stay inside the authored " +
				"window (%.3f deg) — the same claim as the line above measured as an ANGLE rather than " +
				"as a count, so a single-frame excursion cannot hide inside a rounded percentage") %
				[tag, _max_off, _win_seen])
	# ⚠ AND THE MECHANICAL STOP MUST NOT BIND EITHER, or the two limits stop being separable: a clamped
	# head cannot reach the LOS, so its deficit is charged to the DETECTOR budget (slice 34's gate 2).
	# ⚠⚠ IT MATTERS MORE ON THIS WIRE THAN ON SLICE 35's: gate 2 measured that the STOP CAN BIND WHILE
	# A SPACE-STABILIZED HEAD IS HOLDING — the body rotates under it and re-clamps it continuously,
	# which is a state only this rung can produce. No LADDER arm here reaches it (worst 21.4 of 30).
	if not (_max_head < _stop_seen and _max_head < MODEL_VALID_DEG):
		return (("arm %s: the head's travel (%.3f deg) must stay inside BOTH the mechanical stop (%.3f " +
				"deg) and the small-angle bend budget 28/29/30/31 each declared (%.0f deg)") %
				[tag, _max_head, _stop_seen, MODEL_VALID_DEG])
	# ⭐ THE AMBIGUOUS ZERO, COUNTED — the two-run discipline's FOURTH quantity, measured rather than
	# described. A demand of EXACTLY 0.0 is the HANDOVER tick or a head HOLDING with no error signal,
	# and it carries a flag of 0.0 with it. ⚠⚠ AND THIS ASSERT SITS BESIDE THE WINDOW GATE ABOVE ON
	# PURPOSE (gate 2's advisor CATCH 2): a `sat == 0` claim without `out == 0` beside it is the one
	# place the two-run discipline can be asserted IN THE DIRECTION THAT HIDES ITS OWN FAILURE.
	if not (_n_zero_dem == 0):
		return (("arm %s: %d of %d band frames shipped a demand of EXACTLY 0.0 — the ambiguous state (a " +
				"HANDOVER tick, or a head HOLDING with no error signal). Every band statistic here " +
				"would then be averaging a servo together with a head that was not slewing at all") %
				[tag, _n_zero_dem, _n_band])
	# ⚠ THE ISOLATION IS `defl_sat`, NOT `aero_sat` — slice 33's inversion, inherited with its warning
	# and LOUD on this wire: the space-stabilized arms run 44-64 % aero-saturated AND STILL HIT (slice
	# 26's ceiling BOUNDING the cycle), so `aero_sat` discriminates in NEITHER direction here.
	if not (_n_defl == 0):
		return ("arm %s: `defl_sat` must be EXACTLY 0 (got %d) — with the fin out of authority the " +
				"engagement stops being about the head at all") % [tag, _n_defl]
	# THE AUTHORED THREE, ON EVERY ARM: nothing in this file touches them, and that is the point.
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH and _rhat_seen == RHAT_AUTH):
		return (("arm %s: the window / stop / servo must be the AUTHORED %.1f / %.1f / %.1f (got %.3f / " +
				"%.3f / %.3f) and the design the AUTHORED %+.3f (got %+.3f) — this wire's ONE slider " +
				"is the head gyro and its ONE control is the button") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, _win_seen, _stop_seen, _rate_seen,
				 RHAT_AUTH, _rhat_seen])
	if not (_min_los < HIT_MAX):
		return (("arm %s: every arm on this wire HITS on BOTH rungs (%.3f m, must be < %.1f) — the arc's " +
				"standing fact since slice 26, and the reason the verdict is rms r and never a miss. " +
				"If this fires, the ring has started costing accuracy and the metric is wrong") %
				[tag, _min_los, HIT_MAX])
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var op: Dictionary = _res["open"]
	var rp: Dictionary = _res["replay"]
	var cu: Dictionary = _res["cure"]
	var cur: Dictionary = _res["cure_rep"]
	var i0: Dictionary = _res["inert0"]
	var i20: Dictionary = _res["inert20"]
	var mp: Dictionary = _res["midpress"]

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE CURE — ⭐⭐ ONE SLIDER, AND IT RUNS THE WRONG WAY ROUND. Same glass, same believed slope,
	# same servo, same handover, same seed; the ONLY variable is how good the head's gyro is.
	var ratio: float = float(op["rms"]) / maxf(float(cu["rms"]), 1.0e-12)
	print("S38V_CURE     THE SHOWCASE, and it is ONE SLIDER: at the AUTHORED design R̂ %+.2f a PERFECT head gyro (s %+.3f) RINGS at rms r %.5f, and a −5 %% scale factor — an ordinary cheap-MEMS part — makes the SAME missile, SAME glass, SAME believed slope, SAME seed, QUIET at %.5f — %.1fx. Both HIT (%.3f / %.3f m). ⇒ A WORSE GYRO IS A MORE STABLE MISSILE: slice 37's margin is a GYRO SPEC" %
		  [float(op["rhat"]), float(op["s"]), float(op["rms"]), float(cu["rms"]), ratio,
		   float(op["miss"]), float(cu["miss"])])
	if not (float(op["rms"]) > RING and float(cu["rms"]) < RING):
		return _fail(("⭐⭐ PHASE CURE: the two slider values must land on OPPOSITE SIDES of the arc's " +
			"%.2f ring line at the SAME design (%.5f at s %+.3f, %.5f at s %+.3f). ⚠ The line is used " +
			"HERE ONLY, where the two sides differ by more than an order of magnitude — the ladder's " +
			"bracket below is established by the largest-step rule, because slice 37's gate-0 advisor " +
			"catch was exactly a chosen threshold doing load-bearing work") %
			[RING, float(op["rms"]), float(op["s"]), float(cu["rms"]), float(cu["s"])])
	if not (ratio > 25.0):
		return _fail(("⭐⭐ PHASE CURE: the slider must move the ring by a factor worth a lesson " +
			"(%.1fx, must exceed 25). Measured 32.5x per tick at this design") % ratio)
	if not (float(op["miss"]) < HIT_MAX and float(cu["miss"]) < HIT_MAX):
		return _fail(("PHASE CURE: BOTH arms must HIT (%.3f / %.3f m) — the miss is NOT the metric " +
			"here and the slice would be misread if the ringing arm also missed") %
			[float(op["miss"]), float(cu["miss"])])
	# ⚠ AND THE CURE IS NOT A RE-DESIGN: the believed slope the two arms fly is bit-identical, so
	# nothing about the compensator changed. This is what stops the headline being read as slice 37's.
	if not (float(op["rhat"]) == float(cu["rhat"]) and float(op["rhat"]) == RHAT_AUTH):
		return _fail(("⭐⭐ PHASE CURE: both arms must fly the IDENTICAL AUTHORED believed slope " +
			"(%+.9f vs %+.9f, authored %+.3f) — the entire claim is that ONLY the head's gyro changed") %
			[float(op["rhat"]), float(cu["rhat"]), RHAT_AUTH])

	# PHASE REPLAY — determinism, AT BOTH ENDS OF THE SLIDER (class 4a, the 14th consecutive RNG-live
	# slice). The drift changes no draw, so a held seed must replay bit-identically WHERE IT RUNS.
	var pd := _pos_max_diff(op["pos"], rp["pos"])
	var pdc := _pos_max_diff(cu["pos"], cur["pos"])
	print("S38V_REPLAY   the SAME held seed twice, at BOTH ends of the slider: max|Δpos| = %.6f m (perfect gyro) and %.6f m (−5 %%) over %d frames — the drift branch is proven deterministic WHERE IT RUNS, not only beside it" %
		  [pd, pdc, int(min(op["pos"].size(), rp["pos"].size()))])
	if not (pd == 0.0 and pdc == 0.0):
		return _fail(("PHASE REPLAY: a held seed must replay BIT-IDENTICALLY at both slider ends " +
			"(%.9f perfect, %.9f cured). The gyro error changes no draw — class 4a") % [pd, pdc])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE LADDER — ⭐ THE WALK, AND IT IS MONOTONE ACROSS THE WHOLE DOMAIN. ⚠ The rule is the
	# LARGEST SINGLE-STEP RATIO and nothing here compares an rms to a threshold.
	var lad := [_res["s100"], _res["s20"], op, _res["s-10"], _res["s-20"], _res["s-30"], cu,
				_res["s-80"], _res["s-200"]]
	print("S38V_LADDER   %s" % _s_ladder_text(lad))
	# ⚠⚠ MONOTONE IN THE SLIDER — a first for this family after the wrinkles at 19/20/22/28/35/36, and
	# it is asserted CELL BY CELL rather than end to end, because an end-to-end check would pass over
	# any interior reversal. A reversal would mean the ring is NOT simply the leak reaching the index.
	for i in range(1, lad.size()):
		if not (float(lad[i]["rms"]) < float(lad[i - 1]["rms"])):
			return _fail(("⭐ PHASE LADDER: `rms r` must FALL monotonically as the gyro worsens — cell " +
				"%d (s %+.3f, rms %.5f) is not below cell %d (s %+.3f, rms %.5f). The whole ladder is " +
				"printed above so a reader can see the shape rather than trust this assert") %
				[i, float(lad[i]["s"]), float(lad[i]["rms"]), i - 1, float(lad[i - 1]["s"]),
				 float(lad[i - 1]["rms"])])
	# ⭐ THE TRANSITION IS A SINGLE STEP, and it is found by the same threshold-free rule slice 37 used.
	var st := _largest_drop(lad)
	print("S38V_STEP     the transition is a SINGLE step across s ∈ (%+.3f, %+.3f] at %.1fx — the ladder is otherwise a gentle slope, so the gyro spec has a KNEE rather than a proportional cost" %
		  [float(st["hi"]), float(st["lo"]), float(st["ratio"])])
	if not (absf(float(st["lo"]) - S_CURE) < EXACT and absf(float(st["hi"]) - S_M03) < EXACT):
		return _fail(("⭐ PHASE STEP: the largest single step must sit across (%+.3f, %+.3f], got " +
			"(%+.3f, %+.3f] at %.2fx") % [S_M03, S_CURE, float(st["hi"]), float(st["lo"]),
			float(st["ratio"])])
	# ⚠ THE CEILING IS BEYOND SLICE 37's SPACE RUNG, NOT BETWEEN THE TWO: an OVER-reading gyro
	# over-rejects and rings HARDER than a perfect one. That is the half of the axis a rung pair cannot
	# express at all, and it is why the domain is not simply [dead, perfect].
	if not (float(_res["s100"]["rms"]) > float(op["rms"])):
		return _fail(("⚠ PHASE CEILING: an OVER-reading gyro (s %+.3f) must ring HARDER than a perfect " +
			"one (%.5f against %.5f) — the ceiling exists to show the half of this axis that lies " +
			"BEYOND slice 37's stabilized rung rather than between its two") %
			[S_CEIL, float(_res["s100"]["rms"]), float(op["rms"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE INERT — ⭐⭐ THE SLIDER DOES NOTHING ON THE OTHER SIDE OF THE BUTTON, AND IT IS MEASURED AS
	# BIT-IDENTITY. A body-referenced head has no stabilization gyro to corrupt, so the two arms below
	# differ by the FULL slider range and must be the same missile to the last bit. ⚠ THIS IS WHY THE
	# CLIENT NEEDED A MARKER OF ITS OWN: a live control that does nothing is the stale-readout class in
	# a new form, and the HUD names the state instead of leaving a student to drag and watch nothing.
	var pdi := _pos_max_diff(i0["pos"], i20["pos"])
	print("S38V_INERT    on the BODY-REFERENCED rung the slider is INERT: s %+.3f and s %+.3f fly the SAME missile, max|Δpos| = %.9f m over %d frames (rms r %.5f vs %.5f, miss %.3f vs %.3f m). A body-referenced head has NO stabilization gyro to corrupt — which is the same fact the mid-run press below demonstrates from the other direction" %
		  [float(i0["s"]), float(i20["s"]), pdi, int(min(i0["pos"].size(), i20["pos"].size())),
		   float(i0["rms"]), float(i20["rms"]), float(i0["miss"]), float(i20["miss"])])
	if not (pdi == 0.0):
		return _fail(("⭐⭐ PHASE INERT: on the body-referenced rung the slider must be BIT-IDENTICALLY " +
			"inert across its whole range (max|Δpos| = %.9f m). The drift call lives inside the seam's " +
			"`elseif _stab` arm, so this is inert BY PLACEMENT rather than by a guard — if it fires, " +
			"the gyro is reaching a loop that does not exist") % pdi)
	if not (float(i0["rms"]) == float(i20["rms"])):
		return _fail(("⭐⭐ PHASE INERT: …and the ring metric with it (%.9f vs %.9f)") %
			[float(i0["rms"]), float(i20["rms"])])
	# ⚠ AND THE INERT ARM MUST BE QUIET, or "inert" would be indistinguishable from "stuck ringing".
	if not (float(i0["rms"]) < RING):
		return _fail(("PHASE INERT: the body-referenced arm must also be QUIET at this design (%.5f " +
			"against the %.2f line) — otherwise the bit-identity above is consistent with a rung that " +
			"is merely stuck") % [float(i0["rms"]), RING])

	# PHASE PRESS — ⭐ THE BUTTON, MID-FLIGHT, ON THE RINGING ARM. Slice 37's control is live here and
	# pressing it removes the gyro from the loop entirely, so the ring must fall.
	print("S38V_PRESS    the BUTTON pressed MID-FLIGHT at tick %d on the RINGING arm (`set_fidelity seeker_head` — the exact command the client's cycler sends): rms r %.5f against %.5f flown space-stabilized from launch, and the engagement survives it (miss %.3f m, out %.2f %%)" %
		  [PRESS_AT, float(mp["rms"]), float(op["rms"]), float(mp["miss"]), float(mp["out"])])
	if not (float(mp["rms"]) < float(op["rms"])):
		return _fail(("⭐ PHASE PRESS: pressing to the body-referenced rung must REDUCE the ring " +
			"(%.5f against %.5f) — that rung has no gyro leak at all") %
			[float(mp["rms"]), float(op["rms"])])
	if not (float(mp["miss"]) < HIT_MAX):
		return _fail("PHASE PRESS: the engagement must survive the press (%.3f m)" % float(mp["miss"]))

	print("S38V OK: slice 37 showed that stabilizing the seeker head in space REMOVES stability margin, because the position servo's LAG had been quietly low-passing the missile's own body motion out of the radome's INDEX. ⚠ THAT WHOLE RESULT RESTS ON A PERFECT GYRO — the shipped stabilized head rejects body motion at EXACTLY unity gain at every frequency, because the model simply STORES the inertial angles, and slice 37 named that §1 approximation FIRST among its own deferrals. Give the gyro a scale-factor error and the rejection LEAKS: a fraction |s| of the missile's own body motion comes back into the index. ⭐⭐ THE SHOWCASE IS ONE SLIDER AND IT RUNS THE WRONG WAY ROUND — at the authored design a PERFECT gyro RINGS at %.5f, and a −5 %% scale factor (an ordinary cheap-MEMS part) makes the SAME missile with the SAME glass, the SAME believed slope and the SAME seed QUIET at %.5f, %.1fx, both HITTING. ⇒ A WORSE GYRO IS A MORE STABLE MISSILE, and slice 37's margin is a GYRO SPEC that has to be BUDGETED against the sensor maintaining it. ⭐ THE LADDER IS MONOTONE ACROSS THE WHOLE DOMAIN (a first for this family after the wrinkles at 19/20/22/28/35/36), asserted CELL BY CELL, with the transition a SINGLE step across s ∈ (%+.3f, %+.3f] — so the gyro spec has a KNEE rather than a proportional cost — and the CEILING is an OVER-reading gyro that rings HARDER than a perfect one (%.5f against %.5f), which is the half of this axis lying BEYOND slice 37's stabilized rung rather than between its two. ⭐⭐ AND THE SLIDER IS BIT-IDENTICALLY INERT ON THE OTHER SIDE OF THE BUTTON (max|Δpos| = 0.0 across its whole range on the body-referenced rung) — a LIVE CONTROL THAT DOES NOTHING, which is the stale-readout class in a NEW form and the reason this wire needed a marker of its own: `gimbal_gyro_view` names that state instead of leaving a student to drag a slider and watch nothing happen. ⚠⚠ THE HEADLINE THIS SLICE IS ABOUT — the onset bracket walking from slice 37's own SPACE bracket (−0.210, −0.205] at a perfect gyro to its own BODY bracket (−0.170, −0.165] at a dead one, with −5 %% giving back a quarter of the margin — is NOT MEASURED HERE and could not be: it needs `radome_slope_est`, which is AUTHORED on this wire. It lives in `test_missile.jl` on the shipped seam. ⚠ Every arm HITS, the detector window NEVER bites (out = 0.00 %% on all %d arms — the precondition that makes every rms r here a stability read), `defl_sat` is 0 everywhere, and the head's travel stays inside both the 30 deg stop and the small-angle budget. ⚠ NO new rung, no new cap, no new instability, no new draw. Class 4a, the FOURTEENTH consecutive RNG-live slice, replay bit-identical at both ends of the slider." %
		  [float(op["rms"]), float(cu["rms"]), ratio, S_M03, S_CURE,
		   float(_res["s100"]["rms"]), float(op["rms"]), _arms.size()])
	quit(0)
	return true

# The ladder as one printable row — the whole shape, so a reader can redraw any line themselves.
func _s_ladder_text(rows: Array) -> String:
	var out := ""
	for r in rows:
		out += " %+.3f:%.5f" % [float(r["s"]), float(r["rms"])]
	return out

# The largest single-step DROP along a descending ladder, and where it sits. ⚠⚠ DIRECTION MATTERS AND
# THIS IS NOT slice 37's `_largest_step` WITH A SIGN FLIP BY ACCIDENT: gate 0's P3a applied the
# ascending rule to a DESCENDING ladder and reported 1.03x where its own table showed a 10.3x
# collapse. The rule is written here for the direction this ladder actually runs.
func _largest_drop(rows: Array) -> Dictionary:
	var best := 0.0
	var lo := NAN
	var hi := NAN
	for i in range(1, rows.size()):
		var r: float = float(rows[i - 1]["rms"]) / maxf(float(rows[i]["rms"]), 1.0e-12)
		if r > best:
			best = r
			hi = float(rows[i - 1]["s"])
			lo = float(rows[i]["s"])
	return {"ratio": best, "lo": lo, "hi": hi}


func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_turned = false
	_n_gate = 0
	_n_out = 0
	_max_head = 0.0
	_max_off = 0.0
	_min_marg = 1.0e30
	_n_band = 0
	_off_band = 0.0
	_n_sat = 0
	_dems = []
	_n_zero_dem = 0
	_n_aero = 0
	_n_defl = 0
	_sum_r2 = 0.0
	_rhat_seen = 0.0
	_s_seen = 0.0
	_win_seen = 0.0
	_stop_seen = 0.0
	_rate_seen = 0.0
	_worst = 0.0
	_pos_trace = []

func _drain_scan() -> bool:
	var last_t := -1.0
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		var mpos := _missile_pos(f)
		if mpos.size() == 3:
			_pos_trace.append(mpos)
		var tel: Dictionary = f.get("telemetry", {})
		if tel.has(MID + ".gimbal_fov_deg"):
			_win_seen = float(tel[MID + ".gimbal_fov_deg"])
		if tel.has(MID + ".gimbal_stop_deg"):
			_stop_seen = float(tel[MID + ".gimbal_stop_deg"])
		if tel.has(MID + ".gimbal_rate_dps"):
			_rate_seen = float(tel[MID + ".gimbal_rate_dps"])
		if tel.has(MID + ".radome_slope_est"):
			_rhat_seen = float(tel[MID + ".radome_slope_est"])
		if tel.has(MID + ".head_gyro_scale_err"):
			_s_seen = float(tel[MID + ".head_gyro_scale_err"])
		if tel.has(MID + ".radome_slope_worst"):
			_worst = float(tel[MID + ".radome_slope_worst"])
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				# WINDOW 1 — the WHOLE-APPROACH window, RANGE-GATED at r > 200 m. ⚠ Ungated, the endgame
				# LOS swing makes a QUIET arm read a few tenths of a percent out and its tracking error
				# read tens of degrees (slice 33's five failing asserts, 34/35's inherited fix).
				if r > 200.0:
					_n_gate += 1
					_max_head = maxf(_max_head, float(tel.get(MID + ".head_angle_deg", 0.0)))
					_max_off = maxf(_max_off, float(tel.get(MID + ".head_off_deg", 0.0)))
					if tel.has(MID + ".gimbal_fov_margin_deg"):
						_min_marg = minf(_min_marg, float(tel[MID + ".gimbal_fov_margin_deg"]))
					# ⚠ `gimbal_valid`, NEVER `seeker_valid`: different booleans about different
					# windows, and the loader refuses the combination.
					if float(tel.get(MID + ".gimbal_valid", 1.0)) < 0.5:
						_n_out += 1
				# WINDOW 2 — the ISOLATION band, 28/29/30/31/33/34/35's [500, 3000] m, inherited with
				# its reasons: the LAUNCH TURN happens at r ~ 6000 m, so the band excludes the
				# acquisition confound BY CONSTRUCTION rather than by a tuned t0.
				# ⚠ THE CHANNEL IS YAW: the lead is in AZIMUTH on this crossing geometry, so the yaw
				# channel sits on the steep part of the slope curve while pitch sits near the boresight
				# slope (slice 28's finding — a `q` metric meters the quiet channel of a shaking missile).
				if r > 500.0 and r < 3000.0:
					_n_band += 1
					var rr := float(tel.get(MID + ".omega_r", 0.0))
					_sum_r2 += rr * rr
					_off_band = maxf(_off_band, float(tel.get(MID + ".head_off_deg", 0.0)))
					if float(tel.get(MID + ".head_rate_sat", 0.0)) > 0.5:
						_n_sat += 1
					var dmb := float(tel.get(MID + ".head_rate_dps", 0.0))
					_dems.append(dmb)
					if dmb == 0.0:
						_n_zero_dem += 1
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

# ⚠ A PERCENTILE, NEVER A PEAK: `head_rate_dps` peaks at an identical value on EVERY arm because the
# peak is the tick-2 HANDOVER transient, before the arms have diverged at all (slice 35's gate 0 §0.2).
# Slice 25's "exclude the init ticks" rule arriving in a new quantity.
func _pct(v: Array, q: float) -> float:
	if v.is_empty():
		return NAN
	var s := v.duplicate()
	s.sort()
	return float(s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)])

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice38_head_gyro":
		return "expected the 'slice38_head_gyro' scenario, got '%s'" % str(f.get("name", ""))
	if not bool(f.get("airframe_view", false)):
		return "a slice-38 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-38 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	# ⭐⭐ THE NEW MARKER, AND ITS JOB IS THE **OPPOSITE** OF EVERY MARKER THIS FAMILY HAS ADDED SINCE
	# SLICE 26. Those all exist to DROP the shared fidelity button, because slices 26-36 each had no
	# rung to cycle (the lesson was a slider every time) — and 32/33/34/35 got the drop for free by
	# riding `radome_view`. `:seeker_head` IS a rung, the first on this button since slice 25, so here
	# THE BUTTON IS THE LESSON — and this wire raises THREE separate drop markers, so without a marker
	# of its own the one slice in twelve that has something to cycle would ship with no control at all.
	# ⭐⭐ THE NEW MARKER, AND ITS JOB IS THE **HUD**, NOT THE BUTTON — the second of this family to be
	# so (slice 35's shape). A slice-38 wire is a slice-38 wire PLUS one comp key, so `gimbal_frame_view`
	# is raised too and the BUTTON is already correct: `:seeker_head`'s two rungs are the two ENDS of
	# this slice's own slider axis. What is NOT correct without this marker is the HUD — slice 37's
	# block would take the wire, and EVERY KEY IT READS IS LIVE HERE, so it would print a fluent and
	# entirely TRUE frame-comparison verdict, with a cure line naming `radome_slope_est` against
	# `radome_slope_worst`, on a wire whose subject is the GYRO and whose slider is neither of those.
	# The stale-readout class's WORST form (slice 34's), where nothing is stale.
	if not bool(f.get("gimbal_gyro_view", false)):
		return "a slice-38 handshake must ship gimbal_gyro_view=true — the marker that routes the HUD. Without it slice 37's frame-comparison block takes this wire and prints a TRUE verdict about the SERVO'S FRAME (plus a cure line naming a slider this wire does not have) above a lesson about the SENSOR. It must also be checked FIRST at all three client sites, because this wire raises radome_view, gimbal_view, gimbal_rate_view AND gimbal_frame_view"
	if not bool(f.get("gimbal_frame_view", false)):
		return "a slice-38 handshake must ship gimbal_frame_view=true — the FIRST marker of this family whose job is to UN-DROP the shared fidelity button. This wire raises radome_view, gimbal_view AND gimbal_rate_view, every one of which hides it at both client sites, so without this the ONE slice since 25 with a rung to cycle would ship with no button — and its HUD would be slice 35's, which pairs `head_rate_dps` against a rate cap WITHOUT NAMING ITS FRAME (that key means BODY-frame demand on one rung and INERTIAL-frame demand on the other, and at the slider's ceiling the press makes it FALL 3.15x while the ring RISES 1.70x — the invited subtraction is exactly the 'cheaper build' conclusion the core's seam forbids)"
	# …AND THE THREE DROPS IT ALSO RAISES, asserted as the POSITIVE facts that make the marker necessary.
	if not bool(f.get("radome_view", false)):
		return "a slice-38 wire carries GLASS, so it must ship radome_view=true — and it is one of the three markers the new one has to be checked ahead of"
	if not bool(f.get("gimbal_view", false)):
		return "a slice-38 wire carries a HEAD, so it must ship gimbal_view=true"
	if not bool(f.get("gimbal_rate_view", false)):
		return "a slice-38 wire carries a rate-limited servo (slice 35's, AUTHORED here), so it must ship gimbal_rate_view=true"
	if f.has("seeker_fov_view"):
		return "a slice-38 wire must NOT raise seeker_fov_view — the loader refuses `seeker_fov_deg` beside a head (a gimballed seeker has no body-fixed window; its body-fixed limit is the mechanical STOP)"
	if f.has("gimbal_handover_view"):
		return "a slice-38 wire must NOT raise gimbal_handover_view — `gimbal_handover_err_deg` is REFUSED beside `:space_stabilized` at load, because slice 36's basket, its V and its sign convention are all stated in the BODY frame"
	var fid: Dictionary = f.get("fidelity", {})
	# ⭐⭐ THE ONE TOGGLED KEY, AND THE WIRE OPENS ON THE GOOD DESIGN so the FIRST press is the one that
	# breaks it. ⚠ A marker value-guarded on `:space_stabilized` would hide the button on exactly this
	# arm — the one direction that is fatal — which is why the core gates on the KEY, not the value.
	if str(fid.get("seeker_head", "")) != SPACE:
		return "a slice-38 scenario must OPEN on :space_stabilized — the OPPOSITE of slice 37's choice, and for the mirror reason. Slice 37 opened on the GOOD design so the first PRESS would break it; here the slider's job is to make a RINGING missile quiet by making its gyro WORSE, so the wire must open where the ring is. Got %s" % str(fid.get("seeker_head", "<absent>"))
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-38 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS a look angle at all, and the loader refuses `gimbal_tau_s` without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-38 scenario must HOLD :airframe at six_dof — the head AND the attitude it is measured against are gated on that LIVE rung through `_gim`, so they freeze and resume together. A cross-toggle off :six_dof freezes the attitude, and a frozen attitude makes the body<->inertial conversion the IDENTITY: the two rungs would silently BECOME EACH OTHER rather than visibly break. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-38 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-38 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-38 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-38 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the aero ceiling 93.2% of its approach, a THIRD mechanism)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-38 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	if not keys.has("head_gyro_scale_err"):
		return "the slice-38 wire must expose the 'head_gyro_scale_err' slider — the SENSOR axis, and its job is to walk continuously between the two architectures slice 37 shipped as a button"
	if str(keys["head_gyro_scale_err"]) != MID:
		return "the head-gyro knob must target the interceptor '%s'" % MID
	# ⚠⚠ AND THE DISQUALIFICATION THAT IS NEW HERE, AND IT IS THE ONE A READER WOULD EXPECT TO SEE
	# LIVE: slice 37's own slider is AUTHORED on this wire. The claim is that the GYRO moves the
	# boundary at a FIXED design — with R̂ live beside it a student could move the same boundary two
	# ways at once and neither reading would be attributable (convention 9).
	if keys.has("radome_slope_est"):
		return "slice 38 must NOT expose a 'radome_slope_est' knob — that is slice 37's DESIGN slider, and this wire's whole claim is that the head's GYRO moves the stability boundary at a FIXED design. Live beside this slider it would move the same boundary by a second mechanism, and no reading would be attributable"
	if keys.has("head_gyro_bias_y") or keys.has("head_gyro_bias_z"):
		return "slice 38 must NOT expose a head-gyro BIAS knob — it is the SECOND CURRENCY and it ships in the tests and the HUD, not on a slider: its visible domain is ~10^3x a bad real gyro (at 103 deg/hr it moves rms r by 0.00064), which is slice 31's chosen-for-visibility posture, while the SCALE FACTOR's claim rests on a real part"
	if keys.size() != 1:
		return "the slice-38 wire must expose EXACTLY ONE knob (got %d) — convention 9, and on this wire the second control is the BUTTON, which is the SAME AXIS expressed discretely" % keys.size()
	# ⚠⚠ THE DISQUALIFICATION THAT IS NEW HERE, AND IT WAS DECIDED ON A MEASUREMENT: slice 35's servo
	# slider is AUTHORED on this wire.
	if keys.has("gimbal_rate_dps"):
		return "slice 38 must NOT expose a 'gimbal_rate_dps' knob — that is slice 35's TWO-SIDED KNOB, and putting it live beside this button would put a THIRD mechanism on a wire whose subject is the reference frame (convention 9). Its own finding here — the demand inversion at the slider's ceiling, 3.15x with a 17.5-vs-0.0 %% saturation split — is a TOOTH, measured on the AUTHORED servo"
	if keys.has("gimbal_tau_s"):
		return "slice 38 must NOT expose a 'gimbal_tau_s' knob — on this wire it moves the SIZE of the slice's own mechanism (gate 1 measured both terms moving with tau; the honest range over [0.005, 0.2] is 0 %% to 79 %%, and at tau <= 0.005 the two rungs' brackets COINCIDE). Slice 34's 'CONFOUNDED, not dead' disqualification, one slice sharper"
	if keys.has("gimbal_fov_deg"):
		return "slice 38 must NOT expose a 'gimbal_fov_deg' knob — a LIVE window makes the break an ACQUISITION break (slice 35's §C), and every `rms r` here needs the window never to bite"
	if keys.has("gimbal_stop_deg"):
		return "slice 38 must NOT expose a 'gimbal_stop_deg' knob — the stop is a RESTATEMENT of slice 33's excursion, and binding it COUPLES the two budgets"
	if keys.has("cross_speed_mps"):
		return "slice 38 must NOT expose 'cross_speed_mps' — it is slice 32's OWN axis (it moves the LEAD)"
	if keys.has("af_alpha_max") or keys.has("alpha_max"):
		return "slice 38 must NOT expose an 'alpha_max' knob — slice 26's instrument for the ring's AMPLITUDE and a confounded lever"
	if keys.has("radome_slope") or keys.has("radome_ripple") or keys.has("radome_ripple_k"):
		return "slice 38 must NOT expose the GLASS itself — a radome's slope curve is HARDWARE, and the arc's point since slice 27 is that what an engineer can change is what they BELIEVE about it"
	if keys.has("n_pn"):
		return "slice 38 must NOT expose an 'n_pn' knob — it moves the parasitic boundary AND the guidance loop"
	if keys.has("rho"):
		return "slice 38 must NOT expose a 'rho' knob — it moves the parasitic boundary and the aero ceiling at once"
	if keys.has("sigma_seek"):
		return "slice 38 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it"
	if keys.has("elevation_deg"):
		return "slice 38 must NOT expose 'elevation_deg' — the slice-19 DEAD-knob class"
	if keys.has("speed"):
		return "slice 38 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-KNOB finding)"
	if keys.has("gimbal_handover_err_deg"):
		return "slice 38 must NOT expose 'gimbal_handover_err_deg' — it is structurally a DEAD knob (slice 36's finding, and `_parse_knobs` refuses it BY NAME), and it is refused beside this rung at load anyway"
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

func _fail(msg: String, code := 1) -> bool:
	push_error("S38V FAIL: " + msg)
	print("S38V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
