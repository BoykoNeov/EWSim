extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-40 gate-3 verifier — A HEAVIER GIMBAL: THE SECOND-ORDER HEAD SERVO.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice40_resonance.yaml
#   godot --headless --path clients/godot --script res://net/slice40_verify.gd     (exit 0 = pass)
#
# THE LESSON. Slices 34-39's head is a FIRST-ORDER LAG with a rate limit — one number, and a servo
# that moves a fraction of its error every tick. A real gimbal has INERTIA, so its servo is
# SECOND-ORDER, and that is not a refinement: a first-order lag is BOUNDED IN BOTH CURRENCIES (its
# index gain can never exceed 1 and its phase can never pass -90 deg, at every frequency, for every
# tau), so it could only ever make the radome's index QUIETER — which is exactly how slice 37's
# margin was bought. A second-order servo leaves both bounds.
#
# ⭐⭐ THE SHOWCASE IS ONE BUTTON PRESS ON A DESIGN THAT WAS ALREADY GOOD (slice 37's shape). At the
# authored R̂ = -0.18 — slice 34's OWN shipped design — the first-order head flies QUIET. Give the
# SAME gimbal an inertia with light damping and the SAME missile, the SAME glass, the SAME seed and
# the SAME handover RINGS ~44x, and still HITS.
#
# ⭐⭐ AND THE SLIDER IS A SECOND, DIFFERENT CURE — not the other end of the button's axis (slice 38's
# shape inverted). Damp the SAME inertia (zeta -> 1.0) and it is quiet too. ⇒ INERTIA IS NOT THE
# ENEMY, UNDAMPED INERTIA IS.
#
# ⚠⚠ THE PAIR OF WIRES IS THE PAYLOAD AND ONLY HALF OF IT IS HERE. This wire's ringing servo has an
# INDEX GAIN OF ~3.07, above a STRAPDOWN seeker's 1.00; `scenarios/slice40_heavy.yaml` rings just as
# hard at ~0.095, a TENTH of the shipped lag's. NEITHER NUMBER, READ AT A FIXED FREQUENCY, ORDERS THE
# OUTCOME. This file flies wire A and asserts the gain it ships; wire B is `test_missile.jl`'s and
# `docs/plans/slice40.md`'s, because the two wires differ by an AUTHORED key (`gimbal_omega_hz`,
# disqualified as a slider by non-monotonicity) and are therefore NOT client-drivable from one run.
#
# ⚠⚠ THE SLIDER IS **INERT ON THE OTHER SIDE OF THE BUTTON**, ASSERTED AS BIT-IDENTITY. A first-order
# head has no natural frequency and no damping ratio, so on that rung every value of this slider
# flies the SAME missile. A live control that does nothing is the stale-readout class in a NEW form
# — not a stale number but a DEAD KNOB — which is why the HUD names the state and why this file
# measures it rather than describing it.
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
# ⚠ EVERY arm asserts it REACHED CPA rather than trusting this sizing.
const STEPS := 12800
const PRESS_AT := 6400            # the MID-RUN press tick — also a multiple of 16, same reason

const FIRST := "first_order"
const SECOND := "second_order"

# THE SLIDER — the gimbal's DAMPING RATIO, dimensionless. The DEFAULT is where it RINGS, because on
# the OTHER rung this slider is bit-identically inert and a wire opening there would hand the student
# a dead control.
const Z_DEF := 0.10
const Z_CURE := 1.00              # the same inertia, well damped — quiet, and the domain CEILING
const Z_FLOOR := 0.05             # below it slice 35's rate limit comes back even at 120 deg/s
const Z_015 := 0.15
const Z_020 := 0.20
const Z_030 := 0.30
const Z_050 := 0.50
const Z_EDGE := 0.7071            # ⭐ THE ANALYTIC EDGE: no peak above 1 at ANY frequency beyond it
const Z_085 := 0.85

# ⚠ THE RING LINE IS THE ARC's OWN 0.30 AND IT IS USED ONLY FOR PRINTED TAGS AND THE TWO-SIDED
# SHOWCASE ASSERT — the LADDER is judged by MONOTONICITY and RATIOS, never against a threshold
# (slice 37's threshold-free rule, inherited).
const RING := 0.30
const HIT_MAX := 40.0
const WIN_AUTH := 25.0            # the AUTHORED detector window (not a knob here)
const STOP_AUTH := 30.0           # the AUTHORED mechanical stop
const RATE_AUTH := 120.0          # the AUTHORED servo — slice 35's slider, held WIDE as an isolation
const WN_AUTH := 2.0              # the AUTHORED natural frequency — the WIRE, not the knob
const MODEL_VALID_DEG := 30.0     # the small-angle bend budget 28-39 each declared
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
var _pending_press := ""          # the mid-run arm's second leg (see `_process`)

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}

