extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-35 gate-3 verifier — A RATE-LIMITED HEAD: THE BANDWIDTH THAT HOLDS THE TRACK IS THE
# BANDWIDTH THAT FEEDS THE LOOP. Drives the REAL Julia server through SimClient.gd (the same protocol
# code Sandbox.tscn renders off).
#
#   pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice35_rate.yaml
#   godot --headless --path clients/godot --script res://net/slice35_verify.gd     (exit 0 = pass)
#
# ⚠ ONE WIRE, unlike slice 34's PAIR, and the reason is a measurement rather than a preference: the
# whole claim lives INSIDE one slider's declared domain (60 -> 8 deg/s), so the lesson is a DRAG and
# not a comparison between two files. Slice 34 needed a twin only because no in-domain value removes
# a head.
#
# THE LESSON. Slice 34's head was INFINITELY FAST: `head_slew` moved it a full first-order step every
# tick with no bound on how far. A real gimbal has a servo with a maximum slew rate, and the moment it
# does the head's motion stops being free — it becomes a RESOURCE, spent against a demand. AND THE
# DEMAND IS SET BY THE PARASITIC LOOP: on a settled collision course the head barely moves and asks
# for 0.600 deg/s in the engagement band; let the loop ring and the same head must chase its own
# oscillation, 53.6x more, ACROSS SLICE 34's OWN ONSET BRACKET.
#
# ⭐⭐ AND IT IS THE ARC's FIRST TWO-SIDED KNOB. Slices 32, 33 and 34 all end "widen it — it is free".
# That cure does NOT transfer: servo bandwidth is not a window, it is what the loop FEEDS ON. Slow the
# head and the ring is ATTENUATED while the tracking error it must cover GROWS — one knob, two bounds,
# pulling in opposite directions, and no free direction anywhere.
#
# ⚠⚠ THE BREAK IS NOT THIS FILE's CLAIM AND IT DOES NOT ASSERT ONE (gate 0 §0.3, the advisor's own
# ship/no-ship gate, which came back NEGATIVE): a WIDER window rescues a rate-limited arm, so a
# rate-limited head that loses its track loses it by SLICE 34's mechanism. The window is therefore
# AUTHORED WIDE on this wire and PHASE WINDOW asserts it never bites — which is not hygiene but the
# load-bearing condition that makes every other number here attributable to the SERVO.
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`), and the constants below are sized off FRAME
# columns, never off the per-tick suite's ([[ewsim-missile-verifier-sampling]] — the error is
# ASYMMETRIC: a MISS samples faithfully, a HIT samples COARSELY). The metrics here are RMS and
# PERCENTILES over a band, which slice 26 measured to be frame-robust; the miss is corroboration only
# and is never the metric (every arm in the domain HITS — the arc's standing fact since slice 26).
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 2400.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — both sliders live here

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16, asserted core-side). The server
# emits every 16th tick, so a STEPS that is not a multiple makes the last frame land BELOW `STEPS*dt`
# and `_drain_scan` waits forever, SILENTLY, with no output at all (slice 31 lost an hour to exactly
# this and it reads like a slow wire). 12800 = 16 * 800.
# ⚠ SIZED OFF THE SLOWEST ARM, MEASURED: ToF spans 10.90 s (the default) to 11.33 s (the R̂ floor at
# the servo floor). 12.8 s leaves ~1.5 s of headroom, and EVERY arm asserts it REACHED CPA rather
# than trusting the sizing.
const STEPS := 12800

# THE SERVO SLIDER. ⚠ THE CEILING IS NOT A BIT-IDENTITY CONTROL and this file never treats it as one
# (gate 2 pinned it as a `>` in the suite): at 60 deg/s the trajectory MOVES, because the cap clips
# the tick-2 HANDOVER transient — an identical 72.542 deg/s on every arm. The free read is the ABSENT
# key, which a live wire cannot reach. What 60 IS, is the top of the useful range: ~inert ON THE
# METRIC (rms r 0.88469 against the unlimited 0.88465).
const RATE_HI := 60.0
const RATE_DEF := 40.0            # the shipped default — INTERIOR, so the knob drags BOTH ways
const RATE_25 := 25.0
const RATE_15 := 15.0
# THE FLOOR, AND ITS JUSTIFICATION IS THIS SLICE's OWN DISCRIMINATOR: 8 deg/s is exactly where
# `sat_band` is 0.00 % on slice 34's shipped design and 97.14 % on this wire's default. One servo,
# two designs. Below it the head stops being a servo at all (100 % saturation — an open-loop RAMP,
# quiet for slice 34's FROZEN-HEAD reason, and its ring ratio is UNQUOTABLE).
const RATE_LO := 8.0

const RHAT_03 := -0.03            # slice 28's BORESIGHT characterization — the DEFAULT, and the disease
const RHAT_16 := -0.16            # the first RINGING gimbal arm (slice 34's onset bracket, upper rung)
const RHAT_18 := -0.18            # slice 34's shipped design — the QUIET side of the 0-vs-97 split
const RHAT_33 := -0.33            # slice 30's aim point (R0 + 2A) — where the servo goes FREE
const RHAT_36 := -0.36            # the R̂ slider's FLOOR, PAST the aim point

const RING := 0.30                # the arc's ring/quiet line, the same one slices 30/33/34 read against
# ⚠ A SANITY BOUND, NOT THE METRIC. Frame-sampled misses across the 184-cell domain grid run to
# 16.6 m; the per-tick figures are 0.1-14 m. Every arm HITS — that is the arc's standing fact since
# slice 26 and the reason the verdict is rms r, `sat_band` and a tracking error, never a miss.
const HIT_MAX := 40.0
const WIN_AUTH := 25.0            # the AUTHORED detector window (not a knob here — see the handshake)
const MODEL_VALID_DEG := 30.0     # the small-angle bend budget 28/29/30/31 each declared
# ⭐ THE WORST WHOLE-APPROACH REQUIREMENT ANYWHERE IN THE TWO-SLIDER DOMAIN. ⚠ A **MEASURED**
# CONSTANT, not a derived one, and it is labelled as such wherever it appears (here and in
# `test_missile.jl`): it comes from a FINE grid — R̂ on a 0.015 step x rate in {8, 10, 12, 15, 20, 25,
# 40, 60} = 184 cells — flown because the requirement is NON-MONOTONE IN BOTH SLIDERS, so a corner
# sweep is not evidence about the interior (the advisor's blocking catch at this gate; the grid and
# its table are in `docs/plans/slice35.md` §3). It lands at the CORNER (R̂ = -0.03, rate = 8), which
# is the arm this file flies as `r08` — and PHASE WINDOW derives "the corner IS the maximum" from
# this run's own arms BEFORE cross-checking it against this number.
const REQ_WORST := 19.279
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
var _off_band := 0.0              # …the tracking error IN BAND: the LOOP's own requirement
var _n_sat := 0                   # …frames where the SERVO's rate limit BOUND (the core's own flag)
var _dems: Array = []             # …the PRE-LIMIT demanded head rate, deg/s (percentiles, never a peak)
var _n_aero := 0
var _n_defl := 0
var _sum_r2 := 0.0                # for rms r — the RING (yaw: the lead is in AZIMUTH here)
var _n_flag_bad := 0              # frames where the shipped FLAG disagreed with the shipped NUMBERS
var _n_zero_dem := 0              # …band frames whose demand was EXACTLY 0: the AMBIGUOUS state
var _rate_seen := 0.0
var _rhat_seen := 0.0
var _win_seen := 0.0
var _stop_seen := 0.0
var _worst := 0.0                 # slice 30's aim point, READ OFF THE WIRE (never recomputed)
var _pos_trace: Array = []

func _initialize() -> void:
	print("S35V_INIT godot=", Engine.get_version_info().string)
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
	var aerr := _finish_arm()
	if aerr != "":
		return _fail(aerr)
	if _idx + 1 >= _arms.size():
		return _verdict()
	_launch_arm()
	return false

# --- the flight plan ------------------------------------------------------------------------

func _build_arms() -> void:
	# 1) THE SHIPPED WIRE, untouched (R̂ = -0.03, servo 40 deg/s) — and its REPLAY.
	_arms.append({"tag": "open"})
	_arms.append({"tag": "replay"})
	# 2) ⭐⭐ THE TWO-SIDED KNOB — the servo slider walked across its WHOLE declared domain on the
	#    default design. `open` IS the 40 deg/s rung, so the ladder is 60 / 25 / 15 / 8 beside it.
	_arms.append({"tag": "r60", "rate": RATE_HI, "rhat": RHAT_03})
	_arms.append({"tag": "r25", "rate": RATE_25, "rhat": RHAT_03})
	_arms.append({"tag": "r15", "rate": RATE_15, "rhat": RHAT_03})
	#    ⭐ AND THIS ARM IS THREE THINGS AT ONCE, which is why it is flown rather than three arms:
	#    the servo domain's FLOOR, the loud side of the 0-vs-97 saturation split, and the CORNER
	#    where the whole-approach requirement is largest anywhere in the two-slider domain.
	_arms.append({"tag": "r08", "rate": RATE_LO, "rhat": RHAT_03})
	# 3) ⭐⭐ THE 0-vs-97 SPLIT — the SAME 8 deg/s servo on slice 34's shipped design.
	_arms.append({"tag": "s18", "rate": RATE_LO, "rhat": RHAT_18})
	# 4) ⭐ SLICE 30's RULE PAYS A THIRD TIME (33 = FOV, 34 = detector window, 35 = servo bandwidth) —
	#    at the aim point the requirement is FLAT across the entire rate domain.
	_arms.append({"tag": "a33hi", "rate": RATE_HI, "rhat": RHAT_33})
	_arms.append({"tag": "a33lo", "rate": RATE_LO, "rhat": RHAT_33})
	# 5) ⭐⭐ THE DEMAND STEP across slice 34's OWN onset bracket, read at the servo domain's CEILING
	#    (the closest a live wire gets to an unlimited head — the free read is the ABSENT key, which
	#    no slider reaches, so the ceiling stands in for it AND that substitution is stated).
	_arms.append({"tag": "d18", "rate": RATE_HI, "rhat": RHAT_18})
	_arms.append({"tag": "d16", "rate": RATE_HI, "rhat": RHAT_16})
	# 6) THE R̂ SLIDER's FLOOR, at the SERVO's floor — the other corner of the domain (slice 26's
	#    post-commit rule: a declared domain's ENDPOINTS ARE MEASURED, never inferred).
	_arms.append({"tag": "gfloor", "rate": RATE_LO, "rhat": RHAT_36})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("rate"):
		cmds.append(_set_param_cmd(MID, "gimbal_rate_dps", float(arm["rate"])))
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
	# ⚠⚠ NaN, NOT 0.0, WHEN THE BAND IS EMPTY — slice 33's gate-2 finding, inherited: a `sum/max(n,1)`
	# would print a beautifully quiet `rms r = 0.00000` COMPUTED FROM ZERO SAMPLES, and `sat_band` a
	# beautifully free 0.00 %, on exactly the arm where both are undefined.
	var rms := NAN if _n_band == 0 else sqrt(_sum_r2 / float(_n_band))
	var sat_pc := NAN if _n_band == 0 else 100.0 * float(_n_sat) / float(_n_band)
	var aero_pc := NAN if _n_band == 0 else 100.0 * float(_n_aero) / float(_n_band)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		"head": _max_head, "off": _max_off, "offb": _off_band,
		"marg": NAN if _min_marg > 1.0e29 else _min_marg,
		"band": _n_band, "aero": aero_pc, "defl": _n_defl, "rms": rms, "sat": sat_pc,
		"dem95": _pct(_dems, 0.95), "rate": _rate_seen, "rhat": _rhat_seen,
		"win": _win_seen, "stop": _stop_seen, "worst": _worst, "flagbad": _n_flag_bad,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S35V_ARM   %-7s servo=%.1f deg/s  R̂=%+.4f  ->  miss=%.3f  rms_r=%.5f  sat_band=%.2f%% " +
		   "(%d band frames)  demand_p95=%.3f deg/s  off_band=%.3f  off_max=%.3f  head_max=%.3f  " +
		   "margin_min=%.2f  out=%.3f%% of %d gated  aero=%.2f%%  defl=%d  cpa=%s") %
		  [tag, m["rate"], m["rhat"], m["miss"], m["rms"], m["sat"], m["band"], m["dem95"],
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
				"closing at the end, so its miss (%.3f m) is a last closing range and not a CPA at " +
				"all. ToF spans 10.90-11.33 s across this file, so STEPS is sized off the SLOWEST arm " +
				"and every arm asserts this rather than trusting the sizing") % [tag, STEPS, _min_los]
	# ⚠⚠ THE WINDOW MUST NEVER BITE, ON ANY ARM. This is the load-bearing condition of the whole file,
	# not a hygiene check: gate 0's ship/no-ship gate found that a rate-limited arm which BREAKS breaks
	# by SLICE 34's mechanism, and gate 2 found that under a rate limit the requirement that breaks it
	# is the ACQUISITION TURN's, out at launch range — slice 34's lesson re-run as a third mechanism.
	# So the window is AUTHORED WIDE and this asserts the authoring was right. If it fires, every
	# number on this arm is measuring a frozen index instead of a servo.
	if not (out_pc == 0.0):
		return ("arm %s: THE DETECTOR WINDOW MUST NEVER BITE (%.3f %% of gated frames out). It is " +
				"AUTHORED at %.1f deg against a worst whole-approach requirement of %.3f deg measured " +
				"over 184 domain cells, precisely so that what this file measures is the SERVO. A " +
				"windowed arm freezes the head's index, and a frozen index is QUIET at every R̂ — so " +
				"rms r would FALL, `sat_band` would fall to 0 (a held head demands nothing), and both " +
				"would read as good news") % [tag, out_pc, WIN_AUTH, REQ_WORST]
	if not (_max_off < _win_seen):
		return ("arm %s: the whole-approach tracking error (%.3f deg) must stay inside the authored " +
				"window (%.3f deg) — the same claim as the line above, measured as an ANGLE rather " +
				"than as a count, so a single-frame excursion cannot hide inside a rounded " +
				"percentage") % [tag, _max_off, _win_seen]
	# ⚠ AND THE MECHANICAL STOP MUST NOT BIND EITHER, or the two limits stop being separable: a
	# clamped head cannot reach the LOS, so its deficit is charged to the DETECTOR budget (slice 34's
	# gate 2). The stop is a RESTATEMENT of slice 33's excursion, not a limit this slice is about.
	if not (_max_head < _stop_seen and _max_head < MODEL_VALID_DEG):
		return ("arm %s: the head's travel (%.3f deg) must stay inside BOTH the mechanical stop " +
				"(%.3f deg) and the small-angle bend budget 28/29/30/31 each " +
				"declared (%.0f deg)") % [tag, _max_head, _stop_seen, MODEL_VALID_DEG]
	# ⚠ A CONSISTENCY CHECK ON THE SEAM's UNIT CONVERSION, AND THAT IS ALL IT IS — SAID PLAINLY
	# BECAUSE THE FIRST DRAFT CLAIMED MORE (advisor). The kernel branches on `head_dem > deg2rad(cap)
	# * dt` and the seam ships `rad2deg(head_dem)/dt` beside the authored `cap`, so this comparison is
	# the SAME ONE REARRANGED, computed from the same two floats. It CANNOT disagree except at a 1-ULP
	# boundary, which the tolerance then excludes — a tautology in convention 11's sense, and it does
	# NOT license anything. What it would actually catch is a units regression in the seam (a lost
	# `deg2rad`, a `dt` that stopped being the physics step), which is worth one cheap counter and no
	# more. The real reason the client may not re-derive the predicate is architectural and is argued
	# where it belongs, at the HUD.
	if not (_n_flag_bad == 0):
		return ("arm %s: the shipped `head_rate_sat` disagreed with the shipped demand-vs-cap on %d " +
				"frames. These are the same comparison rearranged, so a disagreement means the seam's " +
				"unit conversion has drifted — not that the flag is wrong") % [tag, _n_flag_bad]
	# ⭐ THE TOOTH WITH ACTUAL CONTENT IS THE **ZERO**, AND IT IS THE TWO-RUN DISCIPLINE's FOURTH
	# QUANTITY MEASURED RATHER THAN DESCRIBED. A zero demand is AMBIGUOUS BY CONSTRUCTION: the HANDOVER
	# tick (which calls `head_clamp` and never slews) and every tick with the target OUTSIDE the
	# detector window (the head HOLDS — no error signal, no slew) both ship demand 0.0 AND flag 0.0. So
	# `head_rate_sat` reads FREE on a broken arm for exactly the reason `rms r` reads QUIET there, and
	# the band percentile is only a statement about the SERVO if no band frame is one of those.
	# ⚠ ONE-SIDED, AND THE FILE SAYS SO: this wire's window never bites, so only the HELD side is
	# reachable here (the LOST side is slice 34's wire and a different mechanism — gate 0's ship gate
	# came back negative on it). What is asserted is that the ambiguous state is EMPTY in band, which
	# is what makes `sat_band` and `dem95` measurements of a servo rather than of a held head.
	if not (_n_zero_dem == 0):
		return ("arm %s: %d of %d band frames shipped a demand of EXACTLY 0.0 — the ambiguous state " +
				"(a HANDOVER tick, or a head HOLDING with no error signal). Every band statistic in " +
				"this file would then be averaging a servo together with a head that was not slewing " +
				"at all, and `sat_band` would read FREE for the same reason a broken arm's `rms r` " +
				"reads QUIET") % [tag, _n_zero_dem, _n_band]
	# ⚠ THE ISOLATION IS `defl_sat`, NOT `aero_sat` — slice 33's inversion, inherited with its warning.
	# A ringing arm here saturates the slice-19 aero ceiling heavily AND STILL HITS (slice 26's ceiling
	# BOUNDING the cycle), so aero_sat discriminates in NEITHER direction; deflection saturation is
	# what must be zero, or the fin is out of authority and the miss stops being about the head at all.
	if not (_n_defl == 0):
		return ("arm %s: `defl_sat` must be EXACTLY 0 (got %d) — with the fin out of authority the " +
				"engagement stops being about the servo") % [tag, _n_defl]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var op: Dictionary = _res["open"]
	var rp: Dictionary = _res["replay"]
	var r60: Dictionary = _res["r60"]
	var r25: Dictionary = _res["r25"]
	var r15: Dictionary = _res["r15"]
	var r08: Dictionary = _res["r08"]
	var s18: Dictionary = _res["s18"]
	var a33hi: Dictionary = _res["a33hi"]
	var a33lo: Dictionary = _res["a33lo"]
	var d18: Dictionary = _res["d18"]
	var d16: Dictionary = _res["d16"]
	var gfl: Dictionary = _res["gfloor"]

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE OPEN — the shipped wire, and it opens ON THE DISEASE (slice 33's default, and slice 34's
	# departure from it does not transfer: 34 opened quiet because the two-run discipline forbids a
	# stability verdict on an arm whose window binds, and here the window never binds).
	print("S35V_OPEN     the shipped wire: servo %.0f deg/s, R̂ %+.2f -> rms r %.5f (RINGING), the servo saturated on %.2f %% of the band against a demand p95 of %.3f deg/s, the head lags %.3f deg in band and %.3f deg over the whole approach, and it still HITS (%.3f m)" %
		  [float(op["rate"]), float(op["rhat"]), float(op["rms"]), float(op["sat"]),
		   float(op["dem95"]), float(op["offb"]), float(op["off"]), float(op["miss"])])
	if not (float(op["rms"]) > RING):
		return _fail(("PHASE OPEN: the shipped wire must OPEN ON THE DISEASE — rms r %.5f must exceed " +
			"the arc's %.2f line. The servo knob is only worth dragging where the loop rings, because " +
			"the DEMAND is what the parasitic loop sets") % [float(op["rms"]), RING])
	if not (float(op["sat"]) > 25.0 and float(op["sat"]) < 95.0):
		return _fail(("PHASE OPEN: the DEFAULT must sit in the PARTIALLY-saturated region (%.2f %%, " +
			"must be between 25 and 95). At the top the servo is ~free and at the bottom it is a " +
			"100 %%-saturated OPEN-LOOP RAMP whose ring ratio is UNQUOTABLE (gate 0 §0.6) — the " +
			"default has to be somewhere a student can drag BOTH ways and see something move") %
			float(op["sat"]))
	if not (float(op["dem95"]) > float(op["rate"])):
		return _fail(("PHASE OPEN: the demanded head rate (p95 %.3f deg/s) must EXCEED the servo's cap " +
			"(%.1f deg/s) — the shipped demand is PRE-limit, which is the entire reason " +
			"`head_slew_full` exists. A post-hoc difference of the head's own angles would read the " +
			"CLIPPED motion and report the CAP as the demand, i.e. the answer as the question") %
			[float(op["dem95"]), float(op["rate"])])
	if not (float(op["miss"]) < HIT_MAX):
		return _fail(("PHASE OPEN: the arc's standing fact since slice 26 must hold — a RINGING arm " +
			"with a window it never reaches STILL HITS (%.3f m, must be < %.1f). If this fires, the " +
			"ring has started costing accuracy and the family's choice of metric is wrong") %
			[float(op["miss"]), HIT_MAX])

	# PHASE REPLAY — determinism (class 4a: the seed is LOAD-BEARING, conventions 3/11).
	var pd := _pos_max_diff(op["pos"], rp["pos"])
	print("S35V_REPLAY   the SAME held seed, the SAME sliders, twice: max|Δpos| = %.6f m over %d frames" % [pd, int(min(op["pos"].size(), rp["pos"].size()))])
	if not (pd == 0.0):
		return _fail(("PHASE REPLAY: a held seed must replay BIT-IDENTICALLY (max|Δpos| %.9f m). The " +
			"rate limit is a DETERMINISTIC bound on an existing servo — no new draw, class 4a, the " +
			"ELEVENTH consecutive RNG-live slice") % pd)

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE TRADE — ⭐⭐ THE ARC's FIRST TWO-SIDED KNOB.
	var ring_ratio: float = float(r60["rms"]) / maxf(float(r08["rms"]), 1.0e-9)
	var req_ratio: float = float(r08["offb"]) / maxf(float(r60["offb"]), 1.0e-9)
	print("S35V_TRADE    ONE SLIDER, TWO BOUNDS, OPPOSITE DIRECTIONS. Servo %.0f -> %.0f -> %.0f -> %.0f -> %.0f deg/s at R̂ %+.2f: the RING falls %.5f -> %.5f -> %.5f -> %.5f -> %.5f (%.2fx) while the tracking error it must cover GROWS %.3f -> %.3f -> %.3f -> %.3f -> %.3f deg (%.2fx), and the servo goes from %.2f %% saturated to %.2f %%" %
		  [float(r60["rate"]), float(op["rate"]), float(r25["rate"]), float(r15["rate"]), float(r08["rate"]),
		   float(r60["rhat"]),
		   float(r60["rms"]), float(op["rms"]), float(r25["rms"]), float(r15["rms"]), float(r08["rms"]), ring_ratio,
		   float(r60["offb"]), float(op["offb"]), float(r25["offb"]), float(r15["offb"]), float(r08["offb"]), req_ratio,
		   float(r60["sat"]), float(r08["sat"])])
	# THE RING SIDE — MONOTONE across the whole ladder, which is what makes it a mechanism and not a
	# pair of endpoints. A rate limit ATTENUATES the parasitic feed because the motion that holds the
	# track is the motion that feeds the loop.
	var ladder := [r60, op, r25, r15, r08]
	for i in range(1, ladder.size()):
		var hi: Dictionary = ladder[i - 1]
		var lo: Dictionary = ladder[i]
		if not (float(lo["rms"]) < float(hi["rms"])):
			return _fail(("⭐⭐ PHASE TRADE: the RING must fall MONOTONICALLY as the servo slows — at " +
				"%.0f deg/s rms r is %.5f against %.5f at %.0f. Monotonicity is what makes this a " +
				"mechanism rather than two endpoints, and it is the half of the trade that looks like " +
				"a free lunch") % [float(lo["rate"]), float(lo["rms"]), float(hi["rms"]), float(hi["rate"])])
	if not (ring_ratio > 2.0):
		return _fail(("⭐⭐ PHASE TRADE: the ring must be ATTENUATED by a factor worth quoting across " +
			"the slider (%.2fx, must exceed 2). Measured 2.29x per tick, 0.88469 -> 0.38591") % ring_ratio)
	# THE COST SIDE — quoted ENDPOINT TO ENDPOINT, and the interior is NOT claimed monotone.
	if not (req_ratio > 2.0):
		return _fail(("⭐⭐ PHASE TRADE: and the tracking error the head must cover must GROW by a " +
			"comparable factor (%.2fx, must exceed 2) — that is the whole payload. Slices 32, 33 and " +
			"34 all end 'widen it, it is free'; THAT CURE DOES NOT TRANSFER, because servo bandwidth " +
			"is not a window, it is what the parasitic loop FEEDS ON") % req_ratio)
	# ⚠ AND THE INTERIOR IS NON-MONOTONE, ASSERTED AS A MEASURED FACT RATHER THAN SMOOTHED AWAY. Gate
	# 0 found the same wrinkle on the R̂ = -0.16 row (the ring-suppression benefit briefly outrunning
	# the lag cost around 10-12 deg/s) and NOTHING is built on it — the ~5th occurrence of that
	# pattern in this arc after 19/20/22/28. A one-sided "it grows" assert would be a false claim.
	if not (float(r15["offb"]) > float(r08["offb"])):
		return _fail(("⭐⭐ PHASE TRADE: the interior NON-MONOTONICITY is pinned as a fact, and it just " +
			"changed: %.3f deg at %.0f deg/s must exceed %.3f at %.0f. The claim is ENDPOINT TO " +
			"ENDPOINT precisely because of this cell") %
			[float(r15["offb"]), float(r15["rate"]), float(r08["offb"]), float(r08["rate"])])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE SPLIT — ⭐⭐ ONE SERVO, TWO DESIGNS, AND IT IS WHAT THE DOMAIN FLOOR IS CHOSEN ON.
	print("S35V_SPLIT    the SAME %.0f deg/s servo on two designs: slice 34's shipped R̂ %+.2f saturates it on %.2f %% of the band (demand p95 %.3f deg/s) while the boresight-characterized R̂ %+.2f saturates it on %.2f %% (demand p95 %.3f) — a 0-vs-97 split, and the two quantities come from DIFFERENT code paths in the kernel" %
		  [RATE_LO, float(s18["rhat"]), float(s18["sat"]), float(s18["dem95"]),
		   float(r08["rhat"]), float(r08["sat"]), float(r08["dem95"])])
	if not (float(s18["sat"]) == 0.0):
		return _fail(("⭐⭐ PHASE SPLIT: at the servo domain's FLOOR the GOOD design must not saturate " +
			"AT ALL (%.2f %%, must be exactly 0). That is what makes 8 deg/s the floor: it is where " +
			"the knob is simultaneously FREE for a good design and BINDING for a bad one — a stronger " +
			"reason than 'it stops being a servo'") % float(s18["sat"]))
	if not (float(r08["sat"]) > 90.0):
		return _fail(("⭐⭐ PHASE SPLIT: …and the BAD design must saturate almost everywhere (%.2f %%, " +
			"must exceed 90). Measured 97.14 %%") % float(r08["sat"]))

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE RULE — ⭐ SLICE 30's RULE PAYS A THIRD TIME (33 = FOV, 34 = detector window, 35 = SERVO).
	var flat: float = absf(float(a33hi["offb"]) - float(a33lo["offb"]))
	print("S35V_RULE     at slice 30's aim point R0+2A = %+.4f (READ OFF THE WIRE, never recomputed) the servo is FREE across its WHOLE domain: %.0f -> %.0f deg/s moves the requirement by %.4f deg (%.3f -> %.3f) and the rate limit BINDS ON 0.00 %% of the band at both ends (%.2f, %.2f) — aim R̂ at the glass's worst-case slope and you may fly the cheapest servo in the catalogue" %
		  [float(a33lo["worst"]), float(a33hi["rate"]), float(a33lo["rate"]), flat,
		   float(a33hi["offb"]), float(a33lo["offb"]), float(a33hi["sat"]), float(a33lo["sat"])])
	if not (absf(float(a33lo["rhat"]) - float(a33lo["worst"])) < 1.0e-6):
		return _fail(("PHASE RULE: the aim-point arm must sit AT `radome_slope_worst` as the CORE " +
			"ships it (R̂ %+.6f against %+.6f). The wire's own value is -0.32999999999999996, not " +
			"-0.33 — the slice-21 magic-multiple tooth, pinned against a measured quantity") %
			[float(a33lo["rhat"]), float(a33lo["worst"])])
	if not (flat < 0.05):
		return _fail(("⭐ PHASE RULE: at the aim point the requirement must be FLAT across the whole " +
			"rate domain (moved %.4f deg, must stay under 0.05). Against %.2fx at the boresight " +
			"characterization — the rate knob's COST is charged by the RING, and the ring is what R̂ " +
			"sets. That is also why convention 9 admits both sliders: they are ONE axis") %
			[flat, req_ratio])
	if not (float(a33hi["sat"]) == 0.0 and float(a33lo["sat"]) == 0.0):
		return _fail(("⭐ PHASE RULE: …and the servo must never bind at the aim point, at EITHER end of " +
			"its domain (%.2f %%, %.2f %%). The requirement being flat and the servo never binding are " +
			"two different quantities saying the same thing, which is what makes the rule a measurement") %
			[float(a33hi["sat"]), float(a33lo["sat"])])
	if not (float(a33lo["rms"]) < RING and float(a33hi["rms"]) < RING):
		return _fail(("⭐ PHASE RULE: the aim point must be QUIET at both ends of the rate domain " +
			"(%.5f, %.5f against the %.2f line) — slice 30's one-sided constraint, intact under a " +
			"rate limit") % [float(a33lo["rms"]), float(a33hi["rms"]), RING])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE DEMAND — ⭐⭐ WHERE THE DEMAND ACTUALLY LIVES, AND IT STEPS AT SLICE 34's OWN BRACKET.
	var step: float = float(d16["dem95"]) / maxf(float(d18["dem95"]), 1.0e-9)
	print("S35V_DEMAND   at the servo domain's CEILING (%.0f deg/s — the closest a live wire gets to an unlimited head), the band demand STEPS ACROSS SLICE 34's OWN ONSET BRACKET: R̂ %+.2f asks for %.3f deg/s and R̂ %+.2f for %.3f — %.1fx — while rms r crosses the %.2f line (%.5f -> %.5f). A quiet design asks its servo for essentially nothing; a ringing one must chase its own oscillation" %
		  [RATE_HI, float(d18["rhat"]), float(d18["dem95"]), float(d16["rhat"]), float(d16["dem95"]),
		   step, RING, float(d18["rms"]), float(d16["rms"])])
	if not (float(d18["rms"]) < RING and float(d16["rms"]) > RING):
		return _fail(("PHASE DEMAND: the two arms must straddle slice 34's onset bracket (-0.18, -0.16] " +
			"— quiet %.5f and ringing %.5f against the %.2f line. The demand step is only a statement " +
			"about the LOOP if the loop is what changed between them") %
			[float(d18["rms"]), float(d16["rms"]), RING])
	if not (float(d18["dem95"]) < 2.5):
		return _fail(("⭐⭐ PHASE DEMAND: the QUIET design's band demand must be tiny (%.3f deg/s, must " +
			"stay under 2.5 — measured 0.600). On a settled collision course the LOS barely moves in " +
			"the body frame, which this arc has measured three times (slice 28's 0.2 deg band, slice " +
			"29's refutation 1, slice 34's constant head angle)") % float(d18["dem95"]))
	if not (step > 20.0):
		return _fail(("⭐⭐ PHASE DEMAND: the step across ONE RUNG of the R̂ ladder must be an order of " +
			"magnitude, not a trend (%.1fx, must exceed 20). Measured 53.6x. THE DEMAND IS SET BY THE " +
			"PARASITIC LOOP — that is the sentence this number is") % step)
	# ⚠ AND THE PEAK IS AN ARTEFACT AND IS NEVER QUOTED (gate 0 §0.2): `rate_max` is an identical
	# 72.542 deg/s on EVERY arm, because it is the tick-2 HANDOVER transient, before the arms have
	# diverged at all. Percentiles and the band, never the peak — slice 25's "exclude the init ticks"
	# rule in a new quantity. Nothing in this file reads a maximum demand.

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE WINDOW — ⚠ THE AUTHORED WINDOW IS A MEASUREMENT, AND THIS PHASE IS WHY IT IS AUTHORED.
	print("S35V_WINDOW   the DETECTOR window is AUTHORED at %.1f deg and is NOT a knob (slice 34's one live slider, dropped here ON A NUMBER): the worst whole-approach requirement over the whole two-slider domain is %.3f deg, at the corner this file flies as r08 (measured %.3f), and NO arm ever leaves its window (out = 0.00 %% on all %d). Under a rate limit the binding requirement is the ACQUISITION TURN's, out at launch range — a LIVE window would make this wire's break slice 34's lesson re-run as a third mechanism" %
		  [WIN_AUTH, REQ_WORST, float(r08["off"]), _arms.size()])
	# ⭐ DERIVED FROM THIS RUN FIRST, AND ONLY THEN CROSS-CHECKED AGAINST THE GRID (the slice-21
	# magic-multiple discipline, and the advisor's catch at this gate): the corner arm's requirement
	# must be the LARGEST of every arm flown here, which is a statement this run can make on its own.
	# `REQ_WORST` below is a MEASURED constant from a probe that is not in the repo, so it is the
	# corroboration and never the primary claim — see the const's own comment for the grid.
	for k in _res.keys():
		if float(_res[k]["off"]) > float(r08["off"]) + EXACT:
			return _fail(("PHASE WINDOW: arm %s's whole-approach requirement (%.3f deg) EXCEEDS the " +
				"domain corner's (%.3f). The corner is where the fine grid put the maximum, and the " +
				"authored window is sized against it — if some other cell is worse, the sizing rests " +
				"on the wrong cell") % [str(k), float(_res[k]["off"]), float(r08["off"])])
	if not (absf(float(r08["off"]) - REQ_WORST) < 0.2):
		return _fail(("PHASE WINDOW: the domain CORNER's whole-approach requirement must reproduce the " +
			"fine-grid maximum (%.3f deg against a MEASURED %.3f). If it has moved, the authored " +
			"window was sized against a measurement that no longer holds and the grid must be re-flown") %
			[float(r08["off"]), REQ_WORST])
	for k in _res.keys():
		var a: Dictionary = _res[k]
		if not (float(a["win"]) == WIN_AUTH):
			return _fail(("PHASE WINDOW, arm %s: the window must be the AUTHORED %.1f deg on every arm " +
				"(got %.3f) — nothing in this file touches it, and that is the point") %
				[str(k), WIN_AUTH, float(a["win"])])
		if not (float(a["off"]) < WIN_AUTH):
			return _fail(("PHASE WINDOW, arm %s: the whole-approach requirement (%.3f deg) must clear " +
				"the authored window (%.1f)") % [str(k), float(a["off"]), WIN_AUTH])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE FLOOR — the R̂ slider's own endpoint, at the SERVO's endpoint: the other domain corner.
	print("S35V_FLOOR    the R̂ slider's FLOOR (%+.2f, PAST slice 30's aim point %+.4f) at the servo's floor (%.0f deg/s): rms r %.5f (QUIET — the one-sided constraint holds, a positive residual DE-TUNES rather than rings), servo %.2f %% saturated, requirement %.3f deg of %.1f, head travel %.3f deg of %.0f, miss %.3f m" %
		  [float(gfl["rhat"]), float(gfl["worst"]), float(gfl["rate"]), float(gfl["rms"]),
		   float(gfl["sat"]), float(gfl["off"]), float(gfl["win"]), float(gfl["head"]),
		   float(gfl["stop"]), float(gfl["miss"])])
	if not (float(gfl["rms"]) < RING):
		return _fail(("PHASE FLOOR: PAST slice 30's aim point the loop must stay QUIET (%.5f against " +
			"%.2f) — the one-sided constraint (only a NEGATIVE residual rings) is what makes the aim " +
			"point SUFFICIENT rather than tight, and it must survive the rate limit") %
			[float(gfl["rms"]), RING])
	if not (float(gfl["sat"]) == 0.0):
		return _fail(("PHASE FLOOR: …and the servo must still be FREE there (%.2f %%) — overshooting " +
			"slice 30's rule does not un-buy the cheap servo it bought") % float(gfl["sat"]))

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
	_n_aero = 0
	_n_defl = 0
	_sum_r2 = 0.0
	_n_flag_bad = 0
	_n_zero_dem = 0
	_rate_seen = 0.0
	_rhat_seen = 0.0
	_win_seen = 0.0
	_stop_seen = 0.0
	_worst = 0.0
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
		if tel.has(MID + ".gimbal_rate_dps"):
			_rate_seen = float(tel[MID + ".gimbal_rate_dps"])
		if tel.has(MID + ".gimbal_fov_deg"):
			_win_seen = float(tel[MID + ".gimbal_fov_deg"])
		if tel.has(MID + ".gimbal_stop_deg"):
			_stop_seen = float(tel[MID + ".gimbal_stop_deg"])
		if tel.has(MID + ".radome_slope_est"):
			_rhat_seen = float(tel[MID + ".radome_slope_est"])
		if tel.has(MID + ".radome_slope_worst"):
			_worst = float(tel[MID + ".radome_slope_worst"])
		# ⭐ THE FLAG AGAINST THE NUMBERS, PER FRAME. The core ships the demand PRE-limit in deg/s and
		# the cap in deg/s, and the flag is the kernel's own branch predicate on exactly that
		# comparison — so they must agree on every frame. Counted here rather than compared once at
		# the end, because a disagreement would live at a single boundary tick.
		# ⚠ A ZERO DEMAND IS AMBIGUOUS BY CONSTRUCTION and does not participate: tick 1 (the HANDOVER,
		# which calls `head_clamp` and never slews) and every tick with the target outside the window
		# both ship 0.0 demand and 0.0 sat, so the implication only runs one way there.
		if tel.has(MID + ".head_rate_sat") and tel.has(MID + ".head_rate_dps"):
			var dm := float(tel[MID + ".head_rate_dps"])
			var cp := float(tel[MID + ".gimbal_rate_dps"])
			var st := float(tel[MID + ".head_rate_sat"]) >= 0.5
			if st and dm < cp * (1.0 - EXACT):
				_n_flag_bad += 1
			elif not st and dm > cp * (1.0 + EXACT):
				_n_flag_bad += 1
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				# WINDOW 1 — the WHOLE-APPROACH window, RANGE-GATED at r > 200 m. ⚠ Ungated, the endgame
				# LOS swing makes a QUIET arm read a few tenths of a percent out and its tracking error
				# read tens of degrees (slice 33's five failing asserts, slice 34's inherited fix).
				# ⚠⚠ THIS WINDOW IS WHERE THE *REQUIREMENT* LIVES ON A RATE-LIMITED ARM, and that is
				# gate 2's own finding: the LOOP's requirement (the band, below) barely moves under a
				# rate limit while the whole-approach one TRIPLES, out at LAUNCH RANGE, because the
				# ACQUISITION TURN is the largest slew demand in the engagement. Both are measured, and
				# they are read against different things — the band against the loop, this against the
				# authored window.
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
				# WINDOW 2 — the ISOLATION band, 28/29/30/31/33/34's [500, 3000] m, inherited with its
				# reasons and with ONE gate-0 addition that is this slice's own: the LAUNCH TURN happens
				# at r ~ 6000 m, so the band excludes the acquisition confound BY CONSTRUCTION rather
				# than by a tuned t0. With NO GLASS AT ALL the whole-approach error still runs 2.1 ->
				# 12.3 deg under a rate limit while the band stays a flat 0.031 — that is the missile's
				# own turn, not the loop's, and no number may be attributed to the loop without this gate.
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
					# ⭐ THE AMBIGUOUS STATE, COUNTED: a demand of EXACTLY 0.0 is the HANDOVER tick or a
					# head HOLDING with no error signal, and it carries a flag of 0.0 with it. If any
					# band frame is one of those, `sat_band` and `dem95` stop being about the servo.
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

# ⚠ A PERCENTILE, NEVER A PEAK (gate 0 §0.2): `rate_max` is an identical 72.542 deg/s on EVERY arm
# because it is the tick-2 HANDOVER transient, before the arms have diverged. Slice 25's "exclude the
# init ticks" rule arriving in a new quantity.
func _pct(v: Array, q: float) -> float:
	if v.is_empty():
		return NAN
	var s := v.duplicate()
	s.sort()
	return float(s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)])

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice35_rate":
		return "expected the 'slice35_rate' scenario, got '%s'" % str(f.get("name", ""))
	if not bool(f.get("airframe_view", false)):
		return "a slice-35 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-35 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("radome_view", false)):
		return "a slice-35 wire carries GLASS, so it must ship radome_view=true — and that is also what DROPS the shared fidelity button, at both client sites, with no edit needed (slice 33's finding, third occurrence)"
	if not bool(f.get("gimbal_view", false)):
		return "a slice-35 wire carries a HEAD, so it must ship gimbal_view=true"
	# ⭐⭐ THE NEW MARKER, AND ⚠⚠ THE RE-CHECK THE PLAN DEMANDED CAME BACK **NEGATIVE**, which is the
	# result worth writing down. Slice 34's marker plugged a REAL HOLE — its wire raised neither FOV
	# marker (the loader refuses `seeker_fov_deg` beside a head) and fell through into slice 26/27/28's
	# RADOME cascade, confidently wrong about the SUBJECT. Nothing of the kind happens here: a slice-35
	# wire is a slice-34 wire PLUS one key, `gimbal_view` is raised, and the branch it selects is still
	# about the HEAD. This marker is a BRANCH SELECTOR, and what it selects is the half slice 34's HUD
	# CANNOT SAY: that HUD pairs the tracking error against the DETECTOR WINDOW, which is AUTHORED WIDE
	# here and never binds, so it would print a true verdict about a comfortable budget and never
	# mention the SERVO. ⇒ the failure mode is an INVISIBLE SLICE, not a wrong number, and the two must
	# not be taught as one rule.
	if not bool(f.get("gimbal_rate_view", false)):
		return "a slice-35 handshake must ship gimbal_rate_view=true — without it the client draws slice 34's head HUD, which pairs the tracking error against a DETECTOR WINDOW that is authored wide here and never binds. Every number it drew would be TRUE and the slice would be INVISIBLE: no demand, no cap, no saturation, no trade"
	if f.has("seeker_fov_view"):
		return "a slice-35 wire must NOT raise seeker_fov_view — the loader refuses `seeker_fov_deg` beside a head (a gimballed seeker has no body-fixed window; its body-fixed limit is the mechanical STOP)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-35 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS a look angle at all, and the loader refuses `gimbal_tau_s` without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-35 scenario must HOLD :airframe at six_dof — the head AND the attitude it is measured against are gated on that LIVE rung, so they freeze and resume together. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-35 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-35 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-35 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-35 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the aero ceiling 93.2% of its approach, a THIRD mechanism)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-35 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	if not keys.has("gimbal_rate_dps"):
		return "the slice-35 wire must expose the 'gimbal_rate_dps' slider — the slice's one genuinely new axis, and the arc's FIRST TWO-SIDED knob"
	if str(keys["gimbal_rate_dps"]) != MID:
		return "the servo knob must target the interceptor '%s'" % MID
	if not keys.has("radome_slope_est"):
		return "the slice-35 wire must expose the 'radome_slope_est' slider — the DESIGN side, and gate 2 measured the two to be ONE axis (the rate knob's COST is charged by the ring, and the ring is what R̂ sets)"
	if str(keys["radome_slope_est"]) != MID:
		return "the R̂ knob must target the interceptor '%s'" % MID
	if keys.size() != 2:
		return "the slice-35 wire must expose EXACTLY TWO knobs (got %d) — convention 9, satisfied BY MEASUREMENT (the slice-27 DIAGONAL precedent)" % keys.size()
	# ⭐⭐ THE DISQUALIFICATION THAT IS NEW, AND IT WAS DECIDED ON A NUMBER RATHER THAN AN ARGUMENT:
	# `gimbal_fov_deg` was slice 34's ONE live slider and is AUTHORED here.
	if keys.has("gimbal_fov_deg"):
		return "slice 35 must NOT expose a 'gimbal_fov_deg' knob, and this is the slice's own convention-9 finding rather than an inherited rule: under a rate limit the binding requirement is the ACQUISITION TURN's, out at LAUNCH RANGE (gate 2 measured `off_band` 1.956 -> 2.022 while `off_max` went 1.956 -> 8.051 at r ~ 5700 m, and on a wire with NO GLASS AT ALL the same thing happens). A LIVE window would therefore make this wire's break an ACQUISITION break — slice 34's own lesson re-run as a third mechanism, and a statement about the HANDOVER BASKET, which is slice 34's FIRST named deferral and a different slice"
	# The rest of the disqualifications live IN the gate, not only in the plan.
	if keys.has("gimbal_tau_s"):
		return "slice 35 must NOT expose a 'gimbal_tau_s' knob — slice 34's gate 2 measured the amplitude sagging monotonically with τ and, AT THE LINE, that sag crossing the verdict. A CONFOUNDED lever is a STRONGER reason to keep a key authored than a dead one"
	if keys.has("gimbal_stop_deg"):
		return "slice 35 must NOT expose a 'gimbal_stop_deg' knob — the stop is a RESTATEMENT of slice 33's excursion, and binding it COUPLES the two budgets (a clamped head cannot reach the LOS, so its deficit is charged to the DETECTOR allowance)"
	if keys.has("cross_speed_mps"):
		return "slice 35 must NOT expose 'cross_speed_mps' — it is slice 32's OWN axis (it moves the LEAD, and hence the head's travel requirement AND the demand)"
	if keys.has("af_alpha_max") or keys.has("alpha_max"):
		return "slice 35 must NOT expose an 'alpha_max' knob — slice 26's instrument for the ring's AMPLITUDE and a confounded lever"
	if keys.has("radome_slope") or keys.has("radome_ripple") or keys.has("radome_ripple_k"):
		return "slice 35 must NOT expose the GLASS itself — a radome's slope curve is HARDWARE, and the arc's point since slice 27 is that what an engineer can change is what they BELIEVE about it"
	if keys.has("n_pn"):
		return "slice 35 must NOT expose an 'n_pn' knob — it moves the parasitic boundary (N·|R − R̂|/ρ) AND the guidance loop"
	if keys.has("rho"):
		return "slice 35 must NOT expose a 'rho' knob — it moves the parasitic boundary and the aero ceiling at once"
	if keys.has("sigma_seek"):
		return "slice 35 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it"
	if keys.has("elevation_deg"):
		return "slice 35 must NOT expose 'elevation_deg' — the slice-19 DEAD-knob class, and on this wire it is also what sets a HANDED-OVER head's tick-1 pointing (the largest slew demand in the whole engagement)"
	if keys.has("speed"):
		return "slice 35 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-KNOB finding)"
	if keys.has("seeker_fov_deg"):
		return "slice 35 must NOT expose 'seeker_fov_deg' — the loader refuses it beside a head"
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
	var r60: Dictionary = _res["r60"]
	var r15: Dictionary = _res["r15"]
	var r08: Dictionary = _res["r08"]
	var s18: Dictionary = _res["s18"]
	var a33hi: Dictionary = _res["a33hi"]
	var a33lo: Dictionary = _res["a33lo"]
	var d18: Dictionary = _res["d18"]
	var d16: Dictionary = _res["d16"]
	var gfl: Dictionary = _res["gfloor"]
	print(("S35V OK: slice 34 gave the seeker a head and the head bought a stability margin by pointing " +
		"where its own bent measurement said the target was — but that head was INFINITELY FAST. A real " +
		"gimbal has a servo with a maximum slew rate, and the moment it does the head's motion stops " +
		"being free: it becomes a RESOURCE, spent against a demand. ⭐⭐ AND THE DEMAND IS SET BY THE " +
		"PARASITIC LOOP. At the servo domain's ceiling (%.0f deg/s), a design one rung BELOW slice 34's " +
		"onset asks its head for %.3f deg/s in the engagement band and a design one rung ABOVE it asks " +
		"for %.3f — %.1fx, ACROSS SLICE 34's OWN BRACKET, with rms r crossing the %.2f line (%.5f -> " +
		"%.5f). ⭐⭐ AND THIS IS THE ARC's FIRST TWO-SIDED KNOB: slices 32, 33 and 34 all end 'widen it, " +
		"it is free', and THAT CURE DOES NOT TRANSFER, because servo bandwidth is not a window — it is " +
		"what the loop FEEDS ON. Walk the slider %.0f -> %.0f deg/s on the shipped design and the RING " +
		"is attenuated %.5f -> %.5f (%.2fx, MONOTONICALLY across all five rungs) while the tracking " +
		"error it must cover GROWS %.3f -> %.3f deg (%.2fx). One knob, two bounds, no free direction. " +
		"⚠ Quoted ENDPOINT TO ENDPOINT: the interior is NON-MONOTONE and pinned as a measured fact " +
		"(%.3f deg at %.0f deg/s against %.3f at %.0f), the ~5th occurrence of that pattern in this arc. " +
		"⭐⭐ THE SHARPEST SINGLE PAIR IS A 0-vs-97 SPLIT AT ONE SERVO: at %.0f deg/s slice 34's shipped " +
		"design (R̂ %+.2f) saturates its rate limit on %.2f %% of the band while the boresight-" +
		"characterized default (R̂ %+.2f) saturates on %.2f %% — and that is what the domain FLOOR is " +
		"chosen on, a servo simultaneously FREE for a good design and BINDING for a bad one. " +
		"⭐ SLICE 30's RULE PAYS A THIRD TIME (33 = FOV, 34 = detector window, 35 = SERVO BANDWIDTH): at " +
		"the aim point R0+2A = %+.4f, READ OFF THE WIRE, the requirement is FLAT across the entire rate " +
		"domain (%.3f -> %.3f deg, a move of %.4f) and the limit binds on %.2f %% of the band at BOTH " +
		"ends — aim R̂ at the glass's worst-case slope and you may fly the cheapest servo in the " +
		"catalogue. ⚠⚠ THE DETECTOR WINDOW IS AUTHORED WIDE (%.1f deg) AND THAT IS THIS SLICE's OWN " +
		"CONVENTION-9 FINDING, not an inherited rule: under a rate limit the binding requirement is the " +
		"ACQUISITION TURN's, out at LAUNCH RANGE, so a LIVE window would make this wire's break slice " +
		"34's lesson re-run as a third mechanism. The worst whole-approach requirement anywhere in the " +
		"two-slider domain is %.3f deg (fine grid, 184 cells; this run measures %.3f at that corner) " +
		"and NO arm ever leaves its window. ⚠ THE BREAK IS NOT THIS SLICE's CLAIM AND NOTHING HERE " +
		"ASSERTS ONE — gate 0's own ship/no-ship gate came back NEGATIVE (a wider window rescues a " +
		"rate-limited arm), so the novelty is the REQUIREMENT and the TRADE, relocated rather than " +
		"defended. ⚠ Every arm HITS (%.3f m on the ringing default), the arc's standing fact since " +
		"slice 26 and the reason the verdict is rms r, sat_band and a tracking error — never a miss. " +
		"⚠ The R̂ floor PAST the aim point stays QUIET (%.5f) with the servo still FREE (%.2f %%). " +
		"⚠ NO new rung, cap, instability or draw: a deterministic bound on an existing servo. Class 4a, " +
		"the ELEVENTH consecutive RNG-live slice, replay bit-identical (max|Δpos| = 0.0), button " +
		"DROPPED (11th).")
		% [float(d18["rate"]), float(d18["dem95"]), float(d16["dem95"]),
		   float(d16["dem95"]) / maxf(float(d18["dem95"]), 1.0e-9), RING,
		   float(d18["rms"]), float(d16["rms"]),
		   float(r60["rate"]), float(r08["rate"]), float(r60["rms"]), float(r08["rms"]),
		   float(r60["rms"]) / maxf(float(r08["rms"]), 1.0e-9),
		   float(r60["offb"]), float(r08["offb"]),
		   float(r08["offb"]) / maxf(float(r60["offb"]), 1.0e-9),
		   float(r15["offb"]), float(r15["rate"]), float(r08["offb"]), float(r08["rate"]),
		   RATE_LO, float(s18["rhat"]), float(s18["sat"]), float(r08["rhat"]), float(r08["sat"]),
		   float(a33lo["worst"]), float(a33hi["offb"]), float(a33lo["offb"]),
		   absf(float(a33hi["offb"]) - float(a33lo["offb"])), float(a33lo["sat"]),
		   WIN_AUTH, REQ_WORST, float(r08["off"]), float(op["miss"]),
		   float(gfl["rms"]), float(gfl["sat"])])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S35V FAIL: " + msg)
	print("S35V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
