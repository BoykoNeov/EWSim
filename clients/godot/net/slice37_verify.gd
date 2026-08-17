extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-37 gate-3 verifier — THE HEAD'S OWN GYRO: A SPACE-STABILIZED SERVO GIVES BACK THE
# MARGIN THE POSITION SERVO'S LAG WAS QUIETLY BUYING. Drives the REAL Julia server through
# SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice37_frame.yaml
#   godot --headless --path clients/godot --script res://net/slice37_verify.gd     (exit 0 = pass)
#
# ⚠⚠ THE DEFERRAL'S OWN WORDING WAS REFUTED BEFORE ANY PROBE RAN, and this file must not inherit it.
# `docs/plans/slice34.md:931` named this slice as "a rate-stabilized head measures inertial LOS rate
# DIRECTLY, the classical reason gimbals exist". `missile.jl:1652` is `az_el(u_tru)`, NOT
# `look_angles(att, u_tru)` — the seeker has reported INERTIAL LOS angles since slice 25 and the a-b
# tracker an INERTIAL rate, so the promised headline is ALREADY TRUE and cannot be shipped. What is
# body-referenced is the SERVO, and the live claim is its REFERENCE FRAME.
#
# THE LESSON. Stabilizing the head in space is the textbook improvement — and it makes this missile
# SHAKE, because the position servo's LAG was doing stability work: it LOW-PASSES the missile's own
# body motion out of the radome's INDEX, and slice 26's limit cycle lives at 1.7-2.1 Hz, exactly where
# a tau = 0.05 s filter is worth 12-16 % of gain and ~30 deg of phase. THE CLASSICAL REASON GIMBALS
# EXIST INVERTS ON THIS WIRE.
#
# ⭐⭐ AND THE DEMONSTRATION IS A BUTTON — the first rung on the shared fidelity button since slice 25.
# Slices 26-36 all shipped with it DROPPED (no rung to cycle; the lesson was a slider every time), so
# this wire needs a marker of its own to UN-DROP it, against three separate markers on the same wire
# that each hide it. That inversion is asserted in the handshake check below.
#
# ⚠⚠ THE ONSET RULE IS THE **LARGEST SINGLE-STEP RATIO** AND IS THRESHOLD-FREE BY CONSTRUCTION — gate
# 0's advisor catch, and it is load-bearing HERE rather than merely inherited: the body rung reads
# 0.173 at R̂ = -0.165, which is an order of magnitude above its own 0.012 plateau AND BELOW the arc's
# 0.30 ring line. So the brackets below are established by walking a five-point ladder per rung and
# taking the largest step — NOT by comparing anything to `RING`, which is used only where the two
# sides differ by two orders of magnitude (the showcase, the aim point).
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`) and every constant is sized off a FRAME column
# ([[ewsim-missile-verifier-sampling]] — the error is ASYMMETRIC: a MISS samples faithfully, a HIT
# samples COARSELY). `rms r` is frame-robust (slice 26 measured it, which is why this family uses it).
# ⚠⚠ AND ONE THING A FRAME VERIFIER STRUCTURALLY CANNOT SEE IS PINNED IN `test_missile.jl` INSTEAD:
# across the space→body press, `head_angle_deg` steps 0.939 deg on THIS grid — ~16x a normal frame,
# which reads exactly like the head being re-born. It is not. At the press TICK it moves 0.0074 deg,
# ~9x LESS than the tick before; the frame figure is the SPACE rung's own body-angle motion
# (0.065 deg/tick, a head held inertially being carried along by the rotating body at unity gain)
# accumulated over 16 ticks. ⇒ NOTHING HERE ASSERTS A STEP ACROSS THE PRESS, deliberately.
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
const RHAT_DEF := -0.18
# The two ladders' rungs, on gate 2's own 0.005 grid near each bracket.
const RHAT_210 := -0.210
const RHAT_205 := -0.205
const RHAT_175 := -0.175
const RHAT_170 := -0.170
const RHAT_165 := -0.165
# THE SLIDER'S ENDPOINTS — measured, never inferred from the interior (slice 26's post-commit rule).
const RHAT_FLOOR := -0.33         # slice 30's aim point R0 + 2A — where the BUTTON GOES DEAD
const RHAT_CEIL := -0.14          # where BOTH rungs ring — the only arm a DEMAND comparison is legal on

# ⚠ THE ARC's RING LINE, AND IT IS USED ONLY WHERE THE TWO SIDES DIFFER BY TWO ORDERS OF MAGNITUDE.
# The brackets are established by the largest-step rule instead — see the header.
const RING := 0.30
# A SANITY BOUND, NOT THE METRIC. Every arm on this wire HITS on BOTH rungs (frame-sampled 0.35-6.8 m)
# — the arc's standing fact since slice 26, and the reason the verdict is `rms r` and never a miss.
const HIT_MAX := 40.0
const WIN_AUTH := 25.0            # the AUTHORED detector window (not a knob here)
const STOP_AUTH := 30.0           # the AUTHORED mechanical stop
const RATE_AUTH := 40.0           # the AUTHORED servo — slice 35's slider, held here
const MODEL_VALID_DEG := 30.0     # the small-angle bend budget 28/29/30/31 each declared
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
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _worst := 0.0                 # slice 30's aim point, READ OFF THE WIRE (never recomputed)
var _pos_trace: Array = []

func _initialize() -> void:
	print("S37V_INIT godot=", Engine.get_version_info().string)
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
	# 1) ⭐⭐ THE SHOWCASE — ONE PRESS ON A DESIGN THAT WAS ALREADY GOOD, and its REPLAY on BOTH rungs
	#    (class 4a: the seed is LOAD-BEARING, and a replay proven on only one rung would leave the new
	#    branch unproven where it actually runs).
	_arms.append({"tag": "open", "rung": BODY})
	_arms.append({"tag": "replay", "rung": BODY})
	_arms.append({"tag": "press", "rung": SPACE})
	_arms.append({"tag": "press_rep", "rung": SPACE})
	# 2) ⭐ THE LADDER, WALKED TWICE — five rungs per servo frame on gate 2's own 0.005 grid. The
	#    DEFAULT arms above are each ladder's -0.180 point, so only four new arms per rung are needed.
	#    ⚠ These exist to establish the brackets by the LARGEST-STEP rule; nothing here compares an
	#    `rms r` to a threshold.
	for r in [RHAT_210, RHAT_205, RHAT_175, RHAT_170, RHAT_165]:
		_arms.append({"tag": "b%d" % int(round(-1000.0 * r)), "rung": BODY, "rhat": r})
		_arms.append({"tag": "s%d" % int(round(-1000.0 * r)), "rung": SPACE, "rhat": r})
	# 3) ⭐⭐ THE SLIDER'S FLOOR — slice 30's aim point, WHERE THE BUTTON GOES DEAD. The rule pays a
	#    FOURTH time (33 = FOV, 34 = detector window, 35 = servo bandwidth, 37 = the reference FRAME).
	_arms.append({"tag": "aimb", "rung": BODY, "rhat": RHAT_FLOOR})
	_arms.append({"tag": "aims", "rung": SPACE, "rhat": RHAT_FLOOR})
	# 4) THE SLIDER'S CEILING — the arm where BOTH rungs ring, which is the ONLY kind of arm on which
	#    a DEMAND comparison is legal at all (at the default one rings and one does not).
	_arms.append({"tag": "ceilb", "rung": BODY, "rhat": RHAT_CEIL})
	_arms.append({"tag": "ceils", "rung": SPACE, "rhat": RHAT_CEIL})
	# 5) ⭐⭐ THE PRESS ITSELF, MID-FLIGHT — the one thing gates 0-2 could not cover, because they
	#    toggled in Julia. This is the first time the actual `set_fidelity` a button sends reaches the
	#    rung boundary at an arbitrary tick, which is precisely where gate 2's CATCH-1 branch lives.
	_arms.append({"tag": "midpress", "rung": BODY, "press": SPACE})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `body_referenced` every arm and
	# each arm must re-send its own — which is exactly what makes these arms the BUTTON's path and not
	# a scenario variant. `set_fidelity` is the same command the client's cycler sends.
	_client.send({"type": "reset"})
	if str(arm.get("rung", BODY)) != BODY:
		_client.send({"type": "set_fidelity", "key": "seeker_head", "value": str(arm["rung"])})
	if arm.has("rhat"):
		_client.send(_set_param_cmd(MID, "radome_slope_est", float(arm["rhat"])))
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
		"dem95": _pct(_dems, 0.95), "rhat": _rhat_seen, "rung": str(arm.get("rung", BODY)),
		"win": _win_seen, "stop": _stop_seen, "rate": _rate_seen, "worst": _worst,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S37V_ARM   %-9s %-16s R̂=%+.4f  ->  miss=%.3f  rms_r=%.5f  demand_p95=%.3f deg/s  " +
		   "sat_band=%.2f%% (%d band frames)  off_band=%.3f  off_max=%.3f  head_max=%.3f  " +
		   "margin_min=%.2f  out=%.3f%% of %d gated  aero=%.2f%%  defl=%d  cpa=%s") %
		  [tag, m["rung"], m["rhat"], m["miss"], m["rms"], m["dem95"], m["sat"], m["band"],
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
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH):
		return (("arm %s: the window / stop / servo must be the AUTHORED %.1f / %.1f / %.1f (got %.3f / " +
				"%.3f / %.3f) — this wire's ONE slider is R̂ and its ONE control is the button") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, _win_seen, _stop_seen, _rate_seen])
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
	var pr: Dictionary = _res["press"]
	var prr: Dictionary = _res["press_rep"]
	var aimb: Dictionary = _res["aimb"]
	var aims: Dictionary = _res["aims"]
	var cb: Dictionary = _res["ceilb"]
	var cs: Dictionary = _res["ceils"]
	var mp: Dictionary = _res["midpress"]

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE OPEN — ⭐⭐ ONE PRESS ON A DESIGN THAT WAS ALREADY GOOD. Same glass, same believed slope,
	# same seed, same servo, same handover; the ONLY variable is which frame the servo closes in.
	var ratio: float = float(pr["rms"]) / maxf(float(op["rms"]), 1.0e-12)
	print("S37V_PRESS    THE SHOWCASE, and it is ONE BUTTON PRESS: at R̂ %+.2f the BODY-REFERENCED head is QUIET (rms r %.5f) and hits at %.3f m; press once and the SAME missile, SAME glass, SAME seed, SPACE-STABILIZED, RINGS at %.5f — %.1fx — and still hits at %.3f m. The textbook improvement REMOVES margin: the position servo's LAG was low-passing body motion out of the radome's INDEX" %
		  [float(op["rhat"]), float(op["rms"]), float(op["miss"]), float(pr["rms"]), ratio, float(pr["miss"])])
	if not (float(op["rms"]) < RING and float(pr["rms"]) > RING):
		return _fail(("⭐⭐ PHASE PRESS: the two rungs must land on OPPOSITE SIDES of the arc's %.2f " +
			"ring line at the SAME R̂ (%.5f body, %.5f space). ⚠ The line is used HERE and at the aim " +
			"point ONLY, where the two sides differ by two orders of magnitude — the BRACKETS below " +
			"are established by the largest-step rule, because gate 0's advisor catch was exactly a " +
			"chosen threshold doing load-bearing work") % [RING, float(op["rms"]), float(pr["rms"])])
	if not (ratio > 40.0):
		return _fail(("⭐⭐ PHASE PRESS: the press must move the ring by a factor worth a button " +
			"(%.1fx, must exceed 40). Measured 83.77x frame / 85.44x per tick") % ratio)
	if not (float(op["miss"]) < HIT_MAX and float(pr["miss"]) < HIT_MAX):
		return _fail(("PHASE PRESS: BOTH arms must HIT (%.3f / %.3f m) — the miss is NOT the metric " +
			"here and the slice would be misread if the ringing arm also missed") %
			[float(op["miss"]), float(pr["miss"])])
	# ⚠ AND THE PRESS IS NOT A RE-AIM: the R̂ the two arms fly is bit-identical, so nothing about the
	# design changed. This is what stops the headline being read as a slider move.
	if not (float(op["rhat"]) == float(pr["rhat"])):
		return _fail(("⭐⭐ PHASE PRESS: the two arms must fly the IDENTICAL believed slope (%+.9f vs " +
			"%+.9f) — the entire claim is that ONLY the servo's reference frame changed") %
			[float(op["rhat"]), float(pr["rhat"])])

	# PHASE REPLAY — determinism, ON BOTH RUNGS (class 4a, the 13th consecutive RNG-live slice).
	var pd := _pos_max_diff(op["pos"], rp["pos"])
	var pds := _pos_max_diff(pr["pos"], prr["pos"])
	print("S37V_REPLAY   the SAME held seed twice, on BOTH rungs: max|Δpos| = %.6f m (body) and %.6f m (space) over %d frames — the new branch is proven determinstic WHERE IT RUNS, not only beside it" %
		  [pd, pds, int(min(op["pos"].size(), rp["pos"].size()))])
	if not (pd == 0.0 and pds == 0.0):
		return _fail(("PHASE REPLAY: a held seed must replay BIT-IDENTICALLY on BOTH rungs (%.9f body, " +
			"%.9f space). The rung changes no draw — class 4a, and a replay proven on only the body " +
			"arm would leave the new branch unproven exactly where it executes") % [pd, pds])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE LADDER — ⭐ THE ONSET IS FOUND TWICE, AND THE RULE IS THRESHOLD-FREE.
	var bl := [_res["b210"], _res["b205"], op, _res["b175"], _res["b170"], _res["b165"]]
	var sl := [_res["s210"], _res["s205"], pr, _res["s175"], _res["s170"], _res["s165"]]
	var bb := _largest_step(bl)
	var sb := _largest_step(sl)
	print("S37V_LADDER   BODY-REFERENCED  %s   ->  largest single-step %.2fx across (%+.4f, %+.4f]" % [_ladder_text(bl), float(bb["ratio"]), float(bb["lo"]), float(bb["hi"])])
	print("S37V_LADDER   SPACE-STABILIZED %s   ->  largest single-step %.2fx across (%+.4f, %+.4f]" % [_ladder_text(sl), float(sb["ratio"]), float(sb["lo"]), float(sb["hi"])])
	# ⚠⚠ THE WHOLE LADDER IS PRINTED SO A READER CAN REDRAW THE LINE THEMSELVES (gate 0's advisor
	# catch: the first draft bracketed on a bare `rms r > 0.20` THAT I CHOSE, which appears nowhere in
	# slices 26-36 and was load-bearing — the body rung reads 0.173 at -0.165, 13 % below it).
	if not (absf(float(bb["hi"]) - RHAT_165) < EXACT and absf(float(bb["lo"]) - RHAT_170) < EXACT):
		return _fail(("⭐ PHASE LADDER: the BODY rung's onset bracket must be (%+.3f, %+.3f], got " +
			"(%+.4f, %+.4f] at %.2fx. The rule is the LARGEST SINGLE-STEP RATIO and nothing here " +
			"compares an rms to a threshold") % [RHAT_170, RHAT_165, float(bb["lo"]), float(bb["hi"]),
			float(bb["ratio"])])
	if not (absf(float(sb["hi"]) - RHAT_205) < EXACT and absf(float(sb["lo"]) - RHAT_210) < EXACT):
		return _fail(("⭐ PHASE LADDER: the SPACE rung's onset bracket must be (%+.3f, %+.3f], got " +
			"(%+.4f, %+.4f] at %.2fx") % [RHAT_210, RHAT_205, float(sb["lo"]), float(sb["hi"]),
			float(sb["ratio"])])
	# ⭐⭐ AND THE TWO BRACKETS MUST NOT OVERLAP — asserted FROM BOTH DIRECTIONS, which is what makes
	# "the onset walks two rungs of the same ladder" a MEASUREMENT rather than two separate readings.
	# Across the SPACE bracket the body rung is still on its plateau; across the BODY bracket the space
	# rung is already ringing hard. Either half alone would be consistent with one shifted curve.
	print("S37V_GAP      the two brackets are DISJOINT, from both sides: across the SPACE bracket (%+.3f, %+.3f] the BODY rung is still on its plateau (%.5f / %.5f) while the space rung steps %.5f -> %.5f; across the BODY bracket (%+.3f, %+.3f] the SPACE rung is ALREADY ringing (%.5f / %.5f) while the body rung steps %.5f -> %.5f" %
		  [RHAT_210, RHAT_205, float(_res["b210"]["rms"]), float(_res["b205"]["rms"]),
		   float(_res["s210"]["rms"]), float(_res["s205"]["rms"]),
		   RHAT_170, RHAT_165, float(_res["s170"]["rms"]), float(_res["s165"]["rms"]),
		   float(_res["b170"]["rms"]), float(_res["b165"]["rms"])])
	if not (float(_res["b210"]["rms"]) < RING and float(_res["b205"]["rms"]) < RING):
		return _fail(("⭐⭐ PHASE GAP: across the SPACE rung's onset bracket the BODY rung must still be " +
			"QUIET (%.5f / %.5f against %.2f) — otherwise the two brackets are the same boundary read " +
			"twice") % [float(_res["b210"]["rms"]), float(_res["b205"]["rms"]), RING])
	if not (float(_res["s170"]["rms"]) > RING and float(_res["s165"]["rms"]) > RING):
		return _fail(("⭐⭐ PHASE GAP: …and across the BODY rung's onset bracket the SPACE rung must " +
			"ALREADY be ringing (%.5f / %.5f against %.2f) — the other direction of the same claim") %
			[float(_res["s170"]["rms"]), float(_res["s165"]["rms"]), RING])
	# ⚠ THE FRACTION OF MARGIN GIVEN BACK IS QUOTED AS A RANGE AND NEVER AS A SINGLE NUMBER (gate 0's
	# advisor catch, its second half): it moves with the threshold rule (~42 % under largest-step,
	# 45 % under the rule that was discarded), while THE ORDER OF THE RUNGS AND THE SIGN OF THE EFFECT
	# are threshold-FREE — which is what this phase asserts and all it asserts.
	if not (float(sb["hi"]) < float(bb["hi"])):
		return _fail(("⭐ PHASE LADDER: the SPACE rung's onset must sit at a MORE NEGATIVE R̂ than the " +
			"BODY rung's (%+.4f vs %+.4f) — i.e. it needs a BETTER-aimed compensator to stay quiet. " +
			"That ORDER is the threshold-free half of the claim; the ~40-45 %% of margin given back " +
			"is quoted as a RANGE precisely because it is not") % [float(sb["hi"]), float(bb["hi"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE RULE — ⭐⭐ SLICE 30's RULE PAYS A FOURTH TIME, AND THE PROOF IS A CONTROL GOING DEAD.
	var aim_ratio: float = float(aims["rms"]) / maxf(float(aimb["rms"]), 1.0e-12)
	print("S37V_RULE     at slice 30's aim point R0+2A = %+.4f (READ OFF THE WIRE, never recomputed) the BUTTON GOES DEAD: body %.5f against space %.5f — %.3fx, against %.1fx at the default. Aim R̂ at the glass's worst-case slope and THE ARCHITECTURE DOES NOT MATTER. Slice 30's rule pays a FOURTH time (33 = FOV, 34 = detector window, 35 = servo bandwidth, 37 = the head's REFERENCE FRAME)" %
		  [float(aimb["worst"]), float(aimb["rms"]), float(aims["rms"]), aim_ratio, ratio])
	if not (absf(float(aimb["rhat"]) - float(aimb["worst"])) < 1.0e-6):
		return _fail(("PHASE RULE: the aim-point arm must sit AT `radome_slope_worst` as the CORE ships " +
			"it (R̂ %+.9f against %+.9f). The wire's own value is -0.32999999999999996, not -0.33 — " +
			"slice 21's magic-multiple tooth, pinned against a measured quantity") %
			[float(aimb["rhat"]), float(aimb["worst"])])
	if not (aim_ratio < 1.10):
		return _fail(("⭐⭐ PHASE RULE: at the aim point the two rungs must be INDISTINGUISHABLE " +
			"(%.4fx, must stay under 1.10 — measured 1.022x). This is the slider's FLOOR and the " +
			"reason it is where it is: the strongest statement of a design rule is a control that " +
			"visibly stops working") % aim_ratio)
	if not (float(aimb["rms"]) < RING and float(aims["rms"]) < RING):
		return _fail(("⭐⭐ PHASE RULE: …and BOTH rungs must be QUIET there (%.5f / %.5f against %.2f) — " +
			"'the button does nothing' is only a design rule if what it does nothing to is a WORKING " +
			"missile. Two rungs equally ringing would satisfy the ratio and mean the opposite") %
			[float(aimb["rms"]), float(aims["rms"]), RING])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE PRICE — ⭐⭐ THE HEAD THAT RINGS HARDER DEMANDS LESS, and it is READ ONLY WHERE BOTH RING.
	var dem_ratio: float = float(cb["dem95"]) / maxf(float(cs["dem95"]), 1.0e-9)
	var ring_inv: float = float(cs["rms"]) / maxf(float(cb["rms"]), 1.0e-12)
	print("S37V_PRICE    at the slider's CEILING R̂ %+.2f, where BOTH rungs ring (%.5f body / %.5f space, %.2fx), the space-stabilized head RINGS HARDER AND ASKS FOR LESS: demand p95 %.3f against %.3f deg/s (%.2fx), saturating its %.0f deg/s servo on %.2f %% of the band against %.2f %%. ⇒ THE BODY-REFERENCED SERVO'S DEMAND IS ALMOST ALL BODY MOTION, NOT TARGET MOTION" %
		  [float(cb["rhat"]), float(cb["rms"]), float(cs["rms"]), ring_inv,
		   float(cs["dem95"]), float(cb["dem95"]), dem_ratio, RATE_AUTH,
		   float(cs["sat"]), float(cb["sat"])])
	# ⚠⚠ THE DEMAND COMPARISON IS ONLY LEGAL WHERE BOTH ARMS RING, and that is why the ceiling is a
	# separate arm from the showcase rather than a second reading of it. At the DEFAULT one rings and
	# one does not, and the space arm's demand is the LARGER there (16.6 against 0.5 deg/s) — the
	# reading a careless gate would have shipped backwards.
	if not (float(cb["rms"]) > RING and float(cs["rms"]) > RING):
		return _fail(("⭐⭐ PHASE PRICE: the demand comparison may ONLY be read where BOTH rungs ring " +
			"(%.5f / %.5f against %.2f). At the default the space arm demands MORE, not less, because " +
			"it is the one that is shaking — a demand claim read there is backwards") %
			[float(cb["rms"]), float(cs["rms"]), RING])
	if not (ring_inv > 1.3):
		return _fail(("⭐⭐ PHASE PRICE: …and the space rung must ring HARDER there (%.2fx, must exceed " +
			"1.3 — measured 1.70x). The whole point is that the two bounds move in OPPOSITE " +
			"directions: cheaper in SERVO BANDWIDTH, dearer in STABILITY MARGIN") % ring_inv)
	if not (dem_ratio > 2.0):
		return _fail(("⭐⭐ PHASE PRICE: …while demanding materially LESS slew (%.2fx, must exceed 2 — " +
			"measured 3.15x). ⚠ AND THIS DOES NOT LICENSE 'the stabilized head is the cheaper build': " +
			"it is cheaper in SERVO BANDWIDTH and dearer in STABILITY MARGIN, which is slice 35's " +
			"one-knob-two-bounds shape moved onto the ARCHITECTURE") % dem_ratio)
	# ⭐ AND THE SATURATION SPLIT IS THE SAME FACT FROM A DIFFERENT CODE PATH — the demand is formed
	# unconditionally in the kernel, the flag is its branch predicate — which is what makes the pair a
	# measurement rather than one fact told twice.
	if not (float(cs["sat"]) == 0.0 and float(cb["sat"]) > 5.0):
		return _fail(("⭐ PHASE PRICE: the SPACE rung must never touch its rate limit while the BODY " +
			"rung binds on a material fraction of the band (%.2f %% vs %.2f %%). ⚠ This assert sits " +
			"beside the per-arm `out == 0` gate on purpose (gate 2's advisor CATCH 2): a `sat == 0` " +
			"read WITHOUT the window gate is the one place the two-run discipline can be asserted in " +
			"the direction that hides its own failure — a HELD head demands nothing and saturates " +
			"nothing") % [float(cs["sat"]), float(cb["sat"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE BUTTON — ⭐⭐ THE PRESS ITSELF, MID-FLIGHT, WHICH IS THE ONE PATH GATES 0-2 COULD NOT COVER.
	print("S37V_BUTTON   the BUTTON pressed MID-FLIGHT at tick %d (`set_fidelity seeker_head` — the exact command the client's cycler sends): the arm flies %d ticks body-referenced, is pressed, and finishes at rms r %.5f against %.5f for the same rung flown FROM LAUNCH — the press takes effect and the engagement survives it (miss %.3f m, out %.2f %%, no draw-topology guard anywhere on this key)" %
		  [PRESS_AT, PRESS_AT, float(mp["rms"]), float(pr["rms"]), float(mp["miss"]), float(mp["out"])])
	# The band is reached AFTER the press tick on this wire (the [500, 3000] m window sits at
	# t ~ 8-10.5 s and the press is at 6.4 s), so a mid-run arm's band rms is a fully-toggled read —
	# which is exactly what makes it comparable to the from-launch arm at all. It is NOT bit-identical
	# to it and this file does not claim it is: the first 6400 ticks genuinely differ.
	if not (float(mp["rms"]) > RING):
		return _fail(("⭐⭐ PHASE BUTTON: the mid-flight press must actually take effect (rms r %.5f " +
			"against the %.2f line). If this reads quiet, `set_fidelity seeker_head` is not reaching " +
			"the seam — and the button is the whole demonstration") % [float(mp["rms"]), RING])
	if not (absf(float(mp["rms"]) - float(pr["rms"])) / float(pr["rms"]) < 0.25):
		return _fail(("⭐⭐ PHASE BUTTON: …and the pressed arm must land in the same regime as the same " +
			"rung flown FROM LAUNCH (%.5f vs %.5f). ⚠ NOT bit-identity — the first %d ticks genuinely " +
			"differ — but a mid-run rung that produced a DIFFERENT steady state would mean the " +
			"boundary carries state it should not") % [float(mp["rms"]), float(pr["rms"]), PRESS_AT])
	# ⚠⚠ NOTHING HERE ASSERTS A STEP ACROSS THE PRESS, AND THE REASON IS A GATE-3 MEASUREMENT: on this
	# frame grid the space→body press shows a 0.939 deg step in `head_angle_deg`, ~16x a normal frame,
	# which reads exactly like the head being re-born. It is not — at the press TICK the head moves
	# 0.0074 deg, ~9x LESS than the tick before. The frame figure is the SPACE rung's own body-angle
	# motion accumulated over 16 ticks. THE PRESS IS VISIBLE IN THE RATE, NOT THE POSITION, and a frame
	# verifier structurally cannot see it — so the continuity tooth lives in `test_missile.jl`.

	return _pass()

# --- the scan -------------------------------------------------------------------------------

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

# ⭐⭐ THE ONSET RULE, AND IT IS THRESHOLD-FREE BY CONSTRUCTION. Gate 0's advisor catch was that the
# first draft bracketed on a bare `rms r > 0.20` that I had chosen — a number appearing nowhere in
# slices 26-36 — and it was load-bearing: the body rung reads 0.173 at R̂ = -0.165, 13 % below it and
# an order of magnitude above its own 0.012 plateau. The largest single-step ratio needs no line at
# all, and the whole ladder is printed so a reader can redraw one if they disagree.
func _largest_step(ladder: Array) -> Dictionary:
	var best := {"ratio": 0.0, "lo": 0.0, "hi": 0.0}
	for i in range(1, ladder.size()):
		var a: Dictionary = ladder[i - 1]
		var b: Dictionary = ladder[i]
		var q: float = float(b["rms"]) / maxf(float(a["rms"]), 1.0e-12)
		if q > float(best["ratio"]):
			best = {"ratio": q, "lo": float(a["rhat"]), "hi": float(b["rhat"])}
	return best

func _ladder_text(ladder: Array) -> String:
	var parts: Array = []
	for a in ladder:
		parts.append("%+.3f:%.5f" % [float(a["rhat"]), float(a["rms"])])
	return "  ".join(parts)

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice37_frame":
		return "expected the 'slice37_frame' scenario, got '%s'" % str(f.get("name", ""))
	if not bool(f.get("airframe_view", false)):
		return "a slice-37 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-37 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	# ⭐⭐ THE NEW MARKER, AND ITS JOB IS THE **OPPOSITE** OF EVERY MARKER THIS FAMILY HAS ADDED SINCE
	# SLICE 26. Those all exist to DROP the shared fidelity button, because slices 26-36 each had no
	# rung to cycle (the lesson was a slider every time) — and 32/33/34/35 got the drop for free by
	# riding `radome_view`. `:seeker_head` IS a rung, the first on this button since slice 25, so here
	# THE BUTTON IS THE LESSON — and this wire raises THREE separate drop markers, so without a marker
	# of its own the one slice in twelve that has something to cycle would ship with no control at all.
	if not bool(f.get("gimbal_frame_view", false)):
		return "a slice-37 handshake must ship gimbal_frame_view=true — the FIRST marker of this family whose job is to UN-DROP the shared fidelity button. This wire raises radome_view, gimbal_view AND gimbal_rate_view, every one of which hides it at both client sites, so without this the ONE slice since 25 with a rung to cycle would ship with no button — and its HUD would be slice 35's, which pairs `head_rate_dps` against a rate cap WITHOUT NAMING ITS FRAME (that key means BODY-frame demand on one rung and INERTIAL-frame demand on the other, and at the slider's ceiling the press makes it FALL 3.15x while the ring RISES 1.70x — the invited subtraction is exactly the 'cheaper build' conclusion the core's seam forbids)"
	# …AND THE THREE DROPS IT ALSO RAISES, asserted as the POSITIVE facts that make the marker necessary.
	if not bool(f.get("radome_view", false)):
		return "a slice-37 wire carries GLASS, so it must ship radome_view=true — and it is one of the three markers the new one has to be checked ahead of"
	if not bool(f.get("gimbal_view", false)):
		return "a slice-37 wire carries a HEAD, so it must ship gimbal_view=true"
	if not bool(f.get("gimbal_rate_view", false)):
		return "a slice-37 wire carries a rate-limited servo (slice 35's, AUTHORED here), so it must ship gimbal_rate_view=true"
	if f.has("seeker_fov_view"):
		return "a slice-37 wire must NOT raise seeker_fov_view — the loader refuses `seeker_fov_deg` beside a head (a gimballed seeker has no body-fixed window; its body-fixed limit is the mechanical STOP)"
	if f.has("gimbal_handover_view"):
		return "a slice-37 wire must NOT raise gimbal_handover_view — `gimbal_handover_err_deg` is REFUSED beside `:space_stabilized` at load, because slice 36's basket, its V and its sign convention are all stated in the BODY frame"
	var fid: Dictionary = f.get("fidelity", {})
	# ⭐⭐ THE ONE TOGGLED KEY, AND THE WIRE OPENS ON THE GOOD DESIGN so the FIRST press is the one that
	# breaks it. ⚠ A marker value-guarded on `:space_stabilized` would hide the button on exactly this
	# arm — the one direction that is fatal — which is why the core gates on the KEY, not the value.
	if str(fid.get("seeker_head", "")) != BODY:
		return "a slice-37 scenario must OPEN on :body_referenced (slice 34/35/36's shipped servo — quiet, and it hits) so that the FIRST press is the one that breaks it. Got %s" % str(fid.get("seeker_head", "<absent>"))
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-37 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS a look angle at all, and the loader refuses `gimbal_tau_s` without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-37 scenario must HOLD :airframe at six_dof — the head AND the attitude it is measured against are gated on that LIVE rung through `_gim`, so they freeze and resume together. A cross-toggle off :six_dof freezes the attitude, and a frozen attitude makes the body<->inertial conversion the IDENTITY: the two rungs would silently BECOME EACH OTHER rather than visibly break. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-37 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-37 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-37 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-37 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the aero ceiling 93.2% of its approach, a THIRD mechanism)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-37 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	if not keys.has("radome_slope_est"):
		return "the slice-37 wire must expose the 'radome_slope_est' slider — the DESIGN axis, and its job is to walk the SAME stability boundary TWICE so the press is a mechanism and not a cell"
	if str(keys["radome_slope_est"]) != MID:
		return "the R̂ knob must target the interceptor '%s'" % MID
	if keys.size() != 1:
		return "the slice-37 wire must expose EXACTLY ONE knob (got %d) — convention 9, and on this wire the second control is the BUTTON" % keys.size()
	# ⚠⚠ THE DISQUALIFICATION THAT IS NEW HERE, AND IT WAS DECIDED ON A MEASUREMENT: slice 35's servo
	# slider is AUTHORED on this wire.
	if keys.has("gimbal_rate_dps"):
		return "slice 37 must NOT expose a 'gimbal_rate_dps' knob — that is slice 35's TWO-SIDED KNOB, and putting it live beside this button would put a THIRD mechanism on a wire whose subject is the reference frame (convention 9). Its own finding here — the demand inversion at the slider's ceiling, 3.15x with a 17.5-vs-0.0 %% saturation split — is a TOOTH, measured on the AUTHORED servo"
	if keys.has("gimbal_tau_s"):
		return "slice 37 must NOT expose a 'gimbal_tau_s' knob — on this wire it moves the SIZE of the slice's own mechanism (gate 1 measured both terms moving with tau; the honest range over [0.005, 0.2] is 0 %% to 79 %%, and at tau <= 0.005 the two rungs' brackets COINCIDE). Slice 34's 'CONFOUNDED, not dead' disqualification, one slice sharper"
	if keys.has("gimbal_fov_deg"):
		return "slice 37 must NOT expose a 'gimbal_fov_deg' knob — a LIVE window makes the break an ACQUISITION break (slice 35's §C), and every `rms r` here needs the window never to bite"
	if keys.has("gimbal_stop_deg"):
		return "slice 37 must NOT expose a 'gimbal_stop_deg' knob — the stop is a RESTATEMENT of slice 33's excursion, and binding it COUPLES the two budgets"
	if keys.has("cross_speed_mps"):
		return "slice 37 must NOT expose 'cross_speed_mps' — it is slice 32's OWN axis (it moves the LEAD)"
	if keys.has("af_alpha_max") or keys.has("alpha_max"):
		return "slice 37 must NOT expose an 'alpha_max' knob — slice 26's instrument for the ring's AMPLITUDE and a confounded lever"
	if keys.has("radome_slope") or keys.has("radome_ripple") or keys.has("radome_ripple_k"):
		return "slice 37 must NOT expose the GLASS itself — a radome's slope curve is HARDWARE, and the arc's point since slice 27 is that what an engineer can change is what they BELIEVE about it"
	if keys.has("n_pn"):
		return "slice 37 must NOT expose an 'n_pn' knob — it moves the parasitic boundary AND the guidance loop"
	if keys.has("rho"):
		return "slice 37 must NOT expose a 'rho' knob — it moves the parasitic boundary and the aero ceiling at once"
	if keys.has("sigma_seek"):
		return "slice 37 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it"
	if keys.has("elevation_deg"):
		return "slice 37 must NOT expose 'elevation_deg' — the slice-19 DEAD-knob class"
	if keys.has("speed"):
		return "slice 37 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-KNOB finding)"
	if keys.has("gimbal_handover_err_deg"):
		return "slice 37 must NOT expose 'gimbal_handover_err_deg' — it is structurally a DEAD knob (slice 36's finding, and `_parse_knobs` refuses it BY NAME), and it is refused beside this rung at load anyway"
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
	var op: Dictionary = _res["open"]
	var pr: Dictionary = _res["press"]
	var aimb: Dictionary = _res["aimb"]
	var aims: Dictionary = _res["aims"]
	var cb: Dictionary = _res["ceilb"]
	var cs: Dictionary = _res["ceils"]
	var mp: Dictionary = _res["midpress"]
	var bb := _largest_step([_res["b210"], _res["b205"], op, _res["b175"], _res["b170"], _res["b165"]])
	var sb := _largest_step([_res["s210"], _res["s205"], pr, _res["s175"], _res["s170"], _res["s165"]])
	print(("S37V OK: slice 34 gave the seeker a head and bought a stability margin with it; slice 35 gave " +
		"that head a real servo. This slice asks what frame the servo closes in — and ⚠⚠ THE DEFERRAL " +
		"THAT NAMED IT WAS WRONG: 'a rate-stabilized head measures inertial LOS rate directly' is " +
		"ALREADY TRUE of this model (`missile.jl:1652` is `az_el(u_tru)`), so the seeker has reported " +
		"INERTIAL angles since slice 25. What is body-referenced is the SERVO. ⭐⭐ AND STABILIZING IT " +
		"REMOVES MARGIN — THE CLASSICAL REASON GIMBALS EXIST INVERTS ON THIS WIRE — because the " +
		"position servo's LAG was doing stability work nobody asked it for: it LOW-PASSES the missile's " +
		"own body motion out of the radome's INDEX, and slice 26's limit cycle lives at 1.7-2.1 Hz, " +
		"exactly where a tau = 0.05 s filter is worth 12-16 %% of gain and ~30 deg of phase. ⭐⭐ THE " +
		"DEMONSTRATION IS ONE BUTTON PRESS ON A DESIGN THAT WAS ALREADY GOOD: at R̂ %+.2f the " +
		"body-referenced head is QUIET (rms r %.5f, intercept %.3f m) and the SAME missile — same " +
		"glass, same believed slope, same seed, same servo, same handover — RINGS at %.5f (%.1fx) when " +
		"the head is held in space, and STILL HITS (%.3f m). ⭐ THE ONSET IS FOUND TWICE, ONCE PER " +
		"FRAME, quoted BRACKET TO BRACKET: body-referenced (%+.3f, %+.3f] at %.2fx, space-stabilized " +
		"(%+.3f, %+.3f] at %.2fx — and the two are DISJOINT from both sides (across the space bracket " +
		"the body rung is still on its plateau at %.5f, across the body bracket the space rung is " +
		"already ringing at %.5f), which is what makes it one ladder walked twice rather than two " +
		"readings of one boundary. ⚠⚠ THE ONSET RULE IS THE LARGEST SINGLE-STEP RATIO AND IS " +
		"THRESHOLD-FREE BY CONSTRUCTION (gate 0's advisor catch: a chosen `rms r > 0.20` was " +
		"load-bearing, and the body rung reads %.5f at %+.3f — 13 %% below it and an order of magnitude " +
		"above its own plateau). The whole ladder is printed above so a reader can redraw the line; the " +
		"~40-45 %% of margin given back MOVES with that rule and is quoted as a RANGE, while THE ORDER " +
		"OF THE RUNGS AND THE SIGN OF THE EFFECT are threshold-free. ⭐⭐ THE CURE IS SLICE 30's RULE " +
		"PAYING A FOURTH TIME (33 = FOV, 34 = detector window, 35 = servo bandwidth, 37 = the head's " +
		"REFERENCE FRAME), AND THE PROOF IS A CONTROL GOING DEAD: at the aim point R0+2A = %+.4f, READ " +
		"OFF THE WIRE, the two rungs read %.5f and %.5f — %.3fx, against %.1fx at the default — so aim " +
		"R̂ at the glass's worst-case slope and THE ARCHITECTURE DOES NOT MATTER. That is the slider's " +
		"FLOOR and the reason it is there. ⚠ AND IT IS NOT FREE IN THE ONE CURRENCY A SERVO HAS: at " +
		"the slider's CEILING, where BOTH rungs ring (%.5f / %.5f, %.2fx) and a demand comparison is " +
		"therefore legal at all, the space-stabilized head RINGS HARDER AND ASKS FOR %.2fx LESS PEAK " +
		"SLEW (%.3f against %.3f deg/s), never touching the %.0f deg/s servo the body-referenced head " +
		"saturates on %.2f %% of the band. ⇒ THE BODY-REFERENCED SERVO'S DEMAND IS ALMOST ALL BODY " +
		"MOTION, NOT TARGET MOTION — and it does NOT license 'the stabilized head is the cheaper " +
		"build': cheaper in SERVO BANDWIDTH, dearer in STABILITY MARGIN, which is slice 35's " +
		"one-knob-two-bounds shape moved onto the ARCHITECTURE. ⭐⭐ THE BUTTON IS BACK FOR THE FIRST " +
		"TIME SINCE SLICE 25 and the marker that restores it is the first of this family to UN-DROP " +
		"rather than drop; pressed MID-FLIGHT at tick %d it takes effect and the engagement survives it " +
		"(rms r %.5f against %.5f from launch, miss %.3f m). ⚠ Every arm HITS on BOTH rungs, the " +
		"detector window NEVER bites (out = 0.00 %% on all %d arms — the precondition that makes every " +
		"rms r here a stability read), `defl_sat` is 0 everywhere, and the head's travel stays inside " +
		"both the 30 deg stop and the small-angle budget. ⚠ NO new rung beyond this one, no new cap, no " +
		"new instability, no new draw. Class 4a, the THIRTEENTH consecutive RNG-live slice, replay " +
		"bit-identical on BOTH rungs (max|Δpos| = 0.0).")
		% [float(op["rhat"]), float(op["rms"]), float(op["miss"]), float(pr["rms"]),
		   float(pr["rms"]) / maxf(float(op["rms"]), 1.0e-12), float(pr["miss"]),
		   float(bb["lo"]), float(bb["hi"]), float(bb["ratio"]),
		   float(sb["lo"]), float(sb["hi"]), float(sb["ratio"]),
		   float(_res["b205"]["rms"]), float(_res["s170"]["rms"]),
		   float(_res["b165"]["rms"]), RHAT_165,
		   float(aimb["worst"]), float(aimb["rms"]), float(aims["rms"]),
		   float(aims["rms"]) / maxf(float(aimb["rms"]), 1.0e-12),
		   float(pr["rms"]) / maxf(float(op["rms"]), 1.0e-12),
		   float(cb["rms"]), float(cs["rms"]), float(cs["rms"]) / maxf(float(cb["rms"]), 1.0e-12),
		   float(cb["dem95"]) / maxf(float(cs["dem95"]), 1.0e-9),
		   float(cs["dem95"]), float(cb["dem95"]), RATE_AUTH, float(cb["sat"]),
		   PRESS_AT, float(mp["rms"]), float(pr["rms"]), float(mp["miss"]), _arms.size()])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S37V FAIL: " + msg)
	print("S37V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
