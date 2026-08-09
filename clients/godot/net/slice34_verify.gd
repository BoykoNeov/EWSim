extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-34 gate-3 verifier — THE GIMBAL: THE HEAD POINTS WHERE THE GLASS SAYS THE TARGET IS.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice34_gimbal.yaml
#   godot --headless --path clients/godot --script res://net/slice34_verify.gd     (exit 0 = pass)
#
# ⚠⚠ IT FLIES BOTH SHIPPED WIRES, THROUGH ONE `load_scenario` — start it on the GIMBAL scenario and
# it switches to `slice34_strapdown.yaml` itself (the slice-7 pattern). That is not a convenience: the
# HEADLINE IS A COMPARISON BETWEEN TWO WIRES, because a head is not a fidelity. `gimbal_tau_s` is
# AUTHORED (gate 2 measured τ a CONFOUNDED lever, not a dead one) and NO in-domain slider value
# removes a head — τ → 0 does not, since the head that ships tracks its own BENT, one-tick-delayed
# measurement and is ALREADY QUIET there. So the foil is a second YAML, and a verifier that only flew
# one of them would be asserting half a claim (slice 22's two-scenario precedent).
#
# THE LESSON. Slices 26–33 built the parasitic loop on one geometric fact: the radome bends the ray by
# an amount set by the LOOK ANGLE, and the look angle is the LOS measured off the missile's OWN NOSE —
# a quantity the missile can only move by ROTATING, which is why slice 26 is a BODY-RATE instability.
# A gimballed seeker breaks that identity: the ray passes through the part of the dome the HEAD is
# aimed at, and THE HEAD IS AIMED BY THE VERY MEASUREMENT THE DOME JUST BENT. The index of the glass
# becomes a FIXED POINT of the glass, slice 26's loop is partly re-closed THROUGH THE HEAD where its
# sign is NEGATIVE, and the onset walks two rungs of the ladder.
#
# ⚠⚠ THE TWO-RUN DISCIPLINE IS THE SHIPPED STRUCTURE OF THIS FILE, NOT A COMMENT — inherited from
# slice 33 and MANDATORY here for a second, independent reason gate 0 measured: the head HOLDS when it
# loses its error signal, so a broken detector window FREEZES the index, and a frozen index produces a
# CONSTANT bend, which is QUIET AT EVERY R̂. ⇒ on a windowed arm `rms r` FALLS while the miss OPENS.
# ⚠⚠ AND THE LIST IS THREE QUANTITIES, NOT TWO — THE THIRD FAILS QUIETLY. `rms r` falls and the
# tracking error runs away to ~90 deg (both visibly wrong), but `head_angle_deg` FREEZES at the value
# it held when the track broke, so a windowed arm reads the QUIET arms' 17.19 deg against the ring's
# actual 20.62 deg: a plausible number, in range, on the LOW side. A file that read the excursion off a
# windowed run would report that the ring costs nothing. ⇒ every predictor here comes off a FREE arm
# (the detector-window slider at its CEILING) and every predicted quantity off a WINDOWED one, bound
# at the call sites.
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`), and the constants below are sized off FRAME
# columns, never off the per-tick suite's ([[ewsim-missile-verifier-sampling]] — the error is
# ASYMMETRIC: a MISS samples faithfully, a HIT samples COARSELY). The per-tick headline is 78.9x; the
# frame grid reads ~77x, and the head travel reads 17.19 deg where the core flies 18.12.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 2400.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — every slider on both wires lives here
const GIM_PATH := "scenarios/slice34_gimbal.yaml"
const STRAP_PATH := "scenarios/slice34_strapdown.yaml"

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16, on BOTH wires — asserted core-side
# in `test_missile.jl`). The server emits every 16th tick, so a STEPS that is not a multiple makes the
# last frame land BELOW `STEPS*dt` and `_drain_scan` waits forever, SILENTLY, with no output at all
# (slice 31 lost an hour to exactly this and it reads like a slow wire). 12800 = 16 * 800.
# ⚠ SIZED OFF THE SLOWEST ARM, MEASURED: ToF spans 6.91 s (the badly broken R̂ = -0.03 arm, which flies
# past early) to 11.25 s (the quiet cure arm at slice 30's aim point). 12.8 s leaves ~1.5 s of
# headroom, and EVERY arm asserts it REACHED CPA rather than trusting the sizing.
const STEPS := 12800

const WIN_FREE := 8.0             # the detector-window slider's CEILING = THE FREE READ (bit-identical
                                  # to the key being absent, measured core-side as CONTROL B)
const WIN_SHIP := 4.0             # the shipped default — a free read ON THE APPROACH, not bit-identical
const WIN_FLOOR := 1.0            # the slider's floor: deep in the broken regime, band still alive
const RHAT_SHOW := -0.18          # ⭐⭐ THE SHOWCASE RESIDUAL: INSIDE the strapdown ring bracket
                                  # (-0.27, -0.24] and OUTSIDE the gimballed one (-0.18, -0.16]
const RHAT_16 := -0.16            # the first RINGING gimbal arm — and the head_max STEP
const RHAT_24 := -0.24            # slice 30's "last decisive ring" on the strapdown ladder
const RHAT_27 := -0.27            # …and the quiet rung above it
const RHAT_03 := -0.03            # slice 28's boresight characterization: the LOUDEST arm
const RHAT_33 := -0.33            # slice 30's aim point (R0 + 2A), read off the wire where it matters
const RHAT_36 := -0.36            # ⭐ THE R̂ SLIDER'S FLOOR, PAST the aim point — flown on BOTH wires
                                  # because slice 26's post-commit rule is that a declared domain's
                                  # ENDPOINTS ARE MEASURED, never inferred from the interior. The
                                  # gate-3 post-review found this one flown NOWHERE.
const BRACKET := 0.1              # the predicate bracket, either side of the MEASURED tracking error

const RING := 0.30                # the arc's ring/quiet line, the same one slices 30/33 read against
const HIT_MAX := 10.0             # measured 1.4-7.1 m frame-sampled; the core flies 0.03-0.19
const BREAK_MISS_MIN := 100.0     # measured 201 / 269 / 1029 / 3704 m
const RUNAWAY_OFF_MIN := 60.0     # the post-lock-loss signature: 89.9 / 89.9 / 73.6 deg
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
var _wire := "gimbal"             # which YAML is loaded right now
var _await_scn := false           # a `load_scenario` is in flight; the next "scenario" frame is ours

# per-arm accumulators — ALL CLOSING-LEG ONLY (past CPA the target is BEHIND the missile and every
# angle here is meaningless; slice 32's gate-3 correction, inherited with its reason)
var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0                  # closing frames with r > 200 m — the angle / window window
var _n_out := 0                   # …of which the head had NO error signal
var _max_head := 0.0              # the head's TRAVEL (vs the STOP) — slice 33's excursion, RESTATED
var _max_off := 0.0               # the head's TRACKING ERROR (vs the DETECTOR window) — NEW
var _max_body := 0.0              # the NOSE's look angle: what a strapdown seeker WOULD have indexed
var _min_marg := 1.0e30           # the SIGNED detector budget — THE SIGN IS THE VERDICT
var _n_band := 0                  # closing frames with 500 < r < 3000 — the isolation window
var _n_aero := 0
var _n_defl := 0
var _sum_r2 := 0.0                # for rms r — the RING, legible on the FREE arms ONLY
var _t_break := -1.0
var _r_break := -1.0
var _win_seen := 0.0
var _rhat_seen := 0.0
var _stop_seen := 0.0
var _worst := 0.0                 # slice 30's aim point, READ OFF THE WIRE (never recomputed)
var _n_idx_bad := 0               # ticks where `look_angle` was NOT the head's own angle
var _n_nose_idx := 0              # …or WAS the nose's
var _pos_trace: Array = []

func _initialize() -> void:
	print("S34V_INIT godot=", Engine.get_version_info().string)
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
		var verr := _check_handshake(f, "gimbal")
		if verr != "":
			return _fail(verr)
		_dt = float(f.get("dt_physics", 1.0e-3))
		_handshaked = true
		_build_arms()
		_start_next()
		return false

	# A wire switch is in flight — the next "scenario" frame is the TWIN's handshake, and it is
	# CHECKED rather than merely awaited (the twin has its own marker set and its own single knob).
	if _await_scn:
		var sf := _take("scenario")
		if sf.is_empty():
			return false
		var serr := _check_handshake(sf, _wire)
		if serr != "":
			return _fail(serr)
		_await_scn = false
		_launch_arm()
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
	# ⚠⚠ THE FREE LADDER RUNS FIRST, AND THAT ORDERING IS LOAD-BEARING RATHER THAN TIDY: the
	# predicate bracket is specified RELATIVE to a tracking error THIS RUN measures, and slice 30's
	# aim point is read off the wire's own telemetry (it is -0.32999999999999996, not -0.33). Nothing
	# below hardcodes either — the slice-21 magic-multiple tooth, pinned against a measured quantity.
	#
	# 1) THE FREE LADDER on the GIMBAL wire — the detector-window slider at its CEILING. This is the
	#    ONLY place a stability verdict, a head travel or a tracking error may be read.
	_arms.append({"tag": "g33", "win": WIN_FREE, "rhat": RHAT_33})
	_arms.append({"tag": "g24", "win": WIN_FREE, "rhat": RHAT_24})
	_arms.append({"tag": "g18", "win": WIN_FREE, "rhat": RHAT_SHOW})
	_arms.append({"tag": "g16", "win": WIN_FREE, "rhat": RHAT_16})
	_arms.append({"tag": "g03", "win": WIN_FREE, "rhat": RHAT_03})
	# 2) THE SHIPPED WIRE, untouched (window 4 deg, R̂ = -0.18) — and its REPLAY.
	_arms.append({"tag": "open"})
	_arms.append({"tag": "replay"})
	# 3) THE SAME LADDER THROUGH THE SHIPPED WINDOW — the ENVELOPE read, and the client-drivable
	#    payload: THE RING IS SPENT IN DETECTOR WINDOW.
	_arms.append({"tag": "w16", "win": WIN_SHIP, "rhat": RHAT_16})
	_arms.append({"tag": "w03", "win": WIN_SHIP, "rhat": RHAT_03})
	_arms.append({"tag": "w33", "win": WIN_SHIP, "rhat": RHAT_33})
	# 4) THE PREDICATE, AS A BRACKETING PAIR AROUND THE MEASURED TRACKING ERROR — never `ceil`
	#    (gate 2 measured that rule SUFFICIENT BUT NOT TIGHT on a 0.1 deg grid; the PHYSICAL claim is
	#    the inequality `held <=> window > tracking error`).
	_arms.append({"tag": "brlo", "win_ref": "g18", "win_off": -BRACKET, "rhat": RHAT_SHOW})
	_arms.append({"tag": "brhi", "win_ref": "g18", "win_off": BRACKET, "rhat": RHAT_SHOW})
	# 5) THE DOMAIN FLOOR — the price, at the WINDOW slider's own bottom.
	_arms.append({"tag": "floor", "win": WIN_FLOOR, "rhat": RHAT_SHOW})
	# 5b) ⭐ THE *OTHER* SLIDER'S FLOOR, PAST slice 30's aim point (the gate-3 post-review catch).
	#     Not hygiene: past the aim point the engagement residual goes POSITIVE, which DE-TUNES rather
	#     than rings — but a de-tuned loop LAGS, lag grows the LEAD, and the lead is what the head's
	#     TRAVEL must cover (vs the stop) and what sets the TRACKING ERROR (vs the window). If either
	#     crossed, the student's own "overshoot cure B" gesture would break the arm.
	_arms.append({"tag": "gfloor", "win": WIN_SHIP, "rhat": RHAT_36})
	# 6) THE TWIN — the SAME glass, the SAME residual, the SAME seed, with the head REMOVED.
	_arms.append({"tag": "s18", "wire": "strapdown", "rhat": RHAT_SHOW})
	_arms.append({"tag": "s24", "wire": "strapdown", "rhat": RHAT_24})
	_arms.append({"tag": "s27", "wire": "strapdown", "rhat": RHAT_27})
	_arms.append({"tag": "s33", "wire": "strapdown", "rhat": RHAT_33})
	_arms.append({"tag": "s36", "wire": "strapdown", "rhat": RHAT_36})   # …the same floor, both wires

func _start_next() -> void:
	_idx += 1
	var wire := str(_arms[_idx].get("wire", "gimbal"))
	if wire != _wire:
		# ⚠ THE WIRE SWITCH CLEARS THE INBOX FIRST: a `load_scenario` re-handshakes, and any state
		# frames still queued from the previous arm would otherwise be drained against the new one.
		_wire = wire
		_inbox.clear()
		_await_scn = true
		_client.send({"type": "load_scenario",
					  "path": STRAP_PATH if wire == "strapdown" else GIM_PATH})
		return
	_launch_arm()

func _launch_arm() -> void:
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("win"):
		cmds.append(_set_param_cmd(MID, "gimbal_fov_deg", float(arm["win"])))
	elif arm.has("win_ref"):
		# PINNED AGAINST WHAT THIS RUN MEASURED, not against a literal.
		var base: float = float(_res[str(arm["win_ref"])]["off"])
		cmds.append(_set_param_cmd(MID, "gimbal_fov_deg", base + float(arm["win_off"])))
	if arm.has("rhat"):
		cmds.append(_set_param_cmd(MID, "radome_slope_est", float(arm["rhat"])))
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
	# ⚠⚠ NaN, NOT 0.0, WHEN THE BAND IS EMPTY — slice 33's gate-2 finding, and this file inherits it
	# because it flies the arms it was found on: the R̂ = -0.03 arm through the shipped window misses
	# by 3.7 km, so it never enters r in [500, 3000] at all. A `sum/max(n,1)` would print a
	# beautifully quiet `rms r = 0.00000` COMPUTED FROM ZERO SAMPLES on exactly the worst arm.
	var rms := NAN if _n_band == 0 else sqrt(_sum_r2 / float(_n_band))
	var aero_pc := NAN if _n_band == 0 else 100.0 * float(_n_aero) / float(_n_band)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		# ⚠ NaN, NOT the 1e30 sentinel, when the key never appeared — the TWIN ships no
		# `gimbal_fov_margin_deg` at all (the never-stale discipline), and a sentinel printed into
		# the arm line reads like a measurement of something.
		"head": _max_head, "off": _max_off, "body": _max_body,
		"marg": NAN if _min_marg > 1.0e29 else _min_marg,
		"band": _n_band, "aero": aero_pc, "defl": _n_defl, "rms": rms,
		"tbrk": _t_break, "rbrk": _r_break, "win": _win_seen, "rhat": _rhat_seen,
		"stop": _stop_seen, "worst": _worst, "wire": _wire,
		"idxbad": _n_idx_bad, "noseidx": _n_nose_idx, "pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S34V_ARM   %-6s %-9s win=%.4f  R̂=%+.4f  ->  %s   miss=%.3f  out=%.3f%% of %d gated " +
		   "frames  head_max=%.3f  off_max=%.3f  body_max=%.3f  margin_min=%.2f  rms_r=%.5f (%d band " +
		   "frames)  aero=%.2f%%  defl=%d  break t=%.3f r=%.1f  cpa=%s") %
		  [tag, m["wire"], m["win"], m["rhat"], "TRACK LOST" if out_pc > 0.0 else "held",
		   m["miss"], out_pc, m["gate"], m["head"], m["off"], m["body"], m["marg"], m["rms"],
		   m["band"], m["aero"], m["defl"], m["tbrk"], m["rbrk"], "Y" if m["turned"] else "N"])
	if not (_n_gate > 100):
		return ("arm %s: the r > 200 m window must contain frames to measure (got %d) — every angle, " +
				"budget and out-of-window assert on this arm would be vacuous") % [tag, _n_gate]
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was still " +
				"closing at the end, so its miss (%.3f m) is a last closing range and not a CPA at " +
				"all. ToF spans 6.91-11.25 s across this file, so STEPS is sized off the SLOWEST arm " +
				"and every arm asserts this rather than trusting the sizing") % [tag, STEPS, _min_los]
	# ⭐⭐ THE INDEX, ON EVERY GIMBAL FRAME OF EVERY GIMBAL ARM. Slice 26's `look_angle` ships the angle
	# the glass was ACTUALLY evaluated at, and under a head the seam sets `look_az, look_el = head_az,
	# head_el` BEFORE the bend is taken — so it must equal `head_angle_deg` to the bit and must NEVER
	# equal `look_body_deg`, the NOSE's angle a strapdown seeker would have used. That triple IS the
	# slice, and asserting it here rather than in the verdict makes it a per-frame invariant instead
	# of an end-of-run coincidence.
	if _wire == "gimbal" and not (_n_idx_bad == 0 and _n_nose_idx == 0):
		return ("arm %s: THE INDEX. `look_angle` must BE the head's own angle on every frame " +
				"(%d frames where it was not) and must never be the NOSE's (%d frames where it was). " +
				"If this fires, the glass is being indexed off the airframe and this slice does not " +
				"exist") % [tag, _n_idx_bad, _n_nose_idx]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var g33: Dictionary = _res["g33"]
	var g24: Dictionary = _res["g24"]
	var g18: Dictionary = _res["g18"]
	var g16: Dictionary = _res["g16"]
	var g03: Dictionary = _res["g03"]
	var op: Dictionary = _res["open"]
	var w16: Dictionary = _res["w16"]
	var w03: Dictionary = _res["w03"]
	var w33: Dictionary = _res["w33"]
	var blo: Dictionary = _res["brlo"]
	var bhi: Dictionary = _res["brhi"]
	var flr: Dictionary = _res["floor"]
	var s18: Dictionary = _res["s18"]
	var s24: Dictionary = _res["s24"]
	var s27: Dictionary = _res["s27"]
	var s33: Dictionary = _res["s33"]

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE FREE — the licence for every prediction below, and the arc's standing fact re-measured.
	print("S34V_FREE     the detector-window slider at its ceiling (%.0f deg): R̂ %+.2f / %+.2f / %+.2f / %+.2f / %+.2f -> rms r %.5f / %.5f / %.5f / %.5f / %.5f, tracking error %.3f / %.3f / %.3f / %.3f / %.3f deg, head travel %.3f / %.3f / %.3f / %.3f / %.3f deg, and the miss is %.3f / %.3f / %.3f / %.3f / %.3f m — EVERY ONE OF THEM HITS" %
		  [WIN_FREE, float(g33["rhat"]), float(g24["rhat"]), float(g18["rhat"]), float(g16["rhat"]), float(g03["rhat"]),
		   float(g33["rms"]), float(g24["rms"]), float(g18["rms"]), float(g16["rms"]), float(g03["rms"]),
		   float(g33["off"]), float(g24["off"]), float(g18["off"]), float(g16["off"]), float(g03["off"]),
		   float(g33["head"]), float(g24["head"]), float(g18["head"]), float(g16["head"]), float(g03["head"]),
		   float(g33["miss"]), float(g24["miss"]), float(g18["miss"]), float(g16["miss"]), float(g03["miss"])])
	for k in ["g33", "g24", "g18", "g16", "g03"]:
		var a: Dictionary = _res[k]
		# ⚠⚠ THE FREE READ IS A MEASUREMENT, NOT AN ASSUMPTION. A live wire always carries the key, so
		# "no window at all" is unreachable — the domain CEILING stands in for it, and it is only
		# legitimate if the window is NEVER REACHED on these arms. If this fires, every excursion and
		# tracking error below is contaminated by the ~90 deg post-lock-loss runaway.
		if not (float(a["out"]) == 0.0):
			return _fail(("PHASE FREE, arm %s: the free-read arm must never leave its window (%.3f %% " +
				"out). The window slider's ceiling stands in for 'no window at all', and the tracking " +
				"error it supplies is only the HEAD's if the window is never reached") %
				[k, float(a["out"])])
		if not (float(a["miss"]) < HIT_MAX):
			return _fail(("PHASE FREE, arm %s: THE STANDING FACT OF SLICES 26-33 must hold — a ringing " +
				"arm with an effectively infinite window STILL HITS (%.3f m, must be < %.1f). Slice 26 " +
				"wrote it first and 27/28/29/30/31/33 each inherited it. If this fires, the ring has " +
				"started costing accuracy and the whole family's choice of metric is wrong") %
				[k, float(a["miss"]), HIT_MAX])
		# and the model-validity budget 28/29/30/31 each declared is still headroom, not a stop
		if not (float(a["head"]) < MODEL_VALID_DEG and float(a["head"]) < float(a["stop"])):
			return _fail(("PHASE FREE, arm %s: the head's travel (%.3f deg) must stay inside BOTH the " +
				"small-angle bend budget (%.0f deg) and the mechanical stop (%.3f deg). The stop is a " +
				"RESTATEMENT of slice 33's excursion and must not bind on this wire — if it does, the " +
				"deficit is charged to the DETECTOR budget and the two limits stop being separable") %
				[k, float(a["head"]), MODEL_VALID_DEG, float(a["stop"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE HEADLINE — ⭐⭐ THE SAME GLASS, THE SAME BELIEVED SLOPE, THE SAME SEED, TWO WIRES.
	var ratio: float = float(s18["rms"]) / maxf(float(g18["rms"]), 1.0e-9)
	print("S34V_HEADLINE at R̂ %+.2f on glass R0 = -0.03 / A = -0.15, the STRAPDOWN twin rings at rms r %.5f while the GIMBALLED wire sits at %.5f — %.1fx — and the nose that carries the strapdown index swings to %.3f deg against the head's own %.3f deg. Both HIT (%.3f vs %.3f m): the miss is not the metric here either" %
		  [RHAT_SHOW, float(s18["rms"]), float(g18["rms"]), ratio,
		   float(s18["body"]), float(g18["head"]), float(s18["miss"]), float(g18["miss"])])
	if not (int(s18["band"]) > 0 and int(g18["band"]) > 0):
		return _fail("PHASE HEADLINE: both arms must have band frames before any band number is quoted (%d, %d)" % [int(s18["band"]), int(g18["band"])])
	if not (float(s18["rms"]) > RING and float(g18["rms"]) < RING):
		return _fail(("⭐⭐ THE HEADLINE: the SAME believed slope on the SAME glass must RING strapdown " +
			"(rms r %.5f, must exceed %.2f) and be QUIET gimballed (%.5f, must be under it). This is " +
			"the whole slice — nothing about the missile, the glass, the engagement or the seed " +
			"changed except WHERE THE GLASS IS INDEXED") % [float(s18["rms"]), RING, float(g18["rms"])])
	if not (ratio > 50.0):
		return _fail(("⭐⭐ THE HEADLINE: the ratio must be large enough to be a verdict and not a " +
			"trend (%.1fx, must exceed 50). The core measures 78.9x per tick; this grid reads ~77x") % ratio)
	if not (float(s18["miss"]) < HIT_MAX and float(g18["miss"]) < HIT_MAX):
		return _fail(("PHASE HEADLINE: BOTH arms must HIT (%.3f, %.3f m) — the arc's standing fact " +
			"since slice 26, and the reason the verdict is rms r and never a miss") %
			[float(s18["miss"]), float(g18["miss"])])
	# ⚠ AND THE TWIN MUST BE THE STRAPDOWN WIRE, not a gimbal wire with a wide window: no head key at
	# all reaches this run (asserted per-frame in `_drain_scan` via `_stop_seen`).
	if not (float(s18["stop"]) == 0.0 and float(s18["head"]) == 0.0 and float(s18["off"]) == 0.0):
		return _fail(("PHASE HEADLINE: the twin must ship NO head telemetry at all (stop %.3f, head " +
			"%.3f, off %.3f — all must be 0, the never-stale discipline: `_gim` is false there so not " +
			"one head key is even evaluated). If any of these are live, the two wires are not the " +
			"pair this file claims") % [float(s18["stop"]), float(s18["head"]), float(s18["off"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE BRACKET — ⭐ TWO RUNGS OF THE SAME LADDER, FROM THE SAME SLIDER, ON THE SAME GLASS.
	print("S34V_BRACKET  the SAME R̂ slider on both wires: STRAPDOWN quiet at %+.2f (rms r %.5f) and RINGING at %+.2f (%.5f) -> bracket (%+.2f, %+.2f]; GIMBALLED quiet at %+.2f (%.5f) and RINGING at %+.2f (%.5f) -> bracket (%+.2f, %+.2f]. TWO RUNGS, quoted BRACKET TO BRACKET and never as one number" %
		  [RHAT_27, float(s27["rms"]), RHAT_24, float(s24["rms"]), RHAT_27, RHAT_24,
		   RHAT_SHOW, float(g18["rms"]), RHAT_16, float(g16["rms"]), RHAT_SHOW, RHAT_16])
	if not (float(s27["rms"]) < RING and float(s24["rms"]) > RING):
		return _fail(("PHASE BRACKET: the STRAPDOWN onset must reproduce slice 30's own bracket " +
			"(-0.27, -0.24] — quiet %.5f, ringing %.5f against the %.2f line. This is the column " +
			"convention 2 checks byte-identity ON THE WIRE with") %
			[float(s27["rms"]), float(s24["rms"]), RING])
	if not (float(g18["rms"]) < RING and float(g16["rms"]) > RING):
		return _fail(("PHASE BRACKET: the GIMBALLED onset must be (-0.18, -0.16] — quiet %.5f, ringing " +
			"%.5f") % [float(g18["rms"]), float(g16["rms"])])
	# ⚠ AND THE TWO BRACKETS MUST BE DISJOINT AND ORDERED, which is what "two rungs" means. The gap
	# they admit spans 0.06 to 0.11, so a single number for the shift would be one neither wire supports.
	if not (RHAT_SHOW > RHAT_24):
		return _fail("PHASE BRACKET: the gimballed bracket must sit ABOVE the strapdown one on the ladder")
	# ⭐ THE SECOND TELL, FROM A DIFFERENT QUANTITY — the head's TRAVEL steps at the same place. This
	# is what makes the bracket a MEASUREMENT and not a threshold read off the metric that defined it.
	print("S34V_TELL     head travel is FLAT at %.3f / %.3f / %.3f deg through the quiet arms (it is tracking the engagement's own lead and nothing else) and STEPS to %.3f at the first ringing one and %.3f at the loudest — a SECOND, INDEPENDENT tell from a DIFFERENT quantity" %
		  [float(g33["head"]), float(g24["head"]), float(g18["head"]), float(g16["head"]), float(g03["head"])])
	if not (absf(float(g33["head"]) - float(g18["head"])) < 0.01
			and absf(float(g24["head"]) - float(g18["head"])) < 0.01):
		return _fail(("PHASE TELL: the head's travel must be FLAT across the quiet arms (%.3f / %.3f / " +
			"%.3f deg) — it is tracking the ENGAGEMENT's lead there and nothing else") %
			[float(g33["head"]), float(g24["head"]), float(g18["head"])])
	if not (float(g16["head"]) > float(g18["head"]) + 2.0 and float(g03["head"]) > float(g16["head"])):
		return _fail(("PHASE TELL: and it must STEP at the onset (%.3f -> %.3f deg at R̂ %+.2f -> %+.2f, " +
			"then %.3f at %+.2f) — without this the bracket rests on the single metric that defined it") %
			[float(g18["head"]), float(g16["head"]), RHAT_SHOW, RHAT_16, float(g03["head"]), RHAT_03])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE PRICE — ⭐⭐ SLICE 32's PREDICATE IN THE CURRENCY A GIMBAL HAS: `held <=> error < window`.
	print("S34V_PRICE    against a MEASURED tracking error of %.4f deg: a detector window %.1f deg SHORT breaks (%.3f %% out, %.1f m, lock lost at t = %.3f s / r = %.1f m) and %.1f deg OVER holds (%.3f %% out, %.3f m) and flies the free arm's own error (%.4f vs %.4f deg). ⚠ The two sides come from DIFFERENT RUNS — the error off a FREE arm, the verdict off a WINDOWED one" %
		  [float(g18["off"]), BRACKET, float(blo["out"]), float(blo["miss"]), float(blo["tbrk"]),
		   float(blo["rbrk"]), BRACKET, float(bhi["out"]), float(bhi["miss"]),
		   float(bhi["off"]), float(g18["off"])])
	if not (float(blo["out"]) > 0.0 and float(blo["miss"]) > BREAK_MISS_MIN):
		return _fail(("PHASE PRICE: a detector window a tenth of a degree BELOW the measured tracking " +
			"error must BREAK (%.3f %% out, %.3f m). ⚠ ASSERTED AS AN INEQUALITY, NEVER AS `ceil` — " +
			"gate 2 measured that rule SUFFICIENT BUT NOT TIGHT on a 0.1 deg grid, and gate 0's 16/16 " +
			"agreement was an artifact of its 1 deg one") % [float(blo["out"]), float(blo["miss"])])
	# ⚠ THE MISS TOLERANCE HERE IS 0.05 m AND THAT IS MEASURED, NOT SLACK: a 2.05 deg window is
	# reached by the endgame LOS swing far earlier than the shipped 4 deg one, so the CPA moves by
	# 0.020 m where the shipped arm moves by ~1e-10 (see `_held`). The EXACT claim is on the GATED
	# quantities — the tracking error and the head travel both match to 1e-6 — and this file's first
	# run FAILED here at a flat 1e-6 inherited from slice 33, which is how the dependence was found.
	var herr := _held(bhi, g18, "brhi (a tenth of a degree OVER the measured tracking error)", 0.05)
	if herr != "":
		return _fail(herr)
	# ⭐ AND THE RING IS SPENT IN DETECTOR WINDOW — slice 33's payload, in the quantity a gimbal has.
	print("S34V_SPEND    the tracking error the detector must cover grows %.4f -> %.4f -> %.4f deg (%.1fx) as R̂ walks from slice 30's aim point to slice 28's boresight characterization — the SAME slider that moves the ring moves the bill it sends the detector" %
		  [float(g33["off"]), float(g18["off"]), float(g03["off"]),
		   float(g03["off"]) / maxf(float(g33["off"]), 1.0e-9)])
	if not (float(g03["off"]) > 2.0 * float(g18["off"])):
		return _fail(("PHASE SPEND: the RINGING design must demand MEASURABLY more detector window than " +
			"the quiet one (%.4f vs %.4f deg, must be more than 2x). This is slice 33's payload in the " +
			"new currency, and it is why the two sliders are ONE axis") %
			[float(g03["off"]), float(g18["off"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE ENVELOPE — the client-drivable half: at the SHIPPED window, walking R̂ up BREAKS the track.
	print("S34V_ENVELOPE through the shipped %.0f deg window: R̂ %+.2f holds (%.3f m, budget floor %+.2f deg), %+.2f holds (%.3f m), %+.2f BREAKS at t = %.3f s / r = %.1f m (%.3f %% out, %.1f m) and %+.2f breaks at t = %.3f s / r = %.1f m (%.3f %% out, %.1f m, %.0fx the shipped miss)" %
		  [WIN_SHIP, float(op["rhat"]), float(op["miss"]), float(op["marg"]),
		   float(w33["rhat"]), float(w33["miss"]),
		   float(w16["rhat"]), float(w16["tbrk"]), float(w16["rbrk"]), float(w16["out"]), float(w16["miss"]),
		   float(w03["rhat"]), float(w03["tbrk"]), float(w03["rbrk"]), float(w03["out"]), float(w03["miss"]),
		   float(w03["miss"]) / maxf(float(op["miss"]), 1.0e-9)])
	# THE SHIPPED DEFAULT IS A FREE READ ON THE APPROACH — measured, and it is what licenses reading a
	# stability verdict off the wire a student actually opens. ⚠ It is NOT bit-identity: the window IS
	# reached in the last metres as the LOS unit vector swings at r -> 0 (slice 33's endgame finding).
	herr = _held(op, g18, "open (the shipped wire — a FREE READ ON THE APPROACH, not bit-identical)")
	if herr != "":
		return _fail(herr)
	if not (float(w16["out"]) > 0.0 and float(w16["miss"]) > BREAK_MISS_MIN):
		return _fail(("PHASE ENVELOPE: at the shipped window, the FIRST RINGING design must break " +
			"(%.3f %% out, %.3f m). The ring's tracking error (%.4f deg free) is past the %.0f deg " +
			"window while the quiet design's (%.4f deg) is not — that is the ENVELOPE, spent") %
			[float(w16["out"]), float(w16["miss"]), float(g16["off"]), WIN_SHIP, float(g18["off"])])
	if not (float(w03["out"]) > 50.0 and float(w03["miss"]) > 3000.0):
		return _fail(("PHASE ENVELOPE: and the LOUDEST design must lose the engagement outright " +
			"(%.3f %% out, %.3f m)") % [float(w03["out"]), float(w03["miss"])])
	# ⚠⚠ AND ITS BAND IS EMPTY, so `rms r` is UNDEFINED there rather than quiet — slice 33's gate-2
	# catch, live again on this file's own worst arm.
	if not (int(w03["band"]) == 0 and is_nan(float(w03["rms"]))):
		return _fail(("PHASE ENVELOPE: the badly broken arm must never enter r in [500, 3000] at all " +
			"(%d band frames) so its rms r is NaN (%.5f) rather than a beautifully quiet number " +
			"computed from ZERO samples") % [int(w03["band"]), float(w03["rms"])])
	# CURE: aim R̂ at slice 30's rule and the same window flies.
	herr = _held(w33, g33, "w33 (slice 30's aim point through the shipped window)")
	if herr != "":
		return _fail(herr)
	# THE DOMAIN FLOOR — the price at the slider's own bottom, with a LIVE band (the floor's reason).
	if not (float(flr["out"]) > 50.0 and float(flr["miss"]) > 500.0 and int(flr["band"]) > 0):
		return _fail(("PHASE ENVELOPE: the window slider's FLOOR must be deep in the broken regime " +
			"(%.3f %% out, %.3f m) AND still produce a live band (%d frames) — the second half is the " +
			"measured reason the domain stops at %.1f deg") %
			[float(flr["out"]), float(flr["miss"]), int(flr["band"]), WIN_FLOOR])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE TWO-RUN — ⚠⚠ THE PREDICTOR AND THE PREDICTED MUST NOT COME FROM THE SAME RUN, AND THE
	# THIRD QUANTITY FAILS QUIETLY.
	print("S34V_TWORUN   at a FIXED R̂ %+.2f, the windowed arm's rms r FALLS %.2fx (%.5f -> %.5f) while its miss OPENS %.0fx (%.3f -> %.3f m), its own tracking error reads %.3f deg (the post-lock-loss runaway, against the ring's actual %.3f) — and ⚠ its HEAD TRAVEL FREEZES at %.3f deg, the QUIET arms' number, against the ring's actual %.3f: a plausible, in-range, TOO SMALL reading" %
		  [float(w16["rhat"]), float(g16["rms"]) / maxf(float(w16["rms"]), 1.0e-9), float(g16["rms"]),
		   float(w16["rms"]), float(w16["miss"]) / maxf(float(g16["miss"]), 1.0e-9), float(g16["miss"]),
		   float(w16["miss"]), float(w16["off"]), float(g16["off"]),
		   float(w16["head"]), float(g16["head"])])
	if not (int(g16["band"]) > 0 and int(w16["band"]) > 0):
		return _fail("PHASE TWO-RUN: both arms must have band frames before any band number is quoted (%d, %d)" % [int(g16["band"]), int(w16["band"])])
	if not (float(w16["rms"]) < float(g16["rms"]) and float(w16["miss"]) > float(g16["miss"])):
		return _fail(("PHASE TWO-RUN: the metric inversion must be MEASURED, not assumed — a broken " +
			"window FREEZES the index (no error signal, no slew: the head HOLDS), a frozen index makes " +
			"a CONSTANT bend, and a constant bend is quiet at every R̂. So rms r must FALL (%.5f -> " +
			"%.5f) while the miss OPENS (%.3f -> %.3f m)") %
			[float(g16["rms"]), float(w16["rms"]), float(g16["miss"]), float(w16["miss"])])
	if not (float(w16["off"]) > RUNAWAY_OFF_MIN and float(g16["off"]) < MODEL_VALID_DEG):
		return _fail(("PHASE TWO-RUN: and the same inversion in the tracking error — the windowed arm's " +
			"own reads the ~90 deg post-lock-loss runaway (%.3f > %.0f) and no read at all of a head " +
			"whose actual error was %.3f deg") %
			[float(w16["off"]), RUNAWAY_OFF_MIN, float(g16["off"])])
	# ⚠⚠ THE THIRD QUANTITY, AND IT IS THE DANGEROUS ONE — it does not run away, it FREEZES.
	if not (float(w16["head"]) < float(g16["head"]) - 2.0
			and absf(float(w16["head"]) - float(g18["head"])) < 0.01):
		return _fail(("⚠⚠ PHASE TWO-RUN: `head_angle_deg` must FREEZE on a windowed arm at the value it " +
			"held when the track broke (%.3f deg) — the QUIET arms' number (%.3f) — against the ring's " +
			"actual %.3f. It does NOT run away like the tracking error: it reads a plausible number, in " +
			"range, on the LOW side. A file that read the excursion off a windowed run would report " +
			"that the ring costs nothing, which is why every predictor here comes off a FREE arm") %
			[float(w16["head"]), float(g18["head"]), float(g16["head"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE ISOLATION — ⚠ NOT SLICE 32's AND NOT SLICE 33's. Both of those are about a windowed arm;
	# this slice's discriminating pair is the TWO WIRES at the SAME R̂, and there the aero ceiling
	# separates cleanly: the strapdown twin's ring drives the demand into slice 19's ceiling for half
	# its band, while the gimballed wire never touches it. ⇒ the difference is the INDEX and not
	# authority — the gimbal arm was not flying a better-behaved airframe, it simply was not shaking.
	print("S34V_ISOLATE  at the SAME R̂ %+.2f the STRAPDOWN twin saturates the slice-19 aero ceiling %.2f %% of its band while the GIMBALLED wire touches it %.2f %% — the difference is the INDEX, not authority. And defl_sat fired on %d / %d band frames" %
		  [RHAT_SHOW, float(s18["aero"]), float(g18["aero"]), int(s18["defl"]), int(g18["defl"])])
	if not (float(s18["aero"]) > 20.0 and float(g18["aero"]) < 1.0):
		return _fail(("PHASE ISOLATION: the ringing twin must saturate its ceiling (%.2f %%, must exceed " +
			"20) while the quiet gimbal arm does not (%.2f %%, must be under 1). If the gimbal arm were " +
			"also saturating, the quiet rms r would be a ceiling artifact rather than an absent ring") %
			[float(s18["aero"]), float(g18["aero"])])
	# ⚠ WHAT IS INVARIANT is that the FIN never pegs, on EITHER wire — so the missile always had the
	# authority and slice 15's cap is innocent of everything here (slice 33's tooth, kept because it
	# is the one that still holds; its `aero_sat` reasoning is the part that does not transfer).
	for k in ["g18", "g16", "g03", "open", "w16", "s18", "s24", "s27", "s33", "gfloor", "s36"]:
		if not (int(_res[k]["defl"]) == 0):
			return _fail(("PHASE ISOLATION, arm %s: `defl_sat` fired on %d band frames — the fin must " +
				"never peg on either wire. If this fires, the miss has acquired an ACTUATOR component " +
				"(slice 15's cap) and neither the index nor the window is cleanly the cause any more") %
				[k, int(_res[k]["defl"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE DOMAIN — ⭐ THE R̂ SLIDER'S FLOOR, ON BOTH WIRES (the gate-3 post-review catch).
	var gf: Dictionary = _res["gfloor"]
	var sf: Dictionary = _res["s36"]
	# ⚠ THE REVERSAL IS QUOTED IN `rms r` AND NOT IN THE MISS, AND THAT IS A SAMPLING FACT RATHER THAN
	# a choice of emphasis ([[ewsim-missile-verifier-sampling]]: a MISS samples faithfully, a HIT
	# samples COARSELY). Per tick the miss grows monotonically past the aim point (0.161 -> 0.433 m,
	# on to 5.669 at R̂ = -0.50, measured at gate 3's post-review); on this ~11 m emit grid both arms
	# are HITS a couple of metres apart and the ordering is not resolvable. `rms r` is a band mean and
	# is resolved, so it is what this phase asserts.
	print("S34V_DOMAIN   PAST slice 30's aim point at R̂ %+.2f, on BOTH wires: the gimbal arm holds through the shipped %.0f deg window (%.3f %% out, %.3f m, tracking error %.3f deg, head travel %.3f deg of a %.0f deg stop) and the twin holds too (%.3f m) — and the overshoot is a DE-TUNE THAT REVERSES rather than a plateau: rms r turns back UP %.5f -> %.5f gimballed and %.5f -> %.5f strapdown. It never RINGS anywhere down here. ⚠ The miss reversal is per-tick only (0.161 -> 0.433 m); on this frame grid both arms are HITS and a HIT samples coarsely, so it is not asserted here" %
		  [RHAT_36, WIN_SHIP, float(gf["out"]), float(gf["miss"]), float(gf["off"]), float(gf["head"]),
		   float(gf["stop"]), float(sf["miss"]),
		   float(w33["rms"]), float(gf["rms"]), float(s33["rms"]), float(sf["rms"])])
	for k in ["gfloor", "s36"]:
		var a: Dictionary = _res[k]
		if not (float(a["out"]) == 0.0 and float(a["miss"]) < HIT_MAX):
			return _fail(("PHASE DOMAIN, arm %s: the R̂ slider's FLOOR must be a place a student can " +
				"actually go (%.3f %% out, %.3f m). Past slice 30's aim point the engagement residual " +
				"goes POSITIVE and DE-TUNES rather than rings — but a de-tuned loop LAGS, and lag grows " +
				"the LEAD, which is what the head's travel must cover and what sets the tracking error") %
				[k, float(a["out"]), float(a["miss"])])
		if not (int(a["band"]) > 0 and float(a["rms"]) < RING):
			return _fail(("PHASE DOMAIN, arm %s: it must be QUIET (rms r %.5f over %d band frames) — " +
				"slice 30's constraint is ONE-SIDED, so overshooting the aim point must never ring") %
				[k, float(a["rms"]), int(a["band"])])
	if not (float(gf["head"]) < float(gf["stop"]) and float(gf["off"]) < WIN_SHIP):
		return _fail(("PHASE DOMAIN: at the floor NEITHER limit may bind — head travel %.3f deg against " +
			"a %.3f deg stop and a tracking error of %.3f deg against the shipped %.0f deg window. If " +
			"either crossed, the student's own overshoot-the-aim-point gesture would break the arm and " +
			"the domain's stated reason would be wrong") %
			[float(gf["head"]), float(gf["stop"]), float(gf["off"]), WIN_SHIP])
	# ⭐⭐ AND THE OVERSHOOT REVERSES — which CORRECTS the scenario comment this catch was found by
	# (it said the requirement "STOPS FALLING"; it turns back UP, which is sharper than a plateau).
	if not (float(gf["rms"]) > float(w33["rms"]) and float(sf["rms"]) > float(s33["rms"])):
		return _fail(("PHASE DOMAIN: past the aim point the ring must turn back UP on BOTH wires " +
			"(gimbal %.5f -> %.5f, strapdown %.5f -> %.5f) — a DE-TUNE, which is what makes the floor " +
			"worth reaching") % [float(w33["rms"]), float(gf["rms"]), float(s33["rms"]), float(sf["rms"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE REPLAY — class 4a, held seed, bit-identical. The head is a DETERMINISTIC SERVO on an
	# existing measurement: no new draw, and the window gates the VALUE and never the DRAW.
	var d := _pos_max_diff(op["pos"], _res["replay"]["pos"])
	print("S34V_REPLAY   the same wire twice at the held seed: max|Δpos| = %.6f m over %d frames" %
		  [d, mini((op["pos"] as Array).size(), (_res["replay"]["pos"] as Array).size())])
	if not (d <= EXACT):
		return _fail(("REPLAY: two runs of the shipped wire at the same seed must be BIT-IDENTICAL " +
			"(max|Δpos| = %.9f m). Class 4a — the head adds NO draw (a deterministic servo on an " +
			"existing measurement) and an out-of-window tick still draws `n_az`/`n_el` and DISCARDS " +
			"them, slice 25's lockstep") % d)

	return _pass()

# ⚠⚠ `held` IS NOT BIT-IDENTITY, and slice 33's gate 2 paid five failing asserts to learn it: every
# held arm leaves its window in the last metres (r = 0.2-9 m, at look angles of tens of degrees)
# because the LOS unit vector swings through a huge angle as r -> 0, and those few coasting ticks
# perturb the CPA. That is the very thing the r > 200 m gate exists to exclude, so THE EXACT CLAIM
# LIVES ON THE GATED QUANTITIES and the miss carries a tolerance with a measured reason.
# ⚠ `tag` is not decoration — this is called from four sites.
# ⚠⚠ AND `miss_tol` IS AN ARGUMENT BECAUSE GATE 3 MEASURED THAT THE TOLERANCE IS A FUNCTION OF THE
# WINDOW — a finding, not a fudge. Everything a held arm pays it pays in the ENDGAME, and how early
# the endgame swing reaches the window depends on how wide the window is: the shipped 4 deg one is
# reached ~1e-10 m before CPA (indistinguishable from the free arm) while the bracket's 2.05 deg one
# is reached far enough out to move the CPA by 0.020 m. Slice 33 could use one flat 1e-6 because its
# windows were 21-40 deg; a slice whose whole subject is a DETECTOR window a couple of degrees wide
# cannot. Each caller passes the tolerance its own window earns, and the gated quantities above stay
# EXACT in every case — which is where the claim actually lives.
func _held(win: Dictionary, free: Dictionary, tag: String, miss_tol := 1.0e-6) -> String:
	if not (float(win["out"]) == 0.0):
		return ("HELD FAILED for %s: the window must never be reached on the approach (%.3f %% out)") % [tag, float(win["out"])]
	if not (absf(float(win["off"]) - float(free["off"])) < 1.0e-6):
		return ("HELD FAILED for %s: the tracking error must match the free arm's (%.6f vs %.6f deg). " +
				"If these differ, the window PERTURBED the trajectory it was supposed to merely " +
				"contain, and the error is no longer a property of the head alone") % [tag, float(win["off"]), float(free["off"])]
	if not (absf(float(win["head"]) - float(free["head"])) < 1.0e-6):
		return ("HELD FAILED for %s: the head TRAVEL must match the free arm's (%.6f vs %.6f deg)") % [tag, float(win["head"]), float(free["head"])]
	if not (absf(float(win["miss"]) - float(free["miss"])) < miss_tol):
		return ("HELD FAILED for %s: the miss must match the free arm's to within the endgame " +
				"perturbation (%.9f vs %.9f m, tolerance %.6f)") % [tag, float(win["miss"]),
				float(free["miss"]), miss_tol]
	# ⭐ AND THE SIGNED BUDGET MUST HAVE STAYED NON-NEGATIVE ON THE APPROACH — slice 18's
	# `terrain_clearance_m` / slice 33's `seeker_fov_margin_deg` shape: THE SIGN IS THE VERDICT.
	if not (float(win["marg"]) >= 0.0):
		return ("HELD FAILED for %s: the shipped budget `gimbal_fov_margin_deg` must never go negative " +
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
	_max_head = 0.0
	_max_off = 0.0
	_max_body = 0.0
	_min_marg = 1.0e30
	_n_band = 0
	_n_aero = 0
	_n_defl = 0
	_sum_r2 = 0.0
	_t_break = -1.0
	_r_break = -1.0
	_win_seen = 0.0
	_rhat_seen = 0.0
	_stop_seen = 0.0
	_worst = 0.0
	_n_idx_bad = 0
	_n_nose_idx = 0
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
		if tel.has(MID + ".gimbal_fov_deg"):
			_win_seen = float(tel[MID + ".gimbal_fov_deg"])
		if tel.has(MID + ".gimbal_stop_deg"):
			_stop_seen = float(tel[MID + ".gimbal_stop_deg"])
		if tel.has(MID + ".radome_slope_est"):
			_rhat_seen = float(tel[MID + ".radome_slope_est"])
		if tel.has(MID + ".radome_slope_worst"):
			_worst = float(tel[MID + ".radome_slope_worst"])
		# ⭐⭐ THE INDEX, PER FRAME. Under a head the seam sets `look_az, look_el = head_az, head_el`
		# BEFORE the bend is taken, so slice 26's `look_angle` — the angle the glass was ACTUALLY
		# evaluated at — must BE `head_angle_deg` and must NEVER be `look_body_deg` (the nose's angle,
		# which is what a strapdown seeker indexes and what the TWIN wire uses). Counted here rather
		# than compared once at the end, so a single frame that indexed off the airframe would fail.
		if tel.has(MID + ".head_angle_deg"):
			if absf(float(tel[MID + ".look_angle"]) - float(tel[MID + ".head_angle_deg"])) > 0.0:
				_n_idx_bad += 1
			if float(tel[MID + ".look_angle"]) == float(tel[MID + ".look_body_deg"]):
				_n_nose_idx += 1
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				# WINDOW 1 — the angle / budget / out-of-window window, RANGE-GATED at r > 200 m.
				# ⚠ Ungated, the endgame LOS swing makes a QUIET arm read a few tenths of a percent
				# out and its tracking error read tens of degrees (slice 33's five failing asserts).
				if r > 200.0:
					_n_gate += 1
					_max_head = maxf(_max_head, float(tel.get(MID + ".head_angle_deg", 0.0)))
					_max_off = maxf(_max_off, float(tel.get(MID + ".head_off_deg", 0.0)))
					# ⚠ ON THE TWIN THIS IS THE ONLY LOOK ANGLE THERE IS — a strapdown wire ships no
					# `look_body_deg` (that key exists to sit BESIDE the head's index), so it falls
					# back to slice 26's `look_angle`, which there IS the nose's angle. The two keys
					# mean the same thing on the twin and different things on the head wire, which is
					# exactly the distinction this slice is about.
					_max_body = maxf(_max_body, float(tel.get(MID + ".look_body_deg",
											 float(tel.get(MID + ".look_angle", 0.0)))))
					if tel.has(MID + ".gimbal_fov_margin_deg"):
						_min_marg = minf(_min_marg, float(tel[MID + ".gimbal_fov_margin_deg"]))
					# ⚠ `gimbal_valid`, NEVER `seeker_valid`: they are different booleans about
					# different windows and a gimbal wire ships only the first (the loader refuses the
					# combination). A default of 1.0 makes the twin correctly read "never out".
					if float(tel.get(MID + ".gimbal_valid", 1.0)) < 0.5:
						_n_out += 1
						if _t_break < 0.0:
							_t_break = float(f.get("t", -1.0))
							_r_break = r
				# WINDOW 2 — the ISOLATION band, 28/29/30/31/33's [500, 3000] m, inherited with its
				# reasons. ⚠ THE CHANNEL IS YAW: the lead is in AZIMUTH on this crossing geometry, so
				# the yaw channel sits on the steep part of the slope curve while pitch sits near the
				# boresight slope (slice 28's finding — a `q` metric meters the quiet channel of a
				# shaking missile).
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

# ⚠ BOTH WIRES ARE CHECKED, AND THEY ARE CHECKED DIFFERENTLY — the head wire must raise the NEW
# marker and must NOT raise slice 32's, the twin must raise NEITHER. That asymmetry is the whole
# reason `gimbal_view` exists (see below), so a shared "close enough" check would hide it.
func _check_handshake(f: Dictionary, wire: String) -> String:
	var want := "slice34_gimbal" if wire == "gimbal" else "slice34_strapdown"
	if str(f.get("name", "")) != want:
		return "expected the '%s' scenario, got '%s'" % [want, str(f.get("name", ""))]
	if not bool(f.get("airframe_view", false)):
		return "a slice-34 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-34 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "both slice-34 wires carry GLASS, so both must ship radome_view=true"
	# ⭐⭐ THE MARKER, AND THE REASON IT HAD TO EXIST. The loader REFUSES `seeker_fov_deg` beside a head
	# (a gimballed seeker has no body-fixed window — its body-fixed limit is the mechanical STOP), so
	# a gimbal wire raises `radome_view` and NOT `seeker_fov_view`: BOTH of the client's FOV branches
	# fail their conjunction and slice 26/27/28's RADOME cascade takes it. ⚠ That failure is the
	# stale-readout class's WORST form, because nothing in it is stale — every key that cascade reads
	# is LIVE on this wire — so it would print a fluent ring/quiet verdict about the GLASS on a wire
	# whose subject is the HEAD, and not one test would have failed.
	if wire == "gimbal":
		if not bool(f.get("gimbal_view", false)):
			return "a slice-34 gimbal handshake must ship gimbal_view=true — without it the client's dispatch falls past both FOV branches into the RADOME cascade, which reads only LIVE keys here and would therefore be confidently wrong rather than visibly broken"
		if f.has("seeker_fov_view"):
			return "a gimbal wire must NOT raise seeker_fov_view — the loader refuses `seeker_fov_deg` beside a head, and the client's composition branch keys off exactly that absence"
	else:
		if f.has("gimbal_view"):
			return "the STRAPDOWN twin must NOT raise gimbal_view — it has no head, and the two wires have to stay distinguishable from the CORE side because that is what the client dispatches on"
		if f.has("seeker_fov_view"):
			return "the STRAPDOWN twin must NOT raise seeker_fov_view either — it ships no body window, so its rms r is a clean stability read (slice 33's own two-run rule: a windowed arm's is not)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-34 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS a look angle at all, and the loader refuses `gimbal_tau_s` without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-34 scenario must HOLD :airframe at six_dof — the head AND the attitude it is measured against are gated on that LIVE rung (never on :att_q, which is minted once and never deleted), so they freeze and resume together. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-34 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-34 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-34 scenario must HOLD :seeker at :filtered — the alpha-beta tracker is what COASTS when the head stops supplying measurements, and the coast is half the broken arm's mechanism. Got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-34 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the aero ceiling 93.2% of its approach, a THIRD mechanism)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-34 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	if not keys.has("radome_slope_est"):
		return "both slice-34 wires must expose the 'radome_slope_est' slider — the SHARED axis, and the whole experiment is walking it on BOTH and reading where the ring dies"
	if str(keys["radome_slope_est"]) != MID:
		return "the R̂ knob must target the interceptor '%s'" % MID
	if wire == "gimbal":
		# ⭐⭐ TWO KNOBS — the two halves of ONE comparison, `window` vs `tracking error(R̂)`, which is
		# slice 33's pair re-expressed in the currency a gimbal has. Convention 9 is satisfied BY
		# MEASUREMENT (the slice-27 DIAGONAL precedent). ⚠ STATED AS TRACKING, NEVER AS
		# `window = ceil(error(R̂))` — gate 2 measured that rule sufficient but NOT tight.
		if not keys.has("gimbal_fov_deg"):
			return "the slice-34 gimbal handshake must expose the 'gimbal_fov_deg' slider — the DETECTOR window, the slice's one genuinely new axis, and where the margin the self-referential index buys is paid for"
		if str(keys["gimbal_fov_deg"]) != MID:
			return "the detector-window knob must target the interceptor '%s'" % MID
		if keys.size() != 2:
			return "the slice-34 gimbal wire must expose EXACTLY TWO knobs (got %d) — the detector budget and the design that spends it" % keys.size()
	else:
		if keys.has("gimbal_fov_deg"):
			return "the STRAPDOWN twin must NOT expose 'gimbal_fov_deg' — it has no head and therefore no detector window; the loader would refuse the key as DEAD"
		if keys.size() != 1:
			return "the slice-34 strapdown wire must expose EXACTLY ONE knob (got %d) — convention 9 outright, without the twin's diagonal argument" % keys.size()
	# The DISQUALIFICATIONS live IN the gate, not only in the plan ("a doc claim about a gate must
	# live IN the gate"). ⚠ `gimbal_tau_s` heads this list and its exclusion is MEASURED, not argued.
	if keys.has("gimbal_tau_s"):
		return "slice 34 must NOT expose a 'gimbal_tau_s' knob — gate 2 measured the amplitude sagging monotonically with τ on EVERY arm, and AT THE LINE that same sag crosses the verdict (the bracket walks from (-0.18, -0.17] at τ <= 0.02 to (-0.16, -0.12] at τ = 0.20). It is a CONFOUNDED lever, which is a STRONGER reason to keep it authored than a dead one: a student dragging it moves the verdict without moving the mechanism"
	if keys.has("gimbal_stop_deg"):
		return "slice 34 must NOT expose a 'gimbal_stop_deg' knob — the stop is a RESTATEMENT of slice 33's excursion, and binding it COUPLES the two budgets (a clamped head cannot reach the LOS, so its deficit is charged to the DETECTOR allowance). That coupling is a second mechanism and lives in test_missile.jl"
	if keys.has("cross_speed_mps"):
		return "slice 34 must NOT expose 'cross_speed_mps' — it is slice 32's OWN axis (it moves the LEAD, and hence the head's travel requirement), a THIRD mechanism beside the index and the window"
	if keys.has("af_alpha_max") or keys.has("alpha_max"):
		return "slice 34 must NOT expose an 'alpha_max' knob — slice 26's instrument for the ring's AMPLITUDE and a confounded lever"
	if keys.has("radome_slope") or keys.has("radome_ripple") or keys.has("radome_ripple_k"):
		return "slice 34 must NOT expose the GLASS itself — a radome's slope curve is HARDWARE, and the arc's point since slice 27 is that what an engineer can change is what they BELIEVE about it"
	if keys.has("n_pn"):
		return "slice 34 must NOT expose an 'n_pn' knob — it moves the parasitic boundary (N·|R − R̂|/ρ) AND the guidance loop"
	if keys.has("rho"):
		return "slice 34 must NOT expose a 'rho' knob — it moves the parasitic boundary and the aero ceiling at once"
	if keys.has("sigma_seek"):
		return "slice 34 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it"
	if keys.has("elevation_deg"):
		return "slice 34 must NOT expose 'elevation_deg' — the slice-19 DEAD-knob class (position and attitude are built once at LOAD and `reset` re-reads the YAML), and on this wire it is also what sets a HANDED-OVER head's tick-1 pointing"
	if keys.has("speed"):
		return "slice 34 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-knob finding)"
	if keys.has("seeker_fov_deg"):
		return "slice 34 must NOT expose 'seeker_fov_deg' on either wire — the head wire is refused it by the loader (a gimballed seeker has no body-fixed window) and the twin ships no window at all, so its rms r stays a clean stability read"
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
	var g33: Dictionary = _res["g33"]
	var g18: Dictionary = _res["g18"]
	var g16: Dictionary = _res["g16"]
	var g03: Dictionary = _res["g03"]
	var op: Dictionary = _res["open"]
	var w16: Dictionary = _res["w16"]
	var w03: Dictionary = _res["w03"]
	var blo: Dictionary = _res["brlo"]
	var s18: Dictionary = _res["s18"]
	var s24: Dictionary = _res["s24"]
	var s27: Dictionary = _res["s27"]
	print(("S34V OK: slices 26-33 built the parasitic loop on ONE geometric fact — the radome bends " +
		"the ray by an amount set by the LOOK ANGLE, and the look angle is the LOS measured off the " +
		"missile's OWN NOSE, which it can only move by ROTATING. That is why slice 26 is a BODY-RATE " +
		"instability. ⭐⭐ A GIMBALLED SEEKER BREAKS THAT IDENTITY: the ray passes through the part of " +
		"the dome the HEAD is aimed at, and THE HEAD IS AIMED BY THE VERY MEASUREMENT THE DOME JUST " +
		"BENT — the index of the glass becomes a FIXED POINT of the glass. Measured on two wires that " +
		"differ in nothing else: at R̂ %+.2f on glass R0 = -0.03 / A = -0.15, seed 32, the STRAPDOWN " +
		"twin rings at rms r %.5f while the GIMBALLED wire sits at %.5f — %.1fx — and BOTH HIT (%.3f " +
		"vs %.3f m), the arc's standing fact since slice 26. ⭐ THE ONSET WALKS TWO RUNGS OF THE SAME " +
		"LADDER, FROM THE SAME SLIDER: strapdown quiet at %+.2f (%.5f) and ringing at %+.2f (%.5f) => " +
		"(-0.27, -0.24]; gimballed quiet at %+.2f and ringing at %+.2f (%.5f) => (-0.18, -0.16]. " +
		"Quoted BRACKET TO BRACKET and never as one number — the gap they admit spans 0.06 to 0.11. " +
		"⭐ AND head travel STEPS AT THE SAME PLACE, a SECOND tell from a DIFFERENT quantity: flat at " +
		"%.3f deg through every quiet arm, %.3f at the first ringing one, %.3f at the loudest. " +
		"⚠ AND IT IS NOT FREE, IN THE ONE CURRENCY A GIMBAL HAS: the margin is bought by the head's " +
		"pointing DECOUPLING from the true LOS, and that decoupling IS the tracking error the " +
		"detector must cover. Slice 33's single number splits in TWO — a STOP (the head's TRAVEL, " +
		"which reproduces slice 33's excursion: a RESTATEMENT) and a DETECTOR WINDOW (about the head " +
		"axis: NEW). ⭐⭐ SLICE 32's PREDICATE RETURNS IN THAT CURRENCY, `held <=> tracking error < " +
		"detector window`: against a MEASURED %.4f deg, a window %.1f deg short BREAKS (%.3f %% out, " +
		"%.1f m) and %.1f deg over HOLDS and flies the free arm's own error to 1e-6. The two sides " +
		"come from DIFFERENT RUNS, which is what makes it a measurement rather than a restatement. " +
		"⭐ THE RING IS SPENT IN DETECTOR WINDOW, %.1fx (%.4f -> %.4f deg), so through the shipped " +
		"%.0f deg window the SAME slider that quiets the loop also keeps the track: R̂ %+.2f holds at " +
		"%.3f m while %+.2f loses lock at t = %.3f s / r = %.1f m and misses by %.1f m. ⚠⚠ THE " +
		"PREDICTOR AND THE PREDICTED NEVER COME FROM THE SAME RUN, and the list is THREE quantities: " +
		"on a windowed arm rms r FALLS %.2fx while the miss OPENS %.0fx, the tracking error RUNS AWAY " +
		"to %.3f deg — and ⚠ head travel FREEZES at %.3f deg, the QUIET arms' number, against the " +
		"ring's actual %.3f. It does not run away; it reads a plausible, in-range, TOO SMALL number, " +
		"which is the quiet failure this file is structured to avoid. ⚠ THE ISOLATION IS NEITHER 32's " +
		"NOR 33's: at the same R̂ the twin saturates the slice-19 ceiling %.2f %% of its band while " +
		"the gimbal wire touches it %.2f %% — the difference is the INDEX, not authority — and what " +
		"is invariant is defl_sat = 0 on every arm of both wires. ⚠ The badly broken arm's band is " +
		"EMPTY (%d frames), so its rms r is UNDEFINED rather than quiet. ⭐ AND THE R̂ SLIDER'S FLOOR " +
		"IS FLOWN ON BOTH WIRES (slice 26's post-commit rule: a declared domain's ENDPOINTS ARE " +
		"MEASURED): PAST the aim point it holds with neither limit binding (%.3f m, %.3f %% out, " +
		"tracking error %.3f deg of %.0f, head travel %.3f deg of %.0f) and the overshoot is a " +
		"DE-TUNE THAT REVERSES rather than a plateau — rms r turns back UP %.5f -> %.5f. ⚠ NO new " +
		"rung, cap, instability or draw: the head is a DETERMINISTIC SERVO on an existing " +
		"measurement. Class 4a, the TENTH consecutive RNG-live slice, replay bit-identical, button " +
		"DROPPED (10th).")
		% [RHAT_SHOW, float(s18["rms"]), float(g18["rms"]),
		   float(s18["rms"]) / maxf(float(g18["rms"]), 1.0e-9), float(s18["miss"]), float(g18["miss"]),
		   RHAT_27, float(s27["rms"]), RHAT_24, float(s24["rms"]),
		   RHAT_SHOW, RHAT_16, float(g16["rms"]),
		   float(g18["head"]), float(g16["head"]), float(g03["head"]),
		   float(g18["off"]), BRACKET, float(blo["out"]), float(blo["miss"]), BRACKET,
		   float(g03["off"]) / maxf(float(g33["off"]), 1.0e-9), float(g33["off"]), float(g03["off"]),
		   WIN_SHIP, RHAT_SHOW, float(op["miss"]), RHAT_03, float(w03["tbrk"]), float(w03["rbrk"]),
		   float(w03["miss"]),
		   float(g16["rms"]) / maxf(float(w16["rms"]), 1.0e-9),
		   float(w16["miss"]) / maxf(float(g16["miss"]), 1.0e-9), float(w16["off"]),
		   float(w16["head"]), float(g16["head"]),
		   float(s18["aero"]), float(g18["aero"]), int(w03["band"]),
		   float(_res["gfloor"]["miss"]), float(_res["gfloor"]["out"]),
		   float(_res["gfloor"]["off"]), WIN_SHIP,
		   float(_res["gfloor"]["head"]), float(_res["gfloor"]["stop"]),
		   float(_res["w33"]["rms"]), float(_res["gfloor"]["rms"])])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S34V FAIL: " + msg)
	print("S34V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