var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0                  # closing frames with r > 200 m
var _n_out := 0                   # …of which the head had NO error signal
var _max_head := 0.0              # the head's TRAVEL (vs the STOP)
var _max_off := 0.0               # the head's TRACKING ERROR (vs the WINDOW)
var _min_marg := 1.0e30
var _n_band := 0                  # closing frames with 500 < r < 3000 — the isolation window
var _n_sat := 0                   # …frames where slice 35's rate limit BOUND (the core's own flag)
var _n_defl := 0
var _n_aero := 0
var _sum_r2 := 0.0                # for rms r — the RING (yaw: the lead is in AZIMUTH here)
# ⭐ READ OFF THE WIRE, never trusted from the `set_param` that was sent — slice 19's
# not-a-dead-knob tripwire, and load-bearing here because this slice ships a key that is
# LEGITIMATELY inert on one rung: "it did nothing" must be distinguishable from "it never arrived".
var _z_seen := 0.0
var _wn_seen := 0.0
var _gain_seen := 0.0             # the shipped `head_index_gain`
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S40V_INIT godot=", Engine.get_version_info().string)
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
		_client.send({"type": "set_fidelity", "key": "head_servo", "value": rung})
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
	# 1) ⭐⭐ THE SHOWCASE — the wire as authored (RINGS), the BUTTON (quiet), and the SLIDER (quiet),
	#    each with its REPLAY. Class 4a: the seed is LOAD-BEARING, and a replay proven at only one
	#    slider value would leave the new servo's branch unproven exactly where it does its work.
	_arms.append({"tag": "open", "z": Z_DEF})
	_arms.append({"tag": "replay", "z": Z_DEF})
	_arms.append({"tag": "button", "z": Z_DEF, "rung": FIRST})
	_arms.append({"tag": "button_rep", "z": Z_DEF, "rung": FIRST})
	_arms.append({"tag": "cure", "z": Z_CURE})
	_arms.append({"tag": "cure_rep", "z": Z_CURE})
	# 2) ⭐ THE LADDER over the slider's whole domain. ⚠ These establish MONOTONICITY and the
	#    crossing of the analytic edge; nothing here compares an `rms r` to a threshold.
	for zv in [Z_FLOOR, Z_015, Z_020, Z_030, Z_050, Z_EDGE, Z_085]:
		_arms.append({"tag": "z%d" % int(round(10000.0 * zv)), "z": zv})
	# 3) ⭐⭐ THE SLIDER IS INERT ON THE OTHER SIDE OF THE BUTTON — asserted as BIT-IDENTITY. A
	#    first-order head has no natural frequency and no damping ratio, so these two arms must be the
	#    SAME MISSILE to the last bit.
	_arms.append({"tag": "inert_lo", "z": Z_FLOOR, "rung": FIRST})
	_arms.append({"tag": "inert_hi", "z": Z_CURE, "rung": FIRST})
	# 4) ⭐ THE PRESS ITSELF, MID-FLIGHT — the one thing gates 0-2 could not cover is a `set_fidelity`
	#    reaching the rung boundary at an arbitrary tick, with a rate state live in the head. It must
	#    quiet the ringing arm: a first-order lag cannot ring on this design at all.
	_arms.append({"tag": "midpress", "z": Z_DEF, "press": FIRST})


