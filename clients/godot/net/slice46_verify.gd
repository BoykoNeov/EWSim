extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-46 gate-3 verifier — THE SEEKER'S DETECTION HORIZON.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice46_horizon.yaml
#   godot --headless --path clients/godot --script res://net/slice46_verify.gd     (exit 0 = pass)
#
# THE LESSON. Slices 32/34 modelled "can the seeker see it?" as an ANGLE question alone: inside the
# detector window there is a measurement, outside it there is none, at ANY range. This wire gives the
# seeker a LINK BUDGET, so there is a RANGE past which the echo is under the receiver's threshold and
# there is no measurement AT WHATEVER ANGLE — and the two halves are ONE design variable pulling
# opposite ways, because the window IS the beamwidth that implies the aperture that sets the reach.
#
# ⭐⭐⭐ AND THE ASSERTION THIS FILE EXISTS TO MAKE IS ABOUT THE **AUTHORITY**, NOT THE MISS. Slice 44
# built this physics at gate 0, read MISS across the whole free interval (0.2237 / 0.3491 / 0.3267 /
# 0.2514 m — flat), concluded a delayed acquisition was free, and KILLED THE COMPONENT. ⇒ this
# file's columns are `auth_peak` and `hold%`, and the miss appears only as a sanity bound on arms
# that hold their track. ⚠⚠ IT GOES FURTHER AND ASSERTS THE MISS IS **NON-MONOTONE** ALONG A LADDER
# WHOSE LOCK INSTANT AND AUTHORITY BOTH RISE STRICTLY: 0.2237 → 0.2783 → 0.0858 → 0.1167 → 0.0453 →
# 0.9874 m, up and down by 20× while the delay only grows. A verifier built on the headline metric
# would not merely miss this lesson, it would read NOISE.
#
# ⚠⚠ TWO CORRECTIONS THIS FILE FOUND IN ITS OWN FIRST RUN, both now in the scenario header:
#   (1) SLICE 44 §VII.1's "100.00 % of `a_max`" IS AN r → 0 ENDGAME READ. Gated at r > 200 m the
#       same cell spends 10.45 % and the free arm 3.10 %. The endgame spikes every guidance quantity
#       ([[ewsim-missile-verifier-sampling]], in a NEW quantity) ⇒ `_auth_peak` here is taken INSIDE
#       the 200 m gate. ⭐ The effect survives and is cleaner: gated, it is strictly monotone.
#   (2) THE SERVO WAS NOT ISOLATED AT THE 30 °/s FIRST AUTHORED — slice 35's rate limit still bound
#       205 frames, all of them on the ACQUISITION SLEW at the moment of lock. The wire now authors
#       240 °/s, at which `head_rate_sat` is 0 on EVERY arm and every other number is unchanged to
#       four decimals (measured at 60 / 120 / 240). The isolation is free, which is what licenses it.
#
# ⚠ THE SERVO IS THE MEASURED ISOLATION, NOT A PREFERENCE (slice 44 §VII.2). At the arc's shipped
# 8 °/s the bottom of this slider breaks for SLICE 35's reason (hold 15.4 % at 0.002 m²) from lock
# instants IDENTICAL to the fast-servo arms', because the servo changes nothing about ACQUIRING and
# everything about KEEPING. Every arm here asserts `head_rate_sat == 0`, so slice 35's limit is
# provably outside every verdict below — see correction (2) above for what that cost.
#
# ⚠ THE SLIDER'S OWN TRIPWIRE IS `seeker_r_acq_m`, NOT THE SENT VALUE (slice 19's discipline, in its
# strongest available form): the horizon is READ OFF THE WIRE and checked against `R₀·σ^¼`, so the
# arm proves the slider reached THE PHYSICS rather than merely being accepted by the server.
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`) and every constant is sized off a FRAME column
# ([[ewsim-missile-verifier-sampling]] — the error is ASYMMETRIC: a MISS samples faithfully, a HIT
# samples COARSELY). Lock instants are therefore quoted to ±1 frame (16 ms) and asserted with that
# tolerance, never to the millisecond the core knows them to.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — the seeker, the head and the budget live here
const TID := "tgt1"               # the target — the ONE slider (`rcs_m2`) lives here

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16). The server emits every 16th tick,
# so a STEPS that is not a multiple makes the last frame land BELOW `STEPS*dt` and `_drain_scan` waits
# forever, SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 9600 = 16 * 600,
# and the engagement reaches CPA at ~8.9 s. ⚠ EVERY arm asserts it REACHED CPA rather than trusting it.
const STEPS := 9600
const PRESS_AT := 3200            # the MID-RUN press tick — a multiple of 16, and BEFORE the 6.96 s
                                  # lock, so the press is what acquires

const RUNG_ON := "snr"            # the AUTHORED rung — the showcase opens on the disease
const RUNG_OFF := "none"          # slices 11–45's angle-only seeker

# THE SLIDER — the TARGET's radar cross-section, in m². The DEFAULT is the LAST cell that still hits
# cleanly (0.99 m) while already spending 7.6× the authority of a seeker with no horizon at all:
# nothing on screen looks wrong until you read the gauge.
const RCS_DEF := 0.001
const RCS_TOP := 1.0              # the domain CEILING — where the COMPONENT STOPS EXISTING
const RCS_01 := 0.1
const RCS_001 := 0.01
const RCS_0001 := 0.001
const RCS_00005 := 0.0005   # the CLIFF — the first cell that spends the whole budget
const RCS_FLOOR := 0.0001         # the domain FLOOR — deep in the broken region

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const WIN_AUTH := 10.0            # the detector window — ⚠ TWO-SIDED here for the first time in this
                                  # arc: widening it shrinks the horizon one-for-one
const STOP_AUTH := 30.0
const RATE_AUTH := 240.0          # slice 35's servo, authored FAST as the MEASURED isolation — at
                                  # 30 it still bound 205 frames on the acquisition slew, and at
                                  # 60/120/240 nothing else moves to four decimals

# ⭐ THE APERTURE IDENTITY, as one number: `R_acq · fov` for this authored Ku-band seeker. Measured
# on the flying wire at 80789.2051 m·deg over a 4× window range (0.0000 %), and it is the constant
# that makes coverage and reach one variable. ⚠ Checked at the authored window only — `gimbal_fov_deg`
# is not a knob here (a slider on it would show a NON-MONOTONE composite and reverse the lesson).
const R_FOV_CONST := 80789.2051
const R0_AT_1M2 := 8078.9205      # the horizon against a 1 m² target at this window
const LAUNCH_R := 6436.7          # the engagement's own range at t = 0 — the number that decides
                                  # whether this component can price anything at all

# ⚠ SIZED OFF A **FRAME** COLUMN, NOT THE CORE'S OWN MISS ([[ewsim-missile-verifier-sampling]]: a
# HIT samples COARSELY). The core's 0.9874 m default arm reads ~5.05 m through the 16-tick emit grid,
# so a bound sized on the core's number would fail a green run.
const HIT_MAX := 25.0             # a HIT, on arms that hold — a sanity bound, never the lesson
const HOLD_OK := 99.0             # % of post-lock frames with the target available
const HOLD_BROKEN := 70.0         # the FLOOR arm must be under this — a VERDICT, not metres
const AUTH_SPENT := 0.999         # "every last percent of the airframe"
const AUTH_FREE := 0.05           # the no-horizon arm's cruising spend, GATED (measured 0.031)
const AUTH_RATIO := 5.0           # the default arm must spend this many times the free arm's budget
const RACQ_RTOL := 1.0e-4         # the σ^¼ law, read off the wire
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
var _t_valid := -1.0              # the ACQUISITION instant, frame-sampled
var _r_valid := 0.0               # …and the range there
var _auth_peak := 0.0             # ⭐ THE COLUMN THIS FILE IS ABOUT
var _n_sat := 0                   # slice 35's rate limit — the isolation, must stay 0
var _n_blind := 0                 # frames with the RANGE lamp out
var _racq_seen := 0.0
var _marg_seen := 1.0e30          # the SIGNED range margin at its most negative
var _ap_seen := 0.0
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _n_authkey := 0               # frames carrying `a_cmd_frac` — it must ship on BOTH rungs
var _n_racqkey := 0               # frames carrying `seeker_r_acq_m` — rung-gated, never-stale
var _pos_trace: Array = []

func _initialize() -> void:
	print("S46V_INIT godot=", Engine.get_version_info().string)
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
	# 1) ⭐⭐ THE SHOWCASE — the wire as authored (a seeker that must FIND its target), the BUTTON (a
	#    seeker that simply has it), and a REPLAY of each. Class 4c: no RNG is added by this slice,
	#    but the seed is load-bearing for the seeker noise the whole family carries.
	_arms.append({"tag": "open", "rcs": RCS_DEF})
	_arms.append({"tag": "replay", "rcs": RCS_DEF})
	_arms.append({"tag": "button", "rcs": RCS_DEF, "rung": RUNG_OFF})
	_arms.append({"tag": "button_rep", "rcs": RCS_DEF, "rung": RUNG_OFF})
	# 2) ⭐ THE LADDER over the slider's whole domain, top to bottom. These establish the σ^¼ law, the
	#    MONOTONICITY of the lock instant, and the walk of the authority gauge from cruising to spent.
	#    ⚠ The TOP of the ladder is the NULL: at 1 m² the horizon is outside the engagement and the
	#    component does not exist there. Shipping that as an arm is the honesty this slice was
	#    re-verdicted for (`docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT").
	for rv in [RCS_TOP, RCS_01, RCS_001, RCS_00005, RCS_FLOOR]:
		_arms.append({"tag": "r%d" % int(round(1.0e6 * rv)), "rcs": rv})
	# 3) ⭐ THE PRESS ITSELF, MID-FLIGHT, BEFORE THE LOCK — the one thing gates 1–2 could not cover is
	#    a `set_fidelity` reaching this rung at an arbitrary tick with the tracker still uninitialised.
	#    It must acquire IMMEDIATELY: turning the horizon off cannot un-see a target that is inside the
	#    window, and the availability verdict is re-formed every tick.
	_arms.append({"tag": "midpress", "rcs": RCS_DEF, "press": RUNG_OFF})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `snr` and the slider to its
	# authored 0.005 every arm — each arm must re-send its own. That is what makes these arms the
	# CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", RUNG_ON)) != RUNG_ON:
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": str(arm["rung"])})
	# ⚠ SENT ON EVERY ARM INCLUDING THE DEFAULT ONE, so the `open` arm proves the SLIDER's own path to
	# its authored value rather than merely inheriting it from the YAML.
	_client.send(_set_param_cmd(TID, "rcs_m2", float(arm["rcs"])))
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
	var gated: bool = str(arm.get("rung", RUNG_ON)) == RUNG_ON and not arm.has("press")
	# ⚠⚠ NaN, NOT 0.0, WHEN THERE ARE NO POST-LOCK FRAMES — slice 33's gate-2 finding, inherited: a
	# `sum/max(n,1)` would print a beautifully perfect `hold = 100.00 %` COMPUTED FROM ZERO SAMPLES.
	var hold := NAN if _n_post == 0 else 100.0 * float(_n_held) / float(_n_post)
	var m := {
		"miss": _min_los, "turned": _turned, "gate": _n_gate, "hold": hold,
		"tlock": _t_valid, "rlock": _r_valid, "auth": _auth_peak, "sat": _n_sat,
		"racq": _racq_seen, "marg": NAN if _marg_seen > 1.0e29 else _marg_seen,
		"ap": _ap_seen, "blind": _n_blind, "rcs": float(arm["rcs"]), "gated": gated,
		"win": _win_seen, "stop": _stop_seen, "rate": _rate_seen,
		"authkey": _n_authkey, "racqkey": _n_racqkey,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S46V_ARM   %-10s rcs=%.6f rung=%-4s  ->  R_acq=%.1f m  lock=%.3f s @ %.0f m  " +
		   "auth_peak=%.1f%%  hold=%.2f%%  miss=%.4f  blind_frames=%d  sat=%d  cpa=%s") %
		  [tag, m["rcs"], RUNG_ON if gated else RUNG_OFF, m["racq"], m["tlock"], m["rlock"],
		   100.0 * m["auth"], m["hold"], m["miss"], m["blind"], m["sat"], "Y" if m["turned"] else "N"])
	if not (_n_gate > 100):
		return "arm %s: the r > 200 m window must contain frames to measure (got %d)" % [tag, _n_gate]
	if not _turned:
		return (("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing " +
				"at the end, so its miss (%.3f m) is a last closing range and not a CPA") %
				[tag, STEPS, _min_los])
	if not (_t_valid >= 0.0):
		return (("arm %s: the seeker never became available at all — every arm in this domain " +
				"ACQUIRES, and one that does not has left the regime this file measures") % tag)
	# ⭐ THE NOT-A-DEAD-KNOB TRIPWIRE (slice 19's), IN ITS STRONGEST AVAILABLE FORM: the horizon is
	# read off the WIRE and checked against the σ^¼ law, so the arm proves the slider reached THE
	# PHYSICS. A `set_param` that is accepted and never consumed passes a sent-vs-echoed check and
	# fails this one.
	if gated:
		var expect: float = R0_AT_1M2 * pow(float(arm["rcs"]), 0.25)
		if absf(_racq_seen - expect) > RACQ_RTOL * expect:
			return (("arm %s: the wire flew a horizon of %.3f m but rcs = %.6f implies %.3f m " +
					"(R ∝ σ^¼) — the slider was accepted and not applied to the link budget") %
					[tag, _racq_seen, float(arm["rcs"]), expect])
	# ⚠⚠ SLICE 35's RATE LIMIT MUST NEVER BIND, ON ANY ARM — the load-bearing precondition of the
	# whole file rather than hygiene, and the assertion that FAILED on this file's first run and moved
	# the wire. Slice 44 §VII.2 measured that the acquisition failures of 32/34 were the SERVO's, not
	# the window's: at 8 °/s these same arms collapse (hold 15 %) and at 30 they hit, from IDENTICAL
	# lock instants — but at 30 the limit still binds 205 frames on the ACQUISITION SLEW itself. The
	# wire authors 240 precisely so this stays 0 on every arm INCLUDING the broken ones, which is what
	# lets the floor arm's track loss be attributed to the range gate rather than to a head chasing a
	# runaway LOS.
	if not (_n_sat == 0):
		return (("arm %s: slice 35's rate limit bound on %d frames — this file would then be measuring " +
				"THAT limit. The servo is authored at %.0f °/s exactly so it cannot") %
				[tag, _n_sat, RATE_AUTH])
	# THE AUTHORED THREE, ON EVERY ARM: nothing in this file touches them, and that is the point.
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH):
		return (("arm %s: the window / stop / servo must be the AUTHORED %.1f / %.1f / %.1f " +
				"(got %.3f / %.3f / %.3f)") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, _win_seen, _stop_seen, _rate_seen])
	# ⭐ THE AUTHORITY GAUGE SHIPS ON **BOTH** RUNGS AND THE HORIZON'S OWN KEYS SHIP ON NEITHER WHEN
	# THE RUNG IS OFF — the never-stale discipline (34/38) and slice 40's both-rungs readout rule, in
	# one check. A rung-gated gauge would go blank on exactly the arm the showcase compares against.
	if not (_n_authkey > 100):
		return (("arm %s: `a_cmd_frac` must ship on EVERY frame of BOTH rungs (got %d) — the whole " +
				"showcase is a comparison across the button, and a gauge that vanishes there cannot " +
				"make it") % [tag, _n_authkey])
	if gated and not (_n_racqkey > 100):
		return "arm %s: the horizon's own keys must ship while the rung is on (got %d)" % [tag, _n_racqkey]
	# ⚠ THE PRESS ARM IS EXEMPT FROM THE ABSENCE HALF, AND THAT IS NOT A LOOPHOLE: it flies the
	# FIRST 3.2 s WITH the rung on, so it MUST carry the keys over that stretch and lose them after.
	# Asserting absence over a run that was gated for a third of its length would be asserting that a
	# cross-toggle retroactively rewrites the frames before it — the arm's own verdict (§7) is that
	# the press ACQUIRES, which is the property that actually needed proving.
	if (not gated) and (not arm.has("press")) and not (_n_racqkey == 0):
		return (("arm %s: the horizon's keys must be ABSENT on the `none` rung (got %d frames) — a " +
				"cross-toggle must REMOVE them, not freeze a plausible set (the never-stale " +
				"discipline, 34/38)") % [tag, _n_racqkey])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var open_a: Dictionary = _res["open"]
	var button: Dictionary = _res["button"]

	# ⭐⭐ 1. THE SHOWCASE — ONE PRESS, AND THE NUMBER THAT MOVES IS NOT THE MISS.
	print(("S46V_PRESS  snr: lock %.3f s, auth_peak %.1f%%, miss %.4f   vs   none: lock %.3f s, " +
		   "auth_peak %.1f%%, miss %.4f") %
		  [open_a["tlock"], 100.0 * open_a["auth"], open_a["miss"],
		   button["tlock"], 100.0 * button["auth"], button["miss"]])
	if not (float(open_a["tlock"]) > 6.0):
		return _fail(("the authored wire must acquire LATE (%.3f s of an ~8.9 s flight) — the whole " +
					  "showcase is what a delayed acquisition costs") % open_a["tlock"])
	if not (float(button["tlock"]) < 0.10):
		return _fail(("with the horizon off the seeker must have the target from the first frames " +
					  "(%.3f s) — that is what an angle-only seeker means") % button["tlock"])
	if not (float(button["auth"]) < AUTH_FREE):
		return _fail(("with the horizon off the same missile must CRUISE (%.4f of a_max) — the " +
					  "contrast IS the price of the late lock") % button["auth"])
	# ⭐⭐ THE PRICE, AS A RATIO RATHER THAN A THRESHOLD. The default cell is not yet at the ceiling —
	# deliberately, so the slider teaches in BOTH directions — and what makes it the disease is that
	# it is already spending several times what the same missile needs with no horizon at all.
	if not (float(open_a["auth"]) > AUTH_RATIO * float(button["auth"])):
		return _fail(("the authored wire must spend at least %.0f× the free arm's authority (%.4f vs " +
					  "%.4f of a_max) — this is the column slice 44 did not read, and the reason this " +
					  "component was killed once already") %
					 [AUTH_RATIO, open_a["auth"], button["auth"]])
	# ⭐⭐⭐ AND THE HEADLINE METRIC IS BLIND TO ALL OF IT. Both arms HIT, within a metre of each other
	# in the core (0.9874 vs 0.2237) — a 7.6× swing in what the airframe is spending, hidden behind a
	# miss column that moves by less than the width of the target.
	if not (absf(float(open_a["miss"]) - float(button["miss"])) < HIT_MAX):
		return _fail(("both arms must HIT and land within %.1f m of each other (%.4f vs %.4f) — the " +
					  "point is that the headline metric CANNOT SEE a 7.6× swing in authority. If " +
					  "this ever separates, re-read the wire before re-reading the lesson") %
					 [HIT_MAX, open_a["miss"], button["miss"]])
	print("S46V_MISS   both arms hit (%.4f vs %.4f) while the authority differs %.1f× — the headline metric is BLIND" %
		  [open_a["miss"], button["miss"], float(open_a["auth"]) / maxf(float(button["auth"]), 1.0e-9)])

	# ⭐ 2. DETERMINISM — same seed, same slider, same rung ⇒ the same missile to the last bit.
	for pair in [["open", "replay"], ["button", "button_rep"]]:
		var d: float = _max_pos_diff(_res[pair[0]]["pos"], _res[pair[1]]["pos"])
		print("S46V_REPLAY %-10s max|Δpos| = %.12f m over %d frames" %
			  [pair[0], d, _res[pair[0]]["pos"].size()])
		if not (d <= EXACT):
			return _fail("replay of %s differs by %.12f m — determinism is the master check" % [pair[0], d])

	# ⭐⭐ 3. THE LADDER — the σ^¼ law, the monotone lock, and the authority walking to the ceiling.
	var ladder := ["r1000000", "r100000", "r10000", "r500", "r100"]
	print("S46V_LADDER   rcs        R_acq      R·σ^-¼      lock      auth      hold      miss")
	var prev_t := -1.0
	var prev_auth := -1.0
	for tg in ladder:
		var a: Dictionary = _res[tg]
		var inv: float = float(a["racq"]) / pow(float(a["rcs"]), 0.25)
		print("S46V_LADDER %10.6f %10.1f %11.4f %9.3f %8.1f%% %8.2f%% %9.4f" %
			  [a["rcs"], a["racq"], inv, a["tlock"], 100.0 * float(a["auth"]), a["hold"], a["miss"]])
		if absf(inv - R0_AT_1M2) > RACQ_RTOL * R0_AT_1M2:
			return _fail(("the horizon must go as the FOURTH ROOT of the target (R·σ^-¼ = %.4f, " +
						  "expected %.4f) — 16× the target buys 2× the range, which is why reach is " +
						  "bought with aperture and integration rather than with a bigger target") %
						 [inv, R0_AT_1M2])
		if not (float(a["tlock"]) > prev_t):
			return _fail(("the lock instant must rise MONOTONICALLY as the target shrinks (%.3f s at " +
						  "rcs %.6f, after %.3f s) — a non-monotone axis is not a lesson") %
						 [a["tlock"], a["rcs"], prev_t])
		prev_t = float(a["tlock"])
		if float(a["auth"]) + 1.0e-9 < prev_auth:
			return _fail(("the authority spent must not FALL as the lock gets later (%.4f after %.4f " +
						  "at rcs %.6f)") % [a["auth"], prev_auth, a["rcs"]])
		prev_auth = maxf(prev_auth, float(a["auth"]))
	# ⭐⭐⭐ AND THE MISS IS **NON-MONOTONE** ALONG THAT SAME LADDER — asserted, not merely observed.
	# The lock instant rises strictly and the authority rises strictly; the miss wanders. A slider
	# judged on the headline metric would read as noise, which is the strongest available statement
	# of why this slice's HUD and this file's assertions are built on the authority gauge.
	var misses: Array = []
	for tg in ["r1000000", "r100000", "r10000"]:
		misses.append(float(_res[tg]["miss"]))
	misses.append(float(open_a["miss"]))
	var ups := 0
	var downs := 0
	for i in range(1, misses.size()):
		if misses[i] > misses[i - 1]:
			ups += 1
		elif misses[i] < misses[i - 1]:
			downs += 1
	print("S46V_NOISE  miss along the ladder: %s  (%d up, %d down)" % [str(misses), ups, downs])
	if not (ups > 0 and downs > 0):
		return _fail(("the miss must be NON-MONOTONE along a ladder whose lock instant rises strictly " +
					  "(%s) — this file asserts that the headline metric carries no signal here, and " +
					  "a monotone miss would mean it does") % str(misses))

	# ⭐⭐ 4. THE TOP OF THE SLIDER IS WHERE THE COMPONENT STOPS EXISTING — and that null SHIPS.
	var top: Dictionary = _res["r1000000"]
	print("S46V_NULL   rcs 1.0 m²: horizon %.1f m against a %.1f m launch (ratio %.3f) — lock at %.3f s" %
		  [top["racq"], LAUNCH_R, float(top["racq"]) / LAUNCH_R, top["tlock"]])
	if not (float(top["racq"]) > LAUNCH_R):
		return _fail(("at the top of the slider the horizon (%.1f m) must lie OUTSIDE the engagement " +
					  "(%.1f m) — a detection gate can only price a design variable when the missile " +
					  "is launched outside its own seeker's horizon, which is a property of the WIRE") %
					 [top["racq"], LAUNCH_R])
	if not (float(top["tlock"]) < 0.10 and float(top["blind"]) == 0):
		return _fail(("at the top of the slider the gate must be INERT (lock %.3f s, %d blind frames) " +
					  "— that inertness is slice 44's kill, shipped as the right-hand end of a slider " +
					  "instead of as a reason not to build") % [top["tlock"], top["blind"]])

	# ⭐ 5. THE FLOOR — a VERDICT, never metres. Slice 44 §VII.3 measured failure magnitudes walking
	# 320 → 627 m across a 4× range of `dt` while the verdict held: once the track is gone the miss is
	# sampling a divergence rather than measuring one.
	var floor_a: Dictionary = _res["r100"]
	print("S46V_FLOOR  rcs %.6f: hold %.2f%% (blind %d frames) — the track is LOST, and the metres are not quoted" %
		  [floor_a["rcs"], floor_a["hold"], floor_a["blind"]])
	if not (float(floor_a["hold"]) < HOLD_BROKEN):
		return _fail(("the bottom of the slider must LOSE the track (hold %.2f %%) — the slider must " +
					  "reach a failure or its lower half is decoration") % floor_a["hold"])
	if not (float(floor_a["auth"]) >= AUTH_SPENT):
		return _fail(("the broken arm must have spent the whole budget first (%.4f) — the failure " +
					  "here is the AUTHORITY running out and the track loss FOLLOWING it, not a " +
					  "seeker that simply stopped seeing") % floor_a["auth"])

	# ⭐ 6. THE ARMS THAT HOLD MUST HIT — the sanity bound, and it is not the lesson.
	for tg in ["open", "button", "r1000000", "r100000", "r10000"]:
		var a: Dictionary = _res[tg]
		if not (float(a["hold"]) > HOLD_OK):
			return _fail("arm %s must hold its track (hold %.2f %%)" % [tg, a["hold"]])
		if not (float(a["miss"]) < HIT_MAX):
			return _fail(("arm %s must HIT (%.4f m) — every arm above the floor does, which is exactly " +
						  "why the miss cannot be this slice's metric") % [tg, a["miss"]])

	# ⭐ 7. THE MID-RUN PRESS — the horizon turned off at 3.2 s, BEFORE the 5.95 s lock. The seeker
	# must acquire essentially at once: the availability verdict is re-formed every tick, and the
	# target has been inside the WINDOW the whole time.
	var mp: Dictionary = _res["midpress"]
	print("S46V_MIDPRESS press at %.3f s -> lock at %.3f s (the open arm locks at %.3f s)" %
		  [PRESS_AT * _dt, mp["tlock"], open_a["tlock"]])
	if not (float(mp["tlock"]) >= PRESS_AT * _dt - 0.05 and float(mp["tlock"]) <= PRESS_AT * _dt + 0.05):
		return _fail(("the mid-run press must acquire within a frame or two of itself (press %.3f s, " +
					  "lock %.3f s) — the target was inside the window the whole time and only the " +
					  "RANGE half was refusing it") % [PRESS_AT * _dt, mp["tlock"]])

	# ⭐ 8. THE APERTURE IDENTITY, as the one number that makes coverage and reach one variable.
	print("S46V_APERTURE window %.1f° ⇒ %.4f m of dish ⇒ R_acq·fov = %.4f m·deg" %
		  [open_a["win"], open_a["ap"], float(top["racq"]) * float(open_a["win"])])
	if absf(float(top["racq"]) * float(open_a["win"]) - R_FOV_CONST) > 1.0e-3 * R_FOV_CONST:
		return _fail(("R_acq·fov must be the design's constant %.4f (got %.4f) — buy 2× the window " +
					  "and you have sold half the range, exactly") %
					 [R_FOV_CONST, float(top["racq"]) * float(open_a["win"])])

	print("S46V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice46_horizon":
		return "wrong scenario '%s' — run scenarios/slice46_horizon.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER, AND IT DOES BOTH JOBS. Without `seeker_detect_view` this wire raises neither
	# `radome_view` (no glass) nor `seeker_fov_view` (the loader refuses a body-fixed window beside a
	# head), so BOTH of the client's drop branches fail, the dispatch falls through to slice 25's
	# `seeker_axes` cycler, and the shared button comes back as the WRONG rung. And the HUD would be
	# slice 35's, whose demand-vs-cap pair reads against a servo authored at 30 °/s precisely so it
	# never binds: every number true, the verdict "servo FREE", and the link budget never mentioned.
	if not bool(f.get("seeker_detect_view", false)):
		return ("a slice-46 handshake must ship seeker_detect_view=true — without it the button that " +
				"carries half the lesson is pointed at slice 25's rung and the HUD draws a " +
				"'servo FREE' verdict beside a seeker that is blind for the first 6 seconds")
	for k in ["gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-46 wire is a gimballed, rate-limited head plus a link budget, so it must " +
					"still raise %s — the superset relation is what makes the new marker a BRANCH " +
					"SELECTOR rather than a hole plug, and it is why it must be checked FIRST") % k
	# ⚠ AND THREE MARKERS MUST BE ABSENT, each for its own reason: no glass on this wire (a radome
	# would put slice 26's parasitic loop beside a lesson about detection), no body-fixed window
	# (refused beside a head), and no `head_servo`/`seeker_head` rung (they would point the shared
	# button at a different slice's fidelity — one button, one lesson, convention 9).
	for k in ["radome_view", "seeker_fov_view", "gimbal_servo_view", "gimbal_frame_view"]:
		if bool(f.get(k, false)):
			return ("a slice-46 wire must NOT raise %s — it would either put a second mechanism beside " +
					"this lesson or point the shared button at another slice's rung") % k
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "rcs_m2":
		return ("exactly ONE knob, the TARGET's `rcs_m2` (convention 9). The seven `detect_*` keys are " +
				"the SEEKER and are authored; `gimbal_fov_deg` is disqualified because it moves the " +
				"window and the horizon in OPPOSITE directions; `gimbal_rate_dps` is the measured " +
				"isolation and a slider on it would put slice 35's limit back inside this lesson")
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _n_post = 0; _n_held = 0; _t_valid = -1.0; _r_valid = 0.0
	_auth_peak = 0.0; _n_sat = 0; _n_blind = 0
	_racq_seen = 0.0; _marg_seen = 1.0e30; _ap_seen = 0.0
	_win_seen = 0.0; _stop_seen = 0.0; _rate_seen = 0.0
	_n_authkey = 0; _n_racqkey = 0
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
	if tel.has(MID + ".a_cmd_frac"):
		_n_authkey += 1
	if tel.has(MID + ".seeker_r_acq_m"):
		_n_racqkey += 1
		_racq_seen = float(tel[MID + ".seeker_r_acq_m"])
		_ap_seen = float(tel.get(MID + ".seeker_aperture_m", _ap_seen))
		_marg_seen = minf(_marg_seen, float(tel.get(MID + ".seeker_range_margin_m", 1.0e30)))
		if float(tel.get(MID + ".seeker_detect", 1.0)) < 0.5:
			_n_blind += 1
	if los > 200.0:
		_n_gate += 1
		var avail := float(tel.get(MID + ".gimbal_valid", 1.0)) >= 0.5
		# ⭐ THE ACQUISITION INSTANT, frame-sampled: the first gated frame on which the seeker has its
		# target at all. `gimbal_valid` is the CONJUNCTION of the two gates, which is the right one
		# here — on this wire the handover is perfect and the ANGLE half never breaks, so every flip
		# of it belongs to the RANGE half (asserted per-arm by `blind_frames` on the null).
		if avail and _t_valid < 0.0:
			_t_valid = t
			_r_valid = los
		if _t_valid >= 0.0:
			_n_post += 1
			if avail:
				_n_held += 1
			# ⚠ THE PEAK IS TAKEN AFTER THE LOCK ONLY, and that is slice 44 §VII.1's own definition:
			# before the tracker initialises there is no guidance command to meter, and the r → 0
			# endgame is excluded by the 200 m gate ([[ewsim-missile-verifier-sampling]]).
			_auth_peak = maxf(_auth_peak, float(tel.get(MID + ".a_cmd_frac", 0.0)))
		if float(tel.get(MID + ".head_rate_sat", 0.0)) >= 0.5:
			_n_sat += 1

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

# ⚠ THE FIELD IS `target`, NOT `entity` — slice 40's own first-run bug, and slice 19's
# NOT-A-DEAD-KNOB TRIPWIRE is what catches it: without the read-back the ladder would be a flat line
# of authored arms. Here the read-back is the HORIZON, which proves the value reached the physics.
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
	push_error("S46V FAIL: " + msg)
	print("S46V FAIL: ", msg)
	quit(code)
	return true
