extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-47 gate-3 verifier — THE MIDCOURSE PHASE.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice47_midcourse.yaml
#   godot --headless --path clients/godot --script res://net/slice47_verify.gd     (exit 0 = pass)
#
# THE LESSON. A missile that cannot see its target flies on what it was told at launch: one snapshot
# of the target's position and velocity, dead-reckoned forward. Being told WRONG costs nothing you
# can see — the trajectory looks fine, the airframe is barely working, the miss column says nothing —
# right up until the receiver opens its eyes. Then it is paid all at once, in the one place the
# missile cannot get more of.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE: THE CLIFF IS THE WINDOW. The handover error — the
# angle between where the head is being TOLD to look and where the target really is — grows gently,
# linearly and monotonically with the picture error, and NOTHING HAPPENS until it crosses the
# authored 10.0° detector window. It crosses between 38 and 39 m/s of belief-velocity error, and the
# engagement flips THERE: 9.7846° acquires and arrives at 2.5 m; 10.0505° NEVER ACQUIRES and flies
# 316 m past. **The crossing and the flip are the same event**, and this file asserts them as one:
# the two cliff arms must STRADDLE the authored window, and the one on the `> fov` side must be the
# one that fails.
#
# ⚠⚠ AND THE MISS IS ASSERTED **FORBIDDEN AS THE GAUGE**, which is the half slices 44 and 45 died
# of. Over the surviving domain it walks 0.135 → 0.124 → 0.273 → 0.314 → 1.333 → 0.692 → 2.542 m —
# up and down by 20× — while the authority rises 4.27 → 27.97 % strictly. This file ASSERTS the
# non-monotonicity rather than merely avoiding the column: a verifier built on the headline metric
# here would not miss the lesson, it would read NOISE.
#
# ⚠⚠ §3.2's SECOND BAN — `gimbal_fov_margin_deg` — IS **RETRACTED BY THIS FILE**, and the retraction
# is measured rather than argued (§4b of the verdict). It was banned on gate-0 P6b's finding that the
# margin IMPROVES where the engagement is lost; on the shipped wire it separates the ends of the
# slider cleanly in BOTH samplings, because at the handover instant `margin + cue = fov` — a CUED
# head's pointing error against the truth LOS *is* the cue error. It stays off the HUD for
# REDUNDANCY (convention 9: one lesson, one gauge), not for deception, and §3.2's stated reason must
# not be quoted again.
#
# ⭐⭐ THE BUTTON IS THE SLICE'S OWN CONTROL, AND IT IS A BYTE-IDENTITY CLAIM. Press `seeker_detect`
# to `none` and the horizon goes away; the seeker has its target from tick 1, is never blind, and the
# midcourse arm is never taken. ⇒ WITH THE BUTTON PRESSED THE SLIDER MUST DO **NOTHING AT ALL** — two
# arms at opposite ends of its domain must be bit-identical. That is "the picture only matters
# because you are blind", stated as `max|Δpos| == 0` rather than as a sentence.
#
# ⚠⚠ THE HANDOVER ERROR IS READ FROM `head_cue_err_handover_deg` AND **NEVER** FROM
# `head_cue_err_deg`, and this is the trap gate 2 could not have seen because gate 2 had no client.
# The instantaneous key is a per-tick quantity that is 0.0 the moment the head TRACKS (true — a
# tracking head has no cue), so the handover value survives on NO frame after the switch. And this
# client sees one frame in `emit_every` = 16, so it cannot sample the last blind tick even while the
# missile is still blind: 15 ticks of staleness is ~0.02° against a cliff that straddles the window
# by 0.05°. The LATCHED key holds the last blind tick's value for the rest of the flight, which is
# what makes the degrees below assertable at all (`test_missile.jl` pins the two against each other).
#
# ⚠ THE SLIDER'S OWN TRIPWIRE IS THE HANDOVER ERROR ITSELF (slice 19's discipline): it is READ OFF
# THE WIRE and checked against the measured 0.503–0.522 °/% line, so each arm proves the slider
# reached THE PHYSICS rather than merely being accepted by the server. A `set_param` that is
# swallowed passes a sent-vs-echoed check and fails this one.
#
# ⚠ THE BROKEN ARMS NEVER LOCK, so anything that assumes a lock instant exists reads −1 on exactly
# the cells that carry the lesson. Every per-arm check below is written to be defined without one,
# and `hold` is NaN rather than a beautiful 100 % computed from zero samples (slice 33's finding).
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`) and every constant is sized off a FRAME column
# ([[ewsim-missile-verifier-sampling]] — the error is ASYMMETRIC: a MISS samples faithfully, a HIT
# samples COARSELY). The core's 2.542 m cliff arm reads several metres through the 16-tick grid.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — the seeker, the head and the ONE slider live here
const TID := "tgt1"               # the target — its rcs is AUTHORED here (it is slice 46's slider)

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16). The server emits every 16th tick,
# so a STEPS that is not a multiple makes the last frame land BELOW `STEPS*dt` and `_drain_scan` waits
# forever, SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 11200 = 16 * 700.
# ⚠ AND IT IS SIZED OFF THE **BROKEN** ARMS, NOT THE HITTING ONES: an arm that never acquires flies
# its stale picture well past the range at which a locking arm would have hit, reaching CPA at ~9.2 s
# against the hitting arms' ~7.3 s. Sizing this on the showcase arm would leave every cell that
# carries the lesson still closing at the end — and `_turned` would then fail them all.
const STEPS := 11200
const PRESS_AT := 3200            # the MID-RUN press tick — a multiple of 16, and BEFORE the ~7.26 s
                                  # handover, so the press is what removes the blind phase

const RUNG_ON := "snr"            # the AUTHORED rung — the showcase opens on the disease
const RUNG_OFF := "none"          # slices 11–45's angle-only seeker: no horizon, no blind phase

# THE SLIDER — the launch-time picture error, in m/s of believed target crossing speed, on the MINUS
# side (a belief that the target crosses SLOWER than it does). The DEFAULT is the LAST cell that
# still arrives, one notch below the cliff, already spending 6.5× the authority of a perfect picture.
const ERR_PERFECT := 0.0          # the domain FLOOR — and it is NOT a null: the midcourse still flies
const ERR_DEF := 38.0             # THE AUTHORED DEFAULT — 19.0 %, cue 9.7846°, the last arm that hits
const ERR_CLIFF := 39.0           # 19.5 % — cue 10.0505°, and it NEVER ACQUIRES
const ERR_TOP := 50.0             # the domain CEILING — 25 %, a full 11 m/s past the cliff
const LADDER := [0.0, 10.0, 20.0, 28.0, 34.0, 36.0, 38.0]   # the SURVIVING domain, in order

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const WIN_AUTH := 10.0            # ⭐ THE DETECTOR WINDOW — and on this wire it is the CLIFF's
                                  # location, not merely a seeker property
const STOP_AUTH := 30.0
const RATE_AUTH := 240.0          # slice 46's measured isolation — at 8 °/s the broken arms would
                                  # break for SLICE 35's reason instead
const CROSS_SPEED := 200.0        # the target's crossing speed — what the slider is a fraction OF

# ⭐ THE AXIS, MEASURED (gate-0 P1, corrected upward ~2 % on the COMMANDED trajectory in gate 2):
# the handover error grows 0.503 → 0.522° per % of belief-velocity error across the whole domain —
# as straight a line as this project has found, which is what makes a LINEAR slider right.
const SLOPE_LO := 0.48            # °/% — the bracket, deliberately wider than the measured walk
const SLOPE_HI := 0.56

const HIT_MAX := 30.0             # a HIT, frame-sampled — a sanity bound, NEVER the lesson
const MISS_BROKEN := 100.0        # the broken arms must miss by at least this — a VERDICT, not metres
const HOLD_OK := 99.0             # % of post-lock frames with the target available
const AUTH_FREE_MAX := 0.06       # the perfect-picture arm's post-lock spend (core: 4.27 %)
const AUTH_DEF_MIN := 0.20        # the default arm's (core: 27.97 %) — the DISEASE, one notch below
const AUTH_PRE_MAX := 0.05        # ⚠ P7's BRACKET: the BLIND command, on EVERY arm, read before the
                                  # handover range. The airframe must NOT be pinned before lock
                                  # anywhere in the domain — that would be a different slice.
const R_HANDOVER := 1437.0        # slice 46's horizon at the authored rcs — the range P7's bracket
                                  # is read before
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
var _pending_press := ""

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}

var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0                  # closing frames with r > 200 m
var _n_post := 0                  # closing frames after the FIRST availability
var _n_held := 0                  # …of which the target was still available
var _t_lock := -1.0               # the HANDOVER instant, frame-sampled — −1 on the broken arms
var _auth_peak := 0.0             # ⭐ post-lock, gated at r > 200 m
var _auth_pre := 0.0              # ⚠ P7's bracket — the BLIND command before the handover range
var _n_aero_pre := 0              # …and the aero saturation there, which must be 0 everywhere
var _n_sat := 0                   # slice 35's rate limit — the isolation, must stay 0
var _n_cued := 0                  # frames on which the head was flying the BELIEF
var _cue_hand := 0.0              # ⭐⭐⭐ THE LATCHED HANDOVER ERROR — the slice, in one number
var _cue_live_max := 0.0          # the instantaneous cue error's peak, for the freeze check
var _marg_at_hand := 0.0          # the angle margin ON THE LAST BLIND FRAME…
var _marg_post := 1.0e30          # …and its WORST value AFTER the handover — ⚠ the two are
                                  # different gauges with opposite verdicts (see §4 of the verdict)
var _pip_err := 0.0               # how far the believed intercept point was from the true one
var _act_n := 0                   # frames the midcourse guidance arm owned
var _n_midkey := 0                # frames carrying the midcourse keys — anchor-gated, never-stale
var _n_cuekey := 0                # …and the head's, which must ship on EVERY frame of BOTH modes
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S47V_INIT godot=", Engine.get_version_info().string)
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
	# AT ALL, so [step K, set_fidelity, step N-K] sent back-to-back applies the toggle at tick 0 and
	# silently measures a from-launch arm instead (slice 37's finding).
	if _pending_press != "":
		var rung := _pending_press
		_pending_press = ""
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": rung})
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
	# 1) ⭐⭐ THE LADDER over the SURVIVING domain, in order. These establish the axis (the handover
	#    error linear and monotone in the slider), the authority walking from cruising to the disease,
	#    and — the assertion, not the observation — the MISS carrying no signal along the same rows.
	#    ⚠ The bottom of the ladder is the PERFECT picture, and it is NOT a null: the midcourse still
	#    flies, correcting the authored launch heading onto the collision course. The arm that IS a
	#    null (no midcourse at all — 1203.7 m, never acquires) is not reachable from a client and is
	#    pinned in `test_missile.jl` instead, because it is a claim about the WIRE.
	for ev in LADDER:
		_arms.append({"tag": "e%d" % int(round(ev)), "err": ev})
	# 2) ⭐⭐⭐ THE CLIFF, AND ITS PARTNER IS ALREADY IN THE LADDER (`e38`). One metre per second apart,
	#    five hundredths of a degree either side of the authored window, and opposite verdicts.
	_arms.append({"tag": "cliff", "err": ERR_CLIFF})
	_arms.append({"tag": "top", "err": ERR_TOP})
	# 3) ⭐ DETERMINISM — same seed, same slider, same rung ⇒ the same missile to the last bit.
	_arms.append({"tag": "replay", "err": ERR_DEF})
	# 4) ⭐⭐ THE BUTTON, AT BOTH ENDS OF THE SLIDER. With the horizon off there is no blind phase and
	#    the midcourse arm is never taken, so these two must be BIT-IDENTICAL to each other — the
	#    slice's own control, stated as a byte-identity rather than as a sentence.
	_arms.append({"tag": "off_lo", "err": ERR_PERFECT, "rung": RUNG_OFF})
	_arms.append({"tag": "off_hi", "err": ERR_TOP, "rung": RUNG_OFF})
	# 5) ⭐ THE PRESS ITSELF, MID-FLIGHT, WHILE STILL BLIND — the one thing gates 1–2 could not cover
	#    is a `set_fidelity` reaching this rung with the midcourse arm still flying and the tracker
	#    still uninitialised. It must acquire IMMEDIATELY: the belief-cued head has been pointing
	#    within the window the whole time, and only the RANGE half was refusing it.
	_arms.append({"tag": "midpress", "err": ERR_DEF, "press": RUNG_OFF})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `snr` and the slider to its
	# authored 38.0 every arm — each arm must re-send its own. That is what makes these arms the
	# CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", RUNG_ON)) != RUNG_ON:
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": str(arm["rung"])})
	# ⚠ SENT ON EVERY ARM INCLUDING THE DEFAULT ONE, so the `e38` arm proves the SLIDER's own path to
	# its authored value rather than merely inheriting it from the YAML.
	_client.send(_set_param_cmd(MID, "midcourse_err_gain", float(arm["err"])))
	if arm.has("press"):
		_pending_press = str(arm["press"])
		_t_target = PRESS_AT * _dt
		_client.send({"type": "step", "n": PRESS_AT})
	else:
		_t_target = STEPS * _dt
		_client.send({"type": "step", "n": STEPS})

func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var blind: bool = str(arm.get("rung", RUNG_ON)) == RUNG_ON
	var pressed: bool = arm.has("press")
	# ⚠⚠ NaN, NOT 0.0, WHEN THERE ARE NO POST-LOCK FRAMES — slice 33's gate-2 finding, and on THIS
	# wire it is load-bearing rather than hygienic: the broken arms have no post-lock frames at all,
	# so a `sum/max(n,1)` would print a beautifully perfect `hold = 100.00 %` on precisely the cells
	# that carry the lesson.
	var hold := NAN if _n_post == 0 else 100.0 * float(_n_held) / float(_n_post)
	var m := {
		"miss": _min_los, "turned": _turned, "gate": _n_gate, "hold": hold,
		"tlock": _t_lock, "auth": _auth_peak, "auth_pre": _auth_pre, "aero_pre": _n_aero_pre,
		"sat": _n_sat, "cued": _n_cued, "cue": _cue_hand, "cue_live": _cue_live_max,
		"marg": _marg_at_hand, "marg_post": _marg_post, "pip": _pip_err, "act": _act_n, "err": float(arm["err"]),
		"blind": blind, "midkey": _n_midkey, "cuekey": _n_cuekey,
		"win": _win_seen, "stop": _stop_seen, "rate": _rate_seen,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S47V_ARM   %-9s err=%5.1f m/s (%4.1f%%) rung=%-4s  ->  cue@handover=%7.4f°  " +
		   "lock=%s  auth_peak=%5.1f%%  hold=%6.2f%%  miss=%9.4f  blind_frames=%d  sat=%d") %
		  [tag, m["err"], 100.0 * m["err"] / CROSS_SPEED, RUNG_ON if blind else RUNG_OFF,
		   m["cue"], _lock_str(m["tlock"]), 100.0 * m["auth"], m["hold"], m["miss"],
		   m["cued"], m["sat"]])
	if not (_n_gate > 100):
		return "arm %s: the r > 200 m window must contain frames to measure (got %d)" % [tag, _n_gate]
	if not _turned:
		return (("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing " +
				"at the end, so its miss (%.3f m) is a last closing range and not a CPA. ⚠ The " +
				"broken arms fly ~2 s LONGER than the hitting ones, and STEPS is sized off THEM") %
				[tag, STEPS, _min_los])
	# THE AUTHORED THREE, ON EVERY ARM: nothing in this file touches them, and that is the point.
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH):
		return (("arm %s: the window / stop / servo must be the AUTHORED %.1f / %.1f / %.1f " +
				"(got %.3f / %.3f / %.3f)") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, _win_seen, _stop_seen, _rate_seen])
	# ⚠⚠ SLICE 35's RATE LIMIT MUST NEVER BIND, ON ANY ARM — inherited from slice 46 as the
	# load-bearing precondition rather than as hygiene. The servo is authored at 240 °/s exactly so
	# that a broken arm's track loss can be attributed to the HANDOVER and not to a head chasing a
	# runaway LOS. ⚠ It matters MORE here than it did in 46: this slice's failures are all failures
	# of pointing, which is the servo's own job description.
	if not (_n_sat == 0):
		return (("arm %s: slice 35's rate limit bound on %d frames — a pointing failure on a wire " +
				"whose servo is saturating cannot be attributed to the PICTURE, which is the whole " +
				"claim. The servo is authored at %.0f °/s exactly so it cannot") %
				[tag, _n_sat, RATE_AUTH])
	# ⭐ THE NEVER-STALE DISCIPLINE (34/38/46): the midcourse keys are ANCHOR-gated, so they ship on
	# every frame of this wire regardless of which law is flying — and `head_cue_err_handover_deg`
	# must ship on every frame of BOTH modes, cued and tracking. A key that stops emitting makes the
	# HUD's `.get(k, 0.0)` print a DEFAULTED ZERO as a passed test (`docs/CONVENTIONS.md` §14).
	if not (_n_midkey > 100 and _n_cuekey > 100):
		return (("arm %s: the midcourse keys (%d frames) and the head's cue keys (%d) are ANCHOR-gated " +
				"and must ship on EVERY frame — including after the handover, when the values FREEZE " +
				"rather than vanish. A key that stops emitting reads as a defaulted zero downstream") %
				[tag, _n_midkey, _n_cuekey])
	if blind:
		# ⭐⭐ THE SLIDER'S OWN TRIPWIRE (slice 19's), IN ITS STRONGEST AVAILABLE FORM: the handover
		# error is READ OFF THE WIRE and checked against the measured °/% line, so the arm proves the
		# slider reached THE PHYSICS. A `set_param` that is accepted and never consumed passes a
		# sent-vs-echoed check and fails this one.
		#
		# ⚠⚠ THE PRESS ARM IS EXEMPT, AND THE REASON IT HAD TO BE EXEMPTED IS A FINDING RATHER THAN A
		# LOOPHOLE — this check FAILED it on the file's first run, at 0.0731 °/% against a measured
		# 0.503–0.522. ⭐⭐ **THE HANDOVER ERROR IS NOT A PROPERTY OF THE PICTURE ERROR ALONE; IT IS
		# THE PICTURE ERROR TIMES THE TIME SPENT BLIND.** A belief and the truth start together and
		# separate at a rate the belief error sets, so the angle at handover is set as much by WHEN
		# the receiver opens as by HOW WRONG the picture is. The press arm opens the receiver at
		# 3.2 s instead of 7.26 s and hands over at 1.39° on the identical slider value — a SEVENTH of
		# the angle. The °/% line is therefore a property of THIS engagement's blind duration, and
		# the verdict asserts the press arm's own version of the claim instead.
		if pressed:
			pass
		elif float(arm["err"]) > 0.5:
			var pct: float = 100.0 * float(arm["err"]) / CROSS_SPEED
			var slope: float = _cue_hand / pct
			if slope < SLOPE_LO or slope > SLOPE_HI:
				return (("arm %s: the handover error is %.4f° at %.1f %% of the crossing speed — a " +
						"slope of %.4f °/%%, outside the measured %.2f–%.2f. Either the slider never " +
						"reached the belief or the axis is no longer the one gate 0 measured") %
						[tag, _cue_hand, pct, slope, SLOPE_LO, SLOPE_HI])
		elif _cue_hand > 1.0e-6:
			return (("arm %s: a PERFECT picture must hand over at exactly 0° (got %.6f°) — the belief " +
					"is truth plus an authored error, so a zero error is a zero cue error") %
					[tag, _cue_hand])
		# ⚠⚠ P7's BRACKET, ON EVERY ARM INCLUDING THE BROKEN ONES: *a slider whose top end PINS THE
		# AIRFRAME BEFORE LOCK is a different slice.* Read BEFORE the handover range, the blind
		# command is 3–5 % of `a_max` everywhere and the aero never saturates. ⭐ A whole-flight read
		# of a broken arm shows 22.77 % and 441 saturated ticks — the law's own geometric ceiling,
		# reached long AFTER the handover would have been, a CONSEQUENCE of never acquiring rather
		# than its cause. The two reads are what tell them apart.
		if not (_auth_pre < AUTH_PRE_MAX and _n_aero_pre == 0):
			return (("arm %s: the BLIND command before the handover range must stay under %.0f %% of " +
					"a_max with no aero saturation (got %.2f %%, %d saturated frames) — a midcourse " +
					"that flies itself into the airframe's limit is a different lesson") %
					[tag, 100.0 * AUTH_PRE_MAX, 100.0 * _auth_pre, _n_aero_pre])
		if not (_n_cued > 100 and _act_n > 100):
			return (("arm %s: this wire must actually FLY BLIND (%d cued frames, %d midcourse frames) " +
					"— without a blind phase there is no midcourse and nothing here is measured") %
					[tag, _n_cued, _act_n])
	else:
		# ⚠ THE BUTTON'S ARMS ARE NEVER BLIND, BY CONSTRUCTION — and that is asserted rather than
		# assumed, because it is the premise of the byte-identity claim in the verdict.
		if not (_n_cued == 0 and _act_n == 0 and _cue_hand == 0.0):
			return (("arm %s: with the horizon off the seeker has its target from tick 1, so the head " +
					"is never cued and the midcourse arm is never taken (got %d cued, %d midcourse " +
					"frames, cue %.4f°)") % [tag, _n_cued, _act_n, _cue_hand])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var lo: Dictionary = _res["e38"]
	var hi: Dictionary = _res["cliff"]

	# ⭐⭐⭐ 1. THE CLIFF IS THE WINDOW — the two arms STRADDLE the authored 10.0°, one metre per
	# second apart, and the failure is on the `> fov` side. This is the slice.
	print(("S47V_CLIFF  %.1f m/s -> cue %.4f° (window %.1f°) -> lock %s, miss %.4f m   ||   " +
		   "%.1f m/s -> cue %.4f° -> lock %s, miss %.4f m") %
		  [lo["err"], lo["cue"], WIN_AUTH, _lock_str(lo["tlock"]), lo["miss"],
		   hi["err"], hi["cue"], _lock_str(hi["tlock"]), hi["miss"]])
	if not (float(lo["cue"]) < WIN_AUTH and float(hi["cue"]) > WIN_AUTH):
		return _fail(("the two cliff arms must STRADDLE the authored %.1f° window (%.4f° and %.4f°) " +
					  "— the whole claim is that the crossing and the flip are the SAME EVENT, and " +
					  "if they no longer straddle it, the wire moved and the lesson must be re-read") %
					 [WIN_AUTH, lo["cue"], hi["cue"]])
	if not (float(lo["tlock"]) > 0.0):
		return _fail("the arm INSIDE the window must acquire (lock %s)" % _lock_str(lo["tlock"]))
	if not (float(hi["tlock"]) < 0.0):
		return _fail(("the arm OUTSIDE the window must NEVER acquire (it locked at %.3f s) — a seeker " +
					  "cannot see a target that is outside its detector window at the instant the " +
					  "receiver first hears one, and that is the mechanism this file exists to pin") %
					 hi["tlock"])
	if not (float(lo["miss"]) < HIT_MAX and float(hi["miss"]) > MISS_BROKEN):
		return _fail(("one metre per second of picture error must separate an ARRIVAL from a MISS " +
					  "(%.4f m vs %.4f m)") % [lo["miss"], hi["miss"]])
	print("S47V_CLIFF  ONE m/s of belief error, %.4f° of window, and the engagement flips: %.2f m -> %.1f m" %
		  [float(hi["cue"]) - float(lo["cue"]), lo["miss"], hi["miss"]])

	# ⭐⭐ 2. THE AXIS — the handover error is MONOTONE and essentially LINEAR in the slider, which is
	# what makes this a lesson a student can drag rather than a threshold they can trip over.
	print("S47V_AXIS     err m/s     err %%      cue °    °/%%     lock s      auth %%     hold %%      miss m")
	var prev_cue := -1.0
	var prev_auth := -1.0
	for tg in ["e0", "e10", "e20", "e28", "e34", "e36", "e38"]:
		var a: Dictionary = _res[tg]
		var pct: float = 100.0 * float(a["err"]) / CROSS_SPEED
		print("S47V_AXIS   %9.1f %9.1f %10.4f %6.4f %10s %10.2f %10.2f %11.4f" %
			  [a["err"], pct, a["cue"], (0.0 if pct == 0.0 else float(a["cue"]) / pct),
			   _lock_str(a["tlock"]), 100.0 * float(a["auth"]), a["hold"], a["miss"]])
		if not (float(a["cue"]) > prev_cue):
			return _fail(("the handover error must rise MONOTONICALLY with the picture error " +
						  "(%.4f° at %.1f m/s, after %.4f°) — a non-monotone axis is not a lesson, " +
						  "and this project has disqualified four sliders for exactly that") %
						 [a["cue"], a["err"], prev_cue])
		prev_cue = float(a["cue"])
		# ⭐⭐ AND THE AUTHORITY RISES WITH IT, STRICTLY. This is slice 46's shape reproduced in a new
		# currency: a later/worse handover is paid in the manoeuvre the airframe has left, and it is
		# paid monotonically even where the miss is wandering by 20×.
		if not (float(a["auth"]) > prev_auth):
			return _fail(("the post-lock authority must rise MONOTONICALLY with the picture error " +
						  "(%.4f at %.1f m/s, after %.4f) — this is the column slice 44 did not read, " +
						  "and the reason that component was killed once already") %
						 [a["auth"], a["err"], prev_auth])
		prev_auth = float(a["auth"])
		if not (float(a["hold"]) > HOLD_OK):
			return _fail("arm %s must hold its track once acquired (hold %.2f %%)" % [tg, a["hold"]])
		if not (float(a["miss"]) < HIT_MAX):
			return _fail(("arm %s must HIT (%.4f m) — every arm below the cliff does, which is exactly " +
						  "why the miss cannot be this slice's metric") % [tg, a["miss"]])

	# ⭐ 3. THE ENDS OF THE AXIS, EACH ASSERTED FOR ITS OWN REASON.
	var perfect: Dictionary = _res["e0"]
	if not (float(perfect["auth"]) < AUTH_FREE_MAX):
		return _fail(("a PERFECT picture must hand over into a CRUISE (%.4f of a_max) — that is the " +
					  "baseline the disease is measured against") % perfect["auth"])
	# ⚠⚠ AND THE BOTTOM OF THE SLIDER IS NOT A NULL, WHICH IS THIS SLICE'S DIFFERENCE FROM 46's. The
	# midcourse still FLIES at zero error — it corrects the authored launch heading onto the collision
	# course — and the arm that IS a null (no midcourse at all: 1203.7 m, never acquires) is a claim
	# about the WIRE, pinned in `test_missile.jl`. Without a commanding null arm this showcase would
	# be measuring the launch heading's luck, which is how slices 44 and 45 died.
	if not (float(perfect["act"]) > 100 and float(perfect["auth_pre"]) > 0.005):
		return _fail(("the perfect-picture arm must still COMMAND while blind (%d midcourse frames, " +
					  "%.4f of a_max) — if doing nothing were already right, this scenario would be " +
					  "measuring the launch heading rather than the midcourse") %
					 [perfect["act"], perfect["auth_pre"]])
	if not (float(lo["auth"]) > AUTH_DEF_MIN):
		return _fail(("the AUTHORED default must open on the disease (%.4f of a_max) — one notch below " +
					  "the cliff, already spending several times the perfect arm's budget, and " +
					  "nothing on screen looking wrong") % lo["auth"])
	var top: Dictionary = _res["top"]
	if not (float(top["tlock"]) < 0.0 and float(top["miss"]) > MISS_BROKEN):
		return _fail(("the TOP of the slider must be deep in the broken region (lock %s, miss %.2f m) " +
					  "— a slider whose upper half never fails has a decorative upper half") %
					 [_lock_str(top["tlock"]), top["miss"]])

	# ⭐⭐⭐ 4. THE TWO FORBIDDEN GAUGES, ASSERTED FORBIDDEN.
	# (a) THE MISS carries NO SIGNAL along the same rows where the authority rises strictly.
	var misses: Array = []
	for tg in ["e0", "e10", "e20", "e28", "e34", "e36", "e38"]:
		misses.append(float(_res[tg]["miss"]))
	var ups := 0
	var downs := 0
	for i in range(1, misses.size()):
		if misses[i] > misses[i - 1]:
			ups += 1
		elif misses[i] < misses[i - 1]:
			downs += 1
	print("S47V_NOISE  miss along the axis: %s  (%d up, %d down) while the authority rose strictly" %
		  [str(misses), ups, downs])
	if not (ups > 0 and downs > 0):
		return _fail(("the miss must be NON-MONOTONE along an axis whose handover error and authority " +
					  "both rise strictly (%s) — this file asserts that the headline metric carries no " +
					  "signal here, and a monotone miss would mean it does") % str(misses))
	# (b) ⚠⚠ `gimbal_fov_margin_deg` — AND THIS FILE **RETRACTS §3.2's SECOND BAN**, which is a
	# correction to the plan rather than a finding about the wire, and it took two wrong assertions
	# here to arrive at. §3.2 forbade the angle margin as a gauge on gate-0 P6b's finding that it
	# IMPROVES monotonically across the interval where the engagement is lost — "a gauge that reads
	# better while the engagement is being lost". On the SHIPPED wire it does no such thing, in
	# either sampling a HUD author might use:
	#     at handover   9.9932° (perfect)  →  −2.9281° (broken)
	#     post-lock     9.5682° (4.1 %)    →   1.6764° (27.1 %)
	# Both separate the ends of the slider cleanly and in the right direction. P6b measured its
	# inversion on the sweep §4.4 itself flagged as CONFOUNDED, and the claim did not survive contact
	# with the wire it was written about.
	#
	# ⭐⭐ AND THE REASON IT DOES NOT INVERT IS WORTH MORE THAN THE BAN WAS: **AT THE HANDOVER
	# INSTANT THE MARGIN AND THE CUE ERROR ARE THE SAME MEASUREMENT.** While the head is CUED **and has
	# SETTLED on its cue**, its BORESIGHT error against the truth LOS *is* the cue error, so
	# `margin = fov − cue` — asserted below to half a degree on both ends of the domain.
	# ⚠⚠ SERVO-CONTINGENT, NOT DEFINITIONAL: `off_head` is boresight-vs-truth and the cue error is
	# COMMAND-vs-truth, so they coincide only once the servo has caught up. True here because it is
	# authored at 240 °/s as slice 46's measured isolation — and the ~0.12° that sits inside the 0.5°
	# tolerance below IS that lag, not slack. On slice 35's 8 °/s wire the two would separate, and the
	# tolerance is the only thing standing between this claim and a wire that does not hold it. The margin is therefore not a rival
	# gauge to be banned but this slice's own headline in the window's units. ⇒ IT STAYS OFF THE HUD
	# FOR A DIFFERENT REASON — REDUNDANCY, NOT DECEPTION (convention 9: one lesson, one gauge) — and
	# §3.2's stated reason must not be quoted again.
	var marg_lo: float = float(perfect["marg_post"])
	var marg_hi: float = float(lo["marg_post"])
	var auth_x: float = float(lo["auth"]) / maxf(float(perfect["auth"]), 1.0e-9)
	print(("S47V_MARGIN at handover %.4f° (perfect) -> %.4f° (broken);  post-lock %.4f° at %.1f%% of " +
		   "a_max -> %.4f° at %.1f%% (a %.1fx swing) — it SEPARATES in both, so §3.2's ban is RETRACTED") %
		  [perfect["marg"], top["marg"], marg_lo, 100.0 * float(perfect["auth"]),
		   marg_hi, 100.0 * float(lo["auth"]), auth_x])
	# THE IDENTITY, which is what the retraction rests on: `margin + cue = fov` at the handover
	# instant, on the arm that hits AND on the arm that never acquires.
	for tg in ["e0", "e38", "cliff", "top"]:
		var a: Dictionary = _res[tg]
		var sum_deg: float = float(a["marg"]) + float(a["cue"])
		if absf(sum_deg - WIN_AUTH) > 0.5:
			return _fail(("arm %s: at handover the angle margin and the cue error must be the SAME " +
						  "measurement in opposite directions — %.4f° + %.4f° should be the %.1f° " +
						  "window, and it is %.4f°. If this identity breaks, the two are measuring " +
						  "different things and §3.2's retracted ban has to be re-argued from scratch") %
						 [tg, a["marg"], a["cue"], WIN_AUTH, sum_deg])
	print("S47V_MARGIN margin + cue = the window on all four arms (to 0.5°) — one measurement, two names")
	if not (float(top["marg"]) < 0.0 and float(perfect["marg"]) > 0.0):
		return _fail(("at the handover instant the margin must be POSITIVE on the perfect arm " +
					  "(%.4f°) and NEGATIVE on the broken one (%.4f°) — the sign is the verdict, and it " +
					  "is the same verdict the cue error gives") % [perfect["marg"], top["marg"]])

	# ⭐⭐ 5. THE BUTTON — AND IT IS A BYTE-IDENTITY CLAIM. With the horizon off there is no blind
	# phase, so the picture error is read by nothing at all: two arms at opposite ends of the slider's
	# domain must be BIT-IDENTICAL. *The picture only matters because you are blind*, as `max|Δpos|`.
	var d_off: float = _max_pos_diff(_res["off_lo"]["pos"], _res["off_hi"]["pos"])
	print("S47V_BUTTON horizon OFF: err %.0f vs %.0f m/s -> max|Δpos| = %.12f m over %d frames (lock %s / %s)" %
		  [ERR_PERFECT, ERR_TOP, d_off, _res["off_lo"]["pos"].size(),
		   _lock_str(_res["off_lo"]["tlock"]), _lock_str(_res["off_hi"]["tlock"])])
	if not (d_off <= EXACT):
		return _fail(("with the horizon off the slider must do NOTHING (max|Δpos| = %.12f m over the " +
					  "whole domain) — the midcourse is presence-gated on being blind, and a wire " +
					  "where the picture error leaks into a seeing missile is a wire with a second, " +
					  "unnamed path into the guidance") % d_off)
	if not (float(_res["off_lo"]["tlock"]) >= 0.0 and float(_res["off_lo"]["tlock"]) < 0.10):
		return _fail(("with the horizon off the seeker must have the target from the first frames " +
					  "(%.3f s) — that is what an angle-only seeker means, and it is why the picture " +
					  "stops mattering") % _res["off_lo"]["tlock"])

	# ⭐ 6. DETERMINISM — the master check (convention 2).
	var d_rep: float = _max_pos_diff(_res["e38"]["pos"], _res["replay"]["pos"])
	print("S47V_REPLAY e38 max|Δpos| = %.12f m over %d frames" % [d_rep, _res["e38"]["pos"].size()])
	if not (d_rep <= EXACT):
		return _fail("replay of e38 differs by %.12f m — determinism is the master check" % d_rep)

	# ⭐ 7. THE MID-RUN PRESS — the horizon removed at 3.2 s, WHILE THE MISSILE IS STILL BLIND and
	# flying its (wrong) picture. It must acquire essentially at once: the belief-cued head has been
	# pointing within the window the whole time and only the RANGE half was refusing it. ⚠ This is
	# also the only place a `set_fidelity` is proven to reach this rung with the midcourse arm LIVE.
	var mp: Dictionary = _res["midpress"]
	print("S47V_MIDPRESS press at %.3f s -> lock at %s (the same wire unpressed hands over at %s)" %
		  [PRESS_AT * _dt, _lock_str(mp["tlock"]), _lock_str(lo["tlock"])])
	if not (mp["cued"] > 100 and float(mp["tlock"]) >= PRESS_AT * _dt - 0.05
			and float(mp["tlock"]) <= PRESS_AT * _dt + 0.05):
		return _fail(("the mid-run press must acquire within a frame or two of itself (press %.3f s, " +
					  "lock %s, %d cued frames before it) — the cued head was inside the window the " +
					  "whole time and only the RANGE half was refusing it") %
					 [PRESS_AT * _dt, _lock_str(mp["tlock"]), mp["cued"]])
	# ⭐⭐⭐ AND THE PRESS ARM CARRIES A LESSON THE LADDER CANNOT: **THE HANDOVER ERROR IS THE PICTURE
	# ERROR TIMES THE TIME SPENT BLIND.** Identical slider value, identical belief, identical
	# trajectory up to the press — and a handover error a SEVENTH the size, because the belief and
	# the truth have had a third of the time to separate. This is what the ladder's tidy °/% line
	# hides: that number is a property of THIS engagement's blind duration and not of the picture.
	# ⇒ a midcourse's error budget cannot be specified in metres per second alone; it has to be
	# specified against a handover RANGE. (This check exists because the slope tripwire above FAILED
	# this arm on the file's first run — the failure was right and the tripwire's scope was wrong.)
	print("S47V_DURATION same %.0f m/s of picture error: blind to %.3f s -> %.4f°, blind to %s -> %.4f°" %
		  [lo["err"], mp["tlock"], mp["cue"], _lock_str(lo["tlock"]), lo["cue"]])
	if not (float(mp["cue"]) < 0.5 * float(lo["cue"])):
		return _fail(("the same picture error handed over EARLY must give a much smaller angle " +
					  "(%.4f° at %.3f s against %.4f° at %s) — if it does not, the handover error is " +
					  "not accumulating with time and the mechanism is not the one this slice claims") %
					 [mp["cue"], mp["tlock"], lo["cue"], _lock_str(lo["tlock"])])

	# ⭐⭐ 8. THE LATCH ITSELF — the key this file's degrees are read from, proven to FREEZE rather
	# than to track. `head_cue_err_deg` goes to 0.0 the moment the head tracks (a tracking head has no
	# cue); the latched key must hold its last blind value for the rest of the flight. Without this,
	# every number above would have been sampled off a 16-tick grid that never lands on the handover.
	print("S47V_LATCH  e38: latched %.4f° held to the end of the flight; live cue peaked at %.4f°" %
		  [lo["cue"], lo["cue_live"]])
	if not (absf(float(lo["cue"]) - float(lo["cue_live"])) < 0.05):
		return _fail(("the LATCHED handover error (%.4f°) must be the peak of the live cue error " +
					  "(%.4f°) — they part company only if the latch is tracking something else, and " +
					  "every degree in this file is read off the latch") % [lo["cue"], lo["cue_live"]])

	print("S47V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice47_midcourse":
		return "wrong scenario '%s' — run scenarios/slice47_midcourse.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER, AND IT IS RAISED **BESIDE** SLICE 46's RATHER THAN INSTEAD OF IT. This is 46's
	# wire with a blind phase in front, so its `seeker_detect` button is still the sharpest A/B the
	# slice has — press it and the picture error stops mattering at all. Two markers is what buys
	# both: 47's HUD and 46's button.
	if not bool(f.get("midcourse_view", false)):
		return ("a slice-47 handshake must ship midcourse_view=true — without it the client draws " +
				"slice 46's HUD over a missile that is flying a belief it never mentions, and the " +
				"one number that carries the lesson never reaches the screen")
	if not bool(f.get("seeker_detect_view", false)):
		return ("a slice-47 wire IS a slice-46 wire, so it must still raise seeker_detect_view — the " +
				"blind phase exists BECAUSE of the horizon, and the button that removes it is this " +
				"slice's own control")
	for k in ["gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-47 wire is a gimballed, rate-limited head plus a link budget plus a " +
					"midcourse, so it must still raise %s — the superset relation is what makes the " +
					"new marker a BRANCH SELECTOR rather than a hole plug") % k
	# ⚠ AND THE SAME THREE MUST BE ABSENT AS IN 46, for the same reasons: no glass on this wire, no
	# body-fixed window, and no `head_servo`/`seeker_head` rung to steal the shared button.
	for k in ["radome_view", "seeker_fov_view", "gimbal_servo_view", "gimbal_frame_view"]:
		if bool(f.get(k, false)):
			return ("a slice-47 wire must NOT raise %s — it would either put a second mechanism beside " +
					"this lesson or point the shared button at another slice's rung") % k
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "midcourse_err_gain":
		return ("exactly ONE knob, the MISSILE's `midcourse_err_gain` (convention 9). `midcourse_k` is " +
				"AUTHORED (gate 1 measured it); `rcs_m2` is slice 46's axis and would move the horizon " +
				"under this lesson; `gimbal_fov_deg` moves the window and the horizon in opposite " +
				"directions; and the two belief-error VECTORS are refused at load BY TYPE, because " +
				"`set_param` carries one Float64 and the next `::Vec3` assertion would throw in-tick")
	if not (float(kn[0].get("min", -1.0)) == 0.0 and float(kn[0].get("max", 0.0)) == ERR_TOP):
		return (("the slider must span %.1f–%.1f m/s: the floor is the PERFECT picture (not a null — " +
				 "the midcourse still flies there) and the ceiling is %.0f %% of the crossing speed, " +
				 "a full %.0f m/s past the cliff so the broken region is a REGION") %
				[ERR_PERFECT, ERR_TOP, 100.0 * ERR_TOP / CROSS_SPEED, ERR_TOP - ERR_CLIFF])
	if bool(kn[0].get("log", false)):
		return ("the slider must be LINEAR — gate-0 P1 measured the handover error growing 0.503 → " +
				"0.522° per %% across the whole domain, so every part of the travel is worth the same, " +
				"which is exactly when a log slider is wrong")
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _n_post = 0; _n_held = 0; _t_lock = -1.0
	_auth_peak = 0.0; _auth_pre = 0.0; _n_aero_pre = 0; _n_sat = 0
	_n_cued = 0; _cue_hand = 0.0; _cue_live_max = 0.0; _marg_at_hand = 0.0
	_marg_post = 1.0e30
	_pip_err = 0.0; _act_n = 0; _n_midkey = 0; _n_cuekey = 0
	_win_seen = 0.0; _stop_seen = 0.0; _rate_seen = 0.0
	_pos_trace.clear()

func _drain_scan() -> bool:
	while true:
		var f := _take("state")
		if f.is_empty():
			return false
		_scan(f)
		if float(f.get("t", 0.0)) >= _t_target - 1.0e-9:
			return true
	return false

func _scan(f: Dictionary) -> void:
	var tel: Dictionary = f.get("telemetry", {})
	# ⚠ `entities` IS AN ARRAY OF RECORDS, not a dictionary keyed by id (the wire's own shape — see
	# `SimClient.gd` and every prior verifier). Reading it as a dictionary parses fine and fails at
	# RUNTIME, on every frame, which is the loudest possible version of a quiet mistake.
	var mp: Array = _missile_pos(f)
	if mp.is_empty():
		return
	_pos_trace.append(mp)
	var t := float(f.get("t", 0.0))
	var los := float(tel.get(MID + ".los_range", 1.0e30))
	# ⚠ FIRST-DESCENDING-BAND ONLY ([[ewsim-missile-verifier-sampling]]): once the range turns, the
	# post-CPA re-crossings are a different engagement.
	if _closing:
		if los > _prev_los and _prev_los < 1.0e29:
			_closing = false
			_turned = true
		else:
			_min_los = minf(_min_los, los)
	_prev_los = los
	if not _closing:
		return
	_win_seen = float(tel.get(MID + ".gimbal_fov_deg", _win_seen))
	_stop_seen = float(tel.get(MID + ".gimbal_stop_deg", _stop_seen))
	_rate_seen = float(tel.get(MID + ".gimbal_rate_dps", _rate_seen))
	if tel.has(MID + ".midcourse_active"):
		_n_midkey += 1
		if float(tel[MID + ".midcourse_active"]) >= 0.5:
			_act_n += 1
			_pip_err = float(tel.get(MID + ".midcourse_pip_err_m", _pip_err))
	# ⭐⭐⭐ THE HANDOVER ERROR, READ FROM THE **LATCHED** KEY. It tracks the live cue while the head
	# is cued and then FREEZES at the value it held on the last blind tick — the instant the receiver
	# first heard something — so any frame after that carries it exactly. `head_cue_err_deg` beside it
	# is the instantaneous one and reads 0.0 the moment the head tracks, which is honest and useless
	# to a client sampling one frame in 16.
	if tel.has(MID + ".head_cue_err_handover_deg"):
		_n_cuekey += 1
		_cue_hand = float(tel[MID + ".head_cue_err_handover_deg"])
	if float(tel.get(MID + ".head_cued", 0.0)) >= 0.5:
		_n_cued += 1
		_cue_live_max = maxf(_cue_live_max, float(tel.get(MID + ".head_cue_err_deg", 0.0)))
		# ⚠ THE FORBIDDEN GAUGE, SAMPLED ON THE LAST CUED FRAME so it can be asserted forbidden in
		# the verdict. It is NOT a column this file trusts — it is a column this file DISPROVES.
		_marg_at_hand = float(tel.get(MID + ".gimbal_fov_margin_deg", _marg_at_hand))
	if los > 200.0:
		_n_gate += 1
		var avail := float(tel.get(MID + ".gimbal_valid", 1.0)) >= 0.5
		if avail and _t_lock < 0.0:
			_t_lock = t
		if _t_lock >= 0.0:
			_n_post += 1
			if avail:
				_n_held += 1
			# ⚠ THE PEAK IS TAKEN AFTER THE HANDOVER ONLY, and the r → 0 endgame is excluded by the
			# 200 m gate ([[ewsim-missile-verifier-sampling]]).
			_auth_peak = maxf(_auth_peak, float(tel.get(MID + ".a_cmd_frac", 0.0)))
			# ⚠⚠ THE FORBIDDEN GAUGE, IN THE SAMPLING WHERE IT IS ACTUALLY FORBIDDEN — see §4(b).
			_marg_post = minf(_marg_post, float(tel.get(MID + ".gimbal_fov_margin_deg", 1.0e30)))
		# ⚠⚠ P7's BRACKET — the BLIND command read BEFORE the handover range. This is what separates
		# "the midcourse flew itself into saturation" (a different slice) from "it kept flying
		# midcourse because it never acquired" (this slice's failure mode), and on a broken arm the
		# two reads differ by 5×.
		if los > R_HANDOVER and float(tel.get(MID + ".midcourse_active", 0.0)) >= 0.5:
			_auth_pre = maxf(_auth_pre, float(tel.get(MID + ".a_cmd_frac", 0.0)))
			if float(tel.get(MID + ".aero_sat", 0.0)) >= 0.5:
				_n_aero_pre += 1
		if float(tel.get(MID + ".head_rate_sat", 0.0)) >= 0.5:
			_n_sat += 1

func _lock_str(tl: float) -> String:
	return "NEVER" if tl < 0.0 else "%.3f s" % tl

func _missile_pos(f: Dictionary) -> Array:
	for e in f.get("entities", []):
		if str(e.get("id", "")) == MID:
			var p: Array = e.get("pos", [])
			if p.size() >= 3:
				return [float(p[0]), float(p[1]), float(p[2])]
	return []

func _max_pos_diff(a: Array, b: Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n == 0:
		return INF
	var d := 0.0
	for i in range(n):
		var p: Array = a[i]
		var q: Array = b[i]
		d = maxf(d, sqrt(pow(p[0] - q[0], 2.0) + pow(p[1] - q[1], 2.0) + pow(p[2] - q[2], 2.0)))
	return d

# ⚠ THE FIELD IS `target`, NOT `entity` — slice 40's own first-run bug. ⚠⚠ AND THE TARGET HERE IS THE
# **MISSILE**, not the target entity: slice 46's slider lived on `tgt1` (the target's own RCS) and
# this one lives on `m1` (the missile's belief about the target). Copying 46's call site verbatim
# sends a knob the server refuses BY NAME, which is at least a loud failure — but the reverse (a key
# that happens to exist on both) would not be.
func _set_param_cmd(target: String, key: String, v: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": v}

func _take(kind: String) -> Dictionary:
	for i in range(_inbox.size()):
		if str(_inbox[i].get("type", "")) == kind:
			var f: Dictionary = _inbox[i]
			_inbox.remove_at(i)
			return f
	return {}

func _tag() -> String:
	return "?" if _idx < 0 or _idx >= _arms.size() else str(_arms[_idx]["tag"])

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _fail(msg: String, code: int = 1) -> bool:
	push_error("S47V FAIL: " + msg)
	print("S47V FAIL: ", msg)
	quit(code)
	return true