func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `second_order` and the slider to
	# its authored 0.10 every arm — each arm must re-send its own. That is what makes these arms the
	# CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", SECOND)) != SECOND:
		_client.send({"type": "set_fidelity", "key": "head_servo", "value": str(arm["rung"])})
	# ⚠ SENT ON EVERY ARM INCLUDING THE DEFAULT ONE, so the `open` arm proves the SLIDER's own path to
	# its authored value rather than merely inheriting it from the YAML.
	_client.send(_set_param_cmd(MID, "gimbal_zeta", float(arm["z"])))
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
	var out_pc: float = 100.0 * float(_n_out) / maxf(float(_n_gate), 1.0)
	# ⚠⚠ NaN, NOT 0.0, WHEN THE BAND IS EMPTY — slice 33's gate-2 finding, inherited: a `sum/max(n,1)`
	# would print a beautifully quiet `rms r = 0.00000` COMPUTED FROM ZERO SAMPLES.
	var rms := NAN if _n_band == 0 else sqrt(_sum_r2 / float(_n_band))
	var sat_pc := NAN if _n_band == 0 else 100.0 * float(_n_sat) / float(_n_band)
	var aero_pc := NAN if _n_band == 0 else 100.0 * float(_n_aero) / float(_n_band)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		"head": _max_head, "off": _max_off,
		"marg": NAN if _min_marg > 1.0e29 else _min_marg,
		"band": _n_band, "aero": aero_pc, "defl": _n_defl, "rms": rms, "sat": sat_pc,
		"z": _z_seen, "wn": _wn_seen, "gain": _gain_seen,
		"rung": str(arm.get("rung", SECOND)),
		"win": _win_seen, "stop": _stop_seen, "rate": _rate_seen,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	# ⭐ THE NOT-A-DEAD-KNOB TRIPWIRE (slice 19's, inherited and LOAD-BEARING here): the value the arm
	# FLEW is read back off the wire and compared against the one it SENT. This slice ships a key that
	# is LEGITIMATELY inert on one rung, so "it did nothing" has to be distinguishable from "it never
	# arrived" — and the readout is shipped on BOTH rungs precisely so this check works on both.
	if absf(_z_seen - float(arm["z"])) > EXACT:
		return ("arm %s: the wire flew gimbal_zeta = %+.6f but the arm sent %+.6f — the slider was " +
				"accepted and not applied") % [tag, _z_seen, float(arm["z"])]
	print(("S40V_ARM   %-10s %-13s zeta=%.4f wn=%.2f Hz gain=%.5f  ->  miss=%.3f  rms_r=%.5f  " +
		   "sat_band=%.2f%% (%d band frames)  off_max=%.3f  head_max=%.3f  margin_min=%.2f  " +
		   "out=%.3f%% of %d gated  aero=%.2f%%  defl=%d  cpa=%s") %
		  [tag, m["rung"], m["z"], m["wn"], m["gain"], m["miss"], m["rms"], m["sat"], m["band"],
		   m["off"], m["head"], m["marg"], out_pc, m["gate"], m["aero"], m["defl"],
		   "Y" if m["turned"] else "N"])
	if not (_n_gate > 100):
		return ("arm %s: the r > 200 m window must contain frames to measure (got %d)") % [tag, _n_gate]
	if not (_n_band > 100):
		return ("arm %s: the [500, 3000] m band must contain frames (got %d) — rms r and sat_band are " +
				"BOTH band quantities, and slice 33's gate-2 catch was exactly a band metric computed " +
				"from zero samples") % [tag, _n_band]
	if not _turned:
		return ("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing at " +
				"the end, so its miss (%.3f m) is a last closing range and not a CPA") % [tag, STEPS, _min_los]
	# ⚠⚠ THE DETECTOR WINDOW MUST NEVER BITE, ON ANY ARM — the load-bearing precondition of the whole
	# file rather than hygiene. `rms r`, `head_off_deg`, `head_angle_deg` and `head_rate_sat` are ALL
	# meaningless on a windowed arm (the two-run discipline): a broken window FREEZES the head's index,
	# a frozen index makes a CONSTANT bend, and a constant bend is QUIET AT EVERY R̂ — so the ring would
	# FALL and the servo would read FREE, both of which look like good news.
	if not (out_pc == 0.0):
		return ("arm %s: THE DETECTOR WINDOW MUST NEVER BITE (%.3f %% of gated frames out) — every " +
				"`rms r` in this file is a STABILITY read only while it does not") % [tag, out_pc]
	if not (_max_off < _win_seen):
		return (("arm %s: the whole-approach tracking error (%.3f deg) must stay inside the authored " +
				"window (%.3f deg) — the same claim as the line above measured as an ANGLE rather than " +
				"a count, so a single-frame excursion cannot hide in a rounded percentage") %
				[tag, _max_off, _win_seen])
	# ⚠⚠ THE MECHANICAL STOP MUST NOT BIND EITHER, AND ON THIS SLICE THAT IS NOT INHERITED HYGIENE —
	# IT IS THE KERNEL'S OWN SEAM DECISION STAYING OUT OF THE ANSWER. The second-order servo's stop is
	# INELASTIC (it zeroes the rate state), and a head winding up against a clamp produces an
	# oscillation that would FAKE this slice's resonance exactly. Gate 1 caught that arm for real on
	# the heavy wire (`head_max = 30.000` EXACTLY at slice 37's stop), which is why wire B authors 50.
	if not (_max_head < _stop_seen and _max_head < MODEL_VALID_DEG):
		return (("arm %s: the head's travel (%.3f deg) must stay inside BOTH the mechanical stop (%.3f " +
				"deg) and the small-angle bend budget 28-39 each declared (%.0f deg) — an INELASTIC " +
				"stop is a resonance generator, so a claimed arm may never reach it") %
				[tag, _max_head, _stop_seen, MODEL_VALID_DEG])
	# ⚠⚠ AND SLICE 35's RATE LIMIT MUST NEVER BIND, WHICH IS WHY THIS WIRE AUTHORS 120 deg/s. At slice
	# 37's 40 it binds 20-53 % of band ticks on the lightly damped arms AND ATTENUATES THE RING (0.656
	# against the free 0.800 at zeta = 0.05) — slice 35's own two-sided knob reappearing on a new
	# architecture. ⇒ the honest sentence is that the shipped servo was partly HIDING this.
	if not (sat_pc == 0.0):
		return (("arm %s: slice 35's rate limit bound on %.2f %% of band frames — this file would then " +
				"be measuring THAT knob. The servo is authored at %.0f deg/s precisely so it cannot") %
				[tag, sat_pc, RATE_AUTH])
	# ⚠ THE ISOLATION IS `defl_sat`, NOT `aero_sat` — slice 33's inversion, inherited with its warning:
	# a ringing arm drives the demand into slice 19's aero ceiling AND STILL HITS, so `aero_sat`
	# discriminates in NEITHER direction here.
	if not (_n_defl == 0):
		return ("arm %s: `defl_sat` must be EXACTLY 0 (got %d) — with the fin out of authority the " +
				"engagement stops being about the head at all") % [tag, _n_defl]
	# THE AUTHORED FOUR, ON EVERY ARM: nothing in this file touches them, and that is the point.
	# ⚠ `gimbal_omega_hz` IS IN THIS LIST DELIBERATELY — it is the WIRE, not the knob, disqualified as
	# a slider by NON-MONOTONICITY (slice 28's `k`, 4th occurrence), and an arm that moved it would be
	# comparing two different gimbals.
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH
			and _wn_seen == WN_AUTH):
		return (("arm %s: the window / stop / servo / natural frequency must be the AUTHORED %.1f / " +
				"%.1f / %.1f / %.1f (got %.3f / %.3f / %.3f / %.3f)") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, WN_AUTH, _win_seen, _stop_seen, _rate_seen, _wn_seen])
	if not (_min_los < HIT_MAX):
		return ("arm %s: every arm in this slider's domain HITS (%.3f m) — the miss is not the metric " +
				"here, as in every slice of this family since 26, and an arm that missed would mean " +
				"the wire had left the regime this file measures") % [tag, _min_los]
	return ""


# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var open_a: Dictionary = _res["open"]
	var button: Dictionary = _res["button"]
	var cure: Dictionary = _res["cure"]

	# ⭐⭐ 1. THE SHOWCASE — ONE PRESS ON A DESIGN THAT WAS ALREADY GOOD.
	var ratio: float = float(open_a["rms"]) / float(button["rms"])
	print("S40V_PRESS  second_order zeta=%.2f rms_r=%.5f   vs   first_order rms_r=%.5f   -> %.1fx" %
		  [Z_DEF, open_a["rms"], button["rms"], ratio])
	if not (float(open_a["rms"]) > RING):
		return _fail(("the wire as authored must RING (rms r %.5f, arc line %.2f) — the whole showcase " +
					  "is that an INERTIA rings a design the shipped lag flies quiet") %
					 [open_a["rms"], RING])
	if not (float(button["rms"]) < 0.1 * RING):
		return _fail(("the FIRST-ORDER rung must be QUIET (rms r %.5f) — a first-order lag's index gain " +
					  "is bounded by 1 and its phase by -90 deg at EVERY frequency, so it cannot ring " +
					  "on this design at all (measured across an 800x tau sweep at gate 0)") % button["rms"])
	if not (ratio > 30.0):
		return _fail("the press must be dramatic (%.1fx) — measured 44x at gate 0/2" % ratio)

	# ⭐⭐ 2. THE SECOND CURE — THE SLIDER, on the SAME architecture. Two cures, one control each.
	print("S40V_CURE   zeta %.2f -> %.2f  rms_r %.5f -> %.5f  (%.1fx)  |  first_order %.5f" %
		  [Z_DEF, Z_CURE, open_a["rms"], cure["rms"], float(open_a["rms"]) / float(cure["rms"]),
		   button["rms"]])
	if not (float(cure["rms"]) < 0.1 * RING):
		return _fail(("damping the SAME inertia must quiet it (rms r %.5f) — INERTIA IS NOT THE ENEMY, " +
					  "UNDAMPED INERTIA IS") % cure["rms"])
	# ⚠ AND THE TWO CURES MUST ARRIVE AT THE SAME PLACE WITHOUT BEING THE SAME THING: the damped
	# second-order servo is NOT the first-order lag (it is a different architecture, and gate 0
	# measured the collapse to be CLOSE and never identical — ratios 1.005-1.06 against a matched lag).
	if not (absf(float(cure["rms"]) - float(button["rms"])) / float(button["rms"]) < 0.5):
		return _fail(("the damped servo and the lag must land in the same quiet plateau (%.5f vs %.5f)") %
					 [cure["rms"], button["rms"]])
	if float(cure["rms"]) == float(button["rms"]):
		return _fail("…but they must NOT be identical — a second-order servo that exactly reproduced " +
					 "the lag would be the reparameterization slice 39 was killed for")

	# ⭐ 3. THE LADDER — MONOTONE, and judged by ratios rather than against a threshold.
	var lad := [_res["z500"], _res["open"], _res["z1500"], _res["z2000"], _res["z3000"],
				_res["z5000"], _res["z7071"], _res["z8500"], _res["cure"]]
	var zs := [Z_FLOOR, Z_DEF, Z_015, Z_020, Z_030, Z_050, Z_EDGE, Z_085, Z_CURE]
	var line := ""
	for i in range(lad.size()):
		line += "%.4f:%.5f(g %.3f)  " % [zs[i], lad[i]["rms"], lad[i]["gain"]]
	print("S40V_LADDER ", line)
	for i in range(lad.size() - 1):
		if not (float(lad[i]["rms"]) > float(lad[i + 1]["rms"])):
			return _fail(("the zeta ladder must be MONOTONE — cell %.4f (%.5f) is not above cell %.4f " +
						  "(%.5f). A non-monotone slider is disqualified in this arc (slice 28's `k`), " +
						  "and monotonicity is the measured reason zeta is the knob and omega_n is the " +
						  "wire") % [zs[i], lad[i]["rms"], zs[i + 1], lad[i + 1]["rms"]])
	if not (float(lad[0]["rms"]) / float(lad[-1]["rms"]) > 30.0):
		return _fail("the slider must span its domain (%.1fx)" % (float(lad[0]["rms"]) / float(lad[-1]["rms"])))

	# ⭐⭐ 4. THE ANALYTIC EDGE, MEASURED ON THE WIRE. zeta = 1/sqrt(2) is where the closed-loop response
	# stops having a peak above 1 at ANY frequency — a domain landmark DERIVED before it was measured.
	# The core ships `head_index_gain`, and it must cross 1.0 across that edge. ⚠ THE ASSERT IS THE
	# CROSSING, NOT THE VALUE: re-deriving the closed form here would make this file prove a SECOND
	# implementation and nothing about what flies (the trap `frames.jl` names for `off_axis_angle`).
	print("S40V_EDGE   index gain at zeta %.4f = %.5f   at zeta %.4f = %.5f   (the 1/sqrt(2) edge)" %
		  [Z_050, _res["z5000"]["gain"], Z_EDGE, _res["z7071"]["gain"]])
	if not (float(_res["z5000"]["gain"]) > 1.0 and float(_res["z7071"]["gain"]) < 1.0):
		return _fail(("the shipped index gain must cross 1.0 across the analytic edge zeta = 1/sqrt(2) " +
					  "(got %.5f at %.3f and %.5f at %.4f). Above 1 is WORSE THAN A STRAPDOWN SEEKER, " +
					  "which is what a first-order lag can never be") %
					 [_res["z5000"]["gain"], Z_050, _res["z7071"]["gain"], Z_EDGE])
	# ⚠⚠ AND THE GAIN MUST NOT BE READ AS THE VERDICT — this file can only show half of that, because
	# the other half is wire B (index gain 0.095, ringing just as hard). What it CAN assert is that the
	# ringing arm here sits ABOVE the strapdown seeker's 1.00 while the shipped lag sits below it.
	if not (float(open_a["gain"]) > 1.0):
		return _fail("the ringing arm's index gain (%.5f) must exceed a strapdown seeker's 1.00 — on " +
					 "THIS wire the resonance is the amplifying kind" % open_a["gain"])

	# ⭐⭐ 5. THE SLIDER IS INERT ON THE OTHER RUNG — BIT-IDENTITY, not a description.
	var d_inert := _max_pos_diff(_res["inert_lo"]["pos"], _res["inert_hi"]["pos"])
	print("S40V_INERT  first_order, zeta %.2f vs %.2f: max|dpos| = %.9f m over %d frames" %
		  [Z_FLOOR, Z_CURE, d_inert, _res["inert_lo"]["pos"].size()])
	if not (d_inert == 0.0):
		return _fail(("a FIRST-ORDER head has no natural frequency and no damping ratio, so the slider " +
					  "must be BIT-IDENTICALLY inert there (max|dpos| = %.9f m). A live control that " +
					  "does nothing is the stale-readout class in a new form, which is why the HUD " +
					  "names the state — and why this is measured rather than described") % d_inert)
	# …paired with the DOES-DIFFER case, or the assert above proves only that nothing ran.
	var d_live := _max_pos_diff(_res["open"]["pos"], _res["cure"]["pos"])
	if not (d_live > 1.0):
		return _fail("…and on the SECOND-ORDER rung the same two slider values must fly different " +
					 "missiles (max|dpos| = %.9f m)" % d_live)

	# ⭐ 6. REPLAY — bit-identical at BOTH ends of the slider and on BOTH rungs (class 4a, seed
	# load-bearing). A replay proven at one slider value would leave the new branch unproven where it
	# does its work.
	for pair in [["open", "replay"], ["button", "button_rep"], ["cure", "cure_rep"]]:
		var d := _max_pos_diff(_res[pair[0]]["pos"], _res[pair[1]]["pos"])
		print("S40V_REPLAY %-11s max|dpos| = %.9f m" % [pair[0], d])
		if not (d == 0.0):
			return _fail("arm %s must replay BIT-IDENTICALLY (max|dpos| = %.9f m)" % [pair[0], d])

	# ⭐ 7. THE MID-RUN PRESS — a `set_fidelity` reaching the rung boundary at an arbitrary tick, with
	# a rate state live in the head. ⚠ It must quiet the arm, but NOT to the from-launch value: half
	# the flight was flown ringing, so the band statistic carries it.
	var mp: Dictionary = _res["midpress"]
	print("S40V_MID    pressed at tick %d: rms_r=%.5f  (from-launch ring %.5f, from-launch lag %.5f)" %
		  [PRESS_AT, mp["rms"], open_a["rms"], button["rms"]])
	if not (float(mp["rms"]) < float(open_a["rms"])):
		return _fail("the mid-run press must QUIET the ringing arm (%.5f vs %.5f)" % [mp["rms"], open_a["rms"]])

	print(("S40V OK  — a HEAVIER GIMBAL: an INERTIA rings a design the shipped LAG flies quiet " +
		  "(%.5f vs %.5f, %.1fx), and TWO cures reach the same quiet from opposite sides (the BUTTON " +
		  "back to the lag, the SLIDER damping the same inertia to %.5f). The index gain crosses 1.0 " +
		  "at the analytic edge zeta = 1/sqrt(2), and the ringing arm sits ABOVE a strapdown seeker's " +
		  "1.00 — which a first-order lag can never do. On the lag rung the slider is BIT-IDENTICALLY " +
		  "inert. Every arm: window clear, rate limit free, stop clear, defl_sat 0, CPA reached.") %
		  [open_a["rms"], button["rms"], ratio, cure["rms"]])
	quit(0)
	return true


# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice40_resonance":
		return "wrong scenario '%s' — run scenarios/slice40_resonance.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER, AND IT DOES BOTH JOBS. Without `gimbal_servo_view` the client's dispatch hides
	# the shared button three times over (this wire raises `radome_view`, `gimbal_view` AND
	# `gimbal_rate_view`) — and the button IS the lesson here. And the HUD would be slice 35's, whose
	# demand-vs-cap pair reads against a rate limit authored WIDE precisely so it never binds: every
	# number true, the verdict "servo FREE", and the INERTIA ringing the missile never mentioned.
	if not bool(f.get("gimbal_servo_view", false)):
		return ("a slice-40 handshake must ship gimbal_servo_view=true — without it the button that " +
				"carries the lesson is hidden by three other markers, and slice 35's HUD draws a " +
				"'servo FREE' verdict beside a missile shaking itself")
	for k in ["radome_view", "gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-40 wire is a slice-35 wire plus a rung, so it must still raise %s — the " +
					"superset relation is what makes the marker a BRANCH SELECTOR rather than a hole " +
					"plug, and it is why the new branch must be checked FIRST") % k
	# ⚠ AND `gimbal_frame_view` MUST BE ABSENT: the scenario deliberately does NOT author
	# `seeker_head`, because raising slice 37's marker would point the shared button at the head's
	# FRAME instead of its ORDER. One button, one lesson (convention 9).
	if bool(f.get("gimbal_frame_view", false)):
		return ("a slice-40 wire must NOT raise gimbal_frame_view — it would point the shared button " +
				"at `seeker_head` (the servo's FRAME) instead of `head_servo` (its ORDER), which is a " +
				"different slice's rung on this slice's wire")
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "gimbal_zeta":
		return ("exactly ONE knob, `gimbal_zeta` (convention 9). `gimbal_omega_hz` is AUTHORED and " +
				"disqualified as a slider by NON-MONOTONICITY — it is the WIRE (2.0 Hz here, 0.5 Hz " +
				"on slice40_heavy), and the contrast between the two files is the payload")
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _n_out = 0; _max_head = 0.0; _max_off = 0.0; _min_marg = 1.0e30
	_n_band = 0; _n_sat = 0; _n_defl = 0; _n_aero = 0; _sum_r2 = 0.0
	_z_seen = 0.0; _wn_seen = 0.0; _gain_seen = 0.0
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
	_z_seen = float(tel.get(MID + ".gimbal_zeta", _z_seen))
	_wn_seen = float(tel.get(MID + ".gimbal_omega_hz", _wn_seen))
	_gain_seen = float(tel.get(MID + ".head_index_gain", _gain_seen))
	_win_seen = float(tel.get(MID + ".gimbal_fov_deg", _win_seen))
	_stop_seen = float(tel.get(MID + ".gimbal_stop_deg", _stop_seen))
	_rate_seen = float(tel.get(MID + ".gimbal_rate_dps", _rate_seen))
	if los > 200.0:
		_n_gate += 1
		if float(tel.get(MID + ".gimbal_valid", 1.0)) < 0.5:
			_n_out += 1
		_max_head = maxf(_max_head, float(tel.get(MID + ".head_angle_deg", 0.0)))
		_max_off = maxf(_max_off, float(tel.get(MID + ".head_off_deg", 0.0)))
		_min_marg = minf(_min_marg, float(tel.get(MID + ".gimbal_fov_margin_deg", 1.0e30)))
	if los >= 500.0 and los <= 3000.0:
		_n_band += 1
		var wr := float(tel.get(MID + ".omega_r", 0.0))
		_sum_r2 += wr * wr
		if float(tel.get(MID + ".head_rate_sat", 0.0)) >= 0.5:
			_n_sat += 1
		if float(tel.get(MID + ".defl_sat", 0.0)) >= 0.5:
			_n_defl += 1
		if float(tel.get(MID + ".aero_sat", 0.0)) >= 0.5:
			_n_aero += 1

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

# ⚠ THE FIELD IS `target`, NOT `entity` — and the first run of this file had it wrong, which is
# exactly what slice 19's NOT-A-DEAD-KNOB TRIPWIRE exists to catch: the server ignored every
# `set_param` silently, and the first two arms passed anyway because they happened to request the
# AUTHORED value. Without the read-back the ladder would have been a flat line of authored arms.
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
	push_error("S40V FAIL: " + msg)
	print("S40V FAIL: ", msg)
	quit(code)
	return true
